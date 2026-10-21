"""app.core.db.ideas - Youtube Scrapper."""

import os
import sqlite3

from app.core.db._sqlite import connect as db_connect
from datetime import datetime

from app.config import CONFIG_PATH

# ═════════════════════════════════════════════════════════════════════════
#  IDEAS / OUTLIER DATA HELPERS
# ═════════════════════════════════════════════════════════════════════════
IDEA_STAGES = [
    ("new", "New"),
    ("researching", "Researching"),
    ("scripting", "Scripting"),
    ("ready", "Ready to Film"),
]


def _get_data_db_path():
    cfg_dir = os.path.dirname(CONFIG_PATH)
    return os.path.join(cfg_dir, "ideas.db")


DATA_DB_PATH = _get_data_db_path()


def init_ideas_db():
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS ideas (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            video_id        TEXT,
            title           TEXT,
            channel_title   TEXT,
            video_url       TEXT,
            thumbnail_url   TEXT,
            view_count      INTEGER DEFAULT 0,
            outlier_ratio   REAL DEFAULT 0,
            velocity        REAL DEFAULT 0,
            is_short        INTEGER DEFAULT 0,
            published_at    TEXT,
            stage           TEXT DEFAULT 'new',
            notes           TEXT DEFAULT '',
            ai_analysis     TEXT DEFAULT '',
            created_at      TEXT
        )
    """)
    conn.commit()
    conn.close()


def db_add_idea(video):
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT id FROM ideas WHERE video_id = ?", (video["video_id"],))
    if cur.fetchone():
        conn.close()
        return False
    cur.execute("""
        INSERT INTO ideas (video_id, title, channel_title, video_url, thumbnail_url,
                            view_count, outlier_ratio, velocity, is_short, published_at,
                            stage, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?)
    """, (
        video["video_id"], video["title"], video["channel_title"], video["video_url"],
        video.get("thumbnail_url", ""), video.get("view_count", 0),
        video.get("outlier_ratio", 0), video.get("velocity", 0),
        1 if video.get("is_short") else 0, video.get("published_at", ""),
        datetime.now().isoformat(timespec="seconds"),
    ))
    conn.commit()
    conn.close()
    return True


def db_list_ideas():
    conn = db_connect(DATA_DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute("SELECT * FROM ideas ORDER BY created_at DESC")
    rows = [dict(r) for r in cur.fetchall()]
    conn.close()
    return rows


def db_update_idea_stage(idea_id, stage):
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("UPDATE ideas SET stage = ? WHERE id = ?", (stage, idea_id))
    conn.commit()
    conn.close()


def db_update_idea_analysis(idea_id, analysis_text):
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("UPDATE ideas SET ai_analysis = ? WHERE id = ?", (analysis_text, idea_id))
    conn.commit()
    conn.close()


def db_delete_idea(idea_id):
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("DELETE FROM ideas WHERE id = ?", (idea_id,))
    conn.commit()
    conn.close()
