import QtQuick
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// v3.16-p4 — the cover of one finished clip on the Cutter page.
//
// A frame of film that has been cut out: the clip's own frame sits between two
// sprocket bands, a dashed "cut here" line runs along its top and bottom
// edges, and a small pair of scissors rides the top line. On hover the
// scissors glide across (the cut), the frame eases in a touch and a play disc
// fades up. With no frame yet (still being grabbed, an audio clip, a missing
// file) it falls back to the old dark film tile with the scissors centred, so
// the card never shows an empty box.
//
//   ┌──┬────────────────────┬──┐
//   │▫ │ ✂ - - - - - - - -  │ ▫│
//   │▫ │      [ frame ]     │ ▫│
//   │▫ │ - - - - - - - 1:42 │ ▫│
//   └──┴────────────────────┴──┘
Item {
    id: root

    // file:// url of the clip's cached frame ("" while it is being made)
    property string coverUrl: ""
    // image://thumbs/<id> of the source video's YouTube thumbnail (fallback)
    property string fallbackId: ""
    property bool exists: true
    property bool isAudio: false
    property bool hovered: false
    property string durationText: ""

    signal clicked()

    // drawn the same way in both UI directions (the frame is a picture, not
    // text — and the badge/lines are placed by hand)
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    implicitWidth: 116
    implicitHeight: 66

    readonly property int _band: 9
    readonly property string _src: !root.exists ? ""
                                   : root.coverUrl !== "" ? root.coverUrl
                                   : root.fallbackId !== "" ? "image://thumbs/" + root.fallbackId : ""
    readonly property bool _hasImage: _src !== "" && img.status === Image.Ready
    readonly property color _accent: root.exists ? Theme.primary : Theme.warn

    // rounded crop for everything inside the frame
    Rectangle {
        id: frameMask
        anchors.fill: parent
        radius: Tokens.radiusSm
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frameMask
            saturation: root.exists ? 0 : -1
        }

        // film base
        Rectangle { anchors.fill: parent; color: "#0c0c10" }

        // the picture window, between the sprocket bands
        Item {
            id: picWindow
            anchors.fill: parent
            anchors.leftMargin: root._band
            anchors.rightMargin: root._band
            clip: true

            Image {
                id: img
                anchors.fill: parent
                source: root._src
                sourceSize.width: 240
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                opacity: status === Image.Ready ? (root.exists ? 1 : 0.45) : 0
                scale: root.hovered ? 1.08 : 1.0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                Behavior on scale { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            }

            // soft vignette so the dashes + badge read on any frame
            Rectangle {
                anchors.fill: parent
                visible: root._hasImage
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.42) }
                    GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                }
            }

            // a faint accent wash when there is no picture: keeps the tile alive
            Rectangle {
                anchors.fill: parent
                visible: !root._hasImage
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(root._accent, 0.10) }
                    GradientStop { position: 1.0; color: U.withAlpha(root._accent, 0.02) }
                }
            }
        }

        // sprocket bands
        Repeater {
            model: 2
            Rectangle {
                required property int index
                width: root._band
                height: root.height
                x: index === 0 ? 0 : root.width - root._band
                color: "#0c0c10"
                Column {
                    anchors.centerIn: parent
                    spacing: 5
                    Repeater {
                        model: Math.max(3, Math.floor((root.height - 6) / 10))
                        Rectangle {
                            width: 4; height: 5; radius: 1
                            color: root.hovered ? U.withAlpha(root._accent, 0.55) : Qt.rgba(1, 1, 1, 0.18)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        }
                    }
                }
            }
        }
    }

    // ── the "cut here" lines ──
    // (inline components do not see this file's ids, so colour comes in)
    component CutLine: Row {
        id: cl
        property real lineWidth: 0
        property color dashColor: "white"
        spacing: 3
        LayoutMirroring.enabled: false
        Repeater {
            model: Math.max(0, Math.floor((cl.lineWidth + 3) / 7))
            Rectangle {
                width: 4; height: 1.5; radius: 0.75
                color: cl.dashColor
            }
        }
    }
    readonly property color _dash: U.withAlpha(root._hasImage ? Qt.rgba(1, 1, 1, 1) : root._accent,
                                               root.hovered ? 0.85 : 0.45)
    CutLine {
        id: topLine
        x: root._band + 4
        y: 8
        lineWidth: root.width - root._band * 2 - 8
        dashColor: root._dash
    }
    CutLine {
        x: root._band + 4
        y: root.height - 6
        // stops short of the duration badge at the trailing end
        lineWidth: root.width - root._band * 2 - 8 - (durBadge.visible ? durBadge.width + 4 : 0)
        dashColor: root._dash
    }

    // scissors riding the top line — the signature move: on hover it "cuts"
    // across the frame and stays at the far end until the pointer leaves
    Rectangle {
        id: blade
        readonly property real _from: root._band + 2
        readonly property real _to: root.width - root._band - width - 2
        width: 16; height: 16; radius: 8
        y: topLine.y - height / 2 + 1
        x: root.hovered && root._hasImage ? _to : _from
        color: Qt.rgba(0.05, 0.05, 0.07, 0.88)
        border.width: 1
        border.color: U.withAlpha(root._accent, 0.6)
        visible: root._hasImage
        Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.InOutCubic } }
        IconGlyph {
            anchors.centerIn: parent
            name: "scissors"
            size: 10
            fill: true
            glyphColor: root._accent
        }
    }

    // fallback mark: no picture yet → the classic centred scissors
    IconGlyph {
        anchors.centerIn: parent
        visible: !root._hasImage
        name: !root.exists ? "warning" : root.isAudio ? "music" : "scissors"
        size: 20
        fill: root.hovered
        glyphColor: root._accent
    }

    // clip length
    Rectangle {
        id: durBadge
        visible: root.durationText !== "" && root._hasImage
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root._band + 3
        anchors.bottomMargin: 3
        radius: 4
        color: Qt.rgba(0, 0, 0, 0.72)
        implicitWidth: durText.implicitWidth + 8
        implicitHeight: 16
        LayoutMirroring.enabled: false
        AppText {
            id: durText
            anchors.centerIn: parent
            text: root.durationText
            mono: true
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontMicro
            color: "#ffffff"
        }
    }

    // play disc on hover
    Rectangle {
        anchors.centerIn: parent
        width: 26; height: 26; radius: 13
        visible: root._hasImage && root.exists
        opacity: root.hovered ? 1 : 0
        scale: root.hovered ? 1 : 0.8
        color: U.withAlpha(Theme.primary, 0.92)
        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
        Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack } }
        IconGlyph {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 1
            name: "play_arrow"; fill: true; size: 15
            glyphColor: "#ffffff"
        }
    }

    // thin frame edge, lit on hover
    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: "transparent"
        border.width: 1
        border.color: root.hovered ? U.withAlpha(root._accent, 0.55) : Qt.rgba(1, 1, 1, 0.06)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.exists
        cursorShape: root.exists ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
