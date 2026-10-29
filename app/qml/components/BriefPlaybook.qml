import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.3 — the ACTION half of the Niche Scan brief.
//
// The v12 brief told a creator what the niche looks like (signals, openings,
// questions, experiments) but never answered the question they opened it
// with: "so what do I make?". This block sits right under the intent sheet
// and answers it, from the new brief fields (core/ai/insights.py):
//
//   GAME PLAN       format · length · title style · thumbnail · first 30 s
//   VIDEO IDEAS     five titles ready to film, each with the number it rests on
//   TITLE FORMULAS  reusable patterns + the REAL video that uses them
//   KEYWORDS        click to copy
//   AVOID           what underperforms here, and why
//   COMPETITION     low / medium / high on a 3-step meter + the edge to take
//
// Every panel hides itself when its field is empty (older saved briefs).
ColumnLayout {
    id: root
    property var brief: ({})
    property bool compact: false
    property bool wide: false
    signal copyRequested(string text)

    spacing: Tokens.space5

    readonly property var gp: brief.game_plan || ({})
    readonly property var ideas: brief.video_ideas || []
    readonly property var formulas: brief.title_formulas || []
    readonly property var keywords: brief.keywords || []
    readonly property var avoid: brief.avoid || []
    readonly property var comp: brief.competition || ({})
    readonly property var planItems: {
        var defs = [
            { k: "format",      l: I18n.tr("FORMAT"),        g: "smart_display" },
            { k: "length",      l: I18n.tr("LENGTH"),        g: "schedule" },
            { k: "title_style", l: I18n.tr("TITLE STYLE"),   g: "text" },
            { k: "thumbnail",   l: I18n.tr("THUMBNAIL"),     g: "image" },
            { k: "first_30s",   l: I18n.tr("FIRST 30 SECONDS"), g: "play_circle" }
        ]
        var out = []
        for (var i = 0; i < defs.length; i++) {
            var v = String(root.gp[defs[i].k] || "").trim()
            if (v !== "") out.push({ l: defs[i].l, g: defs[i].g, v: v })
        }
        return out
    }
    readonly property color accent: Theme.primary
    readonly property color good: Theme.secondary_container
    readonly property color bad: U.mix(Theme.error, Theme.on_surface_var, 0.2)
    function effortTint(e) { return e === "Easy" ? good : e === "Hard" ? Theme.error : Theme.warn }
    function levelIndex(l) { return l === "low" ? 1 : l === "medium" ? 2 : l === "high" ? 3 : 0 }
    function levelText(l) {
        return l === "low" ? I18n.tr("Low competition") : l === "medium" ? I18n.tr("Medium competition")
             : l === "high" ? I18n.tr("High competition") : ""
    }

    component Head: RowLayout {
        id: hd
        property string glyph: ""
        property string title: ""
        property string hint: ""
        property color tint: Theme.primary
        Layout.fillWidth: true
        spacing: Tokens.space3
        Rectangle {
            implicitWidth: 34; implicitHeight: 34; radius: 11
            color: U.withAlpha(hd.tint, Theme.isDark ? 0.16 : 0.11)
            border.width: 1
            border.color: U.withAlpha(hd.tint, 0.32)
            C.IconGlyph { anchors.centerIn: parent; name: hd.glyph; size: 17; glyphColor: hd.tint }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            C.AppText {
                Layout.fillWidth: true
                text: hd.title
                weight: Tokens.weightExtraBold
                font.pixelSize: Tokens.fontSubtitle + 1
                color: Theme.text_strong
                wrapMode: Text.WordWrap
            }
            C.AppText {
                Layout.fillWidth: true
                visible: hd.hint !== ""
                text: hd.hint
                font.pixelSize: Tokens.fontCaption + 1
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
            }
        }
    }

    component Tag: Rectangle {
        id: tg
        property string text: ""
        property color tint: Theme.on_surface_var
        radius: Tokens.radiusPill
        color: U.withAlpha(tint, 0.10)
        border.width: 1
        border.color: U.withAlpha(tint, 0.30)
        implicitWidth: tgTxt.implicitWidth + Tokens.space3 * 2
        implicitHeight: 24
        visible: text !== ""
        C.AppText {
            id: tgTxt
            anchors.centerIn: parent
            text: tg.text
            font.pixelSize: Tokens.fontCaption
            weight: Tokens.weightBold
            color: tg.tint
        }
    }

    // ══ GAME PLAN ══
    C.GlassPanel {
        Layout.fillWidth: true
        visible: root.planItems.length > 0
        radius: Tokens.radiusXl
        elevation: 1.3
        implicitHeight: gpCol.implicitHeight + Tokens.space6 * 2
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Tokens.radiusXl - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(root.accent, Theme.isDark ? 0.08 : 0.05) }
                GradientStop { position: 0.5; color: U.withAlpha(root.accent, 0.0) }
            }
        }
        ColumnLayout {
            id: gpCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space6
            spacing: Tokens.space5
            Head {
                glyph: "target"
                title: I18n.tr("Your game plan")
                hint: I18n.tr("The recipe for your next video in this niche, built from what earns views here.")
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.compact ? 1 : (root.wide ? Math.min(5, root.planItems.length) : Math.min(3, root.planItems.length))
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.planItems
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        radius: Tokens.radiusLg
                        color: Theme.surface_low
                        border.width: 1
                        border.color: Theme.border
                        implicitHeight: gcCol.implicitHeight + Tokens.space4 * 2
                        ColumnLayout {
                            id: gcCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            spacing: Tokens.space2
                            RowLayout {
                                spacing: 6
                                C.IconGlyph { name: modelData.g; size: 15; glyphColor: root.accent }
                                C.AppText {
                                    text: modelData.l
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontMicro + 1
                                    font.letterSpacing: 1.2
                                    color: root.accent
                                }
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.v
                                font.pixelSize: Tokens.fontBody + 1
                                lineHeight: 1.3
                                color: Theme.text_strong
                                wrapMode: Text.WordWrap
                                selectable: true
                            }
                        }
                    }
                }
            }
        }
    }

    // ══ VIDEO IDEAS ══
    C.GlassPanel {
        Layout.fillWidth: true
        visible: root.ideas.length > 0
        radius: Tokens.radiusXl
        implicitHeight: viCol.implicitHeight + Tokens.space6 * 2
        ColumnLayout {
            id: viCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space6
            spacing: Tokens.space4
            Head {
                glyph: "lightbulb"
                tint: Theme.warn
                title: I18n.tr("Videos you could film this week")
                hint: I18n.tr("Each one rests on a number from this search. Click a title to copy it.")
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.compact ? 1 : (root.wide ? 3 : 2)
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                Repeater {
                    model: root.ideas
                    Rectangle {
                        id: vc
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        radius: Tokens.radiusLg
                        color: vcHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
                        border.width: 1
                        border.color: vcHover.hovered ? U.withAlpha(Theme.warn, 0.45) : Theme.border
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        implicitHeight: vcCol.implicitHeight + Tokens.space4 * 2
                        HoverHandler { id: vcHover }
                        ColumnLayout {
                            id: vcCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            spacing: Tokens.space2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                C.AppText {
                                    text: (vc.index < 9 ? "0" : "") + (vc.index + 1)
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.warn
                                }
                                Item { Layout.fillWidth: true }
                                Tag { text: vc.modelData.format || ""; tint: Theme.tertiary }
                                Tag { text: vc.modelData.effort || ""; tint: root.effortTint(vc.modelData.effort) }
                            }
                            AbstractButton {
                                id: tBtn
                                Layout.fillWidth: true
                                implicitHeight: tTxt.implicitHeight
                                onClicked: root.copyRequested(vc.modelData.title || "")
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Item {}
                                contentItem: C.AppText {
                                    id: tTxt
                                    text: vc.modelData.title || ""
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontLabel + 1
                                    lineHeight: 1.2
                                    color: tBtn.hovered ? Theme.primary : Theme.text_strong
                                    wrapMode: Text.WordWrap
                                }
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: vc.modelData.angle || ""
                                font.pixelSize: Tokens.fontBody
                                color: Theme.on_surface
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: (vc.modelData.why || "") !== ""
                                spacing: 6
                                C.IconGlyph { name: "bar_chart"; size: 13; glyphColor: Theme.outline; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: vc.modelData.why || ""
                                    font.pixelSize: Tokens.fontCaption + 1
                                    color: Theme.on_surface_var
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ══ TITLE FORMULAS + AVOID ══
    GridLayout {
        Layout.fillWidth: true
        visible: root.formulas.length > 0 || root.avoid.length > 0
        columns: root.compact ? 1 : 2
        columnSpacing: Tokens.space5
        rowSpacing: Tokens.space5

        C.GlassPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            visible: root.formulas.length > 0
            radius: Tokens.radiusXl
            implicitHeight: tfCol.implicitHeight + Tokens.space6 * 2
            ColumnLayout {
                id: tfCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.space6
                spacing: Tokens.space4
                Head {
                    glyph: "text"
                    tint: root.good
                    title: I18n.tr("Title formulas that work here")
                }
                Repeater {
                    model: root.formulas
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.space1
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.pattern || ""
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody + 1
                                color: Theme.text_strong
                                wrapMode: Text.WordWrap
                            }
                            C.IconButton {
                                iconName: "content_copy"
                                tip: I18n.tr("Copy")
                                implicitWidth: 28; implicitHeight: 28
                                glyphSize: 14
                                onClicked: root.copyRequested(modelData.pattern || "")
                            }
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            visible: (modelData.example || "") !== ""
                            text: "“" + (modelData.example || "") + "”"
                            font.pixelSize: Tokens.fontBody
                            font.italic: true
                            color: root.good
                            wrapMode: Text.WordWrap
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: modelData.why || ""
                            font.pixelSize: Tokens.fontCaption + 1
                            color: Theme.on_surface_var
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        C.GlassPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            visible: root.avoid.length > 0
            radius: Tokens.radiusXl
            implicitHeight: avCol.implicitHeight + Tokens.space6 * 2
            ColumnLayout {
                id: avCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.space6
                spacing: Tokens.space4
                Head {
                    glyph: "warning"
                    tint: root.bad
                    title: I18n.tr("Don't do this here")
                }
                Repeater {
                    model: root.avoid
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.space3
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 3
                            implicitWidth: 18; implicitHeight: 18; radius: 9
                            color: U.withAlpha(root.bad, 0.16)
                            C.IconGlyph { anchors.centerIn: parent; name: "close"; size: 11; glyphColor: root.bad }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.what || ""
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody + 1
                                color: Theme.text_strong
                                wrapMode: Text.WordWrap
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: modelData.why || ""
                                font.pixelSize: Tokens.fontCaption + 1
                                color: Theme.on_surface_var
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    // ══ COMPETITION + KEYWORDS ══
    C.GlassPanel {
        Layout.fillWidth: true
        visible: root.levelIndex(root.comp.level) > 0 || root.keywords.length > 0
        radius: Tokens.radiusXl
        implicitHeight: ckGrid.implicitHeight + Tokens.space6 * 2
        GridLayout {
            id: ckGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space6
            columns: root.compact ? 1 : 2
            columnSpacing: Tokens.space6
            rowSpacing: Tokens.space5

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                visible: root.levelIndex(root.comp.level) > 0
                spacing: Tokens.space3
                readonly property int lv: root.levelIndex(root.comp.level)
                readonly property color lvTint: lv === 1 ? root.good : lv === 2 ? Theme.warn : Theme.error
                Head { glyph: "chart"; tint: parent.lvTint; title: root.levelText(root.comp.level) }
                Row {
                    id: meter
                    spacing: 4
                    readonly property int lv: parent.lv
                    readonly property color tint: parent.lvTint
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: 46; height: 8; radius: 4
                            color: index < meter.lv ? meter.tint : U.withAlpha(Theme.outline, 0.2)
                        }
                    }
                }
                C.AppText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.comp.why || ""
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: (root.comp.edge || "") !== ""
                    spacing: Tokens.space2
                    C.IconGlyph { name: "sparkling"; size: 15; glyphColor: root.accent; Layout.alignment: Qt.AlignTop; Layout.topMargin: 2 }
                    C.AppText {
                        Layout.fillWidth: true
                        text: I18n.tr("Your edge: ") + (root.comp.edge || "")
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontBody
                        color: Theme.text_strong
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                visible: root.keywords.length > 0
                spacing: Tokens.space3
                Head {
                    glyph: "search"
                    title: I18n.tr("Keywords people search")
                    hint: I18n.tr("Click one to copy it.")
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    Repeater {
                        model: root.keywords
                        AbstractButton {
                            id: kw
                            required property var modelData
                            implicitHeight: 32
                            implicitWidth: kwTxt.implicitWidth + Tokens.space4 * 2
                            hoverEnabled: true
                            onClicked: root.copyRequested(modelData)
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            background: Rectangle {
                                radius: Tokens.radiusPill
                                color: kw.hovered ? U.withAlpha(root.accent, 0.14) : Theme.surface_low
                                border.width: 1
                                border.color: kw.hovered ? U.withAlpha(root.accent, 0.5) : Theme.border
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                            contentItem: C.AppText {
                                id: kwTxt
                                text: kw.modelData
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Tokens.fontCaption + 1
                                weight: Tokens.weightMedium
                                color: kw.hovered ? Theme.primary : Theme.on_surface
                            }
                        }
                    }
                }
            }
        }
    }
}
