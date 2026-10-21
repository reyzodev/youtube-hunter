"""app.core.transcripts - Youtube Scrapper."""

import html
import json
import re
import threading
import urllib.parse
import urllib.request

from app.core.net import _urlopen, configured_proxy

# ── lazy library binding ─────────────────────────────────────────────────
# `youtube_transcript_api` costs about 7.5 MB of resident memory, and this module
# is imported at STARTUP (dashboard_vm imports fetch_transcript for the scrape
# form), so every launch used to pay for a library that is only needed when the
# user actually asks for a transcript. Resolved once, on first use, and cached.
_YTA = None


def _yta():
    """(api_class, has_new_api, block_errors, no_transcript_errors)."""
    global _YTA
    if _YTA is None:
        import youtube_transcript_api as mod
        from youtube_transcript_api import YouTubeTranscriptApi as api
        block = tuple(
            e for e in (getattr(mod, n, None)
                        for n in ("RequestBlocked", "IpBlocked", "TooManyRequests"))
            if isinstance(e, type))
        no_tr = tuple(
            e for e in (getattr(mod, n, None)
                        for n in ("TranscriptsDisabled", "NoTranscriptFound",
                                  "VideoUnavailable", "CouldNotRetrieveTranscript"))
            if isinstance(e, type))
        _YTA = (api, hasattr(api, "fetch"), block, no_tr)
    return _YTA
# ═════════════════════════════════════════════════════════════════════════
#  TRANSCRIPTS — single clean code path for old AND new library versions
#  ---------------------------------------------------------------------
#  The previous implementation mixed the 0.6.x static API with the 1.x
#  instance API; on a current install two of its three attempts raised
#  AttributeError on every video. This resolves the right API once and
#  distinguishes "no transcript exists" from "YouTube is blocking us".
# ═════════════════════════════════════════════════════════════════════════
_TRANSCRIPT_LANGS = ["en", "en-US", "en-GB", "fa", "ar", "es", "fr", "de",
                      "it", "pt", "ru", "ja", "ko", "hi", "tr", "nl", "pl"]

# Concurrent yt-dlp caption fetches. See _fetch_via_ytdlp. Resized per scrape
# by set_turbo() — the Worker Threads setting decides how hard we push.
_CAPTION_SLOTS = threading.Semaphore(2)


# ═════════════════════════════════════════════════════════════════════════
#  TURBO — the Worker Threads setting (1-8) → how parallel transcripts run
#  ---------------------------------------------------------------------
#  A transcript is almost pure network wait (two small HTTPS round-trips), so
#  the CPU is idle while it runs and many can be in flight at once. The scale
#  is gentle up to 4 (the old behaviour, where everything was capped at 4)
#  and then climbs steeply into the Turbo band, so 8 = 16 transcripts at once.
#  The heavy yt-dlp fallback scales far more carefully: a burst of full player
#  extractions is exactly what gets an IP throttled.
# ═════════════════════════════════════════════════════════════════════════
_TURBO = {
    #     transcript workers, yt-dlp fallback slots
    1: (1, 1),
    2: (2, 2),
    3: (3, 2),
    4: (4, 2),
    5: (6, 3),
    6: (8, 3),
    7: (12, 4),
    8: (16, 6),
}


def turbo_profile(thread_count):
    """{"workers", "ytdlp_slots", "turbo"} for a Worker Threads value."""
    try:
        n = max(1, min(8, int(thread_count or 1)))
    except (TypeError, ValueError):
        n = 1
    workers, slots = _TURBO[n]
    return {"level": n, "workers": workers, "ytdlp_slots": slots, "turbo": n >= 6}


def set_turbo(thread_count):
    """Apply a Worker Threads value before a scrape. Returns the profile."""
    global _CAPTION_SLOTS
    prof = turbo_profile(thread_count)
    # A fresh semaphore: fetches still holding the old one finish normally.
    _CAPTION_SLOTS = threading.Semaphore(prof["ytdlp_slots"])
    return prof


