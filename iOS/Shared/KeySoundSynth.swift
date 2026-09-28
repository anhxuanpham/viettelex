// KeySoundSynth — tổng hợp âm phím (thuần, tất định, test được). Dùng CHUNG app + bàn phím
// (Shared/): bàn phím phát, app nghe thử + nhập âm tự chọn. Thuật toán + công thức Y HỆT
// android/keyboard/.../KeySoundSynth.kt (test chốt cùng checksum hai bên).
//
// Phil 28/09/2026: bản đầu (sine 900–1850 Hz + nhiễu 1–6 kHz, mở 0.4 ms) "chói" ⇒ làm lại:
// thân sine TRẦM-TRUNG (200–700 Hz) có trượt cao độ nhẹ, nhiễu LỌC THẤP (≤ 3.5 kHz), mở mềm
// (raised-cosine 0.8–3 ms), đóng mềm, lọc thấp đầu ra. Test chốt trọng tâm phổ (spectral
// centroid) dưới ngưỡng ⇒ "không chói" đo được.
//
// CÔNG THỨC (mỗi kiểu = danh sách lớp; thời gian giây, tần số Hz):
//   tone: biên độ amp, trễ delay, cao độ f(t) = fEnd + (f0 − fEnd)·e^(−t/glide), tắt dần e^(−t/tau)
//   noise: nhiễu trắng xorshift32 (seed) → high-pass 1 cực hp → low-pass 2 cực lp, tắt dần tau
//   mỗi lớp mở raised-cosine `attack`; tổng → low-pass 1 cực `outLP` → chặn DC 40 Hz → đóng raised-cosine 3 ms
//   → chuẩn hoá đỉnh `peak`.
//   Phím xoá: cao độ ×0.86; phím chức năng (cách/Enter/shift): cao độ ×0.74, tắt chậm ×1.2,
//   dài thêm 6 ms — khác nhẹ như stock.
//
//   Nhẹ nhàng (mặc định): thân 500→360 Hz τ7 ms + bồi 1050→900 Hz τ2.5 ms (0.24) + nhiễu
//     lp 1.9 kHz τ2 ms (0.30); mở 1.6 ms; 32 ms; outLP 2.6 kHz; đỉnh 0.80.
//   Gõ gỗ: 640→590 Hz τ9 ms + mode 2.72× τ2.6 ms (0.28) + nhiễu lp 2.4 kHz τ1.4 ms (0.30); mở 0.9 ms; 42 ms.
//   Bàn phím cơ (thock): 230→180 Hz τ12 ms + 520→450 Hz τ4.5 ms (0.55) + nhiễu lp 1.3 kHz τ3.5 ms (0.55)
//     + chạm đáy trễ 7 ms (300 Hz τ5 ms 0.45 + nhiễu 0.28); mở 1.4 ms; 46 ms.
//   Máy chữ (êm): nhiễu hp 500 Hz lp 2.6 kHz τ2.8 ms (0.95) + 1050→850 Hz τ3 ms (0.35) + thân 260 Hz τ8 ms
//     (0.55) + tiếng "tách" nhỏ trễ 11 ms (nhiễu 0.30 τ1.8 ms); mở 0.8 ms; 44 ms; outLP 3.2 kHz; đỉnh 0.85.
//   Bong bóng: sine trượt LÊN 260→720 Hz (glide 9 ms) τ9 ms + bồi 2× (0.08); mở 3 ms; 36 ms; không nhiễu.
import Foundation

enum KeySoundKind: Int, CaseIterable {
    case letter, delete, modifier
}

/// Kiểu âm phím (setting `keySoundStyle`). rawValue = giá trị lưu/sao lưu.
enum KeySoundStyle: String, CaseIterable {
    case subtle, wood, mechanical, typewriter, bubble, custom

    static let defaultStyle: KeySoundStyle = .subtle
    static let presets: [KeySoundStyle] = [.subtle, .wood, .mechanical, .typewriter, .bubble]

    /// Tên hiển thị (khoá L10n tiếng Việt).
    var viTitle: String {
        switch self {
        case .subtle: return LK("Nhẹ nhàng")
        case .wood: return LK("Gõ gỗ")
        case .mechanical: return LK("Bàn phím cơ")
        case .typewriter: return LK("Máy chữ")
        case .bubble: return LK("Bong bóng")
        case .custom: return LK("Âm của bạn")
        }
    }

