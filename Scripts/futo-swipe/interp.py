"""Pure-python interpreter for the FUTO Swipe encoder .pte graph (reference, slow)."""
import math
import struct
import pte as P

NONE_ID = 4294967295


def numel(s):
    n = 1
    for d in s:
        n *= d
    return n


def strides(s):
    st = [1] * len(s)
    for i in range(len(s) - 2, -1, -1):
        st[i] = st[i + 1] * s[i + 1]
    return st


class Ten:
    def __init__(self, shape, data):
        self.shape = list(shape)
        self.data = data
        assert len(data) == numel(shape), (shape, len(data))


def bshape(a, b):
    n = max(len(a), len(b))
    a = [1] * (n - len(a)) + list(a)
    b = [1] * (n - len(b)) + list(b)
    out = []
    for x, y in zip(a, b):
        assert x == y or x == 1 or y == 1, (a, b)
        out.append(max(x, y))
    return a, b, out


def broadcast_to(t, shape):
    s = [1] * (len(shape) - len(t.shape)) + t.shape
    if s == list(shape):
        return t.data
    st = strides(s)
    ost = strides(shape)
    out = [0.0] * numel(shape)
    for i in range(len(out)):
        r = i
        src = 0
        for d in range(len(shape)):
            q = r // ost[d]
            r -= q * ost[d]
            if s[d] != 1:
                src += q * st[d]
        out[i] = t.data[src]
    return out


def binop(a, b, f):
    _, _, o = bshape(a.shape, b.shape)
    x = broadcast_to(a, o)
    y = broadcast_to(b, o)
    return Ten(o, [f(p, q) for p, q in zip(x, y)])


def transpose(t, perm):
    shape = [t.shape[p] for p in perm]
    ist = strides(t.shape)
    ost = strides(shape)
    out = [0.0] * len(t.data)
    for i in range(len(out)):
        r = i
        src = 0
        for d in range(len(shape)):
            q = r // ost[d]
            r -= q * ost[d]
            src += q * ist[perm[d]]
        out[i] = t.data[src]
    return Ten(shape, out)


def slice_(t, offs, sizes):
    ist = strides(t.shape)
    ost = strides(sizes)
    out = [0.0] * numel(sizes)
    for i in range(len(out)):
        r = i
        src = 0
        for d in range(len(sizes)):
            q = r // ost[d]
            r -= q * ost[d]
            src += (q + offs[d]) * ist[d]
        out[i] = t.data[src]
    return Ten(sizes, out)


def concat(ts, axis):
    shape = list(ts[0].shape)
    shape[axis] = sum(t.shape[axis] for t in ts)
    outer = numel(shape[:axis])
    out = []
    for o in range(outer):
        for t in ts:
            inner = numel(t.shape[axis:])
            out.extend(t.data[o * inner:(o + 1) * inner])
    return Ten(shape, out)


def conv_nhwc(x, w, b, n):
    """x [1,H,W=1,C], w: Conv2d [O,kh,1,Cin/g]; Depthwise [1,kh,1,C*mult]."""
    _, H, W, C = x.shape
    assert W == 1
    kh, dil, sub = n['kernel_height'], n['dilation_height'], n['subsampling_height']
    pt, pb = n['padding_top'], n['padding_bottom']
    Ho = (H + pt + pb - dil * (kh - 1) - 1) // sub + 1
    dw = n['op'] == 'DepthwiseConv2d'
    if dw:
        O = w.shape[3]
    else:
        O = w.shape[0]
    cin_g = n['group_input_channels']
    out = [0.0] * (Ho * O)
    X = x.data
    Wd = w.data
    for h in range(Ho):
        for o in range(O):
            acc = b.data[o] if b is not None else 0.0
            for k in range(kh):
                hi = h * sub - pt + k * dil
                if hi < 0 or hi >= H:
                    continue
                if dw:
                    # channel multiplier 1 (group_output_channels==1)
                    acc += X[hi * C + o] * Wd[k * O + o]
                else:
                    g = o // n['group_output_channels']
                    base = hi * C + g * cin_g
                    wb = (o * kh + k) * cin_g
                    for c in range(cin_g):
                        acc += X[base + c] * Wd[wb + c]
            out[h * O + o] = acc
    return Ten([1, Ho, 1, O], out)


