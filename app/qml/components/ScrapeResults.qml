import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "../Utils.js" as U

// Scraper results board (v3.54).
//
//   ┌ Results · Channel name · 412 videos ─────── [Deep scan] [Top 10 → Ideas] ┐
//   │ VIDEOS   TOTAL VIEWS   MEDIAN   ENGAGEMENT   HIT RATE                    │
//   │ ┌ top outlier ─────────────┐  cadence · best day · sweet-spot length …   │
//   │ │ big thumb   8.4× its era │                                             │
//   │ └──────────────────────────┘                                             │
//   │ [Outliers|Momentum|Views|Newest|Engagement]          ( search titles )   │
//   │  1  ▣  Title …                          4.2×    1.2M views   3.1%  ↗ ⧉ ✦ │
//   └──────────────────────────────────────────────────────────────────────────┘
//
// The signature is the OUTLIER score: a video's views against the median of the
// ~14 videos published around it, not against the whole channel. A 2019 hit and
// a 2025 hit are both visible, instead of the channel's best era drowning the
// rest. It streams while the scrape runs (Dashboard.resultsAppended batches).
Item {
    id: root
    implicitHeight: panel.implicitHeight

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    readonly property bool _wide: width >= 980

    // raw compact rows from DashboardVM (_result_row), run order
    property var _all: []
    // computed
    property var _hero: null
    property var _stats: ({ n: 0, total: 0, median: 0, eng: 0, hit: 0, shorts: 0, tx: 0,
                            cadence: "—", bestDay: "—", sweet: "—", newest: "—" })
    property int _matchCount: 0
    // sorted + filtered rows behind viewModel, so "Top 10" is not limited by
    // how many rows the board currently shows
    property var _view: []
    property int sortMode: 0          // 0 outliers · 1 momentum · 2 views · 3 newest · 4 engagement
    property int _showN: 8
    property string _filter: ""
    property string _sentNote: ""

    // ── formatting ──
    function fmtNum(n) {
        n = Number(n) || 0
        if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K"
        return String(Math.round(n))
    }
    function fmtDur(s) {
        s = Math.max(0, Math.round(Number(s) || 0))
        if (s <= 0) return ""
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60
        const xs = (x < 10 ? "0" : "") + x
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + xs
        return m + ":" + xs
    }
    function fmtAge(d) {
        if (d < 0 || isNaN(d)) return ""
        if (d < 1) return I18n.tr("today")
        if (d < 30) return I18n.tr("{n}d ago").replace("{n}", Math.floor(d))
        if (d < 365) return I18n.tr("{n}mo ago").replace("{n}", Math.floor(d / 30.4))
        return I18n.tr("{n}y ago").replace("{n}", (d / 365).toFixed(d < 3650 ? 1 : 0))
    }
    function fmtMult(m) {
        if (!(m > 0)) return "—"
        return (m >= 10 ? m.toFixed(0) : m.toFixed(1)) + "×"
    }
    function median(arr) {
        if (!arr.length) return 0
        const a = arr.slice().sort(function(x, y) { return x - y })
        const k = Math.floor(a.length / 2)
        return a.length % 2 ? a[k] : (a[k - 1] + a[k]) / 2
    }
    function tierColor(m) {
        if (m >= 5) return Theme.primary
        if (m >= 2) return Theme.warn
        if (m >= 1) return Theme.on_surface
        return Theme.outline
    }
    function videoUrl(vid) { return "https://www.youtube.com/watch?v=" + vid }

    // ── data in ──
    function _reset() {
        _all = []
        _view = []
        _showN = 8
        _sentNote = ""
        _rebuild()
    }
    function _append(batch) {
        for (let i = 0; i < batch.length; ++i)
            _all.push(batch[i])
        rebuildTimer.interval = Dashboard.isRunning ? 700 : 60
        if (!rebuildTimer.running) rebuildTimer.start()
    }
    Timer {
        id: rebuildTimer
        interval: 700
        repeat: false
        onTriggered: root._rebuild()
    }
    Connections {
        target: Dashboard
        function onResultsReset() { root._reset() }
        function onResultsAppended(batch) { root._append(batch) }
        function onRunningChanged() { if (!Dashboard.isRunning) root._rebuild() }
    }
    Component.onCompleted: {
        _all = Dashboard.results() || []
        _rebuild()
    }

    // ── the reading ──
    function _rebuild() {
        const now = Date.now()
        const src = _all
        const n = src.length
        let rows = []
        let total = 0, likes = 0, comments = 0, shorts = 0, tx = 0
        for (let i = 0; i < n; ++i) {
            const r = src[i]
            const t = Date.parse(r.pub)
            const age = isNaN(t) ? -1 : Math.max(0, (now - t) / 86400000)
            const v = Number(r.views) || 0
            total += v
            likes += Number(r.likes) || 0
            comments += Number(r.comments) || 0
            if (r.short) shorts++
            if (r.tx) tx++
            rows.push({
                vid: r.vid, title: r.title, views: v,
                likes: Number(r.likes) || 0, comments: Number(r.comments) || 0,
                pub: r.pub, t: isNaN(t) ? 0 : t, ageDays: age,
                secs: Number(r.secs) || 0, short: !!r.short, tx: !!r.tx, thumb: r.thumb || "",
                vpd: v / Math.max(age, 0.5),
                eng: v > 0 ? ((Number(r.likes) || 0) + (Number(r.comments) || 0)) / v : 0,
                mult: 0
            })
        }
        // outlier: views vs the median of the ~14 videos published around it
        const byDate = rows.slice().sort(function(a, b) { return a.t - b.t })
        const allViews = rows.map(function(r) { return r.views })
        const med = median(allViews)
        const W = 7
        for (let i = 0; i < byDate.length; ++i) {
            let ref
            if (byDate.length < 8) {
                ref = med
            } else {
                let lo = Math.max(0, i - W), hi = Math.min(byDate.length, i + W + 1)
                if (hi - lo < 2 * W + 1) {      // keep the window full at the edges
                    if (lo === 0) hi = Math.min(byDate.length, 2 * W + 1)
                    else lo = Math.max(0, hi - (2 * W + 1))
                }
                const win = []
                for (let j = lo; j < hi; ++j) if (j !== i) win.push(byDate[j].views)
                ref = median(win)
            }
            byDate[i].mult = byDate[i].views / Math.max(ref, 1)
        }

        // insights
        let hit = 0
        for (let i = 0; i < rows.length; ++i) if (rows[i].mult >= 2) hit++
        let cadence = "—", newest = "—"
        const dated = byDate.filter(function(r) { return r.t > 0 })
        if (dated.length >= 2) {
            const spanDays = (dated[dated.length - 1].t - dated[0].t) / 86400000
            if (spanDays > 0) {
                const perWeek = (dated.length - 1) / (spanDays / 7)
                cadence = perWeek >= 1
                        ? I18n.tr("{n} / week").replace("{n}", perWeek.toFixed(perWeek >= 10 ? 0 : 1))
                        : I18n.tr("every {n} days").replace("{n}", Math.round(7 / Math.max(perWeek, 0.001)))
            }
        }
        if (dated.length) newest = fmtAge(dated[dated.length - 1].ageDays)
        // best weekday by median outlier score (2+ videos that day)
        const days = [I18n.tr("Sunday"), I18n.tr("Monday"), I18n.tr("Tuesday"), I18n.tr("Wednesday"),
                      I18n.tr("Thursday"), I18n.tr("Friday"), I18n.tr("Saturday")]
        const perDay = [[], [], [], [], [], [], []]
        for (let i = 0; i < dated.length; ++i) perDay[new Date(dated[i].t).getDay()].push(dated[i].mult)
        let bestDay = "—", bestDayV = 0
        for (let d = 0; d < 7; ++d) {
            if (perDay[d].length < 2) continue
            const m = median(perDay[d])
            if (m > bestDayV) { bestDayV = m; bestDay = days[d] }
        }
        // sweet-spot length (median outlier score per bucket, 3+ videos)
        const buckets = [
            { k: I18n.tr("Shorts"), f: function(r) { return r.short } },
            { k: I18n.tr("under 8 min"), f: function(r) { return !r.short && r.secs < 480 } },
            { k: I18n.tr("8–15 min"), f: function(r) { return !r.short && r.secs >= 480 && r.secs < 900 } },
            { k: I18n.tr("15–30 min"), f: function(r) { return !r.short && r.secs >= 900 && r.secs < 1800 } },
            { k: I18n.tr("30+ min"), f: function(r) { return !r.short && r.secs >= 1800 } }
        ]
        let sweet = "—", sweetV = 0
        for (let b = 0; b < buckets.length; ++b) {
            const ms = rows.filter(buckets[b].f).map(function(r) { return r.mult })
            if (ms.length < 3) continue
            const m = median(ms)
            if (m > sweetV) { sweetV = m; sweet = buckets[b].k }
        }
        _stats = {
            n: n, total: total, median: med,
            eng: total > 0 ? (likes + comments) / total : 0,
            hit: n ? hit / n : 0, shorts: n ? shorts / n : 0, tx: tx,
            cadence: cadence, bestDay: bestDay, sweet: sweet, newest: newest
        }

        // hero: the strongest outlier that has had 2+ days to collect views
        let hero = null
        for (let i = 0; i < rows.length; ++i) {
            const r = rows[i]
            if (r.ageDays >= 0 && r.ageDays < 2 && rows.length > 3) continue
            if (!hero || r.mult > hero.mult) hero = r
        }
        if (!hero && rows.length) hero = rows[0]
        _hero = hero

        // view
        const q = _filter.trim().toLowerCase()
        let view = q === "" ? rows : rows.filter(function(r) { return r.title.toLowerCase().indexOf(q) !== -1 })
        const keys = ["mult", "vpd", "views", "t", "eng"]
        const key = keys[Math.max(0, Math.min(4, sortMode))]
        view.sort(function(a, b) { return b[key] - a[key] })
        _view = view
        _matchCount = view.length
        _sync(view)
    }

    function _sync(view) {
        const m = Math.min(view.length, _showN)
        for (let i = 0; i < m; ++i) {
            const r = view[i]
            const o = {
                rank: i + 1, vid: r.vid, title: r.title, views: r.views, vpd: r.vpd,
                eng: r.eng, mult: r.mult, secs: r.secs, isShort: r.short, tx: r.tx,
                thumb: r.thumb, age: fmtAge(r.ageDays)
            }
            if (i < viewModel.count) viewModel.set(i, o)
            else viewModel.append(o)
        }
        if (viewModel.count > m) viewModel.remove(m, viewModel.count - m)
    }

    onSortModeChanged: { _showN = 8; _rebuild() }
    on_FilterChanged: filterTimer.restart()
    Timer {
        id: filterTimer
        interval: 160
        onTriggered: { root._showN = 8; root._rebuild() }
    }

    function _topPicks(k) {
        const out = []
        for (let i = 0; i < _view.length && out.length < k; ++i) {
            const it = _view[i]
            out.push({ vid: it.vid, mult: it.mult })
        }
        return out
    }
    function _sendTop() {
        const picks = _topPicks(10)
        if (!picks.length) return
        Dashboard.sendToIdeas(picks)
        _sentNote = I18n.tr("Sent {n} to AI Ideas").replace("{n}", picks.length)
        sentTimer.restart()
    }
    Timer { id: sentTimer; interval: 2600; onTriggered: root._sentNote = "" }

    ListModel { id: viewModel }

    // ═════════════ building blocks ═════════════
    component StatTile: Rectangle {
        id: st
        property string label: ""
        property string value: ""
        property string sub: ""
        property color accent: Theme.text_strong
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 86
        radius: Tokens.radiusLg
        color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.55 : 0.85)
        border.width: 1
        border.color: Theme.border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.space4
            spacing: 2
            AppText {
                text: st.label
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontMicro
                font.letterSpacing: Tokens.trackingLabel
                font.capitalization: Font.AllUppercase
                color: Theme.on_surface_var
            }
            AppText {
                text: st.value
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: 26
                color: st.accent
                elide: Text.ElideRight
                Layout.fillWidth: true
                LayoutMirroring.enabled: false
            }
            AppText {
                visible: st.sub !== ""
                text: st.sub
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    component InsightLine: RowLayout {
        id: il
        property string icon: ""
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Tokens.space3
        Rectangle {
            width: 34; height: 34; radius: 10
            color: U.withAlpha(Theme.primary, 0.10)
            border.width: 1
            border.color: U.withAlpha(Theme.primary, 0.22)
            IconGlyph { anchors.centerIn: parent; name: il.icon; size: 16; glyphColor: Theme.primary }
        }
        AppText {
            text: il.label
            font.pixelSize: Tokens.fontBody
            color: Theme.on_surface_var
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        AppText {
            text: il.value
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontBody
            color: Theme.text_strong
            horizontalAlignment: Text.AlignRight
        }
    }

    component MultChip: Rectangle {
        id: mc
        property real mult: 0
        property bool big: false
        // inline components can't see this file's ids, so the tier and the
        // label are worked out here (same rule as root.tierColor / fmtMult)
        readonly property color tint: mult >= 5 ? Theme.primary : mult >= 2 ? Theme.warn
                                     : mult >= 1 ? Theme.on_surface : Theme.outline
        implicitWidth: mcText.implicitWidth + (big ? 22 : 16)
        implicitHeight: big ? 34 : 26
        radius: Tokens.radiusPill
        color: mult >= 5 ? Theme.primary : U.withAlpha(tint, mult >= 2 ? 0.14 : 0.07)
        border.width: 1
        border.color: mult >= 5 ? Theme.primary : U.withAlpha(tint, mult >= 2 ? 0.45 : 0.20)
        AppText {
            id: mcText
            anchors.centerIn: parent
            text: mc.mult > 0 ? ((mc.mult >= 10 ? mc.mult.toFixed(0) : mc.mult.toFixed(1)) + "×") : "—"
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: mc.big ? 16 : Tokens.fontCaption + 1
            color: mc.mult >= 5 ? Theme.on_primary : mc.tint
            LayoutMirroring.enabled: false
        }
    }

    // ═════════════ the panel ═════════════
    GlassPanel {
        id: panel
        width: parent.width
        radius: Tokens.radiusXl
        implicitHeight: col.implicitHeight + Tokens.space6 * 2

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space6
            spacing: Tokens.space5

            // ── header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: 12
                    color: U.withAlpha(Theme.primary, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.30)
                    IconGlyph { anchors.centerIn: parent; name: "insights"; size: 20; glyphColor: Theme.primary }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: Tokens.space2
                        AppText {
                            text: I18n.tr("Results")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontTitle
                            color: Theme.text_strong
                        }
                        // live pill while streaming
                        Rectangle {
                            visible: Dashboard.isRunning
                            radius: Tokens.radiusPill
                            implicitHeight: 24
                            implicitWidth: liveRow.implicitWidth + Tokens.space3 * 2
                            color: U.withAlpha(Theme.primary, 0.12)
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, 0.40)
                            Row {
                                id: liveRow
                                anchors.centerIn: parent
                                spacing: 6
                                Rectangle {
                                    id: liveDot
                                    width: 6; height: 6; radius: 3
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                    SequentialAnimation on opacity {
                                        running: Dashboard.isRunning && root.visible && root._motion
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.25; to: 1; duration: 650; easing.type: Easing.InOutSine }
                                    }
                                }
                                AppText {
                                    text: I18n.tr("Live")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontMicro
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                    AppText {
                        text: {
                            const parts = []
                            if (Dashboard.runChannel !== "") parts.push(Dashboard.runChannel)
                            parts.push(I18n.tr("{n} videos").replace("{n}", Number(root._stats.n).toLocaleString(Qt.locale("en_US"), "f", 0)))
                            if (Dashboard.runChannelVideos > 0)
                                parts.push(I18n.tr("of {n} on the channel").replace("{n}", Number(Dashboard.runChannelVideos).toLocaleString(Qt.locale("en_US"), "f", 0)))
                            return parts.join("  ·  ")
                        }
                        font.pixelSize: Tokens.fontCaption + 1
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                AppText {
                    visible: root._sentNote !== ""
                    text: "✓ " + root._sentNote
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.primary
                }
                PrimaryButton {
                    variant: "ghost"
                    iconName: "query_stats"
                    text: I18n.tr("Deep scan")
                    enabled: root._stats.n > 0 && !Dashboard.isRunning
                    onClicked: Dashboard.analyzeResults()
                }
                PrimaryButton {
                    variant: "ghost"
                    iconName: "auto_awesome"
                    text: I18n.tr("Top 10 → AI Ideas")
                    enabled: viewModel.count > 0
                    onClicked: root._sendTop()
                }
                PrimaryButton {
                    visible: Dashboard.lastExport !== "" && !Dashboard.isRunning
                    iconName: "open_in_new"
                    text: I18n.tr("Open sheet")
                    onClicked: Dashboard.openFile(Dashboard.lastExport)
                }
            }

            // ── numbers ──
            GridLayout {
                Layout.fillWidth: true
                columns: root._wide ? 5 : 3
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                StatTile {
                    label: I18n.tr("Videos")
                    value: Number(root._stats.n).toLocaleString(Qt.locale("en_US"), "f", 0)
                    sub: I18n.tr("Shorts {p}%").replace("{p}", Math.round(root._stats.shorts * 100))
                }
                StatTile {
                    label: I18n.tr("Total views")
                    value: root.fmtNum(root._stats.total)
                    sub: I18n.tr("newest {a}").replace("{a}", root._stats.newest)
                }
                StatTile {
                    label: I18n.tr("Median views")
                    value: root.fmtNum(root._stats.median)
                    sub: I18n.tr("the typical video")
                }
                StatTile {
                    label: I18n.tr("Engagement")
                    value: (root._stats.eng * 100).toFixed(2) + "%"
                    sub: I18n.tr("likes + comments / views")
                }
                StatTile {
                    label: I18n.tr("Hit rate")
                    value: Math.round(root._stats.hit * 100) + "%"
                    sub: I18n.tr("videos at 2× or more")
                    accent: root._stats.hit >= 0.15 ? Theme.primary : Theme.text_strong
                }
            }

            // ── top outlier + insights ──
            GridLayout {
                Layout.fillWidth: true
                visible: root._hero !== null
                columns: root._wide ? 2 : 1
                columnSpacing: Tokens.space5
                rowSpacing: Tokens.space4

                // hero card
                Rectangle {
                    id: heroCard
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    implicitHeight: heroRow.implicitHeight + Tokens.space4 * 2
                    radius: Tokens.radiusXl
                    color: U.mix(Theme.surface_low, Theme.primary, Theme.isDark ? 0.08 : 0.04)
                    border.width: 1
                    border.color: heroHover.hovered ? U.withAlpha(Theme.primary, 0.60) : U.withAlpha(Theme.primary, 0.28)
                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    clip: true
                    HoverHandler { id: heroHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: if (root._hero) Qt.openUrlExternally(root.videoUrl(root._hero.vid)) }

                    GlowBlob {
                        x: -60; y: -80
                        size: 360
                        glow: Theme.primary
                        strength: 0.22
                    }
                    RowLayout {
                        id: heroRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space4
                        spacing: Tokens.space4
                        RoundThumb {
                            Layout.preferredWidth: root._wide ? 288 : 224
                            Layout.preferredHeight: Math.round((root._wide ? 288 : 224) * 9 / 16)
                            radius: Tokens.radiusLg
                            source: root._hero && root._hero.thumb !== "" ? "image://thumbs/" + root._hero.thumb : ""
                            badge: root._hero ? root.fmtDur(root._hero.secs) : ""
                            glyph: "smart_display"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.space2
                            AppText {
                                text: I18n.tr("Top outlier")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontMicro
                                font.letterSpacing: Tokens.trackingLabel
                                font.capitalization: Font.AllUppercase
                                color: Theme.primary
                            }
                            AppText {
                                text: root._hero ? root._hero.title : ""
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Tokens.fontSubtitle + 1
                                color: Theme.text_strong
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            RowLayout {
                                spacing: Tokens.space3
                                MultChip { mult: root._hero ? root._hero.mult : 0; big: true }
                                AppText {
                                    text: I18n.tr("the videos around it")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                            }
                            AppText {
                                text: root._hero
                                      ? root.fmtNum(root._hero.views) + " " + I18n.tr("views") + "  ·  "
                                        + root.fmtNum(root._hero.vpd) + I18n.tr("/day") + "  ·  " + root.fmtAge(root._hero.ageDays)
                                      : ""
                                mono: true
                                font.pixelSize: Tokens.fontCaption + 1
                                color: Theme.on_surface_var
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // insights
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.space3
                    InsightLine { icon: "schedule"; label: I18n.tr("Upload rhythm"); value: root._stats.cadence }
                    InsightLine { icon: "trending_up"; label: I18n.tr("Strongest day"); value: root._stats.bestDay }
                    InsightLine { icon: "movie"; label: I18n.tr("Sweet-spot length"); value: root._stats.sweet }
                    InsightLine {
                        icon: "subject"
                        label: I18n.tr("Transcripts")
                        value: root._stats.tx + " / " + root._stats.n
                    }
                }
            }

            // ── toolbar ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                SlideSegment {
                    id: sortSeg
                    Layout.preferredWidth: root._wide ? 600 : 460
                    equal: true
                    cellHeight: 36
                    iconOnly: !root._wide
                    model: [
                        { label: I18n.tr("Outliers"), icon: "trending_up" },
                        { label: I18n.tr("Momentum"), icon: "speed" },
                        { label: I18n.tr("Views"), icon: "visibility" },
                        { label: I18n.tr("Newest"), icon: "schedule" },
                        { label: I18n.tr("Engagement"), icon: "favorite" }
                    ]
                    currentIndex: root.sortMode
                    onActivated: (i) => root.sortMode = i
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: 260
                    implicitHeight: 40
                    radius: Tokens.radiusMd
                    color: Theme.input_bg
                    border.width: 1
                    border.color: searchField.activeFocus ? U.withAlpha(Theme.primary, 0.60) : Theme.border
                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.space3
                        anchors.rightMargin: Tokens.space2
                        spacing: Tokens.space2
                        IconGlyph { name: "search"; size: 16; glyphColor: searchField.activeFocus ? Theme.primary : Theme.outline }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            placeholderText: I18n.tr("Search titles…")
                            placeholderTextColor: Theme.outline
                            color: Theme.text_strong
                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                            font.family: Fonts.body
                            font.pixelSize: Tokens.fontBody
                            verticalAlignment: TextInput.AlignVCenter
                            leftPadding: 0; rightPadding: 0
                            background: null
                            selectByMouse: true
                            onTextChanged: root._filter = text
                        }
                        IconButton {
                            visible: searchField.text !== ""
                            implicitWidth: 28; implicitHeight: 28
                            iconName: "close"
                            glyphSize: 14
                            tip: I18n.tr("Clear")
                            onClicked: searchField.text = ""
                        }
                    }
                }
            }

            // ── the list ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2

                Repeater {
                    model: viewModel
                    delegate: Rectangle {
                        id: rowCard
                        Layout.fillWidth: true
                        implicitHeight: 88
                        radius: Tokens.radiusLg
                        color: rowHover.hovered ? U.mix(Theme.surface_low, Theme.primary, 0.05)
                                                : U.withAlpha(Theme.surface_low, Theme.isDark ? 0.45 : 0.75)
                        border.width: 1
                        border.color: rowHover.hovered ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        opacity: 0
                        Component.onCompleted: {
                            if (root._motion) fadeIn.start()
                            else opacity = 1
                        }
                        NumberAnimation { id: fadeIn; target: rowCard; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }

                        HoverHandler { id: rowHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(root.videoUrl(model.vid))
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space3
                            anchors.rightMargin: Tokens.space3
                            spacing: Tokens.space3

                            AppText {
                                Layout.preferredWidth: 30
                                text: model.rank
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption + 1
                                color: model.rank <= 3 ? Theme.primary : Theme.outline
                                horizontalAlignment: Text.AlignHCenter
                            }
                            RoundThumb {
                                Layout.preferredWidth: 122
                                Layout.preferredHeight: 68
                                radius: Tokens.radiusSm + 2
                                source: model.thumb !== "" ? "image://thumbs/" + model.thumb : ""
                                badge: root.fmtDur(model.secs)
                                glyph: "smart_display"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                AppText {
                                    text: model.title
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontBody + 1
                                    color: Theme.text_strong
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                RowLayout {
                                    spacing: Tokens.space2
                                    AppText {
                                        text: model.age
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                    }
                                    Rectangle {
                                        visible: model.isShort
                                        radius: 5
                                        implicitWidth: shortLbl.implicitWidth + 10
                                        implicitHeight: 18
                                        color: U.withAlpha(Theme.tertiary, 0.14)
                                        AppText {
                                            id: shortLbl
                                            anchors.centerIn: parent
                                            text: I18n.tr("Short")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontMicro
                                            color: Theme.tertiary
                                        }
                                    }
                                    IconGlyph {
                                        visible: model.tx
                                        name: "subject"
                                        size: 13
                                        glyphColor: Theme.outline
                                    }
                                }
                            }
                            MultChip { mult: model.mult }
                            ColumnLayout {
                                Layout.preferredWidth: 92
                                spacing: 0
                                AppText {
                                    Layout.alignment: Qt.AlignRight
                                    text: root.fmtNum(model.views)
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontSubtitle
                                    color: Theme.text_strong
                                    LayoutMirroring.enabled: false
                                }
                                AppText {
                                    Layout.alignment: Qt.AlignRight
                                    text: root.fmtNum(model.vpd) + I18n.tr("/day")
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    LayoutMirroring.enabled: false
                                }
                            }
                            AppText {
                                visible: root._wide
                                Layout.preferredWidth: 58
                                text: (model.eng * 100).toFixed(1) + "%"
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption + 1
                                color: Theme.on_surface_var
                                horizontalAlignment: Text.AlignRight
                                LayoutMirroring.enabled: false
                            }
                            Row {
                                spacing: 2
                                opacity: rowHover.hovered ? 1 : 0.0
                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                IconButton {
                                    implicitWidth: 32; implicitHeight: 32
                                    iconName: "content_copy"
                                    glyphSize: 15
                                    tip: I18n.tr("Copy link")
                                    onClicked: Dashboard.copyText(root.videoUrl(model.vid))
                                }
                                IconButton {
                                    implicitWidth: 32; implicitHeight: 32
                                    iconName: "auto_awesome"
                                    glyphSize: 15
                                    tip: I18n.tr("Send to AI Ideas")
                                    onClicked: Dashboard.sendToIdeas([{ vid: model.vid, mult: model.mult }])
                                }
                            }
                        }
                    }
                }

                // empty search
                AppText {
                    visible: root._stats.n > 0 && root._matchCount === 0
                    text: I18n.tr("No titles match “{q}”.").replace("{q}", root._filter)
                    color: Theme.outline
                    font.pixelSize: Tokens.fontBody
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.space4
                    Layout.bottomMargin: Tokens.space4
                }

                PrimaryButton {
                    visible: root._matchCount > viewModel.count
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.space2
                    variant: "ghost"
                    iconName: "expand_more"
                    text: I18n.tr("Show {n} more  ·  {left} left")
                          .replace("{n}", Math.min(8, root._matchCount - viewModel.count))
                          .replace("{left}", root._matchCount - viewModel.count)
                    onClicked: { root._showN += 8; root._rebuild() }
                }
            }
        }
    }
}
