"""app.core.analysis.earn_read - YouTube Hunter.

v1.0.3: the "What earns the views" panel, read out in plain language.

The snapshot's lift groups (see snapshot._lift_groups) are exact but speak in
ratios: "Question titles 1.3×". A creator who has never seen a log-scale chart
reads that as noise. This module turns each group into what it MEANS for
someone deciding what to make next:

  pct        "+30%" / "-50%"   — how many more / fewer views per day
  verdict    "do" / "avoid" / "same"
  strength   1-3                — how many videos the reading rests on
  sentence   one plain sentence a beginner understands without the chart

and condenses the whole panel into a three-card plan (do more of / skip /
doesn't matter). Pure Python, no Qt — the VM only wraps it.
"""

import math

from app.core.utils import humanize_count
from app.i18n import tr

# A reading inside this band is too close to "typical" to act on.
FLAT_LOW = 0.87
FLAT_HIGH = 1.15
# How many videos a reading needs before it is "fair" / "solid".
FAIR_ROWS = 8
SOLID_ROWS = 20

_GROUP_KEYS = ("title", "length", "format", "extras")


def pct_text(lift):
    """1.3 -> "+30%", 0.5 -> "-50%", 1.0 -> "±0%"."""
    p = int(round((float(lift) - 1.0) * 100))
    if p == 0:
        return "±0%"
    return ("+%d%%" % p) if p > 0 else ("−%d%%" % abs(p))


def strength_of(rows):
    rows = int(rows or 0)
    return 3 if rows >= SOLID_ROWS else 2 if rows >= FAIR_ROWS else 1


def strength_label(level):
    return {1: tr("Thin evidence"), 2: tr("Fair evidence"), 3: tr("Solid evidence")}[level]


def verdict_of(lift):
    if FLAT_LOW <= lift <= FLAT_HIGH:
        return "same"
    return "do" if lift > 1 else "avoid"


def sentence_for(label, verdict, pct, daily, base, rows):
    n = tr("{n} videos").format(n=rows)
    if verdict == "do":
        return tr("{what} get about {pct} more views per day than a typical video in this "
                  "search ({daily} vs {base}, from {n}).").format(
            what=label, pct=pct.lstrip("+"), daily=daily, base=base, n=n)
    if verdict == "avoid":
        return tr("{what} get about {pct} fewer views per day than a typical video here "
                  "({daily} vs {base}, from {n}).").format(
            what=label, pct=pct.lstrip("−-"), daily=daily, base=base, n=n)
    return tr("{what} perform about the same as a typical video here ({n}): this choice "
              "doesn't move views on its own.").format(what=label, n=n)


def earn_rows(lifts, group_label, choice_label):
    """Every lift group as a display row, strongest first.

    `group_label(group)` / `choice_label(group, key)` are the snapshot's own
    translators (passed in so this module stays import-light)."""
    lifts = lifts or {}
    base = lifts.get("base_daily")
    base_txt = (humanize_count(base) + tr("/day")) if base else "—"
    out = []
    for g in lifts.get("groups") or []:
        lift = float(g.get("lift") or 0)
        if lift <= 0:
            continue
        rows = int(g.get("rows") or 0)
        label = choice_label(g["group"], g["key"])
        verdict = verdict_of(lift)
        pct = pct_text(lift)
        daily = humanize_count(g.get("median_daily") or 0) + tr("/day")
        level = strength_of(rows)
        out.append({
            "groupKey": g["group"] if g["group"] in _GROUP_KEYS else "extras",
            "group": group_label(g["group"]),
            "label": label,
            "rows": rows,
            "rowsText": tr("{n} videos").format(n=rows),
            "daily": daily,
            "lift": lift,
            "liftText": "%.1f×" % lift,
            "pct": pct,
            # log2 scale clamped to ¼×…4× (−1…1): doubling and halving sit
            # the same distance from the centre line
            "pos": max(-1.0, min(1.0, math.log2(lift) / 2.0)),
            "flat": verdict == "same",
            "verdict": verdict,
            "strength": level,
            "strengthText": strength_label(level),
            "sentence": sentence_for(label, verdict, pct, daily, base_txt, rows),
        })
    out.sort(key=lambda r: r["lift"], reverse=True)
    return out


def earn_plan(rows):
    """The three cards over the chart. Thin readings never headline a card
    when a fairer one exists, so one 4-video fluke can't be the advice."""
    def rank(cands, reverse):
        return sorted(cands, key=lambda r: (r["strength"] > 1, abs(math.log2(r["lift"]))),
                      reverse=True)

    do = rank([r for r in rows if r["verdict"] == "do"], True)[:2]
    avoid = rank([r for r in rows if r["verdict"] == "avoid"], True)[:2]
    same = [r for r in rows if r["verdict"] == "same"]
    return {
        "doMore": [{"label": r["label"], "pct": r["pct"], "rowsText": r["rowsText"],
                    "strength": r["strength"]} for r in do],
        "skip": [{"label": r["label"], "pct": r["pct"], "rowsText": r["rowsText"],
                  "strength": r["strength"]} for r in avoid],
        "same": [r["label"] for r in same][:4],
        "sameMore": max(0, len(same) - 4),
        "hasAny": bool(rows),
    }
