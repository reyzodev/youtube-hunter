"""app.core.rpm - Youtube Scrapper."""

import re
import urllib.parse

# ═════════════════════════════════════════════════════════════════════════
#  RPM / CPM MODEL
#  ---------------------------------------------------------------------
#  CPM is what an advertiser pays per 1,000 ad impressions; RPM is what the
#  creator actually banks per 1,000 VIEWS after YouTube's 45% cut and after
#  the views that never saw an ad at all. RPM is therefore the only number
#  worth quoting to a creator, and it is roughly a third of CPM in practice.
#
#  Two things move it more than anything else, so both are modelled:
#
#    niche   an insurance or investing audience is worth an order of
#            magnitude more to advertisers than a gaming or kids audience;
#    country where the AUDIENCE is (approximated here by the channel's own
#            country) — the same video earns several times more from US
#            viewers than from viewers in a low-ad-spend market.
#
#  Shorts are priced separately and far lower: they are paid out of a shared
#  ad pool per 1,000 views, not per ad impression.
# ═════════════════════════════════════════════════════════════════════════
#  GEOGRAPHY TIERS
#  ---------------------------------------------------------------------
#  RPM depends heavily on WHERE the audience is. Rather than a single
#  continuous "% of a US audience" multiplier, the bands below are quoted
#  per geographic TIER, straight from real-world RPM tables:
#    Tier 1 — US / Canada / UK / Germany / Australia / Northern Europe
#    Tier 2 — the rest of Western Europe + wealthy Asia (FR, ES, IT, JP, KR, AE …)
#    Tier 3 — South Asia, the Middle East (incl. Iran), Africa, Latin America
#  A channel's own country is the best free proxy for its audience.
#
#  niche row layout:
#    (key, label, icon, long_tiers, short_tiers, keywords)
#  where *_tiers = ((t1_lo, t1_hi), (t2_lo, t2_hi), (t3_lo, t3_hi)) in USD
#  per 1,000 VIEWS, already net to the creator (Long-form keeps 55% of ad
#  revenue, Shorts 45% of the pool after the music cut). CPM — the
#  advertiser's price — is shown for reference at roughly 3× the long-form
#  RPM.
# ═════════════════════════════════════════════════════════════════════════

# Reusable Shorts bands (T1, T2, T3), from the Shorts RPM table.
_SHORT_FIN  = ((0.15, 0.40), (0.08, 0.20), (0.02, 0.05))
_SHORT_TECH = ((0.10, 0.25), (0.05, 0.12), (0.015, 0.03))
_SHORT_EDU  = ((0.10, 0.25), (0.04, 0.10), (0.01, 0.025))
_SHORT_FIT  = ((0.06, 0.15), (0.03, 0.07), (0.008, 0.02))
_SHORT_FILM = ((0.05, 0.12), (0.025, 0.06), (0.005, 0.015))
_SHORT_PET  = ((0.04, 0.10), (0.02, 0.05), (0.005, 0.012))
_SHORT_GAME = ((0.02, 0.06), (0.01, 0.03), (0.003, 0.01))
_SHORT_GEN  = ((0.02, 0.05), (0.01, 0.025), (0.002, 0.008))

