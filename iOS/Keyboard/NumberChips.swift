// NumberChips — chip số trên thanh gợi ý: đọc số thành chữ, định dạng tiền, máy tính
// nhanh. Logic THUẦN (không UIKit/proxy) — bản Kotlin android NumberChips.kt phải cho
// cùng kết quả trên fixture chung KeyboardTests/Fixtures/number-chips.txt.
// Nguyên tắc: KHÔNG tự thay chữ — chỉ đề xuất chip; chạm mới áp dụng.
//
// Quy tắc (xem iOS/docs/IOS-SUGGESTIONS.md, tầng 7):
// • Đọc số: "linh" (tuỳ chọn "lẻ"), mười/mươi, mốt (sau mươi), lăm (sau mười/mươi),
//   "bốn" (không dùng "tư"); nhóm 0 bị bỏ, nhóm sau nhóm đầu đọc đủ "không trăm";
//   tỷ lặp theo khối 9 chữ số (10^12 = "một nghìn tỷ", 10^18 = "một tỷ tỷ").
//   Thập phân "phẩy": phần lẻ ≤2 chữ số không mở đầu bằng 0 đọc như số, còn lại đọc
//   từng chữ số. Số âm: "âm …".
// • Dấu phân cách: có cả "." và "," → dấu xuất hiện SAU CÙNG là dấu thập phân (chỉ 1
//   lần), dấu kia là phân nhóm nghìn (nhóm đúng 3 chữ số). Chỉ ",": 1 lần = thập phân
//   (kiểu Việt), ≥2 = phân nhóm. Chỉ ".": ≥2 = phân nhóm; 1 lần = phân nhóm nếu sau nó
//   đúng 3 chữ số và phần nguyên 1–3 chữ số không mở đầu bằng 0 ("1.250" = 1250), còn
//   lại là thập phân kiểu Anh ("1.5", "0.250").
import Foundation

struct NumberChip: Equatable {
    /// Chữ hiện trên chip.
    let display: String
    /// Đuôi văn bản trước con trỏ sẽ bị thay (rỗng = chỉ chèn thêm — máy tính).
    let replace: String
    /// Chữ chèn vào (thay cho `replace`).
    let insert: String
}

enum NumberChips {
    static let maxDigits = 30
    /// Số trơn (không phân cách, không đơn vị) dài hơn → coi là mã/số tài khoản, không đọc.
    static let maxPlainDigits = 12

    // MARK: - Số thập phân chính xác (chuỗi chữ số)

    struct Dec: Equatable {
        var negative: Bool
        var int: String    // không số 0 thừa đầu; "0" cho số 0
        var frac: String   // không số 0 thừa cuối

        init(negative: Bool, int: String, frac: String) {
            var i = String(int.drop { $0 == "0" })
            if i.isEmpty { i = "0" }
            var f = frac
            while f.last == "0" { f.removeLast() }
            self.int = i; self.frac = f
            self.negative = negative && !(i == "0" && f.isEmpty)
        }

        /// × 10^e (e ≥ 0) — dời dấu phẩy, chính xác tuyệt đối.
        func shifted(_ e: Int) -> Dec {
            let f = frac + String(repeating: "0", count: max(0, e - frac.count))
            return Dec(negative: negative, int: int + f.prefix(e), frac: String(f.dropFirst(e)))
        }
    }

    struct Literal {
        let value: Dec
        let groupSep: Character?
        let decSep: Character?
    }

