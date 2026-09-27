// FutoSwipeModel.swift — SUY LUẬN TỰ VIẾT cho encoder FUTO Swipe ("honorable_sturgeon", TCN
// ~634K tham số, https://huggingface.co/futo-org/futo-swipe — weights theo FUTO Model Weights
// License 1.0, powered by FUTO Swipe; xem docs/DATA-SOURCES.md). KHÔNG dùng code GPL của FUTO:
// kiến trúc đọc từ đồ thị .pte (Scripts/futo-swipe/), số học viết lại ở đây. Bản Kotlin song
// sinh: android/keyboard/src/main/kotlin/com/viettelex/keyboard/FutoSwipeModel.kt — sửa ở đây
// thì sửa y hệt bên kia (fixture chung KeyboardTests/Fixtures/futo-swipe-fixture.txt).
//
// Đầu vào: đường vuốt resample 64 điểm (x hàng rồi y hàng, vùng phím chữ chuẩn hoá 0–1) + tâm
// nk phím (0–1). Đầu ra: log-xác suất [32 × (nk+1)] (cột cuối = blank, CTC). Kiến trúc: 8 kênh
// đặc trưng (x, y, vx, vy, ax, ay — Savitzky–Golay 7 điểm đệm lặp biên —, tốc độ, độ cong
// của góc hướng unwrap kẹp ±2) → conv 8→128 k7 + hardswish → 5 khối [dwconv k7 dilation
// 1,2,3,5,8 → pw 128→512 → GLU → GRN → pw 256→128 → SE + residual] → adapter k2 s2 (→256,
// 32 bước) → λ = sigmoid(lin 256→1), hệ số DCT 8×8 (lin 256→64) → logit phím = Σ hệ số ·
// cos(π·u·x)·cos(π·v·y) tại tâm phím → log_softmax + ln λ; blank = ln(1−λ); kẹp ≥ −100.
//
// Bộ nhớ: asset fp16 1.27 MB → [Float] 2.5 MB (weights pointwise đã chuyển vị cho vDSP_mmul)
// + scratch ~0.35 MB, chỉ khi công tắc thử nghiệm bật (FutoSwipe giữ/nhả). KHÔNG thread-safe.
import Accelerate
import Foundation

final class FutoSwipeModel {
    static let T = 64, T2 = 32, maxKeys = 64
    private static let C = 128, E = 512, H = 256, SE = 32, AD = 256, NB = 5
    private static let dil = [1, 2, 3, 5, 8]

    // bố cục phẳng (Scripts/futo-swipe/convert.py, cùng thứ tự)
    private static let oSgD1X = 0, oSgD1Y = 7, oSgD2X = 14, oSgD2Y = 21, oSgD1C = 28
    private static let oInW = 35
    private static let oInB = oInW + C * 56
    private static let oBlock = oInB + C
    private static let bDwW = 0
    private static let bDwB = bDwW + 7 * C
    private static let bPw1W = bDwB + C
    private static let bPw1B = bPw1W + E * C
    private static let bGrnG = bPw1B + E
    private static let bGrnB = bGrnG + H
    private static let bPw2W = bGrnB + H
    private static let bPw2B = bPw2W + C * H
    private static let bSe1W = bPw2B + C
    private static let bSe1B = bSe1W + SE * C
    private static let bSe2W = bSe1B + SE
    private static let bSe2B = bSe2W + C * SE
    private static let blockSize = bSe2B + C
    private static let oAdW = oBlock + NB * blockSize
    private static let oAdB = oAdW + AD * 2 * C
    private static let oLamW = oAdB + AD
    private static let oLamB = oLamW + AD
    private static let oCoW = oLamB + 1
    private static let oCoB = oCoW + 64 * AD
    /// Tổng số tham số trong file.
    static let paramCount = oCoB + 64
    static let header = 16

    private var w: [Float]
    // scratch
    private var feat = [Float](repeating: 0, count: 8 * 64)
    private var pad = [Float](repeating: 0, count: 70)
    private var vx = [Float](repeating: 0, count: 64), vy = [Float](repeating: 0, count: 64)
    private var th = [Float](repeating: 0, count: 64)
    private var h = [Float](repeating: 0, count: 64 * 128)
    private var z = [Float](repeating: 0, count: 64 * 128)
    private var p = [Float](repeating: 0, count: 64 * 512)
    private var g = [Float](repeating: 0, count: 64 * 256)
    private var u = [Float](repeating: 0, count: 64 * 128)
    private var gx = [Float](repeating: 0, count: 256)
    private var m = [Float](repeating: 0, count: 128), s1 = [Float](repeating: 0, count: 32)
    private var s2 = [Float](repeating: 0, count: 128)
    private var a = [Float](repeating: 0, count: 32 * 256)
    private var coef = [Float](repeating: 0, count: 32 * 64)
    private var lam = [Float](repeating: 0, count: 32)
    private var basis = [Float](repeating: 0, count: 64 * 64)
    private var logits = [Float](repeating: 0, count: 64 * 32)

