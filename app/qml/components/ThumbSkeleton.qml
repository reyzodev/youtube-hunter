import QtQuick
import NicheScope
import "../Utils.js" as U

// A loading placeholder for a thumbnail that hasn't arrived yet: a muted panel
// with a soft highlight band that travels across it, plus a gentle breathing
// pulse underneath.
//
// Same visual language as the quality picker's skeleton rows and the download
// button's progress shimmer — "something is moving, it's working" — so a grid
// filling in reads as loading rather than broken.
//
// Drop it behind an Image and drive `active` off the image's status:
//
//   C.ThumbSkeleton {
//       anchors.fill: parent
//       active: thumbImg.status !== Image.Ready
//       topLeftRadius: card.radius; topRightRadius: card.radius
//   }
//
// The corner radii are individually settable because a card's thumbnail is
// rounded only along the panel's top edge.
Item {
    id: root
    property bool active: true
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    // Optional glyph shown in the middle once the sweep is running, so an empty
    // cell still says what it is going to be.
    property string glyph: ""
    // v3.54: pause the sweep/pulse while the surrounding grid is scrolling.
    // The placeholder stays visible; only its two infinite animations stop, so
    // a grid of loading cards stops asking for a repaint on every frame.
    property bool animate: true

    visible: opacity > 0
    // Fade the whole skeleton out when the image lands rather than snapping it
    // away — the crossfade is what makes the swap feel intentional.
    // v3.53: 140 ms, not 190. A grid of 24 of these crossfading at once was
    // half a second of everything looking "still loading".
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        id: base
        anchors.fill: parent
        color: Theme.surface_high
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        // Clipped so the travelling band stops at the rounded edge instead of
        // sliding out over the card.
        clip: true

        // A soft breathing pulse under the sweep: on a very wide cell the band
        // spends a moment off-screen, and without this the tile looks dead in
        // that gap.
        SequentialAnimation on opacity {
            running: root.active && root.visible && root.animate
            loops: Animation.Infinite
            NumberAnimation { to: 0.72; duration: 900; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
        }

        // the travelling highlight band
        Rectangle {
            id: sweep
            width: Math.max(60, base.width * 0.45)
            height: base.height * 2
            y: -base.height / 2
            // Angled slightly, the way a highlight sweep reads on a surface
            // rather than a bar sliding past.
            rotation: 14
            transformOrigin: Item.Center
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.on_surface, 0.0) }
                GradientStop { position: 0.5
                    color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.09 : 0.07) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.on_surface, 0.0) }
            }
            SequentialAnimation on x {
                running: root.active && root.visible && root.animate
                loops: Animation.Infinite
                NumberAnimation {
                    from: -sweep.width
                    to: base.width + sweep.width
                    duration: 1250
                    easing.type: Easing.InOutQuad
                }
                // A short beat at the end so consecutive passes are readable as
                // separate sweeps instead of one continuous strobe.
                PauseAnimation { duration: 320 }
            }
        }

        IconGlyph {
            anchors.centerIn: parent
            visible: root.glyph !== ""
            name: root.glyph
            size: 22
            glyphColor: U.withAlpha(Theme.outline, 0.55)
        }
    }
}
