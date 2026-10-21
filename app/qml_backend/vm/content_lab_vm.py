"""app.qml_backend.vm.content_lab_vm - YouTube Hunter (QML).

ViewModel behind ContentLabPage.qml — the migrated Content Lab page.

Two tabs on one VM:
  * Library  — every blueprint ever generated from AI Ideas, grouped into the
    keyword/channel "sections" it was made in (content_lab_entries). Open a
    section to get the same rail-of-cards + one-open-blueprint layout the AI
    Ideas results use — it reuses the exact same BlueprintPane.qml and
    IdeaRailCard.qml, fed by the shared _idea_shape flattener, so a saved
    blueprint looks identical to a fresh one.
  * CSV Analysis — hand the AI a scraped channel export (csv/xlsx/jsonl/db) and
    get back a rich, self-contained HTML report (the same
    generate_deep_analysis_html the legacy History "Deep Analysis" used). All
    numbers are computed in Python from the real rows; only the narrative is the
    model's. Cached per-file so reopening never spends a second AI call.

Everything heavy is the shared, UI-free core: content_lab_* for the persisted
blueprints, generate_deep_analysis_html for the report, AIClient for the
provider call. Long-running work runs on a daemon thread and reports back over a
queued Qt signal, the same worker→GUI pattern as the other VMs.
"""

import os
import threading
import traceback
from datetime import datetime

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.core.ai.profiles import client_from as client_from_route, resolve as resolve_ai_route
from app.core.ai.clients import AIClient, api_mode_for
from app.core.ai.content_lab import generate_content_lab_ideas
from app.core.analysis.deep_report import (forget_deep_report,
                                           generate_combined_report_html,
                                           generate_deep_analysis_html,
                                           get_deep_analysis,
                                           list_deep_reports)
from app.core.db.content_lab import (
    content_lab_all_ideas, content_lab_delete_entry, content_lab_delete_idea,
    content_lab_get_entry, content_lab_get_entry_videos, content_lab_get_ideas,
    content_lab_ideas_by_ids,
    content_lab_list_entries, content_lab_toggle_favorite,
    content_lab_update_idea)
from app.core.db.insights import insights_get, insights_list
from app.core.net import explain_network_error
from app.core.utils import (days_ago_str, local_path_from_url,
                            notif_relative_time, open_external_url,
                            reveal_in_file_manager)
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm._idea_shape import idea_for_qml
from app.qml_backend.desktop_notifier import announce

# Export formats the CSV-analysis tab accepts — the same set _read_export_rows
# in csv_report.py knows how to parse back into rows.
_CSV_EXTS = (".csv", ".xlsx", ".jsonl", ".db")


def _brief_relative(stamp):
    """"3d ago" for an insight_reports.created_at value.

    Same reasoning as InsightsVM._relative: those timestamps are local
    isoformat(timespec="seconds") strings, which days_ago_str (built for
    YouTube's "…Z" format) reads as "N/A".
    """
    try:
        return notif_relative_time(datetime.fromisoformat(str(stamp)))
    except Exception:
        return str(stamp)[:10]



