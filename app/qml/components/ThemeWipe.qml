import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.3 — "Daybreak" theme transition.
//
// The title-bar switch blooms into a hero-sized copy of itself in the middle
// of the window, flips, and the NEW palette floods out of its thumb:
//
//   0.00  curtain (old palette) fades up; a soft accent bloom rises and the
//         hero switch springs in, thumb on the OLD side, old glyph on its face
//   0.23  the thumb slides across the track; the old glyph spins out, the new
//         one spins in, and the thumb's face turns into the NEW palette
//   0.62  landing: two accent ripples ring out from the thumb, stars twinkle
//         in (to dark) or sun rays fan out and keep turning (to light), and
//         the mode label rises beneath
//   hold  ripples / stars / rays keep moving on the render thread while the
//         staged palette swap finishes behind the curtain (capped, see gate)
//   OPEN  the iris IS the thumb: a disc of the new palette, exactly the colour
//         of the thumb's face, swells from it to fill the window, and the
//         overlay melts into the live UI
//
// Why it changed: the v1.0.2 "Eclipse" read as an instrument panel (72 ticks,
// corona, brand mark on a disc) and the label was barely legible. Using the
// same object the user just clicked makes the transition explain itself, and
// opening from the thumb instead of the window centre ties the flood of new
// colour to the control that caused it.
//
// Performance rules unchanged from v3.41 (the reason this file is shaped the
// way it is): everything that MOVES is an Animator (Opacity / Scale /
// Rotation / X / Y), so motion runs on the render thread and keeps gliding
// while the GUI thread republishes the palette. All geometry is static —
// circles are only scaled, rays only rotated. No window snapshot, no
// MultiEffect, no full-window shader, input never blocked. Every colour is
// resolved in run() BEFORE the swap starts, so nothing here re-binds mid-run.
//
// The public API is unchanged: run(cx, cy, targetColor, onCovered, onReveal,
// isReady), warmUp(), `running`, `radius`.
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
    property color accentDeep: Theme.primary_deep
    property bool oldDark: true
    property bool newDark: false
    property var _onCovered: null
    property var _onReveal: null
    property var _isReady: null
    property bool _warming: false
    // ambient loops (stars twinkle) only while the overlay is up
    property bool _ambient: false

    // ── geometry ──
    readonly property real _cx: Math.round(width / 2)
    readonly property real _cy: Math.round(height / 2 - 18)
    readonly property real _pillW: 196
    readonly property real _pillH: 88
    readonly property real _thumbD: 72
    readonly property real _thumbR: _thumbD / 2
    // thumb centre's distance from the pill centre at either end
    readonly property real _travel: _pillW / 2 - 8 - _thumbR
    // hero box (track + thumb + stars + rays + ripples), scaled as one
    readonly property real _heroW: 420
    readonly property real _heroH: 320
    // dark lives on the right, like the title-bar switch
    readonly property real _fromDx: newDark ? -_travel : _travel
    readonly property real _toDx: -_fromDx
    readonly property real _toX: _cx + _toDx      // where the iris opens

    // The iris stops where it meets the window's rounded corners (the 45°
    // point of each corner arc) instead of the bounding-box corner, so it
    // never paints the transparent pixels OUTSIDE the rounded window.
    readonly property real _cornerInset: Math.min(root.radius, width / 2, height / 2) * (1 - Math.SQRT1_2)
    readonly property real _lensR: {
        const dx = Math.max(_toX, width - _toX) - _cornerInset
        const dy = Math.max(_cy, height - _cy) - _cornerInset
        return Math.max(40, Math.sqrt(dx * dx + dy * dy))
    }
    readonly property real _lensStart: _thumbR / _lensR

    // ── palette (resolved in run(), static for the whole run) ──
    readonly property color _ink: oldDark ? "#ECECEF" : "#17171B"
    readonly property color _track: oldDark ? U.mix(oldColor, "#FFFFFF", 0.055)
                                            : U.mix(oldColor, "#000000", 0.045)
    readonly property color _oldFace: oldDark ? U.mix(oldColor, "#FFFFFF", 0.11) : "#FFFFFF"

    function _isDarkColor(c) {
        c = Qt.color(c)
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }

    // hero-local thumb x for a centre offset
    function _thumbX(dx) { return root._heroW / 2 + dx - root._thumbR }

    readonly property Item _outGlyph: newDark ? sunGlyph : moonGlyph
    readonly property Item _inGlyph: newDark ? moonGlyph : sunGlyph
    readonly property real _spinDir: newDark ? 1 : -1

    // Put every animated piece back at its "before the run" value. Animators
    // only write their final value back to the GUI side when they finish, so
    // the reset must be explicit and happen BEFORE any animator starts.
    function _reset() {
        root._ambient = false
        curtain.opacity = 0
        stage.opacity = 1
        bloom.opacity = 0; bloom.scale = 0.85
        hero.opacity = 0; hero.scale = 0.72
        wash.opacity = 0
        thumb.x = root._thumbX(root._fromDx)
        newFace.opacity = 0
        rim.opacity = 0
        sunGlyph.opacity = root.newDark ? 1 : 0
        sunGlyph.scale = 1; sunGlyph.rotation = 0
        moonGlyph.opacity = root.newDark ? 0 : 1
        moonGlyph.scale = 1; moonGlyph.rotation = 0
        ring1.opacity = 0; ring1.scale = 1
        ring2.opacity = 0; ring2.scale = 1
        stars.opacity = 0; stars.scale = 0.9
        rays.opacity = 0; rays.scale = 0.6; rays.rotation = 0
        lens.opacity = 0
        lens.scale = root._lensStart
        label.opacity = 0; label.y = root._labelY + 12
    }
    readonly property real _labelY: _cy + _pillH / 2 + 30

    // Render every piece once, invisibly, so the first real switch does not
    // pay for CurveRenderer shader setup / first-use node creation.
    function warmUp() {
        if (root.running) return
        root._warming = true
        root.opacity = 0.004
        curtain.opacity = 1; bloom.opacity = 1; hero.opacity = 1; wash.opacity = 1
        newFace.opacity = 1; rim.opacity = 1
        sunGlyph.opacity = 1; moonGlyph.opacity = 1
        ring1.opacity = 1; ring2.opacity = 1; stars.opacity = 1; rays.opacity = 1
        lens.opacity = 1; lens.scale = 0.5; label.opacity = 1
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
    // (cx, cy) are accepted for API compatibility; the hero always plays in
    // the middle of the window, where the eye already is after the click.
    function run(cx, cy, targetColor, onCovered, onReveal, isReady) {
        if (root.running) return
        gate.stop(); revealAnim.stop(); intro.stop(); raySpin.stop()
        warmTimer.stop(); root._warming = false; root.opacity = 1
        root.oldColor = Theme.background         // resolve BEFORE the swap
        root.newColor = targetColor
        root.oldDark = Theme.isDark
        root.newDark = _isDarkColor(targetColor)
        root.accent = Theme.primary
        root.accentDeep = Theme.primary_deep !== undefined ? Theme.primary_deep : Theme.primary
        root._onCovered = onCovered
        root._onReveal = onReveal || null
        root._isReady = isReady || null
        root._reset()
        root.running = true
        intro.restart()
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

        // ── accent bloom behind the hero ──
        Shape {
            id: bloom
            width: 760; height: 760
            x: root._cx - width / 2; y: root._cy - height / 2
            opacity: 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: 380; centerY: 380; centerRadius: 380
                    focalX: 380; focalY: 380
                    GradientStop { position: 0.0;  color: U.withAlpha(root.accent, root.oldDark ? 0.26 : 0.16) }
                    GradientStop { position: 0.30; color: U.withAlpha(root.accent, root.oldDark ? 0.09 : 0.06) }
                    GradientStop { position: 1.0;  color: U.withAlpha(root.accent, 0) }
                }
                PathAngleArc { centerX: 380; centerY: 380; radiusX: 380; radiusY: 380; startAngle: 0; sweepAngle: 360 }
            }
        }

        // ── the hero switch ──
        Item {
            id: hero
            width: root._heroW; height: root._heroH
            x: root._cx - width / 2; y: root._cy - height / 2
            opacity: 0
            scale: 0.72

            // landing ripples (behind the track, centred on the thumb's end)
            Rectangle {
                id: ring1
                width: root._thumbD + 10; height: width; radius: width / 2
                x: root._heroW / 2 + root._toDx - width / 2
                y: root._heroH / 2 - height / 2
                color: "transparent"
                border.width: 1.5
                border.color: root.accent
                opacity: 0
                antialiasing: true
            }
            Rectangle {
                id: ring2
                width: root._thumbD + 10; height: width; radius: width / 2
                x: ring1.x; y: ring1.y
                color: "transparent"
                border.width: 1
                border.color: root.accent
                opacity: 0
                antialiasing: true
            }

            // soft drop under the track
            Rectangle {
                width: root._pillW + (root.oldDark ? 24 : 10)
                height: root._pillH + (root.oldDark ? 24 : 10)
                radius: height / 2
                x: (root._heroW - width) / 2
                y: (root._heroH - height) / 2 + (root.oldDark ? 6 : 4)
                color: Qt.rgba(0, 0, 0, root.oldDark ? 0.30 : 0.045)
                antialiasing: true
            }

            // track
            Rectangle {
                id: track
                width: root._pillW; height: root._pillH
                radius: height / 2
                x: (root._heroW - width) / 2
                y: (root._heroH - height) / 2
                color: root._track
                border.width: 1
                border.color: U.withAlpha(root._ink, root.oldDark ? 0.10 : 0.09)
                antialiasing: true

                // accent wash that pours toward the side the thumb is heading
                Rectangle {
                    id: wash
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: height / 2
                    opacity: 0
                    antialiasing: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(root.accent, root.newDark ? 0.0 : 0.30) }
                        GradientStop { position: 0.5; color: U.withAlpha(root.accent, 0.10) }
                        GradientStop { position: 1.0; color: U.withAlpha(root.accent, root.newDark ? 0.30 : 0.0) }
                    }
                }
                // 1 px specular top line: the track reads as a glass object
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - parent.height
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, root.oldDark ? 0.10 : 0.9) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
            }

            // stars (to dark): on the side the thumb leaves, plus a few
            // outside the track — the night arriving around the switch
            Item {
                id: stars
                anchors.fill: parent
                visible: root.newDark || root._warming
                opacity: 0
                Repeater {
                    model: [
                        { x: -64, y: -14, s: 3.2, d: 0,    a: true  },
                        { x: -44, y: 12,  s: 2.2, d: 380,  a: false },
                        { x: -26, y: -22, s: 1.8, d: 760,  a: false },
                        { x: -78, y: 16,  s: 1.6, d: 220,  a: false },
                        { x: -18, y: 20,  s: 1.4, d: 980,  a: false },
                        { x: -128, y: -56, s: 2.4, d: 520, a: false },
                        { x: 132, y: -48, s: 2.0, d: 140,  a: true  },
                        { x: 118, y: 60,  s: 1.6, d: 860,  a: false },
                        { x: -110, y: 64, s: 1.8, d: 640,  a: false }
                    ]
                    delegate: Rectangle {
                        id: star
                        required property var modelData
                        x: root._heroW / 2 + modelData.x - width / 2
                        y: root._heroH / 2 + modelData.y - height / 2
                        width: modelData.s; height: width; radius: width / 2
                        // on a light curtain ink-coloured dots read as dust:
                        // the stars take the accent there instead
                        color: modelData.a ? Qt.lighter(root.accent, 1.25)
                                           : (root.oldDark ? root._ink : U.withAlpha(root.accent, 0.7))
                        antialiasing: true
                        SequentialAnimation {
                            running: root._ambient && root.newDark
                            loops: Animation.Infinite
                            PauseAnimation { duration: star.modelData.d }
                            OpacityAnimator { target: star; from: 1; to: 0.2; duration: 900; easing.type: Easing.InOutSine }
                            OpacityAnimator { target: star; from: 0.2; to: 1; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            // sun rays (to light): fan out around the thumb's landing spot
            Item {
                id: rays
                width: 140; height: 140
                x: root._heroW / 2 + root._toDx - width / 2
                y: root._heroH / 2 - height / 2
                visible: !root.newDark || root._warming
                opacity: 0
                Repeater {
                    model: 16
                    delegate: Item {
                        required property int index
                        anchors.fill: parent
                        rotation: index * 22.5
                        Rectangle {
                            readonly property bool major: parent.index % 2 === 0
                            x: 70 - width / 2
                            y: 70 - root._thumbR - 8 - height
                            width: major ? 3 : 2
                            height: major ? 11 : 6
                            radius: width / 2
                            color: root.accent
                            opacity: major ? 0.85 : 0.45
                            antialiasing: true
                        }
                    }
                }
            }

            // ── the thumb ──
            Item {
                id: thumb
                width: root._thumbD; height: width
                y: (root._heroH - height) / 2

                // accent glow under the thumb (three whisper-alpha discs)
                Repeater {
                    model: [10, 20, 32]
                    Rectangle {
                        required property var modelData
                        anchors.centerIn: parent
                        width: root._thumbD + modelData * 2; height: width; radius: width / 2
                        color: U.withAlpha(root.accent, root.oldDark ? 0.085 : 0.06)
                        antialiasing: true
                    }
                }
                // drop
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 3
                    width: parent.width; height: width; radius: width / 2
                    color: Qt.rgba(0, 0, 0, root.oldDark ? 0.35 : 0.12)
                    antialiasing: true
                }
                // the OLD palette's face
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: root._oldFace
                    border.width: 1
                    border.color: U.withAlpha(root._ink, 0.08)
                    antialiasing: true
                }
                // the NEW palette's face: exactly the iris colour
                Rectangle {
                    id: newFace
                    anchors.fill: parent
                    radius: width / 2
                    color: root.newColor
                    opacity: 0
                    antialiasing: true
                }
                // accent rim that lights as the face turns
                Rectangle {
                    id: rim
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.lighter(root.accent, 1.15)
                    opacity: 0
                    antialiasing: true
                }

                // SUN: accent core + eight short rays
                Item {
                    id: sunGlyph
                    width: 60; height: 60
                    anchors.centerIn: parent
                    Repeater {
                        model: 8
                        Item {
                            required property int index
                            anchors.fill: parent
                            rotation: index * 45
                            Rectangle {
                                x: 30 - width / 2
                                y: 5
                                width: 3.5; height: 8; radius: 1.75
                                color: root.accent
                                opacity: parent.index % 2 === 0 ? 1 : 0.7
                                antialiasing: true
                            }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 26; height: 26; radius: 13
                        antialiasing: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.3) }
                            GradientStop { position: 0.6; color: root.accent }
                            GradientStop { position: 1.0; color: root.accentDeep }
                        }
                        // specular dot: a lit sphere, not a sticker
                        Rectangle {
                            x: 6; y: 5
                            width: 7; height: 7; radius: 3.5
                            color: "#FFFFFF"
                            opacity: 0.5
                        }
                    }
                }

                // MOON: the title-bar crescent at hero size (CurveRenderer
                // scales cleanly, so the 18-unit path is just scaled up)
                Item {
                    id: moonGlyph
                    width: 60; height: 60
                    anchors.centerIn: parent
                    Item {
                        width: 18; height: 18
                        anchors.centerIn: parent
                        scale: 1.9
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: "transparent"
                                fillGradient: LinearGradient {
                                    x1: 0; y1: 18; x2: 18; y2: 0
                                    GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.2) }
                                    GradientStop { position: 1.0; color: root.accentDeep }
                                }
                                startX: 7.567; startY: 0.115
                                PathArc {
                                    x: 17.885; y: 10.433
                                    radiusX: 9; radiusY: 9
                                    useLargeArc: true
                                    direction: PathArc.Counterclockwise
                                }
                                PathArc {
                                    x: 7.567; y: 0.115
                                    radiusX: 7.4; radiusY: 7.4
                                    useLargeArc: false
                                    direction: PathArc.Clockwise
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── the iris: a disc of the NEW palette that starts as the thumb ──
        // A fixed-size circle (radius = _lensR) centred on the thumb's landing
        // spot that is only ever scaled, so the reveal is a transform update.
        Shape {
            id: lens
            width: root._lensR * 2; height: width
            x: root._toX - root._lensR
            y: root._cy - root._lensR
            transformOrigin: Item.Center
            opacity: 0
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

        // ── mode label (old palette ink, fully legible) ──
        C.AppText {
            id: label
            anchors.horizontalCenter: parent.horizontalCenter
            mono: I18n.lang !== "fa"
            text: root.newDark ? I18n.tr("Dark mode") : I18n.tr("Light mode")
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontCaption + 1
            font.capitalization: I18n.lang === "fa" ? Font.MixedCase : Font.AllUppercase
            // tracking only for Latin: letter-spacing breaks Persian joining
            font.letterSpacing: I18n.lang === "fa" ? 0 : 3.5
            color: U.withAlpha(root._ink, 0.88)
            opacity: 0
        }
    }

    // ── continuous motion while we hold (render thread) ──
    RotationAnimator {
        id: raySpin
        target: rays
        from: 0; to: 360
        duration: 16000
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
        ScaleAnimator   { target: bloom; from: 0.85; to: 1; duration: 720; easing.type: Easing.OutCubic }

        // the switch springs in
        SequentialAnimation {
            PauseAnimation { duration: 40 }
            ParallelAnimation {
                OpacityAnimator { target: hero; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                ScaleAnimator   { target: hero; from: 0.72; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
            }
        }

        // the flip
        SequentialAnimation {
            PauseAnimation { duration: 230 }
            ParallelAnimation {
                XAnimator { target: thumb; from: root._thumbX(root._fromDx); to: root._thumbX(root._toDx); duration: 440; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                OpacityAnimator { target: wash; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                // old glyph spins out
                OpacityAnimator { target: root._outGlyph; from: 1; to: 0; duration: 200; easing.type: Easing.OutQuad }
                ScaleAnimator   { target: root._outGlyph; from: 1; to: 0.4; duration: 300; easing.type: Easing.InCubic }
                RotationAnimator { target: root._outGlyph; from: 0; to: 110 * root._spinDir; duration: 320; easing.type: Easing.InCubic }
                // the face turns into the new palette
                SequentialAnimation {
                    PauseAnimation { duration: 110 }
                    OpacityAnimator { target: newFace; from: 0; to: 1; duration: 280; easing.type: Easing.InOutQuad }
                }
                // new glyph spins in
                SequentialAnimation {
                    PauseAnimation { duration: 150 }
                    ParallelAnimation {
                        OpacityAnimator { target: root._inGlyph; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        ScaleAnimator   { target: root._inGlyph; from: 0.4; to: 1; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
                        RotationAnimator { target: root._inGlyph; from: -110 * root._spinDir; to: 0; duration: 460; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        // landing
        SequentialAnimation {
            PauseAnimation { duration: 600 }
            ScriptAction { script: { root._ambient = true; if (!root.newDark) raySpin.restart() } }
            ParallelAnimation {
                OpacityAnimator { target: rim; from: 0; to: 0.9; duration: 180; easing.type: Easing.OutCubic }
                OpacityAnimator { target: ring1; from: 0.6; to: 0; duration: 640; easing.type: Easing.OutQuad }
                ScaleAnimator   { target: ring1; from: 1; to: 2.3; duration: 640; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    PauseAnimation { duration: 110 }
                    ParallelAnimation {
                        OpacityAnimator { target: ring2; from: 0.4; to: 0; duration: 760; easing.type: Easing.OutQuad }
                        ScaleAnimator   { target: ring2; from: 1; to: 3.0; duration: 760; easing.type: Easing.OutCubic }
                    }
                }
                OpacityAnimator { target: stars; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                ScaleAnimator   { target: stars; from: 0.9; to: 1; duration: 560; easing.type: Easing.OutCubic }
                OpacityAnimator { target: rays; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
                ScaleAnimator   { target: rays; from: 0.6; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                OpacityAnimator { target: label; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
                YAnimator       { target: label; from: root._labelY + 12; to: root._labelY; duration: 420; easing.type: Easing.OutCubic }
            }
        }

        // the earliest the reveal may start; it still waits for the swap
        SequentialAnimation {
            PauseAnimation { duration: 700 }
            ScriptAction { script: root._armReveal() }
        }
    }

    // ── reveal gate ──
    // Hold the iris until the staged palette swap is done (polled), never
    // longer than the cap. While we hold, only render-thread motion runs, so
    // a busy GUI thread is invisible.
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
            // the iris takes over from the thumb (same colour, same size, so
            // the hand-off is invisible) and swells to fill the window
            OpacityAnimator { target: lens; from: 0; to: 1; duration: 60 }
            ScaleAnimator   { target: lens; from: root._lensStart; to: 1; duration: 620; easing.type: Easing.InOutCubic }
            // the hero lifts toward the viewer and goes
            ScaleAnimator   { target: hero; from: 1; to: 1.1; duration: 360; easing.type: Easing.InCubic }
            OpacityAnimator { target: hero; from: 1; to: 0; duration: 300; easing.type: Easing.InQuad }
            OpacityAnimator { target: bloom; from: 1; to: 0; duration: 360; easing.type: Easing.OutQuad }
            OpacityAnimator { target: label; from: 1; to: 0; duration: 200; easing.type: Easing.OutQuad }
            // ...and the whole overlay melts into the live UI as it lands
            SequentialAnimation {
                PauseAnimation { duration: 300 }
                OpacityAnimator { target: stage; from: 1; to: 0; duration: 340; easing.type: Easing.OutCubic }
            }
        }
        ScriptAction {
            script: {
                raySpin.stop()
                root.running = false
                root._reset()
            }
        }
    }
}
