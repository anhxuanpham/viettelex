package com.viettelex.keyboard

import java.text.Normalizer

/**
 * Chip tách số trên thanh gợi ý khi vừa copy: mã OTP, SĐT Việt Nam, số tài khoản.
 * Hàm thuần — iOS `ClipDetect.swift` port 1:1 (cùng test vector).
 *
 * Luật biên chung cho mọi dãy số: ký tự kề hai đầu KHÔNG là chữ/số, và không là một
 * trong `.,:/` nối sang một chữ số khác ("1,234,567", "12:30", "27/09" bị loại; "STK:123…"
 * hay "…123456." cuối câu vẫn nhận).
 */
data class ClipChip(val kind: Kind, val value: String, val label: String) {
    enum class Kind { OTP, PHONE, ACCOUNT }
}

object ClipDetect {
    const val MAX_LEN = 500

    private val OTP_KEYWORD = Regex(
        "\\b(otp|ma xac thuc|ma xac nhan|ma kich hoat|ma giao dich|code|verification|passcode)\\b")
    /** "mã" trần: chỉ tính khi có dãy 4–8 số trong [MA_WINDOW] ký tự sau nó. */
    private val MA_WORD = Regex("\\bma\\b")
    private const val MA_WINDOW = 50
    private val ACCOUNT_KEYWORD = Regex("\\b(stk|so tk|so tai khoan|tai khoan|tk|account|acc)\\b|\\ba/c\\b")
    private val MONEY_SUFFIX = Regex("^\\s*(vnd|dong|usd|d|k)(?![\\p{L}\\p{N}])")

    /** [groupEnds]: vị trí kết thúc (exclusive) + số chữ số tích luỹ của từng nhóm. */
    private class Run(val start: Int, val end: Int, val digits: String,
                      val groupEnds: List<Pair<Int, Int>> = emptyList())

    fun detect(text: String): List<ClipChip> {
        if (text.length > MAX_LEN || text.isBlank()) return emptyList()
        val folded = fold(text)
        val trimmed = text.trim()
        val out = ArrayList<ClipChip>(3)
        val taken = ArrayList<IntRange>()

        // --- OTP ---
        var otp: Run? = null
        if (trimmed.length in 4..8 && trimmed.all { it in '0'..'9' }) {
            val s = text.indexOf(trimmed)
            otp = Run(s, s + trimmed.length, trimmed)
        } else {
            val runs = runs(text, "").filter { it.digits.length in 4..8 && !moneyAfter(folded, it.end) }
            val kw = OTP_KEYWORD.find(folded)
            if (kw != null) {
                otp = runs.firstOrNull { it.start >= kw.range.first } ?: runs.firstOrNull()
            } else {
                for (m in MA_WORD.findAll(folded)) {
                    val e = m.range.last + 1
                    otp = runs.firstOrNull { it.start >= e && it.start - e <= MA_WINDOW }
                    if (otp != null) break
                }
            }
        }
        otp?.let { out += chip(ClipChip.Kind.OTP, it.digits); taken += it.start until it.end }

        // --- SĐT ---
        phone@ for (r in runs(text, " .-")) {
            val plus = r.start > 0 && text[r.start - 1] == '+'
            if (plus && r.start - 1 > 0 && !leftOk(text, r.start - 1)) continue
            // Gộp dần các nhóm từ đầu tới khi hợp lệ ("0912 345 678 99" → 0912345678).
            for ((gEnd, n) in r.groupEnds) {
                val phone = normalizePhone(r.digits.substring(0, n), plus) ?: continue
                val span = (if (plus) r.start - 1 else r.start) until gEnd
                if (taken.any { it.overlaps(span) }) continue
                out += chip(ClipChip.Kind.PHONE, phone); taken += span
                break@phone
            }
        }

        // --- STK ---
        val whole = trimmed.all { it in '0'..'9' || it == ' ' || it == '-' }
        val hasKw = ACCOUNT_KEYWORD.containsMatchIn(folded)
        for (r in runs(text, " -")) {
            val n = r.digits.length
            if (n !in 6..19) continue
            val span = r.start until r.end
            if (taken.any { it.overlaps(span) }) continue
            if (r.start > 0 && text[r.start - 1] == '+') continue
            if (moneyAfter(folded, r.end)) continue
            val ok = if (whole) n >= 9 else hasKw || n >= 9
            if (!ok) continue
            out += chip(ClipChip.Kind.ACCOUNT, r.digits); taken += span
            break
        }
        return out.sortedBy { it.kind.ordinal }.take(3)
    }

