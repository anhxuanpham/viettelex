"""Fixture parity FUTO Swipe (Swift/Kotlin): đầu vào + đầu ra tham chiếu từ forward python (mine.py, weights fp16).

python3 gen_fixture.py futo_swipe_encoder.f16.bin swipe-paths.txt out.txt
"""
import math
import sys
import mine
import common as E


def interp(xs, xp, fp):
    return E.interp(xs, xp, fp)


def resample(px, py, pt, T=64):
    """Kiểu README nhưng làm tròn floor(x+0.5) (không banker's rounding) — y hệt Swift/Kotlin."""
    t = [v - pt[0] for v in pt]
    x, y = list(px), list(py)
    if t[-1] > 1e-3:
        n60 = max(2, int(math.floor(t[-1] / (1000.0 / 60.0) + 0.5)) + 1)
        tt = E.linspace(0.0, t[-1], n60)
        x, y = interp(tt, t, x), interp(tt, t, y)
    idx = E.linspace(0, len(x) - 1, T)
    ar = list(range(len(x)))
    return interp(idx, ar, x) + interp(idx, ar, y)


def qwerty_keys(kw=40.0, rh=54.0):
    rows = [("qwertyuiop", 0.5), ("asdfghjkl", 1.0), ("zxcvbnm", 2.0)]
    c = {}
    for r, (row, x0) in enumerate(rows):
        for i, ch in enumerate(row):
            c[ch] = ((x0 + i) * kw, (r + 0.5) * rh)
    return c


def norm_frame(centers, kw):
    xs = [p[0] for p in centers.values()]
    ys = [p[1] for p in centers.values()]
    x0 = min(xs) - kw / 2
    wd = max(xs) - min(xs) + kw
    rh = (max(ys) - min(ys)) / 2
    y0 = min(ys) - rh / 2
    ht = 3 * rh
    return x0, wd, y0, ht


def clip(v):
    return min(max(v, 0.0), 1.0)


def minjerk_path(word, cen, kw=40.0):
    """Nhịp minimum-jerk như FutoSim (không nhiễu): đoạn 120 ms + 300 ms·√(d/bàn phím), 60 Hz."""
    ks = ''.join(c for i, c in enumerate(word) if i == 0 or word[i - 1] != c)
    cx = [cen[c][0] for c in ks]
    cy = [cen[c][1] for c in ks]

    def cat(p0, p1, p2, p3, t):
        t2 = t * t
        t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    out, t, m = [], 0.0, len(ks)
    for s in range(m - 1):
        i0, i1, i2, i3 = max(s - 1, 0), s, s + 1, min(s + 2, m - 1)
        d = math.hypot(cx[i2] - cx[i1], cy[i2] - cy[i1])
        n = max(2, math.ceil((0.120 + 0.300 * math.sqrt(d / (10 * kw))) * 60))
        for j in range(n):
            tau = j / n
            u = tau ** 3 * (10 - 15 * tau + 6 * tau * tau)
            out.append((cat(cx[i0], cx[i1], cx[i2], cx[i3], u), cat(cy[i0], cy[i1], cy[i2], cy[i3], u), t))
            t += 1000.0 / 60.0
    out.append((cx[-1], cy[-1], t))
    return out


def fmt(a):
    return ','.join('%.6g' % v for v in a)


def f32(a):
    """Làm tròn về float32 (đầu vào model phía Swift/Kotlin là Float) — in bằng %.9g là khứ hồi đúng."""
    import struct
    return [struct.unpack('<f', struct.pack('<f', v))[0] for v in a]


def fmt9(a):
    return ','.join('%.9g' % v for v in a)


def main():
    W = mine.load(sys.argv[1])
    paths = {}
    for line in open(sys.argv[2]):
        if line.startswith('#') or not line.strip():
            continue
        p = line.rstrip('\n').split('\t')
        paths[p[0]] = [tuple(map(float, q.split(','))) for q in p[2].split(';')]
    out = ['# futo-swipe-fixture v2 — parity suy luận FUTO Swipe (Swift/Kotlin). Sinh bởi Scripts/futo-swipe/gen_fixture.py',
           '# từ forward python thuần (weights fp16 futoswipe.bin). Mỗi ca: name, keys (nk; x,y chuẩn hoá 0-1 theo a…z),',
           '# raw (x,y,t_ms theo layout qwerty(keyWidth 40, rowHeight 54)), feats (2×64), logem (32×(nk+1), cột cuối = blank).']
    # ca 1: đường tiếng Anh "computer" TỰ SINH (minimum-jerk, không nhiễu) theo layout qwerty(40, 54)
    cen = qwerty_keys()
    comp = minjerk_path('computer', cen)
    paths['computer'] = [(x, y) for x, y, _ in comp]
    times = {'computer': [t for _, _, t in comp]}
    # ca 2-4: đường vuốt giả tiếng Việt từ swipe-paths.txt (nhịp đều 60 Hz), layout qwerty(40, 54)
    x0, wd, y0, ht = norm_frame(cen, 40.0)
    nkeys = []
    for ch in E.LETTERS:
        nkeys += [(cen[ch][0] - x0) / wd, (cen[ch][1] - y0) / ht]
    for word in ['computer', 'khong', 'nguoi', 'duoc']:
        pts = paths[word]
        ts = times.get(word) or [i * 1000.0 / 60.0 for i in range(len(pts))]
        raw = [(x, y, t) for (x, y), t in zip(pts, ts)]
        px = [clip((x - x0) / wd) for x, _, _ in raw]
        py = [clip((y - y0) / ht) for _, y, _ in raw]
        pt = [t for _, _, t in raw]
        feats = f32(resample(px, py, pt))
        le, lam, _ = mine.forward(W, feats, f32(nkeys))
        out += ['case ' + word, 'keys ' + fmt9(f32(nkeys)),
                'raw ' + ';'.join('%.2f,%.2f,%.4f' % r for r in raw),
                'feats ' + fmt9(feats), 'logem ' + fmt(le), 'greedy ' + E.greedy(le, 27)]
        print(word, E.greedy(le, 27))
    open(sys.argv[3], 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
