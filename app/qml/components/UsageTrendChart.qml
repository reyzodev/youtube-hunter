import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v10 "Equalizer" — the Usage page's consumption chart, redrawn.
//
// What changed vs. QuotaTrendChart (kept for reference, no longer used here):
//   • every day owns a faint full-height capsule "slot", so a zero day still
//     reads as a day instead of vanishing into a 2 px sliver
//   • the busiest day carries its number on top and a soft bloom behind it
//   • the running total is a smooth monotone curve (it can never overshoot,
//     a cumulative line only goes up) with a faint wash under it; the duplicate
//     right-hand axis is gone, the card header already prints the total
//   • hover focuses one day: a soft column highlight, every other bar dims,
//     a dot lands on the curve and the ChartTip shows both numbers
//   • 30-day mode thins the date labels, anchored on today, so they never
//     collide
//
// `model` is Usage.trend: [{label, total, totalText, frac, cumFrac, cumText,
// peak}] with every fraction pre-scaled by the VM. `axis` is 5 tick labels
// bottom→top; only 0 / mid / top are drawn.
Item {
    id: root
    property var model: []
    property var axis: []
    implicitHeight: 280

    // Time always runs left → right, also in the Persian (RTL) layout.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true

    property real grow: 0
    property int hover: -1
    readonly property bool _hv: hover >= 0 && hover < n

    // Same guard as before: the page re-polls the ledger and hands over a new
    // list each time; only a real data change replays the grow-in.
    property string _sig: ""
    function _signature(m) {
        if (!m || !m.length) return ""
        var parts = []
        for (var i = 0; i < m.length; i++)
            parts.push(m[i].label + ":" + m[i].total)
        return parts.join("|")
    }
    onModelChanged: _replay()
    // the first model arrives with the binding, which fires no change signal
    Component.onCompleted: _replay()
    function _replay() {
        var s = _signature(model)
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

    // ── geometry ──
    readonly property real gutterL: 40
    readonly property real gutterR: 6
    readonly property real plotTop: 30          // room for the peak label
    readonly property real footer: 30
    readonly property real plotH: Math.max(0, height - plotTop - footer)
    readonly property real plotW: Math.max(0, width - gutterL - gutterR)
    readonly property real baseY: plotTop + plotH
    readonly property int n: model ? model.length : 0
    readonly property real colW: plotW / Math.max(1, n)
    readonly property real barW: Math.max(4, Math.min(22, colW * 0.56))
    readonly property real barR: Math.min(barW / 2, 7)
    // one date label every `labelStep` days, counted back from today
    readonly property int labelStep: Math.max(1, Math.ceil(46 / Math.max(1, colW)))
    readonly property bool empty: {
        for (var i = 0; i < n; i++) if (model[i].total > 0) return false
        return true
    }

    function cx(i) { return gutterL + colW * (i + 0.5) }
    function cumY(i) { return plotTop + plotH * (1 - Math.max(0, Math.min(1, model[i].cumFrac)) * grow) }

    // Monotone cubic (Fritsch–Carlson) through the running-total points, as an
    // SVG path string for PathSvg. Monotone = no wobble above the real value.
    function _curve(close) {
        if (n < 2 || plotW <= 0 || plotH <= 0) return ""
        var xs = [], ys = [], i
        for (i = 0; i < n; i++) { xs.push(cx(i)); ys.push(cumY(i)) }
        var m = [], t = []
        for (i = 0; i < n - 1; i++) m.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]))
        t.push(m[0])
        for (i = 1; i < n - 1; i++) t.push(m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2)
        t.push(m[n - 2])
        for (i = 0; i < n - 1; i++) {
            if (m[i] === 0) { t[i] = 0; t[i + 1] = 0; continue }
            var a = t[i] / m[i], b = t[i + 1] / m[i], s = a * a + b * b
            if (s > 9) { var k = 3 / Math.sqrt(s); t[i] = k * a * m[i]; t[i + 1] = k * b * m[i] }
        }
        var f = function (v) { return v.toFixed(2) }
        var d = "M " + f(xs[0]) + " " + f(ys[0])
        for (i = 0; i < n - 1; i++) {
            var dx = (xs[i + 1] - xs[i]) / 3
            d += " C " + f(xs[i] + dx) + " " + f(ys[i] + t[i] * dx)
               + " " + f(xs[i + 1] - dx) + " " + f(ys[i + 1] - t[i + 1] * dx)
               + " " + f(xs[i + 1]) + " " + f(ys[i + 1])
        }
        if (close)
            d += " L " + f(xs[n - 1]) + " " + f(baseY) + " L " + f(xs[0]) + " " + f(baseY) + " Z"
        return d
    }

    // ── guides: baseline, mid, top (solid hairlines, not dashes) ──
    Repeater {
        model: [0, 2, 4]
        Item {
            required property int modelData
            width: root.width
            height: 1
            y: root.plotTop + root.plotH * (1 - modelData / 4.0)
            Rectangle {
                x: root.gutterL - 6
                width: root.plotW + 6
                height: 1
                color: modelData === 0 ? U.withAlpha(Theme.outline, 0.28)
                                       : U.withAlpha(Theme.outline, 0.12)
            }
            C.AppText {
                x: 0; width: root.gutterL - 12
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                mono: true; font.pixelSize: 11
                color: U.withAlpha(Theme.on_surface_var, 0.85)
                text: (root.axis && root.axis.length === 5) ? root.axis[modelData] : ""
            }
        }
    }

    // ── hover column highlight ──
    Rectangle {
        id: focusCol
        readonly property real w: Math.min(root.colW - 2, root.barW + 16)
        x: root._hv ? root.cx(root.hover) - w / 2 : 0
        y: root.plotTop - 8
        width: w
        height: root.plotH + 8 + 24
        radius: Math.min(w / 2, Tokens.radiusMd)
        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.06)
        opacity: root._hv ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        Behavior on x { enabled: focusCol.opacity > 0.01; NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    }

    // ── running-total wash (behind the bars, very faint) ──
    Shape {
        anchors.fill: parent
        visible: root.n > 1 && !root.empty
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: rendererType !== Shape.CurveRenderer
        layer.samples: 4
        ShapePath {
            strokeWidth: -1
            strokeColor: U.withAlpha(Theme.primary, 0)
            fillGradient: LinearGradient {
                x1: 0; y1: root.plotTop
                x2: 0; y2: root.baseY
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.11) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
            PathSvg { path: root._curve(true) }
        }
    }

    // ── one column per day: slot, bar, peak label, date ──
    Repeater {
        model: root.model
        Item {
            id: col
            required property var modelData
            required property int index
            x: root.gutterL + root.colW * index
            width: root.colW
            height: root.height
            readonly property bool hovered: root.hover === index
            readonly property bool isPeak: modelData.peak === true
            readonly property bool isToday: index === root.n - 1
            readonly property bool dimmed: root.hover >= 0 && !hovered

            // the empty slot — every day keeps its place in the rhythm
            Rectangle {
                width: root.barW
                height: root.plotH
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.plotTop
                radius: root.barR
                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.035)
            }

            // bloom behind the busiest day
            Rectangle {
                visible: col.isPeak && bar.height > 6
                anchors.centerIn: bar
                width: bar.width + 12
                height: bar.height + 12
                radius: root.barR + 6
                color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                opacity: root.grow
            }

            Rectangle {
                id: bar
                visible: col.modelData.total > 0
                width: root.barW
                anchors.horizontalCenter: parent.horizontalCenter
                height: Math.max(root.barW * 0.5, root.plotH * col.modelData.frac) * root.grow
                y: root.baseY - height
                radius: root.barR
                opacity: col.dimmed ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                gradient: Gradient {
                    GradientStop { position: 0.0
                        color: (col.isPeak || col.hovered) ? Theme.primary
                                                           : U.chartTint(1, Theme.primary, Theme.isDark) }
                    GradientStop { position: 1.0
                        color: U.withAlpha((col.isPeak || col.hovered) ? Theme.primary
                                                                       : U.chartTint(1, Theme.primary, Theme.isDark), 0.42) }
                }
                // glossy top edge
                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 2
                    width: Math.max(0, parent.width - 6)
                    height: Math.min(3, Math.max(0, parent.height - 4))
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.22 : 0.35)
                }
            }

            // a quiet dot marks a day with nothing spent
            Rectangle {
                visible: col.modelData.total <= 0
                width: 4; height: 4; radius: 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.baseY - 8
                color: U.withAlpha(Theme.outline, col.hovered ? 0.9 : 0.45)
            }

            // the peak's number rides on top of its bar
            C.AppText {
                visible: col.isPeak && !col.hovered
                anchors.horizontalCenter: parent.horizontalCenter
                y: bar.y - height - 6
                opacity: Math.max(0, (root.grow - 0.6) / 0.4)
                text: col.modelData.totalText
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: 11
                color: Theme.primary
            }

            // date
            C.AppText {
                visible: col.hovered || ((root.n - 1 - col.index) % root.labelStep === 0)
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.baseY + 10
                mono: true
                font.pixelSize: 11
                weight: (col.isToday || col.hovered) ? Tokens.weightBold : Tokens.weightRegular
                color: (col.isToday || col.hovered) ? Theme.text_strong : Theme.on_surface_var
                text: col.modelData.label
            }

            HoverHandler {
                onHoveredChanged: root.hover = hovered ? col.index
                                  : (root.hover === col.index ? -1 : root.hover)
            }
        }
    }

    // ── running-total curve ──
    Shape {
        anchors.fill: parent
        visible: root.n > 1 && !root.empty
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: rendererType !== Shape.CurveRenderer
        layer.samples: 4
        ShapePath {
            fillColor: U.withAlpha(Theme.primary, 0)
            strokeColor: U.chartTint(4, Theme.primary, Theme.isDark)
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root._curve(false) }
        }
    }

    // today's running total: a ringed dot with a slow breathing halo
    Item {
        visible: root.n > 1 && !root.empty && root.grow > 0.98
        width: 12; height: 12
        x: root.n > 0 ? root.cx(root.n - 1) - width / 2 : 0
        y: root.n > 0 ? root.cumY(root.n - 1) - height / 2 : 0
        Rectangle {
            anchors.centerIn: parent
            width: 12; height: 12; radius: 6
            color: U.withAlpha(Theme.primary, 0.30)
            SequentialAnimation on scale {
                running: root._motion && root.visible && Tokens.appActive
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 2.1; duration: 1600; easing.type: Easing.OutCubic }
                NumberAnimation { from: 2.1; to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 10; height: 10; radius: 5
            color: Theme.surface
            border.width: 2.5
            border.color: U.chartTint(4, Theme.primary, Theme.isDark)
        }
    }

    // hovered day's point on the curve
    Rectangle {
        visible: root._hv && root.n > 1 && !root.empty
        width: 9; height: 9; radius: 4.5
        x: root._hv ? root.cx(root.hover) - width / 2 : 0
        y: root._hv ? root.cumY(root.hover) - height / 2 : 0
        color: U.chartTint(4, Theme.primary, Theme.isDark)
        border.width: 2
        border.color: Theme.surface
    }

    // nothing spent in the whole window
    C.AppText {
        visible: root.empty && root.n > 0
        x: root.gutterL
        width: root.plotW
        y: root.plotTop + root.plotH / 2 - height / 2
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("Nothing spent in this window")
        font.pixelSize: Tokens.fontCaption
        color: Theme.outline
    }

    // hover tooltip — sits above the hovered column, flips inside the edges
    C.ChartTip {
        id: tip
        visible: root._hv
        label: root._hv ? root.model[root.hover].label : ""
        rows: root._hv ? [
            { name: I18n.tr("spend"), valueText: root.model[root.hover].totalText + " " + I18n.tr("units"), color: Theme.primary },
            { name: I18n.tr("Running total"), valueText: root.model[root.hover].cumText + " " + I18n.tr("units"), color: U.chartTint(4, Theme.primary, Theme.isDark) }
        ] : []
        x: {
            if (!root._hv) return 0
            var c = root.cx(root.hover)
            var right = c + root.colW / 2 + 8
            return (right + width <= root.width) ? right : Math.max(0, c - root.colW / 2 - 8 - width)
        }
        y: root.plotTop
    }
}
