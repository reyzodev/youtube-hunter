import QtQuick
import NicheScope
import "../Utils.js" as U

// A rounded quota meter that EASES to its value — the QML re-implementation of
// the painted MeterBar widget. `value` is 0..1; the fill animates to new
// values and turns amber past 75%, staying brand-red otherwise, so peripheral
// vision alone reads "how full".
Item {
    id: root
    property real value: 0            // 0..1 target
    property int barHeight: 9
    property color fillColor: value >= 0.75 ? Theme.warn : Theme.primary

    implicitHeight: barHeight
    implicitWidth: 80

    property real anim: 0
    Behavior on anim { NumberAnimation { duration: 720; easing.type: Easing.OutCubic } }
    onValueChanged: anim = Math.max(0, Math.min(1, value))
    Component.onCompleted: anim = Math.max(0, Math.min(1, value))

    // track
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: U.withAlpha(Theme.outline, 0.18)
    }

    // fill (never narrower than its own cap so a 1% value isn't a lens sliver)
    Rectangle {
        height: parent.height
        width: Math.max(root.anim * parent.width, root.anim > 0 ? height : 0)
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: U.withAlpha(root.fillColor, 0.75) }
            GradientStop { position: 1.0; color: root.fillColor }
        }
        // specular top edge
        Rectangle {
            width: parent.width
            height: parent.height * 0.42
            radius: parent.radius
            color: U.withAlpha(Qt.rgba(1,1,1,1), 0.18)
        }
    }
}
