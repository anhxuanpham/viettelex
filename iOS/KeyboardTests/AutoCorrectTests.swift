import XCTest

/// Tự sửa từ gõ sai (Thử nghiệm) — parity Android AutoCorrectTests.kt (cùng ca, cùng kết quả).
final class AutoCorrectTests: XCTestCase {
    private let bridge = EngineBridge(settings: KeyboardSettings())
    private let center = AutoCorrect.Touch(dx: 0, dy: 0)

    /// Điểm chạm: giữa phím, trừ phím thứ `i` lệch (dx, dy).
    private func touches(_ raw: String, _ i: Int = -1, dx: Float = 0, dy: Float = 0) -> [AutoCorrect.Touch] {
        (0..<raw.count).map { $0 == i ? AutoCorrect.Touch(dx: dx, dy: dy) : center }
    }

    private func fix(_ raw: String, _ t: [AutoCorrect.Touch]? = nil, known: Set<String> = []) -> String? {
        AutoCorrect.correction(raw: raw, touches: t ?? touches(raw), compose: { self.bridge.composeTrial($0) },
                               frequency: { VNSuggest.frequency(of: $0) },
                               hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty },
                               isKnown: { known.contains($0) || AutoCorrect.isEnglish($0) })
    }

    func testOffByDefault() { XCTAssertFalse(KeyboardSettings().autoCorrect) }

    func testFixesSlipTowardNeighbor() {
        XCTAssertEqual(fix("tpoi", touches("tpoi", 1, dx: -0.4)), "tôi")        // p chạm lệch về o
        XCTAssertEqual(fix("Tpoi", touches("Tpoi", 1, dx: -0.4)), "Tôi")
        XCTAssertEqual(fix("nayd", touches("nayd", 3, dx: 0.35)), "này")        // d lệch về f (nảy/nãy kém xa)
        XCTAssertNil(fix("ohims", touches("ohims", 0, dx: 0.4)))               // "phím" (87) không đủ phổ biến
    }

    /// Chạm giữa phím (hoặc lệch về phía khác) ⇒ không phải trượt ⇒ không sửa.
    func testNeedsTouchEvidence() {
        XCTAssertNil(fix("tpoi"))
        XCTAssertNil(fix("tpoi", touches("tpoi", 1, dx: 0.4)))
        XCTAssertNil(fix("tpoi", touches("tpo", 1, dx: -0.4)))                 // thiếu điểm chạm
    }

    func testLeavesValidKnownAndShortWordsAlone() {
        XCTAssertNil(fix("tooi", touches("tooi", 1, dx: 0.4)))                 // đã đúng
        XCTAssertNil(fix("toi", touches("toi", 1, dx: 0.4)))                   // không dấu = từ hợp lệ
        XCTAssertNil(fix("github", touches("github", 5, dx: 0.4)))             // tiếng Anh
        XCTAssertNil(fix("tpoi", touches("tpoi", 1, dx: -0.4), known: ["tpoi"]))   // từ người dùng / từng hoàn tác
        XCTAssertNil(fix("kp", touches("kp", 1, dx: -0.4)))                    // quá ngắn
        XCTAssertNil(fix("tp1i", touches("tp1i", 1, dx: -0.4)))                // có số
    }

    func testEvidenceIsProjectionTowardNeighbor() {
        XCTAssertEqual(AutoCorrect.evidence(center, from: "o", to: "p"), 0, accuracy: 1e-6)
        XCTAssertEqual(AutoCorrect.evidence(.init(dx: 0.4, dy: 0), from: "o", to: "p"), 0.4, accuracy: 1e-6)
        XCTAssertEqual(AutoCorrect.evidence(.init(dx: 0.4, dy: 0), from: "o", to: "i"), -0.4, accuracy: 1e-6)
        XCTAssertGreaterThan(AutoCorrect.evidence(.init(dx: 0, dy: 0.5), from: "h", to: "b"), 0.3)   // hàng dưới
    }

    func testBoundaryCaseAndField() {
        XCTAssertTrue(AutoCorrect.triggers(" ")); XCTAssertTrue(AutoCorrect.triggers(",")); XCTAssertTrue(AutoCorrect.triggers("?"))
        XCTAssertFalse(AutoCorrect.triggers(".")); XCTAssertFalse(AutoCorrect.triggers("\n")); XCTAssertFalse(AutoCorrect.triggers("'"))
        XCTAssertTrue(AutoCorrect.isSentenceStart("")); XCTAssertTrue(AutoCorrect.isSentenceStart("Xong. "))
        XCTAssertFalse(AutoCorrect.isSentenceStart("anh "))
        XCTAssertTrue(AutoCorrect.caseAllows("tpoi", sentenceStart: false))
        XCTAssertTrue(AutoCorrect.caseAllows("Tpoi", sentenceStart: true))
        XCTAssertFalse(AutoCorrect.caseAllows("Tpoi", sentenceStart: false))    // giữa câu = tên riêng
        XCTAssertFalse(AutoCorrect.caseAllows("TPoi", sentenceStart: true))
        XCTAssertTrue(AutoCorrect.fieldAllows(FieldTraits()))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(secure: true)))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(keyboardType: .emailAddress)))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(keyboardType: .URL)))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(keyboardType: .numberPad)))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(keyboardType: .webSearch)))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(autocorrection: .no)))
        XCTAssertFalse(AutoCorrect.fieldAllows(FieldTraits(contentType: .givenName)))
    }

    func testRejectedSetPersistsAndCaps() {
        let r = AutoCorrect.Rejected(cap: 2)
        XCTAssertTrue(r.add("Tpoi")); XCTAssertFalse(r.add("tpoi"))
        XCTAssertTrue(r.contains("TPOI"))
        r.add("b"); r.add("c")
        XCTAssertFalse(r.contains("tpoi"))                                     // cũ nhất bị đẩy ra
        let back = AutoCorrect.Rejected.decode(r.encode())
        XCTAssertTrue(back.contains("b") && back.contains("c")); XCTAssertEqual(back.count, 2)
        XCTAssertEqual(AutoCorrect.Rejected.decode(nil).count, 0)
    }

    func testUndoChipLeadsTheBar() {
        var s = KeyboardView.SuggestionSet(); s.nextWords = ["a", "b", "c"]
        s.actionLabel = "↩︎ tpoi"; s.actionPayload = KeyboardView.undoAutoCorrectToken
        guard case .slots(let sl, _) = SuggestionSlots.arrange(s) else { return XCTFail() }
        XCTAssertEqual(sl.map { $0?.payload ?? "-" }, [KeyboardView.undoAutoCorrectToken, "a", "b"])
    }

    func testRetractUndoesOneRecord() {
        let m = UserLangModel(appGroup: nil)
        m.record(word: "anh", after: nil); m.record(word: "anh", after: nil)
        let r = m.record(word: "tôi", after: "anh")
        XCTAssertEqual(m.count(of: "tôi"), 1)
        m.retract(r!)
        XCTAssertEqual(m.count(of: "tôi"), 0)
        XCTAssertEqual(m.count(of: "anh"), 2)
        XCTAssertFalse(m.isUserWord("anh"))
        m.record(word: "anh", after: nil)
        XCTAssertTrue(m.isUserWord("Anh"))                                    // ≥ 3 lần = từ của người dùng
    }

    // MARK: EngineBridge (phần controller làm: điểm chạm + từ đã biết → closure)

    /// Bridge có tự sửa: phím thứ `slip` của mỗi từ chạm lệch dx (âm = về trái).
    private func acBridge(slip: Int = 1, dx: Float = -0.4, settings: KeyboardSettings = KeyboardSettings()) -> EngineBridge {
        let b = EngineBridge(settings: settings)
        b.autoCorrector = { [unowned b] raw in
            AutoCorrect.correction(raw: raw, touches: (0..<raw.count).map { $0 == slip ? .init(dx: dx, dy: 0) : .init(dx: 0, dy: 0) },
                                   compose: { b.composeTrial($0) }, frequency: { VNSuggest.frequency(of: $0) },
                                   hasCompletion: { !VNSuggest.matches($0, poolLimit: 1).isEmpty },
                                   isKnown: { AutoCorrect.isEnglish($0) })
        }
        return b
    }

    private func type(_ b: EngineBridge, _ p: MockProxy, _ keys: String) {
        for ch in keys {
            if ch == " " { b.boundary(" ", proxy: p) } else if ch == "." { b.boundary(".", proxy: p) }
            else { b.letter(ch, proxy: p) }
        }
    }

    func testBridgeCorrectsAtSpaceAndBackspaceRestores() {
        let b = acBridge(), p = MockProxy()
        type(b, p, "tpoi ")
        XCTAssertEqual(p.text, "tôi ")
        XCTAssertTrue(b.expandedAtLastBoundary)
        XCTAssertEqual(b.autoCorrectUndo?.original, "tpoi")
        XCTAssertEqual(b.autoCorrectUndo?.fixed, "tôi")
        b.backspace(proxy: p)
        XCTAssertEqual(p.text, "tpoi ")                                        // giữ dấu cách như hoàn tác gõ tắt
        XCTAssertEqual(b.revertedAutoCorrect, "tpoi")
        XCTAssertNil(b.autoCorrectUndo)
        b.backspace(proxy: p)
        XCTAssertEqual(p.text, "tpoi")                                         // ⌫ thứ hai = ⌫ thường
    }

    func testBridgeChipRevertsAndNextKeyDropsOffer() {
        let b = acBridge(), p = MockProxy()
        type(b, p, "tpoi ")
        XCTAssertTrue(b.revertAutoCorrect(proxy: p))
        XCTAssertEqual(p.text, "tpoi ")
        XCTAssertFalse(b.revertAutoCorrect(proxy: p))
        let c = acBridge(), q = MockProxy()
        type(c, q, "tpoi a")
        XCTAssertNil(c.autoCorrectUndo)                                        // chỉ sống tới phím kế
    }

    func testBridgeSkipsCaseGlueDotAndEnglishMode() {
        let a = acBridge(), p = MockProxy(); p.text = "gặp "
        type(a, p, "Tpoi ")
        XCTAssertEqual(p.text, "gặp Tpoi ")                                   // hoa giữa câu = tên riêng
        let b = acBridge(), q = MockProxy(); q.text = "a@"
        type(b, q, "tpoi ")
        XCTAssertEqual(q.text, "a@tpoi ")                                      // dính email/URL
        let c = acBridge(), r = MockProxy()
        type(c, r, "tpoi.")
        XCTAssertEqual(r.text, "tpoi.")                                        // "." không sửa (tên miền)
        let d = acBridge(), s = MockProxy()
        _ = d.setEnglish(true, proxy: s)
        type(d, s, "tpoi ")
        XCTAssertEqual(s.text, "tpoi ")                                        // chế độ Tiếng Anh
        let e = EngineBridge(settings: KeyboardSettings()), t = MockProxy()
        type(e, t, "tpoi ")
        XCTAssertEqual(t.text, "tpoi ")                                        // tắt (không closure)
        let f = acBridge(), u = MockProxy()
        f.reachBackAllowed = false                                             // omnibox
        type(f, u, "tpoi ")
        XCTAssertEqual(u.text, "tpoi ")
    }

    func testSentenceStartCapitalFixed() {
        let b = acBridge(), p = MockProxy(); p.text = "Xong. "
        type(b, p, "Tpoi ")
        XCTAssertEqual(p.text, "Xong. Tôi ")
    }
}
