# RAM audit — bàn phím iOS (28/09/2026)

Mục tiêu: biết extension `VietTelexKeyboard` tốn RAM vào đâu, có rò rỉ không, và sửa gì trước.
Trần jetsam của keyboard extension ~48–66 MB tuỳ máy/iOS (vượt ⇒ bị giết không log, iOS quay về
bàn phím trước — user thấy "bàn phím trắng / tự đổi bàn phím").

> Số đo trên simulator iPhone 17 (iOS 27.0), bản Release (`-Osize`), commit 6305eef. Simulator
> cộng thêm ~14 MB cố định (dyld_sim, `__DATA` framework hệ thống, page table) nên số tuyệt đối
> cao hơn máy thật vài MB; **phần tăng** giữa các trạng thái và rò rỉ thì như nhau. Dao động giữa
> hai lượt chạy ±5 MB (máy có tải song song).

## Kết luận nhanh

1. **Rò rỉ nghiêm trọng: mỗi lần ẩn/hiện bàn phím giữ lại NGUYÊN cây view cũ** (~1,8 MB/lần,
   không bao giờ nhả). 30 lần ẩn/hiện: 25 → **107 MB**. Trên máy thật extension sẽ bị jetsam
   sau khoảng 15–20 lần ẩn/hiện trong cùng app — rất có thể là nguồn "bàn phím tự văng".
   Nguyên mẫu "xé cây view khi `viewDidDisappear`": 30 vòng chỉ còn 16 → 20 MB. (§3)
2. **Bảng emoji**: mỗi emoji KHÁC NHAU từng vẽ để lại ~8,5 KB trong cache glyph của CoreText,
   vĩnh viễn trong process (cảnh báo bộ nhớ, nhả font đều không nhả). Mở + lướt 6 trang:
   +22 MB (lúc mở) / +16 MB (sau khi rời). Lướt hết ~3.800 emoji trong process test: +108 MB. (§4)
3. **Model cá nhân (UserLangModel)** là cấu trúc `[String: [String: Int]]` — ~1 KB/mục; 4.800 mục
   giả lập ≈ +13 MB heap lúc học dồn (≈5 MB còn lại sau khi lưu). Người dùng lâu gần trần
   (3.000/6.000/3.000) có thể tốn ~10 MB. (§5)
4. Dữ liệu mmap (`vnlm.bin`, `vnlexicon.bin`, `emoji.bin`, `futoswipe.bin`, `enlexicon.bin`) đúng
   thiết kế: **~0 dirty** (trang sạch 12–31 MB, jetsam không tính). FUTO (2,5 MB) nhả đúng khi ẩn.

## 1. Số đo process extension thật (MB phys_footprint)

`iOS/Scripts/ram-audit/ram-audit.sh <default|all|off>` — driver XCUITest đi qua các trạng thái,
host lấy `footprint` / `vmmap --summary` / `heap -s` của process extension ở mỗi mốc.

| Trạng thái | default | all (bật hết¹) | off (tắt hết) |
|---|---|---|---|
| Vừa hiện | 25 | 30 | 24 |
| Sau 200 phím | 26–33 | 40 | 29 |
| Đang mở emoji (lướt 6 trang) | 48–55 | 67 | 50 |
| Rời emoji về chữ | 41–51 | 57 | 44 |
| Panel clipboard | — | 58 | — |
| Sau 50 lần vuốt | 51 | 59 | 44 |
| Xoay ngang / dọc lại | 51 / 52 | 61 / 61 | 44 / 44 |
| Sau cảnh báo bộ nhớ² | không đổi | không đổi | không đổi |
| Sau 10 vòng ẩn/hiện | 69 | 72 | 57 |
| Sau 30 vòng ẩn/hiện | **107** | — | — |
| Đỉnh (peak) trước vòng ẩn/hiện | 61 | 71 | 52 |

¹ gợi ý + vuốt + FUTO + emoji gợi ý + clipboard + âm phím (mechanical) + rung + theme peach +
ảnh nền + trong suốt 30 % + hàng số + chip số/toán + teencode. Full Access bật, Plus mở.
² Simulator không có cách CLI tin cậy để bắn memory warning cho process khác (Simulator ghi file
`SIMULATOR_MEMORY_WARNINGS`, chỉ bắn được lần đầu tạo file) — số "sau cảnh báo" ở đây là không
nhận được cảnh báo. Đo trong process test (gọi thẳng `didReceiveMemoryWarning` + notification):
UIKit tự nhả **13–16 MB** footprint (cache CA/ảnh), heap của mình không giảm (§6).

