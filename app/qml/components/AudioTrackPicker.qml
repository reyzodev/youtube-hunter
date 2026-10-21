import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.2 — Audio track picker ("Voice Deck").
//
// Dubbed YouTube videos ship one audio stream per language: the original plus
// creator dubs and YouTube's own AI auto-dubs. This lets the user say which
// voice the clip / download should carry. One component, two homes:
//   * Video Cutter inspector  (columns: 1-2, header off: the card has one)
//   * Download quality picker (columns: 3, header on)
//
//   ┌──────────────────────────┐ ┌──────────────────────────┐
//   │ [EN]  English    ORIGINAL│ │ [AR]  Arabic           DUB│
//   │       English · US  ▌▌▌▌ │ │       Arabic · 128 kbps   │
//   └──────────────────────────┘ └──────────────────────────┘
//
// The picked card "speaks": a four-bar voice meter breathes beside it (only
// while ambient motion is on and the window is active). Original is always
// first and is the default; AI dubs wear their own tint so nobody mistakes a
// synthetic voice for a human one. Long lists (auto-dubs can be 20+) fold to
// `maxCollapsed` cards with a "show all" toggle; the picked one is always
// kept in view.
//
// tracks: [{ key, lang, code, name, native, nameFa, kind, kbps, rtl }]
//         key "" = original · kind "original" | "dub" | "auto"
Item {
    id: root

    property var tracks: []
    property string current: ""
    property int columns: 2
    property int maxCollapsed: 6
    property bool showHeader: true
    property bool locked: false
    signal picked(string key)

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    readonly property int _n: tracks ? tracks.length : 0
    readonly property bool _collapsible: _n > maxCollapsed
    property bool _expanded: false
    readonly property int _curIdx: {
        for (var i = 0; i < _n; ++i)
            if ((tracks[i].key || "") === current) return i
        return 0
    }
    // what is drawn: all, or the first few with the picked one kept in view
    readonly property var _shown: {
        if (!_collapsible || _expanded) return tracks || []
        var out = tracks.slice(0, maxCollapsed)
        if (_curIdx >= maxCollapsed) out[maxCollapsed - 1] = tracks[_curIdx]
        return out
    }
    readonly property var _cur: _n > 0 ? tracks[_curIdx] : null

    function kindTint(kind) {
        return kind === "original" ? Theme.secondary_container
             : kind === "auto" ? Theme.tertiary
             : Theme.primary
    }
    function kindLabel(kind) {
        return kind === "original" ? I18n.tr("Original")
             : kind === "auto" ? I18n.tr("AI dub")
             : I18n.tr("Dub")
    }
    function localName(t) {
        if (!t) return ""
        return I18n.lang === "fa" ? (t.nameFa || t.name || "") : (t.name || "")
    }

    onTracksChanged: _expanded = false

    implicitWidth: 320
    implicitHeight: col.implicitHeight
    visible: _n > 1

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Tokens.space3

        // ── header (download picker) ──
        RowLayout {
            Layout.fillWidth: true
            visible: root.showHeader
            spacing: Tokens.space2
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 9
                color: U.withAlpha(Theme.primary, Theme.isDark ? 0.18 : 0.11)
                border.width: 1
                border.color: U.withAlpha(Theme.primary, 0.30)
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: "translate"; size: 14
                    glyphColor: Theme.primary
                }
            }
            C.AppText {
                text: I18n.tr("Audio track")
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontBody
                color: Theme.text_strong
            }
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: cntTxt.implicitWidth + 14
                radius: 10
                color: U.withAlpha(Theme.on_surface_var, 0.12)
                C.AppText {
                    id: cntTxt
                    anchors.centerIn: parent
                    text: I18n.tr("{n} languages").replace("{n}", root._n)
                    font.pixelSize: Tokens.fontMicro
                    weight: Tokens.weightBold
                    color: Theme.on_surface_var
                }
            }
            C.AppText {
                Layout.fillWidth: true
                text: root._cur ? (root._cur.kind === "original"
                                   ? I18n.tr("Original voice of the video")
                                   : I18n.tr("Dubbed in {l}").replace("{l}", root.localName(root._cur)))
                                : ""
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        // ── the deck ──
        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1, root.columns)
            columnSpacing: Tokens.space2
            rowSpacing: Tokens.space2

            Repeater {
                model: root._shown

                AbstractButton {
                    id: card
                    readonly property var t: modelData
                    readonly property string key: (t && t.key) ? t.key : ""
                    readonly property bool on: key === root.current
                    readonly property color tint: root.kindTint(t ? t.kind : "")
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 62
                    hoverEnabled: true
                    enabled: !root.locked
                    opacity: enabled || on ? 1 : 0.5
                    padding: 0
                    onClicked: if (!on) root.picked(key)
                    HoverHandler { cursorShape: card.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    scale: pressed ? 0.98 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                    C.AppTooltip {
                        visible: card.hovered && card.t && card.t.kind === "auto"
                        text: I18n.tr("Generated by YouTube with an AI voice")
                    }

                    background: Rectangle {
                        radius: Tokens.radiusLg
                        color: card.on ? U.withAlpha(Theme.primary, Theme.isDark ? 0.15 : 0.08)
                             : card.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                             : Theme.surface_low
                        border.width: card.on ? 2 : 1
                        border.color: card.on ? Theme.primary
                                    : card.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        // a wash of light from the reading edge on the picked card
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.radius - 2
                            opacity: card.on ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, I18n.rtl ? 0.0 : (Theme.isDark ? 0.16 : 0.10)) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, I18n.rtl ? (Theme.isDark ? 0.16 : 0.10) : 0.0) }
                            }
                        }
                    }

                    contentItem: Item {
                        // language code tile
                        Rectangle {
                            id: tile
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38; height: 38
                            radius: 12
                            color: card.on ? Theme.primary : U.withAlpha(card.tint, Theme.isDark ? 0.16 : 0.10)
                            border.width: card.on ? 0 : 1
                            border.color: U.withAlpha(card.tint, 0.30)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                            // sheen on the lit key
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                visible: card.on
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                                    GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.0) }
                                }
                            }
                            C.AppText {
                                anchors.centerIn: parent
                                text: card.t ? (card.t.code || "?") : ""
                                mono: true
                                weight: Tokens.weightExtraBold
                                font.pixelSize: 13
                                font.letterSpacing: 0.5
                                color: card.on ? Theme.on_primary : card.tint
                                LayoutMirroring.enabled: false
                            }
                        }

                        // badge + voice meter (trailing edge)
                        Column {
                            id: trail
                            anchors.right: parent.right
                            anchors.rightMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Rectangle {
                                anchors.right: parent.right
                                height: 18
                                radius: 9
                                width: badgeTxt.implicitWidth + 12
                                color: U.withAlpha(card.tint, Theme.isDark ? 0.18 : 0.12)
                                border.width: 1
                                border.color: U.withAlpha(card.tint, 0.32)
                                C.AppText {
                                    id: badgeTxt
                                    anchors.centerIn: parent
                                    text: card.t ? root.kindLabel(card.t.kind) : ""
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontMicro
                                    font.capitalization: I18n.lang === "fa" ? Font.MixedCase : Font.AllUppercase
                                    font.letterSpacing: I18n.lang === "fa" ? 0 : 0.8
                                    color: Theme.isDark ? card.tint : U.mix(card.tint, Theme.text_strong, 0.25)
                                }
                            }
                            // four bars that "speak" while picked
                            Row {
                                anchors.right: parent.right
                                height: 12
                                spacing: 2
                                opacity: card.on ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                LayoutMirroring.enabled: false
                                Repeater {
                                    model: [ { lo: 3, hi: 11, d: 460 }, { lo: 5, hi: 8, d: 340 },
                                             { lo: 2, hi: 12, d: 560 }, { lo: 4, hi: 9, d: 410 } ]
                                    Rectangle {
                                        id: bar
                                        required property var modelData
                                        width: 3
                                        radius: 1.5
                                        anchors.bottom: parent.bottom
                                        height: bar.modelData.hi * 0.7
                                        color: Theme.primary
                                        SequentialAnimation on height {
                                            running: card.on && root._motion && Tokens.appActive && root.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { to: bar.modelData.hi; duration: bar.modelData.d; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: bar.modelData.lo; duration: bar.modelData.d; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }
                            }
                        }

                        // names
                        Column {
                            anchors.left: tile.right
                            anchors.leftMargin: 11
                            anchors.right: trail.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            C.AppText {
                                width: parent.width
                                text: card.t ? (card.t.native || card.t.name || "") : ""
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: card.on ? Theme.text_strong : Theme.on_surface
                                elide: Text.ElideRight
                            }
                            C.AppText {
                                width: parent.width
                                text: {
                                    if (!card.t) return ""
                                    var nm = root.localName(card.t)
                                    var parts = []
                                    if (nm !== "" && nm !== card.t.native) parts.push(nm)
                                    if (card.t.kbps > 0) parts.push(card.t.kbps + " kbps")
                                    return parts.join(" · ")
                                }
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // ── fold / unfold ──
        AbstractButton {
            id: moreBtn
            Layout.alignment: Qt.AlignHCenter
            visible: root._collapsible
            implicitHeight: 30
            implicitWidth: moreRow.implicitWidth + 24
            hoverEnabled: true
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            onClicked: root._expanded = !root._expanded
            background: Rectangle {
                radius: 15
                color: moreBtn.hovered ? U.withAlpha(Theme.primary, 0.10) : U.withAlpha(Theme.primary, 0)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
            contentItem: Item {
                Row {
                    id: moreRow
                    anchors.centerIn: parent
                    spacing: 6
                    C.AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._expanded ? I18n.tr("Show fewer")
                                             : I18n.tr("Show all {n} languages").replace("{n}", root._n)
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.primary
                    }
                    C.IconGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root._expanded ? "expand_less" : "expand_more"
                        size: 14
                        glyphColor: Theme.primary
                    }
                }
            }
        }
    }
}
