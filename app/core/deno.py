"""app.core.deno - YouTube Hunter.

Manages the JavaScript runtime (deno) that yt-dlp now needs to download from
YouTube.

YouTube gates its streams behind a JavaScript "n-signature" challenge. yt-dlp
can only solve it by RUNNING that JS, which needs an external JS runtime — deno
is the one yt-dlp prefers (see the yt-dlp announcements #14404 / #15012). With
no runtime present, YouTube's response is blocked and the download fails with a
misleading "YouTube blocked this download — close your browser" message whose
real cause is the missing runtime, not cookies.

The installer now SHIPS a deno.exe (assets/bin), so a fresh install never has
to fetch one — the download below is the fallback for source runs and for a
user who wants a newer runtime than the bundled one (Settings → "Reinstall
runtime" writes it into the managed folder, which takes precedence over the
bundled copy). The challenge SOLVER script itself ships inside the `yt_dlp_ejs`
Python package (minified), so once a deno.exe exists the whole thing works
offline — nothing else to fetch.

Install hardening (v3.26):
  * Two mirrors: dl.deno.land (Deno's own CDN) first, GitHub releases second.
    On a filtered connection github.com's release CDN is often the one host
    that fails, which is exactly how the dialog "flashed for a second and went
    back to Install" — the request died instantly and nothing said why.
  * Each mirror is tried through the proxy from Settings, then through the
    system / no proxy, with resumable retries for a dropped connection.
  * `requests` + certifi does the HTTPS, so a frozen build never trips over a
    missing Windows CA store (a CERTIFICATE_VERIFY_FAILED in ~1 s).
  * The binary is extracted to a temp name, test-run (`deno --version`), and
    only then swapped in — a half-written or blocked exe can't be "installed".
  * install_from_file() takes a deno.exe or the official .zip the user already
    has, for machines that can't reach either mirror at all.
"""

import os
import platform
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

from app.config import CONFIG_PATH
from app.core.net import configured_proxy, is_dropped_connection

# Guards a managed-path lookup racing the extraction step of a download.
_LOCK = threading.Lock()

_UA = "YouTubeHunter (deno installer)"
_CHUNK = 256 * 1024
_ATTEMPTS_PER_ROUTE = 3          # resumable retries on a dropped connection


def _exe_name():
    return "deno.exe" if sys.platform == "win32" else "deno"


def _target_triple():
    """Deno's release name for this machine. Windows ships x86_64 only (it runs
    under emulation on ARM64 Windows), the rest follow the CPU."""
    arch = (platform.machine() or "").lower()
    arm = arch in ("arm64", "aarch64")
    if sys.platform == "win32":
        return "x86_64-pc-windows-msvc"
    if sys.platform == "darwin":
        return "aarch64-apple-darwin" if arm else "x86_64-apple-darwin"
    return "aarch64-unknown-linux-gnu" if arm else "x86_64-unknown-linux-gnu"


def _zip_name():
    return f"deno-{_target_triple()}.zip"


def deno_dir():
    """Folder the managed deno lives in — beside config.json, the same writable
    per-user location app.config and app.core.db.ideas already use."""
    return os.path.join(os.path.dirname(CONFIG_PATH), "deno")


def managed_deno_path():
    """Path to the deno we downloaded, or "" when it isn't there yet."""
    p = os.path.join(deno_dir(), _exe_name())
    return p if os.path.isfile(p) and os.path.getsize(p) > 1_000_000 else ""


def deno_available():
    """True when yt-dlp will be able to find a usable JS runtime.

    Delegates to app.core.runtime_deps.find_js_runtime(), the single discovery
    used at download time — so this recognises not just our managed deno but
    ALSO deno/node/bun/quickjs already on PATH or in their usual install
    folders. A user who has node installed is therefore never nagged.
    """
    try:
        from app.core.runtime_deps import find_js_runtime
        return find_js_runtime() is not None
    except Exception:      # noqa: BLE001 — absence is just "not available"
        return bool(managed_deno_path())


def deno_ydl_opts():
    """Kept for old call sites; prefer runtime_deps.js_runtime_opts()."""
    try:
        from app.core.runtime_deps import js_runtime_opts
        return js_runtime_opts()
    except Exception:      # noqa: BLE001
        path = managed_deno_path()
        return {"js_runtimes": {"deno": {"path": path}}} if path else {}


# ════════════════════════════════════════════════════════════════════════
#  download
# ════════════════════════════════════════════════════════════════════════
class _Cancelled(Exception):
    pass


