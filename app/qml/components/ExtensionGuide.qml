import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// ═══════════════════════════════════════════════════════════════════════
//  v3.43 — the browser-extension install guide (shared)
// ═══════════════════════════════════════════════════════════════════════
//
// Used twice: inside the first-run dialog (ExtensionSetupDialog) and inline
// in Settings → Browser extension, so the steps can always be found again
// after "Skip for now".
//
// The steps match what Chrome really does (checked against its UI):
//   1  chrome://extensions can't be opened by another program, so the button
//      starts the browser AND copies the address; the user pastes it.
//   2  Developer mode is a switch at the top of that page (right corner; the
//      left one when Chrome runs in Persian). Edge: left sidebar, bottom.
//   3  "Load unpacked" (shown only after step 2) → pick the FOLDER → Select
//      Folder. Dragging the folder onto the page does the same thing.
//   4  Refresh YouTube tabs that were already open (Chrome only injects into
//      pages loaded after the install).
// The extension pings the app as soon as it is installed; the status line
// turns green by itself.
ColumnLayout {
    id: g
    spacing: Tokens.space4

    property bool _openedBrowser: false
    property bool _browserFailed: false
    property bool _urlCopied: false
    property bool _pathCopied: false
    readonly property bool done: ExtensionSetup.connected

    function reset() {
        _openedBrowser = false; _browserFailed = false
        _urlCopied = false; _pathCopied = false
    }

    // ── one numbered step ──
    component Step: RowLayout {
        id: st
        property int num: 1
        property string label: ""
        property string hint: ""
        property bool done: false
        default property alias extra: extraCol.data
        spacing: 14
        Layout.fillWidth: true
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 15
            color: U.withAlpha(st.done ? Theme.secondary_container : Theme.primary, 0.14)
            border.width: 1
            border.color: U.withAlpha(st.done ? Theme.secondary_container : Theme.primary, 0.45)
            C.AppText {
                anchors.centerIn: parent
                visible: !st.done
                text: st.num
                weight: Tokens.weightBold
                color: Theme.text_strong
            }
            C.IconGlyph {
                anchors.centerIn: parent
                visible: st.done
                name: "check"; size: 16
                glyphColor: Theme.secondary_container
            }
        }
        ColumnLayout {
            id: extraCol
            Layout.fillWidth: true
            spacing: 6
            C.AppText {
                text: st.label
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontLabel
                color: Theme.text_strong
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            C.AppText {
                visible: st.hint !== ""
                text: st.hint
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                lineHeight: 1.25
                Layout.fillWidth: true
            }
        }
    }

    // a monospace "thing to paste" chip with its own copy button
    component CopyChip: Rectangle {
        id: cc
        property string value: ""
        property bool copied: false
        signal copy()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Tokens.radiusMd
        color: Theme.surface_high
        border.width: 1
        border.color: Theme.outline_variant
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space3
            anchors.rightMargin: 4
            spacing: Tokens.space2
            C.AppText {
                text: cc.value
                mono: true
                font.pixelSize: Tokens.fontCaption
                color: Theme.text_strong
                elide: Text.ElideMiddle
                Layout.fillWidth: true
                // paths / URLs read left-to-right even in Persian
                horizontalAlignment: Text.AlignLeft
                LayoutMirroring.enabled: false
            }
            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: ccRow.implicitWidth + 16
                radius: Tokens.radiusSm
                color: ccArea.pressed ? Theme.hover_bg_strong : ccArea.containsMouse ? Theme.hover_bg : "transparent"
                Row {
                    id: ccRow
                    anchors.centerIn: parent
                    spacing: 5
                    C.IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        name: cc.copied ? "check" : "content_copy"; size: 13
                        glyphColor: cc.copied ? Theme.secondary_container : Theme.on_surface_var
                    }
                    C.AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cc.copied ? I18n.tr("Copied") : I18n.tr("Copy")
                        font.pixelSize: Tokens.fontCaption
                        weight: Tokens.weightDemiBold
                        color: Theme.text_strong
                    }
                }
                MouseArea {
                    id: ccArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cc.copy()
                }
            }
        }
    }

    // ── 1 ──
    Step {
        num: 1
        done: g._openedBrowser || g.done
        label: I18n.tr("Open the extensions page")
        hint: I18n.tr("{b} doesn't let other apps open this page, so the address is copied for you. In the {b} window: click the address bar, press Ctrl+V, then Enter.")
              .split("{b}").join(ExtensionSetup.browser)
        RowLayout {
            Layout.topMargin: 4
            Layout.fillWidth: true
            spacing: Tokens.space2
            C.PrimaryButton {
                variant: g._openedBrowser ? "ghost" : "primary"
                iconName: "open_in_new"
                text: I18n.tr("Open {b}").replace("{b}", ExtensionSetup.browser)
                onClicked: {
                    g._browserFailed = !ExtensionSetup.openExtensionsPage()
                    g._openedBrowser = true
                    g._urlCopied = true
                    g._pathCopied = false
                }
            }
            CopyChip {
                value: ExtensionSetup.extensionsUrl
                copied: g._urlCopied
                onCopy: { g._urlCopied = ExtensionSetup.copyExtensionsUrl(); g._pathCopied = false }
            }
        }
        C.AppText {
            visible: g._browserFailed
            text: I18n.tr("{b} wasn't found. Open your browser yourself and paste the address.").replace("{b}", ExtensionSetup.browser)
            font.pixelSize: Tokens.fontCaption
            color: Theme.warn
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // ── 2 ──
    Step {
        num: 2
        done: g.done
        label: I18n.tr("Turn on “Developer mode”")
        hint: ExtensionSetup.isEdge
              ? I18n.tr("In the left sidebar of that page, near the bottom.")
              : I18n.tr("The switch at the top of that page: right corner (left corner if your browser is in Persian). New buttons appear under it.")
    }

    // ── 3 ──
    Step {
        num: 3
        done: g.done
        label: I18n.tr("Load the extension folder")
        hint: I18n.tr("Click “Load unpacked” (the first new button), go to the folder below and press “Select Folder”. Select the folder itself, don't open a file inside it. Quicker: drag the folder card below onto the extensions page.")

        Rectangle {
            id: folderCard
            visible: ExtensionSetup.available
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: folderRow.implicitHeight + Tokens.space3 * 2
            radius: Tokens.radiusMd
            color: folderDrag.active ? U.withAlpha(Theme.primary, 0.16)
                 : folderHover.hovered ? Theme.surface_high : U.withAlpha(Theme.surface_high, 0.7)
            border.width: 1
            border.color: folderHover.hovered ? U.withAlpha(Theme.primary, 0.55) : Theme.outline_variant
            Behavior on color { ColorAnimation { duration: Tokens.durFast } }
            RowLayout {
                id: folderRow
                anchors.fill: parent
                anchors.margins: Tokens.space3
                spacing: Tokens.space2
                C.IconGlyph { name: "folder"; fill: true; size: 22; glyphColor: Theme.primary }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.AppText {
                        text: "browser-extension"
                        weight: Tokens.weightBold
                        color: Theme.text_strong
                    }
                    C.AppText {
                        text: ExtensionSetup.folder
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.on_surface_var
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignLeft
                    }
                }
                C.AppText {
                    text: I18n.tr("drag me")
                    font.pixelSize: Tokens.fontMicro
                    weight: Tokens.weightDemiBold
                    color: Theme.on_surface_var
                }
            }
            HoverHandler { id: folderHover; cursorShape: Qt.OpenHandCursor }
            DragHandler {
                id: folderDrag
                target: null
                dragThreshold: 8
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onActiveChanged: if (active) ExtensionSetup.dragFolder()
            }
        }
        RowLayout {
            visible: ExtensionSetup.available
            spacing: Tokens.space2
            C.PrimaryButton {
                variant: "ghost"
                iconName: g._pathCopied ? "check" : "content_copy"
                text: g._pathCopied ? I18n.tr("Path copied") : I18n.tr("Copy folder path")
                onClicked: { g._pathCopied = ExtensionSetup.copyPath(); g._urlCopied = false }
            }
            C.PrimaryButton {
                variant: "ghost"
                iconName: "folder_open"
                text: I18n.tr("Show folder")
                onClicked: ExtensionSetup.openFolder()
            }
        }
        C.AppText {
            visible: ExtensionSetup.available
            text: I18n.tr("Tip: in the “Select Folder” window, paste the copied path into the bar at the top and press Enter.")
            font.pixelSize: Tokens.fontMicro
            color: Theme.on_surface_var
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        C.AppText {
            visible: !ExtensionSetup.available
            text: I18n.tr("The browser-extension folder isn't next to the app. Reinstall YouTube Hunter to get it back.")
            font.pixelSize: Tokens.fontCaption
            color: Theme.warn
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // ── 4 ──
    Step {
        num: 4
        done: g.done
        label: I18n.tr("Refresh YouTube")
        hint: I18n.tr("Press F5 on any YouTube tab that was already open. The Hunter button sits next to Like and Share; on Shorts it's at the top of the right-hand buttons.")
    }

    // v3.49: escape hatch if the browser never reaches the app (firewall,
    // app closed during install): one tap to say "it's installed".
    RowLayout {
        visible: !g.done
        Layout.fillWidth: true
        spacing: Tokens.space2
        C.AppText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: I18n.tr("Already installed and it still says waiting? Open or refresh any YouTube tab once; that wakes the extension up.")
            font.pixelSize: Tokens.fontCaption
            color: Theme.on_surface_var
        }
        C.PrimaryButton { variant: "ghost"; text: I18n.tr("Mark as connected"); onClicked: ExtensionSetup.markConnected() }
    }

    // live status: waits for the extension's first ping
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        radius: Tokens.radiusMd
        readonly property color tone: g.done ? Theme.secondary_container : Theme.primary
        color: U.withAlpha(tone, 0.10)
        border.width: 1
        border.color: U.withAlpha(tone, 0.28)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space3
            anchors.rightMargin: Tokens.space3
            spacing: Tokens.space2
            Rectangle {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                color: parent.parent.tone
                SequentialAnimation on opacity {
                    running: !g.done && g.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            C.AppText {
                text: g.done
                      ? I18n.tr("Connected. Open any YouTube video, the Hunter button is next to Share.")
                      : I18n.tr("Waiting for the extension… this turns green by itself after step 3.")
                font.pixelSize: Tokens.fontCaption
                weight: Tokens.weightDemiBold
                color: Theme.text_strong
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}
