// Gõ tắt (text expansion) macOS — logic THUẦN, dùng chung IMKit controller
// (TelexInputController) + tap (TerminalTap) + test. Hành vi khớp bản iOS
// iOS/Keyboard/Shortcuts.swift và Android android/keyboard/.../Shortcuts.kt:
//
//  • khoá CHỮ ("ko", "đc", "cty"): tra lúc gõ ranh giới từ (space/Enter/dấu câu kết
//    thúc từ) theo dạng ĐÃ BIẾN ĐỔI trước ("ddc" → "đc"), rồi phím THÔ.
//  • khoá KÝ HIỆU/SỐ ("->", "√√", "k2", ":D"): tra lúc gõ khoảng trắng/Enter, so với
//    CẢ cụm ký tự liền nhau ngay trước con trỏ (từ khoảng trắng gần nhất) — "a->b"
//    không nở. macOS không có contextBeforeInput như iOS, nên cụm này lấy từ
//    ShortcutTail (ký tự chính mình thấy gõ), rồi IMKit ĐỌC LẠI màn hình để xác nhận
//    trước khi thay (ShortcutScreen) — chỉ đọc khi cụm khớp một khoá, không mỗi phím.
//  • giữ hoa theo cách gõ: ko → không, Ko → Không, KO → KHÔNG; hoa lộn xộn không
//    nở; khoá ghi đúng y hệt được ưu tiên.
//  • ⌫ ngay sau khi nở trả lại đúng chữ đã gõ + ranh giới, một lần, chỉ khi màn hình
//    khớp (ShortcutUndo). Sau Enter không hoàn tác.
import Foundation

struct ShortcutTable: Equatable {
    private(set) var entries: [String: String]
    /// Có khoá nào không thuần chữ (cần so cụm trước con trỏ lúc gõ khoảng trắng).
    private(set) var hasTokenKeys: Bool

    init(_ entries: [String: String] = [:]) {
        var clean: [String: String] = [:]
        for (k, v) in entries where Self.isValidKey(k) && !v.isEmpty { clean[k] = v }
        self.entries = clean
        self.hasTokenKeys = clean.keys.contains { !Self.isWordKey($0) }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Khoá hợp lệ: không rỗng, ≤ 64 ký tự, không chứa khoảng trắng.
    static func isValidKey(_ k: String) -> Bool {
        !k.isEmpty && k.count <= 64 && !k.contains(where: { $0.isWhitespace })
    }

    /// Khoá thuần chữ — tra theo từ engine đang soạn.
    static func isWordKey(_ k: String) -> Bool { !k.isEmpty && k.allSatisfy { $0.isLetter } }

    /// Nội dung sẽ nở cho `typed` (đã áp hoa/thường), nil = không khớp.
    /// 1. khớp nguyên văn; 2. khoá viết thường + `typed` viết hoa toàn bộ (≥ 2 chữ) ⇒
    /// nội dung VIẾT HOA; chỉ chữ đầu hoa ⇒ viết hoa chữ đầu; hoa lộn xộn ("kO") ⇒ nil.
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

    /// Từ đang soạn: thử dạng hiển thị rồi phím thô (khoá chứa phím Telex như "ks" chỉ
    /// khớp qua phím thô). Khác iOS một chút: phím thô KHÔNG bắt buộc thuần chữ — giữ
    /// hành vi macOS cũ (VNI: phím thô có số).
    func wordExpansion(composed: String, raw: String) -> String? {
        if let e = expansion(for: composed) { return e }
        if raw != composed, let e = expansion(for: raw) { return e }
        return nil
    }

    /// Cụm không khoảng trắng cuối `context`. nil nếu rỗng.
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

    /// Khoá ký hiệu/số khớp cụm cuối `context`: (cụm, nội dung). Chỉ khoá không thuần
    /// chữ (khoá chữ đi đường từ đang soạn).
    func tokenExpansion(context: String) -> (token: String, expansion: String)? {
        guard hasTokenKeys, let token = Self.trailingToken(context),
              !Self.isWordKey(token), let e = expansion(for: token) else { return nil }
        return (token, e)
    }

    /// Ký tự ranh giới có kích hoạt khoá CHỮ không: khoảng trắng/xuống dòng hoặc dấu
    /// câu kết thúc từ. Chữ số, @ / # - _ … KHÔNG (ko1, ko@, ko/ không phải từ riêng).
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
}

/// Kết quả tra gõ tắt ở một ranh giới.
enum ShortcutMatch: Equatable {
    /// Thay TỪ đang soạn bằng nội dung.
    case word(expansion: String)
    /// Thay cả cụm `token` (= phần đã chốt trước con trỏ + từ đang soạn) bằng nội dung.
    case token(token: String, expansion: String)

