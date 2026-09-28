package com.viettelex.keyboard

import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.time.Instant
import java.util.Locale

/**
 * BỘ ĐO CHỈNH decoder gõ vuốt (không chạy mặc định — SWIPE_TUNE=1). Đo trên CÙNG layout iPhone
 * (bước phím 36.8) với: nét THẬT (SWIPE_TRACES=file xuất từ Luyện vuốt — KHÔNG commit; tách tất
 * định 70 % chỉnh / 30 % giữ lại bằng [split]), từ rời + câu giữ lại với đường giả "đều"
 * (SwipeSim.path) và "tự nhiên" (SwipeSim.natural, hiệu chỉnh theo nét thật).
 * SWIPE_CFGS="nobend;base;bw=2,bb=0.1…" (khoá: xem [cfgs]; nobend = trước uốn h, legacy = trước
 * nhịp); SWIPE_TEST=1 ⇒ tập kiểm thử thay dev (lỗi in theo tập đó); SWIPE_MISS=1 ⇒ bảng lỗi dạng +
 * lỗi DẤU; SWIPE_ISOMISS=1 ⇒ lỗi từ rời; SWIPE_WORDS=chưa,của ⇒ top-1 từng từ trong câu (có ngữ
 * cảnh); SWIPE_JOINT=0 ⇒ sửa từ trước theo top-1 từ kế (cũ). Kết quả: docs/DATA-SOURCES.md
 * "Nét vuốt thật".
 *
 *   SWIPE_TUNE=1 SWIPE_TRACES=… SWIPE_CFGS='nobend;base' ./gradlew --offline :keyboard:test \
 *     --tests '*SwipeTuneTests.tune' --rerun -i | grep TUNE
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

    data class Real(val n: Int, val t1: Int, val t3: Int, val viN: Int, val viT1: Int, val acc: Int,
                    val miss: List<String>, val tone: List<String>) {
        fun fmt() = String.format(Locale.ROOT, "%.3f/%.3f vi %.3f en %.3f dấu %.3f (n=%d)", t1.toDouble() / n,
            t3.toDouble() / n, viT1.toDouble() / maxOf(1, viN), (t1 - viT1).toDouble() / maxOf(1, n - viN),
            acc.toDouble() / n, n)
    }

    private fun realEval(traces: List<SwipeTrace>, p: SwipeDecoder.Params): Real {
        var t1 = 0; var t3 = 0; var viN = 0; var viT1 = 0; var acc = 0
        val miss = ArrayList<String>(); val tone = ArrayList<String>()
        val ds = HashMap<SwipeLayout, SwipeDecoder>()
        for (t in traces) {
            val d = ds.getOrPut(t.layout) { SwipeDecoder(p).also { it.setLayout(t.layout) } }
            val full = SwipePractice.decode(d, t.path(), t.lang)
            val c = full.map { it.folded }
            if (System.getenv("SWIPE_ONLY") == t.folded) println("TUNE ONLY ${t.folded}: " +
                full.joinToString { String.format(Locale.ROOT, "%s %.2f", it.folded, it.score) })
            val vi = t.lang == SwipeLang.VI
            if (vi) viN++
            if (c.firstOrNull() == t.folded) {
                t1++; if (vi) viT1++
                // chấm cả DẤU (Luyện vuốt hiện từ có dấu): dạng đúng + dấu mạnh nhất = mục tiêu
                val top = if (full[0].lang == SwipeLang.EN) full[0].folded else SwipeDecoder.expand(full[0].folded, 1).firstOrNull()?.word
                if (top == t.target) acc++ else tone.add("${t.target}→$top")
            } else miss.add("${t.folded}→${c.firstOrNull()}")
            if (t.folded in c.take(3)) t3++
        }
        return Real(traces.size, t1, t3, viN, viT1, acc, miss, tone)
    }

    /**
     * Tách nét thật TẤT ĐỊNH 70 % chỉnh / 30 % giữ lại: phân tầng theo dạng mục tiêu (Luyện vuốt
     * lặp một từ tới khi đúng ⇒ các lần thử cùng từ tương quan), trong mỗi nhóm xếp theo băm chỉ
     * số, lần thứ k vào tập giữ lại khi (3k + băm(từ)) mod 10 < 3.
     */
    fun split(real: List<SwipeTrace>): Pair<List<SwipeTrace>, List<SwipeTrace>> {
        fun mix(v: Long): Long {
            var z = v * -0x61c8864680b583ebL
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }
        val dev = ArrayList<Int>(); val test = ArrayList<Int>()
        for ((w, idx) in real.indices.groupBy { real[it].folded }) {
            val order = idx.sortedBy { mix(it.toLong() + 1) }
            val off = ((mix(w.fold(7L) { h, ch -> h * 31 + ch.code }) ushr 1) % 10).toInt()
            for ((k, i) in order.withIndex()) if ((k * 3 + off) % 10 < 3) test.add(i) else dev.add(i)
        }
        return dev.sorted().map { real[it] } to test.sorted().map { real[it] }
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
            if (c.firstOrNull() == w) t1++ else if (System.getenv("SWIPE_ISOMISS") == "1")
                println("TUNE ISOMISS ${if (natural) "nat" else "old"} $w→${c.firstOrNull()}")
            if (w in c.take(3)) t3++
        }
        val tot = (vn.size + en.size).toDouble()
        return t1 / tot to t3 / tot
    }

    /** SWIPE_WORDS=chưa,của… ⇒ in top-1 từng từ trong câu giữ lại (có ngữ cảnh). */
    private val watch = System.getenv("SWIPE_WORDS")?.split(',')?.toSet() ?: emptySet()
    private val watchHits = HashMap<String, IntArray>()

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
            if (w in watch) watchHits.getOrPut(w) { IntArray(2) }.also { it[0]++; if (c.word == w) it[1]++ }
        }
        if (watch.isNotEmpty()) println("TUNE WORDS " + (if (natural) "nat " else "old ") + watch.joinToString(" ") { k ->
            watchHits[k]?.let { "$k ${it[1]}/${it[0]}" } ?: "$k -" })
        watchHits.clear()
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
                    "legacy" -> p.copy(speedWeight = 0f, dwellWeight = 0f, overshoot = 0f, bendWeight = 0f)
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
                    "nobend" -> p.copy(bendWeight = 0f)
                    "bw" -> p.copy(bendWeight = v.toFloat())
                    "bb" -> p.copy(bendBias = v.toFloat())
                    "bc" -> p.copy(bendCap = v.toFloat())
                    "bm" -> p.copy(bendMinChord = v.toFloat())
                    "bx" -> p.copy(bendMaxChord = v.toFloat())
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
        val all = heldout()
        val dev = all.filterIndexed { i, _ -> i % 12 == 0 }
        val test = all.filterIndexed { i, _ -> i % 12 == 6 }
        val what = (System.getenv("SWIPE_WHAT") ?: "real,iso,sent").split(',').toSet()
        val useTest = System.getenv("SWIPE_TEST") == "1"
        for (c in cfgs()) {
            val sb = StringBuilder(String.format(Locale.ROOT, "%-40s", c.name))
            if ("real" in what && real.isNotEmpty()) {
                val (dv, te) = split(real)
                val rd = realEval(dv, c.p); val rt = realEval(te, c.p)
                sb.append(" | realDev ").append(rd.fmt()).append(" realTest ").append(rt.fmt())
                if (System.getenv("SWIPE_MISS") == "1") {
                    val r = if (useTest) rt else rd
                    fun hist(l: List<String>) = l.groupingBy { it }.eachCount().entries.sortedBy { -it.value }
                        .joinToString(" ") { "${it.key}×${it.value}" }
                    sb.append("\nTUNE   miss=").append(hist(r.miss)).append("\nTUNE   dấu=").append(hist(r.tone))
                }
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

    /** In tần suất các dấu của từng dạng (SWIPE_FORMS=chua,cua…). */
    @Test fun forms() {
        assumeTrue(System.getenv("SWIPE_TUNE") == "1")
        val b = VNLexicon2Data.blob
        for (w in (System.getenv("SWIPE_FORMS") ?: "chua,cua").split(',')) {
            val f = SwipeLexicon.indexOf(w)
            if (f < 0) { println("TUNE FORM $w: không có"); continue }
            val fs = SwipeLexicon.forms
            println("TUNE FORM $w f=${fs.freq[f]} " + (fs.idStart[f] until fs.idStart[f + 1])
                .joinToString { "${VNSuggest.display(it)}:${b.freq(it)}" })
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
                    if (System.getenv("SWIPE_SEQDUMP") == "1") println("TUNE SEQ ${c.name} ${if (natural) "nat" else "old"} ${chain.joinToString(" ")} → ${r.joinToString(" ")}")
                    for (i in chain.indices) if (chain[i] in watch)
                        watchHits.getOrPut(chain[i]) { IntArray(2) }.also {
                            it[0]++; if (r[i] == chain[i]) it[1]++
                            else if (System.getenv("SWIPE_MISS") == "1") println("TUNE SEQMISS ${chain.joinToString(" ")} → ${r.joinToString(" ")}")
                        }
                }
                if (watch.isNotEmpty()) println("TUNE SEQWORDS ${c.name} " + (if (natural) "nat " else "old ") +
                    watch.joinToString(" ") { k -> watchHits[k]?.let { "$k ${it[1]}/${it[0]}" } ?: "$k -" })
                watchHits.clear()
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
