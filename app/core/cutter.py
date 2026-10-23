"""app.core.cutter - YouTube Hunter.

UI-free video segment cutter for the QML front-end.

A user hands over a YouTube link (or a local file) plus a [start, end) range,
picks a quality, and gets ONLY that segment on disk. The full video is never
downloaded first: for links, yt-dlp resolves the direct stream URLs and ffmpeg
seeks straight to the segment over HTTP, so a 2-hour video costs roughly the
bytes of the chosen minutes. Everything here is stdlib + yt-dlp + ffmpeg
(no Qt), so it runs on a worker thread and reports through callbacks.

Quality ladder goes up to 2160p (4K): whatever the source genuinely ships,
from 360p to 4K, is offered, highest first. Cuts are stream copies (`-c copy`), so
the segment keeps the source's exact quality and finishes fast; the tradeoff
is keyframe precision (the cut lands on the nearest seek point, typically
within a couple of seconds) rather than frame accuracy.
"""

import os
import re
import subprocess
import sys
import tempfile
import threading

from app.core.download import (
    BYPASS_CLIENTS, DOWNLOAD_CANCELLED, client_ladder, note_good_clients,
    _info_richness, _COOKIE_BROWSERS, _fmt_short_side, _stream_kbps,
    _vcodec_family,
    _is_bot_or_403, _is_cookie_problem, _QuietLogger, _UA,
    channel_meta_from_info, friendly_extract_error)
from app.core.audio_tracks import (audio_tracks_from_formats, select_audio,
                                    lang_format_expr)
from app.core.net import explain_network_error
from app.core.runtime_deps import js_runtime_opts
from app.core.utils import ensure_yt_dlp_ready
from app.i18n import tr

# Qualities offered for a link, highest first — the video's REAL range, up to
# 4K. Whatever rungs the source genuinely ships (360p … 2160p) are listed, so
# a 4K video offers 4K and a 1080p-only video tops out at 1080p.
_CUT_CAPS = (2160, 1440, 1080, 720, 480, 360)

_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m|\[\d+(?:;\d+)*m")


def clean_error(text):
    """Make an engine error human-readable: strip ANSI colour codes (with or
    without their escape byte — both show up in the wild), the shouting
    'ERROR:' prefixes yt-dlp decorates every failure with, and the
    'See https://…' developer links. Never returns an empty string."""
    s = _ANSI_RE.sub("", str(text or ""))
    s = re.sub(r"\s+", " ", s).strip()
    # yt-dlp decorates every failure level with its own "ERROR:" marker
    # ("ERROR: [youtube] id: ERROR: real cause") — drop them all, then the
    # developer link tail.
    s = re.sub(r"\bERROR:\s*", "", s)
    s = re.sub(r"\s*See https?://\S+.*$", "", s).strip()
    return s or tr("Unknown error.")


def _friendly_or_clean(err_text):
    """Bot-check / cookie / missing-JS-runtime failures get an actionable
    sentence; anything else keeps the existing cleanup.

    The raw engine line — "[youtube] <id>: Sign in to confirm you're not a bot.
    Use --cookies-from-browser or --cookies for the authentication." — is a
    developer message, and it was reaching the customer verbatim in the cutter's
    log panel with nothing they could act on. Same mapping the download page
    already applies, so one failure reads the same wherever it happened.
    """
    friendly = friendly_extract_error(err_text)
    if friendly and friendly != str(err_text or ""):
        return friendly
    return clean_error(err_text)


def _base_ydl_opts(proxy_url="", cookies_browser=""):
    opts = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "http_headers": {"User-Agent": _UA},
        "extractor_retries": 2,
        "retries": 3,
        "logger": _QuietLogger(),
    }
    opts.update(js_runtime_opts())   # solve YouTube's JS challenge (deno/node/bun/qjs)
    if proxy_url:
        opts["proxy"] = proxy_url
    if cookies_browser:
        opts["cookiesfrombrowser"] = (cookies_browser,)
    return opts


def _extract(url, proxy_url="", cookies_browser="", clients=None):
    """Metadata-only extraction with one client set. Returns (info, error)."""
    yt_dlp, _ffmpeg = ensure_yt_dlp_ready()
    opts = _base_ydl_opts(proxy_url, cookies_browser)
    if clients:
        opts["extractor_args"] = {"youtube": {"player_client": clients}}
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            return ydl.extract_info(url, download=False), ""
    except Exception as exc:          # noqa: BLE001 — surfaced to the caller
        return None, explain_network_error(exc, "YouTube")


# ── v3.41.3: the link read is reused between "paste" and "cut" ─────────────
# probe_link() walks the whole client ladder when a link is pasted; cut_link()
# used to walk it AGAIN ("Reading the video…") seconds later, before ffmpeg
# could start. The read is now kept for a few minutes and reused. Stream URLs
# live for hours, and the stale-URL retry ("Refreshing streams…") always
# bypasses the cache, so a cut can never be stuck on an expired link.
# v1.1.2: 15 min -> 2 h. With 15 min, choosing a segment for longer than
# that made the cut re-read the whole link (seconds of yt-dlp work that also
# stalled the UI) right when Cut was pressed. Stream URLs live ~6 h and an
# expired one is re-read anyway by the "Refreshing streams…" retry.
_LADDER_TTL_S = 2 * 60 * 60
_LADDER_MAX = 6
_ladder_cache = {}              # key -> (monotonic_ts, result tuple)
_ladder_lock = threading.Lock()


def _light_copy_result(result):
    """Copy of a ladder result (info, err, saw_cookie, formats) without
    copy.deepcopy — see download.light_copy_info: the deepcopy held the GIL
    for seconds and froze the whole UI at the start of a cut."""
    from app.core.download import light_copy_info, _light_copy_fmt
    info, err, saw_cookie, fmts = result
    return (light_copy_info(info), err, saw_cookie,
            [_light_copy_fmt(f) for f in (fmts or [])])


def _extract_with_ladder(url, proxy_url="", cookies_browser="", use_cache=True):
    """Cached front door for _extract_with_ladder_uncached (see above)."""
    import copy
    import time as _t
    key = ((url or "").strip(), proxy_url or "", cookies_browser or "")
    if use_cache:
        with _ladder_lock:
            hit = _ladder_cache.get(key)
            if hit and _t.monotonic() - hit[0] > _LADDER_TTL_S:
                _ladder_cache.pop(key, None)
                hit = None
        if hit:
            try:
                return _light_copy_result(hit[1])
            except Exception:         # noqa: BLE001 — cache is best-effort
                pass
    result = _extract_with_ladder_uncached(url, proxy_url, cookies_browser)
    if result and result[0] is not None:
        try:
            snap = _light_copy_result(result)
        except Exception:             # noqa: BLE001
            snap = None
        if snap is not None:
            with _ladder_lock:
                _ladder_cache[key] = (_t.monotonic(), snap)
                if len(_ladder_cache) > _LADDER_MAX:
                    oldest = min(_ladder_cache, key=lambda k: _ladder_cache[k][0])
                    _ladder_cache.pop(oldest, None)
    return result


def _extract_with_ladder_uncached(url, proxy_url="", cookies_browser=""):
    """extract_info across a client fallback ladder: the user's cookies first
    (when set — logged-in cookies beat every client trick against bot checks),
    then the same call WITHOUT cookies across the default + pinned clients.

    The no-cookie rungs matter because a cookie failure (Chrome open with a
    locked profile, DPAPI decryption refusing) is an environment problem, not
    a video problem — without them one locked browser made every link fail.

    Keeps walking past a successful-but-thin extraction (a throttled SABR
    response: no progressive stream and fewer than 2 quality rungs): the
    cutter lives on its quality ladder, so the RICHEST format list wins, not
    merely the first one that answers. Stops early on any normal response.

    Returns (info, error, saw_cookie_problem, preview_formats): `info` is the
    richest response (drives duration/qualities/cut streams);
    `preview_formats` merges the formats of EVERY successful rung, deduped.
    That matters for the preview player: the richest rung (often an iOS/SABR
    response) frequently carries NO progressive stream at all, while an
    earlier rung has the AVC progressive the preview needs for PICTURE+SOUND.
    Picking the preview from the merged pool finds sound where the richest
    rung alone offered a silent video-only stream."""
    plan = []
    if cookies_browser:
        plan.append({"cookies": cookies_browser, "clients": None})
    for clients in client_ladder():
        plan.append({"cookies": None, "clients": clients})
    last_err, saw_cookie = "", False
    best_info, best_caps = None, []
    preview_formats, _seen_fmt = [], set()

    def _rich_enough(info):
        # v3.41.2: "rich" = video-only adaptive streams above 360p (see
        # download._info_richness). The old rule also accepted "one rung plus a
        # progressive stream" as genuine, but that is EXACTLY what a flagged
        # IP gets (Belgian/VPN exits: itag 18 only, 360p), so the cutter showed
        # 360p as the ceiling there. A real 360p-only upload is now recognised
        # by several clients agreeing (thin_seen below) instead.
        if not info:
            return False
        return _info_richness(info)[1]
    thin_seen = 0

    for attempt in plan:
        info, err = _extract(url, proxy_url, attempt["cookies"],
                             attempt["clients"])
        if info:
            # `best_info is None` has to be part of this test. A rung CAN answer
            # with an info dict that carries no usable format at all (a
            # throttled/SABR response), and with the old `len(caps) > len(best_caps)`
            # test alone nothing was assigned — then `_rich_enough(best_info)`
            # ran on None and the whole read died with
            # "'NoneType' object has no attribute 'get'". That is a hard crash
            # inside the ladder, so it depended entirely on which rung answered
            # first: fine on one machine, an error on the next.
            caps = _available_caps(info.get("formats") or [])
            if best_info is None or len(caps) > len(best_caps):
                best_info = info
                best_caps = caps
            for f in info.get("formats") or []:
                key = f.get("format_id") or f.get("url")
                if f.get("url") and key not in _seen_fmt:
                    _seen_fmt.add(key)
                    preview_formats.append(f)
            if _rich_enough(info):
                if attempt["clients"] is not None and not attempt["cookies"]:
                    note_good_clients(attempt["clients"])
                best_info, best_caps = info, caps
                break
            thin_seen += 1
            if thin_seen >= 4:       # several clients agree: the video is low-res
                break
            continue
        last_err = err
        saw_cookie = saw_cookie or _is_cookie_problem(err)
    if best_info is not None:
        return best_info, "", saw_cookie, preview_formats
    return None, last_err or "extraction failed", saw_cookie, []


def _cookie_hint():
    return tr("Your browser cookies couldn't be read either — close that "
              "browser, or set Download cookies to None in Settings.")


def _is_direct_http(f):
    """True when ffmpeg can seek-and-copy this stream over plain HTTP(S).

    HLS/DASH-manifest URLs (`m3u8_native`, `http_dash_segments`, …) hang
    ffmpeg's seek path indefinitely — verified live: a 4K HLS playlist URL
    produced zero output for 150 s while the direct https stream of the same
    tier finished a 10 s clip in seconds. That is the whole "4K/1440p never
    downloads but 1080p does" split: those tiers' highest-tbr variants are
    HLS playlists, so they were picked first and stalled every attempt.
    yt-dlp itself downloads such URLs fine with its own HLS/DASH code (which
    is why the Downloads page and the fetch-then-cut fallback work), but the
    cutter hands URLs straight to ffmpeg, so only plain https/http streams
    are eligible here.
    """
    proto = str(f.get("protocol") or "https").lower().split("+")[0].strip()
    return proto in ("https", "http")


def _available_caps(formats):
    """Distinct heights this video genuinely ships, desc (360p … 2160p).

    A stream belongs to the largest rung at or below its height (10%
    tolerance, so a 1072-tall "1080p" Short still counts as 1080p) — same
    bucketing the download ladder uses. Anything under the 360p rung is not
    offered. Only DIRECT https streams count: an HLS-only tier can never be
    cut with the seek-and-copy path, so offering it would promise a quality
    the fast path cannot deliver (see _is_direct_http).
    """
    seen = set()
    for f in formats or []:
        if (f.get("vcodec") or "none") == "none":
            continue
        if not _is_direct_http(f):
            continue
        px = _fmt_short_side(f)
        for cap in _CUT_CAPS:
            if px and px >= cap * 0.9:
                seen.add(cap)
                break
    return sorted(seen, reverse=True)


