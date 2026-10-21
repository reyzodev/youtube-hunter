"""app.qml_backend.cursor_guard - never let the mouse pointer go invisible.

A QML scene can leave the pointer INVISIBLE while it still works perfectly:
hover highlights light up, clicks land, tooltips appear - there is simply no
arrow to be seen. Three different Qt behaviours produce that same symptom, and
this guard cures all three with one rule.

  * Qt hides the mouse cursor while the user types into a text field and only
    restores it on the next pointer move. If that restore is missed (the field
    is destroyed, a popup closes over it, the focus moves on), the blank
    override cursor stays on the stack for the rest of the session.

  * A window whose scene declares no cursor at all ends up with an *unset*
    window cursor. Qt's Windows backend keeps its window class cursor NULL, so
    a window that does not answer WM_SETCURSOR with a real cursor leaves the
    pointer off-screen - Windows simply removes it until something re-asserts
    one. Popup and tooltip windows are the usual culprits: they are their own
    top-level window, they are created without a cursor, and they are exactly
    where the pointer goes right after you move onto a control.

  * `HoverHandler.cursorShape` is only consulted while the handler is *active*.
    When the pointer crosses between two items and neither handler is active at
    that instant, the window can be left holding whatever was applied last.

The rule is the same for all three: on every pointer event, drop a blank
override cursor and make sure the window under the pointer is not sitting on a
cursor that would draw nothing. QML still owns the *shape* (arrow vs pointing
hand vs I-beam) - this only ever replaces a cursor that renders as empty, so it
can never fight a legitimate cursor change.
"""

from PySide6.QtCore import QEvent, QObject, Qt
from PySide6.QtGui import QCursor, QGuiApplication, QWindow

# Pointer-driven events. Moving the mouse is the one thing a user is guaranteed
# to do when they cannot see the cursor, so these are the moments to re-assert
# one. Keyboard-only events are deliberately excluded: re-asserting on a
# keypress would undo Qt's own "hide the cursor while typing" behaviour.
_POINTER_EVENTS = frozenset({
    QEvent.Type.MouseMove,
    QEvent.Type.HoverMove,
    QEvent.Type.Enter,
    QEvent.Type.MouseButtonPress,
    QEvent.Type.MouseButtonDblClick,
    QEvent.Type.MouseButtonRelease,
    QEvent.Type.Wheel,
})

# Safety valve: never pop more than this many override cursors in one go. A
# sane app stacks one or two; a leak that stacked hundreds would otherwise turn
# every mouse move into a loop.
_MAX_POPS = 8


def _is_invisible(cursor):
    """True when this cursor would draw nothing on screen."""
    if cursor is None:
        return True
    try:
        shape = cursor.shape()
    except RuntimeError:            # the underlying C++ object is gone
        return False
    if shape == Qt.CursorShape.BlankCursor:
        return True
    # A bitmap cursor with a null pixmap is the "cursor object exists but is
    # empty" case - same invisible result, different shape id.
    if shape == Qt.CursorShape.BitmapCursor:
        try:
            return cursor.pixmap().isNull()
        except Exception:           # noqa: BLE001 - never let the guard throw
            return False
    return False


def _drop_blank_override():
    """Pop a leaked blank override cursor (Qt stacks these while typing)."""
    for _ in range(_MAX_POPS):
        current = QGuiApplication.overrideCursor()
        if not _is_invisible(current):
            break
        if current is None:
            break
        QGuiApplication.restoreOverrideCursor()


def install_window_filter(app, filt):
    """Install `filt` on every top-level window instead of on the application.

    v3.39.8 — both cursor helpers used `app.installEventFilter(...)`. An
    application-level filter sees EVERY event delivered to EVERY QObject:
    timers, queued signal calls from the workers, animation ticks, update
    requests, deferred deletes … and in PySide each one is a Python call that
    also allocates an event wrapper. Thousands per second, on the GUI thread,
    for filters that only ever act on pointer events sent to a QWindow. That
    steady overhead (and the garbage it produced) is a quiet source of
    hitches. Window-level filters receive exactly the same pointer events.

    Windows created later (a non-native file dialog, …) are picked up the
    first time they take focus; installing the same filter twice is a no-op
    in Qt (it is moved to the front, never duplicated)."""
    def _attach(win):
        if win is None:
            return
        try:
            win.installEventFilter(filt)
        except RuntimeError:            # window already destroyed
            pass

    for w in list(app.topLevelWindows()):
        _attach(w)
    try:
        app.focusWindowChanged.connect(lambda w: _attach(w))
    except Exception:                   # noqa: BLE001 — never break start-up
        app.installEventFilter(filt)    # old behaviour as a last resort


class CursorGuard(QObject):
    """Application-wide event filter that keeps a visible pointer on screen.

    Install once, right after the QML engine has loaded:

        guard = CursorGuard(app)

    Keep a reference to it for as long as the app runs (the parent argument
    does that if you pass the QGuiApplication, as above).
    """

    def __init__(self, app, parent=None):
        super().__init__(parent or app)
        self._app = app
        install_window_filter(app, self)

    def eventFilter(self, obj, event):      # noqa: N802 - Qt's naming
        if event.type() in _POINTER_EVENTS:
            try:
                self._reassert(obj)
            except Exception:               # noqa: BLE001
                # A cursor guard must never be the reason something breaks.
                pass
        # Always pass the event on untouched.
        return False

    def _reassert(self, obj):
        _drop_blank_override()
        if not isinstance(obj, QWindow):
            return
        try:
            current = obj.cursor()
        except RuntimeError:                # window already destroyed
            return
        if _is_invisible(current):
            obj.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
