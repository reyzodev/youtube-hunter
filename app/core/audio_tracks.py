"""app.core.audio_tracks - YouTube Hunter.

Multi-language audio ("dubbed") tracks: what a video offers, and how to pick
one.

YouTube ships ONE audio stream per language on a dubbed video: the original
track plus creator dubs and YouTube's own auto-dubs (AI voices). yt-dlp exposes
them as separate audio-only formats that differ only in `language`,
`language_preference` (10 = original, 5 = default, -1 = other dub, -10 = audio
description) and `format_note` ("English (United States) original (default)",
"Arabic", "Spanish dubbed-auto", ...).

Shared by the Video Cutter (cutter.py) and the downloader (download.py) so both
show the same list and select the same stream for the same key.

Track KEY:  ""            = the original track (always present, always first)
            "<lang code>" = that dub, exactly as yt-dlp reports `language`
"""

import re

# primary subtag -> (English name, native name, Persian name)
_LANGS = {
    "af": ("Afrikaans", "Afrikaans", "آفریکانس"),
    "am": ("Amharic", "አማርኛ", "امهری"),
    "ar": ("Arabic", "العربية", "عربی"),
    "az": ("Azerbaijani", "Azərbaycan", "آذربایجانی"),
    "be": ("Belarusian", "Беларуская", "بلاروسی"),
    "bg": ("Bulgarian", "Български", "بلغاری"),
    "bn": ("Bengali", "বাংলা", "بنگالی"),
    "bs": ("Bosnian", "Bosanski", "بوسنیایی"),
    "ca": ("Catalan", "Català", "کاتالان"),
    "cs": ("Czech", "Čeština", "چکی"),
    "cy": ("Welsh", "Cymraeg", "ولزی"),
    "da": ("Danish", "Dansk", "دانمارکی"),
    "de": ("German", "Deutsch", "آلمانی"),
    "el": ("Greek", "Ελληνικά", "یونانی"),
    "en": ("English", "English", "انگلیسی"),
    "es": ("Spanish", "Español", "اسپانیایی"),
    "et": ("Estonian", "Eesti", "استونیایی"),
    "eu": ("Basque", "Euskara", "باسکی"),
    "fa": ("Persian", "فارسی", "فارسی"),
    "fi": ("Finnish", "Suomi", "فنلاندی"),
    "fil": ("Filipino", "Filipino", "فیلیپینی"),
    "fr": ("French", "Français", "فرانسوی"),
    "ga": ("Irish", "Gaeilge", "ایرلندی"),
    "gl": ("Galician", "Galego", "گالیسیایی"),
    "gu": ("Gujarati", "ગુજરાતી", "گجراتی"),
    "he": ("Hebrew", "עברית", "عبری"),
    "iw": ("Hebrew", "עברית", "عبری"),
    "hi": ("Hindi", "हिन्दी", "هندی"),
    "hr": ("Croatian", "Hrvatski", "کرواتی"),
    "hu": ("Hungarian", "Magyar", "مجاری"),
    "hy": ("Armenian", "Հայերեն", "ارمنی"),
    "id": ("Indonesian", "Bahasa Indonesia", "اندونزیایی"),
    "is": ("Icelandic", "Íslenska", "ایسلندی"),
    "it": ("Italian", "Italiano", "ایتالیایی"),
    "ja": ("Japanese", "日本語", "ژاپنی"),
    "jv": ("Javanese", "Basa Jawa", "جاوه‌ای"),
    "ka": ("Georgian", "ქართული", "گرجی"),
    "kk": ("Kazakh", "Қазақ", "قزاقی"),
    "km": ("Khmer", "ខ្មែរ", "خمری"),
    "kn": ("Kannada", "ಕನ್ನಡ", "کانادا"),
    "ko": ("Korean", "한국어", "کره‌ای"),
    "ku": ("Kurdish", "Kurdî", "کردی"),
    "ky": ("Kyrgyz", "Кыргызча", "قرقیزی"),
    "lo": ("Lao", "ລາວ", "لائوسی"),
    "lt": ("Lithuanian", "Lietuvių", "لیتوانیایی"),
    "lv": ("Latvian", "Latviešu", "لتونیایی"),
    "mk": ("Macedonian", "Македонски", "مقدونی"),
    "ml": ("Malayalam", "മലയാളം", "مالایالم"),
    "mn": ("Mongolian", "Монгол", "مغولی"),
    "mr": ("Marathi", "मराठी", "مراتی"),
    "ms": ("Malay", "Bahasa Melayu", "مالایی"),
    "my": ("Burmese", "မြန်မာ", "برمه‌ای"),
    "ne": ("Nepali", "नेपाली", "نپالی"),
    "nl": ("Dutch", "Nederlands", "هلندی"),
    "no": ("Norwegian", "Norsk", "نروژی"),
    "nb": ("Norwegian", "Norsk", "نروژی"),
    "pa": ("Punjabi", "ਪੰਜਾਬੀ", "پنجابی"),
    "pl": ("Polish", "Polski", "لهستانی"),
    "ps": ("Pashto", "پښتو", "پشتو"),
    "pt": ("Portuguese", "Português", "پرتغالی"),
    "ro": ("Romanian", "Română", "رومانیایی"),
    "ru": ("Russian", "Русский", "روسی"),
    "si": ("Sinhala", "සිංහල", "سینهالی"),
    "sk": ("Slovak", "Slovenčina", "اسلواکی"),
    "sl": ("Slovenian", "Slovenščina", "اسلوونیایی"),
    "sq": ("Albanian", "Shqip", "آلبانیایی"),
    "sr": ("Serbian", "Српски", "صربی"),
    "sv": ("Swedish", "Svenska", "سوئدی"),
    "sw": ("Swahili", "Kiswahili", "سواحیلی"),
    "ta": ("Tamil", "தமிழ்", "تامیلی"),
    "te": ("Telugu", "తెలుగు", "تلوگو"),
    "tg": ("Tajik", "Тоҷикӣ", "تاجیکی"),
    "th": ("Thai", "ไทย", "تایلندی"),
    "tl": ("Filipino", "Filipino", "فیلیپینی"),
    "tr": ("Turkish", "Türkçe", "ترکی"),
    "uk": ("Ukrainian", "Українська", "اوکراینی"),
    "ur": ("Urdu", "اردو", "اردو"),
    "uz": ("Uzbek", "Oʻzbek", "ازبکی"),
    "vi": ("Vietnamese", "Tiếng Việt", "ویتنامی"),
    "zh": ("Chinese", "中文", "چینی"),
    "zu": ("Zulu", "isiZulu", "زولو"),
}