def _preview_codec_rank(f):
    """How safely the in-page Qt preview can DECODE a stream.

    The user's log showed the failure mode: the picker chose a 360p mp4 that
    turned out to be AV1 (`compatible_brands iso6av01mp41`, itag 396) on a PC
    with no AV1 hardware decoding — Qt's FFmpeg fell back to software, failed
    (`Failed setup for format d3d11`), and the preview stayed black on every
    video, short or long. Extension alone says nothing (AV1 ships as .mp4),
    so rank the actual codec: AVC (hardware everywhere) first, VP9 (bundled
    software decode is fine) next, anything unknown neutral, AV1 last.
    """
    vc = (f.get("vcodec") or "").lower()
    if vc.startswith("avc"):
        return 2
    if vc.startswith("vp9") or vc == "vp09":
        return 1
    if "av01" in vc or vc.startswith("av1"):
        return -2
    return 0


# The in-page preview streams at up to 1080p — never above it. 1440p/4K is
# gigabytes per hour to buffer and decode just to choose a cut point, and it is
# what Cut & Download is for. A video that tops out lower (720p, 480p, ...)
# simply previews at its own best. Short side, so a vertical 1080x1920 Short
# counts as 1080p; a few px of slack for odd encodes (1088, 1072, ...).
PREVIEW_MAX_PX = 1080
_PREVIEW_PX_SLACK = 20


def _audio_preview_rank(f):
    """Best audio-only stream for the preview's sound track.

    Original-language track first (dubbed videos ship several), then AAC/m4a
    (decodes everywhere Qt runs) over Opus, then the normal track over a
    "-drc" (dynamic-range-compressed) twin, then bitrate."""
    try:
        lang_pref = float(f.get("language_preference")
                          if f.get("language_preference") is not None else -1)
    except (TypeError, ValueError):
        lang_pref = -1.0
    ac = (f.get("acodec") or "").lower()
    ext = (f.get("ext") or "").lower()
    codec = 2 if (ac.startswith("mp4a") or ext == "m4a") else (
        1 if "opus" in ac else 0)
    not_drc = 0 if "drc" in str(f.get("format_id") or "").lower() else 1
    try:
        abr = float(f.get("abr") or f.get("tbr") or 0)
    except (TypeError, ValueError):
        abr = 0.0
    return (lang_pref, codec, not_drc, abr)


def _audio_lang_rank(f):
    """How "original" an audio-only stream is (higher = more original).

    Dubbed videos ship one audio track PER language (YouTube auto-dubs and
    creator dubs: Arabic, Spanish, Hindi, ...). The cut used to rank audio by
    container fit + bitrate only, so whichever dub happened to have the
    highest bitrate (often the first one, e.g. Arabic) became the clip's
    sound. yt-dlp marks the original track with the highest
    `language_preference` and "original" in its format_note; the
    audio-description track gets a negative one. Both are folded in here."""
    try:
        lp = float(f.get("language_preference")
                   if f.get("language_preference") is not None else -1)
    except (TypeError, ValueError):
        lp = -1.0
    note = str(f.get("format_note") or "").lower()
    is_orig = 1 if "original" in note else 0
    is_desc = 1 if "descriptive" in note or "audio description" in note else 0
    return (is_orig, lp, -is_desc)


def _original_audio_only(auds, lang=""):
    """Keep only ONE language's audio tracks: the original by default, or the
    dub the user picked (`lang`, see app.core.audio_tracks). Untouched when the
    video has a single language."""
    return select_audio(auds, lang)


def _pick_preview_audio(formats, lang=""):
    """URL of the stream the preview should take its SOUND from, or "".

    YouTube only ships picture+sound together at 360p (when at all); every HD
    tier is video-only. So an HD preview gets a second, audio-only stream that
    the page plays in lock-step with the picture. Falls back to the lightest
    progressive stream's sound when there is no audio-only stream at all."""
    auds, progs = [], []
    for f in formats or []:
        if not f.get("url") or not _is_direct_http(f):
            continue
        has_v = (f.get("vcodec") or "none") != "none"
        has_a = (f.get("acodec") or "none") != "none"
        if has_a and not has_v:
            auds.append(f)
        elif has_a and has_v:
            progs.append(f)
    if auds:
        auds = _original_audio_only(auds, lang)
        return max(auds, key=_audio_preview_rank)["url"]
    if progs:
        return min(progs, key=lambda f: _fmt_short_side(f) or 0)["url"]
    return ""


def _pick_preview(formats, duration=0.0):
    """The stream the in-page preview player plays.

    Returns (url, has_audio, is_av1, px, audio_url):
      * url        — the picture: the best stream at or below 1080p
                     (PREVIEW_MAX_PX), highest resolution first. A 4K video
                     previews at 1080p; a 720p-only video at 720p.
      * audio_url  — a separate audio-only stream to play alongside it when
                     the picture has no sound of its own ("" otherwise).
      * has_audio  — True when the preview will have sound either way.
      * is_av1     — True only when AV1 was literally the sole option, so the
                     page can warn that it may not decode here.
      * px         — the picked short side, for the page's quality badge.

    Codec matters as much as size: at the same resolution AVC (hardware
    decode everywhere) wins over VP9, and AV1 is never picked while anything
    else fits — Qt's software AV1 fallback fails outright on many PCs (black
    preview). At the same resolution and codec a progressive stream wins, since
    it carries its own sound.

    NOTE: pass the MERGED formats from every ladder rung (see
    _extract_with_ladder): the richest rung is often an iOS/SABR response
    with no progressive / audio stream at all, while another rung has them.
    """
    cands = []
    for f in formats or []:
        if (f.get("vcodec") or "none") == "none" or not f.get("url"):
            continue
        # Qt's MediaPlayer cannot play HLS playlist URLs (and they stall) —
        # preview from direct https streams only (see _is_direct_http).
        if not _is_direct_http(f):
            continue
        px = _fmt_short_side(f) or 0
        if not px:
            continue
        prog = (f.get("acodec") or "none") != "none"
        cands.append((px, prog, f))

    limit = PREVIEW_MAX_PX + _PREVIEW_PX_SLACK

    def _best(allow_av1, at_most=True):
        pool = [(px, prog, f) for px, prog, f in cands
                if (px <= limit) == at_most]
        if not allow_av1:
            pool = [t for t in pool if _preview_codec_rank(t[2]) > -2]
        if not pool:
            return None
        if at_most:
            # highest resolution ≤ 1080p, then the safest codec, then sound
            key = lambda t: (t[0], _preview_codec_rank(t[2]), 1 if t[1] else 0,
                             1 if (t[2].get("ext") or "") == "mp4" else 0)
            return max(pool, key=key)
        # Nothing at/below 1080p (rare: a 1440p/4K-only upload) — the
        # SMALLEST tier above it, never the biggest.
        key = lambda t: (-t[0], _preview_codec_rank(t[2]), 1 if t[1] else 0)
        return max(pool, key=key)

    pick = (_best(False) or _best(True)
            or _best(False, at_most=False) or _best(True, at_most=False))
    if not pick:
        return "", False, False, 0, ""
    px, prog, f = pick
    is_av1 = _preview_codec_rank(f) <= -2
    if prog:
        return f["url"], True, is_av1, px, ""
    audio_url = _pick_preview_audio(formats)
    return f["url"], bool(audio_url), is_av1, px, audio_url


def probe_link(url, proxy_url="", cookies_browser=""):
    """What a link offers the cutter. Blocking — call on a worker thread.

    Returns (ok, info, error); info carries video_id, title, duration
    (seconds, float), thumb_url, preview_url + preview_has_audio (a light
    stream for the page's preview player) and qualities=[{key,height,label,
    sub}] with key 0 meaning "best available" (highest the video ships, up to
    4K). `thin` is True when
    YouTube only showed 360p-or-less (throttled read — see above), so the
    page can offer a fix instead of presenting 360p as the whole story.
    Direct stream URLs are deliberately NOT returned — they expire within
    hours, so cut_link() re-resolves them fresh at cut time.
    """
    url = (url or "").strip()
    if not url:
        return False, {}, tr("Paste a YouTube link first.")
    try:
        # A paste is always a FRESH read (it also refills the cache the cut
        # will reuse), so re-pasting a link after a throttled read retries it.
        info, err, saw_cookie, preview_formats = _extract_with_ladder(
            url, proxy_url, cookies_browser, use_cache=False)
    except Exception as exc:          # noqa: BLE001 — e.g. missing engine
        return False, {}, clean_error(str(exc))
    if not info:
        msg = clean_error(err) or tr("Couldn't read that video.")
        if saw_cookie and "cookie" not in msg.lower():
            msg = f"{msg} {_cookie_hint()}"
        return False, {}, msg
    formats = info.get("formats") or []
    caps = _available_caps(formats)
    if not caps:
        return False, {}, tr("This video has no downloadable video stream.")
    duration = 0.0
    try:
        duration = float(info.get("duration") or 0)
    except (TypeError, ValueError):
        duration = 0.0
    if duration <= 0:
        return False, {}, tr("Couldn't read this video's duration.")
    quals = [{"key": 0, "height": 0, "label": tr("Best quality"),
              "sub": tr("highest available")}]
    for cap in caps:
        sub = ("4K · direct" if cap >= 2160 else
               "mp4 · direct" if cap <= 720 else "hd · direct")
        quals.append({"key": cap, "height": cap, "label": f"{cap}p",
                      "sub": sub})
    preview_url, preview_audio, preview_av1, preview_px, preview_audio_url = \
        _pick_preview(preview_formats or formats, duration)
    # Thin response: YouTube only showed 360p-or-less for this read (bot-check
    # throttling, missing deno JS runtime, or no cookies on a flagged network).
    # The page surfaces this honestly with a fix-it banner instead of silently
    # offering "360p" as if that were all the video has.
    thin = max(caps) <= 360 if caps else True
    # Dubbed videos: every audio language on offer (original first), plus a
    # preview sound URL per dub so the page can PLAY the picked language.
    pool_fmts = preview_formats or formats
    audio_tracks = audio_tracks_from_formats(
        [f for f in pool_fmts if _is_direct_http(f)])
    preview_audio_by_lang = {}
    for t in audio_tracks:
        if t["key"]:
            u = _pick_preview_audio(pool_fmts, t["key"])
            if u:
                preview_audio_by_lang[t["key"]] = u
    return True, {
        "video_id": info.get("id") or "",
        "title": info.get("title") or tr("Untitled"),
        "duration": duration,
        "thumb_url": info.get("thumbnail") or "",
        "qualities": quals,
        # Light stream for the page's preview player (fresh URLs expire
        # within hours — the VM re-probes silently when one goes stale).
        "preview_url": preview_url,
        "preview_has_audio": preview_audio,
        # Separate sound track for a video-only (HD) preview — the page plays
        # it in sync with the picture. "" when the picture carries its own.
        "preview_audio_url": preview_audio_url,
        # True only when AV1 was the sole option: the page warns that such a
        # preview may not decode on PCs without AV1 hardware (Cut is
        # unaffected — it runs through ffmpeg directly).
        "preview_is_av1": preview_av1,
        # Short side actually picked (0 = unknown): the page's quality badge.
        "preview_px": preview_px,
        # See above: the page warns + offers deno/cookies/re-read.
        "thin": thin,
        # v1.2: [{key, lang, name, native, nameFa, kind, kbps, rtl}] — [] for
        # a single-language video. key "" = original.
        "audio_tracks": audio_tracks,
        "preview_audio_by_lang": preview_audio_by_lang,
        # v3.16-p4: who made it (name, id, url, subs) — free from the same
        # payload. Recorded with every clip so the player can show the real
        # channel logo + name. The avatar itself is fetched by the VM.
        "channel": channel_meta_from_info(info),
    }, ""


def _vcodec_name(f):
    return (f.get("vcodec") or "").lower()

def _acodec_name(f):
    return (f.get("acodec") or "").lower()

