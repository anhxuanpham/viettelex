import XCTest
import UIKit

/// Hàng phím số tuỳ chọn (27/09/2026, người dùng Laban than thiếu hàng số):
/// plane chữ có thêm 1…0 ở trên cùng, thấp 0.75× hàng chữ; plane số giữ 4 hàng.
final class NumberRowTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor private func makeKeyboard(numberRow: Bool,
                                         onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let w: CGFloat = isPad ? 834 : 390
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.numberRowEnabled = numberRow
        kb.layoutIfNeeded()
        return (kb, host)
    }

    @MainActor private func assertNumberRowLayout(_ kb: KeyboardView, file: StaticString = #filePath,
                                                  line: UInt = #line) throws {
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows.count, 5, file: file, line: line)
        guard rows.count == 5 else { return }
        XCTAssertEqual(rows[0].height, rows[1].height * KeyLayout.numberRowRatio,
                       accuracy: 0.5, file: file, line: line)
        for r in rows[2...] {
            XCTAssertEqual(r.height, rows[1].height, accuracy: 0.5, file: file, line: line)
        }
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let z = try XCTUnwrap(kb.debugLetterFrame("z"))
        let a = try XCTUnwrap(kb.debugLetterFrame("a"))
        XCTAssertEqual(z.width, q.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(a.width, q.width, accuracy: 0.5, file: file, line: line)
        XCTAssertGreaterThan(q.minY, rows[0].maxY - 0.5, file: file, line: line)
        let one = try XCTUnwrap(kb.debugKeyButton("1"), file: file, line: line)
        let f = kb.convert(one.bounds, from: one)
        XCTAssertEqual(f.midX, q.midX, accuracy: 0.5, "1 thẳng cột q", file: file, line: line)
        XCTAssertEqual(f.width, q.width, accuracy: 0.5, file: file, line: line)
    }

    func testKeyAreaHeightAddsThreeQuartersOfARow() {
        XCTAssertEqual(KeyLayout.keyAreaHeight(base: 218, adjust: 0, numberRow: false), 218)
        XCTAssertEqual(KeyLayout.keyAreaHeight(base: 218, adjust: 0, numberRow: true),
                       218 + 218 / 4 * 0.75, accuracy: 0.001)
        // chỉnh ±pt mỗi hàng: hàng số ăn 0.75 phần
        XCTAssertEqual(KeyLayout.keyAreaHeight(base: 240, adjust: 5, numberRow: true),
                       (240 + 20) / 4 * 4.75, accuracy: 0.001)
    }

    @MainActor func testOffByDefaultKeepsFourEqualRows() {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        XCTAssertFalse(kb.numberRowEnabled)
        let (kb2, _) = makeKeyboard(numberRow: false)
        let rows = kb2.debugRowFrames()
        XCTAssertEqual(rows.count, 4)
        for r in rows { XCTAssertEqual(r.height, rows[0].height, accuracy: 0.5) }
        XCTAssertNil(kb2.debugKeyButton("1"))
    }

    @MainActor func testLettersPlaneGetsShorterNumberRow() throws {
        let (kb, _) = makeKeyboard(numberRow: true)
        try assertNumberRowLayout(kb)
        // Phím số là button thật (hitTest trả thẳng) — router phím chữ không cướp.
        let one = try XCTUnwrap(kb.debugKeyButton("1"))
        let f = kb.convert(one.bounds, from: one)
        let hit = kb.hitTest(CGPoint(x: f.midX, y: f.midY), with: nil)
        XCTAssertTrue(hit === one)
        // Chạm q vẫn là router (phím chữ).
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        XCTAssertTrue(kb.hitTest(CGPoint(x: q.midX, y: q.midY), with: nil) === kb)
    }

    @MainActor func testDigitInsertsTextKey() throws {
        var got: [KeyboardView.Key] = []
        let (kb, _) = makeKeyboard(numberRow: true, onKey: { got.append($0) })
        let seven = try XCTUnwrap(kb.debugKeyButton("7"))
        seven.sendActions(for: .touchDown)
        seven.sendActions(for: .touchUpInside)
        guard case .text("7")? = got.last else { return XCTFail("\(got)") }
    }

    @MainActor func testNumberRowSurvivesPlaneCache() throws {
        let (kb, _) = makeKeyboard(numberRow: true)
        kb.debugCycleThroughNumbers()
        kb.layoutIfNeeded()
        try assertNumberRowLayout(kb)
        kb.debugCycleThroughTemplates()
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try assertNumberRowLayout(kb)
    }

    @MainActor func testNumbersPlaneKeepsFourRows() {
        let (kb, _) = makeKeyboard(numberRow: true)
        kb.debugSetPlane(numbers: true)
        kb.layoutIfNeeded()
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows.count, 4)
        for r in rows { XCTAssertEqual(r.height, rows[0].height, accuracy: 0.5) }
    }

    @MainActor func testToggleOffRestoresLayout() {
        let (kb, _) = makeKeyboard(numberRow: true)
        kb.numberRowEnabled = false
        kb.layoutIfNeeded()
        XCTAssertEqual(kb.debugRowFrames().count, 4)
        XCTAssertNil(kb.debugKeyButton("1"))
    }

    /// Gõ vuốt lấy tâm a–z từ frame thật: đủ 26 chữ, không lẫn phím số.
    @MainActor func testSwipeLayoutStillLettersOnly() throws {
        let (kb, _) = makeKeyboard(numberRow: true)
        let layout = try XCTUnwrap(kb.swipeLayout())
        XCTAssertEqual(layout.centers.count, 52)
        XCTAssertTrue(layout.centers.allSatisfy(\.isFinite))
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let qi = Int(Character("q").asciiValue! - Character("a").asciiValue!)
        XCTAssertEqual(CGFloat(layout.centers[2 * qi]), q.midX, accuracy: 0.5)
        XCTAssertEqual(CGFloat(layout.centers[2 * qi + 1]), q.midY, accuracy: 0.5)
    }
}