Cơ cấu lúc vừa hiện (default, 25 MB): malloc 10 MB · `__DATA` framework hệ thống 10,4 MB (cố định)
· dyld + page table 3,4 MB · CoreAnimation 1 MB. Mặc định vs tắt hết chỉ khác ~1 MB lúc hiện.

## 2. Top thành phần (đo tách từng phần — `RamBreakdownTests`)

`RamBreakdownTests/testComponentBreakdown` (bộ chậm) nạp từng thành phần trong process test và in
phần tăng. Sắp theo mức ảnh hưởng thực tế:

| # | Thành phần | RAM | Nhả được? |
|---|---|---|---|
| 1 | **Cây view cũ bị giữ mỗi lần hiện** | +1,8 MB / lần hiện, không giới hạn | ✗ (rò rỉ) |
| 2 | **Cache glyph emoji màu (CoreText)** | ~8,5 KB / emoji khác nhau (mọi cỡ chữ) — 6 trang ≈ 15 MB, hết bảng ≈ 32 MB | ✗ suốt đời process |
| 3 | Backing store CA của bảng emoji (ô UILabel) | +8 MB khi đang mở | ✓ khi rời |
| 4 | Framework hệ thống (`__DATA` dirty, dyld, page table) | ~14 MB (sim) | ✗ cố định |
| 5 | UserLangModel (model cá nhân) | ~1 KB/mục; +13 MB đỉnh khi học 4.800 mục, ~5 MB giữ lại | ✓ khi bỏ controller |
| 6 | Ấm máy khi gõ (cache glyph chữ, layout, gợi ý) | +1 … +8 MB trong 200 phím đầu | một lần |
| 7 | Âm phím riêng (AVAudioEngine + HAL) | +3–4 MB footprint | ✓ shutdown khi ẩn |
| 8 | Ảnh nền (810×1080 @3x) | bitmap 3,4 MB, đỉnh giải mã +7 MB | ✓ |
| 9 | FUTO Swipe model | 2,5 MB | ✓ nhả khi ẩn / memory warning |
| 10 | `EmojiData.categories` (mảng ~3.800 String) | 1,8 MB heap | ✗ static suốt đời |
| 11 | planeCache (số + ký hiệu) | 1,4–2,6 MB | chỉ khi đổi chữ ký |
| 12 | TelexKeyPrior (trie smartTouch) | ~1 MB heap | ✗ static |
| 13 | enlexicon parse / SwipeDecoder template | 0,7 / 0,36 MB | template nhả khi `swipe = nil` |
| — | vnlm / vnlexicon / emoji.bin / futoswipe.bin (mmap) | ~0 dirty | trang sạch |

## 3. Rò rỉ #1 — cây view cũ sống mãi

Tái hiện: `iOS/Scripts/ram-audit/leak-cycle.sh 30` (app chủ tự đổi first responder mỗi 1,5 s,
KHÔNG qua XCUITest ⇒ không có runtime Accessibility giữ view):

| vòng ẩn/hiện | 0 | 10 | 20 | 30 |
|---|---|---|---|---|
| hiện tại: footprint (MB) / số `KeyboardView` sống | 8 / 1 | 46 / 16 | 71 / 31 | 72 / 31 |
| nguyên mẫu xé cây view khi ẩn | 16 / 1 | 19 / 1 | 20 / 1 | — |

(Trong process test cũng thấy: 20 lần dựng/đóng controller +17 MB.)

- `KeyboardViewController` được giải phóng đúng (heap chỉ còn 1–2 instance); **view** của nó
  (`UIInputView` → `KeyboardView` → ~40 `KeyButton`, label, constraint, gesture) thì không.
- `leaks --traceTree` cho đường giữ: `KeyButton` đang sống → `_cachedTraitCollection` →
  `_UICustomTraitStorage` → `_UICornerProvider.id` → `UIStackView` của bàn phím CŨ →
  `_layoutEngine` → toàn bộ cây cũ, và cây cũ lại giữ cây cũ hơn (chuỗi). Tức là trait "corner
  provider" (cơ chế góc bo đồng tâm iOS 26+) của UIKit được tái dùng giữa các lần dựng và kéo theo
  hierarchy cũ. `leaks` thường báo 0 "leak" vì mọi thứ vẫn reachable.
