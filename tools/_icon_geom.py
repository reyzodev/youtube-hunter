import math, re
from shapely.geometry import Polygon, LineString, Point, MultiPolygon, GeometryCollection
from shapely.ops import unary_union
from shapely import make_valid

TOK = re.compile(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?')

def _arc(x1, y1, rx, ry, phi, fa, fs, x2, y2, n=None):
    if rx == 0 or ry == 0:
        return [(x2, y2)]
    phi = math.radians(phi); c, s = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = c * dx + s * dy, -s * dx + c * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p**2 / rx**2 + y1p**2 / ry**2
    if lam > 1:
        rx *= math.sqrt(lam); ry *= math.sqrt(lam)
    num = rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p
    den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
    co = math.sqrt(max(0, num / den)) if den else 0
    if fa == fs: co = -co
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = c * cxp - s * cyp + (x1 + x2) / 2
    cy = s * cxp + c * cyp + (y1 + y2) / 2
    def ang(ux, uy, vx, vy):
        a = math.atan2(ux*vy - uy*vx, ux*vx + uy*vy); return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0: dt -= 2 * math.pi
    elif fs and dt < 0: dt += 2 * math.pi
    n = n or max(4, int(abs(dt) * max(rx, ry) * 4))
    pts = []
    for i in range(1, n + 1):
        t = t1 + dt * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((c * x - s * y + cx, s * x + c * y + cy))
    return pts

def parse_path(d):
    """-> list of (points, closed) subpaths"""
    toks = TOK.findall(d); i = 0
    subs = []; cur = []; x = y = 0; sx = sy = 0; cmd = None; lc = None
    def num():
        nonlocal i; v = float(toks[i]); i += 1; return v
    def flag():
        # arc flags may be glued ("01")
        nonlocal i
        t = toks[i]
        if len(t) > 1 and t[0] in '01' and not t.startswith(('0.', '1.')):
            toks[i] = t[1:]; return int(t[0])
        i += 1; return int(float(t))
    while i < len(toks):
        t = toks[i]
        if re.match(r'[A-Za-z]', t):
            cmd = t; i += 1
            if cmd in 'Zz':
                if cur: subs.append((cur, True))
                cur = []; x, y = sx, sy; lc = None
                continue
        rel = cmd.islower(); C = cmd.upper()
        ox, oy = (x, y) if rel else (0, 0)
        if C == 'M':
            if cur: subs.append((cur, False))
            x, y = num() + ox, num() + oy; sx, sy = x, y; cur = [(x, y)]
            cmd = 'l' if rel else 'L'; lc = None
        elif C == 'L':
            x, y = num() + ox, num() + oy; cur.append((x, y)); lc = None
        elif C == 'H':
            x = num() + (x if rel else 0); cur.append((x, y)); lc = None
        elif C == 'V':
            y = num() + (y if rel else 0); cur.append((x, y)); lc = None
        elif C in 'CS':
            if C == 'C':
                x1, y1 = num() + ox, num() + oy
            else:
                x1, y1 = (2*x - lc[0], 2*y - lc[1]) if lc else (x, y)
            x2, y2 = num() + ox, num() + oy; ex, ey = num() + ox, num() + oy
            for k in range(1, 17):
                tt = k / 16; mt = 1 - tt
                cur.append((mt**3*x + 3*mt*mt*tt*x1 + 3*mt*tt*tt*x2 + tt**3*ex,
                            mt**3*y + 3*mt*mt*tt*y1 + 3*mt*tt*tt*y2 + tt**3*ey))
            lc = (x2, y2); x, y = ex, ey
        elif C == 'A':
            rx, ry, ph = num(), num(), num(); fa = flag(); fs = flag()
            ex, ey = num() + ox, num() + oy
            cur += _arc(x, y, rx, ry, ph, fa, fs, ex, ey); x, y = ex, ey; lc = None
        else:
            raise ValueError(cmd)
    if cur: subs.append((cur, False))
    return subs

def attrs(el):
    return dict(re.findall(r'([\w-]+)="([^"]*)"', el))

def element_subpaths(el):
    a = attrs(el); tag = re.match(r'<(\w+)', el).group(1)
    f = lambda k, d=0: float(a.get(k, d))
    if tag == 'path':
        return parse_path(a['d'])
    if tag == 'circle':
        cx, cy, r = f('cx'), f('cy'), f('r')
        return [([(cx + r*math.cos(2*math.pi*k/96), cy + r*math.sin(2*math.pi*k/96)) for k in range(96)], True)]
    if tag == 'ellipse':
        cx, cy, rx, ry = f('cx'), f('cy'), f('rx'), f('ry')
        return [([(cx + rx*math.cos(2*math.pi*k/96), cy + ry*math.sin(2*math.pi*k/96)) for k in range(96)], True)]
    if tag == 'rect':
        x, y, w, h, r = f('x'), f('y'), f('width'), f('height'), f('rx')
        r = min(r, w/2, h/2)
        d = (f"M{x+r} {y}H{x+w-r}A{r} {r} 0 0 1 {x+w} {y+r}V{y+h-r}A{r} {r} 0 0 1 {x+w-r} {y+h}"
             f"H{x+r}A{r} {r} 0 0 1 {x} {y+h-r}V{y+r}A{r} {r} 0 0 1 {x+r} {y}Z") if r > 0 else \
            f"M{x} {y}H{x+w}V{y+h}H{x}Z"
        return parse_path(d)
    raise ValueError(tag)

def fill_region(el):
    polys = []
    for pts, closed in element_subpaths(el):
        if len(pts) >= 3:
            polys.append(make_valid(Polygon(pts)))
    return unary_union(polys) if polys else GeometryCollection()

def stroke_region(el, w):
    gs = []
    for pts, closed in element_subpaths(el):
        if closed and pts[0] != pts[-1]: pts = pts + [pts[0]]
        if len(pts) == 1: gs.append(Point(pts[0]).buffer(w/2, 32)); continue
        gs.append(LineString(pts).buffer(w/2, quad_segs=16, cap_style='round', join_style='round'))
    return unary_union(gs)

def to_d(g, prec=2):
    out = []
    polys = [g] if g.geom_type == 'Polygon' else [p for p in getattr(g, 'geoms', []) if p.geom_type == 'Polygon']
    for p in polys:
        p = p.simplify(0.015)
        for ring in [p.exterior] + list(p.interiors):
            cs = list(ring.coords)[:-1]
            if len(cs) < 3: continue
            out.append("M" + "L".join(f"{x:.{prec}f} {y:.{prec}f}" for x, y in cs) + "Z")
    return "".join(out)
