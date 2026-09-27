package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Gõ tắt: hàm thuần + luồng EngineBridge/KeyboardSession qua MockProxy + file YAML khứ hồi
 * với sample-shortcuts.yml. Cùng bộ ca với iOS ShortcutTests.swift.
 */
class ShortcutsTests {
    private val table = ShortcutTable(mapOf(
        "ko" to "không", "đc" to "được", "mn" to "mọi người", "->" to "→", "k2" to "không hai",
        "h" to "giờ", "HN" to "Hà Nội", "sig" to "Thân mến,\nPhil", "j" to "gì",
    ))

    private fun settings(t: ShortcutTable = table, enabled: Boolean = true) =
        KeyboardSettings(shortcuts = t, shortcutsEnabled = enabled)

    /** " " "," "." "\n" "!" = ranh giới, "⌫" = xoá, chữ = phím chữ, còn lại = boundary(.text). */
    private fun type(keys: String, b: EngineBridge, p: MockProxy): String {
        for (ch in keys) when {
            ch == '⌫' -> b.backspace(p)
            ch.isLetter() -> b.letter(ch, p)
            else -> b.boundary(ch.toString(), p)
        }
        return p.text
    }

    private fun typed(keys: String, s: KeyboardSettings = settings()) = type(keys, EngineBridge(s), MockProxy())

    // MARK: hàm thuần

    @Test fun caseFollowsTyping() {
        assertEquals("không", table.expansion("ko"))
        assertEquals("Không", table.expansion("Ko"))
        assertEquals("KHÔNG", table.expansion("KO"))
        assertNull(table.expansion("kO"))
        assertEquals("Mọi người", table.expansion("Mn"))
        assertEquals("MỌI NGƯỜI", table.expansion("MN"))
        assertEquals("Gì", table.expansion("J"))
        assertEquals("Hà Nội", table.expansion("HN"))
        assertNull(table.expansion("hn"))
    }

    @Test fun wordMatchComposedThenRaw() {
        assertEquals("được", table.wordExpansion("đc", "ddc"))
        assertNull(table.wordExpansion("dc", "dc"))
        val t2 = ShortcutTable(mapOf("dc" to "được"))
        assertEquals("được", t2.wordExpansion("dc", "dc"))
        assertNull(t2.wordExpansion("đc", "ddc"))
        assertEquals("khách sạn", ShortcutTable(mapOf("ks" to "khách sạn")).wordExpansion("kś", "ks"))
    }

    @Test fun tokenKeysAndTriggers() {
        assertTrue(table.hasTokenKeys)
        assertFalse(ShortcutTable(mapOf("ko" to "không")).hasTokenKeys)
        assertEquals("→", table.tokenExpansion("a ->")?.second)
        assertEquals("k2", table.tokenExpansion("k2")?.first)
        assertNull(table.tokenExpansion("a->"))
        assertNull(table.tokenExpansion("ko"))
        assertTrue(ShortcutTable.triggersWord(" "))
        assertTrue(ShortcutTable.triggersWord(","))
        assertTrue(ShortcutTable.triggersWord("\n"))
        assertFalse(ShortcutTable.triggersWord("1"))
        assertFalse(ShortcutTable.triggersWord("@"))
        assertFalse(ShortcutTable.triggersWord("/"))
        assertFalse(ShortcutTable.triggersToken(","))
        assertFalse(ShortcutTable.isValidKey("a b"))
        assertFalse(ShortcutTable.isValidKey(""))
    }

    @Test fun glued() {
        assertTrue(ShortcutTable.isGlued("h", "5h"))       // #82
        assertTrue(ShortcutTable.isGlued("h", "/h"))       // #87
        assertTrue(ShortcutTable.isGlued("ko", "a@ko"))
        assertFalse(ShortcutTable.isGlued("h", "5 h"))
        assertFalse(ShortcutTable.isGlued("ko", "ko"))
        assertFalse(ShortcutTable.isGlued("ko", null))
        assertTrue(ShortcutTable.isGlued("ko", "khác"))
    }

    // MARK: luồng EngineBridge

