package com.viettelex.android.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Hàng phím số tuỳ chọn (27/09/2026): 1…0 trên plane chữ, cao 0.75 hàng chữ. */
class NumberRowTest {
    private val d = 1f
    private val W = 390f
    private val H4 = KeyLayout.keyAreaDp(false, false, 0)                    // 224
    private val H5 = KeyLayout.keyAreaDp(false, false, 0, numberRow = true)  // 266

    private fun build(plane: Plane, numberRow: Boolean, h: Float = if (numberRow) H5 else H4) =
        KeyLayout.build(LayoutConfig(plane, W, h, d, numberRow = numberRow))

    private fun near(a: Float, b: Float, eps: Float = 0.01f) = assertEquals(b, a, eps)

    @Test fun heightAddsThreeQuartersOfARow() {
        near(H5, 224f + 56f * 0.75f)
        near(KeyLayout.keyAreaDp(true, true, 0, numberRow = true), 300f / 4f * 4.75f)
        // chỉnh ±dp mỗi hàng: hàng số ăn 0.75 phần
        near(KeyLayout.keyAreaDp(false, false, 5, numberRow = true), (224f + 20f) / 4f * 4.75f)
        near(KeyLayout.rowUnit(H5, true), 56f)
        near(KeyLayout.rowUnit(H4, false), 56f)
    }

    @Test fun offIsUnchanged() {
        val a = build(Plane.LETTERS, false)
        assertTrue(a.none { it.kind == KeyKind.CHAR })
        val q = a.first { it.label == "q" }
        near(q.top, KeyLayout.ROW_MARGIN_V)
    }

    @Test fun lettersPlaneGetsShortNumberRow() {
        val keys = build(Plane.LETTERS, true)
        val digits = keys.filter { it.kind == KeyKind.CHAR }
        assertEquals(listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"), digits.map { it.label })
        val u = 56f
        val m = KeyLayout.ROW_MARGIN_V
        // hàng số: [0, 0.75u], phím = hàng − 2 margin
        near(digits[0].top, m); near(digits[0].bottom, 0.75f * u - m)
        // hàng chữ: đúng cao như khi tắt, chỉ dời xuống 0.75u
        val off = build(Plane.LETTERS, false)
        for (k in off) {
            val on = keys.first { it.kind == k.kind && it.label == k.label && it.insert == k.insert }
            near(on.top, k.top + 0.75f * u, 0.05f); near(on.height, k.height, 0.05f)
            near(on.left, k.left); near(on.width, k.width)
        }
        // 1 thẳng cột q, cùng bề rộng
        val q = keys.first { it.label == "q" }
        near(digits[0].left, q.left); near(digits[0].width, q.width)
        // hàng đáy chạm đáy vùng phím
        val space = keys.first { it.kind == KeyKind.SPACE }
        near(space.bottom, H5 - KeyLayout.BOTTOM_ROW_BOTTOM, 0.05f)
    }

    @Test fun digitsHitAsCharNotLetter() {
        val keys = build(Plane.LETTERS, true)
        val seven = keys.first { it.label == "7" }
        val hit = KeyLayout.hit(keys, Plane.LETTERS, seven.centerX, seven.centerY, 4f, d)
        assertEquals("7", hit?.label); assertEquals(KeyKind.CHAR, hit?.kind)
        // giữa chữ u (hàng dưới) vẫn ra u
        val u = keys.first { it.label == "u" }
        assertEquals("u", KeyLayout.hit(keys, Plane.LETTERS, u.centerX, u.centerY, 4f, d)?.label)
        // khe giữa hàng số và hàng q: không mất chạm
        val gapY = (seven.bottom + u.top) / 2
        assertTrue(KeyLayout.hit(keys, Plane.LETTERS, seven.centerX, gapY, 4f, d) != null)
    }

    @Test fun numbersPlaneKeepsFourRowsFillingArea() {
        val keys = build(Plane.NUMBERS, true)
        val rowH = H5 / 4f
        val one = keys.first { it.label == "1" }
        near(one.top, KeyLayout.ROW_MARGIN_V); near(one.bottom, rowH - KeyLayout.ROW_MARGIN_V)
        assertEquals(1, keys.count { it.label == "1" })
    }

    @Test fun templatesBottomRowIsOneStandardRow() {
        val keys = build(Plane.TEMPLATES, true)
        val space = keys.first { it.kind == KeyKind.SPACE }
        near(space.top, H5 - 56f + KeyLayout.BOTTOM_ROW_TOP, 0.05f)
    }

    /** Gõ vuốt lấy tâm a–z: vẫn đủ 26 chữ, bước phím như cũ. */
    @Test fun swipeCentersStillLetters() {
        val keys = build(Plane.LETTERS, true)
        val letters = keys.filter { it.kind == KeyKind.LETTER }
        assertEquals(26, letters.size)
        val off = build(Plane.LETTERS, false).filter { it.kind == KeyKind.LETTER }
        near(letters.first { it.label == "w" }.centerX - letters.first { it.label == "q" }.centerX,
            off.first { it.label == "w" }.centerX - off.first { it.label == "q" }.centerX)
    }
}
