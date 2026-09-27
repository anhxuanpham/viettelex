// Cấu hình VietTelex Plus — ID sản phẩm + danh sách tính năng Plus. Đổi ID ở
// ĐÂY (và trong StoreKit/VietTelex.storekit) cho khớp App Store Connect.
// Dùng chung app + bàn phím (chỉ Foundation, không StoreKit).
import Foundation

enum PlusConfig {
    /// CÔNG TẮC THANH TOÁN. `false` = chưa bán: PlusGate mở MỌI tính năng Plus
    /// cho mọi người. Chỉ bật `true` sau khi đã tạo sản phẩm trên App Store
    /// Connect (xem iOS/store-drafts/PRODUCTS.md).
    static let paywallEnabled = false

    /// Giá gợi ý (chỉ để hiển thị khi StoreKit chưa tải được giá thật).
    static let plusPriceHint = "69.000đ"

    /// Non-consumable: mở khoá VietTelex Plus vĩnh viễn.
    static let plusProductID = "com.viettelex.ios.plus"

    /// Consumable: ủng hộ (tip), không mở khoá gì — 25.000đ / 49.000đ / 99.000đ.
    static let tipProductIDs = [
        "com.viettelex.ios.tip.small",
        "com.viettelex.ios.tip.medium",
        "com.viettelex.ios.tip.large",
    ]

    static var allProductIDs: [String] { [plusProductID] + tipProductIDs }

    /// App Group chung app ↔ bàn phím.
    static let appGroup = "group.com.viettelex"

    /// Key trong App Group. App ghi, bàn phím chỉ đọc.
    static let unlockedKey = "plusUnlocked"
    /// Công tắc giả lập đã mua — CHỈ có tác dụng ở bản Debug.
    static let debugOverrideKey = "plusDebugOverride"

    /// Giới hạn bản miễn phí cho tính năng có "mức" (clipboard ghim).
    static let freePinnedClipLimit = 5
}

/// Tính năng thuộc gói Plus. LUÔN MIỄN PHÍ (không bao giờ thêm vào đây): toàn
/// bộ phần gõ (Telex/VNI, bỏ dấu tự do, khôi phục tiếng Anh, sửa dấu từ đã gõ),
/// gợi ý/emoji/bigram, gõ vuốt, gõ tắt cơ bản, mẫu câu, hàng số, một tay, vuốt
/// ⌫, trackpad, theme hệ thống + sáng/tối + tương phản cao, sao lưu/nhập file.
/// Nguyên tắc: không khoá gì làm việc gõ tệ đi.
enum PlusFeature: String, CaseIterable, Identifiable {
    /// Theme cao cấp + ảnh nền tự chọn.
    case premiumThemes
    /// Thêm dấu cho cả câu gõ không dấu.
    case sentenceDiacritics
    /// Clipboard nâng cao: ghim không giới hạn + chip tách STK/SĐT/OTP.
    /// (Miễn phí vẫn có lịch sử ngắn + ghim tối đa `freePinnedClipLimit`.)
    case advancedClipboard
    /// Đồng bộ cài đặt/gõ tắt/từ đã học qua iCloud.
    case iCloudSync
    /// Công cụ văn bản: HOA/thường/Hoa Đầu Từ/Hoa đầu câu, xoá dấu (Keyboard/TextTools.swift).
    case textTools
    /// Huy hiệu cảm ơn người ủng hộ.
    case thanksBadge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .premiumThemes: return L("Theme cao cấp & ảnh nền")
        case .sentenceDiacritics: return L("Thêm dấu cả câu")
        case .advancedClipboard: return L("Clipboard nâng cao")
        case .iCloudSync: return L("Đồng bộ iCloud")
        case .textTools: return L("Công cụ văn bản")
        case .thanksBadge: return L("Huy hiệu cảm ơn")
        }
    }

    var detail: String {
        switch self {
        case .premiumThemes: return L("Thêm bộ màu bàn phím và đặt ảnh riêng làm nền.")
        case .sentenceDiacritics: return L("Gõ không dấu cả câu, một chạm thêm dấu.")
        case .advancedClipboard: return L("Ghim không giới hạn, chip tách số tài khoản, số điện thoại, mã OTP.")
        case .iCloudSync: return L("Cài đặt, gõ tắt và từ đã học theo bạn sang máy khác.")
        case .textTools: return L("Đổi HOA/thường, hoa đầu từ/đầu câu, xoá dấu tiếng Việt.")
        case .thanksBadge: return L("Dấu ★ nhỏ trong app — lời cảm ơn vì đã ủng hộ.")
        }
    }

    var systemImage: String {
        switch self {
        case .premiumThemes: return "paintpalette"
        case .sentenceDiacritics: return "textformat.abc"
        case .advancedClipboard: return "doc.on.clipboard"
        case .iCloudSync: return "icloud"
        case .textTools: return "wand.and.stars"
        case .thanksBadge: return "star"
        }
    }
}
