"""app.qml_backend.vm.chat_vm - YouTube Hunter (QML).

ViewModel behind AIChatPage.qml — "Hunter", the AI studio partner.

What it owns:
  * threads      — the conversation rail (search, pin, rename, delete, export)
  * the turn     — one streamed answer at a time, on a worker thread, with a
                   Stop that really stops (the socket is shut, see
                   app.core.ai.chat.abort_response)
  * sources      — the data attached to the open thread (Niche Finder /
                   Archive videos, YouTube links, files, Google Drive imports,
                   images), each digested ONCE on a worker and cached in the DB
  * the composer — the chips waiting to ride on the next message

Everything that talks to a network or reads a file runs on a worker thread and
comes back through a private Signal (queued onto the GUI thread). Nothing here
touches QML items directly.

Streaming tokens are NOT pushed through the `messages` list: rebuilding the
ListView per token would re-create every delegate. The live answer has its own
`streamText` property, flushed at most every 45 ms, and only the finished turn
is appended to `messages`.
"""

import base64
import os
import re
import threading
from concurrent.futures import ThreadPoolExecutor
import traceback
from datetime import date, datetime, timedelta

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices, QGuiApplication

from app.config import load_app_config
from app.core.ai.effort import EFFORT_HINTS, EFFORT_LABELS, EFFORT_LEVELS
from app.core.ai.profiles import effective_model as effective_ai_model
from app.core.ai.profiles import find as find_ai_profile
from app.core.ai.profiles import load_state as load_ai_state
from app.core.ai.profiles import resolve as resolve_ai_route
from app.core.ai.profiles import update_route as update_ai_route
from app.core.ai.profiles import set_route_target as set_ai_route_target
from app.core import gdrive
from app.core.ai.chat import (ChatCancelled, abort_response, bind_idea_sources,
                              build_system_prompt, classify_turn,
                              fit_history, parts_to_markdown, split_parts,
                              stream_chat, stream_display, strip_followups,
                              title_for, title_prompt)
from app.core.ai.chat_sources import (ALL_EXTS, brief_source, digest,
                                      file_source, image_payload,
                                      kind_for_path, sources_block,
                                      video_set_analysis, video_source,
                                      written_brief_source)
from app.core.db.insights import insights_list
from app.core.ai.clients import (AI_PROVIDER_DEFAULT_MODEL, AIClient,
                                 api_mode_for)
from app.core.db.chat import (CHAT_FILES_DIR, chat_add_message,
                              chat_add_source, chat_create_thread,
                              chat_delete_all, chat_delete_messages_from,
                              chat_delete_thread, chat_get_thread,
                              chat_list_threads, chat_messages, chat_pin_thread,
                              chat_remove_source, chat_rename_thread,
                              chat_set_source_digest, chat_sources,
                              chat_store_file, chat_thread_signature,
                              init_chat_db)
from app.core.net import explain_network_error, extract_video_id
from app.core.niche.helpers import format_multiplier
from app.core.utils import humanize_count, local_path_from_url
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm._idea_shape import mmss
from app.qml_backend.desktop_notifier import announce

SOURCE_BUDGET = 42000          # mirrors sources_block(budget=42000)
# Source reading (transcripts/files) is bounded: reopening a thread with many
# unread sources used to start one thread + one network fetch per source at once.
_DIGEST_POOL = ThreadPoolExecutor(max_workers=4, thread_name_prefix="chat-digest")

def _notice_preview(text, limit=160):
    """First words of an answer, without the markdown, for the desktop toast."""
    import re as _re
    t = _re.sub(r"```.*?```", " ", str(text or ""), flags=_re.S)
    t = _re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = _re.sub(r"[#*_`>|~]+", "", t)
    t = " ".join(t.split())
    return t if len(t) <= limit else t[:limit - 1].rstrip() + "…"


_STOPPED = "[stopped]"         # error-column sentinel for an answer cut by Stop
_PICKER_LIMIT = 150


def _b64(url):
    if not url:
        return ""
    return base64.b64encode(str(url).encode("utf-8")).decode("ascii")


def _thumb_src(src):
    """A ready-to-bind Image.source for a source dict."""
    thumb = (src or {}).get("thumb") or ""
    if not thumb:
        return ""
    if thumb.startswith(("http://", "https://")):
        return "image://thumbs/" + _b64(thumb)
    if os.path.isfile(thumb):
        return QUrl.fromLocalFile(thumb).toString()
    return ""


def _num(v):
    try:
        return float(str(v).replace(",", ""))
    except (TypeError, ValueError):
        return 0.0


def _mult_of(row):
    m = row.get("multiplier")
    try:
        if m not in (None, "", "N/A"):
            return float(m)
    except (TypeError, ValueError):
        pass
    views, subs = _num(row.get("view_count")), _num(row.get("subscriber_count"))
    return views / subs if subs > 0 else 0.0


def _is_short(row):
    """Same rule as the Niche Finder (detect_short): an explicit flag wins,
    otherwise anything up to 3 minutes is a Short."""
    flag = row.get("is_short")
    if isinstance(flag, bool):
        return flag
    try:
        from app.core.niche.helpers import detect_short
        return bool(detect_short(row.get("duration_s", 0), row.get("title", ""),
                                 row.get("description", "")))
    except Exception:
        d = _num(row.get("duration_s"))
        return 0 < d <= 180


def _has_transcript(row):
    t = row.get("transcript")
    if isinstance(t, str) and t.strip() and t.strip().upper() != "N/A":
        return True
    return row.get("has_captions") in (True, "true", "True", 1, "1")


def _published_key(row):
    return str(row.get("published_at") or row.get("publish_date") or "")


def _when(stamp):
    """(group, short label) for a thread's updated_at."""
    try:
        dt = datetime.fromisoformat(str(stamp))
    except Exception:
        return "older", ""
    today = date.today()
    if dt.date() == today:
        return "today", dt.strftime("%H:%M")
    if dt.date() == today - timedelta(days=1):
        return "week", tr("Yesterday")
    if dt.date() > today - timedelta(days=7):
        return "week", dt.strftime("%a")
    return "older", dt.strftime("%Y-%m-%d")


