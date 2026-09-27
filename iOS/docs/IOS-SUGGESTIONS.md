# Hệ thống gợi ý của bàn phím iOS (suggestion bar)

Tài liệu thiết kế cho toàn bộ pipeline gợi ý trên `VietTelexKeyboard` (iOS
keyboard extension). Viết 2026-07-24, sau hai vòng research (thiết kế datastore
cá nhân hóa + thuật toán inline suggestion) — nguồn tham khảo chính: Gboard
federated n-gram, SwiftKey dynamic model, Grammarly personal LM blog, KenLM,
kinh nghiệm pinyin IME.

## Tổng quan

Thanh gợi ý (30pt — quyết định giữ 30pt thay vì 44pt như stock, 2026-07-24, chỉ hiện khi bật toggle **Thanh gợi ý** trong app; bàn phím
cao 246pt khi bật, 216pt khi tắt) có **ba trạng thái** theo ngữ cảnh gõ:

| Trạng thái | Hiển thị | Nguồn dữ liệu |
|---|---|---|
| Field trống, chưa gõ | 3 từ user hay mở đầu nhất | `UserLangModel.topWords` |
| Vừa space sau một từ ("Anh ␣") | 3 từ **kế tiếp** dự đoán | `UserLangModel.nextWords` (trigram ⊕ bigram ⊕ seed), thiếu thì lấp bằng `SyllableBigram` (tầng 7) |
| Đang gõ dở một từ | `["nguyên văn"] \| ứng viên 1 \| ứng viên 2 (hoặc ≤3 emoji)` | `VNSuggest` (inline) + bigram tĩnh (tầng 7) + `EmojiSuggest` |

Rule ngữ cảnh cứng chạy trước cả ba: token trước con trỏ kết thúc bằng `@` →
gợi `gmail.com / yahoo.com / outlook.com`; kết thúc bằng `.` sau chữ/số → gợi
TLD `com / vn / net`. Các fragment này chèn không kèm space và không đi qua
datastore (token chứa `@`/`.` không phải "từ").

Chip số chạy song song cả hai trạng thái có chữ (xem tầng 8): khi token trước con
trỏ là số/số tiền/biểu thức "…=", **một** chip chiếm slot GIỮA — literal vẫn ở slot
đầu, nội dung slot giữa dời sang slot 3.

Hành vi bấm nhận: **nguyên văn** = giữ như đã gõ; **từ** = thay từ đang gõ +
space, đồng thời **học với weight 2**; **emoji** = thay từ bằng emoji (hành vi
QuickType). Tự tắt ở field từ chối gợi ý (`isSecureTextEntry`,
`autocorrectionType == .no`) — giống bàn phím stock.

## Các tầng dữ liệu

### 1. `VNSuggest` + `VNLexicon2Data` — inline suggestion (từ đang gõ dở)

- **Lexicon**: 7.184 âm tiết tiếng Việt (tập đóng, danh sách hieuthi) + tần
  suất văn nói OpenSubtitles, generate bởi `Scripts/gen-vnlexicon.py` thành
  blob tĩnh (~90KB) nằm thẳng trong binary — **zero cold-start**, quan trọng
  vì extension bị iOS kill/respawn liên tục.
- **Chuẩn hóa dấu kiểu cũ** lúc build: `hoà→hòa`, `thuý→thúy` — CHỈ với âm
  tiết mở (cặp oa/oe/uy ở cuối từ); có coda giữ nguyên (`toàn`, `thuyền`),
  sau `q` giữ nguyên (`quý` — u là glide).
- **Decompose**: mỗi ký tự → `(base, quality, tone)` pack 1 byte
  (`attr = quality<<3 | tone`; quality: 0 none / 1 â-ê-ô / 2 ơ-ư-ă / 3 đ;
  tone: 0-5 ngang sắc huyền hỏi ngã nặng). Bảng tra runtime ~190 ký tự, O(1)
  mỗi char, không allocation.
