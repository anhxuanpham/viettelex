# VietTelex Plus — sản phẩm cần tạo trên Play Console (NHÁP, chưa tạo)

Code đã sẵn (Google Play Billing 8, `app/src/main/kotlin/com/viettelex/android/plus/`).
ID nằm ở `keyboard/src/main/kotlin/com/viettelex/keyboard/PlusGate.kt` (`PlusConfig`).

Play Console → Monetize → Products → **In-app products** (không phải subscription):

| Product ID | Loại (xử lý trong code) | Giá (VND) | ~USD | Tên (vi / en) |
|---|---|---|---|---|
| `plus` | Mua một lần — acknowledge, KHÔNG consume | 69.000đ | $2.99 | VietTelex Plus |
| `tip_small` | Consumable — consume sau khi mua | 25.000đ | $0.99 | Ly cà phê ☕ / Coffee ☕ |
| `tip_medium` | Consumable | 49.000đ | $1.99 | Bữa trưa 🍜 / Lunch 🍜 |
| `tip_large` | Consumable | 99.000đ | $3.99 | Ủng hộ lớn ❤️ / Big thanks ❤️ |

Mô tả sản phẩm: dùng lại câu ở `iOS/store-drafts/PRODUCTS.md`.

## Các bước chủ repo làm khi muốn bán thật
1. Thiết lập **Payments profile** (merchant) cho tài khoản developer.
2. Upload một bản AAB có Billing (bản này) lên track nội bộ — Play chỉ cho tạo
   in-app product sau khi app đã có quyền BILLING (thư viện tự thêm vào manifest).
3. Tạo 4 sản phẩm trên, **Activate**.
4. Thêm tài khoản test ở Settings → License testing để mua thử không mất tiền.
5. Đổi `PlusConfig.PAYWALL_ENABLED = true` (Android) và `PlusConfig.paywallEnabled = true` (iOS).
   Trước đó mọi tính năng Plus mở miễn phí cho tất cả.
6. Data safety: app không gửi dữ liệu mua về server riêng (Play xử lý thanh toán) —
   kiểm tra lại hướng dẫn Play hiện hành trước khi khai.
