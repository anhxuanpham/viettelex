import XCTest

/// Regression: gõ ký hiệu ở plane 123 rồi space không quay về plane chữ.
final class PlanePolicyTests: XCTestCase {
    func testSpaceAfterSymbolReturnsToLetters() {
        XCTAssertTrue(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: true, typedInPlane: true, numericField: false))
    }
    func testSpaceWithoutTypingStaysInSymbols() {
        XCTAssertFalse(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: true, typedInPlane: false, numericField: false))
    }
    func testNumericFieldStaysInNumbers() {
        XCTAssertFalse(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: true, typedInPlane: true, numericField: true))
    }
    func testLettersPlaneUnaffected() {
        XCTAssertFalse(PlanePolicy.returnToLettersOnSpace(inSymbolPlane: false, typedInPlane: true, numericField: false))
    }
}

/// Regression (tester iOS 1.2.x): bật "Tự thêm dấu cách sau dấu câu", gõ "." ở plane
/// 123 → ". " tự thêm, chạm ABC về chữ ⇒ chữ kế KHÔNG viết hoa (code cũ ép shift off
/// khi về plane chữ). Giữ "," ra "." ở plane chữ thì vẫn đúng (không đổi plane).
final class ShiftOnReturnToLettersTests: XCTestCase {
    func testPolicyFollowsAutoShift() {
        XCTAssertTrue(PlanePolicy.shiftOnReturnToLetters(autoShift: true))
        XCTAssertFalse(PlanePolicy.shiftOnReturnToLetters(autoShift: false))
        XCTAssertFalse(PlanePolicy.shiftOnReturnToLetters(autoShift: nil))   // công tắc tắt: như cũ
    }

    func testContextAfterAutoSpaceCapitalizes() {
        for p in [".", "!", "?"] {
            let a = FieldPolicy.autoShift(autocap: .sentences, before: "Xin chào\(p) ")
            XCTAssertTrue(PlanePolicy.shiftOnReturnToLetters(autoShift: a), p)
        }
        let mid = FieldPolicy.autoShift(autocap: .sentences, before: "giá 5")
        XCTAssertFalse(PlanePolicy.shiftOnReturnToLetters(autoShift: mid))
    }

    @MainActor private func makeKeyboard() -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil) { _ in }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.configureInputKind(.normal)
        kb.layoutIfNeeded()
        return (kb, host)
    }

    /// Đường thật: ABC chạm ở plane số sau khi ". " vừa bật auto-shift.
    @MainActor func testABCAfterAutoSpaceKeepsShift() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        kb.setAutoShift(false)                                   // đang giữa câu
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "numbers")
        kb.setAutoShift(true)                                    // "." + dấu cách tự thêm
        kb.autoShiftProbe = { true }
        try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "letters")
        XCTAssertTrue(kb.debugShiftOn, "sau \". \" về ABC phải viết hoa chữ kế")
    }

    @MainActor func testABCMidSentenceDropsShift() throws {
        let (kb, host) = makeKeyboard()
        _ = host
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        kb.autoShiftProbe = { false }
        try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
        XCTAssertFalse(kb.debugShiftOn)
    }
}
