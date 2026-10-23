"""app.core.runtime_deps - YouTube Hunter.

Single source of truth for the video-download engine's runtime dependencies:

  * yt-dlp itself  — the bundled copy, or a newer one the user downloaded via
                     the Settings "Update downloader" button (kept in the
                     user-data dir so it survives without a rebuild).
  * a JS runtime   — yt-dlp 2026+ deprecated YouTube extraction WITHOUT a
                     JavaScript runtime, so several extractor clients (web_safari,
                     ios, mweb) now return nothing unless deno/node/bun/quickjs is
                     present. We look on PATH first, then fall back to a managed
                     deno.exe we download on demand (ported from YTSage).
  * ffmpeg+ffprobe — imageio-ffmpeg ships only ffmpeg.exe; ffprobe is bundled
                     separately in assets/bin. yt-dlp finds BOTH when
                     ffmpeg_location points at a DIRECTORY holding the two, so we
                     assemble one.

Everything here is UI-free (stdlib + requests, no Qt), so it can be called from
a worker thread and shared by every download path (QML VMs and the legacy
QWidgets page alike).
"""

import hashlib
import os
import shutil
import sys
import threading
import zipfile

from app.core.net import _urlopen, configured_proxy, explain_network_error
from app.paths import asset_path

# ── user-data dir (mirrors app.config._get_config_path convention) ──────────
_APP_DIR_NAME = "NicheScope"   # kept: existing installs already have their runtime files here


def user_bin():
    """The app's private bin dir under the user profile, created on demand.

    Kept out of the install tree so it is writable without admin rights and
    survives an app reinstall/upgrade. Mirrors config.py's per-OS base choice.
    """
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support")
    else:
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    path = os.path.join(base, _APP_DIR_NAME, "bin")
    try:
        os.makedirs(path, exist_ok=True)
    except OSError:
        path = os.path.join(os.path.expanduser("~"), f".{_APP_DIR_NAME}", "bin")
        os.makedirs(path, exist_ok=True)
    return path


# ════════════════════════════════════════════════════════════════════════
#  yt-dlp loader (bundled, or a user-downloaded newer wheel)
# ════════════════════════════════════════════════════════════════════════
_YT_DLP = None            # cached module once imported
_FINDER_INSTALLED = False


def _runtime_ytdlp_dir():
    """Where update_yt_dlp() unpacks a downloaded wheel (a plain dir on
    sys.path). None-safe: just a path, may not exist."""
    return os.path.join(user_bin(), "runtime", "yt-dlp")


class _EngineFinder:
    """A sys.meta_path finder that resolves ONLY yt_dlp / yt_dlp_ejs from the
    downloaded-runtime dir, so a newer engine can be loaded without disturbing
    any other package. Verified to work and to stay isolated from the bundled
    copy."""

    def __init__(self, root):
        self._root = root

    def find_spec(self, name, path=None, target=None):
        if name != "yt_dlp" and not name.startswith(("yt_dlp.", "yt_dlp_ejs")):
            return None
        import importlib.machinery
        search = [self._root] if path is None else list(path)
        return importlib.machinery.PathFinder.find_spec(name, search)


# v3.41.3: the engine is now warmed on a background thread at startup
# (prewarm_download_engine), so two threads can reach the import at once. The
# sys.modules / meta_path surgery below must not interleave.
_LOAD_LOCK = threading.RLock()


def load_yt_dlp(force=False):
    """Import and return the yt_dlp module — the downloaded newer copy if the
    user updated it, otherwise the bundled one. Cached unless `force=True`."""
    if _YT_DLP is not None and not force:
        return _YT_DLP
    with _LOAD_LOCK:
        return _load_yt_dlp_locked(force)


