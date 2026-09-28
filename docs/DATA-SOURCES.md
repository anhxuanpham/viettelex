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

#### Phân tích 45 nét thật đầu tiên (iPhone, Luyện vuốt, 28/09/2026) — nhịp, lố, sửa chung cặp

Nét thật (SwiftUI 60 Hz, lọc 1/5 phím) khác hẳn đường giả cũ (`SwipeSim.path`: tốc độ đều
~21 phím/s, đầu/cuối đúng tâm):

| đo | nét thật | `SwipeSim.path` (cũ) | `SwipeSim.natural` (mới) |
|---|---|---|---|
| lấy mẫu | 16,6 ms, có khoảng 60–180 ms (dừng) | 16,7 ms đều | 16,7 ms + dừng |
| tốc độ (phím/s) p10/p50/p90 | 4 / 17 / 32 | ≈ 21 cố định | 4 / 20 / 34 |
| tốc độ tại phím định đi (giữa) / phím lướt qua, ÷ trung bình | 0,78 / 1,97 | ≈ 1 / ≈ 1 | 0,93 / 1,97 |
| thời gian trong bán kính 0,5 phím: phím định đi / lướt qua | 116 / 33 ms | — | 117 / 33 ms |
| giữ ngón trước khi đi (dt điểm 2) | 83 ms | 17 ms | 83 ms |
| lệch điểm đầu (theo hướng nét, + = về phím kế) | −0,16 ± 0,25 | 0 | −0,14 ± 0,25 |
| **lố điểm cuối** theo hướng nét cuối, p10/p50/p90 | **−0,09 / +0,45 / +1,14** | 0 | −0,25 / +0,43 / +0,92 |
| khoảng cách tâm phím giữa ↔ đường (trung vị) | 0,20 | ~0,2 | 0,17 |

Tức là: người thật CHẬM ở phím định đi, lướt nhanh gấp đôi qua phím nằm giữa đường, và TRÔI
chậm quá phím cuối trước khi nhấc tay (đấy → đâu, lấy → lâu, thay → thai). `SwipeSim.natural`
(SwipeDecoderTests, Kotlin + Swift) mô phỏng các đặc điểm trên; đường cũ giữ cho ngưỡng hồi quy.

Decoder (cả hai nền tảng, cùng hằng số; chỉ khi có thời gian điểm — đường không thời gian chấm y
hệt cũ, fixture `swipe-paths.txt` không đổi; parity nhịp: `swipe-paths-timed.txt`):
- **miễn lố cuối** (`overshoot` 1 phím): thành phần lệch THEO hướng nét cuối của template được
  miễn ở ~15 % cuối đường, chỉ khi đuôi nét chậm (tốc độ tương đối đuôi ≤ 0,5 đủ, ≥ 0,8 tắt);
- **phím lướt qua** (`speedWeight` 0,3, `speedRef` 1,3): mỗi phím giữa của ứng viên mà điểm đường
  gần nó nhất có tốc độ tương đối r > 1,3 bị trừ 0,3·(r − 1,3) (cũng → chung, vì → vui);
- **điểm dừng** (`dwellWeight` 3, r < 0,35, không sát 2 đầu) phải gần một phím của ứng viên.
- Đã thử, KHÔNG giữ: tiền nghiệm dạng không dấu = tổng mọi dấu (hiện là âm tiết mạnh nhất —
  vi = vì): +2 nét thật nửa dev nhưng −0,8…−1 điểm đường giả; miễn "hụt" ở điểm đầu (hội/gọi):
  ±0; ưu tiên Việt mạnh hơn sau từ Việt (bias −1,2…−1,5): +0,1 điểm Việt nhưng −1,5…−5 điểm từ
  Anh chen sau từ Việt — "như the" → "thế" đã đúng nhờ LM (test `phraseViDuNhuTheNay`).

**Sửa chung cặp** (`SwipeRevise.revise(…, next: [SwipeWord])`, iOS `SwipeTyping.finish` + Android
`KeyboardSession.resolveSwipe`): từ vuốt trước được chọn CÙNG ứng viên tốt nhất của cú vuốt này
theo nó (trigram · 0,15 = trọng số LM trái, lề 0,1), ứng viên rộng hơn (từ trước 3 dạng × 8 dấu
≤ 12, từ này ≤ 16). Báo lỗi "ví dụ như thế này" → trước: "vì dù như thế này" cả với đường sạch
(ví không nằm trong 4 dấu đầu của "vi", dụ kém sau "vì").

