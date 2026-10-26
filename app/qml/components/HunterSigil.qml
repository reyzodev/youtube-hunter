import QtQuick
import QtQuick.Shapes
import NicheScope

// "Hunter" — the AI Chat's mark (replaces the v3.14 ScopeLens iris).
// The YouTube Hunter crest on a dark badge, inside four HUD brackets: the same
// lock-on language as the launch screen, so the assistant reads as part of the
// brand instead of a leftover camera lens from the Niche Scope days.
// Drawn on a 120-unit grid with QtQuick.Shapes.
//
//   mode "idle"      brackets rest wide and dim; the halo breathes (`breathe`)
//   mode "thinking"  brackets turn and pulse in and out, hunting for the target
//   mode "streaming" brackets snap shut in brand red; the play glints per token
//
// Animation is a FrameAnimation that only runs while something is moving, so a
// page full of idle sigils (one per answer) costs nothing. Same public API as
// ScopeLens: size / mode / breathe.
Item {
    id: root
    property int size: 40
    property string mode: "idle"
    property bool breathe: false
    readonly property bool _live: visible && (mode !== "idle" || (breathe && Tokens.appActive))
                                  && (App.ambientMotion === undefined || App.ambientMotion || mode !== "idle")

    // 0 = brackets wide/neutral, 1 = closed on the crest
    property real lock: 0.0
    property real heat: 0.0          // 0..1 how red the brackets are
    property real rot: 0
    property real glow: 0.7
    property real _t: 0

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property color _a: Theme.logo_grad_in
    readonly property color _b: Theme.logo_grad_out
    readonly property color _dark: Qt.darker(_a, 2.1)
    readonly property color _deep: Qt.darker(_a, 4.2)
    readonly property color _idle: "#5A5A64"
    readonly property color _bracket: Qt.rgba(_idle.r + (_a.r - _idle.r) * heat,
                                              _idle.g + (_a.g - _idle.g) * heat,
                                              _idle.b + (_a.b - _idle.b) * heat, 1)

    FrameAnimation {
        running: root._live
        onTriggered: {
            var dt = Math.min(0.05, frameTime)
            root._t += dt
            var t = root._t, tLock, tHeat, speed
            if (root.mode === "thinking") {
                tLock = 0.45 + Math.sin(t * 5.5) * 0.35
                tHeat = 0.65
                speed = 90
                root.glow = 0.55 + Math.sin(t * 8) * 0.25
            } else if (root.mode === "streaming") {
                tLock = 1.0
                tHeat = 1.0
                speed = 0
                root.glow = 0.85 + Math.random() * 0.15
            } else {
                tLock = 0.15 + Math.sin(t * 1.25) * 0.08
                tHeat = 0.0
                speed = 0
                root.glow = 0.62 + Math.sin(t * 1.25) * 0.14
            }
            var k = Math.min(1, dt * 9)
            root.lock += (tLock - root.lock) * k
            root.heat += (tHeat - root.heat) * k
            if (speed > 0) {
                root.rot = (root.rot + speed * dt) % 90
            } else {
                // settle onto the nearest square angle
                var target = root.rot > 45 ? 90 : 0
                root.rot += (target - root.rot) * k
                if (Math.abs(target - root.rot) < 0.05) root.rot = 0
            }
        }
    }
    onModeChanged: if (mode === "idle" && !breathe) settle.restart()
    ParallelAnimation {
        id: settle
        NumberAnimation { target: root; property: "lock"; to: 0.0; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "heat"; to: 0.0; duration: 420 }
        NumberAnimation { target: root; property: "rot"; to: 0; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "glow"; to: 0.7; duration: 420 }
    }

    Item {
        width: 120
        height: 120
        scale: root.size / 120
        transformOrigin: Item.TopLeft

        // dark badge (dark in both themes, like a physical emblem)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true
            ShapePath {
                strokeColor: "#2A2A31"
                strokeWidth: 1.5
                fillGradient: RadialGradient {
                    centerX: 60; centerY: 64; centerRadius: 58
                    focalX: 60; focalY: 58
                    GradientStop { position: 0.0; color: "#1E0E12" }
                    GradientStop { position: 0.7; color: "#101013" }
                    GradientStop { position: 1.0; color: "#09090B" }
                }
                PathAngleArc { centerX: 60; centerY: 60; radiusX: 58; radiusY: 58; startAngle: 0; sweepAngle: 360 }
            }
        }
        // red light behind the crest
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.glow
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: 60; centerY: 60; centerRadius: 40
                    focalX: 60; focalY: 60
                    GradientStop { position: 0.0; color: Qt.rgba(root._a.r, root._a.g, root._a.b, 0.55) }
                    GradientStop { position: 1.0; color: Qt.rgba(root._a.r, root._a.g, root._a.b, 0) }
                }
                PathAngleArc { centerX: 60; centerY: 60; radiusX: 40; radiusY: 40; startAngle: 0; sweepAngle: 360 }
            }
        }

        // the crest (738 x 812 design box → 46 x 51 here)
        Item {
            id: art
            readonly property real k: 51 / 812
            width: 738; height: 812
            transformOrigin: Item.TopLeft
            scale: k
            x: 60 - 738 * k / 2
            y: 61 - 812 * k / 2
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"; strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 240; x2: 0; y2: 804
                        GradientStop { position: 0.0; color: root._a }
                        GradientStop { position: 0.45; color: root._b }
                        GradientStop { position: 1.0; color: root._dark }
                    }
                    PathPolyline { path: [Qt.point(156, 240), Qt.point(231, 322), Qt.point(231, 444), Qt.point(310, 524), Qt.point(318, 662), Qt.point(363, 804), Qt.point(156, 526), Qt.point(156, 240)] }
                }
                ShapePath {
                    strokeColor: "transparent"; strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 240; x2: 0; y2: 804
                        GradientStop { position: 0.0; color: root._a }
                        GradientStop { position: 0.45; color: root._b }
                        GradientStop { position: 1.0; color: root._dark }
                    }
                    PathPolyline { path: [Qt.point(582, 526), Qt.point(375, 804), Qt.point(420, 662), Qt.point(428, 524), Qt.point(507, 444), Qt.point(507, 322), Qt.point(582, 240), Qt.point(582, 526)] }
                }
                ShapePath {
                    strokeColor: "transparent"; strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: 812
                        GradientStop { position: 0.0; color: root._a }
                        GradientStop { position: 0.40; color: root._b }
                        GradientStop { position: 0.78; color: root._dark }
                        GradientStop { position: 1.0; color: root._deep }
                    }
                    PathPolyline { path: [Qt.point(0, 0), Qt.point(304, 146), Qt.point(304, 260), Qt.point(369, 304), Qt.point(434, 260), Qt.point(434, 146), Qt.point(738, 0), Qt.point(475, 307), Qt.point(475, 477), Qt.point(418, 532), Qt.point(410, 662), Qt.point(369, 812), Qt.point(328, 662), Qt.point(320, 532), Qt.point(263, 477), Qt.point(263, 307), Qt.point(0, 0)] }
                }
                ShapePath {
                    strokeColor: "transparent"; strokeWidth: -1
                    fillColor: "#FFFFFF"
                    PathPolyline { path: [Qt.point(324, 351), Qt.point(427, 422), Qt.point(324, 493), Qt.point(324, 351)] }
                }
            }
        }

        // HUD brackets: wide + dim at rest, closed + red when answering
        Item {
            id: reticle
            visible: root.size >= 24
            x: 60; y: 60
            width: 0; height: 0
            rotation: root.rot
            readonly property real d: 38 - root.lock * 6       // half-size of the bracket square
            readonly property real arm: 11
            readonly property real th: 3.2
            Repeater {
                model: 4
                delegate: Item {
                    required property int index
                    width: 0; height: 0
                    transformOrigin: Item.TopLeft
                    rotation: index * 90
                    Rectangle {
                        x: -reticle.d; y: -reticle.d
                        width: reticle.arm; height: reticle.th
                        color: root._bracket
                        antialiasing: true
                    }
                    Rectangle {
                        x: -reticle.d; y: -reticle.d
                        width: reticle.th; height: reticle.arm
                        color: root._bracket
                        antialiasing: true
                    }
                }
            }
        }

        // glass highlight on the badge
        Rectangle {
            x: 26; y: 18; width: 34; height: 12; radius: 6
            rotation: -30
            color: "white"
            opacity: 0.06
        }
    }
}
