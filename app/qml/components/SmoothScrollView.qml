import QtQuick
import QtQuick.Controls.Basic
import NicheScope

// A ScrollView with the app's standard eased wheel scrolling baked in.
//
// The default per-notch momentum flick reads as a jerky jump on tall content,
// so the wheel is intercepted and contentY is animated toward a clamped target
// that accumulates across notches (OutCubic over durMed). Lifted from the
// hand-rolled copies the Search Archive / Niche Finder / Downloads pages grew
// so every page scrolls identically instead of each reinventing it.
//
// WheelHandler and NumberAnimation are not Items, so they don't disturb
// contentChildren — the page's own content Item stays the single content child.
ScrollView {
    id: root
    contentWidth: availableWidth
    clip: true

    property real _wheelTarget: 0

    // Wheel tuning. A page can override these; the defaults are the behaviour
    // every page already had.
    //   wheelStep     — px travelled per mouse-wheel NOTCH (angleDelta 120)
    //   wheelDuration — the glide for a single notch, in ms
    property real wheelStep: 120
    property int wheelDuration: Tokens.durMed

    // The trackpad path below moves contentY directly (no animation to
    // observe), so it keeps its own short-lived flag: `gliding` must stay true
    // for as long as the fingers are still feeding it deltas.
    property bool _pixelMoving: false
    Timer {
        id: pixelIdle
        interval: 120
        repeat: false
        onTriggered: root._pixelMoving = false
    }

    // True while the content is really moving: a wheel glide, a page jump, or
    // a drag / flick. Grids of rich cards bind this to their delegates so the
    // hover effects stand down while scrolling — see ArchiveVideoCard's
    // `scrollIdle`. Without it every card that slid under a resting pointer
    // started a 720 ms cover zoom, and that zoom re-renders the card's layered
    // thumbnail + mask on EVERY frame, which is what made long grids feel
    // stiff instead of smooth.
    readonly property bool gliding: wheelAnim.running || toTopAnim.running
                                    || _pixelMoving
                                    || (contentItem !== null && contentItem !== undefined
                                        && contentItem.moving === true)

    // Jump back to the top, eased. Called when the content underneath is
    // REPLACED rather than extended — turning a grid page, switching an archive
    // section — where leaving the viewport at the old scroll offset drops you
    // into the middle (or the end) of a page you haven't seen the start of.
    function toTop() {
        const fl = root.contentItem
        if (!fl) return
        wheelAnim.stop()
        root._wheelTarget = 0
        if (fl.contentY <= 0) return
        toTopAnim.stop()
        toTopAnim.from = fl.contentY
        toTopAnim.to = 0
        toTopAnim.start()
    }
    NumberAnimation {
        id: toTopAnim
        target: root.contentItem
        property: "contentY"
        duration: Tokens.durSlow
        easing.type: Easing.OutCubic
    }

    // Scroll so `item`'s top edge sits at the top of the viewport, eased. Used
    // where the thing being paged is a grid PARTWAY down a long page (the AI
    // Ideas reference grid): toTop() would throw the reader back to the page
    // heading, while leaving the offset alone drops them into the middle of a
    // page of cards they haven't seen the start of. `margin` is breathing room
    // above the item.
    function scrollToItem(item, margin) {
        const fl = root.contentItem
        if (!fl || !item) return
        const m = margin === undefined ? Tokens.space4 : margin
        // contentItem IS the flickable that holds the page's content Item, so
        // mapping into it gives a position already in content coordinates.
        const pos = item.mapToItem(fl.contentItem ? fl.contentItem : fl, 0, 0)
        const max = Math.max(0, fl.contentHeight - fl.height)
        const target = Math.max(0, Math.min(max, pos.y - m))
        wheelAnim.stop()
        root._wheelTarget = target
        if (Math.abs(fl.contentY - target) < 1) return
        toTopAnim.stop()
        toTopAnim.from = fl.contentY
        toTopAnim.to = target
        toTopAnim.start()
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (ev) => {
            // Let horizontal / trackpad-only pans reach nested content.
            if (ev.angleDelta.y === 0 && ev.pixelDelta.y === 0) return
            const fl = root.contentItem
            if (!fl) return
            const max = Math.max(0, fl.contentHeight - fl.height)

            // ── v3.52: honour the device instead of flattening every event ──
            // A trackpad (and a "smooth scrolling" mouse) sends many small
            // pixelDelta events that ALREADY carry the user's momentum. The old
            // handler turned each one into a fixed 120 px animated jump, so one
            // flick became a stack of rubbery 190 ms hops that kept restarting
            // before they finished — the "stiff / not quite laggy" scroll on
            // long grids. Pixel deltas are now applied directly: no second
            // animation on top of the one the OS already made.
            if (ev.pixelDelta.y !== 0) {
                wheelAnim.stop()
                const y = Math.max(0, Math.min(max, fl.contentY - ev.pixelDelta.y))
                fl.contentY = y
                root._wheelTarget = y
                root._pixelMoving = true
                pixelIdle.restart()
                return
            }

            // A real wheel: scale by the number of notches actually reported
            // (angleDelta is a multiple of 120 — 240 on some mice is TWO).
            const notches = ev.angleDelta.y / 120
            const base = wheelAnim.running ? root._wheelTarget : fl.contentY
            const target = Math.max(0, Math.min(max, base - notches * root.wheelStep))
            if (Math.abs(target - base) < 0.5) return

            // Duration follows the distance, so the glide keeps a steady speed
            // instead of re-decelerating from zero on every notch — that is
            // what makes a fast spin of the wheel feel like one motion.
            wheelAnim.stop()
            root._wheelTarget = target
            wheelAnim.from = fl.contentY
            wheelAnim.to = target
            wheelAnim.duration = Math.max(80, Math.min(300,
                Math.abs(target - fl.contentY) * (root.wheelDuration / root.wheelStep)))
            wheelAnim.start()
        }
    }
    NumberAnimation {
        id: wheelAnim
        target: root.contentItem
        property: "contentY"
        // overridden per event by the handler above (distance-proportional)
        duration: Tokens.durMed
        easing.type: Easing.OutCubic
    }
}
