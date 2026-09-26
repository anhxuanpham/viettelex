#!/usr/bin/env python3
"""gen-syllable-bigram.py — sinh bảng BIGRAM ÂM TIẾT tiếng Việt tĩnh (vnbigram.bin)
cho gõ vuốt: chọn dấu + phân biệt cặp vuốt gần trùng (cho/co, nay/ngay…) theo
âm tiết đứng trước. Chỉ python3 stdlib.

Nguồn + giấy phép + ghi công: docs/DATA-SOURCES.md (Wikipedia/Wikisource/
Wikivoyage/Wikibooks/Wikiquote tiếng Việt — CC BY-SA 4.0; Tatoeba — CC BY 2.0 FR).
Dữ liệu thô KHÔNG commit; tải về thư mục tạm rồi chạy:

  B=https://dumps.wikimedia.org/other/cirrussearch/20251229
  curl -O https://downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2
  for w in viwikisource viwikivoyage viwikibooks viwikiquote; do
    curl -o $w.json.gz $B/$w-20251229-cirrussearch-content.json.gz; done
  # Wikipedia: chỉ 600 MB nén đầu (bài cũ, id thấp — ít bài bot sơ khai)
  curl -r 0-599999999 -o viwiki-part.json.gz $B/viwiki-20251229-cirrussearch-content.json.gz

  python3 Scripts/gen-syllable-bigram.py count --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --cache /tmp/bg/counts.pkl --test-out /tmp/bg/test.txt --dev-out /tmp/bg/dev.txt \\
      /tmp/bg/*.gz /tmp/bg/*.bz2
  python3 Scripts/gen-syllable-bigram.py build --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --cache /tmp/bg/counts.pkl --out iOS/Keyboard/Resources/vnbigram.bin
  cp iOS/Keyboard/Resources/vnbigram.bin android/app/src/main/assets/
  # fixture đo độ chính xác (câu kiểm thử đã tách âm tiết)
  python3 Scripts/gen-syllable-bigram.py chains --lexicon iOS/Keyboard/Resources/vnlexicon.bin \\
      --input /tmp/bg/test.txt --out iOS/KeyboardTests/Fixtures/bigram-heldout.txt

Tách âm tiết: NFC, chữ thường, kiểu dấu CŨ như vnlexicon (hòa, thủy); chỉ giữ âm
tiết có trong vnlexicon. Chuỗi bigram đứt ở MỌI thứ không phải khoảng trắng giữa hai
âm tiết (dấu câu, số, từ ngoại lai, ký hiệu). Câu có blake2b(câu) % 20 == 0 bị GIỮ LẠI
(không đếm) làm tập kiểm thử, == 1 làm tập dev (chỉnh trọng số) — `--test-out` /
`--dev-out` ghi các câu Tatoeba giữ lại.

Điểm của cặp (a, b): PMI chiết khấu tuyệt đối, đơn vị nat:
    pmi = ln( (c(a,b) − D) · N / (c(a)·c(b)) ),  D = 0.5
giữ khi c(a,b) thô ≥ 3 và pmi ≥ 0.25 (PMI âm chỉ +0.4 điểm top-1 mà gấp 2.3 lần
kích thước — bỏ); lượng tử q = round(pmi·16) (u8, trần
255 ≈ 15.9 nat). Thiếu cặp = không biết (0). Cắt thêm theo |pmi|·c nếu vượt ngân sách.

vnbigram.bin (little-endian, mmap được):
   0  "VNB1"
   4  version u32 = 1
   8  count u32        — số âm tiết của vnlexicon (id theo THỨ TỰ vnlexicon.bin)
  12  entries u32      — số cặp
  16  lexHash u32      — FNV-1a 32 của vnlexicon.bin (reader từ chối nếu lệch)
  20  qPerNat u32 = 16 — q / qPerNat = pmi (nat)
  24  reserved u32 ×2
  32  offsets u32[count+1]   — cặp của âm tiết trước a: [offsets[a], offsets[a+1])
      next u16[entries]      — id âm tiết sau, TĂNG DẦN trong mỗi dải (binary search)
      score u8[entries]      — q
"""
import argparse, bz2, collections, gzip, hashlib, json, math, os, pickle, re, struct, sys
import unicodedata, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
HOLDOUT_MOD = 20
D = 0.5
Q_PER_NAT = 16

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
    import importlib.util
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