class ContentLabVM(QObject):
    """Content Lab: browse saved blueprint sections, and turn a scraped channel
    export into a full AI HTML report."""

    entriesChanged = Signal()       # the library section list
    resultsChanged = Signal()       # the open section's rail + active blueprint
    # v3.16-p3: picking a card only moves the selection. It used to fire
    # resultsChanged, which re-read `ideas` and rebuilt EVERY rail card plus
    # the whole pane on each click (the 2-3 s freeze). Anything that fires
    # resultsChanged still fires this too (wired in __init__).
    activeChanged = Signal()
    tabChanged = Signal()           # library (0) / csv analysis (1)
    busyChanged = Signal()          # a blueprint rebuild in flight
    csvChanged = Signal()           # csv-tab state: picked file, busy, result
    reportsChanged = Signal()       # the produced-report history list
    changed = Signal()              # ai-provider readiness
    labelsChanged = Signal()        # UI language changed
    toast = Signal(str, str)        # (message, kind)

    # worker → GUI bridges (auto-queued across threads)
    _regenDone = Signal(int, "QVariant", str)   # (idea_id, new_idea_or_None, error)
    _csvDone = Signal(str, str)                  # (html_path_or_"", error)
    _csvProgress = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.resultsChanged.connect(self.activeChanged)
        self._reload_ai_config()

        # ── tab ──
        self._tab = 0

        # ── library: section list ──
        self._entries = []
        self._entry_search = ""

        # ── the open section ──
        self._open_entry_id = None
        self._open_title = ""
        self._ideas = []
        self._active_id = -1
        self._rail_fav_only = False
        # Rail format filter: 0 all / 1 short / 2 long.
        self._rail_format = 0
        self._regen_id = -1

        # ── csv analysis tab ──
        self._csv_path = ""
        self._csv_name = ""
        self._csv_busy = False
        self._csv_status = ""
        self._csv_status_kind = "muted"
        self._csv_html_path = ""      # last report produced/opened this session
        # Saved blueprints the user can fold INTO the channel report (phase B).
        # _bp_choices is the pick list; _bp_selected is an ordered set of ids.
        # _bp_sections groups those choices by the keyword/channel they were
        # generated in, so the picker can be "pick a keyword, then its
        # blueprints" rather than one flat list; _bp_section_id is the section
        # currently scoping the list (-1 = show every section's blueprints).
        self._bp_choices = []
        self._bp_all_choices = []
        self._bp_sections = []
        self._bp_section_id = -1
        self._bp_selected = []
        # Saved Niche Scan briefs the user can fold in alongside (or
        # instead of) blueprints. A blueprint says what the creator intends to
        # make; a brief says what the wider niche's search demand looks like —
        # different evidence, so a separate picker rather than one merged list.
        # Keyed by snapshot_key (a TEXT id), which is why this is a list of
        # strings where _bp_selected is a list of ints.
        self._brief_choices = []
        self._brief_selected = []

        self._regenDone.connect(self._on_regen_done)
        self._csvDone.connect(self._on_csv_done)
        self._csvProgress.connect(self._on_csv_progress)

    # ── AI provider config (shared shape with IdeasVM) ────────────────────
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

    @Slot()
    def reloadConfig(self):
        self._reload_ai_config()
        self.changed.emit()

    @Property(bool, notify=changed)
    def hasAiKey(self):
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

    @Property(bool, notify=changed)
    def willWatchVideos(self):
        """Whether this run will actually watch the CSV's videos.

        Watching is unconditional for a Google-shape provider now (it used to be a
        count in Settings that defaulted to off, which quietly made most reports
        the weaker, numbers-only kind). Nothing else can watch, so this is just the
        provider test — exposed so the CSV tab can warn about the extra minutes
        before the user commits to a run.
        """
        return bool(self.isGeminiProvider)

    # ── tab ───────────────────────────────────────────────────────────────
    @Property(int, notify=tabChanged)
    def tab(self):
        return self._tab

    @tab.setter
    def tab(self, i):
        # Two tabs now: library (0), teleprompter (1). The old channel report is retired.
        # The prompter used to be its own top-level page; it lives here because
        # the scripts it reads are these blueprints, and a separate nav row was a
        # second door into the same room.
        i = max(0, min(1, int(i)))
        if i != self._tab:
            self._tab = i
            self.tabChanged.emit()

    # ── library: section list ─────────────────────────────────────────────
    @Property("QVariantList", notify=entriesChanged)
    def entries(self):
        return self._entries

    @Property(bool, notify=entriesChanged)
    def hasEntries(self):
        return bool(self._entries)

    @Property(str, notify=entriesChanged)
    def entrySearch(self):
        return self._entry_search

    @entrySearch.setter
    def entrySearch(self, v):
        if v != self._entry_search:
            self._entry_search = v
            self.refreshEntries()

    @Slot()
    def refreshEntries(self):
        """Reload the library list. Every "Create with AI" run in AI Ideas
        appends to a section, so sections appear here with no separate save."""
        self._entries = [
            dict({"id": e["id"],
                  "title": e.get("title") or tr("Untitled"),
                  "ideaCount": int(e.get("idea_count", 0) or 0),
                  "updated": days_ago_str(e.get("updated_at") or ""),
                  "updatedAt": str(e.get("updated_at") or "")},
                 **self._entry_stats(e["id"]))
            for e in content_lab_list_entries(self._entry_search)
        ]
        self.entriesChanged.emit()

    @staticmethod
    def _entry_stats(entry_id):
        """v12 library cards: a per-section fingerprint so a card can say more
        than "N ideas". Read-only, cheap (one indexed SELECT per section), and
        it never raises — a malformed row just leaves the defaults in place.

        `scores` is newest-first and capped, so the card's score barcode always
        shows the latest batch rather than the first run ever made there."""
        stats = {"shortCount": 0, "longCount": 0, "favCount": 0,
                 "bestScore": 0, "avgScore": 0, "scores": [],
                 "topTitle": "", "topHook": ""}
        try:
            ideas = content_lab_get_ideas(entry_id) or []
        except Exception:
            return stats
        best = None
        total = 0
        scored = 0
        scores = []
        for idea in reversed(ideas):
            try:
                score = int(idea.get("score", 0) or 0)
            except (TypeError, ValueError):
                score = 0
            if idea.get("format") == "long":
                stats["longCount"] += 1
            else:
                stats["shortCount"] += 1
            if idea.get("is_favorite"):
                stats["favCount"] += 1
            if score > 0:
                total += score
                scored += 1
            if len(scores) < 18:
                scores.append(max(0, min(100, score)))
            if best is None or score > best[0]:
                best = (score, idea)
        stats["scores"] = scores
        if scored:
            stats["avgScore"] = int(round(total / scored))
        if best is not None:
            stats["bestScore"] = best[0]
            stats["topTitle"] = str(best[1].get("title") or "")
            stats["topHook"] = str(best[1].get("hook_preview") or "")
        return stats

    # ── open one section ───────────────────────────────────────────────────
    @Property(bool, notify=resultsChanged)
    def sectionOpen(self):
        return self._open_entry_id is not None

    @Property(str, notify=resultsChanged)
    def openTitle(self):
        return self._open_title

    @Slot(int)
    def openEntry(self, entry_id):
        """Load one section's saved blueprints into the rail + pane."""
        entry_id = int(entry_id)
        entry = content_lab_get_entry(entry_id)
        self._open_entry_id = entry_id
        self._open_title = (entry.get("title") if entry else "") or tr("Untitled")
        self._rail_fav_only = False
        self._rail_format = 0
        stored = content_lab_get_ideas(entry_id)
        # Newest first, matching how AI Ideas presents a fresh batch.
        self._ideas = [idea_for_qml(i) for i in reversed(stored)]
        self._ensure_active_visible()
        self.resultsChanged.emit()

    @Slot()
    def backToList(self):
        """Return from a section to the library grid, and refresh it (an idea
        count or "last updated" may have changed while the section was open)."""
        self._open_entry_id = None
        self._open_title = ""
        self._ideas = []
        self._active_id = -1
        self.resultsChanged.emit()
        self.refreshEntries()

    # ── rail + active blueprint (shared shape with IdeasVM) ────────────────
    # Translated, so NOT constant: the UI language can change while running.
    @Property("QVariantList", notify=labelsChanged)
    def railFormatOptions(self):
        """All / Short / Long tabs over the section's blueprints."""
        return [tr("All"), tr("Short"), tr("Long")]

    @Slot()
    def retranslate(self):
        """UI language changed — re-read every translated label."""
        self.labelsChanged.emit()
        self.changed.emit()
        self.entriesChanged.emit()
        self.resultsChanged.emit()
        self.csvChanged.emit()

    @Property("QVariantList", notify=resultsChanged)
    def ideas(self):
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
        self._ensure_active_visible()
        self.resultsChanged.emit()

    @Property(bool, notify=resultsChanged)
    def railIsEmpty(self):
        """True when the favourites filter matched nothing — distinct from the
        section having no blueprints at all."""
        return bool(self._ideas) and not self.ideas

    @Property(int, notify=activeChanged)
    def activeId(self):
        return self._active_id

    @Property("QVariantMap", notify=activeChanged)
    def active(self):
        for i in self._ideas:
            if i.get("id") == self._active_id:
                return i
        return {}

    @Property(bool, notify=activeChanged)
    def hasActive(self):
        return bool(self.active)

    @Slot(int)
    def selectIdea(self, idea_id):
        idea_id = int(idea_id)
        if idea_id == self._active_id:
            return
        self._active_id = idea_id
        self.activeChanged.emit()       # selection only: the rail stays put

    def _ensure_active_visible(self):
        """Point _active_id at something the rail actually lists — same helper
        as IdeasVM. Keeps the selection when it survives; otherwise falls to the
        first visible blueprint, or to nothing when the rail is empty."""
        visible = self.ideas
        if not visible:
            self._active_id = -1
            return
        if any(i.get("id") == self._active_id for i in visible):
            return
        self._active_id = visible[0].get("id", -1)

    @Slot(int)
    def toggleFavorite(self, idea_id):
        idea_id = int(idea_id)
        if idea_id <= 0:
            return
        content_lab_toggle_favorite(idea_id)
        for i in self._ideas:
            if i.get("id") == idea_id:
                i["isFavorite"] = not i.get("isFavorite")
                break
        self._ensure_active_visible()
        self.resultsChanged.emit()

    @Slot(int)
    def deleteIdea(self, idea_id):
        """Delete one blueprint for good — from the database, not just the view.
        The page asks for confirmation before calling this."""
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

    @Slot(int)
    def deleteEntry(self, entry_id):
        """Drop a whole section and every blueprint in it. Destructive; the page
        confirms first. Closes the section if it was open, then refreshes the
        library list."""
        entry_id = int(entry_id)
        if not content_lab_delete_entry(entry_id):
            self.toast.emit(tr("Couldn't delete that section."), "error")
            return
        if self._open_entry_id == entry_id:
            self._open_entry_id = None
            self._open_title = ""
            self._ideas = []
            self._active_id = -1
            self.resultsChanged.emit()
        self.refreshEntries()
        self.toast.emit(tr("Section deleted."), "success")

    # ── regenerate one blueprint in place (same logic as IdeasVM) ─────────
    @Property(int, notify=busyChanged)
    def regenId(self):
        return self._regen_id

    @Slot(int)
    def regenerate(self, idea_id):
        """Rebuild ONE blueprint at the current schema version — what a pre-v2
        record's "Rebuild in full" button calls. Reuses the section's whole
        reference-video pool and keeps the idea's id, favourite flag and slot."""
        idea_id = int(idea_id)
        if idea_id <= 0 or self._regen_id != -1 or self._open_entry_id is None:
            return
        if not self.hasAiKey:
            self.toast.emit(tr("No AI provider configured."), "error")
            return
        current = next((i for i in self._ideas if i.get("id") == idea_id), None)
        if current is None:
            return

        entry_id = self._open_entry_id
        videos = content_lab_get_entry_videos(entry_id)
        fmt = current.get("format") or "short"
        brief = current.get("title") or ""
        mode = "blend" if (videos and brief) else ("videos" if videos else "brief")
        avoid = [i.get("title", "") for i in self._ideas
                 if i.get("id") != idea_id and i.get("title")]

        self._regen_id = idea_id
        self.busyChanged.emit()

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
                content_lab_update_idea(_id, fresh)
                self._regenDone.emit(_id, fresh, "")
            except Exception as exc:      # noqa: BLE001 — surfaced to the user
                log_crash("ContentLabVM.regenerate failed:\n" + traceback.format_exc())
                self._regenDone.emit(_id, None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot(int, "QVariant", str)
    def _on_regen_done(self, idea_id, fresh, error):
        self._regen_id = -1
        self.busyChanged.emit()
        if error or not fresh:
            self.toast.emit(error or tr("Rebuild failed."), "error")
            return
        for idx, i in enumerate(self._ideas):
            if i.get("id") == idea_id:
                merged = dict(fresh)
                merged["id"] = idea_id
                merged["is_favorite"] = i.get("isFavorite", False)
                self._ideas[idx] = idea_for_qml(merged)
                break
        self._active_id = idea_id
        self.resultsChanged.emit()
        self.toast.emit(tr("Blueprint rebuilt."), "success")
        announce("success", tr("Blueprint rebuilt."), "", page=7,
                 icon="nav_lab", source=tr("Content Lab"))

    @Slot(str)
    def copyText(self, text):
        """Copy one field (title, hook line, prompt, whole script) — the pane's
        copy buttons route here, same as the AI Ideas page."""
        if not text:
            return
        from PySide6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        if cb is not None:
            cb.setText(text)
            self.toast.emit(tr("Copied to clipboard."), "success")

    # ══════════════════ CSV ANALYSIS TAB ══════════════════════════════════
    @Property(str, notify=csvChanged)
    def csvName(self):
        return self._csv_name

    @Property(bool, notify=csvChanged)
    def hasCsv(self):
        return bool(self._csv_path)

    @Property(bool, notify=csvChanged)
    def csvBusy(self):
        return self._csv_busy

    @Property(str, notify=csvChanged)
    def csvStatus(self):
        return self._csv_status

    @Property(str, notify=csvChanged)
    def csvStatusKind(self):
        return self._csv_status_kind

    @Property(bool, notify=csvChanged)
    def hasCsvReport(self):
        """A report exists on disk for the picked file (this session's run, or a
        cached one from a previous run) — so "Open report" can reopen it with no
        AI call."""
        return bool(self._csv_html_path)

    def _set_csv_status(self, text, kind="muted"):
        self._csv_status = text
        self._csv_status_kind = kind
        self.csvChanged.emit()

    # ── blueprint picker (fold saved ideas into the channel report) ────────
    def _refresh_blueprint_choices(self):
        """Reload every saved blueprint, tagged with its section, for the
        "combine with my blueprints" picker — and group them by section so the
        picker can be a two-step "pick a keyword, then its blueprints".

        `_bp_all_choices` holds the full flat list; `_bp_choices` is the slice
        currently shown (scoped to `_bp_section_id`, or all of them when it's
        -1). Any current selection that no longer exists on disk is dropped, but
        selections are kept ACROSS sections — analyzeCsv resolves ids through
        content_lab_ideas_by_ids, so a pick from keyword A survives switching to
        keyword B."""
        self._bp_all_choices = [
            {"id": int(i.get("id", 0) or 0),
             "title": i.get("title") or tr("Untitled idea"),
             "sectionId": int(i.get("_section_id", 0) or 0),
             "sectionTitle": i.get("_section_title") or tr("Untitled"),
             "isLong": i.get("format") == "long",
             "isFavorite": bool(i.get("is_favorite"))}
            for i in content_lab_all_ideas()
            if int(i.get("id", 0) or 0) > 0
        ]
        # One entry per section that actually has blueprints, in first-seen
        # order (content_lab_all_ideas already returns newest-section-first).
        sections = {}
        order = []
        for c in self._bp_all_choices:
            sid = c["sectionId"]
            if sid not in sections:
                sections[sid] = {"id": sid, "title": c["sectionTitle"],
                                 "count": 0, "shortCount": 0, "longCount": 0}
                order.append(sid)
            sec = sections[sid]
            sec["count"] += 1
            if c["isLong"]:
                sec["longCount"] += 1
            else:
                sec["shortCount"] += 1
        self._bp_sections = [sections[s] for s in order]
        # A section that vanished (deleted) can't stay selected.
        if self._bp_section_id != -1 and self._bp_section_id not in sections:
            self._bp_section_id = -1
        live = {c["id"] for c in self._bp_all_choices}
        self._bp_selected = [i for i in self._bp_selected if i in live]
        self._rebuild_bp_choices()

    def _rebuild_bp_choices(self):
        """Recompute the visible slice from _bp_all_choices + _bp_section_id."""
        if self._bp_section_id == -1:
            self._bp_choices = list(self._bp_all_choices)
        else:
            self._bp_choices = [c for c in self._bp_all_choices
                                if c["sectionId"] == self._bp_section_id]
        self.csvChanged.emit()

    @Property("QVariantList", notify=csvChanged)
    def blueprintSections(self):
        return self._bp_sections

    @Property(int, notify=csvChanged)
    def blueprintSectionId(self):
        return self._bp_section_id

    @Property(str, notify=csvChanged)
    def blueprintSectionTitle(self):
        for s in self._bp_sections:
            if s["id"] == self._bp_section_id:
                return s["title"]
        return ""

    @Slot(int)
    def pickBlueprintSection(self, section_id):
        section_id = int(section_id)
        if section_id == self._bp_section_id:
            return
        self._bp_section_id = section_id
        self._rebuild_bp_choices()

    @Slot()
    def clearBlueprintSection(self):
        if self._bp_section_id == -1:
            return
        self._bp_section_id = -1
        self._rebuild_bp_choices()

    @Property("QVariantList", notify=csvChanged)
    def blueprintChoices(self):
        return self._bp_choices

    @Property(bool, notify=csvChanged)
    def hasBlueprintChoices(self):
        return bool(self._bp_all_choices)

    @Property("QVariantList", notify=csvChanged)
    def selectedBlueprintIds(self):
        return list(self._bp_selected)

    @Property(int, notify=csvChanged)
    def selectedBlueprintCount(self):
        return len(self._bp_selected)

    @Slot(int)
    def toggleBlueprint(self, idea_id):
        idea_id = int(idea_id)
        if idea_id in self._bp_selected:
            self._bp_selected = [i for i in self._bp_selected if i != idea_id]
        elif any(c["id"] == idea_id for c in self._bp_all_choices):
            self._bp_selected = self._bp_selected + [idea_id]
        else:
            return
        self.csvChanged.emit()

    @Slot()
    def selectAllInSection(self):
        """Tick every blueprint in the currently-scoped list, on top of whatever
        is already selected in other sections."""
        current = set(self._bp_selected)
        for c in self._bp_choices:
            if c["id"] not in current:
                self._bp_selected = self._bp_selected + [c["id"]]
                current.add(c["id"])
        self.csvChanged.emit()

    @Slot()
    def clearBlueprintSelection(self):
        if not self._bp_selected:
            return
        self._bp_selected = []
        self.csvChanged.emit()

    # ── brief picker (fold Niche Scan research into the report) ─────
    def _refresh_brief_choices(self):
        """Reload the saved Insights snapshots for the picker.

        insights_list() is the same query the Insights page's "previously
        analysed" strip uses, so a snapshot read a minute ago is offered here
        without a restart. Only the metadata is read — the full record (and its
        rows) is fetched per selection at analyze time, because loading a dozen
        of them to draw a checkbox list would read every stored result set off
        disk for nothing.

        Every stored snapshot is offered, not only the ones with an AI brief.
        The measured aggregates are saved the moment a result set is read and are
        the half the report quotes as fact about the niche; `kind` distinguishes
        the two so the row can say which it is.
        """
        try:
            records = insights_list(24)
        except Exception:
            records = []
        self._brief_choices = [{
            "key": r["snapshot_key"],
            "query": r.get("query") or tr("Untitled"),
            "videos": str(r.get("total_videos") or 0),
            "when": _brief_relative(r.get("created_at") or ""),
            # RESEARCH = numbers + a written brief; DATA = numbers only.
            "kind": (tr("RESEARCH") if r.get("has_brief") else tr("DATA")),
            "hasBrief": bool(r.get("has_brief")),
        } for r in records]
        live = {c["key"] for c in self._brief_choices}
        self._brief_selected = [k for k in self._brief_selected if k in live]
        self.csvChanged.emit()

    @Property("QVariantList", notify=csvChanged)
    def briefChoices(self):
        return self._brief_choices

    @Property(bool, notify=csvChanged)
    def hasBriefChoices(self):
        return bool(self._brief_choices)

    @Property("QVariantList", notify=csvChanged)
    def selectedBriefKeys(self):
        return list(self._brief_selected)

    @Property(int, notify=csvChanged)
    def selectedBriefCount(self):
        return len(self._brief_selected)

    @Slot(str)
    def toggleBrief(self, snapshot_key):
        snapshot_key = str(snapshot_key)
        if snapshot_key in self._brief_selected:
            self._brief_selected = [k for k in self._brief_selected
                                    if k != snapshot_key]
        elif any(c["key"] == snapshot_key for c in self._brief_choices):
            self._brief_selected = self._brief_selected + [snapshot_key]
        else:
            return
        self.csvChanged.emit()

    @Slot()
    def clearBriefSelection(self):
        if not self._brief_selected:
            return
        self._brief_selected = []
        self.csvChanged.emit()

    @Slot()
    def refreshCombineChoices(self):
        """Reload both "combine with" pick lists.

        pickCsv() fills them, but a creator commonly picks the export FIRST and
        only then goes off to generate the blueprint or the brief they want to
        fold in. Coming back, both lists would still be the ones from before that
        trip. Called on page show, so returning to the tab is enough to see new
        material — no reason to make anyone re-pick the same file.
        """
        self._refresh_blueprint_choices()
        self._refresh_brief_choices()

    @Slot(str)
    def pickCsv(self, file_url):
        """Accept a local path chosen in the QML FileDialog (a file:// URL) or a
        plain path. Resolves whether a cached report already exists for it."""
        path = local_path_from_url(file_url)
        path = os.path.normpath(path) if path else ""
        if not path or not os.path.isfile(path):
            self._set_csv_status(tr("That file couldn't be opened."), "error")
            return
        ext = os.path.splitext(path)[1].lower()
        if ext not in _CSV_EXTS:
            self._set_csv_status(
                tr("Pick a channel export (.csv, .xlsx, .jsonl or .db)."), "warn")
            return
        self._csv_path = path
        self._csv_name = os.path.basename(path)
        cached = get_deep_analysis(path)
        self._csv_html_path = cached.get("html_path") if cached else ""
        self._refresh_blueprint_choices()
        self._refresh_brief_choices()
        if self._csv_html_path:
            self._set_csv_status(
                tr("A report already exists for this file — open it, or analyze again."),
                "success")
        else:
            self._set_csv_status(tr("Ready to analyze “{f}”.").format(f=self._csv_name))
        # `reports` carries an isForPicked flag per entry — a new pick changes it.
        self.reportsChanged.emit()

    @Slot()
    def analyzeCsv(self):
        """Build a fresh HTML report from the picked export, on a worker thread.

        Reuses generate_deep_analysis_html (channel-only), or — when the user has
        ticked saved blueprints and/or saved Niche Scan briefs —
        generate_combined_report_html, which folds each blueprint in as a
        channel-tuned, sharpened section and each brief in as labelled
        demand-side evidence about the niche. Either way the report reads the
        export, (Gemini only) gathers a web-research briefing, asks the AI to
        design its own niche-matched sections, and renders a self-contained,
        print-ready HTML file whose numbers are all computed in Python.
        """
        if self._csv_busy:
            return
        if not self._csv_path:
            self._set_csv_status(tr("Pick a channel export first."), "warn")
            return
        if not self.hasAiKey:
            self._set_csv_status(tr("Add an AI provider key in Settings first."), "error")
            self.toast.emit(tr("No AI provider configured."), "error")
            return

        # Resolve the selected blueprints and briefs to full stored dicts NOW, on
        # the GUI thread, so the worker never touches VM state.
        blueprints = content_lab_ideas_by_ids(self._bp_selected) if self._bp_selected else []
        briefs = []
        for key in self._brief_selected:
            record = insights_get(key)
            # A brief is worth folding in when it has EITHER half: the written
            # analysis, or just the deterministic snapshot aggregates. The
            # measured half needs no AI call at all and is the most trustworthy
            # part of the whole feature (see _brief_measured_block in
            # app.core.analysis.deep_report), so a snapshot the user never asked
            # a model about still tells the report what the niche's real median,
            # momentum, length mix and channel concentration are.
            if record and (record.get("ai") or record.get("analytics")):
                briefs.append(record)

        self._csv_busy = True
        self.csvChanged.emit()
        if blueprints and briefs:
            self._set_csv_status(
                tr("Analyzing with {p}, folding in {n} blueprint(s) and {b} brief(s) — "
                   "this can take a few minutes…").format(
                       p=self.providerLabel, n=len(blueprints), b=len(briefs)))
        elif briefs:
            self._set_csv_status(
                tr("Analyzing with {p} and folding in {b} brief(s) — "
                   "this can take a few minutes…").format(
                       p=self.providerLabel, b=len(briefs)))
        elif blueprints:
            self._set_csv_status(tr("Analyzing with {p} and folding in {n} blueprint(s) — "
                                    "this can take a few minutes…").format(
                p=self.providerLabel, n=len(blueprints)))
        else:
            self._set_csv_status(tr("Analyzing with {p} — this can take a few minutes…").format(
                p=self.providerLabel))

        def worker(_name=self._csv_name, _path=self._csv_path, _bps=blueprints,
                   _briefs=briefs):
            try:
                client = self._make_client("reports")
                # Progress goes through the queued signal, so the worker never
                # touches the GUI thread directly.
                progress = self._csvProgress.emit
                # No watch count is passed: the generator decides for itself
                # whether the provider can watch and splits the videos by length.
                if _bps or _briefs:
                    html_path = generate_combined_report_html(
                        _name, _path, client, _bps, progress_cb=progress,
                        briefs=_briefs)
                else:
                    html_path = generate_deep_analysis_html(
                        _name, _path, client, progress_cb=progress)
                self._csvDone.emit(html_path or "", "")
            except Exception as exc:      # noqa: BLE001 — surfaced to the user
                log_crash("ContentLabVM.analyzeCsv failed:\n" + traceback.format_exc())
                # A five-minute AI call is the likeliest place for a proxy to cut
                # the connection; explain_network_error turns that into a
                # sentence instead of "[WinError 10054] …".
                self._csvDone.emit("", explain_network_error(exc, self.providerLabel))

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str)
    def _on_csv_progress(self, text):
        self._set_csv_status(text)

    @Slot(str, str)
    def _on_csv_done(self, html_path, error):
        self._csv_busy = False
        if error or not html_path:
            self._csv_html_path = ""
            self._set_csv_status("✗ " + (error or tr("Something went wrong.")), "error")
            self.toast.emit(error or tr("Analysis failed."), "error")
            announce("error", tr("Analysis failed."), error or "", page=7,
                     icon="description", source=tr("Content Lab"))
            return
        self._csv_html_path = html_path
        self._set_csv_status(
            tr("✓ Report ready — opened in your browser."), "success")
        self.toast.emit(tr("Channel report ready."), "success")
        announce("success", tr("Channel report ready."),
                 os.path.basename(html_path), page=7, path=html_path,
                 icon="description", source=tr("Content Lab"))
        # The history log gained an entry (written by the generator) — refresh
        # the list so the new report shows up without a page reload.
        self.reportsChanged.emit()
        open_external_url("file:///" + html_path.replace("\\", "/"))

    @Slot()
    def openCsvReport(self):
        """Reopen the last/cached report in the browser — no AI call."""
        if self._csv_html_path and os.path.isfile(self._csv_html_path):
            open_external_url("file:///" + self._csv_html_path.replace("\\", "/"))
        else:
            self._csv_html_path = ""
            self.csvChanged.emit()
            self._set_csv_status(tr("That report is no longer on disk — analyze again."),
                                 "warn")

    # ── report history (what was built before, per export) ────────────────
    # The channel-report cache only remembers the LATEST report per file, so
    # without this a creator has no way to look back at earlier runs — or to see
    # what each of them folded in. This list is the log of every report still on
    # disk, newest first, tagged by kind so the variants never look alike.
    @Property("QVariantList", notify=reportsChanged)
    def reports(self):
        out = []
        for e in list_deep_reports():
            bps = [b for b in (e.get("blueprints") or []) if b]
            brs = [b for b in (e.get("briefs") or []) if b]
            kind = e.get("kind") or "channel"
            combined = kind in ("combined", "combined_brief")
            # Three labels, keyed off what was actually stored rather than off
            # `kind` alone: a pre-brief history entry has kind "combined" and no
            # briefs list, and must keep reading as "Channel + blueprints".
            if brs and bps:
                kind_label = tr("Channel + blueprints + research")
            elif brs:
                kind_label = tr("Channel + research")
            elif combined:
                kind_label = tr("Channel + blueprints")
            else:
                kind_label = tr("Channel report")
            out.append({
                "htmlPath": e.get("html_path") or "",
                "sourceName": e.get("source_name") or "",
                "sourcePath": e.get("source_path") or "",
                # The tag the row shows, so the kinds never look alike.
                "kindLabel": kind_label,
                "isCombined": combined,
                "blueprints": bps,
                "blueprintCount": len(bps),
                "blueprintSummary": " · ".join(bps[:3]) + (" …" if len(bps) > 3 else ""),
                "briefs": brs,
                "briefCount": len(brs),
                "briefSummary": " · ".join(brs[:3]) + (" …" if len(brs) > 3 else ""),
                "provider": e.get("provider") or "",
                "videoCount": int(e.get("video_count") or 0),
                "watched": int(e.get("watched") or 0),
                "createdAt": e.get("created_at") or "",
                # True when this entry came from the export currently picked, so
                # the UI can highlight "reports for this file".
                "isForPicked": bool(self._csv_path) and (
                    os.path.normcase(os.path.abspath(e.get("source_path") or ""))
                    == os.path.normcase(os.path.abspath(self._csv_path))),
            })
        return out

    @Property(bool, notify=reportsChanged)
    def hasReports(self):
        return bool(list_deep_reports())

    @Property(int, notify=reportsChanged)
    def reportCountForPicked(self):
        """How many past reports exist for the export currently picked."""
        if not self._csv_path:
            return 0
        return len(list_deep_reports(self._csv_path))

    @Slot()
    def refreshReports(self):
        self.reportsChanged.emit()

    @Slot(str)
    def openReport(self, html_path):
        """Reopen any past report from the history list."""
        path = (html_path or "").strip()
        if path and os.path.isfile(path):
            open_external_url("file:///" + path.replace("\\", "/"))
        else:
            self.toast.emit(tr("That report is no longer on disk."), "warn")
            self.reportsChanged.emit()

    @Slot(str)
    def revealReport(self, html_path):
        """Show a past report in the file manager."""
        path = (html_path or "").strip()
        if path and os.path.isfile(path):
            if not reveal_in_file_manager(path):
                self.toast.emit(tr("Couldn't open the folder."), "error")
        else:
            self.toast.emit(tr("That report is no longer on disk."), "warn")
            self.reportsChanged.emit()

    @Slot(str, bool)
    def deleteReport(self, html_path, delete_file=True):
        """Drop a past report from the history (and delete its HTML by default)."""
        if forget_deep_report(html_path, delete_file=bool(delete_file)):
            # The cached "open report" pointer may have been the deleted one.
            if self._csv_path:
                cached = get_deep_analysis(self._csv_path)
                self._csv_html_path = cached.get("html_path") if cached else ""
            self.toast.emit(tr("Report removed."), "success")
        self.reportsChanged.emit()
        self.csvChanged.emit()
