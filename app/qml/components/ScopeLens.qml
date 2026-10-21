import QtQuick
import QtQuick.Shapes
import NicheScope

// "Scope" — the AI Chat's mark. A six-blade camera iris around a Signal-red
// tally light, drawn on a 120-unit grid with QtQuick.Shapes.
//
//   mode "idle"      breathes slowly (only when `breathe` is on)
//   mode "thinking"  stops down tight and turns, hunting for focus
//   mode "streaming" opens wide; the tally flickers with each token
//
// The blades are plain quads that overshoot the lens; the barrel ring drawn ON
// TOP of them hides the overshoot, so no clipping/masking is needed. Animation
// is a FrameAnimation that only runs while something is moving, so a page full
// of idle lenses (one per answer) costs nothing.
Item {
    id: root
    property int size: 40
    property string mode: "idle"
    property bool breathe: false
    readonly property bool _live: visible && (mode !== "idle" || (breathe && Tokens.appActive))
                                  && (App.ambientMotion === undefined || App.ambientMotion || mode !== "idle")

    property real open: 0.55
    property real rot: 0
    property real glow: 0.75
    property real _t: 0

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property real _R: 44
    function blade(i) {
        var N = 6, R = _R
        var twist = (1 - open) * 34 + rot
        var r = R * (0.12 + open * 0.5)
        var a0 = (i * 360 / N + twist) * Math.PI / 180
        var a1 = ((i + 1) * 360 / N + twist) * Math.PI / 180
        var sw = 62 * Math.PI / 180
        function p(a, rad) { return (60 + Math.cos(a) * rad).toFixed(2) + " " + (60 + Math.sin(a) * rad).toFixed(2) }
        return "M" + p(a0, r) + "L" + p(a1, r) + "L" + p(a1 + sw, R * 1.3) + "L" + p(a0 + sw, R * 1.3) + "Z"
    }

    FrameAnimation {
        running: root._live
        onTriggered: {
            var dt = Math.min(0.05, frameTime)
            root._t += dt
            var t = root._t, target, speed
            if (root.mode === "thinking") {
                target = 0.16 + Math.sin(t * 5) * 0.05
                speed = 70
                root.glow = 0.55 + Math.sin(t * 8) * 0.25
            } else if (root.mode === "streaming") {
                target = 0.78 + Math.sin(t * 9) * 0.03 + (Math.random() - 0.5) * 0.04
                speed = 14
                root.glow = 0.85 + Math.random() * 0.15
            } else {
                target = 0.55 + Math.sin(t * 1.25) * 0.08
                speed = 4
                root.glow = 0.7 + Math.sin(t * 1.25) * 0.12
            }
            root.open += (target - root.open) * Math.min(1, dt * 5)
            root.rot = (root.rot + speed * dt) % 360
        }
    }
    // Settle back to the rest pose when the motion stops.
    onModeChanged: if (mode === "idle" && !breathe) settle.restart()
    ParallelAnimation {
        id: settle
        NumberAnimation { target: root; property: "open"; to: 0.55; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "glow"; to: 0.75; duration: 420 }
    }

    Item {
        width: 120
        height: 120
        scale: root.size / 120
        transformOrigin: Item.TopLeft

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true
            // the red core
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: 60; centerY: 60; centerRadius: 44
                    focalX: 60; focalY: 60
                    GradientStop { position: 0.0; color: "#FFE3E8" }
                    GradientStop { position: 0.18; color: "#FF4A63" }
                    GradientStop { position: 0.55; color: "#B5001F" }
                    GradientStop { position: 1.0; color: "#2A0007" }
                }
                PathAngleArc { centerX: 60; centerY: 60; radiusX: 44; radiusY: 44; startAngle: 0; sweepAngle: 360 }
            }
        }
        // tally glow
        Rectangle {
            readonly property real rr: Math.min(15, 44 * (0.12 + root.open * 0.5))
            x: 60 - rr; y: 60 - rr
            width: rr * 2; height: rr * 2; radius: rr
            color: "#FF8597"
            opacity: root.glow
        }
        Repeater {
            model: 6
            delegate: Shape {
                required property int index
                width: 120; height: 120
                preferredRendererType: Shape.CurveRenderer
                antialiasing: true
                ShapePath {
                    strokeColor: "#55555F"
                    strokeWidth: 1.1
                    joinStyle: ShapePath.RoundJoin
                    fillGradient: LinearGradient {
                        x1: 10; y1: 10; x2: 110; y2: 110
                        GradientStop { position: 0.0; color: "#4A4A54" }
                        GradientStop { position: 1.0; color: "#17171B" }
                    }
                    PathSvg { path: root.blade(index) }
                }
            }
        }
        // barrel (hides the blades' overshoot) + rim + focus ticks
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true
            ShapePath {
                strokeColor: "#141417"
                strokeWidth: 16
                fillColor: "transparent"
                PathAngleArc { centerX: 60; centerY: 60; radiusX: 52; radiusY: 52; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: "#2B2B31"
                strokeWidth: 1.5
                fillColor: "transparent"
                PathAngleArc { centerX: 60; centerY: 60; radiusX: 44.5; radiusY: 44.5; startAngle: 0; sweepAngle: 360 }
            }
        }
        Item {
            anchors.fill: parent
            visible: root.size >= 26
            rotation: -root.rot * 0.5
            Repeater {
                model: 36
                delegate: Rectangle {
                    required property int index
                    x: 59.4; y: 3
                    width: 1.2; height: index % 3 === 0 ? 5 : 3
                    color: "#3A3A42"
                    transform: Rotation { origin.x: 0.6; origin.y: 57; angle: index * 10 }
                }
            }
        }
        // specular highlight
        Rectangle {
            x: 30; y: 33; width: 26; height: 12; radius: 6
            rotation: -38
            color: "white"
            opacity: 0.10
        }
    }
}
