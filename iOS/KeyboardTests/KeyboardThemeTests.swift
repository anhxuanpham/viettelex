import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Theme bàn phím: token, cổng Plus, lưu/đọc cài đặt, tương phản WCAG, pipeline ảnh nền.
final class KeyboardThemeTests: XCTestCase {

    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var suite = ""

    override func setUp() {
        super.setUp()
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        PlusGate.paywallEnabled = false   // mặc định test = mở (test gating tự bật)
        suite = "themeplus-\(UUID().uuidString)"
        PlusGate.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        PlusGate.defaults.removePersistentDomain(forName: suite)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        super.tearDown()
    }

    /// Bật paywall + chưa mua (tắt cả công tắc giả lập Debug).
    private func lockPlus() {
        PlusGate.paywallEnabled = true
        PlusGate.setPurchased(false)
        PlusGate.debugOverride = false
    }

    // MARK: token

    func testThemeSetIsCompactAndSystemIsDefault() {
        XCTAssertTrue((6...8).contains(KeyboardTheme.allCases.count))
        XCTAssertEqual(ThemeSettings().theme, .system)
        XCTAssertEqual(ThemeSettings.load(nil).theme, .system)
    }

    /// Theme Hệ thống giữ NGUYÊN màu cũ của KeyboardView (không đổi hình người dùng cũ).
    func testSystemPaletteMatchesLegacyColors() {
        let light = KeyboardTheme.system.palette(systemDark: false)
        XCTAssertEqual(light.keyFill, .white)
        XCTAssertEqual(light.specialFill, RGBA(r: 0.68, g: 0.70, b: 0.74))
        XCTAssertEqual(light.ink, .black)
        XCTAssertNil(light.background)
        XCTAssertFalse(light.isDark)
        let dark = KeyboardTheme.system.palette(systemDark: true)
        // Tối: theo stock iOS 27 đo pixel (phím #444444 trên nền #202020) — xem UXFeedbackTests.
        XCTAssertEqual(dark.keyFill, RGBA(hex: 0x444444))
        XCTAssertEqual(dark.ink, .white)
        XCTAssertTrue(dark.isDark)
    }

    func testFixedThemesIgnoreSystemAppearance() {
        for t in KeyboardTheme.allCases where t != .system && t != .glass {
            XCTAssertEqual(t.palette(systemDark: false), t.palette(systemDark: true), t.rawValue)
            XCTAssertNotNil(t.palette(systemDark: false).background, "\(t) cần nền đục")
        }
        XCTAssertNil(KeyboardTheme.glass.palette(systemDark: false).background,
                     "Kính để lộ backdrop hệ thống, không tự blur")
    }

