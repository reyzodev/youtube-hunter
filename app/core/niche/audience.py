"""app.core.niche.audience - who a video is actually FOR (language + country).

Why this module exists
----------------------
The Niche Finder used to forward Language/Country straight to search.list as
`relevanceLanguage` / `regionCode` and stop there. Both are *hints*, not
filters (YouTube's own docs: regionCode returns videos "that can be viewed in"
a country; relevanceLanguage results "most relevant to" a language, and
"results in other languages will still be returned"). So "Spanish + Brazil"
came back as whatever was popular, and the web-scrape source ignored both
fields entirely. The dropdowns looked like filters and behaved like nothing.

What it does now
----------------
Every row is scored against the target language and country from evidence
YouTube already handed us — no extra quota, no extra request:

  language evidence                                   weight
    video.defaultAudioLanguage   (the spoken language)   3.0
    video.defaultLanguage        (title/desc metadata)   2.0
    title + description + tags   (offline detector)      3.0 x confidence
    channel.defaultLanguage                              1.0
    channel country's main languages                     0.5

  country evidence
    channel.snippet.country      (registered country)   3.0
    region subtag of the audio tag ("pt-BR" -> BR)       2.0
    a language that is (nearly) unique to the country    1.0 x confidence
    a language the country does not speak at all        -1.5 x confidence

The sum becomes a verdict per dimension:
    >= 2.5  "verified"   strong, direct evidence
    >= 1.0  "likely"     consistent, indirect evidence
    <= -1.5 "mismatch"   evidence points elsewhere
    else    "unknown"    YouTube gave us nothing to go on

and the precision setting decides what survives:
    broad   keep everything that is not a mismatch
    smart   keep verified + likely            (default)
    strict  keep verified only

The detector is deliberately simple and fully offline: Unicode script ranges
settle most non-Latin languages outright, a few letter markers split the
script-sharing ones (Persian/Arabic/Urdu, Russian/Ukrainian/...), and short
stop-word profiles plus diacritics rank the Latin-script languages.
"""

import re

# Bumped whenever the detector changes, so memoised guesses on cached/archived
# rows are recomputed instead of trusted.
_DETECT_VERSION = 3
_MEMO_KEY = "_aud"

# ═════════════════════════════════════════════════════════════════════════
#  CATALOGUE
# ═════════════════════════════════════════════════════════════════════════
# (UI name, ISO 639-1 code, code search.list's relevanceLanguage wants)
# Order: "any", then the languages with the largest YouTube audiences, then
# alphabetical. The UI shows them in exactly this order.
LANGUAGES = [
    ("Any language", "", ""),
    ("English", "en", "en"),
    ("Spanish", "es", "es"),
    ("Portuguese", "pt", "pt"),
    ("Hindi", "hi", "hi"),
    ("Arabic", "ar", "ar"),
    ("Persian", "fa", "fa"),
    ("Indonesian", "id", "id"),
    ("Russian", "ru", "ru"),
    ("Japanese", "ja", "ja"),
    ("Korean", "ko", "ko"),
    ("Chinese (Simplified)", "zh-hans", "zh-Hans"),
    ("Chinese (Traditional)", "zh-hant", "zh-Hant"),
    ("French", "fr", "fr"),
    ("German", "de", "de"),
    ("Turkish", "tr", "tr"),
    ("Vietnamese", "vi", "vi"),
    ("Italian", "it", "it"),
    ("Thai", "th", "th"),
    ("Filipino", "tl", "tl"),
    ("Bengali", "bn", "bn"),
    ("Urdu", "ur", "ur"),
    ("Polish", "pl", "pl"),
    ("Ukrainian", "uk", "uk"),
    ("Dutch", "nl", "nl"),
    ("Malay", "ms", "ms"),
    ("Tamil", "ta", "ta"),
    ("Telugu", "te", "te"),
    ("Marathi", "mr", "mr"),
    ("Gujarati", "gu", "gu"),
    ("Kannada", "kn", "kn"),
    ("Malayalam", "ml", "ml"),
    ("Punjabi", "pa", "pa"),
    ("Romanian", "ro", "ro"),
    ("Greek", "el", "el"),
    ("Czech", "cs", "cs"),
    ("Hungarian", "hu", "hu"),
    ("Swedish", "sv", "sv"),
    ("Danish", "da", "da"),
    ("Norwegian", "no", "no"),
    ("Finnish", "fi", "fi"),
    ("Hebrew", "he", "iw"),
    ("Azerbaijani", "az", "az"),
    ("Kurdish", "ku", "ku"),
    ("Pashto", "ps", "ps"),
    ("Swahili", "sw", "sw"),
    ("Nepali", "ne", "ne"),
    ("Sinhala", "si", "si"),
    ("Burmese", "my", "my"),
    ("Khmer", "km", "km"),
    ("Georgian", "ka", "ka"),
    ("Armenian", "hy", "hy"),
    ("Amharic", "am", "am"),
    ("Kazakh", "kk", "kk"),
    ("Uzbek", "uz", "uz"),
    ("Serbian", "sr", "sr"),
    ("Bulgarian", "bg", "bg"),
    ("Slovak", "sk", "sk"),
    ("Croatian", "hr", "hr"),
]

