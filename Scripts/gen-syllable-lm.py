#!/usr/bin/env python3
"""gen-syllable-lm.py — sinh MÔ HÌNH NGÔN NGỮ ÂM TIẾT TRIGRAM tĩnh (vnlm.bin) cho gõ vuốt:
Kneser-Ney nội suy bậc 3, cắt tỉa + lượng tử hoá 1 byte, mmap được. Chỉ python3 stdlib.

Cùng nguồn, cùng cách tách âm tiết, cùng tập giữ lại (blake2b % 20: 0 = kiểm thử, 1 = dev)
với Scripts/gen-syllable-bigram.py (dùng lại hàm của script đó) — nguồn + giấy phép + ghi
công: docs/DATA-SOURCES.md. Dữ liệu thô KHÔNG commit; tải như docstring
gen-syllable-bigram.py rồi:

  python3 Scripts/gen-syllable-lm.py count --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --cache /tmp/lm/ngrams.pkl /tmp/bg/*.gz /tmp/bg/*.bz2        # ~3 phút, ~4,5 GB RAM
  python3 Scripts/gen-syllable-lm.py build --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --cache /tmp/lm/ngrams.pkl --out iOS/Keyboard/Resources/vnlm.bin
  cp iOS/Keyboard/Resources/vnlm.bin android/app/src/main/assets/

Mô hình (đo & chọn trên tập dev, xem docs/DATA-SOURCES.md mục vnlm.bin):
  - Đếm có trọng số nguồn (Tatoeba ×30 như bigram). Chuỗi đứt ở mọi thứ không phải
    khoảng trắng giữa hai âm tiết của vnlexicon.
  - KN nội suy, chiết khấu tuyệt đối D = 0.75 mọi bậc:
      P1(c)     = (N1+(•c) + 0.5) / (N1+(••) + 0.5·V)                 (continuation)
      P2(c|b)   = max(c(bc) − D, 0)/c(b) + D·N1+(b•)/c(b) · P1(c)
      P3(c|a,b) = max(c(abc) − D, 0)/c(ab) + D·N1+(ab•)/c(ab) · P2(c|b)
    (c(·) có trọng số, N1+ đếm thô; trigram chỉ giữ khi đếm thô ≥ 2.)
  - Giá trị lưu s = ln(P(c|ngữ cảnh) / P1(c)) (nat) — "c hay theo sau ngữ cảnh hơn bình
    thường bao nhiêu"; âm = ít gặp hơn. Không cần lưu P1: decoder đã có tần suất riêng.
  - Thiếu mục: bigram → s = ln γ2(b), γ2(b) = D·N1+(b•)/c(b); dòng trigram có mà thiếu c
    → s = ln γ3(ab) + s2(b, c); không có dòng trigram (ab) → s2(b, c).
  - Cắt tỉa kiểu "weighted difference" (Seymore & Rosenfeld 1996) trên ĐIỂM decoder thật
    sự dùng: bỏ mục khi c_trọng_số · |clip(β·s) − clip(β·s_lùi)| < ngưỡng (β = 0.15,
    clip [−1, 1] — hằng số của SwipeTyping). Ngưỡng bigram 10, trigram 20.
  - Lượng tử i8 = round(s·16), bão hoà ±127 (±7.9 nat — vượt vùng clip của decoder).

vnlm.bin (little-endian; mọi mảng đọc tại chỗ):
   0  "VNM1"
   4  version u32 = 1
   8  count u32          — số âm tiết vnlexicon (id theo THỨ TỰ vnlexicon.bin)
  12  lexHash u32        — FNV-1a 32 của vnlexicon.bin (reader từ chối nếu lệch)
  16  qPerNat u32 = 16
  20  biEntries u32
  24  triContexts u32
  28  triEntries u32
  32  reserved u32 ×4
  48  gamma2 i8[count]              — q(ln γ2(b)); pad 0 tới bội 4
      biOff u32[count+1]            — mục bigram của b: [biOff[b], biOff[b+1])
      biNext u16[biEntries]         — id c, TĂNG DẦN trong mỗi dải
      biScore i8[biEntries]         — pad 0 tới bội 4
      ctxKey u32[triContexts]       — a<<16 | b, TĂNG DẦN (binary search)
      ctxOff u32[triContexts+1]     — mục trigram của ngữ cảnh k: [ctxOff[k], ctxOff[k+1])
      ctxGamma i8[triContexts]      — q(ln γ3(ab))
      triNext u16[triEntries]       — id c, TĂNG DẦN trong mỗi dải
      triScore i8[triEntries]
"""
import argparse, array, collections, importlib.util, math, os, pickle, struct, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("genbigram", os.path.join(HERE, "gen-syllable-bigram.py"))
G = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(G)

