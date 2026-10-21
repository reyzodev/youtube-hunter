import QtQuick
import NicheScope
import "." as C
import "../Utils.js" as U

// ═══════════════════════════════════════════════════════════════════════════
//  BlueprintStage — v3.16-p3: a smooth, non-blocking host for BlueprintPane
//
//  Why: BlueprintPane is ~4.5k lines with all four acts instantiated. Handing
//  it a new `idea` re-evaluated every binding and rebuilt every Repeater in
//  ONE synchronous pass on the GUI thread: the 2-3 s freeze when you moved
//  between ideas (the old skeleton veil froze along with it, mid-shimmer).
//
//  How: two Loaders, double-buffered. A new idea is built into the hidden
//  BACK pane with `asynchronous: true`, so Qt incubates it a slice per frame
//  and the window keeps painting. The front pane stays on screen under a
//  skeleton veil whose shimmer runs on the render thread (Animators), then
//  the panes swap, the old one is dropped (still under the veil), and the
//  veil lifts while the new pane plays its entrance.
//
//    * clicking several ideas quickly just restarts the back build: only the
//      last pick is ever finished.
//    * same idea, new data (a rebuilt blueprint): rebuilt the same way.
//    * same idea, only the star changed: flips `favOn`, no rebuild at all.
//
//  Public API = BlueprintPane's, so hosts swap the type name and keep going:
//    idea, regenerating, scroller, motion,
//    favorited / deleteRequested / regenerateRequested / copyRequested /
//    prompterRequested.
//    `busy` is true while a pane is being built (hosts may read it).
// ═══════════════════════════════════════════════════════════════════════════
Item {
    id: stage

    property var idea: ({})
    property bool regenerating: false
    property var scroller: null
    // false → no fades (the app's "reduce motion"); the build is still async.
    property bool motion: true

    signal favorited(int ideaId)
    signal deleteRequested(int ideaId)
    signal regenerateRequested(int ideaId)
    signal copyRequested(string text)
    signal prompterRequested(int ideaId)

    readonly property bool busy: _building
    // The pane on screen (null before the first build lands).
    readonly property var pane: _frontL ? _frontL.item : null

    // ── internals ──
    property int _front: 0                 // 0 → paneA is on screen, 1 → paneB
    readonly property var _frontL: _front === 0 ? paneA : paneB
    readonly property var _backL: _front === 0 ? paneB : paneA
    property bool _building: false
    property bool _swapPending: false
    property string _frontKey: ""          // content fingerprint of the front pane
    property string _backKey: ""
    property int _frontId: 0

    // Holds the old height while the next pane builds; a fixed skeleton
    // height for the very first build, when there is nothing to hold.
    implicitHeight: pane ? pane.implicitHeight : (_building ? 620 : 0)

    function _idOf(x) { return (x && x.id) ? x.id : 0 }
    // Everything but the star: two ideas with the same key render the same.
    function _keyOf(x) {
        try {
            return JSON.stringify(x, function(k, v) { return k === "isFavorite" ? undefined : v })
        } catch (e) {
            return String(Math.random())       // unstringifiable → always rebuild
        }
    }

    onIdeaChanged: _route()
    Component.onCompleted: _route()
    onVisibleChanged: if (visible && _swapPending) _doSwap()

    function _route() {
        var a = stage.idea || ({})
        var nid = _idOf(a)
        if (nid === 0) {
            // Nothing selected: the host hides us. Drop any half-built pane,
            // keep the last one (re-binding it to {} costs a full rebind).
            _cancelBuild()
            _lowerVeil()
            return
        }
        var key = _keyOf(a)
        if (stage.pane && nid === _frontId && key === _frontKey) {
            // Same blueprint (maybe re-starred): no rebuild.
            _cancelBuild()
            stage.pane.favOn = a.isFavorite === true
            _lowerVeil()
            return
        }
        if (_building && key === _backKey) return     // already building exactly this
        _build(a, key)
    }

    function _build(a, key) {
        // A drop of the previous front may still be queued on the loader we
        // are about to reuse: do it now so it can't kill the new build.
        if (dropTimer.running) { dropTimer.stop(); _dropOld() }
        _swapPending = false
        _building = true
        _backKey = key
        _raiseVeil()
        var L = _backL
        L.source = ""                       // cancels an in-flight incubation
        L.setSource(Qt.resolvedUrl("BlueprintPane.qml"), {
            idea: a,
            scroller: stage.scroller
        })
    }

    function _cancelBuild() {
        if (!_building) return
        _building = false
        _swapPending = false
        _backL.source = ""
    }

    function _onLoaded(L) {
        if (L !== _backL || !_building || !L.item) return
        var it = L.item
        it.regenerating = Qt.binding(function() { return stage.regenerating && stage._frontL === L })
        it.scroller = Qt.binding(function() { return stage.scroller })
        it.favorited.connect(stage.favorited)
        it.deleteRequested.connect(stage.deleteRequested)
        it.regenerateRequested.connect(stage.regenerateRequested)
        it.copyRequested.connect(stage.copyRequested)
        it.prompterRequested.connect(stage.prompterRequested)
        _swapPending = true
        // wait for the veil to be fully up (and for the page to be on screen)
        if (!veilIn.running && stage.visible) _doSwap()
    }

    function _doSwap() {
        if (!_swapPending) return
        _swapPending = false
        _building = false
        var nb = _backL
        _front = 1 - _front                 // nb is now the front
        _frontKey = _backKey
        _frontId = _idOf(nb.item ? nb.item.idea : null)
        if (nb.item) {
            // replay the entrance now that it is actually visible
            nb.item._lastId = -1
            nb.item._primeForIdea()
        }
        // drop the old pane a beat later, still under the veil
        dropTimer.restart()
    }

    function _dropOld() {
        if (!_building) _backL.source = ""
        _lowerVeil()
    }

    // ── veil ──
    function _raiseVeil() {
        veilOut.stop()
        veil.visible = true
        if (!stage.motion) { veil.opacity = 1; return }
        if (veil.opacity < 0.99) veilIn.restart()
    }
    function _lowerVeil() {
        if (!veil.visible) return
        veilIn.stop()
        if (!stage.motion) { veil.opacity = 0; veil.visible = false; return }
        veilOut.restart()
    }

    Timer {
        id: dropTimer
        interval: 40
        onTriggered: stage._dropOld()
    }

    Loader {
        id: paneA
        width: stage.width
        asynchronous: true
        // only the front pane is drawn / clickable; the back one is laid out
        // (opacity 0, not invisible) so it arrives fully polished
        opacity: stage._front === 0 ? 1 : 0
        enabled: stage._front === 0
        z: stage._front === 0 ? 1 : 0
        onLoaded: stage._onLoaded(paneA)
    }
    Loader {
        id: paneB
        width: stage.width
        asynchronous: true
        opacity: stage._front === 1 ? 1 : 0
        enabled: stage._front === 1
        z: stage._front === 1 ? 1 : 0
        onLoaded: stage._onLoaded(paneB)
    }

    // ── the veil: page-coloured, a blueprint-shaped skeleton with a sweep ──
    // Its fades and the shimmer are Animators, so they keep moving on the
    // render thread even if the GUI thread hitches.
    Item {
        id: veil
        z: 1000
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(320, Math.min(stage.height, 620))
        opacity: 0
        visible: false

        OpacityAnimator {
            id: veilIn
            target: veil
            to: 1
            duration: 120
            easing.type: Easing.OutCubic
            onFinished: if (stage._swapPending && stage.visible) stage._doSwap()
        }
        OpacityAnimator {
            id: veilOut
            target: veil
            to: 0
            duration: 260
            easing.type: Easing.InOutCubic
            onFinished: veil.visible = false
        }

        // swallow clicks while it is up
        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons }

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusXl
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.background }
                GradientStop { position: 0.82; color: Theme.background }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.background, 0) }
            }
        }

        Column {
            id: skel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space5
            spacing: Tokens.space3
            readonly property color bar: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.06)
            Row {
                spacing: Tokens.space4
                layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                width: skel.width
                Rectangle { width: 64; height: 64; radius: 32; color: skel.bar }
                Column {
                    spacing: Tokens.space2
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { width: 110; height: 12; radius: 6; color: skel.bar }
                    Rectangle { width: Math.min(skel.width * 0.55, 460); height: 22; radius: 8; color: skel.bar }
                }
            }
            Item { width: 1; height: Tokens.space2 }
            Row {
                spacing: Tokens.space2
                layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                width: skel.width
                Repeater { model: 4; Rectangle { width: 96; height: 30; radius: 15; color: skel.bar } }
            }
            Item { width: 1; height: Tokens.space2 }
            Repeater {
                model: [1.0, 0.92, 0.97, 0.7, 0.88, 0.6]
                Rectangle {
                    width: skel.width * modelData; height: 12; radius: 6; color: skel.bar
                    x: I18n.rtl ? skel.width - width : 0
                }
            }
            Item { width: 1; height: Tokens.space2 }
            Row {
                spacing: Tokens.space3
                Repeater {
                    model: 3
                    Rectangle { width: (skel.width - Tokens.space3 * 2) / 3; height: 92; radius: Tokens.radiusLg; color: skel.bar }
                }
            }
        }

        // small "loading" read-out under the skeleton, with a spinning ring
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: skel.bottom
            anchors.topMargin: Tokens.space5
            spacing: Tokens.space2
            layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
            Item {
                width: 18; height: 18
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: "transparent"
                    border.width: 2
                    border.color: U.withAlpha(Theme.primary, 0.22)
                }
                Item {
                    id: spinArc
                    anchors.fill: parent
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        color: Theme.primary
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -1
                    }
                    RotationAnimator on rotation {
                        running: veil.visible
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 800
                    }
                }
            }
            C.AppText {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Loading blueprint…")
                color: Theme.on_surface_var
            }
        }

        // shimmer sweep
        Item {
            anchors.fill: skel
            clip: true
            Rectangle {
                id: shim
                width: 160
                height: parent.height * 1.6
                y: -parent.height * 0.3
                rotation: 14
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.on_surface, 0) }
                    GradientStop { position: 0.5; color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.08) }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.on_surface, 0) }
                }
                XAnimator on x {
                    running: veil.visible && stage.motion
                    loops: Animation.Infinite
                    from: I18n.rtl ? skel.width : -200
                    to: I18n.rtl ? -200 : skel.width
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }
        }
    }
}
