package com.viettelex.keyboard

import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.time.Instant
import java.util.Locale

/**
 * BỘ ĐO CHỈNH decoder gõ vuốt (không chạy mặc định — SWIPE_TUNE=1). Đo trên CÙNG layout iPhone
 * (bước phím 36.8) với: nét THẬT (SWIPE_TRACES=file xuất từ Luyện vuốt, tách nửa A/B theo chỉ số
 * chẵn/lẻ), từ rời + câu giữ lại với đường giả "đều" (SwipeSim.path) và "tự nhiên"
 * (SwipeSim.natural, hiệu chỉnh theo nét thật). SWIPE_CFGS="legacy;base;sw=1,ov=0.5…" (khoá: xem
 * [cfgs]); SWIPE_TEST=1 ⇒ tập kiểm thử thay dev; SWIPE_JOINT=0 ⇒ sửa từ trước theo top-1 từ kế
 * (cũ). Kết quả 28/09/2026: docs/DATA-SOURCES.md "Nét vuốt thật".
 *
 *   SWIPE_TUNE=1 SWIPE_TRACES=… SWIPE_CFGS='legacy;base' ./gradlew --offline :keyboard:test \
 *     --tests '*SwipeTuneTests.tune' -i | grep TUNE
 */
class SwipeTuneTests {
    @Before fun setUp() = TestAssets.install()

    private val ios = SwipeLayout.qwerty(keyWidth = 36.8f, rowHeight = 55f, originX = 3.5f, originY = 5f)