# (UI name, ISO 3166-1 alpha-2, main languages in rough order of reach)
COUNTRIES = [
    ("Any country", "", ()),
    ("United States", "US", ("en", "es")),
    ("India", "IN", ("hi", "en", "bn", "te", "mr", "ta", "gu", "kn", "ml", "pa", "ur")),
    ("Brazil", "BR", ("pt",)),
    ("Indonesia", "ID", ("id",)),
    ("Mexico", "MX", ("es",)),
    ("Japan", "JP", ("ja",)),
    ("Russia", "RU", ("ru",)),
    ("Iran", "IR", ("fa", "az", "ku")),
    ("Turkey", "TR", ("tr", "ku")),
    ("Germany", "DE", ("de",)),
    ("United Kingdom", "GB", ("en",)),
    ("France", "FR", ("fr",)),
    ("Philippines", "PH", ("tl", "en")),
    ("Vietnam", "VN", ("vi",)),
    ("South Korea", "KR", ("ko",)),
    ("Pakistan", "PK", ("ur", "en", "pa", "ps")),
    ("Egypt", "EG", ("ar",)),
    ("Saudi Arabia", "SA", ("ar",)),
    ("United Arab Emirates", "AE", ("ar", "en")),
    ("Thailand", "TH", ("th",)),
    ("Spain", "ES", ("es",)),
    ("Italy", "IT", ("it",)),
    ("Canada", "CA", ("en", "fr")),
    ("Australia", "AU", ("en",)),
    ("Argentina", "AR", ("es",)),
    ("Colombia", "CO", ("es",)),
    ("Chile", "CL", ("es",)),
    ("Peru", "PE", ("es",)),
    ("Venezuela", "VE", ("es",)),
    ("Portugal", "PT", ("pt",)),
    ("Netherlands", "NL", ("nl",)),
    ("Belgium", "BE", ("nl", "fr", "de")),
    ("Switzerland", "CH", ("de", "fr", "it")),
    ("Austria", "AT", ("de",)),
    ("Poland", "PL", ("pl",)),
    ("Ukraine", "UA", ("uk", "ru")),
    ("Romania", "RO", ("ro",)),
    ("Greece", "GR", ("el",)),
    ("Czechia", "CZ", ("cs",)),
    ("Hungary", "HU", ("hu",)),
    ("Sweden", "SE", ("sv",)),
    ("Norway", "NO", ("no",)),
    ("Denmark", "DK", ("da",)),
    ("Finland", "FI", ("fi", "sv")),
    ("Ireland", "IE", ("en",)),
    ("New Zealand", "NZ", ("en",)),
    ("South Africa", "ZA", ("en",)),
    ("Nigeria", "NG", ("en",)),
    ("Kenya", "KE", ("sw", "en")),
    ("Morocco", "MA", ("ar", "fr")),
    ("Algeria", "DZ", ("ar", "fr")),
    ("Iraq", "IQ", ("ar", "ku")),
    ("Jordan", "JO", ("ar",)),
    ("Qatar", "QA", ("ar", "en")),
    ("Kuwait", "KW", ("ar",)),
    ("Israel", "IL", ("he", "ar")),
    ("Afghanistan", "AF", ("fa", "ps", "uz")),
    ("Bangladesh", "BD", ("bn",)),
    ("Sri Lanka", "LK", ("si", "ta")),
    ("Nepal", "NP", ("ne",)),
    ("Malaysia", "MY", ("ms", "en")),
    ("Singapore", "SG", ("en", "ms", "ta")),
    ("Taiwan", "TW", ("zh-hant",)),
    ("Hong Kong", "HK", ("zh-hant", "en")),
    ("Azerbaijan", "AZ", ("az", "ru")),
    ("Kazakhstan", "KZ", ("kk", "ru")),
    ("Uzbekistan", "UZ", ("uz", "ru")),
    ("Georgia", "GE", ("ka",)),
    ("Armenia", "AM", ("hy",)),
    ("Serbia", "RS", ("sr",)),
    ("Bulgaria", "BG", ("bg",)),
    ("Croatia", "HR", ("hr",)),
    ("Slovakia", "SK", ("sk",)),
    ("Ethiopia", "ET", ("am",)),
    ("Cambodia", "KH", ("km",)),
    ("Myanmar", "MM", ("my",)),
]

