"""app.core.db.content_lab - Youtube Scrapper."""

import json
import sqlite3

from app.core.db._sqlite import connect as db_connect
from datetime import datetime

from app.core.db.ideas import DATA_DB_PATH
from app.core.niche.helpers import SHORT_MAX_SECONDS
from app.i18n import tr

# ═════════════════════════════════════════════════════════════════════════
#  CONTENT LAB — persisted AI-built idea "blueprints", grouped by whichever
#  keyword/channel section (search_groups row) they were generated from.
#  Each entry maps 1:1 to a search_groups row; every "Create with AI" run
#  APPENDS a fresh batch of ideas onto that entry instead of replacing what's
#  already there, so a keyword's Content Lab section only ever grows across
#  repeat visits — this mirrors how archive_save_search() merges rather than
#  overwrites (see above).
# ═════════════════════════════════════════════════════════════════════════
def init_content_lab_db():
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("""CREATE TABLE IF NOT EXISTS content_lab_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id INTEGER UNIQUE,
            title TEXT,
            created_at TEXT,
            updated_at TEXT,
            videos_json TEXT
        )""")
        cur.execute("""CREATE TABLE IF NOT EXISTS content_lab_ideas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER,
            idea_json TEXT,
            is_favorite INTEGER DEFAULT 0,
            created_at TEXT,
            sort_order INTEGER DEFAULT 0
        )""")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_cl_ideas_entry "
                    "ON content_lab_ideas(entry_id, sort_order, id)")
        conn.commit()
        conn.close()
    except Exception:
        pass


def _content_lab_video_key(v):
    return v.get("video_id") or v.get("video_url") or v.get("title") or ""


# Batch format classifier — decides whether a freshly-selected set of
# reference videos should be scripted as short-form or long-form content.
#
# One boundary now governs everything: a video UNDER 3 minutes is a Short, at or
# over is Long-form (see app.core.niche.helpers.detect_short / SHORT_MAX_SECONDS).
# The old three-rule hard/soft/grey-zone logic existed only because 60-180s was
# ambiguous under the previous 60s cap; it no longer is.
#
# Rules (in order):
#   1. No usable durations -> "short" (safer/more common default for clips).
#   2. Long videos (>= 3 min) are the majority of the batch, OR make up a third
#      or more of it -> "long". A handful of long videos signals the creator is
#      batching long-form sessions even with a stray short clip mixed in
#      (matches "several long + one 60s clip = long").
#   3. Otherwise -> "short".
CONTENT_LAB_LONG_MIN = SHORT_MAX_SECONDS   # seconds; at/over this a video counts as long-form


def content_lab_classify_format(videos):
    """videos: list of video dicts (uses 'duration_s'). Returns 'short' or
    'long'. Falls back to 'short' when no usable duration data exists,
    since that's the safer/more common default for reference clips."""
    durations = [int(v.get("duration_s") or 0) for v in (videos or [])]
    durations = [d for d in durations if d > 0]
    if not durations:
        return "short"

    n = len(durations)
    n_long = sum(1 for d in durations if d >= CONTENT_LAB_LONG_MIN)
    n_short = n - n_long

    if n_long > n_short or (n_long / n) >= 0.34:
        return "long"
    return "short"


def content_lab_get_or_create_entry(group_id, title):
    """The entry id for this keyword/channel group, creating a new (empty)
    entry the first time that group is ever sent to Content Lab. Re-running
    Create later for the same group reuses the same entry (and refreshes its
    display title, in case the keyword section was renamed since)."""
    now = datetime.now().isoformat(timespec="seconds")
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT id FROM content_lab_entries WHERE group_id = ?", (group_id,))
        row = cur.fetchone()
        if row:
            entry_id = row[0]
            cur.execute("UPDATE content_lab_entries SET title = ? WHERE id = ?",
                        (title, entry_id))
        else:
            cur.execute(
                "INSERT INTO content_lab_entries (group_id, title, created_at, updated_at, videos_json) "
                "VALUES (?, ?, ?, ?, ?)",
                (group_id, title, now, now, "[]"))
            entry_id = cur.lastrowid
        conn.commit()
        conn.close()
        return entry_id
    except Exception:
        return None


