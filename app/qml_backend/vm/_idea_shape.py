"""app.qml_backend.vm._idea_shape - YouTube Hunter (QML).

Shared flattener that turns ONE stored Content Lab blueprint (the deeply-nested
schema written by app.core.ai.content_lab) into the flat dict the QML blueprint
pane and rail cards bind to.

Extracted so the AI Ideas page (IdeasVM) and the Content Lab page (ContentLabVM)
render byte-for-byte identical blueprints — the two pages share BlueprintPane.qml
and IdeaRailCard.qml, so their data shape must never drift.
"""

import base64
from urllib.parse import quote_plus

from app.core.ai.content_lab import CONTENT_LAB_SCHEMA_VERSION
from app.core.net import extract_video_id
from app.core.utils import humanize_count
from app.i18n import tr


def _difficulty_label(token):
    """The model returns difficulty as one of three fixed English tokens (so it
    can be compared and coloured); the label the user reads is translated here
    rather than in QML, which has no access to the token list.

    A function, not a module-level dict: i18n.LANG is set from config AFTER this
    module is imported, so a dict built at import time would freeze every label
    in English on a Persian install.
    """
    return {"Easy": tr("Easy"),
            "Medium": tr("Medium"),
            "Hard": tr("Hard")}.get(token or "Medium", tr("Medium"))


def as_list(v):
    """Coerce a field that may be a list (schema v2) or a bare string (v1) to a
    list.

    Not the same as `v or []`: a non-empty string is truthy, so that idiom would
    hand the string straight to a QML Repeater, which iterates it character by
    character. A 55-character hook line then renders as 55 one-letter "options".
    """
    if isinstance(v, (list, tuple)):
        return [str(x) for x in v if str(x).strip()]
    s = str(v).strip() if v is not None else ""
    return [s] if s else []


def as_list_rows(value, fields):
    """A list of {field: text} rows, cleaned to exactly `fields` keys.

    Used by the working-creator pack (risks, series_next). A row that is not an
    object is skipped rather than coerced — a half-populated row would render as
    a box with a heading and no body, which reads as a bug.
    """
    out = []
    for row in (value if isinstance(value, list) else [])[:6]:
        if not isinstance(row, dict):
            continue
        cleaned = {f: str(row.get(f, "") or "").strip() for f in fields}
        if any(cleaned.values()):
            out.append(cleaned)
    return out


def _publish_plan(value):
    """publish_plan as {day, time, why, first_hour[]} — {} when empty.

    A model sometimes answers this object-shaped field with a single string
    ("Friday 6pm"), which is still a usable answer: it is folded into `day`
    rather than discarded, because a plan the creator cannot see is a plan they
    cannot follow.
    """
    if isinstance(value, str):
        value = {"day": value.strip()} if value.strip() else {}
    value = value if isinstance(value, dict) else {}
    first_hour = as_list(value.get("first_hour"))[:6]
    plan = {
        "day": str(value.get("day") or "").strip(),
        "time": str(value.get("time") or "").strip(),
        "why": str(value.get("why") or "").strip(),
        "first_hour": first_hour,
    }
    return plan if any(plan.values()) else {}


