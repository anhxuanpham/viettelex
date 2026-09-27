package com.viettelex.keyboard

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Chip số trên thanh gợi ý: đọc số thành chữ, định dạng tiền, máy tính nhanh — port 1:1
 * iOS NumberChips.swift, cùng kết quả trên fixture chung iOS/KeyboardTests/Fixtures/number-chips.txt.
 * KHÔNG tự thay chữ: chỉ đề xuất chip, chạm mới áp dụng. Quy tắc: xem file Swift / IOS-SUGGESTIONS.md.
 */
data class NumberChip(
    /** Chữ hiện trên chip. */
    val display: String,
    /** Đuôi văn bản trước con trỏ sẽ bị thay (rỗng = chỉ chèn — máy tính). */
    val replace: String,
    /** Chữ chèn vào thay cho [replace]. */
    val insert: String,
)

object NumberChips {
    const val MAX_DIGITS = 30
    /** Số trơn dài hơn → coi là mã/số tài khoản, không đọc. */
    const val MAX_PLAIN_DIGITS = 12

    // MARK: số thập phân chính xác

    class Dec(negative: Boolean, int: String, frac: String) {
        val int: String = int.trimStart('0').ifEmpty { "0" }
        val frac: String = frac.trimEnd('0')
        val negative: Boolean = negative && !(this.int == "0" && this.frac.isEmpty())

        /** × 10^e — dời dấu phẩy, chính xác. */
        fun shifted(e: Int): Dec {
            val f = frac.padEnd(maxOf(frac.length, e), '0')
            return Dec(negative, int + f.substring(0, e), f.substring(e))
        }
    }

    class Literal(val value: Dec, val groupSep: Char?, val decSep: Char?)

    private fun isDigit(c: Char) = c in '0'..'9'

    /** Số viết bằng chữ số + "." "," theo quy tắc phân cách (xem NumberChips.swift). */
    fun parseNumber(s: String): Literal? {
        if (s.isEmpty() || !isDigit(s.first()) || !isDigit(s.last())) return null
        if (!s.all { isDigit(it) || it == '.' || it == ',' }) return null
        val dots = s.count { it == '.' }
        val commas = s.count { it == ',' }
        var groupSep: Char? = null
        var decSep: Char? = null
        if (dots > 0 && commas > 0) {
            decSep = if (s.lastIndexOf('.') > s.lastIndexOf(',')) '.' else ','
            groupSep = if (decSep == '.') ',' else '.'
            if ((if (decSep == '.') dots else commas) != 1) return null
        } else if (commas > 0) {
            if (commas == 1) decSep = ',' else groupSep = ','
        } else if (dots > 0) {
            if (dots > 1) groupSep = '.'
            else {
                val i = s.indexOf('.')
                val head = s.substring(0, i); val tail = s.substring(i + 1)
                if (tail.length == 3 && head.length in 1..3 && head.first() != '0') groupSep = '.'
                else decSep = '.'
            }
        }
        var intPart = s
        var frac = ""
        if (decSep != null) {
            val i = s.indexOf(decSep)
            intPart = s.substring(0, i); frac = s.substring(i + 1)
        }
        val digits: String
        if (groupSep != null) {
            val groups = intPart.split(groupSep)
            if (groups[0].length !in 1..3 || groups.drop(1).any { it.length != 3 } ||
                !groups.all { g -> g.all(::isDigit) }) return null
            digits = groups.joinToString("")
        } else {
            if (!intPart.all(::isDigit)) return null
            digits = intPart
        }
        if (digits.isEmpty() || !frac.all(::isDigit) || digits.length > MAX_DIGITS || frac.length > MAX_DIGITS) return null
        return Literal(Dec(false, digits, frac), groupSep, decSep)
    }

    // MARK: đọc số thành chữ

    private val DIGIT_WORDS = listOf("không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín")

    private fun readTriple(n: Int, full: Boolean, le: Boolean): List<String> {
        val h = n / 100; val t = (n / 10) % 10; val u = n % 10
        val w = ArrayList<String>()
        if (full || h > 0) { w += DIGIT_WORDS[h]; w += "trăm" }
        when (t) {
            0 -> if (u > 0) {
                if (w.isNotEmpty()) w += if (le) "lẻ" else "linh"
                w += DIGIT_WORDS[u]
            }
            1 -> {
                w += "mười"
                if (u == 5) w += "lăm" else if (u > 0) w += DIGIT_WORDS[u]
            }
            else -> {
                w += DIGIT_WORDS[t]; w += "mươi"
                when {
                    u == 1 -> w += "mốt"
                    u == 5 -> w += "lăm"
                    u > 0 -> w += DIGIT_WORDS[u]
                }
            }
        }
        return w
    }