    private static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    /// Một số viết bằng chữ số + "." "," theo quy tắc phân cách ở đầu file.
    static func parseNumber(_ s: String) -> Literal? {
        let chars = Array(s)
        guard let f = chars.first, let l = chars.last, isDigit(f), isDigit(l),
              chars.allSatisfy({ isDigit($0) || $0 == "." || $0 == "," }) else { return nil }
        let dots = chars.filter { $0 == "." }.count
        let commas = chars.filter { $0 == "," }.count
        var groupSep: Character? = nil
        var decSep: Character? = nil
        if dots > 0 && commas > 0 {
            let lastDot = chars.lastIndex(of: ".")!, lastComma = chars.lastIndex(of: ",")!
            decSep = lastDot > lastComma ? "." : ","
            groupSep = decSep == "." ? "," : "."
            if (decSep == "." ? dots : commas) != 1 { return nil }
        } else if commas > 0 {
            if commas == 1 { decSep = "," } else { groupSep = "," }
        } else if dots > 0 {
            if dots > 1 {
                groupSep = "."
            } else {
                let i = chars.firstIndex(of: ".")!
                let head = chars[..<i], tail = chars[(i + 1)...]
                if tail.count == 3, (1...3).contains(head.count), head.first != "0" {
                    groupSep = "."
                } else {
                    decSep = "."
                }
            }
        }
        var intPart = s[...], frac = ""[...]
        if let d = decSep, let i = s.firstIndex(of: d) {
            intPart = s[..<i]; frac = s[s.index(after: i)...]
        }
        var digits = ""
        if let g = groupSep {
            let groups = intPart.split(separator: g, omittingEmptySubsequences: false)
            guard let g0 = groups.first, (1...3).contains(g0.count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }),
                  groups.allSatisfy({ $0.allSatisfy(isDigit) }) else { return nil }
            digits = groups.joined()
        } else {
            guard intPart.allSatisfy(isDigit) else { return nil }
            digits = String(intPart)
        }
        guard !digits.isEmpty, frac.allSatisfy(isDigit),
              digits.count <= maxDigits, frac.count <= maxDigits else { return nil }
        return Literal(value: Dec(negative: false, int: digits, frac: String(frac)),
                       groupSep: groupSep, decSep: decSep)
    }

    // MARK: - Đọc số thành chữ

    private static let digitWords = ["không", "một", "hai", "ba", "bốn",
                                     "năm", "sáu", "bảy", "tám", "chín"]

    /// Nhóm 3 chữ số (1…999). `full` = đọc đủ hàng trăm ("không trăm linh năm").
    private static func readTriple(_ n: Int, full: Bool, le: Bool) -> [String] {
        let h = n / 100, t = (n / 10) % 10, u = n % 10
        var w: [String] = []
        if full || h > 0 { w += [digitWords[h], "trăm"] }
        switch t {
        case 0:
            if u > 0 {
                if !w.isEmpty { w.append(le ? "lẻ" : "linh") }
                w.append(digitWords[u])
            }
        case 1:
            w.append("mười")
            if u == 5 { w.append("lăm") } else if u > 0 { w.append(digitWords[u]) }
        default:
            w += [digitWords[t], "mươi"]
            if u == 1 { w.append("mốt") } else if u == 5 { w.append("lăm") }
            else if u > 0 { w.append(digitWords[u]) }
        }
        return w
    }

    /// 0 < n < 10^9. `leading` = khối đầu tiên của cả số (không đọc "không trăm").
    private static func readBelowBillion(_ n: Int, leading: Bool, le: Bool) -> [String] {
        var out: [String] = []
        var first = leading
        for (g, unit) in [(n / 1_000_000, "triệu"), ((n / 1000) % 1000, "nghìn"), (n % 1000, "")]
        where g > 0 {
            out += readTriple(g, full: !first, le: le)
            if !unit.isEmpty { out.append(unit) }
            first = false
        }
        return out
    }

    /// Phần nguyên (chuỗi chữ số, không 0 thừa đầu) thành chữ.
    static func readInteger(_ digits: String, le: Bool = false) -> String {
        if digits.allSatisfy({ $0 == "0" }) { return "không" }
        var chunks: [Int] = []          // khối 9 chữ số, khối cao trước
        var rest = Substring(digits)
        while !rest.isEmpty {
            chunks.insert(Int(rest.suffix(9))!, at: 0)
            rest = rest.dropLast(min(9, rest.count))
        }
        while chunks.first == 0 { chunks.removeFirst() }
        var words = readBelowBillion(chunks[0], leading: true, le: le)
        for c in chunks.dropFirst() {
            words.append("tỷ")
            if c > 0 { words += readBelowBillion(c, leading: false, le: le) }
        }
        return words.joined(separator: " ")
    }

    static func read(_ d: Dec, le: Bool = false) -> String {
        var s = readInteger(d.int, le: le)
        if !d.frac.isEmpty {
            let f = d.frac
            let fw = f.count <= 2 && f.first != "0"
                ? readInteger(f, le: le)
                : f.map { digitWords[Int(String($0))!] }.joined(separator: " ")
            s += " phẩy " + fw
        }
        return d.negative ? "âm " + s : s
    }

    /// Dạng chuẩn "-1250000,5" → chữ (dùng cho test/fixture). nil nếu sai dạng.
    static func spell(_ canonical: String, le: Bool = false) -> String? {
        var s = Substring(canonical)
        let neg = s.first == "-"
        if neg { s = s.dropFirst() }
        let parts = s.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isDigit) }),
              parts[0].count <= maxDigits else { return nil }
        return read(Dec(negative: neg, int: String(parts[0]),
                        frac: parts.count > 1 ? String(parts[1]) : ""), le: le)
    }

    // MARK: - Tiền: viết tắt & định dạng

    /// Đơn vị nhân (viết tắt) → số mũ 10.
    private static let multipliers: [String: Int] = [
        "k": 3, "nghìn": 3, "ngàn": 3, "nghin": 3, "ngan": 3,
        "tr": 6, "triệu": 6, "trieu": 6,
        "tỷ": 9, "tỉ": 9, "ty": 9,
    ]
    private static let currencies: Set<String> = ["đ", "₫", "đồng", "vnd", "vnđ"]

    struct Amount: Equatable {
        let value: Dec
        let multiplier: Bool      // có k/tr/tỷ
        let currency: String?     // đ ₫ đồng vnd vnđ (đã lowercase)
        let grouped: Bool         // viết có phân nhóm nghìn
    }

    /// Một số tiền/số: 1 từ ("50k", "1tr2", "1.2tr", "2tỷ", "1250000đ", "-5", "3,5")
    /// hoặc 2 từ ("2 tỷ", "1.250.000 ₫", "50 k").
    static func parseAmount(_ token: String) -> Amount? {
        let words = token.split(separator: " ", omittingEmptySubsequences: false)
        guard (1...2).contains(words.count) else { return nil }
        var w = Substring(words[0])
        let neg = w.first == "-" || w.first == "\u{2212}"
        if neg { w = w.dropFirst() }
        let numPart = w.prefix { isDigit($0) || $0 == "." || $0 == "," }
        guard let lit = parseNumber(String(numPart)) else { return nil }
        var suffix = w.dropFirst(numPart.count)
        if words.count == 2 {
            guard suffix.isEmpty, !words[1].isEmpty else { return nil }
            suffix = words[1]
        }
        let unit = String(suffix.prefix { !isDigit($0) }).lowercased()
        let tail = suffix.dropFirst(suffix.prefix { !isDigit($0) }.count)
        guard tail.allSatisfy(isDigit) else { return nil }
        if words.count == 2, unit.isEmpty || !tail.isEmpty { return nil }   // "12 5" không phải 1 số
        let value = Dec(negative: neg, int: lit.value.int, frac: lit.value.frac)
        let grouped = lit.groupSep != nil
        if unit.isEmpty {
            return Amount(value: value, multiplier: false, currency: nil, grouped: grouped)
        }
        if let e = multipliers[unit] {
            var v = value
            if !tail.isEmpty {   // "1tr2" = 1,2 triệu — chỉ sau số nguyên trơn, ≤3 chữ số
                guard lit.groupSep == nil, lit.decSep == nil, tail.count <= 3 else { return nil }
                v = Dec(negative: neg, int: lit.value.int, frac: String(tail))
            }
            v = v.shifted(e)
            guard v.int.count <= maxDigits else { return nil }
            return Amount(value: v, multiplier: true, currency: nil, grouped: grouped)
        }
        if currencies.contains(unit), tail.isEmpty {
            return Amount(value: value, multiplier: false, currency: unit, grouped: grouped)
        }
        return nil
    }

    /// Phần nguyên chia nhóm 3 bằng `sep`.
    static func group(_ digits: String, sep: Character) -> String {
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(sep) }
            out.append(c)
        }
        return out
    }

    /// "1.250.000 ₫" (symbol "₫", có space) / "1.250.000đ" (symbol "đ", liền). Chỉ số nguyên.
    static func formatMoney(_ d: Dec, symbol: String = "₫") -> String? {
        guard d.frac.isEmpty else { return nil }
        let body = (d.negative ? "-" : "") + group(d.int, sep: ".")
        return symbol == "đ" ? body + "đ" : body + " " + symbol
    }

    // MARK: - Máy tính nhanh

    private enum Tok: Equatable { case num(Double), op(Character), lp, rp, pct }

    struct Calc { let value: Double; let english: Bool; let grouped: Bool }

    /// Biểu thức (không có "="). + - * x × / ÷ : ( ) %; số theo quy tắc phân cách.
    /// "A ± B%" = A ± A·B/100 (như máy tính điện thoại); còn lại "B%" = B/100.
    static func evaluate(_ expr: String) -> Calc? {
        var toks: [Tok] = []
        var english = false, grouped = false
        let cs = Array(expr)
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c == " " { i += 1; continue }
            if isDigit(c) {
                var j = i
                while j < cs.count, isDigit(cs[j]) || cs[j] == "." || cs[j] == "," { j += 1 }
                guard let lit = parseNumber(String(cs[i..<j])),
                      let v = Double((lit.value.int) + (lit.value.frac.isEmpty ? "" : "." + lit.value.frac))
                else { return nil }
                if lit.decSep == "." || lit.groupSep == "," { english = true }
                if lit.groupSep != nil { grouped = true }
                toks.append(.num(v)); i = j; continue
            }
            switch c {
            case "+", "-", "\u{2212}": toks.append(.op(c == "+" ? "+" : "-"))
            case "*", "x", "X", "×": toks.append(.op("*"))
            case "/", "÷", ":": toks.append(.op("/"))
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
        func factor(_ depth: Int) -> (Double, Bool)? {
            guard depth < 32 else { return nil }
            if peek() == .op("-") { p += 1; return factor(depth + 1).map { (-$0.0, false) } }
            if peek() == .op("+") { p += 1; return factor(depth + 1).map { ($0.0, false) } }
            guard let v = primary(depth) else { return nil }
            if peek() == .pct { p += 1; return (v / 100, true) }
            return (v, false)
        }
        func term(_ depth: Int) -> (Double, Bool)? {
            guard var (v, isPct) = factor(depth) else { return nil }
            while let t = peek(), t == .op("*") || t == .op("/") {
                p += 1
                guard let (r, _) = factor(depth) else { return nil }
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

    /// Kết quả theo kiểu số của biểu thức: mặc định kiểu Việt (thập phân ","), kiểu Anh
    /// nếu biểu thức dùng "." thập phân hoặc "," phân nhóm; phân nhóm nghìn chỉ khi biểu
    /// thức có phân nhóm. Tối đa 12 chữ số có nghĩa (≤10 chữ số lẻ).
    static func formatResult(_ c: Calc) -> String {
        let a = abs(c.value)
        let intDigits = a < 1 ? 1 : String(format: "%.0f", a.rounded(.down)).count
        let decimals = max(0, min(10, 12 - intDigits))
        var s = String(format: "%.\(decimals)f", a)
        if s.contains(".") {
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        var intPart = String(parts[0])
        if c.grouped { intPart = group(intPart, sep: c.english ? "," : ".") }
        var out = intPart
        if parts.count > 1 { out += (c.english ? "." : ",") + parts[1] }
        if c.value < 0, out != "0" { out = "-" + out }
        return out
    }

    private static let calcChars: Set<Character> = Set("0123456789.,+-\u{2212}*xX×/÷:()% ")

    /// Chip máy tính cho context kết thúc bằng "=". Thử cả đuôi hợp lệ dài nhất lẫn các
    /// đuôi sau khoảng trắng ("năm 2024 12*3=" → "12*3").
    static func calcChip(before: String) -> NumberChip? {
        guard before.hasSuffix("=") else { return nil }
        let body = before.dropLast()
        let scanned = String(body.reversed().prefix { calcChars.contains($0) }.reversed())
        var candidates = [scanned]
        for (k, ch) in scanned.enumerated() where ch == " " {
            candidates.append(String(scanned.dropFirst(k + 1)))
        }
        for cand in candidates {
            let e = cand.trimmingCharacters(in: .whitespaces)
            guard let f = e.first, isDigit(f) || f == "(" || f == "-" || f == "\u{2212}",
                  let c = evaluate(e) else { continue }
            let r = formatResult(c)
            return NumberChip(display: r, replace: "", insert: r)
        }
        return nil
    }

    // MARK: - Chip chính

    /// Chip duy nhất cho thanh gợi ý từ văn bản trước con trỏ (nil = không có).
    /// • "…=" → kết quả phép tính (chèn sau dấu =).
    /// • số có k/tr/tỷ → định dạng tiền "1.200.000 ₫".
    /// • số + đ/₫ chưa phân nhóm (≥4 chữ số) → định dạng giữ ký hiệu ("1.250.000đ").
    /// • số + đ/₫ đã định dạng, hoặc + đồng/vnd → chữ + " đồng".
    /// • số trơn / có phân cách → chữ (không "đồng"). Số trơn mở đầu bằng 0 (điện thoại,
    ///   mã) hoặc dài >12 chữ số → không gợi ý.
    /// Chuỗi chip: "1tr2" → "1.200.000 ₫" → "một triệu hai trăm nghìn đồng".
    static func chip(before: String, le: Bool = false) -> NumberChip? {
        if before.hasSuffix("=") { return calcChip(before: before) }
        var ctx = Substring(before)
        let hadSpace = ctx.hasSuffix(" ")
        if hadSpace { ctx = ctx.dropLast() }
        guard let last = ctx.last, !last.isWhitespace else { return nil }
        func lastWord(_ s: Substring) -> Substring {
            guard let i = s.lastIndex(where: { $0.isWhitespace }) else { return s }
            return s[s.index(after: i)...]
        }
        let w1 = lastWord(ctx)
        var token = String(w1)
        var amount = parseAmount(token)
        // Đơn vị tách rời: "2 tỷ", "1.250.000 ₫".
        let rest1 = ctx.dropLast(w1.count)
        if rest1.hasSuffix(" ") {
            let w0 = lastWord(rest1.dropLast())
            if !w0.isEmpty, let a = parseAmount(w0 + " " + w1), a.multiplier || a.currency != nil {
                token = w0 + " " + w1; amount = a
            }
        }
        guard let a = amount else { return nil }
        let prefix = ctx.dropLast(token.count)
        let text: String?
        if a.multiplier {
            text = formatMoney(a.value, symbol: "₫")
        } else if let cur = a.currency {
            if (cur == "đ" || cur == "₫"), !a.grouped, a.value.int.count >= 4, a.value.frac.isEmpty {
                text = formatMoney(a.value, symbol: cur)
            } else {
                text = read(a.value, le: le) + " đồng"
            }
        } else {
            let plain = !a.grouped && !token.contains(",") && !token.contains(".")
            let digits = token.filter(isDigit)
            if plain && ((digits.count > 1 && digits.first == "0") || digits.count > maxPlainDigits) {
                return nil
            }
            text = read(a.value, le: le)
        }
        guard var t = text else { return nil }
        if atSentenceStart(prefix), let f = t.first, f.isLetter {
            t = f.uppercased() + t.dropFirst()
        }
        let sp = hadSpace ? " " : ""
        return NumberChip(display: t, replace: token + sp, insert: t + sp)
    }

    /// Đầu câu: trước token (bỏ khoảng trắng) là rỗng hoặc . ! ? xuống dòng.
    static func atSentenceStart(_ prefix: Substring) -> Bool {
        if prefix.hasSuffix("\n") { return true }
        let t = prefix.reversed().drop { $0 == " " || $0 == "\t" }
        guard let c = t.first else { return true }
        return c == "." || c == "!" || c == "?" || c == "\n"
    }
}
