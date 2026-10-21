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
//   * Tuner — the three signature cuts as three equal "tracks". Each track
//     has a big mono read-out ("≤ 100K") above a sliding segmented control
//     with an explicit "Any" stop, so clearing a cut is a visible choice
//     instead of the old hidden "click the active pill again".
//   * Recipes — the presets as one row of quiet chips under the tracks.
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
    Component.onCompleted: Niche.refreshDownloaded()

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

    readonly property var _subsOpts:  [ { t: I18n.tr("Any"), v: "" }, { t: "10K", v: "10K" },
                                        { t: "100K", v: "100K" },     { t: "1M", v: "1M" } ]
    readonly property var _viewsOpts: [ { t: I18n.tr("Any"), v: "" }, { t: "10K", v: "10K" },
                                        { t: "100K", v: "100K" },     { t: "1M", v: "1M" },
                                        { t: "10M", v: "10M" } ]
    readonly property var _multOpts:  [ { t: I18n.tr("Any"), v: "" }, { t: "10×", v: "10" },
                                        { t: "50×", v: "50" },        { t: "100×", v: "100" } ]

    // The three cuts the tracks show are not repeated as chips; only the
    // other active options (window, sort, format, depth…) are.
    readonly property var _trackKeys: ["subs_min", "subs_max", "views_min", "views_max", "mult_min"]
    readonly property int _extraFilters: {
        let n = 0
        const a = Niche.activeFilters || []
        for (let i = 0; i < a.length; i++)
            if (_trackKeys.indexOf(a[i].key) < 0) n++
        return n
    }

    // ═══════════════════════ inline building blocks ═══════════════════════

    // The radar scope. Four rings, a crosshair, a sweep that trails off over
    // ~75°, and a handful of blips — one accent blip for "the outlier". It
    // sweeps slowly at rest and hard while a search runs; with ambient motion
    // off it is a still scope. One Canvas painted once, then only rotated.
    component Radar: Item {
        id: rd
        property bool active: false
        property bool motion: true
        property bool hits: false
        implicitWidth: 196
        implicitHeight: 196
        readonly property real _r: Math.min(width, height) / 2

        Rectangle {
            anchors.centerIn: parent
            width: rd._r * 2; height: width; radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.07) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }
        Repeater {
            model: 4
            Rectangle {
                anchors.centerIn: parent
                width: rd._r * 2 * (0.25 + index * 0.25); height: width; radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: U.withAlpha(Theme.primary, index === 3 ? 0.32 : 0.13)
            }
        }
        // outer tick ring — 24 ticks, every sixth one long
        Repeater {
            model: 24
            Rectangle {
                readonly property bool major: index % 6 === 0
                width: 1
                height: major ? 7 : 3
                color: U.withAlpha(Theme.primary, major ? 0.55 : 0.25)
                x: rd.width / 2 - width / 2
                y: rd.height / 2 - rd._r - 6
                transform: Rotation {
                    origin.x: 0.5
                    origin.y: rd._r + 6
                    angle: index * 15
                }
            }
        }
        Rectangle { anchors.centerIn: parent; width: rd._r * 2; height: 1; color: U.withAlpha(Theme.primary, 0.12) }
        Rectangle { anchors.centerIn: parent; width: 1; height: rd._r * 2; color: U.withAlpha(Theme.primary, 0.12) }

        Canvas {
            id: sweepCv
            anchors.fill: parent
            opacity: rd.active ? 1.0 : 0.75
            Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
            property color tint: Theme.primary
            onTintChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2
                var r = Math.min(width, height) / 2 - 1
                var R = Math.round(tint.r * 255), G = Math.round(tint.g * 255), B = Math.round(tint.b * 255)
                var steps = 30
                var span = Math.PI * 0.42
                for (var k = 0; k < steps; k++) {
                    var a1 = -Math.PI / 2 - k * span / steps
                    var a0 = -Math.PI / 2 - (k + 1) * span / steps
                    ctx.beginPath()
                    ctx.moveTo(cx, cy)
                    ctx.arc(cx, cy, r, a0, a1, false)
                    ctx.closePath()
                    ctx.fillStyle = "rgba(" + R + "," + G + "," + B + "," + (0.30 * (1 - k / steps)).toFixed(3) + ")"
                    ctx.fill()
                }
                ctx.strokeStyle = "rgba(" + R + "," + G + "," + B + ",0.95)"
                ctx.lineWidth = 1.5
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx, cy - r)
                ctx.stroke()
            }
            NumberAnimation on rotation {
                running: rd.motion && rd.visible && (rd.active || Tokens.appActive)
                loops: Animation.Infinite
                from: 0; to: 360
                duration: rd.active ? 1700 : 5200
            }
        }

        // blips: polar (angle°, radius 0..1, size, hero?)
        Repeater {
            model: [
                { a: 38,  d: 0.62, s: 12, hero: true },
                { a: 152, d: 0.40, s: 6,  hero: false },
                { a: 228, d: 0.78, s: 7,  hero: false },
                { a: 300, d: 0.30, s: 5,  hero: false },
                { a: 95,  d: 0.86, s: 5,  hero: false }
            ]
            Item {
                readonly property real _rad: (modelData.a - 90) * Math.PI / 180
                x: rd.width / 2 + Math.cos(_rad) * rd._r * modelData.d - width / 2
                y: rd.height / 2 + Math.sin(_rad) * rd._r * modelData.d - height / 2
                width: modelData.s * 3; height: width
                opacity: (rd.hits || rd.active || modelData.hero) ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow } }
                Rectangle {
                    id: ping
                    anchors.centerIn: parent
                    width: modelData.s; height: width; radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: modelData.hero ? Theme.primary : Theme.on_surface_var
                    opacity: 0
                    SequentialAnimation {
                        running: rd.motion && rd.visible && (rd.active || Tokens.appActive)
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 520 }
                        ParallelAnimation {
                            NumberAnimation { target: ping; property: "width"; from: modelData.s; to: modelData.s * 3; duration: 1400; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ping; property: "opacity"; from: 0.8; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                        }
                        PauseAnimation { duration: 1200 + (4 - index) * 300 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: modelData.s; height: width; radius: width / 2
                    color: modelData.hero ? Theme.primary : U.withAlpha(Theme.on_surface_var, 0.85)
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: Theme.primary
        }
    }

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

    // One of the three outlier cuts: caption, a big read-out of the current
    // value, and a sliding segmented control with an explicit "Any" stop.
    component SignalTrack: Rectangle {
        id: trk
        property string caption: ""
        property string icon: ""
        property string unit: ""
        property string readout: ""
        property var options: []
        property int index: 0
        signal picked(string v)
        readonly property bool on: readout !== ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        radius: Tokens.radiusLg
        color: trk.on ? U.mix(Theme.surface_low, Theme.primary, Theme.isDark ? 0.07 : 0.04)
                      : Theme.surface_low
        border.width: 1
        border.color: trk.on ? U.withAlpha(Theme.primary, 0.38) : Theme.border
        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        implicitHeight: trkCol.implicitHeight + Tokens.space4 * 2

        // a short lit bar on the leading top edge when the cut is on
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: Tokens.space4
            height: 2
            radius: 1
            width: trk.on ? 44 : 0
            color: Theme.primary
            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }

        ColumnLayout {
            id: trkCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.space4
            spacing: Tokens.space3

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                C.IconGlyph {
                    name: trk.icon; size: 14
                    fill: trk.on
                    glyphColor: trk.on ? Theme.primary : Theme.on_surface_var
                    Layout.alignment: Qt.AlignVCenter
                }
                C.AppText {
                    text: trk.caption
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter
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

            Row {
                spacing: Tokens.space2
                C.AppText {
                    id: readoutLbl
                    text: trk.on ? trk.readout : I18n.tr("Any")
                    mono: trk.on
                    weight: Tokens.weightExtraBold
                    font.pixelSize: 28
                    font.letterSpacing: trk.on ? -0.5 : 0
                    color: trk.on ? Theme.text_strong : Theme.outline
                    LayoutMirroring.enabled: false
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                }
                C.AppText {
                    visible: trk.on && trk.unit !== ""
                    text: trk.unit
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    anchors.baseline: readoutLbl.baseline
                }
            }

            C.SlideSegment {
                Layout.fillWidth: true
                equal: true
                mono: true
                cellHeight: 30
                fontSize: Tokens.fontCaption
                model: trk.options.map(function (o) { return o.t })
                currentIndex: trk.index
                onActivated: (i) => trk.picked(trk.options[i].v)
            }
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

    // Language / Country explainer + precision dial. Everything it says comes
    // from the VM (audienceSummary / audienceWarning), so the sentence and the
    // filter can never disagree.
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
                        name: "translate"; size: 16
                        fill: Niche.audienceActive
                        glyphColor: Niche.audienceActive ? Theme.primary : Theme.on_surface_var
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    C.AppText {
                        text: I18n.tr("Audience match")
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

            C.SlideSegment {
                    Layout.fillWidth: true
                    equal: true
                    solid: false
                    cellHeight: 30
                    fontSize: Tokens.fontCaption
                    enabledCells: Niche.audienceActive
                    opacity: Niche.audienceActive ? 1 : 0.55
                    model: Niche.precisionOptions
                    currentIndex: Niche.precisionIndex
                    onActivated: (i) => Niche.precisionIndex = i
            }

            C.AppText {
                Layout.fillWidth: true
                text: Niche.audienceSummary
                font.pixelSize: Tokens.fontCaption
                color: Niche.audienceActive ? Theme.on_surface : Theme.outline
                wrapMode: Text.Wrap
                lineHeight: 1.15
            }

            RowLayout {
                Layout.fillWidth: true
                visible: Niche.audienceWarning !== ""
                spacing: Tokens.space2
                C.IconGlyph {
                    name: "warning"; size: 14; fill: true
                    glyphColor: Theme.warn
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 1
                }
                C.AppText {
                    Layout.fillWidth: true
                    text: Niche.audienceWarning
                    font.pixelSize: Tokens.fontCaption
                    weight: Tokens.weightDemiBold
                    color: Theme.warn
                    wrapMode: Text.Wrap
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
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

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
                                    Layout.preferredWidth: 188
                                    Layout.preferredHeight: 188
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
                                        icon: "trending_up"
                                        label: I18n.tr("Multiplier")
                                        value: page._multCut
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
                                size: 34
                                solid: Niche.activeFilterCount > 0
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
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

                        // the three tracks
                        GridLayout {
                            Layout.fillWidth: true
                            columns: page._narrow ? 1 : (Niche.mode === 1 ? 2 : 3)
                            columnSpacing: Tokens.space3
                            rowSpacing: Tokens.space3

                            SignalTrack {
                                // Single Channel Scan has no subscriber cut: it
                                // is about the videos of the one channel picked.
                                visible: Niche.mode === 0
                                caption: I18n.tr("Channel size")
                                icon: "user"
                                unit: I18n.tr("subscribers")
                                readout: page._subsCut
                                options: page._subsOpts
                                index: page._optIndex(page._subsOpts, Niche.subsMax, Niche.subsMin)
                                onPicked: (v) => { Niche.subsMin = ""; Niche.subsMax = v; filterTimer.restart() }
                            }
                            SignalTrack {
                                caption: I18n.tr("Reach")
                                icon: "visibility"
                                unit: I18n.tr("views")
                                readout: page._viewsCut
                                options: page._viewsOpts
                                index: page._optIndex(page._viewsOpts, Niche.viewsMin, Niche.viewsMax)
                                onPicked: (v) => { Niche.viewsMax = ""; Niche.viewsMin = v; filterTimer.restart() }
                            }
                            SignalTrack {
                                caption: I18n.tr("Views ÷ subscribers")
                                icon: "trending_up"
                                unit: I18n.tr("multiplier")
                                readout: page._multCut
                                options: page._multOpts
                                index: page._optIndex(page._multOpts, Niche.multMin, "")
                                onPicked: (v) => { Niche.multMin = v; filterTimer.restart() }
                            }
                        }

                        // recipes (ready-made combinations) + drawer trigger
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space3

                            Flow {
                                Layout.fillWidth: true
                                spacing: Tokens.space2
                                C.AppText {
                                    text: I18n.tr("Recipes")
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    height: 34
                                    verticalAlignment: Text.AlignVCenter
                                    rightPadding: Tokens.space1
                                }
                                Repeater {
                                    model: Niche.presetOptions
                                    AbstractButton {
                                        id: presetBtn
                                        // the last preset is "Clear filters" —
                                        // that lives in the header as Reset all
                                        visible: index < 4
                                        height: 34
                                        implicitWidth: presetRow.implicitWidth + Tokens.space4 * 2
                                        hoverEnabled: true
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        onClicked: Niche.applyPreset(index)
                                        scale: presetBtn.pressed ? Tokens.pressScale : 1.0
                                        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                                        background: Rectangle {
                                            radius: Tokens.radiusPill
                                            // Opaque fills only — a translucent
                                            // hover passes through mid-grey.
                                            color: presetBtn.hovered ? U.mix(Theme.surface, Theme.primary, 0.10) : Theme.surface
                                            border.width: 1
                                            border.color: presetBtn.hovered ? U.withAlpha(Theme.primary, 0.40) : Theme.border
                                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                                        }
                                        contentItem: Item {
                                            implicitWidth: presetRow.implicitWidth
                                            implicitHeight: presetRow.implicitHeight
                                            Row {
                                                id: presetRow
                                                anchors.centerIn: parent
                                                spacing: Tokens.space2
                                                C.IconGlyph {
                                                    name: ["user", "user", "diamond", "visibility"][index] || "tune"
                                                    size: 14
                                                    fill: presetBtn.hovered
                                                    glyphColor: Theme.primary
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                C.AppText {
                                                    text: modelData
                                                    weight: Tokens.weightDemiBold
                                                    font.pixelSize: Tokens.fontCaption
                                                    color: presetBtn.hovered ? Theme.text_strong : Theme.on_surface
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
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
                                            columns: page._narrow ? 1 : 2
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
                                        }

                                        ColumnLayout {
                                            spacing: Tokens.space2
                                            Layout.fillWidth: true
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
                                                text: I18n.tr("These ranges drive the search itself, not just the results it already fetched. If the first pass finds too few videos that fit, the app widens the search on its own - deeper time windows, more pages - and that spends more of today's search quota. Subscribers are ignored in Single Channel Scan.")
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
                                            }
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
                                                FieldCap { text: I18n.tr("Language") }
                                                C.Dropdown { Layout.fillWidth: true; popupMaxHeight: 380; borderColor: U.mix(Theme.border, Theme.outline, 0.45); model: Niche.langOptions; currentIndex: Niche.langIndex; onActivated: Niche.langIndex = currentIndex }
                                            }
                                            ColumnLayout {
                                                spacing: Tokens.space2; Layout.fillWidth: true; Layout.preferredWidth: 1
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
                                        }

                                        ToggleCard {
                                            visible: Niche.mode === 0
                                            icon: "biotech"
                                            label: I18n.tr("Deep scan")
                                            hint: I18n.tr("Slower, digs through more of each channel")
                                            on: Niche.deepScan
                                            onFlipped: (v) => Niche.deepScan = v
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
                    title: I18n.tr("Searching YouTube for “{q}”")
                           .replace("{q}", Niche.query)
                    query: Niche.query
                    found: Niche.foundCount
                    detail: Niche.statusText
                    stages: Niche.stages
                    counts: Niche.liveCounts
                    note: Niche.quotaText !== ""
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
                                        placeholderText: I18n.tr("Filter these results by word …")
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

                            // v16: the Auto/3/4/5 column picker is gone — the grid is always
                            // width-driven (Auto), so it adapts to every screen on its own.
                            C.AppText {
                                text: Niche.cacheLabel
                                mono: true
                                font.pixelSize: Tokens.fontCaption
                                color: Theme.outline
                                Layout.alignment: Qt.AlignVCenter
                            }
                            C.PrimaryButton {
                                variant: "ghost"
                                iconName: "inventory_2"
                                text: I18n.tr("Archive results")
                                visible: Niche.hasResults
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
                                    Layout.preferredWidth: 104
                                    Layout.preferredHeight: 104
                                    motion: page._motion
                                    active: false
                                    hits: false
                                }
                                C.AppText {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Tokens.space2
                                    horizontalAlignment: Text.AlignHCenter
                                    text: emptyState.filteredOut ? I18n.tr("No videos pass these filters")
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
                                          : I18n.tr("Type a niche in the bar above and the outliers will show up here.")
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

                                // the path, in order — numbered because it IS a sequence
                                Row {
                                    visible: !emptyState.filteredOut
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
                            // v16: always Auto (no pinned counts any more).
                            // Frozen during the rail slide.
                            property int _frozenCols: 0
                            property real _frozenW: 0
                            readonly property int _liveCols:
                                     Math.max(1, Math.min(6, Math.floor((availW + columnSpacing) / (330 + columnSpacing))))
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

                            Repeater {
                                // v3.44 perf: integer model + reused cards (see
                                // ArchivePage) — a page flip re-binds 24 cards
                                // instead of destroying and rebuilding them.
                                model: page._nicheRows.length
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
                                    // cards land in a quick stagger (first ~12
                                    // only) whenever a new video takes the slot.
                                    // Ambient motion off = no entrance.
                                    opacity: page._motion ? 0 : 1
                                    on_RowKeyChanged: if (page._motion) { ncard.opacity = 0; ncardIn.restart() }
                                    Component.onCompleted: if (page._motion) ncardIn.restart()
                                    SequentialAnimation {
                                        id: ncardIn
                                        PauseAnimation { duration: Math.min(index, 10) * 14 }
                                        NumberAnimation { target: ncard; property: "opacity"; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
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
