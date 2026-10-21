"""app.qml_backend.vm.notifications_vm - YouTube Hunter (QML).

Notification center for the QML shell. Owns a short history of app events
(scrape finished, download complete, key validated, errors…) and the unread
count the title-bar bell badges. This is the QML re-home of the legacy
NotificationsMixin + NotificationsPopover, minus the QtWidgets rendering.

Every per-page ViewModel already emits a `toast(message, kind)` signal for
transient feedback; main_qml wires those into `push()` here so the same events
also land in a persistent, reviewable tray. Pushing is thread-safe-ish in the
same sense as the rest of the app: callers emit Qt signals from workers, which
are delivered on the GUI thread, and push() is only ever called from there.
"""

from datetime import datetime

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.core.utils import notif_relative_time

# Keep the tray bounded — a long scrape can emit a lot of line-level events and
# an unbounded list is both a memory leak and an unreadable wall.
_HISTORY_CAP = 40

# Which page (StackLayout index in Main.qml, == app_controller PAGE_*) a
# notification belongs to, keyed by the source title main_qml tags each VM's
# toasts with. Clicking a tray row jumps to its page. Kept here rather than in
# QML so the mapping lives next to the push() that stores it.
_TITLE_PAGE = {
    "Settings": 10,
    "History": 2,
    "Niche Finder": 4,
    "Downloads": 8,
    "Monetize Checker": 3,
    "Search Archive": 5,
    "AI Ideas": 6,
    "Scraper": 0,
    "Dashboard": 0,
    "Content Lab": 7,
    # The teleprompter is Content Lab's third tab now, so a Script Studio toast
    # belongs to page 7 as well.
    "Script Studio": 7,
    "Niche Scan": 11,
    "Snapshot Insights": 11,   # pre-rename notifications still route here
    "Video Cutter": 12,
    "AI Chat": 13,
}


class NotificationsVM(QObject):
    """Notification history + unread count for the QML title-bar bell."""

    changed = Signal()          # list or unread count changed
    navigate = Signal(int)      # request the shell open this page index

    @Slot()
    def retranslate(self):
        """UI language changed — the relative timestamps ("2m ago") are built
        on read, so a plain re-emit is enough."""
        self.changed.emit()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._items = []        # list of dicts, newest first
        self._id_seq = 0

    # ── properties ───────────────────────────────────────────────────────
    @Property("QVariantList", notify=changed)
    def entries(self):
        """Newest-first list of {id, title, message, kind, time, read, page}."""
        return [{
            "id": n["id"],
            "title": n["title"],
            "message": n["message"],
            "kind": n["kind"],
            "time": notif_relative_time(n["ts"]),
            "read": n["read"],
            # StackLayout index the notification belongs to, or -1 if it isn't
            # tied to a page. Clicking a row with a page jumps there.
            "page": n.get("page", -1),
        } for n in self._items]

    @Property(int, notify=changed)
    def unreadCount(self):
        return sum(1 for n in self._items if not n["read"])

    @Property(bool, notify=changed)
    def isEmpty(self):
        return len(self._items) == 0

    # ── actions ──────────────────────────────────────────────────────────
    @Slot(str, str)
    @Slot(str, str, str)
    def push(self, message, kind="info", title=""):
        """Add a notification. `kind` is "success" | "error" | "info" |
        "warning". If no explicit title is given one is derived from the kind
        so the tray always has a bold lead line."""
        self._id_seq += 1
        self._items.insert(0, {
            "id": self._id_seq,
            "title": title or self._default_title(kind),
            "message": message,
            "kind": kind,
            "ts": datetime.now(),
            "read": False,
            "page": _TITLE_PAGE.get(title, -1),
        })
        del self._items[_HISTORY_CAP:]
        self.changed.emit()

    @Slot(int)
    def openPage(self, notif_id):
        """A tray row was clicked — mark it read and, if it maps to a page, ask
        the shell to navigate there (Main.qml wires `navigate` → App.goto)."""
        for n in self._items:
            if n["id"] == notif_id:
                if not n["read"]:
                    n["read"] = True
                    self.changed.emit()
                page = n.get("page", -1)
                if page is not None and page >= 0:
                    self.navigate.emit(int(page))
                return

    @Slot()
    def markAllRead(self):
        changed = False
        for n in self._items:
            if not n["read"]:
                n["read"] = True
                changed = True
        if changed:
            self.changed.emit()

    @Slot(int)
    def dismiss(self, notif_id):
        before = len(self._items)
        self._items = [n for n in self._items if n["id"] != notif_id]
        if len(self._items) != before:
            self.changed.emit()

    @Slot()
    def clearAll(self):
        if self._items:
            self._items = []
            self.changed.emit()

    # ── helpers ──────────────────────────────────────────────────────────
    @staticmethod
    def _default_title(kind):
        from app.i18n import tr
        return {
            "success": tr("Success"),
            "error": tr("Error"),
            "warning": tr("Heads up"),
        }.get(kind, tr("Notification"))