# One YouTubeTranscriptApi (and so one requests.Session with its keep-alive
# connection pool) PER WORKER THREAD. The old code built a new client for every
# video, which meant a fresh TCP + TLS handshake to youtube.com twice per
# transcript — on a slow or proxied link that handshake was most of the time.
# requests.Session is not guaranteed thread-safe, hence thread-local.
_TLS = threading.local()


def _session():
    sess = getattr(_TLS, "session", None)
    if sess is None:
        try:
            import requests
            from requests.adapters import HTTPAdapter
            sess = requests.Session()
            adapter = HTTPAdapter(pool_connections=4, pool_maxsize=4, max_retries=0)
            sess.mount("https://", adapter)
            sess.mount("http://", adapter)
            sess.headers.update({"Accept-Language": "en-US,en;q=0.9"})
        except Exception:      # noqa: BLE001 — the library makes its own then
            sess = False
        _TLS.session = sess
    return sess or None


# Circuit breaker for the library path. On a network where youtube.com blocks
# the library outright, every video used to pay a doomed library attempt before
# falling back to yt-dlp. After a few blocks in a row the library is skipped
# for a while and transcripts go straight to the fallback; one success closes
# the breaker again.
_BREAKER_TRIP = 4
_BREAKER_COOLDOWN = 90.0
_breaker = {"fails": 0, "open_until": 0.0}
_breaker_lock = threading.Lock()


def _library_allowed():
    import time as _t
    with _breaker_lock:
        return _t.monotonic() >= _breaker["open_until"]


def _library_result(kind):
    import time as _t
    with _breaker_lock:
        if kind == "blocked":
            _breaker["fails"] += 1
            if _breaker["fails"] >= _BREAKER_TRIP:
                _breaker["open_until"] = _t.monotonic() + _BREAKER_COOLDOWN
                _breaker["fails"] = 0
        elif kind in ("", "none"):
            _breaker["fails"] = 0
            _breaker["open_until"] = 0.0


def reset_breaker():
    """Called when the user switches IP / starts a new scrape."""
    with _breaker_lock:
        _breaker["fails"] = 0
        _breaker["open_until"] = 0.0


def _join_transcript(entries):
    parts = []
    for s in entries:
        txt = getattr(s, "text", None)
        if txt is None and isinstance(s, dict):
            txt = s.get("text", "")
        if txt:
            parts.append(txt)
    return " ".join(parts)


def get_public_ip(timeout=6):
    """Best-effort lookup of this machine's current public IP address.
    Tries a few plain-text endpoints in case one is down or itself
    blocked; returns None (never raises) if all of them fail — callers
    treat that as "couldn't verify" rather than "IP unchanged"."""
    endpoints = (
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    )
    for url in endpoints:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            # Through the configured proxy: the whole point of this lookup is to
            # report the IP YouTube actually sees, and on a proxied setup a
            # direct request reports the wrong one.
            with _urlopen(req, timeout, configured_proxy()) as resp:
                ip = resp.read().decode("utf-8", "ignore").strip()
                if ip and re.match(r"^[0-9a-fA-F:.]+$", ip):
                    return ip
        except Exception:
            continue
    return None


