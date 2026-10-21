import QtQuick
import NicheScope

// Drag a video file OUT of the app (v3.39.9, fixed in v3.39.10).
//
// Put it INSIDE a card / row:  C.FileDragSource { paths: [row.filepath]; preview: thumb }
// Press and drag anywhere on that card and a real OS file drag starts: the
// desktop, an Explorer folder, Premiere / CapCut, Telegram, a browser upload
// box... Always a COPY, so the library keeps its own file (see file_drag.py).
//
// v3.39.10 — this is a plain DragHandler on the card, NOT an overlay Item.
// The first version sat on top of the card (z: 999) and its handler saw the
// press first; once it accepted it, Qt Quick delivered the press to handlers
// only, so the play / delete / folder buttons and the thumbnail never got a
// click. On the card itself the handler is offered the press AFTER the
// buttons (Qt 6 still shows an accepted press to the handlers further down),
// so every click works as before and the drag only takes over once the
// pointer really moves past the threshold.
DragHandler {
    id: root

    // A list of paths (or a single one), or a function returning them —
    // a function is evaluated when the drag starts, so it can look at the
    // current selection.
    property var paths: []
    // Optional item whose pixels become the drag thumbnail.
    property Item preview: null
    property bool canDrag: true

    target: null
    enabled: canDrag
    acceptedButtons: Qt.LeftButton
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    dragThreshold: 10
    // take the pointer from a button / MouseArea once it is clearly a drag
    grabPermissions: PointerHandler.CanTakeOverFromAnything
    cursorShape: Qt.DragCopyCursor
    onActiveChanged: if (active) root._begin()

    function _resolve() {
        let v = typeof root.paths === "function" ? root.paths() : root.paths
        if (v === undefined || v === null) return []
        if (typeof v === "string") v = [v]
        const out = []
        for (let i = 0; i < v.length; ++i) {
            const s = v[i] === undefined || v[i] === null ? "" : String(v[i])
            if (s !== "") out.push(s)
        }
        return out
    }

    function _begin() {
        const list = root._resolve()
        if (list.length === 0) { root._reset(); return }
        const go = function (img) {
            FileDrag.start(list, img === undefined ? null : img)
            root._reset()
        }
        const src = root.preview
        // grabToImage is async (one frame) — which also means the OS drag
        // starts OUTSIDE Qt Quick's pointer delivery, the safe place for it.
        if (src && src.visible && src.width > 0 && src.height > 0
                && src.grabToImage(function (r) { go(r.image) }))
            return
        Qt.callLater(go, null)
    }

    // The OS drag loop swallows the button release, so Qt Quick never sees
    // it and the handler would stay "active" until the next click. Toggling
    // `enabled` drops its grab and leaves it clean for the next drag.
    function _reset() {
        root.enabled = false
        Qt.callLater(function () { root.enabled = Qt.binding(function () { return root.canDrag }) })
    }
}
