package com.viettelex.keyboard

import com.viettelex.telexcore.EnglishContextLookup

/*
 * SwipeEnglish.kt — GÕ VUỐT giai đoạn 3: vuốt ra TỪ TIẾNG ANH xen trong câu tiếng Việt.
 * Bản song sinh của iOS/Keyboard/SwipeEnglish.swift — sửa ở đây thì sửa y hệt bên kia.
 *  - [SwipeEnglish.lexicon]: ~20k từ + tần suất 1 byte cùng thang vnlexicon
 *    (assets/enlexicon.bin, Scripts/gen-enlexicon.py; nguồn: docs/DATA-SOURCES.md).
 *    Không giữ template: decoder dựng template lúc chấm cho từ lọt lọc phím đầu/cuối.
 *  - [SwipeLangContext]: P(ngôn ngữ | 1–2 từ trước) → độ lệch + biên độ cho tiếng Anh.
 *    MẶC ĐỊNH NGHIÊNG TIẾNG VIỆT (the/thế, can/cần trùng hẳn nét vuốt).
 */

enum class SwipeLang { VI, EN }

object SwipeEnglish {
    class Lexicon(
        val words: Array<String>,   // chữ thường a–z, sort tăng dần
        val freq: IntArray,         // 0-255, thang vnlexicon
        val keys: ByteArray,        // phím gộp chữ lặp (0…25)
        val keyStart: IntArray,
        val order: IntArray,        // chỉ số từ xếp theo cặp (phím đầu·26 + phím cuối)
        val bucketStart: IntArray,  // 677
    ) { val count: Int get() = words.size }

    private val EMPTY = Lexicon(emptyArray(), IntArray(0), ByteArray(0), IntArray(1), IntArray(0), IntArray(677))

    @Volatile private var loaded: Lexicon? = null

    /**
     * Từ điển Anh (~1.4 MB heap: ~25k String) — nạp lười, thread-safe. IME [release] khi bàn
     * phím ẩn lâu và nạp lại NỀN lúc hiện ([isLoaded] cho biết có cần hâm nóng).
     */
    val lexicon: Lexicon
        get() = loaded ?: synchronized(this) {
            loaded ?: (try { parse(KeyboardData.buffer(Keys.ASSET_EN_LEXICON)) ?: EMPTY } catch (e: Exception) { EMPTY })
                .also { loaded = it }
        }

    val isLoaded: Boolean get() = loaded != null

    /** Bỏ bảng (GC được); lần dùng sau nạp lại. Ai đang giữ tham chiếu cũ vẫn dùng được. */
    fun release() { loaded = null }

    /** Giải mã enlexicon.bin ("VTE1" | count u32 | [len][freq][ASCII]…). null = hỏng. */
    fun parse(buf: java.nio.ByteBuffer): Lexicon? {
        val b = ByteArray(buf.capacity())
        val d = buf.duplicate(); d.position(0); d.get(b)
        if (b.size < 8 || b[0] != 0x56.toByte() || b[1] != 0x54.toByte() || b[2] != 0x45.toByte() || b[3] != 0x31.toByte()) return null
        val n = (b[4].toInt() and 255) or ((b[5].toInt() and 255) shl 8) or
            ((b[6].toInt() and 255) shl 16) or ((b[7].toInt() and 255) shl 24)
        val words = arrayOfNulls<String>(n)
        val freq = IntArray(n)
        val keys = ByteArray(b.size)
        val keyStart = IntArray(n + 1)
        val first = IntArray(n); val last = IntArray(n)
        var kc = 0
        var p = 8
        for (i in 0 until n) {
            if (p + 2 > b.size) return null
            val len = b[p].toInt() and 255
            val f = b[p + 1].toInt() and 255
            if (len == 0 || p + 2 + len > b.size) return null
            var prev = -1
            for (j in 0 until len) {
                val k = (b[p + 2 + j].toInt() and 255) - 97
                if (k !in 0 until 26) return null
                if (k != prev) { keys[kc++] = k.toByte(); prev = k }
            }
            first[i] = keys[keyStart[i]].toInt(); last[i] = keys[kc - 1].toInt()
            keyStart[i + 1] = kc
            words[i] = String(b, p + 2, len, Charsets.US_ASCII)
            freq[i] = f
            p += 2 + len
        }
        val bucketStart = IntArray(677)
        for (i in 0 until n) bucketStart[first[i] * 26 + last[i] + 1]++
        for (bk in 0 until 676) bucketStart[bk + 1] += bucketStart[bk]
        val fill = bucketStart.copyOf(676)
        val order = IntArray(n)
        for (i in 0 until n) { val bk = first[i] * 26 + last[i]; order[fill[bk]++] = i }
        @Suppress("UNCHECKED_CAST")
        return Lexicon(words as Array<String>, freq, keys.copyOf(kc), keyStart, order, bucketStart)
    }

