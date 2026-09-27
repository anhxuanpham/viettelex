import XCTest
import UIKit

/// Góp ý người dùng 27/09/2026 (ảnh chụp bản phát hành, dark mode): lưới emoji to hơn +
/// thanh tìm luôn hiện, thẻ Dán đè chữ gợi ý + slot "lúc rộng lúc hẹp", trackpad lag,
/// công tắc ô phóng to chữ, nhãn mẫu câu "❓".
final class UXFeedbackTests: XCTestCase {

    private let w: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 834 : 390

    @MainActor private func makeKeyboard(suggestions: Bool = true,
                                         onKey: @escaping (KeyboardView.Key) -> Void = { _ in })
        -> (KeyboardView, UIView) {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: onKey)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: 320))
        host.addSubview(kb)
        kb.frame = host.bounds
        kb.setSuggestionsEnabled(suggestions)
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        return (kb, host)
    }

    // MARK: 1. emoji

    /// Ô emoji ≥ 40pt ở mọi chiều cao lưới thực tế (dọc có/không thanh gợi ý, ngang),
    /// tối đa 5 hàng như stock, glyph ~ cỡ stock (28–34pt).
    func testEmojiGridCellsAreLargeEnough() {
        for h: CGFloat in [120, 126, 140, 148, 174, 190, 230, 260] {
            let m = EmojiGridMetrics.compute(gridHeight: h)
            XCTAssertGreaterThanOrEqual(m.cell, EmojiGridMetrics.minCell, "h=\(h)")
            XCTAssertLessThanOrEqual(m.rows, 5, "h=\(h)")
            XCTAssertLessThanOrEqual(CGFloat(m.rows) * m.cell, h + 0.01, "h=\(h): lưới tràn")
            XCTAssertTrue((28...34).contains(m.fontSize), "h=\(h) font=\(m.fontSize)")
        }
        // Chiều cao lưới iPhone dọc có thanh gợi ý (252 − tìm 40 − category 36 − đệm): 4 hàng.
        XCTAssertEqual(EmojiGridMetrics.compute(gridHeight: 174).rows, 4)
    }

    /// Thanh tìm luôn hiện trên cùng; chạm → onSearch (vào chế độ tìm với phím chữ).
    @MainActor func testEmojiPlaneHasSearchFieldOnTop() throws {
        let plane = EmojiPlane(dark: true)
        plane.frame = CGRect(x: 0, y: 0, width: w, height: 252)
        plane.layoutIfNeeded()
        let f = try XCTUnwrap(plane.searchField)
        XCTAssertLessThan(f.frame.minY, 10)
        XCTAssertGreaterThanOrEqual(f.frame.height, 30)
        XCTAssertGreaterThan(f.frame.width, w * 0.8, "thanh tìm gần đầy bề ngang như stock")
        var searched = false
        plane.onSearch = { searched = true }
        f.sendActions(for: .touchUpInside)
        XCTAssertTrue(searched)
    }

    // MARK: 2. dark mode

    /// Theme Hệ thống tối khớp stock iOS 27 (đo pixel simulator: nền #202020, phím
    /// #444444, chữ trắng) trong ±6/255 mỗi kênh, KHÔNG sáng hơn stock; chữ ≥ 7:1 trên
    /// phím và cả khi đè; phím tách khỏi nền; theme khác không đổi.
    func testSystemDarkMatchesStockAndContrast() {
        let p = KeyboardTheme.system.palette(systemDark: true)
        let stockKey = RGBA(hex: 0x444444), stockBg = RGBA(hex: 0x202020)
        for (a, b) in [(p.keyFill.r, stockKey.r), (p.keyFill.g, stockKey.g), (p.keyFill.b, stockKey.b)] {
            XCTAssertEqual(a, b, accuracy: 6.0 / 255)
        }
        XCTAssertLessThanOrEqual(p.keyFill.luminance, stockKey.luminance + 0.005, "không sáng hơn stock")
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.keyFill), 7)
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.ink, p.specialFill), 7)
        XCTAssertGreaterThan(RGBA.contrast(p.keyFill, stockBg), 1.4, "phím phải nổi khỏi nền")
        XCTAssertGreaterThanOrEqual(RGBA.contrast(p.barInk, stockBg), 7)
        XCTAssertEqual(KeyboardTheme.oled.palette(systemDark: true).keyFill, RGBA(hex: 0x1C1C1E))
        XCTAssertEqual(KeyboardTheme.system.palette(systemDark: false).keyFill, .white)
    }

    // MARK: 3. thanh gợi ý

    private let sets: [KeyboardView.SuggestionSet] = [
        .init(nextWords: ["Đáp", "Được", "Đi"]),
        .init(nextWords: ["a", "nghiêng nghiêng", "ok"]),
        .init(literal: "đ", word: "đường", emojis: ["🛣️", "🚗"]),
        .init(literal: "xin", word: "xin chào các bạn", word2: "xinh"),
        .init(nextWords: ["và"]),
    ]

    /// Bố cục cố định: 3 ô bằng nhau, vạch ngăn đúng mép ô — không nhảy khi nội dung đổi.
    @MainActor func testSuggestionSlotsHaveFixedGeometry() {
        let (kb, host) = makeKeyboard()
        kb.showSuggestions(sets[0])
        let g0 = kb.debugSuggestionGeometry()
        XCTAssertEqual(g0.cells.count, 3)
        XCTAssertEqual(g0.dividers.count, 2)
        let cw = g0.cells[0].width
        XCTAssertGreaterThan(cw, 60)
        for c in g0.cells { XCTAssertEqual(c.width, cw, accuracy: 0.5) }
        XCTAssertEqual(g0.dividers[0].midX, g0.cells[0].maxX, accuracy: 0.5)
        XCTAssertEqual(g0.dividers[1].midX, g0.cells[1].maxX, accuracy: 0.5)
        for s in sets.dropFirst() {
            kb.showSuggestions(s)
            let g = kb.debugSuggestionGeometry()
            for i in 0..<3 { XCTAssertEqual(g.cells[i], g0.cells[i], "ô \(i) nhảy với \(s.nextWords)\(s.word ?? "")") }
            for i in 0..<2 { XCTAssertEqual(g.dividers[i].midX, g0.dividers[i].midX, accuracy: 0.01) }
            for t in g.visibleTitles {
                XCTAssertTrue(g0.cells.contains { $0.insetBy(dx: -1, dy: -40).contains(t) },
                              "chữ tràn khỏi ô: \(t)")
            }
        }
        withExtendedLifetime(host) {}
    }

    /// Regression: thẻ Dán hiện thì KHÔNG còn chữ gợi ý nào vẽ chung (kể cả sau
    /// rebuild/đổi plane — đường từng đặt lại alpha bar = 1 làm "Đáp" đè "Dán").
    @MainActor func testPasteCardHidesSlotsCompletely() throws {
        let (kb, host) = makeKeyboard()
        kb.showSuggestions(sets[0])
        XCTAssertFalse(kb.debugSuggestionGeometry().visibleTitles.isEmpty)
        var paste = sets[0]; paste.paste = true
        kb.showSuggestions(paste)
        var g = kb.debugSuggestionGeometry()
        let card = try XCTUnwrap(g.pasteCard)
        XCTAssertTrue(g.visibleTitles.isEmpty, "slot bị thẻ Dán thay phải ẩn hẳn")
        kb.debugRefreshChrome()                 // rebuild / xoay / đổi plane
        kb.debugCycleThroughNumbers()
        g = kb.debugSuggestionGeometry()
        if g.pasteCard != nil {
            XCTAssertTrue(g.visibleTitles.filter { $0.intersects(card) }.isEmpty,
                          "chữ gợi ý đè lên thẻ Dán sau rebuild")
        }
        // Gõ chữ → thẻ biến mất, gợi ý hiện lại bình thường.
        kb.hidePasteCard()
        kb.showSuggestions(sets[2])
        g = kb.debugSuggestionGeometry()
        XCTAssertNil(g.pasteCard)
        XCTAssertFalse(g.visibleTitles.isEmpty)
        withExtendedLifetime(host) {}
    }

    // MARK: 4. trackpad

    func testCoalescerMergesSameAxisAndKeepsOrder() {
        var c = TrackpadCoalescer()
        c.add(.init(axis: .horizontal, count: 2))
        c.add(.init(axis: .horizontal, count: 3))
        XCTAssertEqual(c.drain(), [.init(axis: .horizontal, count: 5)])
        XCTAssertTrue(c.isEmpty)
        c.add(.init(axis: .horizontal, count: 1))
        c.add(.init(axis: .vertical, count: -1))
        c.add(.init(axis: .vertical, count: -2))
        XCTAssertEqual(c.drain(), [.init(axis: .horizontal, count: 1), .init(axis: .vertical, count: -3)])
        c.add(.init(axis: .horizontal, count: 2))
        c.add(.init(axis: .horizontal, count: -2))       // triệt tiêu trong frame → không gửi gì
        XCTAssertEqual(c.drain(), [])
        c.add(.init(axis: .horizontal, count: 0))
        XCTAssertTrue(c.isEmpty)
    }

    /// Vệt kéo nhanh mẫu (touch 120Hz, màn 60Hz): cùng quãng dời con trỏ nhưng số lệnh
    /// adjustTextPosition (XPC) giảm; phím mờ ngay khi vào trackpad.
    @MainActor func testTrackpadDragSendsAtMostOneCommandPerFrame() {
        func trace() -> [(x: CGFloat, y: CGFloat, t: CFTimeInterval)] {
            // 0.25s chậm (40pt/s) → 0.5s nhanh (1200pt/s) → 0.5s về trái (800pt/s).
            var out: [(x: CGFloat, y: CGFloat, t: CFTimeInterval)] = []
            var x: CGFloat = 100, t: CFTimeInterval = 0
            let dt = 1.0 / 120
            for _ in 0..<30 { out.append((x, 250, t)); x += 40 * dt; t += dt }
            for _ in 0..<60 { out.append((x, 250, t)); x += 1200 * dt; t += dt }
            for _ in 0..<60 { out.append((x, 250, t)); x -= 800 * dt; t += dt }
            return out
        }
        func run(coalesce: Bool) -> (commands: Int, total: Int, ms: Double) {
            var commands = 0, total = 0
            let (kb, host) = makeKeyboard { key in
                if case .moveCursor(let n) = key { commands += 1; total += n }
            }
            var began: Bool?
            kb.onTrackpad = { on in if began == nil { began = on } }
            let t0 = CACurrentMediaTime()
            kb.debugTrackpadDrag(trace(), frameEvery: 2, coalesce: coalesce)
            let ms = (CACurrentMediaTime() - t0) * 1000
            XCTAssertEqual(began, true)
            XCTAssertFalse(kb.debugTrackpadDimmed, "nhả tay → hết mờ")
            withExtendedLifetime(host) {}
            return (commands, total, ms)
        }
        let before = run(coalesce: false), after = run(coalesce: true)
        print("TRACKPAD before: \(before.commands) lệnh, Σ=\(before.total), \(String(format: "%.2f", before.ms))ms"
              + " | after: \(after.commands) lệnh, Σ=\(after.total), \(String(format: "%.2f", after.ms))ms")
        XCTAssertEqual(after.total, before.total, "cùng quãng dời con trỏ")
        XCTAssertLessThanOrEqual(after.commands, 150 / 2 + 1, "≤ 1 lệnh / frame")
        XCTAssertLessThan(after.commands, before.commands)
    }

    // MARK: 5. ô phóng to chữ

    func testKeyPreviewSettingDefaultsOn() {
        let suite = "kp-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(KeyboardView.keyPreviewSetting(nil))
        XCTAssertTrue(KeyboardView.keyPreviewSetting(d))
        d.set(false, forKey: KeyboardView.keyPreviewKey)
        XCTAssertFalse(KeyboardView.keyPreviewSetting(d))
        d.set(true, forKey: KeyboardView.keyPreviewKey)
        XCTAssertTrue(KeyboardView.keyPreviewSetting(d))
    }

    /// Tắt: bấm phím không tạo/vẽ balloon. Bật: như cũ.
    @MainActor func testKeyPreviewOffCreatesNoBalloon() throws {
        let (kb, host) = makeKeyboard()
        kb.debugSetKeyPreview(false)
        let q = try XCTUnwrap(kb.debugLetterFrame("q"))
        let p = CGPoint(x: q.midX, y: q.midY)
        kb.debugTouch(from: p, through: [p], start: 1)
        XCTAssertFalse(kb.debugBalloonMade)
        kb.debugSetKeyPreview(true)
        let routeT: TimeInterval = 5
        kb.debugTouch(from: p, through: [p], start: routeT)
        XCTAssertTrue(kb.debugBalloonMade)
        withExtendedLifetime(host) {}
    }

    // MARK: 6. mẫu câu mặc định

    /// Nhãn mặc định không dùng ❓ (đỏ — trông như lỗi hiển thị); nội dung câu giữ nguyên.
    func testDefaultTemplateLabelsHaveNoRedQuestionMark() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ios-mau-cau.yml")
        let items = KeyboardView.parseTemplatesYAML(try String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(items.count, 23)
        for i in items { XCTAssertFalse(i.label.contains("❓"), i.label) }
        let texts = items.map(\.text)
        for t in ["Đang ở đâu vậy?", "Đang làm gì vậy", "Lúc nào gặp được nhỉ", "Bạn đang ở đâu?",
                  "https://api.ipify.org"] {
            XCTAssertTrue(texts.contains(t), t)
        }
    }
}
