import QtQuick
import NicheScope

// A single icon glyph that can spin cleanly in place.
//
// A RotationAnimation applied straight to an IconGlyph wobbles: IconGlyph is a
// Text sized to the glyph's font metrics, so its centre isn't the glyph's
// visual centre, and rotating about the box centre makes it orbit. This wraps
// the glyph in a fixed size×size box and rotates the WRAPPER about its middle,
// so the glyph turns on the spot.
Item {
    id: root
    property string name: ""
    property int size: 16
    property color glyphColor: Theme.on_surface_var
    property bool spinning: false
    property bool fill: false

    implicitWidth: size
    implicitHeight: size
    transformOrigin: Item.Center

    IconGlyph {
        anchors.centerIn: parent
        name: root.name
        size: root.size
        glyphColor: root.glyphColor
        fill: root.fill
    }

    RotationAnimation on rotation {
        running: root.spinning
        loops: Animation.Infinite
        from: 0; to: 360
        duration: 900
    }
    // Snap back to upright the moment it stops, so a paused spinner never rests
    // at a random angle.
    onSpinningChanged: if (!spinning) rotation = 0
}
