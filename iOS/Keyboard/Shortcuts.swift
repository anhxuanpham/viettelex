// Gõ tắt (text expansion) — logic THUẦN dùng chung bàn phím + app + test. Port hành vi
// macOS (TelexInputController.boundary / ShortcutImporter) và bản Kotlin
// android/keyboard/.../Shortcuts.kt (giữ hai bản y hệt nhau).
//
// Hai loại khoá:
//  • khoá CHỮ ("ko", "đc", "cty"): tra lúc gõ ký tự ranh giới (space/Enter/dấu câu)
//    sau từ đang soạn — theo dạng ĐÃ BIẾN ĐỔI trước ("ddc" → "đc" khớp "đc"), rồi mới
//    tới phím THÔ ("dc" khớp "dc"), như macOS. Ưu tiên TRƯỚC tự khôi phục tiếng Anh.
//  • khoá có KÝ HIỆU/SỐ ("->", "√√", "k2"): tra lúc gõ khoảng trắng/Enter, so với cả
//    cụm ký tự liền nhau ngay trước con trỏ (từ khoảng trắng gần nhất).
// Không nở khi từ dính liền sau chữ số (#82: "5h" giữ nguyên, "5h30") hoặc sau / # @
// (#87: "/h3", đường dẫn, @mention) — như macOS gluesShortcutToken.
// Giữ hoa theo cách gõ: ko → không, Ko → Không, KO → KHÔNG (khoá viết thường).
import Foundation

struct ShortcutTable: Equatable {
    private(set) var entries: [String: String]
    /// Có khoá nào không thuần chữ (cần đọc cụm trước con trỏ lúc gõ khoảng trắng).
    private(set) var hasTokenKeys: Bool

    init(_ entries: [String: String] = [:]) {
        var clean: [String: String] = [:]
        for (k, v) in entries where Self.isValidKey(k) && !v.isEmpty { clean[k] = v }
        self.entries = clean
        self.hasTokenKeys = clean.keys.contains { !Self.isWordKey($0) }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Khoá hợp lệ: không rỗng, ≤ 64 ký tự, không chứa khoảng trắng (như macOS parse()).
    static func isValidKey(_ k: String) -> Bool {
        !k.isEmpty && k.count <= 64 && !k.contains(where: { $0.isWhitespace })
    }

    /// Khoá thuần chữ — tra theo từ engine đang soạn.
    static func isWordKey(_ k: String) -> Bool { !k.isEmpty && k.allSatisfy { $0.isLetter } }

    /// Nội dung sẽ bung cho `typed` (đã áp hoa/thường), nil = không khớp.
    /// 1. khớp nguyên văn; 2. khoá viết thường + `typed` viết hoa toàn bộ (≥ 2 chữ) ⇒ nội
    /// dung VIẾT HOA; chỉ chữ đầu hoa ⇒ viết hoa chữ đầu nội dung; hoa lộn xộn ("kO") ⇒ nil.
    func expansion(for typed: String) -> String? {
        guard !typed.isEmpty else { return nil }
        if let e = entries[typed] { return e }
        let lower = typed.lowercased()
        guard lower != typed, let e = entries[lower] else { return nil }
        return Self.applyCase(typed: typed, to: e)
    }

    static func applyCase(typed: String, to e: String) -> String? {
        let letters = typed.filter { $0.isLetter }
        guard let first = letters.first else { return e }
        if letters.count >= 2, typed == typed.uppercased() { return e.uppercased() }
        let rest = letters.dropFirst()
        if first.isUppercase, String(rest) == String(rest).lowercased() {
            guard let c = e.first else { return e }
            return c.uppercased() + e.dropFirst()
        }
        return nil
    }

    /// Từ đang soạn: thử dạng hiển thị rồi phím thô (như macOS). Chỉ khoá thuần chữ.
    func wordExpansion(composed: String, raw: String) -> String? {
        if let e = expansion(for: composed), Self.isWordKey(composed.lowercased()) { return e }
        if raw != composed, let e = expansion(for: raw), Self.isWordKey(raw.lowercased()) { return e }
        return nil
    }

    /// Cụm không khoảng trắng cuối `context` (khoá ký hiệu/số). nil nếu rỗng.
    static func trailingToken(_ context: String) -> String? {
        var start = context.endIndex
        while start > context.startIndex {
            let prev = context.index(before: start)
            if context[prev].isWhitespace { break }
            start = prev
        }
        guard start < context.endIndex else { return nil }
        return String(context[start...])
    }

    /// Khoá ký hiệu/số khớp cụm cuối `context`: (cụm, nội dung). Chỉ khoá không thuần chữ
    /// (khoá chữ đã xử lý ở từ đang soạn).
    func tokenExpansion(context: String) -> (token: String, expansion: String)? {
        guard hasTokenKeys, let token = Self.trailingToken(context),
              !Self.isWordKey(token), let e = expansion(for: token) else { return nil }
        return (token, e)
    }

    /// Ký tự ranh giới có kích hoạt khoá CHỮ không: khoảng trắng/xuống dòng hoặc dấu câu
    /// kết thúc từ. Chữ số, @ / # - _ … KHÔNG (ko1, ko@, ko/ không phải từ đứng riêng).
    static func triggersWord(_ boundary: String) -> Bool {
        guard let c = boundary.first else { return false }
        return c.isWhitespace || c.isNewline || wordTriggers.contains(c)
    }
    private static let wordTriggers: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "…", "”", "’", "»",
    ]