    fun label(kind: ClipChip.Kind, value: String): String {
        val shown = if (kind == ClipChip.Kind.OTP || value.length <= 6) value else value.take(4) + "…"
        return when (kind) {
            ClipChip.Kind.OTP -> "Dán OTP $shown"
            ClipChip.Kind.PHONE -> "Dán SĐT $shown"
            ClipChip.Kind.ACCOUNT -> "Dán STK $shown"
        }
    }

    private fun chip(kind: ClipChip.Kind, value: String) = ClipChip(kind, value, label(kind, value))

    /** +84/84 → 0; hợp lệ: di động 10 số đầu 03/05/07/08/09, bàn 11 số đầu 02. */
    internal fun normalizePhone(digits: String, plus: Boolean): String? {
        val d = when {
            digits.startsWith("84") && digits.length in 11..12 -> digits.substring(2).let { if (it.startsWith("0")) it else "0$it" }
            plus -> return null
            else -> digits
        }
        if (d.length == 10 && d[0] == '0' && d[1] in "35789") return d
        if (d.length == 11 && d.startsWith("02")) return d
        return null
    }

    private fun moneyAfter(folded: String, end: Int): Boolean =
        end <= folded.length && MONEY_SUFFIX.containsMatchIn(folded.substring(end))

    private fun isDigit(c: Char) = c in '0'..'9'
    private fun isAlnum(c: Char) = Character.isLetterOrDigit(c)

    private fun leftOk(s: String, i: Int): Boolean {
        if (i == 0) return true
        val c = s[i - 1]
        if (isAlnum(c)) return false
        if (c in ".,:/" && i >= 2 && isDigit(s[i - 2])) return false
        return true
    }

    private fun rightOk(s: String, j: Int): Boolean {
        if (j >= s.length) return true
        val c = s[j]
        if (isAlnum(c)) return false
        if (c in ".,:/" && j + 1 < s.length && isDigit(s[j + 1])) return false
        return true
    }

    /** Dãy số tối đa (phân cách đơn thuộc [seps] giữa 2 chữ số), đã qua luật biên. */
    private fun runs(s: String, seps: String): List<Run> {
        val out = ArrayList<Run>()
        var i = 0
        while (i < s.length) {
            if (!isDigit(s[i])) { i++; continue }
            val start = i
            val sb = StringBuilder()
            val groups = ArrayList<Pair<Int, Int>>()
            var j = i
            while (j < s.length) {
                val c = s[j]
                if (isDigit(c)) { sb.append(c); j++ }
                else if (c in seps && j + 1 < s.length && isDigit(s[j + 1])) { groups += j to sb.length; j++ }
                else break
            }
            groups += j to sb.length
            if (leftOk(s, start) && rightOk(s, j)) out += Run(start, j, sb.toString(), groups)
            i = j
        }
        return out
    }

    /** Bỏ dấu + lowercase, GIỮ nguyên độ dài (index khớp chuỗi gốc). */
    internal fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (c in s) {
            val base = when (c) {
                'đ', 'Đ' -> 'd'
                else -> {
                    val n = Normalizer.normalize(c.toString(), Normalizer.Form.NFD)
                    if (n.isNotEmpty()) n[0] else c
                }
            }
            sb.append(base.lowercaseChar())
        }
        return sb.toString()
    }

    private fun IntRange.overlaps(o: IntRange) = first <= o.last && o.first <= last
}

/** Heuristic "trông như bí mật" — mục nhạy cảm tự hết hạn sớm (2 phút) trong lịch sử. */
object ClipSensitivity {
    fun looksSecret(text: String): Boolean {
        val t = text.trim()
        if (t.isEmpty()) return false
        if (t.length in 4..8 && t.all { it in '0'..'9' }) return true
        if (t.length <= ClipDetect.MAX_LEN && ClipDetect.detect(t).any { it.kind == ClipChip.Kind.OTP }) return true
        if (t.any { it.isWhitespace() }) return false
        if (t.contains("://") || t.lowercase().startsWith("www.")) return false
        val at = t.indexOf('@')
        if (at > 0 && t.indexOf('.', at) > at + 1) return false
        val lower = t.any { it.isLowerCase() }
        val upper = t.any { it.isUpperCase() }
        val digit = t.any { it.isDigit() }
        val symbol = t.any { !it.isLetterOrDigit() }
        val classes = listOf(lower, upper, digit, symbol).count { it }
        if (t.length in 8..64 && classes >= 3) return true
        if (t.length >= 20 && (lower || upper) && digit) return true
        return false
    }
}