def _num(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0


def _ref_rows(d):
    """The real reference rows a blueprint was built from, display-ready.
    Only rows with something to show are kept; `url` may be "" for an export
    that carried no video id (the UI then renders the row unlinked)."""
    out = []
    for r in (d.get("refs") if isinstance(d.get("refs"), list) else [])[:24]:
        if not isinstance(r, dict) or not str(r.get("title") or "").strip():
            continue
        views = _num(r.get("views"))
        mult = r.get("multiplier")
        out.append({
            "ref": str(r.get("ref") or ""),
            "title": str(r.get("title") or ""),
            "url": str(r.get("url") or ""),
            "channel": str(r.get("channel") or ""),
            "views": humanize_count(views) if views else "",
            "mult": (f"{mult}×" if isinstance(mult, (int, float)) and mult else ""),
            "isCsv": str(r.get("ref") or "").upper().startswith("C"),
            "source": str(r.get("source") or ""),
        })
    return out


def _pulse(d):
    """data_pulse → a flat list of {label, value, sub} tiles + per-CSV cards.
    Everything here was computed in Python from the inputs (see
    content_lab._data_pulse) — the model never touched these numbers."""
    p = d.get("data_pulse") if isinstance(d.get("data_pulse"), dict) else {}
    tiles = []
    v = p.get("videos") if isinstance(p.get("videos"), dict) else {}
    if v:
        tiles.append({"label": tr("Reference videos"), "value": str(_num(v.get("count"))),
                      "sub": tr("{n} Shorts").format(n=_num(v.get("shorts")))})
        tiles.append({"label": tr("Median views"), "value": humanize_count(_num(v.get("median_views"))),
                      "sub": tr("across the picks")})
        tiles.append({"label": tr("Top performer"), "value": humanize_count(_num(v.get("top_views"))),
                      "sub": str(v.get("top_title") or "")[:60], "url": str(v.get("top_url") or "")})
        if _num(v.get("median_duration_s")):
            tiles.append({"label": tr("Typical length"), "value": mmss(_num(v.get("median_duration_s"))),
                          "sub": tr("median of the picks")})
    csvs = []
    for c in (p.get("csv") if isinstance(p.get("csv"), list) else [])[:6]:
        if not isinstance(c, dict):
            continue
        csvs.append({
            "name": str(c.get("name") or ""),
            "videos": str(_num(c.get("videos"))),
            "median": humanize_count(_num(c.get("median_views"))),
            "top": humanize_count(_num(c.get("top_views"))),
            "outliers": str(_num(c.get("outliers"))),
            "engagement": f'{c.get("median_engagement", 0)}%',
            "shortsShare": f'{int(round(float(c.get("shorts_share", 0) or 0) * 100))}%',
            "bestLength": tr(str(c.get("best_length") or "")) if c.get("best_length") else "—",
            "bestLengthMedian": humanize_count(_num(c.get("best_length_median"))),
            "bestDay": tr(str(c.get("best_weekday") or "")) if c.get("best_weekday") else "—",
            "bestDayMedian": humanize_count(_num(c.get("best_weekday_median"))),
        })
    return {"tiles": tiles, "csv": csvs}


# ── timeline (v12 blueprint) ──
# The redesigned pane lays the script, the re-hooks and the pacing on ONE time
# axis (the "edit bay") and plays the script back in a 9:16 preview. Both need
# real seconds, and the model writes times as free text ("0:00–0:03",
# "۰:۰۳", "4:00-7:30", "12s"), so they are parsed once here rather than in a
# dozen QML bindings.
_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def _clock_tokens(text):
    """Every time token in `text`, in seconds, in reading order."""
    import re
    s = str(text or "").translate(_DIGITS)
    out = []
    for m in re.finditer(r"(\d+):(\d{1,2})(?::(\d{1,2}))?|(\d+(?:\.\d+)?)\s*s\b", s):
        if m.group(4) is not None:
            out.append(float(m.group(4)))
        elif m.group(3) is not None:
            out.append(int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3)))
        else:
            out.append(int(m.group(1)) * 60 + int(m.group(2)))
    return out


def _timed_script(script, total_hint):
    """The script rows with startSec / endSec added, plus the axis length and
    whether the times were real (parsed) or spread by word count.

    A row without a parsable end borrows the next row's start; if NOTHING
    parses, the beats are spread over the total by how many words each has
    (a read-out is roughly proportional to its length), and `ok` is False so
    the pane can say the timing is approximate."""
    rows = [dict(r) for r in script if isinstance(r, dict)]
    spans = []
    for r in rows:
        t = _clock_tokens(r.get("time"))
        spans.append((t[0] if t else None, t[1] if len(t) > 1 else None))
    parsed = sum(1 for a, _ in spans if a is not None)
    ok = bool(rows) and parsed == len(rows)
    if ok:
        for i, r in enumerate(rows):
            a, b = spans[i]
            if b is None or b <= a:
                nxt = spans[i + 1][0] if i + 1 < len(spans) else None
                b = nxt if (nxt is not None and nxt > a) else a + 3
            r["startSec"], r["endSec"] = float(a), float(b)
        total = max(float(total_hint or 0), rows[-1]["endSec"] if rows else 0.0)
    else:
        total = float(total_hint or 0) or 60.0
        weights = [max(1, len(str(r.get("line") or "").split())) for r in rows]
        acc, w = 0.0, float(sum(weights) or 1)
        for r, k in zip(rows, weights):
            r["startSec"] = acc
            acc += total * k / w
            r["endSec"] = acc
    return rows, total, ok


def mmss(seconds):
    """Seconds as m:ss (or h:mm:ss past an hour) for the retention timeline."""
    try:
        total = max(0, int(round(float(seconds))))
    except (TypeError, ValueError):
        return "0:00"
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


_SCORE_LABELS = {
    "hook": "Hook", "retention": "Retention", "packaging": "Packaging",
    "novelty": "Novelty", "feasibility": "Feasibility",
}
_TITLE_MAX = 70