    /// Giá trị lưu → kiểu thật sự phát. Lạ ⇒ mặc định; `custom` mà file vắng/hỏng ⇒ mặc định.
    static func resolve(_ raw: String?, customAvailable: Bool) -> KeySoundStyle {
        guard let s = raw.flatMap(KeySoundStyle.init(rawValue:)) else { return defaultStyle }
        if s == .custom && !customAvailable { return defaultStyle }
        return s
    }
}

enum KeySoundSynth {
    static let sampleRate = 44_100.0
    /// Đổi khi đổi thuật toán/công thức (Android đặt tên file cache theo số này).
    static let version = 2

    struct Tone { var amp: Double; var delay: Double; var f0: Double; var fEnd: Double; var glide: Double; var tau: Double }
    struct Noise { var amp: Double; var delay: Double; var hp: Double; var lp: Double; var tau: Double }
    struct Recipe {
        var tones: [Tone]; var noises: [Noise]
        var attack: Double; var duration: Double; var outLP: Double; var peak: Double
    }

    private static func t(_ amp: Double, _ f0: Double, _ fEnd: Double, glide: Double = 0.008, tau: Double, delay: Double = 0) -> Tone {
        Tone(amp: amp, delay: delay, f0: f0, fEnd: fEnd, glide: glide, tau: tau)
    }
    private static func n(_ amp: Double, hp: Double = 120, lp: Double, tau: Double, delay: Double = 0) -> Noise {
        Noise(amp: amp, delay: delay, hp: hp, lp: lp, tau: tau)
    }

    /// Công thức gốc (phím chữ) của mỗi kiểu có sẵn. `custom` không có công thức.
    static func baseRecipe(_ s: KeySoundStyle) -> Recipe {
        switch s {
        case .subtle, .custom:
            return Recipe(tones: [t(1.0, 500, 360, tau: 0.007), t(0.24, 1050, 900, tau: 0.0025)],
                          noises: [n(0.30, lp: 1900, tau: 0.002)],
                          attack: 0.0016, duration: 0.032, outLP: 2600, peak: 0.80)
        case .wood:
            return Recipe(tones: [t(1.0, 640, 590, tau: 0.009), t(0.28, 640 * 2.72, 590 * 2.72, tau: 0.0026)],
                          noises: [n(0.30, lp: 2400, tau: 0.0014)],
                          attack: 0.0009, duration: 0.042, outLP: 3800, peak: 0.80)
        case .mechanical:
            return Recipe(tones: [t(1.0, 230, 180, glide: 0.010, tau: 0.012), t(0.55, 520, 450, tau: 0.0045),
                                  t(0.45, 300, 280, tau: 0.005, delay: 0.007)],
                          noises: [n(0.55, hp: 90, lp: 1300, tau: 0.0035), n(0.28, hp: 90, lp: 1300, tau: 0.002, delay: 0.007)],
                          attack: 0.0014, duration: 0.046, outLP: 2400, peak: 0.80)
        case .typewriter:
            return Recipe(tones: [t(0.35, 1050, 850, glide: 0.004, tau: 0.003), t(0.55, 260, 240, tau: 0.008)],
                          noises: [n(0.95, hp: 500, lp: 2600, tau: 0.0028), n(0.30, hp: 500, lp: 2600, tau: 0.0018, delay: 0.011)],
                          attack: 0.0008, duration: 0.044, outLP: 3200, peak: 0.85)
        case .bubble:
            return Recipe(tones: [t(1.0, 260, 720, glide: 0.009, tau: 0.009), t(0.08, 520, 1440, glide: 0.009, tau: 0.006)],
                          noises: [],
                          attack: 0.003, duration: 0.036, outLP: 3000, peak: 0.80)
        }
    }

    /// Công thức theo loại phím: xoá trầm hơn chút; phím chức năng trầm + dài hơn.
    static func recipe(_ s: KeySoundStyle, _ k: KeySoundKind) -> Recipe {
        var r = baseRecipe(s)
        let (pitch, decay, extra): (Double, Double, Double)
        switch k {
        case .letter: return r
        case .delete: (pitch, decay, extra) = (0.86, 1.0, 0)
        case .modifier: (pitch, decay, extra) = (0.74, 1.2, 0.006)
        }
        r.tones = r.tones.map { var x = $0; x.f0 *= pitch; x.fEnd *= pitch; x.tau *= decay; return x }
        r.noises = r.noises.map { var x = $0; x.lp *= pitch; x.tau *= decay; return x }
        r.duration += extra
        return r
    }

