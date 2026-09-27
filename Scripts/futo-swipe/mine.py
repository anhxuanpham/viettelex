"""Hand-written forward of the FUTO Swipe encoder (clean re-implementation from the graph), python stdlib.

Mirrors exactly what Swift/Kotlin implement. Input: feats flat [2*64] (x row then y row, normalized [0,1]),
keys flat [nk*2]. Output: logem [32*(nk+1)] (last class = blank), lam [32].
"""
import math
import struct

T, C, E, H, SE, AD, NB = 64, 128, 512, 256, 32, 256, 5
DIL = [1, 2, 3, 5, 8]
SIZES = [('savgol_d1_x', 7), ('savgol_d1_y', 7), ('savgol_d2_x', 7), ('savgol_d2_y', 7), ('savgol_d1_curv', 7),
         ('in_w', C * 56), ('in_b', C)]
for _b in range(NB):
    SIZES += [('b%d_dw_w' % _b, 7 * C), ('b%d_dw_b' % _b, C), ('b%d_pw1_w' % _b, E * C), ('b%d_pw1_b' % _b, E),
              ('b%d_grn_g' % _b, H), ('b%d_grn_b' % _b, H), ('b%d_pw2_w' % _b, C * H), ('b%d_pw2_b' % _b, C),
              ('b%d_se1_w' % _b, SE * C), ('b%d_se1_b' % _b, SE), ('b%d_se2_w' % _b, C * SE),
              ('b%d_se2_b' % _b, C)]
SIZES += [('ad_w', AD * 2 * C), ('ad_b', AD), ('lam_w', AD), ('lam_b', 1), ('co_w', 64 * AD), ('co_b', 64)]


