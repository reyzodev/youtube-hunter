import QtQuick
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// v4 icon tile — the app's "icon pack" container. One glyph sitting in a
// rounded square, in two strengths:
//
//   solid: true   accent → accent2 gradient face, white glyph, glass edge,
//                 and a blurred halo underneath (page headers, hero spots).
//   solid: false  soft tinted well with an accent glyph and a tinted hairline
//                 (stat cards, list rows, section heads).
//
// `lit` raises the halo (bind it to a parent's hover) and `breathe` lets the
// solid tile's halo pulse slowly at rest.
//
//     C.IconTile { iconName: "diamond"; size: 30 }
//     C.IconTile { iconName: "travel_explore"; solid: true; size: 46; breathe: true }
Item {
    id: root
    property string iconName: ""
    property bool solid: false
    property int size: 32
    property int glyphSize: Math.round(size * 0.52)
    property color tint: Theme.primary
    property color tint2: String(tint) === String(Theme.primary)
                          ? U.mix(Theme.primary, Theme.primary_deep, 0.7)
                          : U.mix(tint, Qt.rgba(1, 1, 1, 1), 0.18)
    property bool lit: false
    property bool breathe: false
    property bool iconFill: true
    // false = keep the font glyph (used by the sidebar)
    property bool iconSvg: true
    property real radius: Math.round(size * 0.30)

    readonly property real _glowK: Theme.glow_level !== undefined ? Theme.glow_level : 1.0

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    // slow 0..1 pulse used by the halo when `breathe` is on
    property real _breath: 0
    SequentialAnimation on _breath {
        running: root.breathe && root.solid && root.visible && App.ambientMotion !== false && Tokens.appActive
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 2800; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 2800; easing.type: Easing.InOutSine }
    }

    // halo (solid only) — a blurred proxy, never the glyph itself
    Rectangle {
        id: halo
        visible: root.solid
        anchors.fill: parent
        anchors.margins: 2
        anchors.topMargin: 6
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.tint }
            GradientStop { position: 1.0; color: root.tint2 }
        }
        // v6: a resting halo of 0.22 (was 0.40 + breathing 0.22) — the tile reads
        // as a lit object, not a lamp.
        opacity: (root.lit ? 0.48 : 0.22 + 0.06 * root._breath) * root._glowK
        Behavior on opacity { NumberAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
        layer.enabled: halo.visible
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 32
            autoPaddingEnabled: true
        }
    }

    // face
    Rectangle {
        id: face
        anchors.fill: parent
        radius: root.radius
        color: root.solid ? root.tint : U.withAlpha(root.tint, root.lit ? 0.16 : 0.10)
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        border.width: 1
        border.color: root.solid ? Qt.rgba(1, 1, 1, 0.18)
                                 : U.withAlpha(root.tint, root.lit ? 0.34 : 0.18)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

        // gradient face for the solid tile
        Rectangle {
            visible: root.solid
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, root.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.tint2 }
                GradientStop { position: 1.0; color: root.tint }
            }
        }
        // specular sheen
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: parent.height * 0.5
            radius: Math.max(0, root.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.solid ? 0.14 : 0.04) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        IconGlyph {
            anchors.centerIn: parent
            svg: root.iconSvg
            name: root.iconName
            fill: root.iconFill
            size: root.glyphSize
            glyphColor: root.solid ? Theme.on_primary : root.tint
            scale: root.lit ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
    }
}