def _rows(value, fields, n=10):
    out = []
    for row in (value if isinstance(value, list) else [])[:n]:
        if isinstance(row, dict):
            cleaned = {f: str(row.get(f, "") or "").strip() for f in fields}
            if any(cleaned.values()):
                out.append(cleaned)
    return out


def _v5(d):
    """The v5 pack, flattened. Every block is {} / [] when the record predates
    it, and the pane hides a section whose data is empty."""
    parts = []
    for p in (d.get("score_breakdown") if isinstance(d.get("score_breakdown"), list) else []):
        if not isinstance(p, dict) or p.get("key") not in _SCORE_LABELS:
            continue
        parts.append({"key": p["key"], "label": tr(_SCORE_LABELS[p["key"]]),
                      "points": max(0, min(20, _num(p.get("points")))),
                      "why": str(p.get("why") or "")})
    cp = d.get("core_promise") if isinstance(d.get("core_promise"), dict) else {}
    promise = {k: str(cp.get(k) or "").strip()
               for k in ("promise", "payoff", "payoff_time", "differentiator")}
    sg = d.get("style_guide") if isinstance(d.get("style_guide"), dict) else {}
    style = {
        "look": str(sg.get("look") or ""),
        "palette": as_list(sg.get("palette"))[:5],
        "typography": str(sg.get("typography") or ""),
        "captions": str(sg.get("captions") or ""),
        "music": str(sg.get("music") or ""),
        "sfx": _rows(sg.get("sfx"), ("time", "cue"), 6),
    }
    pp = d.get("production_plan") if isinstance(d.get("production_plan"), dict) else {}
    prod = {
        "prep": str(pp.get("prep") or ""), "shoot": str(pp.get("shoot") or ""),
        "edit": str(pp.get("edit") or ""), "gear": as_list(pp.get("gear")),
        "props": as_list(pp.get("props")), "location": str(pp.get("location") or ""),
        "checklist": as_list(pp.get("checklist")),
    }
    ab = d.get("ab_plan") if isinstance(d.get("ab_plan"), dict) else {}
    abp = {k: str(ab.get(k) or "").strip()
           for k in ("thumbnail_first", "title_first", "swap_rule", "watch")}
    rg = d.get("rights") if isinstance(d.get("rights"), dict) else {}
    rights = {"risk": str(rg.get("risk") or ""),
              "riskLabel": {"Low": tr("Low risk"), "Medium": tr("Medium risk"),
                            "High": tr("High risk")}.get(str(rg.get("risk") or ""), ""),
              "notes": str(rg.get("notes") or ""),
              "safeMoves": as_list(rg.get("safe_moves"))}
    on_screen = _rows(d.get("on_screen_text"), ("time", "text", "style"), 10)
    for r in on_screen:
        t = _clock_tokens(r.get("time"))
        r["atSec"] = float(t[0]) if t else -1.0
    for r in style["sfx"]:
        t = _clock_tokens(r.get("time"))
        r["atSec"] = float(t[0]) if t else -1.0
    playbook = _rows(d.get("playbook"), ("signal", "action"), 5)
    return {
        "scoreParts": parts,
        "hasScoreParts": len(parts) == len(_SCORE_LABELS),
        "promise": {"promise": promise["promise"], "payoff": promise["payoff"],
                    "payoffTime": promise["payoff_time"],
                    "differentiator": promise["differentiator"]},
        "hasPromise": bool(promise["promise"] or promise["payoff"]),
        "styleGuide": style,
        "hasStyle": bool(style["look"] or style["palette"] or style["typography"]
                         or style["captions"] or style["music"] or style["sfx"]),
        "onScreenText": on_screen,
        "hasOnScreen": bool(on_screen),
        "productionPlan": prod,
        "hasProduction": bool(prod["prep"] or prod["shoot"] or prod["edit"] or prod["gear"]
                              or prod["checklist"] or prod["location"]),
        "abPlan": {"thumbnailFirst": abp["thumbnail_first"], "titleFirst": abp["title_first"],
                   "swapRule": abp["swap_rule"], "watch": abp["watch"]},
        "hasAbPlan": any(abp.values()),
        "playbook": playbook,
        "hasPlaybook": bool(playbook),
        "rights": rights,
        "hasRights": bool(rights["risk"] or rights["notes"] or rights["safeMoves"]),
        "communityPost": str(d.get("community_post") or "").strip(),
    }


