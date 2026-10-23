import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Shapes
import NicheScope
import "../components" as C
import "../Utils.js" as U

// Search Archive — v12 "Library" redesign.
//
// The permanent library of every Niche Finder search (one merge-mode section
// per keyword / channel). Reading any of it is local and free.
//
// MASTER  ─ open header on the page wash · the "library spectrum" (every
//           section's share of the archive as one segmented bar you can click)
//           · four headline numbers · command bar · section tiles, each with
//           a volume ring around its avatar and a run tally.
// DETAIL  ─ breadcrumb header with the section's spec sheet · one filter dock
//           (search · sort menu · favorites · ranges / published · format)
//           · removable active-filter pills · Signal cards in an always-auto
//           grid (the Auto/3/4/5 picker is gone — columns follow the width)
//           · a compact dock that floats in once the real one scrolls away
//           · ranges live in a side sheet with presets.
Item {
    id: page

    onVisibleChanged: if (visible) { Archive.reload(); Archive.refreshDownloaded() }
    Component.onCompleted: { Archive.reload(); Archive.refreshDownloaded() }

    property string _pendingThumbId: ""
    property string _pendingThumbTitle: ""
    property bool _pendingThumbShort: false

    function saveThumb(thumbId, title, isShort) {
        if ((thumbId || "") === "") return
        if (Archive.hasThumbFolder) {
            Archive.downloadThumb(thumbId, title, isShort || false)
        } else {
            page._pendingThumbId = thumbId
            page._pendingThumbTitle = title
            page._pendingThumbShort = isShort || false
            thumbFolderDialog.open()
        }
    }

    Connections {
        target: Archive
        function onToast(msg, kind) { toast.show(msg, kind) }
        // keep the detail search box in step when the VM resets it (opening
        // another section, Reset all) — never while the user is typing
        function onDetailChanged() {
            if (!Archive.isDetail) page._specSeen = -2
            if (!detailSearch.fieldFocused && detailSearch.text !== Archive.detailFilterText)
                detailSearch.text = Archive.detailFilterText
        }
        function onRowsChanged() {
            // v3.39.4: no count reset (the ready map is keyed by row, so a
            // stale page can never satisfy the new one) — just re-arm the cap.
            page._thumbGateOpen = false
            thumbGateCap.restart()
            // v3.44: skeletons only if the pictures are actually slow
            page._skeletonArmed = false
            skeletonArm.restart()
        }
    }

    // ═══════════════════════ page-level state ═══════════════════════
    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true

    // ── section-list pagination (v1.2) ──
    // The master grid used to render every section at once: a library of 30+
    // searches was one endless wall with no sense of where you were. Twelve per
    // page keeps a full 4-column page on a laptop screen and puts the count
    // somewhere visible. The slice is recomputed from Archive.groups, so search
    // and the Favorites tab page through their own filtered result.
    readonly property int _sectPerPage: 12
    property int _sectPage: 0
    readonly property int _sectTotal: (Archive.groups || []).length
    readonly property int _sectPages: Math.max(1, Math.ceil(page._sectTotal / page._sectPerPage))
    readonly property var _sectSlice: {
        var g = Archive.groups || []
        var start = page._sectPage * page._sectPerPage
        return g.slice(start, start + page._sectPerPage)
    }
    // "13–24" — the run on screen, 1-based like the pager.
    readonly property string _sectRange: {
        if (page._sectTotal === 0) return ""
        var a = page._sectPage * page._sectPerPage + 1
        var b = Math.min(page._sectTotal, a + page._sectPerPage - 1)
        return a === b ? String(a) : a + "\u2013" + b
    }
    readonly property string _sectLabel:
        page._sectPages > 1
        ? I18n.tr("{r} of {n}").replace("{r}", page._sectRange).replace("{n}", page._sectTotal)
        : I18n.tr("{n} shown").replace("{n}", page._sectTotal)
    function _sectGo(i) {
        var t = Math.max(0, Math.min(page._sectPages - 1, i))
        if (t === page._sectPage) return
        page._sectPage = t
        masterScroll.toTop()
    }
    // The list shrank under us (a section was deleted, the search narrowed):
    // never leave the reader on a page that no longer exists.
    Connections {
        target: Archive
        function onChanged() {          // `groups` notifies through `changed`
            if (page._sectPage > page._sectPages - 1)
                page._sectPage = page._sectPages - 1
        }
    }

    // ── reveal gate (v3.39.4) ──
    // v3.39.2 held the WHOLE page until every one of its ~24 thumbnails had
    // arrived, so one slow image (12s network timeout) kept the grid on
    // skeletons. Now:
    //   • only the first two rows (what is on screen) gate the reveal;
    //   • a hard cap (thumbGateCap) opens the gate regardless — late cards
    //     then fade their own picture in over their own ThumbSkeleton;
    //   • readiness is remembered per row, so going back to a page you have
    //     already seen reveals instantly.
    // v3.44 perf: the page's rows converted from the VM ONCE per change. Every
    // cell used to read Archive.rows itself, i.e. 24 full list conversions.
    readonly property var _rows: Archive.rows || []
    property var _readyMap: ({})
    property int _readyTick: 0
    property bool _thumbGateOpen: false
    function _rowKey(r) { return (r && (r.archiveKey || r.videoId || r.thumbId)) || "" }
    function _noteThumbReady(r) {
        var k = _rowKey(r)
        if (k === "" || _readyMap[k]) return
        _readyMap[k] = true
        _readyTick++
    }
    readonly property int _thumbExpected:
        Math.min(page._rows.length, Math.max(4, grid.columns * 2))
    readonly property int _thumbReadyCount: {
        page._readyTick
        var rs = page._rows
        var n = 0
        for (var i = 0; i < _thumbExpected; i++)
            if (_readyMap[_rowKey(rs[i])]) n++
        return n
    }
    readonly property bool _thumbLoading: Archive.isDetail && _thumbExpected > 0
                                          && !_thumbGateOpen
                                          && _thumbReadyCount < _thumbExpected
    Timer {
        id: thumbGateCap
        // long enough for cached / prefetched thumbs (they land in tens of
        // ms), short enough that a slow CDN never reads as "stuck".
        interval: 650
        onTriggered: page._thumbGateOpen = true
    }
    // v3.44 perf: the 24 skeletons (each a layer + MultiEffect + two infinite
    // animations) used to be BUILT on every page flip, even when the next
    // page's thumbnails were already prefetched and landed in ~30 ms. Now they
    // only come in if the pictures are still missing after this beat.
    property bool _skeletonArmed: false
    Timer {
        id: skeletonArm
        interval: 160
        onTriggered: page._skeletonArmed = true
    }
    property int _specSeen: -2
    readonly property int _heroSize: Math.round(Math.max(30, Math.min(50, masterCol.width / 30)))

    readonly property int _maxItems: {
        var gs = Archive.groups || []
        var m = 1
        for (var i = 0; i < gs.length; i++) m = Math.max(m, gs[i].itemCount || 0)
        return m
    }
    readonly property int _totalItems: {
        var gs = Archive.groups || []
        var t = 0
        for (var i = 0; i < gs.length; i++) t += (gs[i].itemCount || 0)
        return Math.max(1, t)
    }
    // spectrum segments: the 9 biggest sections + one "others" bucket
    readonly property var _spectrum: {
        var gs = (Archive.groups || []).slice()
        gs.sort(function(a, b) { return (b.itemCount || 0) - (a.itemCount || 0) })
        var out = []
        var rest = 0, restN = 0
        for (var i = 0; i < gs.length; i++) {
            if ((gs[i].itemCount || 0) <= 0) continue
            if (out.length < 9) out.push({ id: gs[i].id, title: gs[i].title, n: gs[i].itemCount, text: gs[i].itemCountText, other: false })
            else { rest += gs[i].itemCount; restN += 1 }
        }
        if (rest > 0) out.push({ id: -1, title: I18n.tr("{n} more sections").replace("{n}", restN), n: rest, text: String(rest), other: true })
        return out
    }
    readonly property var _detailGroup: {
        var gs = Archive.groups || []
        for (var i = 0; i < gs.length; i++)
            if (gs[i].id === Archive.detailId) return gs[i]
        return ({})
    }

    // ── detail filters: active pills + helpers ──
    readonly property int _tfLast: Math.max(0, (Archive.timeframeOptions || []).length - 1)
    readonly property var _range: Archive.detailRange || ({})
    readonly property string _format: page._range.format || "all"
    readonly property int _rangeCount: {
        var r = page._range, n = 0
        if ((r.subs_min || "") !== "" || (r.subs_max || "") !== "") n++
        if ((r.views_min || "") !== "" || (r.views_max || "") !== "") n++
        if ((r.sort_views || "") !== "") n++
        if ((r.sort_subs || "") !== "") n++
        return n
    }
    readonly property var _activeFilters: {
        var out = []
        var r = page._range
        if ((Archive.detailFilterText || "") !== "")
            out.push({ k: "text", icon: "search", label: "“" + Archive.detailFilterText + "”" })
        if (Archive.detailTimeframeIndex !== page._tfLast)
            out.push({ k: "tf", icon: "history", label: (Archive.timeframeOptions || [])[Archive.detailTimeframeIndex] || "" })
        if (Archive.detailFavOnly)
            out.push({ k: "fav", icon: "star", label: I18n.tr("Favorites only") })
        if (page._format !== "all")
            out.push({ k: "fmt", icon: page._format === "short" ? "fmt_short" : "fmt_long",
                       label: page._format === "short" ? I18n.tr("Shorts") : I18n.tr("Long-form") })
        if ((r.subs_min || "") !== "" || (r.subs_max || "") !== "")
            out.push({ k: "subs", icon: "user", label: I18n.tr("Subs") + "  " + (r.subs_min || "0") + " – " + (r.subs_max || "∞") })
        if ((r.views_min || "") !== "" || (r.views_max || "") !== "")
            out.push({ k: "views", icon: "visibility", label: I18n.tr("Views") + "  " + (r.views_min || "0") + " – " + (r.views_max || "∞") })
        if ((r.sort_views || "") !== "")
            out.push({ k: "sv", icon: "sort", label: I18n.tr("Views") + (r.sort_views === "asc" ? "  ↑" : "  ↓") })
        if ((r.sort_subs || "") !== "")
            out.push({ k: "ss", icon: "sort", label: I18n.tr("Subs") + (r.sort_subs === "asc" ? "  ↑" : "  ↓") })
        return out
    }

    // Re-apply the range with some keys changed; everything else is kept.
    function applyRange(patch) {
        var r = page._range
        function pick(k) { return (patch[k] !== undefined) ? patch[k] : (r[k] || "") }
        Archive.applyDetailRange(pick("subs_min"), pick("subs_max"),
                                 pick("views_min"), pick("views_max"),
                                 pick("format") || "all",
                                 pick("sort_views"), pick("sort_subs"))
    }
    function clearFilter(k) {
        if (k === "text") { detailSearch.text = ""; Archive.detailFilterText = "" }
        else if (k === "tf") Archive.detailTimeframeIndex = page._tfLast
        else if (k === "fav") Archive.detailFavOnly = false
        else if (k === "fmt") page.applyRange({ format: "all" })
        else if (k === "subs") page.applyRange({ subs_min: "", subs_max: "" })
        else if (k === "views") page.applyRange({ views_min: "", views_max: "" })
        else if (k === "sv") page.applyRange({ sort_views: "" })
        else if (k === "ss") page.applyRange({ sort_subs: "" })
    }
    function resetFilters() {
        detailSearch.text = ""
        Archive.detailFilterText = ""
        Archive.detailTimeframeIndex = page._tfLast
        Archive.detailFavOnly = false
        Archive.clearDetailRange()
    }
    function openSection(gid) {
        Archive.openGroup(gid)
        detailScroll.toTop()
    }

    // ═══════════════════════ building blocks ═══════════════════════

    // Labelled pill (mode / source / runs)
    component Chip: Rectangle {
        id: chip
        property string text_: ""
        property string icon: ""
        property bool accent: false
        property color tint: accent ? Theme.primary : Theme.on_surface_var
        readonly property bool _neutral: !accent && String(tint) === String(Theme.on_surface_var)
        radius: Tokens.radiusPill
        color: _neutral ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(tint, 0.12)
        border.width: 1
        border.color: _neutral ? Theme.outline_variant : U.withAlpha(tint, 0.28)
        implicitWidth: chipRow.implicitWidth + Tokens.space3 * 2
        implicitHeight: 26
        visible: text_ !== ""
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Tokens.space1 + 1
            C.IconGlyph {
                visible: chip.icon !== ""
                name: chip.icon; size: 12
                glyphColor: chip.tint
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: chip.text_
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontMicro
                font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                color: chip.tint
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Segmented control with a sliding thumb. `solid` paints the thumb in the
    // accent (tabs); soft mode tints it (timeframe / format / sort direction).
    component SegBar: Rectangle {
        id: sb
        property var options: []          // [{ label, icon }]
        property int current: 0
        property bool solid: false
        property int segHeight: 34
        signal picked(int index)
        radius: Tokens.radiusMd
        color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.04 : 0.035)
        border.width: 1
        border.color: Theme.border
        implicitWidth: sbRow.implicitWidth + 8
        implicitHeight: segHeight + 8

        Rectangle {
            id: sbThumb
            readonly property Item on: (sbRep.count > 0 && sb.current >= 0 && sb.current < sbRep.count) ? sbRep.liveItemAt(sb.current) : null
            visible: on !== null
            x: on ? sbRow.x + on.x : 4
            y: 4
            width: on ? on.width : 0
            height: sb.segHeight
            radius: Tokens.radiusSm
            color: sb.solid ? Theme.primary : U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.14)
            border.width: sb.solid ? 0 : 1
            border.color: U.withAlpha(Theme.primary, 0.40)
            Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
        }

        Row {
            id: sbRow
            anchors.centerIn: parent
            spacing: 0
            Repeater {
                id: sbRep
                // itemAt() is not a notifying lookup: a binding that ran before the
                // delegates existed got null and kept it (thumb missing on first show,
                // the active label invisible in light theme). `built` re-runs it.
                property int built: 0
                onItemAdded: built++
                onItemRemoved: built++
                function liveItemAt(i) { return built >= 0 ? itemAt(i) : null }
                model: sb.options
                AbstractButton {
                    id: sbBtn
                    readonly property bool on: sb.current === index
                    height: sb.segHeight
                    implicitWidth: sbInner.implicitWidth + Tokens.space3 * 2
                    onClicked: sb.picked(index)
                    HoverHandler { id: sbHover; cursorShape: Qt.PointingHandCursor }
                    background: Item {}
                    contentItem: Item {
                        Row {
                            id: sbInner
                            anchors.centerIn: parent
                            spacing: Tokens.space1 + 2
                            C.IconGlyph {
                                visible: (modelData.icon || "") !== ""
                                name: modelData.icon || ""
                                size: 14
                                fill: sbBtn.on
                                glyphColor: sbBtn.on ? (sb.solid ? Theme.on_primary : Theme.primary)
                                            : sbHover.hovered ? Theme.text_strong : Theme.on_surface_var
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: modelData.label
                                weight: sbBtn.on ? Tokens.weightBold : Tokens.weightDemiBold
                                font.pixelSize: Tokens.fontBody
                                color: sbBtn.on ? (sb.solid ? Theme.on_primary : Theme.primary)
                                       : sbHover.hovered ? Theme.text_strong : Theme.on_surface_var
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                        }
                    }
                }
            }
        }
    }

    // Search field with icon, focus halo, keyboard hint and clear button.
    component SearchBox: Item {
        id: sbx
        property alias text: sbField.text
        property string placeholder: ""
        property string kbd: ""
        readonly property bool fieldFocused: sbField.activeFocus
        function focusField() { sbField.forceActiveFocus(); sbField.selectAll() }
        signal edited()
        implicitHeight: 44

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: Tokens.radiusMd + 3
            color: "transparent"
            border.width: 3
            border.color: U.withAlpha(Theme.primary, sbField.activeFocus ? 0.22 : 0.0)
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
        }
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusMd
            color: Theme.input_bg
            border.width: 1
            border.color: sbField.activeFocus ? Theme.primary
                          : sbxHover.hovered ? U.mix(Theme.border, Theme.outline, 0.6)
                          : U.mix(Theme.border, Theme.outline, 0.3)
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            HoverHandler { id: sbxHover; cursorShape: Qt.IBeamCursor }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space3 + 2
                anchors.rightMargin: Tokens.space2
                spacing: Tokens.space2
                C.IconGlyph {
                    name: "search"; size: 17
                    glyphColor: sbField.activeFocus ? Theme.primary : Theme.on_surface_var
                    Layout.alignment: Qt.AlignVCenter
                }
                TextField {
                    id: sbField
                    // v3.40.1 — premium right-click menu (replaces Qt's stock one)
                    T.ContextMenu.menu: C.EditMenu { editor: sbField }
                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                    selectedTextColor: Theme.text_strong
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    placeholderText: sbx.placeholder
                    placeholderTextColor: Theme.outline
                    color: Theme.on_surface
                    font.family: Fonts.body
                    font.pixelSize: Tokens.fontBody
                    selectByMouse: true
                    background: null
                    onTextChanged: sbx.edited()
                    Keys.onEscapePressed: { text = ""; focus = false }
                }
                Rectangle {
                    visible: sbx.kbd !== "" && sbField.text === "" && !sbField.activeFocus
                    radius: Tokens.radiusXs
                    color: Theme.surface_high
                    border.width: 1
                    border.color: Theme.outline_variant
                    implicitWidth: kbdLbl.implicitWidth + Tokens.space2 * 2
                    implicitHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    C.AppText {
                        id: kbdLbl
                        anchors.centerIn: parent
                        text: sbx.kbd
                        mono: true
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.outline
                    }
                }
                C.IconButton {
                    width: 30; height: 30
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    visible: sbField.text !== ""
                    iconName: "close"
                    glyphSize: 16
                    accent: Theme.on_surface_var
                    tip: I18n.tr("Clear the search")
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: sbField.text = ""
                }
            }
        }
    }

    // A toggle chip (Favorites only).
    component ToggleChip: AbstractButton {
        id: tc
        property string label: ""
        property string glyph: ""
        property bool on: false
        property color tint: Theme.warn
        implicitHeight: 44
        implicitWidth: tcRow.implicitWidth + Tokens.space4 * 2
        HoverHandler { id: tcHover; cursorShape: Qt.PointingHandCursor }
        scale: pressed ? 0.97 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
        background: Rectangle {
            radius: Tokens.radiusMd
            color: tc.on ? U.withAlpha(tc.tint, Theme.isDark ? 0.16 : 0.12)
                 : tcHover.hovered ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(Theme.on_surface, 0)
            border.width: 1
            border.color: tc.on ? U.withAlpha(tc.tint, 0.50) : U.mix(Theme.border, Theme.outline, 0.3)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            Row {
                id: tcRow
                anchors.centerIn: parent
                spacing: Tokens.space2
                C.IconGlyph {
                    name: tc.glyph; size: 16
                    fill: tc.on
                    glyphColor: tc.on ? tc.tint : (tcHover.hovered ? Theme.text_strong : Theme.on_surface_var)
                    anchors.verticalCenter: parent.verticalCenter
                    scale: tc.on ? 1.0 : 0.92
                    Behavior on scale { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
                }
                C.AppText {
                    text: tc.label
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontBody
                    color: tc.on ? tc.tint : (tcHover.hovered ? Theme.text_strong : Theme.on_surface)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // "Ranges" trigger with a count badge.
    component RangeButton: AbstractButton {
        id: rb
        property int count: 0
        property bool compact: false
        implicitHeight: 44
        implicitWidth: compact ? 44 : rbRow.implicitWidth + Tokens.space4 * 2
        HoverHandler { id: rbHover; cursorShape: Qt.PointingHandCursor }
        scale: pressed ? 0.97 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
        C.AppTooltip {
            visible: rbHover.hovered
            delay: 350
            text: I18n.tr("Filter by subscriber and view range")
        }
        background: Rectangle {
            radius: Tokens.radiusMd
            color: rb.count > 0 ? U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                 : rbHover.hovered ? U.withAlpha(Theme.on_surface, 0.05) : U.withAlpha(Theme.on_surface, 0)
            border.width: 1
            border.color: rb.count > 0 ? U.withAlpha(Theme.primary, 0.50) : U.mix(Theme.border, Theme.outline, 0.3)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            Row {
                id: rbRow
                anchors.centerIn: parent
                spacing: Tokens.space2
                C.IconGlyph {
                    name: "tune"; size: 17
                    glyphColor: rb.count > 0 ? Theme.primary : (rbHover.hovered ? Theme.text_strong : Theme.on_surface_var)
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: rbHover.hovered && page._motion ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                }
                C.AppText {
                    visible: !rb.compact
                    text: I18n.tr("Ranges")
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontBody
                    color: rb.count > 0 ? Theme.primary : Theme.on_surface
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    visible: rb.count > 0 && !rb.compact
                    width: 20; height: 20; radius: 10
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                    C.AppText {
                        anchors.centerIn: parent
                        text: rb.count
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontMicro
                        color: Theme.on_primary
                    }
                }
            }
        }
    }

    // Sort menu: a field-like trigger and a rich popup. Each VM option
    // "Best Finds · Views ÷ Subs" splits into a name and a caption.
    component SortMenu: AbstractButton {
        id: sm
        property bool compact: false
        readonly property var opts: Archive.sortOptions || []
        readonly property int cur: Archive.detailSortIndex
        // Glyph per sort KEY, not per position: a channel section hides the two
        // "Smallest Channel" entries, so positions shift but keys don't.
        readonly property var keys: Archive.sortKeys || []
        readonly property var glyphMap: ({ multiplier: "diamond", view_count: "visibility", velocity: "speed",
                                           subscriber_count: "user", small_high_view: "target", published_at: "history",
                                           engagement: "favorite", view_count_asc: "sort" })
        function glyph(i) { return sm.glyphMap[sm.keys[i]] || "sort" }
        readonly property bool overridden: (page._range.sort_views || "") !== "" || (page._range.sort_subs || "") !== ""
        property real _closedAt: 0
        function head(s) { s = String(s || ""); var i = s.indexOf(" · "); return i < 0 ? s : s.substring(0, i) }
        function tail(s) { s = String(s || ""); var i = s.indexOf(" · "); return i < 0 ? "" : s.substring(i + 3) }

        implicitHeight: 44
        implicitWidth: compact ? 200 : 250
        onClicked: {
            if (menu.visible) menu.close()
            else if (Date.now() - sm._closedAt > 250) menu.open()
        }
        HoverHandler { id: smHover; cursorShape: Qt.PointingHandCursor }

        background: Rectangle {
            radius: Tokens.radiusMd
            // v3.43c blink fix: every state is an OPAQUE blend of input_bg. The
            // hover used to be a 5%-alpha overlay replacing the opaque fill, and
            // ColorAnimation interpolates straight alpha — so mid-fade the field
            // went half-transparent grey for a frame (the flash on mouse-over).
            color: menu.visible ? U.mix(Theme.input_bg, Theme.primary, Theme.isDark ? 0.10 : 0.07)
                 : smHover.hovered ? U.mix(Theme.input_bg, Theme.on_surface, Theme.isDark ? 0.06 : 0.04) : Theme.input_bg
            border.width: 1
            border.color: menu.visible ? Theme.primary : U.mix(Theme.border, Theme.outline, 0.3)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: RowLayout {
            spacing: Tokens.space2 + 2
            Item { Layout.preferredWidth: Tokens.space1 }
            C.IconGlyph {
                name: sm.glyph(sm.cur)
                size: 16
                fill: true
                glyphColor: Theme.primary
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                C.AppText {
                    text: sm.overridden ? I18n.tr("Range sort active") : I18n.tr("Sort")
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontMicro
                    font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                    font.capitalization: I18n.rtl ? Font.MixedCase : Font.AllUppercase
                    color: sm.overridden ? Theme.warn : Theme.outline
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                C.AppText {
                    text: sm.head(sm.opts[sm.cur])
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontBody
                    color: Theme.text_strong
                    opacity: sm.overridden ? 0.55 : 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            C.IconGlyph {
                name: "expand_more"; size: 18
                glyphColor: menu.visible ? Theme.primary : Theme.on_surface_var
                rotation: menu.visible ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Tokens.space2
            }
        }

        Popup {
            id: menu
            y: sm.height + 6
            x: I18n.rtl ? sm.width - width : 0
            width: 340
            padding: Tokens.space1 + 2
            onClosed: sm._closedAt = Date.now()
            transformOrigin: I18n.rtl ? Item.TopRight : Item.TopLeft
            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }
            exit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast }
            }
            background: Rectangle {
                id: menuBg
                radius: Tokens.radiusLg
                color: Theme.dropdown_bg
                border.width: 1
                border.color: U.mix(Theme.border, Theme.primary, 0.20)
                layer.enabled: menuBg.height > 0 && menuBg.height <= 4096
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.55 : 0.14)
                    shadowVerticalOffset: 12
                    shadowBlur: 0.9
                    shadowScale: 1.0
                }
            }
            contentItem: Column {
                spacing: 2
                Repeater {
                    model: sm.opts
                    AbstractButton {
                        id: opt
                        readonly property bool on: index === sm.cur
                        width: menu.width - menu.padding * 2
                        height: 52
                        onClicked: {
                            if (sm.overridden) page.applyRange({ sort_views: "", sort_subs: "" })
                            Archive.detailSortIndex = index
                            menu.close()
                        }
                        HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: Tokens.radiusMd
                            color: opt.on ? U.withAlpha(Theme.primary, Theme.isDark ? 0.14 : 0.09)
                                 : optHover.hovered ? U.withAlpha(Theme.on_surface, 0.06) : U.withAlpha(Theme.on_surface, 0)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        contentItem: RowLayout {
                            spacing: Tokens.space3
                            Rectangle {
                                Layout.leftMargin: Tokens.space2
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: Tokens.radiusSm
                                color: opt.on ? Theme.primary : U.withAlpha(Theme.on_surface, 0.06)
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    name: sm.glyph(index)
                                    size: 16
                                    fill: opt.on
                                    glyphColor: opt.on ? Theme.on_primary : Theme.on_surface_var
                                }
                            }
                            ColumnLayout {
                                spacing: 1
                                Layout.fillWidth: true
                                C.AppText {
                                    text: sm.head(modelData)
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontBody
                                    color: opt.on ? Theme.primary : Theme.text_strong
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                C.AppText {
                                    visible: text !== ""
                                    text: sm.tail(modelData)
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            C.IconGlyph {
                                visible: opt.on
                                name: "check"; size: 16
                                glyphColor: Theme.primary
                                Layout.rightMargin: Tokens.space3
                            }
                        }
                    }
                }
            }
        }
    }

    // Removable active-filter pill.
    component FilterPill: AbstractButton {
        id: fp
        property string label: ""
        property string glyph: ""
        signal dismissed()
        implicitHeight: 32
        implicitWidth: fpRow.implicitWidth + Tokens.space3 * 2
        onClicked: fp.dismissed()
        HoverHandler { id: fpHover; cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: Tokens.radiusPill
            color: fpHover.hovered ? U.withAlpha(Theme.error, 0.10) : U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.08)
            border.width: 1
            border.color: fpHover.hovered ? U.withAlpha(Theme.error, 0.45) : U.withAlpha(Theme.primary, 0.32)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        contentItem: Item {
            Row {
                id: fpRow
                anchors.centerIn: parent
                spacing: Tokens.space1 + 2
                C.IconGlyph {
                    name: fp.glyph; size: 13
                    glyphColor: fpHover.hovered ? Theme.error : Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                C.AppText {
                    text: fp.label
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.text_strong
                    anchors.verticalCenter: parent.verticalCenter
                }
                C.IconGlyph {
                    name: "close"; size: 13
                    glyphColor: fpHover.hovered ? Theme.error : Theme.on_surface_var
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        // arrival
        Component.onCompleted: if (page._motion) { fp.opacity = 0; fp.scale = 0.85; fpIn.start() }
        ParallelAnimation {
            id: fpIn
            NumberAnimation { target: fp; property: "opacity"; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { target: fp; property: "scale"; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }
    }

    // A ring drawn around an avatar: the section's share of the archive.
    component VolumeRing: Item {
        id: vr
        property real value: 0
        property real thickness: 3
        property color accent: Theme.primary
        property real _anim: 0
        Behavior on _anim { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        Component.onCompleted: _anim = value
        onValueChanged: _anim = value
        readonly property real _rad: (Math.min(width, height) - thickness) / 2
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeColor: U.withAlpha(Theme.outline, 0.22)
                strokeWidth: vr.thickness
                fillColor: "transparent"
                PathAngleArc {
                    centerX: vr.width / 2; centerY: vr.height / 2
                    radiusX: vr._rad; radiusY: vr._rad
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        Shape {
            anchors.fill: parent
            antialiasing: true
            visible: vr._anim > 0.001
            ShapePath {
                strokeColor: vr.accent
                strokeWidth: vr.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: vr.width / 2; centerY: vr.height / 2
                    radiusX: vr._rad; radiusY: vr._rad
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.02, Math.min(1, vr._anim))
                }
            }
        }
    }

    // Round avatar (channel logo) or a mode tile, with the volume ring.
    component SectionAvatar: Item {
        id: sa
        property string thumb: ""
        property string glyph: "search"
        property real volume: 0
        property bool lit: false
        property int size: 52
        width: size + 10; height: size + 10
        implicitWidth: width; implicitHeight: height

        VolumeRing {
            anchors.fill: parent
            value: sa.volume
            thickness: 3
            accent: sa.lit ? Theme.primary : U.withAlpha(Theme.primary, 0.75)
        }
        Rectangle {
            visible: sa.thumb === ""
            anchors.centerIn: parent
            width: sa.size; height: sa.size
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, sa.lit ? 0.32 : 0.20) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.06) }
            }
            border.width: 1
            border.color: U.withAlpha(Theme.primary, 0.35)
            C.IconGlyph {
                anchors.centerIn: parent
                name: sa.glyph; size: Math.round(sa.size * 0.42)
                fill: sa.lit
                glyphColor: Theme.primary
            }
        }
        Image {
            id: saImg
            anchors.centerIn: parent
            width: sa.size; height: sa.size
            visible: false
            source: sa.thumb !== "" ? "image://thumbs/" + sa.thumb : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: sa.size
            sourceSize.height: sa.size
        }
        Item {
            id: saMask
            anchors.centerIn: parent
            width: sa.size; height: sa.size
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
        }
        MultiEffect {
            anchors.centerIn: parent
            width: sa.size; height: sa.size
            visible: sa.thumb !== ""
            source: saImg
            maskEnabled: true
            maskSource: saMask
            opacity: saImg.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
        }
    }

    // One headline number (master band) — big mono value, small label.
    component Metric: ColumnLayout {
        id: mt
        property string label: ""
        property string value: ""
        property string icon: ""
        property bool hero: false
        property int order: 0
        spacing: 2
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        transform: Translate { id: mtRise }
        function replay() {
            if (!page._motion) { mtIn.stop(); mt.opacity = 1; mtRise.y = 0; return }
            mt.opacity = 0; mtRise.y = 10; mtIn.restart()
        }
        Component.onCompleted: replay()
        Connections {
            target: page
            function onVisibleChanged() { if (page.visible) mt.replay() }
        }
        ParallelAnimation {
            id: mtIn
            SequentialAnimation {
                PauseAnimation { duration: 80 + mt.order * 80 }
                NumberAnimation { target: mt; property: "opacity"; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 80 + mt.order * 80 }
                NumberAnimation { target: mtRise; property: "y"; to: 0; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            }
        }
        C.AppText {
            text: mt.value
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: mt.hero ? 38 : 30
            color: mt.hero ? Theme.primary : Theme.text_strong
            Layout.fillWidth: true
            elide: Text.ElideRight
            LayoutMirroring.enabled: false
            horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
        }
        Row {
            spacing: Tokens.space1 + 2
            C.IconGlyph {
                name: mt.icon; size: 13
                fill: mt.hero
                glyphColor: mt.hero ? Theme.primary : Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: mt.label
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                color: mt.hero ? Theme.primary : Theme.on_surface_var
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // One cell of the detail spec sheet.
    component Spec: ColumnLayout {
        id: sp
        property string label: ""
        property string value: ""
        property string icon: ""
        property bool hero: false
        property int order: 0
        spacing: Tokens.space2
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        transform: Translate { id: spRise }
        function replay() {
            if (!page._motion) { spIn.stop(); sp.opacity = 1; spRise.y = 0; return }
            sp.opacity = 0; spRise.y = 8; spIn.restart()
        }
        // detailStats is re-read on every filter change (the Repeater rebuilds
        // these cells) — only the first build for a section gets the entrance
        Component.onCompleted: {
            if (page._specSeen !== Archive.detailId) {
                replay()
                Qt.callLater(function() { page._specSeen = Archive.detailId })
            }
        }
        ParallelAnimation {
            id: spIn
            SequentialAnimation {
                PauseAnimation { duration: 40 + sp.order * 55 }
                NumberAnimation { target: sp; property: "opacity"; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 40 + sp.order * 55 }
                NumberAnimation { target: spRise; property: "y"; to: 0; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: sp.hero ? 3 : 1
            radius: height / 2
            color: sp.hero ? Theme.primary : Theme.outline_variant
        }
        Row {
            spacing: Tokens.space1 + 2
            C.IconGlyph {
                name: sp.icon; size: 13
                fill: sp.hero
                glyphColor: sp.hero ? Theme.primary : Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: sp.label
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontMicro
                font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                font.capitalization: I18n.rtl ? Font.MixedCase : Font.AllUppercase
                color: sp.hero ? Theme.primary : Theme.on_surface_var
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        C.AppText {
            text: sp.value
            mono: true
            weight: Tokens.weightExtraBold
            font.pixelSize: sp.hero ? 32 : 24
            color: sp.hero ? Theme.primary : Theme.text_strong
            elide: Text.ElideRight
            Layout.fillWidth: true
            LayoutMirroring.enabled: false
            horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
        }
    }

    // A saved section — the master grid's tile.
    component SectionTile: C.GlassPanel {
        id: st
        property var g: ({})
        property int order: 0
        readonly property bool hot: stHover.hovered
        readonly property real volume: Math.max(0, Math.min(1, (st.g.itemCount || 0) / Math.max(1, page._totalItems)))
        readonly property int runs: parseInt(st.g.runCount || "0") || 0
        readonly property int _ticks: Math.min(st.runs, 28)

        radius: Tokens.radiusXl
        elevation: hot ? 1.3 : 0.4
        Behavior on elevation { NumberAnimation { duration: Tokens.durMed } }
        implicitHeight: stCol.implicitHeight + Tokens.space5 * 2
        border.color: hot ? U.withAlpha(Theme.primary, 0.50)
                          : (st.g.isFavoriteSection === true ? U.withAlpha(Theme.primary, 0.26) : Theme.border)
        Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        scale: stPress.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast } }

        transform: [
            Translate { id: stRise },
            Translate {
                y: (st.hot && page._motion) ? -3 : 0
                Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }
        ]
        Component.onCompleted: {
            if (!page._motion) return
            st.opacity = 0
            stRise.y = 14
            stIn.start()
        }
        ParallelAnimation {
            id: stIn
            SequentialAnimation {
                PauseAnimation { duration: Math.min(st.order, 12) * 32 }
                NumberAnimation { target: st; property: "opacity"; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: Math.min(st.order, 12) * 32 }
                NumberAnimation { target: stRise; property: "y"; to: 0; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            }
        }

        HoverHandler { id: stHover; cursorShape: Qt.PointingHandCursor }

        // corner light that follows hover
        C.CornerGlow {
            radius: st.radius
            size: 320
            strength: st.hot ? (Theme.isDark ? 0.16 : 0.10) : (Theme.isDark ? 0.05 : 0.03)
            Behavior on strength { NumberAnimation { duration: Tokens.durGlow } }
        }

        MouseArea {
            id: stPress
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.openSection(st.g.id)
        }

        ColumnLayout {
            id: stCol
            anchors.fill: parent
            anchors.margins: Tokens.space5
            spacing: Tokens.space4

            // avatar · chips · saved marker
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                SectionAvatar {
                    size: 50
                    thumb: st.g.channelThumbId || ""
                    glyph: st.g.modeIcon || "search"
                    volume: st.volume
                    lit: st.hot
                    Layout.alignment: Qt.AlignTop
                    scale: st.hot && page._motion ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                }
                Item { Layout.fillWidth: true }
                Row {
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.space1 + 2
                    Chip {
                        text_: st.g.modeLabel || ""
                        icon: st.g.modeIcon || "search"
                        accent: true
                    }
                    Chip {
                        text_: st.g.sourceLabel || ""
                        icon: st.g.sourceLabel === "SCRAPE" ? "nav_scrape" : "api"
                        tint: st.g.sourceLabel === "SCRAPE" ? Theme.secondary_container : Theme.on_surface_var
                    }
                    Rectangle {
                        visible: st.g.isFavoriteSection === true
                        width: 26; height: 26; radius: 13
                        color: U.withAlpha(Theme.primary, 0.16)
                        border.width: 1
                        border.color: U.withAlpha(Theme.primary, 0.45)
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: "bookmark"; fill: true; size: 13
                            glyphColor: Theme.primary
                        }
                    }
                }
            }

            // title + updated
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                C.AppText {
                    text: st.g.title || "—"
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontSubtitle + 3
                    color: st.hot ? Theme.primary : Theme.text_strong
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                C.AppText {
                    text: I18n.tr("Updated {t}").replace("{t}", st.g.updated || "—")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            // numbers
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                C.AppText {
                    text: st.g.itemCountText || "0"
                    mono: true
                    weight: Tokens.weightExtraBold
                    font.pixelSize: Tokens.fontTitle + 8
                    color: Theme.text_strong
                    Layout.alignment: Qt.AlignBaseline
                    LayoutMirroring.enabled: false
                }
                C.AppText {
                    text: I18n.tr("videos")
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    Layout.alignment: Qt.AlignBaseline
                }
                Item { Layout.fillWidth: true }
                Row {
                    visible: (st.g.favCount || 0) > 0
                    spacing: Tokens.space1
                    Layout.alignment: Qt.AlignVCenter
                    C.IconGlyph {
                        name: "star"; fill: true; size: 14
                        glyphColor: Theme.warn
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    C.AppText {
                        text: st.g.favCountText || ""
                        mono: true
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.warn
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // run tally — one tick per refresh, newest brightest
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    clip: true
                    Row {
                        id: tally
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Repeater {
                            model: st._ticks
                            Rectangle {
                                width: 4
                                height: 14
                                radius: 2
                                readonly property real k: st._ticks <= 1 ? 1 : index / (st._ticks - 1)
                                color: U.withAlpha(Theme.primary, 0.25 + 0.75 * k)
                                anchors.verticalCenter: parent.verticalCenter
                                scale: (st.hot && page._motion) ? 1.0 : 0.86
                                Behavior on scale {
                                    SequentialAnimation {
                                        PauseAnimation { duration: index * 12 }
                                        NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                                    }
                                }
                            }
                        }
                    }
                }
                C.AppText {
                    text: (st.runs > st._ticks ? "+" + (st.runs - st._ticks) + "  " : "")
                          + I18n.tr("{n} runs").replace("{n}", st.runs)
                    mono: true
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // footer: open + hover actions
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space1
                spacing: Tokens.space1
                Rectangle {
                    implicitHeight: 32
                    implicitWidth: openRow.implicitWidth + Tokens.space4 * 2
                    radius: Tokens.radiusPill
                    color: st.hot ? Theme.primary : U.withAlpha(Theme.on_surface, 0.05)
                    border.width: 1
                    border.color: st.hot ? Theme.primary : Theme.outline_variant
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                    Row {
                        id: openRow
                        anchors.centerIn: parent
                        spacing: Tokens.space1 + 2
                        C.AppText {
                            text: I18n.tr("Open section")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontCaption
                            color: st.hot ? Theme.on_primary : Theme.on_surface
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        C.IconGlyph {
                            name: I18n.rtl ? "arrow_back" : "arrow_forward"; size: 14
                            glyphColor: st.hot ? Theme.on_primary : Theme.on_surface_var
                            anchors.verticalCenter: parent.verticalCenter
                            transform: Translate {
                                x: st.hot ? (I18n.rtl ? -3 : 3) : 0
                                Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Row {
                    spacing: Tokens.space1
                    opacity: st.hot ? 1 : 0
                    enabled: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                    C.IconButton {
                        width: 32; height: 32
                        glyphSize: 16
                        iconName: "bookmark_add"
                        accent: Theme.primary
                        active: st.g.isFavoriteSection === true
                        tip: st.g.isFavoriteSection === true ? I18n.tr("Remove from favourites") : I18n.tr("Save to favourites")
                        onClicked: Archive.toggleGroupSaved(st.g.id)
                    }
                    C.IconButton {
                        width: 32; height: 32
                        glyphSize: 16
                        iconName: "edit"
                        accent: Theme.primary
                        tip: I18n.tr("Rename this section")
                        onClicked: page.openRename(st.g.id, st.g.title)
                    }
                    C.IconButton {
                        width: 32; height: 32
                        glyphSize: 16
                        iconName: "delete"
                        accent: Theme.error
                        tip: I18n.tr("Delete this section")
                        onClicked: page.openConfirmDelete(st.g)
                    }
                }
            }
        }
    }

    // ═══════════════════════ MASTER: the library ═══════════════════════
    C.SmoothScrollView {
        id: masterScroll
        anchors.fill: parent
        visible: !Archive.isDetail
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        Item {
            width: masterScroll.availableWidth
            implicitHeight: masterCol.implicitHeight + Tokens.space7 * 2

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 520
            }

            ColumnLayout {
                id: masterCol
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space7
                spacing: Tokens.space6

                // ── header: open, on the page wash ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space5

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space3

                        Row {
                            spacing: Tokens.space2
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: page._motion && page.visible && Tokens.appActive
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 1100; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutQuad }
                                }
                            }
                            C.AppText {
                                text: I18n.tr("Search Archive · Zero quota")
                                mono: true
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontCaption
                                font.letterSpacing: I18n.rtl ? 0 : 1.2
                                font.capitalization: I18n.rtl ? Font.MixedCase : Font.AllUppercase
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Math.round(page._heroSize * 0.28)
                            C.AppText {
                                text: I18n.tr("Every search you've run,")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: page._heroSize
                                font.letterSpacing: I18n.rtl ? 0 : -0.8
                                color: Theme.text_strong
                            }
                            C.AppText {
                                text: I18n.tr("kept forever.")
                                weight: Tokens.weightExtraBold
                                font.pixelSize: page._heroSize
                                font.letterSpacing: I18n.rtl ? 0 : -0.8
                                color: Theme.primary
                            }
                        }
                        C.AppText {
                            text: I18n.tr("Reopen it, re-filter it, export it. Reading the archive never spends a single unit.")
                            font.pixelSize: Tokens.fontLabel + 1
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            Layout.maximumWidth: 640
                        }
                    }

                    Row {
                        Layout.alignment: Qt.AlignBottom
                        spacing: Tokens.space2
                        C.IconButton {
                            width: 44; height: 44
                            iconName: "refresh"
                            accent: Theme.primary
                            tip: I18n.tr("Reload the archive")
                            onClicked: Archive.reload()
                        }
                        C.PrimaryButton {
                            variant: "ghost"
                            iconName: "delete_sweep"
                            text: I18n.tr("Clear all")
                            visible: Archive.hasAny
                            onClicked: confirmClear.open()
                        }
                    }
                }

                // ── the library band: spectrum + four numbers ──
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    visible: Archive.hasAny
                    implicitHeight: bandCol.implicitHeight + Tokens.space6 * 2

                    C.CornerGlow { radius: Tokens.radiusXl; size: 560 }

                    ColumnLayout {
                        id: bandCol
                        anchors.fill: parent
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space5

                        GridLayout {
                            Layout.fillWidth: true
                            columns: masterCol.width < 760 ? 2 : 4
                            columnSpacing: Tokens.space6
                            rowSpacing: Tokens.space5
                            Metric { order: 0; icon: "movie"; label: I18n.tr("Videos archived"); value: Archive.statVideos; hero: true }
                            Metric { order: 1; icon: "archive"; label: I18n.tr("Sections"); value: Archive.statGroups }
                            Metric { order: 2; icon: "star"; label: I18n.tr("Favorites"); value: Archive.statFavorites }
                            Metric { order: 3; icon: "autorenew"; label: I18n.tr("Total runs"); value: Archive.statRuns }
                        }

                        // spectrum
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2
                            visible: page._spectrum.length > 0
                            RowLayout {
                                Layout.fillWidth: true
                                C.AppText {
                                    text: I18n.tr("Where your archive lives")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                }
                                Item { Layout.fillWidth: true }
                                C.AppText {
                                    text: spectrumBar.hoverIdx >= 0
                                          ? (page._spectrum[spectrumBar.hoverIdx].title + "  ·  "
                                             + page._spectrum[spectrumBar.hoverIdx].text + " " + I18n.tr("videos") + "  ·  "
                                             + Math.round(page._spectrum[spectrumBar.hoverIdx].n * 100 / page._totalItems) + "%")
                                          : I18n.tr("Hover a segment · click to open")
                                    mono: spectrumBar.hoverIdx >= 0
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: spectrumBar.hoverIdx >= 0 ? Theme.primary : Theme.outline
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: bandCol.width * 0.6
                                }
                            }
                            Item {
                                id: spectrumBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                property int hoverIdx: -1
                                readonly property real _gap: 3
                                readonly property real _usable: width - _gap * Math.max(0, page._spectrum.length - 1)
                                Row {
                                    anchors.fill: parent
                                    spacing: spectrumBar._gap
                                    Repeater {
                                        model: page._spectrum
                                        Item {
                                            id: seg
                                            readonly property bool hot: spectrumBar.hoverIdx === index
                                            height: spectrumBar.height
                                            width: Math.max(6, spectrumBar._usable * modelData.n / page._totalItems)
                                            property real grow: 1
                                            Component.onCompleted: if (page._motion) segIn.start()
                                            NumberAnimation {
                                                id: segIn
                                                target: seg; property: "grow"
                                                from: 0; to: 1
                                                duration: 700 + index * 60
                                                easing.type: Easing.OutCubic
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width * seg.grow
                                                height: seg.hot ? parent.height : 12
                                                radius: Math.min(4, width / 2)
                                                color: modelData.other ? U.withAlpha(Theme.outline, 0.35)
                                                       : U.withAlpha(Theme.primary, Math.max(0.28, 1.0 - index * 0.08))
                                                border.width: seg.hot ? 1 : 0
                                                border.color: Qt.rgba(1, 1, 1, 0.35)
                                                Behavior on height { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: modelData.other ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                onEntered: spectrumBar.hoverIdx = index
                                                onExited: if (spectrumBar.hoverIdx === index) spectrumBar.hoverIdx = -1
                                                onClicked: if (!modelData.other) page.openSection(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── command bar ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    visible: Archive.hasAny

                    SearchBox {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.maximumWidth: 560
                        placeholder: I18n.tr("Search sections…")
                        kbd: "Ctrl F"
                        onEdited: {
                            Archive.filterText = text
                            page._sectPage = 0        // a new filter starts at page 1
                        }
                    }
                    C.AppText {
                        text: page._sectLabel
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    SegBar {
                        solid: true
                        options: [
                            { label: I18n.tr("All"), icon: "grid_view" },
                            { label: I18n.tr("Favorites"), icon: "star" }
                        ]
                        current: Archive.tabIndex
                        onPicked: (i) => {
                            Archive.tabIndex = i
                            page._sectPage = 0
                        }
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Shortcut {
                    sequences: [ StandardKey.Find ]
                    enabled: page.visible && !Archive.isDetail && Archive.hasAny
                    onActivated: searchField.focusField()
                }

                // empty: nothing archived at all
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: emptyCol.implicitHeight + Tokens.space8 * 2
                    visible: !Archive.hasAny
                    elevation: 0
                    C.CornerGlow { radius: Tokens.radiusXl; size: 520 }
                    ColumnLayout {
                        id: emptyCol
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Tokens.space6 * 2, 520)
                        spacing: Tokens.space3
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 120
                            // three slow ripples behind the tile
                            Repeater {
                                model: 3
                                Rectangle {
                                    id: ripple
                                    anchors.centerIn: parent
                                    width: 70; height: 70; radius: 35
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.primary
                                    opacity: 0
                                    SequentialAnimation {
                                        running: page._motion && page.visible && !Archive.hasAny && Tokens.appActive
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: index * 900 }
                                        ParallelAnimation {
                                            NumberAnimation { target: ripple; property: "scale"; from: 0.9; to: 1.7; duration: 2700; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: ripple; property: "opacity"; from: 0.45; to: 0; duration: 2700; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }
                            }
                            C.IconTile {
                                anchors.centerIn: parent
                                size: 68; glyphSize: 30
                                solid: true
                                breathe: true
                                iconName: "archive"
                            }
                        }
                        C.AppText {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.tr("Nothing archived yet.")
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontTitle + 4
                            color: Theme.text_strong
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("Every finished Niche Finder search lands here automatically.")
                            color: Theme.on_surface_var
                            font.pixelSize: Tokens.fontLabel
                            wrapMode: Text.Wrap
                        }
                        C.PrimaryButton {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Tokens.space2
                            iconName: "travel_explore"
                            text: I18n.tr("Go to Niche Finder")
                            onClicked: App.goto(4)
                        }
                    }
                }

                // empty: search / tab matches nothing
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: noMatchCol.implicitHeight + Tokens.space6 * 2
                    visible: Archive.hasAny && Archive.isEmpty
                    elevation: 0
                    ColumnLayout {
                        id: noMatchCol
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Tokens.space6 * 2, 560)
                        spacing: Tokens.space3
                        C.IconTile {
                            Layout.alignment: Qt.AlignHCenter
                            size: 56; glyphSize: 26
                            iconName: Archive.tabIndex === 1 ? "star" : "folder_off"
                            tint: Archive.tabIndex === 1 ? Theme.warn : Theme.primary
                            iconFill: false
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Archive.tabIndex === 1
                                  ? I18n.tr("No favorites yet — bookmark a section or star its videos to pin them here.")
                                  : I18n.tr("No sections match this search.")
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                        C.PrimaryButton {
                            Layout.alignment: Qt.AlignHCenter
                            variant: "ghost"
                            iconName: Archive.tabIndex === 1 ? "grid_view" : "close"
                            text: Archive.tabIndex === 1 ? I18n.tr("Show all sections") : I18n.tr("Clear the search")
                            onClicked: {
                                if (Archive.tabIndex === 1) Archive.tabIndex = 0
                                else searchField.text = ""
                            }
                        }
                    }
                }

                // section grid
                GridLayout {
                    id: sectGrid
                    objectName: "tour_archiveGrid"
                    Layout.fillWidth: true
                    visible: !Archive.isEmpty
                    columnSpacing: Tokens.space4
                    rowSpacing: Tokens.space4

                    readonly property real availW: masterCol.width
                    property int _frozenCols: 0
                    property real _frozenW: 0
                    readonly property int _liveCols: Math.max(1, Math.min(5, Math.floor((availW + columnSpacing) / (320 + columnSpacing))))
                    columns: (App.railAnimating && _frozenCols > 0) ? _frozenCols : _liveCols
                    readonly property real cardW:
                        (App.railAnimating && _frozenW > 0) ? _frozenW
                        : (availW - columnSpacing * (columns - 1)) / columns
                    Connections {
                        target: App
                        function onRailAnimatingChanged() {
                            if (App.railAnimating) {
                                sectGrid._frozenCols = sectGrid.columns
                                sectGrid._frozenW = sectGrid.cardW
                            }
                        }
                    }

                    Repeater {
                        model: page._sectSlice
                        SectionTile {
                            g: modelData
                            order: index
                            Layout.preferredWidth: sectGrid.cardW
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                        }
                    }
                }

                // ── pager for the section grid ──
                // Only rendered when there is a second page: a one-page library
                // keeps the plain grid it always had.
                C.Pager {
                    objectName: "archiveSectPager"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -Tokens.space2
                    visible: page._sectPages > 1
                    pageIndex: page._sectPage
                    pageCount: page._sectPages
                    onRequested: (i) => page._sectGo(i)
                }
            }
        }
    }

    // ═══════════════════════ DETAIL: one open section ═══════════════════════
    C.SmoothScrollView {
        id: detailScroll
        anchors.fill: parent
        visible: Archive.isDetail
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        Item {
            width: detailScroll.availableWidth
            implicitHeight: detailCol.implicitHeight + Tokens.space7 * 2

            C.GridFade {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 460
            }

            ColumnLayout {
                id: detailCol
                width: Tokens.contentWidth(parent.width)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Tokens.space6
                spacing: Tokens.space4

                // ── breadcrumb · actions ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space2

                    AbstractButton {
                        id: crumb
                        implicitHeight: 36
                        implicitWidth: crumbRow.implicitWidth + Tokens.space3 * 2
                        onClicked: Archive.closeDetail()
                        HoverHandler { id: crumbHover; cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: Tokens.radiusPill
                            color: crumbHover.hovered ? U.withAlpha(Theme.primary, 0.12) : U.withAlpha(Theme.on_surface, 0.05)
                            border.width: 1
                            border.color: crumbHover.hovered ? U.withAlpha(Theme.primary, 0.45) : Theme.outline_variant
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        contentItem: Item {
                            Row {
                                id: crumbRow
                                anchors.centerIn: parent
                                spacing: Tokens.space2
                                C.IconGlyph {
                                    name: I18n.rtl ? "arrow_forward" : "arrow_back"; size: 15
                                    glyphColor: crumbHover.hovered ? Theme.primary : Theme.on_surface_var
                                    anchors.verticalCenter: parent.verticalCenter
                                    transform: Translate {
                                        x: crumbHover.hovered ? (I18n.rtl ? 3 : -3) : 0
                                        Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                    }
                                }
                                C.AppText {
                                    text: I18n.tr("Search Archive")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontBody
                                    color: crumbHover.hovered ? Theme.primary : Theme.on_surface
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                    C.IconGlyph {
                        name: I18n.rtl ? "chevron_left" : "chevron_right"; size: 16
                        glyphColor: Theme.outline
                        Layout.alignment: Qt.AlignVCenter
                    }
                    C.AppText {
                        text: Archive.detailTitle
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontBody
                        color: Theme.on_surface_var
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 320
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    C.PrimaryButton {
                        iconName: "nav_insights"
                        text: I18n.tr("Analyze this section")
                        onClicked: Archive.analyzeDetail()
                    }
                    C.PrimaryButton {
                        variant: "ghost"
                        iconName: "travel_explore"
                        text: I18n.tr("Open in Niche Finder")
                        visible: detailCol.width >= 980
                        onClicked: {
                            Niche.loadArchivedGroup(Archive.detailId)
                            App.goto(4)
                        }
                    }
                    C.IconButton {
                        Layout.preferredWidth: Tokens.fieldHeight
                        Layout.preferredHeight: Tokens.fieldHeight
                        visible: detailCol.width < 980
                        iconName: "travel_explore"
                        accent: Theme.primary
                        tip: I18n.tr("Open in Niche Finder")
                        onClicked: {
                            Niche.loadArchivedGroup(Archive.detailId)
                            App.goto(4)
                        }
                    }
                    C.IconButton {
                        Layout.preferredWidth: Tokens.fieldHeight
                        Layout.preferredHeight: Tokens.fieldHeight
                        iconName: "save"
                        accent: Theme.primary
                        tip: I18n.tr("Export")
                        onClicked: exportDialog.open()
                    }
                    C.IconButton {
                        Layout.preferredWidth: Tokens.fieldHeight
                        Layout.preferredHeight: Tokens.fieldHeight
                        iconName: "delete"
                        accent: Theme.error
                        tip: I18n.tr("Delete this section")
                        onClicked: page.openConfirmDeleteCurrent()
                    }
                }

                // ── section hero: identity + spec sheet ──
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: dHeroCol.implicitHeight + Tokens.space6 * 2

                    C.CornerGlow { radius: Tokens.radiusXl; size: 520 }

                    ColumnLayout {
                        id: dHeroCol
                        anchors.fill: parent
                        anchors.margins: Tokens.space6
                        spacing: Tokens.space6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space5

                            SectionAvatar {
                                size: 72
                                thumb: page._detailGroup.channelThumbId || ""
                                glyph: Archive.detailIsChannel ? "user" : "search"
                                volume: Math.max(0, Math.min(1, (page._detailGroup.itemCount || 0) / page._totalItems))
                                lit: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                spacing: Tokens.space2
                                Layout.fillWidth: true
                                C.AppText {
                                    text: Archive.detailTitle
                                    weight: Tokens.weightExtraBold
                                    font.pixelSize: Math.round(Math.max(28, Math.min(44, detailCol.width / 34)))
                                    font.letterSpacing: I18n.rtl ? 0 : -0.6
                                    color: Theme.text_strong
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Tokens.space2
                                    Chip {
                                        text_: Archive.detailModeLabel
                                        icon: Archive.detailIsChannel ? "user" : "search"
                                        accent: true
                                    }
                                    Chip {
                                        text_: Archive.detailSourceLabel
                                        icon: Archive.detailSourceLabel === "SCRAPE" ? "nav_scrape" : "api"
                                        tint: Archive.detailSourceLabel === "SCRAPE" ? Theme.secondary_container : Theme.on_surface_var
                                    }
                                    Chip {
                                        text_: I18n.tr("{n} runs").replace("{n}", Archive.detailRuns)
                                        icon: "autorenew"
                                    }
                                    // v3.43: are these numbers live? Click to re-read now.
                                    Chip {
                                        id: liveChip
                                        text_: Archive.liveText
                                        icon: Archive.liveBusy ? "autorenew"
                                            : Archive.liveState === "live" ? "check_circle"
                                            : Archive.liveState === "nokey" ? "key" : "warning"
                                        tint: Archive.liveState === "live" ? Theme.secondary_container
                                            : Archive.liveBusy ? Theme.primary
                                            : Theme.warn
                                        opacity: liveTap.pressed ? 0.7 : 1
                                        HoverHandler {
                                            id: liveHover
                                            cursorShape: Archive.liveBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        }
                                        TapHandler {
                                            id: liveTap
                                            enabled: !Archive.liveBusy
                                            onTapped: Archive.liveState === "nokey" ? App.goto(10) : Archive.refreshLive()
                                        }
                                        C.AppTooltip {
                                            visible: liveHover.hovered
                                            text: Archive.liveState === "nokey"
                                                  ? I18n.tr("Open Settings → YouTube API")
                                                  : I18n.tr("Views, likes and subscribers are re-read from YouTube when you open a section and every 5 minutes. Click to update now.")
                                        }
                                    }
                                    Chip {
                                        visible: Archive.liveMissing > 0
                                        text_: I18n.tr("{n} unavailable").replace("{n}", Archive.liveMissing)
                                        icon: "visibility_off"
                                        tint: Theme.warn
                                    }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: detailCol.width < 760 ? 2 : (detailCol.width < 1100 ? 3 : 6)
                            columnSpacing: Tokens.space5
                            rowSpacing: Tokens.space5
                            Repeater {
                                model: Archive.detailStats
                                Spec {
                                    order: index
                                    // VM order: Videos · Favorites · Total views ·
                                    // Best multiplier · Runs · Last refresh
                                    icon: ["movie", "star", "visibility", "trending_up", "autorenew", "history"][index] || "data"
                                    label: modelData.l
                                    value: modelData.v
                                    hero: index === 3
                                }
                            }
                        }
                    }
                }

                // ── the filter dock ──
                Rectangle {
                    id: dock
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space2
                    radius: Tokens.radiusXl
                    color: Theme.panel_bg
                    border.width: 1
                    border.color: Theme.border
                    implicitHeight: dockCol.implicitHeight + Tokens.space3 * 2

                    ColumnLayout {
                        id: dockCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.space3
                        spacing: Tokens.space3

                        // row 1 — search · sort · favorites · ranges
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.space2

                            SearchBox {
                                id: detailSearch
                                Layout.fillWidth: true
                                Layout.minimumWidth: 200
                                placeholder: I18n.tr("Filter these results by word …")
                                kbd: "Ctrl F"
                                onEdited: detailFilterTimer.restart()
                                Component.onCompleted: text = Archive.detailFilterText
                            }
                            SortMenu { compact: detailCol.width < 1000 }
                            ToggleChip {
                                label: I18n.tr("Favorites only")
                                glyph: "star"
                                on: Archive.detailFavOnly
                                onClicked: Archive.detailFavOnly = !Archive.detailFavOnly
                            }
                            RangeButton {
                                count: page._rangeCount
                                onClicked: rangeSheet.openSheet()
                            }
                        }

                        // row 2 — published · format · result count
                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.space4

                            Row {
                                spacing: Tokens.space2
                                C.AppText {
                                    text: I18n.tr("Published")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                SegBar {
                                    segHeight: 30
                                    readonly property var _short: [I18n.tr("24h"), I18n.tr("7d"), I18n.tr("30d"), I18n.tr("90d"), I18n.tr("6m"), I18n.tr("12m"), I18n.tr("All")]
                                    options: {
                                        var src = Archive.timeframeOptions || []
                                        var out = []
                                        for (var i = 0; i < src.length; i++)
                                            out.push({ label: src.length === _short.length ? _short[i] : src[i] })
                                        return out
                                    }
                                    current: Archive.detailTimeframeIndex
                                    onPicked: (i) => Archive.detailTimeframeIndex = i
                                }
                            }

                            Row {
                                spacing: Tokens.space2
                                C.AppText {
                                    text: I18n.tr("Format")
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface_var
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                SegBar {
                                    segHeight: 30
                                    options: [
                                        { label: I18n.tr("All"), icon: "" },
                                        { label: I18n.tr("Long-form"), icon: "fmt_long" },
                                        { label: I18n.tr("Shorts"), icon: "fmt_short" }
                                    ]
                                    current: page._format === "long" ? 1 : page._format === "short" ? 2 : 0
                                    onPicked: (i) => page.applyRange({ format: ["all", "long", "short"][i] })
                                }
                            }
                        }
                    }

                    // result count, pinned to the dock's trailing edge on row 2
                    C.AppText {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: Tokens.space4
                        anchors.bottomMargin: Tokens.space3 + 10
                        visible: Archive.detailPageLabel !== "" && dockCol.width > 980
                        text: Archive.detailPageLabel
                        mono: true
                        weight: Tokens.weightDemiBold
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                    }
                }

                Timer {
                    id: detailFilterTimer
                    interval: 260
                    onTriggered: Archive.detailFilterText = detailSearch.text
                }
                Shortcut {
                    sequences: [ StandardKey.Find ]
                    enabled: page.visible && Archive.isDetail
                    onActivated: { detailScroll.toTop(); detailSearch.focusField() }
                }

                // ── active filters ──
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.space2
                    visible: page._activeFilters.length > 0 || dockCol.width <= 980
                    Repeater {
                        model: page._activeFilters
                        FilterPill {
                            label: modelData.label
                            glyph: modelData.icon
                            onDismissed: page.clearFilter(modelData.k)
                        }
                    }
                    AbstractButton {
                        visible: page._activeFilters.length > 1
                        implicitHeight: 32
                        implicitWidth: resetLbl.implicitWidth + Tokens.space3 * 2
                        onClicked: page.resetFilters()
                        HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                        background: Item {}
                        contentItem: C.AppText {
                            id: resetLbl
                            text: I18n.tr("Reset all")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontCaption
                            font.underline: resetHover.hovered
                            color: Theme.primary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    // narrow windows: the count moves down here
                    C.AppText {
                        visible: dockCol.width <= 980 && Archive.detailPageLabel !== ""
                        height: 32
                        verticalAlignment: Text.AlignVCenter
                        text: Archive.detailPageLabel
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                    }
                }

                // ── empty result ──
                C.GlassPanel {
                    Layout.fillWidth: true
                    radius: Tokens.radiusXl
                    implicitHeight: dEmptyCol.implicitHeight + Tokens.space7 * 2
                    visible: Archive.detailIsEmpty
                    elevation: 0
                    ColumnLayout {
                        id: dEmptyCol
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Tokens.space6 * 2, 520)
                        spacing: Tokens.space3
                        C.IconTile {
                            Layout.alignment: Qt.AlignHCenter
                            size: 60; glyphSize: 28
                            iconName: Archive.detailFavOnly ? "star" : (page._activeFilters.length > 0 ? "filter_alt" : "folder_off")
                            tint: Archive.detailFavOnly ? Theme.warn : Theme.primary
                            iconFill: false
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: page._activeFilters.length > 0
                                  ? I18n.tr("Nothing matches these filters.")
                                  : I18n.tr("This section is empty.")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontSubtitle
                            color: Theme.text_strong
                            wrapMode: Text.Wrap
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            visible: Archive.detailFavOnly
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("No favorites in this section yet — tap the bookmark on a card to pin it.")
                            color: Theme.on_surface_var
                            wrapMode: Text.Wrap
                        }
                        C.PrimaryButton {
                            Layout.alignment: Qt.AlignHCenter
                            visible: page._activeFilters.length > 0
                            variant: "ghost"
                            iconName: "restart_alt"
                            text: I18n.tr("Reset filters")
                            onClicked: page.resetFilters()
                        }
                    }
                }

                // ── the grid — columns always follow the width ──
                GridLayout {
                    id: grid
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space1
                    visible: !Archive.detailIsEmpty
                    columnSpacing: Tokens.space4
                    rowSpacing: Tokens.space5

                    readonly property real availW: detailCol.width
                    readonly property int minCardW: 330
                    property int _frozenCols: 0
                    property real _frozenW: 0
                    readonly property int _liveCols: Math.max(1, Math.min(6, Math.floor((availW + columnSpacing) / (minCardW + columnSpacing))))
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
                        // v3.44 perf: an INTEGER model. With the row list as
                        // the model, every page flip (and every star toggle /
                        // live-stats tick) destroyed all 24 cards and built 24
                        // new ones — each with layered thumbnails, two
                        // MultiEffects and a dozen Behaviors. That rebuild was
                        // the 1–3 s freeze on "next page". Now the cards stay
                        // alive and only their `row` changes; the count only
                        // moves on a short last page.
                        model: page._rows.length
                        Item {
                            id: cell
                            readonly property var rowData: page._rows[index] || ({})
                            readonly property string rowKey: page._rowKey(rowData)
                            Layout.preferredWidth: grid.cardW
                            Layout.preferredHeight: vcard.implicitHeight
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: vcard.implicitHeight
                            // staggered arrival whenever a NEW video lands in
                            // this slot (page / filter / sort change) — not on
                            // in-place updates of the same video
                            opacity: 0
                            transform: Translate { id: cellRise; y: 16 }
                            function arrive() {
                                if (!page._motion) { cellIn.stop(); cell.opacity = 1; cellRise.y = 0; return }
                                cellIn.stop()
                                cell.opacity = 0
                                cellRise.y = 10
                                cellIn.start()
                            }
                            Component.onCompleted: arrive()
                            onRowKeyChanged: arrive()
                            ParallelAnimation {
                                id: cellIn
                                SequentialAnimation {
                                    PauseAnimation { duration: Math.min(index, 10) * 14 }
                                    NumberAnimation { target: cell; property: "opacity"; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
                                }
                                SequentialAnimation {
                                    PauseAnimation { duration: Math.min(index, 10) * 14 }
                                    NumberAnimation { target: cellRise; property: "y"; to: 0; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
                                }
                            }
                            // One card tree only: the skeleton is an overlay,
                            // not a second grid. Built only when thumbnails are
                            // genuinely slow (see _skeletonArmed).
                            Loader {
                                anchors.fill: parent
                                active: {
                                    page._readyTick       // _readyMap mutates in place
                                    return page._thumbLoading && page._skeletonArmed
                                           && !page._readyMap[cell.rowKey]
                                }
                                sourceComponent: C.VideoCardSkeleton {
                                    cardWidth: grid.cardW
                                    running: true
                                    delay: ((index % grid.columns) + Math.floor(index / grid.columns)) * 90
                                }
                            }
                            C.ArchiveVideoCard {
                                id: vcard
                                width: parent.width
                                height: parent.height
                                // v3.52: no hover effects while the grid is
                                // scrolling — see ArchiveVideoCard.scrollIdle.
                                scrollIdle: !detailScroll.gliding
                                opacity: page._thumbLoading ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                                row: cell.rowData
                                target: Archive
                                cardWidth: grid.cardW
                                onDownloadRequested: (vid, title, thumb) => qualityPicker.openFor(vid, title, thumb)
                                onThumbDownloadRequested: (thumb, title, isShort) => page.saveThumb(thumb, title, isShort)
                                onThumbnailReady: page._noteThumbReady(cell.rowData)
                            }
                        }
                    }
                }

                // ── pager ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space3
                    spacing: Tokens.space2
                    visible: !Archive.detailIsEmpty && Archive.detailPageCount > 1
                    C.Pager {
                        pageIndex: Archive.detailPageIndex
                        pageCount: Archive.detailPageCount
                        Layout.alignment: Qt.AlignHCenter
                        onRequested: (i) => {
                            Archive.gotoDetailPage(i)
                            detailScroll.toTop()
                        }
                    }
                    C.AppText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Archive.detailPageLabel
                        mono: true
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                    }
                }
            }
        }
    }

    // ── floating mini dock: slides in once the real dock scrolls away ──
    Item {
        id: miniDock
        readonly property real _dockBottom: detailCol.y + dock.y + dock.height
        readonly property bool shown: Archive.isDetail && page.visible
                                      && detailScroll.contentItem.contentY > _dockBottom
        z: 20
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(detailCol.width, 1080)
        height: 58
        y: shown ? Tokens.space3 : -height - Tokens.space3
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on y { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

        // only the frame is layered for the shadow; the controls stay crisp
        Rectangle {
            id: miniBg
            anchors.fill: parent
            radius: Tokens.radiusXl
            color: U.withAlpha(Theme.panel_bg, 0.97)
            border.width: 1
            border.color: U.mix(Theme.border, Theme.primary, 0.25)
            layer.enabled: miniDock.visible && miniBg.height > 0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.55 : 0.16)
                shadowVerticalOffset: 10
                shadowBlur: 0.9
                shadowScale: 1.0
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.space3
            anchors.rightMargin: Tokens.space2
            spacing: Tokens.space2

            SectionAvatar {
                size: 30
                thumb: page._detailGroup.channelThumbId || ""
                glyph: Archive.detailIsChannel ? "user" : "search"
                volume: Math.max(0, Math.min(1, (page._detailGroup.itemCount || 0) / page._totalItems))
                Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                C.AppText {
                    text: Archive.detailTitle
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontBody
                    color: Theme.text_strong
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                C.AppText {
                    text: Archive.detailPageLabel
                    mono: true
                    font.pixelSize: Tokens.fontMicro
                    color: Theme.outline
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            SortMenu { compact: true; implicitHeight: 42 }
            ToggleChip {
                implicitHeight: 42
                label: I18n.tr("Favorites")
                glyph: "star"
                on: Archive.detailFavOnly
                onClicked: Archive.detailFavOnly = !Archive.detailFavOnly
            }
            RangeButton {
                implicitHeight: 42
                compact: true
                count: page._rangeCount
                onClicked: rangeSheet.openSheet()
            }
            C.IconButton {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                iconName: "search"
                accent: Theme.primary
                tip: I18n.tr("Search these results")
                onClicked: { detailScroll.toTop(); detailSearch.focusField() }
            }
            C.IconButton {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                iconName: "expand_less"
                accent: Theme.on_surface_var
                tip: I18n.tr("Back to top")
                onClicked: detailScroll.toTop()
            }
        }
    }

    // ═══════════════════════ dialogs & overlays ═══════════════════════

    // Ranges — a side sheet that slides in from the trailing edge.
    Dialog {
        id: rangeSheet
        modal: true
        parent: Overlay.overlay
        padding: 0
        width: Math.min(420, (parent ? parent.width : 800) - 24)
        height: (parent ? parent.height : 600) - 24
        y: 12
        readonly property real _restX: I18n.rtl ? 12 : ((parent ? parent.width : 800) - width - 12)
        readonly property real _offX: I18n.rtl ? -width : (parent ? parent.width : 800)
        x: _restX

        property string sortViews: ""
        property string sortSubs: ""

        function openSheet() {
            var r = Archive.detailRange
            subsMin.text = r.subs_min || ""
            subsMax.text = r.subs_max || ""
            viewsMin.text = r.views_min || ""
            viewsMax.text = r.views_max || ""
            sortViews = r.sort_views || ""
            sortSubs = r.sort_subs || ""
            open()
        }
        function apply() {
            Archive.applyDetailRange(subsMin.text, subsMax.text, viewsMin.text, viewsMax.text,
                                     page._format, rangeSheet.sortViews, rangeSheet.sortSubs)
            rangeSheet.close()
        }

        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "x"; from: rangeSheet._offX; to: rangeSheet._restX; duration: Tokens.durSlow; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed }
        }
        exit: Transition {
            NumberAnimation { property: "x"; from: rangeSheet._restX; to: rangeSheet._offX; duration: Tokens.durMed; easing.type: Easing.InCubic }
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durMed }
        }

        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        header: Item {
            implicitHeight: shHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: shHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.primary, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.30)
                    C.IconGlyph { anchors.centerIn: parent; name: "tune"; size: 20; glyphColor: Theme.primary }
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    C.AppText {
                        text: I18n.tr("Filter by range")
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontSubtitle
                        color: Theme.text_strong
                    }
                    C.AppText {
                        text: I18n.tr("Type 1K, 2.5M … or tap a preset")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                }
                C.IconButton {
                    iconName: "close"
                    accent: Theme.on_surface_var
                    implicitWidth: 34; implicitHeight: 34
                    tip: I18n.tr("Close")
                    onClicked: rangeSheet.close()
                }
            }
        }

        // preset chip used in the sheet
        component Preset: AbstractButton {
            id: pr
            property string label: ""
            property bool on: false
            implicitHeight: 32
            implicitWidth: prLbl.implicitWidth + Tokens.space3 * 2
            HoverHandler { id: prHover; cursorShape: Qt.PointingHandCursor }
            background: Rectangle {
                radius: Tokens.radiusPill
                color: pr.on ? Theme.primary : prHover.hovered ? U.withAlpha(Theme.on_surface, 0.07) : U.withAlpha(Theme.on_surface, 0.035)
                border.width: 1
                border.color: pr.on ? Theme.primary : Theme.outline_variant
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
            contentItem: C.AppText {
                id: prLbl
                text: pr.label
                mono: true
                weight: Tokens.weightBold
                font.pixelSize: Tokens.fontCaption
                color: pr.on ? Theme.on_primary : Theme.on_surface
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        contentItem: Flickable {
            id: sheetFlick
            clip: true
            contentHeight: sheetCol.implicitHeight + Tokens.space5
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: sheetCol
                x: Tokens.space5
                width: sheetFlick.width - Tokens.space5 * 2
                spacing: Tokens.space6

                // subscribers (hidden for channel sections — one channel)
                ColumnLayout {
                    visible: !Archive.detailIsChannel
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    Row {
                        spacing: Tokens.space2
                        C.IconGlyph { name: "user"; size: 15; glyphColor: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        C.AppText { text: I18n.tr("Subscribers"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontBody; color: Theme.text_strong; anchors.verticalCenter: parent.verticalCenter }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.LineField { id: subsMin; Layout.fillWidth: true; Layout.preferredWidth: 1; placeholder: I18n.tr("min") + "  ·  100" }
                        C.AppText { text: "–"; color: Theme.outline }
                        C.LineField { id: subsMax; Layout.fillWidth: true; Layout.preferredWidth: 1; placeholder: I18n.tr("max") + "  ·  3K" }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Repeater {
                            model: [
                                { l: "< 1K", a: "", b: "1K" },
                                { l: "1K – 10K", a: "1K", b: "10K" },
                                { l: "10K – 100K", a: "10K", b: "100K" },
                                { l: "100K+", a: "100K", b: "" }
                            ]
                            Preset {
                                label: modelData.l
                                on: subsMin.text === modelData.a && subsMax.text === modelData.b
                                onClicked: {
                                    if (on) { subsMin.text = ""; subsMax.text = "" }
                                    else { subsMin.text = modelData.a; subsMax.text = modelData.b }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.AppText { text: I18n.tr("Order"); font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; Layout.fillWidth: true }
                        SegBar {
                            segHeight: 30
                            options: [ { label: I18n.tr("Off") }, { label: I18n.tr("Low → High") }, { label: I18n.tr("High → Low") } ]
                            current: rangeSheet.sortSubs === "asc" ? 1 : rangeSheet.sortSubs === "desc" ? 2 : 0
                            onPicked: (i) => rangeSheet.sortSubs = ["", "asc", "desc"][i]
                        }
                    }
                }

                // views
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.space3
                    Row {
                        spacing: Tokens.space2
                        C.IconGlyph { name: "visibility"; size: 15; glyphColor: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                        C.AppText { text: I18n.tr("Views"); weight: Tokens.weightBold; font.pixelSize: Tokens.fontBody; color: Theme.text_strong; anchors.verticalCenter: parent.verticalCenter }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.LineField { id: viewsMin; Layout.fillWidth: true; Layout.preferredWidth: 1; placeholder: I18n.tr("min") + "  ·  1M" }
                        C.AppText { text: "–"; color: Theme.outline }
                        C.LineField { id: viewsMax; Layout.fillWidth: true; Layout.preferredWidth: 1; placeholder: I18n.tr("max") + "  ·  " + I18n.tr("any") }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        Repeater {
                            model: [ { l: "100K+", a: "100K" }, { l: "1M+", a: "1M" }, { l: "10M+", a: "10M" }, { l: "100M+", a: "100M" } ]
                            Preset {
                                label: modelData.l
                                on: viewsMin.text === modelData.a && viewsMax.text === ""
                                onClicked: {
                                    if (on) viewsMin.text = ""
                                    else { viewsMin.text = modelData.a; viewsMax.text = "" }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.space2
                        C.AppText { text: I18n.tr("Order"); font.pixelSize: Tokens.fontCaption; color: Theme.on_surface_var; Layout.fillWidth: true }
                        SegBar {
                            segHeight: 30
                            options: [ { label: I18n.tr("Off") }, { label: I18n.tr("Low → High") }, { label: I18n.tr("High → Low") } ]
                            current: rangeSheet.sortViews === "asc" ? 1 : rangeSheet.sortViews === "desc" ? 2 : 0
                            onPicked: (i) => rangeSheet.sortViews = ["", "asc", "desc"][i]
                        }
                    }
                }

                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("An order set here overrides the Sort menu until you turn it off.")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.outline
                    wrapMode: Text.Wrap
                }
            }
        }

        footer: Item {
            implicitHeight: 50 + Tokens.space5 * 2
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.divider_h
            }
            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space2
                C.PrimaryButton {
                    variant: "ghost"
                    iconName: "restart_alt"
                    text: I18n.tr("Clear")
                    onClicked: {
                        page.applyRange({ subs_min: "", subs_max: "", views_min: "", views_max: "", sort_views: "", sort_subs: "" })
                        rangeSheet.close()
                    }
                }
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    iconName: "check"
                    text: I18n.tr("Apply")
                    onClicked: rangeSheet.apply()
                }
            }
        }
    }

    function openRename(gid, title) {
        renameDialog.pendingId = gid
        renameField.text = title || ""
        renameDialog.open()
    }

    Dialog {
        id: renameDialog
        property int pendingId: -1
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: Math.min(440, page.width - 80)
        padding: 0
        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: renameHead.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: renameHead
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.primary, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.30)
                    C.IconGlyph { anchors.centerIn: parent; name: "edit"; size: 20; glyphColor: Theme.primary }
                }
                C.AppText {
                    text: I18n.tr("Rename section")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
        contentItem: Item {
            implicitHeight: renameField.implicitHeight + Tokens.space5 * 2
            C.LineField {
                id: renameField
                x: Tokens.space5
                width: parent.width - Tokens.space5 * 2
                label: I18n.tr("Section name")
                labelIcon: "folder"
                hint: I18n.tr("Enter saves. The name shows up in the sections list and the archive header.")
                placeholder: I18n.tr("Section name")
                onAccepted: {
                    Archive.renameGroup(renameDialog.pendingId, text)
                    renameDialog.close()
                }
            }
        }
        footer: Item {
            implicitHeight: 50 + Tokens.space3
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                anchors.bottomMargin: Tokens.space5
                spacing: Tokens.space2
                Item { Layout.fillWidth: true }
                C.PrimaryButton {
                    variant: "ghost"
                    text: I18n.tr("Cancel")
                    onClicked: renameDialog.close()
                }
                C.PrimaryButton {
                    iconName: "check"
                    text: I18n.tr("Save")
                    onClicked: {
                        Archive.renameGroup(renameDialog.pendingId, renameField.text)
                        renameDialog.close()
                    }
                }
            }
        }
        onOpened: {
            renameField.forceActiveFocus()
            renameField.selectAll()
        }
    }

    Dialog {
        id: confirmDialog
        property string heading: ""
        property string body: ""
        property var action: null
        function ask(h, b, fn) { heading = h; body = b; action = fn; open() }
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: Math.min(440, page.width - 80)
        padding: 0
        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: warnRow1.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: warnRow1
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.30)
                    C.IconGlyph { anchors.centerIn: parent; name: "warning"; fill: true; size: 20; glyphColor: Theme.error }
                }
                C.AppText {
                    text: confirmDialog.heading
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }
        contentItem: C.AppText {
            text: confirmDialog.body
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
                    onClicked: confirmDialog.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete"
                    text: I18n.tr("Delete")
                    onClicked: {
                        confirmDialog.close()
                        if (confirmDialog.action) confirmDialog.action()
                    }
                }
            }
        }
    }

    function openConfirmDelete(g) {
        confirmDialog.ask(
            I18n.tr("Delete this section?"),
            I18n.tr("This permanently removes “{k}” and its {n} archived videos.")
                .replace("{k}", g.title || "—")
                .replace("{n}", g.itemCountText || "0"),
            function() { Archive.deleteGroup(g.id) })
    }
    function openConfirmDeleteCurrent() {
        confirmDialog.ask(
            I18n.tr("Delete this section?"),
            I18n.tr("This permanently removes “{k}” and its saved videos.")
                .replace("{k}", Archive.detailTitle),
            function() { Archive.deleteGroup(Archive.detailId) })
    }

    Dialog {
        id: confirmClear
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: Math.min(440, page.width - 80)
        padding: 0
        Overlay.modal: C.DialogScrim { }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Tokens.durMed; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast } }
        background: Rectangle {
            radius: Tokens.radiusXl
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }
        header: Item {
            implicitHeight: warnRow2.implicitHeight + Tokens.space5 * 2
            RowLayout {
                id: warnRow2
                anchors.fill: parent
                anchors.margins: Tokens.space5
                spacing: Tokens.space3
                Rectangle {
                    width: 40; height: 40; radius: Tokens.radiusMd
                    color: U.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.30)
                    C.IconGlyph { anchors.centerIn: parent; name: "warning"; fill: true; size: 20; glyphColor: Theme.error }
                }
                C.AppText {
                    text: I18n.tr("Clear the whole archive?")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle
                    color: Theme.text_strong
                    Layout.fillWidth: true
                }
            }
        }
        contentItem: C.AppText {
            text: I18n.tr("Every archived section and video will be permanently removed. This cannot be undone.")
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
                    onClicked: confirmClear.close()
                }
                C.PrimaryButton {
                    variant: "danger"
                    iconName: "delete_sweep"
                    text: I18n.tr("Clear all")
                    onClicked: { confirmClear.close(); Archive.clearAll() }
                }
            }
        }
    }

    FileDialog {
        id: exportDialog
        title: I18n.tr("Export section")
        fileMode: FileDialog.SaveFile
        nameFilters: ["CSV (*.csv)", "Excel (*.xlsx)", "JSON Lines (*.jsonl)"]
        onAccepted: Archive.exportCurrent(selectedFile.toString())
    }

    C.QualityPicker { id: qualityPicker; target: Archive }

    FolderDialog {
        id: thumbFolderDialog
        title: I18n.tr("Choose where to save thumbnails")
        onAccepted: {
            Archive.setThumbFolder(selectedFolder.toString())
            if (page._pendingThumbId !== "") {
                Archive.downloadThumb(page._pendingThumbId, page._pendingThumbTitle, page._pendingThumbShort)
                page._pendingThumbId = ""
                page._pendingThumbTitle = ""
                page._pendingThumbShort = false
            }
        }
    }

    C.Toast { id: toast; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 80 }
}
