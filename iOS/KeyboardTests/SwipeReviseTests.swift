// SwipeReviseTests.swift — sửa lại từ vuốt trước theo ngữ cảnh hai phía (SwipeRevise). Song
// sinh android SwipeReviseTests.kt (+ ca luồng SwipeTypingTests.kt). Đo trên câu giữ lại
// bigram-heldout.txt, vuốt TUẦN TỰ qua SwipeTyping.finish + EngineBridge như bàn phím thật.
import XCTest

final class SwipeReviseTests: XCTestCase {
    private let layout = SwipeLayout.qwerty(keyWidth: 36, rowHeight: 54)

    private func w(_ word: String, _ s: Float) -> SwipeWord { SwipeWord(word: word, score: s) }

    func testRightContextFlipsCloseCall() {
        let scored = [w("có", 1.0), w("cô", 0.95), w("co", 0.5)]
        XCTAssertEqual(SwipeRevise.revise(scored, current: "có", prev: "tôi", next: "giáo"), "cô")
        XCTAssertNil(SwipeRevise.revise(scored, current: "có", prev: "tôi", next: "thể"))
        XCTAssertEqual(SwipeRevise.revise([w("cô", 1.0), w("có", 0.95)], current: "cô", prev: "tôi", next: "thể"), "có")
    }

    func testClearLeadIsKept() {
        XCTAssertNil(SwipeRevise.revise([w("có", 4.0), w("cô", 0.5)], current: "có", prev: "tôi", next: "giáo"))
    }

    func testMarginAndGuards() {
        let scored = [w("có", 1.0), w("cô", 0.95)]
        XCTAssertNil(SwipeRevise.revise(scored, current: "có", prev: "tôi", next: "giáo", margin: 50))
        XCTAssertNil(SwipeRevise.revise(scored, current: "có", prev: "tôi", next: "giáo", lm: nil))
        XCTAssertNil(SwipeRevise.revise(scored, current: "có", prev: "tôi", next: "check"))
        XCTAssertNil(SwipeRevise.revise(scored, current: "cỏ", prev: "tôi", next: "giáo"))
        XCTAssertNil(SwipeRevise.revise(Array(scored.prefix(1)), current: "có", prev: "tôi", next: "giáo"))
        XCTAssertEqual(SwipeRevise.revise(scored, current: "có", prev: nil, next: "giáo"), "cô")
    }

    func testRightScoreClamped() throws {
        let lm = try XCTUnwrap(SyllableLM.shared)
        let id = { (s: String) in SyllableBigram.id(of: s) ?? -1 }
        let r = SwipeRevise.rightScore(lm, prev: -1, cand: id("hôm"), next: id("nay"))
        XCTAssertTrue(r > 0 && r <= SwipeRevise.rightCap)
        XCTAssertGreaterThanOrEqual(SwipeRevise.rightScore(lm, prev: -1, cand: id("hôm"), next: id("xịch")),
                                    SwipeRevise.rightFloor)
        XCTAssertEqual(SwipeRevise.rightScore(lm, prev: -1, cand: -1, next: id("nay")), 0)
    }

    func testScoredSkipsEnglishAndIsSorted() {
        let en = [SwipeCandidate(folded: "check", score: 1, lang: .en), SwipeCandidate(folded: "chec", score: 0)]
        XCTAssertTrue(SwipeRevise.scored(en, context: nil, lambdaFreq: 2.5).isEmpty)
        let vi = [SwipeCandidate(folded: "co", score: 2), SwipeCandidate(folded: "cho", score: 1.5)]
        let sc = SwipeRevise.scored(vi, context: nil, lambdaFreq: 2.5)
        XCTAssertEqual(sc.first?.word, SwipeDecoder.expand("co", limit: 1).first?.word)
        XCTAssertTrue((2...SwipeRevise.maxCandidates).contains(sc.count))
        XCTAssertTrue(zip(sc, sc.dropFirst()).allSatisfy { $0.score >= $1.score })
        let re = SwipeRevise.rerank(vi, old: nil, oldLambda: 2.5, new: { $0 == "chó" ? 5 : 0 }, newLambda: 2.5)
        XCTAssertEqual(re.first?.folded, "cho")
    }

    // MARK: luồng SwipeTyping + EngineBridge (như KeyboardViewController.swipeEnded)

    private final class Flow {
        let s = SwipeTyping()
        let b = EngineBridge(settings: KeyboardSettings())
        let p = MockProxy()
        var rec: SwipeTyping.Revisable?
        var committed: [String] = []
        var last: SwipeTyping.Outcome?

        init(_ layout: SwipeLayout) { s.setLayout(layout, prepare: false) }

        @discardableResult
        func swipe(_ word: String, _ layout: SwipeLayout, sim: inout SwipeSim, sigma: Double = 0,
                   case sc: SwipeCase = .lower, revise: Bool = true) -> SwipeTyping.Outcome? {
            let f = SwipeTyping.fold(word)
            b.letter(sc == .lower ? f.first! : Character(f.prefix(1).uppercased()), proxy: p)
            s.begin(bridge: b, proxy: p)
            let composing = b.isComposing
            let prev = composing ? b.predictedCommit : committed.last
            let prev2 = composing ? committed.last : committed.dropLast().last
            let previous = revise ? rec.flatMap { r in
                b.isSwipeWordOpen && b.isFreshSwipeWord && !b.openWordAccepted && !b.isLiteralSwipeWordOpen
                    && b.composedWord == r.word ? r : nil
            } : nil
            rec = nil
            let path = sigma == 0 ? sim.path(f, layout, sigma: 0, jitter: 0) : sim.path(f, layout, sigma: sigma)
            let out = s.finish(path, case: sc, contextWords: [], prev: prev, prev2: prev2,
                               previous: previous, bridge: b, proxy: p)
            if let c = out?.committed { committed.append(c.word) }
            if let out, !out.scored.isEmpty, b.isSwipeWordOpen {
                rec = SwipeTyping.Revisable(word: out.word, scored: out.scored, sc: sc)
            }
            last = out
            return out
        }
    }