def content_lab_merge_entry_videos(entry_id, videos):
    """Folds newly-selected reference videos into the entry's running pool,
    deduped by video key. A per-idea Regenerate reuses this whole pool as
    its reference set, not just whichever batch happened to be picked most
    recently."""
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT videos_json FROM content_lab_entries WHERE id = ?", (entry_id,))
        row = cur.fetchone()
        existing = json.loads(row[0]) if row and row[0] else []
        by_key = {_content_lab_video_key(v): v for v in existing}
        for v in videos:
            by_key[_content_lab_video_key(v)] = v
        merged = list(by_key.values())
        now = datetime.now().isoformat(timespec="seconds")
        cur.execute("UPDATE content_lab_entries SET videos_json = ?, updated_at = ? WHERE id = ?",
                    (json.dumps(merged), now, entry_id))
        conn.commit()
        conn.close()
        return merged
    except Exception:
        return videos


def content_lab_get_entry_videos(entry_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT videos_json FROM content_lab_entries WHERE id = ?", (entry_id,))
        row = cur.fetchone()
        conn.close()
        return json.loads(row[0]) if row and row[0] else []
    except Exception:
        return []


def content_lab_list_entries(search=""):
    """Every Content Lab entry, most-recently-active first, with its idea
    count baked in so the landing list never needs a second query per card."""
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("""SELECT e.id, e.title, e.created_at, e.updated_at,
                              (SELECT COUNT(*) FROM content_lab_ideas WHERE entry_id = e.id) AS n
                       FROM content_lab_entries e ORDER BY e.updated_at DESC""")
        out = []
        needle = (search or "").strip().lower()
        for eid, title, created_at, updated_at, n in cur.fetchall():
            if needle and needle not in (title or "").lower():
                continue
            out.append({"id": eid, "title": title or tr("Untitled"),
                        "created_at": created_at, "updated_at": updated_at,
                        "idea_count": n})
        conn.close()
        return out
    except Exception:
        return []


def content_lab_get_entry(entry_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT id, title, created_at, updated_at FROM content_lab_entries WHERE id = ?",
                    (entry_id,))
        row = cur.fetchone()
        conn.close()
        if not row:
            return None
        return {"id": row[0], "title": row[1], "created_at": row[2], "updated_at": row[3]}
    except Exception:
        return None


def content_lab_add_ideas(entry_id, ideas):
    """Appends a fresh batch onto the entry's idea list — never replaces the
    ones already there — and returns the new rows, each carrying its own db
    id (so the UI can address them individually right away)."""
    now = datetime.now().isoformat(timespec="seconds")
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT COALESCE(MAX(sort_order), -1) FROM content_lab_ideas WHERE entry_id = ?",
                    (entry_id,))
        next_order = (cur.fetchone()[0] or -1) + 1
        new_rows = []
        for i, idea in enumerate(ideas):
            cur.execute(
                "INSERT INTO content_lab_ideas (entry_id, idea_json, is_favorite, created_at, sort_order) "
                "VALUES (?, ?, 0, ?, ?)",
                (entry_id, json.dumps(idea), now, next_order + i))
            new_row = dict(idea)
            new_row["id"] = cur.lastrowid
            new_row["is_favorite"] = False
            new_row["created_at"] = now
            new_rows.append(new_row)
        cur.execute("UPDATE content_lab_entries SET updated_at = ? WHERE id = ?", (now, entry_id))
        conn.commit()
        conn.close()
        return new_rows
    except Exception:
        return []


def content_lab_get_ideas(entry_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT id, idea_json, is_favorite, created_at FROM content_lab_ideas "
                    "WHERE entry_id = ? ORDER BY sort_order ASC, id ASC", (entry_id,))
        out = []
        for iid, blob, is_fav, created_at in cur.fetchall():
            try:
                idea = json.loads(blob)
            except Exception:
                continue
            idea["id"] = iid
            idea["is_favorite"] = bool(is_fav)
            idea["created_at"] = created_at
            out.append(idea)
        conn.close()
        return out
    except Exception:
        return []


