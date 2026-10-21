import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import NicheScope
import "." as C
import "../Utils.js" as U

// v16 "Result banner" — the after-run summary card.
//
// Replaces the bare "● ✓ 100 of 100 results match your filters." mono line and
// the flat green "Archived under …" strip with one composed card:
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │ [✓]  100 of 100 results match your filters          ( 100% ) │
//   │      ┌ 🗄 Archived under "egg" · 100 new, 0 refreshed ┐  [⚡] │
//   └──────────────────────────────────────────────────────────────┘
//
//   * kind: "ok" | "success" | "warn" | "error" | "info" | "muted"
//   * text: the headline (a leading ✓ / ✔ / • is stripped — the icon says it)
//   * note / noteIcon / noteKind: an optional second line rendered as a chip
//   * showRatio: for "ok" headlines carrying "<a> … <b>", draw a match ring
//   * trailing: extra items on the right (e.g. a quota pill)
Rectangle {
    id: root
    property string kind: "info"
    property string text: ""
    property string note: ""
    property string noteIcon: "archive"
    property string noteKind: "ok"
    property bool showRatio: true
    default property alias trailing: trailSlot.data

    readonly property color tone: _toneOf(kind)
    function _toneOf(k) {
        return k === "error" ? Theme.error
             : k === "warn" ? Theme.warn
             : (k === "ok" || k === "success") ? Theme.secondary_container
             : k === "muted" ? Theme.outline
             : Theme.primary
    }
    readonly property string _icon: kind === "error" ? "error"
                                  : kind === "warn" ? "warning"
                                  : (kind === "ok" || kind === "success") ? "check_circle"
                                  : "info"
    readonly property string headline: (text || "").replace(/^[\s✓✔•●]+/, "").replace(/\.\s*$/, "")

    // "<a> of <b>" → ratio (only for good-news headlines)
    readonly property var _nums: {
        var m = (root.text || "").match(/(\d[\d,]*)\D+?(\d[\d,]*)/)
        if (!m) return null
        var a = parseInt(m[1].replace(/,/g, "")), b = parseInt(m[2].replace(/,/g, ""))
        if (!(b > 0) || a > b) return null
        return { a: a, b: b }
    }
    readonly property bool _ratio: showRatio && (kind === "ok" || kind === "success") && _nums !== null
    readonly property real _frac: _ratio ? _nums.a / _nums.b : 0

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 14 * 2
    radius: Tokens.radiusLg + 1
    antialiasing: true
    color: Theme.isDark ? U.mix(Theme.surface_low, Theme.background, 0.2) : Theme.panel_bg
    border.width: 1
    border.color: U.mix(Theme.border, tone, 0.28)
    clip: true

    // tone wash from the reading edge
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        rotation: I18n.rtl ? 180 : 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: U.withAlpha(root.tone, Theme.isDark ? 0.14 : 0.08) }
            GradientStop { position: 0.55; color: U.withAlpha(root.tone, 0.0) }
        }
    }
    // specular top edge
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 40
        height: 1
        color: Theme.glass_hi
    }

    // entrance whenever the headline changes
    property real _in: 1
    onHeadlineChanged: if (headline !== "") enter.restart()
    NumberAnimation { id: enter; target: root; property: "_in"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
    opacity: 0.4 + 0.6 * _in
    transform: Translate { y: (1 - root._in) * 6 }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: Tokens.space3

        // icon tile
        Rectangle {
            Layout.alignment: root.note !== "" ? Qt.AlignTop : Qt.AlignVCenter
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: 12
            color: U.withAlpha(root.tone, Theme.isDark ? 0.16 : 0.12)
            border.width: 1
            border.color: U.withAlpha(root.tone, 0.32)
            scale: 0.6 + 0.4 * root._in
            C.IconGlyph {
                anchors.centerIn: parent
                name: root._icon
                fill: true
                size: 19
                glyphColor: root.tone
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            C.AppText {
                Layout.fillWidth: true
                text: root.headline
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontBody + 1
                color: Theme.text_strong
                wrapMode: Text.Wrap
            }

            // note chip
            Rectangle {
                id: noteChip
                visible: root.note !== ""
                Layout.maximumWidth: parent.width
                implicitWidth: noteRow.implicitWidth + 20
                implicitHeight: noteRow.implicitHeight + 10
                radius: 9
                readonly property color nt: root._toneOf(root.noteKind)
                color: U.withAlpha(nt, Theme.isDark ? 0.10 : 0.07)
                border.width: 1
                border.color: U.withAlpha(nt, 0.24)
                RowLayout {
                    id: noteRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 7
                    C.IconGlyph {
                        name: root.noteIcon; fill: true; size: 13
                        glyphColor: noteChip.nt
                        Layout.alignment: Qt.AlignVCenter
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        text: root.note
                        weight: Tokens.weightMedium
                        font.pixelSize: Tokens.fontCaption
                        color: U.mix(noteChip.nt, Theme.text_strong, Theme.isDark ? 0.35 : 0.2)
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // match ring
        Item {
            id: ringBox
            visible: root._ratio
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 46
            Layout.preferredHeight: 46
            property real sweep: 360 * root._frac * root._in
            Shape {
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    strokeColor: U.withAlpha(root.tone, 0.16)
                    strokeWidth: 4
                    fillColor: "transparent"
                    PathAngleArc { centerX: 23; centerY: 23; radiusX: 19; radiusY: 19; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: root.tone
                    strokeWidth: 4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 23; centerY: 23; radiusX: 19; radiusY: 19; startAngle: -90; sweepAngle: ringBox.sweep }
                }
            }
            C.AppText {
                anchors.centerIn: parent
                text: Math.round(root._frac * 100) + "%"
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: 11
                color: root.tone
                LayoutMirroring.enabled: false
            }
        }

        Row {
            id: trailSlot
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.space2
            visible: children.length > 0
        }
    }
}