NICHE_RPM_TABLE = [
    ("finance", "Finance · Investing · Crypto", "savings",
     ((12.0, 35.0), (6.0, 18.0), (1.5, 4.5)), _SHORT_FIN,
     ("finance", "invest", "investing", "stock", "stocks", "trading", "trader",
      "crypto", "bitcoin", "forex", "money", "wealth", "passive income",
      "dividend", "insurance", "tax", "mortgage", "credit", "banking", "بورس",
      "ارز", "طلا", "سرمایه")),
    ("business", "Business · Marketing · SaaS", "business_center",
     ((10.0, 22.0), (5.0, 12.0), (1.2, 3.5)), _SHORT_FIN,
     ("business", "marketing", "entrepreneur", "startup", "saas", "ecommerce",
      "dropship", "shopify", "agency", "b2b", "sales", "freelance", "career",
      "productivity", "کسب و کار", "بیزینس")),
    ("realestate", "Real Estate", "home_work",
     ((8.0, 20.0), (4.0, 11.0), (1.0, 3.0)), _SHORT_FIN,
     ("real estate", "realtor", "property", "apartment tour", "house tour",
      "mortgage", "landlord", "airbnb", "املاک")),
    ("tech", "Tech · Software · AI", "memory",
     ((5.0, 12.0), (3.0, 7.0), (0.8, 2.0)), _SHORT_TECH,
     ("tech", "technology", "gadget", "review", "unboxing", "iphone", "android",
      "laptop", "pc build", "software", "programming", "coding", "developer",
      "ai", "artificial intelligence", "python", "javascript", "تکنولوژی",
      "برنامه نویسی")),
    ("education", "Education · How-to · History", "school",
     ((4.0, 10.0), (2.5, 5.5), (0.6, 1.5)), _SHORT_EDU,
     ("education", "learn", "course", "tutorial", "how to", "study", "exam",
      "science", "history", "military", "math", "language", "english",
      "documentary", "facts", "آموزش", "درس", "تاریخ")),
    ("news", "News · Politics · Commentary", "newspaper",
     ((4.0, 9.0), (2.0, 5.0), (0.5, 1.3)), _SHORT_EDU,
     ("news", "politics", "political", "election", "geopolitics", "war",
       "breaking", "اخبار", "سیاسی")),
    ("health", "Health · Beauty · Fitness", "fitness_center",
     ((3.5, 8.0), (2.0, 4.5), (0.5, 1.2)), _SHORT_FIT,
     ("health", "fitness", "workout", "gym", "diet", "nutrition", "weight loss",
      "yoga", "medical", "doctor", "mental health", "wellness", "makeup",
      "skincare", "beauty", "سلامت", "بدنسازی", "ورزش")),
    ("beauty", "Beauty · Fashion · Lifestyle", "styler",
     ((3.5, 8.0), (2.0, 4.5), (0.5, 1.2)), _SHORT_FIT,
     ("makeup", "skincare", "fashion", "style", "outfit", "haul",
      "grwm", "hair", "nails", "lifestyle", "مد", "آرایش")),
    ("auto", "Automotive · Lifestyle", "directions_car",
     ((3.0, 6.5), (1.8, 3.5), (0.4, 1.0)), _SHORT_GEN,
     ("car", "cars", "auto", "automotive", "truck", "motorcycle", "ev",
      "tesla", "racing", "خودرو", "ماشین")),
    ("travel", "Travel · Places", "flight",
     ((3.0, 6.5), (1.8, 3.5), (0.4, 1.0)), _SHORT_GEN,
     ("travel", "traveling", "trip", "vlog abroad", "tourism", "hotel",
      "flight", "backpack", "سفر", "گردشگری")),
    ("food", "Food · Cooking", "restaurant",
     ((3.0, 6.5), (1.8, 3.5), (0.4, 1.0)), _SHORT_GEN,
     ("food", "cooking", "recipe", "recipes", "kitchen", "baking", "chef",
      "restaurant", "mukbang", "asmr eating", "آشپزی", "غذا")),
    ("pets", "Animal · Pet Stories", "pets",
     ((1.5, 4.0), (0.9, 2.2), (0.2, 0.6)), _SHORT_PET,
     ("pet", "pets", "dog", "dogs", "cat", "cats", "puppy", "kitten", "animal",
      "animals", "wildlife", "aquarium", "pet story", "pet stories", "حیوان",
      "سگ", "گربه")),
    ("film", "Anime · Cinema · Analysis", "theaters",
     ((1.5, 4.0), (0.9, 2.2), (0.2, 0.6)), _SHORT_FILM,
     ("anime", "manga", "movie", "film", "cinema", "marvel", "mcu", "star wars",
      "trailer", "breakdown", "video essay", "film analysis", "انیمه", "فیلم",
      "سینما")),
    ("gaming", "Gaming", "sports_esports",
     ((1.0, 3.0), (0.6, 1.5), (0.15, 0.5)), _SHORT_GAME,
     ("gaming", "gameplay", "gamer", "minecraft", "fortnite", "roblox",
      "call of duty", "valorant", "league of legends", "elden ring", "fps",
      "speedrun", "let's play", "گیم", "بازی")),
    ("entertainment", "Entertainment · Reaction · Comedy", "movie",
     ((0.8, 2.5), (0.5, 1.2), (0.1, 0.35)), _SHORT_GEN,
     ("vlog", "comedy", "funny", "prank", "challenge", "reaction", "react",
      "story", "drama", "celebrity", "shorts", "meme", "clips", "edits",
      "compilation", "compilations", "highlights", "livestream",
      "live stream", "streamer", "streamers", "کلیپ", "طنز")),
    ("music", "Music", "music_note",
     ((0.8, 2.5), (0.5, 1.2), (0.1, 0.35)), _SHORT_GEN,
     ("music", "song", "album", "beat", "remix", "cover", "guitar", "piano",
      "rap", "hip hop", "dj", "موسیقی", "آهنگ")),
    ("kids", "Kids · Family (COPPA)", "child_care",
     ((0.3, 1.0), (0.2, 0.6), (0.05, 0.2)), _SHORT_GEN,
     ("kids", "kid", "children", "toddler", "nursery", "toys", "cartoon",
      "family friendly", "کودک", "کارتون")),
]
NICHE_RPM_DEFAULT = ("general", "General Audience", "public",
                     ((2.0, 5.0), (1.2, 3.0), (0.3, 0.9)), _SHORT_GEN)

