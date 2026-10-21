"""app.qml_backend.i18n_bridge - YouTube Hunter (QML).

Makes the existing translation table (app.i18n.tr + app.locales.fa.FA_STRINGS)
callable from QML, and drives the app-wide layout direction.

QML usage:
    text: I18n.tr("New Extraction Task")
    LayoutMirroring.enabled: I18n.rtl
    LayoutMirroring.childrenInherit: true

Making a language switch actually repaint takes TWO steps, and only the second
one is obvious:

  * `languageChanged` refreshes the notifying properties (`lang`, `rtl`), so
    layout direction flips on its own.
  * `I18n.tr(...)` is a Slot CALL, and a QML binding records no dependency on a
    function's return value — emitting a signal will never re-run it. What does
    re-run every binding that mentions `I18n` is re-assigning the context
    property itself. `AppController.setLanguage` does that (see
    `_retranslate_context`); the bridge only has to flip the language and notify.
"""

from PySide6.QtCore import QObject, Property, Signal, Slot

from app import i18n


class I18nBridge(QObject):
    """Translation + text-direction bridge for QML."""

    languageChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)

    @Slot(str, result=str)
    def tr(self, text):
        """Same lookup as app.i18n.tr — English key in, active-language out."""
        return i18n.tr(text)

    @Property(str, notify=languageChanged)
    def lang(self):
        return i18n.LANG

    @Property(bool, notify=languageChanged)
    def rtl(self):
        return i18n.LANG == "fa"

    def set_language(self, lang, notify=True):
        """'en' | 'fa'. Anything else falls back to English.

        v3.37: `notify=False` flips the language WITHOUT emitting
        languageChanged. AppController.setLanguage re-assigns the `I18n`
        context property right after, which re-runs every binding that
        mentions I18n (rtl / lang included) anyway, so the signal only bought
        an extra full relayout pass with the OLD strings and fonts."""
        lang = lang if lang in ("en", "fa") else "en"
        if lang == i18n.LANG:
            return False
        i18n.LANG = lang
        if notify:
            self.languageChanged.emit()
        return True
