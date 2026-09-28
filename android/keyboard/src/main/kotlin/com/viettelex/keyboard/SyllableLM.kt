package com.viettelex.keyboard

import java.nio.ByteBuffer
import java.text.Normalizer

/**
 * MÔ HÌNH NGÔN NGỮ ÂM TIẾT TRIGRAM tĩnh cho gõ vuốt (assets/vnlm.bin, GENERATED bởi
 * Scripts/gen-syllable-lm.py — nguồn/giấy phép: docs/DATA-SOURCES.md). Song sinh
 * iOS/Keyboard/SyllableLM.swift — sửa hành vi ở đây thì sửa y hệt bên kia.
 *
 * Kneser-Ney nội suy bậc 3 đã cắt tỉa. Điểm s (nat) của âm tiết c sau (a, b) =
 * ln(P(c|a,b) / P1(c)): > 0 = hay theo sau hơn bình thường, < 0 = hiếm. Thiếu mục ⇒ lùi:
 * dòng trigram (a,b) có mà thiếu c → γ3(ab) + s2(b,c); không có dòng → s2(b,c); bigram
 * thiếu → γ2(b).
 *
 * Cũng là nguồn BIGRAM của thanh gợi ý gõ chạm + Thêm dấu (thay vnbigram.bin cũ): [bigram]
 * trả PMI ≈ ln(P(c|b) / P(c)) = s2(b, c) + uniAdj(c), uniAdj = ln(P1(c)·N / c(c)) đổi mẫu số
 * từ P1 (continuation) sang tần suất thật.
 *
 * Layout (LE) — xem docstring script: 0 "VNM1" | 4 version=2 | 8 count | 12 lexHash |
 * 16 qPerNat | 20 biEntries | 24 triContexts | 28 triEntries | 32 reserved×4 |
 * 48 gamma2 i8[count] (pad 4) | biOff u32[count+1] | biNext u16[] | biScore i8[] (pad 4) |
 * ctxKey u32[] (a<<16|b tăng dần) | ctxOff u32[ctx+1] | ctxGamma i8[] | triNext u16[] |
 * triScore i8[] | uniAdj i8[count].
 *
 * Đọc TẠI CHỖ (mmap, absolute get — thread-safe), không giải mã vào heap.
 */
class SyllableLM private constructor(private val buf: ByteBuffer) {
    val count: Int = buf.getInt(8)
    private val qPerNat: Float = buf.getInt(16).toFloat()
    val biEntries: Int = buf.getInt(20)
    val triContexts: Int = buf.getInt(24)
    val triEntries: Int = buf.getInt(28)
    private val biOffBase = G2_BASE + pad4(count)
    private val biNextBase = biOffBase + (count + 1) * 4
    private val biScoreBase = biNextBase + biEntries * 2
    private val ctxKeyBase = biScoreBase + pad4(biEntries)
    private val ctxOffBase = ctxKeyBase + triContexts * 4
    private val ctxGammaBase = ctxOffBase + (triContexts + 1) * 4
    private val triNextBase = ctxGammaBase + triContexts
    private val triScoreBase = triNextBase + triEntries * 2
    private val adjBase = triScoreBase + triEntries
    val byteCount: Long = adjBase.toLong() + count

    private fun i8(off: Int): Float = buf.get(off) / qPerNat

    private fun find16(base: Int, lo: Int, hi: Int, key: Int): Int {
        var l = lo; var h = hi
        while (l < h) {
            val m = (l + h) ushr 1
            val v = buf.getShort(base + m * 2).toInt() and 0xFFFF
            if (v < key) l = m + 1 else if (v > key) h = m else return m
        }
        return -1
    }

