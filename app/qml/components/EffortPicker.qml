import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// EffortPicker — "how hard should the AI think", as a five-step power meter.
//
//   ┌──────┬──────┬──────┬──────┬──────┐
//   │ Auto │ ▂    │ ▂▄   │ ▂▄▆  │ ▂▄▆█ │
//   │      │ Low  │ Med  │ High │ Max  │
//   └──────┴──────┴──────┴──────┴──────┘
//
// One accent pill slides under the chosen step; every step carries a tiny bar
// meter that fills up as the level rises, so the five options read as a
// scale rather than five unrelated words. The hint line below spells out what
// the chosen level trades (speed vs depth).
//
// Used by Settings → AI routing (one per feature) and the AI Chat composer.
//   options: [{ value, label, hint }]  (SettingsVM.effortOptions / Chat.effortOptions)
//   value:   the current level ("auto" | "low" | "medium" | "high" | "max")
//   picked(value) is emitted on a click; the host writes it to its VM.
Item {
    id: root
    property var options: []
    property string value: "auto"
    property bool compact: false
    property bool showHint: true
    signal picked(string value)

    readonly property int _index: {
        for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
        return 0
    }
    readonly property int _segH: compact ? 34 : 44
    readonly property color _tint: _index >= 4 ? Theme.tertiary : Theme.primary

    implicitWidth: compact ? 280 : 420
    implicitHeight: track.height + (hintText.visible ? hintText.implicitHeight + Tokens.space2 : 0)

    Rectangle {
        id: track
        width: parent.width
        height: root._segH
        radius: root.compact ? 11 : 13
        color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.045)
        border.width: 1
        border.color: Theme.border
        LayoutMirroring.enabled: false

        readonly property real segW: root.options.length > 0 ? (width - 6) / root.options.length : width

        // the sliding pill
        Rectangle {
            id: pill
            y: 3
            height: parent.height - 6
            width: track.segW
            x: 3 + track.segW * (I18n.rtl ? (root.options.length - 1 - root._index) : root._index)
            radius: track.radius - 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(root._tint, Theme.isDark ? 0.30 : 0.18) }
                GradientStop { position: 1.0; color: U.withAlpha(root._tint, Theme.isDark ? 0.18 : 0.10) }
            }
            border.width: 1
            border.color: U.withAlpha(root._tint, 0.55)
            Behavior on x { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        }

        Row {
            x: 3; y: 3
            height: parent.height - 6
            layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
            Repeater {
                model: root.options
                delegate: AbstractButton {
                    id: seg
                    readonly property bool on: index === root._index
                    width: track.segW
                    height: parent.height
                    hoverEnabled: true
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: if (!seg.on) root.picked(modelData.value)
                    background: Rectangle {
                        radius: track.radius - 3
                        color: !seg.on && seg.hovered ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(Theme.on_surface, 0)
                    }
                    C.AppTooltip { visible: seg.hovered && root.compact; text: modelData.hint || "" }
                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: root.compact ? 5 : 7
                            // level meter: 0 bars for Auto, 1..4 for Low..Max
                            Item {
                                visible: !root.compact || track.segW >= 64 || index === 0
                                width: index === 0 ? 12 : 14
                                height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                C.IconGlyph {
                                    visible: index === 0
                                    anchors.centerIn: parent
                                    name: "auto_awesome"
                                    size: 12
                                    glyphColor: seg.on ? root._tint : Theme.outline
                                }
                                Repeater {
                                    model: index === 0 ? 0 : 4
                                    Rectangle {
                                        required property int index
                                        readonly property bool lit: index < seg.levelOf
                                        x: index * 3.6
                                        width: 2.4
                                        radius: 1.2
                                        height: 3 + index * 3
                                        y: 12 - height
                                        color: lit ? (seg.on ? root._tint : Theme.on_surface_var)
                                                   : U.withAlpha(Theme.on_surface, 0.16)
                                    }
                                }
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label || ""
                                weight: seg.on ? Tokens.weightBold : Tokens.weightMedium
                                font.pixelSize: root.compact ? Tokens.fontCaption : Tokens.fontCaption + 1
                                color: seg.on ? Theme.text_strong : Theme.on_surface_var
                            }
                        }
                    }
                    readonly property int levelOf: index
                }
            }
        }
    }

    C.AppText {
        id: hintText
        visible: root.showHint && !root.compact
        anchors.top: track.bottom
        anchors.topMargin: Tokens.space2
        width: parent.width
        text: (root.options[root._index] || {}).hint || ""
        font.pixelSize: Tokens.fontCaption
        color: Theme.outline
        wrapMode: Text.WordWrap
    }
}
