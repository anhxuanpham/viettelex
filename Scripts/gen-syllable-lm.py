#!/usr/bin/env python3
"""gen-syllable-lm.py — sinh MÔ HÌNH NGÔN NGỮ ÂM TIẾT TRIGRAM tĩnh (vnlm.bin) cho gõ vuốt, thanh
gợi ý gõ chạm và Thêm dấu: Kneser-Ney nội suy bậc 3, cắt tỉa + lượng tử hoá 1 byte, mmap được.
Chỉ python3 stdlib. (Thay cả vnbigram.bin + Scripts/gen-syllable-bigram.py cũ từ 28/09/2026 —
hàm tách nguồn/âm tiết/tập giữ lại của script đó chuyển nguyên văn vào đây.)

Nguồn + giấy phép + ghi công: docs/DATA-SOURCES.md (Wikipedia/Wikisource/Wikivoyage/
Wikibooks/Wikiquote tiếng Việt — CC BY-SA 4.0; Tatoeba — CC BY 2.0 FR). Dữ liệu thô KHÔNG
commit; tải về thư mục tạm rồi chạy:

  B=https://dumps.wikimedia.org/other/cirrussearch/20251229
  curl -O https://downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2
  for w in viwikisource viwikivoyage viwikibooks viwikiquote; do
    curl -o $w.json.gz $B/$w-20251229-cirrussearch-content.json.gz; done
  # Wikipedia: chỉ 600 MB nén đầu (bài cũ, id thấp — ít bài bot sơ khai)
  curl -r 0-599999999 -o viwiki-part.json.gz $B/viwiki-20251229-cirrussearch-content.json.gz

  python3 Scripts/gen-syllable-lm.py count --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --cache /tmp/lm/ngrams.pkl --test-out /tmp/lm/test.txt --dev-out /tmp/lm/dev.txt \\
      /tmp/bg/*.gz /tmp/bg/*.bz2                                    # ~3 phút, ~4,5 GB RAM
  python3 Scripts/gen-syllable-lm.py build --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --cache /tmp/lm/ngrams.pkl --out iOS/Keyboard/Resources/vnlm.bin
  cp iOS/Keyboard/Resources/vnlm.bin android/app/src/main/assets/
  # fixture đo độ chính xác (câu kiểm thử đã tách âm tiết)
  python3 Scripts/gen-syllable-lm.py chains --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --input /tmp/lm/test.txt --out iOS/KeyboardTests/Fixtures/bigram-heldout.txt

Tách âm tiết: NFC, chữ thường, kiểu dấu CŨ như vnlexicon (hòa, thủy); chỉ giữ âm tiết có
trong vnlexicon. Chuỗi n-gram đứt ở MỌI thứ không phải khoảng trắng giữa hai âm tiết (dấu
câu, số, từ ngoại lai, ký hiệu). Câu có blake2b(câu) % 20 == 0 bị GIỮ LẠI (không đếm) làm tập
kiểm thử, == 1 làm tập dev (chỉnh trọng số) — `--test-out` / `--dev-out` ghi các câu Tatoeba
giữ lại.

Mô hình (đo & chọn trên tập dev, xem docs/DATA-SOURCES.md mục vnlm.bin):
  - Đếm có trọng số nguồn (Tatoeba ×30 — văn hội thoại, xem WEIGHTS).
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
  - uniAdj(c) = q(ln(P1(c)·N / c(c))): cộng vào s2(b, c) ⇒ PMI ln(P2(c|b) / P(c)) theo tần suất
    thật — thanh gợi ý + Thêm dấu dùng (thay vnbigram.bin; khớp PMI cũ ±0.08 nat trên cặp chung).

vnlm.bin (little-endian; mọi mảng đọc tại chỗ):
   0  "VNM1"
   4  version u32 = 2
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
      uniAdj i8[count]              — q(ln(P1(c)·N / c(c))) (version 2)
"""
import argparse, array, bz2, collections, hashlib, importlib.util, json, math, os, pickle, re
import struct, sys, unicodedata, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
HOLDOUT_MOD = 20

