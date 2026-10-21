import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v18 Settings field: a "labelled well".
//
//   ┌──────────────────────────────────────────────────────┐
//   │ ┌────┐  PRIMARY KEY                         👁  ⧉   │
//   │ │ 🔑 │  AIzaSy••••••••••••••••••••                    │
//   │ └────┘                                               │
//   └──────────────────────────────────────────────────────┘
//     ✓ Format looks right, validate to be sure.
//
// The label lives INSIDE the box, above the value (the way 2026 desktop
// settings do it), so a form of many fields reads as one calm column instead
// of label / box / label / box. The leading icon sits in its own small well
// that lights up in the accent on focus, the focus ring is a soft outer halo
// (the hairline never thickens, so nothing twitches), and an optional helper
// line underneath carries a tone: "" neutral · "ok" · "warn" · "error".
//
// Trailing children (icon buttons, a spinner, a badge) go straight inside:
//     C.SmartField { label: "Key"; C.IconButton { … } }
Item {
    id: root

    property string label: ""
    property string icon: ""
    property string placeholder: ""
    property string helper: ""
    property string tone: ""            // "" | "ok" | "warn" | "error"
    property bool mono: false
    // dense = no inner label, 46px box. For list rows (backup keys).
    property bool dense: false
    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias readOnly: input.readOnly
    property alias inputItem: input
    default property alias trailing: trail.data

    signal edited(string value)
    signal accepted()

    function forceActiveFocus() { input.forceActiveFocus() }
    function selectAll() { input.selectAll() }

    readonly property bool focused: input.activeFocus
    readonly property bool hovered: boxHover.hovered
    readonly property int boxHeight: root.dense ? 46 : 54
    readonly property color toneColor: root.tone === "ok" ? Theme.secondary_container
                                     : root.tone === "warn" ? Theme.warn
                                     : root.tone === "error" ? Theme.error
                                     : Theme.outline

    Layout.fillWidth: true
    implicitWidth: 280
    implicitHeight: box.height + (helperRow.visible ? helperRow.implicitHeight + 8 : 0)
    opacity: enabled ? 1.0 : 0.5
    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

    // ── focus halo (outside the hairline) ──
    Rectangle {
        x: -4; y: -4
        width: box.width + 8
        height: box.height + 8
        radius: box.radius + 4
        color: "transparent"
        border.width: 4
        border.color: U.withAlpha(root.tone === "error" ? Theme.error : Theme.primary,
                                  Theme.isDark ? 0.20 : 0.14)
        opacity: root.focused && !input.readOnly ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: box
        width: parent.width
        height: root.boxHeight
        radius: root.dense ? 12 : 14
        clip: true
        color: input.readOnly ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.035 : 0.04)
             : root.hovered && !root.focused ? U.hoverTint(Theme.input_bg, Theme.isDark, 0.035)
             : Theme.input_bg
        border.width: 1
        border.color: root.focused ? Theme.primary
                    : root.tone === "error" ? U.withAlpha(Theme.error, 0.55)
                    : root.tone === "warn" ? U.withAlpha(Theme.warn, 0.45)
                    : root.hovered ? Theme.border_med
                    : Theme.border
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

        HoverHandler {
            id: boxHover
            cursorShape: input.readOnly ? Qt.ArrowCursor : Qt.IBeamCursor
        }
        // Clicking anywhere in the well (icon, label, padding) focuses the input.
        TapHandler { onTapped: if (!input.readOnly) input.forceActiveFocus() }

        // accent wash rising from the bottom edge while focused
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height
            radius: parent.radius          // clip: true is square; round the wash itself
            opacity: root.focused ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.045) }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.icon !== "" ? (root.dense ? 7 : 9) : Tokens.space4
            anchors.rightMargin: Tokens.space2
            spacing: Tokens.space3

            // leading icon well
            Rectangle {
                visible: root.icon !== ""
                Layout.preferredWidth: root.dense ? 32 : 36
                Layout.preferredHeight: root.dense ? 32 : 36
                Layout.alignment: Qt.AlignVCenter
                radius: root.dense ? 9 : 10
                color: root.focused ? U.withAlpha(Theme.primary, Theme.isDark ? 0.18 : 0.12)
                     : root.tone === "ok" ? U.withAlpha(Theme.secondary_container, 0.13)
                     : root.tone === "error" ? U.withAlpha(Theme.error, 0.13)
                     : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.055 : 0.05)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: root.icon
                    fill: root.focused
                    size: root.dense ? 15 : 17
                    glyphColor: root.focused ? Theme.primary
                              : root.tone === "ok" ? Theme.secondary_container
                              : root.tone === "error" ? Theme.error
                              : Theme.on_surface_var
                    Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                C.AppText {
                    visible: root.label !== "" && !root.dense
                    text: root.label
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    font.letterSpacing: I18n.rtl ? 0 : 0.5
                    color: root.focused ? Theme.primary : Theme.on_surface_var
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                TextField {
                    id: input
                    // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                    T.ContextMenu.menu: EditMenu { editor: input }
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.dense ? 30 : 24
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    placeholderText: root.placeholder
                    placeholderTextColor: U.withAlpha(Theme.outline, 0.9)
                    color: Theme.text_strong
                    selectionColor: U.withAlpha(Theme.primary, 0.35)
                    selectedTextColor: Theme.text_strong
                    font.family: Fonts.familyFor(root.mono ? "mono" : "body", Tokens.weightMedium, text)
                    font.weight: Fonts.weightFor(Tokens.weightMedium, text)
                    font.pixelSize: root.mono ? Tokens.fontBody : Tokens.fontLabel
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    background: null
                    // A key / URL / path is an opaque LTR token, never RTL prose.
                    LayoutMirroring.enabled: root.mono ? false : I18n.rtl
                    onTextEdited: root.edited(text)
                    onAccepted: root.accepted()
                }
            }

            RowLayout {
                id: trail
                spacing: 2
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ── helper line ──
    RowLayout {
        id: helperRow
        visible: root.helper !== ""
        y: box.height + 8
        width: parent.width
        spacing: 6
        C.IconGlyph {
            visible: root.tone !== ""
            name: root.tone === "ok" ? "check_circle" : root.tone === "error" ? "error" : "warning"
            fill: true
            size: 13
            glyphColor: root.toneColor
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
        }
        C.AppText {
            Layout.fillWidth: true
            text: root.helper
            font.pixelSize: Tokens.fontCaption
            lineHeight: 1.25
            color: root.tone === "" ? Theme.outline : root.toneColor
            wrapMode: Text.WordWrap
        }
    }
}
