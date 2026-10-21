import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "../Utils.js" as U

// v9 segmented control with a sliding thumb.
//
// One shape for every "pick one of N" on the redesigned Niche Finder and
// AI Ideas pages (search mode, the three outlier cuts, format, result view,
// blueprint count). The thumb glides to the chosen cell instead of each cell
// repainting on its own, which is the single motion that makes a choice feel
// physical rather than toggled.
//
// `model` takes plain strings or { label, icon } objects. `currentIndex` of
// -1 means "nothing matches" (e.g. a custom value typed into the advanced
// panel): the thumb hides, no cell is lit.
//
// `equal: true` splits the full width evenly between the cells. In that mode
// the implicit width is a fixed floor rather than the sum of the cells, so a
// parent Layout can stretch the control without a width ⇄ implicitWidth
// binding loop.
Item {
    id: root

    property var model: []
    property int currentIndex: 0
    property bool equal: false
    property bool solid: true          // filled-accent thumb vs tinted thumb
    property bool iconOnly: false
    property bool mono: false
    property bool enabledCells: true
    property int cellHeight: 34
    property int pad: 3
    property int fontSize: Tokens.fontBody
    property int iconSize: 15
    property real radius: Tokens.radiusMd
    property color trackColor: Theme.input_bg
    property color trackBorder: Theme.border

    signal activated(int index)

    readonly property int _n: rep.count
    readonly property real _cellW: _n > 0 ? (width - pad * 2 - row.spacing * (_n - 1)) / _n : 0

    implicitWidth: equal ? 160 : row.implicitWidth + pad * 2
    implicitHeight: cellHeight + pad * 2

    // track
    Rectangle {
        anchors.fill: parent
        radius: root.radius + root.pad
        color: root.trackColor
        border.width: 1
        border.color: root.trackBorder
    }

    // thumb
    Rectangle {
        id: thumb
        readonly property Item tgt: (root.currentIndex >= 0 && rep.count > root.currentIndex)
                                    ? rep.liveItemAt(root.currentIndex) : null
        visible: tgt !== null
        x: tgt ? row.x + tgt.x : 0
        y: root.pad
        width: tgt ? tgt.width : 0
        height: root.cellHeight
        radius: root.radius
        color: root.solid ? Theme.primary : U.withAlpha(Theme.primary, Theme.isDark ? 0.18 : 0.12)
        border.width: root.solid ? 0 : 1
        border.color: U.withAlpha(Theme.primary, 0.45)
        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

        // specular top sheen on the solid thumb — reads as a lit key
        Rectangle {
            visible: root.solid
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    Row {
        id: row
        x: root.pad
        y: root.pad
        spacing: 2

        Repeater {
            id: rep
            // itemAt() is not a notifying lookup: a binding that ran before the
            // delegates existed got null and kept it (thumb missing on first show,
            // the active label invisible in light theme). `built` re-runs it.
            property int built: 0
            onItemAdded: built++
            onItemRemoved: built++
            function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
            model: root.model

            AbstractButton {
                id: cell
                readonly property bool isObj: typeof modelData === "object" && modelData !== null
                readonly property string lbl: isObj ? (modelData.label || "") : String(modelData)
                readonly property string ico: isObj ? (modelData.icon || "") : ""
                readonly property bool active: root.currentIndex === index

                height: root.cellHeight
                width: root.equal ? Math.max(0, root._cellW) : implicitWidth
                implicitWidth: cellRow.implicitWidth + (root.iconOnly ? Tokens.space3 * 2 : Tokens.space4 * 2)
                enabled: root.enabledCells
                hoverEnabled: true
                padding: 0
                onClicked: root.activated(index)
                HoverHandler { cursorShape: Qt.PointingHandCursor }

                AppTooltip { visible: root.iconOnly && cell.hovered && cell.lbl !== ""; text: cell.lbl }

                background: Rectangle {
                    radius: root.radius
                    color: !cell.active && cell.hovered ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.04)
                                                        : U.withAlpha(Theme.on_surface, 0)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }

                contentItem: Item {
                    implicitWidth: cellRow.implicitWidth
                    implicitHeight: cellRow.implicitHeight
                    Row {
                        id: cellRow
                        anchors.centerIn: parent
                        spacing: Tokens.space2
                        IconGlyph {
                            visible: cell.ico !== ""
                            name: cell.ico
                            size: root.iconSize
                            fill: cell.active
                            glyphColor: cell.active ? (root.solid ? Theme.on_primary : Theme.primary)
                                                    : (cell.hovered ? Theme.text_strong : Theme.on_surface_var)
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        AppText {
                            visible: !root.iconOnly && cell.lbl !== ""
                            text: cell.lbl
                            mono: root.mono
                            weight: cell.active ? Tokens.weightBold : Tokens.weightDemiBold
                            font.pixelSize: root.fontSize
                            color: cell.active ? (root.solid ? Theme.on_primary : Theme.primary)
                                               : (cell.hovered ? Theme.text_strong : Theme.on_surface_var)
                            anchors.verticalCenter: parent.verticalCenter
                            LayoutMirroring.enabled: false
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                    }
                }
            }
        }
    }

}
