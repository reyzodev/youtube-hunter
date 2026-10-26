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

v3.53 perf - the "keeper" connection
------------------------------------
Every helper in this package opens a connection, runs one statement and closes
it again (`conn = db_connect(...) ... conn.close()`). That is fine on a fast
local disk, but closing the LAST connection to a WAL database makes SQLite run
a checkpoint: it copies the write-ahead log back into the main .db file and
unmaps both. Measured on the real 23 MB ideas.db in %APPDATA%\\Roaming, that
close costs **70-130 ms** - and it lands on the GUI thread, once per query.

That single line was the "slight lag" the user feels everywhere: opening the
Search Archive ran reload() + refreshDownloaded() (two closes), the Content Lab
ran a dozen (one per section), every save ran one more. None of it showed up in
the QML profiler, because it is Python time between two frames.

Holding one connection open per database file for the life of the process means
the short-lived connections are never the last one out, so no checkpoint runs on
close: the same close measures **0.1 ms**. The write-ahead log still stays
bounded - `wal_autocheckpoint` (1000 pages, the SQLite default) checkpoints on
commit - and the file is released when the process exits.
"""

import sqlite3
import threading

_DEFAULT_TIMEOUT = 10.0
_wal_paths = set()
_wal_lock = threading.Lock()

# path -> the connection that keeps the database file open (see module docstring)
_keepers = {}
_keeper_lock = threading.Lock()


def _keeper_for(path):
    """Open (once) and hold a connection on `path`, so that closing the
    short-lived connections this package hands out never triggers a WAL
    checkpoint. Best-effort: on any failure the caller simply gets the old
    behaviour."""
    key = str(path)
    if key in _keepers:
        return
    with _keeper_lock:
        if key in _keepers:
            return
        # :memory: databases are private per connection - nothing to keep.
        # URIs carry their own flags, so leave them alone too.
        if key == ":memory:" or key.startswith("file:"):
            return
        try:
            conn = sqlite3.connect(key, timeout=_DEFAULT_TIMEOUT,
                                   check_same_thread=False)
            # sqlite3.connect() is lazy - the file is only opened by the first
            # statement. Run one so the handle is really held.
            conn.execute("PRAGMA schema_version").fetchone()
            conn.commit()
            _keepers[key] = conn
        except Exception:               # noqa: BLE001 - never break a caller
            pass


def connect(path, timeout=_DEFAULT_TIMEOUT, **kwargs):
    _keeper_for(path)
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
