"""app.core.ai.chat_sources - YouTube Hunter.

Turns whatever the user hands the AI Chat into compact, numbers-first text the
model can reason over — a "digest" per source.

A source is a plain dict:
    {"key": str,              stable identity (dedupe per thread)
     "kind": "video"|"table"|"text"|"image"|"doc"|"brief",
     "title": str, "subtitle": str,
     "thumb": str,            thumbnail URL (videos) or local path (images)
     "path": str,             local file (files / Drive imports)
     "row": dict,             the raw Niche Finder / Archive row (videos)
     "origin": "niche"|"archive"|"link"|"file"|"drive"|"export"|"brief"}

A "brief" (v3.49) is either a saved Niche Scan snapshot (its measured
aggregates + the AI research brief written over them, keyed by snapshot_key)
or a brief the user pasted / wrote themselves (stored as a .md file). Both are
digested into text the model can critique and build on.

Why digest instead of dumping: a 1,600-row export or a 20-minute transcript
would blow past any model's context and cost real money for nothing. The
digest keeps what an analyst would actually look at — the aggregates, the top
of the distribution, a contrast sample, the opening of a transcript — and is
cached per source so a long conversation never re-reads a file.

Everything here runs on a worker thread and never touches Qt widgets. Image
downscaling uses QImage, which is documented as safe off the GUI thread.
"""

import base64
import csv
import io
import json
import mimetypes
import os
import re
import statistics

from app.core.utils import humanize_count, parse_iso8601_duration
from app.i18n import tr

TABLE_EXTS = (".csv", ".tsv", ".xlsx", ".xlsm", ".jsonl", ".db")
TEXT_EXTS = (".txt", ".md", ".json", ".srt", ".vtt", ".log", ".html", ".htm",
             ".xml", ".yaml", ".yml")
DOC_EXTS = (".pdf", ".docx")
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")
ALL_EXTS = TABLE_EXTS + TEXT_EXTS + DOC_EXTS + IMAGE_EXTS

MAX_FILE_BYTES = 40 * 1024 * 1024          # refuse anything bigger, politely
_TEXT_CHARS = 14000                        # per text source
_TRANSCRIPT_CHARS = 2600                   # per video (opening + ending)
_TRANSCRIPT_TAIL = 700                     # of which: the ending (payoff / CTA)
_TAIL_MARK = " [...] "


def _transcript_excerpt(text):
    """(opening, ending) of a transcript within _TRANSCRIPT_CHARS. The opening
    is the hook the model is asked about most; the ending is the payoff and
    the call to action, which the old opening-only cut never showed — so the
    model could judge a hook but not whether the video kept its promise.
    `ending` is "" when the whole transcript fits."""
    t = " ".join(str(text or "").split())
    if _TAIL_MARK.strip() in t:                 # already stored as head [...] tail
        head, _, tail = t.partition(_TAIL_MARK.strip())
        return head.strip(), tail.strip()
    if len(t) <= _TRANSCRIPT_CHARS:
        return t, ""
    head = t[:_TRANSCRIPT_CHARS - _TRANSCRIPT_TAIL].rsplit(" ", 1)[0]
    tail = t[-_TRANSCRIPT_TAIL:].split(" ", 1)[-1]
    return head, tail


def _transcript_store(text):
    head, tail = _transcript_excerpt(text)
    return head + (_TAIL_MARK + tail if tail else "")


def _is_short_row(r, dur):
    """The app-wide Shorts rule (app.core.niche.helpers.detect_short: under
    3 minutes). An explicit flag on the row wins. This used to be `dur <= 60`
    here while every other screen used 3 minutes, so a 2-minute Short was
    filed as long-form in the chat's analysis and compared with the wrong set."""
    flag = r.get("is_short")
    if isinstance(flag, bool):
        return flag
    if flag in (1, "1", "true", "True"):
        return True
    try:
        from app.core.niche.helpers import detect_short
        return bool(detect_short(dur, r.get("title", ""), r.get("description", "")))
    except Exception:
        return 0 < int(dur or 0) < 180
_IMAGE_EDGE = 1568                         # longest side sent to a vision model


def kind_for_path(path):
    ext = os.path.splitext(path or "")[1].lower()
    if ext in TABLE_EXTS:
        return "table"
    if ext in IMAGE_EXTS:
        return "image"
    if ext in DOC_EXTS:
        return "doc"
    if ext in TEXT_EXTS:
        return "text"
    return ""


