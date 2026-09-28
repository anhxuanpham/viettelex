package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Kết quả phép tính theo fixture chung iOS/KeyboardTests/Fixtures/math-results.txt (cùng bộ ca với iOS MathResultsTests). */
class MathResultsTests {
    private fun fixtureLines(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/math-results.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/math-results.txt")
        return f.readText(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { line -> line.split('|').map { it.replace("␣", " ") } }
    }

    @Test fun fixture() {
        var n = 0
        for (c in fixtureLines()) {
            n++
            when (c[0]) {
                "eval" -> assertEquals("eval ${c[1]}", c[2], MathResults.result(c[1]) ?: "-")
                "chip" -> {
                    val chip = MathResults.chip(c[1])
                    if (c[2] == "-") assertNull("chip «${c[1]}» phải null", chip)
                    else assertEquals("chip «${c[1]}»", NumberChip(c[2], "", c[2]), chip)
                }
                else -> error("dòng fixture lạ: $c")
            }
        }
        assertTrue(n > 80)
    }

    /** Chip số không còn nhận "…=" (tránh 2 chip cùng một kết quả). */
    @Test fun numberChipsIgnoreEquals() = assertNull(NumberChips.chip("12*3="))
}