def _routes():
    """(label, proxies) pairs to try, in order. The Settings proxy first when
    there is one; then the system proxy / direct connection (requests reads the
    Windows proxy settings and the HTTP(S)_PROXY env on its own)."""
    out = []
    proxy = configured_proxy()
    if proxy:
        out.append(("proxy", {"http": proxy, "https": proxy}))
    out.append(("direct", None))
    return out


def _session(proxies):
    import requests
    s = requests.Session()
    s.headers["User-Agent"] = _UA
    if proxies:
        s.proxies.update(proxies)
        s.trust_env = False       # the explicit proxy, not a stale env one
    return s


def _mirror_urls(session):
    """Candidate download URLs, best first. dl.deno.land needs the version
    looked up first; if that lookup fails we still have GitHub's /latest."""
    urls = []
    try:
        r = session.get("https://dl.deno.land/release-latest.txt", timeout=12)
        r.raise_for_status()
        ver = (r.text or "").strip()
        if ver.startswith("v") and len(ver) < 24:
            urls.append(("dl.deno.land",
                         f"https://dl.deno.land/release/{ver}/{_zip_name()}"))
    except Exception:      # noqa: BLE001 — the mirror below still exists
        pass
    urls.append(("GitHub",
                 "https://github.com/denoland/deno/releases/latest/download/"
                 + _zip_name()))
    return urls


def _retryable(exc):
    """A blip worth another go (dropped / timed-out connection), as opposed to
    a refusal that will just happen again (SSL, proxy, 403, DNS)."""
    import requests
    ex = requests.exceptions
    if isinstance(exc, (ex.SSLError, ex.ProxyError, ex.HTTPError, ex.InvalidURL)):
        return False
    if isinstance(exc, (ex.ChunkedEncodingError, ex.Timeout, ConnectionError)):
        return True
    if isinstance(exc, ex.ConnectionError):
        low = str(exc).lower()
        return not ("name resolution" in low or "getaddrinfo" in low
                    or "nodename" in low or "refused" in low)
    return is_dropped_connection(exc)


def _fetch(session, url, dest, on_progress, should_cancel):
    """Stream `url` into `dest`, resuming after a dropped connection. Raises on
    failure; returns the byte count on success."""
    done = 0
    total = 0
    last_exc = None
    for attempt in range(_ATTEMPTS_PER_ROUTE):
        headers = {"Range": f"bytes={done}-"} if done else {}
        try:
            with session.get(url, stream=True, timeout=(15, 45),
                             headers=headers, allow_redirects=True) as r:
                if r.status_code == 416 and total and done >= total:
                    return done
                r.raise_for_status()
                resumed = done and r.status_code == 206
                if not resumed:
                    done = 0
                    total = int(r.headers.get("Content-Length") or 0)
                elif not total:
                    total = done + int(r.headers.get("Content-Length") or 0)
                ctype = (r.headers.get("Content-Type") or "").lower()
                if "text/html" in ctype:
                    # a captive portal / block page, not a zip
                    raise RuntimeError("the server returned a web page instead of the file")
                with open(dest, "ab" if resumed else "wb") as out:
                    for chunk in r.iter_content(_CHUNK):
                        if should_cancel is not None and should_cancel():
                            raise _Cancelled()
                        if not chunk:
                            continue
                        out.write(chunk)
                        done += len(chunk)
                        if on_progress:
                            on_progress(done, total)
            if total and done < total:
                raise ConnectionError("connection closed before the download finished")
            return done
        except _Cancelled:
            raise
        except Exception as exc:      # noqa: BLE001
            last_exc = exc
            retryable = _retryable(exc)
            if not retryable or attempt == _ATTEMPTS_PER_ROUTE - 1:
                raise
            time.sleep(1.2 * (attempt + 1))
    raise last_exc or RuntimeError("download failed")


def _verify(exe):
    """Run `deno --version`; returns the version line or raises."""
    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    out = subprocess.run([exe, "--version"], capture_output=True, text=True,
                         encoding="utf-8", errors="replace", timeout=20,
                         creationflags=flags)
    line = (out.stdout or "").strip().splitlines()
    if out.returncode != 0 or not line or "deno" not in line[0].lower():
        detail = (out.stderr or out.stdout or "").strip()[:200]
        raise RuntimeError("the downloaded deno didn't start" + (f": {detail}" if detail else ""))
    return line[0]


