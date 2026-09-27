package com.viettelex.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.KeyAlternates
import com.viettelex.keyboard.Keys
import java.text.Normalizer
import java.util.Locale

// Tab Tính Năng (27/09/2026): trang chính là 8 nhóm (icon + tên + tóm tắt trạng thái), mỗi
// nhóm mở một trang con — thay cho danh sách dài mọi công tắc. Ô tìm kiếm lọc theo tên/từ
// khoá rồi mở đúng trang. KHÔNG đổi key/mặc định: trang con đọc/ghi cùng SharedPreferences.
// Cùng cấu trúc với iOS (App/FeaturePages.swift).

internal const val APPLY_NOTE = "Cài đặt áp dụng ngay lần mở bàn phím kế tiếp."

enum class FeaturePage(val title: String, val glyph: Glyph, val color: Color, val anchor: String, val experimental: Boolean = false) {
    ChinhTa("Chính tả & sửa lỗi", Glyph.Spell, Color(0xFF34C759), "sua-dau"),
    GoiY("Gợi ý & từ điển", Glyph.Bulb, Color(0xFFFF9500), "goi-y"),
    GoVuot("Gõ vuốt", Glyph.Swipe, Color(0xFFAF52DE), "go-vuot", experimental = true),
    GoTat("Gõ tắt & mẫu câu", Glyph.Quote, Color(0xFF30B0C7), "go-tat"),
    Phim("Phím & cử chỉ", Glyph.Keyboard, Color(0xFF8E8E93), "cu-chi"),
    GiaoDien("Giao diện", Glyph.Palette, Color(0xFFFF2D55), "giao-dien"),
    RiengTu("Riêng tư & clipboard", Glyph.Lock, Color(0xFF5856D6), "clipboard"),
    SaoLuu("Sao lưu & đồng bộ", Glyph.Cloud, Color(0xFF007AFF), "sao-luu");

    val guideUrl get() = "https://viettelex.com/hdsd/?os=android#$anchor"

    companion object {
        /** 3 khối như app Cài đặt. */
        val groups = listOf(listOf(ChinhTa, GoiY, GoVuot, GoTat), listOf(Phim, GiaoDien), listOf(RiengTu, SaoLuu))
    }
}

