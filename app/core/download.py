"""app.core.download - YouTube Hunter.

UI-free video download (yt-dlp + a bundled ffmpeg) for the QML front-end.

The legacy QWidgets app runs this same fallback ladder inline inside
app/ui/window/page_archive.py::_archive_download_video, and keeps the quality
presets in app/ui/dialogs/download_quality.py — a module that imports
QtWidgets, which the QML app (a QGuiApplication) must not pull in. So the logic
is re-homed here as a plain function driven by callbacks instead of Qt signals.
The legacy copy is deliberately left untouched for the duration of the
migration; once the QWidgets UI is deleted, page_archive can call this instead.
"""

import copy
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.request

from app.core.net import _urlopen, configured_proxy
from app.core.utils import ensure_yt_dlp_ready
from app.core.runtime_deps import (download_engine_missing, find_js_runtime,
                                   js_runtime_opts)
from app.crash import log_crash
from app.i18n import tr

# Sentinel returned as the `message` when a download was stopped by the user
# (via should_cancel) rather than failing. The VM checks for this so it can
# stay silent instead of showing an error toast.
DOWNLOAD_CANCELLED = "__cancelled__"


# Shared cancel registry, keyed by video id. Any ViewModel can flag a running
# download to stop (request_cancel); the worker's progress hook polls it via
# is_cancelled and raises at the next tick, so the stop is real — the yt-dlp
# download actually unwinds instead of continuing in the background. A
# module-level set (guarded by a lock) rather than per-VM state because a
# download started on one page can be stopped from another.
_CANCEL_LOCK = threading.Lock()
_CANCEL_IDS = set()


def request_cancel(video_id):
    """Ask the running download for `video_id` to stop at its next tick."""
    if not video_id:
        return
    with _CANCEL_LOCK:
        _CANCEL_IDS.add(video_id)


def is_cancelled(video_id):
    with _CANCEL_LOCK:
        return video_id in _CANCEL_IDS


def clear_cancel(video_id):
    """Drop a video id from the cancel set — called when a download starts (so a
    stale flag from a previous run doesn't kill it) and when it ends."""
    with _CANCEL_LOCK:
        _CANCEL_IDS.discard(video_id)


# ═════════════════════════════════════════════════════════════════════════
#  DOWNLOAD CONCURRENCY GATE
#  ---------------------------------------------------------------------
#  Every download path in the app — the Downloads page, the Niche Finder grid
#  and the Search Archive grid — starts its own worker thread and calls
#  download_video(). Nothing capped how many ran at once, so a user who clicked
#  download on ten grid cards started ten yt-dlp downloads, each of them itself
#  opening `concurrent_fragment_downloads` connections. A burst like that is
#  exactly what gets a home IP throttled or bot-checked by YouTube, and to the
#  user it just looks like "the app is broken — downloads fail / crawl / some
#  never finish".
#
#  A small global gate fixes that: at most _DL_MAX_CONCURRENT downloads run at
#  once, the rest WAIT their turn (with a visible "Waiting…" status on their
#  row) and start automatically as slots free up. Two is deliberate — it keeps
#  a batch moving without saturating the connection or tripping rate limits.
#
#  A counter + Condition rather than a semaphore: the cap is mutable and a
#  download already holding a slot must release into the SAME object it
#  acquired from (rebuilding a BoundedSemaphore mid-flight would over-release
#  and raise).
# ═════════════════════════════════════════════════════════════════════════
_DL_GATE = threading.Condition()
_DL_ACTIVE = 0
_DL_MAX_CONCURRENT = 2


def set_max_concurrent_downloads(n):
    """Change the cap (>=1). Downloads already running are unaffected."""
    global _DL_MAX_CONCURRENT
    with _DL_GATE:
        _DL_MAX_CONCURRENT = max(1, int(n))
        _DL_GATE.notify_all()


def _acquire_download_slot(on_status, should_cancel):
    """Block until a download slot is free. Returns False only when the user
    cancelled while waiting, so the caller can bail without downloading."""
    global _DL_ACTIVE
    with _DL_GATE:
        queued = _DL_ACTIVE >= _DL_MAX_CONCURRENT
    if queued and on_status:
        # Say so — a row that silently sits at 0% reads as a hang.
        on_status(tr("Waiting for another download to finish…"))
    while True:
        with _DL_GATE:
            if _DL_ACTIVE < _DL_MAX_CONCURRENT:
                _DL_ACTIVE += 1
                return True
            _DL_GATE.wait(0.25)     # short wait so a cancel stays responsive
        if should_cancel is not None and should_cancel():
            return False


def _release_download_slot():
    global _DL_ACTIVE
    with _DL_GATE:
        if _DL_ACTIVE > 0:
            _DL_ACTIVE -= 1
        _DL_GATE.notify()


# Quality presets offered by the picker. `format` goes straight to yt-dlp; the
# height cap on every non-"best" entry keeps yt-dlp's own bestvideo+bestaudio
# fallback intact (still picks the best AUDIO regardless of the video cap)
# rather than pinning an exact height, which fails outright on a video that
# never shipped that resolution.
#
# IMPORTANT — no [vcodec!*=av01] filter here, and no codec-first format_sort.
# Both were downgrade traps: FILTERING out AV1 means a tier that YouTube only
# ships as AV1 (common at 1080p+) is skipped and a much smaller non-AV1 stream
# is handed back instead ("I picked 1080p and got 480p"); and sorting by codec
# BEFORE resolution makes yt-dlp prefer a low-res AVC stream over a high-res
# VP9/AV1 one ("I picked 1440p and got 720p"). Resolution must win. AV1 is
# de-prioritised at TIE-break only, via `format_sort` in download_video (res
# first, then vp9/avc preference) — so the chosen resolution is always honored,
# and AV1 is only used when it is the sole option at that resolution.
#
# Each cap is expressed twice — [height<=N] then [width<=N]. YouTube labels a
# VERTICAL video's quality by its SHORT side, so a "1080p" Short is 1080 wide
# and 1920 tall: a height cap alone would reject it and silently hand back a
# much smaller file. The height branch wins for normal landscape video, so the
# width branch only ever engages where the height one couldn't match (i.e. a
# portrait video whose height exceeds the cap).
#
# CRITICAL — the strict form deliberately has NO bare `best` / `best[height<=N]`
# rung. Those select a PROGRESSIVE (single-file, video+audio) format, and YouTube
# only publishes progressive at 360p (format 18) and occasionally 720p. So the
# moment the adaptive `bestvideo+bestaudio` branch couldn't be satisfied — a
# client that returned a thin format list, a SABR-only response, a transient
# extractor hiccup — the old ladder fell straight through to `best` and quietly
# delivered 360p while REPORTING SUCCESS. That is the "I chose 1080p and got a
# random low quality" bug: nothing ever failed, so no retry rung ever ran.
#
# The loose form (with the progressive rungs) is kept for the genuine case of a
# video that really only ships progressive, and is only reached after every
# client has been tried with the strict form. See download_video().
def _video_stream_filter(container):
    """Extra yt-dlp filter for the VIDEO stream so it fits the chosen container
    without a re-encode. WebM can only hold VP9/AV1, so a webm pick is
    restricted to webm streams first (a later rung lets anything through and
    converts). MP4/MKV take any codec."""
    return "[ext=webm]" if container == "webm" else ""


def _audio_stream_expr(container):
    """Preferred AUDIO stream for a container, with a plain fallback.

    MP4 is deliberately Opus-FREE at every rung. An MP4 pick used to be able to
    end up with an Opus track through one of the unconditional fallbacks, and
    then the merge handed Opus to ffmpeg inside an MP4 — which older ffmpeg
    builds refuse to write without `-strict -2`. That is the "stuck on Merging,
    then an error" report, and it depended entirely on which ffmpeg version the
    install had staged. YouTube always ships an AAC (m4a) track alongside the
    Opus one, so ruling Opus out costs nothing and makes the merge portable to
    any ffmpeg. WebM needs Opus/Vorbis; MKV takes anything.
    """
    if container == "mp4":
        return ["bestaudio[ext=m4a]", "bestaudio[acodec!*=opus]"]
    if container == "webm":
        return ["bestaudio[ext=webm]", "bestaudio"]
    return ["bestaudio"]


def _format_sort(container):
    """The ONE yt-dlp `format_sort` for a container — shared by the download,
    its per-rung pre-flight and the quality picker's size probe, so all three
    pick the exact same streams. (They used to disagree: the picker ranked
    streams its own way, the pre-flight had no sort at all, so the size shown
    in the picker described a different stream from the one downloaded.)

    Resolution ALWAYS leads (see the downgrade notes above), then frame rate —
    without "fps" here a codec preference outranked it and a 1080p60 pick could
    arrive as 1080p30. Codec is a TIE-BREAK only:

      * MP4 prefers H.264 at equal resolution/fps. The MP4 path converts any
        VP9/AV1 stream to H.264 afterwards (_convert_for_editors), so taking
        VP9 when an H.264 encode of the same tier exists meant a slow re-encode
        AND a final file whose size nobody could predict. YouTube ships H.264
        up to 1080p, so ≤1080p MP4 picks are now a plain remux — the size in
        the picker is the size on disk. 1440p/4K exist only as VP9/AV1, so
        those still convert (to a predictable bitrate, see _editor_target_kbps).
      * MKV / WEBM keep the original VP9-over-AV1 preference.

    "proto:http_dash_segments" closes the loop on the size promise: at equal
    everything YouTube serves the same rendition twice — as DASH segments
    (carrying an exact filesize) and as an HLS playlist (carrying NONE, only a
    declared tbr that OVER-states the served bytes; measured: itag 231 declared
    862 kbps, landed at ~505). yt-dlp's own proto ranking prefers m3u8_native
    (7) over dash segments (6), so without this tie-break the download — and
    with it the picker's number — could land on the unpredictable HLS copy.
    DASH is also the transport the ladder fragments (dashy), so it is the one
    whose byte totals the progress bar can promise.
    """
    # "lang" leads so a dubbed video always gets its ORIGINAL audio track
    # (yt-dlp gives it the top language_preference). Video streams carry no
    # language, so this never changes which picture stream is picked.
    if container == "mp4":
        return ["lang", "res", "fps", "vcodec:h264", "acodec:aac",
                "proto:http_dash_segments"]
    return ["lang", "res", "fps", "vcodec:vp9", "proto:http_dash_segments"]


def _video_format(cap, container="mp4"):
    """Strict format expression for a resolution cap (short side, px).

    Adaptive streams only — never silently degrades to a 360p progressive file.

    ORIENTATION-AWARE. The old form was `bv[height<=N]+ba / bv[width<=N]+ba`,
    on the theory that the width branch only runs when the height branch can't
    match. But on a VERTICAL video the height branch nearly always CAN match —
    just with a much smaller stream (a 608x1080 rendition satisfies
    height<=1080) — so a "1080p" Short (1080x1920) downloaded as 608p, failed
    the quality check on every rung and the download died. Landscape streams
    (aspect_ratio >= 1) are now capped by height, portrait ones by width, so
    the cap always applies to the SHORT side. The old pair is kept as the last
    alternative for a yt-dlp/format that doesn't report aspect_ratio.
    """
    vf = _video_stream_filter(container)
    a_alts = _audio_stream_expr(container)
    alts = []
    for a in a_alts:
        alts.append(f"bestvideo[height<={cap}][aspect_ratio>=1]{vf}+{a}")
        alts.append(f"bestvideo[width<={cap}][aspect_ratio<1]{vf}+{a}")
    if vf:
        # Nothing native for webm at this resolution: take any codec, the
        # converter postprocessor turns it into webm afterwards.
        alts.append(f"bestvideo[height<={cap}][aspect_ratio>=1]+bestaudio")
        alts.append(f"bestvideo[width<={cap}][aspect_ratio<1]+bestaudio")
    # The unconditional rungs reuse the container's LAST audio alternative
    # rather than a bare `bestaudio` — for MP4 that is the Opus-free one, and
    # this is exactly where Opus used to sneak back in (see
    # _audio_stream_expr for why that turned the merge into a failure).
    alts.append(f"bestvideo[height<={cap}]+{a_alts[-1]}")
    alts.append(f"bestvideo[width<={cap}]+{a_alts[-1]}")
    return "/".join(alts)


def _video_format_loose(cap, container="mp4"):
    """Last-resort expression: allows the progressive single-file formats too,
    for a video that genuinely has no adaptive streams at all."""
    return (
        _video_format(cap, container) + "/"
        f"best[height<={cap}]/"
        f"best[width<={cap}]/"
        f"best"
    )


def _best_format(container="mp4"):
    """'Best available' expression for a container (no resolution cap)."""
    vf = _video_stream_filter(container)
    a_alts = _audio_stream_expr(container)
    alts = [f"bestvideo{vf}+{a}" for a in a_alts]
    # Same Opus-free guard as _video_format's final rungs.
    alts.append(f"bestvideo+{a_alts[-1]}")
    return "/".join(alts)


def _best_format_loose(container="mp4"):
    """'Best available' with the progressive rungs appended — the LOOSE form.

    The strict form is adaptive-only on purpose, so a thin format list can never
    masquerade as "the best". But that made "Best available" impossible on the
    clients that keep working when the web side is blocked: android /
    android_vr / tv frequently expose ONLY a muxed progressive file, where
    `bestvideo+bestaudio` matches nothing and yt-dlp answers "Requested format
    is not available" — so the one preset a blocked user would pick failed on
    exactly the machines that needed the fallback.

    Verified live on an old 240p upload: `--player-client android` fails the
    strict form and delivers format 18 (240p, AVC+AAC) with this one. Reached
    only after every client has been tried with the strict form, so it cannot
    downgrade a download that would otherwise have been delivered.
    """
    return f"{_best_format(container)}/best"


DOWNLOAD_QUALITY_PRESETS = [
    {"key": "best", "label": "Best available", "icon": "hd",
     "sub": "Highest resolution + best audio", "audio_only": False,
     # height 0 means "resolve it per video" — download_video() probes the real
     # top tier (probe_max_height) and then verifies against it, exactly like an
     # explicit pick. Without that, "best" had no target at all: nothing could
     # count as falling short, so a 720p progressive file passed for a 1440p video.
     "height": 0,
     "format": "bestvideo+bestaudio",
     # NOTE: for video presets these two literals are not what runs — with_container()
     # rebuilds both from the container choice (_best_format / _best_format_loose).
     # They are kept so a caller that reads a preset directly still sees something
     # sane. The loose form is the one that carries the trailing progressive rung,
     # and that is where a blocked-network download is saved: see _best_format_loose.
     "format_loose": "bestvideo+bestaudio/best"},
    {"key": "2160p", "label": "2160p", "icon": "hd",
     "sub": "4K — very large file", "audio_only": False,
     "height": 2160, "format": _video_format(2160),
     "format_loose": _video_format_loose(2160)},
    {"key": "1440p", "label": "1440p", "icon": "hd",
     "sub": "2K QHD", "audio_only": False,
     "height": 1440, "format": _video_format(1440),
     "format_loose": _video_format_loose(1440)},
    {"key": "1080p", "label": "1080p", "icon": "movie",
     "sub": "Full HD", "audio_only": False,
     "height": 1080, "format": _video_format(1080),
     "format_loose": _video_format_loose(1080)},
    {"key": "720p", "label": "720p", "icon": "smart_display",
     "sub": "HD — good balance of quality and size", "audio_only": False,
     "height": 720, "format": _video_format(720),
     "format_loose": _video_format_loose(720)},
    {"key": "480p", "label": "480p", "icon": "sd",
     "sub": "Standard definition — smallest video file", "audio_only": False,
     "height": 480, "format": _video_format(480),
     "format_loose": _video_format_loose(480)},
    {"key": "360p", "label": "360p", "icon": "sd",
     "sub": "Low definition — smallest video file", "audio_only": False,
     "height": 360, "format": _video_format(360),
     "format_loose": _video_format_loose(360)},
    {"key": "audio", "label": "Audio only", "icon": "music_note",
     "sub": "MP3 — no video, smallest file", "audio_only": True,
     "height": 0, "format": "bestaudio/best",
     "format_loose": "bestaudio/best"},
]

# Resolution buckets, high → low. A format's short side is filed under the
# largest bucket it reaches (so a 1152p encode counts as 1080p) — the same thing
# the [height<=N] caps above do at download time.
_QUALITY_BUCKETS = ("2160p", "1440p", "1080p", "720p", "480p", "360p")


def quality_by_key(key):
    """Preset for a key. A stored key may carry its output format
    ("1080p@mkv") — then a copy with that container attached is returned, so a
    resumed download keeps the format it was started with."""
    key = str(key or "")
    # v1.2: "1080p@mkv~ar" — a picked dub (audio language) rides along too
    key, _, lang = key.partition("~")
    base, _, container = key.partition("@")
    for p in DOWNLOAD_QUALITY_PRESETS:
        if p["key"] == base:
            q = with_container(p, container) if container else p
            return with_audio_lang(q, lang) if lang else q
    return DOWNLOAD_QUALITY_PRESETS[0]


# ── v1.2: audio language (dubbed videos) ────────────────────────────────────
# The quality picker lets the user choose which audio track of a dubbed video
# to download. The choice is per video and lives here (not in a ViewModel) so
# every page that starts a download — Niche Finder, Search Archive, Downloads —
# reads the same answer without each carrying its own copy.
_audio_lang_pick = {}            # video_id -> language code ("" = original)
_audio_lang_lock = threading.Lock()


def set_audio_lang(video_id, lang):
    if not video_id:
        return
    with _audio_lang_lock:
        if lang:
            _audio_lang_pick[video_id] = str(lang)
        else:
            _audio_lang_pick.pop(video_id, None)


