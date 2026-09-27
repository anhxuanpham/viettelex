"""Convert FUTO Swipe encoder (honorable_sturgeon model_fp32.pte) -> flat fp16 binary (VietTelex format).

Python 3 stdlib only. Usage: python3 convert.py model_fp32.pte out.bin
"""
import re
import struct
import sys
import pte as P

MAGIC = b'VTFS'
VERSION = 1
C, E, H, SE, AD, NB = 128, 512, 256, 32, 256, 5


def collect(path):
    m = P.load(path)
    named = {}
    for d in m['delegates']:
        for c in d['consts']:
            if c[0] == 'named':
                k = re.sub(r'_[0-9a-f]{64}$', '', c[1])
                named[k] = c[2]
    V = m['values']

    def const(i):
        k, v = V[i]
        n = 1
        for s in v['sizes']:
            n *= s
        return list(struct.unpack_from('<%df' % n, m['const_seg'], m['const_offsets'][v['buf']]))

    def w(name, n):
        a = named['p_encoder_' + name]
        assert len(a) == n, (name, len(a), n)
        return a

    arrays = [
        ('savgol_d1_x', w('savgol_d1_x_weight', 7)),
        ('savgol_d1_y', w('savgol_d1_y_weight', 7)),
        ('savgol_d2_x', w('savgol_d2_x_weight', 7)),
        ('savgol_d2_y', w('savgol_d2_y_weight', 7)),
        ('savgol_d1_curv', w('savgol_d1_curv_weight', 7)),
        ('in_w', w('backbone_input_conv_weight', C * 7 * 8)),
        ('in_b', w('backbone_input_conv_bias', C)),
    ]
    for b in range(NB):
        p = 'backbone_blocks_%d_' % b
        arrays += [
            ('b%d_dw_w' % b, w(p + 'dwconv_weight', 7 * C)),
            ('b%d_dw_b' % b, w(p + 'dwconv_bias', C)),
            ('b%d_pw1_w' % b, w(p + 'pwconv1_weight', E * C)),
            ('b%d_pw1_b' % b, w(p + 'pwconv1_bias', E)),
            ('b%d_grn_g' % b, const(2 * b)),
            ('b%d_grn_b' % b, const(2 * b + 1)),
            ('b%d_pw2_w' % b, w(p + 'pwconv2_weight', C * H)),
            ('b%d_pw2_b' % b, w(p + 'pwconv2_bias', C)),
            ('b%d_se1_w' % b, w(p + 'se_fc1_weight', SE * C)),
            ('b%d_se1_b' % b, w(p + 'se_fc1_bias', SE)),
            ('b%d_se2_w' % b, w(p + 'se_fc2_weight', C * SE)),
            ('b%d_se2_b' % b, w(p + 'se_fc2_bias', C)),
        ]
    arrays += [
        ('ad_w', w('adapter_0_weight', AD * 2 * C)),
        ('ad_b', w('adapter_0_bias', AD)),
        ('lam_w', w('spatial_head_lambda_proj_weight', AD)),
        ('lam_b', w('spatial_head_lambda_proj_bias', 1)),
        ('co_w', w('spatial_head_coeff_proj_weight', 64 * AD)),
        ('co_b', w('spatial_head_coeff_proj_bias', 64)),
    ]
    return arrays


def write(arrays, out):
    total = sum(len(a) for _, a in arrays)
    body = bytearray()
    for _, a in arrays:
        body += struct.pack('<%de' % len(a), *a)
    hdr = MAGIC + struct.pack('<II', VERSION, total)
    hdr += b'\0' * (16 - len(hdr))
    with open(out, 'wb') as f:
        f.write(hdr + body)
    return total


if __name__ == '__main__':
    arr = collect(sys.argv[1])
    n = write(arr, sys.argv[2])
    print('params', n)
    off = 0
    for k, a in arr:
        print('%-16s off=%7d n=%6d' % (k, off, len(a)))
        off += len(a)