def file_source(path, origin="file"):
    """A source dict for a local file, or raise ValueError with a readable
    reason (unsupported type, too large, missing)."""
    if not path or not os.path.isfile(path):
        raise ValueError(tr("That file could not be found."))
    kind = kind_for_path(path)
    if not kind:
        raise ValueError(tr("This file type isn't supported yet."))
    try:
        size = os.path.getsize(path)
    except OSError:
        size = 0
    if size > MAX_FILE_BYTES:
        raise ValueError(tr("That file is too large (40 MB max)."))
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lstrip(".").upper()
    return {
        "key": "file:" + os.path.normcase(os.path.abspath(path)),
        "kind": kind,
        "title": name,
        "subtitle": ext + " · " + _size_text(size),
        "thumb": path if kind == "image" else "",
        "path": path,
        "origin": origin,
    }


def video_source(row, origin="niche"):
    """A source dict for one video row from Niche Finder / Archive / a link."""
    row = dict(row or {})
    vid = str(row.get("video_id") or "").strip()
    views = _num(row.get("view_count"))
    bits = []
    if row.get("channel_title"):
        bits.append(str(row["channel_title"]))
    if views:
        bits.append(humanize_count(int(views)) + " " + tr("views"))
    mult = row.get("multiplier")
    if mult:
        try:
            bits.append("%s×" % _short_mult(float(mult)))
        except (TypeError, ValueError):
            pass
    return {
        "key": "video:" + (vid or str(row.get("title", ""))[:40]),
        "kind": "video",
        "title": str(row.get("title") or tr("Untitled")),
        "subtitle": " · ".join(bits),
        "thumb": row.get("thumbnail_url")
                 or (f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg" if vid else ""),
        "row": _slim_row(row),
        "origin": origin,
    }


def _slim_row(row):
    keep = ("video_id", "title", "channel_title", "channel_id", "view_count",
            "like_count", "comment_count", "subscriber_count", "multiplier",
            "duration_s", "duration", "published_at", "publish_date",
            "description", "tags", "velocity", "engagement", "is_short",
            "channel_video_count", "channel_total_views", "channel_country",
            "audio_lang", "has_captions", "thumbnail_url", "transcript")
    out = {k: row.get(k) for k in keep if row.get(k) not in (None, "", "N/A")}
    if isinstance(out.get("description"), str):
        out["description"] = out["description"][:600]
    if isinstance(out.get("transcript"), str):
        out["transcript"] = _transcript_store(out["transcript"])
    return out


def brief_source(snapshot_key, query="", total_videos=0, has_brief=False):
    """A source dict for one saved Niche Scan snapshot (its brief + numbers)."""
    bits = [tr("Niche Scan")]
    if total_videos:
        bits.append(tr("{n} videos").format(n=total_videos))
    bits.append(tr("Research brief") if has_brief else tr("Numbers only"))
    return {
        "key": "brief:" + str(snapshot_key),
        "kind": "brief",
        "title": str(query or tr("Untitled brief")),
        "subtitle": " · ".join(bits),
        "thumb": "",
        "snapshot_key": str(snapshot_key),
        "origin": "brief",
    }


def written_brief_source(path, title):
    """A source dict for a brief the user pasted (already saved to `path`)."""
    try:
        size = os.path.getsize(path)
    except OSError:
        size = 0
    return {
        "key": "brief:file:" + os.path.normcase(os.path.abspath(path)),
        "kind": "brief",
        "title": str(title or tr("My brief")),
        "subtitle": tr("Written brief") + " · " + _size_text(size),
        "thumb": "",
        "path": path,
        "origin": "brief",
    }


_BRIEF_CHARS = 12000
_BRIEF_ROWS = 15


def _flatten(value, indent=0, out=None, limit=_BRIEF_CHARS):
    """A nested dict/list as indented "key: value" lines — far cheaper in
    tokens than JSON and just as readable for a model."""
    out = [] if out is None else out
    pad = "  " * indent
    if sum(len(x) for x in out) > limit:
        return out
    if isinstance(value, dict):
        for k, v in value.items():
            if v in (None, "", [], {}):
                continue
            if isinstance(v, (dict, list)):
                out.append(f"{pad}{k}:")
                _flatten(v, indent + 1, out, limit)
            else:
                out.append(f"{pad}{k}: {_fmt(v) if isinstance(v, float) else v}")
    elif isinstance(value, list):
        for v in value[:12]:
            if isinstance(v, (dict, list)):
                out.append(f"{pad}-")
                _flatten(v, indent + 1, out, limit)
            else:
                out.append(f"{pad}- {v}")
    else:
        out.append(f"{pad}{value}")
    return out


def _brief_digest(source):
    title = source.get("title", "")
    if source.get("path"):
        raw = _read_text_file(source["path"], _BRIEF_CHARS * 2).strip()
        return (f"[BRIEF · written by the user] {title} ({len(raw):,} chars"
                f"{', truncated' if len(raw) > _BRIEF_CHARS else ''}):\n"
                + raw[:_BRIEF_CHARS])
    from app.core.db.insights import insights_get
    rec = insights_get(source.get("snapshot_key") or "")
    if not rec:
        return (f"[BRIEF] {title}: this saved Niche Scan snapshot no longer "
                "exists (it was deleted). Ask the user to re-run the scan.")
    parts = [f"[BRIEF · saved Niche Scan] query: {rec.get('query') or title} · "
             f"mode: {rec.get('mode')} · saved: {rec.get('created_at')}"]
    ai = rec.get("ai") or {}
    if ai:
        parts.append("AI RESEARCH BRIEF (written by a model earlier; treat as a "
                     "claim to verify against the numbers, not as fact):")
        parts.append("\n".join(_flatten(ai, 1, limit=_BRIEF_CHARS // 2)))
    else:
        parts.append("AI RESEARCH BRIEF: none yet (numbers only).")
    an = rec.get("analytics") or {}
    if an:
        parts.append("MEASURED AGGREGATES (computed exactly by the app):")
        parts.append("\n".join(_flatten(an, 1, limit=_BRIEF_CHARS // 3)))
    rows = rec.get("rows") or []
    if rows:
        def _views(r):
            return _num(r.get("view_count"))
        top = sorted(rows, key=_views, reverse=True)[:_BRIEF_ROWS]
        parts.append(f"TOP {len(top)} OF {len(rows)} VIDEOS BY VIEWS:")
        for r in top:
            bits = [str(r.get("title") or "")[:90],
                    str(r.get("channel_title") or ""),
                    humanize_count(int(_views(r))) + " views"]
            if r.get("multiplier"):
                try:
                    bits.append("%s× subs" % _short_mult(float(r["multiplier"])))
                except (TypeError, ValueError):
                    pass
            if r.get("published_at"):
                bits.append(str(r["published_at"])[:10])
            parts.append("  - " + " · ".join(b for b in bits if b))
    text = "\n".join(parts)
    return text[:_BRIEF_CHARS + 2000]


# ═════════════════════════════════════════════════════════════════════════
#  Digests
# ═════════════════════════════════════════════════════════════════════════
def digest(source, fetch_transcripts=True):
    """Compact text for one source. Never raises — a source that can't be read
    says so in its digest, so the model can tell the user."""
    kind = source.get("kind")
    try:
        if kind == "video":
            return _video_digest(source, fetch_transcripts)
        if kind == "table":
            return _table_digest(source["path"], source.get("title", ""))
        if kind == "text":
            return _text_digest(source["path"], source.get("title", ""))
        if kind == "doc":
            return _doc_digest(source["path"], source.get("title", ""))
        if kind == "brief":
            return _brief_digest(source)
        if kind == "image":
            return (f"[IMAGE] {source.get('title', '')} — the picture rides on the "
                    "user message it was shared with (recent images are re-sent; "
                    "if it is no longer visible to you, ask the user to attach it again).")
    except Exception as e:      # noqa: BLE001 — a bad file must not kill the turn
        return f"[{(kind or 'FILE').upper()}] {source.get('title', '')}: could not be read ({e})."
    return ""


def _video_digest(source, fetch_transcripts):
    r = source.get("row") or {}
    vid = r.get("video_id", "")
    views = int(_num(r.get("view_count")))
    subs = int(_num(r.get("subscriber_count")))
    likes = int(_num(r.get("like_count")))
    comments = int(_num(r.get("comment_count")))
    dur = r.get("duration_s")
    if not dur and str(r.get("duration", "")).startswith("P"):
        dur = parse_iso8601_duration(r.get("duration"))
    dur = int(_num(dur))
    lines = [f'[VIDEO] "{r.get("title", source.get("title", ""))}"']
    meta = []
    if r.get("channel_title"):
        meta.append("channel: " + str(r["channel_title"]))
    if vid:
        meta.append(f"https://youtu.be/{vid}")
    if meta:
        lines.append("  " + " | ".join(meta))
    stats = []
    if views:
        stats.append(f"views {views:,}")
    if subs:
        stats.append(f"channel subs {subs:,}")
    if r.get("multiplier"):
        stats.append(f"outlier {float(r['multiplier']):.1f}× (views/subs)")
    if likes:
        stats.append(f"likes {likes:,}")
    if comments:
        stats.append(f"comments {comments:,}")
    if views and (likes or comments):
        stats.append(f"engagement {((likes + comments) / views) * 100:.2f}%")
    if dur:
        stats.append(f"length {dur // 60}:{dur % 60:02d}"
                     + (" (Short)" if _is_short_row(r, dur) else " (long-form)"))
    pub = r.get("published_at") or r.get("publish_date")
    if pub:
        stats.append(f"published {str(pub)[:10]}")
    if r.get("velocity"):
        stats.append(f"~{int(_num(r['velocity'])):,} views/hour lifetime")
    if r.get("channel_video_count"):
        stats.append(f"channel has {int(_num(r['channel_video_count'])):,} videos")
    if stats:
        lines.append("  " + " | ".join(stats))
    extra = derived_line(r)
    if extra:
        lines.append(extra)
    tags = r.get("tags")
    if tags:
        if isinstance(tags, (list, tuple)):
            tags = ", ".join(str(t) for t in tags[:15])
        lines.append("  tags: " + str(tags)[:240])
    desc = (r.get("description") or "").strip().replace("\n", " ")
    if desc:
        lines.append("  description: " + desc[:400])
    transcript = (r.get("transcript") or "").strip()
    if not transcript and fetch_transcripts and vid:
        try:
            # the chat's quick path: cached, one round-trip, no slow fallback
            # when YouTube has already said the video has no captions
            from app.core.transcripts import fetch_transcript_quick
            _status, text, _err = fetch_transcript_quick(vid)
            if text and text != "N/A":
                transcript = text
                r["transcript"] = _transcript_store(text)
        except Exception:
            transcript = ""
    if transcript:
        head, tail = _transcript_excerpt(transcript)
        lines.append("  transcript (opening): \"" + head + ("…" if tail else "") + "\"")
        if tail:
            lines.append("  transcript (ending — payoff / CTA): \"…" + tail + "\"")
    else:
        lines.append("  transcript: not available")
    return "\n".join(lines)


def read_table(path, limit=20000):
    """Rows of a table file as a list of dicts (header → value)."""
    ext = os.path.splitext(path)[1].lower()
    if ext in (".csv", ".tsv"):
        raw = _read_text_file(path, None)
        sample = raw[:4096]
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t|")
        except csv.Error:
            dialect = csv.excel_tab if ext == ".tsv" else csv.excel
        rdr = csv.DictReader(io.StringIO(raw), dialect=dialect)
        out = []
        for i, r in enumerate(rdr):
            if i >= limit:
                break
            out.append({(k or "").strip(): v for k, v in r.items() if k is not None})
        return out
    # The app's own export reader handles jsonl / xlsx / db.
    from app.core.analysis.csv_report import _read_export_rows
    return _read_export_rows(path)[:limit]


def _table_digest(path, title):
    rows = read_table(path)
    if not rows:
        return f"[TABLE] {title}: empty or unreadable."
    cols = []
    for r in rows[:200]:
        for k in r.keys():
            if k not in cols:
                cols.append(k)
    lines = [f"[TABLE] {title} — {len(rows):,} rows × {len(cols)} columns",
             "  columns: " + ", ".join(cols[:60])]

    # A YouTube Hunter / YouTube export? Reuse the analyst-grade overview.
    lower = {c.lower() for c in cols}
    if ("title" in lower) and (lower & {"view_count", "views"}):
        try:
            from app.core.analysis.csv_report import _csv_analysis_build_overview
            overview, _n = _csv_analysis_build_overview(title, rows)
            if overview:
                lines.append(overview)
        except Exception:
            pass

    # Column profile.
    profile = []
    numeric_cols = []
    for c in cols[:40]:
        vals = [r.get(c) for r in rows]
        vals = [v for v in vals if v not in (None, "", "N/A")]
        if not vals:
            continue
        nums = [_num(v, None) for v in vals]
        nums = [n for n in nums if n is not None]
        if len(nums) >= max(3, int(len(vals) * 0.8)):
            numeric_cols.append(c)
            profile.append(f"  {c}: numeric · min {_fmt(min(nums))} · median "
                           f"{_fmt(statistics.median(nums))} · mean {_fmt(statistics.mean(nums))}"
                           f" · max {_fmt(max(nums))} · sum {_fmt(sum(nums))}")
        else:
            distinct = {}
            for v in vals:
                s = str(v)[:60]
                distinct[s] = distinct.get(s, 0) + 1
            if len(distinct) <= max(12, len(vals) // 10):
                top = sorted(distinct.items(), key=lambda kv: -kv[1])[:8]
                profile.append(f"  {c}: {len(distinct)} distinct · top: "
                               + "; ".join(f"{k} ({n})" for k, n in top))
            else:
                profile.append(f"  {c}: text · {len(distinct)} distinct · e.g. "
                               + " | ".join(list(distinct)[:3]))
    if profile:
        lines.append("COLUMN PROFILE:")
        lines.extend(profile)

    # Top rows by the most "views-like" numeric column, then a plain head.
    rank_col = None
    for want in ("view_count", "views", "multiplier", "revenue", "impressions",
                 "watch_time", "likes", "like_count"):
        for c in numeric_cols:
            if c.lower() == want:
                rank_col = c
                break
        if rank_col:
            break
    if not rank_col and numeric_cols:
        rank_col = numeric_cols[0]
    show = [c for c in cols if c.lower() not in ("description", "transcript",
                                                  "structured_prompt", "thumbnail_url")][:10]
    if rank_col:
        ranked = sorted(rows, key=lambda r: -(_num(r.get(rank_col), 0) or 0))[:15]
        lines.append(f"TOP 15 ROWS BY {rank_col}:")
        lines.extend("  " + _row_line(r, show) for r in ranked)
    lines.append("FIRST 10 ROWS:")
    lines.extend("  " + _row_line(r, show) for r in rows[:10])
    text = "\n".join(lines)
    return text[:16000]


def _row_line(r, cols):
    return " | ".join(f"{c}={str(r.get(c, ''))[:70]}" for c in cols
                      if r.get(c) not in (None, ""))


def _text_digest(path, title):
    raw = _read_text_file(path, _TEXT_CHARS * 2)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".srt", ".vtt"):
        raw = re.sub(r"^\d+\s*$|^\d\d:\d\d[:.,\d\s\->]+$|^WEBVTT.*$", "", raw,
                     flags=re.M)
        raw = re.sub(r"\n{2,}", "\n", raw)
    if ext in (".html", ".htm"):
        raw = re.sub(r"<[^>]+>", " ", raw)
    raw = raw.strip()
    cut = raw[:_TEXT_CHARS]
    return (f"[FILE] {title} ({len(raw):,} chars{', truncated' if len(raw) > _TEXT_CHARS else ''}):\n"
            + cut)


def _doc_digest(path, title):
    ext = os.path.splitext(path)[1].lower()
    text = ""
    if ext == ".pdf":
        try:
            from pypdf import PdfReader          # optional dependency
            reader = PdfReader(path)
            text = "\n".join((p.extract_text() or "") for p in reader.pages[:40])
        except ImportError:
            return (f"[PDF] {title}: PDF reading needs the optional 'pypdf' "
                    "package (pip install pypdf).")
    elif ext == ".docx":
        try:
            import zipfile
            with zipfile.ZipFile(path) as z:
                xml = z.read("word/document.xml").decode("utf-8", "replace")
            xml = re.sub(r"</w:p>", "\n", xml)
            text = re.sub(r"<[^>]+>", "", xml)
        except Exception as e:
            return f"[DOCX] {title}: could not be read ({e})."
    text = re.sub(r"[ \t]+", " ", text).strip()
    return (f"[DOCUMENT] {title} ({len(text):,} chars):\n" + text[:_TEXT_CHARS])


def image_payload(path):
    """(mime, base64) for a vision model — downscaled so the longest edge is at
    most _IMAGE_EDGE px, re-encoded as JPEG unless it has transparency."""
    try:
        from PySide6.QtCore import QBuffer, QByteArray, QIODevice, Qt
        from PySide6.QtGui import QImage
        img = QImage(path)
        if not img.isNull():
            if max(img.width(), img.height()) > _IMAGE_EDGE:
                img = img.scaled(_IMAGE_EDGE, _IMAGE_EDGE, Qt.KeepAspectRatio,
                                 Qt.SmoothTransformation)
            fmt, mime = ("PNG", "image/png") if img.hasAlphaChannel() else ("JPG", "image/jpeg")
            ba = QByteArray()
            buf = QBuffer(ba)
            buf.open(QIODevice.WriteOnly)
            img.save(buf, fmt, 88)
            buf.close()
            return mime, base64.b64encode(bytes(ba.data())).decode("ascii")
    except Exception:
        pass
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        return mime, base64.b64encode(f.read()).decode("ascii")


def sources_block(digests, budget=42000):
    """Join digests under one character budget. Later sources are trimmed
    first: the ones the user attached first are usually the subject."""
    out, used = [], 0
    for i, d in enumerate(digests, 1):
        if not d:
            continue
        piece = f"--- SOURCE {i} ---\n{d}\n"
        if used + len(piece) > budget:
            room = budget - used
            if room > 600:
                out.append(piece[:room] + "…\n[trimmed to fit]")
            out.append(f"[{len(digests) - i} more source(s) omitted — context full]")
            break
        out.append(piece)
        used += len(piece)
    return "\n".join(out)


# ── small helpers ─────────────────────────────────────────────────────────
def _read_text_file(path, limit):
    with open(path, "rb") as f:
        data = f.read() if limit is None else f.read(limit * 4)
    for enc in ("utf-8-sig", "utf-16", "cp1256", "latin-1"):
        try:
            text = data.decode(enc)
            if enc == "utf-16" and "\x00" in text[:200]:
                continue
            return text if limit is None else text[:limit]
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", "replace")


def _num(v, default=0.0):
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().replace(",", "").replace("%", "")
    if not s:
        return default
    try:
        return float(s)
    except ValueError:
        return default


def _fmt(x):
    if abs(x) >= 1000:
        return f"{x:,.0f}"
    if float(x).is_integer():
        return str(int(x))
    return f"{x:.2f}"


def _short_mult(m):
    return f"{m:.0f}" if m >= 10 else f"{m:.1f}"


def _size_text(n):
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n / 1024:.0f} KB"
    return f"{n / (1024 * 1024):.1f} MB"


# ═════════════════════════════════════════════════════════════════════════
#  Derived metrics + the cross-video analysis
# ═════════════════════════════════════════════════════════════════════════
# Language models are bad at arithmetic over a dozen rows and good at reading
# a table someone already computed. So the maths an analyst would do first —
# per-video rates, the set's medians, who beats the median and by how much,
# what the winners' titles share — is done here, in Python, exactly, and
# handed over as facts. The model's job becomes interpretation, which is what
# it is actually good at, and the numbers in its answer stop drifting.
_EMOJI_RE = re.compile("[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF]")
_CAPS_RE = re.compile(r"\b[A-Z]{3,}\b")
_NUM_RE = re.compile(r"[0-9\u06F0-\u06F9]")
_FIRST_PERSON_RE = re.compile(r"\b(?:I|I'm|I've|my|me|we|our)\b|(?:^|\s)(?:من|ما)(?=\s|$)", re.I)


def _pub_date(r):
    import datetime as _dt
    raw = str(r.get("published_at") or r.get("publish_date") or "")[:10]
    try:
        return _dt.date.fromisoformat(raw)
    except ValueError:
        return None


def derived_metrics(r):
    """Per-video rates the raw row does not carry. Missing inputs → missing
    keys, never zeros (a zero would read as a real, terrible number)."""
    import datetime as _dt
    out = {}
    views = _num(r.get("view_count"))
    likes = _num(r.get("like_count"))
    comments = _num(r.get("comment_count"))
    subs = _num(r.get("subscriber_count"))
    pub = _pub_date(r)
    if pub:
        age = max(1, (_dt.date.today() - pub).days)
        out["age_days"] = age
        if views:
            out["views_per_day"] = views / age
        out["weekday"] = pub.strftime("%a")
    if views:
        if likes:
            out["like_rate"] = likes / views * 100
        if comments:
            out["comment_rate"] = comments / views * 100
    mult = r.get("multiplier")
    try:
        mult = float(mult) if mult not in (None, "") else None
    except (TypeError, ValueError):
        mult = None
    if mult is None and views and subs:
        mult = views / subs
    if mult is not None:
        out["multiplier"] = mult
    ch_views = _num(r.get("channel_total_views"))
    ch_count = _num(r.get("channel_video_count"))
    if views and ch_views and ch_count:
        avg = ch_views / ch_count
        if avg > 0:
            out["vs_channel_avg"] = views / avg
    dur = r.get("duration_s")
    if not dur and str(r.get("duration", "")).startswith("P"):
        dur = parse_iso8601_duration(r.get("duration"))
    dur = int(_num(dur))
    if dur:
        out["duration_s"] = dur
        out["is_short"] = _is_short_row(r, dur)
    return out


def derived_line(r):
    """The derived metrics as one digest line (or "")."""
    d = derived_metrics(r)
    bits = []
    if "age_days" in d:
        bits.append(f"age {d['age_days']:,} days")
    if "views_per_day" in d:
        bits.append(f"~{_fmt(d['views_per_day'])} views/day lifetime")
    if "vs_channel_avg" in d:
        bits.append(f"{d['vs_channel_avg']:.1f}× the channel's average video")
    if "like_rate" in d:
        bits.append(f"like rate {d['like_rate']:.2f}%")
    if "comment_rate" in d:
        bits.append(f"comment rate {d['comment_rate']:.3f}%")
    return ("  derived: " + " | ".join(bits)) if bits else ""


def _title_features(title):
    t = str(title or "")
    return {
        "chars": len(t),
        "words": len(t.split()),
        "number": bool(_NUM_RE.search(t)),
        "question": ("?" in t) or ("؟" in t),
        "brackets": bool(re.search(r"[\[\(【「]", t)),
        "caps": bool(_CAPS_RE.search(t)),
        "emoji": bool(_EMOJI_RE.search(t)),
        "exclaim": "!" in t,
        "first_person": bool(_FIRST_PERSON_RE.search(t)),
    }


def _pct(n, d):
    return f"{(n / d * 100):.0f}%" if d else "—"


def _med(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


def video_set_analysis(numbered):
    """Cross-video facts for the videos attached to a thread.

    `numbered` is [(source_number, source_dict), ...] for the video sources
    only, numbered exactly as the SOURCES block numbers them, so every row
    here can be cited as SOURCE n. Returns "" for fewer than two videos —
    one video has nothing to be compared with."""
    rows = []
    for n, s in numbered or []:
        r = s.get("row") or {}
        d = derived_metrics(r)
        rows.append({"n": n, "title": str(r.get("title") or s.get("title") or ""),
                     "channel": str(r.get("channel_title") or ""),
                     "views": _num(r.get("view_count")), **d})
    if len(rows) < 2:
        return ""

    shorts = [x for x in rows if x.get("is_short")]
    longs = [x for x in rows if "is_short" in x and not x.get("is_short")]
    channels = {x["channel"] for x in rows if x["channel"]}
    has_mult = sum(1 for x in rows if x.get("multiplier") is not None) >= max(2, len(rows) // 2)
    rank_key = "multiplier" if has_mult else ("views_per_day" if any("views_per_day" in x for x in rows) else "views")
    rank_label = {"multiplier": "outlier × (views/subs)",
                  "views_per_day": "views/day", "views": "views"}[rank_key]

    lines = [f"VIDEO SET ANALYSIS — computed exactly by the app from the {len(rows)} attached videos; "
             "use these numbers as given, do not recompute them."]
    mix = []
    if shorts or longs:
        mix.append(f"{len(shorts)} Shorts / {len(longs)} long-form")
    mix.append(f"{len(channels)} channel(s)" if channels else "channels unknown")
    lines.append("  mix: " + " · ".join(mix)
                 + (" — compare Shorts only with Shorts" if shorts and longs else ""))

    def medline(label, key, fmt):
        m = _med([x.get(key) for x in rows])
        return f"{label} {fmt(m)}" if m is not None else None
    meds = [medline("views", "views", _fmt),
            medline("outlier", "multiplier", lambda v: f"{v:.1f}×"),
            medline("views/day", "views_per_day", _fmt),
            medline("vs own channel avg", "vs_channel_avg", lambda v: f"{v:.1f}×"),
            medline("like rate", "like_rate", lambda v: f"{v:.2f}%"),
            medline("comment rate", "comment_rate", lambda v: f"{v:.3f}%"),
            medline("length", "duration_s", lambda v: f"{int(v) // 60}:{int(v) % 60:02d}"),
            medline("age", "age_days", lambda v: f"{int(v)} days")]
    meds = [m for m in meds if m]
    if meds:
        lines.append("  set medians: " + " | ".join(meds))

    ranked = sorted(rows, key=lambda x: -(x.get(rank_key) or 0))
    med_rank = _med([x.get(rank_key) for x in rows]) or 0
    lines.append(f"  RANKING by {rank_label} (× set median in brackets):")
    lines.append("    # | SOURCE | " + rank_label + " | views | views/day | vs own channel avg | len | title")
    for i, x in enumerate(ranked[:12], 1):
        v = x.get(rank_key) or 0
        rel = f" [{v / med_rank:.1f}× median]" if med_rank else ""
        val = f"{v:.1f}×" if rank_key == "multiplier" else _fmt(v)
        dur = x.get("duration_s")
        dtxt = f"{dur // 60}:{dur % 60:02d}" if dur else "—"
        vpd = _fmt(x["views_per_day"]) if "views_per_day" in x else "—"
        vca = f"{x['vs_channel_avg']:.1f}×" if "vs_channel_avg" in x else "—"
        lines.append(f"    {i} | S{x['n']} | {val}{rel} | {_fmt(x['views'])} | {vpd} | {vca} | {dtxt}"
                     f"{' (Short)' if x.get('is_short') else ''} | {x['title'][:90]}")
    if len(ranked) > 12:
        lines.append(f"    … {len(ranked) - 12} more not listed")

    # Winners vs the rest — only meaningful with a few on each side.
    if len(rows) >= 6:
        k = max(2, len(rows) // 3)
        top, bottom = ranked[:k], ranked[-k:]
        ft = [_title_features(x["title"]) for x in top]
        fb = [_title_features(x["title"]) for x in bottom]
        lines.append(f"  TOP {k} vs BOTTOM {k} by {rank_label} — title & format patterns:")
        for key, label in (("number", "has a number"), ("question", "is a question"),
                           ("brackets", "uses brackets/parentheses"), ("caps", "has an ALL-CAPS word"),
                           ("emoji", "has an emoji"), ("exclaim", "has '!'"),
                           ("first_person", "first person (I/my/we)")):
            a = sum(1 for f in ft if f[key])
            b = sum(1 for f in fb if f[key])
            if a or b:
                lines.append(f"    {label}: top {_pct(a, k)} vs bottom {_pct(b, k)}")
        lines.append(f"    title length (chars, median): top {int(_med([f['chars'] for f in ft]) or 0)}"
                     f" vs bottom {int(_med([f['chars'] for f in fb]) or 0)}")
        dt = _med([x.get("duration_s") for x in top])
        db = _med([x.get("duration_s") for x in bottom])
        if dt and db:
            lines.append(f"    length (median): top {int(dt) // 60}:{int(dt) % 60:02d} vs bottom "
                         f"{int(db) // 60}:{int(db) % 60:02d}")
        at = _med([x.get("age_days") for x in top])
        ab = _med([x.get("age_days") for x in bottom])
        if at and ab:
            lines.append(f"    age (median days): top {int(at)} vs bottom {int(ab)}"
                         + (" — winners are mostly older, so part of the gap is just time"
                            if at > ab * 2 else ""))
        days = {}
        for x in top:
            if x.get("weekday"):
                days[x["weekday"]] = days.get(x["weekday"], 0) + 1
        if days:
            lines.append("    top performers' publish weekdays: "
                         + ", ".join(f"{d} {c}" for d, c in sorted(days.items(), key=lambda kv: -kv[1])))
        lines.append(f"    (patterns from {k} vs {k} videos — directional, not proof; say so when you use them)")
    else:
        lines.append("  (fewer than 6 videos: treat any pattern as a hypothesis, not a finding)")

    if shorts and longs:
        sm = _med([x.get("views_per_day") for x in shorts])
        lm = _med([x.get("views_per_day") for x in longs])
        if sm and lm:
            lines.append(f"  Shorts vs long-form, median views/day: {_fmt(sm)} vs {_fmt(lm)}")
    return "\n".join(lines)
