"""app.core.analysis.deep_report - Youtube Scrapper."""

import base64
import json
import os
import re
import statistics
import traceback
import urllib.parse
from datetime import datetime
from html import escape as html_escape

from app.config import CONFIG_PATH
from app.constants import GEMINI_API_KEY_DEFAULT, GEMINI_ENDPOINT, GEMINI_MODEL_DEFAULT
from app.core.ai.clients import AI_PROVIDER_LABELS
from app.core.analysis.csv_report import _CSV_DURATION_BUCKETS, _csv_analysis_build_overview, _csv_analysis_key, _csv_video_stat_row, _parse_export_date, _read_export_rows, _row_get
from app.core.analysis.snapshot import duration_label, recency_label
from app.core.analysis.report_extras import compute_insights, render_insights
from app.core.net import request_with_retry
from app.core.niche.helpers import SHORT_MAX_SECONDS
from app.core.utils import humanize_count
from app.crash import log_crash
from app.i18n import tr
from app.ui.colors import _HEX_RE, _hex_adjust, _hex_to_rgb01, _hex_to_rgba, _hex_toward_lightness

def _get_deep_analysis_dir():
    d = os.path.join(os.path.dirname(CONFIG_PATH), "deep_reports")
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        pass
    return d


_FAVICON_LINK_CACHE = {}


def _favicon_link_tag():
    """<link rel=icon> for the report, using the app's own mark.

    The PNG is embedded as a base64 data URI so the single-file report keeps
    working anywhere (no sidecar file to lose) and the browser tab shows the
    red app icon instead of the default globe. Read once per process; "" when
    the file is absent (frozen exe: assets/ rides along via the spec datas).
    """
    if "tag" in _FAVICON_LINK_CACHE:
        return _FAVICON_LINK_CACHE["tag"]
    tag = ""
    try:
        import sys
        if getattr(sys, "frozen", False):
            root = getattr(sys, "_MEIPASS", None) or os.path.dirname(sys.executable)
        else:
            root = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "..")
        with open(os.path.join(root, "assets", "favicon.png"), "rb") as f:
            b64 = base64.b64encode(f.read()).decode("ascii")
        tag = ('<link rel="icon" type="image/png" '
               f'href="data:image/png;base64,{b64}">')
    except Exception:
        tag = ""
    _FAVICON_LINK_CACHE["tag"] = tag
    return tag


DEEP_ANALYSIS_STORE_PATH = os.path.join(os.path.dirname(CONFIG_PATH), "deep_analysis.json")


