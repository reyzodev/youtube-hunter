"""app.qml_backend.i18n_bridge - YouTube Hunter (QML).

Exposes the app's text lookup to QML. The interface is **English only**: `tr()`
returns the string unchanged (the English text is the key), `rtl` is always
false and there is no language switch any more.

QML usage:
    text: I18n.tr("New Extraction Task")
    LayoutMirroring.enabled: I18n.rtl      // always false
"""

from PySide6.QtCore import QObject, Property, Signal, Slot

from app import i18n


class I18nBridge(QObject):
    """Text bridge for QML. English only."""

    languageChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)

    @Slot(str, result=str)
    def tr(self, text):
        """Same lookup as app.i18n.tr — English in, English out."""
        return i18n.tr(text)

    @Property(str, notify=languageChanged)
    def lang(self):
        return i18n.LANG

    @Property(bool, notify=languageChanged)
    def rtl(self):
        return False

    def set_language(self, lang, notify=True):
        """Kept for API compatibility. The app has one language, so this never
        changes anything and reports False (nothing switched)."""
        return False
