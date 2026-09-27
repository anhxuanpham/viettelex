# Nguồn dữ liệu & giấy phép

Mã nguồn VietTelex theo [MIT](../LICENSE). Một số **file dữ liệu** đóng gói trong app có
nguồn và giấy phép riêng, ghi dưới đây.

## vnbigram.bin — bigram âm tiết cho gõ vuốt + thanh gợi ý

`iOS/Keyboard/Resources/vnbigram.bin` = `android/app/src/main/assets/vnbigram.bin`
(~1,2 MB, 400.807 cặp). Sinh bởi `Scripts/gen-syllable-bigram.py`. Chỉ chứa **số liệu
thống kê**: với mỗi cặp âm tiết liền nhau (a, b) là một byte PMI đã lượng tử hoá. Không
chứa câu hay đoạn văn nào của nguồn.

### Nguồn

| Nguồn | Bản dùng | Giấy phép | Trọng số | Âm tiết đếm |
|---|---|---|---|---|
| [Wikipedia tiếng Việt](https://vi.wikipedia.org) | CirrusSearch dump `viwiki-20251229-cirrussearch-content.json.gz`, 600 MB nén đầu | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | ×1 | 57,5 tr |
| [Wikisource tiếng Việt](https://vi.wikisource.org) | `viwikisource-20251229-cirrussearch-content` | CC BY-SA 4.0 (nhiều tác phẩm là phạm vi công cộng) | ×1 | 33,0 tr |
| [Wikibooks](https://vi.wikibooks.org), [Wikivoyage](https://vi.wikivoyage.org), [Wikiquote](https://vi.wikiquote.org) tiếng Việt | `…-20251229-cirrussearch-content` | CC BY-SA 4.0 | ×1 / ×1 / ×2 | 2,6 / 1,3 / 0,6 tr |
| [Tatoeba](https://tatoeba.org) (câu tiếng Việt) | `downloads.tatoeba.org/exports/per_language/vie/vie_sentences.tsv.bz2` (09/2026) | [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/) | ×30 | 0,25 tr |

Dump Wikimedia lấy tại https://dumps.wikimedia.org/other/cirrussearch/20251229/ (trường
`text` đã là văn bản thuần). Tatoeba nhỏ nhưng là câu hội thoại, gần văn phong bàn phím
nhất ⇒ trọng số cao (chọn trên tập dev, xem dưới).

### Giấy phép của vnbigram.bin

Số đếm n-gram là dữ liệu thống kê, nhưng để an toàn ta **coi vnbigram.bin là tác phẩm
phái sinh** của các nguồn trên và phát hành nó theo **CC BY-SA 4.0** (Tatoeba CC BY 2.0 FR
cho phép gộp vào tác phẩm CC BY-SA khi ghi công). Hệ quả:

- Dùng thương mại được (cả CC BY-SA lẫn CC BY đều cho phép).
- ShareAlike chỉ áp lên **file dữ liệu** (và bản sửa của nó), không lên mã nguồn app đọc
  nó — mã vẫn MIT.
- Phải ghi công khi phân phối (app + repo). Ghi công đặt ở: file này, mục "Giới thiệu"
  trong app iOS/Android (dòng "Dữ liệu gõ vuốt…", mở trang này), header fixture kiểm thử.

**Thông báo ghi công** (dùng nguyên văn khi phân phối lại vnbigram.bin):

> vnbigram.bin chứa số liệu thống kê bigram âm tiết suy ra từ nội dung Wikipedia,
> Wikisource, Wikibooks, Wikivoyage và Wikiquote tiếng Việt (© các tác giả Wikimedia,
> CC BY-SA 4.0) và từ câu tiếng Việt của Tatoeba (© các thành viên Tatoeba, CC BY 2.0 FR).
> Đã biến đổi: tách âm tiết, đếm cặp liền nhau, chuyển thành PMI lượng tử hoá 1 byte.
> vnbigram.bin phát hành theo CC BY-SA 4.0.

### Nguồn KHÔNG dùng (và lý do)

- **OpenSubtitles thô / OPUS OpenSubtitles**: phụ đề thuộc bản quyền phim + người dịch;
  điều khoản của opensubtitles.org/OPUS không cấp rõ quyền phân phối số liệu phái sinh
  cho app thương mại.
- **Báo điện tử (VnExpress, Tuổi Trẻ…), corpus VLSP / corpus tin tức cào web**: bản
  quyền thuộc toà soạn; phần lớn chỉ cho phép dùng nghiên cứu.
- **Common Crawl / OSCAR / CC-100**: bản quyền từng trang không xác định (bộ dữ liệu chỉ
  cấp phép phần đóng gói), không đủ rõ cho repo công khai + app thương mại.

### Tái tạo

Lệnh đầy đủ ở docstring `Scripts/gen-syllable-bigram.py` (tải dump về thư mục tạm →
`count` → `build` → copy sang assets Android). Dữ liệu thô **không** commit. Định dạng
file ở cùng docstring và `iOS/Keyboard/SyllableBigram.swift`.

- Tách âm tiết: NFC, chữ thường, kiểu dấu cũ như vnlexicon (hòa, thủy); chỉ giữ âm
  tiết có trong vnlexicon; chuỗi đứt ở dấu câu/số/từ lạ.
- Điểm: PMI chiết khấu `ln((c(a,b) − 0.5)·N / (c(a)·c(b)))`, giữ khi đếm thô ≥ 3 và
  PMI ≥ 0.25, lượng tử `round(pmi·16)`.
- Câu có `blake2b(câu) % 20 == 0` là **tập kiểm thử**, `== 1` là **tập dev** — cả hai bị
  loại khỏi phép đếm. Trọng số nguồn/hệ số chấm điểm chỉnh trên tập dev.

### Đo (27/09/2026)

Tập kiểm thử: `iOS/KeyboardTests/Fixtures/bigram-heldout.txt` (1.674 câu Tatoeba giữ lại,
12.027 vị trí có âm tiết trước). Đường vuốt giả σ = 0.25 phím; "top-3" = từ chèn + 2
phương án đầu trên thanh gợi ý. Người dùng mới (không dữ liệu cá nhân):

| | top-1 | top-3 |
|---|---|---|
| Trước (tần suất unigram) | 70,4 % | 86,5 % |
| Sau (+ bigram tĩnh, trọng số 0.3/nat, trần 1.2) | **85,6 %** | **94,8 %** |

Test hồi quy: `SyllableBigramTests` (iOS + Android) — ngưỡng top-1 ≥ 84 %, top-3 ≥ 93,5 %,
và các cặp điển hình (không có, cho tôi, hôm nay, ngay lập, môi trường, một nửa…) phải
lên top-1.

## vnlm.bin — mô hình trigram âm tiết cho gõ vuốt

`iOS/Keyboard/Resources/vnlm.bin` = `android/app/src/main/assets/vnlm.bin` (~2,6 MB:
332.396 bigram, 92.541 ngữ cảnh trigram, 259.909 trigram). Sinh bởi
`Scripts/gen-syllable-lm.py` (lệnh + định dạng ở docstring). Gõ vuốt dùng nó thay
vnbigram.bin khi có (vnbigram.bin vẫn giữ cho thanh gợi ý gõ chạm).

- **Nguồn, trọng số, tách âm tiết, tập kiểm thử/dev: y hệt vnbigram.bin** (bảng nguồn ở
  trên; script dùng lại hàm của `gen-syllable-bigram.py`). Chỉ chứa số liệu thống kê
  (điểm log-xác suất lượng tử 1 byte theo cặp/bộ ba âm tiết), không chứa câu nào.
- **Giấy phép: CC BY-SA 4.0**, cùng lý do và cùng hệ quả như vnbigram.bin (mã đọc nó vẫn
  MIT). Thông báo ghi công (dùng nguyên văn khi phân phối lại vnlm.bin):

> vnlm.bin chứa số liệu thống kê n-gram âm tiết suy ra từ nội dung Wikipedia,
> Wikisource, Wikibooks, Wikivoyage và Wikiquote tiếng Việt (© các tác giả Wikimedia,
> CC BY-SA 4.0) và từ câu tiếng Việt của Tatoeba (© các thành viên Tatoeba, CC BY 2.0 FR).
> Đã biến đổi: tách âm tiết, đếm n-gram, làm trơn Kneser-Ney, cắt tỉa, lượng tử hoá
> 1 byte. vnlm.bin phát hành theo CC BY-SA 4.0.

### Mô hình

Kneser-Ney nội suy bậc 3 (D = 0.75), lưu s = ln(P(c | 2 âm tiết trước) / P₁(c)) — có cả
điểm ÂM ("hiếm sau ngữ cảnh này"), điều vnbigram.bin (chỉ PMI dương) không có. Cắt tỉa
"weighted difference" (Seymore & Rosenfeld 1996) trên chính điểm decoder dùng (β·s kẹp
[−1, 1]), ngưỡng bigram 10 / trigram 20 (đếm có trọng số). Decoder: điểm = 0.15·s kẹp
[−1, 1]; khi có trigram, λ tần suất lúc chọn dạng/bung dấu hạ 2.5 → 1.0 (cho cả từ tiếng
Anh, giữ cán cân Việt/Anh).

### Đo (27/09/2026)

Cùng tập kiểm thử với vnbigram.bin (`bigram-heldout.txt`, 12.027 vị trí, đường giả
σ 0.25, người dùng mới). Tham số chọn trên tập dev (11.915 vị trí), rồi đo MỘT lần trên
tập kiểm thử:

| Mô hình ngữ cảnh | Kích thước | top-1 | top-3 |
|---|---|---|---|
| Không (unigram) | — | 70,4 % | 86,5 % |
| Bigram PMI (vnbigram.bin) | 1,2 MB | 85,6 % | 94,8 % |
| Bigram PMI chỉnh lại λ/trần (dev tốt nhất) | 1,2 MB | ≈ +0,1 điểm trên dev | — |
| Trigram PMI lùi về bigram (không cắt tỉa) | — | 88,1 % | 95,7 % |
| KN bigram (không cắt tỉa) | — | 87,9 % | 96,0 % |
| KN trigram (không cắt tỉa, float) | ~ 31 MB | 90,1 % | 96,5 % |
| KN 4-gram (không cắt tỉa) | — | 90,0 % | 96,5 % |
| **KN trigram cắt tỉa + lượng tử (vnlm.bin)** | **2,6 MB** | **89,2 %** | **96,0 %** |

Bảng trên đo với decoder giai đoạn 2. Sau khi decoder có tầng 2 (σ thích nghi, độ dài,
chấm lại top-16 — commit 7cf48ae): bigram 86,1 % / 95,1 % → **trigram 89,4 % / 96,2 %**
(chỉnh lại β/λ trên dev chỉ +0,1 điểm ⇒ giữ tham số).

4-gram không hơn trigram (dữ liệu hội thoại quá ít). Độ trễ: JVM 0,2 ms/vuốt (decode +
LM), simulator Debug 1,91 vs 1,85 ms/vuốt (bigram) — LM gần như không tốn thêm. Test hồi
quy: `SyllableLMTests` (iOS + Android) — top-1 ≥ 87,7 %, top-3 ≥ 95 %, hơn bigram ≥ 2,5
điểm, bật tiếng Anh không tụt quá 1 điểm, câu trộn Việt–Anh không kém bigram.

## enlexicon.bin — từ điển tiếng Anh cho gõ vuốt (giai đoạn 3)

- File: `iOS/Keyboard/Resources/enlexicon.bin`, `android/app/src/main/assets/enlexicon.bin`
  (y hệt nhau, ~180 KB, 20.000 từ chữ thường a–z + tần suất 1 byte).
- Sinh bởi: `Scripts/gen-enlexicon.py` (python3 stdlib).
  ```
  python3 Scripts/gen-enlexicon.py --download <thư_mục_tạm>
  python3 Scripts/gen-enlexicon.py <thư_mục_tạm>
  ```
- Dùng cho: gõ vuốt giai đoạn 3 (vuốt ra từ tiếng Anh xen trong câu Việt), công tắc
  "Vuốt từ tiếng Anh".

### Nguồn

1. **Google Books Ngram Corpus** (phiên bản 20200217, sách xuất bản 2010–2019), qua danh
   sách đã làm sạch của dự án **google-books-ngram-frequency** (orgtre):
   `ngrams/1grams_english.csv` và `ngrams/1grams_english-fiction.csv`, mỗi file 10.000 từ
   phổ biến nhất kèm số lần xuất hiện. Ghim commit
   `6a72a4d96a2c36717479e9e9bf4e24260b3dbdae`.
   - Giấy phép: **Creative Commons Attribution 3.0 Unported (CC BY 3.0)** — cả bộ dữ liệu
     Google Books Ngram lẫn nội dung repo orgtre. Cho phép dùng thương mại, sửa đổi, phân
     phối lại; điều kiện: ghi công.
   - Ghi công: *"Google Books Ngram Viewer data, © Google, CC BY 3.0
     (https://books.google.com/ngrams); cleaned lists by orgtre/google-books-ngram-frequency
     (https://github.com/orgtre/google-books-ngram-frequency), CC BY 3.0."*
   - Chúng tôi đã sửa đổi: lọc, gộp hai danh sách, quy tần suất về thang 1 byte.
2. **wikipedia-word-frequency** (Ilya Semenov): `results/enwiki-2023-04-13.txt` — tần suất từ
   trong Wikipedia tiếng Anh. Chỉ dùng để BỔ SUNG từ phổ biến không có trong danh sách sách
   (google, facebook, website…) và lấy tần suất cho nguồn 3. Ghim commit
   `798ea9062d6e5aed1fa87deeeda1cd99d5b37903`.
   - Giấy phép: **MIT** (Copyright (c) 2015 Ilya Semenov) —
     https://github.com/IlyaSemenov/wikipedia-word-frequency. Chỉ dùng số đếm (dữ kiện
     thống kê), không chứa văn bản Wikipedia.
3. **Dữ liệu của chính repo**: các bảng `neutralLoanwords` / `words` / `restoreOnly` trong
   `TelexCore/Sources/TelexCore/EnglishContextWords.swift` (từ mượn/tên app hay chen trong
   câu Việt: wifi, login, zalo, shopee…) — luôn có mặt trong từ điển.

### Lọc & chuẩn hoá

- Chỉ giữ `^[a-z]{2,}$`; bỏ từ tục/xúc phạm/tình dục thô (danh sách trong script + các từ
  ASCII của `iOS/Keyboard/SensitiveWords.swift`).
- Phần bổ sung từ Wikipedia: ≥ 3 chữ, không trùng dạng không dấu của âm tiết Việt (loại
  tên riêng tiếng Việt như tran, nguyen), không phải số La Mã; lấy theo hạng tới khi đủ
  20.000 từ tổng.
- Tần suất: tỉ lệ token quy về cùng thang với `vnlexicon.bin` (255·ln(count)/ln(max) trên
  corpus OpenSubtitles tiếng Việt ~26,4 triệu token) để decoder so hai từ điển trên một thang.

## vnlexicon.bin — danh sách âm tiết + tần suất

Có từ trước (không đổi trong đợt bigram); nguồn ghi ở `Scripts/gen-vnlexicon.py`:
danh sách 7.184 âm tiết của hieuthi (gist GitHub) và tần suất từ
[hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (nội dung
CC BY-SA 4.0 theo README dự án; số liệu suy ra từ OpenSubtitles). Cần rà soát giấy phép
gist hieuthi nếu phát hành lại vnlexicon.bin độc lập.

## emoji.bin — bàn phím emoji: bộ emoji, tìm kiếm tiếng Việt, kaomoji

`iOS/Keyboard/Resources/emoji.bin` = `android/app/src/main/assets/emoji.bin` (~258 KB:
1.914 emoji Emoji 17.0, 6.493 khoá tìm, 136 kaomoji). Sinh bởi `Scripts/gen-emoji-data.py`
(python3 stdlib, tự tải nguồn về `~/.cache/viettelex-emoji/`); không sửa tay.

| Nguồn | Bản dùng | Giấy phép | Dùng cho |
|---|---|---|---|
| [Unicode emoji-test.txt](https://unicode.org/Public/17.0.0/emoji/emoji-test.txt) | Emoji 17.0 (2025-08-04) | [Unicode License v3](https://www.unicode.org/license.txt) | danh sách, thứ tự, phiên bản emoji |
| [CLDR annotations vi](https://github.com/unicode-org/cldr/tree/release-48/common/annotations) + annotationsDerived vi | CLDR release-48 | Unicode License v3 | tên / từ khoá tiếng Việt để tìm |
| EmojiSuggest (khoá gợi ý emoji sẵn có, `emojisuggest.bin`) | trong repo | MIT (dự án) | từ khoá tiếng Việt biên soạn |
| Kaomoji / bảng ký hiệu | biên soạn tay trong script | MIT (dự án) | tab ^‿^ |

Unicode License v3 cho phép dùng, sửa, phân phối (kể cả thương mại) miễn kèm thông báo
bản quyền "Copyright © 1991-2025 Unicode, Inc." và điều khoản giấy phép
(https://www.unicode.org/license.txt). emoji.bin là dữ liệu biến đổi (lọc, gộp, fold không
dấu, đóng gói nhị phân) từ các file trên.
