"""app.qml_backend.vm.extension_setup_vm - YouTube Hunter (QML).

v3.43 "Add the YouTube button": walks the user through installing the browser
extension in as few moves as Chrome allows for an extension that is not on the
Chrome Web Store:

    1. Open the extensions page   → we launch Chrome / Edge / Brave on it
    2. Turn on Developer mode     → one switch, top-right of that page
    3. Drag the folder onto it    → the folder card in our dialog is a real OS
                                    drag; "Load unpacked" + paste also works
                                    (the path is already on the clipboard)

The dialog closes itself the moment the extension calls the bridge (its
service worker pings /v1/ping right after it is installed), so the user never
has to tell us "done".

Context property `ExtensionSetup`. Persisted config keys:
    ext_connected        an extension has talked to us at least once
    ext_setup_skipped    the user pressed "Skip for now"
    ext_setup_offered    the dialog has opened itself once already
"""

import os
import subprocess
import sys

from PySide6.QtCore import (QMimeData, QObject, Property, Qt, QUrl, Signal,
                            Slot)
from PySide6.QtGui import QDrag, QGuiApplication

from app.config import load_app_config, save_app_config

_K_CONNECTED = "ext_connected"
_K_SKIPPED = "ext_setup_skipped"
_K_OFFERED = "ext_setup_offered"

# (name, exe candidates, extensions-page URL)
# Brave answers chrome://extensions too, but brave:// is what its own UI shows.
_BROWSERS = (
    ("Chrome", (r"Google\Chrome\Application\chrome.exe",), "chrome://extensions"),
    ("Edge", (r"Microsoft\Edge\Application\msedge.exe",), "edge://extensions"),
    ("Brave", (r"BraveSoftware\Brave-Browser\Application\brave.exe",), "brave://extensions"),
)


def _extension_dir():
    """Where the unpacked extension lives.

    Installed build: next to the exe ({app}\\browser-extension, see
    installer.iss). From source: <repo>/browser-extension."""
    if getattr(sys, "frozen", False):
        base = os.path.dirname(os.path.abspath(sys.executable))
    else:
        base = os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.dirname(os.path.abspath(__file__)))))
    path = os.path.join(base, "browser-extension")
    return path if os.path.isfile(os.path.join(path, "manifest.json")) else ""


def _find_browser():
    """(name, exe, url) of the first installed Chromium browser, else None."""
    if sys.platform != "win32":
        return None
    roots = [os.environ.get(k) for k in
             ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA")]
    for name, rels, url in _BROWSERS:
        for root in roots:
            if not root:
                continue
            for rel in rels:
                exe = os.path.join(root, rel)
                if os.path.isfile(exe):
                    return name, exe, url
    return None


class ExtensionSetupVM(QObject):
    changed = Signal()
    openRequested = Signal()        # Settings → "Set up" asks Main.qml to open
    connectedNow = Signal()         # fired once, the moment it gets connected

    def __init__(self, parent=None):
        super().__init__(parent)
        cfg = load_app_config()
        self._connected = bool(cfg.get(_K_CONNECTED, False))
        self._skipped = bool(cfg.get(_K_SKIPPED, False))
        self._offered = bool(cfg.get(_K_OFFERED, False))
        self._folder = _extension_dir()
        b = _find_browser()
        self._browser = b[0] if b else "Chrome"
        self._browser_url = b[2] if b else "chrome://extensions"

    @staticmethod
    def _persist(key, value):
        try:
            cfg = load_app_config()
            cfg[key] = value
            save_app_config(cfg)
        except Exception:
            pass

    # ── state ────────────────────────────────────────────────────────────
    @Property(bool, notify=changed)
    def connected(self):
        return self._connected

    @Property(bool, notify=changed)
    def available(self):
        return self._folder != ""

    @Property(str, notify=changed)
    def folder(self):
        return self._folder

    @Property(str, notify=changed)
    def browser(self):
        return self._browser

    @Property(str, notify=changed)
    def extensionsUrl(self):
        return self._browser_url

    @Property(bool, notify=changed)
    def shouldOfferOnStart(self):
        """Open by itself once, on a launch where it is still not installed."""
        return (self.available and not self._connected
                and not self._skipped and not self._offered)

    # ── actions ──────────────────────────────────────────────────────────
    @Slot()
    def requestOpen(self):
        self.openRequested.emit()

    @Slot()
    def markOffered(self):
        if not self._offered:
            self._offered = True
            self._persist(_K_OFFERED, True)
            self.changed.emit()

    @Slot()
    def skip(self):
        if not self._skipped:
            self._skipped = True
            self._persist(_K_SKIPPED, True)
            self.changed.emit()

    @Slot()
    def markConnected(self):
        """The bridge saw a request from an extension (queued from its
        thread). Idempotent."""
        if self._connected:
            return
        self._connected = True
        self._persist(_K_CONNECTED, True)
        self.changed.emit()
        self.connectedNow.emit()

    @Slot(result=bool)
    def copyPath(self):
        cb = QGuiApplication.clipboard()
        if cb is None or not self._folder:
            return False
        cb.setText(self._folder)
        return True

    @Slot(result=bool)
    def copyExtensionsUrl(self):
        cb = QGuiApplication.clipboard()
        if cb is None:
            return False
        cb.setText(self._browser_url)
        return True

    @Slot(result=bool)
    def openExtensionsPage(self):
        """Bring the browser up with chrome://extensions on the clipboard.

        v3.43 fix: Chrome REFUSES chrome:// addresses handed to it by another
        program (command line, shell, link) and just opens a normal window,
        which is exactly what the first version ran into. Nothing outside the
        browser can open that page, so the honest flow is: start / focus the
        browser and put the address on the clipboard; the guide then says
        "address bar, Ctrl+V, Enter". The URL is still passed along, so a
        browser that does accept it opens the page straight away."""
        self.copyExtensionsUrl()
        b = _find_browser()
        if b is None:
            return False
        try:
            flags = 0x00000008 if sys.platform == "win32" else 0  # DETACHED_PROCESS
            subprocess.Popen([b[1], "--new-window", b[2]], close_fds=True,
                             creationflags=flags)
            return True
        except Exception:
            return False

    @Property(bool, notify=changed)
    def isEdge(self):
        return self._browser == "Edge"

    @Slot()
    def openFolder(self):
        if not self._folder:
            return
        try:
            if sys.platform == "win32":
                os.startfile(self._folder)        # noqa: S606
            else:
                subprocess.Popen(["xdg-open", self._folder])
        except Exception:
            pass

    @Slot(result=bool)
    def dragFolder(self):
        """A real OS drag of the extension FOLDER (FileDrag only carries
        files). Dropped on chrome://extensions with Developer mode on, Chrome
        installs it unpacked: no file dialog at all."""
        if not self._folder:
            return False
        if not (QGuiApplication.mouseButtons() & Qt.LeftButton):
            return False
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(self._folder)])
        drag = QDrag(self)
        drag.setMimeData(mime)
        drag.exec(Qt.CopyAction, Qt.CopyAction)
        return True