class ChatVM(QObject):
    """AI Chat: talk to your own YouTube data."""

    threadsChanged = Signal()
    threadChanged = Signal()
    messagesChanged = Signal()
    sourcesChanged = Signal()
    pendingChanged = Signal()
    streamChanged = Signal()
    busyChanged = Signal()
    configChanged = Signal()
    pickerChanged = Signal()
    driveChanged = Signal()
    labelsChanged = Signal()
    toast = Signal(str, str)
    # Asks the ListView to jump to the end (a new turn, a finished answer).
    scrollToEnd = Signal()

    # ── worker → GUI (queued) ──
    _delta = Signal(int, str)
    _step = Signal(int, int)
    _turnDone = Signal(int, int, str, str, bool, str)
    _sourceDone = Signal(int, str, str, str)          # tid, key, digest, error
    _sourceAdd = Signal(int, "QVariant", str)          # tid, source, error
    _sourcesAdd = Signal(int, "QVariant", int)         # v3.49: tid, [sources], failed count
    briefsChanged = Signal()
    _driveDone = Signal(str, "QVariant", str)          # op, payload, error
    _titleDone = Signal(int, str)
    _openUrl = Signal(str)
    _prefetched = Signal(int, int, object)          # tid, generation, snapshot (raw Python, no QVariant copy)

    def __init__(self, niche_vm=None, parent=None):
        super().__init__(parent)
        init_chat_db()
        self._niche_vm = niche_vm
        self._reload_ai_config()

        self._search = ""
        self._threads = []
        self._tid = 0
        self._title = ""
        self._pinned = False
        self._messages = []
        self._sources = []
        self._src_titles = {}
        # v3.40.7: hover prefetch. tid -> (signature, raw_sources, messages),
        # built off the GUI thread while the pointer rests on a rail row, so
        # the click only has to hand the list to QML.
        self._prefetch = {}
        self._pf_gen = {}
        self._pf_busy = set()
        self._pf_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="chat-prefetch")
        self._pending = []
        self._reading = set()          # source keys still being digested
        self._failed = {}              # key -> error

        self._busy = False
        self._phase = "idle"           # idle | thinking | streaming
        self._steps = []
        self._step_idx = 0
        self._stream_raw = ""
        self._stream_md = ""
        self._stream_cards = False
        self._run_id = 0
        self._run_tid = 0
        self._stop = threading.Event()
        self._resp = None
        self._resp_lock = threading.Lock()
        self._auto_title = {}          # tid -> the title we generated from text

        self._picker_kind = ""
        self._picker_rows_raw = []
        self._picker_rows = []
        self._picker_groups = []
        self._picker_group = 0
        self._picker_query = ""
        # v3.15 picker filters. Kept for the session (not reset on open), so a
        # creator who only ever wants Shorts with transcripts sets it once.
        self._picker_sort = "mult"         # mult | views | new | long
        self._picker_format = "all"        # all | short | long
        self._picker_tx_only = False
        self._picker_total = 0

        self._queued_pending = []      # v3.49: keys added in a batch, chipped once
        self._digest_futures = {}      # v3.49: key -> Future[str] of an in-flight digest
        self._brief_choices = []       # v3.49: saved Niche Scan briefs for the picker
        self._links_busy = False       # v3.49: a batch of YouTube links is being fetched

        self._drive_busy = False
        self._drive_status = ""
        self._drive_files = []
        self._drive_stop = threading.Event()

        self._flush = QTimer(self)
        self._flush.setSingleShot(True)
        self._flush.setInterval(45)
        self._flush.timeout.connect(self._flush_stream)

        self._delta.connect(self._on_delta)
        self._step.connect(self._on_step)
        self._turnDone.connect(self._on_turn_done)
        self._sourceDone.connect(self._on_source_done)
        self._sourceAdd.connect(self._on_source_add)
        self._sourcesAdd.connect(self._on_sources_add)
        self._driveDone.connect(self._on_drive_done)
        self._titleDone.connect(self._on_title_done)
        self._prefetched.connect(self._on_prefetched)
        self._openUrl.connect(lambda u: QDesktopServices.openUrl(QUrl(u)))

        self.refreshThreads()
        if self._threads:
            self.openThread(self._threads[0]["id"])

    # ═════════════════════════════════════════════════════════════════
    #  AI provider (same config shape as Insights / Ideas / Content Lab)
    # ═════════════════════════════════════════════════════════════════
    def _reload_ai_config(self):
        # The provider / model / effort Settings routes "chat" to (AI routing),
        # falling back to the active provider — see app.core.ai.profiles.
        cfg = load_app_config()
        r = resolve_ai_route("chat", cfg)
        self._ai_route = r
        self._ai_provider = r["provider"]
        self._ai_key = r["api_key"]
        self._ai_model = r["model"]
        self._ai_base = r["base_url"]
        self._ai_path = r["path"]
        self._ai_name = r["custom_name"]
        self._ai_proxy = r["proxy"]
        self._ai_mode = api_mode_for(self._ai_provider, r["api_mode"] or None)
        self._ai_effort = r["effort"]
        self._yt_key = ""
        keys = [k for k in (cfg.get("youtube_api_keys") or []) if k]
        if keys:
            self._yt_key = str(keys[0]).strip()
        elif cfg.get("api_key"):
            self._yt_key = str(cfg.get("api_key")).strip()

    def _make_client(self):
        return AIClient(self._ai_provider, self._ai_key, self._ai_model,
                        base_url=self._ai_base, proxy=self._ai_proxy,
                        path=self._ai_path, custom_name=self._ai_name,
                        api_mode=self._ai_mode,
                        effort=self._ai_effort)

    @Slot()
    def reloadConfig(self):
        self._reload_ai_config()
        self.configChanged.emit()
        self.driveChanged.emit()

    @Slot()
    def retranslate(self):
        self.labelsChanged.emit()
        self.refreshThreads()
        self._reload_sources()
        self._reload_messages(scroll=False)
        self.configChanged.emit()

    @Property(bool, notify=configChanged)
    def hasAiKey(self):
        return bool(self._ai_key)

    @Property(str, notify=configChanged)
    def providerLabel(self):
        try:
            return self._make_client().label
        except Exception:
            return self._ai_provider

    @Property(str, notify=configChanged)
    def providerKey(self):
        return self._ai_provider

    @Property(str, notify=configChanged)
    def modelName(self):
        return self._ai_model or AI_PROVIDER_DEFAULT_MODEL.get(self._ai_provider, "") \
            or tr("No model set")

    # ── effort + provider pick for the chat (the composer's model chip) ──
    # Same values Settings → AI routing → "AI Chat" holds; changing them here
    # writes straight to that route, so both places always agree.
    @Property(str, notify=configChanged)
    def effort(self):
        return self._ai_effort

    @Property("QVariantList", notify=labelsChanged)
    def effortOptions(self):
        return [{"value": v, "label": tr(EFFORT_LABELS[v]), "hint": tr(EFFORT_HINTS[v])}
                for v in EFFORT_LEVELS]

    @Slot(str)
    def setEffort(self, value):
        update_ai_route("chat", "effort", value)
        self._reload_ai_config()
        self.configChanged.emit()

    @Property("QVariantList", notify=configChanged)
    def profileChoices(self):
        """Every saved provider, for the "which AI answers here" list."""
        state = load_ai_state(load_app_config())
        route = state["routes"].get("chat", {})
        out = [{"id": "", "label": tr("Default provider"),
                "sub": (find_ai_profile(state, state["active"]) or {}).get("name", ""),
                "current": not route.get("profile")}]
        for p in state["profiles"]:
            ready = bool(p["api_key"]) or (p["kind"] == "custom" and bool(p["base_url"]))
            if not ready:
                continue
            out.append({"id": p["id"], "label": p["name"],
                        "sub": effective_ai_model(p) or tr("No model set"),
                        "kind": p["kind"],
                        "current": route.get("profile") == p["id"]})
        return out

    @Slot(str)
    def setProfile(self, pid):
        update_ai_route("chat", "profile", pid)
        self._reload_ai_config()
        self.configChanged.emit()

    # ── every saved provider's models, for the composer's model list ──
    # A custom provider added in Settings appears here as soon as it has a
    # host (custom) or a key (built-in); its fetched model catalogue — or just
    # its own model when nothing was fetched — becomes pickable rows.
    _GLYPHS = {"openai": "provider_openai", "anthropic": "provider_anthropic",
               "gemini": "provider_gemini"}

    @Property("QVariantList", notify=configChanged)
    def modelGroups(self):
        try:
            state = load_ai_state(load_app_config())
        except Exception:
            return []
        route = state["routes"].get("chat", {})
        r_pid = route.get("profile") or ""
        r_model = route.get("model") or ""
        act = find_ai_profile(state, state["active"]) or {}
        # a pinned model that was since removed from its provider in Settings
        # isn't pinned any more (resolve() falls back the same way)
        pinned = find_ai_profile(state, r_pid) if r_pid else None
        if r_model and pinned is not None:
            allowed = list(pinned.get("picked") or []) or [effective_ai_model(pinned)]
            if r_model not in allowed:
                r_model = ""
        out = []
        for p in state["profiles"]:
            custom = p["kind"] == "custom"
            ready = bool(p["base_url"]) if custom else bool(p["api_key"])
            if not ready:
                continue
            eff = effective_ai_model(p)
            # v3.16-p3: only the models the user ADDED to this provider in
            # Settings (or just its own model when none were added) — never
            # the whole fetched catalogue.
            models = list(p.get("picked") or [])
            if not models and eff:
                models = [eff]
            models = list(dict.fromkeys(m for m in models if m))
            # which row is "on": a pinned route, else the default profile's model
            if r_pid:
                on_pid, on_model = r_pid, (r_model or eff)
            else:
                on_pid, on_model = act.get("id", ""), effective_ai_model(act) if act else ""
            out.append({
                "id": p["id"],
                "name": p["name"],
                "kind": p["kind"],
                "glyph": self._GLYPHS.get(p["kind"], "provider_custom"),
                "isDefault": p["id"] == state["active"],
                "isCurrent": p["id"] == on_pid,
                "models": [{"id": m, "current": p["id"] == on_pid and m == on_model,
                            "isOwn": m == eff} for m in models],
            })
        return out

    @Property(bool, notify=configChanged)
    def followsDefault(self):
        try:
            return not load_ai_state(load_app_config())["routes"].get("chat", {}).get("profile")
        except Exception:
            return True

    @Slot(str, str)
    def pickModel(self, pid, model):
        """Answer this chat with `model` on provider `pid` ("" = follow the
        default provider from Settings)."""
        set_ai_route_target("chat", pid, model)
        self._reload_ai_config()
        self.configChanged.emit()

    # ═════════════════════════════════════════════════════════════════
    #  Threads
    # ═════════════════════════════════════════════════════════════════
    @Property("QVariantList", notify=threadsChanged)
    def threads(self):
        return self._threads

    @Property(str, notify=threadsChanged)
    def search(self):
        return self._search

    @search.setter
    def search(self, v):
        v = v or ""
        if v != self._search:
            self._search = v
            self.refreshThreads()

    @Property(int, notify=threadChanged)
    def threadId(self):
        return self._tid

    @Property(str, notify=threadChanged)
    def threadTitle(self):
        return self._title or tr("New chat")

    @Property(bool, notify=threadChanged)
    def threadPinned(self):
        return self._pinned

    @Slot()
    def refreshThreads(self):
        out = []
        for t in chat_list_threads(self._search):
            group, when = _when(t.get("updated_at"))
            if t.get("pinned"):
                group = "pinned"
            out.append({
                "id": int(t["id"]),
                "title": t.get("title") or tr("New chat"),
                "pinned": bool(t.get("pinned")),
                "group": group,
                "when": when,
                "msgCount": int(t.get("msg_count") or 0),
                "srcCount": int(t.get("src_count") or 0),
                "live": self._busy and int(t["id"]) == self._run_tid,
            })
        self._threads = out
        self.threadsChanged.emit()

    def _set_thread(self, tid):
        t = chat_get_thread(tid) if tid else None
        self._tid = int(t["id"]) if t else 0
        self._title = (t or {}).get("title") or ""
        self._pinned = bool((t or {}).get("pinned"))
        self.threadChanged.emit()

    def _ensure_thread(self):
        if self._tid and chat_get_thread(self._tid):
            return self._tid
        tid = chat_create_thread(tr("New chat"))
        self._set_thread(tid)
        self.refreshThreads()
        return tid

    @Slot()
    def newThread(self):
        """Open an empty composer. The row itself is created lazily — on the
        first message or the first attached source — so clicking New chat five
        times doesn't leave five empty conversations behind."""
        if self._busy:
            self.stop()
        # An untouched empty thread is reused rather than stacked.
        if self._tid and not self._messages and not self._sources:
            self._pending = []
            self.pendingChanged.emit()
            return
        self._set_thread(0)
        self._messages, self._sources, self._pending = [], [], []
        self.messagesChanged.emit()
        self.sourcesChanged.emit()
        self.pendingChanged.emit()

    @Slot(int)
    def openThread(self, tid):
        if int(tid) == self._tid and self._messages:
            return
        if self._busy and int(tid) != self._run_tid:
            self.stop()
        tid = int(tid)
        stopped = self._busy and tid != self._run_tid
        # v3.40.7: use the copy the hover prefetch built, if it is still exact
        snap = self._prefetch.pop(tid, None)
        if snap is not None and snap[0] != chat_thread_signature(tid):
            snap = None
        self._set_thread(tid)
        self._pending = []
        self.pendingChanged.emit()
        # v3.40.4: opening a chat changes nothing in the rail, so don't rebuild
        # every rail row (refreshThreads), and read the sources table once
        # instead of twice (the messages reuse its titles).
        if snap is not None:
            self._reload_sources(refresh=stopped, raw=snap[1])
            self._messages = snap[2]
            self.messagesChanged.emit()
        else:
            self._reload_sources(refresh=stopped)
            self._reload_messages(scroll=False, titles=self._src_titles)

    # ── v3.40.7: hover prefetch ──
    def _drop_prefetch(self, tid=None):
        tid = self._tid if tid is None else int(tid)
        self._prefetch.pop(tid, None)
        self._pf_gen[tid] = self._pf_gen.get(tid, 0) + 1

    @Slot(int)
    def prefetchThread(self, tid):
        """Build a chat's messages in the background while the pointer rests
        on its rail row. Cheap to call repeatedly: one build per chat, max."""
        tid = int(tid)
        if tid <= 0 or tid == self._tid or tid in self._prefetch or tid in self._pf_busy:
            return
        self._pf_busy.add(tid)
        gen = self._pf_gen.get(tid, 0)
        self._pf_pool.submit(self._prefetch_worker, tid, gen)

    def _prefetch_worker(self, tid, gen):
        try:
            sig = chat_thread_signature(tid)
            raw = chat_sources(tid)
            titles = {x.get("key"): (x.get("title") or "") for x in raw}
            msgs = self._build_messages(tid, titles)
            self._prefetched.emit(tid, gen, [sig, raw, msgs])
        except Exception:
            log_crash("chat prefetch:\n" + traceback.format_exc())
            self._prefetched.emit(tid, -1, None)

    def _on_prefetched(self, tid, gen, snap):
        self._pf_busy.discard(tid)
        if snap is None or gen != self._pf_gen.get(tid, 0) or tid == self._tid:
            return
        sig, raw, msgs = snap
        if sig is None:
            return
        self._prefetch[tid] = (tuple(sig), raw, msgs)
        # keep only the last few hovered chats
        while len(self._prefetch) > 6:
            self._prefetch.pop(next(iter(self._prefetch)))

    @Slot(int, str)
    def renameThread(self, tid, title):
        title = " ".join((title or "").split())[:120]
        if not title:
            return
        chat_rename_thread(int(tid), title)
        self._auto_title.pop(int(tid), None)
        if int(tid) == self._tid:
            self._title = title
            self.threadChanged.emit()
        self.refreshThreads()

    @Slot(int, bool)
    def pinThread(self, tid, pinned):
        chat_pin_thread(int(tid), bool(pinned))
        if int(tid) == self._tid:
            self._pinned = bool(pinned)
            self.threadChanged.emit()
        self.refreshThreads()

    @Slot(int)
    def deleteThread(self, tid):
        tid = int(tid)
        self._drop_prefetch(tid)
        if self._busy and tid == self._run_tid:
            self.stop()
        chat_delete_thread(tid)
        self.refreshThreads()
        if tid == self._tid:
            nxt = self._threads[0]["id"] if self._threads else 0
            self._tid = -1      # force a reload in openThread
            if nxt:
                self.openThread(nxt)
            else:
                self._set_thread(0)
                self._messages, self._sources, self._pending = [], [], []
                self.messagesChanged.emit()
                self.sourcesChanged.emit()
                self.pendingChanged.emit()
        self.toast.emit(tr("Conversation deleted."), "success")

    @Slot()
    def deleteAllThreads(self):
        if self._busy:
            self.stop()
        chat_delete_all()
        self._prefetch.clear()
        self._pf_gen = {k: v + 1 for k, v in self._pf_gen.items()}
        self._set_thread(0)
        self._messages, self._sources, self._pending = [], [], []
        self.messagesChanged.emit()
        self.sourcesChanged.emit()
        self.pendingChanged.emit()
        self.refreshThreads()
        self.toast.emit(tr("All conversations deleted."), "success")

    @Slot(str)
    def exportThread(self, file_url):
        if not self._tid:
            return
        path = local_path_from_url(file_url)
        if not path:
            return
        if not path.lower().endswith(".md"):
            path += ".md"
        lines = ["# " + (self._title or tr("New chat")), ""]
        if self._sources:
            lines.append("## " + tr("Sources"))
            for s in self._sources:
                lines.append(f"- {s['title']}" + (f" — {s['subtitle']}" if s.get("subtitle") else ""))
            lines.append("")
        for m in self._messages:
            who = tr("You") if m["role"] == "user" else "Hunter"
            lines.append(f"### {who} · {m.get('time', '')}")
            if m["role"] == "user":
                for a in m.get("attachments") or []:
                    lines.append(f"> 📎 {a.get('title', '')}")
                lines.append(m.get("text") or "")
            else:
                lines.append(parts_to_markdown(m.get("parts")))
            lines.append("")
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            self.toast.emit(tr("Conversation exported."), "success")
        except OSError as e:
            self.toast.emit(tr("Export failed: {err}").format(err=e), "error")

    # ═════════════════════════════════════════════════════════════════
    #  Messages
    # ═════════════════════════════════════════════════════════════════
    @Property("QVariantList", notify=messagesChanged)
    def messages(self):
        return self._messages

    @Property(bool, notify=messagesChanged)
    def hasMessages(self):
        return bool(self._messages)

    def _reload_messages(self, scroll=True, titles=None):
        self._drop_prefetch()
        if titles is None:
            titles = {s.get("key"): (s.get("title") or "")
                      for s in (chat_sources(self._tid) if self._tid else [])}
        self._messages = self._build_messages(self._tid, titles)
        self.messagesChanged.emit()
        if scroll:
            self.scrollToEnd.emit()

    def _build_messages(self, tid, titles):
        """Pure: DB rows -> the list QML binds. Safe on a worker thread."""
        out = []
        for m in (chat_messages(tid) if tid else []):
            role = "assistant" if m.get("role") == "assistant" else "user"
            err = m.get("error") or ""
            stopped = err == _STOPPED
            atts = []
            for a in m.get("attachments") or []:
                if isinstance(a, dict):
                    a = dict(a)
                    a["thumbSrc"] = _thumb_src(a)
                    atts.append(a)
            out.append({
                "id": int(m["id"]),
                "role": role,
                "text": m.get("text") or "",
                "parts": (self._label_parts(split_parts(m.get("text") or ""), titles)
                          if role == "assistant" else []),
                "attachments": atts,
                "error": "" if stopped else err,
                "stopped": stopped,
                "model": m.get("model") or "",
                "time": str(m.get("created_at") or "")[11:16],
            })
        return out

    @staticmethod
    def _label_parts(parts, titles):
        """Give every idea card the titles of the sources it was built on, so
        the card can say what it rests on (and the user can see that Build in
        AI Ideas will carry exactly those videos)."""
        for p in parts:
            if p.get("type") != "ideas":
                continue
            for it in p.get("items") or []:
                it["refTitles"] = [titles[k] for k in it.get("src_keys") or [] if titles.get(k)]
        return parts

    @Slot(int)
    def copyMessage(self, mid):
        for m in self._messages:
            if m["id"] == int(mid):
                text = parts_to_markdown(m["parts"]) if m["role"] == "assistant" else m["text"]
                self.copyText(text)
                return

    @Slot(str)
    def copyText(self, text):
        try:
            QGuiApplication.clipboard().setText(text or "")
            self.toast.emit(tr("Copied."), "success")
        except Exception:
            pass

    @Slot("QVariant", result=str)
    def ideaAsBrief(self, item):
        """One idea card as plain text (Copy) and as the brief AI Ideas gets."""
        it = dict(item or {})
        bits = [it.get("title", "")]
        if it.get("concept"):
            bits.append(tr("Concept") + ": " + it["concept"])
        if it.get("hook"):
            bits.append(tr("Hook") + ": " + it["hook"])
        if it.get("why"):
            bits.append(tr("Why it works") + ": " + it["why"])
        if it.get("format"):
            bits.append(tr("Format") + ": " + it["format"])
        return "\n".join(b for b in bits if b)

    @Slot("QVariant", result="QVariant")
    def ideaHandoff(self, item):
        """Everything AI Ideas needs to build THIS idea properly — not just its
        text. The old hand-off sent the title alone in "My idea only" mode, so
        the blueprint model never saw a single number or transcript line and
        drifted off into something unrelated. Now it carries:

          rows        the video sources the idea was built on (its `refs`); when
                      the model cited none, every video in the conversation
          csvPaths    attached exports the idea rests on (or all of them)
          format      "short" / "long" read off the card's format, or ""
          seedContext the digests of those sources (real stats + transcript
                      openings) and what the creator told the chat about their
                      channel — so the blueprint quotes reality instead of
                      inventing it."""
        it = dict(item or {})
        srcs = chat_sources(self._tid) if self._tid else []
        want = [k for k in (it.get("src_keys") or []) if k]
        picked = [s for s in srcs if s.get("key") in want] if want else []
        if not picked:
            picked = list(srcs)
        rows, csv_paths, digests = [], [], []
        for s in picked:
            kind = s.get("kind")
            if kind == "video":
                row = dict(s.get("row") or {})
                vid = str(row.get("video_id") or "")
                if vid and not row.get("video_url"):
                    row["video_url"] = f"https://www.youtube.com/watch?v={vid}"
                if row.get("duration_s") and "is_short" not in row:
                    # same 3-minute rule as everywhere else (was <= 60 s)
                    row["is_short"] = _is_short(row)
                if row.get("title"):
                    rows.append(row)
            elif kind == "table":
                p = s.get("path") or ""
                if os.path.splitext(p)[1].lower() in (".csv", ".xlsx", ".jsonl", ".db") \
                        and os.path.isfile(p):
                    csv_paths.append(p)
            d = (s.get("_digest") or "").strip()
            if d and kind in ("video", "text", "doc"):
                digests.append(d[:3200])
        ctx = []
        if digests:
            ctx.append("SOURCE DATA THIS IDEA WAS BUILT FROM (real — quote only from here):\n"
                       + "\n\n".join(digests[:4]))
        said = [(m.get("text") or "").strip() for m in (chat_messages(self._tid) if self._tid else [])
                if m.get("role") == "user"]
        said = [t for t in said if t][-4:]
        if said:
            ctx.append("WHAT THE CREATOR TOLD THE CHAT (their channel, goals, constraints):\n"
                       + "\n".join("- " + t[:500] for t in said))
        fmt = str(it.get("format") or "").lower()
        if re.search(r"short|shorts|شورت|کوتاه|ثانیه|\bsec|\b\d+\s*s\b", fmt):
            fmt_key = "short"
        elif re.search(r"long|بلند|min|دقیقه", fmt):
            fmt_key = "long"
        else:
            fmt_key = ""
        return {
            "brief": self.ideaAsBrief(it),
            "title": it.get("title", ""),
            "rows": rows,
            "csvPaths": csv_paths,
            "format": fmt_key,
            "seedContext": "\n\n".join(ctx)[:14000],
        }

    # ═════════════════════════════════════════════════════════════════
    #  Sources + pending chips
    # ═════════════════════════════════════════════════════════════════
    @Property("QVariantList", notify=sourcesChanged)
    def sources(self):
        return self._sources

    @Property(bool, notify=sourcesChanged)
    def sourcesReading(self):
        return any(s.get("status") == "reading" for s in self._sources)

    @Property("QVariantList", notify=pendingChanged)
    def pending(self):
        return self._pending

    @Property(str, constant=True)
    def fileFilter(self):
        return " ".join("*" + e for e in ALL_EXTS)

    def _ui_source(self, s):
        kind = s.get("kind") or "text"
        row = s.get("row") or {}
        dig = s.get("_digest") or ""
        key = s.get("key")
        if key in self._reading:
            status = "reading"
        elif key in self._failed:
            status = "error"
        elif kind == "video" and "transcript: not available" in dig:
            status = "nocap"
        elif dig:
            status = "ready"
        else:
            status = "reading" if kind != "image" else "ready"
        text = {
            "reading": (tr("Reading transcript…") if kind == "video"
                        else tr("Reading the brief…") if kind == "brief"
                        else tr("Summarising…")),
            "error": self._failed.get(key, tr("Could not be read")),
            "nocap": tr("No transcript available"),
            "ready": (tr("Transcript read") if kind == "video"
                      else tr("Ready for vision") if kind == "image"
                      else tr("Brief ready") if kind == "brief"
                      else tr("Summary ready")),
        }[status]
        mult = _mult_of(row) if kind == "video" else 0.0
        origin_label = {
            "niche": tr("Niche Finder"), "archive": tr("Search Archive"),
            "link": tr("Link"), "file": tr("File"), "drive": "Google Drive",
            "export": tr("Export"), "brief": tr("Brief"),
        }.get(s.get("origin") or "", "")
        chars = len(dig) if dig else (120 if kind == "image" else 0)
        return {
            "key": key,
            "kind": kind,
            "title": s.get("title") or tr("Untitled"),
            "subtitle": s.get("subtitle") or "",
            "thumb": s.get("thumb") or "",
            "thumbSrc": _thumb_src(s),
            "path": s.get("path") or "",
            "origin": s.get("origin") or "",
            "originLabel": origin_label,
            "status": status,
            "statusText": text,
            "chars": chars,
            "mult": mult,
            "multLabel": format_multiplier(mult) if mult else "",
            "dur": mmss(row.get("duration_s")) if row.get("duration_s") else "",
        }

    def _reload_sources(self, refresh=True, raw=None):
        if raw is None:
            self._drop_prefetch()
            raw = chat_sources(self._tid) if self._tid else []
        self._src_titles = {s.get("key"): (s.get("title") or "") for s in raw}
        # A source left undigested (the app closed mid-read) is picked up again.
        for s in raw:
            k = s.get("key")
            if (not s.get("_digest") and s.get("kind") != "image"
                    and k not in self._reading and k not in self._failed):
                self._submit_digest(self._tid, dict(s))
        self._sources = [self._ui_source(s) for s in raw]
        # Pending chips mirror their source's live status.
        by_key = {s["key"]: s for s in self._sources}
        if self._pending:
            self._pending = [by_key.get(p["key"], p) for p in self._pending if p["key"] in by_key]
            self.pendingChanged.emit()
        self.sourcesChanged.emit()
        if refresh:
            self.refreshThreads()

    def _add_source(self, src, tid=None, quiet=False, reload=True):
        """Attach one source dict to the open thread and digest it in the
        background. Returns False for a duplicate.

        v3.49: `reload=False` lets a batch (several YouTube links, several
        briefs) attach everything first and rebuild the source list ONCE —
        the old per-item reload re-read the thread's sources from SQLite and
        re-emitted the whole list for every single link."""
        tid = tid or self._ensure_thread()
        if any(s["key"] == src["key"] for s in chat_sources(tid)):
            if not quiet:
                self.toast.emit(tr("That's already in this conversation."), "info")
            return False
        chat_add_source(tid, src, "")
        self._failed.pop(src["key"], None)
        if src.get("kind") != "image":
            self._submit_digest(tid, dict(src))
        if tid == self._tid:
            self._queued_pending = self._queued_pending + [src["key"]]
            if reload:
                self._flush_added()
        return True

    def _flush_added(self):
        """Rebuild the source list once and put every newly added source on
        the composer as a pending chip."""
        keys = set(self._queued_pending)
        self._queued_pending = []
        self._reload_sources()
        have = {p["key"] for p in self._pending}
        add = [s for s in self._sources if s["key"] in keys and s["key"] not in have]
        if add:
            self._pending = self._pending + add
            self.pendingChanged.emit()

    def _submit_digest(self, tid, src):
        """Digest on the shared bounded pool (4 workers). The Future is kept so
        a turn sent while a source is still being read WAITS for that read
        instead of fetching the same transcript a second time."""
        key = src.get("key")
        if key in self._digest_futures and not self._digest_futures[key].done():
            return
        self._reading.add(key)
        fut = _DIGEST_POOL.submit(self._digest_worker, tid, src)
        self._digest_futures[key] = fut

    def _digest_worker(self, tid, src):
        try:
            d = digest(src, fetch_transcripts=True)
            self._sourceDone.emit(tid, src["key"], d or "", "")
            return d or ""
        except Exception as e:      # noqa: BLE001
            log_crash("chat digest:\n" + traceback.format_exc())
            self._sourceDone.emit(tid, src["key"], "", str(e))
            return ""

    @Slot(int, str, str, str)
    def _on_source_done(self, tid, key, dig, error):
        self._drop_prefetch(tid)
        self._reading.discard(key)
        fut = self._digest_futures.get(key)
        if fut is not None and fut.done():
            self._digest_futures.pop(key, None)
        if error:
            self._failed[key] = error
        elif dig:
            chat_set_source_digest(tid, key, dig)
        if tid == self._tid:
            self._reload_sources()

    @Slot(str)
    def removeSource(self, key):
        if not self._tid:
            return
        chat_remove_source(self._tid, key)
        self._reading.discard(key)
        self._pending = [p for p in self._pending if p["key"] != key]
        self.pendingChanged.emit()
        self._reload_sources()

    @Slot(str)
    def removePending(self, key):
        """A chip removed before sending was never used — drop it from the
        conversation too, so the composer never sends what the user dropped."""
        self.removeSource(key)

    # ── files ──
    @Slot("QVariantList")
    def addFiles(self, urls):
        added = 0
        for u in list(urls or [])[:12]:
            path = local_path_from_url(str(u))
            try:
                probe = file_source(path)
            except ValueError as e:
                self.toast.emit(f"{os.path.basename(path or '')}: {e}", "error")
                continue
            stored = chat_store_file(path)
            src = dict(probe)
            src["path"] = stored
            if src["kind"] == "image":
                src["thumb"] = stored
            src["origin"] = "export" if os.path.basename(path).lower().startswith(
                ("niche_", "export", "scrape")) and src["kind"] == "table" else "file"
            if self._add_source(src):
                added += 1
        if added:
            self.toast.emit(tr("{n} file(s) added to the conversation.").format(n=added), "success")

    @Slot(str)
    def addFile(self, url):
        self.addFiles([url])

    # ── links (YouTube videos — one or a whole batch — or a Drive share link) ──
    _MAX_LINKS = 50

    @staticmethod
    def _split_links(text):
        """Every distinct YouTube video id in a pasted blob (one per line,
        comma / space separated, or mixed with other text), in paste order,
        plus any Google Drive links."""
        ids, drive = [], []
        for tok in re.split(r"[\s,;|]+", text or ""):
            tok = tok.strip().strip("<>()[]{}\"'")
            if not tok:
                continue
            if gdrive.is_drive_link(tok):
                drive.append(tok)
                continue
            if ("/" not in tok and "." not in tok and len(tok) == 11
                    and not re.search(r"[0-9_-]", tok)
                    and (tok.islower() or tok.isupper())):
                continue        # an ordinary 11-letter word, not a video id
            vid = extract_video_id(tok)
            if vid and vid not in ids:
                ids.append(vid)
        return ids, drive

    @Slot(str, result=int)
    def countLinks(self, text):
        """Live counter for the link sheet ("Add 7 videos")."""
        ids, drive = self._split_links(text)
        return min(len(ids), self._MAX_LINKS) + len(drive)

    @Property(bool, notify=sourcesChanged)
    def linksBusy(self):
        return self._links_busy

    @Slot(str)
    def addLink(self, text):
        self.addLinks(text)

    @Slot(str)
    def addLinks(self, text):
        text = (text or "").strip()
        if not text:
            return
        tid = self._ensure_thread()
        ids, drive = self._split_links(text)
        if not ids and not drive and gdrive.is_drive_link(text):
            drive = [text]
        for d in drive[:3]:
            self._set_drive_busy(True, tr("Downloading from Google Drive…"))
            threading.Thread(target=self._drive_link_worker, args=(tid, d),
                             daemon=True, name="chat-drive-link").start()
        if not ids:
            if not drive:
                self.toast.emit(tr("Paste one or more YouTube video links."), "error")
            return
        if len(ids) > self._MAX_LINKS:
            self.toast.emit(tr("Only the first {n} links are added.").format(n=self._MAX_LINKS), "info")
            ids = ids[:self._MAX_LINKS]
        have = {s.get("key") for s in chat_sources(tid)}
        fresh = [v for v in ids if "video:" + v not in have]
        if not fresh:
            self.toast.emit(tr("Those videos are already in this conversation."), "info")
            return
        self._links_busy = True
        self.sourcesChanged.emit()
        self.toast.emit(tr("Fetching {n} video(s)…").format(n=len(fresh)) if len(fresh) > 1
                        else tr("Fetching the video…"), "info")
        threading.Thread(target=self._links_worker, args=(tid, fresh), daemon=True,
                         name="chat-links").start()

    def _links_worker(self, tid, vids):
        """One batch for any number of links.

        oEmbed (free, no key) runs 6 at a time instead of one after another,
        and with a YouTube key the exact stats come from ONE videos.list and
        ONE channels.list call for the whole batch (both take 50 ids), so 30
        links cost the same 2 quota units a single link used to."""
        from app.core.net import fetch_youtube_oembed
        rows = {v: {"video_id": v} for v in vids}

        def oembed(v):
            try:
                return v, fetch_youtube_oembed(v, proxy=self._ai_proxy or None) or {}
            except Exception:
                return v, {}
        try:
            with ThreadPoolExecutor(max_workers=min(6, len(vids)),
                                    thread_name_prefix="chat-oembed") as pool:
                for v, meta in pool.map(oembed, vids):
                    rows[v].update({k: val for k, val in meta.items() if val})
            if self._yt_key:
                try:
                    from app.core.niche.search import (enrich_channels,
                                                       enrich_videos,
                                                       merge_niche_row)
                    from app.core.youtube_api import build_youtube_service
                    yt = build_youtube_service(self._yt_key)
                    vmap = enrich_videos(yt, vids)
                    cids = [((vmap.get(v) or {}).get("snippet") or {}).get("channelId")
                            for v in vids]
                    cmap = enrich_channels(yt, [c for c in cids if c]) if any(cids) else {}
                    for v, cid in zip(vids, cids):
                        item = vmap.get(v)
                        if not item:
                            continue
                        row = merge_niche_row(rows[v], item, cmap.get(cid) if cid else None)
                        subs = row.get("subscriber_count") or 0
                        if subs and not row.get("subs_hidden"):
                            row["multiplier"] = (row.get("view_count") or 0) / float(subs)
                        rows[v] = row
                except Exception:
                    log_crash("chat links enrich:\n" + traceback.format_exc())
            ok = [video_source(rows[v], "link") for v in vids if rows[v].get("title")]
            self._sourcesAdd.emit(tid, ok, len(vids) - len(ok))
        except Exception as e:      # noqa: BLE001
            log_crash("chat links:\n" + traceback.format_exc())
            self._sourcesAdd.emit(tid, [], len(vids))

    @Slot(int, "QVariant", int)
    def _on_sources_add(self, tid, srcs, failed):
        self._drop_prefetch(tid)
        self._links_busy = False
        added = 0
        for src in list(srcs or []):
            if self._add_source(dict(src), tid=tid, quiet=True, reload=False):
                added += 1
        if tid == self._tid:
            self._flush_added()
        else:
            self.sourcesChanged.emit()
        if added and failed:
            self.toast.emit(tr("{n} video(s) added · {f} couldn't be read (private or removed?).")
                            .format(n=added, f=failed), "info")
        elif added:
            self.toast.emit(tr("{n} video(s) added to the conversation.").format(n=added)
                            if added > 1 else tr("Added to the conversation."), "success")
        elif failed:
            self.toast.emit(tr("Couldn't read those videos. Are they public?"), "error")

    # ── briefs (v3.49): saved Niche Scan research, or a brief the user wrote ──
    @Property("QVariantList", notify=briefsChanged)
    def briefChoices(self):
        return self._brief_choices

    @Slot()
    def openBriefPicker(self):
        """Reload the saved Niche Scan snapshots (metadata only, one light
        query) and mark the ones already in this conversation."""
        try:
            records = insights_list(40)
        except Exception:
            records = []
        have = {s.get("key") for s in chat_sources(self._tid)} if self._tid else set()
        out = []
        for r in records:
            key = r.get("snapshot_key") or ""
            if not key:
                continue
            group, when = _when(r.get("created_at"))
            out.append({
                "key": key,
                "query": r.get("query") or tr("Untitled"),
                "videos": int(r.get("total_videos") or 0),
                "hasBrief": bool(r.get("has_brief")),
                "kind": tr("RESEARCH") if r.get("has_brief") else tr("DATA"),
                "when": when,
                "mode": r.get("mode") or "keyword",
                "added": ("brief:" + key) in have,
            })
        self._brief_choices = out
        self.briefsChanged.emit()

    @Slot("QVariantList")
    def addBriefs(self, keys):
        tid = self._ensure_thread()
        by_key = {c["key"]: c for c in self._brief_choices}
        added = 0
        for k in list(keys or []):
            c = by_key.get(str(k))
            if not c:
                continue
            src = brief_source(c["key"], c["query"], c["videos"], c["hasBrief"])
            if self._add_source(src, tid=tid, quiet=True, reload=False):
                added += 1
        if tid == self._tid:
            self._flush_added()
        if added:
            self.toast.emit(tr("{n} brief(s) added. Ask Hunter to analyse them.").format(n=added),
                            "success")

    @Slot(str, str)
    def addWrittenBrief(self, title, text):
        """A brief pasted into the sheet (a client's brief, a sponsor's, your
        own plan) is saved as a small .md file next to the other chat files,
        so it survives a restart and digests like any other source."""
        text = (text or "").strip()
        if not text:
            return
        title = " ".join((title or "").split())[:80] or title_for(text)[:60] or tr("My brief")
        try:
            os.makedirs(CHAT_FILES_DIR, exist_ok=True)
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            path = os.path.join(CHAT_FILES_DIR, f"brief-{stamp}.md")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        except OSError as e:
            self.toast.emit(tr("Couldn't save the brief: {e}").format(e=e), "error")
            return
        if self._add_source(written_brief_source(path, title)):
            self.toast.emit(tr("Brief added. Ask Hunter to analyse it."), "success")

    @Slot(int, "QVariant", str)
    def _on_source_add(self, tid, src, error):
        self._drop_prefetch(tid)
        self._set_drive_busy(False, "")
        if error or not src:
            self.toast.emit(error or tr("Couldn't add that."), "error")
            return
        if self._add_source(dict(src), tid=tid):
            self.toast.emit(tr("Added to the conversation."), "success")

    # ── Niche Finder / Archive picker ──
    @Property(str, notify=pickerChanged)
    def pickerKind(self):
        return self._picker_kind

    @Property("QVariantList", notify=pickerChanged)
    def pickerRows(self):
        return self._picker_rows

    @Property("QVariantList", notify=pickerChanged)
    def pickerGroups(self):
        return self._picker_groups

    @Property(int, notify=pickerChanged)
    def pickerGroup(self):
        return self._picker_group

    @Property(str, notify=pickerChanged)
    def pickerSort(self):
        return self._picker_sort

    @Property(str, notify=pickerChanged)
    def pickerFormat(self):
        return self._picker_format

    @Property(bool, notify=pickerChanged)
    def pickerTranscriptOnly(self):
        return self._picker_tx_only

    @Property(int, notify=pickerChanged)
    def pickerTotal(self):
        """Rows in the open section before any filter — the "12 of 48" count."""
        return self._picker_total

    @Property(bool, notify=pickerChanged)
    def pickerFiltered(self):
        return (self._picker_format != "all" or self._picker_tx_only
                or bool(self._picker_query))

    @Slot(str)
    def setPickerSort(self, key):
        if key in ("mult", "views", "new", "long") and key != self._picker_sort:
            self._picker_sort = key
            self._rebuild_picker()

    @Slot(str)
    def setPickerFormat(self, key):
        if key in ("all", "short", "long") and key != self._picker_format:
            self._picker_format = key
            self._rebuild_picker()

    @Slot(bool)
    def setPickerTranscriptOnly(self, on):
        if bool(on) != self._picker_tx_only:
            self._picker_tx_only = bool(on)
            self._rebuild_picker()

    @Slot()
    def resetPickerFilters(self):
        self._picker_sort, self._picker_format, self._picker_tx_only = "mult", "all", False
        self._picker_query = ""
        self._rebuild_picker()

    @Slot(str)
    def openPicker(self, kind):
        self._picker_kind = kind
        self._picker_query = ""
        self._picker_groups = []
        self._picker_group = 0
        if kind == "archive":
            try:
                from app.core.db.archive import archive_list_groups_full
                groups = archive_list_groups_full()
            except Exception:
                groups = []
            self._picker_groups = [{"id": int(g["id"]), "title": g.get("title") or g.get("query") or "",
                                    "count": int(g.get("item_count") or 0)} for g in groups]
            if self._picker_groups:
                self.pickArchiveGroup(self._picker_groups[0]["id"])
                return
            self._picker_rows_raw = []
        else:
            pool = []
            if self._niche_vm is not None:
                pool = list(getattr(self._niche_vm, "_pool", None) or [])
                if not pool:
                    try:
                        pool = list(self._niche_vm.rows or [])
                    except Exception:
                        pool = []
            self._picker_rows_raw = sorted(pool, key=lambda r: -_mult_of(r))
        self._rebuild_picker()

    @Slot(int)
    def pickArchiveGroup(self, gid):
        try:
            from app.core.db.archive import archive_get_rows
            rows = archive_get_rows(int(gid))
        except Exception:
            rows = []
        self._picker_group = int(gid)
        self._picker_rows_raw = list(rows)      # sorted in _rebuild_picker
        self._rebuild_picker()

    @Slot(str)
    def filterPicker(self, q):
        self._picker_query = (q or "").strip().lower()
        self._rebuild_picker()

    def _rebuild_picker(self):
        have = {s["key"] for s in self._sources}
        out = []
        self._picker_total = len(self._picker_rows_raw)
        # `i` stays the index into _picker_rows_raw (addPicked reads it), so
        # the sort runs over (index, row) pairs rather than the rows.
        order = list(enumerate(self._picker_rows_raw))
        key = {
            "views": lambda p: -_num(p[1].get("view_count")),
            "new": lambda p: _published_key(p[1]),
            "long": lambda p: -_num(p[1].get("duration_s")),
        }.get(self._picker_sort, lambda p: -_mult_of(p[1]))
        order.sort(key=key, reverse=(self._picker_sort == "new"))
        for i, r in order:
            title = str(r.get("title") or "")
            chan = str(r.get("channel_title") or "")
            if self._picker_query and self._picker_query not in (title + " " + chan).lower():
                continue
            short = _is_short(r)
            if self._picker_format == "short" and not short:
                continue
            if self._picker_format == "long" and short:
                continue
            has_tx = _has_transcript(r)
            if self._picker_tx_only and not has_tx:
                continue
            vid = str(r.get("video_id") or "")
            mult = _mult_of(r)
            thumb = r.get("thumbnail_url") or (f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg" if vid else "")
            out.append({
                "i": i, "title": title, "channel": chan,
                "views": humanize_count(r.get("view_count") or 0),
                "mult": mult, "multLabel": format_multiplier(mult) if mult else "",
                "dur": mmss(r.get("duration_s")) if r.get("duration_s") else "",
                "thumbSrc": "image://thumbs/" + _b64(thumb) if thumb else "",
                "added": ("video:" + vid) in have,
                "isShort": short,
                "hasTranscript": has_tx,
                "published": _published_key(r)[:10],
            })
            if len(out) >= _PICKER_LIMIT:
                break
        self._picker_rows = out
        self.pickerChanged.emit()

    @Slot("QVariantList")
    def addPicked(self, indices):
        origin = "archive" if self._picker_kind == "archive" else "niche"
        tid = self._ensure_thread()
        n = 0
        for i in indices or []:
            try:
                row = self._picker_rows_raw[int(i)]
            except (IndexError, ValueError, TypeError):
                continue
            if self._add_source(video_source(row, origin), tid=tid):
                n += 1
        if n:
            self.toast.emit(tr("{n} video(s) added to the conversation.").format(n=n), "success")
        self._rebuild_picker()

    # ═════════════════════════════════════════════════════════════════
    #  Google Drive
    # ═════════════════════════════════════════════════════════════════
    @Property(bool, notify=driveChanged)
    def driveConfigured(self):
        return gdrive.is_configured()

    @Property(bool, notify=driveChanged)
    def driveConnected(self):
        return gdrive.is_connected()

    @Property(str, notify=driveChanged)
    def driveEmail(self):
        return gdrive.account_email()

    @Property(bool, notify=driveChanged)
    def driveBusy(self):
        return self._drive_busy

    @Property(str, notify=driveChanged)
    def driveStatus(self):
        return self._drive_status

    @Property("QVariantList", notify=driveChanged)
    def driveFiles(self):
        return self._drive_files

    def _set_drive_busy(self, busy, status=""):
        self._drive_busy = bool(busy)
        self._drive_status = status
        self.driveChanged.emit()

    @Slot(str, str)
    def saveDriveCredentials(self, cid, secret):
        gdrive.save_client_credentials(cid, secret)
        self.driveChanged.emit()
        self.toast.emit(tr("Google OAuth client saved."), "success")

    @Slot()
    def connectDrive(self):
        if self._drive_busy:
            return
        self._drive_stop.clear()
        self._set_drive_busy(True, tr("Finish signing in in your browser…"))

        def work():
            try:
                email = gdrive.connect(lambda u: self._openUrl.emit(u),
                                       should_stop=self._drive_stop.is_set)
                self._driveDone.emit("connect", email, "")
            except Exception as e:      # noqa: BLE001
                self._driveDone.emit("connect", None, str(e))
        threading.Thread(target=work, daemon=True, name="chat-drive-auth").start()

    @Slot()
    def cancelDrive(self):
        self._drive_stop.set()

    @Slot()
    def disconnectDrive(self):
        gdrive.disconnect()
        self._drive_files = []
        self.driveChanged.emit()

    @Slot(str)
    def listDrive(self, search):
        if self._drive_busy or not gdrive.is_connected():
            return
        self._set_drive_busy(True, tr("Loading your Drive…"))

        def work(q=search):
            try:
                self._driveDone.emit("list", gdrive.list_files(q), "")
            except Exception as e:      # noqa: BLE001
                self._driveDone.emit("list", None, explain_network_error(e))
        threading.Thread(target=work, daemon=True, name="chat-drive-list").start()

    @Slot(str)
    def importDriveFile(self, fid):
        if self._drive_busy:
            return
        tid = self._ensure_thread()
        self._set_drive_busy(True, tr("Downloading from Google Drive…"))

        def work(f=fid):
            try:
                path, name = gdrive.download_file(f, CHAT_FILES_DIR)
                self._sourceAdd.emit(tid, self._drive_source(path, name), "")
            except Exception as e:      # noqa: BLE001
                self._sourceAdd.emit(tid, None, explain_network_error(e))
        threading.Thread(target=work, daemon=True, name="chat-drive-get").start()

    def _drive_link_worker(self, tid, text):
        try:
            path, name = gdrive.download_link(text, CHAT_FILES_DIR)
            self._sourceAdd.emit(tid, self._drive_source(path, name), "")
        except Exception as e:      # noqa: BLE001
            self._sourceAdd.emit(tid, None, explain_network_error(e))

    @staticmethod
    def _drive_source(path, name):
        if not kind_for_path(path):
            raise ValueError(tr("This file type isn't supported yet."))
        src = file_source(path, origin="drive")
        src["title"] = name or src["title"]
        src["subtitle"] = src["subtitle"] + " · Google Drive"
        return src

    @Slot(str, "QVariant", str)
    def _on_drive_done(self, op, payload, error):
        self._drive_busy = False
        self._drive_status = ""
        if op == "list" and not error:
            files = []
            for f in payload or []:
                f = dict(f)
                size = int(f.get("size") or 0)
                f["sizeLabel"] = (f"{size / 1048576:.1f} MB" if size >= 1048576
                                  else f"{max(1, size // 1024)} KB" if size else "")
                files.append(f)
            self._drive_files = files
        if op == "connect" and not error:
            self.toast.emit(tr("Google Drive connected{who}.").format(
                who=(" · " + payload) if payload else ""), "success")
            self.driveChanged.emit()
            self.listDrive("")
            return
        if error:
            self.toast.emit(error, "error")
        self.driveChanged.emit()

    # ═════════════════════════════════════════════════════════════════
    #  The turn
    # ═════════════════════════════════════════════════════════════════
    @Property(bool, notify=busyChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=streamChanged)
    def phase(self):
        return self._phase

    @Property(str, notify=streamChanged)
    def streamText(self):
        return self._stream_md

    @Property(bool, notify=streamChanged)
    def streamBuildingCards(self):
        return self._stream_cards

    @Property("QVariantList", notify=streamChanged)
    def steps(self):
        return self._steps

    @Property(int, notify=streamChanged)
    def stepIndex(self):
        return self._step_idx

    @Property(bool, notify=busyChanged)
    def streamingHere(self):
        """Whether the live answer belongs to the thread on screen."""
        return self._busy and self._run_tid == self._tid

    def _set_busy(self, on):
        if on != self._busy:
            self._busy = on
            self.busyChanged.emit()

    @Slot(str)
    def send(self, text):
        text = (text or "").strip()
        if self._busy or (not text and not self._pending):
            return
        if not self._ai_key:
            self.toast.emit(tr("Add an AI provider key in Settings first."), "error")
            return
        tid = self._ensure_thread()
        first = not self._messages
        atts = [{"key": p["key"], "kind": p["kind"], "title": p["title"],
                 "subtitle": p.get("subtitle", ""), "thumb": p.get("thumb", ""),
                 "path": p.get("path", ""), "multLabel": p.get("multLabel", "")}
                for p in self._pending]
        body = text or tr("Take a look at what I attached.")
        chat_add_message(tid, "user", body, atts)
        if first:
            seed = text or (atts[0]["title"] if atts else "")
            t = title_for(seed)
            chat_rename_thread(tid, t)
            self._auto_title[tid] = t
            self._title = t
            self.threadChanged.emit()
        self._pending = []
        self.pendingChanged.emit()
        self._reload_messages()
        self._start_turn(tid)

    @Slot()
    def regenerate(self):
        """Throw the last answer (or the last error) away and ask again."""
        if self._busy or not self._tid or not self._messages:
            return
        last = self._messages[-1]
        if last["role"] == "assistant":
            chat_delete_messages_from(self._tid, last["id"])
        if not any(m["role"] == "user" for m in self._messages):
            return
        self._reload_messages()
        self._start_turn(self._tid)

    @Slot(str)
    def editLast(self, text):
        """Replace the last user message and answer it again."""
        text = (text or "").strip()
        if self._busy or not self._tid or not text:
            return
        users = [m for m in self._messages if m["role"] == "user"]
        if not users:
            return
        last = users[-1]
        atts = [{k: a.get(k, "") for k in ("key", "kind", "title", "subtitle", "thumb", "path", "multLabel")}
                for a in last.get("attachments") or []]
        chat_delete_messages_from(self._tid, last["id"])
        chat_add_message(self._tid, "user", text, atts)
        self._reload_messages()
        self._start_turn(self._tid)

    @Slot()
    def stop(self):
        if not self._busy:
            return
        self._stop.set()
        with self._resp_lock:
            resp = self._resp
        # Shutting the socket is instant; do it here so Stop feels immediate.
        abort_response(resp)

    def _start_turn(self, tid):
        self._run_id += 1
        rid = self._run_id
        self._run_tid = tid
        self._stop = threading.Event()
        with self._resp_lock:
            self._resp = None
        srcs = chat_sources(tid)
        # The SOURCE numbers the model sees this turn, frozen for its idea refs.
        src_keys = [s.get("key") for s in srcs]
        missing = [s for s in srcs if not s.get("_digest") and s.get("kind") != "image"]
        inflight = {s["key"]: self._digest_futures.get(s["key"]) for s in missing
                    if self._digest_futures.get(s["key"]) is not None}
        steps = []
        if srcs:
            steps.append(tr("Reading {n} source(s)").format(n=len(srcs)))
        steps.append(tr("Thinking"))
        steps.append(tr("Writing the answer"))
        self._steps = steps
        self._step_idx = 0
        self._stream_raw = ""
        self._stream_md = ""
        self._stream_cards = False
        self._phase = "thinking"
        self._set_busy(True)
        self.streamChanged.emit()
        self.refreshThreads()
        self.scrollToEnd.emit()

        client = self._make_client()
        model = self.modelName
        history_rows = chat_messages(tid)
        from app import i18n
        ui_lang = "fa" if getattr(i18n, "LANG", "en") == "fa" else "en"
        stop = self._stop

        def set_resp(r):
            with self._resp_lock:
                self._resp = r

        def work():
            try:
                step = 0
                if srcs:
                    for s in missing:
                        if stop.is_set():
                            raise ChatCancelled()
                        d = ""
                        fut = inflight.get(s["key"])
                        if fut is not None:
                            # already being read on the pool: wait for THAT
                            # read rather than fetching the transcript twice
                            try:
                                d = fut.result(timeout=90) or ""
                            except Exception:      # noqa: BLE001
                                d = ""
                        if not d:
                            d = digest(s, fetch_transcripts=True)
                        if d:
                            chat_set_source_digest(tid, s["key"], d)
                            s["_digest"] = d
                            self._sourceDone.emit(tid, s["key"], d, "")
                    step += 1
                    self._step.emit(rid, step)
                block = sources_block([s.get("_digest") or digest(s, False) for s in srcs],
                                      budget=SOURCE_BUDGET)
                # Two or more videos: hand the model the cross-video maths
                # (medians, ranking, winners-vs-rest patterns) computed exactly,
                # numbered like the SOURCES block so it can cite S1, S2 …
                try:
                    analysis = video_set_analysis(
                        [(i, s) for i, s in enumerate(srcs, 1) if s.get("kind") == "video"])
                except Exception:      # noqa: BLE001 — never lose the turn over a stat
                    analysis = ""
                last_user = next((m.get("text") or "" for m in reversed(history_rows)
                                  if m.get("role") == "user"), "")
                turn_no = sum(1 for m in history_rows if m.get("role") == "user")
                hint = classify_turn(
                    last_user, has_sources=bool(srcs),
                    has_briefs=any(s.get("kind") == "brief" for s in srcs),
                    turn_no=turn_no)
                system = build_system_prompt(block, ui_lang, analysis, hint)
                history = self._history(history_rows)
                if stop.is_set():
                    raise ChatCancelled()
                first = [True]

                def on_delta(piece):
                    if first[0]:
                        first[0] = False
                        self._step.emit(rid, len(steps) - 1)
                    self._delta.emit(rid, piece)

                text = stream_chat(client, system, history, on_delta=on_delta,
                                   should_stop=stop.is_set, on_open=set_resp)
                text = bind_idea_sources(text, src_keys)
                self._turnDone.emit(rid, tid, text, "", False, model)
            except ChatCancelled as e:
                partial = bind_idea_sources(getattr(e, "partial", "") or "", src_keys)
                self._turnDone.emit(rid, tid, partial, "", True, model)
            except Exception as e:      # noqa: BLE001
                log_crash("chat turn:\n" + traceback.format_exc())
                self._turnDone.emit(rid, tid, "", explain_network_error(e, client.label), False, model)
            finally:
                set_resp(None)

        threading.Thread(target=work, daemon=True, name="chat-turn").start()

    @staticmethod
    def _history(rows):
        """DB rows → the engine's message shape. Images are loaded only for
        the most recent image-bearing user turns (fit_history would drop the
        rest anyway, and decoding them is not free)."""
        out = []
        image_turns = 0
        for m in reversed(rows):
            role = "assistant" if m.get("role") == "assistant" else "user"
            text = m.get("text") or ""
            err = m.get("error") or ""
            if role == "assistant" and not text:
                continue        # a failed turn: nothing the model said
            if role == "assistant":
                # The follow-up chips are UI, not conversation: re-sending them
                # every turn costs tokens and nudges the model to repeat itself.
                text = strip_followups(text)
            images = []
            if role == "user" and image_turns < 3:
                for a in m.get("attachments") or []:
                    if not isinstance(a, dict):
                        continue
                    p = a.get("path") or ""
                    if a.get("kind") == "image" and p and os.path.isfile(p):
                        try:
                            images.append(image_payload(p))
                        except Exception:
                            pass
                if images:
                    image_turns += 1
            if role == "user":
                titles = [a.get("title", "") for a in (m.get("attachments") or [])
                          if isinstance(a, dict) and a.get("kind") != "image"]
                if titles:
                    text += "\n\n[attached: " + "; ".join(titles) + "]"
            if role == "assistant" and err == _STOPPED:
                text += "\n\n[answer was stopped by the user]"
            out.append({"role": role, "text": text, "images": images})
        out.reverse()
        return fit_history(out)

    @Slot(int, str)
    def _on_delta(self, rid, piece):
        if rid != self._run_id:
            return
        if self._phase != "streaming":
            self._phase = "streaming"
        self._stream_raw += piece
        if not self._flush.isActive():
            self._flush.start()

    def _flush_stream(self):
        self._stream_md, self._stream_cards = stream_display(self._stream_raw)
        self.streamChanged.emit()

    @Slot(int, int)
    def _on_step(self, rid, idx):
        if rid != self._run_id:
            return
        self._step_idx = max(self._step_idx, int(idx))
        self.streamChanged.emit()

    @Slot(int, int, str, str, bool, str)
    def _on_turn_done(self, rid, tid, text, error, cancelled, model):
        self._drop_prefetch(tid)
        if text or error:
            chat_add_message(tid, "assistant", text,
                             error=_STOPPED if cancelled else error, model=model)
        if rid == self._run_id:
            self._flush.stop()
            self._phase = "idle"
            self._stream_raw = self._stream_md = ""
            self._stream_cards = False
            self._run_tid = 0
            self._set_busy(False)
            self.streamChanged.emit()
        if tid == self._tid:
            self._reload_messages()
        self.refreshThreads()
        if error and tid == self._tid:
            self.toast.emit(error, "error")
        # v3.40: a long answer landing while the user is in another app
        if error and not cancelled:
            announce("error", tr("Hunter couldn't answer"), error, page=13,
                     icon="nav_chat", source=tr("AI Chat"))
        elif text and not cancelled:
            announce("success", tr("Hunter replied"), _notice_preview(text),
                     page=13, icon="nav_chat", source=tr("AI Chat"),
                     group="chat")
        if text and not cancelled and not error and tid in self._auto_title:
            self._make_title(tid)

    # ── smart title (best effort, one tiny call after the first answer) ──
    def _make_title(self, tid):
        rows = chat_messages(tid)
        if len(rows) < 2:
            return
        first_user = next((m.get("text") for m in rows if m.get("role") == "user"), "")
        first_ai = next((m.get("text") for m in rows if m.get("role") == "assistant"), "")
        client = self._make_client()

        def work():
            try:
                out = client.generate(title_prompt(first_user, first_ai),
                                      timeout=30, max_output_tokens=40)
                t = " ".join(str(out or "").strip().splitlines()[0].split()) if out else ""
                t = t.strip(" \"'«»“”.:")[:60]
                if t:
                    self._titleDone.emit(tid, t)
            except Exception:
                pass
        threading.Thread(target=work, daemon=True, name="chat-title").start()

    @Slot(int, str)
    def _on_title_done(self, tid, title):
        seed = self._auto_title.pop(tid, None)
        t = chat_get_thread(tid)
        if not t or seed is None or (t.get("title") or "") != seed:
            return      # the user renamed it meanwhile — theirs wins
        chat_rename_thread(tid, title)
        if tid == self._tid:
            self._title = title
            self.threadChanged.emit()
        self.refreshThreads()
