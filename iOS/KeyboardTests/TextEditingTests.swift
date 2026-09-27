import XCTest
import UIKit

/// Bảng sửa văn bản iOS (27/09/2026): hàm thuần đầu/cuối dòng, lưới chỉ gồm nút iOS làm
/// được, bật/tắt theo quyền + vùng chọn, đường nút → controller.
final class TextEditingTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testLineStartOffset() {
        XCTAssertEqual(TextEditing.lineStartOffset(before: "hello"), -5)
        XCTAssertEqual(TextEditing.lineStartOffset(before: "ab\ncde"), -3)
        XCTAssertEqual(TextEditing.lineStartOffset(before: "ab\n"), 0)
        XCTAssertEqual(TextEditing.lineStartOffset(before: "x\r\nyz"), -2)     // \r\n một ngắt
        XCTAssertEqual(TextEditing.lineStartOffset(before: "a\nb😀"), -3)      // UTF-16
        XCTAssertEqual(TextEditing.lineStartOffset(before: ""), 0)
    }

    func testLineEndOffset() {
        XCTAssertEqual(TextEditing.lineEndOffset(after: "tail"), 4)
        XCTAssertEqual(TextEditing.lineEndOffset(after: "ab\ncd"), 2)
        XCTAssertEqual(TextEditing.lineEndOffset(after: "\nx"), 0)
        XCTAssertEqual(TextEditing.lineEndOffset(after: "😀x\u{2029}y"), 3)
        XCTAssertEqual(TextEditing.lineEndOffset(after: ""), 0)
    }

    /// iOS không tạo được vùng chọn / không gọi được menu app ⇒ các nút đó không bao giờ có.
    func testGridOnlyHasSupportedActions() {
        let cells = TextEditing.grid(oneHandAvailable: true).flatMap { $0 }.compactMap { $0 }
        XCTAssertTrue(cells.allSatisfy(\.supportedOnIOS))
        let supported = Set(TextEditAction.allCases.filter(\.supportedOnIOS))
        XCTAssertEqual(Set(cells), supported)
        XCTAssertEqual(cells.count, Set(cells).count)
        for a in [TextEditAction.select, .selectWord, .selectAll, .undo, .redo] {
            XCTAssertFalse(a.supportedOnIOS)
        }
        let pad = TextEditing.grid(oneHandAvailable: false).flatMap { $0 }
        XCTAssertFalse(pad.contains(.oneHand))
        XCTAssertEqual(pad.count, 12)
    }

    func testEnablementFollowsCaps() {
        let none = TextEditing.Caps()
        XCTAssertFalse(TextEditing.isEnabled(.copy, caps: none))
        XCTAssertFalse(TextEditing.isEnabled(.cut, caps: none))
        XCTAssertFalse(TextEditing.isEnabled(.paste, caps: none))
        XCTAssertTrue(TextEditing.isEnabled(.left, caps: none))
        XCTAssertTrue(TextEditing.isEnabled(.lineEnd, caps: none))
        let sel = TextEditing.Caps(canCopyCut: true, canPaste: false)
        XCTAssertTrue(TextEditing.isEnabled(.copy, caps: sel))
        XCTAssertTrue(TextEditing.isEnabled(.cut, caps: sel))
        XCTAssertFalse(TextEditing.isEnabled(.paste, caps: sel))
        XCTAssertFalse(TextEditing.isEnabled(.undo, caps: TextEditing.Caps(canCopyCut: true, canPaste: true)))
    }

    // MARK: panel trong KeyboardView

    @MainActor private func makeKeyboard() -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        let host = UIView(frame: CGRect(x: 0, y: 0, width: isPad ? 834 : 390, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.layoutIfNeeded()
        return (kb, host)
    }

    @MainActor func testPanelOpensWithCapsAndCloses() throws {
        let (kb, _) = makeKeyboard()
        var caps = TextEditing.Caps()
        kb.editCapabilities = { caps }
        kb.toggleEditPanel()
        kb.layoutIfNeeded()
        let panel = try XCTUnwrap(kb.debugEditPanel)
        XCTAssertTrue(kb.isEditPanelOpen)
        let states = Dictionary(panel.debugButtons.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(states[.copy], false)
        XCTAssertEqual(states[.cut], false)
        XCTAssertEqual(states[.paste], false)
        XCTAssertEqual(states[.left], true)
        XCTAssertEqual(states[.oneHand] != nil, !isPad)
        caps = TextEditing.Caps(canCopyCut: true, canPaste: true)
        kb.refreshEditPanel()
        XCTAssertTrue(panel.debugButtons.allSatisfy { $0.1 })
        panel.debugTap(.close)
        kb.layoutIfNeeded()
        XCTAssertNil(kb.debugEditPanel)
        XCTAssertFalse(kb.isEditPanelOpen)
        XCTAssertNotNil(kb.debugLetterFrame("q"))
    }

    @MainActor func testPanelActionsReachControllerOnce() throws {
        let (kb, _) = makeKeyboard()
        var got: [TextEditAction] = []
        kb.onEditAction = { got.append($0) }
        kb.editCapabilities = { TextEditing.Caps(canCopyCut: true, canPaste: true) }
        kb.toggleEditPanel()
        let panel = try XCTUnwrap(kb.debugEditPanel)
        for a in [TextEditAction.left, .up, .lineStart, .lineEnd, .copy, .cut, .paste, .delete] { panel.debugTap(a) }
        XCTAssertEqual(got, [.left, .up, .lineStart, .lineEnd, .copy, .cut, .paste, .delete])
    }

    @MainActor func testPanelOneHandButtonAndNarrowing() throws {
        guard !isPad else { return }
        let (kb, _) = makeKeyboard()
        kb.toggleEditPanel()
        let panel = try XCTUnwrap(kb.debugEditPanel)
        panel.debugTap(.oneHand)
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.oneHand, .right)
        let f = kb.convert(panel.bounds, from: panel)
        XCTAssertEqual(f.width, 390 * OneHand.ratio, accuracy: 0.5)
        XCTAssertEqual(f.maxX, 390, accuracy: 0.5)
        XCTAssertEqual(kb.debugRailFrames().count, 2)
    }

    /// Nối bảng sửa ↔ công cụ văn bản: Plus mở ⇒ hàng công cụ cuối bảng, chạm gọi
    /// onTextTool và Ở LẠI bảng sửa; Plus khoá ⇒ không có hàng; bật/tắt khi đang mở dựng lại.
    @MainActor func testPanelTextToolsRow() throws {
        let (kb, _) = makeKeyboard()
        var got: [TextTool] = []
        kb.onTextTool = { got.append($0) }
        kb.toggleEditPanel()
        XCTAssertEqual(try XCTUnwrap(kb.debugEditPanel).debugTools, [])
        kb.textToolsEnabled = true
        let panel = try XCTUnwrap(kb.debugEditPanel)
        XCTAssertEqual(panel.debugTools, TextTool.allCases)
        panel.debugTapTool(.upper)
        panel.debugTapTool(.stripDiacritics)
        XCTAssertEqual(got, [.upper, .stripDiacritics])
        XCTAssertTrue(kb.isEditPanelOpen)
        kb.textToolsEnabled = false
        XCTAssertEqual(try XCTUnwrap(kb.debugEditPanel).debugTools, [])
        for t in TextTool.allCases { XCTAssertFalse(TextEditing.toolTitle(t).isEmpty) }
    }
}
