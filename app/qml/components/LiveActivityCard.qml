import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.41 "Live activity" — a download / cut that is STILL RUNNING follows the
// user into whatever app they switched to, as a live card in the bottom-right
// corner of the screen. Same family as DesktopToast (own frameless,
// non-activating, always-on-top window, same glass, same shadow), but alive:
//
//   ┌──────────────────────────────────────────────┐
//   │ ● YOUTUBE HUNTER · Downloads              ✕ │  pulse dot = live
//   │ ┌──────────┐  How I built a channel in 30…  │
//   │ │ thumb    │  ⬇ Downloading   1080p · MP4   │  stage chip + quality
//   │ │ ▓▓▓▓░░░░ │                                │
//   │ └──────────┘                                │
//   │ ━━━━━━━━━━━━━━━━━━━━━━━━──────────    64%  │  track + big tabular %
//   │ 12.4 MB/s  ·  182 MB of 284 MB  ·  9s left  │
//   └──────────────────────────────────────────────┘
//
// Signature: the thumbnail DEVELOPS. It starts as a grey print and the colour
// floods in behind a glowing scan line exactly as far as the bytes have
// landed; at 100% the print flashes once and the badge flips to a check.
//
// It ends in one of three ways, and never posts a second notice:
//   success → morphs in place: green, "Download complete", Open / Show in folder
//   error   → morphs in place: red, the reason, "View in app"
//   stopped → a quiet "Stopped" beat, then it glides out
// Closing it with ✕ tells DesktopNotify "not for this job"; that job then gets
// the ordinary completion toast when it ends instead.
Window {
    id: lw

    // ── set by the host ──
    property var job: ({})
    readonly property string key: job.key || ""
    readonly property int token: job.token || 0
    property real targetX: 0
    property real targetY: 0
    property bool placed: false
    property bool closing: false

    // running | paused | success | error | stopped
    property string phase: "running"
    property string message: ""
    property string filePath: ""
    property string folderPath: ""

    signal finished()

    readonly property int margin: 22
    readonly property int cardW: 384
    readonly property bool hasThumb: (job.thumb || "") !== ""
    readonly property bool isCut: (job.kind || "") === "cut"
    readonly property bool running: phase === "running"
    // v3.43: a paused job is still "live" — meter stays, ⏸ became ▶
    readonly property bool paused: phase === "paused"
    readonly property bool live: running || paused
    readonly property bool canPause: !!job.canPause && live
    readonly property bool busy: !!job.busy
    readonly property bool indeterminate: running && !!job.indeterminate
    readonly property int page: job.page !== undefined ? job.page : -1
    readonly property bool hasFile: filePath !== ""
    readonly property bool isMedia: /\.(mp4|mkv|webm|mov|avi|m4v|m4a|mp3|wav|opus|ogg|flac)$/i.test(filePath)
    readonly property int holdMs: phase === "error" ? 12000 : phase === "stopped" ? 2600 : 9000

    // the light this card is lit by — glides between states
    property color tone: phase === "success" ? Theme.secondary_container
                       : phase === "error" ? Theme.error
                       : phase === "stopped" ? Theme.outline
                       : phase === "paused" ? Theme.warn
                       : Theme.primary
    Behavior on tone { ColorAnimation { duration: 520; easing.type: Easing.OutCubic } }

    // eased progress 0..1 — backend ticks land ~5/s, this makes them one glide
    property real frac: 0
    Behavior on frac {
        enabled: lw.placed
        NumberAnimation { duration: 560; easing.type: Easing.OutCubic }
    }

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
        enabled: lw.placed
        NumberAnimation { duration: 340; easing.type: Easing.OutCubic }
    }

    // ── public API (host) ──
    function present() {
        phase = job.paused ? "paused" : "running"
        frac = (job.pct || 0) / 100
        visible = true
        placed = true
        enter.restart()
    }

    function apply(j) {
        if (!live || closing) return
        job = j
        phase = j.paused ? "paused" : "running"
        frac = Math.max(0, Math.min(1, (j.pct || 0) / 100))
    }

    function finish(e) {
        if (closing) return
        job = e
        message = e.message || ""
        filePath = e.path || ""
        folderPath = e.folder || ""
        phase = e.outcome || "success"
        if (phase === "success") frac = 1
        morph.restart()
        countdown.stop()
        timeLeft.progress = 1
        countdown.start()
        if (hover.hovered && phase !== "stopped") countdown.pause()
    }

    function dismiss(byUser) {
        if (closing) return
        closing = true
        countdown.stop()
        enter.stop()
        leave.byUser = !!byUser
        leave.restart()
    }

    function _open() {
        DesktopNotify.activate(lw.page)
        dismiss(false)
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

        BorderImage {
            source: "shadow_soft.png"
            border { left: 64; right: 64; top: 64; bottom: 64 }
            horizontalTileMode: BorderImage.Stretch
            verticalTileMode: BorderImage.Stretch
            anchors.fill: card
            anchors.margins: -lw.margin
            anchors.topMargin: -lw.margin + 6
            opacity: Theme.isDark ? 0.95 : 0.36
            smooth: true
            cache: true
        }

        Rectangle {
            id: card
            x: lw.margin
            y: lw.margin
            width: lw.cardW
            height: body.implicitHeight + 32
            radius: 20
            antialiasing: true
            color: Theme.isDark ? U.mix(Theme.surface_highest, Theme.background, 0.14)
                                : Theme.panel_bg
            border.width: 1
            border.color: U.mix(Theme.border, lw.tone, hover.hovered ? 0.55 : 0.28)
            Behavior on border.color { ColorAnimation { duration: Tokens.durMed } }

            // the tone breathes in from the top-leading corner
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(lw.tone, Theme.isDark ? 0.15 : 0.08) }
                    GradientStop { position: 0.6; color: U.withAlpha(lw.tone, 0.0) }
                }
            }
            // ambient: a slow wash that drifts while the job is alive.
            // FIX: the 220px disc sits mostly ABOVE the card (y: -150) and a
            // Rectangle's radius never clips its children, so its lower half
            // used to poke out over the top edge as a pale half-circle on the
            // desktop. RoundClip masks it to the card's exact rounded shape.
            C.RoundClip {
                anchors.fill: parent
                radius: card.radius
                active: ambient.visible
                LayoutMirroring.enabled: false
                Rectangle {
                    id: ambient
                    visible: lw.running
                    width: 220
                    height: 220
                    radius: 110
                    y: -150
                    x: -110 + (card.width + 110) * ambientT
                    property real ambientT: 0
                    opacity: Theme.isDark ? 0.06 : 0.04
                    color: lw.tone
                    SequentialAnimation on ambientT {
                        running: lw.running && lw.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: 1; duration: 5200; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1; to: 0; duration: 5200; easing.type: Easing.InOutSine }
                    }
                }
            }

            // specular top edge
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 40
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                    GradientStop { position: 0.5; color: Theme.glass_hi }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                }
            }

            // streak of light along the top edge (arrival + every state change)
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
                    width: 150
                    height: 2
                    radius: 1
                    x: -width + (parent.width + width) * t
                    opacity: t > 0 && t < 1 ? 1 : 0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(lw.tone, 0.0) }
                        GradientStop { position: 0.7; color: lw.tone }
                        GradientStop { position: 1.0; color: U.withAlpha(Qt.lighter(lw.tone, 1.6), 0.0) }
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
                    spacing: 7

                    // live dot: ripples while running, settles when done
                    Item {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        Rectangle {
                            id: ripple
                            anchors.centerIn: parent
                            width: 8; height: 8; radius: 4
                            color: lw.tone
                            opacity: 0
                            scale: 1
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 7; height: 7; radius: 3.5
                            color: lw.tone
                        }
                        ParallelAnimation {
                            running: lw.running && lw.visible
                            loops: Animation.Infinite
                            NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.8; duration: 1600; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ripple; property: "opacity"; from: 0.55; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                        }
                    }
                    C.AppText {
                        text: "YouTube Hunter"
                        font.pixelSize: Tokens.fontMicro
                        weight: Tokens.weightBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.9
                        color: Theme.text_strong
                    }
                    Rectangle {
                        visible: (lw.job.source || "") !== ""
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Theme.outline
                    }
                    C.AppText {
                        visible: (lw.job.source || "") !== ""
                        text: lw.job.source || ""
                        font.pixelSize: Tokens.fontMicro
                        weight: Tokens.weightDemiBold
                        color: lw.tone
                        elide: Text.ElideRight
                        Layout.maximumWidth: 160
                    }
                    Item { Layout.fillWidth: true }

                    // ✕ — a first-class control here: "I don't want this one"
                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 9
                        color: closeArea.pressed ? Theme.hover_bg_strong
                             : closeArea.containsMouse ? Theme.hover_bg : "transparent"
                        border.width: closeArea.containsMouse ? 1 : 0
                        border.color: Theme.border_med
                        opacity: hover.hovered ? 1 : 0.6
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
                            onClicked: lw.dismiss(true)
                        }
                    }
                }

                // ── print + text ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 14

                    Item {
                        id: tile
                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 63
                        Layout.alignment: Qt.AlignTop

                        // grey print (what has not landed yet)
                        Item {
                            anchors.fill: parent
                            visible: lw.hasThumb
                            layer.enabled: lw.hasThumb
                            layer.effect: MultiEffect {
                                saturation: -1.0
                                brightness: Theme.isDark ? -0.22 : -0.05
                                contrast: -0.1
                            }
                            C.RoundThumb {
                                anchors.fill: parent
                                radius: 12
                                source: lw.hasThumb ? "image://thumbs/" + lw.job.thumb : ""
                                glyph: lw.isCut ? "scissors" : "movie"
                            }
                        }
                        // no thumbnail: a quiet tile with the job's glyph
                        Rectangle {
                            anchors.fill: parent
                            visible: !lw.hasThumb
                            radius: 12
                            color: Theme.surface_highest
                            border.width: 1
                            border.color: Theme.border_med
                            C.IconGlyph {
                                anchors.centerIn: parent
                                name: lw.isCut ? "scissors" : "download"
                                fill: true
                                size: 24
                                glyphColor: Theme.outline
                            }
                        }

                        // colour floods in as far as the job has got
                        Item {
                            id: developed
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: tile.width * (lw.indeterminate ? 0 : lw.frac)
                            clip: true
                            C.RoundThumb {
                                visible: lw.hasThumb
                                anchors.left: parent.left
                                width: tile.width
                                height: tile.height
                                radius: 12
                                source: lw.hasThumb ? "image://thumbs/" + lw.job.thumb : ""
                                glyph: lw.isCut ? "scissors" : "movie"
                            }
                            Rectangle {
                                visible: !lw.hasThumb
                                anchors.left: parent.left
                                width: tile.width
                                height: tile.height
                                radius: 12
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.lighter(lw.tone, 1.12) }
                                    GradientStop { position: 1.0; color: Qt.darker(lw.tone, 1.35) }
                                }
                                C.IconGlyph {
                                    // centred on the TILE, not on the clip
                                    x: (tile.width - width) / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    LayoutMirroring.enabled: false
                                    name: lw.isCut ? "scissors" : "download"
                                    fill: true
                                    size: 24
                                    glyphColor: "#ffffff"
                                }
                            }
                        }

                        // the scan line at the developing edge
                        Item {
                            visible: lw.running && !lw.indeterminate && lw.frac > 0.01 && lw.frac < 0.99
                            // explicit x (mirroring never touches x): the edge is
                            // where the colour stops, whichever way the language runs
                            LayoutMirroring.enabled: false
                            x: I18n.rtl ? tile.width - developed.width - width / 2
                                        : developed.width - width / 2
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 22
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(lw.tone, 0.0) }
                                    GradientStop { position: 0.5; color: U.withAlpha(lw.tone, 0.42) }
                                    GradientStop { position: 1.0; color: U.withAlpha(lw.tone, 0.0) }
                                }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 2
                                height: parent.height
                                color: Qt.lighter(lw.tone, 1.5)
                                opacity: 0.95
                            }
                        }

                        // working without a number (preparing, merging…): a sheen sweeps the print
                        Item {
                            anchors.fill: parent
                            visible: lw.indeterminate
                            clip: true
                            LayoutMirroring.enabled: false
                            Rectangle {
                                id: sheenBand
                                property real t: 0
                                width: 46
                                height: parent.height * 1.6
                                y: -parent.height * 0.3
                                rotation: 18
                                x: -width + (parent.width + width * 2) * t
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
                                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                }
                                NumberAnimation on t {
                                    running: lw.indeterminate && lw.visible
                                    loops: Animation.Infinite
                                    from: 0; to: 1
                                    duration: 1500
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }

                        // the print "fixes": one flash when it completes
                        Rectangle {
                            id: flash
                            anchors.fill: parent
                            radius: 12
                            color: "#ffffff"
                            opacity: 0
                        }

                        // status badge
                        Rectangle {
                            id: badge
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -6
                            anchors.bottomMargin: -6
                            width: 24; height: 24; radius: 12
                            scale: 0
                            color: lw.tone
                            border.width: 2
                            border.color: card.color
                            C.SpinnerGlyph {
                                anchors.centerIn: parent
                                visible: lw.indeterminate
                                name: "autorenew"
                                size: 12
                                spinning: lw.indeterminate && lw.visible
                                glyphColor: "#ffffff"
                            }
                            C.IconGlyph {
                                anchors.centerIn: parent
                                visible: !lw.indeterminate
                                name: lw.phase === "success" ? "check"
                                    : lw.phase === "error" ? "close"
                                    : lw.phase === "stopped" ? "pause"
                                    : lw.isCut ? "scissors" : "downloading"
                                fill: true
                                size: 13
                                glyphColor: "#ffffff"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                        spacing: 7

                        C.AppText {
                            text: lw.job.title || ""
                            // v1.2: the card follows the title's own direction,
                            // so a Persian video name reads right-to-left on a
                            // card that is otherwise an English notification.
                            readonly property bool rtl: U.isRtlText(text)
                            LayoutMirroring.enabled: false
                            horizontalAlignment: rtl ? Text.AlignRight : Text.AlignLeft
                            color: Theme.text_strong
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontLabel - 1
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 1.12
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // stage chip — says what is happening, or how it ended
                            Rectangle {
                                id: chip
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: Math.min(chipRow.implicitWidth + 16, 190)
                                radius: 11
                                color: U.withAlpha(lw.tone, Theme.isDark ? 0.16 : 0.11)
                                border.width: 1
                                border.color: U.withAlpha(lw.tone, 0.28)
                                Row {
                                    id: chipRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    spacing: 5
                                    C.IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: lw.phase === "success" ? "check_circle"
                                            : lw.phase === "error" ? "error"
                                            : lw.phase === "stopped" ? "pause"
                                            : lw.paused ? "pause"
                                            : lw.indeterminate ? "hourglass_empty"
                                            : lw.isCut ? "scissors" : "downloading"
                                        fill: true
                                        size: 12
                                        glyphColor: lw.tone
                                    }
                                    C.AppText {
                                        id: chipText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: lw.phase === "success" ? (lw.isCut ? I18n.tr("Clip ready") : I18n.tr("Download complete"))
                                            : lw.phase === "error" ? (lw.isCut ? I18n.tr("Cut failed.") : I18n.tr("Download failed"))
                                            : lw.phase === "stopped" ? I18n.tr("Stopped")
                                            : lw.paused ? I18n.tr("Paused")
                                            : (lw.job.stage || (lw.isCut ? I18n.tr("Cutting…") : I18n.tr("Downloading")))
                                        font.pixelSize: Tokens.fontCaption
                                        weight: Tokens.weightDemiBold
                                        color: Theme.isDark ? Qt.lighter(lw.tone, 1.25) : Qt.darker(lw.tone, 1.25)
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, 150)
                                    }
                                }
                            }
                            C.AppText {
                                visible: text !== "" && lw.phase !== "error"
                                text: lw.job.subtitle || ""
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Item { Layout.fillWidth: true; visible: lw.phase === "error" || (lw.job.subtitle || "") === "" }
                        }
                    }
                }

                // ── bottom zone: live meter ⇄ actions (same height, no jump) ──
                Item {
                    id: zone
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.preferredHeight: 48

                    // live meter
                    Item {
                        id: meter
                        anchors.fill: parent
                        opacity: lw.live ? 1 : 0
                        visible: opacity > 0.01
                        transform: Translate { y: lw.live ? 0 : -6; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        RowLayout {
                            id: meterRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 28
                            spacing: 14

                            Item {
                                id: track
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                Layout.alignment: Qt.AlignVCenter
                                // RTL runs right→left; mirror the whole meter, not each part
                                LayoutMirroring.enabled: false
                                transform: Scale { origin.x: track.width / 2; xScale: I18n.rtl ? -1 : 1 }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 3
                                    color: U.withAlpha(lw.tone, Theme.isDark ? 0.16 : 0.12)
                                }
                                Rectangle {
                                    id: fill
                                    visible: !lw.indeterminate
                                    height: parent.height
                                    width: Math.max(height, track.width * lw.frac)
                                    radius: 3
                                    clip: true
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.darker(lw.tone, 1.3) }
                                        GradientStop { position: 1.0; color: Qt.lighter(lw.tone, 1.15) }
                                    }
                                    // light running through the filled part
                                    Rectangle {
                                        property real t: 0
                                        width: 56
                                        height: parent.height
                                        x: -width + (fill.width + width) * t
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                            GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.42) }
                                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                        }
                                        NumberAnimation on t {
                                            running: lw.running && !lw.indeterminate && lw.visible
                                            loops: Animation.Infinite
                                            from: 0; to: 1
                                            duration: 1700
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                }
                                // glowing head
                                Rectangle {
                                    visible: !lw.indeterminate && lw.frac > 0.02 && lw.frac < 0.995
                                    width: 16; height: 16; radius: 8
                                    x: fill.width - width / 2 - 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: U.withAlpha(lw.tone, 0.28)
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8; height: 8; radius: 4
                                        color: Qt.lighter(lw.tone, 1.45)
                                    }
                                }
                                // no number yet: a comet sweeps the track
                                Item {
                                    anchors.fill: parent
                                    visible: lw.indeterminate
                                    clip: true
                                    Rectangle {
                                        property real t: 0
                                        width: track.width * 0.34
                                        height: parent.height
                                        radius: 3
                                        x: -width + (track.width + width) * t
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: U.withAlpha(lw.tone, 0.0) }
                                            GradientStop { position: 0.8; color: lw.tone }
                                            GradientStop { position: 1.0; color: Qt.lighter(lw.tone, 1.3) }
                                        }
                                        NumberAnimation on t {
                                            running: lw.indeterminate && lw.visible
                                            loops: Animation.Infinite
                                            from: 0; to: 1
                                            duration: 1250
                                            easing.type: Easing.InOutCubic
                                        }
                                    }
                                }
                            }

                            // v3.43: ⏸ / ▶ — pauses for real (the bytes stay on disk)
                            // and ▶ continues from them. Hidden while merging.
                            Rectangle {
                                id: pauseBtn
                                visible: lw.canPause
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                Layout.alignment: Qt.AlignVCenter
                                radius: 15
                                color: pauseArea.pressed ? U.withAlpha(lw.tone, 0.32)
                                     : pauseArea.containsMouse ? U.withAlpha(lw.tone, 0.22)
                                     : U.withAlpha(lw.tone, Theme.isDark ? 0.14 : 0.10)
                                border.width: 1
                                border.color: U.withAlpha(lw.tone, pauseArea.containsMouse ? 0.55 : 0.30)
                                opacity: lw.busy ? 0.55 : 1
                                Behavior on color { ColorAnimation { duration: Tokens.durFast } }
                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    name: lw.paused ? "play_arrow" : "pause"
                                    fill: true
                                    size: 16
                                    glyphColor: Theme.isDark ? Qt.lighter(lw.tone, 1.3) : Qt.darker(lw.tone, 1.2)
                                }
                                MouseArea {
                                    id: pauseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // ▶ is allowed while a pause is still settling
                                        // (the backend queues the restart); a second ⏸
                                        // while one is in flight is ignored.
                                        if (lw.paused || !!lw.job.pausing)
                                            DesktopNotify.liveResume(lw.key)
                                        else if (!lw.busy)
                                            DesktopNotify.livePause(lw.key)
                                    }
                                }
                            }

                            // the big number — tabular, so it ticks without wobbling
                            Item {
                                Layout.preferredWidth: 62
                                Layout.fillHeight: true
                                C.AppText {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !lw.indeterminate
                                    text: Math.round(lw.frac * 100) + "%"
                                    font.pixelSize: Tokens.fontTitle
                                    weight: Tokens.weightBold
                                    font.letterSpacing: -0.6
                                    font.features: ({ "tnum": 1 })
                                    color: Theme.text_strong
                                    horizontalAlignment: Text.AlignRight
                                }
                                // three breathing dots while there is no number
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: lw.indeterminate
                                    spacing: 5
                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            required property int index
                                            width: 6; height: 6; radius: 3
                                            color: lw.tone
                                            opacity: 0.25
                                            SequentialAnimation on opacity {
                                                running: lw.indeterminate && lw.visible
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: index * 160 }
                                                NumberAnimation { to: 1; duration: 320; easing.type: Easing.OutCubic }
                                                NumberAnimation { to: 0.25; duration: 520; easing.type: Easing.InCubic }
                                                PauseAnimation { duration: (2 - index) * 160 }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        C.AppText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            text: {
                                var parts = []
                                if (lw.paused) {
                                    if (lw.job.sizeText) parts.push(lw.job.sizeText)
                                    parts.push(I18n.tr("Press ▶ to continue"))
                                    return parts.join("   ·   ")
                                }
                                if (lw.job.speedText) parts.push(lw.job.speedText)
                                if (lw.job.sizeText) parts.push(lw.job.sizeText)
                                if (lw.job.etaText) parts.push(lw.job.etaText)
                                if (parts.length === 0)
                                    return lw.isCut ? (lw.job.subtitle || "") : I18n.tr("Working on it…")
                                return parts.join("   ·   ")
                            }
                            font.pixelSize: Tokens.fontCaption
                            font.features: ({ "tnum": 1 })
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                        }
                    }

                    // actions (after the job ended)
                    Item {
                        id: actions
                        anchors.fill: parent
                        opacity: lw.live ? 0 : 1
                        visible: opacity > 0.01
                        transform: Translate { y: lw.live ? 6 : 0; Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } } }
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: 120 }
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }

                        // error / stop: one line of why, under the buttons' baseline
                        C.AppText {
                            visible: lw.phase === "error" || lw.phase === "stopped"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: lw.phase === "stopped"
                                  ? (lw.isCut ? I18n.tr("Cut stopped.") : I18n.tr("Download stopped."))
                                  : (lw.message || "")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            visible: lw.phase === "success" || lw.phase === "error"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            spacing: 8

                            CardButton {
                                primary: true
                                icon: lw.hasFile ? (lw.isMedia ? "play_arrow" : "open_in_new") : "open_in_new"
                                label: lw.hasFile ? I18n.tr("Open") : I18n.tr("View in app")
                                onClicked: {
                                    if (lw.hasFile) { DesktopNotify.openFile(lw.filePath); lw.dismiss(false) }
                                    else lw._open()
                                }
                            }
                            CardButton {
                                visible: lw.hasFile
                                icon: "folder_open"
                                label: I18n.tr("Show in folder")
                                onClicked: { DesktopNotify.revealFile(lw.filePath); lw.dismiss(false) }
                            }
                            Item { Layout.fillWidth: true }
                            CardButton {
                                visible: lw.hasFile
                                icon: "apps"
                                label: I18n.tr("App")
                                onClicked: lw._open()
                            }
                        }
                    }
                }
            }

            // time left once it has ended — pauses while hovered
            Rectangle {
                visible: !lw.live
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: card.radius
                anchors.rightMargin: card.radius
                anchors.bottomMargin: 1
                height: 2
                radius: 1
                color: U.withAlpha(lw.tone, 0.12)
                Rectangle {
                    id: timeLeft
                    property real progress: 1.0
                    anchors.left: parent.left
                    height: parent.height
                    width: parent.width * progress
                    radius: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(lw.tone, 0.35) }
                        GradientStop { position: 1.0; color: lw.tone }
                    }
                }
            }

            // the card body opens the app on the page the job lives on
            MouseArea {
                anchors.fill: parent
                z: -1
                cursorShape: Qt.PointingHandCursor
                onClicked: lw._open()
            }
            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (lw.closing || lw.live || lw.phase === "stopped") return
                    if (hovered) countdown.pause()
                    else countdown.resume()
                }
            }
        }
    }

    component CardButton: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property bool primary: false
        signal clicked()

        Layout.preferredHeight: 32
        Layout.preferredWidth: btnRow.implicitWidth + 26
        radius: 11
        antialiasing: true
        color: primary
               ? (btnArea.pressed ? Theme.primary_press : btnArea.containsMouse ? Theme.primary_hover : Theme.primary)
               : (btnArea.containsMouse ? U.hoverTint(Theme.input_bg, Theme.isDark, 0.06) : Theme.input_bg)
        border.width: primary ? 0 : 1
        border.color: btnArea.containsMouse ? Theme.border_med : Theme.border
        scale: btnArea.pressed ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: Tokens.durFast } }
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
        NumberAnimation { target: slide; property: "x"; from: 64; to: 0; duration: 640; easing.type: Easing.OutExpo }
        NumberAnimation { target: zoom; properties: "xScale,yScale"; from: 0.96; to: 1; duration: 640; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 460 }
            NumberAnimation { target: badge; property: "scale"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: streak; property: "t"; from: 0; to: 1; duration: 1000; easing.type: Easing.InOutCubic }
        }
    }

    // running → ended: a small lift, the print fixes, the badge flips
    SequentialAnimation {
        id: morph
        ParallelAnimation {
            NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 1.022; duration: 140; easing.type: Easing.OutCubic }
            NumberAnimation { target: badge; property: "scale"; to: 0.4; duration: 140; easing.type: Easing.InCubic }
            SequentialAnimation {
                PauseAnimation { duration: 260 }
                NumberAnimation { target: flash; property: "opacity"; from: 0; to: lw.phase === "success" ? 0.55 : 0.0; duration: 90 }
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 1.0; duration: 360; easing.type: Easing.OutBack }
            NumberAnimation { target: badge; property: "scale"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
            NumberAnimation { target: streak; property: "t"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutCubic }
        }
    }

    NumberAnimation {
        id: countdown
        target: timeLeft; property: "progress"
        from: 1; to: 0
        duration: lw.holdMs
        onFinished: if (timeLeft.progress <= 0.001) lw.dismiss(false)
    }

    SequentialAnimation {
        id: leave
        property bool byUser: false
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InCubic }
            NumberAnimation { target: slide; property: "x"; to: 52; duration: 280; easing.type: Easing.InCubic }
            NumberAnimation { target: zoom; properties: "xScale,yScale"; to: 0.97; duration: 280; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                lw.visible = false
                DesktopNotify.liveClosed(lw.key, lw.token, leave.byUser)
                lw.finished()
            }
        }
    }
}
