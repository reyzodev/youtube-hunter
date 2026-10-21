"""app.ui.fonts - Youtube Scrapper."""

import os

from PySide6.QtGui import QFont, QFontDatabase

from app import i18n
from app.paths import BASE_DIR

FONT_ICON = "remixicon"
FONT_MONO = "JetBrains Mono"
FONT_BODY = "Hanken Grotesk"

# ── PERSIAN (Vazir) UI FONT ──
# v3.37: the Persian UI face is Vazir (v16.1.0) instead of IRANYekanX. Unlike
# IRANYekanX (one family PER weight file), every Vazir-*.ttf reports the SAME
# family name "Vazir" with a real OS/2 weight, so Qt picks the right face from
# font.weight on its own. FONT_FA_FAMILIES still maps {weight: family} (all
# "Vazir") so the old per-weight call sites keep working, and FA_WEIGHTS holds
# the weights that really ship, so a request can be SNAPPED to a real face
# (see fa_weight_for) instead of letting Qt fake a synthetic bold.
FONT_FA_FAMILIES = {}   # {weight_int: family_name}
FONT_FA_DEFAULT = "Vazir"

# Vazir(matn) is used ONLY for the Content Lab PDF export, not the general
# app UI (which stays on IRANYekanX above) — it's a separate, deliberate
# choice for print output specifically. Unlike IRANYekanX, every Vazirmatn
# weight file reports the SAME family name ("Vazirmatn"), so one global is
# enough; the PDF's CSS selects weight numerically (font-weight:400/600/700)
# rather than swapping family names. Falls back to FONT_FA_DEFAULT so PDF
# export still works (just not in Vazir) if these files aren't present yet.
FONT_VAZIR = None


def load_fonts():
    """Load bundled fonts (Latin UI + Material Symbols + Persian IRANYekanX
    + Vazir for PDF export); falls back to system fonts if a file is missing."""
    global FONT_ICON, FONT_MONO, FONT_BODY, FONT_FA_DEFAULT, FONT_VAZIR
    base = BASE_DIR
    fonts_dir = os.path.join(base, "fonts")
    mapping = [
        # Remix Icon (https://remixicon.com) — every glyph ships as a
        # -line (outline) and -fill (solid) pair, so unlike the old Fontello
        # build the "filled when active" state uses a real solid face rather
        # than a synthesised dilation (see app/ui/icons.py).
        ("remixicon.ttf", "icon"),
        ("JetBrainsMono-Regular.ttf", "mono"),
        ("HankenGrotesk.ttf", "body"),
    ]
    result = {}
    for fname, key in mapping:
        if key in result:
            continue
        path = os.path.join(fonts_dir, fname)
        if os.path.exists(path):
            fid = QFontDatabase.addApplicationFont(path)
            fams = QFontDatabase.applicationFontFamilies(fid)
            if fams:
                result[key] = fams[0]
    if "icon" in result:
        FONT_ICON = result["icon"]
    if "mono" in result:
        FONT_MONO = result["mono"]
    if "body" in result:
        FONT_BODY = result["body"]

    # ---- Persian UI (Vazir) — five real weights, one shared family ----
    fa_mapping = [
        ("Vazir-Thin.ttf", 100),
        ("Vazir-Light.ttf", 300),
        ("Vazir.ttf", 400),
        ("Vazir-Medium.ttf", 500),
        ("Vazir-Bold.ttf", 700),
    ]
    for fname, weight in fa_mapping:
        path = os.path.join(fonts_dir, fname)
        if os.path.exists(path):
            fid = QFontDatabase.addApplicationFont(path)
            fams = QFontDatabase.applicationFontFamilies(fid)
            if fams:
                FONT_FA_FAMILIES[weight] = fams[0]
    if 400 in FONT_FA_FAMILIES:
        FONT_FA_DEFAULT = FONT_FA_FAMILIES[400]
    elif FONT_FA_FAMILIES:
        FONT_FA_DEFAULT = next(iter(FONT_FA_FAMILIES.values()))

    install_persian_fallback()

    # ---- Vazir(matn) — PDF export only; every weight shares one family ----
    vazir_files = ("Vazirmatn-Regular.ttf", "Vazirmatn-Medium.ttf",
                  "Vazirmatn-SemiBold.ttf", "Vazirmatn-Bold.ttf")
    for fname in vazir_files:
        path = os.path.join(fonts_dir, fname)
        if os.path.exists(path):
            fid = QFontDatabase.addApplicationFont(path)
            fams = QFontDatabase.applicationFontFamilies(fid)
            if fams and not FONT_VAZIR:
                FONT_VAZIR = fams[0]
import re as _re

# Arabic-script letters (Persian included) + the presentation-form blocks.
_FA_CHARS = _re.compile(r"[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]")


