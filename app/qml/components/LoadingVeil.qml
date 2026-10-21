import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.37 "Prism Shift" — the language-switch cover.
//
// A full-window OPAQUE cover (the reflow underneath — RTL flip, font swap,
// every label — must never be seen mid-flight), rebuilt around the brand mark:
//
//   * the mark re-assembles itself (neon outline draws on, crown drops, blades
//     slide in, play pops) and does a 3D mirror-flip — LTR <-> RTL, the very
//     thing that is happening to the layout behind it. The flip turns the
//     OTHER way when heading into Persian.
//   * a comet arc orbits the mark and a dotted ring counter-rotates. Both are
//     RotationAnimators, i.e. they run on the RENDER thread, so they keep
//     spinning smoothly even while the GUI thread is busy rebuilding the UI —
//     the old pulse/bar froze for that moment, which is what read as "slow".
//   * a liquid pill travels from the old language to the new one (it stretches
//     mid-travel and settles), and an aurora bloom sweeps in the same direction.
//   * when the switch has landed: a light ring bursts out of the mark and the
//     whole stage dissolves forward into the new UI.
//
// Usage (unchanged): `cover(applyFn)` — fades in, calls applyFn behind the
// cover, holds very briefly so the reflow settles, then reveals. Set
// `fromLang` / `toLang` ("en" | "fa") before calling it to show the pill; leave
// them empty for a generic "working" cover.
//
// Timing vs v3.36: in 150 ms (was 180), settle 120 ms (was 400), out 230 ms
// (was 240) — ~0.5 s of chrome instead of ~0.8 s, on top of a switch that now
// does one relayout pass instead of three (AppController.setLanguage).
Item {
    id: root
    anchors.fill: parent
    visible: _up
    enabled: _up
    opacity: 0
    z: 900

    property string label: I18n.tr("Applying …")
    property string fromLang: ""
    property string toLang: ""
    // match the window's rounded shell (set by Main.qml)
    property real radius: 0

    property var _work: null
    property bool _up: false

    // motion state, all 0..1
    property real intro: 0     // stage settles in
    property real swap: 0      // language pill travels from -> to
    property real flip: 0      // mark mirror-flip progress
    property real land: 0      // "landed" burst + forward dissolve

    readonly property bool _toRtl: toLang === "fa"
    readonly property bool _hasPill: fromLang !== "" && toLang !== "" && fromLang !== toLang
    readonly property real _dir: _toRtl ? -1 : 1

    function cover(work) {
        _work = work
        seq.stop()
        introAnim.stop()
        intro = 0; swap = 0; flip = 0; land = 0
        mark.assemble = 0
        mark.trace = 0
        mark.traceOpacity = 1
        mark.playPop = 0
        mark.sheen = -1
        mark.glowStrength = 1.0
        root.opacity = 0
        _up = true
        // direction-aware spin (re-armed per switch)
        orbitSpin.stop(); orbitSpin.from = 0; orbitSpin.to = 360 * _dir; orbitSpin.start()
        dotsSpin.stop(); dotsSpin.from = 0; dotsSpin.to = -360 * _dir; dotsSpin.start()
        seq.start()
        introAnim.start()
    }

    function _clamp(v) { return Math.max(0, Math.min(1, v)) }
    function _ease(t) { t = _clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2 }

    // Eats clicks while up, so a second toggle can't land mid-transition.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onClicked: (m) => m.accepted = true
    }

    // ── opaque base ──
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        color: Theme.background
    }

    // ── centre bloom + travelling aurora ──
    Shape {
        id: bloom
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.55 + 0.45 * root.intro
        readonly property real _cx: stage.x + stage.width / 2
        readonly property real _cy: stage.y + stage.height / 2
        // the aurora drifts across in the reading direction of the NEW language
        readonly property real _ax: _cx + root._dir * (root._ease(root.swap) - 0.5) * Math.min(root.width, 900) * 0.55
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bloom._cx; centerY: bloom._cy
                centerRadius: Math.min(root.width, root.height) * 0.46
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.22 : 0.14) }
                GradientStop { position: 0.5; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.05 : 0.035) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
            }
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.width, 0),
                       Qt.point(root.width, root.height), Qt.point(0, root.height),
                       Qt.point(0, 0)]
            }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bloom._ax; centerY: bloom._cy + 40
                centerRadius: Math.min(root.width, root.height) * 0.34
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: U.withAlpha(Qt.lighter(Theme.primary, 1.35), (Theme.isDark ? 0.13 : 0.08) * Math.sin(Math.PI * root._clamp(root.swap))) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
            }
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.width, 0),
                       Qt.point(root.width, root.height), Qt.point(0, root.height),
                       Qt.point(0, 0)]
            }
        }
    }

    // ── the stage: rings + mark ──
    Item {
        id: stage
        width: 236; height: 236
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root._hasPill ? -46 : -24
        scale: (0.9 + 0.1 * root._ease(root.intro)) * (1 + 0.1 * root.land)

        // static hairline ring
        Rectangle {
            anchors.centerIn: parent
            width: 212; height: 212; radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.09)
            antialiasing: true
            opacity: root.intro
        }

        // comet arc — render-thread spin (keeps moving while the UI rebuilds)
        // outer item spins (render thread); the inner shape is mirrored for a
        // counter-clockwise spin so the tail always trails the head
        Item {
            id: comet
            anchors.fill: parent
            opacity: root.intro * (1 - root.land)
          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.x: 118; xScale: root._dir }
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(Theme.primary, 0.10)
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 118; centerY: 118; radiusX: 106; radiusY: 106; startAngle: -150; sweepAngle: 70 }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(Theme.primary, 0.32)
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 118; centerY: 118; radiusX: 106; radiusY: 106; startAngle: -95; sweepAngle: 45 }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.primary
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 118; centerY: 118; radiusX: 106; radiusY: 106; startAngle: -55; sweepAngle: 34 }
            }
            // spark at the comet head
            ShapePath {
                fillColor: Qt.lighter(Theme.primary, 1.5)
                strokeColor: "transparent"
                strokeWidth: -1
                PathAngleArc { centerX: 118 + 106 * Math.cos(-21 * Math.PI / 180); centerY: 118 + 106 * Math.sin(-21 * Math.PI / 180); radiusX: 3.2; radiusY: 3.2; startAngle: 0; sweepAngle: 360 }
            }
        }
        }
        RotationAnimator {
            id: orbitSpin
            target: comet
            from: 0; to: 360
            duration: 950
            loops: Animation.Infinite
            running: false
        }

        // counter-rotating dotted inner ring
        Shape {
            id: dots
            anchors.fill: parent
            opacity: root.intro * (1 - root.land) * 0.9
            layer.enabled: root._up
            layer.samples: 4
            layer.smooth: true
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.24 : 0.28)
                strokeWidth: 1.6
                capStyle: ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                dashPattern: [0.1, 5.5]
                PathAngleArc { centerX: 118; centerY: 118; radiusX: 90; radiusY: 90; startAngle: 0; sweepAngle: 360 }
            }
        }
        RotationAnimator {
            id: dotsSpin
            target: dots
            from: 0; to: -360
            duration: 5200
            loops: Animation.Infinite
            running: false
        }

        // soft light behind the mark, breathes while the switch runs
        C.GlowBlob {
            anchors.centerIn: parent
            size: 120
            strength: (Theme.isDark ? 0.20 : 0.13) * (0.6 + 0.4 * mark.glowStrength) * (1 - root.land)
        }

        // "landed" light ring
        Rectangle {
            anchors.centerIn: parent
            width: 120; height: 120; radius: 60
            color: "transparent"
            border.width: 2
            border.color: Qt.lighter(Theme.primary, 1.4)
            antialiasing: true
            scale: 0.4 + root.land * 1.9
            opacity: root.land > 0 ? (1 - root.land) * 0.9 : 0
        }

        C.BrandMark {
            id: mark
            anchors.centerIn: parent
            width: 92; height: 102
            glow: root._up
            assemble: 0
            trace: 0
            traceOpacity: 0
            playPop: 0
            // 3D mirror-flip: the layout is mirroring behind the cover, so is the mark
            transform: Rotation {
                origin.x: mark.width / 2
                origin.y: mark.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: 360 * root._dir * root.flip
            }
        }
    }

    // ── language pill: old -> new ──
    Item {
        id: pill
        visible: root._hasPill
        width: 212; height: 38
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: stage.bottom
        anchors.topMargin: 2 + (1 - root.intro) * 10
        opacity: root.intro * (1 - root.land)
        // fixed order (English | فارسی) in both directions
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        readonly property real _chipW: (width - 8) / 2
        readonly property real _xEn: 4
        readonly property real _xFa: 4 + _chipW
        readonly property real _from: root.fromLang === "fa" ? _xFa : _xEn
        readonly property real _to: root.toLang === "fa" ? _xFa : _xEn
        readonly property real _t: root._ease(root.swap)
        // liquid stretch mid-travel
        readonly property real _stretch: 44 * Math.sin(Math.PI * root._clamp(root.swap))

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.05)
            border.width: 1
            border.color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.10 : 0.12)
            antialiasing: true
        }

        Rectangle {
            id: knob
            y: 4
            height: parent.height - 8
            width: pill._chipW + pill._stretch
            x: Math.max(2, Math.min(pill.width - width - 2,
                   pill._from + (pill._to - pill._from) * pill._t - pill._stretch / 2))
            radius: height / 2
            antialiasing: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: Qt.lighter(Theme.primary, 1.22) }
            }
        }

        Row {
            x: 4; y: 4
            height: parent.height - 8
            Repeater {
                model: [ { code: "en", name: "English" }, { code: "fa", name: "فارسی" } ]
                Item {
                    width: pill._chipW
                    height: parent.height
                    readonly property real _cx: x + 4 + width / 2
                    readonly property bool _lit: Math.abs((knob.x + knob.width / 2) - _cx) < width * 0.42
                    C.AppText {
                        anchors.centerIn: parent
                        text: modelData.name
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption + 1
                        color: parent._lit ? Theme.on_primary : Theme.on_surface_var
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: 120 } }
                    }
                }
            }
        }
    }

    // ── status line + render-thread shimmer ──
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root._hasPill ? pill.bottom : stage.bottom
        anchors.topMargin: 16 + (1 - root.intro) * 8
        spacing: 12
        opacity: root.intro * (1 - root.land)

        C.AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.pixelSize: Tokens.fontCaption
            color: Theme.on_surface_var
        }

        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            width: 150; height: 2; radius: 1
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.10)
            clip: true
            Rectangle {
                id: shimmer
                width: 56; height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0) }
                    GradientStop { position: 0.5; color: Theme.primary }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
                }
            }
            XAnimator {
                target: shimmer
                from: root._toRtl ? track.width : -shimmer.width
                to: root._toRtl ? -shimmer.width : track.width
                duration: 820
                easing.type: Easing.InOutCubic
                loops: Animation.Infinite
                running: root._up
            }
        }
    }

    // ── choreography of the mark + pill (GUI thread) ──
    ParallelAnimation {
        id: introAnim
        NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { target: mark; property: "trace"; from: 0; to: 1; duration: 360; easing.type: Easing.InOutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 50 }
            NumberAnimation { target: mark; property: "assemble"; from: 0; to: 1; duration: 420 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            NumberAnimation { target: root; property: "flip"; from: 0; to: 1; duration: 640; easing.type: Easing.InOutBack; easing.overshoot: 1.1 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 110 }
            NumberAnimation { target: root; property: "swap"; from: 0; to: 1; duration: 460; easing.type: Easing.Linear }
        }
        SequentialAnimation {
            PauseAnimation { duration: 260 }
            NumberAnimation { target: mark; property: "playPop"; from: 0; to: 1; duration: 320 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 360 }
            NumberAnimation { target: mark; property: "traceOpacity"; to: 0; duration: 260; easing.type: Easing.OutQuad }
        }
        SequentialAnimation {
            PauseAnimation { duration: 380 }
            NumberAnimation { target: mark; property: "sheen"; from: 0; to: 1; duration: 480; easing.type: Easing.InOutSine }
            PropertyAction { target: mark; property: "sheen"; value: -1 }
        }
        SequentialAnimation {
            loops: 2
            NumberAnimation { target: mark; property: "glowStrength"; to: 0.55; duration: 260; easing.type: Easing.InOutSine }
            NumberAnimation { target: mark; property: "glowStrength"; to: 1.0; duration: 260; easing.type: Easing.InOutSine }
        }
    }

    // ── the switch itself ──
    SequentialAnimation {
        id: seq
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
        // two frames, so the opaque cover is really on screen before the GUI
        // thread goes busy with the reflow
        PauseAnimation { duration: 32 }
        ScriptAction { script: if (root._work) root._work() }
        PauseAnimation { duration: 120 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "land"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                NumberAnimation { target: root; property: "opacity"; to: 0; duration: 230; easing.type: Easing.InOutCubic }
            }
        }
        ScriptAction {
            script: {
                root._work = null
                root._up = false
                orbitSpin.stop()
                dotsSpin.stop()
                introAnim.stop()
            }
        }
    }
}
