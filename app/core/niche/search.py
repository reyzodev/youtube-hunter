"""app.core.niche.search - Youtube Scrapper."""

import json
import re
import statistics
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

from app.core.niche import audience as _aud
from app.core.monetization import _YT_UA_HEADERS, extract_balanced_json, fetch_youtube_html
from app.core.net import _urlopen, configured_proxy
from app.core.niche.helpers import _DIGIT_MAP, _digits_to_int, build_youtube_sp, days_to_sp_bucket, detect_short, iso_age_hours, rel_time_to_iso
from app.core.utils import parse_iso8601_duration
from app.core.youtube_api import ScrapeCancelled, execute_with_retry
from app.i18n import tr

# ═════════════════════════════════════════════════════════════════════════
#  DISCOVERY — MODE A: official search.list  (accurate, 100 calls/day)
# ═════════════════════════════════════════════════════════════════════════
def build_time_windows(days, deep_scan, now=None, max_windows=None):
    """Return [(publishedAfter, publishedBefore)] ISO strings.

    A single wide window sorted by view count surfaces only the very top
    videos. Deep scan slices the period into consecutive sub-windows so each
    slice gets its own "top N" — which is how small channels surface.

    `max_windows` caps the slice count. A capped search (e.g. "300 videos")
    has only so many search pages to spend; more windows than pages would
    leave the newest windows unsearched, so the period is cut into fewer,
    wider slices instead and every part of it still gets a turn."""
    now = now or datetime.now(timezone.utc)
    if not days:
        return [(None, None)]
    start = now - timedelta(days=days)
    if not deep_scan:
        return [(start.strftime("%Y-%m-%dT%H:%M:%SZ"), None)]
    n = 2 if days <= 7 else (4 if days <= 31 else 6)
    if max_windows is not None:
        n = max(1, min(n, int(max_windows)))
    if n == 1:
        return [(start.strftime("%Y-%m-%dT%H:%M:%SZ"), None)]
    step = timedelta(days=days / n)
    windows = []
    for i in range(n):
        w_start = start + step * i
        w_end = start + step * (i + 1)
        windows.append((
            w_start.strftime("%Y-%m-%dT%H:%M:%SZ"),
            (now if i == n - 1 else w_end).strftime("%Y-%m-%dT%H:%M:%SZ"),
        ))
    return windows


