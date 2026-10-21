"""tools/build_icons.py - YouTube Hunter "Aurora 2026" icon set generator.

Every in-page icon (everything except the sidebar's kinetic NavIcon set and
the fmt_* format toggles) is drawn here on a 24-unit grid and written to
assets/icons/<name>.svg (line face) + <name>-fill.svg (solid / active face).

Visual language
  • 1.75 rounded strokes, soft 2.5-3.5 corner radii, optical 2-unit padding.
  • Duotone: each icon's main body carries a vertical currentColor gradient
    tint (subtle on the line face, rich on the fill face) so icons read as
    lit glass rather than flat wire.
  • One solid accent per icon (a dot, a spark, a play head) gives it focus.
Only SVG Tiny features QSvgRenderer supports are used (no masks/filters).

Run:  python tools/build_icons.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icons")



def R(x, y, w, h, r):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/>'


def C(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}"/>'


def E(cx, cy, rx, ry):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/>'


def P(d):
    return f'<path d="{d}"/>'


def star_poly(n, ro, ri, cx=12, cy=12, rot=-90):
    pts = []
    for i in range(n * 2):
        r = ro if i % 2 == 0 else ri
        a = math.radians(rot + i * 180 / n)
        pts.append(f"{cx + r * math.cos(a):.2f} {cy + r * math.sin(a):.2f}")
    return "M" + "L".join(pts) + "z"


# roles: b = body (stroke + gradient tint)   t = tint only (no stroke)
#        l = line stroke   f = faint stroke   a = solid accent   A = accent w/ soft stroke
HEART = "M12 20s-8.5-4.9-8.5-11A4.6 4.6 0 0 1 12 6.4 4.6 4.6 0 0 1 20.5 9c0 6.1-8.5 11-8.5 11z"
EYE = "M2.8 12.4a.9.9 0 0 1 0-.8C4.6 7.7 8 5 12 5s7.4 2.7 9.2 6.6a.9.9 0 0 1 0 .8C19.4 16.3 16 19 12 19s-7.4-2.7-9.2-6.6z"
SPEAKER = "M4 9.5v5a1 1 0 0 0 1 1h3l4.4 3.7a.6.6 0 0 0 1-.5V5.3a.6.6 0 0 0-1-.5L8 8.5H5a1 1 0 0 0-1 1z"
FOLDER = "M3.5 7A2.5 2.5 0 0 1 6 4.5h3.6a2 2 0 0 1 1.4.6l1.4 1.4h5.6A2.5 2.5 0 0 1 20.5 9v8.5A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5z"
BOOKMARK = "M6.5 3.5h11A1.5 1.5 0 0 1 19 5v15.6a.6.6 0 0 1-1 .5L12 16.8l-6 4.3a.6.6 0 0 1-1-.5V5a1.5 1.5 0 0 1 1.5-1.5z"
TRI = "M10.3 4.2a2 2 0 0 1 3.4 0l7.6 13.2a2 2 0 0 1-1.7 3H4.4a2 2 0 0 1-1.7-3z"
SPARK_BIG = "M10 3.5c.6 3.9 2.6 5.9 6.5 6.5-3.9.6-5.9 2.6-6.5 6.5-.6-3.9-2.6-5.9-6.5-6.5 3.9-.6 5.9-2.6 6.5-6.5z"
SPARK_SM = "M18 14.5c.3 1.6.9 2.2 2.5 2.5-1.6.3-2.2.9-2.5 2.5-.3-1.6-.9-2.2-2.5-2.5 1.6-.3 2.2-.9 2.5-2.5z"
TINY_SPARK = "M17.5 3.2l.55 1.45 1.45.55-1.45.55-.55 1.45-.55-1.45-1.45-.55 1.45-.55z"
REFRESH = [("l", P("M20 12a8 8 0 0 1-13.9 5.4M4 12a8 8 0 0 1 13.9-5.4")),
           ("l", P("M18.2 3.2v3.6h-3.6M5.8 20.8v-3.6h3.6")),
           ("a", C(12, 12, 1.5))]
DOC = "M14 3H7a2.5 2.5 0 0 0-2.5 2.5v13A2.5 2.5 0 0 0 7 21h10a2.5 2.5 0 0 0 2.5-2.5V8.5z"
CHART = [("t", P("M3.5 17.5l5.2-5.2 3.8 3.8 7.5-7.6V20.5H3.5z")),
         ("l", P("M3.5 17.5l5.2-5.2 3.8 3.8 7.5-7.6")),
         ("l", P("M15 8.5h5v5")),
         ("a", C(8.7, 12.3, 1.4))]
CLOUD = "M7.2 18A4.2 4.2 0 0 1 6.6 9.7 5.8 5.8 0 0 1 17.6 8.4 4.8 4.8 0 0 1 17.2 18z"
GLOBE_LANG = [("b", C(12, 12, 9)),
              ("l", P("M3 12h18")),
              ("l", P("M12 3c2.5 2.5 3.7 5.5 3.7 9s-1.2 6.5-3.7 9c-2.5-2.5-3.7-5.5-3.7-9S9.5 5.5 12 3z"))]
DOLLAR = [("b", C(12, 12, 9)),
          ("l", P("M14.6 9.2a2.6 2.6 0 0 0-2.4-1.4h-.7a2.1 2.1 0 0 0 0 4.2h1a2.1 2.1 0 0 1 0 4.2h-.8a2.6 2.6 0 0 1-2.4-1.4M12 6v1.8M12 16.2V18"))]
GAUGE = [("t", P("M4.2 18.5A9 9 0 1 1 19.8 18.5z")),
         ("l", P("M4.2 18.5A9 9 0 1 1 19.8 18.5")),
         ("f", P("M7 10.5l1 .8M12 7v1.3M17 10.5l-1 .8")),
         ("l", P("M12 14l3.8-4.3")),
         ("a", C(12, 14, 1.8))]
VIDEO = [("b", R(3, 5, 18, 14, 3.8)),
         ("A", P("M10.3 9.4v5.2a.5.5 0 0 0 .8.4l3.9-2.6a.5.5 0 0 0 0-.8L11.1 9a.5.5 0 0 0-.8.4z"))]
YT = [("b", P("M3 8.5a4 4 0 0 1 3.6-3.9c1.6-.1 3.4-.2 5.4-.2s3.8.1 5.4.2A4 4 0 0 1 21 8.5v7a4 4 0 0 1-3.6 3.9c-1.6.1-3.4.2-5.4.2s-3.8-.1-5.4-.2A4 4 0 0 1 3 15.5z")),
      ("A", P("M10.3 9.3v5.4l4.6-2.7z"))]
TILES = [("b", R(3.5, 3.5, 7, 7, 2.2)), ("b", R(13.5, 3.5, 7, 7, 2.2)),
         ("b", R(3.5, 13.5, 7, 7, 2.2)), ("b", R(13.5, 13.5, 7, 7, 2.2))]
LIST = [("b", R(3.5, 4.5, 3, 3, 1)), ("b", R(3.5, 10.5, 3, 3, 1)), ("b", R(3.5, 16.5, 3, 3, 1)),
        ("l", P("M10 6h10.5M10 12h10.5")), ("f", P("M10 18h7"))]
SORT = [("l", P("M7 4v16M3.8 7.2 7 4l3.2 3.2")), ("f", P("M17 20V4")), ("l", P("M13.8 16.8 17 20l3.2-3.2"))]
APPS = [("b", R(3.5, 3.5, 7, 7, 2.2)), ("b", R(13.5, 3.5, 7, 7, 2.2)),
        ("b", R(3.5, 13.5, 7, 7, 2.2)), ("a", C(17, 17, 3.6))]
KEY = [("b", C(8.5, 15.5, 4.8)), ("l", P("M11.9 12.1 19.5 4.5M16.6 7.4l2.3 2.3M14.3 9.7l1.8 1.8")),
       ("a", C(8.5, 15.5, 1.4))]
BIN = [("b", P("M6 7.5h12l-.9 11.2a2.5 2.5 0 0 1-2.5 2.3H9.4a2.5 2.5 0 0 1-2.5-2.3z")),
       ("l", P("M3.8 7.5h16.4M9.5 7.5V5a1.5 1.5 0 0 1 1.5-1.5h2A1.5 1.5 0 0 1 14.5 5v2.5")),
       ("f", P("M10 11.5v5M14 11.5v5"))]
ARCHIVE = [("b", P("M4.5 9h15v8.5a2.5 2.5 0 0 1-2.5 2.5H7a2.5 2.5 0 0 1-2.5-2.5z")),
           ("b", R(2.5, 4, 19, 5, 2)), ("l", P("M10 13h4"))]
DOWNLOAD = [("t", R(4, 13, 16, 7.5, 3)), ("l", P("M12 3.5v11M7.5 10.5 12 15l4.5-4.5")),
            ("l", P("M4 15.5v2A3 3 0 0 0 7 20.5h10a3 3 0 0 0 3-3v-2"))]
WARN = [("b", P(TRI)), ("l", P("M12 9.5v4.5")), ("a", C(12, 17, 1.15))]
DESC = [("b", P(DOC)), ("l", P("M14 3v3.5a2 2 0 0 0 2 2h3.5")), ("l", P("M8.5 13h7")), ("f", P("M8.5 17h4.5"))]
BOOK = [("b", P(BOOKMARK))]
FILTER = [("b", P("M4 4.5h16a.8.8 0 0 1 .6 1.3L14.5 13v5.2a1 1 0 0 1-.5.9l-3 1.7a.6.6 0 0 1-1-.5V13L3.4 5.8A.8.8 0 0 1 4 4.5z"))]
SPARKLE = [("b", P(SPARK_BIG)), ("a", P(SPARK_SM)), ("a", C(18.5, 5.5, 1.25))]

ICONS = {
    "add": [("l", P("M12 5v14M5 12h14"))],
    "android": [("b", P("M5 16a7 7 0 0 1 14 0v1.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 17.5z")),
                ("l", P("M7.6 9.6 6 7M16.4 9.6 18 7")), ("a", C(9.3, 14, 1.15)), ("a", C(14.7, 14, 1.15))],
    "api": [("l", P("M8.5 7 3.8 12l4.7 5M15.5 7l4.7 5-4.7 5")), ("f", P("M13.4 5.5l-2.8 13"))],
    "archive": ARCHIVE,
    "arrow_back": [("l", P("M19 12H5.5M11 6l-6 6 6 6"))],
    "arrow_forward": [("l", P("M5 12h13.5M13 6l6 6-6 6"))],
    "article": [("b", R(4, 3, 16, 18, 3.5)), ("l", P("M8 8h8M8 12h8")), ("f", P("M8 16h5"))],
    "auto_awesome": SPARKLE,
    "autorenew": REFRESH,
    "backspace": [("b", P("M8.6 5H19a2.5 2.5 0 0 1 2.5 2.5v9A2.5 2.5 0 0 1 19 19H8.6a2 2 0 0 1-1.5-.7L2.5 12l4.6-6.3A2 2 0 0 1 8.6 5z")),
                  ("l", P("M11.5 9.5l5 5M16.5 9.5l-5 5"))],
    "bar_chart": [("b", R(4, 12, 4, 8.5, 1.6)), ("b", R(10, 3.5, 4, 17, 1.6)), ("b", R(16, 8.5, 4, 12, 1.6))],
    "biotech": [("b", P("M10 3.5v5.2L4.9 17.4a2 2 0 0 0 1.7 3.1h10.8a2 2 0 0 0 1.7-3.1L14 8.7V3.5z")),
                ("l", P("M8.5 3.5h7")), ("f", P("M7.2 14.5h9.6")), ("a", C(10.4, 17.4, 1.05)), ("a", C(14, 16.8, .8))],
    "bolt": [("b", P("M13.2 2.8 5 13.4h6l-1.2 7.8 8.2-10.6h-6z"))],
    "bookmark": BOOK,
    "bookmark_add": [("b", P(BOOKMARK)), ("l", P("M12 7.5v5M9.5 10h5"))],
    "cancel": [("b", C(12, 12, 9)), ("l", P("M9 9l6 6M15 9l-6 6"))],
    "car": [("b", P("M3.5 16.5v-3.2a2 2 0 0 1 .6-1.4l2.3-2.3 1.4-3.5a2 2 0 0 1 1.9-1.3h4.6a2 2 0 0 1 1.9 1.3l1.4 3.5 2.3 2.3a2 2 0 0 1 .6 1.4v3.2a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z")),
            ("f", P("M6.4 9.6h11.2")), ("a", C(7, 13.4, 1.05)), ("a", C(17, 13.4, 1.05)),
            ("l", P("M6 17.5v1.5M18 17.5v1.5"))],
    "category": APPS,
    "chart": CHART,
    "check": [("l", P("M4.5 12.5l4.8 4.8L19.5 7"))],
    "check_circle": [("b", C(12, 12, 9)), ("l", P("M8 12.3l2.8 2.8L16.2 9.5"))],
    "checklist": [("l", P("M4 6.5l1.6 1.6L8.5 5.2M4 15.5l1.6 1.6 2.9-2.9")), ("l", P("M12 7h8M12 16h8")),
                  ("f", P("M12 10.5h5M12 19.5h5"))],
    "chevron_left": [("l", P("M14.5 6l-6 6 6 6"))],
    "chevron_right": [("l", P("M9.5 6l6 6-6 6"))],
    "close": [("l", P("M6 6l12 12M18 6 6 18"))],
    "cloud_download": [("b", P(CLOUD)), ("l", P("M12 11v8.5M9.3 17 12 19.7l2.7-2.7"))],
    "contact_support": [("b", P("M12 3.5a8.5 8.5 0 0 1 0 17H4.8a.6.6 0 0 1-.5-.9l1.3-2.2A8.5 8.5 0 0 1 12 3.5z")),
                        ("l", P("M9.7 9.6a2.4 2.4 0 1 1 3.3 2.2c-.6.3-1 .8-1 1.5v.4")), ("a", C(12, 16.4, 1.1))],
    "content_copy": [("b", R(8, 8, 12.5, 12.5, 3)),
                     ("f", P("M16 8V6a2.5 2.5 0 0 0-2.5-2.5H6A2.5 2.5 0 0 0 3.5 6v7.5A2.5 2.5 0 0 0 6 16h2"))],
    "content_paste": [("b", R(4.5, 5, 15, 16, 3)), ("b", R(8.5, 3, 7, 4, 1.5)), ("l", P("M8.5 12h7")), ("f", P("M8.5 16h4"))],
    "crop_square": [("b", R(4.5, 4.5, 15, 15, 3.5))],
    "dark_mode": [("b", P("M20 14.5A8.5 8.5 0 1 1 9.5 4a7.5 7.5 0 0 0 10.5 10.5z")), ("a", P(TINY_SPARK))],
    "data": [("b", E(12, 6, 7.5, 3)), ("t", P("M4.5 6v12c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3V6z")),
             ("l", P("M4.5 6v12c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3V6")), ("f", P("M4.5 12c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3"))],
    "data_array": [("l", P("M8 4H5.5v16H8M16 4h2.5v16H16")), ("a", C(9, 12, 1.2)), ("a", C(12, 12, 1.2)), ("a", C(15, 12, 1.2))],
    "delete": BIN,
    "delete_sweep": [("b", P("M3.5 9h9l-.7 9.3a2 2 0 0 1-2 1.7H6.2a2 2 0 0 1-2-1.7z")),
                     ("l", P("M2.5 9h11M6.3 9V6.8a1 1 0 0 1 1-1h1.4a1 1 0 0 1 1 1V9")),
                     ("l", P("M16 9h5.5M16 13h4")), ("f", P("M16 17h2.5"))],
    "description": DESC,
    "desktop_windows": [("b", R(2.5, 3.5, 19, 13, 3)), ("l", P("M8 20.5h8M12 16.5v4"))],
    "diamond": [("b", P("M7 4h10l4 5.3-9 10.7L3 9.3z")), ("f", P("M3 9.3h18M9.5 4 8 9.3l4 10.7 4-10.7L14.5 4"))],
    "download": DOWNLOAD,
    "edit": [("b", P("M15.2 4.3a2.2 2.2 0 0 1 3.1 0l1.4 1.4a2.2 2.2 0 0 1 0 3.1L9 19.5l-5 1 1-5z")),
             ("f", P("M13.5 6l4.5 4.5")), ("l", P("M13 20.5h7"))],
    "error": WARN,
    "expand_less": [("l", P("M6 15l6-6 6 6"))],
    "expand_more": [("l", P("M6 9l6 6 6-6"))],
    "favorite": [("b", P(HEART)), ("f", P("M7 9.4a2.1 2.1 0 0 1 1.6-1.9"))],
    "filter_alt": FILTER,
    "first_page": [("l", P("M17 6l-6 6 6 6")), ("l", P("M7 6v12"))],
    "folder": [("b", P(FOLDER)), ("f", P("M3.5 10h17"))],
    "folder_off": [("b", P(FOLDER)), ("l", P("M3 3l18 18"))],
    "folder_open": [("l", P("M3.5 17.4V7A2.5 2.5 0 0 1 6 4.5h3.6a2 2 0 0 1 1.4.6l1.4 1.4H17A2.5 2.5 0 0 1 19.5 9v1")),
                    ("b", P("M5.9 11.3A2 2 0 0 1 7.8 10h12.4a1 1 0 0 1 1 1.3l-2 6.9A2.5 2.5 0 0 1 16.8 20H5.4a2 2 0 0 1-1.9-2.6z"))],
    "forward_10": [("l", P("M20 12a8 8 0 1 1-2.4-5.7")), ("l", P("M18.2 3v3.6h-3.6")),
                   ("l", P("M8.7 10.2l1.3-.9v5.7")), ("l", E(14.3, 12.2, 1.7, 2.8))],
    "fullscreen": [("t", R(8, 8, 8, 8, 2)),
                   ("l", P("M4 9V6.5A2.5 2.5 0 0 1 6.5 4H9M15 4h2.5A2.5 2.5 0 0 1 20 6.5V9M20 15v2.5a2.5 2.5 0 0 1-2.5 2.5H15M9 20H6.5A2.5 2.5 0 0 1 4 17.5V15"))],
    "fullscreen_exit": [("l", P("M9 4v2.5A2.5 2.5 0 0 1 6.5 9H4M20 9h-2.5A2.5 2.5 0 0 1 15 6.5V4M15 20v-2.5a2.5 2.5 0 0 1 2.5-2.5H20M4 15h2.5A2.5 2.5 0 0 1 9 17.5V20"))],
    "gemini": [("b", P("M12 3c.5 4.6 3.4 8.5 9 9-5.6.5-8.5 4.4-9 9-.5-4.6-3.4-8.5-9-9 5.6-.5 8.5-4.4 9-9z"))],
    "grid_view": TILES,
    "hd": [("b", R(2.5, 5, 19, 14, 3.5)), ("l", P("M6.5 9v6M10 9v6M6.5 12H10")), ("l", P("M13 9v6h1.5a3 3 0 0 0 0-6z"))],
    "sd": [("b", R(2.5, 5, 19, 14, 3.5)),
           ("l", P("M10.4 9.6a1.7 1.7 0 0 0-1.6-1H8.3a1.6 1.6 0 0 0 0 3.2h1a1.6 1.6 0 0 1 0 3.2h-.6a1.7 1.7 0 0 1-1.6-1")),
           ("l", P("M13 9v6h1.5a3 3 0 0 0 0-6z"))],
    "health": [("b", P(HEART)), ("l", P("M3.8 11.5h4l1.5-2.5 2.5 5 1.7-2.5h6.7"))],
    "help": [("b", C(12, 12, 9)), ("l", P("M9.6 9.4a2.5 2.5 0 1 1 3.4 2.4c-.6.3-1 .8-1 1.5v.5")), ("a", C(12, 16.7, 1.1))],
    "history": [("l", P("M4 12a8 8 0 1 0 2.4-5.7")), ("l", P("M5.8 3v3.6h3.6")),
                ("l", P("M12 8v4.3l3 1.8"))],
    "home_work": [("b", P("M4 10.2 12 4l8 6.2V18a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 18z")),
                  ("l", P("M10 20.5v-4.5a2 2 0 0 1 4 0v4.5"))],
    "hourglass_empty": [("l", P("M6.5 3.5h11M6.5 20.5h11")),
                        ("t", P("M7.5 3.5h9v2.7a4 4 0 0 1-1.6 3.2L12 12l-2.9-2.6a4 4 0 0 1-1.6-3.2z")),
                        ("l", P("M7.5 3.5v2.6a4 4 0 0 0 1.6 3.2L12 12l2.9-2.7a4 4 0 0 0 1.6-3.2V3.5M7.5 20.5v-2.6a4 4 0 0 1 1.6-3.2L12 12l2.9 2.7a4 4 0 0 1 1.6 3.2v2.6")),
                        ("a", P("M9.2 19.6c0-1.3 1.3-2.4 2.8-2.4s2.8 1.1 2.8 2.4z"))],
    "image": [("b", R(3, 4, 18, 16, 3.5)),
              ("l", P("M3.5 16.5l4.6-4.4a1.5 1.5 0 0 1 2 0l6.4 6.4M14 14.5l1.6-1.6a1.5 1.5 0 0 1 2 0l2.9 2.8")),
              ("a", C(15.5, 8.7, 1.6))],
    "info": [("b", C(12, 12, 9)), ("l", P("M12 11v5.5")), ("a", C(12, 7.8, 1.15))],
    "ios_share": [("t", R(4.5, 10.5, 15, 10, 2.5)), ("l", P("M12 3.5v11M8 7.3l4-3.8 4 3.8")),
                  ("l", P("M8.5 10.5H7A2.5 2.5 0 0 0 4.5 13v5A2.5 2.5 0 0 0 7 20.5h10a2.5 2.5 0 0 0 2.5-2.5v-5a2.5 2.5 0 0 0-2.5-2.5h-1.5"))],
    "key": KEY,
    "language": GLOBE_LANG,
    "last_page": [("l", P("M7 6l6 6-6 6")), ("l", P("M17 6v12"))],
    "light_mode": [("b", C(12, 12, 4.3)),
                   ("l", P("M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"))],
    "lightbulb": [("b", P("M12 3a6.5 6.5 0 0 0-3.9 11.7c.6.5.9 1.2.9 1.9v.4h6v-.4c0-.7.3-1.4.9-1.9A6.5 6.5 0 0 0 12 3z")),
                  ("l", P("M9.5 20.5h5")), ("f", P("M12 6.8a2.8 2.8 0 0 0-2.8 2.8"))],
    "link": [("l", P("M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"))],
    "lock": [("b", R(4.5, 10, 15, 11, 3.5)), ("l", P("M8 10V7.5a4 4 0 0 1 8 0V10")), ("a", C(12, 14.6, 1.4)), ("l", P("M12 15.5v1.9"))],
    "math": [("t", R(3, 3, 18, 18, 5)), ("l", P("M8.5 5.5v5M6 8h5M13.5 8h5M6.4 14.4l4.2 4.2M10.6 14.4l-4.2 4.2M13.5 14.8h5M13.5 18.2h5"))],
    "message": [("b", P("M5.5 4h13A2.5 2.5 0 0 1 21 6.5v9a2.5 2.5 0 0 1-2.5 2.5h-8l-4.6 3.3a.6.6 0 0 1-.9-.5V18h-.5A2.5 2.5 0 0 1 3 15.5v-9A2.5 2.5 0 0 1 5.5 4z")),
                ("l", P("M8 9.5h8")), ("f", P("M8 13h5"))],
    "messages": [("f", P("M7.5 7.5v-2A2.5 2.5 0 0 1 10 3h8.5A2.5 2.5 0 0 1 21 5.5V12a2.5 2.5 0 0 1-2.5 2.5h-1")),
                 ("b", P("M5.5 8.5h8A2.5 2.5 0 0 1 16 11v4.5a2.5 2.5 0 0 1-2.5 2.5H9l-3.4 2.8a.6.6 0 0 1-1-.5V18h0A2.5 2.5 0 0 1 3 15.5V11a2.5 2.5 0 0 1 2.5-2.5z"))],
    "monetization_on": DOLLAR,
    "movie": VIDEO,
    "music": [("l", P("M9 18V6l11-2.2v11.7")), ("b", C(6.5, 18, 2.6)), ("b", C(17.5, 15.5, 2.6))],
    "note": [("b", P("M5.5 3.5h13a2 2 0 0 1 2 2v9l-6 6h-9a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z")),
             ("l", P("M14.5 20.5v-4a2 2 0 0 1 2-2h4")), ("l", P("M7.5 8h9")), ("f", P("M7.5 11.5h6"))],
    "notifications": [("b", P("M12 3.5a5.8 5.8 0 0 0-5.8 5.8v3.3c0 .9-.3 1.8-.9 2.5l-.8 1a.8.8 0 0 0 .6 1.4h13.8a.8.8 0 0 0 .6-1.4l-.8-1a3.9 3.9 0 0 1-.9-2.5V9.3A5.8 5.8 0 0 0 12 3.5z")),
                      ("l", P("M10 20.3a2.2 2.2 0 0 0 4 0")), ("a", C(18.4, 4.8, 1.7))],
    "open_in_new": [("t", R(4, 6, 14, 14, 2.5)), ("l", P("M13.5 4h6.5v6.5M20 4l-8.5 8.5")),
                    ("l", P("M18 14v3.5a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 4 17.5v-9A2.5 2.5 0 0 1 6.5 6H10"))],
    "palette": [("b", P("M12 3a9 9 0 0 0 0 18c1.1 0 1.8-.8 1.8-1.7 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-.9.8-1.7 1.8-1.7H17a4 4 0 0 0 4-4C21 6.6 17 3 12 3z")),
                ("a", C(7.5, 11.5, 1.35)), ("a", C(9.6, 7.4, 1.35)), ("a", C(14.4, 7.4, 1.35)), ("a", C(16.8, 11, 1.2))],
    "pause": [("b", R(6, 4.5, 4, 15, 1.8)), ("b", R(14, 4.5, 4, 15, 1.8))],
    "pet": [("b", P("M12 12c-2.4 0-5 2.7-5 5.1 0 1.6 1.2 2.4 2.6 2.4.9 0 1.6-.5 2.4-.5s1.5.5 2.4.5c1.4 0 2.6-.8 2.6-2.4 0-2.4-2.6-5.1-5-5.1z")),
            ("a", E(5.2, 10.6, 1.7, 2.1)), ("a", E(9, 6.4, 1.8, 2.3)), ("a", E(15, 6.4, 1.8, 2.3)), ("a", E(18.8, 10.6, 1.7, 2.1))],
    "play_arrow": [("b", P("M7.5 5.3v13.4a1 1 0 0 0 1.5.9l10.6-6.7a1 1 0 0 0 0-1.7L9 4.4a1 1 0 0 0-1.5.9z"))],
    "play_circle": [("b", C(12, 12, 9)), ("A", P("M10.2 8.8v6.4a.6.6 0 0 0 .9.5l5-3.2a.6.6 0 0 0 0-1L11.1 8.3a.6.6 0 0 0-.9.5z"))],
    "psychology": [("t", P("M14 21v-3h2a2 2 0 0 0 2-2v-2.5l1.6-.6a.6.6 0 0 0 .3-.9L18 9A7 7 0 1 0 8 15.3V21z")),
                   ("l", P("M14 21v-3h2a2 2 0 0 0 2-2v-2.5l1.6-.6a.6.6 0 0 0 .3-.9L18 9A7 7 0 1 0 8 15.3V21")),
                   ("a", P("M11.5 6.6l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"))],
    "public": [("b", C(12, 12, 9)),
               ("l", P("M12 3c-2.4 2.6-3.6 5.6-3.6 9s1.2 6.4 3.6 9M12 3c2.4 2.6 3.6 5.6 3.6 9s-1.2 6.4-3.6 9")),
               ("f", P("M3.6 9h16.8M3.6 15h16.8"))],
    "python": [("b", P("M12 3.5c-3.5 0-4 1.3-4 2.8V8h4.5v1H5.8C4.2 9 3 10.4 3 12.6c0 2.3 1.1 3.6 2.8 3.6H8v-2.1c0-1.6 1.2-2.9 2.8-2.9h4.4c1.3 0 2.3-1 2.3-2.3V6.3c0-1.4-1.5-2.8-5.5-2.8z")),
               ("b", P("M12 20.5c3.5 0 4-1.3 4-2.8V16h-4.5v-1h6.7c1.6 0 2.8-1.4 2.8-3.6 0-2.3-1.1-3.6-2.8-3.6H16v2.1c0 1.6-1.2 2.9-2.8 2.9H8.8c-1.3 0-2.3 1-2.3 2.3v2.6c0 1.4 1.5 2.8 5.5 2.8z")),
               ("a", C(10.4, 6, .9)), ("a", C(13.6, 18, .9))],
    "query_stats": GAUGE,
    "receipt": [("b", P("M5.5 3.5h13v17l-2.2-1.4-2.1 1.4-2.2-1.4-2.2 1.4-2.1-1.4-2.2 1.4z")),
                ("l", P("M8.5 8h7M8.5 11.5h7")), ("f", P("M8.5 15h4"))],
    "remove": [("l", P("M5 12h14"))],
    "replay_10": [("l", P("M4 12a8 8 0 1 0 2.4-5.7")), ("l", P("M5.8 3v3.6h3.6")),
                  ("l", P("M8.7 10.2l1.3-.9v5.7")), ("l", E(14.3, 12.2, 1.7, 2.8))],
    "restart_alt": [("l", P("M5.2 9A7.5 7.5 0 1 1 4.5 13")), ("l", P("M4.3 4.8v4.4h4.4")), ("a", C(12, 12.3, 1.5))],
    "route": [("b", C(5.5, 18, 2.3)), ("b", C(18.5, 5.2, 2.3)), ("l", P("M8 18h8a3.2 3.2 0 0 0 0-6.4H8a3.2 3.2 0 0 1 0-6.4h8"))],
    "save": [("b", P("M5.5 3.5h10.3a2 2 0 0 1 1.4.6l2.7 2.7a2 2 0 0 1 .6 1.4v10.3a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z")),
             ("l", P("M7.5 3.5v4h7v-4")), ("l", P("M7.5 20.5v-5a1.5 1.5 0 0 1 1.5-1.5h6a1.5 1.5 0 0 1 1.5 1.5v5"))],
    "scroll": [("b", R(5, 3, 14, 18, 3.5)), ("l", P("M9 8h6")), ("f", P("M9 11.5h6")), ("l", P("M9.5 15l2.5 2.5 2.5-2.5"))],
    "scissors": [("b", C(6.5, 6.5, 2.8)), ("b", C(6.5, 17.5, 2.8)), ("l", P("M8.8 8.2 20 17M8.8 15.8 20 7")), ("a", C(12.4, 12, 1))],
    "search": [("b", C(10.5, 10.5, 6.5)), ("l", P("M15.4 15.4 20.5 20.5")), ("f", P("M7.5 9.4a3.2 3.2 0 0 1 2-2.1"))],
    "send": [("b", P("M20.4 3.6 3.8 9.6a.6.6 0 0 0 0 1.1l6.6 2.9 2.9 6.6a.6.6 0 0 0 1.1 0z")), ("l", P("M10.4 13.6l4.6-4.6"))],
    "settings": [("b", P("M12 2.8l7.9 4.6v9.2L12 21.2l-7.9-4.6V7.4z")), ("l", C(12, 12, 3)), ("a", C(12, 12, 1))],
    "smart_display": YT,
    "sort": SORT,
    "star": [("b", P("M12 3.3l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.7l-5.2 2.8 1-5.9L3.5 9.5l5.9-.8z"))],
    "status": [("t", R(2.5, 4, 19, 16, 5)), ("l", P("M3 12h3.8l2.4-6 4.4 12 2.6-6H21"))],
    "stop_circle": [("b", C(12, 12, 9)), ("A", R(9.2, 9.2, 5.6, 5.6, 1.4))],
    "story": [("b", P("M4 5.5A2.5 2.5 0 0 1 6.5 3H19v15H6.5A2.5 2.5 0 0 0 4 20.5z")),
              ("l", P("M4 20.5A2.5 2.5 0 0 1 6.5 18H19v3H6.5")), ("a", P("M11.5 6.6l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"))],
    "target": [("b", C(12, 12, 9)), ("l", C(12, 12, 5)), ("a", C(12, 12, 1.8))],
    "terminal": [("b", R(2.5, 4, 19, 16, 3.5)), ("l", P("M7 9.5l3 2.5-3 2.5")), ("l", P("M12.5 15h4.5"))],
    "text": [("l", P("M5 6.5V5h14v1.5M12 5v14M9.5 19h5"))],
    "travel_explore": [("b", C(10.5, 10.5, 7)), ("f", P("M3.5 10.5h14M10.5 3.5c-1.8 2-2.7 4.3-2.7 7s.9 5 2.7 7")),
                       ("l", P("M16 16l4.5 4.5"))],
    "truck": [("b", P("M2.5 6.5A1.5 1.5 0 0 1 4 5h9a1.5 1.5 0 0 1 1.5 1.5v10h-12z")),
              ("b", P("M14.5 9h3.3a1.5 1.5 0 0 1 1.2.6l2.2 2.9a1.5 1.5 0 0 1 .3.9v3.1h-7z")),
              ("b", C(7, 17.5, 2)), ("b", C(17.5, 17.5, 2))],
    "tune": [("l", P("M4 7h8.8M17.2 7H20M4 17h2.8M11.2 17H20")), ("b", C(15, 7, 2.2)), ("b", C(9, 17, 2.2))],
    "user": [("b", C(12, 8, 4)), ("b", P("M4.5 20.2a7.5 7.5 0 0 1 15 0 .8.8 0 0 1-.8.8H5.3a.8.8 0 0 1-.8-.8z"))],
    "verified": [("b", P(star_poly(8, 9.2, 7.6))), ("l", P("M8.6 12.2l2.3 2.3 4.6-4.8"))],
    "view_list": LIST,
    "visibility": [("b", P(EYE)), ("b", C(12, 12, 3.2)), ("a", C(12, 12, 1.1))],
    "visibility_off": [("b", P(EYE)), ("f", C(12, 12, 3.2)), ("l", P("M4 4l16 16"))],
    "volume_off": [("b", P(SPEAKER)), ("l", P("M16.5 9.5l5 5M21.5 9.5l-5 5"))],
    "volume_up": [("b", P(SPEAKER)), ("l", P("M16.5 8.8a4.5 4.5 0 0 1 0 6.4")), ("f", P("M19 6.3a8 8 0 0 1 0 11.4"))],
    "corner_down_left": [("l", P("M19.5 5v6.5a3 3 0 0 1-3 3H5M9 10.5l-4 4 4 4"))],
    "arrow_right_up": [("l", P("M7 17 17 7M8.5 7H17v8.5"))],
    "contrast": [("b", C(12, 12, 9)), ("a", P("M12 3a9 9 0 0 1 0 18z"))],
    "compass": [("b", C(12, 12, 9)), ("A", P("M15.5 8.5l-2 5-5 2 2-5z")), ("f", P("M12 3.5v1.5M12 19v1.5M3.5 12H5M19 12h1.5"))],
    "command": [("t", R(9, 9, 6, 6, 1)),
                ("l", P("M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3"))],
    "extension": [("b", P("M10 3.5a2 2 0 0 1 2 2V6h4a1.5 1.5 0 0 1 1.5 1.5V11h.5a2 2 0 0 1 0 4h-.5v3.5A1.5 1.5 0 0 1 16 20H5.5A1.5 1.5 0 0 1 4 18.5V15h.5a2 2 0 0 0 0-4H4V7.5A1.5 1.5 0 0 1 5.5 6H8v-.5a2 2 0 0 1 2-2z"))],
    "schedule": [("b", R(3.5, 5, 17, 15.5, 3.5)), ("l", P("M8 3v4M16 3v4")), ("f", P("M3.5 10h17")),
                 ("a", C(8.5, 14.2, 1.1)), ("a", C(12, 14.2, 1.1)), ("a", C(15.5, 14.2, 1.1)), ("a", C(8.5, 17.4, 1.1))],
}

ALIASES = {
    "code": "api", "inventory_2": "archive", "sparkling": "auto_awesome",
    "refresh": "autorenew", "sync": "autorenew", "mirror": "autorenew",
    "bookmark_border": "bookmark", "icon": "category", "apps": "category",
    "insights": "chart", "trending_up": "chart", "page_insights": "chart",
    "delete_outline": "delete", "subject": "description", "downloading": "download",
    "warning": "error", "filter_list": "filter_alt", "layout_grid": "grid_view",
    "vpn_key": "key", "translate": "language", "money": "monetization_on",
    "video": "movie", "music_note": "music", "speed": "query_stats",
    "youtube": "smart_display", "arrow_up_down": "sort", "layout_list": "view_list",
    # unused today but share artwork, so they never fall back to the font
    "card": "content_copy", "dashboard": "grid_view", "download_done": "check_circle",
    "filter_none": "content_copy", "search_2": "search",
}

# ── Two clean faces, one colour each ─────────────────────────────────────
# LINE : pure 1.75 outline. Every stroke full-strength currentColor, no fills
#        except tiny accent dots (the i of info, the ! of warning).
# BOLD : true solid glyph. Bodies are filled; inner details are punched OUT
#        (real holes, so it works on any background); a detail that crosses
#        an edge gets a 1.3-unit gap around it. Built as geometry with shapely
#        (tools/_icon_geom.py) and written as one evenodd path, so the SVG is
#        a single flat shape Qt renders exactly.
SW_LINE, SW_BOLD, GAP = 1.75, 2.0, 1.3


def _style(el, attrs):
    return el.replace("/>", " " + attrs + "/>", 1)


def render_line(parts):
    stroke = f'stroke="currentColor" stroke-width="{SW_LINE}" stroke-linecap="round" stroke-linejoin="round"'
    out = []
    for role, el in parts:
        if role in ("b", "l", "f", "A"):
            out.append(_style(el, f'fill="none" {stroke}'))
        elif role == "a":
            out.append(_style(el, 'fill="currentColor" stroke="none"'))
        # "t" (tint-only areas) has no place in a pure outline
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">\n  '
            + "\n  ".join(out) + "\n</svg>\n")


def bold_geometry(parts):
    import _icon_geom as G
    from shapely.geometry import GeometryCollection
    acc = GeometryCollection()
    for role, el in parts:
        if role in ("b", "t"):
            shape = G.fill_region(el).union(G.stroke_region(el, SW_BOLD)) if role == "b" else G.fill_region(el)
        elif role in ("l", "f"):
            shape = G.stroke_region(el, SW_BOLD)
        elif role == "a":
            shape = G.fill_region(el)
        else:  # "A"
            shape = G.fill_region(el).union(G.stroke_region(el, 1.0))
        if shape.is_empty:
            continue
        frac = shape.intersection(acc).area / shape.area if not acc.is_empty else 0.0
        if frac > 0.9:                       # detail sitting on a body: punch it out
            acc = acc.difference(shape)
        elif frac > 0.03:                    # crosses an edge: separate with a gap
            acc = acc.difference(shape.buffer(GAP, quad_segs=16)).union(shape)
        else:
            acc = acc.union(shape)
    return acc


def render_bold(parts):
    import _icon_geom as G
    d = G.to_d(bold_geometry(parts))
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">\n'
            f'  <path fill="currentColor" fill-rule="evenodd" d="{d}"/>\n</svg>\n')


def render(parts, solid):
    return render_bold(parts) if solid else render_line(parts)


def names():
    return sorted(set(ICONS) | set(ALIASES))


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for name in names():
        parts = ICONS[ALIASES.get(name, name)]
        for solid in (False, True):
            fn = os.path.join(OUT, name + ("-fill" if solid else "") + ".svg")
            with open(fn, "w", encoding="utf-8") as f:
                f.write(render(parts, solid))
            n += 1
    print(f"wrote {n} files for {len(names())} icons -> {OUT}")


if __name__ == "__main__":
    main()
