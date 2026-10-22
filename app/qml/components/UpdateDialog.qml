import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.1 — In-app update ("Launch Bay").
//
// One card, five moments, all driven by `Updater` (UpdateVM):
//   available    hero + what's new + Download & install
//   downloading  a big counting percentage, a lit progress rail, live stats
//   ready        verified tick, 5-second countdown, then restart into Setup
//   installing   the app hands over and closes; Setup reopens it
//   error        honest message, Retry / Open on GitHub
//
// Look: a dark glass card with a slow red aurora drifting behind the hero,
// the logo inside a rotating conic orbit, and a version "from → to" capsule.
Dialog {
    id: root
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, (parent ? parent.width : 900) - 64)
    padding: 0
    closePolicy: Updater.state === "installing" ? Popup.NoAutoClose
                                                : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

    readonly property string st: Updater.state
    readonly property bool _motion: root.visible && Tokens.appActive
    property int countdown: 5

    function present() {
        countdown = 5
        open()
    }

    // auto-restart once the installer is downloaded and verified
    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        running: root.opened && root.st === "ready" && Updater.packaged
        onTriggered: {
            if (root.countdown > 1) root.countdown--
            else { stop(); Updater.installNow() }
        }
    }
    onStChanged: if (st === "ready") countdown = 5

    Overlay.modal: C.DialogScrim { }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }

    // ── glass card + drifting aurora ──
    background: Rectangle {
        radius: 26
        color: Theme.surface
        border.width: 1
        border.color: U.withAlpha(Theme.primary, 0.22)
        clip: true

        Item {
            id: aurora
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
            Rectangle {
                id: blobA
                width: 300; height: 300; radius: 150
                color: U.withAlpha(Theme.primary, Theme.isDark ? 0.55 : 0.30)
                y: -150
                x: parent.width * 0.5 - 220
                SequentialAnimation on x {
                    running: root._motion; loops: Animation.Infinite
                    NumberAnimation { to: aurora.width * 0.5 - 120; duration: 7000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: aurora.width * 0.5 - 260; duration: 7000; easing.type: Easing.InOutSine }
                }
            }
            Rectangle {
                width: 220; height: 220; radius: 110
                color: U.withAlpha(U.mix(Theme.primary, "#ff9a3c", 0.45), Theme.isDark ? 0.35 : 0.18)
                y: -120
                x: aurora.width - 160
                SequentialAnimation on y {
                    running: root._motion; loops: Animation.Infinite
                    NumberAnimation { to: -70; duration: 5200; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -130; duration: 5200; easing.type: Easing.InOutSine }
                }
            }
        }
        // fine top highlight: the glass edge
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 1
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.28 : 0.6) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // close
        C.IconButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.space3
            Layout.rightMargin: Tokens.space3
            iconName: "close"
            visible: root.st !== "installing"
            onClicked: root.close()
        }

        // ══ hero ══
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            spacing: Tokens.space3

            // logo in a rotating conic orbit
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 104; implicitHeight: 104

                Shape {
                    id: orbit
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    RotationAnimation on rotation {
                        running: root._motion
                        from: 0; to: 360
                        duration: root.st === "downloading" ? 2200 : 9000
                        loops: Animation.Infinite
                    }
                    ShapePath {
                        startX: 104; startY: 52
                        strokeWidth: -1
                        fillRule: ShapePath.OddEvenFill
                        fillGradient: ConicalGradient {
                            centerX: 52; centerY: 52; angle: 0
                            GradientStop { position: 0.00; color: U.withAlpha(Theme.primary, 0.0) }
                            GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, 0.15) }
                            GradientStop { position: 0.92; color: Theme.primary }
                            GradientStop { position: 1.00; color: U.withAlpha(Theme.primary, 0.0) }
                        }
                        PathAngleArc { centerX: 52; centerY: 52; radiusX: 52; radiusY: 52; startAngle: 0; sweepAngle: 360 }
                        PathMove { x: 52 + 49; y: 52 }
                        PathAngleArc { centerX: 52; centerY: 52; radiusX: 49; radiusY: 49; startAngle: 0; sweepAngle: 360 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 84; height: 84; radius: 26
                    color: Theme.isDark ? "#0e0e11" : "#16161a"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                    Image {
                        anchors.centerIn: parent
                        width: 60; height: 60
                        source: Updater.logoUrl
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                    }
                }
            }

            C.AppText {
                Layout.alignment: Qt.AlignHCenter
                text: root.st === "ready" ? I18n.tr("READY TO INSTALL")
                      : root.st === "downloading" ? I18n.tr("DOWNLOADING")
                      : root.st === "installing" ? I18n.tr("INSTALLING")
                      : root.st === "error" ? I18n.tr("SOMETHING WENT WRONG")
                      : I18n.tr("NEW VERSION")
                mono: true
                weight: Tokens.weightExtraBold
                font.pixelSize: 11
                font.letterSpacing: 2.2
                color: root.st === "error" ? Theme.error : Theme.primary
            }
            C.AppText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("YouTube Hunter {v} is here").replace("{v}", Updater.latestVersion)
                weight: Tokens.weightExtraBold
                font.pixelSize: 26
                color: Theme.text_strong
                wrapMode: Text.Wrap
            }

            // version capsule: from → to · date · size
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.space2
                LayoutMirroring.enabled: false
                Rectangle {
                    height: 28; radius: 14
                    width: capRow.implicitWidth + 22
                    color: U.withAlpha(Theme.on_surface, 0.06)
                    border.width: 1; border.color: Theme.border
                    Row {
                        id: capRow
                        anchors.centerIn: parent
                        spacing: 8
                        C.AppText { text: "v" + Updater.currentVersion; mono: true; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; anchors.verticalCenter: parent.verticalCenter }
                        C.IconGlyph {
                            name: "arrow_forward"; size: 13; glyphColor: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on x {
                                running: root._motion; loops: Animation.Infinite
                                NumberAnimation { from: 0; to: 3; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 3; to: 0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }
                        C.AppText { text: "v" + Updater.latestVersion; mono: true; weight: Tokens.weightExtraBold; font.pixelSize: Tokens.fontCaption; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Rectangle {
                    visible: Updater.published !== "" || Updater.sizeText !== ""
                    height: 28; radius: 14
                    width: metaLbl.implicitWidth + 22
                    color: U.withAlpha(Theme.on_surface, 0.06)
                    border.width: 1; border.color: Theme.border
                    C.AppText {
                        id: metaLbl
                        anchors.centerIn: parent
                        text: [Updater.published, Updater.sizeText].filter(function (x) { return x !== "" }).join("  ·  ")
                        mono: true; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var
                    }
                }
            }
        }

        // ══ what's new ══
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space5
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            visible: root.st === "available" || root.st === "error"
            implicitHeight: Math.min(210, notesCol.implicitHeight + Tokens.space4 * 2)
            radius: 18
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.04 : 0.03)
            border.width: 1
            border.color: Theme.border
            clip: true

            Flickable {
                anchors.fill: parent
                anchors.margins: Tokens.space4
                contentHeight: notesCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: notesCol
                    width: parent.width
                    spacing: Tokens.space2
                    RowLayout {
                        spacing: Tokens.space2
                        C.IconGlyph { name: "sparkling"; size: 15; fill: true; glyphColor: Theme.primary }
                        C.AppText { text: I18n.tr("What's new"); weight: Tokens.weightExtraBold; color: Theme.text_strong }
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        text: Updater.notes
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        color: Theme.on_surface
                        font.pixelSize: Tokens.fontBody
                        lineHeight: 1.25
                        onLinkActivated: (link) => Qt.openUrlExternally(link)
                    }
                }
            }
        }

        // ══ download progress ══
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space5
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            visible: root.st === "downloading"
            spacing: Tokens.space3

            RowLayout {
                Layout.fillWidth: true
                LayoutMirroring.enabled: false
                C.AppText {
                    id: pct
                    property real shown: 0
                    Behavior on shown { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Component.onCompleted: shown = Qt.binding(function () { return Updater.progress * 100 })
                    text: Math.floor(shown) + "%"
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: 44
                    color: Theme.text_strong
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    spacing: 2
                    C.AppText { Layout.alignment: Qt.AlignRight; text: Updater.receivedText; mono: true; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface }
                    C.AppText {
                        Layout.alignment: Qt.AlignRight
                        text: [Updater.speedText, Updater.etaText !== "" ? I18n.tr("{t} left").replace("{t}", Updater.etaText) : ""]
                              .filter(function (x) { return x !== "" }).join("  ·  ")
                        mono: true; font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var
                    }
                }
            }

            // the rail: track, lit fill, travelling shimmer, glowing head
            Item {
                Layout.fillWidth: true
                implicitHeight: 12
                LayoutMirroring.enabled: false
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: U.withAlpha(Theme.on_surface, 0.08)
                }
                Rectangle {
                    id: fillBar
                    height: parent.height
                    radius: 6
                    width: Math.max(height, parent.width * Updater.progress)
                    Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    clip: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.mix(Theme.primary, "#000000", 0.35) }
                        GradientStop { position: 1.0; color: U.mix(Theme.primary, "#ff9a3c", 0.25) }
                    }
                    Rectangle {
                        width: 70; height: parent.height
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.35) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                        }
                        NumberAnimation on x {
                            running: root._motion && root.st === "downloading"
                            from: -70; to: fillBar.width; duration: 1300; loops: Animation.Infinite
                        }
                    }
                }
                Rectangle {
                    width: 18; height: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    x: fillBar.width - width / 2 - 3
                    color: U.withAlpha(Theme.primary, 0.35)
                    layer.enabled: true
                    layer.effect: MultiEffect { blurEnabled: true; blur: 0.8; blurMax: 16 }
                }
            }
        }

        // ══ ready / installing ══
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space5
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            visible: root.st === "ready" || root.st === "installing"
            spacing: Tokens.space4

            Item {
                implicitWidth: 52; implicitHeight: 52
                Rectangle {
                    id: tick
                    anchors.fill: parent
                    radius: 26
                    color: U.withAlpha(Theme.secondary_container, 0.16)
                    border.width: 2
                    border.color: Theme.secondary_container
                    scale: root.st === "ready" ? 1 : 0.9
                    Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: root.st === "installing" ? "autorenew" : "check"
                        size: 24; fill: true
                        glyphColor: Theme.secondary_container
                        RotationAnimation on rotation {
                            running: root.st === "installing" && root._motion
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                C.AppText {
                    text: root.st === "installing" ? I18n.tr("Installing the update…")
                                                   : I18n.tr("Downloaded and verified")
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                }
                C.AppText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    text: root.st === "installing"
                          ? I18n.tr("YouTube Hunter will close and reopen by itself in a moment.")
                          : Updater.packaged
                            ? I18n.tr("Restarting in {n}s to install. Your data and settings stay as they are.").replace("{n}", root.countdown)
                            : I18n.tr("Running from source: the installer will open as a normal setup wizard.")
                }
            }
        }

        // ══ error ══
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space4
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            visible: root.st === "error"
            implicitHeight: errTxt.implicitHeight + Tokens.space3 * 2
            radius: 14
            color: U.withAlpha(Theme.error, 0.09)
            border.width: 1
            border.color: U.withAlpha(Theme.error, 0.35)
            C.AppText {
                id: errTxt
                anchors.fill: parent
                anchors.margins: Tokens.space3
                text: Updater.error
                wrapMode: Text.Wrap
                color: Theme.on_surface
                font.pixelSize: Tokens.fontCaption
            }
        }

        // ══ actions ══
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Tokens.space6
            Layout.topMargin: Tokens.space5
            spacing: Tokens.space3

            C.PrimaryButton {
                variant: "ghost"
                iconName: "open_in_new"
                text: I18n.tr("GitHub")
                visible: root.st === "available" || root.st === "error"
                onClicked: Updater.openReleasePage()
            }
            Item { Layout.fillWidth: true }
            C.PrimaryButton {
                variant: "ghost"
                visible: root.st !== "installing"
                text: root.st === "downloading" ? I18n.tr("Cancel") : I18n.tr("Later")
                onClicked: {
                    if (root.st === "downloading") Updater.cancelDownload()
                    else { countTimer.stop(); root.close() }
                }
            }
            C.PrimaryButton {
                visible: root.st === "available" || root.st === "error"
                iconName: root.st === "error" ? "refresh" : "download"
                text: root.st === "error" ? I18n.tr("Try again") : I18n.tr("Download & install")
                implicitHeight: 46
                onClicked: Updater.latestVersion === "" ? Updater.checkNow() : Updater.startDownload()
            }
            C.PrimaryButton {
                visible: root.st === "ready"
                iconName: "restart_alt"
                text: Updater.packaged ? I18n.tr("Restart now") : I18n.tr("Open installer")
                implicitHeight: 46
                onClicked: { countTimer.stop(); Updater.installNow() }
            }
        }
    }
}
