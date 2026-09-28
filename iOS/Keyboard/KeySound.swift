// KeySound — âm phím RIÊNG của VietTelex (setting "Âm thanh phím", mặc định TẮT).
//
// TẮT ⇒ giữ nguyên hành vi cũ: UIDevice.playInputClick (theo Cài đặt → Âm thanh →
// Tiếng bấm bàn phím), không dựng engine, không tốn gì thêm.
// BẬT ⇒ phát 3 tiếng click tự tổng hợp (chữ / xoá / phím chức năng như stock) theo âm
// lượng thanh trượt, KHÔNG kèm click hệ thống (không kêu đôi).
//
// - Mẫu âm: tổng hợp tất định lúc chạy (sine tắt dần + nhiễu lọc, ~25–40 ms) — không có
//   file âm thanh bên thứ ba. Thuật toán y hệt android/keyboard/.../KeySoundSynth.kt.
// - Độ trễ: AVAudioEngine + 1 AVAudioPlayerNode/loại, buffer PCM dựng sẵn; bấm phím chỉ
//   scheduleBuffer(.interrupts) — không cấp phát, không chặn main (lock.try()).
// - Audio session .ambient (+ mixWithOthers): không ngắt nhạc đang phát, TÔN TRỌNG gạt
//   im lặng — như click bàn phím stock (iOS 17+ im khi bật chế độ im lặng).
// - Cần Toàn quyền Truy cập: không có Full Access, audio của extension không phát được ổn
//   định ⇒ controller chỉ bật đường này khi hasFullAccess, thiếu thì quay về click hệ thống.
// - Vòng đời: engine dựng/khởi động trên queue riêng khi bàn phím hiện (setting BẬT),
//   dừng + nhả khi ẩn hoặc thiếu RAM.
import AVFoundation

enum KeySoundKind: Int, CaseIterable {
    case letter, delete, modifier
}

/// Tổng hợp mẫu click (thuần, tất định — test được). Giống hệt bản Kotlin.
enum KeySoundSynth {
    static let sampleRate = 44_100.0

    struct Voice {
        let freq: Double       // tần số "thân" click (Hz)
        let toneTau: Double    // hằng số tắt dần của tone (s)
        let noiseTau: Double   // hằng số tắt dần của nhiễu (s)
        let noiseMix: Double   // tỉ lệ nhiễu so với tone
        let duration: Double   // độ dài mẫu (s)
        let seed: UInt32
    }

    static func voice(_ k: KeySoundKind) -> Voice {
        switch k {
        case .letter:   return Voice(freq: 1850, toneTau: 0.0045, noiseTau: 0.0022, noiseMix: 0.55, duration: 0.028, seed: 0x1234_5678)
        case .delete:   return Voice(freq: 1300, toneTau: 0.0055, noiseTau: 0.0028, noiseMix: 0.50, duration: 0.032, seed: 0x2345_6789)
        case .modifier: return Voice(freq: 900, toneTau: 0.0075, noiseTau: 0.0035, noiseMix: 0.45, duration: 0.040, seed: 0x3456_789A)
        }
    }

    /// Mẫu mono Float −1…1, đỉnh chuẩn hoá 0.9.
    static func samples(_ k: KeySoundKind) -> [Float] {
        let v = voice(k)
        let n = Int((v.duration * sampleRate).rounded())
        var out = [Double](repeating: 0, count: n)
        var state = v.seed
        // Nhiễu trắng → high-pass một cực (bỏ ù) → low-pass một cực (bỏ xì) ≈ dải 1–6 kHz.
        let hpA = exp(-2 * Double.pi * 1000 / sampleRate)
        let lpA = exp(-2 * Double.pi * 6000 / sampleRate)
        var hpPrevIn = 0.0, hpPrevOut = 0.0, lp = 0.0
        let attack = Int(0.0004 * sampleRate)          // 0.4 ms mở — bớt "bụp"
        let release = Int(0.002 * sampleRate)          // 2 ms đóng — không vấp cuối mẫu
        var peak = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            state ^= state << 13; state ^= state >> 17; state ^= state << 5   // xorshift32
            let white = Double(state) / Double(UInt32.max) * 2 - 1
            let hp = hpA * (hpPrevOut + white - hpPrevIn)
            hpPrevIn = white; hpPrevOut = hp
            lp = (1 - lpA) * hp + lpA * lp
            let tone = sin(2 * Double.pi * v.freq * t) * exp(-t / v.toneTau)
                + 0.35 * sin(2 * Double.pi * v.freq * 2.03 * t) * exp(-t / (v.toneTau * 0.6))
            var s = tone + v.noiseMix * 3 * lp * exp(-t / v.noiseTau)
            if i < attack { s *= Double(i) / Double(attack) }
            if i >= n - release { s *= Double(n - 1 - i) / Double(release) }
            out[i] = s
            peak = max(peak, abs(s))
        }
        let norm = peak > 0 ? 0.9 / peak : 0
        return out.map { Float($0 * norm) }
    }

    /// 0…100 % → biên độ; bình phương cho cảm giác to/nhỏ đều tay hơn tuyến tính.
    static func gain(forPercent p: Int) -> Float {
        let x = Float(max(0, min(100, p))) / 100
        return x * x
    }
}

