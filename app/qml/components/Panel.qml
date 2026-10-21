import QtQuick
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// The Usage page's card surface — the template's rounded-2xl panel with a
// hairline border and a red-tinted shadow that lifts a touch on hover.
//
// Wraps GlassPanel (which already carries the crisp, non-rasterised drop
// shadow) and adds: an optional header row (icon + title + right-aligned hint),
// an eyebrow-only caption for the stat cards, and the hover lift. Children are
// laid into a ColumnLayout below the header via the default property, so a
// caller just drops content inside like any Item.
C.GlassPanel {
    id: root

    // Header: a title with an optional leading icon and trailing hint. Leave
    // `heading` empty for a card that manages its own header (stat cards use
    // `eyebrow` instead).
    property string heading: ""
    property string hint: ""
    property string headIcon: ""
    // Small uppercase label for the stat-card variant (no full header row).
    property string eyebrow: ""
    property string eyebrowIcon: ""
    property bool hoverLift: true
    property alias content: body.data

    radius_: Tokens.radiusXl
    Layout.fillWidth: true

    // Hover feedback — a slightly stronger shadow only. An earlier version also
    // translated the card up by a couple of px (`y: -2`), but these panels live
    // inside GridLayouts, which own their children's `y`; setting `y` here
    // fought the layout, so the card jumped up and stayed there ("goes up and
    // sticks") and could overlap the row above. Elevation alone gives the lift
    // feel without touching geometry the layout controls.
    HoverHandler { id: hh }
    hoverGlow: hoverLift
    elevation: (hoverLift && hh.hovered) ? 1.6 : 1.0
    Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }

    implicitHeight: inner.implicitHeight + Tokens.space5 * 2

    ColumnLayout {
        id: inner
        anchors.fill: parent
        anchors.margins: Tokens.space5
        spacing: Tokens.space3

        // full header row
        RowLayout {
            Layout.fillWidth: true
            visible: root.heading !== ""
            spacing: Tokens.space2
            C.IconGlyph {
                visible: root.headIcon !== ""
                name: root.headIcon
                size: 16
                glyphColor: Theme.primary
                Layout.alignment: Qt.AlignVCenter
            }
            C.AppText {
                text: root.heading
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontSubtitle
                color: Theme.text_strong
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            C.AppText {
                visible: root.hint !== ""
                text: root.hint
                mono: true
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // eyebrow-only row (stat cards)
        RowLayout {
            Layout.fillWidth: true
            visible: root.eyebrow !== ""
            spacing: Tokens.space2
            C.AppText {
                text: root.eyebrow
                mono: true
                weight: Tokens.weightDemiBold
                font.pixelSize: 11
                color: Theme.on_surface_var
                Layout.fillWidth: true
            }
            C.IconGlyph {
                visible: root.eyebrowIcon !== ""
                name: root.eyebrowIcon
                size: 16
                glyphColor: Theme.primary
            }
        }

        // caller content
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Tokens.space3
        }
    }
}