    static func seed(_ s: KeySoundStyle, _ k: KeySoundKind) -> UInt32 {
        let si = UInt32(KeySoundStyle.allCases.firstIndex(of: s) ?? 0)
        return 0x9E37_79B9 &* (si &+ 1) ^ (0x85EB_CA6B &* UInt32(k.rawValue + 1))
    }

    /// Mẫu mono Float −1…1 của một kiểu có sẵn (`custom` ⇒ dùng công thức mặc định).
    static func samples(_ s: KeySoundStyle, _ k: KeySoundKind) -> [Float] {
        render(recipe(s, k), seed: seed(s, k))
    }

    /// Tương thích: kiểu mặc định.
    static func samples(_ k: KeySoundKind) -> [Float] { samples(.defaultStyle, k) }

    /// 3 mẫu (chữ / xoá / chức năng) cho kiểu đã lưu. `custom` vắng/hỏng ⇒ kiểu mặc định.
    static func bank(_ raw: String?, custom: [Float]?) -> (style: KeySoundStyle, samples: [[Float]]) {
        let st = KeySoundStyle.resolve(raw, customAvailable: custom != nil)
        if st == .custom, let c = custom {
            return (st, KeySoundKind.allCases.map { KeySoundCustom.variant(c, $0) })
        }
        return (st, KeySoundKind.allCases.map { samples(st, $0) })
    }

    static func render(_ r: Recipe, seed: UInt32) -> [Float] {
        let sr = sampleRate
        let count = Int((r.duration * sr).rounded())
        var out = [Double](repeating: 0, count: count)
        // Tone
        for tn in r.tones {
            var phase = 0.0
            let start = Int((tn.delay * sr).rounded())
            if start >= count { continue }
            for i in start..<count {
                let tt = Double(i - start) / sr
                let f = tn.fEnd + (tn.f0 - tn.fEnd) * exp(-tt / tn.glide)
                phase += 2 * Double.pi * f / sr
                out[i] += tn.amp * sin(phase) * exp(-tt / tn.tau) * ramp(tt, r.attack)
            }
        }
        // Noise (mỗi lớp dòng xorshift riêng, lệch seed theo chỉ số lớp)
        for (li, nz) in r.noises.enumerated() {
            var state = seed ^ (0x2545_F491 &* UInt32(li + 1))
            if state == 0 { state = 0x1234_5678 }
            let hpA = exp(-2 * Double.pi * nz.hp / sr)
            let lpA = exp(-2 * Double.pi * nz.lp / sr)
            var hpIn = 0.0, hpOut = 0.0, lp1 = 0.0, lp2 = 0.0
            let start = Int((nz.delay * sr).rounded())
            if start >= count { continue }
            for i in start..<count {
                let tt = Double(i - start) / sr
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                let white = Double(state) / Double(UInt32.max) * 2 - 1
                let hp = hpA * (hpOut + white - hpIn)
                hpIn = white; hpOut = hp
                lp1 = (1 - lpA) * hp + lpA * lp1
                lp2 = (1 - lpA) * lp1 + lpA * lp2
                out[i] += nz.amp * 2.5 * lp2 * exp(-tt / nz.tau) * ramp(tt, r.attack)
            }
        }
        // Lọc thấp đầu ra + đóng mềm 3 ms.
        let oA = exp(-2 * Double.pi * r.outLP / sr)
        let dcA = exp(-2 * Double.pi * 40 / sr)   // chặn DC 40 Hz (loa nhỏ không phí công)
        var y = 0.0, dcIn = 0.0, dcOut = 0.0
        let rel = min(count, Int(0.003 * sr))
        var peak = 0.0
        for i in 0..<count {
            y = (1 - oA) * out[i] + oA * y
            dcOut = dcA * (dcOut + y - dcIn); dcIn = y
            var v = dcOut
            let fromEnd = count - 1 - i
            if fromEnd < rel { v *= 0.5 - 0.5 * cos(Double.pi * Double(fromEnd) / Double(rel)) }
            out[i] = v
            peak = max(peak, abs(v))
        }
        let norm = peak > 0 ? r.peak / peak : 0
        return out.map { Float($0 * norm) }
    }

    /// Mở raised-cosine 0→1 trong `a` giây (0 ⇒ luôn 1).
    private static func ramp(_ t: Double, _ a: Double) -> Double {
        if a <= 0 || t >= a { return 1 }
        return 0.5 - 0.5 * cos(Double.pi * t / a)
    }

