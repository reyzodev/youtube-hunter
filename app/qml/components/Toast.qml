import QtQuick
import NicheScope
import "../Utils.js" as U

// v16 "Signal toast".
//
// Same public API as before: `show(text, kind)` with kind
// "success" | "error" | "info" | "download" | "warn". Pages position it with
// x / y / anchors.horizontalCenter exactly as they did, nothing else changes.
//
// What is new:
//  * a glass card with a tone wash bleeding in from the leading edge, a soft
//    9-slice drop shadow and a tone-tinted hairline (no hard neon outline);
//  * an icon "chip" that pops in on a spring with a pulse ring behind it;
//  * a two-line layout: a small tone-coloured kind label above the message;
//  * a countdown line along the bottom edge that shows how long it stays;
//  * hover PAUSES the countdown (the toast never vanishes under the pointer)
//    and reveals a close button; click anywhere dismisses it;
//  * a repeat of the same message while visible bumps a ×N counter and
//    restarts the timer instead of flashing the card out and in again;
//  * errors stay longer (5 s) than confirmations (2.8 s).
Item {
    id: root

    property string kind: "info"
    property string text: ""
    property int repeatCount: 1
    readonly property int holdMs: kind === "error" ? 5000
                                : kind === "warn" ? 4000 : 2800

    readonly property color tone: kind === "error" ? Theme.error
                                : kind === "success" ? Theme.secondary_container
                                : kind === "warn" ? Theme.warn
                                : Theme.primary
    readonly property string iconName: kind === "error" ? "error"
                                     : kind === "success" ? "check_circle"
                                     : kind === "warn" ? "warning"
                                     : kind === "download" ? "download" : "info"
    readonly property string kindLabel: kind === "error" ? I18n.tr("Something went wrong")
                                      : kind === "success" ? I18n.tr("Done")
                                      : kind === "warn" ? I18n.tr("Heads up")
                                      : kind === "download" ? I18n.tr("Download")
                                      : I18n.tr("Note")

    readonly property int _maxW: 460
    width: Math.min(_maxW, Math.max(260, content.implicitWidth + 14 + 14 + closeSlot.width))
    height: 60
    opacity: 0
    visible: opacity > 0
    z: 1000

    // ── shadow ──
    BorderImage {
        z: -1
        source: "shadow_soft.png"
        border { left: 64; right: 64; top: 64; bottom: 64 }
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
        anchors.fill: card
        anchors.margins: -52
        anchors.topMargin: -44
        anchors.bottomMargin: -60
        opacity: Theme.isDark ? 0.55 : 0.14
        smooth: true
        cache: true
    }

    // ── card ──
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        antialiasing: true
        clip: true
        color: Theme.isDark ? U.mix(Theme.surface_highest, Theme.background, 0.25)
                            : Theme.panel_bg
        border.width: 1
        border.color: U.mix(Theme.border, root.tone, hover.hovered ? 0.55 : 0.32)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

        // tone wash from the reading edge
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(root.tone, Theme.isDark ? 0.20 : 0.10) }
                GradientStop { position: 0.45; color: U.withAlpha(root.tone, 0.0) }
            }
            LayoutMirroring.enabled: false
            rotation: I18n.rtl ? 180 : 0
        }

        // specular top edge
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 32
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                GradientStop { position: 0.5; color: Theme.glass_hi }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
            }
        }

        // countdown line
        Rectangle {
            id: track
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            // stay between the 16 px corners, pill-ended, inside the border
            anchors.leftMargin: card.radius
            anchors.rightMargin: card.radius
            anchors.bottomMargin: 1
            height: 2
            radius: 1
            color: U.withAlpha(root.tone, 0.12)
            Rectangle {
                id: bar
                property real progress: 1.0
                anchors.left: parent.left
                height: parent.height
                width: parent.width * progress
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(root.tone, 0.35) }
                    GradientStop { position: 1.0; color: root.tone }
                }
            }
        }
    }

    // ── content ──
    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 14
        spacing: 12

        // icon chip
        Item {
            id: chip
            width: 34; height: 34
            anchors.verticalCenter: parent.verticalCenter
            scale: 0.4

            Rectangle {      // pulse ring
                id: ring
                anchors.centerIn: parent
                width: parent.width; height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: root.tone
                opacity: 0
            }
            Rectangle {
                anchors.fill: parent
                radius: 11
                color: U.withAlpha(root.tone, Theme.isDark ? 0.18 : 0.12)
                border.width: 1
                border.color: U.withAlpha(root.tone, 0.35)
                antialiasing: true
            }
            IconGlyph {
                anchors.centerIn: parent
                name: root.iconName
                fill: true
                size: 18
                glyphColor: root.tone
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Row {
                spacing: 6
                AppText {
                    text: root.kindLabel
                    font.pixelSize: Tokens.fontMicro
                    weight: Tokens.weightBold
                    color: root.tone
                    font.letterSpacing: I18n.rtl ? 0 : 0.4
                }
                Rectangle {
                    visible: root.repeatCount > 1
                    anchors.verticalCenter: parent.verticalCenter
                    height: 15; radius: 7.5
                    width: cnt.implicitWidth + 10
                    color: U.withAlpha(root.tone, 0.16)
                    AppText {
                        id: cnt
                        anchors.centerIn: parent
                        text: "×" + root.repeatCount
                        font.pixelSize: 10
                        weight: Tokens.weightBold
                        color: root.tone
                    }
                }
            }
            AppText {
                id: label
                text: root.text
                color: Theme.text_strong
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontBody - 1
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root._maxW - 14 - 34 - 12 - 14 - closeSlot.width)
            }
        }
    }

    // close (appears on hover)
    Item {
        id: closeSlot
        width: 34
        height: parent.height
        anchors.right: parent.right
        anchors.rightMargin: 6
        Rectangle {
            anchors.centerIn: parent
            width: 26; height: 26; radius: 8
            color: closeHover.hovered ? Theme.hover_bg_strong : "transparent"
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
            IconGlyph {
                anchors.centerIn: parent
                name: "close"
                size: 15
                glyphColor: Theme.on_surface_var
            }
            HoverHandler { id: closeHover }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (!root.visible) return
            if (hovered) countdown.pause()
            else countdown.resume()
        }
    }
    TapHandler { onTapped: root.dismiss() }

    // ── motion ──
    transform: [
        Translate { id: shift; y: 0 },
        Scale { id: zoom; origin.x: root.width / 2; origin.y: root.height; xScale: 1; yScale: 1 }
    ]

    ParallelAnimation {
        id: enter
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        NumberAnimation { target: shift; property: "y"; from: 22; to: 0; duration: Tokens.durSlow + 80; easing.type: Easing.OutExpo }
        NumberAnimation { target: zoom; properties: "xScale,yScale"; from: 0.94; to: 1; duration: Tokens.durSlow + 80; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 70 }
            NumberAnimation { target: chip; property: "scale"; from: 0.4; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 160 }
            ParallelAnimation {
                NumberAnimation { target: ring; property: "opacity"; from: 0.55; to: 0; duration: 700; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.9; duration: 700; easing.type: Easing.OutCubic }
            }
        }
    }

    // a "nudge" when the same message arrives again
    SequentialAnimation {
        id: bump
        NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 1.035; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
    }

    NumberAnimation {
        id: countdown
        target: bar; property: "progress"
        from: 1; to: 0
        duration: root.holdMs
        onFinished: if (bar.progress <= 0.001) root.dismiss()
    }

    ParallelAnimation {
        id: leave
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Tokens.durMed; easing.type: Easing.InCubic }
        NumberAnimation { target: shift; property: "y"; to: 10; duration: Tokens.durMed; easing.type: Easing.InCubic }
        NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 0.97; duration: Tokens.durMed; easing.type: Easing.InCubic }
    }

    function show(text, kind) {
        var k = kind || "info"
        leave.stop()
        if (root.visible && root.opacity > 0.5 && text === root.text && k === root.kind) {
            root.repeatCount += 1
            bump.restart()
        } else {
            root.repeatCount = 1
            root.kind = k
            root.text = text
            enter.restart()
        }
        countdown.stop()
        bar.progress = 1
        countdown.start()
        if (hover.hovered) countdown.pause()
    }

    function dismiss() {
        countdown.stop()
        enter.stop()
        leave.restart()
    }
}
