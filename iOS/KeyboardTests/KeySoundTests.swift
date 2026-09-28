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
        var all: [[Float]] = []
        for k in KeySoundKind.allCases {
            let a = KeySoundSynth.samples(k), b = KeySoundSynth.samples(k)
            XCTAssertEqual(a, b, "\(k) phải tất định")
            XCTAssertGreaterThan(a.count, 1000)
            XCTAssertLessThan(a.count, 2000)             // ≤ 45 ms ở 44.1 kHz
            let peak = a.map(abs).max() ?? 0
            XCTAssertEqual(peak, 0.9, accuracy: 1e-4)
            XCTAssertEqual(a.first ?? 1, 0, accuracy: 1e-6)   // mở/đóng mềm — không "bụp"
            XCTAssertEqual(a.last ?? 1, 0, accuracy: 1e-6)
            all.append(a)
        }
        XCTAssertNotEqual(all[0], all[1]); XCTAssertNotEqual(all[1], all[2])
        // Năng lượng tập trung đầu mẫu (transient): nửa sau < 5 % năng lượng.
        for a in all {
            let e = a.reduce(0) { $0 + $1 * $1 }
            let tail = a[(a.count / 2)...].reduce(0) { $0 + $1 * $1 }
            XCTAssertLessThan(tail / e, 0.05)
        }
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
