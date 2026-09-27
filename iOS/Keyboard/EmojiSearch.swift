// EmojiSearch — tìm emoji bằng tiếng Việt trong bàn phím emoji. Khoá (section SKEY
// của emoji.bin): từ khoá gợi ý emoji sẵn có (EmojiSuggest) + tên/từ khoá CLDR vi.
// Khớp TIỀN TỐ KHÔNG DẤU tại đầu một từ bất kỳ của khoá ("cuoi" → "mặt cười");
// xếp hạng: trùng nguyên khoá có dấu > trùng nguyên khoá không dấu > tiền tố có dấu
// > tiền tố đầu khoá > tiền tố ở từ sau; cùng hạng thì khoá ngắn trước.
// Quét tuyến tính ~6.5k khoá trên blob mmap (không dựng dictionary) — < 1 ms/phím.
import Foundation
import TelexCore

enum EmojiSearch {
    /// Luật fold PHẢI khớp Scripts/gen-emoji-data.py: chữ thường, bỏ dấu (đ→d),
    /// dấu câu → space, gộp space.
    static func fold(_ s: String) -> String {
        clean(s.lowercased().replacingOccurrences(of: "đ", with: "d")
            .decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
            .reduce(into: "") { $0.unicodeScalars.append($1) })
    }

    /// Chữ thường NFC, ký tự không phải chữ/số → space, gộp space.
    static func clean(_ s: String) -> String {
        let n = s.lowercased().precomposedStringWithCanonicalMapping
        var out = ""
        var pendingSpace = false
        for ch in n {
            if ch.isLetter || ch.isNumber {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(ch)
            } else {
                pendingSpace = true
            }
        }
        return out
    }

    private static let base = EmojiData.section("SKEY")
    static let keyCount = EmojiData.u32(base)
    private static var foldOffBase: Int { base + 4 }
    private static var origOffBase: Int { base + 4 + (keyCount + 1) * 4 }
    private static var idOffBase: Int { base + 4 + 2 * (keyCount + 1) * 4 }
    private static let foldBase = base + 4 + 3 * (keyCount + 1) * 4
    private static let origBase = foldBase + EmojiData.u32(base + 4 + keyCount * 4)
    private static let idBase = origBase + EmojiData.u32(base + 4 + (keyCount + 1) * 4 + keyCount * 4)

    /// Emoji khớp `query` (đã theo thứ tự hạng, không trùng, chỉ emoji vẽ được).
    static func search(_ query: String, limit: Int = 60,
                       supported: (Int) -> Bool = EmojiData.isSupported) -> [String] {
        ids(query, limit: limit, supported: supported).map(EmojiData.emoji)
    }

    static func ids(_ query: String, limit: Int = 60,
                    supported: (Int) -> Bool = EmojiData.isSupported) -> [Int] {
        let q = clean(query)
        let qf = Array(fold(q).utf8)
        guard !qf.isEmpty else { return [] }
        let qo = Array(q.utf8)
        var hits: [(rank: Int, len: Int, key: Int)] = []
        EmojiData.blob.withUnsafeBytes { raw in
            func u32(_ o: Int) -> Int { Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
            for k in 0..<keyCount {
                let fs = foldBase + u32(foldOffBase + k * 4)
                let fe = foldBase + u32(foldOffBase + k * 4 + 4)
                guard let pos = wordPrefix(raw, fs, fe, qf) else { continue }
                let os = origBase + u32(origOffBase + k * 4)
                let oe = origBase + u32(origOffBase + k * 4 + 4)
                let exactFold = pos == 0 && fe - fs == qf.count
                let rank: Int
                if exactFold && equal(raw, os, oe, qo) { rank = 0 }
                else if exactFold { rank = 1 }
                else if wordPrefix(raw, os, oe, qo) != nil { rank = 2 }
                else if pos == 0 { rank = 3 }
                else { rank = 4 }
                hits.append((rank, fe - fs, k))
            }
        }
        hits.sort { ($0.rank, $0.len, $0.key) < ($1.rank, $1.len, $1.key) }
        var out: [Int] = []
        var seen = Set<Int>()
        for h in hits {
            let s = EmojiData.u32(idOffBase + h.key * 4), e = EmojiData.u32(idOffBase + h.key * 4 + 4)
            for j in s..<e {
                let id = EmojiData.u16(idBase + j * 2)
                if seen.insert(id).inserted, supported(id) {
                    out.append(id)
                    if out.count >= limit { return out }
                }
            }
        }
        return out
    }

    /// Vị trí (byte) nơi `q` là tiền tố của một từ trong [s, e) — đầu khoá hoặc sau space.
    private static func wordPrefix(_ raw: UnsafeRawBufferPointer, _ s: Int, _ e: Int, _ q: [UInt8]) -> Int? {
        let n = q.count
        var i = s
        while i + n <= e {
            if i == s || raw[i - 1] == 0x20 {
                var j = 0
                while j < n && raw[i + j] == q[j] { j += 1 }
                if j == n { return i - s }
            }
            i += 1
        }
        return nil
    }

    private static func equal(_ raw: UnsafeRawBufferPointer, _ s: Int, _ e: Int, _ q: [UInt8]) -> Bool {
        guard e - s == q.count else { return false }
        for j in 0..<q.count where raw[s + j] != q[j] { return false }
        return true
    }
}

/// Ô tìm emoji tự vẽ: gõ bằng chính phím VietTelex, có Telex (engine riêng, không
/// đụng composition của ô nhập thật). Thuần logic — KeyboardView lo vẽ.
struct EmojiSearchSession {
    private var engine: TelexEngine
    private var committed = ""

    init() {
        var e = TelexEngine()
        let s = KeyboardSettings.load()
        e.freeMarking = s.freeMarking
        e.simpleTelex = s.simpleTelex
        e.quickTelex = s.quickTelex
        e.modernTone = s.modernTone
        e.liveSpellCheck = s.liveSpellCheck
        e.teencode = s.teencode
        engine = e
    }

    /// Chuỗi đang hiện trong ô tìm.
    var query: String { committed + engine.peekCommitText(autoRestore: false) }

    mutating func type(_ ch: Character) {
        let c = Character(ch.lowercased())
        if c.isLetter, c.isASCII {
            _ = engine.feed(c)
        } else {
            commitWord()
            committed.append(c)
        }
    }

    mutating func insert(_ s: String) {
        for ch in s { type(ch) }
    }

    mutating func space() {
        commitWord()
        if !committed.isEmpty, committed.last != " " { committed.append(" ") }
    }

    mutating func backspace() {
        if !engine.isEmpty {
            _ = engine.backspace()
        } else if !committed.isEmpty {
            committed.removeLast()
        }
    }

    mutating func clear() {
        engine.reset()
        committed = ""
    }

    private mutating func commitWord() {
        guard !engine.isEmpty else { return }
        committed += engine.commitText(autoRestore: true)
    }
}
