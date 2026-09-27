package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.nio.file.Files

/** Từ điển cá nhân: xoá từ kéo theo n-gram, thêm từ thủ công được gợi ý, persist. */
class UserDictionaryTests {
    @Before fun setUp() = TestAssets.install()

    private fun model() = UserLangModel()

    private fun sentence(m: UserLangModel, vararg words: String, times: Int = 3) {
        repeat(times) {
            var p1: String? = null; var p2: String? = null
            for (w in words) { m.record(w, p1, p2); p2 = p1; p1 = w }
        }
    }

    @Test fun testRemoveWordDropsBigramsAndTrigrams() {
        val m = model().apply { isKnownWord = { true } }
        sentence(m, "sếp", "duyệt", "gấp")
        sentence(m, "báo", "sếp", "duyệt")
        assertTrue("duyệt" in m.nextWords("sếp", limit = 5))
        assertTrue("gấp" in m.nextWords("duyệt", "sếp", limit = 5))

        assertTrue(m.removeWord("Duyệt"))                         // không phân biệt hoa/thường
        assertEquals(0, m.count("duyệt"))
        assertFalse("duyệt" in m.nextWords("sếp", limit = 5))     // bigram sếp→duyệt
        assertTrue(m.nextWords("duyệt", limit = 5).isEmpty())     // bigram duyệt→*
        assertFalse("gấp" in m.nextWords("duyệt", "sếp", limit = 5)) // trigram sếp␁duyệt→*
        assertFalse(m.entries().any { it.word == "duyệt" })
        // từ khác còn nguyên
        assertEquals(6, m.count("sếp"))
        assertTrue("sếp" in m.nextWords("báo", limit = 5))
        assertFalse(m.removeWord("duyệt"))                        // lần 2: không còn gì
    }

    @Test fun testRemoveWordAsTrigramTarget() {
        val m = model().apply { isKnownWord = { true } }
        sentence(m, "sếp", "duyệt", "gấp")
        m.removeWord("gấp")
        assertFalse("gấp" in m.nextWords("duyệt", "sếp", limit = 5))
        assertFalse("gấp" in m.nextWords("duyệt", limit = 5))
        assertTrue("duyệt" in m.nextWords("sếp", limit = 5))
    }

    @Test fun testManualWordSuggestedImmediately() {
        val m = model()                                     // isKnownWord = false: từ lạ
        m.record("kubernetes", null)
        assertFalse("kubernetes" in m.topWords(10))          // từ lạ 1 lần: chưa gợi ý
        assertTrue(m.addWord("  VietTelex "))
        assertTrue("VietTelex" in m.topWords(10))            // dạng hiển thị giữ hoa
        assertEquals(listOf("VietTelex"), m.manualCompletions("viet"))
        assertEquals(listOf("VietTelex"), m.manualCompletions("Viết"))   // bỏ dấu
        assertTrue(m.manualCompletions("telex").isEmpty())   // chỉ tiền tố
        assertTrue(m.entries().first { it.word == "VietTelex" }.manual)
        assertEquals(listOf("VietTelex"), m.entries("TELEX").map { it.word })   // tìm kiếm
        assertEquals("VietTelex", m.entries().first().word)                      // count 5 > 1
        assertFalse(m.addWord("hai từ"))
        assertFalse(m.addWord("abc123"))
        assertFalse(m.addWord(""))
    }

    @Test fun testManualWordSurvivesDecay() {
        val now = 100L * 7 * 86_400_000L
        val m = UserLangModel(clock = { now })
        m.addWord("Kubernetes")
        m.setLastDecayForTest(now - 20L * 7 * 86_400_000L)  // 20 tuần: count về 0
        m.decayIfDue(now)
        assertTrue(m.count("kubernetes") >= 1)
        assertTrue("Kubernetes" in m.topWords(5))
    }

    @Test fun testManualWordInComposingSuggestions() {
        val s = KeyboardSession(UserLangModel(), null) { 0L }
        s.startInput(KeyboardSettings(), FieldTraits())
        s.langModel.addWord("Kubernetes")
        val p = MockProxy()
        for (c in "kube") s.handle(Key.Letter(c), p)
        val set = s.suggestionsNow(p)!!
        assertTrue(listOf(set.word, set.word2).contains("Kubernetes"))
    }

    @Test fun testPersistManualAndRemoval() {
        val dir = Files.createTempDirectory("userdict").toFile()
        val f = java.io.File(dir, "userlm.bin")
        val direct = java.util.concurrent.Executor { it.run() }
        val a = UserLangModel(f, ImmediateMainThread(), direct).apply { isKnownWord = { true } }
        sentence(a, "sếp", "duyệt", "gấp")
        a.addWord("Phúc")
        a.removeWord("gấp")
        a.save()
        val b = UserLangModel(f, ImmediateMainThread(), direct)
        assertTrue(b.entries().any { it.word == "Phúc" && it.manual })
        assertEquals(0, b.count("gấp"))
        assertEquals(3, b.count("duyệt"))
        assertEquals(listOf("Phúc"), b.manualCompletions("phu"))
        // file cũ không có đuôi manual vẫn đọc được
        b.removeWord("phúc"); b.save()
        val c = UserLangModel(f, ImmediateMainThread(), direct)
        assertTrue(c.isManualEmpty)
        assertEquals(3, c.count("sếp"))
        assertNull(c.entries().firstOrNull { it.manual })
        dir.deleteRecursively()
    }
}
