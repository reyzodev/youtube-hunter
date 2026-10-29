import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// BlueprintForge — the AI Ideas "generating" state (v3.39.5).
//
// The run is a one-to-four-minute black box, so this panel is about making
// the wait feel like the app is BUILDING something, not stalling:
//
//   ┌───────────────────────────────────────────────────────────────────┐
//   │  · · · · · · blueprint dot-grid, drifting · · · · · · · · · · · ·  │
//   │    ╭ ─ ─ ─ ╮        AI FORGE · 01:24                               │
//   │  ◎ [thumb]  ◎       Forging 2 blueprints                           │
//   │ ( ⟲  LOGO  ⟳ )      Asking Appaxa for 2 blueprint(s)…              │
//   │  ◎  [thumb] ◎       ●──────●──────◉──────○  phases                 │
//   │    ╰ ─ ─ ─ ╯        [▤ sheet #1 writing] [▤ sheet #2 writing]      │
//   └───────────────────────────────────────────────────────────────────┘
//
// Signature: the brand mark FORGES itself on a loop — its neon outline is
// drafted like a blueprint line drawing, then the solid pieces slam in, a
// shockwave rings out, and the pieces release again. The picked reference
// thumbnails orbit the mark on a tilted ring (3D carousel: front ones larger
// and brighter), and sparks stream from the orbit into the core — the
// references are visibly being "fed" into the blueprint.
//
// Honesty: the elapsed clock is real. The four phases advance on elapsed time
// (the provider streams no real progress) and the last one never completes
// on its own — the panel disappears when the real result lands.
C.GlassPanel {
    id: root

    property bool active: false
    property string status: ""
    property int count: 1                   // blueprints in this run
    property var thumbs: []                 // thumbnail ids of the picked refs
    property string note: ""

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    readonly property bool _live: active && visible && _motion
    readonly property bool _wide: width >= 860
    readonly property color _a: Theme.primary
    readonly property color _b: Theme.tertiary

    radius: Tokens.radiusXl
    clip: true
    elevation: 1.0
    border.color: U.withAlpha(Theme.primary, 0.34)
    implicitHeight: lay.implicitHeight + Tokens.space6 * 2

    // ── real elapsed clock ──
    property int _secs: 0
    onActiveChanged: if (active) _secs = 0
    Timer {
        interval: 1000; repeat: true
        running: root.active
        onTriggered: root._secs++
    }
    readonly property string _clock: {
        var m = Math.floor(_secs / 60), s = _secs % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }
    // phase thresholds in seconds; the last phase never self-completes
    readonly property var _gates: [0, 10, 35, 85]
    readonly property int _phase: {
        var p = 0
        for (var i = 0; i < _gates.length; i++) if (_secs >= _gates[i]) p = i
        return p
    }
    readonly property var _phases: [
        { icon: "movie",        label: I18n.tr("Reading references") },
        { icon: "query_stats",  label: I18n.tr("Finding the pattern") },
        { icon: "edit",         label: I18n.tr("Drafting hooks & script") },
        { icon: "auto_awesome", label: I18n.tr("Polishing the greenlight") }
    ]

    // ═════════════════ ambient background ═════════════════
    // aurora: two brand-coloured lights drifting slowly behind everything
    C.GlowBlob {
        id: auroraA
        size: 360
        glow: root._a
        strength: Theme.isDark ? 0.15 : 0.09
        x: -120 + 60 * Math.sin(root._drift * Math.PI * 2)
        y: -140 + 40 * Math.cos(root._drift * Math.PI * 2)
    }
    C.GlowBlob {
        size: 300
        glow: root._b
        strength: Theme.isDark ? 0.12 : 0.07
        x: root.width - 260 - 70 * Math.cos(root._drift * Math.PI * 2)
        y: root.height - 200 + 40 * Math.sin(root._drift * Math.PI * 2)
    }
    property real _drift: 0
    NumberAnimation on _drift {
        running: root._live
        from: 0; to: 1; duration: 16000
        loops: Animation.Infinite
    }

    // blueprint dot grid, drifting one cell diagonally on a seamless loop
    Item {
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        opacity: Theme.isDark ? 0.55 : 0.45
        Canvas {
            id: dots
            readonly property int step: 22
            width: parent.width + step
            height: parent.height + step
            property real shift: 0
            x: -shift; y: -shift
            NumberAnimation on shift {
                running: root._live
                from: 0; to: dots.step; duration: 5200
                loops: Animation.Infinite
            }
            renderStrategy: Canvas.Cooperative
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections { target: Theme; function onChanged() { dots.requestPaint() } }
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var c = Theme.outline
                ctx.fillStyle = "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                                + Math.round(c.b * 255) + ",0.30)"
                for (var yy = step / 2; yy < height; yy += step)
                    for (var xx = step / 2; xx < width; xx += step) {
                        ctx.beginPath()
                        ctx.arc(xx, yy, 1, 0, Math.PI * 2)
                        ctx.fill()
                    }
            }
        }
        // fade the grid out toward the text side so copy stays clean
        Rectangle {
            anchors.fill: parent
            rotation: I18n.rtl ? 180 : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.42; color: "transparent" }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.panel_bg, 0.85) }
            }
        }
    }

    // indeterminate comet along the top edge
    Item {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.leftMargin: Tokens.radiusXl; anchors.rightMargin: Tokens.radiusXl
        height: 2
        clip: true
        Rectangle {
            id: comet
            width: parent.width * 0.32
            height: 2
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(root._b, 0.0) }
                GradientStop { position: 0.7; color: root._a }
                GradientStop { position: 1.0; color: Qt.lighter(root._a, 1.5) }
            }
            NumberAnimation on x {
                running: root._live
                from: -comet.width; to: comet.parent.width
                duration: 1900; easing.type: Easing.InOutCubic
                loops: Animation.Infinite
            }
        }
    }

    // ═════════════════ layout ═════════════════
    GridLayout {
        id: lay
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.space6
        anchors.rightMargin: Tokens.space6
        columns: root._wide ? 2 : 1
        columnSpacing: Tokens.space7
        rowSpacing: Tokens.space5

        // ─────────────── the forge stage ───────────────
        Item {
            id: stage
            readonly property real s: 248
            Layout.preferredWidth: s
            Layout.preferredHeight: s
            Layout.alignment: root._wide ? Qt.AlignVCenter : Qt.AlignHCenter
            readonly property real cx: s / 2
            readonly property real cy: s / 2

            // one master clock for the whole forge cycle (0..1, 5.6s)
            property real cyc: 0.62           // resting pose when motion is off
            NumberAnimation on cyc {
                running: root._live
                from: 0; to: 1; duration: 5600
                loops: Animation.Infinite
            }
            // orbit angle
            property real spin: 0
            NumberAnimation on spin {
                running: root._live
                from: 0; to: Math.PI * 2; duration: 18000
                loops: Animation.Infinite
            }

            function seg(t, a, b) { return Math.max(0, Math.min(1, (t - a) / (b - a))) }
            //   0.00-0.30  outline is drafted
            //   0.26-0.44  pieces slam in, play pops
            //   0.44       impact: shockwave + glow spike
            //   0.48-0.70  sheen sweeps the solid mark
            //   0.70-0.86  hold
            //   0.86-1.00  pieces release, outline fades
            readonly property real draft: seg(cyc, 0.0, 0.30)
            readonly property real build: cyc < 0.86 ? seg(cyc, 0.26, 0.44) : 1 - seg(cyc, 0.86, 1.0)
            readonly property real pop: cyc < 0.86 ? seg(cyc, 0.36, 0.50) : 1 - seg(cyc, 0.86, 0.95)
            readonly property real impact: seg(cyc, 0.44, 0.78)
            readonly property real outline: cyc < 0.86 ? 1 - 0.65 * seg(cyc, 0.46, 0.62) : 0.35 + 0.65 * seg(cyc, 0.86, 1.0)

            // core light
            C.GlowBlob {
                anchors.centerIn: parent
                size: 150
                glow: root._a
                strength: (Theme.isDark ? 0.20 : 0.13)
                          * (0.65 + 0.7 * (1 - stage.impact) * (stage.impact > 0 ? 1 : 0) + 0.15 * stage.build)
            }

            // outer dashed blueprint ring, slow
            Shape {
                anchors.fill: parent
                // default renderer here: it is the one that draws dashes
                antialiasing: true
                rotation: stage.spin * 180 / Math.PI * 0.5
                ShapePath {
                    strokeColor: U.withAlpha(Theme.outline, 0.38)
                    strokeWidth: 1
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 5]
                    PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: 116; radiusY: 116; startAngle: 0; sweepAngle: 360 }
                }
            }
            // two counter-rotating accent arcs
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                property real r: 0
                rotation: r
                NumberAnimation on r { running: root._live; from: 0; to: 360; duration: 3400; loops: Animation.Infinite }
                ShapePath {
                    strokeColor: root._a
                    strokeWidth: 2.5
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: 98; radiusY: 98; startAngle: 0; sweepAngle: 74 }
                }
                ShapePath {
                    strokeColor: U.withAlpha(root._a, 0.35)
                    strokeWidth: 2.5
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: 98; radiusY: 98; startAngle: 180; sweepAngle: 26 }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                property real r: 360
                rotation: r
                NumberAnimation on r { running: root._live; from: 360; to: 0; duration: 5200; loops: Animation.Infinite }
                ShapePath {
                    strokeColor: U.withAlpha(root._b, 0.85)
                    strokeWidth: 1.5
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: 84; radiusY: 84; startAngle: 40; sweepAngle: 120 }
                }
            }

            // shockwave on impact
            Rectangle {
                anchors.centerIn: parent
                width: 90; height: 90; radius: 45
                color: "transparent"
                border.width: 2
                border.color: Qt.lighter(root._a, 1.35)
                antialiasing: true
                visible: stage.impact > 0 && stage.impact < 1
                scale: 0.7 + stage.impact * 1.9
                opacity: (1 - stage.impact) * 0.85
            }
            Rectangle {
                anchors.centerIn: parent
                width: 90; height: 90; radius: 45
                color: U.withAlpha(root._a, 0.10)
                antialiasing: true
                readonly property real t: stage.seg(stage.impact, 0.1, 1)
                visible: t > 0 && t < 1
                scale: 0.6 + t * 1.3
                opacity: (1 - t) * 0.7
            }

            // sparks pulled from the orbit into the core
            Repeater {
                model: root._motion ? 14 : 0
                Rectangle {
                    id: spark
                    readonly property real ang: index * 2.39996          // golden angle spread
                    readonly property real r0: 104 + (index % 3) * 10
                    property real t: 0
                    readonly property real e: t * t                         // accelerates inward
                    width: index % 4 === 0 ? 4 : 3
                    height: width
                    radius: width / 2
                    color: index % 2 ? root._a : Qt.lighter(root._b, 1.15)
                    x: stage.cx + Math.cos(ang + t * 0.9) * r0 * (1 - e) - width / 2
                    y: stage.cy + Math.sin(ang + t * 0.9) * r0 * (1 - e) * 0.62 - height / 2
                    opacity: Math.sin(Math.PI * t) * 0.95
                    scale: 1.2 - 0.6 * e
                    SequentialAnimation on t {
                        running: root._live
                        loops: Animation.Infinite
                        PauseAnimation { duration: (index * 263) % 1700 }
                        NumberAnimation { from: 0; to: 1; duration: 1500 + (index * 97) % 900 }
                    }
                }
            }

            // the orbiting references (tilted ring, 3D carousel)
            Repeater {
                id: orbit
                readonly property bool hasThumbs: (root.thumbs || []).length > 0
                model: hasThumbs ? Math.min(6, root.thumbs.length) : 3
                Item {
                    id: sat
                    readonly property real a: stage.spin + index * Math.PI * 2 / orbit.count
                    readonly property real depth: (Math.sin(a) + 1) / 2      // 0 back .. 1 front
                    readonly property real w: orbit.hasThumbs ? 54 : 34
                    readonly property real h: orbit.hasThumbs ? 31 : 34
                    width: w; height: h
                    x: stage.cx + Math.cos(a) * 112 - w / 2
                    y: stage.cy + Math.sin(a) * 44 - h / 2 + 4
                    z: depth > 0.5 ? 6 : 1
                    scale: 0.62 + 0.42 * depth
                    opacity: 0.35 + 0.65 * depth

                    Rectangle {
                        anchors.fill: parent
                        radius: orbit.hasThumbs ? 7 : width / 2
                        color: Theme.surface_high
                        border.width: 1
                        border.color: U.withAlpha(sat.depth > 0.7 ? root._a : Theme.outline, sat.depth > 0.7 ? 0.8 : 0.3)
                        clip: true
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            visible: orbit.hasThumbs
                            source: orbit.hasThumbs ? "image://thumbs/" + root.thumbs[index] : ""
                            sourceSize.width: 128
                            sourceSize.height: 72
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                        C.IconGlyph {
                            anchors.centerIn: parent
                            visible: !orbit.hasThumbs
                            name: ["edit", "psychology", "movie"][index % 3]
                            size: 16
                            glyphColor: root._a
                        }
                    }
                }
            }

            // the mark itself, forging on a loop
            C.BrandMark {
                id: mark
                z: 4
                width: 76
                height: Math.round(width * 812 / 738)
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 2
                glow: root.active
                glowStrength: 0.55 + 0.8 * (stage.impact > 0 ? (1 - stage.impact) : 0) + 0.2 * stage.build
                trace: root._motion ? stage.draft : 1
                traceOpacity: root._motion ? stage.outline : 0.0
                assemble: root._motion ? stage.build : 1
                playPop: root._motion ? stage.pop : 1
                sheen: root._motion && stage.cyc > 0.48 && stage.cyc < 0.72 ? stage.seg(stage.cyc, 0.48, 0.72) : -1
                scale: 1 + 0.06 * Math.sin(Math.PI * stage.seg(stage.cyc, 0.40, 0.56))
            }
        }

        // ─────────────── copy + progress ───────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.space3

            // eyebrow: live dot · AI FORGE · real clock
            RowLayout {
                spacing: Tokens.space2
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: root._a
                    Layout.alignment: Qt.AlignVCenter
                    SequentialAnimation on opacity {
                        running: root._live
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                    }
                }
                C.AppText {
                    text: I18n.tr("AI Forge")
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: I18n.rtl ? 0 : 1.6
                    color: root._a
                }
                Rectangle {
                    implicitWidth: clockTxt.implicitWidth + 14
                    implicitHeight: 22
                    radius: Tokens.radiusPill
                    color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.05)
                    border.width: 1
                    border.color: U.withAlpha(Theme.outline, 0.25)
                    C.AppText {
                        id: clockTxt
                        anchors.centerIn: parent
                        text: root._clock
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.text_strong
                    }
                }
            }

            C.AppText {
                text: (root.count === 1 ? I18n.tr("Forging 1 greenlight")
                                        : I18n.tr("Forging {n} greenlights").replace("{n}", root.count))
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontDisplay + 4
                font.letterSpacing: I18n.rtl ? 0 : -0.8
                color: Theme.text_strong
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            C.AppText {
                text: root.status
                font.pixelSize: Tokens.fontBody
                color: Theme.on_surface_var
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                // re-enter softly whenever the backend sends a new line
                onTextChanged: if (root._motion) statusIn.restart()
                NumberAnimation on opacity { id: statusIn; from: 0.2; to: 1; duration: Tokens.durSlow }
            }

            // ── phase rail ──
            Item {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space2
                implicitHeight: 52
                readonly property real gap: (width - 28) / (root._phases.length - 1)

                // base track + lit track
                Rectangle {
                    x: 14; y: 13
                    width: parent.width - 28; height: 2; radius: 1
                    color: U.withAlpha(Theme.outline, 0.22)
                }
                Rectangle {
                    id: litTrack
                    x: 14; y: 13
                    height: 2; radius: 1
                    width: parent.gap * root._phase
                    Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root._b }
                        GradientStop { position: 1.0; color: root._a }
                    }
                }
                Repeater {
                    model: root._phases
                    Item {
                        readonly property bool done: index < root._phase
                        readonly property bool cur: index === root._phase
                        x: 14 + index * parent.gap - 14
                        width: 28; height: parent.height
                        Rectangle {
                            id: node
                            width: 28; height: 28; radius: 14
                            color: done || cur ? root._a : Theme.surface_high
                            border.width: 1
                            border.color: done || cur ? Qt.lighter(root._a, 1.3) : U.withAlpha(Theme.outline, 0.35)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                            C.IconGlyph {
                                anchors.centerIn: parent
                                name: done ? "check" : modelData.icon
                                fill: true
                                size: 14
                                glyphColor: done || cur ? "#ffffff" : Theme.outline
                            }
                            // halo on the running phase
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28; height: 28; radius: 14
                                color: "transparent"
                                border.width: 2
                                border.color: root._a
                                visible: cur && root._motion
                                property real t: 0
                                scale: 1 + t * 0.7
                                opacity: (1 - t) * 0.8
                                NumberAnimation on t { running: cur && root._live; from: 0; to: 1; duration: 1300; loops: Animation.Infinite }
                            }
                        }
                        C.AppText {
                            anchors.top: node.bottom
                            anchors.topMargin: 6
                            x: index === 0 ? 0
                               : index === root._phases.length - 1 ? node.width - width
                               : (node.width - width) / 2
                            text: modelData.label
                            font.pixelSize: Tokens.fontCaption
                            weight: cur ? Tokens.weightBold : Tokens.weightMedium
                            color: cur ? Theme.text_strong : done ? Theme.on_surface_var : Theme.outline
                            visible: root.width >= 560 || cur
                        }
                    }
                }
            }

            // ── the sheets being written ──
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space3
                spacing: Tokens.space3
                Repeater {
                    model: Math.max(1, Math.min(4, root.count))
                    Rectangle {
                        id: sheet
                        width: Math.min(176, (parent.width - Tokens.space3 * 3) / Math.max(2, Math.min(4, root.count)))
                        height: 96
                        radius: Tokens.radiusLg
                        color: U.withAlpha(Theme.surface_high, Theme.isDark ? 0.75 : 0.9)
                        border.width: 1
                        border.color: U.mix(U.withAlpha(Theme.outline, 0.25), root._a, flash)
                        clip: true

                        property real draw: root._motion ? 0 : 0.6
                        property real flash: 0
                        readonly property var widths: [0.92, 0.66, 0.84, 0.52, 0.74]

                        SequentialAnimation {
                            running: root._live
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 700 }
                            NumberAnimation { target: sheet; property: "draw"; from: 0; to: 1; duration: 3200; easing.type: Easing.InOutSine }
                            NumberAnimation { target: sheet; property: "flash"; from: 0; to: 1; duration: 160 }
                            NumberAnimation { target: sheet; property: "flash"; to: 0; duration: 520; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 500 }
                            NumberAnimation { target: sheet; property: "draw"; to: 0; duration: 380; easing.type: Easing.InCubic }
                            PauseAnimation { duration: Math.max(0, 1400 - index * 700) }
                        }

                        // header: glyph + #n
                        Row {
                            x: 12; y: 10
                            spacing: 6
                            C.IconGlyph { name: "article"; fill: true; size: 13; glyphColor: root._a; anchors.verticalCenter: parent.verticalCenter }
                            C.AppText {
                                text: "#" + (index + 1)
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontMicro
                                color: Theme.on_surface_var
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        // lines filling in one after another
                        Column {
                            id: lines
                            x: 12; y: 34
                            width: parent.width - 24
                            spacing: 7
                            Repeater {
                                model: 5
                                Rectangle {
                                    height: 4; radius: 2
                                    color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.06)
                                    width: lines.width * sheet.widths[index]
                                    Rectangle {
                                        height: parent.height; radius: 2
                                        width: parent.width * Math.max(0, Math.min(1, sheet.draw * 5 - index))
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: U.withAlpha(root._a, index === 0 ? 0.95 : 0.55) }
                                            GradientStop { position: 1.0; color: U.withAlpha(root._b, index === 0 ? 0.85 : 0.45) }
                                        }
                                    }
                                }
                            }
                        }
                        // the write-head: a soft scan line riding the current row
                        Rectangle {
                            visible: root._motion && sheet.draw > 0 && sheet.draw < 1
                            x: 0; width: parent.width; height: 18
                            y: lines.y - 7 + Math.min(4, Math.floor(sheet.draw * 5)) * 11
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: U.withAlpha(root._a, 0.0) }
                                GradientStop { position: 0.5; color: U.withAlpha(root._a, 0.10) }
                                GradientStop { position: 1.0; color: U.withAlpha(root._a, 0.0) }
                            }
                        }
                    }
                }
            }

            C.AppText {
                visible: root.note !== ""
                text: root.note
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space1
            }
        }
    }
}
