package com.viettelex.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.viettelex.keyboard.Keys

/** Tính Năng → "Riêng tư & clipboard": lịch sử clipboard + chế độ ẩn danh. */
@Composable
fun PrivacySection() {
    val ctx = LocalContext.current
    VTSection(header = "Clipboard",
        footer = "Lịch sử chỉ ghi khi VietTelex là bàn phím đang chọn. Không có gì rời khỏi máy.") {
        var history by rememberBoolPref(Keys.CLIPBOARD_HISTORY, Prefs.D.clipboardHistory)
        SettingToggle("Lịch sử clipboard",
            "Nút 📋 trên thanh gợi ý mở 20 mục vừa copy; ghim để giữ lâu. Mục không ghim tự xoá sau 1 giờ " +
                "(mật khẩu/OTP: 2 phút). Chỉ lưu trên máy, bỏ qua ô mật khẩu.", history) {
            history = it
            // Tắt ⇒ xoá luôn dữ liệu đã lưu (IME cùng process cũng bỏ bản trong RAM).
            if (!it) java.io.File(ctx.filesDir, Keys.CLIPBOARD_FILE).delete()
        }
    }
    VTSection(header = "Riêng tư") {
        var incognito by rememberBoolPref(Keys.INCOGNITO, Prefs.D.incognito)
        SettingToggle("Chế độ ẩn danh",
            "Không học từ mới và không lưu clipboard. Ô nhập của trình duyệt ẩn danh tự bật chế độ này.", incognito) { incognito = it }
    }
}
