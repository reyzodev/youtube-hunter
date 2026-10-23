"""app.core.niche.gold - YouTube Hunter.

Gold Score: one 0-100 number for "is this a video worth stealing the idea
of?", so a 200-video viral pool can be read top-down instead of eyeballed.

A video is gold when it does something its channel should not be able to do:

  * reach      views ÷ subscribers (the multiplier), log-scaled. 1× = 0,
               50× and up = full marks. A 4M-sub channel getting 4M views
               is normal; a 20k-sub channel getting 4M is the find.
  * speed      views per hour against the POOL's median, log-scaled. It is
               relative on purpose: on the trending chart everything is fast,
               so only the outrunners score.
  * pull       (likes + comments) ÷ views against the pool median — people
               reacting, not just a thumbnail that got clicked.
  * size       how small the channel is. Same reach from a smaller channel =
               more repeatable by someone who is also small.

Weights: reach 40 · speed 25 · size 20 · pull 15. A row with hidden
subscribers can't be measured on reach or size, so it tops out around 40.

Tiers (what the card badge shows):
  gold  score >= 70 and at least 5× its subscribers
  hot   score >= 55
Pure Python, no Qt — the score is written into each row next to the
multiplier/velocity the pool already carries, so sort, filter, export and
the Search Archive all get it for free.
"""

import math
import statistics

GOLD_MIN = 70
HOT_MIN = 55
GOLD_MIN_MULT = 5.0
# A video this small is not a find yet, whatever its ratio says (10 subs,
# 900 views = 90×). Scores are scaled down below it.
_VIEWS_FLOOR = 20_000

_W_REACH, _W_SPEED, _W_SIZE, _W_PULL = 0.40, 0.25, 0.20, 0.15


def _clamp01(x):
    return 0.0 if x < 0 else 1.0 if x > 1 else x


def _rel_log(value, median, full_at):
    """0.5 at the pool median, 1.0 at `full_at`× the median, 0 at 1/full_at."""
    if not value or value <= 0 or not median or median <= 0:
        return 0.0
    return _clamp01(0.5 + 0.5 * math.log10(value / median) / math.log10(full_at))


def _size_score(subs, hidden):
    if hidden or subs is None:
        return 0.0
    if subs < 10_000:
        return 1.0
    if subs < 50_000:
        return 0.85
    if subs < 250_000:
        return 0.6
    if subs < 1_000_000:
        return 0.3
    return 0.1


def gold_tier(score, multiplier):
    if score >= GOLD_MIN and (multiplier or 0) >= GOLD_MIN_MULT:
        return "gold"
    if score >= HOT_MIN:
        return "hot"
    return ""


def apply_gold_scores(rows):
    """Write `gold_score` (0-100 int) and `gold_tier` into every row.
    Expects compute_niche_metrics' fields (multiplier, velocity, engagement).
    Mutates + returns `rows`."""
    vels = [r.get("velocity") for r in rows if (r.get("velocity") or 0) > 0]
    engs = [r.get("engagement") for r in rows if (r.get("engagement") or 0) > 0]
    med_v = statistics.median(vels) if vels else 0
    med_e = statistics.median(engs) if engs else 0
    for r in rows:
        mult = r.get("multiplier")
        hidden = bool(r.get("subs_hidden"))
        reach = (_clamp01(math.log10(mult) / math.log10(50))
                 if mult and mult > 1 and not hidden else 0.0)
        speed = _rel_log(r.get("velocity"), med_v, 10)
        pull = _rel_log(r.get("engagement"), med_e, 3)
        size = _size_score(r.get("subscriber_count"), hidden)
        score = (_W_REACH * reach + _W_SPEED * speed
                 + _W_SIZE * size + _W_PULL * pull)
        views = r.get("view_count") or 0
        if views < _VIEWS_FLOOR:
            score *= math.sqrt(max(views, 0) / _VIEWS_FLOOR)
        s = int(round(score * 100))
        r["gold_score"] = s
        r["gold_tier"] = gold_tier(s, mult)
    return rows
