import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import NicheScope

// YouTube Hunter brand mark.
//
// Drawn as vectors (not a PNG) for two reasons: it stays razor sharp from the
// 22px title-bar size up to the splash, and it takes its colour from the LIVE
// theme accent, so picking Ocean / Mint / Tungsten in Settings repaints the
// logo with everything else. The play triangle stays white on every accent.
//
// Geometry lives in a 738 x 812 design box (same numbers as app/ui/brand.py,
// which paints the window/taskbar icon from them).
//
// Motion hooks (all default to the resting logo, so a plain `BrandMark {}`
// is just the logo):
//   assemble      0..1  crown drops in, side blades slide in from the edges
//   trace         0..1  neon outline draws itself around every piece
//   traceOpacity  0..1  how visible that outline is
//   playPop       0..1  play triangle pops in with a little overshoot
//   sheen         0..1  light sweep across the faces (-1 = off)
//   glow / glowStrength  accent-coloured neon halo
Item {
    id: root
    implicitWidth: 64
    implicitHeight: Math.round(64 * _vh / _vw)

    property color colorA: Theme.logo_grad_in
    property color colorB: Theme.logo_grad_out
    property color colorDeep: Qt.darker(colorA, 4.2)
    property color playColor: "#FFFFFF"

    property real assemble: 1.0
    property real trace: 1.0
    property real traceOpacity: 0.0
    property real playPop: 1.0
    property real sheen: -1.0
    property bool glow: false
    property real glowStrength: 1.0
    property bool rim: true

    readonly property real _vw: 738
    readonly property real _vh: 812
    readonly property real _k: Math.min(width / _vw, height / _vh)
    readonly property color _colorDark: Qt.darker(colorA, 2.1)
    readonly property color _rimColor: Qt.rgba(1, 1, 1, Theme.isDark ? 0.16 : 0.22)
    // keep the rim about one device pixel wide whatever the size
    readonly property real _rimWidth: Math.max(1.5, 1.2 / Math.max(0.01, _k))
    readonly property color _traceColor: Qt.lighter(colorA, 1.35)

    function _clamp(v) { return Math.max(0, Math.min(1, v)) }
    function _outCubic(t) { t = _clamp(t); return 1 - Math.pow(1 - t, 3) }
    function _outBack(t) {
        t = _clamp(t)
        var c1 = 1.55, c3 = c1 + 1
        return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2)
    }
    readonly property real _eCrown: _outCubic(assemble / 0.7)
    readonly property real _eSide: _outBack((assemble - 0.25) / 0.75)
    readonly property real _ePlay: _outBack(playPop)
    readonly property real _sheenX: sheen < 0 ? -100000 : (-300 + sheen * (_vw + 600))

    Item {
        id: stage
        anchors.fill: parent
        layer.enabled: root.glow
        layer.smooth: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.colorA
            shadowBlur: 1.0
            blurMax: 56
            shadowOpacity: Math.min(1, 0.9 * root.glowStrength)
            shadowScale: 1.0 + 0.05 * root.glowStrength
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }

        Item {
            id: art
            width: root._vw
            height: root._vh
            transformOrigin: Item.TopLeft
            scale: root._k
            x: (stage.width - root._vw * root._k) / 2
            y: (stage.height - root._vh * root._k) / 2

            // ── pillarL ──
            Shape {
                id: pillarL
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: Math.min(1, root._eSide)
                transform: Translate { x: -(1 - root._eSide) * 120 }
                ShapePath {
                    strokeColor: root.rim ? root._rimColor : "transparent"
                    strokeWidth: root.rim ? root._rimWidth : -1
                    joinStyle: ShapePath.MiterJoin
                    fillGradient: LinearGradient {
                        x1: 0; y1: 240; x2: 0; y2: 804
                        GradientStop { position: 0.0; color: root.colorA }
                        GradientStop { position: 0.45; color: root.colorB }
                        GradientStop { position: 1.0; color: root._colorDark }
                    }
                    PathPolyline { path: [Qt.point(156, 240), Qt.point(231, 322), Qt.point(231, 444), Qt.point(310, 524), Qt.point(318, 662), Qt.point(363, 804), Qt.point(156, 526), Qt.point(156, 240)] }
                }
                // travelling light sweep (root.sheen 0..1; -1 = parked off-art)
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: root._sheenX - 150; y1: 0
                        x2: root._sheenX + 150; y2: 240
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.46) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                    }
                    PathPolyline { path: [Qt.point(156, 240), Qt.point(231, 322), Qt.point(231, 444), Qt.point(310, 524), Qt.point(318, 662), Qt.point(363, 804), Qt.point(156, 526), Qt.point(156, 240)] }
                }
            }

            // ── pillarR ──
            Shape {
                id: pillarR
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: Math.min(1, root._eSide)
                transform: Translate { x: (1 - root._eSide) * 120 }
                ShapePath {
                    strokeColor: root.rim ? root._rimColor : "transparent"
                    strokeWidth: root.rim ? root._rimWidth : -1
                    joinStyle: ShapePath.MiterJoin
                    fillGradient: LinearGradient {
                        x1: 0; y1: 240; x2: 0; y2: 804
                        GradientStop { position: 0.0; color: root.colorA }
                        GradientStop { position: 0.45; color: root.colorB }
                        GradientStop { position: 1.0; color: root._colorDark }
                    }
                    PathPolyline { path: [Qt.point(582, 526), Qt.point(375, 804), Qt.point(420, 662), Qt.point(428, 524), Qt.point(507, 444), Qt.point(507, 322), Qt.point(582, 240), Qt.point(582, 526)] }
                }
                // travelling light sweep (root.sheen 0..1; -1 = parked off-art)
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: root._sheenX - 150; y1: 0
                        x2: root._sheenX + 150; y2: 240
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.46) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                    }
                    PathPolyline { path: [Qt.point(582, 526), Qt.point(375, 804), Qt.point(420, 662), Qt.point(428, 524), Qt.point(507, 444), Qt.point(507, 322), Qt.point(582, 240), Qt.point(582, 526)] }
                }
            }

            // ── crown ──
            Shape {
                id: crown
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: root._eCrown
                transform: Translate { y: -(1 - root._eCrown) * 80 }
                ShapePath {
                    strokeColor: root.rim ? root._rimColor : "transparent"
                    strokeWidth: root.rim ? root._rimWidth : -1
                    joinStyle: ShapePath.MiterJoin
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: 812
                        GradientStop { position: 0.0; color: root.colorA }
                        GradientStop { position: 0.40; color: root.colorB }
                        GradientStop { position: 0.78; color: root._colorDark }
                        GradientStop { position: 1.0; color: root.colorDeep }
                    }
                    PathPolyline { path: [Qt.point(0, 0), Qt.point(304, 146), Qt.point(304, 260), Qt.point(369, 304), Qt.point(434, 260), Qt.point(434, 146), Qt.point(738, 0), Qt.point(475, 307), Qt.point(475, 477), Qt.point(418, 532), Qt.point(410, 662), Qt.point(369, 812), Qt.point(328, 662), Qt.point(320, 532), Qt.point(263, 477), Qt.point(263, 307), Qt.point(0, 0)] }
                }
                // travelling light sweep (root.sheen 0..1; -1 = parked off-art)
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: root._sheenX - 150; y1: 0
                        x2: root._sheenX + 150; y2: 240
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.46) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                    }
                    PathPolyline { path: [Qt.point(0, 0), Qt.point(304, 146), Qt.point(304, 260), Qt.point(369, 304), Qt.point(434, 260), Qt.point(434, 146), Qt.point(738, 0), Qt.point(475, 307), Qt.point(475, 477), Qt.point(418, 532), Qt.point(410, 662), Qt.point(369, 812), Qt.point(328, 662), Qt.point(320, 532), Qt.point(263, 477), Qt.point(263, 307), Qt.point(0, 0)] }
                }
            }

            // ── play triangle ──
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: root._clamp(root.playPop * 2.5)
                transform: Scale {
                    origin.x: 358; origin.y: 422
                    xScale: root._ePlay; yScale: root._ePlay
                }
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: -1
                    fillColor: root.playColor
                    PathPolyline { path: [Qt.point(324, 351), Qt.point(427, 422), Qt.point(324, 493), Qt.point(324, 351)] }
                }
            }

            // ── neon outline (draw-on) ──
            // Default (geometry) renderer: it is the one that does dashes, and
            // the draw-on is a single dash whose offset slides along the path.
            Shape {
                anchors.fill: parent
                visible: root.traceOpacity > 0.001
                opacity: root.traceOpacity
                layer.enabled: visible
                layer.samples: 4
                layer.smooth: true
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root._traceColor
                    strokeWidth: 4
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.MiterJoin
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [737.5, 737.5]
                    dashOffset: 737.5 * (1 - root.trace)
                    PathPolyline { path: [Qt.point(0, 0), Qt.point(304, 146), Qt.point(304, 260), Qt.point(369, 304), Qt.point(434, 260), Qt.point(434, 146), Qt.point(738, 0), Qt.point(475, 307), Qt.point(475, 477), Qt.point(418, 532), Qt.point(410, 662), Qt.point(369, 812), Qt.point(328, 662), Qt.point(320, 532), Qt.point(263, 477), Qt.point(263, 307), Qt.point(0, 0)] }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root._traceColor
                    strokeWidth: 4
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.MiterJoin
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [319.3, 319.3]
                    dashOffset: 319.3 * (1 - root.trace)
                    PathPolyline { path: [Qt.point(156, 240), Qt.point(231, 322), Qt.point(231, 444), Qt.point(310, 524), Qt.point(318, 662), Qt.point(363, 804), Qt.point(156, 526), Qt.point(156, 240)] }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root._traceColor
                    strokeWidth: 4
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.MiterJoin
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [319.3, 319.3]
                    dashOffset: 319.3 * (1 - root.trace)
                    PathPolyline { path: [Qt.point(582, 526), Qt.point(375, 804), Qt.point(420, 662), Qt.point(428, 524), Qt.point(507, 444), Qt.point(507, 322), Qt.point(582, 240), Qt.point(582, 526)] }
                }
            }
        }
    }
}