def audio_lang_for(video_id):
    with _audio_lang_lock:
        return _audio_lang_pick.get(video_id or "", "")


def with_audio_lang(quality, lang_or_video_id=None, *, video_id=None):
    """A COPY of a (container-attached) quality that downloads the `lang`
    audio track. Pass `video_id=` to use the picker's saved choice for it.
    "" / None = the original track (the quality is returned unchanged)."""
    lang = lang_or_video_id
    if video_id is not None:
        lang = audio_lang_for(video_id)
    lang = str(lang or "")
    if not lang or not quality:
        return quality
    from app.core.audio_tracks import lang_format_expr
    q = dict(quality)
    q["audio_lang"] = lang
    if q.get("format"):
        q["format"] = lang_format_expr(q["format"], lang)
    if q.get("format_loose"):
        q["format_loose"] = lang_format_expr(q["format_loose"], lang)
    return q


_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
       "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")

# ── the YouTube client ladder (the ONE list, shared by every caller) ────────
# YouTube blocks per INNERTUBE client, and WHICH client is refused changes by
# network, by country and by the week. Measured on one machine in a single
# session: the default set answered, while `web`, `ios`, `mweb` and
# `web_safari` all came back "No video formats found!" — and on another the
# only client that answered was `android_vr`. That is the whole "one video
# downloads, the next one errors, randomly" complaint: a ladder that is missing
# the client YouTube currently allows on THAT user's network fails there while
# working here.
#
# So the list is deliberately WIDE. Every entry is a real client name from
# yt-dlp's own INNERTUBE_CLIENTS table — an unknown name is silently ignored by
# yt-dlp, which then just runs its default set, so a typo looks like a working
# rung that is really a duplicate (`tv_embedded` was exactly that; it is NOT a
# client in this yt-dlp build).
#
# v1.0.1 — SLIMMED. The app now REQUIRES a JS runtime (deno) before any
# download starts (download_engine_missing); the PO Token helper is optional
# but recommended, and when installed the web-family clients get real BotGuard
# tokens and the JS challenge is solved. That makes most of the old 12-rung
# ladder dead weight: `android` and `ios` need DroidGuard / iOSGuard tokens the
# helper cannot mint (they 403 on the CDN now), `web` / `tv_simply` are already
# inside yt-dlp's default set, and `visionos` never answered anywhere. Every
# dead rung was a full player-response + JS-challenge round trip (2-6 s) on the
# failure path — a blocked video walked ~20 of them before giving up.
#
# What is left, in order: the default multi-client set (richest list), then
# the token-free / token-backed clients that each sit on a DIFFERENT block
# list. Callers still gate every rung on the formats it can actually see, so
# this order costs speed at worst, never quality.
CLIENT_LADDER = (
    [],                              # yt-dlp defaults (+ PO tokens via bgutil)
    ["tv"],                          # TV key — needs no PO token
    ["web_safari"],                  # HLS-capable web client, token-backed
    ["android_vr"],                  # separate key, no PO token needed
    ["mweb"],                        # mobile web, token-backed
)

# Clients that keep answering when the web side is blocked — used by the
# non-fragmented and progressive fallback rungs. Both need no PO token.
BYPASS_CLIENTS = (["android_vr"], ["tv"])

# ── "thin" format lists + the sticky client (v3.41.2) ───────────────────────
# On some networks (seen on Belgian and other VPN/datacenter exits) YouTube
# doesn't REFUSE a client, it answers it with a THIN list: just the muxed 360p
# progressive file (itag 18), or adaptive streams capped low, because that
# client is missing a PO token / is being pushed to SABR on that IP. Nothing
# errors, so the old "first attempt with any formats wins" logic took that 360p
# list as the truth and the picker showed 360p as the best this video has; on a
# US exit the same client got the full list. The fix is to JUDGE each answer:
# a list is rich only when it has video-only adaptive streams above 360p, and a
# thin one keeps the ladder going (with a time budget) until a client that
# sees the real list answers. The client that answered richly is then tried
# FIRST for the rest of the session, so the next video on the same network
# doesn't walk the ladder again.
_THIN_PX = 360                  # a best of <= this, with no adaptive stream above it, is suspect
_PROBE_BUDGET_S = 30.0          # stop hunting for a richer list after this long
_STICKY_TTL_S = 30 * 60         # the network can change (VPN hop): re-learn after 30 min
_sticky = {"clients": None, "ts": 0.0}
_sticky_lock = threading.Lock()


def _info_richness(info):
    """(best_px, rich) for one extraction's format list.

    best_px — the highest short side any VIDEO format offers.
    rich    — True when there is at least one video-only (adaptive) stream above
              _THIN_PX: proof that this client was given the real list, not the
              itag-18-only fallback a flagged IP gets.
    """
    best = 0
    rich = False
    for f in (info or {}).get("formats") or []:
        if (f.get("vcodec") or "none") == "none":
            continue
        px = _fmt_short_side(f)
        best = max(best, px)
        if px > _THIN_PX and (f.get("acodec") or "none") == "none":
            rich = True
    return best, rich


def note_good_clients(clients):
    """Remember the client set that just returned a rich list / delivered."""
    if clients is None:
        return
    with _sticky_lock:
        _sticky["clients"] = list(clients)
        _sticky["ts"] = time.time()


def client_ladder():
    """CLIENT_LADDER with this session's last good client moved to the front."""
    with _sticky_lock:
        good = _sticky["clients"]
        fresh = good is not None and (time.time() - _sticky["ts"]) < _STICKY_TTL_S
    if not fresh:
        return list(CLIENT_LADDER)
    rest = [c for c in CLIENT_LADDER if list(c) != good]
    return [good] + rest

# Browsers whose cookie DB yt-dlp can read. Chrome-family DBs may be locked
# (browser running) or undecryptable (App-Bound Encryption on Chrome 127+), so
# the ladder tries all of them and Firefox — whose store has neither problem —
# is the one most likely to succeed.
# v1.0.1: trimmed to the stores that actually decrypt on Windows. Chrome 127+
# (and every Chromium fork that adopted App-Bound Encryption) refuses yt-dlp
# outright, so walking vivaldi/chromium/opera only added failing rungs.
_COOKIE_BROWSERS = ("firefox", "edge", "chrome", "brave")


def friendly_extract_error(err_text):
    """Turn an engine failure into something the user can act on.

    Shared by the download ladder and the cutter: a raw
    "[youtube] <id>: Sign in to confirm you're not a bot. Use
    --cookies-from-browser …" is a developer message, and on a customer's
    machine it is the whole visible outcome of the button they pressed.
    """
    _missing = download_engine_missing()
    if _missing:
        return _missing
    if _is_bot_or_403(err_text):
        return tr(
            "YouTube blocked this download (bot check). Close your browser "
            "completely and try again — or set “Use cookies from browser” in "
            "Settings, or try a different VPN location.")
    if _is_drm(err_text):
        return tr(
            "YouTube only offered DRM-protected formats for this video, so it "
            "can't be downloaded. This sometimes clears up on its own — try "
            "again later, or set “Use cookies from browser” in Settings.")
    if _is_cookie_problem(err_text):
        return tr(
            "The browser's cookies couldn't be read. Close the browser "
            "completely (Chrome/Edge/Firefox) and try again, or set another "
            "browser in Settings.")
    return str(err_text or "")


def _is_retryable(err_text):
    """Errors worth retrying with the NEXT extraction client rather than giving
    up — YouTube throws these per-client, so another client often just works.

    "No video formats found!" is the important one and it used to be MISSING:
    that is the exact answer YouTube gives a client it has decided to withhold
    formats from (throttled/SABR response), it is NOT one of yt-dlp's usual
    "blocked" messages, and without it the ladder's `break` fired on the FIRST
    rung. So a machine whose default client came back empty never even tried
    android/android_vr/tv — the "one video downloads, the next one errors, and
    the same link works on another PC" report.
    """
    t = (err_text or "").lower()
    needles = (
        "not a bot", "sign in to confirm", "http error 403", "forbidden",
        "login_required", "unable to download video data", "drm protected",
        "drm-protected", "drm", "page needs to be reloaded", "reload", "nsig",
        "n challenge", "unable to extract", "player response",
        "requested format is not available",
        "failed to extract any player response",
        "no video formats found", "no formats found", "no playable",
    )
    return any(n in t for n in needles)


def _is_bot_or_403(err_text):
    t = (err_text or "").lower()
    return ("not a bot" in t or "sign in to confirm" in t
            or "http error 403" in t or "forbidden" in t
            or "login_required" in t)


def _is_cookie_problem(err_text):
    """True when a rung failed because BROWSER COOKIES couldn't be read — not
    because the download itself failed.

    This distinction decides whether the ladder keeps going. yt-dlp reports these
    as plain `ERROR:` lines, and the previous word list missed the most common one
    on Windows:

        Failed to decrypt with DPAPI. See …/issues/10927
        Could not copy Chrome cookie database. See …/issues/7271

    Neither is retryable by `_is_retryable`, and the second-to-last only matched by
    accident (it contains "cookie"), so a DPAPI failure hit the ladder's `break` and
    **stopped the whole download on that rung**. That is why closing Chrome broke
    downloads: with the browser closed the DB copy succeeds and decryption fails
    instead.
    """
    t = (err_text or "").lower()
    needles = (
        "dpapi", "cookie", "could not copy", "could not find", "unable to open",
        "no such", "profile", "keyring", "decrypt",
    )
    return any(n in t for n in needles)


def _is_cookie_db_locked(err_text):
    """A cookie failure the USER can fix by closing their browser. Worth saying so
    explicitly rather than showing a generic error."""
    t = (err_text or "").lower()
    return ("locked" in t or "being used" in t or "could not copy" in t
            or "permission" in t or "dpapi" in t)


def _is_drm(err_text):
    return "drm" in (err_text or "").lower()


def _fmt_short_side(f):
    """A format's YouTube-facing resolution number.

    YouTube labels a vertical video by its SHORT side (a "1080p" Short is
    1080×1920), so the quality a user recognises is min(width, height) — using
    height alone would file every Short one or two tiers too high.
    """
    h = f.get("height") or 0
    w = f.get("width") or 0
    if h and w:
        return min(h, w)
    return h or w or 0


def _delivered_short_side(info, requested_downloads):
    """The resolution actually delivered, as YouTube would label it.

    yt-dlp reports the merged result on the top-level info dict, but a
    video+audio merge can leave width/height there unset — the per-download
    entries in `requested_downloads` then carry them. Checks both, and falls back
    to parsing the resolution out of `format`/`resolution` strings ("1920x1080").
    0 means "couldn't tell", which callers must treat as "don't judge it".
    """
    for src in list(requested_downloads or []) + [info or {}]:
        px = _fmt_short_side(src)
        if px:
            return px
    for src in list(requested_downloads or []) + [info or {}]:
        for key in ("resolution", "format", "format_note"):
            m = re.search(r"(\d{3,4})\s*[x×]\s*(\d{3,4})", str(src.get(key) or ""))
            if m:
                return min(int(m.group(1)), int(m.group(2)))
            m = re.search(r"\b(\d{3,4})p\b", str(src.get(key) or ""))
            if m:
                return int(m.group(1))
    return 0


def _quality_floor(want_px):
    """The lowest resolution that still counts as delivering `want_px`.

    EXACT, with only the tolerance YouTube's own odd encodes demand: a "1080p"
    stream of a non-16:9 video is often 1072 or 1088 tall, so anything within 10%
    of the request passes and everything else fails. The same 10% window
    `_resolution_label()` uses, so the label and the verdict always agree.

    This used to return the bucket BELOW the request, which meant a 1080p request
    quietly accepted a 720p file as "close enough" — the whole reason a picked
    quality could arrive as something else. Shared by the pre-flight rung check and
    the post-download verification so the two can never disagree.
    """
    if not want_px:
        return 0
    return int(want_px * 0.9)


def _quality_shortfall(quality, got_px, want_px=0):
    """True when the delivered resolution is below what was asked for.

    `want_px` overrides the preset's own height — needed for the "best available"
    pick, whose preset carries height 0 but whose real target is resolved per video
    by probing (see download_video). Without that override "best" had no target at
    all, so nothing could ever count as falling short and a 720p progressive file
    was accepted for a video whose top tier was 1440p.

    got_px == 0 means the probe couldn't tell, which must not be read as a failure.
    """
    want = int(want_px or quality.get("height") or 0)
    if not want or not got_px or quality.get("audio_only"):
        return False
    return got_px < _quality_floor(want)


def _remove_quietly(path):
    """Delete a partial/undersized download so a retry rung starts clean."""
    if not path:
        return
    for p in (path, path + ".part"):
        try:
            if os.path.isfile(p):
                os.remove(p)
        except OSError:
            pass


def _bucket_for(px):
    """The preset key a format's resolution belongs to, or "" if below 360p."""
    for key in _QUALITY_BUCKETS:
        if px >= int(key[:-1]):
            return key
    return ""


def _fmt_bytes_info(f):
    """A format's size in bytes plus whether that number is EXACT.

    Returns (n, exact). Exact means yt-dlp reported a real `filesize`
    (typically an HTTP content-length); anything else — `filesize_approx`,
    or bitrate × duration — is a guess that routinely overshoots several-fold
    on adaptive streams, so callers must treat it as "unknown" whenever an
    honest number matters (progress totals, picker sizes). 0/False when
    nothing is available.
    """
    n = f.get("filesize") or 0
    if n:
        return int(n), True
    n = f.get("filesize_approx") or 0
    if n:
        return int(n), False
    tbr, dur = f.get("tbr") or 0, f.get("_duration") or 0
    if tbr and dur:
        return int(tbr * 1000 / 8 * dur), False
    return 0, False


def _fmt_bytes(f):
    """A format's size in bytes — exact if yt-dlp knows it, else its estimate,
    else derived from bitrate × duration. 0 when nothing is available."""
    n, _exact = _fmt_bytes_info(f)
    return n


class _QuietLogger:
    """Absorbs yt-dlp's own console output.

    `quiet: True` and `no_warnings: True` silence yt-dlp's PROGRESS chatter but not
    its `ERROR:` lines, which still go to stderr. On this ladder most of those
    errors are not failures at all — a rung failing over to the next client is the
    design — so they only ever misled anyone reading the log. Every real failure
    already reaches the user through the return value and `on_status`, so nothing is
    lost by swallowing them here.

    An optional `on_status` callback routes the genuinely interesting lines onward.
    """

    def __init__(self, on_status=None):
        self._on_status = on_status

    def debug(self, msg):
        pass

    def info(self, msg):
        pass

    def warning(self, msg):
        pass

    def error(self, msg):
        # Deliberately not forwarded: the caller decides what to tell the user once
        # the whole ladder has run, and a per-rung error is not that decision.
        pass


# ── size prediction ─────────────────────────────────────────────────────
# The picker's number has to be the size of the file that lands on disk, not
# of the streams on YouTube's servers. Those differ whenever a postprocessor
# re-encodes: an MP4 pick of a VP9/AV1 tier is converted to H.264, an audio
# pick to MP3/WAV/FLAC. So the probe predicts the OUTPUT, using the same
# constants the converters use — they live here, once, for both sides.
_EDITOR_AUDIO_KBPS = 192
# H.264 needs more bits than VP9/AV1 for the same picture. The conversion
# targets source-bitrate × factor (ABR), which (a) keeps quality on par with
# the source and (b) makes the output size knowable in advance. The old
# CRF-18 encode had no size target at all — a 1440p file could come out 2-3×
# what the picker showed.
_EDITOR_VCODEC_FACTOR = {"vp9": 1.35, "av1": 1.6, "hevc": 1.3}
# Container overhead of a merge/remux (moov/cues/index), measured well under 1%.
_MUX_OVERHEAD = 1.004


def _vcodec_family(vcodec):
    v = str(vcodec or "").strip().lower()
    if v.startswith(("avc", "h264")):
        return "h264"
    if v.startswith(("vp9", "vp09")):
        return "vp9"
    if v.startswith(("av01", "av1")):
        return "av1"
    if v.startswith(("hev", "hvc", "h265", "hevc")):
        return "hevc"
    return v


def _acodec_family(acodec):
    a = str(acodec or "").strip().lower()
    if a.startswith(("mp4a", "aac")):
        return "aac"
    if a.startswith("opus"):
        return "opus"
    return a


def _editor_target_kbps(src_kbps, vcodec):
    """Video bitrate the H.264 editor conversion encodes at. Shared by the
    converter and the picker's prediction so they can never disagree."""
    if not src_kbps or src_kbps <= 0:
        return 0
    factor = _EDITOR_VCODEC_FACTOR.get(_vcodec_family(vcodec), 1.35)
    return max(300, int(round(src_kbps * factor)))


def _stream_kbps(f, duration):
    """A stream's average bitrate. Bytes ÷ duration first (that is the real
    average of THIS file), then the reported vbr/abr/tbr."""
    n = f.get("filesize") or f.get("filesize_approx") or 0
    if n and duration:
        return n * 8 / duration / 1000
    return float(f.get("vbr") or f.get("abr") or f.get("tbr") or 0)


def _picked_streams(info):
    """The streams yt-dlp's selection chose: the merge pair, or the one file."""
    picked = [p for p in (info.get("requested_formats") or []) if p]
    if not picked and (info.get("url") or info.get("format_id")):
        picked = [info]
    return picked


def _split_av(picked):
    video = next((p for p in picked if (p.get("vcodec") or "none") != "none"), None)
    audio = next((p for p in picked if (p.get("acodec") or "none") != "none"
                  and p is not video), None)
    if audio is None and video is not None and (video.get("acodec") or "none") != "none":
        audio = video                       # progressive: one stream carries both
    return video, audio


