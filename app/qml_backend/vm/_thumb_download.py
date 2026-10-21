"""app.qml_backend.vm._thumb_download - YouTube Hunter (QML).

Shared helper for the "download this video's thumbnail" action on the Niche
Finder and Search Archive grid cards (NicheCard). Kept out of the individual
ViewModels so both route through identical logic: the destination folder is
asked for ONCE (via a QML FolderDialog on the page) and then remembered in
config, and the image is normalised to the standard frame size for its format —
1920×1080 for long-form, 1080×1920 for a Short — at high quality.

The Qt signal/slot boilerplate still lives on each VM (a Signal must be a class
attribute of the QObject); these functions carry the reusable behaviour the
slots delegate to.
"""

import base64
import os
import re
import threading

from app.config import load_app_config, save_app_config
from app.core.thumbs import save_thumbnail_to
from app.core.utils import local_path_from_url

_ILLEGAL_FILENAME_RE = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_WHITESPACE_RE = re.compile(r"\s+")

# The two frames a creator actually needs: a 16:9 long-form thumbnail and a 9:16
# vertical Short cover. YouTube serves neither size (maxres is 1280×720), so the
# fetched image is scaled to cover the target and centre-cropped — see
# thumbs._write_resized_thumbnail.
THUMB_SIZE_LONG = (1920, 1080)
THUMB_SIZE_SHORT = (1080, 1920)

# One shared config key, so the folder picked in Niche Finder is also the one
# Search Archive uses (and vice versa) — it's the same "where do my thumbnails
# go" preference either way.
THUMB_FOLDER_KEY = "thumb_save_folder"


def thumb_folder():
    """The remembered thumbnail-save folder, or "" if none is set / it's gone."""
    folder = (load_app_config().get(THUMB_FOLDER_KEY) or "").strip()
    return folder if folder and os.path.isdir(folder) else ""


def remember_thumb_folder(folder):
    """Persist the thumbnail-save folder. Accepts a file:// URL (from the QML
    FolderDialog) or a plain path. Returns True if it was stored."""
    folder = local_path_from_url(folder)
    folder = os.path.normpath(folder) if folder else ""
    if not folder or not os.path.isdir(folder):
        return False
    cfg = load_app_config()
    cfg[THUMB_FOLDER_KEY] = folder
    save_app_config(cfg)
    return True


def safe_thumb_name(title, fallback="thumbnail"):
    """A filesystem-safe base filename from a video title (keeps Persian; strips
    only characters illegal on Windows/macOS/Linux). No extension."""
    text = (title or "").strip()
    cleaned = _ILLEGAL_FILENAME_RE.sub("", text).strip(" .")
    cleaned = _WHITESPACE_RE.sub(" ", cleaned)
    return cleaned[:80] or fallback


def start_thumb_download(thumb_id, title, done_signal, tr, is_short=False):
    """Kick off a thumbnail download on a daemon thread.

    `thumb_id` is the base64 URL the grid card binds (`image://thumbs/<id>`),
    decoded back to the real URL here. `is_short` picks the output frame:
    1080×1920 for a Short, 1920×1080 for long-form. `done_signal` is the VM's
    queued `(path, error)` Signal, emitted when the worker finishes. Returns a
    ("", warn_or_error_message_kind) tuple to surface immediately when it can't
    even start (no folder / no url), or None when a worker was launched.
    """
    folder = thumb_folder()
    if not folder:
        return (tr("Choose a folder to save thumbnails to first."), "warn")
    try:
        url = base64.b64decode((thumb_id or "").encode("ascii")).decode("utf-8")
    except Exception:
        url = ""
    if not url:
        return (tr("This video has no thumbnail to download."), "error")

    size = THUMB_SIZE_SHORT if is_short else THUMB_SIZE_LONG
    # The size goes in the filename so a Short cover and a long-form frame for
    # the same video never collide, and it's obvious which is which on disk.
    base = f"{safe_thumb_name(title)} {size[0]}x{size[1]}"
    dest = os.path.join(folder, base + ".jpg")
    # Avoid clobbering an existing file with the same title.
    n = 2
    while os.path.exists(dest):
        dest = os.path.join(folder, f"{base} ({n}).jpg")
        n += 1

    def worker(_url=url, _dest=dest, _size=size):
        try:
            saved = save_thumbnail_to(_url, _dest, target_size=_size)
            done_signal.emit(saved, "")
        except Exception as exc:      # noqa: BLE001 — surfaced to the user
            done_signal.emit("", str(exc))

    threading.Thread(target=worker, daemon=True).start()
    return None