    private fun readBelowBillion(n: Int, leading: Boolean, le: Boolean): List<String> {
        val out = ArrayList<String>()
        var first = leading
        for ((g, unit) in listOf(n / 1_000_000 to "triệu", (n / 1000) % 1000 to "nghìn", n % 1000 to "")) {
            if (g <= 0) continue
            out += readTriple(g, !first, le)
            if (unit.isNotEmpty()) out += unit
            first = false
        }
        return out
    }

    fun readInteger(digits: String, le: Boolean = false): String {
        if (digits.all { it == '0' }) return "không"
        val chunks = ArrayList<Int>()
        var rest = digits
        while (rest.isNotEmpty()) {
            chunks.add(0, rest.takeLast(9).toInt())
            rest = rest.dropLast(minOf(9, rest.length))
        }
        while (chunks.first() == 0) chunks.removeAt(0)
        val words = ArrayList(readBelowBillion(chunks[0], true, le))
        for (c in chunks.drop(1)) {
            words += "tỷ"
            if (c > 0) words += readBelowBillion(c, false, le)
        }
        return words.joinToString(" ")
    }

    fun read(d: Dec, le: Boolean = false): String {
        var s = readInteger(d.int, le)
        if (d.frac.isNotEmpty()) {
            val f = d.frac
            val fw = if (f.length <= 2 && f.first() != '0') readInteger(f, le)
            else f.map { DIGIT_WORDS[it - '0'] }.joinToString(" ")
            s += " phẩy $fw"
        }
        return if (d.negative) "âm $s" else s
    }

    /** Dạng chuẩn "-1250000,5" → chữ (test/fixture). */
    fun spell(canonical: String, le: Boolean = false): String? {
        val neg = canonical.startsWith("-")
        val s = if (neg) canonical.substring(1) else canonical
        val parts = s.split(',')
        if (parts.size !in 1..2 || parts.any { it.isEmpty() || !it.all(::isDigit) } || parts[0].length > MAX_DIGITS) return null
        return read(Dec(neg, parts[0], parts.getOrElse(1) { "" }), le)
    }

    // MARK: tiền

    private val MULTIPLIERS = mapOf(
        "k" to 3, "nghìn" to 3, "ngàn" to 3, "nghin" to 3, "ngan" to 3,
        "tr" to 6, "triệu" to 6, "trieu" to 6,
        "tỷ" to 9, "tỉ" to 9, "ty" to 9,
    )
    private val CURRENCIES = setOf("đ", "₫", "đồng", "vnd", "vnđ")

    class Amount(val value: Dec, val multiplier: Boolean, val currency: String?, val grouped: Boolean)

    fun parseAmount(token: String): Amount? {
        val words = token.split(' ')
        if (words.size !in 1..2) return null
        var w = words[0]
        val neg = w.startsWith("-") || w.startsWith("−")
        if (neg) w = w.substring(1)
        val numPart = w.takeWhile { isDigit(it) || it == '.' || it == ',' }
        val lit = parseNumber(numPart) ?: return null
        var suffix = w.substring(numPart.length)
        if (words.size == 2) {
            if (suffix.isNotEmpty() || words[1].isEmpty()) return null
            suffix = words[1]
        }
        val unitRaw = suffix.takeWhile { !isDigit(it) }
        val unit = unitRaw.lowercase()
        val tail = suffix.substring(unitRaw.length)
        if (!tail.all(::isDigit)) return null
        if (words.size == 2 && (unit.isEmpty() || tail.isNotEmpty())) return null
        val value = Dec(neg, lit.value.int, lit.value.frac)
        val grouped = lit.groupSep != null
        if (unit.isEmpty()) return Amount(value, false, null, grouped)
        val e = MULTIPLIERS[unit]
        if (e != null) {
            var v = value
            if (tail.isNotEmpty()) {
                if (lit.groupSep != null || lit.decSep != null || tail.length > 3) return null
                v = Dec(neg, lit.value.int, tail)
            }
            v = v.shifted(e)
            if (v.int.length > MAX_DIGITS) return null
            return Amount(v, true, null, grouped)
        }
        if (unit in CURRENCIES && tail.isEmpty()) return Amount(value, false, unit, grouped)
        return null
    }

