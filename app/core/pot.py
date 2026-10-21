"""app.core.pot - YouTube Hunter.

v3.41.4 — optional PO Token helper (bgutil-pot, the Rust build of
"BgUtils POT Provider").

What a PO Token is
------------------
YouTube asks the WEB family of player clients (web, web_safari, mweb,
tv_simply, web_music, web_creator) to prove their requests come from a real
browser. The proof is a "Proof of Origin" token minted by Google's BotGuard
JavaScript, bound to the video id. Without it those clients' stream URLs
answer 403, or the client is handed a THIN list (the 360p-only answer the
v3.41.2 ladder was built to detect). That happens most on flagged IPs: VPN /
datacenter exits, shared NAT.

What bgutil-pot does
--------------------
It runs BotGuard (inside an embedded V8) and hands yt-dlp a fresh token per
video. Clients that need NO token (tv, android_vr, web_embedded) are not
affected; android / ios tokens need DroidGuard / iOSGuard and this helper can
NOT make them. So: it widens which clients work on a flagged network, it does
not replace cookies for a real "sign in to confirm" block.

Why the Rust build (not the Node one)
-------------------------------------
The Node/TypeScript provider needs Node >= 22 (or deno), a git clone, `npm ci`
with a native `canvas` dependency, and a `tsc` build — not something a
customer can be asked to do. The Rust build is ONE self-contained exe
(~44 MB) with the same HTTP API, so it can be shipped or fetched like deno.

How it is wired (no third-party plugin files needed)
----------------------------------------------------
* The exe is looked for in assets/bin (bundled), the managed folder beside
  config.json (installed from Settings), then PATH.
* It is started LAZILY, the first time yt-dlp asks for a token, as an HTTP
  server bound to 127.0.0.1 on a random free port (its default is every
  interface, [::]:4416 — never used here). On Windows it is put in a job
  object, so it dies with the app even after a crash.
* A tiny PoTokenProvider (yt-dlp's own provider framework, 2025.05.22+) is
  registered on the live yt-dlp module and talks to that server. Any failure
  reads as "no token" and yt-dlp carries on exactly as it would without it.
"""

import atexit
import hashlib
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request

from app.config import CONFIG_PATH, load_app_config

POT_VERSION = "0.8.1"
_REPO = "https://github.com/jim60105/bgutil-ytdlp-pot-provider-rs"
# Pinned per release asset (from the v0.8.1 release page). A download whose
# hash doesn't match is thrown away — the exe is never trusted on TLS alone.
_ASSETS = {
    ("win32", "x86_64"):  ("bgutil-pot-windows-x86_64.exe",
                           "25d6b05c79176aa792454c3d1727922ca47e56cf11cb1e866615d751819b14a0"),
    ("linux", "x86_64"):  ("bgutil-pot-linux-x86_64",
                           "e7c264a574fa2705b6e5dc62283a8a4e80130f27b9d7e9df44e6b09aa6151a87"),
    ("linux", "aarch64"): ("bgutil-pot-linux-aarch64",
                           "4f4a1f681dba45e695e1c14d314517da180a1fd374afd09d634fd80ef6d0284b"),
    ("darwin", "x86_64"): ("bgutil-pot-macos-x86_64",
                           "0391175fa938c7fabbb8b40a40bd43182ef75af97e1dd3fab56eb23b4ac3e113"),
    ("darwin", "aarch64"): ("bgutil-pot-macos-aarch64",
                            "34b83baf0a557fecaa6d67a8177e53e169c2ccf987182883a4bae289a7176883"),
}
# The WEB family — the clients a BotGuard token is valid for.
_WEB_CLIENTS = ("web", "web_safari", "mweb", "tv_simply", "web_music",
                "web_creator", "web_embedded", "tv")
_CONFIG_KEY = "pot_helper"          # legacy key; v3.41.5 the helper is REQUIRED
_START_TIMEOUT_S = 15.0
_TOKEN_TIMEOUT_S = 25.0
_RETRY_AFTER_FAIL_S = 120.0         # a server that won't start isn't retried every video

_lock = threading.RLock()
_proc = None
_port = 0
_last_fail = 0.0
_job = None


# ════════════════════════════════════════════════════════════════════════
#  discovery
# ════════════════════════════════════════════════════════════════════════
def _exe_name():
    return "bgutil-pot.exe" if sys.platform == "win32" else "bgutil-pot"


