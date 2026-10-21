import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// Download-quality picker — v14 "Ladder" redesign.
//
// One instance serves a whole page: a card emits downloadRequested and the page
// calls openFor(videoId, title, thumbId). Public API is unchanged.
//
// What changed in v14, and why:
//
//  * THE LADDER. The six near-identical rows are gone. Every quality is now a
//    column whose bar is as tall as the file it makes (√size, so 360p is still
//    visible next to 4K). The size difference — the number that actually
//    decides the pick — reads at a glance instead of being parsed row by row.
//
//  * "Best available" folds into the crown. Once the probe has the real list,
//    "best" is the same file as the top resolution, so the duplicate row is
//    hidden and the top column wears the crown and is pre-selected. When the
//    probe failed (generic ladder) the "Best" column stays, because then it is
//    the only honest way to say "whatever the top is".
//
//  * The video is the header: its blurred thumbnail is the backdrop, so the
//    dialog says WHICH video before it asks HOW.
//
//  * Keyboard: ← / → walk the ladder, Enter downloads, Esc closes.
//
// Everything that matters functionally is kept exactly: the probe (real
// formats only), skeletons while probing, the per-video "not confirmed"
// warning after a failed probe, the container/codec switch that follows the
// selected row, the Deno check, and presetIndex being handed to the VM.
Dialog {
    id: root
    modal: true

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(640, parent ? parent.width - 48 : 640)
    padding: 0

    Overlay.modal: C.DialogScrim { }

    // Arrival: rise + settle with a hint of spring — this is a genuine arrival.
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast }
        NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: Tokens.durFast }
    }

    // The ViewModel that receives startDownload (Niche by default; Downloads and
    // Archive point it at their own VM).
    property var target: Niche

    property string videoId: ""
    property string videoTitle: ""
    property string thumbId: ""
    // Index into `rows` (NOT into the ladder) — so presetIndex lookups stay
    // trivially correct whatever order the ladder draws in.
    property int selected: 0
    property bool _seeded: false

    readonly property var rows: QualityProbe.options

    function openFor(vid, title, thumb) {
        videoId = vid
        videoTitle = title
        thumbId = thumb
        selected = 0
        _seeded = false
        QualityProbe.start(vid)
        if (!QualityProbe.busy) _seed()
        open()
    }

    // ── the ladder: display order + which column wears the crown ─────────
    // Probe rows arrive best-first, highest resolution first, audio last. The
    // ladder draws video ascending (small → big) so bar heights climb, then a
    // gap, then audio.
    readonly property var ladder: {
        var rs = root.rows || []
        var vids = [], aud = [], best = -1
        for (var i = 0; i < rs.length; i++) {
            var r = rs[i]
            if (r.isAudio) aud.push(i)
            else if (r.key === "best") best = i
            else vids.push(i)
        }
        vids.reverse()
        var foldBest = QualityProbe.probed && vids.length > 0
        var out = []
        for (var j = 0; j < vids.length; j++)
            out.push({ idx: vids[j], crown: foldBest && j === vids.length - 1, gap: false })
        if (best >= 0 && !foldBest)
            out.push({ idx: best, crown: true, gap: false })
        for (var k = 0; k < aud.length; k++)
            out.push({ idx: aud[k], crown: false, gap: k === 0 && out.length > 0 })
        return out
    }
    readonly property int _crownIdx: {
        for (var i = 0; i < ladder.length; i++)
            if (ladder[i].crown) return ladder[i].idx
        return ladder.length > 0 ? ladder[0].idx : 0
    }
    readonly property int _ladderPos: {
        for (var i = 0; i < ladder.length; i++)
            if (ladder[i].idx === root.selected) return i
        return -1
    }
    readonly property bool _selectedIsCrown: _ladderPos >= 0 && ladder[_ladderPos].crown
    readonly property real _maxBytes: {
        var m = 0
        var rs = root.rows || []
        for (var i = 0; i < rs.length; i++) m = Math.max(m, rs[i].sizeBytes || 0)
        return m
    }

    function _seed() {
        root.selected = root._crownIdx
        root._seeded = true
    }
    function _step(d) {
        if (QualityProbe.busy || ladder.length === 0) return
        var p = Math.max(0, Math.min(ladder.length - 1, (_ladderPos < 0 ? 0 : _ladderPos) + d))
        root.selected = ladder[p].idx
    }
    function _shortLabel(r) {
        if (!r) return ""
        if (r.key === "best") return I18n.tr("Best")
        if (r.isAudio) return I18n.tr("Audio")
        return r.label
    }

    // The probe narrows the list; seed the pick once the real rows land and
    // keep the user's choice after that (a format switch also re-emits).
    Connections {
        target: QualityProbe
        function onChanged() {
            if (QualityProbe.busy) return
            if (!root._seeded) root._seed()
            else if (root.selected >= root.rows.length) root.selected = root._crownIdx
        }
    }

    onClosed: QualityProbe.reset()

    // output format follows the selected row (video container / audio codec)
    readonly property bool selectedIsAudio: {
        var r = root.rows[root.selected]
        return !!(r && r.isAudio)
    }
    readonly property var formatRows: selectedIsAudio ? QualityProbe.audioFormats
                                                      : QualityProbe.videoFormats
    readonly property string currentFormat: selectedIsAudio ? QualityProbe.audioFormat
                                                            : QualityProbe.videoFormat
    readonly property var _sel: root.rows[root.selected] || null

    background: Rectangle {
        radius: Tokens.radiusXl + 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.border_med
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.65 : 0.28)
            shadowVerticalOffset: 24
            shadowBlur: 1.0
            shadowScale: 1.0
        }
    }

    // ═══ header: the video itself ═══
    header: Item {
        implicitHeight: 172

        Item {
            id: hero
            anchors.fill: parent
            anchors.margins: Tokens.space2
            anchors.bottomMargin: 0

            Image {
                id: heroImg
                anchors.fill: parent
                visible: false
                source: root.thumbId !== "" ? "image://thumbs/" + root.thumbId : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 480
                sourceSize.height: 270
            }
            Item {
                id: heroMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: Tokens.radiusXl - 4; color: "white" }
            }
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusXl - 4
                color: Theme.surface_high
            }
            MultiEffect {
                anchors.fill: parent
                source: heroImg
                blurEnabled: true
                blur: 0.85
                blurMax: 48
                saturation: 0.15
                maskEnabled: true
                maskSource: heroMask
                opacity: heroImg.status === Image.Ready ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            }
            // scrim so the title always reads, fading into the dialog body
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusXl - 4
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.surface, 0.25) }
                    GradientStop { position: 0.55; color: U.withAlpha(Theme.surface, 0.70) }
                    GradientStop { position: 1.0; color: Theme.surface }
                }
            }

            C.IconButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.space3
                iconName: "close"
                implicitWidth: 34
                implicitHeight: 34
                tip: I18n.tr("Close")
                onClicked: root.reject()
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.space5 - Tokens.space2
                anchors.rightMargin: Tokens.space5 - Tokens.space2
                anchors.bottomMargin: Tokens.space2
                spacing: Tokens.space4

                // crisp thumbnail
                Item {
                    Layout.preferredWidth: 112
                    Layout.preferredHeight: 63
                    Layout.alignment: Qt.AlignBottom
                    visible: root.thumbId !== ""
                    Rectangle { anchors.fill: parent; radius: Tokens.radiusMd; color: Theme.surface_high }
                    Item {
                        id: thMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle { anchors.fill: parent; radius: Tokens.radiusMd; color: "white" }
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: heroImg
                        maskEnabled: true
                        maskSource: thMask
                        opacity: heroImg.status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    }
                    C.ThumbSkeleton {
                        anchors.fill: parent
                        active: heroImg.status !== Image.Ready
                        topLeftRadius: Tokens.radiusMd
                        topRightRadius: Tokens.radiusMd
                        bottomLeftRadius: Tokens.radiusMd
                        bottomRightRadius: Tokens.radiusMd
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusMd
                        color: "transparent"
                        border.width: 1
                        border.color: U.withAlpha(Theme.text_strong, 0.14)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Tokens.space1
                    C.AppText {
                        text: I18n.tr("Download quality")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.primary
                    }
                    C.AppText {
                        text: root.videoTitle
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontSubtitle + 1
                        color: Theme.text_strong
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── keyboard: ← / → walk the ladder, Enter downloads (Esc closes) ──
        Shortcut { sequences: ["Right"]; enabled: root.opened; onActivated: root._step(1) }
        Shortcut { sequences: ["Left"]; enabled: root.opened; onActivated: root._step(-1) }
        Shortcut { sequences: ["Return", "Enter"]; enabled: root.opened && dlBtn.enabled; onActivated: dlBtn.clicked() }

        // probe status: real formats / checking / generic ladder
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            Layout.topMargin: Tokens.space3
            spacing: Tokens.space2
            visible: QualityProbe.note !== ""

            C.SpinnerGlyph {
                name: QualityProbe.busy ? "autorenew"
                     : QualityProbe.failed ? "warning" : "check_circle"
                size: 15
                glyphColor: QualityProbe.busy ? Theme.primary
                          : QualityProbe.failed ? Theme.warn : Theme.secondary_container
                Layout.alignment: Qt.AlignTop
                spinning: QualityProbe.busy
            }
            C.AppText {
                text: QualityProbe.note
                font.pixelSize: Tokens.fontCaption
                color: QualityProbe.failed ? Theme.warn : Theme.on_surface_var
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        // ═══ the ladder ═══
        Item {
            id: ladderBox
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            Layout.topMargin: Tokens.space4
            implicitHeight: 208
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            readonly property int barMin: 40
            readonly property int barMax: 142
            readonly property int gapW: Tokens.space4

            // skeleton bars while probing
            Row {
                anchors.fill: parent
                spacing: Tokens.space2
                visible: QualityProbe.busy
                Repeater {
                    model: 5
                    Item {
                        width: (ladderBox.width - Tokens.space2 * 4) / 5
                        height: ladderBox.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 30
                            width: parent.width
                            height: 46 + index * 18
                            radius: Tokens.radiusMd
                            color: Theme.surface_high
                            SequentialAnimation on opacity {
                                running: QualityProbe.busy && root.visible
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 90 }
                                NumberAnimation { to: 0.45; duration: 620; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            Row {
                id: ladderRow
                anchors.fill: parent
                spacing: Tokens.space2
                visible: !QualityProbe.busy
                readonly property int nGaps: {
                    var g = 0
                    for (var i = 0; i < root.ladder.length; i++) if (root.ladder[i].gap) g++
                    return g
                }
                readonly property real colW: root.ladder.length > 0
                    ? (width - spacing * (root.ladder.length - 1) - ladderBox.gapW * nGaps) / root.ladder.length
                    : 0

                Repeater {
                    model: QualityProbe.busy ? [] : root.ladder
                    delegate: Item {
                        id: col
                        readonly property var r: root.rows[modelData.idx] || ({})
                        readonly property bool picked: root.selected === modelData.idx
                        readonly property real _h: {
                            var span = ladderBox.barMax - ladderBox.barMin
                            if (root._maxBytes > 0 && (r.sizeBytes || 0) > 0)
                                return ladderBox.barMin + span * Math.sqrt(r.sizeBytes / root._maxBytes)
                            // no sizes (probe failed): climb by rank, audio stays low
                            if (r.isAudio) return ladderBox.barMin
                            var n = Math.max(1, root.ladder.length)
                            return ladderBox.barMin + span * (index + 1) / n
                        }
                        width: ladderRow.colW + (modelData.gap ? ladderBox.gapW : 0)
                        height: ladderRow.height

                        // size readout above the bar
                        C.AppText {
                            anchors.horizontalCenter: bar.horizontalCenter
                            anchors.bottom: bar.top
                            anchors.bottomMargin: Tokens.space2
                            text: (col.r.sizeText || "") === "" ? "—"
                                  : (col.r.sizeExact ? "" : "≈ ") + col.r.sizeText
                            mono: true
                            weight: col.picked ? Tokens.weightBold : Tokens.weightMedium
                            font.pixelSize: Tokens.fontCaption
                            color: col.picked ? Theme.primary : Theme.on_surface_var
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }

                        Rectangle {
                            id: bar
                            anchors.right: parent.right
                            anchors.bottom: lbl.top
                            anchors.bottomMargin: Tokens.space2
                            width: ladderRow.colW
                            height: col._h
                            radius: Tokens.radiusMd
                            Behavior on height { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                            color: col.picked ? Theme.primary
                                 : colArea.containsMouse ? U.hoverTint(Theme.surface_high, Theme.isDark, 0.08)
                                 : Theme.surface_high
                            border.width: 1
                            border.color: col.picked ? Theme.primary : Theme.border_med
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                            // lit halo under the pick
                            layer.enabled: col.picked
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: U.withAlpha(Theme.primary, 0.55)
                                shadowBlur: 0.9
                                shadowVerticalOffset: 10
                            }

                            C.IconGlyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: Tokens.space2 + 2
                                visible: modelData.crown || !!col.r.isAudio
                                name: modelData.crown ? "star" : "music_note"
                                fill: modelData.crown
                                size: 17
                                glyphColor: col.picked ? Theme.on_primary : Theme.on_surface_var
                            }
                        }

                        C.AppText {
                            id: lbl
                            anchors.horizontalCenter: bar.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: root._shortLabel(col.r)
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            color: col.picked ? Theme.text_strong : Theme.on_surface_var
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, ladderRow.colW + 6)
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            id: colArea
                            anchors.left: bar.left
                            anchors.right: bar.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = modelData.idx
                        }
                    }
                }
            }
        }

        // ═══ what the pick actually is ═══
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            Layout.topMargin: Tokens.space4
            implicitHeight: specCol.implicitHeight + Tokens.space3 * 2
            radius: Tokens.radiusLg
            color: Theme.surface_low
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: specCol
                anchors.fill: parent
                anchors.margins: Tokens.space3
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space4
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    C.AppText {
                        text: QualityProbe.busy ? I18n.tr("Reading formats…")
                              : !root._sel ? ""
                              : root._sel.isAudio ? root._sel.label
                              : root._selectedIsCrown && root._sel.key !== "best"
                                ? root._sel.label + "  ·  " + I18n.tr("the best this video has")
                              : root._sel.label
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel
                        color: Theme.text_strong
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    // keyboard hint
                    Row {
                        spacing: 4
                        visible: !QualityProbe.busy
                        Repeater {
                            model: ["←", "→"]
                            Rectangle {
                                width: 24; height: 22
                                radius: Tokens.radiusXs
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.border_med
                                C.AppText {
                                    anchors.centerIn: parent
                                    text: modelData
                                    mono: true
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                }
                            }
                        }
                    }
                }
                C.AppText {
                    text: QualityProbe.busy ? I18n.tr("Asking YouTube what this video really has")
                                            : (root._sel ? root._sel.sub : "")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                // A failed probe means this is the generic ladder, not this
                // video's formats — say so on the pick itself.
                RowLayout {
                    visible: QualityProbe.failed && !!root._sel && !root._sel.isAudio
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space1
                    spacing: 6
                    C.IconGlyph { name: "help"; size: 13; glyphColor: Theme.warn; Layout.alignment: Qt.AlignTop }
                    C.AppText {
                        text: I18n.tr("Not confirmed for this video — if it isn't available the download will stop.")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.warn
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // ═══ container / codec ═══
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            Layout.topMargin: Tokens.space5
            spacing: Tokens.space3
            visible: !QualityProbe.busy && root.rows.length > 0
            C.AppText {
                text: root.selectedIsAudio ? I18n.tr("Audio format") : I18n.tr("Video format")
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontBody
                color: Theme.text_strong
            }
            C.AppText {
                text: {
                    var fr = root.formatRows || []
                    for (var i = 0; i < fr.length; ++i)
                        if (fr[i].key === root.currentFormat) return fr[i].sub
                    return ""
                }
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }
        }

        Rectangle {
            id: fmtSeg
            visible: !QualityProbe.busy && root.rows.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            Layout.topMargin: Tokens.space2
            implicitHeight: 46
            radius: Tokens.radiusLg
            color: Theme.surface_low
            border.width: 1
            border.color: Theme.border
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            readonly property var fr: root.formatRows || []
            readonly property real segW: fr.length > 0 ? (width - 8) / fr.length : 0
            readonly property int idx: {
                for (var i = 0; i < fr.length; ++i) if (fr[i].key === root.currentFormat) return i
                return 0
            }

            Rectangle {
                x: 4 + fmtSeg.idx * fmtSeg.segW
                y: 4
                width: fmtSeg.segW
                height: parent.height - 8
                radius: Tokens.radiusMd
                color: Theme.text_strong
                visible: fmtSeg.fr.length > 0
                Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }
            Row {
                x: 4; y: 4
                Repeater {
                    model: fmtSeg.fr
                    AbstractButton {
                        id: fmtBtn
                        width: fmtSeg.segW
                        height: fmtSeg.height - 8
                        readonly property bool on: fmtSeg.idx === index
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Item { }
                        contentItem: C.AppText {
                            text: modelData.label
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: fmtBtn.on ? Theme.surface : Theme.on_surface_var
                        }
                        onClicked: {
                            if (root.selectedIsAudio) QualityProbe.setAudioFormat(modelData.key)
                            else QualityProbe.setVideoFormat(modelData.key)
                        }
                    }
                }
            }
        }

        // ═══ audio track (v1.2): only for dubbed videos ═══
        C.AudioTrackPicker {
            id: trackDeck
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space5
            Layout.rightMargin: Tokens.space5
            Layout.topMargin: Tokens.space5
            visible: !QualityProbe.busy && root.rows.length > 0
                     && (QualityProbe.audioTracks || []).length > 1
            showHeader: true
            columns: width >= 520 ? 2 : 1
            maxCollapsed: 4
            tracks: QualityProbe.audioTracks || []
            current: QualityProbe.audioTrack
            onPicked: (key) => QualityProbe.setAudioTrack(key)
        }
    }

    footer: Item {
        implicitHeight: 52 + Tokens.space5 * 2
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space5
            anchors.rightMargin: Tokens.space5
            anchors.topMargin: Tokens.space5
            anchors.bottomMargin: Tokens.space5
            spacing: Tokens.space2

            Row {
                spacing: Tokens.space2
                Layout.alignment: Qt.AlignVCenter
                C.IconGlyph { name: "corner_down_left"; size: 14; glyphColor: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
                C.AppText {
                    text: I18n.tr("Enter to download")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Item { Layout.fillWidth: true }
            C.PrimaryButton {
                variant: "ghost"
                text: I18n.tr("Cancel")
                implicitHeight: 48
                onClicked: root.reject()
            }
            C.PrimaryButton {
                id: dlBtn
                iconName: "download"
                implicitHeight: 48
                text: {
                    var base = I18n.tr("Download")
                    var s = root._sel && !QualityProbe.busy ? (root._sel.sizeText || "") : ""
                    if (s === "") return base
                    return base + "  ·  " + (root._sel.sizeExact ? "" : "≈ ") + s
                }
                // No real list until the probe lands — the action waits too.
                enabled: !QualityProbe.busy && root.rows.length > 0
                onClicked: {
                    // v3.41.5: no point starting if YouTube can't be reached
                    if (!Geo.allowDownload()) { root.reject(); return }
                    if (!Deno.ready) {
                        root.reject()
                        Deno.requestInstall()
                        return
                    }
                    // Hand the VM the row's own presetIndex (rows are a subset
                    // of the preset ladder once probed).
                    var row = root.rows[root.selected]
                    root.target.startDownload(
                        root.videoId,
                        row && row.presetIndex !== undefined ? row.presetIndex
                                                             : root.selected)
                    root.accept()
                }
            }
        }
    }
}
