import XCTest
import TelexCore
@testable import VietTelex

/// Gõ tắt macOS khớp iOS/Android (iOS/KeyboardTests/ShortcutTests.swift — cùng bộ ca):
/// hoa/thường, khoá ký hiệu/số, ranh giới, #82/#87, ⌫ hoàn tác, nhiều dòng, file YAML.
/// Phần luồng dùng một MÔ HÌNH màn hình in-place (Screen) ghép đúng các mảnh thuần mà
/// TelexInputController/TerminalTap dùng: TelexEngine + ShortcutMatch + ShortcutTail +
/// ShortcutScreen + ShortcutUndo.
final class ShortcutExpansionTests: XCTestCase {

    private let table = ShortcutTable([
        "ko": "không", "đc": "được", "mn": "mọi người", "->": "→", "/shop": "cửa hàng", "k2": "không hai",
        "h": "giờ", "HN": "Hà Nội", "sig": "Thân mến,\nPhil", "j": "gì", "√√": "căn",
        ":D": "😀", "1tr": "một triệu",
    ])

    // MARK: - Mô hình màn hình in-place (IMKit đã verify / tap đã neo)

    /// Một ô văn bản, con trỏ luôn ở cuối. `ours` là chữ mình đã đưa lên màn hình.
    private struct Screen {
        var text = ""
        var engine = TelexEngine()
        var tail = ShortcutTail()
        var undo: ShortcutUndo?
        var glued = false
        let table: ShortcutTable

        init(_ table: ShortcutTable) { self.table = table }

        mutating func replaceSuffix(scalars bs: Int, with insert: String) {
            var sc = Array(text.unicodeScalars)
            sc.removeLast(min(bs, sc.count))
            text = String(String.UnicodeScalarView(sc)) + insert
        }

        /// Thay range UTF-16 (như insertText(_:replacementRange:)).
        mutating func replace(_ r: NSRange, with s: String) {
            text = (text as NSString).replacingCharacters(in: r, with: s)
        }

        /// Controller: đọc cửa sổ + xác nhận (ShortcutScreen), như tryTokenShortcut.
        func tokenRange(_ token: String) -> NSRange? {
            let caret = (text as NSString).length
            guard let w = ShortcutScreen.readWindow(caret: caret, text: token) else { return nil }
            return ShortcutScreen.tokenRange(caret: caret, token: token,
                                             window: (text as NSString).substring(with: w), windowStart: w.location)
        }

        mutating func type(_ keys: String) {
            for ch in keys {
                if ch == "⌫" { backspace(); continue }
                let undoNow = undo; undo = nil
                _ = undoNow
                if ch.isLetter, ch.isASCII {
                    if case let .replace(bs, ins) = engine.feed(ch) { replaceSuffix(scalars: bs, with: ins) }
                    else { text.append(ch) }
                    continue
                }
                boundary(String(ch))
            }
        }

        mutating func boundary(_ b: String) {
            let allow = ShortcutMatch.triggers(boundary: b, glued: glued)
            var expanded: (String, String)?
            let word = engine.composed
            switch ShortcutMatch.find(in: table, composed: word, raw: engine.rawKeystrokes,
                                      run: tail.run, allowWord: allow.word, allowToken: allow.token) {
            case let .word(e)?:
                replaceSuffix(scalars: word.unicodeScalars.count, with: e)
                engine.reset()
                tail.append(e)
                expanded = (word, e)
            case let .token(token, e)?:
                if let r = tokenRange(token) {
                    engine.reset()
                    replace(r, with: e)
                    tail.replaceRun(with: e)
                    expanded = (token, e)
                } else {
                    fallthrough
                }
            default:
                if !engine.isEmpty {
                    let restored = engine.commitText(autoRestore: true)
                    replaceSuffix(scalars: word.unicodeScalars.count, with: restored)
                    tail.append(restored)
                }
            }
            text += b
            glued = TelexInputController.gluesShortcutToken(b.utf8.first)
            tail.append(b)
            if let x = expanded { undo = ShortcutUndo.make(typed: x.0, expansion: x.1, boundary: b) }
        }

