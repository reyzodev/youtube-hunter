"""app.ui.theme - Youtube Scrapper."""

import subprocess
import sys

from PySide6.QtCore import Qt

from app.ui.colors import shift

# ═════════════════════════════════════════════════════════════════════════
#  THEME SYSTEM  —  dark ("cyber") and light, sharing one semantic palette
#  ---------------------------------------------------------------------
#  Every widget in this app reads colours out of the module-level CLR dict
#  AT BUILD TIME. So switching themes is just: swap CLR's contents, rebuild
#  the stylesheet, and rebuild the window's widget tree in place (see
#  MainWindow._apply_theme_live). Nothing keeps a stale colour, and nothing
#  has to restart.
#
#  The semantic keys below (hover_bg, border, text_strong, primary_aNN …)
#  exist so the same stylesheet works on both: a white 6% overlay reads as
#  a subtle highlight on black and is invisible on white, so each theme
#  supplies its own overlay values instead of the stylesheet hardcoding one.
# ═════════════════════════════════════════════════════════════════════════
THEME_DARK = {
    # v6 "Graphite" (Studio 2026): the v4 blue-black ink is replaced by a near-
    # neutral graphite. The faint cool cast is kept only in the text greys; the
    # surfaces themselves are neutral so the ACCENT is the only colour on
    # screen. Elevation is carried by four evenly spaced lightness steps (rail
    # 0C → page 09 → card 11 → raised 1D) instead of by glow, and glow_level is
    # cut to 0.45 so halos read as a hint of light, not a haze.
    #
    # (v4 note, kept for history) "Midnight ink" (v4 visual refresh): the old neutral zinc greys are
    # replaced by a deep, faintly cool ink. Blue-black surfaces make the accent
    # glow read as LIGHT instead of paint, and the extra step between the rail
    # (darkest), the page and the raised cards gives the shell real depth.
    # ── surfaces ─────────────────────────────────────────────────────────
    "background":         "#09090B",
    "surface":            "#111114",
    "surface_dim":        "#09090B",
    "surface_low":        "#151518",
    "surface_container":  "#111114",
    "surface_high":       "#17171B",
    "surface_highest":    "#1D1D22",
    "surface_bright":     "#25252B",
    "surface_variant":    "#151518",
    "panel_bg":           "#111114",
    "sidebar_bg":         "#0C0C0F",
    "header_bg":          "#0C0C0F",
    "input_bg":           "#0D0D10",
    "dropdown_bg":        "#16161A",
    "card_bg":            "#111114",
    "kanban_col_bg":      "#151518",
    "terminal_head_bg":   "rgba(255,255,255,0.03)",
    "tooltip_bg":         "#24242B",   # v3.41.2: elevated graphite, not inverted white
    "tooltip_fg":         "#F4F4F7",

    # ── text ─────────────────────────────────────────────────────────────
    "on_surface":         "#ECECEF",
    "on_surface_var":     "#9A9AA5",
    "text_strong":        "#FAFAFB",
    "on_primary":         "#ffffff",
    "outline":            "#6A6A75",
    "outline_variant":    "#25252B",

    # ── brand + status ───────────────────────────────────────────────────
    "primary":            "#FF1F44",
    "primary_container":  "#CC0026",
    "primary_deep":       "#FF5A8A",
    "primary_hover":      "#FF3B5C",
    "primary_press":      "#D80F33",
    "secondary":          "#ECECEF",
    "secondary_container": "#2CC28B",
    "tertiary":           "#B3A4FF",
    "error":              "#FF5468",
    "warn":               "#F6BB45",

    # ── overlays: hover / borders / dividers ─────────────────────────────
    "hover_bg":           "rgba(255,255,255,0.045)",
    "hover_bg_strong":    "rgba(255,255,255,0.08)",
    "border_soft":        "#18181C",
    "border":             "#212126",
    "border_med":         "#2B2B31",
    "border_strong":      "#6A6A75",
    "divider_h":          "#1A1A1F",
    "divider_v":          "#1A1A1F",
    "row_alt":            "rgba(255,255,255,0.016)",
    "row_border":         "rgba(255,255,255,0.045)",
    "header_cell_bg":     "rgba(255,255,255,0.025)",
    "chip_bg":            "#18181C",
    "checkbox_bg":        "rgba(255,255,255,0.03)",

    # ── accent tints (selection, chips, checked tabs) ────────────────────
    "primary_a07":        "rgba(255,31,68,0.07)",
    "primary_a10":        "rgba(255,31,68,0.10)",
    "primary_a12":        "rgba(255,31,68,0.12)",
    "primary_a14":        "rgba(255,31,68,0.14)",
    "primary_a18":        "rgba(255,31,68,0.16)",
    "primary_a25":        "rgba(255,31,68,0.25)",
    "primary_a35":        "rgba(255,31,68,0.35)",
    "error_border":       "rgba(255,84,104,0.40)",
    "error_tint":         "rgba(255,84,104,0.14)",

    # ── disabled ─────────────────────────────────────────────────────────
    "disabled_bg":        "#212126",
    "disabled_fg":        "#6A6A75",
    "disabled_border":    "#212126",
    "disabled_panel":     "#151518",

    # ── glass + glow (v4) ────────────────────────────────────────────────
    # glass_hi is the 1px specular line along a raised panel's top edge;
    # glow_level scales every accent halo (buttons, tiles, focus rings).
    "glass_hi":           "rgba(255,255,255,0.05)",
    "glass_edge":         "rgba(255,255,255,0.025)",
    "glow_level":         "0.45",

    # ── painted widgets (QPainter, not stylesheet) ───────────────────────
    "verdict_yes_bg":     "rgba(44,194,139,0.14)",
    "verdict_no_bg":      "rgba(255,84,104,0.14)",
    "logo_grad_in":       "#FF1F44",
    "logo_grad_out":      "#CC0026",
    "ring_inner":         "17,17,20,215",     # r,g,b,a for QColor(...)
    "glow_rgb":           "255,31,68",
    "shadow_alpha":       "80",
    "slider_handle":      "#ffffff",
    "is_dark":            "1",
}