    @Test fun expandsOnBoundaries() {
        assertEquals("không ", typed("ko "))
        assertEquals("Không,", typed("Ko,"))
        assertEquals("KHÔNG.", typed("KO."))
        assertEquals("mọi người!", typed("mn!"))
        assertEquals("không\n", typed("ko\n"))
        assertEquals("được ", typed("ddc "))
        assertEquals("dc ", typed("dc "))
        assertEquals("Thân mến,\nPhil ", typed("sig "))
    }

    @Test fun notOnNonTriggerOrGlued() {
        assertEquals("ko1", typed("ko1"))
        assertEquals("5h ", typed("5h "))
        assertEquals("5h30", typed("5h30"))
        assertEquals("5 giờ ", typed("5 h "))
        assertEquals("/h ", typed("/h "))
        assertEquals("a@ko ", typed("a@ko "))
    }

    @Test fun symbolAndDigitKeys() {
        assertEquals("a → b", typed("a -> b"))
        assertEquals("không hai ", typed("k2 "))
        assertEquals("a->b ", typed("a->b "))
        assertEquals("->,", typed("->,"))
    }

    @Test fun backspaceRestoresTypedOnce() {
        val p = MockProxy(); val b = EngineBridge(settings())
        type("ko ", b, p)
        assertEquals("không ", p.text)
        type("⌫", b, p); assertEquals("ko ", p.text)
        type("⌫", b, p); assertEquals("ko", p.text)
        type(" ", b, p); assertEquals("ko ", p.text)

        val p2 = MockProxy(); val b2 = EngineBridge(settings())
        type("KO a -> ", b2, p2); assertEquals("KHÔNG a → ", p2.text)
        type("⌫", b2, p2); assertEquals("KHÔNG a -> ", p2.text)
    }

    @Test fun backspaceUndoOnlyImmediately() {
        assertEquals("không ", typed("ko a⌫"))
        val p = MockProxy(); val b = EngineBridge(settings())
        type("ko ", b, p)
        p.sb.setLength(0); p.sb.append("khác ")            // app đổi chữ mà không báo
        b.backspace(p)
        assertEquals("khác", p.text)
        assertEquals("không", typed("ko\n⌫"))
    }

    @Test fun passthroughSecureDisabledUrl() {
        assertEquals("ko ", type("ko ", EngineBridge(settings()), MockProxy(isSecureField = true)))
        assertEquals("ko ", type("ko ", EngineBridge(settings()).also { it.passthrough = true }, MockProxy()))
        assertEquals("ko ", type("ko ", EngineBridge(settings()).also { it.shortcutsAllowed = false }, MockProxy()))
        assertEquals("ko ", typed("ko ", settings(enabled = false)))
    }

    @Test fun beforeAutoRestoreAndFailSafe() {
        val t = ShortcutTable(mapOf("gg" to "Google", "ok" to "được rồi"))
        assertEquals("Google ", typed("gg ", settings(t)))
        assertEquals("được rồi ", typed("ok ", settings(t)))
        val p = MockProxy(); val b = EngineBridge(settings())
        type("ko", b, p)
        p.sb.setLength(0); p.sb.append("xyz")
        b.boundary(" ", p)
        assertEquals("xyz ", p.text)                          // không xoá mù chữ của người dùng
    }

    @Test fun reEditStillWorks() = assertEquals("tháy", typed("thay ⌫s"))

    @Test fun previewAndFlag() {
        val p = MockProxy(); val b = EngineBridge(settings())
        type("Ko", b, p)
        assertEquals("Không", b.shortcutPreview)
        assertEquals("Không", b.boundary(" ", p))
        assertTrue(b.expandedAtLastBoundary)
        type("vui", b, p)
        assertNull(b.shortcutPreview)
        b.boundary(" ", p)
        assertFalse(b.expandedAtLastBoundary)
    }

    // MARK: KeyboardSession

    private fun session(t: ShortcutTable = table, field: FieldTraits = FieldTraits()): Pair<KeyboardSession, UserLangModel> {
        TestAssets.install()
        val lm = UserLangModel()
        val s = KeyboardSession(lm)
        s.startInput(settings(t), field)
        return s to lm
    }