        mutating func backspace() {
            let u = undo; undo = nil
            glued = false
            if engine.isEmpty {
                if let u {
                    let caret = (text as NSString).length
                    if let w = ShortcutScreen.readWindow(caret: caret, text: u.onScreen),
                       let r = ShortcutScreen.undoRange(caret: caret, undo: u,
                                                        window: (text as NSString).substring(with: w),
                                                        windowStart: w.location) {
                        replace(r, with: u.restored)
                        tail.reset(); tail.append(u.restored)
                        return
                    }
                }
                tail.backspace()
                if !text.isEmpty { text.removeLast() }
                return
            }
            let before = engine.composed
            if case let .replace(bs, ins) = engine.backspace() { replaceSuffix(scalars: bs, with: ins) }
            else { _ = before; text.removeLast() }
        }
    }

    private func typed(_ keys: String, _ t: ShortcutTable? = nil) -> String {
        var s = Screen(t ?? table)
        s.type(keys)
        return s.text
    }

    // MARK: - Hàm thuần (cùng ca iOS)

    func testCaseFollowsTyping() {
        XCTAssertEqual(table.expansion(for: "ko"), "không")
        XCTAssertEqual(table.expansion(for: "Ko"), "Không")
        XCTAssertEqual(table.expansion(for: "KO"), "KHÔNG")
        XCTAssertNil(table.expansion(for: "kO"))                 // hoa lộn xộn: không đoán
        XCTAssertEqual(table.expansion(for: "Mn"), "Mọi người")
        XCTAssertEqual(table.expansion(for: "MN"), "MỌI NGƯỜI")
        XCTAssertEqual(table.expansion(for: "J"), "Gì")
        XCTAssertEqual(table.expansion(for: "HN"), "Hà Nội")     // khoá ghi đúng y hệt thắng
        XCTAssertNil(table.expansion(for: "hn"))
    }

    func testWordMatchComposedThenRaw() {
        XCTAssertEqual(table.wordExpansion(composed: "đc", raw: "ddc"), "được")
        XCTAssertNil(table.wordExpansion(composed: "dc", raw: "dc"))
        let t3 = ShortcutTable(["ks": "khách sạn"])
        XCTAssertEqual(t3.wordExpansion(composed: "kś", raw: "ks"), "khách sạn")
        XCTAssertEqual(t3.wordExpansion(composed: "Kś", raw: "Ks"), "Khách sạn")
    }

    func testTriggers() {
        XCTAssertTrue(ShortcutMatch.triggers(boundary: " ", glued: false) == (true, true))
        XCTAssertTrue(ShortcutMatch.triggers(boundary: ",", glued: false) == (true, false))
        XCTAssertTrue(ShortcutMatch.triggers(boundary: "\n", glued: false) == (true, true))
        XCTAssertTrue(ShortcutMatch.triggers(boundary: "1", glued: false) == (false, false))
        XCTAssertTrue(ShortcutMatch.triggers(boundary: "-", glued: false) == (false, false))
        XCTAssertTrue(ShortcutMatch.triggers(boundary: "", glued: false) == (false, false))   // mũi tên
        XCTAssertTrue(ShortcutMatch.triggers(boundary: nil, glued: false) == (true, false))   // Esc: cũ
        XCTAssertTrue(ShortcutMatch.triggers(boundary: " ", glued: true) == (false, true))
    }

    func testFindTokenNeedsWholeRun() {
        func find(_ run: String, _ composed: String = "") -> ShortcutMatch? {
            ShortcutMatch.find(in: table, composed: composed, raw: composed, run: run,
                               allowWord: true, allowToken: true)
        }
        XCTAssertEqual(find("->"), .token(token: "->", expansion: "→"))
        XCTAssertNil(find("a->"))                                // "a->b" / "a->" không nở
        XCTAssertEqual(find("k2"), .token(token: "k2", expansion: "không hai"))
        XCTAssertEqual(find(":", "D"), .token(token: ":D", expansion: "😀"))
        XCTAssertEqual(find("1", "tr"), .token(token: "1tr", expansion: "một triệu"))
        XCTAssertEqual(find("", "ko"), .word(expansion: "không"))
        XCTAssertNil(find("ko"))                                 // khoá chữ không đi đường token
        XCTAssertNil(ShortcutMatch.find(in: ShortcutTable(["ko": "không"]), composed: "", raw: "",
                                        run: "->", allowWord: true, allowToken: true))
    }

