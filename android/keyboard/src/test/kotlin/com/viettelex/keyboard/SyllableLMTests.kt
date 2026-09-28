package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/**
 * Mô hình trigram âm tiết tĩnh (vnlm.bin) + tác dụng lên gõ vuốt; cả phần bigram PMI mà thanh
 * gợi ý + Thêm dấu dùng (thay vnbigram.bin từ 28/09/2026). Song sinh iOS SyllableLMTests.swift.
 * Đo trên câu Tatoeba GIỮ LẠI (bigram-heldout.txt, không nằm trong dữ liệu dựng mô hình).
 */
class SyllableLMTests {
    @Before fun setUp() = TestAssets.install()

    private val layout = SwipeLayout.qwerty(keyWidth = 40f, rowHeight = 54f)
    private val lm get() = SyllableLM.shared!!

    private fun id(w: String) = SyllableLM.idOf(w).also { assertTrue("thiếu $w", it >= 0) }
    private fun s(a: String?, b: String, c: String) = lm.score(if (a == null) -1 else id(a), id(b), id(c))

    @Test fun loadsAndMatchesLexicon() {
        val m = SyllableLM.shared
        assertNotNull("vnlm.bin phải khớp vnlexicon.bin (lexHash)", m)
        assertEquals(VNLexicon2Data.count, m!!.count)
        assertTrue("bigram ${m.biEntries}", m.biEntries in 100_000..600_000)
        assertTrue("trigram ${m.triEntries}", m.triEntries in 100_000..600_000)
        val size = KeyboardData.buffer(Keys.ASSET_LM).capacity()
        assertTrue("kích thước $size", size <= 2_700_000)
    }

    private fun pmi(a: String, b: String) = lm.bigram(id(a)).pmi(id(b))

    /** Bigram PMI (s2 + uniAdj) — thay vnbigram.bin cho thanh gợi ý + Thêm dấu. */
    @Test fun bigramPmi() {
        assertTrue(pmi("hôm", "nay") > 2f)
        assertTrue(pmi("không", "có") > pmi("không", "cô"))
        assertTrue(pmi("hôm", "nay") > pmi("hôm", "ngay"))
        assertTrue(pmi("ngay", "lập") > 2f)
        assertTrue(pmi("điện", "thoại") > 3f)
        // bằng chứng âm (cặp hiếm) + lùi γ2 khi thiếu mục tường minh
        assertTrue(pmi("hôm", "xịch") < 0f)
        assertEquals(0f, lm.bigram(id("hôm")).explicit(id("xịch")), 0f)
        assertEquals(pmi("hôm", "nay"), lm.bigram(id("hôm")).explicit(id("nay")), 0f)
        // PMI = s2 + uniAdj (s2 = điểm bigram của decoder vuốt)
        assertEquals(lm.score(-1, id("hôm"), id("nay")) + lm.uniAdj(id("nay")), pmi("hôm", "nay"), 1e-6f)
        assertEquals(0, lm.bigram(-1).size)
        assertEquals(0, lm.bigram(VNLexicon2Data.count).size)
        assertEquals(0f, lm.bigram(-1).pmi(id("nay")), 0f)
        var n = 0; var hasNay = false
        lm.bigram(id("hôm")).forEach { c, v -> n++; if (c == id("nay")) { hasNay = true; assertEquals(pmi("hôm", "nay"), v, 0f) } }
        assertTrue(hasNay && n == lm.bigram(id("hôm")).size)
    }

    @Test fun normalizeOldStyleAndCase() {
        assertEquals("hòa", SyllableLM.normalize("Hoà"))
        assertEquals("thủy", SyllableLM.normalize("thuỷ"))
        assertEquals("quý", SyllableLM.normalize("quý"))
        assertEquals(SyllableLM.idOf("hòa"), SyllableLM.idOf("HOÀ"))
        assertEquals(-1, SyllableLM.idOf("hello"))
    }

