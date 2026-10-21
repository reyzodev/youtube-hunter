import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// The call-mix donut: one arc segment per call kind with a small gap between
// them, the total in the centre, and a legend list (dot · name · %) below.
//
// `model` is a list of {name, pct, pctText, tint} — pcts already computed by the
// VM. Each slice is its own Shape in a Repeater (no per-frame object creation);
// start/sweep angles are derived from the running pct total, inset by padDeg so
// the gaps show.
//
// Colour comes from `tint` (an index into the brand ramp) OR, when a slice
// carries an explicit `color`, from that. The explicit form exists because some
// splits are not a magnitude ramp: an opportunity band (strong / fair / weak /
// crowded) already has a colour everywhere else it appears in the app, and a
// concept has to keep its colour or the reader re-learns the legend every time
// their eye moves down the page.
Item {
    id: root
    property var model: []
    property string centerText: "—"
    property string centerSub: ""
    implicitHeight: ringWrap.height + legendCol.implicitHeight + Tokens.space3

    property real grow: 0

    // v3.39.8: categorical hues (U.catHue) instead of five near-identical
    // shades of the accent, so every slice is told apart at a glance.
    function sliceColor(m) {
        if (m && m.color !== undefined && m.color !== "")
            return m.color
        var t = m ? m.tint : -1
        if (t === undefined || t < 0)
            return U.chartTint(-1, Theme.primary, Theme.isDark)
        return U.catHue(t, Theme.isDark)
    }

    // Same guard as QuotaTrendChart: the Usage page hands over a fresh
    // QVariantList on every ledger poll, and replaying the sweep each time read
    // as the donut endlessly redrawing itself. Only a real data change restarts
    // it; an identical model snaps to full.
    property string _sig: ""
    function _signature(m) {
        if (!m || !m.length) return ""
        var parts = []
        for (var i = 0; i < m.length; i++)
            parts.push(m[i].name + ":" + m[i].pct)
        return parts.join("|")
    }
    onModelChanged: {
        var s = _signature(model)
        if (s === _sig) { grow = 1; return }
        _sig = s
        grow = 0
        growAnim.restart()
    }
    NumberAnimation {
        id: growAnim
        target: root; property: "grow"; from: 0; to: 1
        duration: 760; easing.type: Easing.OutCubic
    }

    readonly property real padDeg: 3
    readonly property real _total: {
        var t = 0
        for (var i = 0; i < (model ? model.length : 0); i++) t += model[i].pct
        return t
    }
    // cumulative start angle (degrees, clockwise from top) before slice i
    function _startAngle(i) {
        var acc = 0
        for (var j = 0; j < i; j++) acc += model[j].pct
        return -90 + (_total > 0 ? 360 * (acc / _total) : 0)
    }
    function _sweep(i) {
        return _total > 0 ? 360 * (model[i].pct / _total) : 0
    }

    Item {
        id: ringWrap
        width: parent.width
        height: 196

        Item {
            id: ring
            anchors.centerIn: parent
            width: Math.min(ringWrap.width, ringWrap.height)
            height: width
            readonly property real thickness: width * 0.17
            readonly property real rad: width / 2 - 6

            Repeater {
                model: root.model
                Shape {
                    required property var modelData
                    required property int index
                    anchors.fill: parent
                    antialiasing: true
                    // perf: CurveRenderer antialiases on the GPU by itself; the 4-8x MSAA
                    // offscreen layer is only needed as a fallback on older Qt builds.
                    layer.enabled: rendererType !== Shape.CurveRenderer
                    layer.samples: 8
                    layer.smooth: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.sliceColor(modelData)
                        strokeWidth: ring.thickness
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathAngleArc {
                            centerX: ring.width / 2; centerY: ring.height / 2
                            radiusX: ring.rad - ring.thickness / 2
                            radiusY: radiusX
                            startAngle: root._startAngle(index) + root.padDeg / 2
                            sweepAngle: Math.max(0, root._sweep(index) * root.grow - root.padDeg)
                        }
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 0
            C.AppText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.centerText
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontTitle
                color: Theme.text_strong
            }
            C.AppText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.centerSub
                font.pixelSize: 11
                color: Theme.on_surface_var
            }
        }
    }

    // legend
    //
    // Always present, and it carries the NUMBER as well as the swatch. Two things
    // ride on that: identity never rests on colour alone (a reader who cannot
    // separate two hues still has the label), and a value printed in text is what
    // makes a slice colour below the 3:1 contrast floor legal.
    ColumnLayout {
        id: legendCol
        anchors.top: ringWrap.bottom
        anchors.topMargin: Tokens.space3
        width: parent.width
        spacing: Tokens.space2
        Repeater {
            model: root.model
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.space2
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.sliceColor(modelData)
                    Layout.alignment: Qt.AlignVCenter
                }
                C.AppText {
                    text: modelData.name
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                C.AppText {
                    text: modelData.pctText
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                }
            }
        }
    }
}
