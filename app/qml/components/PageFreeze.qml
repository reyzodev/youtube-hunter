import QtQuick

// v3.40.1: sizes a page while it is hidden, so its FIRST appearance is cheap,
// and keeps a hidden page from re-laying itself out on every resize tick.
//
// StackLayout only lays out its CURRENT child. A page that was pre-built in
// the background therefore sat at 0 x 0: its layouts, ListViews (every visible
// delegate + cacheBuffer), wrapped text and so on were all computed for the
// first time in the very frame the page was shown, which is the hitch on the
// first visit to a heavy page (AI Chat most of all). Here the page takes the
// STACK's size as soon as it is built, so all that layout work happens in the
// background build and the first show only has to paint.
//
// While the page is on screen it follows the stack live. While it is hidden
// it does not: dragging the window edge would otherwise re-lay-out every built
// page on every tick. A hidden page catches up once the resize has settled,
// staggered so not all of them land in the same frame.
Item {
    id: host

    default property Item page
    onPageChanged: if (page) page.parent = host

    // Loader -> StackLayout. Falls back to our own size if that ever changes.
    readonly property Item _stack: (parent && parent.parent) ? parent.parent : null
    readonly property real _w: _stack ? _stack.width : width
    readonly property real _h: _stack ? _stack.height : height

    function _sync() {
        if (!page || _w <= 0 || _h <= 0)
            return
        if (page.width !== _w) page.width = _w
        if (page.height !== _h) page.height = _h
    }

    on_WChanged: visible || page === null || page.width <= 0 ? _sync() : catchUp.restart()
    on_HChanged: visible || page === null || page.height <= 0 ? _sync() : catchUp.restart()
    onVisibleChanged: if (visible) _sync()
    Component.onCompleted: _sync()

    Timer {
        id: catchUp
        interval: 1500 + Math.floor(Math.random() * 4000)
        repeat: false
        onTriggered: host._sync()
    }
}
