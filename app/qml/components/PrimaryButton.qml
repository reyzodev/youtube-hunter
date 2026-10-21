import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import NicheScope
import "../Utils.js" as U

// Primary action button (v4 refresh).
// `variant`: "primary" (accent gradient) | "ghost" (outline) | "danger".
//
// Filled variants are lit like a physical key: an accent → accent2 gradient,
// a 1px glass edge, a specular top sheen, and a blurred halo of the same
// colour underneath that swells on hover. Hovering also sends one diagonal
// shine across the face; pressing sinks the key and it springs back on
// release. The ghost variant stays quiet: hairline that warms to the accent.
//
// Optionally doubles as its own progress bar: set `progress` to 0..1 and the
// button fills from the leading edge, with a shimmer riding that edge. Drawn
// inside `background` on purpose — a plain child of a Control is reparented
// into `contentItem`, where it would paint over the label and be inset by the
// button's padding.
Button {
    id: root
    property string variant: "primary"
    property string iconName: ""
    property bool iconFill: true

    // 0..1 while an operation runs; negative (the default) hides the fill
    // entirely. `indeterminate` keeps the shimmer sweeping when the backing
    // task reports no measurable total.
    property real progress: -1
    property bool indeterminate: false
    readonly property bool showProgress: progress >= 0 || indeterminate

    // Halo intensity: the theme's glow level (dark 1.0, light 0.6).
    readonly property real _glowK: Theme.glow_level !== undefined ? Theme.glow_level : 1.0

    // Same height as a field, so a button beside an input lines up exactly.
    implicitHeight: Tokens.fieldHeight
    implicitWidth: Math.max(104, contentRow.implicitWidth + Tokens.space5 * 2)
    hoverEnabled: true
    font.family: Fonts.family("body", Tokens.weightDemiBold)
    font.weight: Fonts.weight(Tokens.weightDemiBold)

    // Pointing-hand cursor whenever the button is enabled — the flat, borderless
    // icon language otherwise gives no hint that a tile is clickable.
    HoverHandler {
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    readonly property bool _filled: variant === "primary" || variant === "danger"
    readonly property color _base: variant === "danger" ? Theme.error : Theme.primary
    readonly property color _base2: variant === "danger"
                                    ? U.mix(Theme.error, Qt.rgba(1, 0.55, 0.35, 1), 0.35)
                                    : U.mix(Theme.primary, Theme.primary_deep, 0.65)

    // Press sinks the key; release springs it back with a whisper of overshoot.
    scale: pressed ? Tokens.pressScale : 1.0
    Behavior on scale {
        // v6: a crisp ease both ways — the v4 OutBack spring (overshoot 2.4)
        // made every click wobble, which reads as a toy, not a tool.
        NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic }
    }
    opacity: enabled ? 1.0 : 0.5
    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

    // One shine pass per hover-in (not looped: a looping shine on every button
    // turns the whole page into a slot machine).
    // v6: the shine sweep is retired — decoration any button could have.
    // Hover is now a flat lift of the face (see the hover-brighten layer).

    background: Item {
        id: bgRoot

        // ── halo ── the accent light pooling under a filled key. A proxy rect,
        // blurred; the label is never rasterised (it lives in contentItem).
        Rectangle {
            id: halo
            visible: root._filled && root.enabled
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.topMargin: 8
            anchors.bottomMargin: -2
            radius: Tokens.radiusMd
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root._base }
                GradientStop { position: 1.0; color: root._base2 }
            }
            opacity: (root.pressed ? 0.10 : root.hovered ? 0.30 : 0.14) * root._glowK
            Behavior on opacity { NumberAnimation { duration: Tokens.durGlow; easing.type: Easing.OutCubic } }
            layer.enabled: halo.visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 36
                autoPaddingEnabled: true
            }
        }

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: Tokens.radiusMd
            color: root._filled
                   ? root._base
                   // v6: ghost = a NEUTRAL secondary button (surface fill +
                   // hairline + strong text). ~80 accent-outlined ghosts made
                   // every screen look like it had six primary actions; now
                   // the one filled key per surface is unmistakably THE action.
                   : (root.pressed ? Theme.hover_bg_strong
                      : root.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark)
                      : Theme.surface_low)
            border.width: root._filled ? 0 : 1
            border.color: root._filled ? U.withAlpha((root.hovered ? U.mix(Theme.border_med, Theme.on_surface, 0.25) : Theme.border_med), 0)
                          : (root.hovered ? U.mix(Theme.border_med, Theme.on_surface, 0.25) : Theme.border_med)
            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            // The fill is clipped to the rounded corners rather than given its own
            // matching radius — at 0% width a rounded fill collapses into a lens
            // shape that reads as a stray dot.
            clip: true

            // ── accent gradient face (filled variants) ──
            Rectangle {
                anchors.fill: parent
                visible: root._filled
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root._base }
                    GradientStop { position: 1.0; color: root._base2 }
                }
            }

            // ── hover brighten ── a white wash rather than a colour swap, so
            // the gradient keeps its shape while the key "lights up".
            Rectangle {
                anchors.fill: parent
                visible: root._filled
                radius: parent.radius
                color: "#ffffff"
                opacity: root.pressed ? 0.0 : root.hovered ? 0.08 : 0.0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
            }

            // ── press darken ──
            Rectangle {
                anchors.fill: parent
                visible: root._filled
                radius: parent.radius
                color: "#000000"
                opacity: root.pressed ? 0.14 : 0.0
                Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
            }

            // ── specular top sheen ──
            Rectangle {
                visible: root._filled
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * 0.5
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.09) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            // ── glass edge ── a 1px inner light line, so the key has an edge
            // against dark panels instead of a flat colour boundary.
            Rectangle {
                visible: root._filled
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, root.hovered ? 0.18 : 0.10)
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
            }

            // v3.27: the fill and the sweep are square bands travelling inside a
            // ROUNDED key. `clip: true` above only cuts to the square bounding
            // box, so at the leading corners they showed as a pale, sharp-edged
            // slab over the button. RoundClip masks them to the key's exact
            // shape; the layer only exists while a progress state is showing.
            RoundClip {
                id: progressClip
                anchors.fill: parent
                radius: bg.radius
                active: root.showProgress
                visible: root.showProgress

                // ── determinate fill ──
                Rectangle {
                    id: fill
                    visible: root.showProgress && !root.indeterminate
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, root.progress))
                    color: root._filled ? U.withAlpha(Theme.on_primary, 0.26)
                                        : U.withAlpha(Theme.primary, 0.18)
                    // Eased, so each backend tick glides instead of jumping — the
                    // difference between "it's working" and "it froze".
                    Behavior on width {
                        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                    }

                    // Shimmer riding the leading edge. A download can sit at one
                    // percentage for seconds on a slow fragment, and a still bar there
                    // looks like a hang.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.min(56, parent.width)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: U.withAlpha(root._filled ? Theme.on_primary : Theme.primary, 0.0) }
                            GradientStop { position: 1.0; color: U.withAlpha(root._filled ? Theme.on_primary : Theme.primary, 0.30) }
                        }
                        SequentialAnimation on opacity {
                            running: fill.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }
                }

                // ── indeterminate sweep ──
                // For the stretch where there is no total to measure against (the
                // ffmpeg mux, a stream with no reported size). Honest: it says "still
                // working" without inventing a percentage.
                Rectangle {
                    id: sweep
                    visible: root.indeterminate
                    width: parent.width * 0.35
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(root._filled ? Theme.on_primary : Theme.primary, 0.0) }
                        GradientStop { position: 0.5; color: U.withAlpha(root._filled ? Theme.on_primary : Theme.primary, root._filled ? 0.28 : 0.20) }
                        GradientStop { position: 1.0; color: U.withAlpha(root._filled ? Theme.on_primary : Theme.primary, 0.0) }
                    }
                    SequentialAnimation on x {
                        running: sweep.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: -sweep.width; to: progressClip.width
                                          duration: 1300; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }

    // Wrap the icon+label Row in a full-size Item and centre it there. Setting
    // `anchors.centerIn: parent` directly on a contentItem is unreliable — the
    // control manages the contentItem's geometry, so when the button is wide
    // (Layout.fillWidth) the Row ended up pinned left instead of centred. An
    // inner Item that fills gives the Row a stable box to centre within.
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Tokens.space2
            IconGlyph {
                name: root.iconName
                fill: root.iconFill
                visible: root.iconName !== ""
                size: 17
                // v6: a neutral glyph on ghosts that picks up the accent on
                // hover; no hover pop (the face lift is the feedback).
                glyphColor: root._filled ? Theme.on_primary
                          : (root.hovered && root.enabled ? Theme.primary : Theme.on_surface_var)
                Behavior on glyphColor { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                anchors.verticalCenter: parent.verticalCenter
            }
            AppText {
                text: root.text
                weight: Tokens.weightDemiBold
                color: root._filled ? Theme.on_primary : Theme.text_strong
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