def load(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'VTFS'
    n = struct.unpack_from('<I', b, 8)[0]
    vals = struct.unpack_from('<%de' % n, b, 16)
    W = {}
    o = 0
    for k, s in SIZES:
        W[k] = list(vals[o:o + s])
        o += s
    assert o == n
    return W


def savgol(sig, w):
    p = [sig[0]] * 3 + sig + [sig[-1]] * 3
    return [sum(p[t + k] * w[k] for k in range(7)) for t in range(T)]


def features(W, f):
    x, y = f[:T], f[T:]
    vx, vy = savgol(x, W['savgol_d1_x']), savgol(y, W['savgol_d1_y'])
    ax, ay = savgol(x, W['savgol_d2_x']), savgol(y, W['savgol_d2_y'])
    th = [math.atan2(vy[t], vx[t]) for t in range(T)]
    un = [th[0]]
    acc = 0.0
    for t in range(1, T):
        d = th[t] - th[t - 1]
        corr = -2 * math.pi if d > math.pi else 0.0
        if d < -math.pi:
            corr = corr + 2 * math.pi
        acc += corr
        un.append(th[t] + acc)
    cu = [min(max(v, -2.0), 2.0) for v in savgol(un, W['savgol_d1_curv'])]
    sp = [math.sqrt(vx[t] * vx[t] + vy[t] * vy[t] + 1e-8) for t in range(T)]
    return [x, y, vx, vy, ax, ay, sp, cu]  # [8][T]


def forward(W, f, keys):
    nk = len(keys) // 2
    F = features(W, f)
    # input conv 8->128, k7, pad 3, hardswish. activations stored [T][C]
    h = [[0.0] * C for _ in range(T)]
    iw = W['in_w']
    for t in range(T):
        for o in range(C):
            a = W['in_b'][o]
            for k in range(7):
                ti = t - 3 + k
                if 0 <= ti < T:
                    base = (o * 7 + k) * 8
                    for c in range(8):
                        a += F[c][ti] * iw[base + c]
            h[t][o] = a * min(max(a + 3.0, 0.0), 6.0) / 6.0
    for b in range(NB):
        d = DIL[b]
        dw, dwb = W['b%d_dw_w' % b], W['b%d_dw_b' % b]
        z = [[0.0] * C for _ in range(T)]
        for t in range(T):
            for c in range(C):
                a = dwb[c]
                for k in range(7):
                    ti = t + (k - 3) * d
                    if 0 <= ti < T:
                        a += h[ti][c] * dw[k * C + c]
                z[t][c] = a
        p1, p1b = W['b%d_pw1_w' % b], W['b%d_pw1_b' % b]
        g = [[0.0] * H for _ in range(T)]
        for t in range(T):
            zt = z[t]
            row = []
            for o in range(E):
                wr = p1[o * C:(o + 1) * C]
                row.append(p1b[o] + sum(p * q for p, q in zip(zt, wr)))
            for j in range(H):
                s = 1.0 / (1.0 + math.exp(-row[j]))
                g[t][j] = s * row[H + j]
        # GRN
        gx = [math.sqrt(sum(g[t][j] ** 2 for t in range(T)) / T + 1e-6) for j in range(H)]
        mg = sum(gx) / H + 1e-6
        gg, gb = W['b%d_grn_g' % b], W['b%d_grn_b' % b]
        for t in range(T):
            for j in range(H):
                v = g[t][j]
                g[t][j] = gg[j] * (v * (gx[j] / mg)) + gb[j] + v
        p2, p2b = W['b%d_pw2_w' % b], W['b%d_pw2_b' % b]
        u = [[0.0] * C for _ in range(T)]
        for t in range(T):
            gt = g[t]
            for o in range(C):
                wr = p2[o * H:(o + 1) * H]
                u[t][o] = p2b[o] + sum(p * q for p, q in zip(gt, wr))
        # SE
        m = [sum(u[t][c] for t in range(T)) / T for c in range(C)]
        s1w, s1b, s2w, s2b = W['b%d_se1_w' % b], W['b%d_se1_b' % b], W['b%d_se2_w' % b], W['b%d_se2_b' % b]
        s1 = [max(0.0, s1b[j] + sum(m[c] * s1w[j * C + c] for c in range(C))) for j in range(SE)]
        s2 = [1.0 / (1.0 + math.exp(-(s2b[c] + sum(s1[j] * s2w[c * SE + j] for j in range(SE))))) for c in range(C)]
        h = [[u[t][c] * s2[c] + h[t][c] for c in range(C)] for t in range(T)]
    # adapter k2 s2 128->256
    aw, ab = W['ad_w'], W['ad_b']
    A = []
    for t2 in range(T // 2):
        row = []
        for o in range(AD):
            a = ab[o]
            for k in range(2):
                wr = aw[(o * 2 + k) * C:(o * 2 + k + 1) * C]
                a += sum(p * q for p, q in zip(h[2 * t2 + k], wr))
            row.append(a)
        A.append(row)
    lam = []
    coef = []
    for t2 in range(T // 2):
        l = W['lam_b'][0] + sum(p * q for p, q in zip(A[t2], W['lam_w']))
        lam.append(1.0 / (1.0 + math.exp(-l)))
        coef.append([W['co_b'][c] + sum(p * q for p, q in zip(A[t2], W['co_w'][c * AD:(c + 1) * AD]))
                     for c in range(64)])
    basis = []
    for k in range(nk):
        kx, ky = keys[2 * k], keys[2 * k + 1]
        bx = [math.cos(math.pi * kx * u) for u in range(8)]
        by = [math.cos(math.pi * ky * v) for v in range(8)]
        basis.append([bx[u] * by[v] for u in range(8) for v in range(8)])
    out = []
    for t2 in range(T // 2):
        lg = [sum(p * q for p, q in zip(coef[t2], basis[k])) for k in range(nk)]
        mx = max(lg)
        lse = mx + math.log(sum(math.exp(v - mx) for v in lg))
        ll = math.log(max(lam[t2], 1e-7))
        lb = math.log(max(1 - lam[t2], 1e-7))
        out.extend([max(v - lse + ll, -100.0) for v in lg])
        out.append(max(lb, -100.0))
    return out, lam, coef
