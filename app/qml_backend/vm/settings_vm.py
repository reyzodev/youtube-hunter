"""app.qml_backend.vm.settings_vm - YouTube Hunter (QML).

ViewModel behind SettingsPage.qml. Owns all persisted preferences (YouTube API
keys, AI provider config, scrape defaults) and the two background validation
flows (YouTube key + AI key), plus the Custom-provider model fetch.

Business logic is reused straight from app.core: build_youtube_service /
i18nLanguages for YT key validation, AIClient + _openai_style_list_models for
the AI side, and app.config for load/save. Worker threads report back via
app.core.signals.SignalEmitter, exactly like the legacy SettingsPageMixin. The
QWidgets app is untouched.
"""

import os
import copy
import json
import threading
import traceback
import urllib.error
import urllib.parse
import urllib.request

from googleapiclient.errors import HttpError
from PySide6.QtCore import QCoreApplication, QObject, QTimer, Property, Signal, Slot

from app.config import load_app_config, save_app_config
from app.constants import FORMAT_KEYS
from app.core.ai.clients import (
    AIClient, AI_API_MODES, AI_API_MODE_LABELS, 
    AI_PROVIDER_API_MODE, AI_PROVIDER_DEFAULTS, AI_PROVIDER_DEFAULT_MODEL,
    api_mode_for, default_path_for, list_models)
from app.core.ai import profiles as ai_profiles
from app.core.ai.effort import EFFORT_HINTS, EFFORT_LABELS, EFFORT_LEVELS
from app.core.net import _urlopen, is_dropped_connection
from app.core.quota import (
    API_QUOTA_PER_KEY, 
    key_quota_remaining, key_quota_used)
from app.core.utils import local_path_from_url
from app.core.youtube_api import build_youtube_service
from app.crash import log_crash
from app.i18n import tr


# The providers the picker offers. "custom" is a first-class entry again, and
# this time it is not a parallel code path — it is the same four fields the
# built-in providers already expose (wire shape, host, path, model), plus a
# display name so error messages say "9router" instead of "Custom AI".
#
# It was briefly removed on the theory that "pick your wire shape and point API
# HOST at your router" covered it. It did not: without a dedicated row there was
# no way to *save* a setup under its own name, the provider label in every error
# read as one of the three brands, and picking a built-in first just to get the
# fields (then blanking its host) left the config claiming to be OpenAI while
# pointing somewhere else. A row of its own makes the intent explicit and keeps
# the built-in providers' configs honest.
UI_PROVIDERS = ("openai", "anthropic", "gemini", "custom")

# Which provider to land a config saved under a since-retired provider name on,
# by the wire shape it was configured to speak. The host it points at is
# preserved either way, so this only decides which row the picker highlights and
# which defaults apply when the user later blanks a field. "custom" is NOT in
# here — it is a live provider again, so its config is loaded as-is.
_MODE_TO_PROVIDER = {
    "openai_compatible": "openai",
    "anthropic_messages": "anthropic",
    "google_genai": "gemini",
}

# Provider names that once existed and no longer do. Anything else is loaded as
# written. "deepseek"/"claude" were folded into their parent brands when the
# picker was reworked; "custom" was retired and has since come back.
_RETIRED_PROVIDERS = ("deepseek", "claude")


# Export formats + their user labels (index-aligned with FORMAT_KEYS).
_FORMAT_LABELS = ["CSV (.csv)", "JSON Lines (.jsonl)", "Excel (.xlsx)", "SQLite (.db)"]
# Autosave-frequency options; value None means "only at the end".
_AUTOSAVE_VALUES = [100, 500, 1000, None]
_AUTOSAVE_LABELS = ["Every 100 videos", "Every 500 videos", "Every 1000 videos", "Only at the end"]
# Browser cookie sources for yt-dlp (index 0 = none).
_COOKIE_VALUES = ["", "chrome", "edge", "firefox", "brave", "chromium", "opera", "vivaldi"]
_COOKIE_LABELS = ["None", "Chrome", "Edge", "Firefox", "Brave", "Chromium", "Opera", "Vivaldi"]
# Re-encode level for clips made by the Cutter (and the extension's Cut panel).
# Index-aligned; the strings are the `cut_quality` values app.core.cutter reads
# straight from config.json on every cut, so a change applies to the next cut
# with no restart. "balanced" is the default there too.
_CUT_QUALITY_VALUES = ["high", "balanced", "small"]
_CUT_QUALITY_DEFAULT = "balanced"
# NOTE: there is no "watch videos" setting any more. Video watching used to be an
# opt-in count here (0 / 10 / 15) and defaulted to OFF, which meant almost every
# CSV report was written from numbers alone — the weaker of the two kinds of
# report the app can produce. It is now unconditional for a Google-shape provider
# and split by video length in app.core.analysis.deep_report (_watch_plan), so
# there is nothing left to configure. Any `ai_watch_videos` still sitting in an
# existing config file is simply never read.