    var expansion: String {
        switch self {
        case let .word(e), let .token(_, e): return e
        }
    }

    /// Tra ở ranh giới: khoá CHỮ theo từ đang soạn trước, rồi khoá KÝ HIỆU/SỐ theo cả
    /// cụm `run + composed` (run = phần đã chốt liền trước từ, xem ShortcutTail).
    static func find(in table: ShortcutTable, composed: String, raw: String, run: String,
                     allowWord: Bool, allowToken: Bool) -> ShortcutMatch? {
        guard !table.isEmpty else { return nil }
        if allowWord, !composed.isEmpty,
           let e = table.wordExpansion(composed: composed, raw: raw) {
            return .word(expansion: e)
        }
        if allowToken, table.hasTokenKeys {
            let cand = run + composed
            if !cand.isEmpty, let m = table.tokenExpansion(context: cand), m.token == cand {
                return .token(token: cand, expansion: m.expansion)
            }
        }
        return nil
    }

    /// Ranh giới `boundary` (nil = Esc / phím không chèn ký tự) + từ có dính sau ký tự
    /// mở token (#82 số, #87 / # @ . _ -) ⇒ được tra khoá chữ / khoá ký hiệu không.
    /// Esc giữ hành vi cũ: khoá chữ có, khoá ký hiệu không.
    static func triggers(boundary: String?, glued: Bool) -> (word: Bool, token: Bool) {
        guard let b = boundary else { return (!glued, false) }
        return (!glued && ShortcutTable.triggersWord(b), ShortcutTable.triggersToken(b))
    }
}

/// Cụm ký tự liền nhau ĐÃ CHỐT ngay trước con trỏ (từ khoảng trắng gần nhất), dựng
/// từ chính các phím mình thấy — không đọc màn hình mỗi phím. `anchored` = đầu cụm
/// chắc chắn đứng ngay sau một khoảng trắng/xuống dòng mình thấy gõ. Mọi sự kiện có
/// thể dời con trỏ (click, phím điều hướng, đổi ô, ⌘-tổ hợp) phải reset().
struct ShortcutTail: Equatable {
    /// Dài hơn khoá dài nhất (64) thì không khoá nào khớp được cho tới khoảng trắng kế.
    static let maxRun = 64
    private(set) var run = ""
    private(set) var anchored = false
    private var runCount = 0

    mutating func reset() { run = ""; runCount = 0; anchored = false }

    /// Văn bản vừa hiện ra trước con trỏ (từ đã chốt, ký tự ranh giới, nội dung nở).
    mutating func append(_ s: String) {
        for ch in s {
            if ch.isWhitespace || ch.isNewline {
                run = ""; runCount = 0; anchored = true
            } else if runCount >= Self.maxRun {
                reset()                       // quá dài: đầu cụm không còn biết
            } else {
                run.append(ch); runCount += 1
            }
        }
    }

    /// ⌫ khi không có từ đang soạn: xoá ký tự cuối cụm; cụm rỗng ⇒ vừa xoá khoảng
    /// trắng, phần trước nó không biết ⇒ mất neo.
    mutating func backspace() {
        if run.isEmpty { anchored = false } else { run.removeLast(); runCount -= 1 }
    }

