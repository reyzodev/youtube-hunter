"""app.qml_backend.vm.studio_vm - YouTube Hunter (QML).

ViewModel behind Content Lab's Teleprompter tab and the Teleprompter overlay —
the piece that turns a stored blueprint's `full_script` from something you read on
screen into something you can actually shoot from.

The gap it closes: AI Ideas / Content Lab already generate a camera-ready,
timecoded script (schema v2+, see app.core.ai.content_lab). Until now the only
thing you could do with it was copy it into another app. This VM feeds a real
teleprompter — WPM-paced auto-scroll, mirror mode for a beam-splitter rig,
per-beat jumping, and in-place editing that writes back to the same blueprint.

No AI call and no new table: it reads the same content_lab_* rows every other
blueprint surface reads, flattens them through the shared _idea_shape helper so
a script here is byte-for-byte the one the BlueprintPane shows, and commits edits
with content_lab_update_idea.

Rig preferences (WPM, font size, mirror, cues, line height) persist through
app_config, because a creator sets those once for their physical setup and
should never have to set them again.
"""

import re

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication

from app.config import load_app_config, save_app_config
from app.core.db.content_lab import (content_lab_all_ideas,
                                     content_lab_ideas_by_ids,
                                     content_lab_list_entries,
                                     content_lab_update_idea)
from app.i18n import tr
from app.qml_backend.vm._idea_shape import idea_for_qml

# Reading-pace bounds. 150 wpm is the usual "clear on-camera delivery" figure and
# the default; the floor and ceiling exist so a slider drag can't produce a
# crawl that never finishes or one that outruns any human.
WPM_MIN = 60
WPM_MAX = 260
WPM_DEFAULT = 150

FONT_MIN = 20
FONT_MAX = 84
FONT_DEFAULT = 40

LINE_HEIGHT_MIN = 1.1
LINE_HEIGHT_MAX = 2.4
LINE_HEIGHT_DEFAULT = 1.55

# How deep undo goes on script edits. Matches the reference implementation's
# 20-step stack; deep enough to walk back a bad rewrite, shallow enough that the
# whole history stays cheap to hold in memory.
UNDO_DEPTH = 20

def _word_count(text):
    """Spoken words in one beat.

    Parenthesised runs are stage directions — "(music swells)", "(cut to
    b-roll)" — not words anyone says, so they are excluded before counting.
    Getting this wrong makes every runtime estimate long, and a prompter whose
    estimate you can't trust is a prompter you stop reading."""
    body = re.sub(r"\([^)]*\)", " ", str(text or ""))
    return len([w for w in re.split(r"\s+", body.strip()) if w])

def _clamp(value, low, high):
    return max(low, min(high, value))

def _mmss(seconds):
    total = max(0, int(round(seconds)))
    minutes, secs = divmod(total, 60)
    if minutes >= 60:
        hours, minutes = divmod(minutes, 60)
        return "%d:%02d:%02d" % (hours, minutes, secs)
    return "%d:%02d" % (minutes, secs)

