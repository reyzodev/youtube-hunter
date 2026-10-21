"""app.core.analysis.report_extras - YouTube Hunter.

Pieces the deep (AI) HTML report is built from that are NOT AI output:

  * a tiny bilingual layer (_t / num / lang state) so the same renderer can
    emit a Persian pane AND an English pane in one HTML file,
  * DATA VERDICTS: findings computed in Python straight from the export rows
    (best length, best weekday, breakout videos, title patterns, momentum,
    cadence, format split, engagement) — each turned into a concrete
    "do this next" action. Numbers here never come from a model.
  * the facts digest fed to the model so its action plan cites real numbers,
  * renderers for the action-plan / roadmap / checklist layouts,
  * the batched translation call that produces the second language.
"""

import json
import re
import statistics
from datetime import datetime
from html import escape as html_escape

from app.locales.fa import FA_STRINGS

# ── bilingual render state ───────────────────────────────────────────────
# Rendering is synchronous and single-threaded per report, so a module-level
# "current pane language" is enough. Always set through render_lang().
_STATE = {"lang": "fa"}


class render_lang:
    """`with render_lang("en"):` — render everything inside in that language."""

    def __init__(self, lang):
        self.lang = "en" if lang == "en" else "fa"
        self._prev = "fa"

    def __enter__(self):
        self._prev = _STATE["lang"]
        _STATE["lang"] = self.lang
        return self

    def __exit__(self, *exc):
        _STATE["lang"] = self._prev
        return False


def cur_lang():
    return _STATE["lang"]


def _t(fa, en):
    """Pick the string for the pane being rendered."""
    return en if _STATE["lang"] == "en" else fa


def tk(en_key):
    """An English UI key (the app's own tr() vocabulary) in the pane language —
    independent of the app's CURRENT language, so both panes come out right."""
    if _STATE["lang"] == "en":
        return en_key
    return FA_STRINGS.get(en_key, en_key)


_FA_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def num(n):
    """A number/str with Persian digits in the fa pane, plain in en."""
    s = str(n)
    return s.translate(_FA_DIGITS) if _STATE["lang"] == "fa" else s


def pct_sign():
    return "٪" if _STATE["lang"] == "fa" else "%"


def humanize(n):
    try:
        n = float(n or 0)
    except (TypeError, ValueError):
        return "0"
    for div, suf in ((1e9, "B"), (1e6, "M"), (1e3, "K")):
        if abs(n) >= div:
            v = n / div
            return f"{v:.1f}".rstrip("0").rstrip(".") + suf
    return str(int(n))


WEEKDAYS = {
    "fa": ["دوشنبه", "سه‌شنبه", "چهارشنبه", "پنج‌شنبه", "جمعه", "شنبه", "یکشنبه"],
    "en": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
}


def weekday_name(i):
    return WEEKDAYS[_STATE["lang"]][int(i) % 7]


# ═════════════════════════════════════════════════════════════════════════
#  DATA VERDICTS — computed, never generated
# ═════════════════════════════════════════════════════════════════════════
_DUR_BUCKETS = [
    (0, 61, "< 1 min (Shorts)"),
    (61, 300, "1-5 min"),
    (300, 900, "5-15 min"),
    (900, 1800, "15-30 min"),
    (1800, None, "30+ min"),
]

_NUM_RE = re.compile(r"[0-9\u06F0-\u06F9]")
_Q_RE = re.compile(r"[?؟]")
_BRACKET_RE = re.compile(r"[\(\)\[\]|«»]")
_EMOJI_RE = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF]")


def _median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else 0


def _parse_date(text):
    s = str(text or "").strip()
    if not s:
        return None
    s = s.replace("Z", "+00:00")
    for fmt in (None, "%Y-%m-%d", "%Y/%m/%d", "%d.%m.%Y", "%Y-%m-%d %H:%M:%S"):
        try:
            if fmt is None:
                dt = datetime.fromisoformat(s)
            else:
                dt = datetime.strptime(s[:len(datetime.now().strftime(fmt))], fmt)
            return dt.replace(tzinfo=None)
        except Exception:      # noqa: BLE001
            continue
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        try:
            return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            return None
    return None