PRECISIONS = [
    ("Broad", "broad"),
    ("Smart", "smart"),
    ("Strict", "strict"),
]

_COUNTRY_LANGS = {c: set(ls) for _n, c, ls in COUNTRIES if c}
# How many catalogue countries speak a language: a language spoken in only a
# couple of them (Persian, Thai, Vietnamese, Polish …) is real evidence of
# origin; English, Spanish or Arabic are not.
_LANG_SPREAD = {}
for _c, _ls in _COUNTRY_LANGS.items():
    for _l in _ls:
        _LANG_SPREAD[_l] = _LANG_SPREAD.get(_l, 0) + 1

_NAME_OF_LANG = {code: name for name, code, _api in LANGUAGES if code}
_NAME_OF_COUNTRY = {code: name for name, code, _l in COUNTRIES if code}


def language_name(code):
    return _NAME_OF_LANG.get(norm_lang(code), "")


def country_name(code):
    return _NAME_OF_COUNTRY.get((code or "").upper(), "")


def country_languages(code):
    return tuple(next((ls for _n, c, ls in COUNTRIES if c == (code or "").upper()), ()))


# ═════════════════════════════════════════════════════════════════════════
#  CODE NORMALISATION
# ═════════════════════════════════════════════════════════════════════════
_ALIASES = {
    "iw": "he", "in": "id", "fil": "tl", "nb": "no", "nn": "no", "ji": "yi",
    "zh-cn": "zh-hans", "zh-sg": "zh-hans", "zh-hans": "zh-hans",
    "zh-tw": "zh-hant", "zh-hk": "zh-hant", "zh-mo": "zh-hant",
    "zh-hant": "zh-hant", "zh": "zh-hans", "pes": "fa", "prs": "fa",
    "ckb": "ku", "kmr": "ku", "arz": "ar",
}
# "no linguistic content" / "undetermined" — a declared non-answer.
_NON_LANGS = {"zxx", "und", "mul", "mis", ""}


def norm_lang(code):
    """'en-US' -> 'en', 'zh-TW' -> 'zh-hant', 'iw' -> 'he'. '' when unknown."""
    c = (code or "").strip().lower().replace("_", "-")
    if not c:
        return ""
    if c in _ALIASES:
        return _ALIASES[c]
    base = c.split("-")[0]
    if base == "zh":
        rest = c.split("-", 1)[1] if "-" in c else ""
        return "zh-hant" if rest in ("hant", "tw", "hk", "mo") else "zh-hans"
    base = _ALIASES.get(base, base)
    return "" if base in _NON_LANGS else base


def lang_region(code):
    """Region subtag of a language tag: 'pt-BR' -> 'BR'. '' when absent."""
    c = (code or "").strip().replace("_", "-")
    for part in c.split("-")[1:]:
        if len(part) == 2 and part.isalpha():
            return part.upper()
    return ""


def _family(code):
    return "zh" if code.startswith("zh") else code


