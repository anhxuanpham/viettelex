import XCTest
import UIKit

/// Ảnh chụp tự kiểm (không phải test hồi quy): dựng KeyboardView offscreen, xuất PNG.
/// Chỉ chạy khi có biến môi trường VT_SNAPSHOT_DIR (xcodebuild: TEST_RUNNER_VT_SNAPSHOT_DIR=…).
final class UXSnapshotTests: XCTestCase {
    @MainActor func testWriteSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["VT_SNAPSHOT_DIR"] else {
            throw XCTSkip("đặt VT_SNAPSHOT_DIR để xuất ảnh")
        }
        let w: CGFloat = 402
        func shot(_ name: String, dark: Bool, _ configure: (KeyboardView) -> Void) throws {
            let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
            let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 300))
            // Nền mô phỏng backdrop bàn phím hệ thống (theme Hệ thống để trong suốt).
            host.backgroundColor = dark ? UIColor(white: 0.11, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
            host.overrideUserInterfaceStyle = dark ? .dark : .light
            host.addSubview(kb)
            kb.frame = host.bounds
            kb.applyAppearance(dark ? .dark : .light, style: dark ? .dark : .light)
            kb.setSuggestionsEnabled(true)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            configure(kb)
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            let h = kb.systemLayoutSizeFitting(CGSize(width: w, height: 0)).height
            host.frame.size.height = max(h, 200); kb.frame = host.bounds
            host.layoutIfNeeded(); kb.layoutIfNeeded()
            let img = UIGraphicsImageRenderer(bounds: host.bounds).image { ctx in host.layer.render(in: ctx.cgContext) }
            try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for dark in [true, false] {
            let s = dark ? "dark" : "light"
            try shot("letters-\(s)", dark: dark) { $0.showSuggestions(.init(literal: "đ", word: "đáp", emojis: ["😀", "👍"])) }
            try shot("paste-\(s)", dark: dark) { kb in
                kb.showSuggestions(.init(nextWords: ["Đáp", "Được", "Đi"]))
                var p = KeyboardView.SuggestionSet(nextWords: ["Đáp", "Được", "Đi"]); p.paste = true
                kb.showSuggestions(p)
                kb.debugRefreshChrome()
            }
            try shot("emoji-\(s)", dark: dark) { $0.debugShowEmojiPlane() }
            // Giữ phím ra số / ký hiệu (issue #98): nhãn nhỏ góc trên-phải.
            try shot("alternates-\(s)", dark: dark) { $0.configureKeyAlternates(numbers: true, symbols: true) }
        }
        // Độ trong suốt phím / ký tự 0/50/100% (Hệ thống + Hồng đào) — ghi App Group rồi trả lại.
        let d = UserDefaultsProvider.shared
        let keys = [ThemeSettings.themeKey, KeyboardTransparency.keyboardKey, KeyboardTransparency.labelKey]
        let saved = keys.map { d?.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d?.set(v, forKey: k) } }
        for theme in [KeyboardTheme.system, .peach] {
            for dark in [true, false] {
                for (k, l) in [(0, 0), (50, 0), (100, 0), (0, 50), (0, 100), (50, 50)] {
                    d?.set(theme.rawValue, forKey: ThemeSettings.themeKey)
                    d?.set(k, forKey: KeyboardTransparency.keyboardKey)
                    d?.set(l, forKey: KeyboardTransparency.labelKey)
                    try shot("transp-\(theme.rawValue)-k\(k)-l\(l)-\(dark ? "dark" : "light")", dark: dark) { _ in }
                }
            }
        }
    }
}
