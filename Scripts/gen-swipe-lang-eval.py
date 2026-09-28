#!/usr/bin/env python3
"""Sinh tập đánh giá "liên tục ngôn ngữ" cho gõ vuốt (SwipeLangTuneTests / SwipeLangEvalTests).

Ra: iOS/KeyboardTests/Fixtures/swipe-lang-sentences.txt, mỗi dòng
    <tập>\t<loại>\t<câu>
  tập  = dev | test (chỉnh CHỈ trên dev, báo trên test)
  loại = en   : câu tiếng Anh thuần (Tatoeba, CC BY 2.0 FR)
         mix  : câu trộn Việt–Anh; từ tiếng Anh mang hậu tố "/e" (mình đang check/e mail/e)
Câu tiếng Việt thuần lấy thẳng từ bigram-heldout.txt (dev = dòng %12==0, test = %12==6), không
chép lại ở đây.

Nguồn câu trộn:
  1. câu trộn tự soạn (danh sách MIXED dưới đây — văn phong chat/công sở, không lấy từ đâu);
  2. ghép câu: câu Việt giữ lại (bigram-heldout, cùng phần dev/test) + câu Anh, hai chiều;
  3. chèn MỘT từ Anh hay chen (danh sách INSERT) vào giữa câu Việt giữ lại.

  curl -sO https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
  bunzip2 eng_sentences.tsv.bz2
  python3 Scripts/gen-swipe-lang-eval.py eng_sentences.tsv
"""
import hashlib
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "iOS/KeyboardTests/Fixtures/swipe-lang-sentences.txt")
HELDOUT = os.path.join(ROOT, "iOS/KeyboardTests/Fixtures/bigram-heldout.txt")
ENLEX = os.path.join(ROOT, "iOS/Keyboard/Resources/enlexicon.bin")

N_EN = 1200          # câu Anh (dev + test)
N_SPLICE = 240       # câu ghép
N_INSERT = 240       # câu chèn một từ Anh

# Câu trộn tự soạn: từ Anh viết "/e".
MIXED = """
mình đang check/e mail/e
gửi file/e cho anh nhé
em gửi email/e cho sếp rồi
hôm nay có meeting/e không
share/e link/e cho mình với
deadline/e là thứ sáu
anh ấy đang online/e
cho mình xin link/e nhé
update/e app/e chưa
tối nay team/e mình đi ăn
bạn đã book/e vé chưa
mai mình có interview/e
cái project/e này khó quá
em đang làm report/e
sếp bảo review/e lại code/e
mình vừa post/e ảnh lên
cho mình cái password/e wifi/e
chị ơi order/e giúp em
bạn follow/e mình đi
nhớ like/e và share/e nhé
anh gửi lại file/e được không
thứ hai có training/e
mình đang ở office/e
em cần support/e gấp
cái laptop/e này chạy chậm quá
bạn check/e giúp mình cái này
tuần sau mình đi business/e trip/e
hôm qua mình xem show/e rất hay
em mới mua cái phone/e mới
mình không có time/e
anh ơi thanks/e nhiều nhé
sorry/e em đến muộn
okay/e mai gặp nhé
mình thấy nó rất cool/e
bài này hay thật sự luôn
cô ấy là manager/e mới
để mình call/e lại sau
bạn có free/e không
tối nay mình chill/e ở nhà
mình đang busy/e lắm
cái game/e này vui ghê
em đã fix/e cái bug/e rồi
anh test/e lại giúp em
bản build/e mới lỗi rồi
mình cần thêm feedback/e
khách hàng muốn change/e thiết kế
cho em cái deadline/e cụ thể
anh đã approve/e chưa
mình note/e lại rồi
bạn nhớ save/e file/e nhé
cái link/e này die/e rồi
tối qua mình ngủ quên
em về nhà trước nhé
the/e end/e
i/e love/e you/e so/e much/e
what/e do/e you/e think/e anh
anh nói là you/e are/e right/e
she/e said/e không sao đâu
thank/e you/e anh nhiều
mình nghĩ that/e is/e fine/e
nó bảo i/e have/e no/e idea/e
good/e morning/e cả nhà
happy/e birthday/e em nhé
see/e you/e tomorrow/e nhé
let/e me/e know/e nhé anh
mình thích cái style/e này
em đang học english/e
bạn nói tiếng anh giỏi quá
cái này gọi là feature/e mới
em đi shopping/e với bạn
mình vừa đi gym/e về
cuối tuần đi camping/e không
bạn có plan/e gì chưa
tháng sau mình nghỉ phép
anh ấy rất professional/e
mình cần một cái charger/e
đừng quên backup/e dữ liệu
em gửi invoice/e cho khách rồi
mình đang đợi confirm/e
sáng mai họp online/e nhé
cái video/e này viral/e lắm
bạn xem story/e của mình chưa
em inbox/e anh rồi đó
nhớ reply/e mail/e giúp em
mình đang work/e from/e home/e
chị ấy mới được promote/e
cái plan/e này ổn đấy
please/e gửi lại cho em
cần gấp lắm please/e
anh check/e inbox/e đi
đây là version/e mới nhất
mình chưa download/e được
em sẽ update/e sau
"""

