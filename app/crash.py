"""app.crash - Youtube Scrapper."""

import faulthandler
import functools
import os
import traceback
from datetime import datetime

from PySide6.QtCore import QObject, Signal

from app.config import CONFIG_PATH

# ═════════════════════════════════════════════════════════════════════════
#  CRASH LOGGING & GUARDS
#  ---------------------------------------------------------------------
#  crash.log lives next to config.json. Three layers of protection:
#    1. faulthandler — catches native/hard crashes (segfaults) with a C-level
#       traceback, so "the app just closed" is never a mystery again.
#    2. sys.excepthook + threading.excepthook — catch Python exceptions on
#       the GUI thread AND worker threads, log them, and show a dialog
#       (marshalled onto the GUI thread — never shown from a worker).
#    3. @safe_slot — Qt-invoked slots never let an exception escape into Qt.
# ═════════════════════════════════════════════════════════════════════════
CRASH_LOG_PATH = os.path.join(os.path.dirname(CONFIG_PATH), "crash.log")
_FAULTHANDLER_FILE = None   # kept open for the process lifetime


def log_crash(text):
    """Append a timestamped block to crash.log (best-effort, never raises)."""
    try:
        # keep the log from growing forever
        if os.path.exists(CRASH_LOG_PATH) and os.path.getsize(CRASH_LOG_PATH) > 512 * 1024:
            with open(CRASH_LOG_PATH, "r", encoding="utf-8", errors="ignore") as f:
                tail = f.read()[-256 * 1024:]
            with open(CRASH_LOG_PATH, "w", encoding="utf-8") as f:
                f.write(tail)
        with open(CRASH_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(f"\n───── {datetime.now().isoformat(timespec='seconds')} ─────\n{text}\n")
    except Exception:
        pass


def _enable_faulthandler():
    """Route hard (native) crash tracebacks into crash.log — works even in
    windowed PyInstaller builds where sys.stderr is None."""
    global _FAULTHANDLER_FILE
    try:
        _FAULTHANDLER_FILE = open(CRASH_LOG_PATH, "a", encoding="utf-8")
        _FAULTHANDLER_FILE.write(
            f"\n═════ app start {datetime.now().isoformat(timespec='seconds')} ═════\n")
        _FAULTHANDLER_FILE.flush()
        faulthandler.enable(file=_FAULTHANDLER_FILE, all_threads=True)
    except Exception:
        pass


class CrashReporter(QObject):
    """Lives on the GUI thread; lets ANY thread request an error dialog."""
    report = Signal(str)


_CRASH_REPORTER = None   # created in main() after QApplication exists


def _request_error_dialog(summary):
    """Thread-safe: ask the GUI thread to show an error dialog."""
    try:
        if _CRASH_REPORTER is not None:
            _CRASH_REPORTER.report.emit(summary)
    except Exception:
        pass


def safe_slot(fn):
    """Decorator for Qt-invoked slots: an exception escaping a slot can abort
    the whole interpreter in a Qt app — catch, log, keep the app alive."""
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except Exception:
            log_crash(f"Exception in slot {fn.__qualname__}:\n{traceback.format_exc()}")
    return wrapper
