// SyllableLMTests.swift — mô hình trigram âm tiết tĩnh (vnlm.bin) + tác dụng lên gõ vuốt; cả phần
// bigram PMI mà thanh gợi ý + Thêm dấu dùng (thay vnbigram.bin từ 28/09/2026). Song sinh android
// SyllableLMTests.kt. Đo trên câu Tatoeba GIỮ LẠI (bigram-heldout.txt, không nằm trong dữ liệu
// dựng mô hình).
import XCTest

final class SyllableLMTests: XCTestCase {
    private let layout = SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)
    private var lm: SyllableLM { SyllableLM.shared! }

    private func id(_ w: String) -> Int {
        guard let i = SyllableLM.id(of: w) else { XCTFail("thiếu \(w)"); return -1 }
        return i
    }
    private func s(_ a: String?, _ b: String, _ c: String) -> Float {
        lm.score(prev2: a.map(id) ?? -1, prev1: id(b), id(c))
    }

    private func blob() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: SyllableLMTests.self).url(forResource: "vnlm", withExtension: "bin"))
        return try Data(contentsOf: url)
    }

    func testLoadsAndMatchesLexicon() throws {
        let m = try XCTUnwrap(SyllableLM.shared, "vnlm.bin phải khớp vnlexicon.bin (lexHash)")
        XCTAssertEqual(m.count, VNLexicon2Data.count)
        XCTAssertTrue((100_000...600_000).contains(m.biEntries), "bigram \(m.biEntries)")
        XCTAssertTrue((100_000...600_000).contains(m.triEntries), "trigram \(m.triEntries)")
        XCTAssertLessThanOrEqual(try blob().count, 2_700_000)
    }

    private func pmi(_ a: String, _ b: String) -> Float { lm.bigram(id(a)).pmi(id(b)) }

    /// Bigram PMI (s2 + uniAdj) — thay vnbigram.bin cho thanh gợi ý + Thêm dấu.
    func testBigramPmi() {
        XCTAssertGreaterThan(pmi("hôm", "nay"), 2)
        XCTAssertGreaterThan(pmi("không", "có"), pmi("không", "cô"))
        XCTAssertGreaterThan(pmi("hôm", "nay"), pmi("hôm", "ngay"))
        XCTAssertGreaterThan(pmi("ngay", "lập"), 2)
        XCTAssertGreaterThan(pmi("điện", "thoại"), 3)
        // bằng chứng âm (cặp hiếm) + lùi γ2 khi thiếu mục tường minh
        XCTAssertLessThan(pmi("hôm", "xịch"), 0)
        XCTAssertEqual(lm.bigram(id("hôm")).explicit(id("xịch")), 0)
        XCTAssertEqual(lm.bigram(id("hôm")).explicit(id("nay")), pmi("hôm", "nay"))
        // PMI = s2 + uniAdj (s2 = điểm bigram của decoder vuốt)
        XCTAssertEqual(pmi("hôm", "nay"), s(nil, "hôm", "nay") + lm.uniAdj(id("nay")), accuracy: 1e-6)
        XCTAssertEqual(lm.bigram(-1).size, 0)
        XCTAssertEqual(lm.bigram(VNLexicon2Data.count).size, 0)
        XCTAssertEqual(lm.bigram(-1).pmi(id("nay")), 0)
        var n = 0, hasNay = false
        lm.bigram(id("hôm")).forEach { c, v in
            n += 1
            if c == id("nay") { hasNay = true; XCTAssertEqual(v, pmi("hôm", "nay")) }
        }
        XCTAssertTrue(hasNay && n == lm.bigram(id("hôm")).size)
    }

    func testNormalizeOldStyleAndCase() {
        XCTAssertEqual(SyllableLM.normalize("Hoà"), "hòa")
        XCTAssertEqual(SyllableLM.normalize("thuỷ"), "thủy")
        XCTAssertEqual(SyllableLM.normalize("quý"), "quý")
        XCTAssertEqual(SyllableLM.id(of: "hòa"), SyllableLM.id(of: "HOÀ"))
        XCTAssertNil(SyllableLM.id(of: "hello"))
    }

    func testTypicalScores() {
        XCTAssertGreaterThan(s(nil, "hôm", "nay"), 2)
        XCTAssertGreaterThan(s(nil, "hôm", "nay"), s(nil, "hôm", "ngay"))
        XCTAssertGreaterThan(s(nil, "không", "có"), s(nil, "không", "cô"))
        XCTAssertLessThan(s(nil, "hôm", "xịch"), 0)   // bằng chứng âm
        XCTAssertGreaterThan(s("cuối", "cùng", "cũng"), s("cuối", "cùng", "chúng"))
        XCTAssertGreaterThan(s("một", "ngày", "nọ"), s(nil, "ngày", "nọ"))
        XCTAssertEqual(lm.score(prev2: -1, prev1: -1, id("nay")), 0)
        XCTAssertNil(lm.context(prev2: -1, prev1: VNLexicon2Data.count))
        XCTAssertEqual(lm.score(prev2: -1, prev1: id("hôm"), VNLexicon2Data.count), 0)
    }

    func testRejectsCorruptOrMismatched() throws {
        let d = try blob()
        let h = SyllableLM.fnv1a(VNLexicon2Data.blob)
        let n = VNLexicon2Data.count
        XCTAssertNotNil(SyllableLM.load(d, lexiconHash: h, lexiconCount: n))
        XCTAssertNil(SyllableLM.load(d, lexiconHash: h ^ 1, lexiconCount: n))
        XCTAssertNil(SyllableLM.load(d, lexiconHash: h, lexiconCount: n - 1))
        XCTAssertNil(SyllableLM.load(Data(d.dropLast()), lexiconHash: h, lexiconCount: n))
        var bad = d; bad[3] = UInt8(ascii: "X")
        XCTAssertNil(SyllableLM.load(bad, lexiconHash: h, lexiconCount: n))
        var v1 = d; v1[4] = 1   // bản cũ (không có uniAdj) ⇒ từ chối
        XCTAssertNil(SyllableLM.load(v1, lexiconHash: h, lexiconCount: n))
    }

    // MARK: gõ vuốt trong ngữ cảnh

    private func make() -> SwipeTyping {
        let s = SwipeTyping()
        s.setLayout(layout, prepare: false)
        return s
    }

    private func clean(_ w: String) -> SwipePath {
        var sim = SwipeSim(seed: 1)
        return sim.path(SwipeTyping.fold(w), layout, sigma: 0, jitter: 0)
    }

    func testContextPicksInTop1() {
        let s = make()
        let pairs: [(String, String)] = [("không", "có"), ("cho", "tôi"), ("hôm", "nay"), ("ngay", "lập"),
            ("đi", "ngay"), ("trong", "nhà"), ("bây", "giờ"), ("nửa", "đêm"), ("bữa", "nay"),
            ("môi", "trường"), ("ở", "trong"), ("làm", "cho"), ("một", "nửa")]
        for (prev, w) in pairs {
            XCTAssertEqual(s.resolve(clean(w), contextWords: [], prev: prev, case: .lower)?.word,
                           w, "\(prev) + vuốt \(SwipeTyping.fold(w))")
        }
        // cần 2 âm tiết trước
        let triples: [(String, String, String)] = [("cuối", "cùng", "cũng"), ("một", "ngày", "nọ"),
            ("bị", "mất", "ví"), ("làm", "việc", "cùng")]
        for (p2, p1, w) in triples {
            XCTAssertEqual(s.resolve(clean(w), contextWords: [], prev: p1, prev2: p2, case: .lower)?.word,
                           w, "\(p2) \(p1) + vuốt \(SwipeTyping.fold(w))")
        }
    }

    func testPersonalStillWins() {
        let s = make()
        XCTAssertEqual(s.resolve(clean("co"), contextWords: ["cô"], count: { $0 == "cô" ? 6 : 0 },
                                 prev: "không", prev2: "tôi", case: .lower)?.word, "cô")
    }

    func testNoContextKeepsOldScoring() {
        let d = SwipeDecoder.Params().lambdaFreq
        XCTAssertEqual(SwipeTyping.Context(next: [], lm: SyllableLM.shared).lambdaFreq, d)
        XCTAssertEqual(SwipeTyping.Context(next: [], prev: "xyzq", prev2: "tôi", lm: SyllableLM.shared).lambdaFreq, d)
        XCTAssertEqual(SwipeTyping.Context(next: [], prev: "tôi", lm: SyllableLM.shared).lambdaFreq,
                       SwipeTyping.lmLambdaFreq)
    }

    // MARK: đo độ chính xác trên câu giữ lại

    private func heldout() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: SyllableLMTests.self)
            .url(forResource: "bigram-heldout", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: " ").map(String.init) }
    }

    private func measure(_ chains: [[String]], useLM: Bool, english: Bool = false) -> (n: Int, top1: Int, top3: Int) {
        let s = make()
        var sim = SwipeSim(seed: 2027)
        var n = 0, t1 = 0, t3 = 0
        for chain in chains {
            for i in 1..<chain.count {
                let w = chain[i]
                let p = sim.path(SwipeTyping.fold(w), layout)
                let prev2 = i >= 2 ? chain[i - 2] : nil
                let prior: SwipeEnglishPrior? = english ? SwipeLangContext.prior(
                    prev1: SwipeLangContext.classify(chain[i - 1]),
                    prev2: SwipeLangContext.classify(prev2)) : nil
                guard let r = s.resolve(p, contextWords: [], prev: chain[i - 1], prev2: prev2,
                                        lm: useLM ? SyllableLM.shared : nil, english: prior,
                                        case: .lower) else { continue }
                n += 1
                if r.word == w { t1 += 1 }
                if r.word == w || r.alternatives.prefix(2).contains(w) { t3 += 1 }
            }
        }
        return (n, t1, t3)
    }

    private func f(_ a: (n: Int, top1: Int, top3: Int)) -> String {
        String(format: "top1 %.3f top3 %.3f (n=%d)", Double(a.top1) / Double(a.n), Double(a.top3) / Double(a.n), a.n)
    }

    func testHeldoutAccuracy() throws {
        try SlowTests.require()
        // 1/3 số chuỗi: Debug simulator chậm hơn JVM (bản Kotlin đo đủ)
        let chains = try heldout().enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        let none = measure(chains, useLM: false)   // không LM tĩnh (vnbigram.bin cũ đã bỏ)
        let t0 = CFAbsoluteTimeGetCurrent()
        let tri = measure(chains, useLM: true)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / Double(tri.n)
        print(String(format: "LM heldout iOS không LM: %@ | trigram: %@ | %.2f ms/vuốt (Debug)", f(none), f(tri), ms))
        // cùng ngưỡng với Kotlin (đo 27/09/2026, decoder tầng 2: 0.861/0.951 → 0.894/0.962 trên toàn tập;
        // 28/09/2026 không LM 0.702/0.869)
        XCTAssertGreaterThanOrEqual(Double(tri.top1) / Double(tri.n), 0.877, f(tri))
        XCTAssertGreaterThanOrEqual(Double(tri.top3) / Double(tri.n), 0.950, f(tri))
        XCTAssertGreaterThanOrEqual(Double(tri.top1 - none.top1) / Double(tri.n), 0.17)
    }

    func testHeldoutAccuracyWithEnglish() throws {
        try SlowTests.require()
        let chains = try heldout().enumerated().filter { $0.offset % 9 == 0 }.map(\.element)
        let vi = measure(chains, useLM: true)
        let both = measure(chains, useLM: true, english: true)
        print("LM+EN heldout iOS: chỉ Việt \(f(vi)) | bật tiếng Anh \(f(both))")
        XCTAssertGreaterThanOrEqual(Double(both.top1) / Double(both.n), 0.877)
        XCTAssertLessThanOrEqual(Double(vi.top1 - both.top1) / Double(vi.n), 0.01)
    }
}