Chọn hằng số trên: nửa A nét thật (chỉ số chẵn) + đường giả dev (từ rời seed 1, câu giữ lại
%12==0 / chuỗi dev của SwipeRevise); báo trên nửa B + tập kiểm thử (`SwipeTuneTests`, layout
iPhone 36,8 pt). Trước = decoder cũ + sửa theo top-1 từ kế:

| tập | trước | sau |
|---|---|---|
| nét thật nửa A (dev, 23) top-1 | 15 | 18 |
| **nét thật nửa B (22, không dùng chỉnh)** top-1 | 15 | **18** |
| nét thật cả 45: top-1 / top-3 | 0,667 / 0,933 | **0,800** / 0,911 |
| — tiếng Việt / tiếng Anh top-1 | 0,606 / 0,833 | 0,788 / 0,833 |
| từ rời test, đường tự nhiên top-1 / top-3 | 0,788 / 0,945 | **0,873** / 0,978 |
| từ rời test, đường đều | 0,908 / 0,995 | 0,905 / 0,998 |
| câu giữ lại test (LM, bật EN), tự nhiên top-1 / top-3 | 0,835 / 0,908 | **0,882** / 0,944 |
| câu giữ lại test, đường đều | 0,915 / 0,964 | 0,914 / 0,964 |
| vuốt tuần tự cả câu (SwipeRevise test, n = 4 631), đường đều | 0,858 | **0,914** |
| — đường tự nhiên | 0,758 | **0,893** |
| — đường tự nhiên, bật vuốt tiếng Anh | 0,742 | **0,889** |
| "ví dụ như thế này" ×30 đường tự nhiên (JVM layout 40) | 0,527 | **0,740** |

Còn sai trên nét thật: thay→thai, đấy→đâu (1/4), hội→gọi ×2, trai→tai, have→gave, chỉ→cu (nét
trôi lên u), away/cũng nét vòng. Độ trễ decode (cùng đường tự nhiên, bật vs tắt nhịp): JVM +10 %,
iOS Debug simulator +5 %; sửa chung cặp thêm ≤ 12 × 16 lần tra LM sau nhấc tay (~0,01 ms JVM).
Chạy lại: `SWIPE_TUNE=1 SWIPE_TRACES=… SWIPE_CFGS='legacy;base' ./gradlew --offline
:keyboard:test --tests '*SwipeTuneTests*' -i | grep TUNE` (xem đầu SwipeTuneTests.kt).

#### 500 nét thật (iPhone, Luyện vuốt, 28/09/2026) — chữ h của phụ âm ghép

Kho 500 nét (415 Việt / 85 Anh, 257 từ mục tiêu, gồm cả 45 nét trên). Luyện vuốt lặp một từ tới
khi đúng ⇒ kho **nghiêng về từ khó** (chưa 16 lần, chọn 13, chúa 12…) và các lần thử cùng từ tương
quan. Tách TẤT ĐỊNH 70/30 (`SwipeTuneTests.split`): phân tầng theo dạng mục tiêu, trong nhóm xếp
theo băm chỉ số, lần thứ k vào tập giữ lại khi (3k + băm(từ)) mod 10 < 3 ⇒ chỉnh 341 / giữ lại 159.
Chỉ chỉnh trên 341 nét + đường giả dev; báo trên 159 nét + tập kiểm thử giả + câu giữ lại.

Phân tích lỗi lớn nhất (chua→cua ×19, chon→con ×9, cho→co ×7 trên tập chỉnh):
- h của ch/nh… bị lướt **nhanh như phím thường** (tốc độ tương đối tại h: chọn ≈ 2,1, chưa ≈ 1,5,
  phím lướt qua ≈ 2) — miễn phạt lướt qua cho chữ thứ hai của phụ âm ghép, hay lấy tốc độ nhỏ nhất
  quanh phím ("chậm nhẹ"), **không** cứu được: tắt hẳn phạt nhịp thì "cua" vẫn thắng (tiền nghiệm
  của 234 > chưa 204, hình học gần hoà) mà cũng → chung tăng. Đã thử, không giữ.