- **Lookup mỗi phím**: binary search range trên folded key (loại 99% lexicon)
  → post-filter **tương thích dấu** từng ký tự:
  - ký tự CHƯA bỏ dấu khớp mọi biến thể: gõ `to` → tôi, tớ, **toàn**…
  - quality đã chốt phải trùng: gõ `tô` → tôi, tối, tội… (**toàn** bị loại)
  - tone đã chốt phải trùng: gõ `tò` → tòa, tồi… (**tôi/tới** bị loại;
    `tồi` vẫn hợp lệ vì quality chưa chốt)
  - prefix 1 phím đi qua bucket **top-32 mỗi chữ cái** precomputed (hot path).
- Chi phí: **<50µs/phím** (budget 1-2ms). Trie/DAWG bị bác có chủ ý: ở scale
  7-15k entries chúng không thắng gì mà trả giá effort + cold-start.
- `VNSuggest.contains(word)` (binary search, zero RAM phụ) là nguồn
  "từ-trong-từ-điển" cho ngưỡng học của UserLangModel.

### 2. `UserLangModel` — datastore cá nhân hóa

- **Cấu trúc**: `uni [từ: count]`, `bi [prev → next → count]`,
  `tri ["p2␁p1" → next → count]` (nested dict → lookup O(1), không scan).
  Cap 3000/6000/3000, quá trần thì chia đôi mọi count (từ hiếm rơi về 0).
- **Học**: mỗi từ commit (+1; suggestion được bấm nhận +2 — tín hiệu mạnh
  hơn). Trigram chỉ ghi khi nền bigram (p2,p1) đã đạt count ≥2 — chống noise.
  Chống học typo: chỉ chữ cái thuần ≤12 ký tự, loại chuỗi lặp ≥3 ("heeeyyy");
  **learning-vs-suggesting** (pattern Grammarly): từ NGOÀI lexicon phải đạt
  count ≥3 mới được *xuất hiện* trong gợi ý (vẫn *đếm* từ lần đầu).
- **Ranking next-word**: linear interpolation với Bayesian shrinkage —
  `λ_tri = n/(n+2)`, `λ_bi = n/(n+4)`:
  `score = λ_tri·P_tri + λ_bi·P_bi + 0.1·P_uni + (1−λ_bi)·0.9·P_seed`
  (seed rank i → 0.5^i). Prev mới gặp 1-2 lần → tin seed; gặp nhiều → tin dữ
  liệu cá nhân. Một lần gõ nhầm không đè nổi seed curated (có golden test).
- **Decay**: mỗi ≥7 ngày, mọi count ×0.7^tuần lúc load (một timestamp toàn
  cục duy nhất — không lưu thời gian per-từ). Hồ sơ phản ánh thói quen gần đây.
- **Persistence**: binary plist `App Group/userlm.plist`, ghi atomic,
  coalesce 5s sau phím cuối + khi bàn phím đóng; có migrate từ format v1.
  SQLite trong App Group bị bác có chủ ý (anti-pattern iOS — corruption khi
  extension bị suspend).
- **Ranking inline**: điểm ứng viên khi đang gõ dở =
  `log(staticFreq+1) + 2.5·log(personalCount+1) + 4·[có trong nextWords ngữ cảnh] + 1.5·[chỉ-còn-thiếu-dấu] + bigram`
  (bigram = tầng 7). Logic thuần ở `SuggestRank.rankInline` (SuggestionSupport); hoà điểm giữ
  thứ tự pool (tần suất tĩnh) để iOS ≡ Android.

### 3. `SeedData` — mồi ban đầu

Inject qua `seedIfEmpty()` khi datastore trống (cài mới / sau nút **Xóa từ đã
học**). ~700 unigram + ~470 bigram:

- Lõi hội thoại từ **OpenSubtitles2018 tiếng Việt** (lọc bias phim ảnh) + lớp
  chat/teencode curated (ko, đc, nhé, nha, haha…), weight log-scale **max 50**.
