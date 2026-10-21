"""app.core.db.chat - YouTube Hunter.

Persistence for AI Chat: conversations, their messages, and the sources
(videos / files / Drive imports) attached to each conversation.

Same SQLite file as the archive, ideas, Content Lab and Insights tables, so
there is still one data file to back up. Imported files are copied into a
`chat_files/` folder beside it, so a conversation keeps working after the
original download is moved or deleted.
"""

import json
import os
import shutil
import sqlite3

from app.core.db._sqlite import connect as db_connect
import uuid
from datetime import datetime

from app.config import CONFIG_PATH

DATA_DB_PATH = os.path.join(os.path.dirname(CONFIG_PATH), "ideas.db")
CHAT_FILES_DIR = os.path.join(os.path.dirname(CONFIG_PATH), "chat_files")


def _now():
    return datetime.now().isoformat(timespec="seconds")


def _conn():
    # timeout: the chat writes from worker threads (digests) while the GUI
    # thread reads; without a busy timeout SQLite answers "database is locked".
    conn = db_connect(DATA_DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def init_chat_db():
    conn = db_connect(DATA_DB_PATH, timeout=10)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS chat_threads (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            title       TEXT,
            pinned      INTEGER DEFAULT 0,
            created_at  TEXT,
            updated_at  TEXT
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS chat_messages (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            thread_id    INTEGER,
            role         TEXT,
            text         TEXT,
            attachments  TEXT,
            error        TEXT,
            model        TEXT,
            created_at   TEXT
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS chat_sources (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            thread_id   INTEGER,
            skey        TEXT,
            payload     TEXT,
            digest      TEXT,
            created_at  TEXT,
            UNIQUE(thread_id, skey)
        )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_chat_msg_thread "
                "ON chat_messages(thread_id, id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_chat_threads_updated "
                "ON chat_threads(updated_at DESC)")
    conn.commit()
    conn.close()
    try:
        os.makedirs(CHAT_FILES_DIR, exist_ok=True)
    except Exception:
        pass


# ── threads ──────────────────────────────────────────────────────────────
def chat_create_thread(title):
    now = _now()
    conn = _conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO chat_threads (title, pinned, created_at, updated_at) "
                "VALUES (?, 0, ?, ?)", (title, now, now))
    tid = cur.lastrowid
    conn.commit()
    conn.close()
    return tid


def chat_list_threads(search=""):
    try:
        conn = _conn()
        cur = conn.cursor()
        sql = ("SELECT t.*, (SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id) AS msg_count, "
               "(SELECT COUNT(*) FROM chat_sources s WHERE s.thread_id = t.id) AS src_count "
               "FROM chat_threads t")
        args = []
        if search.strip():
            sql += (" WHERE t.title LIKE ? OR t.id IN (SELECT thread_id FROM chat_messages "
                    "WHERE text LIKE ?)")
            like = "%" + search.strip() + "%"
            args = [like, like]
        sql += " ORDER BY t.pinned DESC, t.updated_at DESC LIMIT 300"
        cur.execute(sql, args)
        out = [dict(r) for r in cur.fetchall()]
        conn.close()
        return out
    except Exception:
        return []


def chat_get_thread(tid):
    try:
        conn = _conn()
        cur = conn.cursor()
        cur.execute("SELECT * FROM chat_threads WHERE id = ?", (tid,))
        r = cur.fetchone()
        conn.close()
        return dict(r) if r else None
    except Exception:
        return None


def chat_rename_thread(tid, title):
    _exec("UPDATE chat_threads SET title = ? WHERE id = ?", (title, tid))


def chat_pin_thread(tid, pinned):
    _exec("UPDATE chat_threads SET pinned = ? WHERE id = ?", (1 if pinned else 0, tid))


def chat_touch_thread(tid):
    _exec("UPDATE chat_threads SET updated_at = ? WHERE id = ?", (_now(), tid))


def _thread_file_paths(tid):
    """Every local file a thread's sources and message attachments point at."""
    paths = set()
    for s in chat_sources(tid):
        if s.get("path"):
            paths.add(os.path.normcase(os.path.abspath(s["path"])))
    for m in chat_messages(tid):
        for a in m.get("attachments") or []:
            if isinstance(a, dict) and a.get("path"):
                paths.add(os.path.normcase(os.path.abspath(a["path"])))
    return paths


def _remove_owned_files(paths):
    """Delete files that live in chat_files/ — never a user's original file
    that was merely referenced from elsewhere on disk."""
    root = os.path.normcase(os.path.abspath(CHAT_FILES_DIR)) + os.sep
    for p in paths:
        if p.startswith(root):
            try:
                os.remove(p)
            except OSError:
                pass


def chat_delete_thread(tid):
    # Imported copies are owned by the conversation: drop the ones no OTHER
    # thread still references, so chat_files/ doesn't grow forever.
    mine = _thread_file_paths(tid)
    _exec("DELETE FROM chat_messages WHERE thread_id = ?", (tid,))
    _exec("DELETE FROM chat_sources WHERE thread_id = ?", (tid,))
    _exec("DELETE FROM chat_threads WHERE id = ?", (tid,))
    if mine:
        still_used = set()
        for t in chat_list_threads():
            still_used |= _thread_file_paths(t["id"])
        _remove_owned_files(mine - still_used)


def chat_delete_all():
    _exec("DELETE FROM chat_messages", ())
    _exec("DELETE FROM chat_sources", ())
    _exec("DELETE FROM chat_threads", ())
    try:
        for name in os.listdir(CHAT_FILES_DIR):
            p = os.path.join(CHAT_FILES_DIR, name)
            if os.path.isfile(p):
                os.remove(p)
    except OSError:
        pass


def chat_delete_messages_from(tid, mid):
    """Drop message `mid` and everything after it (regenerate / retry)."""
    _exec("DELETE FROM chat_messages WHERE thread_id = ? AND id >= ?", (tid, mid))


# ── messages ─────────────────────────────────────────────────────────────
def chat_add_message(tid, role, text, attachments=None, error="", model=""):
    conn = _conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO chat_messages (thread_id, role, text, attachments, error, model, created_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (tid, role, text or "", json.dumps(attachments or [], ensure_ascii=False),
                 error or "", model or "", _now()))
    mid = cur.lastrowid
    cur.execute("UPDATE chat_threads SET updated_at = ? WHERE id = ?", (_now(), tid))
    conn.commit()
    conn.close()
    return mid


def chat_update_message(mid, text=None, error=None):
    sets, args = [], []
    if text is not None:
        sets.append("text = ?")
        args.append(text)
    if error is not None:
        sets.append("error = ?")
        args.append(error)
    if not sets:
        return
    args.append(mid)
    _exec("UPDATE chat_messages SET " + ", ".join(sets) + " WHERE id = ?", tuple(args))


def chat_delete_message(mid):
    _exec("DELETE FROM chat_messages WHERE id = ?", (mid,))


def chat_messages(tid):
    try:
        conn = _conn()
        cur = conn.cursor()
        cur.execute("SELECT * FROM chat_messages WHERE thread_id = ? ORDER BY id ASC", (tid,))
        out = []
        for r in cur.fetchall():
            d = dict(r)
            try:
                d["attachments"] = json.loads(d.get("attachments") or "[]")
            except Exception:
                d["attachments"] = []
            out.append(d)
        conn.close()
        return out
    except Exception:
        return []


def chat_thread_signature(tid):
    """A cheap fingerprint of everything a chat shows (v3.40.7). The hover
    prefetch keeps a pre-built copy of a chat; opening it compares this tuple
    first so a stale copy (new answer, edited turn, digest finished...) is never
    shown. One connection, two aggregate scans of the thread's own rows."""
    try:
        conn = _conn()
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*), COALESCE(MAX(id), 0), "
                    "COALESCE(SUM(LENGTH(text)), 0), COALESCE(SUM(LENGTH(error)), 0), "
                    "COALESCE(SUM(LENGTH(attachments)), 0) "
                    "FROM chat_messages WHERE thread_id = ?", (tid,))
        m = tuple(cur.fetchone())
        cur.execute("SELECT COUNT(*), COALESCE(MAX(id), 0), "
                    "COALESCE(SUM(LENGTH(digest)), 0), COALESCE(SUM(LENGTH(payload)), 0) "
                    "FROM chat_sources WHERE thread_id = ?", (tid,))
        sr = tuple(cur.fetchone())
        conn.close()
        return m + sr
    except Exception:
        return None