def estimate_search_calls(n_queries, n_windows, pages, target=None):
    """search.list calls a run will make (each one is 100 units).

    Uncapped: every page of every (query × window) slice. Capped by `target`:
    one call per 50 ids, but never fewer than one per slice."""
    slices = max(1, int(n_queries)) * max(1, int(n_windows))
    if target:
        return max(slices, -(-int(target) // 50))
    return slices * max(1, int(pages))


def capped_window_count(n_queries, target):
    """How many deep-scan windows a capped search can afford: one search page
    (50 ids) per (query × window) slice at minimum. None = uncapped."""
    if not target:
        return None
    pages = -(-int(target) // 50)
    return max(1, pages // max(1, int(n_queries)))


# ── progress phases ──────────────────────────────────────────────────────
# Every `progress` callback in this module reports
# (pct, text, phase, info) — the last two added so a UI can draw a real loading
# state instead of one sentence that replaces itself.
#
#   phase — a stable ENGLISH token naming the step. Never a translated string:
#           the text is already translated by the time it reaches the UI, so
#           matching on it would break the moment a word changed or the language
#           switched. This is what lets a UI mark earlier steps done.
#   info  — counts known so far, e.g. {"found": 142, "enriched": 50}. A spinner
#           says "working"; a count says "getting somewhere", and the discover
#           stage knows its number within a second.
#
# Both are positional, and every caller in this app accepts them. A caller that
# only wants (pct, text) must still declare the extras and ignore them.
PHASE_DISCOVER = "discover"     # collecting candidate video ids
PHASE_STATS = "stats"           # videos.list — exact view/like counts
PHASE_CHANNELS = "channels"     # channels.list — subscriber counts


def niche_search_api(yt, queries, order, windows, pages, region=None,
                     lang=None, video_duration=None, stop_check=None,
                     progress=None, quota_cb=None, target=None):
    """Collect candidate video IDs via search.list. Each page costs 1 call
    from the daily search bucket, so the caller decides `pages`.

    `target` (e.g. 300) is a hard cap on how many ids come back. The pages it
    needs (one per 50 ids) are shared out across the (query × window) slices,
    and whatever a slice could not fill (YouTube ran out of results there)
    rolls over to the slices after it. Discovery stops the moment the target
    is reached, so no search call — and no videos/channels enrichment call —
    is ever spent on ids beyond it. `target=None` keeps the old uncapped
    behaviour: every page of every slice."""
    ids, seen = [], set()
    slices = [(q, w) for q in queries for w in windows]
    total_steps = max(1, len(slices))
    target = int(target) if target else None
    for step, (q, (after, before)) in enumerate(slices, start=1):
        if target is not None:
            remaining = target - len(ids)
            if remaining <= 0:
                break
            slices_left = total_steps - step + 1
            pages_left = -(-remaining // 50)
            slice_pages = max(1, -(-pages_left // slices_left))
            slice_cap = min(remaining, slice_pages * 50)
        else:
            slice_pages = max(1, pages)
            slice_cap = None
        slice_got = 0
        token = None
        # The last slice may take one extra page: duplicates across slices can
        # leave it a few ids short, and nothing comes after it to roll into.
        extra = 1 if (target is not None and step == total_steps) else 0
        for _page in range(slice_pages + extra):
            if stop_check and stop_check():
                raise ScrapeCancelled()
            kwargs = {"part": "id", "type": "video", "q": q,
                      "maxResults": 50, "order": order}
            if after:
                kwargs["publishedAfter"] = after
            if before:
                kwargs["publishedBefore"] = before
            if region:
                kwargs["regionCode"] = region
            if lang:
                kwargs["relevanceLanguage"] = lang
            if video_duration:
                kwargs["videoDuration"] = video_duration
            if token:
                kwargs["pageToken"] = token
            resp = execute_with_retry(yt.search().list(**kwargs), stop_check)
            if quota_cb:
                quota_cb(1)
            for it in resp.get("items", []):
                if slice_cap is not None and slice_got >= slice_cap:
                    break
                vid = (it.get("id") or {}).get("videoId")
                if vid and vid not in seen:
                    seen.add(vid)
                    ids.append(vid)
                    slice_got += 1
            token = resp.get("nextPageToken")
            if not token:
                break
            if slice_cap is not None and slice_got >= slice_cap:
                break
        if progress:
            progress(int(step / total_steps * 45),
                     tr("Discovered {n} candidate videos …").format(n=len(ids)),
                     PHASE_DISCOVER, {"found": len(ids)})
    if target is not None:
        return ids[:target]
    return ids


# ═════════════════════════════════════════════════════════════════════════
#  DISCOVERY — MODE B: scrape youtube.com/results  (zero search quota)
# ═════════════════════════════════════════════════════════════════════════
def _walk_renderers(obj, out, key="videoRenderer"):
    """Depth-first collect every `key` renderer dict anywhere in the tree."""
    if isinstance(obj, dict):
        if key in obj and isinstance(obj[key], dict):
            out.append(obj[key])
        for v in obj.values():
            _walk_renderers(v, out, key)
    elif isinstance(obj, list):
        for v in obj:
            _walk_renderers(v, out, key)


def _find_continuation_token(obj):
    tokens = []
    _walk_renderers(obj, tokens, "continuationItemRenderer")
    for t in tokens:
        try:
            tok = (t.get("continuationEndpoint", {})
                    .get("continuationCommand", {}).get("token"))
            if tok:
                return tok
        except Exception:
            continue
    return None


def _text_of(node):
    """YouTube text nodes come as simpleText OR runs[]."""
    if not isinstance(node, dict):
        return ""
    if "simpleText" in node:
        return node["simpleText"] or ""
    runs = node.get("runs")
    if isinstance(runs, list):
        return "".join(r.get("text", "") for r in runs if isinstance(r, dict))
    return ""


def _lockup_text(node):
    """Text out of a `lockupViewModel`-era node.

    The newer shape wraps text one level deeper than the old one: where a
    videoRenderer carries `{"simpleText": "…"}` or `{"runs": [...]}`, a lockup
    carries `{"content": "…"}` and very often a `{"text": {"content": "…"}}`
    wrapper around that. Unwrapping is what stops every field in the new shape
    from reading as an empty string — which is exactly how a page of results
    turns into two or three parsed videos.
    """
    if not isinstance(node, dict):
        return ""
    inner = node.get("text")
    if isinstance(inner, dict):
        return _lockup_text(inner)
    if isinstance(node.get("content"), str):
        return node["content"]
    return _text_of(node)


def _abbrev_to_int(text):
    """'1.2M views' → 1200000, '345K' → 345000, '104,205,993' → 104205993.

    `_digits_to_int` strips every non-digit, which is right for the full
    "104,205,993 views" the videoRenderer shape always carries, but silently
    turns "1.2M" into 12. The lockup shape DOES abbreviate, so it needs a
    multiplier-aware reader rather than a stricter one.
    """
    if not text:
        return 0
    s = str(text).translate(_DIGIT_MAP)
    m = re.search(r"([\d.,]+)\s*([KMB])?", s, re.I)
    if not m:
        return 0
    try:
        num = float(m.group(1).replace(",", "").rstrip("."))
    except ValueError:
        return 0
    mult = {"K": 1_000, "M": 1_000_000, "B": 1_000_000_000}.get(
        (m.group(2) or "").upper(), 1)
    return int(num * mult)


def _first_browse_channel_id(obj, depth=0):
    """The first UC-prefixed browseId anywhere inside `obj`.

    Used to recover the channel id from a lockup, where it is attached to the
    channel-name endpoint rather than to a documented field. Strictly guarded:
    anything that is not an 11+ char "UC…" id is ignored, so a playlist or
    hashtag browseId can never be mistaken for a channel.
    """
    if depth > 12:
        return ""
    if isinstance(obj, dict):
        be = obj.get("browseEndpoint")
        if isinstance(be, dict):
            bid = str(be.get("browseId") or "")
            if bid.startswith("UC") and len(bid) >= 20:
                return bid
        for v in obj.values():
            found = _first_browse_channel_id(v, depth + 1)
            if found:
                return found
    elif isinstance(obj, list):
        for v in obj:
            found = _first_browse_channel_id(v, depth + 1)
            if found:
                return found
    return ""


def parse_lockup_view_model(lk):
    """`lockupViewModel` JSON → our row dict (partial), same shape as
    parse_video_renderer. Returns None when the node is not a video lockup.

    YouTube serves search results in two shapes and a single page can carry
    both: the long-standing `videoRenderer`, and the newer `lockupViewModel`.
    Reading only the old one means every result rendered in the new shape is
    invisible — the reported symptom is a search that obviously returned a full
    page but produced two or three rows.

    Every step is defensive on purpose. A lockup that does not look like a video
    is rejected outright rather than guessed at, because a wrong row here is
    worse than a missing one: it would be enriched, scored and shown as a real
    video.
    """
    if not isinstance(lk, dict):
        return None
    ctype = str(lk.get("contentType") or "").upper()
    if ctype and "VIDEO" not in ctype:
        return None            # a channel / playlist / shelf lockup
    vid = str(lk.get("contentId") or "").strip()
    if len(vid) != 11:
        return None

    meta = (lk.get("metadata") or {}).get("lockupMetadataViewModel") or {}
    title = _lockup_text(meta.get("title"))

    # Channel name, view count and publish age all live in the metadata rows:
    # row 0 is the channel, the last row is "1.2M views · 3 days ago".
    rows = []
    md = meta.get("metadata") or {}
    cmv = md.get("contentMetadataViewModel") or {}
    for row in (cmv.get("metadataRows") or []):
        parts = [_lockup_text(p.get("text"))
                 for p in (row.get("metadataParts") or [])
                 if isinstance(p, dict)]
        parts = [p for p in parts if p]
        if parts:
            rows.append(parts)

    channel_title = rows[0][0] if rows else ""
    views, published = 0, None
    for parts in rows[1:] or rows:
        for p in parts:
            if views == 0 and re.search(r"view", p, re.I):
                views = _abbrev_to_int(p)
            if published is None and re.search(r"ago", p, re.I):
                published = rel_time_to_iso(p)
        if views and published:
            break

    # Thumbnail: the image sits under one of two wrappers depending on whether
    # the lockup is a grid cell or a list row.
    thumb_url = ""
    for node in (lk.get("thumbnailViewModel") or {},
                 ((lk.get("contentImage") or {}).get(
                     "collectionThumbnailViewModel") or {}).get(
                         "primaryThumbnail") or {}):
        sources = ((((node or {}).get("image") or {}).get("sources")) or [])
        if isinstance(sources, list) and sources:
            last = sources[-1] or {}
            if last.get("url"):
                thumb_url = last["url"]
                break

    return {
        "video_id": vid,
        "title": title,
        "channel_id": _first_browse_channel_id(lk),
        "channel_title": channel_title,
        "view_count": views,
        "duration_s": 0,
        "published_at": published,
        "thumbnail_url": thumb_url or f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg",
    }


def parse_video_renderer(vr):
    """videoRenderer JSON → our row dict (partial: no subscriber data yet)."""
    vid = vr.get("videoId")
    if not vid:
        return None
    title = _text_of(vr.get("title", {}))
    thumbs = (vr.get("thumbnail", {}) or {}).get("thumbnails", []) or []
    thumb_url = thumbs[-1].get("url", "") if thumbs else ""

    channel_title, channel_id = "", ""
    for key in ("ownerText", "longBylineText", "shortBylineText"):
        node = vr.get(key)
        if not isinstance(node, dict):
            continue
        channel_title = channel_title or _text_of(node)
        for run in node.get("runs", []) or []:
            browse = ((run.get("navigationEndpoint", {}) or {})
                      .get("browseEndpoint", {}) or {})
            if browse.get("browseId"):
                channel_id = browse["browseId"]
                break
        if channel_id:
            break

    views = _digits_to_int(_text_of(vr.get("viewCountText", {})))
    length_txt = _text_of(vr.get("lengthText", {}))
    duration_s = 0
    if length_txt:
        parts = [p for p in length_txt.split(":") if p.strip().isdigit()]
        for p in parts:
            duration_s = duration_s * 60 + int(p)
    published = rel_time_to_iso(_text_of(vr.get("publishedTimeText", {})))

    return {
        "video_id": vid,
        "title": title,
        "channel_id": channel_id,
        "channel_title": channel_title,
        "view_count": views,
        "duration_s": duration_s,
        "published_at": published,
        "thumbnail_url": thumb_url or f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg",
    }


def _extract_innertube(html):
    """Pull the INNERTUBE api key + client version out of the page so we can
    ask for continuation pages (page 2, 3, …) the way the site itself does."""
    key = version = None
    m = re.search(r'"INNERTUBE_API_KEY":"([^"]+)"', html or "")
    if m:
        key = m.group(1)
    m = re.search(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"', html or "")
    if m:
        version = m.group(1)
    return key, (version or "2.20240101.00.00")


def _innertube_continue(api_key, client_version, token, timeout=15, gl="US"):
    # hl stays English on purpose: the scrape parses "1.2M views" / "3 days
    # ago" as English text. gl (the viewer's country) is what changes which
    # videos YouTube ranks, and it does not localise those strings.
    body = json.dumps({
        "context": {"client": {"clientName": "WEB",
                               "clientVersion": client_version,
                               "hl": "en", "gl": gl or "US"}},
        "continuation": token,
    }).encode("utf-8")
    req = urllib.request.Request(
        f"https://www.youtube.com/youtubei/v1/search?key={api_key}&prettyPrint=false",
        data=body,
        headers={**_YT_UA_HEADERS, "Content-Type": "application/json"})
    # Same proxy as the page fetch that produced this continuation token — page 1
    # coming through a proxy while page 2 went direct is how a proxied user got
    # exactly 20 results and no explanation.
    with _urlopen(req, timeout, configured_proxy()) as resp:
        return json.loads(resp.read().decode("utf-8", errors="ignore"))


def _collect_scrape_rows(data, rows, seen):
    """Append every video in one YouTube payload to `rows`, deduped by id.

    Runs BOTH parsers over the payload. A page can carry `videoRenderer` nodes
    and `lockupViewModel` nodes at the same time — YouTube has been migrating
    search results from the first to the second — and reading only one of them
    silently discards every result rendered in the other. That is the whole
    "the search clearly returned a page but only 2-3 videos came back" bug.

    Returns how many NEW rows were added.
    """
    added = 0
    renderers = []
    _walk_renderers(data, renderers, "videoRenderer")
    for vr in renderers:
        try:
            row = parse_video_renderer(vr)
        except Exception:                      # noqa: BLE001
            continue                           # one malformed node must not end the page
        if row and row["video_id"] not in seen:
            seen.add(row["video_id"])
            rows.append(row)
            added += 1

    lockups = []
    _walk_renderers(data, lockups, "lockupViewModel")
    for lk in lockups:
        try:
            row = parse_lockup_view_model(lk)
        except Exception:                      # noqa: BLE001
            continue
        if row and row["video_id"] not in seen:
            seen.add(row["video_id"])
            rows.append(row)
            added += 1
    return added


def _scrape_one_pass(query, days, sort_by, duration, budget, stop_check,
                     rows, seen, page_budget, region=""):
    """Walk ONE (query, sort) combination as deep as it goes, or until `budget`
    more rows have been collected. Appends into the shared `rows` / `seen`.

    Returns (added, pages_used). Raises RuntimeError only when the very first
    page cannot be fetched — a failure deeper in is not fatal, because the
    caller may already have thousands of rows from earlier passes.
    """
    sp = build_youtube_sp(sort_by=sort_by,
                          upload_date=days_to_sp_bucket(days),
                          result_type=1, duration=duration)
    gl = (region or "US").upper()
    url = ("https://www.youtube.com/results?search_query="
           + urllib.parse.quote(query) + "&sp=" + urllib.parse.quote(sp)
           + "&hl=en&gl=" + urllib.parse.quote(gl))
    html = fetch_youtube_html(url, timeout=20)
    if not html:
        raise RuntimeError(tr("Could not reach youtube.com. Check your connection "
                              "or switch the source back to the official API."))
    data = extract_balanced_json(html, "ytInitialData")
    if not data:
        raise RuntimeError(tr("YouTube returned a page this app could not read. "
                              "Switch the source to the official API."))

    before = len(rows)
    _collect_scrape_rows(data, rows, seen)
    pages = 1

    api_key, client_version = _extract_innertube(html)
    token = _find_continuation_token(data)
    # YouTube hands back roughly 20 videos per continuation. Size the walk from
    # the target instead of a magic number, with slack for pages that yield
    # fewer than 20, and a ceiling so a broken token that keeps returning the
    # same page cannot loop forever.
    max_pages = max(6, min(60, (int(budget) // 20) + 6))
    guard = 0
    while (len(rows) - before < budget and token and api_key
           and guard < max_pages and pages < page_budget):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        guard += 1
        try:
            payload = _innertube_continue(api_key, client_version, token, gl=gl)
        except Exception:
            break
        added = _collect_scrape_rows(payload, rows, seen)
        pages += 1
        token = _find_continuation_token(payload)
        if not added:
            break
        if len(rows) - before < budget:
            time.sleep(0.25)   # be polite — but not after the last page we need
    return len(rows) - before, pages


def niche_scrape_search(query, days=None, sort_by=3, duration=0, max_items=200,
                        stop_check=None, progress=None,
                        queries=None, sweep_sorts=False, page_budget=160,
                        region=""):
    """Read youtube.com/results directly. Costs ZERO search quota.

    Fragile by nature (it depends on YouTube's page shape), so every stage
    degrades gracefully: if continuation breaks we simply return what the pages
    so far gave us.

    `max_items` is a TARGET, not a hard page count. Reaching it needs more than
    one pass, because a single query under a single sort order runs out long
    before 900 videos — YouTube simply stops returning continuations (measured:
    371 videos for "music" in the last 30 days, then nothing). Two extra levers
    are therefore swept, both of which surface genuinely DIFFERENT videos rather
    than repeats:

      * `queries`   — the same comma-separated variants the official-API path
                      already searches, so both sources cover the same ground.
      * `sweep_sorts` — the other sort orders. Relevance, upload date and view
                      count each produce a different ranking of the same search,
                      and the union is much larger than any one of them.

    `page_budget` caps the TOTAL continuation pages across every pass, so a
    sweep on a huge keyword cannot turn into hundreds of requests.
    """
    # Query list: the explicit variants first, then the bare query. Order
    # matters — the user's own phrasing should fill the pool before any variant.
    qs = []
    for q in (queries or []):
        q = (q or "").strip()
        if q and q not in qs:
            qs.append(q)
    base = (query or "").strip()
    if base and base not in qs:
        qs.insert(0, base)
    if not qs:
        qs = [base]

    # Sort order first, then the rest. 3 = view count, 2 = upload date,
    # 0 = relevance — the three YouTube actually offers.
    sorts = [sort_by]
    if sweep_sorts:
        for s in (3, 2, 0):
            if s != sort_by:
                sorts.append(s)

    rows, seen = [], set()
    pages_left = max(1, int(page_budget))
    total_passes = len(qs) * len(sorts)
    done = 0
    for q in qs:
        for s in sorts:
            if len(rows) >= max_items or pages_left <= 0:
                break
            if stop_check and stop_check():
                raise ScrapeCancelled()
            done += 1
            try:
                _added, used = _scrape_one_pass(
                    q, days, s, duration, max_items - len(rows),
                    stop_check, rows, seen, pages_left, region=region)
            except RuntimeError:
                # Nothing at all yet means the very first fetch failed — that is
                # worth reporting. Once we have rows, a later pass failing is
                # just a shallower result, not an error.
                if not rows:
                    raise
                break
            pages_left -= max(1, used)
            if progress:
                progress(min(20 + int(done / max(1, total_passes) * 25), 45),
                         tr("Discovered {n} candidate videos …").format(n=len(rows)),
                         PHASE_DISCOVER, {"found": len(rows)})
    return rows[:max_items]




# ═════════════════════════════════════════════════════════════════════════
#  ENRICHMENT — exact stats (1 quota unit per 50 items, from the big bucket)
# ═════════════════════════════════════════════════════════════════════════
def enrich_videos(yt, video_ids, stop_check=None, progress=None):
    out = {}
    ids = list(dict.fromkeys([v for v in video_ids if v]))
    total = max(1, len(ids))
    for i in range(0, len(ids), 50):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        chunk = ids[i:i + 50]
        resp = execute_with_retry(
            yt.videos().list(part="snippet,statistics,contentDetails",
                             id=",".join(chunk)), stop_check)
        for v in resp.get("items", []):
            out[v["id"]] = v
        if progress:
            progress(45 + int((i + 50) / total * 30),
                     tr("Fetching exact view counts …"), PHASE_STATS,
                     {"enriched": len(out), "of": len(ids)})
    return out


def enrich_channels(yt, channel_ids, stop_check=None, progress=None):
    out = {}
    ids = list(dict.fromkeys([c for c in channel_ids if c]))
    total = max(1, len(ids))
    for i in range(0, len(ids), 50):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        chunk = ids[i:i + 50]
        resp = execute_with_retry(
            yt.channels().list(part="snippet,statistics", id=",".join(chunk)),
            stop_check)
        for c in resp.get("items", []):
            out[c["id"]] = c
        if progress:
            progress(75 + int((i + 50) / total * 20),
                     tr("Fetching subscriber counts …"), PHASE_CHANNELS,
                     {"channels": len(out), "of": len(ids)})
    return out


def merge_niche_row(base, v_item=None, ch_item=None):
    """Fold API video + channel payloads onto a (possibly scraped) base row."""
    row = dict(base or {})
    if v_item:
        snip = v_item.get("snippet", {}) or {}
        stats = v_item.get("statistics", {}) or {}
        details = v_item.get("contentDetails", {}) or {}
        thumbs = snip.get("thumbnails", {}) or {}
        row["video_id"] = v_item.get("id", row.get("video_id", ""))
        row["title"] = snip.get("title", row.get("title", ""))
        row["channel_id"] = snip.get("channelId", row.get("channel_id", ""))
        row["channel_title"] = snip.get("channelTitle", row.get("channel_title", ""))
        row["published_at"] = snip.get("publishedAt", row.get("published_at"))
        # Spoken/declared language of the video itself ("en", "fa", "en-US").
        # Additive: only the QML cards read it, the legacy UI ignores it.
        row["audio_lang"] = (snip.get("defaultAudioLanguage")
                             or snip.get("defaultLanguage")
                             or row.get("audio_lang", ""))
        # The two declarations kept apart for the audience filter: the SPOKEN
        # language is strong evidence, the metadata language weaker (it is the
        # language the title was typed in, often a channel-wide default).
        row["audio_lang_declared"] = snip.get("defaultAudioLanguage", "") or ""
        row["meta_lang"] = snip.get("defaultLanguage", "") or ""
        row["description"] = (snip.get("description", "") or "")[:400]
        best = (thumbs.get("medium") or thumbs.get("high")
                or thumbs.get("default") or {})
        if best.get("url"):
            row["thumbnail_url"] = best["url"]
        for src, dst in (("viewCount", "view_count"), ("likeCount", "like_count"),
                         ("commentCount", "comment_count")):
            try:
                row[dst] = int(stats.get(src, row.get(dst, 0) or 0))
            except (TypeError, ValueError):
                row[dst] = row.get(dst, 0) or 0
        # Whether the public like/comment counts were ACTUALLY returned, as
        # opposed to defaulted to 0 by the loop above. A creator who has hidden
        # their like count and one with genuinely zero likes are different
        # facts, and the interaction rate in app.core.analysis.snapshot must not
        # average the first as if it were the second. Kept as separate flags
        # rather than changing the 0-fill, which every existing reader relies on.
        row["likes_hidden"] = "likeCount" not in stats
        row["comments_hidden"] = "commentCount" not in stats
        row["duration_s"] = parse_iso8601_duration(details.get("duration", "PT0S"))
        # Free extras — already inside the videos.list payload this call pays
        # for (part="snippet,statistics,contentDetails"), just never read until
        # Niche Scan needed them. No extra quota, no extra request.
        tags = snip.get("tags")
        if isinstance(tags, list):
            row["tags"] = [str(t) for t in tags[:15] if str(t).strip()]
        row["has_captions"] = (str(details.get("caption", "")).lower() == "true")
        row["definition"] = str(details.get("definition", "") or "")
        row["category_id"] = str(snip.get("categoryId", "") or "")

    if ch_item:
        c_snip = ch_item.get("snippet", {}) or {}
        c_stats = ch_item.get("statistics", {}) or {}
        c_thumbs = (c_snip.get("thumbnails", {}) or {})
        row["channel_title"] = c_snip.get("title", row.get("channel_title", ""))
        row["channel_thumb_url"] = ((c_thumbs.get("default")
                                     or c_thumbs.get("medium") or {}).get("url", ""))
        row["channel_country"] = c_snip.get("country", "")
        # When the channel was created — free in the same channels.list payload,
        # and what the "Channel age" cut (new channels blowing up) reads.
        if c_snip.get("publishedAt"):
            row["channel_created_at"] = c_snip.get("publishedAt")
        # The channel's own declared language — weak, but free, evidence.
        row["channel_lang"] = c_snip.get("defaultLanguage", "") or ""
        row["subs_hidden"] = bool(c_stats.get("hiddenSubscriberCount", False))
        try:
            row["subscriber_count"] = int(c_stats.get("subscriberCount", 0))
        except (TypeError, ValueError):
            row["subscriber_count"] = 0
        try:
            row["channel_total_views"] = int(c_stats.get("viewCount", 0))
        except (TypeError, ValueError):
            row["channel_total_views"] = 0
        try:
            row["channel_video_count"] = int(c_stats.get("videoCount", 0))
        except (TypeError, ValueError):
            row["channel_video_count"] = 0

    row.setdefault("view_count", 0)
    row.setdefault("like_count", 0)
    row.setdefault("comment_count", 0)
    row.setdefault("subscriber_count", None)
    row.setdefault("subs_hidden", False)
    row.setdefault("duration_s", 0)
    row.setdefault("channel_thumb_url", "")
    row.setdefault("description", "")
    # A scrape-only row never saw a videos.list payload, so its like/comment
    # counts are placeholders and its tags/captions/definition are unknown.
    # Defaulted as "hidden"/absent so snapshot coverage reports the truth rather
    # than counting a scraped row as a complete one.
    row.setdefault("likes_hidden", True)
    row.setdefault("comments_hidden", True)
    row.setdefault("tags", [])
    row.setdefault("has_captions", None)
    row.setdefault("definition", "")
    row.setdefault("category_id", "")
    row["is_short"] = detect_short(row.get("duration_s", 0), row.get("title", ""),
                                   row.get("description", ""))
    vid = row.get("video_id", "")
    row["video_url"] = f"https://www.youtube.com/watch?v={vid}" if vid else ""
    cid = row.get("channel_id", "")
    row["channel_url"] = f"https://www.youtube.com/channel/{cid}" if cid else ""
    if not row.get("thumbnail_url") and vid:
        row["thumbnail_url"] = f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg"
    return row


def compute_niche_metrics(rows):
    """Adds multiplier (views ÷ subs), velocity (views/hour), engagement and
    outlier_ratio (views ÷ pool median). Mutates + returns `rows`."""
    view_list = [r.get("view_count", 0) for r in rows if r.get("view_count")]
    median = max(statistics.median(view_list), 1) if view_list else 1
    for r in rows:
        views = r.get("view_count", 0) or 0
        subs = r.get("subscriber_count")
        if subs and subs > 0 and not r.get("subs_hidden"):
            r["multiplier"] = views / float(subs)
        else:
            r["multiplier"] = None
        age = iso_age_hours(r.get("published_at")) if r.get("published_at") else None
        r["age_hours"] = age
        r["velocity"] = (views / age) if age else 0.0
        r["engagement"] = (((r.get("like_count", 0) or 0)
                            + (r.get("comment_count", 0) or 0)) / views) if views else 0.0
        r["outlier_ratio"] = views / median
        # Channel outlier: this video against its OWN channel's average video
        # (lifetime views ÷ uploads, free in the channels.list payload we
        # already pay for). This is the number pros actually hunt with — views
        # ÷ subs flatters Shorts channels and punishes channels whose subs went
        # stale; "6× what this channel normally gets" is a repeatable signal.
        ch_views = r.get("channel_total_views") or 0
        ch_videos = r.get("channel_video_count") or 0
        if ch_views > 0 and ch_videos > 0:
            avg = ch_views / float(ch_videos)
            r["channel_avg_views"] = avg
            r["channel_outlier"] = (views / avg) if avg > 0 else None
        else:
            r["channel_avg_views"] = None
            r["channel_outlier"] = None
    # Gold Score (app.core.niche.gold): the one-number "steal this idea" rank.
    # Pool-relative, so it is computed after every row has its velocity.
    from app.core.niche.gold import apply_gold_scores
    apply_gold_scores(rows)
    return rows


# Text-filter normalisation (v3.43c). The box used to do a raw lower-case
# substring test, so "کتاب" missed a title typed with Arabic "كتاب", a ZWNJ
# ("می‌خواهم" vs "میخواهم") broke a match, Persian digits never matched Latin
# ones, and two words only matched when they sat next to each other in that
# exact order. Now both sides are normalised and EVERY word must appear.
_TEXT_FOLD = str.maketrans({
    "ي": "ی", "ى": "ی", "ئ": "ی", "ك": "ک", "ة": "ه", "ۀ": "ه",
    "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
    "\u200c": "", "\u200d": "", "\u200e": "", "\u200f": "", "ـ": "",
    "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
    "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
    "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
    "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
})
_ARABIC_MARKS = re.compile("[\u064B-\u065F\u0670]")


def _fold_text(s):
    s = _ARABIC_MARKS.sub("", str(s or "").casefold().translate(_TEXT_FOLD))
    return " ".join(s.split())


def apply_niche_filters(rows, f):
    """Pure, in-memory filtering — this is what makes the sliders instant."""
    f = f or {}
    text_terms = _fold_text(f.get("text") or "").split()
    aud_lang = _aud.norm_lang(f.get("lang") or "")
    aud_region = (f.get("region") or "").strip().upper()
    aud_precision = f.get("precision") or "smart"
    # v1.0.1: one "Country" picker that means "content made for this country"
    # (title in its language, channel not registered elsewhere). Takes over
    # from lang/region when set. See audience.market_fit.
    market = (f.get("market") or "").strip().upper()
    if market:
        aud_lang = aud_region = ""
    ch_age_days = f.get("channel_max_age_days")
    # "-word" in the quick filter EXCLUDES titles containing it — the cut a
    # niche hunter reaches for constantly ("minecraft -mod -server").
    exclude_terms = [t[1:] for t in text_terms if t.startswith("-") and len(t) > 1]
    text_terms = [t for t in text_terms if not t.startswith("-")]
    outlier_min = f.get("outlier_min")
    dur_min = f.get("dur_min_s")
    dur_max = f.get("dur_max_s")
    eng_min = f.get("eng_min")
    vel_min = f.get("vel_min")
    ch_videos_max = f.get("ch_videos_max")
    # Category: "24" keeps only that category, "!10" drops it (e.g. "no music
    # videos" on a trending chart). Rows with no category (scrape-only) are
    # kept only by an exclusion, never by an inclusion.
    category = str(f.get("category") or "").strip()
    out = []
    for r in rows:
        subs = r.get("subscriber_count")
        hidden = bool(r.get("subs_hidden"))
        if f.get("hide_hidden_subs") and hidden:
            continue
        if f.get("subs_min") is not None or f.get("subs_max") is not None:
            if hidden or subs is None:
                continue
            if f.get("subs_min") is not None and subs < f["subs_min"]:
                continue
            if f.get("subs_max") is not None and subs > f["subs_max"]:
                continue
        views = r.get("view_count", 0) or 0
        if f.get("views_min") is not None and views < f["views_min"]:
            continue
        if f.get("views_max") is not None and views > f["views_max"]:
            continue
        if f.get("mult_min") is not None:
            mult = r.get("multiplier")
            if mult is None or mult < f["mult_min"]:
                continue
        fmt = f.get("format")
        if fmt == "long" and r.get("is_short"):
            continue
        if fmt == "short" and not r.get("is_short"):
            continue
        days = f.get("days")
        if days:
            age = r.get("age_hours")
            if age is None:
                # unknown publish date: the live grid keeps it (the search was
                # already date-bounded server-side); the archive asks for
                # strict, because there nothing else vouches for the date.
                if f.get("strict_days"):
                    continue
            elif age > days * 24:
                continue
        if text_terms or exclude_terms:
            haystack = _fold_text(f"{r.get('title','')} {r.get('channel_title','')}")
            if text_terms and not all(t in haystack for t in text_terms):
                continue
            if exclude_terms and any(t in haystack for t in exclude_terms):
                continue
        if outlier_min is not None:
            co = r.get("channel_outlier")
            if co is None or co < outlier_min:
                continue
        if dur_min is not None or dur_max is not None:
            dur = r.get("duration_s") or 0
            if dur <= 0:
                continue
            if dur_min is not None and dur < dur_min:
                continue
            if dur_max is not None and dur >= dur_max:
                continue
        if eng_min is not None:
            # same floor as the engagement sort: under 1K views the rate is noise
            if (r.get("view_count") or 0) < 1000 or (r.get("engagement") or 0) < eng_min:
                continue
        if vel_min is not None and (r.get("velocity") or 0) < vel_min:
            continue
        if ch_videos_max is not None:
            n_up = r.get("channel_video_count") or 0
            if n_up <= 0 or n_up > ch_videos_max:
                continue
        if category:
            cat = str(r.get("category_id") or "")
            if category.startswith("!"):
                if cat and cat == category[1:]:
                    continue
            elif cat != category:
                continue
        if ch_age_days:
            # A channel we have no creation date for is not "new" — leaving it
            # in would let every stale cached row through the cut.
            c_age = iso_age_hours(r.get("channel_created_at")) if r.get("channel_created_at") else None
            if c_age is None or c_age > ch_age_days * 24:
                continue
        if market and not _aud.market_fit(r, market):
            continue
        # Language / country last: it is the only cut that does real work per
        # row (memoised after the first pass), so every cheaper cut runs first.
        if (aud_lang or aud_region) and not _aud.passes(r, aud_lang, aud_region,
                                                         aud_precision):
            continue
        out.append(r)
    return out


def cap_per_channel(rows, limit):
    """Keep at most `limit` rows per channel, in the order given (so after a
    sort it keeps each channel's best). One prolific channel can otherwise fill
    a whole page and hide every other channel doing the same thing. 0 = off."""
    if not limit or limit <= 0:
        return list(rows)
    seen, out = {}, []
    for r in rows:
        cid = r.get("channel_id") or r.get("channel_title") or ""
        n = seen.get(cid, 0)
        if cid and n >= limit:
            continue
        seen[cid] = n + 1
        out.append(r)
    return out
