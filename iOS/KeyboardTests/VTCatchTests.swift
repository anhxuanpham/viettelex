import XCTest

/// Crash thật 28/09/2026 (iOS 27.0, build 1.2(7)): UIKit NÉM NSException khi đọc trait
/// của textDocumentProxy lúc chưa sẵn sàng. vtSafe/VTCatchException phải nuốt lỗi.
final class VTCatchTests: XCTestCase {
    func testCatchesObjCException() {
        let e = VTCatchException {
            NSException(name: .invalidArgumentException, reason: "_controllerState", userInfo: nil).raise()
        }
        XCTAssertEqual(e?.name, .invalidArgumentException)
        XCTAssertNil(VTCatchException { _ = 1 + 1 })
    }

    func testSafeReadFallsBackOnException() {
        let v: UIKeyboardType = vtSafe(.default) {
            NSException(name: .invalidArgumentException, reason: "boom", userInfo: nil).raise()
            return .emailAddress
        }
        XCTAssertEqual(v, .default)
        XCTAssertEqual(vtSafe(.default) { UIKeyboardType.emailAddress }, .emailAddress)
    }
}