def _load_yt_dlp_locked(force):
    global _YT_DLP, _FINDER_INSTALLED
    if _YT_DLP is not None and not force:
        return _YT_DLP

    rt_dir = _runtime_ytdlp_dir()
    if os.path.isdir(os.path.join(rt_dir, "yt_dlp")):
        # yt_dlp may already be imported elsewhere; drop it so the finder wins.
        for mod in [m for m in sys.modules if m == "yt_dlp" or m.startswith("yt_dlp.")]:
            del sys.modules[mod]
        if not _FINDER_INSTALLED:
            sys.meta_path.insert(0, _EngineFinder(rt_dir))
            _FINDER_INSTALLED = True
    elif force:
        # Forced refresh with no downloaded copy to prefer: nothing newer to
        # load, so keep the engine we already have.
        return _YT_DLP

    # Running from source with neither bundled nor downloaded copy present: fall
    # back to the pip bootstrap VERSIK used, so `python main.py` still works.
    if not getattr(sys, "frozen", False):
        try:
            import yt_dlp  # noqa: F401
        except ImportError:
            import subprocess
            # bounded + windowless: a stalled PyPI must not hang startup
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "yt-dlp"],
                check=True, timeout=180,
                creationflags=(subprocess.CREATE_NO_WINDOW
                               if sys.platform == "win32" else 0))

    import yt_dlp
    _YT_DLP = yt_dlp
    return _YT_DLP


def reload_yt_dlp():
    """Re-import yt_dlp so a freshly downloaded engine takes effect IN THIS RUN.

    The bot/403 branch in app.core.download refreshes the engine (frozen builds
    fetch the newest wheel into the user-data dir) and then calls this. Without
    it the new copy was only visible on the NEXT launch, so the download that
    triggered the update still failed with the stale extractor.

    Returns the new module, or None when there is nothing newer to load (the
    caller then keeps using the module it already holds).
    """
    if not os.path.isdir(os.path.join(_runtime_ytdlp_dir(), "yt_dlp")):
        return None
    return load_yt_dlp(force=True)


# ════════════════════════════════════════════════════════════════════════
#  ffmpeg + ffprobe directory
# ════════════════════════════════════════════════════════════════════════
_FFMPEG_DIR = None


def _bundled_ffprobe():
    """Path to the ffprobe.exe bundled in assets/bin, or None if absent."""
    name = "ffprobe.exe" if sys.platform == "win32" else "ffprobe"
    p = asset_path("assets", "bin", name)
    return p if os.path.exists(p) else None


def ensure_ffmpeg_dir():
    """Return a DIRECTORY that holds both ffmpeg and ffprobe, for use as
    yt-dlp's `ffmpeg_location`.

    imageio-ffmpeg ships only ffmpeg.exe (in its own package dir), and ffprobe
    is bundled separately in assets/bin. yt-dlp resolves both executables when
    ffmpeg_location is a directory containing them, so we assemble one under the
    user-bin dir by copying (or hardlinking) the two binaries in. Cached.
    """
    global _FFMPEG_DIR
    if _FFMPEG_DIR and os.path.isdir(_FFMPEG_DIR):
        return _FFMPEG_DIR

    ffmpeg_name = "ffmpeg.exe" if sys.platform == "win32" else "ffmpeg"
    ffprobe_name = "ffprobe.exe" if sys.platform == "win32" else "ffprobe"

    import imageio_ffmpeg
    ffmpeg_src = imageio_ffmpeg.get_ffmpeg_exe()
    ffprobe_src = _bundled_ffprobe()

    out_dir = os.path.join(user_bin(), "ffmpeg")
    os.makedirs(out_dir, exist_ok=True)

    def _place(src, dst_name):
        if not src or not os.path.exists(src):
            return
        dst = os.path.join(out_dir, dst_name)
        try:
            if os.path.exists(dst) and os.path.getsize(dst) == os.path.getsize(src):
                return                       # already staged, same size
        except OSError:
            pass
        try:
            if os.path.exists(dst):
                os.remove(dst)
            os.link(src, dst)                # cheap hardlink where possible
        except OSError:
            shutil.copy2(src, dst)           # cross-volume: real copy

    _place(ffmpeg_src, ffmpeg_name)
    _place(ffprobe_src, ffprobe_name)

    _FFMPEG_DIR = out_dir
    return out_dir


# ════════════════════════════════════════════════════════════════════════
#  JS runtime discovery
# ════════════════════════════════════════════════════════════════════════
# yt-dlp 2026+ needs a JS runtime to solve YouTube's challenge. yt-dlp only
# auto-enables **deno** by default, so a machine that has node/bun/quickjs but
# no deno would still fail unless we point yt-dlp at it explicitly — which is
# exactly what find_js_runtime() does. Managed-deno download stays in
# app.core.deno (it already handles proxy + cancel + a live-progress dialog);
# this module just discovers what's usable and hands yt-dlp the right option.
#
# Priority mirrors yt-dlp's own order. Each entry: (js_runtimes key, PATH exe).
_RUNTIME_CANDIDATES = (
    ("deno", "deno"),
    ("node", "node"),
    ("bun", "bun"),
    ("quickjs", "qjs"),
)