def _predict_output(quality, picked, duration):
    """(bytes, exact, detail) for the file this pick will leave on disk.

    `exact` is True when no re-encode happens and every input byte count is a
    real reported filesize — the output is then the inputs plus a sub-1%
    container overhead. Every re-encode is an estimate and says so.
    """
    container = quality.get("container") or ""
    video, audio = _split_av(picked)
    sizes = [_fmt_bytes_info(dict(p, _duration=duration)) for p in picked]
    raw = sum(n for n, _x in sizes)
    raw_exact = bool(sizes) and all(x and n > 0 for n, x in sizes)

    if quality.get("audio_only"):
        if audio is None:
            return 0, False, ""
        fam = _acodec_family(audio.get("acodec"))
        abr = int(round(_stream_kbps(audio, duration)))
        src = f"{fam.upper()} {abr} kbps" if abr else fam.upper()
        if container == "mp3":
            # FFmpegExtractAudio with quality "192" encodes CBR 192 kbps.
            return (int(duration * 192000 / 8) if duration else 0, False,
                    f"{src} → MP3 192 kbps")
        if container == "m4a":
            if fam == "aac":                  # copied, not re-encoded
                return int(raw * _MUX_OVERHEAD), raw_exact, f"{src} (no re-encode)"
            return (int(duration * 192000 / 8) if duration else 0, False,
                    f"{src} → AAC 192 kbps")
        if container == "opus":
            if fam == "opus":
                return int(raw * _MUX_OVERHEAD), raw_exact, f"{src} (no re-encode)"
            return raw, False, f"{src} → Opus"
        if container in ("wav", "flac"):
            asr = int(audio.get("asr") or 48000)
            ch = int(audio.get("audio_channels") or 2)
            pcm = int(duration * asr * ch * 2) + 44 if duration else 0
            if container == "wav":            # PCM s16: size is arithmetic
                return pcm, bool(pcm), f"{src} → WAV {asr // 1000} kHz"
            # FLAC compresses music to roughly 55-65% of PCM; it depends on
            # the audio itself, so this one can only ever be an estimate.
            return int(pcm * 0.6), False, f"{src} → FLAC"
        return raw, raw_exact, src

    if video is None:
        return raw, False, ""
    vfam = _vcodec_family(video.get("vcodec"))
    w, h = video.get("width") or 0, video.get("height") or 0
    fps = int(round(video.get("fps") or 0))
    detail = " · ".join(x for x in (
        f"{w}×{h}" if w and h else "",
        f"{fps}fps" if fps else "",
        {"h264": "H.264", "vp9": "VP9", "av1": "AV1", "hevc": "HEVC"}.get(vfam, vfam.upper()),
    ) if x)

    if container == "mp4" and _needs_editor_conversion(vfam):
        # Will be converted to H.264 by _convert_for_editors at a target
        # bitrate — so the output size is that bitrate × duration.
        vkbps = _editor_target_kbps(_stream_kbps(video, duration), vfam)
        if audio is not None and _acodec_family(audio.get("acodec")) == "aac":
            a_bytes = _fmt_bytes_info(dict(audio, _duration=duration))[0]
        else:
            a_bytes = duration * _EDITOR_AUDIO_KBPS * 1000 / 8
        if not (vkbps and duration):
            return raw, False, detail + " → H.264"
        total = (duration * vkbps * 1000 / 8 + a_bytes) * _MUX_OVERHEAD
        return int(total), False, detail + " → H.264"
    if container == "webm" and vfam not in ("vp9", "av1"):
        # FFmpegVideoConvertor re-encodes to VP9 — size follows the encoder.
        return raw, False, detail + " → VP9"
    return int(raw * _MUX_OVERHEAD), raw_exact, detail


def _probe_attempts(cookies_browser):
    """The extraction order the DOWNLOAD's first rungs use (cookies, then the
    client ladder, all with formats=dashy). Probing the same way is what makes
    the picker see the same format list the download will choose from —
    `dashy` in particular drops formats without a content length, which can
    change which stream wins."""
    attempts = []
    if cookies_browser:
        attempts.append({"cookies": cookies_browser, "clients": None})
    for clients in client_ladder():
        attempts.append({"cookies": None, "clients": clients})
    return attempts


# ── v3.41.3: probe cache (faster "Preparing…") ─────────────────────────────
# The quality picker already walks the client ladder for a video; a "Best
# available" download then used to walk the SAME ladder again (probe_max_height)
# a few seconds later, before a single byte moved. A RICH answer is kept for a
# few minutes and handed back instead. Stream URLs stay valid for hours, and
# only rich lists are cached, so a throttled answer is never pinned.
_PROBE_CACHE_TTL_S = 15 * 60
_PROBE_CACHE_MAX = 12
_probe_cache = {}               # key -> (monotonic_ts, info)
_PROBE_TAG = "_yth_probe"       # {clients, cookies, dashy} of a cached answer
# A fallback answer (no client returned an adaptive stream above 360p) carries
# these so the picker can explain WHY the ladder is short instead of silently
# presenting 360p as the video's real ceiling:
#   limited  → the low ceiling is likely this IP/VPN being throttled
#   agreed   → several clients agreed on the same ceiling: likely the upload
#   best_px  → the highest resolution actually answered
# A thin answer is never cached, so "check again" after changing IP really does
# ask YouTube fresh instead of reusing the capped result.
_PROBE_LIMITED = "_yth_probe_limited"
_PROBE_AGREED = "_yth_probe_agreed"
_PROBE_BEST_PX = "_yth_probe_best_px"
_probe_cache_lock = threading.Lock()


def _probe_cache_key(url, proxy_url, cookies_browser):
    m = re.search(r"(?:v=|youtu\.be/|/shorts/|/embed/)([\w-]{11})", url or "")
    return ((m.group(1) if m else (url or "").strip()),
            proxy_url or "", cookies_browser or "")


def light_copy_info(info):
    """A private copy of a yt-dlp info dict that is safe to run format
    selection on, WITHOUT copy.deepcopy.

    deepcopy of a YouTube info dict (hundreds of formats with fragment lists,
    ~150 caption languages x formats, heatmap, thumbnails ...) is seconds of
    pure-Python work that holds the GIL, and the Qt GUI thread needs that same
    GIL for every binding it evaluates: the whole window froze for 1-4 s each
    time a cached read was copied (the "cut freezes the app, randomly" report:
    random because only a cache hit/fill does the copy). Selection only ever
    writes into the top-level dict and into individual format dicts, so those
    are copied; the big read-only parts (captions, fragments, thumbnails) are
    shared."""
    if not isinstance(info, dict):
        return info
    out = dict(info)
    for key in ("formats", "requested_formats", "requested_downloads"):
        lst = info.get(key)
        if isinstance(lst, list):
            out[key] = [_light_copy_fmt(f) for f in lst]
    return out


def _light_copy_fmt(f):
    if not isinstance(f, dict):
        return f
    g = dict(f)
    hh = g.get("http_headers")
    if isinstance(hh, dict):
        g["http_headers"] = dict(hh)
    return g


def _probe_cache_get(key):

    with _probe_cache_lock:
        hit = _probe_cache.get(key)
        if not hit:
            return None
        if time.monotonic() - hit[0] > _PROBE_CACHE_TTL_S:
            _probe_cache.pop(key, None)
            return None
        info = hit[1]
    # A private copy per caller: the picker and a download may run selection
    # on the same video at the same moment.
    try:
        return light_copy_info(info)
    except Exception:                     # noqa: BLE001 — cache is best-effort
        return None


def _probe_cache_put(key, info):
    try:
        info = light_copy_info(info)
    except Exception:                     # noqa: BLE001 — cache is best-effort
        return
    with _probe_cache_lock:
        _probe_cache[key] = (time.monotonic(), info)
        if len(_probe_cache) > _PROBE_CACHE_MAX:
            oldest = min(_probe_cache, key=lambda k: _probe_cache[k][0])
            _probe_cache.pop(oldest, None)


def fetch_probe_info(url, proxy_url="", cookies_browser="", use_cache=True):
    """One metadata extraction for the quality picker. Blocking.

    Returns (info, error). The info dict is reusable: qualities_from_info()
    runs selection on it locally, so switching MP4/MKV/MP3… in the picker
    recomputes sizes without another request to YouTube.

    v3.41.3: a rich answer is cached per video for _PROBE_CACHE_TTL_S, so the
    download that follows the picker (and "Best available"'s height check)
    doesn't pay for the same extraction twice.
    """
    ckey = _probe_cache_key(url, proxy_url, cookies_browser)
    if use_cache:
        cached = _probe_cache_get(ckey)
        if cached is not None:
            return cached, ""
    try:
        yt_dlp, _ffmpeg = ensure_yt_dlp_ready()
    except Exception as exc:            # noqa: BLE001 — surfaced to the caller
        return None, str(exc)

    base = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "http_headers": {"User-Agent": _UA},
        "extractor_retries": 2,
        "logger": _QuietLogger(),
    }
    base.update(js_runtime_opts())   # solve YouTube's JS challenge (deno/node/bun/qjs)
    if proxy_url:
        base["proxy"] = proxy_url

    last_err = ""
    started = time.monotonic()
    # The richest THIN answer so far (best_px, n_formats, info, clients): used
    # only if no client gives a rich list (a video that really tops out at
    # 360p, or a network where every client is capped).
    fallback = None
    thin_votes = {}     # best_px -> how many distinct clients agreed on it
    attempts = [dict(a, dashy=True) for a in _probe_attempts(cookies_browser)]
    # Safety net: the plain extraction the picker used before — it is what
    # worked on every machine, so a dashy-specific failure can't blank the
    # picker any more.
    attempts.append({"cookies": None, "clients": None, "dashy": False})
    for attempt in attempts:
        opts = dict(base)
        yt_args = {"formats": ["dashy"]} if attempt["dashy"] else {}
        if attempt["clients"]:
            yt_args["player_client"] = attempt["clients"]
        if attempt["cookies"]:
            opts["cookiesfrombrowser"] = (attempt["cookies"],)
        if yt_args:
            opts["extractor_args"] = {"youtube": yt_args}
        else:
            opts.pop("extractor_args", None)
        if fallback is not None and time.monotonic() - started > _PROBE_BUDGET_S:
            break
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=False)
        except Exception as exc:        # noqa: BLE001
            last_err = str(exc)
            continue
        if not (info and info.get("formats")):
            continue
        best_px, rich = _info_richness(info)
        if rich:
            if attempt["clients"] is not None and not attempt["cookies"]:
                note_good_clients(attempt["clients"])
            if fallback is not None:
                log_crash(f"quality probe: thin list ({fallback[0]}p) upgraded to "
                          f"{best_px}p by client {attempt['clients'] or 'default'}")
            # How this answer was obtained, so the download can reuse it as
            # its first rung's pre-flight instead of asking YouTube again.
            info[_PROBE_TAG] = {"clients": attempt["clients"],
                                "cookies": attempt["cookies"],
                                "dashy": bool(attempt["dashy"])}
            _probe_cache_put(ckey, info)
            return info, ""
        # Thin: keep it in hand, keep looking.
        key = (best_px, len(info.get("formats") or []))
        if fallback is None or key > fallback[:2]:
            fallback = (best_px, key[1], info, attempt["clients"])
        # Several unrelated clients seeing the same low ceiling means the video
        # itself is low-res (an old upload), not that this IP is being capped —
        # stop instead of walking the whole ladder for nothing.
        # A list that HAS adaptive streams (just none above 360p) is far more
        # likely to be the real thing than an itag-18-only answer, so it
        # counts double: two such clients agreeing is enough.
        has_adaptive = any((f.get("vcodec") or "none") != "none"
                           and (f.get("acodec") or "none") == "none"
                           for f in info.get("formats") or [])
        thin_votes[best_px] = thin_votes.get(best_px, 0) + (2 if has_adaptive else 1)
        if thin_votes[best_px] >= 4:
            break
    if fallback is not None:
        info = fallback[2]
        best_px = int(fallback[0] or 0)
        agreed = thin_votes.get(best_px, 0) >= 4
        info[_PROBE_BEST_PX] = best_px
        info[_PROBE_AGREED] = bool(agreed)
        info[_PROBE_LIMITED] = not agreed
        return info, ""
    log_crash("quality probe: extraction failed: " + (last_err or "?"))
    return None, last_err or "extraction failed"


_SELECT_FAILED = object()   # "yt-dlp's selector itself broke", not "no match"


def _sort_formats_like_download(ydl, formats, info, container):
    """Sort `formats` in place exactly as download_video() will (yt-dlp sorts
    worst → best and `best…` picks from the end).

    The sort fields MUST include the download's own format_sort. yt-dlp's
    sort_formats() reads only info['_format_sort_fields'] — it does not merge
    the YoutubeDL params — and the probe's extraction carries no format_sort,
    so without this the list sorted by the extractor's default order, where an
    HLS rendition's declared tbr (itag 231: 862 kbps) outranked the DASH stream
    the download actually takes (itag 135: 529 kbps, exact 14.1 MB on disk).
    The picker then quoted a stream the download never picks: measured,
    480p predicted 25.3 MB → landed 16.8 MB."""
    fields = list(_format_sort(container)) + list(info.get("_format_sort_fields") or [])
    try:
        ydl.sort_formats({"formats": formats, "_format_sort_fields": fields})
        return
    except Exception:                   # noqa: BLE001 — older/newer API
        pass
    try:
        from yt_dlp.utils import FormatSorter
        formats.sort(key=FormatSorter(ydl, fields).calculate_preference)
    except Exception:                   # noqa: BLE001
        pass


def _select_streams(yt_dlp, info, fmt, container):
    """Run yt-dlp's OWN format selector on the extracted format list, with the
    exact `format` + `format_sort` the download uses. Local only — no network.

    Calls the selector directly instead of re-running process_ie_result() on
    the whole info dict: that path re-processes an already-processed result
    and breaks on some yt-dlp builds, which made EVERY row fail and the picker
    fall back to "Couldn't read this video's formats".

    Returns the picked streams, [] when the expression matches nothing, or
    _SELECT_FAILED when the selector itself could not run (the caller then
    uses the built-in picker instead).
    """
    formats = [dict(f) for f in (info.get("formats") or [])
               if f.get("has_drm") is not True]
    if not formats:
        return []
    opts = {
        "quiet": True, "no_warnings": True, "skip_download": True,
        "noplaylist": True, "logger": _QuietLogger(),
    }
    if container not in _AUDIO_CODEC_KEYS:
        opts["format_sort"] = _format_sort(container)
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            _sort_formats_like_download(ydl, formats, info, container)
            selector = ydl.build_format_selector(fmt)
            ctx = {
                "formats": formats,
                "has_merged_format": any(
                    "none" not in ((f.get("acodec") or "none"),
                                   (f.get("vcodec") or "none"))
                    for f in formats),
                "incomplete_formats": (
                    all((f.get("vcodec") or "none") == "none" for f in formats)
                    or all((f.get("acodec") or "none") == "none" for f in formats)),
            }
            chosen = list(selector(ctx))
    except Exception as exc:            # noqa: BLE001
        log_crash("quality probe: yt-dlp selector failed: " + repr(exc))
        return _SELECT_FAILED
    if not chosen:
        return []
    return _picked_streams(chosen[0])


def _heuristic_pick(info, q):
    """Built-in stand-in for yt-dlp's selector, used only when that selector
    can't run. Mirrors _format_sort(): resolution, then fps, then the codec
    the container prefers, then bitrate."""
    formats = [f for f in (info.get("formats") or []) if f.get("has_drm") is not True]
    container = q.get("container") or ""
    audios = [f for f in formats if (f.get("vcodec") or "none") == "none"
              and (f.get("acodec") or "none") != "none"]

    def a_rank(f):
        fam = _acodec_family(f.get("acodec"))
        pref = 0
        if container in ("mp4", "m4a"):
            pref = 1 if fam == "aac" else (-1 if fam == "opus" else 0)
        elif container in ("webm", "opus"):
            pref = 1 if fam == "opus" else 0
        return (pref, float(f.get("abr") or f.get("tbr") or 0))

    best_a = max(audios, key=a_rank) if audios else None
    if container == "mp4" and best_a is not None and \
            _acodec_family(best_a.get("acodec")) == "opus":
        best_a = None                   # the download never puts Opus in MP4
    if q.get("audio_only"):
        return [best_a] if best_a else []

    cap = int(q.get("height") or 0)
    vids = [f for f in formats if (f.get("vcodec") or "none") != "none"
            and (f.get("acodec") or "none") == "none"]
    if container == "webm":
        native = [f for f in vids if f.get("ext") == "webm"]
        vids = native or vids
    if cap:
        vids = [f for f in vids if 0 < _fmt_short_side(f) <= cap]

    def v_rank(f):
        fam = _vcodec_family(f.get("vcodec"))
        if container == "mp4":
            pref = {"h264": 2, "vp9": 1}.get(fam, 0)
        else:
            pref = {"vp9": 2, "h264": 1}.get(fam, 0)
        return (_fmt_short_side(f), int(round(f.get("fps") or 0)), pref,
                float(f.get("vbr") or f.get("tbr") or 0))

    if vids and best_a is not None:
        return [max(vids, key=v_rank), best_a]
    # progressive (video+audio in one file) — the loose rungs
    prog = [f for f in formats if (f.get("vcodec") or "none") != "none"
            and (f.get("acodec") or "none") != "none"]
    if cap:
        prog = [f for f in prog if 0 < _fmt_short_side(f) <= cap]
    return [max(prog, key=v_rank)] if prog else []