    func testTail() {
        var t = ShortcutTail()
        t.append("a ->")
        XCTAssertEqual(t.run, "->"); XCTAssertTrue(t.anchored)
        t.backspace(); XCTAssertEqual(t.run, "-")
        t.backspace(); t.backspace()                             // xoá cả khoảng trắng
        XCTAssertEqual(t.run, ""); XCTAssertFalse(t.anchored)
        t.append("->"); XCTAssertEqual(t.run, "->"); XCTAssertFalse(t.anchored)
        t.append("\n"); XCTAssertTrue(t.anchored); XCTAssertEqual(t.run, "")
        t.append(String(repeating: "x", count: 70))              // quá dài: mất neo
        XCTAssertFalse(t.anchored)
        t.reset(); t.append(" k2"); t.replaceRun(with: "không hai")
        XCTAssertEqual(t.run, "hai"); XCTAssertTrue(t.anchored)
    }

    /// #104: `recent`/`knownText` — văn bản chắc chắn trước con trỏ dựng từ dòng phím.
    func testTailKnownText() {
        var t = ShortcutTail()
        XCTAssertNil(t.knownText)                                // chưa biết gì
        t.caretMoved()
        XCTAssertEqual(t.knownText, "")                          // vừa click: đầu phần đã biết
        t.append("12 * 3")
        XCTAssertEqual(t.knownText, "12 * 3"); XCTAssertEqual(t.run, "3")
        t.backspace(); XCTAssertEqual(t.knownText, "12 * ")
        t.backspace(); t.backspace(); t.backspace(); t.backspace(); t.backspace()
        XCTAssertEqual(t.knownText, "")
        t.backspace()                                            // xoá chữ có từ trước click
        XCTAssertNil(t.knownText)
        // Khoá ký hiệu nở: đuôi recent đổi theo.
        t.caretMoved(); t.append("a k2"); t.replaceRun(with: "không hai")
        XCTAssertEqual(t.knownText, "a không hai")
        // Áp dụng gợi ý: đuôi khớp ⇒ thay; giữ "đầu đã biết" và neo.
        t.caretMoved(); t.append("50k ")
        t.replaceSuffix("50k ", with: "50.000 ₫ ")
        XCTAssertEqual(t.knownText, "50.000 ₫ "); XCTAssertTrue(t.anchored); XCTAssertEqual(t.run, "")
        t.replaceSuffix("zzz", with: "x")                        // không khớp ⇒ chỉ còn chữ mới
        XCTAssertNil(t.knownText); XCTAssertEqual(t.run, "x")
        // Cắt đầu (dài quá maxRecent) ⇒ chỉ còn phần từ khoảng trắng đầu tiên.
        t.caretMoved()
        t.append(String(repeating: "ab ", count: 50))
        XCTAssertFalse(t.recentWhole)
        XCTAssertEqual(t.knownText?.first, " ")
        XCTAssertLessThanOrEqual(t.recent.count, ShortcutTail.maxRecent + 32)
        // Click / phím điều hướng: reset + đầu mới.
        t.caretMoved(); XCTAssertEqual(t.knownText, "")
        t.reset(); XCTAssertNil(t.knownText)
    }