    fun indexOf(word: String): Int {
        val a = lexicon.words
        var lo = 0; var hi = a.size
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (a[mid] < word) lo = mid + 1 else hi = mid
        }
        return if (lo < a.size && a[lo] == word) lo else -1
    }

    fun contains(word: String): Boolean = indexOf(word) >= 0

    /**
     * Chế độ Tiếng Anh (vuốt phím cách): từ bắt đầu bằng [typed] (a–z, không phân biệt hoa
     * thường), tần suất giảm dần, tối đa [limit], bỏ chính từ đang gõ. Chữ hoa theo chữ đang
     * gõ ("Hel" → "Hello", "HEL" → "HELLO"). Chữ ngoài a–z ⇒ rỗng. Giống iOS.
     */
    fun completions(typed: String, limit: Int = 24, lex: Lexicon = lexicon): List<VNSuggest.Match> {
        val low = typed.lowercase()
        if (low.isEmpty() || limit <= 0 || low.any { it !in 'a'..'z' }) return emptyList()
        val a = lex.words
        var lo = 0; var hi = a.size
        while (lo < hi) { val mid = (lo + hi) / 2; if (a[mid] < low) lo = mid + 1 else hi = mid }
        val hits = ArrayList<Int>()
        var i = lo
        while (i < a.size && a[i].startsWith(low)) { if (a[i] != low) hits.add(i); i++ }
        hits.sortWith { x, y -> if (lex.freq[x] != lex.freq[y]) lex.freq[y] - lex.freq[x] else x - y }
        return hits.take(limit).map { VNSuggest.Match(matchCase(a[it], typed), lex.freq[it]) }
    }

    /** Từ phổ biến nhất (đệm thanh gợi ý ở chế độ Tiếng Anh). */
    fun topWords(limit: Int, lex: Lexicon = lexicon): List<String> {
        if (limit <= 0) return emptyList()
        return lex.freq.indices.sortedWith { x, y -> if (lex.freq[x] != lex.freq[y]) lex.freq[y] - lex.freq[x] else x - y }
            .take(limit).map { lex.words[it] }
    }
    val top: List<String> by lazy { topWords(12) }

    fun matchCase(w: String, typed: String): String {
        val f = typed.firstOrNull() ?: return w
        if (!f.isUpperCase()) return w
        if (typed.length > 1 && typed.all { it.isUpperCase() }) return w.uppercase()
        return w.replaceFirstChar { it.uppercaseChar() }
    }
}

/** Tham số tiếng Anh cho một lần decode (xem [SwipeLangContext.prior]). */
data class SwipeEnglishPrior(
    /** Cộng vào điểm mọi ứng viên tiếng Anh (âm = nghiêng Việt). */
    val bias: Float,
    /** Tiếng Anh chỉ giữ top-1 khi hơn ứng viên Việt tốt nhất ≥ margin. */
    val margin: Float,
)

object SwipeLangContext {
    enum class Kind { VI, EN, NEUTRAL }

    // GIỮ Y HỆT bản Swift. Chọn bằng SwipeEnglishTests.sweepPriors (xem bản Swift).
    val DEFAULT = SwipeEnglishPrior(bias = -0.9f, margin = 0.3f)
    val ENGLISH = SwipeEnglishPrior(bias = 0.2f, margin = 0f)
    val STRONG_ENGLISH = SwipeEnglishPrior(bias = 0.5f, margin = 0f)
    val WEAK_ENGLISH = SwipeEnglishPrior(bias = -0.3f, margin = 0.3f)
    /** Chế độ Tiếng Anh: đẩy hẳn tiếng Anh lên (ứng viên Việt bị lọc sau decode). */
    val ONLY_ENGLISH = SwipeEnglishPrior(bias = 4f, margin = 0f)

    /** Phân loại một từ đã có trên màn hình; [swipedEnglish] = vừa vuốt ra như từ tiếng Anh. */
    fun classify(word: String?, swipedEnglish: Boolean = false): Kind {
        if (word.isNullOrEmpty()) return Kind.NEUTRAL
        if (swipedEnglish) return Kind.EN
        val w = word.lowercase()
        if (!w.all { it in 'a'..'z' }) return if (w.any { it.code > 127 }) Kind.VI else Kind.NEUTRAL
        if (EnglishContextLookup.isNeutralLoanword(w)) return Kind.NEUTRAL
        if (EnglishContextLookup.opensEnglishRun(w)) return Kind.EN
        val vnForm = SwipeLexicon.indexOf(w) >= 0
        if (SwipeEnglish.contains(w)) return if (vnForm) Kind.NEUTRAL else Kind.EN
        return if (vnForm) Kind.VI else Kind.NEUTRAL
    }

    fun prior(prev1: Kind, prev2: Kind): SwipeEnglishPrior = when {
        prev1 == Kind.EN && prev2 == Kind.EN -> STRONG_ENGLISH
        prev1 == Kind.EN -> ENGLISH
        prev1 == Kind.NEUTRAL && prev2 == Kind.EN -> WEAK_ENGLISH
        else -> DEFAULT
    }
}
