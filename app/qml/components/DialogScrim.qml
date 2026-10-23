import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Window
import NicheScope
import "../Utils.js" as U

// The backdrop behind every modal dialog: the app behind it goes softly blurred
// and dimmed instead of just darkening.
//
// Drop it in as a dialog's `Overlay.modal` (the property Qt uses to build the
// dim layer for a modal popup):
//
//     Overlay.modal: C.DialogScrim { }
//
// How the blur works: the window's rounded shell is captured through a
// ShaderEffectSource and that texture — not the live item — is what gets
// blurred. The shell is a SIBLING of Overlay.overlay (both are children of the
// window's contentItem), so there is no recursive-source problem.
//
// Two deliberate constraints:
//   * the snapshot is only `live` while the scrim is actually on screen, so the
//     app is not paying for a full-window texture copy every frame while no
//     dialog is open. Qt fades a modal overlay in and out through OPACITY (it
//     leaves `visible` alone), so that — not `visible` — is what gates it.
//   * the blur radius and the dim both animate in, so the background settles
//     rather than snapping — matching how the dialog card itself scales in.
Item {
    id: root

    // The scrim covers the whole window, so for as long as a dialog is open the
    // pointer sits over an item that would otherwise declare no cursor at all —
    // and a window with no cursor declared under the pointer can be left drawing
    // nothing. A modal backdrop is never an interactive surface, so the arrow is
    // both the safe and the correct shape here. (Qt 6's QML `Item` has no
    // `cursor` property, so this has to be a cursor-only MouseArea:
    // `acceptedButtons: Qt.NoButton` means it never swallows a click.)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.ArrowCursor
    }

    // How far the background blurs, in pixels. Tweak this ONE number to taste —
    // it is the single knob for every modal backdrop in the app (each dialog
    // opts in with `Overlay.modal: C.DialogScrim { }`).
    //
    // Why it maps onto blurMax: 64 rather than onto itself: MultiEffect's blur
    // pipeline works in downsample LEVELS, and it only has good levels at
    // blurMax 8 / 16 / 32 / 64. Setting blurMax to a small number (the previous
    // attempt used the pixel value directly) lands on the coarsest, weakest
    // level, which is exactly why the backdrop read as flat glass instead of a
    // real blur. Pinning blurMax at 64 and expressing the request as a fraction
    // of it keeps the good level and makes the pixel number actually mean
    // something.
    // Deliberately light (3-4px): the point is to push the page back a step so
    // the dialog reads as the foreground, NOT to erase it. A heavy blur made the
    // app behind a modal unrecognisable, which is disorienting rather than
    // focusing — you lose the sense of where the dialog opened from.
    property real blurPx: 3.5
    property real dimOpacity: Theme.isDark ? 0.42 : 0.30
    // v3.36: the part of the shell to blur, in shell coordinates. An empty rect
    // (the default) means the whole shell — what every modal dialog wants. The
    // connection gate covers the page area only (the title bar stays live), so
    // it passes the strip below the title bar here.
    property rect sourceRect: Qt.rect(0, 0, 0, 0)

    // True while this scrim is on screen at all. See the note above on why this
    // keys off opacity.
    readonly property bool onScreen: opacity > 0.01

    // Qt shows/hides a modal overlay by WRITING opacity 1 / 0 through
    // QQmlProperty precisely so a QML Behavior can animate it — without one
    // the backdrop snapped on and, worse, vanished in a single frame while the
    // dialog was still animating out, which read as a stutter on every close.
    Behavior on opacity {
        NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
    }

    // A frozen backdrop is still re-captured once per open, otherwise the
    // second open would show the app as it looked the first time.
    onOnScreenChanged: if (onScreen && frozen) snapshot.scheduleUpdate()

    // The item to blur. Main.qml publishes its rounded shell as `blurSource`;
    // if that is ever missing this degrades to the plain dim layer alone.
    readonly property Item _src: {
        var w = Window.window
        return (w && w.blurSource) ? w.blurSource : null
    }

    // 0 → 1 as the scrim comes up. Qt fades the whole scrim item's opacity for
    // us, but the blur strength has to be animated by hand so the background
    // defocuses progressively instead of appearing already-blurred.
    property real progress: 0
    Component.onCompleted: progress = 1
    Behavior on progress {
        NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
    }

    // Set by a dialog whose backdrop does not need to follow the app behind it.
    // `live: true` re-renders the captured window into a texture EVERY frame,
    // which is the single most expensive thing on screen while a heavy dialog is
    // open. At the Support card's 18 px blur + 0.58 dim, a frozen frame is
    // indistinguishable from a live one, and the app behind it is not the thing
    // the user is looking at — so that card asks for a still.
    property bool frozen: false

    ShaderEffectSource {
        id: snapshot
        anchors.fill: parent
        sourceItem: root._src
        sourceRect: root.sourceRect
        live: root.onScreen && !root.frozen
        hideSource: false
        recursive: false
        visible: root._src !== null

        layer.enabled: snapshot.visible
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 64
            blur: Math.min(1.0, (root.blurPx / 64) * root.progress)
            // Pushes the radius past what blurMax alone reaches, so a heavy
            // request really does soften the page rather than plateauing.
            blurMultiplier: 0.4
            // Give the effect padding to sample into, otherwise the blur smears
            // at the window edge instead of softening cleanly.
            autoPaddingEnabled: true
        }
    }

    // dim layer over the blur
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 1)
        opacity: root.dimOpacity * root.progress
    }
}
