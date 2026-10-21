"""app.qml_backend.vm.deno_vm - YouTube Hunter (QML).

Backs the "install deno" dialog.

yt-dlp needs a JavaScript runtime (deno) to solve YouTube's download challenge —
see app.core.deno for the why. This VM downloads deno on a worker thread and
reports live progress to a QML dialog, mirroring the worker-thread → queued Qt
signal pattern the other download VMs use.
"""

import sys
import threading

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.core import deno
from app.core import pot
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.desktop_notifier import announce


def _size_text(n):
    """Bytes as a short human string, or "" when unknown. Same helper the other
    progress VMs use, kept local so this module stands alone."""
    if not n or n <= 0:
        return ""
    units = ("B", "KB", "MB", "GB")
    v = float(n)
    i = 0
    while v >= 1024 and i < len(units) - 1:
        v /= 1024
        i += 1
    return (f"{round(v)} {units[i]}" if (v >= 100 or i == 0)
            else f"{v:.1f} {units[i]}")


class DenoVM(QObject):
    """Download + install state for the deno JS runtime."""

    changed = Signal()
    # A download-point gate (quality picker / resume) asked for the installer —
    # Main.qml opens the dialog in response, so the three call sites don't each
    # need a handle to it.
    installRequested = Signal()
    finished = Signal(bool)            # download ended (ok / not)
    toast = Signal(str, str)           # (message, kind) → notification tray

    _progress = Signal(int, int)       # worker → GUI (done_bytes, total_bytes)
    _finished = Signal(bool, str)      # worker → GUI (ok, error)
    _updateDone = Signal(bool, str)    # worker → GUI (ok, version_or_error)
    _stage = Signal(str)               # worker → GUI (which mirror is being tried)
    _potProgress = Signal(int, int)    # worker → GUI (done_bytes, total_bytes)
    _potDone = Signal(bool, str)       # worker → GUI (ok, error)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._available = deno.deno_available()
        self._busy = False
        self._done = 0
        self._total = 0
        self._cancel = False
        self._updating = False
        # The last failure, shown INSIDE the dialog. It used to go only to the
        # notification tray, so a failed install looked like the dialog had
        # blinked and reset itself — the "it flashes and asks again" report.
        self._error = ""
        self._source = ""
        # js_runtime_status() runs `<runtime> --version` in a subprocess; the
        # three runtime* properties used to call it on EVERY `changed` emit
        # (each download progress tick) on the GUI thread. Cache it.
        self._status_cache = None
        # PO Token helper (bgutil-pot) — REQUIRED since v3.41.5, see app.core.pot
        self._pot_busy = False
        self._pot_pct = 0
        self._pot_cancel = False
        self._pot_status = pot.status()
        self._pot_error = ""
        # installAll(): deno first, then the PO Token helper, as one setup.
        self._chain = False
        self._potProgress.connect(self._on_pot_progress)
        self._potDone.connect(self._on_pot_done)
        self._progress.connect(self._on_progress)
        self._stage.connect(self._on_stage)
        self._finished.connect(self._on_finished)
        self._updateDone.connect(self._on_update_done)

    # ── read-only state ──────────────────────────────────────────────────
    @Property(bool, notify=changed)
    def available(self):
        return self._available

    # v3.41.5: the download engine is READY only when every required part is
    # present: the JS runtime AND the PO Token helper. Every download gate
    # checks this, not `available`.
    @Property(bool, notify=changed)
    def ready(self):
        return self._available and bool(self._pot_status.get("installed"))

    @Property(bool, notify=changed)
    def setupBusy(self):
        return self._busy or self._pot_busy

    @Property(str, notify=changed)
    def setupError(self):
        return self._error or self._pot_error

    @Property(bool, notify=changed)
    def busy(self):
        return self._busy

    @Property(int, notify=changed)
    def pct(self):
        if self._total <= 0:
            return 0
        return max(0, min(100, int(self._done * 100 / self._total)))

    @Property(str, notify=changed)
    def doneText(self):
        return _size_text(self._done)

    @Property(str, notify=changed)
    def totalText(self):
        return _size_text(self._total)

    @Property(str, notify=changed)
    def error(self):
        return self._error

    @Property(str, notify=changed)
    def source(self):
        """The mirror currently being downloaded from (shown while busy)."""
        return self._source

    @Property(str, notify=changed)
    def installDir(self):
        return deno.deno_dir()

    @Property(str, notify=changed)
    def statusText(self):
        if self._available and not self._busy:
            return tr("Ready.")
        if self._busy:
            done = _size_text(self._done)
            total = _size_text(self._total)
            if total:
                return tr("{done} of {total} · {pct}%").format(
                    done=done, total=total, pct=self.pct)
            return tr("Downloading… {done}").format(done=done)
        return ""

    # ── required-files summary (for the startup/first-download dialog) ───
    # The YouTube download engine needs exactly one downloadable component:
    # the deno JS runtime (~40 MB). ffmpeg/ffprobe ship inside the install and
    # yt-dlp's solver script ships inside yt_dlp_ejs, so there is nothing else
    # to fetch. Exposed as file counts (not hardcoded in QML) so the dialog can
    # show "file X of Y" next to the byte progress.
    @Property(str, notify=changed)
    def fileName(self):
        return "deno.exe"

    @Property(str, notify=changed)
    def potFileName(self):
        return "bgutil-pot.exe" if sys.platform == "win32" else "bgutil-pot"

    @Property(int, notify=changed)
    def filesTotal(self):
        return 2

    # ── actions ──────────────────────────────────────────────────────────
    @Slot()
    def requestInstall(self):
        """A download point found deno missing — ask the UI to open the dialog.

        If everything turns out to already be present (a user installed it out
        of band), re-check and stay silent rather than opening a needless dialog.
        v3.41.5: "everything" includes the required PO Token helper."""
        self._available = deno.deno_available()
        self._status_cache = None
        self._pot_status = pot.status()
        self.changed.emit()
        if self.ready:
            return
        self.installRequested.emit()

    @Slot()
    def installAll(self):
        """Install every missing required component: deno, then bgutil-pot."""
        if self._busy or self._pot_busy:
            return
        self._error = ""
        self._pot_error = ""
        self._available = deno.deno_available()
        self._pot_status = pot.status()
        if not self._available:
            self._chain = True
            self.download()
        elif not self._pot_status.get("installed"):
            self._chain = False
            self.installPot()
        else:
            self.changed.emit()
            self.finished.emit(True)

    @Slot()
    def forceInstall(self):
        """Open the installer dialog even when a managed runtime already exists —
        the Settings "Reinstall" button wants this (requestInstall() stays silent
        when a runtime is present so a download point never nags needlessly)."""
        self.installRequested.emit()

    @Slot()
    def download(self):
        """Download and install deno on a worker thread."""
        if self._busy:
            return
        self._busy = True
        self._cancel = False
        self._done = 0
        self._total = 0
        self._error = ""
        self._source = ""
        self.changed.emit()

        def worker():
            try:
                ok, err = deno.download_deno(
                    on_progress=lambda d, t: self._progress.emit(d, t),
                    should_cancel=lambda: self._cancel,
                    on_status=lambda t: self._stage.emit(t))
            except Exception as exc:      # noqa: BLE001 — reported, not raised
                log_crash("DenoVM.download failed: " + str(exc))
                ok, err = False, str(exc)
            self._finished.emit(ok, err)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str)
    def installFromFile(self, url):
        """Offline install: the user points at a deno.exe or the official
        deno-*.zip they downloaded some other way (another PC, a mirror)."""
        if self._busy:
            return
        from app.core.utils import local_path_from_url
        path = local_path_from_url(url)
        self._busy = True
        self._error = ""
        self._source = tr("your file")
        self._done = self._total = 0
        self.changed.emit()

        def worker():
            try:
                ok, err = deno.install_from_file(path)
            except Exception as exc:      # noqa: BLE001
                log_crash("DenoVM.installFromFile failed: " + str(exc))
                ok, err = False, str(exc)
            self._finished.emit(ok, err)

        threading.Thread(target=worker, daemon=True).start()

    @Slot()
    def openInstallDir(self):
        import os
        from PySide6.QtCore import QUrl
        from PySide6.QtGui import QDesktopServices
        try:
            os.makedirs(deno.deno_dir(), exist_ok=True)
        except OSError:
            pass
        QDesktopServices.openUrl(QUrl.fromLocalFile(deno.deno_dir()))

    @Slot()
    def clearError(self):
        if self._error or self._pot_error:
            self._error = ""
            self._pot_error = ""
            self.changed.emit()

    @Slot()
    def cancel(self):
        """Abort an in-flight download — the worker sees the flag between
        chunks and unwinds. Cancels the whole setup chain."""
        self._chain = False
        if self._busy:
            self._cancel = True
        if self._pot_busy:
            self._pot_cancel = True

    @Slot()
    def refresh(self):
        was = (self._available, bool(self._pot_status.get("installed")))
        self._available = deno.deno_available()
        self._pot_status = pot.status()
        self._status_cache = None
        if self._available:
            self._error = ""
        if self._pot_status.get("installed"):
            self._pot_error = ""
        if was != (self._available, bool(self._pot_status.get("installed"))):
            self.changed.emit()

    # ── engine status (for the Settings panel) ───────────────────────────
    def _status_dict(self):
        if self._status_cache is not None:
            return self._status_cache
        try:
            from app.core.runtime_deps import js_runtime_status
            status = js_runtime_status()
        except Exception:      # noqa: BLE001
            status = {"available": False, "name": "", "version": "", "source": "none"}
        self._status_cache = status
        return status

    @Property(str, notify=changed)
    def runtimeName(self):
        return self._status_dict().get("name", "")

    @Property(str, notify=changed)
    def runtimeVersion(self):
        return self._status_dict().get("version", "")

    @Property(str, notify=changed)
    def runtimeSource(self):
        """'path' (found on PATH), 'managed' (we downloaded it), or 'none'."""
        return self._status_dict().get("source", "none")

    @Property(bool, notify=changed)
    def updating(self):
        return self._updating

    @Slot()
    def updateYtDlp(self):
        """Download the newest yt-dlp into the user-data runtime dir on a worker
        thread. Works in a frozen build where `pip install --upgrade` can't run.
        """
        if self._updating:
            return
        self._updating = True
        self.changed.emit()

        def worker():
            try:
                from app.core.runtime_deps import update_yt_dlp
                ok, result = update_yt_dlp(
                    on_status=lambda t: None)   # status flows via toast on finish
            except Exception as exc:      # noqa: BLE001
                log_crash("DenoVM.updateYtDlp failed: " + str(exc))
                ok, result = False, str(exc)
            self._updateDone.emit(ok, result)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(bool, str)
    def _on_update_done(self, ok, result):
        self._updating = False
        self._status_cache = None
        self.changed.emit()
        if ok:
            self.toast.emit(
                tr("Downloader updated to {v}. Restart to use it.").format(v=result),
                "success")
        else:
            self.toast.emit(
                tr("Couldn't update the downloader: {e}").format(e=result), "error")

    @Slot()
    def retranslate(self):
        self.changed.emit()

    # ── worker bridges (GUI thread) ──────────────────────────────────────
    @Slot(int, int)
    def _on_progress(self, done, total):
        self._done = done
        self._total = total
        self.changed.emit()

    @Slot(str)
    def _on_stage(self, text):
        self._source = text
        self.changed.emit()

    @Slot(bool, str)
    def _on_finished(self, ok, err):
        self._busy = False
        self._available = deno.deno_available()
        self._status_cache = None
        if ok and not self._available:
            ok, err = False, tr("installed, but the app still can't find it")
        self._error = "" if ok or err == "cancelled" else (err or tr("Unknown error"))
        self._pot_status = pot.status()
        chain, self._chain = self._chain, False
        self.changed.emit()
        if ok and not self._pot_status.get("installed"):
            # deno is done but the required PO Token helper is still missing:
            # carry on with it as part of the same setup (or, outside a
            # chain, just say what is still needed).
            if chain:
                self.installPot()
            else:
                self.toast.emit(tr("JavaScript runtime installed. The PO Token "
                                   "helper is still required."), "info")
            return
        if ok:
            self._announce_ready()
        elif err == "cancelled":
            self.toast.emit(tr("Install cancelled."), "info")
        else:
            self.toast.emit(
                tr("Couldn't install the component: {e}").format(e=err), "error")
        self.finished.emit(ok)

    def _announce_ready(self):
        self.toast.emit(tr("Ready — you can download now."), "success")
        announce("success", tr("Download engine ready"),
                 tr("Ready — you can download now."), page=8,
                 icon="extension", source=tr("Downloads"))

    # ── PO Token helper (v3.41.4) ────────────────────────────────────────
    @Property(bool, notify=changed)
    def potInstalled(self):
        return bool(self._pot_status.get("installed"))

    @Property(bool, notify=changed)
    def potEnabled(self):
        return bool(self._pot_status.get("enabled"))

    @Property(bool, notify=changed)
    def potRunning(self):
        return bool(self._pot_status.get("running"))

    @Property(str, notify=changed)
    def potSource(self):
        return self._pot_status.get("source") or ""

    @Property(str, notify=changed)
    def potVersion(self):
        return pot.POT_VERSION

    @Property(bool, notify=changed)
    def potBusy(self):
        return self._pot_busy

    @Property(int, notify=changed)
    def potPct(self):
        return self._pot_pct

    @Slot()
    def refreshPot(self):
        self._pot_status = pot.status()
        self.changed.emit()

    @Slot(bool)
    def setPotEnabled(self, on):
        """v3.41.5: the helper is required and can't be turned off. Kept so an
        old QML binding doesn't error; it only clears a legacy "off"."""
        try:
            pot.set_enabled(True)
        except Exception:                  # noqa: BLE001
            log_crash("setPotEnabled failed")
        self.refreshPot()

    @Slot()
    def installPot(self):
        if self._pot_busy:
            return
        self._pot_busy = True
        self._pot_pct = 0
        self._pot_cancel = False
        self._pot_error = ""
        self.changed.emit()

        def worker():
            try:
                ok, err = pot.install(
                    on_progress=lambda d, t: self._potProgress.emit(int(d), int(t)),
                    should_cancel=lambda: self._pot_cancel)
            except Exception as exc:      # noqa: BLE001
                ok, err = False, str(exc)
            self._potDone.emit(ok, err)

        threading.Thread(target=worker, daemon=True, name="pot-install").start()

    @Slot()
    def cancelPot(self):
        self._pot_cancel = True

    @Slot(str)
    def installPotFromFile(self, url):
        """Offline install of bgutil-pot from a file the user already has."""
        if self._pot_busy:
            return
        from app.core.utils import local_path_from_url
        path = local_path_from_url(url)
        self._pot_busy = True
        self._pot_pct = 0
        self._pot_error = ""
        self.changed.emit()

        def worker():
            try:
                ok, err = pot.install_from_file(path)
            except Exception as exc:      # noqa: BLE001
                ok, err = False, str(exc)
            self._potDone.emit(ok, err)

        threading.Thread(target=worker, daemon=True, name="pot-file").start()

    @Slot(str)
    def installFromAnyFile(self, url):
        """The setup dialog's "From file…": the file goes to whichever required
        component is still missing (deno first)."""
        if not self._available:
            self.installFromFile(url)
        else:
            self.installPotFromFile(url)

    @Slot()
    def uninstallPot(self):
        pot.uninstall()
        self.refreshPot()

    @Slot(int, int)
    def _on_pot_progress(self, done, total):
        pct = int(done * 100 / total) if total > 0 else 0
        if pct != self._pot_pct:
            self._pot_pct = pct
            self.changed.emit()

    @Slot(bool, str)
    def _on_pot_done(self, ok, err):
        self._pot_busy = False
        self._pot_status = pot.status()
        if ok and not self._pot_status.get("installed"):
            ok, err = False, tr("installed, but the app still can't find it")
        self._pot_error = "" if ok or err == "cancelled" else (err or tr("Unknown error"))
        self.changed.emit()
        if ok:
            # warm the server now so the first download doesn't wait for it
            threading.Thread(target=pot.ensure_server, daemon=True,
                             name="pot-warm").start()
            if self.ready:
                self._announce_ready()
            else:
                self.toast.emit(tr("PO Token helper installed."), "success")
        elif err == "cancelled":
            self.toast.emit(tr("Install cancelled."), "info")
        else:
            self.toast.emit(tr("Couldn't install the PO Token helper: {e}").format(e=err),
                            "error")
        self.finished.emit(ok)
