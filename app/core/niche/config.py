"""app.core.niche.config - Youtube Scrapper."""


# ── Niche Finder form vocabulary ────────────────────────────────────────
# (label, days)
NICHE_TIMEFRAMES = [
    ("Last 24 Hours", 1),
    ("Last 7 Days", 7),
    ("Last 30 Days", 30),
    ("Last 90 Days", 90),
    ("Last 6 Months", 180),
    ("Last 12 Months", 365),
    ("All Time", None),
]

# (label, local sort key, search.list order, scrape sp sort)
NICHE_SORTS_UI = [
    ("Best Finds · Views ÷ Subs", "multiplier", "viewCount", 3),
    ("Most Views", "view_count", "viewCount", 3),
    ("Fastest Growing · Views/hour", "velocity", "viewCount", 3),
    ("Smallest Channel First", "subscriber_count", "viewCount", 3),
    # Two-key ranking, not a ratio: smallest channel first, and among
    # channels that are ​equally small, whichever video has the most views
    # wins the tie. Distinct from "Best Finds" (views ÷ subs) — a channel
    # with 10 subs and 900 views would top the ratio sort despite the video
    # barely having been watched by anyone; this one always puts real reach
    # (raw view count) second in line, after channel size.
    ("Smallest Channel · Highest Views", "small_high_view", "viewCount", 3),
    ("Newest First", "published_at", "date", 2),
    ("Most Engagement", "engagement", "relevance", 0),
    # Views ascending — the channel-scan "Low → High" toggle (and the sort
    # combo's matching entry). Appended last so every existing index is stable.
    ("Fewest Views", "view_count_asc", "viewCount", 3),
    # v1.1 Gold Score — appended (never inserted) so saved sort indexes stay put.
    ("Gold Score · steal-worthy first", "gold", "viewCount", 3),
    # v1.0.2 — views ÷ the channel's own average video. Appended, never
    # inserted, so every saved sort index (Search Archive) keeps its meaning.
    ("Outlier · vs channel average", "channel_outlier", "viewCount", 3),
]

# What the Niche Finder's "Sort results by" actually offers, as indexes into
# NICHE_SORTS_UI and in this order. The table above stays whole (the Search
# Archive sorts saved sections by index into it); the page just stopped
# offering the two rows that only produce noise in a discovery tool:
#   * "Smallest Channel First" — a raw subscriber ascending sort puts 0-view
#     uploads from empty channels on top; "Smallest Channel · Highest Views"
#     is the version of that idea that works.
#   * "Fewest Views" — a channel-scan tool, not a niche-hunting one (the
#     Archive keeps its Low → High toggle).
# Gold Score moves up next to Best Finds: they are the two "what should I
# steal" rankings.
# v1.0.2: "Outlier · vs channel average" (9) sits with the two other
# "what should I copy" rankings, ahead of the raw-volume sorts.
NICHE_SORTS_VISIBLE = [0, 8, 9, 1, 2, 4, 5, 6]

# "Channel age" — the cut that finds NEW channels blowing up, which is what a
# creator looking for an open niche most wants to see: if a 3-month-old channel
# is pulling a million views, the niche is not saturated. Free: the creation
# date comes in the same channels.list payload the subscriber count does.
# (label, max channel age in days; None = any)
NICHE_CHANNEL_AGES = [
    ("Any channel age", None),
    ("Channel under 3 months", 90),
    ("Channel under 6 months", 180),
    ("Channel under 1 year", 365),
    ("Channel under 2 years", 730),
]

# ── v1.0.2 refinements (all instant, all local, zero quota) ─────────────
# Video length. "Format" only knew Shorts vs long-form, but the question a
# creator actually asks is "does this niche work at 8–20 min" (mid-roll ads
# start at 8:00) or "are 1-hour compilations winning here". Shorts may now run
# up to 3 minutes, hence the 1–3 min bucket.
# (label, min seconds inclusive, max seconds exclusive; None = open)
NICHE_DURATIONS = [
    ("Any length", None, None),
    ("Under 1 min", None, 60),
    ("1–3 min", 60, 180),
    ("3–8 min", 180, 480),
    ("8–20 min · mid-roll ads", 480, 1200),
    ("20–60 min", 1200, 3600),
    ("Over 1 hour", 3600, None),
]

# How many uploads the channel has in total. A channel with 12 videos and a
# 2M-view hit is the most replicable signal there is: it was not years of
# compounding audience, it was the idea. (label, max uploads; None = any)
NICHE_CHANNEL_UPLOADS = [
    ("Any upload count", None),
    ("Under 10 uploads", 10),
    ("Under 30 uploads", 30),
    ("Under 100 uploads", 100),
    ("Under 300 uploads", 300),
]

# Results per channel. One prolific channel used to fill a whole page; capping
# it shows how MANY channels are winning, which is the real saturation read.
# (label, cap; 0 = unlimited)
NICHE_PER_CHANNEL = [
    ("All videos per channel", 0),
    ("Best 1 per channel", 1),
    ("Best 3 per channel", 3),
]

