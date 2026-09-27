# VietTelex Plus — sản phẩm cần tạo trên App Store Connect (NHÁP, chưa tạo)

Code đã sẵn (StoreKit 2, `iOS/App/Plus/`). ID nằm ở `iOS/Shared/PlusConfig.swift`
và `iOS/StoreKit/VietTelex.storekit` — đổi thì đổi cả hai.

| Product ID | Loại | Giá (bậc gần nhất) | Tên hiển thị (vi / en) |
|---|---|---|---|
| `com.viettelex.ios.plus` | Non-Consumable | 69.000đ (~US$2.99) | VietTelex Plus / VietTelex Plus |
| `com.viettelex.ios.tip.small` | Consumable | 25.000đ (~US$0.99) | Ly cà phê ☕ / Coffee ☕ |
| `com.viettelex.ios.tip.medium` | Consumable | 49.000đ (~US$1.99) | Bữa trưa 🍜 / Lunch 🍜 |
| `com.viettelex.ios.tip.large` | Consumable | 99.000đ (~US$3.99) | Ủng hộ lớn ❤️ / Big thanks ❤️ |

- Plus: bật **Family Sharing** (tuỳ chọn, file .storekit đang để bật).
- Mô tả IAP (vi): "Mở khoá VietTelex Plus vĩnh viễn: theme cao cấp, thêm dấu cả câu, clipboard nâng cao, đồng bộ iCloud, công cụ văn bản."
  (en): "Unlock VietTelex Plus forever: premium themes, whole-sentence diacritics, advanced clipboard, iCloud sync, text tools."
- Tip (vi): "Ủng hộ tác giả — không mở khoá thêm tính năng." (en): "Support the developer — does not unlock features."
- Cần ảnh chụp màn hình Plus cho review (Debug có công tắc "Giả lập đã mua Plus").

## Các bước chủ repo làm khi muốn bán thật
1. Ký **Paid Applications Agreement** + thông tin thuế/ngân hàng trong App Store Connect.
2. Tạo 4 sản phẩm trên (App → Monetization → In-App Purchases), gửi kèm bản build.
3. Đổi `PlusConfig.paywallEnabled = true` (iOS) và `PlusConfig.PAYWALL_ENABLED = true` (Android).
   Trước đó mọi tính năng Plus mở miễn phí cho tất cả.
4. Capability In-App Purchase: StoreKit 2 không cần entitlement riêng; nếu Xcode
   nhắc thì bật trong Signing & Capabilities của target VietTelexApp.
5. App Privacy: không đổi (mua qua Apple, app không nhận dữ liệu thanh toán).
6. Test cục bộ: scheme **VietTelexApp** đã gắn `StoreKit/VietTelex.storekit` → chạy trên
   simulator là mua thử được, không cần sản phẩm thật.
