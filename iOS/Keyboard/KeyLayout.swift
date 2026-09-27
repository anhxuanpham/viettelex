// KeyLayout — bảng tỉ lệ phím THUẦN (không UIKit) để unit-test được. KeyboardView
// dựng constraint từ đây. Quy tắc (bug 26/09/2026: nút 🌐 hàng đáy iPad nhảy
// size; hàng 1 iPad thành 12 phím bằng nhau sau khi từ mẫu câu về): mỗi hàng chỉ
// được ĐÚNG MỘT phím co giãn (units = nil), hoặc không phím nào nếu hàng đó là
// hàng neo quyết định bề rộng phím chữ. Hai phím "tự do" = UIKit chia tuỳ lúc.
import CoreGraphics

enum KeyLayout {
    struct Key { let id: String; let units: CGFloat? }   // nil = co giãn

    /// iPad plane chữ — units = bội số bề rộng phím chữ q. Hàng 1 KHÔNG có phím
    /// co giãn: nó quyết định q. Đo ảnh iPad Pro 11" stock.
    static let padRows: [[Key]] = [
        [Key(id: "tab", units: 1.31)] + letters("qwertyuiop") + [Key(id: "back", units: 1.31)],
        [Key(id: "caps", units: 1.67)] + letters("asdfghjkl") + [Key(id: "return", units: nil)],
        [Key(id: "shiftL", units: 2.2)] + letters("zxcvbnm")
            + [Key(id: "!,", units: 1), Key(id: "?.", units: 1), Key(id: "shiftR", units: nil)],
    ]
    static let padAnchorRow = 0

    /// Hàng phím số tuỳ chọn (Settings → "Hàng phím số"), nằm TRÊN hàng tab.
    /// Cùng 12 phím như hàng neo nên số 1…0 thẳng cột q…p: "-" rộng như tab,
    /// "=" co giãn (= đúng phần của ⌫). Không có ký tự phụ vuốt xuống.
    static let padNumberRow: [Key] =
        [Key(id: "-", units: 1.31)] + letters("1234567890") + [Key(id: "=", units: nil)]
    static let digits = "1234567890".map { String($0) }

    /// Hàng số thấp hơn hàng chữ như Gboard — tổng bàn phím tăng ít.
    static let numberRowRatio: CGFloat = 0.75

    /// Tổng chiều cao vùng phím. `base` = 4 hàng chuẩn, `adjust` = ±pt MỖI hàng
    /// (Settings). Hàng số bật → thêm 0.75 hàng, cho MỌI plane (bàn phím không đổi
    /// chiều cao khi chuyển 123/emoji — host relayout dở dang, xem updateSuggestionChrome).
    static func keyAreaHeight(base: CGFloat, adjust: CGFloat, numberRow: Bool) -> CGFloat {
        let unit = (base + adjust * 4) / 4
        return unit * (numberRow ? 4 + numberRowRatio : 4)
    }

    /// Hàng đáy — units = PHẦN của bề rộng hàng (multiplier theo stack width).
    /// iPad full plane chữ = stock [🌐][.?123][☺︎][space][.?123][⌨︎] — KHÔNG phím ","
    /// riêng (phím "!," hàng 3 đã có ","; Phil 27/09). Đo stock Pro 11": 58.7 / 88 trên 834.
    static let padBottom: [Key] = [
        Key(id: "globe", units: 0.068), Key(id: "plane", units: 0.068),
        Key(id: "emoji", units: 0.068), Key(id: "space", units: nil),
        Key(id: "plane2", units: 0.102), Key(id: "dismiss", units: 0.102),
    ]
    /// iPhone: đo stock iOS 26/27 (KeyGeometry): 123 / emoji 43.3pt trên 402 (0.108), "."
    /// bằng phím chữ (0.083), return 0.156 — cũ 0.12/0.12/0.075/0.14 làm phẩy lệch phải
    /// 12pt, return 7pt so với chỗ ngón quen.
    static let phoneBottom: [Key] = [
        Key(id: "plane", units: 0.108), Key(id: "globe", units: 0.10),
        Key(id: "emoji", units: 0.108), Key(id: "space", units: nil),
        Key(id: "comma", units: 0.083), Key(id: "return", units: 0.156),
    ]