- Nguyên mẫu đã thử (KHÔNG commit): trong `viewDidDisappear` gỡ đệ quy mọi subview của `view`.
  Cắt được chuỗi (còn lại cùng lắm vài KB stack view + engine).

**Sửa đề xuất** (ưu tiên 1, tiết kiệm ~1,8 MB × số lần hiện, rủi ro trung bình):
`viewDidDisappear` → `keyboard.tearDown()` (nhả planeCache, emoji plane, panel clipboard, gỡ
subview đệ quy, `keyboard = nil`); `viewWillAppear` → nếu đã xé thì dựng lại `KeyboardView` (tách
phần dựng trong `viewDidLoad` ra hàm). Phải test: hiện → ẩn → hiện CÙNG controller (đổi app nhanh,
đổi ô nhập), xoay, iPad nổi, một tay, mẫu câu. Test hồi quy: `RamBreakdownTests` phần leak-cycles
(đang `XCTExpectFailure`, bỏ dòng đó khi sửa xong) + `leak-cycle.sh`. Nên gửi Feedback cho Apple
(trait `_UICornerProvider` giữ view mạnh).

## 4. Bảng emoji

- `testEmojiGlyphCache`: vẽ emoji bằng CoreText, mỗi emoji MỚI +8–10 KB heap ở MỌI cỡ (20/24/26/32/40
  pt như nhau); vẽ lại emoji cũ +0; `didReceiveMemoryWarning` +0; tự tạo `CTFont` rồi nhả cũng +0
  ⇒ cache glyph toàn process, không API nào xả. Đây là chi phí thuê font Apple Color Emoji —
  không tránh được bằng cỡ chữ.
- Ngoài cache glyph, lướt toàn bộ bảng trong process test tốn thêm ~15 KB/emoji (heap +92 MB tổng)
  — chưa tách được (nghi: layout text của UILabel với `adjustsFontSizeToFitWidth`, layout
  attributes của 3.800 item).
- Backing store CA ~8 MB khi mở — nhả khi rời (bảng emoji không vào planeCache ✓).

Đề xuất (ưu tiên 2):
- Bỏ `adjustsFontSizeToFitWidth` ở `EmojiCell` (đặt cỡ cố định theo metrics); tắt
  `collection.isPrefetchingEnabled` để không dựng/vẽ cột ngoài màn hình. Đo lại bằng
  `testComponentBreakdown` (bước "emoji scroll all sections"). Rủi ro thấp.
- `EmojiData.categories` giữ id `[UInt16]` thay vì `[String]`; ô tự đọc chuỗi từ blob mmap
  (`EmojiData.emoji(id)`) — −1,7 MB, rủi ro thấp.
- Cache glyph không xả được ⇒ giữ "khoảng trống" bằng cách sửa #1 và giảm các khoản khác; nhảy
  theo nhóm (thanh category) thay vì lướt liên tục đã giới hạn số emoji vẽ.

## 5. UserLangModel

`[String: Int]` + `[String: [String: Int]]` ×2 — mỗi cặp bigram tạo cả một Dictionary con.
Giả lập 24.000 lần học (1.600 uni / 1.600 bi / 1.600 tri): +13 MB heap đỉnh, ~5 MB giữ lại sau
lưu (phần còn lại là bản sao khi mã hoá plist + autorelease lúc học dồn). Đề xuất (ưu tiên 3,
tiết kiệm ước 60–80 % = 3–8 MB với người dùng lâu, rủi ro trung bình — đụng định dạng file,
đồng bộ iCloud, parity Android): intern từ thành id `Int32` (bảng từ), bi/tri thành
`[UInt64: UInt16]` (cặp id đóng gói) hoặc mảng phẳng sắp xếp; lưu nhị phân thay plist để hết đỉnh
khi mã hoá. Việc trước mắt, rủi ro thấp: `autoreleasepool` quanh vòng lưu/mã hoá.

## 6. Các khoản nhỏ hơn (ưu tiên 4+)

