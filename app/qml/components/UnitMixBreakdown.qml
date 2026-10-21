import QtQuick
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v10 "Spectrum" — where the units went, replacing the donut on Usage.
//
// A donut is the wrong instrument here: one call type (keyword search, 100
// units a page) routinely owns 95%+ of the spend, so the ring was one solid
// colour with a hairline gap and the legend underneath had to do all the work
// — twice (name · %, then units · price). This merges the two into one ranked
// list and puts a single "spectrum" bar on top:
//
//   • spectrum: one capsule per call type, sized by share, with a minimum
//     width so a 0.1% slice is still there to point at
//   • rows: ranked by units. Colour key · name · what it costs · units · %,
//     with a hairline share track under each
//   • hovering a row or a segment focuses that call type in both places
//
// `model` is Usage.mix: [{name, units, unitsText, pct, pctText, cost, tint}].
ColumnLayout {
    id: root
    property var model: []
    property int hot: -1
    spacing: Tokens.space4

    // ranked copy, biggest spender first (colour still follows `tint`, so a
    // kind keeps the same colour it has everywhere else)
    readonly property var rows: {
        var a = []
        var m = root.model || []
        for (var i = 0; i < m.length; i++) a.push(m[i])
        a.sort(function (x, y) { return y.units - x.units })
        return a
    }
    function tintOf(m) { return U.chartTint(m ? m.tint : -1, Theme.primary, Theme.isDark) }
    function setHot(i, on) { root.hot = on ? i : (root.hot === i ? -1 : root.hot) }

    property real grow: 0
    property string _sig: ""
    onRowsChanged: _replay()
    Component.onCompleted: _replay()
    function _replay() {
        var parts = []
        for (var i = 0; i < rows.length; i++) parts.push(rows[i].name + ":" + rows[i].units)
        var s = parts.join("|")
        if (s === _sig) { grow = 1; return }
        _sig = s
        grow = 0
        growAnim.restart()
    }
    NumberAnimation {
        id: growAnim
        target: root; property: "grow"; from: 0; to: 1
        duration: 900; easing.type: Easing.OutQuart
    }

    // ── spectrum ──
    Item {
        id: spec
        Layout.fillWidth: true
        implicitHeight: 12
        readonly property real gap: 4
        readonly property real minW: 10
        readonly property var widths: {
            var r = root.rows, n = r.length
            if (!n || width <= 0) return []
            var avail = Math.max(0, width - gap * (n - 1))
            var total = 0, i
            for (i = 0; i < n; i++) total += r[i].units
            var w = [], fixed = 0, flex = 0
            for (i = 0; i < n; i++) {
                var share = total > 0 ? r[i].units / total : 0
                if (share * avail < minW) { w.push(minW); fixed += minW }
                else { w.push(-1); flex += r[i].units }
            }
            var rest = Math.max(0, avail - fixed)
            for (i = 0; i < n; i++)
                if (w[i] < 0) w[i] = flex > 0 ? rest * r[i].units / flex : 0
            return w
        }
        Row {
            anchors.fill: parent
            spacing: spec.gap
            Repeater {
                model: root.rows
                Rectangle {
                    id: seg
                    required property var modelData
                    required property int index
                    width: (spec.widths[index] || 0) * root.grow
                    height: spec.height
                    radius: height / 2
                    color: root.tintOf(seg.modelData)
                    opacity: (root.hot < 0 || root.hot === seg.index) ? 1 : 0.28
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    // top sheen, same gloss as the trend bars
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(0, parent.width - 8)
                        height: 2
                        radius: 1
                        color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.20 : 0.32)
                    }
                    HoverHandler { onHoveredChanged: root.setHot(seg.index, hovered) }
                }
            }
        }
    }

    // ── ranked rows ──
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: root.rows
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: root.hot === index
                readonly property color tint: root.tintOf(modelData)
                Layout.fillWidth: true
                implicitHeight: rowLay.implicitHeight + Tokens.space2 * 2
                radius: Tokens.radiusMd
                color: on ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.04)
                          : U.withAlpha(Theme.on_surface, 0)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                opacity: (root.hot < 0 || on) ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                HoverHandler { onHoveredChanged: root.setHot(row.index, hovered) }

                RowLayout {
                    id: rowLay
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.space3
                    anchors.rightMargin: Tokens.space3
                    spacing: Tokens.space3

                    // colour key: a short vertical capsule, not a dot
                    Rectangle {
                        Layout.preferredWidth: 4
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 2
                        radius: 2
                        color: row.tint
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            C.AppText {
                                text: row.modelData.name
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.text_strong
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            C.AppText {
                                text: row.modelData.unitsText
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.text_strong
                            }
                            C.AppText {
                                text: row.modelData.pctText
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: row.on ? Theme.text_strong : Theme.on_surface_var
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 48
                            }
                        }
                        C.AppText {
                            text: row.modelData.cost
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        // share track
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space1
                            Layout.preferredHeight: 3
                            radius: 1.5
                            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.06)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(3, parent.width * Math.max(0, Math.min(1, row.modelData.pct / 100)) * root.grow)
                                radius: 1.5
                                color: row.tint
                            }
                        }
                    }
                }
            }
        }
    }
}