def _platform_key():
    plat = "win32" if sys.platform == "win32" else (
        "darwin" if sys.platform == "darwin" else "linux")
    arch = (platform.machine() or "").lower()
    arch = "aarch64" if arch in ("arm64", "aarch64") else "x86_64"
    if plat == "win32":
        arch = "x86_64"          # x64 build runs under emulation on ARM64 Windows
    return plat, arch


def pot_dir():
    """Managed install folder, beside config.json (like the managed deno)."""
    return os.path.join(os.path.dirname(CONFIG_PATH), "pot")


def managed_path():
    p = os.path.join(pot_dir(), _exe_name())
    return p if os.path.isfile(p) and os.path.getsize(p) > 5_000_000 else ""


def _bundled_path():
    try:
        from app.paths import asset_path
        p = asset_path("assets", "bin", _exe_name())
        return p if os.path.isfile(p) else ""
    except Exception:      # noqa: BLE001
        return ""


def find_exe():
    """(path, source) — source is "managed" | "bundled" | "path" | ""."""
    for path, src in ((managed_path(), "managed"), (_bundled_path(), "bundled"),
                      (shutil.which("bgutil-pot") or "", "path")):
        if path:
            return path, src
    return "", ""


def enabled():
    """v3.41.5: the helper is a REQUIRED part of the download engine (like the
    JS runtime), so it can no longer be switched off. An old config that still
    says "off" is ignored."""
    return True


def set_enabled(on):
    """Kept for API compatibility. The helper is mandatory, so this only clears
    a legacy "off" value from config and never stops the server."""
    try:
        from app.config import save_app_config
        cfg = load_app_config()
        if cfg.get(_CONFIG_KEY) == "off":
            cfg[_CONFIG_KEY] = "auto"
            save_app_config(cfg)
    except Exception:      # noqa: BLE001
        pass


def installed():
    """True when a bgutil-pot exe can be found (managed / bundled / PATH)."""
    return bool(find_exe()[0])


def status():
    path, src = find_exe()
    return {"installed": bool(path), "source": src, "enabled": enabled(),
            "running": is_running(), "version": POT_VERSION if src == "managed" else ""}


# ════════════════════════════════════════════════════════════════════════
#  server lifecycle
# ════════════════════════════════════════════════════════════════════════
def _free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _opener():
    # localhost only: never through the user's proxy
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def _ping(port, timeout=1.5):
    try:
        with _opener().open(f"http://127.0.0.1:{port}/ping", timeout=timeout) as r:
            return r.status == 200
    except Exception:      # noqa: BLE001
        return False


def is_running():
    return _proc is not None and _proc.poll() is None and _port > 0


def _attach_job(proc):
    """Windows: tie the server to this process with a kill-on-close job object,
    so a crash or a Task-Manager kill of the app can't leave it running."""
    global _job
    if sys.platform != "win32":
        return
    try:
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        if _job is None:
            job = k32.CreateJobObjectW(None, None)
            if not job:
                return

            class _BASIC(ctypes.Structure):
                _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64),
                            ("PerJobUserTimeLimit", ctypes.c_int64),
                            ("LimitFlags", wintypes.DWORD),
                            ("MinimumWorkingSetSize", ctypes.c_size_t),
                            ("MaximumWorkingSetSize", ctypes.c_size_t),
                            ("ActiveProcessLimit", wintypes.DWORD),
                            ("Affinity", ctypes.c_size_t),
                            ("PriorityClass", wintypes.DWORD),
                            ("SchedulingClass", wintypes.DWORD)]

            class _IO(ctypes.Structure):
                _fields_ = [(n, ctypes.c_uint64) for n in (
                    "ReadOperationCount", "WriteOperationCount",
                    "OtherOperationCount", "ReadTransferCount",
                    "WriteTransferCount", "OtherTransferCount")]

            class _EXT(ctypes.Structure):
                _fields_ = [("BasicLimitInformation", _BASIC),
                            ("IoInfo", _IO),
                            ("ProcessMemoryLimit", ctypes.c_size_t),
                            ("JobMemoryLimit", ctypes.c_size_t),
                            ("PeakProcessMemoryUsed", ctypes.c_size_t),
                            ("PeakJobMemoryUsed", ctypes.c_size_t)]
            info = _EXT()
            info.BasicLimitInformation.LimitFlags = 0x2000   # KILL_ON_JOB_CLOSE
            k32.SetInformationJobObject(job, 9, ctypes.byref(info),
                                        ctypes.sizeof(info))
            _job = job
        k32.AssignProcessToJobObject(_job, int(proc._handle))
    except Exception:      # noqa: BLE001 — atexit still stops it on a clean exit
        pass