/** Chỉ mục ô tìm kiếm: tên cài đặt + từ khoá → trang chứa nó. */
internal data class FeatureSearchEntry(val title: String, val keywords: String, val page: FeaturePage) {
    companion object {
        val all = listOf(
            FeatureSearchEntry("Tự khôi phục từ tiếng Anh", "english google restore", FeaturePage.ChinhTa),
            FeatureSearchEntry("Kiểm tra chính tả khi gõ", "spell check", FeaturePage.ChinhTa),
            FeatureSearchEntry("Sửa dấu từ đã gõ", "sửa dấu con trỏ backspace", FeaturePage.ChinhTa),
            FeatureSearchEntry("Chọn phím thông minh", "chạm trượt smart touch thử nghiệm", FeaturePage.ChinhTa),
            FeatureSearchEntry("Tự sửa từ gõ sai", "autocorrect sửa lỗi thử nghiệm", FeaturePage.ChinhTa),
            FeatureSearchEntry("Thanh gợi ý", "suggestion học từ", FeaturePage.GoiY),
            FeatureSearchEntry("Chip số", "số tiền tính phép tính number", FeaturePage.GoiY),
            FeatureSearchEntry("Chip “Thêm dấu”", "thêm dấu câu không dấu plus", FeaturePage.GoiY),
            FeatureSearchEntry("Lọc từ nhạy cảm", "tục chửi filter", FeaturePage.GoiY),
            FeatureSearchEntry("Từ điển cá nhân", "dictionary tên riêng thuật ngữ", FeaturePage.GoiY),
            FeatureSearchEntry("Xóa từ đã học", "xoá học reset", FeaturePage.GoiY),
            FeatureSearchEntry("Gõ vuốt", "swipe vuốt thử nghiệm", FeaturePage.GoVuot),
            FeatureSearchEntry("Vuốt từ tiếng Anh", "swipe english", FeaturePage.GoVuot),
            FeatureSearchEntry("Mô hình neural gõ vuốt", "futo neural swipe", FeaturePage.GoVuot),
            FeatureSearchEntry("Luyện vuốt", "practice swipe", FeaturePage.GoVuot),
            FeatureSearchEntry("Gõ tắt", "shortcut viết tắt", FeaturePage.GoTat),
            FeatureSearchEntry("Bảng gõ tắt", "shortcut yaml import export", FeaturePage.GoTat),
            FeatureSearchEntry("Mẫu câu", "template câu soạn sẵn", FeaturePage.GoTat),
            FeatureSearchEntry("Hàng phím số", "number row số", FeaturePage.Phim),
            FeatureSearchEntry("Giữ phím hàng trên để ra số", "số giữ lâu number", FeaturePage.Phim),
            FeatureSearchEntry("Giữ phím ra ký tự đặc biệt", "ký hiệu symbol @ # giữ lâu", FeaturePage.Phim),
            FeatureSearchEntry("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh", "space ngôn ngữ english language", FeaturePage.Phim),
            FeatureSearchEntry("Chế độ một tay", "one hand một tay", FeaturePage.Phim),
            FeatureSearchEntry("Phóng to chữ khi bấm", "key preview popup", FeaturePage.Phim),
            FeatureSearchEntry("Rung phím", "haptic rung vibrate", FeaturePage.Phim),
            FeatureSearchEntry("Telex cho bàn phím cứng", "bluetooth usb dex chromebook hardware", FeaturePage.Phim),
            FeatureSearchEntry("Theme & ảnh nền", "theme màu chủ đề wallpaper hình nền", FeaturePage.GiaoDien),
            FeatureSearchEntry("Độ trong suốt phím", "trong suốt transparent", FeaturePage.GiaoDien),
            FeatureSearchEntry("Độ trong suốt ký tự", "trong suốt transparent chữ", FeaturePage.GiaoDien),
            FeatureSearchEntry("Khôi phục giao diện gốc", "reset mặc định", FeaturePage.GiaoDien),
            FeatureSearchEntry("Chiều cao hàng phím", "height cao thấp", FeaturePage.GiaoDien),
            FeatureSearchEntry("Hiện logo Vᴛ", "logo phím cách", FeaturePage.GiaoDien),
            FeatureSearchEntry("Lịch sử clipboard", "copy dán clipboard", FeaturePage.RiengTu),
            FeatureSearchEntry("Chế độ ẩn danh", "incognito riêng tư", FeaturePage.RiengTu),
            FeatureSearchEntry("Xuất / nhập file sao lưu", "backup export import restore", FeaturePage.SaoLuu),
        )

        /** Bỏ dấu + chữ thường ("trong suot" khớp "trong suốt"). */
        fun fold(s: String): String =
            Normalizer.normalize(s.replace('đ', 'd').replace('Đ', 'D'), Normalizer.Form.NFD)
                .replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)

        fun search(query: String): List<FeatureSearchEntry> {
            val words = fold(query).split(' ').filter { it.isNotBlank() }
            if (words.isEmpty()) return emptyList()
            val pages = FeaturePage.entries.map { FeatureSearchEntry(it.title, "", it) }
            return (pages + all).filter { e -> fold(e.title + " " + e.keywords).let { h -> words.all { h.contains(it) } } }
        }
    }
}

// ---------------------------------------------------------------- khối dùng chung

@Composable
internal fun ExperimentalBadge() {
    Text("Thử nghiệm", style = VTType.caption2.copy(fontWeight = FontWeight.SemiBold), color = Color(0xFFAF52DE),
        modifier = Modifier.background(Color(0xFFAF52DE).copy(alpha = 0.15f), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 1.dp))
}

