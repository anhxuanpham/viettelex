package com.viettelex.android.ime

import com.viettelex.keyboard.BarLayout
import com.viettelex.keyboard.SuggestionSet
import com.viettelex.keyboard.SuggestionSlots
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** Lỗi iOS 27/09/2026: thẻ Dán vẽ chồng chữ gợi ý, slot đổi bề rộng theo nội dung. */
class StripGeometryTest {
    @Test fun threeEqualContiguousSlots() {
        val l = FloatArray(3); val r = FloatArray(3)
        StripGeometry.thirds(100f, 400f, l, r)
        assertEquals(100f, l[0]); assertEquals(400f, r[2])
        for (i in 0..2) assertEquals(100f, r[i] - l[i], 0.001f)
        assertEquals(r[0], l[1]); assertEquals(r[1], l[2])
    }

    @Test fun pasteCardReplacesWholeBar() {
        // Có chữ gợi ý + thẻ Dán ⇒ chỉ thẻ Dán (không slot nào vẽ chồng).
        val set = SuggestionSet(literal = "xin", word = "xin", word2 = "xinh", paste = true)
        assertSame(BarLayout.PasteCard, SuggestionSlots.arrange(set, undoAsPill = true, bestInMiddle = true))
    }
}
