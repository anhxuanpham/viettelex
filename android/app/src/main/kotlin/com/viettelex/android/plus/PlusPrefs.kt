package com.viettelex.android.plus

import android.content.Context
import com.viettelex.android.BuildConfig
import com.viettelex.android.shared.VTPrefs
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.PlusGate

/** Nối [PlusGate] (module :keyboard) với SharedPreferences chung app ↔ IME. */
object PlusPrefs {
    fun install(ctx: Context) {
        val p = VTPrefs.of(ctx)
        // Key của PlusGate đều Boolean — đọc lẻ, tránh p.all (copy cả map).
        PlusGate.install({ k -> if (p.contains(k)) p.getBoolean(k, false) else null }, debugBuild = BuildConfig.DEBUG)
    }

    fun writePurchased(ctx: Context, on: Boolean) {
        VTPrefs.of(ctx).edit().putBoolean(Keys.PLUS_UNLOCKED, on).apply()
    }

    /** Key đánh dấu đã mời bật chip "Thêm dấu" sau khi mua (một lần). */
    const val ADD_TONES_OFFERED = "plusAddTonesOffered"

    /** [com.viettelex.android.plus.PlusOnboarding] trên SharedPreferences chung app ↔ IME. */
    fun onboarding(ctx: Context): PlusOnboarding = object : PlusOnboarding {
        private val p = VTPrefs.of(ctx)
        override fun shouldOfferAddTones() =
            !p.getBoolean(Keys.ADD_TONES_CHIP, false) && !p.getBoolean(ADD_TONES_OFFERED, false)
        override fun markOffered() { p.edit().putBoolean(ADD_TONES_OFFERED, true).apply() }
        override fun enableAddTones() { p.edit().putBoolean(Keys.ADD_TONES_CHIP, true).apply() }
    }
}
