import XCTest
import UIKit

/// iOS 26+ tự phủ "scroll edge effect" (dải mờ) lên mép view cuộn trong bàn phím —
/// dải kết quả tìm emoji thấp nên bị mờ gần hết (Phil 27/09/2026, tìm "chó"). Mọi
/// view cuộn của bàn phím phải gọi disableKeyboardEdgeEffects().
final class ScrollEdgeEffectTests: XCTestCase {
    private func scrollViews(in v: UIView) -> [UIScrollView] {
        ((v as? UIScrollView).map { [$0] } ?? []) + v.subviews.flatMap { scrollViews(in: $0) }
    }

    private func assertNoEdgeEffects(_ root: UIView, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("chỉ iOS 26+") }
        let views = scrollViews(in: root)
        XCTAssertFalse(views.isEmpty, "\(name): không thấy view cuộn", file: file, line: line)
        for s in views {
            XCTAssertTrue(s.topEdgeEffect.isHidden && s.bottomEdgeEffect.isHidden
                          && s.leftEdgeEffect.isHidden && s.rightEdgeEffect.isHidden,
                          "\(name): \(type(of: s)) còn edge effect", file: file, line: line)
        }
    }

    func testEmojiSearchResults() throws { try assertNoEdgeEffects(EmojiSearchBar(dark: true), "EmojiSearchBar") }
    func testClipboardPanel() throws { try assertNoEdgeEffects(ClipboardPanel(frame: .zero), "ClipboardPanel") }
    func testKaomoji() throws {
        try assertNoEdgeEffects(EmojiPlane.KaomojiView(groups: [(name: "a", items: ["^‿^"])], dark: false), "KaomojiView")
    }
    func testEmojiGrid() throws { try assertNoEdgeEffects(EmojiPlane(dark: false, abcSlot: nil), "EmojiPlane") }
}