    func testScreenVerify() {
        // "a ->|" → range của "->"
        XCTAssertEqual(ShortcutScreen.tokenRange(caret: 4, token: "->", window: " ->", windowStart: 1),
                       NSRange(location: 2, length: 2))
        // đầu ô
        XCTAssertEqual(ShortcutScreen.tokenRange(caret: 2, token: "->", window: "->", windowStart: 0),
                       NSRange(location: 0, length: 2))
        XCTAssertNil(ShortcutScreen.tokenRange(caret: 3, token: "->", window: "a->", windowStart: 0))
        XCTAssertNil(ShortcutScreen.tokenRange(caret: 3, token: "->", window: " =>", windowStart: 0))
        XCTAssertNil(ShortcutScreen.tokenRange(caret: 5, token: "->", window: " ->", windowStart: 1)) // lệch caret
        XCTAssertEqual(ShortcutScreen.readWindow(caret: 10, text: "->"), NSRange(location: 7, length: 3))
        XCTAssertEqual(ShortcutScreen.readWindow(caret: 2, text: "->"), NSRange(location: 0, length: 2))
        XCTAssertNil(ShortcutScreen.readWindow(caret: 1, text: "->"))
        // hoàn tác: màn hình phải kết thúc đúng bằng nội dung + ranh giới (UTF-16 chính xác)
        let u = ShortcutUndo(typed: "ko", expansion: "không", boundary: " ")
        XCTAssertEqual(ShortcutScreen.undoRange(caret: 8, undo: u, window: "x không ", windowStart: 0),
                       NSRange(location: 2, length: 6))
        XCTAssertNil(ShortcutScreen.undoRange(caret: 8, undo: u, window: "x khong  ", windowStart: 0))
        let nfd = "kho\u{0302}ng "                                  // NFD: String == nhưng UTF-16 khác
        XCTAssertNil(ShortcutScreen.undoRange(caret: (nfd as NSString).length, undo: u, window: nfd, windowStart: 0))
    }

    func testUndoOnlyOneCharBoundary() {
        XCTAssertNotNil(ShortcutUndo.make(typed: "ko", expansion: "không", boundary: " "))
        XCTAssertNotNil(ShortcutUndo.make(typed: "ko", expansion: "không", boundary: ","))
        XCTAssertNil(ShortcutUndo.make(typed: "ko", expansion: "không", boundary: "\n"))   // Enter
        XCTAssertNil(ShortcutUndo.make(typed: "ko", expansion: "không", boundary: "\t"))
        XCTAssertNil(ShortcutUndo.make(typed: "ko", expansion: "không", boundary: nil))
    }

    func testInsertedText() {
        XCTAssertEqual(ShortcutScreen.insertedText(" "), " ")
        XCTAssertEqual(ShortcutScreen.insertedText("√"), "√")
        XCTAssertNil(ShortcutScreen.insertedText("\u{F702}"))    // mũi tên
        XCTAssertNil(ShortcutScreen.insertedText("\u{1B}"))
        XCTAssertNil(ShortcutScreen.insertedText("ab"))
        XCTAssertNil(ShortcutScreen.insertedText(nil))
    }

    // MARK: - Luồng (mô hình in-place)

    func testExpandsOnBoundaries() {
        XCTAssertEqual(typed("ko "), "không ")
        XCTAssertEqual(typed("Ko,"), "Không,")
        XCTAssertEqual(typed("KO."), "KHÔNG.")
        XCTAssertEqual(typed("kO "), "kO ")
        XCTAssertEqual(typed("mn!"), "mọi người!")
        XCTAssertEqual(typed("ko\n"), "không\n")
        XCTAssertEqual(typed("ddc "), "được ")
        XCTAssertEqual(typed("dc "), "dc ")
        XCTAssertEqual(typed("sig "), "Thân mến,\nPhil ")     // nhiều dòng
    }

    /// Khoá có tiền tố dấu câu (fork vtx "/shop"): cả cụm trước con trỏ khớp khoá ký hiệu.
    func testPunctuationPrefixKey() {
        XCTAssertEqual(typed("/shop "), "cửa hàng ")
        XCTAssertEqual(typed("xem /shop "), "xem cửa hàng ")
        XCTAssertEqual(typed("a/shop "), "a/shop ")          // dính chữ trước ⇒ không nở
        XCTAssertEqual(typed("/h "), "/h ")                  // #87 vẫn giữ
    }

    func testNotOnNonTriggerOrGlued() {
        XCTAssertEqual(typed("ko1"), "ko1")
        XCTAssertEqual(typed("ko-"), "ko-")
        XCTAssertEqual(typed("5h "), "5h ")                    // #82
        XCTAssertEqual(typed("5h30"), "5h30")
        XCTAssertEqual(typed("5 h "), "5 giờ ")
        XCTAssertEqual(typed("/h "), "/h ")                    // #87
        XCTAssertEqual(typed("a@ko "), "a@ko ")
        XCTAssertEqual(typed("a.ko "), "a.ko ")
        XCTAssertEqual(typed("a_ko "), "a_ko ")
        XCTAssertEqual(typed("a-ko "), "a-ko ")
    }

