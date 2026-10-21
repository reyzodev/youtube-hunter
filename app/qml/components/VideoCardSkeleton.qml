import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// VideoCardSkeleton — the loading stand-in for ArchiveVideoCard (v3.39.1).
//
// Shown in the Niche Finder grid while a search runs, so the page already has
// the SHAPE of its answer: inset media, hero number + meter, two title lines,
// channel row, three stats and the action row — same proportions as the real
// card, so when results land nothing jumps.
//
// One highlight band sweeps across the WHOLE card (not each bar on its own):
// the bones are drawn once as a mask and a single moving gradient is cut
// through it with MultiEffect, so every bar lights up in the same pass.
// `delay` offsets the sweep per card, which turns a grid of these into one
// wave travelling across the page.
//
//   ┌──────────────────────────────┐
//   │ ╭──────────────────────────╮ │
//   │ │           ▶              │ │   media (16:9)
//   │ ╰──────────────────────────╯ │
//   │ ▬▬▬▬▬            ▮▮▮▮▮       │   hero number · meter
//   │ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬         │   title, line 1
//   │ ▬▬▬▬▬▬▬▬▬▬▬▬                 │   title, line 2
//   │ (●) ▬▬▬▬▬▬▬                  │   channel
//   │     ▬▬▬▬                     │
//   │ ▬▬▬    ▬▬▬    ▬▬▬            │   stats
//   │ [▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬]  [▪] [▪]    │   actions
//   └──────────────────────────────┘
C.GlassPanel {
    id: sk
    property int cardWidth: 300
    property int delay: 0           // ms, staggers the sweep across a grid
    property bool running: true

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    readonly property real _inset: 6
    readonly property real _r: radius - _inset
    readonly property real _pad: Tokens.space4
    readonly property color _bone: U.mix(Theme.surface_high, Theme.on_surface, Theme.isDark ? 0.05 : 0.035)

    implicitWidth: cardWidth
    implicitHeight: bones.implicitHeight
    radius: Tokens.radiusXl
    elevation: 0.4

    // 0 → 1 position of the highlight band across the card
    property real _sweep: -0.5
    SequentialAnimation on _sweep {
        running: sk.running && sk.visible && sk._motion
        loops: Animation.Infinite
        PauseAnimation { duration: sk.delay }
        NumberAnimation { from: -0.5; to: 1.5; duration: 1400; easing.type: Easing.InOutSine }
        PauseAnimation { duration: Math.max(0, 520 - sk.delay) }
    }

    // ── the bones: drawn visibly AND reused (layered) as the shine mask ──
    Item {
        id: bonesLayer
        anchors.fill: parent
        layer.enabled: true

        // soft breathing so the card never looks frozen between sweeps
        SequentialAnimation on opacity {
            running: sk.running && sk.visible && sk._motion
            loops: Animation.Infinite
            NumberAnimation { to: 0.7; duration: 950; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 950; easing.type: Easing.InOutQuad }
        }

        ColumnLayout {
            id: bones
            width: parent.width
            spacing: 0

            // media
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: sk._inset
                Layout.rightMargin: sk._inset
                Layout.topMargin: sk._inset
                Layout.preferredHeight: Math.round((sk.width - sk._inset * 2) * 9 / 16)
                radius: sk._r
                color: sk._bone
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: "movie"
                    size: 22
                    glyphColor: U.withAlpha(Theme.outline, 0.45)
                }
            }

            // hero number + signal meter
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: sk._pad
                Layout.rightMargin: sk._pad
                Layout.topMargin: Tokens.space4
                spacing: Tokens.space2
                Rectangle { implicitWidth: sk.width * 0.30; implicitHeight: 26; radius: 7; color: sk._bone }
                Item { Layout.fillWidth: true }
                Row {
                    spacing: 3
                    Repeater {
                        model: 5
                        Rectangle {
                            width: 6; radius: 2
                            height: 8 + index * 3
                            anchors.bottom: parent ? parent.bottom : undefined
                            color: sk._bone
                        }
                    }
                }
            }

            // title, two lines
            Rectangle {
                Layout.leftMargin: sk._pad
                Layout.topMargin: Tokens.space4
                implicitWidth: (sk.width - sk._pad * 2) * 0.92
                implicitHeight: 12; radius: 6; color: sk._bone
            }
            Rectangle {
                Layout.leftMargin: sk._pad
                Layout.topMargin: Tokens.space2
                implicitWidth: (sk.width - sk._pad * 2) * 0.58
                implicitHeight: 12; radius: 6; color: sk._bone
            }

            // channel
            RowLayout {
                Layout.leftMargin: sk._pad
                Layout.topMargin: Tokens.space4
                spacing: Tokens.space2
                Rectangle { implicitWidth: 30; implicitHeight: 30; radius: 15; color: sk._bone }
                ColumnLayout {
                    spacing: 6
                    Rectangle { implicitWidth: sk.width * 0.34; implicitHeight: 10; radius: 5; color: sk._bone }
                    Rectangle { implicitWidth: sk.width * 0.22; implicitHeight: 8;  radius: 4; color: sk._bone }
                }
            }

            // hairline
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: sk._pad
                Layout.rightMargin: sk._pad
                Layout.topMargin: Tokens.space4
                implicitHeight: 1
                color: U.withAlpha(Theme.border, 0.8)
            }

            // stats
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: sk._pad
                Layout.rightMargin: sk._pad
                Layout.topMargin: Tokens.space3
                spacing: Tokens.space4
                Repeater {
                    model: 3
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle { implicitWidth: sk.width * 0.16; implicitHeight: 14; radius: 5; color: sk._bone }
                        Rectangle { implicitWidth: sk.width * 0.11; implicitHeight: 8;  radius: 4; color: sk._bone }
                    }
                }
            }

            // actions
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: sk._pad
                Layout.rightMargin: sk._pad
                Layout.topMargin: Tokens.space4
                Layout.bottomMargin: sk._pad
                spacing: Tokens.space2
                Rectangle { Layout.fillWidth: true; implicitHeight: 36; radius: Tokens.radiusMd; color: sk._bone }
                Rectangle { implicitWidth: 36; implicitHeight: 36; radius: Tokens.radiusMd; color: sk._bone }
                Rectangle { implicitWidth: 36; implicitHeight: 36; radius: Tokens.radiusMd; color: sk._bone }
            }
        }
    }

    // ── the shine: one diagonal band, cut to the bones' shape ──
    Item {
        id: shine
        anchors.fill: parent
        visible: false
        layer.enabled: true
        clip: true
        Rectangle {
            width: Math.max(90, sk.width * 0.55)
            height: sk.height * 2
            y: -sk.height / 2
            x: sk._sweep * sk.width - width / 2
            rotation: 16
            transformOrigin: Item.Center
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.on_surface, 0.0) }
                GradientStop { position: 0.5; color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.16 : 0.11) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.on_surface, 0.0) }
            }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: shine
        maskEnabled: true
        maskSource: bonesLayer
        visible: sk._motion
    }
}
