// SyllableBigramTests.swift — bảng bigram âm tiết tĩnh + tác dụng lên gõ vuốt. Song sinh
// android SyllableBigramTests.kt. Đo độ chính xác trên câu Tatoeba GIỮ LẠI (fixture
// bigram-heldout.txt, không nằm trong dữ liệu dựng bảng): mỗi âm tiết có âm tiết trước →
// đường vuốt giả σ0.25 → decode + chọn dấu.
import XCTest

final class SyllableBigramTests: XCTestCase {
    private let layout = SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)
    private var big: SyllableBigram { SyllableBigram.shared! }

    private func id(_ w: String) -> Int {
        guard let i = SyllableBigram.id(of: w) else { XCTFail("thiếu \(w)"); return -1 }
        return i
    }
    private func pmi(_ a: String, _ b: String) -> Float { big.score(id(a), id(b)) }

    private func blob(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: SyllableBigramTests.self).url(forResource: name, withExtension: "bin"))
        return try Data(contentsOf: url)
    }

    func testLoadsAndMatchesLexicon() throws {
        let b = try XCTUnwrap(SyllableBigram.shared, "vnbigram.bin phải khớp vnlexicon.bin (lexHash)")
        XCTAssertEqual(b.count, VNLexicon2Data.count)
        XCTAssertTrue((100_000...500_000).contains(b.entries), "entries \(b.entries)")
        XCTAssertLessThanOrEqual(try blob("vnbigram").count, 1_600_000)
    }

    func testTypicalPairs() {
        XCTAssertGreaterThan(pmi("hôm", "nay"), 2)
        XCTAssertGreaterThan(pmi("không", "có"), pmi("không", "cô"))
        XCTAssertGreaterThan(pmi("hôm", "nay"), pmi("hôm", "ngay"))
        XCTAssertGreaterThan(pmi("ngay", "lập"), 2)
        XCTAssertEqual(big.score(id("hôm"), id("xịch")), 0)
        XCTAssertEqual(big.score(-1, id("nay")), 0)
        XCTAssertEqual(big.row(VNLexicon2Data.count).size, 0)
    }

    func testNormalizeOldStyleAndCase() {
        XCTAssertEqual(SyllableBigram.normalize("Hoà"), "hòa")
        XCTAssertEqual(SyllableBigram.normalize("thuỷ"), "thủy")
        XCTAssertEqual(SyllableBigram.normalize("quý"), "quý")
        XCTAssertEqual(SyllableBigram.id(of: "hòa"), SyllableBigram.id(of: "HOÀ"))
        XCTAssertNil(SyllableBigram.id(of: "hello"))
    }

    func testRejectsCorruptOrMismatched() throws {
        let d = try blob("vnbigram")
        let h = SyllableBigram.fnv1a(VNLexicon2Data.blob)
        let n = VNLexicon2Data.count
        XCTAssertNotNil(SyllableBigram.load(d, lexiconHash: h, lexiconCount: n))
        XCTAssertNil(SyllableBigram.load(d, lexiconHash: h ^ 1, lexiconCount: n))
        XCTAssertNil(SyllableBigram.load(Data(d.dropLast()), lexiconHash: h, lexiconCount: n))
        var bad = d; bad[0] = UInt8(ascii: "X")
        XCTAssertNil(SyllableBigram.load(bad, lexiconHash: h, lexiconCount: n))
    }

    // MARK: gõ vuốt trong ngữ cảnh

    private func make() -> SwipeTyping {
        let s = SwipeTyping()
        s.setLayout(layout, prepare: false)
        return s
    }

    private func path(_ word: String, _ sim: inout SwipeSim, clean: Bool) -> SwipePath {
        sim.path(SwipeTyping.fold(word), layout, sigma: clean ? 0 : 0.25, jitter: clean ? 0 : 0.04)
    }

    func testContextPicksPairInTop1() {
        let s = make()
        let pairs: [(String, String)] = [("không", "có"), ("cho", "tôi"), ("hôm", "nay"), ("ngay", "lập"),
            ("đi", "ngay"), ("trong", "nhà"), ("bây", "giờ"), ("nửa", "đêm"), ("bữa", "nay"),
            ("môi", "trường"), ("ở", "trong"), ("làm", "cho"), ("một", "nửa")]
        for (prev, w) in pairs {
            var sim = SwipeSim(seed: 1)
            XCTAssertEqual(s.resolve(path(w, &sim, clean: true), contextWords: [], prev: prev, case: .lower)?.word,
                           w, "\(prev) + vuốt \(SwipeTyping.fold(w))")
        }
    }

    func testPersonalStillWins() {
        // user hay gõ "không cô" ⇒ nextWords thắng bigram tĩnh
        let s = make()
        var sim = SwipeSim(seed: 1)
        XCTAssertEqual(s.resolve(path("co", &sim, clean: true), contextWords: ["cô"],
                                 count: { $0 == "cô" ? 6 : 0 }, prev: "không", case: .lower)?.word, "cô")
    }

    // MARK: đo độ chính xác trên câu giữ lại

    private func heldout() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: SyllableBigramTests.self)
            .url(forResource: "bigram-heldout", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: " ").map(String.init) }
    }

    /// `useBigram` = false ⇒ như trước giai đoạn 2 (không dữ liệu cá nhân, không bigram).
    private func measure(_ chains: [[String]], useBigram: Bool,
                         english: Bool = false) -> (n: Int, top1: Int, top3: Int) {
        let s = make()
        var sim = SwipeSim(seed: 2027)
        var n = 0, t1 = 0, t3 = 0
        for chain in chains {
            for i in 1..<chain.count {
                let w = chain[i]
                let p = sim.path(SwipeTyping.fold(w), layout)
                // english ⇒ như bàn phím khi bật "Vuốt từ tiếng Anh" (giai đoạn 3)
                let prior: SwipeEnglishPrior? = english ? SwipeLangContext.prior(
                    prev1: SwipeLangContext.classify(chain[i - 1]),
                    prev2: SwipeLangContext.classify(i >= 2 ? chain[i - 2] : nil)) : nil
                guard let r = s.resolve(p, contextWords: [], prev: useBigram ? chain[i - 1] : nil,
                                        english: prior, case: .lower) else { continue }
                n += 1
                if r.word == w { t1 += 1 }
                if r.word == w || r.alternatives.prefix(2).contains(w) { t3 += 1 }
            }
        }
        return (n, t1, t3)
    }

    /// Giai đoạn 2 + 3 cùng bật: ứng viên tiếng Anh không làm tụt bigram quá 1 điểm.
    func testHeldoutAccuracyWithEnglish() throws {
        // 1/9 số chuỗi: decode có tiếng Anh ở Debug chậm (bản Kotlin đo đủ)
        let chains = try heldout().enumerated().filter { $0.offset % 9 == 0 }.map(\.element)
        let vi = measure(chains, useBigram: true)
        let both = measure(chains, useBigram: true, english: true)
        print(String(format: "BIGRAM+EN heldout iOS: chỉ Việt top1 %.3f | bật tiếng Anh top1 %.3f (n=%d)",
                     Double(vi.top1) / Double(vi.n), Double(both.top1) / Double(both.n), both.n))
        XCTAssertGreaterThanOrEqual(Double(both.top1) / Double(both.n), 0.84)
        XCTAssertLessThanOrEqual(Double(vi.top1 - both.top1) / Double(vi.n), 0.01)
    }

    func testHeldoutAccuracy() throws {
        // 1/3 số chuỗi: Debug simulator ~3× chậm hơn JVM (bản Kotlin đo đủ)
        let chains = try heldout().enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        let before = measure(chains, useBigram: false)
        let after = measure(chains, useBigram: true)
        func f(_ a: (n: Int, top1: Int, top3: Int)) -> String {
            String(format: "top1 %.3f top3 %.3f (n=%d)", Double(a.top1) / Double(a.n), Double(a.top3) / Double(a.n), a.n)
        }
        print("BIGRAM heldout iOS trước: \(f(before)) | sau: \(f(after))")
        XCTAssertGreaterThan(before.n, 3000)
        let t0 = CFAbsoluteTimeGetCurrent()
        _ = measure(Array(chains.prefix(100)), useBigram: true)
        print(String(format: "BIGRAM resolve iOS (Debug): %.2f ms/vuốt", (CFAbsoluteTimeGetCurrent() - t0) * 1000
            / Double(chains.prefix(100).reduce(0) { $0 + $1.count - 1 })))
        // cùng ngưỡng với Kotlin (đo 27/09/2026: 0.704/0.865 → 0.856/0.948)
        XCTAssertGreaterThanOrEqual(Double(after.top1) / Double(after.n), 0.84, f(after))
        XCTAssertGreaterThanOrEqual(Double(after.top3) / Double(after.n), 0.935, f(after))
        XCTAssertGreaterThanOrEqual(Double(after.top1 - before.top1) / Double(after.n), 0.13)
    }
}