_SHELF_LABELS = {"Evergreen": "Evergreen", "Seasonal": "Seasonal", "Trending": "Trending"}
_WHEN_ORDER = ("1 hour", "24 hours", "7 days")


def _v6(d):
    """The v6 "after you hit publish" pack, flattened. Same rule as _v5: every
    block is empty on an older record and the pane hides an empty section."""
    wn = d.get("why_now")
    if isinstance(wn, str):
        wn = {"why": wn}
    wn = wn if isinstance(wn, dict) else {}
    shelf = str(wn.get("shelf_life") or "").strip().title()
    why_now = {
        "shelfLife": shelf if shelf in _SHELF_LABELS else "",
        "shelfLabel": tr(_SHELF_LABELS[shelf]) if shelf in _SHELF_LABELS else "",
        "window": str(wn.get("window") or "").strip(),
        "why": str(wn.get("why") or "").strip(),
    }
    dc = d.get("discovery") if isinstance(d.get("discovery"), dict) else {}
    discovery = {
        "searchQueries": as_list(dc.get("search_queries"))[:6],
        "suggestedBeside": as_list(dc.get("suggested_beside"))[:3],
        "browseTrigger": str(dc.get("browse_trigger") or "").strip(),
    }
    dl = d.get("delivery") if isinstance(d.get("delivery"), dict) else {}
    delivery = {
        "tone": str(dl.get("tone") or "").strip(),
        "pace": str(dl.get("pace") or "").strip(),
        "energy": str(dl.get("energy") or "").strip(),
        "emphasis": as_list(dl.get("emphasis"))[:6],
        "avoid": as_list(dl.get("avoid"))[:4],
    }
    es = d.get("end_screen") if isinstance(d.get("end_screen"), dict) else {}
    cards = _rows(es.get("cards"), ("time", "target"), 4)
    for r in cards:
        t = _clock_tokens(r.get("time"))
        r["atSec"] = float(t[0]) if t else -1.0
    end_screen = {"cards": cards,
                  "endTarget": str(es.get("end_target") or "").strip(),
                  "line": str(es.get("line") or "").strip()}
    checkpoints = _rows(d.get("checkpoints"), ("when", "check", "good_sign", "if_not"), 4)
    checkpoints.sort(key=lambda r: _WHEN_ORDER.index(r["when"]) if r["when"] in _WHEN_ORDER else 9)
    for r in checkpoints:
        r["goodSign"], r["ifNot"] = r.pop("good_sign"), r.pop("if_not")
        r["whenLabel"] = tr(r["when"]) if r["when"] in _WHEN_ORDER else r["when"]
    replies = _rows(d.get("reply_bank"), ("comment", "reply"), 5)
    return {
        "whyNow": why_now,
        "hasWhyNow": bool(why_now["shelfLife"] or why_now["window"] or why_now["why"]),
        "discovery": discovery,
        "hasDiscovery": bool(discovery["searchQueries"] or discovery["suggestedBeside"]
                             or discovery["browseTrigger"]),
        "delivery": delivery,
        "hasDelivery": bool(delivery["tone"] or delivery["pace"] or delivery["energy"]
                            or delivery["emphasis"] or delivery["avoid"]),
        "endScreen": end_screen,
        "hasEndScreen": bool(cards or end_screen["endTarget"] or end_screen["line"]),
        "checkpoints": checkpoints,
        "hasCheckpoints": bool(checkpoints),
        "replyBank": replies,
        "hasReplyBank": bool(replies),
    }


def _v7(d):
    """The v7 audit pack (v1.0.3), flattened. Empty on older records; the pane
    hides an empty section."""
    pb = d.get("packaging_brief") if isinstance(d.get("packaging_brief"), dict) else {}
    pack = {
        "thumbText": as_list(pb.get("thumb_text"))[:3],
        "focal": str(pb.get("focal") or "").strip(),
        "pairing": str(pb.get("pairing") or "").strip(),
        "standOut": str(pb.get("stand_out") or "").strip(),
    }
    facts = _rows(d.get("fact_check"), ("claim", "verify"), 5)
    lv = d.get("lite_version") if isinstance(d.get("lite_version"), dict) else {}
    lite = {k: str(lv.get(k) or "").strip() for k in ("time", "cut", "keep")}
    fn = d.get("funnel") if isinstance(d.get("funnel"), dict) else {}
    clips = _rows(fn.get("clips"), ("from", "hook"), 4)
    funnel = {"clips": clips, "linkTo": str(fn.get("link_to") or "").strip(),
              "why": str(fn.get("why") or "").strip()}
    return {
        "packagingBrief": pack,
        "hasPackagingBrief": bool(pack["thumbText"] or pack["focal"] or pack["pairing"]
                                  or pack["standOut"]),
        "factCheck": facts,
        "hasFactCheck": bool(facts),
        "liteVersion": lite,
        "hasLite": bool(lite["cut"] or lite["keep"]),
        "funnel": funnel,
        "hasFunnel": bool(clips or funnel["linkTo"]),
    }


