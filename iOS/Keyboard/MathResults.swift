// MathResults — "Hiện kết quả phép tính" (như Math Results của bàn phím iOS gốc): văn bản
// trước con trỏ kết thúc bằng biểu thức + "=" ⇒ chip kết quả ở slot đầu thanh gợi ý, chạm
// để chèn sau dấu "=". Logic THUẦN (không UIKit/proxy) — bản Kotlin android MathResults.kt
// phải cho cùng kết quả trên fixture chung KeyboardTests/Fixtures/math-results.txt.
// Controller chỉ gọi `chip(before:)` NGAY SAU phím "=" (công tắc `mathResults`) — phím
// khác không tốn gì.
//
// Quy tắc:
// • Phép tính: + - − * × / ÷ : ^ ( ) %, trừ một ngôi. "x"/"X" là nhân CHỈ khi đứng giữa
//   hai số (trước: số / ")" / "%", sau: chữ số / "("). Không biến, không hàm.
//   Ưu tiên: ^ (kết hợp phải, cao hơn trừ một ngôi: -2^2 = -4) > * / > + -.
//   "A ± B%" = A ± A·B/100 (như máy tính điện thoại); còn lại "B%" = B/100.
// • Số: quy tắc phân cách của NumberChips.parseNumber — "," một lần là thập phân kiểu
//   Việt ("1,5"); "." là thập phân trừ khi là nhóm nghìn đúng 3 chữ số ("1.000" = 1000,
//   "1.000.000"); "," lặp là nhóm nghìn kiểu Anh ("1,000,000").
// • Kết quả: số nguyên nếu tròn; không thì tối đa 6 chữ số lẻ (≤12 chữ số có nghĩa), bỏ 0
//   cuối. Dấu thập phân theo kiểu người gõ: "." nếu biểu thức dùng "." thập phân hoặc ","
//   nhóm nghìn, còn lại "," (kiểu Việt). Chia nhóm nghìn chỉ khi biểu thức có chia nhóm.
// • Không chip: chia cho 0, tràn (|kết quả| ≥ 10^15, vô hạn, NaN), kết quả khác 0 mà làm
//   tròn thành 0, biểu thức dài quá 64 ký tự, biểu thức dính liền sau chữ cái ("abc12*3=").
import Foundation

enum MathResults {
    static let maxLength = 64

    struct Calc { let value: Double; let english: Bool; let grouped: Bool }

    private enum Tok: Equatable { case num(Double), op(Character), lp, rp, pct }