# ═════════════════════════════════════════════════════════════════════════
#  OFFLINE TEXT DETECTOR
# ═════════════════════════════════════════════════════════════════════════
# (first, last, script) — only the ranges a YouTube title realistically uses.
_SCRIPT_RANGES = [
    (0x0370, 0x03FF, "greek"), (0x1F00, 0x1FFF, "greek"),
    (0x0400, 0x04FF, "cyrillic"), (0x0500, 0x052F, "cyrillic"),
    (0x0530, 0x058F, "armenian"),
    (0x0590, 0x05FF, "hebrew"),
    (0x0600, 0x06FF, "arabic"), (0x0750, 0x077F, "arabic"),
    (0x08A0, 0x08FF, "arabic"), (0xFB50, 0xFDFF, "arabic"),
    (0xFE70, 0xFEFF, "arabic"),
    (0x0900, 0x097F, "devanagari"),
    (0x0980, 0x09FF, "bengali"),
    (0x0A00, 0x0A7F, "gurmukhi"),
    (0x0A80, 0x0AFF, "gujarati"),
    (0x0B80, 0x0BFF, "tamil"),
    (0x0C00, 0x0C7F, "telugu"),
    (0x0C80, 0x0CFF, "kannada"),
    (0x0D00, 0x0D7F, "malayalam"),
    (0x0D80, 0x0DFF, "sinhala"),
    (0x0E00, 0x0E7F, "thai"),
    (0x1000, 0x109F, "myanmar"),
    (0x10A0, 0x10FF, "georgian"),
    (0x1200, 0x139F, "ethiopic"),
    (0x1780, 0x17FF, "khmer"),
    (0x1100, 0x11FF, "hangul"), (0x3130, 0x318F, "hangul"),
    (0xAC00, 0xD7AF, "hangul"),
    (0x3040, 0x309F, "kana"), (0x30A0, 0x30FF, "kana"),
    (0x31F0, 0x31FF, "kana"),
    (0x4E00, 0x9FFF, "han"), (0x3400, 0x4DBF, "han"),
]
_SINGLE_SCRIPT = {
    "greek": "el", "armenian": "hy", "hebrew": "he", "bengali": "bn",
    "gurmukhi": "pa", "gujarati": "gu", "tamil": "ta", "telugu": "te",
    "kannada": "kn", "malayalam": "ml", "sinhala": "si", "thai": "th",
    "myanmar": "my", "georgian": "ka", "ethiopic": "am", "khmer": "km",
    "hangul": "ko",
}


def _script_of(ch):
    o = ord(ch)
    if o < 0x80:
        return "latin" if (65 <= o <= 90 or 97 <= o <= 122) else None
    if o < 0x0370:
        return "latin" if ch.isalpha() else None
    for lo, hi, name in _SCRIPT_RANGES:
        if lo <= o <= hi:
            return name
    return "latin" if ch.isalpha() else None


# Characters that only (or overwhelmingly) one language of a shared script uses.
# Values are (letters, weight): letters a language shares with a neighbour
# (Urdu also writes پ چ گ ی ک) count once, letters nobody else uses count 3x.
_ARABIC_MARKERS = {
    "fa": ("پچژگکی", 1.0),        # Persian ye/kaf + the four extra letters
    "ur": ("ٹڈڑںےۓہھ", 3.0),
    "ar": ("ةىيكأإآؤئ", 1.0),      # Arabic ye/kaf, taa marbuta, hamza seats
    "ps": ("ټډړږښګڼۍې", 3.0),
    "ku": ("ڕڵێۆەڤ", 3.0),
}
_CYRILLIC_MARKERS = {
    "uk": ("ієїґ", 2.0),
    "sr": ("ђјљњћџ", 3.0),
    "kk": ("әғқңөұүһ", 3.0),
    "bg": ("ъщ", 0.6),
    "ru": ("ыэё", 1.5),
}
_DEVANAGARI_WORDS = {
    "mr": {"आहे", "आणि", "नाही", "काय", "आहेत", "मराठी", "होते", "झाले"},
    "ne": {"छ", "हो", "गर्न", "हुन्छ", "नेपाली", "तपाईं", "भएको", "छन्"},
    "hi": {"है", "और", "का", "की", "के", "में", "नहीं", "यह", "हैं", "को", "से", "क्या"},
}

