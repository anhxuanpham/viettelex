// NumberChipsTests — chip số (đọc chữ / định dạng tiền / máy tính nhanh) theo fixture chung
// Fixtures/number-chips.txt. Cùng bộ ca với android NumberChipsTests.kt.
import XCTest

final class NumberChipsTests: XCTestCase {
    private func fixtureLines() throws -> [[String]] {
        let url = try XCTUnwrap(Bundle(for: NumberChipsTests.self)
            .url(forResource: "number-chips", withExtension: "txt"))
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
            case "spell":
                XCTAssertEqual(NumberChips.spell(c[1]), c[2], "spell \(c[1])")
            case "spellLe":
                XCTAssertEqual(NumberChips.spell(c[1], le: true), c[2], "spellLe \(c[1])")
            case "calc":
                let got = NumberChips.evaluate(c[1]).map(NumberChips.formatResult) ?? "-"
                XCTAssertEqual(got, c[2], "calc \(c[1])")
            case "chip":
                let chip = NumberChips.chip(before: c[1])
                if c[2] == "-" {
                    XCTAssertNil(chip, "chip «\(c[1])» phải nil")
                } else {
                    XCTAssertEqual(chip, NumberChip(display: c[2], replace: c[3], insert: c[4]),
                                   "chip «\(c[1])»")
                }
            default:
                XCTFail("dòng fixture lạ: \(c)")
            }
        }
        XCTAssertGreaterThan(n, 100)
    }

    /// Đuôi bị thay phải đúng là đuôi context (controller xoá đúng từng ấy ký tự).
    func testReplaceIsSuffixOfContext() throws {
        for c in try fixtureLines() where c[0] == "chip" && c[2] != "-" {
            XCTAssertTrue(c[1].hasSuffix(c[3]), "«\(c[3])» không phải đuôi «\(c[1])»")
        }
    }

    func testShorthandExact() {
        XCTAssertEqual(NumberChips.parseAmount("1tr2")?.value.int, "1200000")
        XCTAssertEqual(NumberChips.parseAmount("2 tỷ")?.value.int, "2000000000")
        XCTAssertNil(NumberChips.parseAmount("1.2tr5"))      // tail chỉ sau số nguyên trơn
        XCTAssertNil(NumberChips.parseAmount("12 5"))
    }

    func testDigitNearCaret() {
        XCTAssertTrue(NumberChips.digitNearCaret("giá 2 tỷ"))
        XCTAssertTrue(NumberChips.digitNearCaret("1250000 "))
        XCTAssertTrue(NumberChips.digitNearCaret("a 12+3"))
        XCTAssertFalse(NumberChips.digitNearCaret("năm 2026 rồi mới"))
        XCTAssertFalse(NumberChips.digitNearCaret("xin chào"))
        XCTAssertFalse(NumberChips.digitNearCaret(""))
    }
}
