"""app.qml_backend.premium_cursor - YouTube Hunter "Aura" pointer (v3.27).

Replaces Windows' stock cursors with a hand-drawn, HiDPI-crisp set that matches
the Graphite identity: a graphite arrow with a white rim and soft shadow.
Over anything clickable it becomes a real pointing HAND (index finger up, the
way Windows does it) drawn in the same graphite + white-rim language.
I-beam, resize, and grab cursors are drawn in the same language.

v3.27: the whole set is ~20% smaller (arrow is now 13x20 logical px, close to
the Windows default instead of towering over it), the arrow has classic
proportions, and the "hot" state is a hand instead of a blue arrow.

How: QML keeps choosing the SHAPE (cursorShape: Qt.PointingHandCursor …). Every
time a window's cursor changes Qt sends it QEvent.CursorChange; this filter
swaps a stock shape for our bitmap twin synchronously, before anything paints.
Turn it off with "premium_cursor": false in config.json.
"""

import math

from PySide6.QtCore import QEvent, QObject, QPointF, QRectF, Qt
from PySide6.QtGui import (QBrush, QColor, QCursor, QLinearGradient,
                           QPainter, QPainterPath, QPainterPathStroker, QPen, QPixmap,
                           QTransform, QWindow)

_S = 32  # logical canvas size

_POINTER_EVENTS = frozenset({QEvent.Type.Enter, QEvent.Type.MouseMove,
                             QEvent.Type.HoverMove, QEvent.Type.CursorChange})


def _accent():
    try:
        from app.ui import theme
        return QColor(str(theme.CLR.get("primary", "#3B82F6")))
    except Exception:  # noqa: BLE001
        return QColor("#3B82F6")


def _arrow_path():
    # Classic proportions, 13 x 20.4 logical px, tip at (4.5, 3).
    # The white rim is stroked with round joins, which softens every corner.
    ox, oy = 4.5, 3.0
    pts = ((0, 0), (0, 18.0), (4.6, 14.0), (7.4, 20.4), (10.1, 19.2),
           (7.4, 13.0), (13.0, 13.0))
    p = QPainterPath()
    p.moveTo(ox + pts[0][0], oy + pts[0][1])
    for x, y in pts[1:]:
        p.lineTo(ox + x, oy + y)
    p.closeSubpath()
    return p


def _rrect(x0, y0, x1, y1, r):
    p = QPainterPath()
    p.addRoundedRect(QRectF(x0, y0, x1 - x0, y1 - y0), r, r)
    return p


def _capsule(a, b, w):
    line = QPainterPath(QPointF(*a))
    line.lineTo(QPointF(*b))
    st = QPainterPathStroker()
    st.setWidth(w)
    st.setCapStyle(Qt.PenCapStyle.RoundCap)
    st.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
    return st.createStroke(line)


# x of the gaps between the fingers, and where each gap line starts (the top
# of the shorter finger beside it) - drawn as faint white creases.
_FINGER_GAPS = ((12.8, 10.9), (16.1, 12.0), (19.2, 13.5))
_PALM_TOP = 15.6


def _hand_path():
    # Pointing hand, ~17 x 21 logical px, fingertip (hotspot) at (11, 2.4).
    palm = QPainterPath()
    palm.moveTo(9.2, 13.0)
    for x, y in ((9.2, 19.2), (10.4, 21.8), (12.6, 23.4), (19.6, 23.4),
                 (21.4, 21.4), (22.0, 18.6), (22.0, 13.0)):
        palm.lineTo(x, y)
    palm.closeSubpath()
    parts = (
        _rrect(9.2, 2.4, 12.8, 16.0, 1.8),     # index - the pointer
        _rrect(12.8, 8.6, 16.1, 16.0, 1.65),   # middle (curled)
        _rrect(16.1, 9.8, 19.2, 17.0, 1.55),   # ring
        _rrect(19.2, 11.4, 22.0, 17.6, 1.4),   # little
        palm,
        _capsule((10.4, 19.6), (6.4, 15.0), 3.5),  # thumb
    )
    p = QPainterPath()
    p.setFillRule(Qt.FillRule.WindingFill)
    for part in parts:
        p = p.united(part)
    return p.simplified()


def _double_arrow(length=17.0, w=2.8, head=4.8):
    h = length / 2
    p = QPainterPath()
    p.moveTo(-h, 0)
    p.lineTo(-h + head, -head)
    p.lineTo(-h + head, -w / 2)
    p.lineTo(h - head, -w / 2)
    p.lineTo(h - head, -head)
    p.lineTo(h, 0)
    p.lineTo(h - head, head)
    p.lineTo(h - head, w / 2)
    p.lineTo(-h + head, w / 2)
    p.lineTo(-h + head, head)
    p.closeSubpath()
    return p


def _ibeam():
    p = QPainterPath()
    p.addRoundedRect(QRectF(15.0, 8.4, 2.0, 15.2), 1.0, 1.0)
    p.addRoundedRect(QRectF(12.2, 7.2, 7.6, 2.2), 1.1, 1.1)
    p.addRoundedRect(QRectF(12.2, 22.6, 7.6, 2.2), 1.1, 1.1)
    return p.simplified()


