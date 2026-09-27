// SwipeLexicon.swift — dạng KHÔNG DẤU của vnlexicon (tách khỏi SwipeDecoder.swift để
// dùng chung: gõ vuốt, Thêm dấu (AddTones) — cả bản macOS biên dịch file này theo đường
// dẫn, xem project.yml gốc repo). Thuần Foundation.
import Foundation

// MARK: - Lexicon dạng không dấu (lười)

/// 1666 dạng không dấu rút từ vnlexicon.bin (entry đã sort theo folded rồi
/// tần suất giảm dần → mỗi dạng là một dải id liên tiếp, entry đầu có tần
/// suất cao nhất).
enum SwipeLexicon {
    struct Forms {
        let folded: [String]
        /// Dải id lexicon của dạng f: idStart[f] ..< idStart[f+1].
        let idStart: [Int32]
        /// Tần suất (0-255) = entry mạnh nhất của dạng.
        let freq: [UInt8]
        /// Phím đã gộp chữ lặp (0…25), dạng f: keys[keyStart[f] ..< keyStart[f+1]].
        let keys: [UInt8]
        let keyStart: [Int32]
        var count: Int { folded.count }
    }

    static let forms: Forms = {
        let n = VNLexicon2Data.count
        let off = VNLexicon2Data.offsets
        var folded: [String] = [], idStart: [Int32] = [], freq: [UInt8] = []
        var keys: [UInt8] = [], keyStart: [Int32] = [0]
        folded.reserveCapacity(1700); idStart.reserveCapacity(1701)
        var prev = Data()
        for id in 0..<n {
            let f = VNLexicon2Data.foldedSlice(Int(off[id]), Int(off[id + 1]))
            if id > 0 && f.elementsEqual(prev) { continue }
            prev = f
            folded.append(String(decoding: f, as: UTF8.self))
            idStart.append(Int32(id))
            freq.append(VNLexicon2Data.freq(id))
            var last: UInt8 = 255
            for b in f {
                let k = b &- 97
                if k != last { keys.append(k); last = k }
            }
            keyStart.append(Int32(keys.count))
        }
        idStart.append(Int32(n))
        return Forms(folded: folded, idStart: idStart, freq: freq,
                     keys: keys, keyStart: keyStart)
    }()

    /// Chỉ số dạng `folded` (binary search, ASCII) — nil nếu không có.
    static func index(of folded: String) -> Int? {
        let a = forms.folded
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < folded { lo = mid + 1 } else { hi = mid }
        }
        return lo < a.count && a[lo] == folded ? lo : nil
    }

    /// Bỏ dấu tiếng Việt (đ → d), chữ thường — khoá so với dạng không dấu của lexicon.
    static func fold(_ w: String) -> String {
        w.lowercased().replacingOccurrences(of: "đ", with: "d")
            .folding(options: .diacriticInsensitive, locale: nil)
    }
}
