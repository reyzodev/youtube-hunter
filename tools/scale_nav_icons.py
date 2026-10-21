import re
K = {"cHistory":1.12,"cFinder":1.08,"cInsights":1.06,"cArchive":1.05,"cBulb":1.12,
     "cFlask":1.1,"cDownload":1.06,"cScissors":1.08,"cGauge":1.1}
TOK = re.compile(r'[MmLlHhVvCcSsQqAaZz]|-?(?:\d+\.?\d*|\.\d+)')
NARGS = dict(M=2,L=2,H=1,V=1,C=6,S=4,Q=4,A=7,Z=0)
def f(v): return ("%.2f" % v).rstrip('0').rstrip('.') if abs(v) > 1e-9 else "0"
def scale_path(d, k, c=12):
    toks = TOK.findall(d); out = []; i = 0; cmd = None
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t; out.append(t); i += 1
            if cmd in 'Zz': continue
        C = cmd.upper(); rel = cmd.islower(); n = NARGS[C]
        args = [float(x) for x in toks[i:i+n]]; i += n
        res = []
        for j, v in enumerate(args):
            if C == 'A' and j in (2, 3, 4):
                res.append(f(v) if j == 2 else str(int(v)))
            elif C == 'A' and j in (0, 1):
                res.append(f(v * k))
            else:
                res.append(f(v * k) if rel else f(c + (v - c) * k))
        out.append(" ".join(res))
        if C == 'M': cmd = 'l' if rel else 'L'
    s = ""
    for o in out:
        s += o if o.isalpha() else ((" " if s and not s[-1].isalpha() else "") + o)
    return s
def scale_block(b, k):
    b = re.sub(r'd: "([^"]+)"', lambda m: 'd: "%s"' % scale_path(m.group(1), k), b)
    b = re.sub(r'\b(cx|cy|origin\.x|origin\.y): ([\d.]+)', lambda m: "%s: %s" % (m.group(1), f(12 + (float(m.group(2)) - 12) * k)), b)
    b = re.sub(r'\br: ([\d.]+)', lambda m: "r: %s" % f(float(m.group(1)) * k), b)
    b = re.sub(r'x: 20 - width / 2; y: 6.5 - height / 2', 'x: %s - width / 2; y: %s - height / 2' % (f(12+8*k), f(12-5.5*k)), b)
    return b
def run(path):
    s = open(path, encoding='utf-8').read()
    parts = re.split(r'(\n    Component \{\n        id: (\w+)\n)', s)
    out = parts[0]
    for i in range(1, len(parts), 3):
        head, name, body = parts[i], parts[i+1], parts[i+2]
        out += head + (scale_block(body, K[name]) if name in K else body)
    open(path, 'w', encoding='utf-8').write(out)
if __name__ == "__main__":
    import sys; run(sys.argv[1])
