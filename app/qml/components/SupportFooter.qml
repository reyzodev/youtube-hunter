import QtQuick
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v1.1.3 — the rail's sign-off line, under "All systems normal".
//
//   expanded:   Made with ♥                    ( ☕ Donate )
//   collapsed:                ( ☕ )
//
// The heart beats on its own (C.HeartBeat). Hover the line and it races;
// hover Donate and the cup steams, a sheen crosses the pill and the heart
// races with it, so the two read as one gesture.
//
// v3.52 — the pill is wired to App.openDonate(), which opens the support link
// from config.json's `donate_url` in the browser. Until that key is filled in
// the click is a no-op, so the link is the one thing left to set.
Item {
    id: root
    property bool collapsed: false
    property string donateUrl: ""
    signal donateClicked()

    readonly property color hot: U.mix(Theme.primary, "#FF6FA5", 0.55)
    readonly property color deep: Theme.primary
    readonly property bool _lineHot: lineHover.hovered || donate.hot

    implicitHeight: 34
    height: 34
    // v1.1.4: the line reserves the room it really needs, so the rail's
    // layout can never squeeze the pill narrower than its own content
    implicitWidth: root.collapsed ? 34 + 8
                                  : sig.implicitWidth + 12 + donate.width + 8

    HoverHandler { id: lineHover }

    // ── "Made with ♥" ──
    Row {
        id: sig
        visible: !root.collapsed
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        C.AppText {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Made with")
            font.pixelSize: Tokens.fontCaption - 1
            weight: Tokens.weightMedium
            font.letterSpacing: I18n.lang === "fa" ? 0 : 0.5
            color: root._lineHot ? Theme.on_surface : Theme.on_surface_var
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        }
        C.HeartBeat {
            anchors.verticalCenter: parent.verticalCenter
            size: 13
            racing: root._lineHot
            hot: root.hot
            deep: root.deep
        }
    }

    // ── Donate ──
    Rectangle {
        id: donate
        readonly property bool hot: donateArea.containsMouse
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: root.collapsed ? undefined : parent.right
        // room for the 1.03 hover scale + the 4 px bloom, so nothing is
        // cut off by the rail's edge
        anchors.rightMargin: root.collapsed ? 0 : 4
        anchors.horizontalCenter: root.collapsed ? parent.horizontalCenter : undefined
        // v1.1.4 fix — "the Donate button doesn't fit its box": the pill was
        // sized from the Row's implicitWidth, which was read before the label's
        // font family/weight resolved (FontBridge swaps it after creation) and,
        // with NativeRendering on a scaled display, the drawn glyphs ran wider
        // than the measured ones. Cup + label spilled out of both ends of the
        // pill. Now the width is computed from explicit metrics of the exact
        // font the label uses, rounded UP, plus fixed padding on each side.
        readonly property int padX: 12
        readonly property real labelW: root.collapsed ? 0
            : Math.ceil(Math.max(labelMetrics.advanceWidth,
                                 labelMetrics.tightBoundingRect.width,
                                 donateLabel.implicitWidth))
        height: root.collapsed ? 34 : 28
        width: root.collapsed ? 34
                              : Math.ceil(padX + cup.width + donateRow.spacing + labelW + padX)
        radius: height / 2
        antialiasing: true
        scale: donateArea.pressed ? 0.95 : hot ? 1.03 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: U.withAlpha(root.hot, donate.hot ? 0.24 : 0.14) }
            GradientStop { position: 1.0; color: U.withAlpha(root.deep, donate.hot ? 0.16 : 0.07) }
        }
        border.width: 1
        border.color: U.withAlpha(root.hot, donate.hot ? 0.62 : 0.30)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

        // soft bloom behind the pill on hover (opacity only, no colour midpoint)
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -4
            radius: height / 2
            color: U.withAlpha(root.hot, Theme.isDark ? 0.16 : 0.10)
            opacity: donate.hot ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }

        // sheen that crosses the pill when the pointer lands
        C.RoundClip {
            anchors.fill: parent
            radius: donate.radius
            active: sheen.t > 0 && sheen.t < 1
            LayoutMirroring.enabled: false
            Rectangle {
                id: sheen
                property real t: 0
                width: 26
                height: parent.height * 1.8
                y: -parent.height * 0.4
                rotation: 20
                x: -width + (parent.width + width * 2) * t
                visible: t > 0 && t < 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.22 : 0.45) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }
        NumberAnimation {
            id: sheenAnim
            target: sheen; property: "t"
            from: 0; to: 1
            duration: 720
            easing.type: Easing.InOutCubic
        }
        onHotChanged: if (hot) sheenAnim.restart()

        TextMetrics {
            id: labelMetrics
            font: donateLabel.font
            text: donateLabel.text
        }

        Row {
            id: donateRow
            // explicit size + centred: the content box is exactly what the
            // pill was sized for, so it can't drift off-centre either
            anchors.centerIn: parent
            width: cup.width + (root.collapsed ? 0 : spacing + donate.labelW)
            height: Math.max(cup.height, donateLabel.implicitHeight)
            spacing: 6

            // coffee cup, with steam that rises while hovered
            Item {
                id: cup
                anchors.verticalCenter: parent.verticalCenter
                width: 15; height: 15
                Shape {
                    width: 24; height: 24
                    anchors.centerIn: parent
                    scale: cup.width / 24
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: 2
                        joinStyle: ShapePath.RoundJoin
                        capStyle: ShapePath.RoundCap
                        fillColor: U.withAlpha(root.hot, 0.28)
                        PathSvg { path: "M4.5 9.5h11v4a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5z" }
                    }
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathSvg { path: "M15.5 10.8h1.4a2.3 2.3 0 0 1 0 4.6h-1.4" }
                    }
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathSvg { path: "M4 21.5h12" }
                    }
                }
                // steam
                Shape {
                    id: steam
                    width: 24; height: 24
                    anchors.centerIn: parent
                    preferredRendererType: Shape.CurveRenderer
                    property real t: 0
                    scale: cup.width / 24
                    opacity: donate.hot ? (0.35 + 0.65 * Math.sin(Math.PI * t)) : 0
                    transform: Translate { y: -2.5 * steam.t }
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                    ShapePath {
                        strokeColor: root.hot
                        strokeWidth: 1.8
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathSvg { path: "M8 2.5c-1 1.1 1 2.1 0 3.6M12 2.5c-1 1.1 1 2.1 0 3.6" }
                    }
                    NumberAnimation on t {
                        running: donate.hot && root.visible
                        loops: Animation.Infinite
                        from: 0; to: 1
                        duration: 1100
                        easing.type: Easing.InOutSine
                    }
                }
            }

            C.AppText {
                id: donateLabel
                visible: !root.collapsed
                anchors.verticalCenter: parent.verticalCenter
                width: donate.labelW
                horizontalAlignment: Text.AlignHCenter
                // QtRendering: glyphs drawn at exactly the measured width
                // (NativeRendering hints to device pixels and grows on 125 %+)
                renderType: Text.QtRendering
                text: I18n.tr("Donate")
                font.pixelSize: Tokens.fontCaption - 1
                weight: Tokens.weightBold
                font.letterSpacing: I18n.lang === "fa" ? 0 : 0.3
                color: Theme.isDark ? Qt.lighter(root.hot, 1.18) : Qt.darker(root.hot, 1.15)
            }
        }

        MouseArea {
            id: donateArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.donateClicked()
        }

        C.AppTooltip {
            visible: donate.hot
            delay: 450
            text: I18n.tr("Support YouTube Hunter")
            preferAbove: true
        }
    }
}