def install_persian_fallback():
    """Make Vazir the glyph fallback of the Latin UI faces.

    Hanken Grotesk / JetBrains Mono have no Persian glyphs, so on an English
    UI every Persian string — a Persian channel title, an AI answer, a chat
    message, a blueprint written in Persian — fell through to whatever the OS
    picked (Segoe UI / Tahoma on Windows): wrong shapes, wrong metrics, and it
    looked like a different app. Registering IRANYekanX as the substitute of
    the Latin families makes Qt take the missing glyphs from IRANYekanX, for
    QML Text, TextField/TextArea, Markdown and QWidgets alike — Latin text is
    untouched because the Latin face still has those glyphs."""
    fa = [f for f in (FONT_FA_DEFAULT,) if f]
    if not fa:
        return
    for latin in (FONT_BODY, FONT_MONO):
        if latin and latin not in fa:
            try:
                QFont.insertSubstitutions(latin, fa)
            except Exception:
                pass


def is_mostly_persian(text, share=0.25):
    """True when Persian letters are a real part of `text` (not one stray
    character in an English sentence). Used to give such text the matching
    IRANYekanX WEIGHT family on an English UI — the glyph fallback above
    alone only ever yields the Regular face."""
    t = text or ""
    if not t or not _FA_CHARS.search(t):
        return False
    fa = len(_FA_CHARS.findall(t))
    latin = sum(1 for ch in t if ("a" <= ch <= "z") or ("A" <= ch <= "Z"))
    return fa >= share * max(1, fa + latin)


def fa_weight_for(weight):
    """Snap a requested weight to the nearest weight Vazir really ships
    (100/300/400/500/700). Ties go to the HEAVIER face (600 -> 700), so a
    DemiBold label stays visibly bold. Anything above 700 lands on Bold."""
    target = int(weight) if weight and int(weight) > 0 else 400
    have = sorted(FONT_FA_FAMILIES) or [100, 300, 400, 500, 700]
    return min(have, key=lambda w: (abs(w - target), -w))


def _fa_family_for_weight(weight):
    """Resolve the IRANYekanX family whose static weight is closest to the
    one requested. Each IRANYekanX-*.ttf (Thin..Heavy) ships as its OWN font
    family — unlike the Latin fonts, they are NOT weight faces of a single
    shared family — so asking Qt for "IRANYekanX Regular" at QFont.Bold only
    gets a synthetic (faux) bold smeared onto the Regular outline. Picking
    the matching family up front gives the real, properly hinted face."""
    if not FONT_FA_FAMILIES:
        return FONT_FA_DEFAULT
    target = weight if weight and weight > 0 else QFont.Normal  # unset → Regular
    nearest = min(FONT_FA_FAMILIES, key=lambda w: abs(w - target))
    return FONT_FA_FAMILIES[nearest]


def AppFont(base_family, size, weight=-1, italic=False):
    """Drop-in QFont(family, size, weight, italic) replacement that swaps in
    the correct IRANYekanX weight family whenever the UI language is
    Persian and the requested family is one of the app's Latin body/mono
    fonts (see _fa_family_for_weight — each IRANYekanX weight is its own
    family, so the *family* is swapped rather than relying on Qt's
    synthetic weight engine to fake a heavier face).
    Behaves exactly like QFont(...) when the language is English."""
    if i18n.LANG == "fa" and base_family in (FONT_BODY, FONT_MONO):
        f = QFont(_fa_family_for_weight(weight), size)
        f.setWeight(QFont.Weight(fa_weight_for(weight)))
        f.setItalic(italic)
        return f
    f = QFont(base_family, size, weight)
    f.setItalic(italic)
    return f


def FaFont(base_family, size, weight=-1, italic=False):
    """Like AppFont, but always resolves to the IRANYekanX family —
    regardless of the active UI language. For widgets that are meant to
    render in IRANYekanX on purpose even while the rest of the app is in
    English (currently just the AI Channel Analysis / "Show Analysis"
    popup, CSVAnalysisDialog). `base_family` is accepted only so call
    sites read the same as an AppFont(...) call; it isn't otherwise used."""
    f = QFont(_fa_family_for_weight(weight), size)
    f.setWeight(QFont.Weight(fa_weight_for(weight)))
    f.setItalic(italic)
    return f


def qss_family(kind="body"):
    """Font stack for a QSS `font-family:` declaration.

    AppFont() already swaps in IRANYekanX for widgets built in Python, but a
    stylesheet rule wins over a widget's own QFont for any property it sets —
    so every `font-family: 'JetBrains Mono'` in build_stylesheet() was quietly
    overriding that swap and dropping those widgets back onto a Latin-only
    face. Persian text then rendered in whatever fallback the platform picked
    (wrong shapes, no joining, mismatched metrics), which is exactly the
    "the Persian font applies in some places and not others" symptom.

    Returning a STACK rather than one family fixes it in both directions:
    Persian first while the UI is Persian (Latin digits/labels still resolve
    through the second entry), Latin first otherwise with IRANYekanX behind
    it so a Persian channel title inside an English UI still shapes
    correctly."""
    latin = FONT_MONO if kind == "mono" else FONT_BODY
    fa = FONT_FA_DEFAULT
    order = (fa, latin) if i18n.LANG == "fa" else (latin, fa)
    seen, out = set(), []
    for fam in order:
        if fam and fam not in seen:
            seen.add(fam)
            out.append("'%s'" % fam)
    return ", ".join(out)


def qss_body():
    return qss_family("body")


def qss_mono():
    return qss_family("mono")