    private fun KeyboardSession.keys(keys: String, p: MockProxy) {
        for (ch in keys) handle(when {
            ch == ' ' -> Key.Space
            ch == '⌫' -> Key.Backspace
            ch == '\n' -> Key.Newline
            ch.isLetter() -> Key.Letter(ch)
            else -> Key.Text(ch.toString())
        }, p)
    }

    @Test fun sessionExpandsLearnsExpansionAndUndo() {
        val (s, lm) = session()
        val p = MockProxy()
        val nguoi = lm.count("người"); val moi = lm.count("mọi"); val mn = lm.count("mn")
        s.keys("mn ", p)
        assertEquals("mọi người ", p.text)
        assertEquals(nguoi + 1, lm.count("người"))            // học nội dung đã bung, từng từ
        assertEquals(moi + 1, lm.count("mọi"))
        assertEquals(mn, lm.count("mn"))                       // không học chữ tắt
        s.keys("⌫", p)
        assertEquals("mn ", p.text)
    }

    @Test fun sessionUrlFieldAndSwipeWordNotExpanded() {
        val (s, _) = session(field = FieldTraits(urlField = true))
        val p = MockProxy()
        s.keys("ko ", p)
        assertEquals("ko ", p.text)

        val (s2, _) = session()
        val p2 = MockProxy()
        s2.commitSwipe(SwipeChoice("ko", emptyList()), p2)
        s2.keys(" ", p2)
        assertEquals("ko ", p2.text)
    }

    @Test fun sessionSuggestionPreview() {
        val (s, _) = session()
        val p = MockProxy()
        s.keys("ko", p)
        assertEquals("không", s.suggestionsNow(p)?.word)
    }

    // MARK: file

    private fun sampleFile(): File = listOf(File("../../sample-shortcuts.yml"), File("../sample-shortcuts.yml"), File("sample-shortcuts.yml"))
        .first { it.exists() }

    @Test fun parseExportRoundTripSample() {
        val text = sampleFile().readText()
        val parsed = ShortcutFile.parse(text)
        assertEquals("không", parsed["ko"])
        assertEquals("được", parsed["đc"])
        assertEquals("số tài khoản", parsed["stk"])
        assertEquals(9, parsed.size)
        val exported = ShortcutFile.exportYAML(parsed)
        assertEquals(text, exported)                           // byte-for-byte như macOS
        assertEquals(parsed, ShortcutFile.parse(exported))
    }

    @Test fun parseFormatsAndExtensions() {
        val t = mapOf("sig" to "Thân mến,\nPhil", ":)" to "🙂", "->" to "→", "sp" to " có space ",
            "q" to "\"trích\"", "bs" to "C:\\temp", "k2" to "không hai")
        assertEquals(t, ShortcutFile.parse(ShortcutFile.exportYAML(t)))
        assertEquals(mapOf("ko" to "không"), ShortcutFile.parse("{\"ko\":\"không\"}"))
        assertEquals(mapOf("ko" to "không", "vs" to "với"),
            ShortcutFile.parse("; txt\nko:không\n// c\nvs: 'với'\nbad line\na b: x\n"))
        assertEquals(mapOf("ko" to "không", "dc" to "được"), ShortcutFile.parse("\uFEFFko: không\r\ndc: được\r\n"))
        val (m, added, replaced) = ShortcutFile.merge(mapOf("ko" to "khong", "a" to "b"), mapOf("ko" to "không", "c" to "d"))
        assertEquals(mapOf("ko" to "không", "a" to "b", "c" to "d"), m)
        assertEquals(1, added); assertEquals(1, replaced)
        assertEquals(ShortcutFile.SUGGESTED.size, ShortcutTable(ShortcutFile.SUGGESTED).entries.size)
        assertEquals(listOf("mọi", "người"), ShortcutFile.words("mọi người"))
    }

    @Test fun settingsLoadFromPrefs() {
        val prefs = mapOf<String, Any>(Keys.SHORTCUTS to "ko: không\n")
        assertEquals("không", KeyboardSettings.load { prefs[it] }.shortcuts.expansion("ko"))
        val off = mapOf<String, Any>(Keys.SHORTCUTS to "ko: không\n", Keys.SHORTCUTS_ENABLED to false)
        assertTrue(KeyboardSettings.load { off[it] }.shortcuts.isEmpty)
    }
}
