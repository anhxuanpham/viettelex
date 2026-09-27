import UIKit

// Theme bàn phím — MỌI token màu ở một chỗ (dùng chung Keyboard + App + test).
// Android giữ bảng y hệt ở android/keyboard/.../KeyboardTheme.kt — sửa màu thì
// sửa cả hai. Vẽ phím vẫn phẳng: không bóng, không blur runtime, không offscreen
// pass (xem lịch sử bỏ shadow trong KeyboardView). Kính = để lộ backdrop mờ SẴN
// CÓ của hệ thống + phím bán trong suốt, không tự blur.

/// Màu RGBA thuần (0…1) — tách khỏi UIColor để test tính tương phản.
struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }
    static let white = RGBA(hex: 0xFFFFFF), black = RGBA(hex: 0x000000)
    func alpha(_ x: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: a * x) }
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    /// Trộn màu này (có alpha) lên nền đục.
    func over(_ bg: RGBA) -> RGBA {
        RGBA(r: r * a + bg.r * (1 - a), g: g * a + bg.g * (1 - a), b: b * a + bg.b * (1 - a))
    }
    /// Độ chói tương đối WCAG 2.x.
    var luminance: Double {
        func ch(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
    }
    /// Tỉ lệ tương phản WCAG (1…21), cả hai màu coi như đục.
    static func contrast(_ x: RGBA, _ y: RGBA) -> Double {
        let a = x.luminance, b = y.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Bộ token một theme đã giải (theo sáng/tối hệ thống + ảnh nền).
struct KeyboardPalette: Equatable {
    /// nil = nền trong suốt (backdrop hệ thống lộ ra: theme Hệ thống, Kính).
    var background: RGBA?
    var keyFill: RGBA
    /// Phím chức năng khi ĐÈ (iOS 26+: mọi phím cùng nền, đè thì sẫm lại).
    var specialFill: RGBA
    var ink: RGBA
    var trail: RGBA
    /// Chữ/icon thanh gợi ý.
    var barInk: RGBA
    var balloon: RGBA
    /// Phím return dạng hành động (go/search/send…).
    var accent: RGBA
    var accentInk: RGBA
    /// Viền phím 1pt (chỉ theme tương phản cao) — borderWidth không gây offscreen.
    var keyBorder: RGBA?
    /// Chữ sáng trên nền tối → icon hệ thống, emoji plane, … đi theo nhánh tối.
    var isDark: Bool

    /// Có ảnh nền: phím hơi trong để ảnh lộ ra; lớp phủ (dim) do view vẽ riêng.
    /// Độ trong được chọn sao cho chữ vẫn ≥ 4.5:1 (WCAG AA) kể cả trên ảnh TỆ NHẤT
    /// (trắng tuyền dưới theme tối, đen tuyền dưới theme sáng) và lớp phủ 0%.
    static let wallpaperKeyAlpha = 0.8
    func overWallpaper() -> KeyboardPalette {
        let worst: RGBA = isDark ? .white : .black
        func legible(_ base: RGBA) -> RGBA {
            // Theme phím vốn trong (Kính): đổi sang phím phủ đen/trắng bán trong.
            let translucent = base.a < 1
            let solid = translucent ? (isDark ? RGBA.black : RGBA.white) : base
            var a = translucent ? 0.5 : Self.wallpaperKeyAlpha
            while a < 1, RGBA.contrast(ink, solid.alpha(a).over(worst)) < 4.5 { a += 0.05 }
            return solid.alpha(min(a, 1))
        }
        var p = self
        p.keyFill = legible(keyFill)
        p.specialFill = legible(specialFill)
        p.background = nil
        return p
    }
    /// Màu lớp phủ ảnh nền: tối cho theme tối, sáng cho theme sáng.
    var wallpaperOverlay: RGBA { isDark ? .black : .white }
}

enum KeyboardTheme: String, CaseIterable {
    case system, oled, contrast, peach, mint, sky, lavender, glass

    var title: String {
        switch self {
        case .system: return "Hệ thống"
        case .oled: return "Tối OLED"
        case .contrast: return "Tương phản cao"
        case .peach: return "Hồng đào"
        case .mint: return "Bạc hà"
        case .sky: return "Trời xanh"
        case .lavender: return "Oải hương"
        case .glass: return "Kính"
        }
    }

    /// Theme cao cấp thuộc gói Plus. Tương phản cao là trợ năng → luôn miễn phí.
    var isPlus: Bool {
        switch self {
        case .system, .oled, .contrast: return false
        case .peach, .mint, .sky, .lavender, .glass: return true
        }
    }

    func palette(systemDark: Bool) -> KeyboardPalette {
        let blue = RGBA(r: 0, g: 0.478, b: 1)   // ≈ systemBlue
        switch self {
        case .system:
            // Giá trị cũ của KeyboardView (plainFill/specialFill) — không đổi hình.
            return systemDark
                ? KeyboardPalette(background: nil, keyFill: RGBA(r: 0.42, g: 0.42, b: 0.42),
                                  specialFill: RGBA(r: 0.26, g: 0.26, b: 0.26), ink: .white,
                                  trail: RGBA.white.alpha(0.55), barInk: .white,
                                  balloon: RGBA(r: 0.35, g: 0.35, b: 0.35),
                                  accent: blue, accentInk: .white, keyBorder: nil, isDark: true)
                : KeyboardPalette(background: nil, keyFill: .white,
                                  specialFill: RGBA(r: 0.68, g: 0.70, b: 0.74), ink: .black,
                                  trail: blue.alpha(0.55), barInk: .black, balloon: .white,
                                  accent: blue, accentInk: .white, keyBorder: nil, isDark: false)
        case .oled:
            return KeyboardPalette(background: .black, keyFill: RGBA(hex: 0x1C1C1E),
                                   specialFill: RGBA(hex: 0x3A3A3C), ink: .white,
                                   trail: RGBA.white.alpha(0.6), barInk: .white,
                                   balloon: RGBA(hex: 0x2C2C2E),
                                   accent: RGBA(hex: 0x0A84FF), accentInk: .white,
                                   keyBorder: nil, isDark: true)
        case .contrast:
            // Nền đen tuyền, phím đen viền trắng, chữ trắng, nhấn vàng (≥ AAA 7:1).
            return KeyboardPalette(background: .black, keyFill: RGBA(hex: 0x141414),
                                   specialFill: RGBA(hex: 0x4D4D4D), ink: .white,
                                   trail: RGBA(hex: 0xFFD60A), barInk: .white,
                                   balloon: RGBA(hex: 0x141414),
                                   accent: RGBA(hex: 0xFFD60A), accentInk: .black,
                                   keyBorder: RGBA.white.alpha(0.85), isDark: true)
        case .peach:
            return Self.pastel(bg: 0xFBE3E1, key: 0xFFF8F7, special: 0xF1C4BF,
                               ink: 0x4A2226, accent: 0xC2505A)
        case .mint:
            return Self.pastel(bg: 0xD9F2E7, key: 0xF6FFFA, special: 0xAFDDC9,
                               ink: 0x173B30, accent: 0x1F7A5C)
        case .sky:
            return Self.pastel(bg: 0xDAE9F8, key: 0xF6FAFF, special: 0xB3CFEE,
                               ink: 0x14304C, accent: 0x2C6BB8)
        case .lavender:
            return Self.pastel(bg: 0xE8E2F6, key: 0xFBF9FF, special: 0xCBBFEA,
                               ink: 0x2C2345, accent: 0x6A48C4)
        case .glass:
            // Nền trong suốt: backdrop mờ của hệ thống lộ ra (miễn phí, không
            // blur tự vẽ); phím trắng bán trong kiểu Liquid Glass.
            return systemDark
                ? KeyboardPalette(background: nil, keyFill: RGBA.white.alpha(0.16),
                                  specialFill: RGBA.white.alpha(0.32), ink: .white,
                                  trail: RGBA.white.alpha(0.6), barInk: .white,
                                  balloon: RGBA(hex: 0x4A4A4E),
                                  accent: blue, accentInk: .white, keyBorder: RGBA.white.alpha(0.18),
                                  isDark: true)
                : KeyboardPalette(background: nil, keyFill: RGBA.white.alpha(0.55),
                                  specialFill: RGBA.white.alpha(0.3), ink: .black,
                                  trail: blue.alpha(0.55), barInk: .black, balloon: .white,
                                  accent: blue, accentInk: .white, keyBorder: RGBA.white.alpha(0.6),
                                  isDark: false)
        }
    }

    private static func pastel(bg: UInt32, key: UInt32, special: UInt32,
                               ink: UInt32, accent: UInt32) -> KeyboardPalette {
        let a = RGBA(hex: accent)
        return KeyboardPalette(background: RGBA(hex: bg), keyFill: RGBA(hex: key),
                               specialFill: RGBA(hex: special), ink: RGBA(hex: ink),
                               trail: a.alpha(0.6), barInk: RGBA(hex: ink),
                               balloon: RGBA(hex: key), accent: a, accentInk: .white,
                               keyBorder: nil, isDark: false)
    }
}

/// Cổng Plus cho theme: dùng PlusGate thật (iOS/Shared) — `.premiumThemes` gồm
/// theme cao cấp + ảnh nền. Hệ thống/OLED/tương phản cao luôn miễn phí.
enum ThemeGate {
    static func allows(_ theme: KeyboardTheme) -> Bool {
        !theme.isPlus || PlusGate.isUnlocked(.premiumThemes)
    }
    static var allowsWallpaper: Bool { PlusGate.isUnlocked(.premiumThemes) }
}

/// Cài đặt giao diện (App Group) — app ghi, bàn phím đọc mỗi lần hiện.
struct ThemeSettings: Equatable {
    static let themeKey = "keyboardTheme"
    static let wallpaperKey = "wallpaperEnabled"
    static let dimKey = "wallpaperDim"        // % lớp phủ 0…80
    static let blurKey = "wallpaperBlur"      // bán kính mờ 0…20 (app áp khi lưu ảnh)
    static let versionKey = "wallpaperVersion" // đổi mỗi lần lưu ảnh → vứt cache

    var theme: KeyboardTheme = .system
    var wallpaper = false
    var dim = 30
    var blur = 0
    var version: Double = 0

    static func load(_ d: UserDefaults?) -> ThemeSettings {
        var s = ThemeSettings()
        guard let d else { return s }
        if let raw = d.string(forKey: themeKey), let t = KeyboardTheme(rawValue: raw) { s.theme = t }
        s.wallpaper = d.bool(forKey: wallpaperKey)
        if d.object(forKey: dimKey) != nil { s.dim = max(0, min(80, d.integer(forKey: dimKey))) }
        s.blur = max(0, min(20, d.integer(forKey: blurKey)))
        s.version = d.double(forKey: versionKey)
        return s
    }

    func save(_ d: UserDefaults?) {
        d?.set(theme.rawValue, forKey: Self.themeKey)
        d?.set(wallpaper, forKey: Self.wallpaperKey)
        d?.set(dim, forKey: Self.dimKey)
        d?.set(blur, forKey: Self.blurKey)
        d?.set(version, forKey: Self.versionKey)
    }

    /// Theme thực dùng sau cổng Plus (hết quyền → về Hệ thống, không crash/không trắng).
    var effectiveTheme: KeyboardTheme { ThemeGate.allows(theme) ? theme : .system }
    /// Ảnh nền chỉ bật khi có quyền Plus VÀ file tồn tại.
    func wallpaperActive(fileExists: Bool) -> Bool {
        wallpaper && fileExists && ThemeGate.allowsWallpaper
    }

    func palette(systemDark: Bool, wallpaperActive: Bool) -> KeyboardPalette {
        let p = effectiveTheme.palette(systemDark: systemDark)
        return wallpaperActive ? p.overWallpaper() : p
    }
}
