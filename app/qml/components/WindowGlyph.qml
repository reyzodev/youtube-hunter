import QtQuick
import QtQuick.Shapes
import NicheScope

// v1.0.3 — the title bar's window-control glyphs, drawn live instead of
// borrowed from the in-page icon set.
//
// The old maximise button showed the "fullscreen_exit" glyph (four corners
// pointing inward) once the window was maximised: that is a VIDEO-PLAYER
// symbol, it read as "shrink the picture", and at 16 px it looked like a
// broken asterisk. A desktop app's restore button is two stacked windows.
//
//   kind "min"    one rounded bar; it stretches a touch on hover
//   kind "max"    one rounded window  →  two stacked windows (restore)
//                 The back window slides out from behind the front one when
//                 the app maximises and tucks back in when it restores, so
//                 the state change itself is the animation.
//   kind "close"  an X that turns a quarter on hover
//
// Everything is on a 16-unit grid with the same 1.5 stroke, so the three read
// as one family. `glyphColor` comes from the button (hover / danger states).
Item {
    id: root
    property string kind: "max"
    property bool maximized: false
    property bool hovered: false
    property color glyphColor: Theme.on_surface_var
    readonly property real stroke: 1.5

    implicitWidth: 16
    implicitHeight: 16
    width: 16
    height: 16

    // 0 = one window (maximise), 1 = two windows (restore)
    property real m: maximized ? 1 : 0
    Behavior on m { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    // 0 → 1 while the pointer is over the button
    property real h: hovered ? 1 : 0
    Behavior on h { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    function lerp(a, b, t) { return a + (b - a) * t }

    // ── minimise ──
    Rectangle {
        visible: root.kind === "min"
        width: root.lerp(10, 12, root.h)
        height: root.stroke
        radius: height / 2
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.lerp(0, 1, root.h)
        color: root.glyphColor
        antialiasing: true
    }

    // ── maximise / restore ──
    Item {
        anchors.fill: parent
        visible: root.kind === "max"

        // the window BEHIND: only its top and right edges show, so it reads
        // as tucked behind the front one without any masking
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: Math.max(0, Math.min(1, root.m))
            transform: Translate {
                x: (1 - root.m) * -3 + root.h * root.m * 0.6
                y: (1 - root.m) * 3 - root.h * root.m * 0.6
            }
            ShapePath {
                strokeColor: root.glyphColor
                strokeWidth: root.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 6.4; startY: 1.75
                PathLine { x: 11.6; y: 1.75 }
                PathArc { x: 14.25; y: 4.4; radiusX: 2.65; radiusY: 2.65 }
                PathLine { x: 14.25; y: 9.6 }
            }
        }

        // the FRONT window: one large square when restored-down, the smaller
        // front pane of the pair when maximised
        Rectangle {
            readonly property real grow: root.h * (1 - root.m) * 0.6
            x: root.lerp(2.5, 1.75, root.m) - grow
            y: root.lerp(2.5, 4.9, root.m) - grow
            width: root.lerp(11, 9.35, root.m) + grow * 2
            height: width
            radius: root.lerp(3.2, 2.6, root.m)
            color: "transparent"
            border.width: root.stroke
            border.color: root.glyphColor
            antialiasing: true
        }
    }

    // ── close ──
    Item {
        anchors.fill: parent
        visible: root.kind === "close"
        rotation: root.h * 90
        Rectangle {
            width: 13; height: root.stroke; radius: height / 2
            anchors.centerIn: parent
            rotation: 45
            color: root.glyphColor
            antialiasing: true
        }
        Rectangle {
            width: 13; height: root.stroke; radius: height / 2
            anchors.centerIn: parent
            rotation: -45
            color: root.glyphColor
            antialiasing: true
        }
    }
}
