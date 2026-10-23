"""app.core.niche.sorting - Youtube Scrapper."""

import re

from app.core.niche.helpers import _DIGIT_MAP, _NUM_SUFFIXES

_NICHE_SORTS = {
    "multiplier":       lambda r: (r.get("multiplier") or -1),
    "view_count":       lambda r: (r.get("view_count") or 0),
    # Views ascending — the channel-scan "Low → High" toggle. Same values as
    # view_count, opposite direction (see _NICHE_SORTS_ASCENDING).
    "view_count_asc":   lambda r: (r.get("view_count") or 0),
    "velocity":         lambda r: (r.get("velocity") or 0),
    "subscriber_count": lambda r: (r.get("subscriber_count")
                                   if r.get("subscriber_count") is not None else 10 ** 12),
    # Tuple key: primarily ascending subscriber count (hidden-sub channels
    # sink to the bottom, same as plain "Smallest Channel First"), and
    # WITHIN a given subscriber count the higher view count sorts first —
    # the negation is what turns "higher views" into an ascending
    # comparison so the whole tuple can sort one direction (see reverse=
    # False below).
    "small_high_view":  lambda r: ((r.get("subscriber_count")
                                    if r.get("subscriber_count") is not None
                                    and not r.get("subs_hidden") else 10 ** 12),
                                   -(r.get("view_count") or 0)),
    "published_at":     lambda r: -(r.get("age_hours") or 10 ** 9),
    "engagement":       lambda r: (r.get("engagement") or 0),
    # Gold Score (app.core.niche.gold), views as the tie-break. Rows from an
    # archive saved before v1.1 have no score yet and sink to the bottom.
    "gold":             lambda r: (r.get("gold_score") or 0, r.get("view_count") or 0),
}

# Sort keys whose comparable value is already oriented so plain ascending
# order gives the right result ("smallest first", "fewest first"); everything
# else wants descending ("biggest/most/newest first").
_NICHE_SORTS_ASCENDING = {"subscriber_count", "small_high_view", "view_count_asc"}


def sort_niche_rows(rows, key="multiplier"):
    fn = _NICHE_SORTS.get(key, _NICHE_SORTS["multiplier"])
    reverse = key not in _NICHE_SORTS_ASCENDING
    return sorted(rows, key=fn, reverse=reverse)


def sort_archive_quick(rows, subs_dir, views_dir):
    """ArchiveRangeFilterPopup's Views/Subscribers low↔high buttons — unlike
    the fixed combo above, either axis can be picked on its own OR together.
    Together, Subscribers is the grouping key and Views breaks ties within
    it (same idea as the built-in "Smallest Channel · Highest Views" sort,
    just letting either axis run in either direction instead of only that
    one fixed combination). subs_dir / views_dir are each "asc", "desc", or
    None; returns rows unchanged (well, unsorted) if both are None — callers
    should treat that as "no override, use the regular sort combo".
    """
    def subs_val(r):
        v = r.get("subscriber_count")
        if v is None or r.get("subs_hidden"):
            return 10 ** 12  # unknown/hidden subs always sink to the bottom
        return -v if subs_dir == "desc" else v

    def views_val(r):
        v = r.get("view_count") or 0
        return -v if views_dir == "desc" else v

    if subs_dir and views_dir:
        key_fn = lambda r: (subs_val(r), views_val(r))
    elif subs_dir:
        key_fn = subs_val
    else:
        key_fn = views_val
    # Direction is already baked into the sign of each value above, so a
    # plain ascending sort (reverse=False) gives the right order either way.
    return sorted(rows, key=key_fn)


def aggregate_by_channel(rows):
    """Roll videos up into one row per channel — the 'which small channels
    are winning right now' view."""
    buckets = {}
    for r in rows:
        cid = r.get("channel_id") or r.get("channel_title") or "?"
        b = buckets.setdefault(cid, {
            "channel_id": r.get("channel_id", ""),
            "channel_title": r.get("channel_title", ""),
            "channel_url": r.get("channel_url", ""),
            "channel_thumb_url": r.get("channel_thumb_url", ""),
            "subscriber_count": r.get("subscriber_count"),
            "subs_hidden": r.get("subs_hidden", False),
            "channel_total_views": r.get("channel_total_views", 0),
            "channel_video_count": r.get("channel_video_count", 0),
            "video_count": 0,
            "view_count": 0,
            "best_multiplier": None,
            "best_video": None,
            "velocity": 0.0,
        })
        b["video_count"] += 1
        b["view_count"] += r.get("view_count", 0) or 0
        b["velocity"] += r.get("velocity", 0) or 0
        mult = r.get("multiplier")
        if mult is not None and (b["best_multiplier"] is None or mult > b["best_multiplier"]):
            b["best_multiplier"] = mult
        best = b["best_video"]
        if best is None or (r.get("view_count", 0) or 0) > (best.get("view_count", 0) or 0):
            b["best_video"] = r
    out = []
    for b in buckets.values():
        subs = b.get("subscriber_count")
        b["multiplier"] = (b["view_count"] / float(subs)
                           if subs and not b.get("subs_hidden") else None)
        b["title"] = b["channel_title"]
        bv = b.get("best_video") or {}
        b["thumbnail_url"] = bv.get("thumbnail_url", "")
        b["video_url"] = bv.get("video_url", "")
        b["published_at"] = bv.get("published_at")
        b["age_hours"] = bv.get("age_hours")
        b["is_short"] = bv.get("is_short", False)
        b["outlier_ratio"] = bv.get("outlier_ratio", 0)
        out.append(b)
    return out


def parse_human_float(text, default=None):
    """Like parse_human_number but keeps decimals ('1.5' → 1.5)."""
    if text is None:
        return default
    s = str(text).strip().translate(_DIGIT_MAP)
    for junk in (",", "٬", "،", " ", "‌", "_"):
        s = s.replace(junk, "")
    if not s:
        return default
    m = re.match(r"^([0-9]*\.?[0-9]+)([A-Za-z؀-ۿ]*)$", s)
    if not m:
        return default
    try:
        val = float(m.group(1))
    except ValueError:
        return default
    suf = (m.group(2) or "").lower()
    if suf:
        for key, factor in _NUM_SUFFIXES:
            if suf.startswith(key):
                return val * factor
        return default
    return val