    private fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .first { it.exists() }
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
    }

    private fun trace(word: String, folded: String, lang: SwipeLang, p: SwipePath, l: SwipeLayout): SwipeTrace {
        val pts = (0 until p.count).map { Triple(p.xs[it], p.ys[it], ((p.ts[it] - p.ts[0]) * 1000).toFloat()) }
        return SwipeTrace(word, folded, lang, l.keyWidth, ('a'..'z').associateWith { l.center(it)!! }, pts, emptyList(), 0L)
    }

    @Test fun exportSim() {
        val out = System.getenv("SWIPE_SIM_EXPORT") ?: return
        val sim = SwipeSim(5)
        val words = listOf("thay", "dung", "they", "their", "be", "away", "this", "thuong", "night", "before", "trong",
            "nhan", "day", "me", "lay", "might", "vi", "lan", "these", "after", "chi", "cung", "hoi", "nao", "trai",
            "nhin", "khi", "have")
        val tr = ArrayList<SwipeTrace>()
        repeat(3) { for (w in words) tr.add(trace(w, w, SwipeLang.VI, sim.natural(w, ios), ios)) }
        File(out).writeText(SwipePractice.export(tr, "sim", Instant.EPOCH))
    }

    data class Cfg(val name: String, val p: SwipeDecoder.Params)

    private fun realEval(traces: List<SwipeTrace>, p: SwipeDecoder.Params): Triple<Int, Int, List<String>> {
        var t1 = 0; var t3 = 0; val miss = ArrayList<String>()
        val ds = HashMap<SwipeLayout, SwipeDecoder>()
        for (t in traces) {
            val d = ds.getOrPut(t.layout) { SwipeDecoder(p).also { it.setLayout(t.layout) } }
            val full = SwipePractice.decode(d, t.path(), t.lang)
            val c = full.map { it.folded }
            if (System.getenv("SWIPE_ONLY") == t.folded) println("TUNE ONLY ${t.folded}: " +
                full.joinToString { String.format(Locale.ROOT, "%s %.2f", it.folded, it.score) })
            if (c.firstOrNull() == t.folded) t1++ else miss.add("${t.folded}→${c.firstOrNull()}")
            if (t.folded in c.take(3)) t3++
        }
        return Triple(t1, t3, miss)
    }

    private fun isolated(p: SwipeDecoder.Params, natural: Boolean, seed: Long, n: Int = 300): Pair<Double, Double> {
        val f = SwipeLexicon.forms
        val vn = (0 until f.count).filter { SwipeSim.collapse(f.folded[it]).length >= 2 }
            .sortedWith(compareBy({ -f.freq[it] }, { f.folded[it] })).take(n).map { f.folded[it] }
        val d = SwipeDecoder(p).also { it.setLayout(ios) }
        val sim = SwipeSim(seed)
        var t1 = 0; var t3 = 0
        val en = SwipePractice.english.take(100).map { it.word }
        for ((w, lang) in vn.map { it to SwipeLang.VI } + en.map { it to SwipeLang.EN }) {
            val path = if (natural) sim.natural(w, ios) else sim.path(w, ios)
            val c = SwipePractice.decode(d, path, lang).map { it.folded }
            if (c.firstOrNull() == w) t1++
            if (w in c.take(3)) t3++
        }
        val tot = (vn.size + en.size).toDouble()
        return t1 / tot to t3 / tot
    }

    private fun sentences(p: SwipeDecoder.Params, chains: List<List<String>>, natural: Boolean, seed: Long,
                          english: Boolean = true): Triple<Double, Double, Double> {
        val d = SwipeDecoder(p).also { it.setLayout(ios); it.prepare() }
        val sim = SwipeSim(seed)
        var n = 0; var t1 = 0; var t3 = 0; var ns = 0L
        for (chain in chains) for (i in 1 until chain.size) {
            val w = chain[i]
            val path = if (natural) sim.natural(SwipeSuggest.fold(w), ios) else sim.path(SwipeSuggest.fold(w), ios)
            val prior = if (english) SwipeLangContext.prior(SwipeLangContext.classify(chain[i - 1]),
                SwipeLangContext.classify(chain.getOrNull(i - 2))) else null
            val ctx = SwipeSuggest.context(null, chain[i - 1], chain.getOrNull(i - 2), prior)
            val t0 = System.nanoTime()
            val cands = d.decode(path, SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
            ns += System.nanoTime() - t0
            val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq) ?: continue
            n++
            if (c.word == w) t1++
            if (c.word == w || w in c.alternatives.take(2)) t3++
        }
        return Triple(t1.toDouble() / n, t3.toDouble() / n, ns / 1e6 / n)
    }

    private fun cfgs(): List<Cfg> {
        val b = SwipeDecoder.Params()
        val spec = System.getenv("SWIPE_CFGS") ?: "base"
        return spec.split(';').map { s ->
            var p = b
            for (kv in s.split(',')) {
                val (k, v) = if ('=' in kv) kv.split('=') else listOf(kv, "")
                p = when (k) {
                    "base" -> p
                    "legacy" -> p.copy(speedWeight = 0f, dwellWeight = 0f, overshoot = 0f)
                    "sw" -> p.copy(speedWeight = v.toFloat())
                    "sr" -> p.copy(speedRef = v.toFloat())
                    "dw" -> p.copy(dwellWeight = v.toFloat())
                    "dr" -> p.copy(dwellRatio = v.toFloat())
                    "ov" -> p.copy(overshoot = v.toFloat())
                    "tl" -> p.copy(tailSlow = v.toFloat())
                    "th" -> p.copy(tailFast = v.toFloat())
                    "ew" -> p.copy(endWeight = v.toFloat())
                    "es" -> p.copy(endSpan = v.toFloat())
                    "cw" -> p.copy(cornerWeight = v.toFloat())
                    "aw" -> p.copy(alignWeight = v.toFloat())
                    "sl" -> p.copy(sigmaLoc = v.toFloat())
                    "ss" -> p.copy(sigmaShape = v.toFloat())
                    "lam" -> p.copy(lambdaFreq = v.toFloat())
                    "lw" -> p.copy(lengthWeight = v.toFloat())
                    "tun" -> p.copy(tunnel = v.toFloat())
                    "am" -> p.copy(adaptMax = v.toFloat())
                    "at" -> p.copy(adaptThreshold = v.toFloat())
                    else -> error("khoá lạ $k")
                }
            }
            Cfg(s, p)
        }
    }

    @Test fun tune() {
        assumeTrue(System.getenv("SWIPE_TUNE") == "1")
        val real = System.getenv("SWIPE_TRACES")?.let { SwipePractice.parseExport(File(it).readText()) } ?: emptyList()
        val a = real.filterIndexed { i, _ -> i % 2 == 0 }; val b = real.filterIndexed { i, _ -> i % 2 == 1 }
        val all = heldout()
        val dev = all.filterIndexed { i, _ -> i % 12 == 0 }
        val test = all.filterIndexed { i, _ -> i % 12 == 6 }
        val what = (System.getenv("SWIPE_WHAT") ?: "real,iso,sent").split(',').toSet()
        val useTest = System.getenv("SWIPE_TEST") == "1"
        for (c in cfgs()) {
            val sb = StringBuilder(String.format(Locale.ROOT, "%-40s", c.name))
            if ("real" in what && real.isNotEmpty()) {
                val ra = realEval(a, c.p); val rb = realEval(b, c.p); val r = realEval(real, c.p)
                sb.append(String.format(Locale.ROOT, " | realA %2d/%d realB %2d/%d all %.3f/%.3f",
                    ra.first, a.size, rb.first, b.size, r.first.toDouble() / real.size, r.second.toDouble() / real.size))
                if (System.getenv("SWIPE_MISS") == "1") sb.append(" miss=" + r.third.joinToString(" "))
            }
            if ("iso" in what) {
                val nd = isolated(c.p, true, if (useTest) 2 else 1); val od = isolated(c.p, false, if (useTest) 2 else 1)
                sb.append(String.format(Locale.ROOT, " | isoNat %.3f/%.3f isoOld %.3f/%.3f", nd.first, nd.second, od.first, od.second))
            }
            if ("sent" in what) {
                val ch = if (useTest) test else dev
                val sn = sentences(c.p, ch, true, 2027); val so = sentences(c.p, ch, false, 2027)
                sb.append(String.format(Locale.ROOT, " | sentNat %.3f/%.3f sentOld %.3f/%.3f (%.3f ms)",
                    sn.first, sn.second, so.first, so.second, (sn.third + so.third) / 2))
            }
            println("TUNE " + sb)
        }
    }

    /** Vuốt tuần tự một câu như bàn phím (ngữ cảnh = từ đã hiện, bật tiếng Anh, sửa từ trước). */
    private val joint = System.getenv("SWIPE_JOINT") != "0"
    private val vb = System.getenv("SWIPE_VB")?.toFloat()
    private val vm = System.getenv("SWIPE_VM")?.toFloat() ?: 0.3f
    fun priorT(k1: SwipeLangContext.Kind, k2: SwipeLangContext.Kind): SwipeEnglishPrior =
        if (vb != null && k1 == SwipeLangContext.Kind.VI) SwipeEnglishPrior(vb, vm) else SwipeLangContext.prior(k1, k2)
    private fun env(k: String, d: String) = System.getenv(k) ?: d
    private val pw = env("SWIPE_PW", "${SwipeRevise.POOL_WORDS}").toInt()
    private val pm = env("SWIPE_PM", "${SwipeRevise.MAX_CANDIDATES}").toInt()
    private val nw = env("SWIPE_NW", "${SwipeRevise.NEXT_POOL_WORDS}").toInt()
    private val nm = env("SWIPE_NM", "${SwipeRevise.NEXT_MAX_CANDIDATES}").toInt()
    private val jw = env("SWIPE_JW", "${SwipeRevise.JOINT_WEIGHT}").toFloat()
    private val jm = env("SWIPE_JM", "${SwipeRevise.MARGIN}").toFloat()

    fun phrase(d: SwipeDecoder, words: List<String>, path: (String) -> SwipePath, english: Boolean = true): List<String> {
        val out = ArrayList<String>(); val eng = HashSet<Int>()
        var pending: List<SwipeWord> = emptyList()
        for ((i, word) in words.withIndex()) {
            val p1 = out.getOrNull(i - 1); val p2 = out.getOrNull(i - 2)
            val prior = if (!english) null else priorT(
                SwipeLangContext.classify(p1, (i - 1) in eng), SwipeLangContext.classify(p2, (i - 2) in eng))
            val ctx = SwipeSuggest.context(null, p1, p2, prior)
            val cands = d.decode(path(SwipeSuggest.fold(word)), SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
            val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq)
            var got = c?.word ?: ""
            if (c?.english == true) eng.add(i)
            var sc = if (c == null || c.english) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq, pw, pm)
            val nx = if (c == null || c.english) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq, nw, nm)
            if (p1 != null && pending.isNotEmpty() && got.isNotEmpty() && c?.english != true) {
                (if (joint) SwipeRevise.revise(pending, p1, p2, nx, margin = jm, weight = jw)
                 else SwipeRevise.revise(pending, p1, p2, got))?.let {
                    out[i - 1] = it
                    val nctx = SwipeSuggest.context(null, it, p2, prior)
                    val re = SwipeRevise.rerank(cands, ctx.word, ctx.lambdaFreq, nctx.word, nctx.lambdaFreq)
                    SwipeSuggest.choose(re, nctx.word, lambdaFreq = nctx.lambdaFreq)?.let { r ->
                        got = r.word; sc = if (r.english) emptyList() else SwipeRevise.scored(re, nctx.word, nctx.lambdaFreq, pw, pm)
                    }
                }
            }
            pending = sc
            out.add(got)
        }
        return out
    }

    @Test fun phraseViDu() {
        assumeTrue(System.getenv("SWIPE_TUNE") == "1")
        val words = (System.getenv("SWIPE_PHRASE") ?: "ví dụ như thế này").split(' ')
        for (c in cfgs()) {
            val d = SwipeDecoder(c.p).also { it.setLayout(ios) }
            val n = 40
            for (natural in listOf(true, false)) {
                val sim = SwipeSim(77)
                var okW = 0; var okS = 0; val sample = ArrayList<String>()
                repeat(n) {
                    val r = phrase(d, words, { w -> if (natural) sim.natural(w, ios) else sim.path(w, ios) })
                    okW += r.indices.count { r[it] == words[it] }
                    if (r == words) okS++
                    if (sample.size < 6) sample.add(r.joinToString(" "))
                }
                println(String.format(Locale.ROOT, "PHRASE %-30s %s từ %.3f câu %d/%d  ví dụ: %s", c.name,
                    if (natural) "nat" else "old", okW.toDouble() / (n * words.size), okS, n, sample.joinToString(" | ")))
            }
            val clean = phrase(d, words, { w -> SwipeSim(1).path(w, ios, sigma = 0.0, jitter = 0.0) })
            println("PHRASE ${c.name} sạch: ${clean.joinToString(" ")}")
        }
    }

    @Test fun sequential() {
        assumeTrue(System.getenv("SWIPE_TUNE") == "1")
        val all = heldout()
        val useTest = System.getenv("SWIPE_TEST") == "1"
        val ch = if (useTest) all.filterIndexed { i, _ -> i % 3 == 0 } else all.filterIndexed { i, _ -> i % 3 != 0 }.filterIndexed { i, _ -> i % 4 == 0 }
        val english = System.getenv("SWIPE_EN") == "1"
        for (c in cfgs()) {
            val d = SwipeDecoder(c.p).also { it.setLayout(ios) }
            val sb = StringBuilder(String.format(Locale.ROOT, "%-40s", c.name))
            for (natural in listOf(true, false)) {
                val sim = SwipeSim(2027)
                var n = 0; var ok = 0
                val t0 = System.nanoTime()
                for (chain in ch) {
                    val r = phrase(d, chain, { w -> if (natural) sim.natural(w, ios) else sim.path(w, ios) }, english)
                    n += chain.size; ok += chain.indices.count { r[it] == chain[it] }
                }
                sb.append(String.format(Locale.ROOT, " | seq%s %.4f (n=%d, %.3f ms/từ)", if (natural) "Nat" else "Old",
                    ok.toDouble() / n, n, (System.nanoTime() - t0) / 1e6 / n))
            }
            println("TUNE " + sb)
        }
    }


    /** Từ Anh chen sau từ Việt (phản chứng cho ưu tiên Việt): top-1 / có trên thanh gợi ý. */
    @Test fun englishAfterVietnamese() {
        assumeTrue(System.getenv("SWIPE_TUNE") == "1")
        val en = SwipePractice.english.take(120).map { it.word } +
            listOf("check", "file", "mail", "link", "online", "meeting", "deadline", "update", "app", "share", "email", "like")
        val prevs = listOf("tôi", "đang", "cho", "gửi", "mình", "đã")
        for (c in cfgs()) {
            val d = SwipeDecoder(c.p).also { it.setLayout(ios) }
            for (natural in listOf(true, false)) {
                val sim = SwipeSim(31)
                var n = 0; var t1 = 0; var bar = 0
                for ((k, w) in en.withIndex()) {
                    val p1 = prevs[k % prevs.size]
                    val ctx = SwipeSuggest.context(null, p1, null, priorT(SwipeLangContext.classify(p1), SwipeLangContext.Kind.NEUTRAL))
                    val path = if (natural) sim.natural(w, ios) else sim.path(w, ios)
                    val ch = SwipeSuggest.choose(d.decode(path, SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord),
                        ctx.word, lambdaFreq = ctx.lambdaFreq) ?: continue
                    n++
                    if (ch.word == w) t1++
                    if (ch.word == w || w in ch.alternatives) bar++
                }
                println(String.format(Locale.ROOT, "TUNE %-30s EN-sau-VN %s top1 %.3f thanh gợi ý %.3f (n=%d)", c.name,
                    if (natural) "nat" else "old", t1.toDouble() / n, bar.toDouble() / n, n))
            }
        }
    }
}
