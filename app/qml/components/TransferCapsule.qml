import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// v1.0.2 "Transfer capsule" — what is downloading RIGHT NOW, inside the app.
//
// The desktop live cards (LiveActivityCard) only exist while the user is away
// from the app. In-app, every running download / cut is summarised by this
// capsule in the title bar, just left of Help · Bell · Theme:
//
//      ╭──────────────────────────────────────────╮
//      │ (◔)  10%  ┊ (◕)  50%  ┊ (◑)  72%    +2  │   ← one orb per job
//      ╰──────────────────────────────────────────╯
//        ▲ thumbnail inside its own progress ring
//
//   * one job  → orb · 42% · 8.2 MB/s     (the detail says what is happening)
//   * 2–3 jobs → orb · % for each, hairline between them
//   * 4+ jobs  → the first three, then "+N"
//
// Why the title bar: it is chrome, not content, so the capsule never covers a
// card, a composer or a pager button on any page, and it sits in the same
// place on every page (things that move are things people lose).
//
// Visual hierarchy, loudest first:
//   1. the ring (colour + motion: which job, how far)   — tone per state
//   2. the percentage (bold tabular mono, never jitters)
//   3. the detail (muted: speed, "Merging…", "Paused")
// Signature: the capsule is itself a liquid gauge — its glass fills, very
// faintly, to the AVERAGE progress of everything running, so a glance at the
// shape alone says "about half way".
//
// States per job: running (brand red) · indeterminate (spinning arc: preparing,
// merging) · paused (amber, ⏸ over the thumb) · success (green ✓, then the orb
// folds away) · error (red ✕, stays a little longer) · stopped (grey, quick).
// A job joining sends one soft ping out of the capsule; nothing else blinks.
//
// Click → TransferPanel (owned by TitleBar) with the full detail and ⏸ / ▶ / ■.
// Data: DesktopNotify.activity (desktop_notifier.py, "_dock_rebuild").
AbstractButton {
    id: root

    // TitleBar tells the capsule whether its panel is open (pressed look)
    property bool panelOpen: false
    signal toggleRequested()

    // the shared model — TransferPanel reads the same one
    readonly property alias model: jobs
    readonly property int maxOrbs: 3
    readonly property int count: jobs.count
    property int liveCount: 0
    property real avgFrac: 0
    Behavior on avgFrac { NumberAnimation { duration: 620; easing.type: Easing.OutCubic } }

    // the capsule's own light: red while anything runs, amber when everything
    // left is paused, green / grey for the final beat
    property color tone: Theme.primary
    Behavior on tone { enabled: !Tokens.themeSwapping; ColorAnimation { duration: 420; easing.type: Easing.OutCubic } }

    // ── model sync (keyed, so delegates survive and their rings glide) ──
    ListModel { id: jobs }

    function _indexOf(key) {
        for (let i = 0; i < jobs.count; i++)
            if (jobs.get(i).key === key) return i
        return -1
    }

    function _sync() {
        const rows = DesktopNotify.activity || []
        const keys = rows.map(r => r.key)
        for (let i = jobs.count - 1; i >= 0; i--)
            if (keys.indexOf(jobs.get(i).key) < 0) jobs.remove(i)
        for (let j = 0; j < rows.length; j++) {
            const at = _indexOf(rows[j].key)
            if (at < 0) {
                jobs.insert(Math.min(j, jobs.count), rows[j])
            } else {
                if (at !== j) jobs.move(at, j, 1)
                jobs.set(j, rows[j])
            }
        }
        // summary for the gauge, the tone and the tooltip
        let live = 0, paused = 0, sum = 0, ok = 0
        for (const r of rows) {
            if (r.outcome) { if (r.outcome === "success") ok++; continue }
            live++
            if (r.paused) paused++
            sum += (r.pct || 0) / 100
        }
        if (live > 0) leaving = false
        const grew = live > liveCount
        liveCount = live
        avgFrac = live > 0 ? sum / live : (ok > 0 ? 1 : avgFrac)
        tone = live > 0 ? (paused === live ? Theme.warn : Theme.primary)
             : ok > 0 ? Theme.secondary_container
             : rows.some(r => r.outcome === "error") ? Theme.error
             : Theme.outline
        if (grew && shown) ping.restart()
    }

    Connections {
        target: DesktopNotify
        function onActivityChanged() { root._sync() }
    }
    Component.onCompleted: _sync()

    // ── presence ──
    // `leaving` is raised by the LAST orb's exit: the whole capsule folds
    // instead of shrinking to an empty pill first.
    property bool leaving: false
    readonly property bool shown: jobs.count > 0 && !leaving
    onCountChanged: if (count === 0) leaving = false
    property real reveal: shown ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }

    implicitHeight: 30
    height: 30
    width: Math.round((strip.implicitWidth + 2 * padX) * reveal)
    visible: reveal > 0.01
    opacity: reveal
    scale: 0.92 + 0.08 * reveal
    readonly property int padX: 5

    padding: 0
    hoverEnabled: true
    onClicked: root.toggleRequested()
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    background: Item { }

    contentItem: Item {
        // ── one soft ping when a job joins ──
        Rectangle {
            id: pingRing
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: height / 2
            color: "transparent"
            border.width: 1.5
            border.color: root.tone
            opacity: 0
            antialiasing: true
        }
        ParallelAnimation {
            id: ping
            NumberAnimation { target: pingRing; property: "scale"; from: 1; to: 1.22; duration: 760; easing.type: Easing.OutCubic }
            NumberAnimation { target: pingRing; property: "opacity"; from: 0.55; to: 0; duration: 760; easing.type: Easing.OutCubic }
        }

        // ── the glass ──
        Rectangle {
            id: glass
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            clip: true
            color: root.pressed || root.panelOpen
                   ? U.hoverTint(Theme.header_bg, Theme.isDark, 0.10)
                   : hover.hovered ? U.hoverTint(Theme.header_bg, Theme.isDark, 0.06)
                   : U.hoverTint(Theme.header_bg, Theme.isDark, 0.035)
            border.width: 1
            border.color: U.mix(Theme.border_med, root.tone,
                                (hover.hovered || root.panelOpen) ? 0.55 : 0.30)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

            // liquid gauge: the average progress of everything running
            Item {
                anchors.fill: parent
                anchors.margins: 1
                LayoutMirroring.enabled: false
                Rectangle {
                    readonly property real w: parent.width * Math.max(0, Math.min(1, root.avgFrac))
                    x: I18n.rtl ? parent.width - w : 0
                    width: w
                    height: parent.height
                    radius: parent.height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(root.tone, I18n.rtl ? (Theme.isDark ? 0.16 : 0.12) : (Theme.isDark ? 0.05 : 0.03)) }
                        GradientStop { position: 1.0; color: U.withAlpha(root.tone, I18n.rtl ? (Theme.isDark ? 0.05 : 0.03) : (Theme.isDark ? 0.16 : 0.12)) }
                    }
                }
            }

            // ambient sheen, felt more than seen: one slow pass every few
            // seconds while something is actually moving. Masked to the
            // capsule's real pill shape (a square clip lets it poke out at
            // the rounded ends), and the mask layer only exists while it runs.
            RoundClip {
                anchors.fill: parent
                radius: glass.radius
                active: sheenRun.running
                LayoutMirroring.enabled: false
                Rectangle {
                    id: sheen
                    property real t: 0
                    width: 54
                    height: parent.height * 2
                    y: -parent.height / 2
                    rotation: 20
                    x: -width * 1.5 + (parent.width + width * 3) * t
                    opacity: Theme.isDark ? 0.08 : 0.10
                    readonly property color ink: Theme.isDark ? Qt.rgba(1, 1, 1, 1) : root.tone
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(sheen.ink, 0) }
                        GradientStop { position: 0.5; color: sheen.ink }
                        GradientStop { position: 1.0; color: U.withAlpha(sheen.ink, 0) }
                    }
                    SequentialAnimation on t {
                        id: sheenRun
                        running: root.visible && root.liveCount > 0 && Tokens.appActive
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: 1; duration: 1500; easing.type: Easing.InOutSine }
                        PauseAnimation { duration: 3800 }
                    }
                }
            }

            // ── the orbs ──
            Row {
                id: strip
                x: root.padX
                anchors.verticalCenter: parent.verticalCenter
                layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                spacing: 0

                Repeater {
                    model: jobs
                    // ═════ one job ═════
                    delegate: Item {
                        id: seg
                        required property int index
                        required property string key
                        required property string kind
                        required property string title
                        required property string thumb
                        required property int pct
                        required property bool indeterminate
                        required property bool paused
                        required property string outcome
                        required property string speedText
                        required property string stage

                        readonly property bool solo: jobs.count === 1
                        readonly property bool overflow: index >= root.maxOrbs
                        readonly property bool lastShown: index === Math.min(jobs.count, root.maxOrbs) - 1
                        readonly property bool done: outcome !== ""
                        readonly property color segTone: outcome === "success" ? Theme.secondary_container
                                                       : outcome === "error" ? Theme.error
                                                       : outcome === "stopped" ? Theme.outline
                                                       : paused ? Theme.warn
                                                       : Theme.primary

                        // arrival: unfolds from 0; exit: holds the final beat, then folds
                        property real k: 0
                        Component.onCompleted: {
                            arrive.start()
                            if (done) exitBeat.start()
                        }
                        // a 4th job sliding into view after one of the first
                        // three left: unfold it instead of popping it in
                        onOverflowChanged: if (!overflow && !done) { k = 0; arrive.restart() }
                        NumberAnimation { id: arrive; target: seg; property: "k"; to: 1; duration: 360; easing.type: Easing.OutCubic }
                        onDoneChanged: if (done) exitBeat.restart()
                        SequentialAnimation {
                            id: exitBeat
                            PauseAnimation { duration: seg.outcome === "error" ? 4200 : seg.outcome === "stopped" ? 700 : 1800 }
                            ScriptAction {
                                script: {
                                    // the last orb standing folds the whole capsule instead
                                    let liveLeft = false
                                    for (let i = 0; i < jobs.count; i++)
                                        if (i !== seg.index && jobs.get(i).outcome === "") liveLeft = true
                                    if (!liveLeft && jobs.count <= 1) root.leaving = true
                                }
                            }
                            NumberAnimation { target: seg; property: "k"; to: 0; duration: 300; easing.type: Easing.InOutCubic }
                        }

                        visible: !overflow
                        width: overflow ? 0 : Math.round(row.implicitWidth * k)
                        height: 24
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        clip: true
                        opacity: k

                        Row {
                            id: row
                            height: parent.height
                            layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                            spacing: 0

                            Orb {
                                anchors.verticalCenter: parent.verticalCenter
                                frac: seg.pct / 100
                                spinning: seg.indeterminate && !seg.done
                                paused: seg.paused
                                outcome: seg.outcome
                                thumb: seg.thumb
                                isCut: seg.kind === "cut"
                                tone: seg.segTone
                            }
                            Item { width: 6; height: 1 }
                            // fixed width ("100%"), so the capsule never twitches as digits roll
                            AppText {
                                id: pctLbl
                                anchors.verticalCenter: parent.verticalCenter
                                width: pctMetrics.advanceWidth + 1
                                text: seg.outcome === "error" ? "!" : seg.outcome === "stopped" ? "–"
                                    : seg.indeterminate && !seg.done ? "···"
                                    : seg.pct + "%"
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                color: seg.done ? seg.segTone : seg.paused ? Theme.on_surface_var : Theme.text_strong
                                horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                TextMetrics { id: pctMetrics; font: pctLbl.font; text: "100%" }
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                            }
                            // one job: say what is happening (speed, or the stage).
                            // Fixed slot, so "8.2 MB/s" → "12.4 MB/s" never
                            // nudges the bar; it glides open / shut as the
                            // capsule goes from one job to two and back.
                            Item {
                                id: detailSlot
                                width: seg.solo ? 92 : 0
                                height: parent.height
                                clip: true
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                AppText {
                                    x: I18n.rtl ? parent.width - width : 4
                                    width: 88
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: seg.solo ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    text: seg.outcome === "success" ? I18n.tr("Saved")
                                        : seg.outcome === "error" ? I18n.tr("Failed")
                                        : seg.done ? I18n.tr("Stopped")
                                        : seg.paused ? I18n.tr("Paused")
                                        : (seg.speedText !== "" ? seg.speedText : seg.stage)
                                    font.pixelSize: Tokens.fontCaption
                                    weight: Tokens.weightMedium
                                    color: Theme.on_surface_var
                                    elide: Text.ElideRight
                                    horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                }
                            }
                            Item { width: 8; height: 1 }
                            // hairline between orbs
                            Rectangle {
                                visible: !seg.lastShown
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1
                                height: 12
                                color: Theme.border_med
                            }
                            Item { visible: !seg.lastShown; width: 8; height: 1 }
                        }
                    }
                }

                // +N for everything past the third orb
                Item {
                    visible: jobs.count > root.maxOrbs
                    width: moreLbl.implicitWidth + 14
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.centerIn: parent
                        width: moreLbl.implicitWidth + 10
                        height: 20
                        radius: 10
                        color: U.withAlpha(root.tone, Theme.isDark ? 0.16 : 0.10)
                        AppText {
                            id: moreLbl
                            anchors.centerIn: parent
                            text: "+" + Math.max(0, jobs.count - root.maxOrbs)
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontMicro
                            color: Theme.text_strong
                        }
                    }
                }
            }
        }

        AppTooltip {
            visible: hover.hovered && !root.panelOpen
            delay: 380
            text: root.liveCount === 1 ? I18n.tr("1 transfer in progress · click for details")
                : root.liveCount > 1 ? I18n.tr("{n} transfers in progress · click for details").replace("{n}", root.liveCount)
                : I18n.tr("Transfers")
        }
    }

    // ═════ thumbnail inside its own ring ═════
    component Orb: Item {
        id: orb
        property real frac: 0
        property bool spinning: false
        property bool paused: false
        property string outcome: ""
        property string thumb: ""
        property bool isCut: false
        property color tone: Theme.primary
        Behavior on tone { enabled: !Tokens.themeSwapping; ColorAnimation { duration: 360 } }

        property real shown: 0
        Behavior on shown { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
        onFracChanged: shown = Math.max(0, Math.min(1, frac))
        Component.onCompleted: shown = Math.max(0, Math.min(1, frac))

        width: 24
        height: 24
        readonly property real stroke: 2.25
        readonly property real r: (width - stroke) / 2

        // track
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: U.withAlpha(orb.tone, Theme.isDark ? 0.22 : 0.18)
                strokeWidth: orb.stroke
                fillColor: "transparent"
                PathAngleArc {
                    centerX: orb.width / 2; centerY: orb.height / 2
                    radiusX: orb.r; radiusY: orb.r
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        // progress arc (clockwise from 12 o'clock; counter-clockwise in RTL)
        Shape {
            anchors.fill: parent
            visible: !orb.spinning && orb.shown > 0.004
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: orb.tone
                strokeWidth: orb.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: orb.width / 2; centerY: orb.height / 2
                    radiusX: orb.r; radiusY: orb.r
                    startAngle: -90
                    sweepAngle: (I18n.rtl ? -360 : 360) * (orb.outcome === "success" ? 1 : orb.shown)
                }
            }
        }
        // preparing / merging: a short arc circles instead of a fake number
        Shape {
            id: spin
            anchors.fill: parent
            visible: orb.spinning
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: orb.tone
                strokeWidth: orb.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: orb.width / 2; centerY: orb.height / 2
                    radiusX: orb.r; radiusY: orb.r
                    startAngle: -90; sweepAngle: 96
                }
            }
            RotationAnimation on rotation {
                running: spin.visible && Tokens.appActive
                loops: Animation.Infinite
                from: 0; to: 360
                duration: 950
            }
        }

        // the thumbnail (or the job's glyph)
        RoundThumb {
            anchors.centerIn: parent
            width: 17
            height: 17
            radius: 8.5
            visible: orb.thumb !== ""
            source: orb.thumb !== "" ? "image://thumbs/" + orb.thumb : ""
            glyph: orb.isCut ? "scissors" : "movie"
            opacity: orb.paused || orb.outcome === "stopped" ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        }
        Rectangle {
            anchors.centerIn: parent
            visible: orb.thumb === ""
            width: 17; height: 17; radius: 8.5
            color: U.withAlpha(orb.tone, Theme.isDark ? 0.18 : 0.12)
            IconGlyph {
                anchors.centerIn: parent
                name: orb.isCut ? "scissors" : "download"
                size: 10
                glyphColor: orb.tone
            }
        }

        // state glyph over the thumb: ⏸ paused · ✓ done · ✕ failed
        Rectangle {
            id: stateDot
            readonly property string glyph: orb.outcome === "success" ? "check"
                                          : orb.outcome === "error" ? "close"
                                          : orb.paused ? "pause" : ""
            anchors.centerIn: parent
            width: 17; height: 17; radius: 8.5
            color: orb.outcome !== "" && orb.outcome !== "stopped" ? orb.tone : U.withAlpha(Qt.rgba(0, 0, 0, 1), 0.55)
            scale: glyph !== "" ? 1 : 0.4
            opacity: glyph !== "" ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            IconGlyph {
                anchors.centerIn: parent
                name: stateDot.glyph !== "" ? stateDot.glyph : "check"
                fill: true
                size: 10
                glyphColor: "#ffffff"
            }
        }
    }
}
