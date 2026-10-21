"""app.core.thumbs - Youtube Scrapper."""

import hashlib
import os
import re
import threading
import urllib.parse


from app.config import CONFIG_PATH
from app.core.net import download_image_bytes

# ═════════════════════════════════════════════════════════════════════════
#  THUMBNAIL CACHE  —  in-memory + on-disk, so YouTube thumbnails that were
#  already shown once are never re-downloaded again (faster grids, works
#  offline for anything already seen, and stops hammering i.ytimg.com).
# ═════════════════════════════════════════════════════════════════════════
THUMB_CACHE_DIR = os.path.join(os.path.dirname(CONFIG_PATH), "thumb_cache")
try:
    os.makedirs(THUMB_CACHE_DIR, exist_ok=True)
except Exception:
    pass

_THUMB_MEM_CACHE = {}
_THUMB_MEM_CACHE_LOCK = threading.Lock()
_THUMB_MEM_CACHE_MAX = 600   # plenty for a session's worth of grids/cards


def _thumb_cache_path(url):
    h = hashlib.sha1(url.encode("utf-8")).hexdigest()
    ext = os.path.splitext(urllib.parse.urlparse(url).path)[1][:5]
    if not ext or len(ext) > 5 or "/" in ext:
        ext = ".jpg"
    return os.path.join(THUMB_CACHE_DIR, h + ext)


# ═════════════════════════════════════════════════════════════════════════
#  FAST GRID FETCH  (v3.39.4)
#
#  Three things made a fresh grid slow to fill:
#    1. every thumbnail opened a brand-new TCP + TLS connection (urllib has
#       no keep-alive), so ~24 cards paid ~24 handshakes;
#    2. the stored URL is often the LARGEST variant innertube returned
#       (hq720 / maxres, 60–150 KB) for a ~330px tile;
#    3. the same URL could be fetched twice at once (prefetch + the card).
#  Fixes: a per-thread keep-alive requests.Session, a grid-sized URL
#  (hqdefault, 480x360, ~20 KB), in-flight de-duplication, and a small
#  background prefetcher the VMs call when a page is rendered.
# ═════════════════════════════════════════════════════════════════════════
_YT_THUMB_RE = re.compile(r"^https?://i\d?\.ytimg\.com/(?:vi|vi_webp)/([A-Za-z0-9_-]{6,})/")


def grid_thumb_url(url):
    """The URL a GRID card should load for `url`: i.ytimg video thumbnails are
    swapped to hqdefault.jpg (always exists, ~20 KB, sharp up to ~480px even
    on a 150% display). Anything else (channel avatars, custom hosts) is
    returned unchanged. Saving a thumbnail to disk still uses the original
    url — see save_thumbnail_to()."""
    if not url:
        return url
    m = _YT_THUMB_RE.match(url)
    if not m:
        return url
    return f"https://i.ytimg.com/vi/{m.group(1)}/hqdefault.jpg"


_tls = threading.local()
_PROXY_CACHE = {"t": 0.0, "v": ""}


def _thumb_proxy():
    """The Settings proxy (cached 30s so a grid doesn't re-read config 24x)."""
    import time
    now = time.monotonic()
    if now - _PROXY_CACHE["t"] > 30:
        try:
            from app.core.net import configured_proxy
            _PROXY_CACHE["v"] = configured_proxy() or ""
        except Exception:
            _PROXY_CACHE["v"] = ""
        _PROXY_CACHE["t"] = now
    return _PROXY_CACHE["v"]


def _session():
    s = getattr(_tls, "session", None)
    if s is None:
        try:
            import requests
            from requests.adapters import HTTPAdapter
        except Exception:
            _tls.session = False
            return False
        s = requests.Session()
        s.headers.update({"User-Agent": "Mozilla/5.0",
                          "Accept": "image/avif,image/webp,image/*,*/*;q=0.8"})
        ad = HTTPAdapter(pool_connections=4, pool_maxsize=4, max_retries=0)
        s.mount("https://", ad)
        s.mount("http://", ad)
        _tls.session = s
    return s


def _fetch_bytes(url, timeout):
    """Keep-alive GET; falls back to the old urllib path if requests is
    missing or the request fails."""
    s = _session()
    if s:
        proxy = _thumb_proxy()
        proxies = {"http": proxy, "https": proxy} if proxy else None
        to = (min(4.0, timeout), timeout)      # (connect, read)
        for px in ((proxies, None) if proxies else (None,)):
            try:
                r = s.get(url, timeout=to, proxies=px)
                if r.status_code == 200 and r.content:
                    return r.content
                if r.status_code == 404:
                    return None
            except Exception:
                continue
    return download_image_bytes(url, timeout=timeout)


_INFLIGHT = {}
_INFLIGHT_LOCK = threading.Lock()