# Từ Anh hay chen vào câu Việt (chèn một từ vào câu giữ lại).
INSERT = """check file mail email link meeting deadline update app share online like post team
project report review code order support laptop phone game fix bug test build feedback
note save style plan video story inbox reply version download sorry okay thanks cool free
busy time show interview training office manager password""".split()


def h(s):
    return int(hashlib.sha1(s.encode("utf-8")).hexdigest()[:12], 16)


def en_words():
    b = open(ENLEX, "rb").read()
    assert b[:4] == b"VTE1"
    n = struct.unpack("<I", b[4:8])[0]
    p = 8
    out = set()
    for _ in range(n):
        ln, _f = b[p], b[p + 1]
        out.add(b[p + 2:p + 2 + ln].decode("ascii"))
        p += 2 + ln
    return out


def english_sentences(path, lex):
    """Câu Tatoeba tiếng Anh 3–8 từ, chỉ chữ a–z trong enlexicon (+ "i", "a"), không tên riêng."""
    lines = open(path, encoding="utf-8").read().splitlines()
    # từ viết thường ở GIỮA câu ≥ 20 lần ⇒ không phải tên riêng (loại "Tom", "Sami" ở đầu câu)
    mid = {}
    for line in lines:
        for w in line.split("\t")[-1].split(" ")[1:]:
            if w.isalpha() and w.islower():
                mid[w] = mid.get(w, 0) + 1
    seen = set()
    out = []
    for line in lines:
        cols = line.rstrip("\n").split("\t")
        if len(cols) < 3:
            continue
        s = cols[2].strip()
        s = re.sub(r"[.!?]+$", "", s)
        if not re.fullmatch(r"[A-Za-z]+( [A-Za-z]+)*", s):
            continue          # dấu phẩy, nháy (don't), số… ⇒ bỏ (vuốt không ra)
        ws = s.split(" ")
        if not 3 <= len(ws) <= 8:
            continue
        # chữ hoa chỉ ở đầu câu hoặc "I" ⇒ loại tên riêng (Tom, Mary…)
        if any(w[0].isupper() and w != "I" for w in ws[1:]):
            continue
        low = [w.lower() for w in ws]
        if low[0] not in ("i", "a") and mid.get(low[0], 0) < 20:
            continue
        if any(w not in lex and w not in ("i", "a") for w in low):
            continue
        k = " ".join(low)
        if k in seen:
            continue
        seen.add(k)
        out.append(k)
    out.sort(key=h)
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    lex = en_words()
    en = english_sentences(sys.argv[1], lex)[:N_EN]
    held = [l.strip() for l in open(HELDOUT, encoding="utf-8") if l.strip() and not l.startswith("#")]
    vi = {"dev": [s for i, s in enumerate(held) if i % 12 == 0],
          "test": [s for i, s in enumerate(held) if i % 12 == 6]}
    en_split = {"dev": [s for s in en if h("d" + s) % 2 == 0], "test": [s for s in en if h("d" + s) % 2 == 1]}
    rows = []
    for part in ("dev", "test"):
        for s in en_split[part]:
            rows.append((part, "en", s))
    mixed = [l.strip() for l in MIXED.strip().splitlines() if l.strip()]
    for i, s in enumerate(mixed):
        rows.append(("dev" if i % 2 == 0 else "test", "mix", s))
    for part in ("dev", "test"):
        vs = [s for s in vi[part] if 2 <= len(s.split()) <= 7]
        es = en_split[part]
        for k in range(N_SPLICE // 2):
            v = vs[(k * 7) % len(vs)].split()
            e = [w + "/e" for w in es[(k * 11 + 3) % len(es)].split()]
            if k % 2 == 0:
                rows.append((part, "mix", " ".join(v + e)))
            else:
                rows.append((part, "mix", " ".join(e + v)))
        for k in range(N_INSERT // 2):
            v = vs[(k * 5 + 1) % len(vs)].split()
            w = INSERT[h(part + str(k)) % len(INSERT)]
            pos = 1 + h("p" + part + str(k)) % len(v)       # sau ít nhất một từ Việt
            rows.append((part, "mix", " ".join(v[:pos] + [w + "/e"] + v[pos:])))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("# swipe-lang-sentences v1 — sinh bởi Scripts/gen-swipe-lang-eval.py. <tập>\\t<loại>\\t<câu>;"
                " loại en = câu Anh Tatoeba (CC BY 2.0 FR, https://tatoeba.org), mix = câu trộn (từ Anh \"/e\").\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
    print(f"{len(rows)} dòng ({sum(r[1] == 'en' for r in rows)} en) → {OUT}")


if __name__ == "__main__":
    main()
