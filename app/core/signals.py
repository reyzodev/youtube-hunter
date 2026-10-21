"""app.core.signals - Youtube Scrapper."""

import threading
import traceback

from PySide6.QtCore import QObject, Signal

# ═════════════════════════════════════════════════════════════════════════
#  SIGNAL EMITTER  (worker thread → GUI thread)
# ═════════════════════════════════════════════════════════════════════════
class SignalEmitter(QObject):
    log_signal      = Signal(str)
    finished_signal = Signal()
    progress_signal = Signal(int)
    status_signal   = Signal(str)
    popup_signal    = Signal(str, str, str)
    done_popup_signal = Signal(str, str, str)   # (title, message, output_path)
    validate_signal = Signal(str, bool, str)
    backup_key_validate_signal = Signal(str, bool, str, object, object)
    ai_key_validate_signal   = Signal(str, bool, str)   # (provider, ok, message)
    ai_key_validate_progress = Signal(str)              # interim status text, e.g.
                                                          # "checking base URL …"
    ai_models_fetch_signal   = Signal(bool, list, str)  # (ok, model_ids, error_message) —
                                                          # Custom Provider card's Fetch button
    ip_block_signal = Signal(str)   # (ip_at_time_of_block) — worker blocks on
# ═════════════════════════════════════════════════════════════════════════
#  GEMINI CLIENT  (plain REST call, no extra SDK dependency required)
# ═════════════════════════════════════════════════════════════════════════
class AISignals(QObject):
    """Generic signal bridge for any background AI (Gemini) call."""
    result = Signal(str, object)   # (text, context)
    error  = Signal(str, object)   # (message, context)


class IdeaScanSignals(QObject):
    """Bridges the Niche Finder background search back to the GUI thread."""
    done     = Signal(list, str)   # (rows, error_message or "")
    progress = Signal(int, str)    # (percent, status line)


class MonetizeSignals(QObject):
    """Bridges the Monetization Checker background lookup back to the GUI thread."""
    done = Signal(object, str)   # (data_dict_or_None, error_message or "")


class AIIdeasSignals(QObject):
    """Bridges the AI Ideas composer's background generation call back to
    the GUI thread. `done` carries the parsed list of idea dicts (or None on
    failure) plus an error message string (empty on success)."""
    done = Signal(object, str)   # (list_of_ideas_or_None, error_message or "")


class DownloadSignals(QObject):
    """Bridges a background video download (yt-dlp) back to the GUI thread —
    same shape as ThumbLoader: the worker thread only ever emits, the GUI
    thread does the actual widget touching."""
    status = Signal(str, str)               # (video_id, short status text)
    progress = Signal(str, int)             # (video_id, percent)
    finished = Signal(str, bool, str, str)  # (video_id, ok, message, filepath)


class UrlMetaSignals(QObject):
    """Bridges the Downloads page's "paste a link" metadata lookup back to
    the GUI thread. The worker fetches title/thumbnail/channel for a pasted
    YouTube URL (oEmbed, no API key) and emits `done`; the GUI thread then
    opens the quality picker and starts the real download."""
    done = Signal(object, str)   # (row_dict_or_None, error_message or "")


def run_done_task(signals, fn, *args, **kwargs):
    """Run `fn(...)` on a worker thread and report back through a
    `done(result, error_message)` signal.

    `run_ai_task()` below speaks a different dialect — it emits `result`/
    `error` — and handing it an `AIIdeasSignals` (which only owns `done`)
    made the worker thread die with

        'AIIdeasSignals' object has no attribute 'error'

    the instant the Gemini call finished, success or failure alike. Because
    that happened off the GUI thread the dialog just froze on "Thinking …"
    and the crash reporter popped the "unexpected error" box. Any consumer
    whose bridge object exposes `done` should use this runner instead.
    """
    def worker():
        try:
            result = fn(*args, **kwargs)
        except Exception as exc:
            try:
                signals.done.emit(None, str(exc) or exc.__class__.__name__)
            except Exception:
                traceback.print_exc()
            return
        try:
            signals.done.emit(result, "")
        except Exception:
            traceback.print_exc()
    threading.Thread(target=worker, daemon=True).start()
def run_ai_task(signals, context, fn, *args, **kwargs):
    """Run `fn(*args, **kwargs)` on a worker thread and emit result/error via `signals`."""
    def worker():
        try:
            text = fn(*args, **kwargs)
            signals.result.emit(text, context)
        except Exception as exc:
            signals.error.emit(str(exc), context)
    threading.Thread(target=worker, daemon=True).start()
