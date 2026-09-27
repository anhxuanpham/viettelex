// Chip tách số từ nội dung vừa copy (STK / SĐT / OTP) — hàm THUẦN, không UIKit.
// Hợp đồng dùng chung với Android (keyboard/ClipDetect.kt) — sửa luật phải sửa
// cả hai và giữ test vector khớp (ClipDetectTests ở cả hai bên).
import Foundation

struct ClipChip: Equatable {
    enum Kind: Equatable { case otp, phone, account }
    let kind: Kind
    /// Chỉ chữ số; SĐT chuẩn hoá về 0xxxxxxxxx.
    let value: String
    let label: String
}

enum ClipDetect {
    static let maxLength = 500

    /// Tối đa 1 chip mỗi loại (lần xuất hiện đầu), thứ tự OTP → SĐT → STK.
    static func detect(_ text: String) -> [ClipChip] {
        guard !text.isEmpty, text.count <= maxLength else { return [] }
        let chars = Array(text)
        let folded = fold(chars)
        let tokens = wordTokens(folded)
        var out: [ClipChip] = []

        // OTP
        let otpRuns = runs(chars, seps: []).filter { (4...8).contains($0.digits.count) && bounded(chars, $0) && !followedByCurrency(folded, $0.end) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var otp: String?
        if (4...8).contains(trimmed.count), trimmed.allSatisfy(\.isASCIIDigit) {
            otp = trimmed
        } else if !otpRuns.isEmpty {
            otp = otpAfterKeyword(tokens: tokens, runs: otpRuns)
        }
        if let v = otp { out.append(ClipChip(kind: .otp, value: v, label: L("Dán OTP %@", v))) }

        // SĐT
        var phone: String?, phoneRaw: String?
        for r in runs(chars, seps: [" ", ".", "-"], allowPlus: true) where bounded(chars, r) {
            if let p = phonePrefix(r) { phone = p.normalized; phoneRaw = p.raw; break }
        }
        if let v = phone { out.append(ClipChip(kind: .phone, value: v, label: L("Dán SĐT %@", short(v)))) }

        // STK
        let hasAccountKeyword = tokens.contains { ["stk", "tk", "account", "acc"].contains($0.word) }
            || String(folded).contains("tai khoan") || String(folded).contains("a/c")
        for r in runs(chars, seps: [" ", "-"]) where bounded(chars, r) {
            let d = r.digits
            guard (6...19).contains(d.count), d != phone, d != phoneRaw, d != otp,
                  !followedByCurrency(folded, r.end) else { continue }
            guard hasAccountKeyword || d.count >= 9 else { continue }
            out.append(ClipChip(kind: .account, value: d, label: L("Dán STK %@", short(d))))
            break
        }
        return out
    }

    // MARK: nội bộ

    struct Run { let start: Int; let end: Int; let digits: String; let groups: [String] }

    /// Dãy chữ số, cho phép MỘT ký tự phân cách (thuộc `seps`) giữa hai chữ số.
    /// `end` là chỉ số NGAY SAU chữ số cuối. `allowPlus`: '+' ngay trước tính vào.
    static func runs(_ c: [Character], seps: Set<Character>, allowPlus: Bool = false) -> [Run] {
        var out: [Run] = []
        var i = 0
        while i < c.count {
            guard c[i].isASCIIDigit else { i += 1; continue }
            var start = i
            if allowPlus, i > 0, c[i - 1] == "+" { start = i - 1 }
            var groups: [String] = [""]
            var j = i
            while j < c.count {
                if c[j].isASCIIDigit { groups[groups.count - 1].append(c[j]); j += 1 }
                else if seps.contains(c[j]), j + 1 < c.count, c[j + 1].isASCIIDigit {
                    groups.append(""); j += 1
                } else { break }
            }
            out.append(Run(start: start, end: j, digits: groups.joined(), groups: groups))
            i = j
        }
        return out
    }

    /// Biên: không kề chữ cái/chữ số; không kề [.,:/] mà bên kia là chữ số
    /// (tiền "1,234,567", giờ "12:30", ngày "27/09").
    static func bounded(_ c: [Character], _ r: Run) -> Bool {
        func bad(_ i: Int, _ step: Int) -> Bool {
            guard i >= 0, i < c.count else { return false }
            let ch = c[i]
            if ch.isLetter || ch.isNumber { return true }
            if ".,:/".contains(ch) {
                let k = i + step
                return k >= 0 && k < c.count && c[k].isASCIIDigit
            }
            return false
        }
        return !bad(r.start - 1, -1) && !bad(r.end, 1)
    }

    private static func phonePrefix(_ r: Run) -> (normalized: String, raw: String)? {
        var acc = ""
        for g in r.groups {
            acc += g
            if let p = normalizePhone(acc) { return (p, acc) }
        }
        return nil
    }

    /// 10 số đầu 03/05/07/08/09 (di động) hoặc 11 số đầu 02 (bàn); +84/84 → 0.
    static func normalizePhone(_ digits: String) -> String? {
        var d = digits
        if d.hasPrefix("84"), d.count == 11 || d.count == 12 {
            let rest = d.dropFirst(2)
            d = rest.hasPrefix("0") ? String(rest) : "0" + rest
        }
        guard d.hasPrefix("0") else { return nil }
        let second = d.dropFirst().first
        if d.count == 10, let s = second, "35789".contains(s) { return d }
        if d.count == 11, second == "2" { return d }
        return nil
    }

    private static let strongOTPKeywords: Set<String> = ["otp", "code", "passcode", "verification"]

    /// OTP khi có keyword: dãy 4–8 số đầu tiên SAU keyword; "ma" (mã) chỉ tính khi
    /// dãy số nằm trong 50 ký tự sau nó; keyword mạnh mà không có dãy phía sau →
    /// dãy đầu tiên của cả chuỗi.
    private static func otpAfterKeyword(tokens: [(word: String, start: Int)], runs: [Run]) -> String? {
        var fallback = false
        for t in tokens {
            if strongOTPKeywords.contains(t.word) {
                if let r = runs.first(where: { $0.start > t.start }) { return r.digits }
                fallback = true
            } else if t.word == "ma",
                      let r = runs.first(where: { $0.start > t.start }), r.start - t.start <= 50 {
                return r.digits
            }
        }
        return fallback ? runs.first?.digits : nil
    }

    private static let currencyWords: Set<String> = ["vnd", "d", "dong", "usd", "k"]

    private static func followedByCurrency(_ f: [Character], _ end: Int) -> Bool {
        var i = end
        while i < f.count, f[i] == " " { i += 1 }
        var w = ""
        while i < f.count, f[i].isLetter { w.append(f[i]); i += 1 }
        return currencyWords.contains(w)
    }

    private static func short(_ v: String) -> String {
        v.count <= 6 ? v : String(v.prefix(4)) + "…"
    }

    /// Gập dấu + chữ thường TỪNG ký tự (giữ nguyên chỉ số với chuỗi gốc).
    static func fold(_ chars: [Character]) -> [Character] {
        chars.map { ch in
            if ch == "đ" || ch == "Đ" { return "d" }
            let f = String(ch).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return f.count == 1 ? f.first! : (String(ch).lowercased().first ?? ch)
        }
    }

    private static func wordTokens(_ f: [Character]) -> [(word: String, start: Int)] {
        var out: [(String, Int)] = []
        var i = 0
        while i < f.count {
            guard f[i].isLetter else { i += 1; continue }
            let s = i
            var w = ""
            while i < f.count, f[i].isLetter { w.append(f[i]); i += 1 }
            out.append((w, s))
        }
        return out
    }
}

/// Heuristic nội dung "giống bí mật" (mật khẩu / API key / OTP) → hết hạn sớm (2 phút).
enum ClipSensitivity {
    static func looksSecret(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if (4...8).contains(t.count), t.allSatisfy(\.isASCIIDigit) { return true }
        if ClipDetect.detect(t).contains(where: { $0.kind == .otp }) { return true }
        guard !t.contains(where: \.isWhitespace) else { return false }
        if t.contains("://") || t.lowercased().hasPrefix("www.") { return false }
        if let at = t.firstIndex(of: "@"), t[at...].contains(".") { return false }
        var classes = 0
        if t.contains(where: \.isLowercase) { classes += 1 }
        if t.contains(where: \.isUppercase) { classes += 1 }
        if t.contains(where: \.isASCIIDigit) { classes += 1 }
        if t.contains(where: { !$0.isLetter && !$0.isNumber }) { classes += 1 }
        if (8...64).contains(t.count), classes >= 3 { return true }
        if t.count >= 20, t.contains(where: \.isLetter), t.contains(where: \.isASCIIDigit) { return true }
        return false
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
