"""app.qml_backend.win_frame - YouTube Hunter (QML).

v3.40.1: native maximize / restore / snap for the frameless window.

Why
---
Main.qml used to fake a "smooth" maximize by tweening win.x / y / width /
height every frame. Each of those four writes is a native SetWindowPos, and
every one of them makes Qt re-allocate the swap chain and re-layout the whole
QML tree (every page that was ever opened, not just the visible one). So one
maximize = ~12 frames x 4 resizes = ~48 full relayouts: that is the lag when
the window is made big or small.

The fix is the one every serious frameless app uses (VS Code, Discord,
qwindowkit, PyQt-Frameless-Window): give the HWND back its normal window style
(WS_CAPTION | WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX | WS_SYSMENU),
and answer WM_NCCALCSIZE with "the whole window is client area", so nothing
of the native frame is ever drawn. Windows then:

  * plays its OWN maximize / restore / minimize animation (done by DWM on a
    bitmap of the window, costs the app zero frames),
  * resizes the app exactly ONCE, at the end,
  * and gives back Aero-snap, Win+Up / Win+Down and the system menu.

While maximized, a WS_THICKFRAME window hangs its invisible resize border off
every edge of the monitor; the client rect is inset by that border so the
content fits the work area exactly. An auto-hide taskbar gets a 2px strip so
it can still slide out.

No-op off Windows, and every failure is swallowed: worst case the window
behaves exactly like before.
"""

import ctypes
import sys

from PySide6.QtCore import QAbstractNativeEventFilter
from PySide6.QtGui import QGuiApplication

from app.crash import log_crash

_GWL_STYLE = -16
_WS_CAPTION = 0x00C00000
_WS_THICKFRAME = 0x00040000
_WS_SYSMENU = 0x00080000
_WS_MINIMIZEBOX = 0x00020000
_WS_MAXIMIZEBOX = 0x00010000

_WM_NCCALCSIZE = 0x0083

_SWP_NOSIZE = 0x0001
_SWP_NOMOVE = 0x0002
_SWP_NOZORDER = 0x0004
_SWP_NOACTIVATE = 0x0010
_SWP_FRAMECHANGED = 0x0020

_SM_CXSIZEFRAME = 32
_SM_CYSIZEFRAME = 33
_SM_CXPADDEDBORDER = 92

_ABM_GETSTATE = 0x04
_ABM_GETTASKBARPOS = 0x05
_ABS_AUTOHIDE = 0x01
_ABE_LEFT, _ABE_TOP, _ABE_RIGHT, _ABE_BOTTOM = 0, 1, 2, 3

_MONITOR_DEFAULTTONEAREST = 2


if sys.platform.startswith("win"):
    from ctypes import wintypes

    class _NCCALCSIZE_PARAMS(ctypes.Structure):
        _fields_ = [("rgrc", wintypes.RECT * 3),
                    ("lppos", ctypes.c_void_p)]

    class _APPBARDATA(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD),
                    ("hWnd", wintypes.HWND),
                    ("uCallbackMessage", wintypes.UINT),
                    ("uEdge", wintypes.UINT),
                    ("rc", wintypes.RECT),
                    ("lParam", wintypes.LPARAM)]

    _user32 = ctypes.windll.user32
    _shell32 = ctypes.windll.shell32

    _GetWindowLongW = _user32.GetWindowLongW
    _GetWindowLongW.restype = ctypes.c_long
    _GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
    _SetWindowLongW = _user32.SetWindowLongW
    _SetWindowLongW.restype = ctypes.c_long
    _SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_long]
    _SetWindowPos = _user32.SetWindowPos
    _SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int,
                              ctypes.c_int, ctypes.c_int, ctypes.c_int,
                              wintypes.UINT]
    _IsZoomed = _user32.IsZoomed
    _IsZoomed.argtypes = [wintypes.HWND]
    _MonitorFromWindow = _user32.MonitorFromWindow
    _MonitorFromWindow.restype = wintypes.HMONITOR
    _MonitorFromWindow.argtypes = [wintypes.HWND, wintypes.DWORD]
    _SHAppBarMessage = _shell32.SHAppBarMessage
    _SHAppBarMessage.restype = ctypes.c_size_t
    _SHAppBarMessage.argtypes = [wintypes.DWORD, ctypes.POINTER(_APPBARDATA)]


