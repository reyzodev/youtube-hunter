"""app.ui.colors - Youtube Scrapper."""

import colorsys
import re

from PySide6.QtGui import QColor

#  ICON HELPERS  (Material Symbols via OpenType ligatures + variable axes)
# ═════════════════════════════════════════════════════════════════════════
def _rgba(hex_or_rgba, alpha):
    """QColor from a palette entry plus an explicit alpha (0-255)."""
    c = QColor(hex_or_rgba)
    if not c.isValid():
        c = QColor(255, 82, 82)
    c.setAlpha(max(0, min(255, int(alpha))))
    return c
_RGBA_STR_RE = re.compile(
    r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)")


def qcolor_from_clr(value):
    """QColor from any CLR palette entry — '#rrggbb' *or* the CSS
    'rgba(r, g, b, a)' strings the stylesheet uses, which QColor's own
    constructor can't parse (QSS accepts that syntax; QColor doesn't)."""
    m = _RGBA_STR_RE.match(str(value).strip())
    if not m:
        c = QColor(value)
        return c if c.isValid() else QColor(0, 0, 0, 0)
    r, g, b = (int(float(x)) for x in m.groups()[:3])
    a_str = m.group(4)
    alpha = int(round(float(a_str) * 255)) if a_str is not None else 255
    return QColor(max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)),
                  max(0, min(255, alpha)))


def lerp_qcolor(a, b, t):
    """Blend two QColors — used to ease a caption button's backdrop/icon
    colour in on hover instead of snapping it, since Qt stylesheets have
    no transition property of their own."""
    t = max(0.0, min(1.0, t))
    return QColor(
        int(a.red()   + (b.red()   - a.red())   * t),
        int(a.green() + (b.green() - a.green()) * t),
        int(a.blue()  + (b.blue()  - a.blue())  * t),
        int(a.alpha() + (b.alpha() - a.alpha()) * t),
    )
# ── HTML rendering ──────────────────────────────────────────────────────
# ── per-topic color theme ────────────────────────────────────────────────
# The report's layout, typography, and every component (charts, cards,
# do/don't boxes…) stay fixed — that's the part that's already proven to
# look good. What DOES change per report is the accent palette: the AI
# picks two hex colors that fit the channel's specific niche (warm
# orange/red for cooking, cool blue for tech, vibrant purple for gaming…),
# and everything below derives a full, readable dark+light palette from
# just those two — mechanically, in Python — so a bad or missing AI color
# can never break the report's contrast or crash the render.
_HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


def _hex_to_rgb01(hexcolor):
    hexcolor = hexcolor.lstrip("#")
    return (int(hexcolor[0:2], 16) / 255, int(hexcolor[2:4], 16) / 255, int(hexcolor[4:6], 16) / 255)


def _rgb01_to_hex(rgb):
    r, g, b = rgb
    return "#{:02x}{:02x}{:02x}".format(
        max(0, min(255, round(r * 255))),
        max(0, min(255, round(g * 255))),
        max(0, min(255, round(b * 255))))


def _hex_adjust(hexcolor, dl=0.0, ds=0.0):
    """Shifts a hex color's HSL lightness/saturation by the given deltas
    (roughly -1..1), clamped to a valid range."""
    r, g, b = _hex_to_rgb01(hexcolor)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = max(0.0, min(1.0, l + dl))
    s = max(0.0, min(1.0, s + ds))
    return _rgb01_to_hex(colorsys.hls_to_rgb(h, l, s))


def _hex_to_rgba(hexcolor, alpha):
    r, g, b = (round(c * 255) for c in _hex_to_rgb01(hexcolor))
    return f"rgba({r},{g},{b},{alpha})"


def _hex_toward_lightness(hexcolor, target_l, factor=0.7, ds=-0.35):
    """Blends a hex color's HSL lightness a fraction of the way toward an
    absolute target (rather than a flat +/- delta), so a very light or very
    dark input color still lands near the target instead of clipping to
    pure white/black and losing its hue entirely."""
    r, g, b = _hex_to_rgb01(hexcolor)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    new_l = max(0.0, min(1.0, l + (target_l - l) * factor))
    new_s = max(0.0, min(1.0, s + ds))
    return _rgb01_to_hex(colorsys.hls_to_rgb(h, new_l, new_s))


def shift(hexcolor, dl=0.0, ds=0.0):
    """Public alias of _hex_adjust.

    Used by app.ui.theme's accent generator: the hover/press/container shades of
    a switchable accent colour are all derived from the one picked hex, so a new
    accent needs no hand-tuned palette of its own.
    """
    return _hex_adjust(hexcolor, dl, ds)
