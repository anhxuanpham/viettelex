// FUTO Swipe (thử nghiệm): parity suy luận Swift với forward tham chiếu python (fixture chung
// Fixtures/futo-swipe-fixture.txt — cùng bộ với android FutoSwipeTests.kt), công tắc tắt = không
// tải model, CTC/tìm kiếm; bộ chậm: độ chính xác SHARK2/FUTO/ensemble + độ trễ.
import XCTest

/// Đường vuốt giả có NHỊP kiểu người (minimum-jerk mỗi đoạn: chậm dần tới phím; thời lượng
/// đoạn 120 ms + 300 ms·√(khoảng cách/bề rộng bàn phím)). Hình học như SwipeSim. Song sinh
/// Kotlin FutoSim (FutoSwipeTests.kt).
struct FutoSim {
    private var rnd: SwipeSim
    let sigma: Double, jitter: Double
    init(seed: UInt64, sigma: Double = 0.25, jitter: Double = 0.04) {
        rnd = SwipeSim(seed: seed); self.sigma = sigma; self.jitter = jitter
    }

    private static func catmull(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    mutating func path(_ word: String, _ layout: SwipeLayout) -> SwipePath {
        let w = Double(layout.keyWidth)
        let keys = Array(SwipeSim.collapse(word))
        var cx = [Double](repeating: 0, count: keys.count), cy = cx
        for (i, ch) in keys.enumerated() {
            let c = layout.center(of: ch)!
            cx[i] = Double(c.x) + rnd.gauss() * sigma * w
            cy[i] = Double(c.y) + rnd.gauss() * sigma * w
        }
        var p = SwipePath(minDistance: layout.keyWidth / 5)
        let m = keys.count
        if m == 1 {
            for i in 0..<12 {
                p.add(x: Float(cx[0] + rnd.gauss() * jitter * w), y: Float(cy[0] + rnd.gauss() * jitter * w),
                      t: Double(i) / 60)
            }
            return p
        }
        var t = 0.0
        let board = 10 * w
        for s in 0..<(m - 1) {
            let i0 = max(s - 1, 0), i1 = s, i2 = s + 1, i3 = min(s + 2, m - 1)
            let d = hypot(cx[i2] - cx[i1], cy[i2] - cy[i1])
            let dur = 0.120 + 0.300 * (d / board).squareRoot()
            let n = max(2, Int(ceil(dur * 60)))
            for j in 0..<n {
                let tau = Double(j) / Double(n)
                let u = tau * tau * tau * (10 - 15 * tau + 6 * tau * tau)
                let x = Self.catmull(cx[i0], cx[i1], cx[i2], cx[i3], u) + rnd.gauss() * jitter * w
                let y = Self.catmull(cy[i0], cy[i1], cy[i2], cy[i3], u) + rnd.gauss() * jitter * w
                p.add(x: Float(x), y: Float(y), t: t); t += 1.0 / 60
            }
        }
        p.add(x: Float(cx[m - 1]), y: Float(cy[m - 1]), t: t, force: true)
        return p
    }
}

final class FutoSwipeTests: XCTestCase {
    struct Case { let name: String; let keys: [Float]; let raw: [[Double]]?; let feats: [Float]; let logem: [Float]; let greedy: String }

    static let layout = SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)
    private var layout: SwipeLayout { Self.layout }