def fetch_transcript(video_id):
    """Fetch a transcript. Returns (status, text, err_kind) and NEVER raises.
    err_kind: "" ok/none · "blocked" IP/rate blocked · "error" other.

    The fast path, in order:

      0. The on-disk cache (shared with the AI Chat): a video read before —
         by a previous scrape, a resume, or the chat — costs nothing.
      1. `youtube_transcript_api`, ONE list() + ONE fetch() on a kept-alive
         per-thread session. If YouTube says the video has no captions, that is
         final: we stop here. (The old code then ran the whole yt-dlp client
         ladder — 5-25 s per rung — just to hear "no captions" again. On a
         Shorts-heavy channel that was most of the scrape time.)
      2. Only when the library was blocked or failed: yt-dlp, first a light
         three-rung lookup (no DASH/HLS manifests), and the full download
         client ladder only if nothing answered at all. yt-dlp inherits the
         configured proxy, the JS runtime and the cookies, so this is still the
         path that survives a filtered network.
    """
    video_id = str(video_id or "").strip()
    if not video_id:
        return ("Not Available", "N/A", "none")
    hit = cached_transcript(video_id)
    if hit is not None:
        status, text, kind = hit
        return (status, _trim(text) if text and text != "N/A" else text, kind)

    proxy = configured_proxy()
    if _library_allowed():
        status, text, err_kind = _library_quick(video_id, proxy, trim=False)
        _library_result(err_kind)
    else:
        status, text, err_kind = ("Not Available", "N/A", "blocked")

    if not (text and text != "N/A") and err_kind in ("blocked", "error"):
        fb = None
        try:
            with _CAPTION_SLOTS:
                fb = _ytdlp_quick(video_id, proxy)
                if fb is None:
                    # Nothing answered the light lookup: walk the full ladder.
                    fb = _fetch_via_ytdlp_inner(video_id, proxy) or None
        except Exception:      # noqa: BLE001 — never raise out of this API
            fb = None
        if fb:
            status, text, err_kind = "Available (Auto)", fb, ""
        elif fb == "":
            # The light lookup got a real player answer with no caption
            # tracks: final, even if the library was blocked.
            status, text, err_kind = "Not Available", "N/A", "none"
        # else (None): nothing answered. Keep "blocked" / "error" — "no
        # captions" was never actually checked, and the user needs to know to
        # switch the VPN node rather than read it as final.

    if text and text != "N/A":
        _cache_put(video_id, status, text, "")
        return (status, _trim(text), "")
    _cache_put(video_id, "Not Available", "N/A", err_kind)
    return ("Not Available", "N/A", err_kind or "none")


def _fetch_transcript_legacy(video_id):
    """The pre-turbo path (library fetch → full yt-dlp ladder on anything but
    success). Kept for reference / A-B testing; nothing calls it."""
    proxy = configured_proxy()
    status, text, err_kind = _fetch_via_library(video_id, proxy)
    if text and text != "N/A":
        return (status, text, err_kind)
    try:
        fallback = _fetch_via_ytdlp(video_id, proxy)
    except Exception:      # noqa: BLE001
        fallback = ""
    if fallback:
        return ("Available (Auto)", _trim(fallback), "")
    if err_kind == "blocked":
        return ("Not Available", "N/A", "blocked")
    if err_kind == "error":
        return ("Not Available", "N/A", "error")
    return ("Not Available", "N/A", "none")


def _trim(text):
    text = text.strip()
    return text[:3000] + ("…" if len(text) > 3000 else "")


# The chat keeps the opening AND the ending of a transcript (hook + payoff),
# so its cut is head + " [...] " + tail — see app.core.ai.chat_sources.
_ENDS_HEAD, _ENDS_TAIL = 2300, 700


def _trim_ends(text):
    t = " ".join(str(text or "").split())
    if len(t) <= _ENDS_HEAD + _ENDS_TAIL:
        return t
    head = t[:_ENDS_HEAD].rsplit(" ", 1)[0]
    tail = t[-_ENDS_TAIL:].split(" ", 1)[-1]
    return head + " [...] " + tail


# The cache keeps the transcript at full length (capped), and every caller
# cuts its own view of it: the scraper's export column, the chat's head+tail.
_CACHE_TEXT_CAP = 120_000


def _library_api(api_cls, proxy):
    """A YouTubeTranscriptApi routed through the app's proxy when one is set.

    Without this the library talks to YouTube directly even on a machine whose
    YouTube access depends on the proxy in Settings — the transcript endpoint
    then answers blocked and the row reads "Not Available".
    """
    cfg = None
    if proxy:
        try:
            from youtube_transcript_api.proxies import GenericProxyConfig
            cfg = GenericProxyConfig(http_url=proxy, https_url=proxy)
        except Exception:      # noqa: BLE001 — older library, or no proxy extra
            cfg = None
    key = (id(api_cls), proxy or "")
    cached = getattr(_TLS, "api", None)
    if cached is not None and cached[0] == key:
        return cached[1]
    sess = _session()
    api = None
    kwargs = {}
    if cfg is not None:
        kwargs["proxy_config"] = cfg
    if sess is not None:
        try:
            api = api_cls(http_client=sess, **kwargs)
        except TypeError:
            api = None
    if api is None:
        try:
            api = api_cls(**kwargs)
        except TypeError:
            api = api_cls()    # 0.6.x-style class: no proxy_config parameter
    _TLS.api = (key, api)
    return api


