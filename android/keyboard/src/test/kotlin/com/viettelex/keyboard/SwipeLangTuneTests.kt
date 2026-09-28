package com.viettelex.keyboard

import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.Locale

/**
 * Đo / chỉnh TIỀN NGHIỆM LIÊN TỤC NGÔN NGỮ (SwipeLangContext.prior(kinds)) — không chạy mặc định.
 * Vuốt TUẦN TỰ cả câu như bàn phím (ngữ cảnh = từ đã giải mã, nhãn Anh của từ vừa vuốt, sửa từ
 * trước bằng SwipeRevise), bật vuốt tiếng Anh, layout iPhone 36,8 pt, đường tự nhiên + đều.
 * Tập: câu Việt giữ lại (bigram-heldout dev %12==0 / test %12==6), câu Anh Tatoeba + câu trộn
 * (Fixtures/swipe-lang-sentences.txt, Scripts/gen-swipe-lang-eval.py). Từ 1 chữ (i, a) và từ
 * ngoài từ điển coi như GÕ (vào ngữ cảnh, không chấm).
 *
 *   SWIPE_LANG_TUNE=1 SWIPE_LANG_CFGS='old;base;vm=0.2' [SWIPE_TEST=1] ./gradlew --offline \
 *     :keyboard:test --tests '*SwipeLangTuneTests*' --rerun -i | grep LANG
 *
 * Khoá cấu hình: old = prior(prev1, prev2) trước 28/09 (2 từ, bảng rời); base = CONTINUITY;
 * d/eg/ec/vb/vm/vc = các trường của Continuity; w2 = chỉ 2 từ; loan = từ mượn vuốt ra Anh vẫn
 * trung tính.
 */
class SwipeLangTuneTests {
    @Before fun setUp() = TestAssets.install()

    private val ios = SwipeLayout.qwerty(keyWidth = 36.8f, rowHeight = 55f, originX = 3.5f, originY = 5f)

    data class Tok(val word: String, val en: Boolean)

