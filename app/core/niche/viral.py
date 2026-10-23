"""app.core.niche.viral - YouTube Hunter.

Viral Radar: what is blowing up on YouTube right now, with no keyword.

Two sources, both ending in the same Niche Finder row shape (merge_niche_row +
compute_niche_metrics), so every existing cut, sort, card, export, Niche Scan
hand-off and archive save works on them unchanged:

  * "chart"    — videos.list(chart=mostPopular). YouTube's own trending chart
                 per country (and optionally per category). 1 quota unit per
                 50 videos, and the payload already carries snippet,
                 statistics and contentDetails, so there is no separate
                 videos.list enrich step. Up to 200 videos per country.
  * "breakout" — search.list with NO q, order=viewCount, publishedAfter=now-N.
                 The most-watched uploads of the window across all of YouTube,
                 not only what made the chart, which is where small channels
                 with a huge video actually show up. 100 units per page (it
                 draws on the same search budget as a keyword search).

Either way channels.list (1 unit per 50 channels) supplies subscriber counts,
which is what makes "views ÷ subs" — the high-views / low-subs ranking — work.
"""

from datetime import datetime, timedelta, timezone

from googleapiclient.errors import HttpError

from app.core.niche.helpers import iso_age_hours
from app.core.niche.search import (
    PHASE_CHANNELS, PHASE_DISCOVER, PHASE_STATS, compute_niche_metrics,
    enrich_channels, enrich_videos, merge_niche_row)
from app.core.youtube_api import ScrapeCancelled, execute_with_retry
from app.i18n import tr

# (UI label, region code). "" = Global: the chart of several big markets,
# merged and de-duplicated. mostPopular itself has no "worldwide" chart (no
# regionCode silently means US), so Global is built here instead.
VIRAL_REGIONS = [
    ("Global · top markets", ""),
    ("United States", "US"),
    ("United Kingdom", "GB"),
    ("Canada", "CA"),
    ("Australia", "AU"),
    ("India", "IN"),
    ("Brazil", "BR"),
    ("Mexico", "MX"),
    ("Spain", "ES"),
    ("Germany", "DE"),
    ("France", "FR"),
    ("Italy", "IT"),
    ("Turkey", "TR"),
    ("Russia", "RU"),
    ("Saudi Arabia", "SA"),
    ("United Arab Emirates", "AE"),
    ("Egypt", "EG"),
    ("Iraq", "IQ"),
    ("Pakistan", "PK"),
    ("Indonesia", "ID"),
    ("Philippines", "PH"),
    ("Vietnam", "VN"),
    ("Japan", "JP"),
    ("South Korea", "KR"),
]

# The markets "Global" merges. Eight charts × 2 pages = 16 units.
VIRAL_GLOBAL_MARKETS = ["US", "IN", "BR", "GB", "ID", "MX", "DE", "JP"]

# (UI label, videoCategoryId). Not every category has a chart in every
# country — a missing one is skipped, never an error for the whole run.
VIRAL_CATEGORIES = [
    ("All categories", ""),
    ("Entertainment", "24"),
    ("Gaming", "20"),
    ("Music", "10"),
    ("People & Blogs", "22"),
    ("Comedy", "23"),
    ("Howto & Style", "26"),
    ("Education", "27"),
    ("Science & Technology", "28"),
    ("News & Politics", "25"),
    ("Sports", "17"),
    ("Film & Animation", "1"),
    ("Autos & Vehicles", "2"),
    ("Pets & Animals", "15"),
    ("Travel & Events", "19"),
]

# (UI label, source token)
VIRAL_SOURCES = [
    ("Trending chart · ~1 unit / 50", "chart"),
    ("Breakouts · all of YouTube", "breakout"),
]

# (UI label, hours). The chart is filtered locally by age; a breakout search
# asks YouTube for the window directly (publishedAfter).
VIRAL_WINDOWS = [
    ("24 hours", 24),
    ("48 hours", 48),
    ("7 days", 24 * 7),
    ("30 days", 24 * 30),
]

_CHART_PAGES_SINGLE = 4      # 4 × 50 = the whole chart (YouTube caps it at 200)
_CHART_PAGES_GLOBAL = 2      # per market when merging eight of them
_BREAKOUT_PAGES = 2          # 2 × 100 units = 100 videos per market


def viral_label(region_code, category_id):
    """"Viral · United States · Gaming" — also the Search Archive section
    title, so re-saving the same radar merges into one growing section."""
    region = (next((n for n, c in VIRAL_REGIONS if c == region_code), region_code)
              if region_code else "Global")
    parts = ["Viral", region]
    if category_id:
        cat = next((n for n, c in VIRAL_CATEGORIES if c == category_id), category_id)
        parts.append(cat)
    return " · ".join(parts)


def _is_missing_chart(exc):
    """True for "this country has no chart for this category" style errors,
    which must skip one market rather than fail the run."""
    status = getattr(getattr(exc, "resp", None), "status", None)
    return status in (400, 404)


