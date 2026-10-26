"""app.core.scrape_pipeline - the Scraper's network pipeline (no Qt).

v3.52 "Fast lane". What the old scrape loop did, and why it was slow:

  1. It fetched EVERY video id first (one playlistItems / search page at a
     time), and only then started on metadata. A 5,000-video channel waited
     ~100 sequential round-trips before the first row appeared.
  2. Metadata pages (videos.list, 50 ids each) were also strictly one after
     another, and each one waited for the previous page's processing.
  3. With a Long-form / Shorts filter it over-fetched up to 6x the ids UP
     FRONT. Through the search API that is 100 quota units per 50 ids, spent
     before a single video was checked.
  4. Only the primary API key was ever used. The backup keys in Settings were
     counted by the "quota left" check but a run still died the moment the
     primary key ran out, and a run whose primary was already spent could not
     start at all even with full backups.
  5. Responses carried the full snippet (thumbnails, localizations, ...)
     although the export reads seven fields.

What this module does instead:

  * KeyRing     one service per worker thread per key (httplib2 is not
                thread-safe), automatic rotation to the next key with quota
                left, a per-request timeout, and a "wait for the internet"
                mode so a Wi-Fi drop pauses the run instead of killing it.
  * id pages    are STREAMED: metadata for page 1 is downloading while page 2
                of the id list is still being fetched.
  * MetadataAhead keeps up to `depth` videos.list pages in flight on a small
                pool and hands them back strictly in order, so the export
                order and the log are unchanged.
  * partial responses (`fields=`): same quota, a fraction of the bytes. If a
                server ever rejects the field mask (400), the ring drops it
                for the rest of the run and retries the call without it.

Quota cost is unchanged per call; the format filter now usually costs LESS
because ids are only fetched until enough matching videos were found.
"""

import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutTimeout

from googleapiclient.errors import HttpError

from app.core.youtube_api import (QuotaExceededError, ScrapeCancelled,
                                  build_youtube_service, execute_with_retry)

CHUNK = 50                      # ids per videos.list call (API maximum)
REQUEST_TIMEOUT_S = 25          # per HTTP request (googleapiclient default: 60)
OFFLINE_WAIT_S = 300            # how long a run waits for a dropped connection
MAX_OLDEST_PAGES = 400          # 400 x 50 = 20 000 videos

VIDEO_PARTS = "snippet,statistics,contentDetails"
# Exactly what _row_from_item() reads, nothing else.
VIDEO_FIELDS = ("items(id,snippet(title,publishedAt,description,tags,channelTitle),"
                "statistics(viewCount,likeCount,commentCount),"
                "contentDetails(duration))")
PLAYLIST_FIELDS = "nextPageToken,items/contentDetails/videoId"
SEARCH_FIELDS = "nextPageToken,items/id/videoId"
CHANNEL_FIELDS = ("items(contentDetails/relatedPlaylists/uploads,"
                  "statistics/videoCount)")


def _never():
    return False


class KeyRing:
    """Every configured YouTube key, used one after another.

    `keys`       primary first, then backups (duplicates/blanks are dropped).
    `remaining`  optional fn(key) -> units left today; keys with nothing left
                 are moved to the back (the local ledger is best-effort, so
                 they are still tried as a last resort).
    `on_rotate`  fn(new_index_1_based, total) after a key switch.
    `on_offline` fn(lost: bool) once when the connection drops, once when it
                 is back (shared by all worker threads, never repeated).
    """

    def __init__(self, keys, remaining=None, on_rotate=None, on_offline=None,
                 timeout=REQUEST_TIMEOUT_S, offline_wait=OFFLINE_WAIT_S):
        ordered = []
        for k in keys or []:
            k = str(k or "").strip()
            if k and k not in ordered:
                ordered.append(k)
        if remaining is not None and len(ordered) > 1:
            def _left(k):
                try:
                    return int(remaining(k))
                except Exception:          # noqa: BLE001 — ledger is cosmetic
                    return 1
            live = [k for k in ordered if _left(k) > 0]
            ordered = live + [k for k in ordered if k not in live]
        self._keys = ordered
        self._i = 0
        self._gen = 0
        self._exhausted = not ordered
        self._lock = threading.Lock()
        self._tls = threading.local()
        self._timeout = timeout
        self._offline_wait = offline_wait
        self._on_rotate = on_rotate
        self._on_offline = on_offline
        self._offline = False
        self.fields_ok = True

    # ── state ──────────────────────────────────────────────────────────
    @property
    def key_count(self):
        return len(self._keys)

    @property
    def key_number(self):
        """1-based index of the key in use (for the log, never the key)."""
        return self._i + 1

    # ── internals ──────────────────────────────────────────────────────
    def _snapshot(self):
        with self._lock:
            if self._exhausted:
                raise QuotaExceededError("every configured key is out of quota")
            return self._gen, self._keys[self._i]

    def _service(self, gen, key):
        tls = self._tls
        if getattr(tls, "gen", None) != gen or getattr(tls, "yt", None) is None:
            tls.yt = build_youtube_service(key, timeout=self._timeout)
            tls.gen = gen
        return tls.yt

    def _rotate(self, gen):
        with self._lock:
            if gen != self._gen:          # another thread already moved on
                return
            if self._i + 1 >= len(self._keys):
                self._exhausted = True
                raise QuotaExceededError("every configured key is out of quota")
            self._i += 1
            self._gen += 1
            number, total = self._i + 1, len(self._keys)
        if self._on_rotate:
            try:
                self._on_rotate(number, total)
            except Exception:              # noqa: BLE001
                pass

    def _offline_event(self, exc):
        lost = exc is not None
        with self._lock:
            if self._offline == lost:
                return
            self._offline = lost
        if self._on_offline:
            try:
                self._on_offline(lost)
            except Exception:              # noqa: BLE001
                pass

    # ── public ─────────────────────────────────────────────────────────
    def call(self, build_request, stop_check=None, fields=None):
        """Execute `build_request(yt, **extra)` with retries, key rotation
        and (optionally) a partial-response field mask."""
        while True:
            gen, key = self._snapshot()
            yt = self._service(gen, key)
            use_fields = fields if (fields and self.fields_ok) else None
            extra = {"fields": use_fields} if use_fields else {}
            try:
                return execute_with_retry(
                    build_request(yt, **extra), stop_check,
                    offline_wait=self._offline_wait,
                    on_offline=self._offline_event)
            except QuotaExceededError:
                self._rotate(gen)
            except HttpError as exc:
                status = getattr(getattr(exc, "resp", None), "status", None)
                if use_fields and status == 400:
                    # never let an optimisation break a run
                    self.fields_ok = False
                    continue
                raise

    def run(self, fn, stop_check=None):
        """`fn(yt)` that makes its own calls (e.g. resolve_channel_id), re-run
        on the next key if the current one runs out of quota."""
        while True:
            gen, key = self._snapshot()
            try:
                return fn(self._service(gen, key))
            except QuotaExceededError:
                self._rotate(gen)


