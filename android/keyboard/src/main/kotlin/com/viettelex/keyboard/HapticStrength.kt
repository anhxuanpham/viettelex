package com.viettelex.keyboard

/**
 * Độ mạnh rung phím 10…100 % (thanh trượt "Độ mạnh rung", key [Keys.HAPTIC_STRENGTH],
 * mặc định 45 — giống iOS KeyHaptics). Hàm thuần để test: IME đổi % ra
 * VibrationEffect.createOneShot(durationMs, amplitude).
 */
object HapticStrength {
    const val DEFAULT = 45
    val RANGE = 10..100

    fun clamp(percent: Int): Int = percent.coerceIn(RANGE)

    /**
     * Máy có điều chỉnh biên độ: nhịp ngắn cố định-ish, độ mạnh nằm ở biên độ 1…255
     * (10 % ≈ 26, 45 % ≈ 115, 100 % = 255). Nhịp dài thêm chút theo % để 10 % vẫn cảm được.
     */
    fun amplitude(percent: Int): Int = Math.round(clamp(percent) * 255f / 100f).coerceIn(1, 255)
    fun amplitudeDurationMs(percent: Int): Long = 8L + clamp(percent) / 10   // 9…18 ms

    /** Máy KHÔNG điều chỉnh biên độ (motor ERM cũ): độ mạnh = độ dài nhịp, 5…30 ms. */
    fun durationOnlyMs(percent: Int): Long = 5L + Math.round((clamp(percent) - 10) * 25f / 90f)
}