# ── real byte counts for filesize-less streams ───────────────────────────
# yt-dlp reports no filesize for several YouTube renditions (measured: the
# high-bitrate itags 270/614 and SD itag 231 ship neither filesize nor
# filesize_approx — only tbr). _fmt_bytes_info then estimates from
# tbr × duration, and that guess OVER-states the served bytes: measured
# 25.3 MB predicted for a 480p file that landed at 16.8 MB (1.7×). A 1-byte
# ranged GET answers with "Content-Range: bytes 0-0/<total>" — the exact
# number the picker wants, for the cost of one light request per stream.
_CONTENT_LENGTH_CACHE: dict = {}


def _resolve_content_length(fmt, timeout=6):
    """True byte count of a stream URL, or 0 when it cannot be determined.

    Cached per stream URL, so container switches in the picker recompute rows
    without touching the network again. Only plain https/http renditions are
    asked — HLS/DASH manifests have no single content length."""
    url = fmt.get("url")
    if not url:
        return 0
    if (fmt.get("protocol") or "https").lower() not in ("https", "http"):
        return 0
    hit = _CONTENT_LENGTH_CACHE.get(url)
    if hit is not None:
        return hit
    n = 0
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": _UA, "Range": "bytes=0-0"})
        with _urlopen(req, timeout, configured_proxy()) as resp:
            cr = (resp.headers.get("Content-Range") or "").strip()
            m = re.search(r"/(\d+)\s*$", cr)
            if m:
                n = int(m.group(1))
            else:
                cl = resp.headers.get("Content-Length")
                n = int(cl) if cl else 0
    except Exception:                   # noqa: BLE001 — estimate is the fallback
        n = 0
    if len(_CONTENT_LENGTH_CACHE) > 256:
        _CONTENT_LENGTH_CACHE.clear()
    _CONTENT_LENGTH_CACHE[url] = n
    return n


def qualities_from_info(info, video_container=None, audio_codec=None,
                        audio_lang=""):
    """Picker rows for an extracted video, sized for the chosen output format.

    Returns (ok, options, error) like probe_video_qualities(). Each row is a
    preset carrying `size`, `size_exact` and `detail` (what will actually be
    downloaded, e.g. "1920×1080 · 60fps · H.264", or "VP9 → H.264" when it
    will be converted). A row is offered only when the download would deliver
    that tier — the same 10% floor download_video() enforces — so the picker
    can't list a quality the downloader would then refuse.
    """
    if not info or not info.get("formats"):
        return False, [], "no formats"
    try:
        yt_dlp, _ffmpeg = ensure_yt_dlp_ready()
    except Exception:                   # noqa: BLE001 — heuristic still works
        yt_dlp = None
    prefs = download_prefs()
    vc = video_container or prefs["video"]
    ac = audio_codec or prefs["audio"]
    duration = float(info.get("duration") or 0)

    top_px = max((_fmt_short_side(f) for f in info["formats"]
                  if (f.get("vcodec") or "none") != "none"), default=0)

    use_ytdlp = yt_dlp is not None
    out = []
    for preset in DOWNLOAD_QUALITY_PRESETS:
        try:
            q = with_container(preset, ac if preset.get("audio_only") else vc)
            # sizes follow the picked dub too (v1.2)
            q = with_audio_lang(q, audio_lang)
            picked = _SELECT_FAILED
            if use_ytdlp:
                picked = _select_streams(yt_dlp, info, q["format"], q["container"])
                if picked == [] and not q.get("audio_only"):
                    # The download's final rungs allow progressive files too.
                    picked = _select_streams(yt_dlp, info, q["format_loose"],
                                             q["container"])
            if picked is _SELECT_FAILED:
                use_ytdlp = False       # don't retry a broken selector 8 times
                picked = _heuristic_pick(info, q)
            if not picked:
                continue
            video, _a = _split_av(picked)
            if not q.get("audio_only"):
                got = _fmt_short_side(video or {})
                want = int(q.get("height") or 0) or top_px
                if not got or got < _quality_floor(want):
                    continue    # the download would refuse this tier
            # Real byte counts for the picked streams YouTube gave no filesize
            # for (see _resolve_content_length). After this, a remux pick's
            # prediction is a REAL content length, not a tbr guess — measured:
            # 25.3 MB predicted → 16.8 MB on disk before, exact after.
            for p in picked:
                if _fmt_bytes_info(dict(p, _duration=duration))[1]:
                    continue            # already a real reported filesize
                n = _resolve_content_length(p)
                if n > 0:
                    p["filesize"] = n
                    p.pop("filesize_approx", None)
            size, exact, detail = _predict_output(q, picked, duration)
        except Exception as exc:        # noqa: BLE001 — one bad row ≠ no picker
            log_crash(f"quality probe row {preset.get('key')}: {exc!r}")
            continue
        row = dict(preset)
        row["size"] = size
        row["size_exact"] = bool(exact and size > 0)
        row["detail"] = detail
        row["height_px"] = 0 if q.get("audio_only") else _fmt_short_side(video or {})
        out.append(row)

    if not any(not r.get("audio_only") for r in out):
        return False, [], "no video formats reported"
    return True, out, ""


def probe_video_qualities(url, proxy_url="", cookies_browser="",
                          video_container=None, audio_codec=None):
    """What this ONE video can actually be downloaded as, and how big each
    finished file will be. Blocking — call on a worker thread.

    Returns (ok, options, error). See qualities_from_info() for the rows.
    A caller that gets ok=False should fall back to DOWNLOAD_QUALITY_PRESETS:
    their own expressions still resolve at download time.
    """
    info, err = fetch_probe_info(url, proxy_url, cookies_browser)
    if not info:
        return False, [], err
    return qualities_from_info(info, video_container, audio_codec)


def probe_max_height(url, proxy_url="", cookies_browser=""):
    """The highest resolution this video genuinely offers, or 0 if unknown.

    Exists so that "Best available" has a CHECKABLE target. Its preset carries
    `height: 0`, which meant `want_px` was 0, which meant both the per-rung
    pre-flight and the post-download verification were skipped — so a video whose
    top tier is 1440p could finish as a 720p progressive file and be reported as a
    success. (The reported symptom: a 45 MB video arriving as 9.41 MB.)

    Reuses probe_video_qualities()'s client ladder rather than duplicating it, so a
    video that needs the iOS client to be seen at all is still measured correctly.
    0 on failure, which callers must treat as "no opinion" — an unmeasurable video
    must not become an unfailable one.
    """
    ok, options, _err = probe_video_qualities(
        url, proxy_url=proxy_url, cookies_browser=cookies_browser)
    if not ok:
        return 0
    return max((int(o.get("height_px") or o.get("height") or 0)
                for o in options if not o.get("audio_only")), default=0)


def _resolution_label(px):
    """A delivered resolution as the label a user recognises ("1080p").

    Snapped to the nearest preset bucket the number is within 10% of, because
    YouTube ships odd heights: a "1080p" stream of a non-16:9 video is often 1072
    or 1088 tall. A plain "highest bucket at or below" test would file 1072 as
    720p — understating the file by a whole tier, which is the same kind of lie
    this whole change is removing. Below the smallest bucket the exact number is
    used: there is no bucket for it, and rounding up would overstate it.
    """
    px = int(px or 0)
    if not px:
        return ""
    for key in _QUALITY_BUCKETS:
        if px >= int(key[:-1]) * 0.9:
            return key
    return f"{px}p"


# Channel avatars, keyed by channel id, for the lifetime of the process. The
# avatar is the one piece of channel identity yt-dlp does NOT put in a video's
# info dict, so it costs one page fetch per channel — and one is enough: every
# later download from the same channel reads this instead of asking again.
_CHANNEL_AVATAR_CACHE = {}


def _channel_avatar_url(channel_id):
    """Best-effort channel avatar url, read from the channel's own page.

    Returns "" on anything unexpected — a private/deleted channel, a page shape
    we do not recognise, no network. A missing avatar is a cosmetic loss (the
    player falls back to an initials disc); it must never fail a download.
    """
    cid = (channel_id or "").strip()
    if not cid.startswith("UC"):
        return ""
    if cid in _CHANNEL_AVATAR_CACHE:
        return _CHANNEL_AVATAR_CACHE[cid]
    url = ""
    try:
        from app.core.net import _urlopen, configured_proxy
        from app.core.monetization import (_YT_UA_HEADERS, extract_balanced_json,
                                           fetch_youtube_html)
        html = fetch_youtube_html(f"https://www.youtube.com/channel/{cid}",
                                  timeout=15)
        data = extract_balanced_json(html, "ytInitialData") if html else None
        if data:
            url = _find_avatar_url(data)
    except Exception:                     # noqa: BLE001 — cosmetic only
        url = ""
    # The channel page serves a 72px avatar; the player draws it on a HiDPI
    # display, where 72px upscales visibly. Asking for the same image at a
    # larger size costs nothing (it is the identical asset).
    if url:
        url = re.sub(r"=s\d+", "=s176", url, count=1)
    _CHANNEL_AVATAR_CACHE[cid] = url
    return url


def _find_avatar_url(obj, depth=0):
    """First plausible channel-avatar url anywhere in a channel page payload.

    Deliberately structural rather than path-based: YouTube has moved the header
    avatar between `pageHeaderRenderer`, `pageHeaderViewModel` and
    `decoratedAvatarViewModel` over the last few years, and a hard-coded path
    would have broken on each move. Looking for the avatar's own shape — an
    avatar-hosted image url inside a node whose key mentions "avatar" — survives
    that.

    `channelMetadataRenderer.avatar` is tried first because it is the one node
    that has kept its name throughout; the walk is the safety net for the
    header variants.
    """
    if isinstance(obj, dict):
        meta = obj.get("channelMetadataRenderer")
        if isinstance(meta, dict):
            found = _first_avatar_host_url(meta.get("avatar"))
            if found:
                return found
    if depth > 14:
        return ""
    if isinstance(obj, dict):
        for key, value in obj.items():
            if "avatar" in str(key).lower():
                found = _first_avatar_host_url(value)
                if found:
                    return found
        for value in obj.values():
            found = _find_avatar_url(value, depth + 1)
            if found:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = _find_avatar_url(value, depth + 1)
            if found:
                return found
    return ""


# Where YouTube actually serves images from. `ytimg.com` carries video
# thumbnails; channel avatars moved to `yt3.googleusercontent.com`, and looking
# only for the first host is why an avatar lookup can come back empty on a page
# that plainly contains one.
_IMAGE_HOSTS = ("googleusercontent.com", "ytimg.com", "ggpht.com")


def _first_avatar_host_url(obj, depth=0):
    if depth > 8:
        return ""
    if isinstance(obj, dict):
        url = obj.get("url")
        if isinstance(url, str) and any(h in url for h in _IMAGE_HOSTS):
            return url
        for value in obj.values():
            found = _first_avatar_host_url(value, depth + 1)
            if found:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = _first_avatar_host_url(value, depth + 1)
            if found:
                return found
    return ""


def channel_meta_for_video(video_id):
    """Channel identity for a bare video id — one light page read, no API key.

    Used to backfill clips that were cut before the cutter started recording
    the channel (v3.16-p4). Reads `videoDetails` out of the watch page's
    ytInitialPlayerResponse (channelId + author), then the avatar from the
    channel page through the same per-process cache the downloader uses.
    Returns {} on anything unexpected — identity is cosmetic.
    """
    vid = (video_id or "").strip()
    if not vid:
        return {}
    try:
        from app.core.monetization import extract_balanced_json, fetch_youtube_html
        html = fetch_youtube_html(f"https://www.youtube.com/watch?v={vid}",
                                  timeout=15)
        data = extract_balanced_json(html, "ytInitialPlayerResponse") if html else None
        details = (data or {}).get("videoDetails") or {}
        cid = (details.get("channelId") or "").strip()
        title = (details.get("author") or "").strip()
    except Exception:                     # noqa: BLE001 — cosmetic only
        return {}
    if not (cid or title):
        return {}
    meta = {
        "channel_title": title,
        "channel_id": cid,
        "channel_url": f"https://www.youtube.com/channel/{cid}" if cid else "",
    }
    # v3.51: the subscriber count rides on the same page we already read
    # (videoOwnerRenderer.subscriberCountText). Without it a video downloaded /
    # cut from the browser extension — whose row comes from oEmbed, which has no
    # channel stats — opened in the player with no subscriber count whenever
    # yt-dlp had not returned `channel_follower_count`.
    subs = parse_subscriber_text(_subscriber_text_from_html(html))
    if subs is not None:
        meta["subscriber_count"] = subs
        meta["subs_hidden"] = False
    if cid:
        meta["channel_thumb_url"] = _channel_avatar_url(cid)
    return meta


_SUBS_TEXT_RE = re.compile(
    r'"subscriberCountText"\s*:\s*\{.{0,400}?"(?:simpleText|content)"\s*:\s*"([^"]{1,60})"',
    re.S)


def _subscriber_text_from_html(html):
    """The watch page's "2.5M subscribers" string, or ""."""
    if not html:
        return ""
    m = _SUBS_TEXT_RE.search(html)
    return m.group(1) if m else ""


def parse_subscriber_text(text):
    """"2.5M subscribers" / "1,234 subscribers" / "12K" → an int, else None.

    YouTube's page only ships a rounded figure, so this is the rounded number
    (exactly what the page itself shows). Accepts K / M / B and the spelled-out
    forms; "No subscribers" is 0; anything unrecognised is None (unknown, which
    callers must not treat as "hidden")."""
    t = str(text or "").strip().lower()
    if not t:
        return None
    if t.startswith("no subscriber"):
        return 0
    m = re.search(r"(\d[\d,.\s]*)\s*(k|m|b|thousand|million|billion)?", t)
    if not m:
        return None
    num = m.group(1).strip().replace(" ", "")
    unit = m.group(2) or ""
    mult = {"k": 1e3, "thousand": 1e3, "m": 1e6, "million": 1e6,
            "b": 1e9, "billion": 1e9}.get(unit, 1)
    try:
        if mult == 1:
            return int(re.sub(r"[^\d]", "", num) or 0) or None
        return int(round(float(num.replace(",", "")) * mult))
    except ValueError:
        return None


def channel_meta_from_info(info):
    """Channel identity out of a yt-dlp info dict — for free.

    yt-dlp already carries all of this in the payload the download itself paid
    for: the channel's name, its id, its canonical url, and its follower count.
    Reading it costs nothing and needs no API key, which is the point — a video
    downloaded from a page that had NOT enriched the channel used to land in the
    library with a channel title and nothing else, and that is why the player
    showed "Subscribers hidden" over an initials disc for some videos and a
    proper avatar for others.

    Returns {} when there is nothing usable, so callers can treat "no metadata"
    and "metadata" the same way.
    """
    if not isinstance(info, dict):
        return {}
    followers = info.get("channel_follower_count")
    if followers is None:
        followers = info.get("uploader_follower_count")
    try:
        followers = int(followers) if followers not in (None, "") else None
    except (TypeError, ValueError):
        followers = None
    title = info.get("channel") or info.get("uploader") or ""
    cid = info.get("channel_id") or ""
    curl = info.get("channel_url") or info.get("uploader_url") or ""
    if not (title or cid or followers):
        return {}
    return {
        "channel_title": title,
        "channel_id": cid,
        "channel_url": curl,
        "subscriber_count": followers,
        # Only claim "hidden" when yt-dlp positively told us the count is not
        # public. `None` here means unknown, and unknown must not be written as
        # hidden — that is the bug this whole function exists to fix. Leaving it
        # out lets downloads_upsert keep whatever the search already recorded.
        **({"subs_hidden": False} if followers is not None else {}),
    }


