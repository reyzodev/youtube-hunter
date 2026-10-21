import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v18 "key vault": the YouTube Data API section of Settings, rebuilt.
//
//   ┌ YouTube API ─────────────────────────────────────── ● Valid · 2 keys ┐
//   │ ┌ keys ───────────────────────────────┐ ┌ daily capacity ─────────┐ │
//   │ │ [🔑 PRIMARY KEY  AIza••••   👁 ⎘ ⧉] [Validate] │ 20,000 units      │ │
//   │ │ ✓ format looks right                 │ │ ▰▰▱▱▱  key cells       │ │
//   │ │ BACKUP KEYS · 1                      │ │ search  100 / page      │ │
//   │ │ 2 [key ……………… ] ● [Check] 🗑        │ │ stats   1 / 50 items    │ │
//   │ │ [＋ Add a backup key]                │ │ resets midnight PT      │ │
//   │ └──────────────────────────────────────┘ │ [How do I get a key? →] │ │
//   │                                          └─────────────────────────┘ │
//   └──────────────────────────────────────────────────────────────────────┘
//
// What changed from v17:
//  • Validate is an ActionButton that morphs idle → checking → valid / failed,
//    and the primary key carries a live FORMAT check (AIza… + 39 chars) before
//    a single unit of quota is spent.
//  • Backup rows check the text that is IN the field now. v17's Check button
//    validated `modelData`, the value the row was created with, so editing a
//    backup key and pressing Check silently tested the old key.
//  • Each backup row tracks its own result (a slot call such as keyStatus()
//    records no binding dependency, so the old dot never updated).
//  • The quota panel says the one thing people get wrong: keys only add
//    quota when they come from DIFFERENT Google Cloud projects.
//  • "How do I get a key?" opens the full step-by-step guide section.
//
// All state still lives in the SettingsVM; this is presentation only.
C.GlassPanel {
    id: root
    objectName: "tour_settingsKeys"

    // 0 none · 1 ok · 2 bad   (last result for the PRIMARY key)
    property int primaryState: 0
    property bool primaryBusy: false
    property string primaryMsg: ""
    property bool dimmed: false

    signal guideRequested()

    Layout.fillWidth: true
    radius: Tokens.radiusXl
    implicitHeight: col.implicitHeight + Tokens.space6 * 2
    opacity: root.dimmed ? 0.38 : 1.0
    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

    // ── helpers ──
    function keyFormat(k) {
        const s = String(k || "").trim()
        if (s === "") return ""
        return /^AIza[0-9A-Za-z_\-]{35}$/.test(s) ? "ok" : "warn"
    }
    readonly property int keyCount: {
        let n = String(Settings.apiKey || "").trim() !== "" ? 1 : 0
        const b = Settings.backupKeys
        for (let i = 0; i < b.length; i++)
            if (String(b[i] || "").trim() !== "") n++
        return n
    }

    // one-shot accent ring when the rail / search jumps here
    function flash() { flashAnim.restart() }
    Rectangle {
        id: flashRing
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        opacity: 0
        z: 50
        SequentialAnimation {
            id: flashAnim
            PauseAnimation { duration: 180 }
            NumberAnimation { target: flashRing; property: "opacity"; to: 0.9; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: flashRing; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    // small uppercase-ish block label (Latin is tracked, Persian never is)
    component BlockLabel: RowLayout {
        id: bl
        property string text: ""
        property string count: ""
        spacing: Tokens.space2
        C.AppText {
            text: bl.text
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontMicro
            font.letterSpacing: I18n.rtl ? 0 : 1.1
            color: Theme.on_surface_var
        }
        Rectangle {
            visible: bl.count !== ""
            radius: Tokens.radiusPill
            color: U.withAlpha(Theme.primary, 0.12)
            implicitWidth: Math.max(20, blCount.implicitWidth + 12)
            implicitHeight: 20
            C.AppText {
                id: blCount
                anchors.centerIn: parent
                text: bl.count
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontMicro
                color: Theme.primary
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.space6
        spacing: Tokens.space5

        // ── header (same rhythm as every Settings section) ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space4
            C.IconTile {
                iconName: "youtube"
                size: 44
                lit: headHover.hovered
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignVCenter
                HoverHandler { id: headHover }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                C.AppText {
                    text: I18n.tr("YouTube API")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle + 2
                    color: Theme.text_strong
                }
                C.AppText {
                    text: I18n.tr("Your YouTube Data API v3 keys, stored locally on this device.")
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface_var
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            // status pill
            Rectangle {
                readonly property color tint: root.primaryBusy ? Theme.primary
                                            : root.primaryState === 1 ? Theme.secondary_container
                                            : root.primaryState === 2 ? Theme.error
                                            : root.keyCount === 0 ? Theme.warn : Theme.on_surface_var
                Layout.alignment: Qt.AlignVCenter
                radius: Tokens.radiusPill
                color: U.withAlpha(tint, 0.12)
                border.width: 1
                border.color: U.withAlpha(tint, 0.30)
                implicitWidth: pillRow.implicitWidth + Tokens.space3 * 2
                implicitHeight: 28
                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        color: parent.parent.tint
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.primaryBusy ? I18n.tr("Checking …")
                            : root.primaryState === 1 ? I18n.tr("Valid")
                            : root.primaryState === 2 ? I18n.tr("Invalid")
                            : root.keyCount === 0 ? I18n.tr("No key yet")
                            : I18n.tr("Not validated")
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: parent.parent.tint
                    }
                    C.AppText {
                        visible: root.keyCount > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·  " + (root.keyCount === 1 ? I18n.tr("1 key")
                                       : I18n.tr("{n} keys").replace("{n}", root.keyCount))
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                }
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            columns: root.width >= 960 ? 2 : 1
            columnSpacing: Tokens.space5
            rowSpacing: Tokens.space5

            // ═════════ keys column ═════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.space5

                // ── primary ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    RowLayout {
                        Layout.fillWidth: true
                        BlockLabel { text: I18n.tr("PRIMARY KEY") }
                        Item { Layout.fillWidth: true }
                        C.IconGlyph { name: "lock"; size: 13; glyphColor: Theme.outline }
                        C.AppText {
                            text: I18n.tr("Never leaves your device")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.outline
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        C.SmartField {
                            id: primaryField
                            Layout.alignment: Qt.AlignTop
                            property bool reveal: false
                            label: I18n.tr("YouTube Data API v3 key")
                            icon: "key"
                            mono: true
                            placeholder: "AIzaSy…"
                            echoMode: reveal ? TextInput.Normal : TextInput.Password
                            text: Settings.apiKey
                            tone: root.primaryState === 2 ? "error"
                                : root.primaryState === 1 ? "ok"
                                : root.keyFormat(primaryField.text)
                            helper: root.primaryMsg !== "" ? root.primaryMsg
                                  : root.keyFormat(primaryField.text) === "ok"
                                    ? I18n.tr("Format looks right. Validate to be sure it works.")
                                  : root.keyFormat(primaryField.text) === "warn"
                                    ? I18n.tr("Google keys start with AIza and are 39 characters long. Part of it may be missing.")
                                  : I18n.tr("Paste the key from Google Cloud → Credentials.")
                            onEdited: (v) => {
                                Settings.apiKey = v
                                root.primaryState = 0
                                root.primaryMsg = ""
                            }
                            onAccepted: if (validateBtn.enabled) validateBtn.clicked()
                            C.IconButton {
                                iconName: primaryField.reveal ? "visibility_off" : "visibility"
                                implicitWidth: 34; implicitHeight: 34
                                glyphSize: 16
                                tip: primaryField.reveal ? I18n.tr("Hide") : I18n.tr("Show")
                                onClicked: primaryField.reveal = !primaryField.reveal
                            }
                            C.IconButton {
                                iconName: "content_paste"
                                implicitWidth: 34; implicitHeight: 34
                                glyphSize: 16
                                tip: I18n.tr("Paste")
                                onClicked: {
                                    // through the VM, so the field's binding survives
                                    // (Discard must still be able to reset it)
                                    Settings.apiKey = String(Settings.clipboardText() || "").trim()
                                    root.primaryState = 0
                                    root.primaryMsg = ""
                                }
                            }
                            C.IconButton {
                                visible: primaryField.text !== ""
                                iconName: "content_copy"
                                implicitWidth: 34; implicitHeight: 34
                                glyphSize: 16
                                tip: I18n.tr("Copy")
                                onClicked: Settings.copyToClipboard(primaryField.text)
                            }
                        }
                        C.ActionButton {
                            id: validateBtn
                            Layout.alignment: Qt.AlignTop
                            iconName: "verified"
                            text: I18n.tr("Validate")
                            busyText: I18n.tr("Checking …")
                            okText: I18n.tr("Valid")
                            failText: I18n.tr("Failed")
                            enabled: primaryField.text.trim() !== "" && !root.primaryBusy
                            status: root.primaryBusy ? 1 : root.primaryState === 1 ? 2
                                  : root.primaryState === 2 ? 3 : 0
                            onClicked: {
                                root.primaryState = 0
                                root.primaryBusy = true
                                root.primaryMsg = I18n.tr("Validating …")
                                Settings.validateYouTubeKey(primaryField.text)
                            }
                        }
                    }
                }

                // ── backups ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    BlockLabel {
                        text: I18n.tr("BACKUP KEYS")
                        count: String(Settings.backupKeys.length)
                    }
                    C.AppText {
                        text: I18n.tr("When a key runs out of today's quota mid-scrape, the next one takes over automatically.")
                        font.pixelSize: Tokens.fontCaption + 1
                        color: Theme.on_surface_var
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: Settings.backupKeys
                        RowLayout {
                            id: bk
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            // 0 unknown · 1 checking · 2 ok · 3 bad
                            property int st: {
                                const s = Settings.keyStatus(modelData)
                                return s === "ok" ? 2 : s === "bad" ? 3 : 0
                            }
                            property bool reveal: false

                            Connections {
                                target: Settings
                                function onYtValidateResult(key, ok, msg) {
                                    if (key !== "" && key === bkField.text.trim())
                                        bk.st = ok ? 2 : 3
                                    else if (key === "" && bk.st === 1)
                                        bk.st = 3
                                }
                            }

                            // rank chip: primary is #1, so backups count from 2
                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 46
                                Layout.alignment: Qt.AlignTop
                                radius: 12
                                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.045)
                                border.width: 1
                                border.color: Theme.border
                                C.AppText {
                                    anchors.centerIn: parent
                                    text: index + 2
                                    mono: true
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.on_surface_var
                                }
                            }
                            C.SmartField {
                                id: bkField
                                dense: true
                                mono: true
                                Layout.alignment: Qt.AlignTop
                                icon: ""
                                placeholder: I18n.tr("Backup key from another project")
                                echoMode: bk.reveal ? TextInput.Normal : TextInput.Password
                                text: modelData
                                tone: bk.st === 2 ? "ok" : bk.st === 3 ? "error"
                                    : (root.keyFormat(bkField.text) === "warn" ? "warn" : "")
                                onEdited: (v) => {
                                    Settings.setBackupKey(index, v)
                                    bk.st = 0
                                }
                                // status dot inside the well
                                Rectangle {
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    Layout.rightMargin: 4
                                    Layout.leftMargin: 4
                                    radius: 4
                                    color: bk.st === 2 ? Theme.secondary_container
                                         : bk.st === 3 ? Theme.error
                                         : bk.st === 1 ? Theme.primary : Theme.outline_variant
                                    SequentialAnimation on opacity {
                                        running: bk.st === 1
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.25; duration: 500 }
                                        NumberAnimation { from: 0.25; to: 1; duration: 500 }
                                    }
                                }
                                C.IconButton {
                                    iconName: bk.reveal ? "visibility_off" : "visibility"
                                    implicitWidth: 30; implicitHeight: 30
                                    glyphSize: 15
                                    tip: bk.reveal ? I18n.tr("Hide") : I18n.tr("Show")
                                    onClicked: bk.reveal = !bk.reveal
                                }
                                C.IconButton {
                                    iconName: "content_paste"
                                    implicitWidth: 30; implicitHeight: 30
                                    glyphSize: 15
                                    tip: I18n.tr("Paste")
                                    onClicked: {
                                        const v = String(Settings.clipboardText() || "").trim()
                                        bkField.text = v
                                        Settings.setBackupKey(index, v)
                                        bk.st = 0
                                    }
                                }
                            }
                            C.ActionButton {
                                compact: true
                                variant: "ghost"
                                Layout.preferredHeight: 46
                                Layout.alignment: Qt.AlignTop
                                iconName: "verified"
                                text: I18n.tr("Check")
                                okText: I18n.tr("Valid")
                                failText: I18n.tr("Failed")
                                busyText: I18n.tr("Checking …")
                                enabled: bkField.text.trim() !== "" && bk.st !== 1
                                status: bk.st
                                onClicked: {
                                    bk.st = 1
                                    Settings.validateYouTubeKey(bkField.text)
                                }
                            }
                            C.IconButton {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 3
                                iconName: "delete"
                                accent: Theme.error
                                tip: I18n.tr("Remove this key")
                                onClicked: Settings.removeBackupKey(index)
                            }
                        }
                    }

                    // add tile
                    AbstractButton {
                        id: addBtn
                        Layout.fillWidth: true
                        implicitHeight: 58
                        hoverEnabled: true
                        padding: 0
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: Settings.addBackupKey()
                        scale: addBtn.pressed ? 0.99 : 1.0
                        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                        background: Rectangle {
                            radius: 14
                            color: addBtn.hovered ? U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.05) : U.withAlpha(Theme.primary, 0)
                            border.width: 1
                            border.color: addBtn.hovered ? U.withAlpha(Theme.primary, 0.55) : Theme.border_med
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        contentItem: Item {
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.space3
                                anchors.rightMargin: Tokens.space4
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    radius: 17
                                    color: addBtn.hovered ? Theme.primary : U.withAlpha(Theme.primary, 0.12)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: "add"; size: 17
                                        glyphColor: addBtn.hovered ? Theme.on_primary : Theme.primary
                                        rotation: addBtn.hovered ? 90 : 0
                                        Behavior on rotation { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    C.AppText {
                                        text: I18n.tr("Add a backup key")
                                        weight: Tokens.weightBold
                                        color: Theme.text_strong
                                    }
                                    C.AppText {
                                        text: I18n.tr("Each extra project adds another 10,000 units a day")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═════════ capacity column ═════════
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.maximumWidth: grid.columns === 2 ? 400 : 100000
                Layout.alignment: Qt.AlignTop
                radius: Tokens.radiusLg + 1
                color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.75 : 0.9)
                border.width: 1
                border.color: Theme.border
                implicitHeight: capCol.implicitHeight + Tokens.space5 * 2
                clip: true

                // accent wash from the top
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 150
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.13 : 0.08) }
                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                    }
                }

                ColumnLayout {
                    id: capCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space5
                    spacing: Tokens.space4

                    BlockLabel { text: I18n.tr("DAILY CAPACITY") }

                    RowLayout {
                        spacing: Tokens.space2
                        C.AppText {
                            text: (Math.max(1, root.keyCount) * 10000).toLocaleString(Qt.locale("en_US"), "f", 0)
                            mono: true
                            weight: Tokens.weightExtraBold
                            font.pixelSize: 34
                            color: root.keyCount > 0 ? Theme.text_strong : Theme.outline
                            LayoutMirroring.enabled: false
                        }
                        C.AppText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 6
                            text: I18n.tr("units / day")
                            weight: Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontBody
                            color: Theme.on_surface_var
                        }
                    }

                    // key cells: one per configured key (max 6 drawn)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: 6
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8
                                radius: 4
                                readonly property bool lit: index < root.keyCount
                                color: lit ? Theme.primary : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.07)
                                opacity: lit ? (1.0 - index * 0.1) : 1.0
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                            }
                        }
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        text: root.keyCount === 0
                              ? I18n.tr("Add a key to start searching. One free key covers about 100 keyword searches a day.")
                              : I18n.tr("10,000 units per Google Cloud project. Keys from the same project share one pool.")
                        font.pixelSize: Tokens.fontCaption + 1
                        lineHeight: 1.3
                        color: Theme.on_surface_var
                        wrapMode: Text.WordWrap
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider_h }

                    // what things cost
                    Repeater {
                        model: [
                            { ic: "search",    t: I18n.tr("Keyword search"),       v: "100", u: I18n.tr("units / page") },
                            { ic: "bar_chart", t: I18n.tr("Video & channel stats"), v: "1",   u: I18n.tr("unit / 50 items") },
                            { ic: "history",   t: I18n.tr("Quota resets"),          v: "00:00", u: I18n.tr("Pacific time") }
                        ]
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 9
                                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.05)
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    name: modelData.ic
                                    size: 15
                                    glyphColor: Theme.on_surface_var
                                }
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.t
                                font.pixelSize: Tokens.fontBody
                                color: Theme.on_surface
                                elide: Text.ElideRight
                            }
                            C.AppText {
                                text: modelData.v
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: Theme.text_strong
                                LayoutMirroring.enabled: false
                            }
                            C.AppText {
                                text: modelData.u
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                            }
                        }
                    }

                    // guide CTA
                    AbstractButton {
                        id: guideBtn
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.space1
                        implicitHeight: 52
                        hoverEnabled: true
                        padding: 0
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: root.guideRequested()
                        scale: guideBtn.pressed ? 0.985 : 1.0
                        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                        background: Rectangle {
                            radius: 13
                            color: guideBtn.hovered ? U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                                                    : U.withAlpha(Theme.primary, Theme.isDark ? 0.09 : 0.06)
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, guideBtn.hovered ? 0.55 : 0.28)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        contentItem: Item {
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.space4
                                anchors.rightMargin: Tokens.space3
                                spacing: Tokens.space3
                                C.IconGlyph { name: "help"; fill: true; size: 17; glyphColor: Theme.primary }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: I18n.tr("How do I get a key?")
                                    weight: Tokens.weightBold
                                    color: Theme.text_strong
                                    elide: Text.ElideRight
                                }
                                C.AppText {
                                    text: I18n.tr("6 steps")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                                C.IconGlyph {
                                    name: I18n.rtl ? "arrow_back" : "arrow_forward"
                                    size: 16
                                    glyphColor: Theme.primary
                                    transform: Translate {
                                        x: guideBtn.hovered ? (I18n.rtl ? -3 : 3) : 0
                                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Validation results → header pill + primary helper line.
    Connections {
        target: Settings
        function onYtValidateResult(key, ok, msg) {
            if (key === String(primaryField.text || "").trim()
                    || (key === "" && root.primaryBusy)) {
                root.primaryBusy = false
                root.primaryState = ok ? 1 : 2
                root.primaryMsg = msg + (ok ? "  ·  " + Settings.keyQuotaLine(key) : "")
            }
        }
    }
}
