"""app.core.analysis.csv_report - Youtube Scrapper."""

import csv
import json
import os
import sqlite3
import statistics
from datetime import datetime

from app.config import CONFIG_PATH
from app.core.niche.helpers import fmt_duration
from app.core.utils import humanize_count, parse_iso8601_duration
from app.i18n import tr

# ═════════════════════════════════════════════════════════════════════════
#  HISTORY / CSV EXPORT ANALYSIS  —  turns a saved export back into an AI
#  breakdown of why the channel's top videos are working, and what to make
#  next. Reachable from every History card:
#    • "Analyze with AI"  → always runs a fresh generation
#    • "Show Analysis"    → reopens the last generated result instantly,
#      from the on-disk cache below, without spending another AI call
# ═════════════════════════════════════════════════════════════════════════
def _get_csv_analysis_path():
    return os.path.join(os.path.dirname(CONFIG_PATH), "csv_analysis.json")


CSV_ANALYSIS_PATH = _get_csv_analysis_path()


def _csv_analysis_key(path):
    """Normalize a file path so the same file always maps to the same
    cache entry regardless of how it was referenced."""
    try:
        return os.path.normcase(os.path.abspath(path))
    except Exception:
        return path


def _load_csv_analysis_store():
    try:
        with open(CSV_ANALYSIS_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_csv_analysis_store(store):
    try:
        with open(CSV_ANALYSIS_PATH, "w", encoding="utf-8") as f:
            json.dump(store, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def get_csv_analysis(path):
    """The cached {summary, sections, ideas, raw, created_at} dict for this
    export file, or None if it has never been analyzed."""
    return _load_csv_analysis_store().get(_csv_analysis_key(path))


def save_csv_analysis(path, parsed):
    store = _load_csv_analysis_store()
    entry = dict(parsed)
    entry["created_at"] = datetime.now().strftime("%Y-%m-%d %H:%M")
    store[_csv_analysis_key(path)] = entry
    _save_csv_analysis_store(store)
    return entry


def _read_export_rows(path):
    """Read a History export back into a list of dict rows, regardless of
    which format it was saved in (csv / jsonl / xlsx / db) — so 'Analyze
    with AI' works on every export the app can produce, not just CSV."""
    ext = os.path.splitext(path)[1].lower()
    rows = []
    try:
        if ext == ".csv":
            with open(path, encoding="utf-8-sig", newline="") as f:
                rows = [dict(r) for r in csv.DictReader(f)]
        elif ext == ".jsonl":
            with open(path, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rows.append(json.loads(line))
                    except Exception:
                        continue
        elif ext == ".xlsx":
            from openpyxl import load_workbook
            wb = load_workbook(path, read_only=True)
            try:      # read-only workbooks hold the file open until close()
                ws = wb.active
                it = ws.iter_rows(values_only=True)
                headers = [str(h) if h is not None else "" for h in (next(it, None) or [])]
                for r in it:
                    rows.append({headers[i]: r[i] for i in range(min(len(headers), len(r)))})
            finally:
                wb.close()
        elif ext == ".db":
            conn = sqlite3.connect(path)
            conn.row_factory = sqlite3.Row
            cur = conn.cursor()
            cur.execute("SELECT * FROM videos")
            rows = [dict(r) for r in cur.fetchall()]
            conn.close()
    except Exception:
        return []
    return rows


def _row_get(row, *keys):
    """Fetch the first non-empty value from `row` matching any of `keys`,
    tried case-sensitively first then case-insensitively — different export
    formats/versions have used different casings for the same column."""
    for k in keys:
        v = row.get(k)
        if v not in (None, ""):
            return v
    lower_map = {str(kk).lower(): vv for kk, vv in row.items()}
    for k in keys:
        v = lower_map.get(k.lower())
        if v not in (None, ""):
            return v
    return None


def _csv_video_stat_row(row):
    """Normalize one export row into the fields the CSV-analysis feature
    needs, tolerant of both the raw scraper column names (title,
    view_count, duration as ISO8601 …) and the capitalized names used by
    a couple of other export paths in the app."""
    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return 0.0
    dur_raw = str(_row_get(row, "duration", "Duration") or "")
    dur_s = parse_iso8601_duration(dur_raw) if dur_raw.startswith("P") else int(num(dur_raw))
    views = int(num(_row_get(row, "view_count", "Views", "views")))
    likes = int(num(_row_get(row, "like_count", "Likes", "likes")))
    comments = int(num(_row_get(row, "comment_count", "Comments", "comments")))
    return {
        "title": str(_row_get(row, "title", "Title") or "").strip() or tr("Untitled"),
        "views": views,
        "likes": likes,
        "comments": comments,
        "engagement": round(((likes + comments) / views) * 100, 2) if views > 0 else 0.0,
        "duration_s": dur_s,
        "duration_h": fmt_duration(dur_s),
        "published": str(_row_get(row, "publish_date", "Published", "published_at") or ""),
        "tags": str(_row_get(row, "tags", "Tags") or ""),
        "transcript": str(_row_get(row, "transcript", "Transcript") or ""),
    }


_CSV_DURATION_BUCKETS = [
    (0, 60, "< 1 min (Shorts)"),
    (60, 300, "1-5 min"),
    (300, 900, "5-15 min"),
    (900, 1800, "15-30 min"),
    (1800, None, "30+ min"),
]

_WEEKDAY_NAMES_EN = ["Monday", "Tuesday", "Wednesday", "Thursday",
                     "Friday", "Saturday", "Sunday"]


def _parse_export_date(raw):
    raw = (raw or "").strip()
    if not raw:
        return None
    for cand in (raw, raw.replace("Z", ""), raw[:19], raw[:10]):
        for fmt_ in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
            try:
                return datetime.strptime(cand, fmt_)
            except Exception:
                continue
    return None


def _csv_weekday_stats(stats):
    buckets = {i: [] for i in range(7)}
    for s in stats:
        dt = _parse_export_date(s.get("published"))
        if dt is not None:
            buckets[dt.weekday()].append(s["views"])
    return [f"{_WEEKDAY_NAMES_EN[i]}: {len(vs)} videos, avg {int(statistics.mean(vs)):,} views"
            for i, vs in buckets.items() if vs]


def _csv_analysis_build_overview(filename, rows):
    """Reduce a (potentially large) export into the compact, numbers-backed
    summary that gets sent to the AI. A full row dump would blow past any
    model's context window and cost real money for no benefit, so this
    keeps only what the four analysis sections actually need: the true top
    performers, a contrasting 'normal' sample, and pre-computed
    duration/weekday aggregates — so the model reasons from real stats
    instead of guessing at them from a handful of rows."""
    stats = [_csv_video_stat_row(r) for r in rows]
    stats = [s for s in stats if s["views"] or s["title"] != tr("Untitled")]
    if not stats:
        return None, 0

    views_list = [s["views"] for s in stats]
    avg_views = statistics.mean(views_list)
    median_views = statistics.median(views_list)
    ranked = sorted(stats, key=lambda s: s["views"], reverse=True)
    top = ranked[:12]
    rest = ranked[12:]
    normal = sorted(rest, key=lambda s: abs(s["views"] - median_views))[:6] or ranked[-6:]

    def line(s, with_transcript):
        txt = (s["transcript"] or "").strip().replace("\n", " ")
        if len(txt) > 260:
            txt = txt[:260] + "…"
        out = (f'- "{s["title"]}" | {humanize_count(s["views"])} views | '
               f'{humanize_count(s["likes"])} likes | {humanize_count(s["comments"])} comments | '
               f'engagement {s["engagement"]}% | length {s["duration_h"]} | '
               f'published {s["published"] or "N/A"}')
        if s["tags"]:
            out += f' | tags: {s["tags"][:120]}'
        if with_transcript and txt:
            out += f'\n  opening/transcript excerpt: "{txt}"'
        return out

    top_block = "\n".join(line(s, True) for s in top) or "N/A"
    normal_block = "\n".join(line(s, False) for s in normal) or "N/A"

    dur_lines = []
    for lo, hi, label in _CSV_DURATION_BUCKETS:
        bucket = [s["views"] for s in stats
                  if s["duration_s"] >= lo and (hi is None or s["duration_s"] < hi)]
        if bucket:
            dur_lines.append(f"{label}: {len(bucket)} videos, avg {int(statistics.mean(bucket)):,} views")

    weekday_lines = _csv_weekday_stats(stats)

    overview = (
        f"CHANNEL EXPORT: {filename}\n"
        f"TOTAL VIDEOS ANALYZED: {len(stats)}\n"
        f"AVERAGE VIEWS: {int(avg_views):,}\n"
        f"MEDIAN VIEWS: {int(median_views):,}\n\n"
        f"TOP PERFORMING VIDEOS ({len(top)}):\n{top_block}\n\n"
        f"TYPICAL / MID-RANGE VIDEOS FOR CONTRAST ({len(normal)}):\n{normal_block}\n\n"
        "VIEWS BY VIDEO LENGTH:\n" + ("\n".join(dur_lines) or "N/A") + "\n\n"
        "VIEWS BY PUBLISH WEEKDAY:\n" + ("\n".join(weekday_lines) or "N/A")
    )
    return overview, len(stats)


# The exact question set the analyst wants answered, kept verbatim (in
# Persian) and sent through to the model unmodified rather than translated
# into English and back — translating it would risk drifting from what was
# actually asked.
_CSV_ANALYSIS_QUESTIONS_FA = """۱. تحلیل علت موفقیت و وایرال شدن (Virality & Performance)
- پربازدیدترین ویدیوها چه ویژگی مشترکی دارند؟ (از نظر موضوع، سبک یا فرمت)
- چه تفاوتی بین ویدیوهای ویرال (پربازدید) و ویدیوهای معمولی این کانال وجود دارد؟
- نرخ تعامل (نسبت لایک و کامنت به بازدید) در کدام ویدیوها بالاترین حد است و چرا؟

۲. تحلیل عناوین و قلاب‌های متنی (Titles & Hooks)
- چه الگوها یا کلمات کلیدی مشترکی در عناوین موفق دیده می‌شود؟ (کلمات هیجانی، نام افراد معروف، اعداد، ایموجی و غیره)
- آیا مدت زمان ویدیوها روی میزان بازدید آن‌ها تاثیر مستقیم داشته است؟ کدام مدت زمان بیشترین بازدهی را داشته؟
- در صورت وجود متن (Transcript)، شروع ویدیوها (۳ تا ۵ ثانیه اول) چگونه مخاطب را درگیر می‌کند؟

۳. تحلیل رفتار و تعامل مخاطبان (Audience Engagement)
- کدام موضوعات بیشترین میزان کامنت و بحث را بین مخاطبان ایجاد کرده‌اند؟
- آیا زمان یا روز انتشار ویدیوها الگوی رشد یا افزایش بازدید نشان می‌دهد؟

۴. راهنمای عمل‌پایه برای ساخت ویدیوی مشابه (Actionable Blueprint)
- چگونه می‌توان بر اساس داده‌های این کانال یک ویدیوی پربازدید جدید تولید کرد؟
- ۳ ایده ایده‌آل برای ساخت ویدیوی بعدی همراه با ساختار عنوان پیشنهادی چیست؟
- چه سناریو یا قلاب اولیه (Hook) برای شروع ویدیوی جدید بر اساس این کانال پیشنهاد می‌شود؟"""

_CSV_ANALYSIS_JSON_SCHEMA = '''{
  "summary": "one short punchy paragraph (2-3 sentences) with the single biggest takeaway from this channel's data",
  "sections": [
    {"title": "تحلیل علت موفقیت و وایرال شدن", "points": ["...", "...", "..."]},
    {"title": "تحلیل عناوین و قلاب‌های متنی", "points": ["...", "...", "..."]},
    {"title": "تحلیل رفتار و تعامل مخاطبان", "points": ["...", "..."]},
    {"title": "راهنمای عمل‌پایه برای ساخت ویدیوی مشابه", "points": ["...", "..."]}
  ],
  "blueprint_ideas": [
    {"idea": "...", "title_structure": "...", "hook": "..."},
    {"idea": "...", "title_structure": "...", "hook": "..."},
    {"idea": "...", "title_structure": "...", "hook": "..."}
  ]
}'''


def _csv_analysis_prompt(filename, rows):
    overview, n = _csv_analysis_build_overview(filename, rows)
    if overview is None:
        return None
    return (
        "You are an expert YouTube data analyst. Below is real exported data from "
        "a YouTube channel scrape (title, views, likes, comments, duration, publish "
        "date, and transcript excerpts where available). Study it and answer the "
        "analyst's questions.\n\n"
        f"{overview}\n\n"
        "Answer these exact questions from the analyst, organized by section. Base "
        "every answer strictly on the data above — never invent numbers or claims "
        "the data doesn't support, and say so plainly if the data isn't enough to "
        "answer a specific sub-question.\n\n"
        f"{_CSV_ANALYSIS_QUESTIONS_FA}\n\n"
        "Respond in Persian (Farsi), and respond ONLY with a single JSON object (no "
        "markdown fences, no commentary before or after) shaped exactly like this:\n"
        f"{_CSV_ANALYSIS_JSON_SCHEMA}\n\n"
        "Keep each \"points\" entry to 1-3 sentences, 4-6 points per section. Write "
        "every string value in Persian — only the JSON keys stay in English."
    )


def _csv_analysis_parse_response(raw):
    """Pull the {summary, sections, blueprint_ideas} JSON out of the model's
    reply (same defensive pattern as _ai_ideas_parse_response — providers
    sometimes fence valid JSON in ``` despite being told not to)."""
    text = (raw or "").strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text[:4].lower() == "json":
            text = text[4:]
        text = text.strip()
    start, end = text.find("{"), text.rfind("}")
    candidate = text[start:end + 1] if (start != -1 and end != -1 and end > start) else text

    try:
        data = json.loads(candidate)
        sections = []
        for sec in (data.get("sections") or [])[:6]:
            if not isinstance(sec, dict):
                continue
            pts = [str(p).strip() for p in (sec.get("points") or []) if str(p).strip()]
            title = str(sec.get("title", "")).strip()
            if pts and title:
                sections.append({"title": title, "points": pts})
        ideas = []
        for idea in (data.get("blueprint_ideas") or [])[:3]:
            if not isinstance(idea, dict):
                continue
            cleaned = {
                "idea": str(idea.get("idea", "")).strip(),
                "title_structure": str(idea.get("title_structure", "")).strip(),
                "hook": str(idea.get("hook", "")).strip(),
            }
            if any(cleaned.values()):
                ideas.append(cleaned)
        if sections:
            return {
                "summary": str(data.get("summary", "")).strip(),
                "sections": sections,
                "ideas": ideas,
                "raw": text,
            }
    except Exception:
        pass

    # Fallback: couldn't parse structured JSON — surface the raw text
    # instead of failing outright, same philosophy as the AI Ideas parser.
    return {"summary": "", "sections": [], "ideas": [], "raw": text}


# ═════════════════════════════════════════════════════════════════════════
#  DEEP AI REPORT  —  a much heavier, data-grounded version of the History
#  export analysis above. Reuses the same row-parsing helpers, but sends the
#  model a bigger brief and asks it to design its own report structure
#  instead of filling in a fixed template: the model first works out what
#  the channel's actual niche is, then decides — on its own — which topics
#  are genuinely worth a section (a cooking channel and a real-estate
#  channel shouldn't get the same boilerplate), how many sections that
#  takes, and what to explain about each one. When the AI provider is
#  Gemini, a first grounded call researches current trends for that
#  specific niche via Google Search (Reddit, creator blogs, etc.) before
#  the real synthesis call, so the report isn't limited to this channel's
#  own numbers.
#
#  Every *number* in the HTML (views, charts, top videos, keyword
#  frequency…) is still computed here in Python from the real export rows —
#  never by the model — so the report can't quietly invent a statistic.
#  Only the narrative — why things work, what's missing, what to do next —
#  comes from the AI, and its structure is free-form, not templated.
#
#  The report is rendered into a single self-contained HTML file (own
#  dark/light toggle, print-to-PDF button) rather than shown inside the
#  app, so it can be read comfortably, printed, or revisited later without
#  spending another AI call.
#  Reachable from every History card:
#    • "Deep Analysis"     → always runs a fresh generation


# ═════════════════════════════════════════════════════════════════════════
#  CSV → BLUEPRINT CONTEXT  (v17)
#  ---------------------------------------------------------------------
#  The channel report (a self-contained HTML file) is gone from the UI. A
#  scraped export is now an INPUT to the blueprint builder instead: the creator
#  ticks one or more exports next to (or instead of) reference videos, and the
#  AI designs blueprints grounded in that data.
#
#  Everything numeric here is computed in Python from the real rows — the
#  model only ever sees the numbers, it never produces them. Each export also
#  contributes its top performers as citable references (C1, C2 …) carrying
#  their real URL, so a blueprint that says "this worked for that video" can
#  link straight to it.
# ═════════════════════════════════════════════════════════════════════════

def _row_video_url(row):
    url = str(_row_get(row, "video_url", "url", "URL", "link") or "").strip()
    if url:
        return url
    vid = str(_row_get(row, "video_id", "id", "Video ID") or "").strip()
    if vid and len(vid) == 11:
        return f"https://www.youtube.com/watch?v={vid}"
    return ""


def _row_channel(row):
    return str(_row_get(row, "channel_title", "channel", "Channel") or "").strip()


def _median(xs):
    return statistics.median(xs) if xs else 0


def csv_quick_stats(path):
    """Cheap, model-free numbers for one export: what the picker card and the
    blueprint's "Data pulse" section show. Returns {} when unreadable."""
    rows = _read_export_rows(path)
    stats = [_csv_video_stat_row(r) for r in rows]
    stats = [s for s in stats if s["views"] or s["title"] != tr("Untitled")]
    if not stats:
        return {}
    views = [s["views"] for s in stats]
    med = _median(views)
    durs = [s["duration_s"] for s in stats if s["duration_s"]]
    shorts = sum(1 for d in durs if d <= 180)

    # best length bucket by MEDIAN views (a mean is one viral outlier)
    best_len, best_len_med = "", 0
    for lo, hi, label in _CSV_DURATION_BUCKETS:
        b = [s["views"] for s in stats
             if s["duration_s"] and s["duration_s"] >= lo and (hi is None or s["duration_s"] < hi)]
        if len(b) >= 3 and _median(b) > best_len_med:
            best_len, best_len_med = label, _median(b)

    best_day, best_day_med = "", 0
    by_day = {}
    for s in stats:
        dt = _parse_export_date(s.get("published"))
        if dt is not None:
            by_day.setdefault(dt.weekday(), []).append(s["views"])
    for d, vs in by_day.items():
        if len(vs) >= 3 and _median(vs) > best_day_med:
            best_day, best_day_med = _WEEKDAY_NAMES_EN[d], _median(vs)

    eng = [s["engagement"] for s in stats if s["views"] > 0]
    outliers = sum(1 for v in views if med and v >= 3 * med)
    return {
        "videos": len(stats),
        "median_views": int(med),
        "avg_views": int(statistics.mean(views)),
        "top_views": int(max(views)),
        "outliers": outliers,
        "median_engagement": round(_median(eng), 2) if eng else 0.0,
        "shorts_share": round(shorts / len(durs), 2) if durs else 0.0,
        "median_duration_s": int(_median(durs)) if durs else 0,
        "best_length": best_len,
        "best_length_median": int(best_len_med),
        "best_weekday": best_day,
        "best_weekday_median": int(best_day_med),
    }


def csv_blueprint_source(path, ref_start=1, max_refs=8):
    """Everything one export contributes to a blueprint run.

    Returns {name, path, block, refs, stats} or None:
      block  the compact, numbers-backed brief for the prompt (the same
             reduction the old channel report used, plus the cached AI analysis
             of this file when the user already ran one from History);
      refs   the export's top performers as citable references
             {ref:"C1", title, url, channel, views, duration_s, is_short};
      stats  csv_quick_stats() — rendered by the UI, never by the model.
    """
    rows = _read_export_rows(path)
    if not rows:
        return None
    name = os.path.basename(path)
    overview, n = _csv_analysis_build_overview(name, rows)
    if overview is None:
        return None

    # top performers → citable refs, with their real links
    scored = []
    for r in rows:
        s = _csv_video_stat_row(r)
        if s["views"] <= 0:
            continue
        scored.append((s, r))
    scored.sort(key=lambda t: t[0]["views"], reverse=True)
    med = _median([s["views"] for s, _ in scored]) or 1
    refs = []
    for i, (s, r) in enumerate(scored[:max_refs]):
        refs.append({
            "ref": f"C{ref_start + i}",
            "title": s["title"],
            "url": _row_video_url(r),
            "channel": _row_channel(r),
            "views": s["views"],
            "multiplier": round(s["views"] / med, 1) if med else 0,
            "duration_s": s["duration_s"],
            "is_short": bool(s["duration_s"] and s["duration_s"] <= 180),
            "source": name,
        })
    ref_lines = "\n".join(
        f'[{x["ref"]}] "{x["title"]}" — {x["views"]:,} views ({x["multiplier"]}× this export\'s median)'
        for x in refs)

    cached = get_csv_analysis(path) or {}
    analysis_bits = []
    if cached.get("summary"):
        analysis_bits.append("Earlier analysis summary: " + cached["summary"])
    for sec in (cached.get("sections") or [])[:4]:
        pts = "; ".join((sec.get("points") or [])[:3])
        if pts:
            analysis_bits.append(f'{sec.get("title", "")}: {pts}')
    analysis_txt = ("\nPRIOR ANALYSIS OF THIS EXPORT (from the History page):\n"
                    + "\n".join(analysis_bits)) if analysis_bits else ""

    # keep each export's block bounded so 3-4 of them still fit comfortably
    if len(overview) > 5200:
        overview = overview[:5200] + "\n…(truncated)"
    block = (f"{overview}\n\nCITABLE TOP VIDEOS FROM THIS EXPORT:\n{ref_lines}"
             f"{analysis_txt}")
    return {"name": name, "path": path, "block": block, "refs": refs,
            "stats": csv_quick_stats(path), "rows": n}


def csv_classify_format(sources):
    """'short' | 'long' for a run whose only inputs are exports: the format
    the exports' videos are mostly in."""
    shares = [s.get("stats", {}).get("shorts_share", 0) for s in sources if s]
    if not shares:
        return "short"
    return "short" if (sum(shares) / len(shares)) >= 0.5 else "long"