# YouTube category, read from the videos.list payload we already pay for.
# "!10" = everything except Music, the category that floods every chart.
# (label, token for apply_niche_filters' "category")
NICHE_CATEGORIES = [
    ("All categories", ""),
    ("All except Music", "!10"),
    ("Entertainment", "24"),
    ("Gaming", "20"),
    ("People & Blogs", "22"),
    ("Comedy", "23"),
    ("Howto & Style", "26"),
    ("Education", "27"),
    ("Science & Technology", "28"),
    ("News & Politics", "25"),
    ("Sports", "17"),
    ("Film & Animation", "1"),
    ("Autos & Vehicles", "2"),
    ("Pets & Animals", "15"),
    ("Travel & Events", "19"),
    ("Music", "10"),
]


# AI Ideas' own mini control bar keeps sorting to three choices — unlike
# NICHE_SORTS_UI above, it has to sit in one row next to the format toggle
# and the quick-search box, so it's trimmed to exactly the three an
# idea-hunting pass over a keyword section actually needs: the ratio sort
# for "what punched above its channel's weight", freshest first for "what's
# trending right now", and raw views for "what actually reached people".
# (label, local sort key — reuses sort_niche_rows/_NICHE_SORTS above)
AI_IDEAS_SORTS_UI = [
    ("Best Finds · Top Viral", "multiplier"),
    ("Most Recent", "published_at"),
    ("Most Viewed", "view_count"),
]

# (label, search pages per query/window)
#
# `pages` is the API path's page count per (query × time window). The scrape
# path turns the same number into a TARGET of pages × 50 videos, and keeps
# walking YouTube's continuation token until it gets there or runs out — which
# is why the last entry is labelled "900+" rather than "~900": it is a floor,
# not a promise, and a keyword with enough results lands past it.
#
# What each step actually costs on the API path: one search.list page is 100
# quota units from a 10,000/day budget, so "Normal" (2 pages × 1 query × 1
# window) is 200 units and "Deepest" (18 × queries × windows) is thousands.
# That is the trade the label is warning about, and the reason the run-cost
# line under the form exists.
NICHE_DEPTHS = [
    ("Fast · 50 videos", 1),
    ("Normal · 100 videos", 2),
    ("Deep · 200 videos", 4),
    ("Very deep · 300 videos", 6),
    ("Maximum · 700 videos", 14),
    # The deepest search the app offers. It exists for the case the other five
    # cannot serve: a broad or crowded keyword where the good small channels sit
    # far down the result list, past the point where the API's own 500-results-
    # per-query ceiling stops helping — the extra depth comes from the scrape's
    # continuation walk and from widening across time windows.
    ("Deepest · 900+ videos", 18),
]

# How many videos each depth row collects — a HARD target, not a hint.
# Index-aligned with NICHE_DEPTHS. Picking "300" now means the search stops the
# moment it has 300 ids: it no longer runs every page of every deep-scan window
# (which could pull 1,000+ ids and spend the quota to enrich all of them) and the
# "widen to reach your filters" passes are skipped. Deep scan still spreads that
# same 300 across its time windows; it just never goes past it.
#
# None = no cap: the last row is the app's full power — every page of every
# window, plus the widening passes — and returns whatever YouTube has in range.
NICHE_DEPTH_TARGETS = [50, 100, 200, 300, 700, None]

# From this depth row on the search also slices its time window ("deep scan"),
# so each slice gets its own top-N and small channels surface. It used to be a
# separate toggle; asking for 200+ videos is already asking to dig deeper.
NICHE_DEEP_FROM_DEPTH = 2

# Language / Country now come from app.core.niche.audience, which also owns
# the logic that makes them real filters (they used to be search.list hints
# only — see that module's docstring). Shape kept as (UI name, value) so every
# existing reader still works: the value is what search.list's
# relevanceLanguage / regionCode want.
from app.core.niche.audience import COUNTRIES as _AUD_COUNTRIES  # noqa: E402
from app.core.niche.audience import LANGUAGES as _AUD_LANGUAGES  # noqa: E402
from app.core.niche.audience import PRECISIONS as _AUD_PRECISIONS  # noqa: E402

NICHE_LANGS = [(name, api) for name, _code, api in _AUD_LANGUAGES]
NICHE_REGIONS = [(name, code) for name, code, _langs in _AUD_COUNTRIES]
# How hard Language/Country filter: (UI name, mode token). Index 1 = default.
NICHE_AUDIENCE_PRECISION = list(_AUD_PRECISIONS)

