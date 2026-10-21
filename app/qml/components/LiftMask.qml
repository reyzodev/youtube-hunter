import QtQuick

// Hit-test mask for anything that moves itself on hover (the "lift" cards).
//
// Why: a HoverHandler (or a Control's own `hovered`) tests the pointer against
// its item AFTER the item's transform. Lift a card 2-3px on hover and its hit
// box moves with it, so a pointer resting near the bottom edge is suddenly
// outside -> unhover -> the card drops back -> hovered again -> lifts... Qt
// re-checks hover every frame, so it loops for as long as the mouse sits
// there: a flickering card. This mask makes the item answer for the union of
// where it IS and where it WAS (its resting footprint), which gives the hover
// natural hysteresis: once hovered, moving never un-hovers it.
//
//     containmentMask: C.LiftMask { target: card; dy: lift.y }
//
// dx / dy are the current Translate offsets (negative = moved up / left).
QtObject {
    property Item target: null
    property real dx: 0
    property real dy: 0

    function contains(point: point) : bool {
        if (!target)
            return false
        var x0 = Math.min(0, -dx), x1 = Math.max(target.width, target.width - dx)
        var y0 = Math.min(0, -dy), y1 = Math.max(target.height, target.height - dy)
        return point.x >= x0 && point.x <= x1 && point.y >= y0 && point.y <= y1
    }
}
