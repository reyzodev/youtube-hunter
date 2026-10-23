import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// Viral Radar header (v1.1) — sits on top of the Niche Finder results while
// the pool on screen is "what is viral right now" instead of a keyword search.
//
//   ┌──────────────────────────────────────────────────────────────────────┐
//   │ ▮▮▮▮  VIRAL NOW · live                      [Refresh] [Save to Archive]│
//   │       Viral · Global · Gaming   ~16 units · cached 12m                 │
//   │ [Market ▾] [Category ▾] [24h|48h|7d|30d] [Source ▾] [Rank by ▾]  ◯ open│
//   └──────────────────────────────────────────────────────────────────────┘
//
// v1.0.1: a Market other than Global means that market's CONTENT — local
// title, channel not registered in another country (core/niche/viral.py +
// audience.market_fit) — not just "watchable there".
//
// Every control here only decides WHERE the pool comes from (one cheap
// videos.list chart read, cached for an hour); the Tuner below still cuts it
// live, and "Rank by" is the page's own sort — Views ÷ Subs first is the
// high-views / low-subscribers ranking. Nothing here archives on its own.
//
// v1.1 — the radar runs on the USER'S Google quota, so nothing here fetches
// on its own any more:
//   * setup mode (Niche.viralSetupOpen): the picks + the cost + the key's
//     budget left today, and one "Find viral videos" button;
//   * on a loaded radar, changing a pick only marks it dirty — the
//     "Apply · ~N units" button is what spends;
//   * the lens row (All / Gold / Hidden gems / Shorts / Long) and "Rank by"
//     are local cuts of the pool already in memory: zero quota.
Rectangle {
    id: root
    property bool motion: true
    readonly property bool setup: Niche.viralSetupOpen

    implicitHeight: col.implicitHeight + Tokens.space4 * 2
    radius: Tokens.radiusLg
    color: U.mix(Theme.surface_low, Theme.primary, Theme.isDark ? 0.07 : 0.05)
    border.width: 1
    border.color: U.withAlpha(Theme.primary, 0.26)

    // a slow warm wash from the left edge — the "heat" of the chart
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        opacity: 0.9
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.14) }
            GradientStop { position: 0.45; color: U.withAlpha(Theme.primary, 0.0) }
        }
    }

    function _fetch() { if (!Niche.isRunning) Niche.loadViral() }
    readonly property color _costColor: Niche.viralCostHeavy ? Theme.warn : Theme.on_surface_var

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.space4
        spacing: Tokens.space3

        // ── headline row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space3

            C.PulseBars {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignVCenter
                bars: 6
                gap: 3
                mode: Niche.isRunning ? "busy" : "idle"
                accent: Theme.primary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Row {
                    spacing: Tokens.space2
                    C.AppText {
                        text: I18n.tr("Viral now")
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontTitle
                        color: Theme.text_strong
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: liveLbl.implicitWidth + Tokens.space2 * 2 + 10
                        height: 22
                        radius: Tokens.radiusPill
                        color: U.withAlpha(Theme.primary, 0.14)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: root.motion && root.visible && Tokens.appActive
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                                }
                            }
                            C.AppText {
                                id: liveLbl
                                text: Niche.isRunning ? I18n.tr("scanning")
                                      : root.setup ? I18n.tr("not loaded")
                                      : (Niche.cacheLabel || I18n.tr("live"))
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontMicro
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
                Row {
                    Layout.fillWidth: true
                    spacing: 0
                    C.AppText {
                        text: Niche.viralTitle + "   ·   "
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                    C.AppText {
                        text: Niche.viralCost
                        mono: true
                        weight: Niche.viralCostHeavy ? Tokens.weightBold : Tokens.weightRegular
                        font.pixelSize: Tokens.fontCaption
                        color: root._costColor
                    }
                }
                // the budget the user is about to spend from, in plain numbers
                C.AppText {
                    Layout.fillWidth: true
                    visible: text !== "" && (root.setup || Niche.viralDirty)
                    text: Niche.viralBudgetText
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: root._costColor
                    elide: Text.ElideRight
                }
            }

            // ── setup: nothing loaded yet ──
            C.PrimaryButton {
                visible: root.setup
                variant: "ghost"
                text: I18n.tr("Not now")
                implicitHeight: 40
                onClicked: Niche.closeViralSetup()
            }
            C.PrimaryButton {
                visible: root.setup || Niche.viralDirty
                iconName: "trending_up"
                text: (root.setup ? I18n.tr("Find viral videos") : I18n.tr("Apply"))
                      + "  ·  " + (Niche.viralCostUnits === 0 ? I18n.tr("free")
                                   : I18n.tr("~{n} units").replace("{n}", Niche.viralCostUnits.toLocaleString(Qt.locale("en_US"), "f", 0)))
                implicitHeight: 40
                enabled: !Niche.isRunning
                onClicked: root._fetch()
            }

            // ── a radar is on screen ──
            C.PrimaryButton {
                visible: !root.setup && !Niche.viralDirty
                variant: "ghost"
                iconName: "refresh"
                text: I18n.tr("Refresh")
                implicitHeight: 40
                enabled: !Niche.isRunning
                onClicked: Niche.refreshViral()
            }
            C.PrimaryButton {
                visible: !root.setup
                variant: Niche.viralDirty ? "ghost" : "primary"
                iconName: "inventory_2"
                text: I18n.tr("Save to Archive")
                implicitHeight: 40
                enabled: Niche.hasResults && !Niche.isRunning
                onClicked: Niche.archiveResults()
            }
        }

        // ── lens: one tap from 200 viral videos to the handful worth stealing ──
        Flow {
            Layout.fillWidth: true
            visible: !root.setup && Niche.viralActive
            spacing: Tokens.space2
            Repeater {
                model: Niche.viralLensOptions
                Rectangle {
                    id: lensChip
                    readonly property bool sel: Niche.viralLensIndex === index
                    readonly property int n: (Niche.viralLensCounts || [])[index] || 0
                    readonly property bool gold: index === 1
                    readonly property color hue: gold ? "#e0a521" : Theme.primary
                    height: 32
                    width: lensRow.implicitWidth + Tokens.space3 * 2
                    radius: Tokens.radiusPill
                    color: sel ? U.withAlpha(hue, Theme.isDark ? 0.24 : 0.16)
                              : lensMa.containsMouse ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(U.withAlpha(Theme.on_surface, 0.05), 0)
                    border.width: 1
                    border.color: sel ? U.withAlpha(hue, 0.7) : U.mix(Theme.border, Theme.outline, 0.35)
                    opacity: n === 0 && !sel ? 0.45 : 1.0
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    Row {
                        id: lensRow
                        anchors.centerIn: parent
                        spacing: 6
                        C.IconGlyph {
                            visible: lensChip.gold
                            name: "star"; fill: true; size: 13
                            glyphColor: lensChip.hue
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.AppText {
                            text: modelData
                            weight: lensChip.sel ? Tokens.weightBold : Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontCaption
                            color: lensChip.sel ? Theme.text_strong : Theme.on_surface
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.AppText {
                            text: lensChip.n
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: lensChip.sel ? lensChip.hue : Theme.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: lensMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Niche.viralLensIndex = index
                            // Gold is a ranking as much as a cut: sort by it
                            // too, so the best one is the first card.
                            if (index === 1 && Niche.sortIndex !== Niche.goldSortIndex) {
                                Niche.sortIndex = Niche.goldSortIndex
                                Niche.applyFilters()
                            }
                        }
                    }
                }
            }
        }

        // ── where the pool comes from + how it is ranked ──
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.space2

            C.Dropdown {
                width: 210
                popupMaxHeight: 380
                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                model: Niche.viralRegionOptions
                currentIndex: Niche.viralRegionIndex
                enabled: !Niche.isRunning
                onActivated: { Niche.viralRegionIndex = currentIndex }
            }
            C.Dropdown {
                width: 210
                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                model: Niche.viralCategoryOptions
                currentIndex: Niche.viralCategoryIndex
                enabled: !Niche.isRunning
                onActivated: { Niche.viralCategoryIndex = currentIndex }
            }
            C.SlideSegment {
                width: 280
                cellHeight: Tokens.fieldHeight - 6
                solid: false
                mono: true
                equal: true
                enabledCells: !Niche.isRunning
                model: ["24h", "48h", "7d", "30d"]
                currentIndex: Niche.viralWindowIndex
                onActivated: (i) => { Niche.viralWindowIndex = i }
            }
            C.Dropdown {
                width: 250
                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                model: Niche.viralSourceOptions
                currentIndex: Niche.viralSourceIndex
                enabled: !Niche.isRunning
                onActivated: { Niche.viralSourceIndex = currentIndex }
            }
            C.Dropdown {
                width: 270
                visible: !root.setup
                borderColor: U.withAlpha(Theme.primary, 0.45)
                model: Niche.sortOptions
                currentIndex: Niche.sortIndex
                onActivated: { Niche.sortIndex = currentIndex; Niche.applyFilters() }
            }

            // open the page on this radar next time too
            Row {
                spacing: Tokens.space2
                C.AppSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Niche.viralAutoload
                    onToggled: Niche.viralAutoload = checked
                }
                C.AppText {
                    // honest about what the switch costs
                    text: I18n.tr("Load on open (spends quota)")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
