import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// A soft, diffuse glow — a light that seems to bleed from behind a card.
//
// Perf rewrite: this used to render a circle into an offscreen layer and run
// it through MultiEffect (blurMax 64): two render-to-texture passes plus a
// heavy blur shader per blob, re-run whenever anything around it resized
// (window resize, rail slide). The blurred-circle *profile* is reproduced
// directly with a radial gradient on one Shape: same bright core, same soft
// falloff past the nominal size, zero offscreen passes.
//
// API unchanged: size / glow / strength / spread, anchored by the caller.
//   C.GlowBlob { anchors.right: parent.right; anchors.top: parent.top
//                anchors.rightMargin: -40; anchors.topMargin: -60 }
Item {
    id: root
    property real size: 300
    property color glow: Theme.primary
    property real strength: Theme.isDark ? 0.16 : 0.11
    // How far the halo spreads past `size` (1.35 ≈ the old blur reach).
    property real spread: 1.35

    width: size
    height: size

    // reach of the old blur beyond the circle edge, in px
    readonly property real _pad: 64 * spread
    readonly property real _R: size / 2 + _pad

    Shape {
        id: shape
        anchors.centerIn: parent
        width: root._R * 2
        height: root._R * 2
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root._R; centerY: root._R; centerRadius: root._R
                focalX: root._R; focalY: root._R; focalRadius: 0
                // positions are distances from the centre as a share of _R
                GradientStop { position: 0.0; color: U.withAlpha(root.glow, root.strength * 0.72) }
                GradientStop { position: Math.max(0.05, (root.size / 2 - root._pad * 0.7) / root._R)
                               color: U.withAlpha(root.glow, root.strength * 0.50) }
                GradientStop { position: (root.size / 2) / root._R
                               color: U.withAlpha(root.glow, root.strength * 0.26) }
                GradientStop { position: (root.size / 2 + root._pad * 0.5) / root._R
                               color: U.withAlpha(root.glow, root.strength * 0.08) }
                GradientStop { position: 1.0; color: U.withAlpha(root.glow, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: shape.width; y: 0 }
            PathLine { x: shape.width; y: shape.height }
            PathLine { x: 0; y: shape.height }
            PathLine { x: 0; y: 0 }
        }
    }
}
