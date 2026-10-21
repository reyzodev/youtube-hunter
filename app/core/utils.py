"""app.core.utils - Youtube Scrapper."""

import os
import re
import subprocess
import sys
import webbrowser
from datetime import datetime, timezone

from PySide6.QtCore import QUrl
from PySide6.QtGui import QDesktopServices

from app.i18n import tr

# ═════════════════════════════════════════════════════════════════════════
#  MISC NUMBER / TIME / API HELPERS shared by the new analysis pages
# ═════════════════════════════════════════════════════════════════════════
def parse_iso8601_duration(dur):
    """'PT14M23S' -> total seconds (int)."""
    if not dur:
        return 0
    m = re.match(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", dur)
    if not m:
        return 0
    days, hours, minutes, seconds = (int(g) if g else 0 for g in m.groups())
    return days * 86400 + hours * 3600 + minutes * 60 + seconds


def humanize_count(n):
    try:
        n = float(n)
    except (TypeError, ValueError):
        return "N/A"
    if n >= 1_000_000_000:
        return f"{n/1_000_000_000:.1f}B"
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(int(n))


def parse_iso_utc(dt_str):
    """Parse a YouTube/ISO-8601 timestamp to an aware UTC datetime, or None.

    WHY THIS EXISTS. The Data API's `snippet.publishedAt` is NOT always the
    tidy "...T16:00:02Z" shape. A channel's own `publishedAt` routinely carries
    FRACTIONAL SECONDS — e.g. "2020-04-07T18:46:13.80072Z" — and
    `datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")` raises on that. The old
    `hours_since` swallowed the raise and returned 1.0 (i.e. "one hour ago"),
    so a six-year-old channel was read as brand new; the monetization page then
    divided the channel's LIFETIME views by a 30-day floor and reported billions
    of views a month ("12.0B views / $22M a month" for a channel that does a
    fraction of that). Returning None here lets a caller tell "just published"
    apart from "couldn't read the date" and skip the estimate instead of
    inventing one.

    Normalising before parsing (rather than trusting `fromisoformat`) keeps this
    correct on every Python this app ships on: 'Z' is only understood by
    fromisoformat from 3.11, and more than six fractional digits is rejected by
    every version, while the API happily emits both shapes.
    """
    if not dt_str:
        return None
    s = str(dt_str).strip()
    if not s:
        return None
    # 'Z' (or a lowercase 'z') -> explicit UTC offset.
    if s[-1] in ("Z", "z"):
        s = s[:-1] + "+00:00"
    # Trim fractional seconds to at most 6 digits — the API emits 5, some feeds
    # 7, and fromisoformat refuses more than 6.
    m = re.match(r"^(.*?\.\d{6})\d+([+-]\d{2}:?\d{2})?$", s)
    if m:
        s = m.group(1) + (m.group(2) or "")
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        # Last resort: the seconds-less "...T16:00Z" form.
        try:
            dt = datetime.strptime(s, "%Y-%m-%dT%H:%M%z")
        except ValueError:
            return None
    if dt.tzinfo is None:
        # A timestamp with no offset is UTC by YouTube's own convention.
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def hours_since(published_at):
    """Hours since a UTC timestamp, floored at 1.0 (never zero/negative).

    An unparseable timestamp ALSO floors to 1.0, which is why callers that use
    the value as a divisor (a rate per hour) must prefer `parse_iso_utc` and
    treat a None as "unknown" rather than trusting this fallback — see the
    monetization revenue estimate.
    """
    dt = parse_iso_utc(published_at)
    if dt is None:
        return 1.0
    delta = datetime.now(timezone.utc) - dt
    return max(delta.total_seconds() / 3600, 1.0)


def days_since(published_at):
    """Days (float) since a UTC timestamp, or None when it can't be read.

    None is meaningful and must be respected: a caller that divides by this to
    get a per-day rate has to SKIP the estimate when the date is unreadable,
    rather than substitute a made-up age. That substitution is exactly what
    turned an unreadable channel join date into "30 days old" and a 12-billion
    views-a-month report (see parse_iso_utc).
    """
    dt = parse_iso_utc(published_at)
    if dt is None:
        return None
    return (datetime.now(timezone.utc) - dt).total_seconds() / 86400.0


def days_ago_str(published_at):
    try:
        dt = parse_iso_utc(published_at)
        if dt is None:
            return tr("N/A")
        delta = datetime.now(timezone.utc) - dt
        d = int(delta.total_seconds() // 86400)
        if d < 1:
            h = int(delta.total_seconds() // 3600)
            return tr("{n}h ago").format(n=h) if h > 0 else tr("just now")
        if d < 30:
            return tr("{n}d ago").format(n=d)
        if d < 365:
            return tr("{n}mo ago").format(n=d // 30)
        return tr("{n}y ago").format(n=d // 365)
    except Exception:
        return tr("N/A")


def notif_relative_time(ts):
    """Same 'just now / Xm / Xh / Xd ago' family as days_ago_str(), but for a
    plain local datetime object (the notification list's own timestamps)
    instead of a YouTube-API UTC string."""
    try:
        secs = (datetime.now() - ts).total_seconds()
        if secs < 60:
            return tr("just now")
        mins = int(secs // 60)
        if mins < 60:
            return tr("{n}m ago").format(n=mins)
        hours = int(secs // 3600)
        if hours < 24:
            return tr("{n}h ago").format(n=hours)
        days = int(secs // 86400)
        return tr("{n}d ago").format(n=days)
    except Exception:
        return ""
def desktop_download_dir(subfolder="YouTube"):
    """The user's real Desktop, + subfolder — always this, never tucked
    inside self.save_folder (the CSV-export setting) or next to wherever
    this .py file happens to live, so downloaded videos land somewhere the
    user actually sees them regardless of where the app/project itself is
    checked out.

    On Windows this reads the same 'Shell Folders' registry key Explorer
    itself uses for Desktop, rather than assuming ~/Desktop — a plain
    ~/Desktop guess quietly misses on any machine where OneDrive has
    redirected Desktop elsewhere, which is the *default* on a lot of
    managed / Microsoft-account Windows installs, not an edge case.
    """
    desktop = None
    if sys.platform == "win32":
        try:
            import winreg
            with winreg.OpenKey(
                    winreg.HKEY_CURRENT_USER,
                    r"Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders") as key:
                raw, _ = winreg.QueryValueEx(key, "Desktop")
            desktop = os.path.expandvars(raw) if raw else None
        except Exception:
            desktop = None
    if not desktop:
        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
    return os.path.join(desktop, subfolder)


# Config key for the user's chosen video folder (Settings → Save locations).
VIDEO_FOLDER_KEY = "video_save_folder"


def video_download_dir(subfolder="YouTube"):
    """Where downloaded videos (and cut clips) are written.

    The folder the user picked in Settings → "Videos" when it still exists,
    otherwise the old default: Desktop/<subfolder>. Read fresh from config on
    every call so a change in Settings applies to the very next download
    without a restart.
    """
    try:
        from app.config import load_app_config
        chosen = (load_app_config().get(VIDEO_FOLDER_KEY) or "").strip()
    except Exception:
        chosen = ""
    if chosen and os.path.isdir(chosen):
        return chosen
    return desktop_download_dir(subfolder)


def reveal_in_file_manager(filepath):
    """Open the OS file manager with `filepath` selected/highlighted where
    the platform supports it (Explorer, Finder); falls back to just
    opening its containing folder on Linux, since there's no single
    reliable "select this file" call across every file manager there."""
    if not filepath or not os.path.exists(filepath):
        return False
    try:
        folder = os.path.dirname(filepath)
        if sys.platform == "win32":
            subprocess.Popen(["explorer", "/select,", os.path.normpath(filepath)])
        elif sys.platform == "darwin":
            subprocess.Popen(["open", "-R", filepath])
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(folder))
        return True
    except Exception:
        return False


def ensure_yt_dlp_ready():
    """Zero-config bootstrap for the video-download feature.

    Returns (yt_dlp_module, ffmpeg_location). Delegated to
    app.core.runtime_deps, the single source of truth for the download engine's
    dependencies: it loads yt-dlp (the bundled copy, or a newer one the user
    downloaded via Settings → "Update downloader") and returns an ffmpeg
    *DIRECTORY* holding both ffmpeg and ffprobe — the shape yt-dlp needs to find
    both (a directory `ffmpeg_location` is the only way it locates ffprobe,
    which the "Audio only" mp3 conversion needs). This wrapper is kept so
    existing callers (net.py, the legacy QWidgets page) keep working unchanged;
    new code should call runtime_deps directly.
    """
    from app.core.runtime_deps import ensure_ffmpeg_dir, load_yt_dlp
    return load_yt_dlp(), ensure_ffmpeg_dir()



def local_path_from_url(raw):
    """Turn a value from a QML FileDialog / FolderDialog into a real local path.

    QML hands these over as proper `file://` URLs, which are PERCENT-ENCODED:
    a folder called "Son of Love" arrives as `.../Son%20of%20Love/...` and a
    Persian filename as `%D9%81%D8%A7%DB%8C%D9%84.mp4`. Every VM in this app
    used to just strip the `file:///` scheme, which left those escapes sitting
    in the path — so `os.path.isfile()` returned False, the probe refused the
    file, and the picker looked like it had done nothing at all. The bug was
    invisible on a machine whose user name has no spaces.

    Anything that is not a URL is passed through untouched, so plain paths from
    a command line or from config keep working.
    """
    s = str(raw or "").strip()
    if not s:
        return ""
    if not s.lower().startswith("file:"):
        return s
    try:
        # QUrl knows the platform's rules (drive letters on Windows, UNC paths,
        # the localhost authority) far better than string surgery does.
        path = QUrl(s).toLocalFile()
        if path:
            return path
    except Exception:
        pass
    # Fallback with no Qt: decode the escapes by hand.
    from urllib.parse import unquote, urlsplit
    path = unquote(urlsplit(s).path)
    if os.name == "nt" and re.match(r"^/[A-Za-z]:", path):
        path = path[1:]
    return path


def open_external_url(url):
    """Open a link in the user's real browser (Qt first, stdlib fallback)."""
    if not url:
        return False
    try:
        if QDesktopServices.openUrl(QUrl(url)):
            return True
    except Exception:
        pass
    try:
        webbrowser.open(url)
        return True
    except Exception:
        return False