class StudioVM(QObject):
    """Script Studio: pick a saved blueprint, read it off a teleprompter, edit
    the words in place."""

    libraryChanged = Signal()       # section chips + the blueprint pick list
    scriptChanged = Signal()        # the loaded script + its derived readouts
    prefsChanged = Signal()         # wpm / font / mirror / cues / line height
    dirtyChanged = Signal()         # unsaved edits, and undo/redo availability
    labelsChanged = Signal()        # UI language changed
    toast = Signal(str, str)        # (message, kind)
    # The overlay hosts (AI Ideas, Content Lab) listen for this: openBlueprint()
    # succeeded and the prompter should come up.
    opened = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)

        # ── library ──
        self._sections = []
        self._section_id = -1        # -1 == every section
        self._choices = []
        self._search = ""

        # ── the loaded blueprint ──
        self._idea = None            # flattened dict, or None
        self._idea_id = -1
        self._raw = None             # the stored (nested) record, for write-back
        self._beats = []             # [{time, speaker, line}] — the live copy

        # ── edit history ──
        # Each entry is a full snapshot of _beats. Beats are a handful of short
        # strings, so snapshotting is cheaper and far less bug-prone than
        # tracking per-field deltas.
        self._undo = []
        self._redo = []
        self._dirty = False

        cfg = load_app_config()
        self._wpm = _clamp(int(cfg.get("studio_wpm", WPM_DEFAULT) or WPM_DEFAULT),
                           WPM_MIN, WPM_MAX)
        self._font_size = _clamp(int(cfg.get("studio_font_size", FONT_DEFAULT)
                                     or FONT_DEFAULT), FONT_MIN, FONT_MAX)
        try:
            self._line_height = _clamp(float(cfg.get("studio_line_height",
                                                     LINE_HEIGHT_DEFAULT)),
                                       LINE_HEIGHT_MIN, LINE_HEIGHT_MAX)
        except (TypeError, ValueError):
            self._line_height = LINE_HEIGHT_DEFAULT
        self._mirror = bool(cfg.get("studio_mirror", False))
        self._show_cues = bool(cfg.get("studio_show_cues", True))

        self.refreshLibrary()

    # ── i18n ─────────────────────────────────────────────────────────────
    @Slot()
    def retranslate(self):
        self.labelsChanged.emit()
        self.libraryChanged.emit()
        self.scriptChanged.emit()

    def _save_prefs(self):
        cfg = load_app_config()
        cfg["studio_wpm"] = self._wpm
        cfg["studio_font_size"] = self._font_size
        cfg["studio_line_height"] = self._line_height
        cfg["studio_mirror"] = self._mirror
        cfg["studio_show_cues"] = self._show_cues
        save_app_config(cfg)

    # ── library: sections, then blueprints within them ───────────────────
    @Property("QVariantList", notify=libraryChanged)
    def sections(self):
        """The keyword/channel groups blueprints were generated in, as chips.
        Same two-step shape as the Content Lab combine picker: narrow by section
        first, because a creator with 60 saved blueprints can't scan one flat
        list."""
        return self._sections

    @Property(int, notify=libraryChanged)
    def sectionId(self):
        return self._section_id

    @Property("QVariantList", notify=libraryChanged)
    def choices(self):
        """The pick list — every blueprint that HAS a script, in the current
        section, matching the current search.

        Scriptless blueprints are filtered out rather than shown disabled: a
        pre-v2 record has nothing to read, and offering it only to refuse is
        worse than not offering it."""
        return self._choices

    @Property(bool, notify=libraryChanged)
    def hasChoices(self):
        return bool(self._choices)

    @Property(str, notify=libraryChanged)
    def search(self):
        return self._search

    @search.setter
    def search(self, value):
        value = str(value or "")
        if value != self._search:
            self._search = value
            self._rebuild_choices()

    @Slot()
    def refreshLibrary(self):
        entries = content_lab_list_entries()
        self._all_choices = []
        for record in content_lab_all_ideas():
            script = record.get("full_script")
            if not isinstance(script, list) or not script:
                continue
            words = sum(_word_count(beat.get("line")) for beat in script
                        if isinstance(beat, dict))
            self._all_choices.append({
                "id": int(record.get("id", 0) or 0),
                "sectionId": int(record.get("_section_id", 0) or 0),
                "sectionTitle": record.get("_section_title") or tr("Untitled"),
                "title": record.get("title") or tr("Untitled idea"),
                "format": record.get("format", "short"),
                "formatLabel": (tr("Long-form") if record.get("format") == "long"
                                else tr("Shorts")),
                "beats": len(script),
                "words": words,
                "isFavorite": bool(record.get("is_favorite")),
            })
        # Only sections that actually contain a readable script get a chip.
        with_scripts = {c["sectionId"] for c in self._all_choices}
        self._sections = [{
            "id": entry["id"],
            "title": entry.get("title") or tr("Untitled"),
            "count": sum(1 for c in self._all_choices
                         if c["sectionId"] == entry["id"]),
        } for entry in entries if entry["id"] in with_scripts]
        if self._section_id not in with_scripts:
            self._section_id = -1
        self._rebuild_choices()

    def _rebuild_choices(self):
        needle = self._search.strip().lower()
        self._choices = [
            c for c in self._all_choices
            if (self._section_id < 0 or c["sectionId"] == self._section_id)
            and (not needle or needle in c["title"].lower())
        ]
        self.libraryChanged.emit()

    @Slot(int)
    def pickSection(self, section_id):
        """Scope the pick list to one section, or pass -1 for all of them."""
        section_id = int(section_id)
        self._section_id = -1 if section_id == self._section_id else section_id
        self._rebuild_choices()

    # ── loading one blueprint ────────────────────────────────────────────
    @Slot(int)
    def openBlueprint(self, idea_id):
        """Load a stored blueprint's script into the prompter.

        Called both from the Studio page's pick list and from the "Read on
        camera" button inside BlueprintPane, which is why it emits `opened` —
        the overlay hosts have no other way to know the load succeeded."""
        idea_id = int(idea_id)
        records = content_lab_ideas_by_ids([idea_id])
        if not records:
            self.toast.emit(tr("That greenlight is no longer saved."), "error")
            return
        raw = records[0]
        script = raw.get("full_script")
        if not isinstance(script, list) or not script:
            self.toast.emit(
                tr("This greenlight has no script yet — rebuild it in full first."),
                "error")
            return

        self._raw = raw
        self._idea_id = idea_id
        self._idea = idea_for_qml(raw)
        self._beats = [{
            "time": str(beat.get("time", "") or ""),
            "speaker": str(beat.get("speaker", "") or ""),
            "line": str(beat.get("line", "") or ""),
            # v5: kept so saving an edited script doesn't drop what's on screen
            "visual": str(beat.get("visual", "") or ""),
        } for beat in script if isinstance(beat, dict)]
        self._undo = []
        self._redo = []
        self._dirty = False
        self.scriptChanged.emit()
        self.dirtyChanged.emit()
        self.opened.emit()

    @Slot()
    def close(self):
        """Drop the loaded script. Unsaved edits are discarded — the page asks
        for confirmation before calling this, the same way SettingsPage guards
        its unsaved fields."""
        self._raw = None
        self._idea = None
        self._idea_id = -1
        self._beats = []
        self._undo = []
        self._redo = []
        self._dirty = False
        self.scriptChanged.emit()
        self.dirtyChanged.emit()

    @Property(bool, notify=scriptChanged)
    def hasScript(self):
        return bool(self._beats)

    @Property(int, notify=scriptChanged)
    def ideaId(self):
        return self._idea_id

    @Property("QVariantMap", notify=scriptChanged)
    def idea(self):
        """The whole flattened blueprint, so the prompter's side rail can show
        the hook, the titles and the CTA without a second query."""
        return self._idea or {}

    @Property("QVariantList", notify=scriptChanged)
    def beats(self):
        """The script as the prompter renders it: one entry per beat, with its
        own word count and running cumulative word position.

        `startWord` is what makes per-beat seeking honest — the prompter maps
        scroll position to elapsed reading time through word counts, so jumping
        to beat 4 has to know how many words precede it, not how many pixels."""
        out = []
        running = 0
        for index, beat in enumerate(self._beats):
            words = _word_count(beat["line"])
            out.append({
                "index": index,
                "time": beat["time"],
                "speaker": beat["speaker"],
                "line": beat["line"],
                "words": words,
                "startWord": running,
                # A beat with no spoken words is a direction (music, b-roll):
                # the prompter dims it and never counts it toward pacing.
                "isDirection": words == 0,
            })
            running += words
        return out

    @Property(int, notify=scriptChanged)
    def beatCount(self):
        return len(self._beats)

    @Property(int, notify=scriptChanged)
    def wordCount(self):
        """Spoken words only — the number the pacing math runs on."""
        return sum(_word_count(beat["line"]) for beat in self._beats)

    @Property(str, notify=scriptChanged)
    def scriptCopyText(self):
        return "\n".join(
            "[%s] %s: %s" % (b["time"], b["speaker"], b["line"])
            for b in self._beats)

    # ── pacing readouts ──────────────────────────────────────────────────
    @Property(float, notify=prefsChanged)
    def estimatedSeconds(self):
        """How long this script takes to read at the current WPM."""
        words = sum(_word_count(beat["line"]) for beat in self._beats)
        if words <= 0 or self._wpm <= 0:
            return 0.0
        return (words / float(self._wpm)) * 60.0

    @Property(str, notify=prefsChanged)
    def estimatedText(self):
        return _mmss(self.estimatedSeconds)

    @Property(str, notify=scriptChanged)
    def targetText(self):
        """The blueprint's own intended runtime, for comparison. Reading four
        minutes of script for a planned 60-second Short is the kind of mismatch
        that only shows up on set, and it shows up here instead."""
        return ((self._idea or {}).get("retention") or {}).get("totalLabel", "")

    @Property(str, notify=prefsChanged)
    def paceVerdict(self):
        """Over / under / on target against the blueprint's planned length.

        Compared against the same `retention.total_seconds` the model committed
        to when it designed the beats, not an arbitrary ideal."""
        target = 0
        try:
            target = int((self._raw or {}).get("retention", {})
                         .get("total_seconds", 0) or 0)
        except (TypeError, ValueError, AttributeError):
            target = 0
        estimate = self.estimatedSeconds
        if not target or not estimate:
            return ""
        ratio = estimate / float(target)
        if ratio > 1.15:
            return tr("{s} over the planned length").format(
                s=_mmss(estimate - target))
        if ratio < 0.85:
            return tr("{s} under the planned length").format(
                s=_mmss(target - estimate))
        return tr("On target")

    # ── rig preferences ──────────────────────────────────────────────────
    @Property(int, notify=prefsChanged)
    def wpm(self):
        return self._wpm

    @wpm.setter
    def wpm(self, value):
        value = _clamp(int(value), WPM_MIN, WPM_MAX)
        if value != self._wpm:
            self._wpm = value
            self._save_prefs()
            self.prefsChanged.emit()

    @Property(int, notify=prefsChanged)
    def fontSize(self):
        return self._font_size

    @fontSize.setter
    def fontSize(self, value):
        value = _clamp(int(value), FONT_MIN, FONT_MAX)
        if value != self._font_size:
            self._font_size = value
            self._save_prefs()
            self.prefsChanged.emit()

    @Property(float, notify=prefsChanged)
    def lineHeight(self):
        return self._line_height

    @lineHeight.setter
    def lineHeight(self, value):
        try:
            value = _clamp(float(value), LINE_HEIGHT_MIN, LINE_HEIGHT_MAX)
        except (TypeError, ValueError):
            return
        if abs(value - self._line_height) > 0.001:
            self._line_height = value
            self._save_prefs()
            self.prefsChanged.emit()

    @Property(bool, notify=prefsChanged)
    def mirror(self):
        """Horizontal flip, for reading off a beam-splitter glass where the text
        is bounced back at the lens."""
        return self._mirror

    @mirror.setter
    def mirror(self, value):
        value = bool(value)
        if value != self._mirror:
            self._mirror = value
            self._save_prefs()
            self.prefsChanged.emit()

    @Property(bool, notify=prefsChanged)
    def showCues(self):
        """Whether `[0:00–0:03]` timecodes and `VO:` speaker badges are drawn.
        Useful while rehearsing, noise while rolling."""
        return self._show_cues

    @showCues.setter
    def showCues(self, value):
        value = bool(value)
        if value != self._show_cues:
            self._show_cues = value
            self._save_prefs()
            self.prefsChanged.emit()

    @Property("QVariantList", notify=labelsChanged)
    def wpmPresets(self):
        """Three named paces, so the slider isn't the only way in."""
        return [
            {"label": tr("Calm"), "wpm": 120},
            {"label": tr("Natural"), "wpm": 150},
            {"label": tr("Fast"), "wpm": 185},
        ]

    # ── editing ──────────────────────────────────────────────────────────
    @Property(bool, notify=dirtyChanged)
    def dirty(self):
        return self._dirty

    @Property(bool, notify=dirtyChanged)
    def canUndo(self):
        return bool(self._undo)

    @Property(bool, notify=dirtyChanged)
    def canRedo(self):
        return bool(self._redo)

    def _push_undo(self):
        self._undo.append([dict(b) for b in self._beats])
        if len(self._undo) > UNDO_DEPTH:
            self._undo.pop(0)
        self._redo = []

    @Slot(int, str)
    def editBeat(self, index, text):
        """Rewrite one beat's spoken line. Only the words change — a beat's
        timecode and speaker stay as generated, because renumbering those from
        an edit would desync the shot list that references them."""
        index = int(index)
        if not (0 <= index < len(self._beats)):
            return
        text = str(text or "")
        if text == self._beats[index]["line"]:
            return
        self._push_undo()
        self._beats[index]["line"] = text
        self._dirty = True
        self.scriptChanged.emit()
        self.prefsChanged.emit()   # word count moved, so the estimate did too
        self.dirtyChanged.emit()

    @Slot()
    def undo(self):
        if not self._undo:
            return
        self._redo.append([dict(b) for b in self._beats])
        self._beats = self._undo.pop()
        self._dirty = True
        self.scriptChanged.emit()
        self.prefsChanged.emit()
        self.dirtyChanged.emit()

    @Slot()
    def redo(self):
        if not self._redo:
            return
        self._undo.append([dict(b) for b in self._beats])
        self._beats = self._redo.pop()
        self._dirty = True
        self.scriptChanged.emit()
        self.prefsChanged.emit()
        self.dirtyChanged.emit()

    @Slot()
    def revert(self):
        """Throw away every edit and reload from the database."""
        if self._idea_id > 0:
            self.openBlueprint(self._idea_id)

    @Slot()
    def save(self):
        """Write the edited beats back into the stored blueprint.

        Only `full_script` is replaced — the rest of the record (hook, shot list,
        SEO, retention, schema_version) is passed through untouched, so saving a
        script edit can never silently downgrade a blueprint."""
        if not self._dirty or not self._raw or self._idea_id <= 0:
            return
        record = dict(self._raw)
        record["full_script"] = [dict(b) for b in self._beats]
        # `id` / `is_favorite` / `created_at` are columns, not part of the stored
        # JSON blob — content_lab_update_idea writes whatever dict it is given,
        # so leaving them in would bake stale copies into the record.
        for column in ("id", "is_favorite", "created_at",
                       "_section_id", "_section_title"):
            record.pop(column, None)
        if not content_lab_update_idea(self._idea_id, record):
            self.toast.emit(tr("Couldn't save the script."), "error")
            return
        self._raw["full_script"] = [dict(b) for b in self._beats]
        self._idea = idea_for_qml(dict(self._raw, id=self._idea_id))
        self._dirty = False
        self.scriptChanged.emit()
        self.dirtyChanged.emit()
        self.refreshLibrary()
        self.toast.emit(tr("Script saved to the greenlight."), "success")

    @Slot(str)
    def copyText(self, text):
        if not text:
            return
        clipboard = QGuiApplication.clipboard()
        if clipboard is not None:
            clipboard.setText(text)
            self.toast.emit(tr("Copied to clipboard."), "success")
