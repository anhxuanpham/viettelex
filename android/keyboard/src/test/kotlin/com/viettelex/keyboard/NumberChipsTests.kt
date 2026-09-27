package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Chip số theo fixture chung iOS/KeyboardTests/Fixtures/number-chips.txt (cùng bộ ca với iOS NumberChipsTests). */
class NumberChipsTests {
    private fun fixtureLines(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/number-chips.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/number-chips.txt")
        return f.readText(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { line -> line.split('|').map { it.replace("␣", " ") } }
    }

    @Test fun fixture() {
        var n = 0
        for (c in fixtureLines()) {
            n++
            when (c[0]) {
                "spell" -> assertEquals("spell ${c[1]}", c[2], NumberChips.spell(c[1]))
                "spellLe" -> assertEquals("spellLe ${c[1]}", c[2], NumberChips.spell(c[1], le = true))
                "calc" -> assertEquals("calc ${c[1]}", c[2],
                    NumberChips.evaluate(c[1])?.let(NumberChips::formatResult) ?: "-")
                "chip" -> {
                    val chip = NumberChips.chip(c[1])
                    if (c[2] == "-") assertNull("chip «${c[1]}» phải null", chip)
                    else assertEquals("chip «${c[1]}»", NumberChip(c[2], c[3], c[4]), chip)
                }
                else -> error("dòng fixture lạ: $c")
            }
        }
        assertTrue(n > 100)
    }

    @Test fun replaceIsSuffixOfContext() {
        for (c in fixtureLines()) if (c[0] == "chip" && c[2] != "-")
            assertTrue("«${c[3]}» không phải đuôi «${c[1]}»", c[1].endsWith(c[3]))
    }

    @Test fun shorthandExact() {
        assertEquals("1200000", NumberChips.parseAmount("1tr2")?.value?.int)
        assertEquals("2000000000", NumberChips.parseAmount("2 tỷ")?.value?.int)
        assertNull(NumberChips.parseAmount("1.2tr5"))
        assertNull(NumberChips.parseAmount("12 5"))
    }
}
