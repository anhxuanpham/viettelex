// Regression (video người dùng Messenger, 27/09/2026 — bản 1.1.1/1.1.2): gõ "phai" rồi
// "r" ra "phair". Host gán lại text sau mỗi phím (textWillChange/DidChange đến muộn) làm
// bản phát hành reset mù giữa từ; rồi ⌫ lùi về "ph" gõ tiếp "air" thành từ riêng "ải"
// (raw "air") → chốt bị tự khôi phục tiếng Anh → "phair ". Mô phỏng host ở đây: sau MỖI
// phím, host có thể viết lại text (NFD, bỏ khoảng trắng cuối, cửa sổ context ngắn) rồi
// controller đối chiếu bằng CompositionSync.verdict như syncComposition.
import XCTest
import TelexCore

/// Proxy giả kiểu host: `rewrite` chạy sau mỗi lệnh sửa của bàn phím (host gán lại
/// text); `window` = số ký tự cuối host cho xem (nil = toàn bộ).
private final class HostProxy: TextProxyLike {
    var text = ""
    var textAfter = ""
    var rewrite: (String) -> String = { $0 }
    var window: Int?
    var isSecure: Bool { false }
    var hasSelection: Bool { false }
    var contextBeforeInput: String? { window.map { String(text.suffix($0)) } ?? text }
    var contextAfterInput: String? { textAfter }
    func insertText(_ t: String) { text += t }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func hostRewrites() { text = rewrite(text) }
}

final class HostRewriteCompositionTests: XCTestCase {

    /// Phím như KeyboardViewController.handle + textDidChange muộn của host sau mỗi phím.
    /// `lose`: tập chỉ số phím mà SAU đó composition bị mất (bản phát hành reset mù).
    private func type(_ keys: String, proxy p: HostProxy, bridge b: EngineBridge = EngineBridge(settings: KeyboardSettings()),
                      lose: Set<Int> = []) {
        for (i, ch) in keys.enumerated() {
            if ch == " " || ch == "," { b.boundary(String(ch), proxy: p) }
            else if ch == "⌫" { b.backspace(proxy: p) }
            else { b.letter(ch, proxy: p) }
            p.hostRewrites()
            if lose.contains(i) || CompositionSync.verdict(context: p.contextBeforeInput,
                                                           composed: b.composedWord) != .keep {
                b.reset()
            }
        }
    }

    func testLateHostCallbacksKeepComposition() {
        let p = HostProxy()
        type("chuyeenr ddc, phair vieetj ", proxy: p)
        XCTAssertEqual(p.text, "chuyển đc, phải việt ")
    }

    func testHostNormalizesToNFD() {
        let p = HostProxy()
        p.rewrite = { $0.decomposedStringWithCanonicalMapping }
        type("phair vieetj ", proxy: p)
        XCTAssertEqual(p.text, "phải việt ")          // == so tương đương chuẩn
    }

    func testHostTrimsTrailingSpaceDoesNotGlueNextWord() {
        let p = HostProxy()
        p.rewrite = { s in
            var s = s
            while s.last == " " { s.removeLast() }
            return s
        }
        type("ddc, phair", proxy: p)
        // Host nuốt dấu cách cuối (lỗi của host) nhưng từ sau vẫn soạn đúng.
        XCTAssertEqual(p.text, "đc,phải")
    }

    func testShortContextWindow() {
        let p = HostProxy()
        p.window = 8
        type("rooif chuyeenr laij thif toanf bij ko chuyeenr ddc, phair vieetj ", proxy: p)
        XCTAssertEqual(p.text, "rồi chuyển lại thì toàn bị ko chuyển đc, phải việt ")
    }

    /// Bản phát hành: composition mất ngay sau "phai" → "r" chèn literal. Main: phím dấu
    /// nạp lại từ trước con trỏ (seed).
    func testCompositionLostBeforeToneKey() {
        let p = HostProxy()
        type("phair ", proxy: p, lose: [3])          // mất sau phím thứ 4 ("i")
        XCTAssertEqual(p.text, "phải ")
        let q = HostProxy()
        type("vieetj ", proxy: q, lose: [3])         // mất sau "viee" → "viê" trên màn hình
        XCTAssertEqual(q.text, "việt ")
    }

    /// Đúng cảnh trong video: "phair" (literal) → ⌫⌫⌫ còn "ph" → gõ "air" + space.
    /// Trước: "ải" là từ riêng raw "air" → tự khôi phục tiếng Anh → "phair ".
    func testBackspaceIntoWordThenContinue() {
        let p = HostProxy(); p.text = "chuyển đc, phair"
        let b = EngineBridge(settings: KeyboardSettings())
        type("⌫⌫⌫air", proxy: p, bridge: b)
        XCTAssertEqual(p.text, "chuyển đc, phải")
        XCTAssertEqual(b.composedWord, "phải")
        type(" ", proxy: p, bridge: b)
        XCTAssertEqual(p.text, "chuyển đc, phải ")
    }

    func testContinueAfterLostCompositionMidWord() {
        let p = HostProxy()
        type("vieetj", proxy: p, lose: [1])          // mất sau "vi"
        XCTAssertEqual(p.text, "việt")
        let q = HostProxy()
        type("tieengs ", proxy: q, lose: [1])        // mất sau "ti"
        XCTAssertEqual(q.text, "tiếng ")
    }

    /// Không đổi quyết định 26/09/2026: phím thường không BIẾN ĐỔI chữ cũ ("to" + o = "too").
    func testContinueNeverTransformsExistingText() {
        let p = HostProxy(); p.text = "to"
        type("o", proxy: p)
        XCTAssertEqual(p.text, "too")
        let q = HostProxy(); q.text = "dd"
        type("a", proxy: q)
        XCTAssertEqual(q.text, "dda")
    }

    func testNoContinueInMiddleOfWordOrAfterOwnBoundary() {
        let p = HostProxy(); p.text = "ph"; p.textAfter = "ai"
        let b = EngineBridge(settings: KeyboardSettings())
        type("o", proxy: p, bridge: b)
        XCTAssertEqual(b.composedWord, "o")          // giữa từ: không nạp "ph"
        let q = HostProxy()
        type("ab cd", proxy: q)
        XCTAssertEqual(q.text, "ab cd")
    }
}
