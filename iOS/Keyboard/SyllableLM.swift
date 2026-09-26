// SyllableLM.swift — MÔ HÌNH NGÔN NGỮ ÂM TIẾT TRIGRAM tĩnh cho gõ vuốt (Resources/vnlm.bin,
// GENERATED bởi Scripts/gen-syllable-lm.py — nguồn/giấy phép: docs/DATA-SOURCES.md). Song
// sinh android/keyboard/src/main/kotlin/com/viettelex/keyboard/SyllableLM.kt — sửa hành vi
// ở đây thì sửa y hệt bên kia.
//
// Kneser-Ney nội suy bậc 3 đã cắt tỉa. Điểm s (nat) của âm tiết c sau (a, b) =
// ln(P(c|a,b) / P1(c)): > 0 = hay theo sau hơn bình thường, < 0 = hiếm. Thiếu mục ⇒ lùi:
// dòng trigram (a,b) có mà thiếu c → γ3(ab) + s2(b,c); không có dòng → s2(b,c); bigram
// thiếu → γ2(b). Khác vnbigram.bin (chỉ PMI dương, 1 âm tiết trước): có bằng chứng ÂM và
// 2 âm tiết trước. vnbigram.bin vẫn giữ cho thanh gợi ý gõ chạm.
//
// Layout (LE) — xem docstring script: 0 "VNM1" | 4 version=1 | 8 count | 12 lexHash |
// 16 qPerNat | 20 biEntries | 24 triContexts | 28 triEntries | 32 reserved×4 |
// 48 gamma2 i8[count] (pad 4) | biOff u32[count+1] | biNext u16[] | biScore i8[] (pad 4) |
// ctxKey u32[] (a<<16|b tăng dần) | ctxOff u32[ctx+1] | ctxGamma i8[] | triNext u16[] |
// triScore i8[].
//
// mmap (.alwaysMapped), đọc tại chỗ: RAM bẩn ≈ 0. Chỉ đọc ⇒ thread-safe.
import Foundation

final class SyllableLM {
    let count: Int
    let biEntries: Int
    let triContexts: Int
    let triEntries: Int
    private let blob: Data
    private let qPerNat: Float
    private let g2Base = 48
    private let biOffBase: Int, biNextBase: Int, biScoreBase: Int
    private let ctxKeyBase: Int, ctxOffBase: Int, ctxGammaBase: Int
    private let triNextBase: Int, triScoreBase: Int
    let byteCount: Int

    private static func pad4(_ n: Int) -> Int { (n + 3) & ~3 }

    private init?(blob: Data) {
        guard blob.count >= 48 else { return nil }
        self.blob = blob
        count = Self.u32(blob, 8)
        qPerNat = Float(Self.u32(blob, 16))
        biEntries = Self.u32(blob, 20)
        triContexts = Self.u32(blob, 24)
        triEntries = Self.u32(blob, 28)
        biOffBase = g2Base + Self.pad4(count)
        biNextBase = biOffBase + (count + 1) * 4
        biScoreBase = biNextBase + biEntries * 2
        ctxKeyBase = biScoreBase + Self.pad4(biEntries)
        ctxOffBase = ctxKeyBase + triContexts * 4
        ctxGammaBase = ctxOffBase + (triContexts + 1) * 4
        triNextBase = ctxGammaBase + triContexts
        triScoreBase = triNextBase + triEntries * 2
        byteCount = triScoreBase + triEntries
    }

