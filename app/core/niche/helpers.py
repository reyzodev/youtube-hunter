"""app.core.niche.helpers - Youtube Scrapper."""

import base64
import re
from datetime import datetime, timedelta, timezone

from app.core.utils import humanize_count

# ═════════════════════════════════════════════════════════════════════════
#  NICHE FINDER — DISCOVERY ENGINE
#  ---------------------------------------------------------------------
#  Finds videos ACROSS all of YouTube (not just one channel) that match a
#  keyword, then filters them locally by subscriber count, view count and
#  the "multiplier" (views ÷ subscribers) — the signal that exposes a tiny
#  channel pulling huge numbers.
#
#  QUOTA REALITY (why this module is built the way it is):
#    · search.list  → its OWN daily bucket: 100 calls/day, 1 per page.
#    · videos.list  → 1 unit per 50 videos   (from the 10,000/day bucket)
#    · channels.list→ 1 unit per 50 channels (from the 10,000/day bucket)
#  So DISCOVERY is the scarce resource and ENRICHMENT is practically free.
#  Two consequences shaped the design:
#    1. Every fetched pool is cached to SQLite. Moving the subscriber/view
#       sliders re-filters the cached pool in-process — ZERO API calls.
#    2. A scrape-based discovery mode reads youtube.com/results directly,
#       costing no search quota at all, and still enriches through the
#       (cheap) videos/channels endpoints for exact numbers.
# ═════════════════════════════════════════════════════════════════════════

# ── human number parsing ("1k", "2.5M", "۱۰ میلیون") ─────────────────────
_DIGIT_MAP = {}
for _i, _c in enumerate("۰۱۲۳۴۵۶۷۸۹"):
    _DIGIT_MAP[ord(_c)] = str(_i)
for _i, _c in enumerate("٠١٢٣٤٥٦٧٨٩"):
    _DIGIT_MAP[ord(_c)] = str(_i)

_NUM_SUFFIXES = [
    ("میلیارد", 1_000_000_000),
    ("میلیون", 1_000_000),
    ("million", 1_000_000),
    ("billion", 1_000_000_000),
    ("هزار", 1_000),
    ("mil", 1_000_000),
    ("bil", 1_000_000_000),
    ("میل", 1_000_000),
    ("k", 1_000),
    ("m", 1_000_000),
    ("b", 1_000_000_000),
]


def parse_human_number(text, default=None):
    """'500'→500 · '1k'→1000 · '2.5M'→2500000 · '۱۰ میلیون'→10000000.
    Blank/garbage → `default`. Never raises."""
    if text is None:
        return default
    s = str(text).strip().translate(_DIGIT_MAP)
    for junk in (",", "٬", "،", " ", "‌", "_"):
        s = s.replace(junk, "")
    if not s:
        return default
    m = re.match(r"^([0-9]*\.?[0-9]+)([A-Za-z؀-ۿ]*)$", s)
    if not m:
        return default
    try:
        val = float(m.group(1))
    except ValueError:
        return default
    suf = (m.group(2) or "").lower()
    if suf:
        mult = None
        for key, factor in _NUM_SUFFIXES:
            if suf.startswith(key):
                mult = factor
                break
        if mult is None:
            return default
        val *= mult
    if val < 0:
        return default
    return int(val)


def format_multiplier(x):
    """0.8 → '0.8x' · 47.3 → '47x' · 21500 → '21.5Kx'."""
    try:
        x = float(x)
    except (TypeError, ValueError):
        return "—"
    if x >= 1000:
        return f"{humanize_count(x)}x"
    if x >= 10:
        return f"{x:.0f}x"
    return f"{x:.1f}x"


def is_gem_row(r):
    """True for the same 'hidden gem' videos the Hidden Gems KPI counts:
    a big view/subscriber multiplier on a channel that's still small.
    Shared here so grid cards can badge a video the KPI already counts,
    instead of re-deriving the threshold a third time."""
    return (bool(r.get("multiplier")) and r["multiplier"] >= 10
            and bool(r.get("subscriber_count")) and r["subscriber_count"] < 100_000)


# App-wide short/long boundary: anything UNDER 3 minutes is treated as a Short,
# anything at or over is Long-form. This single value is the whole rule now —
# YouTube's own Shorts cap grew to 3 min in 2024, and the product wants one
# consistent line rather than the old 60s-plus-#short-tag heuristic.
SHORT_MAX_SECONDS = 180   # < 3 min -> Short; >= 3 min -> Long-form


