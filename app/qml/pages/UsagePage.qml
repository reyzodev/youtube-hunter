import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Usage & Quota — what this install has actually spent, and when it runs out.
// Every figure is read from the local ledger via UsageVM; the page re-reads it
// on a timer while visible so the numbers move as quota drains.
//
// v9 "Fuel dial": the page opens on one big reading — today's units as a
// scoreboard number beside a live dial (ticks, glowing arc, a breathing
// needle cap) whose colour moves accent → amber → red as the day's quota
// drains. Every number below it is the same UsageVM binding as before; only
// the presentation changed.
Item {
    id: page

    property color _tint: Theme.primary
    function tintColor(key) {
        return key === "warn" ? Theme.warn
             : key === "secondary_container" ? Theme.secondary_container
             : Theme.primary
    }

    // ── v9 presentation helpers (derived from the VM, no new logic) ──
    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    readonly property real _frac: Math.max(0, Math.min(1, Usage.unitsFrac || 0))
    readonly property int _pct: Math.round(_frac * 100)
    readonly property bool _hasKey: Usage.hasKeys
    // accent while there's plenty, amber once it runs warm, red near empty
    readonly property color _level: _frac >= 0.9 ? Theme.error
                                  : _frac >= 0.7 ? Theme.warn
                                  : Theme.primary
    readonly property string _levelLabel: !_hasKey ? I18n.tr("No key yet")
                                        : _frac >= 0.9 ? I18n.tr("Almost out")
                                        : _frac >= 0.7 ? I18n.tr("Running warm")
                                        : I18n.tr("Plenty left")
    readonly property color _levelChip: !_hasKey ? Theme.on_surface_var
                                      : _frac >= 0.9 ? Theme.error
                                      : _frac >= 0.7 ? Theme.warn
                                      : Theme.secondary_container
    readonly property int _healthyKeys: {
        var ks = Usage.keys || []
        var n = 0
        for (var i = 0; i < ks.length; i++)
            if (ks[i].tint === "secondary_container") n++
        return n
    }

    // refresh on show + poll while visible. The VM stays silent when nothing
    // it renders has moved, so this tick is cheap; the interval is still 30s
    // rather than a few seconds because quota only changes when a call is made.
    // Perf: no Component.onCompleted refresh — the VM already reads the ledger
    // in its constructor, and every page instantiates at startup, so that call
    // was a second full ledger read during boot for a page nobody had opened.
    onVisibleChanged: if (visible) { Usage.refresh(); pollTimer.restart() }
    Timer {
        id: pollTimer
        interval: 30000
        repeat: true
        running: page.visible
        onTriggered: Usage.refresh()
    }

    // ═══════════════════════ inline building blocks ═══════════════════════

    // "rgba(r,g,b,a)" for Canvas — a QML colour handed to fillStyle loses its
    // alpha (it stringifies as #AARRGGBB, which CSS reads differently).
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
               + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a).toFixed(3) + ")"
    }

    // Small pill: optional dot or glyph + label, tinted.
    component Pill: Rectangle {
        id: pill
        property string text_: ""
        property string icon: ""
        property bool dot: false
        property bool pulse: false
        property bool mono: false
        property color tint: Theme.on_surface_var
        readonly property bool _neutral: String(tint) === String(Theme.on_surface_var)
        radius: Tokens.radiusPill
        color: _neutral ? Theme.surface_high : U.withAlpha(tint, 0.12)
        border.width: 1
        border.color: _neutral ? Theme.border : U.withAlpha(tint, 0.32)
        implicitWidth: pillRow.implicitWidth + Tokens.space3 * 2
        implicitHeight: 30
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Tokens.space2
            Rectangle {
                visible: pill.dot
                width: 7; height: 7; radius: 4
                color: pill.tint
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: pill.pulse && page._motion && page.visible && Tokens.appActive
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 1100; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutQuad }
                }
            }
            C.IconGlyph {
                visible: pill.icon !== ""
                name: pill.icon; size: 14
                glyphColor: pill.tint
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: pill.text_
                mono: pill.mono
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                color: pill._neutral ? Theme.on_surface : pill.tint
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // v10: small uppercase card label (Latin tracking only; Persian has no case)
    component Eyebrow: C.AppText {
        mono: true
        weight: Tokens.weightDemiBold
        font.pixelSize: 11
        font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
        color: Theme.on_surface_var
    }

    // v10: a label · value capsule for the consumption card's facts
    component StatChip: Rectangle {
        id: sc
        property string label: ""
        property string value: ""
        property string extra: ""
        property bool accent: false
        radius: Tokens.radiusPill
        color: accent ? U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.09) : Theme.surface_high
        border.width: 1
        border.color: accent ? U.withAlpha(Theme.primary, 0.30) : Theme.border
        implicitWidth: scRow.implicitWidth + Tokens.space3 * 2
        implicitHeight: 30
        Row {
            id: scRow
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                visible: sc.accent
                width: 6; height: 6; radius: 3
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: sc.label
                font.pixelSize: Tokens.fontCaption
                weight: sc.value === "" ? Tokens.weightDemiBold : Tokens.weightRegular
                color: sc.value === "" ? Theme.on_surface : Theme.on_surface_var
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                visible: sc.value !== ""
                text: sc.value
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontCaption
                color: sc.accent ? Theme.primary : Theme.text_strong
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                visible: sc.extra !== ""
                text: "· " + sc.extra
                mono: true
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // The signature dial. Drawn on a Canvas so the arc, the ticks and the
    // needle cap all share one angle convention (0° = 3 o'clock, clockwise);
    // it sweeps 270° from lower-left over the top to lower-right. Hover swaps
    // the centre from the percentage to the raw "used / capacity" reading.
    component FuelDial: Item {
        id: dial
        property real value: 0
        property color tint: Theme.primary
        property string usedText: "—"
        property string capText: ""
        implicitWidth: 236
        implicitHeight: 236

        property real anim: 0
        NumberAnimation {
            id: dialAnim
            target: dial; property: "anim"
            duration: 1100; easing.type: Easing.OutCubic
        }
        function sweepTo(fromZero) {
            var v = Math.max(0, Math.min(1, dial.value))
            dialAnim.stop()
            if (!page._motion) { dial.anim = v; return }
            dialAnim.from = fromZero ? 0 : dial.anim
            dialAnim.to = v
            dialAnim.start()
        }
        onValueChanged: sweepTo(false)
        Component.onCompleted: sweepTo(true)
        // replay the sweep from empty each time the page comes up
        Connections {
            target: page
            function onVisibleChanged() { if (page.visible) dial.sweepTo(true) }
        }

        readonly property real _a0: Math.PI * 0.75          // 135°
        readonly property real _span: Math.PI * 1.5         // 270°
        readonly property real _thick: 14
        readonly property real _r: Math.min(width, height) / 2 - 26
        readonly property real _capAngle: _a0 + _span * anim

        HoverHandler { id: dialHover }

        // soft pool of the level colour behind the dial
        Rectangle {
            anchors.centerIn: parent
            width: dial._r * 2.1; height: width; radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(dial.tint, Theme.isDark ? 0.14 : 0.08) }
                GradientStop { position: 1.0; color: U.withAlpha(dial.tint, 0.0) }
            }
        }

        // Perf rewrite of the dial. It used to be ONE Canvas repainted on every
        // frame of the 1.1 s sweep, each paint running a 22 px shadowBlur on the
        // CPU (the single most expensive Canvas op) — that is what made opening
        // Usage & Quota hitch and spike the CPU. Now:
        //   • track + unlit ticks: a Canvas painted once (resize / theme only)
        //   • lit ticks: a Canvas repainted only when another tick lights (≤41x)
        //   • the glowing arc: a GPU Shape; the glow is two wide translucent
        //     strokes under the main one instead of a blur
        // Same geometry, angles, colours and timing as before.
        Canvas {
            id: dialBase
            anchors.fill: parent
            antialiasing: true
            property color track: Theme.outline
            onTrackChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2
                var r = dial._r, a0 = dial._a0, span = dial._span
                ctx.lineCap = "round"
                ctx.lineWidth = dial._thick
                ctx.strokeStyle = page.css(track, 0.20)
                ctx.beginPath()
                ctx.arc(cx, cy, r, a0, a0 + span, false)
                ctx.stroke()
                var ticks = 40
                for (var i = 0; i <= ticks; i++) {
                    var ang = a0 + span * (i / ticks)
                    var major = (i % 5 === 0)
                    var r1 = r + dial._thick / 2 + 5
                    var r2 = r1 + (major ? 9 : 5)
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(ang) * r1, cy + Math.sin(ang) * r1)
                    ctx.lineTo(cx + Math.cos(ang) * r2, cy + Math.sin(ang) * r2)
                    ctx.lineWidth = major ? 2 : 1.2
                    ctx.strokeStyle = page.css(track, major ? 0.55 : 0.30)
                    ctx.stroke()
                }
            }
        }

        Canvas {
            id: dialTicks
            anchors.fill: parent
            antialiasing: true
            property color tint: dial.tint
            // how many ticks are lit — the only thing this layer depends on
            readonly property int lit: dial.anim > 0 ? Math.floor(dial.anim * 40 + 0.0001) + 1 : 0
            onLitChanged: requestPaint()
            onTintChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                if (lit <= 0) return
                var cx = width / 2, cy = height / 2
                var r = dial._r, a0 = dial._a0, span = dial._span
                ctx.lineCap = "round"
                for (var i = 0; i < lit && i <= 40; i++) {
                    var ang = a0 + span * (i / 40)
                    var major = (i % 5 === 0)
                    var r1 = r + dial._thick / 2 + 5
                    var r2 = r1 + (major ? 9 : 5)
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(ang) * r1, cy + Math.sin(ang) * r1)
                    ctx.lineTo(cx + Math.cos(ang) * r2, cy + Math.sin(ang) * r2)
                    ctx.lineWidth = major ? 2 : 1.2
                    ctx.strokeStyle = page.css(tint, major ? 0.95 : 0.70)
                    ctx.stroke()
                }
            }
        }

        Shape {
            id: dialArc
            anchors.fill: parent
            visible: dial.anim > 0.001
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: rendererType !== Shape.CurveRenderer
            layer.samples: 4
            readonly property real _deg0: 135
            readonly property real _sweep: 270 * dial.anim
            // outer bloom
            ShapePath {
                strokeColor: U.withAlpha(dial.tint, 0.10)
                strokeWidth: dial._thick + 14
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: dial.width / 2; centerY: dial.height / 2
                    radiusX: dial._r; radiusY: dial._r
                    startAngle: dialArc._deg0; sweepAngle: dialArc._sweep
                }
            }
            // inner bloom
            ShapePath {
                strokeColor: U.withAlpha(dial.tint, 0.20)
                strokeWidth: dial._thick + 6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: dial.width / 2; centerY: dial.height / 2
                    radiusX: dial._r; radiusY: dial._r
                    startAngle: dialArc._deg0; sweepAngle: dialArc._sweep
                }
            }
            // the arc
            ShapePath {
                strokeColor: dial.tint
                strokeWidth: dial._thick
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: dial.width / 2; centerY: dial.height / 2
                    radiusX: dial._r; radiusY: dial._r
                    startAngle: dialArc._deg0; sweepAngle: dialArc._sweep
                }
            }
            // lighter inner sheen along the arc
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.22)
                strokeWidth: dial._thick * 0.34
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: dial.width / 2; centerY: dial.height / 2
                    radiusX: dial._r - dial._thick * 0.18; radiusY: dial._r - dial._thick * 0.18
                    startAngle: dialArc._deg0; sweepAngle: dialArc._sweep
                }
            }
        }

        // needle cap — rides the end of the arc and breathes at rest
        Item {
            visible: dial.anim > 0.002
            width: 22; height: 22
            x: dial.width / 2 + Math.cos(dial._capAngle) * dial._r - width / 2
            y: dial.height / 2 + Math.sin(dial._capAngle) * dial._r - height / 2
            Rectangle {
                id: capHalo
                anchors.centerIn: parent
                width: 22; height: 22; radius: 11
                color: U.withAlpha(dial.tint, 0.35)
                SequentialAnimation on scale {
                    running: page._motion && page.visible && Tokens.appActive
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.8; to: 1.45; duration: 1400; easing.type: Easing.OutCubic }
                    NumberAnimation { from: 1.45; to: 0.8; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 12; height: 12; radius: 6
                color: Theme.text_strong
                border.width: 3
                border.color: dial.tint
            }
        }

        // centre reading
        Item {
            anchors.centerIn: parent
            width: dial._r * 1.5
            height: 80
            Column {
                anchors.centerIn: parent
                spacing: 0
                opacity: dialHover.hovered ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(dial.anim * 100) + "%"
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: 40
                    color: Theme.text_strong
                    LayoutMirroring.enabled: false
                }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("spent today")
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: 2
                opacity: dialHover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dial.usedText
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: 30
                    color: dial.tint
                }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("of {c} units").replace("{c}", dial.capText)
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                }
            }
        }
    }

    // A KPI card: tinted icon tile + caption, a big value, an optional visual
    // (dropped in as children) and the VM's explanatory line.
    component KpiCard: C.GlassPanel {
        id: kpi
        property string caption: ""
        property string icon: ""
        property color tint: Theme.primary
        property string value: "—"
        property string sub: ""
        property bool clickable: false
        signal clicked()
        property alias visual: visualSlot.data

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        radius: Tokens.radiusXl
        hoverGlow: true
        elevation: kpi.hovered ? 1.6 : 1.0
        Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
        implicitHeight: kpiCol.implicitHeight + Tokens.space5 * 2

        MouseArea {
            anchors.fill: parent
            enabled: kpi.clickable
            cursorShape: kpi.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: kpi.clicked()
        }

        ColumnLayout {
            id: kpiCol
            anchors.fill: parent
            anchors.margins: Tokens.space5
            spacing: Tokens.space3

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                C.IconTile {
                    iconName: kpi.icon
                    size: 36; glyphSize: 18
                    tint: kpi.tint
                    iconFill: false
                    lit: kpi.hovered
                }
                C.AppText {
                    text: kpi.caption
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                    color: Theme.on_surface_var
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                C.IconGlyph {
                    visible: kpi.clickable
                    name: I18n.rtl ? "arrow_back" : "arrow_forward"; size: 15
                    glyphColor: kpi.hovered ? kpi.tint : Theme.outline
                    transform: Translate { x: kpi.hovered ? (I18n.rtl ? -3 : 3) : 0
                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } } }
                }
            }

            C.AppText {
                text: kpi.value
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontDisplay + 6
                color: Theme.text_strong
                Layout.fillWidth: true
                elide: Text.ElideRight
                LayoutMirroring.enabled: false
                horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
            }

            Item {
                id: visualSlot
                Layout.fillWidth: true
                implicitHeight: childrenRect.height
                visible: children.length > 0
            }

            Item { Layout.fillHeight: true }

            C.AppText {
                text: kpi.sub
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    // Segmented 7 / 30 day switch with a sliding thumb.
    component RangeSwitch: Rectangle {
        id: rs
        radius: Tokens.radiusPill
        color: Theme.input_bg
        border.width: 1
        border.color: Theme.border
        implicitWidth: rsRow.implicitWidth + 8
        implicitHeight: 36

        Rectangle {
            readonly property Item _on: rsRep.count > 1 ? rsRep.liveItemAt(Usage.rangeDays === 7 ? 0 : 1) : null
            x: _on ? rsRow.x + _on.x : 4
            y: 4
            width: _on ? _on.width : 0
            height: parent.height - 8
            radius: Tokens.radiusPill
            color: Theme.primary
            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        Row {
            id: rsRow
            anchors.centerIn: parent
            Repeater {
                id: rsRep
                // itemAt() is not a notifying lookup: a binding that ran before the
                // delegates existed got null and kept it (thumb missing on first show,
                // the active label invisible in light theme). `built` re-runs it.
                property int built: 0
                onItemAdded: built++
                onItemRemoved: built++
                function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                model: [
                    { d: 7,  label: I18n.tr("7 days") },
                    { d: 30, label: I18n.tr("30 days") }
                ]
                AbstractButton {
                    id: rsBtn
                    readonly property bool on: Usage.rangeDays === modelData.d
                    height: 28
                    implicitWidth: rsLbl.implicitWidth + Tokens.space4 * 2
                    hoverEnabled: true
                    onClicked: Usage.rangeDays = modelData.d
                    HoverHandler { id: rsHover; cursorShape: Qt.PointingHandCursor }
                    C.AppTooltip {
                        // A named HoverHandler, NOT `parent.hovered`: AppTooltip
                        // moves itself onto the window overlay.
                        visible: rsHover.hovered
                        delay: 400
                        text: modelData.d === 7
                              ? I18n.tr("Chart the last 7 days")
                              : I18n.tr("Chart the last 30 days")
                    }
                    background: Item {}
                    contentItem: C.AppText {
                        id: rsLbl
                        text: modelData.label
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: rsBtn.on ? Theme.on_primary
                               : rsHover.hovered ? Theme.text_strong : Theme.on_surface_var
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                }
            }
        }
    }

    // ═══════════════════════ page ═══════════════════════
    C.SmoothScrollView {
        anchors.fill: parent

        Item {
            width: parent.width
            implicitHeight: content.implicitHeight + Tokens.space7 * 2

            // faint grid backdrop that fades out behind the header
            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 420
            }

            ColumnLayout {
                id: content
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space7
                spacing: Tokens.space4

                // ═══ HERO — today's reading + the fuel dial ═══
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: heroCol.implicitHeight + Tokens.space6 * 2

                    C.CornerGlow { radius: Tokens.radiusXl; size: 540; glow: page._level }

                    ColumnLayout {
                        id: heroCol
                        anchors.fill: parent
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space4

                        // eyebrow · actions
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            Pill {
                                dot: true
                                pulse: true
                                tint: Theme.primary
                                text_: I18n.tr("Usage & Quota · live ledger")
                            }
                            Item { Layout.fillWidth: true }
                            C.IconButton {
                                iconName: "refresh"
                                accent: Theme.primary
                                tip: I18n.tr("Refresh now")
                                onClicked: Usage.refresh()
                            }
                            C.PrimaryButton {
                                iconName: "vpn_key"
                                text: I18n.tr("Manage keys")
                                onClicked: App.goto(10)  // PAGE_SETTINGS
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space7

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Tokens.space3

                                C.AppText {
                                    text: I18n.tr("TODAY'S API UNITS")
                                    mono: true
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                    color: Theme.on_surface_var
                                }

                                // scoreboard: used / capacity
                                Row {
                                    spacing: Tokens.space2
                                    LayoutMirroring.enabled: false
                                    Layout.alignment: I18n.rtl ? Qt.AlignRight : Qt.AlignLeft
                                    C.AppText {
                                        id: bigUsed
                                        text: Usage.unitsValue.split(" / ")[0]
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Math.round(Math.max(44, Math.min(68, content.width / 22)))
                                        color: Theme.text_strong
                                    }
                                    C.AppText {
                                        text: "/ " + Usage.capacityText
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontTitle
                                        color: Theme.outline
                                        anchors.baseline: bigUsed.baseline
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    Pill { dot: true; tint: page._levelChip; text_: page._levelLabel }
                                    Pill {
                                        visible: page._hasKey
                                        mono: true
                                        tint: page._level
                                        text_: I18n.tr("{p}% spent").replace("{p}", page._pct)
                                    }
                                    Pill { icon: "history"; mono: true; text_: Usage.resetText }
                                }

                                // linear echo of the dial, for narrow windows
                                // where the dial itself is hidden
                                C.MeterBar {
                                    visible: !heroDial.visible
                                    Layout.fillWidth: true
                                    barHeight: 10
                                    value: page._frac
                                    fillColor: page._level
                                }

                                C.AppText {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 680
                                    text: Usage.unitsSub
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.on_surface_var
                                    wrapMode: Text.WordWrap
                                }
                            }

                            FuelDial {
                                id: heroDial
                                visible: content.width >= 820
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: implicitHeight
                                Layout.alignment: Qt.AlignVCenter
                                value: page._frac
                                tint: page._level
                                usedText: Usage.unitsValue.split(" / ")[0]
                                capText: Usage.capacityText
                            }
                        }
                    }
                }

                // ── KPI row: searches · runway · keys ──
                GridLayout {
                    Layout.fillWidth: true
                    columns: content.width < 760 ? 1 : 3
                    columnSpacing: Tokens.space4
                    rowSpacing: Tokens.space4

                    KpiCard {
                        caption: I18n.tr("KEYWORD SEARCHES")
                        icon: "travel_explore"
                        tint: Usage.searchFrac >= 0.75 ? Theme.warn : Theme.primary
                        value: Usage.searchValue
                        sub: Usage.searchSub

                        // the 100-search bucket as 20 cells of 5
                        visual: Row {
                            id: bucket
                            width: parent.width
                            spacing: 3
                            readonly property int lit: Math.round(Math.max(0, Math.min(1, Usage.searchFrac || 0)) * 20)
                            Repeater {
                                model: 20
                                Rectangle {
                                    width: (bucket.width - bucket.spacing * 19) / 20
                                    height: 14
                                    radius: 3
                                    color: index < bucket.lit
                                           ? (Usage.searchFrac >= 0.75 ? Theme.warn : Theme.primary)
                                           : U.withAlpha(Theme.outline, 0.18)
                                    opacity: index < bucket.lit ? (0.55 + 0.45 * (index + 1) / Math.max(1, bucket.lit)) : 1
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                                }
                            }
                        }
                    }

                    KpiCard {
                        caption: I18n.tr("ESTIMATED RUNWAY")
                        icon: "hourglass_empty"
                        tint: Theme.secondary_container
                        value: Usage.runwayValue
                        sub: Usage.runwaySub
                    }

                    KpiCard {
                        caption: I18n.tr("API KEYS")
                        icon: "vpn_key"
                        tint: Theme.tertiary
                        clickable: true
                        onClicked: App.goto(10)
                        value: Usage.hasKeys
                               ? I18n.tr("{h} of {n} healthy")
                                     .replace("{h}", page._healthyKeys)
                                     .replace("{n}", (Usage.keys || []).length)
                               : "0"
                        sub: Usage.hasKeys ? I18n.tr("Spend follows the key. Click to add or rotate keys in Settings.")
                                           : I18n.tr("No keys configured yet.")

                        // one mini meter per key, coloured by its state
                        visual: Row {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: Usage.keys
                                Rectangle {
                                    width: 30; height: 14; radius: 7
                                    color: U.withAlpha(page.tintColor(modelData.tint), 0.22)
                                    border.width: 1
                                    border.color: U.withAlpha(page.tintColor(modelData.tint), 0.55)
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 2
                                        width: Math.max(height, (parent.width - 4) * Math.max(0, Math.min(1, modelData.frac || 0)))
                                        radius: height / 2
                                        color: page.tintColor(modelData.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── v10: consumption ("Equalizer") + where units go ("Spectrum") ──
                GridLayout {
                    Layout.fillWidth: true
                    columns: width < 980 ? 1 : 3
                    columnSpacing: Tokens.space4
                    rowSpacing: Tokens.space4

                    C.Panel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.columnSpan: parent.columns >= 3 ? 2 : 1
                        content: [
                            // headline: the window's total, large and quiet
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space1
                                    Eyebrow { text: I18n.tr("CONSUMPTION") }
                                    RowLayout {
                                        spacing: Tokens.space2
                                        C.AppText {
                                            text: Usage.trendTotalText
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: 36
                                            font.letterSpacing: -0.8
                                            color: Theme.text_strong
                                            Layout.alignment: Qt.AlignBaseline
                                        }
                                        C.AppText {
                                            text: I18n.tr("units in the last {d} days").replace("{d}", Usage.rangeDays)
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.on_surface_var
                                            Layout.alignment: Qt.AlignBaseline
                                        }
                                    }
                                }
                                RangeSwitch { Layout.alignment: Qt.AlignTop }
                            },
                            // three facts that explain the shape of the chart
                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                StatChip {
                                    accent: true
                                    label: I18n.tr("Peak")
                                    value: Usage.peakText
                                    extra: Usage.peakLabel
                                }
                                StatChip {
                                    label: I18n.tr("Avg / day")
                                    value: Usage.trendAvgText
                                }
                                StatChip {
                                    label: I18n.tr("Active days")
                                    value: Usage.trendActiveDays + " / " + Usage.rangeDays
                                }
                            },
                            C.UsageTrendChart {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space2
                                model: Usage.trend
                                axis: Usage.trendAxis
                            },
                            // legend
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space4
                                Row {
                                    spacing: Tokens.space2
                                    Rectangle {
                                        width: 8; height: 12; radius: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Theme.primary }
                                            GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.42) }
                                        }
                                    }
                                    C.AppText {
                                        text: I18n.tr("Daily spend")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Row {
                                    spacing: Tokens.space2
                                    Rectangle {
                                        width: 16; height: 2; radius: 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: U.chartTint(4, Theme.primary, Theme.isDark)
                                    }
                                    C.AppText {
                                        text: I18n.tr("Running total")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                C.AppText {
                                    text: I18n.tr("Hover a day for exact numbers")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 260
                                }
                            }
                        ]
                    }

                    C.Panel {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        content: [
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space1
                                    Eyebrow { text: I18n.tr("WHERE UNITS GO") }
                                    RowLayout {
                                        spacing: Tokens.space2
                                        C.AppText {
                                            text: Usage.mixTotalText
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: 36
                                            font.letterSpacing: -0.8
                                            color: Theme.text_strong
                                            Layout.alignment: Qt.AlignBaseline
                                        }
                                        C.AppText {
                                            text: I18n.tr("units")
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.on_surface_var
                                            Layout.alignment: Qt.AlignBaseline
                                        }
                                    }
                                }
                                StatChip {
                                    Layout.alignment: Qt.AlignTop
                                    label: I18n.tr("30 days")
                                }
                            },
                            // the one sentence that matters: who is eating the quota
                            C.AppText {
                                id: driverLine
                                readonly property var lead: {
                                    var m = Usage.mix || [], best = null
                                    for (var i = 0; i < m.length; i++)
                                        if (!best || m[i].units > best.units) best = m[i]
                                    return best
                                }
                                visible: Usage.hasMix && lead !== null
                                Layout.fillWidth: true
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                font.pixelSize: Tokens.fontBody
                                color: Theme.on_surface_var
                                text: lead ? I18n.tr("{name} drives {p} of your spend")
                                              .replace("{name}", "<font color='" + Theme.text_strong + "'><b>" + lead.name + "</b></font>")
                                              .replace("{p}", "<font color='" + Theme.primary + "'><b>" + lead.pctText + "</b></font>")
                                          : ""
                            },
                            C.UnitMixBreakdown {
                                visible: Usage.hasMix
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space1
                                model: Usage.mix
                            },
                            C.AppText {
                                visible: Usage.mixNote !== ""
                                Layout.fillWidth: true
                                text: Usage.mixNote
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                wrapMode: Text.Wrap
                            },
                            ColumnLayout {
                                visible: !Usage.hasMix
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space5
                                spacing: Tokens.space2
                                C.IconTile {
                                    Layout.alignment: Qt.AlignHCenter
                                    iconName: "insights"
                                    size: 44; glyphSize: 21
                                    iconFill: false
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("No spend recorded yet.")
                                    color: Theme.outline
                                    font.pixelSize: Tokens.fontCaption
                                }
                            }
                        ]
                    }
                }

                // ── v11: the keys behind the spend ("Cells") ──
                C.Panel {
                    Layout.fillWidth: true
                    content: [
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space1
                                Eyebrow { text: I18n.tr("API KEYS") }
                                RowLayout {
                                    spacing: Tokens.space2
                                    C.AppText {
                                        text: Usage.hasKeys ? Usage.unitsLeftText : "0"
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: 36
                                        font.letterSpacing: -0.8
                                        color: Theme.text_strong
                                        Layout.alignment: Qt.AlignBaseline
                                    }
                                    C.AppText {
                                        text: I18n.tr("units left today")
                                        font.pixelSize: Tokens.fontBody
                                        color: Theme.on_surface_var
                                        Layout.alignment: Qt.AlignBaseline
                                    }
                                }
                            }
                            Flow {
                                Layout.alignment: Qt.AlignTop
                                Layout.maximumWidth: 420
                                spacing: Tokens.space2
                                layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                                StatChip {
                                    visible: Usage.hasKeys
                                    accent: page._healthyKeys === (Usage.keys || []).length
                                    label: I18n.tr("{h} of {n} healthy")
                                               .replace("{h}", page._healthyKeys)
                                               .replace("{n}", (Usage.keys || []).length)
                                }
                                StatChip {
                                    visible: Usage.resetText !== ""
                                    label: Usage.resetText
                                }
                            }
                        },

                        // empty: no keys at all
                        Rectangle {
                            Layout.fillWidth: true
                            visible: !Usage.hasKeys
                            implicitHeight: noKeyCol.implicitHeight + Tokens.space6 * 2
                            radius: Tokens.radiusLg
                            color: U.withAlpha(Theme.primary, 0.04)
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, 0.20)
                            ColumnLayout {
                                id: noKeyCol
                                anchors.centerIn: parent
                                spacing: Tokens.space3
                                C.IconTile {
                                    Layout.alignment: Qt.AlignHCenter
                                    iconName: "vpn_key"
                                    solid: true
                                    breathe: true
                                    size: 48; glyphSize: 22
                                }
                                C.AppText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: I18n.tr("No keys configured yet.")
                                    weight: Tokens.weightBold
                                    color: Theme.text_strong
                                }
                                C.PrimaryButton {
                                    Layout.alignment: Qt.AlignHCenter
                                    iconName: "add"
                                    text: I18n.tr("Add your first key")
                                    onClicked: App.goto(10)
                                }
                            }
                        },

                        GridLayout {
                            Layout.fillWidth: true
                            visible: Usage.hasKeys
                            columns: width < 620 ? 1 : (width < 1040 ? 2 : 3)
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space4
                            Repeater {
                                model: Usage.keys
                                Rectangle {
                                    id: keyCard
                                    required property var modelData
                                    readonly property color stateColor: page.tintColor(modelData.tint)
                                    readonly property real frac: Math.max(0, Math.min(1, modelData.frac || 0))
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: keyCol.implicitHeight + Tokens.space4 * 2
                                    radius: Tokens.radiusLg
                                    color: keyHover.hovered ? U.hoverTint(Theme.surface_high, Theme.isDark, 0.03) : Theme.surface_high
                                    border.width: 1
                                    border.color: keyHover.hovered ? U.withAlpha(keyCard.stateColor, 0.45) : Theme.border
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    HoverHandler { id: keyHover }

                                    ColumnLayout {
                                        id: keyCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.space4
                                        spacing: Tokens.space3

                                        // identity
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space3
                                            C.IconTile {
                                                iconName: "vpn_key"
                                                size: 34; glyphSize: 16
                                                tint: keyCard.stateColor
                                                iconFill: false
                                                lit: keyHover.hovered
                                            }
                                            ColumnLayout {
                                                spacing: 0
                                                Layout.fillWidth: true
                                                C.AppText {
                                                    text: keyCard.modelData.name
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontBody
                                                    color: Theme.text_strong
                                                }
                                                C.AppText {
                                                    text: keyCard.modelData.tail
                                                    mono: true
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.outline
                                                    LayoutMirroring.enabled: false
                                                }
                                            }
                                            Pill {
                                                dot: true
                                                pulse: keyCard.modelData.tint !== "secondary_container"
                                                tint: keyCard.stateColor
                                                text_: keyCard.modelData.state
                                            }
                                        }

                                        // what is left, in the units that matter
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: Tokens.space1
                                            spacing: Tokens.space2
                                            C.AppText {
                                                text: keyCard.modelData.leftText
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: 28
                                                font.letterSpacing: -0.6
                                                color: Theme.text_strong
                                                Layout.alignment: Qt.AlignBaseline
                                                LayoutMirroring.enabled: false
                                            }
                                            C.AppText {
                                                text: I18n.tr("left")
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                                Layout.alignment: Qt.AlignBaseline
                                            }
                                            Item { Layout.fillWidth: true }
                                            C.AppText {
                                                text: I18n.tr("{p}% used").replace("{p}", Math.round(keyCard.frac * 100))
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: keyCard.stateColor
                                                Layout.alignment: Qt.AlignBaseline
                                            }
                                        }

                                        // 40 cells, one per 250 units of the key's 10K day
                                        Item {
                                            id: cells
                                            Layout.fillWidth: true
                                            implicitHeight: 16
                                            LayoutMirroring.enabled: false
                                            LayoutMirroring.childrenInherit: true
                                            readonly property int count: 40
                                            readonly property real gap: 3
                                            readonly property int lit: Math.round(keyCard.frac * count)
                                            property real grow: 0
                                            Component.onCompleted: cellAnim.restart()
                                            NumberAnimation {
                                                id: cellAnim
                                                target: cells; property: "grow"; from: 0; to: 1
                                                duration: 900; easing.type: Easing.OutQuart
                                            }
                                            Row {
                                                anchors.fill: parent
                                                spacing: cells.gap
                                                Repeater {
                                                    model: cells.count
                                                    Rectangle {
                                                        required property int index
                                                        readonly property bool on: index < Math.round(cells.lit * cells.grow)
                                                        width: Math.max(1, (cells.width - cells.gap * (cells.count - 1)) / cells.count)
                                                        height: cells.height
                                                        radius: Math.min(3, width / 2)
                                                        color: on ? keyCard.stateColor : U.withAlpha(Theme.outline, 0.16)
                                                        opacity: on ? (0.45 + 0.55 * (index + 1) / Math.max(1, cells.lit)) : 1
                                                    }
                                                }
                                            }
                                        }

                                        C.AppText {
                                            text: keyCard.modelData.usedText + " / " + keyCard.modelData.capText + " " + I18n.tr("units")
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                        }
                                    }
                                }
                            }

                            // add-a-key tile (the VM shows up to 6 keys)
                            Rectangle {
                                id: addKey
                                visible: (Usage.keys || []).length < 6
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                implicitHeight: 120
                                radius: Tokens.radiusLg
                                color: addHover.hovered ? U.withAlpha(Theme.primary, 0.06) : U.withAlpha(Theme.primary, 0.02)
                                border.width: 1
                                border.color: addHover.hovered ? U.withAlpha(Theme.primary, 0.45) : U.mix(Theme.border, Theme.outline, 0.25)
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: App.goto(10) }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: Tokens.space3
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 40; height: 40; radius: 20
                                        color: U.withAlpha(Theme.primary, addHover.hovered ? 0.18 : 0.10)
                                        rotation: addHover.hovered ? 90 : 0
                                        Behavior on rotation { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                        C.IconGlyph {
                                            anchors.centerIn: parent
                                            name: "add"; size: 18
                                            glyphColor: Theme.primary
                                        }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        C.AppText {
                                            text: I18n.tr("Add a key")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontBody
                                            color: addHover.hovered ? Theme.primary : Theme.text_strong
                                        }
                                        C.AppText {
                                            text: I18n.tr("+10K units a day per key")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                        }
                                    }
                                }
                            }
                        }
                    ]
                }

                // ── v11: the price list ("Weights") ──
                C.Panel {
                    Layout.fillWidth: true
                    content: [
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space1
                                Eyebrow { text: I18n.tr("WHAT THINGS COST") }
                                // the one fact that explains this whole page
                                C.AppText {
                                    Layout.fillWidth: true
                                    textFormat: Text.StyledText
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Tokens.fontTitle
                                    weight: Tokens.weightBold
                                    color: Theme.text_strong
                                    text: I18n.tr("One keyword search costs as much as {n} video lookups")
                                              .replace("{n}", "<font color='" + Theme.primary + "'>5,000</font>")
                                }
                            }
                            StatChip {
                                Layout.alignment: Qt.AlignTop
                                label: I18n.tr("YouTube bills in units")
                            }
                        },

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space1
                            columns: width < 620 ? 2 : 4
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space4
                            Repeater {
                                model: [
                                    { icon: "travel_explore", label: I18n.tr("Keyword search"),       cost: 100, note: I18n.tr("per search page") },
                                    { icon: "video",          label: I18n.tr("Video stats"),          cost: 1,   note: I18n.tr("per 50 videos") },
                                    { icon: "user",           label: I18n.tr("Channel lookup"),       cost: 1,   note: I18n.tr("per 50 channels") },
                                    { icon: "archive",        label: I18n.tr("Reopening an archive"), cost: 0,   note: I18n.tr("always free") }
                                ]
                                Rectangle {
                                    id: costTile
                                    required property var modelData
                                    readonly property bool free: modelData.cost === 0
                                    readonly property bool heavy: modelData.cost >= 100
                                    readonly property color accent: free ? Theme.secondary_container : Theme.primary
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: cell.implicitHeight + Tokens.space4 * 2
                                    radius: Tokens.radiusLg
                                    color: heavy ? U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.06)
                                         : free  ? U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.08 : 0.06)
                                         : Theme.surface_high
                                    border.width: 1
                                    border.color: costHover.hovered ? U.withAlpha(costTile.accent, 0.50)
                                                  : heavy ? U.withAlpha(Theme.primary, 0.28)
                                                  : free  ? U.withAlpha(Theme.secondary_container, 0.28)
                                                  : Theme.border
                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    HoverHandler { id: costHover }

                                    ColumnLayout {
                                        id: cell
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.space4
                                        spacing: Tokens.space2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2
                                            C.IconTile {
                                                iconName: costTile.modelData.icon
                                                size: 30; glyphSize: 15
                                                tint: costTile.accent
                                                iconFill: false
                                                lit: costHover.hovered
                                            }
                                            C.AppText {
                                                text: costTile.modelData.label
                                                weight: Tokens.weightDemiBold
                                                font.pixelSize: Tokens.fontBody
                                                color: Theme.text_strong
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        RowLayout {
                                            Layout.topMargin: Tokens.space1
                                            spacing: Tokens.space2
                                            C.AppText {
                                                text: costTile.free ? I18n.tr("Free") : String(costTile.modelData.cost)
                                                mono: !costTile.free
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: 34
                                                font.letterSpacing: -0.8
                                                color: costTile.heavy ? Theme.primary
                                                     : costTile.free ? Theme.secondary_container
                                                     : Theme.text_strong
                                                Layout.alignment: Qt.AlignBaseline
                                            }
                                            C.AppText {
                                                visible: !costTile.free
                                                text: I18n.tr("units")
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                                Layout.alignment: Qt.AlignBaseline
                                            }
                                        }
                                        C.AppText {
                                            text: costTile.modelData.note
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                        }
                                        // weight against the priciest call: 100 = full
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.topMargin: Tokens.space1
                                            Layout.preferredHeight: 4
                                            radius: 2
                                            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.06)
                                            LayoutMirroring.enabled: false
                                            Rectangle {
                                                visible: !costTile.free
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: Math.max(4, parent.width * costTile.modelData.cost / 100)
                                                radius: 2
                                                color: costTile.heavy ? Theme.primary : U.withAlpha(Theme.on_surface_var, 0.55)
                                            }
                                        }
                                    }
                                }
                            }
                        },

                        // savings strip — what the archive has already saved
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: saveRow.implicitHeight + Tokens.space4 * 2
                            radius: Tokens.radiusLg
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.14 : 0.10) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.secondary_container, 0.02) }
                            }
                            border.width: 1
                            border.color: U.withAlpha(Theme.secondary_container, 0.28)
                            RowLayout {
                                id: saveRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.space4
                                anchors.rightMargin: Tokens.space4
                                spacing: Tokens.space4
                                C.IconTile {
                                    iconName: "archive"
                                    size: 40; glyphSize: 19
                                    tint: Theme.secondary_container
                                    iconFill: false
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                // with savings: a number, then the reason
                                ColumnLayout {
                                    visible: Usage.cacheCount > 0
                                    Layout.fillWidth: true
                                    spacing: 0
                                    RowLayout {
                                        spacing: Tokens.space2
                                        C.AppText {
                                            text: Usage.cacheSavedText
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: 24
                                            color: Theme.secondary_container
                                            Layout.alignment: Qt.AlignBaseline
                                        }
                                        C.AppText {
                                            text: I18n.tr("units saved")
                                            weight: Tokens.weightDemiBold
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.text_strong
                                            Layout.alignment: Qt.AlignBaseline
                                        }
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("{n} searches cached locally · reopening them is free")
                                                  .replace("{n}", Usage.cacheCount)
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        elide: Text.ElideRight
                                    }
                                }
                                // nothing cached yet: the original sentence
                                C.AppText {
                                    visible: Usage.cacheCount <= 0
                                    Layout.fillWidth: true
                                    text: Usage.cacheText
                                    color: Theme.on_surface
                                    wrapMode: Text.WordWrap
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                C.PrimaryButton {
                                    variant: "ghost"
                                    iconName: "nav_archive"
                                    text: I18n.tr("Open Search Archive")
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: App.goto(5)  // PAGE_ARCHIVE
                                }
                            }
                        }
                    ]
                }

                // ── how this page counts (collapsible) ──
                // The three ledgers, what bumps each, when they reset, and why
                // reopening a cached search is free. The reset and cache lines
                // reuse the live VM strings so they can never disagree with the
                // header pill and the price list above.
                C.GlassPanel {
                    id: howPanel
                    property bool expanded: false
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    hoverGlow: true
                    implicitHeight: howHead.height + Tokens.space5 * 2 + howClip.height

                    RowLayout {
                        id: howHead
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        height: 36
                        spacing: Tokens.space3
                        C.IconTile {
                            iconName: "info"
                            size: 36; glyphSize: 18
                            iconFill: false
                            lit: howPanel.hovered
                        }
                        C.AppText {
                            text: I18n.tr("How this page counts")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontSubtitle
                            color: Theme.text_strong
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        C.AppText {
                            text: howPanel.expanded ? I18n.tr("Hide details") : I18n.tr("Show details")
                            weight: Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontCaption
                            color: howPanel.hovered ? Theme.primary : Theme.on_surface_var
                        }
                        C.IconGlyph {
                            name: "expand_more"; size: 20
                            glyphColor: howPanel.hovered ? Theme.primary : Theme.on_surface_var
                            rotation: howPanel.expanded ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                        }
                    }
                    MouseArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: howHead.height + Tokens.space5 * 2
                        cursorShape: Qt.PointingHandCursor
                        onClicked: howPanel.expanded = !howPanel.expanded
                    }

                    Item {
                        id: howClip
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: howHead.bottom
                        anchors.leftMargin: Tokens.space5
                        anchors.rightMargin: Tokens.space5
                        clip: true
                        height: howPanel.expanded ? howBody.implicitHeight + Tokens.space4 : 0
                        Behavior on height { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: howBody
                        width: parent.width
                        y: Tokens.space4
                        spacing: Tokens.space3
                        opacity: howPanel.expanded ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: content.width < 900 ? 1 : 3
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3
                            Repeater {
                                model: [
                                    { icon: "data",           text: I18n.tr("Three ledgers: the search bucket (100 search calls a day), raw units per day (what YouTube actually bills), and spend per key.") },
                                    { icon: "travel_explore", text: I18n.tr("An API-source Niche Finder search bumps all three at once — bucket +1, units +100 (plus +1 per enrichment call), and the matching key row.") },
                                    { icon: "nav_scrape",     text: I18n.tr("A Web scrape touches none of the search bucket — only +1-unit enrichment calls, and only when a key is set.") }
                                ]
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: howCell.implicitHeight + Tokens.space4 * 2
                                    radius: Tokens.radiusLg
                                    color: Theme.surface_high
                                    border.width: 1
                                    border.color: Theme.border
                                    RowLayout {
                                        id: howCell
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space4
                                        spacing: Tokens.space3
                                        C.IconTile {
                                            iconName: modelData.icon
                                            size: 30; glyphSize: 15
                                            iconFill: false
                                            Layout.alignment: Qt.AlignTop
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: modelData.text
                                            color: Theme.on_surface
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: Usage.resetText
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: Usage.cacheText
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                    }
                    }
                }
            }
        }
    }
}