    private static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    /// Biểu thức (không có "=") → giá trị, nil nếu sai dạng / không phải phép tính thật.
    static func evaluate(_ expr: String) -> Calc? {
        let cs = Array(expr)
        guard cs.count <= maxLength else { return nil }
        var toks: [Tok] = []
        var english = false, grouped = false
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c == " " { i += 1; continue }
            if isDigit(c) {
                var j = i
                while j < cs.count, isDigit(cs[j]) || cs[j] == "." || cs[j] == "," { j += 1 }
                guard let lit = NumberChips.parseNumber(String(cs[i..<j])),
                      let v = Double(lit.value.int + (lit.value.frac.isEmpty ? "" : "." + lit.value.frac))
                else { return nil }
                if lit.decSep == "." || lit.groupSep == "," { english = true }
                if lit.groupSep != nil { grouped = true }
                toks.append(.num(v)); i = j; continue
            }
            switch c {
            case "+": toks.append(.op("+"))
            case "-", "\u{2212}": toks.append(.op("-"))
            case "*", "×": toks.append(.op("*"))
            case "x", "X":
                // chỉ giữa hai số: "12x3", "(1+2)x3", "2 x (3)"
                var k = i + 1
                while k < cs.count, cs[k] == " " { k += 1 }
                let prevOk: Bool
                switch toks.last {
                case .num?, .rp?, .pct?: prevOk = true
                default: prevOk = false
                }
                guard prevOk, k < cs.count, isDigit(cs[k]) || cs[k] == "(" else { return nil }
                toks.append(.op("*"))
            case "/", "÷", ":": toks.append(.op("/"))
            case "^": toks.append(.op("^"))
            case "(": toks.append(.lp)
            case ")": toks.append(.rp)
            case "%": toks.append(.pct)
            default: return nil
            }
            i += 1
        }
        // Phải có phép tính thật (không nhận "5" hay "-5" trơn).
        let hasOp = toks.enumerated().contains { k, t in
            if t == .pct { return true }
            if case .op = t { return k > 0 }
            return false
        }
        guard hasOp else { return nil }
        var p = 0
        func peek() -> Tok? { p < toks.count ? toks[p] : nil }
        func primary(_ depth: Int) -> Double? {
            guard depth < 32, let t = peek() else { return nil }
            switch t {
            case .num(let v): p += 1; return v
            case .lp:
                p += 1
                guard let v = expression(depth + 1), peek() == .rp else { return nil }
                p += 1; return v
            default: return nil
            }
        }
        /// primary [%] [^ unary] — trả (giá trị, là-phần-trăm).
        func power(_ depth: Int) -> (Double, Bool)? {
            guard let v = primary(depth) else { return nil }
            if peek() == .pct { p += 1; return (v / 100, true) }
            if peek() == .op("^") {
                p += 1
                guard let (e, _) = unary(depth + 1) else { return nil }
                return (pow(v, e), false)
            }
            return (v, false)
        }
        func unary(_ depth: Int) -> (Double, Bool)? {
            guard depth < 32 else { return nil }
            if peek() == .op("-") { p += 1; return unary(depth + 1).map { (-$0.0, false) } }
            if peek() == .op("+") { p += 1; return unary(depth + 1).map { ($0.0, false) } }
            return power(depth)
        }
        func term(_ depth: Int) -> (Double, Bool)? {
            guard var (v, isPct) = unary(depth) else { return nil }
            while let t = peek(), t == .op("*") || t == .op("/") {
                p += 1
                guard let (r, _) = unary(depth) else { return nil }
                if t == .op("/") { guard r != 0 else { return nil }; v /= r } else { v *= r }
                isPct = false
            }
            return (v, isPct)
        }
        func expression(_ depth: Int) -> Double? {
            guard var (v, _) = term(depth) else { return nil }
            while let t = peek(), t == .op("+") || t == .op("-") {
                p += 1
                guard var (r, isPct) = term(depth) else { return nil }
                if isPct { r *= v }
                v = t == .op("+") ? v + r : v - r
            }
            return v
        }
        guard let v = expression(0), p == toks.count, v.isFinite, abs(v) < 1e15 else { return nil }
        return Calc(value: v, english: english, grouped: grouped)
    }

    /// Kết quả theo kiểu số của biểu thức (quy tắc ở đầu file). nil = khác 0 nhưng quá nhỏ.
    static func format(_ c: Calc) -> String? {
        let a = abs(c.value)
        let intDigits = a < 1 ? 1 : String(format: "%.0f", a.rounded(.down)).count
        let decimals = max(0, min(6, 12 - intDigits))
        var s = String(format: "%.\(decimals)f", a)
        if s.contains(".") {
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
        }
        if s == "0", c.value != 0 { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        var intPart = String(parts[0])
        if c.grouped { intPart = NumberChips.group(intPart, sep: c.english ? "," : ".") }
        var out = intPart
        if parts.count > 1 { out += (c.english ? "." : ",") + parts[1] }
        if c.value < 0, out != "0" { out = "-" + out }
        return out
    }

    /// Biểu thức → chữ kết quả (fixture `eval`).
    static func result(_ expr: String) -> String? { evaluate(expr).flatMap(format) }

    private static let calcChars: Set<Character> = Set("0123456789.,+-\u{2212}*xX×/÷:^()% ")

    /// Chip cho văn bản trước con trỏ kết thúc bằng "=". Thử đuôi hợp lệ dài nhất rồi các
    /// đuôi sau khoảng trắng ("năm 2024 12*3=" → "12*3"). Chèn thêm sau "=" (replace rỗng).
    static func chip(before: String) -> NumberChip? {
        guard before.hasSuffix("=") else { return nil }
        let body = before.dropLast()
        let run = body.reversed().prefix { calcChars.contains($0) }
        let scanned = String(run.reversed())
        // Liền sau chữ cái ("abc12*3=", "v2+3=") ⇒ mã/tên, không phải phép tính.
        let glued = body.dropLast(run.count).last?.isLetter == true
        var candidates = glued ? [] : [scanned]
        for (k, ch) in scanned.enumerated() where ch == " " {
            candidates.append(String(scanned.dropFirst(k + 1)))
        }
        for cand in candidates {
            let e = cand.trimmingCharacters(in: .whitespaces)
            guard e.count <= maxLength, let f = e.first,
                  isDigit(f) || f == "(" || f == "-" || f == "\u{2212}",
                  let r = result(e) else { continue }
            return NumberChip(display: r, replace: "", insert: r)
        }
        return nil
    }
}