D = 0.75
Q = 16
BETA, CLIP_LO, CLIP_HI = 0.15, -1.0, 1.0      # = SwipeTyping.lmWeight / lmFloor / lmCap
BR = 0xFFFF
M13 = 0x1FFF

# ---- đếm ----------------------------------------------------------------------

def id_stream(path, tid):
    """Nguồn → mảng id âm tiết, BR ở chỗ đứt chuỗi (bỏ câu giữ lại như bigram)."""
    name, texts = G.source_of(path)
    buf = array.array("H")
    for text in texts:
        text = unicodedata.normalize("NFC", text)
        for s in G.sentences(text):
            low = s.lower()
            if G.held_out(low) is not None: continue
            last_br = True
            for m in G.TOKEN.finditer(low):
                i = tid(m.group())
                if i < 0:
                    if not last_br: buf.append(BR); last_br = True
                    continue
                buf.append(i); last_br = False
            if not last_br: buf.append(BR)
    return name, buf

def cmd_count(a):
    words, _ = G.load_lexicon(a.lexicon)
    assert len(words) <= M13, "id phải vừa 13 bit"
    wid = {w: i for i, w in enumerate(words)}
    old = G._old_style()
    cache = {}
    def tid(t):
        r = cache.get(t)
        if r is None:
            r = wid.get(old(t), -1)
            if len(cache) < 2_000_000: cache[t] = r
        return r
    uni = collections.Counter(); bi = collections.Counter(); tri = collections.Counter()
    bi_raw = collections.Counter(); tri_raw = collections.Counter()
    CH = 4_000_000
    for path in a.inputs:
        name, ids = id_stream(path, tid)
        w = G.WEIGHTS.get(name, 1)
        L = len(ids)
        for s in range(0, L, CH):
            seg = ids[s: min(L, s + CH + 2)]
            e = min(CH, len(seg))
            u = collections.Counter(x for x in seg[:e] if x != BR)
            b = collections.Counter(x << 13 | y for x, y in zip(seg[:e], seg[1:e + 1])
                                    if x != BR and y != BR)
            t = collections.Counter(x << 26 | y << 13 | z for x, y, z in
                                    zip(seg[:e], seg[1:e + 1], seg[2:e + 2])
                                    if x != BR and y != BR and z != BR)
            bi_raw.update(b); tri_raw.update(t)
            if w != 1:
                for c in (u, b, t):
                    for k in c: c[k] *= w
            uni.update(u); bi.update(b); tri.update(t)
        print(f"{name}: {L} token (×{w}), {len(bi)} bigram, {len(tri)} trigram khác nhau",
              file=sys.stderr, flush=True)
    cont1 = collections.Counter(k & M13 for k in bi_raw)
    fol1 = collections.Counter(k >> 13 for k in bi_raw)
    fol2 = collections.Counter(k >> 13 for k in tri_raw)
    keep = {k for k, r in tri_raw.items() if r >= 2}
    with open(a.cache, "wb") as f:
        pickle.dump({"count": len(words), "uni": dict(uni), "bi": dict(bi), "bi_raw": dict(bi_raw),
                     "tri": {k: tri[k] for k in keep}, "tri_raw": {k: tri_raw[k] for k in keep},
                     "cont1": dict(cont1), "fol1": dict(fol1), "fol2": dict(fol2)}, f, protocol=4)

# ---- mô hình ------------------------------------------------------------------

class KN:
    def __init__(self, c):
        self.__dict__.update(c)
        self.nbt = float(len(self.bi_raw))

    def p1(self, c):
        return (self.cont1.get(c, 0) + 0.5) / (self.nbt + 0.5 * self.count)

    def p2(self, b, c):
        cb = self.uni.get(b, 0); f = self.fol1.get(b, 0)
        if cb == 0 or f == 0: return self.p1(c)
        return max(self.bi.get(b << 13 | c, 0.0) - D, 0) / cb + D * f / cb * self.p1(c)

    def p3(self, a, b, c):
        ab = a << 13 | b
        cab = self.bi.get(ab, 0.0); f = self.fol2.get(ab, 0)
        if cab == 0 or f == 0: return self.p2(b, c)
        return max(self.tri.get(ab << 13 | c, 0.0) - D, 0) / cab + D * f / cab * self.p2(b, c)

