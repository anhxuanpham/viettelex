import XCTest

/// Test NẶNG / đo đạc (heldout độ chính xác, độ trễ, RAM, StoreKit session) — tách khỏi bộ
/// mặc định vì chúng làm runner bị kill khi máy tải cao và số đo thời gian dao động. Vẫn là
/// ngưỡng hồi quy: phải PASS khi chạy riêng.
///
/// Chạy (iOS/README.md mục "Test"):
///   xcodebuild -scheme VietTelexKeyboardSlowTests -destination '…' test
/// hoặc bất kỳ scheme test nào với TEST_RUNNER_VT_SLOW_TESTS=1 (xcodebuild bỏ tiền tố
/// TEST_RUNNER_ khi chuyển biến môi trường vào tiến trình test).
enum SlowTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["VT_SLOW_TESTS"] == "1" }

    static func require(file: StaticString = #filePath, line: UInt = #line) throws {
        try XCTSkipUnless(enabled, "Test chậm — bật bằng VT_SLOW_TESTS=1 (scheme VietTelexKeyboardSlowTests)",
                          file: file, line: line)
    }
}
