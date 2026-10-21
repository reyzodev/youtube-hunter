import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import NicheScope
import "." as C
import "../Utils.js" as U

// In-app video player for a finished download.
//
// v15 "Theatre" redesign (2026):
//   * ambient mode: the video's own thumbnail, blurred, glows out around the
//     card, so the player belongs to the picture instead of floating in black
//   * one floating glass dock instead of a full-width gradient bar: a seek
//     line with a hover time bubble and a ghost fill, then the transport
//   * the volume slider folds out of its icon on hover
//   * speed (0.5×–2×) and the downloaded qualities share one settings sheet;
//     the active speed and resolution show as chips on the dock
//   * gestures: double-click the left / right third to skip 10 s, the middle
//     to fill the window; a feedback bubble answers every skip / volume / speed
//     change; a spinner while the file is opening; a clear error card if it
//     cannot be decoded
//   * keyboard: Space/K play · ←/→ or J/L ±10 s · ↑/↓ volume · M mute ·
//     F fill window · < / > speed · 0–9 jump to 0–90 % · Home/End
//   * chrome now hides after 2.4 s of a still pointer even while it is over the
//     video (it used to stay up for as long as the mouse was inside). The
//     pointer itself is never hidden — see the cursor notes below.
//
// Public API is unchanged: `player.play(Downloads.playInfo(videoId))`.
// The previous version lives in _backup_v14/VideoPlayer.qml.
Popup {
    id: root

    // ── public API ──
    // `info` is the map DownloadsVM.playInfo() returns.
    property var info: ({})

    // Audio-only download (.mp3): the card plays as a MUSIC player — cover art
    // instead of a video frame, a big centred transport, no fill-window.
    readonly property bool _audio: !!(info && info.isAudio)

    function play(playInfo) {
        if (!playInfo || !playInfo.fileUrl) return
        root.info = playInfo
        root._seeking = false
        root._maximised = false
        root._variantIndex = root._indexOfCurrent()
        media.source = playInfo.fileUrl
        root.open()
        media.play()
        // Keyboard shortcuts need the stage focused, not whatever had focus
        // on the page underneath.
        Qt.callLater(function () { stage.forceActiveFocus() })
    }

    // Every downloaded file for this video, split by kind (see v14 notes).
    readonly property var _allVariants: (info && info.qualities) ? info.qualities : []
    readonly property var _variants: {
        var out = []
        for (var i = 0; i < root._allVariants.length; ++i) {
            var v = root._allVariants[i]
            if ((v.key === "audio") === root._audio)
                out.push(v)
        }
        return out.length > 0 ? out : root._allVariants
    }
    function _indexOfCurrent() {
        var vs = root._variants
        for (var i = 0; i < vs.length; ++i) {
            if (vs[i].fileUrl === (root.info ? root.info.fileUrl : ""))
                return i
        }
        return 0
    }

    // Cover art for the music player: thumbnail, else channel avatar.
    readonly property string _coverSource: {
        if (!root.info) return ""
        var t = root.info.thumbId || ""
        if (t !== "") return "image://thumbs/" + t
        var c = root.info.channelThumbId || ""
        return c !== "" ? "image://thumbs/" + c : ""
    }
    // Ambient glow source: the video's own thumbnail only (an avatar would
    // tint the room the wrong colour).
    readonly property string _ambientSource: (root.info && (root.info.thumbId || "") !== "")
                                             ? "image://thumbs/" + root.info.thumbId : ""

    property int _variantIndex: 0
    property bool _seeking: false
    property bool _chipHovered: false
    property bool _maximised: false
    // Elapsed / total  ↔  elapsed / −remaining (click the time readout).
    property bool _showRemaining: false
    // Playback speed. Kept for the whole session (YouTube does the same), so
    // a 1.5× watcher does not have to set it again on every file.
    property real _rate: 1.0
    readonly property var _rates: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    readonly property bool _playing: media.playbackState === MediaPlayer.PlayingState
    readonly property bool _busy: media.mediaStatus === MediaPlayer.LoadingMedia
                                  || media.mediaStatus === MediaPlayer.BufferingMedia
                                  || media.mediaStatus === MediaPlayer.StalledMedia
    readonly property bool _failed: media.error !== MediaPlayer.NoError
                                    || media.mediaStatus === MediaPlayer.InvalidMedia
    readonly property string _currentQualityLabel: {
        var v = root._variants
        if (v && _variantIndex >= 0 && _variantIndex < v.length)
            return v[_variantIndex].label || ""
        return info && info.quality ? info.quality : ""
    }
    readonly property real _vol: audioOut.muted ? 0 : audioOut.volume
    readonly property string _volIcon: root._vol <= 0 ? "volume_off" : "volume_up"

    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    padding: 0
    closePolicy: Popup.CloseOnEscape

    // 16:9 card with a generous margin (a little more than before, because the
    // ambient glow needs room to spill into); the music player is a taller,
    // narrower card for its square of cover art.
    readonly property int _availW: parent ? parent.width : 1280
    readonly property int _availH: parent ? parent.height : 720
    width: _maximised ? _availW
                      : Math.max(360, Math.min(_audio ? 560 : 1220, _availW - 128))
    height: _maximised ? _availH
                       : Math.max(260, Math.min(
                            Math.round(width * (_audio ? 1.16 : 9 / 16)),
                            _availH - 112))
    Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

    // Plain dim (no live blur — see the v13 note: a full-window blur would run
    // for as long as a video decodes). A touch darker than before so the
    // ambient glow reads as light, not as a smudge.
    Overlay.modal: Rectangle {
        color: Qt.rgba(0.01, 0.01, 0.02, Theme.isDark ? 0.74 : 0.62)
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.965; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }

    onClosed: { media.pause(); media.source = "" }

    // Background = ambient glow (spills OUTSIDE the card) + the card itself.
    // The glow is a plain Item with no layer, so it is not clipped to the
    // card's bounds; only the card rectangle carries the drop shadow layer.
    background: Item {
        Item {
            id: ambient
            anchors.fill: parent
            anchors.margins: -64
            visible: !root._audio && !root._maximised && root._ambientSource !== ""
            opacity: ambientImg.status === Image.Ready ? (root._playing ? 0.62 : 0.48) : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow * 2; easing.type: Easing.OutCubic } }
            Image {
                id: ambientImg
                anchors.fill: parent
                visible: false
                source: ambient.visible ? root._ambientSource : ""
                // tiny decode: it is about to be blurred to mush anyway
                sourceSize.width: 192
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
            MultiEffect {
                anchors.fill: parent
                source: ambientImg
                visible: ambientImg.status === Image.Ready
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                saturation: 0.35
                brightness: 0.05
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: root._maximised ? 0 : Tokens.radiusXl
            color: "#000000"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), 0.7)
                shadowVerticalOffset: 14
                shadowBlur: 1.0
            }
        }
    }

    // ── playback engine ──
    MediaPlayer {
        id: media
        videoOutput: videoOut
        audioOutput: AudioOutput { id: audioOut; volume: 0.8 }
        playbackRate: root._rate
        // Loop back to the start on end-of-media rather than a black frame.
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) position = 0
    }

    // Dock button: chromeless + overlay → white line glyph, no tile; a soft
    // white disc fades in on hover (a dark disc on a dark dock is invisible).
    component DockButton: C.IconButton {
        id: db
        chromeless: true
        overlay: true
        accent: "#ffffff"
        glyphSize: 20
        implicitWidth: 38
        implicitHeight: 38
        // The dock sits at the bottom of the card: tips go ABOVE the button
        // and stay inside the player card instead of spilling out below it.
        tipAbove: true
        tipBoundsName: "playerStage"
        Rectangle {
            z: -1
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, db.hovered ? 0.13 : 0.0)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
    }

    // Text chip on the dock (speed, resolution). `lit` = accent-filled.
    component DockChip: AbstractButton {
        id: dc
        property string label: ""
        property bool lit: false
        implicitHeight: 26
        implicitWidth: dcLbl.implicitWidth + Tokens.space3 * 2
        hoverEnabled: true
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: Tokens.radiusPill
            color: dc.lit ? Theme.primary
                          : Qt.rgba(1, 1, 1, dc.hovered ? 0.18 : 0.10)
            border.width: dc.lit ? 0 : 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: C.AppText {
            id: dcLbl
            text: dc.label
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontMicro
            color: dc.lit ? Theme.on_primary : "#ffffff"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            LayoutMirroring.enabled: false
        }
    }

    contentItem: Item {
        id: stage
        objectName: "playerStage"
        clip: true

        // NOTE: no `cursor:` here — Qt 6's QML Item has none. The arrow floor is
        // the HoverHandler below + `bodyArea`'s cursorShape; every control
        // declares its own. Never hide the pointer in this player: a window that
        // answers its cursor query with nothing makes Windows stop drawing one
        // (the v12 "mouse vanishes on the player" bug, also guarded in
        // app/qml_backend/cursor_guard.py).

        // Transport chrome is never mirrored (play left, fill right, seek
        // left→right) in any language; page content still mirrors.
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        HoverHandler { cursorShape: Qt.ArrowCursor }

        // ── keyboard ── (on the content Item: a Popup is not an Item, so Keys
        // attached there would be dropped). Esc is left unaccepted so the
        // Popup's CloseOnEscape still sees it.
        focus: true
        Keys.onPressed: (event) => {
            var k = event.key
            var handled = true
            if (k === Qt.Key_Space || k === Qt.Key_K) root._toggle()
            else if (k === Qt.Key_Left || k === Qt.Key_J) root._nudge(-10000, true)
            else if (k === Qt.Key_Right || k === Qt.Key_L) root._nudge(10000, true)
            else if (k === Qt.Key_Up) root._setVolume(audioOut.volume + 0.05, true)
            else if (k === Qt.Key_Down) root._setVolume(audioOut.volume - 0.05, true)
            else if (k === Qt.Key_M) root._toggleMute()
            else if (k === Qt.Key_F) { if (!root._audio) root._maximised = !root._maximised }
            else if (k === Qt.Key_Less || k === Qt.Key_Comma) root._stepRate(-1)
            else if (k === Qt.Key_Greater || k === Qt.Key_Period) root._stepRate(1)
            else if (k === Qt.Key_Home) media.position = 0
            else if (k === Qt.Key_End) media.position = Math.max(0, media.duration - 1000)
            else if (k >= Qt.Key_0 && k <= Qt.Key_9 && !(event.modifiers & Qt.ControlModifier)) {
                if (media.duration > 0)
                    media.position = Math.round(media.duration * (k - Qt.Key_0) / 10)
            }
            else handled = false
            if (handled) {
                event.accepted = true
                stage.chromeShown = true
                chromeTimer.restart()
            }
        }

        // Outer mask: rounds the whole card (the video and scrims paint square
        // pixels straight over the background radius otherwise).
        Rectangle {
            id: videoMask
            anchors.fill: parent
            radius: root._maximised ? 0 : Tokens.radiusXl
            visible: false
            layer.enabled: true
        }

        // ── chrome visibility ──
        property bool chromeShown: true
        Timer {
            id: chromeTimer
            interval: 2400
            onTriggered: {
                if (root._playing && !root._chipHovered && !dockHover.hovered
                        && !settingsMenu.opened && !root._seeking)
                    stage.chromeShown = false
                else if (root._playing)
                    chromeTimer.restart()
            }
            running: false
        }
        onChromeShownChanged: if (chromeShown) chromeTimer.restart()
        Connections {
            target: root
            function on_PlayingChanged() { stage.chromeShown = true; chromeTimer.restart() }
        }
        Component.onCompleted: chromeTimer.restart()

        readonly property bool showChrome: chromeShown || !root._playing || dockHover.hovered
                                           || settingsMenu.opened || root._seeking
                                           || root._failed

        Item {
            id: stageClip
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: videoMask
            }

            // Fitted video frame (real aspect from metadata, so the picture gets
            // its own rounded corners instead of floating square on black bars).
            readonly property var _videoRes: media.metaData
                ? media.metaData.value(MediaMetaData.Resolution) : undefined
            readonly property bool _hasVideoRes: _videoRes !== undefined && _videoRes !== null
                && _videoRes.width > 0 && _videoRes.height > 0
            readonly property real _videoAspect: _hasVideoRes
                ? _videoRes.width / _videoRes.height : (16 / 9)
            readonly property real _stageAspect: stage.height > 0
                ? stage.width / stage.height : (16 / 9)
            readonly property bool _videoWide: _videoAspect >= _stageAspect
            readonly property real _frameW: _hasVideoRes
                ? (_videoWide ? stage.width : stage.height * _videoAspect) : stage.width
            readonly property real _frameH: _hasVideoRes
                ? (_videoWide ? stage.width / _videoAspect : stage.height) : stage.height

            Rectangle { anchors.fill: parent; color: "#000000" }

            Rectangle {
                id: videoInnerMask
                x: videoFrame.x
                y: videoFrame.y
                width: videoFrame.width
                height: videoFrame.height
                radius: root._maximised ? 0 : Tokens.radiusLg
                visible: false
                layer.enabled: true
            }

            Item {
                id: videoFrame
                anchors.centerIn: parent
                width: stageClip._frameW
                height: stageClip._frameH
                visible: !root._audio
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: videoInnerMask
                }
                VideoOutput {
                    id: videoOut
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }
            }

            // ── music player stage (audio-only downloads) ──
            // Cover art on a soft dark wash, sized to the space left between the
            // channel chip at the top and the transport bar at the bottom. The
            // artwork is the video's own thumbnail (the row already has one), so
            // an audio download still looks like the thing it came from rather
            // than a blank grey box.
            Item {
                id: audioStage
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                    bottomMargin: dock.height + Tokens.space4 * 2
                }
                visible: root._audio

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0.09, 0.09, 0.11, 1) }
                        GradientStop { position: 0.55; color: Qt.rgba(0.05, 0.05, 0.06, 1) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.02, 0.03, 1) }
                    }
                }

                Item {
                    id: art
                    anchors.centerIn: parent
                    // Square, capped by whichever axis is tighter, and never so
                    // small that the fallback glyph turns into a dot.
                    readonly property real _fit: Math.min(parent.width - 120,
                                                          parent.height - 24)
                    width: Math.max(96, _fit)
                    height: width

                    // Soft red halo behind the artwork, so the square reads as
                    // "now playing" rather than a stray image.
                    C.GlowBlob {
                        anchors.centerIn: parent
                        size: Math.round(art.width * 1.5)
                        glow: Theme.primary
                        strength: 0.32
                    }

                    Rectangle {
                        id: artMask
                        anchors.fill: parent
                        radius: Tokens.radiusLg
                        visible: false
                        layer.enabled: true
                    }
                    Image {
                        id: artImg
                        anchors.fill: parent
                        visible: false
                        source: root._coverSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: root._coverSource !== ""
                                 && artImg.status !== Image.Error
                        source: artImg
                        maskEnabled: true
                        maskSource: artMask
                    }

                    // No thumbnail on disk: a red disc with a note on it.
                    Rectangle {
                        anchors.fill: parent
                        visible: root._coverSource === ""
                                 || artImg.status === Image.Error
                        radius: Tokens.radiusLg
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.55) }
                            GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.14) }
                        }
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.45)
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: "music_note"
                            fill: true
                            size: Math.round(art.width * 0.30)
                            glyphColor: "#ffffff"
                        }
                    }
                }
            }

        // ── body: click = play/pause, double-click thirds = skip / fill ──
        // A single click waits one double-click interval before toggling, so a
        // double-click to skip does not also pause the video twice.
        MouseArea {
            id: bodyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: clickDelay.restart()
            onDoubleClicked: (m) => {
                clickDelay.stop()
                var third = width / 3
                if (m.x < third) root._nudge(-10000, true)
                else if (m.x > third * 2) root._nudge(10000, true)
                else if (!root._audio) root._maximised = !root._maximised
            }
            onPositionChanged: { stage.chromeShown = true; chromeTimer.restart() }
            onEntered: { stage.chromeShown = true; chromeTimer.restart() }
            Timer {
                id: clickDelay
                interval: 230
                onTriggered: root._toggle()
            }
        }

        // ── top scrim + channel chip + actions ──
        Rectangle {
            id: topScrim
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 120
            opacity: stage.showChrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.72) }
                GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.22) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
            }
        }
        Rectangle {
            id: bottomScrim
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 170
            visible: !root._audio
            opacity: stage.showChrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
            }
        }

        // Channel identity: avatar + video title over channel name. Hovering the
        // avatar fades a translucent dark box IN OVER the title (the title stays
        // put in its own place and ghosts faintly through, spilling out to the
        // right past the box when it is long) while the channel name over the
        // subscriber count cross-fades in on top of the box — the reference
        // channel card. (A real backdrop blur here would cost a full-frame
        // texture per frame, so the card is a translucent tint.)
        Item {
            id: chip
            anchors { left: parent.left; top: parent.top; leftMargin: Tokens.space5; topMargin: Tokens.space4 + 2 }
            width: Math.min(chipRow.implicitWidth, stage.width - topActions.width - Tokens.space6 * 2)
            height: chipRow.implicitHeight
            opacity: stage.showChrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

            // The channel-card backdrop: wraps the avatar + the channel/subs
            // foreground only (not the full title width), so a long title keeps
            // spilling out right onto the bare video like the reference.
            Rectangle {
                id: hoverBg
                x: -8
                y: -7
                width: Math.min(avatar.width + chipRow.spacing
                                + Math.max(lineHover1.implicitWidth,
                                           lineHover2.implicitWidth)
                                + Tokens.space4 + 8,
                                chip.width + 16)
                height: chip.height + 14
                radius: Tokens.radiusMd
                color: Qt.rgba(0, 0, 0, 0.85)
                opacity: avatarHover.hovered ? 1 : 0
                scale: avatarHover.hovered ? 1 : 0.96
                transformOrigin: Item.TopLeft
                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                id: chipRow
                anchors.fill: parent
                spacing: Tokens.space3

            // Channel avatar. The rounded crop is done with a masked layer and a
            // SEPARATE mask item — an inline mask Rectangle declared inside
            // layer.effect never gets a scene of its own to render into, so it
            // produced an all-transparent mask and the logo simply never appeared.
            Item {
                id: avatar
                width: 40; height: 40
                Layout.alignment: Qt.AlignVCenter
                // Gentle pop on hover so the channel affordance feels alive.
                scale: avatarHover.hovered ? 1.1 : 1.0
                Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: avatarMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                // Resting disc, so a missing/slow logo still reads as an avatar.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: U.withAlpha(Qt.rgba(1, 1, 1, 1), 0.16)
                    border.width: 1
                    border.color: U.withAlpha(Qt.rgba(1, 1, 1, 1), 0.28)
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: avatarMask
                    }
                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        visible: (root.info.channelThumbId || "") !== ""
                        source: (root.info.channelThumbId || "") !== ""
                                ? "image://thumbs/" + root.info.channelThumbId : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }

                // Initials fallback — only when there is no logo to show (or it
                // failed to load), so it never sits under a real avatar.
                C.AppText {
                    anchors.centerIn: parent
                    visible: (root.info.channelThumbId || "") === ""
                             || avatarImg.status === Image.Error
                    text: {
                        var n = (root.info.channelTitle || "").trim()
                        if (!n) return "?"
                        // v3.16-p4: drop separator-only tokens ("·", "→", "|") —
                        // "Clip · 30:42 → 32:24" used to render as "C·".
                        var parts = n.replace(/_/g, " ").split(" ").filter(function (p) {
                            return p && !/^[·•|\-–—:→0-9.]+$/.test(p) })
                        if (parts.length === 0) return "?"
                        if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase()
                        return (parts.length >= 2 ? parts[0][0] + parts[1][0] : n.substring(0, 2)).toUpperCase()
                    }
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontBody
                    color: "#ffffff"
                }

                HoverHandler {
                    id: avatarHover
                    cursorShape: (root.info.channelUrl || "") !== ""
                                 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onHoveredChanged: root._chipHovered = hovered
                }
                TapHandler {
                    enabled: (root.info.channelUrl || "") !== ""
                    onTapped: Qt.openUrlExternally(root.info.channelUrl)
                }
            }

            // Channel lines: resting (title / channel) stays put in its own
            // place; on avatar hover the dark box above falls onto it (it shows
            // through faintly) while the hover pair (channel / subscribers)
            // cross-fades in on top of the box with a small slide, instead of
            // snapping text in place. Each pair lives in a wrapper whose
            // implicit size tracks the WIDEST line — a plain Item reports 0,
            // which would collapse the whole column (and elide every line to
            // nothing), so both are forwarded explicitly. Children are
            // top-anchored (never verticalCenter: that would tie their y to a
            // height derived from their own metrics).
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                    implicitWidth: Math.max(lineRest1.implicitWidth, lineHover1.implicitWidth)
                    implicitHeight: Math.max(lineRest1.implicitHeight, lineHover1.implicitHeight)
                    clip: true
                    C.AppText {
                        id: lineRest1
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        text: root.info.title || ""
                        weight: Tokens.weightBold
                        color: "#ffffff"
                        elide: Text.ElideRight
                        opacity: avatarHover.hovered ? 0.15 : 1
                        x: avatarHover.hovered ? -8 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    }
                    C.AppText {
                        id: lineHover1
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        text: root.info.channelTitle || ""
                        weight: Tokens.weightBold
                        color: "#ffffff"
                        elide: Text.ElideRight
                        opacity: avatarHover.hovered ? 1 : 0
                        x: avatarHover.hovered ? 0 : 8
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.info.watchUrl) Qt.openUrlExternally(root.info.watchUrl)
                    }
                }
                Item {
                    Layout.fillWidth: true
                    implicitWidth: Math.max(lineRest2.implicitWidth, lineHover2.implicitWidth)
                    implicitHeight: Math.max(lineRest2.implicitHeight, lineHover2.implicitHeight)
                    clip: true
                    C.AppText {
                        id: lineRest2
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        text: root.info.channelTitle || ""
                        font.pixelSize: Tokens.fontCaption
                        color: U.withAlpha(Qt.rgba(1, 1, 1, 1), 0.86)
                        elide: Text.ElideRight
                        opacity: avatarHover.hovered ? 0.15 : 1
                        x: avatarHover.hovered ? -8 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    }
                    C.AppText {
                        id: lineHover2
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        text: {
                            // "Unknown" is not "hidden". A count that was never
                            // resolved used to print "Subscribers hidden", which
                            // states something false about the channel — and is
                            // what the initials-only avatar next to it made
                            // look like a bug. Only claim hidden when the count
                            // is positively known to be private; otherwise show
                            // nothing rather than an assertion.
                            if (root.info.subsHidden)
                                return I18n.tr("Subscribers hidden")
                            if (root.info.subscriberCount)
                                return I18n.tr("{n} subscribers").replace(
                                    "{n}", Number(root.info.subscriberCount).toLocaleString(Qt.locale(), "f", 0))
                            return ""
                        }
                        font.pixelSize: Tokens.fontCaption
                        color: U.withAlpha(Qt.rgba(1, 1, 1, 1), 0.86)
                        elide: Text.ElideRight
                        opacity: avatarHover.hovered ? 1 : 0
                        x: avatarHover.hovered ? 0 : 8
                        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
        }

        // open on YouTube · close
        Row {
            id: topActions
            anchors { right: parent.right; top: parent.top; rightMargin: Tokens.space3; topMargin: Tokens.space3 }
            spacing: Tokens.space2
            opacity: stage.showChrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
            C.IconButton {
                visible: (root.info.watchUrl || "") !== ""
                iconName: "open_in_new"
                glyphSize: 17
                overlay: true
                accent: "#ffffff"
                tip: I18n.tr("Open on YouTube")
                tipBoundsName: "playerStage"
                onClicked: Qt.openUrlExternally(root.info.watchUrl)
            }
            C.IconButton {
                id: closeBtn
                iconName: "close"
                overlay: true
                accent: "#ffffff"
                tip: I18n.tr("Close") + "  (Esc)"
                tipBoundsName: "playerStage"
                onClicked: root.close()
            }
        }

        // ── centre: frosted play disc while paused ──
        // Not the old solid accent disc: a dark frosted ring with an accent
        // glyph reads as "paused" on any frame without shouting over it.
        C.IconButton {
            id: centrePlay
            anchors.centerIn: parent
            width: 84; height: 84
            glyphSize: 38
            visible: !root._audio && !root._busy && !root._failed && opacity > 0.01
            opacity: root._playing ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            iconName: "play_arrow"
            iconFill: true
            accent: "#ffffff"
            active: true
            chromeless: true
            tip: I18n.tr("Play") + "  (Space)"
            onClicked: root._toggle()
            Rectangle {
                z: -1
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(0.02, 0.02, 0.03, centrePlay.hovered ? 0.70 : 0.52)
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.22)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                // accent ring that tightens on hover
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: centrePlay.hovered ? -5 : -2
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: U.withAlpha(Theme.primary, centrePlay.hovered ? 0.85 : 0.0)
                    Behavior on anchors.margins { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }
            }
        }

        // ── opening / buffering ──
        Rectangle {
            anchors.centerIn: parent
            width: 64; height: 64
            radius: 32
            visible: root._busy && !root._failed
            color: Qt.rgba(0, 0, 0, 0.55)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
            C.SpinnerGlyph {
                anchors.centerIn: parent
                name: "autorenew"
                size: 28
                glyphColor: "#ffffff"
                spinning: parent.visible
            }
        }

        // ── cannot decode ──
        Rectangle {
            anchors.centerIn: parent
            visible: root._failed
            width: Math.min(parent.width - Tokens.space6 * 2, 440)
            height: errCol.implicitHeight + Tokens.space5 * 2
            radius: Tokens.radiusLg
            color: Qt.rgba(0.05, 0.05, 0.07, 0.92)
            border.width: 1
            border.color: U.withAlpha(Theme.error, 0.45)
            ColumnLayout {
                id: errCol
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space2
                C.IconGlyph {
                    name: "error"
                    fill: true
                    size: 26
                    glyphColor: Theme.error
                    Layout.alignment: Qt.AlignHCenter
                }
                C.AppText {
                    text: I18n.tr("This file can't be played here")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontLabel
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                C.AppText {
                    visible: text !== ""
                    text: media.errorString || ""
                    font.pixelSize: Tokens.fontCaption
                    color: Qt.rgba(1, 1, 1, 0.66)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        // ── feedback bubble (skip / volume / speed / mute) ──
        Item {
            id: flash
            property string icon: ""
            property string label: ""
            property int side: 0
            width: 96; height: 96
            anchors.verticalCenter: parent.verticalCenter
            x: side === 0 ? (parent.width - width) / 2
               : side < 0 ? parent.width * 0.2 - width / 2
               : parent.width * 0.8 - width / 2
            opacity: 0
            scale: 0.8
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.58)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
            }
            Column {
                anchors.centerIn: parent
                spacing: 2
                C.IconGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: flash.icon
                    fill: true
                    size: 30
                    glyphColor: "#ffffff"
                }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: flash.label !== ""
                    text: flash.label
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontCaption
                    color: "#ffffff"
                    LayoutMirroring.enabled: false
                }
            }
            ParallelAnimation {
                id: flashAnim
                SequentialAnimation {
                    NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 90; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: 380 }
                    NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 280; easing.type: Easing.InCubic }
                }
                NumberAnimation { target: flash; property: "scale"; from: 0.82; to: 1.0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
        }

        // ══════════ the dock — one floating glass capsule ══════════
        Rectangle {
            id: dock
            anchors {
                left: parent.left; right: parent.right; bottom: parent.bottom
                leftMargin: Tokens.space4; rightMargin: Tokens.space4; bottomMargin: Tokens.space4
            }
            height: dockCol.implicitHeight + Tokens.space3 * 2
            radius: Tokens.radiusXl
            color: Qt.rgba(0.04, 0.04, 0.06, 0.74)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            opacity: stage.showChrome ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            transform: Translate {
                y: stage.showChrome ? 0 : 14
                Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
            }
            // Swallow clicks so pressing a control never also toggles playback
            // through the body MouseArea underneath.
            MouseArea { anchors.fill: parent; onClicked: (m) => m.accepted = true }
            HoverHandler { id: dockHover }

            ColumnLayout {
                id: dockCol
                anchors.fill: parent
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space3
                anchors.topMargin: Tokens.space3
                anchors.bottomMargin: Tokens.space3
                spacing: Tokens.space2

                // ── music-player transport (audio-only downloads) ──
                RowLayout {
                    Layout.fillWidth: true
                    visible: root._audio
                    spacing: Tokens.space4
                    Item { Layout.fillWidth: true }
                    DockButton {
                        implicitWidth: 46; implicitHeight: 46; glyphSize: 22
                        iconName: "replay_10"
                        tip: I18n.tr("Back 10s")
                        onClicked: root._nudge(-10000, false)
                    }
                    C.IconButton {
                        id: audioPlay
                        tipAbove: true
                        tipBoundsName: "playerStage"
                        implicitWidth: 62; implicitHeight: 62; glyphSize: 30
                        chromeless: true
                        iconName: root._playing ? "pause" : "play_arrow"
                        iconFill: true
                        active: true
                        accent: Theme.on_primary
                        tip: root._playing ? I18n.tr("Pause") : I18n.tr("Play")
                        onClicked: root._toggle()
                        Rectangle {
                            z: -1
                            anchors.fill: parent
                            radius: width / 2
                            color: audioPlay.hovered ? Theme.primary_hover : Theme.primary
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                    }
                    DockButton {
                        implicitWidth: 46; implicitHeight: 46; glyphSize: 22
                        iconName: "forward_10"
                        tip: I18n.tr("Forward 10s")
                        onClicked: root._nudge(10000, false)
                    }
                    Item { Layout.fillWidth: true }
                }

                // ── seek line ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3

                    C.AppText {
                        visible: root._audio
                        text: root._fmt(media.position)
                        mono: true
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: "#ffffff"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        id: seek
                        Layout.fillWidth: true
                        implicitHeight: 22
                        readonly property real frac: media.duration > 0
                            ? Math.max(0, Math.min(1, media.position / media.duration)) : 0
                        readonly property bool hot: seekArea.containsMouse || root._seeking
                        readonly property real pointerFrac: width > 0
                            ? Math.max(0, Math.min(1, seekArea.mouseX / width)) : 0

                        Rectangle {
                            id: track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: seek.hot ? 6 : 4
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.20)
                            Behavior on height { NumberAnimation { duration: Tokens.durFast } }
                            // ghost: where a click would land
                            Rectangle {
                                width: seek.hot ? track.width * seek.pointerFrac : 0
                                height: parent.height
                                radius: parent.radius
                                color: Qt.rgba(1, 1, 1, 0.22)
                            }
                            // played
                            Rectangle {
                                width: track.width * seek.frac
                                height: parent.height
                                radius: parent.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.mix(Theme.primary, Qt.rgba(1, 1, 1, 1), 0.18) }
                                    GradientStop { position: 1.0; color: Theme.primary }
                                }
                            }
                        }
                        // play-head: a small white dot at rest, grows while hot
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: "#ffffff"
                            border.width: 3
                            border.color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                            x: track.width * seek.frac - width / 2
                            scale: seek.hot ? 1.0 : 0.55
                            Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                        }
                        // time bubble over the pointer
                        Rectangle {
                            visible: seek.hot && media.duration > 0
                            width: bubbleTxt.implicitWidth + Tokens.space3 * 2
                            height: 26
                            radius: Tokens.radiusSm
                            y: -height - Tokens.space2
                            x: Math.max(0, Math.min(seek.width - width,
                                                    seek.width * seek.pointerFrac - width / 2))
                            color: Qt.rgba(0.02, 0.02, 0.03, 0.92)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)
                            C.AppText {
                                id: bubbleTxt
                                anchors.centerIn: parent
                                text: root._fmt(seek.pointerFrac * media.duration)
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                color: "#ffffff"
                            }
                        }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            anchors.topMargin: -6
                            anchors.bottomMargin: -6
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (m) => { root._seeking = true; seekTo(m.x) }
                            onPositionChanged: (m) => { if (root._seeking) seekTo(m.x) }
                            onReleased: root._seeking = false
                            onCanceled: root._seeking = false
                            function seekTo(x) {
                                if (media.duration <= 0) return
                                var f = Math.max(0, Math.min(1, x / width))
                                media.position = Math.round(f * media.duration)
                            }
                        }
                    }

                    C.AppText {
                        visible: root._audio
                        text: root._fmt(media.duration)
                        mono: true
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: Qt.rgba(1, 1, 1, 0.66)
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // ── transport row ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space1

                    // play / pause — the one accent disc on the dock
                    C.IconButton {
                        id: playBtn
                        tipAbove: true
                        tipBoundsName: "playerStage"
                        visible: !root._audio
                        implicitWidth: 40; implicitHeight: 40
                        glyphSize: 22
                        chromeless: true
                        active: true
                        iconFill: true
                        accent: Theme.on_primary
                        iconName: root._playing ? "pause" : "play_arrow"
                        tip: (root._playing ? I18n.tr("Pause") : I18n.tr("Play")) + "  (K)"
                        onClicked: root._toggle()
                        Rectangle {
                            z: -1
                            anchors.fill: parent
                            radius: width / 2
                            color: playBtn.hovered ? Theme.primary_hover : Theme.primary
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                    }
                    Item { visible: !root._audio; implicitWidth: Tokens.space1 }
                    DockButton {
                        visible: !root._audio
                        iconName: "replay_10"
                        tip: I18n.tr("Back 10s") + "  (J)"
                        onClicked: root._nudge(-10000, false)
                    }
                    DockButton {
                        visible: !root._audio
                        iconName: "forward_10"
                        tip: I18n.tr("Forward 10s") + "  (L)"
                        onClicked: root._nudge(10000, false)
                    }

                    // volume: the slider folds out of the icon on hover
                    Item {
                        id: volGroup
                        readonly property bool open: volHover.hovered || volArea.pressed
                        implicitHeight: 38
                        implicitWidth: volBtn.implicitWidth + (open ? 96 : 0)
                        Behavior on implicitWidth { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        clip: true
                        HoverHandler { id: volHover }
                        DockButton {
                            id: volBtn
                            iconName: root._volIcon
                            tip: audioOut.muted ? I18n.tr("Unmute") + "  (M)" : I18n.tr("Mute") + "  (M)"
                            onClicked: root._toggleMute()
                        }
                        Item {
                            x: volBtn.implicitWidth + Tokens.space1
                            width: 84
                            height: parent.height
                            opacity: volGroup.open ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                            Rectangle {
                                id: volTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.24)
                                Rectangle {
                                    width: volTrack.width * root._vol
                                    height: parent.height
                                    radius: parent.radius
                                    color: "#ffffff"
                                }
                            }
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                                x: volTrack.width * root._vol - width / 2
                            }
                            MouseArea {
                                id: volArea
                                anchors.fill: parent
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (m) => root._setVolume(m.x / width, false)
                                onPositionChanged: (m) => { if (pressed) root._setVolume(m.x / width, false) }
                            }
                        }
                    }

                    // elapsed / total — click to flip to time remaining
                    Item {
                        visible: !root._audio
                        implicitWidth: timeRow.implicitWidth + Tokens.space3 * 2
                        implicitHeight: 30
                        Layout.alignment: Qt.AlignVCenter
                        HoverHandler { id: timeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root._showRemaining = !root._showRemaining }
                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radiusPill
                            color: Qt.rgba(1, 1, 1, timeHover.hovered ? 0.10 : 0.0)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        Row {
                            id: timeRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            C.AppText {
                                text: root._fmt(media.position)
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                color: "#ffffff"
                            }
                            C.AppText {
                                text: "/"
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Qt.rgba(1, 1, 1, 0.40)
                            }
                            C.AppText {
                                text: root._showRemaining
                                      ? "−" + root._fmt(Math.max(0, media.duration - media.position))
                                      : root._fmt(media.duration)
                                mono: true
                                weight: Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontCaption
                                color: Qt.rgba(1, 1, 1, 0.62)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // live state chips: speed (only when not 1×) + resolution
                    DockChip {
                        visible: root._rate !== 1.0
                        label: root._rateLabel(root._rate)
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: root._openSettings()
                    }
                    DockChip {
                        visible: (root._currentQualityLabel || "") !== ""
                        label: root._currentQualityLabel
                        lit: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: Tokens.space1
                        onClicked: root._openSettings()
                    }

                    DockButton {
                        id: gear
                        iconName: "tune"
                        // no tip while its own sheet is open (they'd overlap)
                        tip: settingsMenu.opened ? "" : I18n.tr("Speed & quality")
                        onClicked: settingsMenu.opened ? settingsMenu.close() : root._openSettings()

                        // ── settings sheet: speed + downloaded qualities ──
                        Popup {
                            id: settingsMenu
                            y: -height - Tokens.space4
                            x: gear.width - width + Tokens.space2
                            padding: Tokens.space3
                            onClosed: stage.forceActiveFocus()
                            background: Rectangle {
                                radius: Tokens.radiusLg
                                color: Qt.rgba(0.06, 0.06, 0.08, 0.97)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.10)
                            }
                            enter: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durFast }
                                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                            }
                            exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
                            contentItem: ColumnLayout {
                                spacing: Tokens.space2
                                LayoutMirroring.enabled: false

                                C.AppText {
                                    text: I18n.tr("Playback speed")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Qt.rgba(1, 1, 1, 0.56)
                                    Layout.leftMargin: Tokens.space1
                                }
                                Row {
                                    spacing: Tokens.space1
                                    Layout.bottomMargin: Tokens.space1
                                    Repeater {
                                        model: root._rates
                                        AbstractButton {
                                            id: rateBtn
                                            required property var modelData
                                            readonly property bool on: Math.abs(root._rate - modelData) < 0.001
                                            width: Math.max(44, rateLbl.implicitWidth + Tokens.space2 * 2)
                                            height: 30
                                            hoverEnabled: true
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            onClicked: root._setRate(modelData)
                                            background: Rectangle {
                                                radius: Tokens.radiusSm
                                                color: rateBtn.on ? Theme.primary
                                                       : Qt.rgba(1, 1, 1, rateBtn.hovered ? 0.12 : 0.05)
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: C.AppText {
                                                id: rateLbl
                                                text: root._rateLabel(rateBtn.modelData)
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: rateBtn.on ? Theme.on_primary : "#ffffff"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                }

                                C.AppText {
                                    text: I18n.tr("Downloaded quality")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Qt.rgba(1, 1, 1, 0.56)
                                    Layout.leftMargin: Tokens.space1
                                    Layout.topMargin: Tokens.space1
                                }
                                Repeater {
                                    model: root._variants
                                    AbstractButton {
                                        id: qBtn
                                        required property var modelData
                                        required property int index
                                        readonly property bool current: index === root._variantIndex
                                        Layout.fillWidth: true
                                        implicitWidth: qRow.implicitWidth + Tokens.space3 * 2
                                        implicitHeight: 36
                                        enabled: !current
                                        hoverEnabled: true
                                        HoverHandler { cursorShape: qBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        background: Rectangle {
                                            radius: Tokens.radiusSm
                                            color: qBtn.current ? U.withAlpha(Theme.primary, 0.16)
                                                   : Qt.rgba(1, 1, 1, qBtn.hovered ? 0.08 : 0.0)
                                        }
                                        contentItem: RowLayout {
                                            id: qRow
                                            spacing: Tokens.space2
                                            C.AppText {
                                                text: qBtn.modelData.label
                                                weight: qBtn.current ? Tokens.weightBold : Tokens.weightDemiBold
                                                color: qBtn.current ? Theme.primary : "#ffffff"
                                                Layout.fillWidth: true
                                                Layout.leftMargin: Tokens.space1
                                            }
                                            C.IconGlyph {
                                                name: "check"
                                                size: 15
                                                opacity: qBtn.current ? 1 : 0
                                                glyphColor: Theme.primary
                                                Layout.rightMargin: Tokens.space1
                                            }
                                        }
                                        onClicked: { root._switchVariant(index); settingsMenu.close() }
                                    }
                                }
                            }
                        }
                    }

                    DockButton {
                        visible: !root._audio
                        iconName: root._maximised ? "fullscreen_exit" : "fullscreen"
                        tip: (root._maximised ? I18n.tr("Shrink") : I18n.tr("Fill the window")) + "  (F)"
                        onClicked: root._maximised = !root._maximised
                    }
                }
            }
        }
        } // stageClip — everything above renders inside the rounded card
    }

    // ── actions ──
    function _toggle() {
        if (root._failed) return
        if (root._playing) media.pause()
        else media.play()
    }
    function _nudge(deltaMs, withFlash) {
        if (media.duration <= 0) return
        media.position = Math.max(0, Math.min(media.duration, media.position + deltaMs))
        if (withFlash)
            root._flash(deltaMs < 0 ? "replay_10" : "forward_10",
                        (deltaMs < 0 ? "−" : "+") + Math.round(Math.abs(deltaMs) / 1000) + "s",
                        deltaMs < 0 ? -1 : 1)
    }
    function _setVolume(v, withFlash) {
        audioOut.volume = Math.max(0, Math.min(1, v))
        if (audioOut.volume > 0) audioOut.muted = false
        if (withFlash)
            root._flash(root._volIcon, Math.round(root._vol * 100) + "%", 0)
    }
    function _toggleMute() {
        audioOut.muted = !audioOut.muted
        root._flash(root._volIcon, audioOut.muted ? "" : Math.round(root._vol * 100) + "%", 0)
    }
    function _setRate(r) {
        root._rate = r
        root._flash("speed", root._rateLabel(r), 0)
    }
    function _stepRate(dir) {
        var rs = root._rates
        var i = 0
        for (var j = 0; j < rs.length; ++j)
            if (Math.abs(rs[j] - root._rate) < 0.001) i = j
        i = Math.max(0, Math.min(rs.length - 1, i + dir))
        root._setRate(rs[i])
    }
    function _rateLabel(r) {
        return (Math.round(r * 100) / 100) + "×"
    }
    function _openSettings() {
        stage.chromeShown = true
        settingsMenu.open()
    }
    function _flash(icon, label, side) {
        flash.icon = icon
        flash.label = label
        flash.side = side
        flashAnim.restart()
    }
    // mm:ss, or h:mm:ss past an hour.
    function _fmt(ms) {
        if (!ms || ms < 0) ms = 0
        var t = Math.floor(ms / 1000)
        var h = Math.floor(t / 3600)
        var m = Math.floor((t % 3600) / 60)
        var s = t % 60
        function p(n) { return (n < 10 ? "0" : "") + n }
        return h > 0 ? (h + ":" + p(m) + ":" + p(s)) : (m + ":" + p(s))
    }
    // Switch to another downloaded resolution, keeping the play-head.
    function _switchVariant(i) {
        if (i < 0 || i >= root._variants.length) return
        var v = root._variants[i]
        var pos = media.position
        var wasPlaying = root._playing
        root._variantIndex = i
        media.source = v.fileUrl
        restore.pos = pos
        restore.resume = wasPlaying
        restore.restart()
    }
    Timer {
        id: restore
        interval: 140
        property int pos: 0
        property bool resume: false
        onTriggered: {
            media.position = restore.pos
            if (restore.resume) media.play()
        }
    }
}