    private static func u32(_ d: Data, _ off: Int) -> Int {
        Int(UInt32(littleEndian: d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }))
    }

    private func i8(_ raw: UnsafeRawBufferPointer, _ off: Int) -> Float {
        Float(Int8(bitPattern: raw[off])) / qPerNat
    }

    /// Tìm `key` trong dải u16 [lo, hi) bắt đầu ở `base`; trả chỉ số hoặc -1.
    private static func find16(_ raw: UnsafeRawBufferPointer, _ base: Int, _ lo: Int, _ hi: Int, _ key: Int) -> Int {
        var l = lo, h = hi
        while l < h {
            let m = (l + h) / 2
            let v = Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: base + m * 2, as: UInt16.self)))
            if v < key { l = m + 1 } else if v > key { h = m } else { return m }
        }
        return -1
    }

    /// Ngữ cảnh đã tra sẵn cho một vị trí (1–2 âm tiết trước). Tra điểm O(log n).
    struct Context {
        fileprivate let lm: SyllableLM
        fileprivate let g2: Float
        fileprivate let biLo: Int, biHi: Int
        /// Dải trigram (triLo < 0 ⇒ không có dòng trigram cho (prev2, prev1)).
        fileprivate let triLo: Int, triHi: Int
        fileprivate let g3: Float

        /// s (nat) của âm tiết id `w`.
        func score(_ w: Int) -> Float {
            guard w >= 0, w < lm.count else { return 0 }
            return lm.blob.withUnsafeBytes { raw -> Float in
                if triLo >= 0 {
                    let j = SyllableLM.find16(raw, lm.triNextBase, triLo, triHi, w)
                    if j >= 0 { return lm.i8(raw, lm.triScoreBase + j) }
                }
                let j = SyllableLM.find16(raw, lm.biNextBase, biLo, biHi, w)
                let s2 = j >= 0 ? lm.i8(raw, lm.biScoreBase + j) : g2
                return triLo >= 0 ? g3 + s2 : s2
            }
        }
    }

    /// Ngữ cảnh sau (`prev2`, `prev1`) — id vnlexicon, -1 = không có. nil nếu prev1 không
    /// hợp lệ (không có ngữ cảnh ⇒ caller chấm như không có LM).
    func context(prev2: Int, prev1: Int) -> Context? {
        guard prev1 >= 0, prev1 < count else { return nil }
        return blob.withUnsafeBytes { raw -> Context in
            let g2 = i8(raw, g2Base + prev1)
            let lo = Self.u32(blob, biOffBase + prev1 * 4), hi = Self.u32(blob, biOffBase + (prev1 + 1) * 4)
            var tLo = -1, tHi = -1
            var g3: Float = 0
            if prev2 >= 0, prev2 < count {
                let key = UInt32(prev2) << 16 | UInt32(prev1)
                var l = 0, h = triContexts
                while l < h {
                    let m = (l + h) / 2
                    let v = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: ctxKeyBase + m * 4, as: UInt32.self))
                    if v < key { l = m + 1 } else if v > key { h = m } else {
                        tLo = Self.u32(blob, ctxOffBase + m * 4)
                        tHi = Self.u32(blob, ctxOffBase + (m + 1) * 4)
                        g3 = i8(raw, ctxGammaBase + m)
                        break
                    }
                }
            }
            return Context(lm: self, g2: g2, biLo: lo, biHi: hi, triLo: tLo, triHi: tHi, g3: g3)
        }
    }

    /// s (nat) của `w` sau (`prev2`, `prev1`); 0 nếu không có ngữ cảnh.
    func score(prev2: Int, prev1: Int, _ w: Int) -> Float {
        context(prev2: prev2, prev1: prev1)?.score(w) ?? 0
    }

    /// Kiểm tra header + khớp lexicon + kích thước; nil nếu hỏng/lệch (gõ vuốt lùi về
    /// vnbigram.bin).
    static func load(_ d: Data, lexiconHash: UInt32, lexiconCount: Int) -> SyllableLM? {
        guard d.count >= 48, d.prefix(4).elementsEqual("VNM1".utf8),
              u32(d, 4) == 1, u32(d, 8) == lexiconCount, UInt32(u32(d, 12)) == lexiconHash,
              u32(d, 16) > 0, let lm = SyllableLM(blob: d), lm.byteCount == d.count,
              u32(d, lm.biOffBase + lm.count * 4) == lm.biEntries,
              u32(d, lm.ctxOffBase + lm.triContexts * 4) == lm.triEntries
        else { return nil }
        return lm
    }

    /// Mô hình dùng chung — map lần đầu cần (chỉ khi gõ vuốt bật). nil nếu thiếu/hỏng/lệch.
    static let shared: SyllableLM? = {
        final class BundleToken {}
        guard let url = Bundle(for: BundleToken.self).url(forResource: "vnlm", withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return load(d, lexiconHash: SyllableBigram.fnv1a(VNLexicon2Data.blob), lexiconCount: VNLexicon2Data.count)
    }()
}
