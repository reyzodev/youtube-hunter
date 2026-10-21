.pragma library

// Colour helpers shared across the QML UI. Kept as a pragma-library so every
// component reuses one copy.

// Re-emit a colour at an explicit alpha (0..1). The QML equivalent of the old
// app.ui.colors._rgba(): `withAlpha(Theme.primary, 0.12)`. `c` is a QML color,
// whose r/g/b/a are 0..1 reals.
//
// v3.22 — `c` may also be a hex STRING (seriesColor returns one). A string has
// no .r/.g/.b, so Qt.rgba(undefined, ...) quietly produced opaque-ish BLACK:
// that was every "discovered phrase" dot on the opportunity map and every
// area wash under a series line. Strings are converted to a colour first.
function _col(c) {
    return (typeof c === "string") ? Qt.lighter(c, 1.0) : c
}
function withAlpha(c, a) {
    c = _col(c)
    return Qt.rgba(c.r, c.g, c.b, a)
}

// Linear blend between two QML colours (t = 0 → a, t = 1 → b). Used to derive a
// slightly stronger border by nudging Theme.border toward Theme.outline without
// hard-coding a hex value per theme.
function mix(a, b, t) {
    a = _col(a)
    b = _col(b)
    return Qt.rgba(a.r + (b.r - a.r) * t,
                   a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t,
                   a.a + (b.a - a.a) * t)
}

// The project's standard hover fill: an OPAQUE nudge of `base` toward white (in
// dark themes) or black (in light ones).
//
// Always prefer this over the translucent Theme.hover_bg for a hover state that
// animates. A wash lets whatever sits behind the control show through, so the
// `Behavior on color` transition reads as a flash rather than a fill settling
// in. Pass the colour the control is actually sitting on, e.g.
// `hoverTint(Theme.panel_bg, Theme.isDark)`.
function hoverTint(base, isDark, strength) {
    var t = strength === undefined ? 0.08 : strength
    return mix(base, isDark ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1), t)
}

// The Usage page's 5-step red chart ramp, derived from the live brand colour so
// it tracks the theme instead of hard-coding the template's --chart-1..5 hexes.
// i 0 = strongest (full primary), rising indices step toward a paler / (in dark
// themes) slightly lifted tint, with the last step a deep anchor for the
// cumulative line. `unclassified` buckets pass i = -1 and get a neutral grey.
function chartTint(i, primary, isDark) {
    if (i < 0)
        return isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
    var ramp = [0.0, 0.18, 0.36, 0.55, -0.25]
    var t = ramp[i % ramp.length]
    if (t < 0)   // deep anchor: mix toward black
        return mix(primary, Qt.rgba(0, 0, 0, 1), -t)
    // lighter steps: mix toward white (dark theme) / a warm pale (light theme)
    return mix(primary, isDark ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(1, 0.6, 0.55, 1), t)
}

// v3.39.8 — categorical chart hues.
//
// The old charts coloured every slice with chartTint(), i.e. five shades of the
// SAME accent; on a dark panel three of them were indistinguishable ("which
// green is 29%?"). These are separate hues, tuned per theme so each clears
// 3:1 against its panel, ordered so neighbours never sit close on the wheel.
var _CAT_DARK  = ["#2DD4BF", "#F5A524", "#F25F8B", "#60A5FA", "#A78BFA", "#F97316", "#4ADE80"]
var _CAT_LIGHT = ["#0E9F8E", "#C77C00", "#D9356A", "#2F7BE0", "#7C5CE0", "#E05A00", "#16A34A"]
function catHue(i, isDark) {
    var set = isDark ? _CAT_DARK : _CAT_LIGHT
    if (i === undefined || i < 0)
        return isDark ? "#71717A" : "#A1A1AA"
    return set[i % set.length]
}

// Ordinal "age" ramp for freshness: newest is the loudest, the oldest bucket
// fades to a neutral. i 0..3.
var _AGE_DARK  = ["#2DD4BF", "#60A5FA", "#A78BFA", "#71717A"]
var _AGE_LIGHT = ["#0E9F8E", "#2F7BE0", "#7C5CE0", "#A1A1AA"]
function ageHue(i, isDark) {
    var set = isDark ? _AGE_DARK : _AGE_LIGHT
    return set[Math.max(0, Math.min(set.length - 1, i))]
}
