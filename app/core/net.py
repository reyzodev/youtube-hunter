"""app.core.net - Youtube Scrapper."""

import http.client
import json
import re
import socket
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from app.i18n import tr

# YouTube video-id patterns, tried in order against a pasted link. Covers the
# usual watch?v=, youtu.be/, /shorts/ and /live/ forms.
_YT_ID_RES = (
    re.compile(r"[?&]v=([\w-]{11})"),
    re.compile(r"youtu\.be/([\w-]{11})"),
    re.compile(r"/shorts/([\w-]{11})"),
    re.compile(r"/live/([\w-]{11})"),
    re.compile(r"/embed/([\w-]{11})"),
)


def extract_video_id(text):
    """Pull an 11-char YouTube video id out of a pasted URL (or a bare id).
    Returns the id, or None if nothing that looks like one is present."""
    text = (text or "").strip()
    if not text:
        return None
    for rx in _YT_ID_RES:
        m = rx.search(text)
        if m:
            return m.group(1)
    # A bare id pasted on its own (no URL around it).
    if re.fullmatch(r"[\w-]{11}", text):
        return text
    return None


def fetch_youtube_oembed(video_id, timeout=12, proxy=None):
    """Fetch a video's public title + channel + thumbnail via YouTube's oEmbed
    endpoint — no API key and no quota cost, exactly what the paste-a-link
    Downloads box needs to show the quality picker with real metadata.

    Returns a dict shaped like the archive/niche rows that _archive_download_video
    already understands (video_id, video_url, title, thumbnail_url,
    channel_title, channel_url), or raises on failure so the caller can show
    the error."""
    url = ("https://www.youtube.com/oembed?url="
           + urllib.parse.quote(
               f"https://www.youtube.com/watch?v={video_id}", safe="")
           + "&format=json")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    data = {}
    try:
        with _urlopen(req, timeout, proxy) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
    except Exception:
        # oEmbed can fail (age-restricted / region-blocked / private video, or a
        # flaky proxy) even when the video is perfectly downloadable. Fall back
        # to yt-dlp metadata below rather than raising — an empty title here is
        # what produced the "Untitled" rows.
        data = {}

    title = data.get("title") or ""
    channel_title = data.get("author_name") or ""
    channel_url = data.get("author_url") or ""
    thumb = data.get("thumbnail_url") or ""

    # If oEmbed gave us nothing usable, ask yt-dlp for the real metadata. This
    # is the same extractor the download uses, so anything downloadable resolves
    # here too — no more "Untitled" for videos oEmbed can't see.
    if not title:
        try:
            from app.core.utils import ensure_yt_dlp_ready
            from app.core.runtime_deps import js_runtime_opts
            yt_dlp, _ffmpeg = ensure_yt_dlp_ready()
            opts = {"quiet": True, "no_warnings": True, "skip_download": True,
                    "noplaylist": True, "extractor_retries": 2}
            opts.update(js_runtime_opts())   # extraction may need the JS challenge solved
            if proxy:
                opts["proxy"] = proxy
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(
                    f"https://www.youtube.com/watch?v={video_id}", download=False)
            title = title or (info.get("title") or "")
            channel_title = channel_title or (info.get("channel")
                                              or info.get("uploader") or "")
            channel_url = channel_url or (info.get("channel_url")
                                          or info.get("uploader_url") or "")
            if not thumb:
                thumb = info.get("thumbnail") or ""
        except Exception:
            pass

    return {
        "video_id": video_id,
        "video_url": f"https://www.youtube.com/watch?v={video_id}",
        "title": title,
        # oEmbed's own thumbnail can be a letterboxed hqdefault; the plain
        # hqdefault URL is a safe, always-present fallback.
        "thumbnail_url": thumb
            or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
        "channel_title": channel_title,
        "channel_url": channel_url,
    }


def configured_proxy():
    """The proxy the user typed in Settings, or "".

    Read here rather than threaded down from the UI because the page-scraping
    paths below (monetization signals, the zero-quota search) are reached from
    several VMs and a plain scrape has no "client" object to carry it. The key is
    `ai_proxy` — historically named, but it is the app's ONE proxy setting and
    every download/AI path already reads that name.
    """
    try:
        from app.config import load_app_config
        return (load_app_config().get("ai_proxy", "") or "").strip()
    except Exception:
        return ""