def _bundled_deno():
    """Path to a deno.exe shipped INSIDE the install (assets/bin), or None.

    Why a bundled copy exists: the on-demand download (app.core.deno) needs
    github.com to be reachable. On a filtered connection — or behind a proxy
    that only passes some hosts — that download fails, and then EVERY YouTube
    download fails on the JS challenge no matter how good the client ladder is.
    A bundled copy makes the runtime a property of the install instead of a
    property of the user's network, which is the difference between "works on my
    machine" and "works on the customer's machine". The download path is kept
    for source runs and as a way to get a newer deno later.
    """
    name = "deno.exe" if sys.platform == "win32" else "deno"
    p = asset_path("assets", "bin", name)
    return p if os.path.exists(p) else None


def _known_install_paths(key):
    """Usual install locations for a runtime that may NOT be on this process's
    PATH: the official deno installer and winget/scoop/choco only update PATH
    for processes started afterwards, so a user who installs deno while the app
    is open (or whose PATH is broken) was still told it was missing."""
    home = os.path.expanduser("~")
    if sys.platform == "win32":
        la = os.environ.get("LOCALAPPDATA") or os.path.join(home, "AppData", "Local")
        pf = os.environ.get("ProgramFiles") or r"C:\Program Files"
        pd = os.environ.get("ProgramData") or r"C:\ProgramData"
        table = {
            "deno": [os.path.join(home, ".deno", "bin", "deno.exe"),
                     os.path.join(la, "Microsoft", "WinGet", "Links", "deno.exe"),
                     os.path.join(home, "scoop", "shims", "deno.exe"),
                     os.path.join(pd, "chocolatey", "bin", "deno.exe")],
            "node": [os.path.join(pf, "nodejs", "node.exe"),
                     os.path.join(home, "scoop", "shims", "node.exe")],
            "bun": [os.path.join(home, ".bun", "bin", "bun.exe")],
        }
    else:
        table = {
            "deno": [os.path.join(home, ".deno", "bin", "deno"),
                     "/opt/homebrew/bin/deno", "/usr/local/bin/deno"],
            "node": ["/opt/homebrew/bin/node", "/usr/local/bin/node"],
            "bun": [os.path.join(home, ".bun", "bin", "bun")],
        }
    return [p for p in table.get(key, []) if os.path.isfile(p)]


_JS_RT_CACHE = {"ts": 0.0, "value": None}
_JS_RT_TTL_S = 60.0


def invalidate_js_runtime_cache():
    """Forget the cached runtime search — call after installing/removing deno."""
    _JS_RT_CACHE["ts"] = 0.0
    _JS_RT_CACHE["value"] = None


def find_js_runtimes():
    """Cached front door for _find_js_runtimes_uncached (v1.0.1).

    Every yt-dlp call site builds its options through js_runtime_opts(), so the
    search ran once per probe, per ladder rung and per cut: a `shutil.which`
    PATH scan for four runtimes plus a dozen isfile() checks each time. The
    answer only changes when a runtime is installed, so it is kept for a
    minute (and dropped explicitly by the installers)."""
    import time as _t
    now = _t.monotonic()
    val = _JS_RT_CACHE["value"]
    if val is not None and now - _JS_RT_CACHE["ts"] < _JS_RT_TTL_S:
        return dict(val)
    val = _find_js_runtimes_uncached()
    # an empty answer is not cached: the user may be installing deno right now
    if val:
        _JS_RT_CACHE["value"], _JS_RT_CACHE["ts"] = dict(val), now
    return val


