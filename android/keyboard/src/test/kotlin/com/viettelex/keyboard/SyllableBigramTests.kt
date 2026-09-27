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
 * Bảng bigram âm tiết tĩnh + tác dụng lên gõ vuốt. Song sinh iOS SyllableBigramTests.swift.
 * Đo độ chính xác trên câu Tatoeba GIỮ LẠI (fixture bigram-heldout.txt, không nằm trong dữ
 * liệu dựng bảng): mỗi âm tiết có âm tiết trước → đường vuốt giả σ0.25 → decode + chọn dấu.
 */
class SyllableBigramTests {
    @Before fun setUp() = TestAssets.install()

    private val layout = SwipeLayout.qwerty(keyWidth = 40f, rowHeight = 54f)
    private val big get() = SyllableBigram.shared!!

    private fun id(w: String) = SyllableBigram.idOf(w).also { assertTrue("thiếu $w", it >= 0) }
    private fun pmi(a: String, b: String) = big.score(id(a), id(b))

    @Test fun loadsAndMatchesLexicon() {
        val b = SyllableBigram.shared
        assertNotNull("vnbigram.bin phải khớp vnlexicon.bin (lexHash)", b)
        assertEquals(VNLexicon2Data.count, b!!.count)
        assertTrue("entries ${b.entries}", b.entries in 100_000..500_000)
        val size = KeyboardData.buffer(Keys.ASSET_BIGRAM).capacity()
        assertTrue("kích thước $size", size <= 1_600_000)
    }

    @Test fun typicalPairs() {
        assertTrue(pmi("hôm", "nay") > 2f)
        assertTrue(pmi("không", "có") > pmi("không", "cô"))
        assertTrue(pmi("hôm", "nay") > pmi("hôm", "ngay"))
        assertTrue(pmi("ngay", "lập") > 2f)
        assertEquals(0f, big.score(id("hôm"), id("xịch")), 0f)
        assertEquals(0f, big.score(-1, id("nay")), 0f)
        assertEquals(0, big.row(VNLexicon2Data.count).size)
    }

    @Test fun normalizeOldStyleAndCase() {
        assertEquals("hòa", SyllableBigram.normalize("Hoà"))
        assertEquals("thủy", SyllableBigram.normalize("thuỷ"))
        assertEquals("quý", SyllableBigram.normalize("quý"))
        assertEquals(SyllableBigram.idOf("hòa"), SyllableBigram.idOf("HOÀ"))
        assertEquals(-1, SyllableBigram.idOf("hello"))
    }

    @Test fun rejectsCorruptOrMismatched() {
        val src = KeyboardData.buffer(Keys.ASSET_BIGRAM)
        val bytes = ByteArray(src.capacity()) { src.get(it) }
        fun buf(b: ByteArray) = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
        val lexHash = SyllableBigram.fnv1a(KeyboardData.buffer(Keys.ASSET_LEXICON))
        assertNotNull(SyllableBigram.load(buf(bytes), lexHash, VNLexicon2Data.count))
        assertNull(SyllableBigram.load(buf(bytes), lexHash xor 1, VNLexicon2Data.count))
        assertNull(SyllableBigram.load(buf(bytes.copyOf(bytes.size - 1)), lexHash, VNLexicon2Data.count))
        val bad = bytes.copyOf(); bad[0] = 'X'.code.toByte()
        assertNull(SyllableBigram.load(buf(bad), lexHash, VNLexicon2Data.count))
    }

    // ---- gõ vuốt trong ngữ cảnh ----

    private fun decoder() = SwipeDecoder().also { it.setLayout(layout) }

    /** Vuốt [word] (đường sạch hoặc nhiễu) sau âm tiết [prev], không có dữ liệu cá nhân. */
    private fun swipe(d: SwipeDecoder, prev: String?, word: String, sim: SwipeSim? = null): String? {
        val p = (sim ?: SwipeSim(1)).path(SwipeSuggest.fold(word), layout,
            sigma = if (sim == null) 0.0 else 0.25, jitter = if (sim == null) 0.0 else 0.04)
        val ctx = SwipeSuggest.context(null, prev, null, lm = null)   // chỉ bigram (trigram: SyllableLMTests)
        return SwipeSuggest.choose(d.decode(p, SwipeSuggest.TOP_K, ctx.folded), ctx.word)?.word
    }