def _fetch_via_library(video_id, proxy):
    """The library path. Returns (status, text, err_kind); text is "N/A" when it
    could not answer, so the caller can fall through to yt-dlp."""
    try:
        _api, _has_new, _block_errs, _no_tr_errs = _yta()
    except Exception:
        return ("Not Available", "N/A", "error")
    try:
        text = ""
        status = "Not Available"
        if _has_new:                                    # youtube-transcript-api >= 1.0
            api = _library_api(_api, proxy)
            try:
                fetched = api.fetch(video_id, languages=_TRANSCRIPT_LANGS)
                text = _join_transcript(fetched)
                status = "Available"
            except _block_errs:
                raise
            except Exception:
                # none of the preferred languages → take ANY available track
                tlist = api.list(video_id)
                first = next(iter(tlist))
                text = _join_transcript(first.fetch())
                status = ("Available (Auto)" if getattr(first, "is_generated", False)
                          else "Available (Manual)")
        else:                                            # youtube-transcript-api 0.6.x
            try:
                entries = _api.get_transcript(
                    video_id, languages=_TRANSCRIPT_LANGS)
                text = _join_transcript(entries)
                status = "Available"
            except _block_errs:
                raise
            except Exception:
                tlist = _api.list_transcripts(video_id)
                first = next(iter(tlist))
                text = _join_transcript(first.fetch())
                status = ("Available (Auto)" if getattr(first, "is_generated", False)
                          else "Available (Manual)")
        text = text.strip()
        if not text:
            return ("Not Available", "N/A", "none")
        return (status, _trim(text), "")
    except _block_errs:
        return ("Not Available", "N/A", "blocked")
    except _no_tr_errs:
        return ("Not Available", "N/A", "none")
    except Exception:
        return ("Not Available", "N/A", "error")


# ═════════════════════════════════════════════════════════════════════════
#  yt-dlp caption fallback
# ═════════════════════════════════════════════════════════════════════════
# Preference order for the caption payload: json3 carries the text as clean
# JSON segments, srv3/vtt need tag stripping. All three are offered by YouTube
# for the same track, so asking for the tidiest one costs nothing.
_CAPTION_FORMATS = ("json3", "srv3", "vtt", "ttml")


def _pick_caption_track(subtitles, automatic):
    """(track, is_auto) for the first preferred language that has one."""
    for source, is_auto in ((subtitles, False), (automatic, True)):
        for lang in _TRANSCRIPT_LANGS:
            for key in (lang, lang.lower(), lang.split("-")[0]):
                track = source.get(key)
                if track:
                    return track, is_auto
    # Nothing in a preferred language — take whatever the video actually has.
    for source, is_auto in ((subtitles, False), (automatic, True)):
        for _lang, track in sorted(source.items()):
            if track:
                return track, is_auto
    return None, False


def _caption_payload_text(raw, ext):
    """Plain text out of a YouTube caption payload (json3 / srv3 / vtt / ttml)."""
    if ext == "json3":
        try:
            data = json.loads(raw)
        except ValueError:
            return ""
        parts = []
        for event in data.get("events") or []:
            for seg in event.get("segs") or []:
                parts.append(seg.get("utf8") or "")
        return "".join(parts)
    if ext in ("srv3", "ttml", "xml"):
        # XML-ish: take the TEXT NODES (whatever sits between a `>` and the next
        # `<`). Nested elements are the norm here (`<p><s>one</s><s> two</s></p>`),
        # so matching whole elements with a lazy regex captures the opening tag
        # of the child instead of its text. The document also arrives as ONE
        # line starting with "<?xml", which a line-based strip would throw away
        # entirely — every word of it.
        chunks = re.findall(r">([^<>]+)<", raw)
        return " ".join(html.unescape(c).strip() for c in chunks if c.strip())
    if ext in ("vtt", "srt"):
        out = []
        for line in raw.splitlines():
            s = line.strip()
            if (not s or s.startswith(("WEBVTT", "Kind:", "Language:", "NOTE"))
                    or "-->" in s or s.isdigit()):
                continue
            s = re.sub(r"<[^>]+>", "", s)
            if s:
                out.append(html.unescape(s))
        return " ".join(out)
    return raw


