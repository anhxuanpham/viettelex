"""Parse an ExecuTorch .pte (with XNNPACK delegates) into a python graph description."""
import struct
import sys
from fb import T, root

KT = {0: 'NONE', 1: 'Null', 2: 'Int', 3: 'Bool', 4: 'Double', 5: 'Tensor', 6: 'String',
      7: 'IntList', 8: 'DoubleList', 9: 'BoolList', 10: 'TensorList', 11: 'OptionalTensorList'}
XNODE = ['NONE', 'Add', 'FullyConnected', 'Softmax', 'Sigmoid', 'StaticTranspose', 'Clamp', 'Conv2d', 'Div',
         'StaticResizeBilinear2D', 'StaticConstantPad', 'AvgPooling2d', 'Minimum', 'DepthwiseConv2d',
         'MaxPooling2d', 'Multiply', 'Subtract', 'Floor', 'Convert', 'GlobalAvgPooling2d', 'StaticReshape',
         'ArgMaxPooling2d', 'SquareRoot', 'Ceiling', 'Hardswish', 'LeakyReLU', 'Maximum', 'Negate', 'Square',
         'ELU', 'Abs', 'PReLU', 'Concatenate2', 'Concatenate3', 'Concatenate4', 'StaticSlice',
         'ScaledDotProductAttention', 'BatchMatrixMultiply', 'Concatenate5', 'ConvTranspose2d',
         'ReciprocalSquareRoot', 'Log', 'Gelu', 'Tanh', 'Exp', 'Sin', 'Copy', 'Cos']
N2x1 = {'Add', 'Div', 'Minimum', 'Multiply', 'Subtract', 'Maximum', 'PReLU', 'BatchMatrixMultiply'}
N1x1 = {'Softmax', 'Sigmoid', 'Clamp', 'Floor', 'Convert', 'GlobalAvgPooling2d', 'SquareRoot', 'Ceiling',
        'Hardswish', 'Negate', 'Square', 'Abs', 'ReciprocalSquareRoot', 'Log', 'Gelu', 'Tanh', 'Exp', 'Sin',
        'Copy', 'Cos'}
CONV = {'Conv2d', 'DepthwiseConv2d', 'ConvTranspose2d'}
CONV_F = ['padding_top', 'padding_right', 'padding_bottom', 'padding_left', 'kernel_height', 'kernel_width',
          'subsampling_height', 'subsampling_width', 'dilation_height', 'dilation_width',
          'group_input_channels', 'group_output_channels', 'groups', 'adjustment_height', 'adjustment_width',
          'input1_id', 'filter_id', 'bias_id', 'output_id', 'flags']