    /** Ngữ cảnh đã tra sẵn cho một vị trí (1–2 âm tiết trước). */
    inner class Context internal constructor(
        private val g2: Float, private val biLo: Int, private val biHi: Int,
        /** triLo < 0 ⇒ không có dòng trigram cho (prev2, prev1). */
        private val triLo: Int, private val triHi: Int, private val g3: Float,
    ) {
        /** s (nat) của âm tiết id [w]. */
        fun score(w: Int): Float {
            if (w < 0 || w >= count) return 0f
            if (triLo >= 0) {
                val j = find16(triNextBase, triLo, triHi, w)
                if (j >= 0) return i8(triScoreBase + j)
            }
            val j = find16(biNextBase, biLo, biHi, w)
            val s2 = if (j >= 0) i8(biScoreBase + j) else g2
            return if (triLo >= 0) g3 + s2 else s2
        }
    }

    /** Ngữ cảnh sau ([prev2], [prev1]) — id vnlexicon, -1 = không có. null nếu prev1 không hợp lệ. */
    fun context(prev2: Int, prev1: Int): Context? {
        if (prev1 < 0 || prev1 >= count) return null
        val g2 = i8(G2_BASE + prev1)
        val lo = buf.getInt(biOffBase + prev1 * 4); val hi = buf.getInt(biOffBase + (prev1 + 1) * 4)
        var tLo = -1; var tHi = -1; var g3 = 0f
        if (prev2 in 0 until count) {
            val key = (prev2.toLong() shl 16) or prev1.toLong()
            var l = 0; var h = triContexts
            while (l < h) {
                val m = (l + h) ushr 1
                val v = buf.getInt(ctxKeyBase + m * 4).toLong() and 0xFFFFFFFFL
                if (v < key) l = m + 1 else if (v > key) h = m else {
                    tLo = buf.getInt(ctxOffBase + m * 4); tHi = buf.getInt(ctxOffBase + (m + 1) * 4)
                    g3 = i8(ctxGammaBase + m)
                    break
                }
            }
        }
        return Context(g2, lo, hi, tLo, tHi, g3)
    }

    /** s (nat) của [w] sau ([prev2], [prev1]); 0 nếu không có ngữ cảnh. */
    fun score(prev2: Int, prev1: Int, w: Int): Float = context(prev2, prev1)?.score(w) ?: 0f

    /** ln(P1(c)·N / c(c)) — đổi s2 (so với P1) thành PMI (so với tần suất thật). */
    fun uniAdj(w: Int): Float = if (w < 0 || w >= count) 0f else i8(adjBase + w)

    /**
     * Dải bigram của âm tiết trước — thanh gợi ý gõ chạm + Thêm dấu (thay vnbigram.bin).
     * [size] = 0 ⇒ âm tiết trước không có mục nào (không biết gì về nó).
     */
    inner class Bigram internal constructor(private val g2: Float,
                                            @PublishedApi internal val lo: Int, @PublishedApi internal val hi: Int) {
        val size: Int get() = hi - lo

        /** PMI (nat) của âm tiết sau id [next]; thiếu mục ⇒ lùi γ2(prev) + uniAdj; dải rỗng ⇒ 0. */
        fun pmi(next: Int): Float {
            if (lo >= hi || next < 0 || next >= count) return 0f
            val j = find16(biNextBase, lo, hi, next)
            return (if (j >= 0) i8(biScoreBase + j) else g2) + uniAdj(next)
        }

        /** PMI của mục tường minh; 0 nếu thiếu. */
        fun explicit(next: Int): Float {
            if (next < 0 || next >= count) return 0f
            val j = find16(biNextBase, lo, hi, next)
            return if (j >= 0) i8(biScoreBase + j) + uniAdj(next) else 0f
        }

        /** Duyệt mọi mục tường minh (id âm tiết sau, PMI) — thanh gợi ý lấy top từ kế tiếp. */
        inline fun forEach(action: (next: Int, pmi: Float) -> Unit) {
            for (m in lo until hi) { val c = biNextAt(m); action(c, biScoreAt(m) + uniAdj(c)) }
        }
    }

    @PublishedApi internal fun biNextAt(m: Int): Int = buf.getShort(biNextBase + m * 2).toInt() and 0xFFFF
    @PublishedApi internal fun biScoreAt(m: Int): Float = i8(biScoreBase + m)

