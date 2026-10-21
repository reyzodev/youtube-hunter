"""app.ui.icons - YouTube Hunter.

Semantic icon name -> glyph in the bundled Remix Icon font
(https://remixicon.com). QML draws every icon as a Text element in that font
family (see app.qml_backend.icon_bridge); this module is the single place that
decides which glyph a name maps to. Remix ships each glyph as a matched pair, a
`-line` (outline) face and a `-fill` (solid) face, so ICON_MAP stores every
name as a (line_codepoint, fill_codepoint) tuple.
"""


# ── Semantic UI name -> (line codepoint, fill codepoint) in remixicon.ttf ──
# The keys are exactly the names the app's call sites ask for. A name absent
# here resolves to 'icon' (see icon_name_for) rather than rendering the literal
# word. FILL glyphs are used when a call passes fill > 0.5; otherwise the line
# (outline) glyph is drawn.
ICON_MAP = {
    'nav_chat': (61254, 61253),
    'add': (59923, 59923), 'android': (59958, 59957), 'api': (60333, 60333), 'archive': (59976, 59975),
    'arrow_back': (60000, 59999), 'arrow_forward': (60012, 60011), 'article': (60030, 60029), 'auto_awesome': (62315, 62314),
    'autorenew': (61540, 61539), 'backspace': (60442, 60441), 'bar_chart': (60062, 60057), 'biotech': (61270, 61269),
    'bolt': (60733, 60732), 'bookmark': (60133, 60132), 'bookmark_add': (60131, 60130), 'bookmark_border': (60133, 60132),
    'cancel': (60311, 60310), 'car': (60217, 60216), 'card': (60050, 60049), 'category': (59972, 59971),
    'chart': (61099, 61098), 'check': (60283, 60283), 'check_circle': (60289, 60288), 'checklist': (61113, 61113),
    'chevron_left': (60004, 60003), 'chevron_right': (60014, 60013), 'close': (60313, 60313), 'cloud_download': (60502, 60501),
    'code': (60333, 60333), 'contact_support': (60428, 60427), 'content_copy': (60629, 60628), 'content_paste': (60305, 60304),
    'crop_square': (62428, 62427), 'dark_mode': (61301, 61298), 'dashboard': (60436, 60435), 'data': (60438, 60437),
    'data_array': (60139, 60139), 'delete': (60458, 60457), 'delete_outline': (60458, 60457), 'delete_sweep': (60452, 60451),
    'description': (60687, 60686), 'desktop_windows': (60362, 60361), 'diamond': (62096, 62095), 'download': (60506, 60505),
    'download_done': (60289, 60288), 'downloading': (60506, 60505), 'drag_handle': (61305, 61304), 'edit': (60550, 60549),
    'error': (60577, 60576), 'expand_less': (60024, 60023), 'expand_more': (59982, 59981), 'favorite': (60943, 60942),
    'filter_alt': (60711, 60710), 'filter_list': (60711, 60710), 'filter_none': (60295, 60294), 'first_page': (62179, 62179),
    'folder': (60778, 60769), 'folder_off': (60788, 60787), 'folder_open': (60784, 60783), 'forward_10': (62251, 62250),
    'fullscreen': (60828, 60827), 'fullscreen_exit': (60826, 60826), 'gemini': (62783, 62782), 'grid_view': (61072, 61071),
    'hd': (60930, 60929), 'health': (60945, 60944), 'help': (61509, 61508), 'history': (60951, 60950),
    'home_work': (60957, 60956), 'hourglass_empty': (62263, 62262), 'icon': (59972, 59971), 'image': (61003, 61002),
    'info': (61017, 61016), 'insights': (61099, 61098), 'inventory_2': (59976, 59975), 'ios_share': (61693, 61692),
    'key': (61039, 61038), 'language': (61990, 61990), 'last_page': (62181, 62181), 'light_mode': (61887, 61884),
    'lightbulb': (61097, 61094), 'link': (61106, 61106), 'lock': (61132, 61131), 'math': (60191, 60190),
    'message': (61252, 61251), 'messages': (61254, 61253), 'monetization_on': (61285, 61284), 'money': (61285, 61284),
    'movie': (61313, 61312), 'music': (61315, 61314), 'music_note': (61315, 61314), 'note': (61851, 61850),
    'notifications': (61332, 61331), 'open_in_new': (60591, 60590), 'palette': (61381, 61380), 'pause': (61400, 61400),
    'pet': (60817, 60816), 'play_arrow': (61451, 61450), 'play_circle': (61449, 61448), 'psychology': (62199, 62198),
    'public': (60538, 60537), 'python': (60327, 60326), 'query_stats': (61815, 61814), 'receipt': (62551, 62550),
    'refresh': (61540, 61539), 'remove': (61871, 61870), 'replay_10': (62290, 62289), 'restart_alt': (61568, 61567),
    'route': (61595, 61594), 'save': (61619, 61618), 'scroll': (60653, 60652), 'scissors': (61635, 61634), 'sd': (61641, 61640),
    'search': (61649, 61648), 'send': (61658, 61657), 'settings': (61670, 61669), 'smart_display': (62165, 62164),
    'sort': (60020, 60019), 'speed': (61815, 61814), 'star': (61835, 61830), 'status': (61493, 61493),
    'stop_circle': (61855, 61854), 'story': (61784, 61783), 'sync': (61540, 61539), 'target': (60748, 60747),
    'terminal': (61942, 61941), 'text': (61953, 61953), 'travel_explore': (61647, 61646), 'trending_up': (61099, 61098),
    'truck': (62001, 62000), 'tune': (60573, 60572), 'user': (62052, 62047), 'verified': (62440, 62439),
    'video': (61313, 61312), 'view_list': (61118, 61118), 'visibility': (60597, 60596), 'visibility_off': (60599, 60598),
    'volume_off': (62110, 62109), 'volume_up': (62114, 62113), 'vpn_key': (61039, 61038), 'warning': (60577, 60576),
    'youtube': (62165, 62164),
    # ── Custom-SVG slots (see assets/icons/). Each maps to a font glyph as a
    # fallback for when the .svg is absent, but normally the SVG wins. Kept
    # as dedicated names so swapping these four toggle icons does NOT also
    # change the many other buttons that reuse smart_display / open_in_new /
    # grid_view / view_list elsewhere in the app.
    'tab_videos': (62165, 62164),      # Videos view toggle  (was smart_display)
    'tab_channels': (60591, 60590),    # Channels view toggle (was open_in_new)
    'layout_grid': (61072, 61071),     # card-grid layout    (was grid_view)
    'layout_list': (61118, 61118),     # table layout        (was view_list)
    'fmt_short': (60733, 60732),       # Shorts format toggle (was bolt)
    'fmt_long': (61313, 61312),        # Long-form format toggle (was movie)
    'fmt_all': (61313, 61312),         # All-formats toggle   (was movie)
    'nav_usage': (61815, 61814),       # Usage & Quota nav    (was query_stats)
    'nav_studio': (60687, 60686),      # Script Studio nav    (was description)
    'nav_insights': (61099, 61098),    # Niche Scan nav (was insights)
    # 'subject' was already being asked for by BlueprintPane's Full-script
    # section heading and by the teleprompter; without a key it silently fell
    # back to the generic 'icon' glyph. Aliased to the document glyph, which is
    # what both of those actually mean.
    'subject': (60687, 60686),
    'mirror': (61540, 61539),          # teleprompter mirror  (was autorenew)
    # AI provider logos (drop assets/icons/provider_*.svg — full-colour logos,
    # so they're listed in _SVG_KEEP_COLOR below). Fallbacks are generic glyphs
    # for when a logo file isn't present yet.
    'provider_openai': (62315, 62314),      # fallback: auto_awesome
    'provider_anthropic': (61835, 61830),   # fallback: star
    'provider_gemini': (62783, 62782),       # fallback: gemini glyph
    'provider_custom': (60333, 60333),       # fallback: code/api
    # ── nav-rail collapse control ──
    # remixicon's menu family: the fold/unfold pair draws a hamburger with a
    # chevron pointing the way the panel will move, which reads better on a
    # collapse toggle than a bare chevron did.
    'menu': (61246, 61243),
    'menu_fold': (61245, 61244),
    'menu_unfold': (61248, 61247),
    # ── v6 (Studio 2026) ── per-section nav glyphs, so every rail row has its
    # own silhouette (v5 used generic names like 'download' / 'archive' that
    # were shared with in-page buttons), plus the command-palette set.
    'nav_scrape': (60502, 60501),
    'nav_niche': (60350, 60349),
    'nav_monetize': (60340, 60339),
    'nav_archive': (61005, 61004),
    'nav_ideas': (61096, 61095),
    'nav_lab': (60735, 60734),
    'nav_downloads': (62412, 62411),
    'nav_cutter': (61633, 61632),
    'nav_history': (60951, 60950),
    'nav_settings': (61672, 61671),
    'search_2': (61645, 61644),
    'corner_down_left': (62215, 62214),
    'arrow_up_down': (60020, 60019),
    'sparkling': (62315, 62314),
    'sidebar_fold': (62555, 62554),
    'sidebar_unfold': (62557, 62556),
    'arrow_right_up': (60016, 60015),
    'contrast': (60372, 60371),
    'translate': (61990, 61990),
    'compass': (60350, 60349),
    'page_insights': (61099, 61098),
    'command': (60343, 60343),
    # An unknown name renders as *nothing* with no error, so every name QML
    # asks for must be listed here.
    'apps': (59972, 59971),                 # apps-line / apps-fill
    'extension': (62545, 62544),            # puzzle-line / puzzle-fill
    'schedule': (62450, 62449),             # calendar-schedule-line / -fill
}