- Thứ phân biệt được là đường **UỐN về h**: uốn = khoảng cách h tới dây cung c→u − khoảng cách h
  tới đường. chưa: trung vị +0,22 (n = 28); của: −0,20 / −0,12; cũng: ≈ 0 (7/10 ≤ 0,12). Với
  chọn/con, có/cho (h gần như nằm trên dây cung c→o, 0,14 phím) và trên/tên, trả/ta (r thẳng hàng)
  hình học KHÔNG phân biệt được — chọn/con từ rời là do tiền nghiệm, cần ngữ cảnh.
- Decoder (cả hai nền tảng, cùng hằng số, không cần thời gian điểm): `bendWeight` 3 — hai ứng viên
  trong pool khác nhau đúng một h giữa sau c/n/t/p/k/g (Anh t/s/c/w/p/g), dây cung cách h
  0,3–1 phím ⇒ ứng viên có h += 3·kẹp(uốn − 0,05, ±0,3), rồi kẹp trong điểm của cặp ± 0,01 (chỉ đổi
  chỗ TRONG cặp). Mở rộng cho r/g/i (tr, ng, gi) làm hỏng từ rời giả (ta → tra, nang → ngang) — bỏ.

Trước = main sau commit nhịp (fe1dae6); số tập giữ lại in đậm:

| tập | trước | sau |
|---|---|---|
| nét thật chỉnh (341) top-1 / top-3 | 0,730 / 0,953 | 0,768 / 0,953 |
| **nét thật giữ lại (159) top-1 / top-3** | 0,774 / 0,937 | **0,780** / 0,937 |
| — giữ lại: Việt / Anh | 0,756 / 0,857 | 0,763 / 0,857 |
| — giữ lại: đúng cả DẤU (dạng + dấu mạnh nhất = mục tiêu) | 0,616 | 0,616 |
| cả 500: top-1 | 0,744 | 0,772 |
| từ rời giả test: tự nhiên / đều top-1 | 0,873 / 0,905 | 0,875 / 0,903 |
| câu giữ lại test (LM, bật EN): tự nhiên / đều top-1 | 0,882 / 0,914 | 0,882 / 0,913 |
| vuốt tuần tự cả câu test (n = 4 631): tự nhiên / đều | 0,8933 / 0,9136 | 0,8927 / 0,9125 |
| — cùng, tập chỉnh (n = 2 389) | 0,8966 / 0,9326 | 0,8974 / 0,9334 |
| từ Anh sau từ Việt top-1 (tự nhiên / đều) | 0,886 / 0,864 | 0,886 / 0,864 |

Tuần tự cả câu test −3/−5 từ trên 4 631 (đều: của → chúa ×4 — đường giả nhiễu uốn ngẫu nhiên về h);
tập chỉnh +2. Độ trễ decode (đường tự nhiên, bật vs tắt uốn): JVM +5 %, iOS Debug simulator +4 %.

**Dấu (Luyện vuốt hiện từ CÓ dấu, chấm theo dạng không dấu):** 16 % nét giữ lại đúng dạng nhưng
sai dấu (đấy → đây, nhỏ → nhớ, cầu → cậu, máy → mày…) — không phải lỗi decoder: `expand` đã xếp
dấu theo tần suất của CHÍNH âm tiết có dấu; từ rời không có ngữ cảnh thì dấu mạnh nhất luôn thắng
(mày 203 > máy 183 là thiên lệch phụ đề của OpenSubtitles). Các "lỗi" dạng chi→chi, cam→cam trong
danh sách lỗi là lỗi dấu này, không phải decoder.

Còn sai trên tập giữ lại: chưa → của ×4 (nét thẳng), chọn → con ×4, cho → có ×2, trả → ta ×2
(thẳng hàng — chỉ ngữ cảnh gỡ được), chú → chỉ ×2, trượt vài từ Anh (qua→wits, own→owen, good→fog/
golf, felt→left). Có ngữ cảnh (vuốt tuần tự): chưa cuối câu hỏi ("…đài loan chưa") và "không cho"
→ "không có" vẫn thua LM — việc của trọng số LM, chưa đụng.

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
CC BY-SA 4.0 theo README dự án; số liệu suy ra từ OpenSubtitles). Danh sách âm tiết
gist hieuthi: maintainer đã rà soát 27/09/2026 — được sử dụng tự do.

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
