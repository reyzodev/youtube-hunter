"""app.qml_backend.vm.niche_vm - YouTube Hunter (QML).

ViewModel behind NichePage.qml. Owns the Niche Finder form state, runs a real
discovery + enrichment search on a worker thread, caches the fetched pool, and
re-filters/sorts it in-process (zero API calls) as the user moves the sliders.

Every bit of business logic is reused straight from app.core.niche.* and
app.core.youtube_api / quota — this file only orchestrates them and marshals
rows onto the GUI thread, exactly like the legacy NichePageMixin. The scarce
resource is search.list (its own 100/day bucket); enrichment is cheap; and a
fetched pool is cached so slider moves never spend quota. The QWidgets app is
untouched.
"""

import base64
import math
import os
import statistics
import subprocess
import sys
import threading
import time
import traceback
from datetime import datetime, timezone

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication

from app.config import load_app_config, save_app_config
from app.core.db.archive import (
    archive_get_group, archive_get_rows, archive_save_search,
    archive_update_rows)
from app.core.db.downloads import (downloads_apply_channel_meta,
                                    downloads_list, downloads_upsert,
                                    file_size_of)
from app.core.db.favorites import (
    favorite_ensure_channel_group, favorite_mark_item, favorite_resolve_group_id)
from app.core.db.niche_cache import (niche_cache_fetched_at, niche_cache_get,
                                     niche_cache_key, niche_cache_put)
from app.core.download import (
    DOWNLOAD_CANCELLED, DOWNLOAD_QUALITY_PRESETS, clear_cancel, download_video,
    is_cancelled, quality_by_key, quality_display_label,
    quality_storage_key, request_cancel, with_audio_lang, with_container)
from app.core.exports import write_export
from app.core.net import explain_network_error
from app.core.thumbs import prefetch_thumbs
from app.core.niche.config import (
    NICHE_DEPTH_TARGETS, NICHE_DEPTHS, NICHE_LANGS, NICHE_MAX_POOL, NICHE_PAGE_SIZE, NICHE_PRESETS,
    NICHE_REGIONS, NICHE_SORTS_UI, NICHE_TIMEFRAMES, NICHE_AUDIENCE_PRECISION)
from app.core.niche import audience as _A
from app.core.niche.helpers import (
    fmt_duration, format_multiplier, is_gem_row, parse_human_number)
from app.core.niche import search as _S
from app.core.niche.search import (
    apply_niche_filters, build_time_windows, capped_window_count,
    compute_niche_metrics,
    enrich_channels, enrich_videos, estimate_search_calls, merge_niche_row,
    niche_scrape_search, niche_search_api)
from app.core.niche.viral import (
    VIRAL_CATEGORIES, VIRAL_REGIONS, VIRAL_SOURCES, VIRAL_WINDOWS,
    estimate_viral_units, fetch_viral, viral_label)
from app.core.niche.sorting import (
    aggregate_by_channel, parse_human_float, sort_niche_rows)
from app.core.niche.gold import apply_gold_scores
from app.core.quota import (key_quota_remaining, search_quota_bump,
                            search_quota_remaining)
from app.core.utils import (
    days_ago_str, video_download_dir, humanize_count, local_path_from_url,
    open_external_url)
from app.core.youtube_api import (
    QuotaExceededError, ScrapeCancelled, build_youtube_service,
    execute_with_retry, resolve_channel_id)
from app.core.niche.live_stats import (LiveStatsError, refresh_rows_live,
                                       youtube_api_keys)
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm import _dl_progress as dlp
from app.qml_backend.vm._thumb_download import (remember_thumb_folder,
                                                start_thumb_download,
                                                thumb_folder)
from app.qml_backend.vm.quality_probe import default_quality_rows
from app.qml_backend.desktop_notifier import announce, announce_download

_FMT_MAP = {0: None, 1: "long", 2: "short"}

# ── "search the filters, don't just filter the search" ────────────────────
# YouTube's search.list cannot filter by subscriber count or view count, so a
# range like "1M–10M views, 2k–10k subs" can only ever be honoured by fetching a
# pool and narrowing it. What used to happen is that the pool came back as
# whatever YouTube felt like returning for one wide "top results" window, and a
# narrow filter then had almost nothing left to keep — the user asked for shorts
# in a specific band and got "No result matches these filters".
#
# So when the form carries a narrowing filter, the run now treats it as part of
# the search: if the first pass does not produce a usable set of matches, it goes
# back for more (deeper time windows, more pages) and merges, until it has a full
# page of matches or the budget below runs out. The budget is what keeps this
# from quietly eating a whole day's search quota.
_WIDEN_TARGET = NICHE_PAGE_SIZE      # one full page of MATCHING rows is enough
_WIDEN_MAX_PASSES = 3
_WIDEN_MAX_CALLS = 26                # extra search.list calls we will ever spend
_WIDEN_MAX_CALLS_CHANNEL = 8         # playlistItems calls for a channel scan
_WIDEN_MAX_CALLS_SCRAPE = 12         # extra youtube.com/results continuations



def _prefetch_page_thumbs(page_rows, next_rows=()):
    """v3.39.4: warm the thumbnail cache for the page about to render (and the
    next one) so cards find their bytes already in memory."""
    def urls(rows):
        out = []
        for r in rows:
            if not isinstance(r, dict):
                continue
            r2 = r.get("best_video") or {}
            for u in (r.get("thumbnail_url"), r2.get("thumbnail_url"),
                      r.get("channel_thumb_url")):
                if u:
                    out.append(u)
        return out
    try:
        prefetch_thumbs(urls(page_rows), urls(next_rows))
    except Exception:
        pass


def _thumb_id(url):
    """Encode a thumbnail URL as the id half of `image://thumbs/<id>`.

    Done here in Python (not with QML's Qt.btoa, which is deprecated and warns
    on every call) so the cards can bind the id straight through.
    """
    if not url:
        return ""
    return base64.b64encode(url.encode("utf-8")).decode("ascii")

