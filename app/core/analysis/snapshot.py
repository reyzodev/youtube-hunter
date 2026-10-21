"""app.core.analysis.snapshot - YouTube Hunter.

Deterministic, AI-free aggregate analytics over ONE set of search rows (a
"snapshot"): the numbers a creator needs to read a niche as a whole rather than
one row at a time.

Everything here is computed from the rows the app already has. No API call, no
model call, no quota. The rules that matter:

  * MEDIAN and AVERAGE are always reported together. One viral outlier drags an
    average far from what a new video in this niche can expect, so an average
    quoted alone is the single most misleading number in YouTube research.
  * MISSING STAYS MISSING. A channel that hides its subscriber count, a video
    with likes turned off, a scrape-only row with no videos.list payload — none
    of those become 0. Each metric reports how many rows it could actually be
    computed from (`coverage`), so the UI can say "median of 12 of 50 rows"
    instead of implying all 50.
  * Every number here is OBSERVED (measured off the snapshot) or arithmetic on
    observed values. Nothing in this module infers, predicts or estimates —
    that separation is what lets app.core.ai.insights label its claims honestly.

The row shape is the one app.core.niche.search.merge_niche_row produces (and
which the search archive stores verbatim as JSON), so the same function serves a
live Niche Finder result and a saved archive group.
"""

import hashlib
import re
import statistics
from collections import Counter

from app.core.niche.helpers import iso_age_hours
from app.i18n import tr

# Bucket edges in seconds, (low, high_exclusive, key). `key` is a stable English
# token — the UI translates it, so a stored report doesn't freeze its labels in
# whatever language it was generated in.
DURATION_BUCKETS = [
    (0, 60, "under_1m"),
    (60, 180, "1_3m"),
    (180, 600, "3_10m"),
    (600, 1200, "10_20m"),
    (1200, None, "over_20m"),
]

RECENCY_BUCKETS = [
    (0, 7, "last_7d"),
    (7, 30, "8_30d"),
    (30, 365, "1_12m"),
    (365, None, "over_1y"),
]

# Channel size by public subscriber count, (low, high_exclusive, key). The
# question these answer is the one a new creator actually asks of a niche:
# "do small channels ever win here, or is it only the big ones?"
CHANNEL_SIZE_BUCKETS = [
    (0, 10_000, "under_10k"),
    (10_000, 100_000, "10k_100k"),
    (100_000, 1_000_000, "100k_1m"),
    (1_000_000, None, "over_1m"),
]

# A video "outperformed" when it earned at least this many times its own
# channel's average views per video. Same idea as the outlier score creators
# know from vidIQ / 1of10, but computed from public channel statistics only.
OUTLIER_X = 3.0

# Below this subscriber count a channel counts as "small" for the
# small-channel-wins reading.
SMALL_CHANNEL_SUBS = 10_000

# Words too common to be a "recurring topic". Both languages, since a Persian
# creator's snapshot is titled in Persian. Mirrors _DEEP_STOPWORDS in
# app.core.analysis.deep_report but kept separate: that one is tuned for
# single-channel title mining, this one runs over a mixed-channel search.
_STOPWORDS = set("""
the a an and or of to in on for with is are was were be by this that how why
what your you we our from at as its it new best top get make made do does did
not no all my me him her they them i s t re ve ll d m o
از به که این آن را با در برای یک دو سه چهار پنج شش هفت هشت نه ده و یا اگر تا
هم می نمی شد شده است بود هر همه یه رو چه کی کجا چرا چطور بهترین
""".split())

def _int(v):
    """A count, or 0. Used only where a 0 is genuinely meaningful."""
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0

def _median(values):
    return statistics.median(values) if values else None

def _mean(values):
    return statistics.fmean(values) if values else None

def snapshot_key(rows):
    """A stable id for the exact ordered set of videos this report describes.

    Borrowed from the reference project's `snapshotId` discipline: a brief is
    only valid for the snapshot it was generated from, so the cache key has to
    change the moment the set or its order changes. sha1 over the ids is enough
    — this is an identity, not a security boundary."""
    ids = [str(r.get("video_id") or r.get("channel_id") or "") for r in (rows or [])]
    return hashlib.sha1("\n".join(ids).encode("utf-8")).hexdigest()[:16]

def _row_age_days(row):
    hours = iso_age_hours(row.get("published_at") or "")
    return (hours / 24.0) if hours else None

def _bucket(value, buckets):
    for low, high, key in buckets:
        if value >= low and (high is None or value < high):
            return key
    return buckets[-1][2]

