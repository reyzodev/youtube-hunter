import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "../Utils.js" as U

// Cards-per-row control for every gallery that renders ArchiveVideoCard.
//
// Four cells: Auto (fit as many as the width allows) and a pinned 2 / 3 / 4.
// The pinned modes are drawn as miniature column stacks rather than numbers,
// so the choice reads at a glance and survives translation. The value lives
// on App (persisted in config), which means both the Niche Finder and the
// Search Archive follow the same preference.
Item {
    id: root

    readonly property var options: [0, 2, 3, 4]
    readonly property int value: App.gridColumns !== undefined ? App.gridColumns : 0
    readonly property int cellW: 32
    readonly property int cellH: 28
    readonly property int pad: 3
    readonly property int selectedIndex: Math.max(0, options.indexOf(value))

    signal picked(int v)

    implicitWidth: options.length * cellW + pad * 2
    implicitHeight: cellH + pad * 2

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusMd
        color: Theme.input_bg
        border.width: 1
        border.color: Theme.border
    }

    Rectangle {
        id: thumb
        // itemAt() is not a notifying lookup: this binding can run before the
        // delegates exist, so `built` re-runs it once they do.
        readonly property Item tgt: (rep.built >= 0 && rep.count > root.selectedIndex)
                                    ? rep.itemAt(root.selectedIndex) : null
        visible: tgt !== null
        x: tgt ? tgt.x : root.pad
        y: root.pad
        width: root.cellW
        height: root.cellH
        radius: Tokens.radiusSm
        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.14)
        border.width: 1
        border.color: U.withAlpha(Theme.primary, 0.45)
        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        x: root.pad
        y: root.pad
        spacing: 0

        Repeater {
            id: rep
            property int built: 0
            onItemAdded: built++
            onItemRemoved: built++
            model: root.options

            AbstractButton {
                id: cell
                readonly property bool active: root.value === modelData
                readonly property int n: modelData
                width: root.cellW
                height: root.cellH
                hoverEnabled: true
                padding: 0
                onClicked: {
                    App.setGridColumns(modelData)
                    root.picked(modelData)
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }

                AppTooltip {
                    visible: cell.hovered
                    text: cell.n === 0
                          ? I18n.tr("Auto — fit cards to the window")
                          : I18n.tr("{n} cards per row").replace("{n}", cell.n)
                }

                background: Rectangle {
                    radius: Tokens.radiusSm
                    color: !cell.active && cell.hovered
                           ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.04)
                           : U.withAlpha(Theme.on_surface, 0)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }

                contentItem: Item {
                    // Auto: sparkle glyph. Pinned: a tiny stack of the columns
                    // the choice will produce — 4 bars still fit in 32 px.
                    IconGlyph {
                        visible: cell.n === 0
                        anchors.centerIn: parent
                        name: "auto_awesome"
                        size: 15
                        glyphColor: cell.active ? Theme.primary
                                   : cell.hovered ? Theme.text_strong : Theme.on_surface_var
                        Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    Row {
                        visible: cell.n > 0
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: cell.n
                            Rectangle {
                                width: 4
                                height: 13
                                radius: 1.4
                                color: cell.active ? Theme.primary
                                       : cell.hovered ? Theme.text_strong : Theme.on_surface_var
                                opacity: cell.active ? 1.0 : 0.75
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                        }
                    }
                }
            }
        }
    }
}
