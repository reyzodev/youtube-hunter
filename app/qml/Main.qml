import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import NicheScope
import "components" as C
import "pages" as P
import "Utils.js" as U

// Root frameless window. Hosts the title bar, the sidebar rail, and a stack of
// pages selected by App.currentPage. Colours/text/direction all bind live to
// the Theme / I18n bridges, so a theme or language switch reflows in place.
Window {
    id: win
    width: 1280
    height: 820
    minimumWidth: 980
    minimumHeight: 640
    visible: true
    title: I18n.tr("YouTube Hunter")
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"

    readonly property bool isMaximized: visibility === Window.Maximized

    // v16: page-width rule needs the window width (see Tokens.contentWidth)
    Binding { target: Tokens; property: "windowWidth"; value: win.width }

    // Maximize / restore (v3.40.1).
    //
    // This used to be a hand-rolled tween that wrote win.x / y / width / height
    // on every animation frame. Each write is a real native resize, and every
    // resize re-lays-out the whole QML tree and re-allocates the swap chain, so
    // one maximize cost ~48 full relayouts: the lag when the window was made
    // big or small. Now the state is set ONCE and Windows plays its own DWM
    // animation (enabled by app/qml_backend/win_frame.py), which costs the app
    // nothing. `_animating` stays for the bindings that read it.
    readonly property bool _animating: false

    function toggleMaximize() {
        if (isMaximized) win.showNormal()
        else win.showMaximized()
    }

    // Test-only: render the shell to a PNG (used by the preview harness).
    // Set `grabPath` to a file path and the shell is grabbed on the next frame.
    property string grabPath: ""
    onGrabPathChanged: if (grabPath !== "")
        shell.grabToImage(function(res) { res.saveToFile(grabPath) })

    // Test-only hooks for the same harness: QML-declared items aren't reachable
    // from Python by findChildren, so the tour is driven through the window.
    function tourStart() { tour.start() }
    function tourNext() { tour.next() }
    readonly property int tourIndex: tour.index
    readonly property int tourCount: tour.count
    readonly property bool tourHasHole: tour.hasHole
    readonly property rect tourHole: tour.hole

    // Test-only: a binding that goes through I18n.tr, so the harness can prove a
    // live language switch actually re-evaluates QML bindings (a signal alone
    // cannot — see AppController._retranslate_context).
    readonly property string i18nProbe: I18n.tr("Settings") + "|" + I18n.tr("Downloads")

    // The item modal dialogs blur behind themselves (see DialogScrim). Exposed
    // on the Window so any scrim, at any nesting depth, can reach it through
    // Window.window without every page having to thread it down.
    readonly property alias blurSource: shell

    // ── theme reveal ──
    // The palette is applied at the START of the animation; a frozen snapshot of
    // the OLD theme is then wiped away by a growing circle, so the NEW theme is
    // uncovered from the click point outward — every pixel that enters the circle
    // is already recoloured. On a very large window the full-window texture costs
    // more than the effect is worth, so there the swap is immediate.
    function startThemeWipe(cx, cy, preference) {
        // v3.38: the lock-on curtain takes no window snapshot, so it runs at
        // every window size (the old >1440p shortcut is gone).
        // resolvedThemeName / themeColorOf live on App, not Theme: the Theme
        // bridge is a QQmlPropertyMap and can only publish palette keys, not
        // callable slots. targetColor is passed for signature compatibility;
        // ThemeWipe now reveals the live new theme directly.
        //
        // v3.39.6: the palette is swapped in slices behind the opaque curtain
        // (App.beginThemeSwap), with colour Behaviors snapped instead of
        // animated, and flushed right before the iris opens. Swapping it all
        // in one frame is what made the lock-on motion hitch on every switch.
        const resolved = App.resolvedThemeName(preference)
        themeWipe.run(cx, cy, App.themeColorOf(resolved, "background"),
                      function() {
                          Tokens.themeSwapping = true
                          App.beginThemeSwap(preference)
                      },
                      function() {
                          App.flushThemeSwap()
                          Tokens.themeSwapping = false
                      },
                      // v3.39.8: hold the iris until the staged swap is done
                      // instead of flushing a big remainder in one frame
                      function() { return !App.themeSwapPending() })
    }

    // rounded outer shell
    Rectangle {
        id: shell
        anchors.fill: parent
        radius: win.isMaximized ? 0 : Tokens.windowRadius
        // Without this the 14px curve is drawn with hard, stair-stepped pixels
        // — which reads as "the corner is sharp" even though it is technically
        // rounded. Antialiasing is what makes it look round.
        antialiasing: true
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        // RTL: mirror the whole shell, so the nav rail sits on the right in
        // Persian and page layouts flow right-to-left. NOTE: this must live on
        // an Item — LayoutMirroring attached to the Window itself is inert, so
        // the previous Window-level lines mirrored nothing and the rail stayed
        // left in Persian. TitleBar and the video-player chrome opt back out
        // explicitly (see those files); everything else follows the shell.
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            C.TitleBar {
                Layout.fillWidth: true
                win: win
                // keep the top corners rounded
                topLeftRadius: shell.radius
                topRightRadius: shell.radius
                onThemeWipeRequested: (cx, cy, preference) => win.startThemeWipe(cx, cy, preference)
                onTourRequested: tour.start()
                onUpdateRequested: updateDialog.present()
                // v3.36: the "not connected" pill reopens the connection gate
                gateOpen: geoDialog.visible
                onConnectionRequested: geoDialog.presentStartup()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                C.Sidebar {
                    id: sidebar
                    // v3.39.11: hovering a rail row starts building its page
                    onPrefetchRequested: (code) => pageStack.prefetch(code)
                    Layout.fillHeight: true
                    // The rail animates its own implicitWidth (collapsed vs
                    // expanded); the layout follows it, so the page beside it
                    // grows in step with the slide.
                    Layout.preferredWidth: implicitWidth
                    // Round the sidebar's corner that meets the window's rounded
                    // shell, so the rail follows the frame instead of painting a
                    // hard square over it (the rail has its own opaque bg, so
                    // unlike the page area the shell can't show through
                    // underneath).
                    //
                    // WHICH corner is a function of direction, not of "left":
                    // the shell mirrors in Persian, so the rail sits on the
                    // RIGHT there and its bottom-RIGHT corner is the one against
                    // the frame. Rounding bottomLeft in RTL left the actual
                    // corner square and clipped an interior one.
                    bottomLeftRadius: (!I18n.rtl && !win.isMaximized) ? Tokens.windowRadius - 1 : 0
                    bottomRightRadius: (I18n.rtl && !win.isMaximized) ? Tokens.windowRadius - 1 : 0
                }

                // page stack — wrapped so the first-visit hairline can sit over
                // its top edge (a QML item may only anchor to a parent or a
                // sibling, and the bar has to track the stack's width exactly).
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StackLayout {
                        id: pageStack
                        // Named so the offscreen harness can count how many pages
                        // are actually built right now and prove the lazy loading
                        // below works (see .workbuddy-ai/verify-lazy-pages.py).
                        objectName: "pageStack"
                        anchors.fill: parent
                        // v3.39.9: the stack shows App.currentPage only once that
                        // page is actually BUILT. Until then the page you came from
                        // stays on screen (the rail already highlights the new one),
                        // so a first visit is one clean fade-in instead of an empty
                        // slot fading in, the content popping in, and the whole
                        // entrance replaying a second time (the "pulled down" jump).
                        currentIndex: _shownIndex
                        property int _heldIndex: 0
                        readonly property int _shownIndex: _isReady(App.currentPage) ? App.currentPage : _heldIndex
                        // Reads children[i].status, so the binding above re-runs the
                        // moment an asynchronous Loader finishes.
                        function _isReady(i) {
                            const l = pageStack.children[i]
                            return !!l && l.status === Loader.Ready
                        }
                        Component.onCompleted: _markBuilt(App.currentPage)
                        // v4: each page arrives with a short fade + rise. A
                        // transform, not y, so the RowLayout's geometry is untouched.
                        transform: Translate { id: pageShift; y: 0 }

                        // ── lazy pages (v18.1) ─────────────────────────────────────
                        // Every page used to be constructed before the window
                        // could paint. Together they are ~1.5 MB of QML, and building
                        // them cost ~3.4 s of the ~5 s it took to see the app. Now a
                        // page is built the first time it is shown and then KEPT, so
                        // returning to it is instant and its state survives — the
                        // same behaviour as before, only paid for on first visit.
                        // Index 0 (Scraper) is the landing page and stays eager, so
                        // there is real content on screen the moment the window opens.
                        property var builtPages: {"0": true}
                        function _markBuilt(i) {
                            const k = String(i)
                            if (builtPages[k] === true)
                                return
                            // A fresh object: mutating a `var` property in place does
                            // not notify the `active:` bindings below.
                            const next = {}
                            for (const p in builtPages)
                                next[p] = true
                            next[k] = true
                            builtPages = next
                        }
                        // App.currentPage is the source of truth — the rail, the
                        // onboarding tour, Ctrl+1…9 and every "open this page" toast
                        // move it, and `currentIndex` above follows. Marking it here
                        // as well means the flag is already set in the same
                        // event-loop pass the page becomes current, so anything that
                        // measures the new page (the tour's spotlight) finds it.
                        Connections {
                            target: App
                            function onCurrentPageChanged() {
                                // v3.39.11: a background build of ANOTHER page must not
                                // halve the speed of the one you just opened.
                                if (!pageStack._isReady(App.currentPage))
                                    pageStack._cancelBackground(App.currentPage)
                                if (pageStack._bgIndex === App.currentPage)
                                    pageStack._bgIndex = -1   // it is yours now
                                pageStack._markBuilt(App.currentPage)
                            }
                        }
                        onCurrentIndexChanged: {
                            _heldIndex = currentIndex
                            pageEnter.restart()
                        }
                        // v3.39.8: a page's FIRST visit is built asynchronously (in
                        // per-frame slices) instead of freezing the click for the
                        // few hundred ms a 3,000-line page takes to construct — the
                        // occasional "lag when switching tabs". The tour keeps the
                        // old synchronous path: it measures the page right away.
                        //
                        // v3.39.9: the entrance plays exactly ONCE per switch, when
                        // currentIndex really changes (i.e. the page is ready). It
                        // used to start on the click — over a still-empty Loader —
                        // and then restart from opacity 0 / +8px when the page
                        // landed: a visible double drop on every first visit.
                        ParallelAnimation {
                            id: pageEnter
                            NumberAnimation { target: pageStack; property: "opacity"; from: 0.0; to: 1.0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
                            NumberAnimation { target: pageShift; property: "y"; from: Tokens.pageRise; to: 0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
                        }

                        // ── v3.39.11: idle pre-warm + hover prefetch ─────────────────
                        // Why the FIRST visit took 1–2 s: an asynchronous Loader only
                        // gets a few ms of every frame to build its page (the window's
                        // incubation controller slices the work between frames so the
                        // UI never freezes). A big page costs a few hundred ms of
                        // build time, which works out to 60–120 frames, i.e. 1–2 s of
                        // waiting before the page can appear. The second visit was
                        // instant because the page is kept.
                        //
                        // Fix: nobody should pay that on a click. Shortly after the
                        // window is up, the remaining pages are built in the
                        // background, ONE at a time, in rail order, still in slices,
                        // so the UI keeps animating. Each one stays hidden in the
                        // stack (exactly like a visited page you have left), so by
                        // the time you click it is already built and the switch is
                        // instant. Hovering / pressing a rail row also starts that
                        // page right away, which buys a head start even if the warm
                        // queue has not reached it yet.
                        readonly property var _warmOrder: [4, 11, 5, 6, 7, 13, 8, 12, 9, 2, 3, 10, 1]
                        property bool _warmStarted: false
                        // The page built in the BACKGROUND right now (warm-up or
                        // hover), -1 if none. If you click a different page while it
                        // is still building, it is dropped so your page gets the
                        // whole per-frame budget, and re-queued for later.
                        property int _bgIndex: -1
                        // The rail row the pointer is resting on (-1: none).
                        property int _hoverIndex: -1

                        function _isBuilt(i) { return builtPages[String(i)] === true }
                        function _unmarkBuilt(i) {
                            const k = String(i)
                            if (builtPages[k] !== true || i === 0)
                                return
                            const next = {}
                            for (const p in builtPages)
                                if (p !== k)
                                    next[p] = true
                            builtPages = next
                        }
                        function _anyLoading() {
                            for (let j = 0; j < pageStack.children.length; ++j) {
                                const l = pageStack.children[j]
                                if (l && l.status === Loader.Loading)
                                    return true
                            }
                            return false
                        }
                        // Build page i in the background (never more than one).
                        function _bgBuild(i) {
                            if (i < 0 || i >= pageStack.children.length || _isBuilt(i) || _anyLoading())
                                return false
                            _bgIndex = i
                            _markBuilt(i)
                            if (pageStack.children[i].status !== Loader.Loading) {
                                // built synchronously (tour running): done already
                                _bgIndex = -1
                                warmTimer.interval = 120
                                warmTimer.restart()
                            }
                            return true
                        }
                        // From the rail: -1 = left the row, p = resting on page p,
                        // 1000 + p = pressed (the click is coming: start now).
                        function prefetch(code) {
                            if (code >= 1000) {
                                _hoverIndex = -1
                                const i = code - 1000
                                if (!_isBuilt(i)) {
                                    _cancelBackground(i)
                                    _markBuilt(i)
                                }
                                return
                            }
                            _hoverIndex = code
                            if (code >= 0 && !_isBuilt(code))
                                hoverTimer.restart()   // only if the pointer RESTS there
                            else
                                hoverTimer.stop()
                        }
                        // Drop a background build that is not page `keep`.
                        function _cancelBackground(keep) {
                            const b = _bgIndex
                            if (b < 0 || b === keep)
                                return
                            const l = pageStack.children[b]
                            if (l && l.status === Loader.Loading)
                                _unmarkBuilt(b)        // re-queued: _warmOrder still lists it
                            _bgIndex = -1
                        }
                        function _warmNext() {
                            // The tour builds pages synchronously and measures them;
                            // stay out of its way and try again later.
                            if (tour.running) { warmTimer.interval = 2000; warmTimer.restart(); return }
                            // Never stack builds: _pageSettled() re-arms us.
                            if (_anyLoading())
                                return
                            // the row under the pointer goes first
                            if (_hoverIndex >= 0 && _bgBuild(_hoverIndex))
                                return
                            for (let n = 0; n < _warmOrder.length; ++n)
                                if (_bgBuild(_warmOrder[n]))
                                    return
                            // every page is built: nothing left to do
                        }
                        function _pageSettled(st) {
                            if (st !== Loader.Ready && st !== Loader.Error)
                                return
                            if (_bgIndex >= 0) {
                                const l = pageStack.children[_bgIndex]
                                if (!l || l.status !== Loader.Loading)
                                    _bgIndex = -1
                            }
                            if (_warmStarted) {
                                // a short breather between pages so input and
                                // animations always get whole frames in between
                                warmTimer.interval = 120
                                warmTimer.restart()
                            }
                        }
                        Timer {
                            id: warmTimer
                            // after the splash has handed over and the shell has
                            // painted (the theme warm-up below runs at 2.5 s)
                            interval: 1200
                            running: true
                            repeat: false
                            onTriggered: {
                                pageStack._warmStarted = true
                                pageStack._warmNext()
                            }
                        }
                        Timer {
                            id: hoverTimer
                            // long enough that sweeping the pointer down the rail
                            // starts nothing, short enough to beat a real click
                            interval: 90
                            repeat: false
                            onTriggered: {
                                const i = pageStack._hoverIndex
                                if (i >= 0 && !pageStack._isBuilt(i) && !pageStack._bgBuild(i)) {
                                    // something else is building: if it is only a
                                    // background warm-up, the hovered page wins
                                    const b = pageStack._bgIndex
                                    if (b >= 0 && b !== i && b !== App.currentPage) {
                                        pageStack._cancelBackground(i)
                                        pageStack._bgBuild(i)
                                    }
                                }
                            }
                        }

                        // One Loader per page, in the same order as PAGE_* in
                        // app_controller.py — a StackLayout's index IS its child
                        // order, and several QML files hardcode these numbers.
                        Loader { sourceComponent: pageScraper; active: pageStack.builtPages["0"] === true; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageLogs; active: pageStack.builtPages["1"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageHistory; active: pageStack.builtPages["2"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageMonetize; active: pageStack.builtPages["3"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageNiche; active: pageStack.builtPages["4"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageArchive; active: pageStack.builtPages["5"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageIdeas; active: pageStack.builtPages["6"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageContentLab; active: pageStack.builtPages["7"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageDownloads; active: pageStack.builtPages["8"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageUsage; active: pageStack.builtPages["9"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageSettings; active: pageStack.builtPages["10"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageInsights; active: pageStack.builtPages["11"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageCutter; active: pageStack.builtPages["12"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                        Loader { sourceComponent: pageChat; active: pageStack.builtPages["13"] === true; asynchronous: !tour.running; onStatusChanged: pageStack._pageSettled(status) }
                    }

                    // ── first-visit progress hairline (v3.52) ───────────────────
                    // A page is built asynchronously the first time it is opened,
                    // and the stack deliberately keeps the OLD page on screen
                    // until the new one is ready (that is what makes the entrance
                    // a single clean fade). The rail highlight, however, moves on
                    // the click — so on a big page the click could look like it
                    // did nothing for half a second. This 2 px shimmer sits
                    // exactly where the new page will appear and says "building".
                    // It only exists while the switch is pending; a page that is
                    // already built (every visit after the first) never shows it.
                    Rectangle {
                        id: pageLoadTrack
                        readonly property bool busy: pageStack._shownIndex !== App.currentPage
                        visible: busy
                        z: 20
                        height: 2
                        color: U.withAlpha(Theme.primary, 0.10)
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        clip: true

                        Rectangle {
                            id: pageLoadPulse
                            width: Math.max(96, pageLoadTrack.width * 0.26)
                            height: parent.height
                            radius: height / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                                GradientStop { position: 0.5; color: Theme.primary }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                            }
                            SequentialAnimation {
                                running: pageLoadTrack.visible
                                loops: Animation.Infinite
                                NumberAnimation {
                                    target: pageLoadPulse
                                    property: "x"
                                    from: -pageLoadPulse.width
                                    to: pageLoadTrack.width
                                    duration: 780
                                    easing.type: Easing.InOutQuad
                                }
                                PauseAnimation { duration: 90 }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── the lazy page templates ──
    // Declared as `Component`s, not items, so no layout ever counts them as a
    // child. They live at the window root because the Settings one wires the
    // page's signals to the tour and the title bar, which are declared further
    // down — QML ids are file-scoped, so that forward reference is fine.
    Component { id: pageScraper;    C.PageFreeze { P.DashboardPage {} } }
    Component { id: pageLogs;       C.PageFreeze { P.LogsPage {} } }
    Component { id: pageHistory;    C.PageFreeze { P.HistoryPage {} } }
    Component { id: pageMonetize;   C.PageFreeze { P.MonetizePage {} } }
    Component { id: pageNiche;      C.PageFreeze { P.NichePage {} } }
    Component { id: pageArchive;    C.PageFreeze { P.ArchivePage {} } }
    Component { id: pageIdeas;      C.PageFreeze { P.AIIdeasPage {} } }
    Component { id: pageContentLab; C.PageFreeze { P.ContentLabPage {} } }
    Component { id: pageDownloads;  C.PageFreeze { P.DownloadsPage {} } }
    Component { id: pageUsage;      C.PageFreeze { P.UsagePage {} } }
    Component {
        id: pageSettings
        C.PageFreeze {
            P.SettingsPage {
                onTourRequested: tour.start()
                // Same animated paths the title bar uses.
                onThemeWipeRequested: (cx, cy, preference) => win.startThemeWipe(cx, cy, preference)
            }
        }
    }
    Component { id: pageInsights;   C.PageFreeze { P.InsightsPage {} } }
    Component { id: pageCutter;     C.PageFreeze { P.CutterPage {} } }
    Component { id: pageChat;       C.PageFreeze { P.AIChatPage {} } }

    // ── overlays above the shell ──
    // The theme curtain and the language veil both sit above the page stack but
    // BELOW the resize grips, so dragging an edge still works while they play.
    C.ThemeWipe {
        id: themeWipe
        // Named so the offscreen harness can drive a real theme switch and
        // assert the effect hands control back — a wipe that never clears its
        // _wiping flag would leave a full-window layer armed over the whole app.
        objectName: "themeWipe"
        anchors.fill: parent
        radius: win.isMaximized ? 0 : Tokens.windowRadius
        z: 800
    }

    // Warm the theme-wipe effect up once, shortly after the shell has painted.
    //
    // The first render of a MultiEffect is the expensive one: its shader has to
    // compile and its snapshot/mask textures have to be allocated at the
    // window's size. Paying that during the user's first theme switch is what
    // made the switch feel like it "sometimes" lagged — it lagged the first
    // time and was fine afterwards. This renders the effect once at opacity 0,
    // so every real switch runs on already-warm state.
    Timer {
        interval: 2500
        running: true
        repeat: false
        onTriggered: {
            themeWipe.warmUp()
            // and rasterise the other palette's icons while the app is idle
            App.prewarmThemeSwap()
        }
    }

    C.LoadingVeil {
        id: veil
        radius: win.isMaximized ? 0 : Tokens.windowRadius
    }

    // ── launch splash ──
    // The animated YouTube Hunter mark. `ready` is raised a beat after the shell
    // has painted underneath, so the dissolve reveals a finished window.
    C.BrandSplash {
        id: splash
        radius: win.isMaximized ? 0 : Tokens.windowRadius
    }
    Timer {
        interval: 300
        running: true
        repeat: false
        onTriggered: splash.ready = true
    }

    // ── onboarding tour ──
    // Twelve steps covering the whole app. Each step names an objectName to
    // spotlight and, when the target lives elsewhere, the page to switch to
    // first. A step with no target renders as a plain centred card.
    C.TourOverlay {
        id: tour
        objectName: "tourOverlay"
        // The tour walks the app the way you'd use it: a welcome, then for each
        // section it first spotlights that section's NAV ROW (so you always know
        // which part of the app the next screen belongs to), then switches to the
        // page and points at the one thing that matters there. Nav-row steps have
        // no `page` (they just highlight the rail); content steps carry `page`.
        steps: [
            {
                title: I18n.tr("Welcome to YouTube Hunter"),
                body: I18n.tr("A quick walk through the whole app, in the order you'll actually use it. Leave anytime with Esc, and replay it from the ? button.")
            },
            {
                target: "tour_navList",
                title: I18n.tr("The navigation rail"),
                body: I18n.tr("Every section lives here, roughly in the order you use them: scrape data, find outliers, turn them into ideas, then download. The active section shows a red bar at the window edge. We'll walk through each one.")
            },

            // ── Scraper ──
            {
                target: "tour_nav_0",
                title: I18n.tr("1 · Scraper"),
                body: I18n.tr("Everything starts here: this is where you pull raw video data off YouTube.")
            },
            {
                page: 0,
                target: "tour_scrapeForm",
                title: I18n.tr("Scraper — pull the raw data"),
                body: I18n.tr("Point it at a channel URL or a keyword, set how many videos to take, and start. The rest of the app works from what you extract here.")
            },

            // ── Niche Finder ──
            {
                target: "tour_nav_4",
                title: I18n.tr("2 · Niche Finder"),
                body: I18n.tr("The core of the app — search all of YouTube and surface small channels pulling big numbers.")
            },
            {
                page: 4,
                target: "tour_nicheFilters",
                title: I18n.tr("The outlier hunt"),
                body: I18n.tr("Filter by subscribers, views and time window. The multiplier is views ÷ subscribers — a high one means a small channel punching well above its size.")
            },

            // ── Search Archive ──
            {
                target: "tour_nav_5",
                title: I18n.tr("3 · Search Archive"),
                body: I18n.tr("Every search you run is stored here forever — reopening, re-filtering or exporting one costs no quota at all.")
            },

            // ── AI Ideas ──
            {
                target: "tour_nav_6",
                title: I18n.tr("4 · AI Ideas"),
                body: I18n.tr("Turn the videos you found into full content blueprints with AI.")
            },
            {
                page: 6,
                target: "tour_ideasBrief",
                title: I18n.tr("From finds to blueprints"),
                body: I18n.tr("Tick the reference videos whose style you want to borrow, describe your angle, and the AI returns titles, hooks, structure and a shot list.")
            },

            // ── Downloads ──
            {
                target: "tour_nav_8",
                title: I18n.tr("5 · Downloads"),
                body: I18n.tr("Any video, at the exact quality and format you pick: MP4 / MKV / WEBM or audio only, with the real file size shown before you start.")
            },
            {
                page: 8,
                target: "tour_downloads",
                title: I18n.tr("Your download queue"),
                body: I18n.tr("Live speed, size and ETA per row; pause, resume, then open the file or its folder right from here. Two downloads run at once, the rest wait their turn.")
            },

            // ── Video Cutter ──
            {
                target: "tour_nav_12",
                title: I18n.tr("6 · Video Cutter"),
                body: I18n.tr("Paste a link, mark In and Out, and only that clip is fetched and cut: frame-accurate, in sync, ready for any editor. Local files work too.")
            },

            // ── Quota + Settings (the two things to know before you start) ──
            {
                target: "tour_quotaCard",
                title: I18n.tr("Your YouTube quota"),
                body: I18n.tr("YouTube bills in units, not requests — a keyword search costs 100, video stats cost 1 per 50 videos. This card is always in view; click it for the full breakdown.")
            },
            {
                page: 10,
                target: "tour_settingsKeys",
                title: I18n.tr("Settings — set this up first"),
                body: I18n.tr("Paste your YouTube API key here, and pick an AI provider for the idea and report features. You can replay this tour any time from the bottom of this page.")
            }
        ]
    }

    // First run only: open the tour once the shell has actually laid out.
    Timer {
        interval: 450
        // wait for the splash to clear, the tour spotlights the shell under it
        running: !App.tourSeen && splash.done && !tour.running
        onTriggered: tour.start()
    }

    // ── edge / corner resize grips ──
    // A frameless Window draws no resize border, so these invisible strips
    // supply one: each starts a native OS resize via startSystemResize, which
    // keeps Aero-snap and per-monitor DPI correct. Hidden while maximized —
    // there's no edge to drag then. `RES` is the grab thickness.
    Item {
        anchors.fill: parent
        visible: !win.isMaximized && !win._animating
        z: 999
        readonly property int res: 6
        readonly property int corner: 14

        component Grip: MouseArea {
            property int edges: 0
            acceptedButtons: Qt.LeftButton
            onPressed: if (win.startSystemResize) win.startSystemResize(edges)
        }

        // edges
        Grip {
            edges: Qt.TopEdge; height: parent.res; cursorShape: Qt.SizeVerCursor
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: parent.corner; rightMargin: parent.corner }
        }
        Grip {
            edges: Qt.BottomEdge; height: parent.res; cursorShape: Qt.SizeVerCursor
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: parent.corner; rightMargin: parent.corner }
        }
        Grip {
            edges: Qt.LeftEdge; width: parent.res; cursorShape: Qt.SizeHorCursor
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: parent.corner; bottomMargin: parent.corner }
        }
        Grip {
            edges: Qt.RightEdge; width: parent.res; cursorShape: Qt.SizeHorCursor
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: parent.corner; bottomMargin: parent.corner }
        }

        // corners
        Grip {
            edges: Qt.TopEdge | Qt.LeftEdge; width: parent.corner; height: parent.res; cursorShape: Qt.SizeFDiagCursor
            anchors { top: parent.top; left: parent.left }
        }
        Grip {
            edges: Qt.TopEdge | Qt.RightEdge; width: parent.corner; height: parent.res; cursorShape: Qt.SizeBDiagCursor
            anchors { top: parent.top; right: parent.right }
        }
        Grip {
            edges: Qt.BottomEdge | Qt.LeftEdge; width: parent.corner; height: parent.corner; cursorShape: Qt.SizeBDiagCursor
            anchors { bottom: parent.bottom; left: parent.left }
        }
        Grip {
            edges: Qt.BottomEdge | Qt.RightEdge; width: parent.corner; height: parent.corner; cursorShape: Qt.SizeFDiagCursor
            anchors { bottom: parent.bottom; right: parent.right }
        }
    }

    // popup dialog for VM messages (validation, errors, warnings) — a clean
    // themed card matching the confirm dialogs, replacing the old native box.
    Dialog {
        id: msgDialog
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, win.width - 80)
        padding: 0
        property string kind: "info"
        property string _body: ""
        function present(t, b, k) { title = t; _body = b; kind = k; open() }

        readonly property color _accent: kind === "error" ? Theme.error
                                        : kind === "warning" ? Theme.warn
                                        : kind === "success" ? Theme.secondary_container
                                        : Theme.primary
        readonly property string _glyph: kind === "error" ? "error"
                                       : kind === "warning" ? "warning"
                                       : kind === "success" ? "check_circle" : "info"

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }

        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: msgHeadRow.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: msgHeadRow
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(msgDialog._accent, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(msgDialog._accent, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: msgDialog._glyph; fill: true; size: 20
                        glyphColor: msgDialog._accent
                    }
                }
                C.AppText {
                    text: msgDialog.title
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: C.AppText {
            text: msgDialog._body
            color: Theme.on_surface
            wrapMode: Text.WordWrap
            padding: Tokens.space5
            topPadding: 0
        }
        footer: Item {
            implicitHeight: 50 + Tokens.space5 * 2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.topMargin: Tokens.space3
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    text: I18n.tr("OK")
                    onClicked: msgDialog.close()
                }
            }
        }
    }

    // Unsaved-settings guard dialog. AppController.goto() refuses to leave the
    // Settings page while it has pending edits and emits navBlocked(idx); this
    // asks whether to save, discard, or stay, then completes the jump.
    Dialog {
        id: unsavedDialog
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, win.width - 80)
        padding: 0
        property int pendingPage: -1

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }

        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: unsavedHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: unsavedHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    // 32, not 40: at 40 the tile stood taller than the title's
                    // cap height and the two read as unrelated blocks stacked
                    // side by side rather than one heading.
                    width: 32; height: 32; radius: Tokens.radiusMd
                    Layout.alignment: Qt.AlignVCenter
                    color: U.withAlpha(Theme.warn, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.warn, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "warning"; fill: true; size: 17
                        glyphColor: Theme.warn
                    }
                }
                C.AppText {
                    text: I18n.tr("Unsaved changes")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: C.AppText {
            text: I18n.tr("You have unsaved changes in Settings. Save them before leaving?")
            color: Theme.on_surface
            wrapMode: Text.WordWrap
            padding: Tokens.space5
            // A small gap under the header instead of sitting flush against it —
            // the header's own bottom margin ends exactly at the title baseline.
            topPadding: Tokens.space2
            bottomPadding: 0
        }
        footer: Item {
            implicitHeight: 50 + Tokens.space5 * 2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.topMargin: Tokens.space4
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                // Both actions sit together at the trailing edge, primary last.
                // There is no "Stay here" button: Escape and clicking outside the
                // dialog already do exactly that, so a third button only competed
                // with the two choices that actually change something.
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    // Ghost, not "danger": a second FILLED red button fought the
                    // primary for attention and made discarding look like the
                    // recommended action.
                    variant: "ghost"
                    text: I18n.tr("Discard")
                    onClicked: {
                        Settings.revert()
                        App.setNavGuard(false)
                        unsavedDialog.close()
                        App.goto(unsavedDialog.pendingPage)
                    }
                }
                C.PrimaryButton {
                    text: I18n.tr("Save & continue")
                    iconName: "save"
                    onClicked: {
                        Settings.save()
                        App.setNavGuard(false)
                        unsavedDialog.close()
                        App.goto(unsavedDialog.pendingPage)
                    }
                }
            }
        }
    }

    Connections {
        target: App
        function onNavBlocked(idx) {
            unsavedDialog.pendingPage = idx
            unsavedDialog.open()
        }
    }

    // Scrape-finished dialog — a proper themed card with quick actions to open
    // the export or its folder, instead of the plain native "Done!" box.
    Dialog {
        id: doneDialog
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(500, win.width - 80)
        padding: 0
        property string _body: ""
        property string _path: ""
        function present(t, b, p) { title = t; _body = b; _path = p; open() }

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }

        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: doneHeadRow.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: doneHeadRow
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 44; height: 44; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.secondary_container, 0.14)
                    border.width: 1
                    border.color: U.withAlpha(Theme.secondary_container, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "check_circle"; fill: true; size: 22
                        glyphColor: Theme.secondary_container
                    }
                }
                C.AppText {
                    text: doneDialog.title
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontTitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: ColumnLayout {
            spacing: Tokens.space3
            C.AppText {
                text: doneDialog._body
                color: Theme.on_surface
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
            }
            // the output path in a copy-friendly mono chip
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                visible: doneDialog._path !== ""
                radius: Tokens.radiusMd
                color: Theme.surface_high
                border.width: 1
                border.color: Theme.outline_variant
                implicitHeight: pathRow.implicitHeight + Tokens.space3 * 2
                RowLayout {
                    id: pathRow
                    anchors.fill: parent
                    anchors.margins: Tokens.space3
                    spacing: Tokens.space2
                    C.IconGlyph { name: "description"; size: 15; glyphColor: Theme.on_surface_var }
                    C.AppText {
                        text: doneDialog._path
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }
        }
        footer: Item {
            implicitHeight: 50 + Tokens.space5 * 2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.topMargin: Tokens.space3
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                C.PrimaryButton {
                    variant: "ghost"
                    text: I18n.tr("Close")
                    onClicked: doneDialog.close()
                }
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    iconName: "folder_open"
                    text: I18n.tr("Open Folder")
                    onClicked: { Dashboard.openFolder(doneDialog._path); doneDialog.close() }
                }
                C.PrimaryButton {
                    iconName: "open_in_new"
                    text: I18n.tr("Open File")
                    onClicked: { Dashboard.openFile(doneDialog._path); doneDialog.close() }
                }
            }
        }
    }

    Connections {
        target: Dashboard
        function onPopup(t, m, k) { msgDialog.present(t, m, k) }
        function onDonePopup(t, m, p) { doneDialog.present(t, m, p) }
    }

    // "Signal lost" — the connection gate (components/GeoGateDialog).
    // Opened a moment after launch when the public IP is in a country where
    // YouTube is filtered OR when no server answers at all (internet down),
    // by the title bar's "not connected" pill after a skip, and by the
    // Scraper's Start button when the YouTube
    // API route is. Waits for the onboarding tour to finish so the two never
    // stack on a first launch.
    C.GeoGateDialog { id: geoDialog }

    // ── support / donation ─────────────────────────────────────────────
    // The rail's Donate pill opens this: the real donation page, live inside
    // the app (QtWebEngine), framed by a quiet card. The address comes from
    // App.donateUrl — DONATE_URL in app/constants.py, or `donate_url` in
    // config.json.
    // Only built when there is a page to open. `App.donateUrl` is empty in the
    // published build, and main_qml.py only initialises QtWebEngine when it is
    // not — so a build with no donation address never loads Chromium at all
    // (~260 MB of resident memory saved; the Donate pill is hidden anyway).
    // With an address this is the same eager card as before: ready before the
    // first click, so opening it is instant.
    Loader {
        id: donateLoader
        active: App.donateUrl !== ""
        // `source`, not `sourceComponent`: a sourceComponent is COMPILED as soon
        // as it is declared, which pulls in DonateOverlay.qml and its
        // `import QtWebEngine` even while the loader is inactive — the whole
        // point of this being a loader was lost (measured: the Chromium DLLs
        // were still in the process). `source` is only read when active.
        source: "components/DonateOverlay.qml"
    }
    Connections {
        target: App
        function onDonateRequested() {
            // `active` is already true whenever the pill can be clicked; the
            // guard covers a build where the card failed to build (no
            // QtWebEngine) — then the browser is the honest fallback.
            if (donateLoader.item) donateLoader.item.present()
            else App.openDonateExternal()
        }
    }

    // v3.40: "away notices". When a job finishes while the user is in another
    // app, a premium toast slides into the bottom-right corner of the screen.
    // The host owns no pixels here: every card is its own non-activating
    // top-level window (see DesktopToast.qml / desktop_notifier.py).
    C.DesktopToastHost { id: desktopToasts }

    // v3.43: "Add the download button to YouTube" (browser extension setup).
    // Opens itself ONCE, a few seconds after a launch where the extension has
    // never connected and the user hasn't skipped it, and never on top of the
    // onboarding tour or the connection gate (it waits for them). Settings →
    // Browser extension → "Set up" opens it any time.
    C.ExtensionSetupDialog { id: extSetupDialog }

    // v1.1: in-app update (GitHub Releases). Opened from the title-bar button
    // or from the "update available" notification.
    C.UpdateDialog { id: updateDialog }
    Connections {
        target: Updater
        function onOpenRequested() { updateDialog.present() }
    }
    Connections {
        target: ExtensionSetup
        function onOpenRequested() { extSetupDialog.present() }
    }
    Timer {
        id: extOfferTimer
        interval: 3500
        running: splash.done
        onTriggered: {
            if (!ExtensionSetup.shouldOfferOnStart || extSetupDialog.opened) return
            // busy with something else first (first-run tour, connection
            // gate, another dialog): look again a bit later
            if (!App.tourSeen || tour.running || geoDialog.opened) { interval = 2500; restart(); return }
            extSetupDialog.present()
        }
    }
    property bool _geoStartupPending: false
    // The internet dropped while the Support card is open: the gate still
    // opens (it is the app's answer to "no connection"), but BEHIND the card —
    // DonateOverlay sits at a higher z — and the keyboard stays with the card,
    // so Esc closes the card first and then the gate is simply there. The card
    // shows its own calm "You're offline" state and reloads by itself.
    function _presentGateBehindDonate() {
        geoDialog.presentStartup()
        if (donateLoader.item && donateLoader.item.opened) donateLoader.item.forceActiveFocus()
    }
    Connections {
        target: Geo
        function onStartupWarning() {
            if (tour.running || geoDialog.opened) win._geoStartupPending = true
            else win._presentGateBehindDonate()
        }
        function onGateBlocked(purpose) {
            if (purpose === "scrape") geoDialog.presentScrape()
            else if (purpose === "download") geoDialog.presentDownload()
        }
        // v3.41.5 live monitor: the connection dropped mid-session (internet
        // cut, VPN off, IP filtered / blocked by YouTube) — show the gate
        // again, not only at launch.
        function onConnectionLost(reason) {
            if (tour.running || geoDialog.opened) win._geoStartupPending = true
            else win._presentGateBehindDonate()
        }
        // …and it came back: the open gate steps aside on its own.
        function onConnectionRestored() {
            win._geoStartupPending = false
            geoDialog.markCleared()
        }
    }
    Connections {
        target: tour
        function onRunningChanged() {
            if (!tour.running && win._geoStartupPending) {
                win._geoStartupPending = false
                if (Geo.blocked) geoDialog.presentStartup()
            }
        }
    }

    // deno install dialog. yt-dlp needs a JS runtime to solve YouTube's
    // download challenge; when a download point finds it missing it calls
    // Deno.requestInstall(), which fires installRequested and opens this.
    Dialog {
        id: denoDialog
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, win.width - 80)
        padding: 0
        // While downloading, the dialog must not vanish on an outside click —
        // that would silently cancel and leave the user confused later.
        closePolicy: Deno.setupBusy ? Popup.NoAutoClose
                               : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
        onOpened: Deno.refresh()
        onClosed: Deno.clearError()

        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: denoHeadRow.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: denoHeadRow
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.primary, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "extension"; fill: true; size: 20
                        glyphColor: Theme.primary
                    }
                }
                C.AppText {
                    text: I18n.tr("One-time setup for YouTube downloads")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: ColumnLayout {
            spacing: Tokens.space3
            C.AppText {
                text: I18n.tr("YouTube downloads need two required components: a small JavaScript runtime and the PO Token helper. Install them now and your first download will just work.")
                color: Theme.on_surface
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
            }
            // Required-files list: what has to be fetched and its state.
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                radius: Tokens.radiusMd
                color: Theme.surface_low
                border.width: 1
                border.color: Theme.border
                implicitHeight: fileRow.implicitHeight + Tokens.space3 * 2
                RowLayout {
                    id: fileRow
                    anchors.fill: parent
                    anchors.margins: Tokens.space3
                    spacing: Tokens.space3
                    Rectangle {
                        width: 34; height: 34; radius: 10
                        color: U.withAlpha(Deno.available ? Theme.secondary_container : Theme.primary, 0.12)
                        border.width: 1
                        border.color: U.withAlpha(Deno.available ? Theme.secondary_container : Theme.primary, 0.30)
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: Deno.available ? "check_circle" : "extension"
                            fill: true; size: 18
                            glyphColor: Deno.available ? Theme.secondary_container : Theme.primary
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        C.AppText {
                            text: Deno.fileName
                            mono: true
                            weight: Tokens.weightBold
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: I18n.tr("JavaScript runtime for YouTube downloads (~40 MB)")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                        }
                    }
                    C.AppText {
                        text: Deno.available ? I18n.tr("Ready")
                              : (Deno.busy ? (Deno.pct + "%") : I18n.tr("Not installed"))
                        mono: false
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: Deno.available ? Theme.secondary_container
                              : (Deno.busy ? Theme.primary : Theme.warn)
                    }
                }
            }
            // Skip note: dismissing now just defers the same download to the
            // first video download.
            // v3.41.5: second required file — the PO Token helper.
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                radius: Tokens.radiusMd
                color: Theme.surface_low
                border.width: 1
                border.color: Theme.border
                implicitHeight: potFileRow.implicitHeight + Tokens.space3 * 2
                RowLayout {
                    id: potFileRow
                    anchors.fill: parent
                    anchors.margins: Tokens.space3
                    spacing: Tokens.space3
                    Rectangle {
                        width: 34; height: 34; radius: 10
                        color: U.withAlpha(Deno.potInstalled ? Theme.secondary_container : Theme.primary, 0.12)
                        border.width: 1
                        border.color: U.withAlpha(Deno.potInstalled ? Theme.secondary_container : Theme.primary, 0.30)
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: Deno.potInstalled ? "check_circle" : "key"
                            fill: true; size: 18
                            glyphColor: Deno.potInstalled ? Theme.secondary_container : Theme.primary
                        }
                    }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        C.AppText {
                            text: Deno.potFileName
                            mono: true
                            weight: Tokens.weightBold
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: I18n.tr("PO Token helper for YouTube downloads (~44 MB)")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                        }
                    }
                    C.AppText {
                        text: Deno.potInstalled ? I18n.tr("Ready")
                              : (Deno.potBusy ? (Deno.potPct + "%") : I18n.tr("Not installed"))
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: Deno.potInstalled ? Theme.secondary_container
                              : (Deno.potBusy ? Theme.primary : Theme.warn)
                    }
                }
            }
            // Why the last attempt failed — said HERE, in the dialog. Before, the
            // reason only reached the notification tray, so a failed install
            // looked like the dialog blinked and reset itself.
            Rectangle {
                visible: Deno.setupError !== "" && !Deno.setupBusy && !Deno.ready
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                radius: Tokens.radiusMd
                color: U.withAlpha(Theme.error, 0.10)
                border.width: 1
                border.color: U.withAlpha(Theme.error, 0.35)
                implicitHeight: errCol.implicitHeight + Tokens.space3 * 2
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.space3
                    spacing: Tokens.space3
                    C.IconGlyph {
                        Layout.alignment: Qt.AlignTop
                        name: "error"; fill: true; size: 18
                        glyphColor: Theme.error
                    }
                    ColumnLayout {
                        id: errCol
                        Layout.fillWidth: true
                        spacing: 3
                        C.AppText {
                            text: I18n.tr("Couldn't download it")
                            weight: Tokens.weightBold
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: Deno.setupError
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            LayoutMirroring.enabled: false
                        }
                        C.AppText {
                            text: I18n.tr("Turn on your VPN (or set its HTTP proxy in Settings) and try again — or pick a deno.exe / deno zip you already have.")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
            C.AppText {
                visible: !Deno.ready && !Deno.setupBusy && Deno.setupError === ""
                text: I18n.tr("Both are required. If you skip, downloads stay locked and this setup opens again the first time you download a video.")
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
            }
            // Progress bar + file-count/byte readout while downloading.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                spacing: Tokens.space2
                visible: Deno.setupBusy
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: 4
                    color: Theme.surface_high
                    Rectangle {
                        height: parent.height
                        radius: 4
                        width: parent.width * Math.max(0, Math.min(1, (Deno.busy ? Deno.pct : Deno.potPct) / 100))
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: Tokens.durFast } }
                    }
                }
                C.AppText {
                    text: Deno.potBusy
                          ? I18n.tr("File 2 of {t} · PO Token helper · {pct}%")
                              .replace("{t}", Deno.filesTotal)
                              .replace("{pct}", Deno.potPct)
                          : (Deno.totalText !== ""
                           ? I18n.tr("File 1 of {t} · {done} of {total} · {pct}%")
                             .replace("{t}", Deno.filesTotal)
                             .replace("{done}", Deno.doneText)
                             .replace("{total}", Deno.totalText)
                             .replace("{pct}", Deno.pct)
                           : I18n.tr("File 1 of {t} · Downloading… {done}")
                             .replace("{t}", Deno.filesTotal)
                             .replace("{done}", Deno.doneText))
                          + (Deno.source !== "" ? "  ·  " + Deno.source : "")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                }
            }
            // Leaving-mid-download warning.
            C.AppText {
                visible: Deno.setupBusy
                text: I18n.tr("If you close this now, video downloads won't work "
                              + "until it finishes.")
                font.pixelSize: Tokens.fontCaption
                color: Theme.warn
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
            }
        }
        footer: Item {
            implicitHeight: 50 + Tokens.space5 * 2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.topMargin: Tokens.space3
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                C.PrimaryButton {
                    variant: "ghost"
                    text: Deno.setupBusy ? I18n.tr("Cancel")
                          : (Deno.ready ? I18n.tr("Close") : I18n.tr("Skip"))
                    onClicked: { Deno.cancel(); denoDialog.close() }
                }
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    visible: !Deno.setupBusy && !Deno.ready
                    iconName: "folder_open"
                    text: I18n.tr("From file…")
                    onClicked: denoFileDialog.open()
                }
                C.PrimaryButton {
                    visible: !Deno.ready
                    iconName: Deno.setupError !== "" ? "refresh" : "download"
                    text: Deno.setupError !== "" ? I18n.tr("Try again") : I18n.tr("Download and install")
                    enabled: !Deno.setupBusy
                    onClicked: Deno.installAll()
                }
            }
        }
    }

    // Offline install for the deno dialog: a deno.exe or the official
    // deno-*.zip from disk, for a machine that can't reach either mirror.
    FileDialog {
        id: denoFileDialog
        title: Deno.available ? I18n.tr("Pick bgutil-pot.exe")
                              : I18n.tr("Pick deno.exe or the deno zip")
        nameFilters: Deno.available
                     ? [I18n.tr("PO Token helper") + " (*.exe bgutil-pot*)", I18n.tr("All files") + " (*)"]
                     : [I18n.tr("deno runtime") + " (*.exe *.zip deno)", I18n.tr("All files") + " (*)"]
        onAccepted: Deno.installFromAnyFile(selectedFile.toString())
    }

    Connections {
        target: Deno
        function onInstallRequested() { denoDialog.open() }
        function onToast(msg, kind) { /* surfaced via tray; dialog shows status */ }
        // Close only when EVERY required component is in place.
        function onFinished(ok) { if (ok && Deno.ready) denoDialog.close() }
    }

    // Startup check: if a REQUIRED download component (JS runtime or, since
    // v3.41.5, the PO Token helper) is missing, offer it right away instead of
    // failing the first download. Skipping only defers — every download gate
    // checks Deno.ready and reopens this dialog.
    Timer {
        id: startupDepsTimer
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            // First launch: the tour goes first, the setup dialog right after
            // it (it used to pop up on top of the tour's welcome card).
            if (!App.tourSeen || tour.running) { interval = 1500; restart(); return }
            Deno.refresh()
            if (!Deno.ready)
                denoDialog.open()
        }
    }

    // A notification-tray row was clicked and maps to a page — jump there.
    Connections {
        target: Notifications
        function onNavigate(pageIndex) { App.goto(pageIndex) }
    }

    // "Analyze these results" — Niche Finder and Search Archive hand their rows
    // to Niche Scan and the shell does the routing. The pages don't know
    // (or need to know) which page index Insights lives at.
    Connections {
        target: Niche
        function onAnalyzeRequested(rows, query, mode) {
            Insights.analyzeRows(rows, query, mode)
            App.goto(11)   // PAGE_INSIGHTS
        }
    }
    Connections {
        target: Archive
        function onAnalyzeRequested(rows, query, mode) {
            Insights.analyzeRows(rows, query, mode)
            App.goto(11)   // PAGE_INSIGHTS
        }
    }

    // The blueprint pane's "Read on camera" button, from either page that hosts
    // one. Studio loads the script; the overlay is what actually appears.
    Connections {
        target: Studio
        function onOpened() {
            // Not while Content Lab's own prompter tab is already open — that tab
            // hosts this same Teleprompter inline, and popping the overlay on top
            // of it would cover the thing the user just asked to see.
            if (!(App.currentPage === 7 && ContentLab.tab === 1))
                prompterOverlay.open = true
        }
    }

    // ── teleprompter overlay ──
    // The same Teleprompter component Content Lab's prompter tab hosts inline,
    // shown full-window over whichever page launched it. One definition, two
    // entry points — a second copy would drift the moment either is touched.
    Item {
        id: prompterOverlay
        anchors.fill: parent
        z: 900
        property bool open: false
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.72)
            // Swallow clicks so the page underneath can't be operated through
            // the scrim.
            TapHandler { onTapped: {} }
        }

        C.Teleprompter {
            anchors.fill: parent
            anchors.margins: Tokens.space5
            overlayMode: true
            // Only take focus while actually shown, or its Space/Escape handling
            // would eat keys belonging to the page underneath.
            focus: prompterOverlay.open
            onCloseRequested: prompterOverlay.open = false
            scale: prompterOverlay.open ? 1 : 0.98
            Behavior on scale {
                NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
            }
        }
    }
}
