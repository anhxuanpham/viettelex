# RAM audit — bàn phím Android (process IME)

Ngày đo: 28/09/2026 · commit gốc `6305eef` · chỉ đo + khuyến nghị, **chưa đổi hành vi**.

## Cách đo (lặp lại được)

| Công cụ | Việc |
|---|---|
| `android/Scripts/ram-audit.sh matrix OUT [APK]` | Ma trận cấu hình × trạng thái trên emulator: `dumpsys meminfo`, `/proc/pid/smaps` (vùng `base.apk` = asset mmap), `dumpsys gfxinfo` (cache HWUI/GPU), SIGQUIT → tổng byte ART đã cấp phát + số GC. Tự đặt VietTelex làm IME, trả lại IME cũ khi thoát. |
| `android/Scripts/hprof-summary.py` | Đọc heap dump (`am dumpheap -g` + `hprof-conv`): top lớp theo shallow size; `--referrers X --path` in chuỗi tham chiếu ngắn nhất tới GC root (thay LeakCanary). |
| `keyboard/.../RamFootprintTests.kt` | JVM: heap giữ lại + rác tạm lúc dựng từng cấu trúc; byte cấp phát/phím (ThreadMXBean); `VT_JFR=1` ⇒ JFR chỉ ra dòng code cấp phát. Chạy: `VT_SLOW_TESTS=1 [VT_JFR=1] ./gradlew --offline :keyboard:test --tests '*RamFootprintTests*' -i \| grep RAM` |

Máy: AVD `relaykey-m1` (sdk_gphone64_arm64, API 35, 1080×2400 @420 dpi, RAM 2.5 GB), bản **release** (R8 + shrink, ký debug key), ô "First name" của Contacts, gõ chạm thật (`input tap`) 200 phím.
Cấu hình: **default** (mặc định app) · **off** (tắt gợi ý, chọn phím thông minh, vuốt, âm/rung, …) · **all** (vuốt + FUTO + vuốt tiếng Anh, gợi ý, clipboard, âm phím, rung, mẫu câu, tự sửa, ảnh nền 810×1080 + trong suốt 30 %, Plus).

Lưu ý emulator: cột *Graphics* = 0 (emulator không có memtrack) — texture GPU (gfxinfo báo 8–11 MB) trên máy thật sẽ hiện ở Graphics; Native heap có thêm phần giả lập GL. So sánh **tương đối** giữa cấu hình là đáng tin; số tuyệt đối trên máy thật sẽ khác vài MB.

## Số đo (KB, PSS)

| Trạng thái | default PSS | Java | Native | Code | off PSS | all PSS | all Java | all Native |
|---|---|---|---|---|---|---|---|---|
| vừa hiện (process mới) | 50 085 | **16 008**¹ | 17 728 | 4 756 | 34 825 | **77 902** | **34 552**¹ | 21 484 |
| sau 200 phím | 50 660 | 6 256 | 19 732 | 7 660 | 45 577 | 63 771 | 9 936 | 23 856 |
| mở emoji (cuộn 6 trang) | 53 708 | 4 860 | 24 036 | 7 088 | 47 830 | 67 253 | 8 916 | 28 632 |
| mở clipboard | – | – | – | – | – | 67 691 | 8 528 | 29 332 |
| ẩn bàn phím | 54 541 | 4 416 | 25 260 | 7 092 | 48 926 | 67 492 | 8 528 | 29 216 |
| `send-trim-memory BACKGROUND` | 48 164 | 4 396 | 18 864 | 7 092 | 42 908 | 57 716 | 5 964 | 22 004 |
| `… COMPLETE` | 44 947 | 3 584 | 16 444 | 7 092 | 41 569 | 55 092 | 4 796 | 20 536 |
| hiện/ẩn thêm 20 lần | 57 479 | **16 016**² | 15 816 | 7 924 | 43 119 | 62 552 | 11 136 | 19 672 |