def _fetch_via_ytdlp(video_id, proxy=""):
    """Caption text via yt-dlp, or "" when there is none.

    Uses the SAME client ladder the downloads use (app.core.download.
    CLIENT_LADDER), so a machine where only, say, `android` answers YouTube still
    gets its captions. Bounded: it stops as soon as a rung returns captions, and
    gives up after a few caption-less rungs.
    """
    # A scrape fetches transcripts four at a time; when the library is blocked
    # every one of those would run a full extraction here, and four simultaneous
    # extractions is exactly how an IP gets throttled harder. Two at a time.
    with _CAPTION_SLOTS:
        return _fetch_via_ytdlp_inner(video_id, proxy)


def _fetch_via_ytdlp_inner(video_id, proxy=""):
    from app.core.runtime_deps import js_runtime_opts
    from app.core.utils import ensure_yt_dlp_ready

    try:
        from app.core.download import CLIENT_LADDER, _QuietLogger
    except Exception:          # noqa: BLE001
        CLIENT_LADDER = ([],)

        class _QuietLogger:                      # minimal stand-in
            def debug(self, msg): pass
            def info(self, msg): pass
            def warning(self, msg): pass
            def error(self, msg): pass

    yt_dlp, _ffmpeg = ensure_yt_dlp_ready()
    base = {"quiet": True, "no_warnings": True, "skip_download": True,
            "noplaylist": True, "extractor_retries": 2, "socket_timeout": 25,
            "logger": _QuietLogger()}
    base.update(js_runtime_opts())
    if proxy:
        base["proxy"] = proxy

    url = f"https://www.youtube.com/watch?v={video_id}"
    info, barren = None, 0
    for clients in CLIENT_LADDER:
        opts = dict(base)
        if clients:
            opts["extractor_args"] = {"youtube": {"player_client": clients}}
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                got = ydl.extract_info(url, download=False)
        except Exception:      # noqa: BLE001 — next client
            continue
        if not got:
            continue
        if got.get("subtitles") or got.get("automatic_captions"):
            info = got
            break
        # An answer without captions: keep it (so a genuine "no captions on this
        # video" is reported rather than "blocked") but do not walk all twelve
        # rungs hunting for one that happens to carry them.
        if info is None:
            info = got
        barren += 1
        if barren >= 3:
            break
    if not info:
        return ""
    track, _is_auto = _pick_caption_track(info.get("subtitles") or {},
                                          info.get("automatic_captions") or {})
    if not track:
        return ""
    by_ext = {}
    for fmt in track:
        ext = (fmt.get("ext") or "").lower()
        if ext and ext not in by_ext and fmt.get("url"):
            by_ext[ext] = fmt
    chosen = next((by_ext[e] for e in _CAPTION_FORMATS if e in by_ext), None)
    if chosen is None:
        chosen = next(iter(by_ext.values()), None)
    if chosen is None:
        return ""
    req = urllib.request.Request(
        chosen["url"], headers={"User-Agent": "Mozilla/5.0"})
    with _urlopen(req, 25, proxy) as resp:
        raw = resp.read().decode("utf-8", "replace")
    text = _caption_payload_text(raw, (chosen.get("ext") or "").lower())
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


# ═════════════════════════════════════════════════════════════════════════
#  QUICK PATH — for the AI Chat (archive / niche / link sources)
#  ---------------------------------------------------------------------
#  The chat only needs the opening ~2.6k characters of a transcript, yet it
#  used to go through the scraper's full `fetch_transcript`, which is slow in
#  three ways that add up to 30–90 s per video:
#
#    1. The library path called `fetch()` (list + pick + download) and, when
#       none of the 17 preferred languages matched, called `list()` AGAIN —
#       two round-trips to the watch page for every non-English video.
#    2. When the library said "this video has NO captions" (very common for
#       Shorts), it still fell through to yt-dlp, which walks a client ladder
#       of full extractions (each one 5–25 s) only to confirm the same thing.
#    3. Nothing was remembered: attaching the same archive video to another
#       thread, or re-opening the app mid-read, paid the whole price again.
#
#  `fetch_transcript_quick` fixes all three: one list + one fetch, an
#  authoritative "no captions" stops immediately, the yt-dlp fallback is a
#  short, light ladder (no DASH/HLS manifests, tight timeouts), and every
#  answer — text OR "none" — is cached on disk.
# ═════════════════════════════════════════════════════════════════════════
import os as _os
import sqlite3 as _sqlite3
import time as _time

