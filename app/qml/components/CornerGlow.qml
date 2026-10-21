import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// A soft corner glow clipped to a ROUNDED rectangle (the panel's own curve),
// not the panel's square bounding box. Drop it as a child that fills a panel:
//
//   C.GlassPanel { id: card
//       C.CornerGlow { radius: card.radius }
//       ... }
//
// Perf rewrite: the old version stacked three offscreen passes per card — a
// MultiEffect-blurred GlowBlob, rendered into a layer, masked by a second
// layered rounded rect. Here the panel's rounded outline IS the shape, filled
// with a radial gradient centred where the blob used to sit. Same look, same
// rounded falloff, one plain draw, nothing re-rendered on resize.
Item {
    id: root
    anchors.fill: parent
    property real radius: Tokens.radiusXl
    property real size: 360
    property color glow: Theme.primary
    property real strength: Theme.isDark ? 0.16 : 0.11

    // Invisible stand-in carrying the OLD blob's anchors, so the glow centre
    // follows layout mirroring (RTL puts it in the top-left) exactly as before.
    Item {
        id: spot
        width: root.size; height: root.size
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -60
        anchors.topMargin: -90
    }

    readonly property real _cx: spot.x + spot.width / 2
    readonly property real _cy: spot.y + spot.height / 2
    readonly property real _pad: 64 * 1.35
    readonly property real _R: size / 2 + _pad
    readonly property real _r: Math.max(0, Math.min(radius, width / 2, height / 2))

    Shape {
        id: shape
        anchors.fill: parent
        visible: root.width > 0 && root.height > 0
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root._cx; centerY: root._cy; centerRadius: root._R
                focalX: root._cx; focalY: root._cy; focalRadius: 0
                GradientStop { position: 0.0; color: U.withAlpha(root.glow, root.strength * 0.72) }
                GradientStop { position: Math.max(0.05, (root.size / 2 - root._pad * 0.7) / root._R)
                               color: U.withAlpha(root.glow, root.strength * 0.50) }
                GradientStop { position: (root.size / 2) / root._R
                               color: U.withAlpha(root.glow, root.strength * 0.26) }
                GradientStop { position: (root.size / 2 + root._pad * 0.5) / root._R
                               color: U.withAlpha(root.glow, root.strength * 0.08) }
                GradientStop { position: 1.0; color: U.withAlpha(root.glow, 0.0) }
            }
            // rounded rectangle matching the panel
            startX: root._r; startY: 0
            PathLine { x: shape.width - root._r; y: 0 }
            PathArc  { x: shape.width; y: root._r; radiusX: root._r; radiusY: root._r }
            PathLine { x: shape.width; y: shape.height - root._r }
            PathArc  { x: shape.width - root._r; y: shape.height; radiusX: root._r; radiusY: root._r }
            PathLine { x: root._r; y: shape.height }
            PathArc  { x: 0; y: shape.height - root._r; radiusX: root._r; radiusY: root._r }
            PathLine { x: 0; y: root._r }
            PathArc  { x: root._r; y: 0; radiusX: root._r; radiusY: root._r }
        }
    }
}
