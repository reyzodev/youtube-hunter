"""app.core.quota - Youtube Scrapper."""

import hashlib
import re
import sqlite3
import threading
import urllib.parse
from datetime import datetime, timedelta, timezone

from app import i18n
from app.core.db._sqlite import connect as db_connect
from app.core.db.ideas import DATA_DB_PATH

# ═════════════════════════════════════════════════════════════════════════
#  SEARCH-QUOTA LEDGER  +  RESULT CACHE  (SQLite, next to config.json)
# ═════════════════════════════════════════════════════════════════════════
SEARCH_QUOTA_DAILY_LIMIT = 100   # Google's default search.list bucket

# Every bump below is a read-modify-write on SQLite. Channel scans run several
# worker threads at once (ThreadPoolExecutor), so without a lock two threads
# could read the same "used" value and one of the two spends simply vanished.
_LEDGER_LOCK = threading.RLock()

# Callbacks fired after ANY spend is recorded (from whatever thread made the
# call). The sidebar quota card subscribes here — before this existed, it only
# read the ledger once at startup and after a Settings save, so the number at
# the bottom of the rail never went down while the app was actually spending.
_QUOTA_LISTENERS = []


def add_quota_listener(callback):
    """Register `callback()` to run after every recorded quota spend.

    Called on the thread that made the API call — a Qt receiver must marshal
    to the GUI thread itself (a queued Signal does exactly that)."""
    if callable(callback) and callback not in _QUOTA_LISTENERS:
        _QUOTA_LISTENERS.append(callback)


def _notify_quota_listeners():
    for cb in list(_QUOTA_LISTENERS):
        try:
            cb()
        except Exception:
            pass


