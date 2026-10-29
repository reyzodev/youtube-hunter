import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.3 — "What gets more views here" (Niche Scan → Measured).
//
// Replaces the v1.0.2 diverging chart, which was exact but unreadable for
// anyone who had never met a log-scale ratio ("1.3×", "¼×", "… videos").
// Same data (Insights.earnRows / earnPlan, built by core/analysis/earn_read),
// read in three layers, each one optional:
//
//   1. THE ADVICE   three cards: do more of · skip · doesn't matter
//   2. THE CHART    every choice as "+30% / −40% views per day" on a bar that
//                   grows left (fewer) or right (more) from "typical", with how
//                   many videos it rests on and a 1-3 dot trust meter
//   3. THE READING  one plain sentence for the row under the pointer (or the
//                   strongest row), so the chart explains itself
//
// Category chips filter the chart; "How to read this" unfolds a three-line
// primer. Every count is shown in full: nothing is elided to "…".
C.GlassPanel {
    id: root
    property var rows: []
    property var plan: ({})
    property string baseText: "—"
    property int datedRows: 0
    property bool compact: false

    radius: Tokens.radiusXl
    implicitHeight: col.implicitHeight + Tokens.space6 * 2

    readonly property color up: Theme.secondary_container
    readonly property color down: U.mix(Theme.error, Theme.on_surface_var, 0.2)
    readonly property color flatC: Theme.outline

    function toneOf(v) { return v === "do" ? up : v === "avoid" ? down : flatC }

    // ── filter ──
    property string filter: "all"
    readonly property var shown: {
        var out = []
        for (var i = 0; i < rows.length; i++)
            if (filter === "all" || rows[i].groupKey === filter) out.push(rows[i])
        return out
    }
    readonly property var filters: {
        var defs = [ { k: "all", l: I18n.tr("All") }, { k: "title", l: I18n.tr("Titles") },
                     { k: "length", l: I18n.tr("Length") }, { k: "format", l: I18n.tr("Format") },
                     { k: "extras", l: I18n.tr("Extras") } ]
        var out = []
        for (var d = 0; d < defs.length; d++) {
            var n = 0
            for (var i = 0; i < rows.length; i++)
                if (defs[d].k === "all" || rows[i].groupKey === defs[d].k) n++
            if (n > 0) out.push({ k: defs[d].k, l: defs[d].l, n: n })
        }
        return out
    }
    onRowsChanged: { filter = "all"; hot = -1; grow = 0; growAnim.restart() }

    // ── hover + entrance ──
    property int hot: -1
    readonly property var focusRow: hot >= 0 && hot < shown.length ? shown[hot]
                                   : (shown.length > 0 ? shown[0] : null)
    property real grow: 0
    NumberAnimation { id: growAnim; target: root; property: "grow"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
    Component.onCompleted: growAnim.start()
    property bool helpOpen: false

    readonly property int labelW: compact ? 150 : 240
    readonly property int tailW: compact ? 132 : 200

    // trust meter: three dots
    component Dots: Row {
        id: dt
        property int level: 1
        property color tint: Theme.primary
        spacing: 3
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 6; height: 6; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: index < dt.level ? dt.tint : U.withAlpha(Theme.outline, 0.28)
            }
        }
    }

    // one advice card
    component PlanCard: Rectangle {
        id: pc
        property string kicker: ""
        property string glyph: ""
        property color tint: Theme.primary
        property var items: []          // [{label, pct, rowsText, strength}]
        property var plain: []          // [label] for the "doesn't matter" card
        property int more: 0
        property string empty: ""
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        radius: Tokens.radiusLg
        color: U.withAlpha(tint, Theme.isDark ? 0.09 : 0.07)
        border.width: 1
        border.color: U.withAlpha(tint, pcHover.hovered ? 0.5 : 0.26)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        implicitHeight: pcCol.implicitHeight + Tokens.space4 * 2
        HoverHandler { id: pcHover }
        // a soft wash falling off the top edge
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: pc.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(pc.tint, Theme.isDark ? 0.10 : 0.07) }
                GradientStop { position: 0.6; color: U.withAlpha(pc.tint, 0.0) }
            }
        }
        ColumnLayout {
            id: pcCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space4
            spacing: Tokens.space3
            RowLayout {
                spacing: Tokens.space2
                Rectangle {
                    implicitWidth: 26; implicitHeight: 26; radius: 9
                    color: U.withAlpha(pc.tint, 0.18)
                    C.IconGlyph { anchors.centerIn: parent; name: pc.glyph; size: 15; glyphColor: pc.tint }
                }
                C.AppText {
                    text: pc.kicker
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    font.letterSpacing: 1.4
                    color: pc.tint
                }
            }
            Repeater {
                model: pc.items
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        C.AppText {
                            Layout.fillWidth: true
                            text: modelData.label
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.text_strong
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            spacing: Tokens.space2
                            Dots { level: modelData.strength; tint: pc.tint; anchors.verticalCenter: parent.verticalCenter }
                            C.AppText {
                                text: modelData.rowsText
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    C.AppText {
                        Layout.alignment: Qt.AlignTop
                        text: modelData.pct
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontSubtitle + 2
                        color: pc.tint
                        LayoutMirroring.enabled: false
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                visible: pc.plain.length > 0
                spacing: Tokens.space2
                Repeater {
                    model: pc.plain
                    Rectangle {
                        required property var modelData
                        radius: Tokens.radiusPill
                        color: U.withAlpha(Theme.outline, 0.10)
                        border.width: 1
                        border.color: U.withAlpha(Theme.outline, 0.22)
                        implicitWidth: ptx.implicitWidth + Tokens.space3 * 2
                        implicitHeight: 28
                        C.AppText {
                            id: ptx
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: Tokens.fontCaption + 1
                            weight: Tokens.weightMedium
                            color: Theme.on_surface
                        }
                    }
                }
                C.AppText {
                    visible: pc.more > 0
                    height: 28
                    verticalAlignment: Text.AlignVCenter
                    text: I18n.tr("+{n} more").replace("{n}", pc.more)
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                }
            }
            C.AppText {
                Layout.fillWidth: true
                visible: pc.items.length === 0 && pc.plain.length === 0
                text: pc.empty
                font.pixelSize: Tokens.fontBody
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.space6
        spacing: Tokens.space5

        // ══ header ══
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space4
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40; implicitHeight: 40; radius: 13
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(root.up, 0.30) }
                    GradientStop { position: 1.0; color: U.withAlpha(root.up, 0.12) }
                }
                border.width: 1
                border.color: U.withAlpha(root.up, 0.40)
                C.IconGlyph { anchors.centerIn: parent; name: "bolt"; fill: true; size: 19; glyphColor: root.up }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("What gets more views here")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontTitle
                    color: Theme.text_strong
                    wrapMode: Text.WordWrap
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("Each row compares one kind of video with a typical video in this search · {n} dated videos")
                          .replace("{n}", root.datedRows)
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface_var
                    wrapMode: Text.WordWrap
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 0
                C.AppText {
                    Layout.alignment: Qt.AlignRight
                    text: root.baseText
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontDisplay
                    color: Theme.text_strong
                    LayoutMirroring.enabled: false
                }
                C.AppText {
                    Layout.alignment: Qt.AlignRight
                    text: I18n.tr("views/day for a typical video")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                }
            }
        }

        // ══ 1 · the advice ══
        GridLayout {
            Layout.fillWidth: true
            visible: root.plan.hasAny === true
            columns: root.compact ? 1 : 3
            columnSpacing: Tokens.space3
            rowSpacing: Tokens.space3
            PlanCard {
                kicker: I18n.tr("DO MORE OF")
                glyph: "trending_up"
                tint: root.up
                items: root.plan.doMore || []
                empty: I18n.tr("Nothing clearly beats a typical video here yet.")
            }
            PlanCard {
                kicker: I18n.tr("SKIP")
                glyph: "close"
                tint: root.down
                items: root.plan.skip || []
                empty: I18n.tr("Nothing here clearly drags views down.")
            }
            PlanCard {
                kicker: I18n.tr("DOESN'T MATTER")
                glyph: "remove"
                tint: root.flatC
                plain: root.plan.same || []
                more: root.plan.sameMore || 0
                empty: I18n.tr("Every choice here moves views one way or the other.")
            }
        }

        // ══ filter + how-to-read ══
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space2
            Repeater {
                model: root.filters
                AbstractButton {
                    id: fb
                    required property var modelData
                    readonly property bool on: root.filter === modelData.k
                    implicitHeight: 32
                    implicitWidth: fbRow.implicitWidth + Tokens.space4 * 2
                    hoverEnabled: true
                    onClicked: { root.filter = modelData.k; root.hot = -1 }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle {
                        radius: Tokens.radiusPill
                        color: fb.on ? U.withAlpha(Theme.primary, Theme.isDark ? 0.18 : 0.11)
                             : fb.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                        border.width: 1
                        border.color: fb.on ? U.withAlpha(Theme.primary, 0.55) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    contentItem: Item {
                        implicitWidth: fbRow.implicitWidth
                        implicitHeight: fbRow.implicitHeight
                        Row {
                            id: fbRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.AppText {
                                text: fb.modelData.l
                                weight: fb.on ? Tokens.weightBold : Tokens.weightMedium
                                font.pixelSize: Tokens.fontCaption + 1
                                color: fb.on ? Theme.text_strong : Theme.on_surface
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: String(fb.modelData.n)
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: fb.on ? Theme.primary : Theme.outline
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            AbstractButton {
                id: helpBtn
                implicitHeight: 32
                implicitWidth: helpRow.implicitWidth + Tokens.space3 * 2
                hoverEnabled: true
                onClicked: root.helpOpen = !root.helpOpen
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle {
                    radius: Tokens.radiusPill
                    color: helpBtn.hovered || root.helpOpen ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                }
                contentItem: Item {
                    implicitWidth: helpRow.implicitWidth
                    implicitHeight: helpRow.implicitHeight
                    Row {
                        id: helpRow
                        anchors.centerIn: parent
                        spacing: 6
                        C.IconGlyph { name: "help"; size: 15; glyphColor: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        C.AppText {
                            text: I18n.tr("How to read this")
                            weight: Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontCaption + 1
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }

        // ══ primer (folds) ══
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.helpOpen ? primer.implicitHeight : 0
            implicitHeight: Layout.preferredHeight
            clip: true
            visible: Layout.preferredHeight > 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            Rectangle {
                id: primer
                width: parent.width
                radius: Tokens.radiusLg
                color: U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.05)
                border.width: 1
                border.color: U.withAlpha(Theme.primary, 0.2)
                implicitHeight: primerCol.implicitHeight + Tokens.space4 * 2
                ColumnLayout {
                    id: primerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.space4
                    spacing: Tokens.space2
                    Repeater {
                        model: [
                            { g: "target", t: I18n.tr("The middle line is a typical video in this search. A bar to the right gets more views per day, a bar to the left gets fewer.") },
                            { g: "schedule", t: I18n.tr("It is views PER DAY, so an old video doesn't win just by being old.") },
                            { g: "bar_chart", t: I18n.tr("The dots say how much to trust a row: one dot means only a handful of videos, three means 20 or more.") }
                        ]
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            C.IconGlyph { name: modelData.g; size: 15; glyphColor: Theme.primary; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.t
                                font.pixelSize: Tokens.fontBody
                                color: Theme.on_surface
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }

        // ══ 2 · the chart ══
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            // legend in words, not ratios
            Item {
                Layout.fillWidth: true
                implicitHeight: 22
                LayoutMirroring.enabled: false
                Item {
                    id: legend
                    x: root.labelW
                    width: parent.width - root.labelW - root.tailW
                    height: parent.height
                    C.AppText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "◂ " + I18n.tr("fewer views")
                        font.pixelSize: Tokens.fontCaption
                        weight: Tokens.weightDemiBold
                        color: root.down
                    }
                    C.AppText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("typical")
                        font.pixelSize: Tokens.fontCaption
                        weight: Tokens.weightBold
                        color: Theme.on_surface_var
                    }
                    C.AppText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("more views") + " ▸"
                        font.pixelSize: Tokens.fontCaption
                        weight: Tokens.weightDemiBold
                        color: root.up
                    }
                }
            }

            Repeater {
                model: root.shown
                Item {
                    id: er
                    required property var modelData
                    required property int index
                    readonly property bool lit: root.hot === index
                    readonly property color tint: root.toneOf(modelData.verdict)
                    Layout.fillWidth: true
                    implicitHeight: 48
                    opacity: root.hot < 0 || lit ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    HoverHandler {
                        onHoveredChanged: root.hot = hovered ? er.index : (root.hot === er.index ? -1 : root.hot)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusMd
                        color: U.withAlpha(er.tint, er.lit ? 0.10 : 0)
                        border.width: 1
                        border.color: U.withAlpha(er.tint, er.lit ? 0.3 : 0)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }

                    // label + category
                    ColumnLayout {
                        x: Tokens.space3
                        width: root.labelW - Tokens.space4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        C.AppText {
                            Layout.fillWidth: true
                            text: er.modelData.label
                            weight: er.lit ? Tokens.weightBold : Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontBody
                            color: er.modelData.verdict === "same" ? Theme.on_surface : Theme.text_strong
                            elide: Text.ElideRight
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: er.modelData.group
                            font.pixelSize: Tokens.fontMicro
                            font.letterSpacing: 0.8
                            color: Theme.outline
                            elide: Text.ElideRight
                        }
                    }

                    // bar, growing from "typical"
                    Item {
                        id: track
                        x: root.labelW
                        width: parent.width - root.labelW - root.tailW
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        LayoutMirroring.enabled: false
                        Rectangle {
                            anchors.fill: parent
                            radius: 7
                            color: U.withAlpha(Theme.outline, 0.07)
                        }
                        // half / double guides
                        Repeater {
                            model: [0.25, 0.75]
                            Rectangle {
                                required property var modelData
                                x: track.width * modelData
                                width: 1; height: parent.height
                                color: U.withAlpha(Theme.outline, 0.18)
                            }
                        }
                        Rectangle {
                            readonly property real len: Math.max(6, Math.abs(er.modelData.pos) * track.width / 2 * root.grow)
                            x: er.modelData.pos >= 0 ? track.width / 2 : track.width / 2 - len
                            width: len
                            height: parent.height
                            radius: 7
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: er.modelData.pos >= 0 ? U.withAlpha(er.tint, 0.45) : er.tint }
                                GradientStop { position: 1.0; color: er.modelData.pos >= 0 ? er.tint : U.withAlpha(er.tint, 0.45) }
                            }
                        }
                        // the "typical" line, with a soft glow
                        Rectangle {
                            x: track.width / 2 - 1
                            y: -6
                            width: 2
                            height: parent.height + 12
                            radius: 1
                            color: Theme.on_surface_var
                            opacity: 0.55
                        }
                    }

                    // pct · trust · count — every number shown in full
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.space3
                        anchors.verticalCenter: parent.verticalCenter
                        layoutDirection: Qt.RightToLeft
                        LayoutMirroring.enabled: false
                        spacing: Tokens.space3
                        C.AppText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 58
                            horizontalAlignment: Text.AlignRight
                            text: er.modelData.pct
                            mono: true
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontLabel
                            color: er.modelData.verdict === "same" ? Theme.on_surface_var : er.tint
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !root.compact
                            spacing: 3
                            Dots { level: er.modelData.strength; tint: er.tint; anchors.right: parent.right }
                            C.AppText {
                                anchors.right: parent.right
                                text: er.modelData.rowsText
                                font.pixelSize: Tokens.fontMicro
                                color: Theme.on_surface_var
                            }
                        }
                    }
                }
            }
        }

        // ══ 3 · the reading, in one sentence ══
        Rectangle {
            Layout.fillWidth: true
            visible: root.focusRow !== null
            radius: Tokens.radiusLg
            color: root.focusRow ? U.withAlpha(root.toneOf(root.focusRow.verdict), Theme.isDark ? 0.10 : 0.07) : "transparent"
            border.width: 1
            border.color: root.focusRow ? U.withAlpha(root.toneOf(root.focusRow.verdict), 0.30) : "transparent"
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            implicitHeight: readRow.implicitHeight + Tokens.space4 * 2
            RowLayout {
                id: readRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space4
                spacing: Tokens.space3
                C.IconGlyph {
                    Layout.alignment: Qt.AlignTop
                    name: "lightbulb"
                    size: 18
                    glyphColor: root.focusRow ? root.toneOf(root.focusRow.verdict) : Theme.primary
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: root.focusRow ? root.focusRow.sentence : ""
                    font.pixelSize: Tokens.fontLabel
                    lineHeight: 1.3
                    color: Theme.text_strong
                    wrapMode: Text.WordWrap
                }
                C.AppText {
                    Layout.alignment: Qt.AlignTop
                    visible: root.focusRow !== null
                    text: root.focusRow ? root.focusRow.strengthText : ""
                    font.pixelSize: Tokens.fontCaption
                    weight: Tokens.weightDemiBold
                    color: Theme.on_surface_var
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            C.IconGlyph { name: "info"; size: 13; glyphColor: Theme.outline; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
            C.AppText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: I18n.tr("Choices with fewer than 4 videos (or that cover nearly the whole set) are hidden. This is a pattern inside one search, not a guarantee: test it on your own channel.")
                font.pixelSize: Tokens.fontCaption
                color: Theme.outline
            }
        }
    }
}
