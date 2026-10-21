"""app.core.niche.live_stats - YouTube Hunter.

v3.43 "Live numbers": re-read the CURRENT views / likes / comments /
subscribers for rows that were saved earlier (Search Archive sections, a
Niche Finder result served from the 12 h cache, "Open in Niche Finder").

A saved row is a snapshot of the moment it was found. Two days later its
views, its views ÷ subs multiplier and its views-per-hour are all wrong, and
the Archive cards used to show those old numbers as if they were current.

Cost: videos.list + channels.list, 1 quota unit per 50 ids each, from the
same big bucket the Niche Finder's own enrichment uses, so a 500-video
section costs ~20 units. A search.list call costs 100: refreshing is cheap.

Runs on a worker thread. Never touches Qt.
"""

from datetime import datetime, timezone

from app.config import load_app_config
from app.core.niche.search import merge_niche_row
from app.core.utils import parse_iso_utc
from app.core.youtube_api import (QuotaExceededError, ScrapeCancelled,
                                  build_youtube_service, execute_with_retry)

# A row whose live numbers are younger than this is shown as is.
STALE_AFTER_S = 5 * 60
# Ids per videos.list / channels.list call (the API's own maximum).
_CHUNK = 50

# Keys kept from the saved row: identity / bookkeeping the API doesn't know.
_KEEP_PRIVATE = ("_archive_key", "_first_seen", "_last_seen", "_is_favorite")


class LiveStatsError(Exception):
    """Raised with code 'nokey' | 'quota' | 'error'."""

    def __init__(self, code, message=""):
        super().__init__(message or code)
        self.code = code


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def youtube_api_keys(cfg=None):
    """Primary key first, then the backups, without duplicates or blanks."""
    cfg = cfg if cfg is not None else load_app_config()
    out = []
    for k in [cfg.get("api_key", "")] + list(cfg.get("youtube_api_keys") or []):
        k = str(k or "").strip()
        if k and k not in out:
            out.append(k)
    return out


def stats_age_s(row):
    """Seconds since this row's numbers were read from YouTube, or None."""
    dt = parse_iso_utc(row.get("_stats_at") or "")
    if dt is None:
        return None
    return max(0.0, (datetime.now(timezone.utc) - dt).total_seconds())


def is_stale(row, max_age_s=STALE_AFTER_S):
    age = stats_age_s(row)
    return age is None or age > max_age_s


class _Client:
    """One YouTube service with automatic rotation to the next backup key
    when the current key's daily quota is used up."""

    def __init__(self, keys):
        self._keys = list(keys)
        self._i = 0
        self._yt = None
        if not self._keys:
            raise LiveStatsError("nokey")

    def _service(self):
        if self._yt is None:
            self._yt = build_youtube_service(self._keys[self._i])
        return self._yt

    def call(self, make_request, stop_check):
        while True:
            try:
                return execute_with_retry(make_request(self._service()),
                                          stop_check)
            except QuotaExceededError:
                self._i += 1
                self._yt = None
                if self._i >= len(self._keys):
                    raise LiveStatsError("quota")


def refresh_rows_live(rows, keys=None, stop_check=None, on_chunk=None):
    """Re-read live stats for `rows` (dicts with a `video_id`).

    `on_chunk(list_of_fresh_rows)` is called after every 50 videos, so a
    caller can show the first page while the rest is still loading (pass the
    visible rows first). Each fresh row is the saved row with the API's
    current numbers merged on top, plus:
        _stats_at      when these numbers were read (UTC ISO)
        _live_missing  True when YouTube no longer returns the video
                       (deleted / made private); its old numbers are kept.

    Returns the full list of fresh rows. Raises LiveStatsError for a missing
    key or exhausted quota, ScrapeCancelled when stop_check() turns True.
    """
    client = _Client(keys if keys is not None else youtube_api_keys())
    todo = [r for r in rows or [] if (r or {}).get("video_id")]
    channels = {}                       # channel_id -> API item (shared)
    out = []
    for i in range(0, len(todo), _CHUNK):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        chunk = todo[i:i + _CHUNK]
        ids = list(dict.fromkeys(r["video_id"] for r in chunk))
        resp = client.call(
            lambda yt, ids=ids: yt.videos().list(
                part="snippet,statistics,contentDetails", id=",".join(ids)),
            stop_check)
        v_map = {v.get("id"): v for v in resp.get("items", []) or []}

        want = []
        for v in v_map.values():
            cid = (v.get("snippet") or {}).get("channelId")
            if cid and cid not in channels and cid not in want:
                want.append(cid)
        for j in range(0, len(want), _CHUNK):
            part = want[j:j + _CHUNK]
            c_resp = client.call(
                lambda yt, part=part: yt.channels().list(
                    part="snippet,statistics", id=",".join(part)),
                stop_check)
            for c in c_resp.get("items", []) or []:
                channels[c.get("id")] = c

        stamp = now_iso()
        fresh_chunk = []
        for base in chunk:
            v = v_map.get(base["video_id"])
            if v is None:
                row = dict(base)
                row["_live_missing"] = True
            else:
                cid = (v.get("snippet") or {}).get("channelId") or base.get("channel_id")
                row = merge_niche_row(base, v, channels.get(cid))
                row["_live_missing"] = False
                for k in _KEEP_PRIVATE:
                    if k in base:
                        row[k] = base[k]
            row["_stats_at"] = stamp
            fresh_chunk.append(row)
        out.extend(fresh_chunk)
        if on_chunk:
            on_chunk(fresh_chunk)
    return out