def _leaders(rows, metric, n=5):
    """Top `n` rows by a per-row numeric field, skipping rows where it is
    absent. Returns (row, value) pairs so the UI can print the number that
    earned the placement."""
    scored = [(r, r.get(metric)) for r in rows
              if isinstance(r.get(metric), (int, float)) and r[metric] > 0]
    scored.sort(key=lambda pair: pair[1], reverse=True)
    return scored[:n]

def _topic_chips(rows, n=14):
    """Recurring topics, from real `tags` where the API returned them and real
    title-word frequency where it didn't.

    Two sources rather than one because tags are optional and increasingly
    unused: a snapshot of 50 videos can easily have tags on three of them, and
    an empty chip row is worse than a title-derived one. `source` tells the UI
    which it got, so the label can be honest about it."""
    tag_counts = Counter()
    tag_display = {}
    tagged_rows = 0
    for row in rows:
        tags = row.get("tags")
        if not isinstance(tags, list) or not tags:
            continue
        tagged_rows += 1
        # A tag repeated inside one video's own list is still one video.
        for tag in {str(t).strip().lower() for t in tags if str(t).strip()}:
            tag_counts[tag] += 1
            tag_display.setdefault(tag, tag)

    # Tags only earn the chip row if enough videos carry them to make a count
    # meaningful — otherwise it is three videos' private keywords masquerading
    # as a niche pattern.
    if tagged_rows >= max(4, len(rows) * 0.25):
        ranked = [(tag_display[t], c) for t, c in tag_counts.most_common(n * 2) if c >= 2][:n]
        if ranked:
            return {"source": "tags", "tagged_rows": tagged_rows, "chips": ranked}

    word_counts = Counter()
    word_display = {}
    for row in rows:
        title = str(row.get("title") or "")
        for raw in re.findall(r"[A-Za-z؀-ۿ]{3,}", title):
            key = raw.lower()
            if key in _STOPWORDS:
                continue
            word_counts[key] += 1
            word_display.setdefault(key, raw)
    ranked = [(word_display[w], c) for w, c in word_counts.most_common(n * 2) if c >= 2][:n]
    if len(ranked) < 5:
        ranked = [(word_display[w], c) for w, c in word_counts.most_common(n)]
    return {"source": "titles", "tagged_rows": tagged_rows, "chips": ranked}

def _public_subs(row):
    """Subscriber count, or None when hidden / never fetched. Never 0-filled."""
    if row.get("subs_hidden"):
        return None
    subs = row.get("subscriber_count")
    return _int(subs) if subs not in (None, "") and _int(subs) > 0 else None

def _channel_baseline(row):
    """The channel's average views per video (lifetime views ÷ uploads), or
    None. This is a fairer yardstick than subscribers: it is what this channel
    USUALLY gets, so a video far above it is a genuine outlier for its maker."""
    total = _int(row.get("channel_total_views"))
    count = _int(row.get("channel_video_count"))
    return (total / count) if total > 0 and count > 0 else None

def _format_split(viewed):
    """Median views for Shorts and long-form separately.

    One median across both formats describes neither: a Shorts median of 400K
    next to a long-form median of 12K averages into a number no video in the
    set actually got."""
    shorts = [_int(r["view_count"]) for r in viewed if r.get("is_short")]
    longs = [_int(r["view_count"]) for r in viewed if not r.get("is_short")]
    return {
        "shorts_rows": len(shorts),
        "long_rows": len(longs),
        "shorts_median": _median(shorts),
        "long_median": _median(longs),
        "mixed": bool(shorts) and bool(longs),
    }

def _size_tiers(viewed, set_median):
    """Rows per channel-size tier, each with its own median views and how many
    of its videos beat the median of the whole set."""
    tiers = {key: [] for _lo, _hi, key in CHANNEL_SIZE_BUCKETS}
    for r in viewed:
        subs = _public_subs(r)
        if subs is None:
            continue
        tiers[_bucket(subs, CHANNEL_SIZE_BUCKETS)].append(_int(r["view_count"]))
    out = []
    for _lo, _hi, key in CHANNEL_SIZE_BUCKETS:
        vals = tiers[key]
        out.append({
            "key": key,
            "rows": len(vals),
            "median_views": _median(vals),
            "beat_median": (sum(1 for v in vals if v > set_median)
                            if set_median is not None else 0),
        })
    return out