final class KeySound {
    static let shared = KeySound()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "vt.keysound", qos: .userInteractive)
    // Toàn bộ dưới đây chỉ đụng khi giữ lock.
    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var running = false
    private var wanted = false
    private var gain: Float = KeySoundSynth.gain(forPercent: 50)
    private var configObserver: NSObjectProtocol?

    func setVolume(percent: Int) {
        let g = KeySoundSynth.gain(forPercent: percent)
        lock.lock(); defer { lock.unlock() }
        gain = g
        engine?.mainMixerNode.outputVolume = g
    }

    /// Dựng + khởi động engine NỀN (không chặn lúc bàn phím hiện).
    func prepare() {
        lock.lock(); wanted = true; let ready = running; lock.unlock()
        if ready { return }
        queue.async { [self] in _ = startNow() }
    }

    /// Dừng + nhả engine/buffer (ẩn bàn phím, thiếu RAM, tắt setting).
    func shutdown() {
        lock.lock(); wanted = false; let has = engine != nil; lock.unlock()
        guard has else { return }
        queue.async { [self] in stopNow() }
    }

    /// Phát ngay (gọi ở touch-down trên main). false = engine chưa sẵn sàng (bỏ tiếng này,
    /// KHÔNG chờ). Không cấp phát ở đường nóng.
    @discardableResult
    func play(_ kind: KeySoundKind) -> Bool {
        guard lock.try() else { return false }   // queue đang start/stop — bỏ 1 tiếng, không chặn main
        defer { lock.unlock() }
        guard running, let e = engine else { return false }
        guard e.isRunning else {
            // Bị ngắt (cuộc gọi, Siri…) hoặc đổi route: dựng lại nền, tiếng này bỏ.
            running = false
            queue.async { [self] in _ = startNow() }
            return false
        }
        nodes[kind.rawValue].scheduleBuffer(buffers[kind.rawValue], at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// Đồng bộ (queue nền hoặc test). true = engine chạy.
    @discardableResult
    func startNow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard wanted else { return false }
        if running, engine?.isRunning == true { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            let e = engine ?? AVAudioEngine()
            if engine == nil {
                guard let fmt = AVAudioFormat(standardFormatWithSampleRate: KeySoundSynth.sampleRate, channels: 1)
                else { return false }
                var ns: [AVAudioPlayerNode] = [], bs: [AVAudioPCMBuffer] = []
                for k in KeySoundKind.allCases {
                    let s = KeySoundSynth.samples(k)
                    guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count)),
                          let ch = b.floatChannelData?[0] else { return false }
                    s.withUnsafeBufferPointer { ch.update(from: $0.baseAddress!, count: s.count) }
                    b.frameLength = AVAudioFrameCount(s.count)
                    let node = AVAudioPlayerNode()
                    e.attach(node)
                    e.connect(node, to: e.mainMixerNode, format: fmt)
                    ns.append(node); bs.append(b)
                }
                nodes = ns; buffers = bs; engine = e
                configObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange, object: e, queue: nil) { [weak self] _ in
                    // Không đụng lock ở đây (có thể đang ở trong start/stop) — dồn về queue.
                    guard let self else { return }
                    self.queue.async { _ = self.startNow() }
                }
            }
            e.mainMixerNode.outputVolume = gain
            e.prepare()
            try e.start()
            for n in nodes { n.play() }
            running = true
            #if DEBUG
            NSLog("VTKB keysound start io=%.1fms out=%.1fms", session.ioBufferDuration * 1000, session.outputLatency * 1000)
            #endif
            return true
        } catch {
            TouchLog.write("keysound: không khởi động được engine \(error)")
            running = false
            return false
        }
    }

    func stopNow() {
        lock.lock(); defer { lock.unlock() }
        guard !wanted, engine != nil else { return }   // prepare() lại kịp ⇒ giữ engine
        running = false
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        for n in nodes { n.stop() }
        engine?.stop()
        engine = nil; nodes = []; buffers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    #if DEBUG
    /// Test: bật cờ muốn chạy mà không qua queue.
    func debugWant(_ on: Bool) { lock.lock(); wanted = on; lock.unlock() }
    #endif
}