# one-click filter combinations — v1.0.2 "recipes".
#
# Each recipe is a complete question a creator asks, not a single number:
# applying one resets EVERY instant cut first (so recipes never stack into a
# mystery state), then sets only what it names. Keys missing from a recipe go
# back to their default. Sort / format / duration / channel age are indexes
# into the tables above; "sort" is an index into NICHE_SORTS_UI.
#
# Why these six:
#   * Tiny channel, huge video — the classic outlier: the idea did the work.
#     100K views (not 1M) so it fires on mid-sized niches too.
#   * New channel breakout — a channel under 6 months pulling 100K+ means the
#     niche is still open to newcomers.
#   * 5× its own average — a video far above what ITS channel normally does:
#     the packaging/topic is the reason, not the audience.
#   * Mid-roll long-form — 8–20 min, small channel, real reach: the format that
#     actually pays (mid-roll ads unlock at 8:00).
#   * Shorts rocket — a Short from a sub-50K channel past 1M views.
NICHE_PRESETS = [
    ("Tiny channel, huge video", {"subs_max": "10K", "views_min": "100K",
                                  "mult_min": "20", "sort": 0}),
    ("New channel breakout", {"channel_age": 2, "views_min": "100K", "sort": 0}),
    ("5× its own average", {"outlier_min": "5", "views_min": "20K", "sort": 9}),
    ("Mid-roll long-form", {"format": 1, "duration": 4, "subs_max": "100K",
                            "mult_min": "3", "sort": 8}),
    ("Shorts rocket", {"format": 2, "subs_max": "50K", "views_min": "1M",
                       "sort": 0}),
    ("Clear filters", {}),
]

# Outlier signal tuner (v1.1 "Signal Tuner"). The four cuts the Niche
# Finder's tuner shows as tracks, and the stops on each. The first stop is
# always "" (= Any). Kept here, not in QML, because the VM counts how many
# pooled videos each stop would leave and the two must never disagree.
#   subs    -> subs_max   (channel at most N subscribers)
#   views   -> views_min  (video at least N views)
#   mult    -> mult_min   (views ÷ subscribers at least N×)
#   outlier -> outlier_min (views ÷ the channel's own average at least N×)
# The stops include every threshold a built-in recipe uses (20K views, 50K
# subs, 20× multiplier), so applying a recipe lights a real stop instead of
# reporting a value it cannot show as "Custom".
NICHE_SIGNAL_STOPS = {
    "subs":    ["", "1K", "10K", "50K", "100K", "1M"],
    "views":   ["", "10K", "20K", "100K", "1M", "10M"],
    "mult":    ["", "3", "10", "20", "50", "100"],
    "outlier": ["", "2", "5", "10", "25"],
}

# One line per recipe for the tuner's hover tip, in NICHE_PRESETS order.
NICHE_PRESET_HINTS = [
    "≤ 10K subs · ≥ 100K views · ≥ 20× views ÷ subs",
    "Channel under 6 months · ≥ 100K views",
    "≥ 5× the channel's own average · ≥ 20K views",
    "Long-form 8–20 min · ≤ 100K subs · ≥ 3×",
    "Shorts · ≤ 50K subs · ≥ 1M views",
    "",
]

# Hard ceiling on how many rows a view will take on. It used to be the
# number of cards built in one go, which is why it had to be low — now the
# card grids page six rows at a time (GRID_ROWS_PER_PAGE) and only that
# page's worth of cards exists, so the pool itself can be far larger without
# Qt feeling any of it. The flat table view still renders this many rows in
# one pass, which is what keeps the ceiling from going higher.
NICHE_MAX_RENDER = 900

# How many MATCHED rows the QML Niche Finder keeps available to page through.
#
# Deliberately separate from NICHE_MAX_RENDER above, which is the legacy
# QWidgets grid's ceiling: that grid builds a widget per row in one pass, so
# raising it there costs real memory and layout time. The QML grid pages 24
# cards at a time and only ever instantiates the current page, so its pool can
# be much larger for free — it holds plain dicts, not QObjects.
#
# It sits above the deepest search's 900 target on purpose: the target is a
# floor, and a run that finds 1,300 videos should not silently drop 400 of them
# just because the old cap said 900.
NICHE_MAX_POOL = 1600

# Cards per page in the QML result grid. The QWidgets grid derived its page
# size from its own fixed column count (GRID_COLS * GRID_ROWS_PER_PAGE = 12);
# the QML grid's column count is elastic, so it pages on a flat count instead
# — 24 covers four rows at six columns and eight rows at three, which is more
# than any window shows at once while keeping the number of live NicheCard
# instances (each carrying two MultiEffect mask layers) bounded.
NICHE_PAGE_SIZE = 24

# Result-card width; the card grid derives its column count from this.
# Widened from 292: the gutter between cards came down from 16px to 10px
# (see _new_grid_host), and every pixel saved there went into the cards
# themselves rather than into dead space — same column count on the same
# window, more room for the thumbnail, the title and the channel row.
NICHE_CARD_W = 420

# Narrowest a result card may be squeezed to before the grid gives up a
# column. Below this the thumbnail stops being readable and the four
# action icons no longer fit on one row.
NICHE_CARD_MIN_W = 256

# Gutter between cards in a card grid, and the value _card_grid_columns()
# budgets per column when it works out how many columns fit. Both read the
# same constant, so the two can never drift apart and leave a fat dead
# strip down one side of the panel.
NICHE_CARD_GAP = 8