    fun group(digits: String, sep: Char): String {
        val sb = StringBuilder()
        for ((i, c) in digits.withIndex()) {
            if (i > 0 && (digits.length - i) % 3 == 0) sb.append(sep)
            sb.append(c)
        }
        return sb.toString()
    }

    fun formatMoney(d: Dec, symbol: String = "₫"): String? {
        if (d.frac.isNotEmpty()) return null
        val body = (if (d.negative) "-" else "") + group(d.int, '.')
        return if (symbol == "đ") body + "đ" else "$body $symbol"
    }

    // MARK: máy tính nhanh

    private sealed class Tok {
        data class Num(val v: Double) : Tok()
        data class Op(val c: Char) : Tok()
        object Lp : Tok()
        object Rp : Tok()
        object Pct : Tok()
    }

    class Calc(val value: Double, val english: Boolean, val grouped: Boolean)

    fun evaluate(expr: String): Calc? {
        val toks = ArrayList<Tok>()
        var english = false
        var grouped = false
        var i = 0
        while (i < expr.length) {
            val c = expr[i]
            if (c == ' ') { i++; continue }
            if (isDigit(c)) {
                var j = i
                while (j < expr.length && (isDigit(expr[j]) || expr[j] == '.' || expr[j] == ',')) j++
                val lit = parseNumber(expr.substring(i, j)) ?: return null
                val v = (lit.value.int + if (lit.value.frac.isEmpty()) "" else "." + lit.value.frac).toDoubleOrNull()
                    ?: return null
                if (lit.decSep == '.' || lit.groupSep == ',') english = true
                if (lit.groupSep != null) grouped = true
                toks += Tok.Num(v); i = j; continue
            }
            toks += when (c) {
                '+' -> Tok.Op('+')
                '-', '−' -> Tok.Op('-')
                '*', 'x', 'X', '×' -> Tok.Op('*')
                '/', '÷', ':' -> Tok.Op('/')
                '(' -> Tok.Lp
                ')' -> Tok.Rp
                '%' -> Tok.Pct
                else -> return null
            }
            i++
        }
        val hasOp = toks.withIndex().any { (k, t) -> t == Tok.Pct || (t is Tok.Op && k > 0) }
        if (!hasOp) return null
        val parser = object {
            var p = 0
            fun peek(): Tok? = toks.getOrNull(p)
            fun primary(depth: Int): Double? {
                if (depth >= 32) return null
                return when (val t = peek()) {
                    is Tok.Num -> { p++; t.v }
                    Tok.Lp -> {
                        p++
                        val v = expression(depth + 1) ?: return null
                        if (peek() != Tok.Rp) return null
                        p++; v
                    }
                    else -> null
                }
            }
            fun factor(depth: Int): Pair<Double, Boolean>? {
                if (depth >= 32) return null
                if (peek() == Tok.Op('-')) { p++; return factor(depth + 1)?.let { -it.first to false } }
                if (peek() == Tok.Op('+')) { p++; return factor(depth + 1)?.let { it.first to false } }
                val v = primary(depth) ?: return null
                if (peek() == Tok.Pct) { p++; return v / 100 to true }
                return v to false
            }
            fun term(depth: Int): Pair<Double, Boolean>? {
                var (v, isPct) = factor(depth) ?: return null
                while (true) {
                    val t = peek()
                    if (t != Tok.Op('*') && t != Tok.Op('/')) break
                    p++
                    val (r, _) = factor(depth) ?: return null
                    if (t == Tok.Op('/')) { if (r == 0.0) return null; v /= r } else v *= r
                    isPct = false
                }
                return v to isPct
            }
            fun expression(depth: Int): Double? {
                var v = term(depth)?.first ?: return null
                while (true) {
                    val t = peek()
                    if (t != Tok.Op('+') && t != Tok.Op('-')) break
                    p++
                    var (r, isPct) = term(depth) ?: return null
                    if (isPct) r *= v
                    v = if (t == Tok.Op('+')) v + r else v - r
                }
                return v
            }
        }
        val v = parser.expression(0) ?: return null
        if (parser.p != toks.size || !v.isFinite() || Math.abs(v) >= 1e15) return null
        return Calc(v, english, grouped)
    }

