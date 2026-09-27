"""Kiểm kiến trúc tự viết (mine.py) khớp CHÍNH đồ thị gốc (.pte, chạy bằng interp.py) — python stdlib.

python3 verify.py model_fp32.pte [futoswipe.bin]
  • weights fp32 lấy thẳng từ .pte → mine.forward vs interp.run: sai số ~1e-5 (khớp kiến trúc);
  • có futoswipe.bin: thêm sai số do fp16 (đã phân phối).
"""
import sys
import convert
import gen_fixture as G
import interp
import mine
import pte

m = pte.load(sys.argv[1])
cen = G.qwerty_keys()
x0, wd, y0, ht = G.norm_frame(cen, 40.0)
keys = []
for ch in sorted(cen):
    keys += [(cen[ch][0] - x0) / wd, (cen[ch][1] - y0) / ht]
W32 = {k: a for k, a in convert.collect(sys.argv[1])}
W16 = mine.load(sys.argv[2]) if len(sys.argv) > 2 else None
for word in ['computer', 'nguoi', 'thuong']:
    raw = G.minjerk_path(word, cen)
    f = G.resample([G.clip((x - x0) / wd) for x, _, _ in raw], [G.clip((y - y0) / ht) for _, y, _ in raw],
                   [t for _, _, t in raw])
    le, _, _ = interp.run(m, f, keys + [0.0] * (128 - len(keys)), [True] * 26 + [False] * 38)
    ref = []
    for t in range(32):
        ref += le.data[t * 65:t * 65 + 26] + [le.data[t * 65 + 64]]
    out, _, _ = mine.forward(W32, f, keys)
    line = '%-8s fp32 max|Δ|=%.2e greedy(pte)=%s' % (word, max(abs(a - b) for a, b in zip(out, ref)),
                                                  G.E.greedy(ref, 27))
    if W16:
        o16, _, _ = mine.forward(W16, f, keys)
        line += ' | fp16 max|Δ|=%.3f greedy(fp16)=%s' % (max(abs(a - b) for a, b in zip(o16, ref)), G.E.greedy(o16, 27))
    print(line)
