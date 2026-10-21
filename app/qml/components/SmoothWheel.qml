import QtQuick
import NicheScope

// SmoothWheel — eased wheel scrolling for any Flickable / ListView.
//
// SmoothScrollView does this for a ScrollView; a ListView (the AI Chat thread,
// its rail) never had it, so every wheel notch was Qt's default momentum flick:
// a jump, then a coast, with delegates being built mid-coast. Here each notch
// adds `step` px to a target that ACCUMULATES while the animation runs, and
// contentY eases toward it (OutCubic). Fast spins stay fast, single notches
// glide, and nothing overshoots the ends.
//
// Touchpads send pixelDelta: those follow the fingers 1:1 (no easing — an
// eased touchpad feels laggy), clamped the same way.
//
// Put it INSIDE the flickable:   ListView { id: list; C.SmoothWheel { flick: list } }
// `moved(up)` fires on each wheel event so a chat can stop following the
// stream the moment the reader scrolls up.
Item {
    id: root
    property Flickable flick: parent
    property real step: 110
    property int duration: 260
    signal moved(bool up)

    readonly property real _min: flick ? flick.originY - flick.topMargin : 0
    readonly property real _max: flick
        ? Math.max(_min, flick.originY + flick.contentHeight + flick.bottomMargin - flick.height)
        : 0
    property real _target: 0

    function _clamp(v) { return Math.max(root._min, Math.min(root._max, v)) }

    // Anything else moving the view (positionViewAtEnd while streaming, a
    // scrollbar drag) owns contentY — stop easing so the two never fight.
    function cancel() { anim.stop() }

    WheelHandler {
        target: null
        parent: root.flick
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (ev) => {
            const fl = root.flick
            if (!fl) return
            if (ev.pixelDelta.y !== 0) {            // touchpad: direct
                anim.stop()
                fl.cancelFlick()
                fl.contentY = root._clamp(fl.contentY - ev.pixelDelta.y)
                root._target = fl.contentY
                root.moved(ev.pixelDelta.y > 0)
                return
            }
            if (ev.angleDelta.y === 0) return
            fl.cancelFlick()
            const notches = ev.angleDelta.y / 120
            const base = anim.running ? root._target : fl.contentY
            root._target = root._clamp(base - notches * root.step)
            anim.stop()
            anim.from = fl.contentY
            anim.to = root._target
            anim.start()
            root.moved(ev.angleDelta.y > 0)
        }
    }
    NumberAnimation {
        id: anim
        target: root.flick
        property: "contentY"
        duration: root.duration
        easing.type: Easing.OutCubic
    }
}
