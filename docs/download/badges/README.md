# Huy hiệu cửa hàng (store badges)

File gốc tải nguyên trạng từ Apple/Google (28/09/2026) và Microsoft (29/09/2026) — **không sửa** màu, chữ, viền hay tỉ lệ.

| File | Nguồn |
|---|---|
| `app-store-black-vi-vn.svg` | https://toolbox.marketingtools.apple.com/api/badges/download-on-the-app-store/black/vi-vn |
| `app-store-black-en-us.svg` | https://toolbox.marketingtools.apple.com/api/badges/download-on-the-app-store/black/en-us |
| `google-play-vi.png` | https://play.google.com/intl/en_us/badges/static/images/badges/vi_badge_web_generic.png |
| `google-play-en.png` | https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png |
| `ms-store-dark-vi-vn.svg` | https://get.microsoft.com/images/vi%20dark.svg |
| `ms-store-dark-en-us.svg` | https://get.microsoft.com/images/en-us%20dark.svg |

(`tools.applemarketingtools.com` cũ không còn phân giải DNS; Apple chuyển sang `toolbox.marketingtools.apple.com`.)

## Quy định đang áp dụng

- Apple — [App Store Marketing Guidelines](https://developer.apple.com/app-store/marketing/guidelines/),
  [Marketing Resources and Identity Guidelines](https://toolbox.marketingtools.apple.com/):
  dùng huy hiệu đen (bản ưu tiên, có viền xám nên dùng được cả nền tối), bản địa hoá theo ngôn ngữ trang,
  cao ≥ 40 px trên màn hình (trang dùng 48 px), chừa khoảng trống xung quanh, dẫn thẳng tới
  `https://apps.apple.com/app/id6794425455`.
- Google — [Google Play badge guidelines](https://partnermarketinghub.withgoogle.com/brands/google-play/visual-identity/badge-guidelines/),
  [badge generator](https://play.google.com/intl/en_us/badges/): PNG đã có sẵn khoảng trống, không cắt/đổi màu;
  kích thước hiển thị tương đương huy hiệu App Store. **Chỉ hiện khi đã có trang Play công khai** — hiện tại app
  Android chưa lên Play nên trang chỉ ghi “Sắp có trên Google Play”; khi `stable.json` có
  `"android": {"play": "https://play.google.com/store/apps/details?id=com.viettelex.android"}` thì `download.js`
  tự thay bằng huy hiệu này.

- Microsoft — [Microsoft Store badges](https://apps.microsoft.com/badge): huy hiệu tối, bản địa hoá theo trang,
  cao 48 px như các huy hiệu khác, dẫn tới `https://apps.microsoft.com/detail/xp9cbqk2f77356`.

## Biểu tượng nền tảng

Biểu tượng ở danh sách nền tảng là SVG tự vẽ (một màu, `currentColor`), không lấy từ icon font nào.
macOS dùng hình laptop chung chứ không dùng logo Apple (Apple không cho bên thứ ba dùng logo táo);
robot Android dùng theo giấy phép CC BY 3.0 của Google; Tux/Windows là hình giản lược một màu.
