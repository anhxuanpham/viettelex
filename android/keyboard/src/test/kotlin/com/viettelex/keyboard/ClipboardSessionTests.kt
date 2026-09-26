package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Luồng session: chip số trên bar, ghi lịch sử clipboard, chế độ ẩn danh. */
class ClipboardSessionTests {
    @Before fun setUp() = TestAssets.install()

    private class FakeClip(var text: String? = null) : ClipboardSource {
        override var changeCount = 0
        var sensitive = false
        override fun hasText() = text != null
        override fun readText() = text
        override fun isSensitive() = sensitive
        fun copy(s: String) { text = s; changeCount++ }
    }

    private var now = 1_000_000L
    private val clip = FakeClip()
    private fun session(settings: KeyboardSettings = KeyboardSettings(),
                        traits: FieldTraits = FieldTraits()): KeyboardSession {
        val s = KeyboardSession(UserLangModel(), clip) { now }
        s.startInput(settings, traits)
        return s
    }

    private fun KeyboardSession.typeKeys(p: TextProxy, keys: String) {
        for (c in keys) handle(if (c == ' ') Key.Space else Key.Letter(c), p)
    }

    @Test fun incognitoManualDoesNotLearn() {
        val s = session(settings = KeyboardSettings(incognito = true)); val p = MockProxy()
        val before = s.langModel.count("người")
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before, s.langModel.count("người"))
        assertTrue(s.incognito)
        s.startInput(KeyboardSettings(), FieldTraits())
        assertFalse(s.incognito)
        s.typeKeys(p, "nguoi"); s.acceptSuggestion("người", p)
        assertEquals(before + 2, s.langModel.count("người"))
    }

    @Test fun noLearningFlagCountsAsIncognito() {
        assertTrue(session(traits = FieldTraits(noLearning = true)).incognito)
    }

    @Test fun recordClipRules() {
        val s = session()
        clip.copy("xin chào")
        assertFalse(s.recordClip(fieldSecure = false))                    // lịch sử tắt (null)
        s.clipHistory = ClipboardHistory()
        assertTrue(s.recordClip(fieldSecure = false))
        assertFalse(s.recordClip(fieldSecure = false, onlyIfNew = true))  // đã có
        clip.copy("chép trong ô mật khẩu")
        assertFalse(s.recordClip(fieldSecure = true))
        clip.copy("bí mật"); clip.sensitive = true
        assertFalse(s.recordClip(fieldSecure = false))
        clip.sensitive = false
        val inc = session(settings = KeyboardSettings(incognito = true))
        inc.clipHistory = ClipboardHistory()
        clip.copy("ẩn danh")
        assertFalse(inc.recordClip(fieldSecure = false))
        val incFlag = session(traits = FieldTraits(noLearning = true))
        incFlag.clipHistory = ClipboardHistory()
        assertFalse(incFlag.recordClip(fieldSecure = false))
        assertEquals(listOf("xin chào"), s.clipHistory!!.items(now).map { it.text })
    }

    @Test fun clipChipsOnStripAndAccept() {
        val s = session(); val p = MockProxy()
        clip.copy("Ma OTP cua quy khach la 482913")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.paste)
        assertEquals(listOf("Dán OTP 482913"), set.clipChips.map { it.label })
        s.acceptSuggestion(SuggestionSet.CLIP_CHIP_PREFIX + "482913", p)
        assertEquals("482913", p.text)                   // không space, không học
        now += 3000
        s.invalidatePasteCache()
        p.sb.append(' ')
        assertFalse(s.suggestionsNow(p)!!.paste)         // đã dùng ⇒ hết mời
    }

    @Test fun plainClipNoChips() {
        val s = session(); val p = MockProxy()
        clip.copy("xin chào cả nhà")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.paste)
        assertTrue(set.clipChips.isEmpty())
    }

    @Test fun sensitiveClipNoChips() {
        val s = session(); val p = MockProxy()
        clip.sensitive = true
        clip.copy("482913")
        val set = s.suggestionsNow(p)!!
        assertTrue(set.paste)
        assertTrue(set.clipChips.isEmpty())
    }

    @Test fun insertClipNoLearningNoSpace() {
        val s = session(); val p = MockProxy()
        s.typeKeys(p, "xin ")
        s.insertClip("0912345678", p)
        assertEquals("xin 0912345678", p.text)
        assertFalse(s.bridge.isComposing)
    }
}
