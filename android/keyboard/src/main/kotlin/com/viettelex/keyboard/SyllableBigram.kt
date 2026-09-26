package com.viettelex.keyboard

import java.nio.ByteBuffer
import java.text.Normalizer

/**
 * Bảng BIGRAM ÂM TIẾT tĩnh (assets/vnbigram.bin, GENERATED bởi
 * Scripts/gen-syllable-bigram.py — nguồn/giấy phép: docs/DATA-SOURCES.md). Song sinh
 * iOS/Keyboard/SyllableBigram.swift — sửa hành vi ở đây thì sửa y hệt bên kia.
 *
 * Mỗi cặp (âm tiết trước a, âm tiết sau b) mang PMI chiết khấu (nat, ≥ 0.5) — mức
 * "b hay theo sau a hơn bình thường". Thiếu cặp = 0 (không biết). Gõ vuốt cộng điểm
 * này vào ngữ cảnh để chọn dấu (hôm → nay) và phân biệt cặp vuốt gần trùng (không → có).
 *
 * Layout (LE): 0 "VNB1" | 4 version=1 | 8 count (=vnlexicon) | 12 entries | 16 lexHash
 * (FNV-1a 32 của vnlexicon.bin) | 20 qPerNat | 24 reserved×2 | 32 offsets u32[count+1] |
 * next u16[entries] (tăng dần trong mỗi dải) | score u8[entries]. id = thứ tự vnlexicon.
 *
 * Đọc TẠI CHỖ (mmap, absolute get — thread-safe), không giải mã gì vào heap: RAM bẩn ≈ 0,
 * trang sạch chỉ nạp theo dải được tra. Tra O(log n) theo dải của âm tiết trước.
 */
class SyllableBigram private constructor(private val buf: ByteBuffer) {
    val count: Int = buf.getInt(8)
    val entries: Int = buf.getInt(12)
    private val qPerNat: Float = buf.getInt(20).toFloat()
    private val nextBase = 32 + (count + 1) * 4
    private val scoreBase = nextBase + entries * 2

    /** Dải cặp của một âm tiết trước. [size] = 0 ⇒ không có dữ liệu. */
    inner class Row internal constructor(private val lo: Int, private val hi: Int) {
        val size: Int get() = hi - lo
        /** PMI (nat) của âm tiết sau id [next]; 0 nếu không có cặp. */
        fun score(next: Int): Float {
            var l = lo; var h = hi
            while (l < h) {
                val m = (l + h) ushr 1
                val v = buf.getShort(nextBase + m * 2).toInt() and 0xFFFF
                if (v < next) l = m + 1 else if (v > next) h = m else
                    return (buf.get(scoreBase + m).toInt() and 0xFF) / qPerNat
            }
            return 0f
        }
    }

    /** Dải của âm tiết trước id [prev] (id vnlexicon). */
    fun row(prev: Int): Row {
        if (prev < 0 || prev >= count) return Row(0, 0)
        return Row(buf.getInt(32 + prev * 4), buf.getInt(32 + (prev + 1) * 4))
    }

    fun score(prev: Int, next: Int): Float = row(prev).score(next)

    companion object {
        const val Q_PER_NAT = 16

        /** Kiểm tra header + khớp lexicon; null nếu hỏng/lệch (gõ vuốt chạy không bigram). */
        fun load(buf: ByteBuffer, lexiconHash: Int, lexiconCount: Int): SyllableBigram? {
            if (buf.capacity() < 32) return null
            if (buf.get(0) != 'V'.code.toByte() || buf.get(1) != 'N'.code.toByte() ||
                buf.get(2) != 'B'.code.toByte() || buf.get(3) != '1'.code.toByte()) return null
            if (buf.getInt(4) != 1 || buf.getInt(8) != lexiconCount || buf.getInt(16) != lexiconHash) return null
            val count = buf.getInt(8); val entries = buf.getInt(12)
            if (entries < 0 || buf.getInt(20) <= 0) return null
            if (32L + (count + 1) * 4L + entries * 3L != buf.capacity().toLong()) return null
            if (buf.getInt(32 + count * 4) != entries) return null
            return SyllableBigram(buf)
        }

        /** Bảng dùng chung — map lần đầu cần (chỉ khi gõ vuốt bật). null nếu asset hỏng/lệch. */
        val shared: SyllableBigram? by lazy {
            try {
                load(KeyboardData.buffer(Keys.ASSET_BIGRAM),
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