_QUICK_LADDER = ([], ["android"], ["tv"])          # the rungs that answer most often
_NONE_TTL = 3 * 24 * 3600                          # re-check "no captions" after 3 days
_cache_lock = threading.Lock()


def _cache_path():
    try:
        from app.config import CONFIG_PATH
        return _os.path.join(_os.path.dirname(CONFIG_PATH), "transcripts_cache.db")
    except Exception:          # noqa: BLE001
        return ""


_CONN = None


def _cache_conn():
    """One shared connection (opened lazily, used only under _cache_lock).
    Opening SQLite per lookup was fine one video at a time; at 16 parallel
    transcripts it became a queue of open/close calls on the lock."""
    global _CONN
    if _CONN is not None:
        return _CONN
    path = _cache_path()
    if not path:
        return None
    conn = _sqlite3.connect(path, timeout=5, check_same_thread=False)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
    except Exception:          # noqa: BLE001
        pass
    conn.execute("CREATE TABLE IF NOT EXISTS tx (vid TEXT PRIMARY KEY, status TEXT,"
                 " text TEXT, kind TEXT, at REAL)")
    _CONN = conn
    return conn


def cached_transcript(video_id):
    """(status, text, err_kind) from the disk cache, or None. The text is the
    full cached transcript; callers trim it to their own view."""
    try:
        with _cache_lock:
            conn = _cache_conn()
            if conn is None:
                return None
            row = conn.execute("SELECT status, text, kind, at FROM tx WHERE vid=?",
                               (video_id,)).fetchone()
    except Exception:          # noqa: BLE001
        return None
    if not row:
        return None
    status, text, kind, at = row
    if text and text != "N/A":
        return (status, text, "")
    if kind == "none" and (_time.time() - float(at or 0)) < _NONE_TTL:
        return ("Not Available", "N/A", "none")
    return None                 # a stale "none" or a past error: try again


def _cache_put(video_id, status, text, kind):
    if kind in ("blocked", "error"):
        return                  # transient — never remember a network failure
    if text and text != "N/A":
        text = str(text)[:_CACHE_TEXT_CAP]
    try:
        with _cache_lock:
            conn = _cache_conn()
            if conn is None:
                return
            conn.execute("INSERT OR REPLACE INTO tx VALUES (?,?,?,?,?)",
                         (video_id, status, text, kind, _time.time()))
            conn.commit()
    except Exception:          # noqa: BLE001
        pass


def _library_quick(video_id, proxy, trim=True):
    """ONE list() + ONE fetch(). Returns (status, text, err_kind) where
    err_kind "none" means YouTube itself said there are no captions."""
    try:
        api_cls, has_new, block_errs, _no_tr = _yta()
        import youtube_transcript_api as mod
    except Exception:          # noqa: BLE001
        return ("Not Available", "N/A", "error")
    # Only these two are an authoritative "this video has no captions"; every
    # other CouldNotRetrieveTranscript subclass (PoToken, age gate, request
    # failed…) is a retrieval problem that yt-dlp may still get past.
    final = tuple(e for e in (getattr(mod, n, None) for n in
                              ("TranscriptsDisabled", "NoTranscriptFound"))
                  if isinstance(e, type))
    try:
        if has_new:
            tlist = _library_api(api_cls, proxy).list(video_id)
        else:
            tlist = api_cls.list_transcripts(video_id)
        tracks = list(tlist)
        if not tracks:
            return ("Not Available", "N/A", "none")
        track = None
        try:
            track = tlist.find_transcript(_TRANSCRIPT_LANGS)
        except Exception:      # noqa: BLE001 — none of ours: take the video's own
            # the original-language track first (manual beats generated)
            track = next((t for t in tracks if not getattr(t, "is_generated", False)),
                         tracks[0])
        text = _join_transcript(track.fetch()).strip()
        if not text:
            return ("Not Available", "N/A", "none")
        status = ("Available (Auto)" if getattr(track, "is_generated", False)
                  else "Available (Manual)")
        return (status, _trim_ends(text) if trim else text, "")
    except block_errs:
        return ("Not Available", "N/A", "blocked")
    except final:
        return ("Not Available", "N/A", "none")
    except Exception:          # noqa: BLE001
        return ("Not Available", "N/A", "error")