def _rung_preflight(yt_dlp, url, base_opts, attempt, cached_info=None):
    """One metadata call that answers everything the rung needs to know up front.

    Returns a dict:
        {"best_px": int,        # highest resolution this client sees (-1 = no opinion)
         "expected": int,       # streams the pick will merge (1 or 2)
         "total_bytes": int,    # size the finished file(s) should be, 0 if unknown
         "total_exact": int,    # ... of which are real filesizes (0 = guess/unknown)
         "frag_total": int}     # fragments the whole download will be, 0 if unknown

    A `download=False` extraction runs yt-dlp's full format SELECTION, so the
    same `format` expression and `dashy` setting the rung will download with are
    applied here — `requested_formats` then carries the exact streams, their
    `filesize`, and (in dashy mode) their `fragments` list. That is what lets the
    progress bar know its denominator before a single byte moves, instead of
    discovering and revising it mid-transfer (the old bar-lurch bug).

    Cheap on purpose (`extractor_retries: 1`) — a client that needs three tries
    to answer isn't the one that will serve the download. Any failure reads as
    "no opinion" (`best_px = -1`) so a locked cookie DB can't pre-flight a good
    rung out of the ladder.
    """
    blank = {"best_px": -1, "expected": 0, "total_bytes": 0,
             "total_exact": 0, "frag_total": 0, "channel": {}}
    probe_opts = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "http_headers": {"User-Agent": _UA},
        "extractor_retries": 1,
        "logger": _QuietLogger(),
    }
    probe_opts.update(js_runtime_opts())   # nsig challenge may be needed to extract
    if base_opts.get("proxy"):
        probe_opts["proxy"] = base_opts["proxy"]
    # Select with the SAME expression the rung downloads with, so the probed
    # streams are the ones that will actually be fetched.
    if attempt.get("format"):
        probe_opts["format"] = attempt["format"]
    # ...and with the SAME sort — without it the pre-flight's "exact streams"
    # were picked by yt-dlp's default order, not the download's.
    if base_opts.get("format_sort"):
        probe_opts["format_sort"] = list(base_opts["format_sort"])
    # extractor_args merges player_client (which client to ask) and formats=dashy
    # (fragment the streams) under one "youtube" key — two separate assignments
    # would clobber each other.
    yt_args = {}
    if attempt.get("clients"):
        yt_args["player_client"] = attempt["clients"]
    if attempt.get("dashy"):
        yt_args["formats"] = ["dashy"]
    if yt_args:
        probe_opts["extractor_args"] = {"youtube": yt_args}
    if attempt.get("cookies"):
        probe_opts["cookiesfrombrowser"] = (attempt["cookies"],)
    try:
        with yt_dlp.YoutubeDL(probe_opts) as ydl:
            if cached_info is not None:
                # v1.0.1: the quality picker (or "Best available"'s height
                # check) already extracted this video with this very client
                # moments ago. Re-run only the local format SELECTION on that
                # answer — no network, no JS challenge, no PO token — instead
                # of a second full extraction before the first byte.
                for k in _STALE_PICK_KEYS:
                    cached_info.pop(k, None)
                info = ydl.process_ie_result(cached_info, download=False)
            else:
                info = ydl.extract_info(url, download=False)
    except Exception:   # noqa: BLE001 — a failed probe must never block a rung
        return blank
    if not info:
        return blank

    # Best resolution any video format offers — the rung-skip decision.
    best = 0
    for f in info.get("formats") or []:
        if (f.get("vcodec") or "none") == "none":
            continue
        best = max(best, _fmt_short_side(f))

    # The streams format selection actually chose for this rung.
    picked = info.get("requested_formats") or info.get("requested_downloads") or []
    if not picked and info.get("url"):
        picked = [info]     # a progressive single-file pick
    expected = len([p for p in picked if p]) or 0
    total_bytes = 0
    total_exact = 0
    exact_known = bool(picked)
    for p in picked:
        total_bytes += int(p.get("filesize") or p.get("filesize_approx") or 0)
        if p.get("filesize"):
            total_exact += int(p["filesize"])
        else:
            exact_known = False
    if not exact_known:
        # At least one stream only has an approx size — the sum is a guess
        # (and a routinely inflated one), so report "unknown" rather than a
        # fantasy number the progress line would then present as fact.
        total_exact = 0
    frag_total = 0
    for p in picked:
        frags = p.get("fragments")
        if frags is not None:
            try:
                frag_total += len(frags)
            except TypeError:
                pass
    return {"best_px": best, "expected": expected,
            "total_bytes": total_bytes, "total_exact": total_exact,
            "frag_total": frag_total,
            # v3.41.3: the extraction itself, so the rung can DOWNLOAD from it
            # instead of asking YouTube for the very same metadata again.
            "info": info,
            # Rides along on a probe that was already being made. The caller
            # persists it so the library knows who made the video without a
            # second request (see channel_meta_from_info).
            "channel": channel_meta_from_info(info)}


class _ProgressAggregator:
    """Turns yt-dlp's PER-STREAM, PER-FRAGMENT progress into one bar that only
    moves forward.

    Downloads now run in fragmented DASH mode (see download_video's
    `formats=dashy` extractor arg), so a file arrives as N fixed 10 MB chunks
    rather than one continuous stream. That is what the log's `(frag 32/93)`
    means, and it is a far steadier progress signal than raw bytes: the chunk
    COUNT is known up front and never revises, whereas three separate things
    used to make a naive `downloaded/total` percentage lurch 15% → 5% → 30%:

      * An adaptive pick (`bestvideo+bestaudio`) is TWO sequential downloads.
        Each runs its own 0→100 and the hook reports only the stream in flight.
      * `total_bytes_estimate` for a fragmented stream is RE-DERIVED after every
        fragment (yt_dlp/downloader/fragment.py — recomputed from the running
        average fragment size), so an honest byte percentage legitimately falls.
      * yt-dlp DROPS `requested_formats` from the info_dict of the stream it is
        actively downloading (YoutubeDL.py builds a per-stream `new_info` with
        that key deleted), so a video+audio pair looked like two 1-stream
        downloads — the bar hit ~99 on the video, then the audio stream reset
        the denominator.

    So the percentage is taken from BYTES against the exact total the pre-flight
    probe already knows before the first byte moves — the same `done / total`
    division the size line beside it shows, so "60 MB of 124 MB" and "48%" can
    never contradict each other. A monotonic floor is still applied to both the
    percentage and the byte counters, so a retry rung restarting at zero can only
    ever slow the bar, never walk it back, and the shown total is
    exact-or-hidden (real filesizes only, never an approx sum).

    Fragments are still counted, but only as the FALLBACK denominator for a
    transfer whose byte total genuinely isn't known — never as the source of the
    displayed percentage. Fragment counts are not proportional to bytes: DASH
    segments differ in size, and the audio stream is a handful of small fragments
    beside a video stream of many large ones, so a fragment percentage drifted
    several points off the byte readout for the whole transfer and then lurched
    when the small audio stream finally ran. That mismatch — the size saying one
    thing and the percentage another — is the bug this ordering removes. The
    in-flight fragment's own byte fraction is still used to glide the bar
    between whole fragments instead of stepping once per chunk.
    """

    def __init__(self, expected=1, resume_pct=0):
        self.expected = max(1, int(expected))
        # A resumed download re-fetches the fragmented DASH chunks that were in
        # flight when it stopped, so its first live byte reading is BELOW the
        # percentage the user paused at. `resume_pct` is that paused number;
        # update() maps the new transfer onto [resume_pct, 99] so the bar
        # climbs from exactly where it stopped instead of sitting frozen until
        # the re-fetched bytes catch up.
        try:
            self._resume_from = max(0, min(99, int(resume_pct or 0)))
        except (TypeError, ValueError):
            self._resume_from = 0
        self._resume_base = None    # first live raw percentage, once bytes move
        # Reference totals learned from the pre-flight probe BEFORE the transfer
        # starts, so the denominator is right from the first tick instead of
        # being discovered (and revised) mid-download. 0 means "unknown".
        self._total_hint = 0        # bytes the finished file(s) should be
        self._exact_hint = 0        # ... of which are EXACT (real filesizes)
        self._frag_total_hint = 0   # fragments the whole download should be
        # Per stream, keyed by format id: byte counters plus the fragment the
        # stream is on / has in total. Summed across streams for one global bar.
        self._streams = {}
        self._floor = self._resume_from   # highest percentage reported so far
        self._finished = 0          # streams that reported status == finished
        # BYTE counters get the same monotonic treatment as the percentage, so a
        # retry rung restarting from zero doesn't drop the size line from "50 MB"
        # to "2 MB" while the bar holds.
        self._done_floor = 0
        self._total_ceiling = 0
        # Hold the last real speed sample across the few ticks a freshly started
        # stream needs before it reports one, so the "…/s" readout doesn't blink
        # to empty at every stream/rung change.
        self._last_speed = 0.0
        self._speed_stale = 0
        # Same treatment for ETA: the raw per-stream number blanks/resets at
        # every stream change, so a held sample keeps the "… left" readout from
        # blinking or leaping while the next stream spins up.
        self._last_eta = 0
        self._eta_stale = 0

    def note_totals(self, expected=0, total_bytes=0, frag_total=0,
                    total_exact=0):
        """Seed the reference totals from the pre-flight probe.

        These are what make the bar honest from the first tick: the fragment
        count and byte size are read from metadata before any bytes move, so the
        denominator never has to be guessed from a half-downloaded stream. Each
        is a floor — if the live numbers turn out larger, the larger wins.

        `total_exact` is the same sum counting ONLY real reported filesizes.
        Anything built on approx sizes is deliberately NOT trusted for display:
        approx totals routinely overshoot several-fold, and showing one as the
        file's size is the "464 MB for an 85 MB video" bug.
        """
        try:
            if int(expected) > 0:
                self.expected = int(expected)
        except (TypeError, ValueError):
            pass
        try:
            self._total_hint = max(self._total_hint, int(total_bytes or 0))
        except (TypeError, ValueError):
            pass
        try:
            self._exact_hint = max(self._exact_hint, int(total_exact or 0))
        except (TypeError, ValueError):
            pass
        try:
            self._frag_total_hint = max(self._frag_total_hint, int(frag_total or 0))
        except (TypeError, ValueError):
            pass

    def note_expected(self, n):
        """Raise the expected stream count once yt-dlp reveals it via
        `requested_formats`. Only ever raises — the pre-flight seed is trusted
        over a transient tick that momentarily reports fewer."""
        try:
            n = int(n)
        except (TypeError, ValueError):
            return
        if n > self.expected:
            self.expected = n

    def reset(self):
        """A retry rung is starting over. The per-stream counters go back to
        zero but every FLOOR stays: the user watched the bar and the size line
        get where they are, and dropping either to climb again is the exact
        confusion this class exists to prevent. The reference hints stay too —
        the file didn't change size because we switched clients."""
        self._streams.clear()
        self._finished = 0

    def update(self, d):
        """Fold one hook tick in.

        Returns (pct, done_bytes, total_bytes, speed, eta, frag_done, frag_total).
        `pct` is derived from the bytes above whenever the exact total is known,
        so it always agrees with the `total_bytes` shown beside it; fragments are
        only the fallback denominator when no byte total exists. `total_bytes` is
        0 when the real size is not known — the UI then shows bytes-so-far with
        the fragment position and percentage instead of a guessed total it would
        contradict. `eta` is a GLOBAL, smoothed seconds estimate (from
        remaining/speed when the total is known, else the raw per-stream number
        held across gaps) — never the raw per-stream value, which resets at every
        stream switch and made the countdown leap.
        """
        info = d.get("info_dict") or {}
        reqs = info.get("requested_formats")
        if reqs:
            self.note_expected(len(reqs))
        # format_id identifies the stream; fall back to the temp filename, which
        # yt-dlp makes unique per stream ("…f137.mp4.part").
        key = (info.get("format_id") or d.get("tmpfilename")
               or d.get("filename") or "single")
        entry = self._streams.setdefault(
            key, {"done": 0, "total_x": 0, "total_e": 0,
                  "frag_idx": 0, "frag_cnt": 0})
        entry["done"] = int(d.get("downloaded_bytes") or entry["done"])
        # Exact and estimated totals are tracked SEPARATELY. `total_bytes`
        # (an HTTP content-length) is a fact; `total_bytes_estimate` is
        # re-derived after every fragment and routinely fantasy — mixing them
        # is what let a guess pose as the file's size.
        if d.get("total_bytes"):
            entry["total_x"] = int(d["total_bytes"])
        if d.get("total_bytes_estimate"):
            entry["total_e"] = int(d["total_bytes_estimate"])
        # Fragment position for THIS stream. `fragment_index` is how many chunks
        # of this stream are already on disk; `fragment_count` is its total.
        fidx = d.get("fragment_index")
        if fidx is not None:
            entry["frag_idx"] = int(fidx)
        fcnt = d.get("fragment_count")
        if fcnt:
            entry["frag_cnt"] = int(fcnt)

        done_sum = sum(s["done"] for s in self._streams.values())
        exact_sum = sum(s["total_x"] for s in self._streams.values())
        est_sum = sum(s["total_e"] for s in self._streams.values())
        known_total = max(est_sum, exact_sum, self._total_hint)

        # Held at the high-water mark: a retry rung restarting from zero is a
        # fact about our ladder, not about the user's download.
        done_sum = max(done_sum, self._done_floor)
        self._done_floor = done_sum

        # The byte total SHOWN to the user. Exact only: a real filesize (or a
        # content-length the transfer itself reported) — never an approx sum.
        # 0 means "unknown": the UI then shows bytes-so-far with the fragment
        # position and percentage instead of a made-up total it would
        # contradict ("40 MB of 464 MB at 55%").
        exact_known = max(exact_sum, self._exact_hint)
        if exact_known:
            total_shown = max(exact_known, done_sum)
            self._total_ceiling = max(self._total_ceiling, total_shown)
            total_shown = max(total_shown, self._total_ceiling)
        else:
            total_shown = 0

        frag_done, frag_total = self._fragment_progress()
        # BYTES FIRST — the percentage is the SAME division the size line shows,
        # so "60 MB of 124 MB" and "48%" can never disagree.
        #
        # Fragment counts used to lead here, because the byte denominator had to
        # be discovered (and revised) mid-transfer. The pre-flight probe removed
        # that reason: it seeds an EXACT total before the first byte moves. And
        # fragment counts are not proportional to bytes — DASH segments differ in
        # size, and the audio stream is a handful of small fragments beside a
        # video stream of many large ones — so the fragment percentage drifted
        # several points off the byte readout for the whole transfer, then
        # lurched when the small audio stream ran.
        #
        # The order is deliberate: exact bytes, then FRAGMENTS (steady, and with
        # no byte total displayed there is nothing for them to contradict), and
        # only then the approx estimate — which is re-derived after every
        # fragment and so is the one source that can legitimately walk backwards.
        if total_shown:
            raw_pct = done_sum * 100.0 / total_shown
        elif frag_total:
            raw_pct = frag_done * 100.0 / frag_total
        elif known_total:
            raw_pct = done_sum * 100.0 / known_total
        else:
            raw_pct = 0.0
        # Resume mapping. The first live raw reading becomes the anchor — the
        # paused percentage — and the remaining raw span is stretched onto
        # [anchor, 99]. Without this, a resume whose fragment files were only
        # partially reusable showed a bar frozen at the paused % (the UI floor)
        # for the tens of seconds it took to re-fetch the lost chunks, then a
        # lurch to 99. With it, the percentage moves on the very first tick and
        # keeps moving steadily; bytes and the displayed percentage still come
        # from the same transfer, they are just re-based after the restart.
        if self._resume_from:
            if self._resume_base is None and done_sum > 0:
                self._resume_base = min(raw_pct, float(self._resume_from))
            if self._resume_base is None:
                pct = float(self._resume_from)
            else:
                span = 100.0 - self._resume_base
                if span > 0:
                    pct = self._resume_from + max(
                        0.0, raw_pct - self._resume_base) * (
                            99.0 - self._resume_from) / span
                else:
                    pct = 99.0
                pct = max(pct, float(self._resume_from))
        else:
            pct = raw_pct
        # Capped at 99 while bytes are still moving: 100 is reserved for the file
        # that actually exists on disk (the VM writes it in _on_dl_done, after
        # the ffmpeg mux). Without the cap, a stream that met its byte estimate
        # showed 100% and then sat there through the merge — a finished-looking
        # download that won't open.
        pct = max(0, min(99, int(pct)))
        if pct < self._floor:
            pct = self._floor
        else:
            self._floor = pct

        speed = float(d.get("speed") or 0)
        if speed > 0:
            self._last_speed = speed
            self._speed_stale = 0
        elif self._speed_stale < 3:
            self._speed_stale += 1
            speed = self._last_speed
        else:
            self._last_speed = 0.0

        # Global ETA: remaining bytes over smoothed speed whenever the real
        # total is known — stable across the video→audio stream switch, where
        # the raw per-stream ETA restarts and used to make the countdown jump.
        # Without a known total, hold the last raw sample briefly so the
        # readout doesn't blink to empty between streams.
        raw_eta = 0
        try:
            raw_eta = int(d.get("eta") or 0)
        except (TypeError, ValueError):
            raw_eta = 0
        if total_shown and speed > 0 and done_sum < total_shown:
            try:
                eta = int((total_shown - done_sum) / max(speed, 1.0))
            except (OverflowError, ZeroDivisionError, ValueError):
                eta = raw_eta
            if eta > 0:
                self._last_eta = eta
                self._eta_stale = 0
            else:
                eta = 0
        elif raw_eta > 0:
            eta = raw_eta
            self._last_eta = raw_eta
            self._eta_stale = 0
        elif self._eta_stale < 5 and self._last_eta > 0:
            self._eta_stale += 1
            eta = self._last_eta
        else:
            self._last_eta = 0
            eta = 0

        return (pct, done_sum, total_shown, speed, eta,
                int(round(frag_done)), int(frag_total))

    def _fragment_progress(self):
        """(fragments_done, fragments_total) across every stream.

        `fragments_done` is fractional: the completed chunks of each stream plus
        the byte fraction of the chunk currently in flight, so the bar glides
        between whole fragments rather than stepping once per 10 MB.

        The TOTAL comes from the pre-flight hint whenever we have one, because it
        already sums every stream accurately. Only without a hint do we
        extrapolate the not-yet-started streams — and even then NOT from the
        average fragment count, because a video+audio pair is wildly uneven (a
        90-fragment video beside a 3-fragment audio), so assuming the missing
        stream matches the average doubles the denominator and makes the bar leap
        when the small stream starts. We add just one fragment per missing stream
        as a floor — enough to keep the bar under 100 until it actually reports.
        """
        seen = [s for s in self._streams.values() if s["frag_cnt"]]
        sum_seen = sum(s["frag_cnt"] for s in seen)
        if self._frag_total_hint:
            frag_total = max(self._frag_total_hint, sum_seen)
        else:
            missing = max(0, self.expected - len(seen))
            frag_total = sum_seen + missing if seen else 0
        if not frag_total:
            return 0, 0
        frag_done = 0.0
        for s in seen:
            frag_done += s["frag_idx"]
            # Byte fraction of the fragment in flight, so the bar isn't frozen
            # between chunks on a slow link. Only the current chunk's share.
            # Either total source works here — this is intra-fragment glide,
            # never a displayed number.
            stream_total = s.get("total_x") or s.get("total_e") or 0
            if stream_total and s["frag_cnt"]:
                per_frag = stream_total / s["frag_cnt"]
                if per_frag:
                    into = s["done"] - s["frag_idx"] * per_frag
                    frag_done += max(0.0, min(1.0, into / per_frag))
        return frag_done, frag_total

    def note_finished(self):
        """One stream completed. Returns the percentage to report now.

        Every stream done means the transfer is over and only the ffmpeg mux
        remains, so the bar is pinned at 99 rather than left wherever the last
        stream's estimate landed — 100 belongs to the finished file on disk.
        """
        self._finished += 1
        if self._finished >= self.expected:
            self._floor = max(self._floor, 99)
        return self._floor