def get_cached_image_bytes(url, timeout=12):
    """Same contract as before, but concurrent callers for the same url share
    ONE network fetch instead of downloading it twice."""
    if not url:
        return None
    with _THUMB_MEM_CACHE_LOCK:
        raw = _THUMB_MEM_CACHE.get(url)
    if raw:
        return raw
    with _INFLIGHT_LOCK:
        ev = _INFLIGHT.get(url)
        owner = ev is None
        if owner:
            ev = _INFLIGHT[url] = threading.Event()
    if not owner:
        ev.wait(timeout + 2)
        with _THUMB_MEM_CACHE_LOCK:
            raw = _THUMB_MEM_CACHE.get(url)
        return raw if raw else _get_cached_image_bytes(url, timeout)
    try:
        return _get_cached_image_bytes(url, timeout)
    finally:
        with _INFLIGHT_LOCK:
            _INFLIGHT.pop(url, None)
        ev.set()


GRID_MAX_W = 520   # hqdefault is 480 wide; above this keep the original url


def get_grid_image_bytes(url, want_w=0, timeout=8):
    """Bytes for a card: the grid-sized variant first (only when the box asked
    for is small enough that hqdefault stays sharp), the original url if the
    box is big or the small variant fails. Big hero images elsewhere in the
    app therefore keep their full resolution."""
    if want_w <= 0 or want_w > GRID_MAX_W:
        return get_cached_image_bytes(url, timeout=12)
    small = grid_thumb_url(url)
    raw = get_cached_image_bytes(small, timeout=timeout) if small else None
    if not raw and small != url:
        raw = get_cached_image_bytes(url, timeout=timeout)
    return raw


# ── background prefetch ──
_PREFETCH_LOCK = threading.Lock()
_PREFETCH_POOL = None
_PREFETCH_GEN = [0]


def _prefetch_pool():
    global _PREFETCH_POOL
    with _PREFETCH_LOCK:
        if _PREFETCH_POOL is None:
            from concurrent.futures import ThreadPoolExecutor
            # small on purpose: the QML provider has its own 6 workers and we
            # must not flood i.ytimg.com.
            _PREFETCH_POOL = ThreadPoolExecutor(max_workers=3,
                                                thread_name_prefix="thumb-prefetch")
        return _PREFETCH_POOL


def _is_cached(url):
    with _THUMB_MEM_CACHE_LOCK:
        if url in _THUMB_MEM_CACHE:
            return True
    return False


def prefetch_thumbs(urls, next_urls=()):
    """Warm the cache for a page about to be shown (`urls`, in grid order)
    and, after it, the next page (`next_urls`). A newer call cancels the
    not-yet-started work of an older one, so paging fast never queues stale
    pages. Never raises, never blocks the caller."""
    try:
        with _PREFETCH_LOCK:
            _PREFETCH_GEN[0] += 1
            gen = _PREFETCH_GEN[0]
        seen = set()
        todo = []
        for u in list(urls) + list(next_urls):
            if not u:
                continue
            u = grid_thumb_url(u)
            if u in seen or _is_cached(u):
                continue
            seen.add(u)
            todo.append(u)
        if not todo:
            return
        pool = _prefetch_pool()

        def job(u):
            if _PREFETCH_GEN[0] != gen:
                return              # superseded by a newer page
            try:
                get_cached_image_bytes(u, timeout=8)
            except Exception:
                pass

        for u in todo:
            pool.submit(job, u)
    except Exception:
        pass


def _get_cached_image_bytes(url, timeout=12):
    """Image bytes for `url`, served from the fastest layer available:
    in-memory dict -> on-disk cache file -> network (which then populates
    both caches). Re-opening the app / re-showing a grid never re-fetches
    a thumbnail it has already downloaded."""
    if not url:
        return None

    with _THUMB_MEM_CACHE_LOCK:
        raw = _THUMB_MEM_CACHE.get(url)
    if raw:
        return raw

    path = _thumb_cache_path(url)
    try:
        if os.path.isfile(path):
            with open(path, "rb") as f:
                raw = f.read()
            if raw:
                _thumb_mem_cache_put(url, raw)
                return raw
    except Exception:
        pass

    raw = _fetch_bytes(url, timeout)
    if raw:
        _thumb_mem_cache_put(url, raw)
        try:
            with open(path, "wb") as f:
                f.write(raw)
        except Exception:
            pass  # disk cache is best-effort; in-memory cache still helps
    return raw