- ~112 từ tiếng Anh hay pha trong chat Việt (ok, thanks, meeting…), cap ≤18.
- Proper noun (weight 3-15, dưới lớp hội thoại): địa danh VN/quốc tế, thương
  hiệu (SenPrints, FPT, VinFast…), tech (GitHub, Claude, ChatGPT…), OS, crypto,
  họ/đệm/tên VN với **chuỗi bigram họ→đệm→tên** (Nguyễn␣ → văn/thị → hùng/lan).
- Cụm đa âm tiết luôn tách thành **bigram nối** (`hồ→chí` + `chí→minh`) để gợi
  ý trôi liên tiếp cả chuỗi.
- **Hợp đồng weight**: gõ thật +1/lần vượt seed sau 2-3 ngày; decay tuần làm
  seed mờ dần — seed chỉ là bệ đỡ ngày đầu.

### 4. `EmojiSuggest` — emoji theo nghĩa từ

721 khóa generate từ `kid-words.json` + bản dịch EN của learn-site + bảng
"emoji họ hàng" curated: từ Việt, dạng KHÔNG DẤU và từ Anh cùng nghĩa trả về
cùng bộ ≤3 ứng viên (`yêu ≡ yeu ≡ love → ❤️ 💕 💗`).

### 5. `DisplayCase` — case chuẩn khi hiển thị

Datastore case-fold toàn bộ; bảng `DisplayCase` map dạng thường → dạng chuẩn
lúc HIỂN THỊ và chèn (`senprints → SenPrints`, `iphone → iPhone`,
`macos → macOS`, `nguyễn → Nguyễn`). Nguyên tắc: **chỉ token không nhập
nhằng** — vũ/đỗ/ngô/trang/nội/quốc bị loại có chủ ý (thà hiện thường còn hơn
hoa sai giữa câu). Học vẫn đếm dưới khóa thường.

### 6. `SensitiveWords` — lọc từ nhạy cảm

Chuẩn ngành (Gboard/SwiftKey): từ tục **vẫn nằm trong datastore và vẫn được
học**, nhưng toggle **Lọc từ nhạy cảm khỏi gợi ý** (mặc định BẬT — cân nhắc
App Store review) giấu chúng khỏi thanh. Phân tầng: chỉ token thô (lồn, địt,
đcm, vcl, tml, sml, fuck…) bị lọc; insult chuẩn mực (khốn nạn, ngu si) và từ
đời thường (cướp, giết, đánh rắm, mày/má) KHÔNG lọc. Khi lọc, over-fetch 6
lấy top-3 nên slot luôn được lấp.

### 7. `SyllableBigram` — bigram âm tiết tĩnh (27/09/2026)

Bảng `Resources/vnbigram.bin` (PMI chiết khấu cặp âm tiết liền nhau, ~1,2MB; nguồn/giấy phép
`docs/DATA-SOURCES.md`) — CÙNG một instance `SyllableBigram.shared` với gõ vuốt (map một lần).
Mục đích: người dùng MỚI (UserLangModel chỉ có seed) vẫn được gợi ý theo ngữ cảnh.

- **Inline**: `bigram = min(8, 2.5·PMI(âm tiết trước → ứng viên))`, nhân **0.45** khi có ứng
  viên nào của pool nằm trong nextWords (cá nhân/seed đã có ý kiến về lượt này) ⇒ trần hiệu
  dụng 3.6 < 4 (điểm nextWords) — **cá nhân thắng** khi còn lại ngang nhau (golden: user gõ
  "sao có" 3 lần ⇒ "co" ra có, dù bigram nghiêng cô). Không âm tiết trước / từ lạ ⇒ 0.
- **Từ kế tiếp**: nextWords (cá nhân/seed) giữ trước; còn < 3 thì lấp bằng top âm tiết theo
  `PMI + 12·freq/255` sau từ trước (PMI thuần nghiêng cặp hiếm), qua lọc nhạy cảm + DisplayCase
  + viết hoa đầu câu như mọi gợi ý; cuối cùng mới đệm topWords.
