import XCTest

/// Thứ tự ưu tiên slot thanh gợi ý (SuggestionSlots) — CÙNG bảng ca với Android
/// SuggestionSlotsTests.kt (so payload). Tầng: hoàn tác > clipboard > "Thêm dấu" >
/// chip số (giữa) > chữ.
final class SuggestionSlotsTests: XCTestCase {
    typealias S = KeyboardView.SuggestionSet
    private let N = KeyboardView.numberToken
    private let ADD = KeyboardView.addTonesToken
    private let UNDO = KeyboardView.undoTonesToken
    private let PASTE = KeyboardView.pasteToken
    private func clip(_ v: String) -> String { KeyboardView.clipTokenPrefix + v }
    private var otp: (display: String, insert: String) { ("Dán OTP 482913", clip("482913")) }
    private var stk: (display: String, insert: String) { ("Dán STK 0123456789", clip("0123456789")) }

    private func payloads(_ set: S, pill: Bool = false, middle: Bool = false) -> String {
        switch SuggestionSlots.arrange(set, undoAsPill: pill, bestInMiddle: middle) {
        case .pill(let c): return "pill:" + c.payload
        case .pasteCard: return "paste"
        case .chips(let c): return "chips:" + c.map(\.payload).joined(separator: "|")
        case .slots(let s, let e):
            return s.map { $0?.payload ?? "-" }.joined(separator: "|") + (e.isEmpty ? "" : " e:" + e.joined())
        }
    }

    func testWordsOnly() {
        var s = S(); s.literal = "anh"; s.word = "ánh"; s.word2 = "ảnh"
        XCTAssertEqual(payloads(s), "anh|ánh|ảnh")
        s.emojis = ["😀"]
        XCTAssertEqual(payloads(s), "anh|ánh|- e:😀")
        var n = S(); n.nextWords = ["a", "b", "c"]
        XCTAssertEqual(payloads(n), "a|b|c")
        XCTAssertEqual(payloads(n, middle: true), "b|a|c")
        // nhãn nguyên văn iOS có ngoặc kép, payload là chữ thô
        if case .slots(let sl, _) = SuggestionSlots.arrange(s) { XCTAssertEqual(sl[0]?.label, "\u{201C}anh\u{201D}") }
    }

    func testNumberChipAlwaysMiddle() {
        var s = S(); s.literal = "12"; s.word = "mười"; s.number = "mười hai"
        XCTAssertEqual(payloads(s), "12|\(N)|mười")
        s.emojis = ["😀"]
        XCTAssertEqual(payloads(s), "12|\(N)|- e:😀")
        var n = S(); n.nextWords = ["a", "b", "c"]; n.number = "x"
        XCTAssertEqual(payloads(n), "a|\(N)|b")
    }

    func testUndoBeatsEverything() {
        var busy = S(); busy.nextWords = ["a", "b"]; busy.paste = true; busy.clipChips = [otp]
        busy.number = "x"; busy.actionLabel = "Thêm dấu"; busy.actionPayload = ADD
        busy.restoreLabel = "↩︎ Khôi phục"
        XCTAssertEqual(payloads(busy), "\(KeyboardView.restoreToken)|\(N)|a")
        XCTAssertEqual(payloads(busy, pill: true), "pill:\(KeyboardView.restoreToken)")
        busy.restorePayload = KeyboardView.toolUndoToken          // hoàn tác công cụ văn bản
        XCTAssertEqual(payloads(busy), "\(KeyboardView.toolUndoToken)|\(N)|a")
        var tones = S(); tones.nextWords = ["a", "b"]; tones.number = "x"
        tones.actionLabel = "↩︎ Hoàn tác"; tones.actionPayload = UNDO
        XCTAssertEqual(payloads(tones), "\(UNDO)|\(N)|a")
        XCTAssertEqual(payloads(tones, pill: true), "pill:\(UNDO)")
        var typing = S(); typing.literal = "anh"; typing.word = "ánh"; typing.restoreLabel = "↩︎ Khôi phục"
        XCTAssertEqual(payloads(typing), "\(KeyboardView.restoreToken)|anh|ánh")
    }

    func testClipboardBeatsAddTonesAndNumber() {
        var s = S(); s.nextWords = ["a"]; s.paste = true; s.clipChips = [otp, stk, otp]; s.number = "x"
        s.actionLabel = "Thêm dấu"; s.actionPayload = ADD
        XCTAssertEqual(payloads(s), "chips:\(clip("482913"))|\(clip("0123456789"))|\(PASTE)")
        s.clipChips = []
        XCTAssertEqual(payloads(s), "paste")
        s.paste = false; s.clipChips = [otp]
        XCTAssertEqual(payloads(s), "chips:\(clip("482913"))")
    }

    func testAddTonesLeadsThenNumberMiddle() {
        var s = S(); s.nextWords = ["a", "b", "c"]; s.actionLabel = "Thêm dấu"; s.actionPayload = ADD
        XCTAssertEqual(payloads(s), "\(ADD)|a|b")
        XCTAssertEqual(payloads(s, middle: true), "\(ADD)|a|b")
        s.number = "x"
        XCTAssertEqual(payloads(s), "\(ADD)|\(N)|a")
    }

    /// "↩︎ từ cũ" sau khi vuốt sửa lại từ trước: slot đầu, biến thể vuốt dời phải.
    func testReviseUndoLeadsSwipeAlternatives() {
        let r = KeyboardView.undoReviseToken
        var s = S(); s.nextWords = ["a", "b", "c"]; s.actionLabel = "↩︎ có"; s.actionPayload = r
        XCTAssertEqual(payloads(s), "\(r)|a|b")
        XCTAssertEqual(payloads(s, pill: true), "\(r)|a|b")
    }

    /// Đường thật trên KeyboardView: chip số giữa + "Thêm dấu" đầu; clipboard thay bar.
    @MainActor func testKeyboardViewRendersArrangement() throws {
        let kb = KeyboardView(needsGlobe: false, inputController: nil, onKey: { _ in })
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 320))
        host.addSubview(kb); kb.frame = host.bounds
        kb.setSuggestionsEnabled(true)
        kb.layoutIfNeeded()
        var s = S(); s.nextWords = ["a", "b", "c"]; s.number = "x"; s.actionLabel = "Thêm dấu"; s.actionPayload = ADD
        kb.showSuggestions(s)
        XCTAssertEqual(kb.debugSlotPayloads(), [ADD, N, "a"])
        var c = S(); c.paste = true; c.clipChips = [otp]; c.number = "x"
        kb.showSuggestions(c)
        XCTAssertEqual(kb.debugSlotPayloads(), [clip("482913"), PASTE, nil])
    }
}