    /** Dải bigram của âm tiết trước id [prev] (id vnlexicon). */
    fun bigram(prev: Int): Bigram {
        if (prev < 0 || prev >= count) return Bigram(0f, 0, 0)
        return Bigram(i8(G2_BASE + prev), buf.getInt(biOffBase + prev * 4), buf.getInt(biOffBase + (prev + 1) * 4))
    }

    companion object {
        private const val G2_BASE = 48
        const val VERSION = 2
        private fun pad4(n: Int) = (n + 3) and 3.inv()

        /** Kiểm tra header + khớp lexicon + kích thước; null nếu hỏng/lệch (chạy không LM). */
        fun load(buf: ByteBuffer, lexiconHash: Int, lexiconCount: Int): SyllableLM? {
            if (buf.capacity() < 48) return null
            if (buf.get(0) != 'V'.code.toByte() || buf.get(1) != 'N'.code.toByte() ||
                buf.get(2) != 'M'.code.toByte() || buf.get(3) != '1'.code.toByte()) return null
            if (buf.getInt(4) != VERSION || buf.getInt(8) != lexiconCount || buf.getInt(12) != lexiconHash) return null
            if (buf.getInt(16) <= 0 || buf.getInt(20) < 0 || buf.getInt(24) < 0 || buf.getInt(28) < 0) return null
            val lm = SyllableLM(buf)
            if (lm.byteCount != buf.capacity().toLong()) return null
            if (buf.getInt(lm.biOffBase + lm.count * 4) != lm.biEntries) return null
            if (buf.getInt(lm.ctxOffBase + lm.triContexts * 4) != lm.triEntries) return null
            return lm
        }

        /**
         * Mô hình dùng chung (gõ vuốt + thanh gợi ý + Thêm dấu — một lần map) — map lần đầu cần,
         * nên chạm lần đầu ở luồng nền (hash vnlexicon ~150KB). null nếu asset thiếu/hỏng/lệch.
         */
        val shared: SyllableLM? by lazy {
            try {
                load(KeyboardData.buffer(Keys.ASSET_LM),
                    fnv1a(KeyboardData.buffer(Keys.ASSET_LEXICON)), VNLexicon2Data.count)
            } catch (e: Exception) { null }
        }

        fun fnv1a(b: ByteBuffer): Int {
            var h = 0x811C9DC5.toInt()
            for (i in 0 until b.capacity()) {
                h = (h xor (b.get(i).toInt() and 0xFF)) * 0x01000193
            }
            return h
        }

        private val OLD_STYLE = mapOf(
            "oà" to "òa", "oá" to "óa", "oả" to "ỏa", "oã" to "õa", "oạ" to "ọa",
            "oè" to "òe", "oé" to "óe", "oẻ" to "ỏe", "oẽ" to "õe", "oẹ" to "ọe",
            "uỳ" to "ùy", "uý" to "úy", "uỷ" to "ủy", "uỹ" to "ũy", "uỵ" to "ụy",
        )

        /** NFC, chữ thường, kiểu dấu CŨ như vnlexicon (hoà → hòa; quý giữ nguyên). */
        fun normalize(w: String): String {
            val s = Normalizer.normalize(w.lowercase(), Normalizer.Form.NFC)
            if (s.length < 2) return s
            val pair = s.substring(s.length - 2)
            val rep = OLD_STYLE[pair] ?: return s
            if (pair[0] == 'u' && s.length >= 3 && s[s.length - 3] == 'q') return s
            return s.substring(0, s.length - 2) + rep
        }

        /** id vnlexicon của âm tiết [word] (đã normalize), -1 nếu không có. */
        fun idOf(word: String): Int {
            val w = normalize(word)
            val f = SwipeLexicon.indexOf(SwipeSuggest.fold(w))
            if (f < 0) return -1
            val forms = SwipeLexicon.forms
            for (id in forms.idStart[f] until forms.idStart[f + 1]) if (VNSuggest.display(id) == w) return id
            return -1
        }
    }
}
