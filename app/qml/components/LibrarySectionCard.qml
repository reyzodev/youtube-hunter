import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v12 — one Content Lab section (a keyword or channel) as a library card.
//
// The v11 card said "N ideas · updated X" and little else, so every section
// looked the same until you opened it. This one carries a fingerprint:
//
//   * the SCORE BARCODE — one bar per blueprint (newest first, capped), its
//     height the blueprint's score and its colour the app's three-band score
//     language. A section of strong ideas reads as a tall green skyline before
//     you read a word. On hover the bars rise into place.
//   * the best blueprint's opening line, quoted — the thing you would actually
//     go in for.
//   * a short / long split bar, the favourite count, best and average score.
//
// `featured` widens the card into the library's lead slot (the most recently
// touched section) with a bigger title and the best blueprint's title too.
C.GlassPanel {
    id: root

    property var entry: ({})
    property bool featured: false

    signal openRequested(int entryId)
    signal deleteRequested(int entryId, string title, int count)

    // GlassPanel's own HoverHandler (hoverGlow) — a handler, so hover survives
    // the cursor reaching the buttons on top of the card.
    readonly property bool hot: root.hovered
    readonly property var scores: entry.scores || []
    readonly property int best: entry.bestScore || 0
    readonly property int avg: entry.avgScore || 0
    readonly property int shortN: entry.shortCount || 0
    readonly property int longN: entry.longCount || 0
    readonly property int favN: entry.favCount || 0
    readonly property int ideaN: entry.ideaCount || 0

    function bandColor(s) {
        return s >= 85 ? Theme.secondary_container
             : s >= 70 ? Theme.primary
             : s > 0 ? Theme.warn
             : U.withAlpha(Theme.outline, 0.4)
    }

    radius: Tokens.radiusXl
    hoverGlow: true
    implicitHeight: cardCol.implicitHeight + Tokens.space5 * 2
    elevation: hot ? 1.8 : 1.0
    Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
    // lift on hover — a transform, so the GridLayout's geometry is untouched
    transform: Translate {
        y: root.hot ? -3 : 0
        Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    }

    // the card lights from its corner on hover (always lit when featured)
    C.CornerGlow {
        radius: root.radius
        size: root.featured ? 560 : 320
        opacity: root.hot || root.featured ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durGlow } }
    }

    // A wash of the accent across the top of the featured card.
    Rectangle {
        visible: root.featured
        anchors.fill: parent
        anchors.margins: 1
        radius: root.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.06) }
            GradientStop { position: 0.6; color: U.withAlpha(Theme.primary, 0.0) }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested(root.entry.id || 0)
    }

    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: Tokens.space5
        spacing: Tokens.space3

        // ── row 1: barcode + best-score badge ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space3

            Item {
                id: barcode
                Layout.fillWidth: true
                implicitHeight: root.featured ? 56 : 40
                readonly property int n: Math.max(1, root.scores.length)
                readonly property real gap: 3
                readonly property real barW: Math.max(3, Math.min(14, (width - gap * (n - 1)) / n))
                property real rise: 0.55
                states: State {
                    when: root.hot || root.featured
                    PropertyChanges { target: barcode; rise: 1 }
                }
                transitions: Transition {
                    NumberAnimation { property: "rise"; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                }

                // baseline
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: U.withAlpha(Theme.outline, 0.22)
                }
                Row {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    spacing: barcode.gap
                    Repeater {
                        model: root.scores
                        Rectangle {
                            width: barcode.barW
                            readonly property real k: Math.max(0.12, (modelData || 0) / 100)
                            // Taller bars rise further — the strong ideas stand up.
                            height: Math.max(3, (barcode.height - 2) * k * (0.35 + 0.65 * barcode.rise * (0.6 + 0.4 * k)))
                            radius: Math.min(3, width / 2)
                            color: root.bandColor(modelData || 0)
                            opacity: root.hot || root.featured ? 1 : 0.75
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                        }
                    }
                }
                // a section with no stored scores still gets a quiet skyline
                C.AppText {
                    visible: root.scores.length === 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("no scores yet")
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.outline
                }
            }

            // best score as a dial
            C.ScoreRing {
                visible: root.best > 0
                value: root.best
                accent: root.bandColor(root.best)
                ringSize: root.featured ? 58 : 46
                thickness: 4
                caption: ""
                showHalo: false
                numberSize: root.featured ? 17 : 14
                Layout.alignment: Qt.AlignBottom
            }
        }

        // ── eyebrow: what this card is ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space1
            spacing: Tokens.space2
            Rectangle {
                visible: root.featured
                implicitWidth: latestLbl.implicitWidth + Tokens.space3
                implicitHeight: 20
                radius: Tokens.radiusPill
                color: Theme.primary
                C.AppText {
                    id: latestLbl
                    anchors.centerIn: parent
                    text: I18n.tr("LATEST")
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontMicro
                    font.letterSpacing: I18n.rtl ? 0 : 1
                    color: Theme.on_primary
                }
            }
            C.AppText {
                Layout.fillWidth: true
                text: I18n.tr("updated {t}").replace("{t}", root.entry.updated || "")
                mono: true
                font.pixelSize: Tokens.fontMicro
                color: Theme.on_surface_var
                elide: Text.ElideRight
            }
        }

        // ── the title ──
        C.AppText {
            Layout.fillWidth: true
            text: root.entry.title || ""
            weight: Tokens.weightExtraBold
            font.pixelSize: root.featured ? 30 : 20
            font.letterSpacing: I18n.rtl ? 0 : (root.featured ? -0.8 : -0.4)
            lineHeight: 1.05
            color: root.hot ? Theme.primary : Theme.text_strong
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // ── the best blueprint ──
        ColumnLayout {
            Layout.fillWidth: true
            visible: (root.entry.topHook || "") !== "" || (root.featured && (root.entry.topTitle || "") !== "")
            spacing: Tokens.space1
            C.AppText {
                Layout.fillWidth: true
                visible: root.featured && (root.entry.topTitle || "") !== ""
                text: root.entry.topTitle || ""
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontBody
                color: Theme.on_surface
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                visible: (root.entry.topHook || "") !== ""
                spacing: Tokens.space2
                Rectangle {
                    implicitWidth: 2
                    Layout.fillHeight: true
                    radius: 1
                    color: U.withAlpha(Theme.primary, 0.6)
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: "“" + (root.entry.topHook || "") + "”"
                    font.pixelSize: root.featured ? Tokens.fontLabel : Tokens.fontCaption + 1
                    lineHeight: 1.15
                    color: Theme.on_surface_var
                    wrapMode: Text.Wrap
                    maximumLineCount: root.featured ? 3 : 2
                    elide: Text.ElideRight
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── numbers: count, short/long split, favourites, average ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space1
            spacing: Tokens.space4

            ColumnLayout {
                spacing: 0
                C.AppText {
                    text: String(root.ideaN)
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: root.featured ? 30 : 24
                    font.letterSpacing: -0.8
                    color: Theme.text_strong
                    LayoutMirroring.enabled: false
                }
                C.AppText {
                    text: I18n.tr("blueprints")
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.on_surface_var
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space1
                // short | long split
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: U.withAlpha(Theme.outline, 0.16)
                    clip: true
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (root.shortN / Math.max(1, root.shortN + root.longN))
                        radius: 3
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    C.AppText {
                        text: I18n.tr("Short") + " " + root.shortN
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.primary
                    }
                    Item { Layout.fillWidth: true }
                    C.AppText {
                        text: I18n.tr("Long") + " " + root.longN
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.on_surface_var
                    }
                }
            }

            ColumnLayout {
                visible: root.avg > 0
                spacing: 0
                C.AppText {
                    text: String(root.avg)
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: root.bandColor(root.avg)
                    LayoutMirroring.enabled: false
                    Layout.alignment: Qt.AlignHCenter
                }
                C.AppText {
                    text: I18n.tr("avg")
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.on_surface_var
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // ── actions ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space1
            spacing: Tokens.space2

            C.PrimaryButton {
                variant: root.hot || root.featured ? "primary" : "ghost"
                iconName: I18n.rtl ? "arrow_back" : "arrow_forward"
                text: I18n.tr("Open section")
                implicitHeight: 38
                Layout.fillWidth: true
                onClicked: root.openRequested(root.entry.id || 0)
            }
            Rectangle {
                visible: root.favN > 0
                implicitWidth: favRow.implicitWidth + Tokens.space3 * 2
                implicitHeight: 38
                radius: Tokens.radiusMd
                color: U.withAlpha(Theme.primary, 0.08)
                border.width: 1
                border.color: U.withAlpha(Theme.primary, 0.25)
                Row {
                    id: favRow
                    anchors.centerIn: parent
                    spacing: 4
                    C.IconGlyph {
                        name: "bookmark"; fill: true; size: 14
                        glyphColor: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        text: String(root.favN)
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            C.IconButton {
                iconName: "delete_outline"
                accent: Theme.error
                opacity: root.hot ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                tip: I18n.tr("Delete this section and its blueprints")
                onClicked: root.deleteRequested(root.entry.id || 0, root.entry.title || "", root.ideaN)
            }
        }
    }
}