- **Hiệu năng**: PMI cho pool tính ở `suggestQueue` (nền, cùng generation token); từ kế tiếp
  tra trên main ~µs. Bảng mmap `.alwaysMapped`, đọc tại chỗ: RAM bẩn ≈ 0 (test đo
  phys_footprint sau khi duyệt toàn bảng). Map + hash kiểm lexicon chạy nền ở `viewDidLoad`.
- **Đo** (`SuggestBigramTests`, câu Tatoeba giữ lại, người dùng mới gõ chạm không dấu):
  slot1 0.747 → 0.829, 3 slot 0.880 → 0.938, từ kế tiếp top3 0.111 → 0.271; người dùng đã học
  dần cũng tăng (không tụt). Trọng số chọn bằng lưới `tuneGrid` (Android, `VT_TUNE=1`).

### 8. `NumberChips` — đọc số, định dạng tiền, máy tính nhanh

Hàm thuần `NumberChips.chip(before:)` (Swift) ≡ `NumberChips.chip(before)` (Kotlin),
cùng kết quả trên fixture chung `KeyboardTests/Fixtures/number-chips.txt`. Không bao
giờ tự thay: chip chỉ hiện, chạm mới thay đúng đuôi đã tính (kiểm lại đuôi context
trước khi xoá — lệch thì bỏ, không xoá mù).

- **Chọn chip** (1 chip / lượt): `…=` → kết quả phép tính, chèn sau dấu `=`;
  số + `k/nghìn/ngàn`, `tr/triệu`, `tỷ/tỉ/ty` (liền hoặc cách: `50k`, `1tr2`,
  `1.2tr`, `2 tỷ`) → `1.200.000 ₫`; số chưa phân nhóm + `đ`/`₫` (≥4 chữ số) →
  `1.250.000đ` (giữ ký hiệu); số đã định dạng + `đ`/`₫`, hoặc + `đồng`/`vnd` → chữ +
  " đồng"; số trơn/có phân cách → chữ. Chuỗi chạm: `1tr2` → `1.200.000 ₫` →
  `một triệu hai trăm nghìn đồng`. Viết hoa chữ đầu khi token ở đầu câu.
- **Không gợi ý**: số trơn mở đầu bằng 0 (số điện thoại, mã) hoặc >12 chữ số
  (số tài khoản); tiền có lẻ dưới 1 đồng.
- **Đọc số**: "linh" (hàm có tuỳ chọn "lẻ"), mười/mươi, mốt sau mươi, lăm sau
  mười/mươi, giữ "bốn" (không "tư"); nhóm 0 bỏ qua, nhóm sau nhóm đầu đọc đủ
  "không trăm" (`1.000.001` = một triệu không trăm linh một); tỷ lặp mỗi 9 chữ số
  (`10^12` = một nghìn tỷ, `10^18` = một tỷ tỷ). Thập phân "phẩy": phần lẻ ≤2 chữ số
  không mở đầu 0 đọc như số (3,14 = ba phẩy mười bốn), còn lại đọc từng chữ số. Âm: "âm".
- **Dấu phân cách** (không đoán): có cả `.` và `,` → dấu sau cùng là thập phân;
  chỉ `,`: 1 lần = thập phân, ≥2 = phân nhóm; chỉ `.`: ≥2 = phân nhóm, 1 lần = phân
  nhóm khi sau nó đúng 3 chữ số và phần nguyên 1–3 chữ số không mở đầu 0
  (`1.250` = 1250), còn lại thập phân kiểu Anh (`1.5`).
- **Máy tính**: `+ - * x × / ÷ : ( ) %`, có/không khoảng trắng; `A ± B%` = A ± A·B/100
  (như máy tính điện thoại), còn lại `B%` = B/100. Kết quả kiểu Việt (thập phân `,`),
  kiểu Anh nếu biểu thức dùng `.` thập phân hoặc `,` phân nhóm; phân nhóm nghìn chỉ
  khi biểu thức có phân nhóm; ≤12 chữ số có nghĩa; chia 0 / |kết quả| ≥ 10^15 → không chip.
