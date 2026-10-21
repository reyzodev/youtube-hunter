import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.41.2 — Notifications tray, redesigned ("Quiet Signal").
//
//   ┌──────────────────────────────────────────────┐
//   │ Notifications  (● 2 new)            Clear all │  title + live pill
//   │ ┌ All 3 ─┬ Alerts ─┬ Completed 1 ┐             │  segmented filter
//   │ NEW                                          │
//   │  [▣•]  Search Archive                1m  •   │  borderless rows:
//   │        Download finished                     │  source · status
//   │        GOT💫 #johnsnow #got …                 │  · detail (2 lines)
//   │ EARLIER                                      │
//   │  …                                    (fade) │
//   └──────────────────────────────────────────────┘
//
// Why it used to "step" when opening (v3.41.1 and before):
//   1. Every row lived in a ListView sized by `contentHeight`, and the row
//      bodies were RowLayout/ColumnLayout with wrapping Text. Layouts assign
//      widths during polish, so wrapped text only reported its real height a
//      frame later, and the ListView only learnt its real contentHeight once
//      delegates existed. The popup opened at one height and then grew in
//      steps, frame after frame.
//   2. Each row also staggered in with its own 10px slide (32ms apart), which
//      on top of (1) read as a staircase.
//   3. The open animation was a NumberAnimation on the GUI thread, the same
//      thread that was busy building the rows, so it froze mid-way.
//
// Now: rows are a Column + Repeater built ahead of time (even while closed),
// sized with plain anchors and explicit widths, so the tray's height is final
// before the first frame. The panel arrives as ONE motion and the rows don't
// animate on open at all. The tray is also no longer a child of the bell
// (whose press-scale shifted the popup's mapped position; see TitleBar.qml).
// The settings shortcut is gone: notifications have no settings of their own.
Popup {
    id: root
    width: 400
    padding: 0
    modal: true
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // "all" | "alerts" | "done"
    property string filter: "all"

    readonly property var _all: Notifications.entries || []
    function _isAlert(k) { return k === "error" || k === "warning" }
    readonly property int _alertCount: _all.filter(e => _isAlert(e.kind)).length
    readonly property int _doneCount: _all.filter(e => e.kind === "success").length
    function _matches(e) {
        return filter === "all" ? true
             : filter === "alerts" ? _isAlert(e.kind)
             : e.kind === "success"
    }
    // v1.1.2 — switching All / Alerts / Completed used to BLINK the tray.
    // The row model was rebuilt from the FILTERED list, so every switch made
    // the Repeater destroy every row and build fresh ones (and the panel
    // snapped to the new height in the same frame). Now the model only
    // changes when the notifications themselves change: ALL rows are built
    // once and a filter switch just hides / shows them (Column skips hidden
    // items), while the list's height glides to its new size.
    readonly property int _shownFresh: _all.filter(e => !e.read && _matches(e)).length
    readonly property int _shownOld: _all.filter(e => e.read && _matches(e)).length
    readonly property int shownCount: _shownFresh + _shownOld
    // header rows ("New" / "Earlier") interleaved with the entries — built
    // from the UNFILTERED list, so it is stable across filter switches.
    readonly property var rows: {
        const out = []
        const fresh = _all.filter(e => !e.read)
        const old = _all.filter(e => e.read)
        if (fresh.length) {
            out.push({ hdr: true, grp: "new", label: I18n.tr("New") })
            for (const e of fresh) out.push(e)
        }
        if (old.length) {
            out.push({ hdr: true, grp: "old", label: I18n.tr("Earlier") })
            for (const e of old) out.push(e)
        }
        return out
    }

    readonly property int _pad: 20          // panel side padding
    readonly property int _maxList: 452     // list scrolls past this

    function kindColor(k) {
        return k === "error" ? Theme.error
             : k === "success" ? Theme.secondary_container
             : k === "warning" ? Theme.warn
             : Theme.primary
    }
    function kindIcon(k) {
        return k === "error" ? "error"
             : k === "success" ? "check"
             : k === "warning" ? "warning" : "info"
    }
    // the page's own rail icon, so a row reads by source first
    readonly property var _pageIcon: ({
        0: "cloud_download", 2: "history", 3: "monetization_on", 4: "travel_explore",
        5: "archive", 6: "lightbulb", 7: "biotech", 8: "download", 9: "speed",
        10: "settings", 11: "query_stats", 12: "scissors", 13: "messages"
    })
    function sourceIcon(e) {
        const ic = (e.page !== undefined && e.page >= 0) ? _pageIcon[e.page] : undefined
        return ic || kindIcon(e.kind)
    }

    // ── open / close: one motion ──
    // The Popup's own opacity/scale (the path Qt's styles use), so the panel
    // and its shadow move as ONE layer, growing from the bell's corner. The
    // rows are built ahead of time and never animate on open, so there's
    // nothing else for the eye to catch.
    transformOrigin: I18n.rtl ? Item.TopLeft : Item.TopRight
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 260; easing.type: Easing.OutQuint }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: 110; easing.type: Easing.OutCubic }
        }
    }
    // when the tray last started closing (the bell uses it to ignore the
    // click whose press just closed the tray)
    property real closedAt: 0
    onAboutToHide: closedAt = Date.now()
    onAboutToShow: {
        root.filter = "all"
        flick.contentY = 0
    }
    // marked read on CLOSE, so the "New" group means something while you read
    onClosed: Notifications.markAllRead()

    background: Item { }

    contentItem: Item {
        id: stage
        implicitWidth: root.width
        implicitHeight: col.implicitHeight
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        // ── surface ──
        C.GlassPanel {
            id: panel
            anchors.fill: parent
            radius_: 22
            elevation: 2.6
            color: Theme.surface
            // soft accent light pooling at the top
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 1
                height: 150
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.11 : 0.06) }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                }
            }
        }

        Column {
            id: col
            width: parent.width
            topPadding: root._pad
            bottomPadding: Notifications.isEmpty ? root._pad : 10

            // ── header ──
            Item {
                width: col.width
                height: 34

                C.AppText {
                    id: titleTxt
                    anchors.left: parent.left
                    anchors.leftMargin: root._pad
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Notifications")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: 20
                    font.letterSpacing: I18n.lang === "fa" ? 0 : -0.3
                    color: Theme.text_strong
                }

                // live "N new" pill / quiet caught-up note
                Rectangle {
                    id: newPill
                    anchors.left: titleTxt.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool hot: Notifications.unreadCount > 0
                    visible: hot
                    height: 22
                    radius: 11
                    width: pillRow.implicitWidth + 16
                    color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.28)
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primary
                            SequentialAnimation on opacity {
                                running: root.opened && newPill.hot && Tokens.appActive
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.35; to: 1; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                        C.AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("{n} new").replace("{n}", Notifications.unreadCount)
                            font.pixelSize: Tokens.fontMicro
                            weight: Tokens.weightBold
                            color: Theme.primary
                        }
                    }
                }

                // Clear all: quiet text action, warms toward red on hover
                AbstractButton {
                    id: clearBtn
                    visible: !Notifications.isEmpty
                    anchors.right: parent.right
                    anchors.rightMargin: root._pad - 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 30
                    implicitWidth: clearRow.implicitWidth + 20
                    hoverEnabled: true
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: Notifications.clearAll()
                    scale: pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                    background: Rectangle {
                        radius: 15
                        color: clearBtn.hovered ? U.withAlpha(Theme.error, Theme.isDark ? 0.12 : 0.08)
                                                : U.withAlpha(Theme.error, 0)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    contentItem: Item {
                        Row {
                            id: clearRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.IconGlyph {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "delete_sweep"
                                size: 14
                                glyphColor: clearBtn.hovered ? Theme.error : Theme.on_surface_var
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Clear all")
                                font.pixelSize: Tokens.fontCaption
                                weight: Tokens.weightDemiBold
                                color: clearBtn.hovered ? Theme.error : Theme.on_surface_var
                            }
                        }
                    }
                }
            }

            // ── segmented filter ──
            Item { width: 1; height: 14; visible: !Notifications.isEmpty }
            Item {
                id: seg
                visible: !Notifications.isEmpty
                width: col.width
                height: 38
                readonly property real trackW: width - root._pad * 2
                readonly property real segW: (trackW - 8) / 3
                readonly property var opts: [
                    { key: "all",    label: I18n.tr("All"),       n: root._all.length },
                    { key: "alerts", label: I18n.tr("Alerts"),    n: root._alertCount },
                    { key: "done",   label: I18n.tr("Completed"), n: root._doneCount }
                ]
                readonly property int cur: root.filter === "alerts" ? 1 : root.filter === "done" ? 2 : 0

                Item {
                    id: track
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: seg.trackW
                    height: parent.height
                    LayoutMirroring.enabled: false

                    Rectangle {
                        anchors.fill: parent
                        radius: 13
                        color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.07 : 0.055)
                    }
                    // sliding thumb (accent-tinted, lifted)
                    Rectangle {
                        y: 4
                        height: parent.height - 8
                        width: seg.segW
                        x: 4 + seg.segW * (I18n.rtl ? 2 - seg.cur : seg.cur)
                        radius: 10
                        color: Theme.isDark ? U.mix(Theme.surface, Theme.primary, 0.14) : Theme.surface
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.34 : 0.22)
                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 4
                        Repeater {
                            model: I18n.rtl ? seg.opts.slice().reverse() : seg.opts
                            AbstractButton {
                                id: segBtn
                                required property var modelData
                                width: seg.segW
                                height: parent.height
                                hoverEnabled: true
                                readonly property bool on: root.filter === modelData.key
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                onClicked: { root.filter = modelData.key; flick.contentY = 0 }
                                background: Item { }
                                contentItem: Item {
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        LayoutMirroring.enabled: I18n.rtl
                                        C.AppText {
                                            text: segBtn.modelData.label
                                            font.pixelSize: Tokens.fontCaption
                                            weight: segBtn.on ? Tokens.weightBold : Tokens.weightMedium
                                            color: segBtn.on ? Theme.text_strong
                                                 : segBtn.hovered ? Theme.on_surface : Theme.on_surface_var
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Rectangle {
                                            visible: segBtn.modelData.n > 0
                                            height: 18; radius: 9
                                            width: Math.max(18, cnt.implicitWidth + 10)
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: segBtn.on ? Theme.primary
                                                             : U.withAlpha(Theme.on_surface_var, 0.14)
                                            C.AppText {
                                                id: cnt
                                                anchors.centerIn: parent
                                                text: segBtn.modelData.n > 99 ? "99+" : segBtn.modelData.n
                                                mono: true
                                                font.pixelSize: Tokens.fontMicro
                                                weight: Tokens.weightBold
                                                color: segBtn.on ? Theme.on_primary : Theme.on_surface_var
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── empty state (no notifications at all) ──
            Item {
                visible: Notifications.isEmpty
                width: col.width
                height: 236
                Item {
                    id: emptyArt
                    width: 120; height: 120
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 18
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            width: 56 + index * 30; height: width; radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, 0.20 - index * 0.055)
                            SequentialAnimation on scale {
                                running: root.opened && Notifications.isEmpty && Tokens.appActive
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 220 }
                                NumberAnimation { from: 1; to: 1.06; duration: 1500; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 1.06; to: 1; duration: 1500; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 50; height: 50; radius: 17
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.28 : 0.16) }
                            GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.06) }
                        }
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.30)
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: "notifications"; fill: true; size: 22
                            glyphColor: Theme.primary
                        }
                    }
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: emptyArt.bottom
                    anchors.topMargin: Tokens.space3
                    spacing: 4
                    width: parent.width - Tokens.space6 * 2
                    C.AppText {
                        width: parent.width
                        text: I18n.tr("You're all caught up")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.text_strong
                        horizontalAlignment: Text.AlignHCenter
                    }
                    C.AppText {
                        width: parent.width
                        text: I18n.tr("Finished scrapes, downloads and AI jobs will land here.")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        wrapMode: Text.Wrap
                        lineHeight: 1.4
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // ── filtered-out state ──
            Item {
                visible: !Notifications.isEmpty && root.shownCount === 0
                width: col.width
                height: 120
                Column {
                    anchors.centerIn: parent
                    spacing: Tokens.space2
                    C.IconGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: root.filter === "alerts" ? "check_circle" : "hourglass_empty"
                        size: 22
                        glyphColor: root.filter === "alerts" ? Theme.secondary_container : Theme.outline
                    }
                    C.AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.filter === "alerts" ? I18n.tr("No alerts. All clear.") : I18n.tr("Nothing here yet")
                        font.pixelSize: Tokens.fontCaption
                        weight: Tokens.weightDemiBold
                        color: Theme.on_surface_var
                    }
                }
            }

            // ── list ──
            Item { width: 1; height: 8; visible: root.shownCount > 0 }
            Item {
                id: listBox
                visible: root.shownCount > 0
                width: col.width
                // final before the first frame: rows' Column has a synchronous height
                readonly property real targetH: Math.min(rowsCol.implicitHeight, root._maxList)
                readonly property bool overflows: rowsCol.implicitHeight > root._maxList
                height: targetH
                // Filter switches glide to the new height instead of snapping
                // (never on open: the open height must be final at frame one).
                Behavior on height {
                    enabled: root.opened
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: rowsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    // judged on the FINAL height, so the glide can't flash the bar
                    interactive: listBox.overflows
                    ScrollBar.vertical: ScrollBar {
                        policy: listBox.overflows ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    Column {
                        id: rowsCol
                        x: 10
                        width: flick.width - 20
                        spacing: 4

                        Repeater {
                            model: root.rows

                            delegate: Item {
                                id: d
                                required property var modelData
                                required property int index
                                readonly property bool isHdr: modelData.hdr === true
                                // hidden, not destroyed, when the filter leaves it out
                                readonly property bool shown: isHdr
                                    ? (modelData.grp === "new" ? root._shownFresh > 0 : root._shownOld > 0)
                                    : root._matches(modelData)
                                readonly property bool firstShown: isHdr
                                    && (modelData.grp === "new" || root._shownFresh === 0)
                                visible: shown
                                width: rowsCol.width
                                height: !shown ? 0 : isHdr ? (firstShown ? 24 : 34) : card.height

                                // ── group header ──
                                C.AppText {
                                    visible: d.isHdr
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                    text: d.modelData.label || ""
                                    font.pixelSize: Tokens.fontMicro
                                    weight: Tokens.weightBold
                                    font.capitalization: I18n.lang === "fa" ? Font.MixedCase : Font.AllUppercase
                                    font.letterSpacing: I18n.lang === "fa" ? 0 : 1.4
                                    color: Theme.outline
                                }

                                // ── notification row ──
                                Item {
                                    id: card
                                    visible: !d.isHdr
                                    width: parent.width
                                    readonly property int pad: 12
                                    readonly property real fullH: d.isHdr ? 0
                                        : Math.max(tile.height, textCol.implicitHeight) + pad * 2
                                    height: fullH * (1 - collapse)
                                    clip: collapse > 0

                                    readonly property color accent: root.kindColor(d.modelData.kind)
                                    readonly property bool unread: d.modelData.read === false
                                    readonly property bool linked: d.modelData.page !== undefined && d.modelData.page >= 0
                                    readonly property bool hovered: cardHover.hovered
                                    readonly property string msg: String(d.modelData.message || "")
                                    readonly property int nl: msg.indexOf("\n")
                                    readonly property string line: nl >= 0 ? msg.slice(0, nl) : msg
                                    readonly property string extra: nl >= 0 ? msg.slice(nl + 1).trim() : ""
                                    // "Download finished — <video title>" → status + detail
                                    readonly property int sep: {
                                        const a = line.indexOf(" \u2014 ")
                                        const b = line.indexOf(" \u2013 ")
                                        const i = a >= 0 ? a : b
                                        return (i > 0 && i <= 48) ? i : -1
                                    }
                                    readonly property string status: sep >= 0 ? line.slice(0, sep).trim() : line
                                    readonly property string detail: sep >= 0 ? line.slice(sep + 3).trim() : ""

                                    property real out: 0        // dismiss: fade + slide
                                    property real collapse: 0   // dismiss: then fold the gap

                                    HoverHandler { id: cardHover; cursorShape: card.linked ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                    // whole-row click: jump to its page (and mark read)
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            Notifications.openPage(d.modelData.id)
                                            if (card.linked) root.close()
                                        }
                                    }

                                    Item {
                                        id: face
                                        width: parent.width
                                        height: card.fullH
                                        opacity: 1 - card.out
                                        transform: Translate { x: card.out * (I18n.rtl ? -40 : 40) }

                                        // row surface: borderless at rest, tinted when new / hovered
                                        //
                                        // v1.1.3 — THE HOVER FLASH. This used to be ONE rectangle
                                        // whose colour animated from the unread tint (accent at
                                        // ~7% alpha) to an OPAQUE surface grey. A ColorAnimation
                                        // runs r,g,b and alpha together, so halfway through it
                                        // painted the accent at ~50% alpha: every row the pointer
                                        // entered (and the one it just left) flashed bright red /
                                        // green for 160ms, which read as two rows "blinking".
                                        // Now the unread tint is a fixed layer and hover is a
                                        // separate neutral wash that only fades its OPACITY, so
                                        // there is no colour midpoint left to flash through.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 16
                                            visible: card.unread
                                            color: U.withAlpha(card.accent, Theme.isDark ? 0.075 : 0.05)
                                            border.width: 1
                                            border.color: U.withAlpha(card.accent, 0.16)
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 16
                                            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.055) : Qt.rgba(0, 0, 0, 0.035)
                                            border.width: 1
                                            border.color: Theme.border_soft
                                            opacity: card.hovered ? 1 : 0
                                            visible: opacity > 0.001
                                            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        }

                                        // source tile + kind badge
                                        Item {
                                            id: tile
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.leftMargin: card.pad
                                            anchors.topMargin: card.pad
                                            width: 40; height: 40
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 13
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: U.withAlpha(card.accent, Theme.isDark ? 0.24 : 0.15) }
                                                    GradientStop { position: 1.0; color: U.withAlpha(card.accent, Theme.isDark ? 0.08 : 0.05) }
                                                }
                                                border.width: 1
                                                border.color: U.withAlpha(card.accent, 0.26)
                                            }
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: root.sourceIcon(d.modelData)
                                                size: 18
                                                glyphColor: card.accent
                                            }
                                            Rectangle {
                                                visible: card.linked
                                                width: 17; height: 17; radius: 8.5
                                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                                anchors.rightMargin: -4; anchors.bottomMargin: -4
                                                color: card.accent
                                                border.width: 2.5
                                                border.color: Theme.surface
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    name: root.kindIcon(d.modelData.kind)
                                                    fill: true
                                                    size: 9
                                                    glyphColor: "#FFFFFF"
                                                }
                                            }
                                        }

                                        // text column (anchors + explicit widths: height is known at once)
                                        Column {
                                            id: textCol
                                            anchors.left: tile.right
                                            anchors.leftMargin: 12
                                            anchors.right: parent.right
                                            anchors.rightMargin: card.pad
                                            anchors.top: parent.top
                                            anchors.topMargin: card.pad - 1
                                            spacing: 3

                                            // source · time · unread dot  (dismiss ✕ takes over on hover)
                                            Item {
                                                width: textCol.width
                                                height: 20
                                                C.AppText {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Math.min(implicitWidth, parent.width - meta.width - 10)
                                                    text: I18n.tr(String(d.modelData.title || ""))
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontBody
                                                    color: Theme.text_strong
                                                    elide: Text.ElideRight
                                                }
                                                Row {
                                                    id: meta
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 7
                                                    opacity: card.hovered ? 0 : 1
                                                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                                    C.AppText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: d.modelData.time || ""
                                                        font.pixelSize: Tokens.fontMicro
                                                        weight: Tokens.weightMedium
                                                        color: Theme.outline
                                                    }
                                                    Rectangle {
                                                        visible: card.unread
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 7; height: 7; radius: 3.5
                                                        color: card.accent
                                                    }
                                                }
                                            }

                                            // status line ("Download finished")
                                            C.AppText {
                                                visible: card.status !== ""
                                                width: textCol.width
                                                text: card.status
                                                font.pixelSize: Tokens.fontCaption + 1
                                                weight: card.detail !== "" ? Tokens.weightDemiBold : Tokens.weightRegular
                                                color: Theme.on_surface
                                                wrapMode: Text.Wrap
                                                maximumLineCount: card.detail !== "" ? 1 : 3
                                                elide: Text.ElideRight
                                                lineHeight: 1.3
                                            }
                                            // detail (the video / file it's about), quieter, two lines max
                                            C.AppText {
                                                visible: card.detail !== ""
                                                width: textCol.width
                                                text: card.detail
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                                lineHeight: 1.35
                                            }

                                            // second message line (a saved file path, usually) as a mono chip
                                            Item { width: 1; height: 3; visible: card.extra !== "" }
                                            Rectangle {
                                                visible: card.extra !== ""
                                                width: textCol.width
                                                height: 26
                                                radius: 9
                                                color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.08 : 0.06)
                                                C.IconGlyph {
                                                    id: pathIc
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: "folder_open"; size: 13
                                                    glyphColor: Theme.on_surface_var
                                                }
                                                C.AppText {
                                                    anchors.left: pathIc.right
                                                    anchors.leftMargin: 6
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: card.extra
                                                    mono: true
                                                    font.pixelSize: Tokens.fontMicro
                                                    color: Theme.on_surface_var
                                                    elide: Text.ElideMiddle
                                                }
                                            }
                                        }

                                        // "go" chevron, only when the row leads somewhere
                                        C.IconGlyph {
                                            visible: card.linked
                                            anchors.right: parent.right
                                            anchors.rightMargin: card.pad
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: card.pad
                                            name: I18n.rtl ? "arrow_back" : "arrow_forward"
                                            size: 14
                                            glyphColor: Theme.primary
                                            opacity: card.hovered ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 160 } }
                                        }

                                        // dismiss ✕ (replaces the time on hover)
                                        C.IconButton {
                                            z: 2
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.topMargin: 7
                                            anchors.rightMargin: 7
                                            implicitWidth: 26; implicitHeight: 26
                                            iconName: "close"
                                            glyphSize: 13
                                            tip: I18n.tr("Dismiss")
                                            opacity: card.hovered ? 1 : 0
                                            enabled: card.hovered
                                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                            onClicked: dismissAnim.restart()
                                        }
                                    }

                                    SequentialAnimation {
                                        id: dismissAnim
                                        NumberAnimation { target: card; property: "out"; to: 1; duration: 180; easing.type: Easing.InCubic }
                                        NumberAnimation { target: card; property: "collapse"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                        ScriptAction { script: Notifications.dismiss(d.modelData.id) }
                                    }
                                }
                            }
                        }
                    }
                }

                // soft fade where the list scrolls on
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 36
                    visible: listBox.overflows
                    opacity: flick.atYEnd ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.surface, 0) }
                        GradientStop { position: 1.0; color: Theme.surface }
                    }
                }
            }
        }
    }
}
