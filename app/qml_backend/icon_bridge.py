"""app.qml_backend.icon_bridge - YouTube Hunter (QML).

The app draws icons as glyphs from the bundled `remixicon` font (see
app.ui.icons.ICON_MAP, which maps a semantic name to a (line, fill) codepoint
pair). In QML an icon is just a Text element in that font family whose `text`
is the right glyph character.

    Text {
        font.family: "remixicon"
        text: Icons.glyph("search")           // outline
        // or Icons.glyph("bolt", true)       // filled
    }

Glyph lookup lives in app.ui.icons.icon_char (memoised).
"""

from PySide6.QtCore import QObject, Property, Slot

from app.ui import fonts
from app.ui.icons import has_svg, icon_char


class IconBridge(QObject):
    """Semantic-name -> remixicon glyph lookup for QML."""

    @Slot(str, result=str)
    @Slot(str, bool, result=str)
    def glyph(self, name, fill=False):
        return icon_char(name, 1.0 if fill else 0.0)

    @Slot(str, result=bool)
    def hasSvg(self, name):
        """True when `name` has a custom SVG in assets/icons/ (IconGlyph then
        draws it through image://svgicon instead of the font glyph)."""
        return has_svg(name)

    @Property(str, constant=True)
    def family(self):
        """The resolved remixicon family name (set by fonts.load_fonts)."""
        return fonts.FONT_ICON