def _outliers(viewed):
    """Views ÷ the channel's own average views per video, per row."""
    scored = []
    for r in viewed:
        base = _channel_baseline(r)
        if base:
            scored.append((r, _int(r["view_count"]) / base))
    hits = [pair for pair in scored if pair[1] >= OUTLIER_X]
    hits.sort(key=lambda pair: pair[1], reverse=True)
    return {
        "rows": len(scored),
        "hits": len(hits),
        "rate": (len(hits) / len(scored)) if scored else None,
        "median_score": _median([v for _r, v in scored]),
        "leaders": [{
            "video_id": r.get("video_id", ""),
            "title": r.get("title", ""),
            "channel_title": r.get("channel_title", ""),
            "views": _int(r.get("view_count")),
            "value": v,
        } for r, v in hits[:5]],
    }

def _languages(rows, n=4):
    """Which language the set is made in: declared audio language first, then
    the metadata language, then the channel's default. Weak but free signal —
    the useful reading is a gap ("all English, nothing in Persian")."""
    counts = Counter()
    known = 0
    for r in rows:
        lang = (r.get("audio_lang") or r.get("meta_lang")
                or r.get("channel_lang") or "")
        lang = str(lang).split("-")[0].strip().lower()
        if not lang:
            continue
        known += 1
        counts[lang] += 1
    return {"rows": known, "top": counts.most_common(n)}

def _title_shape(rows):
    """How titles in this niche are written: length, numbers, questions."""
    titles = [str(r.get("title") or "").strip() for r in rows]
    titles = [t for t in titles if t]
    if not titles:
        return None
    n = len(titles)
    return {
        "rows": n,
        "median_chars": _median([len(t) for t in titles]),
        "with_number": sum(1 for t in titles if re.search(r"[0-9۰-۹]", t)) / n,
        "question": sum(1 for t in titles if "?" in t or "؟" in t) / n,
        "brackets": sum(1 for t in titles if re.search(r"[\[\(|]", t)) / n,
    }