# Audience-market multiplier, kept for display ("% of a US audience's
# value") and as the source of the geographic tier below.
COUNTRY_RPM_FACTOR = {
    "US": 1.00, "AU": 0.95, "NO": 0.95, "CH": 0.95, "DK": 0.90, "CA": 0.90,
    "GB": 0.88, "NZ": 0.85, "SE": 0.85, "DE": 0.82, "NL": 0.80, "FI": 0.78,
    "IE": 0.78, "AT": 0.78, "BE": 0.75, "SG": 0.72, "AE": 0.70, "FR": 0.68,
    "JP": 0.62, "IT": 0.55, "ES": 0.55, "KR": 0.52, "IL": 0.50, "SA": 0.48,
    "PL": 0.40, "CZ": 0.40, "GR": 0.35, "PT": 0.35, "ZA": 0.32, "MY": 0.30,
    "CN": 0.30, "MX": 0.28, "TH": 0.26, "TR": 0.24, "RO": 0.24, "AR": 0.22,
    "BR": 0.22, "CO": 0.20, "RU": 0.18, "UA": 0.16, "VN": 0.16, "PH": 0.16,
    "EG": 0.15, "IR": 0.12, "ID": 0.14, "IN": 0.14, "PK": 0.12, "BD": 0.11,
    "NG": 0.12, "IQ": 0.14, "AF": 0.10,
}
COUNTRY_RPM_DEFAULT = 0.30
RPM_TO_CPM = 3.0

# Long-form views earn roughly two orders of magnitude more per view than
# Shorts views (per-tier long÷short mid-RPM runs ~19x for kids content up to
# ~136x for auto/travel/food, ~50x in the middle). The monetization checker's
# auto format detection weighs by this money ratio: deciding by upload count
# flips a Shorts channel that posts an occasional compilation to "long-form"
# and prices millions of Shorts views at long-form RPM (a ~100x revenue
# overstatement), while comparing raw views flips the other way for a
# long-form channel that sprinkles Shorts. Revenue-weighing gets both right.
SHORTS_LONG_VALUE_RATIO = 50.0


def rpm_tier_for_country(country):
    """1 / 2 / 3 for a country code. Unknown → Tier 2 (a middle guess, not
    the harshest), matching the tier lists in the RPM tables."""
    f = COUNTRY_RPM_FACTOR.get((country or "").upper())
    if f is None:
        return 2
    if f >= 0.80:
        return 1
    if f >= 0.45:
        return 2
    return 3


# ═════════════════════════════════════════════════════════════════════════
#  NICHE DETECTION
#  ---------------------------------------------------------------------
#  Deciding the niche is the single biggest lever on the revenue figure — a
#  finance channel's RPM band is roughly 5–10× a gaming or entertainment one —
#  so a wrong guess is not cosmetic, it is a wrong number. The previous
#  detector matched keywords as raw SUBSTRINGS, which made it wrong on almost
#  every big channel:
#
#      "ai"  matched "R*aised*"          -> MrBeast read as "Tech · Software · AI"
#      "ev"  matched "*ev*ery"           -> any channel read as "Automotive"
#      "war" matched "soft*war*e"
#      "pet" matched "com*pet*itive"
#      "business" matched "business inquiries" — in half of all descriptions
#
#  and, because ties were broken by the row's position in the table, a single
#  phantom hit in an early row (business / tech / education) beat a real signal
#  in a later one. T-Series came out "Education", Dude Perfect "Business".
#
#  The fix is threefold:
#    1. YouTube's own topicCategories (the channel's Freebase/Wikipedia topics)
#       are the primary signal — they are authoritative and they are the one
#       niche label YouTube itself publishes.
#    2. Blurb keywords match on WORD boundaries, and boilerplate ("business
#       inquiries", emails, URLs) is stripped first.
#    3. Ties break on the most SPECIFIC matched keyword, not on table order.
# ═════════════════════════════════════════════════════════════════════════