    @Test fun typicalScores() {
        assertTrue(s(null, "hôm", "nay") > 2f)
        assertTrue(s(null, "hôm", "nay") > s(null, "hôm", "ngay"))
        assertTrue(s(null, "không", "có") > s(null, "không", "cô"))
        // bằng chứng âm: cặp hiếm có điểm < 0
        assertTrue(s(null, "hôm", "xịch") < 0f)
        // trigram: 2 âm tiết trước đổi lựa chọn
        assertTrue(s("cuối", "cùng", "cũng") > s("cuối", "cùng", "chúng"))
        assertTrue(s("một", "ngày", "nọ") > s(null, "ngày", "nọ"))
        assertEquals(0f, lm.score(-1, -1, id("nay")), 0f)
        assertNull(lm.context(-1, VNLexicon2Data.count))
        assertEquals(0f, lm.score(-1, id("hôm"), VNLexicon2Data.count), 0f)
    }

    @Test fun rejectsCorruptOrMismatched() {
        val src = KeyboardData.buffer(Keys.ASSET_LM)
        val bytes = ByteArray(src.capacity()) { src.get(it) }
        fun buf(b: ByteArray) = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        val lexHash = SyllableLM.fnv1a(KeyboardData.buffer(Keys.ASSET_LEXICON))
        assertNotNull(SyllableLM.load(buf(bytes), lexHash, VNLexicon2Data.count))
        assertNull(SyllableLM.load(buf(bytes), lexHash xor 1, VNLexicon2Data.count))
        assertNull(SyllableLM.load(buf(bytes), lexHash, VNLexicon2Data.count - 1))
        assertNull(SyllableLM.load(buf(bytes.copyOf(bytes.size - 1)), lexHash, VNLexicon2Data.count))
        val bad = bytes.copyOf(); bad[3] = 'X'.code.toByte()
        assertNull(SyllableLM.load(buf(bad), lexHash, VNLexicon2Data.count))
        val v1 = bytes.copyOf(); v1[4] = 1   // bản cũ (không có uniAdj) ⇒ từ chối
        assertNull(SyllableLM.load(buf(v1), lexHash, VNLexicon2Data.count))
    }

    // ---- gõ vuốt trong ngữ cảnh ----

    private fun decoder() = SwipeDecoder().also { it.setLayout(layout) }

    private fun swipe(d: SwipeDecoder, prev2: String?, prev: String?, word: String,
                      model: UserLangModel? = null): String? {
        val p = SwipeSim(1).path(SwipeSuggest.fold(word), layout, sigma = 0.0, jitter = 0.0)
        val ctx = SwipeSuggest.context(model, prev, prev2)
        return SwipeSuggest.choose(d.decode(p, SwipeSuggest.TOP_K, ctx.folded), ctx.word,
            lambdaFreq = ctx.lambdaFreq)?.word
    }

    @Test fun contextPicksInTop1() {
        val d = decoder()
        // cặp điển hình — trigram không được làm hỏng
        for ((prev, w) in listOf("không" to "có", "cho" to "tôi", "hôm" to "nay", "ngay" to "lập",
            "đi" to "ngay", "trong" to "nhà", "bây" to "giờ", "nửa" to "đêm", "bữa" to "nay",
            "môi" to "trường", "ở" to "trong", "làm" to "cho", "một" to "nửa")) {
            assertEquals("$prev + vuốt ${SwipeSuggest.fold(w)}", w, swipe(d, null, prev, w))
        }
        // cần 2 âm tiết trước (bigram một mình chọn sai trên tập giữ lại)
        for ((ctx, w) in listOf(("cuối" to "cùng") to "cũng", ("một" to "ngày") to "nọ",
            ("bị" to "mất") to "ví", ("làm" to "việc") to "cùng")) {
            assertEquals("${ctx.first} ${ctx.second} + vuốt ${SwipeSuggest.fold(w)}", w,
                swipe(d, ctx.first, ctx.second, w))
        }
    }

