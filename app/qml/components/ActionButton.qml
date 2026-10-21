import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import NicheScope
import "." as C
import "../Utils.js" as U

// v18 Settings action key that MORPHS through its job instead of handing the
// result to a status line somewhere else:
//
//   idle  [ (✓) Validate ]   accent face, lit like a key
//   busy  [ (⟳) Checking… ]  a light sweep rides across the face
//   ok    [ (✓) Valid     ]  face turns green
//   fail  [ (✕) Failed    ]  face turns red and the key shakes once
//
// `status`: 0 idle · 1 busy · 2 ok · 3 failed. The owner decides when to go
// back to 0 (usually when the input it checks is edited again).
// `variant`: "primary" (filled) | "ghost" (neutral surface, accent on hover).
// `compact` = 40px row button; the default 54px matches a SmartField.
AbstractButton {
    id: root

    property string iconName: ""
    property string variant: "primary"
    property int status: 0
    property string busyText: ""
    property string okText: ""
    property string failText: ""
    property bool compact: false

    readonly property bool filled: root.variant === "primary" || root.status === 2 || root.status === 3
    readonly property color base: root.status === 2 ? Theme.secondary_container
                                : root.status === 3 ? Theme.error
                                : Theme.primary
    readonly property color base2: root.status === 2 ? U.mix(Theme.secondary_container, Qt.rgba(0.1, 0.75, 0.85, 1), 0.35)
                                 : root.status === 3 ? U.mix(Theme.error, Qt.rgba(1, 0.55, 0.35, 1), 0.35)
                                 : U.mix(Theme.primary, Theme.primary_deep, 0.7)
    readonly property real _glowK: Theme.glow_level !== undefined ? Theme.glow_level : 1.0
    readonly property string shownText: root.status === 1 && root.busyText !== "" ? root.busyText
                                      : root.status === 2 && root.okText !== "" ? root.okText
                                      : root.status === 3 && root.failText !== "" ? root.failText
                                      : root.text

    implicitHeight: root.compact ? 40 : 54
    implicitWidth: Math.max(root.compact ? 84 : 136, row.implicitWidth + (root.compact ? 30 : 44))
    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

    HoverHandler { enabled: root.enabled; cursorShape: Qt.PointingHandCursor }

    scale: root.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

    // one shake on failure
    transform: Translate { id: shakeT; x: 0 }
    onStatusChanged: if (root.status === 3) shake.restart()
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeT; property: "x"; to: -6; duration: 45; easing.type: Easing.OutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: 6;  duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: -4; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: 3;  duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: 0;  duration: 50; easing.type: Easing.OutQuad }
    }

    background: Item {
        // ── halo ── light pooling under a filled, full-size key. Compact keys
        // skip it: a list of ten rows should not run ten blur passes.
        Rectangle {
            id: halo
            visible: root.filled && root.enabled && !root.compact
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 12
            anchors.bottomMargin: -4
            radius: 14
            color: root.base
            opacity: (root.pressed ? 0.12 : root.hovered ? 0.42 : 0.22) * root._glowK
            Behavior on opacity { NumberAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
            layer.enabled: halo.visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 32
                autoPaddingEnabled: true
            }
        }

        Rectangle {
            id: face
            anchors.fill: parent
            radius: root.compact ? 11 : 14
            clip: true
            color: root.filled ? root.base
                 : root.pressed ? Theme.hover_bg_strong
                 : root.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                 : Theme.surface_low
            border.width: root.filled ? 0 : 1
            border.color: root.hovered || root.activeFocus
                          ? U.mix(Theme.border_med, Theme.primary, 0.5) : Theme.border_med
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

            // gradient face
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: root.filled
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.base }
                    GradientStop { position: 1.0; color: root.base2 }
                }
            }
            // top gloss: a key lit from above. v3.27: carries the face's
            // radius - without it the band's square top corners stuck out past
            // the rounded key as a pale rectangle (`clip` cuts to the square
            // box, not to the rounded shape). The rounded bottom of the band
            // sits where the gradient is already fully transparent.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * 0.55
                radius: parent.radius
                visible: root.filled
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
            // 1px specular edge
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.radius * 2
                height: 1
                color: root.filled ? Qt.rgba(1, 1, 1, 0.30) : Theme.glass_hi
            }
            // hover brighten (v3.27: rounded like the face, same reason)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: root.filled
                color: "#ffffff"
                opacity: root.pressed ? 0.0 : root.hovered ? 0.08 : 0.0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
            // busy sweep - a light band crossing the face. v3.27: masked to the
            // rounded face so it no longer shows square corners as it passes.
            C.RoundClip {
                anchors.fill: parent
                radius: face.radius
                active: root.status === 1
                visible: root.status === 1
                Rectangle {
                    id: sweep
                    visible: root.status === 1
                    width: Math.max(40, parent.width * 0.45)
                    height: parent.height
                    x: -width
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.5; color: root.filled ? Qt.rgba(1, 1, 1, 0.26) : U.withAlpha(Theme.primary, 0.20) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                    NumberAnimation on x {
                        running: sweep.visible
                        loops: Animation.Infinite
                        from: -sweep.width
                        to: face.width
                        duration: 1150
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        // keyboard focus ring
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: face.radius + 3
            color: "transparent"
            border.width: 2
            border.color: U.withAlpha(Theme.primary, 0.45)
            visible: root.visualFocus
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.compact ? 7 : 10

            Item {
                visible: root.iconName !== "" || root.status !== 0
                width: root.compact ? 18 : 26
                height: width
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    visible: !root.compact
                    anchors.fill: parent
                    radius: width / 2
                    color: root.filled ? Qt.rgba(1, 1, 1, 0.20) : U.withAlpha(Theme.primary, 0.12)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }
                C.IconGlyph {
                    anchors.centerIn: parent
                    visible: root.status !== 1
                    name: root.status === 2 ? "check" : root.status === 3 ? "close" : root.iconName
                    fill: true
                    size: root.compact ? 15 : 15
                    glyphColor: root.filled ? Theme.on_primary
                              : root.hovered ? Theme.primary : Theme.on_surface_var
                    Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                C.SpinnerGlyph {
                    anchors.centerIn: parent
                    visible: root.status === 1
                    name: "refresh"
                    spinning: visible
                    size: 15
                    glyphColor: root.filled ? Theme.on_primary : Theme.primary
                }
            }
            C.AppText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.shownText
                weight: Tokens.weightBold
                font.pixelSize: root.compact ? Tokens.fontBody : Tokens.fontLabel
                color: root.filled ? Theme.on_primary
                     : root.hovered ? Theme.text_strong : Theme.on_surface
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
        }
    }
}
