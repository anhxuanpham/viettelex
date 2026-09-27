// Bảng sửa văn bản — logic THUẦN (không UIKit), pinned by TextEditingTests.
//
// GIỚI HẠN iOS (keyboard extension, UITextDocumentProxy):
//  • KHÔNG tạo / mở rộng được vùng chọn (không có setSelectedRange) ⇒ không có
//    "Chọn", "Chọn từ", "Chọn hết".
//  • KHÔNG gọi được menu Cut/Copy/Paste/Undo của app host ⇒ không "Hoàn tác" /
//    "Làm lại"; sao chép / cắt chỉ với phần người dùng ĐANG CHỌN (selectedText, iOS 16+).
//  • Clipboard (sao chép / cắt / dán) cần Toàn quyền truy cập (Full Access).
//  • Lên / xuống chỉ theo ký tự xuống dòng trong context host cho (VerticalMove) —
//    dòng tự ngắt không đi được; đầu / cuối dòng cũng theo ngắt dòng logic.
// Android làm đủ qua InputConnection (android/.../ime/EditPanel.kt).
import Foundation

enum TextEditAction: CaseIterable {
    case left, right, up, down, lineStart, lineEnd
    case copy, cut, paste, delete
    /// Về plane chữ.
    case close
    /// Bật/tắt chế độ một tay (iPhone).
    case oneHand
    // Android có, iOS KHÔNG làm được (xem đầu file) — không bao giờ hiện trên iOS.
    case select, selectWord, selectAll, undo, redo

    var supportedOnIOS: Bool {
        switch self {
        case .select, .selectWord, .selectAll, .undo, .redo: return false
        default: return true
        }
    }

    /// Giữ để lặp (như giữ ⌫).
    var repeats: Bool {
        switch self {
        case .left, .right, .up, .down, .delete: return true
        default: return false
        }
    }
}

enum TextEditing {
    /// Trạng thái bật/tắt của các nút phụ thuộc quyền / vùng chọn.
    struct Caps: Equatable {
        /// Full Access + có phần đang chọn (selectedText không rỗng).
        var canCopyCut = false
        /// Full Access + clipboard có chữ.
        var canPaste = false
    }

    /// Lưới 3×4 (trên → dưới); nil = ô trống (iPad: không có một tay).
    static func grid(oneHandAvailable: Bool) -> [[TextEditAction?]] {
        [
            [.lineStart, .up, .lineEnd, .copy],
            [.left, .down, .right, .cut],
            [.close, oneHandAvailable ? .oneHand : nil, .delete, .paste],
        ]
    }

    /// Nhãn ngắn của công cụ văn bản trên hàng cuối bảng sửa (5 ô chung một hàng; danh
    /// sách đầy đủ ở lưới mẫu câu dùng TextTool.label). Android: EditPanel.toolTitle.
    static func toolTitle(_ t: TextTool) -> String {
        switch t {
        case .upper: return "HOA"
        case .lower: return "thường"
        case .title: return "Hoa Từ"
        case .sentence: return "Hoa câu"
        case .stripDiacritics: return "Xoá dấu"
        }
    }

    static func isEnabled(_ a: TextEditAction, caps: Caps) -> Bool {
        switch a {
        case .copy, .cut: return caps.canCopyCut
        case .paste: return caps.canPaste
        default: return a.supportedOnIOS
        }
    }

    static func title(_ a: TextEditAction) -> String {
        switch a {
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .lineStart: return "⇤"
        case .lineEnd: return "⇥"
        case .copy: return "Sao chép"
        case .cut: return "Cắt"
        case .paste: return "Dán"
        case .delete: return ""
        case .close: return "ABC"
        case .oneHand: return "Một tay"
        case .select: return "Chọn"
        case .selectWord: return "Chọn từ"
        case .selectAll: return "Chọn hết"
        case .undo: return "Hoàn tác"
        case .redo: return "Làm lại"
        }
    }

    /// Dời (UTF-16, ≤ 0) về đầu dòng logic: phần sau ngắt dòng cuối của `before`.
    static func lineStartOffset(before: String) -> Int {
        guard let i = before.lastIndex(where: { $0.isNewline }) else { return -before.utf16.count }
        return -before[before.index(after: i)...].utf16.count
    }

    /// Dời (UTF-16, ≥ 0) tới cuối dòng logic: phần trước ngắt dòng đầu của `after`.
    static func lineEndOffset(after: String) -> Int {
        guard let i = after.firstIndex(where: { $0.isNewline }) else { return after.utf16.count }
        return after[..<i].utf16.count
    }
}
