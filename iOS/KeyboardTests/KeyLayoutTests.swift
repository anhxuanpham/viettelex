import XCTest

/// Regression 26/09/2026: hàng có >1 phím không neo bề rộng → UIKit chia tuỳ lúc
/// (🌐 hàng đáy iPad nhảy size; hàng 1 iPad thành 12 phím đều sau mẫu câu).
final class KeyLayoutTests: XCTestCase {
    func testAnchorRowHasNoFlexKey() {
        XCTAssertEqual(KeyLayout.flexCount(KeyLayout.padRows[KeyLayout.padAnchorRow]), 0)
    }
    func testOtherPadRowsHaveExactlyOneFlexKey() {
        for (i, row) in KeyLayout.padRows.enumerated() where i != KeyLayout.padAnchorRow {
            XCTAssertEqual(KeyLayout.flexCount(row), 1, "hàng \(i)")
        }
    }
    func testBottomRowsHaveExactlyOneFlexKey() {
        XCTAssertEqual(KeyLayout.flexCount(KeyLayout.padBottom), 1)
        XCTAssertEqual(KeyLayout.flexCount(KeyLayout.phoneBottom), 1)
        XCTAssertNotNil(KeyLayout.units("globe", in: KeyLayout.padBottom))
        XCTAssertNotNil(KeyLayout.units("globe", in: KeyLayout.phoneBottom))
    }
    /// Phím co giãn không bị bóp âm/quá nhỏ ở mọi bề rộng iPad (mini dọc → 13" ngang).
    func testPadFlexKeysFitAllWidths() {
        for w: CGFloat in [744, 820, 834, 1024, 1133, 1194, 1366] {
            let q = KeyLayout.padLetterWidth(rowWidth: w, gap: 10, margin: 3)
            for i in 1..<KeyLayout.padRows.count {
                let f = KeyLayout.padFlexWidth(row: i, rowWidth: w, gap: 10, margin: 3)
                XCTAssertGreaterThan(f, q, "w=\(w) hàng \(i)")
            }
        }
    }
    /// Hàng số iPad: đúng một phím co giãn, cùng số phím với hàng neo (1…0 thẳng
    /// cột q…p), phím co giãn rộng đúng như ⌫ ở mọi bề rộng.
    func testPadNumberRowAlignsWithAnchorRow() {
        let num = KeyLayout.padNumberRow
        let anchor = KeyLayout.padRows[KeyLayout.padAnchorRow]
        XCTAssertEqual(KeyLayout.flexCount(num), 1)
        XCTAssertEqual(num.count, anchor.count)
        XCTAssertEqual(num.map(\.id)[1...10].joined(), "1234567890")
        XCTAssertEqual(anchor.map(\.id)[1...10].joined(), "qwertyuiop")
        XCTAssertEqual(num[0].units, anchor[0].units)
        for w: CGFloat in [744, 820, 834, 1024, 1133, 1194, 1366] {
            let q = KeyLayout.padLetterWidth(rowWidth: w, gap: 10, margin: 3)
            let f = KeyLayout.padFlexWidth(num, rowWidth: w, gap: 10, margin: 3)
            XCTAssertEqual(f, q * (KeyLayout.units("back", in: anchor) ?? 0), accuracy: 0.01, "w=\(w)")
        }
        // id không đụng hàng chữ (buildLettersPad tra view theo id)
        let ids = Set(KeyLayout.padRows.flatMap { $0.map(\.id) })
        XCTAssertTrue(ids.isDisjoint(with: num.map(\.id)))
    }
    func testBottomFractionsLeaveRoomForSpace() {
        for row in [KeyLayout.padBottom, KeyLayout.phoneBottom] {
            XCTAssertLessThan(row.compactMap(\.units).reduce(0, +), 0.75)
        }
    }
}
