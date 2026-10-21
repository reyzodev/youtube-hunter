import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.39 — "Hunt scope". The search's own instrument: the YouTube Hunter mark
// sits in the middle of a radar scope, and everything around it is the run.
//
//   sweep      a conic beam circles the scope. It is the "still alive" signal
//              — it never stops while the run is running, so a stuck network
//              call can never be mistaken for a finished one.
//   blips      one contact per ~12 candidate videos actually found (capped).
//              Each one pops in with a ping, then flares every time the beam
//              passes over it. The count is real; only the positions are art.
//   ring       the outer arc IS the progress bar — the backend's percentage,
//              eased. Indeterminate runs get a short orbiting arc instead.
//   brackets   the viewfinder from the theme lock-on. They close in on the
//              mark as the run nears 100%: literally "locking on".
//
// Cheap on purpose: a handful of Rectangles, three Shapes, the vector mark.
// The one per-frame value (`sweep`) drives at most 12 opacity bindings.
Item {
    id: root

    property int size: 132
    property int pct: -1                 // 0..100, or <0 = not measurable yet
    property int found: 0                // candidate videos so far
    property bool running: true
    property color accent: Theme.primary

    implicitWidth: size + 24
    implicitHeight: size + 24
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property real _c: width / 2
    readonly property real _r: size / 2
    readonly property bool _live: running && visible && Tokens.appActive
    readonly property int blips: Math.min(12, Math.ceil(found / 12))
    property real sweep: 0               // beam angle, degrees clockwise from 3 o'clock
    property real _shownPct: Math.max(0, pct)
    Behavior on _shownPct { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

    NumberAnimation on sweep {
        running: root._live
        from: 0; to: 360
        duration: 2600
        loops: Animation.Infinite
    }

    // ── soft bloom behind the scope ──
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root._c; centerY: root._c
                centerRadius: root._r + 12
                focalX: root._c; focalY: root._c
                GradientStop { position: 0.0; color: U.withAlpha(root.accent, Theme.isDark ? 0.22 : 0.14) }
                GradientStop { position: 0.7; color: U.withAlpha(root.accent, 0.05) }
                GradientStop { position: 1.0; color: U.withAlpha(root.accent, 0.0) }
            }
            PathAngleArc { centerX: root._c; centerY: root._c; radiusX: root._r + 12; radiusY: root._r + 12; startAngle: 0; sweepAngle: 360 }
        }
    }

    // ── the scope face ──
    Rectangle {
        id: face
        width: root.size; height: root.size; radius: width / 2
        anchors.centerIn: parent
        color: U.withAlpha(root.accent, Theme.isDark ? 0.07 : 0.045)
        border.width: 1
        border.color: U.withAlpha(root.accent, 0.22)
        antialiasing: true
    }
    Repeater {
        model: [0.34, 0.67]
        delegate: Rectangle {
            required property real modelData
            width: root.size * modelData; height: width; radius: width / 2
            anchors.centerIn: parent
            color: "transparent"
            border.width: 1
            border.color: U.withAlpha(root.accent, 0.13)
            antialiasing: true
        }
    }
    // crosshair, broken at the centre so it never cuts through the mark.
    // Each arm lives in a full-size Item rotated about the scope centre.
    Repeater {
        model: [0, 90, 180, 270]
        delegate: Item {
            required property real modelData
            anchors.fill: parent
            rotation: modelData
            Rectangle {
                x: root._c + root._r * 0.30
                y: root._c - 0.5
                width: root._r * 0.66
                height: 1
                color: U.withAlpha(root.accent, 0.16)
            }
        }
    }

    // ── the beam ──
    Item {
        id: beam
        anchors.fill: parent
        rotation: root.sweep
        visible: root.running
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillGradient: ConicalGradient {
                    centerX: root._c; centerY: root._c; angle: 0
                    GradientStop { position: 0.00; color: U.withAlpha(root.accent, 0.0) }
                    GradientStop { position: 0.70; color: U.withAlpha(root.accent, 0.0) }
                    GradientStop { position: 0.93; color: U.withAlpha(root.accent, Theme.isDark ? 0.20 : 0.15) }
                    GradientStop { position: 1.00; color: U.withAlpha(root.accent, Theme.isDark ? 0.46 : 0.36) }
                }
                PathAngleArc { centerX: root._c; centerY: root._c; radiusX: root._r - 1; radiusY: root._r - 1; startAngle: 0; sweepAngle: 360 }
            }
        }
        // leading edge
        Rectangle {
            x: root._c
            y: root._c - 0.75
            width: root._r - 2
            height: 1.5
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(root.accent, 0.0) }
                GradientStop { position: 1.0; color: U.withAlpha(root.accent, 0.9) }
            }
        }
    }

    // ── contacts: one per ~12 real candidates ──
    Repeater {
        model: 12
        delegate: Item {
            id: blip
            required property int index
            // Golden-angle spiral: evenly spread, never clumped, stable per index.
            readonly property real ang: (index * 137.508 + 24) % 360
            readonly property real dist: root._r * (0.42 + 0.46 * (((index * 0.618034) % 1)))
            readonly property bool on: index < root.blips
            // how long ago the beam passed this contact (0 = right now)
            readonly property real since: ((root.sweep - ang) % 360 + 360) % 360
            readonly property real flare: on ? Math.max(0, 1 - since / 150) : 0
            width: 7; height: 7
            x: root._c + Math.cos(ang * Math.PI / 180) * dist - width / 2
            y: root._c + Math.sin(ang * Math.PI / 180) * dist - height / 2
            opacity: on ? 1 : 0
            scale: on ? 1 : 0.2
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }

            Rectangle {
                anchors.centerIn: parent
                width: 7; height: 7; radius: 3.5
                color: root.accent
                opacity: 0.38 + 0.62 * blip.flare
                antialiasing: true
            }
            // halo that blooms as the beam crosses
            Rectangle {
                anchors.centerIn: parent
                width: 7 + 12 * blip.flare; height: width; radius: width / 2
                color: U.withAlpha(root.accent, 0.22 * blip.flare)
                antialiasing: true
            }
            // one-off ping when the contact first appears
            Rectangle {
                id: ping
                anchors.centerIn: parent
                width: 7; height: 7; radius: width / 2
                color: "transparent"
                border.width: 1.2
                border.color: root.accent
                opacity: 0
                antialiasing: true
            }
            onOnChanged: if (on) pingAnim.restart()
            ParallelAnimation {
                id: pingAnim
                NumberAnimation { target: ping; property: "width"; from: 7; to: 30; duration: 700; easing.type: Easing.OutCubic }
                NumberAnimation { target: ping; property: "height"; from: 7; to: 30; duration: 700; easing.type: Easing.OutCubic }
                NumberAnimation { target: ping; property: "opacity"; from: 0.9; to: 0; duration: 700; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── progress ring (the real percentage) ──
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 3
            strokeColor: U.withAlpha(root.accent, 0.12)
            fillColor: "transparent"
            PathAngleArc { centerX: root._c; centerY: root._c; radiusX: root._r + 7; radiusY: root._r + 7; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: 3
            strokeColor: root.accent
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root._c; centerY: root._c
                radiusX: root._r + 7; radiusY: root._r + 7
                startAngle: -90
                sweepAngle: root.pct >= 0 ? Math.max(1, 3.6 * root._shownPct) : 0
            }
        }
    }
    // indeterminate: a short arc orbiting the ring until a number exists
    Shape {
        anchors.fill: parent
        visible: root.pct < 0 && root.running
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 3
            strokeColor: root.accent
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root._c; centerY: root._c; radiusX: root._r + 7; radiusY: root._r + 7; startAngle: -90; sweepAngle: 54 }
        }
        RotationAnimation on rotation {
            running: root._live && root.pct < 0
            from: 0; to: 360; duration: 1400
            loops: Animation.Infinite
        }
    }

    // ── viewfinder brackets: close in as the run nears done ──
    Repeater {
        model: [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        delegate: Item {
            required property var modelData
            readonly property real sx: modelData[0]
            readonly property real sy: modelData[1]
            readonly property real d: root._r * (0.50 - 0.16 * root._shownPct / 100)
            readonly property real arm: Math.round(root.size * 0.085)
            width: arm; height: arm
            x: root._c + sx * d - (sx < 0 ? 0 : width)
            y: root._c + sy * d - (sy < 0 ? 0 : height)
            Rectangle { width: parent.arm; height: 2; radius: 1; y: sy < 0 ? 0 : parent.arm - 2; color: root.accent; antialiasing: true }
            Rectangle { width: 2; height: parent.arm; radius: 1; x: sx < 0 ? 0 : parent.arm - 2; color: root.accent; antialiasing: true }
        }
    }

    // ── the mark ──
    Rectangle {
        width: root.size * 0.36; height: width; radius: width / 2
        anchors.centerIn: parent
        color: U.withAlpha(root.accent, Theme.isDark ? 0.16 : 0.10)
        SequentialAnimation on scale {
            running: root._live
            loops: Animation.Infinite
            NumberAnimation { from: 0.92; to: 1.08; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.08; to: 0.92; duration: 1300; easing.type: Easing.InOutSine }
        }
    }
    C.BrandMark {
        id: mark
        width: Math.round(root.size * 0.25)
        height: Math.round(width * 812 / 738)
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        rim: true
        SequentialAnimation on sheen {
            running: root._live
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 1500 }
        }
    }
}