# Latin-script profiles: frequent function words (weight 1) and words that are
# close to unique to the language (weight 2). Kept short on purpose — a title is
# 6-12 words, and a frequent function word is what it will actually contain.
_LATIN = {
    "en": ("the and you how what this with for are was why best new top my your "
           "is of to in it on that from we can get all video make".split(),
           "the you how what this with why your that from".split()),
    "es": ("el la los las de que y en un una por con para es del lo como más pero "
           "mi tu sus muy ya cuando mejor nuevo hacer cómo qué".split(),
           "los las del muy cómo qué cuando pero también así porque".split()),
    "pt": ("o a os as de que e do da em um uma para com não é no na mais como "
           "meu seu muito você isso melhor novo fazer".split(),
           "não você isso muito uma do da são então também ação".split()),
    "fr": ("le la les de des et en un une du pour que qui est pas sur au avec "
           "ce mon ton plus comme mais très nouveau faire".split(),
           "les des une pour qui est pas avec très mais vous nous c'est".split()),
    "de": ("der die das und ist nicht ein eine zu mit von den sich auf für im "
           "es wie was ich du wir mein dein neue beste machen".split(),
           "der die das und ist nicht ein eine mit sich für ich wir".split()),
    "it": ("il la le di che e un una per non con del della sono è come più ma "
           "mio tuo anche questo nuovo fare migliore".split(),
           "il della sono questo anche perché molto gli".split()),
    "nl": ("de het een en van in is dat op te met voor niet zijn je ik wat "
           "hoe nieuwe beste maken".split(),
           "het een van niet zijn voor wat hoe".split()),
    "tr": ("ve bir bu da de için ile ne çok en mi gibi daha var yok ben sen "
           "nasıl yeni şey olan oldu".split(),
           "bir için ile çok gibi nasıl yok şey".split()),
    "id": ("yang dan di ini itu dengan untuk dari ke tidak ada saya kamu apa "
           "bisa juga cara baru terbaik paling".split(),
           "yang dengan untuk tidak saya kamu bisa cara".split()),
    "ms": ("yang dan di ini itu dengan untuk dari ke tidak ada saya awak apa "
           "boleh juga cara baru terbaik paling".split(),
           "boleh awak sahaja kerana".split()),
    "vi": ("và của là có không cho một những với được người này trong đã "
           "các cách mới nhất".split(),
           "của là không những được người này".split()),
    "pl": ("i w z na nie się to jest do że jak co po o od mój twój najlepszy "
           "nowy jak".split(),
           "się jest że nie jak".split()),
    "ro": ("și de la în cu pe nu un o este ce mai din pentru cum care cel "
           "nou cel".split(),
           "și este pentru care".split()),
    "sv": ("och att det som en är på för med inte jag du vi av hur bästa ny".split(),
           "och att det som inte jag".split()),
    "da": ("og at det som en er på for med ikke jeg du vi af hvordan bedste ny".split(),
           "og ikke jeg hvordan".split()),
    "no": ("og at det som en er på for med ikke jeg du vi av hvordan beste ny".split(),
           "og ikke jeg hvordan".split()),
    "fi": ("ja on ei se että kun mitä miten tämä uusi paras olen sinä".split(),
           "että miten tämä olen".split()),
    "cs": ("a v je se na to že s z do jak co jsem nový nejlepší".split(),
           "jsem že jak".split()),
    "sk": ("a v je sa na to že s z do ako čo som nový najlepší".split(),
           "som ako sa".split()),
    "hu": ("a az és hogy nem egy is ez meg van mi hogyan új legjobb".split(),
           "hogy nem egy hogyan".split()),
    "tl": ("ang ng sa na mga at ay ko mo ito si kung paano bagong pinaka".split(),
           "ang ng mga ay paano".split()),
    "az": ("və bir bu üçün ilə nə çox ən necə yeni".split(),
           "və üçün necə".split()),
    "sw": ("na ya wa kwa ni katika la za hii cha jinsi mpya".split(),
           "katika jinsi hii".split()),
    "hr": ("i u je se na da za kako što nije novi najbolji".split(),
           "kako što nije".split()),
    "uz": ("va bu uchun bilan qanday yangi eng".split(),
           "uchun qanday".split()),
}
# Letters only some Latin-script languages use. One sighting is a strong vote.
_LATIN_CHARS = {
    "es": "ñ¿¡", "pt": "ãõç", "fr": "çœèêëàâîïûù", "de": "ßäöü",
    "tr": "ışğİ", "pl": "ąęłńśźż", "ro": "ășțâî", "vi": "đơưạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ",
    "cs": "ěščřžůý", "sk": "ľščťžýäô", "hu": "őű", "sv": "åäö",
    "da": "æøå", "no": "æøå", "fi": "äö", "az": "əğış", "hr": "čćđšž",
    "it": "àèéìòù",
}
_WORD_RE = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)?", re.UNICODE)
_URL_RE = re.compile(r"https?://\S+|www\.\S+|#\S+|@\S+")


