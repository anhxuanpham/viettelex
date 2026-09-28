// Lõi gõ vuốt: độ chính xác trên đường vuốt giả, ca khó, parity với bản Kotlin
// (fixture Fixtures/swipe-paths.txt). Cùng bộ ca với android SwipeDecoderTests.kt.
import XCTest

/// Sinh đường vuốt giả — song sinh SwipeSim trong android/keyboard/src/test/…/SwipeDecoderTests.kt.
/// Tâm phím + nhiễu Gaussian σ·phím (điểm điều khiển), lệch đầu/cuối tuỳ chọn, làm mượt
/// Catmull-Rom, mỗi mẫu ~0.35 phím (≈ vuốt 20 phím/s lấy mẫu 60Hz) + rung 0.04 phím,
/// rồi đi qua SwipePath (lọc 1/5 phím) như bản tích hợp.
struct SwipeSim {
    private var s: UInt64
    init(seed: UInt64) { s = seed }

    private mutating func next() -> UInt64 {
        s = s &+ 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func gauss() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    static func collapse(_ s: String) -> String {
        var out = ""
        for c in s where out.last != c { out.append(c) }
        return out
    }

    private static func catmull(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double,
                                _ t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    mutating func path(_ word: String, _ layout: SwipeLayout, sigma: Double = 0.25,
                       endOffset: Double = 0, jitter: Double = 0.04,
                       step: Double = 0.35) -> SwipePath {
        let w = Double(layout.keyWidth)
        let keys = Array(Self.collapse(word))
        var cx = [Double](repeating: 0, count: keys.count), cy = cx
        for (i, ch) in keys.enumerated() {
            let c = layout.center(of: ch)!
            cx[i] = Double(c.x) + gauss() * sigma * w
            cy[i] = Double(c.y) + gauss() * sigma * w
        }
        if endOffset > 0 {
            var a = uniform() * 2 * Double.pi
            cx[0] += cos(a) * endOffset * w; cy[0] += sin(a) * endOffset * w
            a = uniform() * 2 * Double.pi
            let e = keys.count - 1
            cx[e] += cos(a) * endOffset * w; cy[e] += sin(a) * endOffset * w
        }
        var p = SwipePath(minDistance: layout.keyWidth / 5)
        if keys.count == 1 {
            for i in 0..<4 {
                p.add(x: Float(cx[0] + gauss() * jitter * w), y: Float(cy[0] + gauss() * jitter * w),
                      t: Double(i) / 60)
            }
            return p
        }
        var t = 0.0
        let m = keys.count
        for sg in 0..<(m - 1) {
            let i0 = max(sg - 1, 0), i1 = sg, i2 = sg + 1, i3 = min(sg + 2, m - 1)
            let n = max(2, Int(ceil(hypot(cx[i2] - cx[i1], cy[i2] - cy[i1]) / (step * w))))
            for j in 0..<n {
                let u = Double(j) / Double(n)
                let x = Self.catmull(cx[i0], cx[i1], cx[i2], cx[i3], u) + gauss() * jitter * w
                let y = Self.catmull(cy[i0], cy[i1], cy[i2], cy[i3], u) + gauss() * jitter * w
                p.add(x: Float(x), y: Float(y), t: t); t += 1.0 / 60
            }
        }
        p.add(x: Float(cx[m - 1]), y: Float(cy[m - 1]), t: t, force: true)
        return p
    }

    /// Đường vuốt "TỰ NHIÊN" — song sinh SwipeSim.natural (Kotlin), hiệu chỉnh theo nét thật (45
    /// nét iPhone, 28/09/2026, docs/DATA-SOURCES.md "Nét vuốt thật"): lấy mẫu 60 Hz, giữ ngón
    /// ~50–120 ms ở phím đầu, tốc độ đỉnh ~20–40 phím/s trên đoạn thẳng và CHẬM lại ở phím định
    /// đi qua (có khi dừng), điểm đầu hơi lùi sau phím đầu, điểm cuối LỐ quá phím cuối theo hướng
    /// nét (trôi chậm trước khi nhấc tay, trung vị ~0.45 phím).
    mutating func natural(_ word: String, _ layout: SwipeLayout, sigma: Double = 0.2, speed: Double = 1,
                          overshoot: Double = 0.4) -> SwipePath {
        let w = Double(layout.keyWidth)
        let keys = Array(Self.collapse(word))
        let m = keys.count
        var p = SwipePath(minDistance: layout.keyWidth / 5)
        var cx = [Double](repeating: 0, count: m), cy = cx
        for (i, ch) in keys.enumerated() {
            let c = layout.center(of: ch)!
            cx[i] = Double(c.x) + gauss() * sigma * w
            cy[i] = Double(c.y) + gauss() * sigma * w
        }
        if m == 1 {
            for i in 0..<6 {
                p.add(x: Float(cx[0] + gauss() * 0.03 * w), y: Float(cy[0] + gauss() * 0.03 * w), t: Double(i) / 60)
            }
            return p
        }
        // điểm đầu: lùi sau phím đầu theo hướng nét + lệch ngang
        var dx = cx[1] - cx[0], dy = cy[1] - cy[0]
        var dn = max(1e-6, hypot(dx, dy))
        dx /= dn; dy /= dn
        let a0 = (gauss() * 0.22 - 0.15) * w, b0 = gauss() * 0.25 * w
        var px = [cx[0] + dx * a0 - dy * b0], py = [cy[0] + dy * a0 + dx * b0]
        for i in 1..<m { px.append(cx[i]); py.append(cy[i]) }
        // điểm cuối: lố theo hướng nét cuối (trôi chậm) + lệch ngang
        dx = cx[m - 1] - cx[m - 2]; dy = cy[m - 1] - cy[m - 2]; dn = max(1e-6, hypot(dx, dy))
        dx /= dn; dy /= dn
        let o = max(-0.2, overshoot + gauss() * 0.4) * w, b1 = gauss() * 0.3 * w
        let drift = o > 0.1 * w
        let lift = -0.15 * w   // nhấc tay hơi trượt lên (nét thật: dy cuối trung bình −0.4 phím)
        if drift { px.append(cx[m - 1] + dx * o - dy * b1); py.append(cy[m - 1] + dy * o + dx * b1 + lift) }
        else { px[m - 1] = cx[m - 1] + dx * o - dy * b1; py[m - 1] = cy[m - 1] + dy * o + dx * b1 + lift }
        // hình học: Catmull-Rom dày (0.05 phím) → độ dài cung s (phím)
        var gx = [px[0]], gy = [py[0]], gs = [0.0]
        let q = px.count
        var via = [Double](repeating: 0, count: q)
        for sg in 0..<(q - 1) {
            let i0 = max(sg - 1, 0), i1 = sg, i2 = sg + 1, i3 = min(sg + 2, q - 1)
            let n = max(2, Int(ceil(hypot(px[i2] - px[i1], py[i2] - py[i1]) / (0.05 * w))))
            for j in 1...n {
                let u = Double(j) / Double(n)
                let x = Self.catmull(px[i0], px[i1], px[i2], px[i3], u)
                let y = Self.catmull(py[i0], py[i1], py[i2], py[i3], u)
                gs.append(gs.last! + hypot(x - gx.last!, y - gy.last!) / w); gx.append(x); gy.append(y)
            }
            via[sg + 1] = gs.last!
        }
        let total = gs.last!
        // tốc độ (phím/s): đỉnh vPeak, trũng ρ ở phím đi qua, đầu/cuối chậm
        let vPeak = 30 * speed * exp(gauss() * 0.2)
        var rho = [Double](repeating: 0, count: q)
        for k in 0..<q { rho[k] = 0.05 + uniform() * 0.6 }
        rho[0] = 0.12; rho[m - 1] = 0.15
        let vDrift = 3 + uniform() * 5
        let ramp = 0.9
        func v(_ s: Double) -> Double {
            var g = 1.0
            for k in 0..<m {
                let gk = rho[k] + (1 - rho[k]) * min(1, abs(s - via[k]) / ramp)
                if gk < g { g = gk }
            }
            var vv = vPeak * g
            if drift && s > via[m - 1] { vv = min(vv, vDrift) }
            return max(1, vv)
        }
        // dừng: giữ ngón ở phím đầu; đôi khi dừng ở phím giữa / phím cuối
        var pause = [Double](repeating: 0, count: q)
        pause[0] = 0.02 + uniform() * 0.06
        if m > 2 { for k in 1..<(m - 1) where uniform() < 0.35 { pause[k] = 0.02 + uniform() * 0.08 } }
        if uniform() < 0.5 { pause[m - 1] = 0.02 + uniform() * 0.06 }
        let dt = 1.0 / 60
        var t = 0.0, s = 0.0, gi = 0, nextVia = 0
        let jit = 0.025 * w
        func at(_ s: Double) -> (Double, Double) {
            while gi < gs.count - 2 && gs[gi + 1] < s { gi += 1 }
            let seg = gs[gi + 1] - gs[gi]
            let u = seg > 0 ? min(1, max(0, (s - gs[gi]) / seg)) : 0
            return (gx[gi] + (gx[gi + 1] - gx[gi]) * u, gy[gi] + (gy[gi + 1] - gy[gi]) * u)
        }
        p.add(x: Float(px[0]), y: Float(py[0]), t: 0)
        while s < total {
            if nextVia < m && s >= via[nextVia] {
                var hold = pause[nextVia]
                while hold > 0 {
                    t += dt; hold -= dt
                    let (x, y) = at(s)
                    p.add(x: Float(x + gauss() * 0.3 * jit), y: Float(y + gauss() * 0.3 * jit), t: t)
                }
                nextVia += 1
                continue
            }
            let v1 = v(s), v2 = v(s + v1 * dt * 0.5)
            s = min(total, s + v2 * dt); t += dt
            let (x, y) = at(s)
            p.add(x: Float(x + gauss() * jit), y: Float(y + gauss() * jit), t: t)
        }
        p.add(x: Float(px[q - 1]), y: Float(py[q - 1]), t: t + dt, force: true)
        return p
    }
}

final class SwipeDecoderTests: XCTestCase {
    private let layout = SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)
    private func decoder() -> SwipeDecoder {
        let d = SwipeDecoder(); d.setLayout(layout); return d
    }

    /// 500 dạng không dấu phổ biến nhất (≥ 2 phím sau gộp lặp) — cùng thứ tự bản Kotlin.
    private func corpus(_ n: Int = 500) -> [String] {
        let f = SwipeLexicon.forms
        return (0..<f.count)
            .filter { SwipeSim.collapse(f.folded[$0]).count >= 2 }
            .sorted { f.freq[$0] != f.freq[$1] ? f.freq[$0] > f.freq[$1] : f.folded[$0] < f.folded[$1] }
            .prefix(n).map { f.folded[$0] }
    }

    private func accuracy(_ d: SwipeDecoder, _ words: [String], seed: UInt64, sigma: Double = 0.25,
                          endOffset: Double = 0) -> (Double, Double) {
        var sim = SwipeSim(seed: seed)
        var t1 = 0, t3 = 0
        for w in words {
            let r = d.decode(sim.path(w, layout, sigma: sigma, endOffset: endOffset), topK: 3)
                .map(\.folded)
            if r.first == w { t1 += 1 }
            if r.contains(w) { t3 += 1 }
        }
        return (Double(t1) / Double(words.count), Double(t3) / Double(words.count))
    }

    /// String.hashCode của Java — để seed từng ca giống bản Kotlin.
    private func javaHash(_ s: String) -> UInt64 {
        var h: Int32 = 0
        for u in s.utf16 { h = h &* 31 &+ Int32(u) }
        return UInt64(UInt32(bitPattern: h)) & 0xFFFF
    }

    private func hitRate(_ d: SwipeDecoder, _ word: String, _ k: Int, n: Int = 20,
                         sigma: Double = 0.2, endOffset: Double = 0) -> Double {
        var sim = SwipeSim(seed: javaHash(word))
        var hit = 0
        for _ in 0..<n where d.decode(sim.path(word, layout, sigma: sigma, endOffset: endOffset),
                                      topK: k).contains(where: { $0.folded == word }) {
            hit += 1
        }
        return Double(hit) / Double(n)
    }

    private func cleanTop(_ d: SwipeDecoder, _ w: String, _ k: Int) -> Bool {
        var sim = SwipeSim(seed: 1)
        return d.decode(sim.path(w, layout, sigma: 0, jitter: 0), topK: k)
            .contains { $0.folded == w }
    }

    func testLexiconForms() {
        let f = SwipeLexicon.forms
        XCTAssertEqual(f.count, 1666)
        XCTAssertNotNil(SwipeLexicon.index(of: "viet"))
        XCTAssertNil(SwipeLexicon.index(of: "zzz"))
        let i = SwipeLexicon.index(of: "boong")!
        let keys = (Int(f.keyStart[i])..<Int(f.keyStart[i + 1]))
            .map { String(UnicodeScalar(f.keys[$0] + 97)) }.joined()
        XCTAssertEqual(keys, "bong")
    }

    func testAccuracyTop500() {
        let d = decoder(), words = corpus()
        let (a1, a3) = accuracy(d, words, seed: 42)
        let (b1, b3) = accuracy(d, words, seed: 7, sigma: 0.3)
        let (c1, c3) = accuracy(d, words, seed: 42, endOffset: 0.5)
        print(String(format: "SWIPE accuracy σ0.25: top1 %.3f top3 %.3f | σ0.3: %.3f/%.3f | lệch đầu/cuối 0.5: %.3f/%.3f",
                     a1, a3, b1, b3, c1, c3))
        // đo 27/09/2026 (tầng 2 + kênh độ dài): 0.902/0.994 | 0.836/0.984 | 0.724/0.952
        // (trước: 0.900/0.996 | 0.824/0.978 | 0.684/0.914) — cùng ngưỡng Kotlin
        XCTAssertGreaterThanOrEqual(a1, 0.85); XCTAssertGreaterThanOrEqual(a3, 0.98)
        XCTAssertGreaterThanOrEqual(b1, 0.80); XCTAssertGreaterThanOrEqual(b3, 0.96)
        XCTAssertGreaterThanOrEqual(c1, 0.69); XCTAssertGreaterThanOrEqual(c3, 0.93)
    }

    /// Tầng 2 (σ thích nghi + căn phím + góc) + kênh độ dài phải hơn SHARK2 trần ở ca khó.
    func testRescoreBeatsPlainShark2() {
        var pp = SwipeDecoder.Params(); pp.rescorePool = 0; pp.lengthWeight = 0
        let plain = SwipeDecoder(params: pp); plain.setLayout(layout)
        let d = decoder(), words = corpus()
        let (p1, _) = accuracy(plain, words, seed: 42, endOffset: 0.5)
        let (n1, _) = accuracy(d, words, seed: 42, endOffset: 0.5)
        let (q1, _) = accuracy(plain, words, seed: 7, sigma: 0.3)
        let (m1, _) = accuracy(d, words, seed: 7, sigma: 0.3)
        print(String(format: "SWIPE tầng 2: lệch 0.5 %.3f → %.3f | σ0.3 %.3f → %.3f", p1, n1, q1, m1))
        XCTAssertGreaterThanOrEqual(n1, p1 + 0.02)
        XCTAssertGreaterThanOrEqual(m1, q1)
    }

    /// Đường của `words` dời cả nét (dx, dy) phím — người dùng có lệch tay hệ thống.
    private func biasedPaths(_ words: [String], seed: UInt64, dx: Float, dy: Float) -> [SwipePath] {
        var sim = SwipeSim(seed: seed)
        return words.map { w in
            let p = sim.path(w, layout)
            var q = SwipePath(minDistance: p.minDistance)
            for i in 0..<p.count {
                q.add(x: p.xs[i] + dx * layout.keyWidth, y: p.ys[i] + dy * layout.keyWidth, t: p.ts[i], force: true)
            }
            return q
        }
    }

    private func top1(_ d: SwipeDecoder, _ paths: [SwipePath], _ words: [String]) -> Double {
        Double(paths.indices.filter { d.decode(paths[$0], topK: 1).first?.folded == words[$0] }.count)
            / Double(words.count)
    }

    func testLearnOffsetConvergesAndHelps() {
        let d = decoder(), words = corpus()
        let train = words.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let test = words.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let trainPaths = biasedPaths(train, seed: 5, dx: 0.3, dy: 0.25)
        let testPaths = biasedPaths(test, seed: 6, dx: 0.3, dy: 0.25)
        let before = top1(d, testPaths, test)
        for (i, p) in trainPaths.prefix(120).enumerated() { XCTAssertTrue(d.learnOffset(p, folded: train[i])) }
        let after = top1(d, testPaths, test)
        print(String(format: "SWIPE học lệch (0.30, 0.25): học được (%.3f, %.3f), top1 %.3f → %.3f",
                     d.offsetX, d.offsetY, before, after))
        XCTAssertEqual(d.offsetX, 0.3, accuracy: 0.08)
        XCTAssertEqual(d.offsetY, 0.25, accuracy: 0.08)
        XCTAssertGreaterThanOrEqual(after, before + 0.05)
        // không lệch ⇒ học quanh 0 và không hại
        let u = decoder()
        var sim = SwipeSim(seed: 8)
        for w in train.prefix(120) { u.learnOffset(sim.path(w, layout), folded: w) }
        XCTAssertLessThan(abs(u.offsetX), 0.06); XCTAssertLessThan(abs(u.offsetY), 0.06)
        // dạng lạ / đường 1 điểm ⇒ không học
        var p1 = SwipePath(minDistance: 1); p1.add(x: 10, y: 10, t: 0)
        XCTAssertFalse(u.learnOffset(sim.path("viet", layout), folded: "zzz"))
        XCTAssertFalse(u.learnOffset(p1, folded: "viet"))
    }

    func testVietExpandsToAccented() {
        let d = decoder()
        XCTAssertGreaterThanOrEqual(hitRate(d, "viet", 3), 0.9)
        let words = SwipeDecoder.expand("viet").map(\.word)
        XCTAssertTrue(Set(words.prefix(3)).isSuperset(of: ["việt", "viết"]), "\(words)")
        XCTAssertTrue(SwipeDecoder.expand("di").map(\.word).contains("đi"))
    }

    func testHardPairsInTop3() {
        let d = decoder()
        for w in ["cho", "co", "nay", "ngay", "trong", "truong", "bua", "nua"] {
            let r = hitRate(d, w, 3)
            XCTAssertGreaterThanOrEqual(r, 0.85, "\(w) top-3 rate \(r)")
        }
    }

    func testRepeatedLetters() {
        let d = decoder()
        XCTAssertGreaterThanOrEqual(hitRate(d, "luu", 3), 0.9)
        XCTAssertGreaterThanOrEqual(hitRate(d, "boong", 3), 0.85)
        XCTAssertEqual(SwipeDecoder.expand("luu").first?.word, "lưu")
    }

    func testTwoLetterWords() {
        let d = decoder()
        for w in ["an", "em", "di", "la", "ta", "va", "de", "no"] {
            XCTAssertTrue(cleanTop(d, w, 1), "\(w) top-1 (đường sạch)")
            XCTAssertGreaterThanOrEqual(hitRate(d, w, 3), 0.9, "\(w) top-3 nhiễu")
        }
    }

    func testEndpointsOffsetHalfKey() {
        let d = decoder()
        for w in ["khong", "nguoi", "duoc", "viet", "chung"] {
            let r = hitRate(d, w, 3, sigma: 0.15, endOffset: 0.5)
            XCTAssertGreaterThanOrEqual(r, 0.8, "\(w) lệch nửa phím: \(r)")
        }
    }

    // MARK: NHỊP (thời gian điểm vuốt) — lỗi nét thật 28/09/2026 (song sinh Kotlin)

    private var legacyParams: SwipeDecoder.Params {
        var p = SwipeDecoder.Params(); p.speedWeight = 0; p.dwellWeight = 0; p.overshoot = 0; return p
    }

    /// Điểm dừng của `glide`: toạ độ (đơn vị phím, gốc = tâm `at`), tốc độ đi tới (phím/s), giữ (s).
    private struct Stop {
        var at: Character; var dx: Float = 0; var dy: Float = 0; var speed: Float = 25; var hold: Double = 0
    }

    /// Đường vuốt tuyến tính qua `stops`, lấy mẫu 60 Hz, qua SwipePath.
    private func glide(_ stops: [Stop]) -> SwipePath {
        let w = layout.keyWidth
        var p = SwipePath(minDistance: w / 5)
        var t = 0.0
        func xy(_ s: Stop) -> (Float, Float) {
            let c = layout.center(of: s.at)!; return (c.x + s.dx * w, c.y + s.dy * w)
        }
        var (x, y) = xy(stops[0])
        p.add(x: x, y: y, t: t)
        for (k, s) in stops.enumerated() {
            if k > 0 {
                let (tx, ty) = xy(s)
                let d = hypot(Double(tx - x), Double(ty - y)) / Double(w)
                let n = max(1, Int(ceil(d / Double(s.speed) * 60)))
                for j in 1...n {
                    t += 1.0 / 60
                    p.add(x: x + (tx - x) * Float(j) / Float(n), y: y + (ty - y) * Float(j) / Float(n), t: t)
                }
                x = tx; y = ty
            }
            t += s.hold
        }
        p.add(x: x, y: y, t: t, force: true)
        return p
    }

    /// "đấy" ×3 trên iPhone ra "đâu": tới y rồi TRÔI chậm sang u trước khi nhấc tay.
    func testSlowDriftPastLastKeyIsOvershoot() {
        let p = glide([Stop(at: "d", hold: 0.08), Stop(at: "a", hold: 0.1), Stop(at: "y", dy: 0.1, speed: 22),
                       Stop(at: "y", dx: 0.65, dy: -0.15, speed: 3)])
        XCTAssertEqual(decoder().decode(p, topK: 3).first?.folded, "day")
        // cùng đường nhưng không có thời gian (đường đều) ⇒ hành vi cũ
        let old = SwipeDecoder(params: legacyParams); old.setLayout(layout)
        XCTAssertEqual(old.decode(p, topK: 3), decoder().decode(xs: p.xs, ys: p.ys, count: p.count, topK: 3))
    }

    /// "cũng" ra "chung": lướt NHANH qua h trên đường c→u rồi dừng ở u — h không phải phím định đi.
    func testFastPassThroughKeyIsNotInserted() {
        let p = glide([Stop(at: "c", hold: 0.08), Stop(at: "h", speed: 38), Stop(at: "u", speed: 30, hold: 0.1),
                       Stop(at: "n", speed: 20, hold: 0.06), Stop(at: "g", speed: 15, hold: 0.1)])
        XCTAssertEqual(decoder().decode(p, topK: 3).first?.folded, "cung")
        // dừng ở h ⇒ chung (phím có chủ đích)
        let q = glide([Stop(at: "c", hold: 0.08), Stop(at: "h", speed: 20, hold: 0.1), Stop(at: "u", speed: 20, hold: 0.1),
                       Stop(at: "n", speed: 20, hold: 0.06), Stop(at: "g", speed: 15, hold: 0.1)])
        XCTAssertEqual(decoder().decode(q, topK: 3).first?.folded, "chung")
    }

    /// Đường "tự nhiên" (nhịp + lố như nét thật): nhịp phải tăng rõ top-1, đường đều không tụt.
    func testTimingHelpsNaturalPaths() {
        let words = corpus(300)
        let d = decoder(), old = SwipeDecoder(params: legacyParams); old.setLayout(layout)
        func acc(_ dec: SwipeDecoder, _ natural: Bool) -> Double {
            var sim = SwipeSim(seed: 404)
            var ok = 0
            for w in words {
                let p = natural ? sim.natural(w, layout) : sim.path(w, layout)
                if dec.decode(p, topK: 3).first?.folded == w { ok += 1 }
            }
            return Double(ok) / Double(words.count)
        }
        let n0 = acc(old, true), n1 = acc(d, true), o0 = acc(old, false), o1 = acc(d, false)
        print(String(format: "SWIPE nhịp: đường tự nhiên top1 %.3f → %.3f | đường đều %.3f → %.3f", n0, n1, o0, o1))
        XCTAssertGreaterThanOrEqual(n1, n0 + 0.04)
        XCTAssertGreaterThanOrEqual(o1, o0 - 0.01)
    }

    func testContextReranks() {
        let d = decoder()
        var sim = SwipeSim(seed: 3)
        let p = sim.path("cho", layout, sigma: 0, jitter: 0)
        // c-h-o thẳng hàng: hình học không phân biệt được với "co" → tần suất quyết
        XCTAssertEqual(d.decode(p, topK: 3).first?.folded, "co")
        XCTAssertEqual(d.decode(p, topK: 3) { $0 == "cho" ? 3 : 0 }.first?.folded, "cho")
        XCTAssertEqual(SwipeDecoder.expand("cho") { $0 == "chó" ? 5 : 0 }.first?.word, "chó")
    }

    func testLayoutChangeRebuildsAndOtherLayoutWorks() {
        let d = decoder()
        var s5 = SwipeSim(seed: 5)
        _ = d.decode(s5.path("khong", layout), topK: 1)
        XCTAssertTrue((1...1_000_000).contains(d.templateBytes), "RAM \(d.templateBytes)")
        let l2 = SwipeLayout.qwerty(keyWidth: 36, rowHeight: 58, originX: 3, originY: 10)
        d.setLayout(l2)
        XCTAssertEqual(d.templateBytes, 0)
        var sim = SwipeSim(seed: 9)
        var ok = 0
        for w in corpus(100) where d.decode(sim.path(w, l2), topK: 3).contains(where: { $0.folded == w }) {
            ok += 1
        }
        XCTAssertGreaterThanOrEqual(ok, 95, "top3 layout 2 = \(ok)/100")
    }

    func testSwipePathFiltersAndCaps() {
        var p = SwipePath(minDistance: 8, capacity: 4)
        XCTAssertTrue(p.add(x: 0, y: 0, t: 0))
        XCTAssertFalse(p.add(x: 3, y: 4, t: 0.01))        // 5 < 8
        XCTAssertTrue(p.add(x: 6, y: 8, t: 0.02))         // 10
        XCTAssertEqual(p.count, 2); XCTAssertEqual(p.length, 10, accuracy: 1e-4)
        XCTAssertTrue(p.add(x: 7, y: 8, t: 0.03, force: true))
        XCTAssertEqual(p.count, 3)
        p.add(x: 20, y: 8, t: 0.04); XCTAssertEqual(p.count, 4)
        p.add(x: 40, y: 8, t: 0.05)                        // đầy → ghi đè điểm cuối
        XCTAssertEqual(p.count, 4); XCTAssertEqual(p.xs[3], 40)
        XCTAssertEqual(p.length, 44, accuracy: 1e-3)       // 10+1+33
        XCTAssertEqual(p.duration, 0.05, accuracy: 1e-9)
        p.reset(); XCTAssertEqual(p.count, 0)
        XCTAssertTrue(SwipeDecoder().decode(p).isEmpty)
    }

    func testBenchmark() throws {
        try SlowTests.require()
        let d = decoder()
        _ = SwipeLexicon.forms
        let t0 = CFAbsoluteTimeGetCurrent(); d.prepare()
        let build = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        var sim = SwipeSim(seed: 11)
        let paths = corpus(200).map { sim.path($0, layout) }
        var pp = SwipeDecoder.Params(); pp.rescorePool = 0; pp.lengthWeight = 0
        let plain = SwipeDecoder(params: pp); plain.setLayout(layout); plain.prepare()
        for p in paths { _ = d.decode(p, topK: 5); _ = plain.decode(p, topK: 5) }
        // lấy lần nhanh nhất / 3 (simulator hay giật)
        func best(_ x: SwipeDecoder) -> Double {
            var b = Double.infinity
            for _ in 0..<3 {
                let t = CFAbsoluteTimeGetCurrent()
                for p in paths { _ = x.decode(p, topK: 5) }
                b = min(b, (CFAbsoluteTimeGetCurrent() - t) * 1000 / Double(paths.count))
            }
            return b
        }
        let per = best(d), perPlain = best(plain)
        print(String(format: "SWIPE benchmark iOS: dựng template %.1f ms, decode %.3f ms/đường (SHARK2 trần %.3f), RAM template %d B",
                     build, per, perPlain, d.templateBytes))
        XCTAssertLessThan(per, 20)   // Debug -Onone trên simulator; Release nhanh hơn nhiều
        // nhịp (28/09/2026): đường tự nhiên CÓ thời gian, so với cùng decoder tắt nhịp
        let old = SwipeDecoder(params: legacyParams); old.setLayout(layout); old.prepare()
        var nsim = SwipeSim(seed: 12)
        let nat = corpus(200).map { nsim.natural($0, layout) }
        var tn: [Double] = [], to: [Double] = []
        for p in nat { _ = d.decode(p, topK: 5); _ = old.decode(p, topK: 5) }
        for _ in 0..<5 {
            var t = CFAbsoluteTimeGetCurrent()
            for p in nat { _ = d.decode(p, topK: 5) }
            tn.append((CFAbsoluteTimeGetCurrent() - t) * 1000 / Double(nat.count))
            t = CFAbsoluteTimeGetCurrent()
            for p in nat { _ = old.decode(p, topK: 5) }
            to.append((CFAbsoluteTimeGetCurrent() - t) * 1000 / Double(nat.count))
        }
        let mn = tn.sorted()[2], mo = to.sorted()[2]
        print(String(format: "SWIPE benchmark nhịp iOS: %.4f ms/đường (tắt nhịp %.4f, %+.1f%%)", mn, mo, (mn / mo - 1) * 100))
        XCTAssertLessThanOrEqual(mn, mo * 1.2 + 0.02)
    }

    /// Parity phần NHỊP: đường "tự nhiên" x,y,ms (Fixtures/swipe-paths-timed.txt, sinh bởi Kotlin).
    func testTimedFixtureParityWithKotlin() throws {
        let url = try XCTUnwrap(Bundle(for: SwipeDecoderTests.self)
            .url(forResource: "swipe-paths-timed", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let d = decoder()
        var n = 0, same = 0, right = 0
        var diffs: [String] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.isEmpty {
            let cols = line.split(separator: "\t")
            let pts = cols[3].split(separator: ";").map { $0.split(separator: ",") }
            let xs = pts.map { Float(String($0[0]))! }, ys = pts.map { Float(String($0[1]))! }
            let ts = pts.map { Double(String($0[2]))! / 1000 }
            let prior: SwipeEnglishPrior? = cols[1] == "vi" ? SwipeLangContext.defaultPrior
                : cols[1] == "en" ? SwipeLangContext.englishPrior : nil
            n += 1
            guard let r = d.decode(xs: xs, ys: ys, count: xs.count, topK: 3, context: nil, english: prior,
                                   englishContext: nil, ts: ts).first else { continue }
            let got = (r.lang == .en ? "en:" : "vi:") + r.folded
            if got == String(cols[2]) { same += 1 } else { diffs.append("\(cols[0]): \(got) ≠ \(cols[2])") }
            if r.folded == String(cols[0]) { right += 1 }
        }
        XCTAssertGreaterThanOrEqual(n, 190)
        XCTAssertEqual(same, n, "lệch Kotlin: \(diffs)")
        XCTAssertGreaterThanOrEqual(Double(right), Double(n) * 0.8)
    }

    /// Fixture sinh bởi bản Kotlin (SWIPE_WRITE_FIXTURE=1): top-1 hai bản phải trùng khít.
    func testFixtureParityWithKotlin() throws {
        let url = try XCTUnwrap(Bundle(for: SwipeDecoderTests.self)
            .url(forResource: "swipe-paths", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let d = decoder()
        var n = 0, same = 0
        var diffs: [String] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.isEmpty {
            let cols = line.split(separator: "\t")
            let pts = cols[2].split(separator: ";").map { $0.split(separator: ",") }
            let xs = pts.map { Float(String($0[0]))! }, ys = pts.map { Float(String($0[1]))! }
            n += 1
            let top = d.decode(xs: xs, ys: ys, count: xs.count, topK: 1).first?.folded
            if top == String(cols[1]) { same += 1 } else { diffs.append("\(cols[0]): \(top ?? "-") ≠ \(cols[1])") }
        }
        XCTAssertGreaterThanOrEqual(n, 150)
        XCTAssertEqual(same, n, "lệch Kotlin: \(diffs)")
    }
}