    static func fixture() throws -> [Case] {
        let url = try XCTUnwrap(Bundle(for: FutoSwipeTests.self).url(forResource: "futo-swipe-fixture", withExtension: "txt"))
        var out: [Case] = []
        var name = "", keys: [Float] = [], raw: [[Double]]? = nil, feats: [Float] = [], logem: [Float] = []
        func floats(_ s: Substring) -> [Float] { s.split(separator: ",").map { Float(String($0))! } }
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            if line.hasPrefix("#") || line.isEmpty { continue }
            let sp = line.firstIndex(of: " ")!
            let tag = line[..<sp], v = line[line.index(after: sp)...]
            switch tag {
            case "case": name = String(v); raw = nil
            case "keys": keys = floats(v)
            case "raw": raw = v.split(separator: ";").map { $0.split(separator: ",").map { Double(String($0))! } }
            case "feats": feats = floats(v)
            case "logem": logem = floats(v)
            case "greedy": out.append(Case(name: name, keys: keys, raw: raw, feats: feats, logem: logem, greedy: String(v)))
            default: break
            }
        }
        return out
    }

    static func greedy(_ em: [Float], _ nk: Int) -> String {
        var s = "", prev = -1
        for t in 0..<FutoSwipeModel.T2 {
            var best = 0
            for c in 1...nk where em[t * (nk + 1) + c] > em[t * (nk + 1) + best] { best = c }
            if best != prev && best != nk { s.append(Character(UnicodeScalar(UInt8(97 + best)))) }
            prev = best
        }
        return s
    }

    static func loaded() -> FutoSwipe {
        let f = FutoSwipe(source: FutoSwipe.bundledWeights)
        f.setLayout(layout)
        XCTAssertTrue(f.load())
        return f
    }

    func testHalfToFloat() {
        XCTAssertEqual(FutoSwipeModel.halfToFloat(0x3c00), 1)
        XCTAssertEqual(FutoSwipeModel.halfToFloat(0xc000), -2)
        XCTAssertEqual(FutoSwipeModel.halfToFloat(0x7bff), 65504)
        XCTAssertEqual(FutoSwipeModel.halfToFloat(0x0001), 5.9604645e-8)
        XCTAssertTrue(FutoSwipeModel.halfToFloat(0x7c00).isInfinite)
    }

    func testRejectsCorruptWeights() throws {
        let d = try XCTUnwrap(FutoSwipe.bundledWeights())
        XCTAssertNotNil(FutoSwipeModel.load(d))
        XCTAssertNil(FutoSwipeModel.load(d.prefix(d.count - 2)))
        var bad = Data(d); bad[0] = UInt8(ascii: "X")
        XCTAssertNil(FutoSwipeModel.load(bad))
        var ver = Data(d); ver[4] = 2
        XCTAssertNil(FutoSwipeModel.load(ver))
    }

    /// Suy luận Swift khớp forward python (weights fp16) — cùng ngưỡng với Kotlin.
    func testFixtureParity() throws {
        let m = try XCTUnwrap(FutoSwipeModel.load(try XCTUnwrap(FutoSwipe.bundledWeights())))
        let cases = try Self.fixture()
        XCTAssertEqual(cases.count, 4)
        for c in cases {
            let nk = c.keys.count / 2
            var out = [Float](repeating: 0, count: FutoSwipeModel.T2 * (nk + 1))
            m.run(c.feats, c.keys, nk, &out)
            var worst: Float = 0, at = 0, maxd: Float = 0
            for i in out.indices {
                let d = abs(out[i] - c.logem[i])
                maxd = max(maxd, d)
                let r = d / (1e-2 + 1e-3 * abs(c.logem[i]))
                if r > worst { worst = r; at = i }
            }
            print("FUTO parity \(c.name): max Δ=\(maxd)")
            XCTAssertLessThanOrEqual(worst, 1, "\(c.name): Δ=\(abs(out[at] - c.logem[at])) tại \(c.logem[at])")
            XCTAssertEqual(Self.greedy(out, nk), c.greedy, c.name)
        }
    }

    /// Tiền xử lý (khung phím + resample theo thời gian) khớp python.
    func testPreprocessingParity() throws {
        let fs = FutoSwipe(source: { nil })
        fs.setLayout(layout)
        for c in try Self.fixture() {
            guard let raw = c.raw else { continue }
            let nkeys = fs.normalizedKeys()
            for i in nkeys.indices { XCTAssertEqual(nkeys[i], c.keys[i], accuracy: 1e-5, "\(c.name) key \(i)") }
            let f = fs.features(xs: raw.map { Float($0[0]) }, ys: raw.map { Float($0[1]) },
                                ts: raw.map { $0[2] / 1000 }, count: raw.count)
            for i in 0..<128 { XCTAssertEqual(f[i], c.feats[i], accuracy: 2e-4, "\(c.name) feat \(i)") }
        }
    }

    /// Công tắc tắt ⇒ không ai tạo FutoSwipe; tạo rồi mà chưa load ⇒ không đọc asset, decode = nil.
    func testNoLoadUntilAsked() {
        var reads = 0
        let fs = FutoSwipe(source: { reads += 1; return FutoSwipe.bundledWeights() })
        fs.setLayout(layout)
        var sim = SwipeSim(seed: 1)
        let p = sim.path("khong", layout)
        XCTAssertNil(fs.decode(p, topK: 5, context: nil, english: nil, englishContext: nil, shark: nil))
        XCTAssertEqual(reads, 0)
        XCTAssertFalse(fs.isLoaded)
        XCTAssertTrue(fs.load()); XCTAssertEqual(reads, 1)
        XCTAssertTrue(fs.load()); XCTAssertEqual(reads, 1)
        XCTAssertNotNil(fs.decode(p, topK: 5, context: nil, english: nil, englishContext: nil, shark: nil))
        fs.release()
        XCTAssertFalse(fs.isLoaded)
        XCTAssertNil(fs.decode(p, topK: 5, context: nil, english: nil, englishContext: nil, shark: nil))
    }

    /// Mặc định TẮT (KeyboardSettings) và SwipeTyping không giữ FUTO khi chưa bật.
    func testSwitchDefaultsOff() {
        XCTAssertFalse(KeyboardSettings().swipeFuto)
        let s = SwipeTyping()
        s.setLayout(layout, prepare: true)
        XCTAssertFalse(s.futoActive)
        s.setFuto(enabled: true)
        XCTAssertTrue(s.futoActive)
        s.setFuto(enabled: false)
        XCTAssertFalse(s.futoActive)
    }

    func testMissingAssetFailsSoft() {
        let fs = FutoSwipe(source: { nil })
        fs.setLayout(layout)
        XCTAssertFalse(fs.load())
        var sim = SwipeSim(seed: 1)
        XCTAssertNil(fs.decode(sim.path("anh", layout), topK: 5, context: nil, english: nil, englishContext: nil, shark: nil))
    }

    /// CTC dùng lại tiền tố + cắt nhánh ra đúng top-1 âm học như chấm riêng từng từ.
    func testSearchMatchesBruteForce() {
        let fs = Self.loaded()
        var sim = FutoSim(seed: 7)
        for w in ["khong", "nguoi", "duoc", "thuong", "viet", "anh"] {
            let p = sim.path(w, layout)
            XCTAssertTrue(fs.computeEmissions(xs: p.xs, ys: p.ys, ts: p.ts, count: p.count))
            let forms = SwipeLexicon.forms
            var best = -Float.infinity, bestF = ""
            for f in 0..<forms.count {
                let s = fs.score(forms.keys, Int(forms.keyStart[f]), Int(forms.keyStart[f + 1]))
                if s > best { best = s; bestF = forms.folded[f] }
            }
            fs.search(4, 1, 0, nil, 0)
            let top = fs.top()
            XCTAssertEqual(top[0].1, best, accuracy: 1e-4, w)
            XCTAssertEqual(forms.folded[top[0].0], bestF, w)
        }
    }

    /// Đường có nhịp thật (chậm ở phím): FUTO một mình nhận đúng các âm tiết thường.
    func testFutoAloneDecodesRealisticPaths() {
        let fs = Self.loaded()
        fs.params.mode = .futo
        var sim = FutoSim(seed: 3, sigma: 0, jitter: 0)
        for w in ["khong", "nguoi", "duoc", "thuong", "nhung", "viet", "toi", "chung"] {
            let r = fs.decode(sim.path(w, layout), topK: 5, context: nil, english: nil, englishContext: nil, shark: nil)!
            XCTAssertEqual(r.first?.folded, w)
        }
    }

    // MARK: bộ chậm

    /// Độ trễ encoder + ensemble (Debug simulator — số thật trên máy Release nhanh hơn).
    func testLatency() throws {
        try SlowTests.require()
        let fs = Self.loaded()
        let shark = SwipeDecoder(); shark.setLayout(layout); shark.prepare()
        var sim = FutoSim(seed: 5)
        let paths = ["khong", "nguoi", "duoc", "thuong", "viet", "anh", "chung", "nghieng"].map { sim.path($0, layout) }
        for p in paths { _ = fs.decode(p, topK: 5, context: nil, english: nil, englishContext: nil, shark: shark) }
        var model = 0.0, total = 0.0, n = 0
        for _ in 0..<5 {
            for p in paths {
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = fs.decode(p, topK: 5, context: nil, english: nil, englishContext: nil, shark: shark)
                total += (CFAbsoluteTimeGetCurrent() - t0) * 1000
                model += fs.lastModelMs; n += 1
            }
        }
        print(String(format: "FUTO iOS: encoder %.2f ms | ensemble tổng %.2f ms", model / Double(n), total / Double(n)))
    }

    /// Câu giữ lại (như SyllableLMTests): SHARK2 vs FUTO vs ensemble, đường có nhịp.
    func testHeldoutSentences() throws {
        try SlowTests.require()
        let url = try XCTUnwrap(Bundle(for: FutoSwipeTests.self).url(forResource: "bigram-heldout", withExtension: "txt"))
        let chains = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }.map { $0.split(separator: " ").map(String.init) }
            .enumerated().filter { $0.offset % 12 == 6 }.map(\.element)
        let s = SwipeTyping()
        s.setLayout(layout, prepare: false)
        let fs = Self.loaded()
        let shark = SwipeDecoder(); shark.setLayout(layout)
        var sim = FutoSim(seed: 2027)
        var n = 0, t1 = [0, 0, 0]
        for chain in chains {
            for i in 1..<chain.count {
                let w = chain[i]
                let p = sim.path(SwipeTyping.fold(w), layout)
                let prev2 = i >= 2 ? chain[i - 2] : nil
                let ctx = SwipeTyping.Context(next: [], prev: chain[i - 1],
                                              prev2: prev2, lm: SyllableLM.shared)
                n += 1
                for (k, mode) in [FutoSwipe.Mode?.none, .futo, .ensemble].enumerated() {
                    let cands: [SwipeCandidate]
                    if let mode {
                        fs.params.mode = mode
                        cands = fs.decode(p, topK: 5, context: ctx.folded, english: nil, englishContext: nil,
                                          shark: shark, reuseEmissions: k > 1)!
                    } else {
                        cands = shark.decode(p, topK: 5, context: ctx.folded)
                    }
                    if SwipeTyping.pick(cands, context: ctx, case: .lower)?.word == w { t1[k] += 1 }
                }
            }
        }
        print(String(format: "FUTO heldout iOS (nhịp, n=%d): SHARK2 %.3f | FUTO %.3f | ensemble %.3f", n,
                     Double(t1[0]) / Double(n), Double(t1[1]) / Double(n), Double(t1[2]) / Double(n)))
        XCTAssertGreaterThanOrEqual(t1[2], t1[0] - n / 100, "ensemble không được tụt quá 1 điểm so với SHARK2")
    }
}
