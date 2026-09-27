import XCTest
import UIKit

/// Công tắc hiệu năng (27/09/2026): tính năng phụ TẮT ⇒ không đọc context / không nạp dữ
/// liệu / không lên lịch việc mỗi phím. Chạy controller thật với proxy giả (KeyboardBenchTests.Rig).
final class PerfSwitchTests: XCTestCase {
    // Chip "Thêm dấu" là Plus — test công tắc hiệu năng với paywall mở; gating ở PlusTests.
    private var savedPaywall = false
    override func setUp() { super.setUp(); savedPaywall = PlusGate.paywallEnabled; PlusGate.paywallEnabled = false }
    override func tearDown() { PlusGate.paywallEnabled = savedPaywall; super.tearDown() }

    func testNewSettingsDefaultsAndLoad() {
        let s = KeyboardSettings()
        XCTAssertFalse(s.addTonesChip)          // chip "Thêm dấu" mặc định TẮT
        XCTAssertTrue(s.numberChips)
        XCTAssertTrue(s.emojiSuggest)
        XCTAssertTrue(s.pasteButton)
        XCTAssertTrue(s.autoCapitalize)
        let d = UserDefaults(suiteName: "vt-perf-switch")!
        d.removePersistentDomain(forName: "vt-perf-switch")
        d.set(true, forKey: "addTonesChip"); d.set(false, forKey: "numberChips")
        d.set(false, forKey: "emojiSuggest"); d.set(false, forKey: "pasteButton")
        d.set(false, forKey: "autoCapitalize")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved }
        let l = KeyboardSettings.load()
        XCTAssertTrue(l.addTonesChip)
        XCTAssertFalse(l.numberChips)
        XCTAssertFalse(l.emojiSuggest)
        XCTAssertFalse(l.pasteButton)
        XCTAssertFalse(l.autoCapitalize)
    }

    /// Không có người dùng checkpoint (iPhone, gõ vuốt tắt) ⇒ không chụp engine mỗi phím;
    /// chữ ra y hệt, chỉ là không huỷ được phím.
    func testLetterUndoDisabledSameOutput() {
        final class P: TextProxyLike {
            var text = ""
            func insertText(_ t: String) { text += t }
            func deleteBackward() { if !text.isEmpty { text.removeLast() } }
            var isSecure: Bool { false }
            var contextBeforeInput: String? { text }
            var contextAfterInput: String? { nil }
            var hasSelection: Bool { false }
        }
        let on = EngineBridge(settings: KeyboardSettings()), off = EngineBridge(settings: KeyboardSettings())
        off.letterUndoEnabled = false
        let po = P(), pf = P()
        for c in "tieengs vieetj " {
            if c == " " { on.boundary(" ", proxy: po); off.boundary(" ", proxy: pf) }
            else { on.letter(c, proxy: po); off.letter(c, proxy: pf) }
        }
        on.letter("a", proxy: po); off.letter("a", proxy: pf)
        XCTAssertEqual(po.text, "tiếng việt a")
        XCTAssertEqual(pf.text, po.text)
        XCTAssertTrue(on.undoLastLetter(proxy: po))
        XCTAssertFalse(off.undoLastLetter(proxy: pf))
    }

    @MainActor private func type(_ rig: KeyboardBenchTests.Rig, _ s: String) {
        for (i, c) in s.enumerated() { _ = rig.key(c, index: i + 1, drain: 0.04) }
    }

    /// Mọi tính năng phụ tắt: phím CHỮ không đọc context lần nào (chỉ ranh giới từ: auto-shift;
    /// fail-safe CompositionSync khi engine xoá ≥2 ký tự — "tiêng"+s — là lõi, không tính ở đây).
    @MainActor func testAllOffLettersReadNoContext() {
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("C")
        defer { UserDefaultsProvider.shared = saved }
        let rig = KeyboardBenchTests.Rig()
        defer { rig.close() }
        type(rig, "xin chaof ")
        rig.proxy.contextReads = 0
        type(rig, "xinhh")
        XCTAssertEqual(rig.proxy.contextReads, 0)
        XCTAssertEqual(rig.proxy.text, "Xin chào xinhh")
    }

    /// Chip "Thêm dấu": tắt (mặc định) ⇒ không mời; bật ⇒ mời sau dấu cách.
    @MainActor func testAddTonesChipOnlyWhenEnabled() {
        let saved = UserDefaultsProvider.shared
        defer { UserDefaultsProvider.shared = saved }
        for on in [false, true] {
            let d = KeyboardBenchTests.makeDefaults("B")
            d.set(on, forKey: "addTonesChip")
            UserDefaultsProvider.shared = d
            let rig = KeyboardBenchTests.Rig()
            type(rig, "toi di hoc ")
            KeyboardBenchTests.spin(0.1)
            let payloads = rig.vc.debugKeyboard.debugSlotPayloads()
            XCTAssertEqual(payloads.contains(KeyboardView.addTonesToken), on, "addTonesChip=\(on)")
            rig.close()
        }
    }

    /// topWords cập nhật top-K tại chỗ sau mỗi record — phải trùng khớp sort đầy đủ.
    func testTopWordsIncrementalMatchesFullSort() {
        var rng = SystemRandomNumberGenerator()
        let vocab = (0..<60).map { "w" + String(UnicodeScalar(UInt8(97 + $0 % 26))) + String(repeating: "a", count: $0 / 26) }
        let inc = UserLangModel(appGroup: nil)
        inc.isKnownWord = { !$0.hasSuffix("aa") }        // một số từ lạ: cần ≥3 lần mới gợi ý
        for step in 0..<400 {
            let w = vocab[Int.random(in: 0..<vocab.count, using: &rng)]
            inc.record(word: w, after: nil, weight: step % 7 == 0 ? 2 : 1)
            let got = inc.topWords(limit: 14)
            let fresh = UserLangModel(appGroup: nil)
            fresh.isKnownWord = inc.isKnownWord
            // dựng lại cùng count qua record (weight 1 lặp)
            for (word, n) in inc.debugUnigrams() { for _ in 0..<n { fresh.record(word: word, after: nil) } }
            XCTAssertEqual(got, fresh.topWords(limit: 14), "bước \(step)")
        }
    }
}
