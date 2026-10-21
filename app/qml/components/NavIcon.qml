import QtQuick
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// v7 "Kinetic" nav icons: the sidebar's own icon set, drawn as vector strokes
// on a 24-unit grid (QtQuick.Shapes, CurveRenderer = crisp at any DPI) so every
// part of an icon can move on its own. A font glyph is one flat shape; it can
// only scale or spin as a whole, which is why the old rail could never animate
// "the arrow drops into the cloud" or "the scissors snip".
//
// Behaviour rules (the premium part is mostly restraint):
//   • Each icon has ONE short choreography (~0.6–0.9s) that tells its story:
//     the download arrow falls through the cloud, the clock hands rewind,
//     the coin flips, the scissors snip twice, the gauge needle revs...
//   • It plays ONCE per hover-enter and once when the row becomes active.
//     It never loops, and leaving the row mid-way lets it finish on its own
//     (cutting it off reads as a glitch). Re-hovering while it still runs is
//     ignored, so sweeping the mouse up and down the rail never stutters.
//   • Everything ends exactly at the rest pose, so the idle rail is static.
//   • Active row = duotone: stroke in the accent + a soft accent tint inside
//     the icon's main body (replaces the old filled-glyph swap).
//
// Unknown names render nothing; check `NavIcon.has(name)` (see NavButton) and
// fall back to IconGlyph for those.
Item {
    id: root
    property string name: ""
    property int size: 19
    property color glyphColor: Theme.on_surface_var
    property bool active: false
    property bool hovered: false
    // global kill switch for the choreography (static icons, same artwork)
    property bool animated: true

    // stroke weight in grid units: 1.8/24 ≈ 1.43px at 19px, matching the label
    // v8 "Aurora": one colour, two weights. Idle rows draw the 1.75 line face;
    // the active row thickens to 2.25 (bold) instead of the old alpha tint, so
    // the rail matches the in-page Line/Bold icon set. Artwork redrawn on the
    // same 24-grid; every animation, pivot and timing is unchanged.
    property real sw: active ? 2.25 : 1.75
    Behavior on sw { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    readonly property real _tintA: 0.0
    readonly property color tint: "transparent"

    readonly property var _components: ({
        "cloud_download": cScraper,
        "history": cHistory,
        "monetization_on": cCoin,
        "travel_explore": cFinder,
        "nav_insights": cInsights,
        "archive": cArchive,
        "lightbulb": cBulb,
        "biotech": cFlask,
        "download": cDownload,
        "scissors": cScissors,
        "nav_usage": cGauge,
        "settings": cGear,
        "nav_chat": cChat
    })
    function has(n) { return _components[n] !== undefined }
    readonly property bool supported: has(name)

    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    function play() {
        if (!animated || !visible || !stage.item || !stage.item.play) return
        stage.item.play()
    }
    onHoveredChanged: if (hovered) play()
    onActiveChanged: if (active) play()

    // One stroked (optionally tinted) path on the 24-unit grid.
    component Glyph: Shape {
        id: g
        property string d: ""
        property color ink: "black"
        property color body: "transparent"
        property real lineWidth: 1.8
        width: 24
        height: 24
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: g.ink
            strokeWidth: g.lineWidth
            fillColor: g.body
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: g.d }
        }
    }

    // A solid dot (sparkle centres, bubbles, gauge hub).
    component Dot: Rectangle {
        property real cx: 0
        property real cy: 0
        property real r: 1
        x: cx - r
        y: cy - r
        width: r * 2
        height: r * 2
        radius: r
        antialiasing: true
    }

    // 24×24 artwork scaled to `size`
    Loader {
        id: stage
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        sourceComponent: root.supported ? root._components[root.name] : null
    }

    // ───────────────────────────── Scraper ─────────────────────────────
    // The arrow falls through the cloud and drops back in from the top; the
    // cloud gives a small lift as it "catches" it.
    Component {
        id: cScraper
        Item {
            width: 24; height: 24
            clip: true
            function play() { if (!animScr.running) animScr.start() }
            Glyph {
                ink: root.glyphColor; lineWidth: root.sw
                d: "M6.6 17.8A4.7 4.7 0 0 1 5.9 8.5A6.6 6.6 0 0 1 18.4 8.6A4.6 4.6 0 0 1 18.6 17.7"
                transform: Translate { id: cloudT }
            }
            Item {
                id: arrow
                width: 24; height: 24
                transform: Translate { id: arrowT }
                Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M12 11.8v9.2M8.6 17.6l3.4 3.4l3.4-3.4" }
            }
            SequentialAnimation {
                id: animScr
                ParallelAnimation {
                    NumberAnimation { target: arrowT; property: "y"; from: 0; to: 6; duration: 200; easing.type: Easing.InCubic }
                    NumberAnimation { target: arrow; property: "opacity"; from: 1; to: 0; duration: 200; easing.type: Easing.InQuad }
                }
                PropertyAction { target: arrowT; property: "y"; value: -9 }
                ParallelAnimation {
                    NumberAnimation { target: arrowT; property: "y"; to: 0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
                    NumberAnimation { target: arrow; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 170 }
                        NumberAnimation { target: cloudT; property: "y"; to: -1.2; duration: 150; easing.type: Easing.OutCubic }
                        NumberAnimation { target: cloudT; property: "y"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }
            }
        }
    }

    // ───────────────────────────── History ─────────────────────────────
    // A rewind: the minute hand spins back a full turn, the hour hand ticks
    // back and returns, the loop arrow kicks against the motion.
    Component {
        id: cHistory
        Item {
            width: 24; height: 24
            function play() { if (!animHis.running) animHis.start() }
            Item {
                width: 24; height: 24
                transform: Rotation { id: ringR; origin.x: 12; origin.y: 12 }
                Glyph {
                    ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                    d: "M3.04 12a8.96 8.96 0 1 0 2.69 -6.38"
                }
                Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M5.06 1.92v4.03h4.03" }
            }
            Glyph {
                ink: root.glyphColor; lineWidth: root.sw; d: "M12 12V7.3"
                transform: Rotation { id: minR; origin.x: 12; origin.y: 12 }
            }
            Glyph {
                ink: root.glyphColor; lineWidth: root.sw; d: "M12 12l3.36 2.02"
                transform: Rotation { id: hourR; origin.x: 12; origin.y: 12 }
            }
            ParallelAnimation {
                id: animHis
                NumberAnimation { target: minR; property: "angle"; from: 0; to: -360; duration: 820; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    NumberAnimation { target: hourR; property: "angle"; from: 0; to: -40; duration: 300; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hourR; property: "angle"; to: 0; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }
                SequentialAnimation {
                    NumberAnimation { target: ringR; property: "angle"; from: 0; to: -24; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ringR; property: "angle"; to: 0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
            }
        }
    }

    // ────────────────────────── Monetize Checker ──────────────────────────
    // A coin flip: one full turn around the vertical axis with a tiny pop.
    Component {
        id: cCoin
        Item {
            id: coin
            width: 24; height: 24
            function play() { if (!animCoin.running) animCoin.start() }
            transform: [
                Rotation { id: flipR; origin.x: 12; origin.y: 12; axis { x: 0; y: 1; z: 0 } },
                Scale { id: coinS; origin.x: 12; origin.y: 12 }
            ]
            Glyph {
                ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                d: "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z"
            }
            Glyph {
                ink: root.glyphColor; lineWidth: root.sw
                d: "M14.6 9.2a2.6 2.6 0 0 0-2.4-1.4h-.7a2.1 2.1 0 0 0 0 4.2h1a2.1 2.1 0 0 1 0 4.2h-.8a2.6 2.6 0 0 1-2.4-1.4M12 6v1.8M12 16.2V18"
            }
            ParallelAnimation {
                id: animCoin
                NumberAnimation { target: flipR; property: "angle"; from: 0; to: 360; duration: 760; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    NumberAnimation { target: coinS; properties: "xScale,yScale"; from: 1; to: 1.1; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { target: coinS; properties: "xScale,yScale"; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                }
            }
        }
    }

    // ──────────────────────────── Niche Finder ────────────────────────────
    // The lens sweeps a small scan arc; the spark inside it twists and flares
    // the moment it "finds" something.
    Component {
        id: cFinder
        Item {
            width: 24; height: 24
            function play() { if (!animFind.running) animFind.start() }
            Item {
                width: 24; height: 24
                transform: Translate { id: lensT }
                Glyph {
                    ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                    d: "M10.92 3.14a7.78 7.78 0 1 0 0 15.55a7.78 7.78 0 1 0 0 -15.55zM16.64 16.64l4.54 4.54"
                }
                Item {
                    width: 24; height: 24
                    transform: [
                        Rotation { id: sparkR; origin.x: 10.92; origin.y: 10.92 },
                        Scale { id: sparkS; origin.x: 10.92; origin.y: 10.92 }
                    ]
                    Glyph {
                        ink: root.glyphColor; body: root.glyphColor; lineWidth: 1.1
                        d: "M10.92 7.25L11.84 10L14.59 10.92L11.84 11.84L10.92 14.59L10 11.84L7.25 10.92L10 10Z"
                    }
                }
            }
            ParallelAnimation {
                id: animFind
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: lensT; property: "x"; to: -1.6; duration: 200; easing.type: Easing.InOutSine }
                        NumberAnimation { target: lensT; property: "y"; to: -0.8; duration: 200; easing.type: Easing.InOutSine }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: lensT; property: "x"; to: 1.4; duration: 260; easing.type: Easing.InOutSine }
                        NumberAnimation { target: lensT; property: "y"; to: -1.4; duration: 260; easing.type: Easing.InOutSine }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: lensT; property: "x"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                        NumberAnimation { target: lensT; property: "y"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
                    }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 380 }
                    ParallelAnimation {
                        NumberAnimation { target: sparkR; property: "angle"; from: 0; to: 90; duration: 460; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: sparkS; properties: "xScale,yScale"; from: 1; to: 1.45; duration: 170; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sparkS; properties: "xScale,yScale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }
                    }
                }
            }
        }
    }

    // ────────────────────────── Niche Scan ──────────────────────────
    // The trend line re-draws left → right and the peak sends out a ping.
    Component {
        id: cInsights
        Item {
            width: 24; height: 24
            function play() { if (!animIns.running) animIns.start() }
            Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M2.99 2.99v14.84a3.18 3.18 0 0 0 3.18 3.18h14.84" }
            Item {
                id: wipe
                width: 24; height: 24
                clip: true
                Glyph {
                    ink: root.glyphColor; lineWidth: root.sw
                    d: "M7.23 15.18l4.03 -4.56l3.18 3.18l6.04 -7.63"
                }
            }
            Rectangle {
                id: ping
                x: 20.48 - width / 2; y: 6.17 - height / 2
                width: 2; height: 2; radius: width / 2
                color: "transparent"
                border.color: root.glyphColor
                border.width: 1.1
                opacity: 0
                antialiasing: true
            }
            Dot { id: peak; cx: 20.48; cy: 6.17; r: 1.59; color: root.glyphColor; scale: 0 }
            SequentialAnimation {
                id: animIns
                NumberAnimation { target: wipe; property: "width"; from: 5.5; to: 24; duration: 560; easing.type: Easing.OutCubic }
                ParallelAnimation {
                    SequentialAnimation {
                        NumberAnimation { target: peak; property: "scale"; from: 0; to: 1.2; duration: 140; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 120 }
                        NumberAnimation { target: peak; property: "scale"; to: 0; duration: 260; easing.type: Easing.InCubic }
                    }
                    NumberAnimation { target: ping; properties: "width,height"; from: 2; to: 9; duration: 520; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ping; property: "opacity"; from: 0.9; to: 0; duration: 520; easing.type: Easing.OutQuad }
                }
            }
        }
    }

    // ─────────────────────────── Search Archive ───────────────────────────
    // The lid lifts on its left hinge and drops back shut with a settle.
    Component {
        id: cArchive
        Item {
            width: 24; height: 24
            function play() { if (!animArc.running) animArc.start() }
            Glyph {
                ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                d: "M4.12 8.85v8.93a2.62 2.62 0 0 0 2.62 2.62h10.5a2.62 2.62 0 0 0 2.62 -2.62V8.85"
            }
            Glyph {
                ink: root.glyphColor; lineWidth: root.sw; d: "M9.9 13.05h4.2"
                transform: Translate { id: slotT }
            }
            Glyph {
                ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                d: "M4.12 3.6h15.75a2.1 2.1 0 0 1 2.1 2.1v1.05a2.1 2.1 0 0 1 -2.1 2.1h-15.75a2.1 2.1 0 0 1 -2.1 -2.1V5.7a2.1 2.1 0 0 1 2.1 -2.1z"
                transform: [
                    Rotation { id: lidR; origin.x: 2.03; origin.y: 8.85 },
                    Translate { id: lidT }
                ]
            }
            ParallelAnimation {
                id: animArc
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation { target: lidR; property: "angle"; to: -13; duration: 240; easing.type: Easing.OutCubic }
                        NumberAnimation { target: lidT; property: "y"; to: -1.6; duration: 240; easing.type: Easing.OutCubic }
                    }
                    PauseAnimation { duration: 90 }
                    ParallelAnimation {
                        NumberAnimation { target: lidR; property: "angle"; to: 0; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                        NumberAnimation { target: lidT; property: "y"; to: 0; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                    }
                }
                SequentialAnimation {
                    NumberAnimation { target: slotT; property: "y"; to: -2.2; duration: 240; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slotT; property: "y"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
            }
        }
    }

    // ────────────────────────────── AI Ideas ──────────────────────────────
    // The bulb lights: the glass flashes, it lifts a touch, rays burst out.
    Component {
        id: cBulb
        Item {
            id: bulbIcon
            width: 24; height: 24
            property real glow: 0
            function play() { if (!animBulb.running) animBulb.start() }
            Item {
                id: rays
                width: 24; height: 24
                opacity: 0
                transform: Scale { id: raysS; origin.x: 12; origin.y: 7.52 }
                Glyph {
                    ink: root.glyphColor; lineWidth: 1.6
                    d: "M3.49 4.61L1.81 3.71M7.52 0.69L6.62 -0.99M16.48 0.69L17.38 -0.99M20.51 4.61L22.19 3.71"
                }
            }
            Item {
                width: 24; height: 24
                transform: Scale { id: bulbS; origin.x: 12; origin.y: 21.52 }
                Glyph {
                    ink: root.glyphColor; lineWidth: root.sw
                    body: U.withAlpha(root.glyphColor, bulbIcon.glow * 0.32)
                    d: "M8.64 17.6v-0.45c0 -0.78 -0.34 -1.57 -1.01 -2.13A7.28 7.28 0 1 1 16.37 15.02c-0.67 0.56 -1.01 1.34 -1.01 2.13v0.45z"
                }
                Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M9.2 21.52h5.6" }
            }
            ParallelAnimation {
                id: animBulb
                SequentialAnimation {
                    NumberAnimation { target: bulbIcon; property: "glow"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                    NumberAnimation { target: bulbIcon; property: "glow"; to: 0; duration: 560; easing.type: Easing.InOutSine }
                }
                SequentialAnimation {
                    NumberAnimation { target: bulbS; properties: "xScale,yScale"; from: 1; to: 1.07; duration: 180; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bulbS; properties: "xScale,yScale"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation { target: raysS; properties: "xScale,yScale"; from: 0.7; to: 1.12; duration: 520; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: rays; property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: rays; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InQuad }
                        }
                    }
                }
            }
        }
    }

    // ───────────────────────────── Content Lab ─────────────────────────────
    // The flask swirls on its base and three bubbles rise out of the neck.
    Component {
        id: cFlask
        Item {
            width: 24; height: 24
            function play() { if (!animFlask.running) animFlask.start() }
            Item {
                width: 24; height: 24
                transform: Rotation { id: flaskR; origin.x: 12; origin.y: 21.35 }
                Glyph {
                    ink: root.glyphColor; lineWidth: root.sw
                    d: "M9.8 2.65v5.72L4.19 17.94a2.2 2.2 0 0 0 1.87 3.41h11.88a2.2 2.2 0 0 0 1.87 -3.41L14.2 8.37V2.65M8.15 2.65h7.7M6.72 14.75h10.56"
                }
            }
            Dot { id: b1; cx: 10.46; cy: 18.16; r: 1.16; color: root.glyphColor; opacity: 0; transform: Translate { id: b1T } }
            Dot { id: b2; cx: 13.76; cy: 18.49; r: 0.94; color: root.glyphColor; opacity: 0; transform: Translate { id: b2T } }
            Dot { id: b3; cx: 12.11; cy: 19.04; r: 0.77; color: root.glyphColor; opacity: 0; transform: Translate { id: b3T } }
            ParallelAnimation {
                id: animFlask
                SequentialAnimation {
                    NumberAnimation { target: flaskR; property: "angle"; to: -9; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: flaskR; property: "angle"; to: 7; duration: 220; easing.type: Easing.InOutSine }
                    NumberAnimation { target: flaskR; property: "angle"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 140 }
                    ParallelAnimation {
                        NumberAnimation { target: b1T; property: "y"; from: 0; to: -13; duration: 620; easing.type: Easing.OutCubic }
                        NumberAnimation { target: b1T; property: "x"; from: 0; to: 1.2; duration: 620; easing.type: Easing.InOutSine }
                        SequentialAnimation {
                            NumberAnimation { target: b1; property: "opacity"; from: 0; to: 1; duration: 120 }
                            NumberAnimation { target: b1; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InQuad }
                        }
                    }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 240 }
                    ParallelAnimation {
                        NumberAnimation { target: b2T; property: "y"; from: 0; to: -11; duration: 560; easing.type: Easing.OutCubic }
                        NumberAnimation { target: b2T; property: "x"; from: 0; to: -1.4; duration: 560; easing.type: Easing.InOutSine }
                        SequentialAnimation {
                            NumberAnimation { target: b2; property: "opacity"; from: 0; to: 1; duration: 120 }
                            NumberAnimation { target: b2; property: "opacity"; to: 0; duration: 440; easing.type: Easing.InQuad }
                        }
                    }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 340 }
                    ParallelAnimation {
                        NumberAnimation { target: b3T; property: "y"; from: 0; to: -9; duration: 480; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: b3; property: "opacity"; from: 0; to: 1; duration: 100 }
                            NumberAnimation { target: b3; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
                        }
                    }
                }
            }
        }
    }

    // ────────────────────────────── Downloads ──────────────────────────────
    // The arrow punches down into the tray; the tray dips and springs back.
    Component {
        id: cDownload
        Item {
            width: 24; height: 24
            function play() { if (!animDl.running) animDl.start() }
            Glyph {
                ink: root.glyphColor; lineWidth: root.sw; d: "M12 2.99v11.66M7.23 10.41l4.77 4.77l4.77 -4.77"
                transform: Translate { id: dlArrowT }
            }
            Glyph {
                ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                d: "M20.48 15.71v2.12a3.18 3.18 0 0 1 -3.18 3.18H6.7a3.18 3.18 0 0 1 -3.18 -3.18v-2.12"
                transform: [
                    Translate { id: trayT },
                    Scale { id: trayS; origin.x: 12; origin.y: 21.01 }
                ]
            }
            ParallelAnimation {
                id: animDl
                SequentialAnimation {
                    NumberAnimation { target: dlArrowT; property: "y"; from: 0; to: -2; duration: 140; easing.type: Easing.OutCubic }
                    NumberAnimation { target: dlArrowT; property: "y"; to: 3; duration: 170; easing.type: Easing.InCubic }
                    NumberAnimation { target: dlArrowT; property: "y"; to: 0; duration: 440; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 290 }
                    ParallelAnimation {
                        NumberAnimation { target: trayT; property: "y"; to: 1.1; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: trayS; property: "xScale"; to: 1.07; duration: 110; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: trayT; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                        NumberAnimation { target: trayS; property: "xScale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }
                }
            }
        }
    }

    // ──────────────────────────── Video Cutter ────────────────────────────
    // Two quick snips around the pivot while the scissors push forward.
    Component {
        id: cScissors
        Item {
            id: cutIcon
            width: 24; height: 24
            property real blade: 0
            function play() { if (!animCut.running) animCut.start() }
            transform: Translate { id: cutT }
            Item {
                width: 24; height: 24
                transform: Rotation { origin.x: 12; origin.y: 12; angle: cutIcon.blade }
                Glyph {
                    ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                    d: "M6.06 14.92a3.02 3.02 0 1 0 0 6.05a3.02 3.02 0 1 0 0 -6.05z"
                }
                Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M8.22 15.78L20.1 3.9" }
            }
            Item {
                width: 24; height: 24
                transform: Rotation { origin.x: 12; origin.y: 12; angle: -cutIcon.blade }
                Glyph {
                    ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                    d: "M6.06 3.04a3.02 3.02 0 1 0 0 6.05a3.02 3.02 0 1 0 0 -6.05z"
                }
                Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M8.22 8.22L20.1 20.1" }
            }
            ParallelAnimation {
                id: animCut
                SequentialAnimation {
                    NumberAnimation { target: cutIcon; property: "blade"; from: 0; to: 17; duration: 120; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: cutIcon; property: "blade"; to: 0; duration: 120; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: cutIcon; property: "blade"; to: 17; duration: 120; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: cutIcon; property: "blade"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
                SequentialAnimation {
                    NumberAnimation { target: cutT; property: "x"; from: 0; to: 1.6; duration: 360; easing.type: Easing.OutCubic }
                    NumberAnimation { target: cutT; property: "x"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }
            }
        }
    }

    // ─────────────────────────── Usage & Quota ───────────────────────────
    // An engine rev: the needle drops to empty, swings past full, settles.
    Component {
        id: cGauge
        Item {
            width: 24; height: 24
            function play() { if (!animGauge.running) animGauge.start() }
            Glyph {
                ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                d: "M3.42 19.15A9.9 9.9 0 1 1 20.58 19.15"
            }
            Glyph { ink: root.glyphColor; lineWidth: 1.5; d: "M6.5 10.35l1.1 0.88M12 6.5v1.43M17.5 10.35l-1.1 0.88" }
            Item {
                width: 24; height: 24
                transform: Rotation { id: needleR; origin.x: 12; origin.y: 14.2 }
                Glyph { ink: root.glyphColor; lineWidth: root.sw; d: "M12 14.2l4.18 -4.73" }
            }
            Dot { cx: 12; cy: 14.2; r: 1.98; color: root.glyphColor }
            SequentialAnimation {
                id: animGauge
                NumberAnimation { target: needleR; property: "angle"; from: 0; to: -92; duration: 230; easing.type: Easing.OutCubic }
                NumberAnimation { target: needleR; property: "angle"; to: 66; duration: 300; easing.type: Easing.InOutCubic }
                NumberAnimation { target: needleR; property: "angle"; to: 0; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
            }
        }
    }

    // ────────────────────────────── Settings ──────────────────────────────
    // One tooth-pitch turn (45°) with a spring: the 8-tooth gear lands on an
    // identical pose, so it snaps back to 0 invisibly.
    Component {
        id: cGear
        Item {
            width: 24; height: 24
            function play() { if (!animGear.running) animGear.start() }
            Item {
                width: 24; height: 24
                transform: Rotation { id: gearR; origin.x: 12; origin.y: 12 }
                Glyph {
                    ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                    d: "M10.02 4.87L10.25 2.56A9.6 9.6 0 0 1 13.75 2.56L13.98 4.87A7.4 7.4 0 0 1 15.64 5.56L17.44 4.09A9.6 9.6 0 0 1 19.91 6.56L18.44 8.36A7.4 7.4 0 0 1 19.13 10.02L21.44 10.25A9.6 9.6 0 0 1 21.44 13.75L19.13 13.98A7.4 7.4 0 0 1 18.44 15.64L19.91 17.44A9.6 9.6 0 0 1 17.44 19.91L15.64 18.44A7.4 7.4 0 0 1 13.98 19.13L13.75 21.44A9.6 9.6 0 0 1 10.25 21.44L10.02 19.13A7.4 7.4 0 0 1 8.36 18.44L6.56 19.91A9.6 9.6 0 0 1 4.09 17.44L5.56 15.64A7.4 7.4 0 0 1 4.87 13.98L2.56 13.75A9.6 9.6 0 0 1 2.56 10.25L4.87 10.02A7.4 7.4 0 0 1 5.56 8.36L4.09 6.56A9.6 9.6 0 0 1 6.56 4.09L8.36 5.56A7.4 7.4 0 0 1 10.02 4.87ZM12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z"
                }
            }
            SequentialAnimation {
                id: animGear
                NumberAnimation { target: gearR; property: "angle"; from: 0; to: 45; duration: 720; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                PropertyAction { target: gearR; property: "angle"; value: 0 }
            }
        }
    }

    // ─────────────────────────────── AI Chat ───────────────────────────────
    // The bubble "speaks": the three dots hop in turn, the bubble gives one
    // small nod. Ends on the rest pose like every other icon.
    Component {
        id: cChat
        Item {
            id: chatIcon
            width: 24; height: 24
            property real d1: 0
            property real d2: 0
            property real d3: 0
            function play() { if (!animChat.running) animChat.start() }
            Item {
                width: 24; height: 24
                transform: Rotation { id: chatR; origin.x: 6; origin.y: 21 }
                Glyph {
                    ink: root.glyphColor; body: root.tint; lineWidth: root.sw
                    d: "M5.5 4h13a2.5 2.5 0 0 1 2.5 2.5v9a2.5 2.5 0 0 1-2.5 2.5h-8l-4.6 3.3a.6.6 0 0 1-.9-.5V18h-.5A2.5 2.5 0 0 1 3 15.5v-9A2.5 2.5 0 0 1 5.5 4z"
                }
                Dot { cx: 8; cy: 11 - chatIcon.d1; r: 1.25; color: root.glyphColor }
                Dot { cx: 12; cy: 11 - chatIcon.d2; r: 1.25; color: root.glyphColor }
                Dot { cx: 16; cy: 11 - chatIcon.d3; r: 1.25; color: root.glyphColor }
            }
            ParallelAnimation {
                id: animChat
                SequentialAnimation {
                    NumberAnimation { target: chatR; property: "angle"; from: 0; to: -7; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: chatR; property: "angle"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }
                SequentialAnimation {
                    NumberAnimation { target: chatIcon; property: "d1"; from: 0; to: 2.2; duration: 130; easing.type: Easing.OutQuad }
                    NumberAnimation { target: chatIcon; property: "d1"; to: 0; duration: 200; easing.type: Easing.InQuad }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 110 }
                    NumberAnimation { target: chatIcon; property: "d2"; from: 0; to: 2.2; duration: 130; easing.type: Easing.OutQuad }
                    NumberAnimation { target: chatIcon; property: "d2"; to: 0; duration: 200; easing.type: Easing.InQuad }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 220 }
                    NumberAnimation { target: chatIcon; property: "d3"; from: 0; to: 2.2; duration: 130; easing.type: Easing.OutQuad }
                    NumberAnimation { target: chatIcon; property: "d3"; to: 0; duration: 200; easing.type: Easing.InQuad }
                }
            }
        }
    }
}
