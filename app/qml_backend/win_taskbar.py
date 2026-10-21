"""app.qml_backend.win_taskbar - YouTube Hunter (QML).

Windows-only shell nicety: re-add WS_MINIMIZEBOX (and WS_MAXIMIZEBOX) onto the
frameless top-level window's HWND.

Main.qml creates the window with Qt.Window | Qt.FramelessWindowHint, and the
frameless hint strips those two style bits. Without WS_MINIMIZEBOX, Windows will
not perform its usual "click the taskbar button of the active window ->
minimize / click again -> restore" toggle, so the app feels unlike every other
window on the taskbar. Adding the bit back restores that behaviour while the
window stays visually frameless (the OS still draws no caption/border for a
FramelessWindowHint window — this only affects the shell's taskbar handling and
the minimize/restore animation).

Everything here is cosmetic, so it is wrapped so a failure can never block
startup, and it is a no-op off Windows.
"""

import sys

from app.crash import log_crash

# win32 constants
_GWL_STYLE = -16
_WS_MINIMIZEBOX = 0x00020000
_WS_MAXIMIZEBOX = 0x00010000


def enable_taskbar_minimize(window):
    """Add WS_MINIMIZEBOX | WS_MAXIMIZEBOX back onto `window`'s HWND.

    `window` is a QWindow (the QML root Window). Must be called AFTER the window
    has been created/shown — the native HWND doesn't exist before then, so
    winId() would return 0. No-op (returns False) off Windows or on any error.
    """
    if not sys.platform.startswith("win"):
        return False
    try:
        import ctypes

        hwnd = int(window.winId())
        if not hwnd:
            return False
        user32 = ctypes.windll.user32
        # GetWindowLongW/SetWindowLongW work on the 32-bit style word, which is
        # where WS_MINIMIZEBOX/WS_MAXIMIZEBOX live on both 32- and 64-bit.
        get = user32.GetWindowLongW
        set_ = user32.SetWindowLongW
        get.restype = ctypes.c_long
        get.argtypes = [ctypes.c_void_p, ctypes.c_int]
        set_.restype = ctypes.c_long
        set_.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_long]

        style = get(hwnd, _GWL_STYLE)
        new_style = style | _WS_MINIMIZEBOX | _WS_MAXIMIZEBOX
        if new_style != style:
            set_(hwnd, _GWL_STYLE, new_style)
        return True
    except Exception as exc:      # noqa: BLE001 — cosmetic; never crash startup
        log_crash("enable_taskbar_minimize failed:\n" + str(exc))
        return False
