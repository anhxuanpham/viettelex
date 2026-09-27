package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * Sửa lại từ vuốt trước theo ngữ cảnh hai phía (SwipeRevise). Song sinh iOS
 * SwipeReviseTests.swift. Đo trên câu giữ lại bigram-heldout.txt, gõ vuốt TUẦN TỰ như bàn
 * phím thật: ngữ cảnh trái = các từ đã giải mã (không phải đáp án).
 */
class SwipeReviseTests {
    @Before fun setUp() = TestAssets.install()

    private val layout = SwipeLayout.qwerty(keyWidth = 40f, rowHeight = 54f)
    private fun decoder() = SwipeDecoder().also { it.setLayout(layout) }

    private fun w(word: String, s: Float) = SwipeWord(word, s)

    @Test fun rightContextFlipsCloseCall() {
        // "cô" gần bằng "có" bên trái; biết từ kế là "giáo" ⇒ cô
        val scored = listOf(w("có", 1.0f), w("cô", 0.95f), w("co", 0.5f))
        assertEquals("cô", SwipeRevise.revise(scored, "có", "tôi", "giáo"))
        // từ kế ủng hộ từ đang hiện ⇒ giữ
        assertNull(SwipeRevise.revise(scored, "có", "tôi", "thể"))
        // ngược lại: đang hiện "cô" mà từ kế là "thể" ⇒ có
        assertEquals("có", SwipeRevise.revise(listOf(w("cô", 1.0f), w("có", 0.95f)), "cô", "tôi", "thể"))
    }

    @Test fun clearLeadIsKept() {
        val scored = listOf(w("có", 4.0f), w("cô", 0.5f))
        assertNull(SwipeRevise.revise(scored, "có", "tôi", "giáo"))
    }

    @Test fun marginAndGuards() {
        val scored = listOf(w("có", 1.0f), w("cô", 0.95f))
        assertNull("lề quá lớn", SwipeRevise.revise(scored, "có", "tôi", "giáo", margin = 50f))
        assertNull("không có LM", SwipeRevise.revise(scored, "có", "tôi", "giáo", lm = null))
        assertNull("từ kế ngoài lexicon", SwipeRevise.revise(scored, "có", "tôi", "check"))
        assertNull("từ hiện không nằm trong ứng viên", SwipeRevise.revise(scored, "cỏ", "tôi", "giáo"))
        assertNull("một ứng viên", SwipeRevise.revise(scored.take(1), "có", "tôi", "giáo"))
        // không có từ trước: bigram phải vẫn chạy
        assertEquals("cô", SwipeRevise.revise(scored, "có", null, "giáo"))
    }

    @Test fun rightScoreClamped() {
        val lm = SyllableLM.shared!!
        val id = { s: String -> SyllableBigram.idOf(s) }
        val r = SwipeRevise.rightScore(lm, -1, id("hôm"), id("nay"))
        assertTrue(r > 0f && r <= SwipeRevise.RIGHT_CAP)
        assertTrue(SwipeRevise.rightScore(lm, -1, id("hôm"), id("xịch")) >= SwipeRevise.RIGHT_FLOOR)
        assertEquals(0f, SwipeRevise.rightScore(lm, -1, -1, id("nay")), 0f)
    }

