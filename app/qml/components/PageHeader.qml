import QtQuick
import QtQuick.Layouts
import NicheScope
import "." as C

// A page's leading heading: a red icon tile, the title + subtitle, and an
// optional trailing slot for page actions. Every top-level page uses this so the
// tile + title rhythm is identical across the app.
//
//     C.PageHeader {
//         iconName: "history"
//         title: I18n.tr("History")
//         subtitle: I18n.tr("Review or open past extraction exports.")
//         // trailing controls go straight inside — they fill the `actions` slot:
//         C.PrimaryButton { text: "…" }
//     }
RowLayout {
    id: root
    property string iconName: ""
    property string title: ""
    property string subtitle: ""
    // Default children land in the trailing actions row (right-aligned).
    default property alias actions: actionsRow.data

    Layout.fillWidth: true
    spacing: Tokens.space4

    // v4: a lit gradient tile with a slowly breathing halo — the page's
    // one "light source", which the page wash above it (GridFade) echoes.
    C.IconTile {
        size: 48
        glyphSize: 24
        radius: Tokens.radiusMd + 1
        solid: true
        breathe: true
        lit: tileHover.hovered
        iconName: root.iconName
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 48
        Layout.preferredHeight: 48
        HoverHandler { id: tileHover }
    }

    ColumnLayout {
        spacing: 1
        Layout.fillWidth: true
        C.AppText {
            text: root.title
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontDisplay
            color: Theme.text_strong
        }
        C.AppText {
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.on_surface_var
            font.pixelSize: Tokens.fontLabel
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }

    RowLayout {
        id: actionsRow
        Layout.alignment: Qt.AlignVCenter
        spacing: Tokens.space2
    }
}