# word -> [(lang, weight)], built once: one dict lookup per word instead of a
# pass over every profile.
_WORD_VOTES = {}
for _lang, (_common, _strong) in _LATIN.items():
    _ss = set(_strong)
    for _w in set(_common) | _ss:
        _WORD_VOTES.setdefault(_w, []).append((_lang, 2.0 if _w in _ss else 1.0))
_CHAR_VOTES = {}
for _lang, _chars in _LATIN_CHARS.items():
    for _ch in set(_chars):
        _CHAR_VOTES.setdefault(_ch, []).append(_lang)


def _latin_guess(text):
    low = text.lower()
    words = _WORD_RE.findall(low)
    if not words:
        return "", 0.0
    scores = {}
    for w in words:
        for lang, wt in _WORD_VOTES.get(w, ()):
            scores[lang] = scores.get(lang, 0.0) + wt
    char_hits = {}
    for ch in low:
        if ord(ch) > 0x7F:
            for lang in _CHAR_VOTES.get(ch, ()):
                char_hits[lang] = char_hits.get(lang, 0) + 1
    for lang, hits in char_hits.items():
        scores[lang] = scores.get(lang, 0.0) + min(4.0, 1.5 + hits * 0.5)
    if not scores:
        return "", 0.0
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    best, b = ranked[0]
    second = ranked[1][1] if len(ranked) > 1 else 0.0
    if b < 1.5:
        return "", 0.0
    # Confidence: how much evidence there is, times how clearly it wins.
    amount = min(1.0, b / 7.0)
    margin = (b - second) / b
    conf = round(min(0.95, amount * (0.35 + 0.65 * margin)), 3)
    return best, conf


def detect_text_language(text):
    """(code, confidence 0..1) for a title/description blob, or ('', 0)."""
    text = _URL_RE.sub(" ", text or "")
    counts = {}
    letters = 0
    for ch in text:
        s = _script_of(ch)
        if s:
            counts[s] = counts.get(s, 0) + 1
            letters += 1
    if letters < 3:
        return "", 0.0
    # The dominant non-Latin script, if any. Latin brand names inside a Persian
    # title ("iPhone 16 بررسی") must not out-vote the language it is written in,
    # so a non-Latin script wins from 25% of the letters.
    non_latin = {k: v for k, v in counts.items() if k != "latin"}
    if non_latin:
        script, n = max(non_latin.items(), key=lambda kv: kv[1])
        share = n / letters
        if share >= 0.25:
            conf = round(min(0.97, 0.55 + share * 0.45), 3)
            if script in _SINGLE_SCRIPT:
                return _SINGLE_SCRIPT[script], conf
            if script == "kana":
                return "ja", conf
            if script == "han":
                if counts.get("kana"):
                    return "ja", conf
                return _han_variant(text), round(conf * 0.95, 3)
            if script == "arabic":
                code, k = _marker_vote(text, _ARABIC_MARKERS, default="ar")
                return code, round(conf * k, 3)
            if script == "cyrillic":
                code, k = _marker_vote(text.lower(), _CYRILLIC_MARKERS, default="ru")
                return code, round(conf * k, 3)
            if script == "devanagari":
                words = set(_WORD_RE.findall(text))
                best, hits = "hi", 0
                for code, vocab in _DEVANAGARI_WORDS.items():
                    h = len(words & vocab)
                    if h > hits:
                        best, hits = code, h
                return best, round(conf * (0.95 if hits else 0.8), 3)
    return _latin_guess(text)


