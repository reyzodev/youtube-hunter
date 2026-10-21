import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// ── EditMenu (v3.40.1 · "Ember 2026") ──
// The right-click menu of every text box in the app, replacing Qt's stock
// TextField/TextArea menu (a flat black list with grey 2014-era icons).
//
// Attach it with the ContextMenu attached property (Qt 6.9+):
//
//     TextField {
//         id: field
//         T.ContextMenu.menu: C.EditMenu { editor: field }
//     }
//
// Design:
//   * The three actions people actually use — Cut / Copy / Paste — sit on
//     top as a row of tactile tiles, so the common case is one big target.
//   * History (Undo / Redo) and selection (Delete / Select All) follow as
//     rows with real keycaps for their shortcuts.
//   * One "spotlight" pill glides between rows instead of each row lighting
//     up on its own; its leading accent bar is the app's primary colour.
//   * A faint ember wash of the accent sits behind the tiles, the sheet has a
//     specular top edge and a deep soft shadow, and the content cascades in
//     row by row when the menu opens.
//   * Fully themed (dark/light, any accent), RTL-aware, keyboard driven
//     (↑ ↓ ← → / Home / End / Enter / Esc).
Menu {
    id: menu

    // The TextField / TextArea this menu edits.
    property Item editor: null

    parent: editor
    popupType: Popup.Item
    modal: false
    focus: true
    dim: false
    padding: 6
    margins: 10
    // Which corner sits on the pointer; _place() picks it per open.
    property int _origin: I18n.rtl ? Item.TopRight : Item.TopLeft
    transformOrigin: _origin

    // ── snapshot of the editor, taken when the menu opens ──
    // The menu takes focus, so the field's live state can shift under us;
    // every action runs against what the user saw when they right-clicked.
    property int _selStart: 0
    property int _selEnd: 0
    property bool _canPaste: false
    property bool _canUndo: false
    property bool _canRedo: false
    property int _length: 0

    readonly property bool _hasSel: _selEnd > _selStart
    readonly property bool _editable: !!editor && !editor.readOnly && editor.enabled
    readonly property bool _masked: !!editor && editor.echoMode !== undefined
                                     && editor.echoMode !== TextInput.Normal

    // index → enabled.  0 cut · 1 copy · 2 paste · 3 undo · 4 redo · 5 delete · 6 select all
    readonly property var _on: [
        _editable && _hasSel && !_masked,
        _hasSel && !_masked,
        _editable && _canPaste,
        _editable && _canUndo,
        _editable && _canRedo,
        _editable && _hasSel,
        _length > 0 && !(_selStart === 0 && _selEnd === _length)
    ]

    // Highlighted action (hover or keyboard), -1 = none.
    property int hi: -1

    // 0 → 1 over the open; drives the row-by-row cascade.
    property real reveal: 0
    function _rv(k) {
        var t = Math.max(0, Math.min(1, (menu.reveal - k * 0.06) / 0.6))
        return 1 - Math.pow(1 - t, 3)
    }

    readonly property color _ink: Theme.on_surface
    readonly property bool _dark: Theme.isDark

    // v3.40.3: open right where the user clicked. The stock ContextMenu
    // placement dropped the menu on the field's start edge (top-left in
    // English, top-right in Persian) instead of under the pointer.
    //   * English: the pointer is the menu's top-left corner (opens rightward)
    //   * Persian: the pointer is the menu's top-right corner (opens leftward)
    // and it flips to the other side / upward when it would leave the window.
    function _place() {
        var e = menu.editor
        if (!e) return
        var p = null
        if (typeof App !== "undefined" && App && App.cursorPos) {
            var g = App.cursorPos()
            p = e.mapFromGlobal(g.x, g.y)
        }
        // keyboard-invoked (Menu key / Shift+F10) or pointer outside the box:
        // fall back to the text caret
        if (!p || p.x < -2 || p.y < -2 || p.x > e.width + 2 || p.y > e.height + 2) {
            var cr = e.cursorRectangle
            p = cr ? Qt.point(cr.x, cr.y + cr.height) : Qt.point(0, e.height)
        }
        var w = menu.width > 0 ? menu.width : menu.implicitWidth
        var h = menu.height > 0 ? menu.height : menu.implicitHeight
        var win = e.Window.window
        var ww = win ? win.width : 1e6, wh = win ? win.height : 1e6
        var wp = e.mapToItem(null, p.x, p.y)
        var gap = menu.margins
        var openLeft = I18n.rtl
        if (!openLeft && wp.x + w > ww - gap) openLeft = true
        else if (openLeft && wp.x - w < gap) openLeft = false
        var openUp = wp.y + h > wh - gap && wp.y - h >= gap
        menu.x = openLeft ? p.x - w : p.x
        menu.y = openUp ? p.y - h : p.y
        menu._origin = openUp ? (openLeft ? Item.BottomRight : Item.BottomLeft)
                              : (openLeft ? Item.TopRight : Item.TopLeft)
    }

    onAboutToShow: {
        menu._place()
        var e = menu.editor
        if (e) {
            menu._selStart = e.selectionStart
            menu._selEnd = e.selectionEnd
            menu._canPaste = !!e.canPaste
            menu._canUndo = !!e.canUndo
            menu._canRedo = !!e.canRedo
            menu._length = e.length !== undefined ? e.length : (e.text || "").length
        }
        menu.hi = -1
        menu.reveal = 0
        revealAnim.restart()
    }
    onClosed: menu.hi = -1

    // Menu treats Items declared inside it as entries. The real content is the
    // custom contentItem below; this single invisible placeholder just keeps
    // count > 0, so nothing on Qt's side ever skips an "empty" menu.
    Item { visible: false; width: 0; height: 0 }

    function _step(dir) {
        var i = menu.hi < 0 ? (dir > 0 ? -1 : 7) : menu.hi
        for (var n = 0; n < 7; n++) {
            i = ((i + dir) % 7 + 7) % 7
            if (menu._on[i]) { menu.hi = i; return }
        }
    }

    function _run(i) {
        if (i < 0 || !menu._on[i]) return
        var e = menu.editor
        var s = menu._selStart, t = menu._selEnd
        menu.close()
        if (!e) return
        e.forceActiveFocus()
        if (t > s && i !== 6) e.select(s, t)
        switch (i) {
        case 0: e.cut(); break
        case 1: e.copy(); break
        case 2: e.paste(); break
        case 3: e.undo(); break
        case 4: e.redo(); break
        case 5: e.remove(s, t); break
        case 6: e.selectAll(); break
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Tokens.durFast; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 1; to: 0.96; duration: Tokens.durFast; easing.type: Easing.OutCubic }
    }

    // ── the sheet ──
    background: Item {
        implicitWidth: 256
        implicitHeight: 40

        // base + deep shadow (only this rectangle is layered)
        //
        // v3.40.2: the shadow sits on its own layered copy BEHIND the sheet.
        // `layer.enabled` hands the item's own drawing to the effect, so when
        // MultiEffect cannot run — the software renderer (no RHI / no GPU:
        // some VMs, old drivers, QT_QUICK_BACKEND=software) — a layered sheet
        // draws nothing at all and the menu is bare text floating on the page.
        // A plain sheet under it costs one rectangle and always paints.
        Rectangle {
            id: shadow
            anchors.fill: parent
            radius: Tokens.radiusLg + 1
            color: Theme.dropdown_bg
            border.width: 1
            border.color: menu._dark
                          ? U.mix(Theme.border, Theme.primary, 0.20)
                          : U.withAlpha(menu._ink, 0.10)
            layer.enabled: parent.height > 0 && parent.height <= 4096
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), menu._dark ? 0.62 : 0.18)
                shadowVerticalOffset: 14
                shadowBlur: 1.0
                shadowScale: 1.0
            }
        }

        Rectangle {
            id: sheet
            anchors.fill: parent
            radius: Tokens.radiusLg + 1
            color: Theme.dropdown_bg
            border.width: 1
            border.color: menu._dark
                          ? U.mix(Theme.border, Theme.primary, 0.20)
                          : U.withAlpha(menu._ink, 0.10)
        }

        // ember wash: the accent, barely there, glowing down from the top
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: sheet.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, menu._dark ? 0.11 : 0.06) }
                GradientStop { position: 0.42; color: U.withAlpha(Theme.primary, 0.0) }
            }
        }

        // specular top edge
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - sheet.radius * 2
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: menu._dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.9) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // ── the content ──
    contentItem: FocusScope {
        id: body
        focus: true
        implicitWidth: 244
        implicitHeight: stack.implicitHeight
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        NumberAnimation {
            id: revealAnim
            target: menu
            property: "reveal"
            from: 0; to: 1
            duration: 420
        }

        Keys.onPressed: (ev) => {
            const rtl = I18n.rtl
            switch (ev.key) {
            case Qt.Key_Down:  menu._step(+1); ev.accepted = true; break
            case Qt.Key_Up:    menu._step(-1); ev.accepted = true; break
            case Qt.Key_Right: menu._step(rtl ? -1 : +1); ev.accepted = true; break
            case Qt.Key_Left:  menu._step(rtl ? +1 : -1); ev.accepted = true; break
            case Qt.Key_Home:  menu.hi = -1; menu._step(+1); ev.accepted = true; break
            case Qt.Key_End:   menu.hi = -1; menu._step(-1); ev.accepted = true; break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space: menu._run(menu.hi); ev.accepted = true; break
            }
        }

        Column {
            id: stack
            width: parent.width
            spacing: 0

            // ── quick tiles: cut / copy / paste ──
            Row {
                id: tiles
                width: parent.width
                spacing: 6
                HoverHandler {
                    onHoveredChanged: if (!hovered && menu.hi >= 0 && menu.hi <= 2) menu.hi = -1
                }
                Tile { m: menu; idx: 0; icon: "scissors";      label: I18n.tr("Cut") }
                Tile { m: menu; idx: 1; icon: "content_copy";  label: I18n.tr("Copy") }
                Tile { m: menu; idx: 2; icon: "content_paste"; label: I18n.tr("Paste") }
            }

            Item { width: 1; height: 6 }
            Hairline { m: menu }
            Item { width: 1; height: 4 }

            // ── rows: history, then selection ──
            Item {
                id: list
                width: parent.width
                height: rows.implicitHeight

                HoverHandler {
                    onHoveredChanged: if (!hovered && menu.hi >= 3) menu.hi = -1
                }

                // The spotlight: one pill that glides to whichever row is lit.
                Rectangle {
                    id: spot
                    readonly property Item target: menu.hi === 3 ? rUndo
                                                  : menu.hi === 4 ? rRedo
                                                  : menu.hi === 5 ? rDel
                                                  : menu.hi === 6 ? rAll : null
                    readonly property bool danger: menu.hi === 5
                    property real ty: 0
                    onTargetChanged: if (target) ty = target.y
                    x: 0
                    y: ty
                    width: list.width
                    height: 38
                    radius: Tokens.radiusMd
                    opacity: target ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                    Behavior on y {
                        enabled: spot.opacity > 0.5
                        NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic }
                    }
                    readonly property color tint: danger ? Theme.error : Theme.primary
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(spot.tint, menu._dark ? (I18n.rtl ? 0.05 : 0.20) : (I18n.rtl ? 0.03 : 0.12)) }
                        GradientStop { position: 1.0; color: U.withAlpha(spot.tint, menu._dark ? (I18n.rtl ? 0.20 : 0.05) : (I18n.rtl ? 0.12 : 0.03)) }
                    }
                    border.width: 1
                    border.color: U.withAlpha(spot.tint, menu._dark ? 0.26 : 0.20)
                    Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                    // accent bar + its halo on the reading edge
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 22; radius: 4
                        color: U.withAlpha(spot.tint, 0.22)
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 16; radius: 2
                        color: spot.tint
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    }
                }

                Column {
                    id: rows
                    width: parent.width
                    spacing: 0
                    MenuRow { m: menu; id: rUndo; idx: 3; icon: "undo"; label: I18n.tr("Undo"); keys: ["Ctrl", "Z"] }
                    MenuRow { m: menu; id: rRedo; idx: 4; icon: "redo"; label: I18n.tr("Redo"); keys: ["Ctrl", "Y"] }
                    Item { width: 1; height: 4 }
                    Hairline { m: menu }
                    Item { width: 1; height: 4 }
                    MenuRow { m: menu; id: rDel; idx: 5; icon: "delete_outline"; label: I18n.tr("Delete"); keys: ["Del"]; danger: true }
                    MenuRow { m: menu; id: rAll; idx: 6; icon: "select_all"; label: I18n.tr("Select All"); keys: ["Ctrl", "A"] }
                }
            }
        }
    }

    // ───────────────────────── pieces ─────────────────────────

    // Faded hairline: claims the boundary between groups, fades at both ends.
    component Hairline: Rectangle {
        property QtObject m: null
        width: parent ? parent.width : 0
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.10 : 0.09) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Big tactile tile for cut / copy / paste.
    component Tile: Item {
        id: tile
        property QtObject m: null
        property int idx: 0
        property string icon: ""
        property string label: ""
        readonly property bool ok: !!m && m._on[idx]
        readonly property bool lit: ok && !!m && m.hi === idx
        readonly property real rv: m ? m._rv(idx) : 0

        width: parent ? (parent.width - 12) / 3 : 0
        height: 64
        opacity: (ok ? 1 : 0.32) * rv
        transform: Translate { y: (1 - tile.rv) * 6 }

        HoverHandler {
            enabled: tile.ok
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered) m.hi = tile.idx
        }
        TapHandler {
            id: tileTap
            enabled: tile.ok
            onTapped: m._run(tile.idx)
        }

        Rectangle {
            id: face
            anchors.fill: parent
            radius: Tokens.radiusMd
            scale: tileTap.pressed ? 0.95 : (tile.lit ? 1.0 : 0.985)
            Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
            color: tile.lit
                   ? U.withAlpha(Theme.primary, Theme.isDark ? 0.17 : 0.10)
                   : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.035 : 0.03)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            border.width: 1
            border.color: tile.lit
                          ? U.withAlpha(Theme.primary, Theme.isDark ? 0.50 : 0.40)
                          : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.07 : 0.08)
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

            // glass sheen on the upper half
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.55; color: "transparent" }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 6
                IconGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: tile.icon
                    size: 20
                    fill: tile.lit
                    glyphColor: tile.lit ? Theme.primary : Theme.on_surface
                }
                AppText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.label
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption
                    color: tile.lit ? Theme.text_strong : Theme.on_surface_var
                }
            }
        }
    }

    // List row with leading icon, label and trailing keycaps.
    component MenuRow: Item {
        id: menuRow
        property QtObject m: null
        property int idx: 0
        property string icon: ""
        property string label: ""
        property var keys: []
        property bool danger: false
        readonly property bool ok: !!m && m._on[idx]
        readonly property bool lit: ok && !!m && m.hi === idx
        readonly property real rv: m ? m._rv(idx) : 0
        readonly property color tint: danger ? Theme.error : Theme.primary

        width: parent ? parent.width : 0
        height: 38
        opacity: (ok ? 1 : 0.34) * rv
        transform: Translate { y: (1 - menuRow.rv) * 6 }

        HoverHandler {
            enabled: menuRow.ok
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered) m.hi = menuRow.idx
        }
        TapHandler {
            enabled: menuRow.ok
            onTapped: m._run(menuRow.idx)
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                name: menuRow.icon
                size: 18
                glyphColor: menuRow.lit ? menuRow.tint : Theme.on_surface_var
            }
            AppText {
                anchors.verticalCenter: parent.verticalCenter
                text: menuRow.label
                weight: menuRow.lit ? Tokens.weightDemiBold : Tokens.weightMedium
                color: menuRow.lit ? Theme.text_strong : Theme.on_surface
            }
        }

        // keycaps — always read left-to-right ("Ctrl Z"), even in Persian
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            LayoutMirroring.enabled: false
            Repeater {
                model: menuRow.keys
                // NB: the id must not be "row" — a Repeater delegate context
                // carries its own `row` / `column` (DelegateModel), which
                // shadowed the id and made both bindings undefined.
                Keycap { m: menuRow.m; k: modelData; lit: menuRow.lit }
            }
        }
    }

    // A small physical key: face + 1px darker lip underneath.
    component Keycap: Item {
        id: cap
        property QtObject m: null
        property string k: ""
        property bool lit: false
        width: Math.max(20, glyph.implicitWidth + 12)
        height: 21
        Rectangle {
            anchors.fill: parent
            radius: 5
            color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.10 : 0.12)
        }
        Rectangle {
            width: parent.width
            height: parent.height - 1.5
            radius: 5
            color: cap.lit
                   ? U.withAlpha(Theme.on_surface, Theme.isDark ? 0.09 : 0.05)
                   : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.035)
            border.width: 1
            border.color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.09)
            AppText {
                id: glyph
                anchors.centerIn: parent
                text: cap.k
                mono: true
                weight: Tokens.weightMedium
                font.pixelSize: Tokens.fontMicro
                horizontalAlignment: Text.AlignHCenter
                color: cap.lit ? Theme.on_surface_var : Theme.outline
            }
        }
    }
}
