import QtQuick
import NicheScope

// Language- and weight-aware text. Resolves the right font family through the
// FontBridge (Persian swaps FAMILY per weight; Latin stays on Hanken/JetBrains)
// so bold Persian renders with the real IRANYekanX weight face rather than a
// synthetic bold.
//
// Set `selectable: true` where the text is something a user may want to lift out
// with the mouse (blueprint fields, script lines, prompts). See the note on the
// overlay below for how that works without a second copy of the glyphs.
Text {
    id: root
    property int weight: Tokens.weightRegular
    property bool mono: false
    // Opt-in mouse selection + Ctrl+C. Off by default: a TextEdit grabs the
    // press, which would swallow clicks on every card and row that wraps its
    // label in an AppText.
    property bool selectable: false
    color: Theme.on_surface
    // text-aware: Persian inside the English UI renders in Vazir too (weight
    // snapped to a real Vazir face, see FontBridge.weightFor)
    font.family: Fonts.familyFor(mono ? "mono" : "body", weight, root.text)
    font.weight: Fonts.weightFor(weight, root.text)
    font.pixelSize: Tokens.fontBody
    renderType: Text.NativeRendering

    // Align to the LAYOUT START, and let the mirroring do the rest.
    //
    // Qt has a trap here that this line exists to defuse, and it took an A/B on
    // a real screen to pin down:
    //
    //   * left UNSET, Qt aligns by the STRING's own direction, so in Persian a
    //     Persian line hugs the right while a Latin one — an English channel
    //     name, a file name — hugs the far LEFT of the very same box. On the
    //     Monetize profile card that put the channel title at the left edge and
    //     its @handle at the right edge of one column, with the avatar stranded
    //     on the far side. One card, two edges.
    //   * set EXPLICITLY, LayoutMirroring swaps the enum: in a mirrored (RTL)
    //     item `Text.AlignLeft` draws at the visual RIGHT and `Text.AlignRight`
    //     draws at the visual LEFT. Measured on the same card: AlignLeft -> the
    //     title jumped to the right beside the avatar, AlignRight -> it sat at
    //     the left, AlignHCenter -> centred (HCenter is symmetric, so mirroring
    //     leaves it alone).
    //
    // So `Text.AlignLeft` is exactly "the reading edge", in both languages:
    // LTR draws it left, RTL mirrors it right. Writing the obvious-looking
    // `I18n.rtl ? AlignRight : AlignLeft` here would be backwards in a mirrored
    // item — that pattern is only correct where LayoutMirroring is switched off
    // (BlueprintPane, Teleprompter, the terminal), which is why it works there.
    // Anything that needs centring or a deliberate right-hand column still sets
    // horizontalAlignment itself, and that overrides this.
    horizontalAlignment: Text.AlignLeft

    // ── selection overlay ──
    // A Text item cannot select, so an invisible-ink TextEdit is laid exactly
    // over the real glyphs (color: "transparent"). At rest you only ever see
    // the Text underneath.
    //
    // v3.41.6 fix — "selected text shows twice, shifted down":
    //   * A Text honours `lineHeight` (the brief uses 1.22–1.4); a TextEdit
    //     has no such property and always stacks lines at 1.0. The overlay's
    //     lines therefore crept upward line by line, and the selected run was
    //     re-painted there in selectedTextColor — a second, misaligned copy.
    //   * Now the line height is mirrored onto the TextEdit's document from
    //     Python (TextLayout bridge, QTextBlockFormat), so both items stack
    //     lines identically, and
    //   * the overlay never paints glyphs at all: selectedTextColor is
    //     transparent too, so a selection is only a tint over the real text.
    //     Even if a metric ever drifted by a pixel, there is nothing to ghost.
    //   * wrapMode is passed through as-is (Text and TextEdit share the
    //     QTextOption values), instead of forcing WrapAtWordBoundaryOrAnywhere.
    Loader {
        active: root.selectable
        anchors.fill: parent
        sourceComponent: TextEdit {
            id: selEdit
            text: root.text
            font: root.font
            renderType: root.renderType
            horizontalAlignment: root.horizontalAlignment
            verticalAlignment: root.verticalAlignment
            wrapMode: root.wrapMode
            textFormat: TextEdit.PlainText
            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0

            readOnly: true
            selectByMouse: true
            // Invisible ink — see above. Both the resting and the selected
            // glyphs are transparent; only the selection tint is drawn.
            color: "transparent"
            selectedTextColor: "transparent"
            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g,
                                    Theme.primary.b, Theme.isDark ? 0.34 : 0.24)
            cursorVisible: false
            activeFocusOnPress: true
            // An I-beam is the only hint that this text can be dragged over.
            HoverHandler { cursorShape: Qt.IBeamCursor }

            function syncLines() {
                if (typeof TextLayout !== "undefined" && TextLayout)
                    TextLayout.syncLineHeight(selEdit.textDocument, root.lineHeight, root.lineHeightMode)
            }
            Component.onCompleted: Qt.callLater(selEdit.syncLines)
            // Setting `text` rebuilds the document (and drops its block
            // format), so re-sync after the new text has landed. Driven from
            // the Text side on purpose: the format change itself fires the
            // TextEdit's own textChanged, which would loop.
            Connections {
                target: root
                function onTextChanged() { Qt.callLater(selEdit.syncLines) }
                function onLineHeightChanged() { Qt.callLater(selEdit.syncLines) }
                function onLineHeightModeChanged() { Qt.callLater(selEdit.syncLines) }
            }
        }
    }
}
