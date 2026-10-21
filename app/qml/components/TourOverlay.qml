import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Layouts
import QtQuick.Window
import NicheScope
import "." as C
import "../Utils.js" as U

// v3.41 — the guided tour, redesigned ("Lock-on" tour).
//
// The tour now speaks the same visual language as the brand mark and the
// theme switch: every target gets a HUNTER VIEWFINDER, four accent brackets
// that snap onto it with a small overshoot, over a soft breathing halo. The
// explanation card is a single premium sheet:
//
//   ┌──────────────────────────────────────┐
//   │ ▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░░░░░░░░░░░ │  segmented progress (one per stop)
//   │ STEP 3 / 12                       ✕  │
//   │ Scraper: pull the raw data           │  title, 20px
//   │ Point it at a channel URL…           │  body, 14px
//   │ [←][→] [Esc]              (‹)  Next →│  keycaps · back · next key
//   └──────────────────▲───────────────────┘
//                      └ notch pointing at the target
//
// The first step (no target) is a centred HERO card with the live mark, the
// tour length and a single "Start the tour" call to action.
//
// Motion: the overlay fades in, the card glides between targets, its content
// cross-fades with an 8px rise on every step, the spotlight morphs to the next
// target and the brackets re-lock. Placement now tries below → above → beside
// (tall targets like the nav rail get the card NEXT to them, not on top).
//
// Unchanged contract (Main.qml + the offscreen harness rely on it):
// running / index / count / steps / hole / hasHole / start() / next() /
// back() / stop() / finished(). Targets are still resolved by objectName when a
// step is shown, a step on another page navigates first, and a missing target
// just shows a centred card: the tour never dead-ends.
Item {
    id: root
    anchors.fill: parent
    visible: running || _closing
    enabled: running
    z: 950

    property bool running: false
    property int index: 0
    // [{page, target, title, body}] — `target` is an objectName, `page` is a
    // StackLayout index to switch to first (both optional).
    property var steps: []

    readonly property int count: steps ? steps.length : 0
    readonly property var step: (index >= 0 && index < count) ? steps[index] : null

    // What the CARD shows. Lags `index` by the length of the content
    // cross-fade, so the old text fades out before the new one rises in.
    property int shownIndex: 0
    readonly property var shownStep: (shownIndex >= 0 && shownIndex < count) ? steps[shownIndex] : null
    readonly property bool hero: shownIndex === 0 && !!shownStep && !shownStep.target
    readonly property bool isLast: index === count - 1

    property bool _closing: false
    readonly property bool _rtl: I18n.rtl

    signal finished()

    function start() {
        if (count === 0) return
        closeAnim.stop()
        _closing = false
        index = 0
        shownIndex = 0
        _lockedFor = -1
        cardBody.opacity = 1
        cardBody.rise = 0
        running = true
        _show(0)
        introAnim.restart()
        root.forceActiveFocus()
    }

    function stop() {
        if (!running) return
        running = false
        settleTimer.stop()
        _closing = true
        closeAnim.restart()
        App.markTourSeen()
        root.finished()
    }

    function next() { if (!running) return; if (index < count - 1) _show(index + 1); else stop() }
    function back() { if (!running) return; if (index > 0) _show(index - 1) }

    onIndexChanged: if (running && shownIndex !== index) contentSwap.restart()

    // ── target resolution ──
    // The spotlight rect, in this overlay's coordinates. width < 0 means "no
    // target" — the step then renders as a plain centred card.
    property rect hole: Qt.rect(0, 0, -1, -1)
    readonly property bool hasHole: hole.width > 0 && hole.height > 0
    readonly property int holePad: 8
    readonly property int holeRadius: Tokens.radiusXl

    // true for one frame when the spotlight appears from nothing, so it lands
    // on its target instead of flying in from the previous (stale) rect
    property bool _snap: true
    property int _lockedFor: -1

    function _findByName(item, name) {
        if (!item || !name) return null
        if (item.objectName === name) return item
        const kids = item.children
        for (var i = 0; i < kids.length; i++) {
            const found = _findByName(kids[i], name)
            if (found) return found
        }
        return null
    }

    function _setHole(r) {
        const had = root.hasHole
        const appearing = !had && r.width > 0 && r.height > 0
        if (appearing) root._snap = true
        root.hole = r
        // re-lock the brackets only when the TARGET changes, not on every
        // re-measure (a window resize re-measures each frame)
        if (!root.hasHole) root._lockedFor = -1
        else if (root._lockedFor !== root.index) { root._lockedFor = root.index; lockAnim.restart() }
        if (appearing) Qt.callLater(function() { root._snap = false })
    }

    function _resolveHole() {
        const s = root.step
        if (!s || !s.target) { _setHole(Qt.rect(0, 0, -1, -1)); return }
        const win = Window.window
        const target = _findByName(win ? win.contentItem : null, s.target)
        if (!target || target.width <= 0 || !target.visible) {
            _setHole(Qt.rect(0, 0, -1, -1))
            return
        }
        const p = target.mapToItem(root, 0, 0)
        // Clamp into the window: a target inside a scroll view is routinely
        // taller than the viewport, and an unclamped rect would put the
        // spotlight (and the card placed off it) partly off screen.
        const x1 = Math.max(0, p.x - holePad)
        const y1 = Math.max(0, p.y - holePad)
        const x2 = Math.min(root.width, p.x + target.width + holePad)
        const y2 = Math.min(root.height, p.y + target.height + holePad)
        if (x2 - x1 < 8 || y2 - y1 < 8) {
            _setHole(Qt.rect(0, 0, -1, -1))
            return
        }
        _setHole(Qt.rect(x1, y1, x2 - x1, y2 - y1))
    }

    function _show(i) {
        index = i
        const s = root.steps[i]
        if (s && s.page !== undefined && s.page !== App.currentPage) {
            // clear the old spotlight while the new page lays out
            _setHole(Qt.rect(0, 0, -1, -1))
            App.goto(s.page)
            settleTimer.restart()
        } else {
            _resolveHole()
        }
    }

    // Gives a freshly-switched page a moment to lay out before its target is
    // measured; without this the hole lands on a zero-size item.
    Timer {
        id: settleTimer
        interval: 260
        onTriggered: root._resolveHole()
    }

    onWidthChanged: if (running) _resolveHole()
    onHeightChanged: if (running) _resolveHole()

    // ── overlay in / out ──
    NumberAnimation {
        id: introAnim
        target: root; property: "opacity"
        from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        ScriptAction { script: { root._closing = false; root.opacity = 1 } }
    }

    // ── step content cross-fade ──
    SequentialAnimation {
        id: contentSwap
        NumberAnimation { target: cardBody; property: "opacity"; to: 0; duration: 90; easing.type: Easing.InQuad }
        ScriptAction { script: { root.shownIndex = root.index; cardBody.rise = 10 } }
        ParallelAnimation {
            NumberAnimation { target: cardBody; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: cardBody; property: "rise"; to: 0; duration: 340; easing.type: Easing.OutQuint }
        }
    }

    // Swallow every click while the tour is up: the reader follows the tour
    // rather than poking the UI underneath it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: (m) => m.accepted = true
        onWheel: (w) => w.accepted = true
    }

    // ── the spotlight geometry ──
    // One animated rect that the mask, the frame, the halo and the brackets
    // all follow, so they can never drift apart mid-morph.
    Item {
        id: spot
        x: root.hasHole ? root.hole.x : root.width / 2
        y: root.hasHole ? root.hole.y : root.height / 2
        width: root.hasHole ? root.hole.width : 0
        height: root.hasHole ? root.hole.height : 0
        Behavior on x { enabled: !root._snap; NumberAnimation { duration: 360; easing.type: Easing.OutQuint } }
        Behavior on y { enabled: !root._snap; NumberAnimation { duration: 360; easing.type: Easing.OutQuint } }
        Behavior on width { enabled: !root._snap; NumberAnimation { duration: 360; easing.type: Easing.OutQuint } }
        Behavior on height { enabled: !root._snap; NumberAnimation { duration: 360; easing.type: Easing.OutQuint } }
    }

    // ── the dim, with a REAL rounded hole cut out of it ──
    // v3.41.1: the hole is geometry, not a mask. The earlier dim layer was
    // masked through MultiEffect (maskSource + maskInverted). On drivers where
    // the mask texture is not refreshed, or where MultiEffect quietly falls back
    // (software rasterizer, VM, some Intel/AMD drivers), the mask came back
    // empty and the dim covered the target too: the spotlit section looked as
    // dark and "blurry" as everything else. Now the dim is ONE Shape: the
    // window rect plus a rounded-rect sub-path, filled even-odd, so the target
    // is never painted over. No offscreen layer, no shader, works everywhere.
    readonly property color _dim: Theme.isDark ? Qt.rgba(0.012, 0.012, 0.02, 0.72)
                                               : Qt.rgba(0.05, 0.05, 0.08, 0.48)
    // hole geometry the paths follow (parked off-screen when there's no target)
    readonly property real _hx: root.hasHole ? spot.x : -4000
    readonly property real _hy: root.hasHole ? spot.y : -4000
    readonly property real _hw: root.hasHole ? Math.max(2, spot.width) : 2
    readonly property real _hh: root.hasHole ? Math.max(2, spot.height) : 2
    readonly property real _hr: Math.min(root.holeRadius, _hw / 2, _hh / 2)

    // (inline components can't see `root`, so the geometry is passed in)
    component HolePath: ShapePath {
        property real ow: 0
        property real oh: 0
        property real hx: -4000
        property real hy: -4000
        property real hw: 2
        property real hh: 2
        property real hr: 0
        fillRule: ShapePath.OddEvenFill
        strokeColor: "transparent"
        strokeWidth: -1
        // outer: the whole overlay
        startX: 0; startY: 0
        PathLine { x: ow; y: 0 }
        PathLine { x: ow; y: oh }
        PathLine { x: 0; y: oh }
        PathLine { x: 0; y: 0 }
        // inner: the rounded spotlight
        PathMove { x: hx + hr; y: hy }
        PathLine { x: hx + hw - hr; y: hy }
        PathArc  { x: hx + hw; y: hy + hr; radiusX: hr; radiusY: hr }
        PathLine { x: hx + hw; y: hy + hh - hr }
        PathArc  { x: hx + hw - hr; y: hy + hh; radiusX: hr; radiusY: hr }
        PathLine { x: hx + hr; y: hy + hh }
        PathArc  { x: hx; y: hy + hh - hr; radiusX: hr; radiusY: hr }
        PathLine { x: hx; y: hy + hr }
        PathArc  { x: hx + hr; y: hy; radiusX: hr; radiusY: hr }
    }

    Shape {
        id: dimShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // the dim itself
        HolePath { ow: root.width; oh: root.height; hx: root._hx; hy: root._hy; hw: root._hw; hh: root._hh; hr: root._hr; fillColor: root._dim }
        // a whisper of accent pooling at the top, so the overlay reads as lit
        // glass rather than a flat grey sheet (same hole, so it never tints
        // the target either)
        HolePath {
            ow: root.width; oh: root.height; hx: root._hx; hy: root._hy; hw: root._hw; hh: root._hh; hr: root._hr
            fillColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: root.height * 0.55
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.05) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }
    }

    // ── spotlight: frame + breathing halo + viewfinder brackets ──
    property real lockT: 1
    NumberAnimation {
        id: lockAnim
        target: root; property: "lockT"
        from: 0; to: 1; duration: 520
        easing.type: Easing.OutBack; easing.overshoot: 1.7
    }

    Item {
        id: spotFx
        x: spot.x; y: spot.y
        width: spot.width; height: spot.height
        opacity: root.hasHole ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

        // soft halo just outside the frame, breathing slowly
        Rectangle {
            id: halo
            anchors.fill: parent
            anchors.margins: -5
            radius: root.holeRadius + 5
            color: "transparent"
            border.width: 5
            border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.20 : 0.16)
            antialiasing: true
            SequentialAnimation on opacity {
                running: root.running && Tokens.appActive
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.35; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
        // the hairline frame
        Rectangle {
            anchors.fill: parent
            radius: root.holeRadius
            color: "transparent"
            border.width: 1.5
            border.color: U.withAlpha(Theme.primary, 0.85)
            antialiasing: true
        }

        // viewfinder brackets: snap in from a wider stance on every new target
        Repeater {
            model: [[-1, -1], [1, -1], [1, 1], [-1, 1]]
            delegate: Item {
                id: br
                required property var modelData
                readonly property real sx: modelData[0]
                readonly property real sy: modelData[1]
                readonly property real off: 7 + 16 * (1 - root.lockT)
                width: 16; height: 16
                x: sx < 0 ? -off : spotFx.width + off - width
                y: sy < 0 ? -off : spotFx.height + off - height
                opacity: Math.min(1, root.lockT * 1.6)
                Rectangle {
                    width: 16; height: 2.5; radius: 1.25
                    y: br.sy < 0 ? 0 : 13.5
                    color: Theme.primary
                    antialiasing: true
                }
                Rectangle {
                    width: 2.5; height: 16; radius: 1.25
                    x: br.sx < 0 ? 0 : 13.5
                    color: Theme.primary
                    antialiasing: true
                }
            }
        }
    }

    // ── placement ──
    readonly property int cardGap: 22
    readonly property int edge: Tokens.space4
    readonly property int cardW: Math.max(280, Math.min(hero ? 468 : 404, root.width - edge * 2))
    readonly property int cardPad: Tokens.space5
    readonly property int cardInnerW: cardW - cardPad * 2

    // {x, y, side}: side ∈ below | above | right | left | none
    function _placement(h, has, w, ch, W, H) {
        const m = root.edge, g = root.cardGap
        if (!has || root.hero) return { x: (W - w) / 2, y: (H - ch) / 2, side: "none" }
        const cx = h.x + h.width / 2, cy = h.y + h.height / 2
        const clampX = Math.max(m, Math.min(W - w - m, cx - w / 2))
        const clampY = Math.max(m, Math.min(H - ch - m, cy - ch / 2))
        if (h.y + h.height + g + ch <= H - m) return { x: clampX, y: h.y + h.height + g, side: "below" }
        if (h.y - g - ch >= m)                 return { x: clampX, y: h.y - g - ch, side: "above" }
        if (h.x + h.width + g + w <= W - m)    return { x: h.x + h.width + g, y: clampY, side: "right" }
        if (h.x - g - w >= m)                  return { x: h.x - g - w, y: clampY, side: "left" }
        return { x: (W - w) / 2, y: H - ch - m, side: "none" }
    }
    readonly property var _pl: _placement(hole, hasHole, cardW, cardBody.implicitHeight + cardPad * 2, width, height)

    // ── the card ──
    C.GlassPanel {
        id: card
        width: root.cardW
        height: cardBody.implicitHeight + root.cardPad * 2
        radius_: Tokens.radiusXl
        elevation: 2.2
        x: root._pl.x
        y: root._pl.y
        Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }

        // entrance: a small lift and settle
        scale: root.running ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }

        LayoutMirroring.enabled: root._rtl
        LayoutMirroring.childrenInherit: true

        // accent wash across the top of the sheet
        Rectangle {
            id: wash
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: Math.min(parent.height - 2, root.hero ? 220 : 120)
            radius: card.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.13 : 0.07) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }

        // notch pointing at the target. Drawn BEHIND the sheet (negative z),
        // so only the half that sticks out shows, border included.
        Rectangle {
            id: notch
            z: -0.5
            visible: root._pl.side !== "none"
            width: 14; height: 14
            rotation: 45
            // match the accent wash at the point where the notch meets the sheet
            readonly property real _washK: Theme.isDark ? 0.13 : 0.07
            readonly property real _washAt: root._pl.side === "below" ? 1
                                          : root._pl.side === "above" ? 0
                                          : Math.max(0, 1 - (_cyIn + height / 2) / wash.height)
            color: U.mix(Theme.panel_bg, Theme.primary, _washK * _washAt)
            border.width: 1
            border.color: Theme.border
            antialiasing: true
            readonly property real _cxIn: Math.max(22, Math.min(card.width - 22, spot.x + spot.width / 2 - card.x)) - width / 2
            readonly property real _cyIn: Math.max(22, Math.min(card.height - 22, spot.y + spot.height / 2 - card.y)) - height / 2
            x: root._pl.side === "right" ? -width / 2
             : root._pl.side === "left" ? card.width - width / 2
             : _cxIn
            y: root._pl.side === "below" ? -height / 2
             : root._pl.side === "above" ? card.height - height / 2
             : _cyIn
        }

        ColumnLayout {
            id: cardBody
            property real rise: 0
            transform: Translate { y: cardBody.rise }
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.cardPad
            spacing: 0

            // ── HERO (first step) ──
            Item {
                visible: root.hero
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                Layout.bottomMargin: Tokens.space3
                // bloom
                Repeater {
                    model: [86, 62, 42]
                    Rectangle {
                        anchors.centerIn: parent
                        width: modelData; height: modelData; radius: modelData / 2
                        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.05)
                    }
                }
                C.BrandMark {
                    id: heroMark
                    anchors.centerIn: parent
                    width: 54
                    height: Math.round(54 * 812 / 738)
                    rim: true
                    SequentialAnimation on scale {
                        running: root.running && root.hero && Tokens.appActive
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 1.045; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.045; to: 1; duration: 1600; easing.type: Easing.InOutSine }
                    }
                }
            }

            // ── segmented progress (regular steps) ──
            Item {
                id: track
                visible: !root.hero
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                Layout.bottomMargin: Tokens.space4
                readonly property int gap: 4
                readonly property real segW: root.count > 0 ? (width - gap * (root.count - 1)) / root.count : 0
                Row {
                    anchors.fill: parent
                    spacing: track.gap
                    Repeater {
                        model: root.count
                        Rectangle {
                            required property int index
                            width: track.segW; height: 3; radius: 1.5
                            color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.18 : 0.16)
                            Rectangle {
                                height: parent.height; radius: parent.radius
                                width: index <= root.index ? parent.width : 0
                                color: index === root.index ? Theme.primary : U.withAlpha(Theme.primary, 0.55)
                                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutQuint } }
                            }
                        }
                    }
                }
            }

            // eyebrow + close
            RowLayout {
                visible: !root.hero
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.space2
                spacing: Tokens.space2
                C.AppText {
                    Layout.fillWidth: true
                    text: I18n.tr("step {i} / {n}")
                              .replace("{i}", root.shownIndex + 1)
                              .replace("{n}", root.count)
                    mono: I18n.lang !== "fa"
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontMicro
                    font.capitalization: I18n.lang === "fa" ? Font.MixedCase : Font.AllUppercase
                    font.letterSpacing: I18n.lang === "fa" ? 0 : 1.4
                    color: Theme.primary
                }
                C.IconButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    iconName: "close"
                    glyphSize: 15
                    tip: I18n.tr("Skip tour")
                    onClicked: root.stop()
                }
            }

            // title
            C.AppText {
                text: root.shownStep ? root.shownStep.title : ""
                weight: Tokens.weightExtraBold
                font.pixelSize: root.hero ? Tokens.fontDisplay : 20
                color: Theme.text_strong
                wrapMode: Text.Wrap
                horizontalAlignment: root.hero ? Text.AlignHCenter : Text.AlignLeft
                Layout.fillWidth: true
                Layout.preferredWidth: root.cardInnerW
                Layout.bottomMargin: Tokens.space2
            }
            // body
            C.AppText {
                text: root.shownStep ? root.shownStep.body : ""
                color: Theme.on_surface_var
                font.pixelSize: Tokens.fontBody
                lineHeight: 1.5
                wrapMode: Text.Wrap
                horizontalAlignment: root.hero ? Text.AlignHCenter : Text.AlignLeft
                Layout.fillWidth: true
                Layout.preferredWidth: root.cardInnerW
            }

            // hero meta chips
            Row {
                visible: root.hero
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.space4
                spacing: Tokens.space2
                Repeater {
                    model: [
                        { icon: "route", text: I18n.tr("{n} stops").replace("{n}", Math.max(0, root.count - 1)) },
                        { icon: "hourglass_empty", text: I18n.tr("about a minute") }
                    ]
                    Rectangle {
                        required property var modelData
                        height: 28
                        width: chipRow.implicitWidth + Tokens.space3 * 2
                        radius: 14
                        color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.08 : 0.06)
                        border.width: 1
                        border.color: Theme.border
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            C.IconGlyph {
                                name: modelData.icon
                                size: 14
                                glyphColor: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            C.AppText {
                                text: modelData.text
                                font.pixelSize: Tokens.fontCaption
                                weight: Tokens.weightMedium
                                color: Theme.on_surface
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ── actions: regular steps ──
            RowLayout {
                visible: !root.hero
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space5
                spacing: Tokens.space2

                // keycap hints (hidden on a narrow card)
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4
                    visible: root.cardW >= 360
                    Keycap { label: root._rtl ? "→" : "←" }
                    Keycap { label: root._rtl ? "←" : "→" }
                    Item { width: 4; height: 1 }
                    Keycap { label: "Esc" }
                }
                Item { Layout.fillWidth: true }

                C.IconButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    iconName: root._rtl ? "chevron_right" : "chevron_left"
                    glyphSize: 18
                    tip: I18n.tr("Back")
                    enabled: root.index > 0
                    opacity: enabled ? 1 : 0.35
                    onClicked: root.back()
                }
                NextKey {
                    text: root.isLast ? I18n.tr("Finish") : I18n.tr("Next")
                    iconName: root.isLast ? "check" : (root._rtl ? "arrow_back" : "arrow_forward")
                    onClicked: root.next()
                }
            }

            // ── actions: hero ──
            ColumnLayout {
                visible: root.hero
                Layout.fillWidth: true
                Layout.topMargin: Tokens.space5
                spacing: Tokens.space2
                NextKey {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    text: I18n.tr("Start the tour")
                    iconName: root._rtl ? "arrow_back" : "arrow_forward"
                    onClicked: root.next()
                }
                C.PrimaryButton {
                    Layout.fillWidth: true
                    variant: "ghost"
                    implicitHeight: 40
                    text: I18n.tr("Not now")
                    onClicked: root.stop()
                }
            }
        }
    }

    // ── small building blocks ──
    component Keycap: Rectangle {
        property string label: ""
        height: 22
        width: Math.max(22, keyText.implicitWidth + 12)
        radius: 6
        color: U.withAlpha(Theme.on_surface_var, Theme.isDark ? 0.07 : 0.05)
        border.width: 1
        border.color: Theme.border
        // the key's "travel": a slightly heavier bottom edge
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 3; anchors.rightMargin: 3
            height: 1
            color: U.withAlpha(Theme.on_surface_var, 0.22)
        }
        C.AppText {
            id: keyText
            anchors.centerIn: parent
            text: parent.label
            mono: true
            font.pixelSize: Tokens.fontMicro
            color: Theme.on_surface_var
        }
    }

    // The forward key: accent face, glass top edge, and an arrow that leans
    // forward on hover.
    component NextKey: AbstractButton {
        id: nk
        property string iconName: ""
        implicitHeight: 40
        implicitWidth: Math.max(112, nkRow.implicitWidth + Tokens.space5 * 2)
        hoverEnabled: true
        scale: pressed ? Tokens.pressScale : 1
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        background: Rectangle {
            radius: Tokens.radiusMd
            gradient: Gradient {
                GradientStop { position: 0.0; color: nk.hovered ? Theme.primary_hover : Theme.primary }
                GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
            }
            // glass top edge
            Rectangle {
                anchors.top: parent.top; anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.radius * 2; height: 1
                color: Qt.rgba(1, 1, 1, 0.28)
            }
            // accent halo under the key
            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.margins: -3
                anchors.topMargin: 2
                anchors.bottomMargin: -6
                radius: parent.radius + 3
                color: U.withAlpha(Theme.primary, nk.hovered ? 0.30 : 0.18)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            }
        }

        contentItem: Item {
            implicitWidth: nkRow.implicitWidth
            implicitHeight: nkRow.implicitHeight
            Row {
                id: nkRow
                anchors.centerIn: parent
                spacing: Tokens.space2
                C.AppText {
                    text: nk.text
                    weight: Tokens.weightBold
                    color: Theme.on_primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                C.IconGlyph {
                    name: nk.iconName
                    visible: nk.iconName !== ""
                    size: 16
                    fill: true
                    glyphColor: Theme.on_primary
                    anchors.verticalCenter: parent.verticalCenter
                    transform: Translate {
                        x: nk.hovered && nk.iconName !== "check" ? (I18n.rtl ? -3 : 3) : 0
                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    // ── keyboard ──
    // Esc skips, Enter advances; the arrow keys follow reading direction
    // (in Persian, ← is forward).
    focus: running
    Keys.onEscapePressed: root.stop()
    Keys.onReturnPressed: root.next()
    Keys.onEnterPressed: root.next()
    Keys.onRightPressed: root._rtl ? root.back() : root.next()
    Keys.onLeftPressed: root._rtl ? root.next() : root.back()
}
