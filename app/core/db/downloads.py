"""app.core.db.downloads - Youtube Scrapper."""

import os
import sqlite3

from app.core.db._sqlite import connect as db_connect
import traceback
from datetime import datetime, timezone

from app.core.db.ideas import DATA_DB_PATH
from app.crash import log_crash

# ═════════════════════════════════════════════════════════════════════════
#  DOWNLOADS  —  persisted history behind the Downloads page
# ─────────────────────────────────────────────────────────────────────────
#  One row per download attempt, keyed by video_id (a re-download just
#  overwrites the previous row rather than piling up duplicates, so the
#  page always shows each video's LATEST attempt — matters for someone who
#  downloaded 480p, wasn't happy, and grabbed 1080p a minute later). Status
#  is one of "downloading" / "merging" / "complete" / "failed" / "stopped";
#  progress is 0-100 and only meaningful while status is "downloading" or
#  "stopped". `quality_key` stores the PRESET key (not just its label) so a
#  stopped download can be resumed at the same quality later — including
#  after an app restart, when nothing is left in memory.
# ═════════════════════════════════════════════════════════════════════════
def init_downloads_db():
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS downloads (
                video_id      TEXT PRIMARY KEY,
                title         TEXT,
                thumbnail_url TEXT,
                quality_label TEXT,
                quality_key   TEXT,
                video_url     TEXT,
                status        TEXT NOT NULL DEFAULT 'downloading',
                progress      INTEGER NOT NULL DEFAULT 0,
                filepath      TEXT,
                error_message TEXT,
                file_size       INTEGER NOT NULL DEFAULT 0,
                channel_title     TEXT,
                channel_thumb_url TEXT,
                channel_url       TEXT,
                subscriber_count  INTEGER,
                subs_hidden       INTEGER NOT NULL DEFAULT 0,
                added_at      TEXT NOT NULL,
                updated_at    TEXT NOT NULL
            )
        """)
        # `downloads` may already exist on disk from an older install with
        # fewer columns (same situation as `search_items` / is_favorite
        # above) — CREATE TABLE IF NOT EXISTS is then a silent no-op, and
        # every downloads_upsert() INSERT/UPDATE afterwards references a
        # column that doesn't exist, fails with sqlite3.OperationalError,
        # gets swallowed by the try/except in downloads_upsert(), and the
        # Downloads page never gets a single row — with no visible error
        # anywhere. Patch any missing column onto whatever is already there.
        cur.execute("CREATE INDEX IF NOT EXISTS idx_downloads_added "
                    "ON downloads(added_at)")
        cur.execute("PRAGMA table_info(downloads)")
        cols = {r[1] for r in cur.fetchall()}
        required = {
            "title":         "TEXT",
            "thumbnail_url": "TEXT",
            "quality_label": "TEXT",
            "quality_key":   "TEXT",
            "video_url":     "TEXT",
            "status":        "TEXT NOT NULL DEFAULT 'downloading'",
            "progress":      "INTEGER NOT NULL DEFAULT 0",
            "filepath":      "TEXT",
            "error_message": "TEXT",
            "file_size":     "INTEGER NOT NULL DEFAULT 0",
            "channel_title":     "TEXT",
            "channel_thumb_url": "TEXT",
            "channel_url":       "TEXT",
            "subscriber_count":  "INTEGER",
            "subs_hidden":       "INTEGER NOT NULL DEFAULT 0",
            "added_at":      "TEXT",
            "updated_at":    "TEXT",
        }
        for col, decl in required.items():
            if col not in cols:
                cur.execute(f"ALTER TABLE downloads ADD COLUMN {col} {decl}")
        conn.commit()
        conn.close()
    except Exception:
        log_crash("init_downloads_db failed:\n" + traceback.format_exc())


def downloads_upsert(video_id, title=None, thumbnail_url=None, quality_label=None,
                     status=None, progress=None, filepath=None, error_message=None,
                     channel_title=None, channel_thumb_url=None, channel_url=None,
                     subscriber_count=None, subs_hidden=None,
                     quality_key=None, video_url=None, file_size=None,
                     create_if_missing=True):
    """Insert-or-update a single download row. Only the fields the caller
    actually passes get overwritten — a progress-only call from the hot
    progress-hook path doesn't need (and shouldn't risk blanking) title/
    thumbnail/quality, which are only known at the very start.

    `create_if_missing=False` makes the call UPDATE-ONLY: if the row isn't there
    any more it is silently skipped. Progress/status ticks must pass False —
    otherwise a download the user deleted mid-flight gets INSERTed right back by
    the next tick from its still-unwinding worker, reappearing as a title-less
    "Untitled" row that looks like it's downloading again.
    """
    try:
        now = datetime.now(timezone.utc).isoformat()
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("SELECT * FROM downloads WHERE video_id = ?", (video_id,))
        existing = cur.fetchone()
        if existing is None and not create_if_missing:
            conn.close()
            return False
        if existing is None:
            cur.execute("""
                INSERT INTO downloads
                    (video_id, title, thumbnail_url, quality_label, quality_key,
                     video_url, status,
                     progress, filepath, error_message, file_size,
                     channel_title, channel_thumb_url, channel_url,
                     subscriber_count, subs_hidden,
                     added_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (video_id, title or "", thumbnail_url or "", quality_label or "",
                 quality_key or "", video_url or "",
                 status or "downloading", progress if progress is not None else 0,
                 filepath or "", error_message or "", file_size or 0,
                 channel_title or "", channel_thumb_url or "", channel_url or "",
                 subscriber_count, 1 if subs_hidden else 0, now, now))
        else:
            merged = dict(existing)
            if title is not None: merged["title"] = title
            if thumbnail_url is not None: merged["thumbnail_url"] = thumbnail_url
            if quality_label is not None: merged["quality_label"] = quality_label
            if quality_key is not None: merged["quality_key"] = quality_key
            if video_url is not None: merged["video_url"] = video_url
            if status is not None: merged["status"] = status
            if progress is not None: merged["progress"] = progress
            if filepath is not None: merged["filepath"] = filepath
            if error_message is not None: merged["error_message"] = error_message
            if file_size is not None: merged["file_size"] = file_size
            if channel_title is not None: merged["channel_title"] = channel_title
            if channel_thumb_url is not None: merged["channel_thumb_url"] = channel_thumb_url
            if channel_url is not None: merged["channel_url"] = channel_url
            if subscriber_count is not None: merged["subscriber_count"] = subscriber_count
            if subs_hidden is not None: merged["subs_hidden"] = 1 if subs_hidden else 0
            cur.execute("""
                UPDATE downloads SET title=?, thumbnail_url=?, quality_label=?,
                    quality_key=?, video_url=?,
                    status=?, progress=?, filepath=?, error_message=?, file_size=?,
                    channel_title=?, channel_thumb_url=?, channel_url=?,
                    subscriber_count=?, subs_hidden=?,
                    updated_at=?
                WHERE video_id=?
            """, (merged["title"], merged["thumbnail_url"], merged["quality_label"],
                 merged.get("quality_key") or "", merged.get("video_url") or "",
                 merged["status"], merged["progress"], merged["filepath"],
                 merged["error_message"], merged.get("file_size") or 0,
                 merged.get("channel_title") or "", merged.get("channel_thumb_url") or "",
                 merged.get("channel_url") or "",
                 merged.get("subscriber_count"), merged.get("subs_hidden") or 0,
                 now, video_id))
        conn.commit()
        conn.close()
        return True
    except Exception:
        log_crash("downloads_upsert failed:\n" + traceback.format_exc())
        return False