- **Chi phí**: chỉ đọc `documentContextBeforeInput` khi token hiện tại hoặc ngay
  trước có chữ số/phép tính (đếm dấu cách kể từ chữ số cuối ≤1).

## Settings (App Group `group.com.viettelex`)

| Key | Mặc định | Ý nghĩa |
|---|---|---|
| `showSuggestions` | true | Bật thanh gợi ý (bàn phím 246pt ↔ 216pt) |
| `learnWords` | true | Cho phép học từ hay dùng |
| `filterSensitive` | true | Lọc từ tục khỏi gợi ý |
| nút **Xóa từ đã học** | — | Xóa `userlm.plist`; lần mở sau seed lại |

## Privacy

- Chỉ đếm **tần suất** từ đơn + cặp/bộ-ba từ — không lưu câu, không thứ tự gõ,
  không timestamp per-từ. Ô mật khẩu không bao giờ đi qua pipeline.
- Toàn bộ dữ liệu nằm trong App Group container trên máy; không Full Access,
  không network.

## Bản đồ file

| File | Vai trò |
|---|---|
| `ios/Keyboard/VNSuggest.swift` | Engine inline suggestion (lookup + compat filter) |
| `ios/Keyboard/VNLexicon2.swift` | GENERATED — lexicon 7.184 âm tiết (blob) |
| `Scripts/gen-vnlexicon.py` | Script tái lập lexicon (nguồn hieuthi + OpenSubtitles) |
| `ios/Keyboard/UserLangModel.swift` | Datastore cá nhân hóa n-gram |
| `ios/Keyboard/SeedData.swift` | GENERATED + curated — seed ban đầu |
| `ios/Keyboard/EmojiSuggest.swift` | GENERATED — emoji theo nghĩa |
| `ios/Keyboard/DisplayCase.swift` | Case chuẩn proper noun |
| `ios/Keyboard/SensitiveWords.swift` | Bộ lọc từ nhạy cảm |
| `ios/Keyboard/SyllableBigram.swift` | Bảng bigram âm tiết tĩnh (mmap, dùng chung gõ vuốt) |
| `ios/Keyboard/SuggestionSupport.swift` | `SuggestRank` (xếp hạng inline + lấp từ kế tiếp), `SuggestionFill` |
| `ios/Keyboard/NumberChips.swift` | Chip số: đọc chữ / định dạng tiền / máy tính (thuần) |
| `ios/Keyboard/KeyboardViewController.swift` | Điều phối: context, học, build SuggestionSet |
| `ios/Keyboard/KeyboardView.swift` | UI thanh gợi ý (SuggestionSet → slots) |

Tests: `ios/KeyboardTests/EngineBridgeTests.swift` — goldens cho compat-match
("tô" ⊅ toàn), shrinkage (1 lần gõ nhầm không đè seed), trigram gating,
ngưỡng học từ lạ, seed contract (max weight ≤50), filter tiers, display-case.
`ios/KeyboardTests/SuggestBigramTests.swift` (≡ android `SuggestBigramTests.kt`) — số đo heldout
trước/sau làm ngưỡng hồi quy, cá nhân thắng, độ trễ, RAM bẩn.
`ios/KeyboardTests/NumberChipsTests.swift` + android `NumberChipsTests.kt` — cùng
fixture `number-chips.txt` (đọc số, viết tắt k/tr/tỷ, biểu thức, chip theo context).

## Đường nâng cấp đã vạch (chưa làm)

- Personal model >50k entries → binary sorted array + mmap.
- Lexicon tĩnh >100k mục (lên tầng từ ghép/cụm) → double-array trie / marisa,
  bài học pinyin IME.
- Học case từ chính user (hiện DisplayCase là bảng tĩnh).
- Gợi ý viết hoa theo ngữ cảnh câu (auto-shift-aware).