    func testSymbolAndDigitKeys() {
        XCTAssertEqual(typed("a -> b"), "a → b")
        XCTAssertEqual(typed("-> "), "→ ")
        XCTAssertEqual(typed("k2 "), "không hai ")
        XCTAssertEqual(typed("a->b "), "a->b ")
        XCTAssertEqual(typed("a-> "), "a-> ")
        XCTAssertEqual(typed("->,"), "->,")                    // khoá ký hiệu chỉ nở ở space/Enter
        XCTAssertEqual(typed("->\n"), "→\n")
        XCTAssertEqual(typed("x :D "), "x 😀 ")
        XCTAssertEqual(typed("1tr "), "một triệu ")
        XCTAssertEqual(typed("√√ "), "căn ")
    }

    func testBackspaceRestoresTypedOnce() {
        var s = Screen(table)
        s.type("ko ")
        XCTAssertEqual(s.text, "không ")
        s.type("⌫"); XCTAssertEqual(s.text, "ko ")
        s.type("⌫"); XCTAssertEqual(s.text, "ko")              // lần hai: ⌫ thường
        s.type(" "); XCTAssertEqual(s.text, "ko ")             // không nở lại

        var s2 = Screen(table)
        s2.type("KO a -> ")
        XCTAssertEqual(s2.text, "KHÔNG a → ")
        s2.type("⌫"); XCTAssertEqual(s2.text, "KHÔNG a -> ")
        s2.type("⌫⌫"); XCTAssertEqual(s2.text, "KHÔNG a -")

        var s3 = Screen(table)
        s3.type("Ko,⌫"); XCTAssertEqual(s3.text, "Ko,")        // giữ ranh giới
    }

    func testBackspaceUndoOnlyImmediately() {
        XCTAssertEqual(typed("ko a⌫"), "không ")
        XCTAssertEqual(typed("ko\n⌫"), "không")                // Enter không hứa hoàn tác
        var s = Screen(table)
        s.type("ko ")
        s.text = "khác "                                        // host đổi chữ
        s.type("⌫")
        XCTAssertEqual(s.text, "khác")                          // ⌫ thường, không xoá mù
    }

    func testTokenScreenMismatchDoesNothing() {
        // Cụm dựng từ phím khớp "->" nhưng màn hình có chữ dính trước (click giữa chừng
        // mà mình không thấy) ⇒ không đụng.
        var s = Screen(table)
        s.text = "a"
        s.type("-> ")
        XCTAssertEqual(s.text, "a-> ")
    }

    // MARK: - Tap: xuống dòng + neo

    func testTapLineBreakIsShiftReturn() {
        XCTAssertTrue(SyntheticKeyboard.isLineBreakChunk("\n"))
        XCTAssertTrue(SyntheticKeyboard.isLineBreakChunk("\r\n"))
        XCTAssertFalse(SyntheticKeyboard.isLineBreakChunk(" "))
        SyntheticKeyboard._testPostUnicode("a,\nPh")
        XCTAssertEqual(SyntheticKeyboard._testChunkSizes, [1, 1, 0, 1, 1])   // 0 = Shift+Return
    }

    func testTapNeedsAnchoredRun() {
        // Tap không đọc được màn hình (terminal / AX tắt): cụm chưa neo và KHÔNG sau một
        // lần dời con trỏ (vd. vừa ⌫ qua khoảng trắng) không nở; màn hình không bao giờ
        // được hỏi khi cụm đã neo.
        var t = ShortcutTail()
        t.append("->")
        XCTAssertFalse(t.afterJump)
        XCTAssertNil(ShortcutMatch.findForTap(in: table, composed: "", raw: "", tail: t,
                                              allowWord: true, allowToken: true,
                                              screen: { _ in .unreadable }))
        t.reset(); t.append("\n->")
        XCTAssertEqual(ShortcutMatch.findForTap(in: table, composed: "", raw: "", tail: t,
                                                allowWord: true, allowToken: true,
                                                screen: { _ in XCTFail("anchored: no AX read"); return .unreadable }),
                       .token(token: "->", expansion: "→"))
    }