def _age_short(published_at):
    """Compact age for the card footer: "3h" / "12d" / "8mo" / "2y".

    days_ago_str() is the sentence form ("12h ago") used in prose; this is the
    corner-badge form, so it stays unit-suffixed but drops the "ago" and never
    localises the number away from digits.
    """
    if not published_at:
        return ""
    try:
        dt = datetime.strptime(published_at, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return ""
    secs = max((datetime.now(timezone.utc) - dt).total_seconds(), 0)
    days = int(secs // 86400)
    if days < 1:
        hours = int(secs // 3600)
        return f"{hours}h" if hours >= 1 else f"{max(int(secs // 60), 1)}m"
    if days < 30:
        return f"{days}d"
    if days < 365:
        return f"{days // 30}mo"
    return f"{days // 365}y"

def _lang_label(r):
    """"ES · BR" for the card footer — the video's language and the channel's
    country. Declared languages show as-is; a language read off the title
    (nothing was declared) shows as "≈ES" so a guess never poses as a fact.
    Either half may be missing; both missing renders nothing."""
    return _A.card_label(r)


def _export_lang(r):
    code, src = _A.best_language(r)
    return ("~" + code) if (code and src == "text") else code


class NicheVM(QObject):
    """Niche Finder discovery + local filtering for the QML page."""

    # One archive save at a time (all go to the same ideas.db rows).
    _ARCHIVE_LOCK = threading.Lock()

    # form echoes
    changed = Signal()                 # form combos / options
    # run lifecycle
    runningChanged = Signal()
    statusChanged = Signal()
    # The live loading state: percentage, which stage, and how much has been
    # found. Separate from statusChanged because it fires on every worker tick
    # (several times a second) while the status SENTENCE changes far less often —
    # binding the whole status line to this would make the text flicker.
    progressChanged = Signal()
    quotaChanged = Signal()
    resultsChanged = Signal()          # visible rows / metrics changed
    toast = Signal(str, str)           # (message, kind)
    # v3.42: where the ✦ "Send to AI Ideas" tile delivers its row. main_qml.py
    # points this at IdeasVM.addReferences(rows, source) -> (added, already).
    # A plain callable rather than a Signal: the raw dict must reach IdeasVM
    # as-is (a QVariant round-trip would copy and re-type it) and the caller
    # needs the answer to word its toast.
    ideas_sink = None
    # per-card action state, keyed by video id so a card can bind its own
    # download progress / saved flag without the whole grid re-rendering.
    downloadsChanged = Signal()
    savedChanged = Signal()
    labelsChanged = Signal()           # UI language changed
    viralChanged = Signal()            # Viral Radar form / on-screen state
    # "Analyze these results" — hand the whole filtered set to Niche Scan.
    # (rows, query, mode) rather than a page index so the shell can route it:
    # the VM has no business knowing what number Insights sits at, and the rows
    # travel with the request so Insights never re-runs the search.
    analyzeRequested = Signal(list, str, str)
    # internal worker → GUI bridge (queued automatically across threads)
    _searchDone = Signal(list, str)    # (rows, error)
    # (seq, note, kind, manual) — an archive save finishing on its worker.
    _archiveDone = Signal(int, str, str, bool)
    # (pct, text, phase, counts) — `phase` is app.core.niche.search's stable stage
    # token and `counts` its running numbers, both carried so the page can draw a
    # named step list rather than one line of replacing text.
    _searchProgress = Signal(int, str, str, "QVariant")
    _dlStatus = Signal(str, str)       # (video_id, short status text)
    _dlProgress = Signal(str, int)     # (video_id, percent)
    # (video_id, bytes_done, bytes_total, bytes_per_sec, eta_seconds,
    #  frag_done, frag_total) — the raw numbers a live progress UI needs; a bare
    # percentage can't express speed, and frag_done/total drive "part 32 of 93".
    _dlDetail = Signal(str, int, int, float, int, int, int)
    _dlDone = Signal(str, bool, str, str)  # (video_id, ok, message, filepath)
    # (video_id, height_px, label) — the resolution actually delivered, so the
    # mirrored Downloads row is labelled with the file on disk rather than the
    # tier that was asked for.
    _dlResolved = Signal(str, int, str)
    # Channel identity harvested from the download's own metadata, marshalled
    # onto the GUI thread before it touches the DB (see _on_dl_meta).
    _dlMeta = Signal(str, "QVariantMap")
    _thumbDone = Signal(str, str)          # (saved_path_or_"", error)
    _poolLive = Signal(int, list)          # v3.43: (token, fresh rows)

    def __init__(self, parent=None):
        super().__init__(parent)
        cfg = load_app_config()
        self._api_key = cfg.get("api_key", "") or ""

        # form state
        self._mode = 0                 # 0 keyword, 1 channel
        self._source = 0              # 0 api, 1 scrape
        self._query = ""
        self._timeframe = 2            # last 30 days
        self._sort = 0
        self._format = 0
        self._depth = 1
        self._lang = 0
        self._region = 0
        # How strictly Language / Country filter (index into
        # NICHE_AUDIENCE_PRECISION): 0 broad · 1 smart · 2 strict.
        self._precision = 1
        self._subs_min = ""
        self._subs_max = ""
        self._views_min = ""
        self._views_max = ""
        self._mult_min = ""
        self._deep = False
        self._quick = ""
        self._channels_view = False

        # Viral Radar — what is blowing up right now, no keyword needed. Its
        # pool goes through the very same cuts / sorts / cards as a search;
        # these only pick WHERE the pool comes from. Remembered in config.
        vcfg = cfg.get("viral_radar") or {}
        self._viral_active = False     # the pool on screen is a viral pool
        self._viral_tried = False      # auto-load already ran this session
        self._viral_source = self._clamp(vcfg.get("source", 0), VIRAL_SOURCES)
        self._viral_region = self._clamp(vcfg.get("region", 0), VIRAL_REGIONS)
        self._viral_category = self._clamp(vcfg.get("category", 0), VIRAL_CATEGORIES)
        self._viral_window = self._clamp(vcfg.get("window", 2), VIRAL_WINDOWS)
        # v1.1: the radar spends the user's own Google quota, so it never
        # runs by itself any more — it opens on a "pick, see the cost, press
        # Find" panel. The old "autoload" key defaulted to ON and was written
        # back on every pref change, so it can't tell an opt-in from the old
        # default; only the new "auto_open" key (set by the switch) counts.
        self._viral_autoload = bool(vcfg.get("auto_open", False))
        self._viral_setup = False      # the pick-and-confirm panel is open
        self._viral_loaded_sig = None  # params of the radar on screen
        self._viral_lens = 0           # All / Gold / Hidden gems / Shorts / Long

        # run state
        self._running = False
        self._stop = False
        self._status = tr("Type a niche keyword and press Search.")
        self._status_kind = "muted"
        self._cache_label = ""
        self._quota_text = ""
        # Live loading state, fed by the core module's progress callback. Kept
        # apart from `_status` (the sentence) so the panel can show WHERE the run
        # is — which of the three stages, and what it has found — rather than only
        # what it most recently said.
        self._pct = 0
        self._phase = ""
        self._found = 0
        self._enriched = 0

        # data
        self._pool = []
        self._pool_days = None
        self._filtered = []       # ALL rows matching the filters (raw)
        self._visible = []        # the current page, flattened for QML
        self._page = 0
        self._m_matches = "0"
        self._m_gems = "0"
        self._m_best = "—"
        self._m_views = "0"
        self._m_pool = 0
        self._m_match_frac = 0.0
        self._m_gem_frac = 0.0
        self._m_avg_views = "—"
        self._m_best_title = ""
        self._m_best_channel = ""
        self._m_spark = []

        # per-card action state
        self._raw_by_key = {}     # video_id / channel_id → full raw pool row
        self._downloads = {}      # video_id → {"pct": int, "state": str, "text": str}
        self._last_db_write = {}  # video_id -> (monotonic_s, pct), DB throttle
        self._saved = set()       # video_ids already bookmarked this session
        # video_ids with a finished file on disk (any session) — the card's
        # Download button becomes Open for these instead of offering to fetch
        # what's already there.
        self._downloaded = set()
        self._refresh_downloaded(silent=True)
        self._last_query = ""     # for filing favorites under the right group
        self._last_params = {}    # params of the run being archived
        self._archive_note = ""   # "Archived under X · n new, m refreshed"
        self._archive_seq = 0     # newest archive save; older notes are dropped
        # Set by a web-scrape run that came back with less than its depth asked
        # for — YouTube caps a keyword at roughly 370 videos. Surfaced once in
        # the status line so a short result reads as a platform limit rather
        # than as a broken search.
        self._scrape_note = ""
        self._force = False       # skip the pool cache on the next search
        # The filter state frozen at the moment Search was pressed, so the
        # worker can honour it without reading UI state from another thread —
        # and so widening the search uses the filters the user actually
        # searched with, not whatever they have nudged since.
        self._search_filters = None
        self._widen_passes = 0    # extra fetch passes this run needed

        self._searchDone.connect(self._on_done)
        self._archiveDone.connect(self._on_archive_done)
        self._searchProgress.connect(self._on_progress)
        self._dlStatus.connect(self._on_dl_status)
        self._dlProgress.connect(self._on_dl_progress)
        self._dlDetail.connect(self._on_dl_detail)
        self._dlDone.connect(self._on_dl_done)
        self._dlResolved.connect(self._on_dl_resolved)
        self._dlMeta.connect(self._on_dl_meta)
        self._thumbDone.connect(self._on_thumb_done)
        self._pool_live_token = 0
        self._cache_live = False
        self._poolLive.connect(self._on_pool_live)
        self._update_quota()

    # ── option lists (constant) ─────────────────────────────────────────
    @Property("QStringList", notify=labelsChanged)
    def timeframeOptions(self):
        return [tr(n) for n, _ in NICHE_TIMEFRAMES]

    @Property("QStringList", notify=labelsChanged)
    def sortOptions(self):
        return [tr(row[0]) for row in NICHE_SORTS_UI]

    @Property("QStringList", notify=labelsChanged)
    def formatOptions(self):
        return [tr("All Formats"), tr("Long-form"), tr("Shorts")]

    @Property("QStringList", notify=labelsChanged)
    def depthOptions(self):
        return [tr(n) for n, _ in NICHE_DEPTHS]

    @Property("QStringList", notify=labelsChanged)
    def langOptions(self):
        return [tr(n) for n, _ in NICHE_LANGS]

    @Property("QStringList", notify=labelsChanged)
    def regionOptions(self):
        return [tr(n) for n, _ in NICHE_REGIONS]

    @Property("QStringList", notify=labelsChanged)
    def precisionOptions(self):
        return [tr(n) for n, _ in NICHE_AUDIENCE_PRECISION]

    # ── audience (language + country) explainer ─────────────────────────
    def _aud_codes(self):
        lang = _A.norm_lang(NICHE_LANGS[self._lang][1]) if self._lang else ""
        region = NICHE_REGIONS[self._region][1] if self._region else ""
        if self._mode == 1:
            region = ""      # a channel scan has exactly one country
        return lang, region

    @Property(str, notify=changed)
    def audienceSummary(self):
        """One sentence saying what Language / Country will actually do with the
        current settings — the question "what does this even do" answered in
        place, and re-answered every time a dropdown moves."""
        lang, region = self._aud_codes()
        prec = NICHE_AUDIENCE_PRECISION[self._precision][1]
        ln = tr(NICHE_LANGS[self._lang][0]) if lang else ""
        cn = tr(NICHE_REGIONS[self._region][0]) if region else ""
        if not lang and not region:
            return tr("Off. Results come from every language and country.")
        if lang and region:
            what = tr("Keeps videos in {lang} from channels based in {country}.")
        elif lang:
            what = tr("Keeps videos in {lang}.")
        else:
            what = tr("Keeps videos from channels based in {country}.")
        what = what.replace("{lang}", ln).replace("{country}", cn)
        how = {
            "broad": tr("Broad: only drops videos that clearly point elsewhere; unknowns stay."),
            "smart": tr("Smart: needs real evidence (declared audio language, the title's own language, the channel's registered country)."),
            "strict": tr("Strict: only videos the creator explicitly declared. Fewest results, zero guesses."),
        }[prec]
        return what + " " + how

    @Property(str, notify=changed)
    def audienceWarning(self):
        lang, region = self._aud_codes()
        if _A.pair_warning(lang, region):
            return tr("{lang} is not a main language in {country}, so expect very few results.").replace(
                "{lang}", tr(NICHE_LANGS[self._lang][0])).replace(
                "{country}", tr(NICHE_REGIONS[self._region][0]))
        return ""

    @Property(bool, notify=changed)
    def audienceActive(self):
        lang, region = self._aud_codes()
        return bool(lang or region)

    def _on_audience_changed(self):
        # Language / Country are now real filters over the fetched pool as well
        # as hints to the next search, so a change re-filters on the spot.
        self._update_quota()
        self.applyFilters()

    @Property("QStringList", notify=labelsChanged)
    def sourceOptions(self):
        return [tr("Official API · exact, 100 searches/day"),
                tr("Web scrape · unlimited, no search quota")]

    @Property("QStringList", notify=labelsChanged)
    def presetOptions(self):
        return [tr(text) for text, _ in NICHE_PRESETS]

    @Slot()
    def retranslate(self):
        """UI language changed — re-read every translated label. The status line
        and the filter chips were translated when they were built, so they are
        re-emitted too."""
        self.labelsChanged.emit()
        self.changed.emit()
        self.statusChanged.emit()
        self.resultsChanged.emit()

    # ── active-filter summary (chips) ────────────────────────────────────
    # Mirrors the reference design's getActiveFilters: a flat list of the
    # filters currently narrowing the pool, so the collapsed panel can show
    # removable chips and a count badge. `key` is what clearFilter() resets.
    @Property("QVariantList", notify=changed)
    def activeFilters(self):
        out = []
        num = [
            ("subs_min", tr("Subs ≥ {v}")),
            ("subs_max", tr("Subs ≤ {v}")),
            ("views_min", tr("Views ≥ {v}")),
            ("views_max", tr("Views ≤ {v}")),
            ("mult_min", tr("Views ÷ subs ≥ {v}")),
        ]
        for key, tmpl in num:
            # Single Channel Scan has no subscriber range (see _current_filters)
            # — listing a chip for a cut that is not being applied would be a
            # lie the user could only disprove by clearing it and seeing
            # nothing change.
            if self._mode == 1 and key in ("subs_min", "subs_max"):
                continue
            v = (getattr(self, "_" + key) or "").strip()
            if v:
                out.append({"key": key, "label": tmpl.replace("{v}", v)})
        # dropdowns that differ from their default index
        if self._timeframe != 2:
            out.append({"key": "timeframe",
                        "label": tr(NICHE_TIMEFRAMES[self._timeframe][0])})
        if self._sort != 0:
            out.append({"key": "sort", "label": tr(NICHE_SORTS_UI[self._sort][0])})
        if self._format != 0:
            out.append({"key": "format",
                        "label": self.formatOptions[self._format]})
        if self._depth != 1:
            out.append({"key": "depth", "label": tr(NICHE_DEPTHS[self._depth][0])})
        if self._lang != 0:
            out.append({"key": "lang", "label": tr(NICHE_LANGS[self._lang][0])})
        if self._region != 0 and self._mode != 1:
            out.append({"key": "region", "label": tr(NICHE_REGIONS[self._region][0])})
        # toggles that differ from their default
        if self._deep:
            out.append({"key": "deep", "label": tr("Deep scan")})
        if self._force:
            out.append({"key": "force", "label": tr("Cache ignored")})
        return out

    @Property(int, notify=changed)
    def activeFilterCount(self):
        return len(self.activeFilters)

    @Slot(str)
    def clearFilter(self, key):
        """Reset one filter to its default (the chip's ✕). Numeric/text and
        toggle filters re-filter the cached pool live; the search-scope
        dropdowns (timeframe/lang/region/depth) take effect on the next run,
        same asymmetry the page's inline controls already have."""
        defaults = {
            "subs_min": "", "subs_max": "", "views_min": "", "views_max": "",
            "mult_min": "", "timeframe": 2, "sort": 0, "format": 0, "depth": 1,
            "lang": 0, "region": 0, "deep": False,
            "force": False,
        }
        if key not in defaults:
            return
        setattr(self, "_" + key, defaults[key])
        self.changed.emit()
        if key in ("timeframe", "depth", "deep"):
            self._update_quota()
        self.applyFilters()

    @Slot()
    def clearAllFilters(self):
        """Reset every filter to its default, keeping the query + source. The
        reference design's "Clear filters" action."""
        self._subs_min = self._subs_max = ""
        self._views_min = self._views_max = self._mult_min = ""
        self._quick = ""
        self._timeframe = 2
        self._sort = 0
        self._format = 0
        self._depth = 1
        self._lang = 0
        self._region = 0
        self._deep = False
        self._force = False
        self.changed.emit()
        self._update_quota()
        self.applyFilters()

    @Property(bool, notify=changed)
    def forceRefresh(self):
        return self._force

    # ── form properties (two-way; guard emit to avoid binding loops) ─────
    def _prop_str(name, sig):
        attr = "_" + name

        def getter(self):
            return getattr(self, attr)

        def setter(self, v):
            if v != getattr(self, attr):
                setattr(self, attr, v)
                self.changed.emit()
        return Property(str, getter, setter, notify=sig)

    def _prop_int(name, sig, on_change=None):
        attr = "_" + name

        def getter(self):
            return getattr(self, attr)

        def setter(self, v):
            v = int(v)
            if v != getattr(self, attr):
                setattr(self, attr, v)
                self.changed.emit()
                if on_change:
                    on_change(self)
        return Property(int, getter, setter, notify=sig)

    def _prop_bool(name, sig, on_change=None):
        attr = "_" + name

        def getter(self):
            return getattr(self, attr)

        def setter(self, v):
            v = bool(v)
            if v != getattr(self, attr):
                setattr(self, attr, v)
                self.changed.emit()
                if on_change:
                    on_change(self)
        return Property(bool, getter, setter, notify=sig)

    mode = _prop_int("mode", changed)
    source = _prop_int("source", changed)
    query = _prop_str("query", changed)
    sortIndex = _prop_int("sort", changed)
    formatIndex = _prop_int("format", changed)
    langIndex = _prop_int("lang", changed, on_change=lambda self: self._on_audience_changed())
    regionIndex = _prop_int("region", changed, on_change=lambda self: self._on_audience_changed())
    precisionIndex = _prop_int("precision", changed, on_change=lambda self: self._on_audience_changed())
    subsMin = _prop_str("subs_min", changed)
    subsMax = _prop_str("subs_max", changed)
    viewsMin = _prop_str("views_min", changed)
    viewsMax = _prop_str("views_max", changed)
    multMin = _prop_str("mult_min", changed)
    quickFilter = _prop_str("quick", changed)
    channelsView = _prop_bool("channels_view", changed)

    # these feed the quota estimate, so refresh it on change
    timeframeIndex = _prop_int("timeframe", changed, on_change=lambda self: self._update_quota())
    depthIndex = _prop_int("depth", changed, on_change=lambda self: self._update_quota())
    deepScan = _prop_bool("deep", changed, on_change=lambda self: self._update_quota())

    # ── Viral Radar (v1.1) ──────────────────────────────────────────────
    # The page opens on what is viral right now instead of an empty radar; a
    # keyword search replaces it, and "Viral now" brings it back. The pool is
    # an ordinary Niche Finder pool, so "Best Finds · Views ÷ Subs" is the
    # high-views / low-subs ranking, every cut applies live, and saving it to
    # the Search Archive is the same merge a search does — but only when the
    # user asks for it (a radar refresh is never auto-archived).
    @staticmethod
    def _clamp(value, options):
        try:
            i = int(value)
        except (TypeError, ValueError):
            i = 0
        return max(0, min(len(options) - 1, i))

    def _save_viral_prefs(self):
        try:
            cfg = load_app_config()
            cfg["viral_radar"] = {
                "source": self._viral_source, "region": self._viral_region,
                "category": self._viral_category, "window": self._viral_window,
                "auto_open": self._viral_autoload,
            }
            save_app_config(cfg)
        except Exception:
            log_crash("Viral Radar prefs save failed:\n" + traceback.format_exc())
        self.viralChanged.emit()

    viralSourceIndex = _prop_int("viral_source", changed,
                                 on_change=lambda self: self._save_viral_prefs())
    viralRegionIndex = _prop_int("viral_region", changed,
                                 on_change=lambda self: self._save_viral_prefs())
    viralCategoryIndex = _prop_int("viral_category", changed,
                                   on_change=lambda self: self._save_viral_prefs())
    viralWindowIndex = _prop_int("viral_window", changed,
                                 on_change=lambda self: self._save_viral_prefs())
    viralAutoload = _prop_bool("viral_autoload", changed,
                               on_change=lambda self: self._save_viral_prefs())

    @Property("QStringList", notify=labelsChanged)
    def viralSourceOptions(self):
        return [tr(n) for n, _ in VIRAL_SOURCES]

    @Property("QStringList", notify=labelsChanged)
    def viralRegionOptions(self):
        return [tr(n) for n, _ in VIRAL_REGIONS]

    @Property("QStringList", notify=labelsChanged)
    def viralCategoryOptions(self):
        return [tr(n) for n, _ in VIRAL_CATEGORIES]

    @Property("QStringList", notify=labelsChanged)
    def viralWindowOptions(self):
        return [tr(n) for n, _ in VIRAL_WINDOWS]

    @Property(bool, notify=viralChanged)
    def viralActive(self):
        """True while the pool on screen (or the run in flight) is a radar."""
        return self._viral_active

    @Property(str, notify=changed)
    def viralTitle(self):
        """The section name a radar is archived under, e.g.
        "Viral · United States · Gaming"."""
        return viral_label(VIRAL_REGIONS[self._viral_region][1],
                           VIRAL_CATEGORIES[self._viral_category][1])

    def _viral_units(self):
        return estimate_viral_units(VIRAL_SOURCES[self._viral_source][1],
                                    VIRAL_REGIONS[self._viral_region][1])

    def _viral_cached_at(self):
        """When the radar for the CURRENT picks was cached (< 1 h), or "".
        A timestamp-only lookup (no rows loaded), memoised for a few seconds
        because several labels ask for it on every change."""
        key = niche_cache_key(self._viral_params())
        now = time.monotonic()
        memo = getattr(self, "_viral_cache_memo", None)
        if memo and memo[0] == key and now - memo[1] < 5:
            return memo[2]
        at = niche_cache_fetched_at(key, max_age_hours=1)
        self._viral_cache_memo = (key, now, at)
        return at

    @Property(str, notify=changed)
    def viralCost(self):
        at = self._viral_cached_at()
        if at:
            return tr("free · cached {ago}").format(ago=days_ago_str(at))
        return tr("~{n} units").format(n=f"{self._viral_units():,}")

    @Property(int, notify=changed)
    def viralCostUnits(self):
        """0 when the current picks are served from the 1-hour cache."""
        return 0 if self._viral_cached_at() else self._viral_units()

    @Property(bool, notify=changed)
    def viralCostHeavy(self):
        """A run that eats a real slice of the day (Breakouts · Global is
        ~1,600 of a key's 10,000) — the panel colours its button for it."""
        return self.viralCostUnits >= 500

    @Property(str, notify=changed)
    def viralBudgetText(self):
        """"9,840 left on this key today" — so the user decides with the
        number in front of them."""
        key = (self._api_key or "").strip()
        if not key:
            return ""
        try:
            left = key_quota_remaining(key)
        except Exception:
            return ""
        units = self.viralCostUnits
        if units and left:
            pct = max(1, round(units * 100.0 / max(left, 1)))
            return tr("{left} left on this key today · this run ≈ {pct}%").format(
                left=f"{left:,}", pct=min(pct, 100))
        return tr("{left} left on this key today").format(left=f"{left:,}")

    @Property(int, constant=True)
    def goldSortIndex(self):
        """Index of "Gold Score" in sortOptions (the Gold lens switches to it)."""
        return next((i for i, row in enumerate(NICHE_SORTS_UI) if row[1] == "gold"), 0)

    @Property(bool, notify=viralChanged)
    def viralSetupOpen(self):
        """The radar panel is showing its picks but nothing has been fetched."""
        return self._viral_setup and not self._viral_active

    @Property(bool, notify=changed)
    def viralDirty(self):
        """Picks changed since the radar on screen was loaded. Nothing is
        fetched until the user presses Apply."""
        return (self._viral_active and self._viral_loaded_sig is not None
                and self._viral_sig() != self._viral_loaded_sig)

    def _viral_sig(self):
        return (self._viral_source, self._viral_region,
                self._viral_category, self._viral_window)

    @Slot()
    def openViralSetup(self):
        """"Viral now": open the picks + cost panel. Spends nothing."""
        self.refreshApiKeys()
        self._viral_setup = True
        self.viralChanged.emit()
        self.changed.emit()

    @Slot()
    def closeViralSetup(self):
        self._viral_setup = False
        self.viralChanged.emit()

    # Lens: a one-tap cut of the radar pool. Local, zero quota.
    _VIRAL_LENSES = (("All", ""), ("Gold", "gold"), ("Hidden gems", "gems"),
                     ("Shorts", "shorts"), ("Long-form", "long"))

    @Property("QStringList", notify=labelsChanged)
    def viralLensOptions(self):
        return [tr(n) for n, _ in self._VIRAL_LENSES]

    def _get_viral_lens(self):
        return self._viral_lens

    def _set_viral_lens(self, v):
        v = max(0, min(len(self._VIRAL_LENSES) - 1, int(v)))
        if v != self._viral_lens:
            self._viral_lens = v
            self.viralChanged.emit()
            self.applyFilters()

    viralLensIndex = Property(int, _get_viral_lens, _set_viral_lens, notify=viralChanged)

    @Property("QVariantList", notify=viralChanged)
    def viralLensCounts(self):
        """How many pool rows each lens would show, for the chip badges."""
        pool = (self._pool or []) if self._viral_active else []
        return [len(pool)] + [sum(1 for r in pool if self._lens_ok(r, k))
                              for _, k in self._VIRAL_LENSES[1:]]

    @staticmethod
    def _lens_ok(r, lens):
        if lens == "gold":
            return r.get("gold_tier") == "gold"
        if lens == "gems":
            return bool(is_gem_row(r)) or (
                r.get("gold_tier") in ("gold", "hot")
                and (r.get("subscriber_count") or 10 ** 9) < 100_000)
        if lens == "shorts":
            return bool(r.get("is_short"))
        if lens == "long":
            return not r.get("is_short")
        return True

    @Property(bool, notify=changed)
    def viralNeedsKey(self):
        return not (self._api_key or "").strip()

    def _viral_params(self):
        return {
            "mode": "viral",
            "source": "api",
            "viral_source": VIRAL_SOURCES[self._viral_source][1],
            "region_code": VIRAL_REGIONS[self._viral_region][1],
            "category_id": VIRAL_CATEGORIES[self._viral_category][1],
            "hours": VIRAL_WINDOWS[self._viral_window][1],
            "query": self.viralTitle,
            "queries": [],
        }

    @Slot()
    def autoLoadViral(self):
        """Called once when the page is first built: fill the empty page with
        the radar. Never replaces results that are already there (an archived
        section opened from Search Archive, a search already run)."""
        if self._viral_tried:
            return
        self._viral_tried = True
        self.refreshApiKeys()
        if self._running or self._pool or not (self._api_key or "").strip():
            return
        if not self._viral_autoload:
            # Opt-in only: show the picks and the cost, fetch nothing.
            self.openViralSetup()
            return
        self.loadViral()

    @Slot()
    def loadViral(self):
        self._start_viral(force=False)

    @Slot()
    def refreshViral(self):
        """Re-read the charts now, skipping the one-hour radar cache."""
        self._start_viral(force=True)

    def _start_viral(self, force=False):
        if self._running:
            return
        self.refreshApiKeys()
        if not (self._api_key or "").strip():
            self._set_status(tr("Viral Radar reads YouTube's charts through the "
                                "Data API — add your API key in Settings first."),
                             "error")
            self.toast.emit(tr("Add a YouTube API key to load viral videos."),
                            "error")
            return
        params = self._viral_params()
        self._viral_active = True
        self._viral_setup = False
        self._viral_loaded_sig = self._viral_sig()
        self._viral_cache_memo = None
        self._viral_force = bool(force)
        self._requested_days = None
        self._from_cache = ""
        self._last_query = params["query"]
        self._last_params = params
        self._archive_note = ""
        self._archive_seq += 1
        self._pool_live_token += 1
        self._scrape_note = ""
        self._stop = False
        self._running = True
        self._search_filters = self._current_filters()
        self._widen_passes = 0
        self._pct = 0
        self._phase = ""
        self._found = 0
        self._enriched = 0
        self.viralChanged.emit()
        self.changed.emit()               # viralDirty → false
        self.runningChanged.emit()
        self.progressChanged.emit()
        self._set_status(tr("Reading what is viral right now …"), "muted")
        threading.Thread(target=self._worker, args=(params,), daemon=True,
                         name="niche-viral").start()

    def _fetch_viral(self, params):
        """One radar run. Cached for an hour: the charts move, but not by the
        minute, and reopening the app should not re-spend the units."""
        key = niche_cache_key(params)
        if not getattr(self, "_viral_force", False):
            cached, fetched_at = niche_cache_get(key, max_age_hours=1)
            if cached:
                self._from_cache = fetched_at or ""
                return self._ensure_gold(cached)
        yt = build_youtube_service((self._api_key or "").strip())
        rows = fetch_viral(
            yt, source=params["viral_source"], region_code=params["region_code"],
            category_id=params["category_id"], hours=params["hours"],
            stop_check=self._stop_check, progress=self._progress,
            quota_cb=search_quota_bump)
        if rows:
            niche_cache_put(key, params, rows)
        return rows

    @staticmethod
    def _ensure_gold(rows):
        """Rows cached / archived before v1.1 have no Gold Score yet."""
        if rows and any("gold_score" not in r for r in rows):
            try:
                apply_gold_scores(rows)
            except Exception:
                log_crash("gold score failed\n" + traceback.format_exc())
        return rows

    # ── read-only run/result state ──────────────────────────────────────
    @Property(bool, notify=runningChanged)
    def isRunning(self):
        return self._running

    @Property(str, notify=statusChanged)
    def statusText(self):
        return self._status

    @Property(str, notify=statusChanged)
    def statusKind(self):
        return self._status_kind      # "muted" | "ok" | "warn" | "error"

    # ── the run, while it runs ────────────────────────────────────────────
    # A search is three distinct jobs against two different endpoints and takes
    # long enough that "is it stuck?" is a real question. These properties are
    # what let the page draw a loading panel: a percentage, which of the three
    # stages is active, and how many videos have actually been found.
    @Property(int, notify=progressChanged)
    def pct(self):
        return self._pct

    @Property("QVariantList", notify=progressChanged)
    def stages(self):
        """The three search stages, each "done" | "active" | "pending".

        Derived from the stage token the core module reports (search.PHASE_*),
        which is English and stable — the translated status sentence could not
        drive this. They run strictly in order, so anything before the active one
        is finished.

        The last two only exist when there is an API key: a scrape-only run gets
        no exact stats and no subscriber counts, and showing two steps that will
        never run reads as a search that gave up early.
        """
        phases = [(_S.PHASE_DISCOVER, tr("Finding videos"))]
        if (self._api_key or "").strip():
            phases += [(_S.PHASE_STATS, tr("Reading exact view counts")),
                       (_S.PHASE_CHANNELS, tr("Reading subscriber counts"))]
        active = -1
        for i, (token, _label) in enumerate(phases):
            if token == self._phase:
                active = i
                break
        out = []
        for i, (token, label) in enumerate(phases):
            if active < 0:
                state = "pending"
            elif i < active:
                state = "done"
            elif i == active:
                state = "active"
            else:
                state = "pending"
            out.append({"key": token, "label": label, "state": state})
        return out

    @Property(int, notify=progressChanged)
    def foundCount(self):
        """Candidate videos discovered so far — drives the scope's contacts."""
        return int(self._found or 0)

    @Property("QVariantList", notify=progressChanged)
    def liveCounts(self):
        """What the run has found so far, as label/value pairs.

        Real numbers rather than a spinner: discovery produces a count within a
        second or two, and it is the one thing the user actually wants to know
        while waiting. Empty until there is something true to say.
        """
        out = []
        if self._found:
            out.append({"label": tr("videos found"), "value": str(self._found)})
        if self._enriched:
            out.append({"label": tr("stats read"), "value": str(self._enriched)})
        return out

    @Property(str, notify=statusChanged)
    def cacheLabel(self):
        return self._cache_label

    @Property(str, notify=statusChanged)
    def archiveNote(self):
        """"Archived under “kw” · n new, m refreshed" — the confirmation the
        legacy page put under the search card after every finished run."""
        return self._archive_note

    @Property(str, notify=quotaChanged)
    def quotaText(self):
        return self._quota_text

    @Property("QVariantList", notify=resultsChanged)
    def rows(self):
        return self._visible

    @Property(bool, notify=resultsChanged)
    def hasResults(self):
        return len(self._visible) > 0

    # ── paging ───────────────────────────────────────────────────────────
    # A matched pool can run to NICHE_MAX_POOL (1600) rows. Neither this grid
    # nor the legacy one ever builds more than one page of cards at a time: each
    # NicheCard carries two MultiEffect layers (thumbnail mask + avatar mask), so
    # instantiating hundreds of them would allocate GPU textures for rows nobody
    # has scrolled to. The pool is plain dicts, which is why it can be this much
    # larger than the card count without costing anything.
    @Property(int, notify=resultsChanged)
    def pageIndex(self):
        return self._page

    @Property(int, notify=resultsChanged)
    def pageCount(self):
        total = len(self._filtered)
        return max(1, (total + NICHE_PAGE_SIZE - 1) // NICHE_PAGE_SIZE)

    @Property(str, notify=resultsChanged)
    def pageLabel(self):
        total = len(self._filtered)
        if not total:
            return ""
        first = self._page * NICHE_PAGE_SIZE + 1
        last = min(total, first + NICHE_PAGE_SIZE - 1)
        return tr("{a}–{b} of {n}").format(a=first, b=last, n=total)

    @Slot(int)
    def gotoPage(self, index):
        index = max(0, min(int(index), self.pageCount - 1))
        if index != self._page:
            self._page = index
            self._render_page()

    @Property(str, notify=resultsChanged)
    def metricMatches(self):
        return self._m_matches

    @Property(str, notify=resultsChanged)
    def metricGems(self):
        return self._m_gems

    @Property(str, notify=resultsChanged)
    def metricBest(self):
        return self._m_best

    @Property(str, notify=resultsChanged)
    def metricViews(self):
        return self._m_views

    @Property(int, notify=resultsChanged)
    def metricPool(self):
        return self._m_pool

    @Property(float, notify=resultsChanged)
    def metricMatchFrac(self):
        return self._m_match_frac

    @Property(float, notify=resultsChanged)
    def metricGemFrac(self):
        return self._m_gem_frac

    @Property(str, notify=resultsChanged)
    def metricAvgViews(self):
        return self._m_avg_views

    @Property(str, notify=resultsChanged)
    def metricBestTitle(self):
        return self._m_best_title

    @Property(str, notify=resultsChanged)
    def metricBestChannel(self):
        return self._m_best_channel

    @Property("QVariantList", notify=resultsChanged)
    def metricSpark(self):
        return self._m_spark

    # ── per-card action state ───────────────────────────────────────────
    @Property("QVariantMap", notify=downloadsChanged)
    def downloads(self):
        """video_id → {state, pct, text}. A card binds
        `Niche.downloads[row.videoId]` so only its own button reacts."""
        return self._downloads

    @Property("QVariantList", notify=savedChanged)
    def savedIds(self):
        """Video ids bookmarked this session — the bookmark icon stays solid
        once saved (same sticky behaviour as the legacy card rail)."""
        return sorted(self._saved)

    @Property("QVariantList", notify=downloadsChanged)
    def downloadedIds(self):
        """Video ids with a finished file on disk (any session, not just this
        one). The card binds this for its Download→Open switch, so a video
        fetched yesterday doesn't offer to download again after a restart."""
        return sorted(self._downloaded)

    def _refresh_downloaded(self, silent=False):
        """Rebuild the finished-on-disk set from the persisted history.

        Only rows whose file actually exists count — a row whose file was
        moved/deleted must offer Download again, not an Open button that
        immediately reports "file couldn't be found". Rebuilt wholesale (not
        incrementally) so entries removed on the Downloads page drop out here
        too. Emits downloadsChanged unless silent (init path)."""
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
        if fresh != self._downloaded:
            self._downloaded = fresh
            if not silent:
                self.downloadsChanged.emit()
        elif not silent:
            self.downloadsChanged.emit()

    @Slot()
    def refreshDownloaded(self):
        """Re-read the finished-on-disk set — called when the page is shown,
        so a delete on the Downloads page is reflected here without a
        restart."""
        self._refresh_downloaded()

    @Slot(str)
    def openDownloaded(self, video_id):
        """Open an already-downloaded video in the OS default player.

        The card's Download button becomes Open for finished rows; this is
        what it calls instead of the quality picker. The file is looked up in
        the persisted history (not the session cache) so it works right after
        a restart too."""
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

    @Property("QVariantList", constant=True)
    def qualityOptions(self):
        """Fallback rows for the download-quality picker, in the same order as
        DOWNLOAD_QUALITY_PRESETS. The picker normally shows QualityProbe.options
        instead — the real formats THIS video has — and falls back to this
        generic ladder only when the probe couldn't run."""
        return default_quality_rows()

    # ── helpers ──────────────────────────────────────────────────────────
    def _set_status(self, text, kind="muted"):
        self._status = text
        self._status_kind = kind
        self.statusChanged.emit()

    def _queries(self):
        import re
        parts = [p.strip() for p in re.split(r"[,،]", self._query or "") if p.strip()]
        return parts[:5]

    def _depth_target(self, depth=None):
        """The hard video count for a depth row (None = the uncapped last row)."""
        i = self._depth if depth is None else depth
        try:
            return NICHE_DEPTH_TARGETS[i]
        except (IndexError, TypeError):
            return None

    def _search_plan(self):
        queries = self._queries() or [""]
        days = NICHE_TIMEFRAMES[self._timeframe][1]
        pages = NICHE_DEPTHS[self._depth][1]
        target = self._depth_target()
        windows = build_time_windows(
            days, self._deep,
            max_windows=capped_window_count(len(queries), target))
        return estimate_search_calls(len(queries), len(windows), pages,
                                     target=target)

    # ── the filter state, as the search itself understands it ─────────────
    def _current_filters(self):
        """The active cuts, in the shape apply_niche_filters() wants.

        Single Channel Scan deliberately drops the subscriber range: the scan
        is about one channel's own videos, so "only channels between 2k and 10k
        subs" can only ever be a yes/no about the channel you already chose.
        Keeping it silently applied there was the reason a channel scan could
        come back empty for no visible reason.
        """
        if self._mode == 1 and not self._viral_active:
            subs_min = subs_max = None
        else:
            subs_min = parse_human_number(self._subs_min)
            subs_max = parse_human_number(self._subs_max)
        aud_lang, aud_region = self._aud_codes()
        days = NICHE_TIMEFRAMES[self._timeframe][1]
        if self._viral_active:
            # The radar picked its own market and window at fetch time; the
            # search form's Country / Published cuts would only fight it. The
            # Language cut stays — "viral, but only in Persian" is a real ask.
            aud_region = ""
            days = None
        return {
            # Language / country as real filters (app.core.niche.audience).
            "lang": aud_lang,
            "region": aud_region,
            "precision": NICHE_AUDIENCE_PRECISION[self._precision][1],
            "subs_min": subs_min,
            "subs_max": subs_max,
            "views_min": parse_human_number(self._views_min),
            "views_max": parse_human_number(self._views_max),
            "mult_min": parse_human_float(self._mult_min),
            "format": _FMT_MAP[self._format],
            "days": days,
            "text": self._quick,
            # The "hide hidden-sub channels" toggle was removed from the UI: a
            # channel that hides its subscriber count is still a legitimate
            # result (and often an outlier worth seeing), so filtering it out by
            # default cost more than it saved. The core filter still accepts the
            # flag — the legacy QWidgets page passes it — so it is pinned off
            # here rather than deleted from app.core.niche.search.
            "hide_hidden_subs": False,
        }

    def _has_narrow_filters(self):
        """True when the form is asking for something narrower than "whatever
        YouTube's top results are" — i.e. when a plain fetch is likely to come
        back with few or no matches and the run should be prepared to widen."""
        f = self._current_filters()
        if f["format"] or f["lang"] or f["region"]:
            return True
        if self._mode == 1:
            # A channel scan is already narrow; a view range still counts.
            return (f["views_min"] is not None or f["views_max"] is not None
                    or f["mult_min"] is not None)
        return any(f[k] is not None for k in
                   ("subs_min", "subs_max", "views_min", "views_max", "mult_min"))

    @Slot()
    def _update_quota(self):
        if self._mode == 1 or self._source == 1:
            # channel scan or scrape → no search.list bucket spend
            self._quota_text = tr("No search-quota cost")
        else:
            cost = self._search_plan()
            # A narrowed search may run extra passes to actually reach the
            # filters, so the estimate is stated as a range rather than a
            # single number the run could then quietly exceed.
            if self._has_narrow_filters() and self._depth_target() is None:
                self._quota_text = tr(
                    "~{c}–{max} search calls · {left} left today").format(
                        c=cost, max=cost + _WIDEN_MAX_CALLS,
                        left=search_quota_remaining())
            else:
                self._quota_text = tr("~{c} search calls · {left} left today").format(
                    c=cost, left=search_quota_remaining())
        self.quotaChanged.emit()

    def _stop_check(self):
        return self._stop

    @Slot()
    def refreshApiKeys(self):
        """Re-read the YouTube API key from config (it may have changed on Settings).

        Called at the start of every search so a freshly-saved key works
        immediately without restarting the app. Also callable from QML.
        """
        try:
            fresh = (load_app_config().get("api_key", "") or "").strip()
        except Exception:
            return
        if fresh != (self._api_key or ""):
            self._api_key = fresh
            self.changed.emit()
            self.progressChanged.emit()

    # The core search module reports (pct, text, phase, info): `phase` is a stable
    # English stage token (search.PHASE_*) and `info` carries running counts. Both
    # are forwarded so the page can draw a real loading panel — a named step list
    # with live numbers — instead of one caption-sized line that replaces itself.
    def _progress(self, pct, text="", phase="", info=None):
        self._searchProgress.emit(int(pct), text or "", str(phase or ""),
                                  dict(info or {}))

    @Slot(int)
    def applyPreset(self, index):
        if not (0 <= index < len(NICHE_PRESETS)):
            return
        preset = NICHE_PRESETS[index][1]
        self._subs_min = preset.get("subs_min", "")
        self._subs_max = preset.get("subs_max", "")
        self._views_min = preset.get("views_min", "")
        self._views_max = preset.get("views_max", "")
        self._mult_min = preset.get("mult_min", "")
        if "timeframe" in preset:
            self._timeframe = preset["timeframe"]
        if "sort" in preset:
            self._sort = preset["sort"]
        self.changed.emit()
        self.applyFilters()

    @Slot(str)
    def openUrl(self, url):
        open_external_url(url)

    @Slot(str)
    def copyLink(self, url):
        """Put a result's URL on the clipboard — the legacy card rail's second
        icon. QGuiApplication (not QApplication) owns the clipboard here; the
        QML app never builds a QtWidgets application object."""
        if not url:
            return
        clip = QGuiApplication.clipboard()
        if clip is None:
            self.toast.emit(tr("Clipboard is unavailable."), "error")
            return
        clip.setText(url)
        self.toast.emit(tr("Link copied: {url}").format(url=url), "success")

    # ── thumbnail download ─────────────────────────────────────────────────
    # Grab a result's thumbnail at its original resolution. The destination is
    # asked for once (the page opens a FolderDialog when hasThumbFolder is
    # false) and then remembered in config, shared with Search Archive.
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

    # ── archive ──────────────────────────────────────────────────────────
    def _archive_store(self, manual=False):
        """Merge the fetched pool into its keyword section in the Search
        Archive. Every finished search archives automatically (the legacy page
        did the same in _on_idea_scan_done) so a pool outlives its 12-hour
        cache entry; `manual=True` is the Archive-results button re-saving the
        pool that is already on screen.

        The save itself (JSON-encoding every row + one upsert each) runs on a
        worker: on a several-hundred-row pool it used to hold the GUI thread
        right at the moment the results were being drawn. Saves are serialised
        by a lock, and a sequence number drops the note of a save that a newer
        search has already superseded."""
        rows = list(self._pool or [])
        query = self._last_query or (self._query or "").strip()
        if not rows or not query:
            if manual:
                self.toast.emit(
                    tr("Nothing to archive yet — run a search first.") if not rows
                    else tr("Enter at least one niche keyword first."), "error")
            return
        params = dict(self._last_params or {})
        self._archive_seq = getattr(self, "_archive_seq", 0) + 1
        seq = self._archive_seq
        lock = NicheVM._ARCHIVE_LOCK

        def work():
            try:
                with lock:
                    gid, added, updated = archive_save_search(query, params, rows)
            except Exception:
                log_crash(f"qml niche archive save failed\n{traceback.format_exc()}")
                self._archiveDone.emit(seq, tr("(archiving failed)"), "error", manual)
                return
            if gid is None:
                self._archiveDone.emit(seq, "", "", manual)
                return
            self._archiveDone.emit(seq, tr(
                "Archived under “{kw}” · {new} new, {upd} refreshed.").format(
                    kw=query, new=added, upd=updated), "success", manual)

        threading.Thread(target=work, daemon=True, name="niche-archive").start()

    @Slot(int, str, str, bool)
    def _on_archive_done(self, seq, note, kind, manual):
        if seq != getattr(self, "_archive_seq", 0):
            return
        if not note:
            return
        self._archive_note = note
        self.statusChanged.emit()
        if manual:
            self.toast.emit(tr("Archiving failed.") if kind == "error" else note,
                            "error" if kind == "error" else "success")

    @Slot()
    def archiveResults(self):
        self._archive_store(manual=True)

    # ── hand off to Niche Scan ────────────────────────────────────
    @Slot()
    def analyzeResults(self):
        """Send the whole FILTERED set to Niche Scan for a set-level read.

        `self._filtered`, not the visible page and not the raw pool: the user has
        already expressed what they consider the niche by filtering, and a
        conclusion drawn from 10 rows of a 50-row match set would be wrong. Costs
        no quota — the rows are already in memory."""
        rows = self._filtered
        if not rows:
            self.toast.emit(tr("Nothing to analyze yet — run a search first."),
                            "error")
            return
        query = self._last_query or (self._query or "").strip()
        mode = "channel" if (self._mode == 1 and not self._viral_active) else "keyword"
        self.analyzeRequested.emit(list(rows), query, mode)

    @Slot(int)
    def loadArchivedGroup(self, group_id):
        """Bring an archived section's saved rows back into the live grid —
        the Search Archive page's "Open in Niche Finder". Purely local: the
        pool becomes the stored blob set, no API calls, and no re-archive
        (merging again would just bump run_count for a refresh that never
        happened)."""
        try:
            gid = int(group_id)
        except (TypeError, ValueError):
            return
        group = archive_get_group(gid) or {}
        rows = archive_get_rows(gid)
        if not rows:
            self.toast.emit(tr("That section has no saved rows."), "error")
            return
        self._pool = self._ensure_gold(rows)
        self._pool_days = None
        self._from_cache = ""
        self._cache_label = tr("archived")
        self._last_query = group.get("title") or group.get("key") or ""
        self._last_params = {}
        self._viral_tried = True          # never auto-replace an opened section
        if self._viral_active or self._viral_setup:
            self._viral_active = self._viral_setup = False
            self.viralChanged.emit()
        self._archive_note = ""
        self._archive_seq += 1
        self.applyFilters()
        # v3.43: show the saved section now, then swap in live numbers
        self._pool_live_token += 1
        token = self._pool_live_token
        snapshot = [dict(r) for r in rows]
        keys = youtube_api_keys(load_app_config())
        if not keys:
            return
        self._cache_label = tr("archived · updating live numbers…")
        self.statusChanged.emit()

        def worker():
            try:
                fresh = refresh_rows_live(
                    snapshot, keys,
                    stop_check=lambda: token != self._pool_live_token)
            except ScrapeCancelled:
                return
            except Exception:             # noqa: BLE001 — keep saved numbers
                fresh = []
            if fresh:
                try:
                    archive_update_rows(gid, fresh)
                except Exception:
                    pass
            self._poolLive.emit(token, fresh)

        threading.Thread(target=worker, daemon=True, name="niche-live").start()

    @Slot(int, list)
    def _on_pool_live(self, token, fresh):
        if token != self._pool_live_token:
            return                        # a newer search / section replaced it
        if not fresh:
            self._cache_label = tr("archived")
            self.statusChanged.emit()
            return
        by_id = {r.get("video_id"): r for r in fresh if r.get("video_id")}
        pool = []
        for r in self._pool or []:
            new = by_id.get(r.get("video_id"))
            if new is not None:
                new = dict(new)
                for k in ("_archive_key", "_first_seen", "_last_seen", "_is_favorite"):
                    if k in r:
                        new[k] = r[k]
            pool.append(new if new is not None else r)
        self._pool = compute_niche_metrics(pool)
        self._cache_label = tr("archived · numbers live")
        self.applyFilters()
        self.statusChanged.emit()

    @Slot(bool)
    def setForceRefresh(self, force):
        """Skip the pool cache on the next search. The legacy page read the
        Shift key at click time; QML has no equivalent GUI-thread probe, so the
        page exposes it as an explicit toggle instead."""
        force = bool(force)
        if force != self._force:
            self._force = force
            self.changed.emit()

    # ── card actions: download / bookmark / send to AI Ideas ─────────────
    @Slot(str, int)
    def startDownload(self, video_id, quality_index):
        """Download one result's actual video file. `quality_index` is a row of
        qualityOptions (the QML picker's selection).

        Reuses app.core.download, which is the same yt-dlp fallback ladder the
        legacy Archive page runs — including the bundled-ffmpeg bootstrap, so a
        1080p pick genuinely gets muxed instead of failing after the fact.
        """
        raw = self._raw_by_key.get(video_id)
        if not raw:
            self.toast.emit(tr("This result is no longer on screen."), "error")
            return
        url = raw.get("video_url") or (
            f"https://www.youtube.com/watch?v={video_id}" if video_id else "")
        if not url:
            self.toast.emit(tr("This item has no video URL."), "error")
            return
        entry = self._downloads.get(video_id) or {}
        if entry.get("state") == "running":
            return                       # already downloading this one

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

        # Proxy + cookie-browser must be read HERE, on the GUI thread — yt-dlp
        # does its own networking and never picks up the app's proxy on its own,
        # and on a filtered connection that's the difference between working and
        # a wall of SSL errors.
        cfg = load_app_config()
        proxy_url = (cfg.get("ai_proxy", "") or "").strip()
        cookies_browser = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        self._set_download(video_id, "running", 0, tr("Preparing…"),
                           url=url, qualityKey=quality_storage_key(quality))
        clear_cancel(video_id)   # drop any stale stop flag from a previous run
        self.toast.emit(tr("Download started — {t}").format(
            t=(raw.get("title") or "")[:60]), "download")
        # Mirror into the Downloads page's table, same as the legacy path, so a
        # download started from here shows up there too. quality_key + video_url
        # are persisted so a STOPPED download can be resumed at the same quality.
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

        The card's own stopped entry remembers the url + preset, so this works
        without going back through the quality picker. yt-dlp keeps its .part
        file, so it continues from roughly where it left off.
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
        self._set_download(video_id, "running", int(entry.get("pct") or 0),
                           tr("Resuming…"), cancelling=False,
                           url=url, qualityKey=quality_storage_key(quality))
        downloads_upsert(video_id, status="downloading", error_message="",
                         create_if_missing=False)
        self.toast.emit(tr("Resuming download…"), "download")
        self._launch_dl_worker(video_id, url, target_dir, quality,
                               proxy_url, cookies_browser)

    def _launch_dl_worker(self, video_id, url, target_dir, quality,
                          proxy_url, cookies_browser):
        """Run one download on a daemon thread. Shared by startDownload and
        resumeDownload so both report progress and cancellation identically."""
        def worker():
            # A raised exception must still reach _dlDone — without this guard
            # the thread died silently, the card sat on "downloading" forever,
            # and only an app restart (via the orphan-row reconcile) cleared it.
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
                    should_cancel=lambda v=video_id: is_cancelled(v))
            except Exception as exc:      # noqa: BLE001
                log_crash("NicheVM download worker failed:\n" + str(exc))
                ok, message, filepath = False, str(exc), ""
            self._dlDone.emit(video_id, ok, message, filepath)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str)
    def toggleSaved(self, video_id):
        """Bookmark a result into the Search Archive's Favorites, filed under
        the section this search already auto-archived into (falling back to a
        per-channel bucket) — the same resolution order as the legacy page."""
        raw = self._raw_by_key.get(video_id)
        if not raw:
            self.toast.emit(tr("This result is no longer on screen."), "error")
            return
        gid = (favorite_resolve_group_id(self._last_query)
               if self._last_query else None)
        if gid is None and self._viral_active and self._last_query:
            # A radar is not auto-archived, so its section may not exist yet:
            # starring a viral card creates it with just that video in it.
            try:
                with NicheVM._ARCHIVE_LOCK:
                    gid, _n, _u = archive_save_search(
                        self._last_query, dict(self._last_params or {}), [raw])
            except Exception:
                log_crash("viral favorite section failed\n" + traceback.format_exc())
                gid = None
        if gid is None:
            gid = favorite_ensure_channel_group(
                raw.get("channel_id"), raw.get("channel_title"))
        if gid is None:
            self.toast.emit(
                tr("This video is missing channel info, so it can't be filed "
                   "under a favorites section."), "error")
            return
        changed, _total = favorite_mark_item(gid, raw)
        group = archive_get_group(gid) or {}
        self._saved.add(video_id)
        self.savedChanged.emit()
        title = (raw.get("title") or "")[:60]
        self.toast.emit(
            (tr('"{v}" was added to Favorites under "{g}".') if changed
             else tr('"{v}" is already in Favorites under "{g}".')).format(
                v=title, g=group.get("title") or "—"),
            "success")

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
            self.toast.emit(tr("This result is no longer on screen."), "error")
            return
        sink = self.ideas_sink
        if not callable(sink):
            self.toast.emit(tr("AI Ideas isn't ready yet — try again in a moment."), "error")
            return
        try:
            added, _already = sink([dict(raw)], tr("Niche Finder"))
        except Exception as exc:          # noqa: BLE001 — surfaced to the user
            self.toast.emit(str(exc), "error")
            return
        if added:
            self.toast.emit(tr("Added to AI Ideas — it's ticked as a reference there."), "success")
        else:
            self.toast.emit(tr("Already picked on AI Ideas."), "info")

    # ── download signal handlers (GUI thread) ───────────────────────────
    def _set_download(self, video_id, state, pct, text, **extra):
        """Publish one card's download state.

        `extra` merges into the existing entry rather than replacing it, so a
        status line arriving between two progress ticks doesn't wipe the byte
        counts the card is animating from.

        The same values are mirrored into the SHARED live-progress store so the
        Downloads page shows this download moving too. Without that mirror a
        grid download appeared there as a row stuck at 0% until you navigated
        away and back (which re-read the slower, DB-persisted percentage).
        """
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
        self.downloadsChanged.emit()
        if state == "running":
            dlp.publish(video_id, running=True, pct=pct, text=text,
                        cancelling=bool(entry.get("cancelling")),
                        done=entry["done"], total=entry["total"],
                        speed=entry["speed"], eta=entry["eta"],
                        fragDone=entry["fragDone"], fragTotal=entry["fragTotal"])
        else:
            # done / error — the Downloads page reads the persisted row from here
            # on, so the transient entry must go.
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
        self._set_download(video_id, entry.get("state", "running"),
                           entry.get("pct", 0), text)

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
        # be INSERTed back by a late tick from this still-unwinding worker (that
        # is what produced the title-less "Untitled" ghost rows).
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
        """Byte-level progress. Kept separate from _on_dl_progress so the
        percentage (which the card's ring binds to) still updates on providers
        that report no total size."""
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

        A card's download is mirrored into the Downloads page's table, and that
        row was labelled with the tier the user picked — a promise the download
        can't always keep (a video that only ships 720p answers a 1080p request
        with 720p). Relabelling here means the Downloads list describes the file
        on disk. UPDATE-ONLY, so a row the user already deleted stays deleted.
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
        self._set_download(video_id, "done" if ok else "error", 100 if ok else 0,
                           tr("Open") if ok else tr("Failed"),
                           speed=0.0, eta=0)
        if ok and filepath and os.path.isfile(filepath):
            # The card's button flips to Open immediately (downloadsChanged
            # fires from _set_download above, and downloadedIds notifies on
            # the same signal) — no need to wait for a page revisit.
            self._downloaded.add(video_id)
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

    @Slot()
    def stopSearch(self):
        if self._running:
            self._stop = True
            self._set_status(tr("Stopping …"), "warn")

    # ── search entry point ───────────────────────────────────────────────
    @Slot()
    def search(self):
        text = (self._query or "").strip()
        channel_mode = self._mode == 1
        if not text:
            self._set_status(
                tr("Enter a channel URL first.") if channel_mode
                else tr("Enter at least one niche keyword first."), "error")
            return
        if self._running:
            return

        # The key is cached at construction; Settings saves to config.json while
        # the app runs, so re-read it here — otherwise the first search after
        # saving a key still sees the old (empty) value until a restart.
        self.refreshApiKeys()
        scrape_mode = (not channel_mode) and self._source == 1
        api_key = (self._api_key or "").strip()
        if not api_key and not scrape_mode:
            self._set_status(tr("Add your YouTube Data API key in Settings first."), "error")
            return

        days = NICHE_TIMEFRAMES[self._timeframe][1]
        pages = NICHE_DEPTHS[self._depth][1]
        target = self._depth_target()
        fmt = _FMT_MAP[self._format]

        if channel_mode:
            params = {"mode": "channel", "source": "api", "query": text,
                      "queries": [text], "days": days, "pages": pages,
                      "deep": False, "order": "date", "lang": "", "region": "",
                      "fmt": fmt, "target": target}
        else:
            sort_row = NICHE_SORTS_UI[self._sort]
            params = {
                "mode": "keyword",
                "source": "scrape" if scrape_mode else "api",
                "query": text,
                "queries": self._queries(),
                "days": days,
                "pages": pages,
                "deep": self._deep,
                "order": sort_row[2],
                "scrape_sort": sort_row[3],
                "lang": NICHE_LANGS[self._lang][1],
                "region": NICHE_REGIONS[self._region][1],
                "fmt": fmt,
                # Hard cap on how many videos this run collects (None = the
                # last depth row: no cap, everything YouTube has in range).
                "target": target,
            }

        self._requested_days = days
        self._from_cache = ""
        if self._viral_active or self._viral_setup:
            self._viral_active = self._viral_setup = False
            self.viralChanged.emit()
        self._last_query = text     # which archive section favorites file under
        self._last_params = params  # ditto for the archive's stored params
        self._archive_note = ""
        self._archive_seq += 1
        self._pool_live_token += 1   # a new search replaces an archived pool
        self._scrape_note = ""
        self._stop = False
        self._running = True
        # Freeze the filters the user is searching WITH, on this (the GUI)
        # thread, before the worker starts. The worker uses this both to widen
        # the search when matches are scarce and to report how many it found.
        self._search_filters = self._current_filters()
        self._widen_passes = 0
        # Reset the live panel with the flag: a second search showing the first
        # one's stage and counts while it starts up is worse than showing nothing.
        self._pct = 0
        self._phase = ""
        self._found = 0
        self._enriched = 0
        self.runningChanged.emit()
        self.progressChanged.emit()
        self._set_status(tr("Contacting YouTube …"), "muted")

        threading.Thread(target=self._worker, args=(params,), daemon=True).start()

    def _worker(self, params):
        try:
            if params.get("mode") == "viral":
                rows = self._fetch_viral(params)
            else:
                rows = self._fetch(params)
                rows = self._widen_until_matched(params, rows)
            # Read every row's language/country evidence here, on the worker:
            # it is the one per-row cost of the audience filter, and doing it
            # now keeps the first live re-filter on the GUI thread instant.
            for r in rows:
                _A.row_evidence(r)
            self._searchDone.emit(rows, "")
        except ScrapeCancelled:
            self._searchDone.emit([], "__cancelled__")
        except QuotaExceededError:
            self._searchDone.emit([], tr(
                "YouTube API quota exhausted for today. Switch the data source "
                "to Web scrape, or try again after midnight Pacific time."))
        except Exception as exc:
            log_crash(f"qml niche search failed\n{traceback.format_exc()}")
            # A scrape-mode search walks youtube.com over several requests; a
            # proxy dropping one of them used to surface as a bare
            # "[WinError 10054] …" with no hint that the fix is the proxy.
            # "YouTube" is not passed through tr(): it is a brand name, and the
            # sentence it lands in is already translated.
            self._searchDone.emit([], explain_network_error(exc, "YouTube"))

    def _widen_until_matched(self, params, rows):
        """Keep fetching until the pool actually contains the rows the filters ask for.

        The point of the whole feature: "1M–10M views, 2k–10k subs, shorts only"
        has to come back with those videos, not with a wide pool and a shrug.
        YouTube's search endpoint can't express subscriber or view bounds, so the
        only lever is to look at MORE of YouTube — deeper time windows (which is
        what surfaces small channels at all, since one wide window only ever
        returns the biggest videos) and more pages — and keep everything that
        matches. Bounded by _WIDEN_MAX_CALLS so a narrow filter can't silently
        spend the day's whole search bucket.

        Runs on the worker thread; reports through the same progress channel as
        the rest of the run.
        """
        filters = self._search_filters
        if not filters or not self._has_narrow_filters_for(filters):
            return rows
        if params.get("target"):
            # The user picked an exact count ("300 videos"): that is the
            # budget. Widening would fetch past it and spend quota they did
            # not ask to spend — only the uncapped last depth row widens.
            return rows
        if params.get("source") == "scrape":
            # A scrape has no time windows to deepen, so another pass would
            # return the same page again. Its own search is already the only
            # pool we get.
            return rows
        # A channel scan widens by walking further down that one channel's
        # uploads playlist (playlistItems, billed from the big bucket rather
        # than the 100/day search bucket), so it gets its own — and much
        # cheaper — budget, and it runs out on its own: past 200 uploads the
        # fetch returns the same ids and the "no new rows" check stops it.
        is_channel = params.get("mode") == "channel"
        source = params.get("source")
        if source == "scrape":
            # The scrape's own, much cheaper budget. Its widening cost is
            # youtube.com/results continuations (zero quota, real wire time),
            # and counting it with the API's queries × windows × pages formula
            # both over-charged it and let a narrow filter spend the API's
            # whole widening budget on continuations.
            budget = _WIDEN_MAX_CALLS_SCRAPE
        elif is_channel:
            budget = _WIDEN_MAX_CALLS_CHANNEL
        else:
            budget = _WIDEN_MAX_CALLS

        pool = list(rows)
        seen = {r.get("video_id") for r in pool if r.get("video_id")}
        queries = params.get("queries") or [params.get("query") or ""]
        days = params.get("days")
        pages = int(params.get("pages") or 1)
        spent = 0

        for attempt in range(1, _WIDEN_MAX_PASSES + 1):
            if self._stop_check():
                break
            if len(apply_niche_filters(pool, filters)) >= _WIDEN_TARGET:
                break
            next_pages = min(pages * 2, NICHE_DEPTHS[-1][1])
            # Scrape and channel passes both scale with `pages` (max_items =
            # pages * 50; want = min(200, pages * 50)). Only the API path has
            # the extra time-window and query-variant multiplier on top.
            if is_channel or source == "scrape":
                cost = next_pages
            else:
                cost = estimate_search_calls(
                    len(queries), len(build_time_windows(days, True)),
                    next_pages)
            if spent + cost > budget:
                break
            deeper = dict(params)
            deeper["pages"] = next_pages
            if source != "scrape":
                # `deep` only means anything to the API path's time windows;
                # setting it for a scrape would add a meaningless dimension
                # to that pass's cache key.
                deeper["deep"] = True
            self._progress(
                min(44, 30 + attempt * 4),
                tr("Widening the search to reach your filters (pass {n}) …")
                .format(n=attempt),
                _S.PHASE_DISCOVER, {"found": len(pool)})
            try:
                more = self._fetch(deeper)
            except ScrapeCancelled:
                raise
            except QuotaExceededError:
                break
            except Exception:                      # noqa: BLE001
                # Widening is a best-effort improvement on top of a pool we
                # already have — a failed extra pass must not throw away the
                # results the first pass returned.
                log_crash("niche widen pass failed\n" + traceback.format_exc())
                break
            spent += cost
            pages = next_pages
            added = 0
            for r in more:
                vid = r.get("video_id")
                if vid and vid not in seen:
                    seen.add(vid)
                    pool.append(r)
                    added += 1
            self._widen_passes = attempt
            if not added:
                break
        return pool

    def _has_narrow_filters_for(self, filters):
        """_has_narrow_filters() against a filter dict rather than live form
        state, so the worker can ask the question without touching the UI."""
        if filters.get("format") or filters.get("lang") or filters.get("region"):
            return True
        return any(filters.get(k) is not None for k in
                   ("subs_min", "subs_max", "views_min", "views_max", "mult_min"))

    # ── fetch pipelines (worker thread — never touch Qt/widget state) ────
    def _fetch(self, params):
        key = niche_cache_key(params)
        cached, fetched_at = niche_cache_get(key)
        self._cache_live = False
        if cached and not self._force:
            self._from_cache = fetched_at or ""
            # v3.43: the LIST may come from the cache (that's what saves the
            # 100-unit searches), but the NUMBERS on it must not be hours old.
            # Re-read views / likes / subs: ~2 units per 50 videos.
            try:
                fresh = refresh_rows_live(cached, youtube_api_keys(),
                                          stop_check=self._stop_check)
                if fresh:
                    cached = compute_niche_metrics(fresh)
                    niche_cache_put(key, params, cached)
                    self._cache_live = True
            except ScrapeCancelled:
                raise
            except LiveStatsError:
                pass                      # no key / quota: cached numbers
            except Exception as exc:      # noqa: BLE001
                log_crash("Niche cache live refresh failed:\n" + repr(exc))
            return cached
        if params["mode"] == "channel":
            rows = self._fetch_channel(params)
        elif params["source"] == "scrape":
            rows = self._fetch_scrape(params)
        else:
            rows = self._fetch_api(params)
        niche_cache_put(key, params, rows)
        return rows

    def _fetch_api(self, params):
        yt = build_youtube_service((self._api_key or "").strip())
        queries = params["queries"] or [params["query"]]
        target = params.get("target")
        windows = build_time_windows(
            params["days"], params["deep"],
            max_windows=capped_window_count(len(queries), target))
        # Shorts can be asked for server-side (videoDuration=short means "under
        # four minutes", which is a superset of real Shorts — the local
        # is_short cut below tightens it to under three).
        #
        # Long-form is deliberately NOT forwarded. The API's own buckets are
        # short (<4min) / medium (4–20min) / long (>20min), so "long" would
        # silently throw away every 4-to-20-minute video — which is most of what
        # "long-form" means here. Fetching unfiltered and dropping the Shorts
        # locally is the only correct way to say "everything that isn't a Short".
        fmt = params.get("fmt")
        duration = "short" if fmt == "short" else None
        video_ids = niche_search_api(
            yt, queries, params["order"], windows,
            params["pages"], region=params["region"] or None,
            lang=params["lang"] or None,
            video_duration=duration,
            stop_check=self._stop_check, progress=self._progress,
            quota_cb=search_quota_bump, target=target)
        if not video_ids:
            return []
        return self._enrich(yt, [{"video_id": v} for v in video_ids])

    def _fetch_scrape(self, params):
        cap = params.get("target")
        # Capped depth → exactly that many; the uncapped last row asks for as
        # many as the pool can hold and lets YouTube's own end-of-results stop it.
        target = int(cap) if cap else NICHE_MAX_POOL
        # PACE — this is what "the scraper got slow" was. The sweep below is
        # powerful but expensive: three sort orders × up to five query variants
        # × dozens of continuation pages each, at real network latency per
        # request. Measured, a deep run used to walk 150+ requests. So the sweep
        # only engages when the user explicitly asked for a deep setting, and
        # "Fast" / "Normal" run exactly like the pre-3.4 scraper did: one query,
        # one sort, a handful of continuation pages.
        #
        #   Fast(1)  → 4 pages · Normal(2) → 6 · Deep(4) → 10 (+sort sweep)
        #   Very deep(6) → 14 (+sort sweep) · Maximum(14) → 30 · Deepest(18) → 36
        #     (+sort sweep AND the comma-separated query variants)
        pages = int(params["pages"] or 1)
        rows = niche_scrape_search(
            params["query"], days=params["days"],
            sort_by=params.get("scrape_sort", 3),
            duration=(1 if params["fmt"] == "short" else 0),
            max_items=target,
            stop_check=self._stop_check, progress=self._progress,
            queries=(params.get("queries") if pages >= 6 else None),
            sweep_sorts=(pages >= 4),
            # The viewer country YouTube ranks for (gl). The scrape used to be
            # pinned to the US whatever the Country dropdown said.
            region=params.get("region") or "",
            page_budget=(max(2, min(36, pages * 2 + 2)) if cap else 80))
        # A scrape is capped by YouTube itself, not by us: its results page stops
        # handing back continuations after roughly 370 videos for any one keyword,
        # however deep the setting. Saying so is the difference between "the app
        # is broken" and "that keyword has 370 videos in this window" — and it
        # points at the one lever that does work, which is searching more
        # keywords. (See applyFilters, which surfaces this note.)
        if rows and len(rows) < (target if cap else max(50, params["pages"] * 50)):
            self._scrape_note = tr(
                "YouTube returned {n} videos — all it has for this keyword and "
                "window, whatever the depth. Add more keywords, separated by "
                "commas, to search deeper.").format(n=len(rows))
        else:
            self._scrape_note = ""
        if not rows:
            return []
        api_key = (self._api_key or "").strip()
        if api_key:
            yt = build_youtube_service(api_key)
            return self._enrich(yt, rows)
        # no key → enrich impossible; still compute what metrics we can
        return compute_niche_metrics(rows)

    def _enrich(self, yt, base_rows):
        v_map = enrich_videos(yt, [r["video_id"] for r in base_rows],
                              self._stop_check, self._progress)
        ch_ids = [(v.get("snippet") or {}).get("channelId") for v in v_map.values()]
        c_map = enrich_channels(yt, ch_ids, self._stop_check, self._progress)
        rows = []
        for base in base_rows:
            v = v_map.get(base["video_id"])
            cid = (((v or {}).get("snippet") or {}).get("channelId")
                   or base.get("channel_id"))
            rows.append(merge_niche_row(base, v, c_map.get(cid)))
        return compute_niche_metrics(rows)

    def _fetch_channel(self, params):
        api_key = (self._api_key or "").strip()
        yt = build_youtube_service(api_key)
        channel_id = resolve_channel_id(yt, params["query"], self._stop_check)
        if not channel_id:
            raise RuntimeError(tr("Could not resolve that channel. Try pasting the "
                                  "full channel URL."))
        ch_resp = execute_with_retry(
            yt.channels().list(part="snippet,statistics,contentDetails",
                               id=channel_id), self._stop_check)
        if not ch_resp.get("items"):
            raise RuntimeError(tr("Channel not found."))
        ch_item = ch_resp["items"][0]
        uploads_id = ch_item["contentDetails"]["relatedPlaylists"]["uploads"]

        cap = params.get("target")
        want = min(NICHE_MAX_POOL, int(cap)) if cap else NICHE_MAX_POOL
        video_ids, token = [], None
        while len(video_ids) < want:
            if self._stop_check():
                raise ScrapeCancelled()
            resp = execute_with_retry(yt.playlistItems().list(
                part="contentDetails", playlistId=uploads_id,
                maxResults=min(50, want - len(video_ids)),
                pageToken=token), self._stop_check)
            video_ids += [i["contentDetails"]["videoId"] for i in resp.get("items", [])]
            token = resp.get("nextPageToken")
            if not token:
                break
        video_ids = list(dict.fromkeys(video_ids))[:want]
        if not video_ids:
            raise RuntimeError(tr("This channel has no public uploads."))
        self._progress(45, tr("Fetching exact view counts …"))
        v_map = enrich_videos(yt, video_ids, self._stop_check, self._progress)
        rows = [merge_niche_row({"video_id": vid}, v_map.get(vid), ch_item)
                for vid in video_ids if v_map.get(vid)]
        rows = compute_niche_metrics(rows)
        views = [r["view_count"] for r in rows if r["view_count"]]
        median = max(statistics.median(views), 1) if views else 1
        for r in rows:
            r["outlier_ratio"] = r["view_count"] / median
        return rows

    # ── GUI-thread slots (queued from worker) ───────────────────────────
    @Slot(int, str, str, "QVariant")
    def _on_progress(self, pct, text, phase, info):
        self._pct = int(pct)
        self._phase = str(phase or "")
        counts = info if isinstance(info, dict) else {}
        # Each stage reports only ITS OWN counts, so a key is updated only when
        # present. Assigning `counts.get("found") or 0` unconditionally would zero
        # the discovered-videos figure the moment the stats stage started, and the
        # panel would show "142 videos found" flick to nothing mid-run.
        if "found" in counts:
            self._found = int(counts.get("found") or 0)
        if "enriched" in counts:
            self._enriched = int(counts.get("enriched") or 0)
        elif "channels" in counts:
            self._enriched = int(counts.get("channels") or 0)
        if text:
            self._set_status(text, "muted")
        # Emitted even when the text is unchanged: the counts move on every tick
        # and the loading panel binds to those, not only to the sentence.
        self.progressChanged.emit()

    @Slot(list, str)
    def _on_done(self, rows, error):
        self._running = False
        self._stop = False
        self._pct = 0
        self._phase = ""
        self.runningChanged.emit()
        self.progressChanged.emit()
        self._update_quota()

        if self._viral_active and not self._pool and error:
            # A radar that was stopped or failed before showing anything goes
            # back to its picks panel instead of an empty "nothing viral".
            self._viral_active = False
            self._viral_setup = True
            self._viral_loaded_sig = None
            self.viralChanged.emit()
            self.changed.emit()
        if error == "__cancelled__":
            self._set_status(tr("Search stopped."), "warn")
            return
        if error:
            self._set_status("✗ " + error, "error")
            self._pool = []
            self._filtered = []
            self._page = 0
            # Metrics first, then the page: _render_page() is what emits
            # resultsChanged, so anything computed after it reaches QML late.
            self._update_metrics([])
            self._render_page()
            self.toast.emit(tr("Niche Finder search failed"), "error")
            announce("error", tr("Niche Finder search failed"), error,
                     page=4, icon="nav_niche", source=tr("Niche Finder"))
            return

        self._pool = self._ensure_gold(rows)
        self._pool_days = getattr(self, "_requested_days", None)
        cached_at = getattr(self, "_from_cache", "")
        if cached_at and getattr(self, "_cache_live", False):
            self._cache_label = tr("list cached {ago} · numbers live").format(
                ago=days_ago_str(cached_at))
        else:
            self._cache_label = (tr("cached · {ago}").format(ago=days_ago_str(cached_at))
                                 if cached_at else tr("live"))
        self.applyFilters()
        # Say out loud what the extra passes bought, when they ran. A search
        # that quietly went looking three times and then reported a plain match
        # count would hide both the quota it spent and why it took longer.
        if self._widen_passes:
            note = " " + tr("The search was widened {n} time(s) to reach these "
                            "filters.").format(n=self._widen_passes)
            self._set_status(self._status + note, self._status_kind)
        # Results are permanent from here on: the pool is merged into its
        # keyword section in the Search Archive whether or not the cache entry
        # later expires. Same auto-archive the legacy page did.
        if (self._last_params or {}).get("mode") == "viral":
            # A radar is a look, not a search: it lands in the archive only
            # when the user presses "Save to Archive" (or stars a card).
            self._viral_cache_memo = None
            self.viralChanged.emit()          # lens counts
            self.changed.emit()               # cost now reads "free · cached"
            gold = sum(1 for r in self._pool if r.get("gold_tier") == "gold")
            msg = tr("{n} viral videos on the radar.").format(n=len(self._filtered))
            if gold:
                msg += " " + tr("{g} of them are Gold.").format(g=gold)
            self.toast.emit(msg, "success")
            return
        self._archive_store()
        # Report what MATCHES, not what was fetched: with a narrow filter the
        # pool can be several hundred rows of which a handful qualify, and
        # "412 results found" next to an empty-looking grid was its own bug.
        self.toast.emit(
            tr("{n} results found.").format(n=len(self._filtered)), "success")
        announce("success", tr("Niche search complete"),
                 tr("{n} results found.").format(n=len(self._filtered)),
                 page=4, icon="nav_niche", source=tr("Niche Finder"))

    # ── in-memory filter/sort (zero API) ────────────────────────────────
    @Slot()
    def applyFilters(self):
        pool = self._pool or []
        # Built by _current_filters() so the live re-filter and the search-time
        # filter can never disagree — in particular about the subscriber range
        # in Single Channel Scan, which is deliberately not applied there.
        filters = self._current_filters()
        rows = apply_niche_filters(pool, filters)
        if self._viral_active and self._viral_lens:
            lens = self._VIRAL_LENSES[self._viral_lens][1]
            rows = [r for r in rows if self._lens_ok(r, lens)]
        sort_key = NICHE_SORTS_UI[self._sort][1]
        rows = sort_niche_rows(rows, sort_key)
        channels = self._channels_view
        if channels:
            rows = aggregate_by_channel(rows)
            rows = sort_niche_rows(rows, sort_key)

        # Whole match set (capped), then only the current page is flattened for
        # QML. Re-filtering always lands the user back on page 1, exactly as
        # the legacy grid did unless it was explicitly told to keep the page.
        self._filtered = rows[:NICHE_MAX_POOL]
        self._page = 0
        # v3.39.1 fix: metrics MUST be computed before _render_page(), because
        # _render_page() is the one that emits resultsChanged. The old order
        # (render, then metrics) emitted the signal while the scoreboard still
        # held the previous run's numbers (or the initial "0" / "—"), so a fresh
        # search showed an empty scoreboard until something else re-emitted
        # resultsChanged, e.g. flipping the Videos/Channels tab.
        self._update_metrics(rows)
        self._render_page()

        if not pool:
            return
        if not rows:
            msg = tr("No result matches these filters — widen the subscriber or "
                     "view range. ({total} were fetched.)").format(total=len(pool))
            aud = self._audience_note(pool, rows, filters)
            if aud:
                msg += " " + aud
            if self._widen_passes:
                # Say that the search already went looking harder, or the user
                # will reasonably assume the app only tried once.
                msg += " " + tr("The search was already widened {n} time(s).").format(
                    n=self._widen_passes)
            self._set_status(msg, "warn")
        else:
            msg = tr("✓ {shown} of {total} results match your filters.").format(
                shown=len(rows), total=len(pool))
            unknown_subs = sum(1 for r in pool
                               if r.get("subscriber_count") in (None, 0))
            if unknown_subs and unknown_subs == len(pool):
                msg += "  " + tr("Subscriber data is unavailable — add an API key "
                                 "in Settings to filter by subscribers.")
            if len(rows) > NICHE_MAX_POOL:
                msg += "  " + tr("Showing the first {n} — narrow the filters to "
                                 "reach the rest.").format(n=NICHE_MAX_POOL)
            pool_days = self._pool_days
            want_days = filters.get("days")
            if pool_days and want_days and want_days > pool_days:
                msg += "  " + tr("This window is wider than the one you searched — "
                                 "press Search again to fetch it.")
            # A short web-scrape run: say it is YouTube's ceiling, not a failure.
            if self._scrape_note:
                msg += "  " + self._scrape_note
            aud = self._audience_note(pool, rows, filters)
            if aud:
                msg += "  " + aud
            self._set_status(msg, "ok")

    def _audience_note(self, pool, rows, filters):
        """How the language / country cut decided — so a short result reads as
        "92 had no language info" instead of as a broken search."""
        lang, region = filters.get("lang"), filters.get("region")
        if not (lang or region) or self._channels_view:
            return ""
        base = dict(filters, lang="", region="")
        before = apply_niche_filters(pool, base)
        dropped = max(0, len(before) - len(rows))
        b = _A.breakdown(rows, lang, region)
        parts = []
        for dim in ("lang", "region"):
            d = b[dim]
            if not d:
                continue
            ver, lik = d.get(_A.VERIFIED, 0), d.get(_A.LIKELY, 0)
            unk = d.get(_A.UNKNOWN, 0)
            label = tr("Language") if dim == "lang" else tr("Country")
            bit = tr("{dim}: {v} verified, {l} inferred").format(dim=label, v=ver, l=lik)
            if unk:
                bit += tr(", {u} unknown").format(u=unk)
            parts.append(bit)
        note = " · ".join(parts)
        if dropped:
            note += (" · " if note else "") + tr(
                "{n} filtered out by language/country").format(n=dropped)
            if filters.get("precision") != "broad":
                # Name the lever: most drops on a narrow pool are "no data", not
                # "wrong language", and Broad keeps those.
                prec = filters.get("precision")
                unk = sum(1 for r in before
                          if _A.passes(r, lang, region, "broad")
                          and not _A.passes(r, lang, region, prec))
                if unk:
                    note += " " + tr("(Broad would keep {u} more with weaker evidence)").format(u=unk)
        return note

    def _render_page(self):
        """Flatten just the current page into the dicts the QML cards bind to.

        Keeping `_raw_by_key` to the visible page only is deliberate: the card
        actions (download / favorite / send-to-ideas) can only ever be pressed
        on a card that exists, and a page-scoped map means a 900-row pool never
        pins 900 raw rows in a second dict.
        """
        channels = self._channels_view
        start = self._page * NICHE_PAGE_SIZE
        page_rows = self._filtered[start:start + NICHE_PAGE_SIZE]
        _prefetch_page_thumbs(page_rows,
                              self._filtered[start + NICHE_PAGE_SIZE:start + 2 * NICHE_PAGE_SIZE])
        self._visible = [self._row_for_qml(r, channels) for r in page_rows]
        # Keep the FULL raw rows reachable by the id the cards hand back, so a
        # download/favorite/idea action has the real numeric fields (view_count,
        # velocity, published_at …) that the flattened display dict has already
        # turned into strings. Channel rows resolve to their best video, which
        # is what their actions target.
        self._raw_by_key = {}
        for r in page_rows:
            target = (r.get("best_video") or r) if channels else r
            vid = target.get("video_id") or ""
            if vid:
                self._raw_by_key[vid] = target
        self.resultsChanged.emit()

    def _update_metrics(self, rows):
        self._m_matches = str(len(rows))
        gems = [r for r in rows
                if (r.get("multiplier") or 0) >= 10
                and (r.get("subscriber_count") or 0) and r["subscriber_count"] < 100_000]
        self._m_gems = str(len(gems))
        mults = [r.get("multiplier") for r in rows if r.get("multiplier")]
        self._m_best = format_multiplier(max(mults)) if mults else "—"
        total_views = sum(r.get("view_count", 0) or 0 for r in rows)
        self._m_views = humanize_count(total_views)
        # Context for the scoreboard, all from the same rows — no new numbers,
        # just the ratios that make the four big ones readable at a glance.
        pool_n = len(self._pool or [])
        self._m_pool = pool_n
        self._m_match_frac = (len(rows) / pool_n) if pool_n else 0.0
        self._m_gem_frac = (len(gems) / len(rows)) if rows else 0.0
        self._m_avg_views = humanize_count(int(total_views / len(rows))) if rows else "—"
        best = max(rows, key=lambda r: r.get("multiplier") or 0) if mults else None
        self._m_best_title = (best.get("title") or "") if best else ""
        self._m_best_channel = (best.get("channel_title") or "") if best else ""
        # Multiplier distribution on a log scale (0.1x … 1000x+), 14 bins,
        # normalised to the tallest bin — the hero cell's sparkline.
        bins = [0] * 14
        for m in mults:
            k = int((math.log10(max(m, 0.1)) + 1) / 4 * 14)
            bins[max(0, min(13, k))] += 1
        top = max(bins) if bins else 0
        self._m_spark = [b / top for b in bins] if top else []

    def _row_for_qml(self, r, channel):
        """Flatten a pool row into the plain-string dict the QML cards read."""
        subs = r.get("subscriber_count")
        subs_txt = (tr("hidden") if r.get("subs_hidden")
                    else (humanize_count(subs) if subs is not None else "—"))
        mult = r.get("multiplier")
        eng = r.get("engagement")
        base = {
            "isChannel": channel,
            "videoId": r.get("video_id", ""),
            "channelId": r.get("channel_id", ""),
            "title": r.get("title", "") or r.get("channel_title", ""),
            "channelTitle": r.get("channel_title", "—"),
            "channelUrl": r.get("channel_url", ""),
            "videoUrl": r.get("video_url", ""),
            # Pre-encoded ids for the `image://thumbs/<id>` provider. Encoding
            # here rather than with Qt.btoa() in QML keeps it off the binding
            # path and avoids that function's deprecation warning.
            "thumbId": _thumb_id(r.get("thumbnail_url", "")),
            "channelThumbId": _thumb_id(r.get("channel_thumb_url", "")),
            "subsText": subs_txt,
            "views": humanize_count(r.get("view_count", 0) or 0),
            "multiplier": format_multiplier(mult) if mult is not None else "—",
            "multiplierValue": float(mult) if mult is not None else 0.0,
            "isGem": bool(is_gem_row(r)),
            # Gold Score (app.core.niche.gold): 0-100 + "gold" / "hot" / "".
            "goldScore": int(r.get("gold_score") or 0),
            "goldTier": r.get("gold_tier") or "",
            "duration": fmt_duration(r.get("duration_s", 0)),
            # Whether this row is a Short — the card passes it to downloadThumb
            # so a Short's cover exports 1080×1920 and long-form 1920×1080.
            "isShort": bool(r.get("is_short")),
            "age": days_ago_str(r.get("published_at") or ""),
            # Compact age for the card footer ("12h", "3d") — days_ago_str()'s
            # "12h ago" is too long for that corner slot.
            "ageShort": _age_short(r.get("published_at") or ""),
            "speed": humanize_count(r.get("velocity", 0) or 0) + "/h",
            # Same velocity/engagement numbers, unit-free, for the stat strip
            # that puts the unit underneath the value instead of beside it.
            "perHour": humanize_count(r.get("velocity", 0) or 0),
            "engagement": (f"{eng * 100:.1f}%" if eng else "—"),
            "langLabel": _lang_label(r),
            # Viral Radar: "#3 US" — where the video sits on the chart it was
            # found on. Empty for every non-radar row, so the chip hides.
            "viralTag": (f"#{r.get('viral_rank')} {r.get('viral_region') or ''}".strip()
                         if r.get("viral_rank") else ""),
        }
        if channel:
            best = r.get("best_video") or {}
            bm = r.get("best_multiplier")
            base.update({
                "videoCount": str(r.get("video_count", 0)),
                "bestMultiplier": format_multiplier(bm) if bm is not None else "—",
                "bestTitle": best.get("title", "") or "—",
                "bestThumbId": _thumb_id(best.get("thumbnail_url", "")),
                "bestVideoUrl": best.get("video_url", ""),
                # A channel row's actions act on its best video (same rule the
                # legacy _niche_actions used), so carry that id through.
                "videoId": best.get("video_id", ""),
            })
        return base

    # ── export ──────────────────────────────────────────────────────────
    @Slot(str)
    def exportResults(self, path):
        # The RAW filtered rows, not the QML-flattened page: the export needs
        # the numeric fields (view_count, velocity, published_at …) that
        # _row_for_qml has already turned into display strings, and it covers
        # the whole match set rather than just the page on screen.
        rows = self._filtered
        if not rows:
            self.toast.emit(tr("Nothing to export yet — run a search first."), "error")
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
                "Gold score": r.get("gold_score", ""),
                "Published": r.get("published_at", ""),
                "Duration": fmt_duration(r.get("duration_s", 0)),
                "Format": "Shorts" if r.get("is_short") else "Long-form",
                # What the audience filter saw: the language (declared, or
                # "~es" when read off the title) and the channel's country.
                "Language": _export_lang(r),
                "Country": (r.get("channel_country") or ""),
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