def _proxied_opener(proxy_url):
    """Build a urllib opener that forces requests through an explicit
    HTTP/HTTPS proxy (e.g. http://127.0.0.1:10809 — the local HTTP proxy
    port most VPN/v2ray clients expose alongside their SOCKS port).

    This exists because urllib's default opener only picks up a proxy from
    the OS/environment automatically, and that path is unreliable for a
    packaged desktop app: system-wide tunneling tools (Proxifier, etc.)
    hook the browser reliably but sometimes miss a differently-named or
    separately-launched process. Letting the user paste their proxy
    address directly into Settings removes that guesswork entirely.

    Returns None if no proxy is configured, in which case callers should
    fall back to urllib's normal (OS/environment-detected) behavior.

    Note: this only understands HTTP-proxy syntax (http://host:port). Most
    VPN/v2ray clients expose both a SOCKS5 port and a plain HTTP port —
    use the HTTP one here, since the stdlib has no built-in SOCKS support.
    """
    proxy_url = (proxy_url or "").strip()
    if not proxy_url:
        return None
    handler = urllib.request.ProxyHandler({"http": proxy_url, "https": proxy_url})
    return urllib.request.build_opener(handler)


# Sent on every request that does not set its own User-Agent.
#
# urllib's default is "Python-urllib/3.x", and that exact string is on the
# block list of Cloudflare's bot protection (error 1010) and most WAFs in
# front of AI routers / aggregators. Those hosts answer a bare
# "HTTP Error 403: Forbidden" with an HTML page instead of JSON, which is
# exactly what the Custom provider's "Fetch models" button was showing while
# the same key + host worked fine from other tools (they send a real UA).
APP_USER_AGENT = (
    "YouTubeHunter/3.13 (Windows NT 10.0; Win64; x64) "
    "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36")


def _with_default_headers(req):
    if isinstance(req, urllib.request.Request):
        # has_header() looks names up in urllib's capitalize() form.
        if not req.has_header("User-agent"):
            req.add_header("User-Agent", APP_USER_AGENT)
        if not req.has_header("Accept"):
            req.add_header("Accept", "application/json, text/event-stream, */*")
    return req


def _urlopen(req, timeout, proxy=None):
    """Drop-in replacement for urllib.request.urlopen() that routes through
    an explicit proxy when one is configured, otherwise behaves exactly
    like the stdlib default. Requests without their own User-Agent get the
    app's (see APP_USER_AGENT)."""
    req = _with_default_headers(req)
    opener = _proxied_opener(proxy)
    if opener is not None:
        return opener.open(req, timeout=timeout)
    return urllib.request.urlopen(req, timeout=timeout)


def _read_timeout_error(provider_label, timeout):
    """A clear, provider-labeled message for a genuine socket-level timeout
    that fires while waiting for the response BODY, not the connection.

    urlopen(url, timeout=N) only wraps a timeout into urllib.error.URLError
    when it fires during the initial connect. The timeout value is really
    just set once on the underlying socket for its whole lifetime, so if
    the connection succeeds but the provider is slow to finish generating
    and streaming back the body, the timeout fires later, inside our own
    `resp.read()` call — as a bare socket.timeout/TimeoutError that the
    HTTPError/URLError except clauses below never see. Left uncaught, that
    used to reach the user as a bare, unexplained "timed out" with no
    indication of what happened or what to do about it."""
    return RuntimeError(
        tr("{provider} took longer than {timeout}s to respond, so the "
           "request was stopped. This usually means the reply was slow to "
           "finish generating, or the connection — especially through a "
           "proxy — is degraded right now. Try again in a moment.").format(
               provider=provider_label, timeout=int(timeout)))

# ═════════════════════════════════════════════════════════════════════════
#  DROPPED CONNECTIONS
#
#  A long AI call is the most fragile request this app makes: the socket sits
#  open and idle for minutes while the provider generates, and anything in the
#  path — a proxy, a VPN, a home router's NAT table, the provider's own load
#  balancer — is free to give up on it. On Windows that surfaces as
#  "[WinError 10054] An existing connection was forcibly closed by the remote
#  host", which is a ConnectionResetError.
#
#  ConnectionResetError is an OSError but NOT a urllib.error.URLError, so every
#  `except urllib.error.URLError` clause in app.core.ai.clients misses it and
#  the raw WinError text reaches the user — no provider name, no explanation,
#  no suggested action. These two helpers fix both halves of that: recognise
#  the family, and say something useful about it.
# ═════════════════════════════════════════════════════════════════════════