def qz(s): return max(-127, min(127, round(s * Q)))
def clip(s): return max(CLIP_LO, min(CLIP_HI, BETA * s))

def build_model(m, th2, th3, mc2=2):
    g2 = {}
    for b, f in m.fol1.items():
        cb = m.uni.get(b, 0)
        if cb > 0 and f > 0: g2[b] = qz(math.log(D * f / cb))
    bi = {}
    for k, r in m.bi_raw.items():
        if r < mc2: continue
        b, c = k >> 13, k & M13
        if b not in g2: continue
        q = qz(math.log(m.p2(b, c) / m.p1(c)))
        if m.bi[k] * abs(clip(q / Q) - clip(g2[b] / Q)) >= th2: bi[k] = q
    def s2(b, c):
        q = bi.get(b << 13 | c)
        return (q if q is not None else g2.get(b, 0)) / Q
    tri = {}; g3 = {}
    for k in m.tri_raw:
        ab = k >> 13; a, b, c = ab >> 13, ab & M13, k & M13
        cab = m.bi.get(ab, 0.0); f = m.fol2.get(ab, 0)
        if cab <= 0 or f == 0: continue
        g = g3.get(ab)
        if g is None: g = g3[ab] = qz(math.log(D * f / cab))
        q = qz(math.log(m.p3(a, b, c) / m.p1(c)))
        if m.tri[k] * abs(clip(q / Q) - clip(g / Q + s2(b, c))) >= th3: tri[k] = q
    rows = {k >> 13 for k in tri}
    return g2, bi, {k: v for k, v in g3.items() if k in rows}, tri

def pad4(b): return b + b"\0" * (-len(b) % 4)

def serialize(count, lex_hash, g2, bi, g3, tri):
    bl = sorted(bi.items())
    off = [0] * (count + 1)
    for k, _ in bl: off[(k >> 13) + 1] += 1
    for i in range(count): off[i + 1] += off[i]
    ctx = sorted(g3)
    tl = sorted(tri.items())
    coff = [0]; j = 0
    for ab in ctx:
        while j < len(tl) and tl[j][0] >> 13 == ab: j += 1
        coff.append(j)
    assert coff[-1] == len(tl)
    head = b"VNM1" + struct.pack("<7I4I", 1, count, lex_hash, Q, len(bl), len(ctx), len(tl), 0, 0, 0, 0)
    blob = head
    blob += pad4(struct.pack("<%db" % count, *(g2.get(i, 0) for i in range(count))))
    blob += struct.pack("<%dI" % (count + 1), *off)
    blob += struct.pack("<%dH" % len(bl), *(k & M13 for k, _ in bl))
    blob += pad4(struct.pack("<%db" % len(bl), *(q for _, q in bl)))
    blob += struct.pack("<%dI" % len(ctx), *((ab >> 13) << 16 | (ab & M13) for ab in ctx))
    blob += struct.pack("<%dI" % len(coff), *coff)
    blob += struct.pack("<%db" % len(ctx), *(g3[ab] for ab in ctx))
    blob += struct.pack("<%dH" % len(tl), *(k & M13 for k, _ in tl))
    blob += struct.pack("<%db" % len(tl), *(q for _, q in tl))
    return blob

def cmd_build(a):
    words, lex_hash = G.load_lexicon(a.lexicon)
    with open(a.cache, "rb") as f: c = pickle.load(f)
    assert c["count"] == len(words), "cache dựng từ lexicon khác"
    g2, bi, g3, tri = build_model(KN(c), a.th2, a.th3)
    blob = serialize(len(words), lex_hash, g2, bi, g3, tri)
    open(a.out, "wb").write(blob)
    print(f"{len(bi)} bigram, {len(g3)} ngữ cảnh trigram, {len(tri)} trigram, "
          f"{len(blob)} byte → {a.out}", file=sys.stderr)

def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("count")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--cache", required=True)
    p.add_argument("inputs", nargs="+")
    p = sp.add_parser("build")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--cache", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--th2", type=float, default=10)
    p.add_argument("--th3", type=float, default=20)
    a = ap.parse_args()
    {"count": cmd_count, "build": cmd_build}[a.cmd](a)

if __name__ == "__main__":
    main()
