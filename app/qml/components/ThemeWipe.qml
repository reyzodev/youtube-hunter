import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.41 — "Lock-on" theme transition, rebuilt on the RENDER THREAD.
//
// Why it still hitched in v3.39.x / v3.40.x
// -----------------------------------------
// Every moving part of the old curtain (cover, ambient, lock, orbit, the
// mark's assemble/trace/sheen, the iris radius) was a plain NumberAnimation on
// a custom property. Those tick on the GUI thread, and the GUI thread is the
// exact thread the palette swap keeps busy: each staged slice re-evaluates
// thousands of colour bindings and recolours every visible icon. One heavy key
// (Theme.text, Theme.border…) can hold the GUI thread far longer than the 5 ms
// slice budget, and every such stall froze the orbit, the brackets and the
// iris mid-flight: the ~0.3 s "micro lag" on every switch. The iris itself was
// also a CurveRenderer path rebuilt on the GUI thread every frame.
//
// What changed
// ------------
// Everything that MOVES is now an Animator (Opacity/Scale/Rotation/X/Y).
// Animators run on Qt Quick's render thread (the default threaded render loop
// on Windows/D3D11), so they keep gliding at full frame rate even while the
// GUI thread is busy republishing the palette behind the curtain. All the
// geometry is static: the curtain is a plain rounded Rectangle, the iris is a
// fixed CurveRenderer circle that is only SCALED, the orbit arcs are only
// ROTATED. Nothing re-tessellates per frame.
//
//   0.00  curtain (old palette) fades up, mark pops in, brackets snap on,
//         orbit starts spinning: all render-thread animators
//   0.15  curtain opaque → onCovered() starts the staged palette swap
//   ≥0.48 reveal is armed; it waits (orbit still spinning, smoothly) until the
//         swap reports done, capped at _gateCapMs
//   LOCK  burst ring + brackets fly out, the new-palette lens irises open
//         from the mark, then the whole overlay melts into the live UI
//
// Same rules as before: no window snapshot, no MultiEffect, no full-window
// shader, input never blocked (enabled: false).
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

    // bracket geometry: distance of each viewfinder corner from the mark centre
    readonly property real _bWide: 128
    readonly property real _bTight: 74
    readonly property real _bOut: 260

    function _isDarkColor(c) {
        c = Qt.color(c)
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }

    // Put every animated piece back at its "before the run" value. Animators
    // only write their final value back to the GUI side when they finish, so
    // the reset must be explicit and happen BEFORE any animator starts.
    function _reset() {
        curtain.opacity = 0
        stage.opacity = 1
        lens.scale = 0.002
        bloom.opacity = 0; bloom.scale = 0.85
        hud.opacity = 0; hud.scale = 0.92
        arcs.rotation = -40
        burst.opacity = 0; burst.scale = 0.6
        mark.opacity = 0; mark.scale = 0.72
        label.opacity = 0; label.y = root._cy + 116
        for (let i = 0; i < brackets.count; i++) {
            const b = brackets.itemAt(i)
            if (!b) continue
            b.opacity = 0
            b.x = b.posX(root._bWide)
            b.y = b.posY(root._bWide)
        }
    }

    // Render every piece once, invisibly, so the first real switch does not
    // pay for CurveRenderer shader setup / first-use node creation.
    function warmUp() {
        if (root.running) return
        root._warming = true
        root.opacity = 0.004
        curtain.opacity = 1; lens.scale = 0.5; bloom.opacity = 1; hud.opacity = 1
        burst.opacity = 1; mark.opacity = 1; label.opacity = 1
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
        gate.stop(); revealAnim.stop(); intro.stop(); spin.stop()
        warmTimer.stop(); root._warming = false; root.opacity = 1
        root.oldColor = Theme.background         // resolve BEFORE the swap
        root.newColor = targetColor
        root.oldDark = Theme.isDark
        root.newDark = _isDarkColor(targetColor)
        root.accent = Theme.primary
        root._onCovered = onCovered
        root._onReveal = onReveal || null
        root._isReady = isReady || null
        root._reset()
        root.running = true
        intro.restart()
        spin.restart()
    }

    // Everything that fades out together at the very end (curtain + lens).
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

        // ── lens: the NEW palette irising open from the mark ──
        // A fixed-size circle (radius = _lensR) that is only ever scaled, so
        // the growth is a single transform update on the render thread.
        Item {
            id: lens
            width: root._lensR * 2
            height: width
            x: root._cx - width / 2
            y: root._cy - height / 2
            transformOrigin: Item.Center
            scale: 0.002

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
    }

    // ── accent bloom behind the mark ──
    Shape {
        id: bloom
        width: 620; height: 620
        x: root._cx - width / 2; y: root._cy - height / 2
        opacity: 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"; strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: 310; centerY: 310; centerRadius: 310
                focalX: 310; focalY: 310
                GradientStop { position: 0.0;  color: U.withAlpha(root.accent, root.oldDark ? 0.26 : 0.16) }
                GradientStop { position: 0.38; color: U.withAlpha(root.accent, root.oldDark ? 0.07 : 0.05) }
                GradientStop { position: 1.0;  color: U.withAlpha(root.accent, 0) }
            }
            PathPolyline { path: [Qt.point(0, 0), Qt.point(620, 0), Qt.point(620, 620), Qt.point(0, 620), Qt.point(0, 0)] }
        }
    }

    // ── HUD: hairline ring + orbiting arcs (static paths, only rotated) ──
    Item {
        id: hud
        width: 220; height: 220
        x: root._cx - width / 2; y: root._cy - height / 2
        opacity: 0
        Rectangle {
            anchors.centerIn: parent
            width: 196; height: 196; radius: 98
            color: "transparent"
            border.width: 1
            border.color: U.withAlpha(root._ink, root.oldDark ? 0.08 : 0.10)
            antialiasing: true
        }
        Shape {
            id: arcs
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.accent
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 110; centerY: 110; radiusX: 98; radiusY: 98; startAngle: -90; sweepAngle: 64 }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: U.withAlpha(root.accent, 0.35)
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 110; centerY: 110; radiusX: 98; radiusY: 98; startAngle: 90; sweepAngle: 28 }
            }
        }
    }

    // ── lock burst ring ──
    Rectangle {
        id: burst
        width: 120; height: 120; radius: 60
        x: root._cx - 60; y: root._cy - 60
        color: "transparent"
        border.width: 1.5
        border.color: root.accent
        antialiasing: true
        opacity: 0
    }

    // ── viewfinder brackets: the "hunter" lock-on ──
    Repeater {
        id: brackets
        model: [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        delegate: Item {
            id: br
            required property var modelData
            readonly property real sx: modelData[0]
            readonly property real sy: modelData[1]
            function posX(d) { return root._cx + sx * d - (sx < 0 ? 0 : width) }
            function posY(d) { return root._cy + sy * d - (sy < 0 ? 0 : height) }
            width: 18; height: 18
            opacity: 0
            Rectangle { // horizontal arm
                width: 18; height: 2; radius: 1
                y: br.sy < 0 ? 0 : 16
                color: root.accent
                antialiasing: true
            }
            Rectangle { // vertical arm
                width: 2; height: 18; radius: 1
                x: br.sx < 0 ? 0 : 16
                color: root.accent
                antialiasing: true
            }
            // per-bracket animators, driven by intro / revealAnim below
            function play(which) {
                snapIn.stop(); flyOut.stop()
                if (which === "in") snapIn.restart(); else flyOut.restart()
            }
            ParallelAnimation {
                id: snapIn
                XAnimator { target: br; from: br.posX(root._bWide); to: br.posX(root._bTight); duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.9 }
                YAnimator { target: br; from: br.posY(root._bWide); to: br.posY(root._bTight); duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.9 }
                OpacityAnimator { target: br; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
            }
            ParallelAnimation {
                id: flyOut
                XAnimator { target: br; from: br.posX(root._bTight); to: br.posX(root._bOut); duration: 380; easing.type: Easing.InCubic }
                YAnimator { target: br; from: br.posY(root._bTight); to: br.posY(root._bOut); duration: 380; easing.type: Easing.InCubic }
                OpacityAnimator { target: br; from: 1; to: 0; duration: 340; easing.type: Easing.InQuad }
            }
        }
    }
    function _bracketsRun(which) {
        for (let i = 0; i < brackets.count; i++) {
            const b = brackets.itemAt(i)
            if (!b) continue
            b.play(which)
        }
    }

    // ── the mark (resting pose: assembled, no trace; only scaled / faded) ──
    C.BrandMark {
        id: mark
        width: 92
        height: Math.round(92 * 812 / 738)
        x: root._cx - width / 2
        y: root._cy - height / 2 + 4
        rim: true
        opacity: 0
        scale: 0.72
    }

    // ── mode label (target palette) ──
    C.AppText {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        y: root._cy + 116
        mono: I18n.lang !== "fa"
        text: root.newDark ? I18n.tr("Dark mode") : I18n.tr("Light mode")
        font.pixelSize: Tokens.fontCaption
        font.capitalization: I18n.lang === "fa" ? Font.MixedCase : Font.AllUppercase
        // tracking only for Latin: letter-spacing breaks Persian joining
        font.letterSpacing: I18n.lang === "fa" ? 0 : 2
        color: U.withAlpha(root._ink, 0.62)
        opacity: 0
    }

    // ── continuous orbit: the one thing that keeps moving while we hold ──
    RotationAnimator {
        id: spin
        target: arcs
        from: -40; to: 320
        duration: 1500
        loops: Animation.Infinite
    }

    // ── intro (all animators, started together: no GUI-timed pauses) ──
    ParallelAnimation {
        id: intro

        SequentialAnimation {
            OpacityAnimator { target: curtain; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
            ScriptAction { script: { if (root._onCovered) root._onCovered(); root._onCovered = null } }
        }
        OpacityAnimator { target: bloom; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: bloom; from: 0.85; to: 1; duration: 620; easing.type: Easing.OutCubic }
        OpacityAnimator { target: hud; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: hud; from: 0.92; to: 1; duration: 520; easing.type: Easing.OutCubic }
        OpacityAnimator { target: mark; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
        ScaleAnimator   { target: mark; from: 0.72; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        OpacityAnimator { target: label; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
        YAnimator       { target: label; from: root._cy + 116; to: root._cy + 106; duration: 520; easing.type: Easing.OutCubic }
        ScriptAction    { script: root._bracketsRun("in") }

        // the earliest the reveal may start; it still waits for the swap
        SequentialAnimation {
            PauseAnimation { duration: 480 }
            ScriptAction { script: root._armReveal() }
        }
    }

    // ── reveal gate ──
    // Hold the iris until the staged palette swap is done (polled), never
    // longer than the cap. While we hold, only the render-thread orbit moves,
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
        root._bracketsRun("out")
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
            // the lock: ring burst off the mark
            OpacityAnimator { target: burst; from: 0.85; to: 0; duration: 460; easing.type: Easing.OutCubic }
            ScaleAnimator   { target: burst; from: 0.6; to: 2.3; duration: 460; easing.type: Easing.OutCubic }
            // the mark pushes toward the viewer and goes
            ScaleAnimator   { target: mark; from: 1; to: 1.28; duration: 380; easing.type: Easing.InCubic }
            OpacityAnimator { target: mark; from: 1; to: 0; duration: 320; easing.type: Easing.InQuad }
            OpacityAnimator { target: hud; from: 1; to: 0; duration: 300; easing.type: Easing.OutQuad }
            ScaleAnimator   { target: hud; from: 1; to: 1.55; duration: 380; easing.type: Easing.InCubic }
            OpacityAnimator { target: bloom; from: 1; to: 0; duration: 340; easing.type: Easing.OutQuad }
            OpacityAnimator { target: label; from: 1; to: 0; duration: 220; easing.type: Easing.OutQuad }
            // the iris: new palette grows out of the mark
            ScaleAnimator   { target: lens; from: 0.002; to: 1; duration: 560; easing.type: Easing.InOutQuart }
            // ...and the whole overlay melts into the live UI as it lands
            SequentialAnimation {
                PauseAnimation { duration: 250 }
                OpacityAnimator { target: stage; from: 1; to: 0; duration: 340; easing.type: Easing.OutCubic }
            }
        }
        ScriptAction {
            script: {
                spin.stop()
                root.running = false
                root._reset()
            }
        }
    }
}