THEME_LIGHT = {
    # v6: neutral paper (F5F5F7) with pure-white cards, 1px hairlines that do
    # the separating, and glow at 0.25 — in daylight light glows look like
    # smudges, so the accent stays a flat, deliberate signal.
    #
    # (v4 note) Same product in daylight: a clean, faintly cool paper instead of the old
    # warm beige, white cards that lift off it on soft shadows, and glows dialled
    # down (glow_level) so the accent stays a deliberate signal, not a haze.
    "background":         "#F5F5F7",
    "surface":            "#ffffff",
    "surface_dim":        "#F5F5F7",
    "surface_low":        "#FAFAFB",
    "surface_container":  "#ffffff",
    "surface_high":       "#F8F8FA",
    "surface_highest":    "#EEEEF1",
    "surface_bright":     "#ffffff",
    "surface_variant":    "#F8F8FA",
    "panel_bg":           "#ffffff",
    "sidebar_bg":         "#FAFAFB",
    "header_bg":          "#FAFAFB",
    "input_bg":           "#F7F7F9",
    "dropdown_bg":        "#ffffff",
    "card_bg":            "#ffffff",
    "kanban_col_bg":      "#F5F5F7",
    "terminal_head_bg":   "rgba(17,17,22,0.035)",
    "tooltip_bg":         "#17171B",
    "tooltip_fg":         "#ffffff",

    "on_surface":         "#17171B",
    "on_surface_var":     "#5F5F6B",
    "text_strong":        "#0B0B0E",
    "on_primary":         "#ffffff",
    "outline":            "#9A9AA5",
    "outline_variant":    "#E4E4E9",

    "primary":            "#FF1F44",
    "primary_container":  "#CC0026",
    "primary_deep":       "#E0306E",
    "primary_hover":      "#FF3B5C",
    "primary_press":      "#D80F33",
    "secondary":          "#17171B",
    "secondary_container": "#109467",
    "tertiary":           "#6A4BD0",
    "error":              "#E0243F",
    "warn":               "#A86400",

    "hover_bg":           "rgba(17,17,22,0.045)",
    "hover_bg_strong":    "rgba(17,17,22,0.075)",
    "border_soft":        "#EEEEF1",
    "border":             "#E4E4E9",
    "border_med":         "#D6D6DD",
    "border_strong":      "#9A9AA5",
    "divider_h":          "#EEEEF1",
    "divider_v":          "#E9E9ED",
    "row_alt":            "rgba(17,17,22,0.018)",
    "row_border":         "rgba(17,17,22,0.055)",
    "header_cell_bg":     "rgba(17,17,22,0.03)",
    "chip_bg":            "#F3F3F6",
    "checkbox_bg":        "rgba(17,17,22,0.03)",

    "primary_a07":        "rgba(255,31,68,0.05)",
    "primary_a10":        "rgba(255,31,68,0.08)",
    "primary_a12":        "rgba(255,31,68,0.10)",
    "primary_a14":        "rgba(255,31,68,0.12)",
    "primary_a18":        "rgba(255,31,68,0.15)",
    "primary_a25":        "rgba(255,31,68,0.22)",
    "primary_a35":        "rgba(255,31,68,0.32)",
    "error_border":       "rgba(224,36,63,0.38)",
    "error_tint":         "rgba(224,36,63,0.10)",

    "disabled_bg":        "#E9E9ED",
    "disabled_fg":        "#9A9AA5",
    "disabled_border":    "#E4E4E9",
    "disabled_panel":     "#F8F8FA",

    "glass_hi":           "rgba(255,255,255,0.85)",
    "glass_edge":         "rgba(17,17,22,0.02)",
    "glow_level":         "0.25",

    "verdict_yes_bg":     "#E6F5EE",
    "verdict_no_bg":      "#FCE9EC",
    "logo_grad_in":       "#FF1F44",
    "logo_grad_out":      "#CC0026",
    "ring_inner":         "255,255,255,235",
    "glow_rgb":           "255,31,68",
    "shadow_alpha":       "16",
    "slider_handle":      "#ffffff",
    "is_dark":            "0",
}

