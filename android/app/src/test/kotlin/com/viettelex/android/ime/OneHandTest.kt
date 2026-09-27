package com.viettelex.android.ime

import com.viettelex.keyboard.SwipeLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Chế độ một tay (27/09/2026): hình học phím thu hẹp + dời, router, tâm gõ vuốt, rail. */
class OneHandTest {
    private val d = 1f
    private val W = 390f
    private val H = KeyLayout.keyAreaDp(false, false, 0)

    private fun build(plane: Plane, side: OneHandSide, numberRow: Boolean = false) =
        KeyLayout.build(LayoutConfig(plane, W, if (numberRow) KeyLayout.keyAreaDp(false, false, 0, true) else H, d,
            numberRow = numberRow, oneHand = side))

    private fun near(a: Float, b: Float, eps: Float = 0.01f) = assertEquals(b, a, eps)

    @Test fun spanAndRail() {
        near(OneHand.span(W, OneHandSide.OFF).second, W)
        val (l0, lw) = OneHand.span(W, OneHandSide.LEFT)
        near(l0, 0f); near(lw, W * OneHand.RATIO)
        val (r0, rw) = OneHand.span(W, OneHandSide.RIGHT)
        near(r0, W - W * OneHand.RATIO); near(r0 + rw, W)
        assertNull(OneHand.rail(W, OneHandSide.OFF))
        assertEquals(lw to W, OneHand.rail(W, OneHandSide.LEFT))
        assertEquals(0f to r0, OneHand.rail(W, OneHandSide.RIGHT))
        // Nút rail: nửa trên đổi bên, nửa dưới thoát; ngoài rail = -1.
        assertEquals(0, OneHand.railButton(W, H, OneHandSide.RIGHT, 10f, 20f))
        assertEquals(1, OneHand.railButton(W, H, OneHandSide.RIGHT, 10f, H - 5f))
        assertEquals(-1, OneHand.railButton(W, H, OneHandSide.RIGHT, W / 2, 20f))
        assertEquals(0, OneHand.railButton(W, H, OneHandSide.LEFT, W - 5f, 5f))
    }

    @Test fun togglesAndPrefs() {
        assertEquals(OneHandSide.RIGHT, OneHand.switched(OneHandSide.LEFT))
        assertEquals(OneHandSide.LEFT, OneHand.switched(OneHandSide.RIGHT))
        assertEquals(OneHandSide.RIGHT, OneHand.toggled(OneHandSide.OFF))
        assertEquals(OneHandSide.LEFT, OneHand.toggled(OneHandSide.OFF, OneHandSide.LEFT))
        assertEquals(OneHandSide.OFF, OneHand.toggled(OneHandSide.LEFT))
        for (s in OneHandSide.values()) assertEquals(s, OneHandSide.fromPref(s.pref))
        assertEquals(OneHandSide.OFF, OneHandSide.fromPref(null))
        assertEquals(OneHandSide.OFF, OneHandSide.fromPref("garbage"))
    }

    /** Mọi phím nằm trong vùng hẹp, cùng thứ tự/số lượng, bề rộng = RATIO × bản đầy. */
    @Test fun keysScaleIntoSpan() {
        for (plane in listOf(Plane.LETTERS, Plane.NUMBERS, Plane.SYMBOLS, Plane.PHONE, Plane.NUMPAD, Plane.EDIT)) {
            val full = build(plane, OneHandSide.OFF)
            for (side in listOf(OneHandSide.LEFT, OneHandSide.RIGHT)) {
                val (x0, w) = OneHand.span(W, side)
                val nar = build(plane, side)
                assertEquals("$plane $side", full.size, nar.size)
                for (i in full.indices) {
                    val f = full[i]; val n = nar[i]
                    assertEquals(f.label, n.label)
                    assertTrue("$plane $side $n", n.left >= x0 - 0.01f && n.right <= x0 + w + 0.01f)
                    near(n.top, f.top); near(n.bottom, f.bottom)
                    // Hàng đáy dùng hệ số × bề ngang hàng — co đúng tỉ lệ; phím khác cũng vậy
                    // trừ khe/lề cố định (dp) nên chỉ kiểm gần đúng.
                    assertTrue("$plane $side ${f.label}", n.width <= f.width + 0.01f)
                }
            }
        }
    }

    /** Hàng chữ vẫn một hàng co giãn: hàng 1 kín từ lề trái tới lề phải của vùng hẹp. */
    @Test fun rowsFillSpanExactly() {
        for (side in listOf(OneHandSide.LEFT, OneHandSide.RIGHT)) {
            val (x0, w) = OneHand.span(W, side)
            val keys = build(Plane.LETTERS, side)
            val m = KeyLayout.ROW_MARGIN_H * d
            val row1 = keys.filter { it.kind == KeyKind.LETTER && it.label in "qwertyuiop" }
            near(row1.first().left, x0 + m)
            near(row1.last().right, x0 + w - m)
            val bottom = keys.filter { it.top == keys.first { k -> k.kind == KeyKind.SPACE }.top }
            near(bottom.first().left, x0 + m)
            near(bottom.last().right, x0 + w - m)
            assertEquals(1, bottom.count { it.kind == KeyKind.SPACE })
            val bs = keys.first { it.kind == KeyKind.BACKSPACE }
            near(bs.right, x0 + w - m)
        }
    }

