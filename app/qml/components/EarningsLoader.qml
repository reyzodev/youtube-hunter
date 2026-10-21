import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// The Monetize Checker's loading state — "the mint".
//
// A check is 5-20 seconds of four different jobs, so the loader answers the
// two questions a person has while waiting ("is it moving?" / "how far?")
// with things that are TRUE, and dresses them like the thing being made:
// money.
//
//   * the coin       a $ coin in an orbit. It flips once every time the
//                    worker moves to the next real step (MonetizeVM.stage).
//   * the ring       a conic comet that never stops (it's alive), around a
//                    progress arc that only moves forward: finished steps
//                    are solid, the running one creeps toward its end but
//                    never claims it — the next stage signal does that.
//   * the ticker     slot-machine digit reels in the exact shape the answer
//                    will land in ("$000 - $00K"), so the result reads as
//                    the reels stopping, not as a new screen.
//   * the track      the four named steps; done ticks green, live one lit
//                    with a sheen, and an elapsed clock so "stuck" is
//                    visible as a number, not a feeling.
//
// Every animation is gated on `running`, so an off-screen page costs nothing.
Item {
    id: root

    property bool running: false
    property int stage: 0          // 0..3, straight from MonetizeVM.stage
    property string subject: ""    // what the user typed, echoed back

    readonly property var stages: [
        { g: "search",        t: I18n.tr("Finding the channel"),                  s: I18n.tr("Channel") },
        { g: "smart_display", t: I18n.tr("Reading its latest uploads"),           s: I18n.tr("Uploads") },
        { g: "verified",      t: I18n.tr("Scanning for Partner Program signals"), s: I18n.tr("Signals") },
        { g: "money",         t: I18n.tr("Pricing views against the niche RPM"),  s: I18n.tr("Revenue") }
    ]

    implicitHeight: body.implicitHeight

    // ── honest progress ──────────────────────────────────────────────────
    // `creep` eases toward 0.9 of the running step and resets on every real
    // stage change; the bar therefore never fakes a finish.
    property real creep: 0
    readonly property real progress: Math.min(1, (stage + creep) / stages.length)
    property real shownProgress: progress
    Behavior on shownProgress { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

    NumberAnimation {
        id: creepAnim
        target: root; property: "creep"
        from: 0; to: 0.9
        duration: 9000
        easing.type: Easing.OutCubic
    }
    function restartCreep() { creep = 0; if (running) creepAnim.restart() }
    onStageChanged: { restartCreep(); coinFlip.restart(); swapTitle.restart() }
    onRunningChanged: {
        if (running) { elapsed = 0; shownStage = stage; restartCreep() }
        else creepAnim.stop()
    }
    Component.onCompleted: if (running) restartCreep()

    // elapsed clock
    property int elapsed: 0
    Timer { interval: 1000; repeat: true; running: root.running; onTriggered: root.elapsed++ }
    function clock(s) {
        var m = Math.floor(s / 60), r = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
    }

    // the headline swaps with a lift instead of a hard cut
    property int shownStage: 0
    SequentialAnimation {
        id: swapTitle
        ParallelAnimation {
            NumberAnimation { target: titleTxt; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: titleShift; property: "y"; to: -8; duration: 140; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { root.shownStage = root.stage; titleShift.y = 10 } }
        ParallelAnimation {
            NumberAnimation { target: titleTxt; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: titleShift; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack }
        }
    }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.space7

        // ══════════ the orb ══════════
        Item {
            id: orb
            readonly property real d: 184
            readonly property real c: d / 2
            implicitWidth: d; implicitHeight: d
            Layout.alignment: Qt.AlignVCenter

            // breathing halo
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transformOrigin: Item.Center
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: orb.c; centerY: orb.c; centerRadius: orb.c
                        focalX: orb.c; focalY: orb.c
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.34 : 0.22) }
                        GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, 0.08) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    PathAngleArc { centerX: orb.c; centerY: orb.c; radiusX: orb.c; radiusY: orb.c; startAngle: 0; sweepAngle: 360 }
                }
                SequentialAnimation on scale {
                    running: root.running
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.88; to: 1.06; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.06; to: 0.88; duration: 1600; easing.type: Easing.InOutSine }
                }
            }

            // dotted guide ring, drifting the other way
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transformOrigin: Item.Center
                ShapePath {
                    strokeWidth: 1.5
                    strokeColor: U.withAlpha(Theme.outline, 0.55)
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [0.5, 5]
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: orb.c; centerY: orb.c; radiusX: orb.c - 6; radiusY: orb.c - 6; startAngle: 0; sweepAngle: 360 }
                }
                RotationAnimation on rotation {
                    running: root.running
                    loops: Animation.Infinite
                    from: 360; to: 0; duration: 24000
                }
            }

            // the comet: a conic-gradient ring that never stops
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transformOrigin: Item.Center
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: ConicalGradient {
                        centerX: orb.c; centerY: orb.c; angle: 90
                        GradientStop { position: 0.00; color: "transparent" }
                        GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, 0.10) }
                        GradientStop { position: 0.88; color: U.withAlpha(Theme.primary, 0.85) }
                        GradientStop { position: 1.00; color: Theme.secondary_container }
                    }
                    PathAngleArc { centerX: orb.c; centerY: orb.c; radiusX: orb.c - 16; radiusY: orb.c - 16; startAngle: 0; sweepAngle: 360 }
                    PathAngleArc { centerX: orb.c; centerY: orb.c; radiusX: orb.c - 22; radiusY: orb.c - 22; startAngle: 0; sweepAngle: 360 }
                }
                RotationAnimation on rotation {
                    running: root.running
                    loops: Animation.Infinite
                    from: 0; to: 360; duration: 1800
                }
            }

            // true progress: track + forward-only arc
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 4
                    strokeColor: U.withAlpha(Theme.on_surface, 0.07)
                    fillColor: "transparent"
                    PathAngleArc { centerX: orb.c; centerY: orb.c; radiusX: orb.c - 32; radiusY: orb.c - 32; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 4
                    strokeColor: Theme.primary
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: orb.c; centerY: orb.c
                        radiusX: orb.c - 32; radiusY: orb.c - 32
                        startAngle: -90
                        sweepAngle: Math.max(0.5, 360 * root.shownProgress)
                    }
                }
            }

            // orbiting sparks — three radii, three speeds
            Repeater {
                model: [ { r: 82, s: 7, ms: 5200, a: 0,   tint: 0 },
                         { r: 70, s: 5, ms: 3400, a: 140, tint: 1 },
                         { r: 88, s: 4, ms: 8600, a: 250, tint: 0 } ]
                Item {
                    anchors.fill: parent
                    rotation: modelData.a
                    Rectangle {
                        x: orb.c - width / 2
                        y: orb.c - modelData.r - height / 2
                        width: modelData.s; height: width; radius: width / 2
                        color: modelData.tint ? Theme.secondary_container : Theme.primary
                        opacity: 0.9
                    }
                    RotationAnimation on rotation {
                        running: root.running
                        loops: Animation.Infinite
                        from: modelData.a; to: modelData.a + 360; duration: modelData.ms
                    }
                }
            }

            // the coin
            Rectangle {
                id: coin
                anchors.centerIn: parent
                width: 74; height: 74; radius: 37
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.primary }
                    GradientStop { position: 1.0; color: Theme.primary_deep }
                }
                border.width: 1
                border.color: U.withAlpha("#ffffff", 0.28)
                // the inner rim every coin has
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: U.withAlpha("#ffffff", 0.22)
                }
                C.AppText {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    text: "$"
                    weight: Tokens.weightExtraBold
                    font.pixelSize: 34
                    color: Theme.on_primary
                }
                transform: Rotation {
                    id: coinSpin
                    origin.x: coin.width / 2; origin.y: coin.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: 0
                }
                SequentialAnimation on scale {
                    running: root.running
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 1.05; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.05; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            // one flip per real step
            NumberAnimation {
                id: coinFlip
                target: coinSpin; property: "angle"
                from: 0; to: 360; duration: 900
                easing.type: Easing.OutBack
            }
        }

        // ══════════ the readout ══════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.space3

            // eyebrow: live dot · label · step · clock
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: Theme.secondary_container
                    Layout.alignment: Qt.AlignVCenter
                    SequentialAnimation on opacity {
                        running: root.running
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 520; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                    }
                }
                C.AppText {
                    text: I18n.tr("ESTIMATING EARNINGS")
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    font.letterSpacing: I18n.rtl ? 0 : 1.6
                    color: Theme.primary
                }
                C.AppText {
                    text: I18n.tr("step {n} of {m}").replace("{n}", root.stage + 1).replace("{m}", root.stages.length)
                    mono: true
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.outline
                }
                Item { Layout.fillWidth: true }
                C.AppText {
                    text: root.clock(root.elapsed)
                    mono: true
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    LayoutMirroring.enabled: false
                }
            }

            // headline = the step running right now
            C.AppText {
                id: titleTxt
                text: root.stages[root.shownStage].t + "…"
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontTitle + 2
                color: Theme.text_strong
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                transform: Translate { id: titleShift; y: 0 }
            }
            C.AppText {
                visible: root.subject !== ""
                text: root.subject
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            // slot reels in the answer's own shape: $000 - $00K
            Item {
                id: ticker
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space1
                implicitHeight: 46
                LayoutMirroring.enabled: false
                LayoutMirroring.childrenInherit: true

                readonly property int cellH: 40
                Row {
                    id: reelRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        // "d" = a spinning digit reel, anything else is fixed glyph
                        model: ["$", "d", "d", "d", " - ", "$", "d", "d", "K"]
                        Item {
                            id: cell
                            required property string modelData
                            required property int index
                            readonly property bool reel: modelData === "d"
                            width: reel ? 24 : fixed.implicitWidth
                            height: ticker.cellH
                            clip: true

                            C.AppText {
                                id: fixed
                                visible: !cell.reel
                                anchors.verticalCenter: parent.verticalCenter
                                text: cell.modelData
                                mono: true
                                weight: Tokens.weightExtraBold
                                font.pixelSize: 30
                                color: cell.modelData === " - " ? Theme.outline : Theme.text_strong
                            }

                            Rectangle {
                                visible: cell.reel
                                anchors.fill: parent
                                radius: Tokens.radiusXs
                                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.045)
                            }
                            Column {
                                id: strip
                                visible: cell.reel
                                width: parent.width
                                // 0-9 then 0 again, so the loop seam is invisible
                                Repeater {
                                    model: 11
                                    C.AppText {
                                        width: strip.width
                                        height: ticker.cellH
                                        text: String(index % 10)
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: 30
                                        color: Theme.text_strong
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                NumberAnimation on y {
                                    running: root.running && cell.reel
                                    loops: Animation.Infinite
                                    from: 0; to: -10 * ticker.cellH
                                    duration: 700 + ((cell.index * 173) % 520)
                                }
                            }
                            // reel glass: fade the digits out at top and bottom
                            Rectangle {
                                visible: cell.reel
                                anchors.fill: parent
                                radius: Tokens.radiusXs
                                gradient: Gradient {
                                    GradientStop { position: 0.0;  color: Theme.panel_bg }
                                    GradientStop { position: 0.32; color: U.withAlpha(Theme.panel_bg, 0) }
                                    GradientStop { position: 0.68; color: U.withAlpha(Theme.panel_bg, 0) }
                                    GradientStop { position: 1.0;  color: Theme.panel_bg }
                                }
                            }
                        }
                    }
                }
                C.AppText {
                    anchors.left: reelRow.right
                    anchors.leftMargin: Tokens.space3
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("/ month")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                }
            }

            // the four real steps
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space1
                spacing: Tokens.space2
                Repeater {
                    model: root.stages
                    ColumnLayout {
                        id: stepCol
                        required property var modelData
                        required property int index
                        readonly property bool done: index < root.stage
                        readonly property bool live: index === root.stage
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: Tokens.space2

                        Rectangle {
                            id: seg
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: 3
                            color: U.withAlpha(Theme.on_surface, 0.08)
                            clip: true
                            Rectangle {
                                height: parent.height
                                radius: 3
                                width: parent.width * (stepCol.done ? 1 : stepCol.live ? root.creep : 0)
                                color: stepCol.done ? Theme.secondary_container : Theme.primary
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                                Behavior on width { enabled: stepCol.done; NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                            }
                            // sheen across the live segment
                            Rectangle {
                                visible: stepCol.live && root.running
                                width: 46
                                height: parent.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.5; color: U.withAlpha("#ffffff", 0.55) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                                NumberAnimation on x {
                                    running: stepCol.live && root.running
                                    loops: Animation.Infinite
                                    from: -46; to: seg.width
                                    duration: 1300
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                        Row {
                            spacing: 5
                            C.IconGlyph {
                                name: stepCol.done ? "check" : stepCol.modelData.g
                                size: 13
                                glyphColor: stepCol.done ? Theme.secondary_container
                                          : stepCol.live ? Theme.primary : Theme.outline
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: stepCol.modelData.s
                                font.pixelSize: Tokens.fontCaption
                                weight: stepCol.live ? Tokens.weightBold : Tokens.weightMedium
                                color: stepCol.live ? Theme.text_strong
                                     : stepCol.done ? Theme.on_surface_var : Theme.outline
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
