import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// AiProfileCard — one saved AI provider, as an accordion card (Settings v19).
//
//   ┌───────────────────────────────────────────────────────────────────┐
//   │ [◆] 9router            ★ Default   ● Ready   Ideas · Chat      ⌄ │
//   │     gpt-5 · 9router.example/v1                                    │
//   ├───────────────────────────────────────────────────────────────────┤
//   │ NAME ……………………………   API MODE  [OpenAI API Compatible ▾]          │
//   │ API HOST ……………………………………………   API PATH ………………                 │
//   │ API KEY ………………………………………………… 👁 ⧉        [ Validate ]          │
//   │ MODELS  2 added · 180 available     [Pick models] [⟳ Fetch]       │
//   │ (★ gpt-5 ×) (gpt-5-mini ×)                                        │
//   │ [🔍 search fetched models / type an id ]                          │
//   │ ☑ gpt-5   ☐ gpt-5-nano   ☑ gpt-5-mini  …  (tick list, v3.16-p3)   │
//   │ POST → https://…/v1/chat/completions                          ⧉   │
//   │ [★ Make default]  [⧉ Duplicate]                     [🗑 Remove]    │
//   └───────────────────────────────────────────────────────────────────┘
//
// Every field writes straight into SettingsVM, which saves the AI block by
// itself (debounced) — so a host typed here survives switching providers,
// closing the page and quitting the app. Only the CARD STRUCTURE comes from
// Settings.aiProfileIds; the values come from Settings.aiProfileMap and are
// pushed into the fields only while a field is NOT focused, so a refresh of
// the map (another field, a status line) never fights the user's typing.
Rectangle {
    id: card
    property string profileId: ""
    readonly property var d: Settings.aiProfileMap[profileId] || ({})
    readonly property bool open: d.open === true
    readonly property bool custom: d.kind === "custom"
    property bool advanced: false          // host / path / mode for a built-in brand
    readonly property bool showConn: custom || advanced || String(d.baseUrl || "") !== ""
    property bool confirmRemove: false

    // brand tint; custom profiles get a stable colour from their id
    readonly property color tint: d.kind === "openai" ? "#10A37F"
                                : d.kind === "anthropic" ? "#D97757"
                                : d.kind === "gemini" ? "#4C8DF6"
                                : ["#8B7CF6", "#E9A23B", "#2FB5A3", "#E5677D", "#5BA7E8", "#B07CE0"][
                                      Math.abs(card._hash(String(card.profileId))) % 6]
    function _hash(s) { var h = 0; for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0; return h }

    Layout.fillWidth: true
    radius: Tokens.radiusXl
    color: open ? (Theme.isDark ? U.withAlpha(Theme.surface_high, 0.9) : Theme.surface)
                : (headHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low)
    border.width: 1
    border.color: open ? U.withAlpha(card.tint, 0.45) : (d.active ? U.withAlpha(Theme.primary, 0.35) : Theme.border)
    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
    implicitHeight: head.height + (open ? body.implicitHeight + Tokens.space5 : 0)
    Layout.preferredHeight: implicitHeight
    clip: true
    Behavior on implicitHeight { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }

    // brand glow along the leading edge while open — an inset rounded pill.
    // `clip: true` only cuts to the square bounding box, so a full-height bar
    // flush with the edge poked out past the rounded corners as a straight
    // "T"; inset it inside the border and round its own ends instead.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6
        anchors.topMargin: Tokens.space4
        anchors.bottomMargin: Tokens.space4
        width: 3
        radius: width / 2
        antialiasing: true
        color: card.tint
        opacity: card.open ? 0.9 : (card.d.active ? 0.5 : 0)
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
    }

    // ── header (always visible; click toggles) ──
    AbstractButton {
        id: head
        width: parent.width
        height: 72
        padding: 0
        hoverEnabled: true
        HoverHandler { id: headHover; cursorShape: Qt.PointingHandCursor }
        onClicked: Settings.setAiOpen(card.open ? "" : card.profileId)
        background: Item { }
        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space4
                spacing: Tokens.space3

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 13
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(card.tint, Theme.isDark ? 0.30 : 0.20) }
                        GradientStop { position: 1.0; color: U.withAlpha(card.tint, Theme.isDark ? 0.12 : 0.08) }
                    }
                    border.width: 1
                    border.color: U.withAlpha(card.tint, 0.35)
                    C.IconGlyph { anchors.centerIn: parent; name: card.d.glyph || "api"; fill: true; size: 20; glyphColor: card.tint }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.AppText {
                            text: card.d.name || ""
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.text_strong
                            elide: Text.ElideRight
                            Layout.maximumWidth: 260
                        }
                        // default badge
                        Rectangle {
                            visible: card.d.active === true
                            radius: Tokens.radiusPill
                            color: U.withAlpha(Theme.primary, 0.14)
                            implicitWidth: defRow.implicitWidth + 14
                            implicitHeight: 22
                            Row {
                                id: defRow
                                anchors.centerIn: parent
                                spacing: 4
                                C.IconGlyph { anchors.verticalCenter: parent.verticalCenter; name: "star"; fill: true; size: 11; glyphColor: Theme.primary }
                                C.AppText { anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Default"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: Theme.primary }
                            }
                        }
                        // ready dot
                        Row {
                            spacing: 5
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7; height: 7; radius: 4
                                color: card.d.state === 3 ? Theme.error
                                     : card.d.ready ? Theme.secondary_container : Theme.warn
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.d.state === 2 && card.d.statusSrc === "key" ? I18n.tr("Verified")
                                    : card.d.state === 3 ? I18n.tr("Check failed")
                                    : card.d.ready ? I18n.tr("Ready")
                                    : card.custom ? I18n.tr("Needs a host") : I18n.tr("No key")
                                font.pixelSize: Tokens.fontMicro
                                weight: Tokens.weightDemiBold
                                color: Theme.on_surface_var
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        text: (card.d.effectiveModel || I18n.tr("No model set"))
                              + (String(card.d.baseUrl || "") !== "" ? "  ·  " + String(card.d.baseUrl).replace(/^https?:\/\//, "") : "")
                              + (String(card.d.keyHint || "") !== "" ? "  ·  " + card.d.keyHint : "")
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                        elide: Text.ElideRight
                    }
                }
                // which features run on this profile
                Flow {
                    visible: (card.d.usedBy || []).length > 0 && card.width > 620
                    Layout.preferredWidth: Math.min(220, usedRow.implicitWidth)
                    Row {
                        id: usedRow
                        spacing: 4
                        Repeater {
                            model: card.d.usedBy || []
                            Rectangle {
                                radius: Tokens.radiusPill
                                color: U.withAlpha(card.tint, 0.12)
                                implicitWidth: ubTxt.implicitWidth + 14
                                implicitHeight: 22
                                C.AppText { id: ubTxt; anchors.centerIn: parent; text: modelData; font.pixelSize: Tokens.fontMicro; weight: Tokens.weightDemiBold; color: card.tint }
                            }
                        }
                    }
                }
                // quick delete, right on the header (custom providers only):
                // first click arms it, second click removes
                AbstractButton {
                    id: headDel
                    visible: card.custom
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: card.confirmRemove ? hdRow.implicitWidth + 20 : 32
                    hoverEnabled: true
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: {
                        if (card.confirmRemove) Settings.removeAiProfile(card.profileId)
                        else { card.confirmRemove = true; disarm.restart() }
                    }
                    background: Rectangle {
                        radius: 10
                        color: card.confirmRemove ? U.withAlpha(Theme.error, Theme.isDark ? 0.18 : 0.12)
                             : headDel.hovered ? U.withAlpha(Theme.error, 0.10) : U.withAlpha(Theme.error, 0)
                        border.width: card.confirmRemove ? 1 : 0
                        border.color: U.withAlpha(Theme.error, 0.45)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    contentItem: Item {
                        clip: true
                        Row {
                            id: hdRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.IconGlyph {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "delete_outline"; size: 16
                                glyphColor: card.confirmRemove || headDel.hovered ? Theme.error : Theme.on_surface_var
                            }
                            C.AppText {
                                visible: card.confirmRemove
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Delete?")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.error
                            }
                        }
                    }
                    C.AppTooltip { visible: headDel.hovered && !card.confirmRemove; text: I18n.tr("Delete this provider") }
                }
                C.IconGlyph {
                    name: "expand_more"
                    size: 18
                    glyphColor: Theme.on_surface_var
                    rotation: card.open ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // ── body ──
    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.space5
        anchors.rightMargin: Tokens.space5
        y: head.height
        spacing: Tokens.space4
        opacity: card.open ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

        // name + api mode
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space3
            visible: card.custom || card.advanced
            C.SmartField {
                id: nameField
                visible: card.custom
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                label: I18n.tr("Provider name")
                icon: "api"
                placeholder: I18n.tr("My provider")
                onEdited: (v) => Settings.setAiField(card.profileId, "name", v)
                Binding { target: nameField; property: "text"; value: card.d.name || ""; when: !nameField.focused; restoreMode: Binding.RestoreNone }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 6
                C.AppText { text: I18n.tr("API MODE"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: Theme.on_surface_var }
                C.Dropdown {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    model: Settings.apiModeLabels
                    currentIndex: card.d.apiModeIndex || 0
                    onActivated: Settings.setAiApiMode(card.profileId, currentIndex)
                }
            }
        }
        C.AppText {
            visible: card.custom || card.advanced
            Layout.fillWidth: true
            Layout.topMargin: -Tokens.space2
            text: card.d.modeHint || ""
            font.pixelSize: Tokens.fontCaption
            color: Theme.outline
            wrapMode: Text.WordWrap
        }

        // host + path
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space3
            visible: card.showConn
            C.SmartField {
                id: hostField
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.alignment: Qt.AlignTop
                label: I18n.tr("API HOST")
                icon: "link"
                mono: true
                placeholder: card.d.hostPlaceholder || ""
                tone: card.custom && String(card.d.baseUrl || "") === "" ? "warn" : ""
                helper: card.custom && String(card.d.baseUrl || "") === "" ? I18n.tr("Required for a custom provider.") : ""
                onEdited: (v) => Settings.setAiField(card.profileId, "baseUrl", v)
                Binding { target: hostField; property: "text"; value: card.d.baseUrl || ""; when: !hostField.focused; restoreMode: Binding.RestoreNone }
            }
            C.SmartField {
                id: pathField
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.alignment: Qt.AlignTop
                label: I18n.tr("API PATH")
                icon: "route"
                mono: true
                enabled: !card.d.isGoogle
                placeholder: card.d.pathPlaceholder || ""
                onEdited: (v) => Settings.setAiField(card.profileId, "path", v)
                Binding { target: pathField; property: "text"; value: card.d.path || ""; when: !pathField.focused; restoreMode: Binding.RestoreNone }
            }
        }

        // key + validate
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space3
            C.SmartField {
                id: keyField
                property bool reveal: false
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                label: card.custom ? I18n.tr("API key (optional for local gateways)") : I18n.tr("API key")
                icon: "key"
                mono: true
                placeholder: I18n.tr("Paste your {p} key").replace("{p}", card.d.name || "")
                echoMode: reveal ? TextInput.Normal : TextInput.Password
                tone: card.d.statusSrc !== "key" ? "" : card.d.state === 2 ? "ok" : card.d.state === 3 ? "error" : ""
                helper: card.d.statusSrc === "key" ? (card.d.status || "") : ""
                onEdited: (v) => Settings.setAiField(card.profileId, "apiKey", v)
                onAccepted: if (validateBtn.enabled) validateBtn.clicked()
                Binding { target: keyField; property: "text"; value: card.d.apiKey || ""; when: !keyField.focused; restoreMode: Binding.RestoreNone }
                C.IconButton {
                    iconName: keyField.reveal ? "visibility_off" : "visibility"
                    implicitWidth: 34; implicitHeight: 34
                    glyphSize: 16
                    tip: keyField.reveal ? I18n.tr("Hide") : I18n.tr("Show")
                    onClicked: keyField.reveal = !keyField.reveal
                }
                C.IconButton {
                    iconName: "content_paste"
                    implicitWidth: 34; implicitHeight: 34
                    glyphSize: 16
                    tip: I18n.tr("Paste")
                    onClicked: Settings.setAiField(card.profileId, "apiKey", String(Settings.clipboardText() || "").trim())
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
                enabled: card.d.state !== 1
                status: card.d.statusSrc === "key" ? (card.d.state || 0) : 0
                onClicked: Settings.validateAiProfile(card.profileId)
            }
        }

        // ── models (v3.16-p3) ──
        // `picked` = the models the user ADDED to this provider: the only ones
        // AI Chat and AI routing offer. Fetch pulls the provider's catalogue
        // into a tick list; ticking adds, the × on a chip removes, clicking a
        // chip makes it the provider's main model (★). A model id that isn't
        // in the catalogue can be typed in and added with Enter.
        ColumnLayout {
            id: modelsBox
            Layout.fillWidth: true
            spacing: Tokens.space3

            property bool pickerOpen: false
            property string query: ""
            readonly property var picked: card.d.picked || []
            readonly property var catalog: card.d.catalog || []
            readonly property var shown: {
                var q = query.trim().toLowerCase()
                var c = catalog
                if (q === "") return c
                var out = []
                for (var i = 0; i < c.length; i++)
                    if (String(c[i]).toLowerCase().indexOf(q) >= 0) out.push(c[i])
                return out
            }
            readonly property bool typedIsNew: query.trim() !== "" && picked.indexOf(query.trim()) < 0
            function isPicked(m) { return picked.indexOf(m) >= 0 }
            function addTyped() {
                var v = query.trim()
                if (v === "") return
                // Enter on a search with exactly one match adds that match
                var pick = (shown.length === 1 && catalog.indexOf(v) < 0) ? shown[0] : v
                Settings.addAiModel(card.profileId, pick)
                modelQuery.text = ""
                query = ""
            }

            Connections {
                target: Settings
                function onAiCatalogReady(pid) {
                    if (pid === card.profileId) modelsBox.pickerOpen = true
                }
            }

            // header: label · counts · browse · fetch
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                C.AppText { text: I18n.tr("MODELS"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: Theme.on_surface_var }
                C.AppText {
                    text: I18n.tr("{n} added").replace("{n}", modelsBox.picked.length)
                    font.pixelSize: Tokens.fontMicro
                    color: modelsBox.picked.length > 0 ? card.tint : Theme.outline
                    weight: Tokens.weightDemiBold
                }
                C.AppText {
                    visible: modelsBox.catalog.length > 0
                    text: "· " + I18n.tr("{n} available").replace("{n}", modelsBox.catalog.length)
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.outline
                }
                Item { Layout.fillWidth: true }
                C.ActionButton {
                    visible: modelsBox.catalog.length > 0
                    compact: true
                    variant: "ghost"
                    iconName: modelsBox.pickerOpen ? "expand_less" : "expand_more"
                    text: modelsBox.pickerOpen ? I18n.tr("Hide list") : I18n.tr("Pick models")
                    onClicked: modelsBox.pickerOpen = !modelsBox.pickerOpen
                }
                C.ActionButton {
                    compact: true
                    variant: "ghost"
                    iconName: "sync"
                    text: I18n.tr("Fetch models")
                    busyText: I18n.tr("Fetching …")
                    okText: I18n.tr("Loaded")
                    failText: I18n.tr("Failed")
                    enabled: card.d.state !== 1
                    status: card.d.statusSrc === "models" ? (card.d.state || 0) : 0
                    onClicked: Settings.fetchAiProfileModels(card.profileId)
                }
            }

            // the added models, as chips
            Flow {
                Layout.fillWidth: true
                visible: modelsBox.picked.length > 0
                spacing: 6
                layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                Repeater {
                    model: modelsBox.picked
                    Rectangle {
                        id: chip
                        readonly property bool main: modelData === (card.d.model || "")
                        readonly property bool hot: chipHover.containsMouse
                        height: 32
                        width: Math.min(chipRow.implicitWidth + 18, modelsBox.width)
                        radius: 16
                        color: main ? U.withAlpha(card.tint, Theme.isDark ? 0.22 : 0.15)
                             : hot ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.09 : 0.07)
                             : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.04)
                        border.width: 1
                        border.color: main ? U.withAlpha(card.tint, 0.55) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        // under the row, so the × button keeps its own clicks
                        MouseArea {
                            id: chipHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.setAiMainModel(card.profileId, modelData)
                        }
                        C.AppTooltip {
                            visible: chip.hot && !chip.main
                            text: I18n.tr("Click to make this the provider's main model")
                        }
                        Row {
                            id: chipRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            spacing: 6
                            LayoutMirroring.enabled: false
                            C.IconGlyph {
                                visible: chip.main
                                anchors.verticalCenter: parent.verticalCenter
                                name: "star"; fill: true; size: 13
                                glyphColor: card.tint
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: chip.main ? Theme.on_surface : Theme.on_surface_var
                                elide: Text.ElideMiddle
                                width: Math.min(implicitWidth, modelsBox.width - 80)
                            }
                            C.IconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 22; implicitHeight: 22
                                chromeless: true
                                iconName: "close"
                                glyphSize: 13
                                tip: I18n.tr("Remove this model")
                                onClicked: Settings.removeAiModel(card.profileId, modelData)
                            }
                        }
                    }
                }
            }
            C.AppText {
                visible: modelsBox.picked.length === 0
                Layout.fillWidth: true
                text: modelsBox.catalog.length > 0
                      ? I18n.tr("No models added yet. Tick the ones you want in the list below.")
                      : I18n.tr("No models added yet. Press Fetch models to load the list, or type a model id and press Enter.")
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
                wrapMode: Text.WordWrap
            }

            // search the catalogue / type a model id
            C.SmartField {
                id: modelQuery
                Layout.fillWidth: true
                dense: true
                mono: true
                icon: modelsBox.catalog.length > 0 ? "search" : "add"
                placeholder: modelsBox.catalog.length > 0
                             ? I18n.tr("Search the fetched models, or type a model id")
                             : I18n.tr("Type a model id, e.g. gpt-5")
                onEdited: (v) => {
                    modelsBox.query = v
                    if (v.trim() !== "" && modelsBox.catalog.length > 0) modelsBox.pickerOpen = true
                }
                onAccepted: modelsBox.addTyped()
                C.IconButton {
                    visible: modelsBox.typedIsNew
                    iconName: "add"
                    implicitWidth: 32; implicitHeight: 32
                    glyphSize: 16
                    tip: I18n.tr("Add this model")
                    onClicked: modelsBox.addTyped()
                }
            }

            // the fetched catalogue as a tick list
            Rectangle {
                id: pickerBox
                Layout.fillWidth: true
                visible: modelsBox.pickerOpen && modelsBox.catalog.length > 0
                radius: Tokens.radiusMd
                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.035 : 0.03)
                border.width: 1
                border.color: Theme.border
                Layout.preferredHeight: Math.min(272, Math.max(1, modelsBox.shown.length) * 36 + 12)
                implicitHeight: Layout.preferredHeight

                C.AppText {
                    visible: modelsBox.shown.length === 0
                    anchors.centerIn: parent
                    text: I18n.tr("No fetched model matches — press Enter to add it as typed.")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                }
                ListView {
                    id: pickList
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: modelsBox.shown
                    boundsBehavior: Flickable.StopAtBounds
                    reuseItems: true
                    ScrollBar.vertical: ScrollBar { policy: pickList.contentHeight > pickList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool on: modelsBox.isPicked(modelData)
                        width: pickList.width
                        height: 36
                        radius: 9
                        color: rowHover.containsMouse ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.06)
                             : on ? U.withAlpha(card.tint, Theme.isDark ? 0.10 : 0.07)
                             : U.withAlpha(card.tint, 0)
                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.toggleAiModel(card.profileId, row.modelData)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            // checkbox
                            Rectangle {
                                Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                radius: 5
                                color: row.on ? card.tint : U.withAlpha(card.tint, 0)
                                border.width: row.on ? 0 : 1.5
                                border.color: Theme.border_med
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    visible: row.on
                                    name: "check"; size: 13
                                    glyphColor: "white"
                                }
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                text: row.modelData
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: row.on ? Theme.on_surface : Theme.on_surface_var
                                elide: Text.ElideMiddle
                            }
                            C.IconGlyph {
                                visible: row.modelData === (card.d.model || "")
                                name: "star"; fill: true; size: 13
                                glyphColor: card.tint
                            }
                        }
                    }
                }
            }

            // add every match of the current search in one go
            RowLayout {
                Layout.fillWidth: true
                visible: pickerBox.visible && modelsBox.query.trim() !== ""
                         && modelsBox.shown.length > 1 && modelsBox.shown.length <= 50
                Item { Layout.fillWidth: true }
                C.ActionButton {
                    compact: true
                    variant: "ghost"
                    iconName: "add"
                    text: I18n.tr("Add all {n} matches").replace("{n}", modelsBox.shown.length)
                    onClicked: Settings.addAiModels(card.profileId, modelsBox.shown)
                }
            }
        }
        C.AppText {
            visible: card.d.statusSrc === "models" && String(card.d.status || "") !== ""
            Layout.fillWidth: true
            Layout.topMargin: -Tokens.space2
            text: card.d.status || ""
            color: card.d.state === 3 ? Theme.error : card.d.state === 2 ? Theme.secondary_container : Theme.outline
            font.pixelSize: Tokens.fontCaption
            wrapMode: Text.WordWrap
        }

        // endpoint preview
        Rectangle {
            Layout.fillWidth: true
            radius: Tokens.radiusMd
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.04 : 0.035)
            border.width: 1
            border.color: Theme.border
            implicitHeight: 40
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space3
                anchors.rightMargin: 4
                spacing: Tokens.space2
                LayoutMirroring.enabled: false
                Rectangle {
                    radius: 6
                    color: U.withAlpha(card.tint, 0.16)
                    implicitWidth: postTxt.implicitWidth + 12
                    implicitHeight: 20
                    C.AppText { id: postTxt; anchors.centerIn: parent; text: "POST"; mono: true; weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: card.tint }
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: card.d.endpoint || ""
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    elide: Text.ElideMiddle
                }
                C.IconButton {
                    implicitWidth: 32; implicitHeight: 32
                    chromeless: true
                    iconName: "content_copy"
                    glyphSize: 14
                    tip: I18n.tr("Copy")
                    onClicked: Settings.copyToClipboard(card.d.endpoint || "")
                }
            }
        }

        // actions
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            spacing: Tokens.space2
            C.ActionButton {
                visible: card.d.active !== true
                compact: true
                variant: "ghost"
                iconName: "star"
                text: I18n.tr("Make default")
                onClicked: Settings.setAiActive(card.profileId)
            }
            C.ActionButton {
                compact: true
                variant: "ghost"
                iconName: "content_copy"
                text: I18n.tr("Duplicate")
                onClicked: Settings.duplicateAiProfile(card.profileId)
            }
            C.ActionButton {
                visible: !card.custom
                compact: true
                variant: "ghost"
                iconName: "tune"
                text: card.advanced ? I18n.tr("Hide connection") : I18n.tr("Connection")
                onClicked: card.advanced = !card.advanced
            }
            Item { Layout.fillWidth: true }
            C.ActionButton {
                visible: card.custom
                compact: true
                variant: "ghost"
                iconName: "delete_outline"
                text: card.confirmRemove ? I18n.tr("Click again to remove") : I18n.tr("Remove")
                onClicked: {
                    if (card.confirmRemove) Settings.removeAiProfile(card.profileId)
                    else { card.confirmRemove = true; disarm.restart() }
                }
                Timer { id: disarm; interval: 3000; onTriggered: card.confirmRemove = false }
            }
        }
    }
}
