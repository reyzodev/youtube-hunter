import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// A compact circular progress gauge for a download in flight.
//
// Small, sits over a thumbnail, and has the two states a transfer actually has:
//
//   * determinate — `value` 0..1, arc eased so each backend tick glides rather
//     than jumping; the percentage lives in the middle.
//   * spinning — for the ffmpeg mux at the end, which reports no total. A fixed
//     arc rotates instead of a bar sitting at 100% pretending to be done.
Item {
    id: root
    property real value: 0                 // 0..1
    property bool spinning: false
    property string label: ""
    property int ringSize: 54
    property real thickness: 5
    property color accent: Theme.primary

    implicitWidth: ringSize
    implicitHeight: ringSize

    readonly property real frac: Math.max(0, Math.min(1, animValue))
    property real animValue: 0
    Behavior on animValue {
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }
    onValueChanged: animValue = value
    Component.onCompleted: animValue = value

    readonly property real _radius: (ringSize - thickness) / 2 - 1

    // Scrim behind the ring so the percentage stays legible over a bright
    // thumbnail — a plain outline disappears against pale artwork.
    Rectangle {
        anchors.centerIn: parent
        width: root.ringSize; height: root.ringSize
        radius: width / 2
        color: U.withAlpha(Qt.rgba(0, 0, 0, 1), 0.42)
    }

    // track
    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeColor: U.withAlpha(Qt.rgba(1, 1, 1, 1), 0.28)
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root._radius; radiusY: root._radius
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // determinate arc
    Shape {
        anchors.fill: parent
        antialiasing: true
        visible: !root.spinning && root.frac > 0
        ShapePath {
            strokeColor: root.accent
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root._radius; radiusY: root._radius
                startAngle: -90
                sweepAngle: 360 * root.frac
            }
        }
    }

    // spinning arc (indeterminate). The whole Shape rotates, so the arc itself
    // stays a cheap static path.
    Shape {
        id: spinner
        anchors.fill: parent
        antialiasing: true
        visible: root.spinning
        transformOrigin: Item.Center
        ShapePath {
            strokeColor: root.accent
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root._radius; radiusY: root._radius
                startAngle: -90; sweepAngle: 110
            }
        }
        RotationAnimation on rotation {
            running: spinner.visible
            loops: Animation.Infinite
            from: 0; to: 360
            duration: 900
        }
    }

    AppText {
        anchors.centerIn: parent
        visible: root.label !== ""
        text: root.label
        mono: false
        weight: Tokens.weightExtraBold
        font.pixelSize: Math.max(10, root.ringSize * 0.26)
        color: "#ffffff"
    }
}
