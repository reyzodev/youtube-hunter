import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import NicheScope
import "../components" as C
import "../Utils.js" as U

// AI Chat — "Hunter", the studio partner (v3.14; renamed from "Scope" in the launch-screen v3 rebrand).
//
// Design plan (kept here so later edits can check the render against it):
//   * Subject — a producer you talk to about YOUR data: outlier videos,
//     exports, thumbnails. The job: leave with something filmable.
//   * Layout — [conversations 284] [the conversation ≤ 780]. (The v3.14
//     Context panel is gone: attachments ride on the messages they came
//     with, and the composer chips are the only place to drop one.)
//     Assistant turns are unboxed prose; user turns are tight bubbles; the
//     composer floats as one glass instrument over the end of the thread.
//   * Colour — Graphite + the live accent used as a studio TALLY LIGHT only:
//     live state, outliers, the send key. Mint = ready, amber = missing
//     transcript, tertiary = the model.
//   * Signature — the mark (C.HunterAvatar, v1.0.4; was C.HunterSigil): the Hunter crest on an accent tile
//     that breathes when idle, hunts while thinking, locks on while streaming.
//   * Multitool — the + unfolds every way to bring data in (Niche Finder,
//     Archive, a YouTube link, files, Google Drive, images).
Item {
    id: page
    // v3.40.1: converted once per change. Each thread row used to read
    // Chat.threads[index - 1], i.e. convert the WHOLE list from Python once
    // per row (O(n²)) the moment the rail was first laid out.
    readonly property var _threads: Chat.threads
    // v3.40.7: same fix for the messages. Every bubble's `lastUser` read
    // Chat.messages, i.e. converted the WHOLE chat (all parts, all idea cards)
    // from Python once per bubble, on every chat switch. Now: once per change.
    readonly property var _msgs: Chat.messages
    readonly property int _lastUserIdx: {
        var ms = page._msgs
        for (var i = ms.length - 1; i >= 0; i--)
            if (ms[i].role === "user") return i
        return -1
    }
    // GPU path available? (snapshot cross-fade + shared lens need it)
    readonly property bool _gpu: GraphicsInfo.api !== GraphicsInfo.Software

    // ── responsive panes ──
    readonly property bool wide: width >= 1240
    readonly property bool medium: width >= 900
    property bool railOpen: true
    onMediumChanged: railOpen = medium
    readonly property int railW: 284
    readonly property bool railDocked: medium && railOpen

    // editing the last user message?
    property bool editing: false
    readonly property bool _motion: App.ambientMotion === undefined || App.ambientMotion

    Connections {
        target: Chat
        function onToast(msg, kind) { toast.show(msg, kind) }
        function onScrollToEnd() { if (!page._swapping && !page._settling) scrollTimer.restart() }
        function onThreadChanged() { page.editing = false; titleEdit.visible = false }
    }
    Timer { id: scrollTimer; interval: 30; onTriggered: { msgWheel.cancel(); msgList.positionViewAtEnd() } }

    // ── v3.40.6: conversation switch as a real cross-fade ──
    //   v3.40.3 faded out first   -> half-second lag
    //   v3.40.4 hid the pane      -> black frame while the swap worked
    //   v3.40.5 instant swap      -> no lag, but a hard cut
    // Now: the click takes a GPU snapshot of the current chat and lays it on
    // top (so the screen never goes blank), the swap happens underneath,
    // already pinned to the last message, and then the snapshot drifts away
    // while the new chat glides in from the direction you moved in the list.
    property real _pane: 1.0          // new chat: 0 → 1
    property real _old: 0.0           // snapshot of the old chat: 1 → 0
    property int _dir: 1              // +1 moved down the list, -1 up
    property bool _settling: false
    property bool _swapping: false
    property var _swapFn: null
    property bool _armSwap: false
    readonly property int _drift: 18

    function swapThread(fn, dir) {
        page._dir = dir || 1
        if (!page._motion || !page.visible || !page._gpu) { page._swapFn = fn; page._doSwap(false); return }
        xfade.stop()
        page._swapFn = fn
        page._swapping = true
        // freeze what is on screen right now
        snap.sourceItem = msgList.visible ? msgList : empty
        snap.scheduleUpdate()
        page._old = 1
        // swap right after that snapshot frame is on screen
        page._armSwap = true
        swapFallback.restart()
    }
    function _doSwap(animate) {
        page._armSwap = false
        swapFallback.stop()
        page._settling = true
        msgWheel.cancel()
        scrollTimer.stop()
        var fn = page._swapFn
        page._swapFn = null
        if (animate) page._pane = 0
        if (fn) fn()
        msgList.follow = true
        msgList.forceLayout()
        msgList.positionViewAtEnd()
        page._swapping = false
        if (animate) xfade.restart(); else { page._pane = 1; page._old = 0 }
        settleTimer.restart()
        cacheRestore.restart()
    }
    function openThreadSmooth(tid) {
        if (tid === Chat.threadId && Chat.hasMessages) return
        var from = -1, to = -1, ts = page._threads
        for (var i = 0; i < ts.length; i++) {
            if (ts[i].id === Chat.threadId) from = i
            if (ts[i].id === tid) to = i
        }
        page.swapThread(function() { Chat.openThread(tid) }, (from >= 0 && to < from) ? -1 : 1)
    }
    Connections {
        target: page.Window.window
        enabled: page._armSwap
        function onFrameSwapped() { if (page._armSwap) { page._armSwap = false; Qt.callLater(page._doSwap, true) } }
    }
    // safety net if no frame is swapped (window hidden, etc.)
    Timer { id: swapFallback; interval: 60; onTriggered: if (page._armSwap) page._doSwap(true) }
    ParallelAnimation {
        id: xfade
        NumberAnimation { target: page; property: "_old"; to: 0; duration: 170; easing.type: Easing.OutQuad }
        SequentialAnimation {
            PauseAnimation { duration: 40 }
            NumberAnimation { target: page; property: "_pane"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        }
    }
    // keep the view pinned to the end while late bubbles (markdown/images) settle
    Timer { id: settleTimer; interval: 320; onTriggered: page._settling = false }
    // build the off-screen messages only once the new chat is already on screen
    Timer { id: cacheRestore; interval: 400 }

    // v3.40.1: reloadConfig() re-reads the config file and re-evaluates every
    // binding on Chat.modelGroups / profileChoices / ... (each re-reads the file
    // again). It used to run in the SAME frame the page fades in, and twice on
    // the first visit (onCompleted + onVisible). Now it runs once, right after
    // the entrance animation, so the fade itself stays smooth.
    Timer { id: cfgReload; interval: Tokens.durPage + 40; repeat: false; onTriggered: Chat.reloadConfig() }
    onVisibleChanged: if (visible) { cfgReload.restart(); composerInput.forceActiveFocus() }
    Component.onCompleted: { if (!visible) Chat.reloadConfig(); railOpen = medium }

    function sendNow() {
        var t = composerInput.text
        if (Chat.busy) return
        if (page.editing) {
            if (t.trim() === "") return
            Chat.editLast(t)
            page.editing = false
        } else {
            if (t.trim() === "" && Chat.pending.length === 0) return
            Chat.send(t)
        }
        composerInput.text = ""
    }
    function kfmt(n) { return (n / 1000).toFixed(1) }
    function multTone(m) { return m >= 50 ? 2 : m >= 10 ? 1 : 0 }
    function groupLabel(g) {
        return g === "pinned" ? I18n.tr("Pinned") : g === "today" ? I18n.tr("Today")
             : g === "week" ? I18n.tr("This week") : I18n.tr("Earlier")
    }
    function kindColor(k) {
        return k === "video" ? Theme.primary : k === "table" ? Theme.secondary_container
             : k === "doc" ? Theme.tertiary : k === "image" ? Theme.warn
             : k === "brief" ? Theme.tertiary : Theme.on_surface_var
    }
    function kindIcon(k) {
        return k === "video" ? "smart_display" : k === "table" ? "data" : k === "doc" ? "article"
             : k === "image" ? "image" : k === "brief" ? "page_insights" : "description"
    }

    Rectangle { anchors.fill: parent; color: Theme.background }

    // ═══ small building blocks ═══
    component Hairline: Rectangle { color: Theme.border; implicitWidth: 1; implicitHeight: 1 }

    // v1.0.4: size of Hunter's mark in the message header (was 28)
    readonly property int _avatarSize: 30

    // v1.0.4: does this text read right-to-left? Decided by its first strong
    // letter (Persian/Arabic/Hebrew -> true, Latin -> false), skipping markdown
    // marks, digits and emoji, exactly the way Text picks its own alignment.
    // The UI chrome stays English; only Hunter's header row follows the answer.
    function _isRtl(s) {
        s = String(s || "")
        var n = Math.min(s.length, 600)
        for (var i = 0; i < n; i++) {
            var c = s.charCodeAt(i)
            if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF))
                return true
            if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0xC0 && c <= 0x024F))
                return false
        }
        return false
    }
    function _partsRtl(parts) {
        if (!parts) return false
        for (var i = 0; i < parts.length; i++) {
            var p = parts[i]
            if (p && p.type !== "ideas" && p.type !== "next" && p.text) return page._isRtl(p.text)
        }
        return false
    }
    // before the first token of a live answer, follow the question's language
    readonly property bool _liveRtl: Chat.streamText !== ""
                                     ? _isRtl(Chat.streamText)
                                     : (_lastUserIdx >= 0 && _msgs[_lastUserIdx] ? _isRtl(_msgs[_lastUserIdx].text) : false)

    // v1.0.4: the line next to Hunter's mark on every answer —
    //   Hunter  [● free / gemini-3.8-flash]  01:25
    // The model sits in a quiet mono chip (route prefix dimmed) instead of a
    // run of grey text, so the name leads and the meta reads as meta.
    component AuthorMeta: Row {
        id: am
        property string model: ""
        property string time: ""
        property bool live: false
        // RTL answer: Hunter on the right, then the model chip, then the time
        property bool rtl: false
        layoutDirection: rtl ? Qt.RightToLeft : Qt.LeftToRight
        readonly property int _cut: model.lastIndexOf("/")
        readonly property string _route: _cut > 0 ? model.substring(0, _cut) : ""
        readonly property string _name: _cut > 0 ? model.substring(_cut + 1) : model
        spacing: 8
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        LayoutMirroring.enabled: false

        C.AppText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Hunter"
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontLabel
            font.letterSpacing: -0.2
            color: Theme.text_strong
        }
        Rectangle {
            visible: am.model !== ""
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 22
            implicitWidth: chipRow.implicitWidth + 16
            radius: Tokens.radiusPill
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.045 : 0.035)
            border.width: 1
            border.color: Theme.border
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                // the model id is Latin; it always reads left-to-right
                layoutDirection: Qt.LeftToRight
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3
                    color: am.live ? Theme.primary : Theme.secondary_container
                    SequentialAnimation on opacity {
                        running: am.live && am.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
                C.AppText {
                    visible: am._route !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: am._route + " /"
                    mono: true
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.outline
                }
                C.AppText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: am._name
                    mono: true
                    font.pixelSize: Tokens.fontMicro
                    weight: Tokens.weightMedium
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 260)
                }
            }
        }
        C.AppText {
            visible: am.time !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: am.time
            font.pixelSize: Tokens.fontCaption
            color: Theme.outline
        }
    }

    component Pill: Rectangle {
        id: pill
        property string icon: ""
        property string text: ""
        property color tone: Theme.on_surface_var
        property color fill: Theme.surface_highest
        implicitHeight: 28
        implicitWidth: pillRow.implicitWidth + 20
        radius: Tokens.radiusPill
        color: pill.fill
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            C.IconGlyph { visible: pill.icon !== ""; name: pill.icon; size: 14; glyphColor: pill.tone; anchors.verticalCenter: parent.verticalCenter }
            C.AppText { text: pill.text; color: pill.tone; font.pixelSize: Tokens.fontCaption; weight: Tokens.weightDemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    component MultBadge: Rectangle {
        id: mb
        property real mult: 0
        property string label: ""
        readonly property int tone: page.multTone(mult)
        visible: label !== ""
        implicitHeight: 22
        implicitWidth: mbText.implicitWidth + 14
        radius: 7
        color: tone === 2 ? Theme.primary : tone === 1 ? U.withAlpha(Theme.primary, 0.16) : Theme.surface_highest
        LayoutMirroring.enabled: false
        C.AppText {
            id: mbText
            anchors.centerIn: parent
            text: mb.label
            mono: true
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontCaption
            color: mb.tone === 2 ? Theme.on_primary : mb.tone === 1 ? U.mix(Theme.primary, Theme.text_strong, 0.35) : Theme.on_surface_var
        }
    }

    // A quiet text+icon action (Copy · Regenerate · Send to AI Ideas).
    component Ghost: AbstractButton {
        id: gh
        property string glyph: ""
        property bool accent: false
        implicitHeight: 32
        implicitWidth: ghRow.implicitWidth + 20
        hoverEnabled: true
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: Tokens.radiusSm
            color: gh.hovered ? (gh.accent ? U.withAlpha(Theme.primary, 0.10) : U.withAlpha(Theme.on_surface, 0.07)) : U.withAlpha((gh.accent ? U.withAlpha(Theme.primary, 0.10) : U.withAlpha(Theme.on_surface, 0.07)), 0)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            Row {
                id: ghRow
                anchors.centerIn: parent
                spacing: 6
                C.IconGlyph { name: gh.glyph; size: 15; glyphColor: gh.accent ? Theme.primary : (gh.hovered ? Theme.on_surface : Theme.on_surface_var); anchors.verticalCenter: parent.verticalCenter }
                C.AppText { text: gh.text; weight: Tokens.weightDemiBold; font.pixelSize: Tokens.fontCaption; color: gh.accent ? Theme.primary : (gh.hovered ? Theme.on_surface : Theme.on_surface_var); anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // A chip for an attached source (composer + under a user bubble).
    component AttChip: Rectangle {
        id: chip
        property var src: ({})
        property bool removable: false
        signal removeRequested(string key)
        implicitHeight: 38
        implicitWidth: Math.min(280, chipRow.implicitWidth + 14)
        radius: Tokens.radiusMd
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        RowLayout {
            id: chipRow
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: chip.removable ? 4 : 10
            spacing: 8
            Loader {
                Layout.preferredWidth: (chip.src.kind === "video" || chip.src.kind === "image") ? 46 : 30
                Layout.preferredHeight: 30
                sourceComponent: (chip.src.kind === "video" || chip.src.kind === "image") ? chipThumb : chipIcon
                Component { id: chipThumb; C.RoundThumb { source: chip.src.thumbSrc || ""; radius: 7; glyph: page.kindIcon(chip.src.kind) } }
                Component {
                    id: chipIcon
                    Rectangle {
                        radius: 8; color: Theme.surface_highest
                        C.IconGlyph { anchors.centerIn: parent; name: page.kindIcon(chip.src.kind); size: 16; glyphColor: page.kindColor(chip.src.kind) }
                    }
                }
            }
            C.AppText {
                Layout.fillWidth: true
                Layout.maximumWidth: 170
                text: chip.src.title || ""
                elide: Text.ElideRight
                font.pixelSize: Tokens.fontCaption
                weight: Tokens.weightMedium
                color: Theme.on_surface
            }
            MultBadge { mult: chip.src.mult || 0; label: chip.src.multLabel || "" }
            Rectangle {
                visible: chip.src.status === "reading"
                Layout.preferredWidth: 14; Layout.preferredHeight: 14
                radius: 7; color: "transparent"
                border.width: 2; border.color: Theme.border_med
                Rectangle { width: 4; height: 4; radius: 2; color: Theme.primary; x: 5; y: -1 }
                RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: chip.src.status === "reading" && chip.visible }
            }
            C.IconButton {
                visible: chip.removable
                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                iconName: "close"; glyphSize: 13; chromeless: true
                onClicked: chip.removeRequested(chip.src.key)
            }
        }
    }

    // Spinner / check dot for the thinking steps.
    component StepDot: Item {
        id: sd
        property bool done: false
        width: 18; height: 18
        Rectangle {
            anchors.fill: parent; radius: 9
            visible: sd.done
            color: U.withAlpha(Theme.secondary_container, 0.16)
            C.IconGlyph { anchors.centerIn: parent; name: "check"; size: 12; glyphColor: Theme.secondary_container }
        }
        Rectangle {
            anchors.fill: parent; radius: 9
            visible: !sd.done
            color: "transparent"
            border.width: 2; border.color: Theme.border_med
            Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.primary; x: 6.5; y: -1.5 }
            RotationAnimator on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: !sd.done && sd.visible }
        }
    }

    // One idea card from a ```ideas block.
    component IdeaCard: Rectangle {
        id: ic
        property var item: ({})
        implicitHeight: icCol.implicitHeight + 32
        radius: 18
        color: Theme.surface
        border.width: 1
        border.color: icHover.hovered ? Theme.border_med : Theme.border
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        HoverHandler { id: icHover }
        transform: Translate { id: icLift; y: icHover.hovered ? -1 : 0 }
        // keep the hit box on the resting footprint too (see LiftMask.qml) —
        // without this the card's own 1px lift moves its hit box out from under
        // a resting pointer and the hover flickers on and off every frame.
        containmentMask: C.LiftMask { target: ic; dy: icLift.y }
        ColumnLayout {
            id: icCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 16
            anchors.leftMargin: 18; anchors.rightMargin: 18
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                C.AppText {
                    Layout.fillWidth: true
                    text: ic.item.title || ""
                    wrapMode: Text.Wrap
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    lineHeight: 1.25
                }
                Pill { visible: (ic.item.format || "") !== ""; icon: "movie"; text: ic.item.format || ""; Layout.alignment: Qt.AlignTop }
            }
            // what the video actually is — the part a producer needs to make it
            C.AppText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: text !== ""
                text: ic.item.concept || ""
                wrapMode: Text.Wrap
                color: Theme.on_surface
                lineHeight: 1.4
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: (ic.item.hook || "") !== ""
                spacing: 10
                C.AppText { text: I18n.tr("Hook"); color: Theme.primary; weight: Tokens.weightBold; font.pixelSize: Tokens.fontCaption; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                C.AppText { Layout.fillWidth: true; text: ic.item.hook || ""; wrapMode: Text.Wrap; color: Theme.on_surface; font.pixelSize: Tokens.fontBody; lineHeight: 1.35 }
            }
            C.AppText {
                Layout.fillWidth: true
                visible: text !== ""
                text: ic.item.why || ""
                wrapMode: Text.Wrap
                color: Theme.on_surface_var
                lineHeight: 1.35
            }
            // the sources this idea rests on — exactly what Build in AI Ideas carries
            RowLayout {
                Layout.fillWidth: true
                visible: (ic.item.refTitles || []).length > 0
                spacing: 8
                C.IconGlyph { name: "smart_display"; size: 14; glyphColor: Theme.outline; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("Built on: {t}").replace("{t}", (ic.item.refTitles || []).join(" · "))
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.outline
                    font.pixelSize: Tokens.fontCaption
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Rectangle {
                    Layout.preferredWidth: 90; Layout.preferredHeight: 5
                    radius: 3; color: Theme.surface_highest
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, ic.item.score || 0)) / 100
                        height: parent.height; radius: 3
                        color: Theme.primary
                    }
                }
                C.AppText {
                    text: I18n.tr("Confidence {n}%").replace("{n}", ic.item.score || 0)
                    color: Theme.on_surface_var
                    font.pixelSize: Tokens.fontCaption
                }
                Item { Layout.fillWidth: true }
                Ghost { glyph: "content_copy"; text: I18n.tr("Copy"); onClicked: Chat.copyText(Chat.ideaAsBrief(ic.item)) }
                Ghost {
                    glyph: "lightbulb"; accent: true
                    text: I18n.tr("Build in AI Ideas")
                    // The whole idea travels — brief, the source videos it was
                    // built on (ticked as references), the exports, the format
                    // and the chat's real data — not just its title in
                    // "My idea only" mode, which produced unrelated blueprints.
                    onClicked: {
                        Ideas.importFromChat(Chat.ideaHandoff(ic.item))
                        App.goto(6)
                    }
                }
            }
        }
    }

    // Markdown body. Qt's Markdown (md4c) handles headings, lists, bold, code
    // and GFM tables; the size/colour come from here.
    component MdText: Text {
        textFormat: Text.MarkdownText
        wrapMode: Text.Wrap
        color: Theme.on_surface
        linkColor: Theme.primary
        font.family: Fonts.familyFor("body", Tokens.weightRegular, text)
        font.pixelSize: 16
        lineHeight: 1.45
        renderType: Text.NativeRendering
        onLinkActivated: (link) => Qt.openUrlExternally(link)
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Conversations rail
    // ═══════════════════════════════════════════════════════════════════
    Rectangle {
        id: rail
        z: page.railDocked ? 1 : 30
        width: page.railW
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: page.railOpen ? 0 : -page.railW - 2
        Behavior on anchors.leftMargin { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
        visible: anchors.leftMargin > -page.railW - 1
        color: Theme.sidebar_bg
        Hairline { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1 }
        layer.enabled: !page.railDocked && page.railOpen
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.4; shadowColor: "black" }

        ColumnLayout {
            anchors.fill: parent
            anchors.rightMargin: 1
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.bottomMargin: 10
                spacing: 8
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("Conversations")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                }
                AbstractButton {
                    id: newBtn
                    implicitHeight: 34
                    implicitWidth: newRow.implicitWidth + 22
                    hoverEnabled: true
                    onClicked: { page.swapThread(function() { Chat.newThread() }, -1); composerInput.forceActiveFocus(); if (!page.medium) page.railOpen = false }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    scale: pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                    background: Rectangle {
                        radius: 10
                        color: newBtn.hovered ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                        // v3.40.1: the accent glow is three nested translucent
                        // plates (same trick as GlassPanel's halo) instead of a
                        // MultiEffect layer: no offscreen texture, no shader to
                        // build on the page's first frame.
                        Repeater {
                            model: 3
                            Rectangle {
                                z: -1
                                readonly property int g: 3 + index * 3
                                x: -g; y: -g + 4
                                width: parent.width + 2 * g; height: parent.height + 2 * g
                                radius: 10 + g
                                color: U.withAlpha(Theme.primary, [0.14, 0.08, 0.04][index])
                            }
                        }
                    }
                    contentItem: Item {
                        Row {
                            id: newRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.IconGlyph { name: "add"; size: 16; glyphColor: Theme.on_primary; anchors.verticalCenter: parent.verticalCenter }
                            C.AppText { text: I18n.tr("New chat"); color: Theme.on_primary; weight: Tokens.weightBold; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }

            // search
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.bottomMargin: 6
                implicitHeight: 38
                radius: Tokens.radiusMd
                color: Theme.input_bg
                border.width: 1
                border.color: searchField.activeFocus ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 6
                    spacing: 8
                    C.IconGlyph { name: "search"; size: 16; glyphColor: Theme.outline }
                    TextField {
                        id: searchField
                        // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                        T.ContextMenu.menu: C.EditMenu { editor: searchField }
                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                        selectedTextColor: Theme.text_strong
                        Layout.fillWidth: true
                        background: null
                        padding: 0
                        color: Theme.on_surface
                        placeholderText: I18n.tr("Search conversations")
                        placeholderTextColor: Theme.outline
                        font.family: Fonts.familyFor("body", Tokens.weightRegular, text)
                        font.pixelSize: Tokens.fontBody
                        selectByMouse: true
                        onTextChanged: searchDebounce.restart()
                        Timer { id: searchDebounce; interval: 220; onTriggered: Chat.search = searchField.text }
                    }
                    C.IconButton {
                        visible: searchField.text !== ""
                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                        iconName: "close"; glyphSize: 13; chromeless: true
                        onClicked: searchField.text = ""
                    }
                }
            }

            ListView {
                id: threadList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: page._threads
                spacing: 2
                leftMargin: 8; rightMargin: 8; bottomMargin: 12
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                C.SmoothWheel { flick: threadList; step: 90 }

                C.AppText {
                    anchors.centerIn: parent
                    visible: threadList.count === 0
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Chat.search !== "" ? I18n.tr("Nothing found.") : I18n.tr("Your conversations will show up here.")
                    color: Theme.outline
                }

                delegate: Column {
                    id: trow
                    width: threadList.width - 16
                    readonly property bool firstOfGroup: index === 0 || page._threads[index - 1].group !== modelData.group
                    readonly property bool current: modelData.id === Chat.threadId
                    C.AppText {
                        visible: trow.firstOfGroup
                        // v3.40.1: keyed off firstOfGroup, NOT `visible`. Reading
                        // `visible` reads the EFFECTIVE visibility (the whole
                        // parent chain), which flips while the async page build
                        // and the ListView lay out, and re-enters this binding:
                        // the "Binding loop detected for property height".
                        height: trow.firstOfGroup ? implicitHeight + 16 : 0
                        leftPadding: 10
                        topPadding: index === 0 ? 4 : 12
                        text: page.groupLabel(modelData.group)
                        color: Theme.outline
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                    }
                    Rectangle {
                        id: tcard
                        width: parent.width
                        height: 54
                        radius: Tokens.radiusMd
                        // v3.40.8: no colour fade here any more. The old one ran
                        // surface_highest (opaque dark grey) -> on_surface @ 0 alpha
                        // (WHITE, invisible); ColorAnimation mixes straight RGBA, so the
                        // row that lost "current" flashed a LIGHT grey halfway through:
                        // the blink on every chat switch. Two fixed-colour layers whose
                        // OPACITY fades instead can never pass through a third colour.
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: U.withAlpha(Theme.on_surface, 0.05)
                            opacity: tHover.hovered && !trow.current ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Theme.surface_highest
                            opacity: trow.current ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                        }
                        // v3.40.7: rest the pointer on a row for a moment and its chat is
                        // built in the background; the click then just shows it.
                        HoverHandler {
                            id: tHover
                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: if (hovered && !trow.current) pfDwell.restart(); else pfDwell.stop()
                        }
                        Timer { id: pfDwell; interval: 70; onTriggered: Chat.prefetchThread(modelData.id) }
                        // ...and it opens on PRESS, not release (~100 ms sooner). Presses
                        // on the pin / delete buttons are left to those buttons.
                        TapHandler {
                            onPressedChanged: {
                                if (!pressed) return
                                var p = tActions.mapFromItem(tcard, point.position.x, point.position.y)
                                if (tActions.visible && tActions.contains(p)) return
                                page.openThreadSmooth(modelData.id)
                                if (!page.medium) page.railOpen = false
                            }
                        }
                        // tally light
                        Rectangle {
                            id: tally
                            x: 10; y: 14
                            width: 6; height: 6; radius: 3
                            color: (trow.current || modelData.live) ? Theme.primary : Theme.border_med
                            SequentialAnimation on opacity {
                                running: modelData.live === true && page.visible && Tokens.appActive
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                        Rectangle {
                            visible: trow.current
                            anchors.centerIn: tally
                            width: 12; height: 12; radius: 6
                            color: U.withAlpha(Theme.primary, 0.18)
                        }
                        Column {
                            anchors.left: tally.right; anchors.leftMargin: 10
                            anchors.right: parent.right; anchors.rightMargin: tHover.hovered ? 64 : 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            C.AppText {
                                width: parent.width
                                text: modelData.title
                                elide: Text.ElideRight
                                weight: Tokens.weightDemiBold
                                color: trow.current ? Theme.text_strong : Theme.on_surface
                            }
                            C.AppText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: modelData.when
                                      + (modelData.srcCount > 0 ? " · " + I18n.tr("{n} sources").replace("{n}", modelData.srcCount) : "")
                                      + (modelData.msgCount > 0 ? " · " + I18n.tr("{n} msgs").replace("{n}", modelData.msgCount) : "")
                                color: Theme.outline
                                font.pixelSize: Tokens.fontCaption
                            }
                        }
                        Row {
                            id: tActions
                            visible: tHover.hovered
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            C.IconButton {
                                width: 28; height: 28; chromeless: true; glyphSize: 15
                                iconName: modelData.pinned ? "bookmark" : "bookmark_border"
                                iconFill: modelData.pinned
                                active: modelData.pinned
                                accent: modelData.pinned ? Theme.primary : Theme.on_surface_var
                                tip: modelData.pinned ? I18n.tr("Unpin") : I18n.tr("Pin")
                                onClicked: Chat.pinThread(modelData.id, !modelData.pinned)
                            }
                            C.IconButton {
                                width: 28; height: 28; chromeless: true; glyphSize: 15
                                iconName: "delete_outline"
                                tip: I18n.tr("Delete")
                                onClicked: confirmDelete.ask(modelData.id, modelData.title)
                            }
                        }
                    }
                }
            }

            // provider card
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 12
                implicitHeight: 60
                radius: Tokens.radiusLg
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 6
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 34; Layout.preferredHeight: 34
                        radius: 10; color: Theme.surface_highest
                        C.IconGlyph { anchors.centerIn: parent; name: "auto_awesome"; size: 17; glyphColor: Theme.tertiary }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Row {
                            spacing: 6
                            Rectangle {
                                width: 7; height: 7; radius: 3.5
                                anchors.verticalCenter: parent.verticalCenter
                                color: Chat.hasAiKey ? Theme.secondary_container : Theme.warn
                            }
                            C.AppText {
                                text: Chat.hasAiKey ? I18n.tr("Connected · {p}").replace("{p}", Chat.providerLabel) : I18n.tr("No AI key yet")
                                color: Theme.on_surface_var
                                font.pixelSize: Tokens.fontCaption
                            }
                        }
                        C.AppText {
                            width: parent.width
                            text: Chat.modelName
                            elide: Text.ElideRight
                            weight: Tokens.weightBold
                            color: Theme.text_strong
                        }
                    }
                    C.IconButton {
                        Layout.preferredWidth: 32; Layout.preferredHeight: 32
                        iconName: "settings"; glyphSize: 16; chromeless: true
                        tip: I18n.tr("AI settings")
                        onClicked: App.goto(10)
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  The conversation
    // ═══════════════════════════════════════════════════════════════════
    Item {
        id: chatCol
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: page.railDocked ? page.railW : 0
        Behavior on anchors.leftMargin { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
        readonly property int colW: Math.min(780, width - 56)

        // header
        Item {
            id: head
            z: 3
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 60
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.bottom
                height: 24
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.background }
                    GradientStop { position: 1; color: U.withAlpha(Theme.background, 0) }
                }
            }
            Rectangle { anchors.fill: parent; color: Theme.background }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16; anchors.rightMargin: 16
                spacing: 8
                C.IconButton {
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36
                    iconName: page.railOpen ? "sidebar_fold" : "sidebar_unfold"; glyphSize: 18
                    active: page.railOpen
                    tip: I18n.tr("Conversations")
                    onClicked: page.railOpen = !page.railOpen
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    C.AppText {
                        id: titleText
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !titleEdit.visible
                        text: Chat.threadTitle
                        elide: Text.ElideRight
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontSubtitle
                        color: Theme.text_strong
                        TapHandler {
                            enabled: Chat.threadId > 0
                            onDoubleTapped: { titleEdit.text = Chat.threadTitle; titleEdit.visible = true; titleEdit.forceActiveFocus(); titleEdit.selectAll() }
                        }
                    }
                    TextField {
                        id: titleEdit
                        // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                        T.ContextMenu.menu: C.EditMenu { editor: titleEdit }
                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                        selectedTextColor: Theme.text_strong
                        visible: false
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 38
                        color: Theme.text_strong
                        font.family: Fonts.familyFor("body", Tokens.weightExtraBold, text)
                        font.weight: Fonts.weightFor(Tokens.weightExtraBold, text)
                        font.pixelSize: Tokens.fontSubtitle
                        selectByMouse: true
                        leftPadding: 10; rightPadding: 10
                        background: Rectangle { radius: Tokens.radiusSm; color: Theme.input_bg; border.width: 1; border.color: U.withAlpha(Theme.primary, 0.45) }
                        function commit() { if (visible) { Chat.renameThread(Chat.threadId, text); visible = false } }
                        onAccepted: commit()
                        onActiveFocusChanged: if (!activeFocus) commit()
                        Keys.onEscapePressed: visible = false
                    }
                }
                C.IconButton {
                    visible: Chat.threadId > 0
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36
                    iconName: "edit"; glyphSize: 16
                    tip: I18n.tr("Rename")
                    onClicked: { titleEdit.text = Chat.threadTitle; titleEdit.visible = true; titleEdit.forceActiveFocus(); titleEdit.selectAll() }
                }
                C.IconButton {
                    visible: Chat.hasMessages
                    Layout.preferredWidth: 36; Layout.preferredHeight: 36
                    iconName: "ios_share"; glyphSize: 16
                    tip: I18n.tr("Export as Markdown")
                    onClicked: exportDialog.open()
                }
            }
        }

        // ── empty state ──
        Item {
            id: empty
            anchors.top: head.bottom
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: dock.top
            visible: !Chat.hasMessages && !Chat.streamingHere
            opacity: page._pane
            transform: Translate { y: (1 - page._pane) * page._drift * page._dir }
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(680, parent.width - 48)
                spacing: 0
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: heroLens.width; Layout.preferredHeight: heroLens.height
                    Layout.bottomMargin: 22
                    // v3.40.1: the soft glow behind the lens is a radial
                    // gradient now (same look as the old disc + 64px blur, which
                    // was the most expensive thing on this page's first frame).
                    Shape {
                        id: heroGlow
                        anchors.centerIn: parent
                        readonly property real _d: parent.width * 1.9
                        readonly property real _R: _d / 2 + 64
                        readonly property color _c: Theme.primary
                        readonly property real _a: Theme.isDark ? 0.10 : 0.06
                        width: _R * 2; height: _R * 2
                        ShapePath {
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillGradient: RadialGradient {
                                centerX: heroGlow._R; centerY: heroGlow._R; centerRadius: heroGlow._R
                                focalX: heroGlow._R; focalY: heroGlow._R; focalRadius: 0
                                GradientStop { position: 0.0; color: U.withAlpha(heroGlow._c, heroGlow._a) }
                                GradientStop { position: Math.max(0.05, (heroGlow._d / 2 - 64) / heroGlow._R); color: U.withAlpha(heroGlow._c, heroGlow._a * 0.92) }
                                GradientStop { position: (heroGlow._d / 2) / heroGlow._R; color: U.withAlpha(heroGlow._c, heroGlow._a * 0.5) }
                                GradientStop { position: 1.0; color: U.withAlpha(heroGlow._c, 0) }
                            }
                            startX: 0; startY: 0
                            PathLine { x: heroGlow.width; y: 0 }
                            PathLine { x: heroGlow.width; y: heroGlow.height }
                            PathLine { x: 0; y: heroGlow.height }
                            PathLine { x: 0; y: 0 }
                        }
                    }
                    C.HunterAvatar {
                        id: heroLens
                        anchors.centerIn: parent
                        size: Math.round(Math.max(96, Math.min(150, empty.height * 0.22)))
                        breathe: true
                        mode: "idle"
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: I18n.tr("What are we <font color=\"{c}\">making</font> today?").replace("{c}", Theme.primary)
                    font.family: Fonts.familyFor("body", Tokens.weightExtraBold, text)
                    font.weight: Fonts.weightFor(Tokens.weightExtraBold, text)
                    font.pixelSize: Math.round(Math.max(30, Math.min(48, empty.width / 16)))
                    color: Theme.text_strong
                    renderType: Text.NativeRendering
                }
                C.AppText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 30
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !Chat.hasAiKey ? I18n.tr("Connect an AI provider in Settings to start.")
                         : Chat.sources.length > 0 ? I18n.tr("Your sources are ready. Ask away.")
                         : I18n.tr("Hand me a video, an export or a thumbnail — I answer with numbers.")
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.on_surface_var
                }
                C.PrimaryButton {
                    visible: !Chat.hasAiKey
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 24
                    iconName: "key"
                    text: I18n.tr("Open AI settings")
                    onClicked: App.goto(10)
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: empty.width >= 640 ? 2 : 1
                    columnSpacing: 10; rowSpacing: 10
                    visible: empty.height > 420
                    Repeater {
                        model: [
                            { icon: "trending_up", title: I18n.tr("Why did this video blow up?"), body: I18n.tr("Add a video from Niche Finder; I'll take the numbers apart."), prompt: I18n.tr("Why did this video become an outlier? Explain it with the numbers."), tool: "archive" },
                            { icon: "data", title: I18n.tr("Read my CSV export"), body: I18n.tr("I'll find the unsaturated sub-niches and the winning titles."), prompt: I18n.tr("Which sub-niche in this export is still not saturated?"), tool: "file" },
                            { icon: "page_insights", title: I18n.tr("Analyse a brief"), body: I18n.tr("A Niche Scan brief or a client's brief: what's strong, what's missing."), prompt: I18n.tr("Analyse this brief: what's strong, what's missing, and what should I make from it?"), tool: "brief" },
                            { icon: "movie", title: I18n.tr("Coach me"), body: I18n.tr("Tell me about your channel; I'll plan what to make next."), prompt: I18n.tr("Coach me: ask what you need to know about my channel, then tell me exactly what to make next and why."), tool: "" }
                        ]
                        delegate: AbstractButton {
                            id: starter
                            Layout.fillWidth: true
                            implicitHeight: 84
                            hoverEnabled: true
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            opacity: 0
                            Component.onCompleted: starterIn.start()
                            NumberAnimation { id: starterIn; target: starter; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
                            transform: Translate { y: starter.hovered ? -2 : 0 }
                            padding: 16
                            onClicked: {
                                if (modelData.tool === "") { composerInput.text = modelData.prompt; page.sendNow(); return }
                                composerInput.text = modelData.prompt
                                composerInput.forceActiveFocus()
                                page.runTool(modelData.tool)
                            }
                            background: Rectangle {
                                radius: 18
                                color: starter.hovered ? Theme.surface_low : Theme.surface
                                border.width: 1
                                border.color: starter.hovered ? Theme.border_med : Theme.border
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                            contentItem: RowLayout {
                                spacing: 14
                                Rectangle {
                                    Layout.preferredWidth: 38; Layout.preferredHeight: 38
                                    Layout.alignment: Qt.AlignTop
                                    radius: 12; color: Theme.surface_highest
                                    C.IconGlyph { anchors.centerIn: parent; name: modelData.icon; size: 18; glyphColor: Theme.primary }
                                }
                                Column {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 2
                                    C.AppText { width: parent.width; text: modelData.title; weight: Tokens.weightExtraBold; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong; elide: Text.ElideRight }
                                    C.AppText { width: parent.width; text: modelData.body; color: Theme.on_surface_var; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── the thread ──
        ListView {
            id: msgList
            anchors.top: head.bottom
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: !empty.visible
            opacity: page._pane
            transform: Translate { y: (1 - page._pane) * page._drift * page._dir }
            clip: true
            model: page._msgs
            spacing: 0
            topMargin: 16
            boundsBehavior: Flickable.StopAtBounds
            // Messages are heavy delegates (markdown, cards, charts). Building
            // them a couple of screens ahead means a scroll never stalls while
            // the next answer is laid out mid-glide.
            // v3.40.4: tiny right after a chat switch (build just what's visible), full afterwards
            cacheBuffer: (page._settling || cacheRestore.running) ? 200 : Math.max(1200, height * 2)
            flickDeceleration: 2600
            maximumFlickVelocity: 3200
            pixelAligned: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            // Keep following the answer while it streams, unless the reader
            // scrolled up to look at something.
            property bool follow: true
            onMovementEnded: follow = atYEnd || (contentHeight - contentY - height) < 120
            onContentHeightChanged: if (page._settling || (follow && Chat.streamingHere)) { msgWheel.cancel(); positionViewAtEnd() }
            C.SmoothWheel {
                id: msgWheel
                flick: msgList
                onMoved: (up) => {
                    if (up) msgList.follow = false
                    else followCheck.restart()
                }
            }
            // after a downward glide settles, pick the stream back up if we
            // landed at the bottom
            Timer {
                id: followCheck
                interval: 300
                onTriggered: msgList.follow = (msgList.contentHeight + msgList.originY - msgList.contentY - msgList.height) < 120
            }

            delegate: Item {
                id: mrow
                width: msgList.width
                height: (modelData.role === "user" ? userCol.implicitHeight : aiCol.implicitHeight) + (modelData.role === "user" ? 26 : 30)
                readonly property bool isLast: index === msgList.count - 1
                readonly property bool lastUser: index === page._lastUserIdx
                HoverHandler { id: mHover }

                // user turn
                Column {
                    id: userCol
                    visible: modelData.role === "user"
                    width: chatCol.colW
                    x: (msgList.width - width) / 2
                    y: 10
                    spacing: 8
                    Flow {
                        visible: (modelData.attachments || []).length > 0
                        width: parent.width * 0.82
                        anchors.right: parent.right
                        layoutDirection: Qt.RightToLeft
                        spacing: 6
                        Repeater {
                            model: modelData.attachments || []
                            delegate: AttChip { src: modelData }
                        }
                    }
                    Rectangle {
                        id: bubble
                        anchors.right: parent.right
                        width: Math.min(parent.width * 0.82, bubbleText.implicitWidth + 32)
                        height: bubbleText.implicitHeight + 24
                        color: Theme.surface_highest
                        radius: 20
                        // the corner nearest the speaker is tucked in
                        topRightRadius: 6
                        C.AppText {
                            id: bubbleText
                            x: 16; y: 12
                            width: Math.min(chatCol.colW * 0.82 - 32, implicitWidth)
                            text: modelData.text
                            wrapMode: Text.Wrap
                            font.pixelSize: 16
                            lineHeight: 1.4
                            color: Theme.text_strong
                            selectable: true
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 2
                        opacity: mHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        Ghost { glyph: "content_copy"; text: I18n.tr("Copy"); onClicked: Chat.copyText(modelData.text) }
                        Ghost {
                            visible: mrow.lastUser && !Chat.busy
                            glyph: "edit"; text: I18n.tr("Edit")
                            onClicked: { page.editing = true; composerInput.text = modelData.text; composerInput.forceActiveFocus(); composerInput.cursorPosition = composerInput.length }
                        }
                    }
                }

                // assistant turn
                Column {
                    id: aiCol
                    visible: modelData.role === "assistant"
                    readonly property bool rtl: modelData.role === "assistant" && page._partsRtl(modelData.parts)
                    width: chatCol.colW
                    x: (msgList.width - width) / 2
                    y: 4
                    spacing: 10
                    Row {
                        // v1.0.4: a Persian answer puts the header on the right:
                        // mark, then "Hunter", then the model
                        layoutDirection: aiCol.rtl ? Qt.RightToLeft : Qt.LeftToRight
                        x: aiCol.rtl ? aiCol.width - width : 0
                        spacing: 10
                        // v3.40.7: every past answer used to build its own mark (several
                        // curve-rendered Shapes) — the same idle picture ten times over. Now
                        // they all sample ONE shared texture; software renderer keeps the real one.
                        // v1.0.4: the mark is the accent app-tile (C.HunterAvatar).
                        Loader {
                            width: page._avatarSize; height: page._avatarSize
                            anchors.verticalCenter: parent.verticalCenter
                            sourceComponent: page._gpu ? lensStamp : lensReal
                        }
                        AuthorMeta { model: modelData.model || ""; time: modelData.time || ""; rtl: aiCol.rtl }
                    }
                    Repeater {
                        model: modelData.role === "assistant" ? modelData.parts : []
                        delegate: Loader {
                            width: aiCol.width
                            property var part: modelData
                            sourceComponent: part.type === "ideas" ? ideasPart
                                           : (part.type === "next" ? nextPart : mdPart)
                            Component {
                                id: mdPart
                                MdText { width: aiCol.width; text: part.text || ""; visible: text !== "" }
                            }
                            // follow-up chips: only under the newest answer
                            Component {
                                id: nextPart
                                Flow {
                                    width: aiCol.width
                                    spacing: 8
                                    visible: mrow.isLast && !Chat.busy
                                    Repeater {
                                        model: part.items || []
                                        delegate: AbstractButton {
                                            id: fu
                                            hoverEnabled: true
                                            implicitHeight: 34
                                            implicitWidth: Math.min(aiCol.width, fuRow.implicitWidth + 26)
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            background: Rectangle {
                                                radius: Tokens.radiusPill
                                                color: fu.hovered ? U.withAlpha(Theme.primary, 0.12) : U.withAlpha(Theme.primary, 0.05)
                                                border.width: 1
                                                border.color: U.withAlpha(Theme.primary, fu.hovered ? 0.45 : 0.22)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                Row {
                                                    id: fuRow
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    C.IconGlyph { name: I18n.rtl ? "arrow_back" : "arrow_forward"; size: 14; glyphColor: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                                                    C.AppText { text: modelData; color: Theme.on_surface; font.pixelSize: Tokens.fontCaption; weight: Tokens.weightDemiBold; elide: Text.ElideRight; width: Math.min(implicitWidth, aiCol.width - 60); anchors.verticalCenter: parent.verticalCenter }
                                                }
                                            }
                                            onClicked: Chat.send(modelData)
                                        }
                                    }
                                }
                            }
                            Component {
                                id: ideasPart
                                Column {
                                    width: aiCol.width
                                    spacing: 10
                                    Repeater {
                                        model: part.items || []
                                        delegate: IdeaCard { width: aiCol.width; item: modelData }
                                    }
                                }
                            }
                        }
                    }
                    // a failed turn
                    Rectangle {
                        visible: modelData.error !== ""
                        width: parent.width
                        height: errRow.implicitHeight + 24
                        radius: Tokens.radiusLg
                        color: U.withAlpha(Theme.error, 0.10)
                        border.width: 1
                        border.color: U.withAlpha(Theme.error, 0.35)
                        RowLayout {
                            id: errRow
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            C.IconGlyph { name: "error"; size: 18; glyphColor: Theme.error; Layout.alignment: Qt.AlignTop }
                            C.AppText { Layout.fillWidth: true; text: modelData.error; wrapMode: Text.Wrap; color: Theme.on_surface }
                            Ghost { visible: mrow.isLast; glyph: "refresh"; text: I18n.tr("Retry"); onClicked: Chat.regenerate() }
                        }
                    }
                    Pill { visible: modelData.stopped === true; icon: "stop_circle"; text: I18n.tr("Stopped") }
                    Row {
                        spacing: 2
                        layoutDirection: aiCol.rtl ? Qt.RightToLeft : Qt.LeftToRight
                        x: aiCol.rtl ? aiCol.width - width : 0
                        opacity: (mHover.hovered || mrow.isLast) && modelData.error === "" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        Ghost { glyph: "content_copy"; text: I18n.tr("Copy"); onClicked: Chat.copyMessage(modelData.id) }
                        Ghost { visible: mrow.isLast && !Chat.busy; glyph: "refresh"; text: I18n.tr("Regenerate"); onClicked: Chat.regenerate() }
                    }
                }
            }

            // the live answer + room for the floating composer
            footer: Item {
                width: msgList.width
                height: (Chat.streamingHere ? liveCol.implicitHeight + 30 : 0) + dock.height + 40
                Column {
                    id: liveCol
                    visible: Chat.streamingHere
                    width: chatCol.colW
                    x: (msgList.width - width) / 2
                    y: 4
                    spacing: 10
                    Row {
                        spacing: 10
                        layoutDirection: page._liveRtl ? Qt.RightToLeft : Qt.LeftToRight
                        x: page._liveRtl ? liveCol.width - width : 0
                        C.HunterAvatar { size: page._avatarSize; mode: Chat.phase; anchors.verticalCenter: parent.verticalCenter }
                        AuthorMeta { model: Chat.modelName || ""; time: ""; live: true; rtl: page._liveRtl }
                    }
                    Column {
                        visible: Chat.phase === "thinking"
                        spacing: 8
                        Repeater {
                            model: Chat.steps
                            delegate: Row {
                                visible: index <= Chat.stepIndex
                                spacing: 10
                                StepDot { done: index < Chat.stepIndex; anchors.verticalCenter: parent.verticalCenter }
                                C.AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData + (index === Chat.stepIndex ? "…" : "")
                                    color: index === Chat.stepIndex ? Theme.on_surface : Theme.on_surface_var
                                    SequentialAnimation on opacity {
                                        running: index === Chat.stepIndex && Chat.phase === "thinking"
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.55; duration: 650; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                                    }
                                }
                            }
                        }
                    }
                    MdText { width: parent.width; visible: Chat.streamText !== ""; text: Chat.streamText }
                    Row {
                        visible: Chat.streamBuildingCards
                        spacing: 10
                        StepDot { done: false; anchors.verticalCenter: parent.verticalCenter }
                        C.AppText { text: I18n.tr("Building idea cards…"); color: Theme.on_surface_var; anchors.verticalCenter: parent.verticalCenter }
                    }
                    // tally caret
                    Rectangle {
                        visible: Chat.phase === "streaming"
                        width: 9; height: 9; radius: 4.5
                        color: Theme.primary
                        SequentialAnimation on opacity {
                            running: Chat.phase === "streaming"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 500 }
                            NumberAnimation { to: 1.0; duration: 500 }
                        }
                    }
                }
            }
        }

        // v3.40.7: the one idle lens every past answer shows (rendered once)
        // v1.0.4: the mark is now the accent tile (C.HunterAvatar). Idle, it runs
        // no animation at all, so the shared texture is effectively a still.
        C.HunterAvatar { id: lensMaster; size: page._avatarSize; mode: "idle"; x: -200; y: -200; visible: page._gpu }
        ShaderEffectSource {
            id: lensTex
            sourceItem: page._gpu ? lensMaster : null
            hideSource: true
            live: true
            width: page._avatarSize; height: page._avatarSize
            textureSize: Qt.size(page._avatarSize * Screen.devicePixelRatio, page._avatarSize * Screen.devicePixelRatio)
            visible: false
        }
        Component { id: lensStamp; ShaderEffect { property variant source: lensTex } }
        Component { id: lensReal; C.HunterAvatar { size: page._avatarSize; mode: "idle" } }

        // v3.40.6: frozen picture of the previous chat, cross-faded away on a
        // switch. Declared after the thread but before the dock/header, so the
        // composer stays crisp on top of it.
        ShaderEffectSource {
            id: snap
            sourceItem: null
            live: false
            hideSource: false
            recursive: false
            x: sourceItem ? sourceItem.x : 0
            y: sourceItem ? sourceItem.y : 0
            width: sourceItem ? sourceItem.width : 0
            height: sourceItem ? sourceItem.height : 0
            visible: page._old > 0.001 && sourceItem !== null
            opacity: page._old
            transform: Translate { y: -(1 - page._old) * page._drift * page._dir }
            onVisibleChanged: if (!visible && !page._swapping) sourceItem = null
        }

        // jump to the latest message
        C.IconButton {
            z: 4
            visible: msgList.visible && !msgList.atYEnd && msgList.contentHeight > msgList.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: dock.top
            anchors.bottomMargin: 10
            iconName: "expand_more"
            tip: I18n.tr("Latest")
            onClicked: { msgWheel.cancel(); msgList.follow = true; msgList.positionViewAtEnd() }
        }

        // ── the composer ──
        Item {
            id: dock
            z: 5
            // v3.24 — whole-pixel geometry. A centre anchor on an odd width
            // lands the composer on x.5 and every glyph in it is resampled
            // across two pixels, which reads as a soft blur.
            x: Math.round((parent.width - width) / 2)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: Math.round(Math.min(800, chatCol.width - 40))
            height: composer.height + hint.height + 10

            // fade the thread out under the composer
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -14
                width: chatCol.width
                height: parent.height + 60
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.background, 0) }
                    GradientStop { position: 0.45; color: U.withAlpha(Theme.background, 0.92) }
                    GradientStop { position: 1.0; color: Theme.background }
                }
            }

            // v3.24 — the shadow lives on its own plate BEHIND the composer.
            // It used to be a layer on the composer itself, which rendered
            // the text field into an offscreen texture and scaled it back on
            // screen: at 125 % / 150 % Windows scaling that is exactly the
            // "slightly blurry" chat box. The composer now draws straight to
            // the window, so its text is as sharp as the rest of the app.
            Rectangle {
                id: composerShadow
                x: composer.x; y: composer.y
                width: composer.width; height: composer.height
                radius: composer.radius
                color: Theme.isDark ? Theme.surface_high : Theme.surface
                // v3.40.1: pre-blurred 9-slice shadow (GlassPanel / Toast use
                // the same image) instead of a MultiEffect layer. The layer
                // re-rendered its blur every time the composer grew a line or
                // the window was resized, and built its shader on first show.
                BorderImage {
                    z: -1
                    source: "../components/shadow_soft.png"
                    border { left: 64; right: 64; top: 64; bottom: 64 }
                    horizontalTileMode: BorderImage.Stretch
                    verticalTileMode: BorderImage.Stretch
                    anchors.fill: parent
                    anchors.leftMargin: -50; anchors.rightMargin: -50
                    anchors.topMargin: -50 + 12; anchors.bottomMargin: -50 - 12
                    opacity: Theme.isDark ? 0.60 : 0.18
                    smooth: true
                    cache: true
                }
            }

            Rectangle {
                id: composer
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: hint.top; anchors.bottomMargin: 10
                height: Math.round(compCol.implicitHeight + 20)
                radius: 24
                // Opaque: the plate behind it is the same colour, so a
                // translucent fill would only add a faint double edge.
                color: Theme.isDark ? Theme.surface_high : Theme.surface
                border.width: 1
                border.color: composerInput.activeFocus ? U.withAlpha(Theme.primary, 0.45) : Theme.border_med
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                // focus halo
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: parent.radius + 5
                    color: "transparent"
                    border.width: 5
                    border.color: U.withAlpha(Theme.primary, composerInput.activeFocus ? 0.10 : 0)
                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }

                ColumnLayout {
                    id: compCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 4

                    // editing banner
                    RowLayout {
                        visible: page.editing
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        spacing: 8
                        C.IconGlyph { name: "edit"; size: 14; glyphColor: Theme.primary }
                        C.AppText { Layout.fillWidth: true; text: I18n.tr("Editing your last message — the answer will be rewritten."); color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption; elide: Text.ElideRight }
                        Ghost { glyph: "close"; text: I18n.tr("Cancel"); onClicked: { page.editing = false; composerInput.text = "" } }
                    }

                    Flow {
                        visible: Chat.pending.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 4; Layout.rightMargin: 4; Layout.bottomMargin: 2
                        spacing: 6
                        Repeater {
                            model: Chat.pending
                            delegate: AttChip { src: modelData; removable: true; onRemoveRequested: (k) => Chat.removePending(k) }
                        }
                    }

                    ScrollView {
                        id: inputScroll
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(200, Math.max(34, composerInput.implicitHeight))
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        TextArea {
                            selectedTextColor: Theme.text_strong
                            id: composerInput
                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                            T.ContextMenu.menu: C.EditMenu { editor: composerInput }
                            // v3.24 — the same rasteriser as every AppText on
                            // the page; the default (distance-field) one is
                            // what made typed text look softer than the UI.
                            renderType: Text.NativeRendering
                            wrapMode: TextArea.Wrap
                            background: null
                            leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 4
                            color: Theme.text_strong
                            placeholderText: I18n.tr("Ask Hunter… e.g. “Why did this video become an outlier?”")
                            placeholderTextColor: Theme.outline
                            font.family: Fonts.familyFor("body", Tokens.weightRegular, text)
                            font.pixelSize: 16
                            selectByMouse: true
                            selectionColor: U.withAlpha(Theme.primary, 0.35)
                            Keys.onPressed: (event) => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && !(event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true
                                    page.sendNow()
                                } else if (event.key === Qt.Key_Escape) {
                                    if (Chat.busy) { Chat.stop(); event.accepted = true }
                                    else if (page.editing) { page.editing = false; composerInput.text = ""; event.accepted = true }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        // the multitool
                        AbstractButton {
                            id: plusBtn
                            implicitWidth: 38; implicitHeight: 38
                            hoverEnabled: true
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            onClicked: toolMenu.opened ? toolMenu.close() : toolMenu.open()
                            background: Rectangle {
                                radius: 12
                                color: toolMenu.opened ? Theme.surface_highest : (plusBtn.hovered ? U.withAlpha(Theme.on_surface, 0.07) : "transparent")
                            }
                            contentItem: Item {
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    name: "add"; size: 20
                                    glyphColor: toolMenu.opened ? Theme.text_strong : Theme.on_surface_var
                                    rotation: toolMenu.opened ? 45 : 0
                                    Behavior on rotation { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                                }
                            }
                        }
                        C.IconButton {
                            Layout.preferredWidth: 38; Layout.preferredHeight: 38
                            chromeless: true; iconName: "archive"; glyphSize: 18
                            tip: I18n.tr("From Search Archive")
                            onClicked: page.runTool("archive")
                        }
                        // v3.49: the File shortcut moved into the + menu; this slot
                        // is the brief analyser now (saved Niche Scan briefs, or
                        // paste a client's / your own brief).
                        C.IconButton {
                            Layout.preferredWidth: 38; Layout.preferredHeight: 38
                            chromeless: true; iconName: "page_insights"; glyphSize: 18
                            tip: I18n.tr("Analyse a brief")
                            onClicked: page.runTool("brief")
                        }
                        Item { Layout.fillWidth: true }

                        // model chip
                        AbstractButton {
                            id: modelChip
                            implicitHeight: 34
                            implicitWidth: mcRow.implicitWidth + 20
                            hoverEnabled: true
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            onClicked: modelPop.opened ? modelPop.close() : modelPop.open()
                            background: Rectangle { radius: 11; color: modelChip.hovered || modelPop.opened ? U.withAlpha(Theme.on_surface, 0.07) : "transparent" }
                            contentItem: Item {
                                Row {
                                    id: mcRow
                                    anchors.centerIn: parent
                                    spacing: 7
                                    C.IconGlyph { name: "auto_awesome"; size: 15; glyphColor: Theme.tertiary; anchors.verticalCenter: parent.verticalCenter }
                                    C.AppText {
                                        visible: dock.width > 560
                                        text: Chat.modelName
                                        width: Math.min(implicitWidth, 190)
                                        elide: Text.ElideRight
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    C.IconGlyph { name: "expand_more"; size: 14; glyphColor: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                        // send / stop
                        AbstractButton {
                            id: sendBtn
                            readonly property bool can: Chat.busy || composerInput.text.trim() !== "" || Chat.pending.length > 0
                            implicitWidth: 40; implicitHeight: 40
                            enabled: can
                            hoverEnabled: true
                            HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: sendBtn.can }
                            onClicked: Chat.busy ? Chat.stop() : page.sendNow()
                            scale: pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                            background: Rectangle {
                                radius: 13
                                color: Chat.busy ? Theme.text_strong : Theme.primary
                                opacity: sendBtn.can ? 1 : 0.35
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                            }
                            contentItem: Item {
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    visible: !Chat.busy
                                    name: "send"; size: 18
                                    glyphColor: Theme.on_primary
                                    // the paper plane points the way the text runs
                                    transform: Scale { xScale: I18n.rtl ? -1 : 1; origin.x: 9 }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: Chat.busy
                                    width: 13; height: 13; radius: 3
                                    color: Theme.background
                                }
                            }
                        }
                    }
                }

                // + menu
                Popup {
                    id: toolMenu
                    y: -height - 10
                    x: I18n.rtl ? parent.width - width : 0
                    width: 312
                    padding: 8
                    modal: false
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    enter: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                    }
                    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Tokens.durFast } }
                    background: Rectangle {
                        radius: 20
                        color: Theme.isDark ? Theme.surface_high : Theme.surface
                        border.width: 1; border.color: Theme.border_med
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: Theme.isDark ? 0.5 : 0.18; shadowBlur: 1.0; shadowVerticalOffset: 10 }
                    }
                    contentItem: Column {
                        LayoutMirroring.enabled: I18n.rtl
                        LayoutMirroring.childrenInherit: true
                        spacing: 2
                        C.AppText { leftPadding: 10; topPadding: 6; bottomPadding: 6; text: I18n.tr("Add to the chat"); color: Theme.outline; weight: Tokens.weightDemiBold; font.pixelSize: Tokens.fontCaption }
                        Repeater {
                            // v3.49: Search Archive has its own button on the composer,
                            // so the menu keeps only what has no other way in.
                            // (Images still work: pick them as a File, or drop them
                            // anywhere on the page.)
                            model: [
                                { id: "link",    icon: "link",           title: I18n.tr("YouTube links"),          sub: I18n.tr("One video or a whole batch"), tone: Theme.on_surface },
                                { id: "file",    icon: "description",    title: I18n.tr("File"),                   sub: "CSV · XLSX · PDF · DOCX · SRT", tone: Theme.secondary_container }
                            ]
                            delegate: AbstractButton {
                                id: mi
                                width: 296
                                implicitHeight: 52
                                hoverEnabled: true
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                // the blades swing out of one handle
                                opacity: 0
                                rotation: -10
                                transformOrigin: Item.BottomLeft
                                Connections {
                                    target: toolMenu
                                    function onAboutToShow() { mi.opacity = 0; mi.rotation = -10; miIn.restart() }
                                }
                                SequentialAnimation {
                                    id: miIn
                                    PauseAnimation { duration: 24 * (2 - index) }
                                    ParallelAnimation {
                                        NumberAnimation { target: mi; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: mi; property: "rotation"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                                    }
                                }
                                onClicked: { toolMenu.close(); page.runTool(modelData.id) }
                                leftPadding: 8; rightPadding: 8
                                background: Rectangle { radius: 13; color: mi.hovered ? U.withAlpha(Theme.on_surface, 0.07) : "transparent" }
                                contentItem: RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        Layout.preferredWidth: 36; Layout.preferredHeight: 36
                                        radius: 11
                                        color: U.withAlpha(modelData.tone, 0.13)
                                        C.IconGlyph { anchors.centerIn: parent; name: modelData.icon; size: 18; glyphColor: modelData.tone }
                                    }
                                    Column {
                                        Layout.fillWidth: true
                                        C.AppText { text: modelData.title; weight: Tokens.weightBold; color: Theme.text_strong }
                                        C.AppText { text: modelData.sub; color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption }
                                    }
                                }
                            }
                        }
                    }
                }

                // model popover — every saved provider and its models, plus effort.
                // A custom provider added in Settings lands here as its own group
                // (its fetched catalogue, or its one model); picking a row pins
                // this chat to that provider + model.
                Popup {
                    id: modelPop
                    y: -height - 10
                    x: I18n.rtl ? 0 : parent.width - width
                    width: 348
                    padding: 14
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    onAboutToShow: { Chat.reloadConfig(); modelSearch.text = "" }
                    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed } }
                    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Tokens.durFast } }
                    background: Rectangle {
                        radius: 18
                        color: Theme.isDark ? Theme.surface_high : Theme.surface
                        border.width: 1; border.color: Theme.border_med
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: Theme.isDark ? 0.5 : 0.18; shadowBlur: 1.0; shadowVerticalOffset: 10 }
                    }
                    // flat rows: {head: true, ...group} or {head: false, pid, model, current, own}
                    readonly property var rows: {
                        var q = modelSearch.text.trim().toLowerCase()
                        var out = []
                        var gs = Chat.modelGroups || []
                        for (var g = 0; g < gs.length; g++) {
                            var grp = gs[g]
                            var ms = (grp.models || []).filter(function (m) {
                                return q === "" || m.id.toLowerCase().indexOf(q) >= 0
                                       || grp.name.toLowerCase().indexOf(q) >= 0
                            })
                            if (ms.length === 0) continue
                            out.push({ head: true, name: grp.name, glyph: grp.glyph, kind: grp.kind,
                                       isDefault: grp.isDefault, count: ms.length })
                            for (var i = 0; i < ms.length; i++)
                                out.push({ head: false, pid: grp.id, model: ms[i].id,
                                           current: ms[i].current, own: ms[i].isOwn })
                        }
                        return out
                    }
                    readonly property int modelCount: {
                        var n = 0, gs = Chat.modelGroups || []
                        for (var g = 0; g < gs.length; g++) n += (gs[g].models || []).length
                        return n
                    }
                    contentItem: ColumnLayout {
                        LayoutMirroring.enabled: I18n.rtl
                        LayoutMirroring.childrenInherit: true
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            C.AppText { text: I18n.tr("Model for this chat"); color: Theme.outline; weight: Tokens.weightDemiBold; font.pixelSize: Tokens.fontCaption }
                            Item { Layout.fillWidth: true }
                            // back to whatever Settings has starred
                            AbstractButton {
                                id: followBtn
                                visible: !Chat.followsDefault
                                implicitHeight: 24
                                implicitWidth: fbTxt.implicitWidth + 16
                                hoverEnabled: true
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                onClicked: Chat.pickModel("", "")
                                background: Rectangle { radius: 8; color: followBtn.hovered ? U.withAlpha(Theme.primary, 0.14) : U.withAlpha(Theme.primary, 0.07) }
                                contentItem: C.AppText { id: fbTxt; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: I18n.tr("Use default"); color: Theme.primary; weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro + 1 }
                            }
                        }
                        RowLayout {
                            spacing: 10
                            Rectangle {
                                Layout.preferredWidth: 36; Layout.preferredHeight: 36
                                radius: 11; color: Theme.surface_highest
                                C.IconGlyph { anchors.centerIn: parent; name: "auto_awesome"; size: 17; glyphColor: Theme.tertiary }
                            }
                            Column {
                                Layout.fillWidth: true
                                C.AppText { width: parent.width; text: Chat.modelName; weight: Tokens.weightBold; color: Theme.text_strong; elide: Text.ElideRight }
                                C.AppText { text: Chat.providerLabel + (Chat.followsDefault ? "  ·  " + I18n.tr("Default") : ""); color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption }
                            }
                        }

                        // filter (only worth showing for a real catalogue)
                        Rectangle {
                            visible: modelPop.modelCount > 8
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Tokens.radiusMd; color: Theme.input_bg; border.width: 1
                            border.color: modelSearch.activeFocus ? U.withAlpha(Theme.primary, 0.55) : Theme.border
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                C.IconGlyph { name: "search"; size: 14; glyphColor: Theme.outline }
                                TextField {
                                    id: modelSearch
                                    // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                    T.ContextMenu.menu: C.EditMenu { editor: modelSearch }
                                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                    selectedTextColor: Theme.text_strong
                                    Layout.fillWidth: true
                                    background: null; padding: 0
                                    color: Theme.on_surface
                                    placeholderText: I18n.tr("Find a model")
                                    placeholderTextColor: Theme.outline
                                    font.family: Fonts.familyFor("body", Tokens.weightRegular, text)
                                    font.pixelSize: Tokens.fontCaption + 1
                                }
                            }
                        }

                        ListView {
                            id: modelList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, 280)
                            visible: count > 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: modelPop.rows
                            ScrollBar.vertical: ScrollBar { policy: modelList.contentHeight > 280 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                            delegate: Item {
                                width: modelList.width
                                height: modelData.head ? (index === 0 ? 28 : 36) : 36
                                // provider header
                                RowLayout {
                                    visible: modelData.head
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                    anchors.leftMargin: 4; anchors.rightMargin: 4
                                    spacing: 6
                                    C.IconGlyph { name: modelData.glyph || "api"; fill: true; size: 13; glyphColor: Theme.on_surface_var }
                                    C.AppText { text: modelData.name || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                                    C.IconGlyph { visible: modelData.isDefault === true; name: "star"; fill: true; size: 11; glyphColor: Theme.primary }
                                    Item { Layout.fillWidth: true }
                                    C.AppText { text: String(modelData.count || ""); font.pixelSize: Tokens.fontMicro; color: Theme.outline }
                                }
                                // one model
                                AbstractButton {
                                    id: mRow
                                    visible: !modelData.head
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    onClicked: { Chat.pickModel(modelData.pid, modelData.model); modelPop.close() }
                                    background: Rectangle {
                                        radius: 10
                                        color: modelData.current ? U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                                             : mRow.hovered ? U.withAlpha(Theme.on_surface, 0.06) : "transparent"
                                    }
                                    contentItem: RowLayout {
                                        spacing: 8
                                        Item { Layout.preferredWidth: 14 }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: modelData.model || ""
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            weight: modelData.current ? Tokens.weightBold : Tokens.weightRegular
                                            color: modelData.current ? Theme.text_strong : Theme.on_surface
                                            elide: Text.ElideMiddle
                                        }
                                        C.IconGlyph { visible: modelData.current === true; name: "check"; size: 15; glyphColor: Theme.primary }
                                        Item { Layout.preferredWidth: 4 }
                                    }
                                }
                            }
                        }
                        C.AppText {
                            visible: modelList.count === 0
                            Layout.fillWidth: true
                            text: (Chat.modelGroups || []).length === 0 ? I18n.tr("No provider is set up yet. Add one in Settings.")
                                                                        : I18n.tr("No model matches.")
                            wrapMode: Text.Wrap
                            color: Theme.on_surface_var
                            font.pixelSize: Tokens.fontCaption
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                        C.AppText { text: I18n.tr("Effort"); color: Theme.outline; weight: Tokens.weightDemiBold; font.pixelSize: Tokens.fontCaption }
                        C.EffortPicker {
                            Layout.fillWidth: true
                            compact: true
                            showHint: false
                            options: Chat.effortOptions
                            value: Chat.effort || "auto"
                            onPicked: (v) => Chat.setEffort(v)
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: I18n.tr("Pick a vision-capable model to send images. New providers from Settings appear here automatically.")
                            wrapMode: Text.Wrap
                            color: Theme.on_surface_var
                            font.pixelSize: Tokens.fontCaption
                        }
                        C.PrimaryButton {
                            Layout.fillWidth: true
                            variant: "ghost"
                            iconName: "settings"
                            text: I18n.tr("Manage providers")
                            onClicked: { modelPop.close(); App.goto(10) }
                        }
                    }
                }
            }

            C.AppText {
                id: hint
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: dock.width > 520
                // One line always (no wrap, elided), so the height is the font's
                // line box. Written from the font rather than from
                // `implicitHeight` because `dock` above sizes itself as
                // `composer.height + hint.height + 10` — feeding a
                // content-derived implicitHeight back into that chain is what Qt
                // reported as "Binding loop detected for property height", and a
                // loop there re-evaluates the whole composer on every frame.
                height: visible ? Math.ceil(font.pixelSize * 1.45) : 0
                text: I18n.tr("Hunter only answers about YouTube and content creation · Enter to send · Shift+Enter for a new line")
                color: Theme.outline
                font.pixelSize: Tokens.fontCaption
            }
        }
    }

    // scrim for the overlay panes on narrow windows
    Rectangle {
        anchors.fill: parent
        z: 29
        color: "black"
        opacity: (!page.railDocked && page.railOpen) ? 0.35 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        TapHandler { onTapped: { if (!page.railDocked) page.railOpen = false } }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Tools
    // ═══════════════════════════════════════════════════════════════════
    function runTool(id) {
        if (id === "niche" || id === "archive") { Chat.openPicker("archive"); picker.open() }
        else if (id === "link") linkDialog.open()
        else if (id === "brief") { Chat.openBriefPicker(); briefDialog.open() }
        else if (id === "file") fileDialog.open()
        else if (id === "image") imageDialog.open()
        else if (id === "drive") { Chat.reloadConfig(); driveDialog.open(); if (Chat.driveConnected && Chat.driveFiles.length === 0) Chat.listDrive("") }
    }

    FileDialog {
        id: fileDialog
        title: I18n.tr("Add files to the conversation")
        fileMode: FileDialog.OpenFiles
        nameFilters: [I18n.tr("Supported files") + " (*.csv *.tsv *.xlsx *.xlsm *.jsonl *.db *.txt *.md *.json *.srt *.vtt *.pdf *.docx *.png *.jpg *.jpeg *.webp *.gif *.bmp)", I18n.tr("All files") + " (*)"]
        onAccepted: {
            var out = []
            for (var i = 0; i < selectedFiles.length; i++) out.push(selectedFiles[i].toString())
            Chat.addFiles(out)
        }
    }
    FileDialog {
        id: imageDialog
        title: I18n.tr("Choose images")
        fileMode: FileDialog.OpenFiles
        nameFilters: [I18n.tr("Images") + " (*.png *.jpg *.jpeg *.webp *.gif *.bmp)"]
        onAccepted: {
            var out = []
            for (var i = 0; i < selectedFiles.length; i++) out.push(selectedFiles[i].toString())
            Chat.addFiles(out)
        }
    }
    FileDialog {
        id: exportDialog
        title: I18n.tr("Export conversation")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "md"
        nameFilters: ["Markdown (*.md)"]
        onAccepted: Chat.exportThread(selectedFile.toString())
    }

    // drop files anywhere on the page
    DropArea {
        id: dropZone
        anchors.fill: parent
        z: 50
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            if (!drop.hasUrls) return
            var out = []
            for (var i = 0; i < drop.urls.length; i++) out.push(drop.urls[i].toString())
            Chat.addFiles(out)
            drop.accept()
        }
    }
    Rectangle {
        anchors.fill: parent
        z: 60
        visible: opacity > 0.01
        opacity: dropZone.containsDrag ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        color: U.withAlpha(Theme.background, 0.86)
        Column {
            anchors.centerIn: parent
            spacing: 18
            C.HunterAvatar { anchors.horizontalCenter: parent.horizontalCenter; size: 140; mode: dropZone.containsDrag ? "streaming" : "idle" }
            C.AppText { anchors.horizontalCenter: parent.horizontalCenter; text: I18n.tr("Drop it and Hunter reads it"); weight: Tokens.weightExtraBold; font.pixelSize: Tokens.fontDisplay; color: Theme.text_strong }
            C.AppText { anchors.horizontalCenter: parent.horizontalCenter; text: "CSV · XLSX · PDF · DOCX · SRT · PNG/JPG — 40 MB"; mono: true; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var }
        }
    }

    // ── shared dialog chrome ──
    component Sheet: Dialog {
        id: sheet
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        padding: 0
        // NOTE: LayoutMirroring CANNOT be set on the Dialog itself. A Dialog is
        // a Popup, not an Item, so Qt ignores the attached property there and
        // logs "LayoutMirroring attached property only works with Items and
        // Windows" once per sheet. The popup is also parented to
        // Overlay.overlay, which sits OUTSIDE the mirrored shell, so nothing it
        // contains inherits the shell's mirroring either — in Persian the title
        // row, the fields and the footer buttons all laid out left-to-right.
        //
        // So the mirroring is declared on the three Items that actually hold the
        // content — this `header`, and each sheet's `contentItem` and `footer`
        // (marked with a "mirror" comment). Same visual result, no warning.
        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
        background: Rectangle { radius: Tokens.radiusXl; color: Theme.surface; border.width: 1; border.color: Theme.border }
        header: Item {
            implicitHeight: 64
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22; anchors.rightMargin: 12
                spacing: 10
                C.AppText { Layout.fillWidth: true; text: sheet.title; weight: Tokens.weightExtraBold; font.pixelSize: Tokens.fontSubtitle; color: Theme.text_strong; elide: Text.ElideRight }
                C.IconButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; chromeless: true; iconName: "close"; glyphSize: 16; onClicked: sheet.close() }
            }
        }
    }

    // ── video picker (Niche Finder / Archive) ──
    Sheet {
        id: picker
        width: Math.min(820, page.width - 60)
        height: Math.min(680, page.height - 60)
        title: Chat.pickerKind === "archive" ? I18n.tr("Add videos from Search Archive") : I18n.tr("Add videos from Niche Finder")
        property var picked: ({})
        property int pickedCount: 0
        onAboutToShow: { picked = {}; pickedCount = 0; pickerSearch.text = "" }
        function toggle(i) {
            var p = Object.assign({}, picked)
            if (p[i]) delete p[i]; else p[i] = true
            picked = p
            pickedCount = Object.keys(p).length
        }
        contentItem: ColumnLayout {
            spacing: 10
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 8
                Repeater {
                    model: []   // v3.15: the picker is Search Archive only
                    delegate: AbstractButton {
                        id: segBtn
                        readonly property bool on: Chat.pickerKind === modelData.id
                        implicitHeight: 34; implicitWidth: segText.implicitWidth + 28
                        hoverEnabled: true
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: { picker.picked = {}; picker.pickedCount = 0; Chat.openPicker(modelData.id) }
                        background: Rectangle { radius: Tokens.radiusPill; color: segBtn.on ? U.withAlpha(Theme.primary, 0.14) : (segBtn.hovered ? U.withAlpha(Theme.on_surface, 0.06) : "transparent"); border.width: 1; border.color: segBtn.on ? U.withAlpha(Theme.primary, 0.4) : Theme.border }
                        contentItem: C.AppText { id: segText; text: modelData.label; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; weight: Tokens.weightDemiBold; color: segBtn.on ? Theme.primary : Theme.on_surface }
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: 240; implicitHeight: 36
                    radius: Tokens.radiusMd; color: Theme.input_bg; border.width: 1; border.color: Theme.border
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                        C.IconGlyph { name: "search"; size: 15; glyphColor: Theme.outline }
                        TextField {
                            id: pickerSearch
                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                            T.ContextMenu.menu: C.EditMenu { editor: pickerSearch }
                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                            selectedTextColor: Theme.text_strong
                            Layout.fillWidth: true
                            background: null; padding: 0
                            color: Theme.on_surface
                            placeholderText: I18n.tr("Filter by title or channel")
                            placeholderTextColor: Theme.outline
                            font.family: Fonts.familyFor("body", Tokens.weightRegular, text)
                            font.pixelSize: Tokens.fontBody
                            onTextChanged: pickerFilter.restart()
                            Timer { id: pickerFilter; interval: 200; onTriggered: Chat.filterPicker(pickerSearch.text) }
                        }
                    }
                }
            }
            ListView {
                visible: Chat.pickerKind === "archive" && Chat.pickerGroups.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                Layout.preferredHeight: 32
                orientation: ListView.Horizontal
                spacing: 6
                clip: true
                model: Chat.pickerGroups
                delegate: AbstractButton {
                    id: gBtn
                    readonly property bool on: modelData.id === Chat.pickerGroup
                    implicitHeight: 30; implicitWidth: gText.implicitWidth + 24
                    hoverEnabled: true
                    onClicked: { picker.picked = {}; picker.pickedCount = 0; Chat.pickArchiveGroup(modelData.id) }
                    background: Rectangle { radius: Tokens.radiusPill; color: gBtn.on ? Theme.surface_highest : "transparent"; border.width: 1; border.color: gBtn.on ? Theme.border_med : Theme.border }
                    contentItem: C.AppText { id: gText; text: modelData.title + "  " + modelData.count; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Tokens.fontCaption; color: gBtn.on ? Theme.text_strong : Theme.on_surface_var }
                }
            }
            // v3.15 filter bar: format · sort · transcript-only
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 10
                C.SlideSegment {
                    model: [I18n.tr("All"), I18n.tr("Shorts"), I18n.tr("Long")]
                    currentIndex: ["all", "short", "long"].indexOf(Chat.pickerFormat)
                    cellHeight: 30; fontSize: Tokens.fontCaption + 1
                    onActivated: (i) => { picker.picked = {}; picker.pickedCount = 0; Chat.setPickerFormat(["all", "short", "long"][i]) }
                }
                C.SlideSegment {
                    model: [I18n.tr("Outlier"), I18n.tr("Views"), I18n.tr("Newest"), I18n.tr("Longest")]
                    currentIndex: ["mult", "views", "new", "long"].indexOf(Chat.pickerSort)
                    cellHeight: 30; fontSize: Tokens.fontCaption + 1; solid: false
                    onActivated: (i) => Chat.setPickerSort(["mult", "views", "new", "long"][i])
                }
                Item { Layout.fillWidth: true }
                C.AppText { text: I18n.tr("With transcript"); font.pixelSize: Tokens.fontCaption + 1; color: Theme.on_surface_var }
                C.AppSwitch {
                    checked: Chat.pickerTranscriptOnly
                    onToggled: { picker.picked = {}; picker.pickedCount = 0; Chat.setPickerTranscriptOnly(checked) }
                }
            }
            ListView {
                id: pickList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Chat.pickerRows
                leftMargin: 14; rightMargin: 14
                spacing: 2
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                C.AppText {
                    anchors.centerIn: parent
                    width: parent.width - 80
                    visible: pickList.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Chat.pickerKind === "archive" ? I18n.tr("Nothing saved in the Search Archive yet.")
                                                        : I18n.tr("Run a search in Niche Finder first — its results show up here.")
                    color: Theme.on_surface_var
                }
                delegate: AbstractButton {
                    id: prow
                    width: pickList.width - 28
                    implicitHeight: 72
                    hoverEnabled: true
                    enabled: !modelData.added
                    readonly property bool on: picker.picked[modelData.i] === true
                    HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: prow.enabled }
                    onClicked: picker.toggle(modelData.i)
                    background: Rectangle {
                        radius: 14
                        color: prow.on ? U.withAlpha(Theme.primary, 0.08) : (prow.hovered ? U.withAlpha(Theme.on_surface, 0.05) : "transparent")
                        border.width: prow.on ? 1 : 0
                        border.color: U.withAlpha(Theme.primary, 0.35)
                    }
                    padding: 10
                    contentItem: RowLayout {
                        spacing: 12
                        opacity: modelData.added ? 0.45 : 1
                        Rectangle {
                            Layout.preferredWidth: 22; Layout.preferredHeight: 22
                            radius: 7
                            color: prow.on ? Theme.primary : "transparent"
                            border.width: prow.on ? 0 : 1.5
                            border.color: Theme.border_med
                            C.IconGlyph { anchors.centerIn: parent; visible: prow.on || modelData.added; name: "check"; size: 14; glyphColor: prow.on ? Theme.on_primary : Theme.on_surface_var }
                        }
                        C.RoundThumb { Layout.preferredWidth: 92; Layout.preferredHeight: 52; source: modelData.thumbSrc; radius: 9; badge: modelData.dur }
                        Column {
                            Layout.fillWidth: true
                            spacing: 3
                            C.AppText { width: parent.width; text: modelData.title; elide: Text.ElideRight; weight: Tokens.weightBold; color: Theme.text_strong }
                            Row {
                                spacing: 6
                                MultBadge { mult: modelData.mult; label: modelData.multLabel; anchors.verticalCenter: parent.verticalCenter }
                                C.AppText { anchors.verticalCenter: parent.verticalCenter; text: modelData.channel + " · " + modelData.views + " " + I18n.tr("views") + (modelData.added ? " · " + I18n.tr("already added") : ""); color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption }
                            }
                        }
                    }
                }
            }
        }
        footer: Item {
            implicitHeight: 72
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22; anchors.rightMargin: 22
                spacing: 8
                C.AppText { Layout.fillWidth: true; text: I18n.tr("{n} of {m} videos").replace("{n}", pickList.count).replace("{m}", Chat.pickerTotal); color: Theme.outline; font.pixelSize: Tokens.fontCaption }
                C.PrimaryButton { variant: "ghost"; text: I18n.tr("Cancel"); onClicked: picker.close() }
                C.PrimaryButton {
                    enabled: picker.pickedCount > 0
                    iconName: "add"
                    text: picker.pickedCount > 0 ? I18n.tr("Add {n} video(s)").replace("{n}", picker.pickedCount) : I18n.tr("Add videos")
                    onClicked: {
                        Chat.addPicked(Object.keys(picker.picked).map(function (k) { return parseInt(k) }))
                        picker.close()
                        composerInput.forceActiveFocus()
                    }
                }
            }
        }
    }

    // ── YouTube links (v3.49: one or a whole batch) ──
    Sheet {
        id: linkDialog
        width: Math.min(560, page.width - 60)
        title: I18n.tr("Add YouTube links")
        // `Chat` is a context property: during window teardown it is already
        // null while this binding is re-evaluated, which used to print
        // "Cannot call method 'countLinks' of null" on every exit.
        readonly property int found: Chat ? Chat.countLinks(linkField.text) : 0
        function submit() {
            if (found <= 0 || Chat.linksBusy) return
            Chat.addLinks(linkField.text)
            linkDialog.close()
        }
        onAboutToShow: linkField.text = ""
        onOpened: linkField.focusEnd()
        contentItem: ColumnLayout {
            spacing: 8
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            C.TextAreaField {
                id: linkField
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                rows: 5
                label: I18n.tr("Paste one link, or many (one per line, or separated by spaces / commas)")
                labelIcon: "link"
                placeholder: "https://youtube.com/watch?v=…\nhttps://youtu.be/…\nhttps://youtube.com/shorts/…"
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 8
                Rectangle {
                    visible: linkField.text.trim() !== ""
                    implicitHeight: 24; implicitWidth: foundTxt.implicitWidth + 18
                    radius: 12
                    color: U.withAlpha(linkDialog.found > 0 ? Theme.secondary_container : Theme.warn, 0.14)
                    C.AppText {
                        id: foundTxt
                        anchors.centerIn: parent
                        text: linkDialog.found > 0
                              ? I18n.tr("{n} video(s) found").replace("{n}", linkDialog.found)
                              : I18n.tr("No YouTube link found yet")
                        font.pixelSize: Tokens.fontCaption
                        weight: Tokens.weightDemiBold
                        color: linkDialog.found > 0 ? Theme.secondary_container : Theme.warn
                    }
                }
                Item { Layout.fillWidth: true }
            }
            C.AppText {
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                wrapMode: Text.Wrap
                text: I18n.tr("Up to 50 at once. With a YouTube API key the exact stats and subscriber counts are fetched for the whole batch in one go (2 quota units total).")
                color: Theme.on_surface_var
                font.pixelSize: Tokens.fontCaption
            }
        }
        footer: Item {
            implicitHeight: 72
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 8
                Item { Layout.fillWidth: true }
                C.PrimaryButton { variant: "ghost"; text: I18n.tr("Cancel"); onClicked: linkDialog.close() }
                C.PrimaryButton {
                    iconName: "add"
                    text: linkDialog.found > 1 ? I18n.tr("Add {n} videos").replace("{n}", linkDialog.found) : I18n.tr("Add")
                    enabled: linkDialog.found > 0 && !Chat.linksBusy
                    onClicked: linkDialog.submit()
                }
            }
        }
    }

    // ── Brief analyser (v3.49) ──
    // Two ways in: saved Niche Scan snapshots (their research brief + the
    // measured numbers it was written from), or a brief pasted as text — a
    // client's, a sponsor's, or the creator's own plan. Both land on the
    // composer as chips; the system prompt has a dedicated "analysing a
    // brief" playbook for them.
    Sheet {
        id: briefDialog
        width: Math.min(640, page.width - 60)
        height: Math.min(700, page.height - 60)
        title: I18n.tr("Analyse a brief")
        property var picked: ({})
        property int pickedCount: 0
        readonly property bool hasText: briefText.text.trim() !== ""
        onAboutToShow: { picked = {}; pickedCount = 0; briefText.text = ""; briefTitle.text = "" }
        function toggle(k) {
            var p = Object.assign({}, picked)
            if (p[k]) delete p[k]; else p[k] = true
            picked = p
            pickedCount = Object.keys(p).length
        }
        function submit() {
            var n = 0
            if (pickedCount > 0) { Chat.addBriefs(Object.keys(picked)); n += pickedCount }
            if (hasText) { Chat.addWrittenBrief(briefTitle.text, briefText.text); n += 1 }
            briefDialog.close()
            if (n > 0 && composerInput.text.trim() === "")
                composerInput.text = n > 1
                    ? I18n.tr("Analyse these briefs: what's strong, what's missing, and what should I make from them?")
                    : I18n.tr("Analyse this brief: what's strong, what's missing, and what should I make from it?")
            composerInput.forceActiveFocus()
            composerInput.cursorPosition = composerInput.length
        }
        contentItem: ColumnLayout {
            spacing: 10
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            C.AppText {
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                text: I18n.tr("Saved Niche Scan briefs")
                weight: Tokens.weightBold
                color: Theme.text_strong
            }
            ListView {
                id: briefList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                clip: true
                model: Chat.briefChoices
                leftMargin: 14; rightMargin: 14
                spacing: 2
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                C.AppText {
                    anchors.centerIn: parent
                    width: parent.width - 80
                    visible: briefList.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: I18n.tr("No saved briefs yet. Run a Niche Scan and its brief shows up here, or paste one below.")
                    color: Theme.on_surface_var
                }
                delegate: AbstractButton {
                    id: brow
                    width: briefList.width - 28
                    implicitHeight: 58
                    hoverEnabled: true
                    enabled: !modelData.added
                    readonly property bool on: briefDialog.picked[modelData.key] === true
                    HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: brow.enabled }
                    onClicked: briefDialog.toggle(modelData.key)
                    background: Rectangle {
                        radius: 14
                        color: brow.on ? U.withAlpha(Theme.primary, 0.08) : (brow.hovered ? U.withAlpha(Theme.on_surface, 0.05) : "transparent")
                        border.width: brow.on ? 1 : 0
                        border.color: U.withAlpha(Theme.primary, 0.35)
                    }
                    padding: 10
                    contentItem: RowLayout {
                        spacing: 12
                        opacity: modelData.added ? 0.45 : 1
                        Rectangle {
                            Layout.preferredWidth: 22; Layout.preferredHeight: 22
                            radius: 7
                            color: brow.on ? Theme.primary : "transparent"
                            border.width: brow.on ? 0 : 1.5
                            border.color: Theme.border_med
                            C.IconGlyph { anchors.centerIn: parent; visible: brow.on || modelData.added; name: "check"; size: 14; glyphColor: brow.on ? Theme.on_primary : Theme.on_surface_var }
                        }
                        Rectangle {
                            Layout.preferredWidth: 36; Layout.preferredHeight: 36
                            radius: 11
                            color: U.withAlpha(modelData.hasBrief ? Theme.tertiary : Theme.on_surface_var, 0.13)
                            C.IconGlyph { anchors.centerIn: parent; name: modelData.hasBrief ? "page_insights" : "data"; size: 18; glyphColor: modelData.hasBrief ? Theme.tertiary : Theme.on_surface_var }
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 3
                            C.AppText { width: parent.width; text: modelData.query; elide: Text.ElideRight; weight: Tokens.weightBold; color: Theme.text_strong }
                            C.AppText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: [modelData.kind,
                                       I18n.tr("{n} videos").replace("{n}", modelData.videos),
                                       modelData.when,
                                       modelData.added ? I18n.tr("already added") : ""].filter(function (x) { return x }).join(" · ")
                                color: Theme.on_surface_var
                                font.pixelSize: Tokens.fontCaption
                            }
                        }
                    }
                }
            }
            Hairline { Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22 }
            C.LineField {
                id: briefTitle
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                label: I18n.tr("Or paste a brief (a client's, a sponsor's, or your own plan)")
                placeholder: I18n.tr("Brief name (optional)")
            }
            C.TextAreaField {
                id: briefText
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                rows: 5
                softLimit: 12000
                placeholder: I18n.tr("Goal, audience, the idea, deliverables, deadline… paste it as it is.")
            }
        }
        footer: Item {
            implicitHeight: 72
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 8
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("Hunter checks every claim against the numbers it came from.")
                    color: Theme.outline
                    font.pixelSize: Tokens.fontCaption
                    elide: Text.ElideRight
                }
                C.PrimaryButton { variant: "ghost"; text: I18n.tr("Cancel"); onClicked: briefDialog.close() }
                C.PrimaryButton {
                    iconName: "page_insights"
                    enabled: briefDialog.pickedCount > 0 || briefDialog.hasText
                    text: (briefDialog.pickedCount + (briefDialog.hasText ? 1 : 0)) > 1
                          ? I18n.tr("Add {n} briefs").replace("{n}", briefDialog.pickedCount + (briefDialog.hasText ? 1 : 0))
                          : I18n.tr("Add brief")
                    onClicked: briefDialog.submit()
                }
            }
        }
    }

    // ── Google Drive ──
    Sheet {
        id: driveDialog
        width: Math.min(620, page.width - 60)
        height: Math.min(640, page.height - 60)
        title: "Google Drive"
        contentItem: ColumnLayout {
            spacing: 12
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            // share link — always works, no sign-in
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 8
                C.LineField {
                    id: driveLink
                    Layout.fillWidth: true
                    label: I18n.tr("Share link (Anyone with the link)")
                    placeholder: "https://drive.google.com/…"
                    onAccepted: if (text.trim() !== "") { Chat.addLink(text); text = ""; driveDialog.close() }
                }
                C.PrimaryButton {
                    Layout.alignment: Qt.AlignBottom
                    text: I18n.tr("Import")
                    enabled: driveLink.text.trim() !== "" && !Chat.driveBusy
                    onClicked: { Chat.addLink(driveLink.text); driveLink.text = ""; driveDialog.close() }
                }
            }
            Hairline { Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22 }

            // not configured → setup
            ColumnLayout {
                visible: !Chat.driveConfigured
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 8
                C.AppText { text: I18n.tr("Browse My Drive (optional setup)"); weight: Tokens.weightBold; color: Theme.text_strong }
                C.AppText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: I18n.tr("Create an OAuth client of type “Desktop app” in Google Cloud Console (APIs & Services → Credentials), enable the Drive API, then paste its ID and secret here once.")
                    color: Theme.on_surface_var
                    font.pixelSize: Tokens.fontCaption
                }
                C.LineField { id: cidField; Layout.fillWidth: true; label: I18n.tr("Client ID"); placeholder: "…apps.googleusercontent.com" }
                C.LineField { id: secField; Layout.fillWidth: true; label: I18n.tr("Client secret"); echoMode: TextInput.Password }
                C.PrimaryButton {
                    Layout.alignment: Qt.AlignRight
                    text: I18n.tr("Save")
                    enabled: cidField.text.trim() !== ""
                    onClicked: Chat.saveDriveCredentials(cidField.text, secField.text)
                }
            }
            // configured, not connected
            ColumnLayout {
                visible: Chat.driveConfigured && !Chat.driveConnected
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 10
                C.AppText { Layout.fillWidth: true; wrapMode: Text.Wrap; text: I18n.tr("Connect your Google account (read-only) to pick private files from My Drive."); color: Theme.on_surface_var }
                RowLayout {
                    spacing: 8
                    C.PrimaryButton { iconName: "link"; text: I18n.tr("Connect Google Drive"); enabled: !Chat.driveBusy; onClicked: Chat.connectDrive() }
                    C.PrimaryButton { visible: Chat.driveBusy; variant: "ghost"; text: I18n.tr("Cancel"); onClicked: Chat.cancelDrive() }
                }
            }
            // connected → browser
            RowLayout {
                visible: Chat.driveConnected
                Layout.fillWidth: true
                Layout.leftMargin: 22; Layout.rightMargin: 22
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 38
                    radius: Tokens.radiusMd; color: Theme.input_bg; border.width: 1; border.color: Theme.border
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                        C.IconGlyph { name: "search"; size: 15; glyphColor: Theme.outline }
                        TextField {
                            id: driveSearch
                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                            T.ContextMenu.menu: C.EditMenu { editor: driveSearch }
                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                            selectedTextColor: Theme.text_strong
                            Layout.fillWidth: true
                            background: null; padding: 0
                            color: Theme.on_surface
                            placeholderText: I18n.tr("Search My Drive")
                            placeholderTextColor: Theme.outline
                            font.family: Fonts.familyFor("body", Tokens.weightRegular, text)
                            font.pixelSize: Tokens.fontBody
                            onAccepted: Chat.listDrive(text)
                        }
                    }
                }
                C.AppText { text: Chat.driveEmail; color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                C.IconButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; iconName: "refresh"; glyphSize: 15; tip: I18n.tr("Refresh"); onClicked: Chat.listDrive(driveSearch.text) }
                C.IconButton { Layout.preferredWidth: 34; Layout.preferredHeight: 34; iconName: "close"; glyphSize: 15; tip: I18n.tr("Disconnect"); onClicked: Chat.disconnectDrive() }
            }
            C.AppText {
                visible: Chat.driveBusy && Chat.driveStatus !== ""
                Layout.leftMargin: 22
                text: Chat.driveStatus
                color: Theme.on_surface_var
                font.pixelSize: Tokens.fontCaption
            }
            ListView {
                id: driveList
                visible: Chat.driveConnected
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: Chat.driveFiles
                leftMargin: 14; rightMargin: 14
                spacing: 2
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: AbstractButton {
                    id: drow
                    width: driveList.width - 28
                    implicitHeight: 54
                    hoverEnabled: true
                    enabled: !Chat.driveBusy
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: { Chat.importDriveFile(modelData.id); driveDialog.close() }
                    background: Rectangle { radius: 12; color: drow.hovered ? U.withAlpha(Theme.on_surface, 0.06) : "transparent" }
                    padding: 8
                    contentItem: RowLayout {
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 38; Layout.preferredHeight: 38
                            radius: 11; color: Theme.surface_highest
                            C.IconGlyph { anchors.centerIn: parent; name: page.kindIcon(modelData.kind); size: 18; glyphColor: page.kindColor(modelData.kind) }
                        }
                        Column {
                            Layout.fillWidth: true
                            C.AppText { width: parent.width; text: modelData.name; elide: Text.ElideRight; weight: Tokens.weightDemiBold; color: Theme.text_strong }
                            C.AppText { text: [modelData.modified, modelData.sizeLabel].filter(function (x) { return x }).join(" · "); color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption }
                        }
                        C.IconGlyph { name: "add"; size: 16; glyphColor: Theme.on_surface_var }
                    }
                }
            }
            Item { visible: !Chat.driveConnected; Layout.fillHeight: true }
        }
        footer: Item {
            implicitHeight: 16
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
        }
    }

    // ── delete confirmation ──
    Sheet {
        id: confirmDelete
        width: Math.min(460, page.width - 80)
        title: I18n.tr("Delete this conversation?")
        property int pendingId: -1
        property string pendingTitle: ""
        function ask(id, t) { pendingId = id; pendingTitle = t || ""; open() }
        contentItem: ColumnLayout {
            spacing: 6
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            C.AppText { Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22; text: confirmDelete.pendingTitle; weight: Tokens.weightDemiBold; wrapMode: Text.Wrap; color: Theme.on_surface }
            C.AppText { Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22; text: I18n.tr("Its messages and imported files are removed for good."); wrapMode: Text.Wrap; color: Theme.on_surface_var; font.pixelSize: Tokens.fontCaption }
        }
        footer: Item {
            implicitHeight: 72
            LayoutMirroring.enabled: I18n.rtl; LayoutMirroring.childrenInherit: true   // mirror — see the note in Sheet
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 8
                Item { Layout.fillWidth: true }
                C.PrimaryButton { variant: "ghost"; text: I18n.tr("Cancel"); onClicked: confirmDelete.close() }
                C.PrimaryButton { variant: "danger"; iconName: "delete_outline"; text: I18n.tr("Delete"); onClicked: { Chat.deleteThread(confirmDelete.pendingId); confirmDelete.close() } }
            }
        }
    }

    C.Toast { id: toast; z: 100; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 170 }
}
