package com.viettelex.android.ime

import kotlin.math.floor

/**
 * Kích thước lưới emoji (cuộn ngang, column-major) theo vùng lưới — THUẦN, đơn vị dp.
 * Góp ý 27/09/2026: emoji bé, sát nhau, khó bấm ⇒ ô ≥ [MIN_CELL] (vùng chạm HIG/Material),
 * glyph ~ bàn phím emoji iOS gốc (≤ [MAX_GLYPH]), khoảng cách đều (ô chia đều vùng).
 * Hàng: số ô ≥ 44 dp vừa chiều cao (≤ [MAX_ROWS]). Cột: bề ngang chứa đúng n + ½ cột —
 * nửa cột lấp ló báo "cuộn ngang được" như iOS. Pinned by EmojiGridLayoutTest.
 */
object EmojiGridLayout {
    const val MIN_CELL = 44f
    const val MAX_GLYPH = 32f
    const val MAX_ROWS = 5
    /** Glyph ≤ tỉ lệ này của cạnh ô nhỏ hơn (chừa lề giữa các emoji). */
    const val GLYPH_RATIO = 0.74f

    data class Metrics(val rows: Int, val cellW: Float, val cellH: Float, val glyph: Float)

    fun metrics(widthDp: Float, gridHeightDp: Float): Metrics {
        val rows = floor(gridHeightDp / MIN_CELL).toInt().coerceIn(1, MAX_ROWS)
        val cellH = maxOf(gridHeightDp / rows, 1f)
        // n + 0.5 cột trong bề ngang, mỗi cột ≥ MIN_CELL.
        val n = maxOf(1, floor(widthDp / MIN_CELL - 0.5f).toInt())
        val cellW = maxOf(widthDp / (n + 0.5f), MIN_CELL)
        val glyph = minOf(MAX_GLYPH, minOf(cellW, cellH) * GLYPH_RATIO)
        return Metrics(rows, cellW, cellH, glyph)
    }
}