/** Toggle có nhãn "Thử nghiệm". */
@Composable
internal fun ExperimentalToggle(key: String, default: Boolean, title: String, caption: String) {
    val c = LocalVT.current
    var v by rememberBoolPref(key, default)
    VTRow(onClick = { v = !v }) {
        Column(Modifier.weight(1f).padding(end = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title, style = VTType.body, color = c.label)
                ExperimentalBadge()
            }
            Text(caption, style = VTType.footnote, color = c.secondary)
        }
        IosSwitch(v) { v = it }
    }
}

@Composable
private fun FeatureIcon(p: FeaturePage) {
    Box(Modifier.size(29.dp).background(p.color, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
        GlyphIcon(p.glyph, Color.White, 18.dp)
    }
}

@Composable
private fun FeatureRow(p: FeaturePage, title: String, subtitle: String, badge: Boolean, onClick: () -> Unit) {
    val c = LocalVT.current
    VTRow(onClick = onClick) {
        FeatureIcon(p)
        Column(Modifier.weight(1f).padding(start = 12.dp, end = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title, style = VTType.body, color = c.label)
                if (badge) ExperimentalBadge()
            }
            Text(subtitle, style = VTType.footnote, color = c.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text("›", style = VTType.title3, color = c.tertiary)
    }
}

/** Đầu trang con: "‹ Tính Năng" + tên nhóm. */
@Composable
internal fun SubPageHeader(title: String, onBack: () -> Unit) {
    val c = LocalVT.current
    BackHandler(onBack = onBack)
    VTRow(onClick = onBack) { Text("‹ Tính Năng", style = VTType.body, color = c.accent) }
    Text(title, style = VTType.title2, color = c.label, modifier = Modifier.padding(start = 20.dp, top = 2.dp, bottom = 12.dp))
}

/** Link "Tìm hiểu thêm" cuối mỗi trang con. */
@Composable
internal fun GuideLinkSection(p: FeaturePage) {
    val ctx = LocalContext.current
    VTSection(footer = APPLY_NOTE) {
        LinkRow(Glyph.Info, "Tìm hiểu thêm trong Hướng dẫn") { openUrl(ctx, p.guideUrl) }
    }
}

// ---------------------------------------------------------------- trang chính

@Composable
fun TinhNangTab() {
    var open by rememberSaveable { mutableStateOf<String?>(null) }
    val page = open?.let { n -> FeaturePage.entries.firstOrNull { it.name == n } }
    if (page != null) {
        val back = { open = null }
        when (page) {
            FeaturePage.ChinhTa -> ChinhTaPage(back)
            FeaturePage.GoiY -> GoiYPage(back)
            FeaturePage.GoVuot -> GoVuotPage(back)
            FeaturePage.GoTat -> GoTatPage(back)
            FeaturePage.Phim -> PhimPage(back)
            FeaturePage.GiaoDien -> ThemePage(back)
            FeaturePage.RiengTu -> { SubPageHeader(page.title, back); PrivacySection(); GuideLinkSection(page) }
            FeaturePage.SaoLuu -> { SubPageHeader(page.title, back); SaoLuuSection(); GuideLinkSection(page) }
        }
        return
    }
    FeatureHome { open = it.name }
}

@Composable
private fun FeatureHome(onOpen: (FeaturePage) -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var query by rememberSaveable { mutableStateOf("") }

    val autoRestore by rememberBoolPref(Keys.AUTO_RESTORE, Prefs.D.autoRestore)
    val liveSpell by rememberBoolPref(Keys.LIVE_SPELL_CHECK, Prefs.D.liveSpellCheck)
    val reEdit by rememberBoolPref(Keys.RE_EDIT_WORDS, Prefs.D.reEditWords)
    val autoCorrect by rememberBoolPref(Keys.AUTO_CORRECT, Prefs.D.autoCorrect)
    val suggestions by rememberBoolPref(Keys.SHOW_SUGGESTIONS, Prefs.D.showSuggestions)
    val numberChips by rememberBoolPref(Keys.NUMBER_CHIPS, Prefs.D.numberChips)
    val addTones by rememberBoolPref(Keys.ADD_TONES_CHIP, Prefs.D.addTonesChip)
    val swipe by rememberBoolPref(Keys.SWIPE_TYPING, Prefs.D.swipeTyping)
    val swipeEn by rememberBoolPref(Keys.SWIPE_ENGLISH, Prefs.D.swipeEnglish)
    val swipeFuto by rememberBoolPref(Keys.SWIPE_FUTO, Prefs.D.swipeFuto)
    val shortcutsOn by rememberBoolPref(Keys.SHORTCUTS_ENABLED, Prefs.D.shortcutsEnabled)
    val templatesOn by rememberBoolPref(Keys.TEMPLATES_ENABLED, Prefs.D.templatesEnabled)
    val numberRow by rememberBoolPref(Keys.NUMBER_ROW, Prefs.D.numberRow)
    val spaceSwipe by rememberBoolPref(Keys.SPACE_SWIPE_LANGUAGE, Prefs.D.spaceSwipeLanguage)
    val haptic by rememberBoolPref(Keys.HAPTIC_FEEDBACK, Prefs.D.hapticFeedback)
    val oneHand by rememberStringPref(Keys.ONE_HAND_MODE, Prefs.D.oneHandMode)
    val hardware by rememberBoolPref(Keys.HARDWARE_TELEX, Prefs.D.hardwareTelex)
    val clipHistory by rememberBoolPref(Keys.CLIPBOARD_HISTORY, Prefs.D.clipboardHistory)
    val incognito by rememberBoolPref(Keys.INCOGNITO, Prefs.D.incognito)
    val shortcutCount = remember { ShortcutsStore.load(ctx).size }
    val theme = remember { loadThemeSettings(ctx) }
    val wallpaperOn = remember { theme.wallpaperActive(WallpaperStore.file(ctx).exists()) }

    fun join(vararg parts: Pair<Boolean, String>, none: String) =
        parts.filter { it.first }.joinToString(" · ") { it.second }.ifEmpty { none }

    fun summary(p: FeaturePage): String = when (p) {
        FeaturePage.ChinhTa -> join(autoRestore to "Khôi phục tiếng Anh", liveSpell to "Kiểm tra chính tả",
            reEdit to "Sửa dấu", autoCorrect to "Tự sửa", none = "Đang tắt")
        FeaturePage.GoiY -> if (!suggestions) "Tắt thanh gợi ý"
            else join(true to "Thanh gợi ý", numberChips to "Chip số", addTones to "Thêm dấu", none = "")
        FeaturePage.GoVuot -> if (!swipe) "Đang tắt" else join(true to "Bật", swipeEn to "Tiếng Anh", swipeFuto to "Neural", none = "")
        FeaturePage.GoTat -> (if (!shortcutsOn) "Gõ tắt tắt" else if (shortcutCount == 0) "Gõ tắt bật" else "Gõ tắt: $shortcutCount mục") +
            " · Mẫu câu " + if (templatesOn) "bật" else "tắt"
        FeaturePage.Phim -> join(numberRow to "Hàng số", spaceSwipe to "Vuốt phím cách", haptic to "Rung",
            (oneHand != "off") to "Một tay", hardware to "Bàn phím cứng", none = "Mặc định")
        FeaturePage.GiaoDien -> theme.effectiveTheme.title + (if (wallpaperOn) " · Ảnh nền" else "") +
            if (theme.keyboardTransparency > 0 || theme.labelTransparency > 0) " · Trong suốt" else ""
        FeaturePage.RiengTu -> "Lịch sử clipboard " + (if (clipHistory) "bật" else "tắt") + if (incognito) " · Ẩn danh" else ""
        FeaturePage.SaoLuu -> "Xuất / nhập file"
    }

    VTSection {
        VTRow {
            GlyphIcon(Glyph.Search, c.secondary, 18.dp)
            Box(Modifier.weight(1f).padding(start = 10.dp)) {
                VTTextField(query, { query = it }, "Tìm cài đặt…", capitalization = KeyboardCapitalization.None)
            }
            if (query.isNotEmpty()) {
                Text("✕", style = VTType.body, color = c.tertiary,
                    modifier = Modifier.clickable { query = "" }.padding(start = 8.dp))
            }
        }
    }

    if (query.isBlank()) {
        FeaturePage.groups.forEach { group ->
            VTSection {
                group.forEachIndexed { i, p ->
                    if (i > 0) RowDivider(57.dp)
                    FeatureRow(p, p.title, summary(p), p.experimental) { onOpen(p) }
                }
            }
        }
    } else {
        val hits = FeatureSearchEntry.search(query)
        VTSection(header = "Kết quả") {
            if (hits.isEmpty()) VTRow { Text("Không tìm thấy cài đặt nào.", style = VTType.body, color = c.secondary) }
            hits.forEachIndexed { i, e ->
                if (i > 0) RowDivider(57.dp)
                val isPage = e.title == e.page.title
                FeatureRow(e.page, e.title, if (isPage) summary(e.page) else e.page.title, isPage && e.page.experimental) { onOpen(e.page) }
            }
        }
    }
}

// ---------------------------------------------------------------- trang con

@Composable
private fun ChinhTaPage(onBack: () -> Unit) {
    SubPageHeader(FeaturePage.ChinhTa.title, onBack)
    VTSection(header = "Chính tả") {
        BoolToggle(Keys.AUTO_RESTORE, Prefs.D.autoRestore, "Tự khôi phục từ tiếng Anh", "Từ không phải tiếng Việt trả về như đã gõ (google, github…).")
        RowDivider()
        BoolToggle(Keys.LIVE_SPELL_CHECK, Prefs.D.liveSpellCheck, "Kiểm tra chính tả khi gõ", "Ngừng bỏ dấu khi từ không thể là tiếng Việt.")
        RowDivider()
        BoolToggle(Keys.RE_EDIT_WORDS, Prefs.D.reEditWords, "Sửa dấu từ đã gõ", "⌫ ngay sau dấu cách để sửa tiếp từ vừa gõ (tháy ␣ ⌫ a → thấy), hoặc đặt con trỏ sau từ rồi gõ phím dấu: chao + f → chào.")
    }
    VTSection(header = "Chạm trượt", footer = "Gợi ý sửa lỗi chạm trượt (hiện trên thanh gợi ý) nằm ở tab Kiểu Gõ.") {
        ExperimentalToggle(Keys.SMART_TOUCH, Prefs.D.smartTouch, "Chọn phím thông minh",
            "Chạm sát mép giữa hai phím thì chọn phím hợp với chữ đang gõ. Chạm giữa phím luôn ra đúng phím đó.")
        RowDivider()
        ExperimentalToggle(Keys.AUTO_CORRECT, Prefs.D.autoCorrect, "Tự sửa từ gõ sai",
            "Khi gõ dấu cách, sửa từ lỡ chạm phím kề (tpoi → tôi) nếu chắc chắn. ⌫ ngay sau đó để trả lại chữ gốc.")
    }
    GuideLinkSection(FeaturePage.ChinhTa)
}

@Composable
private fun GoiYPage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    SubPageHeader(FeaturePage.GoiY.title, onBack)
    VTSection(header = "Thanh gợi ý") {
        BoolToggle(Keys.SHOW_SUGGESTIONS, Prefs.D.showSuggestions, "Thanh gợi ý", "Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy).")
        RowDivider()
        BoolToggle(Keys.NUMBER_CHIPS, Prefs.D.numberChips, "Chip số", "Đọc số thành chữ, định dạng tiền, tính nhanh (12*3 → 36).")
        RowDivider()
        BoolToggle(Keys.ADD_TONES_CHIP, Prefs.D.addTonesChip, "Chip “Thêm dấu”",
            "Câu vừa gõ không dấu → một chạm thêm dấu cả câu (hom nay troi dep → hôm nay trời đẹp). Tắt mặc định cho nhẹ máy.")
        RowDivider()
        BoolToggle(Keys.FILTER_SENSITIVE, Prefs.D.filterSensitive, "Lọc từ nhạy cảm", "Không chủ động gợi ý từ tục — gõ tay vẫn bình thường.")
    }
    VTSection(header = "Từ đã học") {
        var showDict by remember { mutableStateOf(false) }
        VTRow(onClick = { showDict = true }) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Từ điển cá nhân", style = VTType.body, color = c.label)
                Text("Xem, tìm, xoá từ đã học; thêm tên riêng.", style = VTType.footnote, color = c.secondary)
            }
            Text("›", style = VTType.title3, color = c.tertiary)
        }
        if (showDict) UserDictDialog { showDict = false }
        RowDivider()
        VTRow(onClick = {
            java.io.File(ctx.filesDir, Keys.USERLM_FILE).delete()
            // IME (cùng process) thấy mốc đổi ⇒ bỏ model trong RAM, seed lại, không ghi đè.
            Prefs.of(ctx).edit().putLong(Keys.USERLM_RESET_AT, System.currentTimeMillis()).apply()
        }) { Text("Xóa từ đã học", style = VTType.body, color = c.red) }
    }
    GuideLinkSection(FeaturePage.GoiY)
}

