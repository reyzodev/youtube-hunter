"""app.core.youtube_api - Youtube Scrapper."""

import json
import random
import re
import time
from googleapiclient.errors import HttpError

# ═════════════════════════════════════════════════════════════════════════
#  YOUTUBE DATA API — HARDENED NETWORK LAYER
#  ---------------------------------------------------------------------
#  * one service object per scrape run (static discovery, no network fetch)
#  * every .execute() goes through execute_with_retry(): transient errors
#    (5xx / 429 / rate-limit / socket drops) are retried with exponential
#    backoff, while real quota exhaustion aborts cleanly with a clear,
#    user-readable message instead of silently failing every video.
# ═════════════════════════════════════════════════════════════════════════
class ScrapeCancelled(Exception):
    """User pressed EMERGENCY STOP (or closed the window)."""


class QuotaExceededError(Exception):
    """Daily YouTube API quota is used up — retrying is pointless."""


_TRANSIENT_REASONS = {"rateLimitExceeded", "userRateLimitExceeded",
                       "backendError", "internalError", "internalServerError"}
_QUOTA_REASONS = {"quotaExceeded", "dailyLimitExceeded"}


def build_youtube_service(api_key):
    """The one place a YouTube service object is created.

    `googleapiclient.discovery` is imported HERE rather than at module scope on
    purpose. Measured on this app: it is the single most expensive import in the
    whole program — about 17 MB of resident memory and 0.9 s of startup — and
    nothing needs it until the first API call. Deferring it opens the window
    about a second sooner on a slow machine, and a web-scrape session that never
    builds a service never pays for it at all. (The `errors` module stays at
    module scope: it is a tenth of the cost and is needed by an `except` clause,
    which cannot resolve a lazily-bound name.)
    """
    from googleapiclient.discovery import build
    return build("youtube", "v3", developerKey=api_key,
                 cache_discovery=False, static_discovery=True)


def _http_error_reasons(exc):
    """Extract the machine-readable reason codes from an HttpError."""
    try:
        payload = json.loads(exc.content.decode("utf-8"))
        errs = payload.get("error", {}).get("errors", [])
        return {e.get("reason", "") for e in errs}
    except Exception:
        return set()


def _sleep_interruptible(seconds, stop_check=None):
    """Sleep in small slices so EMERGENCY STOP stays responsive."""
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if stop_check and stop_check():
            raise ScrapeCancelled()
        time.sleep(0.15)


def execute_with_retry(request, stop_check=None, attempts=4):
    """Run a googleapiclient request with bounded retries + backoff."""
    delay = 1.5
    last_exc = None
    for attempt in range(attempts):
        if stop_check and stop_check():
            raise ScrapeCancelled()
        try:
            return request.execute()
        except HttpError as exc:
            reasons = _http_error_reasons(exc)
            if reasons & _QUOTA_REASONS:
                raise QuotaExceededError(str(exc))
            status = getattr(getattr(exc, "resp", None), "status", None)
            transient = (status in (429, 500, 502, 503, 504)
                         or bool(reasons & _TRANSIENT_REASONS))
            if not transient or attempt == attempts - 1:
                raise
            last_exc = exc
        except (ScrapeCancelled, QuotaExceededError):
            raise
        except Exception as exc:
            # socket resets, SSL hiccups, DNS blips, httplib2 errors …
            if attempt == attempts - 1:
                raise
            last_exc = exc
        _sleep_interruptible(delay + random.uniform(0, 0.7), stop_check)
        delay *= 2
    if last_exc:
        raise last_exc


def _row_from_item(video_id, item):
    """Build an export row from a videos().list item (defensive .get()s —
    YouTube occasionally omits statistics/contentDetails fields)."""
    snip = item.get("snippet", {}) or {}
    stats = item.get("statistics", {}) or {}
    cdet = item.get("contentDetails", {}) or {}
    return {
        "title":             snip.get("title", "N/A"),
        "video_id":          video_id,
        "url":               f"https://www.youtube.com/watch?v={video_id}",
        "view_count":        stats.get("viewCount", 0),
        "like_count":        stats.get("likeCount", 0),
        "comment_count":     stats.get("commentCount", 0),
        "publish_date":      snip.get("publishedAt", ""),
        "duration":          cdet.get("duration", ""),
        "description":       snip.get("description") or "N/A",
        "tags":              ", ".join(snip.get("tags", [])) or "N/A",
        "transcript_status": "Not Available",
        "transcript":        "N/A",
        "structured_prompt": "",
    }
_VIDEO_URL_RES = (
    re.compile(r"[?&]v=([\w-]{6,})"),
    re.compile(r"youtu\.be/([\w-]{6,})"),
    re.compile(r"/shorts/([\w-]{6,})"),
    re.compile(r"/live/([\w-]{6,})"),
)


def resolve_channel_id(yt, text, stop_check=None):
    """Resolve URL / @handle / /user/ / /c/ / bare name / channel ID / video
    link to a channel ID. Uses exact channels().list lookups first (accurate
    AND 1 quota unit) and only falls back to search as a last resort."""
    text = (text or "").strip()
    if not text:
        return None

    if "/channel/" in text:
        return text.split("/channel/")[1].split("/")[0].split("?")[0]
    if re.fullmatch(r"UC[\w-]{20,}", text):
        return text

    # a video link? → its snippet tells us the channel
    for rx in _VIDEO_URL_RES:
        m = rx.search(text)
        if m:
            resp = execute_with_retry(
                yt.videos().list(part="snippet", id=m.group(1)), stop_check)
            items = resp.get("items", [])
            if items:
                return items[0]["snippet"]["channelId"]
            break

    handle = None
    legacy_username = None
    if "@" in text:
        handle = text.split("@")[-1].split("/")[0].split("?")[0]
    elif "/user/" in text:
        legacy_username = text.rstrip("/").split("/")[-1].split("?")[0]
    elif "/c/" in text:
        handle = text.rstrip("/").split("/")[-1].split("?")[0]
    elif not text.lower().startswith("http"):
        handle = text.lstrip("@")

    if legacy_username:
        try:
            resp = execute_with_retry(
                yt.channels().list(part="id", forUsername=legacy_username), stop_check)
            if resp.get("items"):
                return resp["items"][0]["id"]
        except (ScrapeCancelled, QuotaExceededError):
            raise
        except Exception:
            pass
        handle = legacy_username

    if handle:
        try:
            resp = execute_with_retry(
                yt.channels().list(part="id", forHandle=handle), stop_check)
            if resp.get("items"):
                return resp["items"][0]["id"]
        except (ScrapeCancelled, QuotaExceededError):
            raise
        except Exception:
            pass
        # last resort: search (least accurate, 100 quota units)
        resp = execute_with_retry(
            yt.search().list(part="snippet", q=handle, type="channel",
                              maxResults=1), stop_check)
        if resp.get("items"):
            return resp["items"][0]["snippet"]["channelId"]
    return None
