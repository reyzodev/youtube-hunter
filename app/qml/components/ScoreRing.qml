import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// v11 — an animated score dial for a blueprint / a verdict.
//
// A thin track, a thick accent arc that sweeps in from 12 o'clock to `value`
// (0..100) every time `replay()` is called (the hosts call it when the shown
// item changes, so swapping ideas re-draws the dial instead of the number just
// rewriting itself), a soft halo the same colour as the arc, and the number in
// the middle counting up alongside the sweep.
//
// Pure Shape paths + one counting property: no shaders, no offscreen layers,
// so it costs nothing to keep a few of these on screen.
Item {
    id: root
    property real value: 0                 // 0..100
    property color accent: Theme.primary
    property int ringSize: 96
    property real thickness: 8
    property string caption: "/100"       // under the number; "" hides it
    property string suffix: ""            // e.g. "%"
    property bool showHalo: true
    property int numberSize: Math.round(ringSize * 0.30)

    implicitWidth: ringSize
    implicitHeight: ringSize

    property real _shown: 0                // animated 0..value
    readonly property real _frac: Math.max(0, Math.min(1, _shown / 100))
    readonly property real _r: (ringSize - thickness) / 2 - 1

    function replay() {
        sweep.stop()
        root._shown = 0
        sweep.to = Math.max(0, Math.min(100, root.value))
        sweep.start()
    }
    onValueChanged: replay()
    Component.onCompleted: replay()

    NumberAnimation {
        id: sweep
        target: root
        property: "_shown"
        from: 0
        duration: 900
        easing.type: Easing.OutCubic
    }

    // halo — two nested discs at a whisper of the accent
    Rectangle {
        visible: root.showHalo
        anchors.centerIn: parent
        width: root.ringSize + 18; height: width; radius: width / 2
        color: U.withAlpha(root.accent, 0.06 * (0.4 + root._frac * 0.6))
    }
    Rectangle {
        visible: root.showHalo
        anchors.centerIn: parent
        width: root.ringSize - root.thickness * 2 - 4; height: width; radius: width / 2
        color: U.withAlpha(root.accent, 0.08)
    }

    // track
    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: U.withAlpha(root.accent, 0.16)
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root._r; radiusY: root._r
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // value arc
    Shape {
        anchors.fill: parent
        antialiasing: true
        visible: root._frac > 0.002
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.accent
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root._r; radiusY: root._r
                startAngle: -90
                sweepAngle: 360 * root._frac
            }
        }
    }

    // the leading-edge spark: a small bright dot riding the end of the arc
    Rectangle {
        visible: root._frac > 0.02
        width: root.thickness + 4; height: width; radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.92)
        border.width: 2
        border.color: root.accent
        readonly property real _a: (-90 + 360 * root._frac) * Math.PI / 180
        x: root.width / 2 + Math.cos(_a) * root._r - width / 2
        y: root.height / 2 + Math.sin(_a) * root._r - height / 2
    }

    Column {
        anchors.centerIn: parent
        spacing: -2
        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root._shown) + root.suffix
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: root.numberSize
            color: Theme.text_strong
            LayoutMirroring.enabled: false
        }
        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.caption !== ""
            text: root.caption
            mono: true
            weight: Tokens.weightDemiBold
            font.pixelSize: 11
            color: Theme.outline
            LayoutMirroring.enabled: false
        }
    }
}