@Composable
private fun GoVuotPage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    SubPageHeader(FeaturePage.GoVuot.title, onBack)
    val swipeOn by rememberBoolPref(Keys.SWIPE_TYPING, Prefs.D.swipeTyping)
    VTSection(footer = "Tự tắt khi bật TalkBack và ở ô mật khẩu, email, địa chỉ web.") {
        ExperimentalToggle(Keys.SWIPE_TYPING, Prefs.D.swipeTyping, "Gõ vuốt",
            "Lướt qua các chữ không dấu rồi nhấc tay: viet → việt. Gõ phím dấu ngay sau để đổi dấu, ⌫ xoá cả từ.")
        if (swipeOn) {
            RowDivider()
            BoolToggle(Keys.SWIPE_ENGLISH, Prefs.D.swipeEnglish, "Vuốt từ tiếng Anh",
                "check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý.")
            RowDivider()
            BoolToggle(Keys.SWIPE_FUTO, Prefs.D.swipeFuto, "Mô hình neural gõ vuốt",
                "Mạng neural chạy hoàn toàn trên máy, chấm cùng bộ giải mã. Tốn thêm ~3 MB bộ nhớ.")
            // Ghi công BẮT BUỘC theo FUTO Model Weights License 1.0 ("visible notice … within
            // the product's settings") — Phil 27/09/2026: chỉ hiện ở đây (dưới công tắc, khi đã
            // bật Gõ vuốt), chữ nhỏ mờ. KHÔNG xoá. Xem docs/DATA-SOURCES.md.
            VTRow(onClick = { openUrl(ctx, "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md#futo-swipe") }) {
                Text("powered by FUTO Swipe", style = VTType.caption2, color = c.tertiary)
            }
        }
    }
    if (swipeOn) {
        VTSection {
            var showPractice by remember { mutableStateOf(false) }
            VTRow(onClick = { showPractice = true }) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Luyện vuốt", style = VTType.body, color = c.label)
                    Text("Vuốt thử từng từ, xem bàn phím đọc đúng bao nhiêu.", style = VTType.footnote, color = c.secondary)
                }
                Text("›", style = VTType.title3, color = c.tertiary)
            }
            if (showPractice) SwipePracticeDialog { showPractice = false }
        }
    }
    GuideLinkSection(FeaturePage.GoVuot)
}