def _ext_name(f):
    return (f.get("ext") or "").lower()


def _container_for_pair(v_fmt, a_fmt):
    """Output container that can hold (video, audio) with `-c copy`.

    WebM only accepts VP8/VP9/AV1 video + Opus/Vorbis audio — a VP9 video with
    an AAC (m4a) track fails outright ("Only VP8 or VP9 or AV1 ..."). MP4
    accepts AVC/HEVC/AV1 (+VP9 on recent ffmpeg) with AAC, but Opus-in-MP4
    fails on older builds. MKV accepts everything, so any MIXED pair
    (mp4-video + opus-audio, webm-video + aac-audio, ...) falls back to MKV
    instead of failing the whole cut. Progressive single-file picks keep
    their own container.
    """
    if a_fmt is None:
        return _ext_name(v_fmt) or "mp4"
    v_ext = _ext_name(v_fmt)
    a_ext = _ext_name(a_fmt)
    vc, ac = _vcodec_name(v_fmt), _acodec_name(a_fmt)
    v_is_webm = v_ext == "webm" or vc.startswith("vp9") or vc.startswith("vp8")
    a_is_opus = ("opus" in ac or "vorbis" in ac or a_ext == "webm"
                 or a_ext == "opus")
    a_is_aac = ("aac" in ac or "mp4a" in ac or a_ext == "m4a"
                or a_ext == "aac" or a_ext == "mp4")
    if v_is_webm and a_is_opus:
        return "webm"
    if not v_is_webm and a_is_aac:
        return "mp4"
    if v_is_webm and v_ext == "webm" and a_ext == "webm":
        return "webm"
    if v_ext == "mp4" and a_ext in ("mp4", "m4a", "aac"):
        return "mp4"
    # Mixed / uncertain pair (the classic 4K case: VP9-webm video + AAC-m4a
    # audio): MKV holds any codec with stream copy, so the cut succeeds at
    # full quality instead of erroring out.
    return "mkv"


def _audio_compat_rank(a_fmt, v_fmt):
    """Higher = better audio partner for this video (container compatibility
    first, bitrate second — handled by the caller)."""
    v_ext = _ext_name(v_fmt)
    vc = _vcodec_name(v_fmt)
    a_ext = _ext_name(a_fmt)
    ac = _acodec_name(a_fmt)
    v_is_webm = v_ext == "webm" or vc.startswith("vp9") or vc.startswith("vp8")
    a_is_opus = ("opus" in ac or "vorbis" in ac or a_ext in ("webm", "opus"))
    a_is_aac = ("aac" in ac or "mp4a" in ac or a_ext in ("m4a", "aac", "mp4"))
    if v_is_webm:
        if a_is_opus:
            return 2
        if a_is_aac:
            return 0
        return 1
    if a_is_aac:
        return 2
    if a_is_opus:
        return 0
    return 1


def _is_hls_stream(f):
    """True when a format is an HLS playlist/manifest, not a seekable file.

    The ffmpeg HTTP-seek cut path needs plain videoplayback URLs. Fed an HLS
    manifest it stalls forever: YouTube's playlists can come back without
    #EXT-X-ENDLIST (or as an error body), so ffmpeg's HLS demuxer polls the
    playlist until the end of time — near-zero CPU, zero output. That is the
    "4K never downloads" hang: high tiers (2160p/1440p) often arrive ONLY as
    HLS manifests, and the picker ranked them above the direct URLs. Such
    tiers are cut through the yt-dlp fetch-then-cut fallback instead, which
    plays HLS/SABR with its own client machinery.
    """
    if not f:
        return False
    proto = (f.get("protocol") or "").lower()
    if proto.startswith("m3u8"):
        return True
    u = f.get("url") or ""
    return ("/hls_playlist/" in u or "manifest.googlevideo.com" in u
            or ".m3u8" in u)


def _pick_streams(formats, cap_h, audio_lang=""):
    """Direct URLs for at most `cap_h` (0 = highest available, up to 4K).

    Prefers a single progressive mp4 (one download, no mux); otherwise the
    best mp4 video-only stream plus the best m4a audio. Returns
    (video_url, audio_url_or_None, ext, picked_px) with picked_px the short
    side actually resolved, or (None, None, "", 0) when nothing fits.
    """
    cap = int(cap_h or 2160)
    if cap <= 0 or cap > 2160:
        cap = 2160

    def ok_height(f):
        px = _fmt_short_side(f)
        return px and px <= cap

    def _video_rank(f):
        return (
            _fmt_short_side(f),
            1 if (f.get("ext") or "") == "mp4" else 0,
            1 if (f.get("vcodec") or "").startswith("avc") else 0,
            f.get("tbr") or 0)

    # Resolution wins over container convenience: the highest video ≤ cap is
    # picked FIRST, and only then decided whether it comes as one progressive
    # file (no mux) or as video-only + audio (muxed). The old order preferred
    # ANY progressive stream, so a 720p progressive (itag 22) beat 1080p/4K
    # adaptive streams and the cut silently arrived a tier lower than picked.
    # Direct https streams only: HLS/DASH-manifest URLs hang ffmpeg's seek
    # path (see _is_direct_http) — the 4K/1440p tiers' highest-tbr variants
    # are exactly such playlists, which is why those tiers always stalled.
    prog = [f for f in (formats or [])
            if (f.get("vcodec") or "none") != "none"
            and (f.get("acodec") or "none") != "none"
            and ok_height(f) and f.get("url") and _is_direct_http(f)]
    vids = [f for f in (formats or [])
            if (f.get("vcodec") or "none") != "none"
            and (f.get("acodec") or "none") == "none"
            and ok_height(f) and f.get("url") and _is_direct_http(f)]
    auds = [f for f in (formats or [])
            if (f.get("vcodec") or "none") == "none"
            and (f.get("acodec") or "none") != "none"
            and f.get("url") and _is_direct_http(f)]
    # ONE language only: the original, or the dub the user picked — never a
    # dub that just happens to carry a higher bitrate.
    if audio_lang and any((a.get("language") or "") == audio_lang for a in auds):
        prog = []        # a progressive file carries the DEFAULT track only
    auds = _original_audio_only(auds, audio_lang)
    best_prog = max(prog, key=_video_rank) if prog else None

    def _audio_rank_for(video_fmt):
        def _rank(f):
            return (_audio_compat_rank(f, video_fmt),
                    1 if (f.get("ext") or "") in ("m4a", "webm", "opus") else 0,
                    f.get("abr") or 0,
                    f.get("tbr") or 0)
        return _rank

    best_vid = max(vids, key=_video_rank) if vids else None
    # The audio partner must FIT the chosen video's container: a VP9-webm
    # video with an AAC-m4a track (YouTube's default "best audio") cannot be
    # stream-copied into .webm at all — ffmpeg exits with "Only VP8 or VP9
    # or AV1 ..." and the whole 4K cut failed while 1080p (AVC-mp4 + AAC,
    # compatible) worked fine. So the audio is ranked FOR this video, and
    # the output container is derived from the PAIR (mixed pairs → .mkv,
    # which holds any codec with -c copy).
    best_aud = max(auds, key=_audio_rank_for(best_vid)) if (
        auds and best_vid) else None
    if not best_aud and auds:
        best_aud = max(auds, key=lambda f: (f.get("abr") or 0,
                                            f.get("tbr") or 0))

    px_prog = _fmt_short_side(best_prog) if best_prog else 0
    px_vid = _fmt_short_side(best_vid) if best_vid else 0
    # Progressive wins ties (one file, no mux); adaptive wins on resolution.
    if best_prog and (best_aud is None or px_prog >= px_vid):
        return (best_prog["url"], None, (best_prog.get("ext") or "mp4"),
                px_prog)
    if best_vid and best_aud:
        return (best_vid["url"], best_aud["url"],
                _container_for_pair(best_vid, best_aud), px_vid)
    if best_prog:
        return (best_prog["url"], None, (best_prog.get("ext") or "mp4"),
                px_prog)
    return None, None, "", 0


def _pick_stream_candidates(formats, cap_h, limit=6, audio_lang=""):
    """All viable (video, audio) pairs for ≤ cap_h, best first.

    cut_link() walks this list until one ffmpeg run succeeds: the first entry
    is identical to _pick_streams(), the rest are fallbacks (next-best video
    at the same cap, alternate audio partner, …) so a single incompatible /
    expired / throttled stream can no longer fail the whole cut — exactly
    what made "4K never downloads, 1080p always does" happen.
    Each entry is (video_url, audio_url_or_None, ext, picked_px).
    """
    cap = int(cap_h or 2160)
    if cap <= 0 or cap > 2160:
        cap = 2160

    def ok_height(f):
        px = _fmt_short_side(f)
        return px and px <= cap

    def _video_rank(f):
        return (
            _fmt_short_side(f),
            1 if (f.get("ext") or "") == "mp4" else 0,
            1 if (f.get("vcodec") or "").startswith("avc") else 0,
            f.get("tbr") or 0,
            f.get("format_id") or "")

    prog = sorted(
        [f for f in (formats or [])
         if (f.get("vcodec") or "none") != "none"
         and (f.get("acodec") or "none") != "none"
         and ok_height(f) and f.get("url") and _is_direct_http(f)],
        key=_video_rank, reverse=True)
    vids = sorted(
        [f for f in (formats or [])
         if (f.get("vcodec") or "none") != "none"
         and (f.get("acodec") or "none") == "none"
         and ok_height(f) and f.get("url") and _is_direct_http(f)],
        key=_video_rank, reverse=True)
    auds = [f for f in (formats or [])
            if (f.get("vcodec") or "none") == "none"
            and (f.get("acodec") or "none") != "none"
            and f.get("url") and _is_direct_http(f)]
    # One language only — fallbacks must not swap in another track. A picked
    # dub also rules out progressive files (they carry the default track).
    if audio_lang and any((a.get("language") or "") == audio_lang for a in auds):
        prog = []
    auds = _original_audio_only(auds, audio_lang)
    if not vids and not prog:
        return []

    cands = []
    seen = set()
    # Progressive options first (single file, no mux) — but ordered by
    # resolution among everything else below.
    prog_px = [(_fmt_short_side(f), f) for f in prog]
    # For each video (highest first), pair with audios ordered by
    # container-compatibility then quality, so the first pair for the top
    # video is the compatible one (VP9+Opus→webm, AVC+AAC→mp4) and mixed
    # pairs (VP9+AAC→mkv) follow as fallbacks rather than failures.
    for v in vids:
        ranked_auds = sorted(
            auds,
            key=lambda a, _v=v: (
                _audio_compat_rank(a, _v),
                a.get("abr") or 0, a.get("tbr") or 0),
            reverse=True)
        for a in ranked_auds[:3]:
            key = (v.get("format_id"), a.get("format_id"))
            if key in seen:
                continue
            seen.add(key)
            cands.append((
                _fmt_short_side(v) or 0,
                1 if _audio_compat_rank(a, v) >= 2 else 0,
                v, a))
    # Rank: resolution first (the picked quality is never traded away),
    # then container-compatibility, then mp4/avc convenience.
    cands.sort(key=lambda t: (
        t[0], t[1],
        1 if _ext_name(t[2]) == "mp4" else 0,
        1 if _vcodec_name(t[2]).startswith("avc") else 0,
        t[2].get("tbr") or 0), reverse=True)

    out = []
    # Merge progressive + adaptive by resolution: progressive wins ties
    # (one file, no mux), adaptive wins on resolution.
    prog_entries = [(px, f) for px, f in prog_px]
    adaptive_entries = [
        (px, v, a) for px, _compat, v, a in cands]
    # Build a single resolution-ordered list.
    merged = []
    for px, f in prog_entries:
        merged.append((px, True, f, None, True))
    for px, v, a in adaptive_entries:
        compat = _audio_compat_rank(a, v) >= 2
        merged.append((px, False, v, a, compat))
    # Sort: px desc; on equal px progressive first, else compatible first.
    def _mkey(e):
        if e[1]:
            return (e[0], 1, 1)
        return (e[0], 0, 1 if e[4] else 0)
    merged.sort(key=_mkey, reverse=True)

    for e in merged:
        if e[1]:
            f = e[2]
            out.append((f["url"], None, (f.get("ext") or "mp4"),
                        _fmt_short_side(f) or 0))
        else:
            _px, _is_prog, v, a = e[0], e[1], e[2], e[3]
            out.append((v["url"], a["url"],
                        _container_for_pair(v, a),
                        _fmt_short_side(v) or 0))
        if len(out) >= limit:
            break
    return out


