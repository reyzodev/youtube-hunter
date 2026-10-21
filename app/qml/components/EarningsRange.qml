import QtQuick
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// The headline the Monetize Checker leads its money panel with:
//
//      $644 - $10K            $5.2K - $83K
//      Monthly Estimated      Yearly Estimated
//
// A range, never a single number — see EARNINGS RANGE in app.core.rpm for
// what the floor and the ceiling each account for. Under each range sits a
// log-scale band with the "Likely" figure (the middle tier card) marked on
// it, so the two views of the money stay visibly the same model.
//
// The figures count up from zero when the panel arrives (the loader's slot
// reels stopping), then land on the VM's own strings, so what's left on
// screen is exactly what the backend formatted.
Item {
    id: root

    // MonetizeVM.result.earnings.{monthly,yearly}: {low, mid, high, lowText, midText, highText}
    property var monthly: ({})
    property var yearly: ({})
    property int startDelay: 900

    implicitHeight: row.implicitHeight

    property real t: 0
    Component.onCompleted: countUp.start()
    SequentialAnimation {
        id: countUp
        PauseAnimation { duration: root.startDelay }
        NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: 1500; easing.type: Easing.OutExpo }
    }

    // JS twin of app.core.rpm.money_compact — only used mid-count; the final
    // frame shows the VM's own text.
    function money(v) {
        v = Math.max(0, v || 0)
        if (v < 10) return "$" + v.toFixed(2)
        if (Math.round(v) < 1000) return "$" + Math.round(v)
        var k = v / 1000
        if (Math.round(k * 10) / 10 < 10) return "$" + (Math.round(k * 10) / 10) + "K"
        if (Math.round(k) < 1000) return "$" + Math.round(k) + "K"
        var m = v / 1e6
        if (Math.round(m * 10) / 10 < 10) return "$" + (Math.round(m * 10) / 10) + "M"
        return "$" + Math.round(m) + "M"
    }
    function rangeText(span) {
        if (!span || span.low === undefined) return "-"
        if (root.t >= 0.999) return span.lowText + " - " + span.highText
        return money(span.low * root.t) + " - " + money(span.high * root.t)
    }
    // where `mid` sits between low and high, on a log scale (the range spans
    // an order of magnitude; a linear band would pin "Likely" to the left edge)
    function logPos(span) {
        if (!span || !(span.low > 0) || !(span.high > span.low)) return 0.5
        var p = Math.log(span.mid / span.low) / Math.log(span.high / span.low)
        return Math.max(0.04, Math.min(0.96, p))
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.space3

        Repeater {
            model: [
                { span: root.monthly, label: I18n.tr("Monthly Estimated Earnings"), lead: true },
                { span: root.yearly,  label: I18n.tr("Yearly Estimated Earnings"),  lead: false }
            ]
            Rectangle {
                id: card
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: cardCol.implicitHeight + Tokens.space5 * 2
                radius: Tokens.radiusLg
                color: card.modelData.lead ? U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.06) : Theme.surface_low
                border.width: 1
                border.color: card.modelData.lead ? U.withAlpha(Theme.primary, 0.45) : Theme.border

                // the arrival: rise + fade, second card a beat later
                opacity: 0
                transform: Translate { id: cardShift; y: 14 }
                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: root.startDelay - 200 + card.index * 120 }
                    ParallelAnimation {
                        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 420; easing.type: Easing.OutCubic }
                        NumberAnimation { target: cardShift; property: "y"; to: 0; duration: 520; easing.type: Easing.OutBack }
                    }
                }

                ColumnLayout {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.space5
                    spacing: Tokens.space2

                    C.AppText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.rangeText(card.modelData.span)
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontDisplay + 12
                        color: Theme.text_strong
                        LayoutMirroring.enabled: false
                    }
                    C.AppText {
                        Layout.alignment: Qt.AlignHCenter
                        text: card.modelData.label
                        font.pixelSize: Tokens.fontBody
                        color: Theme.on_surface_var
                    }

                    // low ─────●───── high, with the likely figure on it
                    Item {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.space2
                        implicitHeight: 34
                        LayoutMirroring.enabled: false
                        LayoutMirroring.childrenInherit: true
                        Rectangle {
                            id: band
                            anchors.left: parent.left
                            anchors.right: parent.right
                            y: 4
                            height: 6; radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.18) }
                                GradientStop { position: 0.5; color: U.withAlpha(Theme.primary, 0.75) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.secondary_container, 0.55) }
                            }
                        }
                        Rectangle {
                            id: pin
                            x: band.width * root.logPos(card.modelData.span) * root.t - width / 2
                            anchors.verticalCenter: band.verticalCenter
                            width: 14; height: 14; radius: 7
                            color: Theme.panel_bg
                            border.width: 3
                            border.color: Theme.primary
                        }
                        C.AppText {
                            readonly property real want: pin.x + pin.width / 2 - implicitWidth / 2
                            x: Math.max(0, Math.min(parent.width - implicitWidth, want))
                            anchors.top: band.bottom
                            anchors.topMargin: Tokens.space2
                            opacity: root.t
                            text: I18n.tr("likely {v}").replace("{v}", (card.modelData.span && card.modelData.span.midText) || "")
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontMicro
                            color: Theme.primary
                        }
                    }
                }
            }
        }
    }
}
