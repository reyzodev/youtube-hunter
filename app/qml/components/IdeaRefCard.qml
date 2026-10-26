import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// A selectable reference-video card for the AI Ideas picker (v9).
//
// Deliberately much lighter than ArchiveVideoCard: this grid exists to pick
// from, not to browse. v9 makes the picking itself feel alive:
//
//   • hover lifts the card and drops a scrim over the thumbnail with a clear
//     "+ Add" / "Remove" call to action, so the whole card reads as a button;
//   • a picked card wears an accent ring + glow and its disc shows the PICK
//     ORDER (1, 2, 3 …) instead of a generic check, so the set reads as a set;
//   • the outlier multiplier is the hero stat, top-right, tiered by strength;
//   • the open-on-YouTube action only appears on hover, keeping rest state calm.
Item {
    id: root

    // The flattened row from IdeasVM.rows.
    property var row: ({})
    property real cardWidth: 300
    // 1-based position in the selection (0 = not picked). Optional.
    property int order: 0

    signal toggled(string key)
    signal opened(string url)

    readonly property bool picked: row.selected === true
    // A HoverHandler, not the MouseArea's containsMouse: the open button's own
    // MouseArea would steal hover and make the card drop/lift under the cursor.
    readonly property bool hovered: cardHover.hovered
    HoverHandler { id: cardHover }
    // "5.5Kx" / "3.1x" → 5500 / 3.1, for tiering the badge
    readonly property real multValue: {
        const t = String(root.row.multiplier || "").replace(/x$/i, "").trim()
        let k = 1
        let n = t
        if (/k$/i.test(t)) { k = 1000; n = t.slice(0, -1) }
        else if (/m$/i.test(t)) { k = 1000000; n = t.slice(0, -1) }
        const v = parseFloat(n)
        return isNaN(v) ? 0 : v * k
    }

    implicitWidth: cardWidth
    implicitHeight: col.implicitHeight + Tokens.space3 * 2

    // hover lift
    transform: Translate {
        y: root.hovered && !hoverArea.pressed ? -3 : 0
        Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    }

    // ── picked glow (behind the surface) ──
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: Tokens.radiusLg + 3
        color: "transparent"
        border.width: 3
        border.color: U.withAlpha(Theme.primary, 0.22)
        opacity: root.picked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
    }

    // ── surface ──
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Tokens.radiusLg
        color: root.picked ? U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.06)
             : root.hovered ? U.hoverTint(Theme.panel_bg, Theme.isDark) : Theme.panel_bg
        border.width: root.picked ? 1.5 : 1
        border.color: root.picked ? Theme.primary
                     : (root.hovered ? U.mix(Theme.border, Theme.outline, 0.6) : Theme.border)
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
    }

    // Card-wide toggle. Declared BEFORE the content on purpose: later siblings
    // paint on top and win pointer events, so putting this first lets the
    // open-on-YouTube button keep its own clicks while every inert item above
    // (rectangles, text, images) still lets events fall through to here.
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(root.row.key || "")
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.space3
        spacing: Tokens.space3

        // ── thumbnail ──
        Item {
            id: thumbBox
            Layout.fillWidth: true
            implicitHeight: width * 9 / 16

            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusMd
                color: Theme.surface_high
            }

            Image {
                id: thumb
                anchors.fill: parent
                visible: false
                source: root.row.thumbId ? "image://thumbs/" + root.row.thumbId : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
            // Loading placeholder while the thumbnail decodes.
            C.ThumbSkeleton {
                anchors.fill: parent
                active: (root.row.thumbId || "") !== "" && thumb.status !== Image.Ready
                        && thumb.status !== Image.Error
                topLeftRadius: Tokens.radiusMd
                topRightRadius: Tokens.radiusMd
                bottomLeftRadius: Tokens.radiusMd
                bottomRightRadius: Tokens.radiusMd
                glyph: "movie"
            }
            Item {
                id: thumbMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusMd
                    color: "white"
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: thumb
                maskEnabled: true
                maskSource: thumbMask
                // Unpicked cards sit back a little so the picked ones read as
                // the active set at a glance across a full grid.
                opacity: (thumb.status === Image.Ready ? 1 : 0)
                         * (root.picked || root.hovered ? 1.0 : 0.86)
                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
            }

            // hover scrim + call to action
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusMd
                opacity: root.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.10) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.space2
                    radius: Tokens.radiusPill
                    color: root.picked ? Qt.rgba(1, 1, 1, 0.16) : Theme.primary
                    implicitWidth: ctaRow.implicitWidth + 16
                    implicitHeight: 26
                    scale: root.hovered ? 1 : 0.9
                    Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    Row {
                        id: ctaRow
                        anchors.centerIn: parent
                        spacing: 4
                        C.IconGlyph {
                            name: root.picked ? "remove" : "add"
                            size: 13
                            glyphColor: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.AppText {
                            text: root.picked ? I18n.tr("Remove") : I18n.tr("Add")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontCaption
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // format + duration chip
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.space2
                radius: Tokens.radiusSm
                color: U.withAlpha(Qt.rgba(0, 0, 0, 1), 0.72)
                implicitWidth: durRow.implicitWidth + Tokens.space2 * 2
                implicitHeight: 22
                Row {
                    id: durRow
                    anchors.centerIn: parent
                    spacing: 4
                    C.IconGlyph {
                        visible: root.row.isShort === true
                        name: "fmt_short"
                        size: 11
                        glyphColor: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        text: root.row.duration || ""
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        weight: Tokens.weightDemiBold
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // selection disc — pick order when picked, + on hover, ring at rest
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Tokens.space2
                width: 28; height: 28; radius: 14
                color: root.picked ? Theme.primary
                     : root.hovered ? U.withAlpha(Theme.primary, 0.85)
                     : U.withAlpha(Qt.rgba(0, 0, 0, 1), 0.50)
                border.width: root.picked ? 2 : 1.5
                border.color: root.picked ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.85)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                scale: root.picked ? 1.0 : (root.hovered ? 1.06 : 0.92)
                Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack } }
                C.AppText {
                    anchors.centerIn: parent
                    visible: root.picked && root.order > 0
                    text: root.order
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_primary
                }
                C.IconGlyph {
                    anchors.centerIn: parent
                    visible: !(root.picked && root.order > 0)
                    name: root.picked ? "check" : (root.hovered ? "add" : "check")
                    size: 15
                    glyphColor: "#ffffff"
                    opacity: root.picked || root.hovered ? 1 : 0.6
                }
            }

            // multiplier badge — the reason a video is worth borrowing from.
            // Tiered: ≥10x glows hot, ≥3x is solid accent, below that quiet.
            Rectangle {
                visible: (root.row.multiplier || "—") !== "—"
                readonly property bool hot: root.multValue >= 10
                readonly property bool strong: root.multValue >= 3
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.space2
                radius: Tokens.radiusSm
                color: strong ? U.withAlpha(Theme.primary, 0.94) : U.withAlpha(Qt.rgba(0, 0, 0, 1), 0.62)
                border.width: hot ? 1 : 0
                border.color: Qt.rgba(1, 1, 1, 0.35)
                implicitWidth: multRow.implicitWidth + Tokens.space2 * 2
                implicitHeight: 22
                Row {
                    id: multRow
                    anchors.centerIn: parent
                    spacing: 3
                    C.IconGlyph {
                        visible: parent.parent.hot
                        name: "trending_up"
                        size: 11
                        glyphColor: Theme.on_primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        text: root.row.multiplier || ""
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        weight: Tokens.weightExtraBold
                        color: parent.parent.strong ? Theme.on_primary : "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ── title ──
        C.AppText {
            text: root.row.title || ""
            weight: Tokens.weightDemiBold
            color: root.picked ? Theme.text_strong : (root.hovered ? Theme.text_strong : Theme.on_surface)
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Layout.fillWidth: true
            // Two lines always, so a one-line title doesn't make its card
            // shorter than its neighbours and stagger the grid rows.
            Layout.preferredHeight: lineHeightPx * 2
            readonly property real lineHeightPx: Math.ceil(font.pixelSize * 1.35)
            verticalAlignment: Text.AlignTop
        }

        // ── channel ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space2
            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 9
                color: U.withAlpha(Theme.primary, 0.14)
                C.AppText {
                    anchors.centerIn: parent
                    text: String(root.row.channelTitle || "?").charAt(0).toUpperCase()
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.primary
                }
            }
            C.AppText {
                text: root.row.channelTitle || ""
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            C.AppText {
                visible: (root.row.subsText || "") !== ""
                text: (root.row.subsText || "")
                mono: true
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
            }
        }

        // ── stats ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space2
            Rectangle {
                radius: Tokens.radiusSm
                color: U.withAlpha(Theme.on_surface, 0.05)
                implicitWidth: viewsRow.implicitWidth + 12
                implicitHeight: 24
                Row {
                    id: viewsRow
                    anchors.centerIn: parent
                    spacing: 5
                    C.IconGlyph {
                        name: "visibility"; size: 12; glyphColor: Theme.outline
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        text: root.row.views || ""
                        mono: true
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            C.AppText {
                text: root.row.age || ""
                mono: true
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            // Opening the source on YouTube is a secondary action, so it is the
            // one small carve-out from the card-wide hit target — and it only
            // shows itself while the card is hovered.
            AbstractButton {
                id: openBtn
                implicitWidth: 26; implicitHeight: 26
                opacity: root.hovered || openHover.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                onClicked: root.opened(root.row.videoUrl || "")
                background: Rectangle {
                    radius: Tokens.radiusSm
                    color: openHover.containsMouse ? U.withAlpha(Theme.primary, 0.14) : "transparent"
                    MouseArea {
                        id: openHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        cursorShape: Qt.PointingHandCursor
                    }
                }
                contentItem: C.IconGlyph {
                    name: "open_in_new"
                    size: 14
                    glyphColor: openHover.containsMouse ? Theme.primary : Theme.on_surface_var
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                C.AppTooltip { visible: openHover.containsMouse; text: I18n.tr("Open on YouTube") }
            }
        }
    }
}