@Composable
private fun GoTatPage(onBack: () -> Unit) {
    // Trang con "Bảng gõ tắt" (như NavigationLink iOS) — ⟵ hệ thống quay lại.
    var showShortcuts by rememberSaveable { mutableStateOf(false) }
    if (showShortcuts) { ShortcutsPage { showShortcuts = false }; return }
    SubPageHeader(FeaturePage.GoTat.title, onBack)
    ShortcutsSection { showShortcuts = true }
    VTSection(header = "Mẫu câu") {
        BoolToggle(Keys.TEMPLATES_ENABLED, Prefs.D.templatesEnabled, "Mẫu câu", "Nút ☰ trên bàn phím chèn câu soạn sẵn — quản lý ở tab Mẫu Câu.")
    }
    GuideLinkSection(FeaturePage.GoTat)
}

@Composable
private fun PhimPage(onBack: () -> Unit) {
    SubPageHeader(FeaturePage.Phim.title, onBack)
    val numberRow by rememberBoolPref(Keys.NUMBER_ROW, Prefs.D.numberRow)
    VTSection(header = "Phím") {
        BoolToggle(Keys.NUMBER_ROW, Prefs.D.numberRow, "Hàng phím số", "Thêm hàng 1 … 0 trên hàng chữ (bàn phím cao thêm ~¾ hàng).")
        RowDivider()
        // Hàng số bật ⇒ giữ q…p ra số vô nghĩa (KeyAlternates.numbersSettingVisible).
        if (KeyAlternates.numbersSettingVisible(numberRow)) {
            BoolToggle(Keys.LONG_PRESS_NUMBERS, Prefs.D.longPressNumbers, "Giữ phím hàng trên để ra số", "Giữ q … p để gõ 1 … 0 (số nhỏ ở góc phím).")
            RowDivider()
        }
        BoolToggle(Keys.LONG_PRESS_SYMBOLS, Prefs.D.longPressSymbols, "Giữ phím hàng 2, 3 để ra ký tự đặc biệt",
            "Giữ a … l, z … m để gõ @ # \$ _ & - + ( ) … Giữ , để ra dấu chấm (nếu , chưa dùng cho giọng nói).")
    }
    VTSection(header = "Cử chỉ") {
        BoolToggle(Keys.SPACE_SWIPE_LANGUAGE, Prefs.D.spaceSwipeLanguage, "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh",
            "Vuốt nhanh phím cách sang trái/phải. Tiếng Anh gõ nguyên văn, logo thành E. Giữ rồi kéo vẫn là di con trỏ.")
        RowDivider()
        OneHandRow()
    }
    VTSection(header = "Phản hồi khi chạm") {
        BoolToggle(Keys.KEY_PREVIEW, Prefs.D.keyPreview, "Phóng to chữ khi bấm", "Ô chữ lớn nổi trên phím vừa chạm. Tắt nếu thấy rối mắt.")
        RowDivider()
        BoolToggle(Keys.HAPTIC_FEEDBACK, Prefs.D.hapticFeedback, "Rung phím", "Rung nhẹ mỗi lần chạm phím.")
    }
    VTSection(header = "Bàn phím cứng") {
        BoolToggle(Keys.HARDWARE_TELEX, Prefs.D.hardwareTelex, "Telex cho bàn phím cứng",
            "Gõ Telex/VNI bằng bàn phím Bluetooth/USB, Samsung DeX, Chromebook. Phím tắt Ctrl/Alt vẫn tới app. Bàn phím ảo tự ẩn khi có bàn phím cứng (bật lại: Cài đặt hệ thống → Bàn phím vật lý → Hiện bàn phím ảo).")
    }
    GuideLinkSection(FeaturePage.Phim)
}
