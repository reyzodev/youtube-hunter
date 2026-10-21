import QtQuick
import QtQuick.Controls.Basic
import NicheScope
import "../Utils.js" as U

// A checkable sidebar navigation row: a leading icon that recolours + fills, a
// label, and (when active) a tinted pill with a red accent bar pinned to the
// window's left edge.
//
// The active pill + bar for the nav LIST is drawn once by a shared sliding
// indicator in Sidebar.qml, so it glides between rows on a single clock. This
// button then only draws a hover fill and recolours its own glyph/label — timed
// at durMed to match the indicator's slide exactly, so nothing trails.
//
// The pinned Settings footer row sits OUTSIDE that list, so it sets
// `selfIndicator: true` and draws its own pill + bar (same durMed timing).
AbstractButton {
    id: root
    property string iconName: ""
    property bool collapsed: false
    // Draw our own active pill + accent bar (footer Settings row) rather than
    // relying on the shared sliding indicator (nav-list rows).
    property bool selfIndicator: false
    // Distance from this button's left edge OUT to the window edge, so the red
    // accent bar can sit flush against it. The Sidebar passes its layout margin.
    property int railInset: 0

    // NOT checkable. `checked` is driven purely by the Sidebar's
    // `App.currentPage === page` binding, so the row's highlight can never
    // disagree with the page actually on screen. With `checkable: true` a SECOND
    // click on the active row toggled `checked` off — and since App.goto() treats
    // a re-select of the current page as a no-op, the page stayed put while the
    // row visually deselected itself, which is exactly the "click twice and it
    // falls out of the selection" bug.
    checkable: false
    hoverEnabled: true
    height: Tokens.navButtonHeight
    // implicitHeight as well as height: inside a Column the explicit `height`
    // wins, but inside a ColumnLayout the layout owns height and reads
    // implicitHeight instead — without this the footer Settings row collapsed to
    // its label's height while the nav rows (in a plain Column) stayed 46px.
    implicitHeight: Tokens.navButtonHeight
    implicitWidth: parent ? parent.width : 200

    // Press-in feedback, scaled to the size of the thing being pressed. A flat
    // 3% looked right on the 250px-wide expanded row and vanished on the
    // collapsed rail: 0.97 of a ~60px square is under 2px of travel, so a click
    // on a collapsed row read as nothing happening at all. The collapsed rail
    // gets the deeper press the icon-only tiles elsewhere use (IconButton is at
    // 0.94, the title-bar glyphs at 0.92).
    // Shared icon ink (both layouts), eased so hover/active recolours glide.
    property color _iconColor: checked ? Theme.primary : hovered ? Theme.on_surface : Theme.on_surface_var
    Behavior on _iconColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

    scale: pressed ? (collapsed ? 0.90 : 0.97) : 1.0
    Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

    // Pointing-hand cursor — a flat nav row gives no other hint that it's
    // clickable. HoverHandler rather than a MouseArea so it never competes with
    // the button's own press handling.
    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    background: Item {
        // Hover + press fill (always drawn). The checked pill for nav rows is the
        // shared indicator behind this button, which shows through this
        // transparent fill.
        //
        // Press has its own, stronger tint rather than relying on the scale alone.
        // On a collapsed rail the row is an icon-only square, and a 3% shrink of
        // a lone glyph is invisible — clicking a collapsed nav row read as
        // nothing happening, while the same click on the expanded rail (a wide
        // row with a visible fill) clearly pressed in. Drawn for the checked row
        // too: re-clicking the section you are already on is a no-op
        // (App.goto ignores it), but the press still has to acknowledge the
        // click, which the hover fill deliberately doesn't do while checked.
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusMd
            color: root.pressed ? Theme.hover_bg_strong
                   : (root.hovered && !root.checked ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0))
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
        }

        // Self-drawn active pill (footer Settings row only).
        Rectangle {
            visible: root.selfIndicator
            anchors.fill: parent
            radius: Tokens.radiusMd
            color: "transparent"
            opacity: root.checked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: I18n.rtl ? U.withAlpha(Theme.primary_deep, 0.04) : U.withAlpha(Theme.primary, 0.20) }
                GradientStop { position: 1.0; color: I18n.rtl ? U.withAlpha(Theme.primary, 0.20) : U.withAlpha(Theme.primary_deep, 0.04) }
            }
            border.width: 1
            border.color: U.withAlpha(Theme.primary, 0.18)

            // Red edge accent, flush with the window's left edge.
            Rectangle {
                width: 3
                height: 24
                topRightRadius: I18n.rtl ? 0 : 3
                    topLeftRadius: I18n.rtl ? 3 : 0
                bottomRightRadius: I18n.rtl ? 0 : 3
                    bottomLeftRadius: I18n.rtl ? 3 : 0
                color: Theme.primary
                anchors.left: parent.left
                anchors.leftMargin: -root.railInset
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.checked ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
        }
    }

    // Two explicit layouts rather than one anchored Row, so the collapsed icon
    // sits dead-centre (a lone glyph, mirroring off so RTL can't offset it) while
    // the expanded row hugs the left with a small inset. Both branches stay
    // instantiated — visibility toggles, nothing is created/destroyed on collapse.
    contentItem: Item {
        // ── collapsed: a single centred glyph ──
        Item {
            visible: root.collapsed
            LayoutMirroring.enabled: false
            anchors.centerIn: parent
            width: 19
            height: 19
            // v4: the active glyph sits a size up; hover pops it slightly
            scale: root.checked ? 1.10 : root.hovered ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }
            // v7: animated vector icon (plays once per hover / on activation)
            NavIcon {
                id: railIcon
                visible: supported
                name: root.iconName
                size: 19
                active: root.checked
                hovered: root.hovered && root.collapsed
                glyphColor: root._iconColor
            }
            // names without a kinetic icon keep the font glyph
            IconGlyph {
                visible: !railIcon.supported
                anchors.centerIn: parent
                name: root.iconName
                fill: root.checked
                size: 19
                glyphColor: root._iconColor
            }
        }

        // ── expanded: icon + label hugging the left ──
        Row {
            id: navRow
            visible: !root.collapsed
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.space2
            spacing: Tokens.space2
            // hover nudges the row a few px inward — a quiet "this one"
            transform: Translate {
                x: (root.hovered && !root.checked) ? (I18n.rtl ? -3 : 3) : 0
                Behavior on x { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }
            Item {
                width: 19
                height: 19
                anchors.verticalCenter: parent.verticalCenter
                scale: root.checked ? 1.10 : 1.0
                Behavior on scale { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }
                NavIcon {
                    id: rowIcon
                    visible: supported
                    name: root.iconName
                    size: 19
                    active: root.checked
                    hovered: root.hovered && !root.collapsed
                    glyphColor: root._iconColor
                }
                IconGlyph {
                    visible: !rowIcon.supported
                    anchors.centerIn: parent
                    name: root.iconName
                    fill: root.checked
                    size: 19
                    glyphColor: root._iconColor
                }
            }
            AppText {
                text: root.text
                visible: !root.collapsed
                // Long labels ("Monetize Checker") must not force the button wider
                // than the rail; the label gets whatever is left after the inset,
                // icon and spacing.
                width: Math.max(0, root.width - Tokens.space2 - Tokens.space2 - 19)
                elide: Text.ElideRight
                weight: root.checked ? Tokens.weightBold : Tokens.weightDemiBold
                // v4: the active label goes bright text (the pill + glowing bar
                // carry the accent); hover lifts the label toward full contrast.
                color: root.checked ? Theme.text_strong : root.hovered ? Theme.on_surface : Theme.on_surface_var
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }
        }
    }

    AppTooltip {
        visible: root.collapsed && root.hovered
        delay: 350
        text: root.text
    }
}