def _thumb_mem_cache_put(url, raw):
    with _THUMB_MEM_CACHE_LOCK:
        if len(_THUMB_MEM_CACHE) >= _THUMB_MEM_CACHE_MAX:
            # Cheap unbounded-growth guard: drop the oldest half. Dict
            # preserves insertion order in Python 3.7+, so this evicts the
            # least-recently-added entries first.
            for k in list(_THUMB_MEM_CACHE.keys())[:_THUMB_MEM_CACHE_MAX // 2]:
                _THUMB_MEM_CACHE.pop(k, None)
        _THUMB_MEM_CACHE[url] = raw


def _thumb_extension_for(url, raw):
    """Pick a sensible file extension for a saved thumbnail: the source URL's
    own extension when it has one, otherwise sniffed from the byte signature,
    defaulting to .jpg (what i.ytimg.com serves)."""
    ext = os.path.splitext(urllib.parse.urlparse(url or "").path)[1].lower()
    if ext in (".jpg", ".jpeg", ".png", ".webp"):
        return ext
    if raw[:8].startswith(b"\x89PNG"):
        return ".png"
    if raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return ".webp"
    return ".jpg"


def save_thumbnail_to(url, dest_path, target_size=None):
    """Download the thumbnail at `url` in the HIGHEST resolution YouTube has and
    write it to `dest_path`.

    The URL stored on a row is only a small preview (e.g. mqdefault = 320x180).
    YouTube serves the same thumbnail at several fixed sizes under
    i.ytimg.com/vi/<id>/<name>.jpg — this walks them from largest to smallest
    (maxres 1280x720 → sd 640x480 → hq 480x360 → the original url) and takes the
    first one that actually exists, so the file is the real full-size thumbnail
    the creator uploaded, not the grid preview.

    `target_size` is an optional (width, height) the image is rendered to — used
    to normalise exports to 1920×1080 for long-form and 1080×1920 for a Short.
    YouTube never serves those sizes, so hitting them means one high-quality
    resample: the fetched image is scaled to COVER the target (preserving aspect,
    so nothing is squashed) and centre-cropped, then written as JPEG at quality
    95. With `target_size` left as None the bytes are written verbatim — no
    re-encode, no resize, exactly as before.

    Returns the final path (its extension may be corrected to the real image
    type, or forced to .jpg when a target size was given), or raises on failure.
    """
    if not url:
        raise ValueError("no thumbnail url")

    raw = None
    used_url = url
    # If this is a standard i.ytimg thumbnail URL we can swap in a bigger name.
    m = re.search(r"/vi/([A-Za-z0-9_-]{6,})/", url)
    if m:
        vid = m.group(1)
        base = f"https://i.ytimg.com/vi/{vid}/"
        for name in ("maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg"):
            candidate = base + name
            data = download_image_bytes(candidate)
            # A missing size still returns 200 with a tiny grey placeholder on
            # some CDNs; treat anything under ~2KB as "not really there" and try
            # the next size down.
            if data and len(data) > 2048:
                raw = data
                used_url = candidate
                break

    if raw is None:
        # Not an i.ytimg URL, or none of the larger sizes existed — fall back to
        # the cached/served bytes of the original url.
        raw = get_cached_image_bytes(url)
    if not raw:
        raise RuntimeError("could not fetch thumbnail")

    if target_size:
        return _write_resized_thumbnail(raw, dest_path, target_size)

    # Correct the extension to the real image type if the caller's guess was off
    # (or absent), so a .jpg name never wraps PNG/WEBP bytes.
    base_path, given_ext = os.path.splitext(dest_path)
    real_ext = _thumb_extension_for(used_url, raw)
    if given_ext.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
        dest_path = base_path + real_ext
    tmp = dest_path + ".part"
    with open(tmp, "wb") as f:
        f.write(raw)
    os.replace(tmp, dest_path)
    return dest_path


def _write_resized_thumbnail(raw, dest_path, target_size):
    """Render `raw` image bytes to exactly `target_size` and save as JPEG q95.

    Cover-and-crop, not stretch: the source is scaled so it fills the target in
    both axes (KeepAspectRatioByExpanding) and the overflow is trimmed from the
    centre. A 1280×720 maxres thumbnail therefore becomes a clean 1920×1080, and
    the same source becomes a 1080×1920 vertical frame for a Short — neither is
    distorted. SmoothTransformation is what keeps the upscale from looking
    blocky.

    QImage (not QPixmap) so this is safe to call from the worker thread the
    thumbnail download already runs on.
    """
    from PySide6.QtCore import QSize, Qt
    from PySide6.QtGui import QImage

    tw, th = int(target_size[0]), int(target_size[1])
    img = QImage()
    if not img.loadFromData(raw):
        raise RuntimeError("could not decode thumbnail")

    scaled = img.scaled(QSize(tw, th), Qt.KeepAspectRatioByExpanding,
                        Qt.SmoothTransformation)
    # Centre-crop the overflow so the subject stays centred.
    x = max(0, (scaled.width() - tw) // 2)
    y = max(0, (scaled.height() - th) // 2)
    out = scaled.copy(x, y, tw, th)

    # A fixed-size export is always JPEG — the size is the point, and JPEG q95 is
    # visually lossless at these dimensions while staying a sane file size.
    base_path, _ = os.path.splitext(dest_path)
    dest_path = base_path + ".jpg"
    tmp = dest_path + ".part"
    if not out.save(tmp, "JPEG", 95):
        raise RuntimeError("could not write thumbnail")
    os.replace(tmp, dest_path)
    return dest_path