def is_dropped_connection(exc):
    """Whether `exc` means "the connection died mid-request" rather than "the
    server answered with an error".

    Deliberately broad, because the same event arrives under a different class
    depending on where in the exchange it lands and whether TLS was involved:

      * ConnectionResetError   — WinError 10054 / ECONNRESET. Also covers
                                 http.client.RemoteDisconnected, which subclasses
                                 it, i.e. the server closed without replying.
      * ConnectionAbortedError — WinError 10053, the local stack gave up.
      * http.client.IncompleteRead — headers arrived, then the body was cut off.
                                 NOT an OSError, so it needs naming explicitly.
      * ssl.SSLEOFError / SSLZeroReturnError — a TLS-layer disconnect.
      * URLError wrapping any of the above — how urllib reports it when the
        break happens during connect rather than during read.
    """
    if isinstance(exc, urllib.error.HTTPError):
        # A real HTTP response with a status code — the server DID answer, so
        # this is not a dropped connection no matter what the body says. Checked
        # first because HTTPError subclasses URLError.
        return False
    if isinstance(exc, (ConnectionResetError, ConnectionAbortedError,
                        http.client.IncompleteRead)):
        return True
    if isinstance(exc, (ssl.SSLEOFError, ssl.SSLZeroReturnError)):
        return True
    if isinstance(exc, urllib.error.URLError):
        return is_dropped_connection(exc.reason)
    # Some proxies raise a bare OSError with the winerror set rather than the
    # mapped subclass, so fall back to the code itself.
    return getattr(exc, "winerror", None) in (10053, 10054)

def _dropped_connection_error(provider_label, attempts=1, generating=True):
    """The message a user actually needs when the connection is cut mid-call.

    Names the provider, says plainly that this is a transport failure rather
    than the model refusing or the key being wrong, and points at the two
    things the user can actually change (the proxy, and retrying). Reports the
    retry count so a persistent failure looks different from a one-off blip.

    `generating=False` for the plain GETs (the Settings "Fetch models" button):
    those never reach a model at all, so the reassurance about not being charged
    would be answering a question the user did not ask."""
    if not generating:
        return RuntimeError(
            tr("The connection to {provider} was closed before it answered. "
               "This is a network problem rather than a bad key — if you are "
               "on a proxy or VPN, check it is still up, then try again.")
            .format(provider=provider_label))
    if attempts > 1:
        return RuntimeError(
            tr("The connection to {provider} was closed mid-request, and "
               "{attempts} attempts all failed. Nothing reached the model, so "
               "no request was charged. Long requests like this one are the "
               "first thing a proxy or VPN drops — if you are using one, check "
               "it is still up, then try again.").format(
                   provider=provider_label, attempts=int(attempts)))
    return RuntimeError(
        tr("The connection to {provider} was closed mid-request. Nothing "
           "reached the model, so no request was charged. Long requests like "
           "this one are the first thing a proxy or VPN drops — if you are "
           "using one, check it is still up, then try again.").format(
               provider=provider_label))

def explain_network_error(exc, label=None):
    """The message to SHOW for an exception that has already been caught.

    Every worker thread in the app ends in `except Exception as exc:` followed by
    handing `str(exc)` to a toast. For a dropped connection that string is
    "[WinError 10054] An existing connection was forcibly closed by the remote
    host" — accurate, and useless: it names no provider, explains nothing, and
    suggests nothing. The call sites can't each re-derive the explanation, so
    this is the one place that turns a caught exception into user-facing text.

    Anything that ISN'T a transport failure passes through as its own message
    untouched: those are already written for the user (a missing API key, an
    unreadable export, a provider's own error body), and second-guessing them
    here would replace a specific message with a vague one.
    """
    if is_dropped_connection(exc):
        return str(_dropped_connection_error(label or tr("The API")))
    return str(exc)


# ═════════════════════════════════════════════════════════════════════════
#  USER CANCEL (Stop button)
#
#  A long AI call blocks a worker thread inside resp.read() for minutes. A
#  "Stop" that only flips a flag would leave that socket open, the provider
#  still generating (and billing), and the thread alive until the timeout.
#  CancelToken lets the GUI thread shut the live socket at once: the worker
#  binds a token to itself with `cancel_scope(token)`, request_with_retry
#  registers every response it opens on that token, and token.cancel() from
#  ANY thread shuts the socket so the blocked recv() returns immediately.
#  Callers that never open a scope are unaffected.
# ═════════════════════════════════════════════════════════════════════════
class RequestCancelled(Exception):
    """The user pressed Stop while a request was in flight."""


