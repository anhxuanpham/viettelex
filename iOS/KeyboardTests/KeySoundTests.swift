import XCTest
import AVFoundation

/// Âm thanh phím riêng (28/09/2026): TẮT ⇒ click hệ thống như cũ; BẬT ⇒ KeySound, không kêu đôi.
final class KeySoundTests: XCTestCase {
    override func tearDown() {
        KeyboardView.customSoundEnabled = false
        KeyboardView.debugLastClickRoute = nil
        super.tearDown()
    }

    func testSettingDefaultsAndClamp() {
        let s = KeyboardSettings()
        XCTAssertFalse(s.keySound)
        XCTAssertEqual(s.keySoundVolume, 50)
        let d = UserDefaults(suiteName: "vt-keysound-test")!
        d.removePersistentDomain(forName: "vt-keysound-test")
        d.set(true, forKey: "keySound")
        d.set(250, forKey: "keySoundVolume")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-keysound-test") }
        var l = KeyboardSettings.load()
        XCTAssertTrue(l.keySound)
        XCTAssertEqual(l.keySoundVolume, 100)
        d.set(-5, forKey: "keySoundVolume")
        l = KeyboardSettings.load()
        XCTAssertEqual(l.keySoundVolume, 0)
    }

    func testGainCurve() {
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 0), 0)
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 50), 0.25, accuracy: 1e-6)
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 100), 1)
        XCTAssertEqual(KeySoundSynth.gain(forPercent: 300), 1)
    }

    /// TẮT ⇒ đường click hệ thống; BẬT ⇒ đường riêng, KHÔNG gọi playInputClick.
    func testRouteOffSystemOnCustom() {
        KeyboardView.customSoundEnabled = false
        KeyboardView.clickLetter()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "system")
        KeyboardView.clickDelete()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "system")

        KeyboardView.customSoundEnabled = true
        KeyboardView.clickLetter()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:letter")
        KeyboardView.clickDelete()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:delete")
        KeyboardView.clickModifier()
        XCTAssertEqual(KeyboardView.debugLastClickRoute, "custom:modifier")
    }

    /// Chỉ bật đường riêng khi có cả setting lẫn Full Access.
    func testActivationNeedsFullAccess() {
        XCTAssertFalse(KeyboardViewController.customKeySoundActive(setting: false, fullAccess: true))
        XCTAssertFalse(KeyboardViewController.customKeySoundActive(setting: true, fullAccess: false))
        XCTAssertTrue(KeyboardViewController.customKeySoundActive(setting: true, fullAccess: true))
    }

    func testSamplesDeterministicNonEmptyDistinct() {
        for st in KeySoundStyle.presets {
            var all: [[Float]] = []
            for k in KeySoundKind.allCases {
                let a = KeySoundSynth.samples(st, k), b = KeySoundSynth.samples(st, k)
                XCTAssertEqual(a, b, "\(st)/\(k) phải tất định")
                XCTAssertGreaterThan(a.count, 1000)
                XCTAssertLessThan(a.count, 2700)                  // ≤ 60 ms ở 44.1 kHz
                let peak = a.map(abs).max() ?? 0
                XCTAssertEqual(Double(peak), KeySoundSynth.baseRecipe(st).peak, accuracy: 1e-4)
                XCTAssertEqual(a.first ?? 1, 0, accuracy: 1e-6)   // mở/đóng mềm — không "bụp"
                XCTAssertEqual(a.last ?? 1, 0, accuracy: 1e-6)
                let e = a.reduce(0) { $0 + $1 * $1 }
                let tail = a[(a.count / 2)...].reduce(0) { $0 + $1 * $1 }
                XCTAssertLessThan(tail / e, 0.08, "\(st)/\(k): năng lượng phải dồn đầu mẫu")
                all.append(a)
            }
            XCTAssertNotEqual(all[0], all[1]); XCTAssertNotEqual(all[1], all[2])
        }
        XCTAssertEqual(KeySoundSynth.samples(.letter), KeySoundSynth.samples(.subtle, .letter))
    }

    /// "Không chói" đo được: trọng tâm phổ thấp (bản cũ ~7 kHz), độ to trong khoảng dễ chịu.
    func testPresetsAreSoft() {
        for st in KeySoundStyle.presets {
            for k in KeySoundKind.allCases {
                let a = KeySoundSynth.samples(st, k)
                let c = KeySoundSynth.spectralCentroid(a)
                XCTAssertLessThan(c, 2500, "\(st)/\(k) centroid \(c)")
                if st == .subtle { XCTAssertLessThan(c, 1000, "mặc định phải trầm-êm: \(c)") }
                let r = KeySoundSynth.rms(a)
                XCTAssertGreaterThan(r, 0.05); XCTAssertLessThan(r, 0.30)
            }
        }
        // Mặc định ở 50 %: đỉnh thực ≤ 0.2 full-scale.
        let p50 = (KeySoundSynth.samples(.subtle, .letter).map(abs).max() ?? 0) * KeySoundSynth.gain(forPercent: 50)
        XCTAssertLessThanOrEqual(p50, 0.2 + 1e-6)
    }

    /// Checksum chung với Android (KeySoundTests.kt) — hai bên tổng hợp giống nhau.
    func testCrossPlatformChecksums() {
        for (st, want) in Self.goldenAbsSum {
            let s = KeySoundSynth.samples(st, .letter).reduce(0.0) { $0 + Double(abs($1)) }
            XCTAssertEqual(s, want, accuracy: 0.01, "\(st)")
        }
    }
    static let goldenAbsSum: [(KeySoundStyle, Double)] = [(.subtle, 169.1699), (.wood, 192.4240), (.mechanical, 239.0849), (.typewriter, 139.7659), (.bubble, 233.6785)]

    func testStyleResolveAndBankFallback() {
        XCTAssertEqual(KeySoundStyle.resolve(nil, customAvailable: true), .subtle)
        XCTAssertEqual(KeySoundStyle.resolve("xyz", customAvailable: true), .subtle)
        XCTAssertEqual(KeySoundStyle.resolve("wood", customAvailable: false), .wood)
        XCTAssertEqual(KeySoundStyle.resolve("custom", customAvailable: false), .subtle)
        XCTAssertEqual(KeySoundStyle.resolve("custom", customAvailable: true), .custom)
        let miss = KeySoundSynth.bank("custom", custom: nil)
        XCTAssertEqual(miss.style, .subtle)
        XCTAssertEqual(miss.samples[0], KeySoundSynth.samples(.subtle, .letter))
        let c: [Float] = [0, 0.5, -0.5, 0]
        let hit = KeySoundSynth.bank("custom", custom: c)
        XCTAssertEqual(hit.style, .custom)
        XCTAssertEqual(hit.samples[0], c)
        XCTAssertEqual(hit.samples.count, 3)
        // File vắng/hỏng ⇒ load nil ⇒ mặc định.
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent(KeySoundCustom.fileName)
        XCTAssertNil(KeySoundCustom.load(f))
        try? Data("not a wav".utf8).write(to: f)
        XCTAssertNil(KeySoundCustom.load(f))
        XCTAssertEqual(KeySoundSynth.bank("custom", custom: KeySoundCustom.load(f)).style, .subtle)
    }

    func testWavRoundTrip() {
        let s = KeySoundSynth.samples(.wood, .delete)
        let w = KeySoundSynth.wav(s)
        XCTAssertEqual(w.count, 44 + s.count * 2)
        let back = KeySoundSynth.parseWav(w)!
        XCTAssertEqual(back.sampleRate, 44_100)
        XCTAssertEqual(back.samples.count, s.count)
        for (a, b) in zip(s, back.samples) { XCTAssertEqual(a, b, accuracy: 1.0 / 16_000) }
        XCTAssertNil(KeySoundSynth.parseWav(Data([1, 2, 3])))
    }

    // MARK: âm tự chọn

    private func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Ghi file thử bằng AVAudioFile: stereo 48 kHz, lặng `lead` s rồi sine `tone` s biên độ `amp`.
    private func writeTestFile(_ url: URL, lead: Double, tone: Double, amp: Float, freq: Double = 440) throws {
        let rate = 48_000.0
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let n = Int((lead + tone) * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for c in 0..<2 {
            let p = buf.floatChannelData![c]
            for i in 0..<n {
                let t = Double(i) / rate - lead
                p[i] = t < 0 ? 0 : amp * Float(sin(2 * .pi * freq * t))
            }
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false]
        try? FileManager.default.removeItem(at: url)
        let f = try AVAudioFile(forWriting: url, settings: settings)
        try f.write(from: buf)
    }

    /// File dài + to + có lặng đầu ⇒ bỏ lặng, cắt ≤ 300 ms (báo cắt), đỉnh/RMS an toàn.
    func testCustomImportTrimsCapsNormalizes() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let src = d.appendingPathComponent("long.wav"), dst = d.appendingPathComponent(KeySoundCustom.fileName)
        try writeTestFile(src, lead: 0.25, tone: 0.8, amp: 1.0)
        let o = try KeySoundImport.importFile(src, to: dst)
        XCTAssertTrue(o.truncated)
        XCTAssertLessThanOrEqual(o.duration, 0.3 + 1e-3)
        XCTAssertGreaterThan(o.duration, 0.29)
        let s = try XCTUnwrap(KeySoundCustom.load(dst))
        let peak = s.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, KeySoundCustom.targetPeak + 1e-3)
        XCTAssertLessThanOrEqual(KeySoundSynth.rms(s), KeySoundCustom.maxRMS + 1e-3)
        // Lặng đầu đã bỏ: 5 ms đầu đã có tiếng.
        XCTAssertGreaterThan(s[..<220].map(abs).max() ?? 0, 0.05)
        XCTAssertEqual(s.last ?? 1, 0, accuracy: 1e-3)   // đóng mềm
        // Khoá bộ mẫu đổi khi file đổi ⇒ bàn phím nạp lại.
        let k1 = KeySoundCustom.bankKey(style: "custom", customURL: dst)
        try writeTestFile(src, lead: 0, tone: 0.05, amp: 0.05)
        try KeySoundImport.importFile(src, to: dst)
        XCTAssertNotEqual(k1, KeySoundCustom.bankKey(style: "custom", customURL: dst))
        XCTAssertEqual(KeySoundCustom.bankKey(style: "wood", customURL: dst), "wood")
    }

    /// Click ngắn + nhỏ ⇒ không cắt, được nâng lên đỉnh chuẩn.
    func testCustomImportShortQuietIsBoosted() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let src = d.appendingPathComponent("tick.wav"), dst = d.appendingPathComponent(KeySoundCustom.fileName)
        try writeTestFile(src, lead: 0.02, tone: 0.03, amp: 0.05, freq: 300)
        let o = try KeySoundImport.importFile(src, to: dst)
        XCTAssertFalse(o.truncated)
        XCTAssertLessThan(o.duration, 0.06)
        let s = try XCTUnwrap(KeySoundCustom.load(dst))
        // Nâng từ 0.05 lên; sine đặc ⇒ trần RMS (độ to ngang các kiểu có sẵn) giữ đỉnh dưới 0.8.
        let peak = s.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.25); XCTAssertLessThanOrEqual(peak, KeySoundCustom.targetPeak + 1e-3)
        XCTAssertEqual(KeySoundSynth.rms(s), KeySoundCustom.maxRMS, accuracy: 0.01)
        XCTAssertEqual(KeySoundSynth.bank("custom", custom: s).style, .custom)
    }

    func testCustomImportErrors() throws {
        let d = tmpDir(); defer { try? FileManager.default.removeItem(at: d) }
        let silent = d.appendingPathComponent("silent.wav")
        try writeTestFile(silent, lead: 0.5, tone: 0, amp: 0)
        XCTAssertThrowsError(try KeySoundImport.importFile(silent, to: d.appendingPathComponent("o.wav"))) {
            XCTAssertEqual($0 as? KeySoundImport.Failure, .silent)
        }
        let junk = d.appendingPathComponent("junk.mp3")
        try Data(repeating: 7, count: 4000).write(to: junk)
        XCTAssertThrowsError(try KeySoundImport.importFile(junk, to: d.appendingPathComponent("o.wav"))) {
            XCTAssertEqual($0 as? KeySoundImport.Failure, .unreadable)
        }
        XCTAssertThrowsError(try KeySoundImport.importFile(junk, to: nil)) {
            XCTAssertEqual($0 as? KeySoundImport.Failure, .noStorage)
        }
        XCTAssertThrowsError(try KeySoundCustom.process([], sampleRate: 44_100))
    }

    func testResampleLength() {
        let x = [Float](repeating: 0.5, count: 48_000)
        XCTAssertEqual(KeySoundCustom.resample(x, from: 48_000, to: 44_100).count, 44_100)
        XCTAssertEqual(KeySoundCustom.resample(x, from: 44_100, to: 44_100).count, 48_000)
    }

    // MARK: nghe thử + pin

    func testPreviewThrottle() {
        var t = PreviewThrottle(interval: 0.12)
        XCTAssertTrue(t.shouldFire(value: 50, now: 0, final: false))
        XCTAssertFalse(t.shouldFire(value: 55, now: 0.05, final: false))   // quá sớm
        XCTAssertTrue(t.shouldFire(value: 55, now: 0.13, final: false))
        XCTAssertFalse(t.shouldFire(value: 55, now: 0.30, final: false))   // cùng giá trị khi kéo
        XCTAssertFalse(t.shouldFire(value: 55, now: 0.20, final: true))    // vừa phát đúng giá trị này
        XCTAssertTrue(t.shouldFire(value: 60, now: 0.21, final: true))     // thả ở giá trị mới ⇒ luôn phát
        XCTAssertTrue(t.shouldFire(value: 60, now: 0.50, final: true))     // thả sau lâu ⇒ phát lại
    }

    func testIdleDecision() {
        XCTAssertTrue(KeySound.idleDecision(now: 20, lastPlay: 10, timeout: 8).stop)
        let d = KeySound.idleDecision(now: 15, lastPlay: 10, timeout: 8)
        XCTAssertFalse(d.stop); XCTAssertEqual(d.recheck, 3, accuracy: 1e-9)
        XCTAssertEqual(KeySound.idleDecision(now: 17.99, lastPlay: 10, timeout: 8).recheck, 0.05, accuracy: 1e-9)
    }

    /// Nghỉ sau idle ⇒ engine dừng; phím kế tiếp khởi động lại nền (không chặn), rồi phát được.
    func testIdlePauseAndRestart() throws {
        let ks = KeySound.shared
        ks.debugWant(true)
        defer { ks.debugWant(false); ks.stopNow() }
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        XCTAssertTrue(ks.isRunning)
        ks.debugSetLastPlay(ago: 100)
        ks.debugIdleCheck()
        XCTAssertFalse(ks.isRunning, "quá idleTimeout ⇒ engine nghỉ")
        let t0 = CACurrentMediaTime()
        _ = ks.play(.letter)                           // không chặn: chỉ hẹn khởi động lại
        XCTAssertLessThan(CACurrentMediaTime() - t0, 0.005)
        let deadline = Date().addingTimeInterval(3)
        while !ks.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(ks.isRunning)
        XCTAssertTrue(ks.play(.delete))
    }

    func testStyleSettingLoad() {
        XCTAssertEqual(KeyboardSettings().keySoundStyle, "subtle")
        let d = UserDefaults(suiteName: "vt-keysound-style")!
        d.removePersistentDomain(forName: "vt-keysound-style")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-keysound-style") }
        d.set("mechanical", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "mechanical")
        d.set("loud", forKey: "keySoundStyle")
        XCTAssertEqual(KeyboardSettings.load().keySoundStyle, "subtle")
    }

    /// Sao lưu: 2 key đi qua khứ hồi; âm lượng ngoài phạm vi bị kẹp 0…100.
    func testBackupRoundTripAndClamp() throws {
        let p = BackupPayload(createdAt: nil, platform: "ios",
                              settings: ["keySound": .bool(true), "keySoundVolume": .int(35)],
                              shortcuts: [:], templates: nil, learnedWords: nil)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(p)).settings, p.settings)
        let raw = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySound":true,"keySoundVolume":250}}"#
        let back = try BackupCodec.decode(Data(raw.utf8))
        XCTAssertEqual(back.settings?["keySoundVolume"], .int(100))
        XCTAssertEqual(back.settings?["keySound"], .bool(true))
        let st = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySoundStyle":"bubble"}}"#
        XCTAssertEqual(try BackupCodec.decode(Data(st.utf8)).settings?["keySoundStyle"], .string("bubble"))
        let bad = #"{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"android","settings":{"keySoundStyle":"loud"}}"#
        XCTAssertNil(try BackupCodec.decode(Data(bad.utf8)).settings?["keySoundStyle"])
    }

    /// Đo trên simulator: chi phí gọi play() ở đường nóng + độ trễ output engine báo.
    func testEngineStartAndPlayCost() throws {
        let ks = KeySound.shared
        ks.debugWant(true)
        defer { ks.debugWant(false); ks.stopNow() }
        let t0 = CACurrentMediaTime()
        guard ks.startNow() else { throw XCTSkip("không có audio output trên máy test") }
        let startMs = (CACurrentMediaTime() - t0) * 1000
        _ = ks.play(.letter)                                   // hâm nóng
        let n = 200
        let t1 = CACurrentMediaTime()
        for i in 0..<n { XCTAssertTrue(ks.play(KeySoundKind(rawValue: i % 3)!)) }
        let perUs = (CACurrentMediaTime() - t1) / Double(n) * 1e6
        let s = AVAudioSession.sharedInstance()
        print(String(format: "KEYSOUND start=%.1fms play=%.1fµs io=%.1fms out=%.1fms",
                     startMs, perUs, s.ioBufferDuration * 1000, s.outputLatency * 1000))
        XCTAssertLessThan(perUs, 1000)   // đường nóng < 1 ms/lần
    }
}
