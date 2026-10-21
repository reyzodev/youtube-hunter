import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Content Lab — three tabs on one page:
//   • Library        — every blueprint ever generated in AI Ideas, grouped into
//                      the keyword/channel section it was made in. Open a
//                      section to get the same rail-of-cards + one-open-blueprint
//                      layout the AI Ideas results use (shared BlueprintPane).
//   • Channel report — hand the AI a scraped channel export and get back a rich,
//                      self-contained HTML report; optionally fold in your saved
//                      blueprints and/or your Niche Scan research.
//   • Teleprompter   — read any saved blueprint's script off the screen while
//                      the camera rolls. This used to be its own nav row
//                      (Script Studio), which meant two doors into one room: the
//                      same Teleprompter also opens as an overlay from the
//                      "Read on camera" button on any blueprint. It lives here
//                      because the scripts it reads ARE this page's blueprints.
Item {
    id: page

    Connections {
        target: ContentLab
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    // ── v10 presentation helpers (read-only views of the VM) ──
    readonly property int _sectionCount: (ContentLab.entries || []).length
    readonly property int _reportCount: (ContentLab.reports || []).length
    readonly property int _maxIdeas: {
        var es = ContentLab.entries || []
        var m = 1
        for (var i = 0; i < es.length; i++) m = Math.max(m, es[i].ideaCount || 0)
        return m
    }

    // ── v12 library helpers (pure views of the VM, no writes) ──
    // Landing order: 0 recent (the VM's own order) · 1 most ideas · 2 top score · 3 A–Z
    property int libSort: 0
    readonly property var _sortedEntries: {
        var es = (ContentLab.entries || []).slice()
        if (libSort === 1)
            es.sort(function(a, b) { return (b.ideaCount || 0) - (a.ideaCount || 0) })
        else if (libSort === 2)
            es.sort(function(a, b) {
                return ((b.bestScore || 0) - (a.bestScore || 0)) || ((b.avgScore || 0) - (a.avgScore || 0))
            })
        else if (libSort === 3)
            es.sort(function(a, b) { return String(a.title || "").localeCompare(String(b.title || "")) })
        return es
    }
    readonly property int _totalIdeas: {
        var es = ContentLab.entries || []
        var n = 0
        for (var i = 0; i < es.length; i++) n += (es[i].ideaCount || 0)
        return n
    }
    readonly property int _totalFavs: {
        var es = ContentLab.entries || []
        var n = 0
        for (var i = 0; i < es.length; i++) n += (es[i].favCount || 0)
        return n
    }
    // The most recently touched section leads, wide — only in the default
    // order and with no search, where "first" really means "latest".
    readonly property bool _featureFirst: libSort === 0 && ContentLab.entrySearch === ""
                                          && _sortedEntries.length >= 3

    // Rail order inside an open section: 0 newest (VM order) · 1 top score.
    property int railSort: 0
    readonly property var _railIdeas: {
        var xs = (ContentLab.ideas || []).slice()
        if (railSort === 1)
            xs.sort(function(a, b) { return (b.score || 0) - (a.score || 0) })
        return xs
    }
    readonly property int _activeIdx: {
        var xs = _railIdeas
        for (var i = 0; i < xs.length; i++)
            if ((xs[i].id || 0) === ContentLab.activeId) return i
        return -1
    }
    readonly property var _railStats: {
        var xs = _railIdeas
        var best = 0, sum = 0, n = 0
        for (var i = 0; i < xs.length; i++) {
            var s = xs[i].score || 0
            if (s > 0) { sum += s; n++ }
            best = Math.max(best, s)
        }
        return { best: best, avg: n > 0 ? Math.round(sum / n) : 0 }
    }
    // The app's three-band score language (same thresholds as the cards).
    function bandColor(s) {
        return s >= 85 ? Theme.secondary_container
             : s >= 70 ? Theme.primary
             : s > 0 ? Theme.warn
             : Theme.outline
    }
    // Walk the rail by `d` cards (clamped), and page the strip onto the pick.
    function stepIdea(d) {
        var xs = page._railIdeas
        if (xs.length === 0) return
        var i = page._activeIdx < 0 ? 0 : page._activeIdx + d
        i = Math.max(0, Math.min(xs.length - 1, i))
        if ((xs[i].id || 0) !== ContentLab.activeId) ContentLab.selectIdea(xs[i].id || 0)
        railStrip.pageIndex = Math.floor(i / Math.max(1, railStrip.perPage))
        railStrip.forceActiveFocus()
    }
    // A section (re)opens on its newest blueprints, first page.
    property string _openSeen: ContentLab.openTitle
    on_OpenSeenChanged: {
        railSort = 0
        railStrip.pageIndex = 0
    }

    // One door for every tab switch (tab bar, stat tiles, shortcuts) — the
    // exact logic the old tab buttons ran: switching INTO the prompter reloads
    // its pick list.
    // m:ss for a read-out at the prompter's current pace
    function mmss(words) {
        var w = Math.max(1, Studio.wpm || 150)
        var secs = Math.round((words || 0) / w * 60)
        var m = Math.floor(secs / 60)
        var r = secs % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }
    readonly property int _maxBeatWords: {
        var bs = Studio.beats || []
        var m = 1
        for (var i = 0; i < bs.length; i++) m = Math.max(m, bs[i].words || 0)
        return m
    }

    function switchTab(i) {
        ContentLab.tab = i
        if (i === 1) Studio.refreshLibrary()
    }
    Shortcut { sequences: ["Ctrl+1"]; enabled: page.visible; onActivated: page.switchTab(0) }
    Shortcut { sequences: ["Ctrl+2"]; enabled: page.visible; onActivated: page.switchTab(1) }

    // tab content arrives with a short fade + rise (transform only, layout untouched)
    property int _tabSeen: ContentLab.tab
    on_TabSeenChanged: tabEnter.restart()
    ParallelAnimation {
        id: tabEnter
        NumberAnimation { target: tabBody; property: "opacity"; from: 0.0; to: 1.0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
        NumberAnimation { target: tabShift; property: "y"; from: 10; to: 0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
    }

    // Reload the section list and the AI provider config on show, so the page
    // never displays a stale library after a fresh AI Ideas run or a Settings
    // change. The prompter's own pick list is refreshed too when that tab is the
    // one showing — a blueprint generated a minute ago should be readable
    // without restarting the app.
    onVisibleChanged: if (visible) {
        ContentLab.reloadConfig()
        ContentLab.refreshEntries()
        // Both "combine with" lists too: a creator who picked the export, went
        // off to generate a blueprint or a brief, and came back should find it
        // offered here without re-picking the file.
        ContentLab.refreshCombineChoices()
        if (ContentLab.tab === 1) Studio.refreshLibrary()
    }
    Component.onCompleted: {
        ContentLab.reloadConfig()
        ContentLab.refreshEntries()
    }

    // Debounce the library search field — pure CPU re-slicing, but rebuilding
    // the card grid on every keystroke still stutters on a big library.
    Timer {
        id: searchTimer
        interval: 220
        property string pending: ""
        onTriggered: ContentLab.entrySearch = pending
    }

    C.SmoothScrollView {
        id: labScroll
        anchors.fill: parent

        Item {
            id: canvas
            width: parent.width
            implicitHeight: content.implicitHeight + Tokens.space7 * 2

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
                y: Tokens.space7
                spacing: Tokens.space5

                // ── v10 "lab deck": heading, live stats and the tab bar in one
                // lit console, so the page opens on what you have (sections,
                // reports, AI status) instead of on a paragraph. Every control in
                // here drives exactly the same VM calls as the old strip did.
                C.GlassPanel {
                    id: deck
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: deckCol.implicitHeight + Tokens.space5 * 2

                    C.CornerGlow { radius: Tokens.radiusXl; size: 520 }

                    ColumnLayout {
                        id: deckCol
                        anchors.fill: parent
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space5

                        C.PageHeader {
                            iconName: "biotech"
                            title: I18n.tr("Content Lab")
                            subtitle: I18n.tr("Your saved blueprints and the teleprompter you shoot from.")

                            // live stats — each one is also a door to its tab
                            Repeater {
                                model: [
                                    { key: "sec", icon: "auto_awesome", tab: 0,
                                      value: String(page._sectionCount), label: I18n.tr("Sections") },
                                    { key: "rep", icon: "insights", tab: 1,
                                      value: String(page._reportCount), label: I18n.tr("Reports") },
                                    { key: "ai", icon: ContentLab.hasAiKey ? "psychology" : "warning", tab: -1,
                                      value: ContentLab.hasAiKey ? (ContentLab.providerLabel || I18n.tr("Ready"))
                                                                 : I18n.tr("No key"),
                                      label: I18n.tr("AI provider") }
                                ]
                                AbstractButton {
                                    id: stat
                                    visible: deck.width > 760 || modelData.key !== "rep"
                                    readonly property bool warn: modelData.key === "ai" && !ContentLab.hasAiKey
                                    readonly property color tint: warn ? Theme.warn
                                                                : modelData.key === "ai" ? Theme.secondary_container
                                                                : Theme.primary
                                    implicitHeight: 52
                                    implicitWidth: Math.min(200, statRow.implicitWidth + Tokens.space3 * 2)
                                    onClicked: modelData.tab >= 0 ? page.switchTab(modelData.tab) : App.goto(10)
                                    HoverHandler { id: statHover; cursorShape: Qt.PointingHandCursor }
                                    transform: Translate {
                                        id: statLift
                                        y: statHover.hovered ? -2 : 0
                                        Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                    }
                                    // keep the hit box on the resting footprint too (see LiftMask.qml)
                                    containmentMask: C.LiftMask { target: stat; dy: statLift.y }
                                    background: Rectangle {
                                        radius: Tokens.radiusLg
                                        color: statHover.hovered ? U.withAlpha(stat.tint, 0.10) : U.withAlpha(Theme.surface_high, 0.7)
                                        border.width: 1
                                        border.color: statHover.hovered ? U.withAlpha(stat.tint, 0.40) : Theme.border
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                    }
                                    contentItem: Item {
                                        RowLayout {
                                            id: statRow
                                            anchors.fill: parent
                                            anchors.leftMargin: Tokens.space3
                                            anchors.rightMargin: Tokens.space3
                                            spacing: Tokens.space2
                                            C.IconTile {
                                                iconName: modelData.icon
                                                size: 30; glyphSize: 15
                                                tint: stat.tint
                                                lit: statHover.hovered
                                            }
                                            ColumnLayout {
                                                spacing: 0
                                                Layout.fillWidth: true
                                                C.AppText {
                                                    text: modelData.value
                                                    mono: modelData.key !== "ai"
                                                    weight: Tokens.weightExtraBold
                                                    font.pixelSize: modelData.key === "ai" ? Tokens.fontBody : Tokens.fontSubtitle
                                                    color: stat.warn ? Theme.warn : Theme.text_strong
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    Layout.maximumWidth: 130
                                                }
                                                C.AppText {
                                                    text: modelData.label
                                                    font.pixelSize: 11
                                                    color: Theme.on_surface_var
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── tab bar: one track, a sliding pill under the active tab ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3

                            Rectangle {
                                id: tabTrack
                                objectName: "tour_labTabs"
                                implicitWidth: tabRowOuter.implicitWidth + 8
                                implicitHeight: 48
                                radius: Tokens.radiusLg
                                color: Theme.input_bg
                                border.width: 1
                                border.color: Theme.border

                                // the sliding active pill
                                Rectangle {
                                    id: tabPill
                                    readonly property Item target: tabRep.count > ContentLab.tab ? tabRep.liveItemAt(ContentLab.tab) : null
                                    x: target ? tabRowOuter.x + target.x : 4
                                    width: target ? target.width : 0
                                    y: 4
                                    height: parent.height - 8
                                    radius: Tokens.radiusMd
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Theme.primary }
                                        GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
                                    }
                                    Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                    Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                    // specular top sheen
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                                        height: parent.height * 0.5
                                        radius: parent.radius - 1
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                        }
                                    }
                                }

                                Row {
                                    id: tabRowOuter
                                    x: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Repeater {
                                        id: tabRep
                                        // itemAt() is not a notifying lookup: a binding that ran before the
                                        // delegates existed got null and kept it (thumb missing on first show,
                                        // the active label invisible in light theme). `built` re-runs it.
                                        property int built: 0
                                        onItemAdded: built++
                                        onItemRemoved: built++
                                        function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                        model: [
                                            { label: I18n.tr("Library"), icon: "auto_awesome", key: "Ctrl+1" },
                                            { label: I18n.tr("Teleprompter"), icon: "nav_studio", key: "Ctrl+2" }
                                        ]
                                        AbstractButton {
                                            id: tabBtn
                                            height: 40
                                            implicitWidth: tabRow.implicitWidth + Tokens.space4 * 2
                                            readonly property bool active: ContentLab.tab === index
                                            // badge: library size / report count; a live dot while a report runs
                                            readonly property string badge: index === 0 ? (page._sectionCount > 0 ? String(page._sectionCount) : "")
                                                                          : index === 1 ? (page._reportCount > 0 ? String(page._reportCount) : "")
                                                                          : ""
                                            onClicked: page.switchTab(index)
                                            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                                            C.AppTooltip {
                                                visible: tabHover.hovered
                                                text: modelData.label + "  ·  " + modelData.key
                                            }
                                            background: Rectangle {
                                                radius: Tokens.radiusMd
                                                color: !tabBtn.active && tabHover.hovered
                                                       ? U.hoverTint(Theme.input_bg, Theme.isDark) : U.withAlpha(U.hoverTint(Theme.input_bg, Theme.isDark), 0)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                implicitWidth: tabRow.implicitWidth
                                                implicitHeight: tabRow.implicitHeight
                                                Row {
                                                    id: tabRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space2
                                                    C.IconGlyph {
                                                        name: modelData.icon
                                                        size: 17
                                                        fill: tabBtn.active
                                                        glyphColor: tabBtn.active ? Theme.on_primary : Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                                    }
                                                    C.AppText {
                                                        text: modelData.label
                                                        weight: tabBtn.active ? Tokens.weightBold : Tokens.weightDemiBold
                                                        color: tabBtn.active ? Theme.on_primary
                                                             : tabHover.hovered ? Theme.text_strong : Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                                    }
                                                    // count badge
                                                    Rectangle {
                                                        visible: tabBtn.badge !== "" && !(index === 1 && ContentLab.csvBusy)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        radius: Tokens.radiusPill
                                                        implicitWidth: Math.max(20, badgeLbl.implicitWidth + 10)
                                                        implicitHeight: 20
                                                        color: tabBtn.active ? Qt.rgba(1, 1, 1, 0.22) : U.withAlpha(Theme.primary, 0.12)
                                                        C.AppText {
                                                            id: badgeLbl
                                                            anchors.centerIn: parent
                                                            text: tabBtn.badge
                                                            mono: true
                                                            weight: Tokens.weightBold
                                                            font.pixelSize: 11
                                                            color: tabBtn.active ? Theme.on_primary : Theme.primary
                                                        }
                                                    }
                                                    // live dot while the channel report is being built
                                                    Rectangle {
                                                        visible: index === 1 && ContentLab.csvBusy
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 8; height: 8; radius: 4
                                                        color: tabBtn.active ? Theme.on_primary : Theme.primary
                                                        SequentialAnimation on opacity {
                                                            running: index === 1 && ContentLab.csvBusy && page.visible
                                                            loops: Animation.Infinite
                                                            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                                                            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // keyboard hint
                            Row {
                                visible: deck.width > 820
                                spacing: Tokens.space1
                                Layout.alignment: Qt.AlignVCenter
                                Repeater {
                                    model: ["Ctrl", "1–3"]
                                    Rectangle {
                                        radius: Tokens.radiusXs
                                        color: Theme.surface_high
                                        border.width: 1
                                        border.color: Theme.border
                                        implicitWidth: kbdLbl.implicitWidth + 12
                                        implicitHeight: 24
                                        C.AppText {
                                            id: kbdLbl
                                            anchors.centerIn: parent
                                            text: modelData
                                            mono: true
                                            font.pixelSize: 11
                                            color: Theme.on_surface_var
                                            LayoutMirroring.enabled: false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // all three tabs share one body so a tab switch can fade + rise
                ColumnLayout {
                    id: tabBody
                    Layout.fillWidth: true
                    spacing: Tokens.space5
                    transform: Translate { id: tabShift; y: 0 }

                    // ═══ LIBRARY TAB ═══
                    // v12 redesign. Landing: a toolbar (search · sort · totals)
                    // over a grid of fingerprinted section cards, the latest one
                    // set wide. Section open: a cover with the section's numbers,
                    // one control bar (format · favourites · order · stepper),
                    // a fixed-height card rail you can walk with ← / →, and the
                    // shared BlueprintPane underneath.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: ContentLab.tab === 0
                        spacing: Tokens.space5

                        // ── landing ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !ContentLab.sectionOpen
                            spacing: Tokens.space4

                            // toolbar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                visible: ContentLab.hasEntries || ContentLab.entrySearch !== ""

                                Item {
                                    Layout.preferredWidth: Math.min(380, content.width * 0.34)
                                    implicitHeight: libSearch.implicitHeight
                                    C.LineField {
                                        id: libSearch
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                        placeholder: I18n.tr("Search Content Lab sections…")
                                        text: ContentLab.entrySearch
                                        onTextChanged: { searchTimer.pending = text; searchTimer.restart() }
                                    }
                                }

                                // sort — a sliding pill over four orders
                                Rectangle {
                                    visible: page._sectionCount > 1
                                    implicitWidth: sortRow.implicitWidth + 8
                                    implicitHeight: 40
                                    radius: Tokens.radiusPill
                                    color: Theme.input_bg
                                    border.width: 1
                                    border.color: Theme.border
                                    Rectangle {
                                        readonly property Item t: sortRep.count > page.libSort ? sortRep.liveItemAt(page.libSort) : null
                                        x: t ? sortRow.x + t.x : 4
                                        y: 4
                                        width: t ? t.width : 0
                                        height: parent.height - 8
                                        radius: Tokens.radiusPill
                                        color: U.withAlpha(Theme.primary, 0.16)
                                        border.width: 1
                                        border.color: U.withAlpha(Theme.primary, 0.45)
                                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                        Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                    }
                                    Row {
                                        id: sortRow
                                        x: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        Repeater {
                                            id: sortRep
                                            // itemAt() is not a notifying lookup: a binding that ran before the
                                            // delegates existed got null and kept it (thumb missing on first show,
                                            // the active label invisible in light theme). `built` re-runs it.
                                            property int built: 0
                                            onItemAdded: built++
                                            onItemRemoved: built++
                                            function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                            model: [
                                                { l: I18n.tr("Recent"),     i: "history" },
                                                { l: I18n.tr("Most ideas"), i: "bar_chart" },
                                                { l: I18n.tr("Top score"),  i: "star" },
                                                { l: I18n.tr("A–Z"),        i: "sort" }
                                            ]
                                            AbstractButton {
                                                id: sortBtn
                                                height: 32
                                                implicitWidth: sortLblRow.implicitWidth + Tokens.space4 * 2
                                                readonly property bool on: page.libSort === index
                                                onClicked: page.libSort = index
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                background: Item {}
                                                contentItem: Item {
                                                    Row {
                                                        id: sortLblRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        C.IconGlyph {
                                                            name: modelData.i; size: 13
                                                            glyphColor: sortBtn.on ? Theme.primary : Theme.on_surface_var
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        C.AppText {
                                                            text: modelData.l
                                                            weight: Tokens.weightBold
                                                            font.pixelSize: Tokens.fontCaption
                                                            color: sortBtn.on ? Theme.primary
                                                                 : sortBtn.hovered ? Theme.text_strong : Theme.on_surface_var
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // totals
                                Row {
                                    visible: ContentLab.hasEntries && content.width > 900
                                    spacing: Tokens.space4
                                    Repeater {
                                        model: [
                                            { v: page._sectionCount, l: I18n.tr("Sections") },
                                            { v: page._totalIdeas,   l: I18n.tr("blueprints") },
                                            { v: page._totalFavs,    l: I18n.tr("Favorites") }
                                        ]
                                        Row {
                                            spacing: 6
                                            C.AppText {
                                                text: String(modelData.v)
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: Tokens.fontSubtitle
                                                color: Theme.text_strong
                                                anchors.baseline: lbl.baseline
                                                LayoutMirroring.enabled: false
                                            }
                                            C.AppText {
                                                id: lbl
                                                text: modelData.l
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                            }
                                        }
                                    }
                                }
                            }

                            // empty state — a stack of "blueprint sheets" and one clear way forward
                            C.GlassPanel {
                                Layout.fillWidth: true
                                visible: !ContentLab.hasEntries
                                radius: Tokens.radiusXl
                                implicitHeight: emptyCol.implicitHeight + Tokens.space8 * 2
                                elevation: 0
                                C.CornerGlow { radius: Tokens.radiusXl; size: 520 }
                                Column {
                                    id: emptyCol
                                    anchors.centerIn: parent
                                    spacing: Tokens.space4
                                    Item {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 168; height: 104
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: 96; height: 70
                                                radius: Tokens.radiusMd
                                                x: 36 + (index - 1) * 34
                                                y: 16 + Math.abs(index - 1) * 10
                                                rotation: (index - 1) * 9
                                                z: index === 1 ? 2 : 1
                                                antialiasing: true
                                                color: index === 1 ? Theme.panel_bg : Theme.surface_high
                                                border.width: 1
                                                border.color: index === 1 ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                                                // a tiny score barcode on the front sheet
                                                Row {
                                                    visible: index === 1
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 12
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: 12
                                                    spacing: 3
                                                    Repeater {
                                                        model: [0.5, 0.8, 0.65, 0.95, 0.7, 0.85, 0.55]
                                                        Rectangle {
                                                            width: 6
                                                            height: 34 * modelData
                                                            radius: 2
                                                            anchors.bottom: parent.bottom
                                                            color: modelData > 0.8 ? Theme.secondary_container
                                                                 : U.withAlpha(Theme.primary, 0.4 + modelData * 0.6)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    C.AppText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: ContentLab.entrySearch !== "" ? I18n.tr("No section matches that search")
                                                                            : I18n.tr("Nothing built yet")
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: 28
                                        font.letterSpacing: I18n.rtl ? 0 : -0.6
                                        color: Theme.text_strong
                                    }
                                    C.AppText {
                                        width: Math.min(520, content.width - Tokens.space6 * 2)
                                        horizontalAlignment: Text.AlignHCenter
                                        text: ContentLab.entrySearch !== ""
                                              ? I18n.tr("Try a shorter word, or clear the search to see every section.")
                                              : I18n.tr("Go to AI Ideas, generate a few blueprints, and they show up here grouped by keyword or channel.")
                                        color: Theme.on_surface_var
                                        font.pixelSize: Tokens.fontLabel
                                        wrapMode: Text.Wrap
                                    }
                                    C.PrimaryButton {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: ContentLab.entrySearch === ""
                                        iconName: "nav_ideas"
                                        text: I18n.tr("Open AI Ideas")
                                        onClicked: App.goto(6)
                                    }
                                    C.PrimaryButton {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: ContentLab.entrySearch !== ""
                                        variant: "ghost"
                                        iconName: "close"
                                        text: I18n.tr("Clear search")
                                        onClicked: { libSearch.text = ""; ContentLab.entrySearch = "" }
                                    }
                                }
                            }

                            // section grid — column count/card width from
                            // content.width, never the grid's own width (a
                            // GridLayout sizes from children's implicit widths, so
                            // reading grid.width here is a 0-wide binding loop).
                            GridLayout {
                                id: entryGrid
                                Layout.fillWidth: true
                                visible: ContentLab.hasEntries
                                columnSpacing: Tokens.space4
                                rowSpacing: Tokens.space4
                                readonly property real availW: content.width
                                // Frozen during the rail slide (App.railAnimating) —
                                // see the Niche Finder grid for why.
                                property int _frozenCols: 0
                                property real _frozenW: 0
                                readonly property int _liveCols: Math.max(1, Math.floor(availW / 320))
                                columns: (App.railAnimating && _frozenCols > 0) ? _frozenCols : _liveCols
                                readonly property real cardW:
                                    (App.railAnimating && _frozenW > 0) ? _frozenW
                                    : (availW - columnSpacing * (columns - 1)) / columns
                                Connections {
                                    target: App
                                    function onRailAnimatingChanged() {
                                        if (App.railAnimating) {
                                            entryGrid._frozenCols = entryGrid.columns
                                            entryGrid._frozenW = entryGrid.cardW
                                        }
                                    }
                                }

                                Repeater {
                                    model: page._sortedEntries
                                    C.LibrarySectionCard {
                                        readonly property bool lead: index === 0 && page._featureFirst && entryGrid.columns >= 3
                                        featured: lead
                                        entry: modelData
                                        Layout.columnSpan: lead ? 2 : 1
                                        Layout.preferredWidth: lead ? entryGrid.cardW * 2 + entryGrid.columnSpacing
                                                                    : entryGrid.cardW
                                        Layout.fillHeight: true
                                        Layout.alignment: Qt.AlignTop
                                        onOpenRequested: (id) => ContentLab.openEntry(id)
                                        onDeleteRequested: (id, title, count) => confirmDeleteEntry.ask(id, title, count)
                                    }
                                }
                            }
                        }

                        // ── section open ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: ContentLab.sectionOpen
                            spacing: Tokens.space4

                            // cover: breadcrumb, title, the section's numbers
                            C.GlassPanel {
                                id: secCover
                                Layout.fillWidth: true
                                radius: Tokens.radiusXl
                                elevation: 1.2
                                implicitHeight: secCol.implicitHeight + Tokens.space5 * 2
                                C.CornerGlow { radius: secCover.radius; size: 560 }

                                ColumnLayout {
                                    id: secCol
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space5
                                    spacing: Tokens.space4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space4

                                        // back — a square key, then the breadcrumb + title
                                        C.IconButton {
                                            Layout.alignment: Qt.AlignTop
                                            iconName: I18n.rtl ? "arrow_forward" : "arrow_back"
                                            implicitWidth: 44
                                            implicitHeight: 44
                                            glyphSize: 20
                                            tip: I18n.tr("All sections")
                                            onClicked: ContentLab.backToList()
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                spacing: 6
                                                AbstractButton {
                                                    id: crumb
                                                    implicitWidth: crumbLbl.implicitWidth
                                                    implicitHeight: crumbLbl.implicitHeight
                                                    onClicked: ContentLab.backToList()
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    background: Item {}
                                                    contentItem: C.AppText {
                                                        id: crumbLbl
                                                        text: I18n.tr("Library")
                                                        weight: Tokens.weightBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: crumb.hovered ? Theme.primary : Theme.on_surface_var
                                                    }
                                                }
                                                C.AppText {
                                                    text: "/"
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.outline
                                                }
                                                C.AppText {
                                                    text: I18n.tr("Section")
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.outline
                                                }
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: ContentLab.openTitle
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: content.width < 760 ? 28 : 38
                                                font.letterSpacing: I18n.rtl ? 0 : -1.1
                                                lineHeight: 1.05
                                                color: Theme.text_strong
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }

                                    // the numbers of this section
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        Repeater {
                                            model: [
                                                { v: String(ContentLab.ideaCount), l: I18n.tr("blueprints"), i: "auto_awesome", c: "" },
                                                { v: page._railStats.best > 0 ? String(page._railStats.best) : "—", l: I18n.tr("best score"), i: "star", c: "best" },
                                                { v: page._railStats.avg > 0 ? String(page._railStats.avg) : "—", l: I18n.tr("average"), i: "bar_chart", c: "avg" },
                                                { v: ContentLab.shortCount + " / " + ContentLab.longCount, l: I18n.tr("short / long"), i: "fmt_short", c: "" },
                                                { v: String(ContentLab.favoriteCount), l: I18n.tr("Favorites"), i: "bookmark", c: "" }
                                            ]
                                            Rectangle {
                                                id: secStat
                                                readonly property color tint: modelData.c === "best" ? page.bandColor(page._railStats.best)
                                                                            : modelData.c === "avg" ? page.bandColor(page._railStats.avg)
                                                                            : Theme.primary
                                                width: secStatRow.implicitWidth + Tokens.space4 * 2
                                                height: 54
                                                radius: Tokens.radiusLg
                                                color: U.withAlpha(Theme.surface_high, 0.7)
                                                border.width: 1
                                                border.color: Theme.border
                                                RowLayout {
                                                    id: secStatRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space3
                                                    C.IconTile {
                                                        iconName: modelData.i
                                                        size: 30; glyphSize: 15
                                                        tint: secStat.tint
                                                    }
                                                    ColumnLayout {
                                                        spacing: 0
                                                        C.AppText {
                                                            text: modelData.v
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: Tokens.fontSubtitle
                                                            color: modelData.c !== "" ? secStat.tint : Theme.text_strong
                                                            LayoutMirroring.enabled: false
                                                        }
                                                        C.AppText {
                                                            text: modelData.l
                                                            font.pixelSize: Tokens.fontMicro
                                                            color: Theme.on_surface_var
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // control bar: format · favourites · order · stepper
                            RowLayout {
                                Layout.fillWidth: true
                                visible: ContentLab.hasIdeas
                                spacing: Tokens.space3

                                // All / Short / Long — sliding pill
                                Rectangle {
                                    implicitWidth: clFmtRow.implicitWidth + 8
                                    implicitHeight: 40
                                    radius: Tokens.radiusPill
                                    color: Theme.input_bg
                                    border.width: 1
                                    border.color: Theme.border
                                    Rectangle {
                                        readonly property Item t: clFmtRep.count > ContentLab.railFormat ? clFmtRep.liveItemAt(ContentLab.railFormat) : null
                                        x: t ? clFmtRow.x + t.x : 4
                                        y: 4
                                        width: t ? t.width : 0
                                        height: parent.height - 8
                                        radius: Tokens.radiusPill
                                        color: Theme.primary
                                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                        Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                    }
                                    Row {
                                        id: clFmtRow
                                        x: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        Repeater {
                                            id: clFmtRep
                                            // itemAt() is not a notifying lookup: a binding that ran before the
                                            // delegates existed got null and kept it (thumb missing on first show,
                                            // the active label invisible in light theme). `built` re-runs it.
                                            property int built: 0
                                            onItemAdded: built++
                                            onItemRemoved: built++
                                            function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                            model: [
                                                { idx: 0, label: ContentLab.railFormatOptions[0], n: ContentLab.ideaCount },
                                                { idx: 1, label: ContentLab.railFormatOptions[1], n: ContentLab.shortCount },
                                                { idx: 2, label: ContentLab.railFormatOptions[2], n: ContentLab.longCount }
                                            ]
                                            AbstractButton {
                                                id: fmtBtn
                                                height: 32
                                                implicitWidth: fmtBtnRow.implicitWidth + Tokens.space4 * 2
                                                readonly property bool on: ContentLab.railFormat === modelData.idx
                                                onClicked: ContentLab.railFormat = modelData.idx
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                background: Item {}
                                                contentItem: Item {
                                                    Row {
                                                        id: fmtBtnRow
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        C.AppText {
                                                            text: modelData.label
                                                            weight: Tokens.weightBold
                                                            font.pixelSize: Tokens.fontCaption + 1
                                                            color: fmtBtn.on ? Theme.on_primary
                                                                 : fmtBtn.hovered ? Theme.text_strong : Theme.on_surface_var
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        C.AppText {
                                                            text: String(modelData.n)
                                                            mono: true
                                                            font.pixelSize: Tokens.fontMicro
                                                            color: fmtBtn.on ? U.withAlpha(Theme.on_primary, 0.8) : Theme.outline
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // favourites toggle
                                AbstractButton {
                                    id: favToggle
                                    visible: ContentLab.favoriteCount > 0 || ContentLab.railFavOnly
                                    readonly property bool on: ContentLab.railFavOnly
                                    implicitHeight: 40
                                    implicitWidth: favTRow.implicitWidth + Tokens.space4 * 2
                                    onClicked: ContentLab.railFavOnly = !ContentLab.railFavOnly
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Tokens.radiusPill
                                        color: favToggle.on ? U.withAlpha(Theme.primary, 0.16)
                                             : favToggle.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark) : Theme.input_bg
                                        border.width: 1
                                        border.color: favToggle.on ? U.withAlpha(Theme.primary, 0.55) : Theme.border
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    }
                                    contentItem: Item {
                                        Row {
                                            id: favTRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            C.IconGlyph {
                                                name: "bookmark"; size: 14
                                                fill: favToggle.on
                                                glyphColor: favToggle.on ? Theme.primary : Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: I18n.tr("Favorites")
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption + 1
                                                color: favToggle.on ? Theme.primary : Theme.on_surface
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: String(ContentLab.favoriteCount)
                                                mono: true
                                                font.pixelSize: Tokens.fontMicro
                                                color: Theme.outline
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                // order: newest / top score
                                AbstractButton {
                                    id: orderToggle
                                    visible: ContentLab.ideas.length > 1
                                    implicitHeight: 40
                                    implicitWidth: ordRow.implicitWidth + Tokens.space4 * 2
                                    onClicked: page.railSort = page.railSort === 0 ? 1 : 0
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Tokens.radiusPill
                                        color: orderToggle.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark) : Theme.input_bg
                                        border.width: 1
                                        border.color: Theme.border
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    }
                                    contentItem: Item {
                                        Row {
                                            id: ordRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            C.IconGlyph {
                                                name: page.railSort === 1 ? "star" : "history"
                                                size: 14
                                                glyphColor: Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: page.railSort === 1 ? I18n.tr("Top score first") : I18n.tr("Newest first")
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption + 1
                                                color: Theme.on_surface
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.IconGlyph {
                                                name: "arrow_up_down"
                                                size: 13
                                                glyphColor: Theme.outline
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // keyboard hint, lit while the rail has focus
                                Row {
                                    visible: content.width > 980 && page._railIdeas.length > 1
                                    spacing: Tokens.space1
                                    opacity: railStrip.activeFocus ? 1 : 0.55
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                    Repeater {
                                        model: ["←", "→"]
                                        Rectangle {
                                            radius: Tokens.radiusXs
                                            color: Theme.surface_high
                                            border.width: 1
                                            border.color: railStrip.activeFocus ? U.withAlpha(Theme.primary, 0.5) : Theme.border
                                            implicitWidth: 26
                                            implicitHeight: 24
                                            C.AppText {
                                                anchors.centerIn: parent
                                                text: modelData
                                                mono: true
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                                LayoutMirroring.enabled: false
                                            }
                                        }
                                    }
                                }

                                // stepper: ‹ 3 / 12 ›
                                Rectangle {
                                    visible: page._railIdeas.length > 0
                                    implicitWidth: stepRow.implicitWidth + 8
                                    implicitHeight: 40
                                    radius: Tokens.radiusPill
                                    color: Theme.input_bg
                                    border.width: 1
                                    border.color: Theme.border
                                    Row {
                                        id: stepRow
                                        anchors.centerIn: parent
                                        spacing: Tokens.space1
                                        C.IconButton {
                                            iconName: I18n.rtl ? "chevron_right" : "chevron_left"
                                            implicitWidth: 32; implicitHeight: 32
                                            enabled: page._activeIdx > 0
                                            opacity: enabled ? 1 : 0.35
                                            tip: I18n.tr("Previous")
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: page.stepIdea(-1)
                                        }
                                        C.AppText {
                                            text: (page._activeIdx + 1) + " / " + page._railIdeas.length
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption + 1
                                            color: Theme.text_strong
                                            anchors.verticalCenter: parent.verticalCenter
                                            LayoutMirroring.enabled: false
                                        }
                                        C.IconButton {
                                            iconName: I18n.rtl ? "chevron_left" : "chevron_right"
                                            implicitWidth: 32; implicitHeight: 32
                                            enabled: page._activeIdx < page._railIdeas.length - 1
                                            opacity: enabled ? 1 : 0.35
                                            tip: I18n.tr("Next")
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: page.stepIdea(1)
                                        }
                                    }
                                }
                            }

                            // idea rail — a PAGED strip of fixed-size cards under a
                            // clip, driven by C.Pager. It takes keyboard focus when a
                            // card is picked, so ← / → walk the blueprints.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !ContentLab.railIsEmpty && ContentLab.hasIdeas
                                spacing: Tokens.space3

                                Item {
                                    id: railStrip
                                    Layout.fillWidth: true
                                    implicitHeight: 214 + Tokens.space3 * 2
                                    clip: true
                                    activeFocusOnTab: true

                                    readonly property int cardW: 300
                                    readonly property int gap: Tokens.space3
                                    readonly property int perPage:
                                        Math.max(1, Math.floor((width + gap) / (cardW + gap)))
                                    readonly property int pageCount:
                                        Math.max(1, Math.ceil(page._railIdeas.length / perPage))
                                    property int pageIndex: 0
                                    onPageCountChanged: if (pageIndex > pageCount - 1) pageIndex = pageCount - 1

                                    // In a mirrored layout the strip reads right to left,
                                    // so the visual arrow keys swap meaning.
                                    Keys.onLeftPressed: page.stepIdea(I18n.rtl ? 1 : -1)
                                    Keys.onRightPressed: page.stepIdea(I18n.rtl ? -1 : 1)
                                    Keys.onPressed: (event) => {
                                        if (event.key === Qt.Key_Home) { page.stepIdea(-100000); event.accepted = true }
                                        else if (event.key === Qt.Key_End) { page.stepIdea(100000); event.accepted = true }
                                    }

                                    Row {
                                        id: railRow
                                        spacing: railStrip.gap
                                        y: Tokens.space3
                                        // In RTL the Row lays its cards out right to left, so
                                        // the strip is anchored by its END and shifted the
                                        // other way — page 1 is then the rightmost cards.
                                        readonly property real shift: railStrip.pageIndex * railStrip.perPage
                                                                      * (railStrip.cardW + railStrip.gap)
                                        x: I18n.rtl ? (railStrip.width - width + shift) : -shift
                                        Behavior on x {
                                            NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                                        }
                                        Repeater {
                                            model: page._railIdeas
                                            C.LibraryIdeaCard {
                                                width: railStrip.cardW
                                                height: 214
                                                idea: modelData
                                                position: (index + 1) + " / " + page._railIdeas.length
                                                active: ContentLab.activeId === (modelData.id || 0)
                                                regenerating: ContentLab.regenId === (modelData.id || 0)
                                                onSelected: (id) => { railStrip.forceActiveFocus(); ContentLab.selectIdea(id) }
                                                onFavorited: (id) => ContentLab.toggleFavorite(id)
                                                onDeleteRequested: (id) => confirmDelete.ask(id)
                                            }
                                        }
                                    }

                                    // trailing-edge fade: the next page's first card peeks
                                    // in here, so it fades rather than being cut.
                                    Rectangle {
                                        visible: railStrip.pageIndex < railStrip.pageCount - 1
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 36
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: U.withAlpha(Theme.background, I18n.rtl ? 0.85 : 0.0) }
                                            GradientStop { position: 1.0; color: U.withAlpha(Theme.background, I18n.rtl ? 0.0 : 0.85) }
                                        }
                                    }
                                }

                                C.Pager {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: railStrip.pageCount > 1
                                    pageIndex: railStrip.pageIndex
                                    pageCount: railStrip.pageCount
                                    showEdgeJumps: false
                                    onRequested: (i) => railStrip.pageIndex = i
                                }
                            }

                            // favourites filter matched nothing
                            C.GlassPanel {
                                Layout.fillWidth: true
                                visible: ContentLab.railIsEmpty
                                radius: Tokens.radiusXl
                                implicitHeight: 150
                                elevation: 0
                                Column {
                                    anchors.centerIn: parent
                                    spacing: Tokens.space3
                                    C.IconGlyph {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: "bookmark"; size: 28
                                        glyphColor: U.withAlpha(Theme.primary, 0.55)
                                    }
                                    C.AppText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: I18n.tr("No favorited blueprints in this section yet.")
                                        color: Theme.on_surface_var
                                    }
                                    C.PrimaryButton {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        variant: "ghost"
                                        text: I18n.tr("Show all")
                                        implicitHeight: 34
                                        onClicked: ContentLab.railFavOnly = false
                                    }
                                }
                            }

                            // the open blueprint
                            // v3.16-p3: async, double-buffered host (see BlueprintStage)
                            // — switching blueprints shows a loading veil instead
                            // of freezing the page.
                            C.BlueprintStage {
                                Layout.fillWidth: true
                                scroller: labScroll
                                visible: ContentLab.hasActive
                                motion: App.ambientMotion === undefined || App.ambientMotion
                                idea: ContentLab.active
                                regenerating: ContentLab.regenId === (ContentLab.active.id || 0)
                                onFavorited: (id) => ContentLab.toggleFavorite(id)
                                onDeleteRequested: (id) => confirmDelete.ask(id)
                                onRegenerateRequested: (id) => ContentLab.regenerate(id)
                                onCopyRequested: (text) => ContentLab.copyText(text)
                                // Same one-liner as AI Ideas: load the script, and
                                // Main.qml raises the prompter overlay.
                                onPrompterRequested: (id) => Studio.openBlueprint(id)
                            }
                        }
                    }

                    // ═══ CHANNEL REPORT TAB ═══
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: false
                        spacing: Tokens.space5

                        // no-AI-key banner
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: !ContentLab.hasAiKey
                            implicitHeight: csvWarnRow.implicitHeight + Tokens.space4 * 2
                            RowLayout {
                                id: csvWarnRow
                                anchors.fill: parent
                                anchors.margins: Tokens.space4
                                spacing: Tokens.space3
                                C.IconGlyph { name: "warning"; size: 20; glyphColor: Theme.warn }
                                C.AppText {
                                    text: I18n.tr("No AI provider configured — add a key in Settings to analyze a CSV.")
                                    color: Theme.warn
                                    weight: Tokens.weightDemiBold
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                C.PrimaryButton {
                                    variant: "ghost"
                                    iconName: "settings"
                                    text: I18n.tr("Open Settings")
                                    implicitHeight: 36
                                    onClicked: App.goto(10)
                                }
                            }
                        }

                        // ── provider capability note ──
                        // Every provider can write the report; only Gemini can also
                        // search the web and watch the videos first. Saying so keeps
                        // a thinner report on another provider from reading as a bug.
                        Rectangle {
                            Layout.fillWidth: true
                            visible: ContentLab.hasAiKey
                            implicitHeight: csvCapRow.implicitHeight + Tokens.space3 * 2
                            radius: Tokens.radiusMd
                            color: U.withAlpha(Theme.primary, 0.06)
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, 0.18)
                            RowLayout {
                                id: csvCapRow
                                anchors.fill: parent
                                anchors.margins: Tokens.space3
                                spacing: Tokens.space2
                                C.IconGlyph {
                                    name: ContentLab.isGeminiProvider ? "auto_awesome" : "info"
                                    size: 15
                                    glyphColor: Theme.primary
                                    Layout.alignment: Qt.AlignTop
                                }
                                C.AppText {
                                    text: ContentLab.providerCapabilityNote
                                    color: Theme.on_surface_var
                                    font.pixelSize: Tokens.fontCaption
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // ── v10 run tracker: the report is a real three-step flow (export → optional
                        // context → build), so it is shown as one. Read-only: it reflects VM state;
                        // only step 1 is clickable and it opens the same file picker as the button.
                        // ── v11 "report studio" cover ──
                        // The tab opens on an instrument rather than a form: a
                        // live bar meter that idles, reads a signal while the
                        // report is built, and locks green when it is done — with
                        // the three-step run tracker underneath it.
                        C.GlassPanel {
                            id: steps
                            Layout.fillWidth: true
                            radius: Tokens.radiusXl
                            elevation: 1.3
                            implicitHeight: studioCol.implicitHeight + Tokens.space6 * 2
                            readonly property bool s1: ContentLab.hasCsv
                            readonly property bool s2: ContentLab.selectedBlueprintCount > 0 || ContentLab.selectedBriefCount > 0
                            readonly property bool s3run: ContentLab.csvBusy
                            readonly property bool s3: ContentLab.hasCsvReport && !ContentLab.csvBusy
                            readonly property color tint: s3run ? Theme.primary : s3 ? Theme.secondary_container : Theme.primary

                            Rectangle {
                                anchors.fill: parent
                                radius: steps.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(steps.tint, 0.0) }
                                    GradientStop { position: 1.0; color: U.withAlpha(steps.tint, Theme.isDark ? 0.14 : 0.08) }
                                }
                                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                            }
                            C.CornerGlow { radius: steps.radius; size: 520; glow: steps.tint }

                            ColumnLayout {
                                id: studioCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.space6
                                spacing: Tokens.space5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space5

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        RowLayout {
                                            spacing: Tokens.space2
                                            Rectangle {
                                                width: 8; height: 8; radius: 4
                                                color: steps.tint
                                                Layout.alignment: Qt.AlignVCenter
                                                SequentialAnimation on opacity {
                                                    running: steps.s3run && page.visible
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                                                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                                                }
                                            }
                                            C.AppText {
                                                text: steps.s3run ? I18n.tr("BUILDING YOUR REPORT")
                                                      : steps.s3 ? I18n.tr("REPORT READY")
                                                      : I18n.tr("AI REPORT STUDIO")
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: 11
                                                color: steps.tint
                                            }
                                        }
                                        C.AppText {
                                            text: I18n.tr("Channel report")
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontDisplay + 6
                                            color: Theme.text_strong
                                        }
                                        C.AppText {
                                            text: I18n.tr("Drop in a scraped channel export. Get back real charts, the top videos, and an AI read on what to make next.")
                                            color: Theme.on_surface_var
                                            font.pixelSize: Tokens.fontLabel
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            Layout.maximumWidth: 620
                                        }
                                    }

                                    C.PulseBars {
                                        visible: steps.width > 720
                                        Layout.preferredWidth: 260
                                        Layout.preferredHeight: 84
                                        Layout.alignment: Qt.AlignBottom
                                        bars: 16
                                        accent: Theme.primary
                                        mode: steps.s3run ? "busy" : steps.s3 ? "done" : "idle"
                                    }
                                }

                                // the run tracker
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 68
                                    radius: Tokens.radiusLg
                                    color: U.withAlpha(Theme.surface_high, Theme.isDark ? 0.65 : 0.85)
                                    border.width: 1
                                    border.color: Theme.border

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.space5
                                        anchors.rightMargin: Tokens.space5
                                        spacing: Tokens.space3

                                        Repeater {
                                            model: [
                                                { n: 1, title: I18n.tr("Pick export"),
                                                  done: steps.s1, run: false, optional: false,
                                                  sub: steps.s1 ? ContentLab.csvName : I18n.tr("Choose CSV…") },
                                                { n: 2, title: I18n.tr("Add context"),
                                                  done: steps.s2, run: false, optional: true,
                                                  sub: steps.s2 ? (ContentLab.selectedBlueprintCount + ContentLab.selectedBriefCount) + " ✓"
                                                                : I18n.tr("Optional") },
                                                { n: 3, title: I18n.tr("Build report"),
                                                  done: steps.s3, run: steps.s3run, optional: false,
                                                  sub: steps.s3run ? I18n.tr("Running") : steps.s3 ? I18n.tr("Done") : I18n.tr("Analyze channel") }
                                            ]
                                            RowLayout {
                                                id: stepItem
                                                Layout.fillWidth: true
                                                spacing: Tokens.space3
                                                readonly property bool current: !modelData.done && !modelData.run
                                                    && ((modelData.n === 1) || (modelData.n === 2 && steps.s1) || (modelData.n === 3 && steps.s1))
                                                readonly property color tint: modelData.done ? Theme.secondary_container
                                                                            : (modelData.run || stepItem.current) ? Theme.primary
                                                                            : Theme.outline

                                                // the step node
                                                Item {
                                                    implicitWidth: 34; implicitHeight: 34
                                                    Rectangle {
                                                        id: halo
                                                        anchors.centerIn: parent
                                                        width: 34; height: 34; radius: 17
                                                        color: U.withAlpha(stepItem.tint, 0.22)
                                                        visible: modelData.run
                                                        SequentialAnimation on scale {
                                                            running: modelData.run && page.visible
                                                            loops: Animation.Infinite
                                                            NumberAnimation { from: 0.85; to: 1.35; duration: 900; easing.type: Easing.OutCubic }
                                                            NumberAnimation { from: 1.35; to: 0.85; duration: 900; easing.type: Easing.InOutSine }
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 30; height: 30; radius: 15
                                                        antialiasing: true
                                                        color: modelData.done || modelData.run ? stepItem.tint : U.withAlpha(stepItem.tint, 0.10)
                                                        border.width: 1
                                                        border.color: U.withAlpha(stepItem.tint, modelData.done || modelData.run ? 0.0 : 0.45)
                                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                                                        C.IconGlyph {
                                                            anchors.centerIn: parent
                                                            visible: modelData.done
                                                            name: "check"; size: 16
                                                            glyphColor: Theme.on_primary
                                                        }
                                                        C.AppText {
                                                            anchors.centerIn: parent
                                                            visible: !modelData.done
                                                            text: String(modelData.n)
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: Tokens.fontCaption
                                                            color: modelData.run ? Theme.on_primary : stepItem.tint
                                                        }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: modelData.n === 1 && !ContentLab.csvBusy
                                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: csvDialog.open()
                                                    }
                                                }

                                                ColumnLayout {
                                                    spacing: 0
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 60
                                                    C.AppText {
                                                        text: modelData.title
                                                        weight: Tokens.weightBold
                                                        color: stepItem.current || modelData.run ? Theme.text_strong : Theme.on_surface
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    C.AppText {
                                                        text: modelData.sub
                                                        mono: modelData.n === 1 && steps.s1
                                                        font.pixelSize: 11
                                                        color: modelData.done ? Theme.secondary_container
                                                             : modelData.run ? Theme.primary : Theme.on_surface_var
                                                        elide: Text.ElideMiddle
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                // connector to the next step
                                                Rectangle {
                                                    visible: modelData.n < 3
                                                    Layout.fillWidth: true
                                                    Layout.maximumWidth: 120
                                                    Layout.preferredHeight: 2
                                                    radius: 1
                                                    color: U.withAlpha(Theme.outline, 0.22)
                                                    Rectangle {
                                                        height: parent.height
                                                        radius: 1
                                                        width: modelData.done ? parent.width : 0
                                                        color: Theme.secondary_container
                                                        Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // pick + info panel
                        C.GlassPanel {
                            Layout.fillWidth: true
                            implicitHeight: pickCol.implicitHeight + Tokens.space5 * 2
                            ColumnLayout {
                                id: pickCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4

                                C.AppText {
                                    text: I18n.tr("STEP 1 · THE EXPORT")
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: 11
                                    color: Theme.on_surface_var
                                }

                                // What the run will actually do, before it starts:
                                // watching the videos is what turns a ~1 minute report
                                // into several, so it is stated up front rather than
                                // discovered from the status line.
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: ContentLab.willWatchVideos
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: "schedule"
                                        size: 15
                                        glyphColor: Theme.warn
                                        Layout.alignment: Qt.AlignTop
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Gemini will watch this channel's best videos first — Shorts in full, and the middle minutes of longer ones — so expect several minutes before the report appears.")
                                        color: Theme.warn
                                        font.pixelSize: Tokens.fontCaption
                                        wrapMode: Text.Wrap
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space3
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: "upload_file"
                                        text: I18n.tr("Choose CSV…")
                                        implicitHeight: 40
                                        enabled: !ContentLab.csvBusy
                                        onClicked: csvDialog.open()
                                    }
                                    // selected-file chip
                                    Rectangle {
                                        visible: ContentLab.hasCsv
                                        Layout.fillWidth: true
                                        radius: Tokens.radiusMd
                                        color: Theme.surface_high
                                        border.width: 1
                                        border.color: Theme.outline_variant
                                        implicitHeight: chipRow.implicitHeight + Tokens.space3 * 2
                                        RowLayout {
                                            id: chipRow
                                            anchors.fill: parent
                                            anchors.margins: Tokens.space3
                                            spacing: Tokens.space2
                                            C.IconGlyph { name: "description"; size: 15; glyphColor: Theme.on_surface_var }
                                            C.AppText {
                                                text: ContentLab.csvName
                                                mono: true
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }

                                // status line
                                C.AppText {
                                    visible: ContentLab.csvStatus !== ""
                                    text: ContentLab.csvStatus
                                    font.pixelSize: Tokens.fontCaption
                                    color: ContentLab.csvStatusKind === "error" ? Theme.error
                                         : ContentLab.csvStatusKind === "warn" ? Theme.warn
                                         : ContentLab.csvStatusKind === "success" ? Theme.secondary_container
                                         : Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // ── optional: fold saved blueprints into the report ──
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: ContentLab.hasCsv
                            implicitHeight: bpCol.implicitHeight + Tokens.space5 * 2
                            ColumnLayout {
                                id: bpCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    C.IconGlyph { name: "auto_awesome"; size: 18; glyphColor: Theme.primary }
                                    C.AppText {
                                        text: I18n.tr("Combine with my blueprints")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontSubtitle
                                        color: Theme.text_strong
                                    }
                                    Rectangle {
                                        visible: ContentLab.selectedBlueprintCount > 0
                                        radius: Tokens.radiusPill
                                        color: Theme.primary
                                        implicitWidth: Math.max(22, bpSelLbl.implicitWidth + 12)
                                        implicitHeight: 22
                                        Layout.alignment: Qt.AlignVCenter
                                        C.AppText {
                                            id: bpSelLbl
                                            anchors.centerIn: parent
                                            text: I18n.tr("{n} picked").replace("{n}", ContentLab.selectedBlueprintCount)
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_primary
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        text: I18n.tr("Clear")
                                        iconName: "backspace"
                                        visible: ContentLab.selectedBlueprintCount > 0
                                        implicitHeight: 32
                                        onClicked: ContentLab.clearBlueprintSelection()
                                    }
                                }

                                C.AppText {
                                    text: I18n.tr("Optional — tick any saved blueprints to have the report sharpen them against this channel's real data.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                C.AppText {
                                    visible: !ContentLab.hasBlueprintChoices
                                    text: I18n.tr("No saved blueprints yet — generate some in AI Ideas first.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                // ── step 1: pick a keyword/channel ──
                                // The blueprints are grouped into the section they
                                // were generated in, so the user chooses the keyword
                                // first and then only that keyword's blueprints show.
                                C.AppText {
                                    visible: ContentLab.hasBlueprintChoices
                                    text: I18n.tr("PICK A KEYWORD / CHANNEL")
                                    mono: false
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: 11
                                    color: Theme.on_surface_var
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    visible: ContentLab.hasBlueprintChoices
                                    spacing: Tokens.space2

                                    // "All keywords" clears the section filter.
                                    AbstractButton {
                                        id: allKwChip
                                        height: 32
                                        implicitWidth: allKwRow.implicitWidth + Tokens.space4
                                        readonly property bool on: ContentLab.blueprintSectionId === -1
                                        onClicked: ContentLab.clearBlueprintSection()
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        background: Rectangle {
                                            radius: Tokens.radiusPill
                                            color: allKwChip.on ? U.withAlpha(Theme.primary, 0.14) : Theme.surface_low
                                            border.width: 1
                                            border.color: allKwChip.on ? Theme.primary : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        }
                                        // The Row is wrapped in a full-size Item and
                                        // centred THERE. `anchors.centerIn` on a
                                        // contentItem is unreliable — the Control owns
                                        // that item's geometry, so the Row ended up
                                        // pinned to the leading edge (see the same note
                                        // in PrimaryButton.qml).
                                        contentItem: Item {
                                            implicitWidth: allKwRow.implicitWidth
                                            implicitHeight: allKwRow.implicitHeight
                                            Row {
                                                id: allKwRow
                                                anchors.centerIn: parent
                                                spacing: Tokens.space1
                                                C.IconGlyph {
                                                    name: "apps"; size: 13
                                                    glyphColor: allKwChip.on ? Theme.primary : Theme.on_surface_var
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: I18n.tr("All keywords")
                                                    weight: Tokens.weightDemiBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: allKwChip.on ? Theme.primary : Theme.on_surface_var
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: ContentLab.blueprintSections
                                        AbstractButton {
                                            id: kwChip
                                            height: 32
                                            implicitWidth: kwChipRow.implicitWidth + Tokens.space4
                                            readonly property bool on: ContentLab.blueprintSectionId === modelData.id
                                            onClicked: ContentLab.pickBlueprintSection(modelData.id)
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            background: Rectangle {
                                                radius: Tokens.radiusPill
                                                color: kwChip.on ? U.withAlpha(Theme.primary, 0.14) : Theme.surface_low
                                                border.width: 1
                                                border.color: kwChip.on ? Theme.primary : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                implicitWidth: kwChipRow.implicitWidth
                                                implicitHeight: kwChipRow.implicitHeight
                                                Row {
                                                    id: kwChipRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space1
                                                    C.AppText {
                                                        text: modelData.title
                                                        weight: Tokens.weightDemiBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: kwChip.on ? Theme.primary : Theme.on_surface
                                                        elide: Text.ElideRight
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: "· " + modelData.count
                                                        mono: true
                                                        font.pixelSize: 11
                                                        color: Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── step 2: tick blueprints in the chosen keyword ──
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: ContentLab.hasBlueprintChoices
                                    spacing: Tokens.space2
                                    C.AppText {
                                        text: ContentLab.blueprintSectionId === -1
                                              ? I18n.tr("ALL BLUEPRINTS")
                                              : I18n.tr("BLUEPRINTS IN “{k}”").replace("{k}", ContentLab.blueprintSectionTitle)
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: 11
                                        color: Theme.on_surface_var
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        text: I18n.tr("Select all here")
                                        iconName: "done_all"
                                        visible: ContentLab.blueprintChoices.length > 0
                                        implicitHeight: 30
                                        onClicked: ContentLab.selectAllInSection()
                                    }
                                }

                                // checkbox list of the scoped saved blueprints
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: ContentLab.hasBlueprintChoices
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: ContentLab.blueprintChoices
                                        AbstractButton {
                                            id: bpItem
                                            Layout.fillWidth: true
                                            implicitHeight: bpItemRow.implicitHeight + Tokens.space3 * 2
                                            readonly property bool picked:
                                                ContentLab.selectedBlueprintIds.indexOf(modelData.id) !== -1
                                            onClicked: ContentLab.toggleBlueprint(modelData.id)
                                            background: Rectangle {
                                                MouseArea {
                                                    id: bpItemHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton
                                                    cursorShape: Qt.PointingHandCursor
                                                }
                                                radius: Tokens.radiusMd
                                                color: bpItem.picked ? U.withAlpha(Theme.primary, 0.10)
                                                     : bpItemHover.containsMouse
                                                       ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                       : Theme.surface_low
                                                border.width: 1
                                                border.color: bpItem.picked ? Theme.primary : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: RowLayout {
                                                id: bpItemRow
                                                spacing: Tokens.space3
                                                // check box
                                                Rectangle {
                                                    width: 22; height: 22; radius: Tokens.radiusSm
                                                    Layout.leftMargin: Tokens.space3
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: bpItem.picked ? Theme.primary : "transparent"
                                                    border.width: 1
                                                    border.color: bpItem.picked ? Theme.primary : Theme.outline
                                                    C.IconGlyph {
                                                        anchors.centerIn: parent
                                                        visible: bpItem.picked
                                                        name: "check"; size: 14
                                                        glyphColor: Theme.on_primary
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: Tokens.space3
                                                    Layout.bottomMargin: Tokens.space3
                                                    spacing: 1
                                                    C.AppText {
                                                        text: modelData.title
                                                        weight: Tokens.weightDemiBold
                                                        color: Theme.text_strong
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    C.AppText {
                                                        text: modelData.sectionTitle
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_surface_var
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                // format tag
                                                Rectangle {
                                                    radius: Tokens.radiusPill
                                                    Layout.rightMargin: Tokens.space3
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: U.withAlpha(Theme.outline, 0.14)
                                                    implicitWidth: bpTag.implicitWidth + Tokens.space3
                                                    implicitHeight: 20
                                                    C.AppText {
                                                        id: bpTag
                                                        anchors.centerIn: parent
                                                        text: modelData.isLong ? I18n.tr("LONG") : I18n.tr("SHORT")
                                                        mono: false
                                                        weight: Tokens.weightDemiBold
                                                        font.pixelSize: 10
                                                        color: Theme.on_surface_var
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── optional: fold saved research briefs into the report ──
                        // Separate from the blueprint picker above, because the two
                        // are different KINDS of evidence and the report is told so:
                        // a blueprint is what this creator intends to make, a brief
                        // is what the wider niche's search demand looks like (read
                        // from other people's videos). Merging them into one list
                        // would erase that distinction in the UI just as surely as
                        // dropping the labels would erase it in the prompt.
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: ContentLab.hasCsv
                            implicitHeight: brCol.implicitHeight + Tokens.space5 * 2
                            ColumnLayout {
                                id: brCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: "nav_insights"; size: 17
                                        glyphColor: Theme.primary
                                    }
                                    C.AppText {
                                        text: I18n.tr("Combine with my research")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontSubtitle
                                        color: Theme.text_strong
                                    }
                                    Rectangle {
                                        radius: Tokens.radiusPill
                                        visible: ContentLab.selectedBriefCount > 0
                                        color: Theme.primary
                                        implicitWidth: Math.max(22, brSelLbl.implicitWidth + 12)
                                        implicitHeight: 22
                                        Layout.alignment: Qt.AlignVCenter
                                        C.AppText {
                                            id: brSelLbl
                                            anchors.centerIn: parent
                                            text: I18n.tr("{n} picked").replace("{n}", ContentLab.selectedBriefCount)
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: 11
                                            color: Theme.on_primary
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: "backspace"
                                        text: I18n.tr("Clear")
                                        visible: ContentLab.selectedBriefCount > 0
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: ContentLab.clearBriefSelection()
                                    }
                                }

                                C.AppText {
                                    Layout.fillWidth: true
                                    text: I18n.tr("Optional — a saved snapshot is research about the niche, not about this channel. A DATA row carries the measured aggregates (median vs average, momentum, length and recency mix, channel concentration); a RESEARCH row adds the written brief on top, every statement keeping its label (observed / inferred / needs Studio). The report is told the channel's own numbers win where the two disagree.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                }

                                // empty state → the page that produces briefs
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: !ContentLab.hasBriefChoices
                                    spacing: Tokens.space3
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("No saved research yet — analyze a search in Niche Scan and press “Generate brief”.")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        wrapMode: Text.Wrap
                                    }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: "nav_insights"
                                        text: I18n.tr("Go to Niche Scan")
                                        onClicked: App.goto(11)   // PAGE_INSIGHTS
                                    }
                                }

                                // checkbox list of saved briefs, newest first
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: ContentLab.hasBriefChoices
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: ContentLab.briefChoices
                                        AbstractButton {
                                            id: brItem
                                            Layout.fillWidth: true
                                            implicitHeight: brItemRow.implicitHeight + Tokens.space3 * 2
                                            readonly property bool picked:
                                                ContentLab.selectedBriefKeys.indexOf(modelData.key) !== -1
                                            onClicked: ContentLab.toggleBrief(modelData.key)
                                            background: Rectangle {
                                                MouseArea {
                                                    id: brItemHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton
                                                    cursorShape: Qt.PointingHandCursor
                                                }
                                                radius: Tokens.radiusMd
                                                color: brItem.picked ? U.withAlpha(Theme.primary, 0.10)
                                                     : brItemHover.containsMouse
                                                       ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                       : Theme.surface_low
                                                border.width: 1
                                                border.color: brItem.picked ? Theme.primary : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: RowLayout {
                                                id: brItemRow
                                                spacing: Tokens.space3
                                                Rectangle {
                                                    width: 18; height: 18
                                                    radius: Tokens.radiusSm
                                                    Layout.leftMargin: Tokens.space3
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: brItem.picked ? Theme.primary : "transparent"
                                                    border.width: 1
                                                    border.color: brItem.picked ? Theme.primary : Theme.outline
                                                    C.IconGlyph {
                                                        anchors.centerIn: parent
                                                        visible: brItem.picked
                                                        name: "check"; size: 12
                                                        glyphColor: Theme.on_primary
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: Tokens.space3
                                                    Layout.bottomMargin: Tokens.space3
                                                    spacing: 1
                                                    C.AppText {
                                                        text: modelData.query
                                                        weight: Tokens.weightDemiBold
                                                        color: Theme.text_strong
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    C.AppText {
                                                        text: I18n.tr("{n} videos · {t}")
                                                            .replace("{n}", modelData.videos)
                                                            .replace("{t}", modelData.when)
                                                        mono: true
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_surface_var
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                Rectangle {
                                                    radius: Tokens.radiusPill
                                                    Layout.rightMargin: Tokens.space3
                                                    Layout.alignment: Qt.AlignVCenter
                                                    // A row carrying a written brief is tinted with the
                                                    // brand accent; a numbers-only snapshot stays neutral,
                                                    // so the two kinds are distinguishable at a glance
                                                    // without reading the word.
                                                    color: modelData.hasBrief
                                                           ? U.withAlpha(Theme.primary, 0.14)
                                                           : U.withAlpha(Theme.outline, 0.14)
                                                    implicitWidth: brTag.implicitWidth + Tokens.space3
                                                    implicitHeight: 20
                                                    C.AppText {
                                                        id: brTag
                                                        anchors.centerIn: parent
                                                        text: modelData.kind
                                                        mono: true
                                                        weight: Tokens.weightDemiBold
                                                        font.pixelSize: 10
                                                        color: modelData.hasBrief ? Theme.primary
                                                                                  : Theme.on_surface_var
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── v11 launch bar: what this run will include, and the button ──
                        C.GlassPanel {
                            id: launchBar
                            Layout.fillWidth: true
                            radius: Tokens.radiusXl
                            readonly property bool ready: ContentLab.hasCsv && ContentLab.hasAiKey && !ContentLab.csvBusy
                            implicitHeight: launchRow.implicitHeight + Tokens.space4 * 2
                            border.color: ready ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                            Rectangle {
                                anchors.fill: parent
                                radius: launchBar.radius
                                opacity: launchBar.ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.07) }
                                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                                }
                            }

                            RowLayout {
                                id: launchRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.space5
                                anchors.rightMargin: Tokens.space4
                                spacing: Tokens.space4

                                C.IconTile {
                                    iconName: ContentLab.csvBusy ? "autorenew" : "auto_awesome"
                                    size: 46
                                    glyphSize: 22
                                    solid: launchBar.ready || ContentLab.csvBusy
                                    lit: launchBar.ready
                                    breathe: launchBar.ready
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    C.AppText {
                                        text: ContentLab.csvBusy ? I18n.tr("Report in progress")
                                              : !ContentLab.hasAiKey ? I18n.tr("Add an AI key to build reports")
                                              : !ContentLab.hasCsv ? I18n.tr("Pick an export to start")
                                              : I18n.tr("Ready to build")
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Tokens.fontSubtitle
                                        color: Theme.text_strong
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    // what goes in — named, so the run is never a surprise
                                    Flow {
                                        Layout.fillWidth: true
                                        visible: ContentLab.hasCsv
                                        spacing: Tokens.space2
                                        Repeater {
                                            model: [
                                                { g: "description", v: ContentLab.csvName, on: true },
                                                { g: "auto_awesome", on: ContentLab.selectedBlueprintCount > 0,
                                                  v: I18n.tr("{n} blueprint(s)").replace("{n}", ContentLab.selectedBlueprintCount) },
                                                { g: "page_insights", on: ContentLab.selectedBriefCount > 0,
                                                  v: I18n.tr("{n} research brief(s)").replace("{n}", ContentLab.selectedBriefCount) }
                                            ]
                                            Rectangle {
                                                visible: modelData.on
                                                radius: Tokens.radiusPill
                                                color: U.withAlpha(Theme.surface_high, 0.85)
                                                border.width: 1
                                                border.color: Theme.border
                                                implicitWidth: Math.min(320, inRow.implicitWidth + Tokens.space4)
                                                implicitHeight: 26
                                                Row {
                                                    id: inRow
                                                    anchors.centerIn: parent
                                                    spacing: 5
                                                    C.IconGlyph {
                                                        name: modelData.g; size: 13
                                                        glyphColor: Theme.primary
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: modelData.v
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_surface
                                                        width: Math.min(implicitWidth, 280)
                                                        elide: Text.ElideMiddle
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                C.PrimaryButton {
                                    variant: "ghost"
                                    iconName: "open_in_new"
                                    text: I18n.tr("Open report")
                                    visible: ContentLab.hasCsvReport && !ContentLab.csvBusy
                                    implicitHeight: 50
                                    onClicked: ContentLab.openCsvReport()
                                }
                                C.PrimaryButton {
                                    iconName: "auto_awesome"
                                    // Four states, because the button is the only place
                                    // that says what this run will actually include.
                                    text: ContentLab.csvBusy ? I18n.tr("Analyzing …")
                                          : (ContentLab.selectedBlueprintCount > 0
                                             && ContentLab.selectedBriefCount > 0)
                                            ? I18n.tr("Analyze + blueprints + research")
                                          : ContentLab.selectedBriefCount > 0
                                            ? I18n.tr("Analyze + combine research")
                                          : ContentLab.selectedBlueprintCount > 0
                                            ? I18n.tr("Analyze + combine blueprints")
                                          : I18n.tr("Analyze channel")
                                    enabled: launchBar.ready
                                    indeterminate: ContentLab.csvBusy
                                    implicitHeight: 50
                                    onClicked: ContentLab.analyzeCsv()
                                }
                            }
                        }

                        // busy panel — the meter reads a signal while the run goes
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: ContentLab.csvBusy
                            radius: Tokens.radiusXl
                            clip: true
                            implicitHeight: csvBusyCol.implicitHeight + Tokens.space5 * 2
                            C.CornerGlow { radius: Tokens.radiusXl; size: 420 }
                            ColumnLayout {
                                id: csvBusyCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space5
                                    C.PulseBars {
                                        Layout.preferredWidth: 150
                                        Layout.preferredHeight: 48
                                        bars: 12
                                        gap: 4
                                        mode: "busy"
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        C.AppText {
                                            text: I18n.tr("Building your channel report — this can take a few minutes. You can leave the page; the run continues.")
                                            color: Theme.text_strong
                                            weight: Tokens.weightBold
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }
                                        C.AppText {
                                            visible: ContentLab.csvStatus !== ""
                                            text: ContentLab.csvStatus
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.primary
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 4
                                    radius: 2
                                    color: U.withAlpha(Theme.outline, 0.18)
                                    clip: true
                                    Rectangle {
                                        id: csvSweep
                                        width: parent.width * 0.3
                                        height: parent.height
                                        radius: 2
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                                            GradientStop { position: 0.6; color: Theme.primary }
                                            GradientStop { position: 1.0; color: Theme.primary_hover }
                                        }
                                        SequentialAnimation on x {
                                            running: ContentLab.csvBusy && csvSweep.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { from: -csvSweep.width; to: csvSweep.parent.width; duration: 1400; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }
                        }
                        // ── produced reports history ──
                        // The cache only ever remembers the LATEST report per export,
                        // so without this list an earlier run is unreachable. Every
                        // entry says which export it came from, whether blueprints
                        // were folded in (and which), and when it was built.
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: ContentLab.hasReports && !ContentLab.csvBusy
                            implicitHeight: repCol.implicitHeight + Tokens.space5 * 2

                            ColumnLayout {
                                id: repCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    C.IconGlyph { name: "history"; size: 18; glyphColor: Theme.primary }
                                    C.AppText {
                                        text: I18n.tr("Reports you have built")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontSubtitle
                                        color: Theme.text_strong
                                    }
                                    Item { Layout.fillWidth: true }
                                    C.AppText {
                                        visible: ContentLab.hasCsv && ContentLab.reportCountForPicked > 0
                                        text: I18n.tr("{n} for this file").replace(
                                            "{n}", ContentLab.reportCountForPicked)
                                        mono: true
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                    }
                                    C.IconButton {
                                        iconName: "refresh"
                                        accent: Theme.primary
                                        tip: I18n.tr("Reload the list")
                                        onClicked: ContentLab.refreshReports()
                                    }
                                }
                                C.AppText {
                                    text: I18n.tr("Every report still on disk, newest first. Open one to read it again — no AI call, no quota.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Repeater {
                                    model: ContentLab.reports
                                    Rectangle {
                                        id: repRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        radius: Tokens.radiusMd
                                        // Reports built from the export currently
                                        // picked are tinted, so "mine, for this file"
                                        // reads at a glance.
                                        color: modelData.isForPicked
                                               ? U.withAlpha(Theme.primary, 0.06)
                                               : Theme.surface_low
                                        border.width: 1
                                        border.color: modelData.isForPicked
                                                      ? U.withAlpha(Theme.primary, 0.28)
                                                      : Theme.border
                                        implicitHeight: repRowCol.implicitHeight + Tokens.space4 * 2

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: Tokens.space4
                                            spacing: Tokens.space3

                                            // kind tile: plain channel vs combined
                                            Rectangle {
                                                width: 38; height: 38; radius: Tokens.radiusSm
                                                Layout.alignment: Qt.AlignTop
                                                color: U.withAlpha(
                                                    repRow.modelData.isCombined ? Theme.primary
                                                                                : Theme.secondary_container, 0.14)
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    name: repRow.modelData.isCombined ? "auto_awesome" : "insights"
                                                    size: 18
                                                    glyphColor: repRow.modelData.isCombined
                                                                ? Theme.primary : Theme.secondary_container
                                                }
                                            }

                                            ColumnLayout {
                                                id: repRowCol
                                                Layout.fillWidth: true
                                                spacing: 2
                                                // source export + kind tag
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Tokens.space2
                                                    C.AppText {
                                                        text: repRow.modelData.sourceName
                                                        weight: Tokens.weightBold
                                                        color: Theme.text_strong
                                                        elide: Text.ElideMiddle
                                                        Layout.fillWidth: true
                                                    }
                                                    Rectangle {
                                                        radius: Tokens.radiusPill
                                                        color: U.withAlpha(
                                                            repRow.modelData.isCombined ? Theme.primary
                                                                                        : Theme.outline, 0.14)
                                                        implicitWidth: kindLbl.implicitWidth + Tokens.space3
                                                        implicitHeight: 20
                                                        C.AppText {
                                                            id: kindLbl
                                                            anchors.centerIn: parent
                                                            text: repRow.modelData.kindLabel
                                                            mono: true
                                                            weight: Tokens.weightDemiBold
                                                            font.pixelSize: 10
                                                            color: repRow.modelData.isCombined
                                                                   ? Theme.primary : Theme.on_surface_var
                                                        }
                                                    }
                                                }
                                                // which blueprints were folded in
                                                C.AppText {
                                                    visible: repRow.modelData.blueprintCount > 0
                                                    text: I18n.tr("{n} blueprint(s): {list}")
                                                        .replace("{n}", repRow.modelData.blueprintCount)
                                                        .replace("{list}", repRow.modelData.blueprintSummary)
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.on_surface_var
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                                // ...and which research. Named, not
                                                // just counted: two reports off the
                                                // same export differ by exactly this.
                                                C.AppText {
                                                    visible: repRow.modelData.briefCount > 0
                                                    text: I18n.tr("{n} brief(s): {list}")
                                                        .replace("{n}", repRow.modelData.briefCount)
                                                        .replace("{list}", repRow.modelData.briefSummary)
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.on_surface_var
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                                // provider · videos · watched · when
                                                C.AppText {
                                                    text: {
                                                        var bits = []
                                                        if (repRow.modelData.provider) bits.push(repRow.modelData.provider)
                                                        if (repRow.modelData.videoCount > 0)
                                                            bits.push(I18n.tr("{n} videos").replace("{n}", repRow.modelData.videoCount))
                                                        if (repRow.modelData.watched > 0)
                                                            bits.push(I18n.tr("{n} watched").replace("{n}", repRow.modelData.watched))
                                                        if (repRow.modelData.createdAt) bits.push(repRow.modelData.createdAt)
                                                        return bits.join("  ·  ")
                                                    }
                                                    mono: true
                                                    font.pixelSize: 11
                                                    color: Theme.outline
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            C.PrimaryButton {
                                                variant: "ghost"
                                                iconName: "open_in_new"
                                                text: I18n.tr("Open")
                                                implicitHeight: 36
                                                Layout.alignment: Qt.AlignVCenter
                                                onClicked: ContentLab.openReport(repRow.modelData.htmlPath)
                                            }
                                            C.IconButton {
                                                iconName: "folder_open"
                                                accent: Theme.on_surface_var
                                                Layout.alignment: Qt.AlignVCenter
                                                tip: I18n.tr("Show in folder")
                                                onClicked: ContentLab.revealReport(repRow.modelData.htmlPath)
                                            }
                                            C.IconButton {
                                                iconName: "delete"
                                                accent: Theme.error
                                                Layout.alignment: Qt.AlignVCenter
                                                tip: I18n.tr("Delete this report")
                                                onClicked: {
                                                    confirmDeleteReport.path = repRow.modelData.htmlPath
                                                    confirmDeleteReport.label = repRow.modelData.sourceName
                                                    confirmDeleteReport.open()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ TELEPROMPTER TAB ═══
                    // The former Script Studio page, moved here whole: a picker and
                    // the prompter, nothing else. Everything else about a blueprint
                    // already has a home in BlueprintPane, and repeating it on the
                    // one screen you look at while recording would turn it into
                    // another dashboard.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: ContentLab.tab === 1
                        spacing: Tokens.space4

                        // ── v11 "on air" cover ──
                        // A studio sign, not a heading: the lamp is lit when a
                        // script is loaded, the title is the script you are about
                        // to read, and the waveform is the SHAPE of that script —
                        // one bar per beat, height = words — so a dense monologue
                        // and a punchy Short look different at a glance.
                        C.GlassPanel {
                            id: airDeck
                            Layout.fillWidth: true
                            radius: Tokens.radiusXl
                            clip: true
                            elevation: 1.3
                            implicitHeight: airCol.implicitHeight + Tokens.space6 * 2
                            readonly property bool live: Studio.hasScript
                            readonly property color lamp: live ? Theme.error : Theme.outline

                            Rectangle {
                                anchors.fill: parent
                                radius: airDeck.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(airDeck.lamp, airDeck.live ? (Theme.isDark ? 0.13 : 0.07) : 0.03) }
                                    GradientStop { position: 0.6; color: U.withAlpha(airDeck.lamp, 0.0) }
                                }
                            }
                            C.CornerGlow { radius: airDeck.radius; size: 480 }

                            ColumnLayout {
                                id: airCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.space6
                                spacing: Tokens.space4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space5

                                    // the on-air lamp
                                    Item {
                                        implicitWidth: 72; implicitHeight: 72
                                        Layout.alignment: Qt.AlignTop
                                        Rectangle {
                                            id: lampHalo
                                            anchors.centerIn: parent
                                            width: 72; height: 72; radius: 36
                                            color: U.withAlpha(airDeck.lamp, 0.16)
                                            SequentialAnimation on scale {
                                                running: airDeck.live && page.visible && Tokens.appActive
                                                loops: Animation.Infinite
                                                NumberAnimation { from: 0.82; to: 1.08; duration: 1100; easing.type: Easing.OutCubic }
                                                NumberAnimation { from: 1.08; to: 0.82; duration: 1100; easing.type: Easing.InOutSine }
                                            }
                                        }
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 50; height: 50; radius: 25
                                            antialiasing: true
                                            color: airDeck.live ? airDeck.lamp : Theme.surface_high
                                            border.width: 1
                                            border.color: U.withAlpha(airDeck.lamp, 0.5)
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: "nav_studio"
                                                fill: true
                                                size: 22
                                                glyphColor: airDeck.live ? "#ffffff" : Theme.on_surface_var
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space1
                                        RowLayout {
                                            spacing: Tokens.space2
                                            Rectangle {
                                                radius: Tokens.radiusXs
                                                color: airDeck.live ? airDeck.lamp : "transparent"
                                                border.width: 1
                                                border.color: airDeck.lamp
                                                implicitWidth: onAirLbl.implicitWidth + Tokens.space3
                                                implicitHeight: 22
                                                C.AppText {
                                                    id: onAirLbl
                                                    anchors.centerIn: parent
                                                    text: airDeck.live ? I18n.tr("ON AIR") : I18n.tr("STANDBY")
                                                    mono: true
                                                    weight: Tokens.weightExtraBold
                                                    font.pixelSize: 11
                                                    color: airDeck.live ? "#ffffff" : airDeck.lamp
                                                }
                                            }
                                            C.AppText {
                                                text: I18n.tr("TELEPROMPTER")
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: 11
                                                color: Theme.on_surface_var
                                            }
                                        }
                                        C.AppText {
                                            text: airDeck.live ? (Studio.idea.title || I18n.tr("Script loaded"))
                                                               : I18n.tr("Pick a script, then press play")
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontDisplay + 4
                                            color: Theme.text_strong
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        // the numbers you check between takes
                                        Flow {
                                            Layout.fillWidth: true
                                            Layout.topMargin: Tokens.space1
                                            visible: airDeck.live
                                            spacing: Tokens.space2
                                            Repeater {
                                                model: [
                                                    { g: "layout_list", v: I18n.tr("{n} beats").replace("{n}", Studio.beatCount) },
                                                    { g: "text",        v: I18n.tr("{n} words").replace("{n}", Studio.wordCount) },
                                                    { g: "speed",       v: Studio.estimatedText + "  @ " + Studio.wpm + " wpm" },
                                                    { g: "target",      v: Studio.targetText !== "" ? I18n.tr("planned {t}").replace("{t}", Studio.targetText) : "" },
                                                    { g: "info",        v: Studio.paceVerdict }
                                                ]
                                                Rectangle {
                                                    visible: (modelData.v || "") !== ""
                                                    radius: Tokens.radiusPill
                                                    color: U.withAlpha(Theme.surface_high, 0.85)
                                                    border.width: 1
                                                    border.color: Theme.border
                                                    implicitWidth: airChip.implicitWidth + Tokens.space4
                                                    implicitHeight: 28
                                                    Row {
                                                        id: airChip
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        C.IconGlyph {
                                                            name: modelData.g; size: 13
                                                            glyphColor: Theme.primary
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        C.AppText {
                                                            text: modelData.v || ""
                                                            mono: modelData.g === "speed"
                                                            font.pixelSize: Tokens.fontCaption
                                                            weight: Tokens.weightDemiBold
                                                            color: Theme.on_surface
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // the script waveform — one bar per beat
                                Item {
                                    id: wave
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    visible: airDeck.live && (Studio.beats || []).length > 0
                                    readonly property int n: (Studio.beats || []).length
                                    readonly property real gap: n > 40 ? 2 : 4
                                    readonly property real bw: n > 0 ? Math.max(2, (width - gap * (n - 1)) / n) : 0
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 1
                                        color: U.withAlpha(Theme.outline, 0.25)
                                    }
                                    Row {
                                        anchors.fill: parent
                                        spacing: wave.gap
                                        LayoutMirroring.enabled: false
                                        Repeater {
                                            model: Studio.beats
                                            Item {
                                                width: wave.bw
                                                height: wave.height
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: Math.max(4, parent.height * (modelData.isDirection ? 0.12
                                                                     : Math.max(0.14, (modelData.words || 0) / page._maxBeatWords)))
                                                    radius: Math.min(3, width / 2)
                                                    color: modelData.isDirection ? U.withAlpha(Theme.outline, 0.45)
                                                                                 : U.withAlpha(Theme.primary, 0.35 + 0.65 * (index / Math.max(1, wave.n - 1)))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── unsaved-edit warning ──
                        // A strip, not a toast: it has to still be true and still
                        // visible ten minutes into a take.
                        Rectangle {
                            Layout.fillWidth: false
                            radius: Tokens.radiusPill
                            visible: Studio.dirty
                            color: U.withAlpha(Theme.warn, 0.14)
                            border.width: 1
                            border.color: U.withAlpha(Theme.warn, 0.4)
                            implicitWidth: dirtyRow.implicitWidth + Tokens.space4
                            implicitHeight: 34
                            Row {
                                id: dirtyRow
                                anchors.centerIn: parent
                                spacing: Tokens.space2
                                C.IconGlyph {
                                    name: "edit"; size: 14; glyphColor: Theme.warn
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                C.AppText {
                                    text: I18n.tr("Unsaved script edits")
                                    mono: false
                                    font.pixelSize: Tokens.fontCaption
                                    weight: Tokens.weightDemiBold
                                    color: Theme.warn
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // ── empty state: nothing in the library has a script yet ──
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: !Studio.hasChoices && !Studio.hasScript
                            implicitHeight: promptEmptyCol.implicitHeight + Tokens.space8 * 2
                            ColumnLayout {
                                id: promptEmptyCol
                                anchors.centerIn: parent
                                width: Math.min(520, parent.width - Tokens.space7 * 2)
                                spacing: Tokens.space3
                                C.IconGlyph {
                                    name: "nav_studio"; size: 42
                                    glyphColor: U.withAlpha(Theme.primary, 0.55)
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                C.AppText {
                                    text: I18n.tr("No scripts saved yet")
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontSubtitle
                                    color: Theme.text_strong
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    text: I18n.tr("Generate blueprints on the AI Ideas page — each one comes with a timecoded, camera-ready script, and every script shows up here.")
                                    color: Theme.on_surface_var
                                }
                                C.PrimaryButton {
                                    variant: "ghost"
                                    iconName: "lightbulb"
                                    text: I18n.tr("Generate a blueprint")
                                    Layout.alignment: Qt.AlignHCenter
                                    onClicked: App.goto(6)   // PAGE_AI_IDEAS
                                }
                            }
                        }

                        // ── picker ──
                        // Section chips first, then the blueprints inside it: the
                        // same two-step narrowing the combine picker above uses, for
                        // the same reason — a flat list of 60 blueprints is unusable.
                        C.Panel {
                            Layout.fillWidth: true
                            visible: Studio.hasChoices
                            eyebrow: I18n.tr("CHOOSE A SCRIPT")
                            eyebrowIcon: "subject"
                            content: [
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space3

                                    C.LineField {
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 360
                                        label: I18n.tr("Find a blueprint")
                                        labelIcon: "search"
                                        placeholder: I18n.tr("Search by title")
                                        text: Studio.search
                                        onTextChanged: Studio.search = text
                                    }
                                    ColumnLayout {
                                        C.AppText { text: " "; font.pixelSize: Tokens.fontCaption }
                                        C.AppText {
                                            text: I18n.tr("{n} scripts").replace("{n}", Studio.choices.length)
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                },

                                // section chips
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: Studio.sections
                                        AbstractButton {
                                            height: 32
                                            width: promptChipRow.implicitWidth + Tokens.space5
                                            readonly property bool isOn: Studio.sectionId === modelData.id
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            onClicked: Studio.pickSection(modelData.id)
                                            background: Rectangle {
                                                radius: Tokens.radiusPill
                                                color: parent.isOn ? U.withAlpha(Theme.primary, 0.14)
                                                     : parent.hovered
                                                       ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                       : Theme.surface_low
                                                border.width: 1
                                                border.color: parent.isOn ? U.withAlpha(Theme.primary, 0.4)
                                                                          : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                implicitWidth: promptChipRow.implicitWidth
                                                Row {
                                                    id: promptChipRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space2
                                                    C.AppText {
                                                        text: modelData.title
                                                        weight: Tokens.weightDemiBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: parent.parent.parent.isOn ? Theme.primary
                                                                                         : Theme.on_surface
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: modelData.count
                                                        mono: true
                                                        font.pixelSize: 11
                                                        color: Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                },

                                // blueprint rows
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space3
                                    Repeater {
                                        model: Studio.choices
                                        C.GlassPanel {
                                            id: choiceCard
                                            width: 306
                                            implicitHeight: choiceCol.implicitHeight + Tokens.space4 * 2
                                            radius_: Tokens.radiusLg
                                            readonly property bool isOpen: Studio.ideaId === modelData.id
                                            readonly property color fmtTint: modelData.format === "long"
                                                                             ? Theme.secondary_container : Theme.primary
                                            border.color: isOpen ? U.withAlpha(Theme.primary, 0.65)
                                                                 : choiceHover.hovered ? U.withAlpha(Theme.primary, 0.32)
                                                                 : Theme.border
                                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            HoverHandler { id: choiceHover; cursorShape: Qt.PointingHandCursor }
                                            elevation: choiceHover.hovered || isOpen ? 1.7 : 1.0
                                            Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
                                            TapHandler { onTapped: Studio.openBlueprint(modelData.id) }
                                            transform: Translate {
                                                y: choiceHover.hovered && !choiceCard.isOpen ? -3 : 0
                                                Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                            }

                                            // loaded = lit
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: choiceCard.radius
                                                opacity: choiceCard.isOpen ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.18 : 0.10) }
                                                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                                                }
                                            }
                                            // a format-coloured edge along the top
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.leftMargin: choiceCard.radius
                                                anchors.rightMargin: choiceCard.radius
                                                height: 2
                                                color: choiceCard.fmtTint
                                                opacity: choiceCard.isOpen || choiceHover.hovered ? 0.9 : 0.35
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                            }

                                            ColumnLayout {
                                                id: choiceCol
                                                anchors.fill: parent
                                                anchors.margins: Tokens.space4
                                                spacing: Tokens.space2

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Tokens.space2
                                                    // Format matters before you press
                                                    // play: a Shorts script and a
                                                    // 12-minute one are different jobs
                                                    // on the same rig.
                                                    Rectangle {
                                                        radius: Tokens.radiusPill
                                                        implicitWidth: promptFmtRow.implicitWidth + Tokens.space3
                                                        implicitHeight: 22
                                                        color: U.withAlpha(choiceCard.fmtTint, 0.16)
                                                        Row {
                                                            id: promptFmtRow
                                                            anchors.centerIn: parent
                                                            spacing: 4
                                                            C.IconGlyph {
                                                                name: modelData.format === "long" ? "fmt_long" : "fmt_short"
                                                                size: 12
                                                                glyphColor: choiceCard.fmtTint
                                                                anchors.verticalCenter: parent.verticalCenter
                                                            }
                                                            C.AppText {
                                                                id: promptFmtLbl
                                                                text: modelData.formatLabel
                                                                mono: true
                                                                font.pixelSize: 11
                                                                weight: Tokens.weightBold
                                                                color: choiceCard.fmtTint
                                                                anchors.verticalCenter: parent.verticalCenter
                                                            }
                                                        }
                                                    }
                                                    // loaded marker
                                                    Row {
                                                        visible: choiceCard.isOpen
                                                        spacing: 5
                                                        Rectangle {
                                                            width: 7; height: 7; radius: 3.5
                                                            color: Theme.error
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            SequentialAnimation on opacity {
                                                                running: choiceCard.isOpen && page.visible && Tokens.appActive
                                                                loops: Animation.Infinite
                                                                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                                                                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                                                            }
                                                        }
                                                        C.AppText {
                                                            text: I18n.tr("ON AIR")
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: 11
                                                            color: Theme.error
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    C.IconGlyph {
                                                        name: "star"; fill: true; size: 13
                                                        glyphColor: Theme.warn
                                                        visible: modelData.isFavorite
                                                    }
                                                    // play disc — appears on hover, stays lit when loaded
                                                    Rectangle {
                                                        width: 30; height: 30; radius: 15
                                                        color: choiceCard.isOpen || choiceHover.hovered ? Theme.primary
                                                                                                        : U.withAlpha(Theme.primary, 0.10)
                                                        scale: choiceHover.hovered ? 1.08 : 1.0
                                                        Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                        C.IconGlyph {
                                                            anchors.centerIn: parent
                                                            name: "play_arrow"; fill: true; size: 16
                                                            glyphColor: choiceCard.isOpen || choiceHover.hovered ? Theme.on_primary : Theme.primary
                                                        }
                                                    }
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: modelData.title
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontLabel
                                                    color: choiceCard.isOpen ? Theme.primary : Theme.text_strong
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Tokens.space3
                                                    C.AppText {
                                                        text: I18n.tr("{n} beats").replace("{n}", modelData.beats)
                                                        mono: true
                                                        font.pixelSize: 11
                                                        color: Theme.on_surface_var
                                                    }
                                                    C.AppText {
                                                        text: "~" + page.mmss(modelData.words)
                                                        mono: true
                                                        weight: Tokens.weightBold
                                                        font.pixelSize: 11
                                                        color: Theme.on_surface
                                                        LayoutMirroring.enabled: false
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    C.AppText {
                                                        text: modelData.sectionTitle
                                                        font.pixelSize: 11
                                                        color: Theme.on_surface_var
                                                        elide: Text.ElideRight
                                                        Layout.maximumWidth: 120
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            ]
                        }

                        // ── the prompter ──
                        // Sized to the window rather than its content: the reading
                        // column scrolls itself, and a prompter that grows the page's
                        // scrollbar is a prompter you can't read.
                        C.Teleprompter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(520, page.height - 300)
                            visible: Studio.hasScript
                        }
                    }
                }
            }
        }
    }

    // Deleting a blueprint removes it from the database, not just the view, so
    // it asks. Cloned from the AI Ideas page's confirmDelete.
    Dialog {
        id: confirmDelete
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(440, page.width - 80)
        padding: 0
        title: I18n.tr("Delete this blueprint?")

        property int pendingId: -1
        property string pendingTitle: ""
        function ask(ideaId) {
            pendingId = ideaId
            var hit = null
            var list = ContentLab.ideas
            for (var i = 0; i < list.length; i++)
                if (list[i].id === ideaId) { hit = list[i]; break }
            pendingTitle = hit ? (hit.title || "") : ""
            open()
        }

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
            implicitHeight: delHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: delHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "delete_outline"; size: 20
                        glyphColor: Theme.error
                    }
                }
                C.AppText {
                    text: confirmDelete.title
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: ColumnLayout {
            spacing: Tokens.space2
            C.AppText {
                text: confirmDelete.pendingTitle
                visible: text !== ""
                weight: Tokens.weightDemiBold
                color: Theme.on_surface
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
            }
            C.AppText {
                text: I18n.tr("It will be removed from your Content Lab library for good. This cannot be undone.")
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                Layout.bottomMargin: Tokens.space2
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
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    text: I18n.tr("Cancel")
                    onClicked: confirmDelete.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete_outline"
                    text: I18n.tr("Delete")
                    onClicked: {
                        ContentLab.deleteIdea(confirmDelete.pendingId)
                        confirmDelete.close()
                    }
                }
            }
        }
    }

    // Deleting a whole section drops every blueprint in it — a bigger,
    // separately-confirmed action.
    Dialog {
        id: confirmDeleteEntry
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, page.width - 80)
        padding: 0
        title: I18n.tr("Delete this section?")

        property int pendingId: -1
        property string pendingTitle: ""
        property int pendingCount: 0
        function ask(entryId, title, count) {
            pendingId = entryId
            pendingTitle = title || ""
            pendingCount = count || 0
            open()
        }

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
            implicitHeight: delEntryHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: delEntryHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "delete_outline"; size: 20
                        glyphColor: Theme.error
                    }
                }
                C.AppText {
                    text: confirmDeleteEntry.title
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: ColumnLayout {
            spacing: Tokens.space2
            C.AppText {
                text: I18n.tr("Delete “{t}” and all {n} idea(s) in it? This can't be undone.")
                          .replace("{t}", confirmDeleteEntry.pendingTitle)
                          .replace("{n}", confirmDeleteEntry.pendingCount)
                color: Theme.on_surface
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.space5
                Layout.rightMargin: Tokens.space5
                Layout.bottomMargin: Tokens.space2
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
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    text: I18n.tr("Cancel")
                    onClicked: confirmDeleteEntry.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete_outline"
                    text: I18n.tr("Delete section")
                    onClicked: {
                        ContentLab.deleteEntry(confirmDeleteEntry.pendingId)
                        confirmDeleteEntry.close()
                    }
                }
            }
        }
    }

    // Deleting a produced report removes the HTML from disk, so it asks first.
    Dialog {
        id: confirmDeleteReport
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, page.width - 80)
        padding: 0
        property string path: ""
        property string label: ""

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
            implicitHeight: delRepHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: delRepHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "delete_outline"; size: 20
                        glyphColor: Theme.error
                    }
                }
                C.AppText {
                    text: I18n.tr("Delete this report?")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: C.AppText {
            text: I18n.tr("The HTML report built from “{f}” will be removed from disk. The export file itself is untouched.")
                      .replace("{f}", confirmDeleteReport.label)
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
                    variant: "ghost"
                    text: I18n.tr("Cancel")
                    onClicked: confirmDeleteReport.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete"
                    text: I18n.tr("Delete report")
                    onClicked: {
                        ContentLab.deleteReport(confirmDeleteReport.path, true)
                        confirmDeleteReport.close()
                    }
                }
            }
        }
    }

    FileDialog {
        id: csvDialog
        title: I18n.tr("Choose a channel export")
        fileMode: FileDialog.OpenFile
        nameFilters: ["Channel export (*.csv *.xlsx *.jsonl *.db)"]
        onAccepted: ContentLab.pickCsv(selectedFile.toString())
    }

    C.Toast { id: toast; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 80 }
}