def _ffmpeg_exe():
    _yt_dlp, ffmpeg_dir = ensure_yt_dlp_ready()
    name = "ffmpeg.exe" if sys.platform == "win32" else "ffmpeg"
    return os.path.join(ffmpeg_dir, name)


def _parse_ffmpeg_duration(text):
    """'Duration: 01:02:03.45' from `ffmpeg -i` stderr → seconds or 0."""
    m = re.search(r"Duration:\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)", text or "")
    if not m:
        return 0.0
    try:
        return (int(m.group(1)) * 3600 + int(m.group(2)) * 60
                + float(m.group(3)))
    except ValueError:
        return 0.0


def probe_file(path):
    """Duration of a local file via the bundled ffmpeg. Returns seconds."""
    return probe_file_with_error(path)[0]


def probe_file_with_error(path):
    """(duration_seconds, error) for a local file.

    `probe_file` swallows every failure into 0.0, which makes "ffmpeg isn't
    installed yet" indistinguishable from "this file is damaged" — and the
    cutter told the user the vague "Couldn't read that file" for both. This
    variant keeps the two apart so the page can say which one it is.
    """
    path = (path or "").strip()
    if not path:
        return 0.0, "empty"
    if not os.path.isfile(path):
        return 0.0, "missing"
    try:
        exe = _ffmpeg_exe()
    except Exception:                 # noqa: BLE001
        return 0.0, "no-ffmpeg"
    try:
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        proc = subprocess.run(
            [exe, "-hide_banner", "-i", path],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=30, creationflags=flags)
        dur = _parse_ffmpeg_duration(proc.stderr)
        return (dur, "") if dur > 0 else (0.0, "unreadable")
    except subprocess.TimeoutExpired:
        return 0.0, "timeout"
    except Exception:                 # noqa: BLE001
        return 0.0, "unreadable"


def extract_clip_thumb(src_path, out_path, at_sec=0.0, width=480):
    """Grab one frame of a finished clip as a JPEG (the Clips-card cover).

    Blocking — call on a worker thread. Seeks before -i (fast, keyframe
    accurate is plenty for a cover), scales to `width` wide keeping aspect,
    and writes atomically through a .part file so a half-written image is
    never shown. Returns True when `out_path` exists afterwards.
    """
    if not src_path or not os.path.isfile(src_path):
        return False
    try:
        exe = _ffmpeg_exe()
    except Exception:                 # noqa: BLE001
        return False
    try:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
    except OSError:
        return False
    tmp = out_path + ".part.jpg"
    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    # Try the requested moment first, then the very first frame (a seek past
    # the end of a very short clip yields no frame at all).
    for at in ([max(0.0, float(at_sec or 0)), 0.0] if at_sec else [0.0]):
        try:
            subprocess.run(
                [exe, "-hide_banner", "-loglevel", "error", "-y",
                 "-ss", f"{at:.2f}", "-i", src_path,
                 "-frames:v", "1", "-an",
                 "-vf", f"scale={int(width)}:-2", "-q:v", "4", tmp],
                capture_output=True, timeout=30, creationflags=flags)
            if os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
                os.replace(tmp, out_path)
                return True
        except Exception:             # noqa: BLE001 — a cover is cosmetic
            pass
    try:
        if os.path.isfile(tmp):
            os.remove(tmp)
    except OSError:
        pass
    return False


def fmt_clock(seconds):
    """123.0 → '2:03' / 3723.0 → '1:02:03'. Never localised (transport text)."""
    try:
        total = max(0, int(round(float(seconds or 0))))
    except (TypeError, ValueError):
        total = 0
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def parse_clock(text, duration=0.0):
    """'SS' / 'M:SS' / 'H:MM:SS' (or plain seconds) → float seconds, or None
    when unparsable. Clamped to [0, duration] when duration is known."""
    s = str(text or "").strip().replace(",", ".")
    if not s:
        return None
    try:
        if ":" in s:
            parts = s.split(":")
            if len(parts) > 3 or not all(
                    p.strip().replace(".", "", 1).isdigit() for p in parts):
                return None
            nums = [float(p.strip()) for p in parts]
            value = 0.0
            for n in nums:
                value = value * 60 + n
        else:
            value = float(s)
    except ValueError:
        return None
    if value < 0:
        return None
    try:
        dur = float(duration or 0)
    except (TypeError, ValueError):
        dur = 0.0
    if dur > 0:
        value = min(value, dur)
    return value


def sanitize_filename(name, limit=120):
    """Filesystem-safe stem (mirrors the scraper's own sanitising)."""
    stem = re.sub(r'[\\/*?:"<>|]', "_", str(name or "").strip())
    stem = re.sub(r"\s+", " ", stem).strip(" .")
    return (stem or "clip")[:limit]


def clip_tag(start, end):
    """Filename-safe segment tag: '0.05-0.12' (clock colons become dots —
    a literal H:MM:SS is not a legal Windows filename)."""
    return (f"{fmt_clock(start).replace(':', '.')}-"
            f"{fmt_clock(end).replace(':', '.')}")


def _unique_path(folder, filename):
    base, ext = os.path.splitext(filename)
    candidate = os.path.join(folder, filename)
    n = 2
    while os.path.exists(candidate):
        candidate = os.path.join(folder, f"{base} ({n}){ext}")
        n += 1
    return candidate


def _run_ffmpeg_cut(args, seg_len, out_path, on_progress, should_cancel):
    """Run one ffmpeg cut. `args` ends right before the output path; progress
    is time-based (out_time_ms vs the segment length) plus live bytes written.
    Returns (ok, message)."""
    cmd = args + [out_path]
    if on_progress:
        on_progress(0, 0)
    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", bufsize=1,
            creationflags=flags)
    except Exception as exc:          # noqa: BLE001
        return False, str(exc)
    err_tail = ""
    # Progress lines arrive per processed frame — hundreds per second on a
    # fast copy, each one a queued Qt signal + progress-bar relayout on the
    # GUI thread. Unthrottled that saturates the event loop and the whole
    # app reads as frozen on long cuts. Emit at most ~4/sec; the final 100
    # always goes out below.
    import time as _time
    last_emit, last_pct = 0.0, -1
    try:
        # -progress lines arrive on stdout; errors accumulate on stderr.
        import threading
        errs = []
        # Stall watchdog: a remote seek that emits NOTHING for a long while
        # (the HLS hang: zero output forever) must not burn the whole 600 s
        # budget per attempt — kill it so the next candidate / fallback gets
        # its turn. Any stdout line resets the clock; healthy copies emit
        # continuously. Also owns the kill when the user cancels during a
        # silent phase (the readline loop below would otherwise block until
        # the process ends on its own).
        stalled = {"flag": False}
        last_io = {"t": _time.monotonic()}
        # v1.0.1: the watchdog naps on an Event instead of time.sleep(2), so
        # it wakes the moment ffmpeg is done. With the plain sleep the final
        # w.join() below added up to 2 s of dead time to EVERY cut.
        done_evt = threading.Event()

        def _drain():
            try:
                errs.append(proc.stderr.read() or "")
            except Exception:         # noqa: BLE001
                pass
        t = threading.Thread(target=_drain, daemon=True)
        t.start()

        def _watchdog():
            while True:
                try:
                    alive = proc.poll() is None
                except Exception:     # noqa: BLE001
                    break
                if not alive:
                    break
                if should_cancel is not None and should_cancel():
                    stalled["flag"] = "cancel"
                    try:
                        proc.terminate()
                    except Exception:  # noqa: BLE001
                        pass
                    break
                if _time.monotonic() - last_io["t"] > 150:
                    stalled["flag"] = True
                    try:
                        proc.terminate()
                    except Exception:  # noqa: BLE001
                        pass
                    try:
                        proc.wait(timeout=10)
                    except Exception:  # noqa: BLE001
                        try:
                            proc.kill()
                        except Exception:  # noqa: BLE001
                            pass
                    break
                if done_evt.wait(1.0):
                    break

        w = threading.Thread(target=_watchdog, daemon=True)
        w.start()
        try:
            for line in (proc.stdout or []):
                last_io["t"] = _time.monotonic()
                if should_cancel is not None and should_cancel():
                    try:
                        proc.terminate()
                    except Exception:  # noqa: BLE001
                        pass
                    try:
                        proc.wait(timeout=8)
                    except Exception:  # noqa: BLE001
                        try:
                            proc.kill()
                        except Exception:  # noqa: BLE001
                            pass
                    try:
                        if os.path.exists(out_path):
                            os.remove(out_path)
                    except OSError:
                        pass
                    return False, DOWNLOAD_CANCELLED
                line = line.strip()
                if line.startswith("out_time_ms="):
                    try:
                        done_s = int(line.split("=", 1)[1]) / 1_000_000
                    except ValueError:
                        continue
                    pct = 0
                    if seg_len > 0:
                        pct = max(0, min(99, int(done_s * 100 / seg_len)))
                    now = _time.monotonic()
                    # Monotonic + throttled: never step back, never flood.
                    if pct <= last_pct or (now - last_emit < 0.25 and pct < 99):
                        continue
                    last_pct, last_emit = pct, now
                    written = 0
                    try:
                        written = os.path.getsize(out_path)
                    except OSError:
                        pass
                    if on_progress:
                        on_progress(pct, written)
        finally:
            try:
                if proc.stdout:
                    proc.stdout.close()
            except Exception:         # noqa: BLE001
                pass
        proc.wait(timeout=600)
        done_evt.set()
        t.join(timeout=5)
        w.join(timeout=5)
        err_tail = (errs[0] if errs else "")[-1500:]
    except Exception as exc:          # noqa: BLE001
        try:
            proc.kill()
        except Exception:             # noqa: BLE001
            pass
        return False, str(exc)
    if should_cancel is not None and should_cancel():
        try:
            if os.path.exists(out_path):
                os.remove(out_path)
        except OSError:
            pass
        return False, DOWNLOAD_CANCELLED
    if proc.returncode != 0:
        try:
            if os.path.exists(out_path):
                os.remove(out_path)
        except OSError:
            pass
        if stalled["flag"] is True:
            return False, tr("The stream stalled (no data for a while). "
                             "Check your connection and try again.")
        # The very last stderr line is often empty or a bare progress remnant;
        # keep the last few MEANINGFUL lines so the real cause (403, codec in
        # container, timeout) survives instead of a cryptic one-liner.
        lines = [ln.strip() for ln in (err_tail or "").strip().splitlines()
                 if ln.strip()]
        tail = " | ".join(lines[-3:]).strip()
        msg = clean_error(tail)
        if not msg or msg == tr("Unknown error."):
            msg = f"ffmpeg exited with code {proc.returncode}"
        return False, msg
    try:
        size = os.path.getsize(out_path)
    except OSError:
        return False, tr("The cut file was not written.")
    if size <= 0:
        try:
            os.remove(out_path)
        except OSError:
            pass
        return False, tr("The cut came out empty.")
    if on_progress:
        on_progress(100, size)
    return True, ""


