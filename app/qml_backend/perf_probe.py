"""app.qml_backend.perf_probe - YouTube Hunter (QML).

v3.40.1 diagnostic. Off unless the app is started with YH_PERF=1:

    set YH_PERF=1            (cmd)   /   $env:YH_PERF=1   (PowerShell)
    python main_qml.py

Then it prints one line per slow frame and per page switch, e.g.

    [perf]   4210ms  page -> 13
    [perf]   4262ms  slow frame 188ms  (gui 151 = polish 140 + sync 11, render 30)

`polish` is QML layout (Layouts, ListView delegates, text wrapping), `sync` is
building scene-graph nodes for newly shown items, `render` is the GPU side
(shader/pipeline creation, texture uploads). That split says which kind of fix
a hitch needs. Nothing here changes behaviour.
"""

import os
import sys
import time

from PySide6.QtCore import QObject, Qt

_T0 = time.perf_counter()
_SLOW_MS = 28.0


def _ms():
    return (time.perf_counter() - _T0) * 1000.0


def _out(text):
    if sys.stderr is not None:
        try:
            sys.stderr.write(f"[perf] {_ms():7.0f}ms  {text}\n")
            sys.stderr.flush()
        except Exception:
            pass


class PerfProbe(QObject):
    def __init__(self, window, app_ctrl=None):
        super().__init__(window)
        self._w = window
        self._t = {}
        d = Qt.DirectConnection          # render-thread signals: time them there
        window.afterAnimating.connect(self._anim, d)
        window.beforeSynchronizing.connect(self._sync0, d)
        window.afterSynchronizing.connect(self._sync1, d)
        window.beforeRendering.connect(self._rend0, d)
        window.frameSwapped.connect(self._swapped, d)
        sig = getattr(app_ctrl, "currentPageChanged", None)
        if sig is not None:
            sig.connect(lambda *_: _out(f"page -> {app_ctrl.property('currentPage')}"))
        _out("probe on")

    def _anim(self):
        self._t["a"] = time.perf_counter()

    def _sync0(self):
        self._t["s0"] = time.perf_counter()

    def _sync1(self):
        self._t["s1"] = time.perf_counter()

    def _rend0(self):
        self._t["r0"] = time.perf_counter()

    def _swapped(self):
        now = time.perf_counter()
        t = self._t
        a, s0, s1, r0 = t.get("a"), t.get("s0"), t.get("s1"), t.get("r0")
        last = t.get("last")
        t["last"] = now
        if last is None or a is None or s0 is None or s1 is None or r0 is None:
            return
        frame = (now - last) * 1000.0
        if frame < _SLOW_MS:
            return
        polish = max(0.0, (s0 - a) * 1000.0)
        sync = max(0.0, (s1 - s0) * 1000.0)
        render = max(0.0, (now - s1) * 1000.0)
        _out(f"slow frame {frame:.0f}ms  (gui {polish + sync:.0f} = polish {polish:.0f}"
             f" + sync {sync:.0f}, render {render:.0f})")


def install(window, app_ctrl=None):
    if os.environ.get("YH_PERF", "") not in ("1", "true", "yes"):
        return None
    try:
        return PerfProbe(window, app_ctrl)
    except Exception as exc:          # noqa: BLE001 — diagnostics only
        _out(f"probe failed: {exc}")
        return None
