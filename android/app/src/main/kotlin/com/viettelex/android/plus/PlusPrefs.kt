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
}
