import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// AiRoutingPanel — "which AI does what" (Settings v19).
//
//   ┌ Idea generation ─────────────────────────────────────────────────┐
//   │ [💡] AI Ideas and Content Lab blueprints                          │
//   │ PROVIDER [OpenRouter ▾]   MODEL [openai/gpt-5 ▾]                  │
//   │ EFFORT   [Auto | ▂ Low | ▂▄ Med | ▂▄▆ High | ▂▄▆█ Max]            │
//   └──────────────────────────────────────────────────────────────────┘
//
// One row per feature. "Default" follows the default provider; picking a
// profile pins that feature to it (and, optionally, to one of its models), so
// e.g. ideas always come from the strong model while chat stays on a cheap one.
// Effort is per feature too; the AI Chat composer edits the same "chat" value.
ColumnLayout {
    id: root
    spacing: Tokens.space3
    Layout.fillWidth: true

    property var choices: []
    function syncChoices() {
        var c = Settings.aiRouteChoices || []
        if (JSON.stringify(c) !== JSON.stringify(choices)) choices = c
    }
    Connections { target: Settings; function onAiDataChanged() { root.syncChoices() } }
    Component.onCompleted: syncChoices()
    readonly property var choiceLabels: choices.map(function (c) { return c.label })
    readonly property var choiceIcons: choices.map(function (c) { return c.glyph })

    Repeater {
        model: (Settings.aiRoutes || []).length
        delegate: Rectangle {
            id: row
            readonly property var r: (Settings.aiRoutes || [])[index] || ({})
            Layout.fillWidth: true
            radius: Tokens.radiusLg
            color: rowHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
            border.width: 1
            border.color: row.r.ready === false ? U.withAlpha(Theme.warn, 0.45) : Theme.border
            implicitHeight: rCol.implicitHeight + Tokens.space4 * 2
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            HoverHandler { id: rowHover }

            ColumnLayout {
                id: rCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.space4
                spacing: Tokens.space3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    Rectangle {
                        Layout.preferredWidth: 34; Layout.preferredHeight: 34
                        radius: 10
                        color: U.withAlpha(Theme.tertiary, Theme.isDark ? 0.16 : 0.10)
                        C.IconGlyph { anchors.centerIn: parent; name: row.r.icon || "psychology"; size: 17; glyphColor: Theme.tertiary }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        C.AppText { text: row.r.title || ""; weight: Tokens.weightBold; color: Theme.text_strong }
                        C.AppText { text: row.r.sub || ""; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    // what it resolves to right now
                    Rectangle {
                        radius: Tokens.radiusPill
                        color: row.r.ready === false ? U.withAlpha(Theme.warn, 0.12) : U.withAlpha(Theme.secondary_container, 0.12)
                        implicitWidth: resRow.implicitWidth + 16
                        implicitHeight: 26
                        Layout.maximumWidth: 300
                        clip: true
                        Row {
                            id: resRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.IconGlyph { anchors.verticalCenter: parent.verticalCenter; name: row.r.ready === false ? "warning" : "check_circle"; size: 13; glyphColor: row.r.ready === false ? Theme.warn : Theme.secondary_container }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.r.ready === false ? I18n.tr("{p} is not set up").replace("{p}", row.r.resolvedName || "")
                                                            : (row.r.resolvedName || "") + " · " + (row.r.resolvedModel || "")
                                mono: row.r.ready !== false
                                font.pixelSize: Tokens.fontMicro + 1
                                color: Theme.text_strong
                                width: Math.min(implicitWidth, 260)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.width >= 720 ? 3 : 1
                    columnSpacing: Tokens.space3
                    rowSpacing: Tokens.space3

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        spacing: 6
                        C.AppText { text: I18n.tr("PROVIDER"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: Theme.on_surface_var }
                        C.Dropdown {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            model: root.choiceLabels
                            icons: root.choiceIcons
                            currentIndex: {
                                for (var i = 0; i < root.choices.length; i++)
                                    if (root.choices[i].id === (row.r.profile || "")) return i
                                return 0
                            }
                            onActivated: Settings.setAiRoute(row.r.feature, "profile", (root.choices[currentIndex] || {}).id || "")
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        spacing: 6
                        C.AppText { text: I18n.tr("MODEL"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: Theme.on_surface_var }
                        C.Dropdown {
                            id: rModel
                            Layout.fillWidth: true
                            implicitHeight: 44
                            editable: true
                            property var stable: []
                            model: stable
                            function sync() {
                                var m = [I18n.tr("Provider's model")].concat(row.r.models || [])
                                if (JSON.stringify(m) !== JSON.stringify(stable)) {
                                    stable = m
                                    Qt.callLater(function () { if (!rModel.activeFocus) rModel.editText = row.r.model || I18n.tr("Provider's model") })
                                }
                            }
                            Connections { target: Settings; function onAiDataChanged() { rModel.sync() } }
                            Component.onCompleted: { sync(); editText = row.r.model || I18n.tr("Provider's model") }
                            function commit(t) {
                                t = String(t || "").trim()
                                Settings.setAiRoute(row.r.feature, "model", t === I18n.tr("Provider's model") ? "" : t)
                            }
                            onActivated: commit(currentIndex === 0 ? "" : stable[currentIndex])
                            onAccepted: commit(editText)
                            onActiveFocusChanged: if (!activeFocus) commit(editText)
                            Binding { target: rModel; property: "editText"; value: row.r.model || I18n.tr("Provider's model"); when: !rModel.activeFocus; restoreMode: Binding.RestoreNone }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 3
                        spacing: 6
                        C.AppText { text: I18n.tr("EFFORT"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontMicro; color: Theme.on_surface_var }
                        C.EffortPicker {
                            Layout.fillWidth: true
                            compact: true
                            options: Settings.effortOptions
                            value: row.r.effort || "auto"
                            onPicked: (v) => Settings.setAiRoute(row.r.feature, "effort", v)
                        }
                    }
                }
            }
        }
    }
}
