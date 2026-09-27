// TextActionsTests — công cụ văn bản + Thêm dấu trên macOS: cùng fixture với iOS/Android
// (iOS/KeyboardTests/Fixtures) để bản biên dịch chung trong app Mac cho đúng kết quả;
// process con --add-tones; clipboard trả lại nguyên vẹn; hotkey.
import AppKit
import XCTest
@testable import VietTelex

final class TextActionsTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("iOS/KeyboardTests/Fixtures")

    private func fixtureLines(_ name: String) throws -> [String] {
        let s = try String(contentsOf: Self.fixtures.appendingPathComponent(name), encoding: .utf8)
        return s.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func testTextToolsSharedFixture() throws {
        let lines = try fixtureLines("text-tools.txt")
        XCTAssertGreaterThan(lines.count, 10)
        func unesc(_ s: String) -> String {
            s.replacingOccurrences(of: "␣", with: " ").replacingOccurrences(of: "⏎", with: "\n")
        }
        for line in lines {
            let c = line.components(separatedBy: "|")
            XCTAssertEqual(c.count, 3, line)
            let nfd = c[0].hasSuffix("@nfd")
            guard let tool = TextTool(rawValue: nfd ? String(c[0].dropLast(4)) : c[0]) else {
                XCTFail("op lạ: \(line)"); continue
            }
            var input = unesc(c[1])
            if nfd { input = input.decomposedStringWithCanonicalMapping }
            XCTAssertTrue(TextTools.apply(tool, input).unicodeScalars.elementsEqual(unesc(c[2]).unicodeScalars), line)
        }
    }

    func testAddTonesSharedFixture() throws {
        for line in try fixtureLines("add-tones.txt") {
            let c = line.components(separatedBy: "\t")
            guard c.count == 2 else { continue }
            XCTAssertEqual(TextActionTransform.addTonesInProcess(c[0]), c[1], line)
        }
    }

    func testApplyMapsActionsAndRejectsNoOps() {
        let noHelper: (String) -> String? = { _ in XCTFail("không được gọi Thêm dấu"); return nil }
        XCTAssertEqual(TextActionTransform.apply(.upper, "tiếng việt", addTones: noHelper), "TIẾNG VIỆT")
        XCTAssertEqual(TextActionTransform.apply(.lower, "TIẾNG Việt", addTones: noHelper), "tiếng việt")
        XCTAssertEqual(TextActionTransform.apply(.title, "tiếng việt", addTones: noHelper), "Tiếng Việt")
        XCTAssertEqual(TextActionTransform.apply(.sentence, "xin chào. tạm biệt", addTones: noHelper),
                       "Xin chào. Tạm biệt")
        XCTAssertEqual(TextActionTransform.apply(.stripDiacritics, "Đường phố", addTones: noHelper), "Duong pho")
        // Không đổi gì ⇒ nil (không đụng vào ô, không đụng clipboard).
        XCTAssertNil(TextActionTransform.apply(.upper, "ABC", addTones: noHelper))
        XCTAssertNil(TextActionTransform.apply(.upper, "", addTones: noHelper))
        XCTAssertNil(TextActionTransform.apply(.lower, String(repeating: "A", count: TextActionTransform.maxLength + 1),
                                               addTones: noHelper))
        XCTAssertEqual(TextActionTransform.apply(.addTones, "toi di", addTones: { _ in "tôi đi" }), "tôi đi")
        XCTAssertNil(TextActionTransform.apply(.addTones, "hello", addTones: { $0 }))
        XCTAssertNil(TextActionTransform.apply(.addTones, "toi", addTones: { _ in nil }))
    }

    /// Process con thật (chính binary app, cờ --add-tones): cùng kết quả với bản trong process.
    func testAddTonesHelperProcess() {
        let input = "Toi di hoc, hom nay troi dep!\nkhong co gi"
        XCTAssertEqual(TextActionTransform.addTonesViaHelper(input),
                       "Tôi đi học, hôm nay trời đẹp!\nkhông có gì")
        XCTAssertEqual(TextActionTransform.addTonesViaHelper(""), "")
    }

    func testPasteboardSnapshotRestoresAllTypes() {
        let pb = NSPasteboard(name: NSPasteboard.Name("vt.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("com.viettelex.test")
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("gốc", forType: .string)
        item.setData(Data([1, 2, 3]), forType: custom)
        pb.writeObjects([item])
        let snap = PasteboardBridge.Snapshot(pb)
        pb.clearContents()
        pb.setString("tạm", forType: .string)
        snap.restore(pb)
        XCTAssertEqual(pb.string(forType: .string), "gốc")
        XCTAssertEqual(pb.data(forType: custom), Data([1, 2, 3]))
        // Clipboard rỗng lúc chụp ⇒ trả lại rỗng.
        pb.clearContents()
        let empty = PasteboardBridge.Snapshot(pb)
        pb.setString("x", forType: .string)
        empty.restore(pb)
        XCTAssertNil(pb.string(forType: .string))
    }

    func testHotkeyChoices() {
        XCTAssertNil(TextActionHotkey.carbonModifiers(for: "off"))
        XCTAssertNil(TextActionHotkey.carbonModifiers(for: "rác"))
        for c in TextActionHotkey.choices where c.id != "off" {
            XCTAssertNotNil(TextActionHotkey.carbonModifiers(for: c.id), c.id)
            XCTAssertFalse(c.label.isEmpty)
        }
    }

    /// Mọi nhãn menu có bản tiếng Việt (thiếu thì menu hiện tiếng Anh giữa UI Việt).
    func testMenuTitlesHaveVietnamese() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let vi = try XCTUnwrap(Bundle(path: path))
        for a in TextAction.allCases {
            XCTAssertNotEqual(vi.localizedString(forKey: a.titleKey, value: "∅", table: nil), "∅", a.titleKey)
        }
        XCTAssertEqual(vi.localizedString(forKey: "Add tones to selection", value: nil, table: nil),
                       "Thêm dấu cho vùng chọn")
        XCTAssertEqual(TextAction.allCases.compactMap(\.textTool).count, TextTool.allCases.count)
    }
}
