import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import NicheScope
import "../components" as C
import "../Utils.js" as U

// History — past extraction exports saved in the output folder.
//
// v8 "Timeline": the flat list of identical rows became a dated timeline.
// Exports are grouped under Today / Yesterday / the date, a rail with a dot per
// file runs down the reading edge, and each file carries a coloured format
// badge (CSV / XLSX / JSON …) instead of the same generic page glyph — so the
// question you actually come here with ("the one from Tuesday, the Excel one")
// is answered by scanning, not reading. Driven by HistoryVM; the VM is untouched.
Item {
    id: page
    // converted once per change (see the timeline Repeater)
    readonly property var _entries: History.entries

    onVisibleChanged: if (visible) History.reloadFolder()
    Component.onCompleted: History.reloadFolder()

    readonly property string _today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property string _yesterday: Qt.formatDate(new Date(Date.now() - 86400000), "yyyy-MM-dd")
    readonly property bool _wide: content.width > 760

    function dayOf(saved) { return String(saved || "").slice(0, 10) }
    function dayLabel(day) {
        if (day === page._today) return I18n.tr("Today")
        if (day === page._yesterday) return I18n.tr("Yesterday")
        return day
    }
    Connections {
        target: History
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    ScrollView {
        id: scroller
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        // Smooth wheel scrolling — same as the other list pages.
        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (ev) => {
                const fl = scroller.contentItem
                if (!fl) return
                const max = Math.max(0, fl.contentHeight - fl.height)
                const dir = ev.angleDelta.y > 0 ? -1 : 1
                const base = hWheelAnim.running ? page._wheelTarget : fl.contentY
                page._wheelTarget = Math.max(0, Math.min(max, base + dir * 120))
                hWheelAnim.stop(); hWheelAnim.from = fl.contentY
                hWheelAnim.to = page._wheelTarget; hWheelAnim.start()
            }
        }

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
                y: Tokens.space7
                spacing: Tokens.space5

                // ── header: statement + stat ribbon ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space5

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space1
                        C.AppText {
                            text: I18n.tr("History")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Math.round(Math.max(28, Math.min(40, content.width / 38)))
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: I18n.tr("Review or open past extraction exports.")
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }

                    // stat ribbon — files · rows · latest
                    Rectangle {
                        visible: History.hasAny
                        radius: Tokens.radiusLg
                        color: Theme.panel_bg
                        border.width: 1
                        border.color: Theme.border
                        implicitWidth: statRow.implicitWidth + Tokens.space2 * 2
                        implicitHeight: 64
                        Layout.alignment: Qt.AlignVCenter
                        Row {
                            id: statRow
                            anchors.centerIn: parent
                            spacing: 0
                            StatCell { glyph: "data"; value: History.statFiles; label: I18n.tr("files") }
                            Rectangle { width: 1; height: 32; color: Theme.border; anchors.verticalCenter: parent.verticalCenter }
                            StatCell { glyph: "view_list"; value: History.statRows; label: I18n.tr("rows") }
                            Rectangle { width: 1; height: 32; color: Theme.border; anchors.verticalCenter: parent.verticalCenter; visible: latestCell.visible }
                            StatCell {
                                id: latestCell
                                visible: page._wide && History.entries.length > 0
                                glyph: "history"
                                value: History.entries.length > 0
                                       ? page.dayLabel(page.dayOf(History.entries[0].saved)) : "—"
                                label: I18n.tr("Latest export")
                            }
                        }
                    }

                    C.PrimaryButton {
                        variant: "danger"
                        iconName: "delete_sweep"
                        text: I18n.tr("Delete all")
                        visible: History.hasAny
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: confirmClear.open()
                    }
                }

                // ── toolbar: segmented filter + search ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3

                    // segmented status filter
                    Rectangle {
                        height: 42
                        radius: Tokens.radiusPill
                        color: Theme.input_bg
                        border.width: 1
                        border.color: Theme.border
                        implicitWidth: segRow.implicitWidth + Tokens.space1 * 2
                        implicitHeight: 42
                        Row {
                            id: segRow
                            anchors.centerIn: parent
                            spacing: Tokens.space1
                            Repeater {
                                model: [
                                    { i: 0, label: I18n.tr("All"),      g: "view_list" },
                                    { i: 1, label: I18n.tr("Complete"), g: "check_circle" },
                                    { i: 2, label: I18n.tr("Partial"),  g: "hourglass_empty" }
                                ]
                                AbstractButton {
                                    id: segBtn
                                    height: 34
                                    implicitWidth: segInner.implicitWidth + Tokens.space5
                                    readonly property bool on: History.filterIndex === modelData.i
                                    hoverEnabled: true
                                    onClicked: History.filterIndex = modelData.i
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Tokens.radiusPill
                                        color: segBtn.on ? Theme.primary
                                             : segBtn.hovered ? U.hoverTint(Theme.input_bg, Theme.isDark)
                                             : Theme.input_bg
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    }
                                    contentItem: Item {
                                        implicitWidth: segInner.implicitWidth
                                        implicitHeight: segInner.implicitHeight
                                        Row {
                                            id: segInner
                                            anchors.centerIn: parent
                                            spacing: Tokens.space1 + 2
                                            C.IconGlyph {
                                                name: modelData.g; size: 14
                                                fill: segBtn.on
                                                glyphColor: segBtn.on ? Theme.on_primary : Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: modelData.label
                                                weight: Tokens.weightDemiBold
                                                color: segBtn.on ? Theme.on_primary : Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // search box
                    Rectangle {
                        Layout.preferredWidth: Math.min(340, content.width * 0.4)
                        implicitHeight: 42
                        radius: Tokens.radiusPill
                        color: Theme.input_bg
                        border.width: 1
                        border.color: histSearch.activeFocus ? Theme.primary : Theme.border
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.space4
                            anchors.rightMargin: Tokens.space1
                            spacing: Tokens.space2
                            C.IconGlyph {
                                name: "search"; size: 16
                                glyphColor: histSearch.activeFocus ? Theme.primary : Theme.on_surface_var
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
                                placeholderText: I18n.tr("Search file or source")
                                placeholderTextColor: Theme.outline
                                color: Theme.on_surface
                                font.family: Fonts.body
                                font.pixelSize: Tokens.fontBody
                                selectByMouse: true
                                leftPadding: 0; rightPadding: 0
                                background: null
                                text: History.searchText
                                onTextChanged: History.searchText = text
                            }
                            C.IconButton {
                                visible: histSearch.text !== ""
                                width: 32; height: 32
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                Layout.alignment: Qt.AlignVCenter
                                iconName: "close"
                                tip: I18n.tr("Clear search")
                                onClicked: histSearch.text = ""
                            }
                        }
                    }
                }

                // ── empty state ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: emptyCol.implicitHeight + Tokens.space7 * 2
                    visible: History.isEmpty
                    radius: Tokens.radiusXl
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border
                    Column {
                        id: emptyCol
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Tokens.space6 * 2, 460)
                        spacing: Tokens.space3
                        // a little stack of "files" — the thing this page holds
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 84; height: 76
                            Repeater {
                                model: 3
                                Rectangle {
                                    x: 14 + (index - 1) * 6
                                    y: (2 - index) * 9
                                    width: 56; height: 62; radius: Tokens.radiusMd
                                    rotation: (index - 1) * 7
                                    color: index === 2 ? Theme.surface_high : Theme.surface_low
                                    border.width: 1
                                    border.color: index === 2 ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                    C.IconGlyph {
                                        visible: index === 2
                                        anchors.centerIn: parent
                                        name: History.hasFolder ? "description" : "folder_off"
                                        size: 22
                                        glyphColor: Theme.primary
                                    }
                                }
                            }
                        }
                        C.AppText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: History.hasFolder ? I18n.tr("No exports found")
                                                    : I18n.tr("No save folder yet")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontTitle
                            color: Theme.text_strong
                        }
                        C.AppText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: History.hasFolder
                                  ? I18n.tr("Try a different search or filter — completed extractions land here automatically.")
                                  : I18n.tr("Select a save folder on the Scraper page to see history here.")
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                        Item { width: 1; height: Tokens.space1 }
                        C.PrimaryButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            iconName: History.hasFolder && histSearch.text !== "" ? "close" : "cloud_download"
                            text: History.hasFolder && histSearch.text !== "" ? I18n.tr("Clear search")
                                                                           : I18n.tr("New Scrape")
                            onClicked: {
                                if (History.hasFolder && histSearch.text !== "") histSearch.text = ""
                                else App.goto(0)   // PAGE_SCRAPER
                            }
                        }
                    }
                }

                // ── the timeline ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    visible: !History.isEmpty
                    Repeater {
                        // v3.40.1: page._entries, not History.entries: every
                        // read of the Python property converts the WHOLE list,
                        // and each row read it up to three times (O(n²)).
                        model: page._entries
                        delegate: ColumnLayout {
                            id: slot
                            Layout.fillWidth: true
                            spacing: 0
                            readonly property string day: page.dayOf(modelData.saved)
                            readonly property bool firstOfDay: index === 0
                                || page.dayOf(page._entries[index - 1].saved) !== slot.day
                            readonly property bool lastOfDay: index === page._entries.length - 1
                                || page.dayOf(page._entries[index + 1].saved) !== slot.day

                            // day header
                            RowLayout {
                                visible: slot.firstOfDay
                                Layout.fillWidth: true
                                Layout.topMargin: index === 0 ? 0 : Tokens.space5
                                Layout.bottomMargin: Tokens.space2
                                spacing: Tokens.space3
                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    Layout.preferredWidth: 28
                                    color: slot.day === page._today ? Theme.primary : Theme.surface_high
                                    border.width: 1
                                    border.color: slot.day === page._today ? Theme.primary : Theme.border
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: "history"; size: 14
                                        glyphColor: slot.day === page._today ? Theme.on_primary : Theme.on_surface_var
                                    }
                                }
                                C.AppText {
                                    text: page.dayLabel(slot.day)
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontLabel
                                    color: Theme.text_strong
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.alignment: Qt.AlignVCenter }
                            }

                            HistoryRow {
                                row: modelData
                                wide: page._wide
                                railTop: !slot.firstOfDay
                                railBottom: !slot.lastOfDay
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
    property real _wheelTarget: 0
    NumberAnimation {
        id: hWheelAnim
        target: scroller.contentItem
        property: "contentY"
        duration: Tokens.durMed
        easing.type: Easing.OutCubic
    }

    C.Toast { id: toast; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 80 }

    // ── clear-all confirmation ──
    Dialog {
        id: confirmClear
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(440, page.width - 80)
        padding: 0

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast }
        }
        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: clHeadRow.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: clHeadRow
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
                        name: "warning"; fill: true; size: 20
                        glyphColor: Theme.error
                    }
                }
                C.AppText {
                    text: I18n.tr("Delete every export?")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.error
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: C.AppText {
            text: I18n.tr("This permanently removes every export file in your save folder. This cannot be undone.")
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
                    onClicked: confirmClear.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete_sweep"
                    text: I18n.tr("Delete all")
                    onClicked: { confirmClear.close(); History.deleteAll() }
                }
            }
        }
    }

    // ── per-file delete confirmation ──
    Dialog {
        id: confirmDeleteFile
        property string pendingPath: ""
        property string pendingName: ""
        function ask(path, name) { pendingPath = path; pendingName = name || ""; open() }

        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(440, page.width - 80)
        padding: 0

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast }
        }
        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: dfHeadRow.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: dfHeadRow
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
                        name: "delete"; fill: true; size: 20
                        glyphColor: Theme.error
                    }
                }
                C.AppText {
                    text: I18n.tr("Delete this export?")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: C.AppText {
            text: confirmDeleteFile.pendingName !== ""
                  ? I18n.tr("“{n}” will be permanently deleted from your save folder. This cannot be undone.")
                        .replace("{n}", confirmDeleteFile.pendingName)
                  : I18n.tr("This file will be permanently deleted from your save folder. This cannot be undone.")
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
                    onClicked: confirmDeleteFile.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete"
                    text: I18n.tr("Delete")
                    onClicked: { confirmDeleteFile.close(); History.deleteFile(confirmDeleteFile.pendingPath) }
                }
            }
        }
    }

    // ── inline building blocks ────────────────────────────────────────────

    // One cell of the header stat ribbon: glyph + big value over a label.
    component StatCell: Item {
        property string glyph: ""
        property string value: "0"
        property string label: ""
        implicitWidth: scCol.implicitWidth + Tokens.space5 * 2
        implicitHeight: 56
        Row {
            id: scCol
            anchors.centerIn: parent
            spacing: Tokens.space3
            C.IconGlyph { name: glyph; size: 18; glyphColor: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
            Column {
                spacing: 0
                anchors.verticalCenter: parent.verticalCenter
                C.AppText {
                    text: value
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                }
                C.AppText {
                    text: label
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.on_surface_var
                }
            }
        }
    }

    // One export on the timeline: rail + dot, format badge, name + source,
    // meta, actions. The rail joins the files of the same day.
    component HistoryRow: Item {
        id: rowCard
        property var row: ({})
        property bool wide: true
        property bool railTop: false
        property bool railBottom: false
        readonly property bool _partial: row.partial === true
        readonly property string _ext: {
            const n = String(row.name || "")
            const i = n.lastIndexOf(".")
            return i >= 0 ? n.slice(i + 1).toUpperCase() : "FILE"
        }
        // a format colour per extension, from the palette (no new hex values)
        readonly property color _tint: (_ext === "CSV") ? Theme.secondary_container
                                     : (_ext === "XLSX" || _ext === "XLS") ? Theme.tertiary
                                     : (_ext === "JSON" || _ext === "JSONL") ? Theme.warn
                                     : Theme.primary
        readonly property string _time: String(row.saved || "").length > 11 ? String(row.saved).slice(11) : (row.saved || "")

        implicitHeight: 84

        // ── the rail ──
        Item {
            id: rail
            width: 28
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            Rectangle {
                visible: rowCard.railTop
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.verticalCenter
                width: 2; color: Theme.border
            }
            Rectangle {
                visible: rowCard.railBottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.bottom: parent.bottom
                width: 2; color: Theme.border
            }
            Rectangle {
                anchors.centerIn: parent
                width: rowHover.hovered ? 12 : 10; height: width; radius: width / 2
                color: rowHover.hovered ? Theme.primary : Theme.panel_bg
                border.width: 2
                border.color: rowHover.hovered ? Theme.primary : (rowCard._partial ? Theme.warn : Theme.outline)
                Behavior on width { NumberAnimation { duration: Tokens.durFast } }
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
        }

        // ── the card ──
        Rectangle {
            id: card
            anchors.left: rail.right
            anchors.leftMargin: Tokens.space3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 74
            radius: Tokens.radiusLg
            color: rowHover.hovered ? U.mix(Theme.panel_bg, Theme.primary, 0.04) : Theme.panel_bg
            border.width: 1
            border.color: rowHover.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

            HoverHandler { id: rowHover }
            // double-click the row = show it in its folder. A MouseArea UNDER
            // the content (declared first), so the buttons on top keep their
            // own clicks and a double-click on one of them never also fires this.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onDoubleClicked: History.openFolder(rowCard.row.path)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space3
                anchors.rightMargin: Tokens.space3
                spacing: Tokens.space4

                // format badge
                Rectangle {
                    width: 50; height: 50; radius: Tokens.radiusMd
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 50
                    Layout.alignment: Qt.AlignVCenter
                    color: U.withAlpha(rowCard._tint, rowHover.hovered ? 0.18 : 0.12)
                    border.width: 1
                    border.color: U.withAlpha(rowCard._tint, 0.35)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        C.IconGlyph {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "description"; size: 16; fill: true
                            glyphColor: rowCard._tint
                        }
                        C.AppText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: rowCard._ext
                            mono: true
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontMicro
                            color: rowCard._tint
                        }
                    }
                }

                // name + source
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.AppText {
                            text: rowCard.row.name || ""
                            weight: Tokens.weightBold
                            color: Theme.text_strong
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        // status badge
                        Rectangle {
                            radius: Tokens.radiusPill
                            color: U.withAlpha(rowCard._partial ? Theme.warn : Theme.secondary_container, 0.14)
                            implicitWidth: stRow.implicitWidth + Tokens.space3
                            implicitHeight: 22
                            Layout.alignment: Qt.AlignVCenter
                            Row {
                                id: stRow
                                anchors.centerIn: parent
                                spacing: Tokens.space1
                                C.IconGlyph {
                                    name: rowCard._partial ? "hourglass_empty" : "check_circle"
                                    fill: true; size: 12
                                    glyphColor: rowCard._partial ? Theme.warn : Theme.secondary_container
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                C.AppText {
                                    text: rowCard._partial ? I18n.tr("Partial") : I18n.tr("Complete")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: rowCard._partial ? Theme.warn : Theme.secondary_container
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                    C.AppText {
                        text: (rowCard.row.source || "") + (rowCard.wide ? "" : "  ·  " + (rowCard.row.rows || "") + " " + I18n.tr("rows"))
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // meta: rows / size / time
                Row {
                    spacing: Tokens.space6
                    Layout.alignment: Qt.AlignVCenter
                    visible: rowCard.wide
                    Repeater {
                        model: [
                            { l: I18n.tr("ROWS"),  v: rowCard.row.rows },
                            { l: I18n.tr("SIZE"),  v: rowCard.row.size },
                            { l: I18n.tr("SAVED"), v: rowCard._time }
                        ]
                        Column {
                            spacing: 2
                            C.AppText {
                                text: modelData.l
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontMicro
                                font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                color: Theme.outline
                            }
                            C.AppText {
                                text: modelData.v || "—"
                                mono: true
                                weight: Tokens.weightBold
                                color: Theme.on_surface
                            }
                        }
                    }
                }

                // actions — quiet at rest, full strength on hover
                Row {
                    spacing: Tokens.space2
                    Layout.alignment: Qt.AlignVCenter
                    opacity: rowHover.hovered ? 1.0 : 0.55
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                    // Straight to the channel report with this file already
                    // picked — both pages accept the same extensions.
                    C.PrimaryButton {
                        variant: rowHover.hovered ? "primary" : "ghost"
                        iconName: "auto_awesome"
                        text: I18n.tr("Analyze")
                        implicitHeight: 38
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            Ideas.addCsv(rowCard.row.path)
                            App.goto(6)   // PAGE_AI_IDEAS, where CSV + videos become one blueprint
                        }
                    }
                    C.IconButton {
                        width: 38; height: 38
                        iconName: "folder_open"
                        anchors.verticalCenter: parent.verticalCenter
                        tip: I18n.tr("Show in folder")
                        onClicked: History.openFolder(rowCard.row.path)
                    }
                    C.IconButton {
                        width: 38; height: 38
                        iconName: "delete"
                        accent: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                        tip: I18n.tr("Delete this export from disk")
                        onClicked: confirmDeleteFile.ask(rowCard.row.path, rowCard.row.name)
                    }
                }
            }
        }
    }
}