# region subtags worth naming ("Portuguese · Brazil" vs "· Portugal")
_REGIONS = {
    "us": ("US", "آمریکا"), "gb": ("UK", "بریتانیا"), "in": ("India", "هند"),
    "br": ("Brazil", "برزیل"), "pt": ("Portugal", "پرتغال"),
    "es": ("Spain", "اسپانیا"), "mx": ("Mexico", "مکزیک"),
    "419": ("Latin America", "آمریکای لاتین"), "fr": ("France", "فرانسه"),
    "ca": ("Canada", "کانادا"), "cn": ("China", "چین"), "tw": ("Taiwan", "تایوان"),
    "hk": ("Hong Kong", "هنگ‌کنگ"), "au": ("Australia", "استرالیا"),
    "hans": ("Simplified", "ساده‌شده"), "hant": ("Traditional", "سنتی"),
}

_RTL = {"ar", "fa", "he", "iw", "ur", "ps", "ku"}


def _is_audio_only(f):
    return ((f.get("vcodec") or "none") == "none"
            and (f.get("acodec") or "none") != "none")


def _note(f):
    return str(f.get("format_note") or "").lower()


def is_descriptive(f):
    """The audio-description track (narrated for blind viewers) — never a
    candidate for "the sound of this video"."""
    n = _note(f)
    try:
        lp = float(f.get("language_preference") or 0)
    except (TypeError, ValueError):
        lp = 0.0
    return "descriptive" in n or "audio description" in n or lp <= -10


def _is_original(f):
    try:
        lp = float(f.get("language_preference") or -1)
    except (TypeError, ValueError):
        lp = -1.0
    return "original" in _note(f) or lp >= 10


def _is_auto_dub(f):
    n = _note(f)
    return ("dubbed-auto" in n or "auto-dubbed" in n or "auto dubbed" in n
            or "ai-dub" in n or "dubbed (auto" in n)


def _display_from_note(f):
    """yt-dlp's displayName part of format_note: "Arabic", "English (US)"."""
    raw = str(f.get("format_note") or "")
    raw = raw.split(",")[0]
    raw = re.sub(r"\(default\)|\boriginal\b|\bdubbed-auto\b|\bdubbed\b|"
                 r"\bdescriptive\b", "", raw, flags=re.I)
    return re.sub(r"\s+", " ", raw).strip(" -·")