# ── v1.0.1: the H.264 encoder for frame-accurate cuts ───────────────────
# The primary cut re-encodes (see _cut_args). libx264 on the CPU is the slow
# part of a long 1440p/4K clip, while almost every Windows PC has a hardware
# H.264 encoder sitting idle (NVIDIA NVENC, Intel Quick Sync, AMD AMF) that
# does the same job several times faster at no CPU cost. Which one works is
# decided ONCE per process by a 3-frame test encode (an encoder can be compiled
# into ffmpeg yet have no GPU/driver behind it), and libx264 stays as the
# guaranteed fallback — both here and at cut time if a hardware run fails.
# Turn it off with `"cut_hw_encode": false` in config.json.
#
# v1.0.2 — HOW BIG THE CLIP IS. Every re-encoded cut used CRF 18 (near-lossless),
# which spends bits preserving the compression noise already baked into a
# YouTube stream: a 1080p clip came out at ~12 Mbit/s against the source's 2-5
# (a 2.5-minute cut = 223 MB). The level is now a setting, `"cut_quality"` in
# config.json:
#     "high"      the old behaviour (editing / archiving; biggest files)
#     "balanced"  DEFAULT — visually the same for sharing and most edits,
#                 roughly half the size of "high"
#     "small"     smallest, a little softer on fine detail and fast motion
# One number per encoder family: x264 CRF, NVENC CQ, QSV global_quality,
# AMF QP (I, P). Lower = better quality = bigger file.
_QUALITY_LEVELS = {
    "high":     {"crf": 18, "cq": 19, "qsv": 20, "amf": (18, 20)},
    "balanced": {"crf": 23, "cq": 25, "qsv": 25, "amf": (23, 25)},
    "small":    {"crf": 27, "cq": 29, "qsv": 29, "amf": (27, 29)},
}
_DEFAULT_QUALITY = "balanced"
_HW_NAMES = ("h264_nvenc", "h264_qsv", "h264_amf")

# v1.0.3 — A SIZE YOU CAN KNOW BEFORE THE CUT. The CRF levels above are
# constant-QUALITY: the encoder spends whatever the picture needs, so the file
# size is only known once the cut is done. The extension's Cut panel showed the
# download's size scaled to the clip length and a "≈ 44 MB" 1080p cut came out
# at 166 MB on High. Now a re-encoded cut is BITRATE-targeted (ABR with a peak
# cap, the same approach download.py's H.264 conversion already uses), and the
# panel's estimate is computed from the very same numbers — so the size shown
# is the size you get, within a few percent.
#
# target video kbps = source kbps × codec factor × level factor
#   codec factor: how many more bits H.264 needs than the source codec for the
#                 same picture (same table as download.py's conversion; H.264
#                 sources are 1.0).
#   level factor: High keeps generous headroom over the source (re-encoding
#                 costs a generation), Balanced a little, Small trims.
# The CRF table stays as the fallback when the source bitrate is unknown.
_CUT_LEVEL_RATE = {"high": 1.6, "balanced": 1.1, "small": 0.75}
_CUT_SRC_FACTOR = {"h264": 1.0, "vp9": 1.35, "av1": 1.6, "hevc": 1.3}
_CUT_MIN_KBPS = 300
_CUT_AUDIO_KBPS = 192            # every re-encoded cut: AAC 192 kbps
_CUT_MUX_OVERHEAD = 1.006        # MP4 index + faststart moov, measured < 1 %


def cut_video_kbps(src_kbps, vcodec, level=None):
    """Video bitrate a re-encoded cut is encoded at, or 0 when the source
    bitrate is unknown (the CRF fallback is used then). Shared by the encoder
    and by the size estimate so the two can never disagree."""
    try:
        src = float(src_kbps or 0)
    except (TypeError, ValueError):
        src = 0.0
    if src <= 0:
        return 0
    level = level if level in _CUT_LEVEL_RATE else _cut_quality()
    fam = _vcodec_family(vcodec)
    k = src * _CUT_SRC_FACTOR.get(fam, 1.35) * _CUT_LEVEL_RATE[level]
    return max(_CUT_MIN_KBPS, int(round(k)))


def _format_for_url(formats, url):
    if not url:
        return None
    return next((f for f in (formats or []) if f.get("url") == url), None)


def _fallback_video_format(formats, cap_h):
    """The stream yt-dlp's own fallback would most likely fetch for ≤ cap_h
    (bestvideo[height<=cap], resolution first) — used only when there is no
    direct-HTTP pick to read the bitrate from."""
    cap = int(cap_h or 2160)
    if cap <= 0 or cap > 2160:
        cap = 2160
    vids = [f for f in (formats or [])
            if (f.get("vcodec") or "none") != "none"
            and 0 < (_fmt_short_side(f) or 0) <= cap]
    if not vids:
        return None
    return max(vids, key=lambda f: (_fmt_short_side(f),
                                    1 if _vcodec_family(f.get("vcodec")) == "vp9" else 0,
                                    f.get("tbr") or 0))


def _video_target_for(formats, cap_h, duration, audio_lang="", v_url=None,
                      level=None):
    """(target_kbps, source_video_format) for a re-encoded cut at ≤ cap_h."""
    f = _format_for_url(formats, v_url)
    if f is None:
        direct = [x for x in (formats or []) if _is_direct_http(x)]
        v0 = _pick_streams(direct, cap_h, audio_lang)[0] if direct else None
        f = _format_for_url(direct, v0) or _fallback_video_format(formats, cap_h)
    if f is None:
        return 0, None
    return cut_video_kbps(_stream_kbps(f, duration), f.get("vcodec"), level), f


def cut_size_rates(formats, duration, audio_lang="", level=None):
    """Bytes per second of clip, for every output the Cut panel offers — what
    the panel multiplies by the clip length. {cap_key: {"mp4": Bps,
    "copy": Bps}, "audio": {"mp3": Bps, ...}}. 0 = unknown."""
    out = {}
    try:
        duration = float(duration or 0)
    except (TypeError, ValueError):
        duration = 0.0
    direct = [f for f in (formats or []) if _is_direct_http(f)]
    for cap in _CUT_CAPS:
        try:
            v_url, a_url, _ext, px = (_pick_streams(direct, cap, audio_lang)
                                      if direct else (None, None, "", 0))
            target, vf = _video_target_for(formats, cap, duration, audio_lang,
                                           v_url=v_url, level=level)
            mp4 = ((target + _CUT_AUDIO_KBPS) * 1000 / 8 * _CUT_MUX_OVERHEAD
                   if target else 0)
            copy = 0
            if vf is not None and v_url:
                af = _format_for_url(direct, a_url)
                kb = _stream_kbps(vf, duration) + (
                    _stream_kbps(af, duration) if af is not None else 0)
                copy = kb * 1000 / 8 * _CUT_MUX_OVERHEAD if kb > 0 else 0
            out[f"{cap}p"] = {"mp4": int(mp4), "copy": int(copy)}
        except Exception:             # noqa: BLE001 — one tier ≠ no estimate
            out[f"{cap}p"] = {"mp4": 0, "copy": 0}
    # audio-only cuts: fixed-rate encoders, except WAV (arithmetic) and FLAC
    auds = [f for f in direct if (f.get("vcodec") or "none") == "none"
            and (f.get("acodec") or "none") != "none" and f.get("url")]
    auds = _original_audio_only(auds, audio_lang)
    ac = max(auds, key=lambda f: (f.get("abr") or 0, f.get("tbr") or 0), default=None)
    asr = int((ac or {}).get("asr") or 48000)
    ch = int((ac or {}).get("audio_channels") or 2)
    pcm = asr * ch * 2
    out["audio"] = {"mp3": 192000 // 8, "m4a": 192000 // 8, "opus": 128000 // 8,
                    "wav": pcm, "flac": int(pcm * 0.6)}
    return out


def _cut_quality():
    try:
        from app.config import load_app_config
        q = str(load_app_config().get("cut_quality", _DEFAULT_QUALITY)).lower()
    except Exception:                 # noqa: BLE001
        q = _DEFAULT_QUALITY
    return q if q in _QUALITY_LEVELS else _DEFAULT_QUALITY


def _encoder_args(name, level=None, kbps=0):
    """ffmpeg video-encoder arguments for `name`: bitrate-targeted at `kbps`
    when given (predictable size, see cut_video_kbps), else the CRF/CQ value
    of the quality level."""
    if kbps and kbps > 0:
        k = int(kbps)
        rate = ["-b:v", f"{k}k", "-maxrate", f"{int(k * 1.5)}k",
                "-bufsize", f"{k * 2}k"]
        if name == "h264_nvenc":
            return ["-c:v", "h264_nvenc", "-preset", "p4", "-tune", "hq",
                    "-rc", "vbr", *rate, "-pix_fmt", "yuv420p"]
        if name == "h264_qsv":
            return ["-c:v", "h264_qsv", "-preset", "faster", *rate,
                    "-pix_fmt", "nv12"]
        if name == "h264_amf":
            return ["-c:v", "h264_amf", "-quality", "balanced",
                    "-rc", "vbr_peak", *rate, "-pix_fmt", "nv12"]
        return ["-c:v", "libx264", "-preset", "veryfast", *rate,
                "-pix_fmt", "yuv420p"]
    q = _QUALITY_LEVELS[level if level in _QUALITY_LEVELS else _cut_quality()]
    if name == "h264_nvenc":
        return ["-c:v", "h264_nvenc", "-preset", "p4", "-tune", "hq",
                "-rc", "vbr", "-cq", str(q["cq"]), "-b:v", "0",
                "-pix_fmt", "yuv420p"]
    if name == "h264_qsv":
        return ["-c:v", "h264_qsv", "-preset", "faster",
                "-global_quality", str(q["qsv"]), "-pix_fmt", "nv12"]
    if name == "h264_amf":
        return ["-c:v", "h264_amf", "-quality", "balanced", "-rc", "cqp",
                "-qp_i", str(q["amf"][0]), "-qp_p", str(q["amf"][1]),
                "-pix_fmt", "nv12"]
    return ["-c:v", "libx264", "-preset", "veryfast",
            "-crf", str(q["crf"]), "-pix_fmt", "yuv420p"]


_ENCODER_CACHE = {}               # ffmpeg path -> [working hardware encoder names]
_ENCODER_LOCK = threading.Lock()


def _hw_encode_enabled():
    try:
        from app.config import load_app_config
        return bool(load_app_config().get("cut_hw_encode", True))
    except Exception:                 # noqa: BLE001
        return True