def cmd_count(a):
    words, _ = load_lexicon(a.lexicon)
    wid = {w: i for i, w in enumerate(words)}
    old = _old_style()
    tok_cache = {}
    def tid(t):
        r = tok_cache.get(t)
        if r is None:
            r = wid.get(old(t), -1)
            if len(tok_cache) < 2_000_000: tok_cache[t] = r
        return r
    uni = collections.Counter()
    bi = collections.Counter()
    raw_bi = collections.Counter()
    test = open(a.test_out, "w", encoding="utf-8") if a.test_out else None
    dev = open(a.dev_out, "w", encoding="utf-8") if a.dev_out else None
    stats = {}
    for path in a.inputs:
        name, texts = source_of(path)
        w = dict(WEIGHTS, **dict((k, int(v)) for k, v in (x.split("=") for x in a.weight))).get(name, 1)
        nsyl = nsent = nheld = 0
        for text in texts:
            text = unicodedata.normalize("NFC", text)
            for s in sentences(text):
                low = s.lower()
                h = held_out(low)
                if h is not None:
                    nheld += 1
                    f = test if h == 0 else dev
                    if f and name == "tatoeba": f.write(s + "\n")
                    continue
                nsent += 1
                prev = -1
                for m in TOKEN.finditer(low):
                    i = tid(m.group())
                    if i < 0: prev = -1; continue
                    uni[i] += w; nsyl += 1
                    if prev >= 0:
                        k = prev << 16 | i
                        bi[k] += w; raw_bi[k] += 1
                    prev = i
            if a.max_syllables and nsyl >= a.max_syllables: break
        stats[name] = (nsent, nheld, nsyl)
        print(f"{name}: {nsent} câu, giữ lại {nheld}, {nsyl} âm tiết (×{w})", file=sys.stderr)
    if test: test.close()
    if dev: dev.close()
    with open(a.cache, "wb") as f:
        pickle.dump({"uni": dict(uni), "bi": dict(bi), "raw": dict(raw_bi), "stats": stats,
                     "count": len(words)}, f, protocol=4)

def score_pairs(c, min_count, min_pmi):
    uni, bi, raw = c["uni"], c["bi"], c["raw"]
    n = float(sum(uni.values()))
    out = []
    for k, v in bi.items():
        if raw[k] < min_count: continue
        a, b = k >> 16, k & 0xFFFF
        p = math.log((v - D * v / raw[k]) * n / (uni[a] * uni[b]))
        if p >= min_pmi:
            out.append((a, b, p, v))
    return out

def cmd_build(a):
    words, lex_hash = load_lexicon(a.lexicon)
    with open(a.cache, "rb") as f: c = pickle.load(f)
    assert c["count"] == len(words), "cache dựng từ lexicon khác"
    pairs = score_pairs(c, a.min_count, a.min_pmi)
    if len(pairs) > a.max_entries:
        # giữ cặp có "khối lượng bằng chứng" lớn: pmi · ln(1+c)
        pairs.sort(key=lambda t: -t[2] * math.log1p(t[3]))
        pairs = pairs[:a.max_entries]
    pairs.sort()
    count = len(words)
    offsets = [0] * (count + 1)
    for p in pairs: offsets[p[0] + 1] += 1
    for i in range(count): offsets[i + 1] += offsets[i]
    nxt = struct.pack("<%dH" % len(pairs), *(p[1] for p in pairs))
    sc = bytes(min(255, max(1, round(p[2] * Q_PER_NAT))) for p in pairs)
    head = b"VNB1" + struct.pack("<7I", 1, count, len(pairs), lex_hash, Q_PER_NAT, 0, 0)
    blob = head + struct.pack("<%dI" % (count + 1), *offsets) + nxt + sc
    open(a.out, "wb").write(blob)
    print(f"{len(pairs)} cặp, {len(blob)} byte → {a.out}", file=sys.stderr)

def cmd_chains(a):
    """Câu giữ lại → chuỗi âm tiết liên tiếp (mỗi dòng một chuỗi ≥ 2 âm tiết) — fixture
    đo độ chính xác gõ vuốt (tách âm tiết y như lúc đếm, reader khỏi phải tách lại)."""
    words, _ = load_lexicon(a.lexicon)
    wid = set(words)
    old = _old_style()
    out = [f"# bigram-heldout v1 — câu Tatoeba (CC BY 2.0 FR, https://tatoeba.org) GIỮ LẠI khỏi "
           f"dữ liệu dựng vnbigram.bin (hash % 20 == 0). Sinh bởi Scripts/gen-syllable-bigram.py chains. "
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
    p.add_argument("--max-syllables", type=int, default=0)
    p.add_argument("--weight", action="append", default=[], help="nguồn=trọng số, vd tatoeba=8")
    p.add_argument("inputs", nargs="+")
    p = sp.add_parser("build")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--cache", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--min-count", type=int, default=3)
    p.add_argument("--min-pmi", type=float, default=0.25)
    p.add_argument("--max-entries", type=int, default=450_000)
    p = sp.add_parser("chains")
    p.add_argument("--lexicon", required=True)
    p.add_argument("--input", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    {"count": cmd_count, "build": cmd_build, "chains": cmd_chains}[a.cmd](a)

if __name__ == "__main__":
    main()
