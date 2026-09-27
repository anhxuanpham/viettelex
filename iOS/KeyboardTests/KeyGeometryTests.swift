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
        // Phím đáy 43 (stock) trong vùng 50: khe trên 7 — trước 6 + 44 trông cao hơn stock.
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: false, landscape: false), 7)
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: false, landscape: true), KeyGeometry.rowGap)
        XCTAssertEqual(KeyGeometry.bottomRowTopMargin(pad: true, landscape: false), KeyGeometry.rowGap)
    }

    /// Chữ phím khớp stock (đo ảnh @3x 27/09): SF Compact, thường 24.5 / hoa-số 22.7, cùng
    /// baseline 28pt dưới đỉnh phím 43. Trước: SF Pro 23 căn giữa → chữ thường nhỏ + thấp.
    func testTypographyMatchesStock() {
        typealias T = KeyGeometry.Typography
        XCTAssertEqual(T.lowercaseSize, 24.5)
        XCTAssertEqual(T.keycapSize, 22.7)
        XCTAssertEqual(T.planeKeySize, 18.9)
        XCTAssertEqual(T.fallbackKeycapSize, 21.3)
        for s in ["a", "q", "đ", "ư", "ấ"] { XCTAssertTrue(T.isLowercase(s), s) }
        for s in ["A", "Đ", "1", ",", "#+=", "", "@"] { XCTAssertFalse(T.isLowercase(s), s) }
        XCTAssertEqual(T.size(for: "q", compact: true), 24.5)
        XCTAssertEqual(T.size(for: "Q", compact: true), 22.7)
        XCTAssertEqual(T.size(for: "7", compact: true), 22.7)
        XCTAssertEqual(T.size(for: "Q", compact: false), 21.3)
        // Baseline: phím 43 → 28 từ đỉnh; phím 44 (hàng chữ, nhô 1pt trên) → 29 (đáy trùng stock).
        XCTAssertEqual(T.baselineFromTop(keyHeight: 43), 28)
        XCTAssertEqual(T.baselineFromTop(keyHeight: 44), 29)
        XCTAssertEqual(T.baselineFromTop(keyHeight: 30.5), 28 * 30.5 / 43, accuracy: 0.001)
        // SF metrics (asc 0.952, desc −0.241) 24.5pt trên phím 44: căn giữa → baseline 30.7,
        // phải dời lên 1.7pt.
        let dy = T.titleOffsetY(keyHeight: 44, ascender: 0.952 * 24.5, descender: -0.241 * 24.5)
        XCTAssertEqual(dy, -1.71, accuracy: 0.02)
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
        XCTAssertEqual(nf.height, KeyGeometry.Stock.keyHeight, accuracy: 0.3, "phím đáy cao 43 như stock")
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

    /// Nhãn phím chữ thật: font Compact (nếu có) đúng cỡ theo hoa/thường, baseline cách đáy
    /// phím 15pt như stock — cả sau khi bật/tắt shift (retitle tại chỗ).
    @MainActor func testLetterLabelsSitOnStockBaseline() throws {
        try XCTSkipIf(isPad)
        let (kb, _) = makeKeyboard()
        func check(_ title: String, size: CGFloat, _ note: String) throws {
            let b = try XCTUnwrap(kb.debugKeyButton(title), note)
            b.layoutIfNeeded()
            let l = try XCTUnwrap(b.titleLabel), f = try XCTUnwrap(l.font)
            XCTAssertEqual(f.pointSize, size, accuracy: 0.01, note)
            if KeyboardView.hasCompactFont {
                XCTAssertTrue(f.fontName.localizedCaseInsensitiveContains("compact"), f.fontName)
            }
            let baseline = l.frame.midY + (f.ascender + f.descender) / 2
            XCTAssertEqual(b.bounds.height - baseline, 15, accuracy: 0.5, "\(note) h=\(b.bounds.height)")
        }
        let T = KeyGeometry.Typography.self
        let c = KeyboardView.hasCompactFont
        let lowerFirst = kb.debugKeyButton("q") != nil
        try check(lowerFirst ? "q" : "Q", size: T.size(for: lowerFirst ? "q" : "Q", compact: c), "ban đầu")
        try XCTUnwrap(kb.debugControl("Shift")).sendActions(for: .touchDown)
        kb.layoutIfNeeded()
        try check(lowerFirst ? "Q" : "q", size: T.size(for: lowerFirst ? "Q" : "q", compact: c), "sau shift")
        // Plane số: chữ số cỡ keycap, cùng baseline.
        kb.debugSetPlane(numbers: true)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        try check("7", size: T.size(for: "7", compact: c), "plane số")
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
