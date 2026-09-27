package com.viettelex.android.shared

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.L10n

/**
 * Ngôn ngữ giao diện ([Keys.UI_LANGUAGE], mặc định "vi" — không theo máy) nối với Compose:
 * [L10n.onRead] đọc [state] ⇒ mọi composable gọi `tr(…)` tự recompose khi đổi, không cần khởi
 * động lại. Nhập file sao lưu đổi pref ⇒ listener cập nhật ngay. IME đọc lại pref mỗi lần hiện
 * bàn phím ([refreshFromPrefs]).
 */
object UiLang {
    val state = mutableStateOf(L10n.DEFAULT)
    private var listener: SharedPreferences.OnSharedPreferenceChangeListener? = null

    fun install(ctx: Context) {
        val p = VTPrefs.of(ctx)
        L10n.onRead = { state.value }
        refreshFromPrefs(p)
        if (listener == null) {
            val l = SharedPreferences.OnSharedPreferenceChangeListener { sp, k ->
                if (k == Keys.UI_LANGUAGE) refreshFromPrefs(sp)
            }
            listener = l   // giữ tham chiếu mạnh (SharedPreferences chỉ giữ weak)
            p.registerOnSharedPreferenceChangeListener(l)
        }
    }

    /** Đọc pref → [L10n.lang] + [state]. Trả true nếu ngôn ngữ đổi. */
    fun refreshFromPrefs(p: SharedPreferences): Boolean {
        val before = L10n.lang
        val v = L10n.load { p.all[it] }
        if (state.value != v) state.value = v
        return before != v
    }

    fun select(ctx: Context, v: String) {
        val p = VTPrefs.of(ctx)
        val applied = L10n.select(v) { k, value -> p.edit().putString(k, value).apply() }
        state.value = applied
    }
}