# A handful of very frequent characters that differ between the two scripts.
_SIMP = set("这们个为来对说时会过还后没么经发现进实动学种样关应头见长问门马书车东乐买")
_TRAD = set("這們個為來對說時會過還後沒麼經發現進實動學種樣關應頭見長問門馬書車東樂買")


def _han_variant(text):
    s = sum(1 for ch in text if ch in _SIMP)
    t = sum(1 for ch in text if ch in _TRAD)
    return "zh-hant" if t > s else "zh-hans"


def _marker_vote(text, markers, default):
    """Pick the language whose marker letters appear most. (code, factor) —
    the factor trims confidence when no marker was seen at all."""
    best, hits = default, 0.0
    for code, (chars, weight) in markers.items():
        h = sum(1 for ch in text if ch in chars) * weight
        if h > hits:
            best, hits = code, h
    # Persian and Arabic share ی/ک look-alikes; Persian's own four letters (پ چ ژ
    # گ) settle it, so a tie-ish Arabic win with any of them flips to Persian.
    if best == "ar" and any(ch in "پچژگ" for ch in text):
        best = "fa"
    return best, (1.0 if hits >= 2 else (0.85 if hits == 1 else 0.7))


# ═════════════════════════════════════════════════════════════════════════
#  PER-ROW EVIDENCE (memoised on the row)
# ═════════════════════════════════════════════════════════════════════════
def _declared_audio(row):
    if "audio_lang_declared" in row:
        return row.get("audio_lang_declared") or ""
    # Rows cached before v3.39 folded defaultLanguage into audio_lang.
    return row.get("audio_lang") or ""


def row_evidence(row):
    """What the row itself says about its language/country. Cheap after the
    first call: the result is memoised on the row dict."""
    memo = row.get(_MEMO_KEY)
    if isinstance(memo, dict) and memo.get("v") == _DETECT_VERSION:
        return memo
    audio_raw = _declared_audio(row)
    meta_raw = row.get("meta_lang") or ""
    title = row.get("title") or ""
    desc = row.get("description") or ""
    tags = " ".join(row.get("tags") or [])
    # Title counts twice: it is what the creator wrote for THIS video, while a
    # description is often a pasted template in the channel's "business" language.
    t_code, t_conf = detect_text_language(" ".join((title, title, desc[:300], tags)))
    title_code, title_conf = detect_text_language(title)
    if title_code and title_code != t_code and title_conf >= 0.6:
        t_code, t_conf = title_code, title_conf
    memo = {
        "v": _DETECT_VERSION,
        "audio": norm_lang(audio_raw),
        "audio_region": lang_region(audio_raw),
        "meta": norm_lang(meta_raw),
        "chan_lang": norm_lang(row.get("channel_lang") or ""),
        "country": (row.get("channel_country") or "").strip().upper(),
        "text": t_code,
        "text_conf": t_conf,
    }
    try:
        row[_MEMO_KEY] = memo
    except TypeError:
        pass
    return memo


def best_language(row):
    """(code, source) — the single best answer to "what language is this in".
    source is 'audio' | 'meta' | 'text' | ''."""
    ev = row_evidence(row)
    if ev["audio"]:
        # A declared audio language contradicted by a confident title is far more
        # often a stale channel default than a mislabelled title.
        if ev["text"] and ev["text_conf"] >= 0.75 and _family(ev["text"]) != _family(ev["audio"]):
            return ev["text"], "text"
        return ev["audio"], "audio"
    if ev["meta"]:
        return ev["meta"], "meta"
    if ev["text"] and ev["text_conf"] >= 0.3:
        return ev["text"], "text"
    return "", ""


# ═════════════════════════════════════════════════════════════════════════
#  SCORING
# ═════════════════════════════════════════════════════════════════════════
VERIFIED, LIKELY, UNKNOWN, MISMATCH = "verified", "likely", "unknown", "mismatch"


def _verdict(score):
    if score >= 2.5:
        return VERIFIED
    if score >= 1.0:
        return LIKELY
    if score <= -1.5:
        return MISMATCH
    return UNKNOWN