# A multi-word keyword ("real estate", "how to") is already specific; a bare
# word needs to be the whole word. Phrases therefore score higher.
_PHRASE_WEIGHT = 3.0
_WORD_WEIGHT = 1.0
# A topic hit (see _NICHE_TOPIC_WORDS) is worth far more than a blurb word: it
# is YouTube telling us the niche rather than us guessing it from prose.
_TOPIC_WEIGHT = 5.0
# Words that show up in a channel's About section for reasons unrelated to what
# the channel is about ("all Indian languages", "the language of the heart").
# They still count, at a discount, so a real signal elsewhere outranks them.
_GENERIC_FACTOR = 0.3
# The score a niche must reach before it is claimed at all — see the guard at
# the end of detect_channel_niche. One whole word (1.0) or a phrase (3.0) is
# enough; a discounted generic word on its own (0.3) is not.
_MIN_NICHE_SCORE = 1.0
_GENERIC_WORDS = frozenset({
    "language", "languages", "learn", "study", "story", "stories", "facts",
    "video", "videos", "channel", "content", "official", "subscribe",
    "welcome", "adventure", "challenge", "lifestyle", "clips", "edits",
    "highlights", "stream", "streams", "livestream", "review", "reviews",
    "tutorial", "how to",
})

# Boilerplate stripped from the blurb before matching. "Business inquiries" is
# in a huge share of descriptions and has nothing to do with a channel's niche.
_BOILERPLATE = (
    "business inquiries", "business enquiry", "business enquiries",
    "business or media", "business email", "business contact", "business only",
    "for business", "media inquiries", "media enquiries", "sponsorship",
    "sponsorships", "sponsor", "for inquiries", "for enquiries",
    "inquiries", "enquiries", "contact", "email", "e-mail",
)

# Per-niche words as they appear in a Wikipedia topic URL (e.g.
# ".../wiki/Video_game_culture" -> "video game culture"). Matched with the same
# word-boundary rule as the blurb keywords.
_NICHE_TOPIC_WORDS = {
    "gaming": ("game", "games", "gaming", "video game", "esports", "minecraft",
               "gameplay", "let's play"),
    "music": ("music", "song", "songs", "album", "band", "singer", "musician",
              "hip hop", "rock", "pop", "rap", "disc jockey"),
    "film": ("film", "films", "cinema", "anime", "manga", "movie", "movies",
             "television", "animation"),
    "entertainment": ("entertainment", "comedy", "humour", "humor", "sport",
                      "sports", "lifestyle", "celebrity", "recreation",
                      "performing arts"),
    "tech": ("technology", "computing", "software", "computer", "programming",
             "engineering", "gadget", "artificial intelligence", "internet",
             "electronics", "mobile phone"),
    "finance": ("finance", "financial", "investment", "investing",
                "cryptocurrency", "crypto", "stock", "money", "insurance",
                "banking", "economics", "tax", "accounting"),
    "business": ("business", "marketing", "entrepreneurship", "management",
                 "ecommerce", "advertising", "sales", "economy", "retail"),
    "realestate": ("real estate", "property", "housing", "mortgage"),
    "health": ("health", "fitness", "exercise", "medicine", "medical",
               "nutrition", "disease", "mental health", "wellness",
               "physical fitness", "public health"),
    "beauty": ("beauty", "fashion", "cosmetics", "clothing", "hair", "style"),
    "auto": ("automobile", "car", "cars", "vehicle", "motorcycle", "motorsport",
             "engine", "electric vehicle", "automotive"),
    "travel": ("travel", "tourism", "tourist", "destination", "geography",
               "landmark", "vacation"),
    "food": ("food", "cooking", "cuisine", "drink", "beverage", "restaurant",
             "recipe", "baking"),
    "pets": ("pet", "pets", "animal", "animals", "dog", "cat", "wildlife",
             "zoology", "aquarium"),
    "education": ("education", "knowledge", "science", "history",
                  "mathematics", "physics", "chemistry", "biology", "learning",
                  "university", "school", "philosophy"),
    "news": ("news", "politics", "journalism", "current events", "society",
             "war", "government", "military", "geopolitics"),
    "kids": ("child", "children", "family", "toy", "toys", "parenting",
             "cartoon", "nursery rhyme"),
}