    private fun fixture(): List<Triple<String, String, List<Tok>>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/swipe-lang-sentences.txt") }
            .first { it.exists() }
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { l ->
            val (part, kind, s) = l.split('\t')
            Triple(part, kind, s.split(' ').map { w ->
                if (kind == "en") Tok(w, true) else if (w.endsWith("/e")) Tok(w.dropLast(2), true) else Tok(w, false)
            })
        }
    }

    private fun heldout(): List<List<String>> {
        val f = listOf("../../iOS", "../iOS", "iOS").map { File(it, "KeyboardTests/Fixtures/bigram-heldout.txt") }
            .first { it.exists() }
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split(' ') }
    }

    class Cfg(val name: String, val prior: (List<SwipeLangContext.Kind>) -> SwipeEnglishPrior,
              val window: Int = 3, val loanNeutral: Boolean = false, val carry: Boolean = true)

    private fun cfgs(): List<Cfg> = (System.getenv("SWIPE_LANG_CFGS") ?: "old;base").split(';').map { s ->
        var c = SwipeLangContext.CONTINUITY
        var old = false; var window = 3; var loan = false; var nocarry = false
        for (kv in s.split(',')) {
            val (k, v) = if ('=' in kv) kv.split('=') else listOf(kv, "")
            when (k) {
                "base" -> {}
                "old" -> old = true
                "w2" -> window = 2
                "loan" -> loan = true
                "nocarry" -> nocarry = true
                "d" -> c = c.copy(decay = v.toFloat())
                "eb" -> c = c.copy(enBias = v.toFloat())
                "eg" -> c = c.copy(enGain = v.toFloat())
                "ec" -> c = c.copy(enCap = v.toFloat())
                "vb" -> c = c.copy(viBias = v.toFloat())
                "vm" -> c = c.copy(viMargin = v.toFloat())
                "vc" -> c = c.copy(viCap = v.toFloat())
                else -> error("khoá lạ $k")
            }
        }
        val cc = c
        Cfg(s, if (old) { k -> oldPrior(k.getOrElse(0) { SwipeLangContext.Kind.NEUTRAL }, k.getOrElse(1) { SwipeLangContext.Kind.NEUTRAL }) }
               else { k -> SwipeLangContext.prior(k, cc) }, if (old) 2 else window, loan, !old && !nocarry)
    }

    /** Bảng trước 28/09/2026 (để so). */
    private fun oldPrior(p1: SwipeLangContext.Kind, p2: SwipeLangContext.Kind): SwipeEnglishPrior = when {
        p1 == SwipeLangContext.Kind.EN && p2 == SwipeLangContext.Kind.EN -> SwipeEnglishPrior(0.5f, 0f)
        p1 == SwipeLangContext.Kind.EN -> SwipeLangContext.ENGLISH
        p1 == SwipeLangContext.Kind.NEUTRAL && p2 == SwipeLangContext.Kind.EN -> SwipeEnglishPrior(-0.3f, 0.3f)
        else -> SwipeLangContext.DEFAULT
    }

    /** Đếm theo nhóm: [0] = n, [1] = top-1 (đúng từ + đúng ngôn ngữ), [2] = có trên thanh (top-1 hoặc phương án). */
    class Acc { val m = LinkedHashMap<String, IntArray>()
        fun add(k: String, t1: Boolean, bar: Boolean) = m.getOrPut(k) { IntArray(3) }.also { it[0]++; if (t1) it[1]++; if (bar) it[2]++ }
        fun fmt(k: String) = m[k]?.let { String.format(Locale.ROOT, "%s %.4f/%.4f (n=%d)", k, it[1].toDouble() / it[0], it[2].toDouble() / it[0], it[0]) } ?: "$k -"
    }

    private fun swipeable(t: Tok): Boolean {
        val f = SwipeSuggest.fold(t.word)
        if (SwipeSim.collapse(f).length < 2) return false
        return if (t.en) SwipeEnglish.contains(f) else SwipeLexicon.indexOf(f) >= 0
    }

    /**
     * Vuốt tuần tự một câu. Trả (từ ra, nhãn Anh). Nhóm chấm: vi-vi / en-en (liền trước cùng ngôn
     * ngữ), en-sau-vi / vi-sau-en (đổi ngôn ngữ), đầu (không có từ trước).
     */
    fun phrase(d: SwipeDecoder, toks: List<Tok>, cfg: Cfg, path: (String) -> SwipePath, acc: Acc?, tag: String,
               carry: List<Pair<String, Boolean>> = emptyList()): List<Pair<String, Boolean>> {
        val out = ArrayList<String>(); val eng = ArrayList<Boolean>()
        var pending: List<SwipeWord> = emptyList()
        for ((i, t) in toks.withIndex()) {
            val p1 = out.getOrNull(i - 1); val p2 = out.getOrNull(i - 2)
            val kinds = (1..cfg.window).map { j ->
                val k = i - j
                val w = if (k >= 0) out[k] else if (cfg.carry) carry.getOrNull(carry.size + k)?.first else null
                val e = (if (k >= 0) eng[k] else carry.getOrNull(carry.size + k)?.second == true) && !(cfg.loanNeutral && w != null &&
                    com.viettelex.telexcore.EnglishContextLookup.isNeutralLoanword(w.lowercase()))
                SwipeLangContext.classify(w, e)
            }
            if (!swipeable(t)) { out.add(t.word); eng.add(t.en); pending = emptyList(); continue }
            val prior = cfg.prior(kinds)
            val ctx = SwipeSuggest.context(null, p1, p2, prior)
            val cands = d.decode(path(SwipeSuggest.fold(t.word)), SwipeSuggest.TOP_K, ctx.folded, ctx.english, ctx.englishWord)
            val c = SwipeSuggest.choose(cands, ctx.word, lambdaFreq = ctx.lambdaFreq)
            var got = c?.word ?: ""
            var gotEn = c?.english == true
            var alts = c?.alternatives ?: emptyList(); var altEn = c?.englishAlternatives ?: emptySet()
            var sc = if (c == null || c.english) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq)
            val nx = if (c == null || c.english) emptyList() else SwipeRevise.nextPool(cands, ctx.word, ctx.lambdaFreq)
            if (p1 != null && pending.isNotEmpty() && got.isNotEmpty() && !gotEn) {
                SwipeRevise.revise(pending, p1, p2, nx)?.let {
                    out[i - 1] = it
                    val nctx = SwipeSuggest.context(null, it, p2, prior)
                    val re = SwipeRevise.rerank(cands, ctx.word, ctx.lambdaFreq, nctx.word, nctx.lambdaFreq)
                    SwipeSuggest.choose(re, nctx.word, lambdaFreq = nctx.lambdaFreq)?.let { r ->
                        got = r.word; gotEn = r.english; alts = r.alternatives; altEn = r.englishAlternatives
                        sc = if (r.english) emptyList() else SwipeRevise.scored(re, nctx.word, nctx.lambdaFreq)
                    }
                }
            }
            pending = sc
            if (acc != null) {
                val prevEn = if (i == 0) null else toks[i - 1].en
                val grp = when (prevEn) { null -> if (carry.isNotEmpty() && cfg.carry) "cont" else "start"; t.en -> if (t.en) "en-en" else "vi-vi"; else -> if (t.en) "en-after-vi" else "vi-after-en" }
                val ok = got == t.word && gotEn == t.en
                val bar = ok || alts.any { it == t.word && (it in altEn) == t.en }
                acc.add("$tag:$grp", ok, bar)
                if (!ok && System.getenv("SWIPE_LANG_MISS")?.let { "$tag:$grp".contains(it) } == true)
                    println("LANGMISS $tag:$grp ${t.word}${if (t.en) "/e" else ""} → $got${if (gotEn) "/e" else ""} | ${kinds.joinToString(",")}")
                acc.add("$tag:all", ok, bar)
            }
            out.add(got); eng.add(gotEn)
        }
        return out.zip(eng)
    }

    @Test fun tune() {
        assumeTrue(System.getenv("SWIPE_LANG_TUNE") == "1")
        val useTest = System.getenv("SWIPE_TEST") == "1"
        val part = if (useTest) "test" else "dev"
        val fx = fixture().filter { it.first == part }
        val all = heldout()
        val vi = all.filterIndexed { i, _ -> i % 12 == (if (useTest) 6 else 0) }.map { s -> s.map { Tok(it, false) } }
        val sets = listOf("vi" to vi, "en" to fx.filter { it.second == "en" }.map { it.third },
            "mix" to fx.filter { it.second == "mix" }.map { it.third })
        for (cfg in cfgs()) {
            val d = SwipeDecoder().also { it.setLayout(ios) }
            val acc = Acc()
            val t0 = System.nanoTime()
            for (natural in listOf(true, false)) {
                val sim = SwipeSim(2027)
                val pth = { w: String -> if (natural) sim.natural(w, ios) else sim.path(w, ios) }
                for ((name, ss) in sets) {
                    // đoạn văn: 3 câu liền (cùng tập) — câu 2, 3 có ngữ cảnh NGÔN NGỮ của câu trước (qua dấu câu)
                    var carry: List<Pair<String, Boolean>> = emptyList()
                    for ((j, s) in ss.withIndex()) {
                        if (j % 3 == 0) carry = emptyList()
                        carry = phrase(d, s, cfg, pth, acc, (if (natural) "nat-" else "old-") + name, carry)
                    }
                }
            }
            val ms = (System.nanoTime() - t0) / 1e6
            println("LANG ${cfg.name} [$part] ${String.format(Locale.ROOT, "%.0f ms", ms)}")
            for (k in acc.m.keys.sorted()) println("LANG   ${cfg.name} ${acc.fmt(k)}")
        }
    }
}
