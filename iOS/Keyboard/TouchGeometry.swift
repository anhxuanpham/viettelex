// TouchGeometry — điểm chọn phím từ điểm chạm (pure, test được, 25/09/2026).
import CoreGraphics

enum TouchGeometry {
    /// Tâm vùng da chạm nằm THẤP hơn điểm mắt nhắm → gõ nhanh hay trượt xuống hàng
    /// dưới (h→b, i→j — screenshot 25/09/2026). Như stock, dời điểm chọn phím lên.
    static let yOffset: CGFloat = 4
    static func keySelectionPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: p.y - yOffset)
    }
    /// Như trên nhưng không đẩy điểm lên QUÁ đỉnh vùng phím `top`: chạm sát mép trên hàng
    /// đầu (khe trên q…p) trước đây bị dời ra ngoài vùng phím → router bỏ → mất phím.
    static func keySelectionPoint(_ p: CGPoint, top: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: max(p.y - yOffset, min(p.y, top)))
    }
}

import UIKit

extension UIScrollView {
    /// iOS 26+ tự vẽ "scroll edge effect" (dải mờ + vạch cứng) ở mép view cuộn nằm
    /// dưới một "bar" — trong bàn phím nó coi thanh gợi ý là bar và phủ dải ~30pt lên
    /// hàng emoji / mẫu câu đầu (Telegram, 25/09/2026). Bàn phím không cần hiệu ứng này.
    func disableKeyboardEdgeEffects() {
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
            leftEdgeEffect.isHidden = true
            rightEdgeEffect.isHidden = true
        }
    }
}
