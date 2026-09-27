// KeyGeometry — hình học hàng phím iPhone khớp bàn phím Apple gốc (27/09/2026), THUẦN
// (không UIKit) để unit-test. Người dùng than "cứ 4–5 chữ sai 1": so ảnh cùng máy, hàng
// phím VietTelex nằm CAO hơn stock 5pt (bản đang phát hành: 11pt), phím rộng hơn (lề 3
// thay 6.5) và hàng đáy lệch (phẩy lệch phải 12pt so với "." stock).
//
// Nguồn số đo stock (pt, dọc):
//  • Simulator iPhone 17 (402×874, iOS 27), bàn phím Apple English (US), XCUITest +
//    ảnh chụp @3x: phím chữ 33.3×43.0, bước ngang 39.5, lề 6.67; tâm hàng (tính từ đáy
//    màn hình) 254.5 / 200.5 / 146.5 / 92.5; đáy phím hàng dưới cách đáy màn hình 71.
//    Ô chạm (accessibility frame) mỗi phím = [đỉnh phím, đỉnh phím hàng dưới).
//  • Video người dùng iPhone 393pt iOS 26 (Messenger, English US): 32.5×42.7, bước 38.6,
//    lề 6.5; tâm hàng 254.3 / 200.2 / 146.4 / 92.4 — khớp simulator ±0.3pt.
//  • Extension KHÔNG vẽ được dưới đáy view: đáy view = 75pt trên đáy màn hình (cả hai
//    máy) — thấp hơn đáy phím stock 4pt, nên hàng đáy của mình cao hơn stock tối đa 4pt.
// Bố cục mới (dọc iPhone): 3 hàng chữ bước 54 (khe 10 + phím 44) → đỉnh/tâm phím trùng
// stock ≤0.5pt; hàng đáy = vùng 50, khe trên nó hẹp lại để 3 hàng trên xuống đúng chỗ
// stock. Tổng vùng phím 212 (cũ 218). Phím đáy 43 như stock (khe 7) — bản đầu để 44
// trông cao hơn stock (Phil so ảnh 27/09).
import CoreGraphics

enum KeyGeometry {
    /// Lề trái/phải hàng phím. iPhone như stock (6.5); iPad giữ 3 (đã đo riêng).
    static func sideMargin(pad: Bool) -> CGFloat { pad ? 3 : 6.5 }
    /// Khe giữa 2 hàng phím (lề trên mỗi hàng).
    static let rowGap: CGFloat = 10
    /// Vùng phím chuẩn 4 hàng × 54 trước khi trừ phần cắt ở hàng đáy (iPhone dọc).
    static let phonePortraitBase: CGFloat = 216
    /// iPhone dọc: hàng đáy thấp hơn các hàng khác chừng này (khe trên nó hẹp lại).
    static func bottomRowTrim(pad: Bool, landscape: Bool) -> CGFloat {
        (pad || landscape) ? 0 : 4
    }

    /// Chiều cao phím hàng đáy iPhone dọc = stock 43 (27/09 chiều: Phil so ảnh — hàng đáy
    /// 44 trông cao hơn stock). Vùng hàng đáy giữ 50 → khe trên nó 7 (3 hàng chữ không dời).
    static let phoneBottomKeyHeight: CGFloat = Stock.keyHeight
    /// Lề trên hàng đáy: iPhone dọc = vùng (54 − trim) − phím 43; iPad/ngang = rowGap.
    static func bottomRowTopMargin(pad: Bool, landscape: Bool) -> CGFloat {
        if pad || landscape { return rowGap }
        return phonePortraitBase / 4 - bottomRowTrim(pad: pad, landscape: landscape) - phoneBottomKeyHeight
    }

    /// Bước phím chữ (tâm → tâm) của hàng 10 phím: (W − 2·lề − 9·khe)/10 + khe.
    static func letterPitch(width: CGFloat, margin: CGFloat, gap: CGFloat) -> CGFloat {
        (width - 2 * margin - 9 * gap) / 10 + gap
    }
    /// Lề hàng thụt (hàng a…l = nửa bước phím) — đúng tuyệt đối, không xấp xỉ W/20.
    static func indentedMargin(width: CGFloat, margin: CGFloat, gap: CGFloat, units: CGFloat) -> CGFloat {
        margin + units * letterPitch(width: width, margin: margin, gap: gap)
    }

    /// Chỉ số rect GẦN `p` nhất (khoảng cách tới mép, 0 nếu nằm trong), nil nếu không có
    /// rect nào trong `reach`. Dùng cho khe/mép giữa các nút thật (123, emoji, ⇧, ⌫, số…):
    /// khe chia đôi theo khoảng cách như phím chữ — không còn vùng chết.
    static func nearest(_ p: CGPoint, in rects: [CGRect], reach: CGFloat) -> (index: Int, distance: CGFloat)? {
        var best: (Int, CGFloat)?
        for (i, f) in rects.enumerated() {
            let dx = max(f.minX - p.x, 0, p.x - f.maxX)
            let dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= reach, best == nil || d < best!.1 { best = (i, d) }
        }
        return best.map { (index: $0.0, distance: $0.1) }
    }

