import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import NicheScope
import "." as C
import "../Utils.js" as U

// The app's one pager. A rounded capsule holding « ‹ 1 2 … 27 › », where the
// active page is a filled red disc under a soft glow.
//
// Every page had grown its own chevron+"Page 3 of 9" strip, so they drifted in
// spacing, in whether they had first/last jumps, and in whether anything
// animated. This is the single implementation: give it `pageIndex` (0-based) and
// `pageCount`, and handle `requested(index)`.
//
//     C.Pager {
//         pageIndex: page.pageIndex
//         pageCount: page.pageCount
//         onRequested: (i) => { page.pageIndex = i; scroller.toTop() }
//     }
//
// It does NOT change `pageIndex` itself — the owner does, in the handler. That
// keeps the "turn the page, then scroll back to the top" pairing every call site
// needs from being duplicated inside here.
Item {
    id: root

    property int pageIndex: 0
    property int pageCount: 1
    // Show the ‹‹ / ›› jump-to-end buttons. Off for a short rail where the
    // chevrons alone are enough.
    property bool showEdgeJumps: true
    // How many numbers to keep either side of the current one before collapsing
    // the rest into an ellipsis.
    property int window: 1

    signal requested(int index)

    // Hidden entirely on a single page — a pager that can't go anywhere is noise.
    visible: pageCount > 1
    implicitWidth: capsule.implicitWidth
    implicitHeight: visible ? capsule.implicitHeight : 0

    // ── which slots to draw ──
    // Entries are either a page number or the string "gap". Always keeps the
    // first and last page reachable in one click, plus a window around the
    // current one, so the capsule's width stays stable as you page through a
    // long list instead of growing and shrinking under the pointer.
    readonly property var slots: {
        var n = root.pageCount
        var cur = root.pageIndex
        var out = []
        if (n <= 0) return out
        var want = {}
        want[0] = true
        want[n - 1] = true
        for (var d = -root.window; d <= root.window; d++) {
            var p = cur + d
            if (p >= 0 && p < n) want[p] = true
        }
        var keys = Object.keys(want).map(function (k) { return parseInt(k, 10) })
        keys.sort(function (a, b) { return a - b })
        for (var i = 0; i < keys.length; i++) {
            // A single skipped page is shown rather than replaced by an ellipsis
            // that is the same width — "1 … 3" hides less than it costs.
            if (i > 0 && keys[i] - keys[i - 1] === 2)
                out.push(keys[i] - 1)
            else if (i > 0 && keys[i] - keys[i - 1] > 2)
                out.push("gap")
            out.push(keys[i])
        }
        return out
    }

    function _go(i) {
        var t = Math.max(0, Math.min(root.pageCount - 1, i))
        if (t !== root.pageIndex) root.requested(t)
    }

    // ── the capsule ──
    Rectangle {
        id: capsule
        anchors.centerIn: parent
        implicitWidth: strip.implicitWidth + Tokens.space3 * 2
        implicitHeight: 52
        radius: Tokens.radiusPill
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        // Lifted off the page so the pager reads as a floating control rather
        // than another row of the list above it.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: U.withAlpha(Qt.rgba(0, 0, 0, 1), Theme.isDark ? 0.45 : 0.10)
            shadowVerticalOffset: 4
            shadowBlur: 0.7
            shadowScale: 1.0
        }

        Row {
            id: strip
            anchors.centerIn: parent
            spacing: Tokens.space1

            // RTL: the strip itself mirrors, so «first» lands on the right where
            // a Persian reader expects the start of the sequence — and the
            // GLYPHS have to mirror with it. Leaving them alone drew a
            // right-pointing chevron on a button that goes to the previous page.
            Arrow {
                glyph: I18n.rtl ? "last_page" : "first_page"
                visible: root.showEdgeJumps
                enabled: root.pageIndex > 0
                onTapped: root._go(0)
            }
            Arrow {
                glyph: I18n.rtl ? "chevron_right" : "chevron_left"
                enabled: root.pageIndex > 0
                onTapped: root._go(root.pageIndex - 1)
            }

            Repeater {
                model: root.slots
                delegate: Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: modelData === "gap" ? gapCell : numCell
                    // The delegate's own modelData isn't visible inside a Loader's
                    // component, so the page number rides across explicitly.
                    property int pageNum: modelData === "gap" ? -1 : modelData
                }
            }

            Arrow {
                glyph: I18n.rtl ? "chevron_left" : "chevron_right"
                enabled: root.pageIndex < root.pageCount - 1
                onTapped: root._go(root.pageIndex + 1)
            }
            Arrow {
                glyph: I18n.rtl ? "first_page" : "last_page"
                visible: root.showEdgeJumps
                enabled: root.pageIndex < root.pageCount - 1
                onTapped: root._go(root.pageCount - 1)
            }
        }
    }

    // ── an elided run of pages ──
    Component {
        id: gapCell
        Item {
            width: 30; height: 34
            C.AppText {
                anchors.centerIn: parent
                text: "···"
                weight: Tokens.weightBold
                color: Theme.outline
                // A row of dots is not prose — never mirror or re-space it.
                LayoutMirroring.enabled: false
            }
        }
    }

    // ── one page number ──
    // The active page is a filled red disc with a glow behind it; the rest are
    // flat numbers that tint on hover. Both share the same 34px box so the row
    // doesn't reflow when the active page moves.
    Component {
        id: numCell
        Item {
            id: cell
            // `parent` here is the Loader, which carries the page number.
            readonly property int num: parent ? parent.pageNum : 0
            readonly property bool active: cell.num === root.pageIndex
            width: 34; height: 34

            // Glow under the active disc. Drawn as a blurred sibling rather than
            // a layer on the disc itself so the number on top stays crisp.
            Rectangle {
                anchors.centerIn: parent
                width: 30; height: 30
                radius: 15
                color: Theme.primary
                opacity: cell.active ? 0.45 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 32
                    autoPaddingEnabled: true
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 30; height: 30
                radius: 15
                color: cell.active ? Theme.primary
                     : numHover.hovered ? U.withAlpha(Theme.primary, 0.10)
                     : U.withAlpha(Theme.primary, 0)
                scale: cell.active ? 1.0 : (numHover.hovered ? 1.06 : 1.0)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                Behavior on scale {
                    NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic }
                }

                C.AppText {
                    anchors.centerIn: parent
                    // 1-based for the reader; pageIndex stays 0-based in the API.
                    text: cell.num + 1
                    mono: true
                    weight: cell.active ? Tokens.weightExtraBold : Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontCaption + 1
                    color: cell.active ? Theme.on_primary
                         : numHover.hovered ? Theme.primary : Theme.on_surface_var
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                    // A page number is a number in every language.
                    LayoutMirroring.enabled: false
                }
            }

            HoverHandler {
                id: numHover
                enabled: !cell.active
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler { onTapped: root._go(cell.num) }
        }
    }

    // ── a chevron / edge-jump button ──
    // An inline component (not IconButton) because these are round, 34px, and
    // sit flush inside the capsule with no border of their own — IconButton's
    // bordered 40px tile would break the capsule's line.
    component Arrow: Item {
        id: arrow
        property string glyph: ""
        signal tapped()
        width: 34; height: 34
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        opacity: enabled ? 1 : 0.32
        Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: arrowHover.hovered && arrow.enabled
                   ? U.withAlpha(Theme.primary, 0.10) : U.withAlpha(Theme.primary, 0)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        C.IconGlyph {
            anchors.centerIn: parent
            name: arrow.glyph
            size: 17
            glyphColor: arrowHover.hovered && arrow.enabled
                        ? Theme.primary : Theme.on_surface_var
            Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
        }
        HoverHandler {
            id: arrowHover
            enabled: arrow.enabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: arrow.enabled
            onTapped: arrow.tapped()
        }
    }
}
