import QtQuick
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// The floating tooltip card shared by the trend + stacked charts.
// v3.41.2: matches the app-wide "Ink" tooltip (AppTooltip): the same ink /
// graphite surface, soft layered shadow and 1px top light. A muted label
// line, a hairline, then one row per series (ringed dot · name · value).
// Positioned by the caller; hidden when `rows` is empty. API unchanged.
Rectangle {
    id: root
    // [{name, valueText, color}]
    property var rows: []
    property string label: ""

    visible: rows && rows.length > 0
    radius: 12
    color: Theme.tooltip_bg
    border.width: 1
    border.color: Theme.isDark ? U.withAlpha("#FFFFFF", 0.10) : U.withAlpha("#FFFFFF", 0.06)
    implicitWidth: Math.max(140, col.implicitWidth + 14 * 2)
    implicitHeight: col.implicitHeight + 10 * 2
    z: 50

    // soft layered shadow (behind the card)
    Repeater {
        model: 3
        Rectangle {
            required property int index
            z: -1
            x: -(index + 1) * 2
            y: -(index + 1) * 2 + 4 + index * 1.5
            width: root.width + (index + 1) * 4
            height: root.height + (index + 1) * 4
            radius: root.radius + (index + 1) * 2
            color: "#000000"
            opacity: (Theme.isDark ? 0.22 : 0.08) / (index + 1)
        }
    }
    // top light
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(0, parent.width - parent.radius * 2)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: U.withAlpha("#FFFFFF", 0) }
            GradientStop { position: 0.5; color: U.withAlpha("#FFFFFF", Theme.isDark ? 0.14 : 0.10) }
            GradientStop { position: 1.0; color: U.withAlpha("#FFFFFF", 0) }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 5

        C.AppText {
            text: root.label
            mono: true
            weight: Tokens.weightMedium
            font.pixelSize: 11
            color: U.withAlpha(Theme.tooltip_fg, 0.55)
            visible: root.label !== ""
        }
        Rectangle {
            visible: root.label !== ""
            Layout.fillWidth: true
            Layout.bottomMargin: 1
            height: 1
            color: U.withAlpha(Theme.tooltip_fg, 0.08)
        }
        Repeater {
            model: root.rows
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                // ringed series dot
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: U.withAlpha(modelData.color || Theme.primary, 0.28)
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6; height: 6; radius: 3
                        color: modelData.color || Theme.primary
                    }
                }
                C.AppText {
                    text: modelData.name || ""
                    font.pixelSize: Tokens.fontCaption
                    weight: Tokens.weightMedium
                    color: U.withAlpha(Theme.tooltip_fg, 0.72)
                }
                Item { Layout.fillWidth: true; Layout.minimumWidth: Tokens.space4 }
                C.AppText {
                    text: modelData.valueText || ""
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.tooltip_fg
                }
            }
        }
    }
}
