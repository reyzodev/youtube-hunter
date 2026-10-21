import QtQuick
import QtQuick.Effects

// v3.27: clips its children to a ROUNDED rectangle.
//
// Why: `clip: true` only ever cuts to the item's square bounding box, so
// anything that fills or travels inside a rounded key (a progress fill, a
// shimmer, a hover shine) pokes out past the rounded corners as a pale
// square-cornered slab. This masks the children with the exact rounded shape
// instead.
//
//     C.RoundClip {
//         anchors.fill: parent
//         radius: face.radius
//         active: sweep.visible        // only pay for the layer while needed
//         Rectangle { id: sweep; ... }
//     }
//
// `active: false` drops the layer and falls back to a plain square clip, so
// keep it bound to "is anything inside visible right now".
Item {
    id: root
    property real radius: 0
    property bool active: true
    default property alias content: inner.data

    // the shape - never drawn, only sampled by the mask
    Rectangle {
        id: shape
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: root.active
        layer.smooth: true
    }

    Item {
        id: inner
        anchors.fill: parent
        clip: !root.active
        layer.enabled: root.active
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shape
            // a soft threshold keeps the masked corner anti-aliased instead
            // of a stair-stepped 1-bit edge
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
}