    /// Issue #99: Chrome/Lark (tap) — click vào ô trống rồi gõ "-> " lần ĐẦU không nở
    /// (tap chưa thấy khoảng trắng nào ⇒ cụm chưa neo), lần hai mới nở. Cụm chưa neo
    /// giờ nở khi AX xác nhận cụm đứng riêng trước con trỏ; AX chỉ được hỏi khi cụm
    /// ĐÃ khớp một khoá.
    func testTapUnanchoredRunExpandsWhenScreenConfirms() {
        var t = ShortcutTail()
        t.caretMoved()               // click / đổi ô
        t.append("-"); t.append(">")
        var asked: [String] = []
        let m = ShortcutMatch.findForTap(in: table, composed: "", raw: "", tail: t,
                                         allowWord: true, allowToken: true,
                                         screen: { asked.append($0); return .standsAlone })
        XCTAssertEqual(m, .token(token: "->", expansion: "→"))
        XCTAssertEqual(asked, ["->"])
        // Cụm không khớp khoá nào ⇒ không đọc màn hình.
        var u = ShortcutTail(); u.append("=>")
        XCTAssertNil(ShortcutMatch.findForTap(in: table, composed: "", raw: "", tail: u,
                                              allowWord: true, allowToken: true,
                                              screen: { _ in XCTFail("no key matched: no AX read"); return .standsAlone }))
        // Khoá CHỮ không phụ thuộc neo / màn hình.
        XCTAssertEqual(ShortcutMatch.findForTap(in: table, composed: "ko", raw: "ko", tail: ShortcutTail(),
                                                allowWord: true, allowToken: true,
                                                screen: { _ in XCTFail("word key: no AX read"); return .glued }),
                       .word(expansion: "không"))
        // Tap cho phép token nhưng ranh giới không (dấu câu) ⇒ không hỏi.
        XCTAssertNil(ShortcutMatch.findForTap(in: table, composed: "", raw: "", tail: t,
                                              allowWord: true, allowToken: false,
                                              screen: { _ in XCTFail(); return .standsAlone }))
    }

    /// #99 follow-up (Lark, Photoshop — AX không đọc được): click/đổi ô là NEO, cụm gõ
    /// ngay sau đó nở. AX đọc được mà cụm dính chữ ⇒ không nở dù vừa click. Gõ liền
    /// "a->" (không dời con trỏ) ⇒ không nở.
    func testTapAfterJumpAnchorsWhenScreenUnreadable() {
        func find(_ t: ShortcutTail, _ v: ShortcutScreen.TokenVerdict) -> ShortcutMatch? {
            ShortcutMatch.findForTap(in: table, composed: "", raw: "", tail: t,
                                     allowWord: true, allowToken: true, screen: { _ in v })
        }
        var t = ShortcutTail()
        t.caretMoved(); t.append("-"); t.append(">")
        XCTAssertTrue(t.afterJump)
        XCTAssertFalse(t.anchored)
        XCTAssertEqual(find(t, .unreadable), .token(token: "->", expansion: "→"))
        XCTAssertNil(find(t, .glued))                        // AX đọc được: giữ kiểm tra chính xác
        XCTAssertEqual(find(t, .standsAlone), .token(token: "->", expansion: "→"))
        // Gõ liền sau chữ: cụm là "a->" ⇒ không khoá nào khớp, dù vừa click.
        var a = ShortcutTail()
        a.caretMoved(); a.append("a"); a.append("-"); a.append(">")
        XCTAssertNil(find(a, .unreadable))
        // ⌫ quá chỗ click (xoá chữ trước điểm neo) ⇒ mất neo.
        var b = ShortcutTail()
        b.caretMoved(); b.backspace(); b.append("->")
        XCTAssertFalse(b.afterJump)
        XCTAssertNil(find(b, .unreadable))
        // ⌫ trong cụm sau click vẫn giữ neo; khoảng trắng chuyển sang neo thường.
        var c = ShortcutTail()
        c.caretMoved(); c.append("-x"); c.backspace(); c.append(">")
        XCTAssertEqual(find(c, .unreadable), .token(token: "->", expansion: "→"))
        c.append(" ")
        XCTAssertTrue(c.anchored); XCTAssertFalse(c.afterJump)
        // Cụm quá dài ⇒ reset ⇒ không còn biết đầu cụm.
        var d = ShortcutTail()
        d.caretMoved(); d.append(String(repeating: "x", count: ShortcutTail.maxRun + 1))
        XCTAssertFalse(d.afterJump)
    }

