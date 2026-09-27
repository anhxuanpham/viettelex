package com.viettelex.keyboard

/**
 * SỬA LẠI TỪ VUỐT TRƯỚC khi đã biết từ kế (ngữ cảnh HAI PHÍA). Song sinh iOS
 * Keyboard/SwipeRevise.swift — sửa hằng số/hành vi ở đây thì sửa y hệt bên kia.
 *
 * Vuốt w1 chỉ biết ngữ cảnh trái (w0). Khi cú vuốt kế ra w2, chấm lại các ứng viên c của
 * w1 bằng điểm cũ (hình học + tần suất + ngữ cảnh trái, [scored]) + trigram phải
 * s(w2 | w0, c) (vnlm.bin) ·[RIGHT_WEIGHT] kẹp [[RIGHT_FLOOR], [RIGHT_CAP]]; ứng viên khác
 * thắng từ đang hiện ≥ [MARGIN] ⇒ thay. Chỉ từ Việt (LM là của âm tiết Việt), chỉ từ vuốt
 * liền trước, một lần. Caller lo fail-safe màn hình (đuôi phải khớp đúng từ cũ).
 *
 * Từ kế cũng có thể GÕ BẰNG PHÍM ([Typed]/[reviseTyped]): chấm lại lúc từ gõ được chốt
 * (dấu cách/dấu câu), ngữ cảnh phải = từ đã chốt (chắc chắn) với trọng số/lề riêng.
 *
 * Chi phí: ≤ [MAX_CANDIDATES] lần tra LM O(log n), chỉ sau một cú vuốt hoặc ở ranh giới từ
 * NGAY SAU từ vuốt — không ở đường phím chữ.
 */
object SwipeRevise {
    /** Chỉnh trên tập dev (SwipeReviseTests.sweep) — docs/DATA-SOURCES.md "Sửa lại từ vuốt trước". */
    const val RIGHT_WEIGHT = 0.1f
    const val RIGHT_CAP = 1.0f
    const val RIGHT_FLOOR = -1.0f
    const val MARGIN = 0.1f
    /**
     * Từ kế GÕ BẰNG PHÍM (chắc chắn, không phải từ vuốt đoán) ⇒ tin ngữ cảnh phải hơn, lề cao
     * hơn để giữ sửa sai thấp. Chỉnh riêng trên dev (SwipeReviseTests.sweepTyped).
     */
    const val TYPED_RIGHT_WEIGHT = 0.15f
    const val TYPED_MARGIN = 0.3f
    const val POOL_FORMS = 3
    const val POOL_WORDS = 4
    const val MAX_CANDIDATES = 8

    /**
     * Ứng viên tiếng Việt (chữ thường) của một cú vuốt + điểm tổng cùng thước decoder:
     * điểm dạng − điểm bung tốt nhất của dạng (= phần hình học) + điểm bung của âm tiết.
     * Rỗng khi top-1 là tiếng Anh. [wordCtx]/[lambdaFreq] = đúng cái đã dùng để chọn từ.
     */
    fun scored(cands: List<SwipeCandidate>, wordCtx: ((String) -> Float)?, lambdaFreq: Float): List<SwipeWord> {
        if (cands.isEmpty() || cands[0].lang != SwipeLang.VI) return emptyList()
        val out = ArrayList<SwipeWord>()
        for (c in cands.take(POOL_FORMS)) {
            if (c.lang != SwipeLang.VI) continue
            val ex = SwipeDecoder.expand(c.folded, POOL_WORDS, lambdaFreq, wordCtx)
            if (ex.isEmpty()) continue
            val geom = c.score - ex[0].score
            for (w in ex) out.add(SwipeWord(w.word, geom + w.score))
        }
        // ổn định: bằng điểm giữ thứ tự decoder
        return out.sortedByDescending { it.score }.take(MAX_CANDIDATES)
    }

    /**
     * Từ trước vừa được sửa ⇒ ngữ cảnh trái của cú vuốt này đổi: chấm lại ứng viên Việt =
     * hình học (điểm cũ − bung tốt nhất theo ngữ cảnh cũ) + bung tốt nhất theo ngữ cảnh mới,
     * xếp lại (ổn định). Ứng viên tiếng Anh giữ điểm (ngữ cảnh Anh không theo âm tiết trước).
     */
    fun rerank(cands: List<SwipeCandidate>, oldCtx: ((String) -> Float)?, oldLambda: Float,
               newCtx: ((String) -> Float)?, newLambda: Float): List<SwipeCandidate> =
        cands.map { c ->
            if (c.lang != SwipeLang.VI) c else {
                val old = SwipeDecoder.expand(c.folded, 1, oldLambda, oldCtx).firstOrNull()
                val new = SwipeDecoder.expand(c.folded, 1, newLambda, newCtx).firstOrNull()
                if (old == null || new == null) c else SwipeCandidate(c.folded, c.score - old.score + new.score)
            }
        }.sortedByDescending { it.score }

