// MathHintTests — "Hiện kết quả phép tính" trên macOS (MathHint.swift): cùng fixture với
// iOS/Android (iOS/KeyboardTests/Fixtures/math-results.txt, dòng "chip") để bản biên dịch
// chung MathResults.swift trong app Mac cho đúng kết quả; + điều kiện phím "=" và Tab.
// Không tạo NSPanel (chỉ logic + trạng thái dưới khoá).
import AppKit
import XCTest
@testable import VietTelex

final class MathHintTests: XCTestCase {
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("iOS/KeyboardTests/Fixtures/math-results.txt")

    func testSharedFixtureChipCases() throws {
        let text = try String(contentsOf: Self.fixture, encoding: .utf8)
        var n = 0
        for line in text.split(separator: "\n") where line.hasPrefix("chip|") {
            let c = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).replacingOccurrences(of: "␣", with: " ") }
            n += 1
            XCTAssertEqual(MathHintLogic.result(beforeCaret: c[1]) ?? "-", c[2], "chip «\(c[1])»")
        }
        XCTAssertGreaterThan(n, 10)
    }

    func testCommonCases() {
        XCTAssertEqual(MathHintLogic.result(beforeCaret: "12*3="), "36")
        XCTAssertEqual(MathHintLogic.result(beforeCaret: "giá 200+10%="), "220")
        XCTAssertNil(MathHintLogic.result(beforeCaret: "a=b"))
        XCTAssertNil(MathHintLogic.result(beforeCaret: "x = 5"))
        XCTAssertNil(MathHintLogic.result(beforeCaret: "12*3"))        // chưa có "="
        XCTAssertEqual(MathHintLogic.label("36"), "= 36")
    }

    func testTriggerOnlyPlainEquals() {
        XCTAssertTrue(MathHintLogic.isTrigger(characters: "=", modifiers: []))
        XCTAssertTrue(MathHintLogic.isTrigger(characters: "=", modifiers: [.shift]))   // bàn phím có "=" cần ⇧
        XCTAssertFalse(MathHintLogic.isTrigger(characters: "=", modifiers: [.command]))
        XCTAssertFalse(MathHintLogic.isTrigger(characters: "+", modifiers: []))
        XCTAssertFalse(MathHintLogic.isTrigger(characters: nil, modifiers: []))
    }

    /// Không có ô ⇒ Tab không bị giữ; dismiss khi không có gì là vô hại.
    func testTabNotConsumedWithoutHint() {
        MathHint.shared.dismiss()
        XCTAssertFalse(MathHint.shared.isShowing)
        XCTAssertNil(MathHint.shared.consumeTab())
    }

    /// Công tắc lưu được và MathHint đọc lại cờ ngay (không phải khởi động lại).
    func testSettingRoundTripReloadsFlag() {
        let before = AppState.shared.mathResults
        defer { AppState.shared.mathResults = before }
        AppState.shared.mathResults = false
        XCTAssertFalse(MathHint.shared.enabled)
        AppState.shared.mathResults = true
        XCTAssertTrue(MathHint.shared.enabled)
    }
}
