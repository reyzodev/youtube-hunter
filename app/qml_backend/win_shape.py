"""app.qml_backend.win_shape - YouTube Hunter (QML).

Makes the frameless window's rounded corners actually round on EVERY machine,
not just the ones where per-pixel window transparency happens to work.

The shell in Main.qml is a rounded Rectangle that fills the window, and the
window itself is created with `color: "transparent"`. On a machine where Qt gets
a surface with an alpha channel, the pixels outside that curve are simply not
painted and the corners are round — which is the normal case, and gives properly
antialiased corners.

On a machine where the alpha channel is NOT granted (a software rasterizer
fallback, a remote/virtual display, an old driver) the same window is composited
OPAQUE: the transparent colour is forced to solid black and the area outside the
shell's curve is painted — so a card with a 14px radius suddenly shows four hard
square corners. That is the "on some systems the frame is sharp, not rounded"
report.

Three things are done here, in order of preference:

  1. Re-assert the transparent window colour, so Qt asks for an alpha surface in
     the first place.
  2. Ask DWM for its own rounded corners (Windows 11). Free, and it also rounds
     the drop shadow the OS draws.
  3. If — and only if — the surface came back WITHOUT an alpha channel, clip the
     window to a rounded region. This is the guaranteed fallback: it does not
     depend on the compositor, the driver or the render backend. The region
     tracks the window's size and is dropped entirely while maximized (a
     maximized window has no corners to round, and a full-screen region would
     only cost a syscall per resize).

Everything here is cosmetic, so it is wrapped so a failure can never block
startup, and it is a no-op off Windows.
"""

import sys

from PySide6.QtCore import QObject, QRectF, Qt
from PySide6.QtGui import QPainterPath, QRegion

from app.crash import log_crash

# dwmapi.h — Windows 11 "round my corners" window attribute.
_DWMWA_WINDOW_CORNER_PREFERENCE = 33
_DWMWCP_DEFAULT = 0
_DWMWCP_DONOTROUND = 1
_DWMWCP_ROUND = 2


def _rounded_region(w, h, radius):
    """A QRegion clipped to a rounded rectangle of `radius`."""
    r = max(0, min(int(radius), int(min(w, h) / 2)))
    path = QPainterPath()
    if r <= 0:
        path.addRect(QRectF(0, 0, w, h))
    else:
        path.addRoundedRect(QRectF(0, 0, w, h), r, r)
    return QRegion(path.toFillPolygon().toPolygon())


def _ask_dwm_to_round(hwnd):
    """Windows 11: let DWM round the window itself. Returns True on success.

    On Windows 10 (or any older build) DwmSetWindowAttribute rejects the
    attribute with E_INVALIDARG — harmless, and the caller falls back to the
    region clip.
    """
    import ctypes

    pref = ctypes.c_int(_DWMWCP_ROUND)
    dwm = ctypes.windll.dwmapi
    res = dwm.DwmSetWindowAttribute(
        ctypes.c_void_p(hwnd),
        ctypes.c_int(_DWMWA_WINDOW_CORNER_PREFERENCE),
        ctypes.byref(pref),
        ctypes.sizeof(pref))
    return res == 0


class RoundedWindow(QObject):
    """Keeps a frameless window's corners round on every system.

    Install once, right after the window exists:

        shaper = RoundedWindow(window, radius=Tokens.windowRadius)

    Keep a reference for as long as the app runs (parenting it to the window
    does that). If the window already has an alpha surface — the normal case —
    this object does nothing beyond asking DWM to round it, because the QML
    shell's own curve is already doing the job with proper antialiasing.
    """

    def __init__(self, window, radius=14, parent=None):
        super().__init__(parent or window)
        self._window = window
        self._radius = int(radius)
        # Only clip when the surface genuinely has no alpha. Clipping a
        # translucent window would do nothing (Windows controls a layered
        # window's shape itself) and would cost a syscall per resize.
        self._needs_clip = False
        try:
            fmt = window.format()
            self._needs_clip = not bool(fmt.hasAlphaChannel())
        except Exception:            # noqa: BLE001
            self._needs_clip = False

        try:
            hwnd = int(window.winId())
            if hwnd:
                _ask_dwm_to_round(hwnd)
        except Exception as exc:      # noqa: BLE001 — cosmetic only
            log_crash("RoundedWindow: DWM call failed:\n" + str(exc))

        if self._needs_clip:
            window.widthChanged.connect(self._reapply)
            window.heightChanged.connect(self._reapply)
            window.windowStateChanged.connect(self._reapply)
            self._reapply()

    # ── region clipping (fallback path only) ─────────────────────────────
    def _maximized(self):
        try:
            return bool(self._window.windowStates() & Qt.WindowMaximized)
        except Exception:            # noqa: BLE001
            return False

    def _reapply(self, *_):
        try:
            w = int(self._window.width())
            h = int(self._window.height())
            if w <= 0 or h <= 0:
                return
            if self._maximized():
                # No corners to round when the window fills the screen, and a
                # region here would just be a syscall on every resize tick.
                self._window.setMask(QRegion())
                return
            self._window.setMask(_rounded_region(w, h, self._radius))
        except Exception:            # noqa: BLE001 — cosmetic; never crash
            pass


def apply_rounded_window(window, radius=14):
    """Convenience wrapper used by main_qml.py. Returns the RoundedWindow (or
    None off Windows)."""
    if not sys.platform.startswith("win"):
        return None
    try:
        # Belt and braces: QML already sets Window.color to "transparent", but
        # re-asserting it here is what guarantees Qt requests an alpha surface.
        window.setColor(Qt.transparent)
    except Exception:                # noqa: BLE001
        pass
    try:
        return RoundedWindow(window, radius=radius)
    except Exception as exc:         # noqa: BLE001
        log_crash("apply_rounded_window failed:\n" + str(exc))
        return None
