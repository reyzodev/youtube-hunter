import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// Square, icon-only action button — the bordered 40×40 tiles that sit beside a
// card's primary action. `accent` tints the glyph (used for the sticky
// bookmark state, which stays solid once a video is saved).
//
// `overlay: true` switches to the variant used ON TOP of video/imagery: the
// glyph stays at full `accent` colour instead of resting at the muted
// on_surface_var (which is a grey picked for page backgrounds and reads as
// washed-out over a dark frame), and the resting backdrop is a translucent dark
// disc rather than a bordered tile.
AbstractButton {
    id: root
    property string iconName: ""
    property bool iconFill: false
    property color accent: Theme.on_surface_var
    property bool active: false
    property bool overlay: false
    property int glyphSize: 18
    // Chromeless: no tile, no border — the caller draws its own backdrop
    // (the player's centre play disc). Pair with `active: true` so the glyph
    // keeps the accent colour at rest instead of the muted resting grey.
    property bool chromeless: false
    // Optional hover tooltip — set `tip` and a themed AppTooltip appears below
    // the tile after a short delay. Empty by default (no tooltip).
    property string tip: ""
    // Tooltip placement: prefer above the button (e.g. a bottom toolbar), and
    // an optional item the tip must stay inside (e.g. the player card).
    property bool tipAbove: false
    // objectName of an ancestor the tip must stay inside ("" = the window)
    property string tipBoundsName: ""

    implicitWidth: 40
    implicitHeight: 40
    hoverEnabled: true
    scale: pressed ? 0.92 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: root.pressed ? Tokens.durFast : Tokens.durSlow
            easing.type: root.pressed ? Easing.OutCubic : Easing.OutBack
            easing.overshoot: 2.6
        }
    }

    // Pointing-hand cursor when the tile is actionable. A HoverHandler is the
    // only way to declare a cursor from QML — Qt 6's `Item` has no `cursor`
    // property — so a control that is not hovered falls back to whatever the
    // item underneath declares. The player supplies an arrow floor that way; see
    // the note on VideoPlayer's `stage`.
    HoverHandler {
        id: hh
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    AppTooltip {
        visible: root.tip !== "" && hh.hovered
        delay: 350
        text: root.tip
        preferAbove: root.tipAbove
        boundsName: root.tipBoundsName
    }

    // v4: hover warms the tile toward the accent (tint + border + a faint
    // halo) instead of a grey wash, and the glyph pops a touch, so even the
    // smallest action answers the pointer.
    // (string compare: two QML colour values are never === each other)
    readonly property color _hoverAccent: String(root.accent) === String(Theme.on_surface_var)
                                          ? Theme.primary : root.accent

    background: Item {
        // soft accent halo behind the tile (bordered tiles only)
        Rectangle {
            id: tileHalo
            anchors.fill: parent
            anchors.margins: 3
            radius: Tokens.radiusSm + 2
            color: root._hoverAccent
            visible: !root.chromeless && !root.overlay && root.enabled
            opacity: (root.hovered || root.active) ? 0.22 * (Theme.glow_level !== undefined ? Theme.glow_level : 1.0) : 0.0
            Behavior on opacity { NumberAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
            layer.enabled: tileHalo.visible && tileHalo.opacity > 0.01
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 24
                autoPaddingEnabled: true
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: root.overlay ? height / 2 : Tokens.radiusSm + 2
            color: root.chromeless ? U.withAlpha(Qt.rgba(0, 0, 0, 1), 0)
                   : root.overlay
                    ? U.withAlpha(Qt.rgba(0, 0, 0, 1), root.hovered ? 0.62 : 0.38)
                    // Translucent tints that keep ONE rgb and only move alpha, so
                    // the ColorAnimation never passes through a grey midpoint and
                    // the tile still sits on whatever surface hosts it.
                    : (root.active ? U.withAlpha(root.accent, 0.14)
                       : U.withAlpha(root._hoverAccent, root.hovered ? 0.10 : 0.0))
            border.width: (root.chromeless || root.overlay) ? 0 : 1
            border.color: root.active ? U.withAlpha(root.accent, 0.45)
                          : root.hovered ? U.withAlpha(root._hoverAccent, 0.45) : Theme.border
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
    }

    contentItem: IconGlyph {
        name: root.iconName
        fill: root.iconFill || root.active
        size: root.glyphSize
        glyphColor: (root.overlay || root.active) ? root.accent
                    : root.hovered ? root._hoverAccent : Theme.on_surface_var
        Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        scale: root.hovered && root.enabled ? 1.12 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    }
}
