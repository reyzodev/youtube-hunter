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

# one-click filter combinations
NICHE_PRESETS = [
    ("Under 1K subs", {"subs_min": "0", "subs_max": "1000", "views_min": "",
                       "views_max": "", "mult_min": ""}),
    ("1K – 10K subs", {"subs_min": "1000", "subs_max": "10000", "views_min": "",
                       "views_max": "", "mult_min": ""}),
    ("Tiny channel, huge video", {"subs_min": "", "subs_max": "5000",
                                  "views_min": "1M", "views_max": "",
                                  "mult_min": "100"}),
    ("10M+ views", {"subs_min": "", "subs_max": "", "views_min": "10M",
                    "views_max": "", "mult_min": ""}),
    ("Clear filters", {"subs_min": "", "subs_max": "", "views_min": "",
                       "views_max": "", "mult_min": ""}),
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
