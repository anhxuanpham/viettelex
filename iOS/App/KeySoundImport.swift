// Âm phím tự chọn + nghe/rung thử trong app (Phím & cử chỉ → Phản hồi khi chạm).
//
// Nhập: .fileImporter (m4a/mp3/wav/caf/aiff…) → AVAudioFile giải mã (tối đa 10 s đầu) →
// trộn mono → KeySoundCustom.process (44.1 kHz, bỏ lặng đầu/cuối, cắt ≤ 300 ms, mở/đóng
// mềm, chuẩn hoá đỉnh 0.8 + trần RMS) → WAV 16-bit mono (~26 KB) trong App Group
// (KeySoundCustom.fileURL). Bàn phím nạp lười khi kiểu = custom; vắng/hỏng ⇒ "Nhẹ nhàng".
// File KHÔNG vào file sao lưu (chỉ key keySoundStyle).
//
// Nghe thử: AVAudioPlayer từ đúng bộ mẫu bàn phím dùng (KeySoundSynth.bank), âm lượng theo
// cùng đường cong. Session .ambient + mixWithOthers GIỐNG bàn phím ⇒ không ngắt nhạc, và
// IM khi gạt chế độ im lặng — cố ý: nghe thử phải đúng cảm giác lúc gõ (gạt im lặng thì
// bàn phím cũng im); chú thích dưới thanh trượt nhắc điều này.
import AVFoundation
import UIKit

enum KeySoundImport {
    enum Failure: LocalizedError, Equatable {
        case unreadable, tooLarge, silent, noStorage
        var errorDescription: String? {
            switch self {
            case .unreadable: return L("Không đọc được file âm thanh này. Hãy thử m4a, mp3, wav, caf hoặc aiff.")
            case .tooLarge: return L("File quá lớn (tối đa 30 MB).")
            case .silent: return L("File không có tiếng (toàn im lặng).")
            case .noStorage: return L("Không lưu được âm (thiếu App Group).")
            }
        }
    }
    struct Outcome: Equatable { let duration: Double; let truncated: Bool }

    static let maxBytes = 30 * 1024 * 1024
    static let maxDecodeSeconds = 10.0

    /// Giải mã + xử lý + ghi `dest` (nguyên tử). Ném Failure.
    @discardableResult
    static func importFile(_ src: URL, to dest: URL? = KeySoundCustom.fileURL) throws -> Outcome {
        guard let dest else { throw Failure.noStorage }
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        if let size = (try? src.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes { throw Failure.tooLarge }
        let (mono, rate) = try decode(src)
        let r: KeySoundCustom.Result
        do { r = try KeySoundCustom.process(mono, sampleRate: rate) } catch { throw Failure.silent }
        try KeySoundSynth.wav(r.samples).write(to: dest, options: .atomic)
        return Outcome(duration: Double(r.samples.count) / KeySoundSynth.sampleRate, truncated: r.truncated)
    }

    /// AVAudioFile → mono Float ở tần số gốc (≤ 10 s đầu).
    static func decode(_ url: URL) throws -> ([Float], Double) {
        let f: AVAudioFile
        do { f = try AVAudioFile(forReading: url) } catch { throw Failure.unreadable }
        let fmt = f.processingFormat
        let frames = AVAudioFrameCount(min(f.length, AVAudioFramePosition(fmt.sampleRate * maxDecodeSeconds)))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { throw Failure.unreadable }
        do { try f.read(into: buf, frameCount: frames) } catch { throw Failure.unreadable }
        guard let ch = buf.floatChannelData else { throw Failure.unreadable }
        let n = Int(buf.frameLength), cc = Int(fmt.channelCount)
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<cc {
            let p = ch[c]
            for i in 0..<n { mono[i] += p[i] }
        }
        if cc > 1 { let k = 1 / Float(cc); for i in 0..<n { mono[i] *= k } }
        return (mono, fmt.sampleRate)
    }

    static func remove(_ dest: URL? = KeySoundCustom.fileURL) {
        guard let dest else { return }
        try? FileManager.default.removeItem(at: dest)
    }

    /// Độ dài (s) âm tự chọn đang lưu; nil ⇒ chưa có.
    static func storedDuration(_ url: URL? = KeySoundCustom.fileURL) -> Double? {
        KeySoundCustom.load(url).map { Double($0.count) / KeySoundSynth.sampleRate }
    }
}

/// Nghe thử âm phím / rung thử trong app.
final class KeyFeedbackPreview {
    static let shared = KeyFeedbackPreview()
    private var player: AVAudioPlayer?
    private var playerKey: String?
    private var sessionReady = false
    private var impact: UIImpactFeedbackGenerator?

    func playSound(style raw: String, volume: Int, kind: KeySoundKind = .letter) {
        let key = KeySoundCustom.bankKey(style: raw, customURL: KeySoundCustom.fileURL) + "/\(kind.rawValue)"
        if !sessionReady {
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.ambient, options: [.mixWithOthers])
            try? s.setActive(true)
            sessionReady = true
        }
        if key != playerKey || player == nil {
            let custom = raw == KeySoundStyle.custom.rawValue ? KeySoundCustom.load(KeySoundCustom.fileURL) : nil
            let bank = KeySoundSynth.bank(raw, custom: custom)
            player = try? AVAudioPlayer(data: KeySoundSynth.wav(bank.samples[kind.rawValue]))
            player?.prepareToPlay()
            playerKey = key
        }
        guard let p = player else { return }
        p.volume = KeySoundSynth.gain(forPercent: volume)
        p.currentTime = 0
        p.play()
    }

    /// Rung thử đúng như bàn phím (Core Haptics cùng độ mạnh); máy không có ⇒ impact nhẹ.
    func playHaptic(strength: Int) {
        KeyHaptics.shared.setStrength(strength)
        if KeyHaptics.shared.play() { return }
        if impact == nil { impact = UIImpactFeedbackGenerator(style: .light) }
        impact?.impactOccurred(intensity: CGFloat(KeyHaptics.intensity(forPercent: strength)))
    }
}
