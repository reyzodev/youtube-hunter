pragma Singleton
import QtQuick

// Design tokens for the QML redesign — spacing, radius, typography scale, and
// motion. These are intentionally NOT colours (colours live in the live Theme
// bridge); they're the geometry/rhythm of the "medium redesign": a single,
// consistent scale so pages don't each invent their own paddings.
QtObject {
    // ── theme swap guard (v3.39.6) ──
    // True only while the theme curtain is opaque and the palette is being
    // republished behind it. Every `Behavior on color / border.color /
    // glyphColor` reads it as `enabled: !Tokens.themeSwapping`, so the swap
    // snaps colours instead of starting ~290 ColorAnimations at once (and,
    // for icons, a fresh SVG rasterise on every animation frame). Written by
    // Main.qml's startThemeWipe(); nothing else should touch it.
    property bool themeSwapping: false

    // ── spacing scale (px) ──
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 22
    readonly property int space6: 30
    readonly property int space7: 42
    readonly property int space8: 56

    // ── corner radii ──
    // v6 ("Studio 2026"): a calmer, more precise radius ladder. v4 rounded
    // everything a notch to read "soft"; next to the quieter v6 surfaces that
    // read as bubbly, so every step comes back down and the ladder is evened
    // out (each step ≈ 1.33× the last) so nested shapes stay concentric:
    // a radiusMd control inside a radiusXl card with space2 padding lines up.
    readonly property int radiusXs: 6
    readonly property int radiusSm: 8
    readonly property int radiusMd: 11
    readonly property int radiusLg: 15
    readonly property int radiusXl: 20
    readonly property int radiusPill: 999

    // ── type scale (px) ──
    // v6: display came down from 29 → 26 (a page title is a label, not a
    // poster), and fontMicro is the floor for badges / section labels — nothing
    // in the app is drawn smaller than 11px any more.
    readonly property int fontMicro: 11
    readonly property int fontCaption: 12
    readonly property int fontBody: 14
    readonly property int fontLabel: 15
    readonly property int fontSubtitle: 17
    readonly property int fontTitle: 22
    readonly property int fontDisplay: 26
    // Latin-only tracking for the small uppercase section labels in the rail
    // and panels (Persian has no case and must never be letter-spaced).
    readonly property real trackingLabel: 0.6

    // ── font weights (map to QFont weights the FontBridge understands) ──
    readonly property int weightRegular: 400
    readonly property int weightMedium: 500
    readonly property int weightDemiBold: 600
    readonly property int weightBold: 700
    readonly property int weightExtraBold: 800

    // ── layout ──
    // v6: a denser shell. The rail gives ~24px back to the page, nav rows go
    // 46 → 38 (11 rows + 4 group labels now fit a 760px laptop window without
    // scrolling), and controls settle at 42px — the 2026 desktop norm.
    readonly property int sidebarExpanded: 248
    readonly property int sidebarCollapsed: 68
    readonly property int titleBarHeight: 48
    readonly property int navButtonHeight: 38
    readonly property int navGroupHeight: 30
    readonly property int fieldHeight: 42
    readonly property int controlHeightSm: 32
    readonly property int windowRadius: 12
    // ── page width (v16) ──
    // One rule for every page, and the rule no longer depends on whether the
    // rail is open:
    //
    //   ref     = the page width WITH THE RAIL EXPANDED (even when it is
    //             collapsed). Collapsing the rail therefore never widens the
    //             column — the freed 180px becomes calm side margin, so the
    //             layout does not jump or stretch to the edges.
    //   gutter  = fluid, 3.5% of ref clamped to 24…64px. Small laptop windows
    //             keep their space; big monitors get real breathing room.
    //   width   = min(contentMaxWidth, ref − 2·gutter)
    //
    // 1440 is the cap: wide enough for four 330px result cards + gaps, narrow
    // enough that rows stay scannable on 1080p/1440p/4K. The content column is
    // centred in the page by every page already.
    readonly property int contentMaxWidth: 1440
    // Kept for the few call sites that want a fixed edge (docks, sheets).
    readonly property int pageGutter: 24
    // Fed by Main.qml (the window width). 0 = unknown → fall back to the page.
    property real windowWidth: 0

    function gutterFor(ref) {
        return Math.round(Math.max(24, Math.min(64, ref * 0.035)))
    }
    function contentWidth(pageW) {
        var ref = pageW
        if (windowWidth > 0)
            ref = Math.min(pageW, windowWidth - sidebarExpanded)
        ref = Math.max(ref, 0)
        return Math.max(0, Math.min(contentMaxWidth, ref - gutterFor(ref) * 2, pageW - 2 * 24))
    }

    // ── motion (ms) ──
    // v4: slightly longer, with dedicated curves, so state changes glide and
    // settle instead of snapping. Still well under the "feels laggy" line.
    // v6: snappier. Springs and overshoot are gone from routine state
    // changes (hover, press, selection) — they now ease out and stop. The
    // bounce is reserved for genuine arrivals (dialogs, the command palette).
    readonly property int durFast: 120
    readonly property int durMed: 190
    readonly property int durSlow: 320
    // a glow breathing in/out on hover / focus
    readonly property int durGlow: 360
    // the page-to-page entrance (fade + rise)
    readonly property int durPage: 240
    // one full drift of the ambient page wash — slow enough to be felt, not seen
    readonly property int durAmbient: 14000

    // ── glow geometry ──
    readonly property int glowBlur: 32
    readonly property real pressScale: 0.98
    readonly property real hoverLiftScale: 1.01
    // page entrance rise (px) — was 14
    readonly property int pageRise: 8

    // ── perf: is the app in front? ──
    // Purely decorative loops (page wash drift, breathing halos, pulsing dots)
    // gate on this, so a minimised or background window stops asking the
    // scene graph for 60 frames a second. Work spinners do NOT use it: a
    // download you are watching side-by-side must keep moving.
    readonly property bool appActive: Qt.application.state === Qt.ApplicationActive
}