def content_lab_all_ideas(search=""):
    """Every stored blueprint across ALL sections, newest-touched section first,
    each tagged with the title of the section it belongs to. Read-only; used by
    the Content Lab CSV-analysis tab's "combine with my blueprints" picker so a
    creator can fold any saved idea into a channel report regardless of which
    keyword/channel it was generated from.

    An optional `search` filters by blueprint title (case-insensitive).
    """
    needle = (search or "").strip().lower()
    out = []
    try:
        for entry in content_lab_list_entries():
            section_title = entry.get("title") or tr("Untitled")
            for idea in content_lab_get_ideas(entry["id"]):
                title = idea.get("title") or tr("Untitled idea")
                if needle and needle not in title.lower():
                    continue
                idea["_section_id"] = entry["id"]
                idea["_section_title"] = section_title
                out.append(idea)
    except Exception:
        return out
    return out


def content_lab_ideas_by_ids(idea_ids):
    """Fetch full stored blueprint dicts for a set of idea ids, preserving the
    given order. Used when the CSV-analysis tab sends its ticked blueprint ids
    to the combined-report generator."""
    wanted = [int(i) for i in (idea_ids or [])]
    if not wanted:
        return []
    by_id = {}
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        qmarks = ",".join("?" for _ in wanted)
        cur.execute(
            f"SELECT id, idea_json, is_favorite, created_at FROM content_lab_ideas "
            f"WHERE id IN ({qmarks})", wanted)
        for iid, blob, is_fav, created_at in cur.fetchall():
            try:
                idea = json.loads(blob)
            except Exception:
                continue
            idea["id"] = iid
            idea["is_favorite"] = bool(is_fav)
            idea["created_at"] = created_at
            by_id[iid] = idea
        conn.close()
    except Exception:
        return [by_id[i] for i in wanted if i in by_id]
    return [by_id[i] for i in wanted if i in by_id]


def content_lab_update_idea(idea_id, idea):
    now = datetime.now().isoformat(timespec="seconds")
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("UPDATE content_lab_ideas SET idea_json = ?, created_at = ? WHERE id = ?",
                    (json.dumps(idea), now, idea_id))
        cur.execute("SELECT entry_id FROM content_lab_ideas WHERE id = ?", (idea_id,))
        row = cur.fetchone()
        if row:
            cur.execute("UPDATE content_lab_entries SET updated_at = ? WHERE id = ?", (now, row[0]))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def content_lab_toggle_favorite(idea_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT is_favorite FROM content_lab_ideas WHERE id = ?", (idea_id,))
        row = cur.fetchone()
        if not row:          # stale id: don't report a favourite that wasn't saved
            conn.close()
            return False
        new_val = 0 if row[0] else 1
        cur.execute("UPDATE content_lab_ideas SET is_favorite = ? WHERE id = ?", (new_val, idea_id))
        conn.commit()
        conn.close()
        return bool(new_val)
    except Exception:
        return False


def content_lab_delete_idea(idea_id):
    """Delete ONE blueprint for good, leaving its entry (and every other
    blueprint in it) alone.

    Distinct from content_lab_delete_entry below, which drops a whole section.
    The entry's updated_at is bumped so the library list still orders by "last
    touched" correctly after a delete.
    """
    now = datetime.now().isoformat(timespec="seconds")
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT entry_id FROM content_lab_ideas WHERE id = ?", (idea_id,))
        row = cur.fetchone()
        cur.execute("DELETE FROM content_lab_ideas WHERE id = ?", (idea_id,))
        deleted = cur.rowcount > 0
        if row:
            cur.execute("UPDATE content_lab_entries SET updated_at = ? WHERE id = ?",
                        (now, row[0]))
        conn.commit()
        conn.close()
        return deleted
    except Exception:
        return False


def content_lab_delete_entry(entry_id):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("DELETE FROM content_lab_ideas WHERE entry_id = ?", (entry_id,))
        cur.execute("DELETE FROM content_lab_entries WHERE id = ?", (entry_id,))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False
