import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// ═══════════════════════════════════════════════════════════════════════════
//  BlueprintPane — v14 (3.15): four acts + the v6 schema pack
//
//  v14 (on top of v13 below):
//    * A fourth act, Grow — what happens after you hit publish: Checkpoints
//      (1h / 24h / 7d), If it stalls (moved from Launch), Reply bank, Series
//      (moved from Launch). Launch is now just "how it ships on day one".
//    * New v6 sections: Why now + Discovery (Strategy), Delivery
//      (Production), Cards & end screen (Launch).
//    * Competition rows rebuilt: a real 16:9 thumbnail, the whole card is a
//      link (video, or a YouTube search when the row has no video), and the
//      row mirrors with the UI instead of pinning to the top-left corner.
//
//  BlueprintPane — v13 "Pitch slate" cover + the v5 schema pack
//
//  v13 (on top of v12 below):
//    * The 9:16 phone preview is gone. The cover is now a pitch slate: the
//      idea, then an OPENING card (what is said, seen and promised in the
//      first 3 seconds) beside a SCORE card that shows the score as five
//      audited 0-20 parts plus the model-free "blueprint check" (timing,
//      title length, hook length, data citations, completeness).
//    * New sections for the v5 schema: Promise (Strategy); On-screen text,
//      Look & sound, Prep & gear (Production); Test plan, Rights, If it
//      stalls, plus a Community teaser in Caption (Launch).
//    * Script rows show what is ON SCREEN under the words; shots name the
//      beat they cover.
//
//  v12 "Production Dossier" (2026 redesign)
//
//  The full production blueprint for ONE idea, rebuilt from scratch.
//
//  What changed from v11 (the numbered spine of folding cards):
//    * The cover is a statement, not a card: a big title, a 20-tick score
//      meter and four stats on one side, and the idea PLAYING as a 9:16 Short
//      on the other (the script, beat by beat, with Shorts-style captions).
//    * The three phases are real tabs — Strategy · Production · Launch — in a
//      bar that sticks to the top of the page while you scroll, with jump
//      chips for every section of the open phase. Only one phase is laid out
//      at a time, so the pane is a third as tall and reads like a dossier.
//    * Each phase owns ONE colour (Strategy = tertiary violet, Production =
//      caption amber, Launch = green) and nothing else is decorated.
//    * Production opens on an "edit bay": the script, the re-hooks and the
//      retention phases on ONE time axis, sharing a playhead with the cover
//      preview. Click / drag the track to scrub.
//    * Every section is composed for its content: an A/B/C hook lab, picker
//      tiles for the thumbnail prompts, a risk → fix ledger, a first-hour
//      checklist you can tick, episode cards for the series.
//
//  Public API is unchanged — both hosts (AI Ideas, Content Lab) keep working:
//    idea, regenerating, scroller,
//    favorited / deleteRequested / regenerateRequested / copyRequested /
//    prompterRequested.
//
//  Data: the flattened dict from app.qml_backend.vm._idea_shape.idea_for_qml.
//  v12 adds `startSec` / `endSec` to every script row, `atSec` to every
//  re-hook, and `totalSeconds` / `totalLabel` / `timelineExact` — see
//  _timed_script() there. Every section hides itself when its data is absent.
// ═══════════════════════════════════════════════════════════════════════════
Item {
    id: root

    // ── public API (unchanged) ──
    property var idea: ({})
    property bool regenerating: false
    property var scroller: null

    signal favorited(int ideaId)
    signal deleteRequested(int ideaId)
    signal regenerateRequested(int ideaId)
    signal copyRequested(string text)
    signal prompterRequested(int ideaId)

    implicitHeight: col.implicitHeight

    // ── guarded accessors (idea starts as {}) ──
    readonly property var angle: idea.viralAngle || ({})
    readonly property var hookData: idea.hook || ({})
    readonly property var antiHookData: idea.antiHook || ({})
    readonly property var exec: idea.execution || ({})
    readonly property var pack: idea.packaging || ({})
    readonly property var comp: idea.competitors || ({})
    readonly property var ret: idea.retention || ({})
    readonly property var seo: idea.seo || ({})
    readonly property var audience: idea.audienceProfile || ({})
    readonly property var monet: idea.monetization || ({})
    readonly property var caption: idea.captionPack || ({})
    readonly property var plan: idea.publishPlan || ({})
    readonly property var script: idea.fullScript || []
    // ── v5 pack ──
    readonly property var promise: idea.promise || ({})
    readonly property var styleG: idea.styleGuide || ({})
    readonly property var prod: idea.productionPlan || ({})
    readonly property var ab: idea.abPlan || ({})
    readonly property var rights: idea.rights || ({})
    readonly property var audit: idea.audit || ({})
    readonly property bool auditAllOk: (audit.total || 0) > 0 && audit.passed === audit.total
    readonly property color rightsAccent: rights.risk === "High" ? Theme.error
                                        : rights.risk === "Medium" ? Theme.warn
                                        : Theme.secondary_container

    // fixed tile ink for the thumbnail concept tiles (dark in both themes)
    readonly property color inkDeep: "#0B0910"

    readonly property int score: idea.score || 0
    readonly property color scoreColor: score >= 85 ? Theme.secondary_container
                                      : score >= 70 ? Theme.primary
                                      : Theme.warn
    readonly property color monetAccent: monet.adSafety === "Risky" ? Theme.error
                                       : monet.adSafety === "Limited" ? Theme.warn
                                       : Theme.secondary_container

    // ── responsive breakpoints (the pane sits beside a rail on AI Ideas) ──
    readonly property bool wide: width >= 900
    readonly property bool mid: width >= 640

    // ── the three acts ──
    // One colour per act, taken from the live theme so light / dark and every
    // accent keep working. Primary (the user's accent) is deliberately NOT an
    // act colour: it stays reserved for actions.
    // v3.15 adds a fourth act, Grow (after you hit publish), in a sky blue
    // that sits apart from all three — still not the primary accent.
    readonly property color growColor: Theme.isDark ? "#62C6F0" : "#0F7FB3"
    function actColor(a) {
        return a === 0 ? Theme.tertiary : a === 1 ? Theme.warn
             : a === 2 ? Theme.secondary_container : growColor
    }
    readonly property var acts: [
        { name: I18n.tr("Strategy"),   sub: I18n.tr("why it spreads and how it opens") },
        { name: I18n.tr("Production"), sub: I18n.tr("what you say, shoot and cut") },
        { name: I18n.tr("Launch"),     sub: I18n.tr("how it ships on day one") },
        { name: I18n.tr("Grow"),       sub: I18n.tr("the first week, and what comes next") }
    ]
    property int activeAct: 0
    // The star on the cover. A plain binding when the pane is used on its
    // own; BlueprintStage overwrites it on a favourite toggle so starring an
    // idea doesn't rebind the whole 4-act pane just to flip one icon.
    property bool favOn: idea.isFavorite === true

    // Persian digits for the act numbers on a Persian install.
    function num(x) {
        var s = String(x)
        if (!I18n.rtl) return s
        var fa = "۰۱۲۳۴۵۶۷۸۹"
        return s.replace(/[0-9]/g, function(d) { return fa.charAt(parseInt(d)) })
    }
    function fmt(sec) {
        var s = Math.max(0, Math.floor(sec || 0))
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
        var mm = h > 0 ? (m < 10 ? "0" + m : String(m)) : String(m)
        return (h > 0 ? h + ":" : "") + mm + ":" + (r < 10 ? "0" : "") + r
    }

    // ── section presence ──
    readonly property bool hasAngle: (angle.concept || "") !== "" || (angle.triggers || []).length > 0
    readonly property bool hasHook: (hookData.visual || []).length > 0 || (hookData.text || []).length > 0
                                    || idea.hasAntiHook === true
    readonly property bool hasThumbs: (idea.thumbnails || []).length > 0
    readonly property bool hasAudience: idea.hasAudience === true
    readonly property bool hasComp: idea.hasCompetitors === true
    readonly property bool hasEvidence: idea.hasEvidence === true
    readonly property bool hasPulse: idea.hasPulse === true
    readonly property bool hasScript: idea.hasScript === true && script.length > 0
    readonly property bool hasShots: idea.hasShots === true
    readonly property bool hasRehooks: idea.hasRehooks === true
    readonly property bool hasExec: (exec.editing || "") !== "" || (exec.assets || "") !== ""
                                    || (exec.audio || "") !== "" || (exec.render || "") !== ""
    readonly property bool hasRet: (ret.phases || []).length > 0
    readonly property bool hasTitles: (idea.titles || []).length > 0 || (pack.framework || "") !== ""
    readonly property bool hasPlan: idea.hasPublishPlan === true || (pack.timing || "") !== ""
    readonly property bool hasCaption: idea.hasCaptionPack === true || idea.hasCta === true
                                       || (idea.pinnedComment || "") !== ""
                                       || (idea.communityPost || "") !== ""
    readonly property bool hasSeo: idea.hasSeo === true
    readonly property bool hasMoney: idea.hasMonetization === true || idea.hasRepurpose === true
    readonly property bool hasRisks: idea.hasRisks === true
    readonly property bool hasSeries: idea.hasSeriesNext === true
    readonly property bool hasScoreParts: idea.hasScoreParts === true
    readonly property bool hasPromise: idea.hasPromise === true
    readonly property bool hasStyle: idea.hasStyle === true
    readonly property bool hasOnScreen: idea.hasOnScreen === true
    readonly property bool hasProduction: idea.hasProduction === true
    readonly property bool hasAbPlan: idea.hasAbPlan === true
    readonly property bool hasPlaybook: idea.hasPlaybook === true
    readonly property bool hasRights: idea.hasRights === true
    // ── v6 pack ──
    readonly property var whyNow: idea.whyNow || ({})
    readonly property var disc: idea.discovery || ({})
    readonly property var deliv: idea.delivery || ({})
    readonly property var endS: idea.endScreen || ({})
    readonly property bool hasWhyNow: idea.hasWhyNow === true
    readonly property bool hasDiscovery: idea.hasDiscovery === true
    readonly property bool hasDelivery: idea.hasDelivery === true
    readonly property bool hasEndScreen: idea.hasEndScreen === true
    readonly property bool hasCheckpoints: idea.hasCheckpoints === true
    readonly property bool hasReplies: idea.hasReplyBank === true
    readonly property color shelfColor: whyNow.shelfLife === "Trending" ? Theme.error
                                      : whyNow.shelfLife === "Seasonal" ? Theme.warn
                                      : Theme.secondary_container

    // Every section that has data, in reading order, tagged with its act.
    // Drives the act tabs (counts), the jump chips and the "next act" card.
    readonly property var navModel: {
        var all = [
            { it: sPromise,  has: hasPromise,  act: 0, label: I18n.tr("Promise") },
            { it: sWhyNow,   has: hasWhyNow,   act: 0, label: I18n.tr("Why now") },
            { it: sAngle,    has: hasAngle,    act: 0, label: I18n.tr("Angle") },
            { it: sHook,     has: hasHook,     act: 0, label: I18n.tr("Hook") },
            { it: sThumbs,   has: hasThumbs,   act: 0, label: I18n.tr("Thumbnails") },
            { it: sAudience, has: hasAudience, act: 0, label: I18n.tr("Audience") },
            { it: sDiscovery, has: hasDiscovery, act: 0, label: I18n.tr("Discovery") },
            { it: sComp,     has: hasComp,     act: 0, label: I18n.tr("Competition") },
            { it: sEvidence, has: hasEvidence, act: 0, label: I18n.tr("Evidence") },
            { it: sPulse,    has: hasPulse,    act: 0, label: I18n.tr("Data pulse") },
            { it: sBay,      has: hasScript,   act: 1, label: I18n.tr("Timeline") },
            { it: sScript,   has: hasScript,   act: 1, label: I18n.tr("Script") },
            { it: sDelivery, has: hasDelivery, act: 1, label: I18n.tr("Delivery") },
            { it: sShots,    has: hasShots,    act: 1, label: I18n.tr("Shots") },
            { it: sRehooks,  has: hasRehooks,  act: 1, label: I18n.tr("Re-hooks") },
            { it: sOverlay,  has: hasOnScreen, act: 1, label: I18n.tr("On-screen text") },
            { it: sExec,     has: hasExec,     act: 1, label: I18n.tr("Edit") },
            { it: sStyle,    has: hasStyle,    act: 1, label: I18n.tr("Look & sound") },
            { it: sRet,      has: hasRet,      act: 1, label: I18n.tr("Pacing") },
            { it: sPrep,     has: hasProduction, act: 1, label: I18n.tr("Prep & gear") },
            { it: sTitles,   has: hasTitles,   act: 2, label: I18n.tr("Titles") },
            { it: sAb,       has: hasAbPlan,   act: 2, label: I18n.tr("Test plan") },
            { it: sPlan,     has: hasPlan,     act: 2, label: I18n.tr("Publish") },
            { it: sCaption,  has: hasCaption,  act: 2, label: I18n.tr("Caption & CTA") },
            { it: sEndScreen, has: hasEndScreen, act: 2, label: I18n.tr("Cards & end screen") },
            { it: sSeo,      has: hasSeo,      act: 2, label: I18n.tr("SEO") },
            { it: sMoney,    has: hasMoney,    act: 2, label: I18n.tr("Monetization") },
            { it: sRights,   has: hasRights,   act: 2, label: I18n.tr("Rights") },
            { it: sRisks,    has: hasRisks,    act: 2, label: I18n.tr("Risks") },
            { it: sCheckpoints, has: hasCheckpoints, act: 3, label: I18n.tr("Checkpoints") },
            { it: sPlaybook, has: hasPlaybook, act: 3, label: I18n.tr("If it stalls") },
            { it: sReplies,  has: hasReplies,  act: 3, label: I18n.tr("Reply bank") },
            { it: sSeries,   has: hasSeries,   act: 3, label: I18n.tr("Series") }
        ]
        var out = []
        for (var i = 0; i < all.length; i++) if (all[i].has) out.push(all[i])
        return out
    }
    function actSections(a) {
        var out = []
        for (var i = 0; i < navModel.length; i++) if (navModel[i].act === a) out.push(navModel[i])
        return out
    }
    function actCount(a) { return actSections(a).length }
    function firstAct() {
        for (var a = 0; a < acts.length; a++) if (actCount(a) > 0) return a
        return 0
    }
    function nextAct(a) {
        for (var n = a + 1; n < acts.length; n++) if (actCount(n) > 0) return n
        return -1
    }

    // ── idea switch: replay the entrance, reset per-idea state ──
    property int revealTick: 0
    property int _lastId: -1
    property int thumbPick: 0
    property var planDone: ({})
    property var prepDone: ({})
    property var cpDone: ({})
    onIdeaChanged: _primeForIdea()
    // v3.16-p3: BlueprintStage creates a fresh pane per idea (asynchronously)
    // with `idea` already set, so the change handler never fires there —
    // prime the per-idea state once the pane finishes building instead.
    Component.onCompleted: _primeForIdea()
    function _primeForIdea() {
        var nid = (idea && idea.id) ? idea.id : 0
        if (nid !== _lastId) {
            _lastId = nid
            thumbPick = 0
            planDone = ({})
            prepDone = ({})
            cpDone = ({})
            playT = 0
            playing = true
            revealTick++
            heroIn.restart()
            scoreIn.to = idea.score || 0
            scoreIn.restart()
            // the has-flags settle in the same pass; read them after it
            Qt.callLater(function() { root.activeAct = root.firstAct() })
        }
    }

    // ── act switching + jumping ──
    property var _pendingJump: null
    Timer {
        id: jumpTimer
        interval: 60
        onTriggered: {
            if (root._pendingJump && root.scroller && root.scroller.scrollToItem)
                root.scroller.scrollToItem(root._pendingJump, actBar.height + Tokens.space5)
            root._pendingJump = null
        }
    }
    function setAct(a) {
        if (a === activeAct) return
        var wasStuck = stickY > 0
        activeAct = a
        // If the bar is stuck, the reader is deep in the old act: bring them
        // to the top of the new one rather than the middle of it.
        if (wasStuck) { _pendingJump = actWrap; jumpTimer.restart() }
    }
    function jumpTo(entry) {
        if (!entry || !entry.it) return
        if (entry.act !== activeAct) activeAct = entry.act
        _pendingJump = entry.it
        jumpTimer.restart()
    }

    // ── sticky act bar ──
    // The bar's resting slot (actWrap) stays in the column; the bar itself is
    // offset by how far the page has scrolled past that slot, clamped to the
    // end of the pane. Re-evaluated on every contentY change.
    readonly property var _flick: scroller && scroller.contentItem ? scroller.contentItem : null
    readonly property real _scrollY: _flick ? _flick.contentY : 0
    readonly property real stickY: {
        var sy = _scrollY
        var colH = col.height
        if (!_flick || !actWrap.visible) return 0
        var host = _flick.contentItem ? _flick.contentItem : _flick
        var p = actWrap.mapToItem(host, 0, 0)
        var off = sy - p.y + Tokens.space2
        var maxOff = colH - actWrap.y - actBar.height - Tokens.space8 * 2
        return Math.max(0, Math.min(off, maxOff))
    }

    // ── playback: one playhead for the cover preview and the edit bay ──
    readonly property real total: Math.max(1, idea.totalSeconds || 0)
    property real playT: 0
    property bool playing: true
    Timer {
        interval: 33
        repeat: true
        running: root.playing && root.visible && root.hasScript && Tokens.appActive
        onTriggered: root.playT = (root.playT + interval / 1000) % root.total
    }
    function seek(s) { playT = Math.max(0, Math.min(total - 0.01, s)) }
    readonly property int beat: {
        var t = playT
        for (var i = 0; i < script.length; i++) {
            var s = script[i]
            if (t >= (s.startSec || 0) && t < (s.endSec || 0)) return i
        }
        return script.length > 0 ? script.length - 1 : -1
    }
    readonly property var beatRow: beat >= 0 ? script[beat] : ({})

    function speakerLabel(sp) {
        var k = String(sp || "")
        if (k === "VO") return I18n.tr("Voice")
        if (k === "Music") return I18n.tr("Scene & sound")
        if (k === "On-screen") return I18n.tr("On-screen text")
        if (k === "On-camera") return I18n.tr("On camera")
        return k
    }
    function speakerColor(sp) {
        var k = String(sp || "")
        if (k === "Music") return Theme.tertiary
        if (k === "On-screen") return Theme.warn
        return Theme.text_strong
    }
    function isScene(sp) { return String(sp || "") === "Music" }

    // ════════════════════════ building blocks ════════════════════════
    // Inline components cannot see this file's ids, so everything they need
    // arrives as a property (`host` is the pane root where they need it).

    // Model-written text: direction follows the TEXT, not the UI language — a
    // Persian line in the English UI still reads right-to-left, an English
    // video title in the Persian UI still reads left-to-right.
    component Body: C.AppText {
        property bool verbatim: false
        readonly property bool _rtl: /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFC]/.test(text)
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.on_surface
        font.pixelSize: Tokens.fontLabel
        mono: verbatim
        selectable: true
        LayoutMirroring.enabled: false
        horizontalAlignment: _rtl ? Text.AlignRight : Text.AlignLeft
    }

    // A small uppercase caption above a value.
    component Caption: C.AppText {
        font.pixelSize: Tokens.fontCaption
        weight: Tokens.weightDemiBold
        color: Theme.outline
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    // A pill: verdict, format, focus tag, hashtag, sponsor.
    component Pill: Rectangle {
        id: pl
        property string text: ""
        property string glyph: ""
        property color tint: Theme.on_surface_var
        property bool mono: false
        property bool strong: false
        property int maxTextWidth: 420
        radius: Tokens.radiusPill
        color: U.withAlpha(tint, strong ? 0.16 : 0.08)
        border.width: 1
        border.color: U.withAlpha(tint, strong ? 0.42 : 0.26)
        implicitWidth: plRow.implicitWidth + Tokens.space4 + Tokens.space1
        implicitHeight: 30
        Row {
            id: plRow
            anchors.centerIn: parent
            spacing: 6
            C.IconGlyph {
                visible: pl.glyph !== ""
                name: pl.glyph
                size: 14
                glyphColor: pl.tint
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: pl.text
                mono: pl.mono
                font.pixelSize: Tokens.fontCaption + 1
                weight: pl.strong ? Tokens.weightBold : Tokens.weightMedium
                color: pl.tint
                width: Math.min(implicitWidth, pl.maxTextWidth)
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // A quiet surface with padding; children stack in a column.
    component Box: Rectangle {
        id: bx
        property int pad: Tokens.space5
        property alias spacing_: bxCol.spacing
        default property alias content: bxCol.data
        radius: Tokens.radiusXl
        color: Theme.surface_high
        border.width: 1
        border.color: Theme.border
        implicitHeight: bxCol.implicitHeight + pad * 2
        ColumnLayout {
            id: bxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: bx.pad
            spacing: Tokens.space3
        }
    }

    // A lettered option tile (A / B) with a copy button.
    component Option: Rectangle {
        id: op
        property string letter: ""
        property string body: ""
        property bool big: false
        property bool verbatim: false
        property color tint: Theme.primary
        signal copyClicked(string text)
        Layout.fillWidth: true
        radius: Tokens.radiusLg
        color: opHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
        border.width: 1
        border.color: opHover.hovered ? U.withAlpha(tint, 0.35) : Theme.border
        implicitHeight: Math.max(56, opRow.implicitHeight + Tokens.space4 * 2)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        HoverHandler { id: opHover }
        RowLayout {
            id: opRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space4
            spacing: Tokens.space3
            Rectangle {
                visible: op.letter !== ""
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                width: 24; height: 24; radius: Tokens.radiusXs
                color: U.withAlpha(op.tint, 0.14)
                C.AppText {
                    anchors.centerIn: parent
                    text: op.letter
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontCaption
                    color: op.tint
                }
            }
            Body {
                text: op.body
                verbatim: op.verbatim
                font.pixelSize: op.big ? Tokens.fontTitle - 1 : Tokens.fontLabel
                weight: op.big ? Tokens.weightExtraBold : Tokens.weightRegular
                color: op.big ? Theme.text_strong : Theme.on_surface
            }
            C.IconButton {
                Layout.alignment: Qt.AlignTop
                iconName: "content_copy"
                tip: I18n.tr("Copy")
                accent: Theme.primary
                implicitWidth: 28
                implicitHeight: 28
                opacity: opHover.hovered ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                onClicked: op.copyClicked(op.body)
            }
        }
    }

    // A folded "why this works" note — the longest prose in the pane, so it
    // stays out of the way until asked for.
    component WhyNote: ColumnLayout {
        id: why
        property string text_: ""
        property color accent: Theme.primary
        property bool open: false
        Layout.fillWidth: true
        visible: why.text_ !== ""
        spacing: Tokens.space2

        AbstractButton {
            id: whyBtn
            implicitHeight: 32
            implicitWidth: whyRow.implicitWidth
            onClicked: why.open = !why.open
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            background: Item {}
            contentItem: Item {
                implicitWidth: whyRow.implicitWidth
                implicitHeight: whyRow.implicitHeight
                Row {
                    id: whyRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.space2
                    C.IconGlyph { name: "sparkling"; size: 16; glyphColor: why.accent; anchors.verticalCenter: parent.verticalCenter }
                    C.AppText {
                        text: I18n.tr("Why this works")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontBody
                        color: why.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.IconGlyph {
                        name: "expand_more"; size: 16
                        glyphColor: why.accent
                        rotation: why.open ? 180 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
        // height animated on a plain clipping Item (never on a self-sizing
        // layout child — that fights the animation and loops)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: why.open ? whyTxt.implicitHeight : 0
            implicitHeight: why.open ? whyTxt.implicitHeight : 0
            clip: true
            visible: Layout.preferredHeight > 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            Body {
                id: whyTxt
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                text: why.text_
                font.pixelSize: Tokens.fontLabel
                color: Theme.on_surface_var
                opacity: why.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
        }
    }

    // A STAGE: kicker + big heading (+ an aside on the far side), then the
    // body. Belongs to one act; only the open act's stages are laid out.
    // Replays a staggered fade + rise whenever the idea or the act changes.
    component Stage: ColumnLayout {
        id: st
        property var host: null
        property int act: 0
        property int order: 0
        property bool has: true
        property string kicker: ""
        property string heading: ""
        default property alias content: stBody.data
        property alias aside: stAside.data
        readonly property color accent: host ? host.actColor(act) : Theme.primary

        Layout.fillWidth: true
        visible: has && host !== null && host.activeAct === act
        spacing: Tokens.space5

        readonly property int revealKey: host ? host.revealTick * 10 + host.activeAct : 0
        onRevealKeyChanged: stIn.restart()
        transform: Translate { id: stShift; y: 0 }
        SequentialAnimation {
            id: stIn
            PropertyAction { target: st; property: "opacity"; value: 0 }
            PropertyAction { target: stShift; property: "y"; value: 18 }
            PauseAnimation { duration: 40 + Math.min(6, st.order) * 60 }
            ParallelAnimation {
                NumberAnimation { target: st; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: stShift; property: "y"; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space4
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space1
                C.AppText {
                    text: st.kicker
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    font.letterSpacing: 1.8
                    color: st.accent
                    Layout.fillWidth: true
                }
                C.AppText {
                    text: st.heading
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontTitle + 4
                    color: Theme.text_strong
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
            RowLayout {
                id: stAside
                Layout.alignment: Qt.AlignBottom
                spacing: Tokens.space2
            }
        }
        ColumnLayout {
            id: stBody
            Layout.fillWidth: true
            spacing: Tokens.space3
        }
    }

    // ── entrance of the cover ──
    ParallelAnimation {
        id: heroIn
        NumberAnimation { target: hero; property: "opacity"; from: 0; to: 1; duration: Tokens.durSlow + 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: heroShift; property: "y"; from: 14; to: 0; duration: 520; easing.type: Easing.OutCubic }
    }
    property real scoreShown: 0
    NumberAnimation {
        id: scoreIn
        target: root; property: "scoreShown"
        from: 0; to: 0
        duration: 1100
        easing.type: Easing.OutCubic
    }
    onScoreChanged: if (!scoreIn.running) scoreShown = score

    // ══════════════════════════════ layout ══════════════════════════════
    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.space6

        // ═════════════ COVER — v13 "pitch slate" ═════════════
        // No device mock-up any more: the cover is the pitch itself. Left, the
        // idea and its opening (what is said, seen and promised in the first
        // three seconds); right, the score as five audited parts and the
        // model-free blueprint check; under both, what is inside the dossier.
        ColumnLayout {
            id: hero
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space5
            spacing: Tokens.space5
            transform: Translate { id: heroShift; y: 0 }

            // ── verdict, format, difficulty · actions ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    Rectangle {
                        visible: (root.idea.scoreLabel || "") !== ""
                        radius: Tokens.radiusPill
                        color: U.withAlpha(root.scoreColor, 0.12)
                        border.width: 1
                        border.color: U.withAlpha(root.scoreColor, 0.42)
                        implicitWidth: vRow.implicitWidth + Tokens.space4 + Tokens.space1
                        implicitHeight: 30
                        Row {
                            id: vRow
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle {
                                width: 7; height: 7; radius: 3.5
                                color: root.scoreColor
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: hero.visible && Tokens.appActive
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }
                            C.AppText {
                                text: root.idea.scoreLabel || ""
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                font.letterSpacing: 1.4
                                color: root.scoreColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    Pill {
                        glyph: root.idea.isLong ? "fmt_long" : "fmt_short"
                        text: root.idea.isLong ? I18n.tr("Long-form") : I18n.tr("Short")
                    }
                    Pill {
                        visible: (root.idea.difficultyLabel || "") !== ""
                        glyph: "tune"
                        text: I18n.tr("Production: {d}").replace("{d}", root.idea.difficultyLabel || "")
                        tint: root.idea.difficulty === "Hard" ? Theme.error
                            : root.idea.difficulty === "Easy" ? Theme.secondary_container : Theme.warn
                    }
                    Pill {
                        visible: root.hasRights && (root.rights.riskLabel || "") !== ""
                        glyph: "verified"
                        text: root.rights.riskLabel || ""
                        tint: root.rightsAccent
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.space1
                    C.IconButton {
                        iconName: "bookmark"
                        iconFill: root.favOn
                        active: root.favOn
                        accent: Theme.primary
                        tip: I18n.tr("Favorite")
                        onClicked: root.favorited(root.idea.id || 0)
                    }
                    C.IconButton {
                        iconName: "auto_awesome"
                        enabled: !root.regenerating
                        accent: Theme.primary
                        tip: I18n.tr("Regenerate this blueprint")
                        onClicked: root.regenerateRequested(root.idea.id || 0)
                    }
                    C.IconButton {
                        iconName: "delete_outline"
                        accent: Theme.error
                        tip: I18n.tr("Delete")
                        onClicked: root.deleteRequested(root.idea.id || 0)
                    }
                }
            }

            // ── the title: the loudest thing in the pane ──
            Body {
                text: root.idea.title || ""
                weight: Tokens.weightExtraBold
                font.pixelSize: root.mid ? 42 : 32
                lineHeight: 1.08
                color: Theme.text_strong
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: -Tokens.space2
                spacing: Tokens.space5
                Repeater {
                    model: [
                        { g: "user",     v: root.idea.audience || "" },
                        { g: "category", v: root.idea.pillar || "" },
                        { g: "link",     v: root.idea.source || "" }
                    ]
                    Row {
                        visible: (modelData.v || "") !== ""
                        spacing: 7
                        C.IconGlyph {
                            name: modelData.g
                            size: 15
                            glyphColor: index === 2 ? Theme.outline : Theme.on_surface_var
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.AppText {
                            text: modelData.v || ""
                            font.pixelSize: index === 2 ? Tokens.fontCaption + 1 : Tokens.fontLabel
                            color: index === 2 ? Theme.outline : Theme.on_surface_var
                            width: Math.min(implicitWidth, Math.max(140, hero.width - 60))
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // ── opening card + score card ──
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: Tokens.space5
                rowSpacing: Tokens.space5

                // THE OPENING — said, seen, promised
                Rectangle {
                    id: openCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    radius: Tokens.radiusXl
                    color: U.mix(Theme.surface_high, Theme.tertiary, Theme.isDark ? 0.07 : 0.04)
                    border.width: 1
                    border.color: U.withAlpha(Theme.tertiary, 0.26)
                    implicitHeight: openCol.implicitHeight + Tokens.space6 * 2
                    visible: (root.idea.hookPreview || "") !== "" || root.hasPromise
                    clip: true

                    // the clapper stripe: the slate's one ornament
                    Row {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 6
                        clip: true
                        LayoutMirroring.enabled: false
                        Repeater {
                            model: Math.max(0, Math.ceil(openCard.width / 22) + 1)
                            Rectangle {
                                width: 22; height: 6
                                color: index % 2 ? "transparent" : U.withAlpha(Theme.tertiary, 0.55)
                            }
                        }
                    }

                    ColumnLayout {
                        id: openCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            C.IconGlyph { name: "play_circle"; size: 16; glyphColor: Theme.tertiary }
                            Caption { text: I18n.tr("First 3 seconds: say this"); color: Theme.tertiary }
                            C.IconButton {
                                visible: (root.idea.hookPreview || "") !== ""
                                iconName: "content_copy"
                                tip: I18n.tr("Copy hook")
                                accent: Theme.primary
                                implicitWidth: 30; implicitHeight: 30
                                onClicked: root.copyRequested(root.idea.hookPreview || "")
                            }
                        }
                        Body {
                            visible: text !== ""
                            text: root.idea.hookPreview || ""
                            weight: Tokens.weightExtraBold
                            font.pixelSize: root.mid ? 26 : 21
                            lineHeight: 1.15
                            color: Theme.text_strong
                        }

                        // what the viewer sees / reads / is promised
                        Repeater {
                            model: {
                                var a = []
                                var vis = (root.hookData.visual || [])[0] || (root.script.length ? (root.script[0].visual || "") : "")
                                if (vis) a.push({ g: "visibility", n: I18n.tr("On screen"), v: vis })
                                var txt = (root.hookData.text || [])[0] || ""
                                if (txt) a.push({ g: "text", n: I18n.tr("Text overlay"), v: txt })
                                if (root.promise.promise) a.push({ g: "target", n: I18n.tr("The promise"), v: root.promise.promise })
                                return a
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                                    Layout.alignment: Qt.AlignTop
                                    radius: Tokens.radiusSm
                                    color: U.withAlpha(Theme.tertiary, 0.12)
                                    C.IconGlyph { anchors.centerIn: parent; name: modelData.g; size: 15; glyphColor: Theme.tertiary }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Caption { text: modelData.n }
                                    Body { text: modelData.v; font.pixelSize: Tokens.fontLabel; color: Theme.on_surface }
                                }
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space2
                            spacing: Tokens.space3
                            C.PrimaryButton {
                                iconName: "play_circle"
                                text: I18n.tr("Read on camera")
                                visible: root.hasScript
                                implicitHeight: 44
                                onClicked: root.prompterRequested(root.idea.id || 0)
                            }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "content_copy"
                                text: I18n.tr("Copy whole script")
                                visible: root.hasScript
                                implicitHeight: 44
                                onClicked: root.copyRequested(root.idea.scriptCopyText || "")
                            }
                        }
                    }
                }

                // THE SCORE — five audited parts + the blueprint check
                Rectangle {
                    id: scoreCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 2
                    Layout.minimumWidth: root.wide ? 300 : 0
                    Layout.alignment: Qt.AlignTop
                    radius: Tokens.radiusXl
                    color: Theme.surface_high
                    border.width: 1
                    border.color: Theme.border
                    implicitHeight: scoreCol.implicitHeight + Tokens.space6 * 2

                    C.GlowBlob {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -40
                        anchors.topMargin: -60
                        size: 220
                        glow: root.scoreColor
                        strength: Theme.isDark ? 0.14 : 0.08
                    }

                    ColumnLayout {
                        id: scoreCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            Row {
                                LayoutMirroring.enabled: false
                                spacing: Tokens.space2
                                C.AppText {
                                    text: String(Math.round(root.scoreShown))
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: 58
                                    color: Theme.text_strong
                                }
                                C.AppText {
                                    text: "/100"
                                    font.pixelSize: Tokens.fontLabel
                                    color: Theme.outline
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 11
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                Caption { text: I18n.tr("Blueprint score"); horizontalAlignment: Text.AlignRight }
                                C.AppText {
                                    Layout.alignment: Qt.AlignRight
                                    text: root.hasScoreParts ? I18n.tr("sum of 5 parts") : I18n.tr("model estimate")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                }
                            }
                        }

                        // five parts, each out of 20
                        Repeater {
                            model: root.hasScoreParts ? root.idea.scoreParts : []
                            ColumnLayout {
                                id: part
                                Layout.fillWidth: true
                                spacing: 4
                                HoverHandler { id: partHover }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    C.AppText {
                                        text: modelData.label
                                        font.pixelSize: Tokens.fontBody
                                        weight: Tokens.weightDemiBold
                                        color: Theme.on_surface
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    C.AppText {
                                        text: modelData.points + "/20"
                                        mono: true
                                        font.pixelSize: Tokens.fontCaption + 1
                                        color: modelData.points >= 16 ? Theme.secondary_container
                                             : modelData.points >= 11 ? Theme.on_surface_var : Theme.warn
                                        LayoutMirroring.enabled: false
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 6
                                    radius: 3
                                    color: Theme.surface_highest
                                    Rectangle {
                                        height: parent.height
                                        radius: 3
                                        width: parent.width * Math.min(1, root.scoreShown / Math.max(1, root.score)) * modelData.points / 20
                                        color: modelData.points >= 16 ? Theme.secondary_container
                                             : modelData.points >= 11 ? root.scoreColor : Theme.warn
                                    }
                                }
                                Body {
                                    visible: partHover.hovered && (modelData.why || "") !== ""
                                    text: modelData.why || ""
                                    font.pixelSize: Tokens.fontCaption + 1
                                    color: Theme.on_surface_var
                                }
                            }
                        }
                        // records before v5: the old 20-tick meter
                        Row {
                            visible: !root.hasScoreParts
                            LayoutMirroring.enabled: false
                            spacing: 3
                            Repeater {
                                model: 20
                                Rectangle {
                                    readonly property bool isOn: index < Math.round(root.scoreShown / 5)
                                    width: 8; height: 18; radius: 2
                                    color: isOn ? root.scoreColor : Theme.surface_highest
                                    opacity: isOn ? 0.45 + 0.55 * index / 19 : 1
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: Tokens.space1 }

                        // the model-free blueprint check
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            C.IconGlyph {
                                name: root.auditAllOk ? "check_circle" : "checklist"
                                fill: root.auditAllOk
                                size: 16
                                glyphColor: root.auditAllOk ? Theme.secondary_container : Theme.warn
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                text: I18n.tr("Blueprint check")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.text_strong
                                elide: Text.ElideRight
                            }
                            C.AppText {
                                text: root.num(root.audit.passed || 0) + " / " + root.num(root.audit.total || 0)
                                mono: true
                                font.pixelSize: Tokens.fontCaption + 1
                                color: root.auditAllOk ? Theme.secondary_container : Theme.warn
                            }
                        }
                        Repeater {
                            model: {
                                var c = root.audit.checks || [], bad = []
                                for (var i = 0; i < c.length; i++) if (!c[i].ok) bad.push(c[i])
                                return bad.slice(0, 4)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                Rectangle {
                                    Layout.preferredWidth: 6; Layout.preferredHeight: 6
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 7
                                    radius: 3
                                    color: Theme.warn
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: modelData.label + (modelData.note ? "  ·  " + modelData.note : "")
                                    font.pixelSize: Tokens.fontCaption + 1
                                    color: Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                        C.AppText {
                            visible: root.auditAllOk
                            Layout.fillWidth: true
                            text: I18n.tr("Timing, titles, hook length and data citations all check out.")
                            font.pixelSize: Tokens.fontCaption + 1
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                        // completeness: how many of the dossier's sections came back
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: Theme.surface_highest
                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    width: parent.width * (root.audit.completeness || 0) / 100
                                    color: root.scoreColor
                                    opacity: 0.8
                                }
                            }
                            C.AppText {
                                text: I18n.tr("{n}% complete").replace("{n}", root.num(root.audit.completeness || 0))
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                            }
                        }
                    }
                }
            }

            // ── what is inside ──
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space2
                Repeater {
                    model: {
                        var a = []
                        if (root.hasScript) a.push({ g: "schedule", v: root.idea.totalLabel || root.fmt(root.total), l: I18n.tr("read-out") })
                        if (root.hasScript) a.push({ g: "subject", v: String(root.script.length), l: I18n.tr("beats") })
                        var sh = (root.idea.shotList || []).length
                        if (sh > 0) a.push({ g: "movie", v: String(sh), l: I18n.tr("shots") })
                        var ti = (root.idea.titles || []).length
                        if (ti > 0) a.push({ g: "text", v: String(ti), l: I18n.tr("titles") })
                        var th = (root.idea.thumbnails || []).length
                        if (th > 0) a.push({ g: "image", v: String(th), l: I18n.tr("thumbnails") })
                        var pp = root.prod
                        if (pp && (pp.shoot || pp.edit)) a.push({ g: "hourglass_empty", v: [pp.prep, pp.shoot, pp.edit].filter(function (x) { return !!x }).join(" + "), l: I18n.tr("to make") })
                        return a
                    }
                    Rectangle {
                        radius: Tokens.radiusPill
                        color: Theme.surface_low
                        border.width: 1
                        border.color: Theme.border
                        implicitHeight: 38
                        implicitWidth: stRow.implicitWidth + Tokens.space5
                        Row {
                            id: stRow
                            anchors.centerIn: parent
                            spacing: 7
                            C.IconGlyph { name: modelData.g; size: 15; glyphColor: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                            C.AppText {
                                text: modelData.v
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.text_strong
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 260)
                                elide: Text.ElideRight
                            }
                            C.AppText {
                                text: modelData.l
                                font.pixelSize: Tokens.fontBody
                                color: Theme.outline
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }

        // ═════════════ pre-v3 record banner ═════════════
        C.GlassPanel {
            Layout.fillWidth: true
            visible: root.idea.isLegacy === true
            radius: Tokens.radiusXl
            implicitHeight: legacyRow.implicitHeight + Tokens.space4 * 2
            color: U.withAlpha(Theme.warn, 0.07)
            border.color: U.withAlpha(Theme.warn, 0.30)
            RowLayout {
                id: legacyRow
                anchors.fill: parent
                anchors.margins: Tokens.space4
                spacing: Tokens.space3
                C.IconGlyph { name: "history"; size: 20; glyphColor: Theme.warn; Layout.alignment: Qt.AlignTop }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.AppText { text: I18n.tr("Built with an earlier version"); weight: Tokens.weightBold; color: Theme.warn }
                    C.AppText {
                        text: I18n.tr("This blueprint has no full script, shot list or competitor breakdown — those came later. Rebuilding keeps the same idea and adds them.")
                        font.pixelSize: Tokens.fontBody
                        color: Theme.on_surface_var
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                C.PrimaryButton {
                    iconName: "auto_awesome"
                    text: root.regenerating ? I18n.tr("Rebuilding …") : I18n.tr("Rebuild in full")
                    enabled: !root.regenerating
                    implicitHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.regenerateRequested(root.idea.id || 0)
                }
            }
        }

        // ═════════════ ACT BAR (sticky) ═════════════
        Item {
            id: actWrap
            Layout.fillWidth: true
            visible: root.navModel.length > 0
            implicitHeight: actBar.height
            z: 20

            C.GlassPanel {
                id: actBar
                width: parent.width
                y: root.stickY
                height: actCol.implicitHeight + Tokens.space2 * 2
                radius: Tokens.radiusXl + 2
                elevation: root.stickY > 0 ? 1.8 : 0.2
                color: U.withAlpha(Theme.surface_low, 0.97)

                ColumnLayout {
                    id: actCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space2
                    spacing: Tokens.space2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Repeater {
                            model: root.acts.length
                            AbstractButton {
                                id: tab
                                readonly property bool isOn: root.activeAct === index
                                readonly property int count: root.actCount(index)
                                readonly property color tint: root.actColor(index)
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: root.mid ? 62 : 54
                                enabled: count > 0
                                opacity: enabled ? 1 : 0.4
                                onClicked: root.setAct(index)
                                HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    radius: Tokens.radiusLg
                                    color: tab.isOn ? Theme.surface_highest
                                         : tabHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                         : U.withAlpha(U.hoverTint(Theme.surface_low, Theme.isDark), 0)
                                    border.width: tab.isOn ? 1 : 0
                                    border.color: U.withAlpha(tab.tint, 0.28)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                }
                                contentItem: RowLayout {
                                    spacing: Tokens.space3
                                    Rectangle {
                                        Layout.leftMargin: Tokens.space3
                                        Layout.alignment: Qt.AlignVCenter
                                        width: root.mid ? 38 : 32
                                        height: width
                                        radius: Tokens.radiusMd
                                        color: tab.isOn ? tab.tint : Theme.surface_high
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        C.AppText {
                                            anchors.centerIn: parent
                                            text: root.num(index + 1)
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontSubtitle
                                            color: tab.isOn ? (Theme.isDark ? "#0F0D12" : "#FFFFFF") : Theme.on_surface_var
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 0
                                        C.AppText {
                                            text: root.acts[index].name
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontLabel + 1
                                            color: tab.isOn ? Theme.text_strong : Theme.on_surface_var
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        C.AppText {
                                            visible: root.wide
                                            text: root.acts[index].sub
                                            font.pixelSize: Tokens.fontCaption
                                            color: tab.isOn ? Theme.on_surface_var : Theme.outline
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                    C.AppText {
                                        visible: root.mid
                                        Layout.rightMargin: Tokens.space3
                                        Layout.alignment: Qt.AlignVCenter
                                        text: String(tab.count)
                                        mono: true
                                        font.pixelSize: Tokens.fontCaption
                                        color: tab.isOn ? tab.tint : Theme.outline
                                    }
                                }
                            }
                        }
                    }

                    // jump chips for the open act
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.space2
                        Layout.rightMargin: Tokens.space2
                        Layout.bottomMargin: Tokens.space1
                        visible: root.actSections(root.activeAct).length > 1
                        spacing: Tokens.space2
                        Repeater {
                            model: root.actSections(root.activeAct)
                            AbstractButton {
                                id: chip
                                implicitHeight: 30
                                implicitWidth: chipTxt.implicitWidth + Tokens.space4 + Tokens.space1
                                onClicked: root.jumpTo(modelData)
                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    radius: Tokens.radiusPill
                                    color: chipHover.hovered ? U.withAlpha(root.actColor(root.activeAct), 0.14) : U.withAlpha(root.actColor(root.activeAct), 0)
                                    border.width: 1
                                    border.color: chipHover.hovered ? U.withAlpha(root.actColor(root.activeAct), 0.45) : Theme.border
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                }
                                contentItem: Item {
                                    C.AppText {
                                        id: chipTxt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: Tokens.fontBody - 1
                                        color: chipHover.hovered ? Theme.text_strong : Theme.on_surface_var
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: Tokens.space3 }

        // ══════════════════════════ ACT 1 · STRATEGY ══════════════════════════

        // ── v5 · THE PROMISE ──
        Stage {
            id: sPromise
            host: root; act: 0; order: 0
            has: root.hasPromise
            kicker: "THE PROMISE"
            heading: I18n.tr("What it promises, and when it pays off")

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Box {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    visible: (root.promise.promise || "") !== ""
                    color: U.withAlpha(Theme.tertiary, Theme.isDark ? 0.07 : 0.05)
                    border.color: U.withAlpha(Theme.tertiary, 0.26)
                    Caption { text: I18n.tr("Title, thumbnail and hook all promise"); color: Theme.tertiary }
                    Body {
                        text: root.promise.promise || ""
                        weight: Tokens.weightBold
                        font.pixelSize: root.mid ? 22 : 19
                        color: Theme.text_strong
                    }
                }
                Box {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    visible: (root.promise.payoff || "") !== "" || (root.promise.differentiator || "") !== ""
                    RowLayout {
                        Layout.fillWidth: true
                        visible: (root.promise.payoff || "") !== ""
                        Caption { text: I18n.tr("The payoff") }
                        Pill {
                            visible: (root.promise.payoffTime || "") !== ""
                            glyph: "schedule"
                            mono: true
                            text: root.promise.payoffTime || ""
                            tint: Theme.tertiary
                        }
                    }
                    Body { visible: text !== ""; text: root.promise.payoff || ""; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong }
                    Caption { visible: (root.promise.differentiator || "") !== ""; text: I18n.tr("Only this version has"); Layout.topMargin: Tokens.space2 }
                    Body { visible: text !== ""; text: root.promise.differentiator || ""; font.pixelSize: Tokens.fontLabel }
                }
            }
        }

        // ── v6 · WHY NOW ──
        // A three-stop shelf-life gauge (Evergreen · Seasonal · Trending) with
        // the idea's stop lit, the window as a pill and the reason beside it.
        Stage {
            id: sWhyNow
            host: root; act: 0; order: 1
            has: root.hasWhyNow
            kicker: "WHY NOW"
            heading: I18n.tr("How long this idea stays worth making")
            aside: [ Pill {
                visible: (root.whyNow.window || "") !== ""
                glyph: "schedule"
                text: root.whyNow.window || ""
                tint: root.shelfColor
                strong: true
                maxTextWidth: 260
            } ]

            Box {
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    visible: (root.whyNow.shelfLife || "") !== ""
                    spacing: Tokens.space2
                    Repeater {
                        model: [
                            { key: "Evergreen", label: I18n.tr("Evergreen"), glyph: "autorenew",     tint: Theme.secondary_container, sub: I18n.tr("works any month") },
                            { key: "Seasonal",  label: I18n.tr("Seasonal"),  glyph: "schedule",       tint: Theme.warn,               sub: I18n.tr("has a season") },
                            { key: "Trending",  label: I18n.tr("Trending"),  glyph: "bolt",           tint: Theme.error,              sub: I18n.tr("make it this week") }
                        ]
                        Rectangle {
                            id: shelf
                            readonly property bool isOn: root.whyNow.shelfLife === modelData.key
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 64
                            radius: Tokens.radiusLg
                            color: isOn ? U.withAlpha(modelData.tint, Theme.isDark ? 0.16 : 0.11) : "transparent"
                            border.width: 1
                            border.color: isOn ? U.withAlpha(modelData.tint, 0.5) : Theme.border
                            opacity: isOn ? 1 : 0.55
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.space4
                                anchors.rightMargin: Tokens.space4
                                spacing: Tokens.space3
                                Rectangle {
                                    width: 32; height: 32; radius: 10
                                    color: shelf.isOn ? modelData.tint : Theme.surface_highest
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: modelData.glyph
                                        size: 17
                                        glyphColor: shelf.isOn ? (Theme.isDark ? "#0F0D12" : "#FFFFFF") : Theme.outline
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    C.AppText { text: modelData.label; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel; color: shelf.isOn ? Theme.text_strong : Theme.on_surface_var; elide: Text.ElideRight; Layout.fillWidth: true }
                                    C.AppText { visible: root.mid; text: modelData.sub; font.pixelSize: Tokens.fontCaption; color: Theme.outline; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
                Body {
                    visible: text !== ""
                    Layout.topMargin: (root.whyNow.shelfLife || "") !== "" ? Tokens.space2 : 0
                    text: root.whyNow.why || ""
                    font.pixelSize: Tokens.fontLabel + 1
                    color: Theme.text_strong
                }
            }
        }

        Stage {
            id: sAngle
            host: root; act: 0; order: 0
            has: root.hasAngle
            kicker: "VIRAL ANGLE"
            heading: I18n.tr("Viral angle")

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide && (root.angle.triggers || []).length > 0 ? 2 : 1
                columnSpacing: Tokens.space7
                rowSpacing: Tokens.space5

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.space4
                    Body {
                        text: root.angle.concept || ""
                        visible: text !== ""
                        weight: Tokens.weightBold
                        font.pixelSize: root.mid ? 26 : 21
                        color: Theme.text_strong
                    }
                    WhyNote { text_: root.angle.reasoning || ""; accent: Theme.tertiary }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    visible: (root.angle.triggers || []).length > 0
                    spacing: Tokens.space2
                    Caption { text: I18n.tr("Psychological triggers") }
                    Repeater {
                        model: root.angle.triggers || []
                        Rectangle {
                            Layout.fillWidth: true
                            radius: Tokens.radiusMd
                            color: index % 2 ? Theme.surface_low : Theme.surface_high
                            border.width: 1
                            border.color: Theme.border
                            implicitHeight: trRow.implicitHeight + Tokens.space3 * 2
                            RowLayout {
                                id: trRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.space4
                                spacing: Tokens.space3
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: Theme.tertiary
                                    opacity: 1 - index * 0.15
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Body { text: modelData; selectable: false; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sHook
            host: root; act: 0; order: 1
            has: root.hasHook
            kicker: "HOOK ANATOMY"
            heading: I18n.tr("Hook anatomy")
            aside: [
                Pill {
                    visible: (root.hookData.focusTag || "") !== ""
                    text: root.hookData.focusTag || ""
                    tint: Theme.tertiary
                    strong: true
                }
            ]

            GridLayout {
                id: hookGrid
                Layout.fillWidth: true
                readonly property var cols: {
                    var c = []
                    if ((root.hookData.visual || []).length > 0)
                        c.push({ g: "visibility", n: I18n.tr("Visual hook"), s: I18n.tr("the first frame they see"), items: root.hookData.visual, big: false, verbatim: false })
                    if ((root.hookData.text || []).length > 0)
                        c.push({ g: "text", n: I18n.tr("On-screen text"), s: I18n.tr("read with the sound off"), items: root.hookData.text, big: true, verbatim: false })
                    if (root.idea.hasAntiHook === true)
                        c.push({ g: "cancel", n: I18n.tr("Anti-hook"), s: I18n.tr("pushes the wrong viewer away"), items: root.antiHookData.options || [], big: false, verbatim: false })
                    return c
                }
                columns: root.wide ? Math.max(1, cols.length) : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                Repeater {
                    model: hookGrid.cols
                    Box {
                        id: hookCol
                        readonly property var cd: modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Tokens.space2
                            spacing: Tokens.space3
                            Rectangle {
                                width: 40; height: 40; radius: Tokens.radiusMd
                                color: U.withAlpha(Theme.tertiary, 0.14)
                                C.IconGlyph { anchors.centerIn: parent; name: modelData.g; size: 18; glyphColor: Theme.tertiary }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                C.AppText { text: modelData.n; weight: Tokens.weightBold; font.pixelSize: Tokens.fontSubtitle; color: Theme.text_strong; Layout.fillWidth: true; elide: Text.ElideRight }
                                C.AppText { text: modelData.s; font.pixelSize: Tokens.fontCaption; color: Theme.outline; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                        }
                        Repeater {
                            model: modelData.items
                            Option {
                                letter: String.fromCharCode(65 + index)
                                body: modelData
                                big: hookCol.cd.big === true
                                tint: Theme.tertiary
                                onCopyClicked: (t) => root.copyRequested(t)
                            }
                        }
                    }
                }
            }
            WhyNote { text_: root.hookData.reasoning || ""; accent: Theme.tertiary }
            WhyNote {
                text_: root.idea.hasAntiHook === true ? (root.antiHookData.reasoning || "") : ""
                accent: Theme.tertiary
            }
        }

        Stage {
            id: sThumbs
            host: root; act: 0; order: 2
            has: root.hasThumbs
            kicker: "THUMBNAIL CONCEPTS"
            heading: I18n.tr("Thumbnails to test against each other")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid ? 2 : 1
                columnSpacing: Tokens.space5
                rowSpacing: Tokens.space4

                // picker tiles — a 9:16 slot per concept
                Row {
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.space3
                    Repeater {
                        model: root.idea.thumbnails || []
                        AbstractButton {
                            id: tile
                            readonly property bool isOn: root.thumbPick === index
                            readonly property color tint: index === 0 ? Theme.tertiary : index === 1 ? Theme.warn : Theme.secondary_container
                            width: root.wide ? 128 : 104
                            height: Math.round(width * 16 / 9)
                            onClicked: root.thumbPick = index
                            HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                            transform: Translate {
                                y: tile.isOn ? -6 : 0
                                Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                            }
                            opacity: tile.isOn || tileHover.hovered ? 1 : 0.6
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                            background: Rectangle {
                                radius: Tokens.radiusLg + 2
                                antialiasing: true
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: U.mix(root.inkDeep, tile.tint, 0.55) }
                                    GradientStop { position: 0.6; color: U.mix(root.inkDeep, tile.tint, 0.16) }
                                    GradientStop { position: 1.0; color: "#0B0910" }
                                }
                                border.width: tile.isOn ? 2 : 1
                                border.color: tile.isOn ? tile.tint : Qt.rgba(1, 1, 1, 0.10)
                            }
                            contentItem: Item {
                                C.AppText {
                                    anchors.centerIn: parent
                                    text: String.fromCharCode(65 + index)
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: 54
                                    color: Qt.rgba(1, 1, 1, tile.isOn ? 0.95 : 0.7)
                                }
                                C.AppText {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Tokens.space3
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - Tokens.space3 * 2
                                    text: modelData.label || ""
                                    font.pixelSize: Tokens.fontCaption
                                    weight: Tokens.weightDemiBold
                                    color: Qt.rgba(1, 1, 1, 0.8)
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Box {
                    id: thumbBox
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    readonly property var cur: (root.idea.thumbnails || [])[root.thumbPick] || ({})
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.AppText {
                            text: (thumbBox.cur.label || "") + " · prompt"
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            color: Theme.tertiary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        C.IconButton {
                            iconName: "content_copy"
                            tip: I18n.tr("Copy")
                            accent: Theme.primary
                            onClicked: root.copyRequested(thumbBox.cur.prompt || "")
                        }
                    }
                    Body {
                        text: thumbBox.cur.prompt || ""
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.on_surface
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.space2
                        text: I18n.tr("Test these against each other rather than picking the first — thumbnail is the single biggest lever on click-through.")
                        font.pixelSize: Tokens.fontBody
                        color: Theme.outline
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        Stage {
            id: sAudience
            host: root; act: 0; order: 3
            has: root.hasAudience
            kicker: "AUDIENCE"
            heading: I18n.tr("Who this is for")
            aside: [
                Pill {
                    visible: (root.audience.watchContext || "") !== "" && root.mid
                    glyph: "smart_display"
                    text: root.audience.watchContext || ""
                    maxTextWidth: 300
                }
            ]

            Body {
                visible: text !== ""
                text: root.audience.persona || ""
                weight: Tokens.weightMedium
                font.pixelSize: Tokens.fontTitle - 1
                color: Theme.text_strong
                Layout.bottomMargin: Tokens.space2
            }
            GridLayout {
                id: audGrid
                Layout.fillWidth: true
                readonly property var cols: {
                    var c = []
                    if ((root.audience.painPoints || []).length) c.push({ n: I18n.tr("Pain points"), items: root.audience.painPoints, tint: Theme.error })
                    if ((root.audience.desires || []).length) c.push({ n: I18n.tr("Desires"), items: root.audience.desires, tint: Theme.secondary_container })
                    if ((root.audience.objections || []).length) c.push({ n: I18n.tr("Objections"), items: root.audience.objections, tint: Theme.warn })
                    return c
                }
                columns: root.mid ? Math.max(1, cols.length) : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: audGrid.cols
                    Box {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: Theme.surface_low
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 3
                            radius: 1.5
                            color: modelData.tint
                        }
                        C.AppText { text: modelData.n; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel; color: modelData.tint }
                        Repeater {
                            model: modelData.items
                            Body { text: modelData; font.pixelSize: Tokens.fontLabel }
                        }
                    }
                }
            }
            C.AppText {
                visible: !root.mid && (root.audience.watchContext || "") !== ""
                text: root.audience.watchContext || ""
                font.pixelSize: Tokens.fontBody
                color: Theme.on_surface_var
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        // ── v6 · DISCOVERY ──
        // How people find it: searches drawn as YouTube search bars you can
        // copy (or open), what it should be suggested beside, why it gets
        // clicked on Home / the feed.
        Stage {
            id: sDiscovery
            host: root; act: 0; order: 4
            has: root.hasDiscovery
            kicker: "DISCOVERY"
            heading: I18n.tr("How viewers will find it")

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide && (root.disc.searchQueries || []).length > 0
                         && ((root.disc.suggestedBeside || []).length > 0 || (root.disc.browseTrigger || "") !== "") ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                Box {
                    visible: (root.disc.searchQueries || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    Caption { text: I18n.tr("What they type into search") }
                    Repeater {
                        model: root.disc.searchQueries || []
                        AbstractButton {
                            id: sq
                            Layout.fillWidth: true
                            implicitHeight: 42
                            hoverEnabled: true
                            onClicked: Qt.openUrlExternally("https://www.youtube.com/results?search_query=" + encodeURIComponent(modelData))
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            background: Rectangle {
                                radius: Tokens.radiusPill
                                color: sq.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark) : Theme.input_bg
                                border.width: 1
                                border.color: sq.hovered ? U.withAlpha(Theme.tertiary, 0.45) : Theme.border
                                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                            contentItem: RowLayout {
                                spacing: Tokens.space3
                                C.IconGlyph { Layout.leftMargin: Tokens.space4; name: "search"; size: 16; glyphColor: sq.hovered ? Theme.tertiary : Theme.outline }
                                Body { text: modelData; selectable: false; maximumLineCount: 1; elide: Text.ElideRight; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                                C.IconButton {
                                    Layout.rightMargin: Tokens.space2
                                    iconName: "content_copy"
                                    tip: I18n.tr("Copy")
                                    accent: Theme.primary
                                    implicitWidth: 28; implicitHeight: 28
                                    opacity: sq.hovered ? 1 : 0.4
                                    onClicked: root.copyRequested(modelData)
                                }
                            }
                        }
                    }
                }
                Box {
                    visible: (root.disc.suggestedBeside || []).length > 0 || (root.disc.browseTrigger || "") !== ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 2
                    Layout.alignment: Qt.AlignTop
                    Caption { visible: (root.disc.suggestedBeside || []).length > 0; text: I18n.tr("Suggested next to") }
                    Flow {
                        Layout.fillWidth: true
                        visible: (root.disc.suggestedBeside || []).length > 0
                        spacing: Tokens.space2
                        Repeater {
                            model: root.disc.suggestedBeside || []
                            Pill { text: modelData; glyph: "smart_display"; tint: Theme.tertiary; maxTextWidth: 300 }
                        }
                    }
                    Caption {
                        visible: (root.disc.browseTrigger || "") !== ""
                        Layout.topMargin: (root.disc.suggestedBeside || []).length > 0 ? Tokens.space2 : 0
                        text: I18n.tr("Why they stop scrolling")
                    }
                    Body { visible: text !== ""; text: root.disc.browseTrigger || ""; font.pixelSize: Tokens.fontLabel }
                }
            }
        }

        Stage {
            id: sComp
            host: root; act: 0; order: 4
            has: root.hasComp
            kicker: "COMPETITION"
            heading: I18n.tr("What others made, and where you stand")

            // the conclusion first — it is the one thing here you act on
            Rectangle {
                Layout.fillWidth: true
                visible: (root.comp.gap || "") !== ""
                radius: Tokens.radiusXl
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.tertiary, Theme.isDark ? 0.20 : 0.12) }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.tertiary, 0.03) }
                }
                border.width: 1
                border.color: U.withAlpha(Theme.tertiary, 0.30)
                implicitHeight: gapCol.implicitHeight + Tokens.space6 * 2
                ColumnLayout {
                    id: gapCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space6
                    spacing: Tokens.space2
                    Caption { text: I18n.tr("Your opening"); color: Theme.tertiary }
                    Body {
                        text: root.comp.gap || ""
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontTitle - 1
                        color: Theme.text_strong
                    }
                }
            }

            // v3.15 competitor reel: a real 16:9 thumbnail on the reading-start
            // side, the title as a link, then their angle and what they miss as
            // two labelled columns. The whole card opens the video (or, for a
            // row with no known video, a YouTube search for its title). It is
            // mirrored with the UI now — the old grid pinned the thumbnail and
            // title to the top-left corner even in Persian.
            Repeater {
                model: root.comp.rows || []
                AbstractButton {
                    id: cRow
                    Layout.fillWidth: true
                    readonly property bool linked: (modelData.openUrl || "") !== ""
                    readonly property bool hasThumb: cThumb.status === Image.Ready
                    readonly property bool hot: cHover.hovered && linked
                    enabled: linked
                    hoverEnabled: true
                    implicitHeight: cLay.implicitHeight + Tokens.space4 * 2
                    onClicked: Qt.openUrlExternally(modelData.openUrl)
                    HoverHandler { id: cHover; cursorShape: cRow.linked ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    C.AppTooltip {
                        visible: cRow.hot
                        text: modelData.isSearch ? I18n.tr("Search this on YouTube") : I18n.tr("Open on YouTube")
                    }
                    background: Rectangle {
                        radius: Tokens.radiusXl
                        color: cRow.hot ? U.hoverTint(Theme.surface_high, Theme.isDark) : Theme.surface_high
                        border.width: 1
                        border.color: cRow.hot ? U.withAlpha(Theme.tertiary, 0.42) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        // a thin act-coloured edge on the reading-start side
                        Rectangle {
                            width: 3
                            radius: 2
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.topMargin: Tokens.space4; anchors.bottomMargin: Tokens.space4
                            x: I18n.rtl ? parent.width - width : 0
                            color: Theme.tertiary
                            opacity: cRow.hot ? 0.9 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        }
                    }
                    contentItem: Item {
                        implicitHeight: cLay.implicitHeight
                        RowLayout {
                            id: cLay
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: Tokens.space4
                            anchors.rightMargin: Tokens.space4
                            anchors.topMargin: Tokens.space4
                            LayoutMirroring.enabled: I18n.rtl
                            LayoutMirroring.childrenInherit: true
                            spacing: Tokens.space4

                            // ── thumbnail ──
                            Rectangle {
                                id: cThumbBox
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: root.mid ? 176 : 128
                                Layout.preferredHeight: root.mid ? 99 : 72
                                radius: Tokens.radiusMd
                                color: Theme.surface_highest
                                clip: true
                                Image {
                                    id: cThumb
                                    anchors.fill: parent
                                    visible: status === Image.Ready
                                    source: (modelData.thumbId || "") !== "" ? "image://thumbs/" + modelData.thumbId : ""
                                    sourceSize: Qt.size(352, 198)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    scale: cRow.hot ? 1.05 : 1
                                    Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                }
                                // no video id: a quiet placeholder, never an empty box
                                Column {
                                    anchors.centerIn: parent
                                    visible: !cRow.hasThumb
                                    spacing: 4
                                    C.IconGlyph {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: modelData.isSearch ? "search" : "smart_display"
                                        size: 22
                                        glyphColor: Theme.outline
                                    }
                                    C.AppText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.isSearch ? I18n.tr("Find it") : (modelData.ref || "—")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                    }
                                }
                                // dark scrim + play disc on hover
                                Rectangle {
                                    anchors.fill: parent
                                    visible: cRow.hasThumb
                                    color: "#000000"
                                    opacity: cRow.hot ? 0.28 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                }
                                Rectangle {
                                    visible: cRow.hasThumb
                                    anchors.centerIn: parent
                                    width: 36; height: 36; radius: 18
                                    color: U.withAlpha("#000000", 0.62)
                                    opacity: cRow.hot ? 1 : 0.0
                                    scale: cRow.hot ? 1 : 0.8
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                    Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack } }
                                    C.IconGlyph { anchors.centerIn: parent; name: "play_arrow"; size: 20; glyphColor: "#FFFFFF" }
                                }
                                // ref tag (V1, C2 …) top-start
                                Rectangle {
                                    visible: (modelData.ref || "") !== "" && cRow.hasThumb
                                    x: I18n.rtl ? parent.width - width - 6 : 6
                                    y: 6
                                    width: cRefTxt.implicitWidth + 10; height: 18; radius: 5
                                    color: U.withAlpha("#000000", 0.66)
                                    C.AppText { id: cRefTxt; anchors.centerIn: parent; text: modelData.ref || ""; mono: true; font.pixelSize: 11; weight: Tokens.weightBold; color: "#FFFFFF" }
                                }
                                // views, bottom-end
                                Rectangle {
                                    visible: (modelData.views || "") !== "" && cRow.hasThumb
                                    x: I18n.rtl ? 6 : parent.width - width - 6
                                    y: parent.height - height - 6
                                    width: cViewsTxt.implicitWidth + 10; height: 18; radius: 5
                                    color: U.withAlpha("#000000", 0.66)
                                    C.AppText { id: cViewsTxt; anchors.centerIn: parent; text: modelData.views || ""; mono: true; font.pixelSize: 11; weight: Tokens.weightBold; color: "#FFFFFF" }
                                }
                            }

                            // ── words ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: Tokens.space2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    Body {
                                        text: modelData.name || ""
                                        selectable: false
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontLabel + 1
                                        font.underline: cRow.hot
                                        color: cRow.hot ? Theme.tertiary : Theme.text_strong
                                        textFormat: Text.PlainText
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                    C.IconGlyph {
                                        visible: cRow.linked
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 3
                                        name: modelData.isSearch ? "search" : "open_in_new"
                                        size: 15
                                        glyphColor: cRow.hot ? Theme.tertiary : Theme.outline
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: (modelData.channel || "") !== "" || (modelData.views || "") !== "" || modelData.isSearch === true
                                    C.AppText { visible: text !== ""; text: modelData.channel || ""; weight: Tokens.weightDemiBold; font.pixelSize: Tokens.fontCaption + 1; color: Theme.on_surface_var }
                                    C.AppText { visible: (modelData.views || "") !== ""; text: ((modelData.channel || "") !== "" ? "· " : "") + (modelData.views || "") + " " + I18n.tr("views"); mono: true; font.pixelSize: Tokens.fontCaption + 1; color: Theme.outline }
                                    C.AppText { visible: modelData.isSearch === true; text: I18n.tr("no video link — opens a YouTube search"); font.pixelSize: Tokens.fontCaption + 1; color: Theme.outline }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space1
                                    visible: (modelData.angle || "") !== "" || (modelData.gap || "") !== ""
                                    columns: root.wide ? 2 : 1
                                    columnSpacing: Tokens.space4
                                    rowSpacing: Tokens.space2
                                    ColumnLayout {
                                        visible: (modelData.angle || "") !== ""
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 2
                                        Caption { text: I18n.tr("Their angle") }
                                        Body { text: modelData.angle || ""; selectable: false; font.pixelSize: Tokens.fontBody; color: Theme.on_surface }
                                    }
                                    ColumnLayout {
                                        visible: (modelData.gap || "") !== ""
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 2
                                        Caption { text: I18n.tr("What they miss"); color: Theme.tertiary }
                                        Body { text: modelData.gap || ""; selectable: false; font.pixelSize: Tokens.fontBody; color: Theme.text_strong }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sEvidence
            host: root; act: 0; order: 5
            has: root.hasEvidence
            kicker: "EVIDENCE"
            heading: I18n.tr("Why the data backs it")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.idea.evidence || []
                    Rectangle {
                        id: evCard
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        readonly property bool linked: (modelData.url || "") !== ""
                        radius: Tokens.radiusXl
                        color: Theme.surface_low
                        border.width: 1
                        border.color: Theme.border
                        implicitHeight: evRow.implicitHeight + Tokens.space5 * 2
                        HoverHandler { cursorShape: evCard.linked ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: evCard.linked; onTapped: Qt.openUrlExternally(modelData.url) }
                        RowLayout {
                            id: evRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space5
                            spacing: Tokens.space4
                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: Math.max(40, evRef.implicitWidth + Tokens.space3)
                                implicitHeight: 32
                                radius: Tokens.radiusSm
                                color: U.withAlpha(Theme.secondary_container, 0.14)
                                C.AppText { id: evRef; anchors.centerIn: parent; text: modelData.ref || "DATA"; mono: true; font.pixelSize: Tokens.fontCaption; color: Theme.secondary_container }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space1
                                Body { text: modelData.claim || ""; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                                Body {
                                    visible: text !== ""
                                    text: (modelData.title || "") + (modelData.views ? "  ·  " + modelData.views : "")
                                    selectable: false
                                    font.pixelSize: Tokens.fontBody - 1
                                    color: Theme.outline
                                }
                            }
                            C.IconGlyph { visible: evCard.linked; name: "open_in_new"; size: 16; glyphColor: Theme.outline; Layout.alignment: Qt.AlignTop }
                        }
                    }
                }
            }
        }

        Stage {
            id: sPulse
            host: root; act: 0; order: 6
            has: root.hasPulse
            kicker: "DATA PULSE"
            heading: I18n.tr("The numbers it was built from")

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space3
                Repeater {
                    model: (root.idea.pulse || {}).tiles || []
                    Rectangle {
                        radius: Tokens.radiusLg
                        color: Theme.surface_high
                        border.width: 1
                        border.color: Theme.border
                        width: Math.max(170, pCol.implicitWidth + Tokens.space5 * 2)
                        implicitHeight: pCol.implicitHeight + Tokens.space4 * 2
                        height: implicitHeight
                        ColumnLayout {
                            id: pCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            anchors.leftMargin: Tokens.space5
                            anchors.rightMargin: Tokens.space5
                            spacing: 2
                            C.AppText { text: modelData.label || ""; font.pixelSize: Tokens.fontCaption; color: Theme.outline }
                            C.AppText { text: modelData.value || ""; weight: Tokens.weightBold; font.pixelSize: 28; color: Theme.text_strong; LayoutMirroring.enabled: false }
                            C.AppText { text: modelData.sub || ""; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; elide: Text.ElideRight; Layout.maximumWidth: 240 }
                        }
                    }
                }
            }
            Repeater {
                model: (root.idea.pulse || {}).csv || []
                Box {
                    Layout.fillWidth: true
                    color: U.withAlpha(Theme.secondary_container, 0.05)
                    border.color: U.withAlpha(Theme.secondary_container, 0.22)
                    pad: Tokens.space4
                    C.AppText { text: modelData.name || ""; weight: Tokens.weightBold; color: Theme.secondary_container; Layout.fillWidth: true; elide: Text.ElideMiddle }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space5
                        Repeater {
                            model: [
                                { l: I18n.tr("Videos"), v: modelData.videos },
                                { l: I18n.tr("Median"), v: modelData.median },
                                { l: I18n.tr("Top"), v: modelData.top },
                                { l: I18n.tr("Best length"), v: modelData.bestLength },
                                { l: I18n.tr("Best day"), v: modelData.bestDay }
                            ]
                            Column {
                                spacing: 0
                                C.AppText { text: modelData.l; font.pixelSize: Tokens.fontCaption; color: Theme.outline }
                                C.AppText { text: modelData.v || "—"; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                            }
                        }
                    }
                }
            }
        }

        // ══════════════════════════ ACT 2 · PRODUCTION ══════════════════════════

        // The edit bay: script, re-hooks and pacing on one time axis, with the
        // cover preview's playhead. Time always runs left → right, like every
        // editing app, so this block is never mirrored.
        Stage {
            id: sBay
            host: root; act: 1; order: 0
            has: root.hasScript
            kicker: "EDIT BAY"
            heading: I18n.tr("The whole video on one timeline")
            aside: [
                C.AppText {
                    text: root.fmt(root.playT) + " / " + (root.idea.totalLabel || root.fmt(root.total))
                    mono: true
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface_var
                    Layout.alignment: Qt.AlignVCenter
                    LayoutMirroring.enabled: false
                },
                C.PrimaryButton {
                    variant: "ghost"
                    iconName: root.playing ? "pause" : "play_arrow"
                    text: root.playing ? I18n.tr("Pause") : I18n.tr("Play")
                    implicitHeight: 38
                    onClicked: root.playing = !root.playing
                }
            ]

            Box {
                Layout.fillWidth: true
                pad: Tokens.space5
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space4
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true

                    // lane names
                    Column {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.mid ? 104 : 72
                        spacing: 0
                        Item { width: 1; height: 30 }
                        Repeater {
                            model: [
                                { n: I18n.tr("Script"), h: 58 },
                                { n: I18n.tr("Re-hooks"), h: 40 },
                                { n: I18n.tr("Pacing"), h: 40 }
                            ]
                            Item {
                                width: parent.width
                                height: modelData.h + Tokens.space2
                                C.AppText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -Tokens.space1
                                    width: parent.width
                                    text: modelData.n
                                    font.pixelSize: Tokens.fontCaption
                                    weight: Tokens.weightDemiBold
                                    color: Theme.outline
                                    elide: Text.ElideRight
                                    horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                }
                            }
                        }
                    }

                    // the track
                    Item {
                        id: track
                        Layout.fillWidth: true
                        implicitHeight: 30 + 58 + 40 + 40 + Tokens.space2 * 3
                        function xOf(s) { return width * Math.max(0, Math.min(1, s / root.total)) }
                        readonly property real step: root.total <= 40 ? 5 : root.total <= 120 ? 15
                                                   : root.total <= 600 ? 60 : root.total <= 1800 ? 120 : 300

                        // ruler
                        Repeater {
                            model: Math.floor(root.total / track.step) + 1
                            Item {
                                x: track.xOf(index * track.step)
                                y: 0
                                C.AppText {
                                    x: index === 0 ? 0 : -implicitWidth / 2
                                    y: 0
                                    text: root.fmt(index * track.step)
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    visible: track.xOf(index * track.step) <= track.width - 18
                                }
                                Rectangle { x: 0; y: 22; width: 1; height: track.height - 22; color: U.withAlpha(Theme.outline, 0.12) }
                            }
                        }

                        // script lane
                        Repeater {
                            model: root.script
                            Rectangle {
                                readonly property bool isOn: index === root.beat
                                readonly property color tone: root.speakerColor(modelData.speaker)
                                x: track.xOf(modelData.startSec || 0) + 1
                                y: 30
                                width: Math.max(6, track.xOf(modelData.endSec || 0) - track.xOf(modelData.startSec || 0) - 2)
                                height: 58
                                radius: Tokens.radiusSm
                                clip: true
                                color: U.withAlpha(tone, isOn ? 0.24 : 0.09)
                                border.width: 1
                                border.color: U.withAlpha(tone, isOn ? 0.65 : 0.22)
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space2
                                    spacing: 2
                                    C.AppText {
                                        width: parent.width
                                        text: modelData.speaker || ""
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontMicro + 1
                                        color: parent.parent.tone
                                        elide: Text.ElideRight
                                    }
                                    C.AppText {
                                        width: parent.width
                                        text: modelData.line || modelData.visual || ""
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        elide: Text.ElideRight
                                        horizontalAlignment: /[\u0590-\u08FF]/.test(text) ? Text.AlignRight : Text.AlignLeft
                                    }
                                }
                            }
                        }

                        // re-hook lane
                        Rectangle { x: 0; y: 30 + 58 + Tokens.space2 + 20; width: track.width; height: 1; color: Theme.border }
                        Repeater {
                            model: root.idea.rehooks || []
                            Rectangle {
                                visible: modelData.atSec !== undefined && modelData.atSec >= 0
                                x: track.xOf(modelData.atSec || 0) - width / 2
                                y: 30 + 58 + Tokens.space2 + 6
                                width: 28; height: 28; radius: 14
                                color: Theme.warn
                                C.IconGlyph { anchors.centerIn: parent; name: "bolt"; fill: true; size: 15; glyphColor: "#1D1305" }
                                HoverHandler { id: rhHover }
                                C.AppTooltip {
                                    visible: rhHover.hovered
                                    text: (modelData.device || "") + (modelData.line ? " · " + modelData.line : "")
                                }
                            }
                        }

                        // pacing lane
                        Repeater {
                            model: root.ret.phases || []
                            Rectangle {
                                readonly property real p0: (index > 0 ? (root.ret.phases[index - 1].endPct || 0) : 0) / 100
                                readonly property real p1: (modelData.endPct || 0) / 100
                                x: track.width * p0 + (index > 0 ? 1 : 0)
                                y: 30 + 58 + 40 + Tokens.space2 * 2
                                width: Math.max(0, track.width * (p1 - p0) - (index > 0 ? 1 : 0))
                                height: 40
                                radius: Tokens.radiusSm
                                color: U.withAlpha(Theme.warn, [0.34, 0.12, 0.26, 0.18, 0.09, 0.22, 0.14, 0.3][index % 8])
                                C.AppText {
                                    anchors.centerIn: parent
                                    width: parent.width - Tokens.space2
                                    text: modelData.label || ""
                                    font.pixelSize: Tokens.fontCaption
                                    weight: Tokens.weightDemiBold
                                    color: Theme.text_strong
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // playhead
                        Item {
                            x: track.xOf(root.playT)
                            y: 18
                            height: track.height - 18
                            Rectangle { x: -5; y: 0; width: 10; height: 10; radius: 3; color: Theme.warn }
                            Rectangle { x: -1; y: 0; width: 2; height: parent.height; color: Theme.warn }
                        }

                        // scrub
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            onPressed: (m) => root.seek(m.x / track.width * root.total)
                            onPositionChanged: (m) => { if (pressed) root.seek(m.x / track.width * root.total) }
                        }
                    }
                }
            }

            // now playing
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space2
                spacing: Tokens.space4
                C.AppText {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    text: root.beatRow.time || ""
                    mono: true
                    font.pixelSize: Tokens.fontBody
                    color: Theme.warn
                    LayoutMirroring.enabled: false
                }
                Body {
                    text: root.beatRow.line || ""
                    selectable: false
                    weight: root.isScene(root.beatRow.speaker) ? Tokens.weightRegular : Tokens.weightBold
                    font.pixelSize: Tokens.fontTitle - 2
                    color: root.isScene(root.beatRow.speaker) ? Theme.on_surface_var : Theme.text_strong
                }
            }
            C.AppText {
                visible: root.idea.timelineExact === false
                text: I18n.tr("Timing estimated from line length")
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
            }
        }

        Stage {
            id: sScript
            host: root; act: 1; order: 1
            has: root.hasScript
            kicker: "FULL SCRIPT"
            heading: I18n.tr("Word for word, second by second")
            aside: [
                C.PrimaryButton {
                    variant: "ghost"
                    iconName: "content_copy"
                    text: root.mid ? I18n.tr("Copy whole script") : ""
                    implicitHeight: 40
                    onClicked: root.copyRequested(root.idea.scriptCopyText || "")
                },
                C.PrimaryButton {
                    iconName: "play_circle"
                    text: I18n.tr("Read on camera")
                    implicitHeight: 40
                    onClicked: root.prompterRequested(root.idea.id || 0)
                }
            ]

            Repeater {
                model: root.script
                Rectangle {
                    id: sRow
                    Layout.fillWidth: true
                    readonly property bool isOn: index === root.beat
                    readonly property bool scene: root.isScene(modelData.speaker)
                    radius: Tokens.radiusLg
                    color: isOn ? U.withAlpha(Theme.warn, Theme.isDark ? 0.08 : 0.10)
                         : srHover.hovered ? U.withAlpha(Theme.on_surface, 0.03) : U.withAlpha(Theme.on_surface, 0)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                    implicitHeight: srRow.implicitHeight + Tokens.space4 * 2
                    HoverHandler { id: srHover }
                    RowLayout {
                        id: srRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space4
                        spacing: Tokens.space5
                        // the timecode doubles as a seek button
                        AbstractButton {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 100
                            implicitHeight: tcCol.implicitHeight
                            onClicked: root.seek(modelData.startSec || 0)
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            background: Item {}
                            contentItem: Column {
                                id: tcCol
                                spacing: 2
                                C.AppText {
                                    text: modelData.time || ""
                                    mono: true
                                    font.pixelSize: Tokens.fontBody - 1
                                    color: sRow.isOn ? Theme.warn : Theme.outline
                                    LayoutMirroring.enabled: false
                                }
                                C.AppText {
                                    text: root.speakerLabel(modelData.speaker)
                                    font.pixelSize: Tokens.fontCaption
                                    color: sRow.scene ? Theme.tertiary : modelData.speaker === "On-screen" ? Theme.warn : Theme.on_surface_var
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            Body {
                                visible: text !== ""
                                text: modelData.line || ""
                                weight: sRow.scene ? Tokens.weightRegular : Tokens.weightBold
                                font.pixelSize: sRow.scene ? Tokens.fontLabel + 1 : Tokens.fontTitle - 2
                                color: sRow.scene ? Theme.on_surface_var
                                     : modelData.speaker === "On-screen" ? Theme.warn : Theme.text_strong
                            }
                            // v5: what is on screen while it is said
                            RowLayout {
                                Layout.fillWidth: true
                                visible: (modelData.visual || "") !== ""
                                spacing: Tokens.space2
                                C.IconGlyph { name: "visibility"; size: 14; glyphColor: Theme.outline; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                                Body {
                                    text: modelData.visual || ""
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.on_surface_var
                                }
                            }
                        }
                        C.IconButton {
                            Layout.alignment: Qt.AlignTop
                            iconName: "content_copy"
                            tip: I18n.tr("Copy")
                            accent: Theme.primary
                            implicitWidth: 30
                            implicitHeight: 30
                            opacity: srHover.hovered ? 1 : 0.35
                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                            onClicked: root.copyRequested(modelData.line || "")
                        }
                    }
                }
            }
        }

        // ── v6 · DELIVERY ──
        // How to SAY the script: three dials (tone · pace · energy), the
        // words to punch as bold chips, and the delivery mistakes to avoid.
        Stage {
            id: sDelivery
            host: root; act: 1; order: 2
            has: root.hasDelivery
            kicker: "DELIVERY"
            heading: I18n.tr("How to say it on camera")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid ? 3 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: [
                        { label: I18n.tr("Tone"),   glyph: "user",       value: root.deliv.tone || "" },
                        { label: I18n.tr("Pace"),   glyph: "speed",      value: root.deliv.pace || "" },
                        { label: I18n.tr("Energy"), glyph: "trending_up", value: root.deliv.energy || "" }
                    ]
                    Box {
                        visible: modelData.value !== ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        pad: Tokens.space4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            C.IconGlyph { name: modelData.glyph; size: 15; glyphColor: Theme.warn }
                            Caption { text: modelData.label; color: Theme.warn }
                        }
                        Body { text: modelData.value; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible: (root.deliv.emphasis || []).length > 0 || (root.deliv.avoid || []).length > 0
                columns: root.mid && (root.deliv.emphasis || []).length > 0 && (root.deliv.avoid || []).length > 0 ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Box {
                    visible: (root.deliv.emphasis || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Caption { text: I18n.tr("Punch these words") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Repeater {
                            model: root.deliv.emphasis || []
                            Pill { text: modelData; glyph: "bolt"; tint: Theme.warn; strong: true; maxTextWidth: 320 }
                        }
                    }
                }
                Box {
                    visible: (root.deliv.avoid || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Caption { text: I18n.tr("Don't") }
                    Repeater {
                        model: root.deliv.avoid || []
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            C.IconGlyph { name: "close"; size: 15; glyphColor: Theme.error; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                            Body { text: modelData; font.pixelSize: Tokens.fontLabel }
                        }
                    }
                }
            }
        }

        Stage {
            id: sShots
            host: root; act: 1; order: 2
            has: root.hasShots
            kicker: "SHOT LIST"
            heading: I18n.tr("What goes in front of the camera")
            aside: [ Pill { visible: root.mid; glyph: "movie"; text: I18n.tr("Shoot the essentials first, B-roll last") } ]

            GridLayout {
                id: shotGrid
                Layout.fillWidth: true
                readonly property int n: (root.idea.shotList || []).length
                columns: Math.max(1, Math.min(n, Math.floor(width / 190)))
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.idea.shotList || []
                    Rectangle {
                        id: shot
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        readonly property bool isB: modelData.broll === true
                        radius: Tokens.radiusXl
                        color: isB ? "transparent" : Theme.surface_high
                        border.width: 1
                        border.color: isB ? U.withAlpha(Theme.outline, 0.45) : Theme.border
                        implicitHeight: shotCol.implicitHeight + Tokens.space5 * 2
                        ColumnLayout {
                            id: shotCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space5
                            spacing: Tokens.space2
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.bottomMargin: Tokens.space3
                                C.AppText {
                                    text: String(modelData.shot || (index + 1))
                                    weight: Tokens.weightRegular
                                    font.pixelSize: 36
                                    color: shot.isB ? Theme.outline : Theme.warn
                                    LayoutMirroring.enabled: false
                                    Layout.fillWidth: true
                                }
                                Pill { visible: shot.isB; text: "B-roll"; mono: true }
                            }
                            C.AppText {
                                text: modelData.type || ""
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.on_surface_var
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                            Body { text: modelData.desc || ""; font.pixelSize: Tokens.fontLabel }
                            C.AppText {
                                visible: (modelData.beat || "") !== ""
                                text: I18n.tr("Covers {t}").replace("{t}", modelData.beat || "")
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sRehooks
            host: root; act: 1; order: 3
            has: root.hasRehooks
            kicker: "RE-HOOKS"
            heading: I18n.tr("Where viewers want to leave")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.idea.rehooks || []
                    Rectangle {
                        id: rh
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: Tokens.radiusXl
                        color: Theme.surface_low
                        border.width: 1
                        border.color: Theme.border
                        implicitHeight: rhRow.implicitHeight + Tokens.space5 * 2
                        HoverHandler { id: rhCardHover }
                        RowLayout {
                            id: rhRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space5
                            spacing: Tokens.space5
                            AbstractButton {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: rhTime.implicitWidth
                                implicitHeight: rhTime.implicitHeight
                                enabled: modelData.atSec !== undefined && modelData.atSec >= 0
                                onClicked: { root.seek(modelData.atSec); }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Item {}
                                contentItem: Column {
                                    id: rhTime
                                    spacing: 2
                                    C.AppText { text: modelData.time || ""; mono: true; font.pixelSize: Tokens.fontTitle; color: Theme.warn; LayoutMirroring.enabled: false }
                                    C.AppText { text: modelData.device || ""; font.pixelSize: Tokens.fontCaption; color: Theme.outline; width: Math.min(implicitWidth, 120); elide: Text.ElideRight }
                                }
                            }
                            Body { text: modelData.line || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontSubtitle + 1; color: Theme.text_strong }
                            C.IconButton {
                                Layout.alignment: Qt.AlignTop
                                iconName: "content_copy"
                                tip: I18n.tr("Copy")
                                accent: Theme.primary
                                implicitWidth: 30
                                implicitHeight: 30
                                opacity: rhCardHover.hovered ? 1 : 0.35
                                onClicked: root.copyRequested(modelData.line || "")
                            }
                        }
                    }
                }
            }
        }

        // ── v5 · ON-SCREEN TEXT ──
        Stage {
            id: sOverlay
            host: root; act: 1; order: 4
            has: root.hasOnScreen
            kicker: "ON-SCREEN TEXT"
            heading: I18n.tr("Every overlay, timed")
            aside: [
                C.PrimaryButton {
                    visible: root.mid
                    variant: "ghost"
                    iconName: "content_copy"
                    text: I18n.tr("Copy all")
                    implicitHeight: 38
                    onClicked: {
                        var a = root.idea.onScreenText || [], out = []
                        for (var i = 0; i < a.length; i++) out.push("[" + (a[i].time || "") + "] " + (a[i].text || "") + (a[i].style ? "  (" + a[i].style + ")" : ""))
                        root.copyRequested(out.join("\n"))
                    }
                }
            ]
            Repeater {
                model: root.idea.onScreenText || []
                Rectangle {
                    id: ov
                    Layout.fillWidth: true
                    radius: Tokens.radiusLg
                    color: index % 2 ? Theme.surface_low : Theme.surface_high
                    border.width: 1
                    border.color: ovHover.hovered ? U.withAlpha(Theme.warn, 0.35) : Theme.border
                    implicitHeight: ovRow.implicitHeight + Tokens.space4 * 2
                    HoverHandler { id: ovHover }
                    RowLayout {
                        id: ovRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.space4
                        spacing: Tokens.space4
                        Rectangle {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 28
                            radius: Tokens.radiusXs + 2
                            color: U.withAlpha(Theme.warn, 0.12)
                            C.AppText {
                                anchors.centerIn: parent
                                text: modelData.time || "—"
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.warn
                                LayoutMirroring.enabled: false
                            }
                        }
                        Body {
                            text: modelData.text || ""
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontSubtitle + 1
                            color: Theme.text_strong
                        }
                        Pill {
                            visible: root.mid && (modelData.style || "") !== ""
                            text: modelData.style || ""
                            maxTextWidth: 180
                            Layout.alignment: Qt.AlignVCenter
                        }
                        C.IconButton {
                            iconName: "content_copy"
                            tip: I18n.tr("Copy")
                            accent: Theme.primary
                            implicitWidth: 30; implicitHeight: 30
                            opacity: ovHover.hovered ? 1 : 0.4
                            onClicked: root.copyRequested(modelData.text || "")
                        }
                    }
                }
            }
        }

        Stage {
            id: sExec
            host: root; act: 1; order: 4
            has: root.hasExec
            kicker: "EDIT NOTES"
            heading: I18n.tr("The editor's brief")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: [
                        { g: "scissors",      n: I18n.tr("Editing & pace"),  v: root.exec.editing || "" },
                        { g: "music_note",    n: I18n.tr("Audio & music"),   v: root.exec.audio || "" },
                        { g: "inventory_2",   n: I18n.tr("Assets needed"),   v: root.exec.assets || "" },
                        { g: "smart_display", n: I18n.tr("Render & export"), v: root.exec.render || "" }
                    ]
                    Box {
                        visible: modelData.v !== ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Row {
                            spacing: Tokens.space2
                            C.IconGlyph { name: modelData.g; size: 16; glyphColor: Theme.warn; anchors.verticalCenter: parent.verticalCenter }
                            C.AppText { text: modelData.n; weight: Tokens.weightBold; font.pixelSize: Tokens.fontBody; color: Theme.warn; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Body { text: modelData.v; font.pixelSize: Tokens.fontLabel + 1 }
                    }
                }
            }
            WhyNote { text_: root.exec.reasoning || ""; accent: Theme.warn }
        }

        // ── v5 · LOOK & SOUND ──
        Stage {
            id: sStyle
            host: root; act: 1; order: 6
            has: root.hasStyle
            kicker: "LOOK & SOUND"
            heading: I18n.tr("How it looks, reads and sounds")

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                Box {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    visible: (root.styleG.look || "") !== "" || (root.styleG.palette || []).length > 0
                             || (root.styleG.typography || "") !== "" || (root.styleG.captions || "") !== ""
                    // palette: real swatches, click to copy the hex
                    Flow {
                        Layout.fillWidth: true
                        visible: (root.styleG.palette || []).length > 0
                        spacing: Tokens.space2
                        Repeater {
                            model: root.styleG.palette || []
                            AbstractButton {
                                id: sw
                                implicitWidth: swRow.implicitWidth + Tokens.space4
                                implicitHeight: 36
                                onClicked: root.copyRequested(modelData)
                                HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    radius: Tokens.radiusPill
                                    color: swHover.hovered ? Theme.surface_highest : Theme.surface_low
                                    border.width: 1
                                    border.color: Theme.border
                                }
                                contentItem: Item {
                                    implicitWidth: swRow.implicitWidth
                                    Row {
                                        id: swRow
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Rectangle {
                                            width: 20; height: 20; radius: 10
                                            color: modelData
                                            border.width: 1
                                            border.color: U.withAlpha(Theme.on_surface, 0.2)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        C.AppText {
                                            text: String(modelData).toUpperCase()
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption + 1
                                            color: Theme.on_surface
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Repeater {
                        model: {
                            var a = []
                            if (root.styleG.look) a.push({ g: "visibility", n: I18n.tr("Look"), v: root.styleG.look })
                            if (root.styleG.typography) a.push({ g: "text", n: I18n.tr("Type"), v: root.styleG.typography })
                            if (root.styleG.captions) a.push({ g: "subject", n: I18n.tr("Captions"), v: root.styleG.captions })
                            return a
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            C.IconGlyph { name: modelData.g; size: 16; glyphColor: Theme.warn; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Caption { text: modelData.n }
                                Body { text: modelData.v }
                            }
                        }
                    }
                }

                Box {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    visible: (root.styleG.music || "") !== "" || (root.styleG.sfx || []).length > 0
                    RowLayout {
                        Layout.fillWidth: true
                        visible: (root.styleG.music || "") !== ""
                        spacing: Tokens.space3
                        C.IconGlyph { name: "music_note"; size: 16; glyphColor: Theme.tertiary; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Caption { text: I18n.tr("Music") }
                            Body { text: root.styleG.music || "" }
                        }
                    }
                    Caption {
                        visible: (root.styleG.sfx || []).length > 0
                        text: I18n.tr("Sound effects, where they hit")
                        Layout.topMargin: Tokens.space2
                    }
                    Repeater {
                        model: root.styleG.sfx || []
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            C.AppText {
                                text: modelData.time || ""
                                mono: true
                                font.pixelSize: Tokens.fontCaption + 1
                                color: Theme.tertiary
                                Layout.preferredWidth: 56
                                Layout.alignment: Qt.AlignTop
                                LayoutMirroring.enabled: false
                            }
                            Body { text: modelData.cue || ""; font.pixelSize: Tokens.fontBody + 1 }
                        }
                    }
                }
            }
        }

        Stage {
            id: sRet
            host: root; act: 1; order: 5
            has: root.hasRet
            kicker: "RETENTION PACING"
            heading: I18n.tr("The rhythm that keeps them watching")
            aside: [ Pill { text: root.ret.totalLabel || ""; mono: true; visible: (root.ret.totalLabel || "") !== "" } ]

            Item {
                Layout.fillWidth: true
                implicitHeight: 12
                Row {
                    id: paceBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 12
                    spacing: 3
                    LayoutMirroring.enabled: false
                    readonly property int phaseCount: (root.ret.phases || []).length
                    Repeater {
                        model: root.ret.phases || []
                        Rectangle {
                            width: (paceBar.width - (paceBar.phaseCount - 1) * 3) * Math.max(0, modelData.spanPct || 0) / 100
                            height: paceBar.height
                            radius: 6
                            color: U.withAlpha(Theme.warn, 1.0 - index * (0.6 / Math.max(1, paceBar.phaseCount)))
                        }
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space2
                columns: root.wide ? Math.max(1, Math.min(5, (root.ret.phases || []).length)) : 1
                columnSpacing: Tokens.space4
                rowSpacing: Tokens.space4
                Repeater {
                    model: root.ret.phases || []
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 2
                        C.AppText { text: modelData.endTime || ""; mono: true; font.pixelSize: Tokens.fontBody; color: Theme.warn; LayoutMirroring.enabled: false }
                        C.AppText { text: modelData.label || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Body { visible: text !== ""; text: modelData.desc || ""; font.pixelSize: Tokens.fontBody; color: Theme.on_surface_var }
                    }
                }
            }
        }

        // ══════════════════════════ ACT 3 · LAUNCH ══════════════════════════

        // ── v5 · PREP & GEAR ──
        Stage {
            id: sPrep
            host: root; act: 1; order: 7
            has: root.hasProduction
            kicker: "PREP & GEAR"
            heading: I18n.tr("What you need before you hit record")

            // time estimates: prep → shoot → edit
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space3
                Repeater {
                    model: {
                        var a = []
                        if (root.prod.prep) a.push({ g: "checklist", n: I18n.tr("Prep"), v: root.prod.prep })
                        if (root.prod.shoot) a.push({ g: "movie", n: I18n.tr("Shoot"), v: root.prod.shoot })
                        if (root.prod.edit) a.push({ g: "scissors", n: I18n.tr("Edit"), v: root.prod.edit })
                        if (root.prod.location) a.push({ g: "compass", n: I18n.tr("Location"), v: root.prod.location })
                        return a
                    }
                    Rectangle {
                        radius: Tokens.radiusLg
                        color: Theme.surface_high
                        border.width: 1
                        border.color: Theme.border
                        implicitWidth: Math.min(360, tCol.implicitWidth + Tokens.space5 * 2)
                        implicitHeight: tCol.implicitHeight + Tokens.space4 * 2
                        Column {
                            id: tCol
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.space5
                            width: Math.min(implicitWidth, 360 - Tokens.space5 * 2)
                            spacing: 2
                            Row {
                                spacing: 6
                                C.IconGlyph { name: modelData.g; size: 14; glyphColor: Theme.warn; anchors.verticalCenter: parent.verticalCenter }
                                C.AppText { text: modelData.n; font.pixelSize: Tokens.fontCaption; weight: Tokens.weightDemiBold; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                            }
                            C.AppText {
                                width: Math.min(implicitWidth, 320)
                                text: modelData.v
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontSubtitle
                                color: Theme.text_strong
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                Box {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    visible: (root.prod.gear || []).length > 0 || (root.prod.props || []).length > 0
                    Caption { visible: (root.prod.gear || []).length > 0; text: I18n.tr("Gear") }
                    Flow {
                        Layout.fillWidth: true
                        visible: (root.prod.gear || []).length > 0
                        spacing: Tokens.space2
                        Repeater { model: root.prod.gear || []; Pill { text: modelData; glyph: "inventory_2"; tint: Theme.warn } }
                    }
                    Caption { visible: (root.prod.props || []).length > 0; text: I18n.tr("Props"); Layout.topMargin: Tokens.space2 }
                    Flow {
                        Layout.fillWidth: true
                        visible: (root.prod.props || []).length > 0
                        spacing: Tokens.space2
                        Repeater { model: root.prod.props || []; Pill { text: modelData } }
                    }
                }

                Box {
                    id: prepBox
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    visible: (root.prod.checklist || []).length > 0
                    readonly property int doneCount: {
                        var n = 0, d = root.prepDone
                        for (var k in d) if (d[k]) n++
                        return n
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        C.AppText { text: I18n.tr("Before you record"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontSubtitle; color: Theme.text_strong; Layout.fillWidth: true; elide: Text.ElideRight }
                        C.AppText {
                            text: prepBox.doneCount + "/" + (root.prod.checklist || []).length
                            mono: true
                            font.pixelSize: Tokens.fontBody
                            color: Theme.warn
                            LayoutMirroring.enabled: false
                        }
                    }
                    Repeater {
                        model: root.prod.checklist || []
                        AbstractButton {
                            id: pchk
                            readonly property bool done: root.prepDone[index] === true
                            Layout.fillWidth: true
                            implicitHeight: pchkRow.implicitHeight + Tokens.space3 * 2
                            onClicked: {
                                var d = Object.assign({}, root.prepDone)
                                d[index] = !pchk.done
                                root.prepDone = d
                            }
                            HoverHandler { id: pchkHover; cursorShape: Qt.PointingHandCursor }
                            background: Rectangle {
                                radius: Tokens.radiusLg
                                color: pchk.done ? U.withAlpha(Theme.warn, 0.07)
                                     : pchkHover.hovered ? U.withAlpha(Theme.on_surface, 0.04) : "transparent"
                            }
                            contentItem: RowLayout {
                                id: pchkRow
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.leftMargin: Tokens.space3
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 22; height: 22; radius: Tokens.radiusXs + 1
                                    color: pchk.done ? Theme.warn : "transparent"
                                    border.width: pchk.done ? 0 : 1.5
                                    border.color: Theme.outline
                                    C.IconGlyph { anchors.centerIn: parent; visible: pchk.done; name: "check"; size: 15; glyphColor: Theme.isDark ? "#0F0D12" : "#FFFFFF" }
                                }
                                Body {
                                    Layout.rightMargin: Tokens.space3
                                    text: modelData
                                    selectable: false
                                    font.pixelSize: Tokens.fontLabel
                                    font.strikeout: pchk.done
                                    color: pchk.done ? Theme.outline : Theme.on_surface
                                }
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sTitles
            host: root; act: 2; order: 0
            has: root.hasTitles
            kicker: "PACKAGING"
            heading: I18n.tr("Titles")

            Rectangle {
                Layout.fillWidth: true
                visible: (root.pack.framework || "") !== ""
                radius: Tokens.radiusLg
                color: U.withAlpha(Theme.secondary_container, 0.06)
                border.width: 1
                border.color: U.withAlpha(Theme.secondary_container, 0.24)
                implicitHeight: fwRow.implicitHeight + Tokens.space4 * 2
                RowLayout {
                    id: fwRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space4
                    spacing: Tokens.space3
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Caption { text: I18n.tr("Title formula"); color: Theme.secondary_container }
                        Body { text: root.pack.framework || ""; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                    }
                    C.IconButton {
                        iconName: "content_copy"
                        tip: I18n.tr("Copy")
                        accent: Theme.primary
                        onClicked: root.copyRequested(root.pack.framework || "")
                    }
                }
            }

            Repeater {
                model: root.idea.titles || []
                Rectangle {
                    id: tRow
                    Layout.fillWidth: true
                    readonly property bool isTop: index === 0
                    radius: Tokens.radiusLg
                    color: isTop ? U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.10 : 0.08)
                               : (index % 2 ? Theme.surface_low : Theme.surface_high)
                    border.width: 1
                    border.color: isTop ? U.withAlpha(Theme.secondary_container, 0.32) : Theme.border
                    implicitHeight: tLay.implicitHeight + Tokens.space5 * 2
                    HoverHandler { id: tHover }
                    RowLayout {
                        id: tLay
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space4
                        C.AppText {
                            text: root.num(index + 1)
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontLabel
                            color: tRow.isTop ? Theme.secondary_container : Theme.outline
                            Layout.preferredWidth: 20
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 3
                        }
                        Body {
                            text: modelData
                            weight: tRow.isTop ? Tokens.weightExtraBold : Tokens.weightMedium
                            font.pixelSize: tRow.isTop ? Tokens.fontTitle : Tokens.fontSubtitle + 1
                            color: Theme.text_strong
                        }
                        Pill {
                            visible: tRow.isTop && root.mid
                            text: I18n.tr("Top pick")
                            tint: Theme.secondary_container
                            Layout.alignment: Qt.AlignVCenter
                        }
                        C.AppText {
                            visible: root.mid
                            text: String(String(modelData).length)
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: String(modelData).length > 70 ? Theme.error : Theme.outline
                            Layout.alignment: Qt.AlignVCenter
                        }
                        C.IconButton {
                            iconName: "content_copy"
                            tip: I18n.tr("Copy")
                            accent: Theme.primary
                            implicitWidth: 30
                            implicitHeight: 30
                            opacity: tHover.hovered ? 1 : 0.35
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: root.copyRequested(modelData)
                        }
                    }
                }
            }
        }

        // ── v5 · TEST PLAN ──
        Stage {
            id: sAb
            host: root; act: 2; order: 1
            has: root.hasAbPlan
            kicker: "TEST PLAN"
            heading: I18n.tr("Launch with this, swap when it stalls")

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: {
                        var a = []
                        if (root.ab.thumbnailFirst) a.push({ g: "image", n: I18n.tr("Thumbnail to launch with"), v: root.ab.thumbnailFirst, t: Theme.secondary_container })
                        if (root.ab.titleFirst) a.push({ g: "text", n: I18n.tr("Title to launch with"), v: root.ab.titleFirst, t: Theme.secondary_container })
                        if (root.ab.swapRule) a.push({ g: "sync", n: I18n.tr("When to swap"), v: root.ab.swapRule, t: Theme.warn })
                        if (root.ab.watch) a.push({ g: "query_stats", n: I18n.tr("Watch first in Studio"), v: root.ab.watch, t: Theme.tertiary })
                        return a
                    }
                    Box {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            Rectangle {
                                Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                Layout.alignment: Qt.AlignTop
                                radius: Tokens.radiusSm
                                color: U.withAlpha(modelData.t, 0.13)
                                C.IconGlyph { anchors.centerIn: parent; name: modelData.g; size: 16; glyphColor: modelData.t }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Caption { text: modelData.n }
                                Body { text: modelData.v; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong }
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sPlan
            host: root; act: 2; order: 1
            has: root.hasPlan
            kicker: "PUBLISH PLAN"
            heading: I18n.tr("When it goes out, and the hour after")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid && (root.plan.first_hour || []).length > 0 ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                // the slot, set like a departure board
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 4
                    radius: Tokens.radiusXl + 4
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.24 : 0.14) }
                        GradientStop { position: 0.75; color: U.withAlpha(Theme.secondary_container, 0.03) }
                    }
                    border.width: 1
                    border.color: U.withAlpha(Theme.secondary_container, 0.30)
                    implicitHeight: slotCol.implicitHeight + Tokens.space6 * 2
                    ColumnLayout {
                        id: slotCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space2
                        Caption { text: I18n.tr("Upload slot"); color: Theme.secondary_container }
                        C.AppText {
                            visible: text !== ""
                            text: root.plan.day || ""
                            weight: Tokens.weightExtraBold
                            font.pixelSize: 40
                            color: Theme.text_strong
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        C.AppText {
                            visible: text !== ""
                            text: root.plan.time || ""
                            weight: Tokens.weightExtraBold
                            font.pixelSize: 52
                            color: Theme.secondary_container
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space3
                            visible: (root.plan.why || "") !== ""
                            spacing: Tokens.space2
                            C.IconGlyph { name: "schedule"; size: 16; glyphColor: Theme.on_surface_var; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                            Body { text: root.plan.why || ""; font.pixelSize: Tokens.fontLabel; color: Theme.on_surface_var }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: (root.pack.timing || "") !== ""
                            spacing: Tokens.space2
                            C.IconGlyph { name: "lightbulb"; size: 16; glyphColor: Theme.on_surface_var; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                            Body { text: root.pack.timing || ""; font.pixelSize: Tokens.fontLabel; color: Theme.on_surface_var }
                        }
                    }
                }

                // the first hour, as a checklist you can actually tick
                Box {
                    id: planBox
                    visible: (root.plan.first_hour || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 5
                    readonly property int doneCount: {
                        var n = 0, d = root.planDone
                        for (var k in d) if (d[k]) n++
                        return n
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Tokens.space2
                        C.AppText { text: I18n.tr("The first hour after publishing"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontSubtitle; color: Theme.text_strong; Layout.fillWidth: true; elide: Text.ElideRight }
                        C.AppText {
                            text: planBox.doneCount + "/" + (root.plan.first_hour || []).length
                            mono: true
                            font.pixelSize: Tokens.fontBody
                            color: Theme.secondary_container
                            LayoutMirroring.enabled: false
                        }
                    }
                    Repeater {
                        model: root.plan.first_hour || []
                        AbstractButton {
                            id: chk
                            readonly property bool done: root.planDone[index] === true
                            Layout.fillWidth: true
                            implicitHeight: chkRow.implicitHeight + Tokens.space3 * 2
                            onClicked: {
                                var d = Object.assign({}, root.planDone)
                                d[index] = !chk.done
                                root.planDone = d
                            }
                            HoverHandler { id: chkHover; cursorShape: Qt.PointingHandCursor }
                            background: Rectangle {
                                radius: Tokens.radiusLg
                                color: chk.done ? U.withAlpha(Theme.secondary_container, 0.07)
                                     : chkHover.hovered ? U.withAlpha(Theme.on_surface, 0.04) : U.withAlpha(Theme.on_surface, 0)
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                            contentItem: RowLayout {
                                id: chkRow
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.leftMargin: Tokens.space3
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 24; height: 24; radius: Tokens.radiusXs + 1
                                    color: chk.done ? Theme.secondary_container : U.withAlpha(Theme.secondary_container, 0)
                                    border.width: chk.done ? 0 : 1.5
                                    border.color: Theme.border_strong !== undefined ? Theme.border_strong : Theme.outline
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    C.IconGlyph { anchors.centerIn: parent; visible: chk.done; name: "check"; size: 16; glyphColor: Theme.isDark ? "#0F0D12" : "#FFFFFF" }
                                }
                                Body {
                                    Layout.rightMargin: Tokens.space3
                                    text: modelData
                                    selectable: false
                                    font.pixelSize: Tokens.fontLabel
                                    font.strikeout: chk.done
                                    color: chk.done ? Theme.outline : Theme.on_surface
                                }
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sCaption
            host: root; act: 2; order: 2
            has: root.hasCaption
            kicker: "CAPTION & CTA"
            heading: I18n.tr("Caption, hashtags and the ask")

            GridLayout {
                Layout.fillWidth: true
                id: capGrid
                readonly property bool hasCap: root.idea.hasCaptionPack === true || (root.idea.pinnedComment || "") !== ""
                columns: root.mid && hasCap && root.idea.hasCta === true ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                Box {
                    visible: capGrid.hasCap
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    RowLayout {
                        Layout.fillWidth: true
                        visible: (root.caption.description || "") !== ""
                        Caption { text: I18n.tr("Shorts caption") }
                        C.IconButton {
                            iconName: "content_copy"
                            tip: I18n.tr("Copy")
                            accent: Theme.primary
                            onClicked: root.copyRequested((root.caption.description || "") + "\n" + (root.caption.hashtags || []).join(" "))
                        }
                    }
                    Body {
                        visible: text !== ""
                        text: root.caption.description || ""
                        weight: Tokens.weightMedium
                        font.pixelSize: Tokens.fontSubtitle + 1
                        color: Theme.text_strong
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: (root.caption.hashtags || []).length > 0
                        spacing: Tokens.space2
                        Repeater {
                            model: root.caption.hashtags || []
                            Pill { text: modelData; tint: Theme.secondary_container }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.space2
                        visible: (root.idea.pinnedComment || "") !== ""
                        radius: Tokens.radiusLg
                        color: Theme.surface_low
                        implicitHeight: pinRow.implicitHeight + Tokens.space4 * 2
                        RowLayout {
                            id: pinRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            spacing: Tokens.space3
                            C.IconGlyph { name: "bookmark"; size: 16; glyphColor: Theme.outline; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Caption { text: I18n.tr("Pinned comment") }
                                Body { text: root.idea.pinnedComment || ""; font.pixelSize: Tokens.fontLabel }
                            }
                            C.IconButton {
                                iconName: "content_copy"
                                tip: I18n.tr("Copy")
                                accent: Theme.primary
                                Layout.alignment: Qt.AlignTop
                                onClicked: root.copyRequested(root.idea.pinnedComment || "")
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: root.idea.hasCta === true
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.space3
                    Repeater {
                        model: root.idea.ctaOptions || []
                        Box {
                            Layout.fillWidth: true
                            color: Theme.surface_low
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                C.IconGlyph { name: "message"; size: 18; glyphColor: Theme.secondary_container }
                                C.AppText { text: modelData.label || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                                C.AppText {
                                    text: modelData.timing || ""
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                C.IconButton {
                                    iconName: "content_copy"
                                    tip: I18n.tr("Copy")
                                    accent: Theme.primary
                                    onClicked: root.copyRequested(modelData.text || "")
                                }
                            }
                            Body { text: modelData.text || ""; weight: Tokens.weightMedium; font.pixelSize: Tokens.fontSubtitle; color: Theme.text_strong }
                        }
                    }
                }
            }
            // v5: the Community tab / Stories teaser
            Box {
                Layout.fillWidth: true
                visible: (root.idea.communityPost || "") !== ""
                color: Theme.surface_low
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    C.IconGlyph { name: "messages"; size: 18; glyphColor: Theme.secondary_container }
                    Caption { text: I18n.tr("Community post teaser") }
                    C.IconButton {
                        iconName: "content_copy"
                        tip: I18n.tr("Copy")
                        accent: Theme.primary
                        onClicked: root.copyRequested(root.idea.communityPost || "")
                    }
                }
                Body { text: root.idea.communityPost || ""; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong }
            }
        }

        // ── v6 · CARDS & END SCREEN ──
        // Where the info cards pop on the video's own time axis, what the end
        // screen pushes, and the exact line spoken over it.
        Stage {
            id: sEndScreen
            host: root; act: 2; order: 3
            has: root.hasEndScreen
            kicker: "CARDS & END SCREEN"
            heading: I18n.tr("Where this viewer goes next")

            // the axis: only drawn when at least one card has a real time
            Box {
                id: esAxisBox
                readonly property var timed: {
                    var out = [], src = root.endS.cards || []
                    for (var i = 0; i < src.length; i++)
                        if (src[i].atSec !== undefined && src[i].atSec >= 0) out.push(src[i])
                    return out
                }
                visible: timed.length > 0
                Layout.fillWidth: true
                pad: Tokens.space4
                Caption { text: I18n.tr("Info cards on the timeline") }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    Rectangle {
                        id: esTrack
                        anchors.left: parent.left; anchors.right: parent.right
                        y: 28
                        height: 4; radius: 2
                        color: Theme.surface_highest
                        LayoutMirroring.enabled: false
                        Rectangle {
                            // the last 20 s: end-screen zone
                            height: parent.height; radius: 2
                            width: Math.min(parent.width, parent.width * Math.min(20, root.total) / root.total)
                            x: parent.width - width
                            color: U.withAlpha(Theme.secondary_container, 0.6)
                        }
                    }
                    Repeater {
                        model: esAxisBox.timed
                        Item {
                            readonly property real fx: Math.max(0, Math.min(1, (modelData.atSec || 0) / root.total))
                            x: Math.max(0, Math.min(esTrack.width - width, fx * esTrack.width - width / 2))
                            y: 0
                            width: 52; height: 40
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: esTime.implicitWidth + 10; height: 20; radius: 6
                                color: Theme.secondary_container
                                C.AppText { id: esTime; anchors.centerIn: parent; text: modelData.time || ""; mono: true; font.pixelSize: 11; weight: Tokens.weightBold; color: Theme.isDark ? "#0F0D12" : "#FFFFFF" }
                            }
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 22; width: 2; height: 12; color: Theme.secondary_container }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid && (root.endS.cards || []).length > 0 && ((root.endS.endTarget || "") !== "" || (root.endS.line || "") !== "") ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Box {
                    visible: (root.endS.cards || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Caption { text: I18n.tr("Info cards") }
                    Repeater {
                        model: root.endS.cards || []
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            Pill { Layout.alignment: Qt.AlignTop; visible: (modelData.time || "") !== ""; text: modelData.time || ""; mono: true; glyph: "schedule"; tint: Theme.secondary_container }
                            Body { text: modelData.target || ""; font.pixelSize: Tokens.fontLabel }
                        }
                    }
                }
                Box {
                    visible: (root.endS.endTarget || "") !== "" || (root.endS.line || "") !== ""
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.07 : 0.05)
                    border.color: U.withAlpha(Theme.secondary_container, 0.28)
                    Caption { visible: (root.endS.endTarget || "") !== ""; text: I18n.tr("End screen points to"); color: Theme.secondary_container }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: (root.endS.endTarget || "") !== ""
                        spacing: Tokens.space3
                        C.IconGlyph { name: "play_circle"; size: 20; glyphColor: Theme.secondary_container; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                        Body { text: root.endS.endTarget || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong }
                    }
                    Caption { visible: (root.endS.line || "") !== ""; Layout.topMargin: Tokens.space2; text: I18n.tr("Say over the last seconds") }
                    Option {
                        visible: (root.endS.line || "") !== ""
                        body: root.endS.line || ""
                        tint: Theme.secondary_container
                        onCopyClicked: (t) => root.copyRequested(t)
                    }
                }
            }
        }

        Stage {
            id: sSeo
            host: root; act: 2; order: 3
            has: root.hasSeo
            kicker: "SEO"
            heading: I18n.tr("SEO & discoverability")

            Box {
                Layout.fillWidth: true
                visible: (root.seo.description || "") !== ""
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: I18n.tr("YouTube description") }
                    C.IconButton { iconName: "content_copy"; tip: I18n.tr("Copy"); accent: Theme.primary; onClicked: root.copyRequested(root.seo.description || "") }
                }
                Body { text: root.seo.description || ""; font.pixelSize: Tokens.fontLabel }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.mid ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Box {
                    visible: (root.seo.keywords || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Caption { text: I18n.tr("Target keywords") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Repeater { model: root.seo.keywords || []; Pill { text: modelData; tint: Theme.secondary_container } }
                    }
                }
                Box {
                    visible: (root.seo.tags || []).length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: I18n.tr("Tags") }
                        C.IconButton { iconName: "content_copy"; tip: I18n.tr("Copy"); accent: Theme.primary; onClicked: root.copyRequested((root.seo.tags || []).join(", ")) }
                    }
                    Body { text: (root.seo.tags || []).join(", "); verbatim: true; font.pixelSize: Tokens.fontBody; color: Theme.on_surface_var }
                }
            }
            Box {
                Layout.fillWidth: true
                visible: (root.seo.timestamps || []).length > 0
                Caption { text: I18n.tr("Chapters") }
                Repeater {
                    model: root.seo.timestamps || []
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space4
                        C.AppText { text: modelData.time || ""; mono: true; font.pixelSize: Tokens.fontBody; color: Theme.secondary_container; Layout.preferredWidth: 64; LayoutMirroring.enabled: false }
                        Body { text: modelData.label || ""; font.pixelSize: Tokens.fontLabel }
                    }
                }
            }
        }

        Stage {
            id: sMoney
            host: root; act: 2; order: 4
            has: root.hasMoney
            kicker: "MONETIZATION & REACH"
            heading: I18n.tr("Revenue fit, and where else it lives")

            GridLayout {
                Layout.fillWidth: true
                columns: root.mid && root.idea.hasMonetization === true && root.idea.hasRepurpose === true ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3

                Box {
                    visible: root.idea.hasMonetization === true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    RowLayout {
                        Layout.fillWidth: true
                        visible: (root.monet.adSafetyLabel || "") !== ""
                        spacing: Tokens.space3
                        C.IconGlyph { name: root.monet.adSafety === "Risky" ? "warning" : "verified"; size: 24; glyphColor: root.monetAccent }
                        C.AppText { text: root.monet.adSafetyLabel || ""; weight: Tokens.weightExtraBold; font.pixelSize: Tokens.fontTitle; color: Theme.text_strong; Layout.fillWidth: true }
                    }
                    Body { visible: text !== ""; text: root.monet.why || ""; font.pixelSize: Tokens.fontLabel; color: Theme.on_surface_var }
                    Caption { visible: (root.monet.sponsorFit || []).length > 0; text: I18n.tr("Sponsor fit"); Layout.topMargin: Tokens.space2 }
                    Flow {
                        Layout.fillWidth: true
                        visible: (root.monet.sponsorFit || []).length > 0
                        spacing: Tokens.space2
                        Repeater { model: root.monet.sponsorFit || []; Pill { text: modelData; tint: root.monetAccent } }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.space2
                        visible: (root.monet.productTieIn || "") !== ""
                        radius: Tokens.radiusLg
                        color: Theme.surface_low
                        implicitHeight: tieCol.implicitHeight + Tokens.space4 * 2
                        ColumnLayout {
                            id: tieCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            spacing: 2
                            Caption { text: I18n.tr("Natural product tie-in") }
                            Body { text: root.monet.productTieIn || ""; font.pixelSize: Tokens.fontLabel }
                        }
                    }
                }

                Box {
                    visible: root.idea.hasRepurpose === true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Caption { text: I18n.tr("One shoot, more distribution") }
                    Repeater {
                        model: root.idea.repurpose || []
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space2
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                C.AppText { text: modelData.platform || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong; Layout.fillWidth: true; elide: Text.ElideRight }
                                C.IconButton { iconName: "content_copy"; tip: I18n.tr("Copy"); accent: Theme.primary; implicitWidth: 28; implicitHeight: 28; onClicked: root.copyRequested(modelData.how || "") }
                            }
                            Body { text: modelData.how || ""; font.pixelSize: Tokens.fontLabel; color: Theme.on_surface_var }
                            Rectangle { Layout.fillWidth: true; Layout.topMargin: Tokens.space2; height: 1; color: Theme.border; visible: index < (root.idea.repurpose || []).length - 1 }
                        }
                    }
                }
            }
        }

        // ── v5 · RIGHTS ──
        Stage {
            id: sRights
            host: root; act: 2; order: 5
            has: root.hasRights
            kicker: "RIGHTS"
            heading: I18n.tr("Copyright and Content ID")
            aside: [
                Pill {
                    visible: (root.rights.riskLabel || "") !== ""
                    glyph: "verified"
                    text: root.rights.riskLabel || ""
                    tint: root.rightsAccent
                    strong: true
                }
            ]
            Box {
                Layout.fillWidth: true
                color: U.withAlpha(root.rightsAccent, Theme.isDark ? 0.06 : 0.05)
                border.color: U.withAlpha(root.rightsAccent, 0.26)
                Body {
                    visible: text !== ""
                    text: root.rights.notes || ""
                    font.pixelSize: Tokens.fontLabel + 1
                    color: Theme.text_strong
                }
                Caption { visible: (root.rights.safeMoves || []).length > 0; text: I18n.tr("Keep it safe"); Layout.topMargin: Tokens.space2 }
                Repeater {
                    model: root.rights.safeMoves || []
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        C.IconGlyph { name: "check_circle"; size: 16; glyphColor: Theme.secondary_container; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                        Body { text: modelData }
                    }
                }
            }
        }

        Stage {
            id: sRisks
            host: root; act: 2; order: 5
            has: root.hasRisks
            kicker: "RISKS"
            heading: I18n.tr("What could sink this video")

            Repeater {
                model: root.idea.risks || []
                Rectangle {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    color: Theme.surface_low
                    border.width: 1
                    border.color: Theme.border
                    implicitHeight: rkGrid.implicitHeight + Tokens.space4 * 2
                    GridLayout {
                        id: rkGrid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space4
                        columns: root.mid ? 3 : 1
                        columnSpacing: Tokens.space4
                        rowSpacing: Tokens.space2
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.leftMargin: Tokens.space2
                            spacing: Tokens.space3
                            C.IconGlyph { name: "warning"; size: 18; glyphColor: Theme.error; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                            Body { text: modelData.risk || ""; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong }
                        }
                        C.IconGlyph {
                            visible: root.mid && (modelData.fix || "") !== ""
                            name: I18n.rtl ? "arrow_back" : "arrow_forward"
                            size: 18
                            glyphColor: Theme.outline
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Rectangle {
                            visible: (modelData.fix || "") !== ""
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            radius: Tokens.radiusLg
                            color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.08 : 0.07)
                            implicitHeight: fixTxt.implicitHeight + Tokens.space3 * 2
                            Body {
                                id: fixTxt
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.space4
                                text: modelData.fix || ""
                                font.pixelSize: Tokens.fontLabel
                            }
                        }
                    }
                }
            }
        }

        // ══════════════════════════ ACT 4 · GROW ══════════════════════════

        // ── v6 · CHECKPOINTS (Grow) ──
        // 1 hour → 24 hours → 7 days as three stations on one line. Each says
        // what to open in Studio, what good looks like, and the move if not.
        // Tick a station once you've checked it (per idea, not saved).
        Stage {
            id: sCheckpoints
            host: root; act: 3; order: 0
            has: root.hasCheckpoints
            kicker: "CHECKPOINTS"
            heading: I18n.tr("What to check, and when")
            aside: [ Pill {
                visible: root.mid
                glyph: "query_stats"
                text: I18n.tr("Against your channel's usual, not someone else's")
                tint: root.growColor
                maxTextWidth: 320
            } ]

            GridLayout {
                id: cpGrid
                Layout.fillWidth: true
                readonly property int n: (root.idea.checkpoints || []).length
                columns: root.mid ? Math.max(1, Math.min(3, n)) : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.idea.checkpoints || []
                    Rectangle {
                        id: cp
                        readonly property bool done: root.cpDone[index] === true
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        radius: Tokens.radiusXl + 2
                        color: done ? U.withAlpha(root.growColor, Theme.isDark ? 0.10 : 0.07) : Theme.surface_high
                        border.width: 1
                        border.color: done ? U.withAlpha(root.growColor, 0.45) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        implicitHeight: cpCol.implicitHeight + Tokens.space5 * 2
                        ColumnLayout {
                            id: cpCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space5
                            spacing: Tokens.space2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                // the station dot
                                Rectangle {
                                    width: 30; height: 30; radius: 15
                                    color: cp.done ? root.growColor : U.withAlpha(root.growColor, 0.16)
                                    border.width: cp.done ? 0 : 1.5
                                    border.color: U.withAlpha(root.growColor, 0.6)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                    C.AppText {
                                        anchors.centerIn: parent
                                        visible: !cp.done
                                        text: root.num(index + 1)
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Tokens.fontCaption + 1
                                        color: root.growColor
                                    }
                                    C.IconGlyph { anchors.centerIn: parent; visible: cp.done; name: "check"; size: 16; glyphColor: Theme.isDark ? "#0F0D12" : "#FFFFFF" }
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: modelData.whenLabel || modelData.when || ""
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontSubtitle + 2
                                    color: Theme.text_strong
                                    elide: Text.ElideRight
                                }
                                C.IconButton {
                                    iconName: cp.done ? "check_circle" : "check"
                                    tip: cp.done ? I18n.tr("Checked") : I18n.tr("Mark as checked")
                                    accent: root.growColor
                                    active: cp.done
                                    implicitWidth: 30; implicitHeight: 30
                                    onClicked: {
                                        var m = Object.assign({}, root.cpDone)
                                        m[index] = !cp.done
                                        root.cpDone = m
                                    }
                                }
                            }
                            Caption { visible: (modelData.check || "") !== ""; Layout.topMargin: Tokens.space1; text: I18n.tr("Open in Studio") }
                            Body { visible: text !== ""; text: modelData.check || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: (modelData.goodSign || "") !== ""
                                Layout.topMargin: Tokens.space1
                                spacing: Tokens.space2
                                C.IconGlyph { name: "check_circle"; size: 15; glyphColor: Theme.secondary_container; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                                Body { text: modelData.goodSign || ""; font.pixelSize: Tokens.fontBody }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: (modelData.ifNot || "") !== ""
                                spacing: Tokens.space2
                                C.IconGlyph { name: I18n.rtl ? "arrow_back" : "arrow_forward"; size: 15; glyphColor: Theme.warn; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                                Body { text: modelData.ifNot || ""; font.pixelSize: Tokens.fontBody; color: Theme.on_surface_var }
                            }
                        }
                    }
                }
            }
        }

        // ── v5 · IF IT STALLS ──
        Stage {
            id: sPlaybook
            host: root; act: 3; order: 1
            has: root.hasPlaybook
            kicker: "PLAYBOOK"
            heading: I18n.tr("If Studio shows this in the first 48 hours")

            Repeater {
                model: root.idea.playbook || []
                Rectangle {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    color: Theme.surface_low
                    border.width: 1
                    border.color: Theme.border
                    implicitHeight: pbGrid.implicitHeight + Tokens.space4 * 2
                    GridLayout {
                        id: pbGrid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space4
                        columns: root.mid ? 3 : 1
                        columnSpacing: Tokens.space4
                        rowSpacing: Tokens.space2
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.leftMargin: Tokens.space2
                            spacing: Tokens.space3
                            C.IconGlyph { name: "query_stats"; size: 18; glyphColor: Theme.warn; Layout.alignment: Qt.AlignTop; Layout.topMargin: 3 }
                            Body { text: modelData.signal || ""; font.pixelSize: Tokens.fontLabel + 1; color: Theme.text_strong }
                        }
                        C.IconGlyph {
                            visible: root.mid && (modelData.action || "") !== ""
                            name: I18n.rtl ? "arrow_back" : "arrow_forward"
                            size: 18
                            glyphColor: Theme.outline
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Rectangle {
                            visible: (modelData.action || "") !== ""
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            radius: Tokens.radiusLg
                            color: U.withAlpha(Theme.tertiary, Theme.isDark ? 0.08 : 0.06)
                            implicitHeight: pbTxt.implicitHeight + Tokens.space3 * 2
                            Body {
                                id: pbTxt
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.space4
                                text: modelData.action || ""
                                font.pixelSize: Tokens.fontLabel
                            }
                        }
                    }
                }
            }
        }

        // ── v6 · REPLY BANK (Grow) ──
        // The comments this video will get, each with a reply ready to paste —
        // drawn as a comment thread so it reads like the place it goes.
        Stage {
            id: sReplies
            host: root; act: 3; order: 2
            has: root.hasReplies
            kicker: "REPLY BANK"
            heading: I18n.tr("Comments you'll get, answers ready")

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.idea.replyBank || []
                    Rectangle {
                        id: rb
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        radius: Tokens.radiusXl
                        color: Theme.surface_high
                        border.width: 1
                        border.color: rbHover.hovered ? U.withAlpha(root.growColor, 0.4) : Theme.border
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        implicitHeight: rbCol.implicitHeight + Tokens.space4 * 2
                        HoverHandler { id: rbHover }
                        ColumnLayout {
                            id: rbCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            spacing: Tokens.space3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    width: 28; height: 28; radius: 14
                                    color: Theme.surface_highest
                                    C.IconGlyph { anchors.centerIn: parent; name: "user"; size: 15; glyphColor: Theme.on_surface_var }
                                }
                                Body { text: modelData.comment || ""; font.pixelSize: Tokens.fontLabel; color: Theme.on_surface }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: (modelData.reply || "") !== ""
                                spacing: Tokens.space3
                                // indent: the reply sits under the comment, like a thread
                                Item { Layout.preferredWidth: 28; Layout.preferredHeight: 1 }
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    width: 28; height: 28; radius: 14
                                    color: root.growColor
                                    C.IconGlyph { anchors.centerIn: parent; name: "message"; size: 14; glyphColor: Theme.isDark ? "#0F0D12" : "#FFFFFF" }
                                }
                                Body { text: modelData.reply || ""; font.pixelSize: Tokens.fontLabel; color: Theme.text_strong }
                                C.IconButton {
                                    Layout.alignment: Qt.AlignTop
                                    iconName: "content_copy"
                                    tip: I18n.tr("Copy reply")
                                    accent: Theme.primary
                                    implicitWidth: 28; implicitHeight: 28
                                    opacity: rbHover.hovered ? 1 : 0.45
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                    onClicked: root.copyRequested(modelData.reply || "")
                                }
                            }
                        }
                    }
                }
            }
        }

        Stage {
            id: sSeries
            host: root; act: 3; order: 3
            has: root.hasSeries
            kicker: "SERIES"
            heading: I18n.tr("What comes next — keep this viewer")

            GridLayout {
                id: serGrid
                Layout.fillWidth: true
                readonly property int n: (root.idea.seriesNext || []).length
                columns: root.mid ? Math.max(1, Math.min(3, n)) : 1
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.idea.seriesNext || []
                    Rectangle {
                        id: ep
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: Tokens.radiusXl + 2
                        color: epHover.hovered ? U.hoverTint(Theme.surface_high, Theme.isDark) : Theme.surface_high
                        border.width: 1
                        border.color: epHover.hovered ? U.withAlpha(Theme.secondary_container, 0.35) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        implicitHeight: Math.max(170, epCol.implicitHeight + Tokens.space5 * 2 + 34)
                        HoverHandler { id: epHover }
                        transform: Translate {
                            id: epLift
                            y: epHover.hovered ? -3 : 0
                            Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                        // keep the hit box on the resting footprint too (see LiftMask.qml)
                        containmentMask: C.LiftMask { target: ep; dy: epLift.y }
                        C.AppText {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Tokens.space5
                            text: "EP " + ((index + 2) < 10 ? "0" : "") + (index + 2)
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            font.letterSpacing: 1.2
                            color: Theme.secondary_container
                        }
                        ColumnLayout {
                            id: epCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Tokens.space5
                            spacing: Tokens.space1
                            Body { text: modelData.title || ""; weight: Tokens.weightBold; font.pixelSize: Tokens.fontSubtitle + 2; color: Theme.text_strong }
                            Body { visible: text !== ""; text: modelData.why || ""; selectable: false; font.pixelSize: Tokens.fontBody; color: Theme.outline }
                        }
                    }
                }
            }
        }

        // ═════════════ next act ═════════════
        AbstractButton {
            id: nextCard
            readonly property int nx: root.nextAct(root.activeAct)
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space6
            visible: nx >= 0
            implicitHeight: nextRow.implicitHeight + Tokens.space6 * 2
            onClicked: root.setAct(nx)
            HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
            background: Rectangle {
                radius: Tokens.radiusXl + 6
                color: nextHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
                border.width: 1
                border.color: nextHover.hovered && nextCard.nx >= 0 ? U.withAlpha(root.actColor(nextCard.nx), 0.4) : Theme.border
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            }
            contentItem: Item {
                implicitHeight: nextRow.implicitHeight
                RowLayout {
                    id: nextRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.space6
                    spacing: Tokens.space4
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        C.AppText { text: I18n.tr("Next step"); font.pixelSize: Tokens.fontBody; color: Theme.outline }
                        C.AppText {
                            text: nextCard.nx >= 0 ? root.num(nextCard.nx + 1) + ". " + root.acts[nextCard.nx].name : ""
                            weight: Tokens.weightExtraBold
                            font.pixelSize: 32
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: nextCard.nx >= 0 ? root.acts[nextCard.nx].sub : ""
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    Rectangle {
                        width: 56; height: 56; radius: 28
                        color: nextCard.nx >= 0 ? root.actColor(nextCard.nx) : Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                        transform: Translate {
                            x: nextHover.hovered ? (I18n.rtl ? -6 : 6) : 0
                            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: I18n.rtl ? "arrow_back" : "arrow_forward"
                            size: 22
                            glyphColor: Theme.isDark ? "#0F0D12" : "#FFFFFF"
                        }
                    }
                }
            }
        }

        // ═════════════ footer ═════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space4
            Layout.bottomMargin: Tokens.space6
            spacing: Tokens.space3
            C.PrimaryButton {
                variant: "ghost"
                iconName: "auto_awesome"
                text: root.regenerating ? I18n.tr("Rebuilding …") : I18n.tr("Regenerate this blueprint")
                enabled: !root.regenerating
                implicitHeight: 40
                onClicked: root.regenerateRequested(root.idea.id || 0)
            }
            Item { Layout.fillWidth: true }
            C.AppText {
                text: I18n.tr("Saved automatically — this blueprint is in your Content Lab library.")
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
                wrapMode: Text.Wrap
                Layout.maximumWidth: 340
            }
        }
    }
}
