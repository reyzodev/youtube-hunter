import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import NicheScope
import "." as C
import "../Utils.js" as U

// The left navigation rail: brand quota ring, the nav list, and pinned footer
// actions. Emits page-change requests through App.goto.
//
// The rail collapses to an icon-only strip (App.sidebarCollapsed, persisted).
// Collapsing is purely a width animation here — every child binds its own
// geometry to `collapsed`, so nothing is created or destroyed on toggle and the
// slide stays smooth. The width it gives up goes straight to the page.
Rectangle {
    id: root
    // v3.39.11: the pointer rests on a rail row (page index), left it (-1), or
    // pressed it (1000 + page: build now, the click is coming).
    // Main.qml uses it to start building that page before the click arrives.
    signal prefetchRequested(int page)
    readonly property bool collapsed: App.sidebarCollapsed

    // The animation lives on implicitWidth, NOT width: inside a RowLayout the
    // layout owns `width`, so animating that directly fights the layout (and
    // Qt resolves the fight as a binding loop). The parent tracks this through
    // Layout.preferredWidth instead, so the page beside the rail grows in step
    // with the slide. durMed rather than durSlow: at 320ms the collapse read as
    // the rail dragging behind the click.
    implicitWidth: collapsed ? Tokens.sidebarCollapsed : Tokens.sidebarExpanded
    Behavior on implicitWidth {
        NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
    }
    // While the slide runs, heavy card grids freeze their columns + card
    // width on App.railAnimating (reflowing ~10 GPU-layered cards every frame
    // is what made the collapse stutter). The timer outlives the 200ms slide
    // with margin; re-toggling mid-flight just re-arms it.
    onCollapsedChanged: { App.setRailAnimating(true); railTimer.restart() }
    Timer {
        id: railTimer
        interval: Tokens.durMed + 120
        repeat: false
        onTriggered: App.setRailAnimating(false)
    }
    color: Theme.sidebar_bg
    clip: true
    // The rail's window-facing corner is rounded (see Main.qml); antialias it so
    // it matches the shell's curve instead of stepping.
    antialiasing: true

    // right hairline divider
    Rectangle {
        width: 1
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        color: Theme.divider_v
    }

    // The nav entries. `page` is the StackLayout index in Main.qml — kept
    // explicit (rather than relying on array position) so an entry can be
    // dropped from the rail without renumbering the pages behind it. Live Logs
    // (page 1) is intentionally absent: its output now lives inside the Scraper
    // page's own log panel. Settings (page 10) is NOT here either — it is
    // pinned in the footer under the quota card, matching the reference layout.
    // Display order is independent of the indices.
    readonly property var _allNav: [
        { icon: "cloud_download",   label: I18n.tr("Scraper"),          page: 0 },
        { icon: "history",          label: I18n.tr("History"),          page: 2 },
        { icon: "monetization_on",  label: I18n.tr("Monetize Checker"), page: 3 },
        { icon: "travel_explore",   label: I18n.tr("Niche Finder"),     page: 4 },
        { icon: "nav_insights",     label: I18n.tr("Niche Scan"), page: 11 },
        { icon: "archive",          label: I18n.tr("Search Archive"),   page: 5 },
        { icon: "lightbulb",        label: I18n.tr("AI Ideas"),         page: 6 },
        { icon: "biotech",          label: I18n.tr("Content Lab"),      page: 7 },
        { icon: "nav_chat",         label: I18n.tr("AI Chat"),          page: 13 },
        { icon: "download",         label: I18n.tr("Downloads"),        page: 8 },
        { icon: "scissors",         label: I18n.tr("Video Cutter"),     page: 12 },
        { icon: "nav_usage",        label: I18n.tr("Usage & Quota"),    page: 9 }
    ]
    readonly property var navModel: _allNav.filter(function(e) { return !e.hidden })

    // How far a nav row's left edge sits from the window edge — the rail's own
    // layout margin. Handed to each NavButton so its red accent bar can be
    // pinned flush to the window edge. Kept tight (space2) so the pill + content
    // sit close to the red bar rather than floating mid-rail.
    readonly property int navInset: Tokens.space2

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.navInset
        anchors.rightMargin: root.navInset + 1
        spacing: root.collapsed ? Tokens.space2 : Tokens.space3

        // v3.40.3: the "New Scrape" CTA is gone; the nav list starts at the
        // top of the rail (Scraper is the first row anyway).

        // ── nav list ──
        // A single shared indicator (the tinted pill + red edge bar) slides
        // between rows behind the list, so the highlight glides on ONE clock;
        // each NavButton only recolours its own glyph/label, timed to match.
        // This block flexes so the quota card + Settings pin to the rail bottom.
        Item {
            id: navArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Tokens.space1

            // Which nav row is currently checked (null when a non-nav page like
            // Settings is open — the indicator then travels DOWN to the pinned
            // Settings row and hands off to that row's own pill).
            property Item checkedRow: {
                for (var i = 0; i < navRepeater.count; i++) {
                    var it = navRepeater.itemAt(i)
                    if (it && it.checked) return it
                }
                return null
            }

            // Where the footer Settings row sits, in navArea's own coordinates.
            // Both are children of the SAME ColumnLayout, so subtracting their
            // `y` values is exact — and it stays a live binding, which
            // mapToItem() in a binding would not.
            readonly property real settingsY: settingsRow.y - navArea.y

            // Where the checked row currently sits ON SCREEN. The rows live
            // inside a Flickable (see below), so their own `y` is in content
            // coordinates — the indicator has to subtract the scroll offset or
            // it would sit still while the list scrolls under it.
            readonly property real checkedY:
                navArea.checkedRow ? navArea.checkedRow.y - navFlick.contentY : -1
            // A row scrolled above the viewport (or below it) must not drag the
            // indicator out over the CTA button or the quota card.
            readonly property bool checkedVisible:
                checkedY >= -2 && checkedY < navArea.height - 4

            // The sliding highlight. It is a SIBLING of navCol (not a child of
            // the Column), so the Column doesn't lay it out as a flow item —
            // otherwise it would take a slot at the top and shove every row down.
            //
            // It also covers the trip to the PINNED Settings row: on the way out
            // of the nav list it slides DOWN to where Settings sits and fades
            // there, handing over to that row's own pill. Previously it simply
            // faded out wherever it stood while Settings' pill appeared at the
            // bottom, which read as the highlight darting upward first.
            Rectangle {
                id: navIndicator
                z: -1
                visible: opacity > 0.01
                radius: Tokens.radiusMd
                // v4: a lit pill — accent light falling off left → right, with a
                // hairline edge — instead of a flat tint.
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: I18n.rtl ? U.withAlpha(Theme.primary_deep, 0.04) : U.withAlpha(Theme.primary, 0.22) }
                    GradientStop { position: 1.0; color: I18n.rtl ? U.withAlpha(Theme.primary, 0.22) : U.withAlpha(Theme.primary_deep, 0.04) }
                }
                border.width: 1
                border.color: U.withAlpha(Theme.primary, 0.20)
                // Same pill in both rail states, exactly like the pinned
                // Settings row's own highlight: full row width with the red
                // edge bar. (It used to shrink to a centred square when
                // collapsed, which left every collapsed row without the bar
                // Settings kept — so only Settings looked selected.)
                width: navCol.width
                x: 0
                y: navArea.checkedRow ? navArea.checkedY : navArea.settingsY
                height: navArea.checkedRow ? navArea.checkedRow.height : Tokens.navButtonHeight
                opacity: navArea.checkedRow
                         ? (navArea.checkedVisible ? 1 : 0) : 0
                // v4: the pill travels on a soft spring — it lands with a hair of
                // overshoot instead of stopping dead.
                Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                Behavior on height { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                // Fades a touch SLOWER than it travels, so the slide down is
                // visible before it hands off rather than vanishing en route.
                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

                // Glow bleeding off the edge bar into the pill.
                Rectangle {
                    id: barGlow
                    width: 14
                    height: 30
                    radius: 7
                    color: Theme.primary
                    opacity: 0.55 * (Theme.glow_level !== undefined ? Theme.glow_level : 1.0)
                    anchors.left: parent.left
                    anchors.leftMargin: -root.navInset - 6
                    anchors.verticalCenter: parent.verticalCenter
                    layer.enabled: navIndicator.visible
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 24
                        autoPaddingEnabled: true
                    }
                }

                // Red edge accent, flush with the window's left edge.
                Rectangle {
                    width: 3
                    height: 24
                    topRightRadius: I18n.rtl ? 0 : 3
                    topLeftRadius: I18n.rtl ? 3 : 0
                    bottomRightRadius: I18n.rtl ? 0 : 3
                    bottomLeftRadius: I18n.rtl ? 3 : 0
                    anchors.left: parent.left
                    anchors.leftMargin: -root.navInset
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.primary_deep }
                        GradientStop { position: 1.0; color: Theme.primary }
                    }
                }
            }

            // The list itself, in a Flickable.
            //
            // WHY: the rail carries eleven rows (plus the CTA, the quota card,
            // Settings and the version line). On a laptop — anything under
            // roughly 760px of window height — the eleven rows simply do not
            // fit in the space the ColumnLayout leaves for them. As a plain
            // Column they overflowed their slot and painted straight over the
            // quota card and the Settings row, which is what made the menu
            // unreadable and unusable at those sizes. Scrolling is the honest
            // answer: the list keeps its full height and the user reaches the
            // rest of it with the wheel, instead of the rail silently folding
            // itself on top of its own footer.
            Flickable {
                id: navFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: navCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Wheel-only. A draggable rail would turn every slightly-moving
                // click on a nav row into a cancelled press, and a menu is not a
                // surface anyone expects to drag — so dragging is off and the
                // wheel is handled explicitly below (same eased pattern
                // SmoothScrollView uses for every page).
                interactive: false

                function scrollBy(dy) {
                    const max = Math.max(0, contentHeight - height)
                    const base = navWheelAnim.running ? navWheelTarget : contentY
                    navWheelTarget = Math.max(0, Math.min(max, base + dy))
                    navWheelAnim.stop()
                    navWheelAnim.from = contentY
                    navWheelAnim.to = navWheelTarget
                    navWheelAnim.start()
                }
                // Bring a row into view (used when the page changes from
                // somewhere other than a click on this rail — the tour, a
                // notification). Instant, not animated: it has to agree with
                // the indicator's own slide, and a second animation racing that
                // one reads as the list twitching under a stationary pill.
                function revealItem(item) {
                    if (!item) return
                    const max = Math.max(0, contentHeight - height)
                    const top = item.y
                    const bottom = item.y + item.height
                    var target = contentY
                    if (top < contentY) target = top - Tokens.space1
                    else if (bottom > contentY + height) target = bottom - height + Tokens.space1
                    navWheelAnim.stop()
                    navWheelTarget = Math.max(0, Math.min(max, target))
                    contentY = navWheelTarget
                }

                property real navWheelTarget: 0
                NumberAnimation {
                    id: navWheelAnim
                    target: navFlick
                    property: "contentY"
                    duration: Tokens.durMed
                    easing.type: Easing.OutCubic
                }
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => {
                        if (ev.angleDelta.y === 0) return
                        navFlick.scrollBy(ev.angleDelta.y > 0 ? -140 : 140)
                    }
                }

                // True only when the rows really do not fit (small window /
                // laptop height). 1px of slack so sub-pixel layout rounding
                // never flashes the bar on a window that fits.
                readonly property bool overflowing: contentHeight > height + 1
                // Window made taller: never leave the list scrolled past what
                // can now be shown (rows stranded above an empty gap).
                function _clamp() {
                    const max = Math.max(0, contentHeight - height)
                    if (contentY > max) {
                        navWheelAnim.stop()
                        navWheelTarget = max
                        contentY = max
                    }
                }
                onHeightChanged: _clamp()
                onContentHeightChanged: _clamp()

                ScrollBar.vertical: ScrollBar {
                    id: navBar
                    // The custom contentItem below replaces Basic's own
                    // show/hide states, so AsNeeded alone left a full-height
                    // track painted even when nothing could scroll (the stray
                    // line down the rail). Visibility is now explicit: the bar
                    // exists only while the menu actually overflows.
                    policy: navFlick.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    visible: navFlick.overflowing
                    width: 5
                    // Pinned INSIDE the rail. A negative margin here (the
                    // obvious way to sit flush with the window edge) puts the
                    // bar outside the Flickable, which clips it — the rail
                    // scrolled perfectly and showed no sign that it could.
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    background: Item {}
                    contentItem: Rectangle {
                        radius: 2.5
                        implicitWidth: 5
                        color: navBar.pressed ? Theme.primary
                             : navBar.hovered ? U.withAlpha(Theme.primary, 0.60)
                             : U.withAlpha(Theme.on_surface, 0.30)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                }

                Column {
                    id: navCol
                    objectName: "tour_navList"
                    width: navFlick.width
                    spacing: Tokens.space1

                    Repeater {
                        id: navRepeater
                        model: root.navModel
                        C.NavButton {
                            id: navBtn
                            width: parent.width
                            // Per-item name so the onboarding tour can spotlight a
                            // single nav row (tour_nav_<page>) before its page.
                            objectName: "tour_nav_" + modelData.page
                            collapsed: root.collapsed
                            railInset: root.navInset
                            iconName: modelData.icon
                            text: modelData.label
                            checked: App.currentPage === modelData.page
                            // Keep the selected row on screen: a page change
                            // made from the tour or a notification must not
                            // leave the highlight pointing at a row that has
                            // scrolled out of the rail.
                            onCheckedChanged: if (checked) navFlick.revealItem(navBtn)
                            onHoveredChanged: root.prefetchRequested(hovered ? modelData.page : -1)
                            onPressed: root.prefetchRequested(1000 + modelData.page)
                            onClicked: App.goto(modelData.page)
                        }
                    }
                }
            }
        }

        // Theme + language live in the title bar only — removed from the rail
        // entirely (expanded and collapsed) to keep the rail purely navigation.


        // ── quota card ──
        // Pinned near the bottom of the rail (the reference's .quota-card): a
        // bordered well with the ring on the left and the big number on the
        // right. Clicking anywhere opens Usage & Quota. Hidden when collapsed —
        // a bordered card can't shrink into a 72px rail gracefully.
        Rectangle {
            id: quotaCard
            objectName: "tour_quotaCard"
            Layout.fillWidth: true
            visible: !root.collapsed
            implicitHeight: visible ? qcCol.implicitHeight + Tokens.space4 * 2 : 0
            radius: Tokens.radiusLg
            antialiasing: true

            // v10 "fuel strip": remaining quota as a big number over a
            // 20-cell meter, with a status chip that actually follows the level
            // (the old chip said "Healthy" no matter what was left).
            readonly property bool hasKey: App.hasApiKey
            readonly property real frac: hasKey && App.quotaCapacity > 0
                                         ? Math.max(0, Math.min(1, App.quotaRemaining / App.quotaCapacity)) : 0
            readonly property color level: !hasKey ? Theme.warn
                                         : frac > 0.30 ? Theme.secondary_container
                                         : frac > 0.10 ? Theme.warn
                                         : Theme.error
            readonly property string levelText: !hasKey ? I18n.tr("No key")
                                              : frac > 0.30 ? I18n.tr("Healthy")
                                              : frac > 0.10 ? I18n.tr("Heavy use")
                                              : I18n.tr("Almost out")
            readonly property bool hot: qcHover.containsMouse

            color: hot ? U.mix(Theme.surface_low, level, Theme.isDark ? 0.06 : 0.04) : Theme.surface_low
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            border.width: 1
            border.color: hot ? U.mix(Theme.border, level, 0.35) : Theme.border
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

            // a wash of the level colour bleeding in from the top edge
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(quotaCard.level, Theme.isDark ? 0.10 : 0.07) }
                    GradientStop { position: 0.65; color: U.withAlpha(quotaCard.level, 0.0) }
                }
            }

            MouseArea {
                id: qcHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: root.prefetchRequested(containsMouse ? 9 : -1)
                onPressed: root.prefetchRequested(1000 + 9)
                onClicked: App.goto(9)
            }

            Column {
                id: qcCol
                anchors.fill: parent
                anchors.margins: Tokens.space4
                spacing: Tokens.space3

                // header: tile + label + live status chip
                RowLayout {
                    width: parent.width
                    spacing: Tokens.space2
                    C.IconTile {
                        iconName: "youtube"
                        size: 24; glyphSize: 13
                        tint: quotaCard.level
                        lit: quotaCard.hot
                    }
                    C.AppText {
                        text: I18n.tr("YOUTUBE DAILY")
                        weight: Tokens.weightBold
                        font.pixelSize: 11
                        font.letterSpacing: I18n.rtl ? 0 : 0.6
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        radius: Tokens.radiusPill
                        color: U.withAlpha(quotaCard.level, 0.14)
                        border.width: 1
                        border.color: U.withAlpha(quotaCard.level, 0.30)
                        implicitWidth: qcChipRow.implicitWidth + Tokens.space2 * 2
                        implicitHeight: 20
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        Row {
                            id: qcChipRow
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: quotaCard.level
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: quotaCard.levelText
                                weight: Tokens.weightDemiBold
                                font.pixelSize: 10
                                color: quotaCard.level
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                // reading: big remaining number + percent left
                RowLayout {
                    width: parent.width
                    spacing: Tokens.space2
                    C.AppText {
                        text: quotaCard.hasKey
                              ? Number(App.quotaRemaining).toLocaleString(Qt.locale(), "f", 0) : "—"
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontTitle
                        color: Theme.text_strong
                        LayoutMirroring.enabled: false
                        Layout.alignment: Qt.AlignBottom
                    }
                    Item { Layout.fillWidth: true }
                    C.AppText {
                        visible: quotaCard.hasKey
                        text: Math.round(quotaCard.frac * 100) + "%"
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: quotaCard.level
                        LayoutMirroring.enabled: false
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 3
                    }
                }

                // 20-cell meter of what is LEFT; cells light from the leading edge
                Row {
                    id: qcCells
                    width: parent.width
                    spacing: 3
                    readonly property int count: 20
                    readonly property real cellW: (width - spacing * (count - 1)) / count
                    readonly property int lit: quotaCard.hasKey
                                               ? Math.max(quotaCard.frac > 0 ? 1 : 0, Math.round(quotaCard.frac * count)) : 0
                    Repeater {
                        model: qcCells.count
                        Rectangle {
                            width: qcCells.cellW
                            height: 7
                            radius: 2
                            antialiasing: true
                            readonly property bool on: index < qcCells.lit
                            color: on ? U.withAlpha(quotaCard.level, 0.55 + 0.45 * (index + 1) / qcCells.count)
                                      : U.withAlpha(Theme.outline, 0.18)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                        }
                    }
                }

                // caption + "open" affordance
                RowLayout {
                    width: parent.width
                    spacing: Tokens.space1
                    C.AppText {
                        text: I18n.tr("of {n} units").replace(
                            "{n}", Number(App.quotaCapacity).toLocaleString(Qt.locale(), "f", 0))
                        mono: true
                        font.pixelSize: 11
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.IconGlyph {
                        name: I18n.rtl ? "arrow_back" : "arrow_forward"
                        size: 13
                        glyphColor: quotaCard.hot ? quotaCard.level : Theme.outline
                        opacity: quotaCard.hot ? 1 : 0.6
                        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                        transform: Translate {
                            x: quotaCard.hot ? (I18n.rtl ? -2 : 2) : 0
                            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        // hairline above the footer
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.divider_h
            visible: !root.collapsed
        }

        // ── Settings row ──
        // Pinned in the footer. Layout.minimumHeight matters: the nav block
        // above has fillHeight, so at short window heights the ColumnLayout was
        // free to squeeze this row down to its label height — it read as a bare
        // word with no button around it.
        C.NavButton {
            id: settingsRow
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.navButtonHeight
            Layout.minimumHeight: Tokens.navButtonHeight
            Layout.bottomMargin: Tokens.space1
            selfIndicator: true
            collapsed: root.collapsed
            railInset: root.navInset
            iconName: "settings"
            text: I18n.tr("Settings")
            checked: App.currentPage === 10
            onHoveredChanged: root.prefetchRequested(hovered ? 10 : -1)
            onPressed: root.prefetchRequested(1000 + 10)
            onClicked: App.goto(10)
        }

        // ── sign-off: "Made with ♥" + Donate (v1.1.3) ──
        // The last line of the rail: out of the way of every task, but always
        // in reach. Collapsed, it shrinks to the Donate cup alone.
        // v3.52: the pill is only there once a support link exists — before
        // that the footer is just the sign-off, never a dead button.
        C.SupportFooter {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            Layout.minimumHeight: implicitHeight
            Layout.bottomMargin: Tokens.space1
            collapsed: root.collapsed
            donateUrl: App.donateUrl
            onDonateClicked: App.openDonate()
        }
    }
}
