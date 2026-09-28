package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** "Tự thêm dấu cách sau dấu câu" ([AutoSpace]) — số liệu y hệt iOS AutoSpaceTests. */
class AutoSpaceTests {
    @Before fun setUp() = TestAssets.install()

    @Test fun addsAfterWord() {
        for (p in listOf(".", ",", "?", "!", ";", ":")) {
            assertTrue(p, AutoSpace.shouldAdd(p, "xin chào$p", ""))
            assertTrue(p, AutoSpace.shouldAdd(p, "chào$p", null))
        }
    }

    @Test fun notInsideNumbers() {
        assertFalse(AutoSpace.shouldAdd(".", "giá 3.", ""))
        assertFalse(AutoSpace.shouldAdd(",", "1,", ""))
        assertFalse(AutoSpace.shouldAdd(":", "lúc 10:", ""))
        assertTrue(AutoSpace.shouldAdd("?", "số 3?", ""))
    }

    @Test fun notInUrlsEmailsPaths() {
        assertFalse(AutoSpace.shouldAdd(".", "mail ptrinh@gmail.", ""))
        assertFalse(AutoSpace.shouldAdd(".", "xem https://vnexpress.", ""))
        assertFalse(AutoSpace.shouldAdd(".", "mở ~/Documents/a.", ""))
        assertFalse(AutoSpace.shouldAdd(".", "vào www.", ""))
        assertFalse(AutoSpace.shouldAdd(".", "vào www.google.", ""))
        assertFalse(AutoSpace.shouldAdd(".", "trang vnexpress.net.", ""))
        assertTrue(AutoSpace.shouldAdd(".", "vd e.g.", ""))
        assertTrue(AutoSpace.shouldAdd(".", "ờ..", ""))
    }

    @Test fun notForLoneOrMidText() {
        assertFalse(AutoSpace.shouldAdd(":", "cười :", ""))
        assertFalse(AutoSpace.shouldAdd(".", ".", ""))
        assertFalse(AutoSpace.shouldAdd(",", "a,", " b"))
        assertFalse(AutoSpace.shouldAdd(".", "(hi.", ")"))
        assertTrue(AutoSpace.shouldAdd(",", "hello,", "world"))
        assertFalse(AutoSpace.shouldAdd("-", "a-", ""))
        assertFalse(AutoSpace.shouldAdd(".", "hi", ""))
    }

    @Test fun reactions() {
        assertEquals(AutoSpace.Reaction.CARRY, AutoSpace.reaction(")"))
        assertEquals(AutoSpace.Reaction.CARRY, AutoSpace.reaction("\""))
        assertEquals(AutoSpace.Reaction.CARRY, AutoSpace.reaction("”"))
        assertEquals(AutoSpace.Reaction.REMOVE, AutoSpace.reaction("."))
        assertEquals(AutoSpace.Reaction.REMOVE, AutoSpace.reaction("?"))
        assertEquals(AutoSpace.Reaction.REMOVE, AutoSpace.reaction("/"))
        assertEquals(AutoSpace.Reaction.KEEP, AutoSpace.reaction("("))
        assertEquals(AutoSpace.Reaction.KEEP, AutoSpace.reaction("5"))
        assertEquals(AutoSpace.Reaction.KEEP, AutoSpace.reaction("😀"))
    }

    @Test fun settingDefaultOffAndLoads() {
        assertFalse(KeyboardSettings().autoSpaceAfterPunct)
        assertTrue(KeyboardSettings.load { if (it == Keys.AUTO_SPACE_AFTER_PUNCT) true else null }.autoSpaceAfterPunct)
    }

    // MARK: session

