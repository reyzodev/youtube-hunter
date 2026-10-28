"""app.qml_backend.vm.archive_vm - YouTube Hunter (QML).

ViewModel behind ArchivePage.qml. The Search Archive is the permanent library
of every Niche Finder search ever run: one section per keyword (merge-mode,
see app.core.db.archive), rows kept forever. This VM exposes it as a
master/detail pair —

  * master — the section list (keyword groups), searchable, with an
    All / Favorites tab switch and per-section rename / delete
  * detail — one section's saved rows, paged, sortable, favorites-only
    filterable, with per-row favorite / download / copy / open / delete and
    a section export

— all read/write through the same app.core.db.archive / favorites functions
the legacy QWidgets page used. Nothing here spends YouTube quota: reading the
archive is always local.
"""

import os
import subprocess
import sys
import threading
import time

from PySide6.QtCore import QObject, Property, Qt, QTimer, Signal, Slot
from PySide6.QtGui import QGuiApplication

from app.config import load_app_config
from app.core.db.archive import (
    archive_clear_all, archive_delete_group, archive_delete_item,
    archive_get_group, archive_get_rows, archive_list_groups_full,
    archive_rename_group, archive_set_group_favorite, archive_update_rows)
from app.core.db.downloads import (downloads_apply_channel_meta,
                                    downloads_list, downloads_upsert,
                                    file_size_of)
from app.core.db.favorites import favorite_mark_item
from app.core.download import (
    DOWNLOAD_CANCELLED, DOWNLOAD_QUALITY_PRESETS, clear_cancel, download_video,
    is_cancelled, quality_by_key, quality_display_label,
    quality_storage_key, request_cancel, with_audio_lang, with_container)
from app.core.exports import write_export
from app.core.niche.config import (
    NICHE_CHANNEL_AGES, NICHE_CHANNEL_UPLOADS, NICHE_DURATIONS, NICHE_PAGE_SIZE,
    NICHE_PER_CHANNEL, NICHE_SORTS_UI, NICHE_TIMEFRAMES)
from app.core.niche.helpers import (
    fmt_duration, format_multiplier, is_gem_row, parse_human_number)
from app.core.niche.search import (apply_niche_filters, cap_per_channel,
                                   compute_niche_metrics)
from app.core.niche.live_stats import (LiveStatsError, STALE_AFTER_S,
                                       is_stale, refresh_rows_live,
                                       stats_age_s, youtube_api_keys)
from app.core.youtube_api import ScrapeCancelled
from app.core.niche.sorting import (aggregate_by_channel, parse_human_float,
                                    sort_archive_quick, sort_niche_rows)
from app.core.utils import (
    days_ago_str, video_download_dir, humanize_count, local_path_from_url,
    open_external_url)
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm import _dl_progress as dlp
from app.qml_backend.vm._thumb_download import (remember_thumb_folder,
                                                start_thumb_download,
                                                thumb_folder)
from app.qml_backend.vm.niche_vm import (_age_short, _channel_card_fields,
                                         _lang_label, _prefetch_page_thumbs,
                                         _thumb_id)
from app.qml_backend.vm.quality_probe import default_quality_rows
from app.qml_backend.desktop_notifier import announce, announce_download

# Detail-view sort menu: reuses the Niche Finder's own sort vocabulary
# (NICHE_SORTS_UI) so a saved section sorts exactly like a live search — the
# "Best Finds · Views ÷ Subs" ladder rather than the old five-item list. Each
# entry is (label, local_sort_key); sort_niche_rows knows every key.
_SORTS = NICHE_SORTS_UI


def _scan_downloaded_ids():
    """Video ids whose finished download still exists on disk.

    Pure function (db read + file checks, no Qt), so it can run on a worker
    thread: see ArchiveVM.refreshDownloaded."""
    try:
        rows = downloads_list()
    except Exception:           # noqa: BLE001 — DB not ready yet
        rows = []
    fresh = set()
    for r in rows:
        try:
            status = (r.get("status") or "").lower()
        except AttributeError:
            continue
        if status not in ("complete", "done"):
            continue
        vid = (r.get("video_id") or "").strip()
        path = (r.get("filepath") or "").strip()
        if vid and path and os.path.isfile(path):
            fresh.add(vid)
    return fresh


def _live_row_key(r):
    """The key live-refresh uses for a row: its archive key, else video id.
    A channel aggregate has neither of its own, so it resolves to its hero
    video — which is one of the raw rows the refresh returns."""
    key = r.get("_archive_key") or r.get("video_id")
    if key:
        return key
    bv = r.get("best_video") or {}
    return bv.get("_archive_key") or bv.get("video_id") or ""

# Everything the "Filters" side sheet can set on an open section. The first
# block are typed bounds (stored parsed, handed back humanized), the second
# are picks stored as an index into the matching NICHE_* table, so a saved
# section cuts exactly like the Niche Finder's own "Refine current results".
_RANGE_NUM_KEYS = ("subs_min", "subs_max", "views_min", "views_max")
_RANGE_FLOAT_KEYS = ("mult_min", "outlier_min", "vel_min", "eng_min")
_RANGE_PICK_KEYS = {           # key → (table, ignored inside a channel section)
    "duration":    (NICHE_DURATIONS, False),
    "channel_age": (NICHE_CHANNEL_AGES, True),
    "uploads":     (NICHE_CHANNEL_UPLOADS, True),
    "per_channel": (NICHE_PER_CHANNEL, True),
}
# One channel = one subscriber count, one age, one upload total: these cuts
# mean nothing there (the sheet hides them; this keeps stale values out).
_CHANNEL_ONLY_KEYS = ("subs_min", "subs_max", "sort_subs", "mult_min")


def _fmt_bound(v):
    """1000 → '1K' · 2.5 → '2.5' · 4.0 → '4' — what the sheet shows back."""
    if v is None:
        return ""
    if v >= 1000:
        return humanize_count(v).replace(".0", "")
    return f"{v:g}"


def _pick_index(table, value):
    try:
        i = int(value or 0)
    except (TypeError, ValueError):
        return 0
    return i if 0 <= i < len(table) else 0

# v3.43c: a CHANNEL section is one channel's uploads, so every row shares the
# same subscriber count — "Smallest Channel First" and "Smallest Channel ·
# Highest Views" can't order anything there (the first was a no-op, the second
# silently degraded into "Most Views"). They are hidden from that section's
# Sort menu; keyword / favorites sections keep them. The VM keeps indexing the
# FULL _SORTS list internally and translates to the visible list at the
# property boundary, so nothing else that reads `_sort` has to change.
_CHANNEL_HIDDEN_SORTS = frozenset({"subscriber_count", "small_high_view"})