THEMES = {"dark": THEME_DARK, "light": THEME_LIGHT}


# ═════════════════════════════════════════════════════════════════════════
#  ACCENT  —  the one signal colour, switchable from Settings
#  ---------------------------------------------------------------------
#  The palette's whole "primary" family (the base, its hover/press/container
#  shades, every rgba() tint the QML derives from it, the logo gradient and the
#  glow's rgb) is generated from ONE accent pair. Picking a colour here
#  therefore repaints every primary button, icon tile, active nav row, focus
#  ring and corner glow at once — mechanically, in Python, so a bad or missing
#  accent can never produce an unreadable tint or crash the swap.
#
#  Error red and the success green are deliberately NOT derived: they carry
#  meaning, and a green "danger" border would be worse than a clashing one.
# ═════════════════════════════════════════════════════════════════════════
# `b` is no longer just a spare: v4 paints every primary button, the page
# header tile, the active nav pill and the page wash as an a → b gradient, so
# each pair is tuned to read as one light source (no muddy midpoints).
ACCENTS = [
    # v6: `b` is now a near ANALOG of `a` for every accent but Aurora. The v4
    # pairs (crimson → pink, amber → orange-red, ocean → cyan) made every
    # primary button a two-colour gradient, which dated fast; a close analog
    # keeps a hint of depth on the button face while reading as ONE colour.
    # Aurora keeps its two-tone pair as the deliberately expressive option.
    {"key": "crimson", "name": "Signal", "a": "#FF1F44", "b": "#FF4A63"},
    {"key": "amber",   "name": "Amber",  "a": "#F59E0B", "b": "#FBB534"},
    {"key": "ocean",   "name": "Ocean",  "a": "#2F7BFF", "b": "#4C93FF"},
    {"key": "indigo",  "name": "Indigo", "a": "#5E5CE6", "b": "#7A78F0"},
    {"key": "violet",  "name": "Violet", "a": "#8B5CF6", "b": "#A27BFA"},
    {"key": "emerald", "name": "Mint",   "a": "#10B981", "b": "#34CB97"},
    {"key": "aurora",  "name": "Aurora", "a": "#6D5BFF", "b": "#1FD6C9"},
    {"key": "rose",    "name": "Rose",   "a": "#F43F7A", "b": "#F86593"},
    # v14: the studio-lamp amber the 2026 Downloads / prompter redesign was
    # drawn in. Light enough that white labels on it fail contrast, so it
    # carries its own dark ink for on_primary (see _apply_accent).
    {"key": "tungsten", "name": "Tungsten", "a": "#FFB547", "b": "#FFC76E", "on": "#1D1305"},
]
DEFAULT_ACCENT = "crimson"

# Live accent. Widgets read CLR; QML reads the Theme bridge, which is fed from
# CLR — so both follow the accent automatically.
ACCENT = DEFAULT_ACCENT
ACCENT_PREF = DEFAULT_ACCENT