    /// Cụm vừa bị thay (khoá ký hiệu nở): bỏ cụm, giữ neo, rồi nối nội dung mới.
    mutating func replaceRun(with s: String) {
        run = ""; runCount = 0
        append(s)
    }
}

/// Lần nở gần nhất — ⌫ NGAY SAU đó trả lại đúng chữ đã gõ + ranh giới (một lần).
struct ShortcutUndo: Equatable {
    let typed: String
    let expansion: String
    let boundary: String

    /// Chỉ hứa hoàn tác khi ranh giới là MỘT ký tự in được, không phải xuống dòng
    /// (Enter có thể đã gửi tin; Tab dời focus).
    static func make(typed: String, expansion: String, boundary: String?) -> ShortcutUndo? {
        guard let b = boundary, b.count == 1, let c = b.first, !c.isNewline, c != "\t",
              !typed.isEmpty else { return nil }
        return ShortcutUndo(typed: typed, expansion: expansion, boundary: b)
    }

    /// Văn bản màn hình phải kết thúc bằng (ngay trước con trỏ) để được hoàn tác.
    var onScreen: String { expansion + boundary }
    var restored: String { typed + boundary }
}

/// Xác nhận màn hình trước khi thay (IMKit: đọc lại bằng attributedSubstring). So
/// UTF-16 chính xác — String == của Swift so tương đương chuẩn (NFD == NFC) nên một
/// ô NFD sẽ "khớp" mà độ dài range lệch.
enum ShortcutScreen {
    /// Cửa sổ cần đọc để xác nhận `text` nằm ngay trước `caret` (+1 ký tự trước nó để
    /// kiểm ranh giới). nil nếu caret không đủ chỗ.
    static func readWindow(caret: Int, text: String) -> NSRange? {
        let len = text.utf16.count
        guard len > 0, caret >= len else { return nil }
        let start = max(0, caret - len - 1)
        return NSRange(location: start, length: caret - start)
    }

    /// Range UTF-16 của khoá `token` nếu màn hình (cửa sổ `window` bắt đầu ở
    /// `windowStart`, kết thúc đúng ở `caret`) kết thúc bằng token VÀ token đứng riêng
    /// (đầu văn bản, hoặc ngay sau khoảng trắng/xuống dòng). Ngược lại nil.
    static func tokenRange(caret: Int, token: String, window: String, windowStart: Int) -> NSRange? {
        let w = Array(window.utf16), t = Array(token.utf16)
        guard !t.isEmpty, windowStart + w.count == caret, w.count >= t.count,
              Array(w.suffix(t.count)) == t else { return nil }
        let start = caret - t.count
        if start > 0 {
            guard w.count > t.count, let s = Unicode.Scalar(w[w.count - t.count - 1]),
                  Character(s).isWhitespace || Character(s).isNewline else { return nil }
        }
        return NSRange(location: start, length: t.count)
    }

    /// Range UTF-16 cần thay để hoàn tác `undo` nếu màn hình kết thúc ĐÚNG bằng nội
    /// dung đã nở + ranh giới. Ngược lại nil (⌫ thường).
    static func undoRange(caret: Int, undo: ShortcutUndo, window: String, windowStart: Int) -> NSRange? {
        let w = Array(window.utf16), t = Array(undo.onScreen.utf16)
        guard !t.isEmpty, windowStart + w.count == caret, w.count >= t.count,
              Array(w.suffix(t.count)) == t else { return nil }
        return NSRange(location: caret - t.count, length: t.count)
    }

    /// Ký tự một phím ranh giới vừa để lại trước con trỏ (đưa vào ShortcutTail), nil =
    /// không chèn gì đoán được (phím điều hướng/chức năng U+F700…, ký tự điều khiển).
    static func insertedText(_ characters: String?) -> String? {
        guard let s = characters, s.count == 1, let u = s.unicodeScalars.first else { return nil }
        if u.value < 0x20 || u.value == 0x7F || (0xF700...0xF8FF).contains(u.value) { return nil }
        return s
    }
}
