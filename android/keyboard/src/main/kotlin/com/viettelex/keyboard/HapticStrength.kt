package com.viettelex.keyboard

/**
 * Độ mạnh rung phím 10…100 % (thanh trượt "Độ mạnh rung", key [Keys.HAPTIC_STRENGTH],
 * mặc định 45 — giống iOS KeyHaptics). Hàm thuần để test: IME đổi % ra VibrationEffect theo
 * [plan].
 *
 * PIN (Phil 28/09 "chọn kiểu rung subtle nào mà đỡ tốn pin nhất"). Năng lượng motor ≈ tỉ lệ
 * biên độ² × thời gian kéo; ưu tiên hiệu ứng NGẮN NHẤT hệ thống tinh chỉnh sẵn:
 *  1. API 30+ và máy hỗ trợ primitive: Composition PRIMITIVE_TICK (≤ 70 %) / PRIMITIVE_CLICK
 *     (> 70 %) có scale — HAL phát dạng sóng đã tối ưu (tick ≈ 5–10 ms, có hãm chủ động),
 *     rẻ nhất mà vẫn chỉnh được độ mạnh. 45 % = TICK scale ≈ 0.71 (nhịp "tách" nhẹ).
 *  2. Có điều chỉnh biên độ (không primitive): one-shot ngắn 7…16 ms, biên độ 26…255
 *     (45 % ≈ 10 ms × 115 ⇒ ~20 % năng lượng nhịp 100 %).
 *  3. API 29+ không điều chỉnh biên độ (motor ERM cũ): createPredefined EFFECT_TICK
 *     (≤ 55 %) / EFFECT_CLICK (≤ 85 %) / EFFECT_HEAVY_CLICK — OEM tinh chỉnh sẵn.
 *  4. Còn lại: one-shot chỉ theo độ dài 5…30 ms.
 */
object HapticStrength {
    const val DEFAULT = 45
    val RANGE = 10..100

    fun clamp(percent: Int): Int = percent.coerceIn(RANGE)

    /** Máy có điều chỉnh biên độ: biên độ 1…255 (10 % ≈ 26, 45 % ≈ 115, 100 % = 255). */
    fun amplitude(percent: Int): Int = Math.round(clamp(percent) * 255f / 100f).coerceIn(1, 255)
    /** Nhịp one-shot ngắn nhất còn cảm được (LRA cần ~1 chu kỳ cộng hưởng ≈ 6 ms): 7…16 ms. */
    fun amplitudeDurationMs(percent: Int): Long = 6L + clamp(percent) / 10

    /** Máy KHÔNG điều chỉnh biên độ (motor ERM cũ): độ mạnh = độ dài nhịp, 5…30 ms. */
    fun durationOnlyMs(percent: Int): Long = 5L + Math.round((clamp(percent) - 10) * 25f / 90f)

    enum class Predef { TICK, CLICK, HEAVY_CLICK }

    sealed class Plan {
        /** VibrationEffect.Composition: PRIMITIVE_TICK (tick = true) / PRIMITIVE_CLICK, scale 0…1. */
        data class Primitive(val tick: Boolean, val scale: Float) : Plan()
        /** createOneShot(ms, amplitude); amplitude = -1 ⇒ DEFAULT_AMPLITUDE. */
        data class OneShot(val ms: Long, val amplitude: Int) : Plan()
        data class Predefined(val effect: Predef) : Plan()
    }

    fun primitiveScale(percent: Int): Pair<Boolean, Float> {
        val p = clamp(percent)
        return if (p <= 70) true to (0.3f + 0.7f * (p - 10) / 60f)
        else false to (0.4f + 0.6f * (p - 70) / 30f)
    }

    fun plan(percent: Int, sdk: Int, primitivesSupported: Boolean, amplitudeControl: Boolean): Plan {
        val p = clamp(percent)
        return when {
            sdk >= 30 && primitivesSupported -> primitiveScale(p).let { (t, s) -> Plan.Primitive(t, s) }
            amplitudeControl -> Plan.OneShot(amplitudeDurationMs(p), amplitude(p))
            sdk >= 29 -> Plan.Predefined(when { p <= 55 -> Predef.TICK; p <= 85 -> Predef.CLICK; else -> Predef.HEAVY_CLICK })
            else -> Plan.OneShot(durationOnlyMs(p), -1)
        }
    }
}