def detect_short(duration_s, title="", description=""):
    """True when a video is a Short: under SHORT_MAX_SECONDS (3 minutes).

    title/description are kept in the signature — call sites pass them
    positionally (see niche/search.py) — and are only consulted as a fallback
    when the duration is missing/unknown: a video that still carries a #short
    tag is a Short even if its length didn't come through.
    """
    try:
        duration_s = int(duration_s)
    except (TypeError, ValueError):
        duration_s = 0
    if duration_s <= 0:
        # No usable duration — lean on the tag if the uploader supplied one.
        return "#short" in f"{title} {description}".lower()
    return duration_s < SHORT_MAX_SECONDS


def fmt_duration(seconds):
    try:
        seconds = int(seconds)
    except (TypeError, ValueError):
        return "—"
    if seconds <= 0:
        return "—"
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


# ── YouTube `sp=` search-filter token (base64 protobuf) ──────────────────
def _pb_varint(value):
    out = bytearray()
    v = int(value)
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            break
    return bytes(out)


def build_youtube_sp(sort_by=0, upload_date=0, result_type=1, duration=0):
    """Build the `sp=` token youtube.com/results uses for its filter chips.

    sort_by     0 relevance · 1 rating · 2 upload date · 3 view count
    upload_date 0 any · 1 last hour · 2 today · 3 this week · 4 this month
                · 5 this year
    result_type 0 any · 1 video · 2 channel · 3 playlist · 4 movie
    duration    0 any · 1 under 4 min · 2 over 20 min · 3 between 4–20 min

    Verified against YouTube's own tokens: (0,3,1,0) → 'EgQIAxAB'
    ("this week" + video) and (3,0,1,0) → 'CAMSAhAB' ("sort by views")."""
    filters = bytearray()
    if upload_date:
        filters += b"\x08" + _pb_varint(upload_date)
    if result_type:
        filters += b"\x10" + _pb_varint(result_type)
    if duration:
        filters += b"\x18" + _pb_varint(duration)
    body = bytearray()
    if sort_by:
        body += b"\x08" + _pb_varint(sort_by)
    if filters:
        body += b"\x12" + _pb_varint(len(filters)) + bytes(filters)
    return base64.b64encode(bytes(body)).decode("ascii")


# days → the closest `sp` upload-date bucket (we still date-filter locally,
# this only narrows what YouTube hands back).
def days_to_sp_bucket(days):
    if not days:
        return 0
    if days <= 1:
        return 2      # today
    if days <= 7:
        return 3      # this week
    if days <= 31:
        return 4      # this month
    return 5          # this year


# ── relative time text ("3 weeks ago") → ISO timestamp ───────────────────
_REL_HOURS = {
    "second": 1 / 3600, "minute": 1 / 60, "hour": 1,
    "day": 24, "week": 168, "month": 730, "year": 8760,
}


def rel_time_to_iso(text):
    """'3 weeks ago' → approximate ISO-8601 UTC stamp. None if unparseable."""
    if not text:
        return None
    m = re.search(r"(\d+)\s*(second|minute|hour|day|week|month|year)s?", str(text), re.I)
    if not m:
        return None
    try:
        hours = int(m.group(1)) * _REL_HOURS[m.group(2).lower()]
    except (ValueError, KeyError):
        return None
    dt = datetime.now(timezone.utc) - timedelta(hours=hours)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_age_hours(published_at):
    """Hours since `published_at`, or None if it can't be read.

    v3.43c: also accepts fractional seconds, explicit offsets and a bare date
    ("2024-05-01T12:00:00.000Z", "…+00:00", "2024-05-01"). Those used to come
    back None, so the row slipped through every "Published" timeframe, sank to
    the bottom of "Newest First" and scored 0 on "Fastest Growing"."""
    s = str(published_at or "").strip()
    if not s:
        return None
    dt = None
    try:
        dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except Exception:
        try:
            iso = s[:-1] + "+00:00" if s.endswith(("Z", "z")) else s
            m = re.match(r"^(.*T\d\d:\d\d:\d\d)\.(\d+)(.*)$", iso)
            if m:   # Python < 3.11 only takes 3 or 6 fraction digits
                iso = m.group(1) + "." + (m.group(2) + "000000")[:6] + m.group(3)
            dt = datetime.fromisoformat(iso)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
        except Exception:
            return None
    return max((datetime.now(timezone.utc) - dt).total_seconds() / 3600, 0.5)


def _digits_to_int(text):
    if not text:
        return 0
    s = str(text).translate(_DIGIT_MAP)
    digits = re.sub(r"[^\d]", "", s)
    return int(digits) if digits else 0