def run(model, feats, keys, mask):
    vals = {}
    addr = {}
    V = model['values']
    cseg = model['const_seg']
    coffs = model['const_offsets']

    def get(i):
        if i in vals:
            return vals[i]
        k, v = V[i]
        if k == 'Tensor':
            if v['buf'] > 0:
                n = numel(v['sizes'])
                off = coffs[v['buf']]
                if v['dtype'] == 6:
                    data = list(struct.unpack_from('<%df' % n, cseg, off))
                elif v['dtype'] == 4:
                    data = [float(x) for x in struct.unpack_from('<%dq' % n, cseg, off)]
                else:
                    raise Exception('dtype %d' % v['dtype'])
                t = Ten(v['sizes'], data)
                vals[i] = t
                return t
            al = v.get('alloc')
            if al in addr:
                src = addr[al]
                t = Ten(v['sizes'], src.data)
                return t
            raise KeyError('uninit tensor v%d' % i)
        return v

    def ival(i):
        k, v = V[i]
        if k == 'IntList':
            return [ival(j) for j in v]
        return v

    class VD(dict):
        def __setitem__(self, k, t):
            dict.__setitem__(self, k, t)
            kk, vv = V[k]
            if kk == 'Tensor' and vv.get('alloc') is not None:
                addr[vv['alloc']] = t
    vals = VD()
    ins = model['inputs']
    vals[ins[0]] = Ten([1, 2, 64], feats)
    vals[ins[1]] = Ten([1, 64, 2], keys)
    vals[ins[2]] = Ten([1, 64], [1.0 if m else 0.0 for m in mask])

    for instr in model['instrs']:
        if instr[0] == 'free':
            continue
        if instr[0] == 'kernel':
            (name, ov), a = instr[1], instr[2]
            out = a[-1]
            if name == 'aten::arange':
                s, e, st = ival(a[0]), ival(a[1]), ival(a[2])
                r = [float(x) for x in range(s, e, st)]
                vals[out] = Ten([len(r)], r)
            elif name == 'aten::scalar_tensor':
                vals[out] = Ten([], [ival(a[0])])
            elif name == 'dim_order_ops::_to_dim_order_copy':
                t = get(a[0])
                vals[out] = Ten(t.shape, [float(x) for x in t.data])
            elif name == 'aten::select_copy':
                t = get(a[0])
                d, idx = ival(a[1]), ival(a[2])
                offs = [0] * len(t.shape)
                offs[d] = idx
                sz = list(t.shape)
                sz[d] = 1
                r = slice_(t, offs, sz)
                del sz[d]
                vals[out] = Ten(sz, r.data)
            elif name == 'aten::unsqueeze_copy':
                t = get(a[0])
                d = ival(a[1])
                sz = list(t.shape)
                if d < 0:
                    d += len(sz) + 1
                sz.insert(d, 1)
                vals[out] = Ten(sz, t.data)
            elif name == 'aten::squeeze_copy':
                t = get(a[0])
                dims = ival(a[1])
                sz = list(t.shape)
                dims = [d + len(sz) if d < 0 else d for d in dims]
                nsz = [s for j, s in enumerate(sz) if not (j in dims and s == 1)]
                vals[out] = Ten(nsz, t.data)
            elif name == 'aten::expand_copy':
                t = get(a[0])
                size = ival(a[1])
                pad = [1] * (len(size) - len(t.shape)) + t.shape
                shape = [pad[j] if s == -1 else s for j, s in enumerate(size)]
                vals[out] = Ten(shape, broadcast_to(t, shape))
            elif name == 'aten::bitwise_not':
                t = get(a[0])
                vals[out] = Ten(t.shape, [0.0 if x else 1.0 for x in t.data])
            elif name == 'aten::atan2':
                vals[out] = binop(get(a[0]), get(a[1]), math.atan2)
            elif name == 'aten::full_like':
                t = get(a[0])
                vals[out] = Ten(t.shape, [float(ival(a[1]))] * len(t.data))
            elif name == 'aten::gt':
                t = get(a[0])
                s = ival(a[1])
                vals[out] = Ten(t.shape, [1.0 if x > s else 0.0 for x in t.data])
            elif name == 'aten::lt':
                t = get(a[0])
                s = ival(a[1])
                vals[out] = Ten(t.shape, [1.0 if x < s else 0.0 for x in t.data])
            elif name == 'aten::where':
                c, x, y = get(a[0]), get(a[1]), get(a[2])
                _, _, o = bshape(c.shape, x.shape)
                _, _, o = bshape(o, y.shape)
                cc, xx, yy = broadcast_to(c, o), broadcast_to(x, o), broadcast_to(y, o)
                vals[out] = Ten(o, [p if q else r for q, p, r in zip(cc, xx, yy)])
            elif name == 'aten::cumsum':
                t = get(a[0])
                d = ival(a[1])
                assert d == -1 or d == len(t.shape) - 1
                n = t.shape[-1]
                o = []
                for r in range(len(t.data) // n):
                    acc = 0.0
                    for j in range(n):
                        acc += t.data[r * n + j]
                        o.append(acc)
                vals[out] = Ten(t.shape, o)
            elif name == 'aten::split_with_sizes_copy':
                t = get(a[0])
                sizes = ival(a[1])
                d = ival(a[2])
                outs = V[a[3]][1]
                off = 0
                for j, s in enumerate(sizes):
                    offs = [0] * len(t.shape)
                    offs[d] = off
                    sz = list(t.shape)
                    sz[d] = s
                    vals[outs[j]] = slice_(t, offs, sz)
                    off += s
            elif name == 'aten::_log_softmax':
                t = get(a[0])
                n = t.shape[-1]
                o = []
                for r in range(len(t.data) // n):
                    row = t.data[r * n:(r + 1) * n]
                    m = max(row)
                    lse = m + math.log(sum(math.exp(x - m) for x in row))
                    o.extend([x - lse for x in row])
                vals[out] = Ten(t.shape, o)
            else:
                raise Exception('op ' + name)
        elif instr[0] == 'delegate':
            run_xnn(model['delegates'][instr[1]], instr[2], get, vals)
    return [vals[o] for o in model['outputs']]


def run_xnn(g, args, get, vals):
    xv = g['xvals']
    ext = {}
    for vid, tv in xv.items():
        if tv['ext'] != NONE_ID:
            ext[tv['ext']] = vid
    env = {}
    for e in sorted(ext):
        vid = ext[e]
        if xv[vid]['flags'] & 1:
            t = get(args[e])
            dims = xv[vid]['dims']
            env[vid] = Ten(dims, t.data)

    def T(i):
        if i in env:
            return env[i]
        tv = xv[i]
        if tv['cbuf']:
            c = g['consts'][tv['cbuf']]
            env[i] = Ten(tv['dims'], c[2])
            return env[i]
        raise KeyError(i)

    for n in g['nodes']:
        op = n['op']
        if op == 'StaticSlice':
            r = slice_(T(n['a']), n['offsets'], n['sizes'])
        elif op.startswith('Concatenate'):
            r = concat([T(i) for i in n['ins'] if i != NONE_ID], n['axis'])
        elif op == 'StaticReshape':
            r = Ten(n['shape'], T(n['a']).data)
        elif op == 'StaticTranspose':
            r = transpose(T(n['a']), n['perm'])
        elif op in ('Conv2d', 'DepthwiseConv2d'):
            b = T(n['bias_id']) if n['bias_id'] != NONE_ID else None
            r = conv_nhwc(T(n['a']), T(n['filter_id']), b, n)
        elif op == 'FullyConnected':
            x, w = T(n['a']), T(n['filter'])
            b = T(n['bias']) if n['bias'] != NONE_ID else None
            O, I = w.shape
            rows = len(x.data) // I
            o = []
            for r_ in range(rows):
                xr = x.data[r_ * I:(r_ + 1) * I]
                for j in range(O):
                    acc = b.data[j] if b else 0.0
                    wr = w.data[j * I:(j + 1) * I]
                    for p, q in zip(xr, wr):
                        acc += p * q
                    o.append(acc)
            r = Ten(x.shape[:-1] + [O], o)
        elif op == 'BatchMatrixMultiply':
            a, b = T(n['a']), T(n['b'])
            B, M, K = a.shape
            _, K2, N = b.shape
            o = []
            for i in range(M):
                for j in range(N):
                    o.append(sum(a.data[i * K + k] * b.data[k * N + j] for k in range(K)))
            r = Ten([B, M, N], o)
        elif op == 'GlobalAvgPooling2d':
            x = T(n['a'])
            _, H, W, C = x.shape
            o = [0.0] * C
            for i in range(H * W):
                for c in range(C):
                    o[c] += x.data[i * C + c]
            r = Ten([1, 1, 1, C], [v / (H * W) for v in o])
        elif op == 'Add':
            r = binop(T(n['a']), T(n['b']), lambda p, q: p + q)
        elif op == 'Subtract':
            r = binop(T(n['a']), T(n['b']), lambda p, q: p - q)
        elif op == 'Multiply':
            r = binop(T(n['a']), T(n['b']), lambda p, q: p * q)
        elif op == 'Div':
            r = binop(T(n['a']), T(n['b']), lambda p, q: p / q)
        else:
            x = T(n['a'])
            f = {
                'Hardswish': lambda v: v * min(max(v + 3.0, 0.0), 6.0) / 6.0,
                'Square': lambda v: v * v,
                'SquareRoot': math.sqrt,
                'Sigmoid': lambda v: 1.0 / (1.0 + math.exp(-v)) if v > -700 else 0.0,
                'Cos': math.cos,
                'Log': lambda v: math.log(v) if v > 0 else -math.inf,
                'Clamp': lambda v: v,
            }[op]
            r = Ten(x.shape, [f(v) for v in x.data])
        if 'min' in n:
            lo, hi = n['min'], n['max']
            r = Ten(r.shape, [min(max(v, lo), hi) for v in r.data])
        env[n['out']] = r
    for e in sorted(ext):
        vid = ext[e]
        if xv[vid]['flags'] & 2:
            vals[args[e]] = Ten(get_shape_hint(xv[vid]), env[vid].data)


def get_shape_hint(tv):
    return tv['dims']
