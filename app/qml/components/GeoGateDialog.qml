import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import NicheScope
import "../Utils.js" as U

// ═══════════════════════════════════════════════════════════════════════
//  "Signal lost" — the connection gate (v3.36 redesign)
// ═══════════════════════════════════════════════════════════════════════
//
// Shown when the app cannot work on this connection. Three stories:
//
//   restricted  the public IP is in a country where YouTube is filtered
//               (Iran first and foremost — see app/core/geo.py).
//   offline     not one geo service answered: the internet is down, or only
//               the national intranet is reachable during a shutdown.
//   scrape      the Scraper's Start button, when the YouTube API route is
//               restricted. The run is parked in GeoVM until the user
//               re-checks, overrides or cancels.
//
// It is a TAKEOVER, not a card: it covers the whole page area under the title
// bar (the title bar stays live so the window can still be moved, minimised
// or closed), blurs the app behind it, and says one thing loudly — the app
// will not work until you connect. Skipping is always possible, and says so.
//
// Signature: the OSCILLOSCOPE. A live signal leaves your machine and travels
// toward YouTube. Filtered, it hits a glitching wall halfway and flatlines;
// offline, it barely leaves you before it dies; while checking a beam sweeps
// the whole line; once clear the wave reaches YouTube in green and the
// screen steps aside on its own.
//
// Popups live under Overlay.overlay, a sibling of the mirrored shell, so the
// content root sets LayoutMirroring itself — otherwise Persian would lay out
// left-to-right here. The Canvas is not mirrored by Qt; it draws between the
// two node centres, whose x already reflects the mirrored layout.
Popup {
    id: root
    parent: Overlay.overlay
    // Not modal: a modal scrim would also cover the title bar and freeze the
    // window controls. The takeover blocks the page itself (see the input
    // catcher in `background`).
    modal: false
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: 0
    x: 0
    y: Tokens.titleBarHeight
    width: parent ? parent.width : 1280
    height: parent ? parent.height - Tokens.titleBarHeight : 760

    // "startup" | "scrape" | "download"
    property string mode: "startup"
    property bool _awaiting: false
    property bool _cleared: false

    function presentStartup() { mode = "startup"; _reset(); open() }
    function presentScrape() { mode = "scrape"; _reset(); open() }
    // _awaiting: the fresh check allowDownload() just started decides; a clean
    // answer closes the screen on its own.
    function presentDownload() { mode = "download"; _reset(); _awaiting = true; open() }
    // The live monitor saw the connection come back: show "You're through"
    // briefly, then step aside.
    function markCleared() {
        if (!opened) return
        _awaiting = false
        if (!_blockedNow) { _cleared = true; closeLater.restart() }
    }
    function _reset() { _awaiting = false; _cleared = false; closeLater.stop() }

    readonly property bool _scrape: mode === "scrape"
    readonly property bool _download: mode === "download"
    readonly property bool _offline: !_scrape && Geo.offline
    // Internet works but YouTube itself doesn't answer from this IP.
    readonly property bool _unreachable: !_scrape && !_offline && Geo.reason === "unreachable"
    readonly property bool _blockedNow: _scrape ? Geo.apiBlocked
                                      : _download ? Geo.downloadBlocked
                                      : Geo.blocked
    // checking | blocked | clear
    readonly property string phase: _cleared ? "clear"
                                  : (Geo.checking ? "checking"
                                  : (_blockedNow ? "blocked" : "clear"))
    readonly property color tone: phase === "blocked" ? Theme.error
                                : phase === "clear" ? Theme.secondary_container
                                : Theme.warn
    readonly property string countryText: Geo.countryName !== "" ? Geo.countryName : I18n.tr("a filtered country")
    readonly property bool compact: height < 700
    readonly property bool _live: visible && Tokens.appActive

    onClosed: {
        closeLater.stop()
        // Escape / Cancel / Skip: a parked scrape is dropped, never left hanging.
        if (Geo.gatePending) Geo.cancelGate()
    }

    Connections {
        target: Geo
        function onChanged() {
            if (!root.opened || !root._awaiting || Geo.checking) return
            root._awaiting = false
            if (!root._blockedNow) {
                root._cleared = true
                closeLater.restart()
            }
        }
    }
    Timer { id: closeLater; interval: 1500; onTriggered: root.close() }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durMed; easing.type: Easing.InCubic }
    }

    // ── one numbered step ("how to fix it") ──────────────────────────────
    // Numbered on purpose: the fix IS a sequence (connect, then re-check).
    // Inline components do NOT share the file's id scope, so everything they
    // need from `root` is handed in as a property.
    component Step: RowLayout {
        id: st
        property color tone: "red"
        property bool compact: false
        property int num: 1
        property string label: ""
        property string hint: ""
        property bool last: false
        spacing: 14
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 30
            Layout.fillHeight: true
            Rectangle {
                id: numDot
                width: 30; height: 30; radius: 15
                color: U.withAlpha(st.tone, 0.14)
                border.width: 1
                border.color: U.withAlpha(st.tone, 0.45)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                AppText {
                    anchors.centerIn: parent
                    text: I18n.rtl ? String(st.num).replace(/[0-9]/g, function(d) { return "۰۱۲۳۴۵۶۷۸۹"[d] }) : String(st.num)
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontBody
                    color: st.tone
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            // the thread that ties step to step
            Rectangle {
                visible: !st.last
                anchors.horizontalCenter: numDot.horizontalCenter
                anchors.top: numDot.bottom
                anchors.topMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -10
                width: 1
                color: U.withAlpha(st.tone, 0.25)
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            AppText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: st.label
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontLabel
                color: Theme.text_strong
                wrapMode: Text.Wrap
            }
            AppText {
                Layout.fillWidth: true
                visible: st.hint !== "" && !st.compact
                text: st.hint
                font.pixelSize: Tokens.fontBody
                color: Theme.on_surface_var
                wrapMode: Text.Wrap
                lineHeight: 1.35
            }
        }
    }

    // a node: you, or YouTube
    component Node: Column {
        id: nd
        property string glyph: ""
        property color ink: "red"
        property bool dead: false
        property string caption: ""
        property bool monoCaption: false
        property string tag: ""
        property real lineY: 56
        y: lineY - 30
        spacing: 10
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 60; height: 60; radius: 20
            color: nd.dead ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(nd.ink, 0.13)
            border.width: 1
            border.color: nd.dead ? U.withAlpha(Theme.on_surface, 0.12) : U.withAlpha(nd.ink, 0.45)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
            IconGlyph {
                anchors.centerIn: parent
                name: nd.glyph; fill: true; size: 26
                glyphColor: nd.dead ? Theme.outline : nd.ink
                opacity: nd.dead ? 0.6 : 1
            }
            Rectangle {
                visible: nd.tag !== ""
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -8
                anchors.bottomMargin: -6
                height: 20
                width: tagTxt.implicitWidth + 12
                radius: 10
                color: nd.ink
                AppText {
                    id: tagTxt
                    anchors.centerIn: parent
                    text: nd.tag
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.isDark ? Theme.background : "white"
                }
            }
        }
        AppText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: nd.caption
            mono: nd.monoCaption
            font.pixelSize: Tokens.fontCaption
            weight: Tokens.weightDemiBold
            color: Theme.on_surface_var
        }
    }


    // ═══ backdrop ═════════════════════════════════════════════════════════
    background: Item {
        id: bg
        readonly property bool maxed: Window.window ? Window.window.isMaximized === true : false
        readonly property int r: maxed ? 0 : Tokens.windowRadius - 1

        // Swallow every press / wheel / hover on the page area: the takeover
        // is non-modal only so the title bar keeps working.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onWheel: (w) => { w.accepted = true }
        }

        // the app behind, pushed far back
        Item {
            anchors.fill: parent
            clip: true
            DialogScrim {
                anchors.fill: parent
                opacity: root.visible ? 1 : 0
                blurPx: 22
                dimOpacity: 0
                sourceRect: Qt.rect(0, Tokens.titleBarHeight, bg.width, bg.height)
            }
        }
        Rectangle {
            anchors.fill: parent
            bottomLeftRadius: bg.r
            bottomRightRadius: bg.r
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.background, Theme.isDark ? 0.80 : 0.74) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.background, Theme.isDark ? 0.94 : 0.90) }
            }
        }
        // the light of the failing signal, bleeding up from behind the scope
        GlowBlob {
            anchors.horizontalCenter: parent.horizontalCenter
            y: stageAnchor.y - size / 2 + 40
            size: Math.min(bg.width * 0.9, 900)
            glow: root.tone
            strength: (Theme.isDark ? 0.20 : 0.12) * (0.85 + 0.15 * breath)
            property real breath: 0
            SequentialAnimation on breath {
                running: root._live
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 2400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0; duration: 2400; easing.type: Easing.InOutSine }
            }
        }
        // fine scanlines: the screen of an instrument, felt more than seen
        Item {
            anchors.fill: parent
            opacity: Theme.isDark ? 0.035 : 0.025
            Repeater {
                model: Math.max(0, Math.ceil(bg.height / 4))
                Rectangle { y: index * 4; width: bg.width; height: 1; color: Theme.on_surface }
            }
        }
        // where the scope sits in backdrop coordinates (glow anchor)
        Item { id: stageAnchor; y: body.y + col.y + stage.y + stage.height / 2 - flick.contentY }
    }

    // ═══ content ═════════════════════════════════════════════════════════
    contentItem: Item {
        id: body
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: Math.max(height, col.implicitHeight + 64)
            interactive: contentHeight > height + 1
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: col
                width: Math.min(640, body.width - 96)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(32, (flick.contentHeight - implicitHeight) / 2)
                spacing: 0

                // ── status chip ────────────────────────────────────────
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitHeight: 32
                    implicitWidth: chipRow.implicitWidth + 28
                    radius: 16
                    color: U.withAlpha(root.tone, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(root.tone, 0.40)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 10
                        Item {
                            width: 8; height: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                id: chipPulse
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                color: root.tone
                                SequentialAnimation on opacity {
                                    running: root._live && root.phase !== "clear"
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.25; to: 1; duration: 650; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                        AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.phase === "checking" ? I18n.tr("Checking connection …")
                                : root.phase === "clear" ? I18n.tr("Connected")
                                : root._offline ? I18n.tr("No internet")
                                : root._unreachable ? I18n.tr("YouTube isn't answering")
                                : I18n.tr("YouTube is blocked")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            color: root.tone
                        }
                        Rectangle {
                            visible: ipLbl.visible
                            width: 1; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: U.withAlpha(root.tone, 0.35)
                        }
                        AppText {
                            id: ipLbl
                            visible: Geo.ip !== "" && root.phase !== "checking"
                            anchors.verticalCenter: parent.verticalCenter
                            text: Geo.ip + (Geo.countryCode !== "" ? "  ·  " + Geo.countryCode : "")
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                        }
                    }
                }

                // ── the oscilloscope ───────────────────────────────────
                Item {
                    id: stage
                    Layout.fillWidth: true
                    Layout.topMargin: root.compact ? 18 : 28
                    Layout.preferredHeight: root.compact ? 118 : 150

                    readonly property real lineY: 56
                    readonly property real youX: youNode.x + youNode.width / 2
                    readonly property real ytX: ytNode.x + ytNode.width / 2
                    readonly property real dir: ytX >= youX ? 1 : -1
                    // where the signal is cut, as a share of the line
                    readonly property real cut: root.phase === "clear" || root.phase === "checking" ? 1.0
                                              : root._offline ? 0.16 : 0.5
                    readonly property real gap: 40    // node radius + breathing room
                    readonly property real x0: youX + dir * gap
                    readonly property real x1: ytX - dir * gap
                    readonly property real breachX: x0 + (x1 - x0) * cut

                    // the wave + the dead line, painted ~30 fps
                    Canvas {
                        id: scope
                        anchors.fill: parent
                        property real t: 0
                        property int glitchSeed: 0
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const x0 = stage.x0, x1 = stage.x1, yc = stage.lineY
                            const len = Math.abs(x1 - x0)
                            if (len < 20) return
                            const d = stage.dir
                            const cut = stage.cut
                            const ph = root.phase
                            const amp = ph === "clear" ? 15 : ph === "checking" ? 3 : 19
                            const T = scope.t
                            const toneS = "" + root.tone
                            const deadS = "" + Theme.outline

                            function wy(u) {
                                const f = u / len
                                let env = Math.min(1, f / 0.07)                // rises out of you
                                if (cut < 1) env *= Math.max(0, Math.min(1, (cut - f) / 0.09))   // dies at the wall
                                else env *= Math.min(1, (1 - f) / 0.07)       // lands in YouTube
                                let w = Math.sin(u * 0.085 - T * 6.2) * 0.62
                                      + Math.sin(u * 0.031 - T * 2.6) * 0.38
                                if (ph === "blocked" && f > cut - 0.12 && f < cut)
                                    w += (Math.sin(u * 1.7 + T * 40) * 0.5)    // the stutter before the wall
                                if (ph === "checking") {
                                    const beam = ((T * 0.55) % 1.2) - 0.1        // a sweep, edge to edge
                                    const g = Math.exp(-Math.pow((f - beam) / 0.05, 2))
                                    w = w * 0.4 + Math.sin(u * 0.22 - T * 9) * g * 5
                                }
                                return yc + amp * env * w
                            }

                            const liveEnd = len * Math.min(1, cut)
                            // dead stretch past the cut: a faint dashed flatline
                            if (cut < 1) {
                                ctx.globalAlpha = 0.28
                                ctx.strokeStyle = deadS
                                ctx.lineWidth = 1.5
                                for (let u = liveEnd + 14; u < len; u += 9) {
                                    ctx.beginPath()
                                    ctx.moveTo(x0 + d * u, yc)
                                    ctx.lineTo(x0 + d * Math.min(len, u + 4), yc)
                                    ctx.stroke()
                                }
                            }
                            // the live wave: a soft halo pass, then the crisp trace
                            for (let pass = 0; pass < 2; pass++) {
                                ctx.globalAlpha = pass === 0 ? 0.20 : 1.0
                                ctx.lineWidth = pass === 0 ? 7 : 2.2
                                ctx.strokeStyle = toneS
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                ctx.moveTo(x0, yc)
                                for (let u = 2; u <= liveEnd; u += 2)
                                    ctx.lineTo(x0 + d * u, wy(u))
                                ctx.stroke()
                            }
                            // the wall: glitching bars at the breach
                            if (ph === "blocked") {
                                ctx.globalAlpha = 0.9
                                ctx.fillStyle = toneS
                                let s = scope.glitchSeed
                                for (let i = 0; i < 5; i++) {
                                    s = (s * 9301 + 49297) % 233280
                                    const h = 10 + (s / 233280) * 44
                                    const bx = stage.breachX + d * (i - 2) * 5
                                    ctx.globalAlpha = 0.35 + 0.55 * ((s % 7) / 7)
                                    ctx.fillRect(bx - 1, yc - h / 2, 2, h)
                                }
                            }
                        }
                        Timer {
                            interval: 33
                            repeat: true
                            running: root._live
                            onTriggered: {
                                scope.t += 0.033
                                if (Math.round(scope.t * 30) % 4 === 0) scope.glitchSeed = (scope.glitchSeed + 17) % 997
                                scope.requestPaint()
                            }
                        }
                    }

                    // the breach marker: a ring that keeps trying to close
                    Item {
                        visible: root.phase === "blocked"
                        width: 46; height: 46
                        x: stage.breachX - width / 2
                        y: stage.lineY - height / 2
                        Rectangle {
                            id: breachRing
                            anchors.centerIn: parent
                            width: 26; height: 26; radius: 13
                            color: "transparent"
                            border.width: 1.5
                            border.color: root.tone
                            opacity: 0
                            SequentialAnimation {
                                running: root._live && root.phase === "blocked"
                                loops: Animation.Infinite
                                ParallelAnimation {
                                    NumberAnimation { target: breachRing; property: "scale"; from: 0.8; to: 2.4; duration: 1500; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: breachRing; property: "opacity"; from: 0.6; to: 0; duration: 1500; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }

                    Node {
                        id: youNode
                        anchors.left: parent.left
                        lineY: stage.lineY
                        ink: root.tone
                        glyph: root._offline ? "desktop_windows" : "public"
                        tag: Geo.countryCode
                        caption: I18n.tr("You")
                    }
                    Node {
                        id: ytNode
                        anchors.right: parent.right
                        lineY: stage.lineY
                        glyph: "youtube"
                        ink: Theme.secondary_container
                        dead: root.phase !== "clear"
                        caption: "YouTube"
                    }
                }

                // ── the words ──────────────────────────────────────────
                AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: root.compact ? 6 : 14
                    horizontalAlignment: Text.AlignHCenter
                    text: root.phase === "clear" ? I18n.tr("You're through.")
                        : root._scrape ? I18n.tr("Extraction can't run on this connection")
                        : root._offline ? I18n.tr("Your internet is down")
                        : root._download ? I18n.tr("Downloads can't run on this connection")
                        : I18n.tr("Your internet can't reach YouTube")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: root.compact ? 28 : 36
                    lineHeight: 1.12
                    wrapMode: Text.Wrap
                    color: Theme.text_strong
                }
                AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    visible: root.phase !== "clear"
                    horizontalAlignment: Text.AlignHCenter
                    text: root._scrape ? I18n.tr("This run would stop at the first request.")
                        : root._download ? I18n.tr("The download would fail before the first byte.")
                        : I18n.tr("The app won't work until you connect.")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: root.compact ? 20 : 24
                    wrapMode: Text.Wrap
                    color: root.tone
                }
                AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: root.phase === "clear"
                          ? (root._scrape ? I18n.tr("Starting your scrape now.")
                             : root._download ? I18n.tr("YouTube is reachable again. Start your download.")
                             : I18n.tr("YouTube is reachable from this connection. Enjoy."))
                          : root._scrape
                            ? I18n.tr("Google's YouTube API refuses every request from {c}, so this run would stop at the first call and save nothing.").replace("{c}", root.countryText)
                          : root._offline
                            ? I18n.tr("Not one server answered. Either the internet is cut, or only the domestic network is reachable right now.")
                          : root._unreachable
                            ? (Geo.youtubeRefused
                               ? I18n.tr("Your internet works, but YouTube refuses requests from this IP ({c}). This VPN server is probably blocked by YouTube — switch to another server or location.").replace("{c}", root.countryText)
                               : I18n.tr("Your internet works, but YouTube doesn't answer from this IP ({c}). It is filtered on this network or blocked by YouTube — switch your VPN on, or pick another server.").replace("{c}", root.countryText))
                            : I18n.tr("Your IP is in {c}, where YouTube is filtered. Extraction, search, downloads and subtitles all need YouTube.").replace("{c}", root.countryText)
                    wrapMode: Text.Wrap
                    lineHeight: 1.45
                    font.pixelSize: Tokens.fontLabel
                    color: Theme.on_surface_var
                }

                // ── the fix ────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: root.compact ? 18 : 26
                    visible: root.phase !== "clear"
                    implicitHeight: steps.implicitHeight + 40
                    radius: Tokens.radiusXl
                    color: U.withAlpha(Theme.surface, Theme.isDark ? 0.72 : 0.85)
                    border.width: 1
                    border.color: Theme.border
                    ColumnLayout {
                        id: steps
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 20
                        spacing: 14
                        Step {
                            Layout.fillWidth: true
                            tone: root.tone
                            compact: root.compact
                            visible: root._offline
                            num: 1
                            label: I18n.tr("Check your Wi-Fi or cable")
                            hint: I18n.tr("Make sure the computer itself is online.")
                        }
                        Step {
                            Layout.fillWidth: true
                            tone: root.tone
                            compact: root.compact
                            num: root._offline ? 2 : 1
                            label: root._unreachable ? I18n.tr("Switch VPN server or location")
                                                     : I18n.tr("Turn your VPN on (TUN mode)")
                            hint: root._unreachable
                                  ? I18n.tr("Pick a different country or server in your VPN app. Keep TUN / system-wide mode on.")
                                  : I18n.tr("In v2rayN, Hiddify or a similar app pick TUN / system-wide mode. “System proxy” alone isn't enough.")
                        }
                        Step {
                            Layout.fillWidth: true
                            tone: root.tone
                            compact: root.compact
                            num: root._offline ? 3 : 2
                            last: true
                            label: I18n.tr("Press “Check again”")
                            hint: I18n.tr("The app keeps checking in the background. Once you're through, this screen closes on its own.")
                        }
                    }
                }

                // the split case: the Settings proxy fixes downloads, the API still leaks out
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    visible: Geo.splitRoute && root.phase !== "clear"
                    implicitHeight: splitTxt.implicitHeight + 22
                    radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.warn, 0.10)
                    border.width: 1
                    border.color: U.withAlpha(Theme.warn, 0.30)
                    AppText {
                        id: splitTxt
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16; anchors.rightMargin: 16
                        text: I18n.tr("Your Settings proxy exits in {w}, so downloads are fine — but the YouTube API still leaves from {c}.")
                              .replace("{w}", Geo.webCountryName).replace("{c}", root.countryText)
                        font.pixelSize: Tokens.fontBody
                        color: Theme.on_surface
                        wrapMode: Text.Wrap
                    }
                }

                // ── actions ────────────────────────────────────────────
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: root.compact ? 18 : 26
                    visible: root.phase !== "clear"
                    spacing: 10
                    PrimaryButton {
                        text: Geo.checking ? I18n.tr("Checking …") : I18n.tr("Check again")
                        iconName: "refresh"
                        indeterminate: Geo.checking
                        enabled: !Geo.checking
                        Layout.minimumWidth: 190
                        onClicked: { root._awaiting = true; Geo.recheck() }
                    }
                    PrimaryButton {
                        variant: "ghost"
                        text: root._scrape ? I18n.tr("Scrape anyway") : I18n.tr("Proxy settings")
                        iconName: root._scrape ? (I18n.rtl ? "arrow_back" : "arrow_forward") : "settings"
                        enabled: !Geo.checking
                        onClicked: {
                            if (root._scrape) {
                                Geo.override()
                                root.close()
                            } else {
                                root.close()
                                App.goto(10)
                            }
                        }
                    }
                }

                // the skip: always there, always honest about what it means
                AbstractButton {
                    id: skipBtn
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 12
                    visible: root.phase !== "clear"
                    implicitHeight: 36
                    implicitWidth: skipLbl.implicitWidth + 28
                    hoverEnabled: true
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle {
                        radius: 18
                        color: skipBtn.hovered ? U.withAlpha(Theme.on_surface, 0.07) : U.withAlpha(Theme.on_surface, 0)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    contentItem: AppText {
                        id: skipLbl
                        text: (root._scrape || root._download) ? I18n.tr("Cancel") : I18n.tr("Skip — I know the app won't work")
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontBody
                        font.underline: skipBtn.hovered
                        color: skipBtn.hovered ? Theme.on_surface : Theme.on_surface_var
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: root.close()
                }
            }
        }
    }
}
