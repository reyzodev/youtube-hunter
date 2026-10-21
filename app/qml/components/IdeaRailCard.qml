import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// One blueprint as a SELECTOR in the idea rail, not as the blueprint itself.
//
// A v2 blueprint is a script plus a shot list plus a competitor table — far too
// tall to stack several of them open, and the thing a creator actually does with
// a batch is compare one against another. So the rail holds these compact rows
// and the pane beside them renders whichever is active (see BlueprintPane).
//
// The card carries only what you choose ON: how strong the idea is, what it is,
// the line you would open with, and what it costs to make. Everything else waits
// for the pane.
Item {
    id: root

    // A flattened blueprint from IdeasVM.ideas.
    property var idea: ({})
    property bool active: false
    // True while THIS blueprint is being rebuilt — the rail dims the one row
    // rather than the page going busy, so the rest stays readable.
    property bool regenerating: false

    signal selected(int ideaId)
    signal favorited(int ideaId)
    signal deleteRequested(int ideaId)

    readonly property int score: idea.score || 0
    // Same three-band language as the rest of the app rather than a gradient,
    // so a score reads the same here as on a niche card.
    readonly property color scoreColor: score >= 85 ? Theme.secondary_container
                                      : score >= 70 ? Theme.primary
                                      : Theme.warn

    implicitHeight: shell.implicitHeight

    C.GlassPanel {
        id: shell
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: col.implicitHeight + Tokens.space4 * 2
        radius: Tokens.radiusLg
        hoverGlow: true
        // The active row is tinted + 1px accent border (kept thin like the
        // rest of the AI Ideas boxes) so it reads at a glance without a
        // heavy stroke.
        color: root.active ? Theme.panel_bg
             : cardHover.hovered ? U.hoverTint(Theme.panel_bg, Theme.isDark)
             : Theme.panel_bg
        border.width: 1
        border.color: root.active ? Theme.primary : Theme.border
        elevation: root.active ? 1.6 : (cardHover.hovered ? 0.8 : 0)
        Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
        opacity: root.regenerating ? 0.55 : 1.0
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        // Hover rides on a HoverHandler, not a MouseArea: the bookmark and
        // delete buttons sit on top of the card, and with Qt 5-style hover the
        // card would lose hover the moment the cursor reached them.
        HoverHandler { id: cardHover }

        // v11: hover lifts the card a touch; the active one carries a
        // gradient wash and a lit accent edge instead of a plain tint.
        transform: Translate {
            y: cardHover.hovered && !root.active ? -2 : 0
            Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: shell.radius - 1
            opacity: root.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.12) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.02) }
            }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.6
            height: 2
            radius: 1
            opacity: root.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                GradientStop { position: 0.5; color: Theme.primary }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }

        // Selecting is the card click. hoverEnabled stays false so this never
        // competes with the HoverHandler or the buttons for hover.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected(root.idea.id || 0)
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Tokens.space4
            spacing: Tokens.space2

            // ── row 1: score + title + actions ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3

                // score dial — the same sweep as the blueprint hero, in miniature
                C.ScoreRing {
                    value: root.score
                    accent: root.scoreColor
                    ringSize: 46
                    thickness: 4
                    caption: ""
                    showHalo: false
                    numberSize: 14
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.AppText {
                        text: root.idea.title || ""
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel
                        color: root.active ? Theme.primary : Theme.text_strong
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.AppText {
                        text: root.idea.scoreLabel || ""
                        visible: text !== ""
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: 11
                        color: root.scoreColor
                    }
                }

                // Actions reveal on hover (or stay put on the active row, which
                // is the one you are most likely to act on).
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    opacity: cardHover.hovered || root.active || root.idea.isFavorite === true
                             ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                    C.IconButton {
                        iconName: "bookmark"
                        iconFill: root.idea.isFavorite === true
                        active: root.idea.isFavorite === true
                        accent: Theme.primary
                        implicitWidth: 28
                        implicitHeight: 28
                        tip: I18n.tr("Favorite")
                        onClicked: root.favorited(root.idea.id || 0)
                    }
                    C.IconButton {
                        iconName: "delete_outline"
                        accent: Theme.error
                        implicitWidth: 28
                        implicitHeight: 28
                        visible: cardHover.hovered || root.active
                        tip: I18n.tr("Delete")
                        onClicked: root.deleteRequested(root.idea.id || 0)
                    }
                }
            }

            // ── row 2: the line you would open with ──
            // In LTR even on a Persian install: the model writes hooks in the
            // language of the target audience, and a mixed-direction quote reads
            // as broken unless it is pinned.
            C.AppText {
                text: (root.idea.hookPreview || "") !== ""
                      ? "“" + root.idea.hookPreview + "”" : ""
                visible: (root.idea.hookPreview || "") !== ""
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // ── row 3: what it is and what it costs to make ──
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.space1

                // format
                Rectangle {
                    radius: Tokens.radiusPill
                    color: Theme.surface_high
                    border.width: 1
                    border.color: Theme.border
                    implicitWidth: fmtLbl.implicitWidth + Tokens.space3
                    implicitHeight: 19
                    C.AppText {
                        id: fmtLbl
                        anchors.centerIn: parent
                        text: root.idea.isLong ? I18n.tr("LONG") : I18n.tr("SHORT")
                        mono: false
                        weight: Tokens.weightBold
                        font.pixelSize: 10
                        color: Theme.on_surface_var
                    }
                }
                // production difficulty — a real judgement from the shot list,
                // unlike the view estimates the old schema invented
                Rectangle {
                    visible: (root.idea.difficultyLabel || "") !== ""
                    radius: Tokens.radiusPill
                    readonly property color tint: root.idea.difficulty === "Hard" ? Theme.error
                                                : root.idea.difficulty === "Easy"
                                                  ? Theme.secondary_container : Theme.warn
                    color: U.withAlpha(tint, 0.14)
                    border.width: 1
                    border.color: U.withAlpha(tint, 0.32)
                    implicitWidth: diffLbl.implicitWidth + Tokens.space3
                    implicitHeight: 19
                    C.AppText {
                        id: diffLbl
                        anchors.centerIn: parent
                        text: root.idea.difficultyLabel || ""
                        weight: Tokens.weightDemiBold
                        font.pixelSize: 10
                        color: parent.tint
                    }
                }
                // pillar
                Rectangle {
                    visible: (root.idea.pillar || "") !== ""
                    radius: Tokens.radiusPill
                    color: Theme.surface_high
                    border.width: 1
                    border.color: Theme.border
                    implicitWidth: Math.min(150, pillarLbl.implicitWidth + Tokens.space3)
                    implicitHeight: 19
                    C.AppText {
                        id: pillarLbl
                        anchors.centerIn: parent
                        width: parent.width - Tokens.space3
                        text: root.idea.pillar || ""
                        font.pixelSize: 10
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // ── row 4: provenance + the "needs a rebuild" flag ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2

                // A pre-v2 record has no script / shot list / competitor table.
                // Saying so on the rail means the gap is never mistaken for the
                // model having returned nothing.
                Rectangle {
                    visible: root.idea.isLegacy === true
                    radius: Tokens.radiusPill
                    color: U.withAlpha(Theme.warn, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.warn, 0.30)
                    implicitWidth: oldRow.implicitWidth + Tokens.space3
                    implicitHeight: 19
                    Row {
                        id: oldRow
                        anchors.centerIn: parent
                        spacing: 3
                        C.IconGlyph {
                            name: "history"
                            size: 11
                            glyphColor: Theme.warn
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.AppText {
                            text: I18n.tr("older version")
                            font.pixelSize: 11
                            weight: Tokens.weightDemiBold
                            color: Theme.warn
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                C.AppText {
                    text: root.regenerating ? I18n.tr("Rebuilding …")
                                            : (root.idea.source || "")
                    font.pixelSize: 11
                    color: root.regenerating ? Theme.primary : Theme.outline
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
