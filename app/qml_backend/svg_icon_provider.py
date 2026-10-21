"""app.qml_backend.svg_icon_provider - YouTube Hunter (QML).

Serves the custom SVG icons in assets/icons/ to QML as
`image://svgicon/<name>/<line|fill>/<hex colour without #>`.

The SVGs are drawn with `currentColor`; this provider swaps it for the
requested colour and rasterises with QSvgRenderer at the exact pixel size QML
asks for (IconGlyph passes size × devicePixelRatio), so the icons stay crisp on
any DPI and recolour like font glyphs do. Rendering a 15-30 px icon costs
microseconds, so this is a plain synchronous provider; QML's image cache keeps
each (name, face, colour, size) after the first request.
"""

import time
from collections import OrderedDict, deque

from PySide6.QtCore import QByteArray, QRectF, QSize, Qt, QTimer
from PySide6.QtGui import QColor, QImage, QPainter
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtSvg import QSvgRenderer

from app.ui.icons import svg_file

_TEXT_CACHE = {}
# v8: almost every icon is an SVG now, and hover colour fades request a new
# (name, face, colour, size) each frame, so finished images are memoised.
# v3.39.6: LRU instead of "clear everything at 2048". The old wholesale clear
# could fire right in the middle of a theme swap and throw away every icon at
# once; now only the least recently used ones go.
_IMG_CACHE = OrderedDict()
_IMG_CACHE_MAX = 6144
# Every (id, w, h) QML has asked for, most recent last. The theme pre-warm
# reads this to know which icons the NEXT palette will need.
_SEEN = OrderedDict()
_SEEN_MAX = 4096
_seen_version = 0          # bumps whenever a NEW (id, w, h) shows up


def _svg_text(path):
    txt = _TEXT_CACHE.get(path)
    if txt is None:
        try:
            with open(path, "r", encoding="utf-8") as f:
                txt = f.read()
        except OSError:
            txt = ""
        _TEXT_CACHE[path] = txt
    return txt


# v3.39.8: every icon is single-colour (`currentColor` only), so the SVG is
# parsed and rasterised ONCE per (name, face, size) into a coverage mask, and a
# colour is applied with a SourceIn fill. A recolour (theme swap, accent change,
# hover fade) used to re-parse the SVG text and re-run QSvgRenderer every time;
# now it is a QImage copy + one fillRect in C++ — roughly 20-50x cheaper, which
# is what made a theme switch with many built pages stutter.
_MASK_CACHE = OrderedDict()
_MASK_CACHE_MAX = 2048


def _mask(name, fill, w, h):
    """The icon's coverage (opaque black where it draws), memoised."""
    key = (name, fill, w, h)
    hit = _MASK_CACHE.get(key)
    if hit is not None:
        _MASK_CACHE.move_to_end(key)
        return hit
    img = QImage(QSize(w, h), QImage.Format.Format_ARGB32_Premultiplied)
    img.fill(Qt.GlobalColor.transparent)
    path = svg_file(name, fill)
    if path:
        svg = _svg_text(path).replace("currentColor", "#000000")
        renderer = QSvgRenderer(QByteArray(svg.encode("utf-8")))
        if renderer.isValid():
            p = QPainter(img)
            p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
            p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
            renderer.render(p, QRectF(0, 0, w, h))
            p.end()
    _MASK_CACHE[key] = img
    while len(_MASK_CACHE) > _MASK_CACHE_MAX:
        _MASK_CACHE.popitem(last=False)
    return img


def _render(id_, w, h):
    """Rasterise one icon request (and memoise it). Returns a QImage."""
    key = (id_, w, h)
    hit = _IMG_CACHE.get(key)
    if hit is not None:
        _IMG_CACHE.move_to_end(key)
        return hit

    parts = (id_ or "").split("/")
    name = parts[0] if parts else ""
    fill = len(parts) > 1 and parts[1] == "fill"
    hexcol = parts[2] if len(parts) > 2 else "000000"
    color = QColor("#" + hexcol)
    if not color.isValid():
        color = QColor("#000000")

    # Same result as baking the colour into the SVG and painting at the
    # colour's alpha: SourceIn keeps the mask's coverage and replaces its
    # colour, and the alpha rides on the fill.
    img = QImage(_mask(name, fill, w, h))      # detached copy
    p = QPainter(img)
    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceIn)
    p.fillRect(img.rect(), color)
    p.end()
    _IMG_CACHE[key] = img
    while len(_IMG_CACHE) > _IMG_CACHE_MAX:
        _IMG_CACHE.popitem(last=False)
    return img


class SvgIconProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Image)

    def requestImage(self, id_, size, requested_size):
        w = requested_size.width() if requested_size.width() > 0 else 24
        h = requested_size.height() if requested_size.height() > 0 else w
        global _seen_version
        key = (id_, w, h)
        if key in _SEEN:
            _SEEN.move_to_end(key)
        else:
            _SEEN[key] = None
            _seen_version += 1
            while len(_SEEN) > _SEEN_MAX:
                _SEEN.popitem(last=False)
        return _render(id_, w, h)


# ── theme pre-warm (v3.39.6) ────────────────────────────────────────────────
# A theme swap recolours every visible icon, and each new colour is a new
# image://svgicon URL: QSvgRenderer parse + paint, in Python, on the GUI thread,
# for hundreds of icons in the same moment. That burst was a big part of the
# hitch in the theme curtain. While the app is idle we rasterise the colours
# the OTHER palette will ask for, so the swap itself only gets cache hits.
_PREWARM_SLICE_S = 0.003
_PREWARM_GAP_MS = 16
_prewarm_queue = deque()
_prewarm_gen = 0


def _qml_color_str(c):
    """The hex QML's String(color) produces, without the '#'."""
    fmt = QColor.NameFormat.HexRgb if c.alpha() == 255 else QColor.NameFormat.HexArgb
    return c.name(fmt).lstrip("#")


def cancel_prewarm():
    global _prewarm_gen, _last_prewarm
    _prewarm_gen += 1
    if _prewarm_queue:
        _last_prewarm = None                 # unfinished: redo it next time
    _prewarm_queue.clear()


_last_prewarm = None       # (seen version, colour pairs) of the last run


def _split_hex(h):
    """'rrggbb' / 'aarrggbb' → (rgb int, alpha 0..255), or None."""
    try:
        if len(h) == 6:
            return int(h, 16), 255
        if len(h) == 8:
            return int(h[2:], 16), int(h[:2], 16)
    except ValueError:
        pass
    return None


def prewarm(color_pairs):
    """Queue every seen icon in its counterpart colour. `color_pairs` is
    [(live QColor, target QColor), …] (see ThemeBridge.color_pairs).
    Returns at once when nothing new has been seen since the last run."""
    global _last_prewarm
    sig = (_seen_version, tuple((a.rgba(), b.rgba()) for a, b in color_pairs))
    if sig == _last_prewarm:
        return                               # already warm, or warming now
    cancel_prewarm()
    _last_prewarm = sig

    by_rgb = {}
    for cur, new in color_pairs:
        by_rgb.setdefault(cur.rgb() & 0xFFFFFF, []).append((cur.alpha(), new))
    mapped = {}                              # seen hex → [target hex, …]
    queue = []
    queued = set()
    # newest first: the icons on screen right now are the ones that matter
    for (id_, w, h) in reversed(list(_SEEN.keys())):
        parts = id_.split("/")
        if len(parts) < 3:
            continue
        hexcol = parts[2]
        targets = mapped.get(hexcol)
        if targets is None:
            targets = []
            split = _split_hex(hexcol)
            if split is not None:
                rgb, alpha = split
                for cur_a, new in by_rgb.get(rgb, ()):
                    if cur_a <= 0:
                        continue
                    c = QColor(new)
                    c.setAlpha(max(0, min(255, round(alpha * new.alpha() / cur_a))))
                    targets.append(_qml_color_str(c))
            mapped[hexcol] = targets
        for t in targets:
            key = ("%s/%s/%s" % (parts[0], parts[1], t), w, h)
            if key in _IMG_CACHE or key in queued:
                continue
            queued.add(key)
            queue.append(key)
    if not queue:
        return
    _prewarm_queue.extend(queue)
    gen = _prewarm_gen
    QTimer.singleShot(0, lambda: _prewarm_step(gen))


def _prewarm_step(gen):
    if gen != _prewarm_gen:
        return
    deadline = time.perf_counter() + _PREWARM_SLICE_S
    while _prewarm_queue:
        id_, w, h = _prewarm_queue.popleft()
        try:
            _render(id_, w, h)
        except Exception:                    # noqa: BLE001 — warm-up only
            pass
        if time.perf_counter() >= deadline:
            break
    if _prewarm_queue:
        QTimer.singleShot(_PREWARM_GAP_MS, lambda: _prewarm_step(gen))
