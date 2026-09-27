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
// stock ≤0.5pt; hàng đáy = khe 6 + phím 44 (vùng 50) — phím đáy vẫn cao 44, khe trên nó
// hẹp lại để 3 hàng trên xuống đúng chỗ stock. Tổng vùng phím 212 (cũ 218).
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
}
