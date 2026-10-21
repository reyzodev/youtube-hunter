"""app.qml_backend.font_bridge - YouTube Hunter (QML).

v3.37: the Persian face is Vazir (one family, real weights; see
app.ui.fonts.fa_weight_for). Historically IRANYekanX shipped as one font FAMILY per weight (Thin ..
Heavy are NOT weight faces of a shared family — see app.ui.fonts). QML's
`font.weight` therefore can't pick the right Persian face on its own; the
FAMILY has to be swapped per weight instead. This bridge exposes that mapping
so QML can ask for the correct family for a given (role, weight) while the UI
language is Persian, and get the Latin family (Hanken Grotesk / JetBrains Mono)
otherwise — exactly mirroring app.ui.fonts.AppFont / qss_family.

    Text {
        font.family: Fonts.family("body", 800)   // ExtraBold
        font.pixelSize: 29
    }
"""

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QFont

from app import i18n
from app.ui import fonts as _fonts


class FontBridge(QObject):
    """Language- and weight-aware font family resolver for QML."""

    languageChanged = Signal()

    @Slot(str, result=str)
    @Slot(str, int, result=str)
    def family(self, role="body", weight=QFont.Normal):
        """role: 'body' | 'mono'. Returns the family QML should set on
        font.family so Persian resolves to the right IRANYekanX weight-family
        and Latin stays on Hanken/JetBrains."""
        latin = _fonts.FONT_MONO if role == "mono" else _fonts.FONT_BODY
        if i18n.LANG == "fa":
            return _fonts._fa_family_for_weight(int(weight))
        return latin

    @Slot(str, int, str, result=str)
    def familyFor(self, role, weight, text):
        """Like family(), but text-aware: on an English UI a string that is
        mostly Persian gets the IRANYekanX family of the right weight instead
        of the Latin face (whose missing Persian glyphs would otherwise come
        from the Regular-only fallback). Everything else is unchanged."""
        if i18n.LANG != "fa" and _fonts.is_mostly_persian(text):
            return _fonts._fa_family_for_weight(int(weight))
        return self.family(role, weight)

    @Slot(int, result=int)
    def weight(self, weight):
        """font.weight companion of family(): on a Persian UI the request is
        snapped to a weight Vazir really ships (no synthetic bold)."""
        if i18n.LANG == "fa":
            return _fonts.fa_weight_for(int(weight))
        return int(weight)

    @Slot(int, str, result=int)
    def weightFor(self, weight, text):
        """font.weight companion of familyFor() (text-aware)."""
        if i18n.LANG == "fa" or _fonts.is_mostly_persian(text):
            return _fonts.fa_weight_for(int(weight))
        return int(weight)

    @Property(str, notify=languageChanged)
    def body(self):
        return self.family("body", QFont.Normal)

    @Property(str, notify=languageChanged)
    def mono(self):
        return self.family("mono", QFont.Normal)

    @Property(str, constant=True)
    def icon(self):
        return _fonts.FONT_ICON

    def _language_changed(self):
        self.languageChanged.emit()