class ArchiveVM(QObject):
    """Search Archive master/detail state for the QML page."""

    changed = Signal()          # section list / stats / filter changed
    detailChanged = Signal()    # open-section meta changed
    rowsChanged = Signal()      # open-section rows / pager changed
    savedChanged = Signal()     # the favorites set changed (sticky stars)
    labelsChanged = Signal()    # UI language changed
    sortsChanged = Signal()     # visible Sort-menu entries changed (v3.43c)
    downloadsChanged = Signal()
    # v3.44 perf: the finished-on-disk set has its own signal. It used to ride
    # on downloadsChanged, which fires on EVERY progress tick — so each tick
    # made all 24 cards re-read (and re-convert) the whole downloaded list.
    downloadedChanged = Signal()
    toast = Signal(str, str)    # (message, kind)
    # v3.42: where the ✦ "Send to AI Ideas" tile delivers its row. main_qml.py
    # points this at IdeasVM.addReferences(rows, source) -> (added, already).
    # A plain callable rather than a Signal: the raw dict must reach IdeasVM
    # as-is (a QVariant round-trip would copy and re-type it) and the caller
    # needs the answer to word its toast.
    ideas_sink = None
    # "Analyze this group" — hand the open section's rows to Niche Scan.
    # Same (rows, query, mode) contract NicheVM uses, so Main.qml routes both
    # with one Connections block.
    analyzeRequested = Signal(list, str, str)
    # internal worker → GUI bridge for downloads (queued across threads)
    _dlStatus = Signal(str, str)
    _dlProgress = Signal(str, int)
    # (video_id, bytes_done, bytes_total, bytes_per_sec, eta_seconds,
    #  frag_done, frag_total) — the raw numbers a live progress UI needs; a bare
    # percentage can't express speed, and frag_done/total drive "part 32 of 93".
    _dlDetail = Signal(str, int, int, float, int, int, int)
    _dlDone = Signal(str, bool, str, str)
    # (video_id, height_px, label) — the resolution actually delivered, so the
    # mirrored Downloads row carries the file's real quality, not the request's.
    _dlResolved = Signal(str, int, str)
    # Channel identity harvested from the download's own metadata, marshalled
    # onto the GUI thread before it touches the DB (see _on_dl_meta).
    _dlMeta = Signal(str, "QVariantMap")
    _thumbDone = Signal(str, str)          # (saved_path_or_"", error)
    # v1.0.1: the finished-on-disk scan runs off the GUI thread when the page
    # is shown (fresh video ids, scan token)
    _dlScanned = Signal(list, int)
    # v3.43 live stats: worker → GUI thread
    liveChanged = Signal()
    _liveChunk = Signal(int, int, list)    # (group_id, token, fresh rows)
    _liveFinished = Signal(int, int, str)  # (group_id, token, error code or "")

    def __init__(self, parent=None):
        super().__init__(parent)
        self._tab = 0                # 0 all, 1 favorites
        self._search = ""
        self._groups_raw = []        # every group dict from the db
        self._groups = []            # after tab/search filtering, for QML
        self._total_videos = 0
        self._total_favs = 0
        self._total_runs = 0

        # open-section detail state
        self._gid = None
        self._group = None
        self._detail_raw = []        # full raw rows of the open group
        self._detail_filtered = []   # after favorites-only + sort (+ channels view)
        self._detail_filtered_videos = []  # same, before channel aggregation
        self._detail_visible = []    # current page, flattened for QML
        self._raw_by_key = {}        # video_id / archive key → raw row
        self._fav_only = False
        # Videos / Channels is a VIEW of the open section, not a filter on the
        # saved rows: switching it rolls the same matched videos up per channel
        # instead of throwing anything away.
        self._channels_view = False
        self._sort = 0
        self._page = 0
        self._saved_ids = []         # favorite video ids ON THE CURRENT PAGE
        self._page_downloaded = []   # downloaded ∩ _page_ids (what cards bind)

        # detail-view filters (mirror the Niche Finder's own toolbar): a free
        # text search over title/channel, a published-within timeframe, and the
        # subscriber/view/format range set from the "Filter by range" flyout.
        self._detail_text = ""
        self._timeframe = len(NICHE_TIMEFRAMES) - 1   # default "All Time"
        self._range = {}             # see _RANGE_KEYS below

        # per-row download state (video_id → {state, pct, text})
        self._downloads = {}
        self._last_db_write = {}  # video_id -> (monotonic_s, pct), DB throttle
        # video_ids with a finished file on disk (any session) — the card's
        # Download button becomes Open for these.
        self._downloaded = set()
        self._dl_scan_token = 0
        self._dlScanned.connect(self._on_dl_scanned)
        self._refresh_downloaded(silent=True)
        # v3.44 perf: progress ticks arrive many times a second per download;
        # the cards only need ~10 fps, so downloadsChanged is coalesced.
        self._dl_emit = QTimer(self)
        self._dl_emit.setSingleShot(True)
        self._dl_emit.setInterval(100)
        self._dl_emit.timeout.connect(self.downloadsChanged.emit)

        self._dlStatus.connect(self._on_dl_status)
        self._dlProgress.connect(self._on_dl_progress)
        self._dlDetail.connect(self._on_dl_detail)
        self._dlDone.connect(self._on_dl_done)
        self._dlResolved.connect(self._on_dl_resolved)
        self._dlMeta.connect(self._on_dl_meta)
        self._thumbDone.connect(self._on_thumb_done)

        # v3.43 live stats for the open section (see app.core.niche.live_stats)
        self._live_token = 0
        self._live_state = "idle"   # idle | refreshing | live | nokey | quota | error
        self._live_done = 0
        self._live_total = 0
        self._live_missing = 0
        # off-page rows from the refresh in flight, applied in one pass when it
        # finishes (see _on_live_chunk for why they are not merged per chunk)
        self._live_pending = {}
        self._liveChunk.connect(self._on_live_chunk)
        self._liveFinished.connect(self._on_live_finished)
        # while a section is open: re-read every STALE_AFTER_S (only when the
        # app is in front), and re-word "updated 3m ago" every 30 s
        self._live_timer = QTimer(self)
        self._live_timer.setInterval(STALE_AFTER_S * 1000)
        self._live_timer.timeout.connect(self._live_auto)
        self._live_clock = QTimer(self)
        self._live_clock.setInterval(30_000)
        self._live_clock.timeout.connect(self.liveChanged.emit)
        gui = QGuiApplication.instance()
        if gui is not None:
            gui.applicationStateChanged.connect(self._on_app_state)
        self.reload()

    # ── option lists (constant) ─────────────────────────────────────────
    # Translated, so NOT constant: the UI language can change while running.
    def _visible_sorts(self):
        """Indices into _SORTS the open section's Sort menu offers."""
        if (self._group or {}).get("mode") == "channel":
            return [i for i, row in enumerate(_SORTS)
                    if row[1] not in _CHANNEL_HIDDEN_SORTS]
        return list(range(len(_SORTS)))

    @Property("QStringList", notify=sortsChanged)
    def sortOptions(self):
        return [tr(_SORTS[i][0]) for i in self._visible_sorts()]

    @Property("QStringList", notify=sortsChanged)
    def sortKeys(self):
        """Local sort key per visible entry — the menu picks its glyph by key
        (not by position), so hiding entries can't shift the icons."""
        return [_SORTS[i][1] for i in self._visible_sorts()]

    @Property("QStringList", notify=labelsChanged)
    def timeframeOptions(self):
        return [tr(label) for label, _ in NICHE_TIMEFRAMES]

    @Slot()
    def retranslate(self):
        """UI language changed — re-read every translated label."""
        self.labelsChanged.emit()
        self.sortsChanged.emit()
        self.changed.emit()
        self.detailChanged.emit()
        self.rowsChanged.emit()

    @Property("QVariantList", constant=True)
    def qualityOptions(self):
        """Fallback rows for the shared QualityPicker (whose `target` is this VM
        on the Archive page). The picker normally shows QualityProbe.options —
        the real formats THIS video has — and falls back to this generic ladder
        only when the probe couldn't run."""
        return default_quality_rows()

    # ── master: section list ────────────────────────────────────────────
    @Property("QVariantList", notify=changed)
    def groups(self):
        return self._groups

    @Property(bool, notify=changed)
    def isEmpty(self):
        return len(self._groups) == 0

    @Property(bool, notify=changed)
    def hasAny(self):
        """Any section at all — distinguishes "archive is empty" (CTA to the
        Niche Finder) from "nothing matches this search"."""
        return len(self._groups_raw) > 0

    @Property(str, notify=changed)
    def filterText(self):
        return self._search

    @filterText.setter
    def filterText(self, v):
        v = v or ""
        if v != self._search:
            self._search = v
            self._derive_groups()

    @Property(int, notify=changed)
    def tabIndex(self):
        return self._tab

    @tabIndex.setter
    def tabIndex(self, i):
        i = 0 if int(i) < 1 else 1
        if i != self._tab:
            self._tab = i
            # reload(), not just _derive_groups(): the tab lives in the DB
            # query (starred sections + sections with starred videos), so
            # switching tabs without re-querying never actually filtered.
            self.reload()

    # headline stats under the page title (over ALL sections, not the
    # filtered view — the numbers describe the library, not the search box)
    @Property(str, notify=changed)
    def statGroups(self):
        return humanize_count(len(self._groups_raw))

    @Property(str, notify=changed)
    def statVideos(self):
        return humanize_count(self._total_videos)

    @Property(str, notify=changed)
    def statFavorites(self):
        return humanize_count(self._total_favs)

    @Property(str, notify=changed)
    def statRuns(self):
        return humanize_count(self._total_runs)

    # ── detail: one open section ────────────────────────────────────────
    @Property(bool, notify=detailChanged)
    def isDetail(self):
        return self._gid is not None

    @Property(int, notify=detailChanged)
    def detailId(self):
        return self._gid if self._gid is not None else -1

    @Property(str, notify=detailChanged)
    def detailTitle(self):
        return (self._group or {}).get("title") or ""

    @Property(str, notify=detailChanged)
    def detailModeLabel(self):
        mode = (self._group or {}).get("mode") or "keyword"
        if mode == "channel":
            return "CHANNEL"
        if mode == "favorite":
            return "FAVORITES"
        if mode == "viral":
            return "VIRAL"
        return "KEYWORD"

    @Property(str, notify=detailChanged)
    def detailSourceLabel(self):
        source = (self._group or {}).get("source") or "api"
        return "SCRAPE" if source == "scrape" else "API"

    @Property(bool, notify=detailChanged)
    def detailIsChannel(self):
        """Whether the open section is a channel scan. The range flyout hides
        its subscriber blocks on these — every video shares the one channel,
        so subscriber bounds/sorts are meaningless there."""
        return (self._group or {}).get("mode") == "channel"

    @Property(bool, notify=detailChanged)
    def detailCanGroupChannels(self):
        """Keyword / Viral / Favorites sections can be read as a channel
        leaderboard; a channel scan cannot (it IS one channel)."""
        return (self._group or {}).get("mode") != "channel"

    @Property(bool, notify=detailChanged)
    def detailChannelsView(self):
        return self._channels_view

    @detailChannelsView.setter
    def detailChannelsView(self, v):
        v = bool(v) and self.detailCanGroupChannels
        if v != self._channels_view:
            self._channels_view = v
            self._render_detail()
            self.detailChanged.emit()

    @Property(str, notify=detailChanged)
    def detailRuns(self):
        return str((self._group or {}).get("run_count") or 0)

    @Property("QVariantList", notify=detailChanged)
    def detailStats(self):
        """Cells of the detail header strip: caption/value pairs computed
        once per open, so QML just lays them out."""
        g = self._group or {}
        # In Channels view the page counts channels, not videos, and its
        # numbers must be the same filtered set the grid shows.
        rows = (self._detail_filtered if self._channels_view
                and self._detail_filtered else self._detail_raw)
        views = sum(r.get("view_count") or 0 for r in rows)
        mults = [r.get("multiplier") for r in rows if r.get("multiplier")]
        return [
            {"l": tr("Channels") if self._channels_view else tr("Videos"),
             "v": humanize_count(len(rows))},
            {"l": tr("Favorites"), "v": humanize_count(g.get("fav_count") or 0)},
            {"l": tr("Total views"), "v": humanize_count(views)},
            {"l": tr("Best multiplier"),
             "v": format_multiplier(max(mults)) if mults else "—"},
            {"l": tr("Runs"), "v": str(g.get("run_count") or 0)},
            {"l": tr("Last refresh"),
             "v": days_ago_str(g.get("updated_at") or "")},
        ]

    @Property(bool, notify=detailChanged)
    def detailFavOnly(self):
        return self._fav_only

    @detailFavOnly.setter
    def detailFavOnly(self, v):
        v = bool(v)
        if v != self._fav_only:
            self._fav_only = v
            self._render_detail()
            self.detailChanged.emit()

    @Property(int, notify=detailChanged)
    def detailSortIndex(self):
        """Position in the VISIBLE Sort menu (see _visible_sorts)."""
        vis = self._visible_sorts()
        return vis.index(self._sort) if self._sort in vis else 0

    @detailSortIndex.setter
    def detailSortIndex(self, i):
        vis = self._visible_sorts()
        try:
            i = vis[max(0, min(len(vis) - 1, int(i)))]
        except (TypeError, ValueError, IndexError):
            return
        if i != self._sort:
            self._sort = i
            self._render_detail(keep_page=True)
            self.detailChanged.emit()

    # ── detail filters: text search, timeframe, range flyout ────────────
    @Property(str, notify=detailChanged)
    def detailFilterText(self):
        return self._detail_text

    @detailFilterText.setter
    def detailFilterText(self, v):
        v = v or ""
        if v != self._detail_text:
            self._detail_text = v
            self._render_detail()
            self.detailChanged.emit()

    @Property(int, notify=detailChanged)
    def detailTimeframeIndex(self):
        return self._timeframe

    @detailTimeframeIndex.setter
    def detailTimeframeIndex(self, i):
        i = max(0, min(len(NICHE_TIMEFRAMES) - 1, int(i)))
        if i != self._timeframe:
            self._timeframe = i
            self._render_detail()
            self.detailChanged.emit()

    @Property(bool, notify=detailChanged)
    def detailRangeActive(self):
        """Whether the Filters sheet has anything set — drives the filter
        button's active tint, same idea as the legacy _refresh_archive_range_btn."""
        f = self._range
        if any(f.get(k) is not None for k in _RANGE_NUM_KEYS + _RANGE_FLOAT_KEYS
               + ("format", "sort_views", "sort_subs")):
            return True
        return any(f.get(k) for k in _RANGE_PICK_KEYS)

    @Property("QVariantMap", notify=detailChanged)
    def detailRange(self):
        """Current sheet values, so it can prefill when it reopens (humanized
        numbers for the min/max boxes, plain indices for the chip rows)."""
        f = self._range
        out = {}
        for k in _RANGE_NUM_KEYS:
            v = f.get(k)
            out[k] = humanize_count(v) if v is not None else ""
        for k in _RANGE_FLOAT_KEYS:
            out[k] = _fmt_bound(f.get(k))
        for k in _RANGE_PICK_KEYS:
            out[k] = int(f.get(k) or 0)
        out["format"] = f.get("format") or "all"
        out["sort_views"] = f.get("sort_views") or ""
        out["sort_subs"] = f.get("sort_subs") or ""
        return out

    @Slot("QVariantMap")
    def applyDetailFilters(self, m):
        """Store everything the Filters sheet sends in one go and re-render.
        Missing / empty values clear that cut. Text bounds accept 1K, 2.5M …;
        eng_min is typed as a percentage ("4" = 4 %)."""
        m = dict(m or {})
        fmt = str(m.get("format") or "all")
        r = {k: parse_human_number(str(m.get(k) or "")) for k in _RANGE_NUM_KEYS}
        for k in _RANGE_FLOAT_KEYS:
            r[k] = parse_human_float(str(m.get(k) or "").replace("%", "").replace("×", "").replace("x", ""))
        for k, (table, _ch) in _RANGE_PICK_KEYS.items():
            r[k] = _pick_index(table, m.get(k))
        r["format"] = None if fmt == "all" else fmt
        r["sort_views"] = m.get("sort_views") or None
        r["sort_subs"] = m.get("sort_subs") or None
        self._range = r
        self._render_detail()
        # the toolbar's pills / segments / badge bind to detailRange & co.
        self.detailChanged.emit()

    @Slot(str, str, str, str, str, str, str)
    def applyDetailRange(self, subs_min, subs_max, views_min, views_max,
                         fmt, sort_views, sort_subs):
        """Legacy 7-argument entry point (subs/views/format/order only). Keeps
        whatever else the Filters sheet has set."""
        m = self.detailRange
        m.update({"subs_min": subs_min, "subs_max": subs_max,
                  "views_min": views_min, "views_max": views_max,
                  "format": fmt, "sort_views": sort_views, "sort_subs": sort_subs})
        self.applyDetailFilters(m)

    @Slot()
    def clearDetailRange(self):
        self._range = {}
        self._render_detail()
        self.detailChanged.emit()

    @Property("QVariantList", notify=rowsChanged)
    def rows(self):
        return self._detail_visible

    @Property(int, constant=True)
    def pageSize(self):
        """Cards per detail page. Exposed so the QML grid can keep a FIXED
        number of cells alive instead of growing the model from 0 on the first
        section open (v3.53 perf): with a fixed model the 24 card trees are
        built with the page (in the background warm-up) and opening a section
        only re-binds them, instead of constructing 24 layered cards inside the
        click."""
        return NICHE_PAGE_SIZE

    @Property(bool, notify=rowsChanged)
    def detailIsEmpty(self):
        return len(self._detail_filtered) == 0

    @Property(int, notify=rowsChanged)
    def detailPageIndex(self):
        return self._page

    @Property(int, notify=rowsChanged)
    def detailPageCount(self):
        total = len(self._detail_filtered)
        return max(1, (total + NICHE_PAGE_SIZE - 1) // NICHE_PAGE_SIZE)

    @Property(str, notify=rowsChanged)
    def detailPageLabel(self):
        total = len(self._detail_filtered)
        if not total:
            return ""
        first = self._page * NICHE_PAGE_SIZE + 1
        last = min(total, first + NICHE_PAGE_SIZE - 1)
        return tr("{a}–{b} of {n}").format(a=first, b=last, n=total)

    # ── per-row action state ────────────────────────────────────────────
    @Property("QVariantMap", notify=downloadsChanged)
    def downloads(self):
        return self._downloads

    @Property("QVariantList", notify=savedChanged)
    def savedIds(self):
        """Video ids flagged favorite among the cards ON SCREEN — the card's
        bookmark tile binds this for its sticky state.

        v3.44 perf: page-scoped. It used to list every favorite of the whole
        filtered section, and each of the 24 cards converted that list to a JS
        array and indexOf'd it on every evaluation — with thousands of
        favorites that alone was a visible stall on every page change."""
        return self._saved_ids

    @Property("QVariantList", notify=downloadedChanged)
    def downloadedIds(self):
        """Video ids with a finished file on disk, limited to the cards on
        screen (v3.44 perf: same reason as savedIds). The card binds this for
        its Download→Open switch."""
        return self._page_downloaded

    def _sync_page_downloaded(self, emit=True):
        fresh = [v for v in self._page_order() if v in self._downloaded]
        if fresh != self._page_downloaded:
            self._page_downloaded = fresh
            if emit:
                self.downloadedChanged.emit()

    def _page_order(self):
        return [r.get("videoId") for r in self._detail_visible if r.get("videoId")]

    def _refresh_downloaded(self, silent=False):
        """Rebuild the finished-on-disk set from the persisted history.

        Only rows whose file actually exists count — a row whose file was
        moved/deleted must offer Download again, not an Open button that
        immediately reports "file couldn't be found". Rebuilt wholesale so
        entries removed on the Downloads page drop out here too. Emits
        downloadsChanged unless silent (init path)."""
        # a synchronous rebuild is the newest truth: drop any scan in flight
        self._dl_scan_token += 1
        self._downloaded = _scan_downloaded_ids()
        self._sync_page_downloaded(emit=not silent)

    @Slot()
    def refreshDownloaded(self):
        """Re-read the finished-on-disk set — called when the page is shown.

        v1.0.1: off the GUI thread. One os.path.isfile() per finished download
        ran inside the page switch; with a long history, or files on a drive
        that has to spin up / a network share, that stalled the very first
        frame of Search Archive for seconds. The cards keep the set they had
        until the scan lands (it only flips Download / Open)."""
        self._dl_scan_token += 1
        token = self._dl_scan_token

        def worker():
            try:
                fresh = sorted(_scan_downloaded_ids())
            except Exception:       # noqa: BLE001 — best effort
                return
            try:
                self._dlScanned.emit(fresh, token)
            except RuntimeError:    # VM already gone (app closing)
                pass

        threading.Thread(target=worker, name="archive-downloaded-scan",
                         daemon=True).start()

    @Slot(list, int)
    def _on_dl_scanned(self, fresh, token):
        if token != self._dl_scan_token:
            return                  # a newer scan / sync rebuild superseded it
        self._downloaded = set(fresh)
        self._sync_page_downloaded()

    @Slot(str)
    def openDownloaded(self, video_id):
        """Open an already-downloaded video in the OS default player."""
        vid = (video_id or "").strip()
        if not vid:
            return
        path = ""
        try:
            for r in downloads_list():
                if (r.get("video_id") or "") == vid:
                    path = (r.get("filepath") or "").strip()
                    break
        except Exception:           # noqa: BLE001
            path = ""
        if not path or not os.path.isfile(path):
            self._refresh_downloaded()
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return
        try:
            if sys.platform.startswith("win"):
                os.startfile(path)      # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])
            else:
                subprocess.Popen(["xdg-open", path])
        except Exception as exc:        # noqa: BLE001
            self.toast.emit(tr("Could not open: {e}").format(e=exc), "error")

    # ── actions ─────────────────────────────────────────────────────────
    @Slot()
    def reload(self):
        """Re-read the section list from the db. Cheap (two scalar subqueries
        per group, no row blobs), so the page can call it on every show."""
        self._groups_raw = archive_list_groups_full(
            favorites_only=(self._tab == 1))
        self._total_videos = sum(g.get("item_count") or 0
                                 for g in self._groups_raw)
        self._total_favs = sum(g.get("fav_count") or 0 for g in self._groups_raw)
        self._total_runs = sum(g.get("run_count") or 0 for g in self._groups_raw)
        self._derive_groups()

    def _derive_groups(self):
        """Apply the tab + search box to the cached list and flatten for QML.
        Runs on the GUI thread over a handful of dicts — no db re-query."""
        text = (self._search or "").strip().lower()
        out = []
        for g in self._groups_raw:
            if text and text not in (g.get("title") or "").lower():
                continue
            mode = g.get("mode") or "keyword"
            out.append({
                "id": g.get("id"),
                "title": g.get("title") or "—",
                "modeLabel": ("CHANNEL" if mode == "channel"
                              else "FAVORITES" if mode == "favorite"
                              else "VIRAL" if mode == "viral"
                              else "KEYWORD"),
                "modeIcon": ("user" if mode == "channel"
                             else "trending_up" if mode == "viral"
                             else "search"),
                "sourceLabel": ("SCRAPE" if g.get("source") == "scrape"
                                else "API"),
                "itemCount": g.get("item_count") or 0,
                "itemCountText": humanize_count(g.get("item_count") or 0),
                "favCount": g.get("fav_count") or 0,
                "favCountText": humanize_count(g.get("fav_count") or 0),
                "runCount": str(g.get("run_count") or 0),
                "updated": days_ago_str(g.get("updated_at") or ""),
                # Section star (the card's save icon) — distinct from favCount,
                # which counts individually starred videos inside the section.
                "isFavoriteSection": bool(g.get("is_favorite")),
                # Channel sections show the channel's own logo on the card;
                # keyword sections have none and keep the mode glyph.
                "channelThumbId": _thumb_id(g.get("channel_thumb") or ""),
            })
        self._groups = out
        self.changed.emit()

    @Slot(int)
    def openGroup(self, group_id):
        try:
            gid = int(group_id)
        except (TypeError, ValueError):
            return
        group = None
        for g in self._groups_raw:
            if g.get("id") == gid:
                group = g
                break
        if group is None:
            # opened right after a rename/delete raced us — fall back to a
            # direct lookup before giving up
            group = archive_get_group(gid)
        if not group:
            self.toast.emit(tr("Couldn't open that section."), "error")
            return
        rows = archive_get_rows(gid)
        # The sort/filter toolbar works off multiplier / velocity / age_hours /
        # engagement — none of which are stored on the raw archive row — so
        # compute them once here, exactly like the live grid does after a
        # search. Cheap: pure arithmetic over the section's rows.
        compute_niche_metrics(rows)
        self._gid = gid
        self._group = dict(group)
        self._detail_raw = rows
        self._fav_only = False
        self._channels_view = False
        self._sort = 0
        self._page = 0
        self._detail_text = ""
        self._timeframe = len(NICHE_TIMEFRAMES) - 1
        self._range = {}
        self.sortsChanged.emit()
        # Fill the page BEFORE the detail view is revealed. Emitting
        # detailChanged first made QML lay out the whole detail page with 24
        # empty cards and then lay it out again the moment rows arrived —
        # the section-open hitch. Now the one layout that matters happens
        # once, on a grid that already holds its rows.
        self._render_detail()
        self.detailChanged.emit()
        # cards show the saved numbers instantly, then turn live in place.
        # A refresh still running for the PREVIOUS section is dropped.
        self._live_token += 1
        self._live_state = "idle"
        # A beat after the section is on screen: the stale scan + config read
        # are not on the click path, and the request thread starts behind the
        # first paint instead of in front of it.
        QTimer.singleShot(60, self._start_live)
        self._live_timer.start()
        self._live_clock.start()

    @Slot()
    def closeDetail(self):
        self._live_token += 1          # drop any refresh still in flight
        self._live_timer.stop()
        self._live_clock.stop()
        self._set_live("idle")
        self._gid = None
        self._group = None
        self._detail_raw = []
        self._detail_filtered = []
        self._detail_filtered_videos = []
        self._detail_visible = []
        self._channels_view = False
        self._live_pending = {}
        self._page = 0
        self.sortsChanged.emit()
        self.detailChanged.emit()
        self.rowsChanged.emit()

    @Slot()
    def analyzeDetail(self):
        """Send the open section's filtered rows to Niche Scan.

        The filtered set, not the raw group: the section's own toolbar is how the
        user says which subset they mean. Purely local — these rows came out of
        SQLite, so a saved search from three weeks ago can be re-read at set level
        without spending a single API unit."""
        # Always the VIDEO set: in the Channels view _detail_filtered holds
        # aggregates, which are a presentation step and not valid input for a
        # video-level report.
        rows = self._detail_filtered_videos or self._detail_raw
        if not rows:
            self.toast.emit(tr("This section has no rows to analyze."), "error")
            return
        group = self._group or {}
        query = group.get("title") or group.get("key") or ""
        mode = group.get("mode") or "keyword"
        self.analyzeRequested.emit(list(rows), query, mode)

    @Slot(int)
    def deleteGroup(self, group_id):
        try:
            gid = int(group_id)
        except (TypeError, ValueError):
            return
        if archive_delete_group(gid):
            self.toast.emit(tr("Section deleted."), "success")
        else:
            self.toast.emit(tr("Deleting failed."), "error")
        if self._gid == gid:
            self.closeDetail()
        self.reload()

    @Slot(int)
    def toggleGroupSaved(self, group_id):
        """Star / unstar a whole section (the card's save icon, next to rename
        and delete). A starred section shows in the Favorites tab even when
        none of its videos is individually starred."""
        try:
            gid = int(group_id)
        except (TypeError, ValueError):
            return
        current = False
        for g in self._groups_raw:
            if g.get("id") == gid:
                current = bool(g.get("is_favorite"))
                break
        else:
            grp = archive_get_group(gid)
            if not grp:
                return
            current = bool(grp.get("is_favorite"))
        if not archive_set_group_favorite(gid, not current):
            self.toast.emit(tr("Saving failed."), "error")
            return
        self.toast.emit(
            tr("Section saved to favourites.") if not current
            else tr("Section removed from favourites."),
            "success" if not current else "info")
        # reload(): in the Favorites tab an unstarred section must vanish, and
        # everywhere the card has to pick up the new star state.
        self.reload()

    @Slot(int, str)
    def renameGroup(self, group_id, title):
        try:
            gid = int(group_id)
        except (TypeError, ValueError):
            return
        title = (title or "").strip()
        if not title:
            return
        if archive_rename_group(gid, title):
            self.toast.emit(tr("Section renamed."), "success")
            if self._gid == gid and self._group:
                self._group["title"] = title
                self.detailChanged.emit()
        else:
            self.toast.emit(tr("Renaming failed."), "error")
        self.reload()

    @Slot()
    def clearAll(self):
        if archive_clear_all():
            self.toast.emit(tr("Archive cleared."), "success")
        else:
            self.toast.emit(tr("Clearing failed."), "error")
        self.closeDetail()
        self.reload()

    @Slot(int)
    def gotoDetailPage(self, index):
        index = max(0, min(int(index), self.detailPageCount - 1))
        if index != self._page:
            self._page = index
            # v3.44 perf: the filtered + sorted list is already cached in
            # _detail_filtered — flipping pages is just a new slice. It used
            # to re-filter and re-sort the WHOLE section on every click.
            self._publish_page()

    # ── per-row actions ─────────────────────────────────────────────────
    @Slot(str)
    def deleteItem(self, key):
        if self._gid is None or not key:
            return
        if archive_delete_item(self._gid, key):
            self._detail_raw = [r for r in self._detail_raw
                                if r.get("_archive_key") != key]
            self._render_detail()
            self.toast.emit(tr("Removed from archive."), "success")
        else:
            self.toast.emit(tr("Deleting failed."), "error")

    @Slot(str)
    def toggleSaved(self, video_id):
        """The NicheCard bookmark action, retargeted at the archive: star /
        unstar the row inside the section it already lives in. The row is on
        screen, so it is already archived — this is a straight flag flip,
        never a re-file into another group."""
        raw = self._raw_by_key.get(video_id)
        if raw is None or self._gid is None:
            self.toast.emit(tr("This result is no longer on screen."), "error")
            return
        was_fav = bool(raw.get("_is_favorite"))
        favorite_mark_item(self._gid, raw, favorite=not was_fav)
        raw["_is_favorite"] = not was_fav
        if self._fav_only:
            # the row may have to leave the favorites-only view
            self._render_detail(keep_page=True)
        else:
            # v3.44 perf: a star flip changes neither the filter nor the
            # order, so only the sticky-star list moves — the grid isn't
            # rebuilt and nothing re-sorts under the cursor.
            self._sync_page_saved()
        title = (raw.get("title") or "")[:60]
        self.toast.emit(
            (tr('"{v}" was added to Favorites.') if not was_fav
             else tr('"{v}" was removed from Favorites.')).format(v=title),
            "success" if not was_fav else "info")

    @Slot(str)
    def sendToIdeas(self, video_id):
        """Tick a card's video as a reference on the AI Ideas page.

        v3.42: this used to call db_add_idea(), which writes the legacy
        `ideas` table that the QML AI Ideas page never reads — so the ✦ tile
        on every card looked dead. The raw row now goes to IdeasVM through
        `ideas_sink` (wired in main_qml.py), which ticks it in the picker.
        """
        raw = self._raw_by_key.get(video_id)
        if not raw or not (raw.get("video_id") or raw.get("video_url")):
            self.toast.emit(tr("This row is missing video info."), "error")
            return
        sink = self.ideas_sink
        if not callable(sink):
            self.toast.emit(tr("AI Ideas isn't ready yet — try again in a moment."), "error")
            return
        try:
            added, _already = sink([dict(raw)], tr("Search Archive"))
        except Exception as exc:          # noqa: BLE001 — surfaced to the user
            self.toast.emit(str(exc), "error")
            return
        if added:
            self.toast.emit(tr("Added to AI Ideas — it's ticked as a reference there."), "success")
        else:
            self.toast.emit(tr("Already picked on AI Ideas."), "info")

    @Slot(str)
    def openUrl(self, url):
        open_external_url(url)

    @Slot(str)
    def copyLink(self, url):
        if not url:
            return
        clip = QGuiApplication.clipboard()
        if clip is None:
            self.toast.emit(tr("Clipboard is unavailable."), "error")
            return
        clip.setText(url)
        self.toast.emit(tr("Link copied: {url}").format(url=url), "success")

    # ── thumbnail download ─────────────────────────────────────────────────
    # Same behaviour and shared folder as the Niche Finder card: original-
    # resolution save, folder asked once then remembered in config.
    @Property(bool, notify=changed)
    def hasThumbFolder(self):
        return bool(thumb_folder())

    @Slot(str)
    def setThumbFolder(self, folder):
        if remember_thumb_folder(folder):
            self.changed.emit()

    @Slot(str, str, bool)
    def downloadThumb(self, thumb_id, title, is_short=False):
        """Save a card's thumbnail. `is_short` picks the output frame — the card
        passes its own format, so a Short exports 1080×1920 and long-form
        1920×1080."""
        problem = start_thumb_download(thumb_id, title, self._thumbDone, tr,
                                       is_short=bool(is_short))
        if problem is not None:
            self.toast.emit(problem[0], problem[1])

    @Slot(str, str)
    def _on_thumb_done(self, path, error):
        if error or not path:
            self.toast.emit(tr("Couldn't save the thumbnail."), "error")
            return
        self.toast.emit(tr("Thumbnail saved."), "success")

    # ── export ──────────────────────────────────────────────────────────
    @Slot(str)
    def exportCurrent(self, path):
        """Export the section as currently viewed — same favorites-only /
        sort state the cards on screen show, not a hidden full dump.

        Always the VIDEO set: the Channels view is an aggregation of these
        rows, and the export format is per-video. In Channels view the export
        therefore carries every matched video (the full evidence behind the
        leaderboard), not one synthesized row per channel."""
        rows = self._detail_filtered_videos or self._detail_filtered
        if not rows:
            self.toast.emit(tr("Nothing to export."), "error")
            return
        path = local_path_from_url(path)
        payload = []
        for r in rows:
            payload.append({
                "Title": r.get("title", ""),
                "Channel": r.get("channel_title", ""),
                "Subscribers": r.get("subscriber_count"),
                "Views": r.get("view_count", 0),
                "Views/Subs": round(r["multiplier"], 2) if r.get("multiplier") else "",
                "Views per hour": round(r.get("velocity", 0)),
                "Published": r.get("published_at", ""),
                "Duration": fmt_duration(r.get("duration_s", 0)),
                "Format": "Shorts" if r.get("is_short") else "Long-form",
                "Favorite": "yes" if r.get("_is_favorite") else "",
                "Video URL": r.get("video_url", ""),
                "Channel URL": r.get("channel_url", ""),
            })
        fmt = ("xlsx" if path.lower().endswith(".xlsx")
               else ("jsonl" if path.lower().endswith(".jsonl") else "csv"))
        try:
            write_export(payload, path, fmt)
        except Exception as exc:
            self.toast.emit(tr("Export failed: {err}").format(err=exc), "error")
            return
        self.toast.emit(tr("Exported {n} rows.").format(n=len(payload)), "success")

    # ── download (same ladder as the Niche Finder card action) ──────────
    @Slot(str, int)
    def startDownload(self, video_id, quality_index):
        raw = self._raw_by_key.get(video_id)
        if not raw:
            self.toast.emit(tr("This row is no longer on screen."), "error")
            return
        url = raw.get("video_url") or (
            f"https://www.youtube.com/watch?v={video_id}" if video_id else "")
        if not url:
            self.toast.emit(tr("This item has no video URL."), "error")
            return
        entry = self._downloads.get(video_id) or {}
        if entry.get("state") == "running":
            return

        quality = (DOWNLOAD_QUALITY_PRESETS[quality_index]
                   if 0 <= quality_index < len(DOWNLOAD_QUALITY_PRESETS)
                   else quality_by_key("best"))
        # Attach the output format picked in the quality dialog (MP4/MKV/WEBM,
        # or MP3/M4A/OPUS/WAV/FLAC for audio).
        quality = with_container(quality)
        # v1.2: the audio track picked in the quality dialog (dubbed videos)
        quality = with_audio_lang(quality, video_id=video_id)
        target_dir = video_download_dir("YouTube")
        try:
            os.makedirs(target_dir, exist_ok=True)
        except OSError as exc:
            self.toast.emit(str(exc), "error")
            return

        # proxy / cookies must be read on the GUI thread — same reason as
        # NicheVM.startDownload (yt-dlp does its own networking).
        cfg = load_app_config()
        proxy_url = (cfg.get("ai_proxy", "") or "").strip()
        cookies_browser = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        self._set_download(video_id, "running", 0, tr("Preparing…"),
                           url=url, qualityKey=quality_storage_key(quality))
        clear_cancel(video_id)   # drop any stale stop flag from a previous run
        self.toast.emit(tr("Download started — {t}").format(
            t=(raw.get("title") or "")[:60]), "download")
        # quality_key + video_url are persisted so a STOPPED download can be
        # resumed at the same quality.
        downloads_upsert(
            video_id, title=raw.get("title", ""),
            thumbnail_url=raw.get("thumbnail_url", ""),
            quality_label=quality_display_label(quality),
            quality_key=quality_storage_key(quality), video_url=url,
            status="downloading", progress=0, file_size=0,
            channel_title=raw.get("channel_title", ""),
            channel_thumb_url=raw.get("channel_thumb_url", ""),
            channel_url=raw.get("channel_url", ""),
            subscriber_count=raw.get("subscriber_count"),
            subs_hidden=raw.get("subs_hidden"))

        self._launch_dl_worker(video_id, url, target_dir, quality,
                               proxy_url, cookies_browser)

    @Slot(str)
    def resumeDownload(self, video_id):
        """Restart a download this card had stopped, at the same quality.

        The card's stopped entry remembers the url + preset, so this skips the
        quality picker. yt-dlp keeps its .part file, so it continues from roughly
        where it left off.
        """
        entry = self._downloads.get(video_id) or {}
        if entry.get("state") == "running":
            return
        raw = self._raw_by_key.get(video_id) or {}
        url = (entry.get("url") or raw.get("video_url")
               or (f"https://www.youtube.com/watch?v={video_id}" if video_id else ""))
        if not url:
            self.toast.emit(tr("This item has no video URL."), "error")
            return
        quality = quality_by_key(entry.get("qualityKey") or "best")
        target_dir = video_download_dir("YouTube")
        try:
            os.makedirs(target_dir, exist_ok=True)
        except OSError as exc:
            self.toast.emit(str(exc), "error")
            return

        cfg = load_app_config()
        proxy_url = (cfg.get("ai_proxy", "") or "").strip()
        cookies_browser = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        clear_cancel(video_id)
        resumed_at = int(entry.get("pct") or 0)
        self._set_download(video_id, "running", resumed_at,
                           tr("Resuming…"), cancelling=False,
                           url=url, qualityKey=quality_storage_key(quality))
        downloads_upsert(video_id, status="downloading", error_message="",
                         create_if_missing=False)
        self.toast.emit(tr("Resuming download…"), "download")
        self._launch_dl_worker(video_id, url, target_dir, quality,
                               proxy_url, cookies_browser,
                               resume_pct=resumed_at)

    def _launch_dl_worker(self, video_id, url, target_dir, quality,
                          proxy_url, cookies_browser, resume_pct=0):
        """Run one download on a daemon thread. Shared by startDownload and
        resumeDownload so both report progress and cancellation identically."""
        def worker():
            # A raised exception must still reach _dlDone — without this guard
            # the thread died silently and the row sat on "downloading" forever.
            try:
                ok, message, filepath = download_video(
                    url, target_dir, quality,
                    on_status=lambda t, v=video_id: self._dlStatus.emit(v, t),
                    on_progress=lambda p, v=video_id: self._dlProgress.emit(v, p),
                    on_detail=lambda d, t, s, e, fd, ft, v=video_id:
                        self._dlDetail.emit(v, d, t, s, e, fd, ft),
                    on_resolved=lambda px, lbl, v=video_id:
                        self._dlResolved.emit(v, px, lbl),
                    on_meta=lambda m, v=video_id: self._dlMeta.emit(v, m),
                    proxy_url=proxy_url, cookies_browser=cookies_browser,
                    should_cancel=lambda v=video_id: is_cancelled(v),
                    resume_pct=resume_pct)
            except Exception as exc:      # noqa: BLE001
                log_crash("ArchiveVM download worker failed:\n" + str(exc))
                ok, message, filepath = False, str(exc), ""
            self._dlDone.emit(video_id, ok, message, filepath)

        threading.Thread(target=worker, daemon=True).start()

    # ── download signal handlers (GUI thread) ───────────────────────────
    def _set_download(self, video_id, state, pct, text, **extra):
        """Publish one card's download state.

        `extra` merges into the existing entry rather than replacing it, so a
        status line arriving between two progress ticks doesn't wipe the byte
        counts the card is animating from. Same shape as NicheVM's.

        The same values are mirrored into the SHARED live-progress store so the
        Downloads page shows this download moving too — otherwise a download
        started from a saved section appeared there stuck at 0% until you
        navigated away and back.
        """
        prev_state = (self._downloads.get(video_id) or {}).get("state")
        entry = dict(self._downloads.get(video_id) or {})
        entry.update({"state": state, "pct": pct, "text": text})
        entry.update(extra)
        entry.setdefault("done", 0)
        entry.setdefault("total", 0)
        entry.setdefault("speed", 0.0)
        entry.setdefault("eta", 0)
        entry.setdefault("fragDone", 0)
        entry.setdefault("fragTotal", 0)
        self._downloads[video_id] = entry
        if state == "running" and prev_state == "running":
            # coalesced: at most one repaint per 100 ms while bytes move
            if not self._dl_emit.isActive():
                self._dl_emit.start()
        else:
            # a state change (start / done / stopped / error) shows at once
            self._dl_emit.stop()
            self.downloadsChanged.emit()
        if state == "running":
            dlp.publish(video_id, running=True, pct=pct, text=text,
                        cancelling=bool(entry.get("cancelling")),
                        done=entry["done"], total=entry["total"],
                        speed=entry["speed"], eta=entry["eta"],
                        fragDone=entry["fragDone"], fragTotal=entry["fragTotal"])
        else:
            dlp.clear(video_id)

    def _ignore_tick(self, video_id):
        """True when a tick from a worker should be dropped: the user stopped
        this download, so its remaining in-flight callbacks must not write to
        the DB or revive the card's progress."""
        entry = self._downloads.get(video_id) or {}
        return bool(entry.get("cancelling")) or is_cancelled(video_id)

    @Slot(str)
    def cancelDownload(self, video_id):
        """Stop a running download for real. The worker's yt-dlp hook sees the
        shared cancel flag and unwinds the download, so nothing keeps pulling
        bytes in the background after the card says it stopped."""
        entry = self._downloads.get(video_id) or {}
        if entry.get("state") != "running":
            return
        request_cancel(video_id)
        self._set_download(video_id, "running", entry.get("pct", 0),
                           tr("Stopping…"), cancelling=True)
        self.toast.emit(tr("Stopping download…"), "info")

    @Slot(str, str)
    def _on_dl_status(self, video_id, text):
        if self._ignore_tick(video_id):
            return
        entry = self._downloads.get(video_id) or {}
        merging = text == tr("Merging…")
        if merging:
            # Mirror the post-processing state into the Downloads-page row, or
            # it kept saying "downloading" with a determinate 99% bar while the
            # mux / MP3 conversion ran (only DownloadsVM used to write this).
            # The old speed/ETA belong to the finished transfer, not to this.
            downloads_upsert(video_id, status="merging", create_if_missing=False)
        self._set_download(video_id, entry.get("state", "running"),
                           entry.get("pct", 0), text,
                           **({"speed": 0.0, "eta": 0} if merging else {}))

    @Slot(str, int)
    def _on_dl_progress(self, video_id, pct):
        if self._ignore_tick(video_id):
            return
        try:
            pct_i = int(pct)
        except (TypeError, ValueError):
            pct_i = 0
        # 100 belongs to the finished file on disk (_on_dl_done), never to a
        # running card — without this clamp a late 100 tick left the button
        # showing 100% while the file wasn't openable yet.
        pct_i = max(0, min(99, pct_i))
        self._set_download(video_id, "running", pct_i,
                           tr("{p}%").format(p=pct_i))
        # UPDATE-ONLY: a Downloads-page row the user deleted mid-flight must not
        # be INSERTed back by a late tick from this still-unwinding worker.
        # Throttled DB write (see DownloadsVM): live card moves every tick.
        now = time.monotonic()
        last = self._last_db_write.get(video_id)
        if (last is None or pct_i >= 99
                or pct_i - int(last[1]) >= 2 or now - float(last[0]) >= 2.0):
            self._last_db_write[video_id] = (now, pct_i)
            downloads_upsert(video_id, status="downloading", progress=pct_i,
                             create_if_missing=False)

    @Slot(str, int, int, float, int, int, int)
    def _on_dl_detail(self, video_id, done, total, speed, eta, frag_done, frag_total):
        if self._ignore_tick(video_id):
            return
        entry = self._downloads.get(video_id) or {}
        self._set_download(video_id, entry.get("state", "running"),
                           entry.get("pct", 0), entry.get("text", ""),
                           done=done, total=total, speed=speed, eta=eta,
                           fragDone=frag_done, fragTotal=frag_total)

    @Slot(str, int, str)
    def _on_dl_resolved(self, video_id, height_px, label):
        """The download reported the resolution it ACTUALLY delivered.

        This row's download is mirrored into the Downloads page's table, labelled
        at start with the tier the user picked. A video that only ships 720p
        answers a 1080p request with 720p, so the label is corrected here to match
        the file on disk. UPDATE-ONLY — a deleted row stays deleted.
        """
        if not label or self._ignore_tick(video_id):
            return
        downloads_upsert(video_id, quality_label=label, create_if_missing=False)

    @Slot(str, "QVariantMap")
    def _on_dl_meta(self, video_id, meta):
        """yt-dlp told us who made this video — complete the library row.

        Runs on the GUI thread (the worker emits a queued signal) so it never
        races this page's own reads of the same SQLite file. Without it a video
        downloaded from a page that had not enriched its channel opened in the
        player with no subscriber count and an initials disc instead of a logo.
        """
        downloads_apply_channel_meta(video_id, dict(meta or {}))

    @Slot(str, bool, str, str)
    def _on_dl_done(self, video_id, ok, message, filepath):
        entry = self._downloads.get(video_id) or {}
        was_cancelling = bool(entry.get("cancelling"))
        clear_cancel(video_id)
        self._last_db_write.pop(video_id, None)
        # A user stop is not a failure. The card is parked as "stopped" at the
        # percent it reached (keeping the url + quality it was started with) so
        # its button turns into a play arrow and the download can be picked back
        # up; the Downloads-page row is parked the same way.
        if message == DOWNLOAD_CANCELLED or was_cancelling:
            stopped_pct = int(entry.get("pct") or 0)
            self._set_download(video_id, "stopped", stopped_pct,
                               tr("Stopped"), cancelling=False,
                               speed=0.0, eta=0)
            downloads_upsert(video_id, status="stopped", progress=stopped_pct,
                             error_message="", create_if_missing=False)
            self.toast.emit(tr("Download stopped."), "info")
            return
        self._set_download(video_id, "done" if ok else "error",
                           100 if ok else 0,
                           tr("Open") if ok else tr("Failed"),
                           speed=0.0, eta=0)
        if ok and filepath and os.path.isfile(filepath):
            # The card's button flips to Open immediately (downloadsChanged
            # fired from _set_download above; downloadedIds re-syncs here).
            self._downloaded.add(video_id)
            self._sync_page_downloaded()
        downloads_upsert(video_id, status="done" if ok else "error",
                         progress=100 if ok else 0,
                         filepath=filepath if ok else None,
                         error_message=None if ok else message,
                         file_size=file_size_of(filepath) if ok else 0,
                         create_if_missing=False)
        if ok:
            self.toast.emit(tr("Download finished — {p}").format(
                p=os.path.basename(filepath or "")), "success")
        else:
            self.toast.emit(message or tr("Download failed"), "error")
        # v3.40: away notice in the corner of the screen
        announce_download(video_id, ok, message, filepath)

    # ── helpers ─────────────────────────────────────────────────────────
    # ── v3.43: live stats for the open section ───────────────────────────
    @Property(str, notify=liveChanged)
    def liveState(self):
        return self._live_state

    @Property(bool, notify=liveChanged)
    def liveBusy(self):
        return self._live_state == "refreshing"

    @Property(str, notify=liveChanged)
    def liveText(self):
        st = self._live_state
        if st == "refreshing":
            if self._live_total > 0:
                return tr("Updating live numbers… {d}/{t}").format(
                    d=min(self._live_done, self._live_total), t=self._live_total)
            return tr("Updating live numbers…")
        if st == "nokey":
            return tr("Saved numbers · add a YouTube API key for live ones")
        ago = self._oldest_stats_text()
        if st == "quota":
            return tr("API quota used up · numbers from {ago}").format(ago=ago)
        if st == "error":
            return tr("Couldn't update · numbers from {ago}").format(ago=ago)
        if st == "live":
            return tr("Live · updated {ago}").format(ago=ago)
        return ""

    @Property(int, notify=liveChanged)
    def liveMissing(self):
        return self._live_missing

    def _oldest_stats_text(self):
        ages = [stats_age_s(r) for r in self._detail_raw if r.get("video_id")]
        known = [a for a in ages if a is not None]
        if not known:
            return tr("when it was saved")
        a = int(max(known))
        if a < 60:
            return tr("just now")
        if a < 3600:
            return tr("{n}m ago").format(n=a // 60)
        if a < 86400:
            return tr("{n}h ago").format(n=a // 3600)
        return tr("{n}d ago").format(n=a // 86400)

    def _set_live(self, state):
        self._live_state = state
        self.liveChanged.emit()

    @Slot()
    def refreshLive(self):
        """The header's ↻: re-read every row of the open section now."""
        self._start_live(force=True)

    def _live_auto(self):
        gui = QGuiApplication.instance()
        if gui is not None and gui.applicationState() != Qt.ApplicationActive:
            return
        self._start_live(force=False)

    def _on_app_state(self, state):
        # back in front after a while away: catch up straight away
        if state == Qt.ApplicationActive and self._gid is not None:
            self._start_live(force=False)

    def _start_live(self, force=False):
        if self._gid is None or self._live_state == "refreshing":
            return
        rows = [r for r in self._detail_raw if r.get("video_id")]
        self._live_missing = sum(1 for r in rows if r.get("_live_missing"))
        if not rows:
            self._set_live("idle")
            return
        keys = youtube_api_keys(load_app_config())
        if not keys:
            self._set_live("nokey")
            return
        todo = rows if force else [r for r in rows if is_stale(r)]
        if not todo:
            self._set_live("live")
            return
        # the cards on screen first, so what the user is looking at turns live
        # in the first second; the rest of the section follows
        start = self._page * NICHE_PAGE_SIZE
        on_page = {_live_row_key(r)
                   for r in self._detail_filtered[start:start + NICHE_PAGE_SIZE]}
        todo.sort(key=lambda r: 0 if _live_row_key(r) in on_page else 1)
        self._live_page_keys = on_page
        self._live_dirty = False
        self._live_pending = {}
        self._live_token += 1
        token, gid = self._live_token, self._gid
        self._live_done, self._live_total = 0, len(todo)
        self._set_live("refreshing")
        snapshot = [dict(r) for r in todo]

        def worker():
            def chunk(fresh):
                archive_update_rows(gid, fresh)       # persist, own connection
                self._liveChunk.emit(gid, token, fresh)
            err = ""
            try:
                refresh_rows_live(snapshot, keys,
                                  stop_check=lambda: token != self._live_token,
                                  on_chunk=chunk)
            except ScrapeCancelled:
                return
            except LiveStatsError as exc:
                err = exc.code
            except Exception as exc:                  # noqa: BLE001
                log_crash("Archive live stats failed:\n" + repr(exc))
                err = "error"
            self._liveFinished.emit(gid, token, err)

        threading.Thread(target=worker, daemon=True, name="archive-live").start()

    def _apply_live_rows(self, fresh_by_key):
        """Merge freshly fetched rows into the open section, preserving stars.

        Pool-relative fields (outlier median, Gold Score) depend on EVERY row,
        so this is a full-section pass. It is deliberately called at most twice
        per refresh — once for the visible page, once for the rest at the end —
        instead of once per 50-row chunk.
        """
        if not fresh_by_key:
            return
        merged = []
        for r in self._detail_raw:
            k = r.get("_archive_key") or r.get("video_id")
            new = fresh_by_key.get(k)
            if new is None:
                merged.append(r)
                continue
            new = dict(new)
            # the star may have been toggled while the request was out
            new["_is_favorite"] = r.get("_is_favorite", False)
            merged.append(new)
        # multiplier / views-per-hour / outlier ratio from the NEW numbers
        compute_niche_metrics(merged)
        self._detail_raw = merged
        self._live_missing = sum(1 for r in merged if r.get("_live_missing"))

    @Slot(int, int, list)
    def _on_live_chunk(self, gid, token, fresh):
        if token != self._live_token or gid != self._gid:
            return
        by_key = {}
        for r in fresh:
            k = r.get("_archive_key") or r.get("video_id")
            if k:
                by_key[k] = r
        self._live_done += len(fresh)
        if not by_key:
            self.liveChanged.emit()
            return
        # A 1,300-row section refreshes in ~26 chunks. Rebuilding the whole
        # section and recomputing its pool metrics per chunk cost ~10 ms on the
        # GUI thread each time — a dropped frame roughly once a second for the
        # length of the refresh, which is what a crowded section felt like while
        # scrolling. Only rows on screen are applied immediately; every other
        # chunk is parked here and merged in one pass when the refresh ends.
        self._live_pending.update(by_key)
        on_page = set(by_key) & getattr(self, "_live_page_keys", set())
        if on_page:
            subset = {k: by_key[k] for k in on_page}
            self._apply_live_rows(subset)
            for k in on_page:
                self._live_pending.pop(k, None)
            self.detailChanged.emit()      # header totals (views, gems …)
            self._render_detail(keep_page=True)
            self._live_dirty = False
        if len(by_key) > len(on_page):
            self._live_dirty = True
        self.liveChanged.emit()

    @Slot(int, int, str)
    def _on_live_finished(self, gid, token, error):
        if token != self._live_token or gid != self._gid:
            return
        if self._live_pending:
            self._apply_live_rows(self._live_pending)
            self._live_pending = {}
            self._live_dirty = False
            self.detailChanged.emit()
            self._render_detail(keep_page=True)
        elif getattr(self, "_live_dirty", False):
            self._live_dirty = False
            self.detailChanged.emit()
            self._render_detail(keep_page=True)
        if error == "quota":
            self._set_live("quota")
            self.toast.emit(tr("YouTube API quota is used up, so these are the last saved numbers."), "info")
        elif error == "nokey":
            self._set_live("nokey")
        elif error:
            self._set_live("error")
        else:
            self._set_live("live")

    def _render_detail(self, keep_page=False):
        """Filter + sort the open section, then flatten the current page for
        QML. keep_page=True keeps the pager where it is (favorite toggles and
        same-page jumps shouldn't yank the user back to page 1).

        The pipeline mirrors the Niche Finder's own results toolbar so a saved
        section behaves identically: favorites-only → range/text/timeframe
        filters (apply_niche_filters) → sort. The range flyout's Views/Subs
        low↔high buttons override the sort combo when either is set (see
        sort_archive_quick), exactly as they do on the live grid."""
        rows = list(self._detail_raw)
        if self._fav_only:
            rows = [r for r in rows if r.get("_is_favorite")]

        # range + text + timeframe, all in one in-memory pass
        rng = self._range
        filters = {k: rng.get(k) for k in _RANGE_NUM_KEYS
                   + ("mult_min", "outlier_min", "vel_min", "format",
                      "sort_views", "sort_subs")}
        eng = rng.get("eng_min")
        filters["eng_min"] = eng / 100.0 if eng is not None else None
        dur = NICHE_DURATIONS[_pick_index(NICHE_DURATIONS, rng.get("duration"))]
        filters["dur_min_s"], filters["dur_max_s"] = dur[1], dur[2]
        filters["channel_max_age_days"] = NICHE_CHANNEL_AGES[
            _pick_index(NICHE_CHANNEL_AGES, rng.get("channel_age"))][1]
        filters["ch_videos_max"] = NICHE_CHANNEL_UPLOADS[
            _pick_index(NICHE_CHANNEL_UPLOADS, rng.get("uploads"))][1]
        per_channel = NICHE_PER_CHANNEL[
            _pick_index(NICHE_PER_CHANNEL, rng.get("per_channel"))][1]
        filters["text"] = self._detail_text
        tf = NICHE_TIMEFRAMES[self._timeframe][1] if 0 <= self._timeframe < len(NICHE_TIMEFRAMES) else None
        filters["days"] = tf
        # A saved section can be weeks old and its rows come from mixed
        # sources: a row whose publish date couldn't be read must NOT pass
        # "Last 24 Hours" just because its age is unknown (it used to).
        filters["strict_days"] = True
        is_channel = (self._group or {}).get("mode") == "channel"
        if is_channel:
            # one channel → subscriber bounds/sorts mean nothing (the flyout
            # hides them; this keeps a stale value from leaking through)
            for k in _CHANNEL_ONLY_KEYS + ("channel_max_age_days", "ch_videos_max"):
                filters.pop(k, None)
            per_channel = 0
        rows = apply_niche_filters(rows, filters)

        sort_views = filters.get("sort_views")
        sort_subs = filters.get("sort_subs")
        sort_i = self._sort if self._sort in self._visible_sorts() else 0
        key = _SORTS[sort_i][1]
        if sort_views or sort_subs:
            rows = sort_archive_quick(rows, sort_subs, sort_views)
        else:
            rows = sort_niche_rows(rows, key)
        # after the sort, so each channel keeps its BEST rows — a keyword
        # section merged over many runs piles up one prolific channel
        if per_channel:
            rows = cap_per_channel(rows, per_channel)

        # Analysis / export of the VIDEO set must stay possible while the
        # Channels view is on: aggregation is a presentation step, and the
        # aggregates are not valid inputs for a video-level report.
        self._detail_filtered_videos = rows
        if self._channels_view:
            rows = aggregate_by_channel(rows)
            # Re-sort the aggregates by the SAME user choice: channel-level
            # multiplier / views / subscribers, not the order the constituent
            # videos happened to have.
            if sort_views or sort_subs:
                rows = sort_archive_quick(rows, sort_subs, sort_views)
            else:
                rows = sort_niche_rows(rows, key)

        self._detail_filtered = rows
        if not keep_page:
            self._page = 0
        self._page = min(self._page, self.detailPageCount - 1)
        self._publish_page()

    def _publish_page(self):
        """Slice the current page out of the cached filtered list and hand it
        to QML. Cheap (24 rows), so page flips call this directly."""
        rows = self._detail_filtered
        start = self._page * NICHE_PAGE_SIZE
        page_rows = rows[start:start + NICHE_PAGE_SIZE]
        _prefetch_page_thumbs(page_rows,
                              rows[start + NICHE_PAGE_SIZE:start + 2 * NICHE_PAGE_SIZE])
        self._detail_visible = [self._row_for_qml(r, channel=self._channels_view)
                                for r in page_rows]

        # keep the raw rows reachable by both keys the cards hand back: the
        # archive key (favorite/delete/send-to-ideas) and the video id
        # (download, which the shared QualityPicker passes).
        self._raw_by_key = {}
        for r in page_rows:
            # A channel card's actions (star, ideas, download) target its best
            # video, so that VIDEO row — not the aggregate — must be reachable
            # by the id the card sends back.
            if self._channels_view:
                r = r.get("best_video") or r
            key_ = r.get("_archive_key")
            if key_:
                self._raw_by_key[key_] = r
            vid = r.get("video_id") or ""
            if vid:
                self._raw_by_key[vid] = r

        # rows first, then the per-card lookups that depend on them
        self.rowsChanged.emit()
        self._sync_page_saved()
        self._sync_page_downloaded()

    def _sync_page_saved(self):
        """Sticky-star list for the cards on screen (see savedIds)."""
        saved = []
        for v in self._page_order():
            raw = self._raw_by_key.get(v)
            if raw is not None and raw.get("_is_favorite"):
                saved.append(v)
        if saved != self._saved_ids:
            self._saved_ids = saved
            self.savedChanged.emit()

    def _row_for_qml(self, r, channel=False):
        """Flatten a stored row into the plain-string dict the QML cards read
        (same field names as NicheVM._row_for_qml, so the card designs stay in
        sync) plus the archive-only fields: archiveKey, isFavorite, seen.

        In the Channels view `r` is an aggregate produced by
        aggregate_by_channel(); its archive-only fields come from the hero
        (best_video) row, because every action on a channel card — star,
        ideas, download — targets that one video.
        """
        bv = (r.get("best_video") or {}) if channel else {}
        src = bv if channel else r
        subs = r.get("subscriber_count")
        subs_txt = (tr("hidden") if r.get("subs_hidden")
                    else (humanize_count(subs) if subs is not None else "—"))
        mult = r.get("multiplier")
        eng = r.get("engagement")
        base = {
            "isChannel": channel,
            "videoId": r.get("video_id", ""),
            "channelId": r.get("channel_id", ""),
            "archiveKey": src.get("_archive_key", ""),
            "title": r.get("title", "") or r.get("channel_title", ""),
            "channelTitle": r.get("channel_title", "—"),
            "channelUrl": r.get("channel_url", ""),
            "videoUrl": r.get("video_url", ""),
            "thumbId": _thumb_id(r.get("thumbnail_url", "")),
            "channelThumbId": _thumb_id(r.get("channel_thumb_url", "")),
            "subsText": subs_txt,
            "views": humanize_count(r.get("view_count", 0) or 0),
            "multiplier": format_multiplier(mult) if mult is not None else "—",
            "multiplierValue": float(mult) if mult is not None else 0.0,
            "isGem": bool(is_gem_row(r)),
            "goldScore": int(r.get("gold_score") or 0),
            "goldTier": r.get("gold_tier") or "",
            "duration": fmt_duration(r.get("duration_s", 0)),
            # Whether this row is a Short — the card passes it to downloadThumb
            # so a Short's cover exports 1080×1920 and long-form 1920×1080.
            "isShort": bool(r.get("is_short")),
            "age": days_ago_str(r.get("published_at") or ""),
            "ageShort": _age_short(r.get("published_at") or ""),
            "perHour": humanize_count(r.get("velocity", 0) or 0),
            "engagement": (f"{eng * 100:.1f}%" if eng else "—"),
            "langLabel": _lang_label(r),
            "viralTag": (f"#{r.get('viral_rank')} {r.get('viral_region') or ''}".strip()
                         if r.get("viral_rank") else ""),
            "isFavorite": bool(src.get("_is_favorite")),
            "firstSeen": days_ago_str(src.get("_first_seen") or ""),
            "lastSeen": days_ago_str(src.get("_last_seen") or ""),
            # v3.43: YouTube no longer returns this video (deleted / private)
            "unavailable": bool(src.get("_live_missing")),
        }
        if channel:
            base.update(_channel_card_fields(r))
            # The card's fourth stat is how many views this channel drew
            # across ALL matched videos, not just the hero's.
            base["views"] = humanize_count(r.get("view_count", 0) or 0)
        return base
