// CaretHintTests — gợi ý cạnh con trỏ (MathHint.swift): máy trạng thái phím (hiện → Tab/
// Enter áp dụng, Esc tắt + nuốt, phím khác tắt + đi tiếp), chip số chỉ-dạng-tiền (fixture
// chung number-chips.txt), điều kiện kích hoạt ở dấu cách, và thứ tự nguồn vị trí con trỏ
// (firstRect IMK → AX caret → AX ký tự trước → ước lượng dòng → mép TRÁI ô; không chuột).
// Không tạo cửa sổ nào.
import AppKit
import XCTest
@testable import VietTelex

final class CaretHintTests: XCTestCase {
    private typealias L = CaretHintLogic
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("iOS/KeyboardTests/Fixtures/number-chips.txt")

    override func tearDown() { CaretHint.shared.setPendingForTesting(nil) }

    // MARK: Phím

    func testKeyActionsMath() {
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kReturn, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kKeypadEnter, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kEscape, plain: true), .dismissConsume)
        XCTAssertEqual(L.action(kind: .math, keyCode: 18 /* "1" */, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .math, keyCode: 0 /* a */, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kTab, plain: false), .dismissPass)      // ⇧Tab
        XCTAssertEqual(L.action(kind: .math, keyCode: L.kReturn, plain: false), .dismissPass)   // ⇧Enter
    }

    /// Chip số: chỉ Tab — Enter sau "50k␣" là gửi/xuống dòng, không được cướp.
    func testKeyActionsNumber() {
        XCTAssertEqual(L.action(kind: .number, keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(L.action(kind: .number, keyCode: L.kReturn, plain: true), .dismissPass)
        XCTAssertEqual(L.action(kind: .number, keyCode: L.kEscape, plain: true), .dismissConsume)
        XCTAssertEqual(L.action(kind: .number, keyCode: 49 /* space */, plain: true), .dismissPass)
    }

    func testStateMachineShowAcceptDismiss() {
        let s = CaretSuggestion(kind: .math, display: "= 36", replace: "", insert: "36")
        let hint = CaretHint.shared
        XCTAssertNil(hint.keyAction(keyCode: L.kTab, plain: true))          // chưa hiện: Tab thường
        hint.setPendingForTesting(s)
        XCTAssertTrue(hint.isShowing)
        XCTAssertEqual(hint.candidateStrings, ["= 36"])
        XCTAssertEqual(hint.keyAction(keyCode: L.kTab, plain: true), .accept)
        XCTAssertEqual(hint.take(), s)
        XCTAssertFalse(hint.isShowing)
        XCTAssertNil(hint.take())                                            // chỉ một lần

        hint.setPendingForTesting(s)
        XCTAssertEqual(hint.keyAction(keyCode: 0, plain: true), .dismissPass)
        hint.dismiss()
        XCTAssertFalse(hint.isShowing)
        XCTAssertEqual(hint.candidateStrings, [])
    }

    /// Tap chỉ lo ô nổi; ô ứng viên hệ thống do controller IMK xử lý.
    func testTapIgnoresCandidateSurface() {
        let s = CaretSuggestion(kind: .number, display: "50.000 ₫", replace: "50k ", insert: "50.000 ₫ ")
        CaretHint.shared.setPendingForTesting(s, surface: .candidates)
        XCTAssertNil(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true, panelOnly: true))
        XCTAssertEqual(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true), .accept)
        CaretHint.shared.setPendingForTesting(s, surface: .panel)
        XCTAssertEqual(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true, panelOnly: true), .accept)
    }

    /// Click (ô nổi bỏ qua chuột) ⇒ con trỏ dời ⇒ tắt: Tab sau đó là Tab thường.
    func testClickDismissesPanelHint() {
        CaretHint.shared.setPendingForTesting(CaretSuggestion(kind: .math, display: "= 4", replace: "", insert: "4"))
        CaretHint.shared.dismissForClick(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(CaretHint.shared.isShowing)
        XCTAssertNil(CaretHint.shared.keyAction(keyCode: L.kTab, plain: true))
    }

    // MARK: Chip số

    func testNumberTriggerOnlyAtSpaceAfterDigits() {
        XCTAssertTrue(L.numberWorthChecking(boundary: " ", run: "1tr2", prevRun: ""))
        XCTAssertTrue(L.numberWorthChecking(boundary: " ", run: "50k", prevRun: "giá"))
        XCTAssertTrue(L.numberWorthChecking(boundary: " ", run: "tỷ", prevRun: "2"))          // "2 tỷ"
        XCTAssertFalse(L.numberWorthChecking(boundary: " ", run: "hello", prevRun: "xin"))
        XCTAssertFalse(L.numberWorthChecking(boundary: " ", run: "", prevRun: "5"))           // dấu cách thứ hai
        XCTAssertFalse(L.numberWorthChecking(boundary: ".", run: "50k", prevRun: ""))
        XCTAssertFalse(L.numberWorthChecking(boundary: nil, run: "50k", prevRun: ""))
    }

    func testMoneyChipOnlyMoneyFormat() {
        XCTAssertEqual(L.moneyChip(before: "giá 1tr2 "),
                       CaretSuggestion(kind: .number, display: "1.200.000 ₫", replace: "1tr2 ", insert: "1.200.000 ₫ "))
        XCTAssertEqual(L.moneyChip(before: "mua 2 tỷ ")?.replace, "2 tỷ ")
        XCTAssertEqual(L.moneyChip(before: "giá 1250000đ ")?.display, "1.250.000đ")
        XCTAssertEqual(L.moneyChip(before: "giá -50k ")?.display, "-50.000 ₫")
        XCTAssertNil(L.moneyChip(before: "giá 1250000 "))        // đọc chữ — không có trên macOS
        XCTAssertNil(L.moneyChip(before: "giá 1.200.000 ₫ "))    // đọc chữ + "đồng"
        XCTAssertNil(L.moneyChip(before: "giá 50k"))              // chưa có dấu cách
        XCTAssertNil(L.moneyChip(before: "giá 50k  "))            // hai dấu cách
        XCTAssertNil(L.moneyChip(before: "gọi 0912345678 "))
    }

    /// Mọi ca chip dạng-tiền (có dấu cách cuối) của fixture chung iOS/Android phải ra đúng
    /// cùng kết quả; ca đọc-chữ thì macOS không gợi ý.
    func testSharedFixtureMoneyCases() throws {
        let text = try String(contentsOf: Self.fixture, encoding: .utf8)
        var money = 0
        for line in text.split(separator: "\n") where line.hasPrefix("chip|") {
            let c = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).replacingOccurrences(of: "␣", with: " ") }
            let before = c[1].hasSuffix(" ") ? c[1] : c[1] + " "
            let got = L.moneyChip(before: before)
            if c[2] == "-" || !L.isMoneyFormat(c[2]) {
                if c[2] == "-" || c[1].hasSuffix(" ") { XCTAssertNil(got, "«\(c[1])»") }
                continue
            }
            money += 1
            XCTAssertEqual(got?.display, c[2], "«\(c[1])»")
            XCTAssertEqual(got?.replace.trimmingCharacters(in: .whitespaces),
                           c[3].trimmingCharacters(in: .whitespaces), "«\(c[1])»")
            XCTAssertEqual(got?.insert, c[2] + " ", "«\(c[1])»")
        }
        XCTAssertGreaterThan(money, 8)
    }

    func testKeyStreamBefore() {
        XCTAssertEqual(L.keyStreamBefore(anchored: true, prevRun: "2", run: "tỷ"), "2 tỷ ")
        XCTAssertEqual(L.keyStreamBefore(anchored: true, prevRun: "", run: "50k"), "50k ")
        XCTAssertNil(L.keyStreamBefore(anchored: false, prevRun: "", run: "50k"))
    }

    // MARK: Vị trí

    private let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
    private let field = NSRect(x: 100, y: 400, width: 800, height: 30)

    private func pick(_ values: [L.CaretSource: NSRect], field: NSRect?) -> (L.CaretSource?, [L.CaretSource]) {
        var asked: [L.CaretSource] = []
        let r = L.anchor(field: field, screens: screens) { src in asked.append(src); return values[src] }
        return (r?.source, asked)
    }

    func testAnchorOrderStopsAtFirstGoodSource() {
        let caret = NSRect(x: 180, y: 405, width: 1, height: 18)
        var (src, asked) = pick([.imkFirstRect: caret, .axCaret: caret], field: field)
        XCTAssertEqual(src, .imkFirstRect); XCTAssertEqual(asked, [.imkFirstRect])   // không gọi AX thừa
        (src, asked) = pick([.axCaret: caret], field: field)
        XCTAssertEqual(src, .axCaret); XCTAssertEqual(asked, [.imkFirstRect, .axCaret])
        (src, _) = pick([.axPrevChar: caret], field: field)
        XCTAssertEqual(src, .axPrevChar)
        (src, _) = pick([.axLineEstimate: caret, .fieldStart: field], field: field)
        XCTAssertEqual(src, .axLineEstimate)
        (src, asked) = pick([:], field: field)
        XCTAssertNil(src)                                                            // không chuột
        XCTAssertEqual(asked, L.order)
    }

    /// Chromium/Electron: rect "con trỏ" cỡ cả ô, rect ngoài ô, rect rỗng ở gốc ⇒ bỏ qua.
    func testAnchorRejectsImplausibleCaretRects() {
        let wholeField = field
        let outside = NSRect(x: 1300, y: 100, width: 1, height: 18)
        let zero = NSRect.zero
        let good = NSRect(x: 150, y: 405, width: 0, height: 18)
        let (src, _) = pick([.imkFirstRect: wholeField, .axCaret: outside, .axPrevChar: zero,
                             .axLineEstimate: good], field: field)
        XCTAssertEqual(src, .axLineEstimate)
    }

    /// Nguồn cuối: mép TRÁI-dưới của ô (không phải mép phải như ảnh chụp lỗi).
    func testFieldStartAnchorsLeftBottom() {
        let r = L.anchor(field: field, screens: screens) { $0 == .fieldStart ? self.field : nil }
        XCTAssertEqual(r?.source, .fieldStart)
        XCTAssertEqual(r?.rect.minX, field.minX + 8)
        XCTAssertEqual(r?.rect.minY, field.minY)
        let origin = TextToolsPanelLogic.origin(caret: r!.rect, panelSize: NSSize(width: 120, height: 28),
                                                visible: screens[0])
        XCTAssertLessThan(origin.x, field.midX)
        XCTAssertLessThan(origin.y, field.minY)                                      // dưới ô
    }

    func testLineEstimate() {
        let one = L.lineEstimate(field: field, line: 0, column: 7)
        XCTAssertEqual(one.minX, field.minX + 8 + 7 * 7.5)
        XCTAssertEqual(one.midY, field.midY, accuracy: 0.01)                         // ô một dòng: giữa
        let tall = NSRect(x: 100, y: 100, width: 600, height: 300)
        let l2 = L.lineEstimate(field: tall, line: 2, column: 500)
        XCTAssertEqual(l2.minX, tall.maxX - 8)                                       // kẹp trong ô
        XCTAssertEqual(l2.minY, tall.maxY - 4 - 3 * 18)
        XCTAssertEqual(L.column(before: "abc\n12*3="), 5)
        XCTAssertEqual(L.column(before: "12*3="), 5)
    }

    func testSurfaceChoice() {
        XCTAssertEqual(L.surface(imkPath: true, hasCandidateWindow: true, source: .imkFirstRect), .candidates)
        XCTAssertEqual(L.surface(imkPath: true, hasCandidateWindow: true, source: .axCaret), .panel)
        XCTAssertEqual(L.surface(imkPath: false, hasCandidateWindow: true, source: .imkFirstRect), .panel)
        XCTAssertEqual(L.surface(imkPath: true, hasCandidateWindow: false, source: .imkFirstRect), .panel)
    }

    func testNumberChipsSettingRoundTrip() {
        let before = AppState.shared.numberChips
        defer { AppState.shared.numberChips = before }
        AppState.shared.numberChips = false
        XCTAssertFalse(CaretHint.shared.numberEnabled)
        AppState.shared.numberChips = true
        XCTAssertTrue(CaretHint.shared.numberEnabled)
    }
}
