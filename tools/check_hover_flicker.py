"""tools/check_hover_flicker.py - the two causes of hover "blink", as a lint.

1) colour fades that flash (auto-fixable with --fix)
2) hover lifts without LiftMask (report only)
3) opaque fill <-> translucent overlay fades (report only, v3.43c)

Part 1: colour fades

The bug this guards against
---------------------------
QML's ColorAnimation interpolates the four RGBA channels independently
(straight alpha, not premultiplied). The literal "transparent" is #00000000:
BLACK at zero alpha. So a hover fill that fades

    "transparent"  ->  a light tint (e.g. #F1F1F4)

passes through ~rgba(120,120,122,0.5) halfway: a grey, darker than both ends,
drawn over a light panel for ~60ms. That is the one-frame "blink" seen when the
mouse enters a Downloads row or moves between Monetize Checker's options (and
the same in reverse on leave). The fix is to fade from the SAME colour at zero
alpha (U.withAlpha(tint, 0)), so only the opacity changes.

Usage
-----
    python tools/check_hover_flicker.py          # report, exit 1 if any found
    python tools/check_hover_flicker.py --fix    # rewrite colour fades in place

It flags any colour binding that contains "transparent" / Qt.rgba(0,0,0,0)
when the same object animates that property with `Behavior on <prop>`.

Part 3: opaque <-> translucent (v3.43c)
A hover that swaps an OPAQUE token (Theme.input_bg, Theme.surface_low …) for a
low-alpha overlay (U.withAlpha(Theme.on_surface, 0.05)) blinks the same way:
mid-fade the fill is half-transparent and the page shows through as grey.
Blend instead: U.mix(Theme.input_bg, Theme.on_surface, 0.05) stays opaque.
This is what made Search Archive's Sort trigger flash on mouse-over.

Part 2: hover lifts
An item that translates ITSELF on its own hover (`transform: Translate { y:
myHover.hovered ? -2 : 0 }`) moves its hit box away from a resting pointer and
oscillates hover on/off every frame near the edge. Such items must set
`containmentMask: C.LiftMask { ... }` (components/LiftMask.qml).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "app" / "qml"
CLEAR = re.compile(r'"transparent"|Qt\.rgba\(\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*\)')
BIND = re.compile(r'^(\s*)((?:[\w]+\.)?[\w]*[cC]olor)\s*:\s*(.*)$')
CONT = re.compile(r'^\s*(\?|:(?!\s*\w+\s*\{)|\|\||&&|\+)')


def _strip_strings(s):
    return re.sub(r'"[^"\n]*"', '""', s)


def _depths(lines):
    """Brace depth at the START of every line (comments/strings ignored)."""
    out, d = [], 0
    for ln in lines:
        out.append(d)
        code = _strip_strings(ln.split("//", 1)[0])
        d += code.count("{") - code.count("}")
    return out


def _object_span(lines, depths, i):
    """Line range of the object whose body contains line i."""
    d = depths[i]
    a = i
    while a > 0 and depths[a] >= d:
        a -= 1
    b = i
    while b + 1 < len(lines) and depths[b + 1] >= d:
        b += 1
    return a, b


def _expr_end(lines, i):
    j = i
    while j + 1 < len(lines):
        cur = lines[j].split("//", 1)[0].rstrip()
        nxt = lines[j + 1]
        open_p = sum(_strip_strings(l.split("//", 1)[0]).count("(") -
                     _strip_strings(l.split("//", 1)[0]).count(")")
                     for l in lines[i:j + 1])
        if open_p > 0 or cur.endswith(("?", ":", "||", "&&", "+", ",")) or CONT.match(nxt):
            j += 1
            continue
        break
    return j


def _alternatives(expr):
    """The value branches of a (possibly chained) ternary, in order. A piece
    followed by '?' is a condition, everything else is a value."""
    pieces, seps, depth, cur = [], [], 0, ""
    in_str = False
    for ch in expr:
        if ch == '"':
            in_str = not in_str
        if not in_str:
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
            if depth == 0 and ch in "?:":
                pieces.append(cur.strip())
                seps.append(ch)
                cur = ""
                continue
        cur += ch
    pieces.append(cur.strip())
    seps.append("$")
    return [p for p, sp in zip(pieces, seps) if sp != "?"]


def _reference(vals):
    """The colour the transparent branch fades to/from: its neighbour."""
    for k, v in enumerate(vals):
        if CLEAR.fullmatch(v):
            for cand in (vals[k - 1] if k > 0 else None,
                         vals[k + 1] if k + 1 < len(vals) else None):
                if cand and not CLEAR.fullmatch(cand):
                    return cand
    return None


def _strip_strings_keep(s):
    return s


def scan(fix=False):
    found = []
    for f in sorted(ROOT.rglob("*.qml")):
        text = f.read_text(encoding="utf-8")
        lines = text.split("\n")
        depths = _depths(lines)
        changed = False
        i = 0
        while i < len(lines):
            m = BIND.match(lines[i])
            if not m or m.group(2).startswith("property"):
                i += 1
                continue
            prop = m.group(2)
            j = _expr_end(lines, i)
            expr = "\n".join(lines[i:j + 1])
            code = expr.split(":", 1)[1]
            if not CLEAR.search(code):
                i = j + 1
                continue
            a, b = _object_span(lines, depths, i)
            body = "\n".join(lines[a:b + 1])
            short = prop.split(".")[-1] if prop.startswith("border.") else prop
            if not re.search(r'Behavior\s+on\s+' + re.escape(prop) + r'\b', body):
                i = j + 1
                continue
            joined = " ".join(l.split("//", 1)[0].strip() for l in lines[i:j + 1])
            ref = _reference(_alternatives(joined.split(":", 1)[1]))
            found.append((f, i + 1, prop, ref))
            if fix and ref:
                for k in range(i, j + 1):
                    head, sep, tail = lines[k].partition("//")
                    if k == i:
                        pre, colon, rest = head.partition(":")
                        head = pre + colon + CLEAR.sub("U.withAlpha(%s, 0)" % ref, rest)
                    else:
                        head = CLEAR.sub("U.withAlpha(%s, 0)" % ref, head)
                    lines[k] = head + sep + tail
                changed = True
            i = j + 1
        if changed:
            if 'as U' not in text:
                # every component that animates colour already imports Utils;
                # bail loudly rather than guess the relative path.
                raise SystemExit("%s: needs `import \"../Utils.js\" as U`" % f)
            f.write_text("\n".join(lines), encoding="utf-8")
    return found


LIFT = re.compile(r'transform:\s*Translate\s*\{[^}]*?[xy]:\s*(\w+)\.hovered\s*\?', re.S)


def scan_lifts():
    bad = []
    for f in sorted(ROOT.rglob("*.qml")):
        lines = f.read_text(encoding="utf-8").split("\n")
        depths = _depths(lines)
        text = "\n".join(lines)
        for m in LIFT.finditer(text):
            ln = text.count("\n", 0, m.start())
            a, b = _object_span(lines, depths, ln)
            body = "\n".join(lines[a:b + 1])
            own = re.search(r'HoverHandler\s*\{\s*id:\s*' + m.group(1) + r'\b', body)
            if own and "containmentMask" not in body:
                bad.append((f, ln + 1))
    return bad


OVERLAY = re.compile(r'hovered\s*\?\s*U\.withAlpha\([^()]*(?:\([^()]*\))?[^()]*\)\s*:\s*'
                     r'Theme\.(input_bg|surface\w*|card\w*|dropdown_bg|bg\w*)\b')


def scan_overlays():
    bad = []
    for f in sorted(ROOT.rglob("*.qml")):
        lines = f.read_text(encoding="utf-8").split("\n")
        depths = _depths(lines)
        for i, ln in enumerate(lines):
            if not OVERLAY.search(ln):
                continue
            a, b = _object_span(lines, depths, i)
            if re.search(r'Behavior\s+on\s+color\b', "\n".join(lines[a:b + 1])):
                bad.append((f, i + 1))
    return bad


if __name__ == "__main__":
    fix = "--fix" in sys.argv
    for f, ln in scan_overlays():
        print("%s:%d  fades an opaque fill to a translucent overlay (use U.mix)" % (
            f.relative_to(ROOT.parent.parent), ln))
    lifts = scan_lifts()
    for f, ln in lifts:
        print("%s:%d  lifts itself on hover without LiftMask" % (
            f.relative_to(ROOT.parent.parent), ln))
    hits = scan(fix=fix)
    if lifts and not hits:
        sys.exit(1)
    for f, ln, prop, ref in hits:
        print("%s:%d  %s fades from transparent -> %s" % (
            f.relative_to(ROOT.parent.parent), ln, prop,
            ref or "?? (fix by hand)"))
    if hits and not fix:
        print("\n%d flashing colour fade(s). Run with --fix." % len(hits))
        sys.exit(1)
    print("fixed %d" % len(hits) if fix else "clean")
