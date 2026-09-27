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

### Sửa lại từ vuốt trước — ngữ cảnh hai phía (27/09/2026, `SwipeRevise`)

Cú vuốt w2 chấm lại ứng viên của từ vuốt liền trước w1 (≤ 8 âm tiết: 3 dạng × 4 dấu) bằng
điểm cũ + 0.1·s(w2 | w0, c) kẹp [−1, 1]; thắng ≥ 0.1 ⇒ thay w1 (đuôi màn hình phải khớp),
rồi chọn lại w2 theo ngữ cảnh trái mới. Chip "↩︎ từ cũ" hoàn tác. Chọn trọng số/lề trên dev
(`SwipeReviseTests.sweep`: 0.1/0.1 ít sửa sai nhất ở gần mức tăng tối đa — 214 sửa đúng /
12 sửa sai), đo MỘT lần trên tập kiểm thử (1/3 chuỗi heldout, vuốt TUẦN TỰ — ngữ cảnh trái
là từ đã giải mã, không phải đáp án, nên thấp hơn bảng trên): JVM 80,9 % → **85,5 %**
(+4,6 điểm, 204 sửa đúng / 12 sửa sai); iOS qua EngineBridge thật 78,0 % → **83,0 %** (+5,0).
Chi phí: vài lần bung dấu + tra LM sau nhấc tay (JVM không đo được khác biệt, ~0,1 ms/vuốt).

**Từ kế gõ bằng phím.** Từ vuốt Việt còn nguyên được dấu cách (iOS: cả phím chữ — dấu cách
treo) chốt ⇒ chờ; ranh giới (dấu cách/dấu câu/xuống dòng) chốt từ gõ NGAY SAU thì chấm lại
từ vuốt với ngữ cảnh phải = từ gõ đã chốt (chắc chắn). Chỉ thay khi đuôi màn hình đúng
"từ vuốt ␠ từ gõ ranh giới" (không dính chữ phía trước), học lại cả hai từ, chip "↩︎ từ cũ"
tới phím kế. Hằng số riêng chỉnh trên dev (`SwipeReviseTests.sweepTyped`, vuốt/gõ xen kẽ):
0.15/0.3 — gần mức tăng tối đa (+8,5 so với đỉnh +8,9 ở 0.15/0.2) mà sửa sai chỉ 7 so với 13;
0.1/0.1 của ca vuốt cho +8,4 / 11 sửa sai. Tập kiểm thử (từ vuốt có từ gõ ngay sau, n = 3 994):
JVM 85,7 % → **94,2 %** (+8,4 điểm, 341 sửa đúng / 15 sửa sai = 3,9 % số lần sửa, 0,38 % số
từ); iOS 85,3 % → **93,4 %** (+8,1; 328 / 15).

### Nét vuốt thật — Luyện vuốt

App (Cài đặt → Gõ vuốt → Luyện vuốt) thu nét vuốt thật trên bàn phím mẫu cùng hình học,
chỉ khi người dùng bật lưu; kho nằm trên máy (không sao lưu, không gửi mạng), xuất JSON
(`viettelex-swipe-traces` v1, xem `SwipePractice.kt`). Đánh giá decoder trên file xuất:
`Scripts/eval-swipe-traces.sh file.json` (top-1/top-3 hiện tại, lúc ghi, tách Việt/Anh).

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

## FUTO Swipe

**futoswipe.bin — encoder FUTO Swipe cho gõ vuốt (THỬ NGHIỆM, mặc định tắt).**

`iOS/Keyboard/Resources/futoswipe.bin` = `android/app/src/main/assets/futoswipe.bin` (1,27 MB,
sha256 `59e41b22…3f089`), kèm `futoswipe-LICENSE.md` (thông báo sửa đổi + nguyên văn giấy phép)
ở cùng thư mục — cả hai được đóng gói vào app. Chỉ đọc khi bật công tắc **Thử nghiệm → Gõ vuốt →
Mô hình neural gõ vuốt** (Keys.SWIPE_FUTO / KeyboardSettings.swipeFuto, mặc định TẮT).
**Powered by FUTO Swipe.**

### Nguồn