D = 0.75
Q = 16
VERSION = 2
BETA, CLIP_LO, CLIP_HI = 0.15, -1.0, 1.0      # = SwipeTyping.lmWeight / lmFloor / lmCap
BR = 0xFFFF
M13 = 0x1FFF

# ---- vnlexicon.bin -------------------------------------------------------------

def load_lexicon(path):
    blob = open(path, "rb").read()
    assert blob[:4] == b"VNL2"
    count, nsec = struct.unpack_from("<II", blob, 8)
    secs = [struct.unpack_from("<II", blob, 16 + i * 8) for i in range(nsec)]
    disp_base = secs[1][0]
    doff_base, _ = secs[4]
    doffs = struct.unpack_from("<%dI" % (count + 1), blob, doff_base)
    words = []
    for i in range(count):
        lo = 0 if i == 0 else doffs[i]
        words.append(blob[disp_base + lo: disp_base + doffs[i + 1]].decode("utf-8"))
    return words, fnv1a(blob)

def fnv1a(data):
    h = 0x811C9DC5
    for b in data:
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h

def _old_style():
    spec = importlib.util.spec_from_file_location("genvnlex", os.path.join(HERE, "gen-vnlexicon.py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m.to_old_style

# ---- nguồn --------------------------------------------------------------------

def gz_lines(path):
    """Đọc gzip theo dòng, chịu được file bị cắt (tải một phần)."""
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    buf = b""
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk: break
            try:
                buf += d.decompress(chunk)
            except zlib.error:
                break
            *lines, buf = buf.split(b"\n")
            yield from lines

def cirrus_texts(path):
    for line in gz_lines(path):
        if not line.startswith(b'{"'): continue
        if line.startswith(b'{"index"'): continue
        try: doc = json.loads(line)
        except ValueError: continue
        t = doc.get("text")
        if t: yield t

def tatoeba_texts(path):
    with bz2.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3: yield parts[2]

def source_of(path):
    b = os.path.basename(path)
    if b.startswith("vie_sentences"): return "tatoeba", tatoeba_texts(path)
    return b.split(".")[0].split("-")[0], cirrus_texts(path)

# Trọng số nguồn: văn hội thoại (Tatoeba) nhỏ nhưng đúng văn phong bàn phím.
# Chọn trên tập dev (Tatoeba giữ lại): ×30 cho top-1 +1.5 điểm so với ×8; ×80 chỉ
# thêm +0.6 mà lệch văn phong Tatoeba (câu dịch) — giữ ×30.
WEIGHTS = {"tatoeba": 30, "viwikisource": 1, "viwikiquote": 2, "viwikivoyage": 1,
           "viwikibooks": 1, "viwiki": 1}

SENT_SPLIT = re.compile(r"(?<=[.!?…])\s+|\n+")
TOKEN = re.compile(r"[^\W\d_]+|\S", re.UNICODE)

def sentences(text):
    for s in SENT_SPLIT.split(text):
        s = s.strip()
        if s: yield s

def held_out(sentence):
    """0 = tập kiểm thử, 1 = tập dev (chỉnh tham số), None = dùng để đếm."""
    h = hashlib.blake2b(sentence.encode("utf-8"), digest_size=4).digest()
    r = int.from_bytes(h, "little") % HOLDOUT_MOD
    return r if r < 2 else None

# ---- đếm ----------------------------------------------------------------------

def id_stream(path, tid, held=(None, None)):
    """Nguồn → mảng id âm tiết, BR ở chỗ đứt chuỗi. Câu giữ lại bị bỏ (Tatoeba: ghi ra
    held[0] = tập kiểm thử / held[1] = tập dev nếu có)."""
    name, texts = source_of(path)
    buf = array.array("H")
    for text in texts:
        text = unicodedata.normalize("NFC", text)
        for s in sentences(text):
            low = s.lower()
            h = held_out(low)
            if h is not None:
                if name == "tatoeba" and held[h]: held[h].write(s + "\n")
                continue
            last_br = True
            for m in TOKEN.finditer(low):
                i = tid(m.group())
                if i < 0:
                    if not last_br: buf.append(BR); last_br = True
                    continue
                buf.append(i); last_br = False
            if not last_br: buf.append(BR)
    return name, buf

def cmd_count(a):
    words, _ = load_lexicon(a.lexicon)
    assert len(words) <= M13, "id phải vừa 13 bit"
    wid = {w: i for i, w in enumerate(words)}
    old = _old_style()
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
    held = tuple(open(f, "w", encoding="utf-8") if f else None for f in (a.test_out, a.dev_out))
    for path in a.inputs:
        name, ids = id_stream(path, tid, held)
        w = WEIGHTS.get(name, 1)
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
    for f in held:
        if f: f.close()
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

def uni_adj(m):
    """q(ln(P1(c)·N / c(c))) — cộng vào s2 ⇒ PMI ln(P2(c|b) / P(c)) theo unigram thật."""
    n = float(sum(m.uni.values()))
    return {c: qz(math.log(m.p1(c) * n / u)) for c, u in m.uni.items() if u > 0}

def serialize(count, lex_hash, g2, bi, g3, tri, adj):
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
    head = b"VNM1" + struct.pack("<7I4I", VERSION, count, lex_hash, Q, len(bl), len(ctx), len(tl), 0, 0, 0, 0)
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
    blob += struct.pack("<%db" % count, *(adj.get(i, 0) for i in range(count)))
    return blob

def cmd_build(a):
    words, lex_hash = load_lexicon(a.lexicon)
    with open(a.cache, "rb") as f: c = pickle.load(f)
    assert c["count"] == len(words), "cache dựng từ lexicon khác"
    m = KN(c)
    g2, bi, g3, tri = build_model(m, a.th2, a.th3)
    blob = serialize(len(words), lex_hash, g2, bi, g3, tri, uni_adj(m))
    open(a.out, "wb").write(blob)
    print(f"{len(bi)} bigram, {len(g3)} ngữ cảnh trigram, {len(tri)} trigram, "
          f"{len(blob)} byte → {a.out}", file=sys.stderr)

def cmd_chains(a):
    """Câu giữ lại → chuỗi âm tiết liên tiếp (mỗi dòng một chuỗi ≥ 2 âm tiết) — fixture
    đo độ chính xác gõ vuốt (tách âm tiết y như lúc đếm, reader khỏi phải tách lại)."""
    words, _ = load_lexicon(a.lexicon)
    wid = set(words)
    old = _old_style()
    out = [f"# bigram-heldout v1 — câu Tatoeba (CC BY 2.0 FR, https://tatoeba.org) GIỮ LẠI khỏi "
           f"dữ liệu dựng vnlm.bin (hash % 20 == 0). Sinh bởi Scripts/gen-syllable-lm.py chains. "
           f"Mỗi dòng: chuỗi âm tiết liên tiếp trong vnlexicon."]
    n = 0
    for line in open(a.input, encoding="utf-8"):
        chain = []
        for m in TOKEN.finditer(unicodedata.normalize("NFC", line.strip()).lower()):
            t = old(m.group())
            if t in wid: chain.append(t); continue
            if len(chain) >= 2: out.append(" ".join(chain))
            chain = []
        if len(chain) >= 2: out.append(" ".join(chain))
        n += 1
        if a.limit and n >= a.limit: break
    open(a.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"{len(out) - 1} chuỗi từ {n} câu → {a.out}", file=sys.stderr)

def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("count")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--cache", required=True)
    p.add_argument("--test-out")
    p.add_argument("--dev-out")
    p.add_argument("inputs", nargs="+")
    p = sp.add_parser("build")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--cache", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--th2", type=float, default=10)
    p.add_argument("--th3", type=float, default=20)
    p = sp.add_parser("chains")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--input", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    {"count": cmd_count, "build": cmd_build, "chains": cmd_chains}[a.cmd](a)

if __name__ == "__main__":
    main()
