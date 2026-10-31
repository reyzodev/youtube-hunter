import QtQuick
import QtQuick.Shapes
import QtQuick.Controls.Basic
import NicheScope
import "../Utils.js" as U

// v3.41.3 — theme switch, redesigned again: "Eclipse".
//
//   light:  ( ✺  ·  ı ı ı )   a sun made of the ACCENT, rangefinder ticks
//   dark:   ( ·  ·  ·   ◐ )   the same accent eclipsed to a crescent, with a
//                              thin corona; the ticks have become stars
//
// Why it changed: v3.41.2 painted the switch in fixed day/night colours
// (yellow sun, navy night). Every other control in the title bar is graphite
// + the user's accent, so the yellow pill was the one thing on screen that
// belonged to a different app. Now:
//
//   · the TRACK is the same surface/hairline the language pill uses
//     (Theme.surface_low + Theme.border), so the two read as a set;
//   · the SUN and the ECLIPSE are drawn in Theme.primary → primary_deep, so
//     they follow the accent picked in Settings (Signal, Ocean, Aurora…);
//   · the rangefinder ticks echo the "Lock-on" theme curtain they trigger.
//
// The crescent is a real path (not a track-coloured disc laid over a disc),
// so it reads correctly on both palettes even while the thumb is heading to
// night with the light palette still live behind it.
//
// Motion rules kept from v3.41: everything that MOVES is an Animator (X /
// Opacity / Rotation / Scale on the render thread) and nothing animates a
// colour, so the palette can be republished behind the curtain without a
// single ColorAnimation. The thumb answers the CLICK (_pendingDark), not
// Theme.isDark.
// v1.0.3 — "Daybreak" refresh. The thumb is now a raised DISC (the way a
// physical toggle is), carrying the sun / crescent on its face, so the switch
// reads as one solid object and matches the hero copy of itself the theme
// curtain plays (ThemeWipe). At night the track fills with a soft accent
// gradient under the stars; by day it stays the title bar's own material.
// Hover lifts the thumb's glow; press squashes it. Same motion rules: only
// Animators move, no colour ever animates.
AbstractButton {
    id: root
    implicitWidth: 60
    implicitHeight: 30
    hoverEnabled: true

    readonly property bool dark: Theme.isDark

    // -1 = no pending switch, 0/1 = heading to light/dark.
    property int _pendingDark: -1
    readonly property bool _showDark: _pendingDark >= 0 ? _pendingDark === 1 : dark
    onDarkChanged: _pendingDark = -1
    Timer {
        // safety net: a wipe that was refused (one already running) must not
        // leave the thumb on the wrong side
        id: pendingReset
        interval: 2600
        onTriggered: root._pendingDark = -1
    }

    readonly property bool _hot: hover.hovered
    // decorative loops (stars, sun breathing) respect "ambient motion" and
    // stop when the window is in the background
    readonly property bool _ambient: root.visible && Tokens.appActive
                                     && App.ambientMotion !== false

    // HoverHandler (not AbstractButton.hovered): opening the tooltip Popup
    // makes the built-in `hovered` blink. See v3.39 notes.
    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        // the pointer is on its way to a click: make sure the other palette's
        // icons are already rasterised (no-op when they are).
        onHoveredChanged: if (hovered) App.prewarmThemeSwap()
    }

    AppTooltip {
        visible: hover.hovered
        delay: 350
        text: root.dark ? I18n.tr("Switch to light theme")
                        : I18n.tr("Switch to dark theme")
    }

    background: Item {
        // ── track: the title bar's own pill material ──
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.surface_low
            border.width: 1
            border.color: Theme.border
        }
        // hover: hairline steps up to the accent (opacity, never a colour anim)
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: Theme.primary
            opacity: root._hot ? 0.55 : 0
            Behavior on opacity { OpacityAnimator { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        // a breath of accent light inside the track on hover
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            color: Theme.primary
            opacity: root._hot ? (root._showDark ? 0.07 : 0.05) : 0
            Behavior on opacity { OpacityAnimator { duration: Tokens.durMed } }
        }

        // ── night: an accent dusk fills the track from the thumb's side ──
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            opacity: root._showDark ? 1 : 0
            Behavior on opacity { OpacityAnimator { duration: 420; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.02) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.20) }
            }
        }

        // ── light: rangefinder ticks on the free (right) side ──
        Item {
            anchors.fill: parent
            opacity: root._showDark ? 0 : 1
            Behavior on opacity { OpacityAnimator { duration: 260; easing.type: Easing.OutCubic } }
            Repeater {
                model: [ { x: 36, h: 6 }, { x: 42, h: 10 }, { x: 48, h: 6 } ]
                Rectangle {
                    required property var modelData
                    required property int index
                    x: modelData.x
                    width: 2; radius: 1
                    height: modelData.h
                    y: (root.height - height) / 2
                    // the centre tick is the "aim" mark: it takes the accent
                    color: index === 1 ? Theme.primary : Theme.outline
                    opacity: index === 1 ? 0.75 : 0.45
                }
            }
        }

        // ── dark: the ticks have become stars, on the free (left) side ──
        Item {
            anchors.fill: parent
            opacity: root._showDark ? 1 : 0
            Behavior on opacity { OpacityAnimator { duration: 420; easing.type: Easing.OutCubic } }
            Repeater {
                model: [
                    { x: 10, y: 10, s: 2.5, d: 0,    a: false },
                    { x: 17, y: 17, s: 2.0, d: 600,  a: true  },
                    { x: 24, y: 9,  s: 1.6, d: 1150, a: false },
                    { x: 13, y: 21, s: 1.4, d: 300,  a: false }
                ]
                Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y
                    width: modelData.s; height: modelData.s; radius: modelData.s / 2
                    // one star carries the accent, the rest are plain light
                    color: modelData.a ? Theme.primary : Theme.on_surface_var
                    SequentialAnimation on opacity {
                        running: root._showDark && root._ambient
                        loops: Animation.Infinite
                        PauseAnimation { duration: modelData.d }
                        NumberAnimation { from: 1; to: 0.25; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.25; to: 1; duration: 1200; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    contentItem: Item { }

    // ── the thumb: a raised disc, sun ↔ crescent on its face ──
    Item {
        id: thumb
        width: 24; height: 24
        y: (root.height - height) / 2
        x: root._showDark ? root.width - width - 3 : 3
        Behavior on x { XAnimator { duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
        scale: root.pressed ? 0.86 : root._hot ? 1.06 : 1
        Behavior on scale { ScaleAnimator { duration: 200; easing.type: Easing.OutCubic } }

        // accent glow behind the disc
        Rectangle {
            anchors.centerIn: parent
            width: 32; height: 32; radius: 16
            color: Theme.primary
            opacity: root._hot ? 0.22 : 0.10
            Behavior on opacity { OpacityAnimator { duration: 260 } }
        }
        // drop
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 1.5
            width: 24; height: 24; radius: 12
            color: Qt.rgba(0, 0, 0, Theme.isDark ? 0.45 : 0.14)
        }
        // the disc: white by day, raised graphite at night
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.isDark ? Theme.surface_highest : "#FFFFFF"
            border.width: 1
            border.color: root._hot ? U.withAlpha(Theme.primary, 0.55)
                                    : (Theme.isDark ? U.withAlpha("#FFFFFF", 0.08) : Theme.border)
            antialiasing: true
            // 1 px top light: a lit object, not a flat dot
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 1
                width: 12; height: 1; radius: 0.5
                color: "#FFFFFF"
                opacity: Theme.isDark ? 0.14 : 0.0
            }
        }

        // ── SUN ──────────────────────────────────────────────────────
        // eight short rays around an accent core; on hover they click round
        // by one notch (like a lens ring), at night they fold away.
        Item {
            id: rays
            anchors.fill: parent
            opacity: root._showDark ? 0 : 1
            scale: root._showDark ? 0.4 : 1
            rotation: root._showDark ? 90 : (root._hot ? 45 : 0)
            Behavior on opacity { OpacityAnimator { duration: 220 } }
            Behavior on scale { ScaleAnimator { duration: 360; easing.type: Easing.OutCubic } }
            Behavior on rotation { RotationAnimator { duration: 420; easing.type: Easing.OutCubic } }
            Repeater {
                model: 8
                Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 45
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 3
                        width: 1.6; height: 3; radius: 0.8
                        color: Theme.primary
                        opacity: index % 2 === 0 ? 1 : 0.65
                        antialiasing: true
                    }
                }
            }
        }
        // slow breathing lives on a wrapper, so it never fights the
        // day/night scale transition on the core itself
        Item {
            id: sunBreath
            anchors.fill: parent
            SequentialAnimation on scale {
                running: !root._showDark && root._ambient && !root._hot
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 1.08; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.08; to: 1; duration: 1800; easing.type: Easing.InOutSine }
            }
            Rectangle {
                id: sunCore
                anchors.centerIn: parent
                width: 9; height: 9; radius: 4.5
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(Theme.primary, 1.25) }
                    GradientStop { position: 1.0; color: Theme.primary_deep }
                }
                opacity: root._showDark ? 0 : 1
                scale: root._showDark ? 1.5 : 1
                Behavior on opacity { OpacityAnimator { duration: 240 } }
                Behavior on scale { ScaleAnimator { duration: 360; easing.type: Easing.OutCubic } }
            }
        }

        // ── CRESCENT ─────────────────────────────────────────────────
        // a 14px accent crescent (the 18-unit path, scaled) on the disc
        Item {
            id: crescent
            width: 18; height: 18
            anchors.centerIn: parent
            opacity: root._showDark ? 1 : 0
            scale: root._showDark ? (root._hot ? 0.86 : 0.78) : 0.4
            rotation: root._showDark ? (root._hot ? -14 : 0) : -70
            Behavior on opacity { OpacityAnimator { duration: 300; easing.type: Easing.OutCubic } }
            Behavior on scale { ScaleAnimator { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on rotation { RotationAnimator { duration: 460; easing.type: Easing.OutCubic } }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: 0; y1: 18; x2: 18; y2: 0
                        GradientStop { position: 0.0; color: Qt.lighter(Theme.primary, 1.15) }
                        GradientStop { position: 1.0; color: Theme.primary_deep }
                    }
                    startX: 7.567; startY: 0.115
                    // outer edge: the long way round, through the lower left
                    PathArc {
                        x: 17.885; y: 10.433
                        radiusX: 9; radiusY: 9
                        useLargeArc: true
                        direction: PathArc.Counterclockwise
                    }
                    // the bite: back along the shadow disc's edge
                    PathArc {
                        x: 7.567; y: 0.115
                        radiusX: 7.4; radiusY: 7.4
                        useLargeArc: false
                        direction: PathArc.Clockwise
                    }
                }
            }
        }
    }

    // The switch does not apply the theme itself: it asks the window to play the
    // curtain from this control's centre, and the window applies the palette at
    // the moment the curtain covers everything (see Main.qml / ThemeWipe).
    signal wipeRequested(real cx, real cy, string preference)

    onClicked: {
        const p = mapToItem(null, width / 2, height / 2)
        const pref = App.nextThemePreference
        root._pendingDark = pref === "dark" ? 1 : 0
        pendingReset.restart()
        root.wipeRequested(p.x, p.y, pref)
    }
}
