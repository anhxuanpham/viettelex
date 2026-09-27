package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * Giữ phím chữ ra số / ký hiệu (issue #98). Bảng theo fixture chung
 * iOS/KeyboardTests/Fixtures/key-alternates.txt (cùng bộ với iOS KeyAlternatesTests).
 */
class KeyAlternatesTests {
    @Before fun setUp() = TestAssets.install()

    private fun fixture(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/key-alternates.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy iOS/KeyboardTests/Fixtures/key-alternates.txt")
        return f.readText(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() && !it.startsWith("#") }
            .map { it.split('\t') }
    }

    @Test fun tablesMatchSharedFixture() {
        val rows = fixture()
        val digits = rows.filter { it[0] == "numbers" }.associate { it[1][0] to it[2] }
        val symbols = rows.filter { it[0] == "symbols" }.associate { it[1][0] to it[2] }
        assertEquals(KeyAlternates.digits, digits)
        assertEquals(KeyAlternates.symbols, symbols)
        assertEquals("qwertyuiop".toSet(), digits.keys)
        assertEquals("asdfghjklzxcvbnm".toSet(), symbols.keys)
    }

    @Test fun noDuplicateAndNoLetters() {
        val all = KeyAlternates.digits.values + KeyAlternates.symbols.values
        assertEquals("không trùng ký tự phụ", all.size, all.toSet().size)
        for (a in all) assertFalse(a, a[0].isLetter())
        assertEquals("₫", KeyAlternates.symbols['d'])        // Telex đã có dd → đ
    }

    @Test fun mapGating() {
        assertEquals(KeyAlternates.digits, KeyAlternates.map(true, false, numberRow = false))
        assertTrue("hàng số bật ⇒ giữ q ra số vô nghĩa", KeyAlternates.map(true, false, numberRow = true).isEmpty())
        assertEquals(KeyAlternates.symbols, KeyAlternates.map(true, true, numberRow = true))
        assertEquals(26, KeyAlternates.map(true, true, numberRow = false).size)
        assertTrue(KeyAlternates.map(false, false, numberRow = false).isEmpty())
        assertTrue(KeyAlternates.map(true, true, numberRow = false, accessibility = true).isEmpty())
        assertTrue(KeyAlternates.numbersSettingVisible(numberRow = false))
        assertFalse(KeyAlternates.numbersSettingVisible(numberRow = true))
    }

    @Test fun holdStateMachine() {
        val h = KeyAlternates.Hold("3", 0f, 0f)
        assertFalse(h.move(6f, 6f))                           // trong slop
        assertNull(h.commit)                                  // chưa đủ giờ = chạm thường
        assertTrue(h.fire())
        assertEquals("3", h.commit)
        assertFalse(h.move(80f, 0f))                          // đã bắn: trôi không huỷ
        h.cancel()
        assertEquals("3", h.commit)

        val d = KeyAlternates.Hold("@", 0f, 0f)
        assertTrue(d.move(KeyAlternates.SLOP_DP + 1, 0f))
        assertFalse("trôi trước khi đủ giờ ⇒ không thành ký tự phụ", d.fire())
        assertNull(d.commit)

        val c = KeyAlternates.Hold("@", 0f, 0f)
        c.cancel()                                            // ngón khác / thành vuốt
        assertFalse(c.fire())
    }

    @Test fun thresholdBetweenTrackpadAndOtherHolds() {
        assertTrue(KeyAlternates.HOLD_MS in 301..449)
    }

    private fun session(alternates: Boolean = true): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(), FieldTraits())
        s.setLetterAlternates(alternates)
        return s
    }

    private fun KeyboardSession.type(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    /** Ký tự phụ huỷ đúng phím chữ (checkpoint, không ⌫) rồi chốt từ + chèn như hàng số. */
    @Test fun rollbackKeepsTelexComposition() {
        val s = session(); val p = MockProxy()
        s.type(p, "tiee")                                     // chạm e thứ hai: "tiê"
        assertEquals("tiê", p.text)
        s.handle(Key.Text("3", replacesLetter = true), p)
        assertEquals("tie3", p.text)
        s.type(p, "a")
        assertEquals("tie3a", p.text)

        val s2 = session(); val p2 = MockProxy()
        s2.type(p2, "tiengs")                                 // phím dấu: "tiéng"
        s2.handle(Key.Text("#", replacesLetter = true), p2)
        assertEquals("tieng#", p2.text)

        val s3 = session(); val p3 = MockProxy()
        s3.type(p3, "xin a")
        s3.handle(Key.Text("@", replacesLetter = true), p3)
        assertEquals("xin @", p3.text)
    }

    /** Tắt ⇒ không ghi checkpoint mỗi phím (0 chi phí); đường ⌫ dự phòng vẫn đúng với chữ thường. */
    @Test fun offMeansNoCheckpoint() {
        val s = session(alternates = false); val p = MockProxy()
        s.type(p, "an")
        assertFalse(s.undoLastLetter(p))
        val s2 = session(alternates = false); val p2 = MockProxy()
        s2.type(p2, "xin q")
        s2.handle(Key.Text("1", replacesLetter = true), p2)
        assertEquals("xin 1", p2.text)
    }
}
