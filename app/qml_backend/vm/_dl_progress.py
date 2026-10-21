"""app.qml_backend.vm._dl_progress - YouTube Hunter (QML).

One shared, in-memory store for LIVE download progress.

Three ViewModels can start a download — DownloadsVM (paste-a-link), NicheVM
(Niche Finder grid) and ArchiveVM (Search Archive grid) — but the Downloads page
must show live progress for ALL of them. Before this module each VM kept its own
progress dict, so a download started from a grid wrote its ticks somewhere the
Downloads page never read: the row appeared, then sat at 0% until you left the
page and came back (which re-read the slower, DB-persisted percentage).

The store is keyed by video id and holds only transient values (percent, status
text, bytes, speed, ETA, plus the `running`/`cancelling` flags the cancel path
needs). Nothing here is persisted — app.core.db.downloads owns the durable row.

Listeners are plain callables invoked synchronously from publish(). Every caller
publishes from a queued Qt slot, i.e. already on the GUI thread, so no extra
locking is needed and a listener may safely emit Qt signals.
"""

# video_id -> {"running": bool, "cancelling": bool, "pct": int, "text": str,
#              "done": int, "total": int, "speed": float, "eta": int}
_STATE = {}

# Callables notified after any change. `structural` is True when the change is
# one the Downloads page must rebuild its row list for (a download starting or
# finishing, a status transition) rather than just a moving number.
_LISTENERS = []


def add_listener(callback):
    """Register a `callback(video_id, structural)` invoked on every change."""
    if callback not in _LISTENERS:
        _LISTENERS.append(callback)


def _notify(video_id, structural):
    for cb in list(_LISTENERS):
        try:
            cb(video_id, structural)
        except Exception:      # noqa: BLE001 — a bad listener must not stop others
            pass


def publish(video_id, structural=False, **fields):
    """Merge `fields` into one video's live state and notify listeners.

    Merging (rather than replacing) matters: a status line arriving between two
    progress ticks must not wipe the byte counts the UI is animating from.
    """
    if not video_id:
        return
    entry = _STATE.setdefault(video_id, {})
    entry.update(fields)
    entry.setdefault("running", True)
    entry.setdefault("pct", 0)
    entry.setdefault("text", "")
    entry.setdefault("done", 0)
    entry.setdefault("total", 0)
    entry.setdefault("speed", 0.0)
    entry.setdefault("eta", 0)
    entry.setdefault("fragDone", 0)
    entry.setdefault("fragTotal", 0)
    _notify(video_id, structural)


def get(video_id):
    """One video's live state, or None when it isn't downloading."""
    return _STATE.get(video_id)


def snapshot():
    """A shallow copy of the whole store — what a QML-facing property returns."""
    return {vid: dict(d) for vid, d in _STATE.items()}


def is_running(video_id):
    return bool((_STATE.get(video_id) or {}).get("running"))


def is_cancelling(video_id):
    return bool((_STATE.get(video_id) or {}).get("cancelling"))


def clear(video_id, structural=True):
    """Forget one video's live state — called when its download ends."""
    if _STATE.pop(video_id, None) is not None:
        _notify(video_id, structural)
