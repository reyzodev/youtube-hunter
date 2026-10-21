import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Dialogs
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Scraper — v15 "Run console" (rebuilt from scratch).
//
//   ┌ Scraper ─────────────────────────────────────────── ● Engine ready ┐
//   ┌ composer ─────────────────────────────────┐ ┌ run card ───────────┐
//   │ 1 Source   big link slate · kind chip     │ │      ╭───────╮      │
//   │            optional "only matching" query │ │      │  200  │ gauge│
//   │ 2 Recipe   amount (type/drag/chips)       │ │      ╰───────╯      │
//   │            order ▾   format [All|Long|Sh] │ │ receipt: source ·   │
//   │ 3 Output   file name · save folder        │ │ amount · order · …  │
//   └───────────────────────────────────────────┘ │ [ Start scraping ]  │
//   transcript banner · live log                  └─────────────────────┘
//
// The signature is the gauge: while you set the recipe it previews the SIZE
// of the run (log scale, 50 → a sliver, 5 000 → a full ring), and the moment
// the run starts the same ring becomes the progress meter. The launch button
// only lights once the run is actually launchable, and the card says what is
// missing instead of letting the VM throw a popup.
//
// VM contract is unchanged: Dashboard.startScraping(url, query, max, sortIndex,
// formatIndex), stopScraping(), setSaveFolder(), filename, saveFolder, the
// transcript-pause slots and the logLine / logCleared signals.
//
// NOTE: the VM always needs a channel / video link (an empty link is rejected
// with "Please enter a YouTube Channel URL"), so the query is presented as
// what it really is — a filter inside that channel — not as a global search.
// The previous page lives in _backup_v14/DashboardPage.qml.
Item {
    id: page

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    // 0 all · 1 long-form · 2 shorts (DashboardVM format_index)
    property int _fmt: 0
    readonly property int _amount: Math.round(maxSlider.value)
    readonly property string _src: (urlField.text || "").trim()
    readonly property string _query: (queryField.text || "").trim()
    readonly property string _srcKind: {
        const u = page._src.toLowerCase()
        if (u === "") return "none"
        if (u.indexOf("watch?v=") !== -1 || u.indexOf("youtu.be/") !== -1 || u.indexOf("/shorts/") !== -1)
            return "video"
        return "channel"
    }
    readonly property color _kindTint: page._srcKind === "video" ? Theme.tertiary : Theme.secondary_container
    readonly property bool _hasFolder: (Dashboard.saveFolder || "") !== ""
    readonly property bool _ready: page._src !== "" && page._hasFolder
    readonly property bool _wide: content.width >= 1080
    readonly property var _fmtLabels: [I18n.tr("All formats"), I18n.tr("Long-form"), I18n.tr("Shorts")]

    // A short, human name for whatever the link points at (receipt line).
    readonly property string _srcName: {
        const u = page._src
        if (u === "") return "—"
        var m = u.match(/@([A-Za-z0-9._\-]+)/)
        if (m) return "@" + m[1]
        m = u.match(/[?&]v=([A-Za-z0-9_\-]{6,})/) || u.match(/youtu\.be\/([A-Za-z0-9_\-]{6,})/)
            || u.match(/shorts\/([A-Za-z0-9_\-]{6,})/)
        if (m) return m[1]
        m = u.match(/channel\/(UC[A-Za-z0-9_\-]+)/)
        if (m) return m[1]
        return u.replace(/^https?:\/\/(www\.)?/, "")
    }
    // Last folder segment, for the receipt ("…/Exports" reads better than a
    // full Windows path in a 300px card).
    readonly property string _folderName: {
        const f = (Dashboard.saveFolder || "").replace(/[\\\/]+$/, "")
        if (f === "") return ""
        const parts = f.split(/[\\\/]/)
        return parts[parts.length - 1] || f
    }

    function _start() {
        if (Dashboard.isRunning || !page._ready) return
        Dashboard.startScraping(page._src, page._query, page._amount,
                                sortCombo.currentIndex, page._fmt)
    }

    FolderDialog {
        id: folderDialog
        onAccepted: Dashboard.setSaveFolder(selectedFolder.toString())
    }

    // Step header: a numbered badge (the three steps ARE an order), a title,
    // and an optional muted note on the far edge.
    component StepHead: RowLayout {
        id: sh
        property int n: 1
        property string title: ""
        property string note: ""
        property bool done: false
        spacing: Tokens.space3
        Layout.fillWidth: true
        Rectangle {
            width: 26; height: 26; radius: 13
            color: sh.done ? Theme.primary : U.withAlpha(Theme.primary, 0.10)
            border.width: 1
            border.color: sh.done ? Theme.primary : U.withAlpha(Theme.primary, 0.32)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            C.AppText {
                anchors.centerIn: parent
                visible: !sh.done
                text: sh.n
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontCaption
                color: Theme.primary
            }
            C.IconGlyph {
                anchors.centerIn: parent
                visible: sh.done
                name: "check"
                size: 14
                glyphColor: Theme.on_primary
            }
        }
        C.AppText {
            text: sh.title
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontSubtitle
            color: Theme.text_strong
        }
        Item { Layout.fillWidth: true }
        C.AppText {
            visible: sh.note !== ""
            text: sh.note
            font.pixelSize: Tokens.fontCaption
            color: Theme.outline
            elide: Text.ElideRight
            Layout.maximumWidth: 320
        }
    }

    // Small field label inside a step.
    component FieldLabel: C.AppText {
        weight: Tokens.weightDemiBold
        font.pixelSize: Tokens.fontCaption
        color: Theme.on_surface_var
    }

    // One line of the run receipt.
    component ReceiptRow: RowLayout {
        id: rr
        property string icon: ""
        property string label: ""
        property string value: ""
        property color valueColor: Theme.text_strong
        property bool monoValue: false
        Layout.fillWidth: true
        spacing: Tokens.space2
        C.IconGlyph {
            name: rr.icon
            size: 15
            glyphColor: Theme.outline
            Layout.alignment: Qt.AlignVCenter
        }
        C.AppText {
            text: rr.label
            font.pixelSize: Tokens.fontCaption
            color: Theme.on_surface_var
            Layout.alignment: Qt.AlignVCenter
        }
        Item { Layout.fillWidth: true; Layout.minimumWidth: Tokens.space2 }
        C.AppText {
            text: rr.value
            mono: rr.monoValue
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontCaption + 1
            color: rr.valueColor
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignRight
            Layout.maximumWidth: 190
            Layout.alignment: Qt.AlignVCenter
        }
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

                // ── header ──
                C.PageHeader {
                    iconName: "cloud_download"
                    title: I18n.tr("Scraper")
                    subtitle: I18n.tr("Turn a channel into one clean, sortable sheet.")

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        radius: Tokens.radiusPill
                        implicitHeight: 34
                        implicitWidth: engRow.implicitWidth + Tokens.space4 * 2
                        color: Dashboard.isRunning ? U.withAlpha(Theme.primary, 0.12) : Theme.surface
                        border.width: 1
                        border.color: Dashboard.isRunning ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        Row {
                            id: engRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            Item {
                                width: 8; height: 8
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    id: engHalo
                                    anchors.centerIn: parent
                                    width: 8; height: 8; radius: 4
                                    color: Dashboard.isRunning ? Theme.primary : Theme.secondary_container
                                    opacity: 0
                                }
                                ParallelAnimation {
                                    running: page._motion && page.visible && Dashboard.isRunning
                                    loops: Animation.Infinite
                                    NumberAnimation { target: engHalo; property: "scale"; from: 1; to: 2.8; duration: 1400; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: engHalo; property: "opacity"; from: 0.55; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8; height: 8; radius: 4
                                    color: Dashboard.isRunning ? Theme.primary : Theme.secondary_container
                                }
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Dashboard.isRunning
                                      ? I18n.tr("Scraping · {p}%").replace("{p}", Dashboard.progress)
                                      : I18n.tr("Engine ready")
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontCaption
                                color: Dashboard.isRunning ? Theme.primary : Theme.on_surface_var
                            }
                        }
                    }
                }

                GridLayout {
                    id: body
                    Layout.fillWidth: true
                    columns: page._wide ? 2 : 1
                    columnSpacing: Tokens.space5
                    rowSpacing: Tokens.space5

                    // ═════════════ composer ═════════════
                    C.GlassPanel {
                        id: composer
                        objectName: "tour_scrapeForm"
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        radius: Tokens.radiusXl
                        implicitHeight: compCol.implicitHeight + Tokens.space6 * 2

                        ColumnLayout {
                            id: compCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space6
                            spacing: Tokens.space6

                            // ─── 1 · Source ───
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3

                                StepHead {
                                    n: 1
                                    title: I18n.tr("Source")
                                    done: page._src !== ""
                                    note: I18n.tr("Channel, @handle, /channel/UC… or one video")
                                }

                                // the link slate — biggest thing on the page
                                Item {
                                    id: slateBox
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    readonly property bool lit: page._src !== ""

                                    Rectangle {
                                        anchors.fill: slate
                                        anchors.margins: -5
                                        radius: slate.radius + 5
                                        color: "transparent"
                                        border.width: 5
                                        border.color: U.withAlpha(Theme.primary, slateBox.lit ? 0.16 : 0.08)
                                        opacity: urlField.activeFocus || slateBox.lit ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                    }
                                    Rectangle {
                                        id: slate
                                        anchors.fill: parent
                                        radius: Tokens.radiusXl
                                        color: Theme.input_bg
                                        border.width: 1
                                        border.color: slateBox.lit ? U.withAlpha(Theme.primary, 0.70)
                                                    : urlField.activeFocus ? Theme.border_strong
                                                    : slateHover.hovered ? Theme.border_med
                                                    : Theme.border
                                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        HoverHandler { id: slateHover }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Tokens.space2
                                            anchors.rightMargin: Tokens.space2
                                            spacing: Tokens.space2

                                            Item {
                                                Layout.preferredWidth: 44
                                                Layout.fillHeight: true
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    name: page._srcKind === "video" ? "smart_display"
                                                        : page._srcKind === "channel" ? "youtube" : "link"
                                                    fill: page._srcKind !== "none"
                                                    size: 22
                                                    glyphColor: page._srcKind !== "none" ? Theme.primary
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
                                                Layout.fillHeight: true
                                                enabled: !Dashboard.isRunning
                                                placeholderText: "youtube.com/@channel"
                                                placeholderTextColor: Theme.outline
                                                color: Theme.text_strong
                                                font.family: Fonts.familyFor("body", Tokens.weightMedium, text)
                                                font.weight: Fonts.weightFor(Tokens.weightMedium, text)
                                                font.pixelSize: 19
                                                selectByMouse: true
                                                verticalAlignment: TextInput.AlignVCenter
                                                leftPadding: 0; rightPadding: 0
                                                background: null
                                                onAccepted: page._start()
                                                HoverHandler { cursorShape: Qt.IBeamCursor }
                                            }
                                            // what the link points at, read back live
                                            Rectangle {
                                                visible: page._srcKind !== "none"
                                                Layout.alignment: Qt.AlignVCenter
                                                radius: Tokens.radiusPill
                                                color: U.withAlpha(page._kindTint, 0.12)
                                                border.width: 1
                                                border.color: U.withAlpha(page._kindTint, 0.40)
                                                implicitWidth: kindRow.implicitWidth + Tokens.space3 * 2
                                                implicitHeight: 30
                                                Row {
                                                    id: kindRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space1 + 2
                                                    C.IconGlyph {
                                                        name: page._srcKind === "video" ? "smart_display" : "user"
                                                        size: 13; fill: true
                                                        glyphColor: page._kindTint
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: page._srcKind === "video" ? I18n.tr("Single video") : I18n.tr("Channel")
                                                        weight: Tokens.weightBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: page._kindTint
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                            C.IconButton {
                                                visible: urlField.text !== "" && !Dashboard.isRunning
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
                                                enabled: !Dashboard.isRunning
                                                implicitHeight: 48
                                                Layout.alignment: Qt.AlignVCenter
                                                onClicked: { urlField.forceActiveFocus(); urlField.paste() }
                                            }
                                        }
                                    }
                                }

                                // filter inside the channel (optional)
                                Rectangle {
                                    id: queryWell
                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    radius: Tokens.radiusLg
                                    color: queryField.activeFocus || page._query !== "" ? Theme.input_bg : U.withAlpha(Theme.input_bg, 0)
                                    border.width: 1
                                    border.color: queryField.activeFocus ? U.withAlpha(Theme.primary, 0.60)
                                                : page._query !== "" ? Theme.border_med
                                                : U.mix(Theme.border, Theme.outline, 0.20)
                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Tokens.space4
                                        anchors.rightMargin: Tokens.space2
                                        spacing: Tokens.space3
                                        C.IconGlyph {
                                            name: "filter_alt"
                                            size: 17
                                            glyphColor: queryField.activeFocus || page._query !== "" ? Theme.primary : Theme.outline
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        TextField {
                                            id: queryField
                                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                            T.ContextMenu.menu: C.EditMenu { editor: queryField }
                                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                            selectedTextColor: Theme.text_strong
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            enabled: !Dashboard.isRunning
                                            placeholderText: I18n.tr("Only videos matching… (optional)")
                                            placeholderTextColor: Theme.outline
                                            color: Theme.text_strong
                                            font.family: Fonts.body
                                            font.pixelSize: Tokens.fontLabel
                                            selectByMouse: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            leftPadding: 0; rightPadding: 0
                                            background: null
                                            onAccepted: page._start()
                                            HoverHandler { cursorShape: Qt.IBeamCursor }
                                        }
                                        // the cost of a filtered run, said up front
                                        Rectangle {
                                            visible: page._query !== ""
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: Tokens.radiusPill
                                            color: U.withAlpha(Theme.warn, 0.12)
                                            border.width: 1
                                            border.color: U.withAlpha(Theme.warn, 0.40)
                                            implicitWidth: costRow.implicitWidth + Tokens.space3 * 2
                                            implicitHeight: 28
                                            Row {
                                                id: costRow
                                                anchors.centerIn: parent
                                                spacing: Tokens.space1 + 2
                                                C.IconGlyph {
                                                    name: "bolt"; fill: true; size: 12
                                                    glyphColor: Theme.warn
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: I18n.tr("100 units / 50 results")
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.warn
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                        C.IconButton {
                                            visible: queryField.text !== "" && !Dashboard.isRunning
                                            implicitWidth: 34; implicitHeight: 34
                                            Layout.alignment: Qt.AlignVCenter
                                            iconName: "close"
                                            glyphSize: 15
                                            tip: I18n.tr("Clear")
                                            onClicked: queryField.text = ""
                                        }
                                    }
                                }
                            }

                            // ─── 2 · Recipe ───
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3

                                StepHead {
                                    n: 2
                                    title: I18n.tr("Recipe")
                                    done: page._src !== ""
                                    note: I18n.tr("How many, which first, which format")
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: compCol.width >= 720 ? 2 : 1
                                    columnSpacing: Tokens.space6
                                    rowSpacing: Tokens.space5

                                    // amount
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        spacing: Tokens.space2

                                        FieldLabel { text: I18n.tr("Max Videos to Scrape") }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2
                                            // EDITABLE readout: at 5000 one slider
                                            // pixel is ~7 videos, so typing is the
                                            // only way to an exact number.
                                            TextField {
                                                id: maxField
                                                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                                T.ContextMenu.menu: C.EditMenu { editor: maxField }
                                                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                                selectedTextColor: Theme.text_strong
                                                Layout.preferredWidth: 140
                                                implicitHeight: 54
                                                enabled: !Dashboard.isRunning
                                                text: Math.round(maxSlider.value)
                                                horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                                verticalAlignment: TextInput.AlignVCenter
                                                color: Theme.text_strong
                                                font.family: Fonts.familyFor("body", Tokens.weightExtraBold, text)
                                                font.weight: Fonts.weightFor(Tokens.weightExtraBold, text)
                                                font.pixelSize: 42
                                                selectByMouse: true
                                                leftPadding: 0; rightPadding: 0
                                                validator: IntValidator { bottom: 0; top: 5000 }
                                                inputMethodHints: Qt.ImhDigitsOnly
                                                background: Rectangle {
                                                    color: "transparent"
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: maxField.activeFocus ? 2 : 1
                                                        color: maxField.activeFocus ? Theme.primary : U.withAlpha(Theme.primary, 0.25)
                                                    }
                                                }
                                                // commit on Enter / focus-out, not per keystroke
                                                onEditingFinished: {
                                                    var n = parseInt(text, 10)
                                                    if (isNaN(n)) n = Math.round(maxSlider.value)
                                                    maxSlider.value = Math.max(0, Math.min(5000, n))
                                                    text = Math.round(maxSlider.value)
                                                }
                                                LayoutMirroring.enabled: false
                                            }
                                            C.AppText {
                                                text: I18n.tr("videos")
                                                color: Theme.on_surface_var
                                                font.pixelSize: Tokens.fontLabel
                                                Layout.alignment: Qt.AlignBottom
                                                Layout.bottomMargin: Tokens.space2
                                            }
                                            Item { Layout.fillWidth: true }
                                        }

                                        Slider {
                                            id: maxSlider
                                            Layout.fillWidth: true
                                            enabled: !Dashboard.isRunning
                                            from: 0; to: 5000; value: 50; stepSize: 1
                                            snapMode: Slider.SnapAlways
                                            live: true
                                            onValueChanged: if (!maxField.activeFocus)
                                                maxField.text = Math.round(value)
                                            background: Rectangle {
                                                x: maxSlider.leftPadding
                                                y: maxSlider.topPadding + maxSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200
                                                implicitHeight: 6
                                                width: maxSlider.availableWidth; height: 6; radius: 3
                                                color: Theme.surface_high
                                                Rectangle {
                                                    width: maxSlider.visualPosition === 0 ? 0 : maxSlider.position * parent.width
                                                    height: parent.height; radius: 3
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: Theme.primary_deep }
                                                        GradientStop { position: 1.0; color: Theme.primary }
                                                    }
                                                }
                                            }
                                            handle: Rectangle {
                                                x: maxSlider.leftPadding + maxSlider.visualPosition * (maxSlider.availableWidth - width)
                                                y: maxSlider.topPadding + maxSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 20
                                                implicitHeight: 20
                                                width: 20; height: 20; radius: 10
                                                color: Theme.slider_handle
                                                border.width: 3; border.color: Theme.primary
                                                scale: maxSlider.pressed ? 1.15 : sliderHover.hovered ? 1.08 : 1.0
                                                Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                                            }
                                            HoverHandler { id: sliderHover; cursorShape: Qt.PointingHandCursor }
                                        }

                                        // the five numbers people actually pick
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space1 + 2
                                            Repeater {
                                                model: [ { t: "50", v: 50 }, { t: "200", v: 200 }, { t: "500", v: 500 },
                                                         { t: "1K", v: 1000 }, { t: "5K", v: 5000 } ]
                                                AbstractButton {
                                                    id: amtChip
                                                    readonly property bool on: page._amount === modelData.v
                                                    height: 30
                                                    implicitWidth: Math.max(48, amtLbl.implicitWidth + Tokens.space3 * 2)
                                                    enabled: !Dashboard.isRunning
                                                    hoverEnabled: true
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    onClicked: { maxSlider.value = modelData.v; maxField.text = modelData.v }
                                                    background: Rectangle {
                                                        radius: Tokens.radiusPill
                                                        color: amtChip.on ? Theme.primary
                                                             : amtChip.hovered ? U.mix(Theme.surface_low, Theme.primary, 0.10)
                                                             : Theme.surface_low
                                                        border.width: 1
                                                        border.color: amtChip.on ? Theme.primary : Theme.border
                                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                    }
                                                    contentItem: C.AppText {
                                                        id: amtLbl
                                                        text: modelData.t
                                                        mono: true
                                                        weight: Tokens.weightBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: amtChip.on ? Theme.on_primary : Theme.on_surface
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // order + format
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        spacing: Tokens.space2

                                        FieldLabel { text: I18n.tr("Order") }
                                        C.Dropdown {
                                            id: sortCombo
                                            Layout.fillWidth: true
                                            enabled: !Dashboard.isRunning
                                            borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                            model: Dashboard.sortOptions
                                        }

                                        FieldLabel {
                                            text: I18n.tr("Format")
                                            Layout.topMargin: Tokens.space3
                                        }
                                        C.SlideSegment {
                                            id: fmtSeg
                                            Layout.fillWidth: true
                                            equal: true
                                            cellHeight: 38
                                            enabledCells: !Dashboard.isRunning
                                            model: [
                                                { label: I18n.tr("All formats"), icon: "fmt_all" },
                                                { label: I18n.tr("Long-form"),   icon: "fmt_long" },
                                                { label: I18n.tr("Shorts"),      icon: "fmt_short" }
                                            ]
                                            currentIndex: page._fmt
                                            onActivated: (i) => page._fmt = i
                                        }
                                        C.AppText {
                                            text: page._fmt === 0
                                                  ? I18n.tr("Decides which videos make the cut when the channel has more than your maximum — and the row order in the export.")
                                                  : I18n.tr("The maximum counts matching videos only — the scraper keeps reading until it has that many.")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.outline
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            Layout.topMargin: Tokens.space1
                                        }
                                    }
                                }
                            }

                            // ─── 3 · Output ───
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3

                                StepHead {
                                    n: 3
                                    title: I18n.tr("Output")
                                    done: page._hasFolder
                                    note: (Dashboard.exportFormat || "") !== ""
                                          ? I18n.tr("Saved as .{f}").replace("{f}", String(Dashboard.exportFormat).toLowerCase())
                                          : ""
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: compCol.width >= 720 ? 2 : 1
                                    columnSpacing: Tokens.space6
                                    rowSpacing: Tokens.space3

                                    C.LineField {
                                        id: filenameField
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        label: I18n.tr("Custom Filename")
                                        labelIcon: "description"
                                        placeholder: "youtube_data"
                                        hint: I18n.tr("Sort order and a timestamp are appended, so runs never overwrite each other.")
                                        text: Dashboard.filename
                                        onTextChanged: Dashboard.filename = text
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        spacing: Tokens.space2
                                        RowLayout {
                                            spacing: Tokens.space2
                                            C.IconGlyph { name: "folder"; size: 14; glyphColor: Theme.on_surface_var }
                                            FieldLabel { text: I18n.tr("Save Location") }
                                        }
                                        // the folder is a button, not a read-only text box
                                        AbstractButton {
                                            id: folderBtn
                                            Layout.fillWidth: true
                                            implicitHeight: Tokens.fieldHeight + 4
                                            hoverEnabled: true
                                            enabled: !Dashboard.isRunning
                                            onClicked: folderDialog.open()
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            background: Rectangle {
                                                radius: Tokens.radiusMd
                                                color: page._hasFolder ? Theme.input_bg
                                                     : U.withAlpha(Theme.warn, folderBtn.hovered ? 0.12 : 0.07)
                                                border.width: 1
                                                border.color: !page._hasFolder ? U.withAlpha(Theme.warn, 0.55)
                                                            : folderBtn.hovered ? Theme.border_med : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: RowLayout {
                                                spacing: Tokens.space3
                                                C.IconGlyph {
                                                    Layout.leftMargin: Tokens.space3
                                                    name: page._hasFolder ? "folder_open" : "warning"
                                                    fill: true
                                                    size: 17
                                                    glyphColor: page._hasFolder ? Theme.primary : Theme.warn
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: page._hasFolder ? Dashboard.saveFolder : I18n.tr("Choose where the sheet lands")
                                                    weight: page._hasFolder ? Tokens.weightMedium : Tokens.weightDemiBold
                                                    color: page._hasFolder ? Theme.text_strong : Theme.warn
                                                    elide: Text.ElideMiddle
                                                }
                                                C.AppText {
                                                    Layout.rightMargin: Tokens.space3
                                                    text: page._hasFolder ? I18n.tr("Change") : I18n.tr("Browse")
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.primary
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═════════════ run card ═════════════
                    C.GlassPanel {
                        id: runCard
                        Layout.fillWidth: !page._wide
                        Layout.preferredWidth: page._wide ? 360 : -1
                        Layout.alignment: Qt.AlignTop
                        radius: Tokens.radiusXl
                        elevation: 1.0
                        implicitHeight: runCol.implicitHeight + Tokens.space5 * 2

                        C.CornerGlow { radius: Tokens.radiusXl; size: 440 }

                        ColumnLayout {
                            id: runCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space5
                            spacing: Tokens.space4

                            C.AppText {
                                text: Dashboard.isRunning ? I18n.tr("Scraping now") : I18n.tr("Run sheet")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                font.capitalization: I18n.rtl ? Font.MixedCase : Font.AllUppercase
                                color: Dashboard.isRunning ? Theme.primary : Theme.on_surface_var
                            }

                            // ── the gauge: run size → run progress ──
                            Item {
                                id: gauge
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 188
                                implicitHeight: 188
                                readonly property real thickness: 12
                                readonly property real r: (width - thickness) / 2 - 2
                                // idle: amount on a log scale (50 → sliver, 5 000 → full)
                                readonly property real sizeFrac: page._amount <= 0 ? 0
                                    : Math.max(0.04, Math.min(1, Math.log(page._amount) / Math.log(5000)))
                                readonly property real target: Dashboard.isRunning
                                    ? Math.max(0, Math.min(1, Dashboard.progress / 100)) : sizeFrac
                                property real shown: target
                                Behavior on shown { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

                                C.GlowBlob {
                                    anchors.centerIn: parent
                                    size: 230
                                    glow: Theme.primary
                                    strength: Dashboard.isRunning ? 0.30 : 0.14
                                    Behavior on strength { NumberAnimation { duration: Tokens.durSlow } }
                                }

                                Shape {
                                    anchors.fill: parent
                                    antialiasing: true
                                    layer.enabled: true
                                    layer.samples: 4
                                    ShapePath {
                                        strokeColor: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.07)
                                        strokeWidth: gauge.thickness
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        PathAngleArc {
                                            centerX: gauge.width / 2; centerY: gauge.height / 2
                                            radiusX: gauge.r; radiusY: gauge.r
                                            startAngle: 0; sweepAngle: 360
                                        }
                                    }
                                    ShapePath {
                                        strokeColor: Dashboard.isRunning ? Theme.primary
                                                     : U.withAlpha(Theme.primary, page._ready ? 0.95 : 0.55)
                                        strokeWidth: gauge.thickness
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        PathAngleArc {
                                            centerX: gauge.width / 2; centerY: gauge.height / 2
                                            radiusX: gauge.r; radiusY: gauge.r
                                            startAngle: -90
                                            sweepAngle: 360 * Math.max(0.001, gauge.shown)
                                        }
                                    }
                                }

                                // a slow tick orbiting while it works
                                Item {
                                    anchors.fill: parent
                                    visible: Dashboard.isRunning
                                    RotationAnimation on rotation {
                                        running: Dashboard.isRunning && page.visible && page._motion
                                        loops: Animation.Infinite
                                        from: 0; to: 360
                                        duration: 2600
                                    }
                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        color: Theme.primary
                                        x: parent.width / 2 - 3
                                        y: gauge.thickness / 2 + 2 + gauge.thickness + 4 - 3
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    C.AppText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Dashboard.isRunning ? Dashboard.progress + "%"
                                                                  : Number(page._amount).toLocaleString(Qt.locale("en_US"), "f", 0)
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: 40
                                        color: Theme.text_strong
                                        LayoutMirroring.enabled: false
                                    }
                                    C.AppText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Dashboard.isRunning ? I18n.tr("scraped") : I18n.tr("videos per run")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                    }
                                }
                            }

                            // ── receipt: the recipe read back ──
                            Rectangle {
                                Layout.fillWidth: true
                                radius: Tokens.radiusLg
                                color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.6 : 0.8)
                                border.width: 1
                                border.color: Theme.border
                                implicitHeight: rcCol.implicitHeight + Tokens.space3 * 2
                                ColumnLayout {
                                    id: rcCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.space3
                                    anchors.leftMargin: Tokens.space4
                                    anchors.rightMargin: Tokens.space4
                                    spacing: Tokens.space2 + 2
                                    ReceiptRow {
                                        icon: page._srcKind === "video" ? "smart_display" : "user"
                                        label: page._srcKind === "video" ? I18n.tr("Video") : I18n.tr("Channel")
                                        value: page._srcName
                                        valueColor: page._src === "" ? Theme.outline : Theme.text_strong
                                    }
                                    ReceiptRow {
                                        visible: page._query !== ""
                                        icon: "filter_alt"
                                        label: I18n.tr("Matching")
                                        value: "“" + page._query + "”"
                                    }
                                    ReceiptRow {
                                        icon: "sort"
                                        label: I18n.tr("Order")
                                        value: sortCombo.currentText || "—"
                                    }
                                    ReceiptRow {
                                        icon: "movie"
                                        label: I18n.tr("Format")
                                        value: page._fmtLabels[page._fmt] || ""
                                    }
                                    ReceiptRow {
                                        icon: "folder"
                                        label: I18n.tr("Saves to")
                                        value: page._hasFolder ? page._folderName : I18n.tr("not set")
                                        valueColor: page._hasFolder ? Theme.text_strong : Theme.warn
                                    }
                                }
                            }

                            // ── what is still missing (instead of a popup later) ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !Dashboard.isRunning && !page._ready
                                spacing: Tokens.space1 + 2
                                Repeater {
                                    model: {
                                        var out = []
                                        if (page._src === "") out.push(I18n.tr("Add a channel or video link"))
                                        if (!page._hasFolder) out.push(I18n.tr("Pick a save folder"))
                                        return out
                                    }
                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: Theme.warn
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        C.AppText {
                                            text: modelData
                                            font.pixelSize: Tokens.fontCaption
                                            weight: Tokens.weightDemiBold
                                            color: Theme.warn
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            C.PrimaryButton {
                                Layout.fillWidth: true
                                implicitHeight: 54
                                enabled: Dashboard.isRunning || page._ready
                                text: Dashboard.isRunning ? I18n.tr("Stop scraping") : I18n.tr("Start scraping")
                                iconName: Dashboard.isRunning ? "stop_circle" : "bolt"
                                variant: Dashboard.isRunning ? "danger" : "primary"
                                onClicked: Dashboard.isRunning ? Dashboard.stopScraping() : page._start()
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: Theme[Dashboard.statusColorKey] || Theme.outline
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                C.AppText {
                                    text: Dashboard.statusText
                                    mono: true
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme[Dashboard.statusColorKey] || Theme.outline
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                C.AppText {
                                    visible: !Dashboard.isRunning && page._ready
                                    text: "Enter ↵"
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }
                }

                // ── transcript pause banner ─────────────────────────────
                // The scrape stops ASKING YouTube for transcripts the moment
                // YouTube blocks the IP, and waits here: the user either skips
                // the rest or switches their VPN node and confirms. Showing the
                // two cases apart matters — "this video has no captions" is
                // final, a blocked IP is one click away from fixed, and the
                // old behaviour could not tell them apart.
                Rectangle {
                    Layout.fillWidth: true
                    visible: Dashboard.transcriptPaused && Dashboard.isRunning
                    radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.10)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.45)
                    implicitHeight: trPauseCol.implicitHeight + Tokens.space3 * 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.space3
                        spacing: Tokens.space3
                        C.IconGlyph {
                            name: "warning"
                            size: 20
                            glyphColor: Theme.error
                            Layout.alignment: Qt.AlignTop
                        }
                        ColumnLayout {
                            id: trPauseCol
                            Layout.fillWidth: true
                            spacing: Tokens.space2

                            C.AppText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption + 1
                                color: Theme.text_strong
                                text: I18n.tr("Transcripts paused — YouTube has stopped answering for this IP.")
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                text: I18n.tr("So far: {f} with transcripts · {b} blocked · {n} without any")
                                          .replace("{f}", Dashboard.transcriptFound)
                                          .replace("{b}", Dashboard.transcriptBlocked)
                                          .replace("{n}", Dashboard.transcriptNone)
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                visible: Dashboard.transcriptIpNote !== ""
                                wrapMode: Text.Wrap
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.warn
                                text: Dashboard.transcriptIpNote
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                C.PrimaryButton {
                                    variant: "ghost"
                                    text: I18n.tr("Skip transcripts")
                                    onClicked: Dashboard.transcriptSkipRest()
                                }
                                C.PrimaryButton {
                                    variant: "primary"
                                    enabled: !Dashboard.transcriptChecking
                                    text: Dashboard.transcriptChecking
                                          ? I18n.tr("Checking IP…")
                                          : I18n.tr("New IP — re-check")
                                    onClicked: Dashboard.transcriptRetryIp()
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                // ── live progress + log (only while running or after a run) ──
                // Same TerminalPanel the Live Logs page uses, so there is one
                // implementation of the log view rather than two that drift.
                C.TerminalPanel {
                    id: term
                    Layout.fillWidth: true
                    Layout.preferredHeight: 400
                    visible: Dashboard.isRunning || term.hasLines
                    showProgress: true
                    progress: Dashboard.progress
                    running: Dashboard.isRunning
                    // v16: the % lives on the progress line now
                    hostLabel: "core-engine · /scrape/live"
                    onCopyRequested: (text) => Dashboard.copyLog(text)
                    onClearRequested: Dashboard.clearLog()
                }
            }
        }
    }

    Connections {
        target: Dashboard
        function onLogLine(line) { term.appendLine(line) }
        function onLogCleared() { term.clear() }
    }
}