def _chart_items(yt, region, category, pages, stop_check):
    items, token = [], None
    for _ in range(max(1, pages)):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        kw = {"part": "snippet,statistics,contentDetails", "chart": "mostPopular",
              "maxResults": 50}
        if region:
            kw["regionCode"] = region
        if category:
            kw["videoCategoryId"] = category
        if token:
            kw["pageToken"] = token
        try:
            resp = execute_with_retry(yt.videos().list(**kw), stop_check)
        except HttpError as exc:
            if _is_missing_chart(exc):
                break
            raise
        items += resp.get("items", []) or []
        token = resp.get("nextPageToken")
        if not token:
            break
    return items


def _breakout_ids(yt, region, category, hours, pages, stop_check, quota_cb):
    after = (datetime.now(timezone.utc) - timedelta(hours=hours)).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    ids, token = [], None
    for _ in range(max(1, pages)):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        kw = {"part": "id", "type": "video", "order": "viewCount",
              "publishedAfter": after, "maxResults": 50}
        if region:
            kw["regionCode"] = region
        if category:
            kw["videoCategoryId"] = category
        if token:
            kw["pageToken"] = token
        try:
            resp = execute_with_retry(yt.search().list(**kw), stop_check)
        except HttpError as exc:
            if _is_missing_chart(exc):
                break
            raise
        if quota_cb:
            quota_cb(1)
        for it in resp.get("items", []) or []:
            vid = (it.get("id") or {}).get("videoId")
            if vid:
                ids.append(vid)
        token = resp.get("nextPageToken")
        if not token:
            break
    return ids


def estimate_viral_units(source, region_code):
    """Rough quota cost of one radar run, for the cost line under the bar."""
    markets = 1 if region_code else len(VIRAL_GLOBAL_MARKETS)
    if source == "breakout":
        return markets * _BREAKOUT_PAGES * 100 + markets * 4
    pages = _CHART_PAGES_SINGLE if region_code else _CHART_PAGES_GLOBAL
    return markets * pages + markets * 3


def fetch_viral(yt, source="chart", region_code="", category_id="", hours=48,
                stop_check=None, progress=None, quota_cb=None):
    """Collect what is viral right now and return Niche Finder rows.

    Every row also carries `viral_rank` (its position in the chart / breakout
    list it came from, best first) and `viral_region` (the market it was
    found in), so a Global run can still say where a video is trending."""
    markets = [region_code] if region_code else list(VIRAL_GLOBAL_MARKETS)
    order, rank, region_of = [], {}, {}
    v_map = {}

    for i, market in enumerate(markets):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        if progress:
            progress(5 + int(i / max(1, len(markets)) * 40),
                     tr("Reading what is viral in {m} …").format(m=market or "US"),
                     PHASE_DISCOVER, {"found": len(order)})
        if source == "breakout":
            ids = _breakout_ids(yt, market, category_id, hours, _BREAKOUT_PAGES,
                                stop_check, quota_cb)
            got = [(vid, None) for vid in ids]
        else:
            pages = _CHART_PAGES_SINGLE if region_code else _CHART_PAGES_GLOBAL
            got = [(it.get("id"), it) for it in
                   _chart_items(yt, market, category_id, pages, stop_check)]
        for pos, (vid, item) in enumerate(got):
            if not vid:
                continue
            if item is not None:
                v_map[vid] = item
            if vid not in rank:
                order.append(vid)
                rank[vid] = pos + 1
                region_of[vid] = market or "US"
            else:
                rank[vid] = min(rank[vid], pos + 1)

    if progress:
        progress(45, tr("Fetching exact view counts …"), PHASE_DISCOVER,
                 {"found": len(order)})
    missing = [vid for vid in order if vid not in v_map]
    if missing:
        v_map.update(enrich_videos(yt, missing, stop_check, progress))
    elif progress:
        progress(70, tr("Fetching exact view counts …"), PHASE_STATS,
                 {"enriched": len(v_map), "of": len(order)})

    ch_ids = [((v_map.get(vid) or {}).get("snippet") or {}).get("channelId")
              for vid in order]
    c_map = enrich_channels(yt, ch_ids, stop_check, progress)

    rows = []
    for vid in order:
        v = v_map.get(vid)
        if not v:
            continue
        cid = (v.get("snippet") or {}).get("channelId")
        row = merge_niche_row({"video_id": vid}, v, c_map.get(cid))
        row["viral_rank"] = rank.get(vid, 0)
        row["viral_region"] = region_of.get(vid, "")
        row["viral_source"] = source
        rows.append(row)

    # The chart is "trending now" with no date bound of its own: hold it to the
    # chosen window here so "24 hours" means what it says.
    if source == "chart" and hours:
        kept = []
        for r in rows:
            age = iso_age_hours(r.get("published_at")) if r.get("published_at") else None
            if age is None or age <= hours:
                kept.append(r)
        rows = kept

    if progress:
        progress(97, tr("Ranking …"), PHASE_CHANNELS, {"channels": len(c_map)})
    return compute_niche_metrics(rows)
