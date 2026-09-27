package com.viettelex.android.ime

/**
 * Hình học slot thanh gợi ý — THUẦN. 3 slot BẰNG NHAU, cố định theo bề rộng bar (không
 * theo nội dung) ⇒ không "lúc rộng lúc hẹp" như lỗi iOS 27/09/2026. Thẻ Dán thay CẢ bar
 * (StripView không vẽ slot khi thẻ hiện). Pinned by StripGeometryTest.
 */
object StripGeometry {
    /** Mép trái/phải slot i (0..2) trong [barL, barR] → ghi vào [l]/[r]. */
    fun thirds(barL: Float, barR: Float, l: FloatArray, r: FloatArray) {
        val third = (barR - barL) / 3f
        for (i in 0..2) { l[i] = barL + i * third; r[i] = if (i == 2) barR else l[i] + third }
    }
}