def _encoder_works(ffmpeg, args):
    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    try:
        proc = subprocess.run(
            [ffmpeg, "-hide_banner", "-v", "error", "-f", "lavfi",
             "-i", "color=c=black:s=640x360:r=30:d=0.2", "-frames:v", "3",
             *args, "-f", "null", "-"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=10, creationflags=flags)
        return proc.returncode == 0
    except Exception:                 # noqa: BLE001
        return False


def video_encoders(ffmpeg, kbps=0):
    """[(name, args)] to try for a re-encoded cut, fastest first; libx264 is
    always last. Probed once per ffmpeg binary and cached. `kbps` > 0 makes
    every entry bitrate-targeted (see cut_video_kbps)."""
    use_hw = _hw_encode_enabled()
    with _ENCODER_LOCK:
        hw = _ENCODER_CACHE.get(ffmpeg)
        if hw is None:
            hw = []
            listed = ""
            flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            try:
                listed = subprocess.run(
                    [ffmpeg, "-hide_banner", "-encoders"],
                    capture_output=True, text=True, encoding="utf-8",
                    errors="replace", timeout=10, creationflags=flags).stdout or ""
            except Exception:         # noqa: BLE001
                listed = ""
            for name in _HW_NAMES:
                if name in listed and _encoder_works(ffmpeg, _encoder_args(name, "balanced")):
                    hw = [name]
                    break
            _ENCODER_CACHE[ffmpeg] = hw
    level = _cut_quality()
    return ([(n, _encoder_args(n, level, kbps)) for n in hw] if use_hw else []) + [
        ("libx264", _encoder_args("libx264", level, kbps))]


def _cut_args(ffmpeg, v_url, a_url, start, seg_len, ext,
               audio_reencode=False, video_reencode=False, audio_only=False,
               vcodec_args=None):
    """Shared ffmpeg argument builder.

    Three output strategies, in the order `cut_link` tries them:

    `video_reencode` — BOTH streams are decoded from the same cut point and
    re-timestamped together. That is the only way to get a cut that is frame-
    accurate AND has audio locked to the picture, because a stream-copied video
    can only ever start on a keyframe: the cut point is rarely on one, so the
    surviving first packet is mid-GOP, players either skip it or render garbage
    until the next keyframe, and the audio (which has no keyframes at all) runs
    ahead — the "the cut plays out of sync" report. H.264/AAC in MP4 is also the
    one combination Premiere, Resolve and every other editor opens without
    complaint, so a cut drops straight into a timeline.

    `audio_reencode` — video bit-for-bit, audio to AAC. Exists purely as a MUX
    fallback for codec pairs that do not fit one container; it inherits the same
    keyframe limitation, so it is not used for the primary cut.

    neither — `-c copy`, the fastest path and the one that preserves the source
    bitstream exactly. Kept as the fallback when no encoder is available.

    Seeking is hybrid for all three: a pure input seek (`-ss` before `-i`) is
    fast but `-t` then mis-caps the length on some files; a pure output seek
    reads everything up to `start`, which is hopeless 90 minutes into a remote
    file. So the start is split: an input seek to 10 s before it (fast HTTP
    range seek, no sequential download) plus an output `-ss` for the remainder
    and `-t` for the exact duration.

    Every remote input carries a browser User-Agent plus reconnect/retry
    flags: YouTube's CDN answers ffmpeg's default `Lavf/...` agent with 403
    far more often on high-resolution (4K) streams — the "1080p cuts, 4K
    never does" split — and a single dropped HTTP range request without
    `-reconnect 1` aborts the whole cut.
    """
    if video_reencode or audio_only:
        # v1.0.1: a TRANSCODE is already frame-accurate with a pure input
        # seek (ffmpeg's accurate_seek decodes from the keyframe and drops
        # what precedes `start`). The 10 s pre-roll below only made both
        # remote streams download and decode ten extra seconds per cut —
        # ~20-40 MB on a 4K clip — for an identical first frame (measured:
        # same frame, same 12.000 s duration, A/V start 0.000 on both).
        pre, off = max(0.0, float(start)), 0.0
    else:
        pre = max(0.0, float(start) - 10.0)
        off = max(0.0, float(start) - pre)

    def _input(url):
        # Input options must precede their `-i`. `-rw_timeout` is in
        # microseconds (15 s); reconnect flags turn one dead CDN connection
        # into a resume instead of a failed cut.
        if not str(url).lower().startswith(("http://", "https://")):
            # a local file (the fetch-then-cut fallback): ffmpeg rejects the
            # HTTP-only options outright ("Option user_agent not found")
            return ["-ss", f"{pre:.3f}", "-i", url]
        return ["-user_agent", _UA,
                "-headers", "Referer: https://www.youtube.com/\r\n",
                "-reconnect", "1", "-reconnect_streamed", "1",
                "-reconnect_delay_max", "5",
                "-rw_timeout", "15000000",
                "-ss", f"{pre:.3f}", "-i", url]

    args = [ffmpeg, "-hide_banner", "-y"]
    args += _input(v_url)
    if a_url:
        args += _input(a_url)
        args += ["-map", "0:v:0", "-map", "1:a:0"]
    elif audio_only:
        args += ["-map", "0:a:0", "-vn"]
    if off > 0:
        args += ["-ss", f"{off:.3f}"]
    args += ["-t", f"{seg_len:.3f}"]
    if audio_only:
        codecs = {"mp3": ["-c:a", "libmp3lame", "-b:a", "192k"],
                  "m4a": ["-c:a", "aac", "-b:a", "192k"],
                  "opus": ["-c:a", "libopus", "-b:a", "128k"],
                  "wav": ["-c:a", "pcm_s16le"],
                  "flac": ["-c:a", "flac"]}
        args += codecs.get((ext or "mp3").lower(), codecs["mp3"])
    elif video_reencode:
        # Encoder args come from video_encoders(): bitrate-targeted when the
        # source bitrate is known, the CRF level otherwise. `-pix_fmt yuv420p` matters
        # because YouTube can serve 10-bit or odd-chroma sources that editors
        # refuse. `veryfast` keeps a long 4K cut from feeling like a render
        # job while still compressing far better than the source bitrate.
        args += list(vcodec_args or _encoder_args("libx264"))
        args += ["-c:a", "aac", "-b:a", "192k"]
    elif audio_reencode:
        # Last-resort mux: keep the video bit-for-bit, re-encode ONLY the
        # audio to AAC so ANY pair fits into .mp4 (VP9-webm video + Opus
        # audio, AV1 + Opus, ...). Slightly slower than -c copy but always
        # produces a universally playable file at the picked resolution.
        args += ["-c:v", "copy", "-c:a", "aac", "-b:a", "192k"]
    elif not audio_only:
        args += ["-c", "copy"]

    # `-avoid_negative_ts make_zero` belongs to the COPY paths only. Measured:
    # with a full re-encode it SHIFTS THE TWO STREAMS BY DIFFERENT AMOUNTS
    # (video +66 ms, audio +43 ms on a 30 fps clip) because it re-bases each
    # stream's first timestamp independently — a 23 ms A/V offset the control
    # run without it does not have. A re-encode starts both streams at zero on
    # its own; the audio's -23 ms "Skip Samples" priming there is the standard
    # AAC edit list every player honours, not a problem to fix.
    if video_reencode:
        pass
    else:
        args += ["-avoid_negative_ts", "make_zero"]

    args += ["-progress", "pipe:1", "-nostats", "-v", "error"]
    if (ext or "").lower() == "mp4":
        args += ["-movflags", "+faststart"]
    return args


def _looks_like_expired_url(err_text):
    """True when ffmpeg failed fetching the remote stream itself (HTTP 403 /
    404 / 401 / timeout) rather than muxing it — worth ONE fresh
    re-extraction, since direct stream URLs expire within hours."""
    t = (err_text or "").lower()
    needles = ("403", "forbidden", "401", "unauthorized", "404", "not found",
               "expired", "timed out", "timeout", "connection reset",
               "connection refused", "http error", "server returned",
               "unable to open", "invalid data found when processing input")
    return any(n in t for n in needles)


def _merge_format_pools(*pools):
    """Merge format lists from several ladder rungs (exact-URL dedup).

    The same itag from two clients carries two DIFFERENT expiring CDN URLs,
    so dedup is by URL, not format_id — retrying the other URL is a genuine
    second chance, not a repeat. Using the merged pool (instead of only the
    richest rung) means a cut-time read that came back throttled still has
    the high-tier streams the probe read minutes earlier.
    """
    out, seen = [], set()
    for pool in pools:
        for f in pool or []:
            u = f.get("url") or ""
            if not u or u in seen:
                continue
            seen.add(u)
            out.append(f)
    return out


def _ffprobe_exe():
    _yt_dlp, ffmpeg_dir = ensure_yt_dlp_ready()
    name = "ffprobe.exe" if sys.platform == "win32" else "ffprobe"
    p = os.path.join(ffmpeg_dir, name)
    return p if os.path.isfile(p) else ""


def _media_short_side(path):
    """Short side of a local file's first video stream via ffprobe, else 0."""
    try:
        exe = _ffprobe_exe()
    except Exception:                 # noqa: BLE001
        return 0
    if not exe or not path or not os.path.isfile(path):
        return 0
    try:
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        proc = subprocess.run(
            [exe, "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height", "-of", "csv=p=0",
             path],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=30, creationflags=flags)
        raw = (proc.stdout or "").strip().replace("x", ",")
        nums = []
        for part in raw.split(","):
            part = part.strip()
            if part.isdigit():
                nums.append(int(part))
        if len(nums) >= 2 and nums[0] > 0 and nums[1] > 0:
            return min(nums[0], nums[1])
        if len(nums) == 1 and nums[0] > 0:
            return nums[0]
    except Exception:                 # noqa: BLE001
        pass
    return 0


def log_section_failure(exc):
    try:
        from app.crash import log_crash
        log_crash("cutter: section download unavailable, fetching the whole "
                  "file: " + str(exc)[:300])
    except Exception:                 # noqa: BLE001
        pass


def _cut_via_ydl_download(url, height_cap, start, end, seg_len, target_dir,
                          title, vid, tag, want_px, on_status=None,
                          on_progress=None, proxy_url="",
                          cookies_browser="", should_cancel=None,
                          audio_lang="", video_kbps=0):
    """Fetch-then-cut fallback for tiers the fast HTTP-seek path can't do.

    yt-dlp itself downloads the requested tier — with its own per-client
    headers, challenge/PO-token handling, fragment retries and fallbacks
    (everything a raw `ffmpeg -i <url>` lacks, and the reason 4K/1440p
    remote seeks fail while smaller tiers pass). v1.0.1: only the requested
    section is fetched (and re-encoded on the way) when the engine can; the
    whole-file download + local frame-accurate cut is kept as the safety net.
    Succeeds wherever the Downloads page succeeds. Blocking — call on a
    worker thread.
    Returns (ok, message_or_CANCELLED, filepath, measured_px).
    """
    def _status(text):
        if on_status:
            on_status(text)

    cap = int(height_cap or 2160)
    if cap <= 0 or cap > 2160:
        cap = 2160
    floor = int(cap * 0.9) if want_px else 0
    try:
        yt_dlp, ffmpeg_dir = ensure_yt_dlp_ready()
    except Exception as exc:          # noqa: BLE001
        return False, str(exc), "", 0

    base = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "ffmpeg_location": ffmpeg_dir,
        "merge_output_format": "mp4",
        # Tie-break only — resolution first, so the picked tier is never
        # traded away for a codec preference (mirrors download_video).
        # "lang" first: on a dubbed video it picks the ORIGINAL audio track
        # (video streams carry no language, so resolution still decides them).
        "format_sort": ["lang", "res", "vcodec:vp9", "vcodec:avc"],
        "retries": 10,
        "fragment_retries": 10,
        "extractor_retries": 3,
        "concurrent_fragment_downloads": 4,
        "http_headers": {"User-Agent": _UA},
        "logger": _QuietLogger(),
    }
    base.update(js_runtime_opts())   # solve YouTube's JS challenge
    if proxy_url:
        base["proxy"] = proxy_url
    fmt_expr = (f"bestvideo[height<={cap}]+bestaudio/"
                f"bestvideo[width<={cap}]+bestaudio/"
                f"best[height<={cap}]/best[width<={cap}]/best")
    # A picked dub: every bestaudio gets [language=...], original as fallback.
    fmt_expr = lang_format_expr(fmt_expr, audio_lang)
    plan = []
    if cookies_browser:
        plan.append({"cookies": cookies_browser, "clients": None})
    for clients in client_ladder():
        plan.append({"cookies": None, "clients": clients})
    # Set once a bot check / 403 is seen, so the cookie rungs below are appended
    # exactly once (the loop iterates `plan` while these are appended to it).
    cookies_added = bool(cookies_browser)

    import time as _time
    dl_state = {"pct": -1, "at": 0.0}

    def _hook(d):
        if should_cancel is not None and should_cancel():
            from yt_dlp.utils import DownloadCancelled
            raise DownloadCancelled("stopped by user")
        if d.get("status") == "downloading":
            try:
                done = int(d.get("downloaded_bytes") or 0)
            except (TypeError, ValueError):
                done = 0
            try:
                total = int(d.get("total_bytes")
                            or d.get("total_bytes_estimate") or 0)
            except (TypeError, ValueError):
                total = 0
            pct = int(done * 78 / total) if total else 0
            pct = max(0, min(78, pct))
            now = _time.monotonic()
            if pct > dl_state["pct"] and (now - dl_state["at"] >= 0.4
                                          or pct >= 78):
                dl_state["pct"], dl_state["at"] = pct, now
                if on_progress:
                    on_progress(pct, done)

    try:
        ffmpeg = _ffmpeg_exe()
    except Exception as exc:          # noqa: BLE001
        return False, str(exc), "", 0
    # the bitrate cut_link worked out for this tier, so the size matches the
    # panel's estimate on this path too
    encoders = video_encoders(ffmpeg, video_kbps)

    def _stem(got):
        got_label = f"{got}p" if got else (f"{cap}p" if want_px else tr("best"))
        return (f"{sanitize_filename(title)} [clip {tag}] [{vid}] {got_label}"
                + (f" [{audio_lang}]" if audio_lang else ""))

    def _local_cut(src, got):
        """Frame-accurate re-encode out of the finished file (same reasoning
        as cut_link's primary path), stream copy only as the last resort."""
        out_path = _unique_path(target_dir, f"{_stem(got)}.mp4")
        _status(tr("Cutting {a} → {b} …").format(
            a=fmt_clock(start), b=fmt_clock(end)))

        def _prog2(p, w):
            if on_progress:
                try:
                    p, w = int(p), int(w)
                except (TypeError, ValueError):
                    p, w = 0, 0
                on_progress(78 + min(22, max(0, p * 22 // 100)), w)

        msg = ""
        for _name, enc_args in encoders:
            ok, msg = _run_ffmpeg_cut(
                _cut_args(ffmpeg, src, None, start, seg_len, "mp4",
                          video_reencode=True, vcodec_args=enc_args)
                + ["-map", "0:v:0", "-map", "0:a:0?"],
                seg_len, out_path, _prog2, should_cancel)
            if ok or msg == DOWNLOAD_CANCELLED:
                return ok, msg, out_path
        ok, msg = _run_ffmpeg_cut(
            _cut_args(ffmpeg, src, None, start, seg_len, "mp4", audio_reencode=True)
            + ["-map", "0:v:0", "-map", "0:a:0?"],
            seg_len, out_path, _prog2, should_cancel)
        return ok, msg, out_path

    # v1.0.1 — SECTION FIRST. The fallback used to download the WHOLE video
    # (a 2-hour 4K file for a 20-second clip) and then cut it. yt-dlp can hand
    # only [start, end) to ffmpeg itself (download_ranges) with its own
    # headers / PO-token-bound URLs — exactly what the raw remote seek lacked —
    # and re-encode it frame-accurately on the way (force_keyframes_at_cuts +
    # our encoder args). The full download stays as the safety net for
    # streams ffmpeg can't range-read (SABR/HLS-only answers).
    section_ok = True
    try:
        from yt_dlp.utils import download_range_func
    except Exception:                 # noqa: BLE001 — older engine
        section_ok = False

    last_err = ""
    with tempfile.TemporaryDirectory(prefix="niche_cut_") as tmp:
        for attempt in plan:
            if should_cancel is not None and should_cancel():
                return False, DOWNLOAD_CANCELLED, "", 0
            opts = dict(base)
            opts["format"] = fmt_expr
            opts["outtmpl"] = os.path.join(tmp, "%(id)s.%(ext)s")
            opts["progress_hooks"] = [_hook]
            yt_args = {}
            if attempt.get("clients"):
                yt_args["player_client"] = attempt["clients"]
            if yt_args:
                opts["extractor_args"] = {"youtube": yt_args}
            if attempt.get("cookies"):
                opts["cookiesfrombrowser"] = (attempt["cookies"],)
            modes = ["section", "full"] if section_ok else ["full"]
            try:
                for mode in modes:
                    run = dict(opts)
                    if mode == "section":
                        run["download_ranges"] = download_range_func(
                            None, [(float(start), float(end))])
                        run["force_keyframes_at_cuts"] = True
                        run["external_downloader_args"] = {"ffmpeg_o": [
                            *encoders[0][1], "-c:a", "aac", "-b:a", "192k",
                            "-movflags", "+faststart"]}
                        _status(tr("Fetching only {a} → {b} at {q}…").format(
                            a=fmt_clock(start), b=fmt_clock(end), q=f"{cap}p"))
                    else:
                        _status(tr("Downloading the {q} file, then cutting…")
                                .format(q=f"{cap}p"))
                    try:
                        with yt_dlp.YoutubeDL(run) as ydl:
                            inf = ydl.extract_info(url, download=True)
                            reqs = inf.get("requested_downloads") or []
                            src = ((reqs[0].get("filepath") if reqs else None)
                                   or ydl.prepare_filename(inf))
                    except Exception as exc:  # noqa: BLE001
                        if (mode == "section" and not _is_bot_or_403(str(exc))
                                and not (should_cancel and should_cancel())):
                            # the section path itself didn't work here: stop
                            # trying it, fetch the whole file this time
                            section_ok = False
                            log_section_failure(exc)
                            continue
                        raise
                    try:
                        empty = (not src or not os.path.isfile(src)
                                 or os.path.getsize(src) <= 0)
                    except OSError:
                        empty = True
                    got = 0 if empty else _media_short_side(src)
                    if empty or (floor and got and got < floor):
                        last_err = (tr("The download came out empty.") if empty
                                    else f"got {got}p, asked for {cap}")
                        try:
                            if src and os.path.isfile(src):
                                os.remove(src)
                        except OSError:
                            pass
                        if mode == "section" and empty:
                            section_ok = False
                            continue
                        break
                    if mode == "section":
                        # already the finished, frame-accurate clip
                        out_path = _unique_path(target_dir, f"{_stem(got)}.mp4")
                        try:
                            os.replace(src, out_path)
                        except OSError:
                            import shutil
                            shutil.move(src, out_path)
                        if on_progress:
                            try:
                                on_progress(100, os.path.getsize(out_path))
                            except OSError:
                                pass
                        return True, out_path, out_path, int(got or 0)
                    ok, msg, out_path = _local_cut(src, got)
                    if ok:
                        return True, out_path, out_path, int(got or 0)
                    if msg == DOWNLOAD_CANCELLED:
                        return False, msg, "", 0
                    last_err = msg or last_err
                    break
            except Exception as exc:          # noqa: BLE001
                if should_cancel is not None and should_cancel():
                    return False, DOWNLOAD_CANCELLED, "", 0
                try:
                    last_err = (explain_network_error(exc, "YouTube")
                                or str(exc))
                except Exception:             # noqa: BLE001
                    last_err = str(exc)
                # Bot check / CDN 403: browser cookies are the only thing that
                # gets past them, so the cookie rungs are appended once, on
                # demand, followed by a no-cookie rung so a locked or
                # undecryptable cookie DB can't end the cut.
                if not cookies_added and _is_bot_or_403(last_err):
                    cookies_added = True
                    for b in _COOKIE_BROWSERS:
                        if b != cookies_browser:
                            plan.append({"cookies": b, "clients": None})
                    for clients in ([],) + tuple(BYPASS_CLIENTS):
                        plan.append({"cookies": None, "clients": clients})
                    _status(tr("Trying browser cookies…"))
                continue
    return (False,
            _friendly_or_clean(last_err) or tr("No playable stream at that quality."),
            "", 0)


def cut_link(url, height_cap, start, end, target_dir, on_status=None,
             on_progress=None, proxy_url="", cookies_browser="",
             should_cancel=None, on_resolved=None, audio_lang="",
             output_format="mp4", audio_only=False):
    """Cut [start, end) out of a YouTube link at ≤ height_cap (0 = best
    available, up to 4K) into `target_dir`. Blocking — call on a worker thread.
    `on_progress(pct, written_bytes)`; `on_resolved(height_px, label)` reports
    the quality actually cut. Returns (ok, message_or_CANCELLED, filepath)."""
    # v3.41.5: YouTube cuts need the full download engine (JS runtime + PO
    # Token helper), same as a normal download.
    from app.core.runtime_deps import download_engine_missing
    _missing = download_engine_missing()
    if _missing:
        return False, _missing, ""
    def _status(text):
        if on_status:
            on_status(text)

    url = (url or "").strip()
    try:
        start, end = float(start), float(end)
    except (TypeError, ValueError):
        return False, tr("Bad segment times."), ""
    if not (end > start >= 0):
        return False, tr("The end must be after the start."), ""
    try:
        os.makedirs(target_dir, exist_ok=True)
    except OSError as exc:
        return False, str(exc), ""

    _status(tr("Reading the video…"))
    try:
        info, err, saw_cookie, ladder_formats = _extract_with_ladder(
            url, proxy_url, cookies_browser)
    except Exception as exc:          # noqa: BLE001
        return False, _friendly_or_clean(str(exc)), ""
    if not info:
        msg = _friendly_or_clean(err) or tr("Couldn't read that video.")
        if saw_cookie and "cookie" not in msg.lower():
            msg = f"{msg} {_cookie_hint()}"
        return False, msg, ""
    try:
        dur = float(info.get("duration") or 0)
    except (TypeError, ValueError):
        dur = 0.0
    if dur <= 0:
        return False, tr("Couldn't read this video's duration."), ""
    if start >= dur:
        return False, tr("The start is past the end of the video."), ""
    end = min(end, dur)
    seg_len = end - start

    # Merged pool: the richest rung PLUS every other rung's streams. A
    # cut-time read that came back throttled (high tiers missing) still has
    # the 4K/1440p streams the probe read minutes earlier — picking only
    # from the richest rung is what made high tiers vanish at cut time.
    # HLS/DASH-manifest URLs are dropped up front: they hang ffmpeg's seek
    # path (see _is_direct_http). An all-manifest pool therefore yields no
    # fast-path candidates and goes straight to the yt-dlp fallback, which
    # downloads such streams natively.
    pool = _merge_format_pools(info.get("formats"), ladder_formats)
    if not pool:
        pool = info.get("formats") or []
    direct = [f for f in pool if _is_direct_http(f)]
    audio_lang = str(audio_lang or "")
    output_format = str(output_format or "mp4").lower()
    if output_format not in ("mp4", "mkv", "webm", "mp3", "m4a", "opus", "wav", "flac"):
        output_format = "mp4"
    if audio_only:
        auds = [f for f in direct if (f.get("vcodec") or "none") == "none"
                and (f.get("acodec") or "none") != "none" and f.get("url")]
        auds = _original_audio_only(auds, audio_lang)
        ac = max(auds, key=lambda f: (f.get("abr") or 0, f.get("tbr") or 0), default=None)
        cands = [(ac["url"], None, output_format, 0)] if ac else []
    else:
        cands = (_pick_stream_candidates(direct, height_cap, limit=6,
                                     audio_lang=audio_lang)
             if direct else [])
    if not audio_only and not cands and direct:
        # No candidate list (shouldn't happen when caps were offered) — fall
        # back to the single-pair picker before giving up.
        v0, a0, e0, p0 = _pick_streams(direct, height_cap, audio_lang)
        if v0:
            cands = [(v0, a0, e0, p0)]
    if audio_only and not cands:
        return False, tr("No playable audio stream was found."), ""
    got_px = cands[0][3] if cands else 0
    want = int(height_cap or 0)
    floor = int(want * 0.9) if want else 0
    try:
        pool_top = max(_available_caps(direct)) if direct else 0
    except (TypeError, ValueError):
        pool_top = 0
    try:
        ffmpeg = _ffmpeg_exe()
    except Exception as exc:          # noqa: BLE001
        return False, str(exc), ""

    vid = info.get("id") or "video"
    title = info.get("title") or tr("Untitled")
    label = (tr("Audio only") if audio_only else (f"{got_px}p" if got_px else (
        f"{int(height_cap)}p" if height_cap else tr("best"))))
    tag = clip_tag(start, end)
    stem = (f"{sanitize_filename(title)} [clip {tag}] "
            f"[{vid}] {label}"
            + (f" [{audio_lang}]" if audio_lang else ""))

    def _report(px, lbl):
        if on_resolved:
            try:
                on_resolved(int(px or 0), lbl)
            except Exception:         # noqa: BLE001 — reporting only
                pass

    # v1.0.3: the re-encode's bitrate, from the stream actually being cut
    # (see cut_video_kbps) — the Cut panel's estimate uses the same numbers.
    v_kbps = 0
    if not audio_only:
        try:
            v_kbps, _vf = _video_target_for(
                pool, height_cap, dur, audio_lang,
                v_url=cands[0][0] if cands else None)
        except Exception:             # noqa: BLE001 — CRF fallback then
            v_kbps = 0

    def _run_fallback():
        _status(tr("Trying full download instead…"))
        return _cut_via_ydl_download(
            url, height_cap, start, end, seg_len, target_dir,
            title, vid, tag, want,
            on_status=on_status, on_progress=on_progress,
            proxy_url=proxy_url, cookies_browser=cookies_browser,
            should_cancel=should_cancel, audio_lang=audio_lang,
            video_kbps=v_kbps)

    # An explicit 4K/1440p pick whose tier is not even VISIBLE right now must
    # not silently arrive as a lower tier: go straight to the fetch-then-cut
    # fallback (it walks more clients and usually still finds the tier), and
    # if that fails too, say exactly which tier is visible.
    if want and floor and (pool_top or got_px) < floor:
        ok_f, msg_f, fp_f, got_f = _run_fallback()
        if ok_f:
            _report(int(got_f or want or 0),
                    f"{int(got_f or want)}p" if (got_f or want) else label)
            return True, fp_f, fp_f
        if msg_f == DOWNLOAD_CANCELLED:
            return False, msg_f, ""
        top = pool_top or got_px or 0
        if top:
            return False, tr(
                "Couldn't get {want}p for this clip right now "
                "(highest visible: {top}p). YouTube sometimes limits high "
                "resolutions — wait a minute and cut again, or pick "
                "{top}p.").format(want=want, top=top), ""
        return False, msg_f or tr("No playable stream at that quality."), ""

    def _out_for(ext):
        return _unique_path(target_dir, f"{stem}.{ext or 'mp4'}")

    _status(tr("Cutting {a} → {b} …").format(a=fmt_clock(start),
                                             b=fmt_clock(end)))
    last_err = ""

    # ── preferred path: re-encode ──
    # A stream-copied video can only start on a keyframe, and the cut point is
    # almost never on one. The surviving first packet is then mid-GOP: players
    # skip it or render garbage until the next keyframe while the audio (which
    # has no keyframes) starts on time — that is exactly the "the cut is out of
    # sync" report, and the same broken GOP is what makes the file fall over the
    # moment another program tries to re-encode or upscale it. Re-encoding
    # decodes BOTH streams from the same point and re-timestamps them together:
    # frame-accurate, in sync, and an H.264/AAC MP4 that any editor opens.
    # Slower than copy, and correctness wins; the copy ladder below remains as
    # the fallback for a build whose ffmpeg has no encoder.
    if cands and (audio_only or output_format == "mp4"):
        v_url, a_url, _ext, _px = cands[0]
        out_path = _out_for(output_format)
        _status(tr("Cutting {a} → {b} (re-encoding for exact sync) …").format(
            a=fmt_clock(start), b=fmt_clock(end)))
        # Hardware encoder first when this PC has one, libx264 after it —
        # a GPU/driver hiccup costs one retry, never the frame-accurate cut.
        encoders = [(None, None)] if audio_only else video_encoders(ffmpeg, v_kbps)
        for _enc_name, enc_args in encoders:
            ok, msg = _run_ffmpeg_cut(
                _cut_args(ffmpeg, v_url, a_url, start, seg_len,
                          output_format if audio_only else "mp4",
                          video_reencode=not audio_only, audio_only=audio_only,
                          vcodec_args=enc_args),
                seg_len, out_path, on_progress, should_cancel)
            if ok:
                _report(int(got_px or 0), label)
                return True, out_path, out_path
            if msg == DOWNLOAD_CANCELLED:
                return False, msg, ""
            last_err = msg or last_err
            # an HTTP failure is not the encoder's fault: don't re-download
            # the same segment with another encoder, go to the next stream
            if _looks_like_expired_url(msg):
                break
        _status(tr("Re-encode unavailable — copying the stream instead …"))

    for idx, (v_url, a_url, ext, px) in enumerate(cands):
        if should_cancel is not None and should_cancel():
            return False, DOWNLOAD_CANCELLED, ""
        if idx > 0:
            _status(tr("Retrying with another stream ({i}/{n}) …").format(
                i=idx + 1, n=len(cands)))
        out_path = _out_for(output_format if audio_only else (output_format or ext))
        ok, msg = _run_ffmpeg_cut(
            _cut_args(ffmpeg, v_url, a_url, start, seg_len,
                      output_format if audio_only else (output_format or ext),
                      audio_only=audio_only),
            seg_len, out_path, on_progress, should_cancel)
        if ok:
            _report(int(got_px or 0), label)
            return True, out_path, out_path
        if msg == DOWNLOAD_CANCELLED:
            return False, msg, ""
        last_err = msg or last_err
        # Try the next candidate pair (different video/audio mux): one bad /
        # incompatible / throttled stream must not fail the whole quality.
        continue

    if audio_only:
        return False, last_err or tr("Couldn't cut the audio."), ""

    # Every stream-copy attempt failed. One last chance: keep the BEST video
    # bit-for-bit but re-encode only the audio to AAC inside .mp4 — this muxes
    # ANY codec pair (VP9+Opus, AV1+Opus, VP9+AAC, ...) into a universally
    # playable file at the picked resolution.
    if cands:
        try:
            v_url, a_url, _ext, _px = cands[0]
            out_path = _out_for("mp4")
            _status(tr("Merging compatibility mode …"))
            ok, msg = _run_ffmpeg_cut(
                _cut_args(ffmpeg, v_url, a_url, start, seg_len, "mp4",
                          audio_reencode=True),
                seg_len, out_path, on_progress, should_cancel)
            if ok:
                _report(int(got_px or 0), label)
                return True, out_path, out_path
            if msg == DOWNLOAD_CANCELLED:
                return False, msg, ""
            last_err = msg or last_err
        except Exception:             # noqa: BLE001 — fall through to re-fetch
            pass

    # Stream URLs expire within hours: if the failure looks like HTTP (403 /
    # timeout / invalid input) the links may simply have gone stale between
    # probing and cutting — resolve them ONCE more and retry the best pair.
    if cands and _looks_like_expired_url(last_err):
        try:
            _status(tr("Refreshing streams…"))
            fresh, ferr, _saw, _prev = _extract_with_ladder(
                url, proxy_url, cookies_browser, use_cache=False)
            if fresh:
                fresh_direct = [f for f in (fresh.get("formats") or [])
                                if _is_direct_http(f)]
                fcands = _pick_stream_candidates(
                    fresh_direct, height_cap, limit=2, audio_lang=audio_lang)
                if fcands:
                    v_url, a_url, ext, _px = fcands[0]
                    out_path = _out_for(ext)
                    ok, msg = _run_ffmpeg_cut(
                        _cut_args(ffmpeg, v_url, a_url, start, seg_len, ext),
                        seg_len, out_path, on_progress, should_cancel)
                    if ok:
                        _report(int(got_px or 0), label)
                        return True, out_path, out_path
                    if msg == DOWNLOAD_CANCELLED:
                        return False, msg, ""
                    last_err = msg or last_err
        except Exception:             # noqa: BLE001 — report original error
            pass
    # Fast remote-seek path failed for every pair (typical for 4K/1440p whose
    # URLs need yt-dlp's own fetching): fetch the tier with yt-dlp itself and
    # cut locally out of the finished file.
    ok_f, msg_f, fp_f, got_f = _run_fallback()
    if ok_f:
        _report(int(got_f or got_px or 0),
                f"{int(got_f or got_px)}p" if (got_f or got_px) else label)
        return True, fp_f, fp_f
    if msg_f == DOWNLOAD_CANCELLED:
        return False, msg_f, ""
    if msg_f:
        last_err = msg_f
    if not last_err:
        last_err = tr("No playable stream at that quality.")
    return False, last_err, ""


def cut_file(path, start, end, target_dir, on_status=None, on_progress=None,
             should_cancel=None, output_format="mp4", audio_only=False):
    """Cut [start, end) out of a LOCAL file (original quality, stream copy).
    Blocking — call on a worker thread. Returns (ok, message, filepath)."""
    def _status(text):
        if on_status:
            on_status(text)

    path = (path or "").strip()
    if not path or not os.path.isfile(path):
        return False, tr("Pick a video file first."), ""
    try:
        start, end = float(start), float(end)
    except (TypeError, ValueError):
        return False, tr("Bad segment times."), ""
    if not (end > start >= 0):
        return False, tr("The end must be after the start."), ""
    try:
        os.makedirs(target_dir, exist_ok=True)
    except OSError as exc:
        return False, str(exc), ""
    try:
        ffmpeg = _ffmpeg_exe()
    except Exception as exc:          # noqa: BLE001
        return False, str(exc), ""

    stem, ext = os.path.splitext(os.path.basename(path))
    ext = (ext or ".mp4").lstrip(".") or "mp4"
    output_format = str(output_format or ("mp3" if audio_only else ext)).lower()
    if output_format not in ("mp4", "mkv", "webm", "mp3", "m4a", "opus", "wav", "flac"):
        output_format = "mp3" if audio_only else "mp4"
    audio_only = bool(audio_only or output_format in ("mp3", "m4a", "opus", "wav", "flac"))
    fname = (f"{sanitize_filename(stem)} "
             f"[clip {clip_tag(start, end)}].{output_format}")
    out_path = _unique_path(target_dir, fname)
    seg_len = end - start
    pre = max(0.0, float(start) - 10.0)
    off = max(0.0, float(start) - pre)

    _status(tr("Cutting {a} → {b} …").format(a=fmt_clock(start),
                                             b=fmt_clock(end)))

    # Re-encode first — see cut_link for why stream copy cannot give a cut that
    # is both frame-accurate and in sync. v1.0.1: through the shared argument
    # builder (accurate input seek, no 10 s pre-roll decode) and the fastest
    # working encoder (GPU when present, libx264 after it). WebM cannot hold
    # H.264, so a webm pick goes straight to the stream copy instead of
    # failing an encode first.
    if audio_only:
        ok, msg = _run_ffmpeg_cut(
            _cut_args(ffmpeg, path, None, start, seg_len, output_format,
                      audio_only=True),
            seg_len, out_path, on_progress, should_cancel)
        if ok:
            return True, out_path, out_path
        return False, msg, ""
    if output_format in ("mp4", "mkv"):
        msg = ""
        for _name, enc_args in video_encoders(ffmpeg):
            ok, msg = _run_ffmpeg_cut(
                _cut_args(ffmpeg, path, None, start, seg_len, output_format,
                          video_reencode=True, vcodec_args=enc_args)
                + ["-map", "0:v:0", "-map", "0:a:0?"],
                seg_len, out_path, on_progress, should_cancel)
            if ok:
                return True, out_path, out_path
            if msg == DOWNLOAD_CANCELLED:
                return False, msg, ""
    if output_format == "webm":
        # VP9/AV1 sources copy straight into webm (fast path below); anything
        # else needs VP9 — realtime settings keep it from feeling like a render.
        ok, msg = _run_ffmpeg_cut(
            [ffmpeg, "-hide_banner", "-y", "-ss", f"{start:.3f}", "-i", path,
             "-t", f"{seg_len:.3f}", "-map", "0:v:0", "-map", "0:a:0?",
             "-c", "copy", "-avoid_negative_ts", "make_zero",
             "-progress", "pipe:1", "-nostats", "-v", "error"],
            seg_len, out_path, on_progress, should_cancel)
        if ok or msg == DOWNLOAD_CANCELLED:
            return (True, out_path, out_path) if ok else (False, msg, "")
        ok, msg = _run_ffmpeg_cut(
            [ffmpeg, "-hide_banner", "-y", "-ss", f"{start:.3f}", "-i", path,
             "-t", f"{seg_len:.3f}", "-map", "0:v:0", "-map", "0:a:0?",
             "-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8",
             "-row-mt", "1", "-crf", "30", "-b:v", "0",
             "-c:a", "libopus", "-b:a", "128k",
             "-progress", "pipe:1", "-nostats", "-v", "error"],
            seg_len, out_path, on_progress, should_cancel)
        return (True, out_path, out_path) if ok else (False, msg, "")
    # No encoder available (or the source defeated it): fall back to stream
    # copy, which keeps the original codecs. Still keyframe-approximate — that
    # limitation is inherent to copy — but a working file beats no file.
    if output_format in ("mp4", "mkv"):
        _status(tr("Re-encode unavailable — copying the stream instead …"))
    args = [ffmpeg, "-hide_banner", "-y",
            "-ss", f"{pre:.3f}", "-i", path,
            "-ss", f"{off:.3f}", "-t", f"{seg_len:.3f}",
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            "-progress", "pipe:1", "-nostats", "-v", "error"]
    if output_format == "mp4":
        args += ["-movflags", "+faststart"]
    ok, msg = _run_ffmpeg_cut(args, seg_len, out_path,
                              on_progress, should_cancel)
    if not ok:
        return False, msg, ""
    return True, out_path, out_path