    /// 0…100 % → biên độ; bình phương cho cảm giác to/nhỏ đều tay hơn tuyến tính.
    static func gain(forPercent p: Int) -> Float {
        let x = Float(max(0, min(100, p))) / 100
        return x * x
    }

    // MARK: đo đạc (test + ghi chú)

    /// Trọng tâm phổ (Hz) — trung bình tần số có trọng số biên độ DFT. Cao ⇒ chói.
    static func spectralCentroid(_ x: [Float], sampleRate sr: Double = sampleRate) -> Double {
        let n = x.count
        guard n > 1 else { return 0 }
        var num = 0.0, den = 0.0
        for k in 1...(n / 2) {
            var re = 0.0, im = 0.0
            let w = 2 * Double.pi * Double(k) / Double(n)
            for (i, v) in x.enumerated() { re += Double(v) * cos(w * Double(i)); im -= Double(v) * sin(w * Double(i)) }
            let mag = (re * re + im * im).squareRoot()
            num += mag * Double(k) * sr / Double(n); den += mag
        }
        return den > 0 ? num / den : 0
    }

    static func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    // MARK: WAV (16-bit PCM mono) — file âm tự chọn + bản nghe thử

    static func wav(_ s: [Float], sampleRate sr: Int = Int(sampleRate)) -> Data {
        var d = Data(capacity: 44 + s.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let data = UInt32(s.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + data); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(data)
        for x in s {
            let v = Int16(max(-1, min(1, x)) * 32767)
            u16(UInt16(bitPattern: v))
        }
        return d
    }

    /// Đọc WAV PCM 16-bit (mono/stereo → mono). nil nếu không phải định dạng đó.
    static func parseWav(_ d: Data) -> (samples: [Float], sampleRate: Double)? {
        let b = [UInt8](d)
        guard b.count >= 44, String(bytes: b[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: b[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var o = 12
        var channels = 0, rate = 0, bits = 0, fmtTag = 0
        while o + 8 <= b.count {
            let id = String(bytes: b[o..<o + 4], encoding: .ascii) ?? ""
            let size = u32(o + 4)
            let body = o + 8
            if id == "fmt ", body + 16 <= b.count {
                fmtTag = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if id == "data" {
                guard fmtTag == 1, bits == 16, channels >= 1, rate > 0 else { return nil }
                let end = min(b.count, body + size)
                let frames = (end - body) / (2 * channels)
                var out = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    var acc = 0.0
                    for c in 0..<channels {
                        let p = body + (f * channels + c) * 2
                        acc += Double(Int16(bitPattern: UInt16(u16(p))))
                    }
                    out[f] = Float(acc / Double(channels) / 32768)
                }
                return (out, Double(rate))
            }
            o = body + size + (size & 1)
        }
        return nil
    }
}

/// Âm tự chọn: xử lý thuần sau khi giải mã (app iOS: AVAudioFile; Android: MediaCodec).
/// Giống hệt Kotlin KeySoundCustom.
enum KeySoundCustom {
    static let maxDuration = 0.300       // ≤ 300 ms
    static let targetPeak: Float = 0.80  // đỉnh an toàn
    static let maxRMS = 0.22             // âm "đặc" (ù dài) bị hạ tiếp cho khỏi to
    static let fileName = "keysound-custom.wav"

    /// File âm tự chọn trong App Group (app ghi, bàn phím đọc — cần Full Access mới đọc được).
    /// KHÔNG nằm trong file sao lưu VietTelex (chỉ key `keySoundStyle` đi theo).
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex")?
            .appendingPathComponent(fileName)
    }

    /// Khoá bộ mẫu: kiểu + (nếu tự chọn) ngày sửa + cỡ file ⇒ app thay file là nạp lại.
    static func bankKey(style raw: String, customURL: URL?) -> String {
        guard raw == KeySoundStyle.custom.rawValue, let u = customURL,
              let a = try? FileManager.default.attributesOfItem(atPath: u.path) else { return raw }
        let m = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(raw)@\(m)#\((a[.size] as? NSNumber)?.intValue ?? 0)"
    }

    /// Đọc file âm tự chọn đã xử lý (WAV 44.1 kHz mono). nil ⇒ vắng/hỏng ⇒ dùng mặc định.
    static func load(_ url: URL?) -> [Float]? {
        guard let url, let d = try? Data(contentsOf: url), let w = KeySoundSynth.parseWav(d),
              !w.samples.isEmpty, w.samples.count <= Int(maxDuration * KeySoundSynth.sampleRate) + 16
        else { return nil }
        return resample(w.samples, from: w.sampleRate, to: KeySoundSynth.sampleRate)
    }

    enum Failure: Error, Equatable { case empty, silent }
    struct Result: Equatable {
        let samples: [Float]
        /// true ⇒ âm gốc dài hơn 300 ms, đã cắt (báo người dùng).
        let truncated: Bool
    }

    /// mono ở `rate` → 44.1 kHz, bỏ lặng đầu/cuối, cắt ≤ 300 ms, mở/đóng mềm, chuẩn hoá đỉnh.
    static func process(_ mono: [Float], sampleRate rate: Double) throws -> Result {
        guard !mono.isEmpty, rate > 0 else { throw Failure.empty }
        let x = resample(mono, from: rate, to: KeySoundSynth.sampleRate)
        let peak = x.reduce(Float(0)) { max($0, abs($1)) }
        guard peak >= 0.001 else { throw Failure.silent }
        let thr = max(peak * 0.05, 0.001)
        let sr = KeySoundSynth.sampleRate
        let first = x.firstIndex { abs($0) >= thr } ?? 0
        let last = x.lastIndex { abs($0) >= thr } ?? (x.count - 1)
        let start = max(0, first - Int(0.002 * sr))           // giữ 2 ms trước đỉnh mở
        let endAll = min(x.count, last + 1 + Int(0.010 * sr))  // giữ 10 ms đuôi
        let cap = Int(maxDuration * sr)
        let truncated = endAll - start > cap
        let end = min(endAll, start + cap)
        var y = Array(x[start..<end])
        // Mở 1 ms (bỏ "bụp" do cắt), đóng 5 ms (15 ms nếu bị cắt giữa chừng).
        let fin = min(y.count, Int(0.001 * sr))
        for i in 0..<fin { y[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fin))) }
        let fout = min(y.count, Int((truncated ? 0.015 : 0.005) * sr))
        for j in 0..<fout {
            let i = y.count - 1 - j
            y[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(j) / Double(fout)))
        }
        let p2 = y.reduce(Float(0)) { max($0, abs($1)) }
        guard p2 > 0 else { throw Failure.silent }
        var g = targetPeak / p2
        let r = KeySoundSynth.rms(y) * Double(g)
        if r > maxRMS { g *= Float(maxRMS / r) }
        return Result(samples: y.map { $0 * g }, truncated: truncated)
    }

