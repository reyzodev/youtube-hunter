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


def parse_version(text):
    """'v1.10.2-beta' -> (1, 10, 2). Missing parts count as 0."""
    nums = re.findall(r"\d+", str(text or ""))[:4]
    parts = [int(n) for n in nums] + [0] * (3 - len(nums))
    return tuple(parts[:4]) if parts else (0, 0, 0)


def is_newer(remote, local=APP_VERSION):
    return parse_version(remote) > parse_version(local)


def _pick_asset(assets):
    """The Windows installer among a release's files."""
    exes = [a for a in assets or []
            if str(a.get("name", "")).lower().endswith(".exe")]
    if not exes:
        return None
    hint = UPDATE_ASSET_HINT.lower()
    for a in exes:
        if hint and hint in a["name"].lower():
            return a
    for a in exes:
        if "setup" in a["name"].lower():
            return a
    return exes[0]


def latest_release(timeout=12):
    """Newest non-draft, non-prerelease release as a plain dict, or raises."""
    req = urllib.request.Request(_API.format(repo=UPDATE_REPO), headers=_HEADERS)
    with _urlopen(req, timeout, configured_proxy()) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    tag = data.get("tag_name") or ""
    asset = _pick_asset(data.get("assets"))
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
    if sha256 and os.path.isfile(dest) and _sha256(dest) == sha256:
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
    if sha256 and h.hexdigest() != sha256:
        os.remove(part)
        raise IOError("The installer failed its integrity check, so it was discarded.")
    os.replace(part, dest)
    if progress:
        progress(done, total or done, 0)
    return dest


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