class SettingsVM(QObject):
    """All application settings + validation, for the QML Settings page."""

    changed = Signal()                       # any persisted field changed
    ytKeysChanged = Signal()
    ytValidateResult = Signal(str, bool, str)   # (key, ok, message)
    aiValidateProgress = Signal(str)
    aiValidateResult = Signal(bool, str)        # (ok, message)
    aiModelsFetched = Signal(bool, "QStringList", str)  # (ok, models, error)
    aiCatalogReady = Signal(str)    # pid — a Fetch landed; that card opens its picker
    quotaChanged = Signal()
    labelsChanged = Signal()                    # UI language changed
    toast = Signal(str, str)                    # (message, kind)
    # ── AI providers ──
    aiProfilesChanged = Signal()     # a profile was added / removed (structure)
    aiSaved = Signal()               # the AI block reached the disk
    autoSaved = Signal()             # an auto-save just wrote the page
    aiDataChanged = Signal()         # any profile field, the default, or a route
    _aiStatusSig = Signal(str, int, str, str)          # worker → (pid, state, msg, src)
    _aiModelsSig = Signal(str, bool, "QStringList", str)   # worker → (pid, ok, models, err)

    def __init__(self, app_controller=None, parent=None):
        super().__init__(parent)
        self._app = app_controller
        cfg = load_app_config()

        # ── YouTube ──
        self._api_key = cfg.get("api_key", "") or ""
        keys = [k for k in (cfg.get("youtube_api_keys") or []) if k]
        # primary key first, then any extra rows (de-duplicated, order-preserved)
        if self._api_key and self._api_key not in keys:
            keys = [self._api_key] + keys
        self._backup_keys = [k for k in keys if k != self._api_key]

        # ── scrape prefs ──
        self._export_format = cfg.get("export_format", "csv") or "csv"
        self._autosave_freq = cfg.get("autosave_freq", 500)
        self._thread_count = int(cfg.get("thread_count", 3) or 3)
        self._transcripts_enabled = bool(cfg.get("transcripts_enabled", True))
        self._save_folder = cfg.get("save_folder", "") or ""
        # Per-kind destinations (Settings → Save locations). Empty means "use
        # the default": Desktop/YouTube for videos, ask-once for thumbnails.
        self._video_folder = cfg.get("video_save_folder", "") or ""
        self._thumb_folder = cfg.get("thumb_save_folder", "") or ""
        self._filename = cfg.get("output_filename", "youtube_data") or "youtube_data"
        self._cookies_browser = cfg.get("yt_cookies_browser", "") or ""
        cq = str(cfg.get("cut_quality", _CUT_QUALITY_DEFAULT) or "").lower()
        self._cut_quality = cq if cq in _CUT_QUALITY_VALUES else _CUT_QUALITY_DEFAULT

        # ── AI providers ──
        # A LIST of saved provider profiles plus per-feature routing (which
        # provider / model / effort each feature uses) — see
        # app.core.ai.profiles. Unlike every other setting on this page, the AI
        # block saves itself (debounced) the moment it changes: the old single
        # set of connection fields lived only in memory until Save, so leaving
        # the app — or merely clicking Gemini to look at it — threw a custom
        # router's API host away. Now every profile keeps its own fields, and
        # they are on disk within half a second of typing them.
        self._ai = ai_profiles.load_state(cfg)
        self._ai_status = {}          # pid -> {"state": 0..3, "msg": str, "src": "key"|"models"}
        self._ai_open = self._ai["active"]   # the card expanded in the accordion
        self._ai_save_timer = QTimer(self)
        self._ai_save_timer.setSingleShot(True)
        self._ai_save_timer.setInterval(450)
        self._ai_save_timer.timeout.connect(self._persist_ai)
        self._aiStatusSig.connect(self._on_ai_status)
        self._aiModelsSig.connect(self._on_ai_models)
        app = QCoreApplication.instance()
        if app is not None:
            # a pending debounce must still reach the disk when the app closes
            app.aboutToQuit.connect(self._flush_ai)
        if not (isinstance(cfg.get("ai_profiles"), list) and cfg.get("ai_profiles")):
            # first run on profiles: migrate the flat config once, for good
            self._persist_ai()
        # The AI block as last saved — what Discard goes back to.
        self._ai_clean = copy.deepcopy(self._ai)

        # ── save mode ──
        # ON  (default): every change on the page — AI providers included —
        #     is written ~0.7 s after the last edit; no save bar.
        # OFF: nothing is written until Save (or Ctrl+S); the save bar, the
        #     Discard button and the leave-page guard cover every field,
        #     AI providers included. The switch itself is saved at once.
        self._autosave = bool(cfg.get("settings_autosave", True))
        self._autosave_timer = QTimer(self)
        self._autosave_timer.setSingleShot(True)
        self._autosave_timer.setInterval(700)
        self._autosave_timer.timeout.connect(self._autosave_now)

        # Per-key validation status, keyed by the key string: {key: (ok, msg)}.
        # Fed by validateYouTubeKey's result so each backup row can show its own
        # dot without re-validating.
        self._key_status = {}
        self.ytValidateResult.connect(self._remember_key_status)

        # Baseline for the unsaved-changes guard. Retaken at the end of save().
        self._clean = self._snapshot()
        self.changed.connect(self._maybe_autosave)

    def _snapshot(self):
        """A hashable-ish dict of every persisted field, for dirty-tracking."""
        return {
            "save_folder": self._save_folder,
            "video_folder": self._video_folder,
            "thumb_folder": self._thumb_folder,
            "filename": self._filename,
            "api_key": self._api_key,
            "backup_keys": tuple(self._backup_keys),
            "export_format": self._export_format,
            "autosave_freq": self._autosave_freq,
            "thread_count": self._thread_count,
            "transcripts": self._transcripts_enabled,
            "cookies": self._cookies_browser,
            "cut_quality": self._cut_quality,
            "ai": self._ai_sig(),
        }

    def _ai_sig(self):
        """The persisted part of the AI block as one comparable string. Only
        the routes Settings owns count — the chat edits its own on disk."""
        a = self._ai
        return json.dumps({
            "profiles": [{k: p.get(k) for k in ai_profiles._FIELDS} for p in a["profiles"]],
            "active": a["active"],
            "routes": {f: a["routes"].get(f) for f in ai_profiles.SETTINGS_FEATURES},
            "proxy": a.get("proxy", ""),
        }, sort_keys=True, default=str)

    # ── static option lists (for QML combos) ──
    # These are translated, so they can't be `constant=True`: the UI language can
    # change while the app runs, and a constant property never re-reads.
    @Property("QStringList", notify=labelsChanged)
    def formatLabels(self):
        return [tr(x) for x in _FORMAT_LABELS]

    @Property("QStringList", notify=labelsChanged)
    def autosaveLabels(self):
        return [tr(x) for x in _AUTOSAVE_LABELS]

    @Property("QStringList", notify=labelsChanged)
    def cookieLabels(self):
        return [tr(x) for x in _COOKIE_LABELS]

    @Property("QStringList", notify=labelsChanged)
    def providerLabels(self):
        # Plain brand names; the picker shows each provider's own logo beside
        # the name (see providerIcons). Gemini is still the suggested one — its
        # "recommended" note lives in the capability line under the picker, not
        # crammed into the label.
        #
        # "Custom" is the fourth row: any OpenAI-compatible router, aggregator
        # or self-hosted gateway, saved under its own name. It speaks all three
        # wire shapes (see the API mode dropdown), so it is not limited to
        # OpenAI-shaped APIs.
        return ["OpenAI", "Anthropic", "Gemini", "Custom"]

    @Property("QStringList", notify=labelsChanged)
    def providerIcons(self):
        """Brand glyph name per provider entry, index-aligned with
        providerLabels. The picker draws these so each option carries its own
        logo."""
        return ["provider_openai", "provider_anthropic", "provider_gemini",
                "provider_custom"]

    @Property("QStringList", notify=labelsChanged)
    def apiModeLabels(self):
        return [AI_API_MODE_LABELS[m] for m in AI_API_MODES]

    # ── i18n ─────────────────────────────────────────────────────────────
    @Slot()
    def retranslate(self):
        """The UI language changed — re-emit so the translated option lists and
        any language-dependent text are re-read."""
        self.labelsChanged.emit()
        self.changed.emit()

    # ── unsaved-changes guard ──
    # SettingsPage.qml mutates fields live and only writes on save(); navigating
    # away would silently discard edits. isDirty drives a nav guard on the
    # AppController, and revert() throws away the pending edits.
    dirtyChanged = Signal()

    @Property(bool, notify=changed)
    def isDirty(self):
        return self._snapshot() != self._clean

    @Slot()
    def revert(self):
        """Restore every field to the last saved (clean) snapshot."""
        c = self._clean
        self._save_folder = c["save_folder"]
        self._video_folder = c["video_folder"]
        self._thumb_folder = c["thumb_folder"]
        self._filename = c["filename"]
        self._api_key = c["api_key"]
        self._backup_keys = list(c["backup_keys"])
        self._export_format = c["export_format"]
        self._autosave_freq = c["autosave_freq"]
        self._thread_count = c["thread_count"]
        self._transcripts_enabled = c["transcripts"]
        self._cookies_browser = c["cookies"]
        self._cut_quality = c["cut_quality"]
        self._ai = copy.deepcopy(self._ai_clean)
        if self._ai_open and not self._prof(self._ai_open):
            self._ai_open = ""
        self._ai_status = {k: v for k, v in self._ai_status.items() if self._prof(k)}
        self.aiProfilesChanged.emit()
        self.aiDataChanged.emit()
        self.changed.emit()
        self.ytKeysChanged.emit()

    # ── clipboard (copy/paste buttons on the API-keys card) ──
    @Slot(str)
    def copyToClipboard(self, text):
        from PySide6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        if cb is not None:
            cb.setText(text or "")

    @Slot(result=str)
    def clipboardText(self):
        from PySide6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        return cb.text() if cb is not None else ""

    # ── per-key validation status ──
    @Slot(str, bool, str)
    def _remember_key_status(self, key, ok, msg):
        if key:
            self._key_status[key] = (ok, msg)

    @Slot(str, result=str)
    def keyStatus(self, key):
        """"ok" / "bad" / "" for a given key — drives the backup-row status dot."""
        key = (key or "").strip()
        st = self._key_status.get(key)
        if st is None:
            return ""
        return "ok" if st[0] else "bad"

    # ── YouTube API keys ──
    @Property(str, notify=changed)
    def apiKey(self):
        return self._api_key

    @apiKey.setter
    def apiKey(self, v):
        v = (v or "").strip()
        if v != self._api_key:
            self._api_key = v
            self.changed.emit()

    @Property("QStringList", notify=ytKeysChanged)
    def backupKeys(self):
        return list(self._backup_keys)

    @Slot()
    def addBackupKey(self):
        self._backup_keys.append("")
        self.ytKeysChanged.emit()

    @Slot(int)
    def removeBackupKey(self, idx):
        if 0 <= idx < len(self._backup_keys):
            self._backup_keys.pop(idx)
            self.ytKeysChanged.emit()

    @Slot(int, str)
    def setBackupKey(self, idx, v):
        if 0 <= idx < len(self._backup_keys):
            self._backup_keys[idx] = (v or "").strip()

    def _collect_youtube_keys(self):
        keys = [self._api_key] + [k.strip() for k in self._backup_keys]
        seen, out = set(), []
        for k in keys:
            if k and k not in seen:
                seen.add(k)
                out.append(k)
        return out

    # ── scrape-pref properties ──
    @Property(int, notify=changed)
    def formatIndex(self):
        try:
            return FORMAT_KEYS.index(self._export_format)
        except ValueError:
            return 0

    @formatIndex.setter
    def formatIndex(self, i):
        i = max(0, min(len(FORMAT_KEYS) - 1, int(i)))
        self._export_format = FORMAT_KEYS[i]
        self.changed.emit()

    @Slot(bool, int)
    def applyScrapePrefs(self, transcripts, format_index):
        """v3.54: the Scraper page's Transcripts switch + export-format chips.
        Written straight to config.json and folded into the clean snapshot,
        so they never leave the Settings page "unsaved"."""
        transcripts = bool(transcripts)
        fmt = FORMAT_KEYS[max(0, min(len(FORMAT_KEYS) - 1, int(format_index)))]
        self._transcripts_enabled = transcripts
        self._export_format = fmt
        if isinstance(self._clean, dict):
            self._clean["transcripts"] = transcripts
            self._clean["export_format"] = fmt
        try:
            cfg = load_app_config()
            cfg["transcripts_enabled"] = transcripts
            cfg["export_format"] = fmt
            save_app_config(cfg)
        except Exception:          # noqa: BLE001
            pass
        self.changed.emit()

    @Property(int, notify=changed)
    def autosaveIndex(self):
        try:
            return _AUTOSAVE_VALUES.index(self._autosave_freq)
        except ValueError:
            return 1

    @autosaveIndex.setter
    def autosaveIndex(self, i):
        i = max(0, min(len(_AUTOSAVE_VALUES) - 1, int(i)))
        self._autosave_freq = _AUTOSAVE_VALUES[i]
        self.changed.emit()

    @Property(int, notify=changed)
    def threadCount(self):
        return self._thread_count

    @threadCount.setter
    def threadCount(self, v):
        v = max(1, min(8, int(v)))
        if v != self._thread_count:
            self._thread_count = v
            self.changed.emit()

    @Property(bool, notify=changed)
    def transcriptsEnabled(self):
        return self._transcripts_enabled

    @transcriptsEnabled.setter
    def transcriptsEnabled(self, v):
        v = bool(v)
        if v != self._transcripts_enabled:
            self._transcripts_enabled = v
            self.changed.emit()

    @Property(int, notify=changed)
    def cookieIndex(self):
        try:
            return _COOKIE_VALUES.index(self._cookies_browser)
        except ValueError:
            return 0

    @cookieIndex.setter
    def cookieIndex(self, i):
        i = max(0, min(len(_COOKIE_VALUES) - 1, int(i)))
        self._cookies_browser = _COOKIE_VALUES[i]
        self.changed.emit()

    @Property(int, notify=changed)
    def cutQualityIndex(self):
        """0 = high, 1 = balanced (default), 2 = small."""
        try:
            return _CUT_QUALITY_VALUES.index(self._cut_quality)
        except ValueError:
            return _CUT_QUALITY_VALUES.index(_CUT_QUALITY_DEFAULT)

    @cutQualityIndex.setter
    def cutQualityIndex(self, i):
        i = max(0, min(len(_CUT_QUALITY_VALUES) - 1, int(i)))
        v = _CUT_QUALITY_VALUES[i]
        if v != self._cut_quality:
            self._cut_quality = v
            self.changed.emit()

    # ═════════════════════════════════════════════════════════════════
    #  AI providers — profiles, the default, and per-feature routing
    # ═════════════════════════════════════════════════════════════════
    # Quick starts for "Add provider". Each one is an ordinary custom profile
    # with its host and wire shape filled in; nothing about them is special
    # after creation.
    _AI_PRESETS = (
        # id,          name,         host,                                   mode,                 glyph
        ("custom",     "",           "",                                     "openai_compatible",  "provider_custom"),
        ("openrouter", "OpenRouter", "https://openrouter.ai/api/v1",         "openai_compatible",  "route"),
        ("deepseek",   "DeepSeek",   "https://api.deepseek.com/v1",          "openai_compatible",  "api"),
        ("groq",       "Groq",       "https://api.groq.com/openai/v1",       "openai_compatible",  "bolt"),
        ("xai",        "xAI Grok",   "https://api.x.ai/v1",                  "openai_compatible",  "auto_awesome"),
        ("mistral",    "Mistral",    "https://api.mistral.ai/v1",            "openai_compatible",  "sparkling"),
        ("ollama",     "Ollama",     "http://localhost:11434/v1",            "openai_compatible",  "desktop_windows"),
        ("lmstudio",   "LM Studio",  "http://localhost:1234/v1",             "openai_compatible",  "terminal"),
    )
    _AI_FEATURES = (
        # feature, title, sub, icon
        ("ideas",   "Idea generation", "AI Ideas and Content Lab blueprints", "nav_ideas"),
        # "AI Chat" picks its provider, model and effort in its own composer
        # (every saved provider's models are listed there), and "Reports" is
        # gone — neither has a row here any more.
    )

    # ── persistence (AI block saves itself) ──
    def _ai_touched(self, structure=False):
        if structure:
            self.aiProfilesChanged.emit()
        self.aiDataChanged.emit()
        # the legacy mirrors (health tile, guide) — and the save mode: this
        # reaches _maybe_autosave, which writes it when auto-save is on and
        # otherwise leaves it for the Save button
        self.changed.emit()

    def _persist_ai(self):
        try:
            cfg = load_app_config()
            # the chat's own route lives on disk; never overwrite it from here
            ai_profiles.merge_foreign_routes(self._ai, cfg)
            ai_profiles.write_state(cfg, self._ai)
            save_app_config(cfg)
        except Exception:
            log_crash("qml persist ai profiles:\n" + traceback.format_exc())
            return
        self.aiSaved.emit()     # AI Chat refreshes its model list from disk

    @Slot()
    def _flush_ai(self):
        """App closing: a pending auto-save must still reach the disk."""
        if self._ai_save_timer.isActive():
            self._ai_save_timer.stop()
            self._persist_ai()
        if self._autosave_timer.isActive():
            self._autosave_timer.stop()
            self._autosave_now()

    # ── save mode ──
    def _maybe_autosave(self):
        if self._autosave and self.isDirty:
            self._autosave_timer.start()

    @Slot()
    def _autosave_now(self):
        if self._autosave and self.isDirty:
            self._save(quiet=True)
            self.autoSaved.emit()

    @Slot()
    def flushAutosave(self):
        """Write a pending auto-save right now (the page is being left)."""
        if self._autosave_timer.isActive():
            self._autosave_timer.stop()
            self._autosave_now()

    @Property(bool, notify=changed)
    def autoSave(self):
        return self._autosave

    @Slot(bool)
    def setAutoSave(self, on):
        on = bool(on)
        if on == self._autosave:
            return
        self._autosave = on
        try:
            cfg = load_app_config()
            cfg["settings_autosave"] = on
            save_app_config(cfg)
        except Exception:
            log_crash("qml save settings_autosave:\n" + traceback.format_exc())
        if not on:
            self._autosave_timer.stop()
            self.changed.emit()
            self.toast.emit(tr("Auto-save off. Changes wait for Save."), "info")
            return
        # turning it on with edits pending: write them now
        if self.isDirty:
            self._save(quiet=True)
            self.autoSaved.emit()
            self.toast.emit(tr("Auto-save on. Your changes were saved."), "success")
        else:
            self.changed.emit()
            self.toast.emit(tr("Auto-save on."), "success")

    def _prof(self, pid):
        return ai_profiles.find(self._ai, pid)

    def _active(self):
        return self._prof(self._ai["active"]) or self._ai["profiles"][0]

    @staticmethod
    def _ready(p):
        if p["kind"] == "custom":
            return bool(p["base_url"].strip())
        return bool(p["api_key"].strip())

    def _client_for(self, p, model=None):
        """An AIClient for one profile, exactly as a real feature call builds it."""
        prov = ai_profiles.provider_of(p)
        return AIClient(prov, p["api_key"], model or ai_profiles.effective_model(p),
                        p["base_url"], self._ai.get("proxy", ""),
                        path=p["path"] or "/chat/completions",
                        custom_name=p["name"] if prov == "custom" else None,
                        api_mode=p["api_mode"] or None)

    def _profile_qml(self, p):
        prov = ai_profiles.provider_of(p)
        mode = api_mode_for(prov, p["api_mode"] or None)
        used = []
        for f, title, _sub, _ic in self._AI_FEATURES:
            r = self._ai["routes"].get(f, {})
            target = r.get("profile") or self._ai["active"]
            if target == p["id"]:
                used.append(tr(title))
        if mode == "google_genai":
            mode_hint = tr("Sends Google's generateContent request. The model id goes in the URL, so API Path is unused.")
        elif mode == "anthropic_messages":
            mode_hint = tr("Sends Anthropic's /v1/messages request, with the key in an x-api-key header.")
        else:
            mode_hint = tr("Sends OpenAI's /chat/completions request, with the key as a bearer token.")
        if prov == "custom" and not p["base_url"]:
            endpoint = tr("set API HOST first")
        else:
            try:
                endpoint = self._client_for(p).endpoint()
            except Exception:
                endpoint = ""
        default_model = AI_PROVIDER_DEFAULT_MODEL.get(prov, "")
        # v3.16-p3: three lists, three jobs —
        #   catalog: everything Fetch found (or Anthropic's known ids), the
        #            pool the picker ticks from;
        #   picked:  what the user ADDED to this provider;
        #   models:  what a model chooser offers = picked, or just the
        #            provider's own model when nothing was added yet.
        catalog = list(p.get("models") or [])
        if not catalog and prov == "anthropic":
            from app.core.ai.clients import ANTHROPIC_KNOWN_MODELS
            catalog = list(ANTHROPIC_KNOWN_MODELS)
        picked = list(p.get("picked") or [])
        models = picked or [m for m in (p["model"] or default_model,) if m]
        key = p["api_key"]
        st = self._ai_status.get(p["id"], {})
        return {
            "id": p["id"],
            "kind": p["kind"],
            "name": p["name"],
            "builtin": p["kind"] in ai_profiles.BUILTIN_KINDS,
            "active": p["id"] == self._ai["active"],
            "open": p["id"] == self._ai_open,
            "ready": self._ready(p),
            "apiKey": key,
            "keyHint": ("••••" + key[-4:]) if len(key) >= 8 else ("••••" if key else ""),
            "model": p["model"],
            "effectiveModel": ai_profiles.effective_model(p),
            "models": list(dict.fromkeys(models)),
            "picked": picked,
            "catalog": list(dict.fromkeys(catalog)),
            "fetchedCount": len(p.get("models") or []),
            "baseUrl": p["base_url"],
            "path": p["path"],
            "apiModeIndex": AI_API_MODES.index(mode) if mode in AI_API_MODES else 0,
            "isGoogle": mode == "google_genai",
            "modeHint": mode_hint,
            "endpoint": endpoint,
            "hostPlaceholder": AI_PROVIDER_DEFAULTS.get(prov, {}).get("base_url", "")
                               or "https://openrouter.ai/api/v1",
            "pathPlaceholder": tr("not used for this API mode") if mode == "google_genai"
                               else (default_path_for(prov, p["api_mode"] or None) or "/chat/completions"),
            "modelPlaceholder": default_model or tr("exact model id"),
            "glyph": {"openai": "provider_openai", "anthropic": "provider_anthropic",
                      "gemini": "provider_gemini"}.get(p["kind"], "provider_custom"),
            "usedBy": used,
            "state": int(st.get("state", 0)),
            "status": st.get("msg", ""),
            "statusSrc": st.get("src", ""),
        }

    @Property("QStringList", notify=aiProfilesChanged)
    def aiProfileIds(self):
        """Structure only. The accordion's Repeater binds to THIS, so typing in
        a field (which changes aiProfileMap) never rebuilds the cards and never
        steals focus from the field being typed in."""
        return [p["id"] for p in self._ai["profiles"]]

    @Property("QVariantMap", notify=aiDataChanged)
    def aiProfileMap(self):
        return {p["id"]: self._profile_qml(p) for p in self._ai["profiles"]}

    @Property(str, notify=aiDataChanged)
    def aiActiveId(self):
        return self._ai["active"]

    @Property(str, notify=aiDataChanged)
    def aiOpenId(self):
        return self._ai_open

    @Slot(str)
    def setAiOpen(self, pid):
        """Which card is expanded (one at a time). "" collapses all."""
        pid = pid if (pid == "" or self._prof(pid)) else ""
        if pid != self._ai_open:
            self._ai_open = pid
            self.aiDataChanged.emit()

    @Property(int, notify=aiDataChanged)
    def aiReadyCount(self):
        return sum(1 for p in self._ai["profiles"] if self._ready(p))

    @Property("QVariantList", notify=labelsChanged)
    def aiPresets(self):
        out = []
        for pid, name, host, mode, glyph in self._AI_PRESETS:
            out.append({"id": pid, "name": name or tr("Custom endpoint"), "host": host,
                        "glyph": glyph,
                        "local": host.startswith("http://localhost")})
        return out

    @Slot(str, result=str)
    def addAiProfile(self, preset):
        """A new custom profile from a quick start (or blank). Returns its id;
        the new card opens straight away."""
        hit = next((x for x in self._AI_PRESETS if x[0] == preset), self._AI_PRESETS[0])
        _pid, name, host, mode, _glyph = hit
        base = name or tr("Custom")
        taken = {p["name"].lower() for p in self._ai["profiles"]}
        final, n = base, 2
        while final.lower() in taken:
            final, n = f"{base} {n}", n + 1
        p = ai_profiles.blank_custom(final, mode)
        p["base_url"] = host
        self._ai["profiles"].append(p)
        self._ai_open = p["id"]
        self._ai_touched(structure=True)
        return p["id"]

    @Slot(str, result=str)
    def duplicateAiProfile(self, pid):
        src = self._prof(pid)
        if not src:
            return ""
        p = dict(src)
        p["id"] = ai_profiles.new_profile_id()
        p["kind"] = "custom" if src["kind"] == "custom" else src["kind"]
        if p["kind"] != "custom":
            # a second key for a built-in brand is a custom profile on its host
            prov = src["kind"]
            p["kind"] = "custom"
            p["base_url"] = src["base_url"] or AI_PROVIDER_DEFAULTS.get(prov, {}).get("base_url", "")
            p["api_mode"] = src["api_mode"] or AI_PROVIDER_API_MODE.get(prov, "openai_compatible")
        p["name"] = tr("{name} copy").format(name=src["name"])
        p["models"] = list(src.get("models") or [])
        i = self._ai["profiles"].index(src)
        self._ai["profiles"].insert(i + 1, p)
        self._ai_open = p["id"]
        self._ai_touched(structure=True)
        return p["id"]

    @Slot(str)
    def removeAiProfile(self, pid):
        p = self._prof(pid)
        if not p or p["kind"] in ai_profiles.BUILTIN_KINDS:
            return
        self._ai["profiles"].remove(p)
        if self._ai["active"] == pid:
            nxt = next((x for x in self._ai["profiles"] if self._ready(x)), None)
            self._ai["active"] = nxt["id"] if nxt else "gemini"
        for r in self._ai["routes"].values():
            if r.get("profile") == pid:
                r["profile"], r["model"] = "", ""
        self._ai_status.pop(pid, None)
        if self._ai_open == pid:
            self._ai_open = ""
        self._ai_touched(structure=True)
        self.toast.emit(tr("Removed {name}.").format(name=p["name"]), "info")

    @Slot(str)
    def setAiActive(self, pid):
        if self._prof(pid) and pid != self._ai["active"]:
            self._ai["active"] = pid
            self._ai_touched()

    @Slot(str, str, str)
    def setAiField(self, pid, field, value):
        """One profile field from the form: name · apiKey · model · baseUrl ·
        path. Blank host / path / model still mean "this provider's default"."""
        p = self._prof(pid)
        key = {"name": "name", "apiKey": "api_key", "model": "model",
               "baseUrl": "base_url", "path": "path"}.get(field)
        if not p or not key:
            return
        v = (value or "").strip()
        if key == "name" and not v:
            return              # a profile always has a name
        if key == "base_url":
            v = v.rstrip("/")
        if key == "path" and v == "/chat/completions":
            v = ""              # the shape's default; keep it implicit
        if p[key] == v:
            return
        if key == "base_url":
            p["models"] = []    # a different host serves a different catalogue
        if key == "model" and v and v not in p.setdefault("picked", []):
            p["picked"].insert(0, v)    # the main model is always a picked one
        p[key] = v
        if key in ("api_key", "base_url"):
            self._ai_status.pop(pid, None)
        self._ai_touched()

    # ── picked models: the short list a provider offers (v3.16-p3) ──
    @Slot(str, str)
    def addAiModel(self, pid, model):
        """Add one model id to a provider's list (from the fetched catalogue or
        typed by hand). The first one added becomes the provider's model."""
        p = self._prof(pid)
        model = (model or "").strip()
        if not p or not model:
            return
        picked = p.setdefault("picked", [])
        if model in picked:
            return
        picked.append(model)
        if not p["model"]:
            p["model"] = model
        self._ai_touched()

    @Slot(str, str)
    def removeAiModel(self, pid, model):
        """Take a model off a provider's list. If it was the provider's main
        model the next one takes over, and any feature pinned to it (the chat
        composer, AI routing) falls back to the provider's model."""
        p = self._prof(pid)
        model = (model or "").strip()
        if not p or model not in (p.get("picked") or []):
            return
        p["picked"] = [m for m in p["picked"] if m != model]
        if p["model"] == model:
            p["model"] = p["picked"][0] if p["picked"] else ""
        for r in self._ai["routes"].values():
            if r.get("model") == model and (r.get("profile") or self._ai["active"]) == pid:
                r["model"] = ""
        self._ai_touched()

    @Slot(str, str)
    def toggleAiModel(self, pid, model):
        p = self._prof(pid)
        if not p:
            return
        if (model or "").strip() in (p.get("picked") or []):
            self.removeAiModel(pid, model)
        else:
            self.addAiModel(pid, model)

    @Slot(str, "QStringList")
    def addAiModels(self, pid, models):
        """Add several at once (the picker's "add all matches")."""
        p = self._prof(pid)
        if not p:
            return
        picked = p.setdefault("picked", [])
        added = [m.strip() for m in (models or []) if m and m.strip() and m.strip() not in picked]
        if not added:
            return
        picked.extend(added[:max(0, 100 - len(picked))])
        if not p["model"] and picked:
            p["model"] = picked[0]
        self._ai_touched()

    @Slot(str, str)
    def setAiMainModel(self, pid, model):
        """Make one of the picked models the provider's default model."""
        p = self._prof(pid)
        model = (model or "").strip()
        if not p or not model or p["model"] == model:
            return
        if model not in p.setdefault("picked", []):
            p["picked"].append(model)
        p["model"] = model
        self._ai_touched()

    @Slot(str, int)
    def setAiApiMode(self, pid, index):
        p = self._prof(pid)
        if not p:
            return
        index = max(0, min(len(AI_API_MODES) - 1, int(index)))
        mode = AI_API_MODES[index]
        if mode == api_mode_for(ai_profiles.provider_of(p), p["api_mode"] or None):
            return
        p["api_mode"] = mode
        p["models"] = []
        self._ai_status.pop(pid, None)
        self._ai_touched()

    # ── routing: which provider / model / effort each feature uses ──
    @Property("QVariantList", notify=aiDataChanged)
    def aiRoutes(self):
        out = []
        for f, title, sub, icon in self._AI_FEATURES:
            r = self._ai["routes"].get(f, {})
            prof = self._prof(r.get("profile") or "") or self._active()
            model = r.get("model") or ""
            pq = self._profile_qml(prof)
            out.append({
                "feature": f, "title": tr(title), "sub": tr(sub), "icon": icon,
                "profile": r.get("profile") or "",
                "model": model,
                "effort": r.get("effort") or "auto",
                "effortIndex": EFFORT_LEVELS.index(r.get("effort") or "auto")
                               if (r.get("effort") or "auto") in EFFORT_LEVELS else 0,
                "resolvedId": prof["id"],
                "resolvedName": prof["name"],
                "resolvedModel": ai_profiles.effective_model(prof, model),
                "resolvedGlyph": pq["glyph"],
                "ready": self._ready(prof),
                "models": pq["models"],
            })
        return out

    @Property("QVariantList", notify=aiDataChanged)
    def aiRouteChoices(self):
        act = self._active()
        out = [{"id": "", "label": tr("Default ({name})").format(name=act["name"]),
                "glyph": "star", "ready": self._ready(act)}]
        for p in self._ai["profiles"]:
            out.append({"id": p["id"], "label": p["name"],
                        "glyph": self._profile_qml(p)["glyph"], "ready": self._ready(p)})
        return out

    @Slot(str, str, str)
    def setAiRoute(self, feature, field, value):
        if feature not in ai_profiles.FEATURES or field not in ("profile", "model", "effort"):
            return
        r = self._ai["routes"][feature]
        value = (value or "").strip()
        if field == "effort":
            from app.core.ai.effort import norm_effort
            value = norm_effort(value)
        if r.get(field) == value:
            return
        r[field] = value
        if field == "profile":
            r["model"] = ""
        self._ai_touched()

    @Property("QVariantList", notify=labelsChanged)
    def effortOptions(self):
        return [{"value": v, "label": tr(EFFORT_LABELS[v]), "hint": tr(EFFORT_HINTS[v])}
                for v in EFFORT_LEVELS]

    @Property(str, notify=aiDataChanged)
    def aiProxy(self):
        return self._ai.get("proxy", "")

    @aiProxy.setter
    def aiProxy(self, v):
        v = (v or "").strip()
        if v != self._ai.get("proxy", ""):
            self._ai["proxy"] = v
            self._ai_touched()

    # ── legacy mirrors of the DEFAULT profile ──
    # The health strip, the rail dot and the key guide only ever cared about
    # "the" provider; they now read the default profile.
    @Property(int, notify=changed)
    def providerIndex(self):
        kind = self._active()["kind"]
        return UI_PROVIDERS.index(kind) if kind in UI_PROVIDERS else 3

    @providerIndex.setter
    def providerIndex(self, i):
        i = max(0, min(len(UI_PROVIDERS) - 1, int(i)))
        kind = UI_PROVIDERS[i]
        if kind == "custom":
            p = next((x for x in self._ai["profiles"] if x["kind"] == "custom"), None)
            pid = p["id"] if p else self.addAiProfile("custom")
        else:
            pid = kind
        self._ai_open = pid
        self.setAiActive(pid)
        self.aiDataChanged.emit()

    @Property(bool, notify=changed)
    def isGeminiProvider(self):
        p = self._active()
        return api_mode_for(ai_profiles.provider_of(p), p["api_mode"] or None) == "google_genai"

    @Property(bool, notify=changed)
    def isCustomProvider(self):
        return self._active()["kind"] == "custom"

    @Property(str, notify=changed)
    def aiCustomName(self):
        return self._active()["name"]

    @Property(str, notify=changed)
    def aiProviderName(self):
        return self._active()["name"]

    @Property(bool, notify=changed)
    def aiReady(self):
        return self._ready(self._active())

    @Property(str, notify=changed)
    def aiApiKey(self):
        return self._active()["api_key"]

    @Property(str, notify=changed)
    def aiModel(self):
        return ai_profiles.effective_model(self._active())

    # ── validation: YouTube key ──
    @Slot(str)
    def validateYouTubeKey(self, key):
        key = (key or "").strip()
        if not key:
            self.ytValidateResult.emit("", False, tr("Enter a key first."))
            return

        def worker():
            try:
                yt = build_youtube_service(key)
                yt.i18nLanguages().list(part="snippet").execute()
                ok, msg = True, tr("Key is valid.")
            except HttpError as e:
                ok, msg = False, tr("Invalid key or quota issue ({code}).").format(code=e.resp.status)
            except Exception as e:
                ok, msg = False, tr("Validation failed: {err}").format(err=e)
            self.ytValidateResult.emit(key, ok, msg)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, result=str)
    def keyQuotaLine(self, key):
        key = (key or "").strip()
        if not key:
            return ""
        used = key_quota_used(key)
        remaining = key_quota_remaining(key)
        if used <= 0:
            return tr("{r} quota units available today.").format(r=f"{remaining:,}")
        return tr("{r} / {c} quota units left today ({u} already spent).").format(
            r=f"{remaining:,}", c=f"{API_QUOTA_PER_KEY:,}", u=f"{used:,}")

    # ── validation + model fetch, per profile ──
    # explicit slots: these receive worker-thread signals, and must run on the
    # GUI thread (they mutate VM state and start the save QTimer)
    @Slot(str, int, str, str)
    def _on_ai_status(self, pid, state, msg, src):
        self._ai_status[pid] = {"state": int(state), "msg": msg, "src": src}
        self.aiDataChanged.emit()

    @Slot(str, bool, "QStringList", str)
    def _on_ai_models(self, pid, ok, models, err):
        p = self._prof(pid)
        if not p:
            return
        if ok and models:
            p["models"] = list(dict.fromkeys(str(m) for m in models if m))[:400]
            # v3.16-p3: no silent auto-pick any more — the card opens its
            # picker and the user ticks the models they want on this provider.
            self._ai_status[pid] = {"state": 2, "src": "models",
                                    "msg": tr("Found {n} models. Tick the ones you want to add.").format(n=len(p["models"]))}
            self._ai_touched()
            self.aiCatalogReady.emit(pid)
        else:
            self._ai_status[pid] = {"state": 3, "src": "models",
                                    "msg": err or tr("The provider returned no models.")}
            self.aiDataChanged.emit()

    @Slot(str)
    def validateAiProfile(self, pid):
        p = self._prof(pid)
        if not p:
            return
        client = self._client_for(p)
        endpoint = client.endpoint() if (p["kind"] != "custom" or p["base_url"]) else ""
        proxy = self._ai.get("proxy", "")
        if p["kind"] == "custom" and not p["base_url"]:
            self._aiStatusSig.emit(pid, 3, tr("Set API HOST first."), "key")
            return
        if not client.model:
            self._aiStatusSig.emit(pid, 3, tr("No model selected yet — press Fetch to pull the model list, or type one."), "key")
            return
        if not p["api_key"] and p["kind"] != "custom":
            self._aiStatusSig.emit(pid, 3, tr("Enter an API key first."), "key")
            return
        needs_host = bool(p["base_url"])
        self._aiStatusSig.emit(pid, 1, tr("Validating …"), "key")

        def worker():
            try:
                if needs_host:
                    try:
                        _urlopen(urllib.request.Request(endpoint, method="GET"), 12, proxy)
                    except urllib.error.HTTPError:
                        pass    # any HTTP status means the host answered
                    except Exception as e:
                        if not is_dropped_connection(e):
                            if isinstance(e, urllib.error.URLError):
                                self._aiStatusSig.emit(pid, 3, tr("API Host is not reachable: {reason}").format(reason=e.reason), "key")
                                return
                            raise
                    self._aiStatusSig.emit(pid, 1, tr("API Host OK — checking API key …"), "key")
                client.generate("Reply with only the single word: ok", timeout=25)
                self._aiStatusSig.emit(pid, 2, tr("Key is valid and working."), "key")
            except Exception as e:
                log_crash("qml ai validate:\n" + traceback.format_exc())
                self._aiStatusSig.emit(pid, 3, tr("Validation failed: {err}").format(err=e), "key")

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str)
    def fetchAiProfileModels(self, pid):
        """Pull one profile's model catalogue through clients.list_models (each
        wire shape publishes it differently). Stored on the profile, so the
        list is still there next launch."""
        p = self._prof(pid)
        if not p:
            return
        if p["kind"] == "custom" and not p["base_url"]:
            self._aiStatusSig.emit(pid, 3, tr("Set API HOST first."), "models")
            return
        prov = ai_profiles.provider_of(p)
        args = dict(base_url=p["base_url"], path=p["path"] or "/chat/completions",
                    timeout=20, proxy=self._ai.get("proxy", ""),
                    api_mode=p["api_mode"] or None)
        key = p["api_key"]
        self._aiStatusSig.emit(pid, 1, tr("Fetching models …"), "models")

        def worker():
            try:
                models = list_models(prov, key, **args)
                self._aiModelsSig.emit(pid, True, [str(m) for m in models], "")
            except Exception as exc:
                log_crash("qml fetch ai models:\n" + traceback.format_exc())
                self._aiModelsSig.emit(pid, False, [], str(exc))

        threading.Thread(target=worker, daemon=True).start()

    # Old single-provider entry points, kept for any caller still using them.
    @Slot()
    def validateAiKey(self):
        self.validateAiProfile(self._ai["active"])

    @Slot()
    def fetchAiModels(self):
        self.fetchAiProfileModels(self._ai["active"])

    # ── persistence ──
    @Slot(str)
    def setSaveFolder(self, path):
        path = local_path_from_url(path)
        self._save_folder = path
        self.changed.emit()

    @Property(str, notify=changed)
    def saveFolder(self):
        return self._save_folder

    # ── per-kind save locations ──
    @Property(str, notify=changed)
    def videoFolder(self):
        return self._video_folder

    @Property(str, notify=changed)
    def thumbFolder(self):
        return self._thumb_folder

    @Property(str, notify=changed)
    def videoFolderDefault(self):
        """Where videos go while no folder is chosen — shown as a hint."""
        try:
            from app.core.utils import desktop_download_dir
            return desktop_download_dir("YouTube")
        except Exception:      # noqa: BLE001
            return ""

    @Slot(str)
    def setVideoFolder(self, path):
        self._video_folder = local_path_from_url(path) or ""
        self.changed.emit()

    @Slot(str)
    def setThumbFolder(self, path):
        self._thumb_folder = local_path_from_url(path) or ""
        self.changed.emit()

    @Slot(str)
    def openFolder(self, path):
        """Open a folder in Explorer, creating it first if it's the default
        Desktop/YouTube that no download has made yet."""
        path = (path or "").strip()
        if not path:
            return
        try:
            os.makedirs(path, exist_ok=True)
        except OSError:
            pass
        from PySide6.QtCore import QUrl
        from PySide6.QtGui import QDesktopServices
        QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    @Slot()
    def reloadFolders(self):
        """Pick up a thumbnail folder chosen elsewhere (Niche Finder / Search
        Archive ask for one the first time) — unless the user is mid-edit of
        that very field here, in which case their edit wins."""
        cfg = load_app_config()
        moved = False
        for attr, key, snap in (("_video_folder", "video_save_folder", "video_folder"),
                                ("_thumb_folder", "thumb_save_folder", "thumb_folder")):
            disk = cfg.get(key, "") or ""
            if getattr(self, attr) == self._clean.get(snap) and disk != getattr(self, attr):
                setattr(self, attr, disk)
                self._clean[snap] = disk
                moved = True
        if moved:
            self.changed.emit()

    @Slot()
    def save(self):
        """Persist every setting to config.json, then refresh the sidebar
        quota ring through the AppController."""
        self._autosave_timer.stop()
        self._save(quiet=False)

    def _save(self, quiet=False):
        keys_before = (self._clean.get("api_key"), self._clean.get("backup_keys"))
        cfg = load_app_config()
        yt_keys = self._collect_youtube_keys()
        # Folders: only write the ones edited here, so a thumbnail folder picked
        # on another page since this one loaded is never clobbered.
        if self._video_folder != self._clean.get("video_folder"):
            cfg["video_save_folder"] = self._video_folder
        if self._thumb_folder != self._clean.get("thumb_folder"):
            cfg["thumb_save_folder"] = self._thumb_folder
        cfg.update({
            "save_folder": self._save_folder,
            "output_filename": self._filename,
            "api_key": self._api_key,
            "youtube_api_keys": yt_keys,
            "export_format": self._export_format,
            "autosave_freq": self._autosave_freq,
            "thread_count": self._thread_count,
            "transcripts_enabled": self._transcripts_enabled,
            "yt_cookies_browser": self._cookies_browser,
            "cut_quality": self._cut_quality,
        })
        # the AI block saves itself, but a Save writes it too (cheap, and it
        # means one Save is always a complete snapshot of the page)
        self._ai_save_timer.stop()
        ai_profiles.merge_foreign_routes(self._ai, cfg)
        ai_profiles.write_state(cfg, self._ai)
        save_app_config(cfg)
        self._ai_clean = copy.deepcopy(self._ai)
        self.aiSaved.emit()
        keys_changed = keys_before != (self._api_key, tuple(self._backup_keys))
        if self._app is not None and (keys_changed or not quiet):
            self._app._youtube_api_keys = yt_keys
            self._app.refresh_quota()
        # Everything on disk now — this is the new clean baseline for the guard.
        self._clean = self._snapshot()
        self.changed.emit()
        if not quiet:
            self.toast.emit(tr("Settings saved."), "success")