    @Test fun contextPicksPairInTop1() {
        val d = decoder()
        for ((prev, w) in listOf("không" to "có", "cho" to "tôi", "hôm" to "nay", "ngay" to "lập",
            "đi" to "ngay", "trong" to "nhà", "bây" to "giờ", "nửa" to "đêm", "bữa" to "nay",
            "môi" to "trường", "ở" to "trong", "làm" to "cho", "một" to "nửa")) {
            assertEquals("$prev + vuốt ${SwipeSuggest.fold(w)}", w, swipe(d, prev, w))
        }
    }

    @Test fun personalStillWins() {
        // user hay gõ "không cô" (vd. tên riêng) ⇒ nextWords thắng bigram tĩnh
        val ctx = SwipeSuggest.Context(setOf("cô"), setOf("co"), { if (it == "cô") 6 else 0 },
            prev = "không", bigram = SyllableBigram.shared)
        val d = decoder()
        val p = SwipeSim(1).path("co", layout, sigma = 0.0, jitter = 0.0)
        assertEquals("cô", SwipeSuggest.choose(d.decode(p, SwipeSuggest.TOP_K, ctx.folded), ctx.word)?.word)
    }

    // ---- đo độ chính xác trên câu giữ lại ----

    private fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy bigram-heldout.txt")
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
    }

    data class Acc(val n: Int, val top1: Int, val top3: Int) {
        fun fmt() = String.format(Locale.ROOT, "top1 %.3f top3 %.3f (n=%d)", top1.toDouble() / n, top3.toDouble() / n, n)
    }

    /** [useBigram]=false ⇒ như trước giai đoạn 2 (không dữ liệu cá nhân, không bigram). */
    private fun measure(useBigram: Boolean, english: Boolean = false): Acc {
        val d = decoder()
        val sim = SwipeSim(2027)
        var n = 0; var t1 = 0; var t3 = 0
        for (chain in heldout()) for (i in 1 until chain.size) {
            val w = chain[i]
            val p = sim.path(SwipeSuggest.fold(w), layout)
            // english ⇒ như IME khi bật "Vuốt từ tiếng Anh" (giai đoạn 3): prior theo từ trước
            val prior = if (english) SwipeLangContext.prior(SwipeLangContext.classify(chain[i - 1]),
                SwipeLangContext.classify(chain.getOrNull(i - 2))) else null
            val ctx = SwipeSuggest.context(null, if (useBigram) chain[i - 1] else null, null, prior, lm = null)
            val cands = d.decode(p, SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
            val c = SwipeSuggest.choose(cands, ctx.word) ?: continue
            n++
            if (c.word == w) t1++
            if (c.word == w || w in c.alternatives.take(2)) t3++
        }
        return Acc(n, t1, t3)
    }

    @Test fun heldoutAccuracy() {
        val before = measure(false)
        val t0 = System.nanoTime()
        val after = measure(true)
        val ms = (System.nanoTime() - t0) / 1e6 / after.n
        println("BIGRAM heldout trước: ${before.fmt()} | sau: ${after.fmt()} | " +
            String.format(Locale.ROOT, "%.2f ms/vuốt (decode + bigram)", ms))
        assertTrue(before.n > 3000)
        assertTrue("top1 sau ${after.fmt()}", after.top1.toDouble() / after.n >= AFTER_TOP1)
        assertTrue("top3 sau ${after.fmt()}", after.top3.toDouble() / after.n >= AFTER_TOP3)
        assertTrue("bigram phải cải thiện ≥ ${GAIN_TOP1}", (after.top1 - before.top1).toDouble() / after.n >= GAIN_TOP1)
    }

    /** Giai đoạn 2 + 3 cùng bật: thêm ứng viên tiếng Anh không làm tụt bigram quá 1 điểm. */
    @Test fun heldoutAccuracyWithEnglish() {
        val vi = measure(true)
        val both = measure(true, english = true)
        println("BIGRAM+EN heldout: chỉ Việt ${vi.fmt()} | bật tiếng Anh ${both.fmt()}")
        assertTrue("top1 ${both.fmt()}", both.top1.toDouble() / both.n >= AFTER_TOP1)
        assertTrue("top1 tụt > 1 điểm", (vi.top1 - both.top1).toDouble() / vi.n <= 0.01)
    }

    companion object {
        // đo 27/09/2026: trước top1 0.704 top3 0.865 → sau top1 0.856 top3 0.948 (n=12027);
        // + tầng 2 decoder (σ thích nghi/căn phím/góc/độ dài): 0.710/0.870 → 0.861/0.951.
        // ngưỡng hồi quy chừa ~1.5 điểm
        const val AFTER_TOP1 = 0.845
        const val AFTER_TOP3 = 0.935
        const val GAIN_TOP1 = 0.13
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
