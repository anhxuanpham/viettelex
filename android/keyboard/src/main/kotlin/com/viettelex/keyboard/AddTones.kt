package com.viettelex.keyboard

import com.viettelex.telexcore.EnglishContextLookup
import kotlin.math.ln
import kotlin.math.min

/**
 * THÊM DẤU CHO CÂU KHÔNG DẤU ("toi di hoc hom nay" → "tôi đi học hôm nay") — phần THUẦN.
 * Song sinh iOS/Keyboard/AddTones.swift: sửa ở đây thì sửa y hệt bên kia (parity qua
 * fixture chung iOS/KeyboardTests/Fixtures/add-tones.txt).
 *
 * Chỉ chạy khi người dùng BẤM chip "Thêm dấu" — không bao giờ tự thay chữ.
 *
 * Giải thuật: Viterbi trên lưới âm tiết. Mỗi token chữ ASCII là một dạng không dấu của
 * vnlexicon (SwipeLexicon) → ứng viên = mọi âm tiết có dấu của dạng đó. Điểm (log, nat):
 *   phát xạ  = FREQ_W·freq/255 (freq byte = 255·ln(count)/ln(max) — tức ≈ log unigram)
 *              + PERSONAL_UNI·ln(1+count cá nhân)
 *   chuyển   = BIGRAM_W·PMI(âm tiết trước → âm tiết này) (vnbigram.bin; thiếu cặp khi âm tiết
 *              trước CÓ dải ⇒ MISSING) + PERSONAL_BI·ln(1+count cặp cá nhân)
 * Chuỗi bị cắt ở dấu câu / token giữ nguyên. GIỮ NGUYÊN: token không phải dạng Việt (tiếng
 * Anh, tên riêng lạ, số, URL, email, chữ có số/ký hiệu bên trong, camelCase), token có dấu.
 * Token vừa là dạng Việt vừa là từ Anh (the, can, to…) giữ nguyên khi kề một từ chắc chắn
 * Anh. Giữ hoa/thường từng chữ, dấu câu, khoảng trắng: kết quả DÀI BẰNG bản gốc (mỗi chữ
 * ASCII ↔ một chữ Việt dựng sẵn NFC).
 */
object AddTones {
    /** Trọng số — GIỮ Y HỆT bản Swift. Chọn bằng lưới trên heldout (AddTonesTests.tuneGrid). */
    data class Params(
        val freqW: Double = FREQ_W,
        val bigramW: Double = BIGRAM_W,
        val missing: Double = MISSING,
        val personalUni: Double = PERSONAL_UNI,
        val personalBi: Double = PERSONAL_BI,
    )

    const val FREQ_W = 10.0
    const val BIGRAM_W = 1.0
    const val MISSING = -0.5
    const val PERSONAL_UNI = 0.1
    const val PERSONAL_BI = 1.0
    /** Trần count cá nhân (đừng để một từ gõ nhiều lấn hết ngữ cảnh). */
    const val PERSONAL_CAP = 50
    /** Giới hạn độ dài xử lý (âm tiết ứng viên trong đoạn). */
    const val MAX_SYLLABLES = 200

    /** Dữ liệu cá nhân (UserLangModel) — null ⇒ chỉ dữ liệu tĩnh. */
    class Personal(val count: (String) -> Int, val pair: (String, String) -> Int)

    /** Kết quả khôi phục một đoạn. */
    class Result(val text: String, val vnTokens: Int, val enTokens: Int, val changed: Int)

    /**
     * Kế hoạch thay: xoá [original] (đuôi văn bản trước con trỏ) rồi chèn [replacement]
     * (cùng độ dài). Hoàn tác = làm ngược lại.
     */
    data class Plan(val original: String, val replacement: String)

    private const val PUNCT = ".,;:!?\"'()[]{}…“”‘’-–—«»"
    private fun isWs(c: Char) = c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ' '
    private fun isNl(c: Char) = c == '\n' || c == '\r'
    private fun isAsciiLetter(c: Char) = c in 'a'..'z' || c in 'A'..'Z'

