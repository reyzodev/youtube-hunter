"""app.qml_backend.vm.update_vm - YouTube Hunter (QML).

Context property `Updater`. Drives the title-bar update button and
UpdateDialog.qml:

  idle → checking → available → downloading → ready → installing
                 ↘ uptodate            ↘ error (retry)

Network work runs on worker threads and reports back over queued signals,
the same worker→GUI pattern every other VM uses.
"""

import os
import threading
import traceback

from PySide6.QtCore import (QCoreApplication, QObject, Property, QTimer, QUrl,
                            Signal, Slot)

from app.config import load_app_config, save_app_config
from app.constants import APP_VERSION, UPDATE_CHECK_HOURS
from app.core import updater
from app.core.utils import open_external_url
from app.crash import log_crash
from app.i18n import tr
from app.paths import asset_path
from app.qml_backend.desktop_notifier import announce


def _mb(n):
    return "%.1f MB" % (max(0, n) / 1048576.0)


def _eta(sec):
    sec = int(max(0, sec))
    if sec >= 3600:
        return "%dh %02dm" % (sec // 3600, sec % 3600 // 60)
    if sec >= 60:
        return "%dm %02ds" % (sec // 60, sec % 60)
    return "%ds" % sec


class UpdateVM(QObject):
    changed = Signal()
    progressChanged = Signal()
    openRequested = Signal()          # the shell should show the dialog
    _checked = Signal("QVariant", str, bool)
    _progress = Signal(float, float, float)
    _downloaded = Signal(str, str)

    def __init__(self, notifications=None, parent=None):
        super().__init__(parent)
        self._notifications = notifications
        self._state = "idle"
        self._rel = {}
        self._error = ""
        self._done = self._total = self._bps = 0.0
        self._path = ""
        self._cancel = False
        self._checked.connect(self._on_checked)
        self._progress.connect(self._on_progress)
        self._downloaded.connect(self._on_downloaded)
        self._timer = QTimer(self)
        self._timer.setInterval(int(UPDATE_CHECK_HOURS * 3600 * 1000))
        self._timer.timeout.connect(lambda: self.check(True))

    # ── lifecycle ────────────────────────────────────────────────────────
    def start(self, first_delay_ms=6000):
        """Called once from main_qml.py after the window is up."""
        if load_app_config().get("auto_update", True) is False:
            return
        QTimer.singleShot(first_delay_ms, lambda: self.check(True))
        self._timer.start()

    # ── properties ───────────────────────────────────────────────────────
    @Property(str, notify=changed)
    def state(self):
        return self._state

    @Property(bool, notify=changed)
    def hasUpdate(self):
        return self._state in ("available", "downloading", "ready",
                               "installing") or (self._state == "error" and bool(self._rel))

    @Property(str, constant=True)
    def currentVersion(self):
        return APP_VERSION

    @Property(str, notify=changed)
    def latestVersion(self):
        return self._rel.get("version", "")

    @Property(str, notify=changed)
    def releaseName(self):
        return self._rel.get("name", "")

    @Property(str, notify=changed)
    def published(self):
        return self._rel.get("published", "")

    @Property(str, notify=changed)
    def notes(self):
        return self._rel.get("notes", "") or tr("Fixes and improvements.")

    @Property(str, notify=changed)
    def sizeText(self):
        return _mb(self._rel.get("asset_size", 0)) if self._rel.get("asset_size") else ""

    @Property(str, notify=changed)
    def error(self):
        return self._error

    @Property(bool, constant=True)
    def packaged(self):
        return updater.is_packaged()

    @Property(str, constant=True)
    def logoUrl(self):
        return QUrl.fromLocalFile(asset_path("assets", "logo_256.png")).toString()

    @Property(float, notify=progressChanged)
    def progress(self):
        return (self._done / self._total) if self._total else 0.0

    @Property(str, notify=progressChanged)
    def receivedText(self):
        return "%s / %s" % (_mb(self._done), _mb(self._total)) if self._total else _mb(self._done)

    @Property(str, notify=progressChanged)
    def speedText(self):
        return (_mb(self._bps) + "/s") if self._bps > 0 else ""

    @Property(str, notify=progressChanged)
    def etaText(self):
        if self._bps <= 0 or not self._total:
            return ""
        return _eta((self._total - self._done) / self._bps)

    def _set_state(self, s, err=""):
        self._state, self._error = s, err
        self.changed.emit()

    # ── check ────────────────────────────────────────────────────────────
    @Slot()
    def checkNow(self):
        self.check(False)

    def check(self, silent=True):
        if self._state in ("checking", "downloading", "installing", "ready"):
            return
        self._set_state("checking")

        def worker():
            try:
                self._checked.emit(updater.latest_release(), "", silent)
            except Exception as exc:  # noqa: BLE001
                self._checked.emit(None, str(exc), silent)

        threading.Thread(target=worker, daemon=True, name="update-check").start()

    @Slot("QVariant", str, bool)
    def _on_checked(self, rel, err, silent):
        if err or not rel:
            # A silent background check that fails stays invisible.
            self._set_state("idle" if silent else "error",
                            tr("Couldn't reach GitHub to check for updates."))
            return
        if not (updater.is_newer(rel["version"]) and rel.get("asset_url")):
            self._rel = {}
            self._set_state("uptodate")
            return
        self._rel = rel
        self._set_state("available")
        self._announce_once(rel)

    def _announce_once(self, rel):
        title = tr("Update available: v{v}").format(v=rel["version"])
        msg = tr("A new version of YouTube Hunter is ready. Click the download "
                 "button in the title bar to install it.")
        if self._notifications is not None:
            try:
                self._notifications.push(msg, "info", title)
            except Exception:
                pass
        cfg = load_app_config()
        if cfg.get("update_notified") != rel["version"]:
            # The desktop card pops once per version, not on every launch.
            announce("info", title, msg, icon="download", source="YouTube Hunter",
                     force=True)
            cfg["update_notified"] = rel["version"]
            save_app_config(cfg)

    # ── download ─────────────────────────────────────────────────────────
    @Slot()
    def open(self):
        self.openRequested.emit()

    @Slot()
    def startDownload(self):
        if not self._rel or self._state in ("downloading", "installing"):
            return
        self._cancel = False
        self._done, self._total, self._bps = 0.0, float(self._rel.get("asset_size", 0)), 0.0
        self.progressChanged.emit()
        self._set_state("downloading")
        rel = dict(self._rel)

        def worker():
            try:
                path = updater.download(
                    rel["asset_url"], rel["asset_name"], rel.get("asset_size", 0),
                    rel.get("sha256", ""),
                    progress=lambda d, t, b: self._progress.emit(float(d), float(t), float(b)),
                    cancelled=lambda: self._cancel)
                self._downloaded.emit(path, "")
            except updater.UpdateCancelled:
                self._downloaded.emit("", "cancelled")
            except Exception as exc:  # noqa: BLE001
                log_crash("Update download failed:\n" + traceback.format_exc())
                self._downloaded.emit("", str(exc))

        threading.Thread(target=worker, daemon=True, name="update-download").start()

    @Slot(float, float, float)
    def _on_progress(self, done, total, bps):
        self._done, self._total, self._bps = done, total, bps
        self.progressChanged.emit()

    @Slot(str, str)
    def _on_downloaded(self, path, err):
        if err == "cancelled":
            self._set_state("available")
            return
        if err or not path:
            self._set_state("error", err or tr("The download failed."))
            return
        self._path = path
        self._set_state("ready")

    @Slot()
    def cancelDownload(self):
        self._cancel = True

    # ── install ──────────────────────────────────────────────────────────
    @Slot()
    def installNow(self):
        """Hand over to the installer and get out of its way. The packaged
        build quits so Setup can replace the files; Setup reopens the app."""
        if not self._path or not os.path.isfile(self._path):
            self._set_state("error", tr("The downloaded installer is missing. Download it again."))
            return
        self._set_state("installing")
        try:
            updater.launch_installer(self._path)
        except Exception as exc:  # noqa: BLE001
            self._set_state("error", tr("Couldn't start the installer: {e}").format(e=exc))
            return
        if updater.is_packaged():
            QTimer.singleShot(900, QCoreApplication.quit)
            # Belt and braces: if some window refuses to close, still leave.
            QTimer.singleShot(6000, lambda: os._exit(0))

    @Slot()
    def openReleasePage(self):
        open_external_url(self._rel.get("page")
                          or "https://github.com/reyzodev/youtube-hunter/releases/latest")
