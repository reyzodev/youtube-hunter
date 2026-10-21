"""app.qml_backend.vm.ideas_vm - YouTube Hunter (QML).

ViewModel behind AIIdeasPage.qml — the migrated AI Ideas page.

The legacy page could only do one thing: pick reference videos out of an
archived keyword section and hand them to the AI to reverse-engineer. This one
adds the creator's own idea as a first-class input, with three explicit modes:

  0 "videos" — reverse-engineer the pattern the picked videos share (legacy
               behaviour).
  1 "blend"  — the creator's brief is the subject; the picked videos are only a
               style/packaging source.
  2 "brief"  — the brief is all there is; no reference videos consulted.

The modes are enforced in the prompt itself (see
app.core.ai.content_lab.generate_content_lab_ideas), not by post-filtering, so
"blend" genuinely keeps the creator's topic instead of drifting onto the
references'.

Everything heavy is the shared, UI-free core: archive_* for the saved keyword
sections, apply_niche_filters/sort_niche_rows for the in-memory re-slicing (zero
API calls, zero quota), AIClient for the provider call, and content_lab_* to
persist the generated blueprints — the same tables the legacy Content Lab page
reads, so nothing is orphaned. The generation runs on a daemon thread and
reports back over a queued Qt signal, the same worker→GUI pattern as the other
VMs.
"""

import base64
import threading
import traceback

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication

from app.core.ai.profiles import client_from as client_from_route, resolve as resolve_ai_route
from app.core.ai.clients import AIClient, api_mode_for
from app.core.ai.content_lab import generate_content_lab_ideas
from app.core.analysis.csv_report import csv_blueprint_source, csv_classify_format
from app.core.db.archive import archive_get_rows, archive_list_groups
from app.core.db.content_lab import (
    content_lab_add_ideas, content_lab_classify_format,
    content_lab_delete_idea, content_lab_get_entry_videos,
    content_lab_get_ideas, content_lab_get_or_create_entry,
    content_lab_merge_entry_videos, content_lab_toggle_favorite,
    content_lab_update_idea)
from app.core.niche.config import AI_IDEAS_SORTS_UI
from app.core.niche.helpers import fmt_duration, format_multiplier
from app.core.niche.search import apply_niche_filters
from app.core.niche.sorting import sort_niche_rows
from app.core.net import CancelToken, RequestCancelled, cancel_scope
from app.core.utils import days_ago_str, humanize_count, open_external_url, local_path_from_url
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm._idea_shape import idea_for_qml as _shared_idea_for_qml
from app.qml_backend.desktop_notifier import announce

# One page of reference cards at a time. Same reasoning as NICHE_PAGE_SIZE in
# niche_vm: every card carries mask layers, so materialising a 300-video keyword
# section at once would allocate hundreds of GPU textures for rows nobody has
# scrolled to.
IDEAS_PAGE_SIZE = 24

# _genDone error sentinel for a run the user stopped (never shown as an error).
_CANCELLED = "__cancelled__"

# segmented-control index → the value apply_niche_filters() expects
_FMT_MAP = {0: None, 1: "short", 2: "long"}

# brief-mode index → the string generate_content_lab_ideas() expects
_BRIEF_MODES = {0: "videos", 1: "blend", 2: "brief"}

# How many blueprints one run asks for. Kept small: each is a full production
# blueprint (angle, two hook options of each kind, three thumbnail prompts, the
# verbatim script, a shot list, competitor gaps, packaging, CTAs and retention
# pacing), so even two already costs a multi-minute call and ~9k output tokens.
IDEAS_COUNT_CHOICES = (1, 2, 3, 4)

# The model returns difficulty as one of three fixed English tokens (so it can
# be compared and coloured); the label the user reads is translated here rather
# than in QML, which has no access to the token list.
#
# A function, not a module-level dict: i18n.LANG is set from config AFTER this
# module is imported, so a dict built at import time would freeze every label
# in English on a Persian install.
def _thumb_id(url):
    """Encode a thumbnail URL as the id half of `image://thumbs/<id>`.

    Done in Python rather than QML's deprecated Qt.btoa() so the cards can bind
    the id straight through — same helper as niche_vm.
    """
    if not url:
        return ""
    return base64.b64encode(url.encode("utf-8")).decode("ascii")


def _video_key(v):
    """Stable identity for a reference row across filter/sort/page changes."""
    return v.get("video_id") or v.get("_archive_key") or v.get("video_url") or ""