    /// Khoá ký hiệu/số chỉ nở ở khoảng trắng / xuống dòng.
    static func triggersToken(_ boundary: String) -> Bool {
        guard let c = boundary.first else { return false }
        return c.isWhitespace || c.isNewline
    }

    /// Từ `word` nằm cuối `context` có dính liền sau một ký tự không cho nở không (#82 số,
    /// #87 / # @, và chữ/ký hiệu nối kiểu . _ - : \ ~ — URL, email, tên file). Context nil
    /// (host không cho biết) ⇒ false (không chặn). Context không kết thúc bằng `word` ⇒
    /// true (không chắc gì trên màn hình — không nở).
    static func isGlued(word: String, context: String?) -> Bool {
        guard let ctx = context else { return false }
        guard ctx.hasSuffix(word) else { return true }
        guard let prev = ctx.dropLast(word.count).last else { return false }
        return prev.isLetter || prev.isNumber || glueChars.contains(prev)
    }
    private static let glueChars: Set<Character> = ["/", "#", "@", ".", "_", "-", ":", "\\", "~", "&", "=", "+", "%"]
}

/// Nhập/xuất bảng gõ tắt — CÙNG định dạng với macOS ShortcutImporter (YAML phẳng
/// "khoá: nội dung", `#` chú thích) để dùng chung một file Mac ↔ iPhone ↔ Android.
/// Mở rộng tương thích ngược: nội dung nhiều dòng xuất trong ngoặc kép với `\n`; khoá
/// chứa ":" (hoặc mở đầu bằng # ; " ') xuất trong ngoặc kép.
enum ShortcutFile {
    static let header = "# VietTelex — bảng gõ tắt"

    static func exportYAML(_ table: [String: String]) -> String {
        var out = header + "\n"
        for key in table.keys.sorted() {
            let value = table[key]!
            out += "\(quoteKeyIfNeeded(key)): \(quoteValueIfNeeded(value))\n"
        }
        return out
    }

    private static func quoteKeyIfNeeded(_ k: String) -> String {
        let needs = k.contains(":") || k.hasPrefix("#") || k.hasPrefix(";") || k.hasPrefix("//")
            || k.hasPrefix("\"") || k.hasPrefix("'")
        return needs ? "\"" + escape(k) + "\"" : k
    }