| Thành phần | Bản dùng | Giấy phép | Dùng thế nào |
|---|---|---|---|
| [futo-org/futo-swipe](https://huggingface.co/futo-org/futo-swipe) `honorable_sturgeon/model_fp32.pte` (encoder TCN 635K tham số; bài [arXiv 2606.25247](https://arxiv.org/abs/2606.25247)) | revision `18328c30…` (26/06/2026), sha256 `725242ba…1fbaf` | **FUTO Model Weights License 1.0** | weights → fp16 (Derivative Model đã sửa) |
| Decoder `magic_macaw`, context LM `hungry_jellyfish` (cùng repo) | — | cùng giấy phép | KHÔNG dùng (chỉ tiếng Anh/QWERTY) |
| [swipe-library](https://gitlab.futo.org/keyboard/swipe-library) (runtime C++/Kotlin của FUTO) | — | **GPL-3.0** | KHÔNG dùng, không chép code — repo MIT |
| Schema flatbuffer ExecuTorch/XNNPACK (`program.fbs`, `runtime_schema.fbs`) | v1.2.0 | BSD-3-Clause | chỉ để đọc định dạng `.pte` trong Scripts/futo-swipe (không kèm file schema) |

### Giấy phép — kết luận (đọc LICENSE.md 27/09/2026)

Dùng trong app thương mại, đóng gói và phân phối lại (kể cả trong repo công khai) **ĐƯỢC PHÉP**,
với điều kiện:

- Quyền: *"non-exclusive, royalty-free, worldwide, non-sublicensable, non-transferable license to
  use, copy, distribute, make available, and prepare Derivative Models of the Weights for any
  purpose"* ⇒ được commit `futoswipe.bin` vào repo và đóng gói vào app; KHÔNG được cấp lại
  (sublicense) ⇒ giấy phép MIT của VietTelex **không** áp lên file này (ghi rõ trong
  `futoswipe-LICENSE.md`); người nhận nhận quyền trực tiếp từ FUTO theo bản giấy phép kèm theo.
- Ghi công bắt buộc: *"You may use the Weights or any Derivative Model for any purpose, including in
  commercial products and services, provided that you display a visible notice to end users stating
  that the product is powered by "FUTO Swipe" technology … such as within the product's settings,
  about screen … Failure to include this notice is a material breach"* ⇒ dòng "powered by FUTO
  Swipe" ở mục **Giới thiệu** (iOS + Android) và trong mô tả công tắc. Luôn hiện, kể cả khi công
  tắc tắt (model vẫn nằm trong app).
- Tên/nhãn hiệu: *"… solely as required by the attribution notice … You may not use the name …
  to suggest a relationship"* ⇒ công tắc đặt tên trung tính ("Mô hình neural gõ vuốt"), "FUTO
  Swipe" chỉ xuất hiện trong câu ghi công; ghi rõ không liên kết/không được FUTO bảo trợ.
- Derivative Model: *"If you distribute a Derivative Model, you must ensure that anyone who receives
  it also receives a copy of these terms … prominent notice … that the model is derived from FUTO
  Swipe … If you modify the Weights, you must include … a prominent notice stating that you have
  modified them"* ⇒ fp16 + đổi bố cục = đã sửa: `futoswipe-LICENSE.md` (đi kèm file trong repo
  VÀ trong bundle/APK) nói rõ nguồn, sha256, cách sửa, và chứa nguyên văn giấy phép;
  `Scripts/futo-swipe/README.md` cũng ghi.
- *"Inference code, source code, and datasets distributed alongside the Weights are governed by
  their own separate licenses"* ⇒ runtime FUTO (GPL) không được kéo theo; suy luận tự viết.
- Điều khoản bằng sáng chế: kiện FUTO về bằng sáng chế ⇒ mất giấy phép. Công bố nghiên cứu dùng
  weights phải trích "FUTO Swipe Model".

### Kiến trúc (đọc từ đồ thị .pte, Scripts/futo-swipe/interp.py)

Đầu vào 64 điểm (x, y chuẩn hoá theo vùng phím chữ 0–1; resample theo thời gian 60 Hz rồi 64 điểm)
→ 8 kênh: x, y, vx, vy (Savitzky–Golay bậc 1, 7 điểm, đệm lặp biên), ax, ay (SG bậc 2),
√(vx²+vy²+1e-8), độ cong = SG bậc 1 của góc hướng atan2 đã unwrap (kẹp ±2) → conv 8→128 k7 +
hardswish → 5 khối (dwconv k7 dilation 1/2/3/5/8 "same" → pw 128→512 → GLU sigmoid(a)·b → GRN
(√mean_t x² + 1e-6, chia trung bình kênh) → pw 256→128 → SE 128→32→128 + residual) → adapter conv
k2 stride 2 (128→256, 64→32 bước) → λ = sigmoid(lin 256→1) ("ý định"), hệ số DCT 8×8 (lin 256→64)
→ logit phím = Σ hệ số·cos(π·u·x_phím)·cos(π·v·y_phím) → log_softmax trên phím + ln λ, blank =
ln(1−λ), kẹp ≥ −100. Không phụ thuộc layout (tâm phím là đầu vào). Tự viết lại: python
(`mine.py`), Swift (`FutoSwipeModel.swift`, vDSP_mmul), Kotlin (`FutoSwipeModel.kt`, khối 4×2).

Kiểm: `mine.py` (weights fp32) vs thông dịch đồ thị gốc: max |Δlog-prob| ≈ 4e-6; fp16 ≈ 0,04–0,08
(greedy giống hệt). Swift / Kotlin vs python trên fixture chung `futo-swipe-fixture.txt`: max |Δ| ≈
1e-4 (đường thường), 3–5e-3 (đường "computer" có đoạn gần đứng yên — góc hướng nhạy).

### Decoder (VietTelex, `FutoSwipe.swift` / `FutoSwipe.kt`)

CTC Viterbi trên chuỗi phím đã gộp chữ lặp của từ vựng hiện có (1.666 dạng Việt không dấu + 20k từ
Anh khi bật), duyệt theo tiền tố (dùng lại cột CTC tiền tố chung, cắt nhánh bằng cận max_t α).
Mặc định **ensemble**: điểm SHARK2 (hình học + tần suất + ngữ cảnh UserLangModel/trigram + phân xử
Việt/Anh) + β·(âm học − âm học tốt nhất), β = 0,1 (tune trên dev), pool = top-16 SHARK2 ∪ top-4 âm
học. Chế độ FUTO một mình (A·âm học + λ·tần suất + ngữ cảnh) giữ trong code để đo.

### Đo (27/09/2026, JVM + simulator, `FutoSwipeEvalTests.kt` / `FutoSwipeTests.swift`, VT_SLOW_TESTS)

Model học từ vuốt THẬT tiếng Anh; đường vuốt ở đây là GIẢ nên số có thể khác thật. Hai kiểu đường:
**nhịp** = FutoSim (minimum-jerk: chậm dần tới phím như tay người), **đều** = SwipeSim hiện có
(tốc độ không đổi, không có nhịp — FUTO dựa nhiều vào nhịp nên bị thiệt).

Câu giữ lại Tatoeba (bigram-heldout, dev = chuỗi %12==0, test = %12==6, n≈1.040 âm tiết, có LM
trigram):

| test | SHARK2 | FUTO một mình | ensemble β=0,1 |
|---|---|---|---|
| nhịp — không dấu top-1 | 0,966 | 0,970 | **0,985** |
| nhịp — có dấu top-1 / top-3 | 0,913 / 0,963 | 0,913 / 0,964 | **0,927** / 0,964 |
| nhịp + bật vuốt tiếng Anh (n=521) — có dấu top-1 | 0,916 | 0,921 | **0,927** |
| đều — không dấu top-1 | 0,967 | 0,884 | 0,964 |
| đều — có dấu top-1 / top-3 | 0,911 / 0,961 | 0,837 / 0,904 | 0,909 / 0,960 |

iOS (Swift) cùng tập test, nhịp: SHARK2 0,913 · FUTO 0,908 · ensemble 0,927 (khớp Kotlin).

Từ rời (500 dạng Việt phổ biến, không ngữ cảnh) top-1 theo độ dài dạng gộp 2/3/4/5+ chữ — nhịp:
SHARK2 0,92/0,89/0,88/0,90 · FUTO 0,94/0,86/0,92/0,90 · ensemble 0,95/0,91/0,94/0,97; đều: SHARK2
0,88/0,90/0,90/0,94 · FUTO 0,85/0,76/0,66/0,59 · ensemble 0,91/0,91/0,82/0,83. Tiếng Anh (500 từ,
prior đang gõ Anh) top-1 — nhịp: SHARK2 0,956 · FUTO 0,946 · ensemble 0,960; đều: 0,960 · 0,820 ·
0,914.

**Thiên lệch tiền nghiệm tiếng Anh:** greedy CTC (không từ điển) trên đường nhịp có tỉ lệ lỗi ký
tự tiếng Việt ≈ 0,09–0,15 so với tiếng Anh ≈ 0,04–0,10 cùng độ dài (gấp ~1,5–2 lần); cặp chữ hay
mất nhất là đặc trưng Việt: hi, ng, uo, hu, ch, ho, ie, th (h trong nh/ch/th, nguyên âm đôi uo/ie
đi qua phím kề). Vì vậy chỉ dùng encoder làm KÊNH PHỤ trọng số nhỏ (β=0,1) cạnh SHARK2 + từ điển
Việt, không thay SHARK2. (Nhận xét người dùng Reddit "FUTO vuốt tiếng Việt rất tệ" là với decoder
cũ + từ điển AOSP; ở đây không tái hiện được mức đó nhờ ràng buộc từ vựng Việt + LM.)

**Độ trễ** (máy dev đang tải nặng, số thật sẽ khác): encoder Swift −O simulator ≈ 3,7 ms, cả
decode ensemble ≈ 4,9 ms; JVM ≈ 14 ms/lần (Android ART dự kiến chậm hơn — decode chạy trên luồng
chính lúc nhấc tay ⇒ có thể tụt 1–2 khung hình; cần đo trên máy thật). SHARK2 ≈ 0,1–0,4 ms.
**RAM** khi bật: weights Float 2,54 MB + scratch ≈ 0,37 MB (file mmap 1,27 MB chỉ lúc nạp); nhả
khi ẩn bàn phím / cảnh báo bộ nhớ (iOS didReceiveMemoryWarning, Android onTrimMemory). Công tắc
tắt: không tạo đối tượng, không đọc file — đường gõ vuốt y như cũ. Kích thước app +1,27 MB.

### Tái tạo

`sh Scripts/futo-swipe/build.sh` (python3 stdlib + curl): tải `.pte` theo revision + kiểm sha256 →
`convert.py` → `verify.py` → chép asset iOS/Android → sinh lại fixture. Kết quả byte-giống bản commit.

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
