import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// v1.1.3 — the "made with ♥" heart.
//
// Not an icon font glyph: a vector heart with a candy gradient and a glossy
// highlight, beating a real "lub-dub" (two pulses, then rest). Every beat
// throws a faint echo ring of itself outward. `racing: true` (the footer is
// hovered, or the pointer is on Donate) speeds the heart up and lets a few
// tiny hearts float off it, so the signature answers the pointer.
Item {
    id: root
    // Named so a headless bench can stop the beat and time idle CPU.
    objectName: "heartBeat"
    property int size: 14
    property bool racing: false
    property bool running: true
    property color hot: U.mix(Theme.primary, "#FF6FA5", 0.55)
    property color deep: Theme.primary

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    property real beat: 1.0

    readonly property string _path: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"

    // ── echo ring: a ghost of the heart that swells and fades on each beat ──
    Shape {
        id: echo
        width: 24; height: 24
        anchors.centerIn: parent
        preferredRendererType: Shape.CurveRenderer
        property real k: 0
        scale: (root.size / 24) * (1 + 0.9 * k)
        opacity: k > 0 ? (1 - k) * 0.45 : 0
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.hot
            strokeWidth: 1.6
            PathSvg { path: root._path }
        }
    }

    NumberAnimation {
        id: echoAnim
        target: echo; property: "k"
        from: 0; to: 1
        duration: 620
        easing.type: Easing.OutCubic
    }

    // ── the heart ──
    Shape {
        id: heart
        width: 24; height: 24
        anchors.centerIn: parent
        preferredRendererType: Shape.CurveRenderer
        scale: (root.size / 24) * root.beat
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 4; y1: 3
                x2: 20; y2: 21
                GradientStop { position: 0.0; color: Qt.lighter(root.hot, 1.18) }
                GradientStop { position: 0.55; color: root.hot }
                GradientStop { position: 1.0; color: root.deep }
            }
            PathSvg { path: root._path }
        }
        // glossy highlight on the upper-left lobe
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.55)
            strokeWidth: 1.7
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M5.2 8.2C5.3 6.6 6.4 5.5 7.9 5.4" }
        }
    }

    // ── lub-dub ──
    // Perf: this used to loop forever whenever the sidebar was visible, which
    // kept the whole window repainting ~80 times a second even with nothing
    // happening — the app could never go idle. It now beats once every few
    // seconds instead, so there is a real rest between beats; hovering still
    // races it continuously. A looping animation reads `loops` and
    // PauseAnimation.duration once per start, so the mode is applied before
    // restart() rather than mid-flight.
    property bool _burst: false
    readonly property bool _live: root.running && root.visible
    // exposed for the headless perf harness
    readonly property bool beating: beatAnim.running
    readonly property int beatLoops: beatAnim.loops

    function _retune() {
        if (!root._live) {
            beatAnim.stop()
            return
        }
        if (root.racing) {
            root._burst = false
            beatAnim.loops = Animation.Infinite
            beatAnim.restart()
        } else if (root._burst) {
            beatAnim.loops = 1
            beatAnim.restart()
        } else {
            beatAnim.stop()
            root.beat = 1.0
            echo.k = 0
        }
    }
    onRunningChanged: _retune()
    onVisibleChanged: _retune()
    onRacingChanged: _retune()
    Component.onCompleted: _retune()

    Timer {
        id: restTimer
        // one beat, then a long quiet rest: the signature stays alive without
        // pinning the render loop
        interval: 4500
        repeat: true
        triggeredOnStart: true
        running: root._live && !root.racing
        onTriggered: {
            root._burst = true
            root._retune()
        }
    }

    SequentialAnimation {
        id: beatAnim
        onFinished: root._burst = false
        ScriptAction { script: echoAnim.restart() }
        NumberAnimation { target: root; property: "beat"; to: 1.24; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "beat"; to: 0.96; duration: 120; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "beat"; to: 1.14; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "beat"; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
        PauseAnimation { duration: root.racing ? 220 : 0 }
    }

    // ── tiny hearts floating off it while racing ──
    Repeater {
        model: 3
        Shape {
            id: mote
            required property int index
            width: 24; height: 24
            preferredRendererType: Shape.CurveRenderer
            property real t: 0
            readonly property real drift: index === 0 ? -6 : index === 1 ? 5 : -1
            x: (root.width - width) / 2 + drift * t
            y: (root.height - height) / 2 - 20 * t
            scale: (root.size / 24) * (0.34 + 0.18 * t)
            opacity: t <= 0 ? 0 : t < 0.25 ? t * 3.2 : (1 - t) * 1.07
            visible: opacity > 0.01
            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: root.hot
                PathSvg { path: root._path }
            }
            SequentialAnimation {
                running: root.racing && root.visible
                loops: Animation.Infinite
                PauseAnimation { duration: 260 * mote.index }
                NumberAnimation { target: mote; property: "t"; from: 0; to: 1; duration: 900; easing.type: Easing.OutSine }
                PropertyAction { target: mote; property: "t"; value: 0 }
                PauseAnimation { duration: 780 - 260 * mote.index }
                onStopped: mote.t = 0
            }
        }
    }
}
