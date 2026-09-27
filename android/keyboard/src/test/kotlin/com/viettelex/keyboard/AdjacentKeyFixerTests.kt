package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AdjacentKeyFixerTests {
    @Before fun setUp() = TestAssets.install()

    private val bridge = EngineBridge(KeyboardSettings().apply { simpleTelex = true })
    private var composeCalls = 0
    private fun fix(raw: String): String? = AdjacentKeyFixer.correction(raw,
        compose = { composeCalls++; bridge.composeTrial(it) },
        frequency = { VNSuggest.frequency(it) },
        hasCompletion = { VNSuggest.matches(it, poolLimit = 1).isNotEmpty() })

    @Test fun testOnByDefault() = assertTrue(KeyboardSettings().autoFixAdjacent)

    @Test fun testNeighborsAreQwertyAdjacent() {
        val h = AdjacentKeyFixer.neighbors['h'].orEmpty()
        assertTrue(h.contains('g') && h.contains('j') && h.contains('b') && h.contains('y'))
        assertFalse(h.contains('q'))
        val i = AdjacentKeyFixer.neighbors['i'].orEmpty()
        assertTrue(i.contains('j') || i.contains('k'))
    }

    @Test fun testFixesFromTheScreenshot() {
        assertEquals("nhiều", fix("nbjeeuf"))
        assertEquals("phím", fix("ohims"))
        assertEquals("này", fix("nayd"))
        assertEquals("cách", fix("cahcs"))
        assertEquals("nhỉ", fix("nbjr"))
    }

    @Test fun testLeavesRealWordsAndPrefixesAlone() {
        assertNull(fix("nhieeuf"))
        assertNull(fix("ng"))
        assertNull(fix("x"))
    }

    private fun slip(raw: String): String? = AdjacentKeyFixer.toneSlipCorrection(raw,
        compose = { bridge.composeTrial(it) }, frequency = { VNSuggest.frequency(it) })

    /** Bug 27/09: "casn" (ý "caan", a trượt sang s) ra "cán" — từ hợp lệ nên fixer cũ bỏ qua, bar không có "cân". */
    @Test fun testToneKeySlipStillValidWord() {
        assertEquals("cán", bridge.composeTrial("casn"))
        assertEquals("cân", slip("casn"))              // nhân đôi a thắng "căn" (phổ biến hơn)
        assertEquals("Cân", slip("Casn"))
        assertEquals("bên", slip("besn"))
    }

    @Test fun testToneSlipLeavesNormalTypingAlone() {
        assertNull(slip("bans"))                       // phím thanh cuối từ = cách gõ thường
        assertNull(slip("cas"))
        assertNull(slip("tre"))                        // "tr" là phụ âm, r không phải dấu
        assertNull(slip("tieesng"))                    // tiếng
        assertNull(slip("lasm"))                       // "lắm"/"lấm": ứng viên hiếm hơn nhiều ⇒ không gợi
        assertNull(slip("ohims"))                      // không phải từ ⇒ việc của correction()
    }

    @Test fun testToneSlipOffInVni() {
        val vni = EngineBridge(KeyboardSettings().apply { vniMode = true })
        assertNull(AdjacentKeyFixer.lexiconToneSlip("casn", vni))
        assertEquals("cân", AdjacentKeyFixer.lexiconToneSlip("casn", EngineBridge(KeyboardSettings())))
    }

    @Test fun testKeepsSentenceCase() = assertEquals("Phím", fix("Ohims"))

    @Test fun testTouchOffsetMovesSelectionUp() {
        val p = TouchGeometry.keySelectionPoint(KPoint(10f, 100f))
        assertEquals(100f - TouchGeometry.yOffset, p.y)
        assertEquals(10f, p.x)
        assertEquals(100f - 4f * 3f, TouchGeometry.keySelectionPoint(KPoint(10f, 100f), 3f).y)
    }

    @Test fun testPruningKeepsToneAndSwapFixes() {
        assertEquals("cụm", fix("cuxmh"))
        assertEquals("đường", fix("ddusoangf"))
        assertEquals("cum", AdjacentKeyFixer.stripTones("cũm"))
        assertEquals("đương", AdjacentKeyFixer.stripTones("đường"))
    }

    @Test fun testTypicalMissIsCheap() {
        for (w in listOf("keyboard", "position", "github")) {
            composeCalls = 0
            assertNull(w, fix(w))
            assertTrue("$w: $composeCalls compose", composeCalls <= 160)
        }
        for (w in listOf("keyboard", "position", "github")) {
            var best = Double.MAX_VALUE
            repeat(5) {
                val t0 = System.nanoTime(); fix(w)
                best = minOf(best, (System.nanoTime() - t0) / 1e6)
            }
            assertTrue("$w: $best ms", best < 150.0)
        }
    }

    @Test fun testCacheByRawKeystrokes() {
        val b = EngineBridge(KeyboardSettings())
        assertEquals("phím", AdjacentKeyFixer.lexiconCorrection("ohims", b))
        assertNull(AdjacentKeyFixer.lexiconCorrection("github", b))
        assertEquals(2, b.adjacentFixCache.count)
        assertEquals("phím", AdjacentKeyFixer.lexiconCorrection("ohims", b))
        assertNull(AdjacentKeyFixer.lexiconCorrection("github", b))
        assertEquals(2, b.adjacentFixCache.count)
        var n = 0
        b.adjacentFixCache.value("ohims") { n++; null }
        assertEquals(0, n)
    }
}