    /// Số đo stock iOS 26/27 (xem đầu file) — tâm phím tính từ ĐÁY MÀN HÌNH, pt.
    enum Stock {
        static let rowCentersFromScreenBottom: [CGFloat] = [254.5, 200.5, 146.5, 92.5]
        static let keyHeight: CGFloat = 43
        static let sideMargin: CGFloat = 6.6
        /// Đáy view extension so với đáy màn hình (vùng 🌐/mic hệ thống bên dưới).
        static let viewBottomAboveScreenBottom: CGFloat = 75
        /// Hàng đáy stock trên máy 402pt: 123 / emoji tâm x.
        static let planeKeyMidX: CGFloat = 28.3, emojiKeyMidX: CGFloat = 77.7
        /// Hàng đáy (ô có "."): tâm "." và return, quy từ máy 393 → 402 theo tỉ lệ.
        static let periodMidXFraction: CGFloat = 302.5 / 393, returnMidXFraction: CGFloat = 355.9 / 393
    }

    /// Chữ trên phím iPhone khớp stock iOS 26/27 (đo 27/09/2026, ảnh @3x simulator iPhone 17,
    /// dark, English US; khớp bbox 25 chữ hoa + 23 chữ thường, sai số rms 0.4–0.6px @3x):
    ///  • Stock dùng SF COMPACT (không phải SF Pro): chữ O/C/G/o/c hẹp — SF Pro cỡ nào cũng
    ///    rộng hơn 4–6px. Lấy qua `SystemDesign("NSCTFontUIFontDesignCompact")`.
    ///  • Chữ THƯỜNG to hơn chữ HOA: thường 24.5pt, hoa/số/ký hiệu 22.7pt (Regular). Trước:
    ///    SF Pro 23 cho tất cả → chữ thường nhỏ hơn stock (x-height 35 vs 38px), chữ hoa to hơn.
    ///  • Mọi phím chung MỘT baseline: 28pt dưới đỉnh phím 43 (15pt trên đáy) — x-height chữ
    ///    thường nằm giữa phím, chữ hoa nhô lên 1pt. UIButton căn giữa hộp dòng (ascender +
    ///    descender) → baseline thấp hơn stock 1.3–2.3pt ("chữ nằm thấp").
    ///  • 123/ABC hàng đáy: Compact 18.9 (trước SF 16). #+=/123 hàng 3 plane số: 16.
    enum Typography {
        static let lowercaseSize: CGFloat = 24.5
        static let keycapSize: CGFloat = 22.7
        static let planeKeySize: CGFloat = 18.9
        static let rowToggleSize: CGFloat = 16
        /// Máy không có SF Compact: SF Pro khớp bbox stock tốt nhất ở cỡ này.
        static let fallbackLowercaseSize: CGFloat = 24.5
        static let fallbackKeycapSize: CGFloat = 21.3
        static let stockBaselineFromTop: CGFloat = 28

        /// Nhãn là chữ thường (a, đ, ư…) → cỡ lớn; chữ hoa, số, ký hiệu → cỡ keycap.
        static func isLowercase(_ title: String) -> Bool {
            !title.isEmpty && title == title.lowercased() && title != title.uppercased()
        }
        static func size(for title: String, compact: Bool) -> CGFloat {
            isLowercase(title) ? (compact ? lowercaseSize : fallbackLowercaseSize)
                               : (compact ? keycapSize : fallbackKeycapSize)
        }
        /// Baseline tính từ đỉnh phím cao `h`. Phím ≥43: đáy trùng stock, phần dư nằm trên
        /// (hàng chữ 44 của mình nhô 1pt lên trên) → baseline cách đáy 15 như stock. Phím
        /// thấp hơn (ngang, hàng số): theo tỉ lệ 28/43.
        static func baselineFromTop(keyHeight h: CGFloat) -> CGFloat {
            let k = Stock.keyHeight
            return h >= k ? h - (k - stockBaselineFromTop) : stockBaselineFromTop * h / k
        }
        /// Dịch dọc (âm = lên) cho nhãn đang căn giữa phím bằng hộp dòng của font
        /// (ascender > 0, descender < 0) để baseline về đúng `baselineFromTop`.
        static func titleOffsetY(keyHeight h: CGFloat, ascender: CGFloat, descender: CGFloat) -> CGFloat {
            let natural = h / 2 + (ascender + descender) / 2
            return baselineFromTop(keyHeight: h) - natural
        }
    }
}
