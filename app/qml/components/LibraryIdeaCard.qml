import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v12 — one blueprint as a selector in the Content Lab library rail.
//
// A Content-Lab-only sibling of IdeaRailCard (which AI Ideas keeps using
// unchanged). Same signals, same data, a calmer and more legible card:
//
//   * a FIXED height, so a rail of cards lines up as one strip instead of a
//     ragged row of differently-tall boxes;
//   * the score dial and its band label lead, the title is set larger, and the
//     opening line sits in a quote bar like the hook card in the blueprint;
//   * the active card carries an accent wash, an accent edge and a lit bar
//     along its foot — "this is the one open below" reads from across the room;
//   * `position` ("3 / 12") prints in the corner so keyboard stepping always
//     says where you are.
Item {
    id: root

    property var idea: ({})
    property bool active: false
    property bool regenerating: false
    property string position: ""

    signal selected(int ideaId)
    signal favorited(int ideaId)
    signal deleteRequested(int ideaId)

    readonly property int score: idea.score || 0
    readonly property color scoreColor: score >= 85 ? Theme.secondary_container
                                      : score >= 70 ? Theme.primary
                                      : Theme.warn
    readonly property bool fav: idea.isFavorite === true
    readonly property bool hot: cardHover.hovered

    implicitHeight: 214

    C.GlassPanel {
        id: shell
        anchors.fill: parent
        radius: Tokens.radiusXl
        color: root.active ? U.mix(Theme.panel_bg, Theme.primary, Theme.isDark ? 0.07 : 0.04)
             : root.hot ? U.hoverTint(Theme.panel_bg, Theme.isDark, 0.04)
             : Theme.panel_bg
        border.width: 1
        border.color: root.active ? U.withAlpha(Theme.primary, 0.85)
                    : root.hot ? U.mix(Theme.border, Theme.primary, 0.30)
                    : Theme.border
        elevation: root.active ? 1.8 : (root.hot ? 1.2 : 0.4)
        Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        opacity: root.regenerating ? 0.55 : 1.0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        HoverHandler { id: cardHover }

        transform: Translate {
            y: root.hot && !root.active ? -3 : 0
            Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }

        // active: a wash from the top
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: shell.radius - 1
            opacity: root.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.22 : 0.12) }
                GradientStop { position: 0.7; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }
        C.CornerGlow {
            radius: shell.radius
            size: 300
            opacity: root.hot && !root.active ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durGlow } }
        }

        // active: the lit foot bar
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.active ? parent.width * 0.5 : 0
            height: 3
            radius: 1.5
            Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                GradientStop { position: 0.5; color: Theme.primary }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }

        // the card click selects; buttons on top keep their own clicks
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected(root.idea.id || 0)
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Tokens.space4
            anchors.bottomMargin: Tokens.space4 + 2
            spacing: Tokens.space2

            // ── score + band + actions ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3

                C.ScoreRing {
                    value: root.score
                    accent: root.scoreColor
                    ringSize: 48
                    thickness: 4
                    caption: ""
                    showHalo: root.active
                    numberSize: 15
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    C.AppText {
                        Layout.fillWidth: true
                        text: root.idea.scoreLabel || ""
                        visible: text !== ""
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontMicro
                        font.letterSpacing: I18n.rtl ? 0 : 1
                        color: root.scoreColor
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: Tokens.space1
                        // format
                        Rectangle {
                            radius: Tokens.radiusPill
                            color: root.idea.isLong ? U.withAlpha(Theme.tertiary, 0.14) : U.withAlpha(Theme.primary, 0.12)
                            border.width: 1
                            border.color: root.idea.isLong ? U.withAlpha(Theme.tertiary, 0.35) : U.withAlpha(Theme.primary, 0.32)
                            width: fmtRow.implicitWidth + Tokens.space3
                            height: 20
                            Row {
                                id: fmtRow
                                anchors.centerIn: parent
                                spacing: 3
                                C.IconGlyph {
                                    name: root.idea.isLong ? "fmt_long" : "fmt_short"
                                    size: 11
                                    glyphColor: root.idea.isLong ? Theme.tertiary : Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                C.AppText {
                                    text: root.idea.isLong ? I18n.tr("LONG") : I18n.tr("SHORT")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontMicro
                                    color: root.idea.isLong ? Theme.tertiary : Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                        // production difficulty
                        Rectangle {
                            visible: (root.idea.difficultyLabel || "") !== ""
                            radius: Tokens.radiusPill
                            readonly property color tint: root.idea.difficulty === "Hard" ? Theme.error
                                                        : root.idea.difficulty === "Easy"
                                                          ? Theme.secondary_container : Theme.warn
                            color: U.withAlpha(tint, 0.12)
                            border.width: 1
                            border.color: U.withAlpha(tint, 0.30)
                            width: diffLbl.implicitWidth + Tokens.space3
                            height: 20
                            C.AppText {
                                id: diffLbl
                                anchors.centerIn: parent
                                text: root.idea.difficultyLabel || ""
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontMicro
                                color: parent.tint
                            }
                        }
                    }
                }

                // actions: bookmark always reachable, delete on hover/active
                Row {
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    C.IconButton {
                        iconName: "bookmark"
                        iconFill: root.fav
                        active: root.fav
                        accent: Theme.primary
                        implicitWidth: 30
                        implicitHeight: 30
                        opacity: root.hot || root.active || root.fav ? 1 : 0.35
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        tip: I18n.tr("Favorite")
                        onClicked: root.favorited(root.idea.id || 0)
                    }
                    C.IconButton {
                        iconName: "delete_outline"
                        accent: Theme.error
                        implicitWidth: 30
                        implicitHeight: 30
                        opacity: root.hot || root.active ? 1 : 0
                        enabled: opacity > 0.5
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        tip: I18n.tr("Delete")
                        onClicked: root.deleteRequested(root.idea.id || 0)
                    }
                }
            }

            // ── the title ──
            C.AppText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space1
                text: root.idea.title || ""
                weight: Tokens.weightExtraBold
                font.pixelSize: 16
                font.letterSpacing: I18n.rtl ? 0 : -0.2
                lineHeight: 1.08
                color: root.active ? Theme.primary : Theme.text_strong
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            // ── the opening line, in a quote bar ──
            RowLayout {
                Layout.fillWidth: true
                visible: (root.idea.hookPreview || "") !== ""
                spacing: Tokens.space2
                Rectangle {
                    implicitWidth: 2
                    Layout.fillHeight: true
                    radius: 1
                    color: root.active ? Theme.primary : U.withAlpha(Theme.outline, 0.45)
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: root.idea.hookPreview || ""
                    font.pixelSize: Tokens.fontCaption + 1
                    lineHeight: 1.12
                    color: Theme.on_surface_var
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Item { Layout.fillHeight: true }

            // ── foot: pillar · provenance · position ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2

                Rectangle {
                    visible: root.idea.isLegacy === true
                    radius: Tokens.radiusPill
                    color: U.withAlpha(Theme.warn, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.warn, 0.30)
                    implicitWidth: oldRow.implicitWidth + Tokens.space3
                    implicitHeight: 20
                    Row {
                        id: oldRow
                        anchors.centerIn: parent
                        spacing: 3
                        C.IconGlyph {
                            name: "history"; size: 11
                            glyphColor: Theme.warn
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.AppText {
                            text: I18n.tr("older version")
                            font.pixelSize: Tokens.fontMicro
                            weight: Tokens.weightDemiBold
                            color: Theme.warn
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
                Rectangle {
                    visible: (root.idea.pillar || "") !== "" && root.idea.isLegacy !== true
                    radius: Tokens.radiusPill
                    color: Theme.surface_high
                    border.width: 1
                    border.color: Theme.border
                    implicitWidth: Math.min(140, pillarLbl.implicitWidth + Tokens.space3)
                    implicitHeight: 20
                    C.AppText {
                        id: pillarLbl
                        anchors.centerIn: parent
                        width: parent.width - Tokens.space3
                        text: root.idea.pillar || ""
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: root.regenerating ? I18n.tr("Rebuilding …") : (root.idea.source || "")
                    font.pixelSize: Tokens.fontMicro
                    color: root.regenerating ? Theme.primary : Theme.outline
                    elide: Text.ElideRight
                }
                C.AppText {
                    visible: root.position !== ""
                    text: root.position
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    color: root.active ? Theme.primary : Theme.outline
                    LayoutMirroring.enabled: false
                }
            }
        }
    }
}
