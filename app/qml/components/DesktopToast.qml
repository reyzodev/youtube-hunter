import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.40 "Away notice" — one desktop toast, in its OWN top-level window.
//
// Shown by DesktopToastHost in the bottom-right corner of the primary screen
// when a job (scrape, download, cut, blueprint, report, chat answer…) finishes
// while the user is in another app. It is:
//
//   * frameless, always on top, never in the taskbar (Qt.Tool);
//   * NON-ACTIVATING: Qt.WindowDoesNotAcceptFocus + the _q_showWithoutActivating
//     flag DesktopNotify.prepare() sets, so the browser tab the user is typing
//     in keeps the keyboard;
//   * sized exactly to the card plus its shadow, so it never blocks clicks on
//     the desktop around it.
//
// Card anatomy
//   ┌────────────────────────────────────────────┐
//   │ YOUTUBE HUNTER · Downloads · now        ✕ │  identity line
//   │ ┌──────┐  ✓ Download complete  ×2         │
//   │ │ logo │  How I built a 10k/mo channel…   │  title + 2-line message
//   │ └──────┘                                   │
//   │ [ ▶ Open ]  [ ▢ Show in folder ]           │  actions (when useful)
//   │ ━━━━━━━━━━━━━━━━━━━━━━━━──────────         │  time left (pauses on hover)
//   └────────────────────────────────────────────┘
//
// The leading tile is the video thumbnail when there is one (with the brand
// mark as a corner badge), otherwise the brand mark itself, which ASSEMBLES on
// arrival: crown drops in, blades slide, play pops, a sheen crosses it. Only
// this app's notice can arrive that way; that is the signature.
Window {
    id: tw

    // ── set by the host ──
    property var notice: ({})
    property real targetX: 0
    property real targetY: 0
    property bool placed: false       // first placement snaps, later moves glide
    property int repeatCount: 1
    property bool closing: false

    signal finished()                 // exit animation is over — host destroys us

    readonly property int margin: 22  // room for the soft shadow
    readonly property int cardW: 376
    readonly property string kind: notice.kind || "info"
    readonly property bool hasThumb: (notice.thumb || "") !== ""
    readonly property bool hasFile: (notice.path || "") !== ""
    readonly property bool hasFolder: !hasFile && (notice.folder || "") !== ""
    readonly property bool isMedia: /\.(mp4|mkv|webm|mov|avi|m4v|m4a|mp3|wav|opus|ogg|flac)$/i.test(notice.path || "")
    readonly property int page: notice.page !== undefined ? notice.page : -1
    readonly property int holdMs: (kind === "error" || kind === "warn") ? 11000 : 7500

    readonly property color tone: kind === "error" ? Theme.error
                                : kind === "success" ? Theme.secondary_container
                                : kind === "warn" ? Theme.warn
                                : Theme.primary

    flags: (Qt.platform.os === "osx" ? Qt.ToolTip : Qt.Tool)
           | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
           | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    transientParent: null
    color: "#00000000"
    title: "YouTube Hunter"
    visible: false
    width: cardW + margin * 2
    height: card.height + margin * 2
    x: targetX
    y: targetY
    Behavior on y {
        enabled: tw.placed
        NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
    }

    // ── public API (host) ──
    function present() {
        visible = true
        placed = true
        enter.restart()
        countdown.restart()
        if (hover.hovered) countdown.pause()
    }

    function bump(n) {
        // Same kind of job finished again while this card is up: count it,
        // show the latest details, restart the clock instead of stacking a twin.
        notice = n
        repeatCount += 1
        bumpAnim.restart()
        countdown.stop()
        bar.progress = 1
        countdown.start()
        if (hover.hovered) countdown.pause()
    }

    function dismiss() {
        if (closing) return
        closing = true
        countdown.stop()
        enter.stop()
        leave.restart()
    }

    function _open() {
        DesktopNotify.activate(tw.page)
        dismiss()
    }

    // ── content ──
    Item {
        id: root
        anchors.fill: parent
        opacity: 0
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        transform: [
            Translate { id: slide; x: 64 },
            Scale {
                id: zoom
                origin.x: root.width
                origin.y: root.height / 2
                xScale: 0.96; yScale: 0.96
            }
        ]

        // soft drop shadow (same 9-slice the in-app toast uses)
        BorderImage {
            source: "shadow_soft.png"
            border { left: 64; right: 64; top: 64; bottom: 64 }
            horizontalTileMode: BorderImage.Stretch
            verticalTileMode: BorderImage.Stretch
            anchors.fill: card
            anchors.margins: -tw.margin
            anchors.topMargin: -tw.margin + 6
            anchors.bottomMargin: -tw.margin
            opacity: Theme.isDark ? 0.9 : 0.32
            smooth: true
            cache: true
        }

        Rectangle {
            id: card
            x: tw.margin
            y: tw.margin
            width: tw.cardW
            height: body.implicitHeight + 32
            radius: 18
            antialiasing: true
            color: Theme.isDark ? U.mix(Theme.surface_highest, Theme.background, 0.18)
                                : Theme.panel_bg
            border.width: 1
            border.color: U.mix(Theme.border, tw.tone, hover.hovered ? 0.5 : 0.24)
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

            // tone wash breathing in from the top-leading corner
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(tw.tone, Theme.isDark ? 0.13 : 0.07) }
                    GradientStop { position: 0.55; color: U.withAlpha(tw.tone, 0.0) }
                }
            }

            // specular top edge
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 36
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                    GradientStop { position: 0.5; color: Theme.glass_hi }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                }
            }

            // arrival streak: a sliver of the tone light running along the top edge once
            Item {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: card.radius
                anchors.rightMargin: card.radius
                height: 2
                clip: true
                LayoutMirroring.enabled: false
                Rectangle {
                    id: streak
                    property real t: 0
                    width: 140
                    height: 2
                    radius: 1
                    x: -width + (parent.width + width) * t
                    opacity: t > 0 && t < 1 ? 1 : 0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(tw.tone, 0.0) }
                        GradientStop { position: 0.7; color: tw.tone }
                        GradientStop { position: 1.0; color: U.withAlpha(Qt.lighter(tw.tone, 1.6), 0.0) }
                    }
                }
            }

            ColumnLayout {
                id: body
                x: 16
                y: 14
                width: card.width - 32
                spacing: 0

                // ── identity line ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    spacing: 6

                    C.AppText {
                        text: "YouTube Hunter"
                        font.pixelSize: Tokens.fontMicro
                        weight: Tokens.weightBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.9
                        color: Theme.text_strong
                    }
                    Rectangle {
                        visible: (tw.notice.source || "") !== ""
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Theme.outline
                    }
                    C.AppText {
                        visible: (tw.notice.source || "") !== ""
                        text: tw.notice.source || ""
                        font.pixelSize: Tokens.fontMicro
                        weight: Tokens.weightDemiBold
                        color: tw.tone
                        elide: Text.ElideRight
                        Layout.maximumWidth: 150
                    }
                    Rectangle {
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Theme.outline
                    }
                    C.AppText {
                        text: I18n.tr("now")
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.on_surface_var
                    }
                    Item { Layout.fillWidth: true }

                    // close — always there, quiet until the card is hovered
                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 8
                        color: closeArea.containsMouse ? Theme.hover_bg_strong : "transparent"
                        opacity: hover.hovered ? 1 : 0.45
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: "close"
                            size: 14
                            glyphColor: closeArea.containsMouse ? Theme.text_strong : Theme.on_surface_var
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tw.dismiss()
                        }
                    }
                }

                // ── leading tile + text ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 14

                    Item {
                        id: lead
                        Layout.preferredWidth: tw.hasThumb ? 100 : 56
                        Layout.preferredHeight: 56
                        Layout.alignment: Qt.AlignTop

                        // brand tile (no thumbnail)
                        Rectangle {
                            id: brandTile
                            anchors.fill: parent
                            visible: !tw.hasThumb
                            radius: 16
                            antialiasing: true
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.logo_grad_in, Theme.isDark ? 0.26 : 0.16) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.logo_grad_out, Theme.isDark ? 0.08 : 0.05) }
                            }
                            border.width: 1
                            border.color: U.withAlpha(Theme.logo_grad_in, 0.34)

                            C.BrandMark {
                                id: mark
                                anchors.centerIn: parent
                                width: 30
                                height: Math.round(30 * 812 / 738)
                                glow: true
                                glowStrength: 0.55
                                assemble: 0
                                playPop: 0
                                sheen: -1
                            }
                        }

                        // thumbnail (downloads / clips)
                        C.RoundThumb {
                            anchors.fill: parent
                            visible: tw.hasThumb
                            radius: 12
                            source: tw.hasThumb ? "image://thumbs/" + tw.notice.thumb : ""
                            glyph: "movie"
                        }
                        // brand badge on the thumbnail
                        Rectangle {
                            visible: tw.hasThumb
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 4
                            width: 22; height: 22; radius: 7
                            color: Qt.rgba(0.04, 0.04, 0.06, 0.78)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            C.BrandMark {
                                anchors.centerIn: parent
                                width: 13
                                height: Math.round(13 * 812 / 738)
                            }
                        }

                        // status badge (bottom-trailing corner)
                        Rectangle {
                            id: badge
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -5
                            anchors.bottomMargin: -5
                            width: 22; height: 22; radius: 11
                            scale: 0
                            color: tw.tone
                            border.width: 2
                            border.color: card.color
                            C.IconGlyph {
                                anchors.centerIn: parent
                                name: tw.kind === "error" ? "close"
                                    : tw.kind === "warn" ? "warning"
                                    : tw.kind === "success" ? "check"
                                    : (tw.notice.icon || "info")
                                fill: true
                                size: 12
                                glyphColor: "#ffffff"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            C.IconGlyph {
                                visible: (tw.notice.icon || "") !== ""
                                name: tw.notice.icon || "info"
                                fill: true
                                size: 15
                                glyphColor: tw.tone
                            }
                            C.AppText {
                                text: tw.notice.title || ""
                                color: Theme.text_strong
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontLabel
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Layout.maximumWidth: implicitWidth
                            }
                            Rectangle {
                                visible: tw.repeatCount > 1
                                Layout.preferredHeight: 17
                                Layout.preferredWidth: cnt.implicitWidth + 12
                                radius: 8.5
                                color: U.withAlpha(tw.tone, 0.18)
                                C.AppText {
                                    id: cnt
                                    anchors.centerIn: parent
                                    text: "×" + tw.repeatCount
                                    font.pixelSize: Tokens.fontMicro
                                    weight: Tokens.weightBold
                                    color: tw.tone
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        C.AppText {
                            visible: text !== ""
                            text: tw.notice.message || ""
                            color: Theme.on_surface_var
                            font.pixelSize: Tokens.fontCaption + 1
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 1.15
                            Layout.fillWidth: true
                        }
                    }
                }

                // ── actions ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 8

                    ToastButton {
                        primary: true
                        icon: tw.hasFile ? (tw.isMedia ? "play_arrow" : "open_in_new") : tw.hasFolder ? "folder_open" : "open_in_new"
                        label: tw.hasFile ? I18n.tr("Open")
                             : tw.hasFolder ? I18n.tr("Open folder")
                             : I18n.tr("View in app")
                        onClicked: {
                            if (tw.hasFile) { DesktopNotify.openFile(tw.notice.path); tw.dismiss() }
                            else if (tw.hasFolder) { DesktopNotify.revealFile(tw.notice.folder); tw.dismiss() }
                            else tw._open()
                        }
                    }
                    ToastButton {
                        visible: tw.hasFile
                        icon: "folder_open"
                        label: I18n.tr("Show in folder")
                        onClicked: { DesktopNotify.revealFile(tw.notice.path); tw.dismiss() }
                    }
                    ToastButton {
                        visible: tw.hasFile || tw.hasFolder
                        icon: "apps"
                        label: I18n.tr("App")
                        onClicked: tw._open()
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // time left — pauses while hovered
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: card.radius
                anchors.rightMargin: card.radius
                anchors.bottomMargin: 1
                height: 2
                radius: 1
                color: U.withAlpha(tw.tone, 0.12)
                Rectangle {
                    id: bar
                    property real progress: 1.0
                    anchors.left: parent.left
                    height: parent.height
                    width: parent.width * progress
                    radius: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(tw.tone, 0.35) }
                        GradientStop { position: 1.0; color: tw.tone }
                    }
                }
            }

            // the card body itself opens the app (buttons sit above this)
            MouseArea {
                anchors.fill: parent
                z: -1
                cursorShape: Qt.PointingHandCursor
                onClicked: tw._open()
            }
            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (tw.closing) return
                    if (hovered) countdown.pause()
                    else countdown.resume()
                }
            }
        }
    }

    // ── a small pill key, primary = accent face ──
    component ToastButton: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property bool primary: false
        signal clicked()

        Layout.preferredHeight: 30
        Layout.preferredWidth: btnRow.implicitWidth + 24
        radius: 10
        antialiasing: true
        color: primary
               ? (btnArea.pressed ? Theme.primary_press : btnArea.containsMouse ? Theme.primary_hover : Theme.primary)
               : (btnArea.containsMouse ? U.hoverTint(Theme.input_bg, Theme.isDark, 0.06) : Theme.input_bg)
        border.width: primary ? 0 : 1
        border.color: btnArea.containsMouse ? Theme.border_med : Theme.border
        scale: btnArea.pressed ? 0.97 : 1
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            C.IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: btn.icon !== ""
                name: btn.icon
                fill: true
                size: 14
                glyphColor: btn.primary ? Theme.on_primary : Theme.on_surface
            }
            C.AppText {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                font.pixelSize: Tokens.fontCaption + 1
                weight: Tokens.weightDemiBold
                color: btn.primary ? Theme.on_primary : Theme.text_strong
            }
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // ── motion ──
    ParallelAnimation {
        id: enter
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "x"; from: 64; to: 0; duration: 620; easing.type: Easing.OutExpo }
        NumberAnimation { target: zoom; properties: "xScale,yScale"; from: 0.96; to: 1; duration: 620; easing.type: Easing.OutExpo }
        // the brand mark builds itself
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: mark; property: "assemble"; from: 0; to: 1; duration: 640; easing.type: Easing.Linear }
        }
        SequentialAnimation {
            PauseAnimation { duration: 420 }
            NumberAnimation { target: mark; property: "playPop"; from: 0; to: 1; duration: 420; easing.type: Easing.Linear }
        }
        SequentialAnimation {
            PauseAnimation { duration: 620 }
            NumberAnimation { target: mark; property: "sheen"; from: 0; to: 1; duration: 820; easing.type: Easing.InOutSine }
            PropertyAction { target: mark; property: "sheen"; value: -1 }
        }
        // status badge pops after the mark lands
        SequentialAnimation {
            PauseAnimation { duration: 520 }
            NumberAnimation { target: badge; property: "scale"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
        }
        // light runs along the top edge
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: streak; property: "t"; from: 0; to: 1; duration: 1000; easing.type: Easing.InOutCubic }
        }
    }

    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 1.025; duration: 100; easing.type: Easing.OutCubic }
        NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
        NumberAnimation { target: streak; property: "t"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutCubic }
    }

    NumberAnimation {
        id: countdown
        target: bar; property: "progress"
        from: 1; to: 0
        duration: tw.holdMs
        onFinished: if (bar.progress <= 0.001) tw.dismiss()
    }

    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InCubic }
            NumberAnimation { target: slide; property: "x"; to: 48; duration: 260; easing.type: Easing.InCubic }
            NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 0.97; duration: 260; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                tw.visible = false
                tw.finished()
            }
        }
    }
}
