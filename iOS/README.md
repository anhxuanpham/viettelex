# VietTelex iOS

Bàn phím iOS VietTelex, nằm trong repo [ptrinh/viettelex](https://github.com/ptrinh/viettelex).
Engine Telex (`TelexCore`) dùng chung với app macOS qua local path `../TelexCore`:

```
~/ClaudeCode/VietTelex/       # repo public: macOS app + TelexCore + web + iOS + android
~/ClaudeCode/VietTelex/iOS/   # app iOS (cùng repo)
```

Build: `xcodegen generate && xcodebuild -project VietTelex-iOS.xcodeproj -scheme VietTelexApp -destination 'generic/platform=iOS Simulator' build`
Bộ mẫu câu mặc định: `ios-mau-cau.yml` (bundle theo build). Blob emoji: `Scripts/blobify-emojisuggest.py`.

## Test

- **Bộ mặc định** (nhanh, ổn định — chạy mỗi lần sửa):
  `xcodebuild -scheme VietTelexKeyboardTests -destination 'platform=iOS Simulator,name=iPhone 17' test`
- **Bộ chậm** (heldout độ chính xác gõ vuốt/gợi ý, độ trễ, RAM, StoreKit session — dễ làm
  runner bị kill khi máy tải cao nên bộ mặc định bỏ qua bằng `XCTSkip`; vẫn phải PASS khi chạy riêng):
  `xcodebuild -scheme VietTelexKeyboardSlowTests -destination 'platform=iOS Simulator,name=iPhone 17' test`
  hoặc thêm `TEST_RUNNER_VT_SLOW_TESTS=1` trước lệnh bộ mặc định để chạy tất cả. Danh sách ở
  `KeyboardTests/SlowTests.swift` (gọi `try SlowTests.require()`) và scheme trong `project.yml`.
  Bench đường nóng mỗi phím (`KeyboardBenchTests`): thêm `TEST_RUNNER_VT_BENCH_CONFIG=B|C|D`
  và `SWIFT_OPTIMIZATION_LEVEL=-O` để lấy số đo — bảng A/B/C/D ở `docs/ios-app.md`.
- **Android** tương tự: `./gradlew --offline test` (mặc định) · `VT_SLOW_TESTS=1 ./gradlew --offline :keyboard:test` (bộ chậm, `SlowTests.kt`).

Gõ giọng nói: KHÔNG có trên iOS — bàn phím bên thứ ba không được truy cập micro
(Android dùng nút giữ lâu "," để chuyển sang IME giọng nói của hệ thống). Trên iOS
dùng nút micro Đọc chính tả của hệ thống (dưới bàn phím, iPhone không nút Home) hoặc 🌐 về bàn phím Apple.