    /** Router: chạm tâm mỗi phím chữ ⇒ đúng phím; chạm giữa rail ⇒ không phím nào. */
    @Test fun routerHitsNarrowedKeys() {
        for (side in listOf(OneHandSide.LEFT, OneHandSide.RIGHT)) {
            val keys = build(Plane.LETTERS, side)
            for (k in keys) {
                val hit = KeyLayout.hit(keys, Plane.LETTERS, k.centerX, k.centerY, 0f, d)
                assertSame("$side ${k.label}", k, hit)
            }
            val (a, b) = OneHand.rail(W, side)!!
            assertNull(KeyLayout.hit(keys, Plane.LETTERS, (a + b) / 2, H * 0.3f, 0f, d))
        }
    }

    /** Gõ vuốt: tâm a–z lấy từ phím thật ⇒ dời theo vùng hẹp, bước phím co theo RATIO. */
    @Test fun swipeCentersFollowNarrowedKeys() {
        val full = KeyLayout.letterCenters(build(Plane.LETTERS, OneHandSide.OFF))
        val nar = KeyLayout.letterCenters(build(Plane.LETTERS, OneHandSide.RIGHT))
        assertEquals(26, nar.size)
        val (x0, _) = OneHand.span(W, OneHandSide.RIGHT)
        for ((ch, p) in nar) {
            assertTrue("$ch", p.first > x0)
            near(p.second, full[ch]!!.second)
        }
        val kwFull = full['w']!!.first - full['q']!!.first
        val kw = nar['w']!!.first - nar['q']!!.first
        assertTrue(kw < kwFull && kw > kwFull * OneHand.RATIO * 0.95f)
        val layout = SwipeLayout(kw, nar)
        assertEquals(kw, layout.keyWidth, 0.001f)
    }

    @Test fun numberRowShiftsToo() {
        val keys = build(Plane.LETTERS, OneHandSide.LEFT, numberRow = true)
        val digits = keys.filter { it.kind == KeyKind.CHAR }
        assertEquals(10, digits.size)
        val w = W * OneHand.RATIO
        assertTrue(digits.all { it.right <= w + 0.01f })
        val q = keys.first { it.label == "q" }
        near(digits.first().centerX, q.centerX)                      // 1 thẳng cột q
    }

    @Test fun emojiAndTemplatesStayFullWidth() {
        assertTrue(!OneHand.appliesTo(Plane.EMOJI) && !OneHand.appliesTo(Plane.TEMPLATES))
        val t = build(Plane.TEMPLATES, OneHandSide.RIGHT)
        near(t.first().left, KeyLayout.ROW_MARGIN_H * d)
        near(t.last().right, W - KeyLayout.ROW_MARGIN_H * d)
    }

    /** Tìm emoji (ô tìm + plane chữ) giữ đầy bề ngang như plane emoji — không rail đè ô tìm. */
    @Test fun emojiSearchStaysFullWidth() {
        assertTrue(!OneHand.appliesTo(Plane.EMOJI_SEARCH))
        val keys = build(Plane.EMOJI_SEARCH, OneHandSide.LEFT)
        near(keys.first { it.label == "q" }.left, KeyLayout.ROW_MARGIN_H * d)
        near(keys.first { it.label == "p" }.right, W - KeyLayout.ROW_MARGIN_H * d)
    }

    /** Tổ hợp: hàng số (VNI tự bật) + một tay — tìm emoji đầy bề ngang (hàng số dưới ô tìm),
     *  bảng sửa có hàng công cụ thu hẹp trong vùng hẹp; router trúng đúng phím. */
    @Test fun numberRowOneHandEmojiSearchAndEditTools() {
        val h = KeyLayout.keyAreaDp(false, false, 0, true)
        val search = KeyLayout.build(LayoutConfig(Plane.EMOJI_SEARCH, W, h, d, numberRow = true, oneHand = OneHandSide.LEFT))
        val head = KeyLayout.searchHeaderPx(h)
        val digits = search.filter { it.kind == KeyKind.CHAR }
        assertEquals(10, digits.size)
        assertTrue(search.all { it.top >= head - 0.01f && it.bottom <= h + 0.01f })
        near(digits.last().right, W - KeyLayout.ROW_MARGIN_H * d)
        near(digits.first().centerX, search.first { it.label == "q" }.centerX)
        val edit = KeyLayout.build(LayoutConfig(Plane.EDIT, W, h, d, numberRow = true, oneHand = OneHandSide.LEFT, editTools = true))
        assertTrue(edit.all { it.right <= W * OneHand.RATIO + 0.01f })
        assertTrue(edit.any { EditPanel.toolOf(it.insert) != null })
        for (k in edit) assertSame(k, KeyLayout.hit(edit, Plane.EDIT, k.centerX, k.centerY, 4f, d))
    }
}
