import QtQuick
import NicheScope
import "../Utils.js" as U

// v11 — a small live bar chart used as the "instrument" of a working page:
// the Channel report studio, the Monetization scanner.
//
//   idle — a still, ascending skyline (a channel growing), barely breathing
//   busy — every bar bounces on its own period, like a level meter reading
//          a signal; the page is visibly working
//   done — the skyline locks into a clean ascending chart in the success tint
//
// Each bar animates only its own height (a plain Rectangle, no layers), and
// all loops stop when the app is in the background.
Item {
    id: root
    property string mode: "idle"          // "idle" | "busy" | "done"
    property color accent: Theme.primary
    property color doneColor: Theme.secondary_container
    property int bars: 14
    property real gap: 5
    property real barRadius: 3

    implicitWidth: 220
    implicitHeight: 72

    readonly property real _bw: Math.max(2, (width - gap * (bars - 1)) / bars)
    readonly property color _tint: mode === "done" ? doneColor : accent

    Row {
        anchors.bottom: parent.bottom
        height: root.height
        spacing: root.gap
        Repeater {
            model: root.bars
            Rectangle {
                id: bar
                readonly property real rest: 0.22 + 0.70 * (index / Math.max(1, root.bars - 1))
                                             + (index % 3 === 1 ? -0.10 : 0)
                property real k: rest
                width: root._bw
                height: Math.max(4, root.height * Math.max(0.08, Math.min(1, k)))
                anchors.bottom: parent.bottom
                radius: root.barRadius
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root._tint }
                    GradientStop { position: 1.0; color: U.withAlpha(root._tint, root.mode === "idle" ? 0.18 : 0.35) }
                }
                opacity: root.mode === "idle" ? 0.55 : 1.0
                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                // the reset back to the skyline eases (animations themselves
                // bypass this Behavior, so it only shapes the settle)
                Behavior on k { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

                SequentialAnimation {
                    running: root.mode === "busy" && root.visible && Tokens.appActive
                    loops: Animation.Infinite
                    onStopped: bar.k = bar.rest
                    NumberAnimation { target: bar; property: "k"; to: 0.25 + ((index * 37) % 60) / 100; duration: 380 + (index * 53) % 420; easing.type: Easing.InOutSine }
                    NumberAnimation { target: bar; property: "k"; to: 0.85 - ((index * 29) % 40) / 100; duration: 340 + (index * 71) % 380; easing.type: Easing.InOutSine }
                }
                SequentialAnimation {
                    running: root.mode === "idle" && root.visible && Tokens.appActive
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 140 }
                    NumberAnimation { target: bar; property: "k"; to: bar.rest + 0.06; duration: 1600; easing.type: Easing.InOutSine }
                    NumberAnimation { target: bar; property: "k"; to: bar.rest; duration: 1600; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
