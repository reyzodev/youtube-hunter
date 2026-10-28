import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Effects
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Downloads — v14 "Dailies" redesign.
//
//  * THE SLATE comes first. The page exists to turn a link into a file, so the
//    link field is the biggest thing on it: one tall bar, a 20px field, smart
//    paste and Fetch inside it, and a border that lights up the moment the text
//    is a YouTube link. The "Download from a link" title row and the format
//    chips are gone — the placeholder and one hint line say the same thing.
//  * ONE RULER instead of four metric tiles: Library · Live · Saved · Needs you
//    as plain numbers, with a single proportional bar under them. Four boxed
//    tiles claimed four equally important facts; they aren't.
//  * NOW TRANSFERRING. Running downloads get their own strip above the library
//    with a tall progress track, live size, speed and time left — the thing you
//    are watching is no longer mixed into history.
//  * DAILIES. The library is grouped by day (Today / Yesterday / Earlier this
//    week / Older) into one joined panel per day, like an editor's bin. Finished
//    rows show when they landed; failed rows offer Retry and stopped rows
//    Resume right on the row; the rest of the actions appear on hover.
//  * A fourth filter, "Needs you" (failed + stopped).
//
// Driven by DownloadsVM (context prop `Downloads`); the only VM additions are
// two read-only row fields (dayKey, whenText). Filtering / search / view stay
// pure QML over Downloads.entries.
Item {
    id: page

    onVisibleChanged: if (visible) Downloads.refresh()

    // toolbar state — "all" | "active" | "done" | "attn", plus the search text
    property string statusFilter: "all"
    property string query: ""
    // "list" | "grid"
    property string viewMode: "list"

    property var selectedIds: []
    property int pageIndex: 0
    readonly property int pageSize: 12
    readonly property int pageCount: Math.max(1, Math.ceil(visibleRows.length / pageSize))
    readonly property var pagedRows: visibleRows.slice(pageIndex * pageSize,
                                                        (pageIndex + 1) * pageSize)

    onStatusFilterChanged: pageIndex = 0
    onQueryChanged: pageIndex = 0
    onViewModeChanged: pageIndex = 0
    onPageCountChanged: if (pageIndex > pageCount - 1) pageIndex = pageCount - 1

    function toggleSelected(videoId) {
        var i = selectedIds.indexOf(videoId)
        if (i === -1) selectedIds = selectedIds.concat([videoId])
        else selectedIds = selectedIds.filter(function (x) { return x !== videoId })
    }
    function selectAllVisible() {
        selectedIds = visibleRows.map(function (r) { return r.videoId })
    }
    function clearSelection() { selectedIds = [] }
    // v3.39.9 drag-out: dragging a row that is part of a multi-selection
    // carries every selected finished file; otherwise just that one.
    function _dragPaths(videoId) {
        var ids = (selectedIds.length > 1 && selectedIds.indexOf(videoId) !== -1)
                  ? selectedIds : [videoId]
        return Downloads.existingPaths(ids)
    }
    readonly property bool allSelected: visibleRows.length > 0
                                        && selectedIds.length >= visibleRows.length

    Connections {
        target: Downloads
        function onToast(msg, kind) { toast.show(msg, kind) }
        function onReadyToPick(videoId, title, thumbId) {
            urlField.text = ""
            qualityPicker.openFor(videoId, title, thumbId)
        }
    }

    // ── status helpers ────────────────────────────────────────────────────
    function _kind(status) {
        if (status === "downloading") return "active"
        if (status === "merging") return "merging"
        if (status === "complete") return "done"
        if (status === "failed") return "failed"
        if (status === "stopped") return "stopped"
        return "queued"
    }
    function _kindColor(k) {
        return k === "active" || k === "merging" ? Theme.primary
             : k === "done" ? Theme.secondary_container
             : k === "failed" ? Theme.error
             : k === "stopped" ? Theme.warn
             : Theme.on_surface_var
    }
    function _kindLabel(k) {
        return k === "active" ? I18n.tr("Downloading")
             : k === "merging" ? I18n.tr("Merging")
             : k === "done" ? I18n.tr("Completed")
             : k === "failed" ? I18n.tr("Failed")
             : k === "stopped" ? I18n.tr("Stopped")
             : I18n.tr("Queued")
    }
    function _live(videoId) {
        return (Downloads.live[videoId || ""]) || null
    }
    function _sizeText(row, live) {
        if (!live) return row.totalText || ""
        var d = live.doneText || ""
        var t = live.totalText || ""
        if (d !== "" && t !== "")
            return I18n.tr("{done} of {total}").replace("{done}", d).replace("{total}", t)
        return d !== "" ? d : t
    }
    function _statusLine(row, live, pct) {
        var k = page._kind(row.status)
        if (k === "merging") {
            // At 99% the engine is muxing or converting. Its live phase text
            // ("Converting to MP3…") names the long silent step; showing only
            // a generic "Merging…" made a 10–30 s audio conversion look like a
            // stuck download.
            var phase = live ? (live.text || "") : ""
            return phase !== "" ? phase : I18n.tr("Merging…")
        }
        if (k === "active") {
            var moving = pct > 0 || (live && (live.doneText || "") !== "")
            if (!moving) {
                var phase = live ? (live.text || "") : ""
                return phase !== "" ? phase : I18n.tr("Preparing…")
            }
            return I18n.tr("Downloading {pct}%").replace("{pct}", pct)
        }
        if (k === "stopped") return I18n.tr("Stopped at {pct}%").replace("{pct}", pct)
        if (k === "failed") return row.error || I18n.tr("Failed — link unavailable")
        if (k === "done") return I18n.tr("Downloaded")
        return I18n.tr("Queued")
    }
    function _looksLikeYouTube(t) {
        return /(youtube\.com\/(watch|shorts|live|embed)|youtu\.be\/|music\.youtube\.com\/watch)/i.test(t || "")
    }
    function _dayLabel(k) {
        return k === "today" ? I18n.tr("Today")
             : k === "yesterday" ? I18n.tr("Yesterday")
             : k === "week" ? I18n.tr("Earlier this week")
             : I18n.tr("Older")
    }
    function _resume(videoId) {
        // Resuming / retrying is a fresh yt-dlp run, so it needs the JS runtime.
        if (!Geo.allowDownload()) return
        if (!Deno.ready) { Deno.requestInstall(); return }
        Downloads.resumeDownload(videoId)
    }

    readonly property var counts: {
        var c = { all: 0, active: 0, done: 0, failed: 0, stopped: 0, attn: 0 }
        var rows = Downloads.entries || []
        for (var i = 0; i < rows.length; i++) {
            var s = rows[i].status
            c.all++
            if (s === "downloading" || s === "merging") c.active++
            else if (s === "complete") c.done++
            else if (s === "failed") c.failed++
            else if (s === "stopped") c.stopped++
        }
        c.attn = c.failed + c.stopped
        return c
    }
    readonly property int overallPct: {
        var _ = Downloads.progressTick
        var rows = Downloads.entries || []
        var n = 0, sum = 0
        for (var i = 0; i < rows.length; i++) {
            var s = rows[i].status
            if (s !== "downloading" && s !== "merging") continue
            var l = Downloads.live[rows[i].videoId || ""]
            sum += l ? (l.pct || 0) : (rows[i].pct || 0)
            n++
        }
        return n > 0 ? Math.round(sum / n) : 0
    }

    // Running downloads, shown in their own strip on the "All" view.
    readonly property var liveRows: (Downloads.entries || []).filter(function (r) {
        return r.status === "downloading" || r.status === "merging"
    })
    readonly property bool showLive: statusFilter === "all" && query.trim() === ""
                                     && liveRows.length > 0

    // The library rows after the filter + search, newest-first.
    readonly property var visibleRows: {
        var q = page.query.trim().toLowerCase()
        var hideLive = page.showLive
        return (Downloads.entries || []).filter(function (r) {
            var running = r.status === "downloading" || r.status === "merging"
            var matchesFilter = page.statusFilter === "all" ? !(hideLive && running)
                : page.statusFilter === "done" ? r.status === "complete"
                : page.statusFilter === "attn" ? (r.status === "failed" || r.status === "stopped")
                : running
            var matchesQuery = !q
                || (r.title || "").toLowerCase().indexOf(q) >= 0
                || (r.channelTitle || "").toLowerCase().indexOf(q) >= 0
            return matchesFilter && matchesQuery
        })
    }
    // This page's rows, cut into day groups (rows arrive newest-first, so each
    // day is one contiguous run).
    readonly property var pagedGroups: {
        var out = [], cur = null
        var rows = page.pagedRows
        for (var i = 0; i < rows.length; i++) {
            var k = rows[i].dayKey || "earlier"
            if (!cur || cur.key !== k) { cur = { key: k, rows: [] }; out.push(cur) }
            cur.rows.push(rows[i])
        }
        return out
    }

    function _playRow(videoId) {
        var info = Downloads.playInfo(videoId)
        if (info && info.fileUrl) videoPlayer.play(info)
    }
    function _smartPaste() {
        urlField.forceActiveFocus()
        urlField.selectAll()
        urlField.paste()
        if (page._looksLikeYouTube(urlField.text) && !Downloads.busy)
            Downloads.fetchFromUrl(urlField.text)
    }

    C.SmoothScrollView {
        id: scroller
        anchors.fill: parent

        Item {
            id: dlScroll
            width: parent.width
            implicitHeight: content.implicitHeight + Tokens.space7 * 2
                            + (page.selectedIds.length > 0 ? 80 : 0)

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 420
            }

            ColumnLayout {
                id: content
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space6
                spacing: Tokens.space5

                // ── header ──
                C.PageHeader {
                    iconName: "download"
                    title: I18n.tr("Downloads")
                    subtitle: I18n.tr("Paste a link. It lands on your Desktop, live.")

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusPill
                        implicitHeight: 34
                        implicitWidth: engRow.implicitWidth + Tokens.space4 * 2
                        color: page.counts.active > 0 ? U.withAlpha(Theme.primary, 0.12) : Theme.surface
                        border.width: 1
                        border.color: page.counts.active > 0 ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        Row {
                            id: engRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            LiveDot {
                                anchors.verticalCenter: parent.verticalCenter
                                dotColor: page.counts.active > 0 ? Theme.primary : Theme.secondary_container
                                pulse: true
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.counts.active > 0
                                      ? I18n.tr("{n} downloading").replace("{n}", page.counts.active)
                                      : I18n.tr("Engine ready")
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontCaption
                                color: page.counts.active > 0 ? Theme.primary : Theme.on_surface_var
                            }
                        }
                    }
                }

                // ═══ the slate ═══
                Item {
                    id: slateBox
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space1
                    implicitHeight: slate.implicitHeight
                    readonly property bool detected: page._looksLikeYouTube(urlField.text)

                    // halo: soft while focused, accent once a link is recognised
                    Rectangle {
                        anchors.fill: slate
                        anchors.margins: -5
                        radius: slate.radius + 5
                        color: "transparent"
                        border.width: 5
                        border.color: U.withAlpha(Theme.primary, slateBox.detected ? 0.16 : 0.08)
                        opacity: urlField.activeFocus || slateBox.detected ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    }

                    Rectangle {
                        id: slate
                        width: parent.width
                        implicitHeight: slateCol.implicitHeight + Tokens.space2 * 2
                        radius: Tokens.radiusXl + 4
                        color: Theme.panel_bg
                        border.width: 1
                        border.color: slateBox.detected ? U.withAlpha(Theme.primary, 0.70)
                                    : urlField.activeFocus ? Theme.border_strong
                                    : slateHover.hovered ? Theme.border_med
                                    : Theme.border
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        clip: true
                        HoverHandler { id: slateHover }

                        ColumnLayout {
                            id: slateCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space2
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                spacing: Tokens.space2

                                Item {
                                    Layout.preferredWidth: 52
                                    Layout.fillHeight: true
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: slateBox.detected ? "youtube" : "link"
                                        fill: slateBox.detected
                                        size: 22
                                        glyphColor: slateBox.detected ? Theme.primary
                                                    : urlField.activeFocus ? Theme.on_surface : Theme.on_surface_var
                                    }
                                }
                                TextField {
                                    id: urlField
                                    // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                    T.ContextMenu.menu: C.EditMenu { editor: urlField }
                                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                    selectedTextColor: Theme.text_strong
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    enabled: !Downloads.busy
                                    placeholderText: I18n.tr("Paste a YouTube link")
                                    placeholderTextColor: Theme.outline
                                    color: Theme.text_strong
                                    font.family: Fonts.familyFor("body", Tokens.weightMedium, text)
                                    font.weight: Fonts.weightFor(Tokens.weightMedium, text)
                                    font.pixelSize: 20
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    background: null
                                    leftPadding: 0
                                    onAccepted: if (text.trim() !== "") Downloads.fetchFromUrl(text)
                                }
                                C.IconButton {
                                    visible: urlField.text !== "" && !Downloads.busy
                                    implicitWidth: 40; implicitHeight: 40
                                    Layout.alignment: Qt.AlignVCenter
                                    iconName: "close"
                                    glyphSize: 17
                                    tip: I18n.tr("Clear")
                                    onClicked: { urlField.text = ""; urlField.forceActiveFocus() }
                                }
                                C.PrimaryButton {
                                    variant: "ghost"
                                    iconName: "content_paste"
                                    text: I18n.tr("Paste")
                                    visible: urlField.text === ""
                                    enabled: !Downloads.busy
                                    implicitHeight: 50
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: page._smartPaste()
                                }
                                C.PrimaryButton {
                                    iconName: "arrow_right_up"
                                    text: Downloads.busy ? I18n.tr("Fetching…") : I18n.tr("Fetch qualities")
                                    enabled: !Downloads.busy && urlField.text.trim() !== ""
                                    indeterminate: Downloads.busy
                                    implicitHeight: 50
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: Downloads.fetchFromUrl(urlField.text)
                                }
                            }

                            // one hint line: what works, or what was recognised
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                Layout.leftMargin: Tokens.space4
                                Layout.rightMargin: Tokens.space4
                                spacing: Tokens.space2

                                C.IconGlyph {
                                    name: slateBox.detected ? "check_circle" : "corner_down_left"
                                    fill: slateBox.detected
                                    size: 14
                                    glyphColor: slateBox.detected ? Theme.secondary_container : Theme.outline
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                C.AppText {
                                    text: slateBox.detected ? I18n.tr("YouTube link detected")
                                                            : I18n.tr("Enter to fetch")
                                    weight: slateBox.detected ? Tokens.weightDemiBold : Tokens.weightRegular
                                    font.pixelSize: Tokens.fontCaption
                                    color: slateBox.detected ? Theme.on_surface : Theme.outline
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                C.AppText {
                                    visible: !slateBox.detected
                                    text: "·   youtube.com/watch   ·   youtu.be   ·   /shorts/"
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Item { Layout.fillWidth: true; visible: slateBox.detected }
                                C.AppText {
                                    text: I18n.tr("Real qualities and sizes are checked before you pick.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    visible: content.width > 900
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }

                        // busy sweep along the bottom edge — runs in a lane
                        // that stops short of the rounded corners and clips
                        // there, so the light never slides out of the slate
                        Item {
                            id: sweepLane
                            visible: Downloads.busy
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: slate.radius
                            anchors.rightMargin: slate.radius
                            anchors.bottomMargin: 1
                            height: 2
                            clip: true
                            Rectangle {
                                id: busySweep
                                visible: Downloads.busy
                                anchors.bottom: parent.bottom
                                radius: 1
                                width: parent.width * 0.28
                                height: 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                                    GradientStop { position: 0.5; color: Theme.primary }
                                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                                }
                                SequentialAnimation on x {
                                    running: busySweep.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: -busySweep.width; to: sweepLane.width
                                                      duration: 1200; easing.type: Easing.InOutQuad }
                                }
                            }
                        }
                    }
                }

                // VM hint (errors, "looking up…")
                Rectangle {
                    visible: Downloads.hint !== ""
                    Layout.fillWidth: true
                    Layout.topMargin: -Tokens.space2
                    radius: Tokens.radiusMd
                    implicitHeight: hintRow.implicitHeight + Tokens.space2 * 2
                    color: Downloads.hintIsError ? U.withAlpha(Theme.error, 0.08)
                                                 : U.withAlpha(Theme.primary, 0.06)
                    border.width: 1
                    border.color: Downloads.hintIsError ? U.withAlpha(Theme.error, 0.30)
                                                        : U.withAlpha(Theme.primary, 0.20)
                    RowLayout {
                        id: hintRow
                        anchors.fill: parent
                        anchors.margins: Tokens.space2
                        anchors.leftMargin: Tokens.space3
                        spacing: Tokens.space2
                        C.IconGlyph {
                            name: Downloads.hintIsError ? "error" : "info"
                            size: 15; fill: true
                            glyphColor: Downloads.hintIsError ? Theme.error : Theme.primary
                            Layout.alignment: Qt.AlignTop
                        }
                        C.AppText {
                            text: Downloads.hint
                            font.pixelSize: Tokens.fontCaption
                            color: Downloads.hintIsError ? Theme.error : Theme.on_surface
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // ═══ the ruler: four numbers, one bar ═══
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space2
                    spacing: Tokens.space3
                    visible: page.counts.all > 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space6
                        Repeater {
                            model: [
                                { n: page.counts.all,    label: I18n.tr("Library"),   c: Theme.text_strong },
                                { n: page.counts.active, label: I18n.tr("Live"),      c: Theme.primary },
                                { n: page.counts.done,   label: I18n.tr("Completed"), c: Theme.secondary_container },
                                { n: page.counts.attn,   label: I18n.tr("Needs you"), c: page.counts.attn > 0 ? Theme.error : Theme.on_surface_var }
                            ]
                            ColumnLayout {
                                spacing: 2
                                C.AppText {
                                    text: modelData.n
                                    mono: true
                                    weight: Tokens.weightBold
                                    font.pixelSize: 30
                                    color: modelData.c
                                }
                                C.AppText {
                                    text: modelData.label
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        C.AppText {
                            Layout.alignment: Qt.AlignBottom
                            text: page.counts.active > 0
                                  ? I18n.tr("{p}% overall").replace("{p}", page.overallPct)
                                  : I18n.tr("{p}% success rate").replace("{p}",
                                        Math.round(page.counts.done * 100 / Math.max(1, page.counts.done + page.counts.attn)))
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                        }
                    }
                    // proportional bar: live · saved · needs you
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        spacing: 4
                        Repeater {
                            model: [
                                { n: page.counts.active, c: Theme.primary },
                                { n: page.counts.done,   c: Theme.secondary_container },
                                { n: page.counts.attn,   c: Theme.error }
                            ]
                            Rectangle {
                                visible: modelData.n > 0
                                Layout.fillWidth: true
                                Layout.preferredWidth: modelData.n * 1000
                                Layout.fillHeight: true
                                radius: 3
                                color: modelData.c
                                opacity: index === 1 ? 0.85 : 1
                            }
                        }
                    }
                }

                // ═══ now transferring ═══
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space3
                    spacing: Tokens.space3
                    visible: page.showLive

                    RowLayout {
                        spacing: Tokens.space2
                        LiveDot { dotColor: Theme.primary; pulse: true; Layout.alignment: Qt.AlignVCenter }
                        C.AppText {
                            text: I18n.tr("Now transferring")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: page.liveRows.length
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.outline
                        }
                    }
                    Repeater {
                        model: page.showLive ? page.liveRows : []
                        delegate: LiveRow { row: modelData }
                    }
                }

                // ── toolbar ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space4
                    spacing: Tokens.space3
                    LayoutMirroring.enabled: false

                    // sliding segmented filter with counts
                    Rectangle {
                        id: seg
                        readonly property var items: [
                            { id: "all",    label: I18n.tr("All"),         n: page.counts.all },
                            { id: "active", label: I18n.tr("In progress"), n: page.counts.active },
                            { id: "done",   label: I18n.tr("Completed"),   n: page.counts.done },
                            { id: "attn",   label: I18n.tr("Needs you"),   n: page.counts.attn }
                        ]
                        readonly property int idx: page.statusFilter === "all" ? 0
                                                 : page.statusFilter === "active" ? 1
                                                 : page.statusFilter === "done" ? 2 : 3
                        readonly property int segW: 128
                        implicitWidth: segW * items.length + 8
                        implicitHeight: 46
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusLg
                        color: Theme.panel_bg
                        border.width: 1
                        border.color: Theme.border

                        Rectangle {
                            x: 4 + seg.idx * seg.segW
                            y: 4
                            width: seg.segW
                            height: parent.height - 8
                            radius: Tokens.radiusMd
                            color: Theme.text_strong
                            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            x: 4; y: 4
                            Repeater {
                                model: seg.items
                                AbstractButton {
                                    id: segBtn
                                    width: seg.segW
                                    height: seg.height - 8
                                    readonly property bool on: seg.idx === index
                                    onClicked: page.statusFilter = modelData.id
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Item { }
                                    contentItem: Item {
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: Tokens.space2
                                            C.AppText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.label
                                                weight: Tokens.weightDemiBold
                                                font.pixelSize: Tokens.fontBody
                                                color: segBtn.on ? Theme.surface
                                                     : segBtn.hovered ? Theme.text_strong : Theme.on_surface_var
                                            }
                                            C.AppText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.n
                                                mono: true
                                                font.pixelSize: Tokens.fontCaption
                                                color: segBtn.on ? U.withAlpha(Theme.surface, 0.6) : Theme.outline
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    // search with clear
                    Rectangle {
                        implicitHeight: 46
                        Layout.preferredWidth: 300
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusLg
                        color: Theme.panel_bg
                        border.width: 1
                        border.color: histSearch.activeFocus ? Theme.border_strong : Theme.border
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space3
                            anchors.rightMargin: Tokens.space1
                            spacing: Tokens.space2
                            C.IconGlyph {
                                name: "search"; size: 17
                                glyphColor: histSearch.activeFocus ? Theme.on_surface : Theme.outline
                                Layout.alignment: Qt.AlignVCenter
                            }
                            TextField {
                                id: histSearch
                                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                T.ContextMenu.menu: C.EditMenu { editor: histSearch }
                                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                selectedTextColor: Theme.text_strong
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                placeholderText: I18n.tr("Search titles or channels")
                                placeholderTextColor: Theme.outline
                                color: Theme.on_surface
                                font.family: Fonts.body
                                font.pixelSize: Tokens.fontBody
                                selectByMouse: true
                                background: null
                                onTextChanged: page.query = text
                            }
                            C.IconButton {
                                visible: histSearch.text !== ""
                                width: 32; height: 32
                                Layout.alignment: Qt.AlignVCenter
                                iconName: "close"
                                glyphSize: 14
                                onClicked: histSearch.text = ""
                            }
                        }
                    }

                    // list / grid switch
                    Rectangle {
                        implicitWidth: 92
                        implicitHeight: 46
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusLg
                        color: Theme.panel_bg
                        border.width: 1
                        border.color: Theme.border
                        Rectangle {
                            x: page.viewMode === "list" ? 4 : 46
                            y: 4
                            width: 42; height: 38
                            radius: Tokens.radiusMd
                            color: Theme.surface_highest
                            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            x: 4; y: 4
                            Repeater {
                                model: [ { id: "list", icon: "layout_list", tip: I18n.tr("List view") },
                                         { id: "grid", icon: "layout_grid", tip: I18n.tr("Grid view") } ]
                                AbstractButton {
                                    id: viewModeBtn
                                    width: 42; height: 38
                                    onClicked: page.viewMode = modelData.id
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Item { }
                                    contentItem: Item {
                                        C.IconGlyph {
                                            anchors.centerIn: parent
                                            name: modelData.icon; size: 18
                                            glyphColor: page.viewMode === modelData.id ? Theme.text_strong : Theme.outline
                                        }
                                    }
                                    C.AppTooltip { visible: viewModeBtn.hovered; text: modelData.tip }
                                }
                            }
                        }
                    }
                }

                // ── empty state ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 260
                    visible: page.visibleRows.length === 0 && !page.showLive
                    radius: Tokens.radiusXl
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border_med

                    Column {
                        anchors.centerIn: parent
                        spacing: Tokens.space3
                        C.IconTile {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: 48
                            iconName: page.query !== "" ? "search" : "cloud_download"
                        }
                        C.AppText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.query !== "" ? I18n.tr("No matches")
                                 : page.statusFilter === "attn" ? I18n.tr("All clear")
                                 : I18n.tr("Nothing here yet")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontTitle
                            color: Theme.text_strong
                        }
                        C.AppText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 440
                            horizontalAlignment: Text.AlignHCenter
                            text: page.query !== ""
                                  ? I18n.tr("No download matches “{q}”. Try another title or channel.").replace("{q}", page.query)
                                  : page.statusFilter === "attn" ? I18n.tr("Nothing failed or paused.")
                                  : I18n.tr("Paste a link above and your downloads will show up here with live progress.")
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                        C.PrimaryButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: page.query === "" && page.statusFilter === "all"
                            iconName: "content_paste"
                            text: I18n.tr("Paste a link")
                            onClicked: page._smartPaste()
                        }
                        C.PrimaryButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: page.query !== ""
                            variant: "ghost"
                            iconName: "close"
                            text: I18n.tr("Clear search")
                            onClicked: histSearch.text = ""
                        }
                    }
                }

                // ═══ dailies: one panel per day ═══
                ColumnLayout {
                    id: rowsCol
                    objectName: "tour_downloads"
                    Layout.fillWidth: true
                    spacing: Tokens.space5
                    visible: page.visibleRows.length > 0

                    Repeater {
                        model: page.pagedGroups
                        delegate: ColumnLayout {
                            id: dayGroup
                            readonly property var group: modelData
                            Layout.fillWidth: true
                            spacing: Tokens.space2

                            RowLayout {
                                Layout.leftMargin: Tokens.space1
                                spacing: Tokens.space2
                                C.AppText {
                                    text: page._dayLabel(dayGroup.group.key)
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.text_strong
                                }
                                C.AppText {
                                    text: dayGroup.group.rows.length
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                }
                            }

                            // list: rows joined in one panel
                            Rectangle {
                                visible: page.viewMode === "list"
                                Layout.fillWidth: true
                                implicitHeight: dayRows.implicitHeight
                                radius: Tokens.radiusXl
                                color: Theme.panel_bg
                                border.width: 1
                                border.color: Theme.border
                                clip: true
                                ColumnLayout {
                                    id: dayRows
                                    width: parent.width
                                    spacing: 0
                                    Repeater {
                                        model: page.viewMode === "list" ? dayGroup.group.rows : []
                                        delegate: LibRow {
                                            row: modelData
                                            first: index === 0
                                            last: index === dayGroup.group.rows.length - 1
                                        }
                                    }
                                }
                            }

                            // grid: cards
                            GridLayout {
                                visible: page.viewMode === "grid"
                                Layout.fillWidth: true
                                columnSpacing: Tokens.space4
                                rowSpacing: Tokens.space4
                                columns: Math.max(1, Math.floor((content.width + columnSpacing) / (280 + columnSpacing)))
                                Repeater {
                                    model: page.viewMode === "grid" ? dayGroup.group.rows : []
                                    delegate: DownloadCard {
                                        row: modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 100
                                        Layout.alignment: Qt.AlignTop
                                    }
                                }
                            }
                        }
                    }
                }

                // ── pager + total ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    visible: page.visibleRows.length > 0
                    LayoutMirroring.enabled: false

                    C.AppText {
                        text: (page.visibleRows.length === Downloads.totalCount
                               ? I18n.tr("{n} videos").replace("{n}", Downloads.totalCount)
                               : I18n.tr("{shown} of {total} videos")
                                     .replace("{shown}", page.visibleRows.length)
                                     .replace("{total}", Downloads.totalCount))
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    C.PrimaryButton {
                        variant: "ghost"
                        iconName: page.allSelected ? "close" : "checklist"
                        text: page.allSelected ? I18n.tr("Clear selection") : I18n.tr("Select all")
                        implicitHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: page.allSelected ? page.clearSelection() : page.selectAllVisible()
                    }
                    C.Pager {
                        visible: page.pageCount > 1
                        pageIndex: page.pageIndex
                        pageCount: page.pageCount
                        Layout.alignment: Qt.AlignVCenter
                        onRequested: (i) => {
                            page.pageIndex = i
                            scroller.scrollToItem(rowsCol)
                        }
                    }
                }
            }
        }
    }


    // ── floating selection bar ──
    C.GlassPanel {
        id: selBar
        readonly property bool shown: page.selectedIds.length > 0
        elevation: 1.6
        radius_: Tokens.radiusPill
        width: selRow.implicitWidth + Tokens.space3 * 2
        height: 58
        anchors.horizontalCenter: parent.horizontalCenter
        y: shown ? parent.height - height - Tokens.space5 : parent.height + 20
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        z: 50

        RowLayout {
            id: selRow
            anchors.centerIn: parent
            spacing: Tokens.space2
            Rectangle {
                implicitWidth: Math.max(34, selCnt.implicitWidth + 16)
                implicitHeight: 34
                radius: Tokens.radiusPill
                color: Theme.primary
                Layout.alignment: Qt.AlignVCenter
                C.AppText {
                    id: selCnt
                    anchors.centerIn: parent
                    text: page.selectedIds.length
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_primary
                }
            }
            C.AppText {
                text: I18n.tr("selected")
                weight: Tokens.weightDemiBold
                color: Theme.text_strong
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Tokens.space2
            }
            Rectangle { width: 1; height: 26; color: Theme.border; Layout.alignment: Qt.AlignVCenter }
            C.PrimaryButton {
                variant: "ghost"
                iconName: "checklist"
                text: I18n.tr("Select all")
                visible: !page.allSelected
                implicitHeight: 40
                Layout.alignment: Qt.AlignVCenter
                onClicked: page.selectAllVisible()
            }
            C.PrimaryButton {
                variant: "ghost"
                iconName: "close"
                text: I18n.tr("Clear")
                implicitHeight: 40
                Layout.alignment: Qt.AlignVCenter
                onClicked: page.clearSelection()
            }
            C.PrimaryButton {
                variant: "danger"
                iconName: "delete"
                text: I18n.tr("Delete selected ({n})").replace("{n}", page.selectedIds.length)
                implicitHeight: 40
                Layout.alignment: Qt.AlignVCenter
                onClicked: confirmBulkDelete.open()
            }
        }
    }

    // shared quality picker, pointed at the Downloads VM
    C.QualityPicker { id: qualityPicker; target: Downloads }

    C.VideoPlayer { id: videoPlayer }

    C.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - (selBar.shown ? 150 : 80)
    }

    // ── delete confirmation ──
    ConfirmDialog {
        id: confirmDelete
        property string pendingId: ""
        property string pendingTitle: ""
        function ask(id, title) { pendingId = id; pendingTitle = title || ""; open() }
        heading: I18n.tr("Remove this download?")
        body: confirmDelete.pendingTitle !== ""
              ? I18n.tr("“{t}” will be removed from this list. The downloaded file on disk is not deleted.")
                    .replace("{t}", confirmDelete.pendingTitle)
              : I18n.tr("This entry will be removed from the list. The downloaded file on disk is not deleted.")
        onConfirmed: Downloads.deleteEntry(confirmDelete.pendingId)
    }

    // ── bulk delete confirmation ──
    ConfirmDialog {
        id: confirmBulkDelete
        heading: I18n.tr("Remove {n} download(s)?").replace("{n}", page.selectedIds.length)
        body: I18n.tr("The selected entries will be removed from this list. The downloaded files on disk are not deleted.")
        onConfirmed: {
            Downloads.deleteEntries(page.selectedIds)
            page.clearSelection()
        }
    }

    // ── inline building blocks ────────────────────────────────────────────

    // A small status dot; `pulse` adds a radiating ring (live downloads).
    component LiveDot: Item {
        id: ld
        property color dotColor: Theme.primary
        property bool pulse: false
        property int dot: 8
        width: dot; height: dot
        Rectangle {
            id: ldHalo
            anchors.centerIn: parent
            width: ld.dot; height: ld.dot; radius: ld.dot / 2
            color: ld.dotColor
            opacity: 0
            visible: ld.pulse
        }
        ParallelAnimation {
            running: ld.pulse && ld.visible
            loops: Animation.Infinite
            NumberAnimation { target: ldHalo; property: "scale"; from: 1; to: 2.8; duration: 1400; easing.type: Easing.OutCubic }
            NumberAnimation { target: ldHalo; property: "opacity"; from: 0.55; to: 0; duration: 1400; easing.type: Easing.OutCubic }
        }
        Rectangle {
            anchors.centerIn: parent
            width: ld.dot; height: ld.dot; radius: ld.dot / 2
            color: ld.dotColor
        }
    }

    // Gradient progress track with a travelling shine; indeterminate sweep.
    component ProgressTrack: Rectangle {
        id: pt
        property real value: 0
        property bool indeterminate: false
        property color accent: Theme.primary
        implicitHeight: 6
        radius: height / 2
        color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.07)
        clip: true

        Rectangle {
            id: ptFill
            visible: !pt.indeterminate
            height: parent.height
            radius: parent.radius
            width: pt.value > 0 ? Math.max(height, parent.width * Math.min(1, pt.value)) : 0
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.mix(pt.accent, Qt.rgba(0, 0, 0, 1), 0.12) }
                GradientStop { position: 1.0; color: U.mix(pt.accent, Qt.rgba(1, 1, 1, 1), 0.22) }
            }
            Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

            Rectangle {
                id: ptShine
                width: 90
                height: parent.height
                x: -width
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.38) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
                NumberAnimation on x {
                    running: ptFill.visible && ptFill.width > 24
                    loops: Animation.Infinite
                    from: -90
                    to: Math.max(0, ptFill.width)
                    duration: 1700
                    easing.type: Easing.InOutSine
                }
            }
        }
        Rectangle {
            id: ptSweep
            visible: pt.indeterminate
            width: parent.width * 0.3
            height: parent.height
            radius: parent.radius
            color: pt.accent
            SequentialAnimation on x {
                running: ptSweep.visible
                loops: Animation.Infinite
                NumberAnimation { from: -ptSweep.width; to: pt.width
                                  duration: 1300; easing.type: Easing.InOutQuad }
            }
        }
    }

    // Status pill: dot + label in the status colour.
    component StatusBadge: Rectangle {
        id: sb
        property string kind: "queued"
        property bool onMedia: false      // sitting over a thumbnail
        readonly property color _c: page._kindColor(kind)
        radius: Tokens.radiusPill
        implicitHeight: 22
        implicitWidth: sbRow.implicitWidth + Tokens.space3 * 2
        color: sb.onMedia ? Qt.rgba(0, 0, 0, 0.62) : U.withAlpha(sb._c, 0.12)
        border.width: sb.onMedia ? 0 : 1
        border.color: U.withAlpha(sb._c, 0.32)
        Row {
            id: sbRow
            anchors.centerIn: parent
            spacing: 6
            LiveDot {
                anchors.verticalCenter: parent.verticalCenter
                dotColor: sb._c
                pulse: sb.kind === "active" || sb.kind === "merging"
                dot: 6
            }
            C.AppText {
                anchors.verticalCenter: parent.verticalCenter
                text: page._kindLabel(sb.kind)
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontMicro
                color: sb.onMedia ? "#ffffff" : sb._c
            }
        }
    }


    // Rounded thumbnail with skeleton + fallback glyph.
    component Thumb: Rectangle {
        id: th
        property string thumbId: ""
        property real r: Tokens.radiusMd
        radius: r
        color: Theme.surface_high
        Image {
            id: thImg
            anchors.fill: parent
            visible: false
            source: th.thumbId !== "" ? "image://thumbs/" + th.thumbId : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 480
            sourceSize.height: 270
        }
        Item {
            id: thMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; radius: th.r; color: "white" }
        }
        MultiEffect {
            anchors.fill: parent
            source: thImg
            maskEnabled: true
            maskSource: thMask
            opacity: thImg.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        C.ThumbSkeleton {
            anchors.fill: parent
            active: th.thumbId !== "" && thImg.status !== Image.Ready
                    && thImg.status !== Image.Error
            topLeftRadius: th.r
            topRightRadius: th.r
            bottomLeftRadius: th.r
            bottomRightRadius: th.r
            glyph: "movie"
        }
        C.IconGlyph {
            anchors.centerIn: parent
            visible: th.thumbId === ""
            name: "movie"; size: 22
            glyphColor: Theme.outline
        }
    }

    // The overlay that sits on a thumbnail: progress ring while running, a
    // play button on hover once done, a status glyph for failed / stopped.
    component ThumbOverlay: Item {
        id: tov
        property string kind: "queued"
        property real pct: 0
        property bool hovered: false
        property string quality: ""
        signal play()

        // dark wash
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusMd
            color: "#000000"
            opacity: tov.kind === "active" || tov.kind === "merging" ? 0.45
                   : tov.kind === "failed" || tov.kind === "stopped" ? 0.40
                   : tov.kind === "done" && tov.hovered ? 0.30 : 0.0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        }
        C.ProgressRing {
            anchors.centerIn: parent
            visible: tov.kind === "active" || tov.kind === "merging"
            ringSize: 46
            thickness: 4
            value: tov.pct
            spinning: tov.kind === "merging"
            label: tov.kind === "merging" ? "" : Math.round(tov.pct * 100) + "%"
        }
        Rectangle {
            anchors.centerIn: parent
            visible: tov.kind === "done"
            width: 44; height: 44; radius: 22
            color: Theme.primary
            opacity: tov.hovered ? 1 : 0
            scale: tov.hovered ? 1 : 0.8
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            C.IconGlyph {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1
                name: "play_arrow"; fill: true; size: 22
                glyphColor: Theme.on_primary
            }
        }
        C.IconGlyph {
            anchors.centerIn: parent
            visible: tov.kind === "failed" || tov.kind === "stopped"
            name: tov.kind === "failed" ? "error" : "pause"
            fill: true; size: 26
            glyphColor: "#ffffff"
        }
        // quality badge, bottom corner
        Rectangle {
            visible: tov.quality !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6
            radius: Tokens.radiusXs
            implicitHeight: 18
            implicitWidth: qBadge.implicitWidth + 10
            color: Qt.rgba(0, 0, 0, 0.72)
            C.AppText {
                id: qBadge
                anchors.centerIn: parent
                text: tov.quality
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontMicro
                color: "#ffffff"
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: tov.kind === "done"
            cursorShape: tov.kind === "done" ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: tov.play()
        }
    }

    // Selection tick box.
    component TickBox: AbstractButton {
        id: tb
        property bool picked: false
        property bool onMedia: false
        implicitWidth: 22
        implicitHeight: 22
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: Tokens.radiusSm - 2
            color: tb.picked ? Theme.primary : tb.onMedia ? Qt.rgba(0, 0, 0, 0.55) : U.withAlpha(Theme.primary, 0)
            border.width: tb.picked ? 0 : 1.5
            border.color: tb.onMedia ? Qt.rgba(1, 1, 1, 0.85)
                          : tb.hovered ? Theme.primary : Theme.outline
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            C.IconGlyph {
                anchors.centerIn: parent
                visible: tb.picked
                name: "check"; size: 14
                glyphColor: Theme.on_primary
            }
        }
    }

    // Per-row action buttons, shared by list rows and grid cards.
    component RowActions: Row {
        id: ra
        property var row: ({})
        property string kind: "queued"
        spacing: Tokens.space1

        C.IconButton {
            visible: ra.kind === "done"
            width: 36; height: 36
            iconName: "folder_open"
            tip: I18n.tr("Show in folder")
            onClicked: Downloads.reveal(ra.row.videoId)
        }
        C.IconButton {
            visible: ra.kind === "done"
            width: 36; height: 36
            iconName: "open_in_new"
            tip: I18n.tr("Open in your default player")
            onClicked: Downloads.openFile(ra.row.videoId)
        }
        C.IconButton {
            visible: ra.kind === "active" || ra.kind === "merging"
            width: 36; height: 36
            iconName: "stop_circle"
            accent: Theme.error
            tip: I18n.tr("Stop this download")
            onClicked: Downloads.cancelDownload(ra.row.videoId)
        }
        C.IconButton {
            visible: ra.kind === "stopped"
            width: 36; height: 36
            iconName: "play_arrow"
            accent: Theme.primary
            active: true
            tip: I18n.tr("Resume at the same quality")
            onClicked: {
                // Resuming is a fresh yt-dlp run, so it needs the JS runtime too.
                if (!Geo.allowDownload()) return
                if (!Deno.ready) { Deno.requestInstall(); return }
                Downloads.resumeDownload(ra.row.videoId)
            }
        }
        C.IconButton {
            width: 36; height: 36
            iconName: "delete"
            accent: Theme.error
            tip: I18n.tr("Remove from this list")
            onClicked: confirmDelete.ask(ra.row.videoId, ra.row.title)
        }
        C.IconButton {
            visible: ra.kind === "done"
            width: 36; height: 36
            iconName: "play_arrow"
            iconFill: true
            accent: Theme.primary
            active: true
            tip: I18n.tr("Play in the app")
            onClicked: page._playRow(ra.row.videoId)
        }
    }


    // ── now-transferring row ──
    component LiveRow: Rectangle {
        id: lr
        property var row: ({})
        readonly property var liveData: {
            var _ = Downloads.progressTick
            return page._live(row.videoId)
        }
        readonly property string kind: page._kind(row.status)
        readonly property int _pct: liveData ? (liveData.pct || 0) : (row.pct || 0)

        Layout.fillWidth: true
        implicitHeight: 116
        radius: Tokens.radiusXl
        color: Theme.panel_bg
        border.width: 1
        border.color: lrHover.hovered ? U.withAlpha(Theme.primary, 0.40) : U.withAlpha(Theme.primary, 0.22)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        HoverHandler { id: lrHover }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.space3
            anchors.rightMargin: Tokens.space4
            spacing: Tokens.space4

            Item {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 90
                Layout.alignment: Qt.AlignVCenter
                Thumb { anchors.fill: parent; thumbId: lr.row.thumbId || "" }
                Rectangle {
                    visible: (lr.row.quality || "") !== ""
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    radius: Tokens.radiusXs
                    implicitHeight: 20
                    implicitWidth: lrQ.implicitWidth + 10
                    color: Qt.rgba(0, 0, 0, 0.72)
                    C.AppText {
                        id: lrQ
                        anchors.centerIn: parent
                        text: lr.row.quality || ""
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontMicro
                        color: "#ffffff"
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.space1

                C.AppText {
                    Layout.fillWidth: true
                    text: lr.row.title
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontLabel
                    color: Theme.text_strong
                    elide: Text.ElideRight
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: lr.row.channelTitle || "—"
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                }
                ProgressTrack {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space2
                    implicitHeight: 8
                    value: lr._pct / 100
                    indeterminate: lr.kind === "merging"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: Tokens.space2
                    LayoutMirroring.enabled: false
                    C.AppText {
                        text: lr.kind === "merging" ? "" : lr._pct + "%"
                        visible: text !== ""
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.primary
                    }
                    C.AppText {
                        text: {
                            var s = page._sizeText(lr.row, lr.liveData)
                            var st = page._statusLine(lr.row, lr.liveData, lr._pct)
                            if (lr.kind === "merging" || s === "") return st
                            return s
                        }
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.AppText {
                        text: {
                            if (!lr.liveData) return ""
                            var sp = lr.liveData.speedText || ""
                            var et = (lr.liveData.etaText || "") !== ""
                                     ? I18n.tr("{t} left").replace("{t}", lr.liveData.etaText) : ""
                            return sp !== "" && et !== "" ? sp + "  ·  " + et : sp + et
                        }
                        visible: text !== ""
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                }
            }

            C.IconButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 40; implicitHeight: 40
                iconName: "stop_circle"
                accent: Theme.error
                tip: I18n.tr("Stop this download")
                onClicked: Downloads.cancelDownload(lr.row.videoId)
            }
        }

        C.AppTooltip {
            visible: lrHover.hovered && lr.liveData && (lr.liveData.tipText || "") !== ""
            delay: 450
            text: lr.liveData ? (lr.liveData.tipText || "") : ""
        }
    }

    // ── library row (one line in a day panel) ──
    component LibRow: Item {
        id: lib
        property var row: ({})
        property bool first: false
        property bool last: false
        readonly property var liveData: {
            var _ = Downloads.progressTick
            return page._live(row.videoId)
        }
        readonly property string kind: page._kind(row.status)
        readonly property bool _running: kind === "active" || kind === "merging"
        readonly property int _pct: liveData ? (liveData.pct || 0) : (row.pct || 0)
        readonly property bool _picked: page.selectedIds.indexOf(row.videoId) !== -1
        readonly property bool _anySel: page.selectedIds.length > 0

        Layout.fillWidth: true
        implicitHeight: 92

        HoverHandler { id: libHover }

        Rectangle {
            anchors.fill: parent
            color: lib._picked ? U.withAlpha(Theme.primary, 0.08)
                 : libHover.hovered ? U.hoverTint(Theme.panel_bg, Theme.isDark, 0.035)
                 : U.withAlpha(U.hoverTint(Theme.panel_bg, Theme.isDark, 0.035), 0)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        Rectangle {
            visible: !lib.first
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Tokens.space4
            anchors.rightMargin: Tokens.space4
            height: 1
            color: Theme.border
        }
        // a pip on the leading edge for rows that need you
        Rectangle {
            visible: lib.kind === "failed" || lib.kind === "stopped" || lib._running
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - Tokens.space5 * 2
            radius: 2
            color: page._kindColor(lib.kind)
        }

        // a click anywhere while selecting toggles the row
        // (a MouseArea under the content, not a TapHandler: a handler's passive
        // grab would also fire on the tick box and undo its toggle)
        MouseArea {
            anchors.fill: parent
            enabled: lib._anySel
            cursorShape: Qt.PointingHandCursor
            onClicked: page.toggleSelected(lib.row.videoId)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space3 + 2
            anchors.rightMargin: Tokens.space4
            spacing: Tokens.space4

            Item {
                Layout.preferredWidth: 128
                Layout.preferredHeight: 72
                Layout.alignment: Qt.AlignVCenter
                Thumb { id: libThumb; anchors.fill: parent; thumbId: lib.row.thumbId || "" }
                ThumbOverlay {
                    anchors.fill: parent
                    kind: lib.kind
                    pct: lib._pct / 100
                    hovered: libHover.hovered && !lib._anySel
                    quality: lib.row.quality || ""
                    onPlay: page._playRow(lib.row.videoId)
                }
                TickBox {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 6
                    onMedia: true
                    picked: lib._picked
                    visible: libHover.hovered || lib._picked || lib._anySel
                    onClicked: page.toggleSelected(lib.row.videoId)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.space1

                C.AppText {
                    Layout.fillWidth: true
                    text: lib.row.title
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontLabel
                    color: Theme.text_strong
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    C.AppText {
                        text: lib.row.channelTitle || "—"
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        Layout.maximumWidth: 240
                    }
                    C.AppText {
                        readonly property string meta: {
                            var parts = []
                            if ((lib.row.quality || "") !== "") parts.push(lib.row.quality)
                            var s = page._sizeText(lib.row, lib.liveData)
                            if (s !== "") parts.push(s)
                            return parts.join("  ·  ")
                        }
                        visible: meta !== ""
                        text: "·  " + meta
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                    Item { Layout.fillWidth: true }
                }
                // why it failed / where it stopped
                C.AppText {
                    visible: lib.kind === "failed" || lib.kind === "stopped" || lib._running
                    Layout.fillWidth: true
                    text: page._statusLine(lib.row, lib.liveData, lib._pct)
                    font.pixelSize: Tokens.fontCaption
                    weight: Tokens.weightDemiBold
                    color: page._kindColor(lib.kind)
                    elide: Text.ElideRight
                }
            }

            // ── right side: status at rest, actions on hover ──
            // Finished rows keep it quiet (a tick and the time they landed);
            // rows that need you keep their one action visible at all times.
            C.PrimaryButton {
                visible: lib.kind === "failed"
                variant: "ghost"
                iconName: "refresh"
                text: I18n.tr("Retry")
                implicitHeight: 38
                Layout.alignment: Qt.AlignVCenter
                onClicked: page._resume(lib.row.videoId)
            }
            C.PrimaryButton {
                visible: lib.kind === "stopped"
                iconName: "play_arrow"
                text: I18n.tr("Resume")
                implicitHeight: 38
                Layout.alignment: Qt.AlignVCenter
                onClicked: page._resume(lib.row.videoId)
            }
            // Status and hover actions share ONE fixed-width slot and cross-fade.
            // They used to be two layout siblings swapped with `visible`, so on
            // hover the row's layout re-ran: the title column lost ~100px, its
            // text re-elided and everything jumped for a frame (the "blink" on
            // finished downloads). The slot is sized for the wider of the two,
            // so hovering changes opacity only, never geometry.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Math.max(libStatus.implicitWidth, libActions.implicitWidth)
                Layout.preferredHeight: 38
                Row {
                    id: libStatus
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.space2
                    opacity: lib.kind === "done" && !libHover.hovered ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                    C.IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check_circle"; fill: true; size: 17
                        glyphColor: Theme.secondary_container
                    }
                    C.AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: lib.row.whenText || ""
                        visible: text !== ""
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                }
                Row {
                    id: libActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.space1
                    opacity: libHover.hovered || lib.kind === "failed" || lib.kind === "stopped" || lib._running ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                    C.IconButton {
                        visible: lib.kind === "done"
                        width: 38; height: 38
                        iconName: "folder_open"
                        tip: I18n.tr("Show in folder")
                        onClicked: Downloads.reveal(lib.row.videoId)
                    }
                    C.IconButton {
                        visible: lib.kind === "done"
                        width: 38; height: 38
                        iconName: "open_in_new"
                        tip: I18n.tr("Open in your default player")
                        onClicked: Downloads.openFile(lib.row.videoId)
                    }
                    C.IconButton {
                        visible: lib._running
                        width: 38; height: 38
                        iconName: "stop_circle"
                        accent: Theme.error
                        tip: I18n.tr("Stop this download")
                        onClicked: Downloads.cancelDownload(lib.row.videoId)
                    }
                    C.IconButton {
                        width: 38; height: 38
                        iconName: "delete"
                        accent: Theme.error
                        tip: I18n.tr("Remove from this list")
                        onClicked: confirmDelete.ask(lib.row.videoId, lib.row.title)
                    }
                    C.IconButton {
                        visible: lib.kind === "done"
                        width: 38; height: 38
                        iconName: "play_arrow"
                        iconFill: true
                        accent: Theme.primary
                        active: true
                        tip: I18n.tr("Play in the app")
                        onClicked: page._playRow(lib.row.videoId)
                    }
                }
            }
        }

        // v3.39.9: press + drag the row out of the app to copy the video
        // anywhere (desktop, a folder, an editor, a chat).
        C.FileDragSource {
            canDrag: lib.kind === "done"
            paths: function () { return page._dragPaths(lib.row.videoId) }
            preview: libThumb
        }

        C.AppTooltip {
            visible: libHover.hovered && lib._running && lib.liveData
                     && (lib.liveData.tipText || "") !== ""
            delay: 450
            text: lib.liveData ? (lib.liveData.tipText || "") : ""
        }
    }


    // ── grid card ──
    component DownloadCard: Rectangle {
        id: card
        property var row: ({})
        readonly property var liveData: {
            var _ = Downloads.progressTick
            return page._live(row.videoId)
        }
        readonly property string kind: page._kind(row.status)
        readonly property bool _running: kind === "active" || kind === "merging"
        readonly property int _livePct: liveData ? (liveData.pct || 0) : (row.pct || 0)
        readonly property bool _picked: page.selectedIds.indexOf(row.videoId) !== -1

        implicitHeight: cardCol.implicitHeight + Tokens.space2 * 2
        radius: Tokens.radiusXl
        color: _picked ? U.mix(Theme.panel_bg, Theme.primary, 0.06) : Theme.panel_bg
        border.width: 1
        border.color: _picked ? U.withAlpha(Theme.primary, 0.55)
                    : cardHover.hovered ? U.withAlpha(Theme.primary, 0.32)
                    : Theme.border
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        transform: Translate {
            id: cardLift
            y: cardHover.hovered ? -2 : 0
            Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        // keep the hit box on the resting footprint too (see LiftMask.qml)
        containmentMask: C.LiftMask { target: card; dy: cardLift.y }
        HoverHandler { id: cardHover }

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space2
            spacing: Tokens.space3

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(width * 9 / 16)
                Thumb { id: cardThumb; anchors.fill: parent; thumbId: card.row.thumbId || "" }
                ThumbOverlay {
                    anchors.fill: parent
                    kind: card.kind
                    pct: card._livePct / 100
                    hovered: cardHover.hovered
                    quality: card.row.quality || ""
                    onPlay: page._playRow(card.row.videoId)
                }
                TickBox {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    onMedia: true
                    picked: card._picked
                    visible: cardHover.hovered || card._picked || page.selectedIds.length > 0
                    onClicked: page.toggleSelected(card.row.videoId)
                }
                StatusBadge {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    kind: card.kind
                    onMedia: true
                }
                ProgressTrack {
                    visible: card._running
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 4
                    value: card._livePct / 100
                    indeterminate: card.kind === "merging"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space2
                Layout.rightMargin: Tokens.space2
                spacing: 3
                C.AppText {
                    Layout.fillWidth: true
                    text: card.row.title
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontBody
                    color: Theme.text_strong
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    Layout.preferredHeight: Math.ceil(font.pixelSize * 1.45) * 2
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: card.row.channelTitle || "—"
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: {
                        var s = page._statusLine(card.row, card.liveData, card._livePct)
                        var z = page._sizeText(card.row, card.liveData)
                        if (card._running && card.liveData && (card.liveData.speedText || "") !== "")
                            s += "  ·  " + card.liveData.speedText
                        return z !== "" ? s + "  ·  " + z : s
                    }
                    mono: card._running
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontMicro + 1
                    color: card.kind === "done" ? Theme.outline : page._kindColor(card.kind)
                    elide: Text.ElideRight
                }
            }

            RowActions {
                Layout.alignment: Qt.AlignRight
                Layout.rightMargin: Tokens.space1
                Layout.bottomMargin: Tokens.space1
                row: card.row
                kind: card.kind
            }
        }

        // v3.39.9: drag the card out of the app to copy the video anywhere.
        C.FileDragSource {
            canDrag: card.kind === "done"
            paths: function () { return page._dragPaths(card.row.videoId) }
            preview: cardThumb
        }

        C.AppTooltip {
            visible: cardHover.hovered && card._running && card.liveData
                     && (card.liveData.tipText || "") !== ""
            delay: 450
            text: card.liveData ? (card.liveData.tipText || "") : ""
        }
    }

    // Shared confirmation dialog (single + bulk delete).
    component ConfirmDialog: Dialog {
        id: cd
        property string heading: ""
        property string body: ""
        signal confirmed()

        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, page.width - 80)
        padding: 0

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast }
        }

        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            clip: true
            C.GlowBlob {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: -150
                size: 240
                glow: Theme.error
                strength: Theme.isDark ? 0.14 : 0.08
            }
        }

        header: Item {
            implicitHeight: cdHead.implicitHeight + Tokens.space5 * 2
            ColumnLayout {
                id: cdHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                C.IconTile {
                    iconName: "delete"
                    tint: Theme.error
                    size: 46
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                }
                C.AppText {
                    text: cd.heading
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontTitle - 2
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }

        contentItem: C.AppText {
            text: cd.body
            color: Theme.on_surface_var
            wrapMode: Text.WordWrap
            padding: Tokens.space5
            topPadding: 0
        }

        footer: Item {
            implicitHeight: Tokens.fieldHeight + Tokens.space5 * 2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.topMargin: Tokens.space3
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    text: I18n.tr("Cancel")
                    onClicked: cd.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete"
                    text: I18n.tr("Remove")
                    onClicked: { cd.confirmed(); cd.close() }
                }
            }
        }
    }
}
