import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.41.2 — tooltip redesign ("Ink").
//
//            ▲                 caret points at the control's centre, even
//   ╭──────────────────╮       when the bubble is clamped at a window edge
//   │  Clear all  [Del] │      optional keycap chip (`shortcut`)
//   ╰──────────────────╯       soft layered shadow, 1px top light
//
// Light theme: near-black ink. Dark theme: elevated graphite (one step above
// every surface), so the tip reads as floating in both, never as a hole.
// Long tips wrap at 280px instead of running across the window. It grows out
// of the caret (scale 0.94 → 1 + a 4px drift away from the control).
//
// History — why this is an item and not a ToolTip/Popup:
// It used to be a `ToolTip`, i.e. a Popup — a second top-level window. Two
// problems came with that, and both were real, reproducible bugs:
//
//  1. THE HOVER BLINK. A Popup appearing takes a transient mouse grab, so the
//     control under the pointer gets a leave event: its `hovered` drops, any
//     `Behavior on color` bound to it animates back, the tip hides, the pointer
//     is "over" the control again, and the whole cycle repeats. That reads as
//     the button flickering every time the mouse lands on it.
//
//  2. THE VANISHING CURSOR. A popup window that declares no cursor can leave
//     Windows drawing NO pointer at all — the app keeps working, the arrow just
//     disappears. The player's control bar sits at the bottom of its card, so
//     Qt flipped the tip ABOVE the button to keep it on screen — directly under
//     the pointer — and the cursor vanished over the player controls.
//
// Drawing the tip as a plain item removes both causes outright: nothing is
// grabbed, nothing leaves, and there is no cursor-less window in the scene.
//
// The API is unchanged (`visible`, `delay`, `text`), so every existing call site
// keeps working — only where the tip lives and how it is drawn changed.

