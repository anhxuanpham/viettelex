package com.viettelex.keyboard

/**
 * Giao diện hai ngôn ngữ (Tiếng Việt / English) — chọn trong app (Tính Năng → Ngôn ngữ), KHÔNG
 * theo ngôn ngữ máy. Chữ tiếng Việt vừa là nguồn vừa là khoá: `tr("Tính Năng")` trả nguyên văn
 * khi "vi", bản dịch ở [L10nTable.EN] khi "en" (thiếu bản dịch ⇒ giữ tiếng Việt). Khoá có
 * `%s`/`%d` thì định dạng bằng args. Cùng khoá/giá trị pref với iOS (`uiLanguage`).
 *
 * App (Compose) gắn [onRead] đọc một `mutableStateOf` ⇒ mọi composable gọi [tr] tự recompose khi
 * đổi ngôn ngữ. IME đặt [lang] một lần mỗi lần hiện bàn phím — không tốn gì mỗi phím.
 */
object L10n {
    const val VI = "vi"
    const val EN = "en"
    const val DEFAULT = VI
    val supported = setOf(VI, EN)

    @Volatile var lang: String = DEFAULT
        set(v) { field = normalize(v) }

    /** Hook Compose: đọc state để composable đang chạy đăng ký theo dõi ngôn ngữ. */
    @Volatile var onRead: (() -> Unit)? = null

    val isEnglish: Boolean get() { onRead?.invoke(); return lang == EN }

    /** Giá trị pref thô ⇒ "vi"/"en" (null, lạ ⇒ "vi"). KHÔNG nhìn Locale máy. */
    fun normalize(raw: Any?): String = (raw as? String)?.takeIf { it in supported } ?: DEFAULT

    /** Nạp từ kho key-value ([read] = giá trị thô của key, vd `prefs.all[it]`); trả ngôn ngữ đã áp. */
    fun load(read: (String) -> Any?): String { lang = normalize(read(Keys.UI_LANGUAGE)); return lang }

    /** Chọn ngôn ngữ: áp ngay + ghi qua [write] (key, giá trị đã chuẩn hoá). */
    fun select(v: String, write: (String, String) -> Unit): String {
        lang = v
        write(Keys.UI_LANGUAGE, lang)
        return lang
    }

    fun tr(vi: String, vararg args: Any?): String {
        onRead?.invoke()
        val s = if (lang == EN) L10nTable.EN[vi] ?: vi else vi
        return if (args.isEmpty()) s else String.format(java.util.Locale.ROOT, s, *args)
    }

    /** Trang hướng dẫn: /hdsd/ (Việt) hoặc /en/guide/ (English). */
    fun guideUrl(os: String, anchor: String? = null): String {
        val base = if (isEnglish) "https://viettelex.com/en/guide/?os=$os" else "https://viettelex.com/hdsd/?os=$os"
        return if (anchor.isNullOrEmpty()) base else "$base#$anchor"
    }
}

/** Viết tắt của [L10n.tr]. */
fun tr(vi: String, vararg args: Any?): String = L10n.tr(vi, *args)
