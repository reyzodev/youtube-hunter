"""app.i18n - Youtube Scrapper."""

from app.locales.fa import FA_STRINGS

# ═════════════════════════════════════════════════════════════════════════
#  INTERNATIONALIZATION (English / Persian)
# ═════════════════════════════════════════════════════════════════════════
LANG = "en"   # set at startup from config.json; "en" or "fa"


def tr(text):
    """Translate an English UI string to the active language. English text
    itself is used as the lookup key, so untranslated strings just pass
    through unchanged."""
    if LANG == "fa":
        return FA_STRINGS.get(text, text)
    return text