def _find_js_runtimes_uncached():
    """Every usable JS runtime, best first, shaped for yt-dlp's `js_runtimes`
    option: e.g. {"deno": {"path": ...}, "node": {"path": ...}}.

    deno leads (it is the runtime yt-dlp's solver is built and tested on), and
    for deno ANY copy beats node: PATH, its usual install folders, the managed
    copy app.core.deno installed, then the one bundled with the app. Handing
    yt-dlp all of them (not just the first) means an outdated node on PATH can
    no longer shadow a perfectly good deno — yt-dlp skips a runtime it can't
    use and moves to the next.
    """
    found = {}

    def _add(key, path):
        if key not in found and path and os.path.isfile(path):
            found[key] = {"path": path}

    try:
        from app.core.deno import managed_deno_path
        managed = managed_deno_path()
    except Exception:      # noqa: BLE001 — absence is just "not available"
        managed = ""
    for key, exe in _RUNTIME_CANDIDATES:
        _add(key, shutil.which(exe))
        for p in _known_install_paths(key):
            _add(key, p)
        if key == "deno":
            _add(key, managed)
            _add(key, _bundled_deno())
    return found


def find_js_runtime():
    """The best usable JS runtime for yt-dlp as a one-entry dict, or None.
    See find_js_runtimes() for the search order."""
    rts = find_js_runtimes()
    if not rts:
        return None
    key = next(iter(rts))
    return {key: rts[key]}


def js_runtime_status():
    """UI-facing status of the JS runtime: name, version, source, availability."""
    rt = find_js_runtime()
    if not rt:
        return {"available": False, "name": "", "version": "", "source": "none"}
    name = next(iter(rt))
    path = rt[name]["path"]
    try:
        from app.core.deno import managed_deno_path
        managed = managed_deno_path()
    except Exception:      # noqa: BLE001
        managed = ""
    bundled = _bundled_deno() or ""
    is_managed = bool(managed) and os.path.normcase(os.path.abspath(path)) == \
        os.path.normcase(os.path.abspath(managed))
    is_bundled = bool(bundled) and os.path.normcase(os.path.abspath(path)) == \
        os.path.normcase(os.path.abspath(bundled))
    source = "managed" if is_managed else ("bundled" if is_bundled else "path")
    return {"available": True, "name": name, "version": _runtime_version(path),
            "source": source}


def download_engine_missing():
    """"" when every REQUIRED download component is present, else a short
    user-facing reason. Required: a JS runtime (deno/node/…) and, since
    v3.41.5, the PO Token helper (bgutil-pot)."""
    from app.i18n import tr
    try:
        if find_js_runtime() is None:
            return tr("To download from YouTube, the app needs a small component "
                      "(deno). Open the download again and install it when asked.")
    except Exception:      # noqa: BLE001
        pass
    try:
        from app.core import pot
        if not pot.installed():
            return tr("The PO Token helper is required for YouTube downloads. "
                      "Install it from the setup dialog or Settings → Download Engine.")
    except Exception:      # noqa: BLE001
        pass
    return ""


def js_runtime_opts():
    """yt-dlp options pointing it at a discovered JS runtime, or {} when none is
    available (yt-dlp then falls back to its own deno-on-PATH auto-detection).

    Prefer this over app.core.deno.deno_ydl_opts() at the yt-dlp call sites: it
    additionally finds node/bun/quickjs, which yt-dlp does NOT auto-enable, so a
    machine that has node but no deno still gets a working runtime. Every
    runtime found is passed, best first, so one broken runtime can't block the
    rest.
    """
    # v3.41.4: every YoutubeDL in the app is built right after this call, so it
    # is the one place that guarantees the optional PO Token helper is
    # registered on the live (possibly just-updated) yt-dlp. No-op without it.
    try:
        from app.core.pot import ensure_registered
        ensure_registered()
    except Exception:      # noqa: BLE001 — the helper is optional
        pass
    rts = find_js_runtimes()
    if not rts:
        return {}
    opts = {"js_runtimes": rts}
    # The challenge SOLVER script ships in the yt_dlp_ejs package. If a build
    # ever goes out without it, let yt-dlp fetch the solver from its official
    # GitHub release instead of silently failing every YouTube download.
    if not _have_ejs():
        opts["remote_components"] = {"ejs:github"}
    return opts


_EJS_OK = None


def _have_ejs():
    global _EJS_OK
    if _EJS_OK is None:
        try:
            import importlib.util
            _EJS_OK = importlib.util.find_spec("yt_dlp_ejs") is not None
        except Exception:      # noqa: BLE001
            _EJS_OK = False
    return _EJS_OK