    private fun run(on: Boolean, keys: List<Key>, traits: FieldTraits = FieldTraits()): MockProxy {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(autoSpaceAfterPunct = on, showSuggestions = false), traits)
        val p = MockProxy()
        for (k in keys) s.handle(k, p)
        return p
    }

    private fun word(w: String): List<Key> = w.map { Key.Letter(it) }
    private fun t(s: String) = Key.Text(s)

    @Test fun offIsUnchanged() {
        assertEquals("hi. ", run(false, word("hi") + t(".") + Key.Space).text)
        assertEquals("hi,", run(false, word("hi") + t(",")).text)
    }

    @Test fun offReadsNoExtraContext() {
        fun reads(on: Boolean, s: String): Int {
            val ss = KeyboardSession(UserLangModel(), null) { 0L }
            ss.startInput(KeyboardSettings(autoSpaceAfterPunct = on, showSuggestions = false), FieldTraits())
            val p = MockProxy()
            for (k in word("hi")) ss.handle(k, p)
            p.contextReads = 0
            ss.handle(t(s), p)
            return p.contextReads
        }
        assertEquals(reads(false, "("), reads(false, ";"))
        assertEquals(reads(false, "("), reads(true, "("))
        assertTrue(reads(true, ";") > reads(false, ";"))
    }

    @Test fun addsSpaceAndSwallowsNext() {
        assertEquals("hi, ", run(true, word("hi") + t(",")).text)
        assertEquals("hi. ", run(true, word("hi") + t(".") + Key.Space).text)
        assertEquals("hi. ", run(true, word("hi") + t(".") + Key.DoubleSpacePeriod).text)
        assertEquals("hi.  ", run(true, word("hi") + t(".") + Key.Space + Key.Space).text)
        assertEquals("hi, b", run(true, word("hi") + t(",") + Key.Letter('b')).text)
    }

    @Test fun backspaceRemovesOnlyAutoSpace() {
        assertEquals("hi.", run(true, word("hi") + t(".") + Key.Backspace).text)
        assertEquals("hi", run(true, word("hi") + t(".") + Key.Backspace + Key.Backspace).text)
    }

    @Test fun punctAndClosersAfterAutoSpace() {
        assertEquals("hi... ", run(true, word("hi") + t(".") + t(".") + t(".")).text)
        assertEquals("hi?! ", run(true, word("hi") + t("?") + t("!")).text)
        assertEquals("hi.) ", run(true, word("hi") + t(".") + t(")")).text)
        assertEquals("hi.\" ", run(true, word("hi") + t(".") + t("\"") + Key.Space).text)
        assertEquals("hi.\n", run(true, word("hi") + t(".") + Key.Newline).text)
        assertEquals("http://", run(true, word("http") + t(":") + t("/") + t("/")).text)
    }

    @Test fun numbersStayTight() {
        assertEquals("3.5", run(true, listOf(t("3"), t("."), t("5"))).text)
        assertEquals("1,0", run(true, listOf(t("1"), t(","), t("0"))).text)
    }

    @Test fun fieldGate() {
        for (tr in listOf(FieldTraits(passthrough = true), FieldTraits(isSecure = true), FieldTraits(urlField = true)))
            assertEquals(tr.toString(), "hi.", run(true, word("hi") + t("."), tr).text)
    }

    /** ". " tự thêm ⇒ IME tính lại auto-shift (viết hoa chữ kế); double-space → ". " vẫn chạy. */
    @Test fun autoCapAndDoubleSpace() {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(autoSpaceAfterPunct = true, showSuggestions = false), FieldTraits(capSentences = true))
        val p = MockProxy()
        for (k in word("chao")) s.handle(k, p)
        assertTrue(s.handle(t("."), p).needsAutoShift)
        assertEquals(true, s.updateAutoShift(p))
        s.handle(Key.Letter('A'), p)
        s.handle(Key.Space, p); s.handle(Key.DoubleSpacePeriod, p)
        assertEquals("chao. A. ", p.text)
    }
}

/** Dấu hiệu phím cách: VI/EN khi bật vuốt đổi ngôn ngữ, logo Vᴛ khi tắt (giống iOS SpaceMarkTests). */
class SpaceMarkTests {
    @Test fun choice() {
        assertEquals(SpaceMark.Code("VI"), SpaceMark.choose(true, true, KeyboardLanguage.VI))
        assertEquals(SpaceMark.Code("EN"), SpaceMark.choose(true, false, KeyboardLanguage.EN))
        assertEquals(SpaceMark.Logo(KeyboardLanguage.VI), SpaceMark.choose(false, true, KeyboardLanguage.VI))
        assertEquals(SpaceMark.None, SpaceMark.choose(false, false, KeyboardLanguage.VI))
    }
}