Item {
    id: root

    property string text: ""
    // Hover-intent delay: long enough that a tip does not flash while the
    // pointer is only passing over on its way somewhere else.
    property int delay: 400
    // The control this tip describes — the item it was DECLARED in, captured
    // before we reparent onto the overlay. Holding the anchor is what lets the
    // tip escape an ancestor's `clip` (the player's stage, a scrolling page)
    // while still pointing at the right control.
    property Item anchor: null
    // Set once the delay has elapsed. `visible` stays the caller's binding, so a
    // caller that wants the tip gone the instant hover ends still gets that.
    property bool shown: false
    // Optional key hint drawn as a keycap chip after the text, e.g. "Ctrl+K".
    property string shortcut: ""
    // Prefer placing the tip ABOVE the control (falls back below when there is
    // no room). The video player's dock sits at the bottom of its card, so a
    // tip below it lands outside the card, over the dimmed backdrop.
    property bool preferAbove: false
    // Optional item to keep the tip INSIDE (e.g. the player card). When set,
    // its rect is used as the bounds instead of the whole window.
    property Item boundsItem: null
    // ...or name it: the nearest ANCESTOR of the anchor with this objectName.
    property string boundsName: ""
    function _resolveBounds() {
        if (boundsItem) return boundsItem
        if (boundsName === "" || !anchor) return null
        let it = anchor.parent
        while (it) {
            if (it.objectName === boundsName) return it
            it = it.parent
        }
        return null
    }
    // Set by _reposition(): true when the tip had to flip ABOVE its control.
    property bool _above: false
    // Where the caret sits along the bubble (the control's centre, clamped).
    property real _caretX: width / 2
    readonly property int _maxTextW: 280

    // A tooltip must never swallow a click meant for the control underneath.
    enabled: false
    // Above the page (which uses z up to 999) and above any popup inside the
    // overlay (the overlay numbers those from 1 upward), so a tip that belongs
    // to the video player is not painted under the player's own card.
    z: 10000

    width: bubble.width
    height: bubble.height
    implicitWidth: bubble.width
    implicitHeight: bubble.height

    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.shown ? 150 : 90; easing.type: Easing.OutCubic } }

    onVisibleChanged: {
        if (visible) {
            // first hover inside a popup: this is where the tip finally finds
            // the window's overlay (see _adopt)
            root._adopt()
            // Place it BEFORE the delay elapses, so the tip is already in the
            // right spot on the frame it fades in instead of jumping there.
            root._reposition()
            showTimer.restart()
        } else {
            showTimer.stop()
            root.shown = false
        }
    }

    Timer {
        id: showTimer
        interval: Math.max(0, root.delay)
        onTriggered: root.shown = true
    }

    // ── placement ──
    // Below the control by preference, flipped above it when the tip would run
    // off the bottom, and clamped horizontally so a control at the window edge
    // never pushes its own tip out of view.
    //
    // This is done IMPERATIVELY, not as a binding. `mapToItem` records no
    // dependency on the items it walks — a binding that calls it is evaluated
    // once and then never again. Measured: moving the control afterwards left
    // the tip exactly where it was. Worse, that single evaluation can happen
    // before the scene has laid out, in which case the mapping is garbage and
    // the tip is pinned in a corner for good. So the position is computed by
    // _reposition() and kept current by a short timer that only runs while the
    // tip is on screen.
    x: 0
    y: 0

    // Re-place once the bubble has its real size: the first _reposition() can
    // run while height is still 0, and the tip then grows past the edge.
    onWidthChanged: if (root.visible) root._reposition()
    onHeightChanged: if (root.visible) root._reposition()

    // The bounds come from the WINDOW, not from the parent. The parent is the
    // window overlay and is normally the same size — but the overlay is a Qt
    // Quick Controls object whose geometry settles later than the tip's, so
    // reading it can hand back a stale 0 and put the tip off-screen.
    readonly property real _boundsW: {
        const w = Window.window
        if (w && w.width > 0) return w.width
        return parent && parent.width > 0 ? parent.width : 0
    }
    readonly property real _boundsH: {
        const w = Window.window
        if (w && w.height > 0) return w.height
        return parent && parent.height > 0 ? parent.height : 0
    }

    function _reposition() {
        if (!anchor || !parent) return
        // bounds rect in the overlay's coordinates: the window, or boundsItem
        let bx = 0, by = 0, bw = _boundsW, bh = _boundsH
        const bi = root._resolveBounds()
        if (bi && bi.width > 0 && bi.height > 0) {
            const tl = bi.mapToItem(parent, 0, 0)
            bx = tl.x; by = tl.y; bw = bi.width; bh = bi.height
        }
        const m = 8
        const px = anchor.mapToItem(parent, anchor.width / 2, 0).x
        const gap = 7
        const topY = anchor.mapToItem(parent, 0, 0).y
        const belowY = anchor.mapToItem(parent, 0, anchor.height + gap).y
        const aboveY = topY - height - gap
        const fitsBelow = bh <= 0 || belowY + height <= by + bh - m
        const fitsAbove = bh <= 0 || aboveY >= by + m
        let above = root.preferAbove ? (fitsAbove || !fitsBelow)
                                     : (!fitsBelow && fitsAbove)
        // neither side fits: take the side with more room
        if (!fitsAbove && !fitsBelow)
            above = (topY - by) > (by + bh - (topY + anchor.height))
        let vy = above ? aboveY : belowY
        let vx = px - width / 2
        if (bw > 0) vx = Math.max(bx + m, Math.min(bx + bw - width - m, vx))
        if (bh > 0) vy = Math.max(by + m, Math.min(by + bh - height - m, vy))
        root._above = above
        // keep the caret off the rounded corners
        root._caretX = Math.max(12, Math.min(width - 12, px - vx))
        root.x = vx
        root.y = vy
    }

    // While the tip is on screen, keep it attached to its control: the page
    // under it can scroll, the window can be resized, a layout can settle.
    // 100ms is far cheaper than a frame and the tip lives for a second or two.
    Timer {
        interval: 100
        repeat: true
        running: root.shown
        onTriggered: root._reposition()
    }
    onShownChanged: if (shown) root._reposition()

    // ── capture the anchor, then move onto the overlay ──
    // The overlay is the window's own top layer: parenting there means no
    // ancestor's clip can cut the tip off (the player's stage clips, and so does
    // every scrolling page). `z` then lifts the tip above the page and above any
    // popup in the overlay, so a tip on a player button draws over the player's
    // own card rather than behind it.
    //
    // This has to be re-done LAZILY, not only at completion. A tip declared
    // inside a Popup (the Support card, every dialog with its own controls) is
    // built while the popup is still closed — its contentItem is not in the
    // window yet, so `Overlay.overlay` and `Window.window` are both null and
    // there is nothing to reparent onto. The tip then stayed a CHILD of its
    // button: drawn under the popup's own content (the web view, the panels),
    // clipped by the card, and positioned in the button's coordinate space. That
    // is the "tooltips don't show right" bug. `_adopt()` runs again on every
    // show, so the first hover after the popup opens puts the tip where it
    // belongs.
    function _adopt() {
        if (!root.anchor) return
        let host = null
        try { host = Overlay.overlay } catch (e) { host = null }
        if (!host) {
            const w = root.Window.window
            host = w ? w.contentItem : null
        }
        if (host && root.parent !== host) {
            root.parent = host
            root._reposition()
        }
    }

    Component.onCompleted: {
        root.anchor = root.parent
        root._adopt()
        root._reposition()
        // A tip declared already-visible (the first hover can land before this
        // object finishes completing) never sees a visible CHANGED signal, so
        // arm the timer here as well.
        if (root.visible) showTimer.restart()
    }

    readonly property color _ink: Theme.tooltip_bg
    readonly property color _edge: Theme.isDark ? U.withAlpha("#FFFFFF", 0.10) : U.withAlpha("#FFFFFF", 0.06)

    // ── visual ──
    Item {
        id: bubble
        width: body.width
        height: body.height
        // grow out of the caret, drift a few px away from the control
        transformOrigin: root._above ? Item.Bottom : Item.Top
        scale: root.shown ? 1 : 0.94
        y: root.shown ? 0 : (root._above ? 4 : -4)
        Behavior on scale { NumberAnimation { duration: root.shown ? 220 : 90; easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: root.shown ? 220 : 90; easing.type: Easing.OutQuint } }

        // soft layered shadow (cheap: three rounded rects, no blur pass)
        Repeater {
            model: 3
            Rectangle {
                required property int index
                x: -(index + 1) * 2
                y: -(index + 1) * 2 + 3 + index * 1.5
                width: body.width + (index + 1) * 4
                height: body.height + (index + 1) * 4
                radius: body.radius + (index + 1) * 2
                color: "#000000"
                opacity: (Theme.isDark ? 0.20 : 0.07) / (index + 1)
            }
        }

        // caret: a small rotated square tucked under the bubble's edge
        Rectangle {
            width: 9; height: 9
            rotation: 45
            antialiasing: true
            x: root._caretX - width / 2
            y: root._above ? body.height - width / 2 - 1.5 : -width / 2 + 1.5
            color: root._ink
            border.width: 1
            border.color: root._edge
        }

        Rectangle {
            id: body
            readonly property real padX: 11
            readonly property real padY: 7
            width: Math.ceil(content.width + padX * 2)
            height: Math.ceil(content.height + padY * 2)
            radius: 10
            color: root._ink
            border.width: 1
            border.color: root._edge

            // 1px of light along the top edge: reads as a lifted sheet
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(0, parent.width - parent.radius * 2)
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha("#FFFFFF", 0) }
                    GradientStop { position: 0.5; color: U.withAlpha("#FFFFFF", Theme.isDark ? 0.14 : 0.10) }
                    GradientStop { position: 1.0; color: U.withAlpha("#FFFFFF", 0) }
                }
            }

            // hide the bubble's own border where the caret joins it (no seam)
            Rectangle {
                x: root._caretX - 4.5
                y: root._above ? parent.height - 1.5 : 0
                width: 9; height: 1.5
                color: root._ink
            }

            Row {
                id: content
                anchors.centerIn: parent
                spacing: 8
                layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight

                // natural (unwrapped) width, to decide when to wrap
                C.AppText {
                    id: measure
                    visible: false
                    text: root.text
                    weight: Tokens.weightMedium
                    font.pixelSize: Tokens.fontCaption
                }
                C.AppText {
                    id: lbl
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(Math.ceil(measure.implicitWidth) + 1, root._maxTextW)
                    text: root.text
                    weight: Tokens.weightMedium
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.tooltip_fg
                    wrapMode: Text.Wrap
                    lineHeight: 1.3
                    horizontalAlignment: measure.implicitWidth > root._maxTextW
                                         ? (I18n.rtl ? Text.AlignRight : Text.AlignLeft)
                                         : Text.AlignHCenter
                    LayoutMirroring.enabled: false
                }
                // keycap
                Rectangle {
                    visible: root.shortcut !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18
                    width: Math.max(18, keyLbl.implicitWidth + 10)
                    radius: 5
                    color: U.withAlpha("#FFFFFF", Theme.isDark ? 0.08 : 0.10)
                    border.width: 1
                    border.color: U.withAlpha("#FFFFFF", Theme.isDark ? 0.12 : 0.14)
                    C.AppText {
                        id: keyLbl
                        anchors.centerIn: parent
                        text: root.shortcut
                        mono: true
                        weight: Tokens.weightMedium
                        font.pixelSize: Tokens.fontMicro
                        color: U.withAlpha(Theme.tooltip_fg, 0.72)
                    }
                }
            }
        }
    }
}