    @Test fun personalStillWins() {
        // user hay gõ "không cô" (tên riêng…) ⇒ nextWords thắng LM tĩnh
        val ctx = SwipeSuggest.Context(setOf("cô"), setOf("co"), { if (it == "cô") 6 else 0 },
            prev = "không", prev2 = "tôi", lm = SyllableLM.shared)
        val p = SwipeSim(1).path("co", layout, sigma = 0.0, jitter = 0.0)
        assertEquals("cô", SwipeSuggest.choose(decoder().decode(p, SwipeSuggest.TOP_K, ctx.folded), ctx.word,
            lambdaFreq = ctx.lambdaFreq)?.word)
    }

    @Test fun noContextKeepsOldScoring() {
        // không có âm tiết trước ⇒ không LM, λ như cũ
        val ctx = SwipeSuggest.context(null, null, null)
        assertEquals(SwipeDecoder.Params().lambdaFreq, ctx.lambdaFreq, 0f)
        assertEquals(SwipeDecoder.Params().lambdaFreq, SwipeSuggest.context(null, "xyzq", "tôi").lambdaFreq, 0f)
        assertEquals(SwipeSuggest.LM_LAMBDA_FREQ, SwipeSuggest.context(null, "tôi", null).lambdaFreq, 0f)
    }

    // ---- đo độ chính xác trên câu giữ lại ----

