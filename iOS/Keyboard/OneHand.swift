// Chế độ một tay (iPhone; iPad bỏ qua) — logic THUẦN, pinned by OneHandTests.
// Cùng tỉ lệ / chuỗi prefs với Android (android/.../ime/OneHand.kt).
//
// Áp: KeyboardView thụt rowsContainer hai mép (insets) — mọi phím dựng bằng stack/
// multiplier theo bề ngang hàng nên co theo, router / gõ vuốt đọc frame thật. Dải trống
// ("rail") có nút đổi bên + thoát. Emoji / mẫu câu giữ đầy bề ngang.
import CoreGraphics

enum OneHandSide: String, CaseIterable {
    case off, left, right

    /// Nút "đổi bên".
    var switched: OneHandSide {
        switch self {
        case .left: return .right
        case .right: return .left
        case .off: return .off
        }
    }
}

enum OneHand {
    /// Bề ngang bàn phím khi thu hẹp (Gboard ≈ 0.8, stock iOS ≈ 0.85).
    static let ratio: CGFloat = 0.82

    /// Khoá: App Group (app chọn) và UserDefaults.standard của extension (bàn phím tự
    /// bật/tắt — không Full Access thì iOS cấm extension GHI App Group).
    static let key = "oneHandMode"
    static let seenGroupKey = "oneHandSeenGroup"
    static let lastSideKey = "oneHandLastSide"

    /// Thụt trái / phải của vùng phím trong bề ngang `width`.
    static func insets(width: CGFloat, side: OneHandSide) -> (left: CGFloat, right: CGFloat) {
        let gap = width * (1 - ratio)
        switch side {
        case .off: return (0, 0)
        case .left: return (0, gap)
        case .right: return (gap, 0)
        }
    }

    /// Dải trống (x, bề rộng) chứa nút rail; nil khi tắt.
    static func rail(width: CGFloat, side: OneHandSide) -> (x: CGFloat, width: CGFloat)? {
        let i = insets(width: width, side: side)
        switch side {
        case .off: return nil
        case .left: return (width - i.right, i.right)
        case .right: return (0, i.left)
        }
    }

    /// Giữ lâu / nút "Một tay": tắt ⇒ bật về `preferred` (mặc định phải); bật ⇒ tắt.
    static func toggled(_ side: OneHandSide, preferred: OneHandSide = .right) -> OneHandSide {
        side != .off ? .off : (preferred == .off ? .right : preferred)
    }

    /// Chế độ hiệu lực khi bàn phím hiện: app vừa đổi lựa chọn (giá trị App Group khác
    /// lần trước đã thấy) ⇒ theo app; không thì theo trạng thái bàn phím tự lưu.
    static func resolve(group: String?, seenGroup: String?, local: String?) -> OneHandSide {
        let g = group.flatMap(OneHandSide.init(rawValue:))
        if group != seenGroup, let g { return g }
        return local.flatMap(OneHandSide.init(rawValue:)) ?? g ?? .off
    }
}