def _load_deep_analysis_store():
    try:
        with open(DEEP_ANALYSIS_STORE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_deep_analysis_store(store):
    try:
        with open(DEEP_ANALYSIS_STORE_PATH, "w", encoding="utf-8") as f:
            json.dump(store, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def get_deep_analysis(path):
    """The cached {html_path, created_at} dict for this export file's last
    deep report, or None if none exists yet / the HTML file was removed."""
    entry = _load_deep_analysis_store().get(_csv_analysis_key(path))
    if not entry:
        return None
    html_path = entry.get("html_path")
    if not html_path or not os.path.isfile(html_path):
        return None
    return entry


def save_deep_analysis(path, html_path):
    store = _load_deep_analysis_store()
    entry = {"html_path": html_path, "created_at": datetime.now().strftime("%Y-%m-%d %H:%M")}
    store[_csv_analysis_key(path)] = entry
    _save_deep_analysis_store(store)
    return entry


# ── report history ──────────────────────────────────────────────────────
# `deep_analysis.json` above holds only the LATEST report per export file (it is
# keyed by the source path), which is what "open the cached report" needs. The
# history below is an append-only log of every report ever produced, so the CSV
# Analysis tab can list what was built before, for which export, with which
# blueprints folded in — and reopen any of them.
DEEP_HISTORY_PATH = os.path.join(os.path.dirname(CONFIG_PATH),
                                 "deep_report_history.json")
# Keep the log bounded; a creator who runs this weekly for years shouldn't grow
# an unbounded JSON file.
_DEEP_HISTORY_MAX = 200


def _load_deep_history():
    try:
        with open(DEEP_HISTORY_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_deep_history(entries):
    try:
        with open(DEEP_HISTORY_PATH, "w", encoding="utf-8") as f:
            json.dump(entries[:_DEEP_HISTORY_MAX], f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def record_deep_report(source_path, html_path, kind="channel",
                       blueprint_titles=None, provider="", watched=0,
                       video_count=0, brief_queries=None):
    """Append one produced report to the history log (newest first).

    `kind` says at a glance what an entry actually is:
      "channel"        — the export alone
      "combined"       — export + the creator's saved blueprints
      "combined_brief" — export + at least one Niche Scan brief (with or
                         without blueprints)
    """
    entries = _load_deep_history()
    entry = {
        "html_path": html_path,
        "source_path": source_path,
        "source_name": os.path.basename(source_path or ""),
        "kind": kind,
        "blueprints": list(blueprint_titles or []),
        # The search queries whose Insights brief was folded in. Stored so the
        # history row can say WHICH research the report leaned on — a report
        # written against "street food challenges" and one against "budget
        # cooking" are different documents even from the same export.
        "briefs": list(brief_queries or []),
        "provider": provider or "",
        "watched": int(watched or 0),
        "video_count": int(video_count or 0),
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }
    # Same HTML file recorded twice (a re-run that overwrote it) collapses to one.
    key = os.path.normcase(html_path or "")
    entries = [e for e in entries
               if os.path.normcase(e.get("html_path") or "") != key]
    entries.insert(0, entry)
    _save_deep_history(entries)
    return entry


def list_deep_reports(source_path=None):
    """History entries whose HTML is still on disk, newest first. Pass
    `source_path` to get only the reports built from that one export."""
    out = []
    key = _csv_analysis_key(source_path) if source_path else None
    for e in _load_deep_history():
        hp = e.get("html_path")
        if not hp or not os.path.isfile(hp):
            continue
        if key is not None and _csv_analysis_key(e.get("source_path") or "") != key:
            continue
        out.append(e)
    return out


def forget_deep_report(html_path, delete_file=False):
    """Drop one entry from the history log; optionally delete its HTML too."""
    key = os.path.normcase(html_path or "")
    if not key:
        return False
    entries = _load_deep_history()
    kept = [e for e in entries
            if os.path.normcase(e.get("html_path") or "") != key]
    _save_deep_history(kept)
    if delete_file:
        try:
            if os.path.isfile(html_path):
                os.remove(html_path)
        except OSError:
            pass
    return len(kept) != len(entries)


def _deep_video_stat_row(row):
    """Like _csv_video_stat_row, plus the identifiers the deep report needs
    to link out to YouTube and show each video's real thumbnail."""
    base = _csv_video_stat_row(row)
    vid = str(_row_get(row, "video_id", "Video ID", "id") or "").strip()
    url = str(_row_get(row, "url", "URL", "video_url") or "").strip()
    if not vid and url:
        m = re.search(r"(?:v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{6,})", url)
        if m:
            vid = m.group(1)
    if not url and vid:
        url = f"https://www.youtube.com/watch?v={vid}"
    base["video_id"] = vid
    base["url"] = url
    base["thumb"] = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg" if vid else ""
    return base


_WEEKDAY_NAMES_FA = ["دوشنبه", "سه‌شنبه", "چهارشنبه", "پنج‌شنبه", "جمعه", "شنبه", "یکشنبه"]

_DEEP_STOPWORDS = set("""
the a an and or of to in on for with is are was were be by this that how why
what your you we our from at as its it new best top full full's dont don't
از به که این آن را با در برای یک دو سه چهار پنج شش هفت هشت نه ده و یا اگر تا
هم می نمی شد شده است بود هر همه یه رو
""".split())


def _deep_analysis_keyword_chips(stats, pool=30, n=14):
    """Real word-frequency across the top-performing titles — not something
    the AI is asked to invent — so the 'title patterns' chips are numbers
    the analyst can trust."""
    from collections import Counter
    counter = Counter()
    display = {}
    for s in stats[:pool]:
        for raw in re.findall(r"[A-Za-z\u0600-\u06FF]{2,}", s.get("title") or ""):
            key = raw.lower()
            if key in _DEEP_STOPWORDS:
                continue
            counter[key] += 1
            display.setdefault(key, raw)
    ranked = [w for w, c in counter.most_common(n * 2) if c >= 2][:n]
    if len(ranked) < 6:
        ranked = [w for w, _c in counter.most_common(n)]
    return [(display[w], counter[w]) for w in ranked]


def _deep_analysis_build_context(filename, rows):
    """Every real, non-hallucinated number the deep report needs, computed
    straight from the raw export rows. Numbers rendered in the HTML always
    come from here, never from the model — see render_deep_analysis_html."""
    stats = [_deep_video_stat_row(r) for r in rows]
    stats = [s for s in stats if s["views"] or s["title"] != tr("Untitled")]
    if not stats:
        return None

    views_list = [s["views"] for s in stats]
    avg_views = statistics.mean(views_list)
    median_views = statistics.median(views_list)
    ranked = sorted(stats, key=lambda s: s["views"], reverse=True)

    dur_chart, max_dur_avg = [], 0
    for lo, hi, label in _CSV_DURATION_BUCKETS:
        bucket = [s["views"] for s in stats
                  if s["duration_s"] >= lo and (hi is None or s["duration_s"] < hi)]
        if bucket:
            avg = int(statistics.mean(bucket))
            dur_chart.append({"label": label, "count": len(bucket), "avg": avg})
            max_dur_avg = max(max_dur_avg, avg)

    wd_buckets = {i: [] for i in range(7)}
    for s in stats:
        dt = _parse_export_date(s.get("published"))
        if dt is not None:
            wd_buckets[dt.weekday()].append(s["views"])
    weekday_chart, max_wd_avg = [], 0
    for i in range(7):
        vs = wd_buckets[i]
        if vs:
            avg = int(statistics.mean(vs))
            weekday_chart.append({"label": _WEEKDAY_NAMES_FA[i], "count": len(vs), "avg": avg})
            max_wd_avg = max(max_wd_avg, avg)

    overview_text, _n_ok = _csv_analysis_build_overview(filename, rows)

    return {
        "n": len(stats),
        "total_views": int(sum(views_list)),
        "avg_views": int(avg_views),
        "median_views": int(median_views),
        "top_video": ranked[0] if ranked else None,
        "top_cards": ranked[:8],
        # A wider pool than the 8 shown in the HTML grid, because the
        # video-watching step files candidates into a shorts bucket and a
        # long-form bucket (_watch_plan) and needs enough of each to fill both.
        # A channel's 8 best videos can easily be all one format.
        "watch_pool": ranked[:24],
        "duration_chart": dur_chart,
        "weekday_chart": weekday_chart,
        "max_dur_avg": max_dur_avg or 1,
        "max_wd_avg": max_wd_avg or 1,
        "median_engagement": round(statistics.median([s["engagement"] for s in stats]), 2),
        "keywords": _deep_analysis_keyword_chips(ranked),
        "overview_text": overview_text or "",
    }


# ── step 1 (Gemini only): a grounded web-search briefing on the channel's
#    niche, gathered BEFORE the real synthesis call ─────────────────────
def _deep_analysis_research_prompt(overview_text):
    return (
        "Below is a real, numbers-backed digest from a YouTube channel's "
        "video export (titles, views, engagement, durations, publish "
        f"dates, and transcript excerpts where available):\n\n{overview_text}\n\n"
        "First, work out what specific topic/niche this channel covers "
        "from the titles and transcripts above — it could be absolutely "
        "anything (cooking, gaming, real estate, tech reviews, comedy, "
        "personal finance, tutorials, vlogging…). Then use Google Search "
        "to research current trends, formats, and audience preferences "
        "that are working well for that specific niche on YouTube right "
        "now — drawing on discussions from places like Reddit, creator "
        "blogs, and industry write-ups where relevant. Focus on concrete, "
        "actionable patterns (formats, hooks, pacing, thumbnail/title "
        "conventions, upload cadence, common viewer complaints or unmet "
        "demand) rather than generic advice that could apply to any "
        "channel.\n\n"
        "Respond in Persian (Farsi) as a short briefing: 8 to 14 bullet "
        "points, each 1-2 sentences, no preamble, no headings, no markdown "
        "formatting — just plain lines, each starting with '- '."
    )


def _gemini_search_briefing(ai_client, prompt, timeout=90):
    """A separate, minimal REST call to Gemini with Google Search grounding
    enabled, used only to gather the research briefing above. Grounded
    responses are known to sometimes truncate or garble structured output,
    so this call only ever asks for plain bulleted text — never JSON — and
    the result is folded into the synthesis prompt as extra context rather
    than parsed itself. If it fails for any reason (quota, network, a
    provider/model that doesn't support grounding…) it just returns "" —
    web research is a bonus for the report, never a requirement."""
    try:
        api_key = (ai_client.api_key or GEMINI_API_KEY_DEFAULT).strip()
        if not api_key:
            return ""
        model = ai_client.model or GEMINI_MODEL_DEFAULT
        url = GEMINI_ENDPOINT.format(model=model)
        body = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "tools": [{"google_search": {}}],
            "generationConfig": {"temperature": 0.4, "maxOutputTokens": 1600},
        }
        payload_bytes = json.dumps(body).encode("utf-8")

        def build():
            return urllib.request.Request(
                url, data=payload_bytes,
                headers={"Content-Type": "application/json",
                         "x-goog-api-key": api_key},
                method="POST")

        # Retried on a dropped connection like every other AI call — this one is
        # a grounded search that can sit open for a minute. The blanket
        # `except Exception: return ""` below still swallows a persistent
        # failure, because web research is a bonus for the report and never a
        # requirement; the retry just stops one proxy blip from silently
        # costing the report its research section.
        payload = json.loads(
            request_with_retry(build, timeout, ai_client.proxy,
                               provider_label="Gemini").decode("utf-8"))
        candidates = payload.get("candidates") or []
        if not candidates:
            return ""
        parts = candidates[0].get("content", {}).get("parts", [])
        return "".join(p.get("text", "") for p in parts if "text" in p).strip()
    except Exception:
        return ""


# ── step 1b (Gemini only): actually WATCH the channel's top videos ──────
# Gemini accepts a YouTube URL directly as `fileData`, so the report can be
# written from what the videos DO rather than only from their metadata. Three
# constraints shape this:
#   * one video per request — the free tier rejects a multi-video call — so this
#     is a sequential loop, not a batch. It costs minutes and quota.
#   * a watched video is cached by id AND clip window, so a second report over an
#     overlapping export never pays for the same observation twice.
#   * a full-length video is far too expensive to watch end to end (roughly 300
#     tokens per second of footage at default media resolution). Shorts are
#     watched whole; long-form is CLIPPED to the window below, which is where the
#     retention decisions a creator can act on actually live.
_WATCH_CACHE_NAME = "watched_videos.json"

# The short/long boundary, in seconds — the single app-wide rule: under 3
# minutes is a Short (watched in full), at or over is long-form (watched as a
# clip). Aliased from app.core.niche.helpers so every surface classifies the
# same way; do NOT reintroduce a local threshold here.
WATCH_SHORT_MAX_SECONDS = SHORT_MAX_SECONDS

# How many of each kind to watch. Shorts are cheap (seconds of footage each), so
# more of them fit in the same budget than long-form clips.
WATCH_SHORTS_LIMIT = 12
WATCH_LONG_LIMIT = 6

# The window watched inside a long-form video, in seconds from the start: minutes
# 2 through 10. Deliberately NOT from 0:00 — the opening is already described by
# the title/thumbnail and the transcript excerpt, while minutes 2-10 are where the
# pacing settles, the first retention dip lands and the structure becomes legible.
WATCH_LONG_START_SECONDS = 120
WATCH_LONG_END_SECONDS = 600


def _watch_plan(cards):
    """Split the candidate videos into (shorts, long_form) watch lists.

    `cards` is a view-ranked list of _deep_video_stat_row dicts (ctx["watch_pool"]),
    so taking the first N of each bucket takes the best-performing ones. A card
    with no URL can't be watched at all and is dropped.

    Both buckets are returned and both are watched when a CSV mixes formats: a
    channel that runs Shorts and long-form is running two different playbooks, and
    a report that only saw one of them would miss half of what it is advising on.
    """
    shorts, longs = [], []
    for c in cards or []:
        if not c.get("url"):
            continue
        dur = int(c.get("duration_s") or 0)
        # duration 0 means the export didn't carry one. Treated as long-form:
        # clipping a Short by mistake loses its ending, while clipping something
        # that turns out to be short just watches all of it anyway.
        if dur and dur < WATCH_SHORT_MAX_SECONDS:
            if len(shorts) < WATCH_SHORTS_LIMIT:
                shorts.append(c)
        elif len(longs) < WATCH_LONG_LIMIT:
            longs.append(c)
    return shorts, longs


def _is_google_shape(ai_client):
    """Whether this client actually speaks Google's generateContent shape.

    Checked via the resolved api_mode rather than `provider == "gemini"`: a
    Custom provider set to "Google Generative AI" is equally capable of web
    grounding and video watching, and the old identity test silently excluded
    it."""
    mode = getattr(ai_client, "api_mode", None)
    if mode:
        return mode == "google_genai"
    return getattr(ai_client, "provider", "") == "gemini"


def _watch_cache_path():
    return os.path.join(_get_deep_analysis_dir(), _WATCH_CACHE_NAME)


def _load_watch_cache():
    try:
        with open(_watch_cache_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_watch_cache(cache):
    try:
        with open(_watch_cache_path(), "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=1)
    except Exception:
        pass


def _watch_prompt_short(title, views):
    """What to look for in a Short, watched end to end.

    Different questions from long-form on purpose: a Short lives or dies on its
    first frame and its loop, and has no chapters or mid-roll structure to
    describe.
    """
    return (
        "You are a senior YouTube strategist. WATCH this SHORT (vertical, under "
        "two minutes) and report what it actually does — not what its title "
        "implies.\n\n"
        f"Title: {title}\n"
        f"Public view count: {views}\n\n"
        "Cover, concretely and briefly:\n"
        "- the first 1.5 seconds: the exact opening frame, the first words, and "
        "the sound — why a thumb stops here\n"
        "- the on-screen text/caption style, and whether it carries the story "
        "without audio\n"
        "- the pacing: how many cuts, and where the tension is held\n"
        "- the payoff: when it lands, and whether the ending loops back into the "
        "opening\n"
        "- production: framing, lighting, audio, and anything that reads as "
        "cheap or as expensive\n"
        "- what is done well, and what is weak or missed\n\n"
        "Respond in Persian (Farsi) as 5 to 9 plain lines, each starting with "
        "'- '. No preamble, no headings, no markdown."
    )


def _watch_prompt_long(title, views, start_s, end_s):
    """What to look for in the clipped middle of a long-form video.

    The prompt states the window explicitly so the model doesn't describe an
    opening it was never shown, and asks for MM:SS references that land inside it.
    """
    def _mmss(s):
        return f"{int(s) // 60}:{int(s) % 60:02d}"

    return (
        "You are a senior YouTube strategist. WATCH the section of this "
        f"long-form video between {_mmss(start_s)} and {_mmss(end_s)} — that is "
        "the only part you are being shown — and report what it actually does.\n\n"
        f"Title: {title}\n"
        f"Public view count: {views}\n\n"
        "Cover, concretely and briefly:\n"
        "- how the segment is structured, and where a viewer would be tempted to "
        "leave\n"
        "- what holds attention through it: story turns, open loops, questions, "
        "stakes\n"
        "- edit density: cut rhythm, b-roll, graphics, text on screen, sound "
        "design\n"
        "- the talking pace and whether there is dead air\n"
        "- production quality: framing, lighting, audio\n"
        "- what is done well, and what is weak or missed\n\n"
        "Reference specific moments as MM:SS timestamps inside the window you "
        "watched. Do NOT speculate about the opening seconds or the ending — you "
        "have not seen them.\n\n"
        "Respond in Persian (Farsi) as 5 to 9 plain lines, each starting with "
        "'- '. No preamble, no headings, no markdown."
    )


def _gemini_watch_video(ai_client, url, title, views, timeout=180,
                        clip=None):
    """Ask Gemini to watch ONE video (or one window of it) and describe it.

    Deliberately a direct REST call rather than going through AIClient: the
    request carries a `fileData` part, which the general client has no shape
    for.

    `clip` is an optional (start_seconds, end_seconds) window. It becomes a
    `videoMetadata` sibling of `fileData` in the SAME part — that is how the API
    expresses a clip — and cuts a two-hour upload down to the minutes actually
    being studied. Without it a single long video would cost more tokens than the
    entire rest of the report.

    A clipped request that fails is retried ONCE unclipped: clipping is an
    optimisation, and losing the observation entirely because a window was
    rejected would be a worse trade. Any remaining failure returns "" — a video
    that won't load must never take the whole report down (same contract as
    _gemini_search_briefing).
    """
    api_key = (ai_client.api_key or GEMINI_API_KEY_DEFAULT).strip()
    if not api_key or not url:
        return ""
    model = ai_client.model or GEMINI_MODEL_DEFAULT
    endpoint = (ai_client.endpoint() if hasattr(ai_client, "endpoint")
                else GEMINI_ENDPOINT.format(model=model))

    def _attempt(window):
        file_part = {"fileData": {"fileUri": url}}
        if window:
            start_s, end_s = window
            file_part["videoMetadata"] = {
                "startOffset": f"{int(start_s)}s",
                "endOffset": f"{int(end_s)}s",
            }
            prompt = _watch_prompt_long(title, views, start_s, end_s)
        else:
            prompt = _watch_prompt_short(title, views)
        body = {
            "contents": [{
                "role": "user",
                # File part first, text after — the API's documented ordering for
                # media prompts.
                "parts": [file_part, {"text": prompt}],
            }],
            "generationConfig": {"temperature": 0.4, "maxOutputTokens": 1200},
        }
        payload_bytes = json.dumps(body).encode("utf-8")

        def build():
            return urllib.request.Request(
                endpoint, data=payload_bytes,
                headers={"Content-Type": "application/json",
                         "x-goog-api-key": api_key},
                method="POST")

        # Watching one video is the single longest call this app makes — Gemini
        # ingests the footage before it answers, so the socket sits idle for
        # minutes and is exactly what a proxy gives up on. Retried like the
        # other AI calls; a persistent failure still falls through to the
        # clip-less retry and then to "" below, so a report never dies on it.
        payload = json.loads(
            request_with_retry(build, timeout, ai_client.proxy,
                               provider_label="Gemini").decode("utf-8"))
        candidates = payload.get("candidates") or []
        if not candidates:
            return ""
        parts = candidates[0].get("content", {}).get("parts", [])
        return "".join(p.get("text", "") for p in parts if "text" in p).strip()

    try:
        out = _attempt(clip)
        if out:
            return out
    except Exception:      # noqa: BLE001 — reported as "" to the caller
        pass
    if clip:
        # The window may have been rejected (an endOffset past the real duration,
        # an unsupported field on this model). Better a whole-video read than none.
        try:
            return _attempt(None)
        except Exception:  # noqa: BLE001
            return ""
    return ""


def _gemini_watch_briefing(ai_client, watch_pool, progress_cb=None):
    """Watch the channel's best videos and return one text block describing them,
    plus how many were actually watched.

    `watch_pool` is ctx["watch_pool"] — view-ranked stat rows. It is split by
    length (_watch_plan): Shorts are watched whole, long-form is clipped to the
    minutes that carry the retention decisions. Both groups run when the export
    contains both, because a channel doing Shorts AND long-form is running two
    playbooks and advising on one of them blind would be guesswork.

    The block is labelled per video with its format, so the synthesis prompt can
    tell a Short's observations from a long-form one's rather than blending
    contradictory pacing advice.
    """
    shorts, longs = _watch_plan(watch_pool)
    jobs = ([(c, None) for c in shorts]
            + [(c, (WATCH_LONG_START_SECONDS, WATCH_LONG_END_SECONDS))
               for c in longs])
    if not jobs:
        return "", 0

    cache = _load_watch_cache()
    cache_dirty = False
    blocks = []
    watched = 0
    n_short, n_long = len(shorts), len(longs)

    for i, (card, clip) in enumerate(jobs, 1):
        vid = card.get("video_id") or card.get("url")
        title = card.get("title") or ""
        views = humanize_count(card.get("views") or 0)
        is_short = clip is None
        # The cache key carries the window: the same video watched whole and
        # watched between 2:00 and 10:00 are two different observations, and
        # serving one for the other would put claims about an opening into a
        # report that never saw it.
        key = vid if is_short else "%s@%d-%d" % (vid, clip[0], clip[1])

        if progress_cb:
            if is_short:
                progress_cb(tr("Watching short {i} of {n} …").format(
                    i=i, n=n_short))
            else:
                progress_cb(tr("Watching long-form {i} of {n} …").format(
                    i=i - n_short, n=n_long))

        entry = cache.get(key)
        notes = entry.get("notes") if isinstance(entry, dict) else None
        if not notes:
            notes = _gemini_watch_video(ai_client, card["url"], title, views,
                                        clip=clip)
            if notes:
                cache[key] = {"notes": notes, "title": title,
                              "at": datetime.now().strftime("%Y-%m-%d %H:%M")}
                cache_dirty = True
        if not notes:
            continue

        watched += 1
        kind = (tr("SHORT — watched in full") if is_short
                else tr("LONG-FORM — watched {a}–{b} min").format(
                    a=WATCH_LONG_START_SECONDS // 60,
                    b=WATCH_LONG_END_SECONDS // 60))
        blocks.append("### %s — %s %s [%s]\n%s" % (
            title, views, tr("views"), kind, notes))

    if cache_dirty:
        _save_watch_cache(cache)
    if not blocks:
        return "", 0
    return "\n\n".join(blocks), watched


# ── step 2: the real synthesis call — free-form sections, not a template ──
_DEEP_ANALYSIS_JSON_SCHEMA = '''{
  "topic": "توصیف کوتاه موضوع/حوزه‌ی این کانال (مثلاً «آموزش آشپزی ایرانی» یا «چالش‌های گیمینگ ماینکرفت» یا «املاک و مستغلات»)",
  "hero_kicker": "عبارت کوتاه ۳ تا ۶ کلمه‌ای",
  "hero_title": "عنوان جذاب و کوتاه گزارش",
  "hero_subtitle": "یک جمله‌ی ۱ تا ۲ خطی که خلاصه‌ی کل گزارش را می‌گوید",
  "hero_emoji": "یک ایموجی که نمادِ بصریِ حوزه‌ی این کانال است",
  "theme_style": "کدام سبک بصری با موضوعِ این کانال جور است — فقط یکی از این مقادیر: sport | fitness | tech | gaming | food | beauty | finance | education | music | travel | nature | luxury | kids | news | auto | entertainment | health | diy | default",
  "theme_primary": "#rrggbb — رنگ اصلی که با حس‌وحال این حوزه هماهنگ است",
  "theme_secondary": "#rrggbb — رنگ دوم، برای گرادیان و نمودارها",
  "sections": [
    {
      "kicker": "برچسب کوتاه بالای عنوان بخش",
      "title": "عنوان بخش",
      "layout": "lead_pillars | lead_points | lead_steps | dos_donts | takes | ideas | callout | lead_only | blueprint",
      "lead": "پاراگراف اصلی این بخش — همیشه چرایی را توضیح بده",
      "pillars": [{"icon": "ایموجی", "title": "...", "desc": "..."}],
      "points": ["...", "..."],
      "steps": [{"title": "...", "desc": "..."}],
      "dos": ["...", "..."],
      "donts": ["...", "..."],
      "takeaways": ["...", "..."],
      "closing_note": "...",
      "ideas": [{"idea": "...", "title_structure": "...", "hook": "spoken opening line for the first 3 seconds", "visual_hook": "what is ON SCREEN during those 3 seconds (frame, movement, text overlay)", "anti_hook": "one reverse-psychology alternative opener (telling the viewer NOT to watch)", "thumbnail_prompt": "EN image-generation prompt for the thumbnail (composition, subject, text overlay)", "outline": [{"title": "beat/chapter", "desc": "what happens"}], "retention_beats": [{"time": "0:15", "risk": "why viewers leave here", "fix": "what to do about it"}], "viral_pct": 0, "why": "..."}],
      "callout_icon": "◆", "callout_title": "...", "callout_text": "...",
      "bp_title": "...", "improved_titles": ["...", "..."],
      "improved_hook": "...", "visual_hook": "...", "anti_hook": "...",
      "outline": [{"title": "...", "desc": "..."}],
      "thumbnail_prompt": "...", "thumbnail_direction": "...",
      "retention_beats": [{"time": "0:45", "risk": "...", "fix": "..."}],
      "seo_keywords": ["...", "..."], "seo_description": "...",
      "first_comment": "...", "why_fits": "...", "viral_pct": 0
    }
  ]
}'''


def _deep_analysis_prompt(filename, overview_text, n_videos, research_briefing="",
                          watch_briefing=""):
    research_block = ""
    if research_briefing:
        research_block = (
            "\n\nA short research briefing on current trends in this "
            "channel's specific niche is below (gathered separately via "
            "live web search — Reddit, creator blogs, industry "
            "write-ups). Weave relevant, concrete insights from it into "
            "your sections naturally wherever they actually fit this "
            "channel's own data — don't force it in where it doesn't "
            f"apply, and don't just repeat it verbatim:\n\n{research_briefing}\n"
        )
    watch_block = ""
    if watch_briefing:
        watch_block = (
            "\n\nThe channel's best-performing videos were then WATCHED, and "
            "the notes below describe what each one actually does on screen. "
            "Each block is labelled with what was watched: a SHORT was watched "
            "end to end, while a LONG-FORM entry was watched only across the "
            "stated minute range — so do not make claims about a long video's "
            "opening seconds or its ending from these notes. This is first-hand "
            "evidence, so prefer it over anything you would otherwise infer from "
            "titles and numbers alone. Ground your observations about hooks, "
            "pacing and packaging in these notes, and name the specific videos "
            "where it helps. If the channel runs both formats, keep their "
            "playbooks distinct rather than averaging the two:\n\n"
            f"{watch_briefing}\n"
        )
    return (
        "You are a senior YouTube growth strategist writing an in-depth, "
        "tailored report for a content creator. Below is a real, "
        f"numbers-backed digest of an export of {n_videos} videos from a "
        "YouTube channel scrape (titles, views, likes, comments, duration, "
        "publish dates, and transcript excerpts where available).\n\n"
        f"{overview_text}"
        f"{research_block}"
        f"{watch_block}\n\n"
        "First, work out exactly what topic/niche this specific channel "
        "covers from the data above — it could be anything at all "
        "(cooking, gaming, real estate, tech reviews, comedy sketches, "
        "tutorials, vlogging, fitness…). Then design a report made ONLY of "
        "sections that are genuinely relevant to THIS channel's actual "
        "niche and data. Do not use a generic one-size-fits-all template — "
        "skip any topic that wouldn't meaningfully help this specific "
        "creator, and add niche-specific sections that would (for example: "
        "a cooking channel might need a section on recipe/ingredient "
        "patterns; a gaming channel on which games or challenge formats "
        "perform best; a real-estate channel on price range or property "
        "type patterns; a tutorial channel on skill level or tooling "
        "patterns). For every section, explain the *why* behind what you "
        "observe, not just what the data shows, and where useful frame it "
        "as a problem the audience or creator faces and a concrete "
        "solution.\n\n"
        "Also choose a visual theme that matches this specific niche's "
        "mood: one emoji (hero_emoji) that visually represents it, and two "
        "hex accent colors (theme_primary, theme_secondary) — vivid and "
        "saturated enough to glow against a near-black background. Pick "
        "whatever combination genuinely fits THIS channel rather than "
        "reusing a stock pairing — as a rough feel: warm orange/red for "
        "food, cool blue/cyan for tech, energetic purple/magenta for "
        "gaming, deep green/teal for finance or nature, gold/navy for "
        "real estate or luxury, soft pink/gold for beauty — but choose "
        "your own exact shades rather than copying an example.\n\n"
        "Then pick theme_style: the SHAPE of the page, which follows the "
        "subject just as the colors do. It must be exactly one of these "
        "words — sport, fitness, tech, gaming, food, beauty, finance, "
        "education, music, travel, nature, luxury, kids, news, auto, "
        "entertainment, health, diy, default. A sports or fitness channel "
        "gets sport/fitness, a cooking channel food, a coding or gadget "
        "channel tech, a makeup channel beauty, a money channel finance, a "
        "family or toy channel kids, a car channel auto, a comedy or "
        "reaction channel entertainment, and so on. Use default only when "
        "nothing on the list genuinely fits.\n\n"
        "Respond in Persian (Farsi), and respond ONLY with a single JSON "
        "object (no markdown fences, no commentary before or after) shaped "
        "exactly like this:\n"
        f"{_DEEP_ANALYSIS_JSON_SCHEMA}\n\n"
        "Rules: 6 to 10 sections total, chosen purely for relevance to "
        "this channel — never padded to hit a number and never trimmed "
        "below what the data actually supports. The first section must "
        "use layout \"lead_pillars\" or \"lead_points\" and work as an "
        "executive summary of the single biggest findings. Include at "
        "least one \"ideas\" section somewhere (3-5 concrete next-video "
        "ideas, each a complete mini-blueprint: a title structure, a spoken "
        "hook AND a visual hook AND one anti-hook alternative, a thumbnail "
        "prompt, a 3-4 beat outline and 2-3 retention beats), and give "
        "EVERY idea a \"viral_pct\" (0-100: this idea's viral potential on "
        "THIS channel, grounded in its real numbers — similar videos' "
        "actual views here, demand signals, format fit) plus a \"why\" line "
        "saying what that estimate rests on. The estimate is an estimate, "
        "never a guarantee. Ground every thumbnail_prompt in what the "
        "watched videos actually show on screen (close-up faces, big "
        "captions, high-contrast moments) rather than generic advice. Include at "
        "least one \"dos_donts\" section. The LAST section must use layout "
        "\"takes\" (4-6 one-line key takeaways, plus an optional short "
        "closing_note). Only fill in the fields that match each section's "
        "own \"layout\" value — leave every other field as an empty array "
        "or empty string. Every string value must be written in Persian — "
        "only the JSON keys, the \"layout\" values and \"thumbnail_prompt\" "
        "stay in English. Keep every point, step, or paragraph to 1-3 sentences."
    )


def _salvage_truncated_report_json(text):
    """Recover what is recoverable from a report reply that was cut off mid-JSON.

    A report asks for the most output of anything in this app (a dozen-plus
    sections, each several paragraphs), so it is the call most likely to hit an
    output ceiling — and when it does, `json.loads` fails on the whole document
    and the user gets a report with real charts and no analysis at all. That is
    the worst possible trade: the sections that DID arrive are complete and
    perfectly usable.

    So this walks the `"sections": [` array one value at a time with
    `raw_decode`, keeping every object that closed properly and stopping at the
    one that didn't, and separately picks up the scalar hero/theme fields (which
    are emitted before the array and therefore almost always intact). Returns a
    dict shaped like the parsed reply, or None when there is nothing to salvage.
    """
    if not text:
        return None
    out = {}
    # The scalars sit before "sections" in the schema, so a simple non-greedy
    # match per key is enough and cannot run past the array into a section's own
    # "title". Only string fields are read; nothing here is a number.
    for key in ("topic", "hero_kicker", "hero_title", "hero_subtitle",
                "hero_emoji", "theme_style", "theme_primary", "theme_secondary"):
        m = re.search(r'"%s"\s*:\s*"((?:[^"\\]|\\.)*)"' % key, text)
        if m:
            try:
                out[key] = json.loads('"%s"' % m.group(1))
            except Exception:
                out[key] = m.group(1)

    idx = text.find('"sections"')
    if idx == -1:
        return out or None
    start = text.find("[", idx)
    if start == -1:
        return out or None

    decoder = json.JSONDecoder()
    sections, i, n = [], start + 1, len(text)
    while i < n:
        brace = text.find("{", i)
        if brace == -1:
            break
        try:
            obj, end = decoder.raw_decode(text, brace)
        except ValueError:
            # The section that was mid-write when the reply stopped. Everything
            # before it is intact, so stop here rather than discarding it all.
            break
        if isinstance(obj, dict):
            sections.append(obj)
        i = end
    if sections:
        out["sections"] = sections
    return out or None


def _viral_pct_or_none(value):
    """Coerce a model's viral-potential estimate to 0-100 int, or None.

    The model is asked for a number but may answer "high", "78%" or "" —
    anything unparseable is dropped rather than invented, and the renderer
    simply hides the meter for that idea.
    """
    try:
        text = str(value or "").strip().rstrip("%").strip()
        if not text:
            return None
        return max(0, min(100, int(float(text))))
    except (TypeError, ValueError):
        return None


def _clean_publish_plan(value):
    """Coerce the model's publish_plan object into renderable shape.

    Four strings plus a list of first-hour actions. An object that isn't an
    object, or one whose fields are all empty, is dropped entirely — a publish
    plan with no day in it would render as an empty box, and an empty box reads
    as the report having forgotten something.

    A model sometimes answers a dict-shaped field with a single string ("Friday
    5pm"), which is still usable information: it is folded into the "day" field
    rather than thrown away.
    """
    if isinstance(value, str):
        value = value.strip()
        if not value:
            return {}
        value = {"day": value}
    if not isinstance(value, dict):
        return {}
    plan = {
        "day": str(value.get("day") or "").strip(),
        "time": str(value.get("time") or "").strip(),
        "why": str(value.get("why") or "").strip(),
    }
    first_hour = []
    for it in (value.get("first_hour") or []):
        text = str(it or "").strip()
        if text:
            first_hour.append(text)
    plan["first_hour"] = first_hour[:6]
    if not any(plan.values()):
        return {}
    return plan


def _clean_fresh_ideas(raw_ideas, limit=5):
    """Fresh \"ideas\" are mini-blueprints, not one-liners: a spoken hook, a
    visual hook and an anti-hook alternative, a thumbnail prompt, a short
    outline and retention beats — the same working parts a saved blueprint
    carries, so the two render identically and stack as one uniform list.

    Old replies (idea/title_structure/hook only) still parse: missing fields
    simply stay empty and their blocks are hidden by the renderer.
    """
    out = []
    for it in (raw_ideas or []):
        if not isinstance(it, dict):
            continue
        outline = []
        for st in (it.get("outline") or []):
            if not isinstance(st, dict):
                continue
            t = str(st.get("title") or "").strip()
            d = str(st.get("desc") or "").strip()
            if t or d:
                outline.append({"title": t, "desc": d})
        beats = []
        for b in (it.get("retention_beats") or []):
            if not isinstance(b, dict):
                continue
            t = str(b.get("time") or "").strip()
            r = str(b.get("risk") or "").strip()
            f = str(b.get("fix") or "").strip()
            if t or r or f:
                beats.append({"time": t, "risk": r, "fix": f})
        cleaned = {
            "idea": str(it.get("idea") or "").strip(),
            "title_structure": str(it.get("title_structure") or "").strip(),
            "hook": str(it.get("hook") or "").strip(),
            "visual_hook": str(it.get("visual_hook") or "").strip(),
            "anti_hook": str(it.get("anti_hook") or "").strip(),
            "thumbnail_prompt": str(it.get("thumbnail_prompt") or "").strip(),
            "outline": outline[:6],
            "retention_beats": beats[:6],
            "viral_pct": _viral_pct_or_none(it.get("viral_pct")),
            "why": str(it.get("why") or "").strip(),
        }
        if any([cleaned["idea"], cleaned["title_structure"], cleaned["hook"],
                cleaned["visual_hook"], cleaned["anti_hook"],
                cleaned["thumbnail_prompt"], cleaned["outline"],
                cleaned["retention_beats"]]):
            out.append(cleaned)
        if len(out) >= limit:
            break
    return out


def _deep_analysis_parse_response(raw):
    text = (raw or "").strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text[:4].lower() == "json":
            text = text[4:]
        text = text.strip()
    start, end = text.find("{"), text.rfind("}")
    candidate = text[start:end + 1] if (start != -1 and end != -1 and end > start) else text
    try:
        data = json.loads(candidate)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    # Nothing parsed as a whole document, or it parsed but carried no sections:
    # try to rescue the sections that did arrive before the reply was cut off.
    if not data.get("sections"):
        salvaged = _salvage_truncated_report_json(text)
        if salvaged and salvaged.get("sections"):
            # The salvaged scalars only fill gaps — a value that survived the
            # normal parse is the more trustworthy of the two.
            for key, value in salvaged.items():
                data.setdefault(key, value)

    def s(key, default=""):
        v = data.get(key)
        return str(v).strip() if v not in (None, "") else default

    _VALID_LAYOUTS = {"lead_pillars", "lead_points", "lead_steps", "dos_donts",
                       "takes", "ideas", "callout", "lead_only", "blueprint"}

    def clean_str_list(v, limit=None):
        if not isinstance(v, list):
            return []
        out = [str(x).strip() for x in v if str(x).strip()]
        return out[:limit] if limit else out

    def clean_dict_list(v, fields, limit=None):
        out = []
        for it in (v or []):
            if not isinstance(it, dict):
                continue
            cleaned = {f: str(it.get(f, "") or "").strip() for f in fields}
            if any(cleaned.values()):
                out.append(cleaned)
        return out[:limit] if limit else out

    sections = []
    for raw_sec in (data.get("sections") or []):
        if not isinstance(raw_sec, dict):
            continue
        title = str(raw_sec.get("title") or "").strip()
        if not title:
            continue
        layout = str(raw_sec.get("layout") or "").strip()
        if layout not in _VALID_LAYOUTS:
            layout = "lead_only"
        sec = {
            "kicker": str(raw_sec.get("kicker") or "").strip(),
            "title": title,
            "layout": layout,
            "lead": str(raw_sec.get("lead") or "").strip(),
            "pillars": clean_dict_list(raw_sec.get("pillars"), ("icon", "title", "desc"), 4),
            "points": clean_str_list(raw_sec.get("points"), 8),
            "steps": clean_dict_list(raw_sec.get("steps"), ("title", "desc"), 4),
            "dos": clean_str_list(raw_sec.get("dos"), 9),
            "donts": clean_str_list(raw_sec.get("donts"), 9),
            "takeaways": clean_str_list(raw_sec.get("takeaways"), 6),
            "closing_note": str(raw_sec.get("closing_note") or "").strip(),
            "ideas": _clean_fresh_ideas(raw_sec.get("ideas")),
            "callout_icon": str(raw_sec.get("callout_icon") or "◆").strip(),
            "callout_title": str(raw_sec.get("callout_title") or "").strip(),
            "callout_text": str(raw_sec.get("callout_text") or "").strip(),
            # ── "blueprint" layout: one creator idea, sharpened against this
            #    channel's real data (Content Lab CSV "combine" feature) ──
            #
            # These fields mirror what the in-app blueprint pane shows
            # (app/qml_backend/vm/_idea_shape.py is the canonical list), because a
            # creator who has seen that pane and then reads this report should not
            # find the report to be the thinner of the two. Everything here is
            # something you can act on before the camera rolls.
            "bp_title": str(raw_sec.get("bp_title") or "").strip(),
            "improved_titles": clean_str_list(raw_sec.get("improved_titles"), 5),
            "improved_hook": str(raw_sec.get("improved_hook") or "").strip(),
            # What is ON SCREEN in the opening — distinct from improved_hook,
            # which is what is SAID. A hook line with no visual is half a hook.
            "visual_hook": str(raw_sec.get("visual_hook") or "").strip(),
            # The reverse-psychology opener. Cheap to try, and the one opener most
            # creators never think of.
            "anti_hook": str(raw_sec.get("anti_hook") or "").strip(),
            "outline": clean_dict_list(raw_sec.get("outline"), ("title", "desc"), 10),
            # A full image-generation prompt, not a vague "direction" — the point
            # is that it can be pasted straight into an image model.
            "thumbnail_prompt": str(raw_sec.get("thumbnail_prompt") or "").strip(),
            "thumbnail_direction": str(raw_sec.get("thumbnail_direction") or "").strip(),
            # Where attention is lost and what holds it, as timed beats.
            "retention_beats": clean_dict_list(
                raw_sec.get("retention_beats"), ("time", "risk", "fix"), 8),
            "seo_keywords": clean_str_list(raw_sec.get("seo_keywords"), 12),
            "seo_description": str(raw_sec.get("seo_description") or "").strip(),
            # The pinned first comment — a free retention/engagement lever.
            "first_comment": str(raw_sec.get("first_comment") or "").strip(),
            "why_fits": str(raw_sec.get("why_fits") or "").strip(),
            "viral_pct": _viral_pct_or_none(raw_sec.get("viral_pct")),
            # ── the working-creator pack: why it travels, when to post it, what
            # to watch in the first 48 hours, what would kill it, what comes
            # next. Each is grounded in the channel's own numbers by the prompt,
            # so none of them has to be generic advice. `publish_plan` is an
            # object rather than a list because it answers ONE question; the
            # other three are lists of comparable rows, which is what the
            # renderer draws well.
            "viral_why": str(raw_sec.get("viral_why") or "").strip(),
            "publish_plan": _clean_publish_plan(raw_sec.get("publish_plan")),
            "success_metrics": clean_dict_list(
                raw_sec.get("success_metrics"), ("metric", "target", "why"), 6),
            "risks": clean_dict_list(raw_sec.get("risks"), ("risk", "fix"), 6),
            "series_next": clean_dict_list(
                raw_sec.get("series_next"), ("title", "why"), 4),
        }
        # The string-cleaned viral estimates become real ints (or None): a meter
        # needs a number, not "78%".
        for idea in sec["ideas"]:
            idea["viral_pct"] = _viral_pct_or_none(idea.get("viral_pct"))
        # A section needs at least *something* to actually show, or it's noise.
        if (sec["lead"] or sec["pillars"] or sec["points"] or sec["steps"] or sec["dos"]
                or sec["donts"] or sec["takeaways"] or sec["ideas"] or sec["callout_text"]
                or sec["improved_titles"] or sec["improved_hook"] or sec["outline"]
                or sec["visual_hook"] or sec["anti_hook"] or sec["thumbnail_prompt"]
                or sec["retention_beats"] or sec["seo_keywords"]
                or sec["seo_description"] or sec["first_comment"]
                or sec["why_fits"] or sec["viral_pct"] is not None
                or sec["viral_why"] or sec["publish_plan"] or sec["success_metrics"]
                or sec["risks"] or sec["series_next"]):
            sections.append(sec)

    return {
        "topic": s("topic"),
        "hero_kicker": s("hero_kicker", "تحلیل عمیق داده‌محور کانال"),
        "hero_title": s("hero_title"),
        "hero_subtitle": s("hero_subtitle"),
        "hero_emoji": s("hero_emoji", "✨"),
        "theme_style": s("theme_style"),
        "theme_primary": s("theme_primary"),
        "theme_secondary": s("theme_secondary"),
        "sections": sections,
    }


def _deep_theme_colors(ai_primary, ai_secondary):
    """Validates the AI's two suggested accent colors — falling back to the
    original red/amber default for either one that's missing or malformed —
    and derives every other shade the CSS needs (glow, light-mode variants,
    hero background tint) from them."""
    primary = ai_primary if _HEX_RE.match(ai_primary or "") else "#ff2d55"
    secondary = ai_secondary if _HEX_RE.match(ai_secondary or "") else "#f6a723"
    r1, g1, b1 = _hex_to_rgb01(primary)
    r2, g2, b2 = _hex_to_rgb01(secondary)
    if abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2) < 0.15:
        # The two picked colors are too close to tell apart in a gradient
        # or chart — nudge the secondary one so both stay legible.
        secondary = _hex_adjust(primary, dl=0.22, ds=-0.1)
    return {
        "primary": primary,
        "secondary": secondary,
        "primary_light": _hex_adjust(primary, dl=-0.14, ds=0.05),
        "secondary_light": _hex_adjust(secondary, dl=-0.16, ds=0.05),
        "glow_dark": _hex_to_rgba(primary, 0.55),
        "glow_light": _hex_to_rgba(_hex_adjust(primary, dl=-0.14, ds=0.05), 0.28),
        "hero_a_dark": _hex_toward_lightness(primary, target_l=0.12),
        "hero_a_light": _hex_toward_lightness(primary, target_l=0.92),
    }


def _deep_theme_root_css(colors):
    return (
        '*{margin:0;padding:0;box-sizing:border-box}\n'
        ':root{--bg:#0c0d11;--bg2:#14161d;--bg3:#1a1d26;--line:#282c37;--ink:#eef0f4;--mut:#9aa2af;\n'
        f'--red:{colors["primary"]};--amber:{colors["secondary"]};--green:#25d366;--purple:#8b6cff;\n'
        '--strong:#ffffff;--body2:#c8cdd7;--track-bg:#0e1015;\n'
        f'--topbar-bg:rgba(12,13,17,.82);--hero-a:{colors["hero_a_dark"]};--hero-b:#0c0d11;'
        f'--hero-glow-op:.28;--glow:{colors["glow_dark"]}}}\n'
        'html[data-theme="light"]{--bg:#f5f5f8;--bg2:#ffffff;--bg3:#eef0f4;--line:#e1e3ea;--ink:#14161c;--mut:#6b7280;\n'
        f'--red:{colors["primary_light"]};--amber:{colors["secondary_light"]};--green:#1a9e57;--purple:#6b4fd6;\n'
        '--strong:#101216;--body2:#3d4149;--track-bg:#edeff3;\n'
        f'--topbar-bg:rgba(255,255,255,.88);--hero-a:{colors["hero_a_light"]};--hero-b:#f5f5f8;'
        f'--hero-glow-op:.30;--glow:{colors["glow_light"]}}}\n'
    )


_DEEP_REPORT_CSS = """
html{transition:background-color .25s ease,color .25s ease}
html{font-family:'Vazirmatn','Vazir','Segoe UI',Tahoma,sans-serif;color:var(--ink);background:var(--bg);line-height:1.9;font-size:15px}
body{background:var(--bg)}
b{font-weight:800;color:var(--strong)}
a{color:inherit}
.hero{position:relative;padding:70px 26px 60px;text-align:center;overflow:hidden;background:radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)}
.hero-glow{position:absolute;inset:0;background:radial-gradient(50% 40% at 50% 0%,var(--glow),transparent 70%);opacity:var(--hero-glow-op);pointer-events:none}
.hero-deco{position:absolute;top:-10px;left:50%;transform:translateX(-50%);font-size:180px;line-height:1;opacity:.07;pointer-events:none;user-select:none;filter:saturate(1.4)}
@media(max-width:820px){.hero-deco{font-size:120px}}
.kick{position:relative;color:var(--red);font-weight:800;letter-spacing:.5px;font-size:13px;margin-bottom:16px}
.hero-title{position:relative;font-weight:900;font-size:32px;line-height:1.55;max-width:880px;margin:0 auto 18px}
.hero-sub{position:relative;color:var(--body2);font-size:16px;max-width:760px;margin:0 auto 30px;line-height:2}
.hero-stats{position:relative;display:flex;gap:14px;justify-content:center;flex-wrap:wrap;margin-bottom:26px}
.hs{background:var(--bg3);border:1px solid var(--line);border-radius:14px;padding:16px 20px;min-width:140px}
.hs-n{font-weight:900;font-size:24px;background:linear-gradient(90deg,var(--red),var(--amber));-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}
.hs-l{color:var(--mut);font-size:12px;margin-top:4px}
.hero-foot{position:relative;color:var(--mut);font-size:12px}
.sec{max-width:1000px;margin:0 auto;padding:34px 22px;border-top:1px solid var(--line)}
.sechead{display:flex;gap:16px;align-items:center;margin-bottom:14px}
.secnum{font-weight:900;font-size:38px;color:transparent;-webkit-text-stroke:2px var(--red);line-height:1;flex-shrink:0;direction:ltr}
.kicker{color:var(--red);font-weight:800;font-size:12px;letter-spacing:.5px;margin-bottom:2px}
.h2{font-weight:900;font-size:22px;line-height:1.5}
.lead{color:var(--body2);font-size:15.5px;margin-bottom:18px;line-height:2.05}
.pillars{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:16px 0}
.pillar{display:flex;gap:12px;background:var(--bg2);border:1px solid var(--line);border-radius:14px;padding:15px}
.pic{font-size:24px;flex-shrink:0}
.pillar b{display:block;margin-bottom:3px}
.pillar span{color:var(--mut);font-size:13.5px;line-height:1.8}
.callout{display:flex;gap:13px;border-radius:14px;padding:15px 17px;margin:14px 0;border:1px solid var(--line);background:var(--bg2)}
.co-ic{width:30px;height:30px;border-radius:9px;display:flex;align-items:center;justify-content:center;font-weight:900;flex-shrink:0;font-size:15px;color:#0c0d11}
.co-body b{display:block;margin-bottom:3px}
.co-body span{color:var(--body2);font-size:14px;line-height:1.9}
.co-tip{border-color:rgba(139,108,255,.45)}.co-tip .co-ic{background:var(--purple)}
.two{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:6px 0}
.panel{background:var(--bg2);border:1px solid var(--line);border-radius:14px;padding:16px}
.ptitle{font-weight:800;font-size:15px;margin-bottom:12px;color:var(--strong)}
.cap{color:var(--mut);font-size:12.5px;margin-top:10px;line-height:1.75}
.statgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:16px 0}
.sc{background:var(--bg2);border:1px solid var(--line);border-radius:13px;padding:14px;text-align:center}
.sc-n{font-weight:900;font-size:20px;color:var(--red)}
.sc-l{color:var(--mut);font-size:12px;margin-top:3px}
.chart{display:flex;flex-direction:column;gap:9px}
.brow{display:flex;align-items:center;gap:10px}
.blab{width:110px;font-size:12.5px;text-align:right;flex-shrink:0;color:var(--body2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.btrack{flex:1;background:var(--track-bg);border-radius:7px;height:20px;overflow:hidden;border:1px solid var(--line)}
.bfill{height:100%;border-radius:7px;background:linear-gradient(90deg,var(--red),var(--amber))}
.bval{width:56px;text-align:left;font-weight:800;font-size:13px;direction:ltr}
.flow{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:14px 0}
.fstep{background:var(--bg2);border:1px solid var(--line);border-top:3px solid var(--red);border-radius:13px;padding:15px}
.fn{width:28px;height:28px;border-radius:50%;background:var(--red);color:#0c0d11;font-weight:900;display:flex;align-items:center;justify-content:center;margin-bottom:8px;direction:ltr}
.fstep b{display:block;margin-bottom:4px;font-size:15px}
.fstep span{color:var(--mut);font-size:13px;line-height:1.8}
.vgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:14px 0}
.vcard{display:block;background:var(--bg2);border:1px solid var(--line);border-radius:13px;overflow:hidden;text-decoration:none}
.vthumb{position:relative;aspect-ratio:16/9;background:var(--track-bg)}
.vthumb img{width:100%;height:100%;object-fit:cover;display:block}
.vcard-noimg .vthumb img{display:none}
.vdur{position:absolute;left:6px;bottom:6px;background:rgba(0,0,0,.75);color:#fff;font-size:10.5px;padding:2px 6px;border-radius:6px;direction:ltr}
.vbody{padding:10px 12px 12px}
.vtitle{font-size:12.5px;font-weight:700;color:var(--strong);line-height:1.6;margin-bottom:8px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.vmeta{display:flex;flex-wrap:wrap;gap:8px;color:var(--mut);font-size:11px;direction:ltr;justify-content:flex-end}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}
.chip{background:var(--bg3);border:1px solid var(--line);border-radius:20px;padding:6px 13px;font-size:12.5px;color:var(--body2);display:inline-block}
.chip b{color:var(--red);font-weight:800;margin-right:4px}
.ul{list-style:none;margin:4px 0}
.ul li{position:relative;padding:5px 20px 5px 0;color:var(--body2);font-size:14px;line-height:1.85}
.ul li:before{content:"▸";position:absolute;right:0;color:var(--red)}
.dobox,.dontbox{border-radius:14px;padding:16px;border:1px solid}
.dobox{background:rgba(37,211,102,.06);border-color:rgba(37,211,102,.35)}
.dontbox{background:rgba(255,45,85,.06);border-color:rgba(255,45,85,.35)}
.dohd,.donthd{font-weight:900;font-size:16px;margin-bottom:10px}
.dohd{color:var(--green)}.donthd{color:var(--red)}
.dobox ul,.dontbox ul{list-style:none}
.dobox li,.dontbox li{padding:5px 20px 5px 0;position:relative;font-size:13.5px;color:var(--body2);line-height:1.8}
.dobox li:before{content:"✓";position:absolute;right:0;color:var(--green);font-weight:900}
.dontbox li:before{content:"✕";position:absolute;right:0;color:var(--red);font-weight:900}
.takes{display:flex;flex-direction:column;gap:12px;margin:12px 0}
.take{display:flex;gap:14px;background:linear-gradient(90deg,rgba(255,45,85,.05),transparent);border:1px solid var(--line);border-right:3px solid var(--red);border-radius:12px;padding:15px}
.tn{font-weight:900;font-size:20px;color:var(--red);flex-shrink:0;direction:ltr;width:24px}
.take span{color:var(--body2);font-size:13.5px;line-height:1.9}
.ideas{display:flex;flex-direction:column;gap:12px;margin:12px 0}
.idea{background:var(--bg2);border:1px solid var(--line);border-radius:13px;padding:14px}
.idea-n{display:inline-block;background:var(--amber);color:#0c0d11;font-weight:900;font-size:11.5px;border-radius:20px;padding:3px 11px;margin-bottom:8px}
.idea b{display:block;margin-bottom:5px;font-size:14.5px;color:var(--strong)}
.idea .meta{color:var(--mut);font-size:12.5px;margin-top:4px;line-height:1.8}
.idea .meta b{display:inline;color:var(--body2);font-weight:700;font-size:12.5px}
.viral{display:flex;align-items:center;gap:10px;margin-top:10px}
.viral-badge{font-weight:900;font-size:16px;direction:ltr;flex-shrink:0;min-width:52px;text-align:left}
.viral-hi{color:var(--green)}.viral-mid{color:var(--amber)}.viral-lo{color:var(--red)}
.viral-track{flex:1;background:var(--track-bg);border-radius:7px;height:10px;overflow:hidden;border:1px solid var(--line)}
.viral-fill{height:100%;border-radius:7px}
.viral-why{color:var(--mut);font-size:12.5px;margin-top:6px;line-height:1.8}
.viral-why b{color:var(--body2)}
.hero-src{position:relative;display:flex;gap:8px;justify-content:center;align-items:center;flex-wrap:wrap;margin-bottom:22px;color:var(--mut);font-size:12.5px}
.hero-chip{background:var(--bg3);border:1px solid var(--line);border-radius:20px;padding:4px 13px;font-size:12px;color:var(--body2)}
/* A verbatim block meant to be copied out and pasted into another tool (an
   image-model prompt, a video description). Monospace + selectable + wrapping,
   and dir is set per-element so an LTR prompt is not laid out right-to-left. */
.prompt{background:var(--track-bg);border:1px solid var(--line);border-radius:10px;
padding:12px 13px;margin-top:10px;font-family:ui-monospace,SFMono-Regular,Consolas,monospace;
font-size:12.5px;line-height:1.85;color:var(--body2);white-space:pre-wrap;word-break:break-word;
user-select:all}
/* One retention beat: the timestamp in the .blab gutter, the risk in bold with
   the fix under it. Reuses .brow/.blab from the bar charts so the timestamps line
   up in the same column the charts use. */
.beat{flex:1;font-size:13px;line-height:1.8;color:var(--body2)}
.beat b{display:block;color:var(--strong);font-size:13.5px}
.beat span{display:block;color:var(--mut);font-size:12.5px}
.fig{margin:16px 0;background:var(--bg2);border:1px solid var(--line);border-radius:14px;padding:10px;overflow:hidden}
.fig img{width:100%;border-radius:9px;display:block}
.fig figcaption{color:var(--mut);font-size:12.5px;margin-top:9px;line-height:1.7;padding:0 4px}
.tbl{width:100%;border-collapse:collapse;margin:10px 0;font-size:13px;background:var(--bg2);border-radius:12px;overflow:hidden}
.tbl th{background:var(--bg3);color:var(--strong);font-weight:800;padding:9px 11px;text-align:right;font-size:12.5px}
.tbl td{padding:9px 11px;border-top:1px solid var(--line);color:var(--body2);vertical-align:top}
.mono{font-size:11.5px;color:var(--mut)}
.steps{display:flex;flex-direction:column;gap:10px;margin:12px 0}
.step{display:flex;gap:13px;background:var(--bg2);border:1px solid var(--line);border-radius:12px;padding:13px}
.stepn{width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,var(--red),var(--amber));color:#0c0d11;font-weight:900;display:flex;align-items:center;justify-content:center;flex-shrink:0;direction:ltr}
.stepb b{display:block;margin-bottom:3px;font-size:14.5px}
.stepb span{color:var(--mut);font-size:13.5px;line-height:1.8}
.formulas{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:12px 0}
.fcard{background:var(--bg2);border:1px solid var(--line);border-radius:13px;padding:14px}
.fcard b{font-size:15px}
.fcard .ex{background:var(--track-bg);border-radius:8px;padding:8px 10px;margin:8px 0;font-size:12.5px;color:var(--body2);text-align:left}
.fcard span{color:var(--mut);font-size:13px;line-height:1.8}
.emoji-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}
.ec{display:flex;gap:10px;align-items:center;background:var(--bg2);border:1px solid var(--line);border-radius:12px;padding:11px}
.ee{font-size:22px;flex-shrink:0}
.ec b{display:block;font-size:14px}.ec span{color:var(--mut);font-size:12px}
.cards2{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:12px 0}
.c2{background:var(--bg2);border:1px solid var(--line);border-radius:13px;padding:14px}
.c2 b{display:block;margin-bottom:5px;font-size:14.5px;color:var(--strong)}
.c2 span{color:var(--body2);font-size:13.5px;line-height:1.85}
.src{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px}
.srci{background:var(--bg2);border:1px solid var(--line);border-radius:9px;padding:9px 12px;font-size:11.5px;color:var(--mut);text-align:left}
.endcap{text-align:center;color:var(--mut);font-size:14px;padding:30px 20px 50px;font-weight:700}
html{scroll-behavior:smooth}
.progress{position:fixed;top:0;right:0;height:4px;background:linear-gradient(90deg,var(--red),var(--amber));width:0;z-index:100;box-shadow:0 0 12px var(--glow)}
.topbar{position:sticky;top:0;z-index:90;background:var(--topbar-bg);backdrop-filter:blur(12px);border-bottom:1px solid var(--line);padding:10px 18px;display:flex;align-items:center;justify-content:space-between;gap:10px}
.tb-brand{font-weight:900;font-size:14px;color:var(--strong);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tb-brand span{color:var(--red)}
.tb-nav{display:flex;gap:6px;flex-wrap:wrap}
.tb-nav a{color:var(--mut);font-size:12px;text-decoration:none;padding:4px 9px;border-radius:8px;white-space:nowrap}
.tb-nav a:hover{color:var(--strong);background:var(--bg3)}
.reveal{opacity:0;transform:translateY(18px);transition:opacity .6s ease,transform .6s ease}
.reveal.in{opacity:1;transform:none}
.pillar,.fstep,.take,.sc,.hs,.vcard,.idea{transition:transform .2s ease,border-color .2s ease}
.pillar:hover,.fstep:hover,.take:hover,.sc:hover,.hs:hover,.vcard:hover{transform:translateY(-3px);border-color:rgba(255,45,85,.4)}
.tb-actions{display:flex;gap:8px;align-items:center;flex-shrink:0}
.tb-btn{display:flex;align-items:center;gap:6px;background:var(--bg3);border:1px solid var(--line);color:var(--ink);font-family:inherit;font-size:12px;font-weight:700;border-radius:9px;padding:7px 12px;cursor:pointer;white-space:nowrap}
.tb-btn:hover{border-color:var(--red);color:var(--strong)}
.tb-btn-accent{background:linear-gradient(90deg,var(--red),var(--amber));border-color:transparent;color:#0c0d11}
@media(max-width:820px){.pillars,.two,.statgrid,.formulas,.cards2,.emoji-grid,.src{grid-template-columns:1fr}.vgrid{grid-template-columns:repeat(2,1fr)}.flow{grid-template-columns:1fr}
.hero-title{font-size:23px}.tb-nav{display:none}.secnum{font-size:28px}.h2{font-size:18px}
.tb-btn-label{display:none}.tb-btn{padding:8px 10px}}
@media print{
.topbar,.progress{display:none!important}
*{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important;color-adjust:exact!important}
html,body{background:var(--bg)!important}
.reveal{opacity:1!important;transform:none!important}
.pillar,.fstep,.take,.sc,.hs,.vcard,.idea{transform:none!important}
.sec{padding:22px 22px}
.panel,.pillar,.callout,.fstep,.take,.hs,.sc,.dobox,.dontbox,.vcard,.idea,.prompt{break-inside:avoid;page-break-inside:avoid}
.hero{padding:40px 26px 34px}
@page{size:A4;margin:14mm 12mm}
}
"""


# ═════════════════════════════════════════════════════════════════════════
#  TOPIC-DRIVEN PAGE SKINS
# ═════════════════════════════════════════════════════════════════════════
# The accent colours already came from the AI. This goes a step further and
# lets the SHAPE of the report follow the channel's subject: a sports channel
# gets a sharp, high-contrast, diagonal-cut page; a beauty channel gets soft
# radii and airy spacing; a finance channel gets a squared-off, ledger-like
# grid; a kids channel gets fat rounded corners and polka dots.
#
# The vocabulary is CLOSED (see _DEEP_STYLE_KEYS) so the model can never invent
# a style the stylesheet has never heard of — an unknown word falls back to a
# keyword sweep over the free-text topic/title, and only then to the neutral
# default. That means the page stays on-subject even from a model that ignores
# the instruction, and it can never come back unstyled or broken.
#
# The styles are applied as OVERRIDES on top of _DEEP_REPORT_CSS (same class
# selectors, later in the sheet, so they win) rather than by templating the
# base sheet — the base sheet stays one readable piece of CSS.

_DEEP_STYLE_KEYS = (
    "sport", "fitness", "tech", "gaming", "food", "beauty", "finance",
    "education", "music", "travel", "nature", "luxury", "kids", "news",
    "auto", "entertainment", "health", "diy", "default",
)

# radius → every card/panel, pill → chips + badges, track → the bar-chart rails,
# lift → how far a card rises on hover, grad → the angle of every accent
# gradient. kicker/h2/secnum/hero/deco/extra carry the character.
_DEEP_STYLES = {
    "sport": dict(
        radius="6px", pill="3px", track="2px", lift="-4px", grad="135deg",
        kicker="text-transform:uppercase;letter-spacing:2.6px;font-style:italic",
        h2="text-transform:uppercase;letter-spacing:.4px",
        secnum="-webkit-text-stroke:2px var(--red);font-style:italic",
        hero="background-image:repeating-linear-gradient(115deg,transparent 0 22px,rgba(255,255,255,.05) 22px 24px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.10;transform:translateX(-50%) scale(1.3)",
        extra=".btrack,.viral-track{height:22px}"
              ".btrack{border-width:0;background:linear-gradient(90deg,transparent,var(--track-bg))}"
              ".fstep{border-top-width:4px}"),
    "fitness": dict(
        radius="8px", pill="4px", track="4px", lift="-5px", grad="160deg",
        kicker="text-transform:uppercase;letter-spacing:2px;font-weight:900",
        h2="text-transform:uppercase;letter-spacing:.2px",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:repeating-linear-gradient(90deg,transparent 0 30px,rgba(255,255,255,.04) 30px 32px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.09;transform:translateX(-50%) scale(1.2)",
        extra=".hero-title{letter-spacing:-.4px}"
              ".sc-n{font-size:22px}"
              ".dobox{border-left:4px solid var(--green)}"
              ".dontbox{border-left:4px solid var(--red)}"),
    "tech": dict(
        radius="10px", pill="6px", track="3px", lift="-3px", grad="90deg",
        kicker="text-transform:uppercase;letter-spacing:3px;font-weight:700",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:linear-gradient(rgba(255,255,255,.05) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.05) 1px,transparent 1px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%);background-size:36px 36px,36px 36px,auto",
        deco="opacity:.06;filter:blur(1px) saturate(1.2)",
        extra=".sec{border-top-style:dashed}"
              ".mono,.prompt{letter-spacing:.2px}"
              ".chip{border-style:dashed}"),
    "gaming": dict(
        radius="12px", pill="4px", track="4px", lift="-6px", grad="45deg",
        kicker="text-transform:uppercase;letter-spacing:2px;font-weight:900",
        h2="text-transform:uppercase",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:radial-gradient(60% 50% at 15% 0%,var(--hero-a) 0%,transparent 60%),radial-gradient(50% 45% at 85% 10%,rgba(139,108,255,.22) 0%,transparent 65%),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.15;filter:saturate(1.6)",
        extra=".pillar,.fstep,.idea,.take{border-left:3px solid var(--red)}"
              ".secnum{font-size:42px}"),
    "food": dict(
        radius="20px", pill="999px", track="10px", lift="-3px", grad="120deg",
        kicker="letter-spacing:.6px",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:radial-gradient(rgba(255,255,255,.06) 1.5px,transparent 1.6px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%);background-size:26px 26px,auto",
        deco="opacity:.13",
        extra=".pic,.ee{font-size:26px}"
              ".chip{background:var(--bg2)}"
              ".hs-n{font-size:26px}"),
    "beauty": dict(
        radius="24px", pill="999px", track="10px", lift="-2px", grad="140deg",
        kicker="letter-spacing:3.4px;font-weight:600;text-transform:uppercase",
        h2="letter-spacing:.3px",
        secnum="-webkit-text-stroke:1.5px var(--red)",
        hero="background-image:radial-gradient(45% 40% at 20% 5%,var(--glow) 0%,transparent 70%),radial-gradient(40% 36% at 82% 12%,rgba(255,255,255,.08) 0%,transparent 70%),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.11;filter:blur(.6px)",
        extra=".lead{font-size:16px;line-height:2.15}"
              ".hero{padding:84px 26px 72px}"
              ".sc,.hs{box-shadow:0 10px 30px rgba(0,0,0,.18)}"),
    "finance": dict(
        radius="4px", pill="2px", track="2px", lift="-2px", grad="0deg",
        kicker="text-transform:uppercase;letter-spacing:1.6px;font-weight:800",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:repeating-linear-gradient(0deg,transparent 0 27px,rgba(255,255,255,.045) 27px 28px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.05",
        extra=".tbl td,.sc-n,.bval,.hs-n,.mono{font-variant-numeric:tabular-nums}"
              ".tbl th{border-bottom:2px solid var(--line)}"
              ".tbl td{border-top-style:dotted}"),
    "education": dict(
        radius="12px", pill="8px", track="6px", lift="-3px", grad="120deg",
        kicker="letter-spacing:1px;font-weight:700",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:radial-gradient(rgba(255,255,255,.05) 1px,transparent 1.1px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%);background-size:22px 22px,auto",
        deco="opacity:.09",
        extra=".lead{line-height:2.2}"
              ".ul li{padding-top:7px;padding-bottom:7px}"),
    "music": dict(
        radius="18px", pill="999px", track="10px", lift="-4px", grad="130deg",
        kicker="letter-spacing:3px;text-transform:uppercase",
        h2="letter-spacing:.2px",
        secnum="-webkit-text-stroke:2px var(--red);font-style:italic",
        hero="background-image:repeating-radial-gradient(circle at 50% 120%,transparent 0 26px,rgba(255,255,255,.05) 26px 28px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.13;filter:saturate(1.4)",
        extra=".take{border-right-width:5px}"
              ".fstep{border-top-width:3px}"),
    "travel": dict(
        radius="16px", pill="999px", track="8px", lift="-4px", grad="120deg",
        kicker="letter-spacing:2.2px;text-transform:uppercase",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:radial-gradient(rgba(255,255,255,.07) 1.4px,transparent 1.5px),linear-gradient(rgba(255,255,255,.03) 1px,transparent 1px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%);background-size:30px 30px,30px 30px,auto",
        deco="opacity:.12",
        extra=".vcard{box-shadow:0 8px 26px rgba(0,0,0,.2)}"),
    "nature": dict(
        radius="18px", pill="999px", track="10px", lift="-3px", grad="150deg",
        kicker="letter-spacing:1.6px;font-weight:700",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:radial-gradient(50% 45% at 25% 0%,var(--glow) 0%,transparent 70%),radial-gradient(45% 40% at 78% 8%,rgba(255,255,255,.07) 0%,transparent 70%),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.10",
        extra=".dobox{border-left:4px solid var(--green)}"),
    "luxury": dict(
        radius="2px", pill="0px", track="1px", lift="-1px", grad="90deg",
        kicker="text-transform:uppercase;letter-spacing:5px;font-weight:600",
        h2="letter-spacing:1px;font-weight:800",
        secnum="-webkit-text-stroke:1px var(--red);font-weight:400",
        hero="background-image:repeating-linear-gradient(90deg,transparent 0 60px,rgba(255,255,255,.05) 60px 61px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.06",
        extra=".hero-title{letter-spacing:.6px;font-weight:700}"
              ".panel,.pillar,.sc,.hs{border-color:rgba(255,255,255,.14)}"
              ".chip{border-radius:0}"),
    "kids": dict(
        radius="28px", pill="999px", track="12px", lift="-5px", grad="120deg",
        kicker="letter-spacing:1px;font-weight:900",
        h2="",
        secnum="-webkit-text-stroke:3px var(--red)",
        hero="background-image:radial-gradient(rgba(255,255,255,.09) 4px,transparent 4.6px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%);background-size:48px 48px,auto",
        deco="opacity:.17",
        extra=".pic,.ee{font-size:30px}"
              ".hero{padding:80px 26px 68px}"),
    "news": dict(
        radius="2px", pill="0px", track="2px", lift="0px", grad="0deg",
        kicker="text-transform:uppercase;letter-spacing:1.2px;font-weight:900",
        h2="font-family:Georgia,'Times New Roman',serif;letter-spacing:0",
        secnum="-webkit-text-stroke:0;color:var(--red);font-weight:900",
        hero="background-image:radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.05",
        extra=".sec{border-top:2px solid var(--line)}"
              ".hero-title{font-family:Georgia,'Times New Roman',serif;font-weight:900}"
              ".lead{font-size:16px}"),
    "auto": dict(
        radius="8px", pill="3px", track="4px", lift="-4px", grad="135deg",
        kicker="text-transform:uppercase;letter-spacing:2.2px;font-weight:800",
        h2="text-transform:uppercase;letter-spacing:.3px",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:repeating-linear-gradient(45deg,transparent 0 16px,rgba(255,255,255,.055) 16px 18px),repeating-linear-gradient(-45deg,transparent 0 26px,rgba(255,255,255,.03) 26px 28px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.09",
        extra=".fstep{border-top-width:4px}"
              ".sc-n{font-size:22px}"),
    "entertainment": dict(
        radius="16px", pill="999px", track="8px", lift="-5px", grad="45deg",
        kicker="letter-spacing:1.6px;font-weight:800;text-transform:uppercase",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red);font-style:italic",
        hero="background-image:radial-gradient(45% 40% at 18% 4%,var(--hero-a) 0%,transparent 65%),radial-gradient(45% 40% at 84% 6%,rgba(246,167,35,.20) 0%,transparent 65%),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.15;filter:saturate(1.5)",
        extra=".idea-n{font-size:12px}"
              ".pillar:hover,.sc:hover{transform:translateY(-6px)}"),
    "health": dict(
        radius="18px", pill="999px", track="8px", lift="-3px", grad="140deg",
        kicker="letter-spacing:1.6px;font-weight:700;text-transform:uppercase",
        h2="",
        secnum="-webkit-text-stroke:1.5px var(--red)",
        hero="background-image:radial-gradient(55% 45% at 30% 0%,var(--glow) 0%,transparent 70%),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%)",
        deco="opacity:.10",
        extra=".dobox{border-left:4px solid var(--green)}"
              ".lead{line-height:2.15}"),
    "diy": dict(
        radius="10px", pill="6px", track="6px", lift="-3px", grad="135deg",
        kicker="text-transform:uppercase;letter-spacing:1.6px;font-weight:800",
        h2="",
        secnum="-webkit-text-stroke:2px var(--red)",
        hero="background-image:linear-gradient(rgba(255,255,255,.045) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.045) 1px,transparent 1px),radial-gradient(120% 90% at 50% -10%,var(--hero-a) 0%,var(--hero-b) 60%);background-size:24px 24px,24px 24px,auto",
        deco="opacity:.09",
        extra=".stepn{border-radius:6px}"
              ".fstep{border-top-width:3px}"),
}

# Topic keywords → style, for when the model leaves theme_style empty. Persian
# words are matched as plain substrings (they inflect and carry ZWNJ), Latin
# ones on word boundaries (so "ai" does not match "said"). Earlier entries win,
# so put the more specific subject first.
_DEEP_STYLE_HINTS = (
    ("fitness", ("بدنسازی", "تناسب اندام", "فیتنس", "باشگاه", "تمرین ورزشی",
                 "fitness", "workout", "gym", "bodybuilding", "yoga", "pilates")),
    ("sport", ("ورزش", "فوتبال", "بسکتبال", "والیبال", "کشتی", "ورزشی",
               "sport", "football", "soccer", "basketball", "nba", "fifa",
               "goal", "match", "athlete")),
    ("gaming", ("گیمینگ", "گیم", "ماینکرفت", "پلی استیشن", "ایکس باکس",
                "gaming", "gameplay", "minecraft", "fortnite", "playstation",
                "xbox", "roblox", "esports")),
    ("tech", ("تکنولوژی", "فناوری", "برنامه‌نویسی", "کدنویسی", "گجت", "موبایل",
              "هوش مصنوعی", "کامپیوتر", "tech", "coding", "programming",
              "gadget", "software", "developer", "smartphone", "laptop")),
    ("food", ("آشپزی", "غذا", "خوراک", "دسر", "شیرینی", "کافه", "رستوران",
              "food", "cooking", "recipe", "baking", "kitchen", "dessert",
              "chef")),
    # "مو" alone is deliberately NOT a keyword: it is a substring of موسیقی,
    # موضوع, مورد … and would have claimed every music channel for beauty,
    # which is checked first.
    ("beauty", ("آرایش", "زیبایی", "میکاپ", "مراقبت از پوست", "مراقبت از مو",
                "آرایشگر", "beauty", "makeup", "skincare", "cosmetic", "haircare")),
    ("finance", ("سرمایه‌گذاری", "بورس", "کریپتو", "اقتصاد", "املاک", "مالی",
                 "پول", "ارز دیجیتال", "finance", "invest", "stock", "crypto",
                 "money", "real estate", "trading", "business")),
    # "ساز" on its own would also match دست‌ساز / سازنده; the music reading
    # is only "ساز موسیقی" or a named instrument.
    ("music", ("موسیقی", "آهنگ", "خواننده", "ساز موسیقی", "گیتار", "پیانو",
               "music", "song", "singing", "guitar", "beat", "rap", "podcast")),
    ("auto", ("خودرو", "ماشین", "اتومبیل", "موتورسیکلت", "car", "auto",
              "vehicle", "motorcycle", "engine", "driving")),
    ("kids", ("کودک", "بچه", "اسباب بازی", "کارتون", "kids", "children",
              "toy", "cartoon", "baby", "family")),
    ("travel", ("سفر", "گردشگری", "تور", "travel", "trip", "tourism",
                "journey", "vlog")),
    ("nature", ("طبیعت", "حیوانات", "محیط زیست", "کشاورزی", "nature", "animal",
                "wildlife", "garden", "farm", "plant")),
    ("health", ("سلامت", "پزشکی", "روانشناسی", "درمان", "health", "medical",
                "doctor", "psychology", "wellness", "mental")),
    ("news", ("اخبار", "تحلیل خبری", "سیاست", "news", "politics", "breaking",
              "commentary")),
    ("luxury", ("لاکچری", "لوکس", "جواهر", "luxury", "gold", "jewel",
                "premium", "watches", "fashion")),
    ("diy", ("دست‌ساز", "کار دستی", "نجاری", "diy", "craft", "woodworking",
             "handmade", "maker")),
    ("education", ("آموزش", "درس", "کنکور", "زبان", "علمی", "دانش", "education",
                   "tutorial", "learn", "course", "study", "science", "how to")),
    ("entertainment", ("سرگرمی", "کمدی", "طنز", "ری‌اکشن", "چالش",
                       "entertainment", "comedy", "funny", "reaction", "prank",
                       "challenge", "meme")),
)

# One template for every style: the selectors never change, only the values.
_DEEP_SKIN_TMPL = """
html[data-style="@S@"]{--r-card:@RADIUS@;--r-pill:@PILL@;--r-track:@TRACK@}
html[data-style="@S@"] .panel,
html[data-style="@S@"] .pillar,
html[data-style="@S@"] .callout,
html[data-style="@S@"] .fstep,
html[data-style="@S@"] .take,
html[data-style="@S@"] .sc,
html[data-style="@S@"] .hs,
html[data-style="@S@"] .vcard,
html[data-style="@S@"] .idea,
html[data-style="@S@"] .fig,
html[data-style="@S@"] .step,
html[data-style="@S@"] .fcard,
html[data-style="@S@"] .c2,
html[data-style="@S@"] .ec,
html[data-style="@S@"] .srci,
html[data-style="@S@"] .dobox,
html[data-style="@S@"] .dontbox,
html[data-style="@S@"] .prompt,
html[data-style="@S@"] .tbl{border-radius:var(--r-card)}
html[data-style="@S@"] .chip,
html[data-style="@S@"] .hero-chip,
html[data-style="@S@"] .tb-nav a,
html[data-style="@S@"] .tb-btn,
html[data-style="@S@"] .idea-n{border-radius:var(--r-pill)}
html[data-style="@S@"] .btrack,
html[data-style="@S@"] .viral-track,
html[data-style="@S@"] .bfill,
html[data-style="@S@"] .viral-fill{border-radius:var(--r-track)}
html[data-style="@S@"] .kick{@KICKER@}
html[data-style="@S@"] .h2{@H2@}
html[data-style="@S@"] .secnum{@SECNUM@}
html[data-style="@S@"] .hero{@HERO@}
html[data-style="@S@"] .hero-deco{@DECO@}
html[data-style="@S@"] .tb-btn-accent,
html[data-style="@S@"] .stepn,
html[data-style="@S@"] .progress{background:linear-gradient(@GRAD@,var(--red),var(--amber))}
html[data-style="@S@"] .hs-n{background:linear-gradient(@GRAD@,var(--red),var(--amber));-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}
html[data-style="@S@"] .pillar:hover,
html[data-style="@S@"] .fstep:hover,
html[data-style="@S@"] .take:hover,
html[data-style="@S@"] .sc:hover,
html[data-style="@S@"] .hs:hover,
html[data-style="@S@"] .vcard:hover{transform:translateY(@LIFT@)}
@EXTRA@
"""


def _deep_style_key(ai):
    """Which page skin this report wears.

    The model's own answer wins when it is one of the known styles. Otherwise
    the free-text topic/title is swept for subject keywords, so an older model
    (or a truncated reply that lost the field) still gets a page that looks
    like its subject. Falls back to the neutral default.
    """
    ai = ai or {}
    raw = str(ai.get("theme_style") or "").strip().lower()
    if raw in _DEEP_STYLE_KEYS:
        return raw
    # Tolerate a model that answered "Style: sport", "sport.", "the sport one".
    for key in _DEEP_STYLE_KEYS:
        if re.search(r"(?<![a-z])" + re.escape(key) + r"(?![a-z])", raw):
            return key
    haystack = " ".join(
        str(ai.get(k) or "") for k in
        ("topic", "hero_title", "hero_kicker", "hero_subtitle")).lower()
    if haystack.strip():
        for key, words in _DEEP_STYLE_HINTS:
            for word in words:
                if word.isascii():
                    if re.search(r"(?<![a-z0-9])" + re.escape(word)
                                 + r"(?![a-z0-9])", haystack):
                        return key
                elif word in haystack:
                    return key
    return "default"


def _scope_css(scope, css):
    """Prefix every rule in a small CSS string with one scope selector.

    The `extra` blocks in _DEEP_STYLES are written as plain rules
    (".fstep{border-top-width:4px}") because repeating the
    `html[data-style="…"]` prefix on every line would make the table
    unreadable. This walks the rules and scopes them, keeping multi-selector
    rules ("a,.b{…}") intact.
    """
    out = []
    for chunk in (css or "").split("}"):
        chunk = chunk.strip()
        if not chunk:
            continue
        head, _, decls = chunk.partition("{")
        sels = [s.strip() for s in head.split(",") if s.strip()]
        if not sels:
            continue
        out.append(",".join("%s %s" % (scope, s) for s in sels)
                   + "{" + decls + "}")
    return "\n".join(out)


def _deep_style_css(style):
    """The override block for one style ("" for the neutral default)."""
    spec = _DEEP_STYLES.get(style)
    if not spec:
        return ""
    css = _DEEP_SKIN_TMPL
    scope = 'html[data-style="%s"]' % style
    for token, key, fallback in (
            ("@S@", None, style),
            ("@RADIUS@", "radius", "14px"),
            ("@PILL@", "pill", "999px"),
            ("@TRACK@", "track", "7px"),
            ("@KICKER@", "kicker", ""),
            ("@H2@", "h2", ""),
            ("@SECNUM@", "secnum", ""),
            ("@HERO@", "hero", ""),
            ("@DECO@", "deco", ""),
            ("@GRAD@", "grad", "90deg"),
            ("@LIFT@", "lift", "-3px"),
            ("@EXTRA@", "extra", ""),
    ):
        value = fallback if key is None else spec.get(key, fallback)
        if key == "extra":
            value = _scope_css(scope, value)
        css = css.replace(token, value)
    return css


_DEEP_REPORT_JS = """
var pb = document.querySelector('.progress');
addEventListener('scroll', function () {
  var h = document.documentElement;
  pb.style.width = (h.scrollTop / (h.scrollHeight - h.clientHeight) * 100) + '%';
});
var io = new IntersectionObserver(function (entries) {
  entries.forEach(function (en) {
    if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
  });
}, { threshold: .08 });
document.querySelectorAll('.sec').forEach(function (s) { s.classList.add('reveal'); io.observe(s); });
(function () {
  var root = document.documentElement,
      btn = document.getElementById('themeToggle'),
      icon = document.getElementById('themeIcon'),
      label = document.getElementById('themeLabel');
  function applyTheme(t) {
    root.setAttribute('data-theme', t);
    if (t === 'light') { icon.textContent = '🌙'; label.textContent = 'تم تیره'; btn.title = 'تغییر به تم تیره'; }
    else { icon.textContent = '☀️'; label.textContent = 'تم روشن'; btn.title = 'تغییر به تم روشن'; }
  }
  applyTheme('dark');
  btn.addEventListener('click', function () {
    applyTheme(root.getAttribute('data-theme') === 'light' ? 'dark' : 'light');
  });
  document.getElementById('printBtn').addEventListener('click', function () { window.print(); });
})();
"""


_FA_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def _fa_num(n):
    """An int rendered in Persian digits, for badges and hero chips."""
    return str(n).translate(_FA_DIGITS)


_VIRAL_CAPTION = ("برآورد پتانسیل وایرال بر پایه‌ی داده‌ی واقعی همین کانال — "
                  "تضمین نیست.")


def _viral_html(pct, why=""):
    """One idea's viral-potential meter: a 0-100 bar, a band-coloured Persian-digit
    badge (green ≥70 / amber 40-69 / red <40) and the "why" line under it.

    Returns "" when there is no estimate — a missing number must read as
    "not estimated", never as zero.
    """
    e = html_escape
    if pct is None:
        return ""
    band = "viral-hi" if pct >= 70 else ("viral-mid" if pct >= 40 else "viral-lo")
    var = "var(--green)" if pct >= 70 else ("var(--amber)" if pct >= 40 else "var(--red)")
    why_html = (f'<div class="viral-why"><b>چرا:</b> {e(why)}</div>'
                if (why or "").strip() else "")
    return (
        f'<div class="viral"><span class="viral-badge {band}">٪{_fa_num(pct)}</span>'
        f'<div class="viral-track"><div class="viral-fill" style="width:{pct}%;'
        f'background:{var}"></div></div></div>{why_html}'
    )


def _deep_sec(num, kicker, title, inner_html):
    return (
        f'<section class="sec" id="s{num}"><div class="sechead">'
        f'<div class="secnum">{num:02d}</div><div><div class="kicker">{kicker}</div>'
        f'<h2 class="h2">{title}</h2></div></div>{inner_html}</section>'
    )


def _deep_render_section_body(sec):
    """Turns one AI-authored, free-form section into HTML using whichever
    of the report's existing visual components matches its own "layout"
    choice — this is what lets the report's structure vary channel to
    channel instead of always showing the same fixed set of boxes."""
    e = html_escape
    layout = sec.get("layout") or "lead_only"
    parts = []
    if sec.get("lead"):
        parts.append(f'<p class="lead">{e(sec["lead"])}</p>')

    if layout == "lead_pillars" and sec.get("pillars"):
        cards = "".join(
            f'<div class="pillar"><div class="pic">{e(p.get("icon") or "◆")}</div>'
            f'<div><b>{e(p.get("title") or "")}</b><span>{e(p.get("desc") or "")}</span></div></div>'
            for p in sec["pillars"]
        )
        parts.append(f'<div class="pillars">{cards}</div>')

    elif layout == "lead_points" and sec.get("points"):
        parts.append('<ul class="ul">' + "".join(f'<li>{e(p)}</li>' for p in sec["points"]) + '</ul>')

    elif layout == "lead_steps" and sec.get("steps"):
        steps_html = "".join(
            f'<div class="fstep"><div class="fn">{i}</div><b>{e(st.get("title") or "")}</b>'
            f'<span>{e(st.get("desc") or "")}</span></div>'
            for i, st in enumerate(sec["steps"], 1)
        )
        parts.append(f'<div class="flow">{steps_html}</div>')

    elif layout == "dos_donts" and (sec.get("dos") or sec.get("donts")):
        do_html = ('<div class="dobox"><div class="dohd">باید‌ها</div><ul>'
                   + "".join(f'<li>{e(p)}</li>' for p in sec["dos"]) + '</ul></div>') if sec.get("dos") else ""
        dont_html = ('<div class="dontbox"><div class="donthd">نبایدها</div><ul>'
                     + "".join(f'<li>{e(p)}</li>' for p in sec["donts"]) + '</ul></div>') if sec.get("donts") else ""
        parts.append(f'<div class="two">{do_html}{dont_html}</div>')

    elif layout == "takes" and sec.get("takeaways"):
        takes_html = "".join(
            f'<div class="take"><div class="tn">{i}</div><div><span>{e(t)}</span></div></div>'
            for i, t in enumerate(sec["takeaways"], 1)
        )
        parts.append(f'<div class="takes">{takes_html}</div>')
        if sec.get("closing_note"):
            parts.append(
                '<div class="callout co-tip"><div class="co-ic">◆</div>'
                f'<div class="co-body"><b>جمع‌بندی</b><span>{e(sec["closing_note"])}</span></div></div>'
            )

    elif layout == "ideas" and sec.get("ideas"):
        # Fresh ideas render as full mini-blueprints — the same boxes a saved
        # blueprint uses (spoken hook, visual hook, anti-hook, thumbnail,
        # outline, retention) — so fresh ideas and saved blueprints stack as
        # one uniform list instead of "brief ideas up top, details below".
        cards = []
        for i, it in enumerate(sec["ideas"], 1):
            blocks = [f'<span class="idea-n">ایده {i}</span><b>{e(it.get("idea") or "")}</b>']
            if it.get("title_structure"):
                blocks.append(f'<div class="meta"><b>ساختار عنوان:</b> {e(it.get("title_structure"))}</div>')
            if it.get("hook"):
                blocks.append(
                    '<div class="callout"><div class="co-ic" style="background:var(--amber)">▶</div>'
                    f'<div class="co-body"><b>قلاب گفتاری — ۳ ثانیه‌ی اول</b>'
                    f'<span>{e(it.get("hook"))}</span></div></div>')
            if it.get("visual_hook"):
                blocks.append(
                    '<div class="callout"><div class="co-ic" style="background:var(--purple)">👁</div>'
                    f'<div class="co-body"><b>قلاب تصویری — چه چیزی روی پرده است</b>'
                    f'<span>{e(it.get("visual_hook"))}</span></div></div>')
            if it.get("anti_hook"):
                blocks.append(
                    '<div class="callout co-tip"><div class="co-ic">↺</div>'
                    f'<div class="co-body"><b>آنتی‌هوک (روان‌شناسی معکوس)</b>'
                    f'<span>{e(it.get("anti_hook"))}</span></div></div>')
            if it.get("thumbnail_prompt"):
                blocks.append(
                    '<div class="panel"><div class="ptitle">پرامپت تامبنیل (آماده‌ی کپی)</div>'
                    f'<div class="prompt" dir="ltr">{e(it.get("thumbnail_prompt"))}</div></div>')
            if it.get("outline"):
                steps_html = "".join(
                    f'<div class="fstep"><div class="fn">{j}</div><b>{e(st.get("title") or "")}</b>'
                    f'<span>{e(st.get("desc") or "")}</span></div>'
                    for j, st in enumerate(it.get("outline") or [], 1))
                blocks.append(f'<div class="flow">{steps_html}</div>')
            if it.get("retention_beats"):
                rows = "".join(
                    '<div class="brow"><div class="blab">{t}</div>'
                    '<div class="beat"><b>{risk}</b>{fix}</div></div>'.format(
                        t=e(b.get("time") or "—"),
                        risk=e(b.get("risk") or ""),
                        fix=(f'<span>{e(b.get("fix"))}</span>' if b.get("fix") else ""))
                    for b in (it.get("retention_beats") or []))
                blocks.append(
                    '<div class="panel"><div class="ptitle">نقاط ریزش و راه نگه‌داشتن مخاطب</div>'
                    f'<div class="chart">{rows}</div></div>')
            blocks.append(_viral_html(_viral_pct_or_none(it.get("viral_pct")), it.get("why") or ""))
            cards.append(f'<div class="idea">{"".join(blocks)}</div>')
        parts.append(f'<div class="ideas">{"".join(cards)}</div>')
        if any(_viral_pct_or_none(it.get("viral_pct")) is not None for it in sec["ideas"]):
            parts.append(f'<div class="cap">{_VIRAL_CAPTION}</div>')

    elif layout == "callout" and sec.get("callout_text"):
        parts.append(
            f'<div class="callout co-tip"><div class="co-ic">{e(sec.get("callout_icon") or "◆")}</div>'
            f'<div class="co-body"><b>{e(sec.get("callout_title") or sec.get("title") or "")}</b>'
            f'<span>{e(sec["callout_text"])}</span></div></div>'
        )

    elif layout == "blueprint":
        # One saved Content Lab idea, sharpened against this channel's real
        # data. Reuses the report's own box classes so it inherits the AI-chosen
        # niche theme and the print/A4 break rules — no bespoke CSS.
        #
        # Ordered the way the work happens: what the idea IS, how it is packaged,
        # how it opens, what it looks like, what happens in it, where it will lose
        # people, how it gets found, and finally why it fits this channel.
        if sec.get("bp_title"):
            parts.append(
                '<div class="callout co-tip"><div class="co-ic">◆</div>'
                f'<div class="co-body"><b>ایده‌ی اصلی</b><span>{e(sec["bp_title"])}</span>'
                '</div></div>'
            )
        if sec.get("viral_pct") is not None:
            parts.append(
                _viral_html(sec.get("viral_pct"), sec.get("why_fits") or "")
                + f'<div class="cap">{_VIRAL_CAPTION}</div>'
            )
        if sec.get("improved_titles"):
            # Lettered A/B/C: these are meant to be TESTED against each other, and
            # a plain bullet list reads as one title written three ways.
            rows = "".join(
                f'<li><b>{chr(65 + i)}</b> — {e(t)}</li>'
                for i, t in enumerate(sec["improved_titles"])
            )
            parts.append(
                '<div class="panel"><div class="ptitle">عنوان‌های پیشنهادی برای تست A/B '
                '(بازنویسی‌شده برای این کانال)</div>'
                f'<ul class="ul">{rows}</ul>'
                '<div class="cap">هر بار یکی را امتحان کنید و نرخ کلیک را مقایسه کنید؛ '
                'همه را یک‌جا عوض نکنید.</div></div>'
            )
        if sec.get("improved_hook"):
            parts.append(
                '<div class="callout"><div class="co-ic" style="background:var(--amber)">▶</div>'
                f'<div class="co-body"><b>قلاب گفتاری — ۳ ثانیه‌ی اول</b>'
                f'<span>{e(sec["improved_hook"])}</span>'
                '</div></div>'
            )
        if sec.get("visual_hook"):
            # What the eye sees, as opposed to what the ear hears. A hook line with
            # no plan for the frame behind it is half an opening.
            parts.append(
                '<div class="callout"><div class="co-ic" style="background:var(--purple)">👁</div>'
                f'<div class="co-body"><b>قلاب تصویری — چه چیزی روی پرده است</b>'
                f'<span>{e(sec["visual_hook"])}</span>'
                '</div></div>'
            )
        if sec.get("anti_hook"):
            parts.append(
                '<div class="callout co-tip"><div class="co-ic">↺</div>'
                f'<div class="co-body"><b>آنتی‌هوک (روان‌شناسی معکوس)</b>'
                f'<span>{e(sec["anti_hook"])}</span></div></div>'
            )
        if sec.get("thumbnail_prompt"):
            # dir=ltr + mono: this is a prompt for an image model, written for that
            # tool rather than for the reader, so RTL layout would corrupt it.
            parts.append(
                '<div class="panel"><div class="ptitle">پرامپت تامبنیل (آماده‌ی کپی)</div>'
                f'<div class="prompt" dir="ltr">{e(sec["thumbnail_prompt"])}</div>'
                '<div class="cap">این متن را مستقیم به یک مدل تصویرساز بدهید.</div></div>'
            )
        if sec.get("thumbnail_direction"):
            parts.append(
                '<div class="callout co-tip"><div class="co-ic">🎨</div>'
                f'<div class="co-body"><b>جهت تامبنیل</b><span>{e(sec["thumbnail_direction"])}</span>'
                '</div></div>'
            )
        if sec.get("outline"):
            steps_html = "".join(
                f'<div class="fstep"><div class="fn">{i}</div><b>{e(st.get("title") or "")}</b>'
                f'<span>{e(st.get("desc") or "")}</span></div>'
                for i, st in enumerate(sec["outline"], 1)
            )
            parts.append(f'<div class="flow">{steps_html}</div>')
        if sec.get("retention_beats"):
            rows = "".join(
                '<div class="brow"><div class="blab">{t}</div>'
                '<div class="beat"><b>{risk}</b>{fix}</div></div>'.format(
                    t=e(b.get("time") or "—"),
                    risk=e(b.get("risk") or ""),
                    fix=(f'<span>{e(b.get("fix"))}</span>' if b.get("fix") else ""),
                )
                for b in sec["retention_beats"]
            )
            parts.append(
                '<div class="panel"><div class="ptitle">نقاط ریزش و راه نگه‌داشتن مخاطب</div>'
                f'<div class="chart">{rows}</div>'
                '<div class="cap">در هر لحظه‌ای که احتمال ترک ویدیو بالاست، کاری که '
                'باید انجام شود.</div></div>'
            )
        if sec.get("seo_keywords") or sec.get("seo_description"):
            kw = ('<div class="chips">' + "".join(
                f'<span class="chip">{e(k)}</span>' for k in sec["seo_keywords"]
            ) + '</div>') if sec.get("seo_keywords") else ""
            desc = (f'<div class="prompt" dir="auto">{e(sec["seo_description"])}</div>'
                    if sec.get("seo_description") else "")
            parts.append(
                '<div class="panel"><div class="ptitle">سئو و کشف‌شدن</div>'
                f'{kw}{desc}</div>'
            )
        if sec.get("first_comment"):
            parts.append(
                '<div class="callout"><div class="co-ic" style="background:var(--green)">💬</div>'
                f'<div class="co-body"><b>کامنت پین‌شده</b>'
                f'<span>{e(sec["first_comment"])}</span></div></div>'
            )
        if sec.get("why_fits") and sec.get("viral_pct") is None:
            # When a viral estimate exists, why_fits already rides with the
            # meter above as the idea's "why" — repeating it here would show
            # the same sentence twice.
            parts.append(
                '<div class="callout co-tip"><div class="co-ic">✓</div>'
                f'<div class="co-body"><b>چرا برای این کانال جواب می‌دهد</b>'
                f'<span>{e(sec["why_fits"])}</span></div></div>'
            )

        # ── the working-creator pack ──
        # Everything below answers a question a creator asks AFTER the idea is
        # settled: why would a stranger pass it on, when do I upload it, what
        # numbers tell me it is working, what would sink it, what do I make
        # next. Kept together at the END of the section so the document reads
        # "what to make" then "how to run it" rather than interleaving the two.
        if sec.get("viral_why"):
            parts.append(
                '<div class="callout co-tip"><div class="co-ic">↗</div>'
                f'<div class="co-body"><b>چرا وایرال می‌شود — مکانیزم پخش‌شدن</b>'
                f'<span>{e(sec["viral_why"])}</span></div></div>'
            )

        plan = sec.get("publish_plan") or {}
        if plan:
            head = []
            if plan.get("day") or plan.get("time"):
                when = " ".join(x for x in (plan.get("day"), plan.get("time")) if x)
                head.append(f'<div class="brow"><div class="blab">{e(tr("When"))}</div>'
                            f'<div class="beat"><b>{e(when)}</b></div></div>')
            if plan.get("why"):
                head.append(f'<div class="brow"><div class="blab">{e(tr("Why then"))}</div>'
                            f'<div class="beat">{e(plan["why"])}</div></div>')
            steps = "".join(f'<li>{e(s)}</li>' for s in plan.get("first_hour") or [])
            if steps:
                head.append(f'<div class="brow"><div class="blab">{e(tr("First hour"))}</div>'
                            f'<div class="beat"><ul class="ul">{steps}</ul></div></div>')
            if head:
                parts.append(
                    '<div class="panel"><div class="ptitle">'
                    + e(tr("Publish plan")) + f'</div><div class="chart">{"".join(head)}</div>'
                    '<div class="cap">' + e(tr("Publishing time is a lever most "
                    "creators never touch — this one is read off your own "
                    "numbers.")) + '</div></div>'
                )

        metrics = sec.get("success_metrics") or []
        if metrics:
            rows = "".join(
                '<div class="brow"><div class="blab">{m}</div>'
                '<div class="beat"><b>{t}</b>{w}</div></div>'.format(
                    m=e(x.get("metric") or ""),
                    t=e(x.get("target") or ""),
                    w=(f'<span>{e(x.get("why"))}</span>' if x.get("why") else ""),
                ) for x in metrics)
            parts.append(
                '<div class="panel"><div class="ptitle">'
                + e(tr("What to watch — first 48 hours"))
                + f'</div><div class="chart">{rows}</div><div class="cap">'
                + e(tr("Targets are read off this channel's own averages, not off "
                       "someone else's benchmark.")) + '</div></div>'
            )

        risks = sec.get("risks") or []
        if risks:
            rows = "".join(
                '<div class="brow"><div class="blab">{n}</div>'
                '<div class="beat"><b>{r}</b>{f}</div></div>'.format(
                    n=chr(65 + i),
                    r=e(x.get("risk") or ""),
                    f=(f'<span>{e(x.get("fix"))}</span>' if x.get("fix") else ""),
                ) for i, x in enumerate(risks))
            parts.append(
                '<div class="panel"><div class="ptitle">'
                + e(tr("What could sink this video"))
                + f'</div><div class="chart">{rows}</div><div class="cap">'
                + e(tr("Named before the shoot, so they get fixed instead of "
                       "explained afterwards.")) + '</div></div>'
            )

        nxt = sec.get("series_next") or []
        if nxt:
            rows = "".join(f'<li><b>{e(x.get("title") or "")}</b>'
                           f'{(" — " + e(x["why"])) if x.get("why") else ""}</li>'
                           for x in nxt if x.get("title"))
            if rows:
                parts.append(
                    '<div class="panel"><div class="ptitle">'
                    + e(tr("What comes next — keep this viewer"))
                    + f'</div><ul class="ul">{rows}</ul><div class="cap">'
                    + e(tr("One video is a view; a series is a subscriber.")) + '</div></div>'
                )

    return "".join(parts)


def _deep_brief_panels(briefs):
    """The MEASURED half of each selected snapshot, rendered as real HTML panels.

    Separate from the prompt digest (_brief_context) and from the AI's own
    sections, because it answers a different question: not "what does the model
    think of this research" but "what did the research actually measure". Every
    number here is computed by app.core.analysis.snapshot from real search rows —
    the same discipline the rest of this report follows, where charts and stats
    come from Python and only the narrative comes from a model.

    Without this the snapshot's numbers only ever reached the model, so a reader
    got the AI's paraphrase of a median and never the median. It is rendered
    whether or not a written brief exists: the aggregates need no AI call.

    Returns "" when nothing measurable was selected.
    """
    e = html_escape
    blocks = []
    for record in (briefs or []):
        if not isinstance(record, dict):
            continue
        snap = record.get("analytics")
        if not isinstance(snap, dict) or not snap.get("total_videos"):
            continue
        query = (record.get("query") or "").strip() or tr("Untitled")
        total = int(snap.get("total_videos") or 0)

        # ── the headline pair, and the warning that goes with it ──
        median = snap.get("median_views")
        average = snap.get("avg_views")
        skew = snap.get("skew")
        cells = [
            (f"{total:,}", "ویدیوی بررسی‌شده"),
            (humanize_count(median) if median else "—", "میانه‌ی بازدید"),
            (humanize_count(average) if average else "—", "میانگین بازدید"),
        ]
        if snap.get("median_daily_views"):
            cells.append((humanize_count(snap["median_daily_views"]),
                          "بازدید روزانه (میانه)"))
        cells.append((str(snap.get("unique_channels") or 0), "کانال متمایز"))
        if snap.get("top_channel_share") is not None:
            cells.append((f'{round((snap.get("top_channel_share") or 0) * 100)}٪',
                          "سهم بزرگ‌ترین کانال"))
        if snap.get("interaction_rate") is not None:
            cells.append((f'{round(snap["interaction_rate"] * 100, 2)}٪',
                          "تعامل دیده‌شدنی"))
        stat_html = "".join(
            f'<div class="sc"><div class="sc-n">{v}</div><div class="sc-l">{e(l)}</div></div>'
            for v, l in cells)

        parts = [f'<div class="statgrid">{stat_html}</div>']

        # The single most misleading number in YouTube research is an average
        # quoted alone, so where the set is outlier-driven the report says so in
        # its own words rather than leaving the two numbers side by side.
        if skew and skew >= 1.5:
            parts.append(
                '<div class="callout"><div class="co-ic" style="background:var(--amber)">!</div>'
                '<div class="co-body"><b>این مجموعه آوتلایر-محور است</b>'
                f'<span>میانگین {round(skew, 1)} برابرِ میانه است، پس عددی که یک ویدیوی '
                'تازه می‌تواند انتظارش را داشته باشد میانه است، نه میانگین.</span></div></div>')

        # ── length mix: what format this demand is being served in ──
        mix = snap.get("duration_mix") or {}
        rows_with_duration = int(snap.get("duration_rows") or 0)
        if mix and rows_with_duration:
            top_count = max(mix.values()) or 1
            rows_html = "".join(
                f'<div class="brow"><div class="blab">{e(duration_label(key))}</div>'
                f'<div class="btrack"><div class="bfill" style="width:'
                f'{max(6, round(count / top_count * 100, 1))}%"></div></div>'
                f'<div class="bval">{count}</div></div>'
                for key, count in mix.items() if count)
            parts.append(
                '<div class="panel"><div class="ptitle">طولِ ویدیوهایی که این تقاضا را '
                f'پاسخ می‌دهند</div><div class="chart">{rows_html}</div>'
                f'<div class="cap">از {rows_with_duration} ردیفی که طول داشتند. '
                'این توزیعِ عرضه است، نه سلیقه‌ی مخاطب.</div></div>')

        # ── recency: is the topic alive ──
        recency = snap.get("recency_mix") or {}
        dated = int(snap.get("dated_rows") or 0)
        if recency and dated:
            top_count = max(recency.values()) or 1
            rows_html = "".join(
                f'<div class="brow"><div class="blab">{e(recency_label(key))}</div>'
                f'<div class="btrack"><div class="bfill" style="width:'
                f'{max(6, round(count / top_count * 100, 1))}%"></div></div>'
                f'<div class="bval">{count}</div></div>'
                for key, count in recency.items() if count)
            parts.append(
                '<div class="panel" style="margin-top:14px"><div class="ptitle">'
                f'تازگیِ انتشار</div><div class="chart">{rows_html}</div>'
                f'<div class="cap">از {dated} ردیفی که تاریخ انتشار داشتند.</div></div>')

        # ── who holds the niche ──
        holders = snap.get("top_channels") or []
        if holders:
            rows_html = "".join(
                '<div class="brow"><div class="blab">{name}</div>'
                '<div class="btrack"><div class="bfill" style="width:{w}%"></div></div>'
                '<div class="bval">{share}٪</div></div>'.format(
                    name=e(str(c.get("title") or "—")),
                    w=max(6, round((c.get("share") or 0) * 100, 1)),
                    share=round((c.get("share") or 0) * 100))
                for c in holders[:5] if isinstance(c, dict))
            parts.append(
                '<div class="panel" style="margin-top:14px"><div class="ptitle">'
                'بزرگ‌ترین دارندگان این نیچ (سهم از بازدید)</div>'
                f'<div class="chart">{rows_html}</div>'
                '<div class="cap">تمرکز بالا یعنی نیچی جاافتاده با بازیگران مستقر؛ '
                'پراکندگی یعنی میدانی باز.</div></div>')

        # ── the terms that keep coming back ──
        topics = snap.get("topics") if isinstance(snap.get("topics"), dict) else {}
        chips = topics.get("chips") or []
        if chips:
            source = ("برچسب‌های واقعی ویدیوها" if topics.get("source") == "tags"
                      else "فراوانی کلمات در عنوان‌ها")
            chips_html = "".join(
                f'<span class="chip">{e(str(item[0]))} <b>×{int(item[1])}</b></span>'
                for item in chips[:14]
                if isinstance(item, (list, tuple)) and len(item) >= 2)
            if chips_html:
                parts.append(
                    '<div class="panel" style="margin-top:14px"><div class="ptitle">'
                    'عبارت‌های پرتکرار در این نیچ</div>'
                    f'<div class="chips">{chips_html}</div>'
                    f'<div class="cap">منبع: {source}. این نشان می‌دهد چه چیزی '
                    '<b>عرضه</b> می‌شود — ثابت نمی‌کند چه چیزی تقاضا دارد.</div></div>')

        # ── videos that reached far past their own subscribers ──
        breakouts = snap.get("breakout_leaders") or []
        if breakouts:
            items = "".join(
                f'<li>{e(str(b.get("title") or ""))} — '
                f'<b>{round(float(b.get("value") or 0), 1)}×</b> تعداد مشترکِ کانالش</li>'
                for b in breakouts[:5] if isinstance(b, dict))
            if items:
                parts.append(
                    '<div class="panel" style="margin-top:14px"><div class="ptitle">'
                    'بیشترین دیده‌شدن فراتر از مشترکان</div>'
                    f'<ul class="ul">{items}</ul>'
                    '<div class="cap">بازدید ÷ مشترک: نزدیک‌ترین نشانه‌ی عمومی به '
                    '«الگوریتم این را هل داد».</div></div>')

        # ── coverage: what the snapshot could actually see ──
        coverage = snap.get("coverage") if isinstance(snap.get("coverage"), dict) else {}
        if coverage:
            labels = (("views", "بازدید"), ("interaction", "لایک و کامنت (هر دو)"),
                      ("subscribers", "تعداد مشترک عمومی"), ("duration", "طول"),
                      ("published", "تاریخ انتشار"), ("tags", "برچسب"),
                      ("captions", "زیرنویس"))
            items = "".join(
                f'<li>{e(label)}: <b>{int(coverage.get(key) or 0)}</b> از {total}</li>'
                for key, label in labels if key in coverage)
            parts.append(
                '<div class="panel" style="margin-top:14px"><div class="ptitle">'
                'این تحقیق واقعاً چه چیزی را دیده</div>'
                f'<ul class="ul">{items}</ul>'
                '<div class="cap">هر چیزی که کم است، واقعاً در دسترس نبوده و صفر '
                'حساب نشده است.</div></div>')

        blocks.append(
            f'<p class="lead">تحقیق روی جست‌وجوی «{e(query)}» — {total} ویدیو از '
            '<b>کانال‌های دیگر</b> در همین نیچ. این‌ها اعدادِ سمت تقاضا هستند و هیچ‌کدام '
            'کانال خودِ شما را توصیف نمی‌کنند؛ همه مستقیماً از ردیف‌های واقعی همان '
            'جست‌وجو محاسبه شده‌اند، نه توسط هوش مصنوعی.</p>'
            + "".join(parts))
    return "".join(blocks)


def render_deep_analysis_html(ctx, ai, filename, provider_label, used_web_research=False,
                              watched_videos=0, briefs=None, blueprint_titles=None, insights_html=""):
    e = html_escape
    sections = []
    n = 1
    ai_sections = ai.get("sections") or []

    hero_title = e(ai.get("hero_title") or f"گزارش عمیق تحلیل کانال · {filename}")
    hero_sub = e(ai.get("hero_subtitle") or "")
    kicker = e(ai.get("hero_kicker") or "تحلیل عمیق داده‌محور کانال")
    hero_stats = [
        (f"{ctx['n']:,}", "ویدیوی تحلیل‌شده"),
        (humanize_count(ctx["total_views"]), "مجموع بازدید"),
        (humanize_count(ctx["avg_views"]), "میانگین بازدید"),
        (humanize_count(ctx["median_views"]), "میانه‌ی بازدید"),
    ]
    if ctx.get("top_video"):
        hero_stats.append((humanize_count(ctx["top_video"]["views"]), "پربازدیدترین ویدیو"))
    hs_html = "".join(
        f'<div class="hs"><div class="hs-n">{v}</div><div class="hs-l">{e(l)}</div></div>'
        for v, l in hero_stats
    )
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M")
    topic_bit = f' · حوزه: {e(ai["topic"])}' if ai.get("topic") else ""
    hero_emoji = e(ai.get("hero_emoji") or "✨")
    # What the report folded in, at a glance: the channel CSV is always there;
    # blueprints and snapshot briefs ride along only in a combined report.
    src_chips = ['<span class="hero-chip">CSV · %s ویدیو</span>' % _fa_num(ctx["n"])]
    if blueprint_titles:
        src_chips.append('<span class="hero-chip">%s بلوپرینت</span>'
                         % _fa_num(len(blueprint_titles)))
    measured_briefs = [r for r in (briefs or [])
                       if isinstance(r, dict)
                       and isinstance(r.get("analytics"), dict)
                       and r["analytics"].get("total_videos")]
    if measured_briefs:
        src_chips.append('<span class="hero-chip">%s بریف</span>'
                         % _fa_num(len(measured_briefs)))
    src_html = ('<div class="hero-src">این گزارش از: ' + "".join(src_chips)
                + ' ساخته شده</div>')
    hero_html = (
        '<div class="hero">'
        f'<div class="hero-deco">{hero_emoji}</div>'
        '<div class="hero-glow"></div>'
        f'<div class="kick">{kicker}</div>'
        f'<h1 class="hero-title">{hero_title}</h1>'
        + (f'<p class="hero-sub">{hero_sub}</p>' if hero_sub else "")
        + f'<div class="hero-stats">{hs_html}</div>'
        + src_html
        + f'<div class="hero-foot">تهیه‌شده در {now_str} · بر پایه‌ی {ctx["n"]} ویدیوی واقعی از '
          f'فایل «{e(filename)}»{topic_bit} · هوش مصنوعی: {e(provider_label)}</div>'
        + '</div>'
    )

    # -- data-driven insights: verdict cards, action plans, roadmaps, checklists --
    if insights_html:
        sections.append(("دیتای قابل اجرا", _deep_sec(
            n, "یافته‌های اصلی", "یافته‌های اصلی از داده", insights_html)))
        n += 1

    # -- first AI section (executive summary), if the model returned one --
    remaining_ai_sections = list(ai_sections)
    if remaining_ai_sections:
        first = remaining_ai_sections.pop(0)
        body = _deep_render_section_body(first)
        if body:
            sections.append((first["title"], _deep_sec(
                n, first.get("kicker") or "خلاصه اجرایی", first["title"], body)))
            n += 1

    # -- fixed: data breakdown (real charts + stats + keyword chips) ------
    panels = []
    if ctx["duration_chart"]:
        rows_html = "".join(
            f'<div class="brow"><div class="blab">{e(it["label"])}</div>'
            f'<div class="btrack"><div class="bfill" style="width:'
            f'{max(6, round(it["avg"] / ctx["max_dur_avg"] * 100, 1))}%"></div></div>'
            f'<div class="bval">{humanize_count(it["avg"])}</div></div>'
            for it in ctx["duration_chart"]
        )
        panels.append(
            '<div class="panel"><div class="ptitle">میانگین بازدید بر اساس طول ویدیو</div>'
            f'<div class="chart">{rows_html}</div>'
            '<div class="cap">میانگین بازدید هر بازه‌ی طول، بر پایه‌ی داده‌ی واقعیِ همین خروجی.</div></div>'
        )
    if ctx["weekday_chart"]:
        rows_html = "".join(
            f'<div class="brow"><div class="blab">{e(it["label"])}</div>'
            f'<div class="btrack"><div class="bfill" style="width:'
            f'{max(6, round(it["avg"] / ctx["max_wd_avg"] * 100, 1))}%"></div></div>'
            f'<div class="bval">{humanize_count(it["avg"])}</div></div>'
            for it in ctx["weekday_chart"]
        )
        panels.append(
            '<div class="panel"><div class="ptitle">میانگین بازدید بر اساس روز انتشار</div>'
            f'<div class="chart">{rows_html}</div>'
            '<div class="cap">هر روز، میانگین بازدیدِ ویدیوهایی که آن روز از هفته منتشر شده‌اند.</div></div>'
        )
    two_html = f'<div class="two">{"".join(panels)}</div>' if panels else ""
    stat_cells = [
        (f"{ctx['n']:,}", "تعداد ویدیو"),
        (humanize_count(ctx["total_views"]), "مجموع بازدید"),
        (humanize_count(ctx["avg_views"]), "میانگین بازدید"),
        (humanize_count(ctx["median_views"]), "میانه‌ی بازدید"),
        (f'{ctx["median_engagement"]}٪', "میانه‌ی نرخ تعامل"),
    ]
    if ctx.get("top_video"):
        stat_cells.append((humanize_count(ctx["top_video"]["views"]), "بیشترین بازدید یک ویدیو"))
    stat_html = "".join(
        f'<div class="sc"><div class="sc-n">{v}</div><div class="sc-l">{e(l)}</div></div>'
        for v, l in stat_cells
    )
    chips_panel = ""
    if ctx["keywords"]:
        chips_html = '<div class="chips">' + "".join(
            f'<span class="chip">{e(w)} <b>×{c}</b></span>' for w, c in ctx["keywords"]
        ) + '</div>'
        chips_panel = (
            '<div class="panel" style="margin-top:14px"><div class="ptitle">'
            'کلمات پرتکرار در عنوان ویدیوهای پربازدید</div>' + chips_html
            + '<div class="cap">بر پایه‌ی فراوانی واقعی کلمات در عنوان‌های همین خروجی.</div></div>'
        )
    inner = two_html + f'<div class="statgrid">{stat_html}</div>' + chips_panel
    sections.append(("کالبدشکافی داده", _deep_sec(n, "داده", "کالبدشکافی داده", inner)))
    n += 1

    # -- fixed: top videos (real thumbnails, real numbers) ------------------
    if ctx["top_cards"]:
        cards = "".join(
            '<a class="vcard" href="{url}" target="_blank" rel="noopener">'
            '<div class="vthumb">{img}<span class="vdur">{dur}</span></div>'
            '<div class="vbody"><div class="vtitle">{title}</div>'
            '<div class="vmeta"><span>▶ {views}</span><span>❤ {likes}</span><span>{eng}٪</span></div>'
            '</div></a>'.format(
                url=e(v.get("url") or "#"),
                img=(f'<img src="{e(v["thumb"])}" alt="" loading="lazy" '
                     'onerror="this.closest(\'.vcard\').classList.add(\'vcard-noimg\')">')
                if v.get("thumb") else "",
                dur=e(v.get("duration_h") or ""),
                title=e(v.get("title") or ""),
                views=humanize_count(v.get("views", 0)),
                likes=humanize_count(v.get("likes", 0)),
                eng=v.get("engagement", 0),
            )
            for v in ctx["top_cards"]
        )
        inner = ('<p class="lead">پربازدیدترین ویدیوهای این خروجی — برای بازکردن هرکدام روی آن '
                  f'کلیک کنید.</p><div class="vgrid">{cards}</div>')
        sections.append(("پربازدیدترین ویدیوها", _deep_sec(
            n, "برترین‌ها", "پربازدیدترین ویدیوها", inner)))
        n += 1

    # -- the creator's own snapshot research, as REAL measured panels ---------
    # Placed after the channel's own data and before the AI's narrative
    # sections, which is the order the reader needs: this is my channel, this is
    # what the wider niche actually looks like, and only then what to conclude.
    # Rendered from the stored aggregates in Python — the model never touches
    # these numbers, same rule as every other chart in this report.
    brief_html = _deep_brief_panels(briefs)
    if brief_html:
        sections.append(("تحقیق نیچ", _deep_sec(
            n, "سمت تقاضا", "تحقیق نیچ — اعداد اندازه‌گیری‌شده", brief_html)))
        n += 1

    # -- the rest of the AI's own, niche-specific sections -------------------
    for sec in remaining_ai_sections:
        body = _deep_render_section_body(sec)
        if not body:
            continue
        sections.append((sec["title"], _deep_sec(n, sec.get("kicker") or "", sec["title"], body)))
        n += 1

    if not ai_sections:
        # The model returned nothing usable — surface that honestly instead
        # of silently showing a half-empty report.
        inner = (
            '<p class="lead">تحلیل هوش مصنوعی برای این بخش برنگشت — احتمالاً یک خطای موقت در پاسخ '
            'مدل بوده. آمار واقعی بالا همچنان معتبر است؛ برای گرفتن بخش‌های تحلیلی، «تحلیل عمیق» را '
            'دوباره امتحان کنید.</p>'
        )
        sections.append(("یادداشت", _deep_sec(n, "یادداشت", "تحلیل روایی در دسترس نبود", inner)))
        n += 1

    # -- methodology (fixed, always last) ------------------------------------
    research_line = (
        ' این گزارش علاوه بر داده‌ی خام، از یک جست‌وجوی وب کوتاه برای شناخت روندهای رایج در حوزه‌ی '
        'این کانال نیز کمک گرفته است.'
    ) if used_web_research else ""
    # State HOW the videos were watched, not just how many. A reader who knows a
    # long video was sampled between minutes 2 and 10 can judge which claims the
    # report is entitled to make — the previous line said "watched directly" for
    # both cases, which overstated the long-form evidence.
    watch_line = (
        f' هم‌چنین {watched_videos} ویدیوی برترِ همین کانال به‌طور مستقیم تماشا شده — '
        'ویدیوهای شورت به‌طور کامل و ویدیوهای بلند در بازه‌ی '
        f'دقیقه‌ی {WATCH_LONG_START_SECONDS // 60} تا {WATCH_LONG_END_SECONDS // 60} — '
        'و مشاهده‌های مربوط به هوک، ساختار، ریتم تدوین و کیفیت تولید بر پایه‌ی همان تماشا '
        'نوشته شده‌اند.'
    ) if watched_videos else ""
    # Name the snapshot research as a separate, differently-sourced body of
    # evidence. A reader who cannot tell which numbers came from their own export
    # and which from other people's videos cannot use either safely.
    brief_line = ""
    measured_briefs = [r for r in (briefs or [])
                       if isinstance(r, dict)
                       and isinstance(r.get("analytics"), dict)
                       and r["analytics"].get("total_videos")]
    if measured_briefs:
        queries = "، ".join(
            "«%s»" % e((r.get("query") or "").strip() or tr("Untitled"))
            for r in measured_briefs[:4])
        brief_line = (
            f' بخش «تحقیق نیچ» از {len(measured_briefs)} مجموعه‌ی جست‌وجوی ذخیره‌شده '
            f'({queries}) می‌آید: آن اعداد هم مثل بقیه در پایتون از ردیف‌های واقعی '
            'محاسبه شده‌اند، اما مربوط به ویدیوهای کانال‌های دیگر در همین نیچ هستند، '
            'نه کانال خودتان.')
    inner = (
        f'<p class="lead">این گزارش به‌صورت خودکار از {ctx["n"]} ردیفِ واقعیِ فایل «{e(filename)}» ساخته شده: '
        'آمارها (بازدید، لایک، کامنت، طول، تاریخ انتشار) مستقیماً از همین فایل محاسبه شده‌اند و توسط هوش '
        f'مصنوعی تولید نشده‌اند؛ تحلیل‌های روایی و ایده‌ها توسط {e(provider_label)} نوشته شده.'
        f'{research_line}{watch_line}{brief_line}</p>'
    )
    sections.append(("شفافیت", _deep_sec(n, "روش", "روش‌شناسی این گزارش", inner)))
    n += 1

    nav_html = "".join(f'<a href="#s{i + 1}">{e(label)}</a>' for i, (label, _h) in enumerate(sections))
    sections_html = "".join(html_ for _l, html_ in sections)

    theme_colors = _deep_theme_colors(ai.get("theme_primary"), ai.get("theme_secondary"))
    # The colours come from the AI; the SHAPE of the page follows the subject
    # (see the skins section). `style_key` also goes onto <html> so the whole
    # sheet can be scoped to it, and so a saved report can be told apart.
    style_key = _deep_style_key(ai)
    theme_css = (_deep_theme_root_css(theme_colors) + _DEEP_REPORT_CSS
                 + _deep_style_css(style_key))

    doc = (
        '<!doctype html><html lang="fa" dir="rtl" data-style="%s"><head><meta charset="utf-8">'
        % style_key +
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'{_favicon_link_tag()}'
        f'<title>{hero_title}</title>'
        '<link rel="preconnect" href="https://fonts.googleapis.com">'
        '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
        '<link href="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@400;500;700;900&display=swap" rel="stylesheet">'
        f'<style>{theme_css}</style>'
        '</head><body>'
        '<div class="progress"></div>'
        '<div class="topbar">'
        f'<div class="tb-brand">گزارش عمیق · <span>{e(filename)}</span></div>'
        f'<div class="tb-nav">{nav_html}</div>'
        '<div class="tb-actions">'
        '<button type="button" class="tb-btn" id="themeToggle" aria-label="تغییر تم">'
        '<span class="tb-ic" id="themeIcon">☀️</span><span class="tb-btn-label" id="themeLabel">تم روشن</span></button>'
        '<button type="button" class="tb-btn tb-btn-accent" id="printBtn" aria-label="چاپ">'
        '<span class="tb-ic">🖨️</span><span class="tb-btn-label">چاپ / PDF</span></button>'
        '</div></div>'
        + hero_html
        + sections_html
        + '<div class="endcap">پایان گزارش · تولیدشده توسط دستیار هوش مصنوعی درون برنامه ⚡</div>'
        + f'<script>{_DEEP_REPORT_JS}</script>'
        + '</body></html>'
    )
    return doc


def generate_deep_analysis_html(filename, path, ai_client, watch_videos=None,
                                progress_cb=None):
    """Runs on a worker thread via run_ai_task. Reads the export, gathers a
    web-research briefing and watches the channel's best videos (both Gemini
    only), asks the AI to design and write the report's own sections, and
    renders + saves a self-contained HTML report. Returns the on-disk path of
    the new report.

    Video watching is not optional any more: for a Google-shape client it always
    runs, split by length (Shorts whole, long-form clipped — see _watch_plan). It
    is what separates a report written from numbers from one written from what the
    videos actually do, and the old "off by default" setting meant most reports
    were the weaker kind. `watch_videos` is accepted and ignored so an older
    caller doesn't break.
    """
    rows = _read_export_rows(path)
    if not rows:
        raise RuntimeError(tr("Couldn't read any rows from this export file."))
    ctx = _deep_analysis_build_context(filename, rows)
    if ctx is None:
        raise RuntimeError(tr("This export doesn't have enough data for a deep report."))

    is_gemini = _is_google_shape(ai_client)
    research_briefing = ""
    if is_gemini:
        research_briefing = _gemini_search_briefing(
            ai_client, _deep_analysis_research_prompt(ctx["overview_text"]))
    used_web_research = bool(research_briefing)

    watch_briefing, watched = "", 0
    if is_gemini:
        watch_briefing, watched = _gemini_watch_briefing(
            ai_client, ctx["watch_pool"], progress_cb)

    if progress_cb:
        progress_cb(tr("Computing data-driven insights …"))
    # Compute verdicts and actionable insights from real data
    insights = compute_insights(ctx)
    insights_html = render_insights(insights) if insights else ""

    if progress_cb:
        progress_cb(tr("Writing the report …"))
    prompt = _deep_analysis_prompt(filename, ctx["overview_text"], ctx["n"],
                                   research_briefing, watch_briefing)
    raw = ai_client.generate(prompt, timeout=240, max_output_tokens=7000)
    ai = _deep_analysis_parse_response(raw)
    provider_label = AI_PROVIDER_LABELS.get(ai_client.provider, ai_client.provider)
    html_doc = render_deep_analysis_html(ctx, ai, filename, provider_label,
                                         used_web_research, watched, insights_html=insights_html)

    safe_name = re.sub(r"[^\w\-]+", "_", os.path.splitext(filename)[0]).strip("_") or "report"
    out_name = f"{safe_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
    out_path = os.path.join(_get_deep_analysis_dir(), out_name)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html_doc)

    save_deep_analysis(path, out_path)
    record_deep_report(path, out_path, kind="channel", provider=provider_label,
                       watched=watched, video_count=ctx["n"])
    return out_path


# ═════════════════════════════════════════════════════════════════════════
#  COMBINED REPORT  —  the channel deep-report PLUS a dedicated, sharpened
#  section per saved Content Lab blueprint the user ticked, and/or the
#  demand-side evidence from a Niche Scan brief. The channel analysis is
#  identical to generate_deep_analysis_html (real numbers, AI free-form niche
#  sections, niche-matched theme, A4 print CSS); the extra "blueprint" sections
#  rewrite each stored idea against THIS channel's real patterns rather than
#  reprinting it. Reachable from the Content Lab channel-report tab.
# ═════════════════════════════════════════════════════════════════════════
def _brief_measured_block(record):
    """The MEASURED half of one Niche Scan brief, as prose.

    This is the half that was missing. `_brief_context` used to carry only the
    model-written part of a brief (its summary, its labelled claims, its
    proposed experiments) and nothing else, so the report never saw the
    deterministic aggregates the brief was itself derived FROM — the median vs
    average split, age-normalised momentum, the length and recency mix, how
    concentrated the niche's channels are, the recurring terms, coverage. Those
    are the most trustworthy numbers in the whole feature: they are measured off
    real rows by app.core.analysis.snapshot, not written by anything.

    app.core.ai.insights._overview_block already renders exactly that, with the
    guardrails attached in the same breath ("the average is 4.1× the median, so
    read the median", "this is not engagement and neither is public data"), and
    it is the text the Insights brief itself was generated against. Reused
    verbatim rather than reimplemented, so the report and the brief cannot drift
    into describing the same snapshot differently.

    Returns "" for a record with no usable analytics — an older row, or one
    stored before a field existed — rather than raising: a brief that can only
    contribute its narrative is still worth carrying.
    """
    analytics = record.get("analytics") if isinstance(record, dict) else None
    if not isinstance(analytics, dict) or not analytics.get("total_videos"):
        return ""
    try:
        from app.core.ai.insights import _overview_block
        # `_overview_block` indexes a handful of keys directly (it was written
        # against a live build_snapshot result, where they always exist). A row
        # stored by an older build, or one whose analytics were saved from a
        # different code path, can be missing them — and a KeyError here would
        # silently cost the report its whole measured block. So the gaps are
        # filled from the record itself before the call.
        snap = dict(analytics)
        snap.setdefault("query", (record.get("query") or "").strip())
        snap.setdefault("mode", record.get("mode") or "keyword")
        snap.setdefault("shorts", 0)
        snap.setdefault("long_form", max(0, int(snap.get("total_videos") or 0)))
        snap.setdefault("coverage", {})
        for key in ("views", "interaction", "subscribers", "duration",
                    "published", "tags", "captions"):
            snap["coverage"].setdefault(key, 0)
        snap.setdefault("interaction_rows", 0)
        snap.setdefault("unique_channels", 0)
        return _overview_block(snap)
    except Exception:      # noqa: BLE001 — a partial snapshot is not a failure
        return ""


def _brief_context(briefs):
    """Text digest of the selected Niche Scan briefs for the prompt.

    Each brief contributes TWO things, in this order and clearly separated:

      MEASURED — the deterministic aggregates from app.core.analysis.snapshot
                 (see _brief_measured_block). Real numbers off real rows.
      WRITTEN  — the AI brief over those numbers, every statement still carrying
                 its evidence class.

    Three things make this different from the blueprint digest, and all of them
    matter:

    1. It is about a DIFFERENT CHANNEL SET. A brief reads a search result — other
       people's videos — while the export is this creator's own channel. So it is
       introduced as demand-side evidence about the niche, never as data about
       the channel, or the model will start quoting a competitor's numbers as if
       they were the creator's.

    2. EVERY CLAIM CARRIES ITS EVIDENCE CLASS. The whole Insights feature rests
       on labelling each statement observed / inferred / requires_studio (see
       app.core.ai.insights), and stripping those labels here would hand the
       model a pile of confident-looking assertions, half of which are guesses.
       The labels ride along verbatim and the prompt tells the model to respect
       them.

    3. A BRIEF WITH NO AI HALF STILL COUNTS. The measured aggregates exist the
       moment a snapshot is taken, with no AI call at all, so a brief the user
       never generated (or one whose generation failed) is still real evidence
       about the niche and is carried on its numbers alone.

    `briefs` is a list of the dicts app.core.db.insights.insights_get returns.
    """
    out = []
    for i, record in enumerate(briefs or [], 1):
        if not isinstance(record, dict):
            continue
        ai = record.get("ai") if isinstance(record.get("ai"), dict) else {}
        measured = _brief_measured_block(record)
        if not ai and not measured:
            continue
        analytics = (record.get("analytics")
                     if isinstance(record.get("analytics"), dict) else {})
        query = (record.get("query") or "").strip() or tr("Untitled")
        lines = ['BRIEF %d — research on the search "%s" (%d videos, %s)' % (
            i, query, int(analytics.get("total_videos") or 0),
            record.get("mode") or "keyword")]

        if measured:
            lines.append("  MEASURED IN THAT SEARCH (computed from the real "
                         "rows, not written by a model — you may quote these "
                         "numbers as facts about the NICHE):")
            lines.extend("    " + ln for ln in measured.splitlines() if ln.strip())

        if ai:
            lines.append("  WRITTEN ANALYSIS of that search:")
        if ai.get("summary"):
            lines.append("  summary: %s" % ai["summary"])
        intent = ai.get("intent") if isinstance(ai.get("intent"), dict) else {}
        for key in ("job", "viewer", "surface", "promise"):
            if intent.get(key):
                lines.append("  viewer %s: %s" % (key, intent[key]))
        for label, key in (("OBSERVED in that search", "observed"),
                           ("INFERRED (hypothesis, not measured)", "inferred"),
                           ("UNKNOWABLE without the owner's Studio", "requires_studio")):
            items = [str(x).strip() for x in (ai.get(key) or []) if str(x).strip()]
            for item in items[:4]:
                lines.append("  [%s] %s" % (label, item))
        for q in (ai.get("audience_questions") or [])[:5]:
            if isinstance(q, dict) and q.get("question"):
                lines.append("  audience question: %s → %s" % (
                    q["question"], q.get("answer", "")))
        for op in (ai.get("opportunities") or [])[:4]:
            if isinstance(op, dict) and op.get("hypothesis"):
                lines.append("  opportunity (unproven): %s | evidence: %s | risk: %s" % (
                    op["hypothesis"], op.get("evidence", ""), op.get("risk", "")))
        for ex in (ai.get("experiments") or [])[:3]:
            if isinstance(ex, dict) and ex.get("title"):
                lines.append("  proposed test: %s | expects: %s | one variable: %s" % (
                    ex["title"], ex.get("hypothesis", ""), ex.get("variable", "")))
        for limit in (ai.get("limits") or [])[:5]:
            if str(limit).strip():
                lines.append("  known limit of this research: %s" % limit)
        out.append("\n".join(lines))
    return "\n\n".join(out)


def _combined_blueprint_context(blueprints):
    """Text digest of the selected blueprints for the prompt.

    The stored ideas are deeply nested (see app.core.ai.content_lab), so this
    flattens each into labelled lines. It carries the WHOLE idea rather than a
    summary on purpose: the model is being asked to SHARPEN each blueprint against
    the channel's data, and it can only improve on what it was shown — an earlier
    version passed title/angle/hook/timing plus three script beats, and the
    "improved" sections that came back kept reinventing details the blueprint had
    already decided. app/qml_backend/vm/_idea_shape.py is the canonical list of
    what a blueprint contains.
    """
    out = []
    for i, bp in enumerate(blueprints or [], 1):
        if not isinstance(bp, dict):
            continue
        fmt = "long-form" if (bp.get("format") == "long") else "short-form"
        angle = bp.get("viral_angle") if isinstance(bp.get("viral_angle"), dict) else {}
        hook = bp.get("hook") if isinstance(bp.get("hook"), dict) else {}
        anti = bp.get("anti_hook") if isinstance(bp.get("anti_hook"), dict) else {}
        pack = bp.get("packaging") if isinstance(bp.get("packaging"), dict) else {}
        seo = bp.get("seo") if isinstance(bp.get("seo"), dict) else {}
        ret = bp.get("retention") if isinstance(bp.get("retention"), dict) else {}
        exe = bp.get("execution") if isinstance(bp.get("execution"), dict) else {}

        def _all(v, limit=3):
            """A field that may be a list (schema v2+) or a bare string (v1)."""
            if isinstance(v, (list, tuple)):
                items = [str(x).strip() for x in v if str(x).strip()]
            else:
                items = [str(v).strip()] if v else []
            return " | ".join(items[:limit])

        lines = [f'BLUEPRINT {i} — "{bp.get("title", "") or "Untitled"}" ({fmt})']
        if angle.get("concept"):
            lines.append(f'  angle: {angle["concept"]}')
        if _all(angle.get("triggers"), 5):
            lines.append(f'  psychological triggers: {_all(angle.get("triggers"), 5)}')
        spoken = _all(hook.get("text"), 2) or str(bp.get("hook_preview") or "")
        if spoken:
            lines.append(f'  current spoken hook: {spoken}')
        if _all(hook.get("visual"), 2):
            lines.append(f'  current visual hook: {_all(hook.get("visual"), 2)}')
        if _all(anti.get("options"), 2):
            lines.append(f'  current anti-hook: {_all(anti.get("options"), 2)}')
        if _all(bp.get("titles"), 4):
            lines.append(f'  current titles: {_all(bp.get("titles"), 4)}')
        thumbs = bp.get("thumbnails") if isinstance(bp.get("thumbnails"), list) else []
        prompts = [str(t.get("prompt", "")).strip() for t in thumbs
                   if isinstance(t, dict) and t.get("prompt")]
        if not prompts and bp.get("thumbnail_prompt"):
            prompts = [str(bp["thumbnail_prompt"])]
        if prompts:
            lines.append(f'  current thumbnail prompt: {prompts[0]}')
        if pack.get("framework"):
            lines.append(f'  title framework: {pack["framework"]}')
        if pack.get("timing"):
            lines.append(f'  intended timing: {pack["timing"]}')
        if _all(bp.get("cta_options"), 2):
            lines.append(f'  current CTA: {_all(bp.get("cta_options"), 2)}')
        phases = ret.get("phases") if isinstance(ret.get("phases"), list) else []
        if phases:
            beats = "; ".join(
                "%s@%s%%" % (p.get("label", ""), p.get("end_pct", ""))
                for p in phases[:6] if isinstance(p, dict))
            lines.append(f'  planned retention phases: {beats}')
        if _all(seo.get("keywords"), 8):
            lines.append(f'  planned SEO keywords: {_all(seo.get("keywords"), 8)}')
        if exe:
            bits = "; ".join(f"{k}: {v}" for k, v in list(exe.items())[:4] if v)
            if bits:
                lines.append(f'  execution notes: {bits}')
        script = bp.get("full_script") if isinstance(bp.get("full_script"), list) else []
        if script:
            beats = "; ".join(str(s.get("line", "")) for s in script[:5]
                              if isinstance(s, dict))
            if beats:
                lines.append(f'  opening script beats: {beats}')
        out.append("\n".join(lines))
    return "\n\n".join(out)


def _combined_analysis_prompt(filename, overview_text, n_videos, has_blueprints=False,
                              research_briefing="", watch_briefing="",
                              brief_block=""):
    """Like _deep_analysis_prompt, but (a) lets the section count scale with how
    much data the channel has, and (b) can carry the creator's own Snapshot
    Insights research as demand-side evidence.

    It does NOT ask for the blueprint sections. Those used to ride along in this
    same reply, which made the combined report the longest single generation in
    the app — a dozen-plus channel sections PLUS a full shoot-ready blueprint per
    picked idea — and a reply that long is exactly what gets cut off mid-JSON or
    dropped by an aggregator mid-stream. They now come from their own call
    (_blueprint_sections_prompt) with its own token budget, so neither half can
    starve the other and a failure in one still leaves the other. `has_blueprints`
    only tells the model that they exist, so it doesn't write one itself.

    `brief_block` comes from _brief_context and is deliberately framed as
    evidence about OTHER channels in the niche. The channel export says what this
    creator's audience already does; a brief says what the wider search demand
    looks like. Merging the two without saying which is which is how a report
    ends up quoting a competitor's view count as the creator's own.
    """
    research_block = ""
    if research_briefing:
        research_block = (
            "\n\nA short research briefing on current trends in this "
            "channel's specific niche is below (gathered separately via live "
            "web search). Weave concrete insights from it into your sections "
            f"where they fit, without repeating it verbatim:\n\n{research_briefing}\n"
        )
    insights_block = ""
    if brief_block:
        insights_block = (
            "\n\nThe creator also ran their own research on YouTube SEARCH RESULTS "
            "in this niche — other people's videos, not their own channel — and the "
            "brief(s) below are what that produced. Read them as DEMAND-SIDE "
            "evidence about the niche, never as data about this channel: no number "
            "in them describes the channel whose export you are analysing.\n\n"
            "Each statement is labelled, and the labels are binding:\n"
            "  [OBSERVED in that search]  — measured in those search results. You "
            "may rely on it, but attribute it to the niche, not to this channel.\n"
            "  [INFERRED …]               — a hypothesis. Repeat it AS a hypothesis "
            "or not at all. Never promote it to a fact.\n"
            "  [UNKNOWABLE …]             — cannot be known from public data. Do "
            "not answer it; if it matters, say what would settle it.\n"
            "An \"opportunity (unproven)\" is a gap the creator SUSPECTS exists; "
            "treat it as something to test against this channel's real numbers, and "
            "say plainly where the channel's own data supports or contradicts it. "
            "Where a brief and the export disagree, the export wins — it is this "
            f"creator's actual audience.\n\n{brief_block}\n"
        )
    watch_block = ""
    if watch_briefing:
        watch_block = (
            "\n\nThe channel's best-performing videos were then WATCHED, and the "
            "notes below describe what each actually does on screen. Each block is "
            "labelled with what was watched: a SHORT was watched end to end, while "
            "a LONG-FORM entry was watched only across the stated minute range, so "
            "do not claim anything about a long video's opening seconds or ending "
            "from these notes. Treat this as first-hand evidence and prefer it over "
            "anything inferred from titles and numbers alone — both for the channel "
            "sections and when sharpening each blueprint. Where a channel runs both "
            "formats, keep the two playbooks distinct rather than averaging their "
            f"pacing advice together:\n\n{watch_briefing}\n"
        )
    # A briefs-only run reaches this same function (the report still needs the
    # demand-side framing above) and must not be told to write blueprint
    # sections — those are generated by their own call now, see
    # _blueprint_sections_prompt. Telling one call to do both is what produced a
    # reply long enough to be cut off mid-JSON.
    blueprint_rules = (
        "The LAST section must use layout \"takes\" (4-6 one-line takeaways). "
        "Do NOT use the \"blueprint\" layout at all — no blueprint was "
        "provided, and inventing one would put an idea the creator never "
        "wrote in front of them as if they had. ")
    if has_blueprints:
        blueprint_rules = (
            "The LAST section must use layout \"takes\" (4-6 one-line "
            "takeaways). Do NOT use the \"blueprint\" layout at all — the "
            "creator's own saved blueprints are being written up separately and "
            "will be appended after your sections, so writing one here would "
            "duplicate that work. Do write your channel sections knowing those "
            "ideas are coming: the patterns you identify are what they will be "
            "sharpened against. ")

    return (
        "You are a senior YouTube growth strategist writing an in-depth, "
        "tailored report for a content creator. Below is a real, numbers-backed "
        f"digest of an export of {n_videos} videos from a YouTube channel "
        "scrape (titles, views, likes, comments, duration, publish dates, and "
        "transcript excerpts where available).\n\n"
        f"{overview_text}"
        f"{research_block}"
        f"{insights_block}"
        f"{watch_block}\n\n"
        "First, work out exactly what topic/niche this specific channel covers "
        "from the data above — it could be anything at all (cooking, gaming, "
        "real estate, tech reviews, comedy sketches, tutorials, vlogging, "
        "fitness…). Then design a report made ONLY of sections genuinely "
        "relevant to THIS channel's actual niche and data. Do not use a generic "
        "one-size-fits-all template — skip any topic that wouldn't meaningfully "
        "help this creator, and add niche-specific sections that would.\n\n"
        "Also choose a visual theme that matches this niche's mood: one emoji "
        "(hero_emoji) that represents it, two vivid hex accent colors "
        "(theme_primary, theme_secondary) saturated enough to glow on a "
        "near-black background — pick shades that genuinely fit THIS channel "
        "(warm orange/red for food, cool blue/cyan for tech, purple/magenta for "
        "gaming, green/teal for finance, gold/navy for real estate/luxury, "
        "pink/gold for beauty — but choose your own exact shades) — and a "
        "theme_style for the SHAPE of the page, which must be exactly one of: "
        "sport, fitness, tech, gaming, food, beauty, finance, education, music, "
        "travel, nature, luxury, kids, news, auto, entertainment, health, diy, "
        "default. A sports channel gets sport, a cooking channel food, a coding "
        "channel tech, a money channel finance, a toy channel kids — default "
        "only when nothing on the list genuinely fits.\n\n"
        "Respond in Persian (Farsi), and respond ONLY with a single JSON object "
        "(no markdown fences, no commentary before or after) shaped exactly like "
        f"this:\n{_DEEP_ANALYSIS_JSON_SCHEMA}\n\n"
        "Rules: choose as many channel sections as the data genuinely supports "
        "(typically 6 to 16, more for a larger channel with more videos) — never "
        "padded to hit a number and never trimmed below what the data supports. "
        "The FIRST section must use layout \"lead_pillars\" or \"lead_points\" as "
        "an executive summary. Include at least one \"dos_donts\" section. "
        "Include exactly one \"ideas\" section of 3-5 FRESH video ideas that are "
        "NOT reprints of the creator's saved blueprints (those are written up "
        "separately and appended after your sections) — synthesise them "
        "from all three sources together: this channel's real numbers above, "
        "the demand-side evidence in the brief block (what the wider niche is "
        "searching for), and what the watched videos actually do on screen. "
        "Write EVERY fresh idea as a complete mini-blueprint in the same shape "
        "as the saved ones: title_structure, spoken hook, visual_hook, one "
        "anti_hook alternative, thumbnail_prompt (EN), a 3-4 beat outline and "
        "2-3 retention beats. Give EVERY fresh idea a \"viral_pct\" "
        "(0-100: its viral potential on THIS channel) plus a \"why\" line citing "
        "what the estimate rests on — similar videos' real views on this "
        "channel, demand signals from the briefs, format fit — and never present "
        "it as a guarantee. Ground every thumbnail_prompt in what the watched "
        "videos actually show (close-up faces, big on-screen captions, "
        "high-contrast decisive moments), not generic advice. "
        f"{blueprint_rules}"
        "Only fill fields that match "
        "each section's own \"layout\". Every string value must be in Persian — "
        "only the JSON keys, the \"layout\" values and \"thumbnail_prompt\" stay "
        "in English. Keep every "
        "point, step or paragraph to 1-3 sentences."
    )


_BLUEPRINT_SECTIONS_JSON_SCHEMA = '''{
  "sections": [
    {
      "kicker": "برچسب کوتاه بالای عنوان بخش",
      "title": "نام همین ایده",
      "layout": "blueprint",
      "bp_title": "...", "improved_titles": ["...", "..."],
      "improved_hook": "...", "visual_hook": "...", "anti_hook": "...",
      "outline": [{"title": "...", "desc": "..."}],
      "thumbnail_prompt": "...", "thumbnail_direction": "...",
      "retention_beats": [{"time": "0:45", "risk": "...", "fix": "..."}],
      "seo_keywords": ["...", "..."], "seo_description": "...",
      "first_comment": "...", "why_fits": "...", "viral_pct": 0,
      "viral_why": "...",
      "publish_plan": {"day": "...", "time": "...", "why": "...",
                       "first_hour": ["...", "..."]},
      "success_metrics": [{"metric": "...", "target": "...", "why": "..."}],
      "risks": [{"risk": "...", "fix": "..."}],
      "series_next": [{"title": "...", "why": "..."}]
    }
  ]
}'''


def _blueprint_fallback_sections(blueprints, ctx):
    """Deterministic blueprint sections when the AI sharpening call fails.

    The old (single-call) combined report always showed the creator's own
    blueprints; the split two-call version can ship zero blueprint sections
    when the second call truncates or mis-labels its layout — exactly the
    regression users reported ("old output used my blueprint data"). This
    fallback reprints each stored blueprint verbatim (titles, hooks, visual,
    anti-hook, outline, thumbnail, retention, SEO, comment) enriched with the
    channel's CURRENT numbers (avg/median/top + best weekday) and a viral_pct
    meter, so a combined report never loses the blueprints even when the model
    gives nothing back.
    """
    def _as_list(v):
        if isinstance(v, (list, tuple)):
            return [str(x).strip() for x in v if str(x).strip()]
        s = str(v or "").strip()
        return [s] if s else []
    avg = humanize_count(ctx.get("avg_views", 0)) if ctx else ""
    median = humanize_count(ctx.get("median_views", 0)) if ctx else ""
    top = ctx.get("top_video") if isinstance(ctx, dict) else None
    top_txt = f'{top.get("title", "")} ({humanize_count(top.get("views", 0))})' if isinstance(top, dict) else ""
    wd = ""
    try:
        charts = (ctx.get("weekday_chart") or []) if isinstance(ctx, dict) else []
        if charts:
            best = max(charts, key=lambda c: c.get("avg", 0))
            wd = best.get("label", "")
    except Exception:
        wd = ""
    out = []
    for bp in (blueprints or []):
        if not isinstance(bp, dict):
            continue
        title = str(bp.get("title") or "").strip() or "بلوپرینت بدون عنوان"
        angle = bp.get("viral_angle") if isinstance(bp.get("viral_angle"), dict) else {}
        hook = bp.get("hook") if isinstance(bp.get("hook"), dict) else {}
        anti = bp.get("anti_hook") if isinstance(bp.get("anti_hook"), dict) else {}
        seo = bp.get("seo") if isinstance(bp.get("seo"), dict) else {}
        ret = bp.get("retention") if isinstance(bp.get("retention"), dict) else {}
        titles = _as_list(bp.get("titles"))[:5]
        hook_text = _as_list(hook.get("text"))[:2]
        hook_vis = _as_list(hook.get("visual"))[:2]
        anti_opts = _as_list(anti.get("options"))[:2]
        thumbs = bp.get("thumbnails") if isinstance(bp.get("thumbnails"), list) else []
        thumb_prompt = ""
        for t in thumbs:
            if isinstance(t, dict) and str(t.get("prompt") or "").strip():
                thumb_prompt = str(t["prompt"]).strip()
                break
        if not thumb_prompt:
            thumb_prompt = str(bp.get("thumbnail_prompt") or "").strip()
        seo_kw = _as_list(seo.get("keywords"))[:12] or _as_list(seo.get("tags"))[:12]
        seo_desc = str(seo.get("description") or "").strip()
        phases = ret.get("phases") if isinstance(ret.get("phases"), list) else []
        outline, beats = [], []
        for p in phases[:8]:
            if not isinstance(p, dict):
                continue
            label = str(p.get("label") or "").strip()
            desc = str(p.get("desc") or str(p.get("reasoning") or "")).strip()
            if label or desc:
                outline.append({"title": label or "بخش", "desc": desc})
        script = bp.get("full_script") if isinstance(bp.get("full_script"), list) else []
        if not outline and script:
            for s in script[:6]:
                if isinstance(s, dict) and str(s.get("line") or "").strip():
                    outline.append({"title": str(s.get("time") or s.get("speaker") or "بیت"), "desc": str(s["line"]).strip()})
        # retention beats: reuse phases with generic risk/fix when missing
        for i, p in enumerate(phases[:6]):
            if not isinstance(p, dict):
                continue
            try:
                total = int(ret.get("total_seconds", 60) or 60)
                end_pct = float(p.get("end_pct", 0) or 0)
                mm = int(total * end_pct / 100.0)
                t = f"{mm // 60}:{mm % 60:02d}"
            except Exception:
                t = f"0:{i * 5:02d}"
            beats.append({"time": t,
                          "risk": str(p.get("label") or "افت توجه")[:120],
                          "fix": str(p.get("desc") or "حفظ ریتم با کات سریع و متن روی تصویر")[:200]})
        try:
            score = int(float(bp.get("score", 0) or 0))
        except Exception:
            score = 0
        viral = max(0, min(100, score)) if score else 78
        why_bits = []
        if avg:
            why_bits.append(f"میانگین کانال {avg} بازدید است")
        if median:
            why_bits.append(f"میانه {median}")
        if top_txt:
            why_bits.append(f"پربازدیدترین «{top_txt}»")
        if wd:
            why_bits.append(f"بهترین روز انتشار {wd}")
        why_fits = ("؛ ".join(why_bits) + f". این بلوپرینت از داده‌ی همین کانال sharpen نشده (تماس دوم ناموفق بود) و با اعداد فعلی غنی شده — درصد وایرال {viral}٪ برآوردی از تناسب فرمت و سوژه با همین میانگین‌هاست، نه تضمین."
                    if why_bits else f"درصد وایرال {viral}٪ برآوردی است، نه تضمین.")
        out.append({
            "kicker": "بلوپرینت شما + داده‌ی فعلی کانال",
            "title": title,
            "layout": "blueprint",
            "lead": "",
            "pillars": [], "points": [], "steps": [], "dos": [], "donts": [],
            "takeaways": [], "closing_note": "",
            "ideas": [],
            "callout_icon": "◆", "callout_title": "", "callout_text": "",
            "bp_title": str(angle.get("concept") or title),
            "improved_titles": titles or [title],
            "improved_hook": hook_text[0] if hook_text else str(bp.get("hook_preview") or ""),
            "visual_hook": hook_vis[0] if hook_vis else "",
            "anti_hook": anti_opts[0] if anti_opts else "",
            "outline": outline[:8],
            "thumbnail_prompt": thumb_prompt,
            "thumbnail_direction": "از پرامپت ذخیره‌شده‌ی خودتان — آماده‌ی تولید تصویر.",
            "retention_beats": beats[:6],
            "seo_keywords": seo_kw,
            "seo_description": seo_desc,
            "first_comment": "",
            "why_fits": why_fits,
            "viral_pct": viral,
            # The parts of the working-creator pack that need no AI: the upload
            # day is read straight off the channel's own weekday chart, and the
            # 48-hour target is its own average. The other three (viral_why,
            # risks, series_next) need reasoning, so a fallback that cannot
            # reason leaves them out rather than padding them with filler.
            "publish_plan": ({"day": wd, "time": "",
                              "why": "از نمودار روزِ انتشار همین کانال — بهترین میانگین بازدید آن روز است.",
                              "first_hour": []} if wd else {}),
            "success_metrics": ([{"metric": "بازدید در ۴۸ ساعت",
                                  "target": avg,
                                  "why": "رسیدن به میانگین کانال یعنی این ویدیو حداقل هم‌سطح بقیهٔ کارها عمل کرده است."}]
                                if avg else []),
            # These three need reasoning, which a fallback cannot do honestly.
            # Present as keys (empty) rather than absent, so nothing downstream
            # has to wonder whether the field exists.
            "viral_why": "",
            "risks": [],
            "series_next": [],
        })
    return out


def _blueprint_sections_prompt(overview_text, blueprint_block, n_blueprints,
                               watch_briefing=""):
    """The second call of a combined report: ONE sharpened section per saved
    blueprint, and nothing else.

    Split out of _combined_analysis_prompt because the two asks have very
    different sizes and the small one was losing. A blueprint section is a
    complete shoot document — titles, both hooks, an anti-hook, an outline, a
    thumbnail prompt, timed retention beats, SEO, a pinned comment — so six of
    them is more output than the entire channel analysis. Asked for together,
    the reply ran past the output ceiling and the whole document failed to
    parse; asked separately, each half fits and each half can succeed alone.

    The channel digest still rides along: sharpening an idea against "this
    channel's real data" is meaningless without the data.
    """
    watch_block = ""
    if watch_briefing:
        watch_block = (
            "\n\nThe channel's best videos were WATCHED and these notes describe "
            "what they actually do on screen. Prefer this first-hand evidence "
            "over anything inferred from titles and numbers when you write the "
            "hooks, the pacing and the retention beats. A SHORT was watched end "
            "to end; a LONG-FORM entry only across the stated minute range, so "
            "claim nothing about a long video's opening or ending from these "
            f"notes:\n\n{watch_briefing}\n"
        )
    return (
        "You are a senior YouTube growth strategist. A creator has drafted the "
        "video ideas below and wants each one SHARPENED against the real "
        "performance data of their own channel.\n\n"
        "THE CHANNEL'S REAL NUMBERS:\n"
        f"{overview_text}"
        f"{watch_block}\n\n"
        f"THE CREATOR'S SAVED BLUEPRINTS ({n_blueprints}):\n{blueprint_block}\n\n"
        "Write exactly one section per blueprint, in the order given, and "
        "nothing else — no channel analysis, no summary, no extra sections. Do "
        "NOT reprint a blueprint: rewrite it using what actually performs on "
        "THIS channel — the video length that wins here, the title words that "
        "work, the best upload day, and what the watched videos really do on "
        "screen. Every field must be BETTER than the one the blueprint already "
        "has; if you cannot improve a field, rewrite it to fit this channel's "
        "voice and data rather than copying it back verbatim. Each section is "
        "the document the creator will shoot from, so it must be complete "
        "enough to act on without opening anything else.\n\n"
        "Fill exactly these fields per section:\n"
        "- \"kicker\", \"title\" (name the idea), \"layout\":\"blueprint\"\n"
        "- \"bp_title\": the sharpened idea in one line\n"
        "- \"improved_titles\": 3-5 rewritten titles tuned to this channel, "
        "ordered so the first is the one you would publish\n"
        "- \"improved_hook\": the strongest SPOKEN opening line, written as it "
        "would be said out loud in the first 3 seconds\n"
        "- \"visual_hook\": what is ON SCREEN during those same 3 seconds — the "
        "frame, the movement, the text overlay. Never repeat improved_hook here\n"
        "- \"anti_hook\": one reverse-psychology opener (telling the viewer NOT "
        "to watch, or that this is not for them) as an alternative to test\n"
        "- \"outline\": 4-8 {\"title\",\"desc\"} beats or chapters covering the "
        "whole video, not only its start\n"
        "- \"thumbnail_prompt\": a complete, vivid image-generation prompt "
        "(composition, subject, expression, lighting, colour, text placement) "
        "that could be pasted straight into an image model. Write this ONE "
        "field in ENGLISH — it is consumed by a tool, not read by the creator\n"
        "- \"thumbnail_direction\": one Persian line explaining the thumbnail "
        "choice, so the creator understands what they are looking at\n"
        "- \"retention_beats\": 3-6 {\"time\",\"risk\",\"fix\"} entries — "
        "\"time\" an MM:SS timestamp, \"risk\" why viewers leave there, \"fix\" "
        "the concrete thing to do about it\n"
        "- \"seo_keywords\": 6-12 search terms real viewers of THIS niche type\n"
        "- \"seo_description\": a ready-to-paste description opening (2-4 "
        "lines) that front-loads the keywords naturally\n"
        "- \"first_comment\": the pinned first comment, written to start a "
        "conversation rather than beg for one\n"
        "- \"why_fits\": why this works for THIS channel, citing its real "
        "numbers (this is the idea's \"why\" — name the videos, views or "
        "patterns it rests on)\n"
        "- \"viral_pct\": 0-100, this sharpened idea's viral potential on THIS "
        "channel. An estimate grounded in the numbers above, never a "
        "guarantee\n"
        # ── the five fields a working creator asks for and a report usually
        # does not carry: WHY it travels, WHEN to post it, WHAT to watch in the
        # first two days, WHAT would kill it, and WHAT comes next. All of them
        # are answerable from the digest above (the weekday chart gives the
        # upload day, the averages give the metric targets), which is what stops
        # them being generic advice.
        "- \"viral_why\": 2-3 sentences naming the MECHANISM by which this video "
        "travels — the specific emotion it triggers, who feels it, why that "
        "person shares or re-watches, and what the first 24 hours should look "
        "like. This is NOT the same as why_fits: why_fits says why the idea "
        "suits this channel, viral_why says why a stranger who has never heard "
        "of this channel would pass it on. Ground it in this channel's real "
        "numbers, and say plainly which part is a hypothesis\n"
        "- \"publish_plan\": {\"day\": the weekday this channel's own videos "
        "perform best on, \"time\": a concrete upload time, \"why\": one line "
        "citing the weekday/view pattern you used, \"first_hour\": 3-4 concrete "
        "things to do in the first hour after publishing (what to answer, what "
        "to pin, where to share, what to check)}. Use the channel's real "
        "weekday data, not generic \"post at 5pm\" advice\n"
        "- \"success_metrics\": 3-4 {\"metric\",\"target\",\"why\"} entries — "
        "the numbers to check in the first 48 hours and the value that means "
        "this is working. \"target\" must be derived from THIS channel's own "
        "averages (its typical views, its typical engagement rate), and "
        "\"metric\" names the thing to look at (click-through rate, average "
        "view duration, views in the first 24 hours, comments per 1,000 views, "
        "subscribers gained)\n"
        "- \"risks\": 2-4 {\"risk\",\"fix\"} entries — what would make THIS "
        "video underperform (the misleading title, the slow first minute, the "
        "thumbnail that repeats the last one, the topic the audience has "
        "already seen twice) and the concrete change that removes it. Not "
        "generic pitfalls\n"
        "- \"series_next\": 2-3 {\"title\",\"why\"} follow-up videos that keep "
        "the viewer who just watched this one — the next question that person "
        "asks, or the same format on an adjacent topic. \"why\" names the "
        "retention logic\n\n"
        "Respond in Persian (Farsi), and respond ONLY with a single JSON object "
        "(no markdown fences, no commentary before or after) shaped exactly "
        f"like this:\n{_BLUEPRINT_SECTIONS_JSON_SCHEMA}\n\n"
        "Only the JSON keys, the \"layout\" value and \"thumbnail_prompt\" stay "
        "in English; every other string is Persian."
    )


def generate_combined_report_html(filename, path, ai_client, blueprints,
                                  watch_videos=None, progress_cb=None,
                                  briefs=None):
    """Like generate_deep_analysis_html, but folds the creator's own material into
    the report: their selected saved blueprints as sharpened, channel-tuned
    sections, and/or their Niche Scan briefs as demand-side evidence about
    the niche. Cached under a key distinct from the plain channel report so the
    two never clobber each other for the same file. Returns the on-disk path of
    the new report.

    Either extra is optional and they compose — briefs alone still produce a
    richer report than the plain channel one, because the model gets research
    about what the niche's viewers are looking for alongside what this channel
    actually published.

    When blueprints ARE picked, the report takes TWO synthesis calls rather than
    one: the channel sections, then the blueprint sections. Together they are
    more output than a single reply can reliably carry, and the failure mode of
    asking for both at once was the worst one available — a truncated reply
    parsed as zero sections, so the user got real charts under a note saying the
    analysis was unavailable. Split, each half has its own budget and a failure
    in the second still ships the first.

    `watch_videos` is accepted and ignored — watching is unconditional for a
    Google-shape client now. See generate_deep_analysis_html.
    """
    if not blueprints and not briefs:
        return generate_deep_analysis_html(filename, path, ai_client,
                                           None, progress_cb)

    rows = _read_export_rows(path)
    if not rows:
        raise RuntimeError(tr("Couldn't read any rows from this export file."))
    ctx = _deep_analysis_build_context(filename, rows)
    if ctx is None:
        raise RuntimeError(tr("This export doesn't have enough data for a deep report."))

    is_gemini = _is_google_shape(ai_client)
    research_briefing = ""
    if is_gemini:
        research_briefing = _gemini_search_briefing(
            ai_client, _deep_analysis_research_prompt(ctx["overview_text"]))
    used_web_research = bool(research_briefing)

    watch_briefing, watched = "", 0
    if is_gemini:
        watch_briefing, watched = _gemini_watch_briefing(
            ai_client, ctx["watch_pool"], progress_cb)

    if progress_cb:
        progress_cb(tr("Computing data-driven insights …"))
    # Compute verdicts and actionable insights from real data
    insights = compute_insights(ctx)
    insights_html = render_insights(insights) if insights else ""

    if progress_cb:
        progress_cb(tr("Writing the report …"))
    brief_block = _brief_context(briefs)
    prompt = _combined_analysis_prompt(
        filename, ctx["overview_text"], ctx["n"], bool(blueprints),
        research_briefing, watch_briefing, brief_block)
    # A combined report's channel half is longer than the plain deep report's
    # (more sections, plus the demand-side brief to weave in), so it keeps the
    # bigger budget — but it no longer also carries the blueprint sections.
    raw = ai_client.generate(prompt, timeout=300, max_output_tokens=10000)
    ai = _deep_analysis_parse_response(raw)

    # ── second call: the blueprint sections, appended after the channel ones ──
    # Deliberately after the channel call and deliberately non-fatal: by this
    # point the expensive work (reading the export, the research briefing, the
    # video watching, the channel synthesis) is already paid for, and shipping a
    # complete channel report without the blueprint sections is far better than
    # raising and shipping nothing.
    if blueprints:
        if progress_cb:
            progress_cb(tr("Sharpening {n} blueprint(s) against this channel …")
                        .format(n=len(blueprints)))
        try:
            bp_prompt = _blueprint_sections_prompt(
                ctx["overview_text"], _combined_blueprint_context(blueprints),
                len(blueprints), watch_briefing)
            # Scaled per blueprint, the way generate_content_lab_ideas budgets
            # its own multi-idea call: each section is a full shoot document, so
            # a flat ceiling would truncate the last ones in a six-idea run.
            bp_tokens = min(16000, 2600 * len(blueprints) + 1200)
            bp_raw = ai_client.generate(bp_prompt, timeout=420,
                                        max_output_tokens=bp_tokens)
            bp_ai = _deep_analysis_parse_response(bp_raw)
            bp_sections = [s for s in (bp_ai.get("sections") or [])
                           if s.get("layout") == "blueprint"]
            # Tolerate a model that forgot the layout tag but returned full
            # blueprint bodies (titles+hook+outline): accept those too rather
            # than dropping the creator's own ideas.
            if not bp_sections:
                alt = [s for s in (bp_ai.get("sections") or [])
                       if isinstance(s, dict) and (s.get("improved_titles") or s.get("improved_hook") or s.get("bp_title"))]
                for s in alt:
                    s["layout"] = "blueprint"
                bp_sections = alt
            if bp_sections:
                ai["sections"] = (ai.get("sections") or []) + bp_sections
            else:
                # AI gave nothing usable — fall back to deterministic sections
                # built from the stored blueprints + current channel numbers,
                # so the combined report never loses the blueprints.
                fb = _blueprint_fallback_sections(blueprints, ctx)
                if fb:
                    ai["sections"] = (ai.get("sections") or []) + fb
        except Exception:      # noqa: BLE001 — the channel report still ships
            log_crash("deep_report: blueprint sections call failed\n"
                      + traceback.format_exc())
            try:
                fb = _blueprint_fallback_sections(blueprints, ctx)
                if fb and not any((s.get("layout") == "blueprint") for s in (ai.get("sections") or [])):
                    ai["sections"] = (ai.get("sections") or []) + fb
            except Exception:
                pass

    provider_label = AI_PROVIDER_LABELS.get(ai_client.provider, ai_client.provider)
    html_doc = render_deep_analysis_html(ctx, ai, filename, provider_label,
                                         used_web_research, watched,
                                         briefs=briefs,
                                         blueprint_titles=[(b.get("title") or "").strip()
                                                           for b in (blueprints or [])
                                                           if isinstance(b, dict)],
                                         insights_html=insights_html)

    safe_name = re.sub(r"[^\w\-]+", "_", os.path.splitext(filename)[0]).strip("_") or "report"
    out_name = f"{safe_name}_combined_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
    out_path = os.path.join(_get_deep_analysis_dir(), out_name)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html_doc)
    record_deep_report(
        path, out_path,
        kind="combined_brief" if briefs else "combined",
        blueprint_titles=[(b.get("title") or "").strip()
                          for b in (blueprints or [])],
        brief_queries=[(r.get("query") or "").strip()
                       for r in (briefs or []) if isinstance(r, dict)],
        provider=provider_label, watched=watched, video_count=ctx["n"])
    return out_path