def _audit(d, out):
    """Model-free checks on the blueprint the model wrote — what a producer
    would catch reading it before the shoot. Nothing here asks the model
    anything; it measures the reply against its own data and the inputs."""
    checks = []

    def add(label, ok, note=""):
        checks.append({"label": label, "ok": bool(ok), "note": note})

    script = out.get("fullScript") or []
    if script:
        end = max((r.get("endSec") or 0) for r in script)
        total = float((d.get("retention") or {}).get("total_seconds") or 0) or out.get("totalSeconds") or 0
        covers = bool(out.get("timelineExact")) and total > 0 and end >= 0.9 * total
        add(tr("Script covers the whole video"), covers,
            "" if covers else (tr("timing estimated") if not out.get("timelineExact")
                               else tr("ends at {a} of {b}").format(a=mmss(end), b=mmss(total))))
        spoken = [r for r in script if str(r.get("line") or "").strip()
                  and not str(r.get("line")).strip().startswith("(")]
        need = [r for r in script if str(r.get("speaker") or "") != "Music"]
        ok = len(spoken) >= max(1, len(need))
        add(tr("Every beat has words to say"), ok,
            "" if ok else tr("{n} beat(s) are stage directions").format(n=max(0, len(need) - len(spoken))))
    titles = out.get("titles") or []
    if titles:
        long_n = sum(1 for t in titles if len(t) > _TITLE_MAX)
        add(tr("Titles fit on mobile"), long_n == 0,
            "" if not long_n else tr("{n} over {m} characters").format(n=long_n, m=_TITLE_MAX))
    hook = str(out.get("hookPreview") or "")
    if hook:
        words = len(hook.split())
        limit = 18 if out.get("isLong") else 12
        add(tr("Hook fits in the first 3 seconds"), words <= limit,
            "" if words <= limit else tr("{n} words, aim for {m}").format(n=words, m=limit))
    add(tr("Three thumbnails to test"), len(out.get("thumbnails") or []) >= 3)
    if out.get("hasRefs"):
        cited = sum(1 for e in out.get("evidence") or [] if e.get("ref"))
        add(tr("Claims cite your real data"), cited >= 2,
            tr("{n} cited").format(n=cited))
    csv_day = any((c.get("bestDay") or "—") != "—" for c in (out.get("pulse") or {}).get("csv") or [])
    if out.get("hasPublishPlan"):
        add(tr("Upload slot from your own data"), csv_day,
            "" if csv_day else tr("general guidance — add a CSV export to ground it"))
    add(tr("Score explained part by part"), out.get("hasScoreParts"))
    sections = ["hasScript", "hasShots", "hasCompetitors", "hasAudience", "hasEvidence",
                "hasRehooks", "hasPublishPlan", "hasRisks", "hasSeriesNext", "hasPromise",
                "hasStyle", "hasOnScreen", "hasProduction", "hasAbPlan", "hasPlaybook",
                "hasRights"]
    # v6 sections only count toward completeness on a v6 record — an older
    # blueprint should not suddenly read "73% complete" for lacking fields
    # that did not exist when it was written.
    if int(out.get("schemaVersion") or 0) >= 6:
        sections += ["hasWhyNow", "hasDiscovery", "hasDelivery", "hasEndScreen",
                     "hasCheckpoints", "hasReplyBank"]
    # v7 (v1.0.3): the playbook and the A/B "watch" line are no longer asked
    # for (Checkpoints carries both), so they stop counting; the audit pack
    # counts instead. fact_check may legitimately be empty, so it never does.
    if int(out.get("schemaVersion") or 0) >= 7:
        sections = [k for k in sections if k != "hasPlaybook"]
        sections += ["hasPackagingBrief", "hasLite", "hasFunnel"]
    have = sum(1 for k in sections if out.get(k))
    passed = sum(1 for c in checks if c["ok"])
    return {"checks": checks, "passed": passed, "total": len(checks),
            "completeness": int(round(100.0 * have / len(sections))),
            "sections": have, "sectionsTotal": len(sections)}