# ── sources ──────────────────────────────────────────────────────────────
def chat_add_source(tid, source, digest=""):
    try:
        conn = _conn()
        cur = conn.cursor()
        cur.execute("INSERT INTO chat_sources (thread_id, skey, payload, digest, created_at) "
                    "VALUES (?, ?, ?, ?, ?) ON CONFLICT(thread_id, skey) DO UPDATE SET "
                    # The digest is replaced too: re-adding a source whose payload
                    # changed (a fresher Niche row, a re-imported file) used to
                    # keep the OLD digest, so the model kept reading stale numbers.
                    "payload = excluded.payload, digest = excluded.digest",
                    (tid, source["key"], json.dumps(source, ensure_ascii=False),
                     digest or "", _now()))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False


def chat_set_source_digest(tid, skey, digest):
    _exec("UPDATE chat_sources SET digest = ? WHERE thread_id = ? AND skey = ?",
          (digest, tid, skey))


def chat_remove_source(tid, skey):
    _exec("DELETE FROM chat_sources WHERE thread_id = ? AND skey = ?", (tid, skey))


def chat_sources(tid):
    try:
        conn = _conn()
        cur = conn.cursor()
        cur.execute("SELECT skey, payload, digest FROM chat_sources WHERE thread_id = ? "
                    "ORDER BY id ASC", (tid,))
        out = []
        for skey, payload, digest in cur.fetchall():
            try:
                s = json.loads(payload)
            except Exception:
                continue
            s["key"] = skey
            s["_digest"] = digest or ""
            out.append(s)
        conn.close()
        return out
    except Exception:
        return []


# ── files ────────────────────────────────────────────────────────────────
def chat_store_file(src_path, display_name=None):
    """Copy a file into chat_files/ under a unique name and return the new
    path. Falls back to the original path if the copy fails."""
    try:
        os.makedirs(CHAT_FILES_DIR, exist_ok=True)
        name = display_name or os.path.basename(src_path)
        stem, ext = os.path.splitext(name)
        safe = "".join(ch for ch in stem if ch.isalnum() or ch in " -_()") .strip() or "file"
        dest = os.path.join(CHAT_FILES_DIR, f"{safe[:60]}-{uuid.uuid4().hex[:8]}{ext.lower()}")
        shutil.copy2(src_path, dest)
        return dest
    except Exception:
        return src_path


def chat_files_path(name):
    os.makedirs(CHAT_FILES_DIR, exist_ok=True)
    return os.path.join(CHAT_FILES_DIR, name)


def _exec(sql, args):
    try:
        conn = db_connect(DATA_DB_PATH, timeout=10)
        conn.execute(sql, args)
        conn.commit()
        conn.close()
    except Exception:
        pass
