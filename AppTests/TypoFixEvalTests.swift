// TypoFixEvalTests — đo "Gợi ý sửa lỗi gõ sai" (TypoFixLogic, CaretSuggestions.swift) trên BÀN
// PHÍM CỨNG: không có điểm chạm như iOS/Android (AutoCorrectEvalTests.kt), nên mô phỏng lỗi gõ
// phím Mac: câu heldout (iOS/KeyboardTests/Fixtures/bigram-heldout.txt — không nằm trong dữ liệu
// dựng lexicon/LM) → chuỗi phím Telex (TelexSpell, kiểm bằng engine thật với setting mặc định
// Mac) → mỗi từ có xác suất `rate` bị MỘT lỗi: thay phím kề 45% | sót phím 20% | thừa phím kề
// 15% | đảo hai phím 15% | lặp phím 5% → engine + auto-restore (chữ trên màn hình) → cổng
// kích hoạt + bản sửa y hệt production.
//  • precision = gợi ý đúng / mọi gợi ý (gồm gợi ý cho từ gõ ĐÚNG = oan);
//    recall = gợi ý đúng / từ ra sai (mọi loại lỗi — kể cả loại không sửa được).
//  • Tập GIỮ NGUYÊN (gõ đúng + gõ có lỗi): tiếng Anh theo tần suất enlexicon, từ chat seed,
//    từ lạ (OOV), gõ không dấu — gợi ý cho bản gõ đúng = oan; bản có lỗi chỉ đúng khi về đúng từ.
//
// Kết quả (28/09/2026; `TEST_RUNNER_TYPOFIX_EVAL=1 xcodebuild … test` in lưới DEV):
//   DEV — chỉ thay phím kề: P ≤ 97% chỉ khi minFreq 210 (R 7.6%); + đảo phím: P 98.0% R 11.3%;
//   + bỏ/thêm phím làm ĐỐI THỦ (không đề xuất): minFreq 150 margin 80 ⇒ P 98.5% R 17.6% (chọn);
//   đề xuất cả bỏ/thêm phím không hơn (P 98.5% R 17.5% ở 170/120).
//   TEST (2 seed × lỗi 10%/20% + giữ nguyên): P 98.1% R 20.7% (1048 gợi ý: 1028 đúng, 20 nhầm,
//   0 oan); riêng câu Việt P 99.9% R 24–30%. R tính trên MỌI từ ra sai (cả lỗi sót/thừa phím
//   không sửa được); "nhầm" gần hết là từ Anh/không dấu gõ sai bị gợi ý về một từ Việt.
import XCTest
@testable import VietTelex
import TelexCore