def _word_hits(text, keyword):
    """How many times `keyword` occurs in `text` as a real word or phrase.

    Bare words match on a whole-word boundary; multi-word keywords are matched
    as plain phrases (they are specific enough on their own). This is what
    stops "ai" matching "Raised", "ev" matching "every" and "war" matching
    "software" — the substring matches that used to file MrBeast under "Tech".
    """
    if not text or not keyword:
        return 0
    if " " in keyword:
        return text.count(keyword)
    return len(re.findall(r"(?<!\w)" + re.escape(keyword) + r"(?!\w)", text))


def _clean_haystack(title, description, keywords=""):
    """The channel's own words, lowercased, with boilerplate and contacts
    removed so they can't be mistaken for a niche signal."""
    text = " ".join((title or "", description or "", keywords or "")).lower()
    text = re.sub(r"\S+@\S+", " ", text)          # emails
    text = re.sub(r"https?://\S+", " ", text)     # urls
    for phrase in _BOILERPLATE:
        text = text.replace(phrase, " ")
    return text


def _topic_text(url):
    """The matchable tail of a topicCategories entry: the Wikipedia article
    name, lowercased, underscores as spaces."""
    s = str(url or "")
    if "/wiki/" in s:
        s = s.split("/wiki/", 1)[1]
    return urllib.parse.unquote(s).replace("_", " ").lower()


def detect_channel_niche(title, description, keywords="", topics=None):
    """Best-guess niche from a channel's own words AND its YouTube topics.

    `topics` is the channel's `topicDetails.topicCategories` (a list of
    Wikipedia URLs) when available; it is scored heavily because it is the one
    niche label YouTube itself publishes. Returns the matching table row plus
    the winning score: (key, label, icon, long_tiers, short_tiers, keywords,
    score) — or the general-audience default with score 0 when nothing matched.
    """
    scores = {}     # niche key -> [weighted score, most specific match length]

    def _add(key, weight, specificity):
        cur = scores.get(key)
        if cur is None:
            scores[key] = [weight, specificity]
        else:
            cur[0] += weight
            cur[1] = max(cur[1], specificity)

    # 1) the authoritative topic signal
    for t in (topics or []):
        text = _topic_text(t)
        if not text:
            continue
        for key, words in _NICHE_TOPIC_WORDS.items():
            for w in words:
                n = _word_hits(text, w)
                if n:
                    _add(key, _TOPIC_WEIGHT * n, len(w))

    # 2) the blurb signal
    haystack = _clean_haystack(title, description, keywords)
    for row in NICHE_RPM_TABLE:
        key = row[0]
        for kw in row[5]:
            n = _word_hits(haystack, kw)
            if not n:
                continue
            weight = _PHRASE_WEIGHT if " " in kw else _WORD_WEIGHT
            if kw in _GENERIC_WORDS:
                weight *= _GENERIC_FACTOR
            _add(key, weight * n, len(kw))

    # Highest score wins; a tie goes to the niche whose best-matched keyword was
    # the most specific (longest) — an order-independent tie-break, where the
    # old code simply took whichever row came first in the table.
    best = max(scores, key=lambda k: (scores[k][0], scores[k][1])) if scores else None
    # A niche has to be EARNED. Below _MIN_NICHE_SCORE the only evidence was a
    # discounted generic word ("language" in an About section), and claiming
    # "Education" on that is a guess dressed as a finding — the general band is
    # the honest answer.
    if best is None or scores[best][0] < _MIN_NICHE_SCORE:
        return NICHE_RPM_DEFAULT + (0,)
    row = next((r for r in NICHE_RPM_TABLE if r[0] == best), NICHE_RPM_DEFAULT)
    return row[:6] + (int(round(scores[best][0])),)


