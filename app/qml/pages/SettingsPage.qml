import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Dialogs
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Settings, v9 "control room" redesign.
//
// The old page was one long column of identical cards with a Save button at
// the very bottom: nothing told you where you were, what was configured, or
// that you had unsaved edits until you tried to leave. The page is now built
// the way modern desktop settings are:
//
//   ┌ rail ──────────┐┌ content ───────────────────────────────────────────┐
//   │ [search]       ││ Settings                         ● All saved       │
//   │ ▌Appearance    ││ [YouTube ✓] [AI ✓] [Engine !] [Output ✓]  ← health │
//   │  YouTube API ● ││ ┌ Appearance ────────────────────────────────────┐ │
//   │  AI Provider ● ││ │ theme · accent · language · motion │ preview  │ │
//   │  Download …  ● ││ └────────────────────────────────────────────────┘ │
//   │  Output …    ● ││ ┌ YouTube API ┐ ┌ AI Provider ┐ …                  │
//   │ [tour]  v9     ││              ╭ unsaved changes · Discard · Save ╮  │
//   └────────────────┘└──────────────╰──────────────────────────────────╯──┘
//
//  • a section rail with a sliding active marker, live status dots and a
//    search box that filters / jumps to sections;
//  • a health strip that answers "is this app set up?" at a glance and jumps
//    to whatever needs attention;
//  • every preference as a label + description + control row (no more
//    floating captions beside dropdowns);
//  • a floating save bar that only appears while there ARE unsaved edits,
//    with Discard and Ctrl+S.
//
// v18 (everything BELOW Appearance rebuilt; Appearance itself is untouched):
//  • YouTube API → a "key vault" (ApiKeysCard): SmartField wells with a live
//    key-format check, an ActionButton that morphs idle → checking → valid /
//    failed, per-row backup checks that test what is actually typed, and a
//    daily-capacity panel that explains keys only add quota across projects.
//  • NEW section "Key guide" (GoogleKeyGuide): exact, current steps for the
//    YouTube Data API key and the Gemini key, tickable, with the real error
//    codes and their fixes. Index 2 in the rail; AI / Engine / Output moved to
//    3 / 4 / 5.
//  • AI Provider: SmartField key + morphing Validate, capability chips,
//    Connection & routing rebuilt on SmartFields.
//  • Download Engine: two status modules (runtime, yt-dlp) with state orbs.
//  • Output & Scraping: format tiles, an equaliser for worker threads,
//    browser-cookie chips and a destination card for the save folder.
//
// All state still lives in the SettingsVM (Settings.*) — this is presentation
// only. Theme / accent / language / motion are App-level and apply instantly.
//
// NOTE: inline components below never reference ids of this document (QML
// inline components do not share the enclosing id scope); they talk to the
// page through properties and signals only.
Item {
    id: page

    // The tour is owned by the window; the button below just asks for it.
    signal tourRequested()
    // Theme + language changes are animated by the window (circular wipe /
    // veil), so the page only asks for them — same path as the title bar.
    signal themeWipeRequested(real cx, real cy, string preference)
    signal languageRequested(string lang)

    FolderDialog {
        id: folderDialog
        onAccepted: Settings.setSaveFolder(selectedFolder.toString())
    }
    // Per-kind destinations (Output & Scraping → Save locations).
    FolderDialog {
        id: videoFolderDialog
        title: I18n.tr("Choose where videos are saved")
        onAccepted: Settings.setVideoFolder(selectedFolder.toString())
    }
    FolderDialog {
        id: thumbFolderDialog
        title: I18n.tr("Choose where thumbnails are saved")
        onAccepted: Settings.setThumbFolder(selectedFolder.toString())
    }

    // transient status strings driven by VM signals
    property string ytStatus: I18n.tr("Not validated yet this session.")
    property color ytStatusColor: Theme.on_surface_var

    Connections {
        target: Settings
        function onYtValidateResult(key, ok, msg) {
            page.ytStatus = (ok ? "✓  " : "✗  ") + msg
                + (ok ? "\n" + Settings.keyQuotaLine(key) : "")
            page.ytStatusColor = ok ? Theme.secondary_container : Theme.error
        }
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    // Arm the AppController nav guard while this page is visible and has unsaved
    // edits, so leaving raises the save/discard/stay dialog (owned by Main.qml).
    // Cleared whenever the page hides or the edits are saved/reverted.
    // With auto-save on there is never anything to guard: a pending write is
    // flushed the moment the page hides instead.
    function _syncGuard() { App.setNavGuard(page.visible && Settings.isDirty && !Settings.autoSave) }
    onVisibleChanged: {
        if (!visible) Settings.flushAutosave()
        else Settings.reloadFolders()   // a thumb folder may have been picked on another page
        _syncGuard()
    }
    Connections {
        target: Settings
        function onChanged() { page._syncGuard() }
        // an auto-save is a save: same key refresh, same "Saved" flash
        function onAutoSaved() { page._afterSave() }
    }
    Component.onCompleted: _syncGuard()

    // ── actions ──
    function save() {
        Settings.save()
        _afterSave()
    }
    function _afterSave() {
        // Push the freshly-saved YouTube key into the pages that cache it, so
        // the first search/scrape/check after saving works immediately.
        Niche.refreshApiKeys()
        Dashboard.refreshApiKeys()
        Monetize.reloadKey()
        savedFlash.restart()
    }
    function discard() { Settings.revert() }

    Shortcut {
        sequences: [ StandardKey.Save ]
        enabled: page.visible && Settings.isDirty
        onActivated: page.save()
    }

    // ── derived status (health strip + rail dots) ──
    readonly property int ytKeyCount: {
        let n = String(Settings.apiKey || "").trim() !== "" ? 1 : 0
        const b = Settings.backupKeys
        for (let i = 0; i < b.length; i++)
            if (String(b[i] || "").trim() !== "") n++
        return n
    }
    readonly property bool ytOk: ytKeyCount > 0
    readonly property bool aiOk: Settings.aiReady
    readonly property string aiProviderName: Settings.aiProviderName
    readonly property bool engineOk: Deno.ready
    readonly property bool outputOk: String(Settings.saveFolder || "") !== ""

    // ── section registry ──
    // `keys` feeds the rail search: English words plus their translation, so
    // either language finds "theme", "proxy", "threads" …
    readonly property var sections: [
        { icon: "palette",     title: I18n.tr("Appearance"),
          sub: I18n.tr("Theme, accent, language"), tracked: false,
          keys: "appearance theme dark light system accent colour color language persian english farsi motion animation " + I18n.tr("theme accent language motion") },
        { icon: "youtube",     title: I18n.tr("YouTube API"),
          sub: I18n.tr("Keys & daily quota"), tracked: true,
          keys: "youtube api key keys quota backup validate data v3 " + I18n.tr("youtube key quota backup") },
        { icon: "key",         title: I18n.tr("Key guide"),
          sub: I18n.tr("Google keys, step by step"), tracked: false,
          keys: "guide help how get create google cloud console credentials ai studio gemini youtube step error 403 " + I18n.tr("guide google key help") },
        { icon: "psychology",  title: I18n.tr("AI Providers"),
          sub: I18n.tr("Providers, routing & effort"), tracked: true,
          keys: "ai provider providers openai anthropic gemini custom openrouter deepseek groq ollama model key host path proxy router endpoint fetch validate routing effort default ideas chat reports " + I18n.tr("ai provider model proxy routing effort") },
        { icon: "downloading", title: I18n.tr("Download Engine"),
          sub: I18n.tr("Runtime & downloader"), tracked: true,
          keys: "download engine runtime deno node javascript yt-dlp ytdlp update install " + I18n.tr("download runtime update") },
        { icon: "tune",        title: I18n.tr("Output & Scraping"),
          sub: I18n.tr("Format, threads, folder"), tracked: true,
          keys: "output scrape export format csv autosave checkpoint worker threads cookies browser transcripts folder save video videos thumbnail thumbnails location path " + I18n.tr("output export threads folder cookies transcripts") },
        // v3.43: always reachable, also after "Skip for now"
        { icon: "extension",   title: I18n.tr("Browser extension"),
          sub: I18n.tr("Download button on YouTube"), tracked: true,
          keys: "extension extensions chrome edge brave browser addon add-on plugin youtube button download unpacked developer " + I18n.tr("extension browser chrome youtube button") }
    ]
    function sectionOk(i) {
        return i === 1 ? page.ytOk : i === 3 ? page.aiOk
             : i === 4 ? page.engineOk : i === 5 ? page.outputOk
             : i === 6 ? ExtensionSetup.connected : true
    }
    function sectionItem(i) {
        return [secAppearance, secYoutube, secGuide, secAi, secEngine, secOutput, secExtension][i]
    }
    function sectionFlash(i) {
        const it = page.sectionItem(i)
        if (it && it.flash) it.flash()
    }
    // Open the key guide on a given track ("youtube" | "gemini").
    function openGuide(track) {
        secGuide.show(track)
        page.jumpTo(2, true)
    }
    // file:/// URL for the save folder (Windows "C:\x" and POSIX "/x" alike).
    function folderUrl() {
        const p = String(Settings.saveFolder || "").replace(/\\/g, "/")
        return p.startsWith("/") ? "file://" + p : "file:///" + p
    }

    // rail search
    property string query: ""
    function matches(i) {
        const q = page.query.trim().toLowerCase()
        if (q === "") return true
        const s = page.sections[i]
        return (s.title + " " + s.sub + " " + s.keys).toLowerCase().indexOf(q) >= 0
    }
    Timer {
        id: searchJump
        interval: 260
        onTriggered: {
            for (let i = 0; i < page.sections.length; i++)
                if (page.matches(i)) { page.jumpTo(i, true); return }
        }
    }

    // active section = the last one whose top has scrolled past the reading line
    property int activeSection: 0
    property bool _jumping: false
    function jumpTo(i, flash) {
        const it = page.sectionItem(i)
        if (!it) return
        page._jumping = true
        page.activeSection = i
        scroll.scrollToItem(it, Tokens.space5)
        jumpLock.restart()
        if (flash) page.sectionFlash(i)
    }
    Timer { id: jumpLock; interval: Tokens.durSlow + 120; onTriggered: page._jumping = false }
    function _recalcActive() {
        if (page._jumping) return
        const fl = scroll.contentItem
        if (!fl) return
        const line = fl.contentY + 160
        let idx = 0
        for (let i = 0; i < page.sections.length; i++) {
            const it = page.sectionItem(i)
            if (it && content.y + it.y <= line) idx = i
        }
        if (fl.contentY > 0 && fl.contentY >= fl.contentHeight - fl.height - 4)
            idx = page.sections.length - 1
        page.activeSection = idx
    }
    Connections {
        target: scroll.contentItem
        function onContentYChanged() { page._recalcActive() }
    }

    readonly property bool compactRail: page.width < 1080
    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true

    // ═════════════════════════ inline components ═════════════════════════

    // A soft accent ring that flashes once around a section the rail (or the
    // search box) just jumped to, so the eye lands on the right card.
    component SectionFlash: Rectangle {
        id: sf
        anchors.fill: parent
        radius: parent ? parent.radius : Tokens.radiusXl
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        opacity: 0
        z: 50
        function play() { sfAnim.restart() }
        SequentialAnimation {
            id: sfAnim
            PauseAnimation { duration: 180 }
            NumberAnimation { target: sf; property: "opacity"; to: 0.9; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: sf; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    // Section shell: icon tile + title + one-line purpose, an optional trailing
    // slot (status chips), then the body.
    component SettingsSection: C.GlassPanel {
        id: ss
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property bool dimmed: false
        default property alias body: ssBody.data
        property alias trailing: ssTrail.data

        Layout.fillWidth: true
        radius: Tokens.radiusXl
        implicitHeight: ssCol.implicitHeight + Tokens.space6 * 2
        opacity: ss.dimmed ? 0.38 : 1.0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        // one-shot accent ring when the rail / search jumps here
        function flash() { ssFlashAnim.restart() }
        Rectangle {
            id: ssFlash
            anchors.fill: parent
            radius: ss.radius
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
            opacity: 0
            z: 50
            SequentialAnimation {
                id: ssFlashAnim
                PauseAnimation { duration: 180 }
                NumberAnimation { target: ssFlash; property: "opacity"; to: 0.9; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: ssFlash; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutSine }
            }
        }

        ColumnLayout {
            id: ssCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space6
            spacing: Tokens.space5

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space4
                C.IconTile {
                    iconName: ss.icon
                    size: 44
                    lit: ssHead.hovered
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignVCenter
                    HoverHandler { id: ssHead }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.AppText {
                        text: ss.title
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontSubtitle + 2
                        color: Theme.text_strong
                    }
                    C.AppText {
                        visible: ss.subtitle !== ""
                        text: ss.subtitle
                        font.pixelSize: Tokens.fontBody
                        color: Theme.on_surface_var
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
                RowLayout {
                    id: ssTrail
                    spacing: Tokens.space2
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            ColumnLayout {
                id: ssBody
                Layout.fillWidth: true
                spacing: Tokens.space4
            }
        }
    }

    // A grouped list of setting rows (the macOS / Linear "inset group").
    component RowGroup: Rectangle {
        id: rg
        default property alias rows: rgCol.data
        Layout.fillWidth: true
        radius: Tokens.radiusLg
        color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.55 : 0.70)
        border.width: 1
        border.color: Theme.border
        implicitHeight: rgCol.implicitHeight + Tokens.space1 * 2
        ColumnLayout {
            id: rgCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space1
            spacing: 0
        }
    }

    component RowSep: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.space4
        Layout.rightMargin: Tokens.space4
        implicitHeight: 1
        color: Theme.divider_h
    }

    // One preference: label + description on the leading side, its control on
    // the trailing side. Stacks the control underneath on narrow widths.
    component SettingRow: Item {
        id: sr
        property string label: ""
        property string description: ""
        property string icon: ""
        property bool stacked: width < 640
        default property alias control: srCtl.data

        Layout.fillWidth: true
        implicitHeight: srGrid.implicitHeight + Tokens.space4 * 2

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusMd + 2
            color: srHover.hovered ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.035 : 0.03)
                                   : U.withAlpha(Theme.on_surface, 0)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        HoverHandler { id: srHover }

        GridLayout {
            id: srGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.space4
            anchors.rightMargin: Tokens.space4
            columns: sr.stacked ? 1 : 2
            columnSpacing: Tokens.space6
            rowSpacing: Tokens.space3

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                C.IconGlyph {
                    visible: sr.icon !== ""
                    name: sr.icon
                    size: 18
                    glyphColor: srHover.hovered ? Theme.primary : Theme.on_surface_var
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 1
                    Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    C.AppText {
                        text: sr.label
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.text_strong
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    C.AppText {
                        visible: sr.description !== ""
                        text: sr.description
                        font.pixelSize: Tokens.fontCaption + 1
                        color: Theme.on_surface_var
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
            RowLayout {
                id: srCtl
                spacing: Tokens.space2
                Layout.alignment: sr.stacked ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
            }
        }
    }

    // Segmented control with a pill that SLIDES to the chosen option.
    // options: [{ label, value, icon? }]
    component Segmented: Item {
        id: seg
        property var options: []
        property var current
        property bool mono: false
        property int minItemWidth: 0
        signal picked(var value, var btn)

        readonly property int curIdx: {
            for (let i = 0; i < seg.options.length; i++)
                if (seg.options[i].value === seg.current) return i
            return -1
        }
        implicitWidth: segRow.implicitWidth + 8
        implicitHeight: 40

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusMd + 3
            color: Theme.input_bg
            border.width: 1
            border.color: Theme.border
        }
        Rectangle {
            id: segPill
            readonly property Item tgt: segRep.count > 0 && seg.curIdx >= 0 ? segRep.liveItemAt(seg.curIdx) : null
            visible: tgt !== null
            x: tgt ? segRow.x + tgt.x : 0
            y: 4
            width: tgt ? tgt.width : 0
            height: seg.height - 8
            radius: Tokens.radiusMd
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
            }
            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        Row {
            id: segRow
            x: 4; y: 4
            spacing: 2
            Repeater {
                id: segRep
                // itemAt() is not a notifying lookup: a binding that ran before the
                // delegates existed got null and kept it (thumb missing on first show,
                // the active label invisible in light theme). `built` re-runs it.
                property int built: 0
                onItemAdded: built++
                onItemRemoved: built++
                function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                model: seg.options
                AbstractButton {
                    id: sb
                    readonly property bool active: index === seg.curIdx
                    height: seg.height - 8
                    implicitWidth: Math.max(seg.minItemWidth, sbRow.implicitWidth + Tokens.space4 * 2)
                    padding: 0
                    hoverEnabled: true
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: seg.picked(modelData.value, sb)
                    background: Rectangle {
                        radius: Tokens.radiusMd
                        color: !sb.active && sb.hovered ? U.withAlpha(Theme.on_surface, 0.06) : U.withAlpha(Theme.on_surface, 0)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    contentItem: Item {
                        Row {
                            id: sbRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.IconGlyph {
                                visible: (modelData.icon || "") !== ""
                                name: modelData.icon || ""
                                fill: sb.active
                                size: 15
                                glyphColor: sb.active ? Theme.on_primary : Theme.on_surface_var
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: modelData.label
                                mono: seg.mono
                                weight: sb.active ? Tokens.weightBold : Tokens.weightMedium
                                font.pixelSize: Tokens.fontBody
                                color: sb.active ? Theme.on_primary
                                     : sb.hovered ? Theme.text_strong : Theme.on_surface_var
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                        }
                    }
                }
            }
        }
    }

    // Small status chip: tinted dot + text.
    component StatusChip: Rectangle {
        id: chip
        property string text: ""
        property color tint: Theme.secondary_container
        property bool pulse: false
        radius: Tokens.radiusPill
        color: U.withAlpha(chip.tint, 0.13)
        border.width: 1
        border.color: U.withAlpha(chip.tint, 0.30)
        implicitWidth: chipRow.implicitWidth + Tokens.space3 * 2
        implicitHeight: 26
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 7
            Rectangle {
                width: 7; height: 7; radius: 3.5
                color: chip.tint
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: chip.pulse && chip.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            C.AppText {
                text: chip.text
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                color: chip.tint
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Health tile in the overview strip — clickable, jumps to its section.
    component HealthTile: AbstractButton {
        id: ht
        property string glyph: ""
        property string label: ""
        property string value: ""
        property string detail: ""
        property bool ok: true
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 92
        hoverEnabled: true
        padding: 0
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        readonly property color tint: ht.ok ? Theme.secondary_container : Theme.warn
        scale: ht.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

        background: Rectangle {
            radius: Tokens.radiusLg
            color: ht.hovered ? U.hoverTint(Theme.panel_bg, Theme.isDark) : Theme.panel_bg
            border.width: 1
            border.color: ht.hovered ? U.mix(Theme.border, Theme.primary, 0.35) : Theme.border
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            // status edge along the bottom
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                height: 2
                radius: 1
                color: U.withAlpha(ht.tint, ht.hovered ? 0.85 : 0.45)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
        }
        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space4
                spacing: Tokens.space3
                C.IconTile {
                    iconName: ht.glyph
                    size: 40
                    tint: ht.ok ? Theme.primary : Theme.warn
                    lit: ht.hovered
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        C.AppText {
                            text: ht.label
                            font.pixelSize: Tokens.fontCaption
                            weight: Tokens.weightDemiBold
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        C.IconGlyph {
                            name: ht.ok ? "check_circle" : "error"
                            fill: true
                            size: 15
                            glyphColor: ht.tint
                        }
                    }
                    C.AppText {
                        text: ht.value
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.text_strong
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.AppText {
                        text: ht.detail
                        visible: ht.detail !== ""
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // Provider choice card (OpenAI / Anthropic / Gemini / Custom).
    // v16: rebuilt. The old card had a fixed 112px height, so the caption was
    // clipped at the bottom edge and the block below (API KEY) sat glued to
    // it. The card now sizes to its content with generous, even padding, the
    // caption may wrap to two lines, each provider gets a brand-tinted icon
    // tile, and the selected card glows instead of just turning blue.
    component ProviderCard: AbstractButton {
        id: pc
        property string glyph: ""
        property string name: ""
        property string caption: ""
        property string badge: ""
        property bool active: false
        property color tint: Theme.primary
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        implicitHeight: pcCol.implicitHeight + 18 * 2
        hoverEnabled: true
        padding: 0
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        scale: pc.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: pc.hovered && !pc.active ? -2 : 0
            Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }

        background: Item {
            // selected halo
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: Tokens.radiusXl + 4
                color: "transparent"
                border.width: 4
                border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.12)
                opacity: pc.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
            Rectangle {
                id: pcBg
                anchors.fill: parent
                radius: Tokens.radiusXl
                clip: true
                color: pc.hovered && !pc.active ? U.hoverTint(Theme.surface_low, Theme.isDark, 0.05) : Theme.surface_low
                border.width: 1
                border.color: pc.active ? Theme.primary
                            : pc.hovered ? U.mix(Theme.border, Theme.outline, 0.55) : Theme.border
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

                // diagonal wash in the provider tint (stronger when active)
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    opacity: pc.active ? 1 : pc.hovered ? 0.6 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: U.withAlpha(pc.active ? Theme.primary : pc.tint, Theme.isDark ? 0.14 : 0.08) }
                        GradientStop { position: 1.0; color: U.withAlpha(pc.active ? Theme.primary : pc.tint, 0.0) }
                    }
                }
                // specular top edge
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Tokens.radiusXl * 2
                    height: 1
                    color: Theme.glass_hi
                }
            }
        }

        contentItem: Item {
            // radio
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 16
                width: 22; height: 22; radius: 11
                color: pc.active ? Theme.primary : U.withAlpha(Theme.primary, 0)
                border.width: pc.active ? 0 : 1.5
                border.color: pc.hovered ? Theme.outline : U.mix(Theme.border, Theme.outline, 0.5)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                scale: pc.active ? 1 : 0.92
                Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                C.IconGlyph {
                    anchors.centerIn: parent
                    visible: pc.active
                    name: "check"; size: 13
                    glyphColor: Theme.on_primary
                }
            }

            ColumnLayout {
                id: pcCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                anchors.rightMargin: 18
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 13
                    color: pc.active ? Theme.primary : U.withAlpha(pc.tint, Theme.isDark ? 0.16 : 0.12)
                    border.width: 1
                    border.color: pc.active ? U.withAlpha(Theme.on_primary, 0.18) : U.withAlpha(pc.tint, 0.28)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: pc.glyph
                        fill: true
                        size: 21
                        glyphColor: pc.active ? Theme.on_primary : U.mix(pc.tint, Theme.text_strong, Theme.isDark ? 0.25 : 0.0)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 8
                    C.AppText {
                        text: pc.name
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontSubtitle - 1
                        color: Theme.text_strong
                        elide: Text.ElideRight
                        Layout.maximumWidth: pcCol.width - (pc.badge !== "" ? badgeBox.implicitWidth + 8 : 0)
                    }
                    Rectangle {
                        id: badgeBox
                        visible: pc.badge !== ""
                        radius: Tokens.radiusPill
                        color: U.withAlpha(Theme.secondary_container, 0.14)
                        border.width: 1
                        border.color: U.withAlpha(Theme.secondary_container, 0.30)
                        implicitWidth: badgeRow.implicitWidth + 14
                        implicitHeight: 20
                        Row {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: 4
                            C.IconGlyph {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "star"; fill: true; size: 10
                                glyphColor: Theme.secondary_container
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pc.badge
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontMicro
                                color: Theme.secondary_container
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                C.AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: pc.caption
                    font.pixelSize: Tokens.fontCaption + 1
                    lineHeight: 1.35
                    color: Theme.on_surface_var
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Tinted callout used for notes (capability, custom-provider instructions).
    component Callout: Rectangle {
        id: co
        property string icon: "info"
        property string text: ""
        property color tint: Theme.primary
        Layout.fillWidth: true
        radius: Tokens.radiusLg
        color: U.withAlpha(co.tint, Theme.isDark ? 0.08 : 0.06)
        border.width: 1
        border.color: U.withAlpha(co.tint, 0.22)
        implicitHeight: coRow.implicitHeight + Tokens.space4 * 2
        RowLayout {
            id: coRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.space4
            spacing: Tokens.space3
            C.IconGlyph {
                name: co.icon
                size: 18
                glyphColor: co.tint
                Layout.alignment: Qt.AlignTop
            }
            C.AppText {
                Layout.fillWidth: true
                text: co.text
                color: Theme.on_surface
                font.pixelSize: Tokens.fontCaption + 1
                wrapMode: Text.WordWrap
            }
        }
    }

    // ─────────────── v18 building blocks (sections below Appearance) ───────────────

    // Small label above a control that is not a SmartField (dropdowns).
    component FieldLabel: Row {
        id: fl
        property string icon: ""
        property string text: ""
        spacing: Tokens.space2
        C.IconGlyph {
            visible: fl.icon !== ""
            name: fl.icon
            size: 14
            glyphColor: Theme.on_surface_var
            anchors.verticalCenter: parent.verticalCenter
        }
        C.AppText {
            text: fl.text
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontMicro
            font.letterSpacing: I18n.rtl ? 0 : 0.5
            color: Theme.on_surface_var
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // A block heading inside a section: icon + title + one-line purpose.
    // One save-location row: what it's for, where it points (or the default it
    // falls back to), and copy / open / change / reset. Empty is not an error
    // here — it just means "use the default" — so it never paints a warning.
    component FolderCard: Rectangle {
        id: fc
        property string label: ""
        property string path: ""
        property string fallback: ""          // shown muted while path is empty
        property string glyph: "folder_open"
        property color tint: Theme.primary
        signal pick()
        signal reset()
        readonly property bool _set: String(fc.path || "") !== ""
        readonly property string _shown: _set ? fc.path : fc.fallback
        Layout.fillWidth: true
        radius: 16
        color: fcHover.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark, 0.03) : Theme.input_bg
        border.width: 1
        border.color: fcHover.hovered ? Theme.border_med : Theme.border
        implicitHeight: 74
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        HoverHandler { id: fcHover }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space3
            anchors.rightMargin: Tokens.space3
            spacing: Tokens.space3
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 14
                color: U.withAlpha(fc.tint, Theme.isDark ? (fc._set ? 0.16 : 0.09) : (fc._set ? 0.10 : 0.06))
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: fc.glyph
                    fill: true
                    size: 22
                    glyphColor: fc._set ? fc.tint : Theme.on_surface_var
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    spacing: Tokens.space2
                    C.AppText {
                        text: fc.label
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontMicro
                        font.letterSpacing: I18n.rtl ? 0 : 1.1
                        color: Theme.on_surface_var
                    }
                    Rectangle {
                        visible: !fc._set
                        radius: Tokens.radiusPill
                        color: U.withAlpha(Theme.on_surface_var, 0.12)
                        implicitWidth: defLbl.implicitWidth + 12
                        implicitHeight: defLbl.implicitHeight + 4
                        C.AppText {
                            id: defLbl
                            anchors.centerIn: parent
                            text: I18n.tr("Default")
                            weight: Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontMicro
                            color: Theme.on_surface_var
                        }
                    }
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: fc._shown !== "" ? fc._shown : I18n.tr("Asked the first time you save one")
                    mono: fc._shown !== ""
                    weight: Tokens.weightMedium
                    font.pixelSize: Tokens.fontBody
                    color: fc._set ? Theme.text_strong : Theme.outline
                    elide: Text.ElideMiddle
                    LayoutMirroring.enabled: fc._shown !== "" ? false : I18n.rtl
                }
            }
            C.IconButton {
                visible: fc._shown !== ""
                iconName: "content_copy"
                implicitWidth: 36; implicitHeight: 36
                glyphSize: 16
                tip: I18n.tr("Copy path")
                onClicked: { Settings.copyToClipboard(fc._shown); toast.show(I18n.tr("Copied"), "info") }
            }
            C.IconButton {
                visible: fc._shown !== ""
                iconName: "open_in_new"
                implicitWidth: 36; implicitHeight: 36
                glyphSize: 16
                tip: I18n.tr("Open folder")
                onClicked: Settings.openFolder(fc._shown)
            }
            C.IconButton {
                visible: fc._set
                iconName: "restart_alt"
                implicitWidth: 36; implicitHeight: 36
                glyphSize: 16
                tip: I18n.tr("Back to default")
                onClicked: fc.reset()
            }
            C.ActionButton {
                compact: true
                variant: "ghost"
                iconName: "folder"
                text: fc._set ? I18n.tr("Change") : I18n.tr("Choose")
                onClicked: fc.pick()
            }
        }
        C.AppTooltip { visible: fcHover.hovered && fc._shown !== ""; text: fc._shown }
    }

    component BlockHead: RowLayout {
        id: bh
        property string icon: ""
        property string title: ""
        property string detail: ""
        Layout.fillWidth: true
        spacing: Tokens.space3
        C.IconGlyph {
            visible: bh.icon !== ""
            name: bh.icon
            size: 18
            glyphColor: Theme.on_surface_var
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            C.AppText {
                text: bh.title
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontLabel
                color: Theme.text_strong
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            C.AppText {
                visible: bh.detail !== ""
                text: bh.detail
                font.pixelSize: Tokens.fontCaption + 1
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    // Capability chip: ✓ on, ✕ off.
    component CapChip: Rectangle {
        id: cap
        property string glyph: ""
        property string text: ""
        property bool ok: true
        radius: Tokens.radiusPill
        color: cap.ok ? U.withAlpha(Theme.secondary_container, 0.13) : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.04)
        border.width: 1
        border.color: cap.ok ? U.withAlpha(Theme.secondary_container, 0.32) : Theme.border
        implicitWidth: capRow.implicitWidth + 24
        implicitHeight: 30
        width: implicitWidth
        height: implicitHeight
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        Row {
            id: capRow
            anchors.centerIn: parent
            spacing: 7
            C.IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                name: cap.glyph
                size: 14
                glyphColor: cap.ok ? Theme.secondary_container : Theme.outline
            }
            C.AppText {
                anchors.verticalCenter: parent.verticalCenter
                text: cap.text
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                font.strikeout: !cap.ok
                color: cap.ok ? Theme.text_strong : Theme.outline
            }
            C.IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                name: cap.ok ? "check" : "close"
                size: 13
                glyphColor: cap.ok ? Theme.secondary_container : Theme.outline
            }
        }
    }

    // Pill choice (one of many, all visible).
    component ChoiceChip: AbstractButton {
        id: cc
        property string glyph: ""
        property bool active: false
        implicitHeight: 40
        implicitWidth: ccRow.implicitWidth + 30
        hoverEnabled: true
        padding: 0
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        scale: cc.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
        background: Rectangle {
            radius: Tokens.radiusPill
            color: cc.active ? U.withAlpha(Theme.primary, Theme.isDark ? 0.17 : 0.10)
                 : cc.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
            border.width: 1
            border.color: cc.active ? Theme.primary : cc.hovered ? Theme.border_med : Theme.border
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            implicitWidth: ccRow.implicitWidth
            implicitHeight: ccRow.implicitHeight
            Row {
                id: ccRow
                anchors.centerIn: parent
                spacing: 7
                Rectangle {
                    width: 18; height: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: cc.active ? Theme.primary : "transparent"
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: cc.active ? "check" : cc.glyph
                        fill: cc.active
                        size: cc.active ? 12 : 15
                        glyphColor: cc.active ? Theme.on_primary : Theme.on_surface_var
                    }
                }
                C.AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cc.text
                    weight: cc.active ? Tokens.weightBold : Tokens.weightMedium
                    font.pixelSize: Tokens.fontBody
                    color: cc.active ? Theme.text_strong : Theme.on_surface
                }
            }
        }
    }

    // Export-format tile.
    component FormatTile: AbstractButton {
        id: ft
        property string glyph: ""
        property string name: ""
        property string ext: ""
        property string caption: ""
        property bool active: false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        implicitHeight: ftCol.implicitHeight + 16 * 2
        hoverEnabled: true
        padding: 0
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        scale: ft.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: ft.hovered && !ft.active ? -2 : 0
            Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        background: Item {
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: Tokens.radiusLg + 4
                color: "transparent"
                border.width: 4
                border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.15 : 0.11)
                opacity: ft.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusLg
                clip: true
                color: ft.hovered && !ft.active ? U.hoverTint(Theme.surface_low, Theme.isDark, 0.05) : Theme.surface_low
                border.width: 1
                border.color: ft.active ? Theme.primary : ft.hovered ? Theme.border_med : Theme.border
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    opacity: ft.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.15 : 0.08) }
                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                    }
                }
            }
        }
        contentItem: Item {
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 14
                width: 20; height: 20; radius: 10
                color: ft.active ? Theme.primary : "transparent"
                border.width: ft.active ? 0 : 1.5
                border.color: ft.hovered ? Theme.outline : U.mix(Theme.border, Theme.outline, 0.5)
                scale: ft.active ? 1 : 0.92
                Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                C.IconGlyph {
                    anchors.centerIn: parent
                    visible: ft.active
                    name: "check"; size: 12
                    glyphColor: Theme.on_primary
                }
            }
            ColumnLayout {
                id: ftCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 0
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 11
                    color: ft.active ? Theme.primary : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.06)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: ft.glyph
                        fill: true
                        size: 18
                        glyphColor: ft.active ? Theme.on_primary : Theme.on_surface_var
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 8
                    C.AppText {
                        text: ft.name
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.text_strong
                        elide: Text.ElideRight
                        Layout.maximumWidth: ftCol.width - (ft.ext !== "" ? extBox.implicitWidth + 8 : 0)
                    }
                    Rectangle {
                        id: extBox
                        visible: ft.ext !== ""
                        radius: 6
                        color: ft.active ? U.withAlpha(Theme.primary, 0.14) : U.withAlpha(Theme.on_surface, 0.06)
                        implicitWidth: extTxt.implicitWidth + 12
                        implicitHeight: 20
                        C.AppText {
                            id: extTxt
                            anchors.centerIn: parent
                            text: ft.ext
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontMicro
                            color: ft.active ? Theme.primary : Theme.on_surface_var
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                C.AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: ft.caption
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Worker threads as an equaliser: eight rising bars, click one to set the
    // count. Hover previews; the last three bars turn amber (turbo zone).
    component ThreadMeter: Item {
        id: tm
        property int value: 1
        property int maxValue: 8
        property int hoverIdx: -1
        signal picked(int v)
        readonly property int shown: tm.hoverIdx >= 0 ? tm.hoverIdx + 1 : tm.value
        readonly property string tier: tm.shown <= 2 ? I18n.tr("Gentle")
                                     : tm.shown <= 5 ? I18n.tr("Balanced") : I18n.tr("Turbo")
        // Mirrors app.core.transcripts._TURBO: parallel transcripts per level.
        readonly property var txPerLevel: [1, 2, 3, 4, 6, 8, 12, 16]
        readonly property int txShown: tm.txPerLevel[Math.max(0, Math.min(7, tm.shown - 1))]
        implicitWidth: tmRow.implicitWidth
        implicitHeight: 44

        RowLayout {
            id: tmRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.space4
            Row {
                spacing: 4
                Repeater {
                    model: tm.maxValue
                    AbstractButton {
                        id: bar
                        readonly property bool lit: index < tm.shown
                        readonly property bool preview: tm.hoverIdx >= 0 && index >= tm.value && index <= tm.hoverIdx
                        width: 22
                        height: 42
                        hoverEnabled: true
                        padding: 0
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onHoveredChanged: {
                            if (bar.hovered) tm.hoverIdx = index
                            else if (tm.hoverIdx === index) tm.hoverIdx = -1
                        }
                        onClicked: tm.picked(index + 1)
                        background: Item {
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 14
                                height: 12 + index * 4
                                radius: 4
                                color: bar.lit ? (index >= 5 ? Theme.warn : Theme.primary)
                                               : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.09 : 0.08)
                                opacity: bar.preview ? 0.55 : 1.0
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                            }
                        }
                        contentItem: Item {}
                    }
                }
            }
            ColumnLayout {
                spacing: 0
                Layout.preferredWidth: 96
                C.AppText {
                    text: tm.shown === 1 ? I18n.tr("1 thread") : I18n.tr("{n} threads").replace("{n}", tm.shown)
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontLabel
                    color: Theme.text_strong
                }
                C.AppText {
                    text: tm.tier + (tm.shown >= 6 ? "  ⚡" : "")
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: tm.shown >= 6 ? Theme.warn : Theme.primary
                }
                C.AppText {
                    text: I18n.tr("×{n} transcripts").replace("{n}", tm.txShown)
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                }
            }
        }
    }

    // Status module (Download Engine): state orb, kicker + title, detail,
    // meta chips, optional progress, then its action buttons.
    component ModuleCard: Rectangle {
        id: mc
        property string kicker: ""
        property string title: ""
        property string detail: ""
        property string orbIcon: ""
        property var meta: []
        property bool ok: true
        property bool busy: false
        property real progress: -1
        property bool indeterminate: false
        default property alias actions: mcActions.data
        readonly property color tint: mc.busy ? Theme.primary : mc.ok ? Theme.secondary_container : Theme.warn

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        radius: Tokens.radiusLg + 1
        color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.75 : 0.9)
        border.width: 1
        border.color: mc.ok ? Theme.border : U.withAlpha(Theme.warn, 0.40)
        implicitHeight: mcCol.implicitHeight + Tokens.space5 * 2
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 130
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(mc.tint, Theme.isDark ? 0.10 : 0.07) }
                GradientStop { position: 1.0; color: U.withAlpha(mc.tint, 0.0) }
            }
        }

        ColumnLayout {
            id: mcCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space5
            spacing: Tokens.space4

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space4
                Item {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    // breathing ring while busy
                    Rectangle {
                        id: mcRing
                        anchors.centerIn: parent
                        width: 52; height: 52; radius: 26
                        color: "transparent"
                        border.width: 2
                        border.color: mc.tint
                        visible: mc.busy
                        opacity: 0
                        SequentialAnimation on scale {
                            running: mcRing.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 1.35; duration: 1200; easing.type: Easing.OutCubic }
                        }
                        SequentialAnimation on opacity {
                            running: mcRing.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.6; to: 0.0; duration: 1200; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 26
                        color: U.withAlpha(mc.tint, Theme.isDark ? 0.14 : 0.11)
                        border.width: 1
                        border.color: U.withAlpha(mc.tint, 0.35)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        C.IconGlyph {
                            anchors.centerIn: parent
                            visible: !mc.busy
                            name: mc.orbIcon
                            fill: true
                            size: 22
                            glyphColor: mc.tint
                        }
                        C.SpinnerGlyph {
                            anchors.centerIn: parent
                            visible: mc.busy
                            name: "refresh"
                            spinning: visible
                            size: 20
                            glyphColor: mc.tint
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.AppText {
                        text: mc.kicker
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontMicro
                        font.letterSpacing: I18n.rtl ? 0 : 1.1
                        color: Theme.on_surface_var
                    }
                    C.AppText {
                        text: mc.title
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontSubtitle + 1
                        color: Theme.text_strong
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            C.AppText {
                Layout.fillWidth: true
                text: mc.detail
                font.pixelSize: Tokens.fontBody
                lineHeight: 1.35
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
            }

            Flow {
                visible: mc.meta.length > 0
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: mc.meta
                    Rectangle {
                        radius: 7
                        color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.05)
                        border.width: 1
                        border.color: Theme.border
                        implicitWidth: metaTxt.implicitWidth + 16
                        implicitHeight: 26
                        width: implicitWidth
                        height: implicitHeight
                        C.AppText {
                            id: metaTxt
                            anchors.centerIn: parent
                            text: modelData
                            mono: index === 0
                            weight: Tokens.weightMedium
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface
                        }
                    }
                }
            }

            // progress (install)
            Rectangle {
                id: mcTrack
                visible: mc.progress >= 0 || mc.indeterminate
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                clip: true
                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.07)
                Rectangle {
                    visible: !mc.indeterminate
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, mc.progress))
                    radius: 3
                    color: Theme.primary
                    Behavior on width { NumberAnimation { duration: Tokens.durMed } }
                }
                Rectangle {
                    id: mcSweep
                    visible: mc.indeterminate
                    width: parent.width * 0.3
                    height: parent.height
                    radius: 3
                    color: Theme.primary
                    NumberAnimation on x {
                        running: mcSweep.visible
                        loops: Animation.Infinite
                        from: -mcSweep.width
                        to: mcTrack.width
                        duration: 1200
                        easing.type: Easing.InOutSine
                    }
                }
            }

            RowLayout {
                id: mcActions
                spacing: Tokens.space2
            }
        }
    }

    // ═════════════════════════════ layout ═════════════════════════════

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── section rail ──
        Item {
            id: rail
            Layout.fillHeight: true
            Layout.preferredWidth: page.compactRail ? 76 : 264
            Behavior on Layout.preferredWidth { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            clip: true

            Rectangle {
                anchors.fill: parent
                color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.45 : 0.6)
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Tokens.space7
                anchors.bottomMargin: Tokens.space5
                anchors.leftMargin: page.compactRail ? Tokens.space3 : Tokens.space4
                anchors.rightMargin: page.compactRail ? Tokens.space3 : Tokens.space4
                spacing: Tokens.space4

                C.AppText {
                    visible: !page.compactRail
                    text: I18n.tr("SETTINGS")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontMicro
                    font.letterSpacing: I18n.rtl ? 0 : 1.4
                    color: Theme.outline
                    Layout.leftMargin: Tokens.space2
                }

                // search
                Rectangle {
                    visible: !page.compactRail
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Tokens.radiusMd + 2
                    color: Theme.input_bg
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.primary : Theme.border
                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.space3
                        anchors.rightMargin: Tokens.space2
                        spacing: Tokens.space2
                        C.IconGlyph {
                            name: "search"; size: 16
                            glyphColor: searchInput.activeFocus ? Theme.primary : Theme.outline
                        }
                        TextField {
                            id: searchInput
                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                            T.ContextMenu.menu: C.EditMenu { editor: searchInput }
                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                            selectedTextColor: Theme.text_strong
                            Layout.fillWidth: true
                            placeholderText: I18n.tr("Find a setting …")
                            placeholderTextColor: Theme.outline
                            color: Theme.on_surface
                            font.family: Fonts.body
                            font.pixelSize: Tokens.fontBody
                            selectByMouse: true
                            background: null
                            leftPadding: 0; rightPadding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            onTextChanged: { page.query = text; if (text.trim() !== "") searchJump.restart() }
                            Keys.onEscapePressed: text = ""
                            Keys.onReturnPressed: searchJump.triggered()
                        }
                        C.IconButton {
                            visible: searchInput.text !== ""
                            iconName: "close"
                            implicitWidth: 26; implicitHeight: 26
                            glyphSize: 14
                            onClicked: searchInput.text = ""
                        }
                    }
                }

                // nav list with a sliding active marker
                Item {
                    Layout.fillWidth: true
                    implicitHeight: navCol.implicitHeight

                    Rectangle {
                        id: navMarker
                        readonly property Item tgt: navRep.count > page.activeSection
                                                    ? navRep.liveItemAt(page.activeSection) : null
                        visible: tgt !== null
                        x: 0
                        width: parent.width
                        y: tgt ? tgt.y : 0
                        height: tgt ? tgt.height : 0
                        radius: Tokens.radiusLg
                        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.13 : 0.10)
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.28)
                        Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                        // leading accent bar — a pill INSIDE the marker (it used
                        // to sit at -1 and poke out over the rounded border)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 4
                            width: 3
                            height: parent.height * 0.5
                            radius: width / 2
                            color: Theme.primary
                        }
                    }

                    Column {
                        id: navCol
                        width: parent.width
                        spacing: 4
                        Repeater {
                            id: navRep
                            // itemAt() is not a notifying lookup: a binding that ran before the
                            // delegates existed got null and kept it (thumb missing on first show,
                            // the active label invisible in light theme). `built` re-runs it.
                            property int built: 0
                            onItemAdded: built++
                            onItemRemoved: built++
                            function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                            model: page.sections
                            AbstractButton {
                                id: nb
                                readonly property bool active: page.activeSection === index
                                readonly property bool hit: page.matches(index)
                                width: navCol.width
                                height: page.compactRail ? 50 : 56
                                hoverEnabled: true
                                padding: 0
                                opacity: nb.hit ? 1.0 : 0.35
                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                onClicked: page.jumpTo(index, true)
                                background: Rectangle {
                                    radius: Tokens.radiusLg
                                    color: !nb.active && nb.hovered ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(Theme.on_surface, 0)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                }
                                contentItem: Item {
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: page.compactRail ? 0 : Tokens.space3
                                        anchors.rightMargin: page.compactRail ? 0 : Tokens.space3
                                        spacing: Tokens.space3
                                        Item { visible: page.compactRail; Layout.fillWidth: true }
                                        Item {
                                            Layout.preferredWidth: 34
                                            Layout.preferredHeight: 34
                                            Layout.alignment: Qt.AlignVCenter
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: Tokens.radiusMd
                                                color: nb.active ? Theme.primary : U.withAlpha(Theme.on_surface, nb.hovered ? 0.09 : 0.06)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    name: modelData.icon
                                                    fill: nb.active
                                                    size: 17
                                                    glyphColor: nb.active ? Theme.on_primary
                                                              : nb.hovered ? Theme.text_strong : Theme.on_surface_var
                                                }
                                            }
                                            // status dot (compact rail only)
                                            Rectangle {
                                                visible: page.compactRail && modelData.tracked === true
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: -2
                                                width: 9; height: 9; radius: 4.5
                                                color: page.sectionOk(index) ? Theme.secondary_container : Theme.warn
                                                border.width: 2
                                                border.color: Theme.background
                                            }
                                        }
                                        ColumnLayout {
                                            visible: !page.compactRail
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 1
                                            C.AppText {
                                                text: modelData.title
                                                weight: nb.active ? Tokens.weightBold : Tokens.weightDemiBold
                                                font.pixelSize: Tokens.fontBody
                                                color: nb.active ? Theme.text_strong : Theme.on_surface
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            C.AppText {
                                                text: modelData.sub
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.outline
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Rectangle {
                                            visible: !page.compactRail && modelData.tracked === true
                                            Layout.preferredWidth: 8
                                            Layout.preferredHeight: 8
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 4
                                            color: page.sectionOk(index) ? Theme.secondary_container : Theme.warn
                                        }
                                        Item { visible: page.compactRail; Layout.fillWidth: true }
                                    }
                                }
                                C.AppTooltip {
                                    visible: page.compactRail && nb.hovered
                                    text: modelData.title
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // footer: tour + version
                C.PrimaryButton {
                    visible: !page.compactRail
                    Layout.fillWidth: true
                    variant: "ghost"
                    iconName: "help"
                    text: I18n.tr("Replay the guided tour")
                    onClicked: page.tourRequested()
                }
                C.IconButton {
                    visible: page.compactRail
                    Layout.alignment: Qt.AlignHCenter
                    iconName: "help"
                    tip: I18n.tr("Replay the guided tour")
                    onClicked: page.tourRequested()
                }
                C.AppText {
                    visible: !page.compactRail
                    text: "YouTube Hunter " + App.version
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // ── content ──
        C.SmoothScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                width: parent.width
                // bottom room so the floating save bar never covers the last row
                implicitHeight: content.implicitHeight + Tokens.space7 + 120

                C.GridFade {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 420
                }

                ColumnLayout {
                    id: content
                    width: Math.min(1180, parent.width - Tokens.space6 * 2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Tokens.space7
                    spacing: Tokens.space5

                    // heading + live save state
                    C.PageHeader {
                        iconName: "settings"
                        title: I18n.tr("Settings")
                        subtitle: I18n.tr("API keys, appearance, downloads and app preferences, all in one place.")

                        StatusChip {
                            visible: Settings.isDirty && !Settings.autoSave
                            text: I18n.tr("Unsaved changes")
                            tint: Theme.warn
                            pulse: page._motion
                        }
                        StatusChip {
                            visible: !Settings.isDirty || Settings.autoSave
                            text: Settings.isDirty ? I18n.tr("Saving…")
                                 : savedFlash.running ? I18n.tr("Saved") : I18n.tr("All changes saved")
                            tint: Theme.secondary_container
                        }
                        // save mode: the user picks auto or manual
                        Rectangle {
                            id: saveMode
                            implicitHeight: 30
                            implicitWidth: smRow.implicitWidth + Tokens.space3 * 2
                            radius: Tokens.radiusPill
                            color: smHover.hovered ? U.withAlpha(Theme.on_surface, 0.07) : U.withAlpha(Theme.on_surface, 0.04)
                            border.width: 1
                            border.color: Theme.border
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            HoverHandler { id: smHover }
                            Row {
                                id: smRow
                                anchors.centerIn: parent
                                spacing: Tokens.space2
                                C.IconGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: Settings.autoSave ? "autorenew" : "save"
                                    size: 14
                                    glyphColor: Settings.autoSave ? Theme.secondary_container : Theme.on_surface_var
                                }
                                C.AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Auto-save")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.text_strong
                                }
                                C.AppSwitch {
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: Settings.autoSave
                                    onToggled: Settings.setAutoSave(checked)
                                }
                            }
                            C.AppTooltip {
                                visible: smHover.hovered
                                delay: 400
                                text: Settings.autoSave ? I18n.tr("On: every change is saved by itself. Turn off to save with the Save button.")
                                                        : I18n.tr("Off: changes wait for Save (Ctrl+S). Turn on to save automatically.")
                            }
                        }
                    }
                    Timer { id: savedFlash; interval: 2200 }

                    // ── health strip ──
                    GridLayout {
                        Layout.fillWidth: true
                        columns: content.width < 760 ? 2 : 4
                        columnSpacing: Tokens.space3
                        rowSpacing: Tokens.space3

                        HealthTile {
                            glyph: "youtube"
                            label: I18n.tr("YouTube API")
                            ok: page.ytOk
                            value: page.ytKeyCount === 0 ? I18n.tr("No key yet")
                                 : page.ytKeyCount === 1 ? I18n.tr("1 key")
                                 : I18n.tr("{n} keys").replace("{n}", page.ytKeyCount)
                            detail: page.ytOk ? I18n.tr("Primary + backups rotate automatically")
                                              : I18n.tr("Needed for every search")
                            onClicked: page.jumpTo(1, true)
                        }
                        HealthTile {
                            glyph: "psychology"
                            label: I18n.tr("AI Provider")
                            ok: page.aiOk
                            value: page.aiProviderName
                            detail: page.aiOk ? (Settings.aiModel || I18n.tr("Default model"))
                                              : I18n.tr("Add an API key")
                            onClicked: page.jumpTo(3, true)
                        }
                        HealthTile {
                            glyph: "downloading"
                            label: I18n.tr("Download Engine")
                            ok: page.engineOk
                            value: Deno.ready ? I18n.tr("Ready")
                                   : !Deno.available ? I18n.tr("Runtime missing")
                                   : I18n.tr("PO Token helper missing")
                            detail: Deno.ready ? (Deno.runtimeName + " " + Deno.runtimeVersion + " · bgutil-pot")
                                   : !Deno.available ? I18n.tr("One-time install, about 40 MB")
                                   : I18n.tr("Required, about 44 MB")
                            onClicked: page.jumpTo(4, true)
                        }
                        HealthTile {
                            glyph: "folder_open"
                            label: I18n.tr("Output")
                            ok: page.outputOk
                            value: (Settings.formatLabels[Settings.formatIndex] || "")
                                   + "  ·  " + I18n.tr("{n} threads").replace("{n}", Settings.threadCount)
                            detail: page.outputOk ? Settings.saveFolder : I18n.tr("Pick a save folder")
                            onClicked: page.jumpTo(5, true)
                        }
                    }

                    // ═══ APPEARANCE ═══
                    SettingsSection {
                        id: secAppearance
                        icon: "palette"
                        title: I18n.tr("Appearance")
                        subtitle: I18n.tr("Make it yours. Everything here applies instantly, no restart.")
                        dimmed: !page.matches(0)

                        GridLayout {
                            Layout.fillWidth: true
                            columns: content.width >= 980 ? 2 : 1
                            columnSpacing: Tokens.space5
                            rowSpacing: Tokens.space4

                            RowGroup {
                                Layout.alignment: Qt.AlignTop
                                SettingRow {
                                    icon: "contrast"
                                    label: I18n.tr("Theme")
                                    description: I18n.tr("Follow Windows, or pin light / dark.")
                                    Segmented {
                                        current: App.themePreference !== undefined
                                                 ? App.themePreference : (Theme.isDark ? "dark" : "light")
                                        options: [
                                            { label: I18n.tr("System"), value: "system", icon: "desktop_windows" },
                                            { label: I18n.tr("Light"),  value: "light",  icon: "light_mode" },
                                            { label: I18n.tr("Dark"),   value: "dark",   icon: "dark_mode" }
                                        ]
                                        onPicked: (value, btn) => {
                                            const now = Theme.isDark ? "dark" : "light"
                                            if (App.resolvedThemeName(value) === now) {
                                                App.applyTheme(value)       // same palette: just remember it
                                                return
                                            }
                                            const p = btn.mapToItem(null, btn.width / 2, btn.height / 2)
                                            page.themeWipeRequested(p.x, p.y, value)
                                        }
                                    }
                                }
                                RowSep {}
                                SettingRow {
                                    icon: "palette"
                                    label: I18n.tr("Accent colour")
                                    description: I18n.tr("Repaints every button, icon tile and glow.")
                                    Grid {
                                        columns: 5
                                        spacing: Tokens.space2 + 2
                                        Repeater {
                                            model: App.accents
                                            delegate: AbstractButton {
                                                id: sw
                                                width: 34; height: 34
                                                hoverEnabled: true
                                                readonly property bool active: App.accent === modelData.key
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                onClicked: App.setAccent(modelData.key)
                                                scale: sw.pressed ? 0.88 : sw.hovered ? 1.08 : 1.0
                                                Behavior on scale {
                                                    NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic }
                                                }
                                                background: Item {
                                                    // ring OUTSIDE the disc so the swatch keeps its true colour
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: parent.width + (sw.active ? 8 : 4)
                                                        height: width
                                                        radius: width / 2
                                                        color: "transparent"
                                                        border.width: 2
                                                        border.color: sw.active ? modelData.color
                                                                      : sw.hovered ? Theme.outline : U.withAlpha(Theme.outline, 0)
                                                        Behavior on width { NumberAnimation { duration: Tokens.durFast } }
                                                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                    }
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: width / 2
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0; color: modelData.color }
                                                            GradientStop { position: 1.0; color: modelData.color2 !== undefined ? modelData.color2 : modelData.color }
                                                        }
                                                        Rectangle {
                                                            width: parent.width * 0.5; height: parent.height * 0.3
                                                            radius: height / 2
                                                            x: parent.width * 0.18; y: parent.height * 0.12
                                                            color: Qt.rgba(1, 1, 1, 0.22)
                                                        }
                                                    }
                                                }
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    visible: sw.active
                                                    name: "check"; fill: true; size: 16
                                                    glyphColor: "#ffffff"
                                                }
                                                C.AppTooltip { visible: sw.hovered; text: I18n.tr(modelData.name) }
                                            }
                                        }
                                    }
                                }
                                RowSep {}
                                SettingRow {
                                    icon: "translate"
                                    label: I18n.tr("Language")
                                    description: I18n.tr("Switches the whole interface, including right-to-left layout.")
                                    Segmented {
                                        current: I18n.lang
                                        minItemWidth: 92
                                        options: [
                                            { label: "English", value: "en" },
                                            { label: "فارسی",   value: "fa" }
                                        ]
                                        onPicked: (value, btn) => {
                                            if (value !== I18n.lang) page.languageRequested(value)
                                        }
                                    }
                                }
                                RowSep {}
                                SettingRow {
                                    icon: "sparkling"
                                    label: I18n.tr("Ambient motion")
                                    description: I18n.tr("Drifting page light and breathing glows. Turn off for a perfectly still interface.")
                                    C.AppSwitch {
                                        checked: App.ambientMotion
                                        onToggled: App.setAmbientMotion(checked)
                                    }
                                }
                                // v3.40: away notices (desktop toasts)
                                RowSep {}
                                SettingRow {
                                    icon: "notifications"
                                    label: I18n.tr("Desktop notifications")
                                    description: I18n.tr("When a scrape, download or AI job finishes while you're in another app, a notice slides into the corner of your screen.")
                                    C.ActionButton {
                                        compact: true
                                        variant: "ghost"
                                        iconName: "visibility"
                                        text: I18n.tr("Preview")
                                        enabled: DesktopNotify.enabled
                                        onClicked: DesktopNotify.preview()
                                    }
                                    C.AppSwitch {
                                        checked: DesktopNotify.enabled
                                        onToggled: DesktopNotify.setEnabled(checked)
                                    }
                                }
                                // v3.41: live activity card for jobs still running
                                RowSep {}
                                SettingRow {
                                    icon: "downloading"
                                    label: I18n.tr("Live progress while away")
                                    description: I18n.tr("A download or cut still running when you switch apps follows you as a live card in the corner. Close it and you'll still get a notice when it's done.")
                                    C.ActionButton {
                                        compact: true
                                        variant: "ghost"
                                        iconName: "visibility"
                                        text: I18n.tr("Preview")
                                        enabled: DesktopNotify.enabled && DesktopNotify.liveEnabled
                                        onClicked: DesktopNotify.previewLive()
                                    }
                                    C.AppSwitch {
                                        checked: DesktopNotify.liveEnabled
                                        enabled: DesktopNotify.enabled
                                        onToggled: DesktopNotify.setLiveEnabled(checked)
                                    }
                                }
                                RowSep { visible: Qt.platform.os === "windows" }
                                SettingRow {
                                    visible: Qt.platform.os === "windows"
                                    icon: "volume_up"
                                    label: I18n.tr("Notification sound")
                                    description: I18n.tr("Play your Windows notification sound with each notice.")
                                    C.AppSwitch {
                                        checked: DesktopNotify.sound
                                        enabled: DesktopNotify.enabled
                                        onToggled: DesktopNotify.setSound(checked)
                                    }
                                }
                            }

                            // live preview — a tiny YouTube Hunter window painted with
                            // the live palette, so every choice on the left is
                            // visible the moment it is made.
                            Rectangle {
                                id: preview
                                Layout.fillWidth: true
                                Layout.preferredWidth: 380
                                Layout.maximumWidth: content.width >= 980 ? 420 : 100000
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: 300
                                radius: Tokens.radiusLg
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.border
                                clip: true

                                // accent wash (rounded: clip: true only cuts square)
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: parent.height * 0.6
                                    radius: parent.radius
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.12) }
                                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                                    }
                                }
                                // title bar dots
                                Row {
                                    x: Tokens.space3; y: Tokens.space3
                                    spacing: 6
                                    Repeater {
                                        model: 3
                                        Rectangle { width: 8; height: 8; radius: 4; color: U.withAlpha(Theme.on_surface, 0.18) }
                                    }
                                }
                                C.AppText {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Tokens.space3
                                    y: Tokens.space2 + 1
                                    text: I18n.tr("Live preview")
                                    font.pixelSize: Tokens.fontMicro
                                    weight: Tokens.weightDemiBold
                                    color: Theme.outline
                                }
                                // mini rail
                                Rectangle {
                                    x: Tokens.space3; y: 34
                                    width: 52; height: parent.height - 34 - Tokens.space3
                                    radius: Tokens.radiusMd
                                    color: Theme.surface_low
                                    border.width: 1; border.color: Theme.border
                                    Column {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: Tokens.space3
                                        spacing: Tokens.space2
                                        Repeater {
                                            model: ["nav_niche", "nav_ideas", "nav_downloads", "nav_settings"]
                                            Rectangle {
                                                width: 32; height: 32; radius: Tokens.radiusSm
                                                color: index === 1 ? Theme.primary : "transparent"
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    name: modelData; size: 15; fill: index === 1
                                                    glyphColor: index === 1 ? Theme.on_primary : Theme.on_surface_var
                                                }
                                            }
                                        }
                                    }
                                }
                                // mini card
                                Rectangle {
                                    x: 52 + Tokens.space3 * 2; y: 34
                                    width: parent.width - x - Tokens.space3
                                    height: parent.height - 34 - Tokens.space3
                                    radius: Tokens.radiusMd
                                    color: Theme.panel_bg
                                    border.width: 1; border.color: Theme.border
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space4
                                        spacing: Tokens.space3
                                        RowLayout {
                                            spacing: Tokens.space2
                                            C.IconTile { iconName: "lightbulb"; size: 30; solid: true; Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                                            ColumnLayout {
                                                spacing: 0
                                                C.AppText { text: I18n.tr("AI Ideas"); weight: Tokens.weightBold; color: Theme.text_strong }
                                                C.AppText { text: I18n.tr("3 blueprints ready"); font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var }
                                            }
                                        }
                                        // chart bars
                                        Row {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 56
                                            spacing: 6
                                            Repeater {
                                                model: [0.35, 0.6, 0.45, 0.85, 0.55, 1.0, 0.7]
                                                Rectangle {
                                                    width: 14
                                                    height: 56 * modelData
                                                    y: 56 - height
                                                    radius: 4
                                                    color: index === 5 ? Theme.primary : U.withAlpha(Theme.primary, 0.28)
                                                }
                                            }
                                        }
                                        Item { Layout.fillHeight: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2
                                            Rectangle {
                                                radius: Tokens.radiusPill
                                                color: U.withAlpha(Theme.primary, 0.14)
                                                implicitWidth: chipTxt.implicitWidth + 16
                                                implicitHeight: 24
                                                C.AppText { id: chipTxt; anchors.centerIn: parent; text: "4.2x"; mono: true; weight: Tokens.weightBold; font.pixelSize: Tokens.fontCaption; color: Theme.primary }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                implicitWidth: 40; implicitHeight: 22; radius: 11
                                                color: Theme.primary
                                                Rectangle { width: 16; height: 16; radius: 8; x: parent.width - width - 3; y: 3; color: "#ffffff" }
                                            }
                                            Rectangle {
                                                implicitWidth: btnTxt.implicitWidth + 24
                                                implicitHeight: 30
                                                radius: Tokens.radiusSm
                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: Theme.primary }
                                                    GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
                                                }
                                                C.AppText { id: btnTxt; anchors.centerIn: parent; text: I18n.tr("Generate"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontCaption; color: Theme.on_primary }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ YOUTUBE API ═══
                    C.ApiKeysCard {
                        id: secYoutube
                        dimmed: !page.matches(1)
                        onGuideRequested: page.openGuide("youtube")
                    }

                    // ═══ GOOGLE KEY GUIDE ═══
                    C.GoogleKeyGuide {
                        id: secGuide
                        dimmed: !page.matches(2)
                        onKeyFieldRequested: page.jumpTo(1, true)
                        onGeminiRequested: {
                            if (Settings.providerIndex !== 2) Settings.providerIndex = 2
                            page.jumpTo(3, true)
                        }
                    }

                    // ═══ AI PROVIDERS (v19: saved profiles + routing) ═══
                    SettingsSection {
                        id: secAi
                        icon: "psychology"
                        title: I18n.tr("AI Providers")
                        subtitle: Settings.autoSave
                                  ? I18n.tr("Save as many providers as you like, then choose which one powers each feature. Changes here save automatically.")
                                  : I18n.tr("Save as many providers as you like, then choose which one powers each feature. Press Save to keep your changes.")
                        dimmed: !page.matches(3)
                        trailing: [
                            StatusChip {
                                text: Settings.aiReadyCount === 0 ? I18n.tr("No key yet")
                                     : Settings.aiReadyCount === 1 ? I18n.tr("1 ready")
                                     : I18n.tr("{n} ready").replace("{n}", Settings.aiReadyCount)
                                tint: Settings.aiReadyCount > 0 ? Theme.secondary_container : Theme.warn
                            }
                        ]

                        // ── the saved providers ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            BlockHead {
                                icon: "api"
                                title: I18n.tr("Your providers")
                                detail: I18n.tr("Each one keeps its own host, key and model. Star one as the default.")
                            }
                            C.ActionButton {
                                id: addProvBtn
                                Layout.alignment: Qt.AlignVCenter
                                iconName: "add"
                                text: I18n.tr("Add provider")
                                onClicked: addMenu.opened ? addMenu.close() : addMenu.open()

                                Popup {
                                    id: addMenu
                                    y: addProvBtn.height + 8
                                    x: I18n.rtl ? 0 : addProvBtn.width - width
                                    width: 320
                                    padding: 8
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                    enter: Transition {
                                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                                        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                                    }
                                    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Tokens.durFast } }
                                    background: Rectangle {
                                        radius: 18
                                        color: Theme.isDark ? Theme.surface_high : Theme.surface
                                        border.width: 1; border.color: Theme.border_med
                                    }
                                    contentItem: Column {
                                        LayoutMirroring.enabled: I18n.rtl
                                        LayoutMirroring.childrenInherit: true
                                        spacing: 2
                                        C.AppText { leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6; text: I18n.tr("Start from"); color: Theme.outline; weight: Tokens.weightDemiBold; font.pixelSize: Tokens.fontCaption }
                                        Repeater {
                                            model: Settings.aiPresets
                                            delegate: AbstractButton {
                                                id: pm
                                                width: 304
                                                implicitHeight: 48
                                                hoverEnabled: true
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                leftPadding: 8; rightPadding: 8
                                                onClicked: { addMenu.close(); Settings.addAiProfile(modelData.id) }
                                                background: Rectangle { radius: 12; color: pm.hovered ? U.withAlpha(Theme.on_surface, 0.07) : U.withAlpha(Theme.on_surface, 0) }
                                                contentItem: RowLayout {
                                                    spacing: 10
                                                    Rectangle {
                                                        Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                                        radius: 10
                                                        color: index === 0 ? U.withAlpha(Theme.primary, 0.14) : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.05)
                                                        C.IconGlyph { anchors.centerIn: parent; name: modelData.glyph; size: 16; glyphColor: index === 0 ? Theme.primary : Theme.on_surface_var }
                                                    }
                                                    Column {
                                                        Layout.fillWidth: true
                                                        spacing: 1
                                                        C.AppText { text: modelData.name; weight: Tokens.weightBold; color: Theme.text_strong }
                                                        C.AppText {
                                                            width: 230
                                                            text: modelData.host !== "" ? modelData.host.replace(/^https?:\/\//, "") : I18n.tr("Any compatible endpoint")
                                                            mono: modelData.host !== ""
                                                            font.pixelSize: Tokens.fontMicro + 1
                                                            color: Theme.on_surface_var
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    Rectangle {
                                                        visible: modelData.local
                                                        radius: Tokens.radiusPill
                                                        color: U.withAlpha(Theme.secondary_container, 0.14)
                                                        implicitWidth: locTxt.implicitWidth + 12
                                                        implicitHeight: 20
                                                        C.AppText { id: locTxt; anchors.centerIn: parent; text: I18n.tr("Local"); font.pixelSize: Tokens.fontMicro; weight: Tokens.weightBold; color: Theme.secondary_container }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            Repeater {
                                model: Settings.aiProfileIds
                                delegate: C.AiProfileCard { profileId: modelData }
                            }
                        }

                        // no Gemini key yet → straight to the guide
                        AbstractButton {
                            id: geminiNudge
                            visible: String((Settings.aiProfileMap["gemini"] || {}).apiKey || "") === ""
                            Layout.fillWidth: true
                            implicitHeight: 56
                            hoverEnabled: true
                            padding: 0
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            onClicked: page.openGuide("gemini")
                            background: Rectangle {
                                radius: 14
                                color: geminiNudge.hovered ? U.withAlpha(Theme.primary, Theme.isDark ? 0.14 : 0.09)
                                                           : U.withAlpha(Theme.primary, Theme.isDark ? 0.08 : 0.05)
                                border.width: 1
                                border.color: U.withAlpha(Theme.primary, geminiNudge.hovered ? 0.5 : 0.25)
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                            contentItem: Item {
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.space4
                                    anchors.rightMargin: Tokens.space4
                                    spacing: Tokens.space3
                                    C.IconGlyph { name: "provider_gemini"; fill: true; size: 18; glyphColor: Theme.primary }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("No Gemini key yet? It is free from Google AI Studio, four steps.")
                                        weight: Tokens.weightDemiBold
                                        color: Theme.text_strong
                                        elide: Text.ElideRight
                                    }
                                    C.AppText {
                                        text: I18n.tr("Open the guide")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption + 1
                                        color: Theme.primary
                                    }
                                    C.IconGlyph {
                                        name: I18n.rtl ? "arrow_back" : "arrow_forward"
                                        size: 16
                                        glyphColor: Theme.primary
                                    }
                                }
                            }
                        }

                        // ── routing: which AI does what ──
                        BlockHead {
                            Layout.topMargin: Tokens.space3
                            icon: "route"
                            title: I18n.tr("Which AI does what")
                            detail: I18n.tr("Pin idea generation to one provider and model. AI Chat picks its own model and effort in the chat.")
                        }
                        C.AiRoutingPanel { Layout.fillWidth: true }

                        // what the default provider can do for the AI features
                        Rectangle {
                            Layout.fillWidth: true
                            radius: Tokens.radiusLg
                            readonly property color tint: Settings.isGeminiProvider ? Theme.secondary_container : Theme.on_surface_var
                            color: U.withAlpha(tint, Theme.isDark ? 0.07 : 0.05)
                            border.width: 1
                            border.color: U.withAlpha(tint, 0.22)
                            implicitHeight: aiCapCol.implicitHeight + Tokens.space4 * 2
                            ColumnLayout {
                                id: aiCapCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.space4
                                spacing: Tokens.space3
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    CapChip { glyph: "article"; text: I18n.tr("Writes reports & ideas"); ok: true }
                                    CapChip { glyph: "travel_explore"; text: I18n.tr("Searches the web"); ok: Settings.isGeminiProvider }
                                    CapChip { glyph: "movie"; text: I18n.tr("Watches the videos"); ok: Settings.isGeminiProvider }
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: Settings.isGeminiProvider
                                          ? I18n.tr("Before writing a CSV report, Gemini watches the channel's best videos — Shorts in full, and the middle minutes of long-form ones. It takes a few minutes and costs quota, and it is what makes the report describe what the videos actually do.")
                                          : I18n.tr("Only Google Gemini can search the web and watch videos. Reports still work with this provider, but they are written from the numbers alone.")
                                    font.pixelSize: Tokens.fontCaption + 1
                                    lineHeight: 1.35
                                    color: Theme.on_surface
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        C.SmartField {
                            id: proxyField
                            label: I18n.tr("PROXY (optional)")
                            icon: "vpn_key"
                            mono: true
                            placeholder: "http://127.0.0.1:10809"
                            helper: I18n.tr("An HTTP proxy for the AI requests only — YouTube calls and downloads don't use it.")
                            onEdited: (v) => Settings.aiProxy = v
                            Binding { target: proxyField; property: "text"; value: Settings.aiProxy; when: !proxyField.focused; restoreMode: Binding.RestoreNone }
                        }
                    }

                    // ═══ DOWNLOAD ENGINE ═══
                    // yt-dlp 2026+ needs a JS runtime (deno/node/…) to pull YouTube
                    // streams; ffmpeg/ffprobe are bundled.
                    SettingsSection {
                        id: secEngine
                        icon: "downloading"
                        title: I18n.tr("Download Engine")
                        subtitle: I18n.tr("What the downloader needs to pull streams from YouTube.")
                        dimmed: !page.matches(4)
                        trailing: [
                            StatusChip {
                                text: Deno.setupBusy ? I18n.tr("Installing …")
                                     : Deno.ready ? I18n.tr("Ready") : I18n.tr("Action needed")
                                tint: Deno.ready && !Deno.setupBusy ? Theme.secondary_container : Theme.warn
                                pulse: Deno.setupBusy
                            }
                        ]

                        GridLayout {
                            Layout.fillWidth: true
                            columns: content.width >= 900 ? 2 : 1
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space4

                            ModuleCard {
                                kicker: I18n.tr("JAVASCRIPT RUNTIME")
                                orbIcon: Deno.available ? "check" : "download"
                                ok: Deno.available
                                busy: Deno.busy
                                title: Deno.busy ? I18n.tr("Installing …")
                                     : Deno.available ? I18n.tr("Ready") : I18n.tr("Not installed")
                                detail: Deno.available
                                        ? I18n.tr("yt-dlp uses it to answer YouTube's player challenge, so streams keep downloading.")
                                        : I18n.tr("Needed to download from YouTube. About 40 MB, one-time.")
                                meta: Deno.available
                                      ? [Deno.runtimeName + " " + Deno.runtimeVersion,
                                         Deno.runtimeSource === "path" ? I18n.tr("found on your system")
                                         : Deno.runtimeSource === "bundled" ? I18n.tr("included with the app")
                                         : I18n.tr("managed by the app")]
                                      : []
                                progress: Deno.busy && Deno.pct > 0 ? Deno.pct / 100 : -1
                                indeterminate: Deno.busy && Deno.pct <= 0
                                C.ActionButton {
                                    compact: true
                                    variant: Deno.available ? "ghost" : "primary"
                                    iconName: "download"
                                    enabled: !Deno.busy && Deno.runtimeSource !== "path"
                                    status: Deno.busy ? 1 : 0
                                    busyText: Deno.pct > 0 ? (Deno.pct + "%") : I18n.tr("Installing …")
                                    text: Deno.available ? I18n.tr("Reinstall") : I18n.tr("Install runtime")
                                    onClicked: Deno.available ? Deno.forceInstall() : Deno.requestInstall()
                                }
                            }

                            ModuleCard {
                                kicker: I18n.tr("DOWNLOADER")
                                orbIcon: "sync"
                                ok: true
                                busy: Deno.updating
                                title: "yt-dlp"
                                detail: I18n.tr("YouTube changes often. If downloads start failing, update first.")
                                meta: [I18n.tr("Updates in place, no reinstall")]
                                C.ActionButton {
                                    compact: true
                                    variant: "ghost"
                                    iconName: "sync"
                                    enabled: !Deno.updating
                                    status: Deno.updating ? 1 : 0
                                    busyText: I18n.tr("Updating…")
                                    text: I18n.tr("Update downloader")
                                    onClicked: Deno.updateYtDlp()
                                }
                            }

                            // v3.41.5: PO Token helper (bgutil-pot, Rust) — REQUIRED,
                            // same as the JS runtime: no on/off switch, and a missing
                            // helper is a warning state that locks downloads.
                            ModuleCard {
                                kicker: I18n.tr("PO TOKEN HELPER")
                                orbIcon: Deno.potInstalled ? "verified" : "download"
                                ok: Deno.potInstalled
                                busy: Deno.potBusy
                                title: Deno.potBusy ? I18n.tr("Installing …")
                                     : !Deno.potInstalled ? I18n.tr("Not installed")
                                     : Deno.potRunning ? I18n.tr("Active") : I18n.tr("Ready")
                                detail: Deno.potInstalled
                                        ? I18n.tr("Proves to YouTube that requests come from a real browser, so downloads don't hit 403 or get stuck at 360p.")
                                        : I18n.tr("Required to download from YouTube. About 44 MB, one-time.")
                                meta: Deno.potInstalled
                                      ? ["bgutil-pot " + (Deno.potSource === "managed" ? Deno.potVersion : ""),
                                         Deno.potSource === "path" ? I18n.tr("found on your system")
                                         : Deno.potSource === "bundled" ? I18n.tr("included with the app")
                                         : I18n.tr("managed by the app")]
                                      : [I18n.tr("Required")]
                                progress: Deno.potBusy && Deno.potPct > 0 ? Deno.potPct / 100 : -1
                                indeterminate: Deno.potBusy && Deno.potPct <= 0
                                Component.onCompleted: Deno.refreshPot()
                                C.ActionButton {
                                    compact: true
                                    variant: Deno.potInstalled ? "ghost" : "primary"
                                    iconName: "download"
                                    enabled: !Deno.potBusy && Deno.potSource !== "path"
                                    status: Deno.potBusy ? 1 : 0
                                    busyText: Deno.potPct > 0 ? (Deno.potPct + "%") : I18n.tr("Installing …")
                                    text: Deno.potInstalled ? I18n.tr("Reinstall") : I18n.tr("Install helper")
                                    onClicked: Deno.installPot()
                                }
                            }
                        }
                    }

                    // ═══ OUTPUT & SCRAPING ═══
                    SettingsSection {
                        id: secOutput
                        icon: "tune"
                        title: I18n.tr("Output & Scraping")
                        subtitle: I18n.tr("How scrapes run, and where their files land.")
                        dimmed: !page.matches(5)
                        trailing: [
                            StatusChip {
                                text: page.outputOk ? I18n.tr("Folder set") : I18n.tr("Pick a save folder")
                                tint: page.outputOk ? Theme.secondary_container : Theme.warn
                            }
                        ]

                        // export format: four tiles instead of a dropdown —
                        // there are only four, and each wants a word of "why".
                        BlockHead {
                            icon: "description"
                            title: I18n.tr("Export Format")
                            detail: I18n.tr("File type written when a scrape finishes.")
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: content.width < 760 ? 2 : 4
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3
                            Repeater {
                                model: Settings.formatLabels
                                FormatTile {
                                    readonly property var parts: String(modelData).match(/^(.*?)\s*\((\.[A-Za-z0-9]+)\)\s*$/)
                                    active: Settings.formatIndex === index
                                    glyph: ["description", "data_array", "grid_view", "data"][index] || "description"
                                    name: parts ? parts[1] : modelData
                                    ext: parts ? parts[2] : ""
                                    caption: index === 0 ? I18n.tr("Opens anywhere")
                                           : index === 1 ? I18n.tr("One record per line, for code")
                                           : index === 2 ? I18n.tr("A ready-made workbook")
                                           : I18n.tr("Query it with SQL")
                                    onClicked: Settings.formatIndex = index
                                }
                            }
                        }

                        RowGroup {
                            Layout.topMargin: Tokens.space2
                            SettingRow {
                                icon: "save"
                                label: I18n.tr("Autosave Checkpoint")
                                description: I18n.tr("Save progress every N videos, so a crash or a quota wall loses nothing.")
                                Segmented {
                                    current: Settings.autosaveIndex
                                    minItemWidth: 52
                                    options: [
                                        { label: "100",  value: 0 },
                                        { label: "500",  value: 1 },
                                        { label: "1000", value: 2 },
                                        { label: I18n.tr("At the end"), value: 3 }
                                    ]
                                    onPicked: (value, btn) => Settings.autosaveIndex = value
                                }
                            }
                            RowSep {}
                            SettingRow {
                                icon: "speed"
                                label: I18n.tr("Worker Threads")
                                description: I18n.tr("Parallel workers while scraping. Higher is faster, and heavier on your connection.")
                                ThreadMeter {
                                    value: Settings.threadCount
                                    onPicked: (v) => Settings.threadCount = v
                                }
                            }
                            RowSep {}
                            SettingRow {
                                icon: "subject"
                                label: I18n.tr("Fetch transcripts while scraping")
                                description: I18n.tr("Richer AI reports, slightly slower scrapes.")
                                C.AppSwitch {
                                    checked: Settings.transcriptsEnabled
                                    onToggled: Settings.transcriptsEnabled = checked
                                }
                            }
                        }

                        // browser cookies: chips, every option visible at once
                        BlockHead {
                            Layout.topMargin: Tokens.space3
                            icon: "language"
                            title: I18n.tr("Browser Cookies (for downloads)")
                            detail: I18n.tr("Borrow a signed-in browser session for age-gated or members-only videos.")
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            Repeater {
                                model: Settings.cookieLabels
                                ChoiceChip {
                                    text: modelData
                                    glyph: index === 0 ? "cancel" : "public"
                                    active: Settings.cookieIndex === index
                                    onClicked: Settings.cookieIndex = index
                                }
                            }
                        }

                        // destination
                        BlockHead {
                            Layout.topMargin: Tokens.space3
                            icon: "folder_open"
                            title: I18n.tr("Default Save Folder")
                            detail: I18n.tr("Where exports and downloads are written.")
                        }
                        Rectangle {
                            id: folderCard
                            Layout.fillWidth: true
                            radius: 16
                            color: folderHover.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark, 0.03) : Theme.input_bg
                            border.width: 1
                            border.color: page.outputOk ? (folderHover.hovered ? Theme.border_med : Theme.border)
                                                        : U.withAlpha(Theme.warn, 0.5)
                            implicitHeight: 74
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            HoverHandler { id: folderHover }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.space3
                                anchors.rightMargin: Tokens.space3
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 48
                                    radius: 14
                                    color: page.outputOk ? U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                                                         : U.withAlpha(Theme.warn, 0.14)
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: page.outputOk ? "folder_open" : "folder_off"
                                        fill: true
                                        size: 22
                                        glyphColor: page.outputOk ? Theme.primary : Theme.warn
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    C.AppText {
                                        text: I18n.tr("SAVE TO")
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Tokens.fontMicro
                                        font.letterSpacing: I18n.rtl ? 0 : 1.1
                                        color: Theme.on_surface_var
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: page.outputOk ? Settings.saveFolder : I18n.tr("Not chosen yet")
                                        mono: page.outputOk
                                        weight: Tokens.weightMedium
                                        font.pixelSize: Tokens.fontBody
                                        color: page.outputOk ? Theme.text_strong : Theme.outline
                                        elide: Text.ElideMiddle
                                        LayoutMirroring.enabled: page.outputOk ? false : I18n.rtl
                                    }
                                }
                                C.IconButton {
                                    visible: page.outputOk
                                    iconName: "content_copy"
                                    implicitWidth: 36; implicitHeight: 36
                                    glyphSize: 16
                                    tip: I18n.tr("Copy path")
                                    onClicked: { Settings.copyToClipboard(Settings.saveFolder); toast.show(I18n.tr("Copied"), "info") }
                                }
                                C.IconButton {
                                    visible: page.outputOk
                                    iconName: "open_in_new"
                                    implicitWidth: 36; implicitHeight: 36
                                    glyphSize: 16
                                    tip: I18n.tr("Open folder")
                                    onClicked: Qt.openUrlExternally(page.folderUrl())
                                }
                                C.ActionButton {
                                    compact: true
                                    variant: page.outputOk ? "ghost" : "primary"
                                    iconName: "folder"
                                    text: page.outputOk ? I18n.tr("Change") : I18n.tr("Browse")
                                    onClicked: folderDialog.open()
                                }
                            }
                            C.AppTooltip { visible: folderHover.hovered && page.outputOk; text: Settings.saveFolder }
                        }

                        // per-kind destinations
                        BlockHead {
                            Layout.topMargin: Tokens.space3
                            icon: "folder"
                            title: I18n.tr("Save Locations")
                            detail: I18n.tr("Pick a separate home for downloaded videos and thumbnails.")
                        }
                        FolderCard {
                            label: I18n.tr("VIDEOS")
                            glyph: "movie"
                            path: Settings.videoFolder
                            fallback: Settings.videoFolderDefault
                            onPick: videoFolderDialog.open()
                            onReset: Settings.setVideoFolder("")
                        }
                        FolderCard {
                            label: I18n.tr("THUMBNAILS")
                            glyph: "image"
                            tint: Theme.secondary_container
                            path: Settings.thumbFolder
                            fallback: ""
                            onPick: thumbFolderDialog.open()
                            onReset: Settings.setThumbFolder("")
                        }
                    }

                    // ═══ BROWSER EXTENSION ═══ (v3.43)
                    // The download button on YouTube. The full install guide
                    // lives here, so it is never lost after "Skip for now".
                    SettingsSection {
                        id: secExtension
                        icon: "extension"
                        title: I18n.tr("Browser extension")
                        subtitle: ExtensionSetup.connected
                                  ? I18n.tr("Installed. Every YouTube video and Short has a Hunter download button.")
                                  : I18n.tr("Adds a Hunter download button to every YouTube video and Short. One-time setup, about a minute.")
                        dimmed: !page.matches(6)
                        trailing: [
                            StatusChip {
                                text: ExtensionSetup.connected ? I18n.tr("Connected") : I18n.tr("Not installed")
                                tint: ExtensionSetup.connected ? Theme.secondary_container : Theme.warn
                            }
                        ]

                        // installed: a short line + the steps folded away
                        // (reinstall / update after an app update)
                        property bool showSteps: !ExtensionSetup.connected
                        Connections {
                            target: ExtensionSetup
                            function onConnectedNow() { secExtension.showSteps = false }
                        }
                        C.PrimaryButton {
                            visible: ExtensionSetup.connected
                            variant: "ghost"
                            iconName: secExtension.showSteps ? "expand_less" : "expand_more"
                            text: secExtension.showSteps ? I18n.tr("Hide the steps")
                                                         : I18n.tr("Reinstall or update the extension")
                            onClicked: secExtension.showSteps = !secExtension.showSteps
                        }
                        C.ExtensionGuide {
                            visible: secExtension.showSteps
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    // ── floating save bar ──
    // Only exists while there is something to save, so "did that stick?" is
    // never a question: the bar is the answer.
    C.GlassPanel {
        id: saveBar
        readonly property bool shown: Settings.isDirty && !Settings.autoSave && page.visible
        width: Math.min(640, scroll.width - Tokens.space6 * 2)
        height: 60
        radius: Tokens.radiusXl
        elevation: 2.2
        x: scroll.x + (scroll.width - width) / 2
        y: shown ? page.height - height - Tokens.space5 : page.height + 24
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        z: 100
        border.color: U.mix(Theme.border, Theme.warn, 0.35)
        Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space5
            anchors.rightMargin: Tokens.space2 + 2
            spacing: Tokens.space2

            Rectangle {
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                radius: 5
                color: Theme.warn
                SequentialAnimation on opacity {
                    running: saveBar.shown && page._motion && page.visible && Tokens.appActive
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                C.AppText {
                    text: I18n.tr("You have unsaved changes")
                    weight: Tokens.weightBold
                    color: Theme.text_strong
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                C.AppText {
                    text: I18n.tr("Ctrl+S to save")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                }
            }
            C.PrimaryButton {
                variant: "ghost"
                text: I18n.tr("Discard")
                iconName: "restart_alt"
                implicitHeight: 42
                onClicked: page.discard()
            }
            C.PrimaryButton {
                text: I18n.tr("Save changes")
                iconName: "save"
                implicitHeight: 42
                onClicked: page.save()
            }
        }
    }

    C.Toast {
        id: toast
        x: scroll.x + (scroll.width - width) / 2
        y: parent.height - (saveBar.shown ? 150 : 80)
        Behavior on y { NumberAnimation { duration: Tokens.durMed } }
    }
}