# ═════════════════════════════════════════════════════════════════════════
#  id sources (generators of id pages)
# ═════════════════════════════════════════════════════════════════════════
def channel_info(ring, channel_id, stop_check=None):
    """(uploads_playlist_id, video_count) in one 1-unit call."""
    resp = ring.call(
        lambda yt, **kw: yt.channels().list(
            part="contentDetails,statistics", id=channel_id, **kw),
        stop_check, fields=CHANNEL_FIELDS)
    items = resp.get("items") or []
    if not items:
        return None, 0
    it = items[0] or {}
    uploads = (((it.get("contentDetails") or {}).get("relatedPlaylists") or {})
               .get("uploads"))
    try:
        count = int((it.get("statistics") or {}).get("videoCount") or 0)
    except (TypeError, ValueError):
        count = 0
    return uploads, count


def iter_upload_pages(ring, uploads, limit, stop_check=_never):
    """Newest-first uploads, one list of ids per API page, `limit` ids max."""
    token, got = None, 0
    while got < limit:
        if stop_check():
            raise ScrapeCancelled()
        want = min(CHUNK, limit - got)

        def req(yt, _t=token, _n=want, **kw):
            return yt.playlistItems().list(
                part="contentDetails", playlistId=uploads, maxResults=_n,
                pageToken=_t, **kw)
        resp = ring.call(req, stop_check, fields=PLAYLIST_FIELDS)
        ids = [((it or {}).get("contentDetails") or {}).get("videoId")
               for it in resp.get("items") or []]
        ids = [v for v in ids if v][:limit - got]
        got += len(ids)
        if ids:
            yield ids
        token = resp.get("nextPageToken")
        if not token:
            return


def iter_search_pages(ring, channel_id, limit, order, query, stop_check=_never,
                      published_after=None):
    """search.list pages (100 units each). Pulled lazily by the consumer, so
    a run that finds enough videos early stops paying for more pages.

    published_after (v3.54): RFC 3339 timestamp; YouTube then only returns
    videos newer than it (the Scraper's "Published" window)."""
    token, got = None, 0
    while got < limit:
        if stop_check():
            raise ScrapeCancelled()
        want = min(CHUNK, limit - got)

        def req(yt, _t=token, _n=want, **kw):
            args = dict(part="id", channelId=channel_id, maxResults=_n,
                        order=order, type="video", pageToken=_t)
            if query:
                args["q"] = query
            if published_after:
                args["publishedAfter"] = published_after
            args.update(kw)
            return yt.search().list(**args)
        resp = ring.call(req, stop_check, fields=SEARCH_FIELDS)
        ids = [((it or {}).get("id") or {}).get("videoId")
               for it in resp.get("items") or []]
        ids = [v for v in ids if v][:limit - got]
        got += len(ids)
        if ids:
            yield ids
        token = resp.get("nextPageToken")
        if not token:
            return


