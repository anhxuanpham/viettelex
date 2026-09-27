// Ngôn ngữ giao diện (Shared/L10n.swift): bảng dịch đủ cho MỌI chuỗi `L("…")`/`LK("…")`
// trong mã nguồn app + bàn phím, mặc định "vi" bất kể ngôn ngữ máy, đổi thì lưu lại.
import XCTest

final class L10nTests: XCTestCase {

    override func tearDown() {
        L10n.apply("vi")   // các test khác so chuỗi tiếng Việt
        super.tearDown()
    }

    private static var iosRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Giải escape literal Swift một dòng (\" \\ \n \t \u{…}) — khớp khoá lúc chạy.
    private static func unescape(_ s: String) -> String {
        var out = ""; let it = Array(s); var i = 0
        while i < it.count {
            let c = it[i]
            guard c == "\\", i + 1 < it.count else { out.append(c); i += 1; continue }
            let n = it[i + 1]
            switch n {
            case "n": out.append("\n"); i += 2
            case "t": out.append("\t"); i += 2
            case "\"", "\\", "'": out.append(n); i += 2
            case "u":
                if let close = it[(i + 2)...].firstIndex(of: "}") {
                    let hex = String(it[(i + 3)..<close])
                    if let v = UInt32(hex, radix: 16), let sc = Unicode.Scalar(v) { out.unicodeScalars.append(sc) }
                    i = close + 1
                } else { out.append(c); i += 1 }
            default: out.append(c); i += 1
            }
        }
        return out
    }

    /// Mọi khoá `L("…")` / `LK("…")` trong App/, Keyboard/, Shared/.
    private static func sourceKeys() throws -> [(key: String, file: String)] {
        let re = try NSRegularExpression(pattern: #"\bLK?\("((?:[^"\\\n]|\\.)*)""#)
        var out: [(String, String)] = []
        for dir in ["App", "Keyboard", "Shared"] {
            let base = iosRoot.appendingPathComponent(dir)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            for f in files where f.lastPathComponent != "L10n.swift" {
                let src = try String(contentsOf: f, encoding: .utf8)
                let ns = src as NSString
                for m in re.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
                    out.append((unescape(ns.substring(with: m.range(at: 1))), f.lastPathComponent))
                }
            }
        }
        return out
    }

    private static func placeholders(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(\d\$)?[+]?(@|d|ld|lld)"#)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).replacingOccurrences(of: #"\d\$"#, with: "", options: .regularExpression)
        }.sorted()
    }

    func testEverySourceStringHasEnglish() throws {
        let keys = try Self.sourceKeys()
        XCTAssertGreaterThan(keys.count, 300, "quét mã nguồn không ra khoá — sai đường dẫn?")
        var missing: [String] = []
        for (k, f) in keys where (L10n.en[k] ?? "").isEmpty {
            missing.append("\(f): \(k)")
        }
        XCTAssertEqual(missing, [], "thiếu bản dịch tiếng Anh")
        for (k, _) in keys { XCTAssertFalse(k.contains("\\("), "không nội suy trong khoá L(): \(k)") }
    }

    func testTableEntriesValid() throws {
        let used = Set(try Self.sourceKeys().map(\.key))
        for (vi, en) in L10n.en {
            XCTAssertFalse(vi.isEmpty)
            XCTAssertFalse(en.trimmingCharacters(in: .whitespaces).isEmpty, "rỗng: \(vi)")
            XCTAssertEqual(Self.placeholders(vi), Self.placeholders(en), "tham số lệch: \(vi)")
            XCTAssertTrue(used.contains(vi), "bản dịch thừa (không còn dùng): \(vi)")
        }
    }

    /// Mặc định LUÔN tiếng Việt — kể cả khi máy/tiến trình ưu tiên tiếng Anh.
    func testDefaultIsVietnameseRegardlessOfDeviceLanguage() {
        let d = UserDefaults(suiteName: "vt.l10n.test.\(UUID().uuidString)")!
        d.set(["en-US", "en"], forKey: "AppleLanguages")
        d.set("en_US", forKey: "AppleLocale")
        XCTAssertEqual(L10n.stored(d), "vi")
        XCTAssertEqual(L10n.stored(nil), "vi")
        d.set("fr", forKey: L10n.defaultsKey)
        XCTAssertEqual(L10n.stored(d), "vi", "giá trị lạ ⇒ vi")
        L10n.reload(d)
        XCTAssertEqual(L("Gõ tắt"), "Gõ tắt")
    }

    func testSwitchingPersistsAndTranslates() {
        let d = UserDefaults(suiteName: "vt.l10n.test.\(UUID().uuidString)")!
        L10n.set("en", d)
        XCTAssertEqual(d.string(forKey: "uiLanguage"), "en")
        L10n.apply("vi")
        L10n.reload(d)   // như bàn phím đọc lại khi hiện
        XCTAssertTrue(L10n.isEnglish)
        XCTAssertEqual(L("Gõ tắt"), "Shortcuts")
        XCTAssertEqual(L("Đã nhập %@ mục: %@ mới, %@ ghi đè.", 5, 3, 2), "Imported 5 items: 3 new, 2 replaced.")
        XCTAssertEqual(L("Chuỗi chưa dịch"), "Chuỗi chưa dịch", "thiếu bản dịch ⇒ giữ tiếng Việt")
        L10n.set("vi", d)
        XCTAssertEqual(d.string(forKey: "uiLanguage"), "vi")
        XCTAssertEqual(L("Gõ tắt"), "Gõ tắt")
        XCTAssertEqual(L("Đã nhập %@ mục: %@ mới, %@ ghi đè.", 5, 3, 2), "Đã nhập 5 mục: 3 mới, 2 ghi đè.")
    }

    func testFormatPositional() {
        XCTAssertEqual(L10n.format("%2$@ / %1$@", ["a", "b"]), "b / a")
        XCTAssertEqual(L10n.format("%@%", [40]), "40%")
        XCTAssertEqual(L10n.format("không tham số %@", []), "không tham số %@")
    }

    func testGuideURLFollowsLanguage() {
        L10n.apply("vi")
        XCTAssertEqual(L10n.guideURL(os: "ios").absoluteString, "https://viettelex.com/hdsd/?os=ios")
        XCTAssertEqual(L10n.guideURL(os: "ios", anchor: "go-vuot").absoluteString, "https://viettelex.com/hdsd/?os=ios#go-vuot")
        L10n.apply("en")
        XCTAssertEqual(L10n.guideURL(os: "ios").absoluteString, "https://viettelex.com/en/guide/?os=ios")
        XCTAssertEqual(L10n.guideURL(os: "ios", anchor: "go-vuot").absoluteString, "https://viettelex.com/en/guide/?os=ios#swipe")
    }

    /// Mọi anchor tiếng Anh tồn tại trong docs/en/guide (và anchor Việt trong docs/hdsd).
    func testGuideAnchorsExist() throws {
        let docs = Self.iosRoot.deletingLastPathComponent().appendingPathComponent("docs")
        let vi = try String(contentsOf: docs.appendingPathComponent("hdsd/index.html"), encoding: .utf8)
        let en = try String(contentsOf: docs.appendingPathComponent("en/guide/index.html"), encoding: .utf8)
        for (v, e) in L10n.enAnchors {
            XCTAssertTrue(vi.contains("id=\"\(v)\""), v)
            XCTAssertTrue(en.contains("id=\"\(e)\""), e)
        }
    }
}