    // MARK: iPad — hai kiểu bàn phím stock iPadOS 27 (đo simulator 27/09/2026)
    //  • full (Air/Pro 11", 13"): có tab + ⇪, icon/nhãn chức năng dạt góc dưới.
    //  • compact (iPad mini, cạnh ngắn màn hình < 800pt): KHÔNG tab/⇪, ⌫ cuối hàng 1,
    //    ⇧ hai đầu hàng 3, icon + nhãn (123/ABC/#+=) nằm GIỮA phím, chữ nhãn to.
    // Plane số/ký hiệu cùng khung phím với plane chữ của kiểu đó (stock y hệt), ký tự phụ
    // xám phía trên = vuốt xuống / giữ phím. Ô undo/redo của stock: bàn phím bên thứ ba
    // không chạm được undo manager của app → ô undo = ",", ô redo = "₫".
    enum PadStyle: Equatable { case full, compact }
    static func padStyle(screenShortSide s: CGFloat) -> PadStyle { s < 800 ? .compact : .full }

    /// ⌫ / ⇧ phải của kiểu compact = 1.23 phím chữ (stock mini: 79.5 / 66.5 bước phím).
    static let compactWideUnits: CGFloat = 1.23
    /// Khoảng thụt hàng 2 kiểu compact (khoảng trống TRƯỚC a/@/¥, chưa kể khe): stock mini
    /// a lệch q 26.5pt = khe 10 + 16.5 ≈ 0.29 phím chữ.
    static let compactIndentUnits: CGFloat = 0.29

    static func padLetterRows(_ s: PadStyle) -> [[Key]] {
        switch s {
        case .full: return padRows
        case .compact: return [
            letters("qwertyuiop") + [Key(id: "back", units: compactWideUnits)],
            [Key(id: "indent", units: compactIndentUnits)] + letters("asdfghjkl") + [Key(id: "return", units: nil)],
            [Key(id: "shiftL", units: 1)] + letters("zxcvbnm")
                + [Key(id: "!,", units: 1), Key(id: "?.", units: 1), Key(id: "shiftR", units: nil)],
        ]
        }
    }

    /// Plane số (.?123) iPad — thứ tự phím đúng stock. id = ký tự của phím (trừ phím chức
    /// năng: tab/back/return/more/more2/undo/indent; "!," "?." = phím 2 tầng).
    static func padNumberRows(_ s: PadStyle) -> [[Key]] {
        padSymbolic(s, row2: ["@", "#", "$", "&", "*", "(", ")", "'", "\""],
                    row3: ["%", "-", "+", "=", "/", ";", ":", "!,", "?."], slot: "undo")
    }
    /// Plane ký hiệu (#+=) iPad — đúng stock.
    static func padSymbolRows(_ s: PadStyle) -> [[Key]] {
        padSymbolic(s, row2: ["¥", "£", "€", "_", "^", "[", "]", "{", "}"],
                    row3: ["§", "|", "~", "…", "\\", "<", ">", "!", "?"], slot: "redo")
    }
    private static func padSymbolic(_ s: PadStyle, row2: [String], row3: [String], slot: String) -> [[Key]] {
        let digits = letters("1234567890")
        let r2 = row2.map { Key(id: $0, units: 1) }, r3 = row3.map { Key(id: $0, units: 1) }
        switch s {
        case .full: return [
            [Key(id: "tab", units: 1.31)] + digits + [Key(id: "back", units: 1.31)],
            [Key(id: slot, units: 1.67)] + r2 + [Key(id: "return", units: nil)],
            [Key(id: "more", units: 2.2)] + r3 + [Key(id: "more2", units: nil)],
        ]
        case .compact: return [
            digits + [Key(id: "back", units: compactWideUnits)],
            [Key(id: "indent", units: compactIndentUnits)] + r2 + [Key(id: "return", units: nil)],
            [Key(id: "more", units: 1)] + r3 + [Key(id: "more2", units: nil)],
        ]
        }
    }
    /// Nội dung ô undo (plane số) / redo (plane ký hiệu) của stock.
    static func padSlotTitle(_ id: String) -> String? {
        switch id { case "undo": return ","; case "redo": return "₫"; default: return nil }
    }

