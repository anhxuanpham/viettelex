// MathResultsTests — "Hiện kết quả phép tính" theo fixture chung Fixtures/math-results.txt
// (cùng bộ ca với android MathResultsTests.kt) + vị trí chip trên thanh + điều kiện ô nhập.
import UIKit
import XCTest

final class MathResultsTests: XCTestCase {
    private func fixtureLines() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: MathResultsTests.self)
            .url(forResource: "math-results", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).replacingOccurrences(of: "␣", with: " ") } }
    }

    func testFixture() throws {
        var n = 0
        for c in try fixtureLines() {
            n += 1
            switch c[0] {
            case "eval":
                XCTAssertEqual(MathResults.result(c[1]) ?? "-", c[2], "eval \(c[1])")
            case "chip":
                let chip = MathResults.chip(before: c[1])
                if c[2] == "-" {
                    XCTAssertNil(chip, "chip «\(c[1])» phải nil")
                } else {
                    XCTAssertEqual(chip, NumberChip(display: c[2], replace: "", insert: c[2]), "chip «\(c[1])»")
                }
            default:
                XCTFail("dòng fixture lạ: \(c)")
            }
        }
        XCTAssertGreaterThan(n, 80)
    }

    /// Chip số không còn nhận "…=" (tránh 2 chip cùng một kết quả).
    func testNumberChipsIgnoreEquals() {
        XCTAssertNil(NumberChips.chip(before: "12*3="))
        XCTAssertNotNil(MathResults.chip(before: "12*3="))
    }

    /// Chip kết quả ở slot ĐẦU; chữ cũ dời phải.
    func testSlotFirst() {
        var set = KeyboardView.SuggestionSet()
        set.nextWords = ["a", "b", "c"]
        set.math = "36"
        XCTAssertEqual(SuggestionSlots.arrange(set), .slots([
            BarChip(label: "36", payload: KeyboardView.mathToken),
            BarChip(label: "a", payload: "a"), BarChip(label: "b", payload: "b")], emojis: []))
        XCTAssertFalse(set.isEmpty)
    }

    /// Ô mật khẩu / URL / email: không; ô số: có.
    func testFieldGate() {
        XCTAssertTrue(FieldTraits().allowsMathResults)
        XCTAssertTrue(FieldTraits(keyboardType: .decimalPad).allowsMathResults)
        XCTAssertTrue(FieldTraits(keyboardType: .numbersAndPunctuation).allowsMathResults)
        XCTAssertFalse(FieldTraits(secure: true).allowsMathResults)
        XCTAssertFalse(FieldTraits(keyboardType: .URL).allowsMathResults)
        XCTAssertFalse(FieldTraits(keyboardType: .emailAddress).allowsMathResults)
        XCTAssertFalse(FieldTraits(contentType: .password).allowsMathResults)
        XCTAssertFalse(FieldTraits(contentType: .URL).allowsMathResults)
    }

    // MARK: luồng thật (controller + proxy giả)

    @MainActor private func run(_ mathResults: Bool, _ keys: String) -> KeyboardBenchTests.Rig {
        let d = KeyboardBenchTests.makeDefaults("B")
        d.set(mathResults, forKey: "mathResults")
        UserDefaultsProvider.shared = d
        let rig = KeyboardBenchTests.Rig()
        for c in keys { rig.vc.debugHandle(.text(String(c))) }
        KeyboardBenchTests.spin(0.1)
        return rig
    }

    /// Gõ "12*3=" → chip "36" ở slot đầu; chạm → "12*3=36", chip mất.
    @MainActor func testInsertFlow() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let rig = run(true, "12*3=")
        defer { rig.close() }
        let kb = rig.vc.debugKeyboard
        XCTAssertEqual(kb.debugSlotPayloads().first ?? nil, KeyboardView.mathToken)
        XCTAssertEqual(kb.debugSlotTitles().first ?? nil, "36")
        rig.vc.debugAcceptSuggestion(KeyboardView.mathToken)
        KeyboardBenchTests.spin(0.1)
        XCTAssertEqual(rig.proxy.text, "12*3=36")
        XCTAssertFalse(kb.debugSlotPayloads().contains(KeyboardView.mathToken))
    }

    /// Công tắc tắt ⇒ không chip; phím khác sau "=" ⇒ chip mất (chỉ ngay sau "=").
    @MainActor func testNoTrigger() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        let off = run(false, "12*3=")
        XCTAssertFalse(off.vc.debugKeyboard.debugSlotPayloads().contains(KeyboardView.mathToken))
        off.close()
        let later = run(true, "12*3=+")
        XCTAssertFalse(later.vc.debugKeyboard.debugSlotPayloads().contains(KeyboardView.mathToken))
        later.close()
        // "5=" không phải phép tính.
        let none = run(true, "5=")
        XCTAssertFalse(none.vc.debugKeyboard.debugSlotPayloads().contains(KeyboardView.mathToken))
        none.close()
    }

    func testSettingDefaultOn() {
        XCTAssertTrue(KeyboardSettings().mathResults)
        guard case .bool(true)? = BackupSettings.byKey["mathResults"]?.kind else {
            return XCTFail("thiếu spec sao lưu mathResults (bool, mặc định true)")
        }
    }
}