def f32(b):
    return list(struct.unpack('<%df' % (len(b) // 4), b))


def load(path):
    buf = open(path, 'rb').read()
    assert buf[4:8] == b'ET12'
    assert buf[8:12] == b'eh00'
    seg_base = struct.unpack_from('<Q', buf, 24)[0]
    prog = root(buf)
    segs = [(s.scalar(0, 'Q'), s.scalar(1, 'Q')) for s in prog.vec_table(4)]

    def segment(i):
        o, n = segs[i]
        return buf[seg_base + o: seg_base + o + n]

    named = {nd.string(0): nd.scalar(1, 'I') for nd in prog.vec_table(7)}
    plan = prog.vec_table(1)[0]
    values = []
    for ev in plan.vec_table(2):
        t = ev.scalar(0, 'B')
        v = ev.table(1)
        k = KT[t]
        if k == 'Tensor':
            values.append(('Tensor', dict(dtype=v.scalar(0, 'b'), sizes=v.vec_scalar(2, 'i'),
                                          dim_order=list(v.vec_bytes(3)), buf=v.scalar(5, 'I'),
                                          alloc=(lambda a: None if a is None else (a.scalar(0,'I'), a.scalar(1,'I'), a.scalar(2,'I')))(v.table(6)))))
        elif k == 'Int':
            values.append(('Int', v.scalar(0, 'q')))
        elif k == 'Bool':
            values.append(('Bool', v.scalar(0, 'B')))
        elif k == 'Double':
            values.append(('Double', v.scalar(0, 'd')))
        elif k == 'IntList':
            values.append(('IntList', v.vec_scalar(0, 'q')))
        elif k == 'BoolList':
            values.append(('BoolList', v.vec_scalar(0, 'B')))
        elif k in ('TensorList', 'OptionalTensorList'):
            values.append((k, v.vec_scalar(0, 'i')))
        elif k == 'String':
            values.append(('String', v.string(0)))
        else:
            values.append((k, None))
    ops = [(o.string(0), o.string(1)) for o in plan.vec_table(6)]
    instrs = []
    for ch in plan.vec_table(5):
        for ins in ch.vec_table(2):
            t = ins.scalar(0, 'B')
            a = ins.table(1)
            if t == 1:
                instrs.append(('kernel', ops[a.scalar(0, 'i')], a.vec_scalar(1, 'i')))
            elif t == 2:
                instrs.append(('delegate', a.scalar(0, 'i'), a.vec_scalar(1, 'i')))
            elif t == 5:
                instrs.append(('free', a.scalar(0, 'i')))
            else:
                instrs.append(('other', t))
    # constant buffer (non-delegated constants): constant_segment
    cseg = prog.table(5)
    const_offsets = cseg.vec_scalar(1, 'Q') if cseg else []
    const_seg = segment(cseg.scalar(0, 'I')) if cseg and segs else b''
    delegates = []
    for d in plan.vec_table(7):
        ref = d.table(1)
        loc, idx = ref.scalar(0, 'b'), ref.scalar(1, 'I')
        blob = segment(idx) if loc == 1 else prog.vec_table(3)[idx].vec_bytes(0)
        delegates.append(parse_xnn(blob, named, segment))
    return dict(values=values, instrs=instrs, inputs=plan.vec_scalar(3, 'i'), outputs=plan.vec_scalar(4, 'i'),
                const_offsets=const_offsets, const_seg=const_seg, delegates=delegates)


def parse_xnn(blob, named, segment):
    assert blob[4:8] == b'XH00', blob[:16]
    fb_off, fb_size = struct.unpack_from('<II', blob, 10)
    cd_off, cd_size = struct.unpack_from('<QQ', blob, 18)
    g = root(blob, fb_off)
    g = T(blob, g.pos)
    cdata = blob[cd_off:cd_off + cd_size]
    consts = []
    for c in g.vec_table(8):
        key = c.string(2)
        if key:
            consts.append(('named', key, f32(segment(named[key]))))
        else:
            o, n = c.scalar(0, 'Q'), c.scalar(1, 'Q')
            consts.append(('inline', None, f32(cdata[o:o + n]) if n else None))
    xvals = {}
    for xv in g.vec_table(2):
        t = xv.scalar(0, 'B')
        v = xv.table(1)
        if t == 2:
            v = v.table(0)
        tv = dict(dtype=v.scalar(0, 'h'), dims=v.vec_scalar(2, 'I'), cbuf=v.scalar(3, 'I'),
                  ext=v.scalar(4, 'I'), flags=v.scalar(5, 'I'), id=v.scalar(6, 'I'))
        xvals[tv['id']] = tv
    nodes = []
    for xn in g.vec_table(1):
        t = xn.scalar(0, 'B')
        name = XNODE[t]
        v = xn.table(1)
        mm = xn.table(3)
        d = {'op': name}
        if mm:
            d['min'] = mm.scalar(0, 'f')
            d['max'] = mm.scalar(1, 'f')
        if name in N2x1:
            d.update(a=v.scalar(0, 'I'), b=v.scalar(1, 'I'), out=v.scalar(2, 'I'))
        elif name in N1x1:
            d.update(a=v.scalar(0, 'I'), out=v.scalar(1, 'I'))
        elif name in CONV:
            for i, f in enumerate(CONV_F):
                d[f] = v.scalar(i, 'I')
            d['a'] = d['input1_id']
            d['out'] = d['output_id']
        elif name == 'FullyConnected':
            d.update(a=v.scalar(0, 'I'), filter=v.scalar(1, 'I'), bias=v.scalar(2, 'I'), out=v.scalar(3, 'I'),
                     flags=v.scalar(4, 'I'))
        elif name == 'StaticTranspose':
            d.update(perm=v.vec_scalar(1, 'I'), a=v.scalar(2, 'I'), out=v.scalar(3, 'I'))
        elif name == 'StaticReshape':
            d.update(shape=v.vec_scalar(1, 'I'), a=v.scalar(2, 'I'), out=v.scalar(3, 'I'))
        elif name == 'StaticSlice':
            d.update(offsets=v.vec_scalar(1, 'I'), sizes=v.vec_scalar(2, 'I'), a=v.scalar(3, 'I'),
                     out=v.scalar(4, 'I'))
        elif name == 'StaticConstantPad':
            d.update(pre=v.vec_scalar(0, 'I'), post=v.vec_scalar(1, 'I'), value=v.scalar(2, 'f'),
                     a=v.scalar(3, 'I'), out=v.scalar(4, 'I'))
        elif name.startswith('Concatenate'):
            d.update(axis=v.scalar(0, 'I'), ins=[v.scalar(i, 'I') for i in (1, 2, 3, 4, 7)], out=v.scalar(5, 'I'))
        elif name in ('AvgPooling2d', 'MaxPooling2d'):
            fl = ['pt', 'pr', 'pb', 'pl', 'ph', 'pw', 'sh', 'sw', 'dh', 'dw', 'a', 'out', 'flags']
            for i, f in enumerate(fl):
                d[f] = v.scalar(i, 'I')
        elif name in ('LeakyReLU', 'ELU'):
            d.update(alpha=v.scalar(0, 'f'), a=v.scalar(1, 'I'), out=v.scalar(2, 'I'))
        else:
            d['raw'] = True
        nodes.append(d)
    return dict(nodes=nodes, xvals=xvals, consts=consts, inputs=g.vec_scalar(4, 'I'),
                outputs=g.vec_scalar(5, 'I'), version=g.string(0))


if __name__ == '__main__':
    m = load(sys.argv[1])
    print('inputs', m['inputs'], 'outputs', m['outputs'])
    for i, v in enumerate(m['values']):
        if v[0] != 'Tensor':
            print('  v%d' % i, v)
        else:
            print('  v%d Tensor %s' % (i, v[1]))
    for ins in m['instrs']:
        print(ins)
    for di, d in enumerate(m['delegates']):
        print('--- delegate', di, 'in', d['inputs'], 'out', d['outputs'])
        for n in d['nodes']:
            nn = {k: v for k, v in n.items() if k not in ('op',)}
            print('   ', n['op'], nn)
        for vid, tv in sorted(d['xvals'].items()):
            c = d['consts'][tv['cbuf']] if tv['cbuf'] else None
            print('     x%d dims=%s dt=%d ext=%d flags=%d %s' % (vid, tv['dims'], tv['dtype'], tv['ext'], tv['flags'],
                                                               ('const:' + str(c[1])[:60] + ' n=' + str(len(c[2]) if c[2] else 0)) if c else ''))