    /// Nội suy tuyến tính (đủ cho click ngắn).
    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        if abs(from - to) < 0.5 || x.count < 2 { return x }
        let n = max(1, Int((Double(x.count) * to / from).rounded()))
        var out = [Float](repeating: 0, count: n)
        let step = from / to
        for i in 0..<n {
            let p = Double(i) * step
            let j = Int(p)
            if j >= x.count - 1 { out[i] = x[x.count - 1]; continue }
            let f = Float(p - Double(j))
            out[i] = x[j] * (1 - f) + x[j + 1] * f
        }
        return out
    }

    /// Mẫu phát cho từng loại phím từ âm tự chọn: chữ nguyên bản, xoá/chức năng nhỏ hơn chút.
    static func variant(_ s: [Float], _ k: KeySoundKind) -> [Float] {
        switch k {
        case .letter: return s
        case .delete: return s.map { $0 * 0.9 }
        case .modifier: return s.map { $0 * 0.82 }
        }
    }
}

/// Giới hạn tần suất nghe thử khi kéo thanh trượt: tối đa 1 lần / `interval` trong lúc kéo,
/// và luôn phát lúc thả (trừ khi vừa phát đúng giá trị đó rất gần). Thuần — test được.
struct PreviewThrottle {
    var interval: TimeInterval = 0.12
    private(set) var lastFire: TimeInterval = -.infinity
    private(set) var lastValue: Int?

    init(interval: TimeInterval = 0.12) { self.interval = interval }

    /// true ⇒ phát ngay bây giờ.
    mutating func shouldFire(value: Int, now: TimeInterval, final: Bool) -> Bool {
        let elapsed = now - lastFire
        let fire: Bool
        if final { fire = value != lastValue || elapsed >= interval }
        else { fire = elapsed >= interval && value != lastValue }
        if fire { lastFire = now; lastValue = value }
        return fire
    }
}