def _install_exe_from(src_path_or_zip):
    """Put a deno binary (a bare exe, or the official zip) into deno_dir():
    extract/copy to a temp name, test-run it, then atomically swap it in."""
    os.makedirs(deno_dir(), exist_ok=True)
    target = os.path.join(deno_dir(), _exe_name())
    staged = target + ".new"
    with _LOCK:
        try:
            if zipfile.is_zipfile(src_path_or_zip):
                with zipfile.ZipFile(src_path_or_zip) as zf:
                    member = next((n for n in zf.namelist()
                                   if os.path.basename(n).lower() == _exe_name()), None)
                    if not member:
                        raise RuntimeError("this zip doesn't contain " + _exe_name())
                    with zf.open(member) as src, open(staged, "wb") as dst:
                        while True:
                            buf = src.read(_CHUNK)
                            if not buf:
                                break
                            dst.write(buf)
            else:
                import shutil
                shutil.copyfile(src_path_or_zip, staged)
            if sys.platform != "win32":
                os.chmod(staged, 0o755)
            _verify(staged)
            try:
                os.replace(staged, target)
            except PermissionError:
                # Windows: the old deno.exe is running (a download in flight)
                # or an antivirus is scanning it — rename it out of the way.
                old = target + ".old"
                try:
                    if os.path.exists(old):
                        os.remove(old)
                except OSError:
                    pass
                os.replace(target, old)
                os.replace(staged, target)
        finally:
            if os.path.exists(staged):
                try:
                    os.remove(staged)
                except OSError:
                    pass
    try:
        from app.core.runtime_deps import invalidate_js_runtime_cache
        invalidate_js_runtime_cache()
    except Exception:      # noqa: BLE001 — cache is best-effort
        pass
    return target


def _explain(exc):
    """One short, human reason for a failed attempt."""
    text = str(exc) or type(exc).__name__
    low = text.lower()
    if "certificate" in low or "ssl" in low:
        return "secure connection failed (SSL)"
    if "timed out" in low or "timeout" in type(exc).__name__.lower():
        return "timed out"
    if is_dropped_connection(exc) or "10054" in low or "reset" in low:
        return "connection dropped"
    if "proxy" in low:
        return "proxy refused the connection"
    if "refused" in low or "max retries exceeded" in low or "newconnectionerror" in low:
        return "couldn't connect"
    if "name resolution" in low or "getaddrinfo" in low or "nodename" in low:
        return "couldn't resolve the server"
    if "403" in low or "451" in low:
        return "blocked (HTTP 403)"
    if "404" in low:
        return "file not found (404)"
    return text[:120]


def download_deno(on_progress=None, should_cancel=None, on_status=None):
    """Download deno and install it into deno_dir(). Blocking — call on a worker
    thread.

    `on_progress(done_bytes, total_bytes)` is called as bytes arrive (total is 0
    when the server sends no Content-Length). `should_cancel` is polled between
    chunks so the user can abort. `on_status(text)` names the mirror being
    tried. Returns (ok, message).
    """
    tried = []
    fd, tmp_zip = tempfile.mkstemp(suffix=".zip", prefix="deno_")
    os.close(fd)
    try:
        for route, proxies in _routes():
            session = _session(proxies)
            for host, url in _mirror_urls(session):
                if should_cancel is not None and should_cancel():
                    return False, "cancelled"
                if on_status:
                    on_status(host + (" · proxy" if route == "proxy" else ""))
                if on_progress:
                    on_progress(0, 0)
                try:
                    _fetch(session, url, tmp_zip, on_progress, should_cancel)
                    if not zipfile.is_zipfile(tmp_zip):
                        raise RuntimeError("the download was damaged (not a zip)")
                    _install_exe_from(tmp_zip)
                    return True, ""
                except _Cancelled:
                    return False, "cancelled"
                except Exception as exc:      # noqa: BLE001 — try the next one
                    tried.append(f"{host}{' (proxy)' if route == 'proxy' else ''}: {_explain(exc)}")
        return False, "; ".join(tried) or "no download source was reachable"
    finally:
        try:
            os.remove(tmp_zip)
        except OSError:
            pass


def install_from_file(path):
    """Install a deno.exe (or the official deno-*.zip) the user picked on disk.
    Returns (ok, message)."""
    try:
        if not path or not os.path.isfile(path):
            return False, "file not found"
        _install_exe_from(path)
        return True, ""
    except Exception as exc:      # noqa: BLE001
        return False, _explain(exc)