def _border_thickness(hwnd):
    """Resize-border thickness (x, y) in physical px, DPI-aware when possible."""
    try:
        dpi = _user32.GetDpiForWindow(wintypes.HWND(hwnd))
        sm = _user32.GetSystemMetricsForDpi
        pad = sm(_SM_CXPADDEDBORDER, dpi)
        return sm(_SM_CXSIZEFRAME, dpi) + pad, sm(_SM_CYSIZEFRAME, dpi) + pad
    except Exception:                 # noqa: BLE001 — pre-1607 Windows
        sm = _user32.GetSystemMetrics
        pad = sm(_SM_CXPADDEDBORDER)
        return sm(_SM_CXSIZEFRAME) + pad, sm(_SM_CYSIZEFRAME) + pad


def _autohide_taskbar_edge(hwnd):
    """Edge of an auto-hide taskbar on this window's monitor, else None."""
    try:
        abd = _APPBARDATA()
        abd.cbSize = ctypes.sizeof(_APPBARDATA)
        if not (_SHAppBarMessage(_ABM_GETSTATE, ctypes.byref(abd)) & _ABS_AUTOHIDE):
            return None
        if not _SHAppBarMessage(_ABM_GETTASKBARPOS, ctypes.byref(abd)):
            return None
        bar_mon = _MonitorFromWindow(abd.hWnd, _MONITOR_DEFAULTTONEAREST)
        win_mon = _MonitorFromWindow(wintypes.HWND(hwnd), _MONITOR_DEFAULTTONEAREST)
        if bar_mon != win_mon:
            return None
        return int(abd.uEdge)
    except Exception:                 # noqa: BLE001
        return None


class _FrameFilter(QAbstractNativeEventFilter):
    """Turns the whole HWND into client area (see module docstring).

    App-level filters see every native message, so the fast path is one struct
    read and two int compares; everything else is only for WM_NCCALCSIZE.
    """

    def __init__(self, hwnd):
        super().__init__()
        self._hwnd = int(hwnd)

    def nativeEventFilter(self, eventType, message):   # noqa: N802 (Qt API)
        try:
            msg = wintypes.MSG.from_address(int(message))
            if msg.message != _WM_NCCALCSIZE or (msg.hWnd or 0) != self._hwnd:
                return False, 0
            if msg.wParam:
                rect = ctypes.cast(msg.lParam, ctypes.POINTER(
                    _NCCALCSIZE_PARAMS)).contents.rgrc[0]
            else:
                rect = ctypes.cast(msg.lParam, ctypes.POINTER(wintypes.RECT)).contents
            if _IsZoomed(wintypes.HWND(self._hwnd)):
                bx, by = _border_thickness(self._hwnd)
                rect.left += bx
                rect.top += by
                rect.right -= bx
                rect.bottom -= by
                edge = _autohide_taskbar_edge(self._hwnd)
                if edge == _ABE_BOTTOM:
                    rect.bottom -= 2
                elif edge == _ABE_TOP:
                    rect.top += 2
                elif edge == _ABE_LEFT:
                    rect.left += 2
                elif edge == _ABE_RIGHT:
                    rect.right -= 2
            # 0 = "client area is the rect I just gave you" → no native frame.
            return True, 0
        except Exception:             # noqa: BLE001 — never break the message loop
            return False, 0


def install_native_frame(window):
    """Give the frameless QML `window` native maximize/restore/snap.

    Call once, after the window is shown (its HWND must exist). Returns the
    filter object (keep a reference to it), or None off Windows / on failure.
    """
    if not sys.platform.startswith("win"):
        return None
    try:
        hwnd = int(window.winId())
        if not hwnd:
            return None
        flt = _FrameFilter(hwnd)
        # Filter FIRST: the style change below fires WM_NCCALCSIZE immediately.
        QGuiApplication.instance().installNativeEventFilter(flt)
        h = wintypes.HWND(hwnd)
        style = _GetWindowLongW(h, _GWL_STYLE)
        new_style = (style | _WS_CAPTION | _WS_THICKFRAME | _WS_SYSMENU
                     | _WS_MINIMIZEBOX | _WS_MAXIMIZEBOX)
        if new_style != style:
            _SetWindowLongW(h, _GWL_STYLE, new_style)
        _SetWindowPos(h, None, 0, 0, 0, 0,
                      _SWP_NOMOVE | _SWP_NOSIZE | _SWP_NOZORDER
                      | _SWP_NOACTIVATE | _SWP_FRAMECHANGED)
        return flt
    except Exception as exc:          # noqa: BLE001 — cosmetic; never block startup
        log_crash("install_native_frame failed:\n" + str(exc))
        return None
