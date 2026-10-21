import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtMultimedia
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Video Cutter — v12 "Edit Bay".
//
// A ground-up rework of the page as a small editing suite instead of a form:
//
//   ┌ header ─────────────────────────────────────────── [⌨ shortcuts] ┐
//   ┌ source dock: [ YouTube | File ]  link / file …  [Paste] [Read]   ┐
//   ┌ MONITOR (16:9, viewfinder HUD) ─────────┐ ┌ INSPECTOR ──────────┐
//   │  colour bars + slate while empty        │ │ source · clip meter │
//   │  live preview once a video is read      │ │ IN / OUT editors    │
//   ├ transport: −10 ▶ +10  tc  loop  speed  │ │ length presets      │
//   └─────────────────────────────────────────┘ │ quality             │
//   ┌ EDIT BAY: ruler · filmstrip track · trim frame · zoom-to-clip   ┐
//   ┌ clip reel (history)                                              ┐
//   └ floating export dock: ready → cutting (tally) → done             ┘
//
// Signature: the empty monitor shows broadcast colour bars and a slate; the
// timeline is a filmstrip with a trim frame. Keyboard-first: Space, J / L,
// ← / →, I / O, P, Z and Ctrl+Enter drive the whole cut without the mouse.
//
// CutterVM API is untouched — this is a presentation pass. Timeline
// mechanics keep the v6 rules (own hit areas per handle, whole-second
// commits, push-instead-of-jam, pause while dragging) and add a zoom window.
Item {
    id: page

    property bool _clipPreview: false
    property bool _wasProbing: false
    // Preview failure state: DECODER errors only (see onErrorOccurred).
    property bool _previewFailed: false
    property string _previewError: ""
    // HD previews are video-only (YouTube ships sound with picture only at
    // 360p), so the sound comes from a second player — previewSound — that is
    // kept in lock-step with the picture. False = the picture has its own.
    readonly property bool _splitAudio: Cutter.mode === 0 && (Cutter.previewAudioUrl || "") !== ""
    // v3.41.5: cutting a YouTube link uses the full download engine, so it
    // needs every required component (JS runtime + PO Token helper).
    function _startCut() {
        if (Cutter.mode === 0 && !Geo.allowDownload()) return
        if (Cutter.mode === 0 && !Deno.ready) { Deno.requestInstall(); return }
        Cutter.startCut()
    }
    // How far the sound may drift from the picture before it is re-aligned.
    readonly property int _driftMs: 300
    readonly property var _rates: [1, 1.25, 1.5, 2, 0.5]
    property int _rateIdx: 0
    // v12: loop the clip while previewing it, and zoom the edit bay to it.
    property bool _loop: false
    property bool _zoom: false
    readonly property int _dockH: 88
    readonly property int _inspectorW: 392

    // ── clip reel paging (v3.52) ────────────────────────────────────────────
    // The reel used to build a card for EVERY clip in history. Each card is a
    // cover, a drag source, four chips and three buttons, so 200 clips meant
    // ~2,000 QML items constructed before the page could paint — that is the
    // "the Cutter takes a moment to land" feeling, and it got worse the more
    // you cut. One page of cards exists at a time now; the rest are a click
    // away, exactly like the Downloads page.
    readonly property int clipsPerPage: 9
    property int clipsPage: 0
    readonly property int clipsPageCount: Math.max(1, Math.ceil(Cutter.clipsCount / clipsPerPage))
    readonly property var pagedClips: {
        var all = Cutter.clips
        if (!all) return []
        var start = clipsPage * clipsPerPage
        return all.slice(start, start + clipsPerPage)
    }
    // A delete / clear-all can shrink the list under the current page.
    onClipsPageCountChanged: if (clipsPage > clipsPageCount - 1) clipsPage = clipsPageCount - 1

    // 0 source · 1 segment · 2 export — drives the header tracker.
    readonly property int _stage: Cutter.hasResult || Cutter.cutting ? 2
                                : Cutter.hasInfo ? 1 : 0
    readonly property bool _playing: previewPlayer.playbackState === MediaPlayer.PlayingState
    readonly property real _posSec: previewPlayer.position / 1000
    readonly property bool _inClip: Cutter.hasInfo && _posSec >= Cutter.startSec
                                    && _posSec <= Cutter.endSec
    readonly property real _clipLen: Math.max(0, Cutter.endSec - Cutter.startSec)
    readonly property bool _armed: Cutter.hasInfo && !Cutter.cutting
    readonly property bool _wide: content.width >= 1120
    readonly property bool _hasThumb: (Cutter.thumbId || "") !== ""
    readonly property string _thumbSrc: _hasThumb ? "image://thumbs/" + Cutter.thumbId : ""
    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    // A text box has the keyboard: page shortcuts must stand down so Space,
    // I, O and the arrows type / move the caret instead of driving the cut.
    readonly property bool _typing: {
        var f = Window.activeFocusItem
        return f !== null && f !== undefined && f.cursorPosition !== undefined
    }
    readonly property bool _keys: page.visible && !page._typing

    onVisibleChanged: {
        if (!visible && typeof previewPlayer !== "undefined" && previewPlayer)
            previewPlayer.pause()
    }

    function _fmt(ms) {
        if (!ms || ms < 0) ms = 0
        var t = Math.floor(ms / 1000)
        var h = Math.floor(t / 3600)
        var m = Math.floor((t % 3600) / 60)
        var s = t % 60
        function p(n) { return (n < 10 ? "0" : "") + n }
        return h > 0 ? (h + ":" + p(m) + ":" + p(s)) : (m + ":" + p(s))
    }
    // Broadcast-style timecode for the big counters: HH:MM:SS.t
    function _tc(sec) {
        if (!sec || sec < 0) sec = 0
        var tenth = Math.floor((sec * 10) % 10)
        var t = Math.floor(sec)
        var h = Math.floor(t / 3600)
        var m = Math.floor((t % 3600) / 60)
        var s = t % 60
        function p(n) { return (n < 10 ? "0" : "") + n }
        return p(h) + ":" + p(m) + ":" + p(s) + "." + tenth
    }
    // Resolution tier for a quality label ("1080p60" → "FHD").
    function _tier(label) {
        var m = /(\d{3,4})p/.exec(label || "")
        if (!m) return ""
        var h = parseInt(m[1])
        return h >= 2160 ? "4K" : h >= 1440 ? "2K" : h >= 1080 ? "FHD" : h >= 720 ? "HD" : "SD"
    }
    function _qualityLabel() {
        if (Cutter.mode === 1) return I18n.tr("Original")
        var q = Cutter.qualities
        var i = Cutter.qualityIndex
        return (q && i >= 0 && i < q.length) ? (q[i].label || "") : ""
    }

    // ── preview transport helpers ───────────────────────────────────────────
    function _seekSec(sec) {
        page._clipPreview = false
        if (typeof previewPlayer === "undefined" || !previewPlayer) return
        previewPlayer.position = Math.max(0, sec) * 1000
    }
    function _seekBy(deltaSec) {
        page._seekSec(Math.min(Math.max(1, Cutter.durationSec), page._posSec + deltaSec))
    }
    function _seekEdge(which) {
        page._seekSec(which === 0 ? Cutter.startSec : Cutter.endSec)
    }
    function _togglePlay() {
        if (!Cutter.hasInfo || Cutter.previewUrl === "") return
        page._clipPreview = false
        if (page._playing) previewPlayer.pause()
        else previewPlayer.play()
    }
    function _previewClip() {
        if (!Cutter.hasInfo || Cutter.endSec <= Cutter.startSec) return
        previewPlayer.position = Cutter.startSec * 1000
        page._clipPreview = true
        previewPlayer.play()
    }
    // The VM clamps start to [0, end] and end to [start, duration], so the
    // ORDER of the two writes decides whether a new range survives: moving the
    // whole range right must write the end first, moving it left the start.
    function _setRange(s, e) {
        var d = Math.max(0, Cutter.durationSec)
        s = Math.max(0, Math.min(d, s))
        e = Math.max(s, Math.min(d, e))
        page._clipPreview = false
        if (s > Cutter.endSec) { Cutter.endSec = e; Cutter.startSec = s }
        else { Cutter.startSec = s; Cutter.endSec = e }
    }
    // Mark In / Out at the play-head. Marking an In past the Out (or an Out
    // before the In) carries the other edge along, keeping the clip's length,
    // rather than collapsing the clip to zero.
    function _markIn() {
        if (!page._armed) return
        var p = Math.round(page._posSec)
        var len = Math.max(1, page._clipLen)
        if (p >= Cutter.endSec) page._setRange(p, Math.min(Cutter.durationSec, p + len))
        else Cutter.startSec = p
    }
    function _markOut() {
        if (!page._armed) return
        var p = Math.round(page._posSec)
        var len = Math.max(1, page._clipLen)
        if (p <= Cutter.startSec) page._setRange(Math.max(0, p - len), Math.max(1, p))
        else Cutter.endSec = p
    }
    // A fixed-length clip from the current In (Shorts presets). When the video
    // ends too soon, the window slides back so the length still holds.
    function _preset(len) {
        if (!page._armed) return
        var d = Cutter.durationSec
        if (len <= 0 || len >= d) { page._setRange(0, d); page._seekSec(0); return }
        var s = Cutter.startSec
        if (s + len > d) s = Math.max(0, d - len)
        page._setRange(s, s + len)
        page._seekEdge(0)
    }

    // v1.2: a new audio track swaps previewSound's source; if the picture is
    // playing, pick the new voice up at the same moment instead of going
    // silent until the next pause/play.
    Connections {
        target: Cutter
        function onAudioChanged() {
            Qt.callLater(function() {
                if (page._playing && page._splitAudio) {
                    page._syncSound(true)
                    previewSound.play()
                }
            })
        }
    }
    Connections {
        target: Cutter
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    // ── keyboard: the whole cut without the mouse ───────────────────────────
    Shortcut { sequences: ["Space"]; enabled: page._keys && Cutter.previewUrl !== ""; onActivated: page._togglePlay() }
    Shortcut { sequences: ["J"]; enabled: page._keys && page._armed; onActivated: page._seekBy(-10) }
    Shortcut { sequences: ["L"]; enabled: page._keys && page._armed; onActivated: page._seekBy(10) }
    Shortcut { sequences: ["Left"]; enabled: page._keys && page._armed; onActivated: page._seekBy(-1) }
    Shortcut { sequences: ["Right"]; enabled: page._keys && page._armed; onActivated: page._seekBy(1) }
    Shortcut { sequences: ["I"]; enabled: page._keys && page._armed; onActivated: page._markIn() }
    Shortcut { sequences: ["O"]; enabled: page._keys && page._armed; onActivated: page._markOut() }
    Shortcut { sequences: ["P"]; enabled: page._keys && page._armed; onActivated: page._previewClip() }
    Shortcut { sequences: ["Z"]; enabled: page._keys && Cutter.hasInfo; onActivated: page._zoom = !page._zoom }
    Shortcut { sequences: ["Shift+I"]; enabled: page._keys && page._armed; onActivated: page._seekEdge(0) }
    Shortcut { sequences: ["Shift+O"]; enabled: page._keys && page._armed; onActivated: page._seekEdge(1) }
    Shortcut {
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        enabled: page.visible && Cutter.canCut
        onActivated: page._startCut()
    }

    // ── preview engine (page level so every control can reach it) ──────────
    MediaPlayer {
        id: previewPlayer
        source: Cutter.previewUrl
        videoOutput: previewOut
        // The picture's own sound (progressive stream / local file). Mirrors
        // the page's volume + mute, and stays muted while previewSound plays
        // the separate track so the two can never double up.
        audioOutput: AudioOutput {
            id: videoAudio
            volume: previewAudio.volume
            muted: previewAudio.muted || page._splitAudio
        }
        // Stop before a new source loads so an old remote stream can't keep
        // buffering in the background (the long-video freeze fix). Never
        // autoplays: the user presses play.
        onSourceChanged: {
            page._clipPreview = false
            page._previewFailed = false
            page._previewError = ""
            page._rateIdx = 0
            playbackRate = 1
            stop()
        }
    }
    // ── separate sound track for HD (video-only) previews ───────────────────
    // Follows previewPlayer: same play / pause / stop, same speed, same
    // position. The picture is the master clock; the sound is nudged back
    // onto it whenever it drifts past _driftMs (seek, loop, a stall on either
    // stream), with a short cooldown so a slow network can't trigger a storm
    // of re-seeks.
    MediaPlayer {
        id: previewSound
        source: page._splitAudio ? Cutter.previewAudioUrl : ""
        audioOutput: AudioOutput { id: previewAudio; volume: 0.8 }
        playbackRate: previewPlayer.playbackRate
        onSourceChanged: stop()
        onMediaStatusChanged: {
            // Loaded after the user already pressed play: join in, in sync.
            if ((mediaStatus === MediaPlayer.LoadedMedia
                    || mediaStatus === MediaPlayer.BufferedMedia)
                    && page._playing && playbackState !== MediaPlayer.PlayingState) {
                page._syncSound(true)
                play()
            }
        }
        onErrorOccurred: (error, errorString) => {
            // A stale sound URL expires with the picture's: same fix.
            if (error === MediaPlayer.ResourceError
                    || error === MediaPlayer.NetworkError
                    || error === MediaPlayer.AccessDeniedError)
                Cutter.refreshPreview()
        }
    }
    Timer { id: soundCooldown; interval: 900; repeat: false }
    function _syncSound(force) {
        if (!page._splitAudio) return
        var v = previewPlayer.position
        var d = Math.abs(previewSound.position - v)
        if (force || d > page._driftMs) {
            previewSound.position = v
            soundCooldown.restart()
        }
    }
    Connections {
        target: previewPlayer
        enabled: page._splitAudio
        function onPlaybackStateChanged() {
            var st = previewPlayer.playbackState
            if (st === MediaPlayer.PlayingState) {
                page._syncSound(true)
                previewSound.play()
            } else if (st === MediaPlayer.PausedState) {
                previewSound.pause()
                page._syncSound(true)
            } else {
                previewSound.stop()
            }
        }
        function onPositionChanged() {
            if (!page._playing) {
                // Scrubbing while paused: keep the sound parked on the frame.
                if (Math.abs(previewSound.position - previewPlayer.position) > 40)
                    previewSound.position = previewPlayer.position
                return
            }
            var d = Math.abs(previewSound.position - previewPlayer.position)
            // A real jump (seek / loop) is fixed at once; ordinary drift
            // waits out the cooldown so a buffering stream can settle.
            if (d > 1500 || (d > page._driftMs && !soundCooldown.running))
                page._syncSound(true)
        }
        function onMediaStatusChanged() {
            var ms = previewPlayer.mediaStatus
            // Picture stalled for data: hold the sound so it doesn't run ahead.
            if (ms === MediaPlayer.StalledMedia) {
                previewSound.pause()
            } else if ((ms === MediaPlayer.BufferedMedia || ms === MediaPlayer.BufferingMedia)
                       && page._playing
                       && previewSound.playbackState !== MediaPlayer.PlayingState) {
                page._syncSound(true)
                previewSound.play()
            }
        }
    }
    Connections {
        target: previewPlayer
        function onPositionChanged() {
            if (page._clipPreview
                    && previewPlayer.position >= Cutter.endSec * 1000) {
                if (page._loop && Cutter.endSec > Cutter.startSec) {
                    // keep _clipPreview on so the next pass loops as well
                    previewPlayer.position = Cutter.startSec * 1000
                    return
                }
                previewPlayer.pause()
                previewPlayer.position = Cutter.endSec * 1000
                page._clipPreview = false
            }
        }
        function onErrorOccurred(error, errorString) {
            page._clipPreview = false
            // Expired/blocked URLs just need a fresh URL — the VM re-resolves.
            if (error === MediaPlayer.ResourceError
                    || error === MediaPlayer.NetworkError
                    || error === MediaPlayer.AccessDeniedError) {
                page._previewFailed = false
                page._previewError = ""
                Cutter.refreshPreview()
                return
            }
            // Anything else is the DECODER; re-probing returns the same bytes,
            // so show the failure card instead of looping probes.
            page._previewFailed = true
            page._previewError = errorString || ""
        }
        function onPlaybackStateChanged() {
            if (previewPlayer.playbackState === MediaPlayer.PlayingState) {
                page._previewFailed = false
                page._previewError = ""
            }
        }
    }
    // A fresh probe must never inherit the old stream: stop the decoder while
    // "Reading…". Cutter.probing notifies via `changed`, so edge-detect here.
    Connections {
        target: Cutter
        function onChanged() {
            var p = Cutter.probing
            if (p && !page._wasProbing
                    && typeof previewPlayer !== "undefined" && previewPlayer) {
                page._clipPreview = false
                page._previewFailed = false
                page._previewError = ""
                previewPlayer.stop()
            }
            page._wasProbing = p
        }
    }

    // ── shared building blocks ──────────────────────────────────────────────

    // A keyboard key, drawn. ASCII only, so it never mirrors in RTL.
    component Keycap: Rectangle {
        id: kc
        property string k: ""
        property bool onAccent: false
        implicitWidth: Math.max(20, kcLbl.implicitWidth + 10)
        implicitHeight: 20
        radius: 5
        color: kc.onAccent ? Qt.rgba(1, 1, 1, 0.18) : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.06)
        border.width: 1
        border.color: kc.onAccent ? Qt.rgba(1, 1, 1, 0.35) : U.withAlpha(Theme.on_surface, 0.16)
        LayoutMirroring.enabled: false
        // the key's lower lip
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1
            height: 2
            radius: 2
            color: kc.onAccent ? Qt.rgba(0, 0, 0, 0.18) : U.withAlpha(Theme.on_surface, 0.10)
        }
        C.AppText {
            id: kcLbl
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: kc.k
            mono: true
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontMicro
            color: kc.onAccent ? "#ffffff" : Theme.on_surface_var
        }
    }

    // Small uppercase panel label — the edit-suite "channel name".
    component BayLabel: Row {
        id: bl
        property string text: ""
        property string glyph: ""
        property color tint: Theme.on_surface_var
        spacing: 6
        C.IconGlyph {
            visible: bl.glyph !== ""
            name: bl.glyph; size: 13
            glyphColor: bl.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        C.AppText {
            text: I18n.rtl ? bl.text : bl.text.toUpperCase()
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontMicro
            font.letterSpacing: I18n.rtl ? 0 : 1.1
            color: bl.tint
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Small info chip (icon + text).
    component InfoChip: Rectangle {
        id: ic
        property string glyph: ""
        property string text: ""
        property color tint: Theme.on_surface_var
        property bool mono: false
        visible: text !== ""
        radius: Tokens.radiusPill
        implicitHeight: 24
        implicitWidth: icRow.implicitWidth + Tokens.space3 * 2
        color: String(tint) === String(Theme.on_surface_var) ? Theme.surface_low : U.withAlpha(tint, 0.12)
        border.width: 1
        border.color: String(tint) === String(Theme.on_surface_var) ? Theme.border : U.withAlpha(tint, 0.35)
        Row {
            id: icRow
            anchors.centerIn: parent
            spacing: 5
            C.IconGlyph {
                visible: ic.glyph !== ""
                name: ic.glyph; size: 12
                glyphColor: ic.tint
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: ic.text
                mono: ic.mono
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontMicro
                color: String(ic.tint) === String(Theme.on_surface_var) ? Theme.on_surface : ic.tint
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // One compact time-stepper (−10 / −1 / +1 / +10). ASCII labels only, so
    // the pill stays bidi-safe inside the Persian layout.
    component StepPill: AbstractButton {
        id: sp
        property string delta: ""
        property int stepFor: 0
        Layout.fillWidth: true
        implicitHeight: 32
        implicitWidth: stepLbl.implicitWidth + Tokens.space4
        hoverEnabled: true
        opacity: enabled ? 1 : 0.4
        scale: pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
        HoverHandler { cursorShape: sp.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        // hold to repeat — fine-tuning an edge by a few seconds is a hold,
        // not five clicks
        autoRepeat: true
        autoRepeatDelay: 380
        autoRepeatInterval: 110
        onClicked: {
            var d = parseFloat(delta)
            if (isNaN(d)) return
            if (stepFor === 0) Cutter.nudgeStart(d)
            else Cutter.nudgeEnd(d)
            page._seekEdge(stepFor)
        }
        background: Rectangle {
            radius: Tokens.radiusSm
            color: sp.pressed ? U.withAlpha(Theme.primary, 0.18)
                 : sp.hovered ? U.withAlpha(Theme.primary, 0.08)
                 : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.04 : 0.03)
            border.width: 1
            border.color: sp.hovered ? U.withAlpha(Theme.primary, 0.45) : Theme.border
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: C.AppText {
            id: stepLbl
            text: sp.delta + "s"
            mono: true
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontCaption
            color: sp.hovered ? Theme.primary : Theme.on_surface_var
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Round transport button.
    component RoundBtn: AbstractButton {
        id: rb
        property string glyph: ""
        property bool primary: false
        property bool lit: false
        property int d: 38
        property string tip: ""
        implicitWidth: d
        implicitHeight: d
        hoverEnabled: true
        opacity: enabled ? 1 : 0.4
        scale: pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
        HoverHandler { cursorShape: rb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: rb.primary ? U.mix(Theme.primary, Qt.rgba(1, 1, 1, 1), 0.12)
                                                   : rb.lit ? U.withAlpha(Theme.primary, 0.16)
                                                   : rb.hovered ? U.hoverTint(Theme.surface, Theme.isDark) : Theme.surface }
                GradientStop { position: 1.0; color: rb.primary ? U.mix(Theme.primary, Theme.primary_deep, 0.65)
                                                   : rb.lit ? U.withAlpha(Theme.primary, 0.16)
                                                   : rb.hovered ? U.hoverTint(Theme.surface, Theme.isDark) : Theme.surface }
            }
            border.width: rb.primary ? 0 : 1
            border.color: rb.lit ? U.withAlpha(Theme.primary, 0.5) : Theme.border
        }
        contentItem: Item {
            C.IconGlyph {
                anchors.centerIn: parent
                name: rb.glyph
                fill: rb.primary || rb.lit
                size: rb.primary ? Math.round(rb.d * 0.46) : 18
                glyphColor: rb.primary ? Theme.on_primary
                          : rb.lit || rb.hovered ? Theme.primary : Theme.on_surface
            }
        }
        C.AppTooltip { visible: rb.hovered && rb.tip !== ""; text: rb.tip }
    }

    // Broadcast colour bars (SMPTE-style), the monitor's "no signal" card.
    component ColorBars: Item {
        id: bars
        readonly property var _top: ["#c0c0c0", "#c0c000", "#00c0c0", "#00c000", "#c000c0", "#c00000", "#0000c0"]
        readonly property var _mid: ["#0000c0", "#131313", "#c000c0", "#131313", "#00c0c0", "#131313", "#c0c0c0"]
        Row {
            id: topBars
            width: parent.width
            height: Math.round(parent.height * 0.66)
            Repeater {
                model: bars._top
                Rectangle { width: bars.width / 7; height: topBars.height; color: modelData }
            }
        }
        Row {
            id: midBars
            y: topBars.height
            width: parent.width
            height: Math.round(parent.height * 0.09)
            Repeater {
                model: bars._mid
                Rectangle { width: bars.width / 7; height: midBars.height; color: modelData }
            }
        }
        Row {
            y: topBars.height + midBars.height
            width: parent.width
            height: parent.height - y
            Rectangle { width: bars.width * 5 / 28; height: parent.height; color: "#00214c" }
            Rectangle { width: bars.width * 5 / 28; height: parent.height; color: "#f0f0f0" }
            Rectangle { width: bars.width * 5 / 28; height: parent.height; color: "#32006a" }
            Rectangle { width: bars.width * 5 / 28; height: parent.height; color: "#131313" }
            Rectangle { width: bars.width / 21; height: parent.height; color: "#090909" }
            Rectangle { width: bars.width / 21; height: parent.height; color: "#131313" }
            Rectangle { width: bars.width / 21; height: parent.height; color: "#1d1d1d" }
            Rectangle { width: bars.width / 7; height: parent.height; color: "#131313" }
        }
    }

    // Viewfinder corner brackets over the monitor.
    component Corner: Item {
        id: cn
        property int arm: 22
        property color tint: Qt.rgba(1, 1, 1, 0.75)
        property bool flipX: false
        property bool flipY: false
        width: arm; height: arm
        Rectangle {
            x: cn.flipX ? cn.arm - width : 0
            y: cn.flipY ? cn.arm - height : 0
            width: cn.arm; height: 2; radius: 1
            color: cn.tint
        }
        Rectangle {
            x: cn.flipX ? cn.arm - width : 0
            y: cn.flipY ? 0 : 0
            width: 2; height: cn.arm; radius: 1
            color: cn.tint
        }
    }

    // ── the edit bay timeline ───────────────────────────────────────────────
    // A filmstrip track under a ruler. Click / drag anywhere to scrub; drag a
    // bracket to move a cut edge; drag the grip on top of the trim frame to
    // slide the whole clip. `page._zoom` narrows the view to the clip (+ a
    // margin) for frame-tight trims; the view freezes while dragging so the
    // ground never moves under the pointer.
    component TrimTimeline: Item {
        id: tl
        implicitHeight: 142

        readonly property real _dur: Math.max(1, Cutter.durationSec)
        readonly property int _hitW: 30
        property int _edge: 0       // 0 idle, 1 Start, 2 End, 3 slide
        property real _slideOff: 0
        property real _slideLen: 0
        property real _fzS: 0
        property real _fzE: 1
        readonly property bool _armed: page._armed
        readonly property bool _dragging: _edge !== 0

        // visible window [_vs, _ve] in seconds
        readonly property real _pad: Math.max(3, page._clipLen * 0.35)
        readonly property real _zs: page._zoom ? Math.max(0, Cutter.startSec - _pad) : 0
        readonly property real _ze: page._zoom ? Math.min(_dur, Cutter.endSec + _pad) : _dur
        readonly property real _vs: _dragging ? _fzS : _zs
        readonly property real _ve: _dragging ? _fzE : Math.max(_zs + 1, _ze)
        readonly property real _span: Math.max(1, _ve - _vs)

        // Live, un-rounded edges while a drag is in flight. The VM only stores
        // whole seconds, so binding the brackets straight to it made them hop
        // second-to-second (tens of px when zoomed in) and wait for a round
        // trip through Python on every move. The brackets now follow the
        // pointer 1:1 from these, and the VM is written only when the rounded
        // second actually changes.
        property real _liveS: 0
        property real _liveE: 0
        // What the timeline DRAWS: the live edge while dragging, the VM's
        // value otherwise — eased, so the release snap to the whole second
        // (and a typed / nudged / marked edge) glides instead of jumping.
        property real _showS: _dragging ? _liveS : Cutter.startSec
        property real _showE: _dragging ? _liveE : Cutter.endSec
        Behavior on _showS { enabled: !tl._dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on _showE { enabled: !tl._dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        readonly property real _sx: _px(_showS)
        readonly property real _ex: _px(_showE)
        readonly property real _phx: _px(page._posSec)
        // the two time tags collide when the edges are close
        readonly property bool _tight: (_ex - _sx) < 96

        function _px(sec) { return (sec - _vs) / _span * track.width }
        function _cx(sec) { return Math.max(0, Math.min(track.width, _px(sec))) }
        function _sec(x) { return _vs + Math.max(0, Math.min(1, x / Math.max(1, track.width))) * _span }
        function _dist(sec, x) { return Math.abs(x - _px(sec)) }

        // Ruler ticks: the smallest "nice" step that leaves ~96px per label.
        readonly property var _ticks: {
            var steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
            var want = Math.max(2, Math.floor(Math.max(1, track.width) / 96))
            var step = steps[steps.length - 1]
            for (var i = 0; i < steps.length; i++) {
                if (tl._span / steps[i] <= want) { step = steps[i]; break }
            }
            var out = []
            var half = step / 2
            var t0 = Math.ceil(tl._vs / half) * half
            for (var t = t0; t <= tl._ve + 0.001 && out.length < 400; t += half) {
                var major = Math.abs((t / step) - Math.round(t / step)) < 0.001
                out.push({ t: t, major: major })
            }
            return out
        }

        function _freeze() { tl._fzS = tl._zs; tl._fzE = Math.max(tl._zs + 1, tl._ze) }
        function _beginDrag(which) {
            tl._freeze()
            tl._liveS = Cutter.startSec
            tl._liveE = Cutter.endSec
            tl._edge = which
            page._clipPreview = false
            if (typeof previewPlayer !== "undefined" && previewPlayer)
                previewPlayer.pause()
        }
        function _endDrag() {
            if (tl._edge === 1 || tl._edge === 3) page._seekEdge(0)
            else if (tl._edge === 2) page._seekEdge(1)
            tl._edge = 0
        }
        // The brackets follow the pointer exactly (_liveS/_liveE); the VM gets
        // whole seconds, and only when the rounded value moves. A drag that
        // reaches the other edge pushes it (1s min).
        function _applyDrag(x) {
            var raw = tl._sec(x)
            var d = tl._dur
            var ls = tl._liveS, le = tl._liveE
            if (tl._edge === 1) {
                ls = Math.max(0, Math.min(raw, d - 1))
                if (le < ls + 1) le = Math.min(d, ls + 1)
            } else if (tl._edge === 2) {
                le = Math.max(1, Math.min(raw, d))
                if (ls > le - 1) ls = Math.max(0, le - 1)
            } else if (tl._edge === 3) {
                ls = Math.max(0, Math.min(Cutter.durationSec - tl._slideLen, raw - tl._slideOff))
                le = ls + tl._slideLen
            } else {
                return
            }
            tl._liveS = ls
            tl._liveE = le
            var rs = Math.round(ls)
            var re = Math.max(rs + 1, Math.round(le))
            if (tl._edge === 3) re = rs + tl._slideLen
            if (rs !== Cutter.startSec || re !== Cutter.endSec)
                page._setRange(rs, Math.min(d, re))
        }

        HoverHandler {
            id: tlHover
            cursorShape: tl._armed ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        readonly property real _hoverX: tlHover.point.position.x
        readonly property bool _showGhost: tlHover.hovered && tl._edge === 0 && tl._armed

        // ── ruler ──
        Item {
            id: ruler
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 28
            Repeater {
                model: tl._ticks
                Item {
                    readonly property real _x: tl._px(modelData.t)
                    x: _x
                    y: 0
                    width: 1
                    height: ruler.height
                    visible: _x >= -1 && _x <= track.width + 1
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: 1
                        height: modelData.major ? 9 : 5
                        color: Theme.outline
                        opacity: modelData.major ? 0.75 : 0.4
                    }
                    C.AppText {
                        visible: modelData.major
                        y: 0
                        x: parent._x < 30 ? 3 : (parent._x > track.width - 30 ? -implicitWidth - 3 : -implicitWidth / 2)
                        text: page._fmt(modelData.t * 1000)
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.outline
                    }
                }
            }
        }

        // ── the filmstrip ──
        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            y: ruler.height + 6
            height: 76
            radius: Tokens.radiusMd
            color: "#0c0c10"
            clip: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)

            readonly property int _bandY: 13
            readonly property int _bandH: height - _bandY * 2
            readonly property int _cellW: Math.round(_bandH * 16 / 9)

            // frames
            Row {
                x: 0
                y: track._bandY
                spacing: 2
                Repeater {
                    model: Math.max(0, Math.ceil(track.width / (track._cellW + 2)) + 1)
                    Item {
                        width: track._cellW
                        height: track._bandH
                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            visible: !page._hasThumb
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.20) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary_deep, 0.10) }
                            }
                        }
                        Image {
                            anchors.fill: parent
                            visible: page._hasThumb
                            source: page._thumbSrc
                            sourceSize.width: track._cellW * 2
                            sourceSize.height: track._bandH * 2
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            opacity: 0.9
                        }
                    }
                }
            }
            // sprocket holes, top and bottom
            Repeater {
                model: 2
                Row {
                    y: index === 0 ? 4 : track.height - 9
                    x: 5
                    spacing: 9
                    Repeater {
                        model: Math.max(0, Math.ceil(track.width / 16))
                        Rectangle { width: 7; height: 5; radius: 1.5; color: Qt.rgba(1, 1, 1, 0.13) }
                    }
                }
            }
            // already-played wash
            Rectangle {
                width: tl._cx(page._posSec)
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.05)
            }
            // outside-the-clip dim
            Rectangle {
                x: 0
                width: tl._cx(tl._showS)
                height: parent.height
                color: Qt.rgba(0, 0, 0, 0.66)
            }
            Rectangle {
                x: tl._cx(tl._showE)
                width: Math.max(0, track.width - x)
                height: parent.height
                color: Qt.rgba(0, 0, 0, 0.66)
            }
            // a faint accent tint inside the clip
            Rectangle {
                x: tl._cx(tl._showS)
                width: Math.max(0, tl._cx(tl._showE) - x)
                height: parent.height
                color: U.withAlpha(Theme.primary, 0.10)
            }
            // hover ghost line
            Rectangle {
                visible: tl._showGhost
                x: Math.round(tl._hoverX)
                width: 1
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.45)
            }
        }

        // trim frame (outside the clipped track so its stroke isn't cut)
        Rectangle {
            id: frame
            readonly property real _l: tl._cx(tl._showS)
            readonly property real _r: tl._cx(tl._showE)
            x: _l
            y: track.y - 2
            width: Math.max(4, _r - _l)
            height: track.height + 4
            radius: Tokens.radiusSm
            color: "transparent"
            border.width: 3
            border.color: Theme.primary
            visible: Cutter.hasInfo
            // the clip glows a touch while the preview plays inside it
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: parent.radius + 4
                color: "transparent"
                border.width: 4
                border.color: U.withAlpha(Theme.primary, 0.22)
                opacity: page._inClip && page._playing ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
        }

        // play-head: flag on the ruler, line through the strip
        Item {
            id: playhead
            visible: Cutter.hasInfo && tl._phx >= -1 && tl._phx <= track.width + 1
            x: tl._phx - width / 2
            y: ruler.height - 12
            width: 14
            height: track.y + track.height - y + 4
            z: 4
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 2
                height: parent.height - 8
                radius: 1
                color: "#ffffff"
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 12; height: 12
                radius: 3
                rotation: 45
                color: "#ffffff"
                border.width: 2
                border.color: Theme.primary
            }
        }

        // hover time flag (on the ruler, over its labels)
        Rectangle {
            visible: tl._showGhost
            x: Math.max(0, Math.min(tl.width - width, tl._hoverX - width / 2))
            y: 0
            radius: Tokens.radiusXs
            implicitWidth: ghostLbl.implicitWidth + 12
            implicitHeight: 18
            color: Theme.surface_high
            border.width: 1
            border.color: U.withAlpha(Theme.primary, 0.45)
            z: 5
            C.AppText {
                id: ghostLbl
                anchors.centerIn: parent
                text: page._fmt(tl._sec(tl._hoverX) * 1000)
                mono: true
                font.pixelSize: Tokens.fontMicro
                color: Theme.on_surface
            }
        }

        // Scrub surface — handles sit above it, so a press off a handle can
        // only mean "move the play-head". Pauses while scrubbing.
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: track.y + track.height
            z: 1
            enabled: tl._armed
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => {
                page._clipPreview = false
                if (typeof previewPlayer !== "undefined" && previewPlayer)
                    previewPlayer.pause()
                scrub(mouse.x)
            }
            onPositionChanged: (mouse) => { if (pressed) scrub(mouse.x) }
            function scrub(x) {
                previewPlayer.position = Math.round(tl._sec(x) * 1000)
            }
        }

        // slide grip — top centre of the trim frame
        Item {
            id: slideHit
            visible: Cutter.hasInfo && (frame._r - frame._l) > 64
            x: (frame._l + frame._r) / 2 - width / 2
            y: track.y - 11
            width: 46
            height: 20
            z: 3
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusPill
                color: tl._edge === 3 ? U.mix(Theme.primary, Qt.rgba(1, 1, 1, 1), 0.2) : Theme.primary
                scale: slideMa.containsMouse || tl._edge === 3 ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: 3
                        Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.on_primary }
                    }
                }
            }
            MouseArea {
                id: slideMa
                anchors.fill: parent
                enabled: tl._armed
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: (m) => {
                    var gx = m.x + slideHit.x
                    tl._beginDrag(3)
                    tl._slideLen = Math.max(1, Math.round(page._clipLen))
                    tl._slideOff = tl._sec(gx) - Cutter.startSec
                }
                onPositionChanged: (m) => { if (pressed) tl._applyDrag(m.x + slideHit.x) }
                onReleased: tl._endDrag()
                onCanceled: tl._endDrag()
            }
            C.AppTooltip { visible: slideMa.containsMouse && tl._edge === 0; text: I18n.tr("Drag to slide the whole clip") }
        }

        // bracket handles
        Item {
            id: startHit
            visible: Cutter.hasInfo && tl._sx >= -tl._hitW && tl._sx <= track.width + tl._hitW
            x: tl._sx - width / 2
            y: track.y - 4
            width: tl._hitW
            height: track.height + 8
            z: 2
            Handle {
                anchors.right: parent.horizontalCenter
                anchors.rightMargin: -2
                anchors.verticalCenter: parent.verticalCenter
                leading: true
                active: tl._edge === 1
                hovered: shMa.containsMouse
            }
            MouseArea {
                id: shMa
                anchors.fill: parent
                enabled: tl._armed
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.SizeHorCursor
                onPressed: (m) => {
                    // Both handles under the cursor: the nearer edge wins.
                    if (tl._dist(Cutter.endSec, m.x + startHit.x)
                            < tl._dist(Cutter.startSec, m.x + startHit.x)) {
                        m.accepted = false
                        return
                    }
                    tl._beginDrag(1)
                }
                onPositionChanged: (m) => { if (pressed) tl._applyDrag(m.x + startHit.x) }
                onReleased: tl._endDrag()
                onCanceled: tl._endDrag()
            }
        }
        Item {
            id: endHit
            visible: Cutter.hasInfo && tl._ex >= -tl._hitW && tl._ex <= track.width + tl._hitW
            x: tl._ex - width / 2
            y: track.y - 4
            width: tl._hitW
            height: track.height + 8
            z: 2
            Handle {
                anchors.left: parent.horizontalCenter
                anchors.leftMargin: -2
                anchors.verticalCenter: parent.verticalCenter
                leading: false
                active: tl._edge === 2
                hovered: ehMa.containsMouse
            }
            MouseArea {
                id: ehMa
                anchors.fill: parent
                enabled: tl._armed
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.SizeHorCursor
                onPressed: (m) => {
                    if (tl._dist(Cutter.startSec, m.x + endHit.x)
                            < tl._dist(Cutter.endSec, m.x + endHit.x)) {
                        m.accepted = false
                        return
                    }
                    tl._beginDrag(2)
                }
                onPositionChanged: (m) => { if (pressed) tl._applyDrag(m.x + endHit.x) }
                onReleased: tl._endDrag()
                onCanceled: tl._endDrag()
            }
        }

        // live time tags under each bracket
        EdgeTag {
            visible: Cutter.hasInfo && (!tl._tight || tl._edge !== 2)
            label: "IN  " + Cutter.startLabel
            hot: tl._edge === 1 || tl._edge === 3
            y: track.y + track.height + 8
            x: Math.max(0, Math.min(tl.width - width, tl._cx(tl._showS) - width / 2
                        - (tl._tight && tl._edge === 0 ? width / 2 + 3 : 0)))
        }
        EdgeTag {
            visible: Cutter.hasInfo && (!tl._tight || tl._edge !== 1)
            label: "OUT  " + Cutter.endLabel
            hot: tl._edge === 2 || tl._edge === 3
            y: track.y + track.height + 8
            x: Math.max(0, Math.min(tl.width - width, tl._cx(tl._showE) - width / 2
                        + (tl._tight && tl._edge === 0 ? width / 2 + 3 : 0)))
        }
    }

    // A trim bracket: a solid accent jaw with grip lines, shaped like [ or ].
    component Handle: Rectangle {
        id: hd
        property bool active: false
        property bool hovered: false
        property bool leading: true
        width: 14
        height: 84
        topLeftRadius: leading ? 6 : 2
        bottomLeftRadius: leading ? 6 : 2
        topRightRadius: leading ? 2 : 6
        bottomRightRadius: leading ? 2 : 6
        color: active ? U.mix(Theme.primary, Qt.rgba(1, 1, 1, 1), 0.18) : Theme.primary
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        transform: Scale {
            origin.x: hd.width / 2
            origin.y: hd.height / 2
            xScale: hd.active ? 1.25 : hd.hovered ? 1.12 : 1.0
            Behavior on xScale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
        }
        Row {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: 2
                Rectangle { width: 2; height: 18; radius: 1; color: U.withAlpha(Theme.on_primary, 0.85) }
            }
        }
    }

    // Time tag under a bracket.
    component EdgeTag: Rectangle {
        id: et
        property string label: ""
        property bool hot: false
        radius: Tokens.radiusSm
        implicitWidth: etLbl.implicitWidth + Tokens.space3
        implicitHeight: 22
        color: hot ? Theme.primary : U.withAlpha(Theme.primary, 0.14)
        border.width: 1
        border.color: U.withAlpha(Theme.primary, hot ? 0 : 0.45)
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        C.AppText {
            id: etLbl
            anchors.centerIn: parent
            text: et.label
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: Tokens.fontMicro
            color: et.hot ? Theme.on_primary : Theme.primary
        }
    }

    // An IN / OUT editor: the edge's timecode as a big typed field, steppers
    // that repeat while held, jump-to and mark-at-play-head with their keys.
    component EdgeCard: Rectangle {
        id: ec
        property int which: 0
        readonly property bool isStart: which === 0
        readonly property string edgeLabel: isStart ? Cutter.startLabel : Cutter.endLabel
        readonly property bool _on: page._armed

        Layout.fillWidth: true
        implicitHeight: ecCol.implicitHeight + Tokens.space3 * 2
        radius: Tokens.radiusLg
        color: Theme.surface_low
        border.width: 1
        border.color: timeField.activeFocus ? Theme.primary : Theme.border
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

        ColumnLayout {
            id: ecCol
            anchors.fill: parent
            anchors.margins: Tokens.space3
            spacing: Tokens.space2

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                // the bracket glyph, drawn: [ for In, ] for Out
                Item {
                    width: 22; height: 22
                    Layout.alignment: Qt.AlignVCenter
                    LayoutMirroring.enabled: false
                    Rectangle {
                        x: ec.isStart ? 6 : 13
                        y: 2
                        width: 3; height: 18; radius: 1
                        color: Theme.primary
                    }
                    Rectangle {
                        x: ec.isStart ? 6 : 9
                        y: 2
                        width: 7; height: 3; radius: 1
                        color: Theme.primary
                    }
                    Rectangle {
                        x: ec.isStart ? 6 : 9
                        y: 17
                        width: 7; height: 3; radius: 1
                        color: Theme.primary
                    }
                }
                C.AppText {
                    text: ec.isStart ? I18n.tr("Start") : I18n.tr("End")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontBody
                    color: Theme.text_strong
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                C.IconButton {
                    implicitWidth: 30; implicitHeight: 30
                    iconName: "play_circle"
                    glyphSize: 16
                    accent: Theme.primary
                    enabled: ec._on
                    tip: I18n.tr("Jump the preview here") + (ec.isStart ? "  (Shift+I)" : "  (Shift+O)")
                    onClicked: page._seekEdge(ec.which)
                }
            }

            // big time input
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 50
                radius: Tokens.radiusMd
                color: timeField.activeFocus ? Theme.input_bg : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.03 : 0.02)
                border.width: 1
                border.color: timeField.activeFocus ? Theme.primary : Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.space3
                    anchors.rightMargin: Tokens.space2
                    spacing: Tokens.space2
                    LayoutMirroring.enabled: false
                    TextField {
                        id: timeField
                        // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                        T.ContextMenu.menu: C.EditMenu { editor: timeField }
                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                        selectedTextColor: Theme.text_strong
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        enabled: ec._on
                        text: ec.edgeLabel
                        placeholderText: "0:00"
                        placeholderTextColor: Theme.outline
                        color: Theme.text_strong
                        font.family: Fonts.mono
                        font.pixelSize: Tokens.fontTitle + 2
                        font.weight: Font.Bold
                        selectByMouse: true
                        background: null
                        leftPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        // Re-bind after Enter: typing breaks the `text:` binding,
                        // so without this later timeline drags would stop
                        // updating the box.
                        onAccepted: {
                            if (ec.isStart) Cutter.setStartText(text)
                            else Cutter.setEndText(text)
                            text = Qt.binding(function () { return ec.edgeLabel })
                            page._seekEdge(ec.which)
                            timeField.focus = false
                        }
                        Keys.onEscapePressed: {
                            text = Qt.binding(function () { return ec.edgeLabel })
                            timeField.focus = false
                        }
                    }
                    C.IconGlyph {
                        visible: timeField.activeFocus
                        name: "corner_down_left"; size: 15
                        glyphColor: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    // mark at play-head — the edit-suite I / O
                    AbstractButton {
                        id: markBtn
                        visible: !timeField.activeFocus
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 34
                        implicitWidth: markRow.implicitWidth + Tokens.space3 * 2
                        enabled: ec._on
                        hoverEnabled: true
                        opacity: enabled ? 1 : 0.45
                        onClicked: ec.isStart ? page._markIn() : page._markOut()
                        HoverHandler { cursorShape: markBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        background: Rectangle {
                            radius: Tokens.radiusSm
                            color: markBtn.pressed ? U.withAlpha(Theme.primary, 0.26)
                                 : markBtn.hovered ? U.withAlpha(Theme.primary, 0.16)
                                 : U.withAlpha(Theme.primary, 0.09)
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, markBtn.hovered ? 0.55 : 0.30)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        contentItem: Item {
                            Row {
                                id: markRow
                                anchors.centerIn: parent
                                spacing: 6
                                C.IconGlyph {
                                    name: "target"; size: 14
                                    glyphColor: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Keycap {
                                    k: ec.isStart ? "I" : "O"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                        C.AppTooltip {
                            visible: markBtn.hovered
                            text: ec.isStart ? I18n.tr("Set Start") : I18n.tr("Set End")
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space1
                LayoutMirroring.enabled: false
                StepPill { stepFor: ec.which; delta: "-10"; enabled: ec._on }
                StepPill { stepFor: ec.which; delta: "-1"; enabled: ec._on }
                StepPill { stepFor: ec.which; delta: "+1"; enabled: ec._on }
                StepPill { stepFor: ec.which; delta: "+10"; enabled: ec._on }
            }
        }
    }

    // Inspector section: a glass card with a bay label and a body.
    component InspectorCard: C.GlassPanel {
        id: icard
        property string label: ""
        property string glyph: ""
        default property alias body: icBody.data
        property alias trailing: icTrail.data
        Layout.fillWidth: true
        radius_: Tokens.radiusXl
        implicitHeight: icCol.implicitHeight + Tokens.space4 * 2
        ColumnLayout {
            id: icCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space4
            spacing: Tokens.space3
            RowLayout {
                Layout.fillWidth: true
                visible: icard.label !== ""
                spacing: Tokens.space2
                BayLabel { text: icard.label; glyph: icard.glyph; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                Row { id: icTrail; spacing: Tokens.space1; Layout.alignment: Qt.AlignVCenter }
            }
            ColumnLayout {
                id: icBody
                Layout.fillWidth: true
                spacing: Tokens.space3
            }
        }
    }

    // ── scrollable content ──────────────────────────────────────────────────
    C.SmoothScrollView {
        id: scroller
        anchors.fill: parent
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Item {
            id: canvas
            width: parent.width
            implicitHeight: content.implicitHeight + Tokens.space7 * 2
                            + (Cutter.hasInfo ? page._dockH + Tokens.space5 : 0)

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 420
            }

            ColumnLayout {
                id: content
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space6
                spacing: Tokens.space4

                // ── header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space5

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2

                        Rectangle {
                            radius: Tokens.radiusPill
                            color: U.withAlpha(Theme.primary, 0.10)
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, 0.28)
                            implicitWidth: eyebrowRow.implicitWidth + Tokens.space3 * 2
                            implicitHeight: 28
                            Row {
                                id: eyebrowRow
                                anchors.centerIn: parent
                                spacing: Tokens.space2
                                // tally light: red while a cut is running
                                Rectangle {
                                    id: tally
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Cutter.cutting ? Theme.error : Theme.primary
                                    SequentialAnimation on opacity {
                                        running: (Cutter.cutting || Cutter.probing) && page.visible
                                        loops: Animation.Infinite
                                        alwaysRunToEnd: true
                                        NumberAnimation { to: 0.25; duration: 520; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutQuad }
                                    }
                                }
                                C.AppText {
                                    text: I18n.rtl ? I18n.tr("Video Cutter") : I18n.tr("Video Cutter").toUpperCase()
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    font.letterSpacing: I18n.rtl ? 0 : 1.2
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            C.AppText {
                                text: I18n.tr("Cut the moment,")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Math.round(Math.max(26, Math.min(38, content.width / 40)))
                                color: Theme.text_strong
                            }
                            C.AppText {
                                text: I18n.tr("not the whole video.")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: Math.round(Math.max(26, Math.min(38, content.width / 40)))
                                color: Theme.primary
                            }
                        }
                        C.AppText {
                            text: I18n.tr("A YouTube link or a file on this PC, trimmed to the second and saved at its own quality up to 4K.")
                            font.pixelSize: Tokens.fontLabel
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            Layout.maximumWidth: 720
                        }
                    }

                    // live tracker: Source → Segment → Export
                    Rectangle {
                        visible: content.width > 940
                        Layout.alignment: Qt.AlignBottom
                        radius: Tokens.radiusXl
                        color: Theme.panel_bg
                        border.width: 1
                        border.color: Theme.border
                        implicitHeight: 52
                        implicitWidth: trackRow.implicitWidth + Tokens.space4 * 2
                        Row {
                            id: trackRow
                            anchors.centerIn: parent
                            spacing: Tokens.space2
                            Repeater {
                                model: [I18n.tr("Source"), I18n.tr("Segment"), I18n.tr("Export")]
                                Row {
                                    id: tkRow
                                    spacing: Tokens.space2
                                    readonly property bool _done: page._stage > index || (index === 2 && Cutter.hasResult)
                                    readonly property bool _cur: page._stage === index && !_done
                                    Rectangle {
                                        visible: index > 0
                                        width: 22; height: 2; radius: 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: page._stage >= index ? Theme.primary : Theme.border
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                    }
                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: tkRow._done || tkRow._cur ? Theme.primary : U.withAlpha(Theme.primary, 0)
                                        border.width: tkRow._done || tkRow._cur ? 0 : 1
                                        border.color: Theme.outline
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        C.AppText {
                                            anchors.centerIn: parent
                                            visible: !tkRow._done
                                            text: index + 1
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontMicro
                                            color: tkRow._cur ? Theme.on_primary : Theme.on_surface_var
                                        }
                                        C.IconGlyph {
                                            anchors.centerIn: parent
                                            visible: tkRow._done
                                            name: "check"; size: 13
                                            glyphColor: Theme.on_primary
                                        }
                                    }
                                    C.AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        weight: tkRow._cur ? Tokens.weightBold : Tokens.weightMedium
                                        font.pixelSize: Tokens.fontCaption
                                        color: tkRow._cur ? Theme.text_strong : Theme.on_surface_var
                                    }
                                }
                            }
                        }
                    }

                    // keyboard cheat-sheet
                    AbstractButton {
                        id: keysBtn
                        Layout.alignment: Qt.AlignBottom
                        implicitWidth: 52
                        implicitHeight: 52
                        hoverEnabled: true
                        onClicked: keysPop.opened ? keysPop.close() : keysPop.open()
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: Tokens.radiusXl
                            color: keysPop.opened ? U.withAlpha(Theme.primary, 0.14)
                                 : keysBtn.hovered ? U.hoverTint(Theme.panel_bg, Theme.isDark) : Theme.panel_bg
                            border.width: 1
                            border.color: keysPop.opened || keysBtn.hovered ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        contentItem: Item {
                            C.IconGlyph {
                                anchors.centerIn: parent
                                name: "command"; size: 20
                                glyphColor: keysPop.opened || keysBtn.hovered ? Theme.primary : Theme.on_surface_var
                            }
                        }
                        C.AppTooltip { visible: keysBtn.hovered && !keysPop.opened; text: I18n.tr("Keyboard shortcuts") }

                        Popup {
                            id: keysPop
                            y: keysBtn.height + Tokens.space2
                            x: I18n.rtl ? 0 : keysBtn.width - width
                            width: 300
                            padding: Tokens.space4
                            modal: false
                            focus: false
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                            enter: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                            }
                            exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
                            background: C.GlassPanel { radius_: Tokens.radiusLg; elevation: 2 }
                            contentItem: ColumnLayout {
                                spacing: Tokens.space2
                                BayLabel { text: I18n.tr("Keyboard shortcuts"); glyph: "command"; tint: Theme.primary }
                                Repeater {
                                    model: [
                                        { k: "Space",      t: I18n.tr("Play / pause") },
                                        { k: "J / L",      t: I18n.tr("Back / forward 10s") },
                                        { k: "← / →",      t: I18n.tr("Back / forward 1s") },
                                        { k: "I / O",      t: I18n.tr("Mark Start / End at the play-head") },
                                        { k: "Shift + I / O", t: I18n.tr("Jump to Start / End") },
                                        { k: "P",          t: I18n.tr("Preview clip") },
                                        { k: "Z",          t: I18n.tr("Zoom the timeline to the clip") },
                                        { k: "Ctrl+Enter", t: I18n.tr("Cut & Download") }
                                    ]
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space3
                                        Keycap { k: modelData.k; Layout.alignment: Qt.AlignVCenter }
                                        C.AppText {
                                            text: modelData.t
                                            font.pixelSize: Tokens.fontCaption + 1
                                            color: Theme.on_surface
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── source dock ──
                C.GlassPanel {
                    id: sourceDock
                    Layout.fillWidth: true
                    radius_: Tokens.radiusXl
                    border.color: linkField.activeFocus ? U.mix(Theme.border, Theme.primary, 0.5) : Theme.border
                    implicitHeight: dockCol.implicitHeight + Tokens.space3 * 2

                    ColumnLayout {
                        id: dockCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space3
                        spacing: Tokens.space2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2

                            // sliding mode switch
                            Rectangle {
                                id: modeSeg
                                readonly property int segW: content.width > 760 ? 148 : 56
                                Layout.preferredWidth: segW * 2 + 8
                                Layout.preferredHeight: 50
                                Layout.alignment: Qt.AlignVCenter
                                radius: Tokens.radiusLg
                                color: Theme.input_bg
                                border.width: 1
                                border.color: Theme.border
                                LayoutMirroring.enabled: false
                                Rectangle {
                                    x: 4 + Cutter.mode * modeSeg.segW
                                    y: 4
                                    width: modeSeg.segW
                                    height: parent.height - 8
                                    radius: Tokens.radiusMd
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Theme.primary }
                                        GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.6) }
                                    }
                                    Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                }
                                Row {
                                    x: 4; y: 4
                                    Repeater {
                                        model: [ { label: I18n.tr("YouTube link"), icon: "youtube" },
                                                 { label: I18n.tr("Local file"), icon: "folder_open" } ]
                                        AbstractButton {
                                            id: modeBtn
                                            width: modeSeg.segW
                                            height: modeSeg.height - 8
                                            readonly property bool on: Cutter.mode === index
                                            enabled: !Cutter.cutting && !Cutter.probing
                                            opacity: enabled ? 1 : 0.5
                                            hoverEnabled: true
                                            onClicked: Cutter.mode = index
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            background: Item { }
                                            contentItem: Item {
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space2
                                                    C.IconGlyph {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        name: modelData.icon; size: 17
                                                        fill: modeBtn.on
                                                        glyphColor: modeBtn.on ? Theme.on_primary
                                                                  : modeBtn.hovered ? Theme.text_strong : Theme.on_surface_var
                                                    }
                                                    C.AppText {
                                                        visible: modeSeg.segW > 100
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.label
                                                        weight: Tokens.weightDemiBold
                                                        font.pixelSize: Tokens.fontCaption + 1
                                                        color: modeBtn.on ? Theme.on_primary
                                                             : modeBtn.hovered ? Theme.text_strong : Theme.on_surface_var
                                                    }
                                                }
                                            }
                                            C.AppTooltip { visible: modeBtn.hovered && modeSeg.segW <= 100; text: modelData.label }
                                        }
                                    }
                                }
                            }

                            // link field
                            Rectangle {
                                id: linkBar
                                visible: Cutter.mode === 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                Layout.alignment: Qt.AlignVCenter
                                radius: Tokens.radiusLg
                                color: linkField.activeFocus ? Theme.input_bg : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.03 : 0.02)
                                border.width: 1
                                border.color: linkField.activeFocus ? Theme.primary : Theme.border
                                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.space3
                                    anchors.rightMargin: Tokens.space1
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: "link"; size: 18
                                        glyphColor: linkField.activeFocus ? Theme.primary : Theme.outline
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    TextField {
                                        id: linkField
                                        // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                        T.ContextMenu.menu: C.EditMenu { editor: linkField }
                                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                        selectedTextColor: Theme.text_strong
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Cutter.link
                                        onTextChanged: Cutter.link = text
                                        onAccepted: if (!Cutter.probing) Cutter.fetchInfo()
                                        enabled: !Cutter.cutting
                                        placeholderText: "https://www.youtube.com/watch?v=…"
                                        placeholderTextColor: Theme.outline
                                        color: Theme.on_surface
                                        font.family: Fonts.mono
                                        font.pixelSize: Tokens.fontBody
                                        verticalAlignment: TextInput.AlignVCenter
                                        selectByMouse: true
                                        background: null
                                        LayoutMirroring.enabled: false
                                        horizontalAlignment: TextInput.AlignLeft
                                    }
                                    C.IconButton {
                                        visible: linkField.text !== "" && !Cutter.probing && !Cutter.cutting
                                        implicitWidth: 32; implicitHeight: 32
                                        Layout.alignment: Qt.AlignVCenter
                                        iconName: "close"
                                        glyphSize: 15
                                        tip: I18n.tr("Clear")
                                        onClicked: { linkField.text = ""; linkField.forceActiveFocus() }
                                    }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: "content_paste"
                                        text: I18n.tr("Paste")
                                        implicitHeight: 40
                                        Layout.alignment: Qt.AlignVCenter
                                        enabled: !Cutter.cutting && !Cutter.probing
                                        onClicked: Cutter.pasteLink()
                                    }
                                }
                            }

                            // file picker strip
                            Rectangle {
                                id: fileTile
                                visible: Cutter.mode === 1
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                Layout.alignment: Qt.AlignVCenter
                                radius: Tokens.radiusLg
                                color: tileHover.hovered || dropZone.containsDrag
                                       ? U.withAlpha(Theme.primary, 0.07) : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.03 : 0.02)
                                border.width: 1
                                border.color: tileHover.hovered || dropZone.containsDrag
                                              ? U.withAlpha(Theme.primary, 0.55) : Theme.border_med
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    enabled: !Cutter.cutting && !Cutter.probing
                                    onTapped: fileDialog.open()
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.space3
                                    anchors.rightMargin: Tokens.space1
                                    spacing: Tokens.space3
                                    C.IconGlyph {
                                        name: Cutter.filePath !== "" ? "movie" : "folder_open"
                                        size: 18
                                        fill: Cutter.filePath !== ""
                                        glyphColor: Cutter.filePath !== "" || tileHover.hovered ? Theme.primary : Theme.outline
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: Cutter.filePath !== "" ? Cutter.fileName
                                                                     : I18n.tr("Drop a video here, or click to browse")
                                        weight: Cutter.filePath !== "" ? Tokens.weightBold : Tokens.weightRegular
                                        color: Cutter.filePath !== "" ? Theme.text_strong : Theme.outline
                                        elide: Text.ElideMiddle
                                    }
                                    C.AppText {
                                        visible: Cutter.filePath === "" && content.width > 900
                                        text: "MP4 · MKV · WEBM · MOV · AVI · M4V"
                                        mono: true
                                        font.pixelSize: Tokens.fontMicro
                                        color: Theme.outline
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    C.PrimaryButton {
                                        variant: "ghost"
                                        iconName: "folder_open"
                                        text: I18n.tr("Browse…")
                                        implicitHeight: 40
                                        enabled: !Cutter.cutting && !Cutter.probing
                                        Layout.alignment: Qt.AlignVCenter
                                        onClicked: fileDialog.open()
                                    }
                                }
                            }

                            C.PrimaryButton {
                                iconName: "search"
                                text: Cutter.probing ? I18n.tr("Reading…")
                                      : Cutter.mode === 0 ? I18n.tr("Read video") : I18n.tr("Read file")
                                enabled: !Cutter.probing && !Cutter.cutting
                                         && (Cutter.mode === 0 ? linkField.text.trim() !== "" : Cutter.filePath !== "")
                                indeterminate: Cutter.probing
                                implicitHeight: 50
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: Cutter.fetchInfo()
                            }
                        }

                        // status line
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Tokens.space2
                            Layout.rightMargin: Tokens.space2
                            visible: Cutter.statusText !== ""
                            spacing: Tokens.space2
                            readonly property color _c: Cutter.statusKind === "error" ? Theme.error
                                                      : Cutter.statusKind === "warn" ? Theme.warn
                                                      : Cutter.statusKind === "ok" ? Theme.secondary_container
                                                      : Theme.outline
                            Item {
                                width: 12; height: 12
                                Layout.alignment: Qt.AlignVCenter
                                Rectangle {
                                    id: stHalo
                                    anchors.centerIn: parent
                                    width: 7; height: 7; radius: 4
                                    color: parent.parent._c
                                    opacity: 0
                                }
                                ParallelAnimation {
                                    running: Cutter.probing && page.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { target: stHalo; property: "scale"; from: 1; to: 2.6; duration: 1300 }
                                    NumberAnimation { target: stHalo; property: "opacity"; from: 0.6; to: 0; duration: 1300 }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 7; height: 7; radius: 4
                                    color: parent.parent._c
                                }
                            }
                            C.AppText {
                                text: Cutter.statusText
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Tokens.fontCaption
                                color: Cutter.statusKind === "" || Cutter.statusKind === "info" || Cutter.statusKind === "muted"
                                       ? Theme.on_surface_var : parent._c
                            }
                        }
                    }
                }

                // ── studio: monitor + inspector ──
                GridLayout {
                    id: studio
                    Layout.fillWidth: true
                    columns: page._wide ? 2 : 1
                    columnSpacing: Tokens.space4
                    rowSpacing: Tokens.space4

                    // ── monitor column ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Tokens.space3

                        // the monitor: a dark bezel around the picture
                        Rectangle {
                            id: monitor
                            Layout.fillWidth: true
                            implicitHeight: Math.min(760, Math.round((width - 12) * 9 / 16)) + 12
                            radius: Tokens.radiusXl
                            color: "#09090c"
                            border.width: 1
                            border.color: page._inClip && page._playing
                                          ? U.withAlpha(Theme.primary, 0.70)
                                          : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.18))
                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

                            Item {
                                id: stage
                                anchors.fill: parent
                                anchors.margins: 6
                                clip: true
                                HoverHandler { id: stageHover }

                                readonly property bool _live: Cutter.hasInfo
                                // the picture's real rect inside the stage
                                readonly property rect _pic: previewOut.contentRect

                                Rectangle { anchors.fill: parent; radius: Tokens.radiusXs; color: "#000000" }

                                // ── no-signal card: colour bars + slate ──
                                Item {
                                    id: noSignal
                                    anchors.fill: parent
                                    visible: !stage._live
                                    ColorBars {
                                        anchors.fill: parent
                                        opacity: Cutter.probing ? 0.55 : 0.85
                                        Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                                    }
                                    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, Cutter.probing ? 0.62 : 0.50) }
                                    // a scan line while the video is being read
                                    Rectangle {
                                        id: scanLine
                                        visible: Cutter.probing
                                        width: parent.width
                                        height: 46
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                            GradientStop { position: 0.85; color: U.withAlpha(Theme.primary, 0.30) }
                                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.55) }
                                        }
                                        NumberAnimation on y {
                                            running: Cutter.probing && page.visible
                                            loops: Animation.Infinite
                                            from: -scanLine.height
                                            to: noSignal.height
                                            duration: 1600
                                            easing.type: Easing.InOutSine
                                        }
                                    }
                                    // the slate
                                    Rectangle {
                                        id: slate
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - Tokens.space6 * 2, 520)
                                        height: slateCol.implicitHeight + Tokens.space5 * 2
                                        radius: Tokens.radiusLg
                                        color: Qt.rgba(0.04, 0.04, 0.05, 0.86)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        HoverHandler { id: slateHover; cursorShape: Cutter.probing ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                        TapHandler {
                                            enabled: !Cutter.probing && !Cutter.cutting
                                            onTapped: {
                                                if (Cutter.mode === 1) fileDialog.open()
                                                else linkField.forceActiveFocus()
                                            }
                                        }
                                        // clapper stripes along the top
                                        Row {
                                            id: clapper
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 1
                                            height: 10
                                            clip: true
                                            LayoutMirroring.enabled: false
                                            Repeater {
                                                model: 24
                                                Rectangle {
                                                    width: 26; height: 10
                                                    color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(0, 0, 0, 0)
                                                    transform: Matrix4x4 {
                                                        matrix: Qt.matrix4x4(1, -0.9, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
                                                    }
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            id: slateCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: Tokens.space5
                                            anchors.topMargin: Tokens.space5 + 8
                                            spacing: Tokens.space2
                                            C.AppText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: Cutter.probing ? "READING SIGNAL" : "NO SOURCE"
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                font.letterSpacing: 3
                                                color: Cutter.probing ? Theme.primary : Qt.rgba(1, 1, 1, 0.55)
                                                LayoutMirroring.enabled: false
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Cutter.probing ? I18n.tr("Reading the video…")
                                                      : Cutter.mode === 1 ? I18n.tr("Drop a video here, or click to browse")
                                                      : I18n.tr("Paste a YouTube link above")
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: Tokens.fontTitle
                                                color: "#ffffff"
                                                wrapMode: Text.Wrap
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Cutter.probing
                                                      ? I18n.tr("Only the length and qualities are fetched, not the video itself.")
                                                      : I18n.tr("The full video is never downloaded — only the part you cut.")
                                                font.pixelSize: Tokens.fontCaption + 1
                                                color: Qt.rgba(1, 1, 1, 0.66)
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }
                                }

                                // ── live picture ──
                                VideoOutput {
                                    id: previewOut
                                    anchors.fill: parent
                                    visible: stage._live
                                    fillMode: VideoOutput.PreserveAspectFit
                                }
                                // poster until the first frame lands
                                Image {
                                    anchors.fill: parent
                                    visible: stage._live && !previewPlayer.hasVideo && page._hasThumb
                                    source: page._thumbSrc
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                }
                                // click the picture to play / pause, double-click
                                // to preview just the clip
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: stage._live && !page._previewFailed && Cutter.previewUrl !== ""
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page._togglePlay()
                                    onDoubleClicked: page._previewClip()
                                }

                                // 9:16 Shorts safe frame over the real picture
                                Item {
                                    id: shortsGuide
                                    property bool on: false
                                    visible: on && stage._live && previewPlayer.hasVideo
                                    readonly property real _h: stage._pic.height > 0 ? stage._pic.height : stage.height
                                    readonly property real _cx: stage._pic.width > 0 ? stage._pic.x + stage._pic.width / 2 : stage.width / 2
                                    readonly property real _y0: stage._pic.height > 0 ? stage._pic.y : 0
                                    readonly property real _w: Math.min(_h * 9 / 16, stage.width)
                                    anchors.fill: parent
                                    Rectangle {
                                        x: 0; y: shortsGuide._y0
                                        width: Math.max(0, shortsGuide._cx - shortsGuide._w / 2)
                                        height: shortsGuide._h
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                    }
                                    Rectangle {
                                        x: shortsGuide._cx + shortsGuide._w / 2; y: shortsGuide._y0
                                        width: Math.max(0, stage.width - x)
                                        height: shortsGuide._h
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                    }
                                    Rectangle {
                                        x: shortsGuide._cx - shortsGuide._w / 2; y: shortsGuide._y0
                                        width: shortsGuide._w
                                        height: shortsGuide._h
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Theme.primary
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: Tokens.space2
                                            radius: Tokens.radiusSm
                                            color: Theme.primary
                                            implicitWidth: sgLbl.implicitWidth + 12
                                            implicitHeight: 20
                                            C.AppText {
                                                id: sgLbl
                                                anchors.centerIn: parent
                                                text: "9:16"
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: Tokens.fontMicro
                                                color: Theme.on_primary
                                            }
                                        }
                                    }
                                }

                                // viewfinder corners
                                Item {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space4
                                    visible: stage._live
                                    opacity: stageHover.hovered || !page._playing ? 0.9 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                                    Corner { anchors.left: parent.left; anchors.top: parent.top }
                                    Corner { anchors.right: parent.right; anchors.top: parent.top; flipX: true }
                                    Corner { anchors.left: parent.left; anchors.bottom: parent.bottom; flipY: true }
                                    Corner { anchors.right: parent.right; anchors.bottom: parent.bottom; flipX: true; flipY: true }
                                }

                                // top scrim + HUD
                                Rectangle {
                                    visible: stage._live
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: 72
                                    opacity: stageHover.hovered || !page._playing ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.62) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
                                    }
                                    Row {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.space4
                                        spacing: Tokens.space2
                                        LayoutMirroring.enabled: false
                                        Rectangle {
                                            radius: Tokens.radiusSm
                                            implicitWidth: hudTime.implicitWidth + 16
                                            implicitHeight: 26
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.16)
                                            C.AppText {
                                                id: hudTime
                                                anchors.centerIn: parent
                                                text: page._tc(page._posSec)
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: "#ffffff"
                                            }
                                        }
                                        Rectangle {
                                            visible: page._rateIdx !== 0
                                            radius: Tokens.radiusSm
                                            implicitWidth: hudRate.implicitWidth + 14
                                            implicitHeight: 26
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            C.AppText {
                                                id: hudRate
                                                anchors.centerIn: parent
                                                text: page._rates[page._rateIdx] + "×"
                                                mono: true
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: "#ffffff"
                                            }
                                        }
                                        Rectangle {
                                            visible: page._loop
                                            radius: Tokens.radiusSm
                                            implicitWidth: 30
                                            implicitHeight: 26
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            C.IconGlyph {
                                                anchors.centerIn: parent
                                                name: "sync"; size: 14
                                                glyphColor: "#ffffff"
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.space4
                                        radius: Tokens.radiusPill
                                        implicitWidth: inClipRow.implicitWidth + 18
                                        implicitHeight: 26
                                        color: page._inClip ? Theme.primary : Qt.rgba(0, 0, 0, 0.55)
                                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                        Row {
                                            id: inClipRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            C.IconGlyph {
                                                name: "scissors"; size: 13
                                                glyphColor: page._inClip ? Theme.on_primary : "#ffffff"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            C.AppText {
                                                text: page._inClip ? I18n.tr("Inside the clip") : I18n.tr("Outside the clip")
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontMicro
                                                color: page._inClip ? Theme.on_primary : "#ffffff"
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                // bottom scrubline across the picture (whole video)
                                Item {
                                    visible: stage._live
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 4
                                    opacity: stageHover.hovered || !page._playing ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                    readonly property real _d: Math.max(1, Cutter.durationSec)
                                    Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.12) }
                                    Rectangle {
                                        x: parent.width * Math.min(1, Cutter.startSec / parent._d)
                                        width: Math.max(2, parent.width * Math.min(1, page._clipLen / parent._d))
                                        height: parent.height
                                        color: U.withAlpha(Theme.primary, 0.75)
                                    }
                                    Rectangle {
                                        width: parent.width * Math.min(1, page._posSec / parent._d)
                                        height: parent.height
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                    }
                                }

                                // loading pill
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Tokens.space5
                                    implicitWidth: loadRow.implicitWidth + Tokens.space4 * 2
                                    implicitHeight: 32
                                    radius: Tokens.radiusPill
                                    color: Qt.rgba(0, 0, 0, 0.72)
                                    visible: stage._live && (Cutter.previewUrl === ""
                                             || previewPlayer.mediaStatus === MediaPlayer.LoadingMedia
                                             || previewPlayer.mediaStatus === MediaPlayer.StalledMedia
                                             || previewPlayer.mediaStatus === MediaPlayer.BufferingMedia)
                                    Row {
                                        id: loadRow
                                        anchors.centerIn: parent
                                        spacing: Tokens.space2
                                        C.SpinnerGlyph {
                                            name: "autorenew"; size: 14
                                            glyphColor: "#ffffff"
                                            spinning: parent.parent.visible
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        C.AppText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Cutter.previewUrl === "" ? I18n.tr("Preparing preview…")
                                                  : previewPlayer.bufferProgress > 0 && previewPlayer.bufferProgress < 1
                                                  ? I18n.tr("Loading… {p}%").replace("{p}", Math.round(previewPlayer.bufferProgress * 100))
                                                  : I18n.tr("Loading…")
                                            mono: true
                                            font.pixelSize: Tokens.fontCaption
                                            color: "#ffffff"
                                        }
                                    }
                                }

                                // big play button with a breathing ring
                                Item {
                                    anchors.centerIn: parent
                                    width: 96; height: 96
                                    visible: stage._live && Cutter.previewUrl !== "" && !page._playing && !page._previewFailed
                                    Rectangle {
                                        id: playRing
                                        anchors.centerIn: parent
                                        width: 92; height: 92; radius: 46
                                        color: "transparent"
                                        border.width: 2
                                        border.color: U.withAlpha(Theme.primary, 0.6)
                                        SequentialAnimation on scale {
                                            running: playRing.visible && page._motion && Tokens.appActive
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0.84; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                                            NumberAnimation { from: 1.0; to: 0.84; duration: 1100; easing.type: Easing.InOutSine }
                                        }
                                    }
                                    RoundBtn {
                                        anchors.centerIn: parent
                                        d: 70
                                        primary: true
                                        glyph: "play_arrow"
                                        onClicked: { page._clipPreview = false; previewPlayer.play() }
                                    }
                                }

                                // decoder-failure card
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Tokens.space3
                                    radius: Tokens.radiusMd
                                    color: Qt.rgba(0, 0, 0, 0.82)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.warn, 0.45)
                                    visible: page._previewFailed
                                    height: errCol.implicitHeight + Tokens.space3 * 2
                                    Column {
                                        id: errCol
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space3
                                        spacing: Tokens.space2
                                        Row {
                                            spacing: Tokens.space2
                                            C.IconGlyph { name: "warning"; size: 15; fill: true; glyphColor: Theme.warn }
                                            C.AppText {
                                                width: errCol.width - 24
                                                text: I18n.tr("Preview can't play this stream on your PC — Cut & Download still works.")
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: "#ffffff"
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                        C.AppText {
                                            width: parent.width
                                            visible: page._previewError !== ""
                                            text: page._previewError
                                            mono: true
                                            font.pixelSize: Tokens.fontMicro
                                            color: U.withAlpha(Qt.rgba(1, 1, 1, 1), 0.75)
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                        }
                                        C.PrimaryButton {
                                            variant: "ghost"
                                            iconName: "refresh"
                                            text: I18n.tr("Retry preview")
                                            implicitHeight: 34
                                            onClicked: {
                                                page._previewFailed = false
                                                page._previewError = ""
                                                Cutter.refreshPreview()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── transport bar ──
                        Rectangle {
                            Layout.fillWidth: true
                            visible: Cutter.hasInfo
                            implicitHeight: 62
                            radius: Tokens.radiusXl
                            color: Theme.panel_bg
                            border.width: 1
                            border.color: Theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.space3
                                anchors.rightMargin: Tokens.space3
                                spacing: Tokens.space2
                                LayoutMirroring.enabled: false

                                RoundBtn {
                                    glyph: "replay_10"
                                    tip: I18n.tr("Back 10s") + "  (J)"
                                    enabled: page._armed
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: page._seekBy(-10)
                                }
                                RoundBtn {
                                    d: 46
                                    primary: true
                                    glyph: page._playing ? "pause" : "play_arrow"
                                    tip: (page._playing ? I18n.tr("Pause") : I18n.tr("Play")) + "  (Space)"
                                    enabled: Cutter.previewUrl !== ""
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: page._togglePlay()
                                }
                                RoundBtn {
                                    glyph: "forward_10"
                                    tip: I18n.tr("Forward 10s") + "  (L)"
                                    enabled: page._armed
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: page._seekBy(10)
                                }
                                // timecode
                                Column {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.leftMargin: Tokens.space2
                                    spacing: 0
                                    C.AppText {
                                        text: page._tc(page._posSec)
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: Tokens.fontSubtitle
                                        color: Theme.text_strong
                                    }
                                    C.AppText {
                                        text: "/ " + Cutter.durationText
                                        mono: true
                                        font.pixelSize: Tokens.fontMicro
                                        color: Theme.on_surface_var
                                    }
                                }
                                Item { Layout.fillWidth: true }

                                // loop the clip preview
                                RoundBtn {
                                    glyph: "sync"
                                    lit: page._loop
                                    tip: page._loop ? I18n.tr("Loop clip: on") : I18n.tr("Loop clip: off")
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: page._loop = !page._loop
                                }
                                // 9:16 safe frame
                                AbstractButton {
                                    id: guideBtn
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 38
                                    Layout.alignment: Qt.AlignVCenter
                                    hoverEnabled: true
                                    onClicked: shortsGuide.on = !shortsGuide.on
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Tokens.radiusPill
                                        color: shortsGuide.on ? U.withAlpha(Theme.primary, 0.16)
                                             : guideBtn.hovered ? U.hoverTint(Theme.surface, Theme.isDark) : Theme.surface
                                        border.width: 1
                                        border.color: shortsGuide.on ? U.withAlpha(Theme.primary, 0.5) : Theme.border
                                    }
                                    contentItem: C.AppText {
                                        text: "9:16"
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: shortsGuide.on || guideBtn.hovered ? Theme.primary : Theme.on_surface_var
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    C.AppTooltip { visible: guideBtn.hovered; text: I18n.tr("Show the Shorts (9:16) frame") }
                                }
                                // playback speed
                                AbstractButton {
                                    id: rateBtn
                                    Layout.preferredWidth: 56
                                    Layout.preferredHeight: 38
                                    Layout.alignment: Qt.AlignVCenter
                                    hoverEnabled: true
                                    onClicked: {
                                        page._rateIdx = (page._rateIdx + 1) % page._rates.length
                                        previewPlayer.playbackRate = page._rates[page._rateIdx]
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Tokens.radiusPill
                                        color: page._rateIdx !== 0 ? U.withAlpha(Theme.primary, 0.14)
                                             : rateBtn.hovered ? U.hoverTint(Theme.surface, Theme.isDark) : Theme.surface
                                        border.width: 1
                                        border.color: page._rateIdx !== 0 ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                                    }
                                    contentItem: C.AppText {
                                        text: page._rates[page._rateIdx] + "×"
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: page._rateIdx === 0 ? Theme.on_surface_var : Theme.primary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    C.AppTooltip { visible: rateBtn.hovered; text: I18n.tr("Playback speed") }
                                }
                                C.IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: content.width > 700
                                    iconName: previewAudio.muted || previewAudio.volume <= 0 ? "volume_off" : "volume_up"
                                    accent: Theme.on_surface_var
                                    tip: previewAudio.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
                                    onClicked: previewAudio.muted = !previewAudio.muted
                                }
                                Slider {
                                    id: volSlider
                                    visible: content.width > 700
                                    Layout.preferredWidth: 88
                                    Layout.alignment: Qt.AlignVCenter
                                    from: 0; to: 1
                                    value: previewAudio.muted ? 0 : previewAudio.volume
                                    onMoved: {
                                        previewAudio.volume = value
                                        if (value > 0) previewAudio.muted = false
                                    }
                                    background: Rectangle {
                                        x: volSlider.leftPadding
                                        y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 88
                                        implicitHeight: 4
                                        width: volSlider.availableWidth; height: 4; radius: 2
                                        color: Theme.surface_high
                                        Rectangle {
                                            width: volSlider.visualPosition * parent.width
                                            height: parent.height; radius: 2
                                            color: Theme.primary
                                        }
                                    }
                                    handle: Rectangle {
                                        x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                                        y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 14
                                        implicitHeight: 14
                                        width: 14; height: 14; radius: 7
                                        color: Theme.slider_handle
                                        border.width: 2; border.color: Theme.primary
                                        scale: volSlider.pressed ? 1.15 : 1
                                        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }

                        // ── the two edges, under the transport ──
                        // v3.27: Start / End used to stack in the inspector, which
                        // made that column ~350px taller than the monitor and left
                        // a dead black hole under the player. In / out points
                        // belong next to the play-head controls anyway (that is
                        // where every edit suite puts them), so they now sit here
                        // side by side and the inspector keeps source, length and
                        // output.
                        GridLayout {
                            id: edgeRow
                            Layout.fillWidth: true
                            visible: Cutter.hasInfo
                            columns: monitor.width >= 600 ? 2 : 1
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3
                            EdgeCard { which: 0; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop }
                            EdgeCard { which: 1; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop }
                        }
                    }

                    // ── inspector column ──
                    ColumnLayout {
                        Layout.fillWidth: !page._wide
                        Layout.preferredWidth: page._wide ? page._inspectorW : -1
                        Layout.maximumWidth: page._wide ? page._inspectorW : Number.POSITIVE_INFINITY
                        Layout.alignment: Qt.AlignTop
                        spacing: Tokens.space3

                        // ── empty: how it works ──
                        InspectorCard {
                            visible: !Cutter.hasInfo
                            label: I18n.tr("How it works")
                            glyph: "route"
                            Repeater {
                                model: [
                                    { icon: "link",     title: I18n.tr("Bring a video"),
                                      text: I18n.tr("Paste a YouTube link, or pick a video file you already have.") },
                                    { icon: "crop_square", title: I18n.tr("Mark the moment"),
                                      text: I18n.tr("Drag the brackets on the filmstrip, or press I and O at the play-head.") },
                                    { icon: "scissors", title: I18n.tr("Cut it out"),
                                      text: I18n.tr("Pick a quality, then Cut & Download — just that clip is saved.") }
                                ]
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space3
                                    // numbered because it IS a sequence
                                    Item {
                                        Layout.preferredWidth: 34
                                        Layout.fillHeight: true
                                        Rectangle {
                                            id: howDot
                                            width: 34; height: 34; radius: 17
                                            color: index === 0 ? Theme.primary : U.withAlpha(Theme.primary, 0.10)
                                            border.width: index === 0 ? 0 : 1
                                            border.color: U.withAlpha(Theme.primary, 0.35)
                                            C.AppText {
                                                anchors.centerIn: parent
                                                text: index + 1
                                                mono: true
                                                weight: Tokens.weightExtraBold
                                                font.pixelSize: Tokens.fontBody
                                                color: index === 0 ? Theme.on_primary : Theme.primary
                                            }
                                        }
                                        Rectangle {
                                            visible: index < 2
                                            anchors.horizontalCenter: howDot.horizontalCenter
                                            anchors.top: howDot.bottom
                                            anchors.topMargin: 4
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: -Tokens.space3 + 4
                                            width: 2; radius: 1
                                            color: U.withAlpha(Theme.primary, 0.22)
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Layout.bottomMargin: Tokens.space2
                                        RowLayout {
                                            spacing: Tokens.space2
                                            C.IconGlyph { name: modelData.icon; size: 15; glyphColor: Theme.primary }
                                            C.AppText {
                                                text: modelData.title
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontLabel
                                                color: Theme.text_strong
                                            }
                                        }
                                        C.AppText {
                                            Layout.fillWidth: true
                                            text: modelData.text
                                            font.pixelSize: Tokens.fontCaption + 1
                                            color: Theme.on_surface_var
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }
                        InspectorCard {
                            visible: !Cutter.hasInfo
                            label: I18n.tr("Keyboard shortcuts")
                            glyph: "command"
                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                Repeater {
                                    model: [ { k: "Space", t: I18n.tr("Play") }, { k: "I", t: I18n.tr("Start") },
                                             { k: "O", t: I18n.tr("End") }, { k: "J / L", t: "±10s" },
                                             { k: "P", t: I18n.tr("Preview clip") }, { k: "Z", t: I18n.tr("Zoom") } ]
                                    Rectangle {
                                        radius: Tokens.radiusMd
                                        implicitHeight: 32
                                        implicitWidth: kRow.implicitWidth + Tokens.space2 * 2
                                        color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.03 : 0.025)
                                        border.width: 1
                                        border.color: Theme.border
                                        Row {
                                            id: kRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Keycap { k: modelData.k; anchors.verticalCenter: parent.verticalCenter }
                                            C.AppText {
                                                text: modelData.t
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.on_surface
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── source info ──
                        InspectorCard {
                            visible: Cutter.hasInfo
                            label: Cutter.mode === 0 ? I18n.tr("YouTube link") : I18n.tr("Local file")
                            glyph: Cutter.mode === 0 ? "youtube" : "movie"
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                Item {
                                    Layout.preferredWidth: 112
                                    Layout.preferredHeight: 63
                                    Layout.alignment: Qt.AlignTop
                                    visible: page._hasThumb
                                    Rectangle {
                                        id: thumbMask
                                        anchors.fill: parent
                                        radius: Tokens.radiusSm
                                        visible: false
                                        layer.enabled: true
                                    }
                                    Image {
                                        id: thumbImg
                                        anchors.fill: parent
                                        visible: false
                                        source: page._thumbSrc
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                    }
                                    MultiEffect {
                                        anchors.fill: parent
                                        source: thumbImg
                                        maskEnabled: true
                                        maskSource: thumbMask
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 4
                                        radius: 4
                                        color: Qt.rgba(0, 0, 0, 0.75)
                                        implicitWidth: durLbl.implicitWidth + 8
                                        implicitHeight: 18
                                        C.AppText {
                                            id: durLbl
                                            anchors.centerIn: parent
                                            text: Cutter.durationText
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontMicro
                                            color: "#ffffff"
                                        }
                                    }
                                }
                                C.IconTile {
                                    visible: !page._hasThumb
                                    iconName: "movie"
                                    size: 52
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 52
                                    Layout.alignment: Qt.AlignTop
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    text: Cutter.title
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontBody
                                    color: Theme.text_strong
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 3
                                }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space1 + 2
                                InfoChip { glyph: "hourglass_empty"; text: page._hasThumb ? "" : Cutter.durationText; mono: true }
                                InfoChip {
                                    glyph: "hd"
                                    text: Cutter.mode === 1 ? I18n.tr("Original quality (stream copy)") : ""
                                }
                                InfoChip {
                                    glyph: "visibility"
                                    text: Cutter.previewLabel !== ""
                                          ? I18n.tr("Preview quality {q}").replace("{q}", Cutter.previewLabel) : ""
                                }
                                InfoChip {
                                    glyph: Cutter.previewHasAudio ? "volume_up" : "volume_off"
                                    tint: Cutter.previewHasAudio ? Theme.secondary_container : Theme.on_surface_var
                                    text: Cutter.mode !== 0 || Cutter.previewUrl === "" ? ""
                                          : Cutter.previewHasAudio ? I18n.tr("with sound")
                                          : I18n.tr("Preview without sound")
                                }
                                InfoChip {
                                    glyph: "bolt"
                                    text: Cutter.mode === 0 && Cutter.durationSec >= 3600
                                          ? I18n.tr("Light preview for long video") : ""
                                }
                                InfoChip {
                                    glyph: "warning"
                                    tint: Theme.warn
                                    text: Cutter.previewCodecWarning
                                          ? I18n.tr("AV1 preview — may not play on this PC. Cut still works.") : ""
                                }
                            }
                        }

                        // ── the clip: length meter + quick lengths ──
                        InspectorCard {
                            visible: Cutter.hasInfo
                            label: I18n.tr("Clip length")
                            glyph: "scissors"
                            trailing: [
                                C.AppText {
                                    text: Cutter.durationSec > 0
                                          ? Math.round(page._clipLen / Cutter.durationSec * 100) + "%"
                                          : ""
                                    mono: true
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                            ]

                            // the counter — the number that matters
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space3
                                LayoutMirroring.enabled: false
                                C.AppText {
                                    id: lenCounter
                                    text: page._tc(page._clipLen)
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: 34
                                    color: Theme.primary
                                    Layout.alignment: Qt.AlignVCenter
                                    // a tick of emphasis whenever the length changes
                                    property real _pop: 1
                                    scale: _pop
                                    transformOrigin: Item.Left
                                    onTextChanged: popAnim.restart()
                                    SequentialAnimation {
                                        id: popAnim
                                        NumberAnimation { target: lenCounter; property: "_pop"; to: 1.04; duration: 70; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: lenCounter; property: "_pop"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Column {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2
                                    C.AppText {
                                        anchors.right: parent.right
                                        text: Cutter.startLabel + "  →  " + Cutter.endLabel
                                        mono: true
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.text_strong
                                    }
                                    C.AppText {
                                        anchors.right: parent.right
                                        text: "/ " + Cutter.durationText
                                        mono: true
                                        font.pixelSize: Tokens.fontMicro
                                        color: Theme.on_surface_var
                                    }
                                }
                            }
                            // where the clip sits in the whole video
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 10
                                LayoutMirroring.enabled: false
                                readonly property real _d: Math.max(1, Cutter.durationSec)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 6; radius: 3
                                    color: Theme.surface_high
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.width * Math.min(1, Cutter.startSec / parent._d)
                                    width: Math.max(4, parent.width * Math.min(1, page._clipLen / parent._d))
                                    height: 6; radius: 3
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Theme.primary }
                                        GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.6) }
                                    }
                                    Behavior on x { NumberAnimation { duration: Tokens.durFast } }
                                    Behavior on width { NumberAnimation { duration: Tokens.durFast } }
                                }
                                Rectangle {
                                    x: parent.width * Math.min(1, page._posSec / parent._d) - 1
                                    width: 2; height: parent.height; radius: 1
                                    color: Theme.text_strong
                                }
                            }
                            // quick lengths — the Shorts presets
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                C.AppText {
                                    text: I18n.tr("Quick length from Start")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space1
                                    LayoutMirroring.enabled: false
                                    Repeater {
                                        model: [ { l: "15s", s: 15 }, { l: "30s", s: 30 }, { l: "60s", s: 60 },
                                                 { l: "3m", s: 180 }, { l: I18n.tr("Whole"), s: 0 } ]
                                        AbstractButton {
                                            id: preBtn
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            hoverEnabled: true
                                            enabled: page._armed && (modelData.s === 0 || modelData.s < Cutter.durationSec)
                                            opacity: enabled ? 1 : 0.4
                                            readonly property bool on: modelData.s === 0
                                                ? (Cutter.startSec <= 0 && Cutter.endSec >= Cutter.durationSec)
                                                : Math.round(page._clipLen) === modelData.s
                                            onClicked: page._preset(modelData.s)
                                            scale: pressed ? 0.95 : 1
                                            Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                                            HoverHandler { cursorShape: preBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                            background: Rectangle {
                                                radius: Tokens.radiusSm
                                                color: preBtn.on ? Theme.primary
                                                     : preBtn.hovered ? U.withAlpha(Theme.primary, 0.10)
                                                     : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.04 : 0.03)
                                                border.width: preBtn.on ? 0 : 1
                                                border.color: preBtn.hovered ? U.withAlpha(Theme.primary, 0.45) : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: C.AppText {
                                                text: modelData.l
                                                mono: modelData.s !== 0
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontCaption
                                                color: preBtn.on ? Theme.on_primary
                                                     : preBtn.hovered ? Theme.primary : Theme.on_surface_var
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // (v3.27: the Start / End cards moved under the player)

                        // ── quality ──
                        InspectorCard {
                            visible: Cutter.hasInfo
                            label: I18n.tr("Quality & output")
                            glyph: "hd"

                            // throttled-read warning
                            Rectangle {
                                Layout.fillWidth: true
                                visible: Cutter.thinProbe
                                radius: Tokens.radiusMd
                                color: U.withAlpha(Theme.warn, 0.10)
                                border.width: 1
                                border.color: U.withAlpha(Theme.warn, 0.40)
                                implicitHeight: thinCol.implicitHeight + Tokens.space3 * 2
                                ColumnLayout {
                                    id: thinCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.space3
                                    spacing: Tokens.space2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        C.IconGlyph { name: "warning"; size: 16; fill: true; glyphColor: Theme.warn; Layout.alignment: Qt.AlignTop }
                                        C.AppText {
                                            text: I18n.tr("YouTube only showed 360p for this video — its HD qualities are hidden by a limited read.")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.text_strong
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                    C.AppText {
                                        text: I18n.tr("1) Install the downloader component  2) Set browser cookies in Settings (and close that browser)  3) Press Read video again.")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Tokens.space2
                                        C.PrimaryButton {
                                            variant: "ghost"
                                            iconName: "download"
                                            text: I18n.tr("Install component")
                                            implicitHeight: 34
                                            visible: !Deno.ready
                                            onClicked: Deno.requestInstall()
                                        }
                                        C.PrimaryButton {
                                            variant: "ghost"
                                            iconName: "refresh"
                                            text: I18n.tr("Read again")
                                            implicitHeight: 34
                                            enabled: !Cutter.probing && !Cutter.cutting
                                            onClicked: Cutter.fetchInfo()
                                        }
                                    }
                                }
                            }

                            // local file: original-quality banner
                            Rectangle {
                                Layout.fillWidth: true
                                visible: Cutter.mode === 1
                                radius: Tokens.radiusLg
                                implicitHeight: 60
                                color: U.withAlpha(Theme.primary, 0.07)
                                border.width: 1
                                border.color: U.withAlpha(Theme.primary, 0.30)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.space3
                                    spacing: Tokens.space3
                                    C.IconTile {
                                        iconName: "diamond"
                                        solid: true
                                        size: 36
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                    }
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: I18n.tr("Original quality (stream copy)")
                                        weight: Tokens.weightBold
                                        color: Theme.text_strong
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            // quality tiles
                            GridLayout {
                                Layout.fillWidth: true
                                visible: Cutter.mode === 0
                                columns: page._wide ? 3 : Math.max(3, Math.min(6, Math.floor(content.width / 170)))
                                columnSpacing: Tokens.space2
                                rowSpacing: Tokens.space2
                                Repeater {
                                    model: Cutter.qualities
                                    AbstractButton {
                                        id: qTile
                                        readonly property string tier: page._tier(modelData.label)
                                        readonly property bool hi: tier === "4K" || tier === "2K"
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        implicitHeight: 64
                                        text: modelData.label
                                        checkable: true
                                        checked: Cutter.qualityIndex === index && !Cutter.audioOnly
                                        enabled: !Cutter.cutting
                                        hoverEnabled: true
                                        opacity: enabled ? 1 : 0.5
                                        onClicked: {
                                            // Guard against stale delegates during the
                                            // model rebuild after a fresh probe.
                                            if (index >= 0 && index < Cutter.qualities.length)
                                                Cutter.qualityIndex = index
                                            Cutter.setAudioOnly(false)
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        scale: pressed ? 0.97 : 1
                                        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                                        background: Rectangle {
                                            radius: Tokens.radiusMd
                                            color: qTile.checked ? U.withAlpha(Theme.primary, 0.13)
                                                   : qTile.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                   : Theme.surface_low
                                            border.width: qTile.checked ? 2 : 1
                                            border.color: qTile.checked ? Theme.primary
                                                        : qTile.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            Rectangle {
                                                visible: qTile.checked
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 5
                                                width: 16; height: 16; radius: 8
                                                color: Theme.primary
                                                C.IconGlyph {
                                                    anchors.centerIn: parent
                                                    name: "check"; size: 11
                                                    glyphColor: Theme.on_primary
                                                }
                                            }
                                        }
                                        contentItem: Item {
                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                RowLayout {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    spacing: 5
                                                    LayoutMirroring.enabled: false
                                                    C.AppText {
                                                        text: qTile.text
                                                        mono: true
                                                        weight: Tokens.weightExtraBold
                                                        font.pixelSize: Tokens.fontBody
                                                        color: qTile.checked ? Theme.primary : Theme.text_strong
                                                    }
                                                    Rectangle {
                                                        visible: qTile.tier !== ""
                                                        radius: 4
                                                        implicitHeight: 16
                                                        implicitWidth: tierLbl.implicitWidth + 8
                                                        Layout.alignment: Qt.AlignVCenter
                                                        color: qTile.hi ? Theme.primary : U.withAlpha(Theme.on_surface, 0.10)
                                                        C.AppText {
                                                            id: tierLbl
                                                            anchors.centerIn: parent
                                                            text: qTile.tier
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: Tokens.fontMicro
                                                            color: qTile.hi ? Theme.on_primary : Theme.on_surface_var
                                                        }
                                                    }
                                                }
                                                C.AppText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Layout.maximumWidth: qTile.width - 12
                                                    text: modelData.sub
                                                    font.pixelSize: Tokens.fontMicro
                                                    color: Theme.on_surface_var
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── v3.47: Video → its format │ Audio only → its format ──
                            // Video format
                            Flow {
                                Layout.fillWidth: true
                                                                spacing: Tokens.space2
                                opacity: Cutter.audioOnly ? 0.65 : 1
                                C.AppText {
                                    height: 30
                                    verticalAlignment: Text.AlignVCenter
                                    text: I18n.tr("Video format")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                                Repeater {
                                    model: ["mp4", "mkv", "webm"]
                                    AbstractButton {
                                        id: vchip
                                        readonly property bool on: !Cutter.audioOnly && Cutter.videoFormat === modelData
                                        enabled: !Cutter.cutting
                                        implicitHeight: 30
                                        implicitWidth: vchipLbl.implicitWidth + 22
                                        opacity: enabled ? 1 : 0.5
                                        onClicked: Cutter.setVideoFormat(modelData)
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        background: Rectangle {
                                            radius: 15
                                            color: vchip.on ? U.withAlpha(Theme.primary, 0.14)
                                                 : vchip.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                 : Theme.surface_low
                                            border.width: vchip.on ? 2 : 1
                                            border.color: vchip.on ? Theme.primary
                                                        : vchip.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                        }
                                        contentItem: C.AppText {
                                            id: vchipLbl
                                            text: modelData.toUpperCase()
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: vchip.on ? Theme.primary : Theme.on_surface_var
                                        }
                                    }
                                }
                            }

                            C.AppText {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space2
                                text: I18n.tr("Audio")
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                            }
                            AbstractButton {
                                id: aOnly
                                Layout.fillWidth: true
                                implicitHeight: 52
                                checkable: true
                                checked: Cutter.audioOnly
                                enabled: !Cutter.cutting
                                opacity: enabled ? 1 : 0.5
                                onClicked: Cutter.setAudioOnly(true)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    radius: Tokens.radiusMd
                                    color: aOnly.checked ? U.withAlpha(Theme.primary, 0.13)
                                           : aOnly.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                           : Theme.surface_low
                                    border.width: aOnly.checked ? 2 : 1
                                    border.color: aOnly.checked ? Theme.primary
                                                : aOnly.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                }
                                contentItem: RowLayout {
                                    spacing: Tokens.space3
                                    C.IconGlyph {
                                        Layout.leftMargin: Tokens.space3
                                        name: "music"; size: 18
                                        glyphColor: aOnly.checked ? Theme.primary : Theme.on_surface_var
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        C.AppText {
                                            text: I18n.tr("Audio only")
                                            weight: Tokens.weightBold
                                            color: aOnly.checked ? Theme.primary : Theme.text_strong
                                        }
                                        C.AppText {
                                            text: I18n.tr("No picture, just the sound")
                                            font.pixelSize: Tokens.fontMicro
                                            color: Theme.on_surface_var
                                        }
                                    }
                                }
                            }
                            // Audio format
                            Flow {
                                Layout.fillWidth: true
                                                                spacing: Tokens.space2
                                opacity: !Cutter.audioOnly ? 0.65 : 1
                                C.AppText {
                                    height: 30
                                    verticalAlignment: Text.AlignVCenter
                                    text: I18n.tr("Audio format")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                                Repeater {
                                    model: ["mp3", "m4a", "opus", "wav", "flac"]
                                    AbstractButton {
                                        id: achip
                                        readonly property bool on: Cutter.audioOnly && Cutter.audioFormat === modelData
                                        enabled: !Cutter.cutting
                                        implicitHeight: 30
                                        implicitWidth: achipLbl.implicitWidth + 22
                                        opacity: enabled ? 1 : 0.5
                                        onClicked: Cutter.setAudioFormat(modelData)
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        background: Rectangle {
                                            radius: 15
                                            color: achip.on ? U.withAlpha(Theme.primary, 0.14)
                                                 : achip.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                                 : Theme.surface_low
                                            border.width: achip.on ? 2 : 1
                                            border.color: achip.on ? Theme.primary
                                                        : achip.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                        }
                                        contentItem: C.AppText {
                                            id: achipLbl
                                            text: modelData.toUpperCase()
                                            mono: true
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: achip.on ? Theme.primary : Theme.on_surface_var
                                        }
                                    }
                                }
                            }
                        }

                        // ── audio track (v1.2): dubbed videos only ──
                        InspectorCard {
                            id: audioCard
                            visible: Cutter.hasInfo && Cutter.mode === 0
                                     && (Cutter.audioTracks || []).length > 1
                            label: I18n.tr("Audio track")
                            glyph: "translate"
                            trailing: [
                                InfoChip {
                                    glyph: "volume_up"
                                    tint: Theme.primary
                                    text: I18n.tr("{n} languages").replace("{n}", (Cutter.audioTracks || []).length)
                                }
                            ]

                            C.AppText {
                                Layout.fillWidth: true
                                text: I18n.tr("This video is dubbed. Pick the voice your clip should carry — the preview switches to it right away.")
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                wrapMode: Text.Wrap
                            }
                            C.AudioTrackPicker {
                                Layout.fillWidth: true
                                showHeader: false
                                columns: audioCard.width >= 760 ? 3 : audioCard.width >= 500 ? 2 : 1
                                maxCollapsed: columns === 1 ? 4 : 6
                                tracks: Cutter.audioTracks || []
                                current: Cutter.audioTrack
                                locked: Cutter.cutting
                                onPicked: (key) => Cutter.setAudioTrack(key)
                            }
                        }
                    }
                }

                // ── edit bay: the timeline ──
                C.GlassPanel {
                    id: bay
                    Layout.fillWidth: true
                    visible: Cutter.hasInfo
                    radius_: Tokens.radiusXl
                    implicitHeight: bayCol.implicitHeight + Tokens.space4 * 2

                    ColumnLayout {
                        id: bayCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space4
                        anchors.leftMargin: Tokens.space5
                        anchors.rightMargin: Tokens.space5
                        spacing: Tokens.space3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            BayLabel { text: I18n.tr("Timeline"); glyph: "movie"; Layout.alignment: Qt.AlignVCenter }
                            C.AppText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                visible: content.width > 820
                                text: I18n.tr("Click to scrub · drag the brackets to trim · drag the grip to slide the clip")
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                                elide: Text.ElideRight
                            }
                            Item { Layout.fillWidth: content.width <= 820 }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "play_circle"
                                text: I18n.tr("Preview clip")
                                implicitHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                enabled: page._armed && Cutter.endSec > Cutter.startSec && Cutter.previewUrl !== ""
                                onClicked: page._previewClip()
                            }
                            // zoom: whole video ↔ fit the clip
                            Rectangle {
                                id: zoomSeg
                                readonly property int segW: 92
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: segW * 2 + 6
                                implicitHeight: 36
                                radius: Tokens.radiusMd
                                color: Theme.input_bg
                                border.width: 1
                                border.color: Theme.border
                                LayoutMirroring.enabled: false
                                Rectangle {
                                    x: 3 + (page._zoom ? zoomSeg.segW : 0)
                                    y: 3
                                    width: zoomSeg.segW
                                    height: parent.height - 6
                                    radius: Tokens.radiusSm
                                    color: U.withAlpha(Theme.primary, Theme.isDark ? 0.22 : 0.15)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.primary, 0.5)
                                    Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                }
                                Row {
                                    x: 3; y: 3
                                    Repeater {
                                        model: [ { l: I18n.tr("Whole"), z: false, g: "fullscreen" },
                                                 { l: I18n.tr("Clip"),  z: true,  g: "fullscreen_exit" } ]
                                        AbstractButton {
                                            id: zBtn
                                            width: zoomSeg.segW
                                            height: zoomSeg.height - 6
                                            readonly property bool on: page._zoom === modelData.z
                                            hoverEnabled: true
                                            onClicked: page._zoom = modelData.z
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            background: Item { }
                                            contentItem: Item {
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: 5
                                                    C.IconGlyph {
                                                        name: modelData.g; size: 14
                                                        glyphColor: zBtn.on ? Theme.primary : Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    C.AppText {
                                                        text: modelData.l
                                                        weight: zBtn.on ? Tokens.weightBold : Tokens.weightMedium
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: zBtn.on ? Theme.primary : Theme.on_surface_var
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                C.AppTooltip { visible: zoomHover.hovered; text: I18n.tr("Zoom the timeline to the clip") + "  (Z)" }
                                HoverHandler { id: zoomHover }
                            }
                        }

                        TrimTimeline {
                            Layout.fillWidth: true
                            LayoutMirroring.enabled: false
                        }
                    }
                }

                // ── clip reel (history) ──
                C.GlassPanel {
                    id: clipsPanel
                    Layout.fillWidth: true
                    visible: Cutter.clipsCount > 0
                    radius_: Tokens.radiusXl
                    implicitHeight: clipsCol.implicitHeight + Tokens.space5 * 2
                    ColumnLayout {
                        id: clipsCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            BayLabel { text: I18n.tr("Clips"); glyph: "history"; Layout.alignment: Qt.AlignVCenter }
                            Rectangle {
                                radius: Tokens.radiusPill
                                color: U.withAlpha(Theme.primary, 0.14)
                                implicitWidth: Math.max(24, clipCount.implicitWidth + Tokens.space2 * 2)
                                implicitHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                C.AppText {
                                    id: clipCount
                                    anchors.centerIn: parent
                                    text: Cutter.clipsCount
                                    mono: true
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontMicro
                                    color: Theme.primary
                                }
                            }
                            Item { Layout.fillWidth: true }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "delete_sweep"
                                text: I18n.tr("Clear all")
                                implicitHeight: 36
                                onClicked: confirmClearClips.open()
                            }
                        }

                        GridLayout {
                            id: reel
                            Layout.fillWidth: true
                            columns: Math.max(1, Math.floor((content.width - Tokens.space5 * 2 + Tokens.space3) / 380))
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3
                            Repeater {
                                model: page.pagedClips
                                Rectangle {
                                    id: clipCard
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    // v3.24 — grows with its content. It was a
                                    // fixed 92 px: on a narrow column the chips
                                    // wrap to a second / third line, the row
                                    // grew past the card and the cover and the
                                    // "file missing" chip spilled out of it.
                                    // fillHeight keeps a grid row's cards level.
                                    Layout.fillHeight: true
                                    implicitHeight: Math.max(92, clipRow.implicitHeight + Tokens.space3 * 2)
                                    radius: Tokens.radiusLg
                                    color: clipHover.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
                                    border.width: 1
                                    border.color: clipHover.hovered ? U.withAlpha(Theme.primary, 0.35) : Theme.border
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                    HoverHandler { id: clipHover }
                                    transform: Translate {
                                        id: clipCardLift
                                        y: clipHover.hovered ? -2 : 0
                                        Behavior on y { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                                    }
                                    // keep the hit box on the resting footprint too (see LiftMask.qml)
                                    containmentMask: C.LiftMask { target: clipCard; dy: clipCardLift.y }

                                    // v3.39.9: drag the clip out of the app to copy it
                                    // anywhere (desktop, a folder, an editor, a chat).
                                    C.FileDragSource {
                                        canDrag: !!clipCard.modelData.exists
                                        paths: [clipCard.modelData.filepath || ""]
                                        preview: clipCover
                                    }

                                    RowLayout {
                                        id: clipRow
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space3
                                        spacing: Tokens.space3
                                        // v3.16-p4: the clip's own frame, cut out of a film strip
                                        C.ClipCover {
                                            id: clipCover
                                            Layout.preferredWidth: 116
                                            Layout.preferredHeight: 66
                                            Layout.minimumWidth: 116
                                            Layout.minimumHeight: 66
                                            Layout.maximumHeight: 66
                                            Layout.alignment: Qt.AlignVCenter
                                            coverUrl: clipCard.modelData.thumbUrl || ""
                                            fallbackId: clipCard.modelData.ytThumbId || ""
                                            exists: clipCard.modelData.exists
                                            isAudio: !!clipCard.modelData.isAudio
                                            durationText: clipCard.modelData.spanText || ""
                                            hovered: clipHover.hovered
                                            onClicked: {
                                                var info = Cutter.clipPlayInfo(clipCard.modelData.id)
                                                if (info && info.fileUrl) clipPlayer.play(info)
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: Tokens.space2
                                            C.AppText {
                                                text: clipCard.modelData.title
                                                weight: Tokens.weightBold
                                                font.pixelSize: Tokens.fontBody
                                                color: clipCard.modelData.exists ? Theme.text_strong : Theme.outline
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: Tokens.space1 + 2
                                                LayoutMirroring.enabled: false
                                                InfoChip { glyph: "crop_square"; mono: true; text: clipCard.modelData.rangeText || "" }
                                                InfoChip { glyph: "hd"; mono: true; text: clipCard.modelData.quality || "" }
                                                InfoChip { glyph: "data"; mono: true; text: clipCard.modelData.sizeText || "" }
                                                InfoChip {
                                                    glyph: "warning"; tint: Theme.warn
                                                    text: clipCard.modelData.exists ? "" : I18n.tr("file missing")
                                                }
                                            }
                                        }
                                        Row {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 0
                                            opacity: clipHover.hovered ? 1 : 0.6
                                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                                            // play right here, in the app's own player
                                            C.IconButton {
                                                implicitWidth: 32; implicitHeight: 32
                                                glyphSize: 16
                                                iconName: "play_arrow"
                                                iconFill: true
                                                accent: Theme.primary
                                                tip: I18n.tr("Play in YouTube Hunter")
                                                enabled: clipCard.modelData.exists
                                                opacity: enabled ? 1 : 0.4
                                                onClicked: {
                                                    var info = Cutter.clipPlayInfo(clipCard.modelData.id)
                                                    if (info && info.fileUrl) clipPlayer.play(info)
                                                }
                                            }
                                            C.IconButton {
                                                implicitWidth: 32; implicitHeight: 32
                                                glyphSize: 15
                                                iconName: "folder_open"
                                                tip: I18n.tr("Open folder")
                                                enabled: clipCard.modelData.exists
                                                opacity: enabled ? 1 : 0.4
                                                onClicked: Cutter.openClipFolder(clipCard.modelData.filepath)
                                            }
                                            C.IconButton {
                                                implicitWidth: 32; implicitHeight: 32
                                                glyphSize: 15
                                                iconName: "delete"
                                                accent: Theme.error
                                                tip: I18n.tr("Remove from history")
                                                onClicked: confirmDeleteClip.ask(clipCard.modelData.id, clipCard.modelData.title)
                                            }
                                            C.IconButton {
                                                implicitWidth: 32; implicitHeight: 32
                                                glyphSize: 15
                                                iconName: "open_in_new"
                                                accent: Theme.primary
                                                active: true
                                                tip: I18n.tr("Open file")
                                                enabled: clipCard.modelData.exists
                                                opacity: enabled ? 1 : 0.4
                                                onClicked: Cutter.openClipFile(clipCard.modelData.filepath)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── pager + total ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            visible: page.clipsPageCount > 1
                            LayoutMirroring.enabled: false

                            C.AppText {
                                text: I18n.tr("{shown} of {total} clips")
                                        .replace("{shown}", page.pagedClips.length)
                                        .replace("{total}", Cutter.clipsCount)
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.on_surface_var
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Item { Layout.fillWidth: true }
                            C.Pager {
                                pageIndex: page.clipsPage
                                pageCount: page.clipsPageCount
                                Layout.alignment: Qt.AlignVCenter
                                onRequested: (i) => {
                                    page.clipsPage = i
                                    scroller.scrollToItem(clipsPanel)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── floating export dock: ready → cutting → done ─────────────────────────
    C.GlassPanel {
        id: dock
        visible: Cutter.hasInfo
        elevation: 1.8
        radius_: Tokens.radiusXl
        width: Tokens.contentWidth(page.width)
        height: page._dockH - Tokens.space2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.space4
        clip: true
        border.color: Cutter.cutting ? U.withAlpha(Theme.error, 0.45)
                    : _done ? U.withAlpha(Theme.secondary_container, 0.55)
                    : Cutter.canCut ? U.withAlpha(Theme.primary, 0.40) : Theme.border

        readonly property bool _done: Cutter.hasResult && !Cutter.cutting

        // v3.39.9: once the clip is ready, the whole dock is a drag handle —
        // pull it onto the desktop / a folder / an editor to copy the file.
        C.FileDragSource {
            canDrag: dock._done && Cutter.resultPath !== ""
            paths: [Cutter.resultPath]
        }

        // a wash from the leading edge, coloured by the state
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: dock.radius - 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: U.withAlpha(Cutter.cutting ? Theme.error : dock._done ? Theme.secondary_container : Theme.primary,
                                       Theme.isDark ? 0.14 : 0.08)
                }
                GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }

        // cut progress along the top edge — kept between the rounded corners
        // and pill-ended, so it never pokes out of the dock as a square slab
        Rectangle {
            visible: Cutter.cutting
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: dock.radius_
            anchors.topMargin: 1
            height: 3
            radius: height / 2
            width: (parent.width - dock.radius_ * 2) * Math.max(0.02, Cutter.cutPct / 100)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: U.mix(Theme.primary, Qt.rgba(1, 1, 1, 1), 0.25) }
            }
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }

        // ── ready / cutting ──
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space5
            anchors.rightMargin: Tokens.space3
            spacing: Tokens.space4
            visible: !dock._done
            LayoutMirroring.enabled: false

            // state light + clip length
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.space3
                Rectangle {
                    id: dockTally
                    width: 12; height: 12; radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: Cutter.cutting ? Theme.error : Cutter.canCut ? Theme.primary : Theme.outline
                    Rectangle {
                        anchors.centerIn: parent
                        width: 24; height: 24; radius: 12
                        color: "transparent"
                        border.width: 2
                        border.color: U.withAlpha(parent.color, 0.35)
                        visible: Cutter.cutting
                        SequentialAnimation on scale {
                            running: Cutter.cutting && page.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.6; to: 1.2; duration: 900; easing.type: Easing.OutQuad }
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    C.AppText {
                        text: Cutter.cutting ? I18n.tr("Cutting…") : I18n.tr("Clip length")
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontMicro
                        color: Cutter.cutting ? Theme.error : Theme.on_surface_var
                    }
                    C.AppText {
                        text: Cutter.cutting && Cutter.cutPct > 0 ? Cutter.cutPct + "%" : page._fmt(page._clipLen * 1000)
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: Tokens.fontTitle + 2
                        color: Cutter.cutting ? Theme.text_strong : Theme.primary
                    }
                }
            }

            Rectangle {
                visible: dock.width > 820
                width: 1; height: 40
                color: Theme.border
                Layout.alignment: Qt.AlignVCenter
            }

            // mini range map
            ColumnLayout {
                spacing: 6
                Layout.alignment: Qt.AlignVCenter
                visible: dock.width > 820
                Row {
                    spacing: Tokens.space2
                    C.AppText {
                        text: Cutter.startLabel
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.text_strong
                    }
                    C.IconGlyph {
                        name: I18n.rtl ? "arrow_back" : "arrow_forward"; size: 13
                        glyphColor: Theme.outline
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        text: Cutter.endLabel
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.text_strong
                    }
                }
                Rectangle {
                    implicitWidth: 180
                    implicitHeight: 6
                    radius: 3
                    color: Theme.surface_high
                    Rectangle {
                        readonly property real _d: Math.max(1, Cutter.durationSec)
                        x: parent.width * Math.max(0, Math.min(1, Cutter.startSec / _d))
                        width: Math.max(3, parent.width * Math.max(0, Math.min(1, page._clipLen / _d)))
                        height: parent.height
                        radius: 3
                        color: Theme.primary
                    }
                }
            }

            // the quality this clip will be saved at
            Rectangle {
                visible: dock.width > 960 && page._qualityLabel() !== ""
                Layout.alignment: Qt.AlignVCenter
                radius: Tokens.radiusPill
                implicitHeight: 30
                implicitWidth: qRow.implicitWidth + Tokens.space3 * 2
                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.04)
                border.width: 1
                border.color: Theme.border
                Row {
                    id: qRow
                    anchors.centerIn: parent
                    spacing: 6
                    C.IconGlyph { name: "hd"; size: 14; glyphColor: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    C.AppText {
                        text: page._qualityLabel()
                        mono: Cutter.mode === 0
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.text_strong
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item { Layout.fillWidth: true }

            C.AppText {
                visible: Cutter.cutDetail !== ""
                text: Cutter.cutDetail
                mono: true
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                color: Theme.on_surface_var
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
                Layout.maximumWidth: 320
            }
            C.PrimaryButton {
                variant: "ghost"
                text: I18n.tr("Cancel")
                visible: Cutter.cutting
                implicitHeight: 52
                Layout.alignment: Qt.AlignVCenter
                onClicked: Cutter.cancelCut()
            }
            Keycap {
                visible: !Cutter.cutting && Cutter.canCut && dock.width > 1080
                k: "Ctrl+Enter"
                Layout.alignment: Qt.AlignVCenter
            }
            C.PrimaryButton {
                id: cutBtn
                iconName: "scissors"
                text: Cutter.cutting
                      ? (Cutter.cutPct > 0 ? I18n.tr("Cutting…") + "  " + Cutter.cutPct + "%" : I18n.tr("Cutting…"))
                      : I18n.tr("Cut & Download")
                enabled: Cutter.canCut
                implicitHeight: 52
                implicitWidth: Math.max(220, contentItem.implicitWidth + Tokens.space6 * 2)
                Layout.alignment: Qt.AlignVCenter
                progress: Cutter.cutting ? (Cutter.cutPct > 0 ? Cutter.cutPct / 100 : -1) : -1
                indeterminate: Cutter.cutting && Cutter.cutPct <= 0
                onClicked: page._startCut()
            }
        }

        // ── done ──
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space4
            anchors.rightMargin: Tokens.space3
            spacing: Tokens.space3
            visible: dock._done
            opacity: dock._done ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

            C.IconTile {
                iconName: "check_circle"
                tint: Theme.secondary_container
                solid: true
                size: 46
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                C.AppText {
                    text: I18n.tr("Your clip is ready")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontLabel
                    color: Theme.text_strong
                }
                C.AppText {
                    text: Cutter.resultName
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
            C.PrimaryButton {
                variant: "ghost"
                iconName: "folder_open"
                text: I18n.tr("Open folder")
                visible: dock.width > 760
                Layout.alignment: Qt.AlignVCenter
                onClicked: Cutter.openResultFolder()
            }
            C.PrimaryButton {
                variant: "ghost"
                iconName: "scissors"
                text: I18n.tr("Cut again")
                visible: dock.width > 900
                enabled: Cutter.canCut
                Layout.alignment: Qt.AlignVCenter
                onClicked: page._startCut()
            }
            C.PrimaryButton {
                variant: "ghost"
                iconName: "refresh"
                text: I18n.tr("New clip")
                Layout.alignment: Qt.AlignVCenter
                onClicked: Cutter.newClip()
            }
            C.PrimaryButton {
                iconName: "open_in_new"
                text: I18n.tr("Open file")
                implicitHeight: 48
                Layout.alignment: Qt.AlignVCenter
                onClicked: Cutter.openResult()
            }
        }
    }

    // Drop a video file anywhere on the page — switches to Local file first.
    DropArea {
        id: dropZone
        anchors.fill: parent
        // FileDrag.active: ignore a clip dragged out of THIS page (v3.39.9),
        // otherwise letting go over the window would load it as the source.
        enabled: !Cutter.cutting && !Cutter.probing && !FileDrag.active
        onDropped: (drop) => {
            if (!drop.hasUrls || drop.urls.length === 0) return
            if (Cutter.mode !== 1) Cutter.mode = 1
            Cutter.setFile(drop.urls[0].toString())
            Cutter.fetchInfo()
        }
    }
    Rectangle {
        anchors.fill: parent
        z: 700
        visible: opacity > 0.01
        opacity: dropZone.containsDrag ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        color: U.withAlpha(Theme.background, 0.84)
        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.space6
            radius: Tokens.radiusXl
            color: U.withAlpha(Theme.primary, 0.08)
            border.width: 2
            border.color: Theme.primary
            // viewfinder corners, big
            Corner { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Tokens.space5; arm: 40; tint: Theme.primary }
            Corner { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Tokens.space5; arm: 40; tint: Theme.primary; flipX: true }
            Corner { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Tokens.space5; arm: 40; tint: Theme.primary; flipY: true }
            Corner { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Tokens.space5; arm: 40; tint: Theme.primary; flipX: true; flipY: true }
            Column {
                anchors.centerIn: parent
                spacing: Tokens.space4
                C.IconTile {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconName: "movie"
                    solid: true
                    breathe: true
                    size: 76
                }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Drop the video here to load it")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontTitle
                    color: Theme.text_strong
                }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "MP4 · MKV · WEBM · MOV · AVI · M4V"
                    mono: true
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: I18n.tr("Choose a video file")
        fileMode: FileDialog.OpenFile
        nameFilters: [I18n.tr("Video files") + " (*.mp4 *.mkv *.webm *.mov *.avi *.m4v)", I18n.tr("All files") + " (*)"]
        onAccepted: {
            Cutter.setFile(selectedFile.toString())
            Cutter.fetchInfo()
        }
    }

    C.Toast { id: toast; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - (Cutter.hasInfo ? 150 : 80) }

    // the same in-app player Downloads uses, for finished clips
    // ── v3.16-p4: ask before a clip leaves the history ─────────────────────
    // One card for both questions (one clip / every clip): same look as the
    // History page's delete confirmations. Removing only drops the history
    // row — the clip file on disk stays where it is, and the dialog says so.
    component ClipConfirm: Dialog {
        id: cc
        property string glyph: "delete"
        property string heading: ""
        property string body: ""
        property string confirmText: I18n.tr("Remove")
        property string confirmIcon: "delete"
        signal confirmed()

        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(440, (parent ? parent.width : 520) - 80)
        padding: 0

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast }
        }
        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: ccHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: ccHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.30)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: cc.glyph; fill: true; size: 20
                        glyphColor: Theme.error
                    }
                }
                C.AppText {
                    text: cc.heading
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }
        contentItem: C.AppText {
            text: cc.body
            color: Theme.on_surface
            wrapMode: Text.WordWrap
            padding: Tokens.space5
            topPadding: 0
        }
        footer: Item {
            implicitHeight: 50 + Tokens.space5 * 2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.topMargin: Tokens.space3
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    text: I18n.tr("Cancel")
                    onClicked: cc.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: cc.confirmIcon
                    text: cc.confirmText
                    onClicked: { cc.close(); cc.confirmed() }
                }
            }
        }
    }

    ClipConfirm {
        id: confirmDeleteClip
        property int pendingId: 0
        property string pendingName: ""
        function ask(id, name) { pendingId = id; pendingName = name || ""; open() }
        glyph: "delete"
        heading: I18n.tr("Remove this clip?")
        body: (confirmDeleteClip.pendingName !== ""
               ? I18n.tr("“{n}” will be removed from your clips history.").replace("{n}", confirmDeleteClip.pendingName)
               : I18n.tr("This clip will be removed from your clips history."))
              + " " + I18n.tr("The video file itself stays on your disk.")
        confirmText: I18n.tr("Remove")
        confirmIcon: "delete"
        onConfirmed: Cutter.deleteClip(confirmDeleteClip.pendingId)
    }

    ClipConfirm {
        id: confirmClearClips
        glyph: "warning"
        heading: I18n.tr("Clear every clip?")
        body: I18n.tr("All {n} clips will be removed from your clips history.").replace("{n}", Cutter.clipsCount)
              + " " + I18n.tr("The video files themselves stay on your disk.")
        confirmText: I18n.tr("Clear all")
        confirmIcon: "delete_sweep"
        onConfirmed: Cutter.clearClips()
    }

    C.VideoPlayer { id: clipPlayer }
}