    /// Đọc màn hình (thuần, reader giả lập AX kAXStringForRange): đầu ô, sau khoảng
    /// trắng, sau xuống dòng ⇒ đứng riêng; chữ dính trước ("a->") ⇒ dính; con trỏ
    /// không đọc được, AX trả nil, AX stale (chưa thấy ">"), caret giả ⇒ không đọc được.
    func testConfirmsTokenAgainstScreen() {
        func verdict(_ text: String, caret: Int? = nil, readable: Bool = true) -> ShortcutScreen.TokenVerdict {
            let ns = text as NSString
            return ShortcutScreen.tokenVerdict("->", caret: caret ?? ns.length) { r in
                guard readable, r.location >= 0, NSMaxRange(r) <= ns.length else { return nil }
                return ns.substring(with: r)
            }
        }
        XCTAssertEqual(verdict("->"), .standsAlone)          // đầu ô trống (video #99)
        XCTAssertEqual(verdict("abc ->"), .standsAlone)
        XCTAssertEqual(verdict("dòng 1\n->"), .standsAlone)
        XCTAssertEqual(verdict("a->"), .glued)
        XCTAssertEqual(verdict("-"), .unreadable)            // AX stale: '>' chưa tới cây AX
        XCTAssertEqual(verdict("->", readable: false), .unreadable)
        XCTAssertEqual(ShortcutScreen.tokenVerdict("->", caret: nil) { _ in "->" }, .unreadable)
        XCTAssertEqual(verdict("-> x", caret: 4), .unreadable) // con trỏ không đứng ngay sau cụm
        XCTAssertEqual(verdict("a->", caret: 1), .unreadable)  // Lark: caret hằng số 1
        XCTAssertTrue(ShortcutScreen.confirmsToken("->", caret: 2) { _ in "->" })
        XCTAssertFalse(ShortcutScreen.confirmsToken("->", caret: 3) { _ in "a->" })
    }

    /// Mô hình luồng TAP (#99): màn hình = ô web, tap thấy phím. AX đọc được ⇒ "->␣"
    /// lần đầu sau click nở, click ngay sau chữ thì không; ô không có AX (Lark,
    /// Photoshop) ⇒ click là neo: nở lần đầu, kể cả "a|->" (đánh đổi đã duyệt).
    func testTapFlowFirstArrowAfterClick() {
        struct TapField {
            var text = ""
            var tail = ShortcutTail()
            let table: ShortcutTable
            let axReadable: Bool
            mutating func click() { tail.caretMoved() }
            mutating func type(_ keys: String) {
                for ch in keys {
                    if ch == " " {
                        let m = ShortcutMatch.findForTap(
                            in: table, composed: "", raw: "", tail: tail,
                            allowWord: true, allowToken: true) { token in
                                let ns = text as NSString
                                return ShortcutScreen.tokenVerdict(token, caret: axReadable ? ns.length : nil) {
                                    ns.substring(with: $0)
                                }
                            }
                        if case let .token(token, e)? = m {
                            text.removeLast(token.count); text += e     // ⌫ theo ký tự + gõ lại
                            tail.replaceRun(with: e)
                        }
                    }
                    text.append(ch); tail.append(String(ch))
                }
            }
        }
        var f = TapField(table: table, axReadable: true)
        f.click(); f.type("-> -> ")
        XCTAssertEqual(f.text, "→ → ")
        var g = TapField(table: table, axReadable: false)
        g.click(); g.type("-> -> ")
        XCTAssertEqual(g.text, "→ → ")             // không AX: click là neo (#99 follow-up)
        var h = TapField(table: table, axReadable: true)
        h.text = "a"; h.click(); h.type("-> ")    // click ngay sau chữ "a", AX thấy dính
        XCTAssertEqual(h.text, "a-> ")
        var k = TapField(table: table, axReadable: false)
        k.text = "a"; k.click(); k.type("-> ")    // không AX: đánh đổi đã duyệt
        XCTAssertEqual(k.text, "a→ ")
        var s = TapField(table: table, axReadable: false)
        s.click(); s.type("a-> ")                 // gõ liền sau chữ: không nở
        XCTAssertEqual(s.text, "a-> ")
    }