    /** Điểm phải: trigram s([next] | [prev], c) có trọng số, kẹp. 0 nếu thiếu dữ liệu. */
    fun rightScore(lm: SyllableLM, prevId: Int, candId: Int, nextId: Int, weight: Float = RIGHT_WEIGHT): Float {
        val s = lm.context(prevId, candId)?.score(nextId) ?: return 0f
        return maxOf(RIGHT_FLOOR, minOf(RIGHT_CAP, weight * s))
    }

    /**
     * Từ thay cho [current] (chữ thường, có dấu) khi biết từ kế [next]; null = giữ nguyên.
     * [prev] = từ trước [current] (ngữ cảnh trái của trigram phải).
     */
    fun revise(scored: List<SwipeWord>, current: String, prev: String?, next: String,
               lm: SyllableLM? = SyllableLM.shared, margin: Float = MARGIN,
               weight: Float = RIGHT_WEIGHT): String? {
        if (lm == null || scored.size < 2) return null
        val nextId = SyllableBigram.idOf(next)
        if (nextId < 0) return null
        val prevId = if (prev == null) -1 else SyllableBigram.idOf(prev)
        var cur = Float.NaN
        var best: String? = null
        var bestScore = Float.NEGATIVE_INFINITY
        for (w in scored) {
            val id = SyllableBigram.idOf(w.word)
            if (id < 0) continue
            val s = w.score + rightScore(lm, prevId, id, nextId, weight)
            if (w.word == current) cur = s
            if (s > bestScore) { bestScore = s; best = w.word }
        }
        if (cur.isNaN() || best == null || best == current) return null
        return if (bestScore - cur >= margin) best else null
    }

    /**
     * Từ vuốt Việt vừa được chốt bằng dấu cách (Android) / phím chữ hay dấu cách (iOS), chờ từ
     * gõ kế tiếp. [prev] = từ trước nó (ngữ cảnh trái của trigram phải).
     */
    class Typed(val word: String, val scored: List<SwipeWord>, val case: SwipeSuggest.Case, val prev: String?)

    /** Kết quả [reviseTyped]: thay đuôi [tail] (đang trên màn hình) bằng [replacement]. */
    class TypedEdit(val old: String, val new: String, val typed: String, val boundary: String) {
        /** Đuôi đang trên màn hình trước khi sửa. */
        val tail: String get() = "$old $typed$boundary"
        /** Đuôi sau khi sửa. */
        val replacement: String get() = "$new $typed$boundary"
    }

    /**
     * Từ gõ [typed] (dạng cuối đã chốt) vừa được ranh giới [boundary] chốt ngay sau từ vuốt
     * [p]: chấm lại từ vuốt. Chỉ khi chữ trước con trỏ [before] kết thúc ĐÚNG bằng
     * "từ vuốt + ␠ + từ gõ + ranh giới" và trước đó không dính chữ/số — lệch/không đọc được ⇒ null.
     */
    fun reviseTyped(p: Typed, typed: String, boundary: String, before: String?,
                    lm: SyllableLM? = SyllableLM.shared, margin: Float = TYPED_MARGIN,
                    weight: Float = TYPED_RIGHT_WEIGHT): TypedEdit? {
        if (typed.isEmpty() || boundary.isEmpty() || before == null) return null
        if (Character.isLetterOrDigit(boundary.codePointAt(0))) return null
        val tail = p.word + " " + typed + boundary
        if (!before.endsWith(tail)) return null
        val head = before.length - tail.length
        if (head > 0 && Character.isLetterOrDigit(before.codePointBefore(head))) return null
        val new = revise(p.scored, p.word.lowercase(), p.prev, typed.lowercase(), lm, margin, weight) ?: return null
        val cased = SwipeSuggest.applyCase(new, p.case)
        return if (cased == p.word) null else TypedEdit(p.word, cased, typed, boundary)
    }
}
