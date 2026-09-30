package com.viettelex.keyboard

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * "Hiện kết quả phép tính" (Math Results như bàn phím iOS gốc): chữ trước con trỏ kết thúc
 * bằng biểu thức + "=" ⇒ chip kết quả ở slot đầu, chạm để chèn sau "=". Port 1:1
 * iOS MathResults.swift, cùng kết quả trên fixture chung iOS/KeyboardTests/Fixtures/math-results.txt.
 * Quy tắc (phép tính, dấu phân cách, làm tròn, khi nào không có chip): xem đầu file Swift.
 * Session chỉ gọi [chip] NGAY SAU phím "=" — phím khác không tốn gì.
 */
object MathResults {
    const val MAX_LENGTH = 64

    class Calc(val value: Double, val english: Boolean, val grouped: Boolean)

    private sealed class Tok {
        data class Num(val v: Double) : Tok()
        data class Op(val c: Char) : Tok()
        object Lp : Tok()
        object Rp : Tok()
        object Pct : Tok()
    }

    private fun isDigit(c: Char) = c in '0'..'9'

    fun evaluate(expr: String): Calc? = (analyze(expr) as? Outcome.Ok)?.calc

    /** [Outcome.Conflict] = đúng dạng phép tính nhưng dấu phân cách mâu thuẫn ("1,5 * 2 + 2.5") —
     *  [chip] dừng hẳn, không thử đuôi ngắn hơn ("2 + 2.5"). */
    private sealed class Outcome {
        class Ok(val calc: Calc) : Outcome()
        object Invalid : Outcome()
        object Conflict : Outcome()
    }

    private fun analyze(expr: String): Outcome {
        if (expr.length > MAX_LENGTH) return Outcome.Invalid
        val toks = ArrayList<Tok>()
        val lits = ArrayList<String>()
        var i = 0
        while (i < expr.length) {
            val c = expr[i]
            if (c == ' ') { i++; continue }
            if (isDigit(c)) {
                var j = i
                while (j < expr.length && (isDigit(expr[j]) || expr[j] == '.' || expr[j] == ',')) j++
                lits += expr.substring(i, j)
                toks += Tok.Num(0.0); i = j; continue
            }
            toks += when (c) {
                '+' -> Tok.Op('+')
                '-', '−' -> Tok.Op('-')
                '*', '×' -> Tok.Op('*')
                'x', 'X' -> {
                    // chỉ giữa hai số: "12x3", "(1+2)x3", "2 x (3)"
                    var k = i + 1
                    while (k < expr.length && expr[k] == ' ') k++
                    val prev = toks.lastOrNull()
                    val prevOk = prev is Tok.Num || prev == Tok.Rp || prev == Tok.Pct
                    if (!prevOk || k >= expr.length || !(isDigit(expr[k]) || expr[k] == '(')) return Outcome.Invalid
                    Tok.Op('*')
                }
                '/', '÷', ':' -> Tok.Op('/')
                '^' -> Tok.Op('^')
                '(' -> Tok.Lp
                ')' -> Tok.Rp
                '%' -> Tok.Pct
                else -> return Outcome.Invalid
            }
            i++
        }
        val hasOp = toks.withIndex().any { (k, t) -> t == Tok.Pct || (t is Tok.Op && k > 0) }
        if (!hasOp) return Outcome.Invalid
        fun fill(values: List<Double>): List<Tok> {
            var n = 0
            return toks.map { if (it is Tok.Num) Tok.Num(values[n++]) else it }
        }
        return when (val nums = numbers(lits)) {
            Numbers.Malformed -> Outcome.Invalid
            // Giá trị 1 không chia 0 / tràn ⇒ parse được ⇔ đúng dạng phép tính.
            Numbers.Conflict -> if (parse(fill(lits.map { 1.0 })) != null) Outcome.Conflict else Outcome.Invalid
            is Numbers.Ok -> {
                val v = parse(fill(nums.values))
                if (v == null || !v.isFinite() || Math.abs(v) >= 1e15) Outcome.Invalid
                else Outcome.Ok(Calc(v, nums.dec == '.', nums.grouped))
            }
        }
    }

    private sealed class Numbers {
        class Ok(val values: List<Double>, val dec: Char?, val grouped: Boolean) : Numbers()
        object Malformed : Numbers()
        object Conflict : Numbers()
    }

