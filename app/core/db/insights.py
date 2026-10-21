"""app.core.db.insights - YouTube Hunter.

Persistence for Niche Scan: one row per analysed snapshot, keyed by the
snapshot's own identity (the sha1 over its ordered video ids, see
app.core.analysis.snapshot.snapshot_key).

Why keyed that way rather than by query string: a brief is only true of the exact
set of videos it was generated from. Re-running the same keyword tomorrow returns
a different set and deserves a different report; re-opening today's saved archive
group must find the report that already exists rather than paying for the model
again. The key changes the moment the set or its order does, which is exactly the
cache-invalidation rule the app wants.

Lives in the same SQLite file as the search archive and Content Lab tables, so
there is still one data file to back up.
"""

import json
import os
import sqlite3
from datetime import datetime

from app.config import CONFIG_PATH
from app.core.db._sqlite import connect as db_connect

def _get_data_db_path():
    """Same file the search archive and Content Lab tables live in — one data
    file to back up, and one connection pattern across every db module."""
    return os.path.join(os.path.dirname(CONFIG_PATH), "ideas.db")

DATA_DB_PATH = _get_data_db_path()

def init_insights_db():
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS insight_reports (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_key  TEXT UNIQUE,
            query         TEXT,
            mode          TEXT,
            provider      TEXT,
            analytics_json TEXT,
            ai_json       TEXT,
            rows_json     TEXT,
            created_at    TEXT
        )
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_insights_created "
                "ON insight_reports(created_at DESC)")
    conn.commit()
    conn.close()

def insights_save(snapshot_key, query, mode, provider, analytics, ai, rows):
    """Upsert one report.

    `rows` is stored alongside so a saved report can be re-opened, re-read and
    handed on to AI Ideas without re-running the search — the same reason the
    search archive keeps its rows rather than just its query."""
    now = datetime.now().isoformat(timespec="seconds")
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO insight_reports (snapshot_key, query, mode, provider, "
            "analytics_json, ai_json, rows_json, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(snapshot_key) DO UPDATE SET "
            "query=excluded.query, mode=excluded.mode, provider=excluded.provider, "
            "analytics_json=excluded.analytics_json, ai_json=excluded.ai_json, "
            "rows_json=excluded.rows_json, created_at=excluded.created_at",
            (snapshot_key, query, mode, provider,
             json.dumps(analytics or {}, ensure_ascii=False),
             json.dumps(ai or {}, ensure_ascii=False),
             json.dumps(rows or [], ensure_ascii=False), now))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False

def insights_get(snapshot_key):
    """The stored report for a snapshot, or None. Never raises — a corrupt row
    reads as "no cached report", which just costs one AI call."""
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT query, mode, provider, analytics_json, ai_json, "
                    "rows_json, created_at FROM insight_reports "
                    "WHERE snapshot_key = ?", (snapshot_key,))
        row = cur.fetchone()
        conn.close()
        if not row:
            return None
        return {
            "snapshot_key": snapshot_key,
            "query": row[0] or "",
            "mode": row[1] or "keyword",
            "provider": row[2] or "",
            "analytics": json.loads(row[3]) if row[3] else {},
            "ai": json.loads(row[4]) if row[4] else {},
            "rows": json.loads(row[5]) if row[5] else [],
            "created_at": row[6] or "",
        }
    except Exception:
        return None

def insights_list(limit=30):
    """Recent snapshots, newest first — the "previously analysed" strip, and the
    report builder's "combine with research" picker.

    A row exists as soon as a result set is READ (the deterministic snapshot is
    saved immediately, brief or no brief), so `has_brief` says which half a row
    actually carries: True when a model has written the research brief over it,
    False when it is aggregates only. Both are usable — the measured half needs
    no AI call and is what the channel report quotes as fact — so the flag is for
    labelling, never for filtering.
    """
    # v3.49: the list only needs two facts out of each row's JSON (a count and
    # "is there a brief"), so SQLite reads them in place with json_extract
    # instead of handing Python every stored analytics + brief blob to parse.
    # The briefs picker in AI Chat and Content Lab open noticeably faster on
    # a long history. Older SQLite builds without JSON1 use the slow path.
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        try:
            cur.execute(
                "SELECT snapshot_key, query, mode, created_at, "
                "COALESCE(json_extract(analytics_json, '$.total_videos'), 0), "
                "CASE WHEN ai_json IS NULL OR TRIM(ai_json) IN ('', '{}', 'null') "
                "THEN 0 ELSE 1 END "
                "FROM insight_reports ORDER BY created_at DESC LIMIT ?",
                (int(limit),))
            out = [{
                "snapshot_key": key,
                "query": query or "",
                "mode": mode or "keyword",
                "created_at": created_at or "",
                "total_videos": int(total or 0),
                "has_brief": bool(has),
            } for key, query, mode, created_at, total, has in cur.fetchall()]
            conn.close()
            return out
        except sqlite3.OperationalError:
            pass                    # no JSON1 — fall through to Python parsing
        cur.execute("SELECT snapshot_key, query, mode, created_at, analytics_json, "
                    "ai_json FROM insight_reports ORDER BY created_at DESC LIMIT ?",
                    (int(limit),))
        out = []
        for key, query, mode, created_at, analytics, ai in cur.fetchall():
            try:
                stats = json.loads(analytics) if analytics else {}
            except Exception:
                stats = {}
            try:
                brief = json.loads(ai) if ai else None
            except Exception:
                brief = None
            out.append({
                "snapshot_key": key,
                "query": query or "",
                "mode": mode or "keyword",
                "created_at": created_at or "",
                "total_videos": stats.get("total_videos", 0),
                "has_brief": bool(brief),
            })
        conn.close()
        return out
    except Exception:
        return []

def insights_delete(snapshot_key):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("DELETE FROM insight_reports WHERE snapshot_key = ?",
                    (snapshot_key,))
        conn.commit()
        conn.close()
        return True
    except Exception:
        return False
