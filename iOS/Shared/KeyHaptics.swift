// KeyHaptics — rung phím bằng Core Haptics, chỉnh được độ mạnh. Dùng CHUNG bàn phím +
// app (nghe/rung thử khi kéo "Độ mạnh rung" — cùng cảm giác thật).
//
// PIN (Phil 28/09 "chọn kiểu rung subtle nào mà đỡ tốn pin nhất"):
// - Mỗi phím đúng MỘT .hapticTransient (≈10–15 ms kéo actuator), không sự kiện continuous,
//   không audio. Năng lượng Taptic ~ tỉ lệ intensity² × thời gian kéo ⇒ 45 % ≈ 20 % năng
//   lượng nhịp 100 %; transient là loại rẻ nhất Core Haptics có.
// - playsHapticsOnly = true: engine KHÔNG dựng đường audio (bớt một IO unit).
// - isAutoShutdownEnabled = true: engine tự tắt phần cứng khi rảnh, tự bật lại lúc player
//   start ⇒ KHÔNG gọi engine.start() mỗi phím (bản cũ gọi mỗi lần — tốn IPC). Chỉ start khi
//   dựng engine, hoặc khi player.start báo lỗi (engine bị hệ thống dừng) thì start rồi thử lại 1 lần.
// - Pattern player dựng sẵn cho độ mạnh hiện tại, đổi độ mạnh mới dựng lại.
import CoreHaptics
import Foundation

final class KeyHaptics {
    static let shared = KeyHaptics()
    /// Ghi log lỗi (bàn phím gán TouchLog.write; app để im).
    nonisolated(unsafe) static var log: (String) -> Void = { _ in }
    /// Độ mạnh 10…100 % từ thanh trượt (Phil 28/09: 45 = "vừa", nhịp nhẹ).
    private(set) var intensity: Float = 0.45
    var sharpness: Float = 0.6
    static func intensity(forPercent p: Int) -> Float { Float(max(10, min(100, p))) / 100 }
    func setStrength(_ percent: Int) {
        let v = Self.intensity(forPercent: percent)
        if v != intensity { intensity = v; player = nil }   // pattern dựng lại lần rung sau
    }
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var broken = false
    private var loggedFailure = false
    /// Số lần gọi engine.start() (test: không start mỗi phím).
    private(set) var engineStarts = 0

    func play() -> Bool {
        guard !broken, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.playsHapticsOnly = true
                e.isAutoShutdownEnabled = true
                e.stoppedHandler = { [weak self] _ in self?.player = nil }
                e.resetHandler = { [weak self] in self?.player = nil }
                try e.start(); engineStarts += 1
                engine = e
            }
            guard let e = engine else { return false }
            if player == nil { player = try makePlayer(e) }
            do {
                try player?.start(atTime: CHHapticTimeImmediate)
            } catch {
                // Engine bị dừng (reset/ngắt) — start lại một lần, dựng lại player, thử lại.
                try e.start(); engineStarts += 1
                player = try makePlayer(e)
                try player?.start(atTime: CHHapticTimeImmediate)
            }
            return true
        } catch {
            if !loggedFailure { loggedFailure = true; Self.log("haptics: Core Haptics lỗi \(error) → dùng 1519") }
            broken = true
            return false
        }
    }

    private func makePlayer(_ e: CHHapticEngine) throws -> CHHapticPatternPlayer {
        let ev = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: 0)
        return try e.makePlayer(with: CHHapticPattern(events: [ev], parameters: []))
    }
}
