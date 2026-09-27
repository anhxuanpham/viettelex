// PlusGate — cổng kiểm tra quyền Plus, dùng được cả trong app lẫn bàn phím.
// Bàn phím KHÔNG gọi StoreKit: chỉ đọc cờ `plusUnlocked` mà app ghi vào App
// Group sau khi StoreKit xác thực giao dịch (Transaction.currentEntitlements).
//
//   if PlusGate.isUnlocked(.textTransforms) { … }
//
import Foundation

enum PlusGate {
    /// Nơi đọc/ghi cờ — test thay bằng suite riêng.
    static var defaults: UserDefaults = UserDefaults(suiteName: PlusConfig.appGroup) ?? .standard

    /// Bản Debug cho phép công tắc giả lập đã mua; Release luôn bỏ qua.
    static var allowsDebugOverride: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Mặc định theo `PlusConfig.paywallEnabled`; test đổi được.
    static var paywallEnabled: Bool = PlusConfig.paywallEnabled

    /// Tính năng đã mở chưa. Chưa bật thanh toán → mở hết. Đã bật → mở khi có Plus.
    /// Riêng huy hiệu cảm ơn chỉ hiện khi đã mua thật (không "mở free").
    static func isUnlocked(_ feature: PlusFeature) -> Bool {
        if feature == .thanksBadge { return isPlus }
        return !paywallEnabled || isPlus
    }

    /// Đã có Plus (mua thật, hoặc giả lập trong bản Debug).
    static var isPlus: Bool {
        resolve(purchased: purchased,
                debugOverride: defaults.bool(forKey: PlusConfig.debugOverrideKey),
                allowDebugOverride: allowsDebugOverride)
    }

    /// Cờ mua thật do app ghi.
    static var purchased: Bool { defaults.bool(forKey: PlusConfig.unlockedKey) }

    /// Chỉ app gọi (sau khi xác thực entitlement). Bàn phím không ghi.
    static func setPurchased(_ on: Bool) {
        defaults.set(on, forKey: PlusConfig.unlockedKey)
    }

    /// Công tắc giả lập (Debug).
    static var debugOverride: Bool {
        get { defaults.bool(forKey: PlusConfig.debugOverrideKey) }
        set { defaults.set(newValue, forKey: PlusConfig.debugOverrideKey) }
    }

    /// Hàm thuần: tách để test.
    static func resolve(purchased: Bool, debugOverride: Bool, allowDebugOverride: Bool) -> Bool {
        purchased || (allowDebugOverride && debugOverride)
    }

    /// Số mục ghim clipboard tối đa (nil = không giới hạn).
    static var pinnedClipLimit: Int? {
        isUnlocked(.advancedClipboard) ? nil : PlusConfig.freePinnedClipLimit
    }
}
