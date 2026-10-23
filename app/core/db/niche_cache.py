"""app.core.db.niche_cache - Youtube Scrapper."""

import hashlib
import json
import sqlite3

from app.core.db._sqlite import connect as db_connect
from datetime import datetime, timezone

from app.core.db.ideas import DATA_DB_PATH
from app.core.niche.helpers import iso_age_hours

def niche_cache_key(params):
    blob = json.dumps(params, sort_keys=True, ensure_ascii=False)
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()


def niche_cache_get(key, max_age_hours=12):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT rows, fetched_at FROM niche_cache WHERE key = ?", (key,))
        row = cur.fetchone()
        conn.close()
        if not row:
            return None, None
        rows = json.loads(row[0])
        fetched = row[1]
        age = iso_age_hours(fetched)
        if age is not None and max_age_hours and age > max_age_hours:
            return None, None
        return rows, fetched
    except Exception:
        return None, None


def niche_cache_fetched_at(key, max_age_hours=12):
    """Just the timestamp of a fresh cache entry ("" if none) — without
    loading the rows, so a UI label can ask on every change for free."""
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT fetched_at FROM niche_cache WHERE key = ?", (key,))
        row = cur.fetchone()
        conn.close()
        if not row or not row[0]:
            return ""
        age = iso_age_hours(row[0])
        if age is not None and max_age_hours and age > max_age_hours:
            return ""
        return row[0]
    except Exception:
        return ""


def niche_cache_put(key, params, rows):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute(
            "INSERT OR REPLACE INTO niche_cache (key, params, rows, fetched_at) "
            "VALUES (?, ?, ?, ?)",
            (key, json.dumps(params, ensure_ascii=False),
             json.dumps(rows, ensure_ascii=False),
             datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")))
        # keep the cache from growing forever
        cur.execute("DELETE FROM niche_cache WHERE key NOT IN "
                    "(SELECT key FROM niche_cache ORDER BY fetched_at DESC LIMIT 40)")
        conn.commit()
        conn.close()
    except Exception:
        pass


def niche_cache_clear():
    try:
        conn = db_connect(DATA_DB_PATH)
        conn.execute("DELETE FROM niche_cache")
        conn.commit()
        conn.close()
    except Exception:
        pass