def build_snapshot(rows, query="", mode="keyword"):
    """Reduce a list of search rows to the aggregate reading of the set.

    Returns None for an empty snapshot rather than a dict full of zeros — the
    caller shows an empty state, not a report claiming a median of 0.
    """
    rows = [r for r in (rows or []) if isinstance(r, dict)]
    if not rows:
        return None

    total = len(rows)

    # ── views: the median/average pair, and momentum ──────────────────────
    # A row with no view count at all is excluded rather than counted as 0;
    # `coverage.views` reports how many were usable.
    viewed = [r for r in rows if _int(r.get("view_count")) > 0]
    views = [_int(r["view_count"]) for r in viewed]
    total_views = sum(views)

    # Age-normalised momentum: views per day, median across rows that have both
    # a view count and a parseable publish date. The reference project's
    # `medianDailyViews` — a fair comparison between a 3-day-old video and a
    # 3-year-old one, which raw views never is.
    daily = []
    for r in viewed:
        age_days = _row_age_days(r)
        if age_days and age_days > 0:
            daily.append(_int(r["view_count"]) / max(age_days, 0.25))

    # ── interaction: complete rows only ──────────────────────────────────
    # (likes + comments) ÷ views, and ONLY over rows where the API actually
    # returned both counts. This is a visible-interaction proxy, not engagement
    # and certainly not satisfaction — YouTube reports neither publicly.
    complete = [r for r in viewed
                if not r.get("likes_hidden") and not r.get("comments_hidden")]
    inter_views = sum(_int(r["view_count"]) for r in complete)
    inter_actions = sum(_int(r.get("like_count")) + _int(r.get("comment_count"))
                        for r in complete)
    interaction_rate = (inter_actions / inter_views) if inter_views > 0 else None

    # Comments on their own, per 1,000 views. Likes dominate the combined rate
    # (often 20:1), so the combined number mostly measures likes; comments are
    # the closer proxy for "this audience has something to say / ask".
    comment_rows = [r for r in viewed if not r.get("comments_hidden")]
    c_views = sum(_int(r["view_count"]) for r in comment_rows)
    comments_per_1k = ((sum(_int(r.get("comment_count")) for r in comment_rows)
                        / c_views * 1000) if c_views > 0 else None)

    # ── shape of the set: how long, how fresh ────────────────────────────
    duration_rows = [r for r in rows if _int(r.get("duration_s")) > 0]
    duration_mix = {key: 0 for _lo, _hi, key in DURATION_BUCKETS}
    for r in duration_rows:
        duration_mix[_bucket(_int(r["duration_s"]), DURATION_BUCKETS)] += 1

    recency_mix = {key: 0 for _lo, _hi, key in RECENCY_BUCKETS}
    dated_rows = 0
    for r in rows:
        age_days = _row_age_days(r)
        if age_days is None:
            continue
        dated_rows += 1
        recency_mix[_bucket(age_days, RECENCY_BUCKETS)] += 1

    shorts = sum(1 for r in rows if r.get("is_short"))

    # ── who holds the set ────────────────────────────────────────────────
    # Concentration matters: 50 results from 4 channels is an established niche
    # with incumbents; 50 from 45 channels is an open one. Same list, opposite
    # decisions, and neither is visible from a sorted grid.
    channel_views = Counter()
    channel_names = {}
    for r in viewed:
        cid = str(r.get("channel_id") or r.get("channel_title") or "")
        if not cid:
            continue
        channel_views[cid] += _int(r["view_count"])
        channel_names.setdefault(cid, str(r.get("channel_title") or "—"))
    channel_rows = Counter(str(r.get("channel_id") or r.get("channel_title") or "")
                           for r in rows)
    channel_rows.pop("", None)
    top_channels = [{
        "channel_id": cid,
        "title": channel_names.get(cid, "—"),
        "videos": channel_rows.get(cid, 0),
        "views": v,
        "share": (v / total_views) if total_views else 0.0,
    } for cid, v in channel_views.most_common(5)]

    # ── leaders: two different kinds of "winning" ────────────────────────
    # velocity  = views per hour, so a fresh video can out-rank an old giant.
    # multiplier= views ÷ subscribers, i.e. reach beyond the existing audience —
    #             the closest public proxy for "the algorithm pushed this".
    velocity_leaders = [{
        "video_id": r.get("video_id", ""),
        "title": r.get("title", ""),
        "channel_title": r.get("channel_title", ""),
        "thumbnail_url": r.get("thumbnail_url", ""),
        "video_url": r.get("video_url", ""),
        "views": _int(r.get("view_count")),
        "value": v,
    } for r, v in _leaders(rows, "velocity")]

    breakout_leaders = [{
        "video_id": r.get("video_id", ""),
        "title": r.get("title", ""),
        "channel_title": r.get("channel_title", ""),
        "thumbnail_url": r.get("thumbnail_url", ""),
        "video_url": r.get("video_url", ""),
        "views": _int(r.get("view_count")),
        "subscriber_count": r.get("subscriber_count"),
        "value": v,
    } for r, v in _leaders(rows, "multiplier")]

    set_median = _median(views)
    size_tiers = _size_tiers(viewed, set_median)
    small = next((t for t in size_tiers if t["key"] == "under_10k"), None)
    sized_rows = sum(t["rows"] for t in size_tiers)

    return {
        "snapshot_key": snapshot_key(rows),
        "query": str(query or ""),
        "mode": str(mode or "keyword"),
        "total_videos": total,
        "shorts": shorts,
        "long_form": total - shorts,

        "total_views": total_views,
        "avg_views": _mean(views),
        "median_views": _median(views),
        # How far the average sits from the median, as a ratio. > ~1.5 means the
        # set is outlier-driven and the average should not be quoted alone.
        "skew": ((_mean(views) / _median(views))
                 if views and _median(views) else None),
        "median_daily_views": _median(daily),
        "top_views": max(views) if views else None,

        "interaction_rate": interaction_rate,
        "interaction_rows": len(complete),
        "comments_per_1k": comments_per_1k,
        "comment_rows": len(comment_rows),

        # Shorts and long-form read separately (see _format_split).
        "format_split": _format_split(viewed),

        # Can a small channel win here? Tiers by public subscriber count.
        "size_tiers": size_tiers,
        "sized_rows": sized_rows,
        "small_rows": small["rows"] if small else 0,
        "small_beat_median": small["beat_median"] if small else 0,

        # Outliers against each video's OWN channel baseline.
        "outliers": _outliers(viewed),

        "languages": _languages(rows),
        "title_shape": _title_shape(rows),

        "duration_mix": duration_mix,
        "duration_rows": len(duration_rows),
        "median_duration_s": _median([_int(r["duration_s"]) for r in duration_rows]),
        "recency_mix": recency_mix,
        "dated_rows": dated_rows,

        "unique_channels": len(channel_rows),
        "top_channels": top_channels,
        "top_channel_share": top_channels[0]["share"] if top_channels else None,

        "velocity_leaders": velocity_leaders,
        "breakout_leaders": breakout_leaders,
        "topics": _topic_chips(rows),

        # What the snapshot could actually see. Every one of these is a count of
        # rows, so the UI can render "N of total" beside the metric it feeds.
        "coverage": {
            "views": len(viewed),
            "interaction": len(complete),
            "subscribers": sum(1 for r in rows
                               if r.get("subscriber_count") and not r.get("subs_hidden")),
            "duration": len(duration_rows),
            "published": dated_rows,
            "tags": sum(1 for r in rows if isinstance(r.get("tags"), list) and r["tags"]),
            "captions": sum(1 for r in rows if r.get("has_captions") is True),
            "hd": sum(1 for r in rows if str(r.get("definition") or "").lower() == "hd"),
            "channel_baseline": sum(1 for r in rows if _channel_baseline(r)),
        },
    }