    private fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy bigram-heldout.txt")
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
    }

    data class Acc(val n: Int, val top1: Int, val top3: Int, val ms: Double) {
        fun fmt() = String.format(Locale.ROOT, "top1 %.3f top3 %.3f (n=%d, %.3f ms/vuốt)",
            top1.toDouble() / n, top3.toDouble() / n, n, ms)
    }

    /** [useLM]=false ⇒ không LM tĩnh (chỉ tần suất — vnbigram.bin cũ đã bỏ). */
    private fun measure(useLM: Boolean, english: Boolean = false): Acc {
        val d = decoder()
        val sim = SwipeSim(2027)
        var n = 0; var t1 = 0; var t3 = 0
        val t0 = System.nanoTime()
        for (chain in heldout()) for (i in 1 until chain.size) {
            val w = chain[i]
            val p = sim.path(SwipeSuggest.fold(w), layout)
            val prior = if (english) SwipeLangContext.prior(SwipeLangContext.classify(chain[i - 1]),
                SwipeLangContext.classify(chain.getOrNull(i - 2))) else null
            val ctx = SwipeSuggest.context(null, chain[i - 1], chain.getOrNull(i - 2), prior,
                lm = if (useLM) SyllableLM.shared else null)
            val cands = d.decode(p, SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
            val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq) ?: continue
            n++
            if (c.word == w) t1++
            if (c.word == w || w in c.alternatives.take(2)) t3++
        }
        return Acc(n, t1, t3, (System.nanoTime() - t0) / 1e6 / maxOf(1, n))
    }

    @Test fun heldoutAccuracy() {
        SlowTests.assume()
        val none = measure(false)
        val tri = measure(true)
        println("LM heldout không LM: ${none.fmt()} | trigram: ${tri.fmt()}")
        assertTrue("top1 ${tri.fmt()}", tri.top1.toDouble() / tri.n >= TOP1)
        assertTrue("top3 ${tri.fmt()}", tri.top3.toDouble() / tri.n >= TOP3)
        assertTrue("trigram phải hơn không LM ≥ $GAIN_TOP1", (tri.top1 - none.top1).toDouble() / tri.n >= GAIN_TOP1)
    }

    /** Bật cả vuốt tiếng Anh: ứng viên Anh không làm tụt trigram quá 1 điểm. */
    @Test fun heldoutAccuracyWithEnglish() {
        SlowTests.assume()
        val vi = measure(true)
        val both = measure(true, english = true)
        println("LM+EN heldout: chỉ Việt ${vi.fmt()} | bật tiếng Anh ${both.fmt()}")
        assertTrue("top1 ${both.fmt()}", both.top1.toDouble() / both.n >= TOP1)
        assertTrue("top1 tụt > 1 điểm", (vi.top1 - both.top1).toDouble() / vi.n <= 0.01)
    }

    /** Câu trộn Việt–Anh: trigram (có điểm âm cho âm tiết Việt) không được đẩy từ Anh ra ngoài. */
    @Test fun mixedSentencesKeepEnglish() {
        val sentences = listOf(
            listOf("mình", "đang", "check", "mail"), listOf("gửi", "file", "cho", "anh"),
            listOf("em", "gửi", "email", "cho", "sếp"), listOf("tôi", "nay", "có", "meeting", "không"),
            listOf("share", "link", "cho", "mình"), listOf("deadline", "là", "thứ", "sáu"),
            listOf("anh", "ấy", "đang", "online"), listOf("cho", "mình", "xin", "link", "nhé"))
        fun run(useLM: Boolean): Triple<Int, Int, Int> {
            val d = decoder(); val sim = SwipeSim(99)
            var t1 = 0; var t3 = 0; var n = 0
            repeat(10) {
                for (s in sentences) for (i in 1 until s.size) {
                    val w = s[i]
                    val prior = SwipeLangContext.prior(SwipeLangContext.classify(s[i - 1]),
                        SwipeLangContext.classify(s.getOrNull(i - 2)))
                    val ctx = SwipeSuggest.context(null, s[i - 1], s.getOrNull(i - 2), prior,
                        lm = if (useLM) SyllableLM.shared else null)
                    val c = SwipeSuggest.choose(d.decode(sim.path(SwipeSuggest.fold(w), layout), SwipeSuggest.TOP_K,
                        ctx.folded, ctx.english, ctx.englishWord), ctx.word, lambdaFreq = ctx.lambdaFreq) ?: continue
                    n++
                    if (c.word == w) t1++
                    if (c.word == w || w in c.alternatives) t3++
                }
            }
            return Triple(t1, t3, n)
        }
        val off = run(false); val on = run(true)
        println("LM câu trộn Việt–Anh (n=${on.third}): không LM top1 ${off.first} top3 ${off.second} | trigram top1 ${on.first} top3 ${on.second}")
        assertTrue("top1 trigram ${on.first} < không LM ${off.first}", on.first >= off.first)
        assertTrue("top3 ${on.second}/${on.third}", on.second >= on.third * 9 / 10)
    }

    companion object {
        // đo 27/09/2026 (decoder tầng 2): bigram 0.861/0.951 → trigram 0.894/0.962;
        // ngưỡng hồi quy chừa ~1.5 điểm. 28/09/2026 (bỏ vnbigram.bin): không LM 0.702/0.869
        // → trigram 0.894/0.961.
        const val TOP1 = 0.877
        const val TOP3 = 0.950
        const val GAIN_TOP1 = 0.17
    }

    /** Dump ứng viên hình học để chỉnh tham số ngoài (BIGRAM_DUMP=đường-dẫn, BIGRAM_CHAINS=chuỗi). */
    @Test fun dumpGeometry() {
        val out = System.getenv("BIGRAM_DUMP") ?: return
        val chains = File(System.getenv("BIGRAM_CHAINS")).readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
        val d = decoder()
        val sim = SwipeSim(2027)
        val sb = StringBuilder()
        for (chain in chains) for (i in 1 until chain.size) {
            val w = chain[i]
            val p = sim.path(SwipeSuggest.fold(w), layout)
            val c = d.decode(p, 16)
            sb.append(chain[i - 1]).append('\t').append(w).append('\t')
            c.joinTo(sb, ";") { it.folded + ":" + String.format(Locale.ROOT, "%.4f", it.score) }
            sb.append('\n')
        }
        File(out).writeText(sb.toString())
    }
}
