import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Dialogs
import NicheScope
import "../components" as C
import "../Utils.js" as U

// AI Ideas — v10 "Studio Brief".
//
// Describe the video you want to make, and/or hand-pick reference videos that
// already perform, then have the AI build full production blueprints.
//
// Design plan (kept here so later edits can check the render against it):
//   * Subject — a producer's brief desk, not a settings form. The page reads
//     as one order: RECIPE (what to build from) → INGREDIENTS (your words,
//     reference videos) → BUILD (a launch bar that summarises the order like a
//     checkout, then one big button) → the blueprints.
//   * Composer — recipe list on one side, the writing surface on the other.
//     A recipe that ignores your idea folds the surface into one calm card
//     with the way back, instead of a dead textarea.
//   * Launch bar — the order summary (recipe · idea · picks) + count + Create.
//     While you pick references far below it, a floating dock carries the
//     same Create button, so the one action on the page is never a scroll away.
//   * Pipeline — (removed in v1.0.4: the step badges on each panel say it)
//   * My channel (v1.0.4) — who is making the video: niche, audience, what
//     they can't do (faceless, phone only…) and the output language. Set once,
//     sent with every run, so a greenlight is something THIS creator can shoot.
//   * Type & colour — Hanken / IRANYekanX via FontBridge, live Theme accent;
//     the accent is reserved for "chosen", "ready" and the Create action.
Item {
    id: page

    // Reference picker collapsed/expanded.
    property bool pickerOpen: true

    Connections {
        target: Ideas
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    // Loading the section list and the AI provider config is cheap; doing it
    // on show means the page never displays a stale archive or key state.
    onVisibleChanged: if (visible) {
        Ideas.reloadConfig()
        Ideas.refreshSections()
    }

    Component.onCompleted: {
        Ideas.reloadConfig()
        Ideas.refreshSections()
    }

    // Debounce the quick-filter field.
    Timer {
        id: filterTimer
        interval: 220
        onTriggered: Ideas.applyFilters()
    }

    // ═══ step state — derived only from VM state ═══
    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    readonly property bool _s1: !Ideas.briefRequired || String(Ideas.brief || "").trim() !== ""
    readonly property bool _s2: !Ideas.videosRequired || Ideas.selectedCount > 0
    // Settings ▸ Appearance ▸ ambient motion off: switch ideas with no veil
    readonly property bool _motionOk: App.ambientMotion === undefined || App.ambientMotion
    readonly property bool _s3: Ideas.hasIdeas
    readonly property int _cur: !_s1 ? 1 : (!_s2 ? 2 : 3)
    readonly property int _doneCount: (_s1 ? 1 : 0) + (_s2 ? 1 : 0) + (_s3 ? 1 : 0)
    readonly property bool _wide: content.width >= 1100
    readonly property bool _narrow: content.width < 760
    readonly property int _heroSize: Math.round(Math.max(30, Math.min(46, content.width / 32)))
    readonly property var _recipe: (Ideas.briefModeOptions && Ideas.briefModeOptions.length > Ideas.briefMode)
                                   ? Ideas.briefModeOptions[Ideas.briefMode] : ({ label: "", icon: "auto_awesome" })

    // The floating dock shows while the launch bar is below the viewport —
    // i.e. while you are composing or picking, never while reading results.
    readonly property real _viewBottom: pageScroll.contentItem
                                        ? pageScroll.contentItem.contentY + pageScroll.height : 0
    readonly property bool _dockOn: !Ideas.busy && genPanel.visible
                                    && (content.y + genPanel.y + 72) > _viewBottom

    component StepBadge: Rectangle {
        id: sbd
        property string n: "1"
        property bool done: false
        property bool current: false
        width: 32; height: 32
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        Layout.alignment: Qt.AlignVCenter
        radius: 16
        color: sbd.done ? U.withAlpha(Theme.secondary_container, 0.16)
             : sbd.current ? Theme.primary : Theme.surface_high
        border.width: 1
        border.color: sbd.done ? U.withAlpha(Theme.secondary_container, 0.50)
                    : sbd.current ? Theme.primary : Theme.border
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        // a soft halo on the current step
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8; height: width; radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: U.withAlpha(Theme.primary, 0.18)
            visible: sbd.current && !sbd.done
        }
        C.AppText {
            visible: !sbd.done
            anchors.centerIn: parent
            text: sbd.n
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontBody
            color: sbd.current ? Theme.on_primary : Theme.on_surface_var
        }
        C.IconGlyph {
            visible: sbd.done
            anchors.centerIn: parent
            name: "check"; size: 16
            glyphColor: Theme.secondary_container
        }
    }

    // One "ingredient" of a recipe (Videos / Your idea): lit when the recipe
    // uses it, struck through when it doesn't.
    component Ingredient: Rectangle {
        id: ing
        property string icon: ""
        property string label: ""
        property bool used: true
        property bool lit: false
        radius: Tokens.radiusPill
        implicitWidth: ingRow.implicitWidth + 16
        implicitHeight: 24
        color: ing.used ? U.withAlpha(Theme.primary, ing.lit ? 0.16 : 0.08) : U.withAlpha(Theme.primary, 0)
        border.width: 1
        border.color: ing.used ? U.withAlpha(Theme.primary, ing.lit ? 0.45 : 0.22)
                               : U.withAlpha(Theme.on_surface, 0.12)
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        Row {
            id: ingRow
            anchors.centerIn: parent
            spacing: 5
            C.IconGlyph {
                name: ing.icon
                size: 12
                glyphColor: ing.used ? Theme.primary : Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: ing.label
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                font.strikeout: !ing.used
                color: ing.used ? Theme.primary : Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // A summary token in the launch bar: icon + text, ok/missing tone.
    component OrderToken: Rectangle {
        id: tok
        property string icon: ""
        property string label: ""
        property bool ok: true
        property bool muted: false
        radius: Tokens.radiusPill
        implicitWidth: tokRow.implicitWidth + Tokens.space3 * 2
        implicitHeight: 30
        color: tok.muted ? U.withAlpha(Theme.secondary_container, 0)
             : tok.ok ? U.withAlpha(Theme.secondary_container, 0.10)
             : U.withAlpha(Theme.warn, 0.10)
        border.width: 1
        border.color: tok.muted ? Theme.border
                    : tok.ok ? U.withAlpha(Theme.secondary_container, 0.35)
                    : U.withAlpha(Theme.warn, 0.35)
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        Row {
            id: tokRow
            anchors.centerIn: parent
            spacing: Tokens.space2
            C.IconGlyph {
                name: tok.icon; size: 13
                glyphColor: tok.muted ? Theme.outline : tok.ok ? Theme.secondary_container : Theme.warn
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: tok.label
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                font.strikeout: tok.muted
                color: tok.muted ? Theme.outline : Theme.text_strong
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Saved-search shelf arrows: glide about one screen of cards per click.
    // originX keeps the clamp right in RTL, where the strip runs the other way.
    function shelfStep(dir) {
        const lv = secList
        const step = Math.max(240, lv.width * 0.8) * dir * (I18n.rtl ? -1 : 1)
        const minX = lv.originX
        const maxX = lv.originX + Math.max(0, lv.contentWidth - lv.width)
        shelfAnim.stop()
        shelfAnim.from = lv.contentX
        shelfAnim.to = Math.max(minX, Math.min(maxX, lv.contentX + step))
        shelfAnim.start()
    }

    C.SmoothScrollView {
        id: pageScroll
        anchors.fill: parent

        Item {
            id: canvas
            width: parent.width
            // room at the foot for the floating dock
            implicitHeight: content.implicitHeight + Tokens.space7 * 2 + 40

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 460
            }

            ColumnLayout {
                id: content
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space6
                spacing: Tokens.space4

                // ═══════════════ HERO ═══════════════
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Tokens.space2
                    spacing: Tokens.space6

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: Tokens.space3

                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            Rectangle {
                                radius: Tokens.radiusPill
                                color: U.withAlpha(Theme.primary, 0.10)
                                border.width: 1
                                border.color: U.withAlpha(Theme.primary, 0.28)
                                width: aiEyebrow.implicitWidth + Tokens.space3 * 2
                                height: 28
                                Row {
                                    id: aiEyebrow
                                    anchors.centerIn: parent
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: "auto_awesome"; size: 13; fill: true
                                        glyphColor: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    C.AppText {
                                        text: I18n.tr("AI Ideas · Greenlight Builder")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                            // the engine: which AI provider will build this
                            Rectangle {
                                visible: Ideas.hasAiKey
                                radius: Tokens.radiusPill
                                color: Theme.surface_low
                                border.width: 1
                                border.color: Theme.border
                                width: engineRow.implicitWidth + Tokens.space3 * 2
                                height: 28
                                Row {
                                    id: engineRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.space2
                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        color: Theme.secondary_container
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    C.AppText {
                                        text: Ideas.providerLabel
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    C.AppText {
                                        visible: Ideas.isGeminiProvider
                                        text: "· " + I18n.tr("web + video")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                HoverHandler { id: engineHover }
                                C.AppTooltip { visible: engineHover.hovered; text: Ideas.providerCapabilityNote }
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            C.AppText {
                                text: I18n.tr("Turn videos that already work")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: page._heroSize
                                font.letterSpacing: I18n.rtl ? 0 : -page._heroSize * 0.022
                                lineHeight: 1.05
                                color: Theme.text_strong
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                            C.AppText {
                                text: I18n.tr("into your next greenlight.")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: page._heroSize
                                font.letterSpacing: I18n.rtl ? 0 : -page._heroSize * 0.022
                                lineHeight: 1.05
                                color: Theme.primary
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        C.AppText {
                            text: I18n.tr("Describe the video you want to make, pick references that already perform, or both — and get full production greenlights back.")
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            Layout.maximumWidth: 660
                        }
                    }

                    // v1.0.4: the three-node pipeline card that sat here is gone. It
                    // repeated the step badges every panel below already carries, and
                    // pushed the first real control (the composer) down the page.
                }

                // ── no AI provider banner ──
                // The one blocker no layout works around: stated once, with the fix.
                Rectangle {
                    Layout.fillWidth: true
                    visible: !Ideas.hasAiKey
                    radius: Tokens.radiusLg
                    color: U.withAlpha(Theme.warn, 0.08)
                    border.width: 1
                    border.color: U.withAlpha(Theme.warn, 0.35)
                    implicitHeight: warnRow.implicitHeight + Tokens.space4 * 2
                    RowLayout {
                        id: warnRow
                        anchors.fill: parent
                        anchors.margins: Tokens.space4
                        spacing: Tokens.space3
                        C.IconTile {
                            iconName: "key"
                            size: 36
                            tint: Theme.warn
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                        }
                        C.AppText {
                            text: I18n.tr("No AI provider configured — add a key in Settings to generate greenlights.")
                            color: Theme.text_strong
                            weight: Tokens.weightDemiBold
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        C.PrimaryButton {
                            iconName: "settings"
                            text: I18n.tr("Open Settings")
                            implicitHeight: 38
                            onClicked: App.goto(10)
                        }
                    }
                }

                // ═══════════════ MY CHANNEL (v1.0.4) ═══════════════
                // The one thing every run was missing: who is making the video.
                // Folded to one line once it is set; it rides along with every
                // run (and every single-greenlight rebuild) from then on.
                C.GlassPanel {
                    id: creatorCard
                    objectName: "tour_ideasCreator"
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    property bool open: false
                    implicitHeight: creatorCol.implicitHeight + Tokens.space5 * 2
                    border.color: Ideas.hasCreator ? U.withAlpha(Theme.primary, 0.30) : Theme.border

                    ColumnLayout {
                        id: creatorCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space4

                        GridLayout {
                            Layout.fillWidth: true
                            columns: page._narrow ? 1 : 3
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                C.IconTile {
                                    iconName: "user"
                                    size: 36
                                    tint: Theme.primary
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Row {
                                        spacing: Tokens.space2
                                        C.AppText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: I18n.tr("My channel")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontSubtitle
                                            color: Theme.text_strong
                                        }
                                        Rectangle {
                                            visible: Ideas.hasCreator
                                            anchors.verticalCenter: parent.verticalCenter
                                            radius: Tokens.radiusPill
                                            implicitWidth: inUse.implicitWidth + 14
                                            implicitHeight: 22
                                            color: U.withAlpha(Theme.secondary_container, 0.12)
                                            border.width: 1
                                            border.color: U.withAlpha(Theme.secondary_container, 0.35)
                                            C.AppText {
                                                id: inUse
                                                anchors.centerIn: parent
                                                text: I18n.tr("In every run")
                                                font.pixelSize: Tokens.fontMicro
                                                weight: Tokens.weightBold
                                                color: Theme.secondary_container
                                            }
                                        }
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: Ideas.hasCreator
                                              ? Ideas.creatorSummary
                                              : I18n.tr("Tell the AI what you make and what you can't do, so every greenlight is one you can actually shoot.")
                                        font.pixelSize: Tokens.fontCaption + 1
                                        color: Theme.on_surface_var
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // output language: always one click away
                            RowLayout {
                                spacing: Tokens.space2
                                Layout.alignment: Qt.AlignVCenter
                                C.IconGlyph { name: "translate"; size: 15; glyphColor: Theme.on_surface_var }
                                C.SlideSegment {
                                    solid: false
                                    cellHeight: 30
                                    fontSize: Tokens.fontCaption + 1
                                    enabledCells: !Ideas.busy
                                    model: Ideas.outputLanguageOptions
                                    currentIndex: Ideas.outputLanguage
                                    onActivated: (i) => Ideas.outputLanguage = i
                                }
                            }

                            C.PrimaryButton {
                                Layout.alignment: Qt.AlignVCenter
                                variant: creatorCard.open || Ideas.hasCreator ? "ghost" : "primary"
                                iconName: creatorCard.open ? "check" : (Ideas.hasCreator ? "edit" : "add")
                                text: creatorCard.open ? I18n.tr("Done")
                                      : Ideas.hasCreator ? I18n.tr("Edit") : I18n.tr("Set up")
                                implicitHeight: 38
                                onClicked: {
                                    if (creatorCard.open) { nicheSave.flush(); audienceSave.flush() }
                                    creatorCard.open = !creatorCard.open
                                }
                            }
                        }

                        // ── the form ──
                        ColumnLayout {
                            visible: creatorCard.open
                            Layout.fillWidth: true
                            spacing: Tokens.space4

                            GridLayout {
                                Layout.fillWidth: true
                                columns: page._wide ? 2 : 1
                                columnSpacing: Tokens.space4
                                rowSpacing: Tokens.space3
                                C.LineField {
                                    id: nicheField
                                    Layout.fillWidth: true
                                    label: I18n.tr("What is your channel about?")
                                    placeholder: I18n.tr("e.g. Honest street-food reviews, one Short a day")
                                    Component.onCompleted: text = Ideas.creatorNiche
                                    onTextChanged: nicheSave.restart()
                                }
                                C.LineField {
                                    id: audienceField
                                    Layout.fillWidth: true
                                    label: I18n.tr("Who watches it?")
                                    placeholder: I18n.tr("e.g. 18-30, students, watch on their phone at night")
                                    Component.onCompleted: text = Ideas.creatorAudience
                                    onTextChanged: audienceSave.restart()
                                }
                            }
                            // typing is saved after a short pause, not per key
                            Timer {
                                id: nicheSave; interval: 700
                                onTriggered: Ideas.creatorNiche = nicheField.text
                                function flush() { if (running) { stop(); triggered() } }
                            }
                            Timer {
                                id: audienceSave; interval: 700
                                onTriggered: Ideas.creatorAudience = audienceField.text
                                function flush() { if (running) { stop(); triggered() } }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                C.AppText {
                                    text: I18n.tr("What you can't or won't do")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.text_strong
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: Ideas.constraintOptions
                                        delegate: AbstractButton {
                                            id: chip
                                            required property var modelData
                                            readonly property bool on: Ideas.creatorConstraints.indexOf(modelData.key) >= 0
                                            hoverEnabled: true
                                            implicitHeight: 34
                                            implicitWidth: chipRow.implicitWidth + 24
                                            onClicked: Ideas.toggleConstraint(modelData.key)
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            background: Rectangle {
                                                radius: Tokens.radiusPill
                                                color: chip.on ? U.withAlpha(Theme.primary, 0.14)
                                                     : chip.hovered ? Theme.hover_bg : Theme.surface_low
                                                border.width: 1
                                                border.color: chip.on ? U.withAlpha(Theme.primary, 0.50) : Theme.border_med
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                Row {
                                                    id: chipRow
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    C.IconGlyph {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        name: chip.on ? "check" : chip.modelData.icon
                                                        size: 14
                                                        glyphColor: chip.on ? Theme.primary : Theme.on_surface_var
                                                    }
                                                    C.AppText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: chip.modelData.label
                                                        font.pixelSize: Tokens.fontCaption + 1
                                                        weight: Tokens.weightDemiBold
                                                        color: chip.on ? Theme.text_strong : Theme.on_surface
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════ STEP 1 — the composer ═══════════════
                C.GlassPanel {
                    objectName: "tour_ideasBrief"
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: composeCol.implicitHeight + Tokens.space6 * 2

                    C.CornerGlow { radius: Tokens.radiusXl; size: 520 }

                    ColumnLayout {
                        id: composeCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            StepBadge { n: "1"; done: page._s1; current: page._cur === 1 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                C.AppText {
                                    text: I18n.tr("What should the AI build from?")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontSubtitle + 1
                                    color: Theme.text_strong
                                }
                                C.AppText {
                                    text: I18n.tr("Pick a recipe. You can switch any time, nothing is lost.")
                                    font.pixelSize: Tokens.fontCaption + 1
                                    color: Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: page._wide ? 2 : 1
                            columnSpacing: Tokens.space5
                            rowSpacing: Tokens.space4

                            // ── recipes ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 2
                                Layout.alignment: Qt.AlignTop
                                spacing: Tokens.space2

                                Repeater {
                                    model: Ideas.briefModeOptions
                                    AbstractButton {
                                        id: modeBtn
                                        Layout.fillWidth: true
                                        implicitHeight: mRow.implicitHeight + Tokens.space4 * 2
                                        hoverEnabled: true
                                        padding: 0
                                        readonly property bool active: Ideas.briefMode === index
                                        readonly property bool usesVideos: index !== 2
                                        readonly property bool usesIdea: index !== 0
                                        onClicked: Ideas.briefMode = index
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        scale: modeBtn.pressed ? 0.99 : 1.0
                                        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

                                        background: Rectangle {
                                            radius: Tokens.radiusLg
                                            color: modeBtn.active ? U.mix(Theme.surface_low, Theme.primary, Theme.isDark ? 0.09 : 0.05)
                                                 : modeBtn.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                 : Theme.surface_low
                                            border.width: 1
                                            border.color: modeBtn.active ? U.withAlpha(Theme.primary, 0.70)
                                                        : modeBtn.hovered ? U.mix(Theme.border, Theme.outline, 0.6)
                                                        : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            // lit leading edge on the chosen recipe
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: -1
                                                width: 3
                                                radius: 2
                                                height: modeBtn.active ? parent.height * 0.56 : 0
                                                color: Theme.primary
                                                Behavior on height { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                            }
                                        }

                                        contentItem: Item {
                                            RowLayout {
                                                id: mRow
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: Tokens.space4
                                                spacing: Tokens.space3

                                                C.IconTile {
                                                    iconName: modelData.icon
                                                    size: 40
                                                    solid: modeBtn.active
                                                    lit: modeBtn.hovered
                                                    Layout.preferredWidth: 40
                                                    Layout.preferredHeight: 40
                                                    Layout.alignment: Qt.AlignTop
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Tokens.space2
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2
                                                        C.AppText {
                                                            text: modelData.label
                                                            weight: Tokens.weightBold
                                                            font.pixelSize: Tokens.fontLabel
                                                            color: modeBtn.active ? Theme.primary : Theme.text_strong
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                        }
                                                        C.AppText {
                                                            text: modelData.hint
                                                            font.pixelSize: Tokens.fontCaption + 1
                                                            color: Theme.on_surface_var
                                                            wrapMode: Text.Wrap
                                                            Layout.fillWidth: true
                                                        }
                                                    }
                                                    Row {
                                                        spacing: 6
                                                        Ingredient {
                                                            icon: "movie"
                                                            label: I18n.tr("Videos")
                                                            used: modeBtn.usesVideos
                                                            lit: modeBtn.active
                                                        }
                                                        C.IconGlyph {
                                                            name: "add"; size: 13
                                                            glyphColor: Theme.outline
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        Ingredient {
                                                            icon: "edit"
                                                            label: I18n.tr("Your idea")
                                                            used: modeBtn.usesIdea
                                                            lit: modeBtn.active
                                                        }
                                                    }
                                                }
                                                // radio
                                                Rectangle {
                                                    Layout.alignment: Qt.AlignTop
                                                    width: 22; height: 22; radius: 11
                                                    Layout.preferredWidth: 22
                                                    Layout.preferredHeight: 22
                                                    color: modeBtn.active ? Theme.primary : U.withAlpha(Theme.primary, 0)
                                                    border.width: modeBtn.active ? 0 : 1.5
                                                    border.color: modeBtn.hovered ? Theme.outline : U.mix(Theme.border, Theme.outline, 0.5)
                                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                    C.IconGlyph {
                                                        anchors.centerIn: parent
                                                        visible: modeBtn.active
                                                        name: "check"; size: 13
                                                        glyphColor: Theme.on_primary
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── the writing surface ──
                            Item {
                                id: briefBox
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 3
                                readonly property bool open: Ideas.briefRequired
                                implicitHeight: open ? briefCol.implicitHeight : (page._wide ? 0 : 64)
                                Layout.minimumHeight: open ? briefCol.implicitHeight : 64
                                clip: true

                                ColumnLayout {
                                    id: briefCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: Tokens.space3
                                    opacity: briefBox.open ? 1 : 0
                                    visible: opacity > 0.01
                                    enabled: briefBox.open
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

                                    C.TextAreaField {
                                        id: briefField
                                        width: parent.width
                                        Layout.fillWidth: true
                                        rows: page._wide ? 8 : 5
                                        softLimit: 1200
                                        borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                        label: I18n.tr("Your idea, in your own words")
                                        labelIcon: "edit"
                                        placeholder: I18n.tr("e.g. I want to make a series where I try a different street food every day for 30 days. Fast cuts, lots of reactions, ends on a cliffhanger about tomorrow's dish. I want the titles to feel like a challenge, not a review.")
                                        text: Ideas.brief
                                        onTextChanged: Ideas.brief = text
                                    }

                                    // starter chips: one click adds a labelled
                                    // line, the caret lands after it
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        C.AppText {
                                            text: I18n.tr("Add a line:")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.outline
                                            height: 30
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        Repeater {
                                            model: [
                                                { k: I18n.tr("Angle"),    icon: "target" },
                                                { k: I18n.tr("Tone"),     icon: "music_note" },
                                                { k: I18n.tr("Format"),   icon: "smart_display" },
                                                { k: I18n.tr("Hook"),     icon: "bolt" },
                                                { k: I18n.tr("Audience"), icon: "user" }
                                            ]
                                            AbstractButton {
                                                id: starter
                                                height: 30
                                                implicitWidth: stRow.implicitWidth + Tokens.space3 * 2
                                                hoverEnabled: true
                                                padding: 0
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                onClicked: {
                                                    const t = String(Ideas.brief || "")
                                                    const sep = (t === "" || t.endsWith("\n")) ? "" : "\n"
                                                    Ideas.brief = t + sep + modelData.k + ": "
                                                    briefField.focusEnd()
                                                }
                                                background: Rectangle {
                                                    radius: Tokens.radiusPill
                                                    color: starter.hovered ? U.mix(Theme.surface_low, Theme.primary, 0.10) : Theme.surface_low
                                                    border.width: 1
                                                    border.color: starter.hovered ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                }
                                                contentItem: Item {
                                                    Row {
                                                        id: stRow
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        C.IconGlyph {
                                                            name: "add"; size: 12
                                                            glyphColor: starter.hovered ? Theme.primary : Theme.outline
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        C.AppText {
                                                            text: modelData.k
                                                            weight: Tokens.weightDemiBold
                                                            font.pixelSize: Tokens.fontCaption
                                                            color: starter.hovered ? Theme.primary : Theme.on_surface
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // folded state — the recipe ignores your idea
                                Rectangle {
                                    id: briefOff
                                    anchors.fill: parent
                                    radius: Tokens.radiusLg
                                    color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.025 : 0.02)
                                    border.width: 1
                                    border.color: Theme.border
                                    opacity: briefBox.open ? 0 : 1
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

                                    // wide: a centred invitation filling the column
                                    ColumnLayout {
                                        visible: page._wide
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - Tokens.space6 * 2, 420)
                                        spacing: Tokens.space3
                                        C.IconTile {
                                            Layout.alignment: Qt.AlignHCenter
                                            iconName: "lightbulb"
                                            size: 48
                                            breathe: page._motion
                                            Layout.preferredWidth: 48
                                            Layout.preferredHeight: 48
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: I18n.tr("This recipe works from your videos alone")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontLabel
                                            color: Theme.text_strong
                                            wrapMode: Text.Wrap
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: I18n.tr("Want to steer it? Add your own idea on top of the videos.")
                                            color: Theme.on_surface_var
                                            font.pixelSize: Tokens.fontCaption + 1
                                            wrapMode: Text.Wrap
                                        }
                                        C.PrimaryButton {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.topMargin: Tokens.space1
                                            variant: "ghost"
                                            iconName: "edit"
                                            text: I18n.tr("Add my idea")
                                            implicitHeight: 38
                                            onClicked: Ideas.briefMode = 1
                                        }
                                    }

                                    // narrow: one line
                                    RowLayout {
                                        visible: !page._wide
                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.space4
                                        anchors.rightMargin: Tokens.space2
                                        spacing: Tokens.space3
                                        C.IconGlyph { name: "lightbulb"; size: 18; glyphColor: Theme.primary }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: I18n.tr("Want to steer it? Add your own idea on top of the videos.")
                                            color: Theme.on_surface_var
                                            font.pixelSize: Tokens.fontCaption + 1
                                            elide: Text.ElideRight
                                        }
                                        C.PrimaryButton {
                                            variant: "ghost"
                                            iconName: "edit"
                                            text: I18n.tr("Add my idea")
                                            implicitHeight: 38
                                            onClicked: Ideas.briefMode = 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════ STEP 2 — reference videos ═══════════════
                // Collapsible, and dimmed + inert in idea-only mode.
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: refCol.implicitHeight + Tokens.space6 * 2
                    opacity: Ideas.videosRequired ? 1.0 : 0.5
                    enabled: Ideas.videosRequired
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

                    ColumnLayout {
                        id: refCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space5

                        // ── header: step, title + purpose, selection meter, collapse ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3

                            StepBadge { n: "2"; done: page._s2; current: page._cur === 2 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                C.AppText {
                                    text: Ideas.briefMode === 1
                                          ? I18n.tr("Videos to borrow style from")
                                          : I18n.tr("Reference videos")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontSubtitle + 1
                                    color: Theme.text_strong
                                }
                                C.AppText {
                                    text: Ideas.briefMode === 2
                                          ? I18n.tr("Not used in this mode — the greenlights come from your brief alone.")
                                          : (Ideas.briefMode === 1
                                             ? I18n.tr("Your idea stays the subject; these only lend their hook style, pacing and packaging.")
                                             : I18n.tr("The AI studies what these have in common and designs new videos from that pattern."))
                                    font.pixelSize: Tokens.fontCaption + 1
                                    color: Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }

                            // selection meter: count + 10 ticks (5–10 is the
                            // sweet spot for a pattern to show)
                            Rectangle {
                                visible: Ideas.selectedCount > 0
                                radius: Tokens.radiusPill
                                color: U.withAlpha(Theme.primary, 0.10)
                                border.width: 1
                                border.color: U.withAlpha(Theme.primary, 0.35)
                                implicitWidth: trayRow.implicitWidth + Tokens.space3 * 2
                                implicitHeight: 38
                                Layout.alignment: Qt.AlignVCenter
                                RowLayout {
                                    id: trayRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.space3
                                    C.AppText {
                                        text: I18n.tr("{n} picked").replace("{n}", Ideas.selectedCount)
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Tokens.fontCaption + 1
                                        color: Theme.primary
                                    }
                                    Row {
                                        spacing: 3
                                        Layout.alignment: Qt.AlignVCenter
                                        Repeater {
                                            model: 10
                                            Rectangle {
                                                width: 4; height: index < Ideas.selectedCount ? 14 : 8
                                                radius: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: index < Ideas.selectedCount
                                                       ? (index >= 4 ? Theme.secondary_container : Theme.primary)
                                                       : U.withAlpha(Theme.on_surface, 0.14)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                Behavior on height { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }
                                    C.IconButton {
                                        iconName: "close"
                                        implicitWidth: 26; implicitHeight: 26
                                        glyphSize: 14
                                        tip: I18n.tr("Clear")
                                        onClicked: Ideas.clearSelection()
                                    }
                                }
                            }

                            AbstractButton {
                                id: collapseBtn
                                implicitHeight: 38
                                implicitWidth: 38
                                hoverEnabled: true
                                onClicked: page.pickerOpen = !page.pickerOpen
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    radius: 19
                                    color: collapseBtn.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
                                    border.width: 1
                                    border.color: Theme.border
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                }
                                contentItem: C.IconGlyph {
                                    name: "expand_more"
                                    size: 18
                                    glyphColor: Theme.on_surface_var
                                    rotation: page.pickerOpen ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                }
                                C.AppTooltip {
                                    visible: collapseBtn.hovered
                                    text: page.pickerOpen ? I18n.tr("Collapse") : I18n.tr("Expand")
                                }
                            }
                        }

                        // ── the collapsible picker body ──
                        // Height animated on a plain Item: a Layout that owns its
                        // own height fights the animation (binding loop).
                        Item {
                            id: picker
                            Layout.fillWidth: true
                            readonly property real fullHeight: pickerCol.implicitHeight
                            Layout.preferredHeight: page.pickerOpen ? fullHeight : 0
                            implicitHeight: page.pickerOpen ? fullHeight : 0
                            clip: true
                            visible: Layout.preferredHeight > 0
                            Behavior on Layout.preferredHeight {
                                NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                id: pickerCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                spacing: Tokens.space4
                                opacity: page.pickerOpen ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }

                                // ── saved searches: a scrollable shelf ──
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        C.AppText {
                                            text: I18n.tr("From a saved search")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.text_strong
                                        }
                                        Rectangle {
                                            visible: Ideas.hasSections
                                            radius: Tokens.radiusPill
                                            color: Theme.surface_high
                                            implicitWidth: secCnt.implicitWidth + 12
                                            implicitHeight: 20
                                            Layout.alignment: Qt.AlignVCenter
                                            C.AppText {
                                                id: secCnt
                                                anchors.centerIn: parent
                                                text: Ideas.sections.length
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontMicro
                                                color: Theme.on_surface_var
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        C.IconButton {
                                            visible: secList.contentWidth > secList.width + 1
                                            enabled: !secList.atXBeginning
                                            opacity: enabled ? 1 : 0.35
                                            iconName: I18n.rtl ? "chevron_right" : "chevron_left"
                                            implicitWidth: 32; implicitHeight: 32
                                            glyphSize: 16
                                            onClicked: page.shelfStep(-1)
                                        }
                                        C.IconButton {
                                            visible: secList.contentWidth > secList.width + 1
                                            enabled: !secList.atXEnd
                                            opacity: enabled ? 1 : 0.35
                                            iconName: I18n.rtl ? "chevron_left" : "chevron_right"
                                            implicitWidth: 32; implicitHeight: 32
                                            glyphSize: 16
                                            onClicked: page.shelfStep(1)
                                        }
                                    }

                                    C.AppText {
                                        visible: !Ideas.hasSections
                                        text: I18n.tr("Nothing archived yet — run a Niche Finder search and it shows up here automatically.")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        visible: Ideas.hasSections
                                        implicitHeight: 88

                                        ListView {
                                            id: secList
                                            anchors.fill: parent
                                            orientation: ListView.Horizontal
                                            spacing: Tokens.space3
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds
                                            model: Ideas.sections
                                            readonly property real maxCount: {
                                                let m = 1
                                                const s = Ideas.sections
                                                for (let i = 0; i < s.length; i++)
                                                    m = Math.max(m, parseInt(s[i].count) || 0)
                                                return m
                                            }
                                            NumberAnimation {
                                                id: shelfAnim
                                                target: secList
                                                property: "contentX"
                                                duration: Tokens.durSlow
                                                easing.type: Easing.OutCubic
                                            }
                                            delegate: AbstractButton {
                                                id: secBtn
                                                height: 88
                                                width: 244
                                                hoverEnabled: true
                                                padding: 0
                                                readonly property bool active: Ideas.sectionId === modelData.id
                                                readonly property real share: Math.max(0.04, (parseInt(modelData.count) || 0) / secList.maxCount)
                                                scale: pressed ? 0.97 : 1.0
                                                Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                onClicked: secBtn.active ? Ideas.clearSection()
                                                                         : Ideas.openSection(modelData.id)

                                                background: Rectangle {
                                                    radius: Tokens.radiusLg
                                                    color: secBtn.active ? U.mix(Theme.surface_low, Theme.primary, Theme.isDark ? 0.12 : 0.07)
                                                         : secBtn.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                         : Theme.surface_low
                                                    border.width: 1
                                                    border.color: secBtn.active ? U.withAlpha(Theme.primary, 0.70)
                                                                : secBtn.hovered ? U.mix(Theme.border, Theme.outline, 0.6)
                                                                : Theme.border
                                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                    // relative-size bar along the bottom
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.leftMargin: Tokens.space4
                                                        anchors.rightMargin: Tokens.space4
                                                        anchors.bottomMargin: 10
                                                        height: 3
                                                        radius: 2
                                                        color: U.withAlpha(Theme.on_surface, 0.07)
                                                        Rectangle {
                                                            width: parent.width * secBtn.share
                                                            height: parent.height
                                                            radius: 2
                                                            color: secBtn.active ? Theme.primary : U.withAlpha(Theme.primary, 0.55)
                                                            Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                                        }
                                                    }
                                                }

                                                contentItem: Item {
                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.leftMargin: Tokens.space4
                                                        anchors.rightMargin: Tokens.space4
                                                        anchors.topMargin: Tokens.space3 + 2
                                                        spacing: Tokens.space3
                                                        C.IconTile {
                                                            iconName: secBtn.active ? "check" : "archive"
                                                            size: 38
                                                            solid: secBtn.active
                                                            lit: secBtn.hovered
                                                            Layout.preferredWidth: 38
                                                            Layout.preferredHeight: 38
                                                            Layout.alignment: Qt.AlignVCenter
                                                        }
                                                        ColumnLayout {
                                                            spacing: 2
                                                            Layout.fillWidth: true
                                                            C.AppText {
                                                                text: modelData.title
                                                                weight: Tokens.weightBold
                                                                font.pixelSize: Tokens.fontBody
                                                                color: secBtn.active ? Theme.primary : Theme.text_strong
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }
                                                            C.AppText {
                                                                text: I18n.tr("{n} videos").replace("{n}", modelData.count)
                                                                      + ((modelData.updated || "") !== "" ? "  ·  " + modelData.updated : "")
                                                                mono: true
                                                                font.pixelSize: Tokens.fontCaption
                                                                color: Theme.on_surface_var
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                            }
                                                        }
                                                    }
                                                }
                                                C.AppTooltip { visible: secBtn.hovered; text: modelData.title }
                                            }
                                        }

                                        // edge fades — "there is more this way"
                                        Rectangle {
                                            visible: !secList.atXBeginning
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 48
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: Theme.panel_bg }
                                                GradientStop { position: 1.0; color: U.withAlpha(Theme.panel_bg, 0.0) }
                                            }
                                        }
                                        Rectangle {
                                            visible: !secList.atXEnd
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 48
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: U.withAlpha(Theme.panel_bg, 0.0) }
                                                GradientStop { position: 1.0; color: Theme.panel_bg }
                                            }
                                        }
                                    }
                                }

                                // ── toolbar: search · format · sort · count · quick pick ──
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: Ideas.hasPool
                                    spacing: Tokens.space2

                                    Rectangle {
                                        Layout.preferredWidth: Math.min(300, Math.max(180, content.width * 0.2))
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitHeight: 40
                                        radius: Tokens.radiusMd
                                        color: Theme.input_bg
                                        border.width: 1
                                        border.color: filterInput.activeFocus ? Theme.primary : Theme.border
                                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Tokens.space3
                                            anchors.rightMargin: Tokens.space1
                                            spacing: Tokens.space2
                                            C.IconGlyph {
                                                name: "search"; size: 15
                                                glyphColor: filterInput.activeFocus ? Theme.primary : Theme.outline
                                            }
                                            TextField {
                                                id: filterInput
                                                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                                T.ContextMenu.menu: C.EditMenu { editor: filterInput }
                                                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                                selectedTextColor: Theme.text_strong
                                                Layout.fillWidth: true
                                                placeholderText: I18n.tr("Filter titles …")
                                                placeholderTextColor: Theme.outline
                                                color: Theme.on_surface
                                                font.family: Fonts.body
                                                font.pixelSize: Tokens.fontBody
                                                selectByMouse: true
                                                background: null
                                                leftPadding: 0; rightPadding: 0
                                                verticalAlignment: TextInput.AlignVCenter
                                                text: Ideas.quickFilter
                                                onTextChanged: { if (Ideas.quickFilter !== text) { Ideas.quickFilter = text; filterTimer.restart() } }
                                                Keys.onEscapePressed: text = ""
                                            }
                                            C.IconButton {
                                                visible: filterInput.text !== ""
                                                iconName: "close"
                                                implicitWidth: 28; implicitHeight: 28
                                                glyphSize: 13
                                                onClicked: filterInput.text = ""
                                            }
                                        }
                                    }

                                    C.SlideSegment {
                                        Layout.alignment: Qt.AlignVCenter
                                        solid: false
                                        cellHeight: 34
                                        fontSize: Tokens.fontCaption + 1
                                        iconSize: 14
                                        model: {
                                            const o = Ideas.formatOptions || []
                                            const ic = ["layout_grid", "fmt_short", "fmt_long"]
                                            let out = []
                                            for (let i = 0; i < o.length; i++)
                                                out.push({ label: o[i], icon: ic[i] || "movie" })
                                            return out
                                        }
                                        currentIndex: Ideas.formatIndex
                                        onActivated: (i) => { Ideas.formatIndex = i; Ideas.applyFilters() }
                                    }

                                    C.Dropdown {
                                        Layout.preferredWidth: 220
                                        Layout.alignment: Qt.AlignVCenter
                                        borderColor: Theme.border
                                        model: Ideas.sortOptions
                                        currentIndex: Ideas.sortIndex
                                        onActivated: { Ideas.sortIndex = currentIndex; Ideas.applyFilters() }
                                    }

                                    Item { Layout.fillWidth: true }

                                    C.AppText {
                                        text: Ideas.countLabel
                                        mono: true
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        Layout.rightMargin: Tokens.space2
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: "bolt"
                                        text: I18n.tr("Pick top 5")
                                        implicitHeight: 40
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: Ideas.selectTop(5)
                                    }
                                }

                                // ── empty state ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 210
                                    visible: !Ideas.hasRows
                                    radius: Tokens.radiusLg
                                    color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.015 : 0.02)
                                    border.width: 1
                                    border.color: Theme.border
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Tokens.space3
                                        C.IconTile {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            iconName: Ideas.hasPool ? "filter_alt" : "archive"
                                            size: 52
                                            breathe: page._motion
                                            solid: !Ideas.hasPool
                                        }
                                        C.AppText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Ideas.hasPool
                                                  ? I18n.tr("No videos match this filter.")
                                                  : I18n.tr("Pick a saved search above to choose reference videos.")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontLabel
                                            color: Theme.text_strong
                                        }
                                        C.AppText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Ideas.hasPool
                                                  ? I18n.tr("Try another format or clear the title filter.")
                                                  : I18n.tr("Tip: 5 to 10 strong videos make the clearest pattern.")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                        }
                                    }
                                }

                                // ── the reference grid ──
                                // Column count and card width come from
                                // content.width, NOT the grid's own width
                                // (binding loop → zero-wide cards).
                                GridLayout {
                                    id: refGrid
                                    Layout.fillWidth: true
                                    visible: Ideas.hasRows
                                    columnSpacing: Tokens.space3
                                    rowSpacing: Tokens.space3

                                    readonly property real availW: content.width - Tokens.space6 * 2
                                    property int _frozenCols: 0
                                    property real _frozenW: 0
                                    readonly property int _liveCols: Math.max(1, Math.floor(availW / 240))
                                    columns: (App.railAnimating && _frozenCols > 0) ? _frozenCols : _liveCols
                                    readonly property real cardW:
                                        (App.railAnimating && _frozenW > 0) ? _frozenW
                                        : (availW - columnSpacing * (columns - 1)) / columns
                                    Connections {
                                        target: App
                                        function onRailAnimatingChanged() {
                                            if (App.railAnimating) {
                                                refGrid._frozenCols = refGrid.columns
                                                refGrid._frozenW = refGrid.cardW
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: Ideas.rows
                                        C.IdeaRefCard {
                                            row: modelData
                                            // 1-based pick order (0 = not picked)
                                            order: Ideas.selectedKeys.indexOf(modelData.key) + 1
                                            cardWidth: refGrid.cardW
                                            Layout.preferredWidth: refGrid.cardW
                                            Layout.alignment: Qt.AlignTop
                                            onToggled: (key) => Ideas.toggle(key)
                                            onOpened: (url) => Ideas.openVideo(url)
                                        }
                                    }
                                }

                                // ── pager ──
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    visible: Ideas.hasRows && Ideas.pageCount > 1

                                    Item { Layout.fillWidth: true }
                                    C.Pager {
                                        pageIndex: Ideas.pageIndex
                                        pageCount: Ideas.pageCount
                                        Layout.alignment: Qt.AlignVCenter
                                        onRequested: (i) => {
                                            Ideas.gotoPage(i)
                                            pageScroll.scrollToItem(refGrid)
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }

                // ═══════════════ DATA INPUTS — CSV exports ═══════════════
                // CSV is a first-class ingredient, not a separate report room:
                // the creator can ground a blueprint in one channel or compare
                // several exports alongside the picked videos.
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: csvInputCol.implicitHeight + Tokens.space5 * 2
                    border.color: Ideas.csvCount > 0 ? U.withAlpha(Theme.secondary_container, 0.42) : Theme.border

                    ColumnLayout {
                        id: csvInputCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            StepBadge { n: "D"; done: Ideas.csvCount > 0; current: false }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Row {
                                    spacing: Tokens.space2
                                    C.AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr("Channel data exports")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontSubtitle
                                        color: Theme.text_strong
                                    }
                                    Rectangle {
                                        visible: Ideas.csvCount === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: Tokens.radiusPill
                                        implicitWidth: optTag.implicitWidth + 14
                                        implicitHeight: 22
                                        color: Theme.surface_high
                                        border.width: 1
                                        border.color: Theme.border
                                        C.AppText {
                                            id: optTag
                                            anchors.centerIn: parent
                                            text: I18n.tr("Optional")
                                            font.pixelSize: Tokens.fontMicro
                                            weight: Tokens.weightBold
                                            color: Theme.on_surface_var
                                        }
                                    }
                                }
                                C.AppText {
                                    text: I18n.tr("Add one or more CSV exports to ground the greenlight in real views, titles, lengths and publishing patterns.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            C.PrimaryButton {
                                iconName: "cloud_download"
                                text: I18n.tr("Add export")
                                variant: "ghost"
                                implicitHeight: 38
                                onClicked: csvInputDialog.open()
                            }
                        }

                        Flow {
                            visible: Ideas.csvCount > 0
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            Repeater {
                                model: Ideas.csvSources
                                Rectangle {
                                    radius: Tokens.radiusMd
                                    color: U.withAlpha(Theme.secondary_container, 0.10)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.secondary_container, 0.28)
                                    implicitWidth: csvRow.implicitWidth + Tokens.space4
                                    implicitHeight: 54
                                    RowLayout {
                                        id: csvRow
                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.space3
                                        anchors.rightMargin: Tokens.space2
                                        spacing: Tokens.space2
                                        C.IconGlyph { name: "data"; size: 16; glyphColor: Theme.secondary_container }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            C.AppText { text: modelData.name || ""; weight: Tokens.weightDemiBold; color: Theme.text_strong; elide: Text.ElideRight; Layout.fillWidth: true }
                                            C.AppText { text: (modelData.rows || 0) + " " + I18n.tr("rows") + (modelData.stats && modelData.stats.median_views ? "  ·  " + I18n.tr("median") + " " + modelData.stats.median_views : ""); font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                        C.IconButton { iconName: "close"; tip: I18n.tr("Remove"); implicitWidth: 28; implicitHeight: 28; onClicked: Ideas.removeCsv(modelData.path) }
                                    }
                                }
                            }
                        }

                    }
                }

                // ═══════════════ STEP 3 — the launch bar ═══════════════
                // The one action on the page: the order summary (recipe · idea ·
                // picks), how many blueprints, and Create — with the reason it
                // is not ready stated beside it rather than a greyed button.
                C.GlassPanel {
                    id: genPanel
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    border.color: Ideas.canGenerate ? U.withAlpha(Theme.primary, 0.50) : Theme.border
                    implicitHeight: genGrid.implicitHeight + Tokens.space5 * 2

                    // accent wash — brighter once the order is ready
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: genPanel.radius - 1
                        opacity: Ideas.canGenerate ? 1.0 : 0.4
                        Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.09) }
                            GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, 0.0) }
                            GradientStop { position: 1.0; color: U.withAlpha(Theme.tertiary, Theme.isDark ? 0.08 : 0.05) }
                        }
                    }

                    GridLayout {
                        id: genGrid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.space5
                        columns: page._wide ? 3 : 1
                        columnSpacing: Tokens.space5
                        rowSpacing: Tokens.space4

                        // ── what + status ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space4
                            StepBadge { n: "3"; done: page._s3; current: page._cur === 3 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                C.AppText {
                                    text: I18n.tr("Build the greenlights")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontSubtitle
                                    color: Theme.text_strong
                                }
                                // the order summary
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    OrderToken {
                                        icon: page._recipe.icon || "auto_awesome"
                                        label: page._recipe.label || ""
                                        ok: true
                                    }
                                    OrderToken {
                                        icon: "edit"
                                        label: I18n.tr("Your idea")
                                        muted: !Ideas.briefRequired
                                        ok: page._s1
                                    }
                                    OrderToken {
                                        icon: "movie"
                                        label: Ideas.videosRequired
                                               ? I18n.tr("{n} picked").replace("{n}", Ideas.selectedCount)
                                               : I18n.tr("Videos")
                                        muted: !Ideas.videosRequired
                                        ok: Ideas.selectedCount > 0
                                    }
                                    // v1.0.4: the creator profile rides along
                                    OrderToken {
                                        visible: Ideas.hasCreator
                                        icon: "user"
                                        label: I18n.tr("My channel")
                                        ok: true
                                    }
                                    OrderToken {
                                        visible: Ideas.outputLanguage > 0
                                        icon: "translate"
                                        label: Ideas.outputLanguageOptions[Ideas.outputLanguage] || ""
                                        ok: true
                                    }
                                }
                                C.AppText {
                                    text: Ideas.busy ? Ideas.status : Ideas.readyHint
                                    font.pixelSize: Tokens.fontCaption
                                    color: Ideas.statusKind === "error" ? Theme.error
                                         : Ideas.statusKind === "warn" ? Theme.warn
                                         : Ideas.canGenerate || Ideas.busy
                                           ? Theme.secondary_container
                                           : Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // ── how many ──
                        ColumnLayout {
                            spacing: Tokens.space2
                            Layout.alignment: page._wide ? Qt.AlignVCenter : Qt.AlignLeft
                            C.AppText {
                                text: I18n.tr("Greenlights per run")
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                            }
                            C.SlideSegment {
                                mono: true
                                cellHeight: 32
                                fontSize: Tokens.fontBody
                                enabledCells: !Ideas.busy
                                model: Ideas.countOptions
                                currentIndex: Ideas.countIndex
                                onActivated: (i) => Ideas.countIndex = i
                            }
                        }

                        // While a run is in flight this same button is Stop:
                        // the one place the eye already is. Stop shuts the live
                        // request (the provider stops generating) and nothing
                        // from the stopped run is saved.
                        C.PrimaryButton {
                            id: genBtn
                            variant: Ideas.busy ? "danger" : "primary"
                            iconName: Ideas.busy ? "crop_square" : "auto_awesome"
                            text: Ideas.busy ? I18n.tr("Stop generating")
                                             : I18n.tr("Create with AI")
                            enabled: Ideas.canGenerate || Ideas.busy
                            implicitHeight: 56
                            Layout.preferredWidth: page._wide ? Math.max(220, implicitWidth) : -1
                            Layout.fillWidth: !page._wide
                            Layout.alignment: Qt.AlignVCenter
                            indeterminate: Ideas.busy
                            onClicked: Ideas.busy ? Ideas.cancelGenerate() : Ideas.generate()
                        }
                    }
                }

                // ── generating ── (v3.39.5: BlueprintForge)
                // The brand mark forges itself while the picked references
                // orbit it; real elapsed clock, phase rail, sheets being
                // written. Unloaded entirely when idle — zero cost.
                Loader {
                    Layout.fillWidth: true
                    active: Ideas.busy
                    visible: active
                    sourceComponent: C.BlueprintForge {
                        id: forgeItem
                        active: Ideas.busy
                        status: Ideas.status
                        count: parseInt(Ideas.countOptions[Ideas.countIndex]) || 1
                        thumbs: Ideas.videosRequired ? Ideas.selectedThumbs : []
                        note: I18n.tr("This can take a few minutes — each greenlight is a full production plan. You can leave the page; the run continues.")
                        opacity: 0
                        transform: Translate { id: forgeRise; y: 14 }
                        Component.onCompleted: forgeIn.start()
                        ParallelAnimation {
                            id: forgeIn
                            NumberAnimation { target: forgeRise; property: "y"; to: 0; duration: Tokens.durSlow + 120; easing.type: Easing.OutCubic }
                            NumberAnimation { target: forgeItem; property: "opacity"; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                        }
                    }
                }

                // ═══════════════ RESULTS ═══════════════
                // Selector strip on top, full-width blueprint underneath: the
                // blueprint is the tall thing and deserves the full width.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space3
                    visible: Ideas.hasIdeas
                    spacing: Tokens.space4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.AppText {
                            text: I18n.tr("Your greenlights")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontTitle + 2
                            font.letterSpacing: I18n.rtl ? 0 : -0.4
                            color: Theme.text_strong
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Rectangle {
                            radius: Tokens.radiusPill
                            color: Theme.primary
                            implicitWidth: Math.max(24, bpCount.implicitWidth + 12)
                            implicitHeight: 22
                            Layout.alignment: Qt.AlignVCenter
                            C.AppText {
                                id: bpCount
                                anchors.centerIn: parent
                                text: Ideas.ideaCount
                                mono: true
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_primary
                            }
                        }
                        Item { Layout.fillWidth: true }

                        // All / Short / Long over the output
                        C.SlideSegment {
                            visible: Ideas.ideaCount > 0
                            Layout.alignment: Qt.AlignVCenter
                            solid: false
                            cellHeight: 30
                            fontSize: Tokens.fontCaption
                            model: [
                                Ideas.railFormatOptions[0] || "",
                                (Ideas.railFormatOptions[1] || "") + " · " + Ideas.shortCount,
                                (Ideas.railFormatOptions[2] || "") + " · " + Ideas.longCount
                            ]
                            currentIndex: Ideas.railFormat
                            onActivated: (i) => Ideas.railFormat = i
                        }

                        // Favourites filter over the OUTPUT — separate from
                        // the reference-video filters in step 2.
                        C.PrimaryButton {
                            variant: "ghost"
                            iconName: "bookmark"
                            text: Ideas.railFavOnly ? I18n.tr("Showing favorites")
                                                    : I18n.tr("Favorites only")
                            visible: Ideas.favoriteCount > 0 || Ideas.railFavOnly
                            implicitHeight: 36
                            onClicked: Ideas.railFavOnly = !Ideas.railFavOnly
                        }
                        C.PrimaryButton {
                            variant: "ghost"
                            iconName: "history"
                            text: I18n.tr("Load saved")
                            implicitHeight: 36
                            onClicked: Ideas.loadSaved()
                        }
                        C.PrimaryButton {
                            variant: "ghost"
                            iconName: "backspace"
                            text: I18n.tr("Clear view")
                            implicitHeight: 36
                            onClicked: Ideas.clearIdeas()
                        }
                    }

                    C.AppText {
                        text: I18n.tr("Pick an idea to open its full production plan below.")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    // ── the idea strip ──
                    // A PAGED rail: fixed-width cards sliding under a clip,
                    // turned by the shared C.Pager below.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !Ideas.railIsEmpty
                        spacing: Tokens.space2

                        Item {
                            id: railStrip
                            Layout.fillWidth: true
                            implicitHeight: railRow.implicitHeight + Tokens.space3
                            clip: true

                            readonly property int cardW: 300
                            readonly property int gap: Tokens.space3
                            readonly property int perPage:
                                Math.max(1, Math.floor((width + gap) / (cardW + gap)))
                            readonly property int pageCount:
                                Math.max(1, Math.ceil(Ideas.ideas.length / perPage))
                            property int pageIndex: 0
                            onPageCountChanged: if (pageIndex > pageCount - 1) pageIndex = pageCount - 1

                            Row {
                                id: railRow
                                spacing: railStrip.gap
                                y: Tokens.space1
                                x: -railStrip.pageIndex * railStrip.perPage
                                     * (railStrip.cardW + railStrip.gap)
                                Behavior on x {
                                    NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
                                }
                                Repeater {
                                    model: Ideas.ideas
                                    C.IdeaRailCard {
                                        width: railStrip.cardW
                                        idea: modelData
                                        active: Ideas.activeId === (modelData.id || 0)
                                        regenerating: Ideas.regenId === (modelData.id || 0)
                                        onSelected: (id) => Ideas.selectIdea(id)
                                        onFavorited: (id) => Ideas.toggleFavorite(id)
                                        onDeleteRequested: (id) => confirmDelete.ask(id)
                                    }
                                }
                            }
                        }

                        C.Pager {
                            Layout.alignment: Qt.AlignHCenter
                            pageIndex: railStrip.pageIndex
                            pageCount: railStrip.pageCount
                            showEdgeJumps: false
                            onRequested: (i) => railStrip.pageIndex = i
                        }
                    }

                    // The favourites filter matched nothing.
                    C.GlassPanel {
                        Layout.fillWidth: true
                        visible: Ideas.railIsEmpty
                        implicitHeight: 120
                        elevation: 0
                        Column {
                            anchors.centerIn: parent
                            spacing: Tokens.space3
                            C.AppText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: I18n.tr("No favorited greenlights yet.")
                                color: Theme.on_surface_var
                            }
                            C.PrimaryButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "ghost"
                                text: I18n.tr("Show all")
                                implicitHeight: 34
                                onClicked: Ideas.railFavOnly = false
                            }
                        }
                    }

                    // ── the open blueprint ──
                    // v3.16-p3: BlueprintStage builds the next blueprint asynchronously in a
                    // hidden pane under a skeleton veil, then swaps it in, so switching
                    // ideas no longer freezes the window for a couple of seconds.
                    C.BlueprintStage {
                        id: bpPane
                        Layout.fillWidth: true
                        scroller: pageScroll
                        visible: Ideas.hasActive
                        motion: page._motionOk
                        idea: Ideas.active
                        regenerating: Ideas.regenId === (Ideas.active.id || 0)
                        onFavorited: (id) => Ideas.toggleFavorite(id)
                        onDeleteRequested: (id) => confirmDelete.ask(id)
                        onRegenerateRequested: (id) => Ideas.regenerate(id)
                        onCopyRequested: (text) => Ideas.copyText(text)
                        // Loading the script is all this does — Main.qml raises
                        // the prompter overlay off Studio's `opened` signal.
                        onPrompterRequested: (id) => Studio.openBlueprint(id)
                    }
                }

                // ── first-run empty state ──
                C.GlassPanel {
                    Layout.fillWidth: true
                    visible: !Ideas.hasIdeas && !Ideas.busy
                    radius: Tokens.radiusXl
                    implicitHeight: 220
                    elevation: 0
                    color: U.withAlpha(Theme.panel_bg, 0.6)

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Tokens.space6 * 2, 560)
                        spacing: Tokens.space3

                        // three ghost blueprint sheets, fanned
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 64
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 56; height: 64
                                    radius: Tokens.radiusSm
                                    x: 32 + (index - 1) * 26
                                    rotation: (index - 1) * 9
                                    transformOrigin: Item.Bottom
                                    color: index === 1 ? U.mix(Theme.surface_low, Theme.primary, 0.14) : Theme.surface_low
                                    border.width: 1
                                    border.color: index === 1 ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                                    z: index === 1 ? 2 : 1
                                    Column {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 9
                                        spacing: 5
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                width: index === 0 ? 30 : (index === 3 ? 18 : 38)
                                                height: index === 0 ? 4 : 3
                                                radius: 2
                                                color: index === 0 && parent.parent.z === 2
                                                       ? Theme.primary : U.withAlpha(Theme.on_surface, 0.16)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space2
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("No greenlights yet")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontSubtitle
                            color: Theme.text_strong
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Write your idea, pick some references, or both — then Create with AI.")
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }

    // ═══ the floating dock ═══
    // Carries the Create action while the launch bar is below the fold.
    Item {
        id: dock
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(dockRow.implicitWidth + Tokens.space3 * 2, page.width - Tokens.pageGutter * 2)
        height: 60
        y: page._dockOn ? page.height - height - Tokens.space5 : page.height + 12
        opacity: page._dockOn ? 1 : 0
        visible: opacity > 0.01
        Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        C.GlassPanel {
            anchors.fill: parent
            radius: 30
            elevation: 2.2
            color: U.withAlpha(Theme.surface, 0.96)
            border.color: Ideas.canGenerate ? U.withAlpha(Theme.primary, 0.55) : Theme.border_med
        }

        RowLayout {
            id: dockRow
            anchors.fill: parent
            anchors.leftMargin: Tokens.space3
            anchors.rightMargin: Tokens.space2
            spacing: Tokens.space3

            C.IconTile {
                iconName: page._recipe.icon || "auto_awesome"
                size: 34
                solid: Ideas.canGenerate
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignVCenter
                C.AppText {
                    text: page._recipe.label || ""
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontBody
                    color: Theme.text_strong
                }
                C.AppText {
                    text: Ideas.videosRequired
                          ? I18n.tr("{n} picked").replace("{n}", Ideas.selectedCount)
                            + "  ·  " + (Ideas.countOptions[Ideas.countIndex] || "") + " " + I18n.tr("greenlights")
                          : (Ideas.countOptions[Ideas.countIndex] || "") + " " + I18n.tr("greenlights")
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                }
            }
            C.IconButton {
                iconName: "expand_more"
                implicitWidth: 36; implicitHeight: 36
                glyphSize: 18
                tip: I18n.tr("Jump to Build")
                Layout.alignment: Qt.AlignVCenter
                onClicked: pageScroll.scrollToItem(genPanel)
            }
            C.PrimaryButton {
                iconName: "auto_awesome"
                text: I18n.tr("Create with AI")
                enabled: Ideas.canGenerate
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                onClicked: Ideas.generate()
            }
        }
    }

    // Deleting a blueprint is not undoable — the row leaves the database, not
    // just the view — so it asks. "Clear view" beside it is the reversible
    // option and deliberately does NOT ask.
    Dialog {
        id: confirmDelete
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(440, page.width - 80)
        padding: 0
        title: I18n.tr("Delete this greenlight?")

        property int pendingId: -1
        property string pendingTitle: ""
        function ask(ideaId) {
            pendingId = ideaId
            var hit = null
            var list = Ideas.ideas
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
                        Ideas.deleteIdea(confirmDelete.pendingId)
                        confirmDelete.close()
                    }
                }
            }
        }
    }

    FileDialog {
        id: csvInputDialog
        title: I18n.tr("Choose channel exports")
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Channel exports (*.csv *.xlsx *.jsonl *.db)"]
        onAccepted: {
            var xs = selectedFiles || []
            for (var i = 0; i < xs.length; i++) Ideas.addCsv(xs[i].toString())
        }
    }

    C.Toast { id: toast; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 80 }
}
