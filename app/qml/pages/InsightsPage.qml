import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "../components" as C
import "../Utils.js" as U

// SNAPSHOT INSIGHTS — v12 "scan room" redesign.
//
// Same data, same VM contract (InsightsVM is untouched), a different reading
// experience. The v11 page was one very long column of equal-weight panels:
// the computed verdict, the numbers, the AI brief and the audit trail all
// claimed the same amount of attention. v12 gives the page a spine:
//
//   1. COVER     — the query set big, the computed verdict under it, and a
//                  three-step pipeline (Measured → Written → Audited) that is
//                  both a status read-out and the page's navigation.
//   2. LENSES    — four views of one snapshot instead of one endless scroll:
//                  Measured · Brief · Evidence · Limits. A sliding pill says
//                  which one is open; Ctrl+1…4 switch without the mouse.
//   3. INTERACTION where the data earns it — hover a channel to light its
//      slice of the share bar, flip the leaders between "fastest" and
//      "reaching past their audience", click a term to copy it, focus one
//      evidence class, step through the experiments as a pipeline, filter and
//      unfold the evidence ledger.
//
// The honesty rules of v11 all survive: the verdict is labelled as arithmetic,
// every AI statement keeps its Observed / Inferred / Needs-Studio class and
// colour, and owner-only metrics stay amber everywhere they appear.
Item {
    id: page

    // ── evidence-class colours (unchanged mapping) ──
    function classColor(key) {
        return key === "primary" ? Theme.primary
             : key === "secondary_container" ? Theme.secondary_container
             : Theme.warn
    }
    function classTint(cls) {
        return cls === "observed" ? Theme.primary
             : cls === "inferred" ? Theme.secondary_container
             : Theme.warn
    }
    // confidence colour: high reads green, medium a muted olive, low grey —
    // deliberately never the amber that means "needs YouTube Studio"
    function confTint(c) {
        return c === "high" ? Theme.secondary_container
             : c === "medium" ? U.mix(Theme.secondary_container, Theme.on_surface_var, 0.55)
             : Theme.outline
    }

    // ── lens state ──
    // 0 Measured · 1 Brief · 2 Evidence · 3 Limits
    property int lens: 0
    function goLens(i) {
        if (i === page.lens) return
        page.lens = i
        lensEnter.restart()
        scroller.scrollToItem(lensBar, Tokens.space4)
    }

    readonly property bool briefOk: Insights.hasBrief && Insights.brief.ok === true
    readonly property int claimCount: (Insights.claims || []).length
    readonly property int observedCount: briefOk ? (Insights.brief.observed || []).length : 0
    readonly property int inferredCount: briefOk ? (Insights.brief.inferred || []).length : 0
    readonly property int studioCount: briefOk ? (Insights.brief.requires_studio || []).length : 0

    // v1.1.3: re-read the AI provider on show (AI Ideas / Content Lab do the
    // same), so a key saved in Settings is picked up without a restart.
    onVisibleChanged: if (visible) {
        Insights.reloadConfig()
        Insights.refreshHistory()
    }

    Shortcut { sequences: ["Ctrl+1"]; enabled: page.visible && Insights.hasSnapshot; onActivated: page.goLens(0) }
    Shortcut { sequences: ["Ctrl+2"]; enabled: page.visible && Insights.hasSnapshot; onActivated: page.goLens(1) }
    Shortcut { sequences: ["Ctrl+3"]; enabled: page.visible && Insights.hasSnapshot; onActivated: page.goLens(2) }
    Shortcut { sequences: ["Ctrl+4"]; enabled: page.visible && Insights.hasSnapshot; onActivated: page.goLens(3) }

    // A new snapshot is a new arrival: back to the numbers, and the scan beam
    // sweeps the cover once. A finished brief opens its own lens, because the
    // creator just waited minutes for it and should not have to go looking.
    property bool _wasBusy: false
    Connections {
        target: Insights
        function onSnapshotChanged() {
            page.lens = 0
            scanOnce.restart()
        }
        function onBusyChanged() {
            if (page._wasBusy && !Insights.busy && Insights.hasBrief)
                page.goLens(1)
            page._wasBusy = Insights.busy
        }
    }

    // Clipboard without a VM round-trip: an invisible TextEdit does the copy.
    TextEdit {
        id: clipHelper
        visible: false
        function put(t) {
            text = t
            selectAll()
            copy()
            text = ""
        }
    }

    // lens content arrives with a short fade + rise (transform only)
    ParallelAnimation {
        id: lensEnter
        NumberAnimation { target: lensBody; property: "opacity"; from: 0.0; to: 1.0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
        NumberAnimation { target: lensShift; property: "y"; from: 12; to: 0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
    }

    // ════════════════════════════════════════════════════════════════════
    //  inline building blocks
    // ════════════════════════════════════════════════════════════════════

    // Section header: icon tile, title, a quiet hint, and any trailing
    // controls the caller drops in (they land after the spacer).
    component SectionHead: RowLayout {
        id: sh
        property string title: ""
        property string hint: ""
        property string icon: ""
        property color tint: Theme.primary
        Layout.fillWidth: true
        spacing: Tokens.space3

        Rectangle {
            visible: sh.icon !== ""
            implicitWidth: 32; implicitHeight: 32
            radius: Tokens.radiusSm
            color: U.withAlpha(sh.tint, Theme.isDark ? 0.14 : 0.10)
            border.width: 1
            border.color: U.withAlpha(sh.tint, 0.22)
            C.IconGlyph {
                anchors.centerIn: parent
                name: sh.icon
                size: 16
                glyphColor: sh.tint
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            C.AppText {
                Layout.fillWidth: true
                text: sh.title
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontSubtitle
                font.letterSpacing: I18n.rtl ? 0 : -0.2
                color: Theme.text_strong
                elide: Text.ElideRight
            }
            C.AppText {
                Layout.fillWidth: true
                visible: text !== ""
                text: sh.hint
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                elide: Text.ElideRight
            }
        }
    }

    // Small uppercase label used inside cards.
    component Eyebrow: C.AppText {
        mono: true
        weight: Tokens.weightBold
        font.pixelSize: Tokens.fontMicro
        font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
        color: Theme.on_surface_var
    }

    // A rounded thumbnail with the shared skeleton while it loads.
    component Thumb: Rectangle {
        id: thumbBox
        property string thumbId: ""
        property int srcW: 320
        radius: Tokens.radiusSm
        color: Theme.surface_low
        // v3.42: the picture is MASKED to the rounded shape. The old
        // `clip: true` only ever cuts to the square bounding box, so the
        // thumbnail painted straight over the radius and every Moving-fastest
        // tile (the big #1 and the small 02-05 rows) came out sharp-cornered.
        C.RoundClip {
            anchors.fill: parent
            radius: thumbBox.radius
            active: thumbImg.status === Image.Ready
            Image {
                id: thumbImg
                anchors.fill: parent
                source: thumbBox.thumbId ? ("image://thumbs/" + thumbBox.thumbId) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: thumbBox.srcW
                sourceSize.height: Math.round(thumbBox.srcW * 9 / 16)
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
        }
        C.ThumbSkeleton {
            anchors.fill: parent
            active: thumbBox.thumbId !== "" && thumbImg.status !== Image.Ready
            topLeftRadius: parent.radius
            topRightRadius: parent.radius
            bottomLeftRadius: parent.radius
            bottomRightRadius: parent.radius
            glyph: "movie"
        }
    }

    // One headline number. The segmented meter is the tile's VM `meter`
    // (coverage for three tiles, dominance for the channel tile) — ten cells
    // so "7 of 10" reads without a legend.
    component KpiTile: C.GlassPanel {
        id: kpi
        property string caption: ""
        property string icon: ""
        property string value: "—"
        property string sub: ""
        property real meter: 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: kpiCol.implicitHeight + Tokens.space5 * 2
        radius: Tokens.radiusXl
        hoverGlow: true
        elevation: hovered ? 1.5 : 1.0
        Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }

        C.CornerGlow {
            radius: kpi.radius
            size: 260
            opacity: kpi.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durGlow } }
        }

        ColumnLayout {
            id: kpiCol
            anchors.fill: parent
            anchors.margins: Tokens.space5
            spacing: Tokens.space2

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                C.IconGlyph {
                    name: kpi.icon
                    size: 15
                    glyphColor: kpi.hovered ? Theme.primary : Theme.on_surface_var
                    Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }
                Eyebrow {
                    Layout.fillWidth: true
                    text: kpi.caption
                    elide: Text.ElideRight
                }
            }
            C.AppText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space1
                text: kpi.value
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: 34
                font.letterSpacing: -1
                color: Theme.text_strong
                elide: Text.ElideRight
                LayoutMirroring.enabled: false
                horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
            }
            C.AppText {
                Layout.fillWidth: true
                text: kpi.sub
                visible: text !== ""
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                maximumLineCount: kpi.hovered ? 4 : 2
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }
            Row {
                id: cells
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space2
                spacing: 3
                readonly property int lit: Math.round(Math.max(0, Math.min(1, kpi.meter)) * 10)
                Repeater {
                    model: 10
                    Rectangle {
                        width: (cells.width - 9 * cells.spacing) / 10
                        height: 5
                        radius: 2.5
                        color: index < cells.lit
                               ? U.withAlpha(Theme.primary, 0.45 + 0.55 * (index + 1) / 10)
                               : U.withAlpha(Theme.outline, 0.18)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                    }
                }
            }
        }
    }

    // A compact ranked leader row (rank, thumbnail, title, metric pill).
    component LeaderRow: Rectangle {
        id: lr
        property var row: ({})
        property int rank: 1
        Layout.fillWidth: true
        implicitHeight: 64
        radius: Tokens.radiusMd
        color: lrHover.hovered ? U.hoverTint(Theme.panel_bg, Theme.isDark, 0.05) : U.withAlpha(U.hoverTint(Theme.panel_bg, Theme.isDark, 0.05), 0)
        border.width: 1
        border.color: lrHover.hovered ? Theme.border : "transparent"
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

        HoverHandler { id: lrHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (lr.row.videoUrl) Qt.openUrlExternally(lr.row.videoUrl) }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.space2
            spacing: Tokens.space3

            C.AppText {
                text: lr.rank < 10 ? "0" + lr.rank : String(lr.rank)
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontCaption
                color: lrHover.hovered ? Theme.primary : Theme.outline
                Layout.minimumWidth: 20
                LayoutMirroring.enabled: false
            }
            Thumb {
                implicitWidth: 80; implicitHeight: 45
                radius: Tokens.radiusSm      // 8px on a 45px tile: soft, not a pill
                thumbId: lr.row.thumbId || ""
                srcW: 160
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: "play_circle"; fill: true; size: 20
                    glyphColor: "white"
                    opacity: lrHover.hovered ? 0.95 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                C.AppText {
                    Layout.fillWidth: true
                    text: lr.row.title || ""
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption + 1
                    color: Theme.text_strong
                    elide: Text.ElideRight
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: (lr.row.channelTitle || "") + "  ·  " + (lr.row.views || "")
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                radius: Tokens.radiusPill
                implicitWidth: lrVal.implicitWidth + Tokens.space4
                implicitHeight: 26
                color: U.withAlpha(Theme.primary, lrHover.hovered ? 0.22 : 0.13)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                C.AppText {
                    id: lrVal
                    anchors.centerIn: parent
                    text: lr.row.value || ""
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.primary
                    LayoutMirroring.enabled: false
                }
            }
        }
    }

    // A pill of a fixed tint — class labels, confidence, counters.
    // Signal-strength confidence: three rising bars, `level` of them lit.
    component ConfBars: Row {
        property int level: 1
        property color tint: Theme.secondary_container
        spacing: 2
        height: 12
        Repeater {
            model: 3
            Rectangle {
                anchors.bottom: parent.bottom
                width: 3.5
                height: 5 + index * 3.5
                radius: 1.5
                color: index < parent.level ? parent.tint
                                            : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.16 : 0.14)
            }
        }
    }

    // A quiet pill action (icon + label) for toolbars and card footers.
    component PillAction: AbstractButton {
        id: pa
        property string glyph: ""
        property string label: ""
        implicitHeight: 32
        implicitWidth: paRow.implicitWidth + Tokens.space3 * 2
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        scale: pressed ? Tokens.pressScale : 1
        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
        background: Rectangle {
            radius: Tokens.radiusPill
            color: pa.hovered ? Theme.hover_bg : Theme.panel_bg
            border.width: 1
            border.color: pa.hovered ? U.withAlpha(Theme.primary, 0.40) : Theme.border
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            Row {
                id: paRow
                anchors.centerIn: parent
                spacing: 6
                C.IconGlyph {
                    name: pa.glyph; size: 14
                    glyphColor: pa.hovered ? Theme.primary : Theme.on_surface_var
                    anchors.verticalCenter: parent.verticalCenter
                }
                C.AppText {
                    text: pa.label
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption + 1
                    color: Theme.on_surface
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    component Tag: Rectangle {
        property string label: ""
        property color tint: Theme.on_surface_var
        property bool strong: false
        radius: Tokens.radiusPill
        implicitWidth: tagLbl.implicitWidth + Tokens.space3 + 2
        implicitHeight: 22
        color: U.withAlpha(tint, strong ? 0.20 : 0.12)
        border.width: 1
        border.color: U.withAlpha(tint, 0.30)
        C.AppText {
            id: tagLbl
            anchors.centerIn: parent
            text: parent.label
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontMicro
            color: parent.tint
        }
    }


    // A small lit pill: icon + uppercase label. Used as the brief's masthead.
    component Badge: Rectangle {
        id: bdg
        property string label: ""
        property string icon: ""
        property color tint: Theme.primary
        implicitWidth: bdgRow.implicitWidth + Tokens.space3 * 2
        implicitHeight: 26
        radius: Tokens.radiusPill
        color: U.withAlpha(tint, Theme.isDark ? 0.13 : 0.09)
        border.width: 1
        border.color: U.withAlpha(tint, 0.30)
        Row {
            id: bdgRow
            anchors.centerIn: parent
            spacing: 6
            C.IconGlyph {
                visible: bdg.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: bdg.icon
                size: 13
                glyphColor: bdg.tint
            }
            Eyebrow {
                anchors.verticalCenter: parent.verticalCenter
                text: bdg.label
                color: bdg.tint
            }
        }
    }

    // ── v3.39.8 chart parts (shape-of-the-set panels) ──────────────────

    // A big number with a quiet caption, for a SectionHead's trailing slot.
    component StatBlock: ColumnLayout {
        id: stb
        property string value: "—"
        property string caption: ""
        spacing: 0
        C.AppText {
            Layout.alignment: Qt.AlignRight
            text: stb.value
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontDisplay
            font.letterSpacing: -0.8
            color: Theme.text_strong
            LayoutMirroring.enabled: false
        }
        C.AppText {
            Layout.alignment: Qt.AlignRight
            text: stb.caption
            font.pixelSize: Tokens.fontMicro
            color: Theme.on_surface_var
        }
    }

    // "50%  are over 20 min" — the one sentence a panel is about, with the
    // number set in the bucket's own hue so it links to the chart below.
    component LeadLine: Rectangle {
        id: ll
        property string big: ""
        property string text: ""
        property color tint: Theme.primary
        implicitHeight: 48
        radius: Tokens.radiusMd
        color: U.withAlpha(tint, Theme.isDark ? 0.09 : 0.07)
        border.width: 1
        border.color: U.withAlpha(tint, 0.22)
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            width: 3
            radius: 1.5
            color: ll.tint
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space5
            anchors.rightMargin: Tokens.space4
            spacing: Tokens.space3
            C.AppText {
                text: ll.big
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontTitle
                font.letterSpacing: -0.6
                color: ll.tint
                LayoutMirroring.enabled: false
            }
            C.AppText {
                Layout.fillWidth: true
                text: ll.text
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontBody
                color: Theme.text_strong
                elide: Text.ElideRight
            }
        }
    }

    // A segmented 100% bar. `items` is [{frac, color}]; empty parts vanish,
    // the rest keep a 3 px gap. Hover reports (index, on) to the owner.
    component MixBar: Item {
        id: mb
        property var items: []
        property int hot: -1
        property real grow: 1
        signal hover(int i, bool on)
        implicitHeight: 14
        readonly property int _nz: {
            var n = 0
            for (var i = 0; i < (items ? items.length : 0); i++)
                if ((items[i].frac || 0) > 0) n++
            return n
        }
        Row {
            id: mbRow
            anchors.fill: parent
            spacing: 3
            Repeater {
                model: mb.items
                Rectangle {
                    required property var modelData
                    required property int index
                    visible: (modelData.frac || 0) > 0
                    height: mbRow.height
                    width: Math.max(4, (mbRow.width - Math.max(0, mb._nz - 1) * mbRow.spacing) * (modelData.frac || 0) * mb.grow)
                    radius: Math.min(height / 2, width / 2)
                    color: modelData.color
                    opacity: mb.hot < 0 || mb.hot === index ? 1 : 0.28
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    HoverHandler { onHoveredChanged: mb.hover(index, hovered) }
                }
            }
        }
    }

    // One bucket of a scale: swatch · label · bar · count · percent.
    component MixRow: Item {
        id: mr
        property string label: ""
        property int count: 0
        property real frac: 0
        property string pctText: ""
        property color tint: Theme.primary
        property bool isTop: false
        property bool lit: false
        property bool dim: false
        property real grow: 1
        signal hover(bool on)
        Layout.fillWidth: true
        implicitHeight: 36
        opacity: count === 0 ? 0.4 : (dim ? 0.55 : 1)
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        HoverHandler { onHoveredChanged: mr.hover(hovered) }

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: U.withAlpha(mr.tint, mr.lit ? 0.10 : 0)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space2
            anchors.rightMargin: Tokens.space2
            spacing: Tokens.space3
            Rectangle {
                implicitWidth: 10; implicitHeight: 10
                radius: 3
                color: mr.tint
            }
            C.AppText {
                Layout.preferredWidth: 104
                text: mr.label
                weight: mr.isTop ? Tokens.weightBold : Tokens.weightMedium
                font.pixelSize: Tokens.fontCaption + 1
                color: (mr.isTop || mr.lit) ? Theme.text_strong : Theme.on_surface
                elide: Text.ElideRight
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: 8
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: U.withAlpha(Theme.outline, 0.12)
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    visible: mr.count > 0
                    width: Math.max(6, parent.width * mr.frac * mr.grow)
                    radius: 4
                    color: mr.tint
                }
            }
            C.AppText {
                text: String(mr.count)
                mono: true
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                Layout.minimumWidth: 22
                horizontalAlignment: Text.AlignRight
                LayoutMirroring.enabled: false
            }
            C.AppText {
                text: mr.pctText
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontBody
                color: mr.lit ? mr.tint : Theme.text_strong
                Layout.minimumWidth: 44
                horizontalAlignment: Text.AlignRight
                LayoutMirroring.enabled: false
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  page
    // ════════════════════════════════════════════════════════════════════
    C.SmoothScrollView {
        id: scroller
        anchors.fill: parent

        Item {
            width: parent.width
            implicitHeight: content.implicitHeight + Tokens.space7 * 2

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 520
            }

            ColumnLayout {
                id: content
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space7
                spacing: Tokens.space5

                readonly property bool wide: width >= 1080

                // ═══ EMPTY STATE ═══════════════════════════════════════
                // Not a shrug — the three real steps that lead here, in order.
                C.GlassPanel {
                    id: emptyHero
                    Layout.fillWidth: true
                    visible: !Insights.hasSnapshot
                    radius: Tokens.radiusXl
                    implicitHeight: emptyCol.implicitHeight + Tokens.space8 * 2
                                        C.CornerGlow { radius: emptyHero.radius; size: 640 }

                    ColumnLayout {
                        id: emptyCol
                        anchors.centerIn: parent
                        width: Math.min(820, parent.width - Tokens.space7 * 2)
                        spacing: Tokens.space4

                        C.IconTile {
                            iconName: "nav_insights"
                            size: 56
                            solid: true
                            lit: true
                            breathe: Tokens.appActive
                            Layout.alignment: Qt.AlignHCenter
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Read a niche as one set")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: 34
                            font.letterSpacing: I18n.rtl ? 0 : -0.8
                            color: Theme.text_strong
                            wrapMode: Text.WordWrap
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: I18n.tr("Who holds it, how long and how fresh the videos are, what is moving — measured for free from rows you already have.")
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.on_surface_var
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space3
                            columns: emptyCol.width < 640 ? 1 : 3
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3
                            Repeater {
                                model: [
                                    { n: "1", i: "travel_explore", t: I18n.tr("Search in Niche Finder") },
                                    { n: "2", i: "insights",       t: I18n.tr("Press “Analyze these results”") },
                                    { n: "3", i: "nav_insights",   t: I18n.tr("Read the whole set here") }
                                ]
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: Tokens.radiusLg
                                    color: Theme.surface_low
                                    border.width: 1
                                    border.color: Theme.border
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space3
                                        spacing: Tokens.space3
                                        Rectangle {
                                            implicitWidth: 34; implicitHeight: 34
                                            radius: 17
                                            color: U.withAlpha(Theme.primary, 0.14)
                                            C.AppText {
                                                anchors.centerIn: parent
                                                text: modelData.n
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: Tokens.fontBody
                                                color: Theme.primary
                                            }
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: modelData.t
                                            weight: Tokens.weightDemiBold
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.on_surface
                                            wrapMode: Text.WordWrap
                                        }
                                        C.IconGlyph {
                                            name: modelData.i; size: 18
                                            glyphColor: Theme.outline
                                        }
                                    }
                                }
                            }
                        }

                        C.PrimaryButton {
                            Layout.topMargin: Tokens.space2
                            iconName: "travel_explore"
                            text: I18n.tr("Go to Niche Finder")
                            Layout.alignment: Qt.AlignHCenter
                            onClicked: App.goto(4)
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Or open a saved section in Search Archive. This page costs no API quota.")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.outline
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ═══ COVER ═════════════════════════════════════════════
                C.GlassPanel {
                    id: cover
                    Layout.fillWidth: true
                    visible: Insights.hasSnapshot
                    radius: Tokens.radiusXl
                    elevation: 1.3
                                        implicitHeight: coverGrid.implicitHeight + Tokens.space6 * 2

                    C.CornerGlow { radius: cover.radius; size: 720 }

                    // faint measuring grid — the cover is an instrument panel
                    Item {
                        anchors.fill: parent
                        opacity: Theme.isDark ? 0.55 : 0.4
                        Repeater {
                            model: Math.max(0, Math.ceil(cover.width / 48))
                            Rectangle {
                                x: index * 48
                                width: 1
                                height: cover.height
                                color: U.withAlpha(Theme.outline, 0.07)
                            }
                        }
                        Repeater {
                            model: Math.max(0, Math.ceil(cover.height / 48))
                            Rectangle {
                                y: index * 48
                                height: 1
                                width: cover.width
                                color: U.withAlpha(Theme.outline, 0.07)
                            }
                        }
                    }

                    // SIGNATURE — the scan beam. It sweeps the cover once when a
                    // snapshot arrives and keeps sweeping while the AI reads it.
                    // masked to the cover's rounded shape (a plain clip: true is
                    // square, so the beam slid out past the rounded corners)
                    C.RoundClip {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: cover.radius - 1
                        active: scanBeam.opacity > 0
                        Rectangle {
                            id: scanBeam
                            width: 220
                            height: parent.height
                            x: -width
                            opacity: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                                GradientStop { position: 0.85; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.07) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 30
                                width: 2
                                height: parent.height
                                color: U.withAlpha(Theme.primary, 0.55)
                            }
                        }
                    }
                    SequentialAnimation {
                        id: scanOnce
                        PropertyAction { target: scanBeam; property: "opacity"; value: 1 }
                        NumberAnimation {
                            target: scanBeam; property: "x"
                            from: -scanBeam.width; to: cover.width
                            duration: 1500; easing.type: Easing.InOutCubic
                        }
                        PropertyAction { target: scanBeam; property: "opacity"; value: 0 }
                    }
                    SequentialAnimation {
                        id: scanLoop
                        running: Insights.busy && Tokens.appActive && page.visible
                        loops: Animation.Infinite
                        PropertyAction { target: scanBeam; property: "opacity"; value: 1 }
                        NumberAnimation {
                            target: scanBeam; property: "x"
                            from: -scanBeam.width; to: cover.width
                            duration: 2200; easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: 260 }
                        onStopped: scanBeam.opacity = 0
                    }
                    Component.onCompleted: if (Insights.hasSnapshot) scanOnce.start()

                    GridLayout {
                        id: coverGrid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        columns: content.wide ? 2 : 1
                        columnSpacing: Tokens.space7
                        rowSpacing: Tokens.space5

                        // ── left: the set itself ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Tokens.space3

                            RowLayout {
                                spacing: Tokens.space2
                                Rectangle {
                                    implicitWidth: liveRow.implicitWidth + Tokens.space4
                                    implicitHeight: 26
                                    radius: Tokens.radiusPill
                                    color: U.withAlpha(Theme.primary, 0.12)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.primary, 0.30)
                                    Row {
                                        id: liveRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Rectangle {
                                            id: liveDot
                                            width: 7; height: 7; radius: 3.5
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                            SequentialAnimation on opacity {
                                                running: Tokens.appActive && page.visible
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                                            }
                                        }
                                        C.AppText {
                                            text: I18n.tr("SNAPSHOT")
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontMicro
                                            font.letterSpacing: I18n.rtl ? 0 : 1.2
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                                C.AppText {
                                    text: I18n.tr("{n} videos").replace("{n}", Insights.snap.total_videos || 0)
                                          + "  ·  "
                                          + I18n.tr("{n} channels").replace("{n}", Insights.snap.unique_channels || 0)
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                            }

                            C.AppText {
                                Layout.fillWidth: true
                                text: Insights.query || I18n.tr("Untitled")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: content.width < 760 ? 32 : 44
                                font.letterSpacing: I18n.rtl ? 0 : -1.4
                                lineHeight: 1.04
                                color: Theme.text_strong
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            // the computed verdict — set like a standfirst
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space1
                                spacing: Tokens.space3
                                Rectangle {
                                    implicitWidth: 3
                                    Layout.fillHeight: true
                                    radius: 2
                                    color: Theme.primary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space1
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: Insights.verdict
                                        weight: Tokens.weightMedium
                                        font.pixelSize: 18
                                        lineHeight: 1.18
                                        color: Theme.on_surface
                                        wrapMode: Text.WordWrap
                                        selectable: true
                                    }
                                    RowLayout {
                                        spacing: 6
                                        C.IconGlyph { name: "math"; size: 13; glyphColor: Theme.outline }
                                        C.AppText {
                                            text: I18n.tr("Measured from the result rows — no AI involved, no quota spent.")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.outline
                                        }
                                    }
                                }
                            }

                            // actions
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space3
                                spacing: Tokens.space2
                                C.PrimaryButton {
                                    iconName: Insights.hasBrief ? "refresh" : "auto_awesome"
                                    text: Insights.busy ? I18n.tr("Reading …")
                                          : Insights.hasBrief ? I18n.tr("Re-analyze")
                                          : I18n.tr("Generate brief")
                                    indeterminate: Insights.busy
                                    enabled: Insights.hasSnapshot && !Insights.busy
                                    onClicked: Insights.generateBrief(Insights.hasBrief)
                                }
                                // v3.42: "Send winners to AI Ideas" removed on request —
                                // the brief is read here; picking references happens
                                // per card (the ✦ tile on every video card).
                                Rectangle {
                                    visible: Insights.hasBrief && Insights.fromCache
                                    radius: Tokens.radiusPill
                                    color: Theme.surface_low
                                    border.width: 1
                                    border.color: Theme.border
                                    width: cacheRow.implicitWidth + Tokens.space4
                                    height: Tokens.fieldHeight
                                    Row {
                                        id: cacheRow
                                        anchors.centerIn: parent
                                        spacing: Tokens.space2
                                        C.IconGlyph {
                                            name: "history"; size: 14
                                            glyphColor: Theme.on_surface_var
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        C.AppText {
                                            text: I18n.tr("Saved brief · {t}").replace("{t}", Insights.generatedAt)
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }

                        // ── right: the pipeline (status + navigation in one) ──
                        Rectangle {
                            Layout.fillWidth: !content.wide
                            Layout.preferredWidth: content.wide ? 360 : -1
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: pipeCol.implicitHeight + Tokens.space4 * 2
                            radius: Tokens.radiusLg
                            color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.82 : 0.92)
                            border.width: 1
                            border.color: Theme.border

                            ColumnLayout {
                                id: pipeCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space4
                                spacing: 0

                                Eyebrow {
                                    text: I18n.tr("PIPELINE")
                                    Layout.bottomMargin: Tokens.space3
                                }

                                Repeater {
                                    model: [
                                        { k: 0, t: I18n.tr("Measured"), i: "math",
                                          s: I18n.tr("instant · free · no AI"),
                                          st: "done" },
                                        { k: 1, t: I18n.tr("Written brief"), i: "auto_awesome",
                                          s: Insights.busy ? I18n.tr("reading with {p} …").replace("{p}", Insights.providerLabel)
                                             : page.briefOk ? Insights.providerLabel
                                             : Insights.hasBrief ? I18n.tr("reply was not structured")
                                             : Insights.hasAiKey ? I18n.tr("one AI call") : I18n.tr("needs an AI key"),
                                          st: Insights.busy ? "busy" : page.briefOk ? "done"
                                              : Insights.hasBrief ? "warn" : "todo" },
                                        { k: 2, t: I18n.tr("Evidence audited"), i: "receipt",
                                          s: page.claimCount > 0
                                             ? I18n.tr("{n} claims").replace("{n}", page.claimCount)
                                             : I18n.tr("after the brief"),
                                          st: page.claimCount > 0 ? "done" : "todo" }
                                    ]
                                    Item {
                                        id: step
                                        Layout.fillWidth: true
                                        implicitHeight: 58
                                        readonly property bool on: page.lens === modelData.k
                                        readonly property color tint: modelData.st === "done" ? Theme.secondary_container
                                                                    : modelData.st === "busy" ? Theme.primary
                                                                    : modelData.st === "warn" ? Theme.warn
                                                                    : Theme.outline

                                        // connector to the next node
                                        Rectangle {
                                            visible: index < 2
                                            anchors.left: parent.left
                                            anchors.leftMargin: 15
                                            y: 40
                                            width: 2
                                            height: step.height - 36
                                            radius: 1
                                            color: modelData.st === "done"
                                                   ? U.withAlpha(Theme.secondary_container, 0.55)
                                                   : U.withAlpha(Theme.outline, 0.25)
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.space1
                                            radius: Tokens.radiusMd
                                            color: step.on ? U.withAlpha(Theme.primary, 0.10)
                                                 : stepHover.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        }

                                        HoverHandler { id: stepHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: page.goLens(modelData.k) }

                                        RowLayout {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: 6
                                            spacing: Tokens.space3

                                            Rectangle {
                                                implicitWidth: 32; implicitHeight: 32
                                                radius: 16
                                                color: modelData.st === "todo" ? Theme.panel_bg
                                                       : U.withAlpha(step.tint, 0.16)
                                                border.width: 1
                                                border.color: U.withAlpha(step.tint, modelData.st === "todo" ? 0.45 : 0.55)
                                                C.SpinnerGlyph {
                                                    anchors.centerIn: parent
                                                    visible: modelData.st === "busy"
                                                    name: "autorenew"
                                                    size: 15
                                                    spinning: visible
                                                    glyphColor: Theme.primary
                                                }
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    visible: modelData.st !== "busy"
                                                    name: modelData.st === "done" ? "check" : modelData.st === "warn" ? "warning" : modelData.i
                                                    size: 15
                                                    glyphColor: step.tint
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: modelData.t
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontBody
                                                    color: step.on ? Theme.primary : Theme.text_strong
                                                    elide: Text.ElideRight
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: modelData.s
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.on_surface_var
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            C.IconGlyph {
                                                name: I18n.rtl ? "chevron_left" : "chevron_right"
                                                size: 16
                                                glyphColor: step.on ? Theme.primary : Theme.outline
                                                opacity: step.on || stepHover.hovered ? 1 : 0.4
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══ status line ═══
                Rectangle {
                    id: statusBox
                    Layout.fillWidth: true
                    visible: Insights.status !== ""
                    implicitHeight: statusRow.implicitHeight + Tokens.space3 * 2
                    radius: Tokens.radiusMd
                    readonly property color tint: Insights.statusKind === "error" ? Theme.error
                                                : Insights.statusKind === "warn" ? Theme.warn
                                                : Insights.statusKind === "success" ? Theme.secondary_container
                                                : Theme.on_surface_var
                    color: U.withAlpha(tint, 0.08)
                    border.width: 1
                    border.color: U.withAlpha(tint, 0.25)
                    RowLayout {
                        id: statusRow
                        anchors.fill: parent
                        anchors.margins: Tokens.space3
                        spacing: Tokens.space2
                        C.IconGlyph {
                            name: Insights.statusKind === "error" ? "error"
                                : Insights.statusKind === "warn" ? "warning"
                                : Insights.statusKind === "success" ? "check_circle" : "info"
                            size: 15
                            glyphColor: statusBox.tint
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: Insights.status
                            wrapMode: Text.WordWrap
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface
                        }
                    }
                }

                // ═══ previously analyzed ═══
                ColumnLayout {
                    id: histBlock
                    Layout.fillWidth: true
                    visible: Insights.hasHistory
                    spacing: Tokens.space2
                    property bool showAll: false
                    readonly property int cap: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.IconGlyph { name: "history"; size: 14; glyphColor: Theme.on_surface_var }
                        Eyebrow { text: I18n.tr("PREVIOUSLY ANALYZED") }
                        C.AppText {
                            text: String((Insights.history || []).length)
                            mono: true
                            font.pixelSize: Tokens.fontMicro
                            color: Theme.outline
                        }
                        Item { Layout.fillWidth: true }
                        C.PrimaryButton {
                            visible: (Insights.history || []).length > histBlock.cap
                            variant: "ghost"
                            implicitHeight: 30
                            iconName: histBlock.showAll ? "expand_less" : "expand_more"
                            text: histBlock.showAll ? I18n.tr("Show less") : I18n.tr("Show all")
                            onClicked: histBlock.showAll = !histBlock.showAll
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Repeater {
                            model: histBlock.showAll ? Insights.history
                                                     : (Insights.history || []).slice(0, histBlock.cap)
                            Rectangle {
                                id: histChip
                                height: 48
                                width: Math.min(300, histCol.implicitWidth + Tokens.space4 * 2 + 26)
                                radius: Tokens.radiusMd
                                readonly property bool hot: histHover.hovered
                                color: modelData.isOpen ? U.withAlpha(Theme.primary, 0.12)
                                     : hot ? U.hoverTint(Theme.panel_bg, Theme.isDark, 0.05)
                                     : Theme.panel_bg
                                border.width: 1
                                border.color: modelData.isOpen ? U.withAlpha(Theme.primary, 0.45)
                                            : hot ? Theme.border_med : Theme.border
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                                HoverHandler { id: histHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Insights.openSaved(modelData.key) }

                                ColumnLayout {
                                    id: histCol
                                    anchors.left: parent.left
                                    anchors.right: delBtn.left
                                    anchors.leftMargin: Tokens.space4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    RowLayout {
                                        spacing: 6
                                        Layout.maximumWidth: 230
                                        Rectangle {
                                            visible: modelData.hasBrief
                                            implicitWidth: 6; implicitHeight: 6; radius: 3
                                            color: Theme.secondary_container
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            Layout.maximumWidth: 220
                                            text: modelData.query
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption + 1
                                            color: modelData.isOpen ? Theme.primary : Theme.text_strong
                                            elide: Text.ElideRight
                                        }
                                    }
                                    C.AppText {
                                        text: I18n.tr("{n} videos").replace("{n}", modelData.videos) + " · " + modelData.when
                                        mono: true
                                        font.pixelSize: Tokens.fontMicro
                                        color: Theme.on_surface_var
                                    }
                                }
                                C.IconButton {
                                    id: delBtn
                                    anchors.right: parent.right
                                    anchors.rightMargin: Tokens.space1
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "close"
                                    glyphSize: 12
                                    implicitWidth: 24; implicitHeight: 24
                                    opacity: histChip.hot ? 1 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                    tip: I18n.tr("Delete this saved report")
                                    onClicked: Insights.deleteSaved(modelData.key)
                                }
                            }
                        }
                    }
                }

                // ═══ LENS BAR ══════════════════════════════════════════
                Item {
                    id: lensBar
                    Layout.fillWidth: true
                    visible: Insights.hasSnapshot
                    implicitHeight: 52

                    Rectangle {
                        id: lensTrack
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(parent.width, lensRow.implicitWidth + 10)
                        height: 50
                        radius: Tokens.radiusPill
                        color: Theme.input_bg
                        border.width: 1
                        border.color: Theme.border

                        // the sliding pill
                        Rectangle {
                            id: lensPill
                            readonly property Item target: lensRep.count > page.lens ? lensRep.liveItemAt(page.lens) : null
                            x: target ? lensRow.x + target.x : 5
                            y: 5
                            width: target ? target.width : 0
                            height: parent.height - 10
                            radius: Tokens.radiusPill
                            color: Theme.primary
                            Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                        }

                        Row {
                            id: lensRow
                            x: 5
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Repeater {
                                id: lensRep
                                // itemAt() is not a notifying lookup: a binding that ran before the
                                // delegates existed got null and kept it (thumb missing on first show,
                                // the active label invisible in light theme). `built` re-runs it.
                                property int built: 0
                                onItemAdded: built++
                                onItemRemoved: built++
                                function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                model: [
                                    { k: 0, l: I18n.tr("Measured"),  i: "bar_chart" },
                                    { k: 1, l: I18n.tr("AI brief"),  i: "auto_awesome" },
                                    { k: 2, l: I18n.tr("Evidence"),  i: "receipt" },
                                    { k: 3, l: I18n.tr("Limits"),    i: "lock" }
                                ]
                                AbstractButton {
                                    id: lensBtn
                                    height: 40
                                    implicitWidth: lensBtnRow.implicitWidth + Tokens.space5 * 2
                                    readonly property bool on: page.lens === modelData.k
                                    onClicked: page.goLens(modelData.k)
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Tokens.radiusPill
                                        color: !lensBtn.on && lensBtn.hovered ? Theme.hover_bg : "transparent"
                                    }
                                    contentItem: Item {
                                        Row {
                                            id: lensBtnRow
                                            anchors.centerIn: parent
                                            spacing: Tokens.space2
                                            C.IconGlyph {
                                                name: modelData.i
                                                size: 15
                                                fill: lensBtn.on
                                                glyphColor: lensBtn.on ? Theme.on_primary : Theme.on_surface_var
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: modelData.l
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontBody
                                                color: lensBtn.on ? Theme.on_primary : Theme.on_surface
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            // badges: brief state / claim count
                                            Rectangle {
                                                visible: modelData.k === 1 && (Insights.busy || page.briefOk)
                                                width: 7; height: 7; radius: 3.5
                                                color: lensBtn.on ? Theme.on_primary
                                                     : Insights.busy ? Theme.primary : Theme.secondary_container
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Rectangle {
                                                visible: modelData.k === 2 && page.claimCount > 0
                                                width: Math.max(20, cntLbl.implicitWidth + 10)
                                                height: 20
                                                radius: 10
                                                color: lensBtn.on ? U.withAlpha(Theme.on_primary, 0.22)
                                                                  : U.withAlpha(Theme.primary, 0.16)
                                                anchors.verticalCenter: parent.verticalCenter
                                                C.AppText {
                                                    id: cntLbl
                                                    anchors.centerIn: parent
                                                    text: String(page.claimCount)
                                                    mono: true
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontMicro
                                                    color: lensBtn.on ? Theme.on_primary : Theme.primary
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    C.AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: content.width > lensTrack.width + 220
                        text: I18n.tr("Ctrl + 1 … 4 to switch")
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.outline
                    }
                }

                // ═══ LENS BODY ═════════════════════════════════════════
                ColumnLayout {
                    id: lensBody
                    Layout.fillWidth: true
                    visible: Insights.hasSnapshot
                    spacing: Tokens.space5
                    transform: Translate { id: lensShift; y: 0 }

                    // ───────────────────────── 0 · MEASURED ───────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: page.lens === 0
                        spacing: Tokens.space5

                        // headline numbers
                        GridLayout {
                            Layout.fillWidth: true
                            columns: content.width < 760 ? 2 : 4
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space4
                            Repeater {
                                model: Insights.tiles
                                KpiTile {
                                    caption: modelData.caption
                                    icon: modelData.icon
                                    value: modelData.value
                                    sub: modelData.sub
                                    meter: modelData.meter
                                }
                            }
                        }

                        // ═══ the shape of the set — v3.39.8 redesign ═══════
                        // Every split now names its own numbers. The old donut
                        // painted five shades of one accent, so "which green is
                        // 29%?" had no answer; these use separate hues (U.catHue /
                        // U.ageHue), keep empty buckets on the scale, and light
                        // the same bucket in the bar and in its row on hover.
                        GridLayout {
                            Layout.fillWidth: true
                            columns: content.width < 900 ? 1 : 2
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space4

                            // ── length: one spectrum bar + a ruled scale ──
                            C.GlassPanel {
                                id: durPanel
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                radius: Tokens.radiusXl
                                implicitHeight: durCol.implicitHeight + Tokens.space5 * 2
                                property int hot: -1
                                readonly property var rows: Insights.durationSpectrum || []
                                readonly property var lead: {
                                    for (var i = 0; i < rows.length; i++)
                                        if (rows[i].top) return rows[i]
                                    return null
                                }
                                function tint(i) { return U.catHue(i, Theme.isDark) }
                                readonly property var barItems: {
                                    var out = []
                                    for (var i = 0; i < rows.length; i++)
                                        out.push({ frac: rows[i].frac, color: durPanel.tint(i) })
                                    return out
                                }
                                function setHot(i, on) { hot = on ? i : (hot === i ? -1 : hot) }
                                property real grow: 0
                                Component.onCompleted: durGrow.start()
                                NumberAnimation { id: durGrow; target: durPanel; property: "grow"; from: 0; to: 1; duration: 820; easing.type: Easing.OutCubic }
                                Connections { target: Insights; function onSnapshotChanged() { durGrow.restart() } }

                                ColumnLayout {
                                    id: durCol
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space5
                                    spacing: Tokens.space4

                                    SectionHead {
                                        title: I18n.tr("How long they are")
                                        hint: I18n.tr("length of each video")
                                        icon: "hourglass_empty"
                                        StatBlock {
                                            value: Insights.medianDurationText
                                            caption: I18n.tr("median length")
                                        }
                                    }

                                    // the headline: the length this set is made of
                                    LeadLine {
                                        Layout.fillWidth: true
                                        visible: Insights.hasDurationMix && durPanel.lead !== null
                                        tint: durPanel.lead ? durPanel.tint(durPanel.lead.index) : Theme.primary
                                        big: durPanel.lead ? durPanel.lead.pctText : ""
                                        text: durPanel.lead ? durPanel.lead.label + "  ·  " + I18n.tr("most common length") : ""
                                    }

                                    MixBar {
                                        Layout.fillWidth: true
                                        visible: Insights.hasDurationMix
                                        items: durPanel.barItems
                                        hot: durPanel.hot
                                        grow: durPanel.grow
                                        onHover: (i, on) => durPanel.setHot(i, on)
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: Insights.hasDurationMix
                                        spacing: 2
                                        Repeater {
                                            model: durPanel.rows
                                            MixRow {
                                                required property var modelData
                                                required property int index
                                                label: modelData.label
                                                count: modelData.count
                                                frac: modelData.frac
                                                pctText: modelData.pctText
                                                isTop: modelData.top
                                                tint: durPanel.tint(index)
                                                lit: durPanel.hot === index
                                                dim: durPanel.hot >= 0 && durPanel.hot !== index
                                                grow: durPanel.grow
                                                onHover: (on) => durPanel.setHot(index, on)
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }

                                    C.AppText {
                                        Layout.fillWidth: true
                                        visible: Insights.hasDurationMix
                                        text: I18n.tr("{n} of {t} videos reported a length")
                                              .replace("{n}", Insights.durationTotalText)
                                              .replace("{t}", Insights.totalVideos)
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                    }
                                    C.AppText {
                                        visible: !Insights.hasDurationMix
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: I18n.tr("No row in this set reported a duration.")
                                        color: Theme.outline
                                        font.pixelSize: Tokens.fontCaption
                                    }
                                }
                            }

                            // ── freshness: an age timeline, newest first ──
                            C.GlassPanel {
                                id: freshPanel
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                radius: Tokens.radiusXl
                                implicitHeight: freshCol.implicitHeight + Tokens.space5 * 2
                                property int hot: -1
                                readonly property var rows: Insights.recencyTimeline || []
                                readonly property real maxFrac: {
                                    var m = 0.0001
                                    for (var i = 0; i < rows.length; i++) m = Math.max(m, rows[i].frac || 0)
                                    return m
                                }
                                // share published in the last 30 days (buckets 0 + 1)
                                readonly property real recentFrac: rows.length > 1 ? (rows[0].frac + rows[1].frac) : 0
                                function tint(i) { return U.ageHue(i, Theme.isDark) }
                                function setHot(i, on) { hot = on ? i : (hot === i ? -1 : hot) }
                                property real grow: 0
                                Component.onCompleted: growAnim.start()
                                NumberAnimation { id: growAnim; target: freshPanel; property: "grow"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
                                Connections { target: Insights; function onSnapshotChanged() { growAnim.restart() } }

                                ColumnLayout {
                                    id: freshCol
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space5
                                    spacing: Tokens.space4

                                    SectionHead {
                                        title: I18n.tr("How fresh they are")
                                        hint: I18n.tr("by publish date")
                                        icon: "history"
                                        StatBlock {
                                            visible: Insights.datedRows > 0
                                            value: Math.round(freshPanel.recentFrac * 100) + "%"
                                            caption: I18n.tr("from the last 30 days")
                                        }
                                    }

                                    LeadLine {
                                        Layout.fillWidth: true
                                        visible: Insights.datedRows > 0
                                        tint: freshPanel.tint(0)
                                        big: freshPanel.rows.length > 0 ? String(freshPanel.rows[0].count) : "0"
                                        text: I18n.tr("published this week")
                                    }

                                    // the timeline: four columns, newest → oldest
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumHeight: 196
                                        visible: Insights.datedRows > 0
                                        spacing: Tokens.space3
                                        Repeater {
                                            model: freshPanel.rows
                                            Item {
                                                id: fcol
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                readonly property bool lit: freshPanel.hot === index
                                                readonly property bool dim: freshPanel.hot >= 0 && !lit
                                                readonly property color tint: freshPanel.tint(index)
                                                readonly property bool empty: modelData.count === 0
                                                opacity: dim ? 0.5 : 1
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                                HoverHandler { onHoveredChanged: freshPanel.setHot(fcol.index, hovered) }

                                                // label + pct under the column
                                                Column {
                                                    id: fFoot
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    spacing: 2
                                                    C.AppText {
                                                        width: parent.width
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: fcol.modelData.label
                                                        weight: fcol.lit ? Tokens.weightBold : Tokens.weightMedium
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: fcol.lit ? Theme.text_strong : Theme.on_surface_var
                                                        elide: Text.ElideRight
                                                    }
                                                    C.AppText {
                                                        width: parent.width
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: fcol.modelData.pctText
                                                        mono: true
                                                        font.pixelSize: Tokens.fontMicro
                                                        color: fcol.lit ? fcol.tint : Theme.outline
                                                        LayoutMirroring.enabled: false
                                                    }
                                                }

                                                // the column itself
                                                Item {
                                                    id: fArea
                                                    anchors.top: parent.top
                                                    anchors.bottom: fFoot.top
                                                    anchors.bottomMargin: Tokens.space3
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: Math.min(72, parent.width)
                                                    readonly property real usable: Math.max(0, height - 28)

                                                    Rectangle {          // track
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: fArea.usable
                                                        radius: Tokens.radiusMd
                                                        color: U.withAlpha(fcol.empty ? Theme.outline : fcol.tint, fcol.lit ? 0.14 : 0.07)
                                                        border.width: 1
                                                        border.color: U.withAlpha(fcol.empty ? Theme.outline : fcol.tint, fcol.lit ? 0.35 : 0.12)
                                                    }
                                                    Rectangle {          // fill
                                                        id: fFill
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        visible: !fcol.empty
                                                        height: Math.max(8, fArea.usable * (fcol.modelData.frac / freshPanel.maxFrac) * freshPanel.grow)
                                                        radius: Tokens.radiusMd
                                                        gradient: Gradient {
                                                            GradientStop { position: 0.0; color: fcol.tint }
                                                            GradientStop { position: 1.0; color: U.withAlpha(fcol.tint, 0.55) }
                                                        }
                                                    }
                                                    C.AppText {          // count, riding the fill
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.bottom: fcol.empty ? parent.bottom : fFill.top
                                                        anchors.bottomMargin: fcol.empty ? Tokens.space2 : 6
                                                        text: String(fcol.modelData.count)
                                                        mono: true
                                                        weight: Tokens.weightExtraBold
                                                        font.pixelSize: Tokens.fontLabel
                                                        color: fcol.empty ? Theme.outline : (fcol.lit ? fcol.tint : Theme.text_strong)
                                                        LayoutMirroring.enabled: false
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    C.AppText {
                                        Layout.fillWidth: true
                                        visible: Insights.datedRows > 0
                                        text: I18n.tr("{n} of {t} videos had a publish date")
                                              .replace("{n}", Insights.datedRows)
                                              .replace("{t}", Insights.totalVideos)
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                    }
                                    C.AppText {
                                        visible: Insights.datedRows === 0
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: I18n.tr("No row in this set reported a publish date.")
                                        color: Theme.outline
                                        font.pixelSize: Tokens.fontCaption
                                    }
                                }
                            }
                        }

                        // ── who holds the niche: verdict + ranked share ──
                        C.GlassPanel {
                            id: holdPanel
                            Layout.fillWidth: true
                            visible: (Insights.topChannels || []).length > 0
                            radius: Tokens.radiusXl
                            implicitHeight: holdCol.implicitHeight + Tokens.space5 * 2
                            property int hot: -1
                            readonly property var chans: Insights.topChannels || []
                            readonly property real shareSum: {
                                var s = 0
                                for (var i = 0; i < chans.length; i++) s += (chans[i].share || 0)
                                return Math.min(1, s)
                            }
                            readonly property real topShare: chans.length > 0 ? (chans[0].share || 0) : 0
                            readonly property real top3Share: {
                                var s = 0
                                for (var i = 0; i < Math.min(3, chans.length); i++) s += (chans[i].share || 0)
                                return s
                            }
                            // 0 one channel dominates · 1 a few lead · 2 open field
                            readonly property int verdict: topShare >= 0.5 ? 0 : (top3Share >= 0.6 ? 1 : 2)
                            readonly property color verdictTint: verdict === 0 ? Theme.warn
                                                               : verdict === 1 ? U.catHue(1, Theme.isDark)
                                                               : U.catHue(0, Theme.isDark)
                            readonly property real others: Math.max(0, 1 - shareSum)
                            function tint(i) { return U.catHue(i + 2, Theme.isDark) }
                            readonly property var barItems: {
                                var out = []
                                for (var i = 0; i < chans.length; i++)
                                    out.push({ frac: chans[i].share || 0, color: holdPanel.tint(i) })
                                if (others > 0.005)
                                    out.push({ frac: others, color: U.catHue(-1, Theme.isDark) })
                                return out
                            }
                            function setHot(i, on) { hot = on ? i : (hot === i ? -1 : hot) }
                            property real grow: 0
                            Component.onCompleted: holdGrow.start()
                            NumberAnimation { id: holdGrow; target: holdPanel; property: "grow"; from: 0; to: 1; duration: 820; easing.type: Easing.OutCubic }
                            Connections { target: Insights; function onSnapshotChanged() { holdGrow.restart() } }

                            ColumnLayout {
                                id: holdCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4

                                SectionHead {
                                    title: I18n.tr("Who holds this niche")
                                    hint: I18n.tr("share of the views in this set")
                                    icon: "user"
                                    Tag {
                                        label: holdPanel.verdict === 0 ? I18n.tr("One channel dominates")
                                             : holdPanel.verdict === 1 ? I18n.tr("A few channels lead")
                                             : I18n.tr("Open field")
                                        tint: holdPanel.verdictTint
                                        strong: true
                                        implicitHeight: 28
                                    }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: content.width < 900 ? 1 : 2
                                    columnSpacing: Tokens.space6
                                    rowSpacing: Tokens.space4

                                    // left: the concentration read-out
                                    ColumnLayout {
                                        Layout.preferredWidth: content.width < 900 ? -1 : 300
                                        Layout.maximumWidth: content.width < 900 ? 100000 : 300
                                        Layout.fillWidth: content.width < 900
                                        Layout.alignment: Qt.AlignTop
                                        spacing: Tokens.space2

                                        Row {
                                            spacing: Tokens.space2
                                            C.AppText {
                                                text: Math.round(holdPanel.topShare * 100) + "%"
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: 44
                                                font.letterSpacing: -1.5
                                                color: holdPanel.verdictTint
                                                LayoutMirroring.enabled: false
                                            }
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: I18n.tr("of the views go to the #1 channel")
                                            weight: Tokens.weightDemiBold
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.text_strong
                                            wrapMode: Text.WordWrap
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: holdPanel.verdict === 0 ? I18n.tr("Hard to break in: one channel takes most of the attention.")
                                                : holdPanel.verdict === 1 ? I18n.tr("A handful of channels share most of the views.")
                                                : I18n.tr("Views are spread out, there is room for a new channel.")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                            wrapMode: Text.WordWrap
                                        }

                                        // mini read-outs
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: Tokens.space2
                                            spacing: Tokens.space2
                                            Repeater {
                                                model: [
                                                    { v: String(Insights.channelCount), l: I18n.tr("channels") },
                                                    { v: Math.round(holdPanel.top3Share * 100) + "%", l: I18n.tr("top 3") },
                                                    { v: Math.round(holdPanel.others * 100) + "%", l: I18n.tr("everyone else") }
                                                ]
                                                Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    implicitHeight: 58
                                                    radius: Tokens.radiusMd
                                                    color: U.withAlpha(Theme.outline, 0.07)
                                                    border.width: 1
                                                    border.color: U.withAlpha(Theme.outline, 0.12)
                                                    Column {
                                                        anchors.centerIn: parent
                                                        spacing: 1
                                                        C.AppText {
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            text: modelData.v
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: Tokens.fontLabel
                                                            color: Theme.text_strong
                                                            LayoutMirroring.enabled: false
                                                        }
                                                        C.AppText {
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            text: modelData.l
                                                            font.pixelSize: Tokens.fontMicro
                                                            color: Theme.on_surface_var
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // right: the share bar + the ranked channels
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignTop
                                        spacing: Tokens.space3

                                        MixBar {
                                            Layout.fillWidth: true
                                            implicitHeight: 16
                                            items: holdPanel.barItems
                                            hot: holdPanel.hot
                                            grow: holdPanel.grow
                                            onHover: (i, on) => holdPanel.setHot(i, on)
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Repeater {
                                                model: holdPanel.chans
                                                Rectangle {
                                                    id: chRow
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    implicitHeight: 52
                                                    radius: Tokens.radiusMd
                                                    readonly property bool lit: holdPanel.hot === index
                                                    readonly property color tint: holdPanel.tint(index)
                                                    color: U.withAlpha(tint, lit ? 0.10 : 0)
                                                    opacity: holdPanel.hot >= 0 && !lit ? 0.55 : 1
                                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                                    HoverHandler { onHoveredChanged: holdPanel.setHot(chRow.index, hovered) }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: Tokens.space2
                                                        anchors.rightMargin: Tokens.space3
                                                        spacing: Tokens.space3

                                                        // monogram tile in the channel's hue
                                                        Rectangle {
                                                            implicitWidth: 34; implicitHeight: 34
                                                            radius: Tokens.radiusSm
                                                            color: U.withAlpha(chRow.tint, Theme.isDark ? 0.18 : 0.14)
                                                            border.width: 1
                                                            border.color: U.withAlpha(chRow.tint, 0.40)
                                                            C.AppText {
                                                                anchors.centerIn: parent
                                                                text: (chRow.modelData.title || "?").charAt(0).toUpperCase()
                                                                weight: Tokens.weightExtraBold
                                                                font.pixelSize: Tokens.fontLabel
                                                                color: chRow.tint
                                                            }
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 5
                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                spacing: Tokens.space2
                                                                C.AppText {
                                                                    text: chRow.index < 9 ? "0" + (chRow.index + 1) : String(chRow.index + 1)
                                                                    mono: true
                                                                    weight: Tokens.weightBold
                                                                    font.pixelSize: Tokens.fontMicro
                                                                    color: chRow.lit ? chRow.tint : Theme.outline
                                                                    LayoutMirroring.enabled: false
                                                                }
                                                                C.AppText {
                                                                    Layout.fillWidth: true
                                                                    text: chRow.modelData.title
                                                                    weight: Tokens.weightDemiBold
                                                                    font.pixelSize: Tokens.fontBody
                                                                    color: Theme.text_strong
                                                                    elide: Text.ElideRight
                                                                }
                                                                C.AppText {
                                                                    text: I18n.tr("{n} videos").replace("{n}", chRow.modelData.videos) + " · " + chRow.modelData.views
                                                                    mono: true
                                                                    font.pixelSize: Tokens.fontMicro
                                                                    color: Theme.on_surface_var
                                                                }
                                                            }
                                                            Item {
                                                                Layout.fillWidth: true
                                                                implicitHeight: 6
                                                                Rectangle {
                                                                    anchors.fill: parent
                                                                    radius: 3
                                                                    color: U.withAlpha(Theme.outline, 0.12)
                                                                }
                                                                Rectangle {
                                                                    anchors.left: parent.left
                                                                    anchors.top: parent.top
                                                                    anchors.bottom: parent.bottom
                                                                    width: Math.max(4, parent.width * (chRow.modelData.share || 0) * holdPanel.grow)
                                                                    radius: 3
                                                                    color: chRow.tint
                                                                }
                                                            }
                                                        }
                                                        C.AppText {
                                                            text: chRow.modelData.sharePct
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: Tokens.fontLabel
                                                            color: chRow.lit ? chRow.tint : Theme.text_strong
                                                            Layout.minimumWidth: 48
                                                            horizontalAlignment: Text.AlignRight
                                                            LayoutMirroring.enabled: false
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // who is winning — one panel, two meanings of "winning"
                        C.GlassPanel {
                            id: leadPanel
                            Layout.fillWidth: true
                            radius: Tokens.radiusXl
                            implicitHeight: leadCol.implicitHeight + Tokens.space5 * 2
                            property int mode: 0     // 0 velocity · 1 breakout
                            readonly property var rows: mode === 0 ? (Insights.velocityLeaders || [])
                                                                   : (Insights.breakoutLeaders || [])
                            readonly property var first: rows.length > 0 ? rows[0] : ({})

                            ColumnLayout {
                                id: leadCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4

                                SectionHead {
                                    title: leadPanel.mode === 0 ? I18n.tr("Moving fastest") : I18n.tr("Reaching past their audience")
                                    hint: leadPanel.mode === 0 ? I18n.tr("views per hour since publishing") : I18n.tr("views ÷ subscribers")
                                    icon: leadPanel.mode === 0 ? "speed" : "trending_up"

                                    // two-way switch
                                    Rectangle {
                                        implicitWidth: modeRow.implicitWidth + 8
                                        implicitHeight: 36
                                        radius: Tokens.radiusPill
                                        color: Theme.input_bg
                                        border.width: 1
                                        border.color: Theme.border
                                        Rectangle {
                                            readonly property Item t: modeRep.count > leadPanel.mode ? modeRep.liveItemAt(leadPanel.mode) : null
                                            x: t ? modeRow.x + t.x : 4
                                            y: 4
                                            width: t ? t.width : 0
                                            height: parent.height - 8
                                            radius: Tokens.radiusPill
                                            color: U.withAlpha(Theme.primary, 0.18)
                                            border.width: 1
                                            border.color: U.withAlpha(Theme.primary, 0.45)
                                            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                        }
                                        Row {
                                            id: modeRow
                                            x: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            Repeater {
                                                id: modeRep
                                                // itemAt() is not a notifying lookup: a binding that ran before the
                                                // delegates existed got null and kept it (thumb missing on first show,
                                                // the active label invisible in light theme). `built` re-runs it.
                                                property int built: 0
                                                onItemAdded: built++
                                                onItemRemoved: built++
                                                function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                                                model: [
                                                    { l: I18n.tr("Fastest"), i: "speed" },
                                                    { l: I18n.tr("Breakout"), i: "trending_up" }
                                                ]
                                                AbstractButton {
                                                    id: modeBtn
                                                    height: 28
                                                    implicitWidth: modeLblRow.implicitWidth + Tokens.space4 * 2
                                                    readonly property bool on: leadPanel.mode === index
                                                    onClicked: leadPanel.mode = index
                                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                    background: Item {}
                                                    contentItem: Item {
                                                        Row {
                                                            id: modeLblRow
                                                            anchors.centerIn: parent
                                                            spacing: 6
                                                            C.IconGlyph {
                                                                name: modelData.i; size: 13
                                                                glyphColor: modeBtn.on ? Theme.primary : Theme.on_surface_var
                                                                anchors.verticalCenter: parent.verticalCenter
                                                            }
                                                            C.AppText {
                                                                text: modelData.l
                                                                weight: Tokens.weightBold
                                                                font.pixelSize: Tokens.fontCaption
                                                                color: modeBtn.on ? Theme.primary : Theme.on_surface_var
                                                                anchors.verticalCenter: parent.verticalCenter
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                C.AppText {
                                    visible: leadPanel.rows.length === 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space4
                                    Layout.bottomMargin: Tokens.space4
                                    horizontalAlignment: Text.AlignHCenter
                                    text: leadPanel.mode === 0 ? I18n.tr("No row had both views and a publish date.")
                                                               : I18n.tr("No channel in this set showed a public subscriber count.")
                                    color: Theme.outline
                                    font.pixelSize: Tokens.fontCaption
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    visible: leadPanel.rows.length > 0
                                    columns: content.width < 900 ? 1 : 2
                                    columnSpacing: Tokens.space5
                                    rowSpacing: Tokens.space3

                                    // the #1, set big
                                    Rectangle {
                                        id: champ
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        implicitHeight: champCol.implicitHeight
                                        color: "transparent"
                                        HoverHandler { id: champHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: if (leadPanel.first.videoUrl) Qt.openUrlExternally(leadPanel.first.videoUrl) }

                                        ColumnLayout {
                                            id: champCol
                                            width: parent.width
                                            spacing: Tokens.space3
                                            Thumb {
                                                Layout.fillWidth: true
                                                implicitHeight: Math.round(width * 9 / 16)
                                                radius: Tokens.radiusLg
                                                thumbId: leadPanel.first.thumbId || ""
                                                srcW: 640
                                                scale: champHover.hovered ? 1.01 : 1
                                                Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: parent.radius
                                                    gradient: Gradient {
                                                        GradientStop { position: 0.45; color: "transparent" }
                                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.margins: Tokens.space3
                                                    implicitWidth: rankLbl.implicitWidth + Tokens.space4
                                                    implicitHeight: 28
                                                    width: implicitWidth; height: implicitHeight
                                                    radius: Tokens.radiusPill
                                                    color: Theme.primary
                                                    C.AppText {
                                                        id: rankLbl
                                                        anchors.centerIn: parent
                                                        text: "#1"
                                                        mono: true
                                                        weight: Tokens.weightExtraBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_primary
                                                    }
                                                }
                                                C.AppText {
                                                    anchors.left: parent.left
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: Tokens.space4
                                                    text: leadPanel.first.value || ""
                                                    mono: true
                                                    weight: Tokens.weightExtraBold
                                                    font.pixelSize: 30
                                                    font.letterSpacing: -0.8
                                                    color: "white"
                                                    LayoutMirroring.enabled: false
                                                }
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 56; height: 56; radius: 28
                                                    color: Qt.rgba(0, 0, 0, 0.45)
                                                    opacity: champHover.hovered ? 1 : 0
                                                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                                    C.IconGlyph {
                                                        anchors.centerIn: parent
                                                        name: "play_arrow"; fill: true; size: 26
                                                        glyphColor: "white"
                                                    }
                                                }
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: leadPanel.first.title || ""
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontSubtitle
                                                color: champHover.hovered ? Theme.primary : Theme.text_strong
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: (leadPanel.first.channelTitle || "") + "  ·  " + (leadPanel.first.views || "")
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    // the rest
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 2
                                        Repeater {
                                            model: leadPanel.rows.slice(1)
                                            LeaderRow {
                                                row: modelData
                                                rank: index + 2
                                            }
                                        }
                                        C.AppText {
                                            visible: leadPanel.rows.length === 1
                                            Layout.fillWidth: true
                                            text: I18n.tr("Only one video qualified for this ranking.")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.outline
                                        }
                                    }
                                }
                            }
                        }

                        // recurring terms — weighted, click to copy
                        C.GlassPanel {
                            id: termPanel
                            Layout.fillWidth: true
                            visible: (Insights.topics || []).length > 0
                            radius: Tokens.radiusXl
                            implicitHeight: termCol.implicitHeight + Tokens.space5 * 2
                            readonly property int maxCount: {
                                var m = 1
                                var t = Insights.topics || []
                                for (var i = 0; i < t.length; i++) m = Math.max(m, t[i].count || 0)
                                return m
                            }
                            property string copied: ""
                            Timer { id: copiedTimer; interval: 1300; onTriggered: termPanel.copied = "" }

                            ColumnLayout {
                                id: termCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4
                                SectionHead {
                                    title: I18n.tr("Terms that keep coming back")
                                    hint: Insights.topicsSource
                                    icon: "search"
                                    C.AppText {
                                        text: I18n.tr("click a term to copy it")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: Insights.topics
                                        Rectangle {
                                            id: term
                                            readonly property real w: (modelData.count || 0) / termPanel.maxCount
                                            readonly property bool hot: termHover.hovered
                                            readonly property bool done: termPanel.copied === modelData.label
                                            height: 30 + Math.round(10 * w)
                                            width: termRow.implicitWidth + Tokens.space4 * 2
                                            radius: Tokens.radiusPill
                                            color: done ? U.withAlpha(Theme.secondary_container, 0.16)
                                                 : hot ? U.withAlpha(Theme.primary, 0.14)
                                                 : U.withAlpha(Theme.primary, 0.03 + 0.09 * w)
                                            border.width: 1
                                            border.color: done ? U.withAlpha(Theme.secondary_container, 0.5)
                                                        : hot ? U.withAlpha(Theme.primary, 0.5)
                                                        : U.withAlpha(Theme.primary, 0.10 + 0.25 * w)
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            HoverHandler { id: termHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    clipHelper.put(modelData.label)
                                                    termPanel.copied = modelData.label
                                                    copiedTimer.restart()
                                                }
                                            }
                                            Row {
                                                id: termRow
                                                anchors.centerIn: parent
                                                spacing: Tokens.space2
                                                C.IconGlyph {
                                                    visible: term.done
                                                    name: "check"; size: 13
                                                    glyphColor: Theme.secondary_container
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: modelData.label
                                                    weight: term.w > 0.6 ? Tokens.weightBold : Tokens.weightMedium
                                                    font.pixelSize: Tokens.fontCaption + Math.round(5 * term.w)
                                                    color: term.done ? Theme.secondary_container
                                                         : term.w > 0.6 ? Theme.text_strong : Theme.on_surface
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: String(modelData.count)
                                                    mono: true
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontMicro
                                                    color: Theme.primary
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    C.IconGlyph { name: "info"; size: 13; glyphColor: Theme.outline }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: I18n.tr("These show what is being SUPPLIED in this niche. They are not search volume and do not prove demand.")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                    }
                                }
                            }
                        }
                    }

                    // ───────────────────────── 1 · BRIEF ─────────────────
                    // v13 "Dossier" (2026 premium pass).
                    //
                    // The v12 lens stacked seven equal-weight panels. The dossier gives it
                    // one lead and a clear descent:
                    //   HERO      the summary set as a statement on an accent rail, with
                    //             the confidence spectrum (Observed / Inferred / Studio)
                    //             under it — the spectrum, its legend and the signal
                    //             board below all share ONE focus (briefLens.pick).
                    //   INTENT    the four framing calls as a spec sheet: one surface,
                    //             columns split by hairlines, not four floating cards.
                    //   SIGNALS   every labelled statement, filtered by a sliding
                    //             segmented control.
                    //   OPENINGS  · QUESTIONS · EXPERIMENTS follow, quieter.
                    // Motion: one arrival (summary rises, spectrum fills) per brief and
                    // a slow breath on the rail + glow, gated on the window being active.
                    ColumnLayout {
                        id: briefLens
                        Layout.fillWidth: true
                        visible: page.lens === 1
                        spacing: Tokens.space5

                        property string pick: ""
                        readonly property bool compact: content.width < 760
                        readonly property var classes: [
                            { key: "observed", label: I18n.tr("Observed"), short: I18n.tr("Observed"),
                              note: I18n.tr("Measured in this result set."), icon: "check_circle" },
                            { key: "inferred", label: I18n.tr("Inferred"), short: I18n.tr("Inferred"),
                              note: I18n.tr("A reading of that data — a hypothesis, not a fact."), icon: "psychology" },
                            { key: "requires_studio", label: I18n.tr("Needs YouTube Studio"), short: I18n.tr("Needs Studio"),
                              note: I18n.tr("Not public data. Only the channel owner's analytics can answer these."), icon: "lock" }
                        ]
                        readonly property int rawTotal: page.observedCount + page.inferredCount + page.studioCount
                        readonly property int total: Math.max(1, rawTotal)
                        readonly property var intentItems: {
                            var it = page.briefOk ? (Insights.brief.intent || {}) : {}
                            var defs = [
                                { l: I18n.tr("VIEWER'S JOB"),   k: "job",     i: "target" },
                                { l: I18n.tr("THE VIEWER"),     k: "viewer",  i: "user" },
                                { l: I18n.tr("LIKELY SURFACE"), k: "surface", i: "route" },
                                { l: I18n.tr("HONEST PROMISE"), k: "promise", i: "verified" }
                            ]
                            var out = []
                            for (var i = 0; i < defs.length; i++) {
                                var v = String(it[defs[i].k] || "").trim()
                                if (v !== "") out.push({ l: defs[i].l, i: defs[i].i, v: v })
                            }
                            return out
                        }
                        function countFor(k) {
                            return k === "observed" ? page.observedCount
                                 : k === "inferred" ? page.inferredCount
                                 : page.studioCount
                        }
                        function toggle(k) { briefLens.pick = (briefLens.pick === k ? "" : k) }
                        function clamp01(x) { return Math.max(0, Math.min(1, x)) }

                        // ── arrival: 0 → 1 once per brief / per visit ──
                        property real reveal: 1
                        readonly property real riseK: clamp01(reveal * 1.7)
                        readonly property real fillK: clamp01((reveal - 0.25) / 0.75)
                        NumberAnimation {
                            id: bfReveal
                            target: briefLens; property: "reveal"
                            from: 0; to: 1
                            duration: 950
                            easing.type: Easing.OutCubic
                        }
                        function replay() { if (page.briefOk) bfReveal.restart() }
                        onVisibleChanged: if (visible) replay()
                        Connections {
                            target: Insights
                            function onAiChanged() {
                                briefLens.pick = ""
                                if (briefLens.visible) briefLens.replay()
                            }
                        }

                        // ── ambient breath (felt, not seen) ──
                        property real breath: 0
                        SequentialAnimation on breath {
                            running: briefLens.visible && page.briefOk && Tokens.appActive
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 1; duration: 3800; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1; to: 0; duration: 3800; easing.type: Easing.InOutSine }
                        }

                        // ═══ PITCH — no brief yet ══════════════════════════════
                        C.GlassPanel {
                            id: pitch
                            Layout.fillWidth: true
                            visible: !Insights.hasBrief && !Insights.busy
                            radius: Tokens.radiusXl
                            elevation: 1.4
                            readonly property int pad: briefLens.compact ? Tokens.space6 : Tokens.space8
                            implicitHeight: bfPitchGrid.implicitHeight + pad * 2

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: pitch.radius - 1
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.04) }
                                    GradientStop { position: 0.6; color: U.withAlpha(Theme.primary, 0.0) }
                                }
                            }
                            C.CornerGlow { radius: pitch.radius; size: 640 }

                            GridLayout {
                                id: bfPitchGrid
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: pitch.pad
                                anchors.rightMargin: pitch.pad
                                columns: content.width < 980 ? 1 : 2
                                columnSpacing: Tokens.space8
                                rowSpacing: Tokens.space6

                                // the ask
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 5
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: Tokens.space4
                                    Badge { label: I18n.tr("AI BRIEF"); icon: "auto_awesome" }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Add the written brief")
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: briefLens.compact ? 28 : 38
                                        font.letterSpacing: I18n.rtl ? 0 : -1.1
                                        lineHeight: 1.08
                                        color: Theme.text_strong
                                        wrapMode: Text.WordWrap
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 560
                                        wrapMode: Text.WordWrap
                                        text: I18n.tr("One AI call: audience questions, openings worth testing and three experiments. Every statement keeps a label.")
                                        font.pixelSize: Tokens.fontLabel + 1
                                        lineHeight: 1.3
                                        color: Theme.on_surface_var
                                    }
                                    RowLayout {
                                        Layout.topMargin: Tokens.space2
                                        spacing: Tokens.space3
                                        C.PrimaryButton {
                                            iconName: "auto_awesome"
                                            text: I18n.tr("Generate brief")
                                            enabled: Insights.hasAiKey
                                            onClicked: Insights.generateBrief(false)
                                        }
                                        C.AppText {
                                            visible: !Insights.hasAiKey
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            text: I18n.tr("No AI provider configured — add a key in Settings first.")
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.warn
                                        }
                                    }
                                }

                                // what every line will carry
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 4
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: Tokens.space2
                                    Eyebrow {
                                        Layout.fillWidth: true
                                        Layout.bottomMargin: Tokens.space1
                                        text: I18n.tr("EVERY LINE CARRIES ONE OF THREE LABELS")
                                        wrapMode: Text.WordWrap
                                    }
                                    Repeater {
                                        model: briefLens.classes
                                        Rectangle {
                                            id: pcRow
                                            Layout.fillWidth: true
                                            readonly property color tint: page.classTint(modelData.key)
                                            implicitHeight: pcRowL.implicitHeight + Tokens.space3 * 2
                                            radius: Tokens.radiusLg
                                            color: U.withAlpha(tint, Theme.isDark ? 0.06 : 0.045)
                                            border.width: 1
                                            border.color: U.withAlpha(tint, 0.22)
                                            RowLayout {
                                                id: pcRowL
                                                anchors.fill: parent
                                                anchors.margins: Tokens.space3
                                                anchors.leftMargin: Tokens.space4
                                                anchors.rightMargin: Tokens.space4
                                                spacing: Tokens.space3
                                                Rectangle {
                                                    Layout.alignment: Qt.AlignTop
                                                    implicitWidth: 30; implicitHeight: 30
                                                    radius: 15
                                                    color: U.withAlpha(pcRow.tint, 0.14)
                                                    C.IconGlyph { anchors.centerIn: parent; name: modelData.icon; size: 15; glyphColor: pcRow.tint }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2
                                                    C.AppText {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        weight: Tokens.weightExtraBold
                                                        font.pixelSize: Tokens.fontBody
                                                        color: pcRow.tint
                                                    }
                                                    C.AppText {
                                                        Layout.fillWidth: true
                                                        text: modelData.note
                                                        wrapMode: Text.WordWrap
                                                        font.pixelSize: Tokens.fontCaption + 1
                                                        color: Theme.on_surface_var
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ BUSY — a real call takes minutes ═════════════════
                        C.GlassPanel {
                            id: bfBusy
                            Layout.fillWidth: true
                            visible: Insights.busy
                            radius: Tokens.radiusXl
                            elevation: 1.4
                            implicitHeight: bfBusyCol.implicitHeight + Tokens.space8 * 2
                            property int secs: 0
                            Timer {
                                interval: 1000
                                repeat: true
                                running: Insights.busy
                                onTriggered: bfBusy.secs = bfBusy.secs + 1
                            }
                            Connections {
                                target: Insights
                                function onBusyChanged() { if (Insights.busy) bfBusy.secs = 0 }
                            }
                            C.CornerGlow { radius: bfBusy.radius; size: 560 }
                            ColumnLayout {
                                id: bfBusyCol
                                anchors.centerIn: parent
                                width: Math.min(600, parent.width - Tokens.space7 * 2)
                                spacing: Tokens.space4
                                C.PulseBars {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 300
                                    Layout.preferredHeight: 76
                                    mode: "busy"
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space2
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("Reading the snapshot with {p} …").replace("{p}", Insights.providerLabel)
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontTitle
                                    font.letterSpacing: I18n.rtl ? 0 : -0.4
                                    color: Theme.text_strong
                                    wrapMode: Text.WordWrap
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("This is one long call — a full brief can take a couple of minutes.")
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.on_surface_var
                                    wrapMode: Text.WordWrap
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: Tokens.space1
                                    implicitWidth: bfElapsed.implicitWidth + Tokens.space4 * 2
                                    implicitHeight: 28
                                    radius: Tokens.radiusPill
                                    color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.08 : 0.06)
                                    border.width: 1
                                    border.color: Theme.border
                                    C.AppText {
                                        id: bfElapsed
                                        anchors.centerIn: parent
                                        text: Math.floor(bfBusy.secs / 60) + ":" + (bfBusy.secs % 60 < 10 ? "0" : "") + (bfBusy.secs % 60)
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        LayoutMirroring.enabled: false
                                    }
                                }
                            }
                        }
                        // ── unreadable reply (v1.1.3) ──
                        // Used to be a Panel with the whole raw JSON poured into
                        // it in monospace: a wall nobody could read. The reader
                        // now salvages cut-off / messy replies itself (see
                        // core/ai/insights.py), so this only shows when there was
                        // no object at all. It says so plainly, offers the one
                        // useful action (try again), and keeps the raw text
                        // folded away for whoever wants to inspect it.
                        C.GlassPanel {
                            id: rawCard
                            Layout.fillWidth: true
                            visible: Insights.hasBrief && Insights.brief.ok === false
                            radius: Tokens.radiusXl
                            implicitHeight: rawCol.implicitHeight + Tokens.space6 * 2
                            property bool showRaw: false
                            C.CornerGlow { radius: rawCard.radius; size: 420; glow: Theme.warn }

                            ColumnLayout {
                                id: rawCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space6
                                spacing: Tokens.space4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space4
                                    C.IconTile {
                                        iconName: "warning"
                                        size: 46
                                        tint: Theme.warn
                                        lit: true
                                        Layout.alignment: Qt.AlignTop
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space1
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: I18n.tr("The AI answered, but not in a shape we can lay out")
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontSubtitle
                                            color: Theme.text_strong
                                            wrapMode: Text.WordWrap
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: I18n.tr("Usually a one-off. Running it again almost always comes back clean.")
                                            font.pixelSize: Tokens.fontBody
                                            color: Theme.on_surface_var
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    C.PrimaryButton {
                                        iconName: "restart_alt"
                                        text: I18n.tr("Try again")
                                        enabled: Insights.hasAiKey && !Insights.busy
                                        onClicked: Insights.generateBrief(true)
                                    }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: rawCard.showRaw ? "expand_less" : "expand_more"
                                        text: rawCard.showRaw ? I18n.tr("Hide raw reply") : I18n.tr("Show raw reply")
                                        onClicked: rawCard.showRaw = !rawCard.showRaw
                                    }
                                    Item { Layout.fillWidth: true }
                                    C.IconButton {
                                        iconName: "content_copy"
                                        glyphSize: 15
                                        implicitWidth: 34; implicitHeight: 34
                                        tip: I18n.tr("Copy raw reply")
                                        onClicked: clipHelper.put(Insights.brief.fallback_text || "")
                                    }
                                }

                                // the raw text, folded by default, in a quiet well
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: rawCard.showRaw
                                    implicitHeight: Math.min(rawTxt.implicitHeight + Tokens.space4 * 2, 360)
                                    radius: Tokens.radiusLg
                                    color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.06 : 0.05)
                                    border.width: 1
                                    border.color: Theme.border
                                    clip: true
                                    Flickable {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space4
                                        contentWidth: width
                                        contentHeight: rawTxt.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height
                                        clip: true
                                        C.AppText {
                                            id: rawTxt
                                            width: parent.width
                                            text: Insights.brief.fallback_text || ""
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                            font.pixelSize: Tokens.fontCaption
                                            lineHeight: 1.35
                                            mono: true
                                            color: Theme.on_surface_var
                                            selectable: true
                                        }
                                    }
                                }
                            }
                        }

                        // reply was cut short and the reader closed it: every
                        // section that arrived is shown, this says what's missing
                        Rectangle {
                            id: partialNote
                            Layout.fillWidth: true
                            visible: page.briefOk && Insights.brief.partial === true
                            implicitHeight: partialRow.implicitHeight + Tokens.space3 * 2
                            radius: Tokens.radiusLg
                            color: U.withAlpha(Theme.warn, Theme.isDark ? 0.08 : 0.06)
                            border.width: 1
                            border.color: U.withAlpha(Theme.warn, 0.30)
                            RowLayout {
                                id: partialRow
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.space4
                                anchors.rightMargin: Tokens.space2
                                anchors.topMargin: Tokens.space3
                                anchors.bottomMargin: Tokens.space3
                                spacing: Tokens.space3
                                C.IconGlyph { name: "info"; fill: true; size: 16; glyphColor: Theme.warn }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: I18n.tr("The AI's reply was cut short. Everything that arrived is below; the last sections may be missing.")
                                    font.pixelSize: Tokens.fontCaption + 1
                                    color: Theme.on_surface
                                    wrapMode: Text.WordWrap
                                }
                                C.PrimaryButton {
                                    variant: "ghost"
                                    iconName: "restart_alt"
                                    text: I18n.tr("Run again")
                                    enabled: Insights.hasAiKey && !Insights.busy
                                    onClicked: Insights.generateBrief(true)
                                }
                            }
                        }


                        // ═══ HERO — the summary as a statement ═══════════════
                        C.GlassPanel {
                            id: bfHero
                            Layout.fillWidth: true
                            visible: page.briefOk
                            radius: Tokens.radiusXl
                            elevation: 1.6
                            readonly property int pad: briefLens.compact ? Tokens.space6 : Tokens.space7
                            implicitHeight: bfHeroCol.implicitHeight + pad * 2

                            // depth: a wash of the accent falling off the top edge
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: bfHero.radius - 1
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.085 : 0.05) }
                                    GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, 0.0) }
                                }
                            }
                            C.CornerGlow {
                                radius: bfHero.radius
                                size: 720
                                opacity: 0.78 + 0.22 * briefLens.breath
                            }

                            ColumnLayout {
                                id: bfHeroCol
                                anchors.fill: parent
                                anchors.margins: bfHero.pad
                                spacing: 0

                                // meta strip
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space3
                                    Badge { label: I18n.tr("THE BRIEF"); icon: "auto_awesome" }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: Insights.providerLabel
                                              + (Insights.fromCache && Insights.generatedAt !== ""
                                                 ? "  ·  " + Insights.generatedAt : "")
                                        mono: true
                                        font.pixelSize: Tokens.fontMicro + 1
                                        color: Theme.outline
                                        elide: Text.ElideRight
                                    }
                                    C.IconButton {
                                        iconName: "content_copy"
                                        glyphSize: 15
                                        implicitWidth: 34; implicitHeight: 34
                                        tip: I18n.tr("Copy")
                                        onClicked: clipHelper.put(Insights.brief.summary || "")
                                    }
                                    C.IconButton {
                                        iconName: "refresh"
                                        glyphSize: 15
                                        implicitWidth: 34; implicitHeight: 34
                                        tip: I18n.tr("Re-analyze")
                                        enabled: Insights.hasAiKey && !Insights.busy
                                        onClicked: Insights.generateBrief(true)
                                    }
                                }

                                // the statement, on a breathing accent rail
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: briefLens.compact ? Tokens.space5 : Tokens.space6
                                    spacing: briefLens.compact ? Tokens.space4 : Tokens.space5
                                    opacity: briefLens.riseK
                                    transform: Translate { y: (1 - briefLens.riseK) * 14 }

                                    Rectangle {
                                        Layout.fillHeight: true
                                        implicitWidth: 3
                                        radius: 1.5
                                        opacity: 0.7 + 0.3 * briefLens.breath
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Theme.primary }
                                            GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.05) }
                                        }
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 1080
                                        text: Insights.brief.summary || ""
                                        wrapMode: Text.WordWrap
                                        weight: Tokens.weightMedium
                                        font.pixelSize: briefLens.compact ? 20 : (content.wide ? 28 : 24)
                                        font.letterSpacing: I18n.rtl ? 0 : -0.45
                                        lineHeight: 1.3
                                        color: Theme.text_strong
                                        selectable: true
                                    }
                                }

                                // confidence spectrum
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: briefLens.compact ? Tokens.space6 : Tokens.space7
                                    visible: briefLens.rawTotal > 0
                                    spacing: Tokens.space3
                                    Eyebrow { text: I18n.tr("HOW SURE THE BRIEF IS") }
                                    Item { Layout.fillWidth: true }
                                    C.AppText {
                                        text: briefLens.pick === "" ? I18n.tr("tap a label to focus it")
                                                                    : I18n.tr("tap it again to show all")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space3
                                    visible: briefLens.rawTotal > 0
                                    implicitHeight: 10
                                    Row {
                                        id: bfSpec
                                        anchors.fill: parent
                                        spacing: 4
                                        readonly property int shown: (page.observedCount > 0 ? 1 : 0)
                                                                     + (page.inferredCount > 0 ? 1 : 0)
                                                                     + (page.studioCount > 0 ? 1 : 0)
                                        readonly property real usable: Math.max(0, width - spacing * Math.max(0, shown - 1))
                                        Repeater {
                                            model: briefLens.classes
                                            Rectangle {
                                                readonly property int n: briefLens.countFor(modelData.key)
                                                visible: n > 0
                                                height: bfSpec.height
                                                width: Math.max(10, bfSpec.usable * n / briefLens.total) * briefLens.fillK
                                                radius: height / 2
                                                color: page.classTint(modelData.key)
                                                opacity: briefLens.pick === "" || briefLens.pick === modelData.key ? 1 : 0.2
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: briefLens.toggle(modelData.key) }
                                            }
                                        }
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space4
                                    visible: briefLens.rawTotal > 0
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: briefLens.classes
                                        Rectangle {
                                            id: lgChip
                                            readonly property color tint: page.classTint(modelData.key)
                                            readonly property bool on: briefLens.pick === modelData.key
                                            width: lgRow.implicitWidth + Tokens.space4 * 2
                                            height: 34
                                            radius: Tokens.radiusPill
                                            color: on ? U.withAlpha(tint, 0.16)
                                                 : lgHover.hovered ? U.withAlpha(tint, 0.08) : U.withAlpha(tint, 0.0)
                                            border.width: 1
                                            border.color: on ? U.withAlpha(tint, 0.55) : Theme.border
                                            opacity: briefLens.pick === "" || on ? 1 : 0.55
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                            HoverHandler { id: lgHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: briefLens.toggle(modelData.key) }
                                            Row {
                                                id: lgRow
                                                anchors.centerIn: parent
                                                spacing: Tokens.space2
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 8; height: 8; radius: 4
                                                    color: lgChip.tint
                                                }
                                                C.AppText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.label
                                                    weight: Tokens.weightDemiBold
                                                    font.pixelSize: Tokens.fontCaption + 1
                                                    color: lgChip.on ? Theme.text_strong : Theme.on_surface
                                                }
                                                C.AppText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: String(briefLens.countFor(modelData.key))
                                                    mono: true
                                                    weight: Tokens.weightExtraBold
                                                    font.pixelSize: Tokens.fontCaption + 1
                                                    color: lgChip.tint
                                                    LayoutMirroring.enabled: false
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ INTENT — one spec sheet, four columns ═══════════
                        C.GlassPanel {
                            id: bfIntent
                            Layout.fillWidth: true
                            visible: page.briefOk && briefLens.intentItems.length > 0
                            radius: Tokens.radiusXl
                            implicitHeight: bfIntentGrid.implicitHeight + Tokens.space5 * 2
                            GridLayout {
                                id: bfIntentGrid
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                columns: briefLens.compact ? 1
                                         : Math.max(1, Math.min(briefLens.intentItems.length, content.wide ? 4 : 2))
                                columnSpacing: 0
                                rowSpacing: Tokens.space5
                                Repeater {
                                    model: briefLens.intentItems
                                    Item {
                                        id: icCell
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.alignment: Qt.AlignTop
                                        readonly property bool lead: (index % bfIntentGrid.columns) === 0
                                        implicitHeight: icCol.implicitHeight
                                        Rectangle {
                                            visible: !icCell.lead
                                            width: 1
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            color: Theme.border
                                        }
                                        ColumnLayout {
                                            id: icCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: icCell.lead ? Tokens.space1 : Tokens.space5
                                            anchors.rightMargin: Tokens.space5
                                            spacing: Tokens.space2
                                            RowLayout {
                                                spacing: 6
                                                C.IconGlyph { name: modelData.i; size: 14; glyphColor: Theme.primary }
                                                Eyebrow { text: modelData.l }
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: modelData.v
                                                wrapMode: Text.WordWrap
                                                font.pixelSize: Tokens.fontLabel
                                                lineHeight: 1.3
                                                color: Theme.on_surface
                                                selectable: true
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ SIGNALS — every labelled statement ══════════════
                        C.GlassPanel {
                            id: bfSignals
                            Layout.fillWidth: true
                            visible: page.briefOk && briefLens.rawTotal > 0
                            radius: Tokens.radiusXl
                            implicitHeight: bfSigCol.implicitHeight + Tokens.space6 * 2
                            ColumnLayout {
                                id: bfSigCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space6
                                spacing: Tokens.space5

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: content.width < 900 ? 1 : 2
                                    columnSpacing: Tokens.space4
                                    rowSpacing: Tokens.space3
                                    SectionHead {
                                        title: I18n.tr("What the brief stands on")
                                        hint: I18n.tr("every statement keeps its label")
                                        icon: "verified"
                                    }
                                    // segmented filter with a sliding pill
                                    Rectangle {
                                        id: bfSeg
                                        Layout.alignment: content.width < 900 ? Qt.AlignLeft : Qt.AlignRight
                                        implicitWidth: bfSegRow.implicitWidth + 8
                                        implicitHeight: 40
                                        radius: Tokens.radiusPill
                                        color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.07 : 0.06)
                                        border.width: 1
                                        border.color: Theme.border
                                        readonly property int idx: briefLens.pick === "observed" ? 1
                                                                 : briefLens.pick === "inferred" ? 2
                                                                 : briefLens.pick === "requires_studio" ? 3 : 0
                                        readonly property color tint: idx === 0 ? Theme.primary
                                                                      : page.classTint(briefLens.pick)
                                        Rectangle {
                                            id: bfSegPill
                                            readonly property Item target: bfSegRep.count > bfSeg.idx ? bfSegRep.itemAt(bfSeg.idx) : null
                                            y: 4
                                            height: bfSeg.height - 8
                                            x: target ? bfSegRow.x + target.x : 4
                                            width: target ? target.width : 0
                                            radius: Tokens.radiusPill
                                            color: U.withAlpha(bfSeg.tint, Theme.isDark ? 0.20 : 0.14)
                                            border.width: 1
                                            border.color: U.withAlpha(bfSeg.tint, 0.45)
                                            Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                            Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        }
                                        Row {
                                            id: bfSegRow
                                            anchors.centerIn: parent
                                            spacing: 0
                                            Repeater {
                                                id: bfSegRep
                                                model: [{ key: "", short: I18n.tr("All"), n: briefLens.rawTotal }]
                                                       .concat(briefLens.classes.map(function (c) {
                                                           return { key: c.key, short: c.short, n: briefLens.countFor(c.key) } }))
                                                Item {
                                                    id: segItem
                                                    readonly property bool on: briefLens.pick === modelData.key
                                                    width: segInner.implicitWidth + Tokens.space4 * 2
                                                    height: bfSeg.height - 8
                                                    HoverHandler { id: segHover; cursorShape: Qt.PointingHandCursor }
                                                    TapHandler { onTapped: briefLens.pick = modelData.key }
                                                    Row {
                                                        id: segInner
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Rectangle {
                                                            visible: modelData.key !== ""
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 7; height: 7; radius: 3.5
                                                            color: page.classTint(modelData.key)
                                                        }
                                                        C.AppText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: modelData.short
                                                            weight: segItem.on ? Tokens.weightBold : Tokens.weightMedium
                                                            font.pixelSize: Tokens.fontCaption + 1
                                                            color: segItem.on || segHover.hovered ? Theme.text_strong : Theme.on_surface_var
                                                        }
                                                        C.AppText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: String(modelData.n)
                                                            mono: true
                                                            weight: Tokens.weightBold
                                                            font.pixelSize: Tokens.fontMicro
                                                            color: Theme.outline
                                                            LayoutMirroring.enabled: false
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // the statements — all three classes side by side on a
                                // wide window, or the focused class alone
                                GridLayout {
                                    id: bfSigGrid
                                    Layout.fillWidth: true
                                    columns: briefLens.pick === "" && content.width >= 1000 ? 3 : 1
                                    columnSpacing: Tokens.space4
                                    rowSpacing: Tokens.space4
                                    Repeater {
                                        model: briefLens.classes
                                        Rectangle {
                                            id: sigCol
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: 1
                                            Layout.alignment: Qt.AlignTop
                                            readonly property color tint: page.classTint(modelData.key)
                                            readonly property var items: Insights.brief[modelData.key] || []
                                            visible: (briefLens.pick === "" || briefLens.pick === modelData.key) && items.length > 0
                                            implicitHeight: sigInner.implicitHeight + Tokens.space5 * 2
                                            radius: Tokens.radiusLg
                                            color: "transparent"
                                            border.width: 1
                                            border.color: U.withAlpha(tint, 0.20)
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                radius: sigCol.radius - 1
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: U.withAlpha(sigCol.tint, Theme.isDark ? 0.09 : 0.06) }
                                                    GradientStop { position: 0.45; color: U.withAlpha(sigCol.tint, 0.0) }
                                                }
                                            }
                                            ColumnLayout {
                                                id: sigInner
                                                anchors.fill: parent
                                                anchors.margins: Tokens.space5
                                                spacing: Tokens.space4

                                                // a short tinted tab marks the class
                                                Rectangle {
                                                    implicitWidth: 28; implicitHeight: 3
                                                    radius: 1.5
                                                    color: sigCol.tint
                                                }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: -Tokens.space1
                                                    spacing: Tokens.space2
                                                    C.IconGlyph { name: modelData.icon; size: 16; glyphColor: sigCol.tint }
                                                    C.AppText {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        weight: Tokens.weightExtraBold
                                                        font.pixelSize: Tokens.fontLabel
                                                        color: sigCol.tint
                                                        elide: Text.ElideRight
                                                    }
                                                    C.AppText {
                                                        text: String(sigCol.items.length)
                                                        mono: true
                                                        weight: Tokens.weightExtraBold
                                                        font.pixelSize: Tokens.fontTitle
                                                        color: sigCol.tint
                                                        LayoutMirroring.enabled: false
                                                    }
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: -Tokens.space2
                                                    text: modelData.note
                                                    wrapMode: Text.WordWrap
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.on_surface_var
                                                }
                                                Repeater {
                                                    model: sigCol.items
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Layout.maximumWidth: 860
                                                        spacing: Tokens.space3
                                                        Rectangle {
                                                            Layout.alignment: Qt.AlignTop
                                                            Layout.topMargin: 8
                                                            implicitWidth: 6; implicitHeight: 6
                                                            radius: 3
                                                            color: sigCol.tint
                                                        }
                                                        C.AppText {
                                                            Layout.fillWidth: true
                                                            text: modelData
                                                            wrapMode: Text.WordWrap
                                                            font.pixelSize: Tokens.fontBody
                                                            lineHeight: 1.4
                                                            color: Theme.on_surface
                                                            selectable: true
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ OPENINGS — each with the reason it might be wrong ═══
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space3
                            visible: page.briefOk && (Insights.brief.opportunities || []).length > 0
                            spacing: Tokens.space4
                            SectionHead {
                                title: I18n.tr("Openings worth testing")
                                hint: I18n.tr("each with the reason it might be wrong")
                                icon: "diamond"
                            }
                            GridLayout {
                                id: bfOppGrid
                                Layout.fillWidth: true
                                readonly property int n: (Insights.brief.opportunities || []).length
                                columns: content.width < 900 ? 1 : (content.width >= 1240 && n % 3 === 0 ? 3 : 2)
                                columnSpacing: Tokens.space4
                                rowSpacing: Tokens.space4
                                Repeater {
                                    model: Insights.brief.opportunities || []
                                    C.GlassPanel {
                                        id: oppCard
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredWidth: 1
                                        radius: Tokens.radiusXl
                                        hoverGlow: true
                                        elevation: hovered ? 1.6 : 1.0
                                        Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
                                        implicitHeight: oppCol.implicitHeight + Tokens.space6 * 2
                                        readonly property var opp: modelData
                                        C.CornerGlow {
                                            radius: oppCard.radius
                                            size: 320
                                            opacity: oppCard.hovered ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: Tokens.durGlow } }
                                        }
                                        ColumnLayout {
                                            id: oppCol
                                            anchors.fill: parent
                                            anchors.margins: Tokens.space6
                                            spacing: Tokens.space4
                                            Rectangle {
                                                implicitWidth: 36; implicitHeight: 36
                                                radius: Tokens.radiusMd
                                                color: U.withAlpha(Theme.primary, oppCard.hovered ? 0.20 : 0.12)
                                                border.width: 1
                                                border.color: U.withAlpha(Theme.primary, 0.28)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                                C.IconGlyph { anchors.centerIn: parent; name: "diamond"; size: 17; glyphColor: Theme.primary }
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: oppCard.opp.hypothesis || ""
                                                weight: Tokens.weightBold
                                                font.pixelSize: briefLens.compact ? Tokens.fontSubtitle : 19
                                                font.letterSpacing: I18n.rtl ? 0 : -0.25
                                                lineHeight: 1.28
                                                color: Theme.text_strong
                                                wrapMode: Text.WordWrap
                                                selectable: true
                                            }
                                            Item { Layout.fillHeight: true; implicitHeight: 0 }
                                            Repeater {
                                                model: [
                                                    { l: I18n.tr("WHY"),  v: oppCard.opp.evidence, c: "inferred",        i: "search" },
                                                    { l: I18n.tr("RISK"), v: oppCard.opp.risk,     c: "requires_studio", i: "warning" }
                                                ]
                                                ColumnLayout {
                                                    id: oppPart
                                                    Layout.fillWidth: true
                                                    visible: (modelData.v || "") !== ""
                                                    readonly property color tint: page.classTint(modelData.c)
                                                    spacing: Tokens.space1 + 2
                                                    RowLayout {
                                                        spacing: 6
                                                        C.IconGlyph { name: modelData.i; size: 13; glyphColor: oppPart.tint }
                                                        Eyebrow { text: modelData.l; color: oppPart.tint }
                                                    }
                                                    C.AppText {
                                                        Layout.fillWidth: true
                                                        text: modelData.v || ""
                                                        wrapMode: Text.WordWrap
                                                        font.pixelSize: Tokens.fontBody
                                                        lineHeight: 1.35
                                                        color: Theme.on_surface_var
                                                        selectable: true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ QUESTIONS — an accordion ═════════════════════════
                        C.GlassPanel {
                            id: qPanel
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space3
                            visible: page.briefOk && (Insights.brief.audience_questions || []).length > 0
                            radius: Tokens.radiusXl
                            implicitHeight: qCol.implicitHeight + Tokens.space6 * 2
                            property int open: 0
                            ColumnLayout {
                                id: qCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space6
                                spacing: 0
                                SectionHead {
                                    Layout.bottomMargin: Tokens.space4
                                    title: I18n.tr("Questions this audience is likely asking")
                                    hint: I18n.tr("hypotheses, not measured queries")
                                    icon: "contact_support"
                                }
                                Repeater {
                                    model: Insights.brief.audience_questions || []
                                    Rectangle {
                                        id: qRow
                                        Layout.fillWidth: true
                                        Layout.topMargin: index === 0 ? 0 : Tokens.space1
                                        readonly property bool isOpen: qPanel.open === index
                                        implicitHeight: qInner.implicitHeight + Tokens.space4 * 2
                                        radius: Tokens.radiusLg
                                        color: isOpen ? U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.05)
                                             : qHover.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                                        border.width: 1
                                        border.color: isOpen ? U.withAlpha(Theme.primary, 0.26) : "transparent"
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        Behavior on implicitHeight { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                        clip: true
                                        HoverHandler { id: qHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: qPanel.open = qRow.isOpen ? -1 : index }

                                        ColumnLayout {
                                            id: qInner
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: Tokens.space4
                                            anchors.leftMargin: Tokens.space4
                                            anchors.rightMargin: Tokens.space4
                                            spacing: Tokens.space3
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Tokens.space3
                                                Rectangle {
                                                    Layout.alignment: Qt.AlignTop
                                                    implicitWidth: 26; implicitHeight: 26
                                                    radius: 13
                                                    color: qRow.isOpen ? U.withAlpha(Theme.primary, 0.16)
                                                                       : U.withAlpha(Theme.on_surface_var, 0.08)
                                                    C.IconGlyph {
                                                        anchors.centerIn: parent
                                                        name: "help"; size: 14
                                                        glyphColor: qRow.isOpen ? Theme.primary : Theme.outline
                                                    }
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    text: modelData.question || ""
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontLabel
                                                    lineHeight: 1.25
                                                    color: Theme.text_strong
                                                    wrapMode: Text.WordWrap
                                                }
                                                C.IconGlyph {
                                                    Layout.alignment: Qt.AlignTop
                                                    name: qRow.isOpen ? "expand_less" : "expand_more"
                                                    size: 18
                                                    glyphColor: Theme.on_surface_var
                                                }
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 26 + Tokens.space3
                                                Layout.rightMargin: Tokens.space5
                                                Layout.bottomMargin: Tokens.space1
                                                visible: qRow.isOpen
                                                text: modelData.answer || ""
                                                wrapMode: Text.WordWrap
                                                font.pixelSize: Tokens.fontBody
                                                lineHeight: 1.4
                                                color: Theme.on_surface_var
                                                selectable: true
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═══ EXPERIMENTS — chapters, each a five-stage run ═══════
                        C.GlassPanel {
                            id: expPanel
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space3
                            visible: page.briefOk && (Insights.brief.experiments || []).length > 0
                            radius: Tokens.radiusXl
                            elevation: 1.3
                            implicitHeight: expCol.implicitHeight + Tokens.space6 * 2
                            readonly property var list: Insights.brief.experiments || []
                            property int sel: 0
                            readonly property var cur: list.length > 0 ? list[Math.min(sel, list.length - 1)] : ({})
                            readonly property bool rowMode: content.width >= 1100
                            onSelChanged: expSwap.restart()
                            onListChanged: sel = 0
                            ParallelAnimation {
                                id: expSwap
                                NumberAnimation { target: expBody; property: "opacity"; from: 0.0; to: 1.0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
                                NumberAnimation { target: expShift; property: "x"; from: I18n.rtl ? -14 : 14; to: 0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                id: expCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space6
                                spacing: Tokens.space5

                                SectionHead {
                                    title: I18n.tr("Things to actually try")
                                    hint: I18n.tr("one variable each, with the metric that settles it")
                                    icon: "checklist"
                                }

                                // chapter tabs: a number, a title, a progress hairline
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: briefLens.compact ? 1 : Math.max(1, expPanel.list.length)
                                    columnSpacing: Tokens.space3
                                    rowSpacing: Tokens.space2
                                    Repeater {
                                        model: expPanel.list
                                        Rectangle {
                                            id: expTab
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            implicitHeight: 66
                                            radius: Tokens.radiusLg
                                            readonly property bool on: expPanel.sel === index
                                            color: on ? U.withAlpha(Theme.primary, Theme.isDark ? 0.11 : 0.08)
                                                 : expTabHover.hovered ? Theme.hover_bg : U.withAlpha(Theme.surface_low, 0.6)
                                            border.width: 1
                                            border.color: on ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                                            clip: true
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            HoverHandler { id: expTabHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: expPanel.sel = index }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Tokens.space4
                                                anchors.rightMargin: Tokens.space4
                                                spacing: Tokens.space3
                                                C.AppText {
                                                    text: (index < 9 ? "0" : "") + (index + 1)
                                                    mono: true
                                                    weight: Tokens.weightExtraBold
                                                    font.pixelSize: Tokens.fontTitle
                                                    color: expTab.on ? Theme.primary : Theme.outline
                                                    LayoutMirroring.enabled: false
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: modelData.title || ""
                                                    weight: expTab.on ? Tokens.weightBold : Tokens.weightMedium
                                                    font.pixelSize: Tokens.fontCaption + 1
                                                    color: expTab.on ? Theme.text_strong : Theme.on_surface_var
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            // active chapter: a lit hairline along the bottom
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.leftMargin: Tokens.space4
                                                anchors.rightMargin: Tokens.space4
                                                height: 2
                                                radius: 1
                                                color: Theme.primary
                                                opacity: expTab.on ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: expBody
                                    Layout.fillWidth: true
                                    spacing: Tokens.space5
                                    transform: Translate { id: expShift; x: 0 }

                                    C.AppText {
                                        Layout.fillWidth: true
                                        Layout.topMargin: Tokens.space1
                                        text: expPanel.cur.title || ""
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: briefLens.compact ? 21 : 26
                                        font.letterSpacing: I18n.rtl ? 0 : -0.5
                                        lineHeight: 1.2
                                        color: Theme.text_strong
                                        wrapMode: Text.WordWrap
                                        selectable: true
                                    }

                                    // the run: because → expecting → testing → measure → if it fails
                                    GridLayout {
                                        id: pipeGrid
                                        Layout.fillWidth: true
                                        columns: expPanel.rowMode ? 5 : 1
                                        columnSpacing: Tokens.space5
                                        rowSpacing: Tokens.space4
                                        Repeater {
                                            id: stageRep
                                            model: [
                                                { l: I18n.tr("BECAUSE"),           v: expPanel.cur.evidence,      i: "search",      s: false },
                                                { l: I18n.tr("EXPECTING"),         v: expPanel.cur.hypothesis,    i: "lightbulb",   s: false },
                                                { l: I18n.tr("TESTING"),           v: expPanel.cur.variable,      i: "tune",        s: false },
                                                { l: I18n.tr("MEASURE IN STUDIO"), v: expPanel.cur.studio_metric, i: "lock",        s: true  },
                                                { l: I18n.tr("IF IT FAILS"),       v: expPanel.cur.rollback,      i: "restart_alt", s: false }
                                            ]
                                            ColumnLayout {
                                                id: stage
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.alignment: Qt.AlignTop
                                                visible: (modelData.v || "") !== ""
                                                spacing: Tokens.space2
                                                readonly property color tint: modelData.s ? Theme.warn : Theme.primary

                                                Item {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 36
                                                    Rectangle {
                                                        id: node
                                                        width: 36; height: 36; radius: 18
                                                        anchors.left: parent.left
                                                        color: U.withAlpha(stage.tint, Theme.isDark ? 0.14 : 0.10)
                                                        border.width: 1
                                                        border.color: U.withAlpha(stage.tint, 0.45)
                                                        C.IconGlyph {
                                                            anchors.centerIn: parent
                                                            name: modelData.i; size: 16
                                                            glyphColor: stage.tint
                                                        }
                                                    }
                                                    // connector toward the next stage (row mode only)
                                                    Rectangle {
                                                        visible: expPanel.rowMode && index < stageRep.count - 1
                                                        anchors.left: node.right
                                                        anchors.leftMargin: 8
                                                        anchors.right: parent.right
                                                        anchors.rightMargin: -pipeGrid.columnSpacing + 8
                                                        anchors.verticalCenter: node.verticalCenter
                                                        height: 2
                                                        radius: 1
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0; color: U.withAlpha(stage.tint, 0.55) }
                                                            GradientStop { position: 1.0; color: U.withAlpha(Theme.outline, 0.12) }
                                                        }
                                                    }
                                                    C.AppText {
                                                        visible: !expPanel.rowMode
                                                        anchors.left: node.right
                                                        anchors.leftMargin: Tokens.space3
                                                        anchors.verticalCenter: node.verticalCenter
                                                        text: modelData.l
                                                        mono: true
                                                        weight: Tokens.weightBold
                                                        font.pixelSize: Tokens.fontMicro
                                                        font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                                        color: modelData.s ? Theme.warn : Theme.on_surface_var
                                                    }
                                                }
                                                C.AppText {
                                                    visible: expPanel.rowMode
                                                    Layout.topMargin: Tokens.space1
                                                    text: modelData.l
                                                    mono: true
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontMicro
                                                    font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                                    color: modelData.s ? Theme.warn : Theme.on_surface_var
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: expPanel.rowMode ? 0 : 36 + Tokens.space3
                                                    text: modelData.v || ""
                                                    wrapMode: Text.WordWrap
                                                    font.pixelSize: Tokens.fontBody
                                                    lineHeight: 1.38
                                                    color: Theme.on_surface
                                                    selectable: true
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: expPanel.list.length > 1
                                    spacing: Tokens.space2
                                    C.AppText {
                                        text: (expPanel.sel + 1) + " / " + expPanel.list.length
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        LayoutMirroring.enabled: false
                                    }
                                    Item { Layout.fillWidth: true }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        implicitHeight: 34
                                        iconName: I18n.rtl ? "arrow_forward" : "arrow_back"
                                        text: I18n.tr("Previous")
                                        enabled: expPanel.sel > 0
                                        onClicked: expPanel.sel = expPanel.sel - 1
                                    }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        implicitHeight: 34
                                        iconName: I18n.rtl ? "arrow_back" : "arrow_forward"
                                        text: I18n.tr("Next")
                                        enabled: expPanel.sel < expPanel.list.length - 1
                                        onClicked: expPanel.sel = expPanel.sel + 1
                                    }
                                }
                            }
                        }
                    }

                    // ───────────────────────── 2 · EVIDENCE ──────────────
                    // v1.0.2 "case file" ledger.
                    //
                    // Design plan (check the render against this):
                    //   * Masthead — the ledger reads like the cover of a case
                    //     file: claim + source totals set big, and a pill-segment
                    //     composition bar that shows at a glance how much of the
                    //     brief is measured vs reasoned vs owner-only.
                    //   * Class tiles — the four filters become tiles (icon,
                    //     name, one-line meaning, big count, share bar). The
                    //     tile IS the legend, so the colours never need a key.
                    //   * Entries — each claim is a file entry: class glyph
                    //     tile, the claim set at reading size, then a quiet meta
                    //     line: signal-bar confidence, a stack of source
                    //     thumbnails, the caveat count. The class lives in the
                    //     glyph + a gradient rail; no more three equal pills.
                    //   * Unfolded — sources become media tiles (thumbnail,
                    //     channel, views, reach) beside an amber "stress test"
                    //     panel, side by side when there is room.
                    //   * Motion — entries rise in on a short stagger, the
                    //     chevron turns, the body fades; nothing loops.
                    ColumnLayout {
                        id: ledger
                        Layout.fillWidth: true
                        visible: page.lens === 2
                        spacing: Tokens.space4

                        property string filter: ""
                        // 0 = the brief's own order, 1 = strongest first
                        property int sortMode: 0
                        // open entries, keyed by row index. `openRev` is bumped on
                        // every change so bindings re-read the plain JS object.
                        property var openMap: ({})
                        property int openRev: 0
                        readonly property bool anyOpen: {
                            var _r = openRev
                            for (var k in openMap) if (openMap[k]) return true
                            return false
                        }
                        function isOpen(i) { var _r = openRev; return openMap[i] === true }
                        function toggle(i) { openMap[i] = !(openMap[i] === true); openRev++ }
                        function setAll(on) {
                            var m = {}
                            if (on) for (var i = 0; i < rows.length; i++) m[i] = true
                            openMap = m
                            openRev++
                        }

                        function confRank(c) { return c === "high" ? 3 : c === "medium" ? 2 : 1 }
                        readonly property var rows: {
                            var all = Insights.claims || []
                            var out = []
                            for (var i = 0; i < all.length; i++)
                                if (filter === "" || all[i].evidenceClass === filter) {
                                    var r = all[i]
                                    out.push({ d: r, n: i + 1 })
                                }
                            if (sortMode === 1)
                                out.sort(function (a, b) {
                                    var c = ledger.confRank(b.d.confidence) - ledger.confRank(a.d.confidence)
                                    if (c !== 0) return c
                                    return (b.d.sources || []).length - (a.d.sources || []).length
                                })
                            return out
                        }
                        function countOf(cls) {
                            var all = Insights.claims || []
                            var n = 0
                            for (var i = 0; i < all.length; i++) if (all[i].evidenceClass === cls) n++
                            return n
                        }
                        function confCount(c) {
                            var all = Insights.claims || []
                            var n = 0
                            for (var i = 0; i < all.length; i++) if ((all[i].confidence || "low") === c) n++
                            return n
                        }
                        // distinct videos the whole ledger leans on
                        readonly property int sourceCount: {
                            var all = Insights.claims || []
                            var seen = {}, n = 0
                            for (var i = 0; i < all.length; i++) {
                                var s = all[i].sources || []
                                for (var j = 0; j < s.length; j++)
                                    if (!seen[s[j].videoId]) { seen[s[j].videoId] = true; n++ }
                            }
                            return n
                        }
                        readonly property var classes: [
                            { c: "observed",        l: I18n.tr("Observed"),             d: I18n.tr("Measured in this data"),   icon: "query_stats" },
                            { c: "inferred",        l: I18n.tr("Inferred"),             d: I18n.tr("Reasoned from patterns"),  icon: "psychology" },
                            { c: "requires_studio", l: I18n.tr("Needs YouTube Studio"), d: I18n.tr("Owner-only metrics"),      icon: "lock" }
                        ]
                        function classIcon(cls) {
                            return cls === "observed" ? "query_stats" : cls === "inferred" ? "psychology" : "lock"
                        }
                        onFilterChanged: setAll(false)
                        onSortModeChanged: setAll(false)

                        // nothing to audit yet
                        C.GlassPanel {
                            Layout.fillWidth: true
                            visible: page.claimCount === 0
                            radius: Tokens.radiusXl
                            implicitHeight: noLedger.implicitHeight + Tokens.space7 * 2
                            ColumnLayout {
                                id: noLedger
                                anchors.centerIn: parent
                                width: Math.min(520, parent.width - Tokens.space7 * 2)
                                spacing: Tokens.space3
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 64; implicitHeight: 64
                                    radius: Tokens.radiusXl
                                    color: U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.08)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.primary, 0.30)
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: "receipt"; size: 30
                                        glyphColor: Theme.primary
                                    }
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("No evidence ledger yet")
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontTitle
                                    color: Theme.text_strong
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("The ledger lists every claim the brief makes, what it rests on and what would undermine it.")
                                    wrapMode: Text.WordWrap
                                    color: Theme.on_surface_var
                                }
                                C.PrimaryButton {
                                    Layout.alignment: Qt.AlignHCenter
                                    variant: "ghost"
                                    iconName: "auto_awesome"
                                    text: I18n.tr("Go to the brief")
                                    onClicked: page.goLens(1)
                                }
                            }
                        }

                        // ══ masthead: the case-file cover ══
                        C.GlassPanel {
                            id: ledgerHead
                            Layout.fillWidth: true
                            visible: page.claimCount > 0
                            radius: Tokens.radiusXl
                            implicitHeight: headGrid.implicitHeight + Tokens.space5 * 2
                            clip: true

                            // a slow wash of the accent from the reading corner
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.06) }
                                    GradientStop { position: 0.6; color: U.withAlpha(Theme.primary, 0.0) }
                                }
                            }

                            GridLayout {
                                id: headGrid
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.space5
                                columns: ledgerHead.width >= 900 ? 2 : 1
                                columnSpacing: Tokens.space7
                                rowSpacing: Tokens.space5

                                // left: the statement
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 5
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Tokens.space2
                                    Badge { label: I18n.tr("EVIDENCE LEDGER"); icon: "receipt"; tint: Theme.primary }
                                    Row {
                                        Layout.topMargin: Tokens.space2
                                        spacing: Tokens.space3
                                        C.AppText {
                                            id: bigClaims
                                            text: String(page.claimCount)
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: 44
                                            font.letterSpacing: -1.5
                                            color: Theme.text_strong
                                        }
                                        C.AppText {
                                            text: page.claimCount === 1 ? I18n.tr("claim") : I18n.tr("claims")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontTitle
                                            color: Theme.on_surface
                                            anchors.baseline: bigClaims.baseline
                                        }
                                        C.AppText {
                                            text: "·"
                                            font.pixelSize: Tokens.fontTitle
                                            color: Theme.outline
                                            anchors.baseline: bigClaims.baseline
                                        }
                                        C.AppText {
                                            text: String(ledger.sourceCount)
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: 44
                                            font.letterSpacing: -1.5
                                            color: Theme.primary
                                            anchors.baseline: bigClaims.baseline
                                        }
                                        C.AppText {
                                            text: ledger.sourceCount === 1 ? I18n.tr("video cited") : I18n.tr("videos cited")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontTitle
                                            color: Theme.on_surface
                                            anchors.baseline: bigClaims.baseline
                                        }
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Every claim the brief makes, the videos it rests on, and what would break it.")
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: Tokens.fontBody
                                        color: Theme.on_surface_var
                                    }
                                }

                                // right: composition + confidence
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 4
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: Tokens.space3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Eyebrow { text: I18n.tr("COMPOSITION") }
                                        Item { Layout.fillWidth: true }
                                        C.AppText {
                                            text: I18n.tr("{p}% measured").replace("{p}",
                                                  page.claimCount ? Math.round(ledger.countOf("observed") * 100 / page.claimCount) : 0)
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                        }
                                    }
                                    // pill segments, one per class, width = share
                                    Item {
                                        id: compBar
                                        Layout.fillWidth: true
                                        implicitHeight: 10
                                        readonly property var parts: {
                                            var out = []
                                            for (var i = 0; i < ledger.classes.length; i++) {
                                                var n = ledger.countOf(ledger.classes[i].c)
                                                if (n > 0) out.push({ c: ledger.classes[i].c, n: n })
                                            }
                                            return out
                                        }
                                        Row {
                                            anchors.fill: parent
                                            spacing: 3
                                            Repeater {
                                                model: compBar.parts
                                                Rectangle {
                                                    readonly property real share: page.claimCount ? modelData.n / page.claimCount : 0
                                                    width: Math.max(6, (compBar.width - 3 * (compBar.parts.length - 1)) * share)
                                                    height: compBar.height
                                                    radius: height / 2
                                                    color: page.classTint(modelData.c)
                                                    opacity: ledger.filter === "" || ledger.filter === modelData.c ? 1 : 0.28
                                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                                    Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                        }
                                    }
                                    // confidence spread
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: Tokens.space2
                                        spacing: Tokens.space4
                                        Eyebrow { text: I18n.tr("CONFIDENCE") }
                                        Item { Layout.fillWidth: true }
                                        Repeater {
                                            model: [
                                                { k: "high",   l: I18n.tr("high"),   lv: 3 },
                                                { k: "medium", l: I18n.tr("medium"), lv: 2 },
                                                { k: "low",    l: I18n.tr("low"),    lv: 1 }
                                            ]
                                            Row {
                                                spacing: 6
                                                ConfBars {
                                                    level: modelData.lv
                                                    tint: page.confTint(modelData.k)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: modelData.l
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.on_surface_var
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: String(ledger.confCount(modelData.k))
                                                    mono: true
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.text_strong
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ══ class tiles: the filter and the legend in one ══
                        GridLayout {
                            id: classGrid
                            Layout.fillWidth: true
                            visible: page.claimCount > 0
                            columns: ledger.width >= 980 ? 4 : 2
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3
                            Repeater {
                                model: [ { c: "", l: I18n.tr("All claims"), d: I18n.tr("The whole brief"), icon: "receipt" } ]
                                           .concat(ledger.classes)
                                AbstractButton {
                                    id: cTile
                                    readonly property int n: modelData.c === "" ? page.claimCount : ledger.countOf(modelData.c)
                                    readonly property bool on: ledger.filter === modelData.c
                                    readonly property color tint: modelData.c === "" ? Theme.primary : page.classTint(modelData.c)
                                    visible: modelData.c === "" || n > 0
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 72
                                    onClicked: ledger.filter = modelData.c
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    scale: pressed ? Tokens.pressScale : 1
                                    Behavior on scale { NumberAnimation { duration: Tokens.durFast } }

                                    background: Rectangle {
                                        radius: Tokens.radiusLg
                                        color: cTile.on ? U.withAlpha(cTile.tint, Theme.isDark ? 0.14 : 0.09)
                                             : cTile.hovered ? Theme.hover_bg : Theme.panel_bg
                                        border.width: 1
                                        border.color: cTile.on ? U.withAlpha(cTile.tint, 0.60)
                                                    : cTile.hovered ? U.withAlpha(cTile.tint, 0.30) : Theme.border
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        // share of the brief, along the floor of the tile
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: Tokens.space4
                                            anchors.bottomMargin: 8
                                            width: (parent.width - Tokens.space4 * 2)
                                            height: 3
                                            radius: 2
                                            color: U.withAlpha(cTile.tint, 0.14)
                                            Rectangle {
                                                width: parent.width * (page.claimCount ? cTile.n / page.claimCount : 0)
                                                height: parent.height
                                                radius: 2
                                                color: cTile.tint
                                                opacity: cTile.on ? 1 : 0.55
                                                Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }
                                    leftPadding: Tokens.space4
                                    rightPadding: Tokens.space4
                                    topPadding: 0
                                    bottomPadding: 6
                                    contentItem: RowLayout {
                                        spacing: Tokens.space3
                                        Rectangle {
                                            implicitWidth: 34; implicitHeight: 34
                                            radius: Tokens.radiusMd
                                            color: U.withAlpha(cTile.tint, cTile.on ? 0.22 : 0.12)
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: modelData.icon; size: 17
                                                glyphColor: cTile.tint
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: modelData.l
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontBody
                                                color: cTile.on ? Theme.text_strong : Theme.on_surface
                                                elide: Text.ElideRight
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: modelData.d
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface_var
                                                elide: Text.ElideRight
                                            }
                                        }
                                        C.AppText {
                                            text: String(cTile.n)
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontTitle
                                            color: cTile.on ? cTile.tint : Theme.text_strong
                                        }
                                    }
                                }
                            }
                        }

                        // ══ toolbar: order + unfold ══
                        RowLayout {
                            Layout.fillWidth: true
                            visible: page.claimCount > 0
                            spacing: Tokens.space3
                            C.SlideSegment {
                                Layout.preferredWidth: 300
                                equal: true
                                solid: false
                                cellHeight: 32
                                fontSize: Tokens.fontCaption + 1
                                model: [ I18n.tr("Brief order"), I18n.tr("Strongest first") ]
                                currentIndex: ledger.sortMode
                                onActivated: (i) => ledger.sortMode = i
                            }
                            Item { Layout.fillWidth: true }
                            C.AppText {
                                text: I18n.tr("{n} shown").replace("{n}", ledger.rows.length)
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                            }
                            PillAction {
                                glyph: ledger.anyOpen ? "expand_less" : "expand_more"
                                label: ledger.anyOpen ? I18n.tr("Collapse all") : I18n.tr("Expand all")
                                onClicked: ledger.setAll(!ledger.anyOpen)
                            }
                        }

                        // dropped claims, stated plainly
                        Rectangle {
                            Layout.fillWidth: true
                            visible: Insights.droppedClaims > 0
                            implicitHeight: dropRow.implicitHeight + Tokens.space3 * 2
                            radius: Tokens.radiusMd
                            color: U.withAlpha(Theme.warn, 0.10)
                            border.width: 1
                            border.color: U.withAlpha(Theme.warn, 0.35)
                            RowLayout {
                                id: dropRow
                                anchors.fill: parent
                                anchors.margins: Tokens.space3
                                spacing: Tokens.space2
                                C.IconGlyph { name: "warning"; size: 15; glyphColor: Theme.warn }
                                C.AppText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: I18n.tr("{n} claims cited videos that aren't in this result set and were dropped.")
                                          .replace("{n}", Insights.droppedClaims)
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.warn
                                }
                            }
                        }

                        // ══ the entries ══
                        Repeater {
                            model: ledger.rows
                            C.GlassPanel {
                                id: claimCard
                                Layout.fillWidth: true
                                radius: Tokens.radiusLg
                                readonly property var d: modelData.d
                                readonly property color tint: page.classColor(d.classKey)
                                readonly property bool isOpen: ledger.isOpen(index)
                                readonly property var srcs: d.sources || []
                                readonly property var lims: d.limitations || []
                                readonly property int confLevel: ledger.confRank(d.confidence)
                                readonly property bool twoCol: width >= 940 && srcs.length > 0 && lims.length > 0
                                implicitHeight: claimCol.implicitHeight + Tokens.space4 * 2
                                hoverGlow: true
                                border.color: isOpen ? U.withAlpha(tint, 0.55)
                                            : hovered ? U.withAlpha(tint, 0.28) : Theme.border
                                Behavior on implicitHeight { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                clip: true

                                // entrance: a short rise, staggered by position
                                opacity: 0
                                transform: Translate { id: cardRise; y: 10 }
                                Component.onCompleted: cardIn.start()
                                ParallelAnimation {
                                    id: cardIn
                                    SequentialAnimation {
                                        PauseAnimation { duration: Math.min(index, 8) * 35 }
                                        NumberAnimation { target: claimCard; property: "opacity"; to: 1; duration: Tokens.durPage; easing.type: Easing.OutCubic }
                                    }
                                    SequentialAnimation {
                                        PauseAnimation { duration: Math.min(index, 8) * 35 }
                                        NumberAnimation { target: cardRise; property: "y"; to: 0; duration: Tokens.durPage; easing.type: Easing.OutCubic }
                                    }
                                }

                                // open: the class colour washes in from the top
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    opacity: claimCard.isOpen ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: U.withAlpha(claimCard.tint, Theme.isDark ? 0.09 : 0.06) }
                                        GradientStop { position: 0.45; color: U.withAlpha(claimCard.tint, 0.0) }
                                    }
                                }

                                // class rail on the reading edge, fading downwards
                                Rectangle {
                                    width: 3
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.topMargin: Tokens.space4
                                    anchors.bottomMargin: Tokens.space4
                                    radius: 2
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: claimCard.tint }
                                        GradientStop { position: 1.0; color: U.withAlpha(claimCard.tint, claimCard.isOpen ? 0.25 : 0.55) }
                                    }
                                }

                                ColumnLayout {
                                    id: claimCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.space4
                                    anchors.leftMargin: Tokens.space5
                                    spacing: Tokens.space4

                                    // ── header (the click target) ──
                                    RowLayout {
                                        id: claimHead
                                        Layout.fillWidth: true
                                        spacing: Tokens.space4
                                        TapHandler { onTapped: ledger.toggle(index) }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: 40; implicitHeight: 40
                                            radius: Tokens.radiusMd
                                            color: U.withAlpha(claimCard.tint, Theme.isDark ? 0.14 : 0.10)
                                            border.width: 1
                                            border.color: U.withAlpha(claimCard.tint, 0.32)
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: ledger.classIcon(claimCard.d.evidenceClass)
                                                size: 19
                                                glyphColor: claimCard.tint
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2

                                            Row {
                                                spacing: Tokens.space2
                                                C.AppText {
                                                    text: claimCard.d.classLabel.toUpperCase()
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontMicro
                                                    font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                                    color: claimCard.tint
                                                }
                                                C.AppText {
                                                    text: "·  " + I18n.tr("claim {n}").replace("{n}", (modelData.n < 10 ? "0" : "") + modelData.n)
                                                    mono: true
                                                    font.pixelSize: Tokens.fontMicro
                                                    color: Theme.outline
                                                }
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: claimCard.d.claim
                                                wrapMode: Text.WordWrap
                                                weight: Tokens.weightDemiBold
                                                font.pixelSize: Tokens.fontLabel + 1
                                                lineHeight: 1.22
                                                color: Theme.text_strong
                                            }

                                            // meta line: confidence · sources · caveats
                                            Flow {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 2
                                                spacing: Tokens.space5

                                                Row {
                                                    spacing: Tokens.space2
                                                    ConfBars {
                                                        level: claimCard.confLevel
                                                        tint: page.confTint(claimCard.d.confidence)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: I18n.tr("{c} confidence").replace("{c}", claimCard.d.confidenceLabel)
                                                        weight: Tokens.weightMedium
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_surface
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }

                                                Row {
                                                    visible: claimCard.srcs.length > 0
                                                    spacing: Tokens.space2
                                                    // overlapping thumbnails, like faces on a thread
                                                    Item {
                                                        width: 32 + (Math.min(3, claimCard.srcs.length) - 1) * 20
                                                        height: 20
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Repeater {
                                                            model: Math.min(3, claimCard.srcs.length)
                                                            Rectangle {
                                                                x: index * 20
                                                                z: 3 - index
                                                                width: 32; height: 20
                                                                radius: 6
                                                                color: Theme.panel_bg
                                                                Thumb {
                                                                    anchors.fill: parent
                                                                    anchors.margins: 1.5
                                                                    radius: 5
                                                                    srcW: 96
                                                                    thumbId: claimCard.srcs[index].thumbId || ""
                                                                }
                                                            }
                                                        }
                                                    }
                                                    C.AppText {
                                                        text: claimCard.srcs.length === 1 ? I18n.tr("1 source")
                                                              : I18n.tr("{n} sources").replace("{n}", claimCard.srcs.length)
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }

                                                Row {
                                                    visible: claimCard.lims.length > 0
                                                    spacing: 6
                                                    C.IconGlyph {
                                                        name: "warning"; size: 13
                                                        glyphColor: Theme.warn
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: claimCard.lims.length === 1 ? I18n.tr("1 caveat")
                                                              : I18n.tr("{n} caveats").replace("{n}", claimCard.lims.length)
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: U.mix(Theme.warn, Theme.on_surface_var, 0.25)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }

                                        // chevron that turns
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: 32; implicitHeight: 32
                                            radius: 16
                                            color: claimCard.isOpen ? U.withAlpha(claimCard.tint, 0.16)
                                                 : claimCard.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                                            border.width: 1
                                            border.color: claimCard.isOpen ? U.withAlpha(claimCard.tint, 0.45) : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: "expand_more"
                                                size: 18
                                                glyphColor: claimCard.isOpen ? claimCard.tint : Theme.on_surface_var
                                                rotation: claimCard.isOpen ? 180 : 0
                                                Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    // ── unfolded body ──
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: claimCard.isOpen
                                        opacity: claimCard.isOpen ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                        spacing: Tokens.space4

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 1
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: U.withAlpha(claimCard.tint, 0.45) }
                                                GradientStop { position: 1.0; color: U.withAlpha(claimCard.tint, 0.0) }
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: claimCard.twoCol ? 2 : 1
                                            columnSpacing: Tokens.space5
                                            rowSpacing: Tokens.space4

                                            // rests on: the videos themselves
                                            ColumnLayout {
                                                id: srcCol
                                                visible: claimCard.srcs.length > 0
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 3
                                                Layout.alignment: Qt.AlignTop
                                                spacing: Tokens.space3
                                                RowLayout {
                                                    spacing: Tokens.space2
                                                    C.IconGlyph { name: "link"; size: 14; glyphColor: claimCard.tint }
                                                    Eyebrow { text: I18n.tr("RESTS ON") }
                                                    C.AppText {
                                                        text: String(claimCard.srcs.length)
                                                        mono: true
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.outline
                                                    }
                                                }
                                                GridLayout {
                                                    Layout.fillWidth: true
                                                    columns: Math.max(1, Math.min(claimCard.srcs.length, Math.floor((srcCol.width + Tokens.space3) / (300 + Tokens.space3))))
                                                    columnSpacing: Tokens.space3
                                                    rowSpacing: Tokens.space3
                                                    Repeater {
                                                        model: claimCard.srcs
                                                        Rectangle {
                                                            id: srcTile
                                                            Layout.fillWidth: true
                                                            Layout.preferredWidth: 1
                                                            implicitHeight: 72
                                                            radius: Tokens.radiusMd
                                                            readonly property bool hot: srcMa.containsMouse
                                                            color: hot ? U.mix(Theme.surface_low, claimCard.tint, 0.10) : Theme.surface_low
                                                            border.width: 1
                                                            border.color: hot ? U.withAlpha(claimCard.tint, 0.50) : Theme.border
                                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                                            MouseArea {
                                                                id: srcMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Qt.openUrlExternally(modelData.url)
                                                            }
                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.margins: Tokens.space2
                                                                spacing: Tokens.space3
                                                                Thumb {
                                                                    Layout.preferredWidth: 100
                                                                    Layout.preferredHeight: 56
                                                                    radius: Tokens.radiusSm
                                                                    srcW: 240
                                                                    thumbId: modelData.thumbId || ""
                                                                    // "Short" corner tag
                                                                    Rectangle {
                                                                        visible: modelData.isShort === true
                                                                        anchors.right: parent.right
                                                                        anchors.bottom: parent.bottom
                                                                        anchors.margins: 4
                                                                        width: shortLbl.implicitWidth + 8
                                                                        height: 16
                                                                        radius: 4
                                                                        color: U.withAlpha("#000000", 0.62)
                                                                        C.AppText {
                                                                            id: shortLbl
                                                                            anchors.centerIn: parent
                                                                            text: I18n.tr("Short")
                                                                            weight: Tokens.weightBold
                                                                            font.pixelSize: Tokens.fontMicro
                                                                            color: "#ffffff"
                                                                        }
                                                                    }
                                                                }
                                                                ColumnLayout {
                                                                    Layout.fillWidth: true
                                                                    spacing: 3
                                                                    C.AppText {
                                                                        Layout.fillWidth: true
                                                                        text: modelData.title
                                                                        weight: Tokens.weightDemiBold
                                                                        font.pixelSize: Tokens.fontCaption + 1
                                                                        color: srcTile.hot ? Theme.text_strong : Theme.on_surface
                                                                        wrapMode: Text.WordWrap
                                                                        maximumLineCount: 2
                                                                        elide: Text.ElideRight
                                                                    }
                                                                    C.AppText {
                                                                        Layout.fillWidth: true
                                                                        visible: text !== ""
                                                                        text: {
                                                                            var p = []
                                                                            if (modelData.channelTitle) p.push(modelData.channelTitle)
                                                                            if (modelData.views) p.push(I18n.tr("{v} views").replace("{v}", modelData.views))
                                                                            return p.join("  ·  ")
                                                                        }
                                                                        font.pixelSize: Tokens.fontCaption
                                                                        color: Theme.outline
                                                                        elide: Text.ElideRight
                                                                    }
                                                                }
                                                                ColumnLayout {
                                                                    Layout.alignment: Qt.AlignVCenter
                                                                    spacing: 2
                                                                    C.AppText {
                                                                        Layout.alignment: Qt.AlignRight
                                                                        visible: (modelData.multiplier || "") !== ""
                                                                        text: String(modelData.multiplier || "").replace(/x\s*$/i, "×")
                                                                        mono: true
                                                                        weight: Tokens.weightExtraBold
                                                                        font.pixelSize: Tokens.fontLabel
                                                                        color: claimCard.tint
                                                                    }
                                                                    C.IconGlyph {
                                                                        Layout.alignment: Qt.AlignRight
                                                                        name: "open_in_new"; size: 13
                                                                        glyphColor: srcTile.hot ? claimCard.tint : Theme.outline
                                                                        opacity: srcTile.hot ? 1 : 0.6
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // what would undermine it: an amber stress test
                                            Rectangle {
                                                visible: claimCard.lims.length > 0
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 2
                                                Layout.alignment: Qt.AlignTop
                                                implicitHeight: limCol.implicitHeight + Tokens.space4 * 2
                                                radius: Tokens.radiusMd
                                                color: U.withAlpha(Theme.warn, Theme.isDark ? 0.07 : 0.06)
                                                border.width: 1
                                                border.color: U.withAlpha(Theme.warn, 0.26)
                                                ColumnLayout {
                                                    id: limCol
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: Tokens.space4
                                                    spacing: Tokens.space3
                                                    RowLayout {
                                                        spacing: Tokens.space2
                                                        C.IconGlyph { name: "warning"; size: 14; glyphColor: Theme.warn }
                                                        Eyebrow { text: I18n.tr("WHAT WOULD UNDERMINE IT"); color: Theme.warn }
                                                    }
                                                    Repeater {
                                                        model: claimCard.lims
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Tokens.space3
                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignTop
                                                                Layout.topMargin: 7
                                                                implicitWidth: 6; implicitHeight: 6
                                                                radius: 3
                                                                color: Theme.warn
                                                            }
                                                            C.AppText {
                                                                Layout.fillWidth: true
                                                                text: modelData
                                                                wrapMode: Text.WordWrap
                                                                font.pixelSize: Tokens.fontBody
                                                                lineHeight: 1.2
                                                                color: Theme.on_surface
                                                                selectable: true
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // footer: take the claim with you
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2
                                            Item { Layout.fillWidth: true }
                                            PillAction {
                                                id: copyBtn
                                                property bool done: false
                                                glyph: done ? "check" : "content_copy"
                                                label: done ? I18n.tr("Copied") : I18n.tr("Copy with sources")
                                                onClicked: {
                                                    var t = claimCard.d.claim + "\n[" + claimCard.d.classLabel + " · "
                                                          + I18n.tr("{c} confidence").replace("{c}", claimCard.d.confidenceLabel) + "]"
                                                    for (var i = 0; i < claimCard.srcs.length; i++)
                                                        t += "\n- " + claimCard.srcs[i].title + "  " + claimCard.srcs[i].url
                                                    for (var j = 0; j < claimCard.lims.length; j++)
                                                        t += "\n! " + claimCard.lims[j]
                                                    clipHelper.put(t)
                                                    done = true
                                                    copyReset.restart()
                                                }
                                                Timer { id: copyReset; interval: 1600; onTriggered: copyBtn.done = false }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ───────────────────────── 3 · LIMITS ────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: page.lens === 3
                        spacing: Tokens.space5

                        C.GlassPanel {
                            Layout.fillWidth: true
                            radius: Tokens.radiusXl
                            implicitHeight: covCol.implicitHeight + Tokens.space5 * 2
                            ColumnLayout {
                                id: covCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4
                                SectionHead {
                                    title: I18n.tr("What this snapshot could see")
                                    hint: I18n.tr("how many rows carried each field")
                                    icon: "visibility"
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: content.width < 700 ? 2 : (content.width < 1100 ? 4 : 8)
                                    columnSpacing: Tokens.space3
                                    rowSpacing: Tokens.space3
                                    Repeater {
                                        model: Insights.coverageRows
                                        Rectangle {
                                            id: covCell
                                            Layout.fillWidth: true
                                            implicitHeight: covInner.implicitHeight + Tokens.space4 * 2
                                            radius: Tokens.radiusLg
                                            readonly property color tint: modelData.frac >= 0.999 ? Theme.secondary_container
                                                                        : modelData.frac < 0.5 ? Theme.warn
                                                                        : Theme.primary
                                            color: covHover.hovered ? U.mix(Theme.surface_low, tint, 0.07) : Theme.surface_low
                                            border.width: 1
                                            border.color: covHover.hovered ? U.withAlpha(tint, 0.35) : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            HoverHandler { id: covHover }
                                            ColumnLayout {
                                                id: covInner
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.margins: Tokens.space3
                                                spacing: Tokens.space2
                                                C.ScoreRing {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    value: Math.round(modelData.frac * 100)
                                                    accent: covCell.tint
                                                    ringSize: 64
                                                    thickness: 5
                                                    caption: ""
                                                    suffix: "%"
                                                    showHalo: false
                                                    numberSize: 15
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: modelData.label
                                                    weight: Tokens.weightDemiBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.on_surface
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: modelData.value
                                                    mono: true
                                                    font.pixelSize: Tokens.fontMicro
                                                    color: Theme.on_surface_var
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        C.GlassPanel {
                            Layout.fillWidth: true
                            radius: Tokens.radiusXl
                            implicitHeight: limCol.implicitHeight + Tokens.space5 * 2
                            ColumnLayout {
                                id: limCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                spacing: Tokens.space4
                                SectionHead {
                                    title: I18n.tr("What it cannot tell you")
                                    hint: I18n.tr("public data has hard edges")
                                    icon: "lock"
                                    tint: Theme.warn
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: content.width < 900 ? 1 : 2
                                    columnSpacing: Tokens.space3
                                    rowSpacing: Tokens.space3
                                    Repeater {
                                        model: [
                                            { t: I18n.tr("Click-through rate, impressions, retention and watch time are owner-only — they are not public for anyone else's videos."), i: "lock" },
                                            { t: I18n.tr("Where views came from (browse, suggested, search) is not public, so no result here proves a discovery surface."), i: "route" },
                                            { t: I18n.tr("Subscriber counts are current and rounded, not what they were when a video was published."), i: "user" },
                                            { t: I18n.tr("Search result order is a personalised, region-sensitive snapshot — not a census of the niche."), i: "public" }
                                        ]
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            implicitHeight: limRow.implicitHeight + Tokens.space4 * 2
                                            radius: Tokens.radiusLg
                                            color: U.withAlpha(Theme.warn, 0.05)
                                            border.width: 1
                                            border.color: U.withAlpha(Theme.warn, 0.20)
                                            RowLayout {
                                                id: limRow
                                                anchors.fill: parent
                                                anchors.margins: Tokens.space4
                                                spacing: Tokens.space3
                                                C.IconGlyph {
                                                    name: modelData.i; size: 16
                                                    glyphColor: Theme.warn
                                                    Layout.alignment: Qt.AlignTop
                                                }
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: modelData.t
                                                    wrapMode: Text.WordWrap
                                                    font.pixelSize: Tokens.fontCaption + 1
                                                    color: Theme.on_surface
                                                }
                                            }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: (Insights.brief.limits || []).length > 0
                                    spacing: Tokens.space2
                                    Eyebrow { text: I18n.tr("THE MODEL'S OWN CAVEATS"); Layout.topMargin: Tokens.space2 }
                                    Repeater {
                                        model: Insights.brief.limits || []
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2
                                            C.IconGlyph {
                                                name: "auto_awesome"; size: 13
                                                glyphColor: Theme.outline
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 2
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: modelData
                                                wrapMode: Text.WordWrap
                                                font.pixelSize: Tokens.fontCaption + 1
                                                color: Theme.on_surface_var
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
