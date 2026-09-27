// TextToolsPanelTests — bảng "Công cụ…" (TextToolsPanel.swift): thứ tự nút + phím 1–6,
// dời chọn, toán đặt vị trí cạnh con trỏ, vị trí mục trong menu VietTelex. Chỉ logic
// thuần: không tạo NSPanel, không đăng ký hotkey (test host không được giành phím).
import AppKit
import Carbon.HIToolbox
import XCTest
@testable import VietTelex

final class TextToolsPanelTests: XCTestCase {
    typealias L = TextToolsPanelLogic

    func testToolOrderMatchesOldMenu() {
        XCTAssertEqual(L.tools, [.addTones, .upper, .lower, .title, .sentence, .stripDiacritics])
        XCTAssertEqual(Set(L.tools), Set(TextAction.allCases))
    }

    func testDigitKeysRunTools() {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6]
        let keypad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
                      kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6]
        for i in 0..<6 {
            XCTAssertEqual(L.command(keyCode: digits[i], shift: false), .run(i))
            XCTAssertEqual(L.command(keyCode: keypad[i], shift: false), .run(i))
        }
        XCTAssertNil(L.command(keyCode: kVK_ANSI_7, shift: false))
        XCTAssertNil(L.command(keyCode: kVK_ANSI_0, shift: false))
        XCTAssertNil(L.command(keyCode: kVK_ANSI_1, shift: true))     // ⇧1 = "!" không phải công cụ
        XCTAssertNil(L.command(keyCode: kVK_ANSI_A, shift: false))    // phím chữ đi thẳng vào app
    }

    func testNavigationKeys() {
        XCTAssertEqual(L.command(keyCode: kVK_DownArrow, shift: false), .move(1))
        XCTAssertEqual(L.command(keyCode: kVK_UpArrow, shift: false), .move(-1))
        XCTAssertEqual(L.command(keyCode: kVK_Tab, shift: false), .move(1))
        XCTAssertEqual(L.command(keyCode: kVK_Tab, shift: true), .move(-1))
        XCTAssertEqual(L.command(keyCode: kVK_Return, shift: false), .activate)
        XCTAssertEqual(L.command(keyCode: kVK_ANSI_KeypadEnter, shift: false), .activate)
        XCTAssertEqual(L.command(keyCode: kVK_Escape, shift: false), .cancel)
    }

    func testBindingsUnique() {
        // Mỗi (phím, shift) một lệnh: RegisterEventHotKey trùng sẽ fail.
        var seen = Set<String>()
        for b in L.bindings { XCTAssertTrue(seen.insert("\(b.keyCode)-\(b.shift)").inserted, "\(b)") }
    }

    func testMoveWraps() {
        XCTAssertEqual(L.moved(0, by: -1), 5)
        XCTAssertEqual(L.moved(5, by: 1), 0)
        XCTAssertEqual(L.moved(2, by: 1), 3)
        XCTAssertEqual(L.moved(0, by: 1, count: 0), 0)
    }

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)   // visibleFrame
    private let size = NSSize(width: 230, height: 154)

    func testPlacedBelowCaretLeftAligned() {
        let caret = NSRect(x: 400, y: 500, width: 1, height: 18)
        let o = L.origin(caret: caret, panelSize: size, visible: screen)
        XCTAssertEqual(o.x, 400)
        XCTAssertEqual(o.y, 500 - 4 - 154)
    }

    func testFlipsAboveNearBottom() {
        let caret = NSRect(x: 400, y: 60, width: 1, height: 18)
        let o = L.origin(caret: caret, panelSize: size, visible: screen)
        XCTAssertEqual(o.y, 78 + 4)                  // trên dòng, không che chữ
    }

    func testClampedToRightAndTopEdges() {
        let caret = NSRect(x: 1430, y: 870, width: 1, height: 18)
        let o = L.origin(caret: caret, panelSize: size, visible: screen)
        XCTAssertEqual(o.x, 1440 - 6 - 230)
        XCTAssertLessThanOrEqual(o.y + size.height, 875 - 6)
    }

    func testSecondScreenCoordinates() {
        let second = NSRect(x: -1920, y: 200, width: 1920, height: 1055)
        let caret = NSRect(x: -1900, y: 220, width: 0, height: 16)
        let o = L.origin(caret: caret, panelSize: size, visible: second)
        XCTAssertEqual(o.x, -1900)
        XCTAssertEqual(o.y, 236 + 4)                // sát đáy → lật lên
        XCTAssertTrue(second.contains(NSRect(origin: o, size: size)))
        // Con trỏ sát mép trái → kẹp vào trong lề.
        XCTAssertEqual(L.origin(caret: NSRect(x: -1920, y: 600, width: 0, height: 16),
                                panelSize: size, visible: second).x, -1920 + 6)
    }

    func testCaretRectValidity() {
        let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertTrue(L.isUsableCaretRect(NSRect(x: 100, y: 300, width: 1, height: 18), screens: screens))
        XCTAssertFalse(L.isUsableCaretRect(.zero, screens: screens))
        XCTAssertFalse(L.isUsableCaretRect(NSRect(x: 5000, y: 300, width: 1, height: 18), screens: screens))
        XCTAssertFalse(L.isUsableCaretRect(NSRect(x: CGFloat.nan, y: 300, width: 1, height: 18), screens: screens))
        XCTAssertFalse(L.isUsableCaretRect(NSRect(x: 0, y: 0, width: 1440, height: 900), screens: screens))
    }

    func testMenuHasToolsItemRightBelowSystemSettings() {
        XCTAssertEqual(TelexInputController.trailingMenuKeys(textToolsInMenu: true),
                       ["Settings…", "System Settings…", "Tools…"])
        XCTAssertEqual(TelexInputController.trailingMenuKeys(textToolsInMenu: false),
                       ["Settings…", "System Settings…"])
    }

    func testToolsItemLocalized() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(vi.localizedString(forKey: TelexInputController.toolsItemKey, value: nil, table: nil),
                       "Công cụ…")
    }
}
