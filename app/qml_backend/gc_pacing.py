"""app.qml_backend.gc_pacing - keep Python's garbage collector off the frames
that matter (v3.39.8).

Why this exists
---------------
CPython's cyclic collector runs whenever enough container objects have been
allocated, on whatever thread happens to be allocating — very often the GUI
thread, in the middle of an animation. A *full* (generation-2) pass walks every
tracked object in the process, so its pause grows with the heap: right after
start-up it is a few ms, after ten minutes of scraping, snapshots, chat
history and built pages it can be 50-200 ms. That is the "sometimes a small
lag, not always, and worse after a while" pattern.

Three cheap rules fix most of it:

  1. After start-up, `gc.freeze()` moves everything that exists (Qt wrappers,
     modules, the whole QML-side Python state) into a permanent generation the
     collector never walks again. Full passes then only scan what is new.
  2. While a theme swap or a page switch is animating, automatic collection is
     paused (`hold()`); it resumes a moment later. Reference counting still
     frees almost everything immediately — only *cycles* wait.
  3. When the app goes to the background (another window gets focus), the
     heap is collected in full and re-frozen, so the expensive pass happens
     while nobody is watching. Rate-limited.

None of this changes behaviour; it only moves *when* the collector runs.
"""

import gc
import time

from PySide6.QtCore import Qt, QTimer

_holds = 0
_paused_by_us = False
_last_idle_collect = 0.0
_IDLE_COLLECT_MIN_GAP_S = 90.0


def hold(ms=800):
    """Pause automatic cyclic GC for about `ms` milliseconds (nest-safe)."""
    global _holds, _paused_by_us
    if _holds == 0:
        if not gc.isenabled():
            return                       # someone else turned it off: leave it
        gc.disable()
        _paused_by_us = True
    _holds += 1
    QTimer.singleShot(max(1, int(ms)), lambda: _release())


def _release():
    global _holds, _paused_by_us
    if _holds <= 0:
        return
    _holds -= 1
    if _holds == 0 and _paused_by_us:
        _paused_by_us = False
        gc.enable()


def compact():
    """Full collection + re-freeze. Only call when nothing is animating."""
    global _last_idle_collect
    if _holds:
        return
    _last_idle_collect = time.monotonic()
    try:
        gc.unfreeze()
        gc.collect()
        gc.freeze()
    except Exception:                    # noqa: BLE001 — pacing must never break the app
        pass


def _on_state(state):
    if state == Qt.ApplicationState.ApplicationActive:
        return
    if time.monotonic() - _last_idle_collect < _IDLE_COLLECT_MIN_GAP_S:
        return
    # one event-loop turn later, so the deactivation itself paints first
    QTimer.singleShot(250, lambda: compact())


def install(app, settle_ms=6000):
    """Call once after the QML engine has loaded."""
    try:
        # Fewer, slightly larger young-generation passes. Young passes are
        # cheap; this mostly avoids promoting short-lived binding/model
        # temporaries into the old generations during bursts.
        t0, t1, t2 = gc.get_threshold()
        gc.set_threshold(max(t0, 5000), t1, t2)
    except Exception:                    # noqa: BLE001
        pass
    # Freeze once start-up has settled (first page built, fonts, icons).
    QTimer.singleShot(settle_ms, lambda: compact())
    try:
        app.applicationStateChanged.connect(_on_state)
    except Exception:                    # noqa: BLE001
        pass
