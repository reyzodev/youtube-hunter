import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import NicheScope
import "../Utils.js" as U

// Themed multi-line text field with an optional label row above it — the
// multi-line counterpart to LineField, for anywhere a user writes a paragraph
// rather than a value (the AI Ideas brief being the first).
//
// The height is fixed by `rows` rather than growing with the content: this sits
// inside a scrolling page, and a field that grows pushes everything below it
// around while you type. It scrolls internally instead.
Column {
    id: root
    property string label: ""
    property string labelIcon: ""
    property string placeholder: ""
    property alias text: field.text
    property alias readOnly: field.readOnly
    property int rows: 4
    // Idle border colour — overridable so a section can ask for a stronger
    // border than the default hairline.
    property color borderColor: Theme.border
    // Optional soft cap shown as a live counter. 0 disables it.
    property int softLimit: 0

    // Focus the editor and park the caret at the end — used by the AI Ideas
    // "starter" chips after they append a prompt line.
    function focusEnd() {
        field.forceActiveFocus()
        field.cursorPosition = field.length
    }

    spacing: Tokens.space2

    // Label row: the icon+label group on the left, the counter pinned right.
    //
    // This is an Item with anchored children rather than a Row with a flexible
    // spacer. A spacer sized `root.width - x - counter.width` depends on its own
    // `x`, which the Row derives from the widths before it — a genuine layout
    // cycle, which Qt reported as "Row called polish() inside updatePolish()".
    Item {
        width: parent.width
        visible: root.label !== ""
        height: visible ? Math.max(labelRow.implicitHeight, counter.implicitHeight) : 0

        Row {
            id: labelRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.space2
            IconGlyph {
                name: root.labelIcon
                visible: root.labelIcon !== ""
                size: 15
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

        AppText {
            id: counter
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.softLimit > 0
            text: field.text.length + " / " + root.softLimit
            mono: true
            font.pixelSize: Tokens.fontCaption
            // Turns amber once over the soft cap: the request still goes
            // through, it just costs more tokens and dilutes the brief.
            color: field.text.length > root.softLimit ? Theme.warn : Theme.outline
        }
    }

    Rectangle {
        width: parent.width
        // Line height ≈ 1.45× the font size, plus the vertical padding.
        height: Math.ceil(Tokens.fontBody * 1.45) * root.rows + Tokens.space4 * 2
        radius: Tokens.radiusMd
        color: Theme.input_bg
        border.width: 1
        border.color: field.activeFocus ? Theme.primary : root.borderColor
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 1
            clip: true

            TextArea {
                id: field
                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                T.ContextMenu.menu: EditMenu { editor: field }
                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                selectedTextColor: Theme.text_strong
                placeholderText: root.placeholder
                placeholderTextColor: Theme.outline
                color: Theme.on_surface
                font.family: Fonts.body
                font.pixelSize: Tokens.fontBody
                wrapMode: TextArea.Wrap
                selectByMouse: true
                leftPadding: Tokens.space4
                rightPadding: Tokens.space4
                topPadding: Tokens.space4
                bottomPadding: Tokens.space4
                // The bordered Rectangle above is the visible frame; the inner
                // TextArea must not draw a second one.
                background: null
            }
        }
    }
}
