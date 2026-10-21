"""app.core.db.archive - Youtube Scrapper."""

import json
import re
import sqlite3

from app.core.db._sqlite import connect as db_connect
from datetime import datetime, timezone

from app.core.db.ideas import DATA_DB_PATH

# ═════════════════════════════════════════════════════════════════════════
#  SEARCH ARCHIVE — permanent, per-keyword result library
#
#  `niche_cache` is a *cache*: it expires after 12 h and self-trims to the
#  last 40 entries, so results vanish. The archive below never expires and is
#  never trimmed automatically — one group per keyword, results merged in
#  place so re-running the same keyword refreshes stats instead of
#  duplicating rows.
# ═════════════════════════════════════════════════════════════════════════
def init_archive_db():
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS search_groups (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            key         TEXT UNIQUE,
            title       TEXT,
            mode        TEXT DEFAULT 'keyword',
            source      TEXT DEFAULT 'api',
            params      TEXT,
            run_count   INTEGER DEFAULT 0,
            created_at  TEXT,
            updated_at  TEXT,
            is_favorite INTEGER DEFAULT 0,
            channel_thumb TEXT DEFAULT ''
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS search_items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id    INTEGER,
            video_id    TEXT,
            row         TEXT,
            first_seen  TEXT,
            last_seen   TEXT,
            is_favorite INTEGER DEFAULT 0,
            UNIQUE(group_id, video_id)
        )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_items_group "
                "ON search_items(group_id)")
    # `is_favorite` was added after this table already existed on disk for
    # earlier installs — CREATE TABLE IF NOT EXISTS above is a no-op there,
    # so add the column by hand the first time this runs against an old DB.
    cur.execute("PRAGMA table_info(search_items)")
    cols = {r[1] for r in cur.fetchall()}
    if "is_favorite" not in cols:
        cur.execute("ALTER TABLE search_items ADD COLUMN is_favorite INTEGER DEFAULT 0")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_items_favorite "
                "ON search_items(group_id, is_favorite)")
    # `is_favorite` / `channel_thumb` on search_groups arrived after the table
    # already existed on disk — same treatment as search_items.is_favorite
    # above: add whichever column is missing, then backfill channel logos for
    # channel sections saved before the column existed (read once per group
    # from its first stored row; groups already stamped are skipped).
    cur.execute("PRAGMA table_info(search_groups)")
    gcols = {r[1] for r in cur.fetchall()}
    if "is_favorite" not in gcols:
        cur.execute("ALTER TABLE search_groups ADD COLUMN is_favorite INTEGER DEFAULT 0")
    if "channel_thumb" not in gcols:
        cur.execute("ALTER TABLE search_groups ADD COLUMN channel_thumb TEXT DEFAULT ''")
    try:
        cur.execute("SELECT id FROM search_groups WHERE mode = 'channel' "
                    "AND (channel_thumb IS NULL OR channel_thumb = '')")
        for (gid,) in cur.fetchall():
            cur.execute("SELECT row FROM search_items WHERE group_id = ? "
                        "ORDER BY id ASC LIMIT 1", (gid,))
            first = cur.fetchone()
            if not first:
                continue
            try:
                blob = json.loads(first[0])
            except Exception:
                continue
            thumb = ((blob or {}).get("channel_thumb_url") or "").strip()
            if thumb:
                cur.execute("UPDATE search_groups SET channel_thumb = ? "
                            "WHERE id = ?", (thumb, gid))
    except Exception:
        pass
    conn.commit()
    conn.close()


def archive_norm_key(text):
    """Group key for a query. Case/spacing/order-insensitive so
    'AI, reddit' and 'reddit ,ai' land in the same group."""
    parts = [p.strip().lower() for p in str(text or "").split(",")]
    parts = [" ".join(p.split()) for p in parts if p.strip()]
    return " , ".join(sorted(parts))


def _archive_row_key(row, idx=0):
    return (row.get("video_id") or row.get("channel_id")
            or row.get("video_url") or f"row-{idx}")


