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

    @Test fun typedNextWordNeedsExactTail() {
        val scored = listOf(w("có", 1.0f), w("cô", 0.95f), w("cố", 0.9f))
        val t = SwipeRevise.Typed("có", scored, SwipeSuggest.Case.LOWER, "tôi")
        val e = SwipeRevise.reviseTyped(t, "giáo", " ", "tôi có giáo ")!!
        assertEquals("cô", e.new)
        assertEquals("tôi có giáo ", "tôi " + e.tail)
        assertEquals("cô giáo ", e.replacement)
        assertEquals("cô giáo,", SwipeRevise.reviseTyped(t, "giáo", ",", "có giáo,")!!.replacement)
        assertNull("đuôi lệch", SwipeRevise.reviseTyped(t, "giáo", " ", "tôi có giáo  "))
        assertNull("từ vuốt dính chữ trước", SwipeRevise.reviseTyped(t, "giáo", " ", "xcó giáo "))
        assertNull("ranh giới là chữ", SwipeRevise.reviseTyped(t, "giáo", "a", "có giáoa"))
        assertNull("không đọc được", SwipeRevise.reviseTyped(t, "giáo", " ", null))
        assertNull("từ gõ rỗng", SwipeRevise.reviseTyped(t, "", " ", "có  "))
        assertNull("từ gõ tiếng Anh", SwipeRevise.reviseTyped(t, "check", " ", "có check "))
        assertNull("từ kế ủng hộ từ đang hiện", SwipeRevise.reviseTyped(t, "thể", " ", "có thể "))
        // chữ hoa theo từ cũ; từ gõ viết hoa vẫn tra LM chữ thường
        val c = SwipeRevise.Typed("Có", scored, SwipeSuggest.Case.FIRST, null)
        assertEquals("Cô Giáo ", SwipeRevise.reviseTyped(c, "Giáo", " ", "Có Giáo ")!!.replacement)
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

    /**
     * Vuốt CẢ CÂU từng từ như bàn phím (KeyboardSession.resolveSwipe): ngữ cảnh trái = từ đã hiện,
     * bật vuốt tiếng Anh (ngôn ngữ theo 2 từ trước), sửa chung cặp với cú vuốt trước. [old] = cách
     * trước 28/09/2026 (sửa theo top-1 từ kế, ứng viên 3 dạng × 4 dấu).
     */
    private fun phrase(d: SwipeDecoder, words: List<String>, old: Boolean = false, path: (String) -> SwipePath): List<String> {
        val pw = if (old) 4 else SwipeRevise.POOL_WORDS; val pm = if (old) 8 else SwipeRevise.MAX_CANDIDATES
        val out = ArrayList<String>(); val eng = HashSet<Int>()
        var pending: List<SwipeWord> = emptyList()
        for ((i, word) in words.withIndex()) {
            val p1 = out.getOrNull(i - 1); val p2 = out.getOrNull(i - 2)
            val prior = SwipeLangContext.prior(SwipeLangContext.classify(p1, (i - 1) in eng),
                SwipeLangContext.classify(p2, (i - 2) in eng))
            val ctx = SwipeSuggest.context(null, p1, p2, prior)
            val cands = d.decode(path(SwipeSuggest.fold(word)), SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
            var c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq)
            var sc = if (c == null || c.english) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq, pw, pm)
            val new = if (c == null || c.english || p1 == null || pending.isEmpty()) null
                else if (old) SwipeRevise.revise(pending, p1, p2, c.word)
                else SwipeRevise.revise(pending, p1, p2, SwipeRevise.nextPool(cands, ctx.word, ctx.lambdaFreq))
            if (new != null) {
                out[i - 1] = new
                val nctx = SwipeSuggest.context(null, new, p2, prior)
                val re = SwipeRevise.rerank(cands, ctx.word, ctx.lambdaFreq, nctx.word, nctx.lambdaFreq)
                val r = SwipeSuggest.choose(re, nctx.word, lambdaFreq = nctx.lambdaFreq)
                if (r != null) { c = r; sc = if (r.english) emptyList() else SwipeRevise.scored(re, nctx.word, nctx.lambdaFreq, pw, pm) }
            }
            if (c?.english == true) eng.add(i)
            pending = sc
            out.add(c?.word ?: "")
        }
        return out
    }

    /**
     * Báo lỗi người dùng 28/09/2026: vuốt "ví dụ như thế này" không ra từ nào đúng. Trước: "vì dù
     * như thế này" cả với đường sạch (ví không nằm trong ứng viên, dụ kém sau "vì"). Sửa chung cặp
     * + ứng viên rộng ⇒ đúng; "the" sau từ Việt ra "thế" (không phải the tiếng Anh).
     */
    @Test fun phraseViDuNhuTheNay() {
        val words = "ví dụ như thế này".split(' ')
        val d = decoder()
        val clean = { w: String -> SwipeSim(1).path(w, layout, sigma = 0.0, jitter = 0.0) }
        assertEquals(words, phrase(d, words, path = clean))
        val legacy = SwipeDecoder(SwipeDecoder.Params(speedWeight = 0f, dwellWeight = 0f, overshoot = 0f)).also { it.setLayout(layout) }
        assertEquals("vì dù như thế này", phrase(legacy, words, old = true, path = clean).joinToString(" "))
        // đường "tự nhiên" (nhịp + lố như nét thật), 30 lần — cùng đường cho cách cũ/mới
        fun run(dec: SwipeDecoder, old: Boolean): Pair<Int, Int> {
            val sim = SwipeSim(77)
            var ok = 0; var theEn = 0
            repeat(30) {
                val r = phrase(dec, words, old) { w -> sim.natural(w, layout) }
                ok += words.indices.count { r[it] == words[it] }
                if (r[2] == "như" && r[3] == "the") theEn++   // sau "như" đúng
            }
            return ok to theEn
        }
        val n = 30 * words.size
        val (ok0, en0) = run(legacy, true); val (ok1, en1) = run(d, false)
        println(String.format(Locale.ROOT, "REVISE câu \"ví dụ như thế này\" (đường tự nhiên ×30, bật EN): đúng %.3f → %.3f từ, the Anh (sau \"như\") %d → %d",
            ok0.toDouble() / n, ok1.toDouble() / n, en0, en1))
        assertTrue("đúng $ok0 → $ok1 /$n", ok1 >= n * 0.7 && ok1 >= ok0 + n / 10)
        assertEquals(0, en1)
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
                         weight: Float = SwipeRevise.JOINT_WEIGHT, joint: Boolean = true): Pair<List<String>, List<String>> {
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
                // như KeyboardSession: sửa chung cặp với ứng viên rộng của cú vuốt này
                (if (joint) SwipeRevise.revise(pending, p1, p2, SwipeRevise.nextPool(cands, ctx.word, ctx.lambdaFreq),
                    margin = margin, weight = weight)
                else SwipeRevise.revise(pending, p1, p2, got, margin = margin, weight = weight))?.let {
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
                        weight: Float = SwipeRevise.JOINT_WEIGHT, joint: Boolean = true): Acc {
        val d = decoder()
        val sim = SwipeSim(2027)
        var n = 0; var ok = 0; var fixed = 0; var broke = 0; var revised = 0
        for (chain in chains) {
            val (final, before) = simulate(d, chain, revise, sim, margin = margin, weight = weight, joint = joint)
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
        val chain = measure(test, true, weight = SwipeRevise.RIGHT_WEIGHT, joint = false)
        t0 = System.nanoTime()
        val rev = measure(test, true)
        val msRev = (System.nanoTime() - t0) / 1e6 / rev.n
        println("REVISE heldout (tuần tự, σ0.25): trước ${base.fmt()} | sửa theo từ kế ${chain.fmt()} | sửa chung cặp ${rev.fmt()} | +%.2f điểm | %.3f → %.3f ms/vuốt".format(
            Locale.ROOT, (rev.rate() - base.rate()) * 100, msBase, msRev))
        assertTrue("sửa lại phải tăng top-1 ≥ 1 điểm", rev.rate() - base.rate() >= 0.01)
        // sửa chung cặp (28/09/2026) phải hơn hẳn sửa theo top-1 từ kế
        assertTrue("chung cặp ${rev.fmt()} vs theo từ kế ${chain.fmt()}", rev.rate() >= chain.rate() + 0.02)
        assertTrue("sửa sai (${rev.broke}) phải ít hơn nhiều sửa đúng (${rev.fixed})", rev.broke * 3 <= rev.fixed)
    }

    // ---- từ kế GÕ BẰNG PHÍM (chắc chắn): vuốt xen kẽ gõ ----

    /**
     * Vuốt/gõ xen kẽ: vị trí i vuốt khi i % 2 == [phase], còn lại gõ phím (đúng đáp án). Gõ
     * xong từ kế ⇒ chấm lại từ vuốt ngay trước (lõi của [SwipeRevise.reviseTyped], hằng số TYPED_*). Đo CHỈ các từ vuốt
     * có từ gõ ngay sau (đủ điều kiện). Trả (n, đúng, sửa đúng, sửa sai, số lần sửa).
     */
    private fun simulateTyped(d: SwipeDecoder, words: List<String>, phase: Int, revise: Boolean, sim: SwipeSim,
                              margin: Float, weight: Float): Acc {
        val out = ArrayList<String>()
        val before = HashMap<Int, String>()
        var pending: List<SwipeWord> = emptyList()
        for ((i, word) in words.withIndex()) {
            val p1 = out.getOrNull(i - 1); val p2 = out.getOrNull(i - 2)
            if (i % 2 != phase) {
                if (revise && p1 != null && pending.isNotEmpty())
                    SwipeRevise.revise(pending, p1, p2, word, margin = margin, weight = weight)?.let { out[i - 1] = it }
                pending = emptyList()
                out.add(word)
                continue
            }
            val p = sim.path(SwipeSuggest.fold(word), layout, sigma = 0.25)
            val ctx = SwipeSuggest.context(null, p1, p2)
            val cands = d.decode(p, SwipeSuggest.TOP_K, ctx.folded)
            val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq)
            val got = c?.word ?: ""
            pending = if (c == null) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq)
            if (i + 1 < words.size) before[i] = got
            out.add(got)
        }
        var n = 0; var ok = 0; var fixed = 0; var broke = 0; var revised = 0
        for ((i, b) in before) {
            n++
            if (out[i] == words[i]) ok++
            if (out[i] != b) { revised++; if (out[i] == words[i]) fixed++; if (b == words[i]) broke++ }
        }
        return Acc(n, ok, fixed, broke, revised)
    }

    private fun measureTyped(chains: List<List<String>>, revise: Boolean, margin: Float = SwipeRevise.TYPED_MARGIN,
                             weight: Float = SwipeRevise.TYPED_RIGHT_WEIGHT): Acc {
        val d = decoder()
        val sim = SwipeSim(2027)
        var a = Acc(0, 0, 0, 0, 0)
        for (chain in chains) for (phase in 0..1) {
            val r = simulateTyped(d, chain, phase, revise, sim, margin, weight)
            a = Acc(a.n + r.n, a.ok + r.ok, a.fixed + r.fixed, a.broke + r.broke, a.revised + r.revised)
        }
        return a
    }

    /** Cùng tập đo như [heldoutRevisionGain]; từ kế gõ bằng phím. JVM 27/09/2026: 85,7 % → 94,2 % (+341 −15). */
    @Test fun heldoutTypedRevisionGain() {
        SlowTests.assume()
        val test = heldout().filterIndexed { i, _ -> i % 3 == 0 }
        val base = measureTyped(test, false)
        val rev = measureTyped(test, true)
        println("REVISE-TYPED heldout (vuốt xen gõ, σ0.25): trước ${base.fmt()} | sau ${rev.fmt()} | +%.2f điểm | sửa sai %.2f%% số lần sửa, %.2f%% số từ".format(
            Locale.ROOT, (rev.rate() - base.rate()) * 100, 100.0 * rev.broke / maxOf(1, rev.revised), 100.0 * rev.broke / rev.n))
        assertTrue("sửa lại phải tăng top-1 ≥ 1 điểm", rev.rate() - base.rate() >= 0.01)
        assertTrue("sửa sai (${rev.broke}) phải rất ít so với sửa đúng (${rev.fixed})", rev.broke * 5 <= rev.fixed)
    }

    /** Quét cho ca từ kế gõ phím trên tập dev: `VT_SLOW_TESTS=1 SWIPE_REVISE_SWEEP=1`. */
    @Test fun sweepTyped() {
        SlowTests.assume()
        org.junit.Assume.assumeTrue(System.getenv("SWIPE_REVISE_SWEEP") == "1")
        val dev = heldout().filterIndexed { i, _ -> i % 3 != 0 }.filterIndexed { i, _ -> i % 2 == 0 }
        val base = measureTyped(dev, false)
        println("SWEEP-TYPED dev base ${base.fmt()}")
        for (wt in listOf(0.1f, 0.15f, 0.2f, 0.3f, 0.4f, 0.6f)) for (m in listOf(0f, 0.1f, 0.2f, 0.3f, 0.5f)) {
            val r = measureTyped(dev, true, margin = m, weight = wt)
            println("SWEEP-TYPED w=$wt m=$m ${r.fmt()} +%.2f".format(Locale.ROOT, (r.rate() - base.rate()) * 100))
        }
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
