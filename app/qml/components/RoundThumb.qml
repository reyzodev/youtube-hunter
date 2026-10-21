import QtQuick
import QtQuick.Effects
import NicheScope

// A rounded image tile (thumbnail / picture source) with a calm placeholder
// glyph while it loads or when there is no image at all.
Item {
    id: root
    property string source: ""
    property real radius: Tokens.radiusSm
    property string glyph: "movie"
    property string badge: ""          // e.g. a duration, bottom-end corner

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.surface_highest
        IconGlyph {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            name: root.glyph
            size: Math.max(14, Math.min(22, root.height * 0.42))
            glyphColor: Theme.outline
        }
    }
    Image {
        id: img
        anchors.fill: parent
        visible: false
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: Math.max(64, root.width * 2)
    }
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: root.radius; color: "white" }
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        opacity: img.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
    }
    Rectangle {
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 3
        width: badgeText.implicitWidth + 8
        height: 16
        radius: 4
        color: Qt.rgba(0, 0, 0, 0.78)
        LayoutMirroring.enabled: false
        AppText {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge
            mono: true
            font.pixelSize: Tokens.fontMicro
            color: "white"
        }
    }
}
