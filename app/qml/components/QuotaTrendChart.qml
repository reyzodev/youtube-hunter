import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// The Usage page's main consumption chart: gradient bars for each day's spend
// plus a cumulative polyline on a right-hand axis. Left + right tick labels,
// dashed horizontal guides, and per-day hover that lifts the bar and shows a
// ChartTip. Replaces the old painted-style TrendChart.
//
// `model` is Usage.trend: [{label, total, totalText, frac, cumFrac, cumText,
// peak}] — all fractions pre-scaled by the VM, so this never re-derives an
// axis. `axis` / `cumAxis` are 5 pre-formatted tick labels bottom→top.
Item {
    id: root
    property var model: []
    property var axis: []
    property var cumAxis: []
    implicitHeight: 300

    property real grow: 0
    property int hover: -1

    // The Usage page re-reads the ledger on a timer, so `model` is reassigned a
    // brand-new QVariantList every poll even when nothing changed. Replaying the
    // grow-in on every one of those made the whole chart look like it was
    // perpetually loading in from the baseline. So the animation only replays
    // when the DATA actually differs: a cheap signature of the series is kept
    // and compared, and an unchanged model just snaps grow to 1.
    property string _sig: ""
    function _signature(m) {
        if (!m || !m.length) return ""
        var parts = []
        for (var i = 0; i < m.length; i++)
            parts.push(m[i].label + ":" + m[i].total)
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

    readonly property real gutterL: 44
    readonly property real gutterR: 40
    readonly property real footer: 26
    readonly property real plotTop: 10
    readonly property real plotH: height - plotTop - footer
    readonly property real plotW: width - gutterL - gutterR
    readonly property int n: model ? model.length : 0

    // dashed horizontal guides + left/right axis labels
    Repeater {
        model: 5
        Item {
            width: root.width
            readonly property real frac: index / 4.0
            y: root.plotTop + root.plotH * (1 - frac)
            // dashed line
            Row {
                x: root.gutterL
                spacing: 6
                Repeater {
                    // Clamped: before the first layout pass `width` is 0, so
                    // plotW is negative (0 - gutters) and Repeater warns about a
                    // negative model size.
                    model: Math.max(0, Math.ceil(root.plotW / 12))
                    Rectangle { width: 6; height: 1; color: U.withAlpha(Theme.border, 0.7) }
                }
            }
            C.AppText {
                x: 0; width: root.gutterL - 6
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                mono: true; font.pixelSize: 11
                color: Theme.on_surface_var
                text: (root.axis && root.axis.length === 5) ? root.axis[index] : ""
            }
            C.AppText {
                x: root.width - root.gutterR + 4; width: root.gutterR - 4
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignLeft
                mono: true; font.pixelSize: 11
                color: U.withAlpha(Theme.on_surface_var, 0.8)
                text: (root.cumAxis && root.cumAxis.length === 5) ? root.cumAxis[index] : ""
            }
        }
    }

    // columns
    Row {
        id: cols
        x: root.gutterL
        width: root.plotW
        height: root.height
        Repeater {
            model: root.model
            Item {
                id: colItem
                width: cols.width / Math.max(1, root.n)
                height: cols.height
                readonly property bool hovered: root.hover === index
                readonly property bool isPeak: modelData.peak === true

                Rectangle {
                    id: bar
                    width: Math.min(26, colItem.width * 0.5)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: Math.max(2, root.plotH * modelData.frac * root.grow)
                    y: root.plotTop + root.plotH - height - (colItem.hovered ? 4 : 0)
                    radius: 6
                    Behavior on y { NumberAnimation { duration: Tokens.durFast } }
                    gradient: Gradient {
                        GradientStop { position: 0.0
                            color: (colItem.hovered || colItem.isPeak)
                                   ? Theme.primary : U.chartTint(0, Theme.primary, Theme.isDark) }
                        GradientStop { position: 1.0
                            color: (colItem.hovered || colItem.isPeak)
                                   ? U.withAlpha(Theme.primary, 0.55)
                                   : U.chartTint(2, Theme.primary, Theme.isDark) }
                    }
                }

                // day label
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.plotTop + root.plotH + 8
                    mono: true; font.pixelSize: 11
                    color: colItem.hovered ? Theme.text_strong : Theme.on_surface_var
                    text: modelData.label
                }

                HoverHandler {
                    onHoveredChanged: root.hover = hovered ? index
                                      : (root.hover === index ? -1 : root.hover)
                }
            }
        }
    }

    // cumulative polyline over the bars, on the right axis (0..1 already)
    Shape {
        anchors.fill: parent
        antialiasing: true
        // perf: CurveRenderer antialiases on the GPU by itself; the 4-8x MSAA
        // offscreen layer is only needed as a fallback on older Qt builds.
        layer.enabled: rendererType !== Shape.CurveRenderer
        layer.samples: 4
        preferredRendererType: Shape.CurveRenderer
        visible: root.n > 1
        ShapePath {
            fillColor: "transparent"
            strokeColor: U.chartTint(4, Theme.primary, Theme.isDark)
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
                path: {
                    var pts = []
                    var colW = root.plotW / Math.max(1, root.n)
                    for (var i = 0; i < root.n; i++) {
                        var cx = root.gutterL + colW * (i + 0.5)
                        var cy = root.plotTop + root.plotH * (1 - root.model[i].cumFrac * root.grow)
                        pts.push(Qt.point(cx, cy))
                    }
                    return pts
                }
            }
        }
    }

    // hover tooltip
    C.ChartTip {
        id: tip
        visible: root.hover >= 0 && root.hover < root.n
        label: (root.hover >= 0 && root.hover < root.n) ? root.model[root.hover].label : ""
        rows: (root.hover >= 0 && root.hover < root.n) ? [
            { name: I18n.tr("spend"), valueText: root.model[root.hover].totalText + " " + I18n.tr("units"), color: Theme.primary },
            { name: I18n.tr("cumulative"), valueText: root.model[root.hover].cumText + " " + I18n.tr("units"), color: U.chartTint(4, Theme.primary, Theme.isDark) }
        ] : []
        x: {
            if (root.hover < 0) return 0
            var colW = root.plotW / Math.max(1, root.n)
            var cx = root.gutterL + colW * (root.hover + 0.5)
            return Math.max(4, Math.min(root.width - width - 4, cx - width / 2))
        }
        y: root.plotTop
    }
}