    /** Chunk chứa chữ có dấu / chữ ngoài Latin ASCII ⇒ đã "có dấu", dừng đoạn. */
    private fun hasNonAsciiLetter(s: String): Boolean {
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            if (cp > 127 && Character.isLetter(cp)) return true
            i += Character.charCount(cp)
        }
        return false
    }

    /**
     * Đoạn cuối văn bản trước con trỏ để thêm dấu: các chunk (cách nhau khoảng trắng) liên
     * tiếp tính từ cuối, dừng ở xuống dòng, ở chunk đã có chữ có dấu, hoặc khi đủ
     * [MAX_SYLLABLES] token chữ. "" nếu không có gì.
     */
    fun segment(before: String): String {
        var end = before.length
        var start = end
        var tokens = 0
        while (end > 0) {
            var ws = end
            while (ws > 0 && isWs(before[ws - 1])) {
                if (isNl(before[ws - 1])) return before.substring(start)
                ws--
            }
            if (ws == 0) break
            var cs = ws
            while (cs > 0 && !isWs(before[cs - 1])) cs--
            val chunk = before.substring(cs, ws)
            if (hasNonAsciiLetter(chunk)) break
            if (chunk.any { isAsciiLetter(it) }) tokens++
            if (tokens > MAX_SYLLABLES) break
            start = cs
            end = cs
        }
        // khoảng trắng đầu đoạn không thuộc đoạn (để bản gốc giữ nguyên)
        while (start < before.length && isWs(before[start])) start++
        return before.substring(start)
    }

    private class Tok(val start: Int, val end: Int, val word: String, val breakBefore: Boolean,
                      val breakAfter: Boolean) {
        /** Dạng SwipeLexicon (-1 = không phải dạng Việt). */
        var form = -1
        var english = false   // chắc chắn Anh (không phải dạng Việt)
        var ambiguous = false // vừa dạng Việt vừa từ Anh
        var keep = false
    }

    /** Tách [text] thành token chữ ứng viên (kèm vị trí) — chunk khác giữ nguyên. */
    private fun tokenize(text: String): List<Tok?> {
        // null = chunk giữ nguyên (cắt chuỗi bigram)
        val out = ArrayList<Tok?>()
        var i = 0
        val n = text.length
        while (i < n) {
            if (isWs(text[i])) { i++; continue }
            var j = i
            while (j < n && !isWs(text[j])) j++
            var a = i; var b = j
            while (a < b && !isAsciiLetter(text[a])) a++
            while (b > a && !isAsciiLetter(text[b - 1])) b--
            val ok = a < b && (i until a).all { text[it] in PUNCT } && (b until j).all { text[it] in PUNCT } &&
                (a until b).all { isAsciiLetter(text[it]) }
            if (!ok) { out.add(null); i = j; continue }
            val core = text.substring(a, b)
            // camelCase / iPhone: có chữ hoa sau vị trí đầu mà không phải toàn hoa ⇒ giữ
            val upperInside = (1 until core.length).any { core[it].isUpperCase() }
            val allUpper = core.all { it.isUpperCase() }
            if (upperInside && !allUpper) { out.add(null); i = j; continue }
            out.add(Tok(a, b, core.lowercase(), a > i, b < j))
            i = j
        }
        return out
    }

    /** Phân loại token: dạng Việt / Anh / nhập nhằng + lan "giữ nguyên" từ từ Anh kề bên. */
    private fun classify(toks: List<Tok?>) {
        for (t in toks) {
            if (t == null) continue
            t.form = SwipeLexicon.indexOf(t.word)
            val en = SwipeEnglish.contains(t.word) || EnglishContextLookup.opensEnglishRun(t.word)
            if (t.form < 0) { t.keep = true; t.english = en && !EnglishContextLookup.isNeutralLoanword(t.word) }
            else if (en) t.ambiguous = true
        }
        // nhập nhằng kề (không qua dấu câu) một từ Anh ⇒ giữ nguyên, lan hai chiều tới khi ổn định
        var changed = true
        while (changed) {
            changed = false
            for (k in toks.indices) {
                val t = toks[k] ?: continue
                if (!t.ambiguous || t.keep) continue
                val p = if (k > 0 && !t.breakBefore) toks[k - 1]?.takeIf { !it.breakAfter } else null
                val q = if (k + 1 < toks.size && !t.breakAfter) toks[k + 1]?.takeIf { !it.breakBefore } else null
                if (p?.english == true || q?.english == true) {
                    t.keep = true; t.english = true; changed = true
                }
            }
        }
    }

    /** Khôi phục dấu cho [text] (một đoạn — thường là [segment]). Độ dài giữ nguyên. */
    fun restore(text: String, personal: Personal? = null, p: Params = Params(),
                bigram: SyllableBigram? = SyllableBigram.shared): Result {
        val toks = tokenize(text)
        classify(toks)
        val forms = SwipeLexicon.forms
        val chosen = arrayOfNulls<String>(toks.size)
        var vn = 0; var en = 0
        // Viterbi trên từng chuỗi token Việt liên tiếp
        var k = 0
        while (k < toks.size) {
            val t = toks[k]
            if (t == null || t.keep) { if (t?.english == true) en++; k++; continue }
            var e = k + 1
            while (e < toks.size) {
                val u = toks[e] ?: break
                if (u.keep || u.breakBefore || toks[e - 1]!!.breakAfter) break
                e++
            }
            vn += e - k
            viterbi(toks, k, e, forms, personal, p, bigram, chosen)
            k = e
        }
        val sb = StringBuilder(text)
        var changed = 0
        for (i in toks.indices) {
            val t = toks[i] ?: continue
            val w = chosen[i] ?: continue
            if (w == t.word) continue
            changed++
            for (c in 0 until t.end - t.start) {
                val orig = text[t.start + c]
                sb.setCharAt(t.start + c, if (orig.isUpperCase()) w[c].uppercaseChar() else w[c])
            }
        }
        return Result(sb.toString(), vn, en, changed)
    }

    private fun viterbi(toks: List<Tok?>, from: Int, to: Int, forms: SwipeLexicon.Forms,
                        personal: Personal?, p: Params, bigram: SyllableBigram?, chosen: Array<String?>) {
        val n = to - from
        val ids = Array(n) { i ->
            val f = toks[from + i]!!.form
            IntArray(forms.idStart[f + 1] - forms.idStart[f]) { forms.idStart[f] + it }
        }
        val words = Array(n) { i -> Array(ids[i].size) { VNSuggest.display(ids[i][it]) } }
        val score = Array(n) { DoubleArray(ids[it].size) }
        val back = Array(n) { IntArray(ids[it].size) }
        for (i in 0 until n) {
            val rows = if (i > 0 && bigram != null) Array(ids[i - 1].size) { bigram.row(ids[i - 1][it]) } else null
            for (s in ids[i].indices) {
                var emit = p.freqW * VNSuggest.freq(ids[i][s]) / 255.0
                if (personal != null) {
                    val c = min(personal.count(words[i][s]), PERSONAL_CAP)
                    if (c > 0) emit += p.personalUni * ln(1.0 + c)
                }
                if (i == 0) { score[i][s] = emit; back[i][s] = -1; continue }
                var best = Double.NEGATIVE_INFINITY; var arg = 0
                for (r in ids[i - 1].indices) {
                    var tr = 0.0
                    if (rows != null) {
                        val row = rows[r]
                        if (row.size > 0) {
                            val pmi = row.score(ids[i][s])
                            tr = if (pmi > 0f) p.bigramW * pmi else p.missing
                        }
                    }
                    if (personal != null) {
                        val c = min(personal.pair(words[i - 1][r], words[i][s]), PERSONAL_CAP)
                        if (c > 0) tr += p.personalBi * ln(1.0 + c)
                    }
                    val v = score[i - 1][r] + tr
                    if (v > best) { best = v; arg = r }
                }
                score[i][s] = best + emit
                back[i][s] = arg
            }
        }
        var s = 0
        for (x in 1 until score[n - 1].size) if (score[n - 1][x] > score[n - 1][s]) s = x
        for (i in n - 1 downTo 0) {
            chosen[from + i] = words[i][s]
            s = back[i][s]
        }
    }

    /**
     * Kế hoạch thêm dấu cho văn bản trước con trỏ; null nếu không nên mời (đoạn < 2 token
     * Việt, nghiêng tiếng Anh, hoặc không đổi gì). Kế hoạch chỉ gồm phần đuôi từ ký tự
     * khác đầu tiên — xoá ít nhất có thể.
     */
    fun plan(before: String, personal: Personal? = null, p: Params = Params()): Plan? {
        val seg = segment(before)
        if (seg.isEmpty()) return null
        val r = restore(seg, personal, p)
        if (r.vnTokens < 2 || r.enTokens >= r.vnTokens || r.changed == 0) return null
        var d = 0
        while (d < seg.length && seg[d] == r.text[d]) d++
        return Plan(seg.substring(d), r.text.substring(d))
    }
}