def _ytdlp_quick(video_id, proxy=""):
    """A light yt-dlp caption lookup: three rungs, no manifests, tight
    timeouts. Returns text, "" (the player answered: no captions) or None
    (nothing answered)."""
    from app.core.runtime_deps import js_runtime_opts
    from app.core.utils import ensure_yt_dlp_ready
    try:
        from app.core.download import _QuietLogger
        logger = _QuietLogger()
    except Exception:          # noqa: BLE001
        logger = None
    yt_dlp, _ffmpeg = ensure_yt_dlp_ready()
    base = {"quiet": True, "no_warnings": True, "skip_download": True,
            "noplaylist": True, "extractor_retries": 0, "socket_timeout": 12,
            "check_formats": False}
    if logger is not None:
        base["logger"] = logger
    base.update(js_runtime_opts())
    if proxy:
        base["proxy"] = proxy
    url = f"https://www.youtube.com/watch?v={video_id}"
    for clients in _QUICK_LADDER:
        yt_args = {"skip": ["dash", "hls", "translated_subs"]}
        if clients:
            yt_args["player_client"] = clients
        opts = dict(base, extractor_args={"youtube": yt_args})
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=False, process=False)
        except Exception:      # noqa: BLE001 — next rung
            continue
        if not info:
            continue
        subs, auto = info.get("subtitles") or {}, info.get("automatic_captions") or {}
        if not (subs or auto):
            return ""           # the player answered: there really are none
        track, _is_auto = _pick_caption_track(subs, auto)
        if not track:
            return ""
        by_ext = {}
        for fmt in track:
            ext = (fmt.get("ext") or "").lower()
            if ext and ext not in by_ext and fmt.get("url"):
                by_ext[ext] = fmt
        chosen = next((by_ext[e] for e in _CAPTION_FORMATS if e in by_ext), None) \
            or next(iter(by_ext.values()), None)
        if chosen is None:
            return ""
        req = urllib.request.Request(chosen["url"], headers={"User-Agent": "Mozilla/5.0"})
        with _urlopen(req, 15, proxy) as resp:
            raw = resp.read().decode("utf-8", "replace")
        text = _caption_payload_text(raw, (chosen.get("ext") or "").lower())
        return re.sub(r"\s+", " ", html.unescape(text)).strip()
    return None                 # no rung answered at all: unknown, not "none"


def fetch_transcript_quick(video_id):
    """Like fetch_transcript (same return shape, never raises) but tuned for
    the AI Chat: cached, one library round-trip, no yt-dlp when YouTube has
    already said "no captions", and a short yt-dlp ladder otherwise."""
    video_id = str(video_id or "").strip()
    if not video_id:
        return ("Not Available", "N/A", "none")
    hit = cached_transcript(video_id)
    if hit is not None:
        status, text, kind = hit
        return (status, _trim_ends(text) if text and text != "N/A" else text, kind)
    proxy = configured_proxy()
    status, text, err_kind = _library_quick(video_id, proxy, trim=False)
    if not (text and text != "N/A") and err_kind in ("blocked", "error"):
        try:
            with _CAPTION_SLOTS:
                fb = _ytdlp_quick(video_id, proxy)
        except Exception:      # noqa: BLE001
            fb = None
        if fb:
            status, text, err_kind = "Available (Auto)", fb, ""
        elif fb == "":
            status, text, err_kind = "Not Available", "N/A", "none"
    _cache_put(video_id, status, text, err_kind)
    if text and text != "N/A":
        return (status, _trim_ends(text), err_kind)
    return (status, text, err_kind)
