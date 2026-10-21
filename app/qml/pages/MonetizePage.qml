import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Monetize Checker — resolve a channel and get a straight monetized / not
// verdict with the evidence behind it, a certainty meter, an estimated RPM/CPM
// band, and projected ad revenue. Driven by MonetizeVM (context prop
// `Monetize`): the check runs on a worker thread and the result flows back as a
// flat map the page binds to.
//
// v11 "the stamp": the page is built like an inspection.
//   * the checker card is a scanner console — one big input, a sliding format
//     switch, and the signals the check actually looks for, named up front;
//   * while it runs, a radar sweeps and those same signals light in turn;
//   * the answer lands as a verdict STAMP pressed onto the channel card, with
//     the certainty drawn as a dial — then the evidence as a grid of signal
//     cards, and the money as three tier cards you can flip between daily,
//     monthly and yearly.
// Every number and string still comes from MonetizeVM exactly as before.
Item {
    id: page

    onVisibleChanged: if (visible) Monetize.reloadKey()

    Connections {
        target: Monetize
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    // The signals the checker reads, in the VM's own keys. Used three times:
    // the console's "what we look for" row, the scanner's lit list while the
    // check runs, and the icon + name on each evidence card.
    readonly property var signalInfo: ({
        "membership":      { g: "user",          n: I18n.tr("Memberships") },
        "super_thanks":    { g: "favorite",      n: I18n.tr("Super Thanks") },
        "ads":             { g: "smart_display", n: I18n.tr("Ads on videos") },
        "midroll":         { g: "scissors",      n: I18n.tr("Mid-roll breaks") },
        "merch":           { g: "inventory_2",   n: I18n.tr("Merch shelf") },
        "subs_1k":         { g: "user",          n: I18n.tr("1K subscribers") },
        "subs_gate":       { g: "lock",          n: I18n.tr("Subscriber floor") },
        "no_ads_possible": { g: "lock",          n: I18n.tr("Ad eligibility") },
        "watch_hours":     { g: "hourglass_empty", n: I18n.tr("4K watch hours") },
        "shorts_views":    { g: "fmt_short",     n: I18n.tr("10M Shorts views") },
        "fetch_failed":    { g: "warning",       n: I18n.tr("Page check") }
    })
    readonly property var scanKeys: ["membership", "super_thanks", "ads", "midroll", "merch", "subs_1k"]
    function sig(key) {
        var s = page.signalInfo[key]
        return s ? s : { g: "check_circle", n: key }
    }

    // the lit signal while the scanner runs — a visual sweep, not a progress claim
    property int _scanIx: 0
    Timer {
        interval: 520
        repeat: true
        running: Monetize.busy && page.visible
        onTriggered: page._scanIx = (page._scanIx + 1) % page.scanKeys.length
    }

    C.SmoothScrollView {
        anchors.fill: parent

        Item {
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
                y: Tokens.space6
                spacing: Tokens.space5

                // ── heading ──
                C.PageHeader {
                    iconName: "monetization_on"
                    title: I18n.tr("Monetization Checker")
                    subtitle: I18n.tr("A straight yes or no — with evidence, certainty, RPM and projected revenue.")
                }

                // ══════════════ scanner console ══════════════
                C.GlassPanel {
                    id: consolePanel
                    Layout.fillWidth: true
                    implicitHeight: searchCol.implicitHeight + Tokens.space6 * 2
                    radius_: Tokens.radiusXl
                    elevation: 1.4

                    C.CornerGlow { radius: Tokens.radiusXl; size: 560 }

                    ColumnLayout {
                        id: searchCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: Monetize.busy ? Theme.primary : Theme.secondary_container
                                Layout.alignment: Qt.AlignVCenter
                                SequentialAnimation on opacity {
                                    running: page.visible && Tokens.appActive
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: Monetize.busy ? 380 : 1200; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: Monetize.busy ? 380 : 1200; easing.type: Easing.InOutSine }
                                }
                            }
                            C.AppText {
                                text: Monetize.busy ? I18n.tr("SCANNING") : I18n.tr("READY TO CHECK")
                                mono: true
                                weight: Tokens.weightExtraBold
                                font.pixelSize: 11
                                color: Monetize.busy ? Theme.primary : Theme.secondary_container
                            }
                            Item { Layout.fillWidth: true }
                            C.AppText {
                                text: I18n.tr("Channel URL, @handle or name")
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                            }
                        }

                        // input + check button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 62

                                // focus halo
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    radius: Tokens.radiusLg + 4
                                    color: "transparent"
                                    border.width: 4
                                    border.color: U.withAlpha(Theme.primary, urlField.activeFocus ? 0.16 : 0.0)
                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.radiusLg
                                    color: urlField.activeFocus ? Theme.input_bg : Theme.surface_low
                                    border.width: 1
                                    border.color: urlField.activeFocus ? Theme.primary : U.mix(Theme.border, Theme.outline, 0.35)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.space4
                                        anchors.rightMargin: Tokens.space2
                                        spacing: Tokens.space3
                                        C.IconGlyph {
                                            name: "youtube"; size: 20
                                            fill: true
                                            glyphColor: urlField.activeFocus ? Theme.primary : Theme.on_surface_var
                                            Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        }
                                        TextField {
                                            id: urlField
                                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                            T.ContextMenu.menu: C.EditMenu { editor: urlField }
                                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                            selectedTextColor: Theme.text_strong
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            placeholderText: "https://youtube.com/@channelname   ·   @channelname"
                                            placeholderTextColor: Theme.outline
                                            color: Theme.on_surface
                                            font.family: Fonts.body
                                            font.pixelSize: Tokens.fontLabel
                                            verticalAlignment: TextInput.AlignVCenter
                                            selectByMouse: true
                                            background: null
                                            text: Monetize.query
                                            onTextChanged: Monetize.query = text
                                            onAccepted: Monetize.check()
                                        }
                                        C.IconButton {
                                            visible: urlField.text !== "" && !Monetize.busy
                                            iconName: "close"
                                            tip: I18n.tr("Clear")
                                            implicitWidth: 30
                                            implicitHeight: 30
                                            onClicked: { urlField.text = ""; urlField.forceActiveFocus() }
                                        }
                                        Rectangle {
                                            visible: urlField.text === ""
                                            radius: Tokens.radiusXs
                                            color: Theme.surface_high
                                            border.width: 1
                                            border.color: Theme.border
                                            implicitWidth: enterLbl.implicitWidth + 12
                                            implicitHeight: 24
                                            C.AppText {
                                                id: enterLbl
                                                anchors.centerIn: parent
                                                text: "Enter ↵"
                                                mono: true
                                                font.pixelSize: 11
                                                color: Theme.on_surface_var
                                                LayoutMirroring.enabled: false
                                            }
                                        }
                                    }
                                }
                            }
                            C.PrimaryButton {
                                iconName: "search"
                                text: Monetize.busy ? I18n.tr("Checking…") : I18n.tr("Check Monetization")
                                enabled: !Monetize.busy && urlField.text.trim() !== ""
                                indeterminate: Monetize.busy
                                implicitHeight: 62
                                onClicked: Monetize.check()
                            }
                        }

                        // format switch (sliding pill) + what we look for
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space4

                            Rectangle {
                                id: fmtTrack
                                implicitWidth: fmtRowOuter.implicitWidth + 8
                                implicitHeight: 40
                                radius: Tokens.radiusPill
                                color: Theme.input_bg
                                border.width: 1
                                border.color: Theme.border

                                Rectangle {
                                    id: fmtPill
                                    readonly property Item target: fmtRep.count > Monetize.formatMode ? fmtRep.liveItemAt(Monetize.formatMode) : null
                                    x: target ? fmtRowOuter.x + target.x : 4
                                    width: target ? target.width : 0
                                    y: 4
                                    height: parent.height - 8
                                    radius: Tokens.radiusPill
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Theme.primary }
                                        GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
                                    }
                                    Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                    Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                }
                                Row {
                                    id: fmtRowOuter
                                    x: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Repeater {
                                        id: fmtRep
                                        // itemAt() is not a notifying lookup: a binding that ran before the
                                        // delegates existed got null and kept it (thumb missing on first show,
                                        // the active label invisible in light theme). `built` re-runs it.
                                        property int built: 0
                                        onItemAdded: built++
                                        onItemRemoved: built++
                                        function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                        model: [
                                            { l: I18n.tr("Auto-detect"), ic: "auto_awesome" },
                                            { l: I18n.tr("Long-form"),   ic: "fmt_long" },
                                            { l: I18n.tr("Shorts"),      ic: "fmt_short" }
                                        ]
                                        AbstractButton {
                                            id: fmtBtn
                                            height: 32
                                            implicitWidth: fmtRow.implicitWidth + Tokens.space4 * 2
                                            readonly property bool on: Monetize.formatMode === index
                                            onClicked: Monetize.formatMode = index
                                            HoverHandler { id: fmtHover; cursorShape: Qt.PointingHandCursor }
                                            background: Rectangle {
                                                radius: Tokens.radiusPill
                                                color: !fmtBtn.on && fmtHover.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark) : U.withAlpha(U.hoverTint(Theme.input_bg, Theme.isDark), 0)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                implicitWidth: fmtRow.implicitWidth
                                                implicitHeight: fmtRow.implicitHeight
                                                Row {
                                                    id: fmtRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space2
                                                    C.IconGlyph {
                                                        name: modelData.ic; size: 14
                                                        glyphColor: fmtBtn.on ? Theme.on_primary : Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                                    }
                                                    C.AppText {
                                                        text: modelData.l
                                                        weight: fmtBtn.on ? Tokens.weightBold : Tokens.weightDemiBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: fmtBtn.on ? Theme.on_primary : Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // what the check looks for
                            Row {
                                visible: consolePanel.width > 980
                                spacing: Tokens.space2
                                Layout.alignment: Qt.AlignVCenter
                                C.AppText {
                                    text: I18n.tr("Looks for")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Repeater {
                                    model: page.scanKeys
                                    Rectangle {
                                        readonly property bool lit: Monetize.busy && page._scanIx === index
                                        radius: Tokens.radiusPill
                                        color: lit ? U.withAlpha(Theme.primary, 0.18) : Theme.surface_low
                                        border.width: 1
                                        border.color: lit ? U.withAlpha(Theme.primary, 0.55) : Theme.border
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        implicitWidth: lfRow.implicitWidth + Tokens.space3
                                        implicitHeight: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        Row {
                                            id: lfRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            C.IconGlyph {
                                                name: page.sig(modelData).g; size: 12
                                                glyphColor: parent.parent.lit ? Theme.primary : Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: page.sig(modelData).n
                                                font.pixelSize: 11
                                                weight: Tokens.weightDemiBold
                                                color: parent.parent.lit ? Theme.primary : Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // v16: composed result banner instead of a mono line
                        C.ResultBanner {
                            visible: Monetize.status !== "" && !Monetize.busy
                            Layout.fillWidth: true
                            kind: Monetize.statusKind === "" ? "info" : Monetize.statusKind
                            text: Monetize.status
                            showRatio: false
                        }
                    }
                }

                // ══════════════ the mint (busy) ══════════════
                // v17.2: the radar became EarningsLoader — a coin that flips on
                // every real pipeline step (Monetize.stage), a forward-only
                // progress ring, and slot reels shaped like the answer.
                C.GlassPanel {
                    id: mintPanel
                    Layout.fillWidth: true
                    visible: Monetize.busy
                    implicitHeight: mint.implicitHeight + Tokens.space6 * 2
                    radius_: Tokens.radiusXl
                    elevation: 0.8
                    border.color: U.withAlpha(Theme.primary, 0.30)

                    C.CornerGlow { radius: Tokens.radiusXl; size: 520 }

                    // arrival: the panel rises in rather than popping
                    onVisibleChanged: if (visible) mintIn.restart()
                    opacity: 1
                    transform: Translate { id: mintShift; y: 0 }
                    ParallelAnimation {
                        id: mintIn
                        NumberAnimation { target: mintPanel; property: "opacity"; from: 0; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                        NumberAnimation { target: mintShift; property: "y"; from: 18; to: 0; duration: 460; easing.type: Easing.OutBack }
                    }

                    C.EarningsLoader {
                        id: mint
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.space6
                        anchors.rightMargin: Tokens.space6
                        running: Monetize.busy && page.visible
                        stage: Monetize.stage
                        subject: Monetize.query.trim()
                    }
                }

                // ══════════════ first-run empty state ══════════════
                C.GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: emptyCol.implicitHeight + Tokens.space7 * 2
                    visible: !Monetize.hasResult && !Monetize.busy
                    radius_: Tokens.radiusXl
                    elevation: 0
                    color: U.withAlpha(Theme.surface_low, 0.6)
                    Column {
                        id: emptyCol
                        anchors.centerIn: parent
                        spacing: Tokens.space3
                        // a blank stamp waiting for a verdict
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 190; height: 64
                            Rectangle {
                                anchors.centerIn: parent
                                width: 180; height: 52
                                radius: Tokens.radiusMd
                                rotation: -4
                                antialiasing: true
                                color: "transparent"
                                border.width: 2
                                border.color: U.withAlpha(Theme.outline, 0.45)
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    radius: Tokens.radiusSm
                                    color: "transparent"
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.outline, 0.30)
                                }
                                C.AppText {
                                    anchors.centerIn: parent
                                    text: I18n.tr("VERDICT")
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontLabel
                                    font.letterSpacing: 3
                                    color: U.withAlpha(Theme.outline, 0.8)
                                }
                            }
                        }
                        C.AppText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("Nothing checked yet")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontSubtitle
                            color: Theme.text_strong
                        }
                        C.AppText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(480, content.width - Tokens.space6 * 2)
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Paste a channel URL, @handle or name above. You'll get the verdict, the signals behind it, and an RPM-based revenue range.")
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // ══════════════ results ══════════════
                Loader {
                    Layout.fillWidth: true
                    active: Monetize.hasResult && !Monetize.busy
                    visible: active
                    sourceComponent: resultsComponent
                }
            }
        }
    }

    C.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 80
    }

    Component {
        id: resultsComponent
        ColumnLayout {
            id: res
            readonly property var r: Monetize.result
            readonly property bool mon: r.verdict.monetized
            readonly property color accent: mon ? Theme.secondary_container : Theme.error
            // 0 daily · 1 monthly · 2 yearly — the revenue cards flip on this
            property int horizon: 1
            spacing: Tokens.space5

            // staggered arrival: card, evidence, money
            Component.onCompleted: arrive.start()
            SequentialAnimation {
                id: arrive
                ParallelAnimation {
                    NumberAnimation { target: verdictCard; property: "opacity"; from: 0; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                    NumberAnimation { target: vcShift; property: "y"; from: 16; to: 0; duration: 420; easing.type: Easing.OutCubic }
                }
                ParallelAnimation {
                    NumberAnimation { target: stamp; property: "scale"; from: 1.6; to: 1.0; duration: 360; easing.type: Easing.OutBack }
                    NumberAnimation { target: stamp; property: "opacity"; from: 0; to: 1; duration: 200 }
                }
                ParallelAnimation {
                    NumberAnimation { target: evidencePanel; property: "opacity"; from: 0; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                    NumberAnimation { target: evShift; property: "y"; from: 16; to: 0; duration: 420; easing.type: Easing.OutCubic }
                }
                ParallelAnimation {
                    NumberAnimation { target: moneyPanel; property: "opacity"; from: 0; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                    NumberAnimation { target: mnShift; property: "y"; from: 16; to: 0; duration: 420; easing.type: Easing.OutCubic }
                }
            }

            // ══════════ the verdict card: who + the stamp ══════════
            C.GlassPanel {
                id: verdictCard
                Layout.fillWidth: true
                radius_: Tokens.radiusXl
                elevation: 1.5
                implicitHeight: vcCol.implicitHeight
                transform: Translate { id: vcShift; y: 0 }
                border.color: U.withAlpha(res.accent, 0.40)

                C.CornerGlow { radius: Tokens.radiusXl; size: 560; glow: res.accent }

                ColumnLayout {
                    id: vcCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 0

                    // ── the channel ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Tokens.space6
                        spacing: Tokens.space5

                        // avatar in a verdict-coloured ring
                        Item {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 104; implicitHeight: 104
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: U.withAlpha(res.accent, 0.12)
                                border.width: 2
                                border.color: res.accent
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 88; height: 88; radius: 44
                                color: Theme.surface_high
                                clip: true
                                Image {
                                    id: avatar
                                    anchors.fill: parent
                                    visible: false
                                    source: res.r.profile.thumbnailUrl || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 176; sourceSize.height: 176
                                }
                                Item {
                                    id: avatarMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    Rectangle { anchors.fill: parent; radius: 44; color: "white" }
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: avatar
                                    maskEnabled: true
                                    maskSource: avatarMask
                                    visible: avatar.status === Image.Ready
                                }
                                C.AppText {
                                    anchors.centerIn: parent
                                    visible: avatar.status !== Image.Ready
                                    text: (res.r.profile.title || "?").charAt(0).toUpperCase()
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: 36
                                    color: res.accent
                                }
                            }
                            // verdict badge on the avatar
                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 2
                                anchors.bottomMargin: 2
                                width: 30; height: 30; radius: 15
                                color: res.accent
                                border.width: 3
                                border.color: Theme.panel_bg
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    name: res.mon ? "check" : "close"
                                    size: 15
                                    glyphColor: "#ffffff"
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.space2
                            C.AppText {
                                text: res.r.profile.title
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Tokens.fontDisplay + 4
                                color: Theme.text_strong
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                            C.AppText {
                                text: res.r.profile.handle
                                mono: true
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.primary
                            }
                            C.AppText {
                                visible: res.r.profile.description !== ""
                                text: res.r.profile.description
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // the stamp
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: stamp.width + 24
                            implicitHeight: stamp.height + 24
                            visible: verdictCard.width > 760
                            Rectangle {
                                id: stamp
                                anchors.centerIn: parent
                                width: stampLbl.implicitWidth + Tokens.space6 * 2
                                height: 64
                                radius: Tokens.radiusMd
                                rotation: -5
                                antialiasing: true
                                color: U.withAlpha(res.accent, 0.08)
                                border.width: 3
                                border.color: res.accent
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    radius: Tokens.radiusSm
                                    color: "transparent"
                                    border.width: 1
                                    border.color: U.withAlpha(res.accent, 0.6)
                                }
                                C.AppText {
                                    id: stampLbl
                                    anchors.centerIn: parent
                                    text: res.mon ? I18n.tr("MONETIZED") : I18n.tr("NOT MONETIZED")
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontTitle
                                    font.letterSpacing: I18n.rtl ? 0 : 2.5
                                    color: res.accent
                                }
                            }
                        }
                    }

                    // ── channel numbers ──
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.space6
                        Layout.rightMargin: Tokens.space6
                        Layout.bottomMargin: Tokens.space5
                        spacing: Tokens.space3
                        Repeater {
                            model: [
                                { ic: "user",       l: I18n.tr("Subscribers"), v: res.r.profile.subs },
                                { ic: "visibility", l: I18n.tr("Total views"), v: res.r.profile.totalViews },
                                { ic: "video",      l: I18n.tr("Videos"),      v: res.r.profile.videoCount },
                                { ic: "public",     l: I18n.tr("Country"),     v: res.r.profile.country },
                                { ic: "history",    l: I18n.tr("Joined"),      v: res.r.profile.joined }
                            ]
                            Rectangle {
                                radius: Tokens.radiusLg
                                color: U.withAlpha(Theme.surface_high, Theme.isDark ? 0.75 : 0.9)
                                border.width: 1
                                border.color: tileHover.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                HoverHandler { id: tileHover }
                                implicitWidth: Math.max(130, tileRow.implicitWidth + Tokens.space4 * 2)
                                implicitHeight: 58
                                Row {
                                    id: tileRow
                                    anchors.left: parent.left
                                    anchors.leftMargin: Tokens.space4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.space3
                                    C.IconTile {
                                        iconName: modelData.ic
                                        size: 32; glyphSize: 15
                                        lit: tileHover.hovered
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0
                                        C.AppText {
                                            text: modelData.v
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontSubtitle
                                            color: Theme.text_strong
                                        }
                                        C.AppText {
                                            text: modelData.l
                                            font.pixelSize: 11
                                            color: Theme.on_surface_var
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── the verdict band ──
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: bandRow.implicitHeight + Tokens.space5 * 2
                        color: U.withAlpha(res.accent, Theme.isDark ? 0.10 : 0.07)
                        radius: Tokens.radiusXl
                        // square off the top corners so the band reads as the
                        // card's footer, not a card inside a card
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: Tokens.radiusXl
                            color: parent.color
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 1
                            color: U.withAlpha(res.accent, 0.30)
                        }

                        RowLayout {
                            id: bandRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.space6
                            anchors.rightMargin: Tokens.space6
                            spacing: Tokens.space5

                            C.ScoreRing {
                                value: res.r.verdict.certainty
                                accent: res.accent
                                ringSize: 92
                                thickness: 8
                                suffix: "%"
                                caption: I18n.tr("certainty")
                                numberSize: 24
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space1
                                RowLayout {
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: res.mon ? "check_circle" : "cancel"
                                        fill: true
                                        size: 24
                                        glyphColor: res.accent
                                    }
                                    C.AppText {
                                        text: res.r.verdict.headline
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Tokens.fontTitle
                                        color: res.accent
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                                C.AppText {
                                    text: res.r.verdict.reason
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.on_surface
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                                // certainty meter, for the reader who wants a line not a dial
                                C.MeterBar {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 520
                                    Layout.topMargin: Tokens.space1
                                    barHeight: 6
                                    value: res.r.verdict.certainty / 100
                                    fillColor: res.accent
                                }
                            }
                        }
                    }
                }
            }

            // ══════════ evidence: one card per signal ══════════
            C.GlassPanel {
                id: evidencePanel
                Layout.fillWidth: true
                radius_: Tokens.radiusXl
                implicitHeight: evCol.implicitHeight + Tokens.space5 * 2
                transform: Translate { id: evShift; y: 0 }

                ColumnLayout {
                    id: evCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space5
                    spacing: Tokens.space4

                    readonly property int foundCount: {
                        var n = 0
                        var cs = res.r.checks || []
                        for (var i = 0; i < cs.length; i++) if (cs[i].ok) n++
                        return n
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        C.IconTile { iconName: "verified"; size: 36; glyphSize: 18; tint: res.accent }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            C.AppText {
                                text: I18n.tr("The evidence")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Tokens.fontSubtitle
                                color: Theme.text_strong
                            }
                            C.AppText {
                                text: I18n.tr("{a} of {b} signals found").replace("{a}", evCol.foundCount)
                                                                       .replace("{b}", (res.r.checks || []).length)
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                            }
                        }
                        // a segment per signal, filled when found
                        Row {
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: res.r.checks || []
                                Rectangle {
                                    width: 22; height: 8; radius: 4
                                    color: modelData.kind === "note" ? U.withAlpha(Theme.outline, 0.35)
                                         : modelData.ok ? Theme.secondary_container
                                         : U.withAlpha(Theme.outline, 0.18)
                                }
                            }
                        }
                    }

                    GridLayout {
                        id: evGrid
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor(content.width / 360))
                        columnSpacing: Tokens.space3
                        rowSpacing: Tokens.space3
                        readonly property real cardW: (content.width - Tokens.space5 * 2 - columnSpacing * (columns - 1)) / columns

                        Repeater {
                            model: res.r.checks || []
                            Rectangle {
                                id: evCard
                                readonly property bool note: modelData.kind === "note"
                                readonly property color tint: note ? Theme.on_surface_var
                                                            : modelData.ok ? Theme.secondary_container
                                                            : Theme.outline
                                Layout.preferredWidth: evGrid.cardW
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignTop
                                implicitHeight: evCardCol.implicitHeight + Tokens.space4 * 2
                                radius: Tokens.radiusLg
                                color: modelData.ok ? U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.09 : 0.06)
                                     : evHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                     : Theme.surface_low
                                border.width: 1
                                border.color: modelData.ok ? U.withAlpha(Theme.secondary_container, 0.35) : Theme.border
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                HoverHandler { id: evHover }

                                ColumnLayout {
                                    id: evCardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.space4
                                    spacing: Tokens.space2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        Rectangle {
                                            width: 32; height: 32; radius: Tokens.radiusMd
                                            color: U.withAlpha(evCard.tint, 0.14)
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: page.sig(modelData.key).g
                                                fill: true
                                                size: 16
                                                glyphColor: evCard.tint
                                            }
                                        }
                                        C.AppText {
                                            text: page.sig(modelData.key).n
                                            weight: Tokens.weightBold
                                            color: Theme.text_strong
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Rectangle {
                                            radius: Tokens.radiusPill
                                            color: U.withAlpha(evCard.tint, 0.14)
                                            implicitWidth: evPillRow.implicitWidth + Tokens.space3
                                            implicitHeight: 22
                                            Row {
                                                id: evPillRow
                                                anchors.centerIn: parent
                                                spacing: 3
                                                C.IconGlyph {
                                                    name: evCard.note ? "info" : modelData.ok ? "check" : "close"
                                                    size: 11
                                                    glyphColor: evCard.tint
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: evCard.note ? I18n.tr("NOTE")
                                                          : modelData.ok ? I18n.tr("FOUND") : I18n.tr("NOT FOUND")
                                                    mono: true
                                                    weight: Tokens.weightExtraBold
                                                    font.pixelSize: 11
                                                    color: evCard.tint
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                    C.AppText {
                                        text: modelData.text
                                        font.pixelSize: Tokens.fontCaption
                                        color: modelData.ok ? Theme.on_surface : Theme.on_surface_var
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ══════════ the money ══════════
            C.GlassPanel {
                id: moneyPanel
                Layout.fillWidth: true
                radius_: Tokens.radiusXl
                elevation: 1.3
                implicitHeight: revCol.implicitHeight + Tokens.space6 * 2
                transform: Translate { id: mnShift; y: 0 }

                C.CornerGlow { radius: Tokens.radiusXl; size: 520 }

                ColumnLayout {
                    id: revCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space6
                    spacing: Tokens.space5

                    // header + horizon switch
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        C.IconTile { iconName: "monetization_on"; size: 40; glyphSize: 20; solid: true }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            C.AppText {
                                text: I18n.tr("Estimated ad revenue")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Tokens.fontSubtitle
                                color: Theme.text_strong
                            }
                            // The input the whole panel is computed from — named
                            // as an input, because a reader who does not know
                            // what went in cannot judge what came out.
                            C.AppText {
                                text: I18n.tr("modelled from ~{v} views / month").replace("{v}", res.r.views.monthly)
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                            }
                        }

                        Rectangle {
                            id: hzTrack
                            implicitWidth: hzRowOuter.implicitWidth + 8
                            implicitHeight: 38
                            radius: Tokens.radiusPill
                            color: Theme.input_bg
                            border.width: 1
                            border.color: Theme.border
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                readonly property Item target: hzRep.count > res.horizon ? hzRep.liveItemAt(res.horizon) : null
                                x: target ? hzRowOuter.x + target.x : 4
                                width: target ? target.width : 0
                                y: 4
                                height: parent.height - 8
                                radius: Tokens.radiusPill
                                color: Theme.primary
                                Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                            }
                            Row {
                                id: hzRowOuter
                                x: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater {
                                    id: hzRep
                                    // itemAt() is not a notifying lookup: a binding that ran before the
                                    // delegates existed got null and kept it (thumb missing on first show,
                                    // the active label invisible in light theme). `built` re-runs it.
                                    property int built: 0
                                    onItemAdded: built++
                                    onItemRemoved: built++
                                    function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                    model: [I18n.tr("Daily"), I18n.tr("Monthly"), I18n.tr("Yearly")]
                                    AbstractButton {
                                        id: hzBtn
                                        height: 30
                                        implicitWidth: hzLbl.implicitWidth + Tokens.space4 * 2
                                        readonly property bool on: res.horizon === index
                                        onClicked: res.horizon = index
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        background: Item {}
                                        contentItem: C.AppText {
                                            id: hzLbl
                                            text: modelData
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption
                                            color: hzBtn.on ? Theme.on_primary : Theme.on_surface_var
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // the headline range — "$644 - $10K a month" — counted up on arrival
                    C.EarningsRange {
                        Layout.fillWidth: true
                        visible: !!res.r.earnings
                        monthly: res.r.earnings ? res.r.earnings.monthly : ({})
                        yearly: res.r.earnings ? res.r.earnings.yearly : ({})
                        startDelay: 1100
                    }

                    // three tier cards — the middle one is the one to plan against
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        layoutDirection: Qt.LeftToRight

                        Repeater {
                            model: res.r.revenue
                            delegate: Rectangle {
                                id: tierCard
                                required property var modelData
                                required property int index
                                readonly property bool mid: modelData.isMid
                                readonly property string shown: res.horizon === 0 ? modelData.daily
                                                               : res.horizon === 2 ? modelData.yearly
                                                               : modelData.monthly
                                Layout.fillWidth: true
                                Layout.preferredWidth: mid ? 1.2 : 1
                                Layout.alignment: Qt.AlignBottom
                                implicitHeight: tierCol.implicitHeight + Tokens.space5 * 2 + (mid ? Tokens.space3 : 0)
                                radius: Tokens.radiusLg
                                color: mid ? U.withAlpha(Theme.primary, Theme.isDark ? 0.14 : 0.08)
                                     : tierHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                     : Theme.surface_low
                                border.width: 1
                                border.color: mid ? U.withAlpha(Theme.primary, 0.55)
                                            : tierHover.hovered ? U.withAlpha(Theme.primary, 0.30) : Theme.border
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                HoverHandler { id: tierHover }
                                transform: Translate {
                                    id: tierCardLift
                                    y: tierHover.hovered ? -3 : 0
                                    Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                }
                                // keep the hit box on the resting footprint too (see LiftMask.qml)
                                containmentMask: C.LiftMask { target: tierCard; dy: tierCardLift.y }

                                // the plan-with-this ribbon
                                Rectangle {
                                    visible: tierCard.mid
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: -11
                                    radius: Tokens.radiusPill
                                    color: Theme.primary
                                    implicitWidth: ribbonLbl.implicitWidth + Tokens.space4
                                    implicitHeight: 22
                                    C.AppText {
                                        id: ribbonLbl
                                        anchors.centerIn: parent
                                        text: I18n.tr("PLAN WITH THIS")
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: 11
                                        color: Theme.on_primary
                                    }
                                }

                                ColumnLayout {
                                    id: tierCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Tokens.space5
                                    spacing: Tokens.space2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        C.AppText {
                                            text: tierCard.modelData.label
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontLabel
                                            color: tierCard.mid ? Theme.primary : Theme.text_strong
                                            Layout.fillWidth: true
                                        }
                                        Rectangle {
                                            radius: Tokens.radiusPill
                                            color: U.withAlpha(Theme.on_surface, 0.07)
                                            implicitWidth: rpmLbl.implicitWidth + Tokens.space3
                                            implicitHeight: 22
                                            C.AppText {
                                                id: rpmLbl
                                                anchors.centerIn: parent
                                                text: tierCard.modelData.rpmText + " " + I18n.tr("RPM")
                                                mono: true
                                                weight: Tokens.weightDemiBold
                                                font.pixelSize: 11
                                                color: Theme.on_surface_var
                                            }
                                        }
                                    }
                                    C.AppText {
                                        id: tierBig
                                        text: tierCard.shown
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: tierCard.mid ? Tokens.fontDisplay + 10 : Tokens.fontDisplay
                                        color: tierCard.mid ? Theme.text_strong : Theme.on_surface
                                        LayoutMirroring.enabled: false
                                        // flip when the horizon changes
                                        onTextChanged: flip.restart()
                                        SequentialAnimation {
                                            id: flip
                                            NumberAnimation { target: tierBig; property: "opacity"; to: 0.2; duration: 80 }
                                            NumberAnimation { target: tierBig; property: "opacity"; to: 1.0; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    C.AppText {
                                        text: res.horizon === 0 ? I18n.tr("per day")
                                              : res.horizon === 2 ? I18n.tr("per year") : I18n.tr("per month")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                    }
                                    C.AppText {
                                        text: tierCard.modelData.note
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    // the range, as a track: conservative → likely → optimistic
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 14
                            LayoutMirroring.enabled: false
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.20) }
                                    GradientStop { position: 0.5; color: Theme.primary }
                                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.35) }
                                }
                            }
                            Rectangle {
                                x: parent.width / 2 - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14; radius: 7
                                color: Theme.panel_bg
                                border.width: 3
                                border.color: Theme.primary
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            layoutDirection: Qt.LeftToRight
                            C.AppText {
                                text: I18n.tr("range {r}").replace("{r}", res.r.headline.range) + "  ·  " + I18n.tr("per month")
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                Layout.fillWidth: true
                            }
                            C.AppText {
                                text: I18n.tr("{y} / year at the likely rate").replace("{y}", res.r.headline.yearly)
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.text_strong
                            }
                        }
                    }

                    // niche + rates + views — the inputs, as tiles
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        Repeater {
                            model: [
                                { ic: "target", l: I18n.tr("Niche"), v: I18n.tr(res.r.rpm.nicheLabel),
                                  s: (res.r.rpm.formatUsed === "short" ? I18n.tr("Shorts") : I18n.tr("Long-form"))
                                     + " · " + I18n.tr("Tier {n}").replace("{n}", res.r.rpm.tier) },
                                { ic: "money", l: I18n.tr("RPM / 1K views"), v: res.r.rpm.rpmLow + " – " + res.r.rpm.rpmHigh,
                                  s: I18n.tr("Shorts / long-form") },
                                { ic: "bar_chart", l: I18n.tr("CPM (advertiser)"), v: res.r.rpm.cpmLow + " – " + res.r.rpm.cpmHigh, s: "" },
                                { ic: "visibility", l: I18n.tr("Views modelled"),
                                  v: res.r.views.daily + " / " + I18n.tr("day"),
                                  s: res.r.views.yearly + " / " + I18n.tr("year") }
                            ]
                            Rectangle {
                                radius: Tokens.radiusLg
                                color: Theme.surface_low
                                border.width: 1
                                border.color: Theme.border
                                implicitWidth: Math.max(220, inTile.implicitWidth + Tokens.space4 * 2)
                                implicitHeight: inTile.implicitHeight + Tokens.space3 * 2
                                Row {
                                    id: inTile
                                    anchors.left: parent.left
                                    anchors.leftMargin: Tokens.space4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.space3
                                    C.IconGlyph {
                                        name: modelData.ic; size: 18
                                        glyphColor: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        spacing: 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        C.AppText {
                                            text: modelData.l
                                            font.pixelSize: 11
                                            color: Theme.on_surface_var
                                        }
                                        C.AppText {
                                            text: modelData.v
                                            weight: Tokens.weightExtraBold
                                            color: Theme.text_strong
                                        }
                                        C.AppText {
                                            visible: modelData.s !== ""
                                            text: modelData.s
                                            font.pixelSize: 11
                                            color: Theme.outline
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The standing caveat, in a bordered callout rather than as
                    // grey small print. Everything above it is modelled.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: caveatRow.implicitHeight + Tokens.space3 * 2
                        radius: Tokens.radiusMd
                        color: U.withAlpha(Theme.warn, 0.07)
                        border.width: 1
                        border.color: U.withAlpha(Theme.warn, 0.22)
                        RowLayout {
                            id: caveatRow
                            anchors.fill: parent
                            anchors.margins: Tokens.space3
                            spacing: Tokens.space2
                            C.IconGlyph {
                                name: "info"; size: 15; fill: true
                                glyphColor: Theme.warn
                                Layout.alignment: Qt.AlignTop
                            }
                            C.AppText {
                                text: I18n.tr("Estimates, not earnings. YouTube never publishes what a channel makes — these are modelled from the niche's RPM band, the audience market and public view velocity. Real figures also include memberships, Super Thanks and sponsorships, none of which are visible from outside.")
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
