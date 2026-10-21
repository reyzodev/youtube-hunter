import QtQuick
import NicheScope
import "../Utils.js" as U

// A themed "glass" surface: rounded panel with a soft border and a drop
// shadow, matching the legacy glass_panel() but as a live-bound QML surface.
Rectangle {
    id: root
    property real elevation: 1.0        // scales the shadow
    property alias radius_: root.radius

    // v4: opt-in hover glow — the hairline warms toward the accent and the
    // drop shadow turns into a soft accent halo. Used by cards that are
    // interactive or worth "lighting up" (Panel, stat cards).
    property bool hoverGlow: false
    readonly property bool _lit: hoverGlow && gpHover.hovered
    // pointer is over the card (only tracked when hoverGlow is on)
    readonly property bool hovered: gpHover.hovered
    readonly property real _glowK: Theme.glow_level !== undefined ? Theme.glow_level : 1.0

    radius: Tokens.radiusLg
    color: Theme.panel_bg
    border.width: 1
    // v6: the hover edge is a whisper of accent (0.38 → 0.22) — enough to say
    // "this card is live", not enough to outline it in neon.
    border.color: _lit ? U.mix(Theme.border, Theme.primary, 0.22) : Theme.border
    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
    antialiasing: true

    HoverHandler { id: gpHover; enabled: root.hoverGlow }

    // Specular top edge — a 1px line of light that fades out toward the
    // corners, so a card reads as a lit sheet of glass rather than a flat box.
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(0, parent.width - root.radius * 2)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
            GradientStop { position: 0.5; color: root._lit ? U.withAlpha(Theme.primary, 0.55) : Theme.glass_hi }
            GradientStop { position: 1.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
        }
    }

    // ── drop shadow ──
    // Perf rewrite: every card used to cast its shadow through a layered proxy
    // + MultiEffect, i.e. one offscreen texture and a blur shader PER CARD,
    // re-rendered whenever the card resized (window resize, the rail slide,
    // grids reflowing). With dozens of cards on a page that was the bulk of the
    // GPU/CPU cost of simply showing a page. The shadow is now a pre-blurred
    // 9-slice image stretched around the card: same soft falloff, same offset
    // and depth per elevation, zero offscreen passes, free to resize. It sits
    // behind the panel (z -1), so text inside is never rasterised.
    readonly property real _elev: Math.max(0, elevation)
    readonly property real _shadowAlpha: Theme.isDark ? 0.34 : 0.06
    BorderImage {
        id: shadowImg
        z: -1
        visible: root._elev > 0 && root.width > 0 && root.height > 0
        source: "shadow_soft.png"
        border { left: 64; right: 64; top: 64; bottom: 64 }
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
        smooth: true
        cache: true
        readonly property real _grow: (root._elev - 1) * 6       // softer when lifted
        readonly property real _dy: 5 * root._elev                // drop distance
        anchors.fill: parent
        anchors.leftMargin: -48 - _grow
        anchors.rightMargin: -48 - _grow
        anchors.topMargin: -48 - _grow + _dy
        anchors.bottomMargin: -48 - _grow - _dy
        opacity: root._shadowAlpha * (root._lit ? 1.25 : 1.0) * Math.min(1.4, 0.75 + 0.25 * root._elev)
        Behavior on opacity { NumberAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
    }

    // Accent halo for hover-glow cards: three nested rounded rects at a whisper
    // of alpha read as a soft tinted bloom. Opacity 0 at rest, so the renderer
    // skips them entirely until the card is actually lit.
    Item {
        z: -1
        anchors.fill: parent
        visible: root.hoverGlow
        opacity: root._lit ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
        Repeater {
            model: [3, 7, 12]
            Rectangle {
                anchors.fill: parent
                anchors.margins: -modelData
                anchors.topMargin: -modelData + 4
                anchors.bottomMargin: -modelData - 4
                radius: root.radius + modelData
                color: U.withAlpha(Theme.primary, (Theme.isDark ? 0.06 : 0.035) * root._glowK)
                antialiasing: true
            }
        }
    }
}
