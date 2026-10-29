import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.2 — the panel under the title-bar TransferCapsule.
//
//   ┌────────────────────────────────────────────┐
//   │ Transfers  (● 2 active)        Downloads ↗ │
//   │ ┌───────┐ How I built a channel in 30…  64% │  title · big tabular %
//   │ │ thumb │ ● Downloading · 1080p · MP4       │  stage (tone) · quality
//   │ └───────┘ ━━━━━━━━━━━━━━━━━━━━━━━──────────  │  the meter, glowing head
//   │           12.4 MB/s · 182 of 284 MB · 9s ⏸ ■│  muted facts · actions
//   ├────────────────────────────────────────────┤
//   │ …                                          │
//   └────────────────────────────────────────────┘
//
// Same family as the notifications tray (GlassPanel, same open motion), so it
// reads as part of the title bar, not a new kind of window. Rows are a Column
// + Repeater over the capsule's keyed ListModel: a tick updates a row in place
// (the meter glides), it never rebuilds. A click on a row opens the page that
// owns the job; ⏸ / ▶ / ■ act on downloads the app can actually pause.
Popup {
    id: root
    property var model: null
    readonly property int count: model ? model.count : 0

    width: 372
    padding: 0
    modal: true
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property real closedAt: 0
    onAboutToHide: closedAt = Date.now()
    // the last job left while the panel was open: nothing to show any more
    onCountChanged: if (count === 0 && opened) close()

    readonly property int _pad: 16
    readonly property int _maxList: 330

    function toneOf(outcome, paused) {
        return outcome === "success" ? Theme.secondary_container
             : outcome === "error" ? Theme.error
             : outcome === "stopped" ? Theme.outline
             : paused ? Theme.warn
             : Theme.primary
    }

    transformOrigin: I18n.rtl ? Item.TopLeft : Item.TopRight
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 260; easing.type: Easing.OutQuint }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: 110; easing.type: Easing.OutCubic }
        }
    }

    background: Item { }

    contentItem: Item {
        id: stage
        implicitWidth: root.width
        implicitHeight: col.implicitHeight
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        C.GlassPanel {
            anchors.fill: parent
            radius_: 20
            elevation: 2.6
            color: Theme.surface
            // brand light pooling at the top, like the tray
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 1
                height: 120
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.05) }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                }
            }
        }

        Column {
            id: col
            width: parent.width

            // ── header ──
            Item {
                width: parent.width
                height: 52

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: root._pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    C.AppText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Transfers")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.text_strong
                    }
                    // live count
                    Rectangle {
                        visible: DesktopNotify.activeCount > 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: 20
                        width: liveRow.implicitWidth + 16
                        radius: 10
                        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.09)
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.26)
                        Row {
                            id: liveRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6; radius: 3
                                color: Theme.primary
                                SequentialAnimation on opacity {
                                    running: root.opened && Tokens.appActive
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.35; to: 1; duration: 800; easing.type: Easing.InOutSine }
                                }
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("{n} active").replace("{n}", DesktopNotify.activeCount)
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontMicro
                                color: Theme.isDark ? Qt.lighter(Theme.primary, 1.25) : Theme.primary_container
                            }
                        }
                    }
                }

                // → Downloads page
                AbstractButton {
                    id: openAll
                    anchors.right: parent.right
                    anchors.rightMargin: root._pad - 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    width: openRow.implicitWidth + 16
                    padding: 0
                    HoverHandler { id: openHover; cursorShape: Qt.PointingHandCursor }
                    onClicked: { App.goto(8); root.close() }
                    background: Rectangle {
                        radius: Tokens.radiusSm
                        color: openHover.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                    contentItem: Item {
                        Row {
                            id: openRow
                            anchors.centerIn: parent
                            spacing: 4
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Downloads")
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontCaption
                                color: openHover.hovered ? Theme.primary : Theme.on_surface_var
                            }
                            C.IconGlyph {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "arrow_right_up"
                                size: 13
                                glyphColor: openHover.hovered ? Theme.primary : Theme.on_surface_var
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: root._pad; anchors.rightMargin: root._pad
                    height: 1
                    color: Theme.divider_h
                }
            }

            // ── rows ──
            Flickable {
                id: flick
                width: parent.width
                height: Math.min(rows.implicitHeight, root._maxList)
                contentHeight: rows.implicitHeight
                interactive: rows.implicitHeight > root._maxList
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Column {
                    id: rows
                    width: flick.width
                    topPadding: 6
                    bottomPadding: 8

                    Repeater {
                        model: root.model
                        // ═════ one transfer ═════
                        delegate: Item {
                            id: jr
                            required property int index
                            required property string key
                            required property string kind
                            required property string title
                            required property string subtitle
                            required property string thumb
                            required property int page
                            required property int pct
                            required property bool indeterminate
                            required property bool paused
                            required property bool canPause
                            required property bool busy
                            required property string outcome
                            required property string stage
                            required property string speedText
                            required property string sizeText
                            required property string etaText

                            readonly property bool done: outcome !== ""
                            readonly property bool isCut: kind === "cut"
                            readonly property bool isDl: key.indexOf("dl:") === 0
                            readonly property color tone: root.toneOf(outcome, paused)

                            property real frac: 0
                            Behavior on frac { NumberAnimation { duration: 560; easing.type: Easing.OutCubic } }
                            onPctChanged: frac = outcome === "success" ? 1 : pct / 100
                            onOutcomeChanged: if (outcome === "success") frac = 1
                            Component.onCompleted: frac = outcome === "success" ? 1 : pct / 100

                            width: parent ? parent.width : 0
                            height: 92

                            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                            // a click anywhere on the row (buttons on top take their own) opens
                            // the page that owns the job
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { DesktopNotify.activityOpen(jr.page); root.close() }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 6; anchors.rightMargin: 6
                                anchors.topMargin: 2; anchors.bottomMargin: 2
                                radius: Tokens.radiusLg
                                color: rowHover.hovered ? U.hoverTint(Theme.surface, Theme.isDark, 0.05) : U.withAlpha(Theme.surface, 0)
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }

                            // thumbnail
                            Item {
                                id: tile
                                x: root._pad
                                y: 14
                                width: 72
                                height: 41
                                C.RoundThumb {
                                    anchors.fill: parent
                                    visible: jr.thumb !== ""
                                    radius: Tokens.radiusSm
                                    source: jr.thumb !== "" ? "image://thumbs/" + jr.thumb : ""
                                    glyph: jr.isCut ? "scissors" : "movie"
                                    opacity: jr.paused || jr.outcome === "stopped" ? 0.5 : 1
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: jr.thumb === ""
                                    radius: Tokens.radiusSm
                                    color: Theme.surface_highest
                                    border.width: 1
                                    border.color: Theme.border_med
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        name: jr.isCut ? "scissors" : "download"
                                        fill: true
                                        size: 18
                                        glyphColor: Theme.outline
                                    }
                                }
                                // state badge on the corner
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: -5
                                    anchors.bottomMargin: -5
                                    width: 20; height: 20; radius: 10
                                    color: jr.tone
                                    border.width: 2
                                    border.color: Theme.surface
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: 360 } }
                                    C.SpinnerGlyph {
                                        anchors.centerIn: parent
                                        visible: jr.indeterminate && !jr.done
                                        name: "autorenew"
                                        size: 11
                                        spinning: visible && root.opened
                                        glyphColor: "#ffffff"
                                    }
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        visible: !(jr.indeterminate && !jr.done)
                                        name: jr.outcome === "success" ? "check"
                                            : jr.outcome === "error" ? "close"
                                            : jr.paused || jr.outcome === "stopped" ? "pause"
                                            : jr.isCut ? "scissors" : "downloading"
                                        fill: true
                                        size: 11
                                        glyphColor: "#ffffff"
                                    }
                                }
                            }

                            // text column
                            Item {
                                id: body
                                anchors.left: tile.right
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.rightMargin: root._pad
                                y: 12
                                height: parent.height - 24

                                // title + big %
                                C.AppText {
                                    id: pctBig
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    text: jr.outcome === "success" ? "100%"
                                        : jr.indeterminate && !jr.done ? ""
                                        : jr.done ? "" : jr.pct + "%"
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontLabel
                                    color: jr.outcome === "success" ? jr.tone : jr.paused ? Theme.on_surface_var : Theme.text_strong
                                }
                                C.AppText {
                                    anchors.left: parent.left
                                    anchors.right: pctBig.left
                                    anchors.rightMargin: 10
                                    anchors.top: parent.top
                                    text: jr.title
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.text_strong
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                // stage · quality
                                Row {
                                    id: stageRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    y: 21
                                    spacing: 6
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6; height: 6; radius: 3
                                        color: jr.tone
                                    }
                                    C.AppText {
                                        id: stageLbl
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: jr.paused ? I18n.tr("Paused")
                                            : jr.stage !== "" ? jr.stage
                                            : jr.isCut ? I18n.tr("Cutting…") : I18n.tr("Downloading")
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.isDark ? Qt.lighter(jr.tone, 1.2) : Qt.darker(jr.tone, 1.2)
                                    }
                                    C.AppText {
                                        visible: jr.subtitle !== "" && jr.outcome !== "error"
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "·  " + jr.subtitle
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, stageRow.width - stageLbl.width - 20)
                                    }
                                }

                                // the meter
                                Item {
                                    id: track
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    y: 44
                                    height: 4
                                    LayoutMirroring.enabled: false
                                    transform: Scale { origin.x: track.width / 2; xScale: I18n.rtl ? -1 : 1 }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color: U.withAlpha(jr.tone, Theme.isDark ? 0.16 : 0.12)
                                    }
                                    Rectangle {
                                        id: fill
                                        visible: !(jr.indeterminate && !jr.done)
                                        height: parent.height
                                        width: Math.max(height, track.width * jr.frac)
                                        radius: 2
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Qt.darker(jr.tone, 1.35) }
                                            GradientStop { position: 1.0; color: Qt.lighter(jr.tone, 1.12) }
                                        }
                                    }
                                    // glowing head while bytes are landing
                                    Rectangle {
                                        visible: fill.visible && !jr.done && !jr.paused && jr.frac > 0.01 && jr.frac < 0.995
                                        width: 12; height: 12; radius: 6
                                        x: fill.width - width / 2 - 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: U.withAlpha(jr.tone, 0.30)
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 5; height: 5; radius: 2.5
                                            color: Qt.lighter(jr.tone, 1.5)
                                        }
                                    }
                                    // preparing / merging: a band sweeps the track
                                    Item {
                                        anchors.fill: parent
                                        visible: jr.indeterminate && !jr.done
                                        clip: true
                                        Rectangle {
                                            id: band
                                            property real t: 0
                                            width: parent.width * 0.32
                                            height: parent.height
                                            radius: 2
                                            x: -width + (parent.width + width) * t
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: U.withAlpha(jr.tone, 0.0) }
                                                GradientStop { position: 0.5; color: jr.tone }
                                                GradientStop { position: 1.0; color: U.withAlpha(jr.tone, 0.0) }
                                            }
                                            NumberAnimation on t {
                                                running: band.visible && root.opened
                                                loops: Animation.Infinite
                                                from: 0; to: 1
                                                duration: 1200
                                                easing.type: Easing.InOutSine
                                            }
                                        }
                                    }
                                }

                                // facts · actions
                                C.AppText {
                                    anchors.left: parent.left
                                    anchors.right: actions.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: actions.verticalCenter
                                    text: {
                                        const bits = []
                                        if (jr.speedText !== "") bits.push(jr.speedText)
                                        if (jr.sizeText !== "") bits.push(jr.sizeText)
                                        if (jr.etaText !== "") bits.push(jr.etaText)
                                        return bits.join("  ·  ")
                                    }
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    elide: Text.ElideRight
                                }
                                Row {
                                    id: actions
                                    anchors.right: parent.right
                                    anchors.rightMargin: -4
                                    y: 54
                                    spacing: 2
                                    MiniBtn {
                                        visible: jr.canPause && !jr.done
                                        enabled: !jr.busy
                                        glyph: jr.paused ? "play_arrow" : "pause"
                                        tip: jr.paused ? I18n.tr("Resume") : I18n.tr("Pause")
                                        onClicked: jr.paused ? DesktopNotify.liveResume(jr.key) : DesktopNotify.livePause(jr.key)
                                    }
                                    MiniBtn {
                                        visible: jr.isDl && !jr.done && !jr.paused
                                        enabled: !jr.busy
                                        glyph: "crop_square"
                                        danger: true
                                        tip: I18n.tr("Stop")
                                        onClicked: DesktopNotify.activityStop(jr.key)
                                    }
                                    // keeps the row's rhythm when there is nothing to press
                                    Item { visible: !(jr.canPause && !jr.done) && !(jr.isDl && !jr.done && !jr.paused); width: 26; height: 26 }
                                }
                            }

                            // hairline between rows
                            Rectangle {
                                visible: jr.index < root.count - 1
                                anchors.bottom: parent.bottom
                                anchors.left: body.left
                                anchors.right: parent.right
                                anchors.rightMargin: root._pad
                                height: 1
                                color: Theme.divider_h
                            }
                        }
                    }
                }
            }
        }
    }

    component MiniBtn: AbstractButton {
        id: mb
        property string glyph: ""
        property string tip: ""
        property bool danger: false
        width: 26; height: 26
        padding: 0
        opacity: enabled ? 1 : 0.4
        HoverHandler { id: mbHover; cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: 8
            color: mb.pressed ? Theme.hover_bg_strong
                 : mbHover.hovered ? (mb.danger ? U.withAlpha(Theme.error, 0.14) : Theme.hover_bg)
                 : "transparent"
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: C.IconGlyph {
            name: mb.glyph
            fill: true
            size: 13
            glyphColor: mbHover.hovered ? (mb.danger ? Theme.error : Theme.text_strong) : Theme.on_surface_var
        }
        C.AppTooltip {
            visible: mbHover.hovered
            delay: 300
            text: mb.tip
        }
    }
}
