import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// Two numeric inputs sharing one bordered box with a dash between them — the
// "100 – 3,000" range control from the reference design. Each side is a plain
// TextField; the box lights its border on focus. Values are strings (they may
// carry "1M"/"3k" shorthand the VM parses), so no numeric coercion here.
Column {
    id: root
    property string label: ""
    property string labelIcon: ""
    property alias minText: minField.text
    property alias maxText: maxField.text
    property string minPlaceholder: "min"
    property string maxPlaceholder: "max"
    // Idle border colour — overridable so a section (e.g. the Niche Finder
    // advanced filters) can request a slightly stronger, more visible border.
    property color borderColor: Theme.border
    // Soft bottom drop shadow — opt-in so it only shows where a section wants
    // its fields to read as raised cards.
    property bool shadow: false
    signal minEdited(string v)
    signal maxEdited(string v)
    spacing: Tokens.space2

    Row {
        spacing: Tokens.space2
        visible: root.label !== ""
        IconGlyph {
            name: root.labelIcon
            visible: root.labelIcon !== ""
            size: 14
            glyphColor: Theme.on_surface_var
            anchors.verticalCenter: parent.verticalCenter
        }
        AppText {
            text: root.label
            mono: false
            weight: Tokens.weightDemiBold
            font.pixelSize: Tokens.fontCaption
            color: Theme.on_surface_var
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        width: parent.width
        height: Tokens.fieldHeight
        radius: Tokens.radiusMd
        color: Theme.input_bg
        border.width: 1
        border.color: (minField.activeFocus || maxField.activeFocus) ? Theme.primary : root.borderColor
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

        // Soft downward shadow, opt-in via `shadow`.
        layer.enabled: root.shadow && height > 0 && height <= 4096
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.40 : 0.12)
            shadowVerticalOffset: 4
            shadowBlur: 0.5
            shadowScale: 1.0
        }

        Row {
            anchors.fill: parent
            TextField {
                id: minField
                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                T.ContextMenu.menu: EditMenu { editor: minField }
                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                selectedTextColor: Theme.text_strong
                width: (parent.width - dash.width) / 2
                height: parent.height
                placeholderText: root.minPlaceholder
                placeholderTextColor: Theme.outline
                color: Theme.on_surface
                font.family: Fonts.body
                font.pixelSize: Tokens.fontBody
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhPreferNumbers
                selectByMouse: true
                background: null
                onTextChanged: root.minEdited(text)
            }
            AppText {
                id: dash
                text: "–"
                width: 14
                height: parent.height
                color: Theme.outline
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            TextField {
                id: maxField
                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                T.ContextMenu.menu: EditMenu { editor: maxField }
                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                selectedTextColor: Theme.text_strong
                width: (parent.width - dash.width) / 2
                height: parent.height
                placeholderText: root.maxPlaceholder
                placeholderTextColor: Theme.outline
                color: Theme.on_surface
                font.family: Fonts.body
                font.pixelSize: Tokens.fontBody
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhPreferNumbers
                selectByMouse: true
                background: null
                onTextChanged: root.maxEdited(text)
            }
        }
    }
}
