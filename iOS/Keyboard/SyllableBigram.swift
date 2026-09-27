// SyllableBigram.swift — bảng BIGRAM ÂM TIẾT tĩnh (Resources/vnbigram.bin, GENERATED
// bởi Scripts/gen-syllable-bigram.py — nguồn/giấy phép: docs/DATA-SOURCES.md). Song
// sinh android/keyboard/src/main/kotlin/com/viettelex/keyboard/SyllableBigram.kt —
// sửa hành vi ở đây thì sửa y hệt bên kia.
//
// Mỗi cặp (âm tiết trước a, âm tiết sau b) mang PMI chiết khấu (nat, ≥ 0.25) — mức
// "b hay theo sau a hơn bình thường". Thiếu cặp = 0 (không biết). Gõ vuốt cộng điểm
// này vào ngữ cảnh để chọn dấu (hôm → nay) và phân biệt cặp vuốt gần trùng (không → có).
//
// Layout (LE): 0 "VNB1" | 4 version=1 | 8 count (=vnlexicon) | 12 entries | 16 lexHash
// (FNV-1a 32 của vnlexicon.bin) | 20 qPerNat | 24 reserved×2 | 32 offsets u32[count+1] |
// next u16[entries] (tăng dần trong mỗi dải) | score u8[entries]. id = thứ tự vnlexicon.
//
// mmap (.alwaysMapped), đọc tại chỗ, không giải mã vào heap: RAM bẩn ≈ 0, trang sạch
// chỉ nạp theo dải được tra. Tra O(log n) trong dải của âm tiết trước. Chỉ đọc ⇒
// thread-safe.
import Foundation

final class SyllableBigram {
    let count: Int
    let entries: Int
    private let blob: Data
    private let qPerNat: Float
    private let nextBase: Int
    private let scoreBase: Int

    private init(blob: Data) {
        self.blob = blob
        count = Self.u32(blob, 8)
        entries = Self.u32(blob, 12)
        qPerNat = Float(Self.u32(blob, 20))
        nextBase = 32 + (count + 1) * 4
        scoreBase = nextBase + entries * 2
    }

    private static func u32(_ d: Data, _ off: Int) -> Int {
        Int(UInt32(littleEndian: d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }))
    }

    /// Dải cặp của một âm tiết trước. `size` = 0 ⇒ không có dữ liệu.
    struct Row {
        fileprivate let table: SyllableBigram?
        fileprivate let lo: Int, hi: Int
        var size: Int { hi - lo }

        /// PMI (nat) của âm tiết sau id `next`; 0 nếu không có cặp.
        func score(_ next: Int) -> Float {
            guard let t = table, lo < hi else { return 0 }
            return t.blob.withUnsafeBytes { raw -> Float in
                var l = lo, h = hi
                while l < h {
                    let m = (l + h) / 2
                    let v = Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: t.nextBase + m * 2,
                                                                      as: UInt16.self)))
                    if v < next { l = m + 1 } else if v > next { h = m } else {
                        return Float(raw[t.scoreBase + m]) / t.qPerNat
                    }
                }
                return 0
            }
        }

        /// Duyệt mọi cặp (id âm tiết sau, PMI) của dải — thanh gợi ý lấy top từ kế tiếp.
        func forEach(_ body: (_ next: Int, _ pmi: Float) -> Void) {
            guard let t = table, lo < hi else { return }
            t.blob.withUnsafeBytes { raw in
                for m in lo..<hi {
                    let v = Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: t.nextBase + m * 2,
                                                                      as: UInt16.self)))
                    body(v, Float(raw[t.scoreBase + m]) / t.qPerNat)
                }
            }
        }
    }

    /// Dải của âm tiết trước id `prev` (id vnlexicon).
    func row(_ prev: Int) -> Row {
        guard prev >= 0, prev < count else { return Row(table: nil, lo: 0, hi: 0) }
        return Row(table: self, lo: Self.u32(blob, 32 + prev * 4), hi: Self.u32(blob, 32 + (prev + 1) * 4))
    }

    func score(_ prev: Int, _ next: Int) -> Float { row(prev).score(next) }

    static let qPerNatDefault = 16

    /// Kiểm tra header + khớp lexicon; nil nếu hỏng/lệch (gõ vuốt chạy không bigram).
    static func load(_ d: Data, lexiconHash: UInt32, lexiconCount: Int) -> SyllableBigram? {
        guard d.count >= 32, d.prefix(4).elementsEqual("VNB1".utf8),
              u32(d, 4) == 1, u32(d, 8) == lexiconCount, UInt32(u32(d, 16)) == lexiconHash,
              u32(d, 20) > 0 else { return nil }
        let count = u32(d, 8), entries = u32(d, 12)
        guard 32 + (count + 1) * 4 + entries * 3 == d.count, u32(d, 32 + count * 4) == entries
        else { return nil }
        return SyllableBigram(blob: d)
    }

    /// Bảng dùng chung (gõ vuốt + thanh gợi ý — một lần map) — map lần đầu cần, nên chạm
    /// lần đầu ở hàng đợi nền (hash vnlexicon ~150KB). nil nếu thiếu/hỏng/lệch.
    static let shared: SyllableBigram? = {
        final class BundleToken {}
        guard let url = Bundle(for: BundleToken.self).url(forResource: "vnbigram", withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return load(d, lexiconHash: fnv1a(VNLexicon2Data.blob), lexiconCount: VNLexicon2Data.count)
    }()

    static func fnv1a(_ d: Data) -> UInt32 {
        d.withUnsafeBytes { raw in
            var h: UInt32 = 0x811C9DC5
            for b in raw { h = (h ^ UInt32(b)) &* 0x01000193 }
            return h
        }
    }

    private static let oldStyle: [String: String] = [
        "oà": "òa", "oá": "óa", "oả": "ỏa", "oã": "õa", "oạ": "ọa",
        "oè": "òe", "oé": "óe", "oẻ": "ỏe", "oẽ": "õe", "oẹ": "ọe",
        "uỳ": "ùy", "uý": "úy", "uỷ": "ủy", "uỹ": "ũy", "uỵ": "ụy",
    ]

    /// NFC, chữ thường, kiểu dấu CŨ như vnlexicon (hoà → hòa; quý giữ nguyên).
    static func normalize(_ w: String) -> String {
        let s = w.lowercased().precomposedStringWithCanonicalMapping
        guard s.count >= 2 else { return s }
        let pair = String(s.suffix(2))
        guard let rep = oldStyle[pair] else { return s }
        if pair.first == "u", s.count >= 3, s.dropLast(2).last == "q" { return s }
        return String(s.dropLast(2)) + rep
    }

    /// id vnlexicon của âm tiết `word` (đã normalize), nil nếu không có.
    static func id(of word: String) -> Int? {
        let w = normalize(word)
        guard let f = SwipeLexicon.index(of: SwipeTyping.fold(w)) else { return nil }
        let forms = SwipeLexicon.forms
        for id in Int(forms.idStart[f])..<Int(forms.idStart[f + 1]) where VNSuggest.display(id) == w {
            return id
        }
        return nil
    }
}