def _grip(closed):
    p = QPainterPath()
    r = 6.0 if closed else 7.2
    p.addEllipse(QPointF(16, 16), r, r)
    return p


class PremiumCursor(QObject):
    def __init__(self, app, parent=None):
        super().__init__(parent or app)
        self._cache = {}
        self._accent_name = ""
        try:
            from app.config import load_app_config
            self._on = bool(load_app_config().get("premium_cursor", True))
        except Exception:  # noqa: BLE001
            self._on = True
        # v3.39.8: window-level, not application-level (see cursor_guard)
        from app.qml_backend.cursor_guard import install_window_filter
        install_window_filter(app, self)

    # ── painting ──
    def _paint(self, kind, dpr):
        accent = _accent()
        px = QPixmap(math.ceil(_S * dpr), math.ceil(_S * dpr))
        px.setDevicePixelRatio(dpr)
        px.fill(Qt.GlobalColor.transparent)
        g = QPainter(px)
        g.setRenderHint(QPainter.RenderHint.Antialiasing)
        closed = kind == "closed"
        if kind == "arrow":
            path = _arrow_path()
        elif kind == "hand":
            path = _hand_path()
        elif kind == "ibeam":
            path = _ibeam()
        elif kind in ("open", "closed"):
            path = _grip(closed)
        else:
            angle = {"hor": 0, "ver": 90, "fdiag": 45, "bdiag": -45}[kind]
            path = QTransform().translate(16, 16).rotate(angle).map(_double_arrow())
        # soft drop shadow: two faint, offset, widening strokes
        g.setBrush(Qt.BrushStyle.NoBrush)
        for (dx, dy, w, a) in ((0.5, 1.3, 4.0, 22), (0.3, 1.0, 2.6, 34)):
            g.setPen(QPen(QColor(0, 0, 0, a), w, Qt.PenStyle.SolidLine,
                          Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
            g.drawPath(path.translated(dx, dy))
        # graphite body (the grab cursor alone turns accent while held)
        grad = QLinearGradient(QPointF(4, 2), QPointF(18, 26))
        if closed:
            grad.setColorAt(0, accent.lighter(120))
            grad.setColorAt(1, accent.darker(115))
        else:
            grad.setColorAt(0, QColor("#2E333D"))
            grad.setColorAt(1, QColor("#121419"))
        g.setBrush(QBrush(grad))
        g.setPen(QPen(QColor(255, 255, 255, 245), 1.35, Qt.PenStyle.SolidLine,
                      Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
        g.drawPath(path)
        if kind == "arrow":  # glassy highlight along the leading edge
            g.setPen(QPen(QColor(255, 255, 255, 56), 0.9, Qt.PenStyle.SolidLine,
                          Qt.PenCapStyle.RoundCap))
            g.drawLine(QPointF(6.0, 6.2), QPointF(6.0, 17.0))
        elif kind == "hand":  # creases between the fingers
            g.setPen(QPen(QColor(255, 255, 255, 120), 0.9, Qt.PenStyle.SolidLine,
                          Qt.PenCapStyle.RoundCap))
            for x, y0 in _FINGER_GAPS:
                g.drawLine(QPointF(x, y0), QPointF(x, _PALM_TOP))
        if kind in ("open", "closed"):  # 4-way chevrons inside the grip
            g.setPen(QPen(QColor(255, 255, 255, 235), 1.4, Qt.PenStyle.SolidLine,
                          Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
            k = 0.85 if closed else 1.0
            for ang in (0, 90, 180, 270):
                t = QTransform().translate(16, 16).rotate(ang).scale(k, k)
                c = QPainterPath()
                c.moveTo(-1.9, -2.6); c.lineTo(0, -4.3); c.lineTo(1.9, -2.6)
                g.drawPath(t.map(c))
        g.end()
        hs = {"arrow": (5, 3), "hand": (11, 3)}.get(kind, (16, 16))
        return QCursor(px, hs[0], hs[1])

    _MAP = {
        Qt.CursorShape.ArrowCursor: "arrow",
        Qt.CursorShape.PointingHandCursor: "hand",
        Qt.CursorShape.IBeamCursor: "ibeam",
        Qt.CursorShape.SizeHorCursor: "hor",
        Qt.CursorShape.SizeVerCursor: "ver",
        Qt.CursorShape.SizeFDiagCursor: "fdiag",
        Qt.CursorShape.SizeBDiagCursor: "bdiag",
        Qt.CursorShape.OpenHandCursor: "open",
        Qt.CursorShape.ClosedHandCursor: "closed",
    }

    def _cursor(self, kind, dpr):
        accent = _accent().name()
        if accent != self._accent_name:  # accent changed in Settings → repaint set
            self._cache.clear()
            self._accent_name = accent
        key = (kind, round(dpr, 2))
        if key not in self._cache:
            self._cache[key] = self._paint(kind, dpr)
        return self._cache[key]

    def eventFilter(self, obj, event):  # noqa: N802
        if self._on and event.type() in _POINTER_EVENTS and isinstance(obj, QWindow):
            try:
                kind = self._MAP.get(obj.cursor().shape())
                if kind:
                    obj.setCursor(self._cursor(kind, obj.devicePixelRatio() or 1.0))
            except Exception:  # noqa: BLE001 - a cursor must never break the app
                pass
        return False
