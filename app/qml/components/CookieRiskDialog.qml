import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.0.3 — "Before you connect a browser".
//
// Browser cookies are now strictly opt-in: the download / cut ladders no
// longer borrow a browser's signed-in session on their own (see download.py
// and cutter.py). Picking a browser in Settings opens this card first, and the
// choice only lands after the user HOLDS the confirm button — a deliberate
// gesture, so it can't be clicked through by accident.
//
// Look: a warm-to-red aurora behind a pulsing "radar" emblem, three plain-
// language risk rows, one safer-route tip, and a hold-to-confirm key whose
// face fills while it is held.
//
// v1.0.4 pass:
//   * the aurora is no longer a blurred layer clipped by a SQUARE clip (which
//     left a hard rectangular corner top-right and a visible seam where the
//     blur ended). It is two radial gradients filled into the card's own
//     rounded shape, so it fades into the surface and can never leave the
//     corners. No offscreen layer, no blur shader: lighter too.
//   * the rim is lit at the top and settles to a neutral hairline, so the card
//     sits IN the scene instead of being outlined in red on top of it.
//   * the hold key is its own control now: a tinted key that floods with the
//     danger gradient from the left as you hold (label turns white under the
//     fill), and the emblem's ring charges in step. On completion: a check,
//     a short beat, then the dialog commits.
//
//   C.CookieRiskDialog { id: cookieWarn; onConfirmed: (i) => Settings.cookieIndex = i }
//   cookieWarn.ask(index, "Chrome")
Dialog {
    id: root
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(540, (parent ? parent.width : 900) - 48)
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property int pendingIndex: -1
    property string browser: ""
    signal confirmed(int index)

    // 0..1 while the confirm key is held; 1 = confirmed
    property real hold: 0
    // true for the short "done" beat between a full hold and the commit
    property bool _done: false
    readonly property int holdMs: 1300
    readonly property bool _motion: root.visible && Tokens.appActive

    function ask(index, browserName) {
        pendingIndex = index
        browser = browserName || ""
        hold = 0
        _done = false
        open()
    }

    NumberAnimation {
        id: holdAnim
        target: root; property: "hold"
        to: 1
        duration: root.holdMs
        easing.type: Easing.Linear
        onFinished: if (root.hold >= 0.999) { root._done = true; commitBeat.restart() }
    }
    NumberAnimation {
        id: holdBack
        target: root; property: "hold"
        to: 0
        duration: 260
        easing.type: Easing.OutCubic
    }
    // the remaining hold time is fixed when the press starts (never bound:
    // a running animation must not have its duration rewritten every frame)
    function _startHold() {
        holdBack.stop()
        holdAnim.stop()
        holdAnim.duration = Math.max(1, Math.round(root.holdMs * (1 - root.hold)))
        holdAnim.start()
    }
    function _releaseHold() {
        if (root.hold >= 0.999 || root._done) return
        holdAnim.stop()
        holdBack.restart()
    }
    Timer { id: commitBeat; interval: 420; onTriggered: root._commit() }
    function _commit() {
        var i = root.pendingIndex
        root.close()
        if (i >= 0) root.confirmed(i)
    }
    onClosed: { holdAnim.stop(); holdBack.stop(); commitBeat.stop(); hold = 0; _done = false }

    Overlay.modal: C.DialogScrim { }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }

    readonly property color danger: Theme.error
    readonly property color amber: Theme.warn

    // ── glass card + drifting aurora ──
    background: Item {
        id: card
        readonly property real r: 26

        // rim: lit with the warning colour at the top, settling to a hairline
        Rectangle {
            anchors.fill: parent
            radius: card.r
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.mix(Theme.border_med, root.danger, Theme.isDark ? 0.45 : 0.35) }
                GradientStop { position: 0.30; color: Theme.border_med }
                GradientStop { position: 1.0; color: Theme.border }
            }
        }
        Rectangle {
            id: face
            anchors.fill: parent
            anchors.margins: 1
            radius: card.r - 1
            antialiasing: true
            color: Theme.surface
        }

        // aurora: radial light filled into the card's own rounded shape
        Shape {
            id: aurora
            anchors.fill: face
            preferredRendererType: Shape.CurveRenderer
            property real drift: 0      // 0..1, slow
            property real lift: 0       // 0..1, slower
            readonly property real k: Theme.isDark ? 1.0 : 0.55
            // holding warms the light up a touch
            readonly property real heat: 1 + root.hold * 0.45

            SequentialAnimation on drift {
                running: root._motion; loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 7000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 7000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on lift {
                running: root._motion; loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 5400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 5400; easing.type: Easing.InOutSine }
            }

            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: aurora.width * (0.36 + 0.22 * aurora.drift)
                    centerY: -30
                    centerRadius: 260
                    focalX: centerX; focalY: centerY; focalRadius: 0
                    GradientStop { position: 0.0; color: U.withAlpha(root.danger, 0.36 * aurora.k * aurora.heat) }
                    GradientStop { position: 0.45; color: U.withAlpha(root.danger, 0.14 * aurora.k * aurora.heat) }
                    GradientStop { position: 1.0; color: U.withAlpha(root.danger, 0.0) }
                }
                PathRectangle { x: 0; y: 0; width: aurora.width; height: aurora.height; radius: card.r - 1 }
            }
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: aurora.width * 0.86
                    centerY: -50 + 40 * aurora.lift
                    centerRadius: 200
                    focalX: centerX; focalY: centerY; focalRadius: 0
                    GradientStop { position: 0.0; color: U.withAlpha(root.amber, 0.26 * aurora.k) }
                    GradientStop { position: 0.5; color: U.withAlpha(root.amber, 0.09 * aurora.k) }
                    GradientStop { position: 1.0; color: U.withAlpha(root.amber, 0.0) }
                }
                PathRectangle { x: 0; y: 0; width: aurora.width; height: aurora.height; radius: card.r - 1 }
            }
        }

        // specular top line (kept inside the straight part of the top edge)
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - card.r * 2.4
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.26 : 0.7) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // icon + label of the hold key (drawn twice: tinted, and white under the fill)
    component HoldLabel: Row {
        id: hl
        property string glyph: ""
        property string label: ""
        property color tone: Theme.text_strong
        spacing: Tokens.space2
        C.IconGlyph {
            anchors.verticalCenter: parent.verticalCenter
            name: hl.glyph
            fill: true
            size: 17
            glyphColor: hl.tone
        }
        C.AppText {
            anchors.verticalCenter: parent.verticalCenter
            text: hl.label
            weight: Tokens.weightDemiBold
            color: hl.tone
        }
    }

    // one risk line: tinted icon tile + bold lead + plain sentence
    component RiskRow: RowLayout {
        id: rr
        property string glyph: ""
        property string lead: ""
        property string body: ""
        property color tint: Theme.error
        Layout.fillWidth: true
        spacing: Tokens.space4
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 38; implicitHeight: 38
            radius: 12
            color: U.withAlpha(rr.tint, Theme.isDark ? 0.16 : 0.11)
            border.width: 1
            border.color: U.withAlpha(rr.tint, 0.30)
            C.IconGlyph { anchors.centerIn: parent; name: rr.glyph; size: 18; glyphColor: rr.tint }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            C.AppText {
                Layout.fillWidth: true
                text: rr.lead
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontLabel
                color: Theme.text_strong
                wrapMode: Text.WordWrap
            }
            C.AppText {
                Layout.fillWidth: true
                text: rr.body
                font.pixelSize: Tokens.fontBody
                color: Theme.on_surface_var
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        C.IconButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.space3
            Layout.rightMargin: Tokens.space3
            iconName: "close"
            tip: I18n.tr("Keep cookies off")
            onClicked: root.close()
        }

        // ══ emblem: a lock with a soft glow, a resting ripple, and a ring
        //    that charges in step with the hold key ══
        Item {
            id: emblem
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -Tokens.space2
            implicitWidth: 104; implicitHeight: 104
            readonly property real cx: width / 2
            readonly property real cy: height / 2

            // light pooling under the tile (radial, no shadow layer)
            C.GlowBlob {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 8
                size: 70
                spread: 0.6
                glow: root.danger
                strength: (Theme.isDark ? 0.55 : 0.32) * (1 + root.hold * 0.6)
            }

            // resting ripple: one soft ring every 2.6 s (stops while holding)
            Rectangle {
                id: ripple
                anchors.centerIn: parent
                width: 64; height: 64; radius: 32
                color: "transparent"
                border.width: 1.5
                border.color: root.danger
                opacity: 0
                SequentialAnimation {
                    running: root._motion && root.hold === 0 && !root._done
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) { ripple.opacity = 0; ripple.scale = 1 }
                    ParallelAnimation {
                        NumberAnimation { target: ripple; property: "scale"; from: 1.0; to: 1.55; duration: 1900; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ripple; property: "opacity"; from: 0.45; to: 0.0; duration: 1900; easing.type: Easing.OutQuad }
                    }
                    PauseAnimation { duration: 700 }
                }
            }

            // charge ring: a faint track that appears while holding, and an arc
            // that fills clockwise from 12 o'clock with the hold
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: root.hold > 0 || root._done ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: U.withAlpha(root.danger, 0.20)
                    strokeWidth: 3
                    PathAngleArc { centerX: emblem.cx; centerY: emblem.cy; radiusX: 44; radiusY: 44; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root._done ? Theme.secondary_container : U.mix(root.danger, root.amber, 0.25)
                    strokeWidth: 3
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: emblem.cx; centerY: emblem.cy; radiusX: 44; radiusY: 44
                        startAngle: -90
                        sweepAngle: 360 * Math.max(0.001, root.hold)
                    }
                }
            }

            // the tile
            Rectangle {
                id: tile
                anchors.centerIn: parent
                width: 60; height: 60; radius: 20
                antialiasing: true
                scale: 1 + root.hold * 0.06
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root._done ? U.mix(Theme.secondary_container, "#FFFFFF", 0.15) : U.mix(root.danger, root.amber, 0.35) }
                    GradientStop { position: 1.0; color: root._done ? Theme.secondary_container : root.danger }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.26) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    antialiasing: true
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.22)
                }
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: root._done ? "check" : "lock"
                    fill: true
                    size: 26
                    glyphColor: "#ffffff"
                }
            }
        }

        // ══ headline ══
        C.AppText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space4
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            horizontalAlignment: Text.AlignHCenter
            text: root.browser !== ""
                  ? I18n.tr("BEFORE YOU CONNECT {b}").replace("{b}", root.browser.toUpperCase())
                  : I18n.tr("BEFORE YOU CONNECT A BROWSER")
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontCaption
            font.letterSpacing: 1.8
            color: root.danger
        }
        C.AppText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space2
            Layout.leftMargin: Tokens.space6
            Layout.rightMargin: Tokens.space6
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Your YouTube account could get banned")
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontDisplay
            font.letterSpacing: I18n.rtl ? 0 : -0.4
            color: Theme.text_strong
            wrapMode: Text.WordWrap
        }
        C.AppText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space3
            Layout.leftMargin: Tokens.space7
            Layout.rightMargin: Tokens.space7
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Cookies let the app download as your signed-in {b} session. YouTube can treat that as automated use of your account.")
                    .replace("{b}", root.browser !== "" ? root.browser : I18n.tr("browser"))
            font.pixelSize: Tokens.fontBody + 1
            lineHeight: 1.3
            color: Theme.on_surface_var
            wrapMode: Text.WordWrap
        }

        // ══ the three risks ══
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space5
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            radius: Tokens.radiusXl
            color: U.withAlpha(Theme.surface_high, Theme.isDark ? 0.75 : 0.9)
            border.width: 1
            border.color: Theme.border
            implicitHeight: riskCol.implicitHeight + Tokens.space5 * 2
            ColumnLayout {
                id: riskCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.space5
                spacing: Tokens.space4
                RiskRow {
                    glyph: "user"
                    tint: root.danger
                    lead: I18n.tr("It acts as you")
                    body: I18n.tr("Every download uses your real login. YouTube sees it as your account, not as the app.")
                }
                RiskRow {
                    glyph: "warning"
                    tint: root.danger
                    lead: I18n.tr("Bulk downloads get flagged")
                    body: I18n.tr("Heavy or repeated downloading can get the account limited, suspended or banned, channel included.")
                }
                RiskRow {
                    glyph: "key"
                    tint: root.amber
                    lead: I18n.tr("Cookies are a key to your account")
                    body: I18n.tr("They stay on this PC, but anyone who gets them can sign in as you. Never share them.")
                }
            }
        }

        // ══ the safer route ══
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space3
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            radius: Tokens.radiusLg
            color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.12 : 0.10)
            border.width: 1
            border.color: U.withAlpha(Theme.secondary_container, 0.35)
            implicitHeight: tipRow.implicitHeight + Tokens.space3 * 2
            RowLayout {
                id: tipRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space4
                spacing: Tokens.space3
                C.IconGlyph { name: "verified"; size: 18; glyphColor: Theme.secondary_container; Layout.alignment: Qt.AlignTop; Layout.topMargin: 1 }
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("Safer: sign that browser in to a spare YouTube account, never your main channel. You can switch this off any time.")
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }
            }
        }

        // ══ actions ══
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space5
            Layout.bottomMargin: Tokens.space5
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            spacing: Tokens.space3

            C.PrimaryButton {
                variant: "ghost"
                text: I18n.tr("Keep cookies off")
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                onClicked: root.close()
            }
            // the hold key (v1.0.4). A tinted key whose face floods with the
            // danger gradient from the left while it is held; the label turns
            // white where the fill has reached. AbstractButton sets `pressed`
            // for the mouse AND for a held Space key, so one handler covers both.
            AbstractButton {
                id: holdBtn
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                implicitHeight: Tokens.fieldHeight
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                onPressedChanged: pressed ? root._startHold() : root._releaseHold()
                HoverHandler { cursorShape: Qt.PointingHandCursor }

                readonly property string label: root._done
                      ? I18n.tr("Connected")
                      : root.hold > 0
                        ? I18n.tr("Keep holding…")
                        : I18n.tr("Hold to connect {b}").replace("{b}", root.browser !== "" ? root.browser : I18n.tr("browser"))
                readonly property string glyph: root._done ? "check" : "key"
                readonly property real r: Tokens.radiusMd
                // the fill never drops below a full circle-ended pill, so it
                // grows as a capsule instead of a sliver
                readonly property real fillW: root._done ? width
                      : (root.hold > 0 ? Math.max(height, width * root.hold) : 0)

                background: Rectangle {
                    radius: holdBtn.r
                    antialiasing: true
                    color: U.withAlpha(root.danger, holdBtn.hovered ? (Theme.isDark ? 0.20 : 0.14) : (Theme.isDark ? 0.14 : 0.10))
                    border.width: 1
                    border.color: U.withAlpha(root.danger, holdBtn.activeFocus ? 0.75 : 0.42)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                    // the light under the key brightens as it charges
                    C.GlowBlob {
                        z: -1   // under the key's face, never over it
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 10
                        size: parent.width * 0.7
                        spread: 0.5
                        glow: root.danger
                        strength: (Theme.isDark ? 0.30 : 0.18) * Math.min(1, root.hold * 1.4)
                        visible: root.hold > 0
                    }

                    // the fill
                    Rectangle {
                        id: holdFill
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: holdBtn.fillW
                        radius: holdBtn.r
                        antialiasing: true
                        opacity: holdBtn.fillW > 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root._done ? Theme.secondary_container : root.danger }
                            GradientStop { position: 1.0; color: root._done ? Theme.secondary_container : U.mix(root.danger, root.amber, 0.35) }
                        }
                        // bright leading edge, so the motion reads at a glance
                        Rectangle {
                            visible: !root._done
                            anchors.right: parent.right
                            anchors.rightMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3; height: parent.height - 14; radius: 1.5
                            color: Qt.rgba(1, 1, 1, 0.75)
                        }
                        // glass sheen on the fill
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            height: parent.height / 2
                            radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            }
                        }
                    }
                }

                contentItem: Item {
                    // label on the tinted face
                    HoldLabel {
                        id: labelBase
                        anchors.centerIn: parent
                        glyph: holdBtn.glyph
                        label: holdBtn.label
                        tone: U.mix(root.danger, Theme.text_strong, Theme.isDark ? 0.25 : 0.10)
                    }
                    // the same label in white, revealed only where the fill is
                    Item {
                        x: -holdBtn.leftPadding
                        y: -holdBtn.topPadding
                        width: holdBtn.fillW
                        height: holdBtn.height
                        clip: true
                        HoldLabel {
                            x: holdBtn.leftPadding + labelBase.x
                            y: holdBtn.topPadding + labelBase.y
                            glyph: holdBtn.glyph
                            label: holdBtn.label
                            tone: "#FFFFFF"
                        }
                    }
                }
            }
        }
    }
}