    func testNextSwipeRevisesPrevious() {
        let f = Flow(layout)
        var sim = SwipeSim(seed: 7)
        f.swipe("co", layout, sim: &sim)
        XCTAssertEqual(f.p.text, "có")
        let out = f.swipe("gang", layout, sim: &sim)
        XCTAssertEqual(f.p.text, "cố gắng")
        XCTAssertEqual(out?.revised, SwipeTyping.Revision(old: "có", new: "cố"))
        XCTAssertEqual(out?.committed?.word, "cố", "học từ mới, không học từ cũ")
        XCTAssertFalse(out?.committed?.accepted ?? true)
        // chip "↩︎ có": trả lại đúng từ cũ, từ vuốt mới vẫn mở
        XCTAssertTrue(f.b.restoreRevisedWord(old: "có", new: "cố", proxy: f.p))
        XCTAssertEqual(f.p.text, "có gắng")
        XCTAssertTrue(f.b.isSwipeWordOpen)
        XCTAssertFalse(f.b.restoreRevisedWord(old: "có", new: "cố", proxy: f.p), "đuôi đã khác ⇒ không đụng")
        f.b.boundary(" ", proxy: f.p)
        XCTAssertEqual(f.p.text, "có gắng ")
    }

    func testCaseKeptAndOnlyOnce() {
        let f = Flow(layout)
        var sim = SwipeSim(seed: 7)
        f.swipe("co", layout, sim: &sim, case: .capitalized)
        f.swipe("gang", layout, sim: &sim)
        XCTAssertEqual(f.p.text, "Cố gắng")
        f.swipe("len", layout, sim: &sim)
        XCTAssertTrue(f.p.text.hasPrefix("Cố gắng "), f.p.text)
    }

    func testNoRevisionAfterToneEditOrChoice() {
        // phím dấu Telex sửa từ vuốt ⇒ không còn nguyên
        do {
            let f = Flow(layout)
            var sim = SwipeSim(seed: 7)
            f.swipe("co", layout, sim: &sim)
            f.b.letter("f", proxy: f.p)                     // có → cò
            XCTAssertEqual(f.p.text, "cò")
            f.swipe("gang", layout, sim: &sim)
            XCTAssertTrue(f.p.text.hasPrefix("cò "), f.p.text)
        }
        // chọn phương án ⇒ user đã quyết (controller bỏ rec; bridge đánh dấu accepted)
        do {
            let f = Flow(layout)
            var sim = SwipeSim(seed: 7)
            f.swipe("co", layout, sim: &sim)
            let alt = f.last!.alternatives.first { $0 != "cố" }!
            XCTAssertTrue(f.b.replaceSwipeWord(with: alt, proxy: f.p))
            f.swipe("gang", layout, sim: &sim)
            XCTAssertTrue(f.p.text.hasPrefix(alt + " "), f.p.text)
        }
    }

    func testFailSafeWhenContextDiffers() {
        let f = Flow(layout)
        var sim = SwipeSim(seed: 7)
        f.swipe("co", layout, sim: &sim)
        f.p.fakeContext = .some(nil)                        // host không cho đọc context
        f.swipe("gang", layout, sim: &sim)
        XCTAssertFalse(f.p.text.contains("cố"), f.p.text)
        XCTAssertNil(f.last?.revised)
    }

    // MARK: đo trên câu giữ lại

    private func heldout() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: SwipeReviseTests.self)
            .url(forResource: "bigram-heldout", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: " ").map(String.init) }
    }

    private func measure(_ chains: [[String]], revise: Bool) -> (n: Int, ok: Int, revised: Int) {
        var sim = SwipeSim(seed: 2027)
        var n = 0, ok = 0, revised = 0
        for chain in chains {
            let f = Flow(layout)
            for w in chain {
                if f.swipe(w, layout, sim: &sim, sigma: 0.25, revise: revise)?.revised != nil { revised += 1 }
            }
            let got = f.p.text.split(separator: " ").map(String.init)
            n += chain.count
            ok += zip(got, chain).filter { $0 == $1 }.count
        }
        return (n, ok, revised)
    }

    /// Cùng tập đo với Kotlin (offset % 3 == 0). Android JVM 27/09/2026: 0.809 → 0.855.
    func testHeldoutRevisionGain() throws {
        try SlowTests.require()
        let test = try heldout().enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        let t0 = CFAbsoluteTimeGetCurrent()
        let base = measure(test, revise: false)
        let t1 = CFAbsoluteTimeGetCurrent()
        let rev = measure(test, revise: true)
        let t2 = CFAbsoluteTimeGetCurrent()
        let a = Double(base.ok) / Double(base.n), b = Double(rev.ok) / Double(rev.n)
        print(String(format: "REVISE heldout iOS (tuần tự, σ0.25): trước %.4f | sau %.4f (+%.2f điểm, sửa %d, n=%d) | %.2f → %.2f ms/vuốt (Debug)",
                     a, b, (b - a) * 100, rev.revised, rev.n,
                     (t1 - t0) * 1000 / Double(base.n), (t2 - t1) * 1000 / Double(rev.n)))
        XCTAssertGreaterThanOrEqual(b - a, 0.01)
    }
}
