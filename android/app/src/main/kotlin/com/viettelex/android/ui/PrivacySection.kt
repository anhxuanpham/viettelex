package com.viettelex.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.tr

/** Tính Năng → "Riêng tư & clipboard": lịch sử clipboard + chế độ ẩn danh. */
@Composable
fun PrivacySection() {
    val ctx = LocalContext.current
    VTSection(header = "Clipboard",
        footer = tr("Lịch sử chỉ ghi khi VietTelex là bàn phím đang chọn. Không có gì rời khỏi máy.")) {
        var history by rememberBoolPref(Keys.CLIPBOARD_HISTORY, Prefs.D.clipboardHistory)
        SettingToggle(tr("Lịch sử clipboard"),
            tr("Nút 📋 trên thanh gợi ý mở 20 mục vừa copy; ghim để giữ lâu. Mục không ghim tự xoá sau 1 giờ (mật khẩu/OTP: 2 phút). Chỉ lưu trên máy, bỏ qua ô mật khẩu."), history) {
            history = it
            // Tắt ⇒ xoá luôn dữ liệu đã lưu (IME cùng process cũng bỏ bản trong RAM).
            if (!it) java.io.File(ctx.filesDir, Keys.CLIPBOARD_FILE).delete()
        }
    }
    VTSection(header = tr("Riêng tư")) {
        var incognito by rememberBoolPref(Keys.INCOGNITO, Prefs.D.incognito)
        SettingToggle(tr("Chế độ ẩn danh"),
            tr("Không học từ mới và không lưu clipboard. Ô nhập của trình duyệt ẩn danh tự bật chế độ này."), incognito) { incognito = it }
    }
}
