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

    // MARK: iPad plane số / ký hiệu + kiểu compact (đo stock iPadOS 27, 27/09/2026)

    func testPadStyleFollowsScreenShortSide() {
        XCTAssertEqual(KeyLayout.padStyle(screenShortSide: 744), .compact)   // iPad mini
        for s: CGFloat in [820, 834, 1024, 1032] {                             // Air / Pro
            XCTAssertEqual(KeyLayout.padStyle(screenShortSide: s), .full, "\(s)")
        }
    }

    private func ids(_ rows: [[KeyLayout.Key]]) -> [[String]] { rows.map { $0.map(\.id) } }

    /// Thứ tự phím plane .?123 đúng stock (full 11"/13" có tab + ô undo; mini không tab).
    func testPadNumberPlaneOrderMatchesStock() {
        let d = "1234567890".map(String.init)
        let r2 = ["@", "#", "$", "&", "*", "(", ")", "'", "\""]
        let r3 = ["%", "-", "+", "=", "/", ";", ":", "!,", "?."]
        XCTAssertEqual(ids(KeyLayout.padNumberRows(.full)), [
            ["tab"] + d + ["back"], ["undo"] + r2 + ["return"], ["more"] + r3 + ["more2"]])
        XCTAssertEqual(ids(KeyLayout.padNumberRows(.compact)), [
            d + ["back"], ["indent"] + r2 + ["return"], ["more"] + r3 + ["more2"]])
    }
    func testPadSymbolPlaneOrderMatchesStock() {
        let d = "1234567890".map(String.init)
        let r2 = ["¥", "£", "€", "_", "^", "[", "]", "{", "}"]
        let r3 = ["§", "|", "~", "…", "\\", "<", ">", "!", "?"]
        XCTAssertEqual(ids(KeyLayout.padSymbolRows(.full)), [
            ["tab"] + d + ["back"], ["redo"] + r2 + ["return"], ["more"] + r3 + ["more2"]])
        XCTAssertEqual(ids(KeyLayout.padSymbolRows(.compact)), [
            d + ["back"], ["indent"] + r2 + ["return"], ["more"] + r3 + ["more2"]])
        // Ô undo/redo stock (bàn phím bên thứ ba không undo được app): "," và "₫".
        XCTAssertEqual(KeyLayout.padSlotTitle("undo"), ",")
        XCTAssertEqual(KeyLayout.padSlotTitle("redo"), "₫")
    }
    /// Plane chữ mini: không tab/⇪, ⌫ cuối hàng 1, ⇧ hai đầu hàng 3.
    func testPadCompactLetterRowsMatchStock() {
        let r1: [String] = "qwertyuiop".map(String.init) + ["back"]
        let r2: [String] = ["indent"] + "asdfghjkl".map(String.init) + ["return"]
        let r3: [String] = ["shiftL"] + "zxcvbnm".map(String.init) + ["!,", "?.", "shiftR"]
        XCTAssertEqual(ids(KeyLayout.padLetterRows(.compact)), [r1, r2, r3])
        XCTAssertEqual(ids(KeyLayout.padLetterRows(.full)), ids(KeyLayout.padRows))
    }
    /// Ký tự phụ plane số = stock.
    func testPadNumberHintsMatchStock() {
        XCTAssertEqual(KeyLayout.padNumberHints, [
            "@": "¥", "#": "£", "$": "€", "&": "_", "*": "^", "(": "[", ")": "]", "'": "{", "\"": "}",
            "%": "§", "-": "|", "+": "~", "=": "…", "/": "\\", ";": "<", ":": ">"])
        let keys = Set(KeyLayout.padNumberRows(.full).flatMap { $0.map(\.id) })
        XCTAssertTrue(Set(KeyLayout.padNumberHints.keys).isSubset(of: keys))
    }
    /// Mỗi hàng: hàng neo (0) không co giãn, hàng khác đúng MỘT phím co giãn, vừa mọi bề rộng.
    func testPadPlaneRowsHaveOneFlexKeyAndFit() {
        for s in [KeyLayout.PadStyle.full, .compact] {
            for rows in [KeyLayout.padLetterRows(s), KeyLayout.padNumberRows(s), KeyLayout.padSymbolRows(s)] {
                XCTAssertEqual(KeyLayout.flexCount(rows[0]), 0, "\(s)")
                for r in rows.dropFirst() {
                    XCTAssertEqual(KeyLayout.flexCount(r), 1, "\(s) \(r.map(\.id))")
                    for w: CGFloat in s == .compact ? [744, 1133] : [820, 834, 1032, 1194, 1376] {
                        let q = KeyLayout.padLetterWidth(anchor: rows[0], rowWidth: w, gap: 10, margin: 3)
                        let f = KeyLayout.padFlexWidth(r, anchor: rows[0], rowWidth: w, gap: 10, margin: 3)
                        XCTAssertGreaterThan(f, q, "\(s) w=\(w) \(r.map(\.id))")
                    }
                }
            }
        }
        // compact: ⇧ phải co giãn = đúng ⌫ (1.23 phím) như stock.
        let rows = KeyLayout.padLetterRows(.compact)
        let f = KeyLayout.padFlexWidth(rows[2], anchor: rows[0], rowWidth: 744, gap: 10, margin: 3)
        let q = KeyLayout.padLetterWidth(anchor: rows[0], rowWidth: 744, gap: 10, margin: 3)
        XCTAssertEqual(f, q * KeyLayout.compactWideUnits, accuracy: 0.01)
    }
    /// Hàng đáy: 🌐 đầu hàng mọi plane iPad; plane số full không phẩy, compact có ô undo/redo.
    func testPadBottomRowsMatchStock() {
        XCTAssertEqual(KeyLayout.padBottomRow(.full, letters: true).map(\.id),
                       ["globe", "plane", "emoji", "space", "plane2", "dismiss"], "stock: không phím , riêng")
        XCTAssertEqual(KeyLayout.padBottomRow(.compact, letters: true).map(\.id),
                       ["globe", "plane", "emoji", "space", "plane2", "dismiss"])
        XCTAssertEqual(KeyLayout.padBottomRow(.full, letters: false).map(\.id),
                       ["globe", "plane", "emoji", "space", "plane2", "dismiss"])
        XCTAssertEqual(KeyLayout.padBottomRow(.compact, letters: false).map(\.id),
                       ["globe", "plane", "emoji", "space", "slot", "plane2", "dismiss"])
        for s in [KeyLayout.PadStyle.full, .compact] {
            for l in [true, false] {
                let r = KeyLayout.padBottomRow(s, letters: l)
                XCTAssertEqual(KeyLayout.flexCount(r), 1)
                XCTAssertLessThan(r.compactMap(\.units).reduce(0, +), 0.75)
            }
        }
    }
    /// Vuốt xuống = ký tự phụ: xuống quá ngưỡng và dọc hơn ngang.
    func testPadFlickIsDownward() {
        XCTAssertTrue(KeyLayout.isPadFlick(dx: 0, dy: 19, threshold: 18))
        XCTAssertTrue(KeyLayout.isPadFlick(dx: -10, dy: 25, threshold: 18))
        XCTAssertFalse(KeyLayout.isPadFlick(dx: 0, dy: 17, threshold: 18))
        XCTAssertFalse(KeyLayout.isPadFlick(dx: 30, dy: 25, threshold: 18))
        XCTAssertFalse(KeyLayout.isPadFlick(dx: 0, dy: -30, threshold: 18))
    }
}
