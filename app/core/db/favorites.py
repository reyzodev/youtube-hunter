"""app.core.db.favorites - Youtube Scrapper."""

import json
import sqlite3

from app.core.db._sqlite import connect as db_connect
from datetime import datetime, timezone

from app.core.db.archive import _archive_row_key, archive_norm_key
from app.core.db.ideas import DATA_DB_PATH

# ═════════════════════════════════════════════════════════════════════════
#  FAVORITES
# ═════════════════════════════════════════════════════════════════════════
# A favorite is just a search_item with is_favorite=1 — it stays a member of
# whichever keyword/channel section it was already archived under (see
# archive_save_search above), so "Save to Favorite" never needs its own
# separate storage table: it reuses the exact same merge-not-replace rows
# the rest of the archive keeps forever. The Favorites tab in Search
# Archive is then just a filtered view: same groups, same rows, only the
# ones flagged favorite.

def favorite_mark_item(group_id, row, idx=0, favorite=True):
    """Flag (or unflag) one row as a favorite, inside its group. If the row
    somehow isn't archived yet it is inserted here, so favoriting never
    depends on the auto-archive step having already run. Returns
    (changed, total_favorites_now_in_group)."""
    if group_id is None:
        return False, 0
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    vid = _archive_row_key(row, idx)
    blob = json.dumps(row, ensure_ascii=False)
    flag = 1 if favorite else 0
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT id, is_favorite FROM search_items "
                "WHERE group_id = ? AND video_id = ?", (group_id, vid))
    found = cur.fetchone()
    if found:
        item_id, was_fav = found
        changed = bool(was_fav) != bool(favorite)
        cur.execute("UPDATE search_items SET row = ?, last_seen = ?, "
                    "is_favorite = ? WHERE id = ?", (blob, now, flag, item_id))
    else:
        cur.execute("INSERT INTO search_items (group_id, video_id, row, "
                    "first_seen, last_seen, is_favorite) VALUES (?, ?, ?, ?, ?, ?)",
                    (group_id, vid, blob, now, now, flag))
        changed = bool(favorite)
    cur.execute("SELECT COUNT(*) FROM search_items "
                "WHERE group_id = ? AND is_favorite = 1", (group_id,))
    total = cur.fetchone()[0]
    conn.commit()
    conn.close()
    return changed, total


def favorite_unmark_item(group_id, item_key):
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.execute("UPDATE search_items SET is_favorite = 0 "
                     "WHERE group_id = ? AND video_id = ?", (group_id, item_key))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def favorite_unmark_all_in_group(group_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.execute("UPDATE search_items SET is_favorite = 0 WHERE group_id = ?",
                     (group_id,))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def favorite_clear_all():
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.execute("UPDATE search_items SET is_favorite = 0")
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def favorite_resolve_group_id(query):
    """Look up the group a live (not-yet-opened-from-the-archive) search
    result belongs to, by the same normalised key archive_save_search()
    files it under. Never creates one — a row on screen has always just
    been through the auto-archive step already."""
    key = archive_norm_key(query)
    if not key:
        return None
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT id FROM search_groups WHERE key = ?", (key,))
        found = cur.fetchone()
        conn.close()
        return found[0] if found else None
    except Exception:
        return None


def favorite_ensure_channel_group(channel_id, channel_title):
    """Fallback bucket for a favorite that can't be tied to any active
    keyword/channel search context — files it under a channel-mode section
    keyed by channel id, so repeat favorites from the same channel keep
    landing in the same place."""
    key = archive_norm_key(f"channel:{channel_id or channel_title or ''}")
    if not key:
        return None
    title = channel_title or channel_id or "—"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT id FROM search_groups WHERE key = ?", (key,))
    found = cur.fetchone()
    if found:
        gid = found[0]
        cur.execute("UPDATE search_groups SET updated_at = ? WHERE id = ?", (now, gid))
    else:
        cur.execute("INSERT INTO search_groups (key, title, mode, source, params, "
                    "run_count, created_at, updated_at) VALUES (?, ?, 'channel', "
                    "'favorite', '{}', 0, ?, ?)", (key, title, now, now))
        gid = cur.lastrowid
    conn.commit()
    conn.close()
    return gid


def archive_list_favorite_groups():
    """Same shape as archive_list_groups(), but scoped to sections that have
    at least one favorited item — item_count here means "favorited", not
    "archived"."""
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("""
            SELECT g.*, (SELECT COUNT(*) FROM search_items i
                         WHERE i.group_id = g.id AND i.is_favorite = 1) AS item_count
            FROM search_groups g
            WHERE (SELECT COUNT(*) FROM search_items i
                   WHERE i.group_id = g.id AND i.is_favorite = 1) > 0
            ORDER BY g.updated_at DESC
        """)
        out = [dict(r) for r in cur.fetchall()]
        conn.close()
        return out
    except Exception:
        return []