def format_channel_handle(title):
    """Best-effort '@handle' for a channel-mode archive section. The stored
    title is whatever the user typed into the channel field — a handle, a
    full channel URL, or a plain name — so pull a clean handle out of a URL
    if there is one, otherwise just make sure it reads like a handle."""
    raw = (title or "").strip()
    if not raw:
        return "@—"
    m = re.search(r"@([A-Za-z0-9._-]+)", raw)
    if m:
        return "@" + m.group(1)
    if raw.startswith("@"):
        return raw
    return "@" + re.sub(r"\s+", "", raw)


def archive_save_search(query, params, rows):
    """Merge a finished search into its keyword group.

    Returns (group_id, n_new, n_updated). Rows already in the group keep their
    original `first_seen` but get the fresh stats — that is the whole point of
    merge mode: the group grows over time and never goes stale."""
    key = archive_norm_key(query)
    if not key:
        return None, 0, 0
    title = " , ".join(p.strip() for p in str(query).split(",") if p.strip())
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    mode = (params or {}).get("mode", "keyword")
    # Channel sections carry the channel's own logo on the section card, so
    # remember one thumb URL at save time (first row that has one) rather
    # than parsing blobs on every list.
    thumb = ""
    if mode == "channel":
        for row in rows or []:
            t = ((row or {}).get("channel_thumb_url") or "").strip()
            if t:
                thumb = t
                break
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT id, run_count, channel_thumb FROM search_groups "
                "WHERE key = ?", (key,))
    found = cur.fetchone()
    p_json = json.dumps(params or {}, ensure_ascii=False)
    if found:
        gid, runs, old_thumb = found[0], (found[1] or 0), (found[2] or "")
        cur.execute("UPDATE search_groups SET title = ?, mode = ?, source = ?, "
                    "params = ?, run_count = ?, updated_at = ?, channel_thumb = ? "
                    "WHERE id = ?",
                    (title, mode,
                     (params or {}).get("source", "api"), p_json,
                     runs + 1, now, thumb or old_thumb, gid))
    else:
        cur.execute("INSERT INTO search_groups (key, title, mode, source, params, "
                    "run_count, created_at, updated_at, channel_thumb) "
                    "VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)",
                    (key, title, mode,
                     (params or {}).get("source", "api"), p_json, now, now, thumb))
        gid = cur.lastrowid

    new_n = upd_n = 0
    for idx, row in enumerate(rows or []):
        vid = _archive_row_key(row, idx)
        blob = json.dumps(row, ensure_ascii=False)
        cur.execute("SELECT id FROM search_items WHERE group_id = ? AND video_id = ?",
                    (gid, vid))
        if cur.fetchone():
            cur.execute("UPDATE search_items SET row = ?, last_seen = ? "
                        "WHERE group_id = ? AND video_id = ?", (blob, now, gid, vid))
            upd_n += 1
        else:
            cur.execute("INSERT INTO search_items (group_id, video_id, row, "
                        "first_seen, last_seen) VALUES (?, ?, ?, ?, ?)",
                        (gid, vid, blob, now, now))
            new_n += 1
    conn.commit()
    conn.close()
    return gid, new_n, upd_n


def archive_list_groups():
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("""
            SELECT g.*, (SELECT COUNT(*) FROM search_items i
                         WHERE i.group_id = g.id) AS item_count
            FROM search_groups g ORDER BY g.updated_at DESC
        """)
        out = [dict(r) for r in cur.fetchall()]
        conn.close()
        return out
    except Exception:
        return []


def archive_set_group_favorite(group_id, favorite):
    """Star / unstar a whole section. Starred sections show in the Favorites
    tab even when none of their videos is individually starred (see
    archive_list_groups_full) — the section card's save icon flips this."""
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("UPDATE search_groups SET is_favorite = ? WHERE id = ?",
                    (1 if favorite else 0, group_id))
        ok = cur.rowcount > 0
        conn.commit()
        conn.close()
        return ok
    except Exception:
        return False