class CancelToken:
    __slots__ = ("_event", "_lock", "_resp")

    def __init__(self):
        self._event = threading.Event()
        self._lock = threading.Lock()
        self._resp = None

    @property
    def cancelled(self):
        return self._event.is_set()

    def check(self):
        if self._event.is_set():
            raise RequestCancelled()

    def attach(self, resp):
        with self._lock:
            self._resp = resp
        # Cancelled between open() and attach(): shut it right away.
        if self._event.is_set():
            _shutdown_response(resp)

    def detach(self):
        with self._lock:
            self._resp = None

    def cancel(self):
        self._event.set()
        with self._lock:
            resp = self._resp
        _shutdown_response(resp)


def _shutdown_response(resp):
    """Wake a reader blocked in resp.read() from another thread. close() alone
    does not reliably interrupt a blocked recv() on Windows; shutdown() does."""
    if resp is None:
        return
    try:
        raw = getattr(getattr(resp, "fp", None), "raw", None)
        sock = getattr(raw, "_sock", None)
        if sock is not None:
            sock.shutdown(socket.SHUT_RDWR)
    except Exception:
        pass
    try:
        resp.close()
    except Exception:
        pass


_cancel_local = threading.local()


def current_cancel_token():
    return getattr(_cancel_local, "token", None)


class cancel_scope:
    """`with cancel_scope(token): ...` — every request_with_retry() made on this
    thread inside the block can be aborted by token.cancel()."""

    def __init__(self, token):
        self.token = token
        self._prev = None

    def __enter__(self):
        self._prev = current_cancel_token()
        _cancel_local.token = self.token
        return self.token

    def __exit__(self, *exc):
        _cancel_local.token = self._prev
        return False


def request_with_retry(build_request, timeout, proxy=None, attempts=3,
                       provider_label="The API"):
    """POST/GET a request, retrying when the connection is dropped mid-flight.

    `build_request` is a zero-arg callable returning a fresh urllib Request —
    a callable rather than a Request because a Request's body stream can only be
    consumed once, so a retry needs a new one.

    Only dropped connections are retried. An HTTP error status, a timeout, or
    anything the server actually answered is raised immediately: those mean the
    request WAS delivered, and re-sending it would risk paying for the same
    generation twice. A dropped connection means nothing arrived, so retrying is
    free.

    Backoff is 1s then 2s. Deliberately short — the caller is a worker thread
    with a user watching a spinner, and a proxy that is going to recover does so
    within a second or two."""
    last = None
    token = current_cancel_token()
    for attempt in range(1, max(1, attempts) + 1):
        if token is not None:
            token.check()
        try:
            with _urlopen(build_request(), timeout, proxy) as resp:
                if token is not None:
                    token.attach(resp)
                try:
                    data = resp.read()
                finally:
                    if token is not None:
                        token.detach()
                # A shut socket can end read() "cleanly" with a truncated body.
                if token is not None:
                    token.check()
                return data
        except RequestCancelled:
            raise
        except Exception as e:
            # Whatever the socket shutdown surfaced as (reset, timeout, a bare
            # OSError), a cancelled request is never retried or re-explained.
            if token is not None and token.cancelled:
                raise RequestCancelled() from e
            if isinstance(e, (socket.timeout, TimeoutError)):
                # The socket was alive and the provider was simply slow.
                # Re-sending would double-charge a generation that may still be
                # running, so this is never retried.
                raise _read_timeout_error(provider_label, timeout) from e
            if not is_dropped_connection(e):
                # The server answered, or something else went wrong: hand it to
                # the caller, which knows its own provider's error bodies.
                raise
            last = e
            if attempt >= attempts:
                # Raise the EXPLAINED error, never the raw "[WinError 10054]".
                raise _dropped_connection_error(provider_label, attempts) from e
            if token is not None:
                # Interruptible backoff: Stop during the 1-2 s wait is instant.
                if token._event.wait(attempt):
                    raise RequestCancelled() from e
            else:
                time.sleep(attempt)
            continue
    # Unreachable: the loop either returns or raises. Kept as a guard so a
    # future edit to the loop bounds cannot silently return None.
    raise _dropped_connection_error(provider_label, attempts) from last


def download_image_bytes(url, timeout=12):
    """Best-effort image download — returns raw bytes or None (never raises).
    NOTE: deliberately returns bytes, NOT a QPixmap: this function runs on
    worker threads where creating QPixmap objects is unsafe."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
        return raw or None
    except Exception:
        return None