_FALLBACK = ICON_MAP['icon']


# ── Custom SVG icons (assets/icons/) ──
# A name listed here is drawn from its SVG instead of the font glyph:
# assets/icons/<name>.svg is the outline face, <name>-fill.svg the solid face
# (used where the font would use the -fill glyph, e.g. the active segment).
# The SVGs paint with `currentColor`; the svgicon image provider swaps that
# for the colour QML asks for, so they theme exactly like font glyphs. If a
# file is missing the font glyph from ICON_MAP is used, so nothing ever blanks.
# v8 "Aurora 2026": every in-page icon now has a hand-drawn duotone SVG
# (generated by tools/build_icons.py). The set is discovered from the folder,
# so dropping a new <name>.svg in is all it takes. The sidebar keeps its own
# kinetic NavIcon set (IconGlyph.svg: false there) and fmt_* are unchanged.
def _discover_svgs():
    import os
    from app.paths import asset_path
    try:
        files = os.listdir(asset_path("assets", "icons"))
    except OSError:
        return frozenset(('fmt_all', 'fmt_long', 'fmt_short'))
    return frozenset(f[:-4] for f in files
                     if f.endswith(".svg") and not f.endswith("-fill.svg"))


SVG_ICONS = _discover_svgs()

_SVG_CACHE = {}


