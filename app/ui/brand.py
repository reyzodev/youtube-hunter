"""app.ui.brand - YouTube Hunter brand mark, painted in code.

The same geometry BrandMark.qml draws (738 x 812 design box). Painting it with
QPainter lets the window / taskbar icon follow the live theme accent the way
the in-app logo does: main_qml re-applies `window_icon()` whenever the theme
bridge reports a palette change.

`render_logo()` is also what tools can use to re-export assets/logo.png.
"""

from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import (QColor, QIcon, QImage, QLinearGradient, QPainter,
                           QPen, QPixmap, QPolygonF)

from app.ui import theme

VB_W, VB_H = 738.0, 812.0

PIECES = {
    "pillarL": [(156, 240), (231, 322), (231, 444), (310, 524), (318, 662), (363, 804), (156, 526)],
    "pillarR": [(582, 526), (375, 804), (420, 662), (428, 524), (507, 444), (507, 322), (582, 240)],
    "crown": [(0, 0), (304, 146), (304, 260), (369, 304), (434, 260), (434, 146), (738, 0),
              (475, 307), (475, 477), (418, 532), (410, 662), (369, 812), (328, 662),
              (320, 532), (263, 477), (263, 307)],
}
PLAY = [(324, 351), (427, 422), (324, 493)]


def _poly(pts):
    return QPolygonF([QPointF(x, y) for x, y in pts])


def _accent():
    return QColor(str(theme.CLR.get("logo_grad_in") or "#FF1F44"))


def _accent_out():
    return QColor(str(theme.CLR.get("logo_grad_out") or "#CC0026"))


def render_logo(size, color_a=None, color_b=None, margin=0.04):
    """The mark as a transparent square QImage, `size` px."""
    a = QColor(color_a) if color_a else _accent()
    b = QColor(color_b) if color_b else _accent_out()
    dark = a.darker(210)
    deep = a.darker(420)

    img = QImage(size, size, QImage.Format_ARGB32_Premultiplied)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing, True)
    avail = size * (1 - 2 * margin)
    k = min(avail / VB_W, avail / VB_H)
    p.translate((size - VB_W * k) / 2, (size - VB_H * k) / 2)
    p.scale(k, k)

    rim = QPen(QColor(255, 255, 255, 40))
    rim.setWidthF(max(1.5, 1.0 / k))
    rim.setJoinStyle(Qt.MiterJoin)

    for name in ("pillarL", "pillarR", "crown"):
        if name == "crown":
            g = QLinearGradient(0, 0, 0, 812)
            g.setColorAt(0.0, a); g.setColorAt(0.40, b)
            g.setColorAt(0.78, dark); g.setColorAt(1.0, deep)
        else:
            g = QLinearGradient(0, 240, 0, 804)
            g.setColorAt(0.0, a); g.setColorAt(0.45, b); g.setColorAt(1.0, dark)
        p.setBrush(g)
        p.setPen(rim if size >= 48 else Qt.NoPen)
        p.drawPolygon(_poly(PIECES[name]))

    p.setPen(Qt.NoPen)
    p.setBrush(QColor("#FFFFFF"))
    p.drawPolygon(_poly(PLAY))
    p.end()
    return img


def window_icon():
    """Multi-size icon in the current accent."""
    icon = QIcon()
    for s in (16, 24, 32, 48, 64, 128, 256):
        icon.addPixmap(QPixmap.fromImage(render_logo(s, margin=0.02 if s <= 32 else 0.04)))
    return icon