¹ ở lần đo khác (rel2) default-shown = 29 MB Java: đỉnh do rác lúc dựng bảng *chọn phím thông minh* (xem #1). ² dựng lại bảng đó sau trim.

| Cấp phát ART (tích luỹ) | default | off | all |
|---|---|---|---|
| tới lúc bàn phím hiện | **~30 MB** | 4.2 MB | **~37 MB** |
| 200 phím | +1–2 MB (~5–7 KB/phím) | +1.5 MB | +3 MB |
| 20 lần hiện/ẩn | **+28.7 MB** (sau trim) | +2 MB | **+95 MB** (FUTO nạp lại mỗi lần hiện) |
| Số GC trong cả kịch bản | 11 | 7 | 16 |

Tham chiếu cùng emulator: **Gboard sau 200 phím = 189 MB PSS** (Java 17.7, Native 49.8, Code 60.9 MB). VietTelex nhẹ ~3–4× — hướng tối ưu là **đỉnh** và **churn**, không phải nền.

Mở app cài đặt (Compose, **cùng process**) rồi thoát: PSS IME 40.4 → **57.2 MB** (+16.7 MB) và **giữ nguyên** vì từ API 31 Back không finish activity gốc (Activities = 1 sau khi thoát), mà process IME ở oom_adj 100 nên hệ thống không bao giờ dọn.

### Heap giữ lại theo cấu trúc (JVM ≈ ART, ±15 %)

| Cấu trúc | Giữ lại | Rác lúc dựng | Khi nào sống |
|---|---|---|---|
| FutoSwipeModel (fp16 → FloatArray + scratch) | **3.4 MB** | 2.8 MB | FUTO bật; nhả lúc ẩn ⇒ nạp lại mỗi lần hiện |
| SwipeEnglish.lexicon (~25k String) | **1.4 MB** | 1.9 MB | vuốt tiếng Anh / gõ EN — `by lazy` trong object, **không bao giờ nhả** |
| UserLangModel đầy cap (HashMap<String,Int>) | 1.5 MB | 14 MB | luôn (seed mới: 0.2 MB) |
| TelexKeyPrior (chọn phím thông minh, **mặc định BẬT**) | 0.86 MB | **31 MB** | luôn; nhả ở onTrimMemory ⇒ dựng lại |
| SwipeDecoder templates | 0.37 MB | 0.5 MB | gõ vuốt |
| VNLexicon2 offsets / SwipeLexicon.forms / Emoji strings | 0.12 / 0.11 / 0.11 MB | < 3.3 MB | luôn / vuốt / emoji |
| SyllableLM, EmojiSuggest, EmojiSearch | ~0 (mmap) | < 1 MB | — |

Asset `.bin`: **đã mmap đúng cách** (`noCompress += "bin"` + `openFd` + `FileChannel.map`) — smaps thấy vùng `base.apk` riêng từng asset, trang *sạch* (kernel thu hồi được): emoji.bin 112/256 KB resident, vnlexicon 152 KB, enlexicon 184 KB. Riêng `SwipeEnglish.parse` và `TelexKeyPrior` **copy cả enlexicon vào ByteArray** rồi dựng String. (vnlm.bin không được map trong các kịch bản gõ chạm này — chỉ khi vuốt/Thêm dấu cần.)

### Cấp phát mỗi phím (JVM, `RamFootprintTests.allocationPerKey`)

| Đường | B/phím | Nguồn chính (JFR) |
|---|---|---|
| engine + auto-shift | ~1.7 KB | `autoShiftFor` (`trim` copy chuỗi ngữ cảnh ≤256 ký tự), đọc ngữ cảnh |
| + thanh gợi ý | ~7.3 KB | **42 % `EngineBridge.composeTrial` tạo `TelexEngine()` mới mỗi lần** (~12 IntArray(32)); `VNSuggest.display` String; `VNSuggest.matches` |

5–7 KB/phím ⇒ GC trẻ ~mỗi 500–800 phím, concurrent — **không phải nguồn jank hiện tại** (máy đo 1 GC/200 phím, không có GC chặn lúc gõ). Churn lớn nằm ở dựng/nạp lại dữ liệu (#1, #3).

### Native / đồ hoạ

Native heap 16–29 MB là phần lớn nhất nhưng chủ yếu **HWUI/Skia của framework**: ~17.5 MB ngay khi view đầu tiên vẽ (cấu hình off). App ảnh hưởng qua:
- **Ảnh nền**: +3.5 MB native (bitmap 810×1080 ARGB_8888 giải nguyên ảnh dù chỉ thấy vùng center-crop ~60 %) + 3.34 MB texture GPU (gfxinfo) ⇒ ~7 MB trên máy thật.
- **Bảng emoji**: +2–4 MB (glyph cache màu Skia + atlas 8 MB GPU), **không nhả khi đóng/ẩn**.
- `send-trim-memory` giải phóng 6–8 MB (HWUI purge cache) — nhưng xem #6: IME đang chọn gần như không bao giờ nhận trim.

## Rò rỉ

Kịch bản: 15 lần hiện/ẩn, 4 lần xoay, 3 lần đổi IME (Gboard ↔ VietTelex), `am dumpheap -g`.
- Views/ViewRootImpl/AppContexts **không tăng** qua hiện/ẩn/xoay (27 view) — không rò view.
- **Đổi IME: 4 instance `VietTelexIME` sống sau GC** (mỗi cái giữ KeyboardSession + UserLangModel + view tree nếu đã hiện). `hprof-summary.py --path`:
  - `ROOT[jni-global] ClipboardManager$1 → ClipboardManager → VietTelexIME` ×2 — **lỗi của mình**: `AndroidClipboard` lấy `ClipboardManager` từ context của *service*; binder listener của manager chỉ được thả khi system_server GC proxy. Ép GC system_server (SIGUSR1) thì 2 instance này biến mất ⇒ rò *tạm* (vài giây → vài phút trên máy thật).
  - `ROOT RecordingCanvas pool → RenderNode → KeyButtonView (nav bar IME) → VietTelexIME` ×1 — rò của framework (pool RecordingCanvas giữ nav bar của service cũ), **sống lâu**.

## Khuyến nghị (ưu tiên theo lợi/rủi ro)

| # | Việc | Tiết kiệm ước tính | Rủi ro / công |
|---|---|---|---|
| 1 | **TelexKeyPrior (mặc định BẬT): sinh trie sẵn thành asset mmap** (script generator + test parity với `fromLexicon`), hoặc tối thiểu dựng không qua `Sequence<Pair<String,Int>>`/String/enlexicon copy. Bỏ `TelexKeyPrior.release()` ở onTrimMemory (nhả 0.86 MB nhưng lần hiện sau tốn 31 MB rác + ~0.2–1 s CPU). | Đỉnh Java **−12…24 MB** lúc mở bàn phím lần đầu; −0.86 MB giữ lại (mmap sạch); −31 MB cấp phát mỗi lần dựng | Thấp–TB (asset mới ~1 MB, phải regen khi lexicon đổi) |
| 2 | **Rò service qua ClipboardManager**: `ctx.applicationContext.getSystemService(ClipboardManager)` trong `AndroidClipboard`; trong `onDestroy` bỏ tham chiếu nặng (views, clipPane, session/model → nullable) để vỏ service bị giữ (framework pool) còn nhẹ. Tuỳ chọn: giữ UserLangModel/KeyboardSession ở singleton cấp process (đổi IME qua lại khỏi nạp lại file + 2 bản trong RAM). | Mỗi lần đổi IME: tránh giữ nguyên một bản service (UserLangModel 0.2–1.5 MB + view tree + session) | Thấp (1 dòng + dọn onDestroy) |
| 3 | **FUTO: thôi giải fp16 → FloatArray mỗi lần hiện.** (a) nhả theo hẹn giờ ẩn (#6) thay vì mỗi `onFinishInputView`; hoặc (b) ship weights fp32 không nén, đọc qua `FloatBuffer` mmap (0 heap, trang sạch) — đo lại tốc độ encoder. | −2.5…3.4 MB heap khi bật; −4.7 MB cấp phát mỗi lần hiện (95 MB/20 lần đo được) | (a) thấp; (b) TB (+1.27 MB APK, FloatBuffer chậm hơn FloatArray) |
| 4 | **Ảnh nền**: giải `inPreferredConfig = RGB_565` (JPEG không alpha; paint alpha vẫn chạy) hoặc `Bitmap.Config.HARDWARE` (bỏ bản CPU); cắt đúng vùng center-crop bằng `BitmapRegionDecoder` hoặc lưu sẵn ảnh đã crop theo tỉ lệ bàn phím lúc import. `WallpaperBitmap.drop()` khi ẩn lâu. | −1.7…3.4 MB native (+ tương đương GPU) | Thấp (565 có thể vằn trên ảnh mờ → bật dither) |
| 5 | **App cài đặt cùng process IME**: rẻ — `finish()` MainActivity ở `onStop` (không phải đổi cấu hình) để Compose/HWUI của activity được dọn; triệt để — `android:process=":settings"` (nhưng IME đang dựa `OnSharedPreferenceChangeListener` cùng process ⇒ phải đổi sang cơ chế liên process). | −10…16 MB sau khi user từng mở cài đặt/Luyện vuốt | Rẻ: thấp (mất trạng thái tab khi quay lại); tách process: cao |
| 6 | **onTrimMemory gần như chết**: API 34+ không gửi `TRIM_MEMORY_RUNNING_*`; IME đang chọn ở procState 5 / oom_adj 100 nên cũng không nhận `BACKGROUND`. Thay bằng **hẹn giờ ẩn** (vd 30–60 s sau `onFinishInputView`, huỷ khi hiện lại): nhả FUTO, SwipeEnglish.lexicon, WallpaperBitmap, emoji category strings, ClipboardPane view, templatesCache. Giữ TelexKeyPrior (#1). | 2–7 MB lúc ẩn (tuỳ tính năng) | Thấp |
| 7 | **SwipeEnglish.lexicon** (1.4 MB, không bao giờ nhả): đọc từ tại chỗ trên buffer mmap (so byte ASCII, không String) hoặc holder nhả được (#6). | −1.4 MB khi vuốt EN / gõ EN | TB |
| 8 | **Cấp phát mỗi phím**: `composeTrial` dùng lại một `TelexEngine` scratch mỗi luồng (reset thay vì `TelexEngine()`); `autoShiftFor` duyệt ngược thay vì `trim` copy. | −3 KB/phím (~−45 % trên đường gợi ý) | Thấp (có test engine) |
| 9 | UserLangModel: bảng HashMap<String, Int> boxing (~1.5 MB ở cap) + `snapshot()` copy toàn bảng mỗi lần lưu ⇒ bảng mở-địa-chỉ mảng nguyên thuỷ. | −~1 MB + bớt churn lúc lưu | TB–cao; để sau |

Không cần làm: không có Compose trong view IME (KeyboardView vẽ một canvas, EmojiPane vẽ trực tiếp — không view per emoji); không `largeHeap`; R8 minify + shrinkResources đã bật; SoundPool nhả khi ẩn, mẫu âm nhỏ; không có view leak khi xoay/hiện-ẩn.

## Kinh nghiệm IME khác (đối chiếu)

- AOSP LatinIME / HeliBoard: từ điển nhị phân mmap ở native (không vào Java heap) — VietTelex đã làm tương đương với ByteBuffer mmap; bảng/phím dựng sẵn offline thay vì lúc chạy (chính là #1). Bảng emoji dựng lười.
- FlorisBoard dùng Compose cho cả UI IME — nặng hơn đáng kể; VietTelex đúng hướng khi giữ View/Canvas trong IME (và nên tách Compose của app ra, #5).
- Tài liệu Android: từ API 34 chỉ còn `TRIM_MEMORY_UI_HIDDEN`/`BACKGROUND` được gửi; bitmap pixel ở native heap từ API 26; `HARDWARE` bitmap chỉ ở GPU; `inSampleSize` chỉ lũy thừa 2 — muốn đúng cỡ thì crop/scale khi lưu.
