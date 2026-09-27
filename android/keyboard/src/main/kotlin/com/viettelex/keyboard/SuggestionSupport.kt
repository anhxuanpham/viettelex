package com.viettelex.keyboard

import kotlin.math.ln

/** Đệm thanh gợi ý cho đủ 3 (port iOS SuggestionFill). */
object SuggestionFill {
    fun pad(base: List<String>, with: List<String>, need: Int, excluding: String = ""): List<String> {
        if (base.size >= need) return base.take(need)
        val out = base.toMutableList()
        val seen = base.mapTo(HashSet()) { it.lowercase() }
        if (excluding.isNotEmpty()) seen.add(excluding.lowercase())
        for (c in with) {
            if (out.size >= need) break
            if (seen.add(c.lowercase())) out.add(c)
        }
        return out
    }
}

/**
 * Xếp hạng thanh gợi ý — logic THUẦN (song sinh iOS SuggestRank trong SuggestionSupport.swift;
 * sửa ở đây thì sửa y hệt bên kia). Hợp đồng: iOS/docs/IOS-SUGGESTIONS.md (tầng 1, 2, 7).
 *
 * Inline (đang gõ dở): `ln(freq+1) + 2.5·ln(count+1) + 4·[trong nextWords] + 1.5·[chỉ thiếu dấu]
 * + bigram`, bigram = min(cap, weight·PMI(âm tiết trước → ứng viên)) — nhân [Params.bigramDamp]
 * khi UserLangModel đã có ý kiến về chính lượt này (một ứng viên nằm trong nextWords): khi đó
 * cap·damp = 3.6 < 4 ⇒ ứng viên trong nextWords luôn hơn ứng viên chỉ có bigram (còn lại ngang
 * nhau) — cá nhân thắng. Không ứng viên nào trong nextWords (người dùng mới, prev lạ) ⇒ bigram đủ mạnh.
 *
 * Từ kế tiếp (sau dấu cách): nextWords cá nhân/seed trước; thiếu thì lấp bằng top âm tiết theo
 * bigram tĩnh sau từ trước (PMI + nextFreqWeight·freq/255 — PMI thuần nghiêng về cặp hiếm).
 */
object SuggestRank {
    data class Params(
        val bigramWeight: Double = BIGRAM_WEIGHT,
        val bigramCap: Double = BIGRAM_CAP,
        val bigramDamp: Double = BIGRAM_DAMP,
        val nextFreqWeight: Double = NEXT_FREQ_WEIGHT,
    )

    // chọn trên heldout (27/09/2026, lưới trong SuggestBigramTests.tuneGrid); cap·damp = 3.6 < 4
    const val BIGRAM_WEIGHT = 2.5
    const val BIGRAM_CAP = 8.0
    const val BIGRAM_DAMP = 0.45
    const val NEXT_FREQ_WEIGHT = 12.0
    val DEFAULT = Params()

    /**
     * Xếp pool VNSuggest (chưa lọc nhạy cảm). [pmi]\[i] = PMI bigram của pool\[i] (null = không
     * có âm tiết trước / bảng). Hoà điểm giữ thứ tự pool (tần suất tĩnh) — iOS y hệt.
     */
    fun rankInline(pool: List<VNSuggest.Match>, pmi: FloatArray?, typedLen: Int,
                   count: (String) -> Int, ctx: Set<String>, p: Params = DEFAULT): List<String> {
        val damp = if (pool.any { it.word in ctx }) p.bigramDamp else 1.0
        val scores = DoubleArray(pool.size) { i ->
            val m = pool[i]
            val b = pmi?.getOrNull(i)?.takeIf { it > 0f }?.let { minOf(p.bigramCap, p.bigramWeight * it) * damp } ?: 0.0
            ln(m.freq + 1.0) + 2.5 * ln(count(m.word) + 1.0) +
                (if (m.word in ctx) 4.0 else 0.0) + (if (Cp.count(m.word) == typedLen) 1.5 else 0.0) + b
        }
        return pool.indices.sortedWith { a, b ->
            val c = scores[b].compareTo(scores[a]); if (c != 0) c else a.compareTo(b)
        }.map { pool[it].word }
    }

    /** PMI bigram của từng ứng viên sau âm tiết [prev] (null nếu không có dữ liệu). Chạy nền. */
    fun inlinePmi(pool: List<VNSuggest.Match>, prev: String?,
                  big: SyllableBigram? = SyllableBigram.shared): FloatArray? {
        if (prev == null || big == null || pool.isEmpty()) return null
        val row = big.row(VNSuggest.lexiconId(prev))
        if (row.size == 0) return null
        return FloatArray(pool.size) { if (pool[it].id >= 0) row.score(pool[it].id) else 0f }
    }

    /** Top [limit] âm tiết hay theo sau [prev] theo bigram tĩnh (chữ thường, dạng lexicon). */
    fun bigramNext(prev: String, limit: Int, big: SyllableBigram? = SyllableBigram.shared,
                   p: Params = DEFAULT): List<String> {
        if (big == null || limit <= 0) return emptyList()
        val row = big.row(VNSuggest.lexiconId(prev))
        if (row.size == 0) return emptyList()
        val ids = IntArray(limit); val sc = DoubleArray(limit); var n = 0
        row.forEach { id, pmi ->
            val s = pmi + p.nextFreqWeight * VNSuggest.freq(id) / 255.0
            if (n == limit && s <= sc[n - 1]) return@forEach
            var j = if (n < limit) n++ else n - 1
            while (j > 0 && sc[j - 1] < s) { sc[j] = sc[j - 1]; ids[j] = ids[j - 1]; j-- }
            sc[j] = s; ids[j] = id
        }
        return List(n) { VNSuggest.display(ids[it]) }
    }
}

object TypingHeuristics {
    /** Double-space → ". " (hành vi Apple): trước space là chữ/số, không phải dấu câu. */
    fun doubleSpaceMakesPeriod(context: String, lastWasSpace: Boolean): Boolean {
        if (!lastWasSpace || !context.endsWith(" ")) return false
        val rest = context.dropLast(1)
        val prev = Cp.lastCodePoint(rest) ?: return false
        return !Character.isWhitespace(prev) && prev != '.'.code && prev != '!'.code &&
            prev != '?'.code && prev != ','.code
    }
}

/** Nhịp thời gian iOS (giây) cho IME. */
object TypingTimings {
    const val DOUBLE_SPACE_S = 0.35
    const val SUGGESTION_DEBOUNCE_MS = 30L
    const val SHIFT_DOUBLE_TAP_S = 0.3
    const val BACKSPACE_REPEAT_DELAY_S = 0.5
    const val BACKSPACE_REPEAT_INTERVAL_S = 0.09
    const val BACKSPACE_DOUBLE_AFTER_S = 1.6
    const val BACKSPACE_WORD_AFTER_S = 3.0
    const val BACKSPACE_WORD_EVERY_NTH_TICK = 4
    const val SPACE_TRACKPAD_HOLD_S = 0.4
    const val TRACKPAD_DP_PER_CHAR = 9f
    const val USERLM_SAVE_COALESCE_MS = 5000L
}
