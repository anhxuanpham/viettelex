import XCTest
import UIKit

/// Hình học hàng phím iPhone so với bàn phím Apple gốc (đo 27/09/2026 — KeyGeometry) +
/// vùng chạm hàng đáy / khe (mục 9) + đổi plane một chạm (mục 10).
final class KeyGeometryTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: thuần

    func testPitchAndIndentMatchStock() {
        // 402pt, lề 6.5, khe 6 → phím 33.5 (stock 33.3), bước 39.5 (stock 39.5).
        let pitch = KeyGeometry.letterPitch(width: 402, margin: 6.5, gap: 6)
        XCTAssertEqual(pitch, 39.5, accuracy: 0.3)
        // Hàng a…l thụt nửa bước: mép a = 26.25 (stock 26.3).
        XCTAssertEqual(KeyGeometry.indentedMargin(width: 402, margin: 6.5, gap: 6, units: 0.5),
                       26.3, accuracy: 0.3)
        XCTAssertEqual(KeyGeometry.sideMargin(pad: false), 6.5)
        XCTAssertEqual(KeyGeometry.sideMargin(pad: true), 3)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: false, landscape: false), 4)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: false, landscape: true), 0)
        XCTAssertEqual(KeyGeometry.bottomRowTrim(pad: true, landscape: false), 0)
    }

    func testNearestSplitsGapByDistance() {
        let upper = CGRect(x: 0, y: 0, width: 40, height: 44)
        let lower = CGRect(x: 0, y: 54, width: 40, height: 44)   // khe 10
        XCTAssertEqual(KeyGeometry.nearest(CGPoint(x: 20, y: 47), in: [upper, lower], reach: 22)?.index, 0)
        XCTAssertEqual(KeyGeometry.nearest(CGPoint(x: 20, y: 51), in: [upper, lower], reach: 22)?.index, 1)
        XCTAssertNil(KeyGeometry.nearest(CGPoint(x: 90, y: 20), in: [upper], reach: 22))
    }

    func testSelectionPointNeverLeavesKeyAreaTop() {
        // Chạm 1pt dưới đỉnh vùng phím: dời lên 4pt thì ra ngoài → router bỏ (mất phím).
        XCTAssertEqual(TouchGeometry.keySelectionPoint(CGPoint(x: 5, y: 101), top: 100).y, 100)
        XCTAssertEqual(TouchGeometry.keySelectionPoint(CGPoint(x: 5, y: 150), top: 100).y, 146)
        XCTAssertEqual(TouchGeometry.keySelectionPoint(CGPoint(x: 5, y: 90), top: 100).y, 90)
    }

    // MARK: bàn phím thật

    @MainActor private func makeKeyboard(onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 212))
        host.addSubview(kb)
        kb.frame = host.bounds          // gợi ý tắt: strip 0, vùng phím 212 = cả view
        kb.layoutIfNeeded()
        return (kb, host)
    }

    private func frame(_ kb: KeyboardView, _ c: UIControl) -> CGRect { kb.convert(c.bounds, from: c) }

    /// Tâm phím (tính từ ĐÁY view) ≈ stock (tính từ đáy màn hình − 75pt vùng 🌐/mic).
    /// Trước: cả 3 hàng chữ cao hơn stock 5–6pt (bản phát hành 11pt).
    @MainActor func testLetterRowsMatchStockFromBottom() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        let h = kb.bounds.height
        XCTAssertEqual(h, 212, accuracy: 0.5)
        let stock = KeyGeometry.Stock.rowCentersFromScreenBottom.map {
            $0 - KeyGeometry.Stock.viewBottomAboveScreenBottom
        }
        for (i, s) in ["q", "a", "z"].enumerated() {
            let f = try XCTUnwrap(kb.debugLetterFrame(s))
            XCTAssertEqual(h - f.midY, stock[i], accuracy: 1, "hàng \(s)")
            XCTAssertEqual(f.height, 44, accuracy: 0.5)
        }
        let num = try XCTUnwrap(kb.debugControl("Số"))
        let nf = frame(kb, num)
        XCTAssertEqual(nf.maxY, h, accuracy: 0.5, "hàng đáy sát đáy view")
        XCTAssertEqual(nf.height, 44, accuracy: 0.5, "phím đáy vẫn cao 44")
        XCTAssertEqual(h - nf.midY, stock[3], accuracy: 5, "đáy view cao hơn đáy phím stock 4pt")
    }

    @MainActor func testColumnsAndBottomRowMatchStock() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        let expect: [(String, CGFloat)] = [("q", 23.3), ("p", 378.8), ("a", 43.0), ("l", 359.0)]
        for (s, x) in expect {
            XCTAssertEqual(try XCTUnwrap(kb.debugLetterFrame(s)).midX, x, accuracy: 1, s)
        }
        let num = frame(kb, try XCTUnwrap(kb.debugControl("Số")))
        let emoji = frame(kb, try XCTUnwrap(kb.debugControl("Emoji")))
        let comma = frame(kb, try XCTUnwrap(kb.debugKeyButton(",")))
        let ret = frame(kb, try XCTUnwrap(kb.debugControl("Xuống dòng")))
        XCTAssertEqual(num.midX, KeyGeometry.Stock.planeKeyMidX, accuracy: 1.5)
        XCTAssertEqual(emoji.midX, KeyGeometry.Stock.emojiKeyMidX, accuracy: 1.5)
        XCTAssertEqual(comma.midX, 402 * KeyGeometry.Stock.periodMidXFraction, accuracy: 2)
        XCTAssertEqual(ret.midX, 402 * KeyGeometry.Stock.returnMidXFraction, accuracy: 2)
    }

    /// Mục 9: khe trên hàng đáy + mép trái — trước là vùng chết (chạm cao 123 mất, cao
    /// emoji ra chữ z). Giờ trả đúng nút gần nhất.
    @MainActor func testBottomRowGapsHitNearestButton() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        for label in ["Số", "Emoji", "Dấu cách", "Xuống dòng"] {
            let c = try XCTUnwrap(kb.debugControl(label))
            let f = frame(kb, c)
            for p in [CGPoint(x: f.midX, y: f.minY - 2.5), CGPoint(x: f.midX, y: f.minY - 1)] {
                XCTAssertTrue(kb.hitTest(p, with: nil) === c, "\(label) chạm cao \(f.minY - p.y)pt")
            }
        }
        let num = try XCTUnwrap(kb.debugControl("Số"))
        XCTAssertTrue(kb.hitTest(CGPoint(x: 1, y: frame(kb, num).midY), with: nil) === num, "mép trái")
        // Quét cả khe ⇧ ↔ 123: điểm nào cũng phải thuộc một trong hai nút (trước: dải chết).
        let shift = try XCTUnwrap(kb.debugControl("Shift"))
        let sf = frame(kb, shift), nf = frame(kb, num)
        var y = sf.maxY
        while y <= nf.minY {
            let v = kb.hitTest(CGPoint(x: nf.midX, y: y), with: nil)
            XCTAssertTrue(v === shift || v === num, "khe ⇧/123 y=\(y): \(String(describing: v))")
            y += 0.5
        }
        // Khe giữa 123 và emoji: về nút gần hơn.
        let e = try XCTUnwrap(kb.debugControl("Emoji"))
        let ef = frame(kb, e)
        XCTAssertTrue(kb.hitTest(CGPoint(x: ef.minX - 1, y: ef.midY), with: nil) === e)
    }

    /// Plane số không có router chữ: khe giữa các hàng số từng chết 4.5pt mỗi hàng.
    @MainActor func testNumbersPlaneHasNoDeadGaps() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let one = try XCTUnwrap(kb.debugKeyButton("1"))
        let dash = try XCTUnwrap(kb.debugKeyButton("-"))
        let f1 = frame(kb, one), fd = frame(kb, dash)
        XCTAssertGreaterThan(fd.minY, f1.maxY, "rows=\(kb.debugRowFrames()) f1=\(f1) fd=\(fd)")
        var y = f1.maxY
        while y < fd.minY {
            let v = kb.hitTest(CGPoint(x: f1.midX, y: y), with: nil)
            XCTAssertTrue(v === one || v === dash, "khe y=\(y)")
            y += 0.5
        }
        let abc = try XCTUnwrap(kb.debugControl("Chữ"))
        let fa = frame(kb, abc)
        let more = try XCTUnwrap(kb.debugControl("Ký hiệu"))
        var yy = frame(kb, more).maxY
        while yy <= fa.minY {
            let v = kb.hitTest(CGPoint(x: fa.midX, y: yy), with: nil)
            XCTAssertTrue(v === more || v === abc, "khe #+=/ABC y=\(yy)")
            yy += 0.5
        }
        let hv = kb.hitTest(CGPoint(x: fa.midX, y: fa.minY - 2.5), with: nil)
        XCTAssertTrue(hv === abc, "\(String(describing: hv)) rows=\(kb.debugRowFrames()) abc=\(fa)")
        let rows = kb.debugRowFrames()
        XCTAssertEqual(rows[3].height, rows[0].height - KeyGeometry.bottomRowTrim(pad: false, landscape: false),
                       accuracy: 0.5)
    }

    /// Mục 10: 123 ↔ ABC đổi ngay lúc CHẠM (như stock) — không cần touch-up (hệ thống huỷ
    /// touch sát vùng 🌐/mic, hay ngón trượt khỏi phím ⇒ trước đây phải bấm lại).
    @MainActor func testPlaneKeysSwitchOnTouchDown() throws {
        let (kb, _) = makeKeyboard()
        for i in 0..<5 {
            try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
            XCTAssertEqual(kb.debugPlaneName, "numbers", "lần \(i)")
            kb.layoutIfNeeded()
            try XCTUnwrap(kb.debugControl("Chữ")).sendActions(for: .touchDown)
            XCTAssertEqual(kb.debugPlaneName, "letters", "lần \(i)")
            kb.layoutIfNeeded()
        }
        // #+= cũng vậy
        try XCTUnwrap(kb.debugControl("Số")).sendActions(for: .touchDown)
        try XCTUnwrap(kb.debugControl("Ký hiệu")).sendActions(for: .touchDown)
        XCTAssertEqual(kb.debugPlaneName, "symbols")
    }

    @MainActor func testEmojiOpensEvenIfTouchCancelled() throws {
        let (kb, _) = makeKeyboard()
        try XCTUnwrap(kb.debugControl("Emoji")).sendActions(for: .touchCancel)
        XCTAssertEqual(kb.debugPlaneName, "emoji")
    }

    /// Chạm sát đỉnh vùng phím (khe trên q) vẫn ra q (trước: dời lên 4pt → ra ngoài → mất).
    @MainActor func testTouchAtKeyAreaTopStillTypes() throws {
        var typed: [KeyboardView.Key] = []
        let (kb, _) = makeKeyboard { typed.append($0) }
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        kb.debugTouch(from: CGPoint(x: q.midX, y: 1), through: [], start: 100)
        guard case .letter(let c)? = typed.first else { return XCTFail("mất phím: \(typed)") }
        XCTAssertEqual(String(c).lowercased(), "q")
    }
}
