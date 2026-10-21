import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.43 "Add the download button to YouTube": first-run dialog around the
// shared ExtensionGuide. Opens itself once; "Skip for now" stops that, and
// Settings → Browser extension always has the same guide inline.
Dialog {
    id: root
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(600, (parent ? parent.width : 900) - 80)
    height: Math.min(implicitHeight, (parent ? parent.height : 800) - 80)
    padding: 0
    closePolicy: Popup.CloseOnEscape

    function present() {
        guide.reset()
        ExtensionSetup.markOffered()
        open()
    }

    Connections {
        target: ExtensionSetup
        function onConnectedNow() { if (root.opened) closeLater.restart() }
    }
    Timer { id: closeLater; interval: 2200; onTriggered: root.close() }

    Overlay.modal: C.DialogScrim { }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }

    background: Rectangle {
        radius: Tokens.radiusXl
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    header: Item {
        implicitHeight: headCol.implicitHeight + Tokens.space5 * 2
        ColumnLayout {
            id: headCol
            anchors.fill: parent
            anchors.margins: Tokens.space5
            spacing: 6
            RowLayout {
                spacing: Tokens.space3
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.primary, 0.14)
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.30)
                    C.IconGlyph { anchors.centerIn: parent; name: "extension"; fill: true; size: 22; glyphColor: Theme.primary }
                }
                C.AppText {
                    text: I18n.tr("Add the download button to YouTube")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontTitle
                    color: Theme.text_strong
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
            C.AppText {
                text: I18n.tr("One time, about a minute. You can also do it later from Settings → Browser extension.")
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    contentItem: Flickable {
        implicitHeight: guide.implicitHeight
        contentHeight: guide.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        C.ExtensionGuide {
            id: guide
            x: Tokens.space5
            width: parent.width - Tokens.space5 * 2
        }
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
            C.PrimaryButton {
                visible: !ExtensionSetup.connected
                variant: "ghost"
                text: I18n.tr("Skip for now")
                onClicked: { ExtensionSetup.skip(); root.close() }
            }
            Item { Layout.fillWidth: true }
            C.PrimaryButton {
                variant: ExtensionSetup.connected ? "primary" : "ghost"
                text: ExtensionSetup.connected ? I18n.tr("Done") : I18n.tr("Close")
                onClicked: root.close()
            }
        }
    }
}