final class TypoFixEvalTests: XCTestCase {
    // MARK: Dữ liệu

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static let heldout: [[String]] = {
        let url = root.appendingPathComponent("iOS/KeyboardTests/Fixtures/bigram-heldout.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: " ").map(String.init) }
    }()
    private static var dev: [[String]] { heldout.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }
    private static var test: [[String]] { heldout.enumerated().filter { $0.offset % 2 == 1 }.map(\.element) }

    private static let flags = AppState.EngineFlags()        // setting mặc định macOS
    private static let compose = TypoFixLogic.composer(flags)

    /// Chữ engine để lại trên màn hình ở ranh giới (auto-restore bật như mặc định).
    private static func screen(_ raw: String) -> String {
        var e = TelexEngine(); e.apply(flags)
        for ch in raw { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    /// Chuỗi phím Telex (bản sao TelexSpell ở iOS/Keyboard/TouchTarget.swift — file đó kéo theo
    /// dữ liệu seed/trie không có trên Mac). Tỉ trọng: dấu thanh cuối 0.6 / trước phụ âm cuối 0.4.
    private static func variants(_ syllable: String) -> [(keys: String, share: Double)] {
        var chars: [String] = []
        var tone: Character?
        for u in syllable.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.value {
            case 0x302: guard let k = chars.last else { return [] }; chars[chars.count - 1] = k + k
            case 0x306, 0x31B: guard let k = chars.last else { return [] }; chars[chars.count - 1] = k + "w"
            case 0x301: tone = "s"
            case 0x300: tone = "f"
            case 0x309: tone = "r"
            case 0x303: tone = "x"
            case 0x323: tone = "j"
            case 0x111: chars.append("dd")
            case 0x61...0x7A: chars.append(String(Character(u)))
            default: return []
            }
        }
        guard !chars.isEmpty else { return [] }
        let all = chars.joined()
        guard let t = tone else { return [(all, 1)] }
        var lastVowel = -1
        for (i, c) in chars.enumerated() where "aeiouy".contains(c.first!) { lastVowel = i }
        guard lastVowel >= 0, lastVowel < chars.count - 1 else { return [(all + String(t), 1)] }
        let head = chars[0...lastVowel].joined(), coda = chars[(lastVowel + 1)...].joined()
        return [(all + String(t), 0.6), (head + String(t) + coda, 0.4)]
    }

    private static var variantCache: [String: [(keys: String, share: Double)]] = [:]
    private static func validVariants(_ s: String) -> [(keys: String, share: Double)] {
        if let v = variantCache[s] { return v }
        let want = SyllableLM.normalize(s)
        let v = variants(s).filter { SyllableLM.normalize(compose($0.keys)) == want }
        variantCache[s] = v
        return v
    }

    private static func toneless(_ s: String) -> String {
        String(String.UnicodeScalarView(s.replacingOccurrences(of: "đ", with: "d")
            .decomposedStringWithCanonicalMapping.unicodeScalars.filter { $0.value < 0x300 || $0.value > 0x36F }))
    }

    // MARK: Mô phỏng lỗi phím cứng

    private struct RNG {
        var s: UInt64
        mutating func next() -> UInt64 {
            s &+= 0x9E3779B97F4A7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    /// MỘT lỗi gõ phím cứng lên `keys`.
    private static func typo(_ keys: String, _ rng: inout RNG) -> String {
        var c = Array(keys)
        let nb = AdjacentKeyFixer.physicalNeighbors
        let r = rng.unit(), i = rng.int(c.count)
        func neighbor(_ k: Character) -> Character? {
            guard let n = nb[k], !n.isEmpty else { return nil }
            return n[rng.int(n.count)]
        }
        if r < 0.45 {
            if let n = neighbor(c[i]) { c[i] = n }
        } else if r < 0.65 {
            if c.count > 1 { c.remove(at: i) }
        } else if r < 0.80 {
            if let n = neighbor(c[i]) { c.insert(n, at: rng.int(2) == 0 ? i : i + 1) }
        } else if r < 0.95 {
            if c.count > 1 { let j = min(i, c.count - 2); c.swapAt(j, j + 1) }
        } else {
            c.insert(c[i], at: i)
        }
        return String(c)
    }

    // MARK: Chấm

    /// Một từ đã gõ: ứng viên (nil = không qua cổng), đúng/sai, dạng muốn.
    private struct Rec {
        let typed: String
        let cands: [TypoFixLogic.Cand]?     // mọi loại sửa; nil = không qua cổng
        let ok: Bool
        let want: String
    }

    /// Cổng production: worthChecking (chữ màn hình không phải âm tiết) + các loại trừ của
    /// `correction` (đã biết / đang là từ / còn là tiền tố) — phần không phụ thuộc ngưỡng.
    private static func rec(typed: String, ok: Bool, want: String) -> Rec {
        let word = screen(typed)
        guard TypoFixLogic.worthChecking(boundary: " ", raw: typed, word: word, minLen: 3) else {
            return Rec(typed: typed, cands: nil, ok: ok, want: want)
        }
        let lower = typed.lowercased()
        let cur = compose(lower)
        let freq: (String) -> Int? = { VNSuggest.frequency(of: $0) }
        let hasC: (String) -> Bool = { !VNSuggest.matches($0, poolLimit: 1).isEmpty }
        if TypoFixLogic.isKnown(lower) || (cur != lower && TypoFixLogic.isKnown(cur.lowercased()))
            || freq(cur) != nil || hasC(cur) {
            return Rec(typed: typed, cands: nil, ok: ok, want: want)
        }
        let all = TypoFixLogic.candidates(lower, compose: compose, frequency: freq, hasCompletion: hasC)
        return Rec(typed: typed, cands: all, ok: ok, want: want)
    }

    private static func collectVn(_ sents: [[String]], rate: Double, seed: UInt64) -> [Rec] {
        var rng = RNG(s: seed)
        var out: [Rec] = []
        for sent in sents {
            for syl in sent {
                let v = validVariants(syl)
                guard !v.isEmpty else { continue }
                var x = rng.unit() * v.reduce(0) { $0 + $1.share }
                var keys = v.last!.keys
                for (k, w) in v { x -= w; if x <= 0 { keys = k; break } }
                let typed = rng.unit() < rate ? typo(keys, &rng) : keys
                let want = SyllableLM.normalize(syl)
                out.append(rec(typed: typed, ok: SyllableLM.normalize(compose(typed)) == want, want: want))
            }
        }
        return out
    }

    private static func collectKeep(_ words: [String], rate: Double, seed: UInt64) -> [Rec] {
        var rng = RNG(s: seed)
        return words.filter { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isLowercase } }.map { w in
            let typed = rng.unit() < rate ? typo(w, &rng) : w
            return rec(typed: typed, ok: typed == w, want: w)
        }
    }

    private static func englishWords(_ n: Int, seed: UInt64) -> [String] {
        let lx = SwipeEnglish.lexicon
        let w = (0..<lx.count).map { exp(0.06 * (Double(lx.freq[$0]) - 255)) }
        let tot = w.reduce(0, +)
        var rng = RNG(s: seed)
        return (0..<n).map { _ in
            var r = rng.unit() * tot, i = 0
            while i < w.count - 1, r > w[i] { r -= w[i]; i += 1 }
            return lx.words[i]
        }
    }

    private static let oov = ["khum", "mng", "nma", "nhma", "tks", "thx", "pls", "plz", "omg", "hcm", "tphcm",
        "kpop", "hic", "hix", "ntn", "trc", "bik", "thik", "zui", "kkk", "hjhj", "vcd", "hqua", "hnay", "nguoi",
        "ngta", "vch", "cty", "sdt", "cmnd", "gplx", "atm", "iphone", "macbook", "zalo", "shopee", "tiktok",
        "grab", "momo", "vnexpress", "hanoi", "saigon", "danang", "nguyen", "tran", "pham", "huynh"]

    private static func keepSets(_ n: Int, _ sents: [[String]]) -> [(String, [String])] {
        let chat = Array(TypoFixLogic.chatWords).sorted()
        let tl = sents.prefix(400).flatMap { $0 }.map(toneless)
        return [("en", englishWords(n, seed: 7)), ("chat", Array(repeating: chat, count: 3).flatMap { $0 }),
                ("oov", Array(repeating: oov, count: 5).flatMap { $0 }), ("khôngdấu", tl)]
    }

    private struct Score: CustomStringConvertible {
        var fix = 0, good = 0, wrong = 0, falseFix = 0, err = 0, words = 0
        var precision: Double { fix == 0 ? 1 : Double(good) / Double(fix) }
        var recall: Double { err == 0 ? 0 : Double(good) / Double(err) }
        mutating func add(_ o: Score) {
            fix += o.fix; good += o.good; wrong += o.wrong; falseFix += o.falseFix; err += o.err; words += o.words
        }
        var description: String {
            String(format: "từ %d | sai %d | gợi ý %d (đúng %d, nhầm %d, oan %d) | P=%.1f%% R=%.1f%%",
                   words, err, fix, good, wrong, falseFix, 100 * precision, 100 * recall)
        }
    }

    private static func decide(_ r: Rec, _ p: TypoFixLogic.Params) -> TypoFixLogic.Cand? {
        guard r.typed.count >= p.minLen, let c = r.cands else { return nil }
        return TypoFixLogic.pick(c, p: p)
    }

    private static func score(_ recs: [Rec], _ p: TypoFixLogic.Params, dump: Bool = false) -> Score {
        var s = Score()
        for r in recs {
            s.words += 1
            if !r.ok { s.err += 1 }
            guard let c = decide(r, p) else { continue }
            s.fix += 1
            if r.ok { s.falseFix += 1 } else if SyllableLM.normalize(c.word) == r.want { s.good += 1 } else { s.wrong += 1 }
            if dump, r.ok || SyllableLM.normalize(c.word) != r.want {
                print("DUMP \(r.typed) → \(c.word) (muốn \(r.want)) | " +
                      r.cands!.map { "\($0.word):\($0.freq)\($0.edit)" }.joined(separator: " "))
            }
        }
        return s
    }

    private static func total(_ sents: [[String]], _ p: TypoFixLogic.Params, seeds: [UInt64],
                              rates: [Double], log: String? = nil) -> Score {
        var tot = Score()
        for sd in seeds {
            for rate in rates {
                let v = score(collectVn(sents, rate: rate, seed: sd), p)
                tot.add(v)
                if let log { print("\(log) vn seed=\(sd) lỗi=\(Int(rate * 100))% | \(v)") }
            }
        }
        for (name, w) in keepSets(1500, sents) {
            let a = score(collectKeep(w, rate: 0, seed: 1), p)
            let b = score(collectKeep(w, rate: 0.2, seed: 3), p)
            tot.add(a); tot.add(b)
            if let log { print("\(log) giữ-nguyên \(name) gõ-đúng | \(a)"); print("\(log) giữ-nguyên \(name) lỗi-20% | \(b)") }
        }
        return tot
    }

    // MARK: Test

    /// Hồi quy: precision ≥ 97% trên TEST (VN 2 seed × lỗi 10%/20% + tập giữ nguyên), recall có sàn.
    func testPrecisionFloorOnHeldout() throws {
        try XCTSkipIf(Self.heldout.isEmpty, "không thấy bigram-heldout.txt")
        let tot = Self.total(Self.test, TypoFixLogic.defaults, seeds: [11, 22], rates: [0.1, 0.2], log: "TEST")
        print("TYPOFIX TEST TỔNG | \(tot)")
        XCTAssertGreaterThanOrEqual(tot.precision, 0.97, "\(tot)")
        XCTAssertGreaterThanOrEqual(tot.recall, 0.10, "\(tot)")
    }

    /// Lưới ngưỡng trên DEV (chỉ khi TYPOFIX_EVAL=1).
    func testTuneGridOnDev() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TYPOFIX_EVAL"] == nil, "TYPOFIX_EVAL=1 để dò")
        var vn: [Rec] = []
        for sd: UInt64 in [1, 2] { vn += Self.collectVn(Self.dev, rate: 0.15, seed: sd) }
        var keep: [Rec] = []
        for (_, w) in Self.keepSets(1500, Self.dev) {
            keep += Self.collectKeep(w, rate: 0, seed: 1) + Self.collectKeep(w, rate: 0.2, seed: 2)
        }
        typealias E = TypoFixLogic.Edit
        let modes: [(String, Set<E>, Set<E>)] = [
            ("sub", [.sub], []), ("sub+swap", [.sub, .swap], []),
            ("sub+swap|rival del+ins", [.sub, .swap], [.del, .ins]),
            ("sub+swap+del|rival ins", [.sub, .swap, .del], [.ins]),
            ("all", [.sub, .swap, .del, .ins], []),
        ]
        for (name, edits, rivals) in modes {
            for minLen in [3, 4] {
                for minFreq in [110, 130, 150, 170, 190, 210] {
                    for margin in [0, 40, 60, 80, 100, 120] {
                        let p = TypoFixLogic.Params(minLen: minLen, minFreq: minFreq, margin: margin,
                                                    edits: edits, rivals: rivals)
                        var t = Self.score(vn, p); let k = Self.score(keep, p); t.add(k)
                        print(String(format: "TUNE %@ len=%d minFreq=%d margin=%d | P=%.1f%% R=%.1f%% gợi ý %d (giữ-nguyên: oan %d nhầm %d)",
                                     name, minLen, minFreq, margin, 100 * t.precision, 100 * t.recall,
                                     t.fix, k.falseFix, k.wrong))
                    }
                }
            }
        }
        _ = Self.score(vn + keep, TypoFixLogic.defaults, dump: true)
    }
}
