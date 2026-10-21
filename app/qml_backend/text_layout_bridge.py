"""app.qml_backend.text_layout_bridge - YouTube Hunter (QML).

Why this exists
---------------
`AppText { selectable: true }` makes text selectable by laying an invisible-ink
TextEdit exactly over the visible Text. A QML `Text` honours `lineHeight`
(1.22, 1.3, ...), but a QML `TextEdit` has no such property: its lines are
always packed at 1.0. So on any selectable text with a custom line height the
selection overlay drifted a little further down on every line, and the
selected run was re-drawn there in `selectedTextColor` — the "doubled, offset
text" you saw when selecting the brief summary.

QML can't reach a TextEdit's block format, but Python can: this bridge sets
the same line height on the TextEdit's QTextDocument (QTextBlockFormat), so
both items break and stack their lines identically.

    TextLayout.syncLineHeight(edit.textDocument, root.lineHeight, root.lineHeightMode)
"""

from PySide6.QtCore import QObject, Slot
from PySide6.QtGui import QTextBlockFormat, QTextCursor

try:  # QQuickTextDocument lives in QtQuick; import it so PySide knows the type
    from PySide6.QtQuick import QQuickTextDocument
except Exception:  # pragma: no cover - QtQuick is always there in this app
    QQuickTextDocument = None

# QTextBlockFormat::LineHeightTypes (plain ints: stable across PySide enum styles)
_SINGLE, _PROPORTIONAL, _FIXED = 0, 1, 2
# QQuickText::LineHeightMode
_QML_FIXED_HEIGHT = 1


def _as_quick_doc(obj):
    if obj is None or QQuickTextDocument is None:
        return None
    if isinstance(obj, QQuickTextDocument):
        return obj
    try:
        import shiboken6
        ptr = shiboken6.getCppPointer(obj)[0]
        return shiboken6.wrapInstance(ptr, QQuickTextDocument)
    except Exception:
        return None


class TextLayoutBridge(QObject):
    """Mirrors a Text's line height onto a TextEdit's document."""

    @Slot(QObject, float, int)
    def syncLineHeight(self, quick_doc, line_height, mode):
        qdoc = _as_quick_doc(quick_doc)
        if qdoc is None:
            return
        try:
            doc = qdoc.textDocument()
        except Exception:
            return
        if doc is None:
            return

        lh = float(line_height or 1.0)
        if int(mode) == _QML_FIXED_HEIGHT:
            kind, value = _FIXED, max(1.0, lh)
        elif abs(lh - 1.0) < 1e-4:
            kind, value = _SINGLE, 0.0
        else:
            kind, value = _PROPORTIONAL, lh * 100.0

        # already applied? (cheap check on the first block)
        first = doc.firstBlock().blockFormat()
        if (doc.blockCount() <= 1
                and int(first.lineHeightType()) == kind
                and abs(first.lineHeight() - value) < 1e-3):
            return

        doc.setUndoRedoEnabled(False)   # read-only overlay: no undo history
        cur = QTextCursor(doc)
        cur.select(QTextCursor.SelectionType.Document)
        fmt = QTextBlockFormat()
        fmt.setLineHeight(value, kind)
        cur.mergeBlockFormat(fmt)
