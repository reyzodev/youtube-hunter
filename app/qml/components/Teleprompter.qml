import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Effects
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// TELEPROMPTER — v14 "On Air" redesign.
//
// Read a blueprint's script off the screen while the camera rolls. Same
// StudioVM (`Studio`), same public API (overlayMode, immersive, closeRequested,
// togglePlay / restart / jumpToBeat), same keyboard map — what changed is the
// room it sits in:
//
//   * A TALLY LAMP. The header's pill reads STANDBY and lights ON AIR (with a
//     breathing glow) while the crawl runs, like the red lamp on a camera.
//   * 3 · 2 · 1. Pressing play from the top counts you in, so you are not
//     already a line behind when you look up at the lens. Space again cancels.
//   * THE READING LINE is a real landmark now: two accent arrows at the stage
//     edges plus a hairline, exactly where a hardware prompter puts them. The
//     first line of a beat — not its cue row — sits on it.
//   * A FLOATING TRANSPORT. The bottom bar became a capsule over the stage:
//     play, back to top, a scrubber with a tick for every beat (click to seek),
//     the named paces and a ± wpm stepper. In immersive mode (F) it fades away
//     after two seconds of reading and returns on any mouse move.
//   * The beat rail shows how far through each beat you are, and owns undo /
//     redo / save — editing lives next to the lines it edits.
//
// Kept on purpose: PACING IS IN WORDS, NOT PIXELS (crawl speed comes from WPM
// over the spoken word count), FrameAnimation drives the crawl by real elapsed
// time, MIRROR flips only the text column, and the active beat is the only one
// at full contrast.
Item {
    id: root

    property bool overlayMode: false
    property bool immersive: false
    signal closeRequested()

    readonly property var beats: Studio.beats
    readonly property bool playing: crawl.running
    // ON AIR covers the count-in too — the lamp lights when you commit.
    readonly property bool live: crawl.running || countdown > 0
    property int activeIndex: 0
    // 3, 2, 1 while counting in; 0 otherwise.
    property int countdown: 0

    focus: true
    Keys.onPressed: (event) => root._handleKey(event)

    // One rule for RTL wherever this is hosted (the overlay lives outside the
    // mirrored shell, the Content Lab tab inside it): mirroring is OFF here and
    // direction is set explicitly with layoutDirection / alignment below.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true
    readonly property int _dir: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight

    // ── geometry ─────────────────────────────────────────────────────────
    // The reading line sits at 38% — your eye wants the next line visible
    // below the one being spoken.
    readonly property real readLine: 0.38
    // How far above the reading line a beat's item starts, so its first LINE
    // of words (not the timecode row above it) lands on the line.
    readonly property real _lead: (Studio.showCues ? 30 : 0) + Studio.fontSize * 0.62
    readonly property real _topPad: Math.max(0, view.height * readLine - _lead)

    // ── pacing ───────────────────────────────────────────────────────────
    readonly property real _distance: Math.max(0, view.contentHeight - view.height)
    readonly property real _readSeconds: Math.max(1, Studio.estimatedSeconds)
    readonly property real _pxPerSecond: _distance > 0 ? _distance / _readSeconds : 0
    readonly property real progress: _distance > 0
                                     ? Math.min(1, view.contentY / _distance) : 0

    function _fmt(seconds) {
        var total = Math.max(0, Math.round(seconds))
        var m = Math.floor(total / 60)
        var s = total % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function togglePlay() {
        if (editing) return
        if (root.countdown > 0) { root.countdown = 0; return }
        if (crawl.running) { crawl.running = false; return }
        // At the end, play means "again from the top" — the commonest retake.
        if (root._distance > 0 && view.contentY >= root._distance - 1)
            view.contentY = 0
        // From the top you get counted in; mid-script you are already reading.
        if (view.contentY < 2) root.countdown = 3
        else crawl.running = true
    }

    function restart() {
        crawl.running = false
        root.countdown = 0
        view.contentY = 0
        root._measure()
    }

    function seekTo(fraction) {
        crawl.running = false
        root.countdown = 0
        view.contentY = Math.max(0, Math.min(root._distance, fraction * root._distance))
    }

    function jumpToBeat(index) {
        var item = beatRepeater.itemAt(index)
        if (!item) return
        crawl.running = false
        root.countdown = 0
        view.contentY = Math.max(0, Math.min(root._distance, item.y - root._topPad))
        root.activeIndex = index
    }

    function _measure() {
        var line = view.contentY + root._topPad + 2
        var found = 0
        for (var i = 0; i < beatRepeater.count; i++) {
            var item = beatRepeater.itemAt(i)
            if (item && item.y <= line) found = i
            else break
        }
        root.activeIndex = found
    }

    // 0..1 through beat `index`, for the rail's per-beat meter.
    function beatProgress(index) {
        var item = beatRepeater.itemAt(index)
        if (!item) return 0
        var line = view.contentY + root._topPad + 2
        return Math.max(0, Math.min(1, (line - item.y) / Math.max(1, item.height)))
    }

    // ── editing ──────────────────────────────────────────────────────────
    property int editing: 0        // 0 = none; otherwise beat index + 1
    property string editDraft: ""

    function beginEdit(index) {
        crawl.running = false
        root.countdown = 0
        root.editDraft = root.beats[index] ? root.beats[index].line : ""
        root.editing = index + 1
    }
    function commitEdit() {
        if (root.editing > 0) Studio.editBeat(root.editing - 1, root.editDraft)
        root.editing = 0
    }
    function cancelEdit() { root.editing = 0 }

    // ── keyboard ─────────────────────────────────────────────────────────
    function _handleKey(event) {
        if (root.editing > 0) {
            if (event.key === Qt.Key_Escape) { root.cancelEdit(); event.accepted = true }
            return
        }
        root._wake()
        switch (event.key) {
        case Qt.Key_Space:
            root.togglePlay(); event.accepted = true; break
        case Qt.Key_Home:
            root.restart(); event.accepted = true; break
        case Qt.Key_Up:
            crawl.running = false; root.countdown = 0
            view.contentY = Math.max(0, view.contentY - view.height * 0.25)
            event.accepted = true; break
        case Qt.Key_Down:
            crawl.running = false; root.countdown = 0
            view.contentY = Math.min(root._distance, view.contentY + view.height * 0.25)
            event.accepted = true; break
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            Studio.wpm = Studio.wpm + 5; event.accepted = true; break
        case Qt.Key_Minus:
            Studio.wpm = Studio.wpm - 5; event.accepted = true; break
        case Qt.Key_M:
            Studio.mirror = !Studio.mirror; event.accepted = true; break
        case Qt.Key_F:
            root.immersive = !root.immersive; event.accepted = true; break
        case Qt.Key_Escape:
            if (root.countdown > 0) root.countdown = 0
            else if (root.immersive) root.immersive = false
            else if (root.overlayMode) root.closeRequested()
            event.accepted = true; break
        }
    }

    Connections {
        target: Studio
        function onScriptChanged() { root.restart() }
    }

    FrameAnimation {
        id: crawl
        running: false
        onTriggered: {
            if (root._pxPerSecond <= 0) { running = false; return }
            var next = view.contentY + frameTime * root._pxPerSecond
            if (next >= root._distance) {
                view.contentY = root._distance
                running = false
            } else {
                view.contentY = next
            }
            root._measure()
        }
    }

    // the count-in
    Timer {
        interval: 650
        repeat: true
        running: root.countdown > 0
        onTriggered: {
            if (root.countdown <= 1) { root.countdown = 0; crawl.running = true }
            else root.countdown = root.countdown - 1
        }
    }

    // ── chrome that rests while you read (immersive only) ───────────────
    property bool _idle: false
    readonly property bool _chromeHidden: _idle && immersive && playing
    function _wake() {
        root._idle = false
        if (root.immersive && crawl.running) idleTimer.restart()
        else idleTimer.stop()
    }
    Timer { id: idleTimer; interval: 2000; onTriggered: root._idle = true }
    onPlayingChanged: _wake()
    onImmersiveChanged: _wake()

    // ── stage palette ────────────────────────────────────────────────────
    // Follows the app theme (the user prefers it to match the app).
    readonly property color _stageBg:  Theme.isDark ? "#07070A" : "#F4F4F6"
    readonly property color _ink:      Theme.isDark ? "#FFFFFF" : "#17171C"
    readonly property color _inkHi:    Theme.isDark ? "#F4F4F6" : "#1E1E24"
    readonly property color _inkMid:   Theme.isDark ? "#C4C4CC" : "#4E4E58"
    readonly property color _inkMut:   Theme.isDark ? "#9A9AA5" : "#62626C"
    readonly property color _inkFaint: Theme.isDark ? "#7A7A85" : "#8A8A94"
    readonly property color _chrome:   Theme.isDark ? "#101014" : "#FFFFFF"

    Rectangle {
        id: stage
        anchors.fill: parent
        radius: root.overlayMode ? Tokens.radiusLg : Tokens.radiusXl
        color: root._stageBg
        border.width: root.overlayMode ? 0 : 1
        border.color: U.withAlpha(Theme.border, 0.6)
        clip: true

        HoverHandler { onPointChanged: root._wake() }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ═══ top bar ═══
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.immersive ? 0 : 62
                visible: implicitHeight > 0
                color: U.withAlpha(root._ink, 0.025)
                clip: true
                Behavior on implicitHeight { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: U.withAlpha(root._ink, 0.07)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space4
                    anchors.rightMargin: Tokens.space4
                    spacing: Tokens.space3
                    layoutDirection: root._dir

                    // ── tally lamp ──
                    Rectangle {
                        radius: Tokens.radiusPill
                        implicitHeight: 32
                        implicitWidth: tallyRow.implicitWidth + Tokens.space4 + 2
                        color: root.live ? U.withAlpha(Theme.primary, 0.14) : U.withAlpha(Theme.primary, 0)
                        border.width: 1
                        border.color: root.live ? U.withAlpha(Theme.primary, 0.45) : U.withAlpha(root._ink, 0.10)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        Row {
                            id: tallyRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            Item {
                                width: 12; height: 12
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    id: tallyHalo
                                    anchors.centerIn: parent
                                    width: 12; height: 12; radius: 6
                                    color: Theme.primary
                                    visible: root.live
                                    opacity: 0
                                }
                                ParallelAnimation {
                                    running: root.live && root.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { target: tallyHalo; property: "scale"; from: 1; to: 2.6; duration: 1400; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: tallyHalo; property: "opacity"; from: 0.6; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 12; height: 12; radius: 6
                                    color: root.live ? Theme.primary : U.withAlpha(root._ink, 0.22)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                }
                            }
                            C.AppText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.live ? I18n.tr("ON AIR") : I18n.tr("STANDBY")
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                font.letterSpacing: I18n.rtl ? 0 : 1.2
                                color: root.live ? Theme.primary : root._inkMut
                            }
                        }
                    }

                    C.AppText {
                        text: Studio.idea.title || I18n.tr("No script loaded")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontLabel + 1
                        color: root._inkHi
                        elide: Text.ElideRight
                        Layout.maximumWidth: 440
                    }
                    C.AppText {
                        text: I18n.tr("Beat {i} of {n}")
                              .replace("{i}", root.activeIndex + 1)
                              .replace("{n}", Studio.beatCount)
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: root._inkMut
                        visible: Studio.hasScript
                    }

                    Item { Layout.fillWidth: true }

                    // pacing verdict: read time vs the blueprint's planned length
                    Rectangle {
                        radius: Tokens.radiusPill
                        implicitWidth: paceRow.implicitWidth + Tokens.space4
                        implicitHeight: 30
                        readonly property bool onTarget: Studio.paceVerdict === I18n.tr("On target")
                        readonly property color paceColor: onTarget ? Theme.secondary_container : Theme.warn
                        color: U.withAlpha(paceColor, 0.14)
                        border.width: 1
                        border.color: U.withAlpha(paceColor, 0.38)
                        visible: Studio.paceVerdict !== ""
                        Row {
                            id: paceRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            C.IconGlyph {
                                name: parent.parent.onTarget ? "check_circle" : "hourglass_empty"
                                size: 14
                                glyphColor: parent.parent.paceColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: Studio.estimatedText + " · " + Studio.paceVerdict
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                weight: Tokens.weightDemiBold
                                color: parent.parent.paceColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // type size stepper
                    Rectangle {
                        implicitHeight: 36
                        implicitWidth: sizeRow.implicitWidth + 4
                        radius: Tokens.radiusMd
                        color: "transparent"
                        border.width: 1
                        border.color: U.withAlpha(root._ink, 0.10)
                        Row {
                            id: sizeRow
                            anchors.centerIn: parent
                            C.IconButton {
                                iconName: "remove"; glyphSize: 15
                                implicitWidth: 32; implicitHeight: 32
                                tip: I18n.tr("Smaller text")
                                accent: root._inkMid
                                onClicked: Studio.fontSize = Studio.fontSize - 4
                            }
                            C.AppText {
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: Studio.fontSize
                                mono: true
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontCaption
                                color: root._inkMid
                            }
                            C.IconButton {
                                iconName: "add"; glyphSize: 15
                                implicitWidth: 32; implicitHeight: 32
                                tip: I18n.tr("Larger text")
                                accent: root._inkMid
                                onClicked: Studio.fontSize = Studio.fontSize + 4
                            }
                        }
                    }
                    C.IconButton {
                        iconName: "mirror"
                        tip: I18n.tr("Mirror for a beam-splitter rig  (M)")
                        active: Studio.mirror
                        accent: Studio.mirror ? Theme.primary : root._inkMid
                        onClicked: Studio.mirror = !Studio.mirror
                    }
                    C.IconButton {
                        iconName: Studio.showCues ? "visibility" : "visibility_off"
                        tip: I18n.tr("Timecodes and speaker labels")
                        active: Studio.showCues
                        accent: Studio.showCues ? Theme.primary : root._inkMid
                        onClicked: Studio.showCues = !Studio.showCues
                    }
                    C.IconButton {
                        iconName: "fullscreen"
                        tip: I18n.tr("Hide everything but the words  (F)")
                        accent: root._inkMid
                        onClicked: root.immersive = true
                    }
                    Rectangle {
                        visible: root.overlayMode
                        implicitWidth: 1; implicitHeight: 24
                        color: U.withAlpha(root._ink, 0.10)
                    }
                    C.IconButton {
                        iconName: "close"
                        tip: I18n.tr("Close")
                        visible: root.overlayMode
                        accent: root._inkMid
                        onClicked: root.closeRequested()
                    }
                }
            }

            // ═══ body: beat rail + stage ═══
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                layoutDirection: root._dir

                // ── beat rail ──
                Rectangle {
                    id: rail
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.immersive ? 0 : 272
                    visible: Layout.preferredWidth > 0
                    color: U.withAlpha(root._ink, 0.02)
                    clip: true
                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.right: I18n.rtl ? undefined : parent.right
                        anchors.left: I18n.rtl ? parent.left : undefined
                        width: 1; height: parent.height
                        color: U.withAlpha(root._ink, 0.07)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            layoutDirection: root._dir
                            Layout.leftMargin: Tokens.space4 + 2
                            Layout.rightMargin: Tokens.space4 + 2
                            Layout.topMargin: Tokens.space4
                            Layout.bottomMargin: Tokens.space2
                            C.AppText {
                                text: I18n.tr("Beats")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontBody
                                color: root._inkHi
                                Layout.fillWidth: true
                            }
                            C.AppText {
                                text: Studio.wordCount + " " + I18n.tr("words")
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: root._inkFaint
                            }
                        }

                        ListView {
                            id: railList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.leftMargin: Tokens.space2 + 2
                            Layout.rightMargin: Tokens.space2 + 2
                            spacing: 2
                            clip: true
                            model: root.beats
                            currentIndex: root.activeIndex
                            highlightFollowsCurrentItem: true
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: railRow
                                width: railList.width
                                implicitHeight: railCol.implicitHeight + Tokens.space3 * 2
                                radius: Tokens.radiusMd
                                clip: true
                                readonly property bool isActive: index === root.activeIndex
                                readonly property real prog: {
                                    var _ = view.contentY + root._topPad
                                    return root.beatProgress(index)
                                }
                                color: isActive ? U.withAlpha(root._ink, Theme.isDark ? 0.07 : 0.06)
                                     : railHover.hovered ? U.withAlpha(root._ink, 0.04)
                                     : U.withAlpha(root._ink, 0)
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                                HoverHandler { id: railHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.jumpToBeat(index) }

                                ColumnLayout {
                                    id: railCol
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space3
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        layoutDirection: root._dir
                                        C.AppText {
                                            text: modelData.time || ("#" + (index + 1))
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption
                                            color: railRow.isActive ? Theme.primary : root._inkMut
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: Theme.warn
                                            visible: modelData.isDirection
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                        C.AppText {
                                            text: modelData.words + "w"
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            color: root._inkFaint
                                            visible: !modelData.isDirection
                                        }
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: modelData.line
                                        font.pixelSize: Tokens.fontCaption + 1
                                        lineHeight: 1.15
                                        color: railRow.isActive ? root._ink
                                             : railRow.prog >= 1 ? root._inkFaint : root._inkMut
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        wrapMode: Text.WordWrap
                                        horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                    }
                                }

                                // how far through this beat the read is
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: I18n.rtl ? undefined : parent.left
                                    anchors.right: I18n.rtl ? parent.right : undefined
                                    anchors.leftMargin: railRow.radius
                                    anchors.rightMargin: railRow.radius
                                    anchors.bottomMargin: 1
                                    height: 2
                                    radius: 1
                                    width: (parent.width - railRow.radius * 2) * railRow.prog
                                    color: Theme.primary
                                    opacity: railRow.prog >= 1 ? 0.35 : 1
                                    visible: railRow.prog > 0
                                }
                            }
                        }

                        // edit history + save, next to the lines they change
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: U.withAlpha(root._ink, 0.07)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: Tokens.space3
                            spacing: Tokens.space1
                            layoutDirection: root._dir
                            C.IconButton {
                                iconName: "arrow_back"
                                tip: I18n.tr("Undo")
                                accent: root._inkMid
                                enabled: Studio.canUndo
                                onClicked: Studio.undo()
                            }
                            C.IconButton {
                                iconName: "arrow_forward"
                                tip: I18n.tr("Redo")
                                accent: root._inkMid
                                enabled: Studio.canRedo
                                onClicked: Studio.redo()
                            }
                            Item { Layout.fillWidth: true }
                            C.PrimaryButton {
                                variant: Studio.dirty ? "primary" : "ghost"
                                text: Studio.dirty ? I18n.tr("Save script") : I18n.tr("Saved")
                                iconName: Studio.dirty ? "save" : "check"
                                implicitHeight: 38
                                enabled: Studio.dirty
                                onClicked: Studio.save()
                            }
                        }
                    }
                }

                // ── the stage ──
                Item {
                    id: readingArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // MIRROR wraps only the words; chrome stays readable.
                    Item {
                        anchors.fill: parent
                        transform: Scale {
                            origin.x: readingArea.width / 2
                            xScale: Studio.mirror ? -1 : 1
                        }

                        Flickable {
                            id: view
                            anchors.fill: parent
                            contentHeight: column.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            // A wheel/drag while playing takes over.
                            onMovementStarted: { crawl.running = false; root.countdown = 0 }
                            onContentYChanged: root._measure()
                            clip: true

                            ColumnLayout {
                                id: column
                                width: Math.min(1040, view.width - Tokens.space8 * 2)
                                x: (view.width - width) / 2
                                spacing: Tokens.space6
                                Item { Layout.fillWidth: true; implicitHeight: root._topPad }

                                Repeater {
                                    id: beatRepeater
                                    model: root.beats

                                    ColumnLayout {
                                        id: beatCol
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        readonly property bool isActive: index === root.activeIndex
                                        readonly property bool isEditing: root.editing === index + 1

                                        // Only the beat being spoken is at full
                                        // contrast; the next one is a preview, the
                                        // rest recede (read ones furthest).
                                        opacity: isActive || isEditing ? 1.0
                                               : index === root.activeIndex + 1 ? 0.42
                                               : index < root.activeIndex ? 0.16 : 0.24
                                        Behavior on opacity { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }

                                        // cue row: timecode + speaker + line actions
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space3
                                            layoutDirection: root._dir
                                            visible: Studio.showCues && !beatCol.isEditing

                                            Rectangle {
                                                radius: Tokens.radiusSm
                                                implicitWidth: tcLbl.implicitWidth + Tokens.space3
                                                implicitHeight: 24
                                                color: beatCol.isActive ? U.withAlpha(Theme.primary, 0.18)
                                                                        : U.withAlpha(root._ink, 0.06)
                                                C.AppText {
                                                    id: tcLbl
                                                    anchors.centerIn: parent
                                                    text: modelData.time || ("#" + (index + 1))
                                                    mono: true
                                                    weight: Tokens.weightBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: beatCol.isActive ? Theme.primary : root._inkMut
                                                }
                                            }
                                            C.AppText {
                                                text: modelData.speaker
                                                visible: modelData.speaker !== ""
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: root._inkMut
                                            }
                                            Item { Layout.fillWidth: true }
                                            C.IconButton {
                                                iconName: "edit"
                                                glyphSize: 15
                                                implicitWidth: 32; implicitHeight: 32
                                                tip: I18n.tr("Edit this line")
                                                accent: root._inkMut
                                                visible: !root.live
                                                opacity: beatHover.hovered ? 1 : 0
                                                onClicked: root.beginEdit(index)
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                            }
                                            C.IconButton {
                                                iconName: "content_copy"
                                                glyphSize: 15
                                                implicitWidth: 32; implicitHeight: 32
                                                tip: I18n.tr("Copy this line")
                                                accent: root._inkMut
                                                visible: !root.live
                                                opacity: beatHover.hovered ? 1 : 0
                                                onClicked: Studio.copyText(modelData.line)
                                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                            }
                                        }

                                        HoverHandler { id: beatHover }

                                        // the words
                                        C.AppText {
                                            Layout.fillWidth: true
                                            visible: !beatCol.isEditing
                                            text: modelData.line
                                            weight: modelData.isDirection ? Tokens.weightRegular
                                                                          : Tokens.weightDemiBold
                                            font.pixelSize: modelData.isDirection
                                                            ? Math.max(16, Studio.fontSize * 0.62)
                                                            : Studio.fontSize
                                            font.italic: modelData.isDirection
                                            font.letterSpacing: I18n.rtl ? 0 : -0.3
                                            lineHeight: Studio.lineHeight
                                            lineHeightMode: Text.ProportionalHeight
                                            color: modelData.isDirection ? Theme.warn : root._ink
                                            wrapMode: Text.WordWrap
                                            horizontalAlignment: I18n.rtl ? Text.AlignRight
                                                                          : Text.AlignLeft
                                        }

                                        // in-place editor
                                        Rectangle {
                                            Layout.fillWidth: true
                                            visible: beatCol.isEditing
                                            implicitHeight: editArea.implicitHeight + Tokens.space4 * 2
                                            radius: Tokens.radiusLg
                                            color: U.withAlpha(root._ink, 0.05)
                                            border.width: 1
                                            border.color: U.withAlpha(Theme.primary, 0.55)
                                            // An editor must read the right way round
                                            // even when the column is mirrored.
                                            transform: Scale {
                                                origin.x: column.width / 2
                                                xScale: Studio.mirror ? -1 : 1
                                            }

                                            TextArea {
                                                id: editArea
                                                // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                                T.ContextMenu.menu: EditMenu { editor: editArea }
                                                anchors.fill: parent
                                                anchors.margins: Tokens.space4
                                                text: root.editDraft
                                                onTextChanged: root.editDraft = text
                                                wrapMode: TextArea.Wrap
                                                color: root._ink
                                                selectionColor: U.withAlpha(Theme.primary, 0.35)
                                                selectedTextColor: root._ink
                                                font.family: Fonts.familyFor("body", Tokens.weightDemiBold, text)
                                                font.weight: Fonts.weightFor(Tokens.weightDemiBold, text)
                                                font.pixelSize: Math.min(Studio.fontSize, 30)
                                                background: null
                                                onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                                                Keys.onPressed: (event) => {
                                                    if (event.key === Qt.Key_Escape) {
                                                        root.cancelEdit(); event.accepted = true
                                                    } else if ((event.key === Qt.Key_Return
                                                                || event.key === Qt.Key_Enter)
                                                               && (event.modifiers & Qt.ControlModifier)) {
                                                        root.commitEdit(); event.accepted = true
                                                    }
                                                }
                                            }
                                        }
                                        RowLayout {
                                            visible: beatCol.isEditing
                                            spacing: Tokens.space2
                                            layoutDirection: root._dir
                                            C.PrimaryButton {
                                                text: I18n.tr("Apply")
                                                iconName: "check"
                                                implicitHeight: 38
                                                onClicked: root.commitEdit()
                                            }
                                            C.PrimaryButton {
                                                variant: "ghost"
                                                text: I18n.tr("Cancel")
                                                implicitHeight: 38
                                                onClicked: root.cancelEdit()
                                            }
                                            C.AppText {
                                                text: I18n.tr("Ctrl+Enter to apply")
                                                mono: true
                                                font.pixelSize: Tokens.fontCaption
                                                color: root._inkFaint
                                                Layout.leftMargin: Tokens.space2
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true; implicitHeight: Math.max(0, view.height - root._topPad) }
                            }
                        }
                    }

                    // soft fades so lines arrive and leave instead of being cut
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: parent.height * 0.22
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: root._stageBg }
                            GradientStop { position: 1.0; color: U.withAlpha(root._stageBg, 0) }
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * 0.30
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: U.withAlpha(root._stageBg, 0) }
                            GradientStop { position: 0.55; color: U.withAlpha(root._stageBg, 0.8) }
                            GradientStop { position: 1.0; color: root._stageBg }
                        }
                    }

                    // ── the reading line: a hairline + two edge arrows ──
                    Item {
                        visible: Studio.hasScript
                        y: view.height * root.readLine
                        width: parent.width
                        height: 1
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0) }
                                GradientStop { position: 0.18; color: U.withAlpha(Theme.primary, root.live ? 0.42 : 0.20) }
                                GradientStop { position: 0.82; color: U.withAlpha(Theme.primary, root.live ? 0.42 : 0.20) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
                            }
                        }
                        C.IconGlyph {
                            x: Tokens.space3
                            anchors.verticalCenter: parent.verticalCenter
                            name: "play_arrow"; fill: true; size: 26
                            glyphColor: Theme.primary
                            opacity: root.live ? 1 : 0.7
                        }
                        C.IconGlyph {
                            x: parent.width - width - Tokens.space3
                            anchors.verticalCenter: parent.verticalCenter
                            rotation: 180
                            name: "play_arrow"; fill: true; size: 26
                            glyphColor: Theme.primary
                            opacity: root.live ? 1 : 0.7
                        }
                    }

                    // empty state
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.space3
                        visible: !Studio.hasScript
                        C.IconGlyph {
                            name: "subject"; size: 44
                            glyphColor: U.withAlpha(root._ink, 0.2)
                            Layout.alignment: Qt.AlignHCenter
                        }
                        C.AppText {
                            text: I18n.tr("Pick a greenlight with a script to read it here.")
                            color: root._inkMut
                            font.pixelSize: Tokens.fontLabel
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // ── 3 · 2 · 1 ──
                    Rectangle {
                        anchors.centerIn: parent
                        width: 184; height: 184; radius: 92
                        visible: root.countdown > 0
                        color: U.withAlpha(root._stageBg, 0.82)
                        border.width: 2
                        border.color: U.withAlpha(Theme.primary, 0.55)
                        C.AppText {
                            id: countLbl
                            anchors.centerIn: parent
                            text: root.countdown
                            mono: true
                            weight: Tokens.weightExtraBold
                            font.pixelSize: 104
                            color: Theme.primary
                        }
                        // each number lands: scale down + fade in
                        onVisibleChanged: if (visible) countPop.restart()
                        Connections {
                            target: root
                            function onCountdownChanged() { if (root.countdown > 0) countPop.restart() }
                        }
                        ParallelAnimation {
                            id: countPop
                            NumberAnimation { target: countLbl; property: "scale"; from: 1.35; to: 1; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: countLbl; property: "opacity"; from: 0; to: 1; duration: 220 }
                        }
                    }

                    // ═══ floating transport ═══
                    Rectangle {
                        id: capsule
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root._chromeHidden ? -height : Tokens.space5
                        width: capRow.implicitWidth + Tokens.space2 * 2 + Tokens.space2
                        height: 72
                        radius: 24
                        color: U.withAlpha(root._chrome, Theme.isDark ? 0.92 : 0.96)
                        border.width: 1
                        border.color: U.withAlpha(root._ink, 0.10)
                        opacity: root._chromeHidden ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                        Behavior on anchors.bottomMargin { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.6 : 0.18)
                            shadowBlur: 1.0
                            shadowVerticalOffset: 14
                        }

                        RowLayout {
                            id: capRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.space2
                            spacing: Tokens.space3

                            // play / pause — the one big key
                            AbstractButton {
                                id: playBtn
                                implicitWidth: 56; implicitHeight: 56
                                enabled: Studio.hasScript && root.editing === 0
                                onClicked: root.togglePlay()
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                scale: pressed ? Tokens.pressScale : 1
                                Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                                background: Rectangle {
                                    radius: 18
                                    color: !playBtn.enabled ? Theme.disabled_bg
                                         : playBtn.hovered ? Theme.primary_hover : Theme.primary
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                }
                                contentItem: Item {
                                    C.IconGlyph {
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: root.live ? 0 : 1
                                        name: root.live ? "pause" : "play_arrow"
                                        fill: true
                                        size: 26
                                        glyphColor: playBtn.enabled ? Theme.on_primary : Theme.disabled_fg
                                    }
                                }
                                C.AppTooltip {
                                    visible: playBtn.hovered
                                    text: (root.live ? I18n.tr("Pause") : I18n.tr("Play")) + "  (Space)"
                                }
                            }
                            C.IconButton {
                                iconName: "restart_alt"
                                tip: I18n.tr("Back to the top")
                                accent: root._inkMid
                                enabled: Studio.hasScript
                                onClicked: root.restart()
                            }

                            // scrubber: elapsed / total + a tick per beat
                            Item {
                                id: scrub
                                implicitWidth: Math.max(140, Math.min(250, readingArea.width - 720))
                                implicitHeight: 44
                                readonly property real frac: root.progress

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    C.AppText {
                                        text: root._fmt(root.progress * Studio.estimatedSeconds)
                                        mono: true
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: root._ink
                                        Layout.fillWidth: true
                                    }
                                    C.AppText {
                                        text: Studio.estimatedText
                                        mono: true
                                        font.pixelSize: Tokens.fontCaption
                                        color: root._inkFaint
                                    }
                                }
                                Item {
                                    id: track
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 20
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 4; radius: 2
                                        color: U.withAlpha(root._ink, 0.12)
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width * scrub.frac; height: 4; radius: 2
                                        color: Theme.primary
                                    }
                                    Repeater {
                                        model: Studio.hasScript ? beatRepeater.count : 0
                                        Rectangle {
                                            visible: index > 0
                                            readonly property var it: beatRepeater.itemAt(index)
                                            x: {
                                                var _ = root._distance + column.implicitHeight
                                                if (!it || root._distance <= 0) return 0
                                                return track.width * Math.min(1, Math.max(0, (it.y - root._topPad) / root._distance))
                                            }
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 2; height: 12; radius: 1
                                            color: U.withAlpha(root._ink, 0.35)
                                        }
                                    }
                                    Rectangle {
                                        x: track.width * scrub.frac - width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16; height: 16; radius: 8
                                        color: root._ink
                                        border.width: 3
                                        border.color: U.withAlpha(Theme.primary, 0.5)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.topMargin: -6
                                        anchors.bottomMargin: -6
                                        enabled: Studio.hasScript
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: (mouse) => root.seekTo(mouse.x / Math.max(1, width))
                                        onPositionChanged: (mouse) => { if (pressed) root.seekTo(mouse.x / Math.max(1, width)) }
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 1; implicitHeight: 32
                                color: U.withAlpha(root._ink, 0.10)
                            }

                            // named paces, with a sliding pill
                            Rectangle {
                                id: paceSeg
                                readonly property var presets: Studio.wpmPresets || []
                                readonly property int segW: 76
                                readonly property int idx: {
                                    for (var i = 0; i < presets.length; i++)
                                        if (presets[i].wpm === Studio.wpm) return i
                                    return -1
                                }
                                implicitWidth: segW * presets.length + 8
                                implicitHeight: 44
                                radius: 15
                                color: U.withAlpha(root._ink, 0.05)

                                Rectangle {
                                    visible: paceSeg.idx >= 0
                                    x: 4 + Math.max(0, paceSeg.idx) * paceSeg.segW
                                    y: 4
                                    width: paceSeg.segW
                                    height: parent.height - 8
                                    radius: 11
                                    color: root._ink
                                    Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                }
                                Row {
                                    x: 4; y: 4
                                    Repeater {
                                        model: paceSeg.presets
                                        AbstractButton {
                                            id: paceBtn
                                            width: paceSeg.segW
                                            height: paceSeg.height - 8
                                            readonly property bool isOn: paceSeg.idx === index
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            onClicked: Studio.wpm = modelData.wpm
                                            background: Item { }
                                            contentItem: C.AppText {
                                                text: modelData.label
                                                weight: Tokens.weightDemiBold
                                                font.pixelSize: Tokens.fontBody
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                color: paceBtn.isOn ? root._stageBg : root._inkMid
                                            }
                                        }
                                    }
                                }
                            }

                            // fine pace: ± 5 wpm
                            Row {
                                spacing: 0
                                C.IconButton {
                                    iconName: "remove"; glyphSize: 15
                                    implicitWidth: 32; implicitHeight: 32
                                    anchors.verticalCenter: parent.verticalCenter
                                    tip: I18n.tr("Slower  (−)")
                                    accent: root._inkMid
                                    onClicked: Studio.wpm = Studio.wpm - 5
                                }
                                Column {
                                    width: I18n.rtl ? 86 : 52
                                    anchors.verticalCenter: parent.verticalCenter
                                    C.AppText {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Studio.wpm
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontLabel
                                        color: root._ink
                                    }
                                    C.AppText {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: I18n.tr("wpm")
                                        font.pixelSize: Tokens.fontMicro
                                        color: root._inkFaint
                                    }
                                }
                                C.IconButton {
                                    iconName: "add"; glyphSize: 15
                                    implicitWidth: 32; implicitHeight: 32
                                    anchors.verticalCenter: parent.verticalCenter
                                    tip: I18n.tr("Faster  (+)")
                                    accent: root._inkMid
                                    onClicked: Studio.wpm = Studio.wpm + 5
                                }
                            }

                            C.IconButton {
                                visible: root.immersive
                                iconName: "fullscreen_exit"
                                tip: I18n.tr("Show the controls  (F)")
                                accent: root._inkMid
                                onClicked: root.immersive = false
                            }
                        }
                    }
                }
            }
        }

        // read progress, a hairline across the very top — inset past the
        // rounded corners so it stays inside the stage
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: stage.radius
            anchors.topMargin: 1
            width: (parent.width - stage.radius * 2) * root.progress
            height: 2
            radius: 1
            color: Theme.primary
            visible: Studio.hasScript
        }
    }
}
