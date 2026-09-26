package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Kiểu gõ VNI trên Android: số (hàng số / plane ?123 = Key.Text) trong lúc soạn từ mang dấu
 * (engine vniMode như macOS), ngoài từ vẫn là số; sửa dấu từ đã gõ bằng 1–5/0/7/8; gợi ý
 * dùng raw VNI. Cùng kỳ vọng với iOS VNIBridgeTests.
 */
class VNITests {
    @Before fun setUp() = TestAssets.install()

    private val vni = KeyboardSettings(vniMode = true)

    private fun session(settings: KeyboardSettings = vni) =
        KeyboardSession(UserLangModel()).also { it.startInput(settings, FieldTraits()) }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(when (c) {
            ' ' -> Key.Space
            '<' -> Key.Backspace
            '.' -> Key.Text(".")
            in '0'..'9' -> Key.Text(c.toString())
            else -> Key.Letter(c)
        }, p)
    }

    private fun type(keys: String, initial: String = "", settings: KeyboardSettings = vni): String {
        val p = MockProxy(); p.sb.append(initial)
        session(settings).typeKeys(p, keys)
        return p.text
    }

    @Test fun digitsCarryDiacriticsInsideWord() {
        assertEquals("tiếng việt ", type("tie6ng1 vie6t5 "))
        assertEquals("đường ", type("d9u7o7ng2 "))
        assertEquals("Việt Nam ", type("Vie6t5 Nam "))
        assertEquals("hòa ", type("hoa2 "))
        assertEquals("", type("a1<"))
        assertEquals("việ", type("vie6t5<"))
    }

    @Test fun digitsOutsideWordStayNumbers() {
        assertEquals("2026 ", type("2026 "))
        assertEquals("nam 2026.", type("nam 2026."))
        assertEquals("hoa 2", type("hoa 2"))
        assertEquals("mp3 ", type("mp3 "))
    }

    @Test fun lettersAreLiteralInVNI() {
        assertEquals("vieetj ", type("vieetj "))
        assertEquals("google ", type("google "))
    }

    @Test fun telexUnchanged() {
        val telex = KeyboardSettings()
        assertFalse(EngineBridge(telex).vniDigit('1', MockProxy()))
        assertEquals("việt1 ", type("vieetj1 ", settings = telex))
        assertEquals("tiếng 2026 ", type("tieengs 2026 ", settings = telex))
    }

    @Test fun reEditWithDigits() {
        assertEquals("việt", type("5", initial = "viêt"))
        assertEquals("viêt", type("0", initial = "việt"))
        assertEquals("hòa", type("hoa <2"))
        assertEquals("xin chào ", type("xin chao <2 "))
        assertEquals("thấy", type("tha1y <6"))
        assertEquals("to6", type("6", initial = "to"))
        assertEquals("mp3", type("3", initial = "mp"))
        assertEquals("viêt5", type("5", initial = "viêt", settings = vni.copy(reEditWords = false)))
    }

    @Test fun reEditKeySetsPerMethod() {
        assertTrue(ReEdit.isTransformKey('s'))
        assertFalse(ReEdit.isTransformKey('1'))
        for (d in "12345078") assertTrue(ReEdit.isTransformKey(d, vni = true))
        for (c in "69sfw") assertFalse(ReEdit.isTransformKey(c, vni = true))
    }

    @Test fun suggestionsUseVNIRaw() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "vie6t5")
        assertEquals("vie6t5", s.bridge.rawWord)
        assertEquals("việt", s.bridge.composedWord)
        assertEquals("việt", s.bridge.predictedCommit)
        assertEquals("tiếng", s.bridge.composeTrial("tie6ng1"))
        val set = s.suggestionsNow(p)!!
        assertEquals("vie6t5", set.literal)      // predicted == composed ⇒ slot nguyên văn = raw VNI
        val fix = AdjacentKeyFixer.correction(
            "nbie6u2", { s.bridge.composeTrial(it) },
            { if (it == "nhiều") 100 else null },
            { w -> "nhiều".startsWith(w) || "nhiêu".startsWith(w) })
        assertEquals("nhiều", fix)
    }

    @Test fun swipeWordEditableWithDigits() {
        val s = session(); val p = MockProxy()
        assertTrue(s.bridge.adoptWord("tiêng"))
        p.sb.append("tiêng")
        s.typeKeys(p, "1 ")
        assertEquals("tiếng ", p.text)
    }
}