def estimate_rpm(niche_row, country, is_shorts):
    """Turn (niche, country, format) into an RPM/CPM band in USD, read
    straight off the per-tier tables — the geography is baked into the band,
    not layered on as a separate multiplier."""
    tier = rpm_tier_for_country(country)
    bands = niche_row[4] if is_shorts else niche_row[3]
    lo, hi = bands[tier - 1]
    mid = (lo + hi) / 2.0
    floor = 0.002 if is_shorts else 0.05
    rpm = {"low": max(lo, floor), "mid": max(mid, floor), "high": max(hi, floor)}
    cpm = {k: v * RPM_TO_CPM for k, v in rpm.items()}
    # Display-only "% of a US (Tier 1) audience" for this same niche/format.
    t1_lo, t1_hi = bands[0]
    t1_mid = (t1_lo + t1_hi) / 2.0 or 1.0
    factor = min(1.0, mid / t1_mid) if t1_mid else 1.0
    return {"rpm": rpm, "cpm": cpm, "country_factor": factor, "tier": tier,
            "niche_key": niche_row[0], "niche_label": niche_row[1],
            "niche_icon": niche_row[2], "is_shorts": is_shorts}


# ═════════════════════════════════════════════════════════════════════════
#  EARNINGS RANGE ("$644 - $10K a month")
#  ---------------------------------------------------------------------
#  Nobody outside YouTube can name what a channel banks, so the headline the
#  checker leads with is an honest RANGE, not a number. The three tier cards
#  are three points INSIDE the niche's published RPM band; the range is wider
#  on purpose, because the band itself is not the whole uncertainty:
#
#    floor    bottom of the band, then × RANGE_RPM_FLOOR — a Q1 ad-spend
#             trough, ad-blockers, and the share of views that never serve
#             an ad at all (embedded, kids-flagged, non-advertiser-friendly);
#    ceiling  top of the band, then × RANGE_RPM_CEIL — a Q4 peak, and an
#             audience richer than the channel's own country suggests (the
#             country is only a proxy for where viewers actually are);
#    views    the view projection itself is a model, so the floor uses
#             RANGE_VIEWS_LOW of it and the ceiling RANGE_VIEWS_HIGH.
#
#  Net effect: a ~8–12× spread, the same order as the public "estimated
#  earnings" ranges people already know, and every factor is a named constant
#  rather than a fudge buried in a formula.
# ═════════════════════════════════════════════════════════════════════════
RANGE_RPM_FLOOR = 0.60
RANGE_RPM_CEIL = 1.60
RANGE_VIEWS_LOW = 0.85
RANGE_VIEWS_HIGH = 1.15


def blended_rpm(short_share, rpm_short, rpm_long, tier):
    """Effective RPM for a channel whose views split `short_share` Shorts /
    the rest long-form — each side priced at its own band."""
    s = max(0.0, min(1.0, float(short_share or 0.0)))
    return s * rpm_short["rpm"][tier] + (1.0 - s) * rpm_long["rpm"][tier]


def earnings_range(views, short_share, rpm_short, rpm_long):
    """(low, likely, high) USD earned on `views` views.

    `likely` is the middle of the band — the same figure the "Likely" tier
    card shows — so the range always brackets the plan-with-this number."""
    v = max(0.0, float(views or 0.0))
    lo = (v * RANGE_VIEWS_LOW / 1000.0
          * blended_rpm(short_share, rpm_short, rpm_long, "low") * RANGE_RPM_FLOOR)
    mid = v / 1000.0 * blended_rpm(short_share, rpm_short, rpm_long, "mid")
    hi = (v * RANGE_VIEWS_HIGH / 1000.0
          * blended_rpm(short_share, rpm_short, rpm_long, "high") * RANGE_RPM_CEIL)
    return lo, mid, hi


def money_compact(v):
    """A range end as a short $ label, the way the range reads at a glance:
    $0.42 · $8.10 · $644 · $5.2K · $10K · $83K · $1.4M · $12M.
    Rounded BEFORE choosing the unit, so 999.7 reads "$1K", never "$1000"."""
    v = max(0.0, float(v or 0.0))
    if v < 10:
        return f"${v:.2f}"
    if round(v) < 1_000:
        return f"${round(v):.0f}"
    k = v / 1_000.0
    if round(k, 1) < 10:
        return f"${round(k, 1):g}K"
    if round(k) < 1_000:
        return f"${round(k):.0f}K"
    m = v / 1_000_000.0
    if round(m, 1) < 10:
        return f"${round(m, 1):g}M"
    return f"${round(m):.0f}M"
