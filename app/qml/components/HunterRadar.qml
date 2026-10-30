import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.2 — "Hunter Radar". The Niche Finder's live monitor, rebuilt around the
// brand: the YouTube Hunter mark is the transmitter at the heart of the scope,
// and every revolution of the beam is a pulse it sends out.
//
//   bezel      72-tick instrument ring (cardinals long, every 30° medium) with
//              two orbit arcs drifting the other way: the "precision" read.
//   beam       phosphor sweep painted ONCE on a Canvas and only rotated. The
//              speed is eased (idle cruise ↔ hunting sprint), so a run starting
//              spins the scope up instead of snapping to a new speed.
//   tip        a lit bead rides the bezel at the beam's leading edge.
//   contacts   blips flare and ping exactly when the beam passes them (synced
//              to the sweep, not to independent timers). The hero contact is
//              the outlier: it gets viewfinder brackets that snap shut on it
//              each pass while hunting, and a LOCK tag once there are results.
//   core       the mark sits in a dark lens with a counter-rotating dash ring.
//              Each revolution the lens fires a sonar ring outwards, the neon
//              glow surges and a light sheen crosses the logo.
//
// Same API as the old inline Radar (active / motion / hits), so call sites are
// unchanged. With ambient motion off it is a still, fully drawn scope.
Item {
    id: rd

    property bool active: false          // a search is running
    property bool motion: true           // ambient motion setting
    property bool hits: false            // the pool has results
    property color accent: Theme.primary

    implicitWidth: 216
    implicitHeight: 216
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property real _c: Math.min(width, height) / 2
    readonly property real _R: _c                    // bezel outer edge
    readonly property real _r: _R * 0.84             // scope face
    readonly property real _orbitR: _R * 0.885       // orbit arcs + beam tip
    readonly property real _coreR: _r * 0.27         // the lens holding the mark
    readonly property bool _live: motion && visible && (active || Tokens.appActive)

    // Beam angle, degrees clockwise from 3 o'clock. Parked just past the hero
    // contact when motion is off, so the still scope shows a lit outlier.
    property real sweep: 312
    property real _speed: active ? 230 : 58          // deg / s, eased below
    property real _pulse: 0                          // 1 on each revolution, decays

    signal revolution()

    FrameAnimation {
        running: rd._live
        onTriggered: {
            var dt = Math.min(0.05, frameTime)
            var target = rd.active ? 230 : 58
            rd._speed += (target - rd._speed) * Math.min(1, dt * 2.6)
            var next = rd.sweep + rd._speed * dt
            if (next >= 360) {
                next -= 360
                rd.revolution()
            }
            rd.sweep = next
        }
    }

    onRevolution: {
        centerPing.restart()
        pulseAnim.restart()
        sheenAnim.restart()
    }

    NumberAnimation {
        id: pulseAnim
        target: rd; property: "_pulse"
        from: 1; to: 0
        duration: 1300
        easing.type: Easing.OutCubic
    }

    // ── bloom behind everything ──
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: rd.active ? 1.0 : 0.7
        Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: rd._c; centerY: rd._c
                centerRadius: rd._R * 1.08
                focalX: rd._c; focalY: rd._c
                GradientStop { position: 0.0; color: U.withAlpha(rd.accent, Theme.isDark ? 0.20 : 0.12) }
                GradientStop { position: 0.62; color: U.withAlpha(rd.accent, Theme.isDark ? 0.07 : 0.045) }
                GradientStop { position: 1.0; color: U.withAlpha(rd.accent, 0.0) }
            }
            PathAngleArc { centerX: rd._c; centerY: rd._c; radiusX: rd._R * 1.08; radiusY: rd._R * 1.08; startAngle: 0; sweepAngle: 360 }
        }
    }

    // ── scope face: a lit glass dish, brighter at the core ──
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: U.withAlpha(rd.accent, 0.42)
            strokeWidth: 1
            fillGradient: RadialGradient {
                centerX: rd._c; centerY: rd._c
                centerRadius: rd._r
                focalX: rd._c; focalY: rd._c
                GradientStop { position: 0.0; color: U.withAlpha(rd.accent, Theme.isDark ? 0.13 : 0.08) }
                GradientStop { position: 0.75; color: U.withAlpha(rd.accent, Theme.isDark ? 0.035 : 0.025) }
                GradientStop { position: 1.0; color: U.withAlpha(rd.accent, Theme.isDark ? 0.08 : 0.05) }
            }
            PathAngleArc { centerX: rd._c; centerY: rd._c; radiusX: rd._r; radiusY: rd._r; startAngle: 0; sweepAngle: 360 }
        }
    }

    // range rings
    Repeater {
        model: [0.36, 0.68]
        delegate: Rectangle {
            required property real modelData
            anchors.centerIn: parent
            width: rd._r * 2 * modelData; height: width; radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: U.withAlpha(rd.accent, 0.12)
            antialiasing: true
        }
    }

    // crosshair, broken at the lens so it never cuts through the mark
    Repeater {
        model: [0, 90, 180, 270]
        delegate: Item {
            required property real modelData
            anchors.fill: parent
            rotation: modelData
            Rectangle {
                x: rd._c + rd._coreR * 1.25
                y: rd._c - 0.5
                width: rd._r - rd._coreR * 1.25
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(rd.accent, 0.0) }
                    GradientStop { position: 0.35; color: U.withAlpha(rd.accent, 0.14) }
                    GradientStop { position: 1.0; color: U.withAlpha(rd.accent, 0.20) }
                }
            }
        }
    }

    // ── the beam: painted once, then only rotated ──
    Item {
        id: beam
        anchors.fill: parent
        rotation: rd.sweep
        opacity: rd.active ? 1.0 : 0.82
        Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }

        Canvas {
            id: beamCv
            anchors.fill: parent
            antialiasing: true
            smooth: true
            property color tint: rd.accent
            onTintChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2
                var r = rd._r - 1
                if (r <= 0) return
                var R = Math.round(tint.r * 255), G = Math.round(tint.g * 255), B = Math.round(tint.b * 255)
                function rgba(a) { return "rgba(" + R + "," + G + "," + B + "," + a.toFixed(3) + ")" }
                // Trail sits counter-clockwise of the edge (angle 0) — behind a
                // clockwise beam. Each wedge overlaps the next a hair so no
                // seams show once rotated.
                var steps = 72
                var span = Math.PI * 0.50
                for (var k = 0; k < steps; k++) {
                    var t = k / steps
                    var a = 0.36 * Math.pow(1 - t, 1.7)
                    var a1 = -k * span / steps + 0.004
                    var a0 = -(k + 1) * span / steps
                    var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                    g.addColorStop(0.0, rgba(a * 0.25))
                    g.addColorStop(0.7, rgba(a * 0.8))
                    g.addColorStop(1.0, rgba(a))
                    ctx.beginPath()
                    ctx.moveTo(cx, cy)
                    ctx.arc(cx, cy, r, a0, a1, false)
                    ctx.closePath()
                    ctx.fillStyle = g
                    ctx.fill()
                }
                // leading edge: fades in from the core, hot at the rim
                var lg = ctx.createLinearGradient(cx, cy, cx + r, cy)
                lg.addColorStop(0.0, rgba(0.0))
                lg.addColorStop(0.3, rgba(0.35))
                lg.addColorStop(1.0, rgba(1.0))
                ctx.strokeStyle = lg
                ctx.lineWidth = 1.8
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx + r, cy)
                ctx.stroke()
            }
        }

        // the bead riding the bezel at the beam's edge
        Rectangle {
            width: 16; height: 16; radius: 8
            x: rd._c + rd._orbitR - width / 2
            y: rd._c - height / 2
            color: U.withAlpha(rd.accent, 0.22 + 0.18 * rd._pulse)
            antialiasing: true
        }
        Rectangle {
            width: 5; height: 5; radius: 2.5
            x: rd._c + rd._orbitR - width / 2
            y: rd._c - height / 2
            color: Qt.lighter(rd.accent, 1.35)
            antialiasing: true
        }
    }

    // ── contacts: angle° (clockwise from 3 o'clock), distance 0..1, size ──
    Repeater {
        model: [
            { a: -52, d: 0.64, s: 9, hero: true  },
            { a: 62,  d: 0.42, s: 5, hero: false },
            { a: 138, d: 0.80, s: 5, hero: false },
            { a: 210, d: 0.34, s: 4, hero: false },
            { a: 5,   d: 0.86, s: 4, hero: false },
            { a: 172, d: 0.58, s: 3, hero: false },
            { a: 292, d: 0.90, s: 3, hero: false }
        ]
        delegate: Item {
            id: blip
            required property var modelData
            required property int index
            readonly property bool hero: modelData.hero
            readonly property real s: Math.max(3, modelData.s * rd._R / 108)
            readonly property real ang: modelData.a
            readonly property real _rad: ang * Math.PI / 180
            // how far the beam has travelled past this contact (0 = right now)
            readonly property real since: ((rd.sweep - ang) % 360 + 360) % 360
            readonly property real flare: Math.max(0, 1 - since / 130)
            readonly property real base: hero ? 0.85 : ((rd.hits || rd.active) ? 0.5 : 0.3)
            property real _prev: 0
            property real _snap: 0               // 1 = brackets wide open, eases to 0

            width: s * 4; height: width
            x: rd._c + Math.cos(_rad) * rd._r * modelData.d - width / 2
            y: rd._c + Math.sin(_rad) * rd._r * modelData.d - height / 2

            // the beam just crossed this contact
            onSinceChanged: {
                if (since < _prev - 180 && rd._live) {
                    pingAnim.restart()
                    if (hero && (rd.active || rd.hits)) snapAnim.restart()
                }
                _prev = since
            }

            // halo that blooms as the beam crosses
            Rectangle {
                anchors.centerIn: parent
                width: blip.s * (1 + 2.2 * blip.flare); height: width; radius: width / 2
                color: U.withAlpha(blip.hero ? rd.accent : Theme.on_surface_var, 0.26 * blip.flare)
                antialiasing: true
            }
            // ping ring
            Rectangle {
                id: ping
                anchors.centerIn: parent
                width: blip.s; height: width; radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: blip.hero ? rd.accent : Theme.on_surface_var
                opacity: 0
                antialiasing: true
            }
            ParallelAnimation {
                id: pingAnim
                NumberAnimation { target: ping; property: "width"; from: blip.s; to: blip.s * (blip.hero ? 4.4 : 3.2); duration: 900; easing.type: Easing.OutCubic }
                NumberAnimation { target: ping; property: "opacity"; from: 0.85; to: 0; duration: 900; easing.type: Easing.OutCubic }
            }
            // the contact itself
            Rectangle {
                anchors.centerIn: parent
                width: blip.s; height: width; radius: width / 2
                color: blip.hero ? (blip.flare > 0.6 ? Qt.lighter(rd.accent, 1.25) : rd.accent)
                                 : Theme.on_surface_var
                opacity: Math.min(1, blip.base + (1 - blip.base) * blip.flare)
                antialiasing: true
            }

            // ── hero only: viewfinder lock ──
            Item {
                id: lock
                visible: blip.hero
                anchors.centerIn: parent
                width: blip.s * 3.1; height: width
                opacity: (rd.active || rd.hits) ? 1.0 : 0.45
                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                scale: 1 + 0.8 * blip._snap
                rotation: 45 * blip._snap
                readonly property real arm: Math.max(3, Math.round(width * 0.30))
                Repeater {
                    model: [[-1, -1], [1, -1], [1, 1], [-1, 1]]
                    delegate: Item {
                        required property var modelData
                        readonly property real sx: modelData[0]
                        readonly property real sy: modelData[1]
                        width: lock.arm; height: lock.arm
                        x: sx < 0 ? 0 : lock.width - width
                        y: sy < 0 ? 0 : lock.height - height
                        Rectangle { width: lock.arm; height: 1.5; y: parent.sy < 0 ? 0 : lock.arm - 1.5; color: rd.accent; antialiasing: true }
                        Rectangle { width: 1.5; height: lock.arm; x: parent.sx < 0 ? 0 : lock.arm - 1.5; color: rd.accent; antialiasing: true }
                    }
                }
            }
            NumberAnimation {
                id: snapAnim
                target: blip; property: "_snap"
                from: 1; to: 0
                duration: 560
                easing.type: Easing.OutBack
                easing.overshoot: 1.6
            }
            C.AppText {
                visible: blip.hero && rd.hits && rd._R > 70
                x: lock.x + lock.width + 3
                y: lock.y - height + 4
                text: I18n.tr("LOCK")
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontMicro
                font.letterSpacing: 1.2
                color: rd.accent
            }
        }
    }

    // ── bezel: 72 ticks, read from the outside in ──
    Repeater {
        model: 72
        delegate: Rectangle {
            id: tick
            required property int index
            readonly property bool cardinal: index % 18 === 0
            readonly property bool major: index % 6 === 0
            width: cardinal ? 1.5 : 1
            height: rd._R * (cardinal ? 0.085 : major ? 0.06 : 0.03)
            color: U.withAlpha(rd.accent, cardinal ? 0.85 : major ? 0.5 : 0.2)
            antialiasing: true
            x: rd._c - width / 2
            y: rd._c - rd._R
            transform: Rotation {
                origin.x: tick.width / 2
                origin.y: rd._R
                angle: tick.index * 5
            }
        }
    }

    // orbit arcs drifting against the beam
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1.5
            strokeColor: U.withAlpha(rd.accent, 0.55)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: rd._c; centerY: rd._c; radiusX: rd._orbitR; radiusY: rd._orbitR; startAngle: 10; sweepAngle: 62 }
        }
        ShapePath {
            strokeWidth: 1.5
            strokeColor: U.withAlpha(rd.accent, 0.30)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: rd._c; centerY: rd._c; radiusX: rd._orbitR; radiusY: rd._orbitR; startAngle: 190; sweepAngle: 34 }
        }
        RotationAnimation on rotation {
            running: rd._live
            from: 360; to: 0
            duration: rd.active ? 9000 : 26000
            loops: Animation.Infinite
        }
    }

    // ── core: sonar ring, lens, dash ring, the mark ──
    Rectangle {
        id: cping
        anchors.centerIn: parent
        width: rd._coreR * 2; height: width; radius: width / 2
        color: "transparent"
        border.width: 1.2
        border.color: rd.accent
        opacity: 0
        antialiasing: true
    }
    ParallelAnimation {
        id: centerPing
        NumberAnimation { target: cping; property: "width"; from: rd._coreR * 2; to: rd._r * 2; duration: 1250; easing.type: Easing.OutCubic }
        NumberAnimation { target: cping; property: "opacity"; from: 0.6; to: 0; duration: 1250; easing.type: Easing.OutQuad }
    }

    // glow under the lens
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        scale: 1 + 0.10 * rd._pulse
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: rd._c; centerY: rd._c
                centerRadius: rd._coreR * 1.9
                focalX: rd._c; focalY: rd._c
                GradientStop { position: 0.0; color: U.withAlpha(rd.accent, 0.34 + 0.16 * rd._pulse) }
                GradientStop { position: 0.5; color: U.withAlpha(rd.accent, 0.10) }
                GradientStop { position: 1.0; color: U.withAlpha(rd.accent, 0.0) }
            }
            PathAngleArc { centerX: rd._c; centerY: rd._c; radiusX: rd._coreR * 1.9; radiusY: rd._coreR * 1.9; startAngle: 0; sweepAngle: 360 }
        }
    }

    // the dark lens that holds the mark
    Rectangle {
        anchors.centerIn: parent
        width: rd._coreR * 2; height: width; radius: width / 2
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(0.10, 0.09, 0.08, 0.92) : Qt.rgba(1, 1, 1, 0.92) }
            GradientStop { position: 1.0; color: Theme.isDark ? Qt.rgba(0.04, 0.035, 0.03, 0.96) : Qt.rgba(0.96, 0.95, 0.94, 0.96) }
        }
        border.width: 1
        border.color: U.withAlpha(rd.accent, 0.55 + 0.35 * rd._pulse)
    }

    // dashed ring turning against the beam
    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: U.withAlpha(rd.accent, 0.5)
            strokeStyle: ShapePath.DashLine
            dashPattern: [1.5, 3]
            PathAngleArc { centerX: rd._c; centerY: rd._c; radiusX: rd._coreR * 1.2; radiusY: rd._coreR * 1.2; startAngle: 0; sweepAngle: 360 }
        }
        RotationAnimation on rotation {
            running: rd._live
            from: 360; to: 0
            duration: 18000
            loops: Animation.Infinite
        }
    }

    C.BrandMark {
        id: mark
        width: Math.round(rd._coreR * 1.12)
        height: Math.round(width * 812 / 738)
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(rd._coreR * 0.04)
        rim: true
        glow: rd._R > 40
        glowStrength: 0.4 + 0.6 * rd._pulse
        sheen: -1
    }
    NumberAnimation {
        id: sheenAnim
        target: mark; property: "sheen"
        from: 0; to: 1
        duration: 950
        easing.type: Easing.InOutSine
    }
}