def lang_names(code, fallback=""):
    """(English, native, Persian) for a BCP-47-ish code ("pt-BR", "es-419")."""
    code = str(code or "")
    parts = re.split(r"[-_]", code.lower())
    prim = parts[0] if parts else ""
    base = _LANGS.get(prim)
    if not base:
        name = fallback or code or "Unknown"
        return name, name, name
    en, native, fa = base
    if len(parts) > 1:
        reg = _REGIONS.get(parts[1])
        if reg:
            en = f"{en} · {reg[0]}"
            fa = f"{fa} · {reg[1]}"
    return en, native, fa


def _abr(f):
    try:
        return float(f.get("abr") or f.get("tbr") or 0)
    except (TypeError, ValueError):
        return 0.0


def audio_tracks_from_formats(formats):
    """The audio tracks a video offers, original first.

    [] when the video has a single language (nothing to choose). Each entry:
      key       "" for the original, else the yt-dlp language code
      lang      language code ("" when unknown)
      name      English name ("Arabic", "Portuguese · Brazil")
      native    the language in its own script ("العربية")
      nameFa    Persian name
      kind      "original" | "dub" | "auto"  (auto = YouTube's AI voice)
      kbps      best bitrate on offer for that track
      rtl       native name is right-to-left
    """
    groups = {}
    order = []
    for f in formats or []:
        if not isinstance(f, dict) or not _is_audio_only(f) or not f.get("url"):
            continue
        if is_descriptive(f):
            continue
        lang = str(f.get("language") or "")
        g = groups.get(lang)
        if g is None:
            g = {"lang": lang, "orig": False, "auto": False, "kbps": 0.0,
                 "lp": -99.0, "display": ""}
            groups[lang] = g
            order.append(lang)
        g["orig"] = g["orig"] or _is_original(f)
        g["auto"] = g["auto"] or _is_auto_dub(f)
        g["kbps"] = max(g["kbps"], _abr(f))
        try:
            g["lp"] = max(g["lp"], float(f.get("language_preference")
                                         if f.get("language_preference") is not None else -1))
        except (TypeError, ValueError):
            pass
        if not g["display"]:
            g["display"] = _display_from_note(f)
    if len(groups) < 2:
        return []
    orig_lang = max(order, key=lambda k: (1 if groups[k]["orig"] else 0,
                                          groups[k]["lp"]))
    out = []
    for lang in [orig_lang] + sorted(
            (k for k in order if k != orig_lang),
            key=lambda k: lang_names(k, groups[k]["display"])[0].lower()):
        g = groups[lang]
        en, native, fa = lang_names(lang, g["display"])
        is_orig = lang == orig_lang
        out.append({
            "key": "" if is_orig else lang,
            "lang": lang,
            "code": (lang.split("-")[0] or "?").upper()[:3],
            "name": en,
            "native": native,
            "nameFa": fa,
            "kind": "original" if is_orig else ("auto" if g["auto"] else "dub"),
            "kbps": int(round(g["kbps"])),
            "rtl": lang.split("-")[0].lower() in _RTL,
        })
    return out


def _lang_rank(f):
    try:
        lp = float(f.get("language_preference")
                   if f.get("language_preference") is not None else -1)
    except (TypeError, ValueError):
        lp = -1.0
    return (1 if _is_original(f) else 0, lp, 0 if is_descriptive(f) else 1)


def select_audio(auds, lang=""):
    """Narrow audio-only formats to ONE language.

    lang ""  -> the original track (highest language rank)
    lang "x" -> exactly that language; falls back to the original when the
                video doesn't (or no longer) ship it.
    A single-language video is returned untouched."""
    auds = [a for a in (auds or []) if isinstance(a, dict)]
    if not auds:
        return auds
    if lang:
        hit = [a for a in auds if str(a.get("language") or "") == lang
               and not is_descriptive(a)]
        if hit:
            return hit
    top = max(_lang_rank(a) for a in auds)
    keep = [a for a in auds if _lang_rank(a) == top]
    return keep or auds


def lang_format_expr(expr, lang):
    """A yt-dlp format expression that takes the `lang` audio track.

    Every `bestaudio` alternative gets a [language=...] filter; the untouched
    expression follows as the fallback, so a dub that disappears never turns
    into a failed download (the "lang" format_sort then takes the original)."""
    if not lang or not expr:
        return expr
    safe = re.sub(r"[^\w-]", "", lang)
    if not safe:
        return expr
    # Only the alternatives that name an audio stream get a strict twin, so a
    # progressive "best" rung (default track only) can't jump the queue.
    alts = [a for a in expr.split("/") if re.search(r"\bbestaudio\b", a)]
    if not alts:
        return expr
    strict = "/".join(re.sub(r"\bbestaudio\b", f"bestaudio[language={safe}]", a)
                      for a in alts)
    return f"{strict}/{expr}"
