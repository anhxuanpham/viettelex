package com.viettelex.keyboard

import com.viettelex.telexcore.TelexEngine
import java.text.Normalizer

/**
 * Tìm emoji bằng tiếng Việt (port iOS EmojiSearch). Khoá = section SKEY của emoji.bin:
 * từ khoá gợi ý emoji sẵn có (EmojiSuggest) + tên/từ khoá CLDR vi. Khớp TIỀN TỐ KHÔNG DẤU
 * tại đầu một từ của khoá; hạng: trùng nguyên khoá có dấu > trùng không dấu > tiền tố có
 * dấu > tiền tố đầu khoá > tiền tố ở từ sau; cùng hạng thì khoá ngắn trước. Quét tuyến
 * tính trên blob mmap (không dựng map).
 */
object EmojiSearch {
    /** Luật fold PHẢI khớp Scripts/gen-emoji-data.py: thường, bỏ dấu (đ→d), dấu câu → space. */
    fun fold(s: String): String {
        val n = Normalizer.normalize(s.lowercase().replace('đ', 'd'), Normalizer.Form.NFD)
        val sb = StringBuilder(n.length)
        for (c in n) if (c.code !in 0x300..0x36F) sb.append(c)
        return clean(sb.toString())
    }

    /** Chữ thường NFC, ký tự không phải chữ/số → space, gộp space. */
    fun clean(s: String): String {
        val n = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFC)
        val sb = StringBuilder(n.length)
        var pending = false
        var i = 0
        while (i < n.length) {
            val cp = n.codePointAt(i)
            if (Character.isLetterOrDigit(cp)) {
                if (pending && sb.isNotEmpty()) sb.append(' ')
                pending = false
                sb.appendCodePoint(cp)
            } else pending = true
            i += Character.charCount(cp)
        }
        return sb.toString()
    }

    private class Index {
        val base = EmojiData.section("SKEY")
        val count = EmojiData.u32(base)
        val foldOff = base + 4
        val origOff = foldOff + (count + 1) * 4
        val idOff = origOff + (count + 1) * 4
        val foldBase = idOff + (count + 1) * 4
        val origBase = foldBase + EmojiData.u32(foldOff + count * 4)
        val idBase = origBase + EmojiData.u32(origOff + count * 4)
    }
    private val index by lazy { Index() }

    val keyCount: Int get() = index.count

    fun search(query: String, limit: Int = 60, supported: (Int) -> Boolean = EmojiData::isSupported): List<String> =
        ids(query, limit, supported).map(EmojiData::emoji)

    fun ids(query: String, limit: Int = 60, supported: (Int) -> Boolean = EmojiData::isSupported): List<Int> {
        val q = clean(query)
        val qf = fold(q).toByteArray(Charsets.UTF_8)
        if (qf.isEmpty()) return emptyList()
        val qo = q.toByteArray(Charsets.UTF_8)
        val x = index
        val buf = EmojiData.buf
        // (rank, len, key) gói vào Long để sort không cấp phát object.
        val hits = LongArray(x.count)
        var nh = 0
        for (k in 0 until x.count) {
            val fs = x.foldBase + buf.getInt(x.foldOff + k * 4)
            val fe = x.foldBase + buf.getInt(x.foldOff + k * 4 + 4)
            val pos = wordPrefix(fs, fe, qf)
            if (pos < 0) continue
            val os = x.origBase + buf.getInt(x.origOff + k * 4)
            val oe = x.origBase + buf.getInt(x.origOff + k * 4 + 4)
            val exactFold = pos == 0 && fe - fs == qf.size
            val rank = when {
                exactFold && equal(os, oe, qo) -> 0
                exactFold -> 1
                wordPrefix(os, oe, qo) >= 0 -> 2
                pos == 0 -> 3
                else -> 4
            }
            hits[nh++] = (rank.toLong() shl 50) or (minOf(fe - fs, 0xFFFF).toLong() shl 24) or k.toLong()
        }
        java.util.Arrays.sort(hits, 0, nh)
        val out = ArrayList<Int>()
        val seen = HashSet<Int>()
        for (h in 0 until nh) {
            val k = (hits[h] and 0xFFFFFF).toInt()
            val s = buf.getInt(x.idOff + k * 4); val e = buf.getInt(x.idOff + k * 4 + 4)
            for (j in s until e) {
                val id = EmojiData.u16(x.idBase + j * 2)
                if (seen.add(id) && supported(id)) {
                    out += id
                    if (out.size >= limit) return out
                }
            }
        }
        return out
    }

    /** Vị trí nơi [q] là tiền tố của một từ trong [s, e) (đầu khoá hoặc sau space); −1 nếu không. */
    private fun wordPrefix(s: Int, e: Int, q: ByteArray): Int {
        val buf = EmojiData.buf
        val n = q.size
        var i = s
        while (i + n <= e) {
            if (i == s || buf.get(i - 1) == 0x20.toByte()) {
                var j = 0
                while (j < n && buf.get(i + j) == q[j]) j++
                if (j == n) return i - s
            }
            i++
        }
        return -1
    }

    private fun equal(s: Int, e: Int, q: ByteArray): Boolean {
        if (e - s != q.size) return false
        val buf = EmojiData.buf
        for (j in q.indices) if (buf.get(s + j) != q[j]) return false
        return true
    }
}

/**
 * Ô tìm emoji tự vẽ: gõ bằng chính phím VietTelex, có Telex (engine RIÊNG — không đụng
 * composition của ô nhập thật). Thuần logic; KeyboardView lo vẽ.
 */
class EmojiSearchSession(settings: KeyboardSettings = KeyboardSettings()) {
    private val engine = TelexEngine().apply {
        freeMarking = settings.freeMarking
        simpleTelex = settings.simpleTelex
        liveSpellCheck = settings.liveSpellCheck
        quickTelex = settings.quickTelex
        modernTone = settings.modernTone
        teencode = settings.teencode
    }
    private val committed = StringBuilder()

    /** Chuỗi đang hiện trong ô tìm. */
    val query: String get() = committed.toString() + engine.peekCommitText(false)

    fun type(ch: Char) {
        val c = ch.lowercaseChar()
        if (c in 'a'..'z') engine.feed(c)
        else { commitWord(); committed.append(c) }
    }

    fun insert(s: String) { for (c in s) type(c) }

    fun space() {
        commitWord()
        if (committed.isNotEmpty() && committed.last() != ' ') committed.append(' ')
    }

    fun backspace() {
        if (!engine.isEmpty) engine.backspace()
        else if (committed.isNotEmpty()) committed.setLength(committed.length - 1)
    }

    fun clear() { engine.reset(); committed.setLength(0) }

    private fun commitWord() {
        if (engine.isEmpty) return
        committed.append(engine.commitText(true))
    }
}