    /** Kết quả: kiểu Việt mặc định, kiểu Anh nếu biểu thức dùng "." thập phân / "," phân nhóm. */
    fun formatResult(c: Calc): String {
        val a = Math.abs(c.value)
        val intDigits = if (a < 1) 1 else BigDecimal(Math.floor(a)).toPlainString().length
        val decimals = maxOf(0, minOf(10, 12 - intDigits))
        // Làm tròn giá trị nhị phân CHÍNH XÁC, half-even — trùng printf của Swift.
        var s = BigDecimal(a).setScale(decimals, RoundingMode.HALF_EVEN).toPlainString()
        if (s.contains('.')) s = s.trimEnd('0').trimEnd('.')
        val parts = s.split('.')
        var intPart = parts[0]
        if (c.grouped) intPart = group(intPart, if (c.english) ',' else '.')
        var out = intPart
        if (parts.size > 1) out += (if (c.english) "." else ",") + parts[1]
        if (c.value < 0 && out != "0") out = "-$out"
        return out
    }

    private const val CALC_CHARS = "0123456789.,+-−*xX×/÷:()% "

    fun calcChip(before: String): NumberChip? {
        if (!before.endsWith("=")) return null
        val body = before.dropLast(1)
        val scanned = body.takeLastWhile { it in CALC_CHARS }
        val candidates = arrayListOf(scanned)
        for ((k, ch) in scanned.withIndex()) if (ch == ' ') candidates += scanned.substring(k + 1)
        for (cand in candidates) {
            val e = cand.trim(' ', '\t')
            val f = e.firstOrNull() ?: continue
            if (!(isDigit(f) || f == '(' || f == '-' || f == '−')) continue
            val c = evaluate(e) ?: continue
            val r = formatResult(c)
            return NumberChip(r, "", r)
        }
        return null
    }

    // MARK: chip chính (quy tắc chọn: xem NumberChips.swift `chip(before:)`)

    fun chip(before: String, le: Boolean = false): NumberChip? {
        if (before.endsWith("=")) return calcChip(before)
        var ctx = before
        val hadSpace = ctx.endsWith(" ")
        if (hadSpace) ctx = ctx.dropLast(1)
        val last = ctx.lastOrNull() ?: return null
        if (last.isWhitespace()) return null
        fun lastWord(s: String): String = s.takeLastWhile { !it.isWhitespace() }
        val w1 = lastWord(ctx)
        var token = w1
        var amount = parseAmount(token)
        val rest1 = ctx.dropLast(w1.length)
        if (rest1.endsWith(" ")) {
            val w0 = lastWord(rest1.dropLast(1))
            if (w0.isNotEmpty()) {
                val a = parseAmount("$w0 $w1")
                if (a != null && (a.multiplier || a.currency != null)) { token = "$w0 $w1"; amount = a }
            }
        }
        val a = amount ?: return null
        val prefix = ctx.dropLast(token.length)
        val cur = a.currency
        val text: String? = when {
            a.multiplier -> formatMoney(a.value, "₫")
            cur != null ->
                if ((cur == "đ" || cur == "₫") && !a.grouped && a.value.int.length >= 4 && a.value.frac.isEmpty())
                    formatMoney(a.value, cur)
                else read(a.value, le) + " đồng"
            else -> {
                val plain = !a.grouped && !token.contains(',') && !token.contains('.')
                val digits = token.filter(::isDigit)
                if (plain && ((digits.length > 1 && digits.first() == '0') || digits.length > MAX_PLAIN_DIGITS)) return null
                read(a.value, le)
            }
        }
        var t = text ?: return null
        if (atSentenceStart(prefix) && t.first().isLetter()) t = t.first().uppercase() + t.substring(1)
        val sp = if (hadSpace) " " else ""
        return NumberChip(t, token + sp, t + sp)
    }

    fun atSentenceStart(prefix: String): Boolean {
        if (prefix.endsWith("\n")) return true
        val c = prefix.trimEnd(' ', '\t').lastOrNull() ?: return true
        return c == '.' || c == '!' || c == '?' || c == '\n'
    }
}