    /// Ký tự phụ (xám, trên) của phím plane số iPad — stock iPadOS 27. Vuốt xuống / giữ → ra.
    static let padNumberHints: [String: String] = [
        "@": "¥", "#": "£", "$": "€", "&": "_", "*": "^", "(": "[", ")": "]", "'": "{", "\"": "}",
        "%": "§", "-": "|", "+": "~", "=": "…", "/": "\\", ";": "<", ":": ">",
    ]

    /// Hàng đáy iPad theo kiểu + plane. `letters`: [🌐][.?123][☺︎][space][.?123][⌨︎] (stock,
    /// full lẫn mini — "," nằm ở phím "!," hàng 3);
    /// plane số/ký hiệu full: [🌐][ABC][☺︎][space][ABC][⌨︎] (stock không có phẩy);
    /// compact số/ký hiệu: [🌐][ABC][☺︎][space][ô undo/redo][ABC][⌨︎].
    /// units = phần bề rộng hàng (compact: stock mini 59 / 93.5 trên 744).
    static func padBottomRow(_ s: PadStyle, letters: Bool) -> [Key] {
        switch (s, letters) {
        case (.full, true): return padBottom
        case (.full, false): return [
            Key(id: "globe", units: 0.068), Key(id: "plane", units: 0.068),
            Key(id: "emoji", units: 0.068), Key(id: "space", units: nil),
            Key(id: "plane2", units: 0.102), Key(id: "dismiss", units: 0.102),
        ]
        case (.compact, true): return [
            Key(id: "globe", units: 0.079), Key(id: "plane", units: 0.079),
            Key(id: "emoji", units: 0.079), Key(id: "space", units: nil),
            Key(id: "plane2", units: 0.126),
            Key(id: "dismiss", units: 0.126),
        ]
        case (.compact, false): return [
            Key(id: "globe", units: 0.079), Key(id: "plane", units: 0.079),
            Key(id: "emoji", units: 0.079), Key(id: "space", units: nil),
            Key(id: "slot", units: 0.079), Key(id: "plane2", units: 0.079),
            Key(id: "dismiss", units: 0.079),
        ]
        }
    }

    /// Vuốt XUỐNG trên phím iPad (ký tự phụ): đi xuống quá ngưỡng và dọc nhiều hơn ngang.
    static func isPadFlick(dx: CGFloat, dy: CGFloat, threshold: CGFloat) -> Bool {
        dy > threshold && dy > abs(dx)
    }

    static func units(_ id: String, in row: [Key]) -> CGFloat? {
        row.first { $0.id == id }?.units
    }

    private static func letters(_ s: String) -> [Key] {
        s.map { Key(id: String($0), units: 1) }
    }

    // MARK: kiểm tra (test dùng)

    static func flexCount(_ row: [Key]) -> Int { row.filter { $0.units == nil }.count }

    /// Bề rộng phím chữ q do hàng neo quyết định.
    static func padLetterWidth(rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        padLetterWidth(anchor: padRows[padAnchorRow], rowWidth: w, gap: gap, margin: margin)
    }
    static func padLetterWidth(anchor row: [Key], rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        let units = row.compactMap(\.units).reduce(0, +)
        return (w - 2 * margin - gap * CGFloat(row.count - 1)) / units
    }

    /// Bề rộng phím co giãn của hàng `i` (≤ 0 = tràn hàng).
    static func padFlexWidth(row i: Int, rowWidth w: CGFloat, gap: CGFloat, margin: CGFloat) -> CGFloat {
        padFlexWidth(padRows[i], rowWidth: w, gap: gap, margin: margin)
    }
    static func padFlexWidth(_ row: [Key], anchor: [Key]? = nil, rowWidth w: CGFloat,
                             gap: CGFloat, margin: CGFloat) -> CGFloat {
        let q = padLetterWidth(anchor: anchor ?? padRows[padAnchorRow], rowWidth: w, gap: gap, margin: margin)
        let fixed = row.compactMap(\.units).reduce(0, +) * q
        return w - 2 * margin - gap * CGFloat(row.count - 1) - fixed
    }
}