    private init(w: [Float]) { self.w = w }

    /// Header "VTFS" v1 + đúng `paramCount` số fp16; nil nếu hỏng/lệch.
    static func load(_ d: Data) -> FutoSwipeModel? {
        guard d.count == header + 2 * paramCount, d.prefix(4).elementsEqual("VTFS".utf8) else { return nil }
        func u32(_ o: Int) -> UInt32 {
            d.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
        }
        guard u32(4) == 1, u32(8) == UInt32(paramCount) else { return nil }
        var w = [Float](repeating: 0, count: paramCount)
        var ok = true
        d.withUnsafeBytes { raw in
            w.withUnsafeMutableBufferPointer { dst in
                var src = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: raw.baseAddress! + header),
                                        height: 1, width: vImagePixelCount(paramCount), rowBytes: paramCount * 2)
                var out = vImage_Buffer(data: dst.baseAddress!, height: 1, width: vImagePixelCount(paramCount),
                                        rowBytes: paramCount * 4)
                ok = vImageConvert_Planar16FtoPlanarF(&src, &out, vImage_Flags(kvImageNoFlags)) == kvImageNoError
            }
        }
        guard ok, !w.contains(where: { !$0.isFinite }) else { return nil }
        // chuyển vị weights pointwise [O][Cin] → [Cin][O] cho vDSP_mmul (in·Wᵀ)
        func transpose(_ off: Int, _ o: Int, _ cin: Int) {
            let src = Array(w[off..<(off + o * cin)])
            w.withUnsafeMutableBufferPointer { W in
                src.withUnsafeBufferPointer { S in
                    vDSP_mtrans(S.baseAddress!, 1, W.baseAddress! + off, 1, vDSP_Length(cin), vDSP_Length(o))
                }
            }
        }
        for b in 0..<NB {
            let o = oBlock + b * blockSize
            transpose(o + bPw1W, E, C)
            transpose(o + bPw2W, C, H)
        }
        transpose(oAdW, AD, 2 * C)
        transpose(oCoW, 64, AD)
        return FutoSwipeModel(w: w)
    }

    /// fp16 IEEE → Float (test đối chiếu Kotlin).
    static func halfToFloat(_ bits: UInt16) -> Float {
        var src = bits, dst: Float = 0
        withUnsafeMutablePointer(to: &src) { sp in
            withUnsafeMutablePointer(to: &dst) { dp in
                var s = vImage_Buffer(data: sp, height: 1, width: 1, rowBytes: 2)
                var o = vImage_Buffer(data: dp, height: 1, width: 1, rowBytes: 4)
                _ = vImageConvert_Planar16FtoPlanarF(&s, &o, vImage_Flags(kvImageNoFlags))
            }
        }
        return dst
    }

    @inline(__always) private static func sigmoid(_ x: Float) -> Float { Float(1 / (1 + exp(-Double(x)))) }
    @inline(__always) private static func hardswish(_ x: Float) -> Float { x * min(max(x + 3, 0), 6) / 6 }

    /// Chạy encoder: `feats` 128 số, `keys` 2·nk, `out` ≥ 32·(nk+1). `lambdaOut` nhận λ (tuỳ chọn).
    func run(_ feats: [Float], _ keys: [Float], _ nk: Int, _ out: inout [Float], lambdaOut: UnsafeMutablePointer<Float>? = nil) {
        precondition(nk >= 1 && nk <= Self.maxKeys && keys.count >= 2 * nk && out.count >= Self.T2 * (nk + 1))
        features(feats)
        inputConv()
        for b in 0..<Self.NB { block(b) }
        pointwise(h, Self.T2, 2 * Self.C, Self.oAdW, Self.oAdB, Self.AD, &a)
        let T2 = Self.T2, AD = Self.AD
        w.withUnsafeBufferPointer { W in
            a.withUnsafeBufferPointer { A in
                for t in 0..<T2 {
                    var s: Float = 0
                    vDSP_dotpr(A.baseAddress! + t * AD, 1, W.baseAddress! + Self.oLamW, 1, &s, vDSP_Length(AD))
                    lam[t] = Self.sigmoid(s + W[Self.oLamB])
                }
            }
        }
        pointwise(a, T2, AD, Self.oCoW, Self.oCoB, 64, &coef)
        if basis.count < nk * 64 { basis = [Float](repeating: 0, count: nk * 64) }
        var bx = [Float](repeating: 0, count: 8), by = bx
        for k in 0..<nk {
            let kx = Double(keys[2 * k]), ky = Double(keys[2 * k + 1])
            for q in 0..<8 {
                bx[q] = Float(cos(Double.pi * kx * Double(q)))
                by[q] = Float(cos(Double.pi * ky * Double(q)))
            }
            for uu in 0..<8 { for v in 0..<8 { basis[k * 64 + uu * 8 + v] = bx[uu] * by[v] } }
        }
        // logits[t][k] = coef[t]·basis[k]  (coef 32×64 · basisᵀ 64×nk)
        if logits.count < T2 * nk { logits = [Float](repeating: 0, count: T2 * nk) }
        var bt = [Float](repeating: 0, count: 64 * nk)
        vDSP_mtrans(basis, 1, &bt, 1, 64, vDSP_Length(nk))
        vDSP_mmul(coef, 1, bt, 1, &logits, 1, vDSP_Length(T2), vDSP_Length(nk), 64)
        let stride = nk + 1
        for t in 0..<T2 {
            var mx = -Float.infinity
            for k in 0..<nk where logits[t * nk + k] > mx { mx = logits[t * nk + k] }
            var sum = 0.0
            for k in 0..<nk { sum += exp(Double(logits[t * nk + k] - mx)) }
            let lse = mx + Float(log(sum))
            let l = lam[t]
            let ll = log(max(l, 1e-7)), lb = log(max(1 - l, 1e-7))
            for k in 0..<nk { out[t * stride + k] = max(logits[t * nk + k] - lse + ll, -100) }
            out[t * stride + nk] = max(lb, -100)
            lambdaOut?[t] = l
        }
    }

    private func savgol(_ src: UnsafePointer<Float>, _ wOff: Int, _ dst: UnsafeMutablePointer<Float>) {
        let T = Self.T
        for i in 0..<3 { pad[i] = src[0]; pad[3 + T + i] = src[T - 1] }
        for i in 0..<T { pad[3 + i] = src[i] }
        for t in 0..<T {
            var s: Float = 0
            for k in 0..<7 { s += pad[t + k] * w[wOff + k] }
            dst[t] = s
        }
    }

    private func features(_ f: [Float]) {
        let T = Self.T
        var feat = self.feat, vx = self.vx, vy = self.vy, th = self.th
        f.withUnsafeBufferPointer { F in
            feat.withUnsafeMutableBufferPointer { D in
                for i in 0..<(2 * T) { D[i] = F[i] }
                vx.withUnsafeMutableBufferPointer { savgol(F.baseAddress!, Self.oSgD1X, $0.baseAddress!) }
                vy.withUnsafeMutableBufferPointer { savgol(F.baseAddress! + T, Self.oSgD1Y, $0.baseAddress!) }
                for t in 0..<T { D[2 * T + t] = vx[t]; D[3 * T + t] = vy[t] }
                savgol(F.baseAddress!, Self.oSgD2X, D.baseAddress! + 4 * T)
                savgol(F.baseAddress! + T, Self.oSgD2Y, D.baseAddress! + 5 * T)
                for t in 0..<T { D[6 * T + t] = (vx[t] * vx[t] + vy[t] * vy[t] + 1e-8).squareRoot() }
                let pi = Float.pi, twoPi = 2 * Float.pi
                var acc: Float = 0, prev: Float = 0
                for t in 0..<T {
                    let an = atan2(vy[t], vx[t])
                    if t > 0 {
                        let d = an - prev
                        var corr: Float = d > pi ? -twoPi : 0
                        if d < -pi { corr += twoPi }
                        acc += corr
                    }
                    prev = an
                    th[t] = an + acc
                }
                th.withUnsafeBufferPointer { savgol($0.baseAddress!, Self.oSgD1C, D.baseAddress! + 7 * T) }
                for t in 0..<T { D[7 * T + t] = min(max(D[7 * T + t], -2), 2) }
            }
        }
        self.feat = feat; self.vx = vx; self.vy = vy; self.th = th
    }

    private func inputConv() {
        let T = Self.T, C = Self.C
        w.withUnsafeBufferPointer { W in
            feat.withUnsafeBufferPointer { F in
                h.withUnsafeMutableBufferPointer { Hp in
                    for t in 0..<T {
                        for o in 0..<C {
                            var s = W[Self.oInB + o]
                            for k in 0..<7 {
                                let ti = t - 3 + k
                                if ti < 0 || ti >= T { continue }
                                let wb = Self.oInW + (o * 7 + k) * 8
                                for c in 0..<8 { s += F[c * T + ti] * W[wb + c] }
                            }
                            Hp[t * C + o] = Self.hardswish(s)
                        }
                    }
                }
            }
        }
    }

    private func block(_ b: Int) {
        let T = Self.T, C = Self.C, H = Self.H, E = Self.E, SE = Self.SE
        let o = Self.oBlock + b * Self.blockSize
        let d = Self.dil[b]
        w.withUnsafeBufferPointer { W in
            h.withUnsafeBufferPointer { Hp in
                z.withUnsafeMutableBufferPointer { Z in
                    for t in 0..<T {
                        let zb = t * C
                        for c in 0..<C { Z[zb + c] = W[o + Self.bDwB + c] }
                        for k in 0..<7 {
                            let ti = t + (k - 3) * d
                            if ti < 0 || ti >= T { continue }
                            // Z[zb..] += H[ti..] * W[k..]
                            vDSP_vma(Hp.baseAddress! + ti * C, 1, W.baseAddress! + o + Self.bDwW + k * C, 1,
                                     Z.baseAddress! + zb, 1, Z.baseAddress! + zb, 1, vDSP_Length(C))
                        }
                    }
                }
            }
        }
        pointwise(z, T, C, o + Self.bPw1W, o + Self.bPw1B, E, &p)
        p.withUnsafeBufferPointer { P in
            g.withUnsafeMutableBufferPointer { G in
                for t in 0..<T {
                    let pb = t * E, gb = t * H
                    for j in 0..<H { G[gb + j] = Self.sigmoid(P[pb + j]) * P[pb + H + j] }
                }
            }
        }
        // GRN
        w.withUnsafeBufferPointer { W in
            g.withUnsafeMutableBufferPointer { G in
                var mean: Float = 0
                for j in 0..<H {
                    var s: Float = 0
                    for t in 0..<T { let v = G[t * H + j]; s += v * v }
                    gx[j] = (s / Float(T) + 1e-6).squareRoot()
                    mean += gx[j]
                }
                let mg = mean / Float(H) + 1e-6
                for t in 0..<T {
                    let gb = t * H
                    for j in 0..<H {
                        let v = G[gb + j]
                        G[gb + j] = W[o + Self.bGrnG + j] * (v * (gx[j] / mg)) + W[o + Self.bGrnB + j] + v
                    }
                }
            }
        }
        pointwise(g, T, H, o + Self.bPw2W, o + Self.bPw2B, C, &u)
        // SE
        w.withUnsafeBufferPointer { W in
            u.withUnsafeMutableBufferPointer { U in
                h.withUnsafeMutableBufferPointer { Hp in
                    for c in 0..<C { m[c] = 0 }
                    for t in 0..<T { for c in 0..<C { m[c] += U[t * C + c] } }
                    for c in 0..<C { m[c] /= Float(T) }
                    for j in 0..<SE {
                        var s = W[o + Self.bSe1B + j]
                        let wb = o + Self.bSe1W + j * C
                        for c in 0..<C { s += m[c] * W[wb + c] }
                        s1[j] = max(0, s)
                    }
                    for c in 0..<C {
                        var s = W[o + Self.bSe2B + c]
                        let wb = o + Self.bSe2W + c * SE
                        for j in 0..<SE { s += s1[j] * W[wb + j] }
                        s2[c] = Self.sigmoid(s)
                    }
                    for t in 0..<T {
                        let b0 = t * C
                        for c in 0..<C { Hp[b0 + c] = U[b0 + c] * s2[c] + Hp[b0 + c] }
                    }
                }
            }
        }
    }

    /// out[t][o] = b[o] + Σ_c inp[t][c]·W[o][c]; W lưu chuyển vị [Cin][O] ⇒ vDSP_mmul(inp, Wᵀ).
    private func pointwise(_ inp: [Float], _ rows: Int, _ cin: Int, _ wOff: Int, _ bOff: Int, _ cout: Int,
                           _ out: inout [Float]) {
        w.withUnsafeBufferPointer { W in
            inp.withUnsafeBufferPointer { I in
                out.withUnsafeMutableBufferPointer { O in
                    vDSP_mmul(I.baseAddress!, 1, W.baseAddress! + wOff, 1, O.baseAddress!, 1,
                              vDSP_Length(rows), vDSP_Length(cout), vDSP_Length(cin))
                    for t in 0..<rows {
                        vDSP_vadd(O.baseAddress! + t * cout, 1, W.baseAddress! + bOff, 1,
                                  O.baseAddress! + t * cout, 1, vDSP_Length(cout))
                    }
                }
            }
        }
    }
}
