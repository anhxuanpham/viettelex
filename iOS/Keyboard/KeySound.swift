// KeySound — âm phím RIÊNG của VietTelex (setting "Âm thanh phím", mặc định TẮT).
//
// TẮT ⇒ giữ nguyên hành vi cũ: UIDevice.playInputClick (theo Cài đặt → Âm thanh →
// Tiếng bấm bàn phím), không dựng engine, không tốn gì thêm.
// BẬT ⇒ phát 3 tiếng (chữ / xoá / phím chức năng như stock) theo KIỂU đã chọn
// (`keySoundStyle`: 5 kiểu tổng hợp + âm tự chọn) và âm lượng thanh trượt, KHÔNG kèm
// click hệ thống (không kêu đôi).
//
// - Mẫu âm: Shared/KeySoundSynth.swift (tất định, dùng chung với app để nghe thử). Âm tự
//   chọn: WAV đã xử lý trong App Group (KeySoundCustom.fileURL) — vắng/hỏng ⇒ "Nhẹ nhàng".
// - Độ trễ: AVAudioEngine + 1 AVAudioPlayerNode/loại, buffer PCM dựng sẵn; bấm phím chỉ
//   scheduleBuffer(.interrupts) — không cấp phát, không chặn main (lock.try()).
// - Audio session .ambient (+ mixWithOthers): không ngắt nhạc đang phát, TÔN TRỌNG gạt
//   im lặng — như click bàn phím stock (iOS 17+ im khi bật chế độ im lặng).
// - Cần Toàn quyền Truy cập: không có Full Access, audio của extension không phát được ổn
//   định ⇒ controller chỉ bật đường này khi hasFullAccess, thiếu thì quay về click hệ thống.
// - PIN (Phil 28/09): engine đang chạy = phần cứng audio render liên tục (~vài mW) dù im.
//   ⇒ NGHỈ sau `idleTimeout` (8 s) không bấm: engine.pause() + nhả session. Lần bấm kế
//   tiếp khởi động lại NỀN (không chặn main); tiếng của lần bấm đó chỉ phát nếu engine
//   sẵn sàng trong `lateWindow` (40 ms), trễ hơn thì bỏ (thà im một tiếng còn hơn kêu muộn).
//   Kiểm tra nghỉ là một asyncAfter một lần (hẹn lại theo lastPlay) — không timer lặp,
//   bấm phím không hẹn gì thêm.
// - Vòng đời: engine dựng/khởi động trên queue riêng khi bàn phím hiện (setting BẬT),
//   dừng + nhả khi ẩn hoặc thiếu RAM.
import AVFoundation

final class KeySound {
    static let shared = KeySound()

