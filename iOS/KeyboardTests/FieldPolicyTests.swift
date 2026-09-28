import XCTest

/// Regression: không gõ được tiếng Việt ở thanh địa chỉ Safari/Chrome và Spotlight
/// (ô tìm kiếm tắt autocorrect) — passthrough không còn dựa vào autocorrect.
final class FieldPolicyTests: XCTestCase {
    func testSearchFieldsKeepTelex() {
        XCTAssertFalse(FieldPolicy.passthrough(keyboardType: .webSearch, contentType: nil))
        XCTAssertFalse(FieldPolicy.passthrough(keyboardType: .default, contentType: nil))
    }
    func testLiteralFields() {
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .emailAddress, contentType: nil))
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .URL, contentType: nil))
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .default, contentType: .username))
        XCTAssertTrue(FieldPolicy.passthrough(keyboardType: .default, contentType: .oneTimeCode))
    }
}

/// Regression: ô không khai báo autocapitalization (nil) → ô trống vẫn chữ thường.
final class AutoShiftTests: XCTestCase {
    func testUndeclaredFieldCapitalizesSentenceStart() {
        XCTAssertEqual(FieldPolicy.autoShift(autocap: nil, before: ""), true)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: nil, before: "Xin chào. "), true)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: nil, before: "Xin chào "), false)
    }
    func testNoneLeavesShiftAlone() {
        XCTAssertNil(FieldPolicy.autoShift(autocap: UITextAutocapitalizationType.none, before: ""))
    }
    func testWordsAndAllCharacters() {
        XCTAssertEqual(FieldPolicy.autoShift(autocap: .words, before: "Nguyễn "), true)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: .words, before: "Nguy"), false)
        XCTAssertEqual(FieldPolicy.autoShift(autocap: .allCharacters, before: "AB"), true)
    }

    /// Công tắc "Tự động viết hoa đầu câu" TẮT (công tắc iOS không áp cho bàn phím bên
    /// thứ ba): không auto-shift ở đầu câu và KHÔNG đọc context.
    func testSettingOffNeverShiftsAndSkipsContextRead() {
        var reads = 0
        for cap: UITextAutocapitalizationType? in [nil, .sentences, .words, .allCharacters] {
            XCTAssertNil(FieldPolicy.autoShift(enabled: false, autocap: cap, before: { reads += 1; return "" }))
        }
        XCTAssertEqual(reads, 0)
    }
    func testSettingOnUnchanged() {
        var reads = 0
        XCTAssertEqual(FieldPolicy.autoShift(enabled: true, autocap: nil, before: { reads += 1; return "Xin chào. " }), true)
        XCTAssertEqual(FieldPolicy.autoShift(enabled: true, autocap: .sentences, before: { reads += 1; return "Xin " }), false)
        XCTAssertEqual(reads, 2)
    }

    /// Thanh địa chỉ (.webSearch): phím "," đổi thành "." như stock, nhưng vẫn là ô chữ tự do
    /// (gõ Telex / vuốt) và vẫn không tự thêm dấu cách / tự sửa.
    func testWebSearchFieldGetsDotKey() {
        let t = FieldTraits(keyboardType: .webSearch)
        XCTAssertEqual(t.inputKind, .search)
        XCTAssertTrue(t.inputKind.isFreeText)
        XCTAssertFalse(t.allowsAutoSpace)
        XCTAssertFalse(AutoCorrect.fieldAllows(t))
        XCTAssertTrue(FieldTraits().inputKind.isFreeText)
        XCTAssertFalse(FieldTraits(keyboardType: .URL).inputKind.isFreeText)
    }
}