    // MARK: - File (khứ hồi với iOS/Android)

    private func repoFile(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSampleRoundTripByteForByte() throws {
        let text = try repoFile("sample-shortcuts.yml")
        let parsed = try XCTUnwrap(ShortcutImporter.parse(Data(text.utf8)))
        XCTAssertEqual(parsed["ko"], "không")
        XCTAssertEqual(parsed["đc"], "được")
        XCTAssertEqual(parsed.count, 9)
        XCTAssertEqual(ShortcutImporter.exportYAML(parsed), text)   // y hệt iOS/Android
    }

    func testExtensionsRoundTrip() {
        let t: [String: String] = [
            "sig": "Thân mến,\nPhil", ":)": "🙂", "->": "→", "sp": " có space ", "q": "\"trích\"",
            "bs": "C:\\temp", "k2": "không hai", "a:b": "x", "#tag": "y", " lead": "z",
        ].filter { ShortcutTable.isValidKey($0.key) }
        let yaml = ShortcutImporter.exportYAML(t)
        XCTAssertTrue(yaml.contains("sig: \"Thân mến,\\nPhil\"\n"))   // định dạng iOS/Android
        XCTAssertTrue(yaml.contains("\":)\": 🙂\n"))
        XCTAssertTrue(yaml.contains("\"a:b\": x\n"))
        XCTAssertEqual(ShortcutImporter.parse(Data(yaml.utf8)), t)
    }

    func testParsesFilesWrittenByIOSAndAndroid() {
        // Chuỗi đúng như iOS ShortcutFile.exportYAML / Android Shortcuts.kt xuất.
        let fromPhone = """
        # VietTelex — bảng gõ tắt
        "->": →
        ":)": 🙂
        k2: không hai
        q: ""trích""
        sig: "Thân mến,\\nPhil"
        sp: " có space "

        """
        XCTAssertEqual(ShortcutImporter.parse(Data(fromPhone.utf8)), [
            "->": "→", ":)": "🙂", "k2": "không hai", "q": "\"trích\"",
            "sig": "Thân mến,\nPhil", "sp": " có space ",
        ])
        XCTAssertEqual(ShortcutImporter.parse(Data("\u{FEFF}ko: không\r\ndc: được\r\n".utf8)),
                       ["ko": "không", "dc": "được"])
    }

    // MARK: - AppState + UI

    func testAppStateTableTracksEdits() {
        let saved = AppState.shared.shortcuts
        defer { AppState.shared.setShortcuts(saved) }
        AppState.shared.setShortcuts(["ko": "không"])
        XCTAssertFalse(AppState.shared.shortcutTable.hasTokenKeys)
        AppState.shared.upsertShortcut(key: "->", value: "→")
        XCTAssertTrue(AppState.shared.shortcutTable.hasTokenKeys)
        XCTAssertEqual(AppState.shared.shortcutTable.expansion(for: "Ko"), "Không")
        AppState.shared.removeShortcut(key: "->")
        XCTAssertFalse(AppState.shared.shortcutTable.hasTokenKeys)
    }

    func testRowShowsMultilineOnOneLine() {
        XCTAssertEqual(ShortcutRow.oneLine("Thân mến,\nPhil"), "Thân mến, ⏎ Phil")
        XCTAssertEqual(ShortcutRow(key: "a", value: "x\r\ny").displayValue, "x ⏎ y")
    }
}