def init_niche_db():
    conn = db_connect(DATA_DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS niche_cache (
            key         TEXT PRIMARY KEY,
            params      TEXT,
            rows        TEXT,
            fetched_at  TEXT
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS niche_meta (
            key    TEXT PRIMARY KEY,
            value  TEXT
        )
    """)
    conn.commit()
    conn.close()


def _meta_get(key, default=None):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT value FROM niche_meta WHERE key = ?", (key,))
        row = cur.fetchone()
        conn.close()
        return row[0] if row else default
    except Exception:
        return default


def _meta_set(key, value):
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("INSERT OR REPLACE INTO niche_meta (key, value) VALUES (?, ?)",
                    (key, str(value)))
        conn.commit()
        conn.close()
    except Exception:
        pass


def _meta_get_many(keys):
    """{key: value} for every key in `keys` that exists, in ONE connection.

    Perf: the Usage page used to resolve every day / kind cell through
    _meta_get, i.e. one sqlite3.connect + SELECT per cell — roughly 350
    round-trips on the GUI thread per refresh (7 + 30 + 30 days x 5 rows,
    plus per-key rows), which is what made opening Usage & Quota stutter.
    Same rows, same values, a handful of queries instead.
    """
    keys = [k for k in dict.fromkeys(keys) if k]
    out = {}
    if not keys:
        return out
    try:
        conn = db_connect(DATA_DB_PATH)
        try:
            cur = conn.cursor()
            # stay well under SQLITE_MAX_VARIABLE_NUMBER (999 on old builds)
            for i in range(0, len(keys), 500):
                chunk = keys[i:i + 500]
                cur.execute(
                    "SELECT key, value FROM niche_meta WHERE key IN (%s)"
                    % ",".join("?" * len(chunk)), chunk)
                for k, v in cur.fetchall():
                    out[k] = v
        finally:
            conn.close()
    except Exception:
        return {}
    return out


def _as_int(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _pacific_utc_offset_hours(naive_utc_dt):
    """-7 (PDT) or -8 (PST) for a given naive-UTC datetime, using the US DST
    rule in effect since 2007 (2nd Sunday of March 2 AM → 1st Sunday of
    November 2 AM, local). Computed by hand rather than via zoneinfo so this
    doesn't depend on an IANA timezone database being present — Windows
    doesn't ship one, and nothing else in this app needed zoneinfo/tzdata
    bundled into the build until now."""
    year = naive_utc_dt.year

    d = datetime(year, 3, 1)
    dst_start = datetime(year, 3, 1 + ((6 - d.weekday()) % 7) + 7, 10, 0)  # 2 AM PST = 10:00 UTC
    d = datetime(year, 11, 1)
    dst_end = datetime(year, 11, 1 + ((6 - d.weekday()) % 7), 9, 0)       # 2 AM PDT = 09:00 UTC

    return -7 if dst_start <= naive_utc_dt < dst_end else -8


def _pacific_now():
    now_utc = datetime.now(timezone.utc)
    offset_h = _pacific_utc_offset_hours(now_utc.replace(tzinfo=None))
    return now_utc.astimezone(timezone(timedelta(hours=offset_h)))


def _pt_date_str():
    """Google resets quota at midnight Pacific — this is that day's date,
    now DST-aware (was previously a fixed UTC-8 approximation, which was an
    hour off for the ~7 months of the year Pacific is on daylight time)."""
    return _pacific_now().strftime("%Y-%m-%d")


def _next_pacific_midnight_utc():
    pt_now = _pacific_now()
    next_midnight_pt = (pt_now.replace(hour=0, minute=0, second=0, microsecond=0)
                        + timedelta(days=1))
    return next_midnight_pt.astimezone(timezone.utc)


def quota_reset_local_str():
    """When today's quota resets, worded in the user's own system clock —
    not everyone knows what time 'midnight Pacific' is where they live.
    `.astimezone()` with no argument converts to the OS's local timezone
    directly, no timezone database needed for that half of the trip."""
    local_dt = _next_pacific_midnight_utc().astimezone()
    if i18n.LANG == "fa":
        return local_dt.strftime("%H:%M")
    return local_dt.strftime("%I:%M %p").lstrip("0")


def search_quota_used():
    """How many search.list calls we've spent today (local best-effort count —
    other apps sharing the same key are invisible to us)."""
    if _meta_get("search_quota_date") != _pt_date_str():
        return 0
    try:
        return int(_meta_get("search_quota_used", "0") or 0)
    except ValueError:
        return 0


def search_quota_bump(n=1):
    with _LEDGER_LOCK:
        today = _pt_date_str()
        used = search_quota_used() if _meta_get("search_quota_date") == today else 0
        _meta_set("search_quota_date", today)
        _meta_set("search_quota_used", used + int(n))
    _notify_quota_listeners()
    return used + int(n)


def search_quota_remaining():
    return max(0, SEARCH_QUOTA_DAILY_LIMIT - search_quota_used())


# ═════════════════════════════════════════════════════════════════════════
#  RAW API-UNIT LEDGER  (feeds the sidebar QuotaRing)
#  ---------------------------------------------------------------------
#  Counts actual YouTube Data API cost units — 100 for a search.list call,
#  1 for everything else (channels/videos/playlistItems/... .list) — the
#  same units Google's own quota page uses. Tracked PER KEY (see
#  key_quota_* below), keyed by a hash of the key string itself rather
#  than "is this key currently configured" — so a key's spend today
#  follows the key, not its row in Settings. Total capacity/remaining is
#  just the sum across whichever keys are currently configured.
# ═════════════════════════════════════════════════════════════════════════
API_QUOTA_PER_KEY = 10000   # YouTube's real daily unit cap, per project/key

# Call-kind vocabulary for the per-kind ledger below. Anything billed that
# isn't a search / videos / channels call lands in "other"; a day recorded
# before per-kind tracking existed reports its whole total as "unclassified"
# (see api_quota_history_by_kind / api_quota_mix) so the charts never invent a
# split or silently shrink a bar.
QUOTA_KINDS = ("search", "video", "channel", "other")


def api_quota_used():
    """Best-effort local count of raw API units spent today, across every
    key and every kind of call combined — resets at the same Pacific
    midnight as search_quota_* and key_quota_*. Kept around as a rough
    aggregate; the sidebar ring and per-key displays use key_quota_*
    instead, since this total alone can't say which key has how much
    left."""
    if _meta_get("api_quota_date") != _pt_date_str():
        return 0
    try:
        return int(_meta_get("api_quota_used", "0") or 0)
    except ValueError:
        return 0


def api_quota_bump(n=1, kind=None):
    with _LEDGER_LOCK:
        return _api_quota_bump_locked(n, kind)


def _api_quota_bump_locked(n=1, kind=None):
    today = _pt_date_str()
    used = api_quota_used() if _meta_get("api_quota_date") == today else 0
    new_used = used + int(n)
    _meta_set("api_quota_date", today)
    _meta_set("api_quota_used", new_used)
    # Per-DAY ledger, written alongside the running total. The aggregate
    # above is deliberately reset every Pacific midnight, so on its own it
    # can only ever answer "what about today?" — these rows are what let the
    # Usage & Quota page chart an actual week and work out a burn rate,
    # instead of drawing an invented trend. One tiny row per day; nothing
    # prunes them because a year of them is under 4 KB.
    _meta_set("aq_day::%s" % today, new_used)
    # Per-KIND split of the same day's spend, one tiny row per (day, kind).
    # Optional so every existing caller (kind=None) keeps writing only the
    # total; the googleapiclient wrapper passes the kind it already classifies.
    # This is what feeds the call-mix donut and the daily-mix stacked chart.
    if kind in QUOTA_KINDS:
        key = "aq_kind::%s::%s" % (today, kind)
        try:
            prev = int(_meta_get(key, "0") or 0)
        except (TypeError, ValueError):
            prev = 0
        _meta_set(key, prev + int(n))
    return new_used


def _api_quota_kinds_for_day(day, _rows=None):
    """{kind: units} recorded for one Pacific day, only the non-zero kinds."""
    if _rows is None:
        _rows = _meta_get_many(["aq_kind::%s::%s" % (day, k) for k in QUOTA_KINDS])
    out = {}
    for k in QUOTA_KINDS:
        v = _as_int(_rows.get("aq_kind::%s::%s" % (day, k), "0"))
        if v:
            out[k] = v
    return out


def api_quota_history(days=7):
    """[(YYYY-MM-DD, units_spent)] for the last `days` Pacific days,
    oldest first.

    Zero-filled: a day with no activity has no row at all, and a chart with
    holes punched in it is harder to read than one with honest zeros. Days are
    counted in PACIFIC time, not local time, because that is the clock
    YouTube's quota actually resets on — a chart bucketed by local midnight
    would disagree with the number in the sidebar for several hours a day.
    """
    days_list = _quota_days(days)
    rows = _meta_get_many(["aq_day::%s" % d for d in days_list])
    return [(d, _as_int(rows.get("aq_day::%s" % d, "0"))) for d in days_list]


def _quota_days(days):
    """The last `days` Pacific dates as YYYY-MM-DD, oldest first."""
    today = _pacific_now().date()
    return [(today - timedelta(days=i)).strftime("%Y-%m-%d")
            for i in range(int(days) - 1, -1, -1)]


def api_quota_burn_rate(days=7):
    """Average units/day over the days that actually saw traffic.

    Averaging over all seven would halve the rate of someone who only works
    weekdays and make "days remaining" read roughly twice as long as it is —
    the exact direction you do NOT want that estimate to be wrong in.
    """
    hist = [v for _d, v in api_quota_history(days)]
    active = [v for v in hist if v > 0]
    if not active:
        return 0.0
    return sum(active) / float(len(active))


def api_quota_history_by_kind(days=7):
    """[(YYYY-MM-DD, total_units, {kind: units})] for the last `days` Pacific
    days, oldest first — the per-kind companion to api_quota_history().

    The per-kind dict always carries an "unclassified" remainder equal to
    total minus the sum of the tracked kinds, so a day recorded before per-kind
    tracking existed (total known, no kind rows) still stacks to its full
    height as one neutral band instead of collapsing. Zero-filled the same way,
    for the same reason: honest zeros beat holes.
    """
    days_list = _quota_days(days)
    wanted = []
    for day in days_list:
        wanted.append("aq_day::%s" % day)
        wanted.extend("aq_kind::%s::%s" % (day, k) for k in QUOTA_KINDS)
    rows = _meta_get_many(wanted)
    out = []
    for day in days_list:
        total = _as_int(rows.get("aq_day::%s" % day, "0"))
        kinds = _api_quota_kinds_for_day(day, rows)
        remainder = total - sum(kinds.values())
        if remainder > 0:
            kinds["unclassified"] = remainder
        out.append((day, total, kinds))
    return out


def api_quota_mix(days=30):
    """{kind: units} summed over the last `days` Pacific days — the call-mix
    breakdown behind the donut. Carries the same "unclassified" remainder as
    api_quota_history_by_kind so pre-tracking spend is shown, not dropped."""
    return _mix_from_history(api_quota_history_by_kind(days))


def _mix_from_history(history):
    """api_quota_mix() over an already-fetched api_quota_history_by_kind()."""
    mix = {}
    for _day, total, kinds in history:
        for k, v in kinds.items():
            mix[k] = mix.get(k, 0) + v
    return {k: v for k, v in mix.items() if v > 0}


def api_quota_untracked_days(days=30):
    """How many days in the window spent units but recorded no per-kind split.

    This is what the donut's "Untracked" slice is actually made of, and it is
    worth naming: per-kind tracking was added after the daily totals were, so
    every day before it exists as one lump with no breakdown. Without this count
    the slice looks like calls the app failed to classify — a bug — when it is
    simply history. Those days age out of the window on their own.
    """
    return _untracked_from_history(api_quota_history_by_kind(days))


def _untracked_from_history(history):
    """api_quota_untracked_days() over an already-fetched history."""
    count = 0
    for _day, total, kinds in history:
        if total <= 0:
            continue
        tracked = sum(v for k, v in kinds.items() if k in QUOTA_KINDS)
        if tracked <= 0:
            count += 1
    return count


def niche_cache_stats():
    """(cached_searches, units_those_searches_would_cost_again).

    Every cached keyword search is a search.list call that will NOT be made
    again — and search.list is the expensive one at 100 units a shot, 1% of a
    key's entire day. Worth showing as a number, because it is the single
    biggest lever the user has over their own quota.
    """
    try:
        conn = db_connect(DATA_DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM niche_cache")
        rows = int((cur.fetchone() or [0])[0] or 0)
        conn.close()
    except Exception:
        return (0, 0)
    return (rows, rows * 100)


def api_quota_capacity(keys):
    """Total daily allotment across every currently-configured key."""
    return max(1, len(keys)) * API_QUOTA_PER_KEY


def api_quota_remaining(keys):
    """Total remaining across every configured key — summed PER KEY (see
    key_quota_remaining below) rather than one shared pool. That's what
    makes a key's spend follow the key itself: remove it from Settings,
    close the app, paste the same key back in tomorrow — or in five
    minutes — and it still reports exactly what it had left, because the
    ledger is keyed by the key's own hash, not by "is this key currently
    in my list"."""
    keys = [k for k in keys if k]
    return sum(max(0, API_QUOTA_PER_KEY - u) for u in keys_quota_used(keys))


def _key_hash(api_key):
    # Never store the raw key on disk, even locally — only enough of a
    # fingerprint to tell "same key" from "different key" again later.
    return hashlib.sha256((api_key or "").strip().encode("utf-8")).hexdigest()[:20]


def key_quota_used(api_key):
    """Units spent today by THIS specific key, regardless of whether it's
    currently sitting in Settings or was removed and typed back in."""
    h = _key_hash(api_key)
    if not h or _meta_get(f"kq_date::{h}") != _pt_date_str():
        return 0
    try:
        return int(_meta_get(f"kq_used::{h}", "0") or 0)
    except ValueError:
        return 0


def keys_quota_used(keys):
    """[units used today] for each key in `keys`, same rules as
    key_quota_used() but resolved in one query instead of two per key."""
    today = _pt_date_str()
    hashes = [_key_hash(k) for k in keys]
    wanted = []
    for h in hashes:
        if h:
            wanted += ["kq_date::%s" % h, "kq_used::%s" % h]
    rows = _meta_get_many(wanted)
    out = []
    for h in hashes:
        if not h or rows.get("kq_date::%s" % h) != today:
            out.append(0)
            continue
        try:
            out.append(int(rows.get("kq_used::%s" % h, "0") or 0))
        except ValueError:
            out.append(0)
    return out


def key_quota_bump(api_key, n=1):
    h = _key_hash(api_key)
    if not h:
        return 0
    with _LEDGER_LOCK:
        today = _pt_date_str()
        new_used = key_quota_used(api_key) + int(n)
        _meta_set(f"kq_date::{h}", today)
        _meta_set(f"kq_used::{h}", new_used)
    return new_used


def key_quota_remaining(api_key):
    return max(0, API_QUOTA_PER_KEY - key_quota_used(api_key))


def _install_quota_tracking():
    """Wrap googleapiclient's HttpRequest.execute exactly once so every
    YouTube Data API call this app makes — channel scans, searches,
    monetize checks, anything added later — is caught in a single place
    and fed into the ledger above, instead of instrumenting each call
    site (there are several, and not all of them go through
    execute_with_retry). Any failure here is swallowed: quota display is
    cosmetic and must never be able to break a real API call."""
    try:
        import googleapiclient.http as _gah
    except Exception:
        return
    if getattr(_gah.HttpRequest, "_quota_wrapped", False):
        return
    _orig_execute = _gah.HttpRequest.execute

    def _record_spend(self):
        try:
            uri = getattr(self, "uri", "") or ""
            uri_l = uri.lower()
            if "/search" in uri_l:
                n, kind = 100, "search"
            elif "/videos" in uri_l:
                n, kind = 1, "video"
            elif "/channels" in uri_l:
                n, kind = 1, "channel"
            elif any(seg in uri_l for seg in
                     ("/playlistitems", "/playlists",
                      "/commentthreads", "/comments", "/subscriptions",
                      "/i18nlanguages")):
                n, kind = 1, "other"
            else:
                n, kind = 0, None
            if n:
                api_quota_bump(n, kind=kind)
                # Google's client library puts the developer key straight
                # in the query string — this is how we know WHICH key just
                # spent these units, without touching any call site.
                m = re.search(r"[?&]key=([^&]+)", uri)
                if m:
                    key_quota_bump(urllib.parse.unquote(m.group(1)), n)
                _notify_quota_listeners()
        except Exception:
            pass

    def _quota_tracking_execute(self, *args, **kwargs):
        try:
            result = _orig_execute(self, *args, **kwargs)
        except Exception as exc:
            # Google bills a rejected request too (at least its base cost),
            # except when it was refused for quota / rate limit — so a failed
            # 400/404 still has to come off the counter, or the card drifts
            # above what Google's own console says is left.
            status = getattr(getattr(exc, "resp", None), "status", None)
            if status is not None and int(status) not in (403, 429):
                _record_spend(self)
            raise
        _record_spend(self)
        return result

    _gah.HttpRequest.execute = _quota_tracking_execute
    _gah.HttpRequest._quota_wrapped = True


_install_quota_tracking()