def idea_for_qml(d):
    """Flatten one blueprint into the shape BlueprintPane.qml / IdeaRailCard.qml
    read.

    The stored schema (see app.core.ai.content_lab._content_lab_default_idea) is
    deeply nested; QML reads nested QVariantMaps fine, but the retention phases
    need their absolute times computed and the SEO block only exists for
    long-form, so the flattening happens once here rather than in a dozen
    bindings.

    `isLegacy` is the one piece of logic the UI can't derive itself: a blueprint
    stored before schema v2 has no script, shot list or competitor table, and
    the difference between "the model returned nothing for this section" and
    "this record predates the section" decides whether the card offers a full
    regeneration or just hides the section.
    """
    total = int(d.get("retention", {}).get("total_seconds", 60) or 60)
    phases = []
    prev_pct = 0
    for p in d.get("retention", {}).get("phases", []) or []:
        end_pct = int(p.get("end_pct", 0) or 0)
        phases.append({
            "label": p.get("label", ""),
            "desc": p.get("desc", ""),
            "endPct": end_pct,
            # Width as a fraction of the bar, so the QML meter doesn't have to
            # remember the previous phase's end.
            "spanPct": max(0, end_pct - prev_pct),
            "endTime": mmss(total * end_pct / 100.0),
        })
        prev_pct = end_pct

    seo = d.get("seo", {}) or {}
    hook = d.get("hook", {}) or {}
    anti = d.get("anti_hook", {}) or {}
    # visual/text are lists in v2 and were plain strings in v1. This has to
    # normalise them here rather than trusting the cleaner: loadSaved() reads
    # rows straight out of the database and hands them over uncleaned, and a
    # bare string reaching a QML Repeater is iterated character by character (a
    # 55-character hook line rendered as "55 options").
    hook_visual = as_list(hook.get("visual"))
    hook_text = as_list(hook.get("text"))
    # Same guard for the list-of-objects sections: a stored row that came back
    # malformed must not reach a Repeater as a string or a dict.
    script = d.get("full_script") if isinstance(d.get("full_script"), list) else []
    timed_script, timeline_total, timeline_ok = _timed_script(
        script, (d.get("retention") or {}).get("total_seconds") or 0)
    shots = d.get("shot_list") if isinstance(d.get("shot_list"), list) else []
    competitors = d.get("competitors") if isinstance(d.get("competitors"), dict) else {}
    thumbs = d.get("thumbnails") if isinstance(d.get("thumbnails"), list) else []
    if not thumbs:
        # A pre-v2 record has one bare `thumbnail_prompt` and no list. Wrap it so
        # the section still renders (with one concept instead of three) rather
        # than disappearing on a blueprint that does have a prompt.
        legacy_prompt = str(d.get("thumbnail_prompt") or "").strip()
        if legacy_prompt:
            thumbs = [{"label": tr("Concept A"), "prompt": legacy_prompt}]
    titles = as_list(d.get("titles"))
    ctas = d.get("cta_options") if isinstance(d.get("cta_options"), list) else []
    angle = d.get("viral_angle") if isinstance(d.get("viral_angle"), dict) else {}
    try:
        schema_v = int(d.get("schema_version") or 1)
    except (TypeError, ValueError):
        schema_v = 1

    # ── v4 pack ──
    ap = d.get("audience_profile") if isinstance(d.get("audience_profile"), dict) else {}
    audience_profile = {
        "persona": str(ap.get("persona") or ""),
        "painPoints": as_list(ap.get("pain_points")),
        "desires": as_list(ap.get("desires")),
        "objections": as_list(ap.get("objections")),
        "watchContext": str(ap.get("watch_context") or ""),
    }
    mo = d.get("monetization") if isinstance(d.get("monetization"), dict) else {}
    monet = {
        "adSafety": str(mo.get("ad_safety") or ""),
        "adSafetyLabel": {"Safe": tr("Ad-safe"), "Limited": tr("Limited ads"),
                          "Risky": tr("Ad risk")}.get(str(mo.get("ad_safety") or ""), ""),
        "why": str(mo.get("why") or ""),
        "sponsorFit": as_list(mo.get("sponsor_fit")),
        "productTieIn": str(mo.get("product_tie_in") or ""),
    }
    cpk = d.get("caption_pack") if isinstance(d.get("caption_pack"), dict) else {}
    caption_pack = {"description": str(cpk.get("description") or ""),
                    "hashtags": as_list(cpk.get("hashtags"))}
    rehooks = as_list_rows(d.get("rehooks"), ("time", "device", "line"))
    for r in rehooks:
        t = _clock_tokens(r.get("time"))
        r["atSec"] = float(t[0]) if t else -1.0
    evidence = as_list_rows(d.get("evidence"), ("claim", "ref", "url", "title", "views"))
    for e in evidence:
        e["views"] = humanize_count(_num(e.get("views"))) if _num(e.get("views")) else ""
    repurpose = as_list_rows(d.get("repurpose"), ("platform", "how"))
    pinned = str(d.get("pinned_comment") or "").strip()
    refs = _ref_rows(d)
    pulse = _pulse(d)
    comp_rows = []
    for r in (competitors.get("rows") if isinstance(competitors.get("rows"), list) else []):
        if not isinstance(r, dict):
            continue
        rr = {k: str(r.get(k, "") or "") for k in ("ref", "name", "angle", "gap", "url", "channel")}
        rr["views"] = humanize_count(_num(r.get("views"))) if _num(r.get("views")) else ""
        # an older record has no url on the row — find it among the refs, first
        # by the ref id the model cited ("V2"), then by title
        if not rr["url"] and rr["ref"]:
            for ref in refs:
                if ref["url"] and ref["ref"].upper() == rr["ref"].upper():
                    rr["url"] = ref["url"]
                    rr["channel"] = rr["channel"] or ref["channel"]
                    break
        if not rr["url"] and rr["name"]:
            low = rr["name"].strip().lower()
            for ref in refs:
                if ref["url"] and ref["title"].strip().lower() == low:
                    rr["url"], rr["ref"] = ref["url"], ref["ref"]
                    rr["channel"] = rr["channel"] or ref["channel"]
                    break
        if not rr["views"] and rr["url"]:
            for ref in refs:
                if ref["url"] == rr["url"] and ref["views"]:
                    rr["views"] = ref["views"]
                    break
        # The row ALWAYS gets a link: a video URL when one is known, otherwise
        # a YouTube search for the title, so every competitor can be opened.
        rr["openUrl"] = rr["url"] or (
            "https://www.youtube.com/results?search_query=" + quote_plus(rr["name"])
            if rr["name"] else "")
        rr["isSearch"] = not rr["url"] and bool(rr["name"])
        # A small thumbnail beside each row (served by image://thumbs).
        vid = extract_video_id(rr["url"]) if rr["url"] else None
        rr["thumbId"] = (base64.b64encode(
            f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg".encode("utf-8")).decode("ascii")
            if vid else "")
        comp_rows.append(rr)
    sources = [x for x in (d.get("data_sources") if isinstance(d.get("data_sources"), list) else [])
               if isinstance(x, dict)]

    out = {
        "id": int(d.get("id", 0) or 0),
        "format": d.get("format", "short"),
        "isLong": d.get("format") == "long",
        "title": d.get("title", "") or tr("Untitled idea"),
        "score": int(d.get("score", 0) or 0),
        "scoreLabel": d.get("score_label", ""),
        "hookPreview": d.get("hook_preview", ""),
        "source": d.get("source", ""),
        "audience": d.get("audience", ""),
        "pillar": d.get("pillar", ""),
        "difficulty": d.get("difficulty", "") or "Medium",
        "difficultyLabel": _difficulty_label(d.get("difficulty")),
        "thumbnails": thumbs,
        # Kept for the PDF export and anything else that wants one prompt.
        "thumbnailPrompt": d.get("thumbnail_prompt", ""),
        "titles": titles,
        "viralAngle": {
            "concept": angle.get("concept", ""),
            "triggers": as_list(angle.get("triggers")),
            "reasoning": angle.get("reasoning", ""),
        },
        "hook": {
            "focusTag": hook.get("focus_tag", ""),
            "visual": hook_visual,
            "text": hook_text,
            "reasoning": hook.get("reasoning", ""),
        },
        # Anti-hook is short-form only (empty on long-form). `as_list` guards a
        # bare string reaching a Repeater (iterated char-by-char otherwise).
        "antiHook": {
            "focusTag": anti.get("focus_tag", ""),
            "options": as_list(anti.get("options")),
            "reasoning": anti.get("reasoning", ""),
        },
        "hasAntiHook": bool(as_list(anti.get("options"))),
        # Rows carry startSec / endSec (see _timed_script) for the edit bay and
        # the 9:16 preview; every original key is kept for the teleprompter.
        "fullScript": timed_script,
        "totalSeconds": timeline_total,
        "totalLabel": mmss(timeline_total),
        "timelineExact": timeline_ok,
        # One string the copy button can lift wholesale — building it here keeps
        # the QML side from having to join a model.
        "scriptCopyText": "\n".join(
            f'[{s.get("time", "")}] {s.get("speaker", "")}: {s.get("line", "")}'
            for s in script),
        "shotList": shots,
        "competitors": {
            "rows": comp_rows,
            "gap": competitors.get("gap", ""),
        },
        "execution": d.get("execution", {}) or {},
        "packaging": d.get("packaging", {}) or {},
        "ctaOptions": ctas,
        "retention": {"totalLabel": mmss(total), "phases": phases},
        "seo": {
            "keywords": as_list(seo.get("keywords")),
            "tags": as_list(seo.get("tags")),
            "description": seo.get("description", "") or "",
            "timestamps": seo.get("timestamps") if isinstance(
                seo.get("timestamps"), list) else [],
        },
        "hasSeo": bool(seo.get("keywords") or seo.get("description")),
        # ── the working-creator pack ──
        # What would sink this video, when to post it, what to make next. Same
        # three the combined report's blueprint section carries, so a creator
        # reading either finds the same depth. Old stored blueprints simply lack
        # the keys; the pane hides empty sections, so nothing to migrate.
        "risks": as_list_rows(d.get("risks"), ("risk", "fix")),
        "publishPlan": _publish_plan(d.get("publish_plan")),
        "seriesNext": as_list_rows(d.get("series_next"), ("title", "why")),
        "hasRisks": bool(as_list_rows(d.get("risks"), ("risk", "fix"))),
        "hasPublishPlan": bool(_publish_plan(d.get("publish_plan"))),
        "hasSeriesNext": bool(as_list_rows(d.get("series_next"), ("title", "why"))),
        # Section-presence flags. QML can test an empty list itself, but doing it
        # here means one binding per section instead of a `(x || []).length > 0`
        # in every visible: expression.
        "hasScript": bool(script),
        "hasShots": bool(shots),
        "hasCompetitors": bool(competitors.get("rows") or competitors.get("gap")),
        "hasCta": bool(ctas),
        # ── v4 pack ──
        "audienceProfile": audience_profile,
        "hasAudience": bool(audience_profile["persona"] or audience_profile["painPoints"]
                            or audience_profile["desires"]),
        "rehooks": rehooks,
        "hasRehooks": bool(rehooks),
        "evidence": evidence,
        "hasEvidence": bool(evidence),
        "monetization": monet,
        "hasMonetization": bool(monet["adSafety"] or monet["sponsorFit"] or monet["productTieIn"]),
        "repurpose": repurpose,
        "hasRepurpose": bool(repurpose),
        "pinnedComment": pinned,
        "captionPack": caption_pack,
        "hasCaptionPack": bool(caption_pack["description"] or caption_pack["hashtags"]),
        "refs": refs,
        "hasRefs": bool(refs),
        "pulse": pulse,
        "hasPulse": bool(pulse["tiles"] or pulse["csv"]),
        "dataSources": [str(x.get("name") or "") for x in sources],
        "csvPaths": [str(x.get("path") or "") for x in sources if x.get("path")],
        "schemaVersion": schema_v,
        # Pre-v3 records lack the script / shots / competitors: a full banner.
        "isLegacy": schema_v < 3,
        # v3 records have everything but the v4 pack: a quiet "upgrade" line.
        "canUpgrade": 3 <= schema_v < CONTENT_LAB_SCHEMA_VERSION,
        "isFavorite": bool(d.get("is_favorite")),
    }
    out.update(_v5(d))
    out.update(_v6(d))
    out.update(_v7(d))
    # v7: SEO keywords were the same phrases as discovery.search_queries, so a
    # v7 record no longer asks for them; the SEO section shows the queries.
    if not out["seo"]["keywords"] and out.get("discovery", {}).get("searchQueries"):
        out["seo"]["keywords"] = list(out["discovery"]["searchQueries"])
    out["hasSeo"] = bool(out["seo"]["keywords"] or out["seo"]["tags"]
                         or out["seo"]["description"])
    out["titleRows"] = [{"text": t, "chars": len(t), "long": len(t) > _TITLE_MAX} for t in titles]
    # The PDF / clipboard keep reading scriptCopyText; v5 rows also carry what
    # is on screen, so the copy carries it too.
    out["scriptCopyText"] = "\n".join(
        f'[{s.get("time", "")}] {s.get("speaker", "")}: {s.get("line", "")}'
        + (f'  — {s.get("visual")}' if s.get("visual") else "")
        for s in script if isinstance(s, dict))
    out["audit"] = _audit(d, out)
    return out