# ── output format (container / audio codec) ─────────────────────────────
# Chosen in the quality picker, persisted in the app config, and carried on the
# quality dict as `container`. Videos: the container the streams are merged
# into. Audio: the codec FFmpegExtractAudio converts to.
VIDEO_CONTAINERS = [
    {"key": "mp4", "label": "MP4", "sub": "Plays everywhere"},
    {"key": "mkv", "label": "MKV", "sub": "Any codec, no conversion"},
    {"key": "webm", "label": "WEBM", "sub": "VP9 / Opus, web-friendly"},
]
AUDIO_CODECS = [
    {"key": "mp3", "label": "MP3", "sub": "192 kbps, plays everywhere",
     "format": "bestaudio/best", "quality": "192"},
    {"key": "m4a", "label": "M4A", "sub": "AAC, no re-encode when possible",
     "format": "bestaudio[ext=m4a]/bestaudio/best", "quality": "192"},
    {"key": "opus", "label": "OPUS", "sub": "Original YouTube audio",
     "format": "bestaudio[acodec=opus]/bestaudio/best", "quality": "0"},
    {"key": "wav", "label": "WAV", "sub": "Uncompressed, large",
     "format": "bestaudio/best", "quality": "0"},
    {"key": "flac", "label": "FLAC", "sub": "Lossless container",
     "format": "bestaudio/best", "quality": "0"},
]
_VIDEO_CONTAINER_KEYS = [c["key"] for c in VIDEO_CONTAINERS]
_AUDIO_CODEC_KEYS = [c["key"] for c in AUDIO_CODECS]
DEFAULT_VIDEO_CONTAINER = "mp4"
DEFAULT_AUDIO_CODEC = "mp3"


def _norm_container(quality, container):
    c = str(container or "").strip().lower()
    if quality.get("audio_only"):
        return c if c in _AUDIO_CODEC_KEYS else DEFAULT_AUDIO_CODEC
    return c if c in _VIDEO_CONTAINER_KEYS else DEFAULT_VIDEO_CONTAINER


def download_prefs():
    """The saved format choice: {"video": "mp4", "audio": "mp3"}."""
    try:
        from app.config import load_app_config
        cfg = load_app_config() or {}
    except Exception:       # noqa: BLE001
        cfg = {}
    v = str(cfg.get("dl_video_container") or "").lower()
    a = str(cfg.get("dl_audio_codec") or "").lower()
    return {"video": v if v in _VIDEO_CONTAINER_KEYS else DEFAULT_VIDEO_CONTAINER,
            "audio": a if a in _AUDIO_CODEC_KEYS else DEFAULT_AUDIO_CODEC}


def save_download_prefs(video=None, audio=None):
    """Persist the format choice into the shared app config."""
    try:
        from app.config import load_app_config, save_app_config
        cfg = load_app_config() or {}
        if video and str(video).lower() in _VIDEO_CONTAINER_KEYS:
            cfg["dl_video_container"] = str(video).lower()
        if audio and str(audio).lower() in _AUDIO_CODEC_KEYS:
            cfg["dl_audio_codec"] = str(audio).lower()
        save_app_config(cfg)
    except Exception:       # noqa: BLE001
        pass


def with_container(quality, container=None):
    """A COPY of a quality preset with its output format attached.

    `container` None means "use the saved choice". The preset's format
    expressions are rebuilt for the container so the streams picked can be
    merged into it without a re-encode."""
    q = dict(quality or quality_by_key("best"))
    if container is None:
        prefs = download_prefs()
        container = prefs["audio"] if q.get("audio_only") else prefs["video"]
    c = _norm_container(q, container)
    q["container"] = c
    if q.get("audio_only"):
        spec = next(x for x in AUDIO_CODECS if x["key"] == c)
        q["format"] = q["format_loose"] = spec["format"]
    elif q.get("key") == "best" or not q.get("height"):
        q["format"] = _best_format(c)
        q["format_loose"] = _best_format_loose(c)
    else:
        q["format"] = _video_format(int(q["height"]), c)
        q["format_loose"] = _video_format_loose(int(q["height"]), c)
    # the format strings were just rebuilt: a picked dub must ride along
    if q.get("audio_lang"):
        q = with_audio_lang(q, q["audio_lang"])
    return q


def quality_storage_key(quality):
    """What gets persisted for resume: "1080p@mkv", "audio@flac", "best@mp4"."""
    key = quality.get("key", "")
    c = quality.get("container")
    out = f"{key}@{c}" if key and c else key
    lang = quality.get("audio_lang") or ""
    return f"{out}~{lang}" if (out and lang) else out


def quality_display_label(quality):
    """Row label: "1080p · MKV". Translated preset label + the format."""
    base = tr(quality.get("label") or "")
    c = quality.get("container")
    out = f"{base} · {c.upper()}" if c else base
    lang = quality.get("audio_lang") or ""
    if lang:
        from app.core.audio_tracks import lang_names
        out = f"{out} · {tr('Dub')}: {lang_names(lang)[0]}"
    return out


def _final_ext(quality):
    return quality.get("container") or ("mp3" if quality.get("audio_only") else "mp4")


def _resolve_final_path(candidate, target_dir, video_id, q_key, ext):
    """The file actually on disk after merge/convert.

    yt-dlp's reported path can still name the pre-postprocessor file (.webm
    before an mp3 extraction, .mkv before a webm conversion). Try the expected
    extension first, then the reported path, then scan the folder for this
    video id + quality key with the right extension."""
    tries = []
    if candidate:
        tries.append(os.path.splitext(candidate)[0] + "." + ext)
        tries.append(candidate)
    for t in tries:
        if t and os.path.isfile(t):
            return t
    if video_id and target_dir and os.path.isdir(target_dir):
        tag = f"[{video_id}]"
        hits = []
        for name in os.listdir(target_dir):
            if tag not in name or name.endswith((".part", ".ytdl", ".temp")):
                continue
            stem, e = os.path.splitext(name)
            if q_key and not stem.rstrip().endswith(q_key):
                continue
            if e.lower().lstrip(".") == ext:
                hits.append(os.path.join(target_dir, name))
        if hits:
            return max(hits, key=os.path.getmtime)
    return tries[0] if tries else candidate


def _ffprobe_exe(ffmpeg_dir):
    name = "ffprobe.exe" if sys.platform == "win32" else "ffprobe"
    return os.path.join(ffmpeg_dir, name)


def _probe_vcodec_ffmpeg(ffmpeg, path):
    """Video codec via `ffmpeg -i` — the fallback when ffprobe is absent.

    `ensure_ffmpeg_dir()` stages ffprobe only when the installer bundled it, so
    a machine running from a source checkout has ffmpeg and nothing else.
    Decoding the whole file to find out would be absurd; `ffmpeg -i` prints the
    stream summary and exits, which carries the same answer:

        Stream #0:0[0x1](und): Video: vp9 (Profile 0) 1920x1080, ...
    """
    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    try:
        proc = subprocess.run(
            [ffmpeg, "-hide_banner", "-nostats", "-v", "info", "-i", path,
             "-t", "0.1", "-f", "null", "-"],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=60, creationflags=flags)
    except Exception:                 # noqa: BLE001
        return ""
    text = (proc.stderr or "")
    m = re.search(r"Stream #\d+:\d+.*?: Video: ([A-Za-z0-9_.]+)", text)
    if not m:
        return ""
    codec = m.group(1).strip().lower()
    # ffmpeg prints the encoder-ish name ("vp9", "h264", "av1", "hevc") but
    # some containers report a longer form ("mpeg4", "vp8"); every name an
    # editor chokes on is covered by the mapping table, so nothing else matters.
    return {"vp9": "vp9", "av01": "av1", "av1": "av1",
            "h264": "h264", "hevc": "hevc", "h265": "hevc"}.get(codec, codec)


def _probe_vcodec(ffmpeg_dir, path):
    """Video codec of `path`: ffprobe when present, `ffmpeg -i` otherwise."""
    ffprobe = _ffprobe_exe(ffmpeg_dir)
    if os.path.isfile(ffprobe):
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        try:
            out = subprocess.run(
                [ffprobe, "-v", "error", "-select_streams", "v:0",
                 "-show_entries", "stream=codec_name", "-of", "csv=p=0", path],
                capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=30, creationflags=flags)
            codecs = [ln.strip().lower() for ln in (out.stdout or "").splitlines()
                      if ln.strip()]
            if codecs:
                return codecs[0]
        except Exception:             # noqa: BLE001
            pass
    ffmpeg = os.path.join(ffmpeg_dir,
                          "ffmpeg.exe" if sys.platform == "win32" else "ffmpeg")
    if not os.path.isfile(ffmpeg):
        return ""
    return _probe_vcodec_ffmpeg(ffmpeg, path)


# The editor-compatible target. H.264 + AAC in MP4 is the one combination
# Premiere, Resolve, DaVinci, FCP and Windows' own player all open — YouTube's
# own high-resolution streams are VP9/AV1 in WebM, which Premiere rejects with
# "unsupported file or damaged" because it has no VP9/AV1 decoder.
_EDITOR_VCODEC = "h264"
_EDITOR_UNREADABLE = ("vp9", "vp9.2", "av01", "av1", "hevc", "h265")


def _needs_editor_conversion(vcodec):
    """True when a video stream an editor cannot open."""
    v = (vcodec or "").strip().lower()
    return bool(v) and v != _EDITOR_VCODEC and v in _EDITOR_UNREADABLE


def _run_editor_encode(ffmpeg, src, out_path, v_args, a_args, dur,
                       on_progress, should_cancel):
    """One ffmpeg pass of the editor conversion. Returns the exit code, or
    DOWNLOAD_CANCELLED when the user stopped it."""
    args = [ffmpeg, "-hide_banner", "-y", "-i", src, *v_args, *a_args,
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats", "-v", "error", out_path]
    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    try:
        proc = subprocess.Popen(args, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True,
                                encoding="utf-8", errors="replace", bufsize=1,
                                creationflags=flags)
    except Exception:                 # noqa: BLE001
        return 1
    last_emit = 0.0
    try:
        for line in proc.stdout or []:
            line = (line or "").strip()
            if should_cancel is not None and should_cancel():
                proc.kill()
                # reap it first: on Windows the half-written file stays locked
                # until ffmpeg has really exited
                try:
                    proc.wait(timeout=5)
                except Exception:     # noqa: BLE001
                    pass
                _remove_quietly(out_path)
                return DOWNLOAD_CANCELLED
            if not line.startswith("out_time_ms="):
                continue
            try:
                done_us = int(line.split("=", 1)[1])
            except ValueError:
                continue
            if dur > 0 and on_progress:
                now = time.monotonic()
                if now - last_emit > 0.25:      # ~4/sec, like the cutter
                    last_emit = now
                    on_progress(max(0, min(99, int(done_us / 1e6 / dur * 100))))
        # a generous multiple of the clip's length, not a fixed hour: a hung
        # ffmpeg used to hold the row open and read as "stuck on Merging"
        proc.wait(timeout=max(180.0, float(dur or 0.0) * 10.0))
    except Exception:                 # noqa: BLE001
        try:
            proc.kill()
        except Exception:             # noqa: BLE001
            pass
        return 1
    finally:
        try:
            if proc.stdout:
                proc.stdout.close()
        except Exception:             # noqa: BLE001
            pass
    return proc.returncode


def _convert_for_editors(ffmpeg_dir, filepath, quality, _status, on_progress,
                         should_cancel, src_vkbps=0, src_acodec=""):
    """Re-encode a freshly downloaded file to H.264/AAC MP4.

    Only ever called for an MP4 container pick. The picker promises MP4, but
    YouTube serves 1080p+ as VP9/AV1 in WebM, and yt-dlp keeps that codec when
    it merges — so an "MP4" download used to land as a .webm/.mkv that Premiere
    refuses. Rather than degrading the pick to a lower-resolution AVC stream
    (which is the downgrade trap documented at _video_stream_filter: YouTube
    only ships AVC up to 1080p, so filtering for it silently loses the
    resolution the user asked for), the picked resolution is kept and the CODEC
    is brought to the user afterwards.

    Returns (path, converted, message). On any failure the ORIGINAL file is
    returned untouched — a VP9 file the user can still play beats a failed
    conversion and nothing at all.

    NOTE — `on_progress` here is the caller's to interpret. download_video()
    passes a no-op so the conversion never moves the download % bar (see the
    call site): the transfer already sits at 99/"Merging…", and a second
    0→100 here read as "the download restarted" then stuck on
    "Downloading 100%".
    """
    vcodec = _probe_vcodec(ffmpeg_dir, filepath)
    if not _needs_editor_conversion(vcodec):
        return filepath, False, ""

    ffmpeg = os.path.join(ffmpeg_dir,
                          "ffmpeg.exe" if sys.platform == "win32" else "ffmpeg")
    if not os.path.isfile(ffmpeg):
        return filepath, False, tr("The conversion tool is not installed yet.")

    dur, _e = 0.0, ""
    try:
        from app.core.cutter import probe_file_with_error
        dur, _e = probe_file_with_error(filepath) or (0.0, "")
    except Exception:                 # noqa: BLE001
        dur = 0.0

    stem, ext = os.path.splitext(filepath)
    out_path = stem + ".mp4"
    if os.path.abspath(out_path) == os.path.abspath(filepath):
        out_path = stem + " [H264].mp4"

    _status(tr("Converting to H.264 MP4 for editing ({c}) …").format(
        c=vcodec.upper()))
    if on_progress:
        on_progress(0)
    # Bitrate-targeted, not CRF. CRF 18 has no size target, so the finished
    # file could be several times what the quality picker had promised. The
    # target is the SAME number the picker predicted (_editor_target_kbps), so
    # the size shown before the download is the size after it, within a few %.
    # CRF stays as the fallback when the source bitrate is unknown.
    target = _editor_target_kbps(src_vkbps, vcodec)
    # AAC is already what an editor wants — copy it instead of re-encoding
    # (no generation loss, and its size is known exactly).
    if _acodec_family(src_acodec) == "aac":
        a_args = ["-c:a", "copy"]
    else:
        a_args = ["-c:a", "aac", "-b:a", f"{_EDITOR_AUDIO_KBPS}k"]
    # v1.0.1: the GPU's H.264 encoder (NVENC / Quick Sync / AMF) when this PC
    # has a working one — the same once-per-process probe the cutter uses —
    # with libx264 as the guaranteed second try. A 4K VP9 → H.264 conversion
    # was the single slowest step of an MP4 download.
    try:
        from app.core.cutter import video_encoders
        encoders = video_encoders(ffmpeg)
    except Exception:                 # noqa: BLE001
        encoders = [("libx264", [])]
    rc_final = 1
    for enc_name, enc_args in encoders:
        if enc_name == "libx264":
            if target:
                v_args = ["-c:v", "libx264", "-preset", "veryfast",
                          "-b:v", f"{target}k", "-maxrate", f"{int(target * 1.5)}k",
                          "-bufsize", f"{target * 2}k", "-pix_fmt", "yuv420p"]
            else:
                v_args = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
                          "-pix_fmt", "yuv420p"]
        elif target:
            # bitrate-targeted like the CPU path, so the picker's size holds
            pix = enc_args[enc_args.index("-pix_fmt") + 1] if "-pix_fmt" in enc_args else "yuv420p"
            v_args = ["-c:v", enc_name, "-b:v", f"{target}k",
                      "-maxrate", f"{int(target * 1.5)}k",
                      "-bufsize", f"{target * 2}k", "-pix_fmt", pix]
        else:
            v_args = list(enc_args)
        rc = _run_editor_encode(ffmpeg, filepath, out_path, v_args, a_args,
                                dur, on_progress, should_cancel)
        if rc == DOWNLOAD_CANCELLED:
            return filepath, False, DOWNLOAD_CANCELLED
        rc_final = rc
        if rc == 0 and os.path.isfile(out_path):
            break
        try:
            if os.path.isfile(out_path):
                os.remove(out_path)
        except OSError:
            pass
    if rc_final != 0 or not os.path.isfile(out_path):
        try:
            if os.path.isfile(out_path):
                os.remove(out_path)
        except OSError:
            pass
        return filepath, False, tr("The conversion to H.264 did not finish.")
    if on_progress:
        on_progress(100)
    # Only now is the original removed: a half-written replacement must never
    # leave the user with neither file. And when the original carried the name
    # the user expects (it was already .mp4, just with VP9 inside), the
    # converted file takes that name back so the library shows a clean
    # "Video 720p.mp4" rather than "Video 720p [H264].mp4".
    if os.path.abspath(out_path) != os.path.abspath(filepath):
        _remove_quietly(filepath)
        # Take the original name back ONLY when it already ended in .mp4 — that
        # is the case where yt-dlp merged VP9 straight into an MP4 container and
        # the name was right, only the codec inside was not. Renaming the other
        # way (a .webm download) would leave an MP4 wearing a .webm label.
        if filepath.lower().endswith(".mp4"):
            try:
                os.replace(out_path, filepath)
                return filepath, True, ""
            except OSError:
                pass
    return out_path, True, ""


# Keys a processed info dict carries from its OWN format selection. Dropped
# before the dict is processed again, exactly like yt-dlp's --load-info-json
# does (YoutubeDL.sanitize_info), so the download makes a fresh selection with
# its own format / sort / merge options.
_STALE_PICK_KEYS = ("requested_downloads", "requested_formats",
                    "requested_subtitles", "requested_entries", "filepath",
                    "_filename", "filename", "infojson_filename")