    @Test fun scoredMatchesChoiceAndSkipsEnglish() {
        val d = decoder()
        val p = SwipeSim(1).path("co", layout, sigma = 0.0, jitter = 0.0)
        val ctx = SwipeSuggest.context(null, "không", "tôi")
        val cands = d.decode(p, SwipeSuggest.TOP_K, ctx.folded)
        val choice = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq)!!
        val scored = SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq)
        assertEquals("top-1 của scored = từ chèn", choice.word, scored[0].word)
        assertTrue(scored.size in 2..SwipeRevise.MAX_CANDIDATES)
        assertTrue(scored.zipWithNext().all { (a, b) -> a.score >= b.score })
        val en = listOf(SwipeCandidate("check", 1f, SwipeLang.EN), SwipeCandidate("chec", 0f))
        assertTrue(SwipeRevise.scored(en, null, 2.5f).isEmpty())
    }

    /** Vuốt thật (đường giả sạch) trong câu: từ kế sửa được từ trước. */
    @Test fun sentenceRevision() {
        val d = decoder()
        fun run(words: List<String>, revise: Boolean): List<String> =
            simulate(d, words, revise, SwipeSim(1), sigma = 0.0).first
        // "hôm nay tôi đi học": không được hỏng câu đúng sẵn
        for (s in listOf("hôm nay tôi đi học", "tôi không biết", "cô giáo của tôi")) {
            val words = s.split(' ')
            assertEquals(s, words, run(words, true))
        }
    }

    // ---- mô phỏng tuần tự + đo ----

    data class Acc(val n: Int, val ok: Int, val fixed: Int, val broke: Int, val revised: Int) {
        fun rate() = ok.toDouble() / n
        fun fmt() = String.format(Locale.ROOT, "top1 %.4f (n=%d, sửa %d: +%d −%d)", rate(), n, revised, fixed, broke)
    }

    /**
     * Vuốt lần lượt [words]; trả (từ cuối cùng trên màn hình, số lần sửa, trước-sửa). Ngữ cảnh
     * trái = từ đã hiện (giải mã, đã sửa nếu có) — như KeyboardSession.swipeContext.
     */
    private fun simulate(d: SwipeDecoder, words: List<String>, revise: Boolean, sim: SwipeSim,
                         sigma: Double = 0.25, margin: Float = SwipeRevise.MARGIN,
                         weight: Float = SwipeRevise.RIGHT_WEIGHT): Pair<List<String>, List<String>> {
        val out = ArrayList<String>()
        val before = ArrayList<String>()
        var pending: List<SwipeWord> = emptyList()
        for ((i, word) in words.withIndex()) {
            val p = sim.path(SwipeSuggest.fold(word), layout, sigma = sigma)
            val p1 = out.getOrNull(i - 1); val p2 = out.getOrNull(i - 2)
            val ctx = SwipeSuggest.context(null, p1, p2)
            val cands = d.decode(p, SwipeSuggest.TOP_K, ctx.folded)
            val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq)
            var got = c?.word ?: ""
            var sc = if (c == null) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq)
            if (revise && p1 != null && pending.isNotEmpty() && got.isNotEmpty()) {
                SwipeRevise.revise(pending, p1, p2, got, margin = margin, weight = weight)?.let {
                    out[i - 1] = it
                    val nctx = SwipeSuggest.context(null, it, p2)
                    val re = SwipeRevise.rerank(cands, ctx.word, ctx.lambdaFreq, nctx.word, nctx.lambdaFreq)
                    SwipeSuggest.choose(re, nctx.word, lambdaFreq = nctx.lambdaFreq)?.let { r ->
                        got = r.word; sc = SwipeRevise.scored(re, nctx.word, nctx.lambdaFreq)
                    }
                }
            }
            pending = sc
            out.add(got); before.add(got)
        }
        return out to before
    }

    private fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .firstOrNull { it.exists() } ?: error("không thấy bigram-heldout.txt")
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
    }

    private fun measure(chains: List<List<String>>, revise: Boolean, margin: Float = SwipeRevise.MARGIN,
                        weight: Float = SwipeRevise.RIGHT_WEIGHT): Acc {
        val d = decoder()
        val sim = SwipeSim(2027)
        var n = 0; var ok = 0; var fixed = 0; var broke = 0; var revised = 0
        for (chain in chains) {
            val (final, before) = simulate(d, chain, revise, sim, margin = margin, weight = weight)
            for (i in chain.indices) {
                n++
                if (final[i] == chain[i]) ok++
                if (final[i] != before[i]) {
                    revised++
                    if (final[i] == chain[i]) fixed++
                    if (before[i] == chain[i]) broke++
                }
            }
        }
        return Acc(n, ok, fixed, broke, revised)
    }

    /** Tập đo = 1/3 chuỗi (offset % 3 == 0, như iOS SyllableLMTests); dev (chỉnh hằng số) = phần còn lại. */
    @Test fun heldoutRevisionGain() {
        SlowTests.assume()
        val test = heldout().filterIndexed { i, _ -> i % 3 == 0 }
        measure(test.take(50), true)                               // làm nóng JIT
        var t0 = System.nanoTime()
        val base = measure(test, false)
        val msBase = (System.nanoTime() - t0) / 1e6 / base.n
        t0 = System.nanoTime()
        val rev = measure(test, true)
        val msRev = (System.nanoTime() - t0) / 1e6 / rev.n
        println("REVISE heldout (tuần tự, σ0.25): trước ${base.fmt()} | sau ${rev.fmt()} | +%.2f điểm | %.3f → %.3f ms/vuốt".format(
            Locale.ROOT, (rev.rate() - base.rate()) * 100, msBase, msRev))
        assertTrue("sửa lại phải tăng top-1 ≥ 1 điểm", rev.rate() - base.rate() >= 0.01)
        assertTrue("sửa sai (${rev.broke}) phải ít hơn nhiều sửa đúng (${rev.fixed})", rev.broke * 3 <= rev.fixed)
    }

    /** Quét trọng số/lề trên tập dev: `VT_SLOW_TESTS=1 SWIPE_REVISE_SWEEP=1`. */
    @Test fun sweep() {
        SlowTests.assume()
        org.junit.Assume.assumeTrue(System.getenv("SWIPE_REVISE_SWEEP") == "1")
        val dev = heldout().filterIndexed { i, _ -> i % 3 != 0 }.filterIndexed { i, _ -> i % 2 == 0 }
        val base = measure(dev, false)
        println("SWEEP dev base ${base.fmt()}")
        for (wt in listOf(0.1f, 0.15f, 0.2f, 0.3f)) for (m in listOf(0f, 0.1f, 0.2f, 0.4f)) {
            val r = measure(dev, true, margin = m, weight = wt)
            println("SWEEP w=$wt m=$m ${r.fmt()} +%.2f".format(Locale.ROOT, (r.rate() - base.rate()) * 100))
        }
    }
}
