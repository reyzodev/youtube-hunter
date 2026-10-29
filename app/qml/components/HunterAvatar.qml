import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// "Hunter" avatar — the AI Chat's per-message mark (v1.0.4, 2026 pass).
//
// Replaces the dark round badge + HUD brackets in the message header. That
// badge was near-black in BOTH themes, so on the light theme it read as a hole
// punched in the page, and its crest picked up the accent only as a thin
// gradient. This is an app-icon tile instead:
//
//   * a squircle filled with the live accent (Theme.logo_grad_in -> out), so it
//     follows whatever accent the user picked and sits right in light and dark;
//   * the Hunter crest in white on top, the play notch punched out in accent;
//   * a glass sheen across the top half and a 1 px inner light edge, the way a
//     real glossy icon catches light.
//
//   mode "idle"      still. Costs nothing (no animation runs).
//   mode "thinking"  a comet of light orbits the tile's rim, the crest breathes
//   mode "streaming" the rim stays lit and a glint sweeps across the glass
//
// Same public API as HunterSigil (size / mode / breathe) so it is a drop-in.
// Everything is drawn inside `size` except the activity rim (only the live
// answer has one), so the shared idle texture in AIChatPage stays exact.
Item {
    id: root
    property int size: 30
    property string mode: "idle"
    property bool breathe: false

    readonly property bool _active: mode === "thinking" || mode === "streaming"
    readonly property bool _live: visible && (_active || (breathe && Tokens.appActive))
                                  && (App.ambientMotion === undefined || App.ambientMotion || _active)

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // ── palette (all derived from the live accent) ──
    readonly property color _a: Theme.logo_grad_in
    readonly property color _b: Theme.logo_grad_out
    readonly property color _top: U.mix(_a, "#FFFFFF", 0.14)
    readonly property color _bottom: U.mix(_b, "#000000", 0.18)
    readonly property color _notch: U.mix(_a, _b, 0.6)
    readonly property real _r: Math.round(size * 0.31)   // squircle-ish corner

    // ── animation state ──
    property real _t: 0
    property real _spin: 0       // rim comet angle (deg)
    property real _rim: 0        // 0..1 rim visibility
    property real _pulse: 1      // crest scale
    property real _glint: -1     // glint position, -1..2 (off-tile outside 0..1)

    FrameAnimation {
        running: root._live
        onTriggered: {
            var dt = Math.min(0.05, frameTime)
            root._t += dt
            var k = Math.min(1, dt * 8)
            var tRim, tPulse
            if (root.mode === "thinking") {
                root._spin = (root._spin + 330 * dt) % 360
                tRim = 1
                tPulse = 0.93 + 0.07 * (0.5 + 0.5 * Math.sin(root._t * 6))
                root._glint = -1
            } else if (root.mode === "streaming") {
                root._spin = (root._spin + 140 * dt) % 360
                tRim = 1
                tPulse = 1
                // one glint every 1.6 s
                root._glint = ((root._t % 1.6) / 1.6) * 3 - 1
            } else {
                // idle + breathe (hero only): a slow glint every 6 s, no rim
                tRim = 0
                tPulse = 1
                root._glint = ((root._t % 6.0) / 1.4) * 3 - 1
            }
            root._rim += (tRim - root._rim) * k
            root._pulse += (tPulse - root._pulse) * k
        }
    }
    onModeChanged: if (!_active) settle.restart()
    ParallelAnimation {
        id: settle
        NumberAnimation { target: root; property: "_rim"; to: 0; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "_pulse"; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "_glint"; to: -1; duration: 0 }
    }

    // ── activity rim (outside the tile; only while thinking / streaming) ──
    Shape {
        id: rim
        readonly property real pad: Math.max(3, Math.round(root.size * 0.07))
        readonly property real th: Math.max(1.6, root.size * 0.022)
        x: -pad; y: -pad
        width: root.size + pad * 2
        height: root.size + pad * 2
        visible: root._rim > 0.01 && root.size >= 20
        opacity: root._rim
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: rim.width / 2; centerY: rim.height / 2
                angle: -root._spin
                GradientStop { position: 0.0;  color: U.withAlpha(root._a, 0.95) }
                GradientStop { position: 0.08; color: U.withAlpha(root._a, 0.55) }
                GradientStop { position: 0.55; color: U.withAlpha(root._a, root.mode === "streaming" ? 0.30 : 0.0) }
                GradientStop { position: 0.92; color: U.withAlpha(root._a, root.mode === "streaming" ? 0.45 : 0.10) }
                GradientStop { position: 1.0;  color: U.withAlpha(root._a, 0.95) }
            }
            PathRectangle {
                x: 0; y: 0; width: rim.width; height: rim.height
                radius: root._r + rim.pad
            }
            PathRectangle {
                x: rim.th; y: rim.th
                width: rim.width - rim.th * 2; height: rim.height - rim.th * 2
                radius: root._r + rim.pad - rim.th
            }
        }
    }

    // ── the tile ──
    Rectangle {
        id: tile
        anchors.fill: parent
        radius: root._r
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: root._top }
            GradientStop { position: 0.55; color: root._a }
            GradientStop { position: 1.0; color: root._bottom }
        }
    }

    // glass sheen over the top half
    Rectangle {
        anchors.fill: parent
        radius: root._r
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.30) }
            GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, 0.04) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    // moving glint, confined exactly to the rounded tile (a gradient band, so
    // nothing ever leaks past the corners)
    Shape {
        anchors.fill: parent
        visible: root._glint > -0.6 && root._glint < 1.6
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: -1
            fillGradient: LinearGradient {
                readonly property real o: root._glint * root.size
                x1: o - root.size * 0.5; y1: 0
                x2: o + root.size * 0.1; y2: root.size
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.42) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathRectangle { x: 0; y: 0; width: root.size; height: root.size; radius: root._r }
        }
    }

    // the crest (738 x 812 design box), white with the play notch in accent
    Item {
        id: art
        readonly property real k: (root.size * 0.58) / 812
        width: 738; height: 812
        transformOrigin: Item.Center
        scale: k * root._pulse
        x: (root.size - 738) / 2
        y: (root.size - 812) / 2 + root.size * 0.02
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // side blades: slightly dimmer, so the centre blade leads
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillColor: Qt.rgba(1, 1, 1, 0.78)
                PathPolyline { path: [Qt.point(156, 240), Qt.point(231, 322), Qt.point(231, 444), Qt.point(310, 524), Qt.point(318, 662), Qt.point(363, 804), Qt.point(156, 526), Qt.point(156, 240)] }
            }
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillColor: Qt.rgba(1, 1, 1, 0.78)
                PathPolyline { path: [Qt.point(582, 526), Qt.point(375, 804), Qt.point(420, 662), Qt.point(428, 524), Qt.point(507, 444), Qt.point(507, 322), Qt.point(582, 240), Qt.point(582, 526)] }
            }
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: 812
                    GradientStop { position: 0.0; color: "#FFFFFF" }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.86) }
                }
                PathPolyline { path: [Qt.point(0, 0), Qt.point(304, 146), Qt.point(304, 260), Qt.point(369, 304), Qt.point(434, 260), Qt.point(434, 146), Qt.point(738, 0), Qt.point(475, 307), Qt.point(475, 477), Qt.point(418, 532), Qt.point(410, 662), Qt.point(369, 812), Qt.point(328, 662), Qt.point(320, 532), Qt.point(263, 477), Qt.point(263, 307), Qt.point(0, 0)] }
            }
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillColor: root._notch
                PathPolyline { path: [Qt.point(324, 351), Qt.point(427, 422), Qt.point(324, 493), Qt.point(324, 351)] }
            }
        }
    }

    // contact line on the very edge (keeps the tile from floating on
    // near-black, and gives it a crisp accent edge on white) ...
    Rectangle {
        anchors.fill: parent
        radius: root._r
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: Theme.isDark ? Qt.rgba(0, 0, 0, 0.40) : U.withAlpha(root._b, 0.22)
    }
    // ... and a 1 px inner light edge just inside it: the tile's glass rim
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root._r - 1
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.20)
    }
}