    private static func quoteValueIfNeeded(_ v: String) -> String {
        if v.contains("\n") || v.contains("\r") { return "\"" + escape(v) + "\"" }
        // y hệt macOS exportYAML: bọc nháy khi có khoảng trắng hai đầu / mở đầu ' " #
        let needs = v.hasPrefix(" ") || v.hasSuffix(" ") || v.hasPrefix("'") || v.hasPrefix("\"") || v.hasPrefix("#")
        return needs ? "\"\(v)\"" : v
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let n = it.next() else { out.append("\\"); break }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "\\": out.append("\\")
            case "\"": out.append("\"")
            default: out.append("\\"); out.append(n)
            }
        }
        return out
    }

    /// Parse: JSON object {khoá: nội dung} hoặc dòng "khoá: nội dung" / "khoá:nội dung"
    /// (`#` `;` `//` chú thích). Rỗng / không đọc được ⇒ [:].
    static func parse(_ text: String) -> [String: String] {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        if let data = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String], !dict.isEmpty {
            return ShortcutTable(dict).entries
        }
        var out: [String: String] = [:]
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            var key: String
            var rest: Substring
            if line.hasPrefix("\""), let (k, after) = quotedPrefix(Substring(line)) {
                // khoá trong ngoặc kép (chứa ":"): "…": nội dung
                let r = after.drop(while: { $0 == " " || $0 == "\t" })
                guard r.first == ":" else { continue }
                key = k; rest = r.dropFirst()
            } else {
                guard let colon = line.firstIndex(of: ":") else { continue }
                key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                rest = line[line.index(after: colon)...]
            }
            var value = rest.trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = unescape(String(value.dropFirst().dropLast()))
            } else if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }
            key = key.trimmingCharacters(in: .whitespaces)
            guard ShortcutTable.isValidKey(key), !value.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    /// `"…"` ở đầu chuỗi → (nội dung đã unescape, phần còn lại). nil nếu không đóng nháy.
    private static func quotedPrefix(_ s: Substring) -> (String, Substring)? {
        var i = s.index(after: s.startIndex)
        var raw = ""
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" {
                let n = s.index(after: i)
                guard n < s.endIndex else { return nil }
                raw.append(c); raw.append(s[n])
                i = s.index(after: n)
                continue
            }
            if c == "\"" { return (unescape(raw), s[s.index(after: i)...]) }
            raw.append(c)
            i = s.index(after: i)
        }
        return nil
    }

    /// Gộp import vào bảng hiện có: mục nhập vào THẮNG (như macOS merging). Trả (bảng mới,
    /// số mục mới thêm, số mục bị ghi đè).
    static func merge(_ current: [String: String], _ imported: [String: String])
        -> (table: [String: String], added: Int, replaced: Int) {
        var out = current
        var added = 0, replaced = 0
        for (k, v) in imported {
            if let old = out[k] { if old != v { replaced += 1 } } else { added += 1 }
            out[k] = v
        }
        return (out, added, replaced)
    }

    /// Bộ gợi ý (người dùng bấm "Thêm bộ gợi ý" mới có — mặc định bảng RỖNG, như macOS).
    /// Chọn khoá không trùng từ tiếng Việt/Anh thường gặp ở dạng viết thường.
    static let suggested: [String: String] = [
        "ko": "không",
        "dc": "được",
        "đc": "được",
        "vs": "với",
        "mn": "mọi người",
        "trc": "trước",
        "cty": "công ty",
        "bsi": "bác sĩ",
        "stk": "số tài khoản",
        "->": "→",
    ]

    // Lưu trữ chung (App Group; key giống Android pref).
    static let storeKey = "shortcuts"
    static let enabledKey = "shortcutsEnabled"
}

/// Học từ nội dung đã bung (không học chữ tắt).
enum ShortcutLearning {
    /// Tách theo khoảng trắng: "mọi người" → ["mọi", "người"]; một từ → [chính nó].
    static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }
}