def _lang_hit(have, want):
    """+1 same language, -1 a different one, 0 nothing to compare."""
    if not have or not want:
        return 0
    if have == want:
        return 1
    if _family(have) == _family(want):
        return 0.5           # Simplified vs Traditional: same language, other script
    return -1


def language_score(row, want):
    want = norm_lang(want)
    ev = row_evidence(row)
    score = 0.0
    score += 3.0 * _lang_hit(ev["audio"], want)
    score += 2.0 * _lang_hit(ev["meta"], want)
    hit = _lang_hit(ev["text"], want)
    if hit > 0:
        score += 3.0 * ev["text_conf"] * hit
    elif hit < 0 and ev["text_conf"] >= 0.35:
        score -= 3.0 * ev["text_conf"]
    score += 1.0 * _lang_hit(ev["chan_lang"], want)
    if ev["country"] and want in _COUNTRY_LANGS.get(ev["country"], ()):
        score += 0.5
    # English is the default every upload form starts on: a declared "en" that a
    # confident non-English title contradicts is noise, not evidence against.
    if ev["audio"] == "en" and want != "en" and _lang_hit(ev["text"], want) > 0 \
            and ev["text_conf"] >= 0.5:
        score += 1.5
    return score


def country_score(row, want):
    want = (want or "").upper()
    ev = row_evidence(row)
    score = 0.0
    if ev["country"]:
        score += 3.0 if ev["country"] == want else -3.0
    if ev["audio_region"]:
        score += 2.0 if ev["audio_region"] == want else -1.0
    lang, src = best_language(row)
    if lang:
        conf = 1.0 if src in ("audio", "meta") else max(0.0, min(1.0, ev["text_conf"]))
        spoken = _COUNTRY_LANGS.get(want, set())
        fam_spoken = {_family(x) for x in spoken}
        if lang in spoken or _family(lang) in fam_spoken:
            spread = _LANG_SPREAD.get(lang, 99)
            if spread <= 2:
                score += 1.5 * conf      # Persian→Iran, Thai→Thailand, Polish→Poland
            elif spread <= 4:
                score += 1.0 * conf
        elif spoken:
            score -= 1.5 * conf          # Japanese audio is not a Brazilian channel
    return score


def match(row, lang="", region=""):
    """{'lang': verdict|None, 'region': verdict|None} for the wanted pair."""
    return {
        "lang": _verdict(language_score(row, lang)) if lang else None,
        "region": _verdict(country_score(row, region)) if region else None,
    }


def _keeps(verdict, precision):
    if verdict is None:
        return True
    if precision == "strict":
        return verdict == VERIFIED
    if precision == "broad":
        return verdict != MISMATCH
    return verdict in (VERIFIED, LIKELY)


def passes(row, lang="", region="", precision="smart"):
    if not lang and not region:
        return True
    m = match(row, lang, region)
    return _keeps(m["lang"], precision) and _keeps(m["region"], precision)


def breakdown(rows, lang="", region=""):
    """Counts of each verdict per dimension, for the status line."""
    out = {"lang": {}, "region": {}}
    for r in rows:
        m = match(r, lang, region)
        for dim in ("lang", "region"):
            v = m[dim]
            if v:
                out[dim][v] = out[dim].get(v, 0) + 1
    return out


def pair_warning(lang, region):
    """'' or the English sentence explaining why a combo will return little.
    The caller translates it."""
    lang = norm_lang(lang)
    region = (region or "").upper()
    if not lang or not region:
        return ""
    spoken = country_languages(region)
    if not spoken:
        return ""
    if lang in spoken or _family(lang) in {_family(x) for x in spoken}:
        return ""
    return "mismatch"


def card_label(row):
    """'ES · BR' for the card footer; '≈ES' when the language was inferred
    from the text rather than declared by the creator."""
    ev = row_evidence(row)
    lang, src = best_language(row)
    code = ""
    if lang:
        code = ("ZH" if lang.startswith("zh") else lang.upper())
        if src == "text":
            code = "≈" + code
    country = ev["audio_region"] if (src == "audio" and ev["audio_region"]) else ev["country"]
    return " · ".join(p for p in (code, country) if p)