def archive_list_groups_full(favorites_only=False):
    """archive_list_groups() plus a per-group favorites count, for the QML
    Search Archive page (whose section cards show both numbers). With
    favorites_only=True the list is scoped to starred sections plus sections
    that have at least one favorited item — the Favorites tab — same rule as
    archive_list_favorite_groups(), plus the section star."""
    where = ("WHERE (COALESCE(g.is_favorite, 0) = 1 OR (SELECT COUNT(*) "
             "FROM search_items i "
             "WHERE i.group_id = g.id AND i.is_favorite = 1) > 0)"
             if favorites_only else "")
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute(f"""
            SELECT g.*,
                   (SELECT COUNT(*) FROM search_items i
                    WHERE i.group_id = g.id) AS item_count,
                   (SELECT COUNT(*) FROM search_items i
                    WHERE i.group_id = g.id AND i.is_favorite = 1) AS fav_count
            FROM search_groups g {where}
            ORDER BY g.updated_at DESC
        """)
        out = [dict(r) for r in cur.fetchall()]
        conn.close()
        return out
    except Exception:
        return []


def archive_get_rows(group_id, favorites_only=False):
    """Stored result rows for a group, newest-seen first. Pass
    favorites_only=True to get just the rows flagged is_favorite — used by
    the Favorites tab, which is a filtered view over the same rows rather
    than its own separate storage."""
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        sql = ("SELECT video_id, row, first_seen, last_seen, is_favorite "
               "FROM search_items WHERE group_id = ?")
        args = [group_id]
        if favorites_only:
            sql += " AND is_favorite = 1"
        sql += " ORDER BY id ASC"
        cur.execute(sql, args)
        rows = []
        for vid, blob, first_seen, last_seen, is_fav in cur.fetchall():
            try:
                row = json.loads(blob)
            except Exception:
                continue
            row["_archive_key"] = vid
            row["_first_seen"] = first_seen
            row["_last_seen"] = last_seen
            row["_is_favorite"] = bool(is_fav)
            rows.append(row)
        conn.close()
        return rows
    except Exception:
        return []


def archive_delete_group(group_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("DELETE FROM search_items WHERE group_id = ?", (group_id,))
        cur.execute("DELETE FROM search_groups WHERE id = ?", (group_id,))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def archive_delete_item(group_id, item_key):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("DELETE FROM search_items WHERE group_id = ? AND video_id = ?",
                    (group_id, item_key))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def archive_rename_group(group_id, title):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("UPDATE search_groups SET title = ? WHERE id = ?",
                    (title, group_id))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def archive_clear_all():
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.execute("DELETE FROM search_items")
        conn.execute("DELETE FROM search_groups")
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def archive_update_rows(group_id, rows):
    """v3.43: write refreshed live stats back onto stored rows.

    Only the row blob changes. `last_seen` is NOT touched (it means "this
    video showed up in a search"), the favorite flag lives in its own column
    and the section's updated_at / run_count stay as they are, so a stats
    refresh never reorders the section list or counts as a run. Bookkeeping
    keys that come from columns (_archive_key, _first_seen, ...) are stripped;
    _stats_at / _live_missing are kept so the next open knows how fresh the
    numbers are. Returns the number of rows written."""
    keep = ("_stats_at", "_live_missing")
    n = 0
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        for row in rows or []:
            key = (row or {}).get("_archive_key") or _archive_row_key(row or {})
            if not key:
                continue
            blob = {k: v for k, v in row.items()
                    if not str(k).startswith("_") or k in keep}
            cur.execute("UPDATE search_items SET row = ? "
                        "WHERE group_id = ? AND video_id = ?",
                        (json.dumps(blob, ensure_ascii=False), group_id, key))
            n += cur.rowcount
        conn.commit()
        conn.close()
    except Exception:
        return 0
    return n


def archive_update_rows_everywhere(rows):
    """Same as archive_update_rows, for rows whose section is unknown (a
    Niche Finder pool): a video saved under several keyword sections gets
    the fresh numbers in all of them."""
    keep = ("_stats_at", "_live_missing")
    n = 0
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        for row in rows or []:
            key = (row or {}).get("video_id")
            if not key:
                continue
            blob = {k: v for k, v in row.items()
                    if not str(k).startswith("_") or k in keep}
            cur.execute("UPDATE search_items SET row = ? WHERE video_id = ?",
                        (json.dumps(blob, ensure_ascii=False), key))
            n += cur.rowcount
        conn.commit()
        conn.close()
    except Exception:
        return 0
    return n


def archive_get_group(group_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        cur.execute("SELECT * FROM search_groups WHERE id = ?", (group_id,))
        row = cur.fetchone()
        conn.close()
        return dict(row) if row else None
    except Exception:
        return None
