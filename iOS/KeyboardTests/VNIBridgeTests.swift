// Kiểu gõ VNI trên iOS: phím số trong lúc soạn từ mang dấu (engine vniMode giống macOS),
// ngoài từ vẫn là số; sửa dấu từ đã gõ bằng 1–5/0/7/8; gõ vuốt + gợi ý dùng đúng kiểu gõ.
// Định tuyến phím số y như KeyboardViewController: vniDigit, không nhận ⇒ boundary.
import XCTest
import TelexCore

final class VNIBridgeTests: XCTestCase {

    private var vni: KeyboardSettings { var s = KeyboardSettings(); s.vniMode = true; return s }

    private func run(_ keys: String, on p: MockProxy, bridge b: EngineBridge) {
        for ch in keys {
            if ch == " " || ch == "." { b.boundary(String(ch), proxy: p) }
            else if ch == "⌫" { b.backspace(proxy: p) }
            else if ch.isNumber {
                if !b.vniDigit(ch, proxy: p) { b.boundary(String(ch), proxy: p) }
            } else { b.letter(ch, proxy: p) }
        }
    }

    private func type(_ keys: String, initial: String = "", settings: KeyboardSettings? = nil) -> String {
        let p = MockProxy(); p.text = initial
        run(keys, on: p, bridge: EngineBridge(settings: settings ?? vni))
        return p.text
    }

    func testDigitsCarryDiacriticsInsideWord() {
        XCTAssertEqual(type("tie6ng1 vie6t5 "), "tiếng việt ")
        XCTAssertEqual(type("d9u7o7ng2 "), "đường ")
        XCTAssertEqual(type("Vie6t5 Nam "), "Việt Nam ")
        XCTAssertEqual(type("hoa2 "), "hòa ")
        XCTAssertEqual(type("a1⌫"), "")
        XCTAssertEqual(type("vie6t5⌫"), "việ")
    }

    func testDigitsOutsideWordStayNumbers() {
        XCTAssertEqual(type("2026 "), "2026 ")
        XCTAssertEqual(type("nam 2026."), "nam 2026.")
        XCTAssertEqual(type("hoa 2"), "hoa 2")          // sau dấu cách của mình: số
        XCTAssertEqual(type("mp3 "), "mp3 ")            // không có nguyên âm: số literal trong từ
    }

    func testLettersAreLiteralInVNI() {
        XCTAssertEqual(type("vieetj "), "vieetj ")
        XCTAssertEqual(type("google "), "google ")
    }

    func testTelexUnchangedByDigitRouting() {
        var telex = KeyboardSettings(); telex.vniMode = false
        let b = EngineBridge(settings: telex)
        let p = MockProxy()
        XCTAssertFalse(b.vniDigit("1", proxy: p))
        XCTAssertEqual(type("vieetj1 ", settings: telex), "việt1 ")
        XCTAssertEqual(type("tieengs 2026 ", settings: telex), "tiếng 2026 ")
    }

    func testReEditWithDigits() {
        XCTAssertEqual(type("5", initial: "viêt"), "việt")        // đặt con trỏ sau từ + số dấu
        XCTAssertEqual(type("0", initial: "việt"), "viêt")        // 0 xoá dấu
        XCTAssertEqual(type("hoa ⌫2"), "hòa")                     // ⌫ mở lại từ rồi gõ số
        XCTAssertEqual(type("xin chao ⌫2 "), "xin chào ")
        XCTAssertEqual(type("tha1y ⌫6"), "thấy")                  // mở lại qua ⌫: 6 cũng được
        XCTAssertEqual(type("6", initial: "to"), "to6")           // 6/9 không nạp lại từ (≙ a e o d)
        XCTAssertEqual(type("3", initial: "mp"), "mp3")           // không biến đổi ⇒ số
        var off = vni; off.reEditWord = false
        XCTAssertEqual(type("5", initial: "viêt", settings: off), "viêt5")
    }

    func testReEditKeySetsPerMethod() {
        XCTAssertTrue(EngineBridge.isReEditKey("s"))
        XCTAssertFalse(EngineBridge.isReEditKey("1"))
        for d in "1234507" + "8" { XCTAssertTrue(EngineBridge.isReEditKey(d, vni: true)) }
        for c in "69sfw" { XCTAssertFalse(EngineBridge.isReEditKey(c, vni: true)) }
    }

    func testSuggestionHelpersUseVNI() {
        let b = EngineBridge(settings: vni)
        XCTAssertEqual(b.composeTrial("tie6ng1"), "tiếng")
        let p = MockProxy()
        run("vie6t5", on: p, bridge: b)
        XCTAssertEqual(b.rawWord, "vie6t5")
        XCTAssertEqual(b.composedWord, "việt")
        XCTAssertEqual(b.predictedCommit, "việt")
        // AdjacentKeyFixer nhận raw có số (VNI): chạm trượt h→b vẫn sửa được.
        let fix = AdjacentKeyFixer.correction(
            raw: "nbie6u2", compose: { b.composeTrial($0) },
            frequency: { $0 == "nhiều" ? 100 : nil },
            hasCompletion: { w in "nhiều".hasPrefix(w) || "nhiêu".hasPrefix(w) })
        XCTAssertEqual(fix, "nhiều")
    }

    func testSwipeWordEditableWithDigits() {
        let b = EngineBridge(settings: vni)
        let p = MockProxy()
        b.insertSwipeWord("tiêng", proxy: p)
        XCTAssertTrue(b.isSwipeWordOpen)
        XCTAssertTrue(b.vniDigit("1", proxy: p))
        XCTAssertEqual(p.text, "tiếng")
        b.boundary(" ", proxy: p)
        XCTAssertEqual(p.text, "tiếng ")
        // Số không sửa được từ vuốt ⇒ ranh giới (caller chèn số liền sau).
        let p2 = MockProxy()
        let b2 = EngineBridge(settings: vni)
        b2.insertSwipeWord("tiêng", proxy: p2)
        XCTAssertFalse(b2.vniDigit("9", proxy: p2))
        XCTAssertTrue(b2.isSwipeWordOpen)
        // Phím chữ sau từ vuốt ở VNI không bao giờ là phím dấu ⇒ dấu cách treo.
        let p3 = MockProxy()
        let b3 = EngineBridge(settings: vni)
        b3.insertSwipeWord("tiêng", proxy: p3)
        b3.letter("s", proxy: p3)
        XCTAssertEqual(p3.text, "tiêng s")
    }

    // MARK: gõ tắt + VNI — khớp dạng đã qua engine VNI; số là phím dấu TRONG từ, không phải
    // "chữ tắt dính sau số" (#82).
    private var vniShortcuts: KeyboardSettings {
        var s = vni
        s.shortcuts = ShortcutTable(["ko": "không", "đc": "được", "dc": "đi chơi"])
        return s
    }

    func testShortcutsExpandInVNI() {
        XCTAssertEqual(type("ko ", settings: vniShortcuts), "không ")
        XCTAssertEqual(type("d9c ", settings: vniShortcuts), "được ")         // khoá "đc"
        XCTAssertEqual(type("xin d9c.", settings: vniShortcuts), "xin được.")
        XCTAssertEqual(type("dc ", settings: vniShortcuts), "đi chơi ")       // raw "d9c" ≠ "dc"
        XCTAssertEqual(type("2 ko ", settings: vniShortcuts), "2 không ")
    }

    func testShortcutGluedAfterRealNumberStaysInVNI() {
        XCTAssertEqual(type("2ko ", settings: vniShortcuts), "2ko ")          // #82: số NGOÀI từ
    }
}
