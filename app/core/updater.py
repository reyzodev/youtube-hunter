"""app.core.updater - YouTube Hunter in-app updates (GitHub Releases).

UI-free. Three jobs:

  * latest_release()  ask GitHub for the newest published release of
                      UPDATE_REPO and pick the Windows installer asset;
  * download()        stream that installer to %TEMP% with progress,
                      cancellation and a SHA-256 check (GitHub publishes a
                      `digest` for every release asset);
  * launch_installer() start Inno Setup silently with /relaunch=1 so the
                      installer reopens the app once the files are replaced.

Publishing a release = push a tag like v1.2.0 and attach the
`YouTubeHunter-Setup.exe` that build.bat produces. Nothing else is needed.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from app.constants import APP_VERSION, UPDATE_ASSET_HINT, UPDATE_REPO
from app.core.net import _urlopen, configured_proxy

_API = "https://api.github.com/repos/{repo}/releases/latest"
_HEADERS = {
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}


class UpdateCancelled(Exception):
    pass


class UpdateError(Exception):
    """A check/download failure with a message that is safe to show as-is."""


# A real installer is ~250 MB (it ships Qt, QtWebEngine, ffmpeg, deno). Anything
# under this is not the installer, whatever its name says: on the v1.0.0
# release a 4.9 MB source zip had been uploaded as "YouTubeHunter-Setup-1.0.1-x64.exe".
_MIN_INSTALLER_BYTES = 20 * 1024 * 1024
_NOT_AN_EXE_TYPES = ("zip", "x-7z", "x-rar", "gzip", "x-tar", "text/", "json")

_VERSION_RE = re.compile(r"(\d+(?:\.\d+){0,3})")


def parse_version(text):
    """'v1.10.2-beta' -> (1, 10, 2). Missing parts count as 0.

    Only the FIRST dotted number is read, so a tag like 'v1.1-x64' is
    (1, 1, 0) and not (1, 1, 64), which the old findall() produced."""
    m = _VERSION_RE.search(str(text or ""))
    if not m:
        return (0, 0, 0)
    nums = [int(n) for n in m.group(1).split(".")]
    nums += [0] * (3 - len(nums))
    return tuple(nums[:4])


def is_newer(remote, local=APP_VERSION):
    return parse_version(remote) > parse_version(local)


def _looks_like_installer(a):
    name = str(a.get("name", "")).lower()
    if not name.endswith(".exe"):
        return False
    ctype = str(a.get("content_type", "")).lower()
    if any(t in ctype for t in _NOT_AN_EXE_TYPES):
        return False
    if str(a.get("state", "uploaded")) != "uploaded":
        return False          # an upload that never finished
    size = int(a.get("size") or 0)
    return size == 0 or size >= _MIN_INSTALLER_BYTES


def _pick_asset(assets, version=""):
    """The Windows installer among a release's files.

    Order of preference: a real installer (see _looks_like_installer) whose
    name carries this release's version, then one matching
    UPDATE_ASSET_HINT, then any "setup" .exe. A zip renamed to .exe, a
    half-uploaded file or a 32-bit build never wins."""
    exes = [a for a in assets or [] if _looks_like_installer(a)]
    exes = [a for a in exes if "x86" not in a["name"].lower()
            and "32bit" not in a["name"].lower()] or exes
    want = parse_version(version) if version else None
    if want is not None:
        # An installer named for ANOTHER version is the wrong file: installing
        # the 1.0.0 setup from the 1.0.1 release would leave the app on 1.0.0
        # and offer the same "update" again on every launch.
        exes = [a for a in exes if _asset_version(a["name"]) in (None, want)]
    if not exes:
        return None
    hint = UPDATE_ASSET_HINT.lower()

    def score(a):
        n = a["name"].lower()
        return (_asset_version(n) is not None,
                bool(hint) and hint in n,
                "setup" in n,
                int(a.get("size") or 0))
    return max(exes, key=score)


_ASSET_VERSION_RE = re.compile(r"(?<![\d.])v?(\d+\.\d+(?:\.\d+){0,2})(?![\d.])")


def _asset_version(name):
    """'YouTubeHunter-Setup-1.0.1-x64.exe' -> (1, 0, 1); None when the file
    name carries no dotted version ('-x64' is not one)."""
    m = _ASSET_VERSION_RE.search(str(name or "").lower())
    return parse_version(m.group(1)) if m else None


def latest_release(timeout=12):
    """Newest non-draft, non-prerelease release as a plain dict, or raises
    UpdateError with a message the dialog can show."""
    req = urllib.request.Request(_API.format(repo=UPDATE_REPO), headers=_HEADERS)
    try:
        with _urlopen(req, timeout, configured_proxy()) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise UpdateError("No release has been published on GitHub yet.") from exc
        if exc.code in (403, 429):
            reset = exc.headers.get("X-RateLimit-Reset") if exc.headers else None
            when = ""
            try:
                mins = max(1, int((int(reset) - time.time()) / 60)) if reset else 0
                when = f" Try again in about {mins} min." if mins else ""
            except (TypeError, ValueError):
                pass
            raise UpdateError("GitHub is rate-limiting update checks from this "
                              "network." + when) from exc
        raise UpdateError(f"GitHub answered HTTP {exc.code}.") from exc
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise UpdateError("Couldn't reach GitHub to check for updates.") from exc
    tag = data.get("tag_name") or ""
    # The TAG is the version. The release title is free text: v1.0.0 was
    # titled "YouTube Hunter 1.0.1", which no installed copy could ever see.
    asset = _pick_asset(data.get("assets"), tag)
    digest = (asset or {}).get("digest") or ""
    return {
        "tag": tag,
        "version": tag.lstrip("vV") or "0.0.0",
        "name": data.get("name") or tag,
        "notes": (data.get("body") or "").strip(),
        "published": (data.get("published_at") or "")[:10],
        "page": data.get("html_url") or f"https://github.com/{UPDATE_REPO}/releases/latest",
        "asset_name": (asset or {}).get("name", ""),
        "asset_url": (asset or {}).get("browser_download_url", ""),
        "asset_size": int((asset or {}).get("size") or 0),
        "sha256": digest.split(":", 1)[1].lower() if digest.startswith("sha256:") else "",
    }


def update_dir():
    d = os.path.join(tempfile.gettempdir(), "YouTubeHunter-Update")
    os.makedirs(d, exist_ok=True)
    return d


def download(url, filename, expected_size=0, sha256="", progress=None,
             cancelled=None, timeout=30):
    """Stream `url` into the update folder. `progress(done, total, bps)` is
    called at most ~8x/s. Returns the final path. Raises UpdateCancelled."""
    dest = os.path.join(update_dir(), os.path.basename(filename) or "YouTubeHunter-Setup.exe")
    # A finished, verified copy from an earlier attempt: reuse it.
    if sha256 and os.path.isfile(dest) and _sha256(dest) == sha256 \
            and _is_windows_exe(dest):
        if progress:
            progress(os.path.getsize(dest), os.path.getsize(dest), 0)
        return dest
    part = dest + ".part"
    req = urllib.request.Request(url, headers={"Accept": "application/octet-stream"})
    h = hashlib.sha256()
    with _urlopen(req, timeout, configured_proxy()) as resp, open(part, "wb") as out:
        total = int(resp.headers.get("Content-Length") or expected_size or 0)
        done, last_t, last_done, bps = 0, time.monotonic(), 0, 0.0
        while True:
            if cancelled and cancelled():
                raise UpdateCancelled()
            chunk = resp.read(256 * 1024)
            if not chunk:
                break
            out.write(chunk)
            h.update(chunk)
            done += len(chunk)
            now = time.monotonic()
            if now - last_t >= 0.125:
                inst = (done - last_done) / (now - last_t)
                bps = inst if bps == 0 else bps * 0.7 + inst * 0.3   # smoothed
                last_t, last_done = now, done
                if progress:
                    progress(done, total, bps)
    if total and done < total:
        raise IOError("The download stopped early. Check the connection and try again.")
    if not _is_windows_exe(part):
        os.remove(part)
        raise IOError("The file on GitHub isn't a Windows installer, so it was "
                      "discarded. Open the release page instead.")
    if sha256 and h.hexdigest() != sha256:
        os.remove(part)
        raise IOError("The installer failed its integrity check, so it was discarded.")
    os.replace(part, dest)
    if progress:
        progress(done, total or done, 0)
    return dest


def _is_windows_exe(path):
    """Every Windows .exe starts with the two bytes 'MZ'."""
    try:
        with open(path, "rb") as f:
            return f.read(2) == b"MZ"
    except OSError:
        return False


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def is_packaged():
    return bool(getattr(sys, "frozen", False))


def launch_installer(path):
    """Start the installer detached. Packaged app: silent install, then the
    installer reopens the app (/relaunch=1, see installer.iss). Source run:
    the normal wizard, since there is no installed copy being replaced."""
    if is_packaged():
        args = [path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART",
                "/CLOSEAPPLICATIONS", "/relaunch=1"]
    else:
        args = [path]
    flags = 0
    if os.name == "nt":
        flags = 0x00000008 | 0x00000200      # DETACHED_PROCESS | NEW_PROCESS_GROUP
    subprocess.Popen(args, close_fds=True, creationflags=flags)
