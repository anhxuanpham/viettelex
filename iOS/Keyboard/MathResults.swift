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
// • Số: "," / "." suy từ CẢ biểu thức (một quy tắc tất định, #bug "26,160*2,500=" → "65,4"):
//   – Trong một số: "."/"," lặp ("1.000.000") hoặc có cả hai ("1.000,5": dấu CUỐI là thập
//     phân, dấu kia nhóm nghìn) ⇒ CHẮC nhóm nghìn; một dấu duy nhất mà KHÔNG phải dạng
//     "d,ddd"/"dd.ddd"/"ddd,ddd" (1–3 chữ số không bắt đầu bằng 0, rồi đúng 3 chữ số) ⇒
//     CHẮC thập phân ("1,5", "0.500", "1234,567"); còn lại MƠ HỒ ("2,500", "26.163").
//   – Cả biểu thức: có dấu CHẮC thập phân ⇒ nó là thập phân (kể cả ở số mơ hồ: "1,5+2,500"
//     = 4), dấu kia là nhóm nghìn; không có mà có dấu CHẮC nhóm ⇒ dấu kia là thập phân;
//     chỉ có số mơ hồ ⇒ nhóm nghìn ("2,500" = 2500, "1.500" = 1500).
//   – Mâu thuẫn (cả hai dấu đều thập phân "1,5+2.5", cả hai đều nhóm, một dấu vừa thập
//     phân vừa nhóm, hay hai dấu mơ hồ khác nhau "1,500+2.500") ⇒ KHÔNG chip (chip() cũng
//     không lùi sang đuôi ngắn hơn như "2 + 2.5").
// • Kết quả: số nguyên nếu tròn; không thì tối đa 6 chữ số lẻ (≤12 chữ số có nghĩa), bỏ 0
//   cuối. Dấu thập phân = dấu thập phân đã suy (có dấu nhóm mà không có thập phân ⇒ dấu
//   kia: "," nhóm → "." thập phân và ngược lại); biểu thức không có dấu nào ⇒ "," (kiểu
//   Việt). Chia nhóm nghìn (bằng dấu kia) chỉ khi biểu thức có số dùng nhóm nghìn.
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
        if case .ok(let c) = analyze(expr) { return c }
        return nil
    }

    /// `.conflict` = đúng dạng phép tính nhưng dấu phân cách mâu thuẫn ("1,5 * 2 + 2.5") —
    /// chip() dừng hẳn, không thử đuôi ngắn hơn ("2 + 2.5").
    private enum Outcome { case ok(Calc), invalid, conflict }

    private static func analyze(_ expr: String) -> Outcome {
        let cs = Array(expr)
        guard cs.count <= maxLength else { return .invalid }
        var toks: [Tok] = []
        var lits: [String] = []
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c == " " { i += 1; continue }
            if isDigit(c) {
                var j = i
                while j < cs.count, isDigit(cs[j]) || cs[j] == "." || cs[j] == "," { j += 1 }
                lits.append(String(cs[i..<j]))
                toks.append(.num(0)); i = j; continue
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
                guard prevOk, k < cs.count, isDigit(cs[k]) || cs[k] == "(" else { return .invalid }
                toks.append(.op("*"))
            case "/", "÷", ":": toks.append(.op("/"))
            case "^": toks.append(.op("^"))
            case "(": toks.append(.lp)
            case ")": toks.append(.rp)
            case "%": toks.append(.pct)
            default: return .invalid
            }
            i += 1
        }
        // Phải có phép tính thật (không nhận "5" hay "-5" trơn).
        let hasOp = toks.enumerated().contains { k, t in
            if t == .pct { return true }
            if case .op = t { return k > 0 }
            return false
        }
        guard hasOp else { return .invalid }
        func fill(_ values: [Double]) -> [Tok] {
            var n = 0
            return toks.map { t in
                guard case .num = t else { return t }
                defer { n += 1 }
                return .num(values[n])
            }
        }
        switch numbers(lits) {
        case .malformed: return .invalid
        case .conflict:
            // Giá trị 1 không chia 0 / tràn ⇒ parse được ⇔ đúng dạng phép tính.
            return parse(fill(lits.map { _ in 1 })) != nil ? .conflict : .invalid
        case .ok(let values, let dec, let grouped):
            guard let v = parse(fill(values)), v.isFinite, abs(v) < 1e15 else { return .invalid }
            return .ok(Calc(value: v, english: dec == ".", grouped: grouped))
        }
    }

    private enum Numbers { case ok([Double], dec: Character?, grouped: Bool), malformed, conflict }

    /// Các số của biểu thức ("26,160", "2.5"…) → giá trị theo dấu phân cách suy từ CẢ
    /// biểu thức (quy tắc đầu file). `dec` = dấu thập phân đã suy (nil: không có dấu nào),
    /// `grouped` = có số dùng nhóm nghìn.
    private static func numbers(_ lits: [String]) -> Numbers {
        var certDec = Set<Character>(), certGroup = Set<Character>(), ambiguous = Set<Character>()
        for lit in lits {
            let cs = Array(lit)
            guard let l = cs.last, isDigit(l) else { return .malformed }
            let dots = cs.filter { $0 == "." }.count, commas = cs.filter { $0 == "," }.count
            if dots > 0, commas > 0 {
                let d: Character = cs.lastIndex(of: ".")! > cs.lastIndex(of: ",")! ? "." : ","
                guard (d == "." ? dots : commas) == 1 else { return .malformed }
                certDec.insert(d); certGroup.insert(d == "." ? "," : ".")
            } else if dots + commas > 1 {
                certGroup.insert(dots > 0 ? "." : ",")
            } else if dots + commas == 1 {
                let s: Character = dots > 0 ? "." : ","
                let k = cs.firstIndex(of: s)!
                if cs.count - k - 1 == 3, (1...3).contains(k), cs[0] != "0" { ambiguous.insert(s) } else { certDec.insert(s) }
            }
        }
        guard certDec.count <= 1, certGroup.count <= 1, certDec.isDisjoint(with: certGroup) else { return .conflict }
        let other: (Character) -> Character = { $0 == "." ? "," : "." }
        var dec: Character? = nil
        if let d = certDec.first { dec = d }
        else if let g = certGroup.first { dec = other(g) }
        else if ambiguous.count > 1 { return .conflict }
        else if let a = ambiguous.first { dec = other(a) }
        var values: [Double] = [], grouped = false
        for lit in lits {
            var intPart = Substring(lit), frac = ""[...]
            if let d = dec, let k = lit.firstIndex(of: d) {
                intPart = lit[..<k]; frac = lit[lit.index(after: k)...]
                guard !frac.contains(d) else { return .malformed }
            }
            var digits = String(intPart)
            if let d = dec, intPart.contains(other(d)) {
                let groups = intPart.split(separator: other(d), omittingEmptySubsequences: false)
                guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 })
                else { return .malformed }
                digits = groups.joined(); grouped = true
            }
            guard !digits.isEmpty, digits.count <= NumberChips.maxDigits, frac.count <= NumberChips.maxDigits,
                  frac.allSatisfy(isDigit),
                  let v = Double(digits + (frac.isEmpty ? "" : "." + frac)) else { return .malformed }
            values.append(v)
        }
        return .ok(values, dec: dec, grouped: grouped)
    }

    private static func parse(_ toks: [Tok]) -> Double? {
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
        guard let v = expression(0), p == toks.count else { return nil }
        return v
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
                  isDigit(f) || f == "(" || f == "-" || f == "\u{2212}" else { continue }
            let outcome = analyze(e)
            if case .conflict = outcome { return nil }
            guard case .ok(let c) = outcome, let r = format(c) else { continue }
            return NumberChip(display: r, replace: "", insert: r)
        }
        return nil
    }
}