    func testIsDarkMatchesInkLuminance() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let p = t.palette(systemDark: d)
                XCTAssertEqual(p.isDark, p.ink.luminance > 0.5, "\(t) dark=\(d)")
            }
        }
    }

    // MARK: tương phản WCAG

    /// Tương phản cao: chữ/nền phím ≥ 7:1 (AAA, vượt AA 4.5), cả khi đè phím, nhấn
    /// (return hành động) và thanh gợi ý trên nền bàn phím.
    func testHighContrastMeetsWCAG() {
        let p = KeyboardTheme.contrast.palette(systemDark: false)
        let bg = p.background!
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(bg)), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill.over(bg)), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, bg), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.balloon), 7)
        // Ranh giới phím phải thấy được (viền ≥ 3:1 so với nền — WCAG 1.4.11).
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.keyBorder!.over(bg), bg), 3)
    }

    /// Mọi theme đục: chữ trên phím đạt AA (4.5:1).
    func testAllOpaqueThemesMeetAA() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let p = t.palette(systemDark: d)
                // Nền trong suốt: kiểm trên backdrop hệ thống xấp xỉ (xám sáng / xám tối).
                let bg = p.background ?? (p.isDark ? RGBA(hex: 0x2A2A2A) : RGBA(hex: 0xD1D4DA))
                let key = p.keyFill.over(bg)
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, key), 4.5, "\(t) dark=\(d) phím")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, bg), 4.5, "\(t) dark=\(d) bar")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.accentInk, p.accent), 3, "\(t) dark=\(d) nhấn")
            }
        }
    }

    /// Có ảnh nền: phím bán trong 80%. Kể cả ảnh tệ nhất (đen tuyền dưới theme sáng,
    /// trắng tuyền dưới theme tối) và lớp phủ 0%, chữ vẫn ≥ 4.5:1.
    func testWallpaperKeysStayLegibleOnWorstImage() {
        for t in KeyboardTheme.allCases {
            for d in [false, true] {
                let p = ThemeSettings(theme: t).palette(systemDark: d, wallpaperActive: true)
                XCTAssertNil(p.background)
                let worst: RGBA = p.isDark ? .white : .black
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill.over(worst)), 4.5,
                                            "\(t) dark=\(d) phím")
                XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill.over(worst)), 4.5,
                                            "\(t) dark=\(d) phím đè")
                XCTAssertLessThan(p.keyFill.a, 1.0001)
                // Ảnh vẫn lộ ra ở theme sáng (phím không đục hoàn toàn).
                if !p.isDark { XCTAssertLessThan(p.keyFill.a, 1, "\(t) phím nên hơi trong") }
            }
        }
    }

    func testContrastMath() {
        XCTAssertEqual(RGBA.contrast(.white, .black), 21, accuracy: 0.01)
        XCTAssertEqual(RGBA.contrast(.white, .white), 1, accuracy: 0.001)
        // #767676 trên trắng ≈ 4.54 (mốc AA quen thuộc).
        XCTAssertEqual(RGBA.contrast(RGBA(hex: 0x767676), .white), 4.54, accuracy: 0.02)
    }

    // MARK: cổng Plus

    func testGateOpenWhilePaywallOff() {
        PlusGate.paywallEnabled = false
        for t in KeyboardTheme.allCases { XCTAssertTrue(ThemeGate.allows(t)) }
        XCTAssertTrue(ThemeGate.allowsWallpaper)
    }

    func testFreeThemesStayFreeBehindPaywall() {
        lockPlus()
        XCTAssertTrue(ThemeGate.allows(.system))
        XCTAssertTrue(ThemeGate.allows(.oled))
        XCTAssertTrue(ThemeGate.allows(.contrast))
        XCTAssertFalse(ThemeGate.allows(.glass))
        XCTAssertFalse(ThemeGate.allowsWallpaper)
        PlusGate.setPurchased(true)
        XCTAssertTrue(ThemeGate.allows(.glass))
        XCTAssertTrue(ThemeGate.allowsWallpaper)
    }

    func testFreeThemesIncludeAccessibility() {
        XCTAssertFalse(KeyboardTheme.system.isPlus)
        XCTAssertFalse(KeyboardTheme.contrast.isPlus, "trợ năng không được khoá sau Plus")
        XCTAssertTrue(KeyboardTheme.glass.isPlus)
        XCTAssertTrue(KeyboardTheme.allCases.contains { $0.isPlus })
    }

    func testLockedPlusFallsBackToSystem() {
        lockPlus()
        let s = ThemeSettings(theme: .mint, wallpaper: true)
        XCTAssertEqual(s.effectiveTheme, .system)
        XCTAssertFalse(s.wallpaperActive(fileExists: true))
        XCTAssertEqual(ThemeSettings(theme: .contrast).effectiveTheme, .contrast)
    }

    // MARK: lưu/đọc

    func testSettingsRoundTrip() {
        let suite = "themetest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ThemeSettings.load(d), ThemeSettings())   // mặc định khi trống
        let s = ThemeSettings(theme: .lavender, wallpaper: true, dim: 55, blur: 7, version: 123.5,
                              keyboardTransparency: 35, labelTransparency: 60)
        s.save(d)
        XCTAssertEqual(ThemeSettings.load(d), s)
    }

    func testLoadClampsAndIgnoresGarbage() {
        let suite = "themetest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set("neon-pink-unknown", forKey: ThemeSettings.themeKey)
        d.set(500, forKey: ThemeSettings.dimKey)
        d.set(-3, forKey: ThemeSettings.blurKey)
        d.set(180, forKey: KeyboardTransparency.keyboardKey)
        d.set(-9, forKey: KeyboardTransparency.labelKey)
        let s = ThemeSettings.load(d)
        XCTAssertEqual(s.keyboardTransparency, 100)
        XCTAssertEqual(s.labelTransparency, 0)
        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.dim, 80)
        XCTAssertEqual(s.blur, 0)
    }

    // MARK: độ trong suốt

    private func allPalettes() -> [(KeyboardPalette, Bool, Bool)] {
        var out: [(KeyboardPalette, Bool, Bool)] = []
        for t in KeyboardTheme.allCases {
            for dark in [false, true] {
                let p = t.palette(systemDark: dark)
                out.append((p, dark, false)); out.append((p.overWallpaper(), dark, true))
            }
        }
        return out
    }

    func testTransparencyZeroIsIdentity() {
        for (p, dark, wp) in allPalettes() {
            XCTAssertEqual(p.withTransparency(keyboard: 0, labels: 0, systemDark: dark, wallpaper: wp), p)
            XCTAssertEqual(p.withTransparency(keyboard: -30, labels: -1, systemDark: dark, wallpaper: wp), p)
        }
    }

    func testTransparencyMapping() {
        XCTAssertEqual(KeyboardTransparency.alpha(0), 1)
        XCTAssertEqual(KeyboardTransparency.alpha(40), 0.6, accuracy: 1e-9)
        XCTAssertEqual(KeyboardTransparency.alpha(100), 0)
        XCTAssertEqual(KeyboardTransparency.alpha(250), 0)      // kẹp
        XCTAssertEqual(KeyboardTransparency.alpha(-5), 1)

        let peach = KeyboardTheme.peach.palette(systemDark: false)
        let half = peach.withTransparency(keyboard: 50, labels: 0, systemDark: false, wallpaper: false)
        XCTAssertEqual(half.background?.a ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.keyFill.a, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.specialFill.a, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.accent.a, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.surfaceAlpha, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.keyInk.a, 1)                        // chữ không mờ theo phím

        let glass = KeyboardTheme.glass.palette(systemDark: false)
        let g = glass.withTransparency(keyboard: 50, labels: 0, systemDark: false, wallpaper: false)
        XCTAssertEqual(g.keyBorder?.a ?? -1, (glass.keyBorder?.a ?? 0) * 0.5, accuracy: 1e-9)
        XCTAssertNil(g.background)                              // nền trong suốt vẫn nil

        // 100% phím: nền/phím/viền/bóng biến mất hẳn, chữ còn nguyên.
        for (p, dark, wp) in allPalettes() {
            let z = p.withTransparency(keyboard: 100, labels: 0, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(z.keyFill.a, 0); XCTAssertEqual(z.specialFill.a, 0); XCTAssertEqual(z.accent.a, 0)
            XCTAssertEqual(z.background?.a ?? 0, 0); XCTAssertEqual(z.keyBorder?.a ?? 0, 0)
            XCTAssertEqual(z.surfaceAlpha, 0)
            XCTAssertEqual(z.keyInk.a, 1)
        }
    }

    func testLabelTransparencyIndependentAndSparesBalloon() {
        for (p, dark, wp) in allPalettes() {
            let z = p.withTransparency(keyboard: 0, labels: 100, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(z.keyInk.a, 0); XCTAssertEqual(z.accentInk.a, 0)
            XCTAssertEqual(z.keyFill, p.keyFill); XCTAssertEqual(z.background, p.background)
            XCTAssertEqual(z.ink, p.ink); XCTAssertEqual(z.balloon, p.balloon)   // balloon rõ nguyên
            let h = p.withTransparency(keyboard: 0, labels: 30, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(h.keyInk, p.ink.alpha(0.7))
        }
    }

    /// Nền trong suốt lộ backdrop khác tông → chữ tự đổi đen/trắng cho đọc được;
    /// mức nhỏ không được lật màu (không đổi hình người đang dùng).
    func testLabelsStayReadableWhenBackgroundGoesClear() {
        let peachDark = KeyboardTheme.peach.palette(systemDark: true)
            .withTransparency(keyboard: 100, labels: 0, systemDark: true, wallpaper: false)
        XCTAssertEqual(peachDark.keyInk, .white)
        XCTAssertTrue(peachDark.isDark)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(peachDark.barInk,
                                                  KeyboardTransparency.systemBackdrop(dark: true)), 4.5)
        let peachLight = KeyboardTheme.peach.palette(systemDark: false)
        XCTAssertEqual(peachLight.withTransparency(keyboard: 100, labels: 0, systemDark: false,
                                                   wallpaper: false).keyInk, peachLight.ink)
        for (p, dark, wp) in allPalettes() {
            let small = p.withTransparency(keyboard: 10, labels: 0, systemDark: dark, wallpaper: wp)
            XCTAssertEqual(small.keyInk, p.ink); XCTAssertEqual(small.barInk, p.barInk)
            XCTAssertEqual(small.accentInk, p.accentInk); XCTAssertEqual(small.isDark, p.isDark)
        }
    }

    func testSettingsApplyTransparency() {
        let s = ThemeSettings(theme: .mint, keyboardTransparency: 100, labelTransparency: 100)
        let p = s.palette(systemDark: false, wallpaperActive: false)
        XCTAssertEqual(p.keyFill.a, 0); XCTAssertEqual(p.keyInk.a, 0)
    }

    func testResetToDefaults() {
        XCTAssertTrue(ThemeSettings().isDefault)
        let s = ThemeSettings(theme: .sky, wallpaper: true, dim: 60, blur: 9, version: 77,
                              keyboardTransparency: 40, labelTransparency: 25)
        XCTAssertFalse(s.isDefault)
        let r = s.resetToDefaults()
        XCTAssertTrue(r.isDefault)
        XCTAssertEqual(r.theme, .system); XCTAssertFalse(r.wallpaper)
        XCTAssertEqual(r.dim, 30); XCTAssertEqual(r.blur, 0)
        XCTAssertEqual(r.keyboardTransparency, 0); XCTAssertEqual(r.labelTransparency, 0)
        XCTAssertEqual(r.version, 77)                          // ảnh nền giữ nguyên, không vứt cache
        XCTAssertFalse(ThemeSettings(labelTransparency: 5).isDefault)
    }

    func testWallpaperNeedsFile() {
        let s = ThemeSettings(theme: .sky, wallpaper: true)
        XCTAssertFalse(s.wallpaperActive(fileExists: false))
        XCTAssertTrue(s.wallpaperActive(fileExists: true))
        XCTAssertFalse(ThemeSettings(wallpaper: false).wallpaperActive(fileExists: true))
    }

    // MARK: ảnh nền

    nonisolated(unsafe) private static var jpegCache: [String: Data] = [:]
    private func makeJPEG(width: Int, height: Int) -> Data {
        let k = "\(width)x\(height)"
        if let d = Self.jpegCache[k] { return d }
        let d = renderJPEG(width: width, height: height)
        Self.jpegCache[k] = d
        return d
    }

    private func renderJPEG(width: Int, height: Int) -> Data {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            // Nhiễu màu → JPEG khó nén (trường hợp xấu cho giới hạn dung lượng).
            var seed: UInt32 = 12345
            let step = 16
            for y in stride(from: 0, to: height, by: step) {
                for x in stride(from: 0, to: width, by: step) {
                    seed = seed &* 1664525 &+ 1013904223
                    UIColor(red: CGFloat(seed & 0xFF) / 255, green: CGFloat((seed >> 8) & 0xFF) / 255,
                            blue: CGFloat((seed >> 16) & 0xFF) / 255, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: step, height: step))
                }
            }
        }
        return img.jpegData(compressionQuality: 0.95)!
    }

    private func pixelSize(_ data: Data) -> (Int, Int) {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }

    func testPrepareDownsamplesAndCompresses() {
        let original = makeJPEG(width: 4032, height: 3024)     // ảnh camera 12MP
        let out = Wallpaper.prepare(original: original, blur: 0)!
        let (w, h) = pixelSize(out)
        XCTAssertLessThanOrEqual(max(w, h), Wallpaper.maxEdge)
        XCTAssertEqual(max(w, h), Wallpaper.maxEdge)
        XCTAssertEqual(Double(w) / Double(h), 4032.0 / 3024.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(out.count, Wallpaper.maxBytes)
    }

    func testPreparePortraitAndBlur() {
        let original = makeJPEG(width: 1500, height: 3000)
        let out = Wallpaper.prepare(original: original, blur: 10)!
        let (w, h) = pixelSize(out)
        XCTAssertEqual(h, Wallpaper.maxEdge)
        XCTAssertEqual(w, 540)
        XCTAssertLessThanOrEqual(out.count, Wallpaper.maxBytes)
    }

    func testSmallImageNotUpscaled() {
        let out = Wallpaper.prepare(original: makeJPEG(width: 600, height: 400), blur: 0)!
        let (w, h) = pixelSize(out)
        XCTAssertLessThanOrEqual(w, 600)
        XCTAssertLessThanOrEqual(h, 400)
    }

    /// Cỡ giải trong extension: đủ phủ view (aspect-fill) nhưng không vượt bản lưu.
    func testDisplayMaxPixel() {
        // iPhone dọc 393×300pt @3x = 1179×900px; ảnh 4:3 ngang → cần rộng 1200 → kẹp 1080.
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: CGSize(width: 393, height: 300),
                                                 scale: 3, imageAspect: 4.0 / 3), 1080)
        // @2x view 320×216 = 640×432, ảnh vuông → cần 640×640.
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: CGSize(width: 320, height: 216),
                                                 scale: 2, imageAspect: 1), 640)
        // Ảnh dọc 1:2 phủ view ngang 640×432: rộng 640 → cao 1280 → kẹp 1080.
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: CGSize(width: 320, height: 216),
                                                 scale: 2, imageAspect: 0.5), 1080)
        XCTAssertEqual(Wallpaper.displayMaxPixel(viewSize: .zero, scale: 3, imageAspect: 1), 1080)
    }

    func testKeyboardDecodeRespectsLimit() {
        let data = Wallpaper.prepare(original: makeJPEG(width: 4032, height: 3024), blur: 0)!
        let cg = Wallpaper.downsample(data: data, maxPixel: 640)!
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 640)
    }

    /// RAM: giải ảnh nền cỡ bàn phím iPhone 3x — đo phys_footprint tăng thêm.
    func testKeyboardDecodeMemoryFootprint() throws {
        try SlowTests.require()
        let data = Wallpaper.prepare(original: makeJPEG(width: 4032, height: 3024), blur: 0)!
        let px = Wallpaper.displayMaxPixel(viewSize: CGSize(width: 430, height: 300), scale: 3,
                                           imageAspect: 4.0 / 3)
        let before = Self.footprint()
        var images: [CGImage] = []
        autoreleasepool {
            images.append(Wallpaper.downsample(data: data, maxPixel: px)!)
        }
        let delta = Double(Self.footprint() - before) / 1_048_576
        let bitmapMB = Double(images[0].bytesPerRow * images[0].height) / 1_048_576
        print("THEME-RAM wallpaper decode \(images[0].width)x\(images[0].height): bitmap \(String(format: "%.1f", bitmapMB))MB, footprint +\(String(format: "%.1f", delta))MB")
        XCTAssertLessThanOrEqual(bitmapMB, 5, "bitmap ảnh nền phải ≤5MB (ngân sách extension ~48MB)")
        XCTAssertLessThan(delta, 12)
    }

    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}
