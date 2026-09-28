import XCTest

/// Rung phím (28/09/2026): UIImpactFeedbackGenerator im lặng trong extension iOS 27 ⇒
/// Core Haptics với độ mạnh theo thanh trượt 10…100 %, mặc định 45.
final class HapticTests: XCTestCase {
    func testPercentMapsAndClamps() {
        XCTAssertEqual(KeyHaptics.intensity(forPercent: 45), 0.45, accuracy: 1e-6)
        XCTAssertEqual(KeyHaptics.intensity(forPercent: 0), 0.10, accuracy: 1e-6)
        XCTAssertEqual(KeyHaptics.intensity(forPercent: 250), 1.0, accuracy: 1e-6)
    }

    func testSettingDefaultAndLoadClamp() {
        XCTAssertEqual(KeyboardSettings().hapticStrength, 45)
        let d = UserDefaults(suiteName: "vt-haptic-test")!
        d.removePersistentDomain(forName: "vt-haptic-test")
        d.set(500, forKey: "hapticStrength")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-haptic-test") }
        XCTAssertEqual(KeyboardSettings.load().hapticStrength, 100)
    }
}