def svg_file(name, fill=False):
    """Absolute path of the SVG for (name, solid?), or "" when there is none.
    A missing -fill face falls back to the outline file."""
    key = (name, bool(fill))
    if key in _SVG_CACHE:
        return _SVG_CACHE[key]
    path = ""
    if name in SVG_ICONS:
        import os
        from app.paths import asset_path
        for stem in ((name + "-fill", name) if fill else (name,)):
            cand = asset_path("assets", "icons", stem + ".svg")
            if os.path.isfile(cand):
                path = cand
                break
    _SVG_CACHE[key] = path
    return path


def has_svg(name):
    return bool(svg_file(name, False))


def icon_name_for(name):
    """Normalise a requested name to a key present in ICON_MAP.

    All call sites use underscore-style names that are direct keys; a
    hyphenated legacy spelling is tried next, and anything still unknown
    resolves to the generic 'icon' glyph rather than the literal word."""
    if name in ICON_MAP:
        return name
    key = str(name).replace('-', '_')
    return key if key in ICON_MAP else 'icon'


# QML calls icon_char from a binding for every glyph on screen (thousands per
# grid rebuild), and the answer only depends on (name, solid?), so it is memoised.
_CHAR_CACHE = {}


def icon_char(name, fill=0.0):
    """Semantic icon name -> the actual character remixicon.ttf maps it to.

    Picks the solid (-fill) glyph when fill > 0.5, otherwise the outline
    (-line) glyph. MUST be used by every call site that draws an icon as
    TEXT; the font has no ligature table, so
    handing it the raw name would render the literal word."""
    solid = float(fill) > 0.5
    key = (name, solid)
    ch = _CHAR_CACHE.get(key)
    if ch is not None:
        return ch
    line_cp, fill_cp = ICON_MAP.get(icon_name_for(name), _FALLBACK)
    cp = fill_cp if solid else line_cp
    try:
        ch = chr(int(cp))
    except (TypeError, ValueError):
        ch = chr(int(_FALLBACK[0]))
    _CHAR_CACHE[key] = ch
    return ch