def _download_from_preflight(ydl, url, pre_info, bytes_seen, should_cancel):
    """v3.41.3 — the biggest chunk of "Preparing…", removed.

    Every rung used to extract the video TWICE before the first byte: once in
    the pre-flight (download=False, to gate the rung and seed the bar) and then
    again inside extract_info(download=True) — same client, same options, the
    whole player-response + JS-challenge round trip a second time. The
    pre-flight's info dict already holds every stream URL, so it is processed
    for download directly (the same path yt-dlp's --load-info-json uses).

    Safety net: if that reuse fails BEFORE any byte has moved (a stream URL
    the CDN refuses, an extractor quirk), the rung falls back to the old fresh
    extraction once, so nothing that worked before can break. A failure after
    bytes moved, or a user stop, propagates to the ladder unchanged.
    """
    if pre_info and pre_info.get("formats"):
        for k in _STALE_PICK_KEYS:
            pre_info.pop(k, None)
        try:
            return ydl.process_ie_result(pre_info, download=True)
        except Exception as exc:          # noqa: BLE001 — judged below
            if should_cancel is not None and should_cancel():
                raise
            if type(exc).__name__ == "DownloadCancelled" or bytes_seen[0]:
                raise
            log_crash("download: reusing the pre-flight info failed, "
                      "re-extracting: " + str(exc)[:300])
    return ydl.extract_info(url, download=True)


# v1.0.2: the refresh runs on its OWN thread and a download waits for it at
# most _ENGINE_REFRESH_BUDGET_S. Before, it ran inline with no overall
# deadline: on a filtered / throttled network the PyPI wheel trickled in
# forever and the row sat on "Updating downloader… 0%" until the app was
# killed (that row also held one of the two global download slots, so every
# later download queued behind it). Now the download carries on down the
# ladder with the engine it already has, and the user gets a real answer.
_ENGINE_REFRESH_BUDGET_S = 35.0
_ENGINE_REFRESH = {"started": False, "module": None, "abandoned": False,
                   "sink": None, "event": threading.Event()}
_ENGINE_REFRESH_LOCK = threading.Lock()


def _engine_refresh_worker():
    st = _ENGINE_REFRESH

    def _say(text):
        sink = st["sink"]
        if sink:
            try:
                sink(text)
            except Exception:      # noqa: BLE001
                pass

    try:
        from app.core.runtime_deps import (latest_yt_dlp_release,
                                           current_yt_dlp_version,
                                           update_yt_dlp, reload_yt_dlp,
                                           version_tuple)
        release = latest_yt_dlp_release(timeout=12)
        cur = current_yt_dlp_version()
        if cur and version_tuple(cur) >= version_tuple(release["version"]):
            # Already the newest engine: re-downloading the same wheel can't
            # fix a block, it only made the user wait.
            log_crash(f"engine refresh: yt-dlp {cur} is already current, skipped")
            return
        ok, info = update_yt_dlp(
            on_progress=lambda p: _say(tr("Updating downloader… {pct}%").format(pct=p)),
            deadline_s=_ENGINE_REFRESH_BUDGET_S - 3,
            should_cancel=lambda: st["abandoned"])
        if not ok:
            log_crash("engine refresh failed: " + str(info)[:300])
            return
        with _ENGINE_REFRESH_LOCK:
            # Only swap the live module while a download is still waiting for
            # it. If every waiter already moved on, the new wheel is on disk
            # and simply loads on the next launch: no mid-flight module swap.
            if not st["abandoned"]:
                st["module"] = reload_yt_dlp()
    except Exception as exc:      # noqa: BLE001 — refresh is best-effort
        log_crash("engine refresh failed: " + str(exc)[:300])
    finally:
        st["event"].set()


def _refresh_engine_once(_status=None, should_cancel=None):
    """Fetch the newest yt-dlp wheel into the runtime dir and load it, at most
    once per process. Returns the fresh module, or None when nothing newer
    could be loaded IN TIME. Never blocks longer than _ENGINE_REFRESH_BUDGET_S
    and stops waiting at once when the user cancels."""
    st = _ENGINE_REFRESH
    with _ENGINE_REFRESH_LOCK:
        first = not st["started"]
        st["started"] = True
        if _status:
            st["sink"] = _status
    if st["event"].is_set():
        return st["module"]
    if st["abandoned"]:
        return None          # an earlier download already gave up on it
    if _status:
        _status(tr("Updating downloader…"))
    if first:
        threading.Thread(target=_engine_refresh_worker, daemon=True,
                         name="yt-dlp-refresh").start()
    deadline = time.monotonic() + _ENGINE_REFRESH_BUDGET_S
    try:
        while not st["event"].wait(0.25):
            if should_cancel is not None and should_cancel():
                return None
            if time.monotonic() >= deadline:
                log_crash("engine refresh: no answer within "
                          f"{int(_ENGINE_REFRESH_BUDGET_S)}s, continuing with "
                          "the current engine")
                with _ENGINE_REFRESH_LOCK:
                    st["abandoned"] = True
                return None
        return st["module"]
    finally:
        with _ENGINE_REFRESH_LOCK:
            if st["sink"] is _status:
                st["sink"] = None


