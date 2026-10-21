"""app.qml_backend.vm.history_vm - YouTube Hunter (QML).

ViewModel behind HistoryPage.qml. Lists the export files saved in the user's
output folder (csv / jsonl / xlsx / sqlite), with filtering (all / completed /
partial), row counting, deletion, and "open in file manager" — the same logic
the legacy HistoryPageMixin implemented, minus the widget wiring.

Row counting and file opening reuse plain stdlib + openpyxl/sqlite3, so nothing
here depends on QtWidgets. The QWidgets app is untouched.
"""

import os
import sqlite3
import subprocess
import sys
from datetime import datetime

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.config import load_app_config
from app.core.utils import humanize_count
from app.i18n import tr

_EXPORT_EXTS = (".csv", ".jsonl", ".xlsx", ".db")


def _is_partial(name):
    n = name.lower()
    return "partial" in n or "checkpoint" in n


class HistoryVM(QObject):
    """Export-archive listing for the QML History page."""

    changed = Signal()            # list model changed
    folderChanged = Signal()
    toast = Signal(str, str)      # (message, kind)

    @Slot()
    def retranslate(self):
        """UI language changed — rebuild the rows so their translated text is
        re-read instead of served from the cache it was built in.

        A plain folder scan, so it is cheap. Re-emitting alone was not enough:
        the rows carry strings translated at build time (the "N/A" / "FILE"
        fallbacks), and a signal just re-delivers the old ones.
        """
        self.refresh()

    def __init__(self, parent=None):
        super().__init__(parent)
        cfg = load_app_config()
        self._folder = cfg.get("save_folder", "") or ""
        self._filter = 0          # 0=all, 1=completed, 2=partial
        self._search = ""         # free-text filter over file name / source
        self._rows = []           # cached list of dicts for QML
        self._all_rows = []       # unfiltered (for the search box + totals)
        self._total_rows = 0      # sum of row counts over every export

    # ── properties ─────────────────────────────────────────────────────
    @Property(str, notify=folderChanged)
    def folder(self):
        return self._folder

    @Property(int, notify=changed)
    def filterIndex(self):
        return self._filter

    @filterIndex.setter
    def filterIndex(self, i):
        i = max(0, min(2, int(i)))
        if i != self._filter:
            self._filter = i
            self._derive()

    @Property(str, notify=changed)
    def searchText(self):
        return self._search

    @searchText.setter
    def searchText(self, v):
        v = v or ""
        if v != self._search:
            self._search = v
            self._derive()

    @Property("QVariantList", notify=changed)
    def entries(self):
        """List of {name, path, source, partial, size, rows, saved} dicts,
        after the status filter + search box."""
        return self._rows

    @Property(bool, notify=changed)
    def hasFolder(self):
        return bool(self._folder) and os.path.isdir(self._folder)

    @Property(bool, notify=changed)
    def isEmpty(self):
        return len(self._rows) == 0

    @Property(bool, notify=changed)
    def hasAny(self):
        """Any export at all, regardless of filter/search — distinguishes an
        empty folder from a search that simply matched nothing."""
        return len(self._all_rows) > 0

    # headline totals (over every export, not the filtered view)
    @Property(str, notify=changed)
    def statFiles(self):
        return humanize_count(len(self._all_rows))

    @Property(str, notify=changed)
    def statRows(self):
        return humanize_count(self._total_rows)

    # ── actions ─────────────────────────────────────────────────────────
    @Slot()
    def reloadFolder(self):
        """Re-read the save folder from config (it may have changed on the
        Settings/Dashboard page) and refresh."""
        cfg = load_app_config()
        new_folder = cfg.get("save_folder", "") or ""
        if new_folder != self._folder:
            self._folder = new_folder
            self.folderChanged.emit()
        self.refresh()

    @Slot()
    def refresh(self):
        self._all_rows = []
        self._total_rows = 0
        folder = self._folder
        if not folder or not os.path.isdir(folder):
            self._rows = []
            self.changed.emit()
            return
        try:
            files = [fn for fn in os.listdir(folder) if fn.lower().endswith(_EXPORT_EXTS)]
        except Exception:
            files = []
        files.sort(key=lambda f: os.path.getmtime(os.path.join(folder, f)), reverse=True)

        for fn in files:
            path = os.path.join(folder, fn)
            partial = _is_partial(fn)
            try:
                size_kb = os.path.getsize(path) / 1024
                size_txt = f"{size_kb:.1f} KB" if size_kb < 1024 else f"{size_kb / 1024:.2f} MB"
            except Exception:
                size_txt = tr("N/A")
            rows = self._count_rows(path)
            if rows:
                self._total_rows += rows
            try:
                saved = datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d %H:%M")
            except Exception:
                saved = tr("N/A")
            ext = os.path.splitext(fn)[1].lstrip(".").upper() or tr("FILE")
            self._all_rows.append({
                "name": fn,
                "path": path,
                # the reference shows a "source" sub-line under the file name;
                # the export folder + type is the closest real analogue.
                "source": ext + " · " + os.path.basename(folder),
                "partial": partial,
                "size": size_txt,
                "rows": humanize_count(rows) if rows is not None else tr("N/A"),
                "saved": saved,
            })
        self._derive()

    def _derive(self):
        """Apply the status filter + search box to the cached list. Runs over a
        handful of dicts on the GUI thread — no disk re-scan."""
        needle = (self._search or "").strip().lower()
        out = []
        for r in self._all_rows:
            if self._filter == 1 and r["partial"]:
                continue
            if self._filter == 2 and not r["partial"]:
                continue
            if needle and needle not in r["name"].lower() and needle not in r["source"].lower():
                continue
            out.append(r)
        self._rows = out
        self.changed.emit()

    @Slot(str)
    def openFolder(self, path):
        folder = os.path.dirname(path) if path else self._folder
        self._reveal(folder)

    @Slot(str)
    def openFile(self, path):
        self._reveal(path)

    def _reveal(self, target):
        try:
            if sys.platform.startswith("win"):
                os.startfile(target)  # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", target])
            else:
                subprocess.Popen(["xdg-open", target])
        except Exception as e:
            self.toast.emit(tr("Could not open: {e}").format(e=e), "error")

    @Slot(str)
    def deleteFile(self, path):
        try:
            os.remove(path)
            self.toast.emit(tr("Deleted {name}.").format(name=os.path.basename(path)), "success")
        except Exception as e:
            self.toast.emit(tr("Delete failed: {e}").format(e=e), "error")
        self.refresh()

    @Slot()
    def deleteAll(self):
        n = 0
        for row in list(self._all_rows):
            try:
                os.remove(row["path"])
                n += 1
            except Exception:
                pass
        self.toast.emit(tr("Deleted {n} exports.").format(n=n), "success")
        self.refresh()

    # ── helpers ─────────────────────────────────────────────────────────
    def _count_rows(self, path):
        try:
            ext = os.path.splitext(path)[1].lower()
            if ext == ".csv":
                with open(path, encoding="utf-8-sig") as f:
                    return max(0, sum(1 for _ in f) - 1)
            if ext == ".jsonl":
                with open(path, encoding="utf-8") as f:
                    return sum(1 for _ in f)
            if ext == ".xlsx":
                from openpyxl import load_workbook
                wb = load_workbook(path, read_only=True)
                ws = wb.active
                return max(0, ws.max_row - 1)
            if ext == ".db":
                conn = sqlite3.connect(path)
                cur = conn.cursor()
                cur.execute("SELECT COUNT(*) FROM videos")
                n = cur.fetchone()[0]
                conn.close()
                return n
        except Exception:
            return None
        return None
