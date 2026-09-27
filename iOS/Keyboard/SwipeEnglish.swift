// SwipeEnglish.swift — GÕ VUỐT giai đoạn 3: vuốt ra TỪ TIẾNG ANH xen trong câu tiếng
// Việt (code-switching). Phần THUẦN, bản Kotlin song sinh:
// android/keyboard/src/main/kotlin/com/viettelex/keyboard/SwipeEnglish.kt — sửa ở đây
// thì sửa y hệt bên kia (parity top-1 qua fixture chung).
//
//   • `SwipeEnglish.lexicon`: ~20k từ tiếng Anh + tần suất 1 byte CÙNG THANG với
//     vnlexicon (Resources/enlexicon.bin, sinh bởi Scripts/gen-enlexicon.py; nguồn +
//     giấy phép: docs/DATA-SOURCES.md). Nạp lười ở lần decode tiếng Anh đầu tiên.
//     Không giữ template: decoder dựng template NGAY LÚC CHẤM cho các từ lọt bộ lọc
//     phím đầu/cuối (xếp sẵn theo cặp phím đầu–cuối) — vài trăm từ mỗi cú vuốt thay
//     vì 20k × 192 B = 3,8 MB template thường trực.
//   • `SwipeLangContext`: P(ngôn ngữ | 1–2 từ trước) → độ lệch điểm cho ứng viên tiếng
//     Anh + biên độ phải thắng. MẶC ĐỊNH NGHIÊNG TIẾNG VIỆT: 182+ từ tiếng Anh trùng hẳn
//     chuỗi với âm tiết Việt (the/thế, to/tô, can/cần…) — nét vuốt y hệt, phân xử sai
//     tệ hơn gõ chạm, nên chỉ chọn tiếng Anh top-1 khi hình học thắng rõ hoặc đang
//     trong mạch tiếng Anh; phương án ngôn ngữ kia luôn nằm trên thanh gợi ý.
import Foundation
import TelexCore

enum SwipeLang: UInt8, Equatable { case vi, en }

enum SwipeEnglish {
    struct Lexicon {
        /// Từ chữ thường a–z, sort tăng dần (binary search).
        let words: [String]
        /// Tần suất 0-255, thang của vnlexicon.
        let freq: [UInt8]
        /// Phím đã gộp chữ lặp (hello → helo), từ i: keys[keyStart[i] ..< keyStart[i+1]].
        let keys: [UInt8]
        let keyStart: [Int32]
        /// Chỉ số từ xếp theo cặp (phím đầu, phím cuối) b = đầu·26 + cuối, trong mỗi
        /// cặp giữ thứ tự chữ cái: order[bucketStart[b] ..< bucketStart[b+1]].
        let order: [Int32]
        let bucketStart: [Int32]
        var count: Int { words.count }

        static let empty = Lexicon(words: [], freq: [], keys: [], keyStart: [0], order: [],
                                   bucketStart: [Int32](repeating: 0, count: 677))
    }

    static let lexicon: Lexicon = {
        final class BundleToken {}
        guard let url = Bundle(for: BundleToken.self).url(forResource: "enlexicon", withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return .empty }
        return parse(d) ?? .empty
    }()

    /// Giải mã enlexicon.bin ("VTE1" | count u32 | [len][freq][ASCII]…). nil = hỏng.
    static func parse(_ d: Data) -> Lexicon? {
        let b = [UInt8](d)
        guard b.count >= 8, b[0] == 0x56, b[1] == 0x54, b[2] == 0x45, b[3] == 0x31 else { return nil }
        let n = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
        var words: [String] = [], freq: [UInt8] = [], keys: [UInt8] = [], keyStart: [Int32] = [0]
        words.reserveCapacity(n); freq.reserveCapacity(n); keyStart.reserveCapacity(n + 1)
        var first = [Int](repeating: 0, count: n), last = first
        var p = 8
        for i in 0..<n {
            guard p + 2 <= b.count else { return nil }
            let len = Int(b[p]), f = b[p + 1]
            guard len > 0, p + 2 + len <= b.count else { return nil }
            var prev: UInt8 = 255
            for j in 0..<len {
                let k = b[p + 2 + j] &- 97
                guard k < 26 else { return nil }
                if k != prev { keys.append(k); prev = k }
            }
            first[i] = Int(keys[Int(keyStart[i])]); last[i] = Int(keys[keys.count - 1])
            keyStart.append(Int32(keys.count))
            words.append(String(decoding: b[(p + 2)..<(p + 2 + len)], as: UTF8.self))
            freq.append(f)
            p += 2 + len
        }
        // counting sort ổn định theo cặp phím đầu–cuối
        var bucketStart = [Int32](repeating: 0, count: 677)
        for i in 0..<n { bucketStart[first[i] * 26 + last[i] + 1] += 1 }
        for bk in 0..<676 { bucketStart[bk + 1] += bucketStart[bk] }
        var fill = Array(bucketStart[0..<676])
        var order = [Int32](repeating: 0, count: n)
        for i in 0..<n {
            let bk = first[i] * 26 + last[i]
            order[Int(fill[bk])] = Int32(i); fill[bk] += 1
        }
        return Lexicon(words: words, freq: freq, keys: keys, keyStart: keyStart,
                       order: order, bucketStart: bucketStart)
    }

