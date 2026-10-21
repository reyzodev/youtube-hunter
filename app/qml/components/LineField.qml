import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// Themed single-line text field with an optional leading icon and a floating
// label row above it (matches the legacy field_label + make_lineedit pair).
//
// Set `hint` and the label gets a small (?) that explains the field on hover —
// for anything carrying a unit, a limit or a format the label alone can't state.
Column {
    id: root
    property string label: ""
    property string labelIcon: ""
    property string placeholder: ""
    property string hint: ""
    property alias text: field.text
    property alias readOnly: field.readOnly
    property alias echoMode: field.echoMode
    // Focus/selection passthroughs for dialogs that open a LineField primed to
    // type over (the Archive rename box).
    function forceActiveFocus() { field.forceActiveFocus() }
    function selectAll() { field.selectAll() }
    // Idle border colour — overridable so a section can request a stronger,
    // more visible border than the default hairline.
    property color borderColor: Theme.border
    // Transparent variant: no filled input well, just a 1px hairline. Used on
    // the Scraper form so the fields read as outlines on the card rather than
    // as separate grey blocks.
    property bool transparentBg: false
    // Soft bottom drop shadow — opt-in so it only shows where a section wants
    // its fields to read as raised cards.
    property bool shadow: false
    // Enter/Return inside the field. Forwarded from the inner TextField so a
    // page can wire a search button's action to the keyboard as well.
    signal accepted()
    spacing: Tokens.space2

    Row {
        spacing: Tokens.space2
        visible: root.label !== ""
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
        // hint marker — only present when there is something to say
        Item {
            visible: root.hint !== ""
            width: 15; height: 15
            anchors.verticalCenter: parent.verticalCenter
            IconGlyph {
                anchors.centerIn: parent
                name: "help"
                size: 13
                glyphColor: hintHover.hovered ? Theme.primary : Theme.outline
                Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
            HoverHandler { id: hintHover }
            AppTooltip {
                visible: hintHover.hovered
                text: root.hint
            }
        }
    }

    TextField {
        id: field
        // v3.40.1 — premium right-click menu (replaces Qt's stock one)
        T.ContextMenu.menu: EditMenu { editor: field }
        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
        selectedTextColor: Theme.text_strong
        width: parent.width
        height: Tokens.fieldHeight
        placeholderText: root.placeholder
        placeholderTextColor: Theme.outline
        color: Theme.on_surface
        font.family: Fonts.body
        font.pixelSize: Tokens.fontBody
        leftPadding: Tokens.space4
        rightPadding: Tokens.space4
        selectByMouse: true
        verticalAlignment: TextInput.AlignVCenter
        onAccepted: root.accepted()

        // Hover feedback matters most in the transparent style: with no fill, the
        // border is the only "this is interactive" signal at rest, so a plain
        // border alone gives the pointer nothing to land on.
        HoverHandler {
            id: fieldHover
            cursorShape: field.readOnly ? Qt.ArrowCursor : Qt.IBeamCursor
        }

        background: Rectangle {
            radius: Tokens.radiusMd
            // Read-only fields invert the treatment on purpose: they get a soft
            // fill and NO border, so they read as "a value being shown" rather
            // than "a box you type in". (Save Location looked identical to the
            // editable fields before this.)
            color: {
                if (root.transparentBg && field.readOnly)
                    return U.withAlpha(Theme.on_surface, 0.05)
                if (root.transparentBg)
                    return fieldHover.hovered && !field.activeFocus
                           ? U.withAlpha(Theme.on_surface, 0.04) : "transparent"
                return Theme.input_bg
            }
            // Focus ring stays a 1px hairline — the same weight as the idle
            // border, so gaining focus recolours the outline instead of also
            // thickening it. A width change nudges the field's inner content by a
            // pixel on every focus/blur, which reads as a twitch.
            border.width: 1
            border.color: {
                if (field.activeFocus) return Theme.primary
                if (root.transparentBg && field.readOnly) return "transparent"
                if (root.transparentBg)
                    // 0.32 at rest clears the 3:1 contrast floor WCAG asks of a
                    // component boundary; 0.20 (the first pass) sat near 1.6:1
                    // and washed out in bright light.
                    return U.withAlpha(Theme.on_surface,
                                       fieldHover.hovered ? 0.45 : 0.32)
                return root.borderColor
            }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

            // v4 focus halo: a soft 3px accent ring OUTSIDE the hairline, so
            // focus reads at a glance without the border itself changing
            // weight (see the note above). Skipped on the shadow variant,
            // whose layer would clip anything outside the field's bounds.
            Rectangle {
                visible: !root.shadow
                anchors.fill: parent
                anchors.margins: -3
                radius: parent.radius + 3
                color: "transparent"
                border.width: 3
                border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.22 : 0.16)
                opacity: field.activeFocus && !field.readOnly ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }

            // Soft downward shadow, opt-in via `shadow`.
            layer.enabled: root.shadow && height > 0 && height <= 4096
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.40 : 0.12)
                shadowVerticalOffset: 4
                shadowBlur: 0.5
                shadowScale: 1.0
            }
        }
    }
}
