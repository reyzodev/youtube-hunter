import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import NicheScope
import "." as C
import "../Utils.js" as U

// Launch screen: the YouTube Hunter mark assembling itself.
//
// Timeline (~2.3 s, click anywhere to skip):
//   0.00  backdrop + accent bloom fade up, HUD rings start orbiting
//   0.12  neon outline draws itself around every piece of the mark
//   0.65  crown drops in, the two side blades slide in from the edges
//   1.30  play triangle pops (with a light ring burst), outline fades out
//   1.45  wordmark tracks in from wide letter-spacing, light sweeps the logo
//   ...   breathing glow until the app says `ready`, then the mark pushes
//         toward the viewer while the whole cover dissolves into the shell
//
// Everything is tinted from the live Theme accent, so the splash matches the
// colour the user picked in Settings.
Item {
    id: root
    anchors.fill: parent
    z: 5000
    visible: !done

    property bool ready: false
    property bool introDone: false
    property bool done: false
    property real radius: 0
    signal finished()

    property real ambient: 0
    property real wordReveal: 0
    property real orbit: 0
    property real exitT: 0
    property real burst: 0

    opacity: 1 - exitT

    function _maybeExit() {
        if (introDone && ready && !done && !outro.running)
            outro.start()
    }
    onReadyChanged: _maybeExit()

    // swallow input while up: drag moves the frameless window, click skips
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onClicked: (m) => {
            if (!intro.running) return
            intro.stop()
            root.ambient = 1
            mark.assemble = 1
            mark.trace = 1
            mark.traceOpacity = 0
            mark.playPop = 1
            mark.sheen = -1
            root.wordReveal = 1
            root.introDone = true
            root._maybeExit()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.background
        antialiasing: true
    }

    // accent bloom behind the mark
    Shape {
        anchors.fill: parent
        opacity: root.ambient
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: hud.x + hud.width / 2
                centerY: hud.y + hud.height / 2
                centerRadius: Math.min(root.width, root.height) * 0.48
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.13) }
                GradientStop { position: 0.45; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.06 : 0.04) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
            }
            PathPolyline {
                path: [Qt.point(0, 0), Qt.point(root.width, 0),
                       Qt.point(root.width, root.height), Qt.point(0, root.height),
                       Qt.point(0, 0)]
            }
        }
    }

    // ── HUD: target rings around the mark ──
    Item {
        id: hud
        width: 300; height: 300
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -54
        opacity: root.ambient
        scale: (0.86 + 0.14 * root.ambient) * (1 + root.exitT * 0.35)

        // static hairline ring
        Rectangle {
            anchors.centerIn: parent
            width: 268; height: 268; radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.09)
            antialiasing: true
        }

        // orbiting accent arc
        Shape {
            anchors.fill: parent
            rotation: root.orbit
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.primary
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 150; centerY: 150
                    radiusX: 134; radiusY: 134
                    startAngle: -90; sweepAngle: 64
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(Theme.primary, 0.35)
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 150; centerY: 150
                    radiusX: 134; radiusY: 134
                    startAngle: 90; sweepAngle: 22
                }
            }
        }

        // counter-rotating inner arcs
        Shape {
            anchors.fill: parent
            rotation: -root.orbit * 0.65
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.18 : 0.22)
                strokeWidth: 1.2
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 150; centerY: 150
                    radiusX: 118; radiusY: 118
                    startAngle: 20; sweepAngle: 110
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.18 : 0.22)
                strokeWidth: 1.2
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 150; centerY: 150
                    radiusX: 118; radiusY: 118
                    startAngle: 200; sweepAngle: 110
                }
            }
        }

        // reticle ticks (N / E / S / W) — "hunter" crosshair
        Repeater {
            model: 4
            Item {
                anchors.fill: parent
                rotation: index * 90
                Rectangle {
                    width: 2; height: 12; radius: 1
                    x: parent.width / 2 - 1
                    y: 150 - 134 - 6 - (1 - root.ambient) * 18
                    color: U.withAlpha(Theme.primary, 0.75)
                    antialiasing: true
                }
            }
        }

        // ring burst when the play triangle lands
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 4
            width: 120; height: 120; radius: 60
            color: "transparent"
            border.width: 2
            border.color: Qt.lighter(Theme.primary, 1.4)
            antialiasing: true
            scale: 0.35 + root.burst * 1.9
            opacity: root.burst > 0 ? (1 - root.burst) * 0.9 : 0
        }

        C.BrandMark {
            id: mark
            anchors.centerIn: parent
            width: 150; height: 165
            glow: true
            assemble: 0
            trace: 0
            traceOpacity: 0
            playPop: 0
        }
    }

    // ── wordmark ──
    Column {
        id: words
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: hud.bottom
        anchors.topMargin: 6 + (1 - root.wordReveal) * 12
        spacing: 10
        opacity: root.wordReveal * (1 - root.exitT)
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 + (1 - root.wordReveal) * 22
            C.AppText {
                text: "YOUTUBE"
                weight: Tokens.weightBold
                color: Theme.text_strong
                font.pixelSize: 26
                font.letterSpacing: 3 + (1 - root.wordReveal) * 14
            }
            C.AppText {
                text: "HUNTER"
                weight: Tokens.weightBold
                color: Theme.primary
                font.pixelSize: 26
                font.letterSpacing: 3 + (1 - root.wordReveal) * 14
            }
        }

        C.AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("YouTube Research Studio")
            color: Theme.on_surface_var
            font.pixelSize: Tokens.fontCaption
            font.letterSpacing: 1
        }

        Item { width: 1; height: 8 }

        // indeterminate loader line
        Rectangle {
            id: track
            anchors.horizontalCenter: parent.horizontalCenter
            width: 168; height: 2; radius: 1
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.10)
            clip: true
            Rectangle {
                id: chip
                width: 64; height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0) }
                    GradientStop { position: 0.5; color: Theme.primary }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
                }
                NumberAnimation on x {
                    running: root.visible
                    loops: Animation.Infinite
                    from: -chip.width; to: track.width
                    duration: 1100
                    easing.type: Easing.InOutCubic
                }
            }
        }
    }

    C.AppText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        text: "v" + App.version
        color: Theme.on_surface_var
        opacity: 0.45 * root.wordReveal
        font.pixelSize: Tokens.fontCaption
    }

    // ── motion ──
    NumberAnimation on orbit {
        running: root.visible
        loops: Animation.Infinite
        from: 0; to: 360
        duration: 2800
    }

    // breathing halo while waiting for the app
    SequentialAnimation {
        running: root.introDone && !root.done
        loops: Animation.Infinite
        NumberAnimation { target: mark; property: "glowStrength"; to: 0.55; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { target: mark; property: "glowStrength"; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
    }

    SequentialAnimation {
        id: intro
        running: true
        ParallelAnimation {
            NumberAnimation { target: root; property: "ambient"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                ParallelAnimation {
                    NumberAnimation { target: mark; property: "traceOpacity"; from: 0; to: 1; duration: 220 }
                    NumberAnimation { target: mark; property: "trace"; from: 0; to: 1; duration: 950; easing.type: Easing.InOutCubic }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 650 }
                NumberAnimation { target: mark; property: "assemble"; from: 0; to: 1; duration: 900 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 1250 }
                NumberAnimation { target: mark; property: "traceOpacity"; to: 0; duration: 520; easing.type: Easing.OutQuad }
            }
            SequentialAnimation {
                PauseAnimation { duration: 1300 }
                NumberAnimation { target: mark; property: "playPop"; from: 0; to: 1; duration: 520 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 1340 }
                NumberAnimation { target: root; property: "burst"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 1450 }
                NumberAnimation { target: mark; property: "sheen"; from: 0; to: 1; duration: 850; easing.type: Easing.InOutSine }
                PropertyAction { target: mark; property: "sheen"; value: -1 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 1400 }
                NumberAnimation { target: root; property: "wordReveal"; from: 0; to: 1; duration: 850; easing.type: Easing.OutExpo }
            }
        }
        ScriptAction { script: { root.introDone = true; root._maybeExit() } }
    }

    SequentialAnimation {
        id: outro
        PauseAnimation { duration: 120 }
        NumberAnimation { target: root; property: "exitT"; from: 0; to: 1; duration: 560; easing.type: Easing.InOutCubic }
        ScriptAction { script: { root.done = true; root.finished() } }
    }

    // never hold the user hostage if `ready` is never raised
    Timer {
        interval: 7000
        running: !root.done
        onTriggered: root.ready = true
    }
}