def verdict_line(snap):
    """One plain sentence naming what the set looks like — computed, not written
    by a model, so it is safe to show before (or without) an AI brief.

    Deliberately narrow: it reports concentration, skew and freshness, which are
    the three readings a sorted grid hides. It makes no recommendation."""
    if not snap:
        return ""
    total = snap["total_videos"]
    parts = []

    uniq = snap.get("unique_channels") or 0
    if uniq:
        share = snap.get("top_channel_share") or 0
        if uniq <= max(3, total * 0.15):
            parts.append(tr("{n} videos from only {c} channels — concentrated.")
                         .format(n=total, c=uniq))
        elif share >= 0.4:
            parts.append(tr("{n} videos, but one channel holds {p}% of the views.")
                         .format(n=total, p=int(share * 100)))
        else:
            parts.append(tr("{n} videos spread across {c} channels.")
                         .format(n=total, c=uniq))

    # Small channels: the reading a new creator cares about most.
    if snap.get("sized_rows", 0) >= 5:
        if snap.get("small_beat_median", 0) >= 2:
            parts.append(tr("{k} videos from channels under 10K subscribers beat "
                            "the median — small channels can win here.")
                         .format(k=snap["small_beat_median"]))
        elif snap.get("small_rows", 0) == 0:
            parts.append(tr("No channel under 10K subscribers made this list."))

    split = snap.get("format_split") or {}
    if split.get("mixed") and split.get("shorts_median") and split.get("long_median"):
        ratio = split["shorts_median"] / split["long_median"]
        if ratio >= 3 or ratio <= 1 / 3.0:
            parts.append(tr("Shorts and long-form behave very differently here — "
                            "read them separately."))

    skew = snap.get("skew")
    if skew and skew >= 1.5:
        parts.append(tr("Outlier-driven: the average is {x}× the median, "
                        "so read the median.").format(x=round(skew, 1)))
    # (An evenly spread set no longer gets its own sentence: "nothing unusual"
    # is not worth one of the cover line's four slots.)

    fresh = (snap.get("recency_mix") or {}).get("last_7d", 0) + \
            (snap.get("recency_mix") or {}).get("8_30d", 0)
    if snap.get("dated_rows"):
        if fresh >= snap["dated_rows"] * 0.5:
            parts.append(tr("Mostly recent uploads — this is an active topic."))
        elif fresh == 0:
            parts.append(tr("Nothing here is from the last 30 days."))

    langs = snap.get("languages") or {}
    if langs.get("rows", 0) >= 10 and langs.get("top"):
        lang, count = langs["top"][0]
        if count >= langs["rows"] * 0.8:
            parts.append(tr("{p}% of the videos with a declared language are in “{l}”.")
                         .format(p=int(count / langs["rows"] * 100), l=lang))

    # The cover line stays a line: at most four readings, in the order a
    # creator decides with them (who owns it, can I win, which format, is the
    # average lying, is it alive, which language).
    return " ".join(parts[:4])

def duration_label(key):
    """Bucket token → the label the UI shows. Translated at read time, so a
    stored report follows the current UI language."""
    return {
        "under_1m": tr("Under 1 min"),
        "1_3m": tr("1–3 min"),
        "3_10m": tr("3–10 min"),
        "10_20m": tr("10–20 min"),
        "over_20m": tr("Over 20 min"),
    }.get(key, key)

def size_label(key):
    return {
        "under_10k": tr("Under 10K subs"),
        "10k_100k": tr("10K–100K subs"),
        "100k_1m": tr("100K–1M subs"),
        "over_1m": tr("Over 1M subs"),
    }.get(key, key)

def recency_label(key):
    return {
        "last_7d": tr("Last 7 days"),
        "8_30d": tr("8–30 days"),
        "1_12m": tr("1–12 months"),
        "over_1y": tr("Over a year"),
    }.get(key, key)