    static func index(of word: String) -> Int? {
        let a = lexicon.words
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < word { lo = mid + 1 } else { hi = mid }
        }
        return lo < a.count && a[lo] == word ? lo : nil
    }

    static func contains(_ word: String) -> Bool { index(of: word) != nil }

    /// Chế độ Tiếng Anh (vuốt phím cách): từ bắt đầu bằng `typed` (a–z, không phân biệt
    /// hoa thường), tần suất giảm dần, tối đa `limit`, bỏ chính từ đang gõ. Chữ hoa theo
    /// chữ đang gõ ("Hel" → "Hello", "HEL" → "HELLO"). Chữ ngoài a–z ⇒ [].
    static func completions(_ typed: String, limit: Int = 24, in lex: Lexicon = lexicon) -> [VNSuggest.Match] {
        let low = typed.lowercased()
        guard !low.isEmpty, limit > 0,
              low.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else { return [] }
        let a = lex.words
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < low { lo = mid + 1 } else { hi = mid }
        }
        var hits: [(f: UInt8, i: Int)] = []
        var i = lo
        while i < a.count, a[i].hasPrefix(low) {
            if a[i] != low { hits.append((lex.freq[i], i)) }
            i += 1
        }
        hits.sort { $0.f != $1.f ? $0.f > $1.f : $0.i < $1.i }
        return hits.prefix(limit).map { VNSuggest.Match(word: matchCase(a[$0.i], typed), freq: Int($0.f)) }
    }

    /// Từ phổ biến nhất (đệm thanh gợi ý ở chế độ Tiếng Anh khi chưa gõ gì).
    static func topWords(limit: Int, in lex: Lexicon = lexicon) -> [String] {
        guard limit > 0 else { return [] }
        return lex.freq.indices.sorted { lex.freq[$0] != lex.freq[$1] ? lex.freq[$0] > lex.freq[$1] : $0 < $1 }
            .prefix(limit).map { lex.words[$0] }
    }
    static let top: [String] = topWords(limit: 12)

    static func matchCase(_ w: String, _ typed: String) -> String {
        guard let f = typed.first, f.isUppercase else { return w }
        if typed.count > 1, typed.allSatisfy({ $0.isUppercase }) { return w.uppercased() }
        return w.prefix(1).uppercased() + w.dropFirst()
    }
}

/// Tham số tiếng Anh cho một lần decode (xem SwipeLangContext.prior).
struct SwipeEnglishPrior: Equatable {
    /// Cộng vào điểm mọi ứng viên tiếng Anh (log-domain; âm = nghiêng Việt).
    var bias: Float
    /// Tiếng Anh chỉ giữ top-1 khi hơn ứng viên Việt tốt nhất ≥ margin; không thì
    /// ứng viên Việt đó lên đầu (tiếng Anh vẫn nằm trong danh sách → thanh gợi ý).
    var margin: Float
}

/// Ngữ cảnh ngôn ngữ từ 1–2 từ trước con trỏ.
enum SwipeLangContext {
    enum Kind: Equatable { case vi, en, neutral }

    // Hằng số — GIỮ Y HỆT bản Kotlin. Chọn bằng quét (SwipeEnglishTests.kt sweepPriors,
    // đường vuốt giả σ0.25): ngưỡng hiệu dụng bias−margin ≈ −1.2 là mức nhỏ nhất đưa MỌI
    // cặp trùng chuỗi trong top-1000 Anh (58 cặp: the/thế, can/cần…) về tiếng Việt khi
    // ngữ cảnh Việt, mà top-1 Việt không đổi (0.900) và từ Anh riêng hình vẫn thắng.
    // Mạch Anh: bias 0.2 cân hai ngôn ngữ (từ Việt sau một từ Anh vẫn hay gặp: "app chưa").
    static let defaultPrior = SwipeEnglishPrior(bias: -0.9, margin: 0.3)
    static let englishPrior = SwipeEnglishPrior(bias: 0.2, margin: 0)
    static let strongEnglishPrior = SwipeEnglishPrior(bias: 0.5, margin: 0)
    static let weakEnglishPrior = SwipeEnglishPrior(bias: -0.3, margin: 0.3)
    /// Chế độ Tiếng Anh: đẩy hẳn tiếng Anh lên (ứng viên Việt bị lọc bỏ sau decode).
    static let onlyEnglishPrior = SwipeEnglishPrior(bias: 4, margin: 0)

    /// Phân loại một từ đã có trên màn hình. `swipedEnglish` = từ đó vừa được vuốt ra
    /// như từ tiếng Anh (nhãn decoder) — chắc chắn nhất.
    static func classify(_ word: String?, swipedEnglish: Bool = false) -> Kind {
        guard let raw = word, !raw.isEmpty else { return .neutral }
        if swipedEnglish { return .en }
        let w = raw.lowercased()
        guard w.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else {
            // có dấu / đ ⇒ tiếng Việt; số, ký hiệu ⇒ không rõ
            return w.unicodeScalars.contains { $0.value > 127 } ? .vi : .neutral
        }
        // cùng bảng với engine.contextualEnglish: từ mượn giữ nguyên mạch, từ chức năng
        // tiếng Anh mở mạch
        if EnglishContextLookup.isNeutralLoanword(w) { return .neutral }
        if EnglishContextLookup.opensEnglishRun(w) { return .en }
        let vnForm = SwipeLexicon.index(of: w) != nil
        if SwipeEnglish.contains(w) { return vnForm ? .neutral : .en }
        return vnForm ? .vi : .neutral
    }

    /// Độ lệch tiếng Anh theo 2 từ trước (prev1 = liền trước).
    static func prior(prev1: Kind, prev2: Kind) -> SwipeEnglishPrior {
        switch (prev1, prev2) {
        case (.en, .en): return strongEnglishPrior
        case (.en, _): return englishPrior
        case (.neutral, .en): return weakEnglishPrior
        default: return defaultPrior
        }
    }
}
