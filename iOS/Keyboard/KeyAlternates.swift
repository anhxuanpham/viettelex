// KeyAlternates — giữ phím chữ để ra ký tự phụ (issue #98, kiểu Gboard): hàng trên
// q…p → 1…0, hàng 2–3 → ký hiệu. Phần THUẦN, bản Kotlin song sinh:
// android/keyboard/src/main/kotlin/com/viettelex/keyboard/KeyAlternates.kt — sửa ở đây
// thì sửa y hệt bên kia (bảng khớp fixture chung Fixtures/key-alternates.txt).
//
// Bảng ký hiệu theo Gboard tiếng Anh (a@ s# … m?), riêng d → ₫ (Gboard Việt để "đ" —
// Telex đã có dd; "$" vẫn ở bàn 123). Không trùng ký tự nào giữa các phím.
import CoreGraphics
import Foundation

enum KeyAlternates {
    static let digits: [Character: String] = [
        "q": "1", "w": "2", "e": "3", "r": "4", "t": "5",
        "y": "6", "u": "7", "i": "8", "o": "9", "p": "0",
    ]
    static let symbols: [Character: String] = [
        "a": "@", "s": "#", "d": "₫", "f": "_", "g": "&", "h": "-", "j": "+", "k": "(", "l": ")",
        "z": "*", "x": "\"", "c": "'", "v": ":", "b": ";", "n": "!", "m": "?",
    ]

    /// Giữ bao lâu thì thành ký tự phụ — ngắn hơn giữ ⌫/emoji (0,45–0,5 s), dài hơn
    /// trackpad phím cách (0,3 s) để gõ chậm không lỡ tay.
    static let holdDelay: TimeInterval = 0.38
    /// Ngón trôi quá ngần này (pt/dp) trước khi đủ giờ ⇒ không phải giữ (vuốt / trượt).
    static let slop: CGFloat = 10

    /// Bảng đang dùng. Hàng số bật ⇒ bỏ số (đã có phím riêng). iPad có ký tự phụ vuốt
    /// xuống riêng; VoiceOver/TalkBack: giữ phím là cử chỉ của trình đọc ⇒ tắt hết.
    /// Rỗng ⇒ không hẹn giờ, không vẽ nhãn (0 chi phí).
    static func map(numbers: Bool, symbols sym: Bool, numberRow: Bool,
                    isPad: Bool = false, accessibility: Bool = false) -> [Character: String] {
        guard !isPad, !accessibility else { return [:] }
        var m: [Character: String] = [:]
        if numbers, !numberRow { m.merge(digits) { a, _ in a } }
        if sym { m.merge(symbols) { a, _ in a } }
        return m
    }

    /// Công tắc số chỉ có nghĩa (và chỉ hiện trong app) khi hàng phím số TẮT.
    static func numbersSettingVisible(numberRow: Bool) -> Bool { !numberRow }

    /// Theo dõi MỘT ngón đang giữ phím có ký tự phụ. Không đồng hồ bên trong: view hẹn
    /// giờ `holdDelay` rồi gọi `fire()`; mọi hủy (trôi, ngón khác, thành vuốt) đi qua đây.
    struct Hold: Equatable {
        let alt: String
        let start: CGPoint
        private(set) var fired = false
        private(set) var cancelled = false

        init(alt: String, start: CGPoint) { self.alt = alt; self.start = start }

        /// Ngón di chuyển; true nếu vừa hủy vì trôi quá slop (trước khi bắn).
        mutating func move(to p: CGPoint) -> Bool {
            guard !fired, !cancelled else { return false }
            if hypot(p.x - start.x, p.y - start.y) > KeyAlternates.slop { cancelled = true; return true }
            return false
        }
        /// Ngón khác chạm / cú vuốt bắt đầu / bàn phím ẩn.
        mutating func cancel() { if !fired { cancelled = true } }
        /// Hết giờ: true nếu thành ký tự phụ (chưa hủy).
        mutating func fire() -> Bool {
            guard !fired, !cancelled else { return false }
            fired = true
            return true
        }
        /// Nhấc tay: ký tự phụ phải chèn (thay chữ đã chèn lúc chạm), nil = chạm thường.
        var commit: String? { fired ? alt : nil }
    }
}