def iter_oldest_pages(ring, uploads, limit, stop_check=_never, log=None):
    """The channel's OLDEST uploads, oldest first. The API has no ascending
    order, so the uploads playlist is walked to its end (1 unit per 50) and
    the tail is handed out reversed."""
    ids, token, pages = [], None, 0
    while pages < MAX_OLDEST_PAGES:
        if stop_check():
            raise ScrapeCancelled()

        def req(yt, _t=token, **kw):
            return yt.playlistItems().list(
                part="contentDetails", playlistId=uploads, maxResults=CHUNK,
                pageToken=_t, **kw)
        resp = ring.call(req, stop_check, fields=PLAYLIST_FIELDS)
        for it in resp.get("items") or []:
            vid = ((it or {}).get("contentDetails") or {}).get("videoId")
            if vid:
                ids.append(vid)
        pages += 1
        token = resp.get("nextPageToken")
        if not token:
            break
        if log and pages % 10 == 0:
            log("walk", len(ids))
    if pages >= MAX_OLDEST_PAGES and token and log:
        log("cap", len(ids))
    oldest = list(reversed(ids))[:limit]
    for i in range(0, len(oldest), CHUNK):
        yield oldest[i:i + CHUNK]


class ChunkFeed:
    """Regroups id pages into CHUNK-sized lists of ids still to do: drops
    duplicates and ids already restored from a checkpoint. Pull-based, so
    nothing is fetched before the consumer asks for it."""

    def __init__(self, pages, skip=None, size=CHUNK):
        self._pages = iter(pages)
        self._skip = set(skip or ())
        self._seen = set()
        self._buf = deque()
        self._size = size
        self.seen = 0          # raw ids received (resumed ones included)
        self.queued = 0        # ids handed out
        self.skipped = 0       # restored from the checkpoint
        self.exhausted = False

    def next(self):
        while len(self._buf) < self._size and not self.exhausted:
            try:
                page = next(self._pages)
            except StopIteration:
                self.exhausted = True
                break
            for vid in page:
                if vid in self._seen:
                    continue
                self._seen.add(vid)
                self.seen += 1
                if vid in self._skip:
                    self.skipped += 1
                    continue
                self._buf.append(vid)
        if not self._buf:
            return None
        n = min(self._size, len(self._buf))
        chunk = [self._buf.popleft() for _ in range(n)]
        self.queued += len(chunk)
        return chunk


def fetch_metadata(ring, chunk, stop_check=None):
    """{video_id: videos.list item} for one chunk (1 unit)."""
    ids = ",".join(chunk)
    resp = ring.call(
        lambda yt, **kw: yt.videos().list(part=VIDEO_PARTS, id=ids, **kw),
        stop_check, fields=VIDEO_FIELDS)
    return {it.get("id"): it for it in resp.get("items") or [] if it}


class _Ready:
    """A finished 'future' for the no-prefetch path."""

    def __init__(self, value=None, exc=None):
        self._v, self._e = value, exc

    def result(self, timeout=None):
        if self._e is not None:
            raise self._e
        return self._v

    def cancel(self):
        return False


class MetadataAhead:
    """videos.list pages fetched ahead of the consumer, returned in order.

    depth    pages kept in flight (1 = no prefetch, fully lazy).
    prefetch when False, the id feed is only advanced when the consumer asks
             for the next chunk (used for search + format filter, where every
             extra id page costs 100 units).
    """

    def __init__(self, ring, feed, stop_check=_never, depth=3, prefetch=True):
        self._ring = ring
        self._feed = feed
        self._stop = stop_check
        self._depth = max(1, int(depth))
        self._prefetch = prefetch and self._depth > 1
        self._pool = (ThreadPoolExecutor(max_workers=self._depth,
                                         thread_name_prefix="meta")
                      if self._prefetch else None)
        self._q = deque()

    def _submit(self, chunk):
        if self._pool is not None:
            return self._pool.submit(fetch_metadata, self._ring, chunk, self._stop)
        try:
            return _Ready(fetch_metadata(self._ring, chunk, self._stop))
        except Exception as exc:           # noqa: BLE001 — re-raised in order
            return _Ready(exc=exc)

    def _top_up(self, want):
        while len(self._q) < want:
            chunk = self._feed.next()
            if chunk is None:
                return
            self._q.append((chunk, self._submit(chunk)))

    def next(self):
        """(chunk, {id: item}) for the next chunk in order, or None."""
        if not self._q:
            self._top_up(1)
        if not self._q:
            return None
        chunk, fut = self._q.popleft()
        if self._prefetch:
            # Fetch the next id page(s) while this page's metadata downloads.
            # Ramps up by two per call, so the first row is not held back
            # behind `depth` sequential id pages.
            self._top_up(min(self._depth, len(self._q) + 2))
        while True:
            try:
                items = fut.result(timeout=0.25)
                break
            except FutTimeout:
                if self._stop():
                    raise ScrapeCancelled()
        return chunk, items

    def close(self):
        for _c, fut in self._q:
            try:
                fut.cancel()
            except Exception:              # noqa: BLE001
                pass
        self._q.clear()
        if self._pool is not None:
            self._pool.shutdown(wait=False, cancel_futures=True)
            self._pool = None


class Throttle:
    """True at most once per `interval` seconds (or when forced)."""

    def __init__(self, interval):
        self._interval = interval
        self._last = 0.0

    def ready(self, force=False):
        now = time.monotonic()
        if force or now - self._last >= self._interval:
            self._last = now
            return True
        return False
