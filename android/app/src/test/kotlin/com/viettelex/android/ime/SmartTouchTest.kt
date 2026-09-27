package com.viettelex.android.ime

import org.junit.Assert.assertSame
import org.junit.Test

/** Chọn phím theo ngữ cảnh trên layout Android thật (logic: keyboard/TouchTarget.kt). */
class SmartTouchTest {
    private val keys = KeyLayout.build(LayoutConfig(Plane.LETTERS, 390f, KeyLayout.keyAreaDp(false, false, 0), 1f))
    private fun key(c: String) = keys.first { it.kind == KeyKind.LETTER && it.label == c }
    private val onlyW: (Char) -> Float? = { if (it == 'w') 1f else 0f }

    @Test fun centerKeepsNearestEvenAgainstPrior() {
        val q = key("q")
        val cx = (q.left + q.right) / 2; val cy = (q.top + q.bottom) / 2
        assertSame(q, SmartTouch.refine(keys, q, cx, cy, onlyW))
    }

    @Test fun borderFollowsPrior() {
        val q = key("q"); val w = key("w")
        val cy = (q.top + q.bottom) / 2
        val x = q.right - 0.05f * (q.right - q.left)
        assertSame(w, SmartTouch.refine(keys, q, x, cy, onlyW))
        // Không prior / prior không biết ⇒ giữ phím gần nhất.
        assertSame(q, SmartTouch.refine(keys, q, x, cy, null))
        assertSame(q, SmartTouch.refine(keys, q, x, cy) { null })
    }

    @Test fun nonLetterUntouched() {
        val shift = keys.first { it.kind == KeyKind.SHIFT }
        assertSame(shift, SmartTouch.refine(keys, shift, shift.right - 1f, (shift.top + shift.bottom) / 2, onlyW))
    }
}
