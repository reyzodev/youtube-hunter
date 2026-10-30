import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Dialogs
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Niche Finder — v9 "Signal Console".
//
// Search all of YouTube for a keyword, then cut the fetched pool locally by
// channel size / reach / multiplier to surface tiny channels with huge videos.
// Driven by NicheVM: search runs on a worker thread; every cut re-filters the
// cached pool instantly with zero API calls.
//
// Design plan (kept here so later edits can check the render against it):
//   * Subject — an outlier hunter's instrument, not a form. The page reads
//     like a signal console: you aim (query), tune (three cuts), and the
//     scope tells you what you are hunting for.
//   * Console — statement + one command bar on the left; on the right a live
//     monitor: the radar plus a spec sheet of the current cuts, so the radar
//     is no longer decoration — it is the read-out of your filter state.
//   * Tuner — the three signature cuts inside ONE console deck. Each track
//     reads label → statement value → fine calibration rail, so the three
//     cuts scan as a single instrument instead of three form cards. The rail
//     keeps an explicit "Any" stop, so clearing a cut stays a visible choice.
//     The header carries live match telemetry, putting the effect of a cut
//     right where the cut is made.
//   * Recipes — the presets as one row of quiet chips under the deck.
//   * Drawer — advanced options split by BEHAVIOUR in two side-by-side zones
//     ("Instant" vs "On next run"), so it is obvious which knob needs a re-run.
//   * Type — one family (Hanken / IRANYekanX via FontBridge), personality from
//     scale and weight: a 30–48px statement, 28px mono read-outs, 12–15px UI.
//   * Colour — everything from the live Theme (accent follows Settings).
//     The accent is reserved for "this cut is on" and the one primary action.
Item {
    id: page
    // v3.44 perf: Niche.rows converted once per change, not once per card
    readonly property var _nicheRows: Niche.rows || []

    // A download finished elsewhere (or was deleted on the Downloads page)
    // while this page was hidden — re-read which videos have a file on disk
    // so each card's Download/Open button is correct when shown.
    onVisibleChanged: if (visible) Niche.refreshDownloaded()
    // Viral Radar: the first time the page is built, open the radar panel —
    // picks + cost only. It fetches by itself only if the user switched on
    // "Load on open" (v1.1: the quota is theirs to spend).
    Component.onCompleted: { Niche.refreshDownloaded(); Qt.callLater(function () { Niche.autoLoadViral() }) }

    // Advanced drawer expanded/collapsed. Collapsed by default so the tuner
    // reads as three tracks and a row of recipes.
    property bool filtersOpen: false

    // A thumbnail-download the grid requested but with no save folder yet:
    // remember it, ask for the folder once, then run it on the folder pick.
    property string _pendingThumbId: ""
    property string _pendingThumbTitle: ""
    property bool _pendingThumbShort: false

    // Save a card's thumbnail. First time, ask where (then remembered in
    // config, shared with Search Archive); after that it's one click. `isShort`
    // decides the exported frame: 1080×1920 vs 1920×1080.
    function saveThumb(thumbId, title, isShort) {
        if ((thumbId || "") === "") return
        if (Niche.hasThumbFolder) {
            Niche.downloadThumb(thumbId, title, isShort || false)
        } else {
            page._pendingThumbId = thumbId
            page._pendingThumbTitle = title
            page._pendingThumbShort = isShort || false
            thumbFolderDialog.open()
        }
    }

    Connections {
        target: Niche
        function onToast(msg, kind) { toast.show(msg, kind) }
    }

    // debounce re-filtering (mirrors the legacy 260ms timer)
    Timer {
        id: filterTimer
        interval: 260
        onTriggered: Niche.applyFilters()
    }

    // ═══════════════════════ page-level knobs ═══════════════════════
    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    // The statement scales with the column: 30px on a laptop, 48px wide.
    readonly property int _heroSize: Math.round(Math.max(30, Math.min(48, content.width / 30)))
    // Wide enough for the console monitor and the two-zone drawer.
    readonly property bool _wide: content.width >= 1120
    readonly property bool _narrow: content.width < 760
    // The cuts now exclude every fetched video — the header says so before
    // the empty grid has to.
    readonly property bool _noMatch: Niche.hasResults && !Niche.isRunning
                                     && Niche.metricPool > 0 && Niche.metricMatchFrac <= 0

    // A human read-out of one numeric cut: "≤ 100K", "≥ 1M", "1K – 10K".
    function _cut(minV, maxV) {
        const a = String(minV || "").trim()
        const b = String(maxV || "").trim()
        if (a !== "" && b !== "") return a + " – " + b
        if (b !== "") return "≤ " + b
        if (a !== "") return "≥ " + a
        return ""
    }
    readonly property string _subsCut: Niche.mode === 1 ? "" : _cut(Niche.subsMin, Niche.subsMax)
    readonly property string _viewsCut: _cut(Niche.viewsMin, Niche.viewsMax)
    readonly property string _multCut: String(Niche.multMin || "").trim() !== ""
                                       ? "≥ " + String(Niche.multMin).trim() + "×" : ""
    readonly property string _outlierCut: String(Niche.outlierMin || "").trim() !== ""
                                          ? "≥ " + String(Niche.outlierMin).trim() + "×" : ""

    // Which option of a track the VM's current value is (0 = Any, -1 = a
    // custom value typed in the drawer).
    function _optIndex(opts, value, other) {
        const v = String(value || "").trim()
        const o = String(other || "").trim()
        if (v === "" && o === "") return 0
        if (o !== "") return -1
        for (let i = 0; i < opts.length; i++)
            if (opts[i].v === v) return i
        return -1
    }

    // The stops live in app/core/niche/config.py (the VM counts each one), so
    // the rail and the histogram can never disagree about what a stop means.
    function _stops(track, suffix) {
        const src = (Niche.signalStops && Niche.signalStops[track]) || []
        const out = []
        for (let i = 0; i < src.length; i++)
            out.push({ t: i === 0 ? I18n.tr("Any") : src[i] + suffix, v: src[i] })
        return out
    }
    function _counts(track) {
        return (Niche.signalCounts && Niche.signalCounts[track]) || []
    }

    readonly property var _subsOpts: _stops("subs", "")
    readonly property var _viewsOpts: _stops("views", "")
    readonly property var _multOpts: _stops("mult", "×")
    readonly property var _outlierOpts: _stops("outlier", "×")

    // The cuts the tracks show are not repeated as chips; only the other
    // active options (window, sort, format, depth…) are. A channel scan has
    // no channel-wide cuts, so only its two tracks' keys are claimed.
    readonly property var _trackKeys: Niche.mode === 1
        ? ["views_min", "views_max", "outlier_min"]
        : ["subs_min", "subs_max", "views_min", "views_max", "mult_min", "outlier_min"]
    readonly property int _extraFilters: {
        let n = 0
        const a = Niche.activeFilters || []
        for (let i = 0; i < a.length; i++)
            if (_trackKeys.indexOf(a[i].key) < 0) n++
        return n
    }

    // ═══════════════════════ inline building blocks ═══════════════════════

    // The radar scope: the Hunter Radar (components/HunterRadar.qml). The
    // brand mark is the transmitter at its core; the beam eases between a
    // slow cruise at rest and a hard sweep while a search runs, contacts
    // flare as it passes, and the hero contact locks once there are results.
    component Radar: C.HunterRadar {}

    // One line of the monitor's spec sheet: icon · label ······ value.
    component SpecRow: RowLayout {
        id: spec
        property string icon: ""
        property string label: ""
        property string value: ""
        readonly property bool on: value !== ""
        Layout.fillWidth: true
        spacing: Tokens.space2
        C.IconGlyph {
            name: spec.icon; size: 14
            glyphColor: spec.on ? Theme.primary : Theme.outline
            Layout.alignment: Qt.AlignVCenter
        }
        C.AppText {
            text: spec.label
            font.pixelSize: Tokens.fontCaption
            color: Theme.on_surface_var
            Layout.fillWidth: true
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignVCenter
        }
        C.AppText {
            text: spec.on ? spec.value : I18n.tr("Any")
            mono: spec.on
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontBody
            color: spec.on ? Theme.text_strong : Theme.outline
            LayoutMirroring.enabled: false
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // A fine calibration rail: one stop per value, a lit bridge up to the
    // selected one, and the label under each. It reads as an instrument scale
    // rather than a row of buttons — still one click per stop.
    component SignalRail: Item {
        id: rail
        property var options: []
        // videos left at each stop (same order as options); [] until the
        // first pool exists, which is when the rail stays a bare scale
        property var counts: []
        property int index: 0
        signal picked(string v)
        readonly property int n: options.length
        readonly property bool hasData: n > 0 && counts.length === n
        readonly property real cellW: n > 0 ? width / n : 0
        readonly property int _active: (index >= 0 && index < n) ? index : -1
        readonly property int _max: {
            let m = 0
            for (let i = 0; i < counts.length; i++) m = Math.max(m, counts[i] || 0)
            return m
        }
        // the scale sits lower once the histogram needs room above it
        readonly property int _lineY: hasData ? 30 : 12
        implicitHeight: hasData ? 58 : 42
        Behavior on implicitHeight { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

        // the scale
        Rectangle {
            x: rail.cellW / 2
            y: rail._lineY
            width: Math.max(0, rail.width - rail.cellW)
            height: 2
            radius: 1
            color: Theme.border_med
        }
        // the lit bridge — fills from "Any" to the active stop
        Rectangle {
            x: rail.cellW / 2
            y: rail._lineY
            width: rail._active > 0 ? rail.cellW * rail._active : 0
            height: 2
            radius: 1
            color: Theme.primary
            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }

        Repeater {
            model: rail.options
            Item {
                id: stop
                required property int index
                required property var modelData
                readonly property bool active: rail._active === index
                readonly property int cnt: rail.hasData ? (rail.counts[index] || 0) : -1
                readonly property bool empty: cnt === 0
                width: rail.cellW
                height: rail.height
                x: index * rail.cellW

                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rail.picked(stop.modelData.v)
                }

                // how much the pool gives at this stop — a tall bar is an
                // open door, a missing one is a cut that leads nowhere
                Rectangle {
                    visible: rail.hasData
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 16
                    height: rail._max > 0
                            ? Math.max(stop.cnt > 0 ? 2 : 0,
                                       (rail._lineY - 15) * stop.cnt / rail._max)
                            : 0
                    y: rail._lineY - 4 - height
                    radius: 2
                    color: stop.active ? U.withAlpha(Theme.primary, 0.85)
                         : stop.empty ? U.withAlpha(Theme.on_surface, 0.08)
                         : U.withAlpha(Theme.primary, stopMouse.containsMouse ? 0.42 : 0.26)
                    Behavior on height { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                }
                C.AppText {
                    visible: rail.hasData
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    text: stop.cnt >= 0 ? stop.cnt : ""
                    mono: true
                    weight: stop.active ? Tokens.weightBold : Tokens.weightMedium
                    font.pixelSize: Tokens.fontMicro - 1
                    color: stop.active ? (stop.empty ? Theme.warn : Theme.text_strong)
                         : stop.empty ? Theme.outline : Theme.on_surface_var
                    opacity: stop.empty && !stop.active ? 0.7 : 1
                    LayoutMirroring.enabled: false
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }

                // halo under the chosen stop, so the rail has a "lit" point
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: rail._lineY + 1 - height / 2
                    width: 18; height: 18; radius: 9
                    visible: stop.active
                    color: U.withAlpha(Theme.primary, 0.16)
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: rail._lineY + 1 - height / 2
                    width: stop.active ? 10 : (stopMouse.containsMouse ? 9 : 7)
                    height: width
                    radius: width / 2
                    color: stop.active ? Theme.primary
                         : stopMouse.containsMouse ? Theme.on_surface : Theme.border_med
                    Behavior on width { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                C.AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: rail._lineY + 12
                    text: stop.modelData.t
                    mono: true
                    weight: stop.active ? Tokens.weightBold : Tokens.weightMedium
                    font.pixelSize: Tokens.fontMicro
                    color: stop.active ? Theme.text_strong
                         : stopMouse.containsMouse ? Theme.on_surface : Theme.on_surface_var
                    opacity: stop.empty && !stop.active ? 0.5 : 1
                    LayoutMirroring.enabled: false
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
            }
        }
    }

    // One outlier cut: label, statement read-out, calibration rail with the
    // pool each stop would leave. It draws no box of its own — all four share
    // one deck in the tuner, which is what removes the stacked-card look.
    component SignalTrack: ColumnLayout {
        id: trk
        property string caption: ""
        property string icon: ""
        property string unit: ""
        property string tip: ""
        property string readout: ""
        property var options: []
        property var counts: []
        property int index: 0
        signal picked(string v)
        readonly property bool on: readout !== ""
        readonly property bool hasData: options.length > 0
                                            && counts.length === options.length
        readonly property int _activeCnt: (hasData && index >= 0)
                                          ? (counts[index] || 0) : -1
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: Tokens.space2

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space2
            HoverHandler { id: capHover }
            C.AppTooltip {
                visible: capHover.hovered && trk.tip !== ""
                delay: 420
                text: trk.tip
                preferAbove: true
            }

            Rectangle {
                width: 28; height: 28; radius: 9
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                color: trk.on ? U.withAlpha(Theme.primary, 0.16)
                              : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.03)
                border.width: 1
                border.color: trk.on ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: trk.icon; size: 14
                    fill: trk.on
                    glyphColor: trk.on ? Theme.primary : Theme.on_surface_var
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                C.AppText {
                    Layout.fillWidth: true
                    text: trk.caption
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: trk.on ? Theme.text_strong : Theme.on_surface
                    elide: Text.ElideRight
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: trk.unit
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                visible: trk.on && trk.index < 0
                radius: Tokens.radiusPill
                color: U.withAlpha(Theme.tertiary, 0.12)
                border.width: 1
                border.color: U.withAlpha(Theme.tertiary, 0.35)
                implicitWidth: customLbl.implicitWidth + Tokens.space2 * 2
                implicitHeight: 20
                Layout.alignment: Qt.AlignVCenter
                C.AppText {
                    id: customLbl
                    anchors.centerIn: parent
                    text: I18n.tr("Custom")
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.tertiary
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space1
            spacing: Tokens.space2

            C.AppText {
                text: trk.on ? trk.readout : I18n.tr("Any")
                mono: trk.on
                weight: Tokens.weightExtraBold
                font.pixelSize: 30
                font.letterSpacing: trk.on ? -0.6 : 0
                color: trk.on ? Theme.text_strong : Theme.outline
                LayoutMirroring.enabled: false
                Layout.alignment: Qt.AlignBottom
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            }
            Item { Layout.fillWidth: true }
            // what the chosen stop leaves — the same number the histogram
            // shows, repeated where the eye already is
            Rectangle {
                visible: trk.on && trk.hasData && trk.index >= 0
                radius: Tokens.radiusPill
                color: U.withAlpha(trk._activeCnt === 0 ? Theme.warn : Theme.primary, 0.10)
                border.width: 1
                border.color: U.withAlpha(trk._activeCnt === 0 ? Theme.warn : Theme.primary, 0.28)
                implicitWidth: leftLbl.implicitWidth + Tokens.space2 * 2
                implicitHeight: 20
                Layout.alignment: Qt.AlignBottom
                C.AppText {
                    id: leftLbl
                    anchors.centerIn: parent
                    text: I18n.tr("{n} left").replace("{n}", trk._activeCnt)
                    mono: true
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    color: trk._activeCnt === 0 ? Theme.warn : Theme.primary
                }
            }
            // a quiet bulb that lights once this cut narrows the pool
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 15; implicitHeight: 15
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: U.withAlpha(Theme.primary, 0.14)
                    visible: trk.on
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 7; height: 7; radius: 3.5
                    color: trk.on ? Theme.primary : Theme.border_med
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }
            }
        }

        SignalRail {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.space1
            options: trk.options
            counts: trk.counts
            index: trk.index
            onPicked: (v) => trk.picked(v)
        }
    }

    // Drawer zone header: tinted icon tile + title + behaviour badge
    // ("Instant" green / "On next run" amber). The badge is the whole point.
    component ZoneHead: RowLayout {
        id: zh
        property string title: ""
        property string icon: "tune"
        property string badge: ""
        property bool amber: false
        readonly property color _tone: zh.amber ? Theme.warn : Theme.secondary_container
        spacing: Tokens.space3
        Layout.fillWidth: true
        Rectangle {
            width: 32; height: 32; radius: Tokens.radiusMd
            color: U.withAlpha(zh._tone, 0.12)
            border.width: 1
            border.color: U.withAlpha(zh._tone, 0.32)
            C.IconGlyph {
                anchors.centerIn: parent
                name: zh.icon; size: 16
                glyphColor: zh._tone
            }
        }
        C.AppText {
            text: zh.title
            weight: Tokens.weightBold
            font.pixelSize: Tokens.fontLabel
            color: Theme.text_strong
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Rectangle {
            radius: Tokens.radiusPill
            color: U.withAlpha(zh._tone, 0.12)
            border.width: 1
            border.color: U.withAlpha(zh._tone, 0.35)
            implicitWidth: zhBadge.implicitWidth + Tokens.space3 * 2
            implicitHeight: 22
            Row {
                id: zhBadge
                anchors.centerIn: parent
                spacing: Tokens.space1
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: zh._tone
                    anchors.verticalCenter: parent.verticalCenter
                }
                C.AppText {
                    text: zh.badge
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    color: zh._tone
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Small field caption used above every drawer control.
    component FieldCap: C.AppText {
        weight: Tokens.weightDemiBold
        font.pixelSize: Tokens.fontCaption
        color: Theme.on_surface_var
    }

    // Country explainer. v1.0.1: one Country picker means "content made for
    // that country" (title in its language, channel not registered elsewhere),
    // so the old Language dropdown and Broad/Smart/Strict dial are gone. The
    // sentence comes from the VM (audienceSummary), so it can never disagree
    // with the filter.
    component AudienceCard: Rectangle {
        id: ac
        radius: Tokens.radiusMd
        color: Niche.audienceActive ? U.withAlpha(Theme.primary, Theme.isDark ? 0.08 : 0.05)
                                    : Theme.surface_low
        border.width: 1
        border.color: Niche.audienceActive ? U.withAlpha(Theme.primary, 0.30) : Theme.border
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        implicitHeight: acCol.implicitHeight + Tokens.space3 * 2

        ColumnLayout {
            id: acCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space3
            spacing: Tokens.space3

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                Rectangle {
                    width: 32; height: 32; radius: Tokens.radiusMd
                    color: Niche.audienceActive ? U.withAlpha(Theme.primary, 0.16) : Theme.surface_high
                    border.width: 1
                    border.color: Niche.audienceActive ? U.withAlpha(Theme.primary, 0.32) : Theme.outline_variant
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: "public"; size: 16
                        fill: Niche.audienceActive
                        glyphColor: Niche.audienceActive ? Theme.primary : Theme.on_surface_var
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.AppText {
                        text: I18n.tr("Country match")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontBody
                        color: Theme.text_strong
                    }
                    C.AppText {
                        text: I18n.tr("Filters the current results instantly and steers the next search")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }

            C.AppText {
                Layout.fillWidth: true
                text: Niche.audienceSummary
                font.pixelSize: Tokens.fontCaption
                color: Niche.audienceActive ? Theme.on_surface : Theme.outline
                wrapMode: Text.Wrap
                lineHeight: 1.15
            }

            // English keyword + non-English country: translate it first, or
            // "king" + France finds nothing (French titles say "roi").
            Rectangle {
                Layout.fillWidth: true
                visible: Niche.translateAvailable
                height: 1
                color: Theme.border
            }
            RowLayout {
                Layout.fillWidth: true
                visible: Niche.translateAvailable
                spacing: Tokens.space3
                C.IconGlyph {
                    name: "translate"; size: 16
                    fill: Niche.translateKeyword
                    glyphColor: Niche.translateKeyword ? Theme.primary : Theme.on_surface_var
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.AppText {
                        text: I18n.tr("Translate my keyword")
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontBody
                        color: Niche.translateKeyword ? Theme.primary : Theme.text_strong
                    }
                    C.AppText {
                        Layout.fillWidth: true
                        text: Niche.translateHint
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        wrapMode: Text.Wrap
                    }
                }
                C.AppSwitch {
                    Layout.alignment: Qt.AlignVCenter
                    checked: Niche.translateKeyword
                    onToggled: Niche.translateKeyword = checked
                }
            }

        }
    }

    // An option toggle as a full clickable row: icon tile, label + hint,
    // switch on the far edge. Row and switch both flip the VM exactly once.
    component ToggleCard: Rectangle {
        id: tc
        property string icon: ""
        property string label: ""
        property string hint: ""
        property bool on: false
        signal flipped(bool on)
        radius: Tokens.radiusMd
        color: tcHover.containsMouse ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
        border.width: 1
        border.color: tc.on ? U.withAlpha(Theme.primary, 0.35) : Theme.border
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        implicitHeight: tcRow.implicitHeight + Tokens.space3 * 2
        Layout.fillWidth: true
        MouseArea {
            id: tcHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tc.flipped(!tc.on)
        }
        RowLayout {
            id: tcRow
            anchors.fill: parent
            anchors.margins: Tokens.space3
            spacing: Tokens.space3
            Rectangle {
                width: 32; height: 32; radius: Tokens.radiusMd
                color: tc.on ? U.withAlpha(Theme.primary, 0.14) : Theme.surface_high
                border.width: 1
                border.color: tc.on ? U.withAlpha(Theme.primary, 0.30) : Theme.outline_variant
                C.IconGlyph {
                    anchors.centerIn: parent
                    name: tc.icon; size: 16
                    glyphColor: tc.on ? Theme.primary : Theme.on_surface_var
                }
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                C.AppText {
                    text: tc.label
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontBody
                    color: tc.on ? Theme.primary : Theme.text_strong
                }
                C.AppText {
                    text: tc.hint
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
            C.AppSwitch {
                checked: tc.on
                onClicked: tc.flipped(checked)
            }
        }
    }

    // ═══════════════════════ page ═══════════════════════
    C.SmoothScrollView {
        id: scroller
        anchors.fill: parent

        Item {
            id: canvas
            width: parent.width
            implicitHeight: content.implicitHeight + Tokens.space7 * 2

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 460
            }

            ColumnLayout {
                id: content
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space6
                spacing: Tokens.space4

                // ═══════════════ 1 · CONSOLE — aim ═══════════════
                C.GlassPanel {
                    id: consolePanel
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: consoleRow.implicitHeight + Tokens.space6 * 2

                    C.CornerGlow { radius: Tokens.radiusXl; size: 620 }

                    RowLayout {
                        id: consoleRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space6

                        // ── left: statement + command bar ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Tokens.space4

                            // eyebrow: live dot + section name
                            Row {
                                spacing: Tokens.space3
                                Rectangle {
                                    radius: Tokens.radiusPill
                                    color: U.withAlpha(Theme.primary, 0.10)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.primary, 0.28)
                                    width: eyebrowRow.implicitWidth + Tokens.space3 * 2
                                    height: 28
                                    Row {
                                        id: eyebrowRow
                                        anchors.centerIn: parent
                                        spacing: Tokens.space2
                                        Rectangle {
                                            width: 7; height: 7; radius: 4
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                            SequentialAnimation on opacity {
                                                running: page._motion && page.visible && (Niche.isRunning || Tokens.appActive)
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 0.25; duration: Niche.isRunning ? 420 : 1100; easing.type: Easing.InOutQuad }
                                                NumberAnimation { to: 1.0; duration: Niche.isRunning ? 420 : 1100; easing.type: Easing.InOutQuad }
                                            }
                                        }
                                        C.AppText {
                                            text: Niche.isRunning ? I18n.tr("Scanning YouTube")
                                                  : Niche.viralActive ? I18n.tr("Niche Finder · Viral Radar")
                                                  : I18n.tr("Niche Finder · Outlier Radar")
                                            weight: Tokens.weightBold
                                            font.pixelSize: Tokens.fontCaption
                                            font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }

                            // the statement — big, quiet, two tones
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                C.AppText {
                                    text: I18n.tr("Find small channels")
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: page._heroSize
                                    font.letterSpacing: I18n.rtl ? 0 : -page._heroSize * 0.022
                                    lineHeight: 1.05
                                    color: Theme.text_strong
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }
                                C.AppText {
                                    text: I18n.tr("pulling giant numbers.")
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: page._heroSize
                                    font.letterSpacing: I18n.rtl ? 0 : -page._heroSize * 0.022
                                    lineHeight: 1.05
                                    color: Theme.primary
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }
                            }
                            C.AppText {
                                text: I18n.tr("Search a niche, then cut by channel size, reach and the views ÷ subscribers multiplier. Every cut re-filters instantly.")
                                font.pixelSize: Tokens.fontLabel
                                color: Theme.on_surface_var
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                Layout.maximumWidth: 620
                            }

                            // ── the command bar ──
                            Item {
                                Layout.fillWidth: true
                                Layout.topMargin: Tokens.space3
                                implicitHeight: 66

                                // focus halo — accent → tertiary ring outside the bar
                                Rectangle {
                                    anchors.fill: cmdBar
                                    anchors.margins: -3
                                    radius: cmdBar.radius + 3
                                    opacity: queryInput.activeFocus ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.55) }
                                        GradientStop { position: 0.6; color: U.withAlpha(Theme.primary, 0.18) }
                                        GradientStop { position: 1.0; color: U.withAlpha(Theme.tertiary, 0.30) }
                                    }
                                }

                                Rectangle {
                                    id: cmdBar
                                    anchors.fill: parent
                                    radius: Tokens.radiusXl
                                    color: Theme.input_bg
                                    border.width: 1
                                    border.color: queryInput.activeFocus ? U.withAlpha(U.mix(Theme.border, Theme.outline, 0.35), 0)
                                                                         : U.mix(Theme.border, Theme.outline, 0.35)
                                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.space2
                                        spacing: Tokens.space2

                                        // mode — sliding segmented, nested in the bar
                                        C.SlideSegment {
                                            id: modeSeg
                                            Layout.alignment: Qt.AlignVCenter
                                            readonly property bool compact: cmdBar.width < 900
                                            iconOnly: compact
                                            cellHeight: 42
                                            radius: Tokens.radiusLg - 2
                                            trackColor: Theme.surface_high
                                            model: [
                                                { icon: "search", label: I18n.tr("Keyword Search") },
                                                { icon: "user",   label: I18n.tr("Single Channel Scan") }
                                            ]
                                            currentIndex: Niche.mode
                                            onActivated: (i) => { Niche.mode = i; queryInput.forceActiveFocus() }
                                        }

                                        C.IconGlyph {
                                            name: Niche.mode === 1 ? "link" : "travel_explore"
                                            size: 20
                                            glyphColor: queryInput.activeFocus ? Theme.primary : Theme.on_surface_var
                                            Layout.leftMargin: Tokens.space2
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        TextField {
                                            id: queryInput
                                            // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                            T.ContextMenu.menu: C.EditMenu { editor: queryInput }
                                            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                            selectedTextColor: Theme.text_strong
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            placeholderText: Niche.mode === 1
                                                   ? "https://youtube.com/@channelname"
                                                   : I18n.tr("e.g.  faceless ai channel, reddit stories, satisfying asmr")
                                            placeholderTextColor: Theme.outline
                                            color: Theme.text_strong
                                            font.family: Fonts.body
                                            font.pixelSize: Tokens.fontSubtitle
                                            selectByMouse: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            leftPadding: Tokens.space1
                                            rightPadding: Tokens.space1
                                            background: null
                                            text: Niche.query
                                            onTextChanged: Niche.query = text
                                            // Enter runs the search.
                                            onAccepted: if (!Niche.isRunning) Niche.search()
                                            HoverHandler { cursorShape: Qt.IBeamCursor }
                                        }

                                        C.IconButton {
                                            visible: queryInput.text !== "" && !Niche.isRunning
                                            width: 32; height: 32
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 32
                                            Layout.alignment: Qt.AlignVCenter
                                            iconName: "close"
                                            tip: I18n.tr("Clear")
                                            onClicked: { queryInput.text = ""; queryInput.forceActiveFocus() }
                                        }

                                        // source — keyword mode only
                                        Rectangle {
                                            visible: Niche.mode === 0
                                            width: 1
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: 28
                                            Layout.alignment: Qt.AlignVCenter
                                            color: Theme.border
                                        }
                                        C.Dropdown {
                                            visible: Niche.mode === 0
                                            Layout.preferredWidth: Math.max(160, Math.min(260, cmdBar.width * 0.2))
                                            Layout.alignment: Qt.AlignVCenter
                                            transparentBg: true
                                            borderColor: "transparent"
                                            model: Niche.sourceOptions
                                            currentIndex: Niche.source
                                            onActivated: Niche.source = currentIndex
                                        }

                                        C.PrimaryButton {
                                            Layout.fillHeight: true
                                            implicitHeight: 50
                                            text: Niche.isRunning ? I18n.tr("Searching …")
                                                  : (Niche.mode === 1 ? I18n.tr("Scan Channel") : I18n.tr("Search"))
                                            iconName: "travel_explore"
                                            enabled: !Niche.isRunning && queryInput.text.trim() !== ""
                                            // Doubles as its own progress bar while
                                            // the run is on (Stop lives on the
                                            // loading panel below).
                                            progress: Niche.isRunning
                                                      ? (Niche.pct > 0 ? Niche.pct / 100 : -1) : -1
                                            indeterminate: Niche.isRunning && Niche.pct <= 0
                                            onClicked: Niche.search()
                                        }
                                    }
                                }
                            }

                            // ── under the bar: keycap hint + one-click examples ──
                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space2

                                Row {
                                    spacing: Tokens.space2
                                    height: 30
                                    // a keycap, not an icon — it is a key you press
                                    Rectangle {
                                        width: kbdLbl.implicitWidth + Tokens.space2 * 2
                                        height: 22
                                        radius: Tokens.radiusXs
                                        color: Theme.surface_high
                                        border.width: 1
                                        border.color: Theme.border_med
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 2
                                            radius: parent.radius
                                            color: U.withAlpha(Theme.on_surface, 0.06)
                                        }
                                        C.AppText {
                                            id: kbdLbl
                                            anchors.centerIn: parent
                                            text: "Enter"
                                            mono: true
                                            weight: Tokens.weightDemiBold
                                            font.pixelSize: Tokens.fontMicro
                                            color: Theme.on_surface_var
                                            LayoutMirroring.enabled: false
                                        }
                                    }
                                    C.AppText {
                                        text: Niche.mode === 1
                                              ? I18n.tr("Paste a channel URL, @handle or name · Enter to scan")
                                              : I18n.tr("Enter to search · separate several keywords with a comma")
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.outline
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Item { width: Tokens.space3; height: 30; visible: tryRow.visible }

                                Row {
                                    id: tryRow
                                    spacing: Tokens.space2
                                    height: 30
                                    visible: Niche.mode === 0 && queryInput.text === "" && !Niche.isRunning
                                    C.AppText {
                                        text: I18n.tr("Try")
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Repeater {
                                        model: ["faceless ai channel", "reddit stories", "satisfying asmr", "budget travel hacks"]
                                        AbstractButton {
                                            id: tryChip
                                            height: 28
                                            anchors.verticalCenter: parent.verticalCenter
                                            implicitWidth: tryRowIn.implicitWidth + Tokens.space3 * 2
                                            hoverEnabled: true
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            onClicked: { queryInput.text = modelData; queryInput.forceActiveFocus() }
                                            background: Rectangle {
                                                radius: Tokens.radiusPill
                                                color: tryChip.hovered ? U.mix(Theme.surface_low, Theme.primary, 0.10) : U.withAlpha(U.mix(Theme.surface_low, Theme.primary, 0.10), 0)
                                                border.width: 1
                                                border.color: tryChip.hovered ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            }
                                            contentItem: Item {
                                                implicitWidth: tryRowIn.implicitWidth
                                                implicitHeight: tryRowIn.implicitHeight
                                                Row {
                                                    id: tryRowIn
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space1
                                                    C.AppText {
                                                        text: modelData
                                                        font.pixelSize: Tokens.fontCaption
                                                        weight: Tokens.weightMedium
                                                        color: tryChip.hovered ? Theme.primary : Theme.on_surface
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        LayoutMirroring.enabled: false
                                                    }
                                                    C.IconGlyph {
                                                        name: "arrow_right_up"; size: 12
                                                        glyphColor: tryChip.hovered ? Theme.primary : Theme.outline
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── status + archive + quota — the summary AFTER a run ──
                            // v16: one composed ResultBanner instead of a mono
                            // status line with a dot + a flat green strip.
                            // While the search runs the loading panel owns the
                            // reporting, so this steps aside.
                            C.ResultBanner {
                                Layout.fillWidth: true
                                visible: !Niche.isRunning && (Niche.statusText !== "" || Niche.archiveNote !== "")
                                kind: Niche.statusText !== "" ? Niche.statusKind : "ok"
                                text: Niche.statusText !== "" ? Niche.statusText : Niche.archiveNote
                                note: Niche.statusText !== "" ? Niche.archiveNote : ""
                                noteIcon: "archive"
                                noteKind: Niche.archiveNote.indexOf("(") === 0 ? "warn" : "ok"

                                // quota lives in the monitor on wide windows
                                Rectangle {
                                    visible: Niche.quotaText !== "" && !monitor.visible
                                    radius: Tokens.radiusPill
                                    color: Theme.surface_low
                                    border.width: 1
                                    border.color: Theme.border
                                    width: quotaRowA.implicitWidth + Tokens.space3 * 2
                                    height: 28
                                    Row {
                                        id: quotaRowA
                                        anchors.centerIn: parent
                                        spacing: Tokens.space1
                                        C.IconGlyph {
                                            name: "bolt"; size: 12
                                            glyphColor: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        C.AppText {
                                            text: Niche.quotaText
                                            mono: true
                                            weight: Tokens.weightDemiBold
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.on_surface_var
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }

                        // ── right: the live monitor ──
                        // The radar is the read-out of what you are hunting for:
                        // the scope on top, the current cuts as a spec sheet
                        // underneath, the cost of the next run at the foot.
                        Rectangle {
                            id: monitor
                            visible: page._wide
                            Layout.preferredWidth: 320
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            radius: Tokens.radiusLg
                            color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.70 : 0.92)
                            border.width: 1
                            border.color: Theme.border
                            implicitHeight: monCol.implicitHeight + Tokens.space4 * 2

                            ColumnLayout {
                                id: monCol
                                anchors.fill: parent
                                anchors.margins: Tokens.space4
                                spacing: Tokens.space3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    C.AppText {
                                        text: I18n.tr("Live signal")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                                        color: Theme.on_surface_var
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        Layout.alignment: Qt.AlignVCenter
                                        color: Niche.isRunning ? Theme.primary
                                             : Niche.hasResults ? Theme.secondary_container : Theme.outline
                                    }
                                    C.AppText {
                                        text: Niche.isRunning ? I18n.tr("Scanning")
                                              : Niche.hasResults ? I18n.tr("{n} matches").replace("{n}", Niche.metricMatches)
                                              : I18n.tr("Idle")
                                        mono: true
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Niche.isRunning ? Theme.primary : Theme.on_surface_var
                                    }
                                }

                                Radar {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: Tokens.space2
                                    Layout.preferredWidth: 216
                                    Layout.preferredHeight: 216
                                    active: Niche.isRunning
                                    motion: page._motion
                                    hits: Niche.hasResults
                                }

                                C.AppText {
                                    Layout.topMargin: Tokens.space3
                                    text: I18n.tr("Hunting for")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.text_strong
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    SpecRow {
                                        visible: Niche.mode === 0
                                        icon: "user"
                                        label: I18n.tr("Channel size")
                                        value: page._subsCut
                                    }
                                    SpecRow {
                                        icon: "visibility"
                                        label: I18n.tr("Views")
                                        value: page._viewsCut
                                    }
                                    SpecRow {
                                        visible: Niche.mode === 0
                                        icon: "trending_up"
                                        label: I18n.tr("Multiplier")
                                        value: page._multCut
                                    }
                                    SpecRow {
                                        icon: "query_stats"
                                        label: I18n.tr("vs own average")
                                        value: page._outlierCut
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Theme.border
                                    visible: Niche.quotaText !== ""
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: Niche.quotaText !== ""
                                    spacing: Tokens.space2
                                    C.IconGlyph { name: "bolt"; size: 13; glyphColor: Theme.primary; Layout.alignment: Qt.AlignVCenter }
                                    C.AppText {
                                        text: Niche.quotaText
                                        mono: true
                                        weight: Tokens.weightDemiBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════ 2 · TUNER — cut ═══════════════
                C.GlassPanel {
                    objectName: "tour_nicheFilters"
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: tunerCol.implicitHeight + Tokens.space5 * 2

                    ColumnLayout {
                        id: tunerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space4

                        // header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3
                            C.IconTile {
                                iconName: "target"
                                size: 38
                                solid: Niche.activeFilterCount > 0
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignVCenter
                            }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                C.AppText {
                                    text: I18n.tr("Outlier signal")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontSubtitle
                                    color: Theme.text_strong
                                }
                                C.AppText {
                                    text: Niche.hasResults
                                          ? I18n.tr("Re-filters the fetched pool instantly · no quota")
                                          : I18n.tr("Set the cuts first or after — every change re-filters instantly.")
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                            // Live impact, at the point of action: how many of
                            // the fetched pool survive the current cuts, with
                            // the same share meter the scoreboard uses.
                            Rectangle {
                                visible: Niche.hasResults && !Niche.isRunning
                                Layout.alignment: Qt.AlignVCenter
                                radius: Tokens.radiusPill
                                color: U.withAlpha(page._noMatch ? Theme.warn : Theme.secondary_container, 0.10)
                                border.width: 1
                                border.color: U.withAlpha(page._noMatch ? Theme.warn : Theme.secondary_container, 0.30)
                                implicitWidth: impactRow.implicitWidth + Tokens.space3 * 2
                                implicitHeight: 30
                                Row {
                                    id: impactRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.space2
                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        color: page._noMatch ? Theme.warn : Theme.secondary_container
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    C.AppText {
                                        text: page._noMatch
                                              ? I18n.tr("No matches")
                                              : I18n.tr("{n} matches").replace("{n}", Niche.metricMatches)
                                        mono: !page._noMatch
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: page._noMatch ? Theme.warn : Theme.secondary_container
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Rectangle {
                                        width: 38; height: 3; radius: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: U.withAlpha(page._noMatch ? Theme.warn : Theme.secondary_container, 0.18)
                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(1, Niche.metricMatchFrac))
                                            height: parent.height
                                            radius: 2
                                            color: page._noMatch ? Theme.warn : Theme.secondary_container
                                            Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "restart_alt"
                                text: I18n.tr("Reset all")
                                visible: Niche.activeFilterCount > 0
                                implicitHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: Niche.clearAllFilters()
                            }
                        }

                        // the console deck — all three cuts on ONE instrument
                        // face, with no nested cards between them
                        Rectangle {
                            Layout.fillWidth: true
                            radius: Tokens.radiusLg
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: U.withAlpha(Theme.surface_low, Theme.isDark ? 0.78 : 0.94) }
                                GradientStop { position: 1.0; color: U.withAlpha(Theme.surface, Theme.isDark ? 0.42 : 0.92) }
                            }
                            border.width: 1
                            border.color: Theme.border
                            implicitHeight: trackGrid.implicitHeight + Tokens.space5 * 2

                            // specular top edge — the same lit-glass language
                            // as GlassPanel, so the deck belongs to the panel
                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(0, parent.width - Tokens.radiusLg * 2)
                                height: 1
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                                    GradientStop { position: 0.5; color: Theme.glass_hi }
                                    GradientStop { position: 1.0; color: U.withAlpha(Theme.glass_hi, 0.0) }
                                }
                            }

                            GridLayout {
                                id: trackGrid
                                anchors.fill: parent
                                anchors.margins: Tokens.space5
                                // Four instruments across when there is room;
                                // two rows of two at mid widths; one column
                                // when narrow. A channel scan drops the two
                                // channel-wide tracks, so it stays two-up.
                                columns: page._narrow ? 1
                                       : (Niche.mode === 1 ? 2 : (page._wide ? 4 : 2))
                                columnSpacing: Tokens.space5
                                rowSpacing: Tokens.space5

                                SignalTrack {
                                    // Single Channel Scan has no channel-wide
                                    // cuts: subscriber count and views÷subs
                                    // describe the channel, not its videos.
                                    visible: Niche.mode === 0
                                    caption: I18n.tr("Channel size")
                                    icon: "user"
                                    unit: I18n.tr("subscribers")
                                    tip: I18n.tr("The channel's subscriber count. Small channels are where an outlier means the idea won, not the audience.")
                                    readout: page._subsCut
                                    options: page._subsOpts
                                    counts: page._counts("subs")
                                    index: page._optIndex(page._subsOpts, Niche.subsMax, Niche.subsMin)
                                    onPicked: (v) => { Niche.subsMin = ""; Niche.subsMax = v; filterTimer.restart() }
                                }
                                SignalTrack {
                                    caption: I18n.tr("Reach")
                                    icon: "visibility"
                                    unit: I18n.tr("views")
                                    tip: I18n.tr("The video's own view count.")
                                    readout: page._viewsCut
                                    options: page._viewsOpts
                                    counts: page._counts("views")
                                    index: page._optIndex(page._viewsOpts, Niche.viewsMin, Niche.viewsMax)
                                    onPicked: (v) => { Niche.viewsMax = ""; Niche.viewsMin = v; filterTimer.restart() }
                                }
                                SignalTrack {
                                    visible: Niche.mode === 0
                                    caption: I18n.tr("Views ÷ subscribers")
                                    icon: "trending_up"
                                    unit: I18n.tr("multiplier")
                                    tip: I18n.tr("How far the video outran the channel's subscriber base.")
                                    readout: page._multCut
                                    options: page._multOpts
                                    counts: page._counts("mult")
                                    index: page._optIndex(page._multOpts, Niche.multMin, "")
                                    onPicked: (v) => { Niche.multMin = v; filterTimer.restart() }
                                }
                                SignalTrack {
                                    caption: I18n.tr("vs own average")
                                    icon: "query_stats"
                                    unit: I18n.tr("channel outlier")
                                    tip: I18n.tr("Views against the channel's own typical video. The cleanest outlier signal: the idea won, not the audience.")
                                    readout: page._outlierCut
                                    options: page._outlierOpts
                                    counts: page._counts("outlier")
                                    index: page._optIndex(page._outlierOpts, Niche.outlierMin, "")
                                    onPicked: (v) => { Niche.outlierMin = v; filterTimer.restart() }
                                }
                            }
                        }

                        // recipes (ready-made combinations) + drawer trigger
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3

                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                Row {
                                    height: 34
                                    spacing: Tokens.space1 + 2
                                    C.IconGlyph {
                                        name: "auto_awesome"; size: 13
                                        glyphColor: Theme.tertiary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    C.AppText {
                                        text: I18n.tr("Recipes")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption
                                        color: Theme.on_surface_var
                                        anchors.verticalCenter: parent.verticalCenter
                                        rightPadding: Tokens.space1
                                    }
                                }
                                Repeater {
                                    model: Niche.presetOptions
                                    AbstractButton {
                                        id: presetBtn
                                        // the last preset is "Clear filters" —
                                        // that lives in the header as Reset all
                                        visible: index < 5
                                        // the chip the form currently IS; any
                                        // touch on a cut un-lights it
                                        readonly property bool current: Niche.activePreset === index
                                        height: 34
                                        implicitWidth: presetRow.implicitWidth + Tokens.space4 * 2
                                        hoverEnabled: true
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        // second click returns to the open form
                                        onClicked: presetBtn.current ? Niche.clearAllFilters()
                                                                     : Niche.applyPreset(index)
                                        scale: presetBtn.pressed ? Tokens.pressScale
                                             : presetBtn.hovered ? 1.012 : 1.0
                                        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                                        background: Rectangle {
                                            radius: Tokens.radiusPill
                                            // Opaque fills only — a translucent
                                            // hover passes through mid-grey.
                                            color: presetBtn.current
                                                   ? U.mix(Theme.surface, Theme.primary, 0.14)
                                                   : presetBtn.hovered ? U.mix(Theme.surface, Theme.primary, 0.10)
                                                                       : Theme.surface
                                            border.width: 1
                                            border.color: presetBtn.current ? U.withAlpha(Theme.primary, 0.62)
                                                         : presetBtn.hovered ? U.withAlpha(Theme.primary, 0.40)
                                                                             : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        }
                                        contentItem: Item {
                                            implicitWidth: presetRow.implicitWidth
                                            implicitHeight: presetRow.implicitHeight
                                            Row {
                                                id: presetRow
                                                anchors.centerIn: parent
                                                spacing: Tokens.space2
                                                C.IconGlyph {
                                                    name: ["user", "bolt", "query_stats", "movie", "fmt_short"][index] || "tune"
                                                    size: 14
                                                    fill: presetBtn.hovered || presetBtn.current
                                                    glyphColor: presetBtn.current ? Theme.primary : Theme.on_surface_var
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: modelData
                                                    weight: presetBtn.current ? Tokens.weightBold : Tokens.weightDemiBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: presetBtn.current ? Theme.primary
                                                         : presetBtn.hovered ? Theme.text_strong : Theme.on_surface
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.IconGlyph {
                                                    visible: presetBtn.current
                                                    name: "check"; size: 12
                                                    glyphColor: Theme.primary
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                            C.AppTooltip {
                                                visible: presetBtn.hovered
                                                         && (Niche.presetHints[index] || "") !== ""
                                                delay: 420
                                                text: Niche.presetHints[index] || ""
                                                preferAbove: true
                                            }
                                        }
                                    }
                                }
                            }

                            AbstractButton {
                                id: advBtn
                                Layout.alignment: Qt.AlignTop
                                hoverEnabled: true
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                onClicked: page.filtersOpen = !page.filtersOpen
                                leftPadding: Tokens.space4
                                rightPadding: Tokens.space4
                                topPadding: 0
                                bottomPadding: 0
                                implicitHeight: 36
                                background: Rectangle {
                                    radius: Tokens.radiusPill
                                    color: page.filtersOpen ? U.mix(Theme.surface_low, Theme.primary, 0.12)
                                         : advBtn.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                                         : Theme.surface_low
                                    border.width: 1
                                    border.color: page.filtersOpen ? U.withAlpha(Theme.primary, 0.45)
                                                                   : U.mix(Theme.border, Theme.outline, 0.45)
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                }
                                contentItem: RowLayout {
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: "tune"; size: 16
                                        glyphColor: page.filtersOpen ? Theme.primary : Theme.text_strong
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    C.AppText {
                                        text: I18n.tr("Advanced filters")
                                        weight: Tokens.weightBold
                                        font.pixelSize: Tokens.fontCaption + 1
                                        color: page.filtersOpen ? Theme.primary : Theme.text_strong
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Rectangle {
                                        visible: page._extraFilters > 0
                                        radius: Tokens.radiusPill
                                        color: Theme.primary
                                        implicitWidth: Math.max(18, cntLbl.implicitWidth + 8)
                                        implicitHeight: 18
                                        Layout.alignment: Qt.AlignVCenter
                                        C.AppText {
                                            id: cntLbl
                                            anchors.centerIn: parent
                                            text: page._extraFilters
                                            mono: true
                                            weight: Tokens.weightExtraBold
                                            font.pixelSize: Tokens.fontMicro
                                            color: Theme.on_primary
                                        }
                                    }
                                    C.IconGlyph {
                                        name: "expand_more"
                                        size: 16
                                        glyphColor: page.filtersOpen ? Theme.primary : Theme.text_strong
                                        rotation: page.filtersOpen ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }
                        }

                        // the other active options as removable chips
                        // (drawer closed only — open, the controls say it)
                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            visible: !page.filtersOpen && page._extraFilters > 0
                            C.AppText {
                                text: I18n.tr("Also on")
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                                height: 28
                                verticalAlignment: Text.AlignVCenter
                                rightPadding: Tokens.space1
                            }
                            Repeater {
                                model: Niche.activeFilters
                                Rectangle {
                                    visible: page._trackKeys.indexOf(modelData.key) < 0
                                    radius: Tokens.radiusPill
                                    color: U.withAlpha(Theme.primary, 0.07)
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.primary, 0.30)
                                    width: chipRow.implicitWidth + Tokens.space3 * 2
                                    height: 28
                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: Tokens.space1
                                        C.AppText {
                                            text: modelData.label
                                            font.pixelSize: Tokens.fontCaption
                                            weight: Tokens.weightDemiBold
                                            color: Theme.on_surface
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        AbstractButton {
                                            width: 16; height: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: Niche.clearFilter(modelData.key)
                                            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                            contentItem: C.IconGlyph {
                                                name: "close"; size: 12
                                                glyphColor: chipHover.hovered ? Theme.primary : Theme.on_surface_var
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── the drawer ──
                        // Outer is a plain Item (not a Layout) whose height we
                        // animate; a Layout here would fight the animation.
                        Item {
                            id: drawer
                            Layout.fillWidth: true
                            readonly property real fullHeight: drawerGrid.implicitHeight + Tokens.space1
                            Layout.preferredHeight: page.filtersOpen ? fullHeight : 0
                            implicitHeight: page.filtersOpen ? fullHeight : 0
                            clip: true
                            visible: Layout.preferredHeight > 0
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

                            GridLayout {
                                id: drawerGrid
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                columns: page._wide ? 2 : 1
                                columnSpacing: Tokens.space3
                                rowSpacing: Tokens.space3
                                opacity: page.filtersOpen ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }

                                // ══ zone A — instant ══
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 3
                                    radius: Tokens.radiusLg
                                    color: U.withAlpha(Theme.surface_low, 0.6)
                                    border.width: 1
                                    border.color: Theme.border
                                    implicitHeight: zoneA.implicitHeight + Tokens.space5 * 2

                                    ColumnLayout {
                                        id: zoneA
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.space5
                                        spacing: Tokens.space4

                                        ZoneHead {
                                            title: I18n.tr("Refine current results")
                                            icon: "bolt"
                                            badge: I18n.tr("Instant")
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: page._narrow ? 1 : 3
                                            columnSpacing: Tokens.space4
                                            rowSpacing: Tokens.space4
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Published within") }
                                                C.Dropdown { Layout.fillWidth: true; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.timeframeOptions; currentIndex: Niche.timeframeIndex; onActivated: { Niche.timeframeIndex = currentIndex; Niche.applyFilters() } }
                                            }
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Sort results by") }
                                                C.Dropdown { Layout.fillWidth: true; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.sortOptions; currentIndex: Niche.sortIndex; onActivated: { Niche.sortIndex = currentIndex; Niche.applyFilters() } }
                                            }
                                            // new channels blowing up = an open niche
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Channel age") }
                                                C.Dropdown { Layout.fillWidth: true; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.channelAgeOptions; currentIndex: Niche.channelAgeIndex; onActivated: Niche.channelAgeIndex = currentIndex }
                                            }
                                            // v1.0.2 — "does this niche work at 8–20 min?"
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Video length") }
                                                C.Dropdown { Layout.fillWidth: true; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.durationOptions; currentIndex: Niche.durationIndex; onActivated: Niche.durationIndex = currentIndex }
                                            }
                                            // few uploads + a big hit = the idea did the work
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Channel uploads") }
                                                C.Dropdown { Layout.fillWidth: true; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.uploadsOptions; currentIndex: Niche.uploadsIndex; onActivated: Niche.uploadsIndex = currentIndex }
                                            }
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Category") }
                                                C.Dropdown { Layout.fillWidth: true; popupMaxHeight: 380; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.categoryOptions; currentIndex: Niche.categoryIndex; onActivated: Niche.categoryIndex = currentIndex }
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: page._narrow ? 1 : 2
                                            columnSpacing: Tokens.space4
                                            rowSpacing: Tokens.space4
                                            ColumnLayout {
                                                spacing: Tokens.space2
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 3
                                                FieldCap { text: I18n.tr("Format") }
                                                C.SlideSegment {
                                                    Layout.fillWidth: true
                                                    equal: true
                                                    solid: false
                                                    cellHeight: 36
                                                    fontSize: Tokens.fontCaption + 1
                                                    model: [
                                                        { icon: "movie",     label: Niche.formatOptions[0] || "" },
                                                        { icon: "fmt_long",  label: Niche.formatOptions[1] || "" },
                                                        { icon: "fmt_short", label: Niche.formatOptions[2] || "" }
                                                    ]
                                                    currentIndex: Niche.formatIndex
                                                    onActivated: (i) => { Niche.formatIndex = i; Niche.applyFilters() }
                                                }
                                            }
                                            // one prolific channel can't flood the page:
                                            // "how many channels are winning" is the saturation read
                                            ColumnLayout {
                                                spacing: Tokens.space2
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 2
                                                FieldCap { text: I18n.tr("Per channel") }
                                                C.SlideSegment {
                                                    Layout.fillWidth: true
                                                    equal: true
                                                    solid: false
                                                    cellHeight: 36
                                                    fontSize: Tokens.fontCaption + 1
                                                    model: [ I18n.tr("All"), I18n.tr("Best 1"), I18n.tr("Best 3") ]
                                                    currentIndex: Niche.perChannelIndex
                                                    onActivated: (i) => { Niche.perChannelIndex = i }
                                                }
                                            }
                                        }

                                        // precise numeric cuts, for when the
                                        // tracks above aren't exact enough. These
                                        // are handed to the search itself too.
                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: page._narrow ? 1 : (Niche.mode === 1 ? 2 : 3)
                                            columnSpacing: Tokens.space3
                                            rowSpacing: Tokens.space4
                                            C.RangeField {
                                                visible: Niche.mode === 0
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                                label: I18n.tr("Subscribers"); labelIcon: "user"
                                                minPlaceholder: "100"; maxPlaceholder: "3,000"
                                                minText: Niche.subsMin
                                                maxText: Niche.subsMax
                                                onMinEdited: (v) => { Niche.subsMin = v; filterTimer.restart() }
                                                onMaxEdited: (v) => { Niche.subsMax = v; filterTimer.restart() }
                                            }
                                            C.RangeField {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                                label: I18n.tr("Views"); labelIcon: "visibility"
                                                minPlaceholder: "1M"; maxPlaceholder: I18n.tr("any")
                                                minText: Niche.viewsMin
                                                maxText: Niche.viewsMax
                                                onMinEdited: (v) => { Niche.viewsMin = v; filterTimer.restart() }
                                                onMaxEdited: (v) => { Niche.viewsMax = v; filterTimer.restart() }
                                            }
                                            C.LineField {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                                label: I18n.tr("Min views ÷ subscribers"); labelIcon: "trending_up"
                                                placeholder: "50"
                                                text: Niche.multMin
                                                onTextChanged: { if (Niche.multMin !== text) { Niche.multMin = text; filterTimer.restart() } }
                                            }
                                        }

                                        // v1.0.2 — the signals a pro filters on after
                                        // reach: beats its OWN channel, still moving,
                                        // people actually reacting.
                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: page._narrow ? 1 : 3
                                            columnSpacing: Tokens.space3
                                            rowSpacing: Tokens.space4
                                            C.LineField {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                                label: I18n.tr("Min × channel average"); labelIcon: "bolt"
                                                placeholder: "5"
                                                text: Niche.outlierMin
                                                onTextChanged: { if (Niche.outlierMin !== text) { Niche.outlierMin = text; filterTimer.restart() } }
                                            }
                                            C.LineField {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                                label: I18n.tr("Min views / hour"); labelIcon: "speed"
                                                placeholder: "1K"
                                                text: Niche.velMin
                                                onTextChanged: { if (Niche.velMin !== text) { Niche.velMin = text; filterTimer.restart() } }
                                            }
                                            C.LineField {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                borderColor: U.mix(Theme.border, Theme.outline, 0.45)
                                                label: I18n.tr("Min engagement %"); labelIcon: "favorite"
                                                placeholder: "4"
                                                text: Niche.engMin
                                                onTextChanged: { if (Niche.engMin !== text) { Niche.engMin = text; filterTimer.restart() } }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Tokens.space2
                                            C.IconGlyph {
                                                name: "info"; size: 14
                                                glyphColor: Theme.outline
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 1
                                            }
                                            C.AppText {
                                                Layout.fillWidth: true
                                                text: I18n.tr("× channel average = views against the channel's own typical video, the cleanest outlier signal. Type -word in the results filter to exclude it. Too few matches? The next run widens itself (uses more quota).")
                                                font.pixelSize: Tokens.fontCaption
                                                color: Theme.outline
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }
                                }

                                // ══ zone B — next run ══
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 2
                                    radius: Tokens.radiusLg
                                    color: U.withAlpha(Theme.surface_low, 0.6)
                                    border.width: 1
                                    border.color: Theme.border
                                    implicitHeight: zoneB.implicitHeight + Tokens.space5 * 2

                                    ColumnLayout {
                                        id: zoneB
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: Tokens.space5
                                        spacing: Tokens.space4

                                        ZoneHead {
                                            title: I18n.tr("Next search options")
                                            icon: "hourglass_empty"
                                            badge: I18n.tr("On next run")
                                            amber: true
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: page._narrow ? 1 : 2
                                            columnSpacing: Tokens.space4
                                            rowSpacing: Tokens.space4
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true
                                                Layout.columnSpan: page._narrow ? 1 : 2
                                                FieldCap { text: I18n.tr("Search depth") }
                                                C.Dropdown { Layout.fillWidth: true; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.depthOptions; currentIndex: Niche.depthIndex; onActivated: Niche.depthIndex = currentIndex }
                                                // "Deep scan" is no longer a separate toggle: Deep and up slice the window
                                                C.AppText {
                                                    Layout.fillWidth: true
                                                    text: I18n.tr("Deep and above also slice the time window, so small channels surface.")
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: Theme.outline
                                                    wrapMode: Text.Wrap
                                                }
                                            }
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true
                                                Layout.columnSpan: page._narrow ? 1 : 2
                                                FieldCap { text: I18n.tr("Country") }
                                                C.Dropdown { Layout.fillWidth: true; popupMaxHeight: 380; enabled: Niche.mode === 0; opacity: enabled ? 1 : 0.5; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.regionOptions; currentIndex: Niche.regionIndex; onActivated: Niche.regionIndex = currentIndex }
                                            }
                                        }

                                        // ── audience match: how hard Language / Country filter ──
                                        // They used to be hints YouTube was free to ignore. Now they
                                        // filter the pool for real, so the user needs (a) a dial for
                                        // how much evidence counts and (b) one sentence saying what
                                        // the current settings will actually do.
                                        AudienceCard {
                                            Layout.fillWidth: true
                                            visible: Niche.mode === 0
                                        }

                                        ToggleCard {
                                            icon: "autorenew"
                                            label: I18n.tr("Ignore cache")
                                            hint: I18n.tr("Always fetch fresh results")
                                            on: Niche.forceRefresh
                                            onFlipped: (v) => Niche.setForceRefresh(v)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── the run, while it runs ──
                C.LoadingPanel {
                    Layout.fillWidth: true
                    visible: Niche.isRunning
                    pct: Niche.pct > 0 ? Niche.pct : -1
                    title: Niche.viralActive
                           ? I18n.tr("Reading what's viral · {t}").replace("{t}", Niche.viralTitle)
                           : I18n.tr("Searching YouTube for “{q}”").replace("{q}", Niche.query)
                    query: Niche.viralActive ? Niche.viralTitle : Niche.query
                    found: Niche.foundCount
                    detail: Niche.statusText
                    stages: Niche.stages
                    counts: Niche.liveCounts
                    note: Niche.viralActive
                          ? I18n.tr("This radar costs about {c} — it is cached for an hour.").replace("{c}", Niche.viralCost)
                          : Niche.quotaText !== ""
                          ? I18n.tr("This run costs about {c} — results are cached, so reopening this search later is free.")
                            .replace("{c}", Niche.quotaText)
                          : ""
                    onStopRequested: Niche.stopSearch()
                }

                // ── skeleton grid, while it runs (v3.39.1) ──
                // The result cards' own silhouette with one light sweep rolling
                // across them, so the page already looks like the answer it is
                // waiting for. Same column math as the real grid below, so the
                // swap to real cards does not reflow.
                C.GlassPanel {
                    id: skeletonPanel
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    visible: opacity > 0
                    opacity: Niche.isRunning ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                    implicitHeight: Niche.isRunning ? skGrid.implicitHeight + Tokens.space5 * 2 : 0

                    GridLayout {
                        id: skGrid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space5
                        columnSpacing: Tokens.space4
                        rowSpacing: Tokens.space4

                        readonly property real availW: content.width - Tokens.space5 * 2
                        columns: Math.max(1, Math.min(6, Math.floor((availW + columnSpacing) / (330 + columnSpacing))))
                        readonly property real cardW: (availW - columnSpacing * (columns - 1)) / columns

                        Repeater {
                            // two rows' worth: enough to read as "a grid is coming"
                            model: Niche.isRunning ? Math.max(4, Math.min(12, skGrid.columns * 2)) : 0
                            C.VideoCardSkeleton {
                                cardWidth: skGrid.cardW
                                Layout.preferredWidth: skGrid.cardW
                                Layout.alignment: Qt.AlignTop
                                running: Niche.isRunning
                                // diagonal wave: column + row offset
                                delay: ((index % skGrid.columns) + Math.floor(index / skGrid.columns)) * 90
                                opacity: 0
                                NumberAnimation on opacity {
                                    from: 0; to: 1
                                    duration: Tokens.durSlow
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }

                // ═══════════════ 3 · SCOREBOARD ═══════════════
                // The multiplier is the number this page exists for, so it gets
                // the lit, wider cell; the other three sit quieter beside it.
                C.GlassPanel {
                    Layout.fillWidth: true
                    visible: !Niche.isRunning && Niche.hasResults
                    radius: Tokens.radiusXl
                    implicitHeight: board.implicitHeight + Tokens.space2 * 2

                    GridLayout {
                        id: board
                        anchors.fill: parent
                        anchors.margins: Tokens.space2
                        columns: page._narrow ? 2 : 4
                        columnSpacing: 0
                        rowSpacing: 0
                        Repeater {
                            model: [
                                { l: I18n.tr("Best Multiplier"), v: Niche.metricBest,    icon: "trending_up", hero: true  },
                                { l: I18n.tr("Matches"),         v: Niche.metricMatches, icon: "data_array",  hero: false },
                                { l: I18n.tr("Hidden Gems"),     v: Niche.metricGems,    icon: "diamond",     hero: false },
                                { l: I18n.tr("Total Views"),     v: Niche.metricViews,   icon: "visibility",  hero: false }
                            ]
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredWidth: modelData.hero && !page._narrow ? 1.4 : 1
                                implicitHeight: cellCol.implicitHeight + Tokens.space4 * 2

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.radiusLg
                                    visible: modelData.hero
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.12) }
                                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.03) }
                                    }
                                    border.width: 1
                                    border.color: U.withAlpha(Theme.primary, 0.32)
                                }
                                Rectangle {
                                    visible: index > 1 && !(page._narrow && index === 2)
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 1; height: parent.height * 0.5
                                    color: Theme.border
                                }

                                ColumnLayout {
                                    id: cellCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.space5
                                    anchors.rightMargin: Tokens.space5
                                    spacing: Tokens.space1
                                    Row {
                                        spacing: Tokens.space2
                                        C.IconGlyph {
                                            name: modelData.icon; size: 14
                                            fill: modelData.hero
                                            glyphColor: modelData.hero ? Theme.primary : Theme.on_surface_var
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        C.AppText {
                                            text: modelData.l
                                            weight: Tokens.weightDemiBold
                                            font.pixelSize: Tokens.fontCaption
                                            color: modelData.hero ? Theme.primary : Theme.on_surface_var
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    C.AppText {
                                        text: modelData.v
                                        mono: true
                                        weight: Tokens.weightExtraBold
                                        font.pixelSize: modelData.hero ? 46 : 30
                                        font.letterSpacing: -0.5
                                        color: modelData.hero ? Theme.primary : Theme.text_strong
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        LayoutMirroring.enabled: false
                                        horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                    }
                                    // v3.39: each number gets its context, from the same rows
                                    C.AppText {
                                        Layout.fillWidth: true
                                        text: index === 0 ? (Niche.metricBestChannel !== "" ? Niche.metricBestChannel : "")
                                            : index === 1 ? I18n.tr("of {n} fetched").replace("{n}", Niche.metricPool)
                                            : index === 2 ? I18n.tr("{p}% of matches").replace("{p}", Math.round(Niche.metricGemFrac * 100))
                                            : I18n.tr("avg {v} per video").replace("{v}", Niche.metricAvgViews)
                                        font.pixelSize: Tokens.fontCaption
                                        color: modelData.hero ? U.withAlpha(Theme.primary, 0.85) : Theme.outline
                                        elide: Text.ElideRight
                                        visible: text !== ""
                                    }
                                    // hero: multiplier distribution (log scale) · others: share meter
                                    Row {
                                        visible: modelData.hero && Niche.metricSpark.length > 0
                                        spacing: 3
                                        LayoutMirroring.enabled: false
                                        Repeater {
                                            model: modelData.hero ? Niche.metricSpark : []
                                            Rectangle {
                                                required property var modelData
                                                width: 7; radius: 2
                                                height: 3 + 22 * modelData
                                                anchors.bottom: parent ? parent.bottom : undefined
                                                color: U.withAlpha(Theme.primary, 0.25 + 0.75 * modelData)
                                            }
                                        }
                                    }
                                    Rectangle {
                                        visible: index === 1 || index === 2
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        implicitHeight: 4; radius: 2
                                        color: U.withAlpha(Theme.outline, 0.16)
                                        Rectangle {
                                            height: parent.height; radius: 2
                                            width: parent.width * Math.max(0, Math.min(1, index === 1 ? Niche.metricMatchFrac : Niche.metricGemFrac))
                                            color: Theme.primary
                                            Behavior on width { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ═══════════════ 4 · RESULTS ═══════════════
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    visible: !Niche.isRunning
                    implicitHeight: resCol.implicitHeight + Tokens.space5 * 2

                    ColumnLayout {
                        id: resCol
                        anchors.fill: parent
                        anchors.margins: Tokens.space5
                        spacing: Tokens.space4

                        // Viral Radar header — only while the pool is a radar
                        C.ViralRadarBar {
                            Layout.fillWidth: true
                            visible: Niche.viralActive || Niche.viralSetupOpen
                            motion: page._motion
                        }

                        // results toolbar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2

                            C.SlideSegment {
                                Layout.alignment: Qt.AlignVCenter
                                solid: false
                                cellHeight: 34
                                model: [ { label: I18n.tr("Videos"),   icon: "smart_display" },
                                         { label: I18n.tr("Channels"), icon: "user" } ]
                                currentIndex: Niche.channelsView ? 1 : 0
                                onActivated: (i) => { Niche.channelsView = (i === 1); Niche.applyFilters() }
                            }

                            // filter-by-word field
                            Rectangle {
                                Layout.preferredWidth: Math.min(300, Math.max(180, content.width * 0.2))
                                Layout.alignment: Qt.AlignVCenter
                                implicitHeight: 40
                                radius: Tokens.radiusMd
                                color: Theme.input_bg
                                border.width: 1
                                border.color: wordInput.activeFocus ? Theme.primary : Theme.border
                                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.space3
                                    anchors.rightMargin: Tokens.space1
                                    spacing: Tokens.space2
                                    C.IconGlyph {
                                        name: "filter_list"; size: 15
                                        glyphColor: wordInput.activeFocus ? Theme.primary : Theme.outline
                                    }
                                    TextField {
                                        id: wordInput
                                        // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                                        T.ContextMenu.menu: C.EditMenu { editor: wordInput }
                                        selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                        selectedTextColor: Theme.text_strong
                                        Layout.fillWidth: true
                                        placeholderText: I18n.tr("Filter by word … (-word excludes)")
                                        placeholderTextColor: Theme.outline
                                        color: Theme.on_surface
                                        font.family: Fonts.body
                                        font.pixelSize: Tokens.fontBody
                                        selectByMouse: true
                                        background: null
                                        leftPadding: 0; rightPadding: 0
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: Niche.quickFilter
                                        onTextChanged: { if (Niche.quickFilter !== text) { Niche.quickFilter = text; filterTimer.restart() } }
                                        Keys.onEscapePressed: text = ""
                                    }
                                    C.IconButton {
                                        visible: wordInput.text !== ""
                                        iconName: "close"
                                        implicitWidth: 28; implicitHeight: 28
                                        glyphSize: 13
                                        onClicked: wordInput.text = ""
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Cards per row — Auto or a pinned 2/3/4. Shared
                            // with the Search Archive grid via App.gridColumns.
                            C.GridDensityPicker {
                                Layout.alignment: Qt.AlignVCenter
                                visible: Niche.hasResults
                            }

                            C.AppText {
                                text: Niche.cacheLabel
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                                Layout.alignment: Qt.AlignVCenter
                            }
                            // back to the radar after a keyword search
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "trending_up"
                                text: I18n.tr("Viral now")
                                visible: !Niche.viralActive && !Niche.viralSetupOpen
                                implicitHeight: 40
                                onClicked: Niche.openViralSetup()
                            }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "inventory_2"
                                text: I18n.tr("Archive results")
                                // the radar bar carries its own "Save to Archive"
                                visible: Niche.hasResults && !Niche.viralActive
                                implicitHeight: 40
                                onClicked: Niche.archiveResults()
                            }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "download"
                                text: I18n.tr("Export")
                                visible: Niche.hasResults
                                implicitHeight: 40
                                onClicked: exportDialog.open()
                            }
                            // The set-level read — filled, last, the one that
                            // answers "so what?". No API call, no quota.
                            C.PrimaryButton {
                                iconName: "nav_insights"
                                text: I18n.tr("Analyze these results")
                                visible: Niche.hasResults
                                implicitHeight: 40
                                onClicked: Niche.analyzeResults()
                            }
                        }

                        // empty state — two different "nothing here"s, told apart
                        Item {
                            id: emptyState
                            Layout.fillWidth: true
                            visible: !Niche.hasResults
                            readonly property bool filteredOut: Niche.activeFilterCount > 0 && Niche.statusText !== ""
                            implicitHeight: emptyCol.implicitHeight + Tokens.space7 * 2

                            Rectangle {
                                anchors.fill: parent
                                radius: Tokens.radiusLg
                                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.015 : 0.02)
                                border.width: 1
                                border.color: Theme.border
                            }

                            ColumnLayout {
                                id: emptyCol
                                anchors.centerIn: parent
                                width: Math.min(parent.width - Tokens.space6 * 2, 620)
                                spacing: Tokens.space3

                                Radar {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 120
                                    Layout.preferredHeight: 120
                                    motion: page._motion
                                    active: false
                                    hits: false
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space2
                                    horizontalAlignment: Text.AlignHCenter
                                    text: emptyState.filteredOut ? I18n.tr("No videos pass these filters")
                                          : Niche.viralSetupOpen ? I18n.tr("Your quota, your call")
                                          : (Niche.viralActive && Niche.viralLensIndex > 0)
                                          ? I18n.tr("No {l} videos in this radar").replace("{l}", Niche.viralLensOptions[Niche.viralLensIndex])
                                          : Niche.viralActive ? I18n.tr("Nothing viral in this window")
                                          : I18n.tr("Nothing on the radar yet")
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Tokens.fontTitle
                                    color: Theme.text_strong
                                    wrapMode: Text.Wrap
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: emptyState.filteredOut
                                          ? I18n.tr("Nothing passes these cuts. Loosen a pill above or clear the filters to widen the net.")
                                          : Niche.viralSetupOpen
                                          ? I18n.tr("Pick a market, a category and a window above. Nothing is fetched until you press Find, and the button shows what it costs.")
                                          : (Niche.viralActive && Niche.viralLensIndex > 0)
                                          ? I18n.tr("Switch the lens back to All, or widen the window to pull in more.")
                                          : Niche.viralActive
                                          ? I18n.tr("The chart has nothing this fresh. Widen the window to 7d, or switch the source to Breakouts.")
                                          : Niche.viralNeedsKey
                                          ? I18n.tr("Type a niche in the bar above. Add a YouTube API key in Settings to open on what's viral right now.")
                                          : I18n.tr("Type a niche in the bar above, or see what's viral on YouTube right now.")
                                    color: Theme.on_surface_var
                                    wrapMode: Text.Wrap
                                }

                                C.PrimaryButton {
                                    visible: emptyState.filteredOut
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: Tokens.space2
                                    iconName: "filter_alt"
                                    text: I18n.tr("Clear filters")
                                    onClicked: Niche.clearAllFilters()
                                }
                                C.PrimaryButton {
                                    visible: !emptyState.filteredOut && !Niche.viralActive && !Niche.viralSetupOpen && !Niche.viralNeedsKey
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: Tokens.space2
                                    iconName: "trending_up"
                                    text: I18n.tr("Show what's viral now")
                                    onClicked: Niche.openViralSetup()
                                }

                                // the path, in order — numbered because it IS a sequence
                                Row {
                                    visible: !emptyState.filteredOut && !Niche.viralActive && !Niche.viralSetupOpen
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: Tokens.space3
                                    spacing: Tokens.space2
                                    Repeater {
                                        model: [ { n: "1", t: I18n.tr("Type a niche") },
                                                 { n: "2", t: I18n.tr("Tune the signal") },
                                                 { n: "3", t: I18n.tr("Open the outliers") } ]
                                        Row {
                                            spacing: Tokens.space2
                                            Rectangle {
                                                radius: Tokens.radiusPill
                                                color: Theme.surface_low
                                                border.width: 1
                                                border.color: Theme.border
                                                width: stepRow.implicitWidth + Tokens.space3 * 2
                                                height: 34
                                                Row {
                                                    id: stepRow
                                                    anchors.centerIn: parent
                                                    spacing: Tokens.space2
                                                    Rectangle {
                                                        width: 20; height: 20; radius: 10
                                                        color: U.withAlpha(Theme.primary, 0.14)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        C.AppText {
                                                            anchors.centerIn: parent
                                                            text: modelData.n
                                                            mono: true
                                                            weight: Tokens.weightExtraBold
                                                            font.pixelSize: Tokens.fontMicro
                                                            color: Theme.primary
                                                        }
                                                    }
                                                    C.AppText {
                                                        text: modelData.t
                                                        weight: Tokens.weightDemiBold
                                                        font.pixelSize: Tokens.fontCaption
                                                        color: Theme.on_surface
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                visible: index < 2
                                                width: 16; height: 1
                                                color: Theme.border_med
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // card grid
                        //
                        // NOTE: column count / card width are derived from
                        // `content.width`, NOT the grid's own width — reading
                        // grid.width here is a binding loop Qt resolves to 0.
                        GridLayout {
                            id: grid
                            objectName: "tour_resultGrid"
                            Layout.fillWidth: true
                            visible: Niche.hasResults
                            columnSpacing: Tokens.space4
                            rowSpacing: Tokens.space4

                            readonly property real availW: content.width - Tokens.space5 * 2
                            // 330: the Signal card's floor (same as Search
                            // Archive, so both grids break at the same widths).
                            // Frozen during the rail slide.
                            property int _frozenCols: 0
                            property real _frozenW: 0
                            readonly property int _autoCols:
                                     Math.max(1, Math.min(6, Math.floor((availW + columnSpacing) / (330 + columnSpacing))))
                            // A pinned 2/3/4 is an intent, not a promise: below
                            // 256 px the card's action row stops fitting, so a
                            // narrow window falls back to the columns that do.
                            readonly property int _fitCols:
                                     Math.max(1, Math.min(6, Math.floor((availW + columnSpacing) / (256 + columnSpacing))))
                            readonly property int _liveCols:
                                     App.gridColumns > 0
                                     ? Math.min(App.gridColumns, _fitCols)
                                     : _autoCols
                            columns: (App.railAnimating && _frozenCols > 0) ? _frozenCols : _liveCols
                            readonly property real cardW:
                                (App.railAnimating && _frozenW > 0) ? _frozenW
                                : (availW - columnSpacing * (columns - 1)) / columns
                            Connections {
                                target: App
                                function onRailAnimatingChanged() {
                                    if (App.railAnimating) {
                                        grid._frozenCols = grid.columns
                                        grid._frozenW = grid.cardW
                                    }
                                }
                            }

                            // ── smooth first paint ──
                            // Cards used to be created in one go the moment the
                            // results landed (a long frame) and then each faded
                            // in on its own as its thumbnail arrived — a
                            // trickle of cards. Now:
                            //  1. slots are created a few per frame, while the
                            //     grid is still invisible, and are never torn
                            //     down again (a shorter page just hides the
                            //     spare ones);
                            //  2. the grid appears ONCE, whole, when the first
                            //     two rows have their pictures (900 ms at most).
                            property int _slots: 0
                            property bool revealed: false
                            readonly property string _sig: {
                                const r = page._nicheRows
                                if (!r.length) return "0"
                                const f = r[0] || ({})
                                return r.length + ":" + (f.archiveKey || f.videoId || f.thumbId || "")
                            }
                            function _firstRowsReady() {
                                const n = Math.min(page._nicheRows.length, columns * 2)
                                for (let i = 0; i < n; ++i) {
                                    const c = nrep.itemAt(i)
                                    if (!c || !c.thumbReady) return false
                                }
                                return true
                            }
                            function _tryReveal() {
                                if (revealed) return
                                if (page._nicheRows.length === 0) return
                                if (_firstRowsReady()) { revealed = true; revealTimer.stop() }
                            }
                            function _rearm() {
                                revealed = false
                                if (page._nicheRows.length === 0) { revealTimer.stop(); return }
                                revealTimer.restart()
                                Qt.callLater(grid._tryReveal)
                            }
                            on_SigChanged: _rearm()
                            Component.onCompleted: _rearm()
                            Timer {
                                id: revealTimer
                                interval: 900
                                onTriggered: grid.revealed = true
                            }
                            Timer {
                                interval: 1
                                repeat: true
                                running: grid._slots < page._nicheRows.length
                                onTriggered: {
                                    grid._slots = Math.min(page._nicheRows.length, grid._slots + 6)
                                    Qt.callLater(grid._tryReveal)
                                }
                            }
                            // instant hide, soft show
                            opacity: revealed ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: grid.revealed ? 180 : 0; easing.type: Easing.OutCubic }
                            }

                            Repeater {
                                id: nrep
                                // v3.44 perf: integer model + reused cards (see
                                // ArchivePage) — a page flip re-binds 24 cards
                                // instead of destroying and rebuilding them.
                                // v3.57: the count only ever GROWS (grid._slots),
                                // so a shorter page or a smaller search never
                                // destroys cards that the next one rebuilds.
                                model: grid._slots
                                // v15: the Search Archive "Signal" card, so a
                                // result looks the same here and once it is
                                // saved.
                                C.ArchiveVideoCard {
                                    id: ncard
                                    row: page._nicheRows[index] || ({})
                                    target: Niche
                                    cardWidth: grid.cardW
                                    // v3.52: no hover effects while scrolling
                                    // — see ArchiveVideoCard.scrollIdle.
                                    scrollIdle: !scroller.gliding
                                    // v3.57: no per-card entrance — the whole
                                    // grid fades in once (grid.revealed).
                                    readonly property bool thumbReady: ncard._thumbnailAnnounced
                                    visible: index < page._nicheRows.length
                                    onThumbnailReady: grid._tryReveal()
                                    // Painted only within one card-row of the
                                    // viewport (same rule as the Search Archive
                                    // grid): a card far off-screen costs a
                                    // layered thumbnail + mask + effect pass for
                                    // nothing. Opacity, not `visible`, keeps the
                                    // layout geometry. y/height are read so the
                                    // binding re-runs when the grid reflows.
                                    opacity: {
                                        const fl = scroller.contentItem
                                        const vh = scroller.height
                                        if (!fl || vh <= 0) return 1
                                        const pad = ncard.height + 320
                                        const _dep = ncard.y + grid.y + grid.height
                                        const viewY = fl.contentY
                                        const top = ncard.mapToItem(fl.contentItem, 0, 0).y
                                        return (top + ncard.height > viewY - pad
                                                && top < viewY + vh + pad) ? 1 : 0
                                    }
                                    Layout.preferredWidth: grid.cardW
                                    Layout.fillHeight: true
                                    Layout.alignment: Qt.AlignTop
                                    onDownloadRequested: (vid, title, thumb) =>
                                        qualityPicker.openFor(vid, title, thumb)
                                    onThumbDownloadRequested: (thumb, title, isShort) =>
                                        page.saveThumb(thumb, title, isShort)
                                }
                            }
                        }

                        // ── pager ── only one page of cards exists at a time
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space2
                            spacing: Tokens.space2
                            visible: Niche.hasResults && Niche.pageCount > 1

                            Item { Layout.fillWidth: true }
                            C.Pager {
                                pageIndex: Niche.pageIndex
                                pageCount: Niche.pageCount
                                Layout.alignment: Qt.AlignVCenter
                                onRequested: (i) => { Niche.gotoPage(i); scroller.toTop() }
                            }
                            Item { Layout.fillWidth: true }
                            C.AppText {
                                text: Niche.pageLabel
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportDialog
        title: I18n.tr("Export results")
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV (*.csv)", "Excel (*.xlsx)", "JSON Lines (*.jsonl)"]
        onAccepted: Niche.exportResults(selectedFile.toString())
    }

    C.QualityPicker { id: qualityPicker }

    // Asked once, the first time a thumbnail is downloaded. The chosen folder
    // is remembered in config (shared with Search Archive).
    FolderDialog {
        id: thumbFolderDialog
        title: I18n.tr("Choose where to save thumbnails")
        onAccepted: {
            Niche.setThumbFolder(selectedFolder.toString())
            if (page._pendingThumbId !== "") {
                Niche.downloadThumb(page._pendingThumbId, page._pendingThumbTitle,
                                    page._pendingThumbShort)
                page._pendingThumbId = ""
                page._pendingThumbTitle = ""
                page._pendingThumbShort = false
            }
        }
    }

    C.Toast { id: toast; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 80 }
}
