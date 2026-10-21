"""app.i18n - YouTube Hunter.

The interface ships in English only. This module keeps the historical `tr()`
lookup so every call site (and every QML `I18n.tr(...)`) keeps working: the
English string IS the key, so `tr()` returns it unchanged.
"""

LANG = "en"


def tr(text):
    """Return the UI string. English only — the key is the text."""
    return text