    /** Các số của biểu thức → giá trị theo dấu phân cách suy từ CẢ biểu thức (quy tắc đầu
     *  MathResults.swift). `dec` = dấu thập phân đã suy (null: không có dấu nào). */
    private fun numbers(lits: List<String>): Numbers {
        val certDec = HashSet<Char>()
        val certGroup = HashSet<Char>()
        val ambiguous = HashSet<Char>()
        for (lit in lits) {
            if (!isDigit(lit.last())) return Numbers.Malformed
            val dots = lit.count { it == '.' }
            val commas = lit.count { it == ',' }
            if (dots > 0 && commas > 0) {
                val d = if (lit.lastIndexOf('.') > lit.lastIndexOf(',')) '.' else ','
                if ((if (d == '.') dots else commas) != 1) return Numbers.Malformed
                certDec += d; certGroup += if (d == '.') ',' else '.'
            } else if (dots + commas > 1) {
                certGroup += if (dots > 0) '.' else ','
            } else if (dots + commas == 1) {
                val s = if (dots > 0) '.' else ','
                val k = lit.indexOf(s)
                if (lit.length - k - 1 == 3 && k in 1..3 && lit[0] != '0') ambiguous += s else certDec += s
            }
        }
        if (certDec.size > 1 || certGroup.size > 1 || certDec.any { it in certGroup }) return Numbers.Conflict
        fun other(c: Char) = if (c == '.') ',' else '.'
        val dec: Char? = when {
            certDec.isNotEmpty() -> certDec.first()
            certGroup.isNotEmpty() -> other(certGroup.first())
            ambiguous.size > 1 -> return Numbers.Conflict
            ambiguous.isNotEmpty() -> other(ambiguous.first())
            else -> null
        }
        val values = ArrayList<Double>()
        var grouped = false
        for (lit in lits) {
            var intPart = lit
            var frac = ""
            val k = if (dec == null) -1 else lit.indexOf(dec)
            if (k >= 0) {
                intPart = lit.substring(0, k); frac = lit.substring(k + 1)
                if (dec!! in frac) return Numbers.Malformed
            }
            var digits = intPart
            if (dec != null && other(dec) in intPart) {
                val groups = intPart.split(other(dec))
                if (groups[0].length !in 1..3 || groups.drop(1).any { it.length != 3 }) return Numbers.Malformed
                digits = groups.joinToString(""); grouped = true
            }
            if (digits.isEmpty() || digits.length > NumberChips.MAX_DIGITS || frac.length > NumberChips.MAX_DIGITS ||
                !frac.all(::isDigit)) return Numbers.Malformed
            values += (digits + if (frac.isEmpty()) "" else ".$frac").toDoubleOrNull() ?: return Numbers.Malformed
        }
        return Numbers.Ok(values, dec, grouped)
    }

    private fun parse(toks: List<Tok>): Double? {
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
            /** primary [%] [^ unary] — (giá trị, là-phần-trăm). */
            fun power(depth: Int): Pair<Double, Boolean>? {
                val v = primary(depth) ?: return null
                if (peek() == Tok.Pct) { p++; return v / 100 to true }
                if (peek() == Tok.Op('^')) {
                    p++
                    val (e, _) = unary(depth + 1) ?: return null
                    return Math.pow(v, e) to false
                }
                return v to false
            }
            fun unary(depth: Int): Pair<Double, Boolean>? {
                if (depth >= 32) return null
                if (peek() == Tok.Op('-')) { p++; return unary(depth + 1)?.let { -it.first to false } }
                if (peek() == Tok.Op('+')) { p++; return unary(depth + 1)?.let { it.first to false } }
                return power(depth)
            }
            fun term(depth: Int): Pair<Double, Boolean>? {
                var (v, isPct) = unary(depth) ?: return null
                while (true) {
                    val t = peek()
                    if (t != Tok.Op('*') && t != Tok.Op('/')) break
                    p++
                    val (r, _) = unary(depth) ?: return null
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
        return if (parser.p == toks.size) v else null
    }

    /** Kết quả theo kiểu số của biểu thức; null = khác 0 nhưng làm tròn thành 0. */
    fun format(c: Calc): String? {
        val a = Math.abs(c.value)
        val intDigits = if (a < 1) 1 else BigDecimal(Math.floor(a)).toPlainString().length
        val decimals = maxOf(0, minOf(6, 12 - intDigits))
        // Làm tròn giá trị nhị phân CHÍNH XÁC, half-even — trùng printf của Swift.
        var s = BigDecimal(a).setScale(decimals, RoundingMode.HALF_EVEN).toPlainString()
        if (s.contains('.')) s = s.trimEnd('0').trimEnd('.')
        if (s == "0" && c.value != 0.0) return null
        val parts = s.split('.')
        var intPart = parts[0]
        if (c.grouped) intPart = NumberChips.group(intPart, if (c.english) ',' else '.')
        var out = intPart
        if (parts.size > 1) out += (if (c.english) "." else ",") + parts[1]
        if (c.value < 0 && out != "0") out = "-$out"
        return out
    }

    /** Biểu thức → chữ kết quả (fixture `eval`). */
    fun result(expr: String): String? = evaluate(expr)?.let(::format)

    private const val CALC_CHARS = "0123456789.,+-−*xX×/÷:^()% "

    /** Chip cho chữ trước con trỏ kết thúc bằng "=" (chèn thêm sau "=", replace rỗng). */
    fun chip(before: String): NumberChip? {
        if (!before.endsWith("=")) return null
        val body = before.dropLast(1)
        val scanned = body.takeLastWhile { it in CALC_CHARS }
        // Liền sau chữ cái ("abc12*3=", "v2+3=") ⇒ mã/tên, không phải phép tính.
        val glued = body.dropLast(scanned.length).lastOrNull()?.isLetter() == true
        val candidates = if (glued) arrayListOf() else arrayListOf(scanned)
        for ((k, ch) in scanned.withIndex()) if (ch == ' ') candidates += scanned.substring(k + 1)
        for (cand in candidates) {
            val e = cand.trim(' ')
            if (e.length > MAX_LENGTH) continue
            val f = e.firstOrNull() ?: continue
            if (!(isDigit(f) || f == '(' || f == '-' || f == '−')) continue
            val outcome = analyze(e)
            if (outcome == Outcome.Conflict) return null
            val r = (outcome as? Outcome.Ok)?.calc?.let(::format) ?: continue
            return NumberChip(r, "", r)
        }
        return null
    }
}
