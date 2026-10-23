"""app.qml_backend.web_bridge - YouTube Hunter (QML).

v3.42 "Hunter on YouTube": the desktop half of the browser extension.

The extension (browser-extension/) puts a YouTube Hunter download button on
every YouTube watch page. Clicking it opens a small panel in the TOP-RIGHT
corner of the YouTube tab that lists the qualities this video really has (the
same probe the in-app quality picker runs) and, on Download, hands the job to
this app. The app does not have to come to the front: the download runs in the
background, shows up on the Downloads page like any other, and the panel in
the browser follows its progress.

Transport: a tiny JSON HTTP server on 127.0.0.1:BRIDGE_PORT.

    GET  /v1/ping                    → app name, version, UI language, accent
    GET  /v1/qualities?v=<id>        → picker rows for that video (blocking probe)
    POST /v1/download {v, key}       → start a download at preset `key`
    POST /v1/watch {v, jobs?}        → v3.47: panel heartbeat (no desktop card)
    GET  /v1/status?v=<id>[&watch=1] → live progress / final state
                                       (watch=1: the panel is on screen, so the
                                       desktop live card stays out of the way)
    POST /v1/pause {v}               → v3.44: pause a running download
    POST /v1/resume {v}              → v3.44: resume a paused / stopped one
    POST /v1/reveal {v, id?}         → show the finished file in Explorer
                                       (id: one saved quality, see below)
    POST /v1/play {v, id}            → v3.45: open a saved file in the
                                       system player

    v3.45 — formats + dubs on YouTube:
    GET  /v1/qualities?v=<id>&vf=<mp4|mkv|webm>&af=<mp3|m4a|opus|wav|flac>&lang=<code>
         every row carries `id` ("1080p@mkv", "audio@m4a~ar") and `saved`
         (that exact file is already on disk), plus the format lists and the
         video's audio tracks (original + dubs) so the panel can offer them.
    POST /v1/show {page?}            → bring the window to the front

    v3.43c "Cut on YouTube" — the panel's Cut tab:
    POST /v1/cut {v, cap, start, end, title?, channel?}
                                     → cut [start, end) at ≤ cap p (0 = best)
                                       WITHOUT downloading the whole video;
                                       returns {job}
    GET  /v1/cut/status?job=<id>     → live progress / final state of one cut
    POST /v1/unwatch {v, jobs?}      → v3.51: panel closed / tab left (card may show now)
    POST /v1/cut/cancel {job}        → stop it
    POST /v1/cut/reveal {job}        → show the finished clip in Explorer

Who may talk to it — this is a local server that can start downloads, so it is
deliberately strict:

  * bound to 127.0.0.1 only (never 0.0.0.0);
  * the Host header must be 127.0.0.1 / localhost (blocks DNS rebinding);
  * a request carrying an Origin must come from a browser EXTENSION
    (chrome-extension:// / moz-extension:// / safari-web-extension://). A web
    page's fetch always carries its own https:// origin, so youtube.com — or
    any other site — is refused outright;
  * every non-preflight request must carry `X-YTH-Bridge: 1`. A custom header
    forces a CORS preflight, and preflights are only answered for extension
    origins, so a page cannot even reach the handler by accident.

Threads: the server runs on its own daemon thread (ThreadingHTTPServer, one
thread per request — a quality probe can take several seconds and must not
block a status poll). Anything that touches a ViewModel or a window is sent to
the GUI thread through a queued Signal; the handler only reads thread-safe
state (the live-progress dict, SQLite with its own connection).
"""

import itertools
import json
import os
import re
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from PySide6.QtCore import QObject, Signal, Slot

from app.config import load_app_config
from app.constants import APP_VERSION
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm import _dl_progress as dlp

BRIDGE_PORT = 47391
BRIDGE_HOST = "127.0.0.1"
_EXT_ORIGINS = ("chrome-extension://", "moz-extension://",
                "safari-web-extension://")
_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_MAX_BODY = 16 * 1024
# v3.43c: rows the extension's picker never shows. "Best available" is the
# same file as the top resolution once the probe has the real list, and the
# panel already names every real quality — a second row for it only confused.
# (The preset itself stays: stored/resumed downloads still reference it.)
_HIDDEN_KEYS = frozenset({"best"})
# Cut caps the bridge accepts — the cutter's own ladder (0 = best available).
_CUT_CAPS = (0, 2160, 1440, 1080, 720, 480, 360)
_MAX_LIVE_CUTS = 3
_MAX_CUT_SECONDS = 6 * 3600


class _CutJobs:
    """Thread-safe store for the extension's cut jobs (handler threads read,
    worker threads write). In-memory only: a finished clip is persisted to the
    Cutter's history by clips_add; this just carries live state."""

    def __init__(self):
        self._lock = threading.Lock()
        self._jobs = {}
        self._seq = itertools.count(1)

    def new(self, **fields):
        with self._lock:
            # forget finished jobs older than an hour
            now = time.time()
            for k in [k for k, j in self._jobs.items()
                      if j["state"] not in ("starting", "running")
                      and now - j.get("t", now) > 3600]:
                self._jobs.pop(k, None)
            job = f"c{next(self._seq)}{int(now * 1000) % 100000:05d}"
            self._jobs[job] = dict(fields, state="starting", pct=0, written=0,
                                   text="", label="", file="", size=0,
                                   error="", cancel=False, t=now)
            return job

    def update(self, job, **fields):
        with self._lock:
            if job in self._jobs:
                self._jobs[job].update(fields)

    def get(self, job):
        with self._lock:
            j = self._jobs.get(job)
            return dict(j) if j else None

    def live_count(self):
        with self._lock:
            return sum(1 for j in self._jobs.values()
                       if j["state"] in ("starting", "running"))