    /// Không bấm quá chừng này ⇒ tạm dừng engine (pin). Test chỉnh nhỏ lại.
    var idleTimeout: TimeInterval = 8
    /// Bấm lúc engine đang nghỉ: khởi động xong trong khoảng này thì vẫn phát tiếng đó.
    static let lateWindow: TimeInterval = 0.040

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "vt.keysound", qos: .userInteractive)
    // Toàn bộ dưới đây chỉ đụng khi giữ lock.
    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var running = false
    private var wanted = false
    private var restarting = false
    private var pending: (kind: KeySoundKind, at: TimeInterval)?
    private var lastPlay: TimeInterval = 0
    private var idleCheckScheduled = false
    private var gain: Float = KeySoundSynth.gain(forPercent: 50)
    private var configObserver: NSObjectProtocol?
    /// Kiểu mong muốn (giá trị lưu) + khoá bộ mẫu đang dựng (kiểu + mtime file tự chọn).
    private var styleRaw = KeySoundStyle.defaultStyle.rawValue
    private var customURL: URL? = KeySoundCustom.fileURL
    private var builtKey: String?
    /// Kiểu thật sự đang phát (custom thiếu file ⇒ subtle) — log/test.
    private(set) var activeStyle: KeySoundStyle = .defaultStyle

    func setVolume(percent: Int) {
        let g = KeySoundSynth.gain(forPercent: percent)
        lock.lock(); defer { lock.unlock() }
        gain = g
        engine?.mainMixerNode.outputVolume = g
    }

    /// Chọn kiểu (giá trị `keySoundStyle`). Đổi ⇒ bộ mẫu dựng lại ở lần khởi động kế tiếp.
    func setStyle(_ raw: String, customURL: URL? = KeySoundCustom.fileURL) {
        lock.lock(); defer { lock.unlock() }
        styleRaw = raw
        self.customURL = customURL
    }

    /// Dựng + khởi động engine NỀN (không chặn lúc bàn phím hiện).
    func prepare() {
        lock.lock()
        wanted = true
        let ready = running && builtKey == KeySoundCustom.bankKey(style: styleRaw, customURL: customURL)
        lock.unlock()
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
    /// KHÔNG chờ — trừ khi khởi động lại kịp trong lateWindow). Không cấp phát ở đường nóng.
    @discardableResult
    func play(_ kind: KeySoundKind) -> Bool {
        guard lock.try() else { return false }   // queue đang start/stop — bỏ 1 tiếng, không chặn main
        defer { lock.unlock() }
        let now = CACurrentMediaTime()
        lastPlay = now
        guard wanted else { return false }
        guard running, let e = engine, e.isRunning else {
            // Nghỉ (pin), bị ngắt (cuộc gọi, Siri…) hoặc đổi route: dựng lại nền.
            running = false
            pending = (kind, now)
            if !restarting {
                restarting = true
                queue.async { [self] in _ = startNow() }
            }
            return false
        }
        nodes[kind.rawValue].scheduleBuffer(buffers[kind.rawValue], at: nil, options: .interrupts, completionHandler: nil)
        return true
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// Quyết định nghỉ (thuần — test được): true ⇒ dừng ngay; false ⇒ hẹn kiểm lại sau `recheck` giây.
    static func idleDecision(now: TimeInterval, lastPlay: TimeInterval, timeout: TimeInterval) -> (stop: Bool, recheck: TimeInterval) {
        let idle = now - lastPlay
        if idle >= timeout { return (true, 0) }
        return (false, max(0.05, timeout - idle))
    }

    /// Đồng bộ (queue nền hoặc test). true = engine chạy.
    @discardableResult
    func startNow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { restarting = false }
        guard wanted else { pending = nil; return false }
        let key = KeySoundCustom.bankKey(style: styleRaw, customURL: customURL)
        if running, engine?.isRunning == true, builtKey == key { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: KeySoundSynth.sampleRate, channels: 1)
            else { return false }
            let e = engine ?? AVAudioEngine()
            if engine == nil {
                var ns: [AVAudioPlayerNode] = []
                for _ in KeySoundKind.allCases {
                    let node = AVAudioPlayerNode()
                    e.attach(node)
                    e.connect(node, to: e.mainMixerNode, format: fmt)
                    ns.append(node)
                }
                nodes = ns; engine = e
                configObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange, object: e, queue: nil) { [weak self] _ in
                    // Không đụng lock ở đây (có thể đang ở trong start/stop) — dồn về queue.
                    guard let self else { return }
                    self.queue.async { _ = self.startNow() }
                }
            }
            if builtKey != key {
                let custom = styleRaw == KeySoundStyle.custom.rawValue ? KeySoundCustom.load(customURL) : nil
                let bank = KeySoundSynth.bank(styleRaw, custom: custom)
                var bs: [AVAudioPCMBuffer] = []
                for s in bank.samples {
                    guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count)),
                          let ch = b.floatChannelData?[0] else { return false }
                    s.withUnsafeBufferPointer { ch.update(from: $0.baseAddress!, count: s.count) }
                    b.frameLength = AVAudioFrameCount(s.count)
                    bs.append(b)
                }
                buffers = bs; builtKey = key; activeStyle = bank.style
                if bank.style.rawValue != styleRaw { TouchLog.write("keysound: \(styleRaw) thiếu file → \(bank.style.rawValue)") }
            }
            e.mainMixerNode.outputVolume = gain
            if !e.isRunning {
                e.prepare()
                try e.start()
            }
            for n in nodes where !n.isPlaying { n.play() }
            running = true
            let now = CACurrentMediaTime()
            if let p = pending, now - p.at <= Self.lateWindow {
                nodes[p.kind.rawValue].scheduleBuffer(buffers[p.kind.rawValue], at: nil, options: .interrupts, completionHandler: nil)
            }
            pending = nil
            lastPlay = now   // khởi động = hoạt động: đếm 8 s nghỉ từ đây
            scheduleIdleCheckLocked(after: idleTimeout)
            #if DEBUG
            NSLog("VTKB keysound start style=%@ io=%.1fms out=%.1fms", activeStyle.rawValue, session.ioBufferDuration * 1000, session.outputLatency * 1000)
            #endif
            return true
        } catch {
            TouchLog.write("keysound: không khởi động được engine \(error)")
            running = false
            pending = nil
            return false
        }
    }

    private func scheduleIdleCheckLocked(after delay: TimeInterval) {
        guard !idleCheckScheduled else { return }
        idleCheckScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.idleCheck() }
    }

    private func idleCheck() {
        lock.lock(); defer { lock.unlock() }
        idleCheckScheduled = false
        guard running, let e = engine else { return }
        let d = Self.idleDecision(now: CACurrentMediaTime(), lastPlay: lastPlay, timeout: idleTimeout)
        if !d.stop { scheduleIdleCheckLocked(after: d.recheck); return }
        // Nghỉ: giữ node/buffer (khởi động lại nhanh), dừng phần cứng + nhả session.
        running = false
        e.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #if DEBUG
        NSLog("VTKB keysound idle pause")
        #endif
    }

    func stopNow() {
        lock.lock(); defer { lock.unlock() }
        guard !wanted, engine != nil else { return }   // prepare() lại kịp ⇒ giữ engine
        running = false
        pending = nil
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        for n in nodes { n.stop() }
        engine?.stop()
        engine = nil; nodes = []; buffers = []; builtKey = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    #if DEBUG
    /// Test: bật cờ muốn chạy mà không qua queue.
    func debugWant(_ on: Bool) { lock.lock(); wanted = on; lock.unlock() }
    /// Test: chạy kiểm tra nghỉ ngay (đồng bộ).
    func debugIdleCheck() { idleCheck() }
    /// Test: giả lập lần bấm cuối cách đây `ago` giây.
    func debugSetLastPlay(ago: TimeInterval) { lock.lock(); lastPlay = CACurrentMediaTime() - ago; lock.unlock() }
    #endif
}