def compute_insights(stats, short_max_seconds=60):
    """Language-neutral findings from the export rows. Every value is a real
    number from the file; the renderer only words them."""
    stats = [s for s in stats if (s.get("views") or 0) > 0]
    out = {"n": len(stats)}
    if len(stats) < 3:
        return out
    views = [s["views"] for s in stats]
    med = _median(views) or 1
    out["median"] = med

    # ── length: median views per bucket (median, not mean: one viral video
    #    must not crown a bucket) ──
    dur = []
    for lo, hi, label in _DUR_BUCKETS:
        b = [s["views"] for s in stats if s.get("duration_s")
             and s["duration_s"] >= lo and (hi is None or s["duration_s"] < hi)]
        if len(b) >= 2:
            dur.append({"label": label, "n": len(b), "median": _median(b)})
    if len(dur) >= 2:
        best = max(dur, key=lambda d: d["median"])
        worst = min(dur, key=lambda d: d["median"])
        if worst["median"] > 0 and best is not worst:
            out["duration"] = {"best": best, "worst": worst,
                               "ratio": round(best["median"] / worst["median"], 1)}

    # ── weekday ──
    wd = {}
    dated = []
    for s in stats:
        dt = _parse_date(s.get("published"))
        if dt is not None:
            wd.setdefault(dt.weekday(), []).append(s["views"])
            dated.append((dt, s))
    wd_rows = [{"wd": k, "n": len(v), "median": _median(v)}
               for k, v in wd.items() if len(v) >= 2]
    if len(wd_rows) >= 2:
        best = max(wd_rows, key=lambda d: d["median"])
        worst = min(wd_rows, key=lambda d: d["median"])
        if worst["median"] > 0 and best is not worst:
            out["weekday"] = {"best": best, "worst": worst,
                              "ratio": round(best["median"] / worst["median"], 1)}

    # ── breakouts: the videos to study and remake ──
    brk = []
    for s in stats:
        mult = s["views"] / med
        if mult >= 2:
            brk.append({"title": s.get("title") or "", "url": s.get("url") or "",
                        "views": s["views"], "mult": round(mult, 1),
                        "duration_h": s.get("duration_h") or "",
                        "engagement": s.get("engagement") or 0})
    brk.sort(key=lambda b: b["mult"], reverse=True)
    out["breakouts"] = brk[:8]
    out["hit_rate"] = round(len(brk) * 100 / len(stats))

    # ── title patterns: with vs without, median views ──
    feats = [
        ("number", lambda t: bool(_NUM_RE.search(t))),
        ("question", lambda t: bool(_Q_RE.search(t))),
        ("brackets", lambda t: bool(_BRACKET_RE.search(t))),
        ("emoji", lambda t: bool(_EMOJI_RE.search(t))),
        ("short_title", lambda t: len(t) <= 40),
        ("long_title", lambda t: len(t) >= 70),
    ]
    tp = []
    for key, fn in feats:
        yes = [s["views"] for s in stats if fn(s.get("title") or "")]
        no = [s["views"] for s in stats if not fn(s.get("title") or "")]
        if len(yes) >= 3 and len(no) >= 3:
            my, mn = _median(yes), _median(no)
            if mn > 0:
                tp.append({"key": key, "with_n": len(yes), "with_median": my,
                           "without_median": mn, "lift": round(my / mn, 2)})
    tp.sort(key=lambda r: abs(r["lift"] - 1), reverse=True)
    out["title_patterns"] = tp

    # ── momentum + cadence (needs dates) ──
    if len(dated) >= 8:
        dated.sort(key=lambda p: p[0])
        k = max(3, min(10, len(dated) // 3))
        recent = [s["views"] for _d, s in dated[-k:]]
        before = [s["views"] for _d, s in dated[:-k]]
        if before and _median(before) > 0:
            out["momentum"] = {"recent_n": k, "recent_median": _median(recent),
                               "before_median": _median(before),
                               "ratio": round(_median(recent) / _median(before), 2)}
    if len(dated) >= 4:
        ds = sorted(d for d, _s in dated)
        gaps = [(b - a).days for a, b in zip(ds, ds[1:])]
        gaps = [g for g in gaps if g >= 0]
        if gaps:
            latest = ds[-1]
            last30 = sum(1 for d in ds if (latest - d).days <= 30)
            out["cadence"] = {"median_gap": round(_median(gaps), 1),
                              "last30": last30,
                              "latest": latest.strftime("%Y-%m-%d")}

    # ── format split ──
    shorts = [s["views"] for s in stats if 0 < (s.get("duration_s") or 0) <= short_max_seconds]
    longs = [s["views"] for s in stats if (s.get("duration_s") or 0) > short_max_seconds]
    if len(shorts) >= 3 and len(longs) >= 3:
        out["formats"] = {"shorts_n": len(shorts), "shorts_median": _median(shorts),
                          "long_n": len(longs), "long_median": _median(longs)}

    # ── engagement ──
    like_rates = [s["likes"] * 100 / s["views"] for s in stats if s.get("likes")]
    com_rates = [s["comments"] * 1000 / s["views"] for s in stats if s.get("comments")]
    if like_rates:
        out["engagement"] = {
            "like_rate": round(_median(like_rates), 2),
            "comments_per_1k": round(_median(com_rates), 2) if com_rates else 0.0,
        }
    return out


_TP_NAMES = {
    "number": ("عدد در عنوان", "A number in the title"),
    "question": ("عنوان سؤالی", "Question titles"),
    "brackets": ("پرانتز / براکت در عنوان", "Brackets / parentheses"),
    "emoji": ("ایموجی در عنوان", "Emoji in the title"),
    "short_title": ("عنوان کوتاه (≤۴۰ حرف)", "Short title (≤40 chars)"),
    "long_title": ("عنوان بلند (≥۷۰ حرف)", "Long title (≥70 chars)"),
}


def insights_facts_text(ins):
    """The verdicts as plain English lines for the prompt. The model is told
    these are hard facts it must cite and must not contradict."""
    if not ins or ins.get("n", 0) < 3:
        return ""
    L = [f"- Median views per video: {int(ins['median']):,}."]
    d = ins.get("duration")
    if d:
        L.append(f"- Best length bucket: {d['best']['label']} (median {int(d['best']['median']):,} views, "
                 f"{d['best']['n']} videos); worst: {d['worst']['label']} (median "
                 f"{int(d['worst']['median']):,}). Ratio {d['ratio']}x.")
    w = ins.get("weekday")
    if w:
        names = WEEKDAYS["en"]
        L.append(f"- Best publish weekday: {names[w['best']['wd']]} (median {int(w['best']['median']):,}); "
                 f"worst: {names[w['worst']['wd']]} (median {int(w['worst']['median']):,}).")
    if ins.get("breakouts"):
        top = "; ".join(f"\"{b['title'][:70]}\" {b['mult']}x median" for b in ins["breakouts"][:5])
        L.append(f"- Breakout videos (>=2x median), {ins.get('hit_rate', 0)}% of uploads: {top}.")
    for r in (ins.get("title_patterns") or [])[:4]:
        L.append(f"- Title pattern '{_TP_NAMES[r['key']][1]}': {r['lift']}x the median views of titles "
                 f"without it ({r['with_n']} videos).")
    m = ins.get("momentum")
    if m:
        L.append(f"- Momentum: last {m['recent_n']} uploads median {int(m['recent_median']):,} vs "
                 f"earlier {int(m['before_median']):,} ({m['ratio']}x).")
    c = ins.get("cadence")
    if c:
        L.append(f"- Cadence: median {c['median_gap']} days between uploads; {c['last30']} uploads "
                 f"in the 30 days before the latest one.")
    f = ins.get("formats")
    if f:
        L.append(f"- Shorts: {f['shorts_n']} videos, median {int(f['shorts_median']):,}; long-form: "
                 f"{f['long_n']} videos, median {int(f['long_median']):,} (different discovery "
                 f"surfaces, not directly comparable).")
    e = ins.get("engagement")
    if e:
        L.append(f"- Median like rate {e['like_rate']}%; median {e['comments_per_1k']} comments per 1,000 views.")
    return "HARD FACTS computed in code from the export (cite them, never contradict them):\n" + "\n".join(L)


def _verdict_card(icon, tone, finding, action, evidence=""):
    e = html_escape
    ev = f'<div class="vd-ev">{e(evidence)}</div>' if evidence else ""
    return (f'<div class="vd vd-{tone}"><div class="vd-ic">{icon}</div><div class="vd-b">'
            f'<div class="vd-f">{e(finding)}</div>'
            f'<div class="vd-a"><span class="vd-tag">{e(_t("کار بعدی", "Do next"))}</span>{e(action)}</div>'
            f'{ev}</div></div>')


def render_insights(ins):
    """The "data verdicts" block: finding → action cards, the breakout table
    and the title-pattern lift bars. "" when the export is too thin."""
    if not ins or ins.get("n", 0) < 3:
        return ""
    e = html_escape
    cards = []
    d = ins.get("duration")
    if d:
        b, w = tk(d["best"]["label"]), tk(d["worst"]["label"])
        cards.append(_verdict_card(
            "⏱", "good",
            _t(f"ویدیوهای {b} با میانه‌ی {num(humanize(d['best']['median']))} بازدید، "
               f"{num(d['ratio'])} برابر ویدیوهای {w} دیده می‌شوند.",
               f"{b} videos get a median {humanize(d['best']['median'])} views — "
               f"{d['ratio']}× your {w} videos."),
            _t(f"بیشترِ ویدیوهای بعدی را در بازه‌ی {b} بسازید و {w} را فقط برای تست نگه دارید.",
               f"Make most of your next uploads {b} long; keep {w} for experiments only."),
            _t(f"بر پایه‌ی {num(d['best']['n'])} و {num(d['worst']['n'])} ویدیو",
               f"Based on {d['best']['n']} vs {d['worst']['n']} videos")))
    w = ins.get("weekday")
    if w:
        bn, wn = weekday_name(w["best"]["wd"]), weekday_name(w["worst"]["wd"])
        cards.append(_verdict_card(
            "📅", "good",
            _t(f"ویدیوهای منتشرشده در {bn} میانه‌ی {num(humanize(w['best']['median']))} بازدید دارند؛ "
               f"{num(w['ratio'])} برابر {wn}.",
               f"Videos published on {bn} reach a median {humanize(w['best']['median'])} views — "
               f"{w['ratio']}× {wn}."),
            _t(f"ویدیوی اصلی هفته را {bn} منتشر کنید و {wn} را خالی بگذارید یا برای شورت استفاده کنید.",
               f"Publish your main video of the week on {bn}; skip {wn} or use it for a Short."),
            _t("روز انتشار یک عامل است نه علت — چند هفته تست کنید.",
               "Weekday is a signal, not a cause — test it for a few weeks.")))
    m = ins.get("momentum")
    if m:
        up = m["ratio"] >= 1.1
        down = m["ratio"] <= 0.9
        cards.append(_verdict_card(
            "📈" if up else ("📉" if down else "➖"), "good" if up else ("bad" if down else "mid"),
            _t(f"{num(m['recent_n'])} ویدیوی آخر میانه‌ی {num(humanize(m['recent_median']))} بازدید دارند "
               f"در برابر {num(humanize(m['before_median']))} قبل از آن ({num(m['ratio'])}×).",
               f"Your last {m['recent_n']} uploads have a median {humanize(m['recent_median'])} views vs "
               f"{humanize(m['before_median'])} before ({m['ratio']}×)."),
            (_t("فرمت فعلی جواب می‌دهد؛ همان ساختار را حفظ کنید و فقط یک متغیر را در هر ویدیو تغییر دهید.",
                "What you're doing now works — keep the format and change only one variable per video.")
             if up else
             _t("ببینید چه چیزی تغییر کرده (موضوع، طول، تامبنیل، روز انتشار) و به الگوی ویدیوهای قوی‌تر قبلی برگردید.",
                "Find what changed (topic, length, thumbnail, publish day) and go back to the pattern of your stronger earlier videos.")
             if down else
             _t("روند ثابت است؛ برای رشد، یکی از ایده‌های آوتلایر پایین را بازسازی کنید.",
                "Flat trend — to break out, remake one of the breakout videos below."))))
    c = ins.get("cadence")
    if c:
        g = c["median_gap"]
        cards.append(_verdict_card(
            "🗓", "mid" if g > 10 else "good",
            _t(f"به‌طور معمول هر {num(g)} روز یک ویدیو منتشر می‌کنید ({num(c['last30'])} ویدیو در ۳۰ روز آخر).",
               f"You publish roughly every {g} days ({c['last30']} uploads in the last 30 days)."),
            (_t("یک برنامه‌ی ثابت بگذارید: حداقل هفته‌ای یک ویدیو، همان روز و همان ساعت.",
                "Lock a fixed schedule: at least one video a week, same day, same hour.")
             if g > 10 else
             _t("این ریتم را نگه دارید و ثابتش کنید (روز و ساعت مشخص)؛ ثبات از تعداد مهم‌تر است.",
                "Keep this pace and make it predictable (fixed day and hour) — consistency beats volume."))))
    f = ins.get("formats")
    if f:
        cards.append(_verdict_card(
            "🎬", "mid",
            _t(f"شورت‌ها: {num(f['shorts_n'])} ویدیو، میانه‌ی {num(humanize(f['shorts_median']))} — "
               f"بلندها: {num(f['long_n'])} ویدیو، میانه‌ی {num(humanize(f['long_median']))}.",
               f"Shorts: {f['shorts_n']} videos, median {humanize(f['shorts_median'])} — "
               f"Long-form: {f['long_n']} videos, median {humanize(f['long_median'])}."),
            _t("از شورت برای جذب مخاطب جدید و از ویدیوی بلند برای درآمد و وفاداری استفاده کنید؛ هر شورت را به یک ویدیوی بلند وصل کنید.",
               "Use Shorts to reach new viewers and long-form for watch time and revenue — link every Short to a related long video."),
            _t("بازدید شورت و ویدیوی بلند مستقیماً قابل مقایسه نیستند.",
               "Shorts and long-form views aren't directly comparable.")))
    eg = ins.get("engagement")
    if eg:
        low_c = eg["comments_per_1k"] < 2
        cards.append(_verdict_card(
            "💬", "bad" if low_c else "good",
            _t(f"میانه‌ی نرخ لایک {num(eg['like_rate'])}{pct_sign()} و {num(eg['comments_per_1k'])} کامنت در هر هزار بازدید.",
               f"Median like rate {eg['like_rate']}% and {eg['comments_per_1k']} comments per 1,000 views."),
            (_t("در ۳۰ ثانیه‌ی اول یک سؤال مشخص (نه «نظرتون چیه؟») بپرسید و جوابش را در کامنت پین‌شده بخواهید.",
                "Ask one specific question in the first 30 seconds (not \"what do you think?\") and ask for the answer in a pinned comment.")
             if low_c else
             _t("مخاطب درگیر است؛ از کامنت‌ها ایده‌ی ویدیوی بعدی بگیرید و در ویدیو به آن‌ها اشاره کنید.",
                "Your audience engages — mine the comments for next video ideas and shout them out on screen."))))
    tp = [r for r in (ins.get("title_patterns") or []) if r["lift"] >= 1.25 or r["lift"] <= 0.8]
    if tp:
        r = tp[0]
        name = _t(*_TP_NAMES[r["key"]])
        good = r["lift"] >= 1.25
        cards.append(_verdict_card(
            "🔤", "good" if good else "bad",
            _t(f"«{name}»: میانه‌ی بازدید {num(r['lift'])} برابر عنوان‌های بدون آن.",
               f"“{name}”: {r['lift']}× the median views of titles without it."),
            (_t(f"در عنوان‌های بعدی از «{name}» استفاده کنید.", f"Use “{name}” in your next titles.")
             if good else
             _t(f"از «{name}» در عنوان فاصله بگیرید.", f"Move away from “{name}” in titles.")),
            _t(f"{num(r['with_n'])} ویدیو این الگو را داشتند", f"{r['with_n']} videos had this pattern")))

    parts = []
    if cards:
        parts.append(f'<div class="vds">{"".join(cards)}</div>')

    if ins.get("breakouts"):
        rows = "".join(
            '<tr><td><a href="{u}" target="_blank" rel="noopener">{t}</a></td>'
            '<td class="num">{v}</td><td class="num"><span class="mult">{m}×</span></td>'
            '<td class="num">{d}</td></tr>'.format(
                u=e(b["url"] or "#"), t=e(b["title"]), v=num(humanize(b["views"])),
                m=num(b["mult"]), d=e(b["duration_h"]))
            for b in ins["breakouts"])
        parts.append(
            '<div class="panel" style="margin-top:14px"><div class="ptitle">'
            + e(_t("ویدیوهای آوتلایر شما — این‌ها را مطالعه و بازسازی کنید",
                   "Your breakout videos — study these and remake them"))
            + '</div><div class="tblwrap"><table class="tbl"><tr>'
            + "".join(f'<th>{e(h)}</th>' for h in (
                _t("ویدیو", "Video"), _t("بازدید", "Views"),
                _t("نسبت به میانه", "vs median"), _t("طول", "Length")))
            + f'</tr>{rows}</table></div><div class="cap">'
            + e(_t(f"{num(ins.get('hit_rate', 0))}{pct_sign()} از ویدیوها حداقل ۲ برابر میانه بازدید گرفته‌اند. "
                   "برای هرکدام بپرسید: موضوع، عنوان و تامبنیل چه چیزی را وعده دادند که بقیه ندادند؟",
                   f"{ins.get('hit_rate', 0)}% of your uploads got at least 2× the median. For each one ask: "
                   "what did the topic, title and thumbnail promise that the others didn't?"))
            + '</div></div>')

    tps = ins.get("title_patterns") or []
    if tps:
        mx = max(max(r["lift"] for r in tps), 1.0)
        rows = "".join(
            f'<div class="brow"><div class="blab">{e(_t(*_TP_NAMES[r["key"]]))}</div>'
            f'<div class="btrack"><div class="bfill{" bneg" if r["lift"] < 1 else ""}" '
            f'style="width:{max(6, round(r["lift"] / mx * 100, 1))}%"></div></div>'
            f'<div class="bval">{num(r["lift"])}×</div></div>'
            for r in tps)
        parts.append(
            '<div class="panel" style="margin-top:14px"><div class="ptitle">'
            + e(_t("الگوهای عنوان — تأثیر واقعی روی بازدید", "Title patterns — real effect on views"))
            + f'</div><div class="chart">{rows}</div><div class="cap">'
            + e(_t("بالای ۱× یعنی عنوان‌های دارای این الگو میانه‌ی بازدید بیشتری دارند. همبستگی است، نه علیت.",
                   "Above 1× means titles with this pattern get more median views. Correlation, not causation."))
            + '</div></div>')
    return "".join(parts)


# ═════════════════════════════════════════════════════════════════════════
#  NEW AI LAYOUTS: action_plan, roadmap, checklist
# ═════════════════════════════════════════════════════════════════════════
def clean_actions(v):
    out = []
    for it in (v or []):
        if not isinstance(it, dict):
            continue
        how = it.get("how") or []
        if isinstance(how, str):
            how = [h.strip() for h in re.split(r"\n+|(?<=\.)\s+(?=\d)", how) if h.strip()]
        a = {
            "priority": str(it.get("priority") or "").strip().lower(),
            "task": str(it.get("task") or "").strip(),
            "why": str(it.get("why") or "").strip(),
            "how": [str(h).strip() for h in how if str(h).strip()][:7],
            "metric": str(it.get("metric") or "").strip(),
            "timeframe": str(it.get("timeframe") or "").strip(),
        }
        if a["priority"] not in ("high", "medium", "low"):
            a["priority"] = "medium"
        if a["task"]:
            out.append(a)
    return out[:10]


def clean_weeks(v):
    out = []
    for it in (v or []):
        if not isinstance(it, dict):
            continue
        tasks = [str(x).strip() for x in (it.get("tasks") or []) if str(x).strip()]
        w = {"label": str(it.get("label") or "").strip(),
             "focus": str(it.get("focus") or "").strip(), "tasks": tasks[:7]}
        if w["focus"] or w["tasks"]:
            out.append(w)
    return out[:6]


def _check(key, text_html):
    return (f'<label class="ck"><input type="checkbox" data-k="{html_escape(key)}">'
            f'<span class="ck-box"></span><span class="ck-t">{text_html}</span></label>')


def render_actions(sec, sidx):
    e = html_escape
    pr_lbl = {"high": _t("اولویت بالا", "High priority"),
              "medium": _t("اولویت متوسط", "Medium priority"),
              "low": _t("اولویت پایین", "Low priority")}
    cards = []
    for i, a in enumerate(sec.get("actions") or [], 1):
        how = ""
        if a["how"]:
            how = (f'<div class="ap-h">{e(_t("چطور انجامش بدهید", "How to do it"))}</div><ol class="ap-steps">'
                   + "".join(f'<li>{e(h)}</li>' for h in a["how"]) + '</ol>')
        meta = ""
        if a["metric"]:
            meta += f'<span class="ap-chip">📏 {e(_t("معیار موفقیت", "Measure"))}: {e(a["metric"])}</span>'
        if a["timeframe"]:
            meta += f'<span class="ap-chip">⏳ {e(a["timeframe"])}</span>'
        why = (f'<div class="ap-why"><b>{e(_t("چرا", "Why"))}:</b> {e(a["why"])}</div>' if a["why"] else "")
        cards.append(
            f'<div class="ap ap-{a["priority"]}"><div class="ap-top">'
            f'<span class="ap-n">{num(i)}</span><span class="ap-pr">{e(pr_lbl[a["priority"]])}</span></div>'
            + _check(f"a{sidx}-{i}", f'<b>{e(a["task"])}</b>')
            + why + how + (f'<div class="ap-meta">{meta}</div>' if meta else "") + '</div>')
    return f'<div class="aps">{"".join(cards)}</div>' if cards else ""


def render_roadmap(sec, sidx):
    e = html_escape
    cols = []
    for wi, w in enumerate(sec.get("weeks") or [], 1):
        label = w["label"] or _t(f"هفته‌ی {num(wi)}", f"Week {wi}")
        tasks = "".join(_check(f"r{sidx}-{wi}-{ti}", e(t)) for ti, t in enumerate(w["tasks"], 1))
        cols.append(f'<div class="wk"><div class="wk-l">{e(label)}</div>'
                    f'<div class="wk-f">{e(w["focus"])}</div><div class="wk-t">{tasks}</div></div>')
    return f'<div class="wks">{"".join(cols)}</div>' if cols else ""


def render_checklist(sec, sidx):
    items = sec.get("checklist") or []
    if not items:
        return ""
    return ('<div class="cl">' + "".join(
        _check(f"c{sidx}-{i}", html_escape(t)) for i, t in enumerate(items, 1))
        + '</div><div class="cap">' + html_escape(_t(
            "تیک‌ها در همین مرورگر ذخیره می‌شوند.", "Ticks are saved in this browser.")) + '</div>')


# ═════════════════════════════════════════════════════════════════════════
#  PROMPT ADDITIONS
# ═════════════════════════════════════════════════════════════════════════
LANG_NAME = {"fa": "Persian (Farsi)", "en": "English"}

SCHEMA_EXTRA_FIELDS = (
    '      "actions": [{"priority": "high|medium|low", "task": "one concrete thing to do", '
    '"why": "the data point it rests on (cite a number)", "how": ["step 1", "step 2", "step 3"], '
    '"metric": "what number to watch to know it worked", "timeframe": "e.g. this week / next 3 videos"}],\n'
    '      "weeks": [{"label": "Week 1", "focus": "the theme of the week", "tasks": ["...", "..."]}],\n'
    '      "checklist": ["...", "..."],\n'
)

ACTIONABLE_RULES = (
    "\n\nMAKE IT ACTIONABLE — this report is read by a creator who wants to know exactly what to do "
    "tomorrow morning. Every recommendation anywhere in the report must say WHAT to do, HOW to do it "
    "(concrete steps, examples, wording), WHY (cite a specific number, video or pattern from the data) "
    "and HOW TO MEASURE that it worked. Never write generic advice like \"post consistently\" or "
    "\"make better thumbnails\" without the specific how for THIS channel.\n"
    "Required extra sections (in addition to the rules below):\n"
    "  * Right after the executive summary: one section with layout \"action_plan\" titled like "
    "\"Your action plan\" — 5 to 8 \"actions\" ordered by impact, each with priority, task, why "
    "(cite the hard facts), 3-5 \"how\" steps, a metric and a timeframe.\n"
    "  * One section with layout \"roadmap\": a 30-day plan as 4 \"weeks\", each with a focus and 3-5 "
    "concrete tasks (which video to make, what to test, what to measure).\n"
    "  * One section with layout \"checklist\": an 8-12 item pre-publish checklist specific to this "
    "niche (title, thumbnail, first 30 seconds, description, end screen, pinned comment…).\n"
    "These new layouts use only the \"actions\", \"weeks\" and \"checklist\" fields respectively."
)


def actionable_block(facts_text):
    return (f"\n\n{facts_text}" if facts_text else "") + ACTIONABLE_RULES


# ═════════════════════════════════════════════════════════════════════════
#  TRANSLATION (second language pane)
# ═════════════════════════════════════════════════════════════════════════
_KEEP_KEYS = {"layout", "thumbnail_prompt", "viral_pct", "priority", "time",
              "icon", "callout_icon", "hero_emoji", "theme_style",
              "theme_primary", "theme_secondary"}


def _translate_prompt(payload, target):
    return (
        f"Translate every human-readable string value in the JSON below into natural, fluent "
        f"{LANG_NAME[target]} written for a YouTube creator. Keep the JSON structure, keys, array "
        f"lengths and order EXACTLY the same. Do NOT translate these keys' values: "
        f"{', '.join(sorted(_KEEP_KEYS))}. Keep numbers, video titles in quotes, names, hashtags and "
        f"timestamps as they are (a quoted original video title may stay in its original language). "
        f"Respond ONLY with the translated JSON object, no markdown fences, no commentary.\n\n"
        + json.dumps(payload, ensure_ascii=False)
    )


def _strip_for_translation(sec):
    """Drop empty fields so the translation call carries only real text."""
    out = {}
    for k, v in sec.items():
        if v in ("", None, [], {}):
            continue
        out[k] = v
    out.setdefault("layout", sec.get("layout") or "lead_only")
    out.setdefault("title", sec.get("title") or "")
    return out


def translate_report(ai_client, ai, target, parse_fn, progress_cb=None, batch=4):
    """`ai` (parsed report) translated into `target` ("fa"/"en").

    Batched, a few sections per call, so a long report never hits the output
    ceiling in one reply. A batch that fails or comes back with a different
    number of sections keeps its original text: one bad batch costs that
    batch, never the report. Returns None if nothing at all could be
    translated."""
    sections = ai.get("sections") or []
    hero_keys = ("topic", "hero_kicker", "hero_title", "hero_subtitle")
    out = dict(ai)
    out["_lang"] = target
    new_secs = list(sections)
    any_ok = False
    chunks = [sections[i:i + batch] for i in range(0, len(sections), batch)] or [[]]
    for ci, chunk in enumerate(chunks):
        payload = {"sections": [_strip_for_translation(s) for s in chunk]}
        if ci == 0:
            for k in hero_keys:
                if ai.get(k):
                    payload[k] = ai[k]
        if progress_cb:
            progress_cb(f"{ci + 1}/{len(chunks)}")
        try:
            raw = ai_client.generate(_translate_prompt(payload, target),
                                     timeout=240, max_output_tokens=8000)
            parsed = parse_fn(raw)
        except Exception:      # noqa: BLE001 — that batch keeps its original text
            continue
        got = parsed.get("sections") or []
        if chunk and len(got) == len(chunk):
            for j, s in enumerate(got):
                # Non-text fields are taken from the original — the model must
                # never be able to change a score or a layout in translation.
                orig = chunk[j]
                s["layout"] = orig.get("layout")
                s["viral_pct"] = orig.get("viral_pct")
                s["thumbnail_prompt"] = orig.get("thumbnail_prompt", "")
                for oi, idea in enumerate(s.get("ideas") or []):
                    if oi < len(orig.get("ideas") or []):
                        idea["viral_pct"] = orig["ideas"][oi].get("viral_pct")
                        idea["thumbnail_prompt"] = orig["ideas"][oi].get("thumbnail_prompt", "")
                new_secs[ci * batch + j] = s
            any_ok = True
        if ci == 0:
            for k in hero_keys:
                if parsed.get(k) and ai.get(k):
                    out[k] = parsed[k]
                    any_ok = True
    out["sections"] = new_secs
    return out if any_ok else None