def _hex_rgba(hexcolor, alpha):
    """'#rrggbb' → 'rgba(r,g,b,a)' — the string shape the QML tints are stored
    in (QColor can't parse that syntax, which is why CLR keeps it as text)."""
    h = hexcolor.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r},{g},{b},{round(float(alpha), 3)})"


def accent_entry(key):
    """The accent record for `key`, falling back to the product red."""
    return next((x for x in ACCENTS if x["key"] == key), ACCENTS[0])


def accent_swatches():
    """The picker's list, JSON-friendly for QML."""
    return [{"key": a["key"], "name": a["name"], "color": a["a"], "color2": a["b"]}
            for a in ACCENTS]


def _apply_accent(palette, key):
    """Overwrite the palette's whole primary family from one accent pair."""
    a = accent_entry(key)["a"]
    b = accent_entry(key)["b"]
    h = a.lstrip("#")
    palette.update({
        "primary":           a,
        "primary_container": shift(a, dl=-0.14),
        "primary_deep":      b,
        "primary_hover":     shift(a, dl=0.06, ds=0.04),
        "primary_press":     shift(a, dl=-0.10),
        "primary_a07":       _hex_rgba(a, 0.07),
        "primary_a10":       _hex_rgba(a, 0.10),
        "primary_a12":       _hex_rgba(a, 0.12),
        "primary_a14":       _hex_rgba(a, 0.14),
        "primary_a18":       _hex_rgba(a, 0.18),
        "primary_a25":       _hex_rgba(a, 0.25),
        "primary_a35":       _hex_rgba(a, 0.35),
        "logo_grad_in":      a,
        "logo_grad_out":     shift(a, dl=-0.14),
        "glow_rgb":          f"{int(h[0:2], 16)},{int(h[2:4], 16)},{int(h[4:6], 16)}",
        # convenience: the raw accent pair, for anything that wants it directly
        "accent":            a,
        "accent2":           b,
    })
    # A light accent needs dark labels on its buttons. CLR is rebuilt from the
    # theme dict before every call, so other accents keep the theme's white.
    on = accent_entry(key).get("on")
    if on:
        palette["on_primary"] = on
    return palette


# Live palette. Widgets read this; apply_theme() swaps its contents in place
# so every `CLR[...]` lookup anywhere in the file follows automatically.
CLR = dict(THEME_DARK)

THEME = "dark"          # resolved theme actually in use
THEME_PREF = "system"   # what the user picked: "system" | "dark" | "light"


def detect_system_theme():
    """Read the OS light/dark preference.

    Qt 6.5+ reports it directly and cross-platform; Windows gets a registry
    fallback for older Qt builds. Defaults to dark if nothing answers."""
    try:
        from PySide6.QtGui import QGuiApplication
        if QGuiApplication.instance() is not None:
            scheme = QGuiApplication.styleHints().colorScheme()
            if scheme == Qt.ColorScheme.Light:
                return "light"
            if scheme == Qt.ColorScheme.Dark:
                return "dark"
    except Exception:
        pass
    if sys.platform.startswith("win"):
        try:
            import winreg
            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
            value, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
            return "light" if value else "dark"
        except Exception:
            pass
    if sys.platform == "darwin":
        try:
            out = subprocess.run(["defaults", "read", "-g", "AppleInterfaceStyle"],
                                 capture_output=True, text=True, timeout=3)
            return "dark" if "Dark" in out.stdout else "light"
        except Exception:
            pass
    return "dark"


def apply_theme(preference="system", accent=None):
    """Point CLR at the requested palette + accent. `preference` may be
    'system', 'dark' or 'light'; `accent` is an ACCENTS key (None keeps the one
    already in use). Returns the theme actually resolved."""
    global THEME, THEME_PREF, ACCENT, ACCENT_PREF
    THEME_PREF = preference if preference in ("system", "dark", "light") else "system"
    if accent:
        ACCENT_PREF = accent if any(x["key"] == accent for x in ACCENTS) else DEFAULT_ACCENT
    ACCENT = ACCENT_PREF
    resolved = detect_system_theme() if THEME_PREF == "system" else THEME_PREF
    CLR.clear()
    CLR.update(THEMES.get(resolved, THEME_DARK))
    _apply_accent(CLR, ACCENT)
    THEME = resolved
    return resolved


def is_light():
    return CLR.get("is_dark") == "0"
