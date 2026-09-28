package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Góp ý 27/09/2026: emoji bé, sát nhau, khó bấm. */
class EmojiGridLayoutTest {
    /** Vùng lưới thật: keyArea 218 dp − thanh tìm (218/5) − hàng category ≈ 136 dp. */
    @Test fun phonePortraitCellsAtLeast44() {
        val m = EmojiGridLayout.metrics(411f, 136f)
        assertEquals(3, m.rows)
        assertTrue(m.cellW >= 44f && m.cellH >= 44f)
        assertTrue(m.glyph in 30f..32f)                  // ~ glyph iOS gốc
        // n + ½ cột vừa đúng bề ngang (nửa cột báo cuộn được).
        val cols = 411f / m.cellW
        assertEquals(0.5f, cols - cols.toInt(), 0.001f)
    }

    @Test fun everyWidthKeepsMinimumTarget() {
        for (w in 280..1400 step 7) for (h in 44..300 step 11) {
            val m = EmojiGridLayout.metrics(w.toFloat(), h.toFloat())
            assertTrue("w=$w h=$h", m.cellW >= 44f)
            assertTrue("w=$w h=$h", m.cellH >= 44f)
            assertTrue(m.rows in 1..EmojiGridLayout.MAX_ROWS)
            assertTrue(m.glyph <= EmojiGridLayout.MAX_GLYPH && m.glyph < minOf(m.cellW, m.cellH))
        }
    }

    @Test fun tallAreaCapsRows() {
        val m = EmojiGridLayout.metrics(800f, 400f)
        assertEquals(5, m.rows)
        assertEquals(80f, m.cellH, 0.001f)
        assertEquals(32f, m.glyph, 0.001f)
    }

    /**
     * Đo emulator 28/09/2026 (Pixel 6 411 dp + chế độ tablet 800 dp): Gboard vẽ emoji
     * cao ≈ 31 dp, bước 45.7 × 44.8 dp (9 cột). Mình ≈ 35 dp (điện thoại) / 34 dp
     * (tablet) — KHÔNG được bé hơn Gboard: glyph phải chạm trần [MAX_GLYPH] ở mọi lưới thật.
     */
    @Test fun glyphNeverSmallerThanGboard() {
        for ((w, h) in listOf(411f to 136f, 411f to 170f, 800f to 220f, 915f to 120f, 1280f to 260f)) {
            val m = EmojiGridLayout.metrics(w, h)
            assertEquals("w=$w h=$h", EmojiGridLayout.MAX_GLYPH, m.glyph, 0.001f)
        }
    }
}