def _clip_target_dir():
    """Same folder the Cutter page saves to: Settings' Videos folder, then the
    older general save folder, then Desktop/YouTube."""
    from app.core.utils import desktop_download_dir
    cfg = load_app_config()
    target = (cfg.get("video_save_folder") or "").strip()
    if not target or not os.path.isdir(target):
        target = (cfg.get("save_folder") or "").strip()
    if not target or not os.path.isdir(target):
        target = desktop_download_dir("YouTube")
    return target


def bridge_running(timeout=0.4):
    """True when some YouTube Hunter is already answering on the bridge port.

    Used at start-up: a `youtubehunter://` launch (the extension waking the app
    up) must not open a SECOND window when one is already running."""
    import urllib.request
    try:
        req = urllib.request.Request(
            f"http://{BRIDGE_HOST}:{BRIDGE_PORT}/v1/ping",
            headers={"X-YTH-Bridge": "1"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
            return bool(data.get("ok")) and data.get("app") == "YouTube Hunter"
    except Exception:
        return False


def _accent():
    try:
        from app.ui import theme
        return {"a": str(theme.CLR.get("logo_grad_in") or "#FF1F44"),
                "b": str(theme.CLR.get("logo_grad_out") or "#CC0026")}
    except Exception:
        return {"a": "#FF1F44", "b": "#CC0026"}


# v3.44: the panel on YouTube follows the APP's theme (not YouTube's), so the
# palette it needs is sent with /v1/ping. Keys are the extension's CSS vars.
_THEME_VARS = (
    ("bg", "panel_bg"), ("raise", "surface_high"), ("well", "surface_low"),
    ("line", "border"), ("line-soft", "row_border"), ("text", "on_surface"),
    ("strong", "text_strong"), ("muted", "on_surface_var"), ("dim", "outline"),
    ("track", "hover_bg_strong"), ("ok", "secondary_container"),
    ("bad", "error"), ("warn", "warn"), ("on-acc", "on_primary"),
)


def _theme():
    try:
        from app.ui import theme
        clr = theme.CLR
        return {"mode": "light" if theme.is_light() else "dark",
                "vars": {css: str(clr.get(key)) for css, key in _THEME_VARS
                         if clr.get(key)}}
    except Exception:
        return {"mode": "dark", "vars": {}}


def _lang():
    try:
        from app import i18n
        return i18n.LANG if i18n.LANG in ("en", "fa") else "en"
    except Exception:
        return "en"


# ── v3.45: saved files per quality / format / dub ───────────────────────────
# Downloads are named "<title> [<id>] <key>[ <lang>].<ext>" (download.py), so
# every quality, every output format and every dub of one video sits beside the
# others on disk. The panel's row id spells the same three things:
#     "<key>@<container>[~<lang>]"   e.g. "1080p@mp4", "audio@m4a~ar"
def _row_id(key, container, lang=""):
    out = f"{key}@{container}" if container else str(key or "")
    return f"{out}~{lang}" if lang else out


def _file_id(path, vid):
    """The row id a finished file answers to, or "" if it isn't one of ours."""
    m = re.search(r"\[" + re.escape(vid) + r"\]\s*([^.\[\]]*)\.(\w+)$",
                  os.path.basename(path or ""))
    if not m:
        return ""
    ext = m.group(2).lower()
    if ext not in _SAVED_EXTS:
        return ""                  # .part / .ytdl / an intermediate stream
    key, _, lang = m.group(1).strip().partition(" ")
    return _row_id(key.lower(), ext, lang.strip()) if key else ""


def _saved_files(vid):
    """{row id: path} for every finished file of this video on disk."""
    from app.core.db.downloads import downloads_get
    from app.core.utils import video_download_dir
    if not vid:
        return {}
    folders = []
    try:
        folders.append(video_download_dir("YouTube"))
    except Exception:              # noqa: BLE001
        pass
    try:
        fp = str((downloads_get(vid) or {}).get("filepath") or "")
        if fp:
            folders.append(os.path.dirname(fp))
    except Exception:              # noqa: BLE001
        pass
    out, seen = {}, set()
    tag = f"[{vid}]"
    for folder in folders:
        nf = os.path.normcase(os.path.abspath(folder or "."))
        if not folder or nf in seen or not os.path.isdir(folder):
            continue
        seen.add(nf)
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            if tag not in name:
                continue
            full = os.path.join(folder, name)
            rid = _file_id(full, vid)
            if rid and rid not in out and os.path.isfile(full):
                out[rid] = full
    return out


def _saved_exts():
    try:
        from app.core.download import AUDIO_CODECS, VIDEO_CONTAINERS
        return frozenset([c["key"] for c in VIDEO_CONTAINERS]
                         + [c["key"] for c in AUDIO_CODECS])
    except Exception:              # noqa: BLE001
        return frozenset({"mp4", "mkv", "webm", "mp3", "m4a", "opus", "wav", "flac"})


_SAVED_EXTS = _saved_exts()


class WebBridge(QObject):
    """Owns the local server and runs its requests' side effects on the GUI
    thread. One instance for the whole app (created in main_qml.py)."""

    # handler thread → GUI thread (auto-queued: emitted off the GUI thread)
    _startReq = Signal(str, "QVariant", int)   # (video_id, row, preset_index)
    _revealReq = Signal(str)
    _openPathReq = Signal(str)                  # v3.45: ▶ Play a saved file
    _showReq = Signal(int)
    _revealPathReq = Signal(str)                # v3.43c: a finished clip
    _cutEvent = Signal(str, str, "QVariant")    # (job, begin|update|finish, data)
    _ctlReq = Signal(str, str)                  # v3.44: (video_id, pause|resume)
    # v3.43: an extension answered (installed / Chrome started / YouTube open)
    extensionSeen = Signal()

    def __init__(self, downloads_vm, notifier=None, parent=None, cutter_vm=None):
        super().__init__(parent)
        self._downloads = downloads_vm
        self._notifier = notifier
        self._cutter = cutter_vm
        self._server = None
        self._thread = None
        self._ext_noted = False        # v3.49: extensionSeen already sent this run
        self.cuts = _CutJobs()
        # v3.43c: video ids handed to the GUI thread but not yet started.
        # /v1/status used to answer from the DB row in that gap — and after a
        # FIRST download of the same video that row says "done", so picking a
        # second quality looked finished before it had even begun.
        self._pending = {}
        self._pending_lock = threading.Lock()
        self._startReq.connect(self._on_start)
        self._revealReq.connect(self._on_reveal)
        self._openPathReq.connect(self._on_open_path)
        self._showReq.connect(self._on_show)
        self._revealPathReq.connect(self._on_reveal_path)
        self._cutEvent.connect(self._on_cut_event)
        self._ctlReq.connect(self._on_ctl)

    # ── pending starts (handler thread ↔ GUI thread) ────────────────────
    def mark_pending(self, video_id):
        with self._pending_lock:
            self._pending[video_id] = time.time()

    def clear_pending(self, video_id):
        with self._pending_lock:
            self._pending.pop(video_id, None)

    def is_pending(self, video_id):
        with self._pending_lock:
            t = self._pending.get(video_id)
            if t is None:
                return False
            if time.time() - t > 20:          # the GUI thread never took it
                self._pending.pop(video_id, None)
                return False
            return True

    # ── lifecycle ────────────────────────────────────────────────────────
    def start(self):
        """Bind and serve. False (and the app carries on without the bridge)
        if the port is taken — e.g. a second copy of the app is running."""
        if self._server is not None:
            return True
        cfg = load_app_config()
        if cfg.get("browser_bridge", True) is False:
            return False
        bridge = self

        class _Handler(_BridgeHandler):
            owner = bridge

        try:
            srv = ThreadingHTTPServer((BRIDGE_HOST, BRIDGE_PORT), _Handler)
        except OSError as exc:
            log_crash(f"web bridge: port {BRIDGE_PORT} unavailable: {exc}")
            return False
        srv.daemon_threads = True
        self._server = srv
        self._thread = threading.Thread(
            target=srv.serve_forever, name="yth-web-bridge", daemon=True)
        self._thread.start()
        return True

    @Slot()
    def stop(self):
        srv, self._server = self._server, None
        if srv is not None:
            try:
                srv.shutdown()
                srv.server_close()
            except Exception:
                pass

    # ── GUI-thread side effects ──────────────────────────────────────────
    @Slot(str, "QVariant", int)
    def _on_start(self, video_id, row, preset_index):
        """Exactly what the Downloads page does after its own quality picker:
        park the metadata row as pending, then start at the picked preset.
        Same DB row, same live progress, same away-notice when it finishes."""
        vm = self._downloads
        try:
            if vm is None or dlp.is_running(video_id):
                return
            vm._pending[video_id] = dict(row or {})
            vm.startDownload(video_id, int(preset_index))
        except Exception as exc:          # noqa: BLE001
            log_crash("web bridge: start failed:\n" + repr(exc))
        finally:
            self.clear_pending(video_id)

    @Slot(str, str)
    def _on_ctl(self, video_id, action):
        """v3.44: ⏸ / ▶ from the YouTube panel — the exact calls the desktop
        live card makes, so a pause from either place is the same pause (the
        row parks as "stopped" and yt-dlp's .part file is kept for the resume)."""
        vm = self._downloads
        if vm is None:
            return
        try:
            if action == "pause":
                vm.pauseDownload(video_id)
            elif action == "resume":
                vm.resumeAfterPause(video_id)
        except Exception as exc:          # noqa: BLE001
            log_crash("web bridge: %s failed:\n%r" % (action, exc))

    def watch(self, video_id):
        n = self._notifier
        if n is not None:
            try:
                n.watch(video_id)
            except Exception:
                pass

    @Slot(str)
    def _on_reveal(self, video_id):
        try:
            self._downloads.reveal(video_id)
        except Exception:
            pass

    @Slot(str)
    def _on_reveal_path(self, path):
        try:
            from app.core.utils import reveal_in_file_manager
            if path and os.path.exists(path):
                reveal_in_file_manager(path)
        except Exception:
            pass

    @Slot(str)
    def _on_open_path(self, path):
        """v3.45: ▶ on the YouTube panel — open the saved file in the user's
        default player. Only ever a path _saved_files() found for that video."""
        try:
            if not path or not os.path.isfile(path):
                return
            if sys.platform.startswith("win"):
                os.startfile(path)      # noqa: S606
            else:
                from PySide6.QtCore import QUrl
                from PySide6.QtGui import QDesktopServices
                QDesktopServices.openUrl(QUrl.fromLocalFile(path))
        except Exception as exc:        # noqa: BLE001
            log_crash("web bridge: open failed:\n" + repr(exc))

    def live_card_on(self):
        """True when the app will follow a download with its own live card
        in the corner of the screen — the extension then closes its big
        quality panel right after Download instead of mirroring progress."""
        n = self._notifier
        try:
            return bool(n is not None and n._enabled and n._live_on)
        except Exception:
            return False

    @Slot(int)
    def _on_show(self, page):
        n = self._notifier
        if n is not None:
            try:
                n.activate(int(page))
            except Exception:
                pass


    # ── v3.43c: cuts started from the YouTube panel ─────────────────────
    def start_cut(self, vid, cap, start, end, title, channel,
                  output_format="mp4", audio_only=False, audio_lang=""):
        """Start one cut on its own worker thread. Mirrors CutterVM.startCut
        (same engine, same folder, same Clips history, same live card) but does
        not touch the Cutter page's form — the user may be editing a different
        video there."""
        job = self.cuts.new(vid=vid, cap=cap, start=start, end=end,
                            title=title, channel=channel,
                            output_format=output_format, audio_only=audio_only,
                            audio_lang=audio_lang)
        # The cut was started from the YouTube panel, which is on screen right
        # now: mark it watched BEFORE the "begin" event so the app's corner card
        # never flashes up for the first poll or two (it used to appear, then
        # vanish once the panel's first status request arrived).
        n0 = self._notifier
        if n0 is not None:
            try:
                n0.watch_cut(job)
            except Exception:             # noqa: BLE001
                pass
        self._cutEvent.emit(job, "begin", {"title": title, "vid": vid,
                                           "start": start, "end": end})

        def worker():
            from app.core.cutter import cut_link
            from app.core.download import DOWNLOAD_CANCELLED
            from app.core.db.downloads import file_size_of
            cfg = load_app_config()
            proxy = (cfg.get("ai_proxy", "") or "").strip()
            cookies = (cfg.get("yt_cookies_browser", "") or "").strip().lower()
            jobs = self.cuts
            last = [0.0]
            # v3.49: live speed / expected size / time left for the panel's Cut
            # capsule (the Download capsule already had them). Speed is an EMA
            # over write deltas so a bursty ffmpeg mux doesn't make it jump;
            # the size is extrapolated from bytes-per-percent once the cut is
            # far enough in to be meaningful.
            rate = {"t0": 0.0, "t": 0.0, "w": 0, "spd": 0.0}

            def on_status(text):
                jobs.update(job, text=str(text or ""))
                self._cutEvent.emit(job, "update", {"stage": str(text or "")})

            def on_progress(pct, written):
                pct_i = max(0, min(100, int(pct)))
                written = max(0, int(written))
                now = time.time()
                if not rate["t0"]:
                    rate.update(t0=now, t=now, w=written)
                dt = now - rate["t"]
                if dt >= 0.4:
                    inst = max(0.0, (written - rate["w"]) / dt)
                    rate["spd"] = inst if rate["spd"] <= 0 else rate["spd"] * 0.65 + inst * 0.35
                    rate.update(t=now, w=written)
                total = int(written * 100 / pct_i) if pct_i >= 3 and written > 0 else 0
                elapsed = now - rate["t0"]
                eta = 0
                if 2 <= pct_i < 100 and elapsed > 1.5:
                    eta = int(elapsed * (100 - pct_i) / pct_i)
                elif total and rate["spd"] > 0:
                    eta = int(max(0, total - written) / rate["spd"])
                jobs.update(job, state="running", pct=pct_i, written=written,
                            speed=int(rate["spd"]), total=total, eta=eta,
                            elapsed=int(elapsed))
                if now - last[0] > 0.25:      # the live card needs ~4 fps, not 60
                    last[0] = now
                    self._cutEvent.emit(job, "update",
                                        {"pct": int(pct), "done": int(written)})

            def on_resolved(px, label):
                jobs.update(job, label=str(label or ""))

            try:
                target = _clip_target_dir()
                os.makedirs(target, exist_ok=True)
                jobs.update(job, state="running")
                ok, msg, fp = cut_link(
                    f"https://www.youtube.com/watch?v={vid}", cap, start, end,
                    target, on_status=on_status, on_progress=on_progress,
                    proxy_url=proxy, cookies_browser=cookies,
                    should_cancel=lambda: bool((jobs.get(job) or {}).get("cancel")),
                    on_resolved=on_resolved,
                    audio_lang=audio_lang, output_format=output_format,
                    audio_only=audio_only)
            except Exception as exc:          # noqa: BLE001
                log_crash("web bridge cut failed:\n" + repr(exc))
                ok, msg, fp = False, str(exc), ""
            if msg == DOWNLOAD_CANCELLED:
                jobs.update(job, state="stopped", t=time.time())
                self._cutEvent.emit(job, "finish", {"outcome": "stopped"})
                return
            if not ok:
                jobs.update(job, state="error", error=str(msg or tr("Cut failed.")),
                            t=time.time())
                self._cutEvent.emit(job, "finish", {"outcome": "error",
                                                    "message": str(msg or "")})
                return
            size = 0
            try:
                size = int(file_size_of(fp) or 0)
            except Exception:
                pass
            j = jobs.get(job) or {}
            try:
                from app.core.db.clips import clips_add
                clips_add(title or tr("Untitled"), source_label=title or vid,
                          video_id=vid, start_sec=start, end_sec=end,
                          quality_label=j.get("label") or "",
                          filepath=fp, file_size=size,
                          channel={"channel_title": channel} if channel else None)
            except Exception:                 # noqa: BLE001 — history is auxiliary
                log_crash("web bridge: clip history failed")
            jobs.update(job, state="done", pct=100, file=fp, size=size,
                        t=time.time())
            self._cutEvent.emit(job, "finish", {"outcome": "success", "path": fp})
            # v3.51: the clip row only knows the channel NAME the page showed.
            # Fill in avatar, link and subscriber count (one watch-page read) so
            # the in-app player's channel card is complete, like a cut made in
            # the app itself. Done AFTER the job is reported finished: the read
            # can take a few seconds through a proxy.
            try:
                from app.core.download import channel_meta_for_video
                from app.core.db.clips import clips_update_channel
                meta = channel_meta_for_video(vid)
                if meta and clips_update_channel(vid, meta):
                    self._cutEvent.emit(job, "refresh", {})
            except Exception:                 # noqa: BLE001 — cosmetic only
                log_crash("web bridge: clip channel backfill failed")

        threading.Thread(target=worker, name="yth-bridge-cut", daemon=True).start()
        return job

    @Slot(str, str, "QVariant")
    def _on_cut_event(self, job, kind, data):
        """GUI thread: the desktop live card + the Cutter page's Clips list."""
        from app.qml_backend.desktop_notifier import announce
        from app.core.cutter import fmt_clock
        data = dict(data or {})
        key = "ext-cut:" + job
        n = self._notifier
        try:
            if kind == "begin" and n is not None:
                n.live_begin(key, "cut", title=data.get("title") or tr("Untitled"),
                             thumb_url=f"https://i.ytimg.com/vi/{data.get('vid')}/mqdefault.jpg",
                             page=12, source=tr("Video Cutter"),
                             subtitle=f"{fmt_clock(data.get('start') or 0)} → "
                                      f"{fmt_clock(data.get('end') or 0)}")
                n.live_update(key, stage=tr("Cutting…"))
            elif kind == "update" and n is not None:
                if "pct" in data:
                    n.live_update(key, pct=int(data["pct"]), done=int(data.get("done") or 0),
                                  indeterminate=int(data["pct"]) <= 0)
                elif data.get("stage"):
                    n.live_update(key, stage=str(data["stage"]).rstrip(" …").rstrip("…").strip())
            elif kind == "refresh":
                if self._cutter is not None:
                    self._cutter.refreshClips()
            elif kind == "finish":
                outcome = data.get("outcome") or "error"
                consumed = False
                if n is not None:
                    consumed = n.live_finish(key, outcome,
                                             message=data.get("message") or "",
                                             path=data.get("path") or "")
                # v1.2: the panel is still on screen for this clip and already
                # shows "Clip saved" — never drop a second card on top of it.
                # live_finish() holds the card back for the same reason; this
                # covers the case where its job record was already gone.
                in_page = False
                if n is not None:
                    try:
                        in_page = n.watched("cut:" + job)
                    except Exception:         # noqa: BLE001 — cosmetic only
                        in_page = False
                if not consumed and outcome == "success" and not in_page:
                    announce("success", tr("Clip ready"),
                             os.path.basename(data.get("path") or ""), page=12,
                             path=data.get("path") or "", icon="scissors",
                             source=tr("Video Cutter"))
                if outcome == "success" and self._cutter is not None:
                    self._cutter.refreshClips()
        except Exception as exc:              # noqa: BLE001 — cosmetic only
            log_crash("web bridge cut event: " + repr(exc))


class _BridgeHandler(BaseHTTPRequestHandler):
    owner = None                       # the WebBridge, set per server
    server_version = "YouTubeHunterBridge/1"
    protocol_version = "HTTP/1.1"

    # quiet: BaseHTTPRequestHandler prints every request to stderr
    def log_message(self, fmt, *args):  # noqa: D401
        return

    # ── gatekeeping ──────────────────────────────────────────────────────
    def _origin(self):
        return (self.headers.get("Origin") or "").strip()

    def _origin_ok(self):
        o = self._origin()
        return (not o) or o.startswith(_EXT_ORIGINS)

    def _from_extension(self):
        """Did this request come from the browser extension (vs. the app's own
        `bridge_running()` probe, which is the only other legitimate caller)?

        v3.49 fix — "Settings keeps saying Waiting for the extension": the old
        check required an `Origin: chrome-extension://…` header. Chrome does
        NOT send Origin on a plain GET from an extension's service worker to a
        host it has host_permissions for (no CORS is needed there), so /v1/ping
        succeeded, the YouTube button worked, and the app still never marked
        the extension as connected. Now any of these count:
          * an extension Origin (Firefox / Safari, or Chrome on POSTs);
          * the `X-YTH-Client: ext/<version>` header the extension sends since
            1.1.3;
          * a browser-made request (Sec-Fetch-* headers, or a browser User-Agent)
            from an extension older than 1.1.3. A web page cannot get here:
            it always carries its https:// Origin and _guard() refuses it.
        """
        if self._origin().startswith(_EXT_ORIGINS):
            return True
        if (self.headers.get("X-YTH-Client") or "").lower().startswith("ext"):
            return True
        if self._origin():
            return False
        if self.headers.get("Sec-Fetch-Mode") or self.headers.get("Sec-Fetch-Site"):
            return True
        ua = (self.headers.get("User-Agent") or "")
        return ua.startswith("Mozilla/") and "Python-urllib" not in ua

    def _note_extension(self):
        """Tell the GUI thread once per run; later requests are a no-op so a
        status poll every second does not flood the event queue."""
        owner = self.owner
        if owner is None or getattr(owner, "_ext_noted", False):
            return
        if self._from_extension():
            owner._ext_noted = True
            owner.extensionSeen.emit()         # queued → GUI thread

    def _host_ok(self):
        host = (self.headers.get("Host") or "").strip().lower()
        name = host.rsplit(":", 1)[0] if ":" in host else host
        return name in ("127.0.0.1", "localhost")

    def _cors(self):
        o = self._origin()
        if o and o.startswith(_EXT_ORIGINS):
            self.send_header("Access-Control-Allow-Origin", o)
            self.send_header("Vary", "Origin")

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _guard(self):
        if not self._host_ok() or not self._origin_ok():
            self._send(403, {"ok": False, "error": "forbidden"})
            return False
        if self.headers.get("X-YTH-Bridge") != "1":
            self._send(403, {"ok": False, "error": "missing bridge header"})
            return False
        return True

    def _json_body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0 or n > _MAX_BODY:
            return {}
        try:
            data = json.loads(self.rfile.read(n).decode("utf-8", "replace"))
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _vid(self, value):
        v = str(value or "").strip()
        return v if _VIDEO_ID.match(v) else ""

    # ── verbs ────────────────────────────────────────────────────────────
    def do_OPTIONS(self):            # noqa: N802 — http.server naming
        if not self._host_ok() or not self._origin().startswith(_EXT_ORIGINS):
            self.send_response(403)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(204)
        self._cors()
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-YTH-Bridge, X-YTH-Client")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):                # noqa: N802
        if not self._guard():
            return
        url = urllib.parse.urlsplit(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        try:
            # Any request the extension makes proves it is installed — not only
            # /v1/ping (a panel opened on YouTube is just as good a signal).
            self._note_extension()
            if url.path == "/v1/ping":
                return self._send(200, {
                    "ok": True, "app": "YouTube Hunter", "version": APP_VERSION,
                    "api": 2, "lang": _lang(), "accent": _accent(),
                    "theme": _theme(), "pause": True,
                    # v3.45: per-row formats + dubs, and ▶ Play for saved files
                    "formats": True, "play": True})
            if url.path == "/v1/qualities":
                return self._qualities(self._vid(q.get("v")), q.get("vf"),
                                       q.get("af"), q.get("lang"))
            if url.path == "/v1/status":
                vid = self._vid(q.get("v"))
                if vid and q.get("watch") == "1":
                    self.owner.watch(vid)
                return self._status(vid)
            if url.path == "/v1/cut/status":
                job_id = str(q.get("job") or "")
                if q.get("watch") == "1":
                    n = self.owner._notifier
                    if n is not None:
                        n.watch_cut(job_id)
                return self._cut_status(job_id)
        except Exception as exc:     # noqa: BLE001
            log_crash("web bridge GET failed:\n" + repr(exc))
            return self._send(500, {"ok": False, "error": str(exc)})
        self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self):               # noqa: N802
        if not self._guard():
            return
        path = urllib.parse.urlsplit(self.path).path
        body = self._json_body()
        self._note_extension()
        try:
            if path == "/v1/download":
                return self._download(self._vid(body.get("v")),
                                      str(body.get("key") or "best"), body)
            if path == "/v1/watch":
                # v3.47: the panel's steady heartbeat — this video (and these
                # cut jobs) are on screen in the browser, so the desktop live
                # card stays away from them until the beats stop.
                vid = self._vid(body.get("v"))
                n = self.owner._notifier
                if n is not None:
                    if vid:
                        n.watch(vid)
                    for j in (body.get("jobs") or [])[:_MAX_LIVE_CUTS]:
                        if isinstance(j, str) and self.owner.cuts.get(j):
                            n.watch_cut(j)
                return self._send(200, {"ok": True})
            if path == "/v1/unwatch":
                vid = self._vid(body.get("v"))
                n = self.owner._notifier
                if n is not None:
                    if vid:
                        n.unwatch(vid)
                    for j in (body.get("jobs") or [])[:_MAX_LIVE_CUTS]:
                        if isinstance(j, str):
                            n.unwatch_cut(j)
                return self._send(200, {"ok": True})
            if path in ("/v1/pause", "/v1/resume"):
                return self._control(self._vid(body.get("v")), path[4:])
            if path == "/v1/reveal":
                vid = self._vid(body.get("v"))
                rid = str(body.get("id") or "")
                if vid and rid:
                    # one exact saved quality — never an arbitrary path
                    f = _saved_files(vid).get(rid)
                    if f:
                        self.owner._revealPathReq.emit(f)
                        return self._send(200, {"ok": True})
                if vid:
                    self.owner._revealReq.emit(vid)
                return self._send(200, {"ok": bool(vid)})
            if path == "/v1/play":
                vid = self._vid(body.get("v"))
                f = _saved_files(vid).get(str(body.get("id") or "")) if vid else None
                if f:
                    self.owner._openPathReq.emit(f)   # queued → GUI thread
                return self._send(200, {"ok": bool(f),
                                        "error": "" if f else "not found"})
            if path == "/v1/cut":
                return self._cut(body)
            if path == "/v1/cut/cancel":
                job = str(body.get("job") or "")
                ok = self.owner.cuts.get(job) is not None
                if ok:
                    self.owner.cuts.update(job, cancel=True)
                return self._send(200, {"ok": ok})
            if path == "/v1/cut/reveal":
                j = self.owner.cuts.get(str(body.get("job") or "")) or {}
                # only a file THIS bridge produced — never an arbitrary path
                if j.get("file"):
                    self.owner._revealPathReq.emit(j["file"])
                return self._send(200, {"ok": bool(j.get("file"))})
            if path == "/v1/show":
                try:
                    page = int(body.get("page", 8))
                except (TypeError, ValueError):
                    page = 8
                self.owner._showReq.emit(page)
                return self._send(200, {"ok": True})
        except Exception as exc:     # noqa: BLE001
            log_crash("web bridge POST failed:\n" + repr(exc))
            return self._send(500, {"ok": False, "error": str(exc)})
        self._send(404, {"ok": False, "error": "not found"})

    # ── endpoints ────────────────────────────────────────────────────────
    def _qualities(self, vid, vf=None, af=None, lang=None):
        """The picker rows for one video, sized for the output format the
        panel picked (default: the user's saved choice) and, on a dubbed
        video, for the picked audio track. Falls back to the generic ladder
        (probed=False) exactly like the in-app picker, so a probe failure
        never blocks a download.

        v3.45: the same choices the in-app quality picker offers — video
        format (MP4 / MKV / WEBM), audio format (MP3 / M4A / OPUS / WAV /
        FLAC) and the audio language of a dubbed video. Re-asking with a new
        format is cheap: fetch_probe_info() caches the extraction per video."""
        from app.core.audio_tracks import audio_tracks_from_formats
        from app.core.download import (AUDIO_CODECS, VIDEO_CONTAINERS,
                                       download_prefs, fetch_probe_info,
                                       qualities_from_info)
        from app.qml_backend.vm.quality_probe import _row, default_quality_rows
        if not vid:
            return self._send(400, {"ok": False, "error": "bad video id"})
        cfg = load_app_config()
        proxy = (cfg.get("ai_proxy", "") or "").strip()
        cookies = (cfg.get("yt_cookies_browser", "") or "").strip().lower()
        prefs = download_prefs()
        vkeys = [c["key"] for c in VIDEO_CONTAINERS]
        akeys = [c["key"] for c in AUDIO_CODECS]
        vf = str(vf or "").lower()
        af = str(af or "").lower()
        vf = vf if vf in vkeys else prefs.get("video", "mp4")
        af = af if af in akeys else prefs.get("audio", "mp3")
        lang = re.sub(r"[^\w-]", "", str(lang or ""))[:16]
        rows, probed, err, tracks = None, False, "", []
        cut_rates, cut_level = {}, ""
        try:
            info, err = fetch_probe_info(
                f"https://www.youtube.com/watch?v={vid}",
                proxy_url=proxy, cookies_browser=cookies)
            if info:
                try:
                    tracks = audio_tracks_from_formats(info.get("formats") or [])
                except Exception as exc:     # noqa: BLE001 — no dub list, still fine
                    log_crash("web bridge: audio tracks: " + repr(exc))
                    tracks = []
                if lang and not any(t.get("key") == lang for t in tracks):
                    lang = ""                # that dub isn't (or no longer) there
                ok, opts, err = qualities_from_info(info, vf, af, audio_lang=lang)
                # v1.0.3: the Cut tab's sizes — bytes per second of clip for
                # each tier and output, from the same numbers the cutter
                # encodes with (app.core.cutter.cut_video_kbps)
                try:
                    from app.core.cutter import _cut_quality, cut_size_rates
                    cut_level = _cut_quality()
                    cut_rates = cut_size_rates(info.get("formats") or [],
                                               info.get("duration") or 0,
                                               audio_lang=lang, level=cut_level)
                except Exception as exc:     # noqa: BLE001 — panel falls back
                    log_crash("web bridge: cut rates: " + repr(exc))
                    cut_rates = {}
                if ok and opts:
                    rows = [_row(p, p.get("size"), p.get("size_exact")) for p in opts]
                    probed = True
        except Exception as exc:     # noqa: BLE001 — fall back, don't fail
            err = str(exc)
        if rows is None:
            rows = default_quality_rows()
            lang = ""
        rows = [r for r in rows if r.get("key") not in _HIDDEN_KEYS]
        saved = _saved_files(vid)
        for r in rows:
            c = af if r.get("isAudio") else vf
            r["container"] = c
            r["id"] = _row_id(r.get("key"), c, lang)
            r["saved"] = r["id"] in saved
        self._send(200, {
            "ok": True, "probed": probed, "rows": rows,
            "format": {"video": vf, "audio": af},
            "formats": {
                "video": [{"key": c["key"], "label": c["label"], "sub": tr(c["sub"])}
                          for c in VIDEO_CONTAINERS],
                "audio": [{"key": c["key"], "label": c["label"], "sub": tr(c["sub"])}
                          for c in AUDIO_CODECS]},
            "tracks": tracks,
            "lang": lang,
            "cutRates": cut_rates,
            "cutQuality": cut_level,
            "saved": sorted(saved.keys()),
            "note": "" if probed else tr(
                "Couldn't read this video's formats — showing the standard options."),
            "error": "" if probed else (err or "")})

    def _download(self, vid, key, body):
        from app.core.download import DOWNLOAD_QUALITY_PRESETS
        from app.core.net import fetch_youtube_oembed
        if not vid:
            return self._send(400, {"ok": False, "error": "bad video id"})
        index = next((i for i, p in enumerate(DOWNLOAD_QUALITY_PRESETS)
                      if p["key"] == key), 0)
        if dlp.is_running(vid) or self.owner.is_pending(vid):
            return self._send(200, {"ok": True, "already": True,
                                    "live": self.owner.live_card_on()})
        # v3.45: the panel's format + dub picks. Exactly what the in-app
        # picker does on a click: the format becomes the saved choice and the
        # dub is remembered for this video, and startDownload() reads both.
        self._apply_picks(vid, body)
        cfg = load_app_config()
        proxy = (cfg.get("ai_proxy", "") or "").strip()
        # oEmbed on THIS thread: the GUI thread must never wait on the network.
        try:
            row = fetch_youtube_oembed(vid, proxy=proxy or None) or {}
        except Exception:            # noqa: BLE001 — the page's own hints suffice
            row = {}
        row = dict(row)
        row.setdefault("video_id", vid)
        row.setdefault("video_url", f"https://www.youtube.com/watch?v={vid}")
        # the extension sends what YouTube's page already shows; only used to
        # fill gaps (oEmbed fails on age-restricted / members-only videos)
        for k_row, k_body in (("title", "title"), ("channel_title", "channel")):
            if not row.get(k_row) and body.get(k_body):
                row[k_row] = str(body.get(k_body))[:300]
        if not row.get("thumbnail_url"):
            row["thumbnail_url"] = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
        self.owner.mark_pending(vid)
        if body.get("inPage"):
            # the panel follows this one itself — before the first tick, so
            # the desktop live card never flashes up
            self.owner.watch(vid)
        self.owner._startReq.emit(vid, row, index)
        self._send(200, {"ok": True, "queued": True,
                         "title": row.get("title") or "",
                         "live": self.owner.live_card_on()})

    @staticmethod
    def _apply_picks(vid, body):
        from app.core.download import save_download_prefs, set_audio_lang
        vf = str(body.get("vf") or "").lower()
        af = str(body.get("af") or "").lower()
        if vf or af:
            save_download_prefs(video=vf or None, audio=af or None)
        if "lang" in body:
            set_audio_lang(vid, re.sub(r"[^\w-]", "", str(body.get("lang") or ""))[:16])

    def _status(self, vid):
        from app.core.db.downloads import downloads_get
        if not vid:
            return self._send(400, {"ok": False, "error": "bad video id"})
        live = dict(dlp.get(vid) or {})
        if not live.get("running") and self.owner.is_pending(vid):
            return self._send(200, {"ok": True, "state": "starting", "pct": 0,
                                    "text": "", "done": 0, "total": 0,
                                    "speed": 0.0, "eta": 0})
        if live.get("running"):
            text = str(live.get("text") or "")
            cancelling = bool(live.get("cancelling"))
            intent = str(live.get("intent") or "") if cancelling else ""
            # merging / converting: the bytes are in, nothing left to pause
            post = (text == tr("Merging…")
                    or text.startswith(tr("Converting to {fmt}…").split("{")[0]))
            return self._send(200, {
                "ok": True, "state": "running",
                "pct": int(live.get("pct") or 0),
                "text": text,
                "done": int(live.get("done") or 0),
                "total": int(live.get("total") or 0),
                "speed": float(live.get("speed") or 0.0),
                "eta": int(live.get("eta") or 0),
                "cancelling": cancelling,
                # v3.44: lets the panel word "Pausing…" / "Resuming…" and
                # decide whether ⏸ is offered at all
                "intent": intent,
                "post": bool(post),
                "canPause": not cancelling and not post})
        row = downloads_get(vid) or {}
        status = str(row.get("status") or "")
        state = {"complete": "done", "done": "done",
                 "failed": "error", "error": "error",
                 "stopped": "stopped",
                 "downloading": "starting", "merging": "running"}.get(status, "none")
        self._send(200, {
            "ok": True, "state": state,
            "pct": int(row.get("progress") or 0),
            "file": str(row.get("filepath") or ""),
            # v3.45: which row that file is ("720p@mp4", "audio@mp3~ar")
            "id": _file_id(str(row.get("filepath") or ""), vid),
            "size": int(row.get("file_size") or 0),
            "quality": str(row.get("quality_label") or ""),
            "error": str(row.get("error_message") or "")})

    def _control(self, vid, action):
        """v3.44: ⏸ / ▶ for one download. Answers at once; the panel's next
        /v1/status poll shows the result ("Pausing…" → paused, or bytes
        moving again)."""
        if not vid:
            return self._send(400, {"ok": False, "error": "bad video id"})
        live = dlp.get(vid) or {}
        if action == "pause":
            ok = bool(live.get("running")) and not live.get("cancelling")
        else:
            # paused/stopped (no live entry), or a pause still unwinding
            ok = (not live.get("running")) or (
                bool(live.get("cancelling"))
                and live.get("intent") in ("pause", "stop"))
        if ok:
            self.owner._ctlReq.emit(vid, action)   # queued → GUI thread
        self._send(200, {"ok": ok})

    # ── v3.43c: cut ──────────────────────────────────────────────────────
    def _cut(self, body):
        vid = self._vid(body.get("v"))
        if not vid:
            return self._send(400, {"ok": False, "error": "bad video id"})
        try:
            cap = int(body.get("cap") or 0)
            start = float(body.get("start"))
            end = float(body.get("end"))
        except (TypeError, ValueError):
            return self._send(400, {"ok": False, "error": tr("Bad segment times.")})
        if cap not in _CUT_CAPS:
            cap = 0
        if not (end > start >= 0) or end - start > _MAX_CUT_SECONDS:
            return self._send(400, {"ok": False,
                                    "error": tr("The end must be after the start.")})
        if self.owner.cuts.live_count() >= _MAX_LIVE_CUTS:
            return self._send(429, {"ok": False, "error": tr(
                "Three cuts are already running — wait for one to finish.")})
        title = str(body.get("title") or "")[:300]
        channel = str(body.get("channel") or "")[:200]
        fmt = str(body.get("format") or "mp4").lower()
        allowed = {"mp4", "mkv", "webm", "mp3", "m4a", "opus", "wav", "flac"}
        if fmt not in allowed:
            fmt = "mp4"
        audio_only = bool(body.get("audioOnly")) or fmt in {"mp3", "m4a", "opus", "wav", "flac"}
        lang = re.sub(r"[^\w-]", "", str(body.get("lang") or ""))[:16]
        job = self.owner.start_cut(vid, cap, start, end, title, channel,
                                   output_format=fmt, audio_only=audio_only,
                                   audio_lang=lang)
        self._send(200, {"ok": True, "job": job})

    def _cut_status(self, job):
        j = self.owner.cuts.get(job)
        if not j:
            return self._send(404, {"ok": False, "state": "none"})
        self._send(200, {
            "ok": True, "state": j["state"], "pct": int(j.get("pct") or 0),
            "written": int(j.get("written") or 0), "text": j.get("text") or "",
            # v3.49: same three numbers the Download capsule shows
            "speed": int(j.get("speed") or 0), "total": int(j.get("total") or 0),
            "eta": int(j.get("eta") or 0), "elapsed": int(j.get("elapsed") or 0),
            "label": j.get("label") or "", "size": int(j.get("size") or 0),
            "name": os.path.basename(j.get("file") or ""),
            "error": j.get("error") or ""})
