import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// ═══════════════════════════════════════════════════════════════════════
//  DonateLoader — "Heartline", the Support window's loading stage
// ═══════════════════════════════════════════════════════════════════════
//
// Replaces the old 3 px indeterminate bar. The subject is support, so the
// stage beats like a heart instead of spinning like a generic loader:
//
//   * the brand mark assembles itself once (outline traces on, blades slide
//     in, play pops), then breathes on a real "lub-dub" rhythm — two pulses,
//     a rest — and every beat throws an echo ring outward.
//   * a ring around the mark is the HONEST progress: it fills with the web
//     view's real loadProgress. Real progress tends to sit at 10 % and then
//     jump to 100 %, so a trickle creeps the ring toward 88 % meanwhile —
//     it never looks frozen, and it never claims "done" before the page is.
//   * a comet orbits the ring on the render thread (RotationAnimator), so it
//     stays smooth even while Chromium is busy spinning up its processes.
//   * two accent glows drift behind everything: ambient, felt more than seen.
//   * the status line changes with the stage of the load (reaching host →
//     securing → almost there), not on a fake timer.
//
// When the parent fades the veil out, `leaving` lets the mark bloom forward a
// touch, so the hand-off to the painted page reads as a reveal, not a cut.
//
// Usage:
//   C.DonateLoader { anchors.fill: parent; progress: web.loadProgress
//                    host: "example.com"; running: veil.visible }
Item {
    id: root

    // 0..100 — the web view's real load progress
    property real progress: 0
    // shown in the first status line ("Reaching example.com…")
    property string host: ""
    // pause every animation when the stage is not on screen
    property bool running: visible
    // set by the parent while the veil is fading out
    property bool leaving: false

    readonly property color _accent: Theme.primary
    readonly property color _hot: U.mix(Theme.primary, "#FF6FA5", 0.5)
    readonly property color _base: Theme.isDark ? "#0E0E11" : "#FFFFFF"

    // ── progress: real value, smoothed, with an honest trickle ─────────
    property real _trickle: 0
    property bool _smooth: true
    readonly property real _target: Math.max(progress, _trickle)
    property real shown: 0
    on_TargetChanged: {
        // a fresh load (progress back to 0) snaps to the start; anything
        // else only ever moves forward
        if (progress <= 0 && _trickle <= 0) {
            _smooth = false
            shown = 0
            _smooth = true
        } else if (_target > shown) {
            shown = _target
        }
    }
    Behavior on shown {
        enabled: root._smooth
        NumberAnimation { duration: 620; easing.type: Easing.OutCubic }
    }

    onProgressChanged: {
        if (progress <= 0) { _trickle = 0; trickleTimer.restart() }
    }
    Timer {
        id: trickleTimer
        interval: 140
        repeat: true
        running: root.running && root.progress < 100
        onTriggered: {
            // ease toward 88 %: fast at first, slower the closer it gets
            var ceiling = 88
            var floor = Math.max(root._trickle, root.progress)
            root._trickle = Math.min(ceiling, floor + (ceiling - floor) * 0.035 + 0.15)
        }
    }

    readonly property string _status: {
        if (shown < 30) return host ? I18n.tr("Reaching %1…").arg(host) : I18n.tr("Reaching the page…")
        if (shown < 75) return I18n.tr("Securing the connection…")
        return I18n.tr("Almost there…")
    }

    // ── base + ambient drift ────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root._base
    }

    Item {
        id: ambient
        anchors.fill: parent
        clip: true

        C.GlowBlob {
            id: blobA
            size: Math.min(ambient.width, ambient.height) * 0.62
            glow: root._accent
            strength: Theme.isDark ? 0.15 : 0.09
            x: ambient.width * 0.5 - width * 0.5 + driftA.dx
            y: ambient.height * 0.5 - height * 0.62 + driftA.dy
            QtObject {
                id: driftA
                property real t: 0
                readonly property real dx: Math.sin(t * Math.PI * 2) * ambient.width * 0.10
                readonly property real dy: Math.cos(t * Math.PI * 2) * ambient.height * 0.06
            }
            NumberAnimation {
                target: driftA; property: "t"; from: 0; to: 1
                duration: 14000; loops: Animation.Infinite; running: root.running
            }
        }
        C.GlowBlob {
            size: Math.min(ambient.width, ambient.height) * 0.5
            glow: root._hot
            strength: Theme.isDark ? 0.12 : 0.07
            x: ambient.width * 0.5 - width * 0.5 + driftB.dx
            y: ambient.height * 0.5 - height * 0.30 + driftB.dy
            QtObject {
                id: driftB
                property real t: 0
                readonly property real dx: Math.cos(t * Math.PI * 2) * ambient.width * 0.12
                readonly property real dy: Math.sin(t * Math.PI * 2) * ambient.height * 0.07
            }
            NumberAnimation {
                target: driftB; property: "t"; from: 0; to: 1
                duration: 19000; loops: Animation.Infinite; running: root.running
            }
        }
    }

    // ── the stage ───────────────────────────────────────────────────────
    ColumnLayout {
        id: column
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -12
        spacing: 0
        width: Math.min(360, parent.width - 64)
        opacity: root.leaving ? 0 : 1
        scale: root.leaving ? 1.06 : 1
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        Item {
            id: stage
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 188
            Layout.preferredHeight: 188

            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real ringR: 62

            // heartbeat state: 0 = rest, peaks at 1 on "lub", 0.6 on "dub"
            property real beat: 0

            // echo rings — one per beat, swelling out past the ring and fading
            Repeater {
                model: 2
                delegate: Rectangle {
                    id: echo
                    required property int index
                    property real k: 0
                    anchors.centerIn: parent
                    width: stage.ringR * 2
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: index === 0 ? root._accent : root._hot
                    antialiasing: true
                    scale: 1 + 0.55 * k
                    opacity: k > 0 ? (1 - k) * (index === 0 ? 0.55 : 0.38) : 0

                    SequentialAnimation {
                        running: root.running
                        loops: Animation.Infinite
                        PauseAnimation { duration: echo.index === 0 ? 0 : 190 }
                        NumberAnimation {
                            target: echo; property: "k"; from: 0; to: 1
                            duration: 1100; easing.type: Easing.OutCubic
                        }
                        PropertyAction { target: echo; property: "k"; value: 0 }
                        PauseAnimation { duration: echo.index === 0 ? 300 : 110 }
                    }
                }
            }

            // the lub-dub that drives the mark (same 1.4 s cycle as the echoes)
            SequentialAnimation {
                running: root.running
                loops: Animation.Infinite
                NumberAnimation { target: stage; property: "beat"; to: 1.0; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: stage; property: "beat"; to: 0.15; duration: 120; easing.type: Easing.InQuad }
                NumberAnimation { target: stage; property: "beat"; to: 0.6; duration: 100; easing.type: Easing.OutQuad }
                NumberAnimation { target: stage; property: "beat"; to: 0.0; duration: 260; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 810 }
            }

            // track + real progress
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.07)
                    strokeWidth: 3
                    PathAngleArc {
                        centerX: stage.cx; centerY: stage.cy
                        radiusX: stage.ringR; radiusY: stage.ringR
                        startAngle: 0; sweepAngle: 360
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root._accent
                    strokeWidth: 3
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: stage.cx; centerY: stage.cy
                        radiusX: stage.ringR; radiusY: stage.ringR
                        startAngle: -90
                        sweepAngle: Math.max(0.5, 3.6 * Math.min(100, root.shown))
                    }
                }
            }

            // comet: a fading tail built from three arcs + a glowing head,
            // rotated on the render thread
            Item {
                id: comet
                anchors.fill: parent
                readonly property real r: stage.ringR + 11

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: U.withAlpha(root._hot, 0.10)
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: comet.r; radiusY: comet.r; startAngle: -200; sweepAngle: 110 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: U.withAlpha(root._hot, 0.30)
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: comet.r; radiusY: comet.r; startAngle: -150; sweepAngle: 60 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: U.withAlpha(root._hot, 0.85)
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: stage.cx; centerY: stage.cy; radiusX: comet.r; radiusY: comet.r; startAngle: -115; sweepAngle: 25 }
                    }
                }
                // head sits at -90° (top) — where the brightest arc ends
                Rectangle {
                    width: 14; height: 14; radius: 7
                    x: stage.cx - width / 2
                    y: stage.cy - comet.r - height / 2
                    color: U.withAlpha(root._hot, 0.22)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6; height: 6; radius: 3
                        color: "#FFFFFF"
                        border.width: 1.5
                        border.color: root._hot
                    }
                }

                RotationAnimator on rotation {
                    from: 0; to: 360
                    duration: 1800
                    loops: Animation.Infinite
                    running: root.running
                }
            }

            // the mark itself: assembles once, then beats
            C.BrandMark {
                id: mark
                anchors.centerIn: parent
                width: 52
                height: 57
                glow: true
                glowStrength: 0.45 + 0.55 * stage.beat
                scale: 1 + 0.07 * stage.beat
                assemble: 0
                trace: 0
                traceOpacity: 0
                playPop: 0
            }

            SequentialAnimation {
                id: assembleAnim
                running: false
                ParallelAnimation {
                    SequentialAnimation {
                        NumberAnimation { target: mark; property: "traceOpacity"; from: 0; to: 1; duration: 160 }
                        NumberAnimation { target: mark; property: "trace"; from: 0; to: 1; duration: 620; easing.type: Easing.InOutCubic }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 180 }
                        NumberAnimation { target: mark; property: "assemble"; from: 0; to: 1; duration: 640 }
                    }
                }
                ParallelAnimation {
                    NumberAnimation { target: mark; property: "traceOpacity"; to: 0; duration: 380; easing.type: Easing.OutQuad }
                    NumberAnimation { target: mark; property: "playPop"; from: 0; to: 1; duration: 420 }
                }
                NumberAnimation { target: mark; property: "sheen"; from: 0; to: 1; duration: 760; easing.type: Easing.InOutSine }
                PropertyAction { target: mark; property: "sheen"; value: -1 }
            }
            // a light sweep across the mark every few seconds while it waits
            Timer {
                interval: 3200
                repeat: true
                running: root.running && !assembleAnim.running
                onTriggered: sheenAnim.restart()
            }
            SequentialAnimation {
                id: sheenAnim
                NumberAnimation { target: mark; property: "sheen"; from: 0; to: 1; duration: 760; easing.type: Easing.InOutSine }
                PropertyAction { target: mark; property: "sheen"; value: -1 }
            }
        }

        C.AppText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space4
            text: I18n.tr("Opening the donation page")
            font.pixelSize: Tokens.fontLabel
            weight: Tokens.weightDemiBold
            color: Theme.text_strong
            horizontalAlignment: Text.AlignHCenter
        }

        // status line: cross-fades when the stage of the load changes
        Item {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space1
            Layout.preferredHeight: 20

            C.AppText {
                id: statusText
                anchors.fill: parent
                text: root._status
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { target: statusText; property: "opacity"; to: 0; duration: 140 }
                        PropertyAction { }
                        NumberAnimation { target: statusText; property: "opacity"; to: 1; duration: 220 }
                    }
                }
            }
        }

        C.AppText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space2
            text: Math.round(Math.min(100, root.shown)) + "%"
            mono: true
            font.pixelSize: Tokens.fontMicro
            color: U.withAlpha(Theme.on_surface_var, 0.75)
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // replay the assembly every time the stage comes back on screen
    onRunningChanged: if (running) _replay()
    Component.onCompleted: if (running) _replay()
    function _replay() {
        // a fresh stage: empty ring, trickle from zero
        _trickle = 0
        _smooth = false
        shown = Math.max(0, progress)
        _smooth = true
        assembleAnim.stop()
        mark.assemble = 0
        mark.trace = 0
        mark.traceOpacity = 0
        mark.playPop = 0
        mark.sheen = -1
        assembleAnim.start()
    }
}
