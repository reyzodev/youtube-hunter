import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "../Utils.js" as U

// Themed on/off switch matching the red brand accent.
Switch {
    id: root
    implicitHeight: 26

    // Pointing-hand cursor whenever the switch is live.
    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    indicator: Rectangle {
        implicitWidth: 44
        implicitHeight: 24
        radius: 12
        x: root.leftPadding
        y: (root.height - height) / 2
        color: root.checked ? Theme.primary : Theme.surface_high
        border.width: root.checked ? 0 : 1
        border.color: root.hovered ? U.withAlpha(Theme.primary, 0.45) : Theme.border
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        // v4: lit gradient track when on
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: root.checked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
            }
        }

        Rectangle {
            width: 18; height: 18; radius: 9
            x: root.checked ? parent.width - width - 3 : 3
            y: 3
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            // knob squishes while pressed — tactile
            scale: root.pressed ? 0.86 : 1.0
            Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
        }
    }

    contentItem: AppText {
        text: root.text
        color: Theme.on_surface
        verticalAlignment: Text.AlignVCenter
        leftPadding: root.indicator.width + Tokens.space3
    }
}