class IdeasVM(QObject):
    """AI Ideas: pick reference videos and/or describe your own idea, then have
    the AI build full production blueprints from that."""

    changed = Signal()              # form state: mode, brief, filters, sort
    sectionsChanged = Signal()      # the keyword-section list
    poolChanged = Signal()          # loaded section / filtered view / paging
    selectionChanged = Signal()     # which reference videos are ticked
    busyChanged = Signal()
    # v3.39.5: everything the Create button depends on. canGenerate/readyHint
    # used to notify on `changed` only, but ticking a video emits
    # `selectionChanged` — so QML never re-read them and "Create with AI"
    # stayed greyed out with 4 videos picked until some unrelated form change.
    readyChanged = Signal()
    resultsChanged = Signal()       # generated blueprints
    # Just WHICH blueprint is open. Selecting used to emit resultsChanged,
    # which re-evaluates every results property — the whole rail list (each
    # blueprint a big dict, converted to QVariant again), so the rail's
    # Repeater rebuilt every card — and that was the 1–3 s stop between ideas.
    activeChanged = Signal()
    labelsChanged = Signal()        # UI language changed
    toast = Signal(str, str)        # (message, kind)

    # worker → GUI bridge (auto-queued across threads)
    _genDone = Signal(int, "QVariant", str)   # (run_id, ideas_or_None, error)
    _genProgress = Signal(str)
    _csvLoaded = Signal(str, "QVariant")   # (path, source_or_None)
    # (idea_id, new_idea_or_None, error) — a single-blueprint rebuild landing
    # back on the GUI thread. Separate from _genDone because it REPLACES one
    # record in place rather than prepending a batch.
    _regenDone = Signal(int, "QVariant", str)

    def __init__(self, parent=None):
        super().__init__(parent)
        # anything that changes the results can change the open blueprint too
        self.resultsChanged.connect(self.activeChanged)
        # any input to the Create gate re-evaluates it
        self.changed.connect(self.readyChanged)
        self.selectionChanged.connect(self.readyChanged)
        self.busyChanged.connect(self.readyChanged)
        self._reload_ai_config()

        # ── keyword sections (shared storage with Search Archive) ──
        self._sections = []
        self._section_id = -1
        self._section_title = ""

        # ── reference pool ──
        # _pool is the section exactly as stored; _filtered is the projection
        # the grid renders. Keeping them apart means changing sort/format/search
        # never re-hits the database, and "select top N" always means the top N
        # of what is currently on screen.
        self._pool = []
        self._filtered = []
        self._visible = []
        self._raw_by_key = {}
        self._page = 0

        # ── filter/sort form ──
        self._quick = ""
        self._format = 0
        self._sort = 0

        # ── selection (survives filter/sort/page changes) ──
        self._selected = {}       # key -> raw row

        # ── the creator's own idea ──
        self._brief = ""
        self._brief_mode = 0      # 0 videos, 1 blend, 2 brief-only
        # An idea handed over from AI Chat ("Build in AI Ideas"). While the
        # brief is still that idea, the run uses the "seeded" framing: the
        # idea is fixed, the videos it came from are its evidence AND source
        # material, and the chat's digests ride along as real data.
        self._seed_brief = ""
        self._seed_context = ""
        self._seed_format = ""
        self._count = 2           # blueprints per run

        # ── CSV data inputs ──
        # One or more exports can sit beside picked videos. They are reduced to
        # real stats on the worker and passed into the same blueprint prompt.
        self._csv_sources = []
        self._csv_cache = {}       # path -> parsed source (read once, at add)
        self._csv_pending = set()  # paths still being read on a worker

        # ── generation ──
        self._busy = False
        # Stop button: the live run's token (shuts its socket) and a run id so
        # a late reply from a stopped run can never land on the page.
        self._gen_token = None
        self._gen_run = 0
        self._status = tr("Pick a keyword section, or just describe your idea below.")
        self._status_kind = "muted"
        self._ideas = []          # flattened blueprints for QML
        self._entry_id = None
        # Which blueprint the pane below the rail is showing. -1 = none yet.
        # The rail is a selector, not a list of expandable cards: a blueprint is
        # far too tall to stack several of them open, and the thing a creator
        # does with a batch is compare one against another.
        self._active_id = -1
        # Rail filter: show only starred blueprints. Deliberately separate from
        # the reference-video filters above — this one filters OUTPUT, those
        # filter INPUT, and sharing state between them would be confusing.
        self._rail_fav_only = False
        # Rail format filter: 0 all / 1 short / 2 long. The blueprint format is
        # fixed at generation time, so this just slices the existing rail.
        self._rail_format = 0
        # A single-idea regeneration in flight, so the rail can show which card
        # is being rebuilt rather than freezing the whole page.
        self._regen_id = -1

        self._genDone.connect(self._on_gen_done)
        self._csvLoaded.connect(self._on_csv_loaded)
        self._genProgress.connect(self._on_gen_progress)
        self._regenDone.connect(self._on_regen_done)

    def _reload_ai_config(self):
        # Whatever Settings routes "Idea generation" to (AI routing), falling
        # back to the active provider — see app.core.ai.profiles.
        r = resolve_ai_route("ideas")
        self._ai_route = r
        self._ai_provider = r["provider"]
        self._ai_api_key = r["api_key"]
        self._ai_model = r["model"]
        self._ai_base_url = r["base_url"]
        self._ai_path = r["path"]
        self._ai_proxy = r["proxy"]
        self._ai_custom_name = r["custom_name"]
        self._ai_api_mode = r["api_mode"]
        self._ai_effort = r["effort"]

    def _make_client(self, feature="ideas"):
        if feature != "ideas":
            return client_from_route(resolve_ai_route(feature))
        return client_from_route(self._ai_route)

    # ── static option lists for the QML controls ──────────────────────────
    # Translated, so NOT constant: the UI language can change while running and
    # a constant property would never re-read.
    @Property("QVariantList", notify=labelsChanged)
    def sortOptions(self):
        return [tr(row[0]) for row in AI_IDEAS_SORTS_UI]

    @Property("QVariantList", notify=labelsChanged)
    def formatOptions(self):
        return [tr("All"), tr("Shorts"), tr("Long-form")]

    @Property("QVariantList", notify=labelsChanged)
    def briefModeOptions(self):
        """The three ways a brief can relate to the picked videos. Each carries
        its own one-line explanation — the difference between "blend" and
        "brief" is the whole point of the control, so it can't be left to the
        user to infer from a two-word label."""
        return [
            {"label": tr("From videos"),
             "hint": tr("Reverse-engineer what the videos you picked have in common."),
             "icon": "travel_explore"},
            {"label": tr("My idea + videos"),
             "hint": tr("Your idea is the subject; the videos only lend their style."),
             "icon": "auto_awesome"},
            {"label": tr("My idea only"),
             "hint": tr("Build purely from what you describe — no videos used."),
             "icon": "edit"},
        ]

    @Property("QVariantList", constant=True)
    def countOptions(self):
        return [str(n) for n in IDEAS_COUNT_CHOICES]

    @Property("QVariantList", notify=labelsChanged)
    def railFormatOptions(self):
        """All / Short / Long tabs over the generated blueprints."""
        return [tr("All"), tr("Short"), tr("Long")]

    @Slot()
    def retranslate(self):
        """UI language changed — re-read every translated label."""
        self.labelsChanged.emit()
        self.changed.emit()
        self.sectionsChanged.emit()
        self.poolChanged.emit()
        self.resultsChanged.emit()

    # ── AI provider readiness ────────────────────────────────────────────
    @Slot()
    def reloadConfig(self):
        """Re-read the AI provider settings (they may have changed on the
        Settings page since this page was last opened)."""
        self._reload_ai_config()
        self.changed.emit()

    @Property(bool, notify=changed)
    def hasAiKey(self):
        # A custom provider is configured by host, not necessarily by key.
        if self._ai_provider == "custom":
            return bool(self._ai_base_url.strip())
        return bool(self._ai_api_key.strip())

    @Property(str, notify=changed)
    def providerLabel(self):
        if self._ai_provider == "custom":
            return self._ai_custom_name or tr("Custom provider")
        return self._ai_route.get("profile_name") or self._ai_provider.title()

    @Property(bool, notify=changed)
    def isGeminiProvider(self):
        """Whether the active provider speaks Google's shape — the only one here
        that can also search the web and watch videos."""
        return api_mode_for(self._ai_provider, self._ai_api_mode or None) == "google_genai"

    @Property(str, notify=changed)
    def providerCapabilityNote(self):
        """One line naming what this provider can and cannot do for the AI
        features, so a non-Gemini choice doesn't look broken when the extras
        quietly don't happen."""
        if self.isGeminiProvider:
            return tr("Gemini can also search the web and watch videos, so its reports and ideas draw on more than the numbers.")
        return tr("Ideas and reports work with {provider}; web research and video watching are Gemini-only.").format(
            provider=self.providerLabel)

    # ── keyword sections ─────────────────────────────────────────────────
    @Property("QVariantList", notify=sectionsChanged)
    def sections(self):
        return self._sections

    @Property(bool, notify=sectionsChanged)
    def hasSections(self):
        return bool(self._sections)

    @Property(int, notify=poolChanged)
    def sectionId(self):
        return self._section_id

    @Property(str, notify=poolChanged)
    def sectionTitle(self):
        return self._section_title

    @Slot()
    def refreshSections(self):
        """Reload the keyword-section list. Every finished Niche Finder search
        auto-archives, so sections appear here with no separate save step."""
        self._sections = [
            {"id": g["id"],
             "title": g.get("title") or tr("Untitled"),
             "count": str(g.get("item_count", 0)),
             "updated": days_ago_str(g.get("updated_at") or "")}
            for g in archive_list_groups()
        ]
        self.sectionsChanged.emit()
        # A section that was open may have been deleted from Search Archive
        # while this page was in the background.
        if self._section_id != -1 and not any(
                s["id"] == self._section_id for s in self._sections):
            self.clearSection()

    @Slot(int)
    def openSection(self, gid):
        """Load one keyword section's saved videos as the reference pool."""
        gid = int(gid)
        self._section_id = gid
        self._section_title = next(
            (s["title"] for s in self._sections if s["id"] == gid), "")
        self._pool = archive_get_rows(gid)
        # Switching sections starts the filter bar fresh: a quick search or
        # format toggle left over from the previous keyword would otherwise
        # silently hide videos in a section the user just opened.
        self._quick = ""
        self._format = 0
        self._page = 0
        self.changed.emit()
        self._apply()
        if self._pool:
            self._set_status(tr("{n} videos in “{kw}”. Tick the ones to use.").format(
                n=len(self._pool), kw=self._section_title))
        else:
            self._set_status(tr("This section is empty."), "warn")

    @Slot()
    def clearSection(self):
        """Close the open section. Any ticked videos stay ticked — a selection
        can legitimately span sections, and the raw rows are already held in
        _selected rather than being looked up from the pool at send time."""
        self._section_id = -1
        self._section_title = ""
        self._pool = []
        self._page = 0
        self._apply()
        self._set_status(tr("Pick a keyword section, or just describe your idea below."))

    # ── filter / sort form ───────────────────────────────────────────────
    @Property(str, notify=changed)
    def quickFilter(self):
        return self._quick

    @quickFilter.setter
    def quickFilter(self, v):
        if v != self._quick:
            self._quick = v
            self.changed.emit()

    @Property(int, notify=changed)
    def formatIndex(self):
        return self._format

    @formatIndex.setter
    def formatIndex(self, i):
        i = max(0, min(2, int(i)))
        if i != self._format:
            self._format = i
            self.changed.emit()

    @Property(int, notify=changed)
    def sortIndex(self):
        return self._sort

    @sortIndex.setter
    def sortIndex(self, i):
        i = max(0, min(len(AI_IDEAS_SORTS_UI) - 1, int(i)))
        if i != self._sort:
            self._sort = i
            self.changed.emit()

    @Slot()
    def applyFilters(self):
        """Re-slice the loaded section in memory. Pure CPU — no network, no
        quota — so the page can call this on every keystroke."""
        self._page = 0
        self._apply()

    def _apply(self):
        pool = list(self._pool)
        if pool:
            rows = apply_niche_filters(pool, {
                "text": self._quick,
                "format": _FMT_MAP.get(self._format),
            })
            sort_key = (AI_IDEAS_SORTS_UI[self._sort][1]
                        if 0 <= self._sort < len(AI_IDEAS_SORTS_UI) else "multiplier")
            self._filtered = sort_niche_rows(rows, sort_key)
        else:
            self._filtered = []
        self._render_page()

    def _render_page(self):
        """Flatten just the current page into the dicts the QML cards bind to.

        Page-scoped like niche_vm's: only a card that exists can be ticked, so
        the raw-row map never needs to hold the whole pool.
        """
        pages = self.pageCount
        self._page = max(0, min(self._page, pages - 1))
        start = self._page * IDEAS_PAGE_SIZE
        page_rows = self._filtered[start:start + IDEAS_PAGE_SIZE]
        self._visible = [self._row_for_qml(r) for r in page_rows]
        self._raw_by_key = {}
        for r in page_rows:
            key = _video_key(r)
            if key:
                self._raw_by_key[key] = r
        self.poolChanged.emit()

    def _row_for_qml(self, r):
        """Flatten a pool row into the plain-string dict the QML cards read."""
        subs = r.get("subscriber_count")
        mult = r.get("multiplier")
        key = _video_key(r)
        return {
            "key": key,
            "videoId": r.get("video_id", ""),
            "title": r.get("title", "") or tr("Untitled"),
            "channelTitle": r.get("channel_title", "—"),
            "videoUrl": r.get("video_url", ""),
            "thumbId": _thumb_id(r.get("thumbnail_url", "")),
            "subsText": (tr("hidden") if r.get("subs_hidden")
                         else (humanize_count(subs) if subs is not None else "—")),
            "views": humanize_count(r.get("view_count", 0) or 0),
            "multiplier": format_multiplier(mult) if mult is not None else "—",
            "duration": fmt_duration(r.get("duration_s", 0)),
            "age": days_ago_str(r.get("published_at") or ""),
            "isShort": bool(r.get("is_short")),
            "selected": key in self._selected,
        }

    # ── pool / paging read-only props ────────────────────────────────────
    @Property("QVariantList", notify=poolChanged)
    def rows(self):
        return self._visible

    @Property(bool, notify=poolChanged)
    def hasRows(self):
        return bool(self._visible)

    @Property(bool, notify=poolChanged)
    def hasPool(self):
        return bool(self._pool)

    @Property(int, notify=poolChanged)
    def matchCount(self):
        return len(self._filtered)

    @Property(str, notify=poolChanged)
    def countLabel(self):
        if not self._pool:
            return ""
        return tr("{shown} / {total}").format(
            shown=len(self._filtered), total=len(self._pool))

    @Property(int, notify=poolChanged)
    def pageIndex(self):
        return self._page

    @Property(int, notify=poolChanged)
    def pageCount(self):
        return max(1, (len(self._filtered) + IDEAS_PAGE_SIZE - 1) // IDEAS_PAGE_SIZE)

    @Slot(int)
    def gotoPage(self, i):
        i = max(0, min(int(i), self.pageCount - 1))
        if i != self._page:
            self._page = i
            self._render_page()

    # ── selection ────────────────────────────────────────────────────────
    @Property(int, notify=selectionChanged)
    def selectedCount(self):
        return len(self._selected)

    @Property("QVariantList", notify=selectionChanged)
    def selectedKeys(self):
        return list(self._selected.keys())

    @Property("QVariantList", notify=selectionChanged)
    def selectedThumbs(self):
        """Thumbnail ids of the picked references (max 8), for the generating
        animation — the videos visibly orbit the logo while it works."""
        out = []
        for r in self._selected.values():
            t = _thumb_id((r or {}).get("thumbnail_url", ""))
            if t:
                out.append(t)
            if len(out) >= 8:
                break
        return out

    @Slot(str)
    def toggle(self, key):
        """Tick / untick one reference video.

        Only poolChanged carries the per-card `selected` flag, so this re-renders
        the page rather than the whole pool — and the raw row is stashed in
        _selected, not looked up again at send time, so a selection survives
        filtering, sorting, paging and even switching sections.
        """
        key = str(key)
        if not key:
            return
        if key in self._selected:
            del self._selected[key]
        else:
            row = self._raw_by_key.get(key)
            if row is None:
                return
            self._selected[key] = row
        self.selectionChanged.emit()
        self._render_page()

    @Slot(int)
    def selectTop(self, n):
        """Swap the selection for the top N of whatever is on screen right now
        (current sort + format + quick filter), ready to send straight to AI."""
        rows = self._filtered[:max(1, int(n))]
        if not rows:
            return
        self._selected = {}
        for r in rows:
            key = _video_key(r)
            if key:
                self._selected[key] = r
        self.selectionChanged.emit()
        self._render_page()

    def addReferences(self, rows, source=""):
        """v3.42: take videos handed over from another page (the ✦ "Send to
        AI Ideas" tile on a Niche Finder / Search Archive card) and TICK them
        as references here.

        Before this, those tiles wrote into the legacy `ideas` table, which
        nothing in the QML app reads any more — so the click showed a toast at
        most and the video never appeared on the AI Ideas page. Ticking it in
        _selected is exactly what picking it from a section does, so it shows
        up in the "N picked" meter, feeds the next generation, and survives
        section switches like any other pick.

        Returns (added, already) counts. Plain Python (not a Slot): the raw
        rows come from another ViewModel and must not round-trip through QML.
        """
        added = already = 0
        for r in rows or []:
            if not isinstance(r, dict):
                continue
            key = _video_key(r)
            if not key:
                continue
            if key in self._selected:
                already += 1
                continue
            self._selected[key] = dict(r)
            added += 1
        if added:
            # a hand-picked reference only means something when videos are used
            if self._brief_mode == 2:
                self._brief_mode = 0
                self.changed.emit()
            self.selectionChanged.emit()
            self._render_page()
            self._set_status(
                tr("{n} reference video(s) picked — sent from {src}.").format(
                    n=len(self._selected), src=source or tr("another page")),
                "success")
        return added, already

    @Slot()
    def clearSelection(self):
        if not self._selected:
            return
        self._selected = {}
        self.selectionChanged.emit()
        self._render_page()

    @Slot(str)
    def openVideo(self, url):
        if url:
            open_external_url(url)

    # ── the creator's own idea (brief) ───────────────────────────────────
    @Property(str, notify=changed)
    def brief(self):
        return self._brief

    @brief.setter
    def brief(self, v):
        if v != self._brief:
            self._brief = v
            # Rewriting the hand-over idea into something else ends the seed;
            # small edits (a word, a typo) keep it.
            if self._seed_brief and not self._same_seed(v):
                self._clear_seed()
            self.changed.emit()

    def _same_seed(self, v):
        a = (self._seed_brief or "").splitlines()[0:1]
        b = (v or "").strip().splitlines()[0:1]
        if not a or not b:
            return False
        a, b = a[0].strip(), b[0].strip()
        if a == b:
            return True
        # same first line give or take a short edit
        short, longer = sorted((a, b), key=len)
        return len(short) >= 0.6 * len(longer) and (longer.startswith(short[:12]) or short[:12] == longer[:12])

    def _clear_seed(self):
        self._seed_brief = ""
        self._seed_context = ""
        self._seed_format = ""

    @Property(bool, notify=changed)
    def fromChat(self):
        """True while the brief is an idea handed over from AI Chat."""
        return bool(self._seed_brief)

    @Slot("QVariant")
    def importFromChat(self, payload):
        """Take one idea from AI Chat and set the page up to build it WELL:
        the idea as the brief, the videos it was derived from ticked as the
        references, the exports it rests on added, and the mode switched to
        "My idea + videos" (or "My idea only" when the chat had no data).
        Previously only the title travelled, in brief-only mode — so the
        blueprint was written blind and came out unrelated to the data."""
        p = dict(payload or {})
        brief = str(p.get("brief") or "").strip()
        if not brief:
            return
        rows = [dict(r) for r in (p.get("rows") or []) if isinstance(r, dict)]
        sel = {}
        for r in rows:
            key = _video_key(r)
            if key:
                sel[key] = r
        self._selected = sel
        csvs = []
        for path in p.get("csvPaths") or []:
            try:
                src = csv_blueprint_source(path)
            except Exception:
                src = None
            if src:
                csvs.append({"path": path, "name": src["name"], "rows": src.get("rows", 0),
                             "stats": src.get("stats", {})})
        self._csv_sources = csvs
        self._brief = brief
        self._brief_mode = 1 if (sel or csvs) else 2
        self._seed_brief = brief
        self._seed_context = str(p.get("seedContext") or "")
        self._seed_format = p.get("format") if p.get("format") in ("short", "long") else ""
        self.selectionChanged.emit()
        self._render_page()
        self._set_status(
            tr("Idea from AI Chat — {n} source video(s) picked. Hit Generate.").format(n=len(sel))
            if sel else tr("Idea from AI Chat — ready to generate."), "success")
        self.changed.emit()

    @Property(int, notify=changed)
    def briefMode(self):
        return self._brief_mode

    @briefMode.setter
    def briefMode(self, i):
        i = max(0, min(2, int(i)))
        if i != self._brief_mode:
            self._brief_mode = i
            self.changed.emit()

    @Property(int, notify=changed)
    def countIndex(self):
        return IDEAS_COUNT_CHOICES.index(self._count) if self._count in IDEAS_COUNT_CHOICES else 1

    @countIndex.setter
    def countIndex(self, i):
        i = max(0, min(len(IDEAS_COUNT_CHOICES) - 1, int(i)))
        n = IDEAS_COUNT_CHOICES[i]
        if n != self._count:
            self._count = n
            self.changed.emit()

    @Property(bool, notify=changed)
    def briefRequired(self):
        """True in the two modes that consume the brief, so the page can mark
        the field as the thing that is missing rather than just refusing."""
        return self._brief_mode in (1, 2)

    @Property(bool, notify=changed)
    def videosRequired(self):
        return self._brief_mode in (0, 1)

    @Property(bool, notify=readyChanged)
    def canGenerate(self):
        """Whether Generate is currently a legal action. Mirrors exactly what
        generate() enforces, so the button is never enabled into an error."""
        if self._busy or not self.hasAiKey:
            return False
        if self.videosRequired and not self._selected and not self._csv_sources:
            return False
        if self.briefRequired and not self._brief.strip():
            return False
        return True

    @Property(str, notify=readyChanged)
    def readyHint(self):
        """One line naming the single next thing to do. The button being greyed
        out is not self-explanatory when three inputs feed it, so the page shows
        this beside it."""
        if not self.hasAiKey:
            return tr("Add an AI provider key in Settings first.")
        if self.videosRequired and not self._selected and not self._csv_sources:
            return (tr("Pick a reference video or add a CSV export.") if self._brief_mode == 0
                    else tr("Pick videos or add a CSV export for the style."))
        if self.briefRequired and not self._brief.strip():
            return tr("Describe your idea in the box above.")
        if self._seed_brief and self._brief_mode in (1, 2):
            return tr("Ready — building the chat idea from {n} source video(s).").format(
                n=len(self._selected)) if self._selected and self._brief_mode == 1 \
                else tr("Ready — building the chat idea.")
        if self._brief_mode == 2:
            return tr("Ready — building from your idea alone.")
        return tr("Ready — {n} video(s) + {c} export(s) selected.").format(
            n=len(self._selected), c=len(self._csv_sources))

    # ── CSV inputs ───────────────────────────────────────────────────────
    @Property("QVariantList", notify=changed)
    def csvSources(self):
        return self._csv_sources

    @Property(int, notify=changed)
    def csvCount(self):
        return len(self._csv_sources)

    @Slot(str)
    def addCsv(self, file_url):
        path = local_path_from_url(file_url)
        path = path if path else ""
        if not path or not __import__("os").path.isfile(path):
            self.toast.emit(tr("That export couldn't be opened."), "error")
            return
        if __import__("os").path.splitext(path)[1].lower() not in (".csv", ".xlsx", ".jsonl", ".db"):
            self.toast.emit(tr("Pick a CSV, XLSX, JSONL or DB export."), "warn")
            return
        if any(x.get("path") == path for x in self._csv_sources):
            return
        if path in self._csv_pending:
            return
        # Read the export on a worker: a big XLSX/CSV used to freeze the page
        # right after the file picker closed. The parsed source is kept so
        # Generate does not read the same file a second time.
        self._csv_pending.add(path)

        def work(_path=path):
            try:
                src = csv_blueprint_source(_path)
            except Exception:      # noqa: BLE001 — reported as unreadable
                log_crash("IdeasVM.addCsv failed:\n" + traceback.format_exc())
                src = None
            self._csvLoaded.emit(_path, src)

        threading.Thread(target=work, daemon=True, name="ideas-csv").start()

    @Slot(str, "QVariant")
    def _on_csv_loaded(self, path, src):
        self._csv_pending.discard(path)
        if not src:
            self.toast.emit(tr("This export has no readable video rows."), "error")
            return
        if any(x.get("path") == path for x in self._csv_sources):
            return
        self._csv_cache[path] = src
        self._csv_sources = self._csv_sources + [{
            "path": path, "name": src.get("name", ""), "rows": src.get("rows", 0),
            "stats": src.get("stats", {}),
        }]
        self.changed.emit()

    @Slot(str)
    def removeCsv(self, path):
        self._csv_sources = [x for x in self._csv_sources if x.get("path") != path]
        self._csv_cache.pop(path, None)
        self.changed.emit()

    @Slot()
    def clearCsv(self):
        if self._csv_sources:
            self._csv_sources = []
            self._csv_cache = {}
            self.changed.emit()

    # ── generation ───────────────────────────────────────────────────────
    @Property(bool, notify=busyChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=changed)
    def status(self):
        return self._status

    @Property(str, notify=changed)
    def statusKind(self):
        return self._status_kind

    def _set_status(self, text, kind="muted"):
        self._status = text
        self._status_kind = kind
        self.changed.emit()

    def _set_busy(self, busy):
        if busy != self._busy:
            self._busy = busy
            self.busyChanged.emit()
            # canGenerate/readyHint key off busy too.
            self.changed.emit()

    @Slot()
    def generate(self):
        """Build `count` blueprints from the current inputs, on a worker thread.

        The three brief modes are passed straight through to the prompt builder
        rather than being emulated here — "blend" has to keep the creator's topic
        as the subject, and that is a property of the instruction the model gets,
        not something that can be fixed up afterwards.
        """
        if self._busy:
            return
        if not self.hasAiKey:
            self._set_status(tr("Add an AI provider key in Settings first."), "error")
            self.toast.emit(tr("No AI provider configured."), "error")
            return

        brief = self._brief.strip()
        mode = _BRIEF_MODES.get(self._brief_mode, "videos")
        videos = [] if mode == "brief" else list(self._selected.values())
        csv_sources = list(self._csv_sources)

        if mode in ("videos", "blend") and not videos and not csv_sources:
            self._set_status(tr("Tick at least one reference video first."), "error")
            return
        if mode in ("blend", "brief") and not brief:
            self._set_status(tr("Describe your idea first."), "error")
            return

        # Which batch/tab the blueprints belong to. With no reference videos
        # there is nothing to classify, so a brief-only run is treated as
        # short-form — the same default content_lab_classify_format() falls back
        # to, and the more common case for a creator sketching an idea.
        fmt = content_lab_classify_format(videos) if videos else csv_classify_format(csv_sources)
        seeded = bool(self._seed_brief) and mode in ("blend", "brief") and self._same_seed(brief)
        seed_context = self._seed_context if seeded else ""
        if seeded:
            mode = "seeded"
            # The chat card already decided Short vs long-form; the references'
            # majority must not overrule the idea itself.
            if self._seed_format:
                fmt = self._seed_format
            elif not videos and not csv_sources:
                fmt = "short"
        n = self._count
        # Don't let the model re-propose a title this workspace already holds.
        avoid = [i.get("title", "") for i in self._ideas if i.get("title")]

        self._gen_run += 1
        run_id = self._gen_run
        token = CancelToken()
        self._gen_token = token
        self._set_busy(True)
        self._set_status(tr("Asking {p} for {n} blueprint(s)…").format(
            p=self.providerLabel, n=n))

        def worker(_videos=videos, _brief=brief, _mode=mode, _fmt=fmt, _n=n,
                   _avoid=avoid, _section=self._section_id, _title=self._section_title,
                   _csv_sources=csv_sources, _seed=seed_context, _rid=run_id, _tok=token,
                   _csv_cache=dict(self._csv_cache)):
            try:
                client = self._make_client()
                _tok.check()
                srcs = []
                for x in _csv_sources:
                    _tok.check()
                    srcs.append(_csv_cache.get(x["path"])
                                or csv_blueprint_source(x["path"]))
                with cancel_scope(_tok):
                    ideas = generate_content_lab_ideas(
                        _videos, client, n=_n, avoid_titles=_avoid, format=_fmt,
                        brief=_brief, brief_mode=_mode, seed_context=_seed,
                        csv_sources=srcs)
                # Stopped after the last byte arrived: still honour Stop, and
                # don't save blueprints the user said they didn't want.
                _tok.check()
                # Persist into the same tables the Content Lab page reads, so a
                # run here is never orphaned. A brief-only run has no keyword
                # section to hang off, so it goes to a synthetic group_id of -1
                # ("My ideas") rather than being dropped.
                gid = _section if _section != -1 else -1
                entry_title = _title or tr("My ideas")
                entry_id = content_lab_get_or_create_entry(gid, entry_title)
                if entry_id is not None:
                    if _videos:
                        content_lab_merge_entry_videos(entry_id, _videos)
                    saved = content_lab_add_ideas(entry_id, ideas)
                    if saved:
                        ideas = saved
                self._genDone.emit(_rid, {"ideas": ideas, "entryId": entry_id or -1}, "")
            except RequestCancelled:
                self._genDone.emit(_rid, None, _CANCELLED)
            except Exception as exc:      # noqa: BLE001 — surfaced to the user
                if _tok.cancelled:
                    # The shut socket surfaced as some other error: still a Stop.
                    self._genDone.emit(_rid, None, _CANCELLED)
                    return
                log_crash("IdeasVM.generate failed:\n" + traceback.format_exc())
                self._genDone.emit(_rid, None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot()
    def cancelGenerate(self):
        """Stop the running generation now.

        The page is released at once (no waiting for the worker): the token
        shuts the live socket so the provider stops generating, and the run id
        bump means anything the old worker still emits is ignored. Nothing from
        a stopped run is saved."""
        if not self._busy or self._gen_token is None:
            return
        token, self._gen_token = self._gen_token, None
        self._gen_run += 1
        token.cancel()
        self._set_busy(False)
        self._set_status(tr("Generation stopped."), "muted")
        self.toast.emit(tr("Generation stopped."), "info")

    @Slot(str)
    def _on_gen_progress(self, text):
        if self._busy:
            self._set_status(text)

    @Slot(int, "QVariant", str)
    def _on_gen_done(self, run_id, data, error):
        if run_id != self._gen_run:
            return      # a stopped run finishing late
        self._gen_token = None
        if error == _CANCELLED:
            self._set_busy(False)
            self._set_status(tr("Generation stopped."), "muted")
            return
        self._set_busy(False)
        if error or not data:
            self._set_status("✗ " + (error or tr("Something went wrong.")), "error")
            self.toast.emit(error or tr("Idea generation failed."), "error")
            announce("error", tr("Idea generation failed."), error or "",
                     page=6, icon="auto_awesome", source=tr("AI Ideas"))
            return
        ideas = data.get("ideas") or []
        self._entry_id = data.get("entryId") if data.get("entryId", -1) != -1 else None
        # Newest first: the run that just finished is what the user is waiting to
        # read, so it goes to the top of the rail…
        fresh = [self._idea_for_qml(i) for i in ideas]
        self._ideas = fresh + self._ideas
        # …and opens itself in the pane. Making the user click to see what they
        # just waited minutes for would be perverse.
        if fresh:
            self._active_id = fresh[0].get("id", -1)
        else:
            self._ensure_active_visible()
        self.resultsChanged.emit()
        self._set_status(tr("✓ {n} blueprint(s) ready.").format(n=len(ideas)), "success")
        self.toast.emit(tr("{n} new blueprint(s) generated.").format(n=len(ideas)),
                        "success")
        announce("success", tr("Blueprints ready"),
                 tr("{n} new blueprint(s) generated.").format(n=len(ideas)),
                 page=6, icon="auto_awesome", source=tr("AI Ideas"))

    def _idea_for_qml(self, d):
        """Flatten one blueprint into the shape the QML blueprint pane binds to.

        Delegates to the shared flattener so the AI Ideas page and the Content
        Lab page (ContentLabVM) render identical blueprints — see
        app.qml_backend.vm._idea_shape.
        """
        return _shared_idea_for_qml(d)

    # ── results: the rail + the one open blueprint ───────────────────────
    #
    # The page shows a NARROW RAIL of every blueprint in the workspace and ONE
    # full blueprint beside it. The previous shape — every blueprint as its own
    # expandable card, stacked — could not survive schema v2: one card now
    # carries a script, a shot list and a competitor table, so two open at once
    # is several screens of scrolling and comparing two is impossible. A rail
    # plus a detail pane makes switching cost one click and keeps the compare
    # loop (read this one, glance at that one) intact.
    @Property("QVariantList", notify=resultsChanged)
    def ideas(self):
        """Every blueprint in the workspace, newest first — the rail's model,
        already filtered by the favourites toggle and the format tab."""
        out = self._ideas
        if self._rail_fav_only:
            out = [i for i in out if i.get("isFavorite")]
        if self._rail_format == 1:
            out = [i for i in out if not i.get("isLong")]
        elif self._rail_format == 2:
            out = [i for i in out if i.get("isLong")]
        return out

    @Property(int, notify=resultsChanged)
    def shortCount(self):
        return sum(1 for i in self._ideas if not i.get("isLong"))

    @Property(int, notify=resultsChanged)
    def longCount(self):
        return sum(1 for i in self._ideas if i.get("isLong"))

    @Property(int, notify=resultsChanged)
    def railFormat(self):
        return self._rail_format

    @railFormat.setter
    def railFormat(self, i):
        i = max(0, min(2, int(i)))
        if i == self._rail_format:
            return
        self._rail_format = i
        # Never leave the pane showing a blueprint the tab no longer lists.
        self._ensure_active_visible()
        self.resultsChanged.emit()

    @Property(bool, notify=resultsChanged)
    def hasIdeas(self):
        return bool(self._ideas)

    @Property(int, notify=resultsChanged)
    def ideaCount(self):
        return len(self._ideas)

    @Property(int, notify=resultsChanged)
    def favoriteCount(self):
        return sum(1 for i in self._ideas if i.get("isFavorite"))

    @Property(bool, notify=resultsChanged)
    def railFavOnly(self):
        return self._rail_fav_only

    @railFavOnly.setter
    def railFavOnly(self, v):
        v = bool(v)
        if v == self._rail_fav_only:
            return
        self._rail_fav_only = v
        # Filtering the rail must never leave the pane showing a blueprint the
        # rail no longer lists — that reads as a bug ("why is this still here?").
        self._ensure_active_visible()
        self.resultsChanged.emit()

    @Property(bool, notify=resultsChanged)
    def railIsEmpty(self):
        """True when the favourites filter matched nothing — distinct from
        having no blueprints at all, and it needs a different message."""
        return bool(self._ideas) and not self.ideas

    @Property(int, notify=activeChanged)
    def activeId(self):
        return self._active_id

    @Property("QVariantMap", notify=activeChanged)
    def active(self):
        """The blueprint the detail pane renders. An empty map when nothing is
        selected, so QML bindings read `Ideas.active.title` safely either way."""
        for i in self._ideas:
            if i.get("id") == self._active_id:
                return i
        return {}

    @Property(bool, notify=activeChanged)
    def hasActive(self):
        return bool(self.active)

    @Slot(int)
    def selectIdea(self, idea_id):
        """Open one blueprint in the detail pane."""
        idea_id = int(idea_id)
        if idea_id == self._active_id:
            return
        self._active_id = idea_id
        self.activeChanged.emit()

    def _ensure_active_visible(self):
        """Point `_active_id` at something the rail actually lists.

        Called after anything that can change the rail's contents (a new batch,
        a delete, the favourites toggle, a reload). Keeps the current selection
        when it survives; otherwise falls to the first visible blueprint, or to
        nothing when the rail is empty.
        """
        visible = self.ideas
        if not visible:
            self._active_id = -1
            return
        if any(i.get("id") == self._active_id for i in visible):
            return
        self._active_id = visible[0].get("id", -1)

    @Slot(int)
    def toggleFavorite(self, idea_id):
        """Star / unstar a blueprint. Persisted, so it survives a restart and
        shows up starred in the Content Lab library too."""
        idea_id = int(idea_id)
        if idea_id <= 0:
            return
        content_lab_toggle_favorite(idea_id)
        for i in self._ideas:
            if i.get("id") == idea_id:
                i["isFavorite"] = not i.get("isFavorite")
                break
        # Un-starring the open blueprint while the rail is filtered to
        # favourites would otherwise leave it visible in the pane but gone from
        # the rail.
        self._ensure_active_visible()
        self.resultsChanged.emit()

    @Slot(int)
    def deleteIdea(self, idea_id):
        """Delete one blueprint for good — from the database, not just the view.

        The separate "Clear view" below is the non-destructive option; this is
        the one that needs a confirmation in the UI, and the page asks for it.
        """
        idea_id = int(idea_id)
        if idea_id <= 0:
            return
        if not content_lab_delete_idea(idea_id):
            self.toast.emit(tr("Couldn't delete that blueprint."), "error")
            return
        self._ideas = [i for i in self._ideas if i.get("id") != idea_id]
        self._ensure_active_visible()
        self.resultsChanged.emit()
        self.toast.emit(tr("Blueprint deleted."), "success")

    @Slot()
    def clearIdeas(self):
        """Clear the on-screen list only. The blueprints stay in the database —
        this is "tidy my workspace", not "delete my work". Use deleteIdea for
        the destructive version."""
        if not self._ideas:
            return
        self._ideas = []
        self._active_id = -1
        self.resultsChanged.emit()
        self._set_status(tr("Cleared the view. Your blueprints are still saved."))

    @Slot()
    def loadSaved(self):
        """Pull back the blueprints already stored for the open section, so
        returning to the page shows previous runs instead of an empty panel."""
        gid = self._section_id if self._section_id != -1 else -1
        title = self._section_title or tr("My ideas")
        entry_id = content_lab_get_or_create_entry(gid, title)
        if entry_id is None:
            return
        self._entry_id = entry_id
        stored = content_lab_get_ideas(entry_id)
        # Newest first, matching what a fresh run does.
        self._ideas = [self._idea_for_qml(i) for i in reversed(stored)]
        self._ensure_active_visible()
        self.resultsChanged.emit()
        if self._ideas:
            self._set_status(tr("{n} saved blueprint(s) for “{kw}”.").format(
                n=len(self._ideas), kw=title))
        else:
            self._set_status(tr("No saved blueprints for “{kw}” yet.").format(kw=title))

    # ── regenerate one blueprint ─────────────────────────────────────────
    @Property(int, notify=busyChanged)
    def regenId(self):
        """Which blueprint is being rebuilt right now, or -1. The rail dims that
        one row instead of the page going busy — the rest stays readable."""
        return self._regen_id

    @Slot(int)
    def regenerate(self, idea_id):
        """Rebuild ONE blueprint in place, at the current schema version.

        This is what a pre-v2 record's "regenerate in full" button calls: the
        stored idea keeps its id, its favourite flag and its position in the
        rail, and comes back with the script / shot list / competitor sections
        it never had. It reuses the ENTRY's whole reference-video pool (kept by
        content_lab_merge_entry_videos) rather than whatever happens to be
        ticked right now — the blueprint belongs to the section it was made in,
        not to the current selection.
        """
        idea_id = int(idea_id)
        if idea_id <= 0 or self._busy or self._regen_id != -1:
            return
        if not self.hasAiKey:
            self._set_status(tr("Add an AI provider key in Settings first."), "error")
            self.toast.emit(tr("No AI provider configured."), "error")
            return
        current = next((i for i in self._ideas if i.get("id") == idea_id), None)
        if current is None:
            return

        entry_id = self._entry_id
        if entry_id is None:
            gid = self._section_id if self._section_id != -1 else -1
            entry_id = content_lab_get_or_create_entry(
                gid, self._section_title or tr("My ideas"))
        if entry_id is None:
            self.toast.emit(tr("Couldn't find where this blueprint is stored."), "error")
            return

        videos = content_lab_get_entry_videos(entry_id)
        fmt = current.get("format") or "short"
        # Keep the idea recognisably the same idea: its own title is the brief,
        # so a rebuild deepens it instead of replacing it with something else.
        brief = current.get("title") or ""
        mode = "blend" if (videos and brief) else ("videos" if videos else "brief")
        # Every OTHER title in the workspace is off-limits, so a rebuild can't
        # collapse onto a sibling blueprint.
        avoid = [i.get("title", "") for i in self._ideas
                 if i.get("id") != idea_id and i.get("title")]

        self._regen_id = idea_id
        self.busyChanged.emit()
        self._set_status(tr("Rebuilding “{t}” with the full blueprint…").format(
            t=brief or tr("Untitled idea")))

        def worker(_id=idea_id, _videos=videos, _brief=brief, _mode=mode,
                   _fmt=fmt, _avoid=avoid):
            try:
                client = self._make_client()
                ideas = generate_content_lab_ideas(
                    _videos, client, n=1, avoid_titles=_avoid, format=_fmt,
                    brief=_brief, brief_mode=_mode)
                if not ideas:
                    raise RuntimeError(tr("The model returned nothing usable."))
                fresh = ideas[0]
                # Overwrite the stored record rather than appending a new one:
                # the point of a rebuild is that this blueprint improves, not
                # that the library grows a near-duplicate.
                content_lab_update_idea(_id, fresh)
                self._regenDone.emit(_id, fresh, "")
            except Exception as exc:      # noqa: BLE001 — surfaced to the user
                log_crash("IdeasVM.regenerate failed:\n" + traceback.format_exc())
                self._regenDone.emit(_id, None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot(int, "QVariant", str)
    def _on_regen_done(self, idea_id, fresh, error):
        self._regen_id = -1
        self.busyChanged.emit()
        if error or not fresh:
            self._set_status("✗ " + (error or tr("Something went wrong.")), "error")
            self.toast.emit(error or tr("Rebuild failed."), "error")
            return
        # Splice the rebuilt blueprint back into the same slot, carrying over
        # the id and the favourite flag the stored row still holds.
        for idx, i in enumerate(self._ideas):
            if i.get("id") == idea_id:
                merged = dict(fresh)
                merged["id"] = idea_id
                merged["is_favorite"] = i.get("isFavorite", False)
                self._ideas[idx] = self._idea_for_qml(merged)
                break
        self._active_id = idea_id
        self.resultsChanged.emit()
        self._set_status(tr("✓ Blueprint rebuilt with the full production plan."),
                         "success")
        self.toast.emit(tr("Blueprint rebuilt."), "success")
        announce("success", tr("Blueprint rebuilt."),
                 tr("✓ Blueprint rebuilt with the full production plan."),
                 page=6, icon="auto_awesome", source=tr("AI Ideas"))

    @Slot(str)
    def copyText(self, text):
        """Copy any one field (a title, a hook line, a thumbnail prompt, the
        whole script) to the clipboard. QGuiApplication, not QApplication —
        there is no QtWidgets app in the QML build."""
        if not text:
            return
        cb = QGuiApplication.clipboard()
        if cb is not None:
            cb.setText(text)
            self.toast.emit(tr("Copied to clipboard."), "success")







