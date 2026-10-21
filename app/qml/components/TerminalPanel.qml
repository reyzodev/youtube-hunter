import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v16 "Run stream" — the scrape's live output.
//
// The old panel printed the scraper's raw text (emoji + box-drawing rules +
// padded counters) into a fake terminal. This one keeps the SAME public API
// (hostLabel / emptyText / showProgress / progress / maxLines, appendLine(),
// clear(), bufferText(), copyRequested, clearRequested) and adds `running`,
// but PARSES every line into a structured event and draws it as a feed:
//
//   ┌ ● LIVE  Run stream   /scrape/live          ✓12 ⚠1 ✕0  [All|Issues] ⧉ 🗑 ┐
//   │━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  42%           │
//   │  ⚡ Scraper started · Strategy: Popular                 (banner)         │
//   │ 11:34  ◉ Channel ID: UC…                                                 │
//   │ 11:34  ▶ 2/4  ▓▓▓▓░░  Pww8rIzr1pg        [Transcript found]   +4s       │
//   │ ───────────────────────── (section) ─────────────────────────            │
//   │        [✓ Success 4] [✕ Failed 0] [📝 Transcripts 4/4]   (stat chips)    │
//   │  ✦ Scraping completed successfully!                     (done banner)   │
//   └──────────────────────────────────────────────── [↓ Latest] ─────────────┘
//
// Box-drawing rules become hairline section breaks (the ═ frames around the
// start/finish lines are dropped — those lines are banners now), leading
// emoji become theme-coloured glyph chips, per-video lines become rows with a
// mini progress meter and a status pill, and the summary line becomes chips.
// Anything unrecognised still renders as a plain line, so a new VM message
// can never be lost. Copy still yields the original raw text.
Item {
    id: root

    property string hostLabel: "root@core-engine:~ /logs/live"
    property string emptyText: I18n.tr("No activity yet. Start a scrape.")
    property bool showProgress: false
    property real progress: 0
    // v16: drives the LIVE orb + progress shimmer. Optional.
    property bool running: false
    property int maxLines: 2000
    signal copyRequested(string text)
    signal clearRequested()

    readonly property int lineCount: lines.count
    readonly property bool hasLines: lines.count > 0

    // counters shown in the header
    property int okCount: 0
    property int warnCount: 0
    property int errCount: 0
    // "issues only" filter
    property bool issuesOnly: false
    property bool finished: false
    property double _lastMs: 0

    readonly property color paneBg: Theme.isDark ? "#09090C" : "#FBFBFD"
    readonly property color rowHover: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.035)
    readonly property color stampColor: Theme.isDark ? "#4D4D58" : "#A3A3AE"
    readonly property color okColor: Theme.isDark ? "#34E3A4" : "#0E9F6E"
    readonly property color warnColor: Theme.isDark ? "#FFC857" : "#B9770B"
    readonly property color errColor: Theme.isDark ? "#FF6B6B" : Theme.error
    readonly property color infoColor: Theme.isDark ? "#7FB2FF" : "#2563C9"
    readonly property color textColor: Theme.isDark ? "#D4D4DC" : Theme.on_surface
    readonly property color dimText: Theme.isDark ? "#8A8A96" : Theme.on_surface_var

    function toneOf(level) {
        return level === "error" ? errColor
             : level === "warn"  ? warnColor
             : level === "ok"    ? okColor
             : level === "accent" ? Theme.primary
             : infoColor
    }

    ListModel { id: lines }

    // ── parsing ───────────────────────────────────────────────────────────
    // leading emoji → (glyph, level). Order matters for multi-codepoint ones.
    readonly property var _lead: [
        ["✅", "check_circle", "ok"],   ["✔", "check_circle", "ok"],
        ["❌", "error", "error"],       ["✗", "error", "error"],
        ["🚫", "error", "error"],
        ["⚠️", "warning", "warn"],      ["⚠", "warning", "warn"],
        ["🚀", "bolt", "accent"],
        ["🎉", "sparkling", "ok"],
        ["📡", "public", "info"],       ["🌐", "language", "info"],
        ["📥", "download", "info"],     ["🎯", "target", "info"],
        ["💾", "save", "info"],         ["📝", "article", "info"],
        ["⏭", "arrow_forward", "info"], ["⏩", "arrow_forward", "info"],
        ["ℹ️", "info", "info"],         ["ℹ", "info", "info"],
        ["📹", "video", "info"]
    ]

    function _stripLead(t) {
        for (var i = 0; i < _lead.length; i++) {
            var e = _lead[i][0]
            if (t.indexOf(e) === 0) {
                var rest = t.substring(e.length).replace(/^[\uFE0F\s]+/, "")
                return { emoji: e, icon: _lead[i][1], level: _lead[i][2], rest: rest }
            }
        }
        return { emoji: "", icon: "", level: "", rest: t }
    }

    function _wordLevel(text) {
        var t = (text || "").toLowerCase()
        if (t.indexOf("error") >= 0 || t.indexOf("failed") >= 0 || t.indexOf("exception") >= 0)
            return "error"
        if (t.indexOf("warn") >= 0 || t.indexOf("retry") >= 0 || t.indexOf("quota") >= 0)
            return "warn"
        if (t.indexOf("done") >= 0 || t.indexOf("complete") >= 0 || t.indexOf("saved") >= 0)
            return "ok"
        return "info"
    }

    function _parse(raw) {
        var t = raw || ""
        var gap = 0
        while (t.length && t.charAt(0) === "\n") { gap++; t = t.substring(1) }
        t = t.replace(/\n+$/, "")
        var indent = (t.match(/^\s*/) || [""])[0].length
        var s = t.trim()
        var ev = { kind: "line", level: "info", icon: "", text: s, a: 0, b: 0, pct: 0,
                   vid: "", status: "", statusLevel: "", chips: "[]", gap: gap }

        if (s === "") { ev.kind = "blank"; return ev }
        if (/^[─━═\-=_]{6,}$/.test(s)) {
            ev.kind = (s.charAt(0) === "═" || s.charAt(0) === "=") ? "frame" : "rule"
            return ev
        }

        // summary line: two or more status emoji on one line → chips
        var marks = s.match(/(✅|❌|📝|⏭)/g) || []
        if (marks.length >= 2 && s.indexOf("📹") < 0) {
            var parts = s.split(/(✅|❌|📝|⏭)/)
            var chips = []
            for (var i = 1; i < parts.length; i += 2) {
                var em = parts[i], body = (parts[i + 1] || "").replace(/^[\uFE0F\s]+/, "").trim()
                var lv = em === "✅" ? "ok" : em === "❌" ? "error" : "info"
                var ic = em === "✅" ? "check_circle" : em === "❌" ? "error" : em === "📝" ? "article" : "arrow_forward"
                // a zero failure count is good news, not an error
                if (lv === "error" && /[:：]\s*0(\D|$)/.test(body)) lv = "muted"
                chips.push({ icon: ic, level: lv, text: body })
            }
            ev.kind = "stats"
            ev.chips = JSON.stringify(chips)
            return ev
        }

        var lead = _stripLead(s)
        ev.icon = lead.icon
        ev.text = lead.rest
        ev.level = lead.level !== "" ? lead.level : _wordLevel(s)

        if (lead.emoji === "📹") {
            var m = lead.rest.match(/^\[\s*(\d+)\s*\/\s*(\d+)\s*\]\s*\(\s*(\d+)\s*%\)\s+(\S+)\s*(.*)$/)
            if (m) {
                ev.kind = "video"
                ev.a = parseInt(m[1]); ev.b = parseInt(m[2]); ev.pct = parseInt(m[3])
                ev.vid = m[4]
                var st = _stripLead(m[5].trim())
                ev.status = st.rest
                ev.statusLevel = st.level !== "" ? st.level : _wordLevel(m[5])
                ev.level = ev.statusLevel
                return ev
            }
        }
        if (lead.emoji === "🚀") { ev.kind = "start"; return ev }
        if (lead.emoji === "🎉") { ev.kind = "done"; return ev }
        if (lead.emoji === "" && indent >= 3) { ev.kind = "note"; ev.level = "muted"; return ev }
        return ev
    }

    function _stamp(d) {
        function p(n) { return (n < 10 ? "0" : "") + n }
        return p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
    }

    function appendLine(text) {
        var d = new Date()
        var ms = d.getTime()
        var ev = _parse(text)
        if (ev.kind === "blank") return
        if (ev.kind === "start") { okCount = 0; warnCount = 0; errCount = 0; finished = false }
        if (ev.kind === "done") finished = true
        if (ev.level === "ok" && (ev.kind === "video" || ev.kind === "line")) okCount++
        else if (ev.level === "warn") warnCount++
        else if (ev.level === "error") errCount++

        var delta = (_lastMs > 0 && ev.kind === "video") ? Math.round((ms - _lastMs) / 1000) : -1
        _lastMs = ms
        lines.append({
            ts: _stamp(d), body: text || "", kind: ev.kind, level: ev.level,
            icon: ev.icon, text: ev.text, a: ev.a, b: ev.b, pct: ev.pct,
            vid: ev.vid, status: ev.status, statusLevel: ev.statusLevel,
            chips: ev.chips, gap: ev.gap, delta: delta
        })
        while (lines.count > root.maxLines)
            lines.remove(0)
        if (view.atYEnd || view.contentHeight <= view.height || root._follow)
            Qt.callLater(root._toEnd)
    }

    property bool _follow: true
    function _toEnd() { view.positionViewAtEnd() }

    function clear() {
        lines.clear()
        okCount = 0; warnCount = 0; errCount = 0
        finished = false
        _lastMs = 0
        _follow = true
    }

    function bufferText() {
        var out = []
        for (var i = 0; i < lines.count; i++) {
            var l = lines.get(i)
            out.push("[" + l.ts + "] " + l.body.replace(/^\n+/, ""))
        }
        return out.join("\n")
    }

    // ── window ───────────────────────────────────────────────────────────
    C.GlassPanel {
        id: frame
        anchors.fill: parent
        radius: Tokens.radiusXl
        color: root.paneBg

        // soft accent glow at the top while running
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 140
            radius: frame.radius
            opacity: root.running ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.05) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── header ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space4
                    anchors.rightMargin: Tokens.space3
                    spacing: Tokens.space3

                    // status orb
                    Item {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        readonly property color c: root.running ? Theme.primary
                                                 : root.errCount > 0 && !root.finished ? root.errColor
                                                 : root.finished ? root.okColor : Theme.outline
                        Rectangle {
                            id: orbPulse
                            anchors.centerIn: parent
                            width: 26; height: 26; radius: 13
                            color: U.withAlpha(parent.c, 0.18)
                            SequentialAnimation on scale {
                                running: root.running && root.visible && Tokens.appActive
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { from: 0.7; to: 1.15; duration: 900; easing.type: Easing.OutCubic }
                                NumberAnimation { to: 0.7; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            visible: !root.finished || root.running
                            color: parent.c
                        }
                        C.IconGlyph {
                            anchors.centerIn: parent
                            visible: root.finished && !root.running
                            name: "check"; size: 14
                            glyphColor: root.okColor
                        }
                    }

                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Row {
                            spacing: Tokens.space2
                            C.AppText {
                                text: I18n.tr("Run stream")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.text_strong
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18; radius: 9
                                width: liveLbl.implicitWidth + 12
                                color: root.running ? U.withAlpha(Theme.primary, 0.16)
                                     : root.finished ? U.withAlpha(root.okColor, 0.14)
                                     : U.withAlpha(Theme.outline, 0.14)
                                C.AppText {
                                    id: liveLbl
                                    anchors.centerIn: parent
                                    text: root.running ? I18n.tr("LIVE")
                                        : root.finished ? I18n.tr("COMPLETE")
                                        : root.hasLines ? I18n.tr("IDLE") : I18n.tr("READY")
                                    weight: Tokens.weightBold
                                    font.pixelSize: 10
                                    font.letterSpacing: I18n.rtl ? 0 : 0.8
                                    color: root.running ? Theme.primary
                                         : root.finished ? root.okColor : Theme.on_surface_var
                                }
                            }
                        }
                        C.AppText {
                            text: root.hostLabel
                            mono: true
                            font.pixelSize: 11
                            color: Theme.outline
                            elide: Text.ElideMiddle
                            width: Math.min(implicitWidth, 320)
                            LayoutMirroring.enabled: false
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // counters
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        visible: root.hasLines
                        Repeater {
                            model: [
                                { i: "check_circle", n: root.okCount,   c: root.okColor,   t: I18n.tr("Succeeded") },
                                { i: "warning",      n: root.warnCount, c: root.warnColor, t: I18n.tr("Warnings") },
                                { i: "error",        n: root.errCount,  c: root.errColor,  t: I18n.tr("Errors") }
                            ]
                            Rectangle {
                                height: 26; radius: 8
                                width: cRow.implicitWidth + 14
                                color: modelData.n > 0 ? U.withAlpha(modelData.c, 0.12) : "transparent"
                                border.width: 1
                                border.color: modelData.n > 0 ? U.withAlpha(modelData.c, 0.28) : Theme.border
                                Row {
                                    id: cRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    C.IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.i; fill: true; size: 13
                                        glyphColor: modelData.n > 0 ? modelData.c : Theme.outline
                                    }
                                    C.AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.n
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: 12
                                        color: modelData.n > 0 ? modelData.c : Theme.outline
                                    }
                                }
                                HoverHandler { id: cHover }
                                C.AppTooltip { visible: cHover.hovered; delay: 300; text: modelData.t }
                            }
                        }
                    }

                    // All / Issues filter
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.hasLines
                        height: 28; radius: 9
                        width: segRow.implicitWidth + 4
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.04)
                        border.width: 1
                        border.color: Theme.border
                        Rectangle {
                            y: 2; height: parent.height - 4; radius: 7
                            x: 2 + (root.issuesOnly ? segAll.width : 0)
                            width: root.issuesOnly ? segIssues.width : segAll.width
                            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Theme.panel_bg
                            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            id: segRow
                            x: 2
                            anchors.verticalCenter: parent.verticalCenter
                            LayoutMirroring.enabled: false
                            Item {
                                id: segAll
                                height: 24
                                width: segAllT.implicitWidth + 18
                                C.AppText {
                                    id: segAllT
                                    anchors.centerIn: parent
                                    text: I18n.tr("All")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: 11
                                    color: !root.issuesOnly ? Theme.text_strong : Theme.on_surface_var
                                }
                                TapHandler { onTapped: root.issuesOnly = false }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                            Item {
                                id: segIssues
                                height: 24
                                width: segIssT.implicitWidth + 18
                                C.AppText {
                                    id: segIssT
                                    anchors.centerIn: parent
                                    text: I18n.tr("Issues")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: 11
                                    color: root.issuesOnly ? Theme.text_strong : Theme.on_surface_var
                                }
                                TapHandler { onTapped: root.issuesOnly = true }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }

                    C.IconButton {
                        iconName: "content_copy"
                        accent: Theme.primary
                        implicitWidth: 30; implicitHeight: 30
                        glyphSize: 15
                        enabled: root.hasLines
                        tip: I18n.tr("Copy the whole log")
                        onClicked: root.copyRequested(root.bufferText())
                    }
                    C.IconButton {
                        iconName: "delete"
                        accent: Theme.primary
                        implicitWidth: 30; implicitHeight: 30
                        glyphSize: 15
                        enabled: root.hasLines && !root.running
                        tip: I18n.tr("Clear the log view")
                        onClicked: root.clearRequested()
                    }
                }
            }

            // ── progress ──
            Item {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space4
                Layout.rightMargin: Tokens.space4
                Layout.preferredHeight: root.showProgress ? 18 : 0
                visible: root.showProgress
                readonly property real p: Math.max(0, Math.min(1, root.progress / 100))
                Rectangle {
                    id: pTrack
                    anchors.left: parent.left
                    anchors.right: pctLbl.left
                    anchors.rightMargin: Tokens.space3
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4; radius: 2
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
                    clip: true
                    LayoutMirroring.enabled: false
                    Rectangle {
                        id: pFill
                        height: parent.height; radius: 2
                        width: parent.width * parent.parent.p
                        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.55) }
                            GradientStop { position: 1.0; color: root.finished ? root.okColor : Theme.primary }
                        }
                        // travelling shimmer while running
                        Rectangle {
                            id: shim
                            visible: root.running
                            width: 60; height: parent.height
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                            }
                            NumberAnimation on x {
                                running: root.running && root.visible && Tokens.appActive
                                loops: Animation.Infinite
                                from: -60; to: Math.max(60, pFill.width)
                                duration: 1400
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }
                C.AppText {
                    id: pctLbl
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(root.progress) + "%"
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: 11
                    color: root.finished ? root.okColor : Theme.primary
                    LayoutMirroring.enabled: false
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space2
                height: 1
                color: Theme.border
            }

            // ── stream ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                LayoutMirroring.enabled: false
                LayoutMirroring.childrenInherit: true

                // empty state
                Column {
                    anchors.centerIn: parent
                    visible: !root.hasLines
                    spacing: Tokens.space3
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 44; height: 44; radius: 14
                        color: U.withAlpha(Theme.primary, 0.10)
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.25)
                        C.IconGlyph { anchors.centerIn: parent; name: "terminal"; size: 20; glyphColor: Theme.primary }
                    }
                    C.AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.emptyText
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                ListView {
                    id: view
                    anchors.fill: parent
                    anchors.topMargin: Tokens.space2
                    anchors.bottomMargin: Tokens.space2
                    clip: true
                    spacing: 0
                    model: lines
                    boundsBehavior: Flickable.StopAtBounds
                    onMovementEnded: root._follow = atYEnd
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: rowItem
                        required property int index
                        required property string ts
                        required property string kind
                        required property string level
                        required property string icon
                        required property string text
                        required property int a
                        required property int b
                        required property int pct
                        required property string vid
                        required property string status
                        required property string statusLevel
                        required property string chips
                        required property int gap
                        required property int delta

                        readonly property bool hiddenByFilter: root.issuesOnly && !(level === "error" || level === "warn")
                        readonly property bool isFrame: kind === "frame"
                        width: view.width
                        visible: !hiddenByFilter && !isFrame
                        height: visible ? loader.height + (gap > 0 && !root.issuesOnly ? 8 : 0) : 0
                        readonly property color tone: root.toneOf(level)

                        // entrance
                        opacity: 1
                        Component.onCompleted: if (index === lines.count - 1 && root.running) fadeIn.start()
                        NumberAnimation { id: fadeIn; target: rowItem; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }

                        HoverHandler { id: rh }

                        Loader {
                            id: loader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            active: rowItem.visible
                            sourceComponent: rowItem.kind === "rule" ? ruleC
                                           : rowItem.kind === "start" ? bannerC
                                           : rowItem.kind === "done" ? bannerC
                                           : rowItem.kind === "stats" ? statsC
                                           : rowItem.kind === "video" ? videoC
                                           : lineC
                        }

                        // ── plain event line ──
                        Component {
                            id: lineC
                            Rectangle {
                                height: Math.max(26, msg.implicitHeight + 8)
                                color: rh.hovered ? root.rowHover : "transparent"
                                radius: 6
                                Text {
                                    id: tsT
                                    x: Tokens.space4
                                    anchors.top: parent.top; anchors.topMargin: 6
                                    text: rowItem.ts
                                    font.family: Fonts.family("mono", Tokens.weightRegular)
                                    font.pixelSize: 11
                                    color: root.stampColor
                                }
                                Item {
                                    id: icoBox
                                    x: tsT.x + 64
                                    width: 18; height: 26
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        visible: rowItem.icon !== ""
                                        name: rowItem.icon; fill: true; size: 14
                                        glyphColor: rowItem.tone
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: rowItem.icon === ""
                                        width: 4; height: 4; radius: 2
                                        color: rowItem.level === "muted" ? root.stampColor : U.withAlpha(rowItem.tone, 0.7)
                                    }
                                }
                                C.AppText {
                                    id: msg
                                    anchors.left: icoBox.right
                                    anchors.leftMargin: Tokens.space2
                                    anchors.right: parent.right
                                    anchors.rightMargin: Tokens.space4
                                    anchors.top: parent.top; anchors.topMargin: 4
                                    text: rowItem.text
                                    font.pixelSize: 13
                                    wrapMode: Text.Wrap
                                    weight: (rowItem.level === "error" || rowItem.level === "warn") ? Tokens.weightDemiBold : Tokens.weightRegular
                                    color: rowItem.level === "muted" ? root.dimText
                                         : rowItem.level === "error" || rowItem.level === "warn" ? rowItem.tone
                                         : rowItem.level === "ok" ? root.textColor
                                         : root.textColor
                                }
                            }
                        }

                        // ── section break ──
                        Component {
                            id: ruleC
                            Item {
                                height: 17
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Tokens.space4
                                    width: parent.width - Tokens.space4 * 2
                                    height: 1
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: U.withAlpha(Theme.border, 0.0) }
                                        GradientStop { position: 0.15; color: Theme.border }
                                        GradientStop { position: 0.85; color: Theme.border }
                                        GradientStop { position: 1.0; color: U.withAlpha(Theme.border, 0.0) }
                                    }
                                }
                            }
                        }

                        // ── start / done banner ──
                        Component {
                            id: bannerC
                            Item {
                                height: 54
                                readonly property bool isDone: rowItem.kind === "done"
                                readonly property color c: isDone ? root.okColor : Theme.primary
                                Rectangle {
                                    id: bn
                                    x: Tokens.space3
                                    y: 5
                                    width: parent.width - Tokens.space3 * 2
                                    height: 44
                                    radius: 12
                                    border.width: 1
                                    border.color: U.withAlpha(parent.c, 0.30)
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: U.withAlpha(bn.parent.c, Theme.isDark ? 0.18 : 0.10) }
                                        GradientStop { position: 1.0; color: U.withAlpha(bn.parent.c, 0.02) }
                                    }
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Tokens.space3
                                        spacing: Tokens.space3
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 28; height: 28; radius: 9
                                            color: U.withAlpha(bn.parent.c, 0.20)
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: bn.parent.isDone ? "sparkling" : "bolt"
                                                fill: true; size: 15
                                                glyphColor: bn.parent.c
                                            }
                                        }
                                        C.AppText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: rowItem.text
                                            weight: Tokens.weightBold
                                            font.pixelSize: 13
                                            color: Theme.text_strong
                                            elide: Text.ElideRight
                                            width: Math.min(implicitWidth, bn.width - 140)
                                        }
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: Tokens.space3
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rowItem.ts
                                        font.family: Fonts.family("mono", Tokens.weightRegular)
                                        font.pixelSize: 11
                                        color: root.stampColor
                                    }
                                }
                            }
                        }

                        // ── per-video row ──
                        Component {
                            id: videoC
                            Rectangle {
                                height: 30
                                radius: 6
                                color: rh.hovered ? root.rowHover : "transparent"
                                readonly property color sc: root.toneOf(rowItem.statusLevel)
                                Text {
                                    id: vts
                                    x: Tokens.space4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.ts
                                    font.family: Fonts.family("mono", Tokens.weightRegular)
                                    font.pixelSize: 11
                                    color: root.stampColor
                                }
                                Row {
                                    x: vts.x + 64
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.space3
                                    C.IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "play_circle"; fill: true; size: 14
                                        glyphColor: root.dimText
                                    }
                                    // counter
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 46
                                        text: rowItem.a + "/" + rowItem.b
                                        font.family: Fonts.family("mono", Tokens.weightDemiBold)
                                        font.weight: Fonts.weight(Tokens.weightDemiBold)
                                        font.pixelSize: 12
                                        color: root.textColor
                                    }
                                    // mini meter
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 54; height: 4; radius: 2
                                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.07)
                                        Rectangle {
                                            width: parent.width * Math.min(1, rowItem.pct / 100)
                                            height: parent.height; radius: 2
                                            color: Theme.primary
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 34
                                        text: rowItem.pct + "%"
                                        font.family: Fonts.family("mono", Tokens.weightRegular)
                                        font.pixelSize: 11
                                        color: root.dimText
                                    }
                                    // video id chip
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 20; radius: 6
                                        width: vidT.implicitWidth + 12
                                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.045)
                                        border.width: 1
                                        border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)
                                        Text {
                                            id: vidT
                                            anchors.centerIn: parent
                                            text: rowItem.vid
                                            font.family: Fonts.family("mono", Tokens.weightMedium)
                                            font.weight: Fonts.weight(Tokens.weightMedium)
                                            font.pixelSize: 11
                                            color: root.textColor
                                        }
                                    }
                                    // status pill
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: rowItem.status !== ""
                                        height: 20; radius: 10
                                        width: stRow.implicitWidth + 14
                                        color: U.withAlpha(parent.parent.sc, 0.13)
                                        Row {
                                            id: stRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            C.IconGlyph {
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: rowItem.statusLevel === "error" ? "error"
                                                    : rowItem.statusLevel === "warn" ? "warning" : "check_circle"
                                                fill: true; size: 11
                                                glyphColor: stRow.parent.parent.parent.sc
                                            }
                                            C.AppText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: rowItem.status
                                                weight: Tokens.weightDemiBold
                                                font.pixelSize: 11
                                                color: stRow.parent.parent.parent.sc
                                            }
                                        }
                                    }
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Tokens.space4
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: rowItem.delta >= 0
                                    text: "+" + rowItem.delta + "s"
                                    font.family: Fonts.family("mono", Tokens.weightRegular)
                                    font.pixelSize: 11
                                    color: root.stampColor
                                }
                            }
                        }

                        // ── summary chips ──
                        Component {
                            id: statsC
                            Item {
                                height: 40
                                readonly property var items: { try { return JSON.parse(rowItem.chips) } catch (e) { return [] } }
                                Row {
                                    x: Tokens.space4 + 64 + 18 + Tokens.space2
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: parent.parent.items
                                        Rectangle {
                                            readonly property color c: modelData.level === "muted" ? Theme.outline : root.toneOf(modelData.level)
                                            height: 28; radius: 9
                                            width: chRow.implicitWidth + 18
                                            color: U.withAlpha(c, 0.10)
                                            border.width: 1
                                            border.color: U.withAlpha(c, 0.26)
                                            Row {
                                                id: chRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                C.IconGlyph {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: modelData.icon; fill: true; size: 13
                                                    glyphColor: chRow.parent.c
                                                }
                                                C.AppText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.text
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: 12
                                                    color: chRow.parent.c
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // waiting caret (thin, breathing) under the last line while running
                    footer: Item {
                        width: view.width
                        height: root.running ? 26 : 8
                        Row {
                            visible: root.running
                            x: Tokens.space4 + 64
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 5; height: 5; radius: 2.5
                                    color: Theme.primary
                                    opacity: 0.25
                                    SequentialAnimation on opacity {
                                        running: root.running && root.visible && Tokens.appActive
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: index * 160 }
                                        NumberAnimation { to: 1.0; duration: 320 }
                                        NumberAnimation { to: 0.25; duration: 320 }
                                        PauseAnimation { duration: (2 - index) * 160 }
                                    }
                                }
                            }
                        }
                    }
                }

                // bottom fade
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 24
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(root.paneBg, 0.0) }
                        GradientStop { position: 1.0; color: root.paneBg }
                    }
                }

                // jump to latest
                Rectangle {
                    id: jump
                    readonly property bool shown: root.hasLines && !view.atYEnd && view.contentHeight > view.height + 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: shown ? Tokens.space3 : -40
                    Behavior on anchors.bottomMargin { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    opacity: shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    height: 30; radius: 15
                    width: jRow.implicitWidth + 22
                    color: Theme.isDark ? "#1C1C22" : "#FFFFFF"
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.35)
                    Row {
                        id: jRow
                        anchors.centerIn: parent
                        spacing: 6
                        C.IconGlyph { anchors.verticalCenter: parent.verticalCenter; name: "expand_more"; size: 15; glyphColor: Theme.primary }
                        C.AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Jump to latest")
                            weight: Tokens.weightDemiBold
                            font.pixelSize: 12
                            color: Theme.primary
                        }
                    }
                    TapHandler { onTapped: { root._follow = true; view.positionViewAtEnd() } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }
    }
}