def ensure_server():
    """Start the server if needed. Returns the port, or 0 when unavailable."""
    global _proc, _port, _last_fail
    if not enabled():
        return 0
    with _lock:
        if is_running():
            return _port
        if _last_fail and time.monotonic() - _last_fail < _RETRY_AFTER_FAIL_S:
            return 0
        exe, _src = find_exe()
        if not exe:
            return 0
        port = _free_port()
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        try:
            proc = subprocess.Popen(
                [exe, "server", "--host", "127.0.0.1", "--port", str(port)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, creationflags=flags)
        except Exception:      # noqa: BLE001
            _last_fail = time.monotonic()
            return 0
        _attach_job(proc)
        deadline = time.monotonic() + _START_TIMEOUT_S
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            if _ping(port):
                _proc, _port, _last_fail = proc, port, 0.0
                return port
            time.sleep(0.15)
        try:
            proc.kill()
        except Exception:      # noqa: BLE001
            pass
        _last_fail = time.monotonic()
        try:
            from app.crash import log_crash
            log_crash("pot: bgutil-pot server did not start")
        except Exception:      # noqa: BLE001
            pass
        return 0


def stop():
    global _proc, _port
    with _lock:
        p, _proc, _port = _proc, None, 0
    if p is not None and p.poll() is None:
        try:
            p.terminate()
            p.wait(timeout=3)
        except Exception:      # noqa: BLE001
            try:
                p.kill()
            except Exception:  # noqa: BLE001
                pass


atexit.register(stop)


def fetch_token(content_binding, proxy="", bypass_cache=False):
    """(po_token, expires_at_epoch_or_None) from the local server, or ("", None)."""
    port = ensure_server()
    if not port or not content_binding:
        return "", None
    body = {"content_binding": content_binding, "bypass_cache": bool(bypass_cache)}
    if proxy:
        body["proxy"] = proxy
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/get_pot",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with _opener().open(req, timeout=_TOKEN_TIMEOUT_S) as r:
            data = json.loads(r.read().decode("utf-8") or "{}")
    except Exception:      # noqa: BLE001
        return "", None
    tok = (data.get("po_token") or data.get("poToken") or "").strip()
    exp = data.get("expires_at") or data.get("expiresAt")
    exp_ts = None
    if isinstance(exp, (int, float)):
        exp_ts = int(exp)
    elif isinstance(exp, str) and exp:
        try:
            from datetime import datetime
            exp_ts = int(datetime.fromisoformat(exp.replace("Z", "+00:00")).timestamp())
        except Exception:  # noqa: BLE001
            exp_ts = None
    return tok, exp_ts


# ════════════════════════════════════════════════════════════════════════
#  yt-dlp provider (registered on the live yt-dlp module)
# ════════════════════════════════════════════════════════════════════════
_registered_on = None     # id() of the yt_dlp module the provider is registered on


def ensure_registered():
    """Register the provider on the CURRENT yt-dlp module. Idempotent and cheap;
    called before every YoutubeDL is built (see runtime_deps.js_runtime_opts),
    so a reloaded / updated yt-dlp gets it again. Never raises."""
    global _registered_on
    mod = sys.modules.get("yt_dlp")
    if mod is None or _registered_on == id(mod):
        return
    if not find_exe()[0]:
        return            # nothing to talk to: stay out of yt-dlp's way entirely
    try:
        from yt_dlp.extractor.youtube.pot.provider import (
            PoTokenContext, PoTokenProvider, PoTokenProviderRejectedRequest,
            PoTokenResponse, register_provider)
        try:
            from yt_dlp.extractor.youtube.pot.utils import get_webpo_content_binding
        except Exception:  # noqa: BLE001
            get_webpo_content_binding = None
    except Exception:      # noqa: BLE001 — yt-dlp older than 2025.05.22
        _registered_on = id(mod)
        return

    class YTHunterBgutilPTP(PoTokenProvider):   # name must end in PTP
        PROVIDER_VERSION = POT_VERSION
        BUG_REPORT_LOCATION = _REPO + "/issues"
        _SUPPORTED_CLIENTS = _WEB_CLIENTS
        _SUPPORTED_CONTEXTS = (PoTokenContext.GVS, PoTokenContext.PLAYER,
                               PoTokenContext.SUBS)

        def is_available(self):
            return enabled() and bool(find_exe()[0])

        def _real_request_pot(self, request):
            binding = None
            if get_webpo_content_binding is not None:
                try:
                    res = get_webpo_content_binding(request)
                    binding = res[0] if isinstance(res, tuple) else res
                except Exception:   # noqa: BLE001
                    binding = None
            binding = binding or getattr(request, "video_id", None) \
                or getattr(request, "visitor_data", None)
            if not binding:
                raise PoTokenProviderRejectedRequest("no content binding")
            tok, exp = fetch_token(binding,
                                   proxy=getattr(request, "request_proxy", "") or "",
                                   bypass_cache=bool(getattr(request, "bypass_cache", False)))
            if not tok:
                raise PoTokenProviderRejectedRequest("bgutil-pot gave no token")
            return PoTokenResponse(po_token=tok, expires_at=exp)

    try:
        register_provider(YTHunterBgutilPTP)
    except Exception:      # noqa: BLE001 — already registered / API changed
        pass
    _registered_on = id(mod)


# ════════════════════════════════════════════════════════════════════════
#  install (Settings → "Install helper")
# ════════════════════════════════════════════════════════════════════════
def install(on_progress=None, should_cancel=None):
    """Download the pinned release asset, verify SHA-256, test-run, swap in.
    Returns (ok, error)."""
    import requests
    from app.core.net import configured_proxy
    key = _platform_key()
    if key not in _ASSETS:
        return False, "No helper build for this platform."
    name, sha = _ASSETS[key]
    url = f"{_REPO}/releases/download/v{POT_VERSION}/{name}"
    os.makedirs(pot_dir(), exist_ok=True)
    tmp = os.path.join(pot_dir(), _exe_name() + ".part")
    proxy = configured_proxy()
    routes = [{"http": proxy, "https": proxy}] if proxy else []
    routes.append(None)
    last = ""
    for proxies in routes:
        try:
            h = hashlib.sha256()
            with requests.get(url, stream=True, timeout=(15, 60), proxies=proxies,
                              headers={"User-Agent": "YouTubeHunter (pot installer)"}) as r:
                r.raise_for_status()
                total = int(r.headers.get("content-length") or 0)
                done = 0
                with open(tmp, "wb") as f:
                    for chunk in r.iter_content(256 * 1024):
                        if should_cancel is not None and should_cancel():
                            raise RuntimeError("cancelled")
                        f.write(chunk)
                        h.update(chunk)
                        done += len(chunk)
                        if on_progress:
                            on_progress(done, total)
            if h.hexdigest() != sha:
                last = "Download failed verification (SHA-256 mismatch)."
                continue
            if sys.platform != "win32":
                os.chmod(tmp, 0o755)
            flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            subprocess.run([tmp, "--version"], capture_output=True, timeout=20,
                           creationflags=flags, check=True)
            stop()
            os.replace(tmp, os.path.join(pot_dir(), _exe_name()))
            global _last_fail
            _last_fail = 0.0
            return True, ""
        except Exception as exc:   # noqa: BLE001
            last = str(exc)
            if last == "cancelled":
                break
    try:
        os.remove(tmp)
    except OSError:
        pass
    return False, last or "download failed"


def install_from_file(path):
    """Offline install: copy a bgutil-pot exe the user already has, after a
    `--version` test run. Returns (ok, error)."""
    try:
        if not path or not os.path.isfile(path):
            return False, "File not found."
        if os.path.getsize(path) < 5_000_000:
            return False, "That file is too small to be bgutil-pot."
        os.makedirs(pot_dir(), exist_ok=True)
        tmp = os.path.join(pot_dir(), _exe_name() + ".part")
        shutil.copyfile(path, tmp)
        if sys.platform != "win32":
            os.chmod(tmp, 0o755)
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        subprocess.run([tmp, "--version"], capture_output=True, timeout=20,
                       creationflags=flags, check=True)
        stop()
        os.replace(tmp, os.path.join(pot_dir(), _exe_name()))
        global _last_fail
        _last_fail = 0.0
        return True, ""
    except Exception as exc:   # noqa: BLE001
        try:
            os.remove(os.path.join(pot_dir(), _exe_name() + ".part"))
        except OSError:
            pass
        return False, str(exc) or "install failed"


def uninstall():
    stop()
    p = managed_path()
    if p:
        try:
            os.remove(p)
        except OSError:
            return False
    return True