def download_video(url, target_dir, quality, on_status=None, on_progress=None,
                   proxy_url="", cookies_browser="", on_detail=None,
                   should_cancel=None, on_resolved=None, on_meta=None,
                   resume_pct=0):
    """Download one video to `target_dir`. Blocking — call on a worker thread.

    `quality` is a preset dict from DOWNLOAD_QUALITY_PRESETS. `on_status(text)`,
    `on_progress(pct)` and
    `on_detail(done, total, speed, eta, frag_done, frag_total)` are called from
    this thread; the caller is responsible for marshalling onto the GUI thread
    (Qt signals do that). `on_detail` is optional — it carries the raw numbers a
    live UI needs but a bare percentage can't express: bytes transferred / total,
    bytes-per-second, seconds remaining, and the fragment position
    (`frag_done`/`frag_total`, e.g. "part 32 of 93") that downloads now report
    because they run in fragmented DASH mode. `frag_total` is 0 when the download
    isn't fragmented, in which case the UI just omits the fragment readout.

    `resume_pct` is the percentage the user paused this download at (0 for a
    fresh download). Fragment files are only partially reusable across a
    restart, so the resumed transfer's own byte percentage starts below that
    number; the aggregator maps it onto [resume_pct, 99] so the bar resumes
    exactly where it stopped and climbs continuously.

    `on_resolved(height_px, label)` is called once, after a successful download,
    with the resolution ACTUALLY delivered. Callers persist the row's quality
    label from this rather than from the preset that was requested — a video that
    only had 720p must not leave a row claiming 1080p.

    `on_meta(dict)` is called as soon as yt-dlp has the video's
    metadata (the pre-flight probe, before any bytes move). The dict carries the
    channel's name, id, url and follower count — see channel_meta_from_info.
    Callers use it to complete the library row, which is what gives the player a
    subscriber count and a channel avatar instead of "Subscribers hidden".
    v3.41.3: when the channel avatar isn't cached yet it arrives in a SECOND,
    partial call ({channel_id, channel_thumb_url}) from a side thread, so the
    page read no longer delays the download's start.

    `should_cancel` is an optional zero-arg callable polled from the progress
    hook; when it returns True the download is aborted for real (the partial
    file is cleaned up by yt-dlp) and the call returns (False, DOWNLOAD_CANCELLED,
    "") so the caller can distinguish a user stop from a failure.

    Returns (ok, message_or_error, filepath).
    """
    def _status(text):
        if on_status:
            on_status(text)

    # v1.0.2: refuse up front when the REQUIRED engine component is missing
    # (the JS runtime) instead of half-working at 360p / 403. The PO Token
    # helper is optional and never blocks a download.
    _missing = download_engine_missing()
    if _missing:
        return False, _missing, ""

    # Attach the output format (container / audio codec). A quality that
    # already carries one (a resumed "1080p@mkv" row) keeps it; otherwise the
    # choice saved from the picker is used.
    if not quality.get("container"):
        quality = with_container(quality)
    container = quality["container"]
    final_ext = _final_ext(quality)
    _m = re.search(r"(?:v=|youtu\.be/|/shorts/|/embed/)([\w-]{11})", url or "")
    video_id = _m.group(1) if _m else ""

    # One aggregator for the whole call. A non-audio pick merges video+audio, so
    # two streams are expected until the pre-flight probe reports the real count.
    progress = _ProgressAggregator(1 if quality.get("audio_only") else 2,
                                   resume_pct=resume_pct)
    # GUI throttle (mirrors the cutter's 4/sec): yt-dlp hook ticks arrive many
    # times per second with concurrent fragments, and each one used to become
    # two queued Qt signals + a SQLite write on the GUI thread — the flood that
    # made the percentage/bar look jumpy and the whole UI stutter. The
    # aggregator still folds EVERY tick (floors stay exact); only the GUI
    # emission is throttled, monotonic (never re-emit the same pct within the
    # window) with the final 99 always going out.
    _last_emit = [0.0]
    _last_pct_emit = [-1]
    # v3.41.3: did this rung move any bytes yet? Decides whether a failed
    # reuse of the pre-flight extraction may quietly re-extract (see below).
    _bytes_seen = [False]

    def _hook(d):
        # A user stop takes effect at the next hook tick. yt-dlp's OWN
        # DownloadCancelled is raised (not a custom exception): the extractor
        # recognises it and unwinds the whole download cleanly. A bespoke
        # exception class got caught by the retry ladder further down and the
        # download simply carried on in the background — which is exactly the
        # bug this replaces.
        if should_cancel is not None and should_cancel():
            from yt_dlp.utils import DownloadCancelled
            raise DownloadCancelled("stopped by user")
        if d.get("status") == "downloading":
            _bytes_seen[0] = True
            # Aggregated across every stream/fragment of this download, and
            # monotonic — see _ProgressAggregator for why the raw per-stream
            # numbers bounce. Speed/ETA come back through the aggregator too, so
            # a stream that hasn't reported one yet doesn't blank the readout or
            # restart the countdown.
            pct, done, total, speed, eta, frag_done, frag_total = progress.update(d)
            now = time.monotonic()
            if now - _last_emit[0] < 0.25 and pct <= _last_pct_emit[0]:
                return
            _last_emit[0] = now
            _last_pct_emit[0] = pct
            if on_progress:
                on_progress(pct)
            if on_detail:
                on_detail(int(done), int(total), speed, int(eta),
                          int(frag_done), int(frag_total))
        elif d.get("status") == "finished":
            pct = progress.note_finished()
            if on_progress:
                on_progress(pct)
            _status(tr("Merging…"))          # ffmpeg mux still to come



    def _pp_hook(d):
        # Tell the user what the long silent step at 99% is.
        if d.get("status") != "started":
            return
        name = str(d.get("postprocessor") or "")
        if name in ("ExtractAudio", "VideoConvertor"):
            _status(tr("Converting to {fmt}…").format(fmt=container.upper()))

    ok, message, filepath = False, "", ""
    # The resolution actually delivered, reported through on_resolved so the
    # caller's row can be labelled with what is on disk rather than what was asked
    # for. 0 means "couldn't tell", which callers treat as "leave the label alone".
    delivered_px = 0
    # The best resolution any client was seen to offer. Used to explain a failure
    # ("this video's highest is 1080p") instead of a bare "couldn't get 2160p".
    seen_best_px = 0
    # Channel metadata is reported once, from whichever rung first knows it —
    # normally the pre-flight probe, so it lands before any bytes move.
    meta_sent = False
    src_vkbps, src_acodec = 0, ""   # source streams, for the editor conversion
    # ── global concurrency gate ─────────────────────────────────────────
    # Wait for a slot BEFORE any network work, so a batch of downloads queues
    # instead of all hitting YouTube at once (see _DL_GATE above). Placed here,
    # immediately before the big try, so nothing between acquiring the slot and
    # entering the try can raise and leak it.
    if not _acquire_download_slot(_status, should_cancel):
        return False, DOWNLOAD_CANCELLED, ""
    try:
        try:
            import yt_dlp as _p1      # noqa: F401
            import imageio_ffmpeg as _p2   # noqa: F401
        except ImportError:
            _status(tr("Installing required components…"))
        yt_dlp, ffmpeg_location = ensure_yt_dlp_ready()

        _status(tr("Preparing…"))
        # The quality key is baked into the filename so a second quality of the
        # same video sits BESIDE the first on disk instead of overwriting it.
        q_key = quality.get("key", "")
        if quality.get("audio_lang") and q_key:
            # a dub sits BESIDE the original on disk, never over it
            q_key = f"{q_key} {quality['audio_lang']}"
        name_tmpl = (f"%(title)s [%(id)s] {q_key}.%(ext)s" if q_key
                     else "%(title)s [%(id)s].%(ext)s")
        opts = {
            "outtmpl": os.path.join(target_dir, name_tmpl),
            "format": quality["format"],
            "ffmpeg_location": ffmpeg_location,
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "progress_hooks": [_hook],
            "postprocessor_hooks": [_pp_hook],
            # A mid-download 403 on one fragment is usually a single CDN node
            # rejecting one request — let yt-dlp retry before we call it a loss.
            "retries": 10,
            "fragment_retries": 10,
            "extractor_retries": 3,
            "skip_unavailable_fragments": False,
            # Fetch the file as fixed 10 MB DASH fragments (see the per-rung
            # `dashy` flag below), four at a time. Fragmenting is what gives a
            # steady, known-denominator progress bar and per-fragment retries; the
            # concurrency is what turns a single ~100 KiB/s CDN connection into
            # several, which is the actual speed win.
            "concurrent_fragment_downloads": 4,
            "http_headers": {"User-Agent": _UA},
            # Absorb yt-dlp's own ERROR: lines. Most rungs on this ladder are
            # EXPECTED to fail over, so those lines described normal operation
            # while looking like a broken app in the log. Real failures reach the
            # user through the return value and on_status instead.
            "logger": _QuietLogger(),
        }
        opts.update(js_runtime_opts())   # solve YouTube's JS challenge (deno/node/bun/qjs)
        if quality["audio_only"]:
            spec = next(x for x in AUDIO_CODECS if x["key"] == container)
            opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": container,
                "preferredquality": spec["quality"],
            }]
        else:
            if container == "webm":
                # Native VP9/AV1+Opus streams merge straight into webm. When the
                # chosen resolution only exists as H.264 the merge lands in mkv
                # and the converter turns it into webm, so the file ALWAYS
                # matches the picked format.
                opts["merge_output_format"] = "webm/mkv"
                opts["postprocessors"] = [{
                    "key": "FFmpegVideoConvertor", "preferedformat": "webm"}]
            else:
                opts["merge_output_format"] = container
                # A progressive (single-file) fallback is never merged, so it
                # would keep its own extension — remux it (no re-encode).
                opts["postprocessors"] = [{
                    "key": "FFmpegVideoRemuxer", "preferedformat": container}]
            # TIE-BREAK ONLY — resolution first, so the picked quality is never
            # traded away for a codec preference (the old "+vcodec:avc" alone
            # sorted codec-first and handed back a lower resolution). "res"
            # leads; within the same resolution prefer VP9 then AVC over AV1
            # (AV1 needs recent hardware to decode and can play as audio-only on
            # older machines), but AV1 is still used when it's the only encode
            # at that resolution.
            # Shared with the picker's size probe and the pre-flight so all
            # three select the same streams (see _format_sort).
            opts["format_sort"] = _format_sort(container)
        if proxy_url:
            opts["proxy"] = proxy_url
        # ── extraction fallback ladder ──────────────────────────────────
        # yt-dlp's DEFAULT extraction queries several INNERTUBE clients and
        # merges their format lists, so it sees the full adaptive set — that's
        # what actually yields the requested 1080p. Pinning a single client
        # narrows that list and can silently fall back to a 360p progressive
        # stream. So defaults go FIRST; the pinned clients (see CLIENT_LADDER)
        # are for when the defaults are genuinely blocked — bot check / 403 /
        # DRM-only — which is a per-network condition, not a per-video one.
        # v3.41.2: the session's last good client goes first (see client_ladder)
        client_attempts = client_ladder()
        attempts = []
        if cookies_browser:
            # Real logged-in cookies beat every client trick, so try first — but
            # ONLY when the user actually chose a browser in Settings.
            attempts.append({"cookies": cookies_browser, "clients": None,
                             "loose": False, "dashy": True})
        for clients in client_attempts:
            attempts.append({"cookies": None, "clients": clients,
                             "loose": False, "dashy": True})
        # NOTE — no unconditional chrome/edge/firefox/brave rungs here any more.
        # They used to be appended to EVERY download, so on Windows every single
        # download printed "Failed to decrypt with DPAPI" / "Could not copy Chrome
        # cookie database" whether or not the user had asked for cookies at all.
        # Worse, a DPAPI failure isn't retryable and wasn't recognised as a cookie
        # problem, so it hit the ladder's `break` and killed the download outright —
        # which is why closing Chrome made downloads fail. Cookie rungs are now
        # added only on demand, when YouTube has actually blocked us (see the
        # bot/403 branch in the exception handler below).
        # NON-DASHY fallback rungs: `formats=dashy` DROPS any format that has no
        # `contentLength` (see youtube/_video.py — `and fmt['filesize']`), which
        # is rare but real. So before the loose/progressive rungs, retry the
        # strict adaptive pick WITHOUT fragmenting, so such a video still gets its
        # exact resolution (just as a plain https transfer). These sit after the
        # dashy rungs because fragmenting is preferred whenever it's available.
        # The pinned clients here are the BYPASS part of CLIENT_LADDER, not the
        # old ["ios", "mweb", "web_safari"] pair: a fallback pass is only reached
        # when the web-side clients already failed, so pinning those again made
        # the pass a guaranteed no-op.
        bypass_clients = BYPASS_CLIENTS
        if not quality["audio_only"]:
            attempts.append({"cookies": cookies_browser or None,
                             "clients": None, "loose": False, "dashy": False})
            for clients in bypass_clients:
                attempts.append({"cookies": None, "clients": clients,
                                 "loose": False, "dashy": False})
        # FINAL rungs only: allow the progressive single-file formats. Reached
        # solely when every client above failed to satisfy the strict adaptive
        # expression — i.e. this video really has no adaptive stream at the asked
        # resolution. Keeping these last is the whole point: it means a thin
        # format list from one client can no longer masquerade as success by
        # handing back 360p.
        if not quality["audio_only"]:
            attempts.append({"cookies": cookies_browser or None,
                             "clients": None, "loose": True, "dashy": False})
            for clients in bypass_clients:
                attempts.append({"cookies": None, "clients": clients,
                                 "loose": True, "dashy": False})

        # v1.0.1: the picker's extraction is reused as the first rung's
        # pre-flight when it is still fresh (see _rung_preflight), and the
        # identical uncached rung is dropped so a stale answer can't cost the
        # same client twice — a reuse that fails re-extracts that client
        # fresh anyway (_download_from_preflight).
        cached_probe = _probe_cache_get(
            _probe_cache_key(url, proxy_url, cookies_browser))
        tag = (cached_probe or {}).get(_PROBE_TAG) or {}
        if cached_probe and tag.get("dashy"):
            want_c = tag.get("clients")
            want_k = tag.get("cookies") or None
            attempts = [a for a in attempts
                        if not (a.get("dashy") and not a.get("loose")
                                and (a.get("cookies") or None) == want_k
                                and (a.get("clients") or []) == (want_c or []))]
            attempts.insert(0, {"cookies": want_k, "clients": want_c,
                                "loose": False, "dashy": True,
                                "cached": cached_probe})
        last_err = ""
        refreshed = False
        cookie_db_locked = False   # browser was open and locked its cookie DB
        cookies_tried = bool(cookies_browser)   # cookie rungs already in the ladder
        # The resolution this download must actually deliver. An explicit tier
        # states its own; "best available" has none (height 0), so it is RESOLVED by
        # probing the video — otherwise "best" had no target, nothing could count as
        # falling short, and a 720p progressive file passed for a 1440p video.
        want_px = 0 if quality.get("audio_only") else int(quality.get("height") or 0)
        if not want_px and not quality.get("audio_only"):
            _status(tr("Checking the highest quality this video has…"))
            want_px = probe_max_height(url, proxy_url=proxy_url,
                                       cookies_browser=cookies_browser)
            if want_px:
                seen_best_px = want_px
        floor_px = _quality_floor(want_px) if want_px else 0
        i = -1
        while True:
            i += 1
            if i >= len(attempts):
                # Ladder exhausted with nothing delivered. This used to force the
                # most promising skipped rung to run anyway — deliberately
                # downloading a LOWER quality than the user picked. That is the
                # behaviour being removed: a picked quality is delivered exactly or
                # not at all, so there is nothing left to fall back to here.
                break
            attempt = attempts[i]
            try_opts = dict(opts)
            if attempt.get("loose"):
                # Progressive formats are allowed on this rung, and the muxed
                # 360p file it may return has to be reported honestly rather than
                # silently accepted as the requested quality.
                try_opts["format"] = quality.get("format_loose") or quality["format"]
                _status(tr("No adaptive stream at that quality — trying "
                           "the combined file …"))
            # player_client (which client to ask) and formats=dashy (fragment the
            # streams into 10 MB chunks) both live under the one "youtube"
            # extractor_args key, so they are merged into a single dict — two
            # separate assignments would clobber each other and silently drop the
            # fragmenting.
            yt_args = {}
            if attempt["clients"]:
                yt_args["player_client"] = attempt["clients"]
            if attempt.get("dashy"):
                yt_args["formats"] = ["dashy"]
            if yt_args:
                try_opts["extractor_args"] = {"youtube": yt_args}
            if attempt["cookies"]:
                try_opts["cookiesfrombrowser"] = (attempt["cookies"],)
            # The format expression this rung will use — passed to the pre-flight
            # so it probes the exact streams it's about to download.
            attempt = dict(attempt, format=try_opts["format"])
            # A user stop must beat every retry rung. Checked BEFORE the attempt
            # so a cancel that landed between rungs doesn't start another one.
            if should_cancel is not None and should_cancel():
                return False, DOWNLOAD_CANCELLED, ""
            # ── pre-flight: one metadata call that both gates the rung and seeds
            # the progress bar's denominator (fragment count + byte size) so it
            # never has to guess mid-transfer. A rung whose client can only see,
            # say, 360p is skipped outright instead of downloading a 360p file,
            # measuring it, deleting it and moving on.
            pf = _rung_preflight(yt_dlp, url, opts, attempt,
                                 cached_info=attempt.pop("cached", None))
            best_px = pf["best_px"]
            # The probe already fetched the video's metadata, so it knows the
            # channel. Hand it over now rather than at the end of the transfer,
            # so the library row is complete even if the download is stopped or
            # fails later. Fired once (meta_sent), from the first rung that could
            # see anything at all.
            if not meta_sent and on_meta and pf.get("channel"):
                meta_sent = True
                meta = dict(pf["channel"])
                # The one piece of channel identity yt-dlp does not carry. Read
                # from the channel page, cached per channel for the process, so a
                # batch download from one creator pays for it exactly once.
                # v3.41.3: that page read (up to 15 s) used to sit INSIDE
                # "Preparing…". A cached avatar still rides along now; an
                # uncached one is fetched on a side thread and reported with a
                # second on_meta call (only present fields are written, so the
                # follow-up just adds the avatar).
                cid = meta.get("channel_id") or ""
                if cid in _CHANNEL_AVATAR_CACHE:
                    meta["channel_thumb_url"] = _CHANNEL_AVATAR_CACHE[cid]
                elif cid:
                    def _avatar_later(_cid=cid, _cb=on_meta):
                        thumb = _channel_avatar_url(_cid)
                        if thumb:
                            try:
                                _cb({"channel_id": _cid,
                                     "channel_thumb_url": thumb})
                            except Exception:  # noqa: BLE001 — cosmetic only
                                pass
                    threading.Thread(target=_avatar_later, daemon=True,
                                     name="dl-avatar").start()
                try:
                    on_meta(meta)
                except Exception:              # noqa: BLE001 — never break a download
                    pass
            if best_px > 0:
                seen_best_px = max(seen_best_px, best_px)
            if floor_px and not attempt.get("loose"):
                if best_px >= 0 and best_px < floor_px:
                    last_err = (f"client sees only {best_px}p, "
                                f"asked for {want_px}")
                    continue
            # Seed the aggregator with what this rung will download, so the bar is
            # honest from the first byte. Values are floors — larger live numbers
            # from the hook still win.
            progress.note_totals(expected=pf["expected"],
                                 total_bytes=pf["total_bytes"],
                                 frag_total=pf["frag_total"],
                                 total_exact=pf.get("total_exact", 0))
            # Each rung is a fresh transfer, so the per-stream byte counters
            # restart — but everything the user SEES holds its floor (see
            # _ProgressAggregator.reset).
            progress.reset()
            _bytes_seen[0] = False
            pre_info = pf.pop("info", None)
            try:
                with yt_dlp.YoutubeDL(try_opts) as ydl:
                    info = _download_from_preflight(
                        ydl, url, pre_info, _bytes_seen, should_cancel)
                    reqs = info.get("requested_downloads") or []
                    filepath = ((reqs[0].get("filepath") if reqs else None)
                                or info.get("filepath")
                                or ydl.prepare_filename(info))
                    filepath = _resolve_final_path(
                        filepath, target_dir, video_id or info.get("id") or "",
                        q_key, final_ext)
                    got_px = _delivered_short_side(info, reqs)
                    # The source streams, so an editor conversion can target a
                    # bitrate the picker already predicted (see _predict_output).
                    _sv, _sa = _split_av(_picked_streams(info))
                    _dur = float(info.get("duration") or 0)
                    src_vkbps = _stream_kbps(_sv, _dur) if _sv else 0
                    src_acodec = (_sa or {}).get("acodec") or ""
                    # Fallback for the rungs whose probe said nothing (a rung
                    # that failed its pre-flight still downloads fine): the
                    # finished transfer's own info dict has the same fields.
                    if not meta_sent and on_meta:
                        meta = channel_meta_from_info(info)
                        if meta:
                            meta_sent = True
                            try:
                                on_meta(meta)
                            except Exception:      # noqa: BLE001
                                pass
                if got_px:
                    seen_best_px = max(seen_best_px, got_px)
                # VERIFY, don't trust. yt-dlp reports success for whatever it
                # managed to fetch, so a rung that quietly delivered a smaller
                # stream than asked used to end the loop as a "win" — the "I picked
                # 1080p and a random low quality arrived" bug. A short file is
                # deleted and the next client tried; if the ladder runs out, this
                # FAILS rather than accepting the downgrade (the user asked for a
                # specific quality, and a different file is not that quality).
                if _quality_shortfall(quality, got_px, want_px):
                    last_err = (f"got {got_px}p, asked for {want_px}")
                    _remove_quietly(filepath)
                    filepath = ""
                    if i < len(attempts) - 1:
                        _status(tr("Only {got}p came back — retrying for {want}p …")
                                .format(got=got_px, want=want_px))
                        continue
                    break
                if not filepath or not os.path.isfile(filepath):
                    last_err = "the finished file was not found on disk"
                    if i < len(attempts) - 1:
                        _status(tr("Retrying with another method…"))
                        continue
                    break
                ok, message, last_err = True, filepath, ""
                delivered_px = got_px
                if (not attempt.get("cookies") and not attempt.get("loose")
                        and got_px and got_px > _THIN_PX):
                    note_good_clients(attempt["clients"] or [])
                break
            except Exception as exc:
                # The user stopped this one. Caught as a plain Exception on
                # purpose: yt-dlp wraps a cancelled download in its own error
                # types on some paths, so the AUTHORITATIVE check is the cancel
                # flag itself, not the exception class. Without this, a cancel
                # fell through to the retry ladder and the download quietly
                # started over on the next rung — the "still downloading in the
                # log after I pressed stop" bug.
                if should_cancel is not None and should_cancel():
                    return False, DOWNLOAD_CANCELLED, ""
                last_err = str(exc)
                is_last = (i == len(attempts) - 1)
                # A COOKIE problem is not a download failure. It says nothing about
                # the video, so it must never end the ladder — but a DPAPI failure
                # ("Failed to decrypt with DPAPI") isn't retryable and wasn't
                # recognised as a cookie problem, so it fell through to the `break`
                # below and killed the download. See _is_cookie_problem.
                if attempt.get("cookies") and _is_cookie_problem(last_err):
                    if _is_cookie_db_locked(last_err):
                        cookie_db_locked = True   # user CAN fix this
                    if not is_last:
                        continue
                if not _is_retryable(last_err) or is_last:
                    break
                # bot/403 specifically: refresh yt-dlp, then keep going down
                # the ladder with the fresher extractor code. v1.0.1: ONCE PER
                # PROCESS (was once per download — on a flagged network every
                # blocked download re-fetched the PyPI wheel), and always via
                # the runtime-dir wheel instead of a `pip install` subprocess
                # that silently rewrote the developer's environment.
                if _is_bot_or_403(last_err) and not refreshed:
                    refreshed = True
                    fresh = _refresh_engine_once(_status, should_cancel)
                    if fresh is not None:
                        yt_dlp = fresh
                # Browser cookies are the ONLY thing that gets past a real bot
                # check or a CDN 403, so they are appended to the ladder here —
                # on demand, once YouTube has actually blocked us — rather than
                # being tried on every download whether needed or not. A browser
                # that isn't installed just raises and is skipped by the cookie
                # guard above.
                if _is_bot_or_403(last_err) and not cookies_tried:
                    cookies_tried = True
                    for b in _COOKIE_BROWSERS:
                        if b != cookies_browser:
                            attempts.append({"cookies": b, "clients": None,
                                             "loose": False, "dashy": True})
                    # NEVER let a cookie rung be the LAST rung. Every
                    # Chrome-family store can fail at once — browser running
                    # (DB locked) or App-Bound Encryption on Chrome 127+
                    # ("Failed to decrypt with DPAPI") — and when the last rung
                    # of the ladder is a cookie rung, that failure ENDS the
                    # download with the misleading "close your browser" message.
                    # These no-cookie client rungs run after them, so the ladder
                    # always ends on a rung that can actually succeed.
                    # (only the rungs that may answer differently after
                    # the engine refresh above — not the whole ladder again)
                    for clients in ([], ["tv"]):
                        attempts.append({"cookies": None, "clients": clients,
                                         "loose": False, "dashy": True})
                nxt = attempts[i + 1] if i + 1 < len(attempts) else None
                _status(tr("Trying browser cookies…") if (nxt and nxt.get("cookies"))
                        else tr("Retrying with another method…"))

        if not ok:
            # Give the user something actionable instead of yt-dlp's wall of text.
            # The quality answer comes FIRST: when the video simply doesn't have the
            # requested tier, that is the whole story and every other explanation
            # would be a guess.
            if want_px and seen_best_px and seen_best_px < _quality_floor(want_px):
                message = tr(
                    "This video doesn't have {want}p. The highest it offers is "
                    "{got} — pick that quality instead."
                ).format(want=want_px, got=_resolution_label(seen_best_px))
            elif find_js_runtime() is None:
                # The real cause of most "blocked" downloads now: YouTube's JS
                # challenge can't be solved without a JS runtime (deno/node/bun/
                # quickjs). Say so plainly instead of blaming cookies, and point
                # at the installer.
                message = tr(
                    "To download from YouTube, the app needs a small component "
                    "(deno). Open the download again and install it when asked.")
            elif cookie_db_locked:
                message = tr(
                    "YouTube blocked this download. Close your browser "
                    "(Chrome/Edge/Firefox) completely, then try the download "
                    "again — the app can then use its YouTube login to get "
                    "past the block.")
            elif _is_bot_or_403(last_err):
                message = tr(
                    "YouTube blocked this download (bot check). Sign in to "
                    "YouTube in your browser, then set “Use cookies from "
                    "browser” in Settings — or try a different VPN location "
                    "— and download again.")
            elif _is_drm(last_err):
                message = tr(
                    "YouTube only offered DRM-protected formats for this "
                    "video, so it can't be downloaded. This sometimes clears "
                    "up on its own — try again later, or set “Use cookies "
                    "from browser” in Settings.")
            elif want_px:
                # The ladder ran out without ever delivering the asked resolution,
                # and nothing measured how high the video actually goes.
                message = tr(
                    "Couldn't get {want}p for this video. Try “Best available”, "
                    "or a lower quality."
                ).format(want=want_px)
            else:
                message = last_err
            # Nothing half-downloaded may be left behind: a stray .part looks like
            # a file the user can play.
            _remove_quietly(filepath)
            filepath = ""
        # Tell the caller what actually landed, so the row's quality label comes
        # from the file rather than from the request. Only on success, and only
        # when the resolution could be read — a caller must never relabel a row
        # from a guess. Audio-only has no resolution to report.
        #
        # There is no "downloaded at a lower tier" branch any more: a short file is
        # now a failure, so a successful return always means the requested quality.
        if ok and on_resolved and delivered_px and not quality.get("audio_only"):
            on_resolved(int(delivered_px),
                        f"{_resolution_label(delivered_px)} · {container.upper()}")

        # Editor compatibility: an MP4 pick must actually be an MP4 that an
        # editor can open. YouTube serves 1080p+ as VP9/AV1, so the merged file
        # keeps that codec and Premiere rejects it ("unsupported file or
        # damaged"). Resolution is never traded away to fix this — the CODEC is
        # converted afterwards. No-op when the stream was already H.264, for
        # every non-MP4 container, and for audio-only picks.
        if ok and filepath and container == "mp4" and not quality.get("audio_only"):
            try:
                _yt_dlp2, ffmpeg_dir = ensure_yt_dlp_ready()
                # The H.264 editor conversion runs AFTER the transfer is done
                # (bar already at 99 via note_finished + "Merging…" status).
                # It must NOT drive the download % bar: its own 0→100 used to
                # overwrite the finished transfer, so the row visibly restarted
                # from zero ("downloads twice") and then sat on
                # "Downloading 100%" while still running — 100 belongs to the
                # finished file on disk (_on_dl_done), never to an in-flight
                # row. Progress stays pinned at 99; the row keeps its
                # "Merging…" indeterminate state until the worker returns.
                # Detailed codec messages are also suppressed for the same
                # reason: they overwrote the "Merging…" text the VMs and QML
                # match on to show the indeterminate merge state.
                _status(tr("Merging…"))
                if on_progress:
                    try:
                        on_progress(99)
                    except Exception:   # noqa: BLE001 — progress is best-effort
                        pass

                def _conv_status(_t):
                    return None

                def _conv_progress(_p):
                    return None

                filepath, _converted, conv_err = _convert_for_editors(
                    ffmpeg_dir, filepath, quality, _conv_status,
                    _conv_progress, should_cancel,
                    src_vkbps=src_vkbps, src_acodec=src_acodec)
                if conv_err == DOWNLOAD_CANCELLED:
                    return False, DOWNLOAD_CANCELLED, ""
            except Exception as exc:      # noqa: BLE001 — the download succeeded
                log_crash("editor conversion failed:\n" + str(exc))
    except Exception as exc:
        ok, message = False, str(exc)
    finally:
        # Release on EVERY exit — success, failure or a user stop — so a queued
        # download always gets its turn.
        _release_download_slot()
    return ok, message, filepath
