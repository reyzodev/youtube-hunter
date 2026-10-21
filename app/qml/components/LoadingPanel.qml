import QtQuick
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// The panel a long-running search puts in place of its results.
//
// v3.39 "Hunt" redesign. The v3.15 panel answered the right questions (how far
// along, is it stuck, what has it found) but looked like a settings card with a
// progress bar in it. This one is an instrument:
//
//   * HuntScope on the leading edge — the app's mark inside a radar scope. The
//     beam is the "alive" signal, the outer ring is the real percentage, one
//     contact appears per ~12 videos actually found, and the viewfinder
//     brackets close in as the run nears done.
//   * the QUERY is the headline, at display size, under a live "Hunting" tag —
//     it is the one thing on screen the user typed.
//   * the stages are a segmented track: finished segments full, the running one
//     filling from its own slice of the percentage, the rest empty. Same named
//     steps as before, now readable as a sequence at a glance.
//   * counts are readouts that roll up as they change, not chips.
//
// Still computes nothing about the run: every value is passed in.
Item {
    id: root

    // 0..100, or negative when the backend has nothing measurable to report yet.
    property int pct: -1
    property string title: ""
    // The search text. When set it becomes the headline; `title` is the
    // fallback for callers that only have a sentence.
    property string query: ""
    property string detail: ""
    // [{key, label, state: "done"|"active"|"pending", detail}]
    property var stages: []
    // [{label, value}]
    property var counts: []
    // Candidate videos found so far (drives the scope's contacts).
    property int found: 0
    property string note: ""
    signal stopRequested()
    property bool canStop: true

    implicitHeight: card.implicitHeight

    readonly property bool _narrow: width < 720
    readonly property bool _fa: I18n.lang === "fa"
    readonly property bool _live: visible && Tokens.appActive

    // Each core stage owns a slice of the backend's percentage
    // (app.core.niche.search: discover 0-45, stats 45-75, channels 75-100).
    function _slice(key, i, n) {
        if (key === "discover") return [0, n === 1 ? 100 : 45]
        if (key === "stats") return [45, 75]
        if (key === "channels") return [75, 100]
        return [i * 100 / n, (i + 1) * 100 / n]
    }
    function _fill(st, i, n) {
        if (!st) return 0
        if (st.state === "done") return 1
        if (st.state !== "active") return 0
        if (root.pct < 0) return 0.08
        var s = _slice(st.key, i, n)
        return Math.max(0.04, Math.min(1, (root.pct - s[0]) / Math.max(1, s[1] - s[0])))
    }

    C.GlassPanel {
        id: card
        width: parent.width
        radius_: Tokens.radiusXl
        implicitHeight: body.implicitHeight + Tokens.space5 * 2

        // Accent wash pooled behind the scope, fading across the card — the
        // panel reads as "live" before a single word is read.
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusXl
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.13 : 0.08) }
                GradientStop { position: 0.45; color: U.withAlpha(Theme.primary, 0.025) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
            // pool the wash on the scope's side in right-to-left layouts too
            rotation: I18n.rtl ? 180 : 0
        }
        // A thin scan line drifting across the top edge: ambient, felt more
        // than seen, and it stops the moment the window loses focus.
        Rectangle {
            id: scan
            y: 0
            height: 2
            width: card.width * 0.22
            // kept inside the straight part of the top edge so it never
            // pokes past the rounded corners (the card does not clip — that
            // would cut off its own drop shadow)
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                GradientStop { position: 0.5; color: U.withAlpha(Theme.primary, 0.75) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
            readonly property real _x0: Tokens.radiusXl
            readonly property real _x1: Math.max(_x0, card.width - Tokens.radiusXl - width)
            SequentialAnimation on x {
                running: root._live
                loops: Animation.Infinite
                NumberAnimation { from: scan._x0; to: scan._x1; duration: 3200; easing.type: Easing.InOutSine }
                NumberAnimation { from: scan._x1; to: scan._x0; duration: 3200; easing.type: Easing.InOutSine }
            }
        }

        RowLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space5
            spacing: root._narrow ? Tokens.space4 : Tokens.space6

            C.HuntScope {
                size: root._narrow ? 96 : 132
                pct: root.pct
                found: root.found
                running: root.visible
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2

                // ── tag · percentage · stop ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3

                    Rectangle {
                        implicitWidth: tagRow.implicitWidth + Tokens.space3 * 2
                        implicitHeight: 24
                        radius: Tokens.radiusPill
                        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.11)
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.30)
                        Row {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            Rectangle {
                                width: 7; height: 7; radius: 3.5
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: root._live
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.25; to: 1; duration: 650; easing.type: Easing.InOutSine }
                                }
                            }
                            C.AppText {
                                text: I18n.tr("Hunting")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontMicro
                                font.capitalization: root._fa ? Font.MixedCase : Font.AllUppercase
                                font.letterSpacing: root._fa ? 0 : 1.4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // The percentage, set like a scoreboard number.
                    Row {
                        visible: root.pct >= 0
                        Layout.alignment: Qt.AlignVCenter
                        LayoutMirroring.enabled: false
                        spacing: 2
                        C.AppText {
                            id: pctNum
                            property real shown: Math.max(0, root.pct)
                            Behavior on shown { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                            text: Math.round(shown)
                            mono: true
                            weight: Tokens.weightExtraBold
                            font.pixelSize: root._narrow ? 26 : 32
                            font.letterSpacing: -1
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: "%"
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: root._narrow ? 15 : 17
                            color: Theme.primary
                            anchors.baseline: pctNum.baseline
                        }
                    }

                    C.PrimaryButton {
                        visible: root.canStop
                        variant: "ghost"
                        iconName: "stop_circle"
                        text: I18n.tr("Stop")
                        implicitHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: root.stopRequested()
                    }
                }

                // ── the query, as the headline ──
                C.AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: root.query !== ""
                          ? (root._fa ? "«" + root.query + "»" : "“" + root.query + "”")
                          : root.title
                    weight: Tokens.weightExtraBold
                    font.pixelSize: root.query !== "" ? (root._narrow ? 22 : 28) : Tokens.fontSubtitle
                    font.letterSpacing: root._fa ? 0 : -0.6
                    color: Theme.text_strong
                    elide: Text.ElideRight
                }
                // what the running stage is doing right now
                C.AppText {
                    Layout.fillWidth: true
                    text: root.detail
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                }

                // ── segmented stage track ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space2
                    visible: root.stages && root.stages.length > 0
                    spacing: Tokens.space2

                    Repeater {
                        model: root.stages
                        delegate: ColumnLayout {
                            id: seg
                            required property var modelData
                            required property int index
                            readonly property real frac: root._fill(modelData, index, root.stages.length)
                            readonly property bool active: modelData.state === "active"
                            readonly property bool done: modelData.state === "done"
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: Tokens.space2

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: U.withAlpha(Theme.outline, Theme.isDark ? 0.22 : 0.16)
                                clip: true
                                Rectangle {
                                    height: parent.height
                                    radius: parent.radius
                                    width: parent.width * seg.frac
                                    Behavior on width { NumberAnimation { duration: 460; easing.type: Easing.OutCubic } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, seg.done ? 0.85 : 0.6) }
                                        GradientStop { position: 1.0; color: Theme.primary }
                                    }
                                }
                                // shimmer travelling through the running segment
                                Rectangle {
                                    id: shim
                                    visible: seg.active
                                    width: parent.width * 0.35
                                    height: parent.height
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.28 : 0.55) }
                                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                                    }
                                    NumberAnimation on x {
                                        running: seg.active && root._live
                                        from: -shim.width; to: shim.parent.width
                                        duration: 1400
                                        loops: Animation.Infinite
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                Item {
                                    width: 16; height: 16
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        visible: seg.done
                                        name: "check_circle"; fill: true; size: 15
                                        glyphColor: Theme.primary
                                    }
                                    C.SpinnerGlyph {
                                        anchors.centerIn: parent
                                        visible: seg.active
                                        name: "autorenew"; size: 15
                                        glyphColor: Theme.primary
                                        spinning: seg.active
                                    }
                                    C.AppText {
                                        anchors.centerIn: parent
                                        visible: !seg.done && !seg.active
                                        text: seg.index + 1
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontMicro
                                        color: Theme.outline
                                    }
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    text: seg.modelData.label || ""
                                    font.pixelSize: Tokens.fontCaption
                                    weight: seg.active ? Tokens.weightBold : Tokens.weightMedium
                                    color: seg.active ? Theme.text_strong
                                         : seg.done ? Theme.on_surface : Theme.outline
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // ── readouts + run cost ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space2
                    spacing: Tokens.space5

                    Repeater {
                        model: root.counts
                        delegate: Row {
                            required property var modelData
                            spacing: Tokens.space2
                            C.AppText {
                                id: ro
                                property real target: parseInt(modelData.value || "0") || 0
                                property real shown: 0
                                onTargetChanged: shown = target
                                Component.onCompleted: shown = target
                                Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                text: Math.round(shown).toLocaleString(Qt.locale("en_US"), "f", 0)
                                mono: true
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Tokens.fontLabel
                                color: Theme.primary
                                anchors.baseline: roLbl.baseline
                            }
                            C.AppText {
                                id: roLbl
                                text: modelData.label || ""
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; visible: !root._narrow }
                }

                // what the run costs, why it takes this long
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.note !== ""
                    spacing: Tokens.space2
                    C.IconGlyph {
                        name: "bolt"; size: 13
                        glyphColor: Theme.outline
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        text: root.note
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
