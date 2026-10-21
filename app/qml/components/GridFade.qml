import QtQuick
import NicheScope
import "../Utils.js" as U

// A wash of the SIGNAL colour bleeding down from the top of a page — the light
// that ties a screen to the accent picked in Settings.
//
// This used to be a faint square grid. A grid and a coloured wash compete for
// the same few pixels above the fold: the lines cut the glow into squares, so
// the tint read as dirt on the background instead of as light falling on it.
// The grid is gone.
//
// WHY NOT A BLURRED BLOB: the obvious way to paint this is a GlowBlob (a circle
// through MultiEffect). That is a shader effect — it needs a working GPU, it
// costs a render-to-texture per page, and it does not render at all under the
// offscreen platform this UI is verified with. Two ellipses filled with plain
// gradients read the same, cost nothing, and are a material every Qt backend
// (including software) supports.
//
// Purely decorative: it ignores the mouse and sits behind the content.
Item {
    id: root
    // Core strength of the light. A wash, not a paint — the veil below carries
    // the body, these two ellipses carry the hotspot.
    property real strength: Theme.isDark ? 0.40 : 0.26
    property color glow: Theme.primary
    // v4: the second light — the accent's partner hue — so the wash reads as
    // an aurora instead of a single tinted fog.
    property color glow2: Theme.primary_deep
    // Slow ambient drift of the two hotspots. Runs only while the page is on
    // screen (StackLayout hides the others), and is so slow it is felt, not
    // watched. Set false for a perfectly still wash.
    property bool ambient: App.ambientMotion !== false
    z: -1
    clip: true

    // Perf: the drift used to be a 60 fps SequentialAnimation that never
    // stopped, on every page — the window could never go idle, so the CPU/GPU
    // stayed busy even with nothing happening. The motion is a ~100 px glide of
    // soft gradients over 14 s (≈ 7 px/s), so a 12 fps clock is visually
    // identical while asking for one fifth of the frames. Same sine path, same
    // period; pauses when the page is hidden or the app is in the background.
    property real drift: 0.5
    property real _phase: 0
    Timer {
        interval: 83
        repeat: true
        running: root.ambient && root.visible && Tokens.appActive
        onTriggered: {
            root._phase = (root._phase + interval / (Tokens.durAmbient * 2)) % 1
            root.drift = 0.5 + 0.5 * Math.sin(root._phase * Math.PI * 2)
        }
    }

    // ── the broad, soft part of the light ──
    // Wider than the page so its curved edges stay off-screen; only the dome
    // above the fold is ever seen.
    Rectangle {
        width: Math.max(980, root.width * 1.2)
        height: Math.max(320, root.height * 0.9)
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -height * 0.58
        gradient: Gradient {
            GradientStop { position: 0.0; color: U.withAlpha(root.glow, root.strength) }
            GradientStop { position: 0.55; color: U.withAlpha(root.glow, root.strength * 0.28) }
            GradientStop { position: 1.0; color: U.withAlpha(root.glow, 0.0) }
        }
    }

    // ── the hotspot ──
    // A narrower, stronger dome centred above the header, so the light has a
    // source rather than being a flat band.
    Rectangle {
        width: Math.max(460, root.width * 0.44)
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -root.width * 0.14 + (root.drift - 0.5) * root.width * 0.10
        anchors.top: parent.top
        anchors.topMargin: -height * 0.66
        gradient: Gradient {
            GradientStop { position: 0.0; color: U.withAlpha(root.glow, root.strength * 0.62) }
            GradientStop { position: 0.6; color: U.withAlpha(root.glow, root.strength * 0.16) }
            GradientStop { position: 1.0; color: U.withAlpha(root.glow, 0.0) }
        }
    }

    // ── the partner hotspot ── accent2, opposite side, drifting the other way
    Rectangle {
        width: Math.max(380, root.width * 0.36)
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.width * 0.20 - (root.drift - 0.5) * root.width * 0.12
        anchors.top: parent.top
        anchors.topMargin: -height * 0.70
        gradient: Gradient {
            GradientStop { position: 0.0; color: U.withAlpha(root.glow2, root.strength * 0.50) }
            GradientStop { position: 0.6; color: U.withAlpha(root.glow2, root.strength * 0.12) }
            GradientStop { position: 1.0; color: U.withAlpha(root.glow2, 0.0) }
        }
    }

    // ── the vertical veil ──
    // Carries the colour down past the header so the page does not go flat the
    // moment the domes end.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(200, parent.height * 0.78)
        gradient: Gradient {
            GradientStop { position: 0.0; color: U.withAlpha(root.glow, root.strength * 0.34) }
            GradientStop { position: 0.45; color: U.withAlpha(root.glow, root.strength * 0.11) }
            GradientStop { position: 1.0; color: U.withAlpha(root.glow, 0.0) }
        }
    }
}