def _runtime_version(path):
    import re
    import subprocess
    try:
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        out = subprocess.run([path, "--version"], capture_output=True, text=True,
                             encoding="utf-8", errors="replace",
                             timeout=8, creationflags=flags)
        first = (out.stdout or out.stderr or "").strip().splitlines()
        if not first:
            return ""
        # Runtimes print e.g. "deno 2.9.6 (stable, …)" or "v24.19.0"; keep just
        # the version number for a tidy Settings display, falling back to the
        # whole first line when no number is found.
        m = re.search(r"\d+\.\d+(?:\.\d+)?", first[0])
        return m.group(0) if m else first[0].strip()
    except Exception:      # noqa: BLE001
        return ""


# ════════════════════════════════════════════════════════════════════════
#  yt-dlp self-update (download newest wheel into runtime dir)
# ════════════════════════════════════════════════════════════════════════
def update_yt_dlp(on_status=None):
    """Fetch the newest yt-dlp wheel from PyPI, verify its SHA256, and unpack it
    into the runtime dir so load_yt_dlp() picks it up next launch.

    Works in a frozen build (where `pip install --upgrade` cannot run because
    sys.executable is the app exe). Returns (ok, version_or_error).
    """
    import io
    import json
    import urllib.request
    import requests

    def _status(t):
        if on_status:
            on_status(t)

    try:
        _status("Checking for updates…")
        # Both requests go through the configured proxy: on a proxied setup PyPI
        # and the wheel CDN are reachable exactly the same way every other
        # outbound call in the app is, and a direct attempt just times out.
        proxy = configured_proxy()
        meta = json.load(_urlopen(
            urllib.request.Request("https://pypi.org/pypi/yt-dlp/json",
                                   headers={"User-Agent": "YouTubeHunter"}),
            30, proxy))
        version = meta["info"]["version"]
        whl = next(f for f in meta["releases"][version]
                   if f["packagetype"] == "bdist_wheel")

        _status(f"Downloading yt-dlp {version}…")
        proxies = {"http": proxy, "https": proxy} if proxy else None
        data = requests.get(whl["url"], timeout=120, proxies=proxies).content
        if hashlib.sha256(data).hexdigest() != whl["digests"]["sha256"]:
            return False, "Downloader update failed verification (SHA256 mismatch)."

        _status("Installing…")
        rt_dir = _runtime_ytdlp_dir()
        # Fresh unpack: clear any previous copy so a partial extract can't linger.
        if os.path.isdir(rt_dir):
            shutil.rmtree(rt_dir, ignore_errors=True)
        os.makedirs(rt_dir, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            z.extractall(rt_dir)
        _status("Done")
        return True, version
    except Exception as exc:                 # noqa: BLE001
        # A dropped connection mid-download is the commonest failure here (a
        # multi-megabyte wheel over a proxy), and `str(exc)` for it is the bare
        # "[WinError 10054] …" that means nothing to the user.
        return False, explain_network_error(exc, "PyPI")

def find_ffmpeg():
    """Find ffmpeg: try imageio-ffmpeg, then system PATH"""
    import shutil
    try:
        import imageio_ffmpeg
        path = imageio_ffmpeg.get_ffmpeg_exe()
        if os.path.exists(path):
            return path
    except:
        pass
    return shutil.which('ffmpeg')


def prewarm_download_engine():
    """v3.41.3 — pay the engine's one-time costs before the user asks.

    The first download / cut of a session used to spend its "Preparing…" on
    importing yt-dlp (hundreds of extractor modules; seconds in a frozen build
    on a cold disk), staging the ffmpeg directory and locating the JS runtime.
    Called once on a background thread shortly after startup; every step is
    cached, so the real call later finds it all done. Never raises.
    """
    try:
        load_yt_dlp()
        ensure_ffmpeg_dir()
        js_runtime_opts()
        import yt_dlp.extractor.youtube  # noqa: F401 — the extractor we use
    except Exception:      # noqa: BLE001 — warm-up only
        pass
    # Start the (required) PO Token helper so the first video doesn't wait for
    # its BotGuard spin-up.
    try:
        from app.core import pot
        if pot.installed():
            pot.ensure_server()
    except Exception:      # noqa: BLE001
        pass
