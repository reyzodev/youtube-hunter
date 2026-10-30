import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.2 — "Eclipse" theme transition. The title-bar switch is a sun that
// eclipses into a crescent; the curtain now tells the same story full-screen.
//
//   0.00  curtain (old palette) fades up; the accent SUN rises in the middle
//         inside a slowly turning instrument bezel
//   0.12  the MOON (a disc of the NEW palette) glides in from the side the
//         switch was clicked on, eclipsing the sun
//   0.52  TOTALITY: the corona flares out around the moon, a "diamond ring"
//         sparkle flashes on the sun's last edge, and the brand mark appears
//         on the moon's face with the mode label beneath
//   hold  the corona and bezel keep turning (render thread) while the staged
//         palette swap finishes behind the curtain, capped at _gateCapMs
//   LOCK  the moon IS the iris: it swells to fill the window with the new
//         palette, corona rays fly out, and the overlay melts into the UI
//
// Performance rules carried over from v3.41 (the reason this file is shaped
// the way it is): everything that MOVES is an Animator (Opacity / Scale /
// Rotation / X / Y), so motion runs on the render thread and keeps gliding
// while the GUI thread republishes the palette. All geometry is static —
// circles are only scaled, rays and ticks only rotated. No window snapshot,
// no MultiEffect, no full-window shader, input never blocked.
Item {
    id: root
    anchors.fill: parent
    visible: running || _warming
    enabled: false
    z: 800

    property bool running: false
    property real radius: 12                     // window corner radius (0 when maximized)
    property color oldColor: "#09090B"
    property color newColor: "#F5F5F7"
    property color accent: Theme.primary
    property bool oldDark: true
    property bool newDark: false
    property var _onCovered: null
    property var _onReveal: null
    property var _isReady: null
    property bool _warming: false

    readonly property real _cx: width / 2
    readonly property real _cy: height / 2 - 18
    // The iris stops where it meets the window's rounded corners (the 45°
    // point of each corner arc) instead of the bounding-box corner, so it
    // never paints the transparent pixels OUTSIDE the rounded window.
    readonly property real _cornerInset: Math.min(root.radius, width / 2, height / 2) * (1 - Math.SQRT1_2)
    readonly property real _lensR: {
        const dx = Math.max(_cx, width - _cx) - _cornerInset
        const dy = Math.max(_cy, height - _cy) - _cornerInset
        return Math.max(40, Math.sqrt(dx * dx + dy * dy))
    }
    readonly property color _ink: oldDark ? "#ECECEF" : "#17171B"

    // eclipse geometry
    readonly property real _sunR: 66
    readonly property real _moonR: 68            // a hair bigger: totality is total
    readonly property real _moonScale: _moonR / _lensR
    readonly property real _approach: 190        // how far out the moon starts
    // unit vector from the centre toward the click (set in run())
    property real _dirX: 0.8
    property real _dirY: -0.6

    function _isDarkColor(c) {
        c = Qt.color(c)
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }

    function _lensX(off) { return root._cx - root._lensR + off }
    function _lensY(off) { return root._cy - root._lensR + off }

    // Put every animated piece back at its "before the run" value. Animators
    // only write their final value back to the GUI side when they finish, so
    // the reset must be explicit and happen BEFORE any animator starts.
    function _reset() {
        curtain.opacity = 0
        stage.opacity = 1
        bloom.opacity = 0; bloom.scale = 0.8
        bezel.opacity = 0; bezel.scale = 0.9; bezel.rotation = 0
        sun.opacity = 0; sun.scale = 0.55
        sunGlow.opacity = 0; sunGlow.scale = 0.6
        lens.opacity = 0
        lens.scale = root._moonScale
        lens.x = root._lensX(root._dirX * root._approach)
        lens.y = root._lensY(root._dirY * root._approach)
        corona.opacity = 0; corona.scale = 0.7; corona.rotation = 0
        rim.opacity = 0; rim.scale = 0.96
        bead.opacity = 0; bead.scale = 0.3
        bead.x = root._cx - root._dirX * root._sunR - bead.width / 2
        bead.y = root._cy - root._dirY * root._sunR - bead.height / 2
        mark.opacity = 0; mark.scale = 0.6
        label.opacity = 0; label.y = root._cy + 168
    }

    // Render every piece once, invisibly, so the first real switch does not
    // pay for CurveRenderer shader setup / first-use node creation.
    function warmUp() {
        if (root.running) return
        root._warming = true
        root.opacity = 0.004
        curtain.opacity = 1; bloom.opacity = 1; bezel.opacity = 1; sun.opacity = 1
        sunGlow.opacity = 1; lens.opacity = 1; lens.scale = 0.5; corona.opacity = 1
        rim.opacity = 1; bead.opacity = 1; mark.opacity = 1; label.opacity = 1
        warmTimer.restart()
    }
    Timer {
        id: warmTimer
        interval: 80
        onTriggered: { root._warming = false; root._reset(); root.opacity = 1 }
    }

    // `onReveal` (optional) runs right before the iris opens: Main.qml uses it
    // to finish the staged palette swap so the reveal is never early.
    // `isReady` (optional) is polled before the iris opens; the reveal waits
    // (up to _gateCapMs) until it returns true.
    function run(cx, cy, targetColor, onCovered, onReveal, isReady) {
        if (root.running) return
        gate.stop(); revealAnim.stop(); intro.stop(); spin.stop(); coronaSpin.stop()
        warmTimer.stop(); root._warming = false; root.opacity = 1
        root.oldColor = Theme.background         // resolve BEFORE the swap
        root.newColor = targetColor
        root.oldDark = Theme.isDark
        root.newDark = _isDarkColor(targetColor)
        root.accent = Theme.primary
        root._onCovered = onCovered
        root._onReveal = onReveal || null
        root._isReady = isReady || null
        // the moon arrives from the side the switch was clicked on
        let dx = (cx === undefined ? root.width : cx) - root._cx
        let dy = (cy === undefined ? 0 : cy) - root._cy
        const len = Math.sqrt(dx * dx + dy * dy)
        if (len < 1) { dx = 0.8; dy = -0.6 } else { dx /= len; dy /= len }
        root._dirX = dx
        root._dirY = dy
        root._reset()
        root.running = true
        intro.restart()
        spin.restart()
    }

    Item {
        id: stage
        anchors.fill: parent

        // ── curtain: the OLD palette, a plain rounded rect (static geometry) ──
        Rectangle {
            id: curtain
            anchors.fill: parent
            radius: root.radius
            color: root.oldColor
            opacity: 0
            antialiasing: true
        }

        // ── accent bloom ──
        Shape {
            id: bloom
            width: 700; height: 700
            x: root._cx - width / 2; y: root._cy - height / 2
            opacity: 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: 350; centerY: 350; centerRadius: 350
                    focalX: 350; focalY: 350
                    GradientStop { position: 0.0;  color: U.withAlpha(root.accent, root.oldDark ? 0.24 : 0.15) }
                    GradientStop { position: 0.32; color: U.withAlpha(root.accent, root.oldDark ? 0.08 : 0.05) }
                    GradientStop { position: 1.0;  color: U.withAlpha(root.accent, 0) }
                }
                PathPolyline { path: [Qt.point(0, 0), Qt.point(700, 0), Qt.point(700, 700), Qt.point(0, 700), Qt.point(0, 0)] }
            }
        }

        // ── instrument bezel: 72 ticks + a hairline, only rotated ──
        Item {
            id: bezel
            width: 300; height: 300
            x: root._cx - 150; y: root._cy - 150
            opacity: 0
            Rectangle {
                anchors.centerIn: parent
                width: 252; height: 252; radius: 126
                color: "transparent"
                border.width: 1
                border.color: U.withAlpha(root._ink, root.oldDark ? 0.08 : 0.10)
                antialiasing: true
            }
            Repeater {
                model: 72
                delegate: Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 5
                    Rectangle {
                        readonly property bool major: parent.index % 6 === 0
                        x: 150 - width / 2
                        y: 150 - 142
                        width: major ? 1.5 : 1
                        height: parent.index % 18 === 0 ? 12 : major ? 8 : 4
                        color: parent.index % 18 === 0 ? root.accent : root._ink
                        opacity: parent.index % 18 === 0 ? 0.9 : major ? 0.28 : 0.14
                        antialiasing: true
                    }
                }
            }
            // two accent arcs riding the hairline
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.accent
                    strokeWidth: 2
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 150; centerY: 150; radiusX: 126; radiusY: 126; startAngle: -90; sweepAngle: 52 }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: U.withAlpha(root.accent, 0.35)
                    strokeWidth: 2
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 150; centerY: 150; radiusX: 126; radiusY: 126; startAngle: 100; sweepAngle: 22 }
                }
            }
        }

        // ── corona: 48 rays of uneven length around the moon ──
        Item {
            id: corona
            width: 420; height: 420
            x: root._cx - 210; y: root._cy - 210
            opacity: 0
            Repeater {
                model: 48
                delegate: Item {
                    required property int index
                    // stable pseudo-random length and tilt per ray
                    readonly property real n: ((index * 7919) % 97) / 97
                    anchors.fill: parent
                    rotation: index * 7.5 + (n - 0.5) * 3
                    Rectangle {
                        x: 210 + root._moonR + 4
                        y: 210 - height / 2
                        width: 14 + 62 * parent.n * parent.n + (parent.index % 4 === 0 ? 26 : 0)
                        height: parent.index % 4 === 0 ? 2 : 1.2
                        radius: height / 2
                        antialiasing: true
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: U.withAlpha(root.accent, 0.9) }
                            GradientStop { position: 1.0; color: U.withAlpha(root.accent, 0.0) }
                        }
                    }
                }
            }
        }

        // ── the sun ──
        Shape {
            id: sunGlow
            width: 320; height: 320
            x: root._cx - 160; y: root._cy - 160
            opacity: 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: 160; centerY: 160; centerRadius: 160
                    focalX: 160; focalY: 160
                    GradientStop { position: 0.0;  color: U.withAlpha(root.accent, 0.55) }
                    GradientStop { position: 0.42; color: U.withAlpha(root.accent, 0.22) }
                    GradientStop { position: 1.0;  color: U.withAlpha(root.accent, 0) }
                }
                PathAngleArc { centerX: 160; centerY: 160; radiusX: 160; radiusY: 160; startAngle: 0; sweepAngle: 360 }
            }
        }
        Rectangle {
            id: sun
            width: root._sunR * 2; height: width; radius: width / 2
            x: root._cx - root._sunR; y: root._cy - root._sunR
            opacity: 0
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.35) }
                GradientStop { position: 0.55; color: root.accent }
                GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.35) }
            }
        }

        // ── the moon: a disc of the NEW palette, and later the iris ──
        // A fixed-size circle (radius = _lensR) that is only ever moved and
        // scaled, so both the transit and the reveal are transform updates.
        Item {
            id: lens
            width: root._lensR * 2
            height: width
            transformOrigin: Item.Center
            opacity: 0

            // thin accent rim riding the edge (a slightly larger disc behind)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: U.withAlpha(root.accent, 0.55)
                    strokeColor: "transparent"
                    strokeWidth: -1
                    startX: root._lensR * 2 + 5; startY: root._lensR
                    PathArc { x: -5; y: root._lensR; radiusX: root._lensR + 5; radiusY: root._lensR + 5 }
                    PathArc { x: root._lensR * 2 + 5; y: root._lensR; radiusX: root._lensR + 5; radiusY: root._lensR + 5 }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: root.newColor
                    strokeColor: "transparent"
                    strokeWidth: -1
                    startX: root._lensR * 2; startY: root._lensR
                    PathArc { x: 0; y: root._lensR; radiusX: root._lensR; radiusY: root._lensR }
                    PathArc { x: root._lensR * 2; y: root._lensR; radiusX: root._lensR; radiusY: root._lensR }
                }
            }
        }

        // totality rim: the bright ring the sun leaves around the moon
        Rectangle {
            id: rim
            width: root._moonR * 2 + 6; height: width; radius: width / 2
            x: root._cx - width / 2; y: root._cy - height / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.lighter(root.accent, 1.2)
            opacity: 0
            antialiasing: true
        }

        // "diamond ring": the last sliver of sun, as a sparkle
        Item {
            id: bead
            width: 90; height: 90
            opacity: 0
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"; strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: 45; centerY: 45; centerRadius: 45
                        focalX: 45; focalY: 45
                        GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.95) }
                        GradientStop { position: 0.12; color: U.withAlpha(Qt.lighter(root.accent, 1.3), 0.85) }
                        GradientStop { position: 0.45; color: U.withAlpha(root.accent, 0.25) }
                        GradientStop { position: 1.0;  color: U.withAlpha(root.accent, 0) }
                    }
                    PathAngleArc { centerX: 45; centerY: 45; radiusX: 45; radiusY: 45; startAngle: 0; sweepAngle: 360 }
                }
            }
            // lens flare cross
            Rectangle {
                anchors.centerIn: parent
                width: 90; height: 1.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.95) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 1.5; height: 56
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.85) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
        }

        // ── the mark, on the moon's face ──
        C.BrandMark {
            id: mark
            width: 62
            height: Math.round(62 * 812 / 738)
            x: root._cx - width / 2
            y: root._cy - height / 2 + 3
            rim: true
            opacity: 0
            scale: 0.6
        }

        // ── mode label (target palette) ──
        C.AppText {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            mono: I18n.lang !== "fa"
            text: root.newDark ? I18n.tr("Dark mode") : I18n.tr("Light mode")
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontCaption
            font.capitalization: I18n.lang === "fa" ? Font.MixedCase : Font.AllUppercase
            // tracking only for Latin: letter-spacing breaks Persian joining
            font.letterSpacing: I18n.lang === "fa" ? 0 : 4
            color: U.withAlpha(root._ink, 0.7)
            opacity: 0
        }
    }

    // ── continuous motion while we hold (render thread) ──
    RotationAnimator {
        id: spin
        target: bezel
        from: 0; to: 360
        duration: 14000
        loops: Animation.Infinite
    }
    RotationAnimator {
        id: coronaSpin
        target: corona
        from: 0; to: -360
        duration: 22000
        loops: Animation.Infinite
    }

    // ── intro (all animators, started together: no GUI-timed pauses) ──
    ParallelAnimation {
        id: intro

        SequentialAnimation {
            OpacityAnimator { target: curtain; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
            ScriptAction { script: { if (root._onCovered) root._onCovered(); root._onCovered = null } }
        }
        OpacityAnimator { target: bloom; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: bloom; from: 0.8; to: 1; duration: 700; easing.type: Easing.OutCubic }
        OpacityAnimator { target: bezel; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: bezel; from: 0.9; to: 1; duration: 560; easing.type: Easing.OutCubic }

        // sunrise
        OpacityAnimator { target: sun; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: sun; from: 0.55; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
        OpacityAnimator { target: sunGlow; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: sunGlow; from: 0.6; to: 1; duration: 520; easing.type: Easing.OutCubic }

        // transit: the new palette's moon glides over the sun
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                OpacityAnimator { target: lens; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
                XAnimator { target: lens; from: root._lensX(root._dirX * root._approach); to: root._lensX(0); duration: 400; easing.type: Easing.OutCubic }
                YAnimator { target: lens; from: root._lensY(root._dirY * root._approach); to: root._lensY(0); duration: 400; easing.type: Easing.OutCubic }
            }
        }

        // totality
        SequentialAnimation {
            PauseAnimation { duration: 470 }
            ParallelAnimation {
                OpacityAnimator { target: corona; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                ScaleAnimator   { target: corona; from: 0.7; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                OpacityAnimator { target: rim; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                ScaleAnimator   { target: rim; from: 0.96; to: 1; duration: 300; easing.type: Easing.OutCubic }
                OpacityAnimator { target: sunGlow; from: 1; to: 0.55; duration: 300; easing.type: Easing.OutCubic }
                OpacityAnimator { target: mark; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
                ScaleAnimator   { target: mark; from: 0.6; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
                OpacityAnimator { target: label; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
                YAnimator       { target: label; from: root._cy + 168; to: root._cy + 156; duration: 460; easing.type: Easing.OutCubic }
                ScriptAction    { script: coronaSpin.restart() }
                SequentialAnimation {
                    ParallelAnimation {
                        OpacityAnimator { target: bead; from: 0; to: 1; duration: 110; easing.type: Easing.OutCubic }
                        ScaleAnimator   { target: bead; from: 0.3; to: 1.15; duration: 200; easing.type: Easing.OutCubic }
                    }
                    ParallelAnimation {
                        OpacityAnimator { target: bead; from: 1; to: 0; duration: 420; easing.type: Easing.InQuad }
                        ScaleAnimator   { target: bead; from: 1.15; to: 0.7; duration: 420; easing.type: Easing.InCubic }
                    }
                }
            }
        }

        // the earliest the reveal may start; it still waits for the swap
        SequentialAnimation {
            PauseAnimation { duration: 640 }
            ScriptAction { script: root._armReveal() }
        }
    }

    // ── reveal gate ──
    // Hold the iris until the staged palette swap is done (polled), never
    // longer than the cap. While we hold, only render-thread rotation moves,
    // so a busy GUI thread is invisible.
    readonly property int _gateCapMs: 900
    property double _gateStart: 0
    function _armReveal() {
        if (root._isReady && !root._isReady()) {
            root._gateStart = Date.now()
            gate.start()
            return
        }
        root._openIris()
    }
    function _openIris() {
        gate.stop()
        if (root._onReveal) root._onReveal()
        root._onReveal = null
        revealAnim.restart()
    }
    Timer {
        id: gate
        interval: 16
        repeat: true
        onTriggered: {
            // wall-clock, not tick-counting: a blocked GUI thread delivers
            // fewer ticks, which used to stretch the cap well past 900 ms
            if (!root._isReady || root._isReady() || Date.now() - root._gateStart >= root._gateCapMs)
                root._openIris()
        }
    }

    SequentialAnimation {
        id: revealAnim
        ParallelAnimation {
            // corona and bezel fly outward and go
            ScaleAnimator   { target: corona; from: 1; to: 2.2; duration: 520; easing.type: Easing.InCubic }
            OpacityAnimator { target: corona; from: 1; to: 0; duration: 420; easing.type: Easing.OutQuad }
            ScaleAnimator   { target: bezel; from: 1; to: 1.7; duration: 440; easing.type: Easing.InCubic }
            OpacityAnimator { target: bezel; from: 1; to: 0; duration: 320; easing.type: Easing.OutQuad }
            OpacityAnimator { target: rim; from: 1; to: 0; duration: 240; easing.type: Easing.OutQuad }
            OpacityAnimator { target: sun; from: 1; to: 0; duration: 260; easing.type: Easing.OutQuad }
            OpacityAnimator { target: sunGlow; from: 0.55; to: 0; duration: 260; easing.type: Easing.OutQuad }
            OpacityAnimator { target: bloom; from: 1; to: 0; duration: 360; easing.type: Easing.OutQuad }
            OpacityAnimator { target: label; from: 1; to: 0; duration: 200; easing.type: Easing.OutQuad }
            // the mark pushes toward the viewer and goes
            ScaleAnimator   { target: mark; from: 1; to: 1.35; duration: 380; easing.type: Easing.InCubic }
            OpacityAnimator { target: mark; from: 1; to: 0; duration: 320; easing.type: Easing.InQuad }
            // the moon swells into the new palette
            ScaleAnimator   { target: lens; from: root._moonScale; to: 1; duration: 580; easing.type: Easing.InOutQuart }
            // ...and the whole overlay melts into the live UI as it lands
            SequentialAnimation {
                PauseAnimation { duration: 270 }
                OpacityAnimator { target: stage; from: 1; to: 0; duration: 340; easing.type: Easing.OutCubic }
            }
        }
        ScriptAction {
            script: {
                spin.stop()
                coronaSpin.stop()
                root.running = false
                root._reset()
            }
        }
    }
}
