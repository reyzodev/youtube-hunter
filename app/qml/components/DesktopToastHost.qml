import QtQuick
import "." as C

// v3.40 — owns the stack of desktop "away notices" (DesktopToast windows).
//
// Lives once in Main.qml. It has no pixels of its own: every notice is its own
// small top-level window, stacked newest-at-the-bottom above the taskbar on
// the primary screen's right edge (DesktopNotify.workArea already excludes the
// taskbar, wherever it is docked).
//
//   * at most `maxStack` cards are up; a fourth retires the oldest;
//   * a notice with the same `group` + kind as a card that is still up bumps
//     that card (×2, ×3…) instead of stacking a twin — ten downloads finishing
//     together are one card, not ten;
//   * DesktopNotify.dismissAll (the app came back to the front, or a card was
//     clicked) glides every card out.
//
// v3.41: it also owns the LIVE cards (LiveActivityCard) for downloads / cuts
// still running while the user is away. They sit at the bottom of the stack
// (oldest job lowest) and the ordinary notices stack above them.
Item {
    id: host
    visible: false
    width: 0
    height: 0

    readonly property int maxStack: 3
    readonly property int gap: 10          // visible space between two cards
    property var toasts: []                // newest first
    property var lives: []                 // live job cards, oldest first

    Component {
        id: toastComp
        C.DesktopToast {}
    }
    Component {
        id: liveComp
        C.LiveActivityCard {}
    }

    Connections {
        target: DesktopNotify
        function onPosted(n) { host.push(n) }
        function onDismissAll() { host.dismissAll() }
        function onWorkAreaChanged() { host.layout() }
        function onLiveEvent(e) { host.live(e) }
    }

    function _liveCard(e) {
        for (var i = 0; i < lives.length; i++) {
            var w = lives[i]
            if (!w.closing && w.key === e.key && w.token === e.token) return w
        }
        return null
    }

    function live(e) {
        if (!e) return
        if (e.op === "show") {
            var w = liveComp.createObject(null, { job: e })
            if (!w) return
            w.finished.connect(function() { host._removeLive(w) })
            w.heightChanged.connect(host.layout)
            w.closingChanged.connect(host.layout)
            lives.push(w)
            layout()
            DesktopNotify.prepare(w)
            w.present()
            return
        }
        var card = _liveCard(e)
        if (!card) return
        if (e.op === "update") card.apply(e)
        else if (e.op === "finish") card.finish(e)
        else if (e.op === "hide") card.dismiss(false)
    }

    function _removeLive(w) {
        var idx = lives.indexOf(w)
        if (idx >= 0) lives.splice(idx, 1)
        layout()
        w.destroy()
    }

    function push(n) {
        if (!n) return
        if ((n.group || "") !== "") {
            for (var i = 0; i < toasts.length; i++) {
                var t = toasts[i]
                if (!t.closing && t.notice.group === n.group && t.notice.kind === n.kind) {
                    t.bump(n)
                    return
                }
            }
        }
        var w = toastComp.createObject(null, { notice: n })
        if (!w) return
        w.finished.connect(function() { host._remove(w) })
        w.heightChanged.connect(host.layout)
        // a card that starts closing frees its slot at once, so the rest glide down
        w.closingChanged.connect(host.layout)
        toasts.unshift(w)
        var alive = 0
        for (var j = 0; j < toasts.length; j++) {
            if (toasts[j].closing) continue
            alive += 1
            if (alive > maxStack) toasts[j].dismiss()
        }
        layout()
        DesktopNotify.prepare(w)
        w.present()
    }

    function layout() {
        var wa = DesktopNotify.workArea
        var right = wa.x + wa.width
        var cursor = wa.y + wa.height          // bottom edge of the next window
        for (var k = 0; k < lives.length; k++) {
            var l = lives[k]
            if (l.closing) continue
            l.targetX = right - l.width
            l.targetY = cursor - l.height
            cursor = l.targetY + l.margin * 2 - gap
        }
        for (var i = 0; i < toasts.length; i++) {
            var t = toasts[i]
            if (t.closing) continue
            t.targetX = right - t.width
            t.targetY = cursor - t.height
            // next card's visible bottom sits `gap` above this card's top
            cursor = t.targetY + t.margin * 2 - gap
        }
    }

    function dismissAll() {
        for (var i = 0; i < toasts.length; i++)
            toasts[i].dismiss()
        for (var k = 0; k < lives.length; k++)
            lives[k].dismiss(false)
    }

    function _remove(w) {
        var idx = toasts.indexOf(w)
        if (idx >= 0) toasts.splice(idx, 1)
        layout()
        w.destroy()
    }
}