def downloads_apply_channel_meta(video_id, meta):
    """Fold channel identity harvested during a download onto the library row.

    Called as soon as yt-dlp knows who made the video — normally from the
    pre-flight probe, before any bytes move. This is what makes the player show
    a real subscriber count for a video that was downloaded from a page that had
    not enriched its channel: without it the row kept a channel TITLE and
    nothing else, and the player fell back to "Subscribers hidden" over an
    initials disc.

    Only the fields actually present in `meta` are written (downloads_upsert
    treats None as "leave alone"), and the row must already exist — the download
    inserts it before starting, so a missing row means this call is pointless
    rather than something to fix.
    """
    if not video_id or not meta:
        return False
    return downloads_upsert(
        video_id,
        channel_title=(meta.get("channel_title") or None),
        channel_url=(meta.get("channel_url") or None),
        channel_thumb_url=(meta.get("channel_thumb_url") or None),
        subscriber_count=meta.get("subscriber_count"),
        subs_hidden=meta.get("subs_hidden"),
        create_if_missing=False)


def downloads_list():
    """Newest first — a fresh download should always appear at the top of
    the Downloads page regardless of when an older one finishes."""
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("SELECT * FROM downloads ORDER BY added_at DESC")
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return rows
    except Exception:
        log_crash("downloads_list failed:\n" + traceback.format_exc())
        return []


def downloads_get(video_id):
    """One row as a dict, or None. Used by the v3.40 away notice to put the
    video's real title and thumbnail on the desktop toast."""
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("SELECT * FROM downloads WHERE video_id = ?", (str(video_id),))
        row = cur.fetchone()
        conn.close()
        return dict(row) if row else None
    except Exception:
        log_crash("downloads_get failed:\n" + traceback.format_exc())
        return None


def file_size_of(path):
    """The real on-disk size of a finished download, or 0. What completed rows
    show — never an estimate."""
    try:
        return os.path.getsize(path) if path and os.path.isfile(path) else 0
    except OSError:
        return 0


def downloads_delete(video_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("DELETE FROM downloads WHERE video_id = ?", (video_id,))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False
