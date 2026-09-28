package com.viettelex.android.ime

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.viettelex.keyboard.HapticStrength

/**
 * Rung một nhịp theo độ mạnh % — dùng chung IME ([Feedback]) và app (rung thử khi kéo "Độ
 * mạnh rung"). Chọn hiệu ứng rẻ pin nhất theo [HapticStrength.plan] (primitive TICK/CLICK có
 * scale → one-shot ngắn có biên độ → predefined → one-shot theo độ dài). VibrationEffect dựng
 * sẵn cho mỗi độ mạnh (không cấp phát mỗi phím); Vibrator lấy lười lần đầu.
 */
class KeyVibrator(ctx: Context) {
    private val appCtx = ctx.applicationContext
    private var loaded = false
    private var vibrator: Vibrator? = null
    private var primitives = false
    private val cache = HashMap<Int, VibrationEffect>(4)

    fun vib(): Vibrator? {
        if (!loaded) {
            loaded = true
            vibrator = runCatching {
                if (Build.VERSION.SDK_INT >= 31)
                    (appCtx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
                else @Suppress("DEPRECATION") (appCtx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
            }.getOrNull()?.takeIf { it.hasVibrator() }
            primitives = vibrator?.let { v ->
                Build.VERSION.SDK_INT >= 30 && runCatching {
                    v.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK,
                        VibrationEffect.Composition.PRIMITIVE_CLICK)
                }.getOrDefault(false)
            } ?: false
        }
        return vibrator
    }

    fun plan(percent: Int): HapticStrength.Plan? {
        val v = vib() ?: return null
        return HapticStrength.plan(percent, Build.VERSION.SDK_INT, primitives, v.hasAmplitudeControl())
    }

    private fun build(p: HapticStrength.Plan): VibrationEffect = when (p) {
        is HapticStrength.Plan.Primitive -> if (Build.VERSION.SDK_INT >= 30)
            VibrationEffect.startComposition().addPrimitive(
                if (p.tick) VibrationEffect.Composition.PRIMITIVE_TICK else VibrationEffect.Composition.PRIMITIVE_CLICK,
                p.scale).compose()
            else VibrationEffect.createOneShot(10, VibrationEffect.DEFAULT_AMPLITUDE)
        is HapticStrength.Plan.OneShot -> VibrationEffect.createOneShot(p.ms,
            if (p.amplitude < 0) VibrationEffect.DEFAULT_AMPLITUDE else p.amplitude)
        is HapticStrength.Plan.Predefined -> if (Build.VERSION.SDK_INT >= 29) VibrationEffect.createPredefined(when (p.effect) {
                HapticStrength.Predef.TICK -> VibrationEffect.EFFECT_TICK
                HapticStrength.Predef.CLICK -> VibrationEffect.EFFECT_CLICK
                HapticStrength.Predef.HEAVY_CLICK -> VibrationEffect.EFFECT_HEAVY_CLICK
            }) else VibrationEffect.createOneShot(10, VibrationEffect.DEFAULT_AMPLITUDE)
    }

    /** false ⇒ máy không có Vibrator (gọi view.performHapticFeedback thay). */
    fun vibrate(percent: Int): Boolean {
        val v = vib() ?: return false
        val pct = HapticStrength.clamp(percent)
        val e = cache[pct] ?: plan(pct)?.let(::build)?.also { if (cache.size > 8) cache.clear(); cache[pct] = it } ?: return false
        return runCatching { v.vibrate(e) }.isSuccess
    }

    fun clear() = cache.clear()
}