| Việc | Tiết kiệm ước | Rủi ro |
|---|---|---|
| Ảnh nền giải ở @2x thay @3x (nền đã mờ/phủ tối, mắt không thấy) | −1,9 MB giữ, đỉnh giải mã −3 MB | thấp |
| `didReceiveMemoryWarning`: thêm `planeCache.removeAll()`, bỏ `EmojiData` cache, `Wallpaper.dropCache()` khi không hiện, template vuốt khi ẩn | 2–4 MB khi bị ép | thấp |
| Âm phím: đã shutdown khi ẩn ✓; nếu cần nhẹ hơn nữa: `AudioServicesPlaySystemSound` với file dựng sẵn thay AVAudioEngine | −2–3 MB khi bật | trung bình (độ trễ/âm lượng) |
| Link yếu + nạp lười AVFAudio/AudioToolbox/CoreHaptics (đang link cứng, nạp lúc khởi động dù tắt) | ước 0,5–1,5 MB `__DATA` (cần đo máy thật) | trung bình |
| FUTO giữ fp16, đổi fp32 theo lớp khi chạy | −1,25 MB khi bật | trung bình (CPU) |

Đã đúng (không cần làm): mmap `.alwaysMapped` cho mọi blob; ảnh nền giải bằng ImageIO thumbnail
đúng cỡ (`kCGImageSourceThumbnailMaxPixelSize`) và nhả ảnh cũ trước khi giải ảnh mới; bảng emoji
không cache; FUTO nhả khi ẩn/memory warning; AVAudioEngine tắt khi ẩn; `CADisplayLink` trackpad dùng
proxy weak; closure `onKey`… đều `[weak self]`; `leaks` không thấy chu trình nào của code mình
(469 "leak" ≈ 25 KB đều là nội bộ UIKit `_UIViewServiceLegacyClientSession`).

## 7. Thực hành tốt đã đối chiếu

- WWDC18 *iOS Memory Deep Dive* / WWDC21 *Detect and diagnose memory issues*: footprint = dirty +
  compressed; ảnh giải = rộng × cao × 4 bất kể file nén; downsample bằng ImageIO; `vmmap --summary`,
  `footprint`, `leaks --traceTree`, memory graph.
- Extension: nhả khi `viewDidDisappear` / memory warning; không giữ cache static lớn; mmap dữ liệu
  chỉ đọc; `autoreleasepool` trong vòng lặp dựng nhiều object; tránh view/layer thừa (một plane chữ
  ~40 `KeyButton` + label là ổn — chi phí chính không nằm ở số view mà ở việc cả cây bị giữ).
- Cộng đồng bàn phím (KeyboardKit, bài "three hard constraints of an iOS keyboard extension"):
  trần ~48–60 MB, jetsam không để lại crash log ⇒ phải tự đo footprint theo trạng thái như file này.

## 8. Công cụ

| Công cụ | Dùng |
|---|---|
| `iOS/Scripts/ram-audit/ram-audit.sh <default\|all\|off> [out] [udid] [cycles]` | Driver XCUITest (`Driver/`, app chủ `Host/`, `project.yml` sinh bằng xcodegen) + mẫu footprint/vmmap/heap mỗi mốc, in bảng (`summarize.py`). ~8 phút/cấu hình. |
| `iOS/Scripts/ram-audit/leak-cycle.sh [cycles]` | Ẩn/hiện không qua XCUITest, in footprint + số `KeyboardView` sống. |
| `iOS/Scripts/ram-audit/heapdiff.py a.heap b.heap` | Lớp tăng nhiều nhất giữa hai mốc. |
| `RamBreakdownTests` (bộ chậm, scheme `VietTelexKeyboardSlowTests`) | Tách RAM từng thành phần + leak-cycles + cache glyph emoji. `TEST_RUNNER_VT_SLOW_TESTS=1 xcodebuild -scheme VietTelexKeyboardTests -only-testing:VietTelexKeyboardTests/RamBreakdownTests test` |

Lưu ý khi đo: (1) `pgrep` phải lấy đúng process extension của đúng simulator (script đã lọc theo
UDID); (2) XCUITest bật Accessibility ⇒ `_AXObjectCacheHelper` cũng giữ view — kiểm rò rỉ bằng
`leak-cycle.sh`; (3) `MallocStackLogging` qua `launchctl setenv` làm cả simulator chậm tới mức driver
hỏng — gỡ bằng `launchctl unsetenv`.
