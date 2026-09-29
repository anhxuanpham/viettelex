import XCTest
import UIKit

/// Regression (tester iOS 1.2.x): bàn phím / thanh gợi ý co lại ở Notes, Facebook và
/// lúc ngẫu nhiên — phím lùn/ép; tìm emoji cũng làm phím co. Quy tắc: vùng 4 hàng chữ
/// LUÔN đủ keyArea, dù đổi ô, tìm emoji hay host cấp thiếu chiều cao.
final class KeyboardHeightTests: XCTestCase {
    // MARK: Hàm thuần

    func testKeysModeStripOnTop() {
        let c = KeyLayout.chrome(keyArea: 212, strip: 34, mode: .keys)
        XCTAssertEqual(c, KeyLayout.Chrome(rowsTop: 34, rows: 212, total: 246))
    }

    func testEmojiGridTakesStripSameTotal() {
        let k = KeyLayout.chrome(keyArea: 212, strip: 34, mode: .keys)
        let e = KeyLayout.chrome(keyArea: 212, strip: 34, mode: .emoji)
        XCTAssertEqual(e.total, k.total)            // vào emoji không đổi chiều cao (Telegram)
        XCTAssertEqual(e.rowsTop, 0)
    }

    /// Bug: ô tìm chen vào keyArea ⇒ 4 hàng chữ còn 4/5 chiều cao.
    func testEmojiSearchKeepsFullKeyArea() {
        for strip: CGFloat in [0, 14, 34] {
            let c = KeyLayout.chrome(keyArea: 212, strip: strip, mode: .emojiSearch)
            let bar = KeyLayout.emojiSearchBarHeight(strip: strip)
            XCTAssertEqual(c.rows - bar, 212, "strip \(strip)")      // phần của hàng chữ
            XCTAssertEqual(c.total, c.rowsTop + c.rows)
            XCTAssertGreaterThanOrEqual(c.total, 212 + strip)         // không bao giờ thấp hơn plane chữ
        }
    }

    /// Bug: ô từ chối gợi ý (autocorrect .no — ô tìm Facebook, trait Notes chập chờn) làm
    /// strip 34 → 0 → 34 khi đang hiện; host không cấp lại ⇒ hàng phím bị ép.
    func testStripFollowsGlobalSettingNotField() {
        XCTAssertEqual(KeyLayout.stripHeight(reserved: true, collapsed: false, open: 34), 34)
        XCTAssertEqual(KeyLayout.stripHeight(reserved: true, collapsed: true, open: 34), 14)
        XCTAssertEqual(KeyLayout.stripHeight(reserved: false, collapsed: false, open: 34), 0)
    }

    func testPhoneLandscapeByWidth() {
        XCTAssertFalse(KeyLayout.isPhoneLandscape(width: 440, sceneLandscape: true))   // scene lệch: vẫn dọc
        XCTAssertFalse(KeyLayout.isPhoneLandscape(width: 375, sceneLandscape: nil))
        XCTAssertTrue(KeyLayout.isPhoneLandscape(width: 874, sceneLandscape: false))
        XCTAssertTrue(KeyLayout.isPhoneLandscape(width: 0, sceneLandscape: true))
        XCTAssertFalse(KeyLayout.isPhoneLandscape(width: 0, sceneLandscape: nil))
    }

    // MARK: View thật

    private var width: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 834 : 390 }

    @MainActor private func makeKeyboard(suggestions: Bool = true) -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        host.addSubview(kb)
        kb.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        kb.configureInputKind(.normal)
        kb.setSuggestionsEnabled(suggestions)
        kb.layoutIfNeeded()
        // Host cấp đúng mức xin.
        kb.frame.size.height = kb.debugRequestedHeight
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    @MainActor private func letterRowHeight(_ kb: KeyboardView) throws -> (q: CGFloat, z: CGFloat) {
        (try XCTUnwrap(kb.debugLetterFrame("q")).height, try XCTUnwrap(kb.debugLetterFrame("z")).height)
    }

    @MainActor func testFieldWithoutSuggestionsKeepsHeight() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        let h0 = kb.debugRequestedHeight
        kb.setSuggestionsEnabled(false, reserveStrip: true)   // sang ô mật khẩu / autocorrect .no
        XCTAssertEqual(kb.debugRequestedHeight, h0)
        kb.setSuggestionsEnabled(true, reserveStrip: true)
        XCTAssertEqual(kb.debugRequestedHeight, h0)
    }

    /// Host cấp THIẾU (không cho lại 34pt strip): strip co, phím giữ nguyên chiều cao.
    @MainActor func testHostShortfallSqueezesStripNotKeys() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        let full = try letterRowHeight(kb)
        kb.frame.size.height = kb.debugRequestedHeight - 34
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let squeezed = try letterRowHeight(kb)
        XCTAssertEqual(squeezed.q, full.q, accuracy: 0.5)
        XCTAssertEqual(squeezed.z, full.z, accuracy: 0.5)
        // Không tràn khỏi đỉnh view.
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(kb.debugRowFrames().first).minY, -0.5)
    }

    /// Tìm emoji: 4 hàng chữ cao y như plane chữ.
    @MainActor func testEmojiSearchDoesNotCompressKeys() throws {
        for suggestions in [true, false] {
            let (kb, host) = makeKeyboard(suggestions: suggestions)
            _ = host
            let full = try letterRowHeight(kb)
            let h0 = kb.debugRequestedHeight
            kb.debugEnterEmojiSearch()
            XCTAssertTrue(kb.debugInEmojiSearch)
            XCTAssertGreaterThanOrEqual(kb.debugRequestedHeight, h0)
            kb.frame.size.height = kb.debugRequestedHeight
            kb.setNeedsLayout(); kb.layoutIfNeeded()
            let s = try letterRowHeight(kb)
            XCTAssertEqual(s.q, full.q, accuracy: 0.5, "suggestions \(suggestions)")
            XCTAssertEqual(s.z, full.z, accuracy: 0.5, "suggestions \(suggestions)")
        }
    }
}
