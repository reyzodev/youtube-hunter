"""app.core.db._sqlite - one place every app database connection is opened.

All of the app's tables (archive, favourites, AI Ideas / Content Lab, chat,
downloads, clips, insights, quota) live in the same ideas.db, and it is written
from worker threads (a blueprint run saving, chat digests, download progress,
quota ticks) while the GUI thread reads it. In SQLite's default rollback-journal
mode a writer locks out every reader, so a long write made the UI wait on its
own database and, past the busy timeout, surfaced as "database is locked".

WAL mode lets readers carry on while one writer writes. It is a property of the
database FILE (persistent once set), so it is switched on once per path per
process; `synchronous=NORMAL` is the documented safe pairing for WAL (durable
across app crashes, only the last commit can be lost on power loss) and is
per-connection, so it is applied every time. Both are best-effort: a read-only
or network location that refuses WAL simply keeps working the old way.
"""

import sqlite3
import threading

_DEFAULT_TIMEOUT = 10.0
_wal_paths = set()
_wal_lock = threading.Lock()


def connect(path, timeout=_DEFAULT_TIMEOUT, **kwargs):
    conn = sqlite3.connect(path, timeout=timeout, **kwargs)
    key = str(path)
    if key != ":memory:" and key not in _wal_paths:
        with _wal_lock:
            if key not in _wal_paths:
                try:
                    conn.execute("PRAGMA journal_mode=WAL")
                except sqlite3.Error:
                    pass
                _wal_paths.add(key)
    try:
        conn.execute("PRAGMA synchronous=NORMAL")
    except sqlite3.Error:
        pass
    return conn
