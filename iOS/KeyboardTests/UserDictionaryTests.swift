import XCTest

/// Từ điển cá nhân: xoá từ kéo theo n-gram, thêm từ thủ công được gợi ý, app sửa file →
/// bàn phím nạp lại.
final class UserDictionaryTests: XCTestCase {

    private func sentence(_ m: UserLangModel, _ words: [String], times: Int = 3) {
        for _ in 0..<times {
            var p1: String?, p2: String?
            for w in words { m.record(word: w, after: p1, prev2: p2); p2 = p1; p1 = w }
        }
    }

    func testRemoveWordDropsBigramsAndTrigrams() {
        let m = UserLangModel(appGroup: nil)
        m.isKnownWord = { _ in true }
        sentence(m, ["sếp", "duyệt", "gấp"])
        sentence(m, ["báo", "sếp", "duyệt"])
        XCTAssertTrue(m.nextWords(after: "sếp", limit: 5).contains("duyệt"))
        XCTAssertTrue(m.nextWords(after: "duyệt", prev2: "sếp", limit: 5).contains("gấp"))

        XCTAssertTrue(m.removeWord("Duyệt"))
        XCTAssertEqual(m.count(of: "duyệt"), 0)
        XCTAssertFalse(m.nextWords(after: "sếp", limit: 5).contains("duyệt"))      // bigram sếp→duyệt
        XCTAssertTrue(m.nextWords(after: "duyệt", limit: 5).isEmpty)               // bigram duyệt→*
        XCTAssertFalse(m.nextWords(after: "duyệt", prev2: "sếp", limit: 5).contains("gấp")) // trigram
        XCTAssertFalse(m.tri.keys.contains { $0.contains("duyệt") })
        XCTAssertFalse(m.entries().contains { $0.word == "duyệt" })
        XCTAssertEqual(m.count(of: "sếp"), 6)                                      // từ khác nguyên
        XCTAssertTrue(m.nextWords(after: "báo", limit: 5).contains("sếp"))
        XCTAssertFalse(m.removeWord("duyệt"))
    }

    func testManualWordSuggestedImmediately() {
        let m = UserLangModel(appGroup: nil)          // isKnownWord = false: từ lạ
        m.record(word: "kubernetes", after: nil)
        XCTAssertFalse(m.topWords(limit: 10).contains("kubernetes"))   // 1 lần: chưa gợi ý
        XCTAssertTrue(m.addWord("  VietTelex "))
        XCTAssertTrue(m.topWords(limit: 10).contains("VietTelex"))     // giữ dạng hoa
        XCTAssertEqual(m.manualCompletions("viet"), ["VietTelex"])
        XCTAssertEqual(m.manualCompletions("Viết"), ["VietTelex"])     // bỏ dấu
        XCTAssertTrue(m.manualCompletions("telex").isEmpty)            // chỉ tiền tố
        XCTAssertEqual(m.entries(query: "TELEX").map(\.word), ["VietTelex"])
        XCTAssertEqual(m.entries().first, .init(word: "VietTelex", count: 5, manual: true))
        XCTAssertFalse(m.addWord("hai từ"))
        XCTAssertFalse(m.addWord("abc123"))
        XCTAssertFalse(m.addWord(""))
    }

    func testAppEditReloadsKeyboardModel() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("userdict-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        // "App" ghi file có dữ liệu học + từ thêm tay, xoá một từ.
        let app = UserLangModel(fileURL: url, synchronous: true)
        app.isKnownWord = { _ in true }
        sentence(app, ["sếp", "duyệt", "gấp"])
        app.addWord("Phúc")
        app.removeWord("gấp")
        app.saveSync()

        // "Bàn phím" nạp lại (như khi thấy mốc userlmResetAt đổi).
        let kbFile = UserLangModel(fileURL: url)
        let ready = expectation(description: "reload")
        kbFile.onReady = { ready.fulfill() }
        wait(for: [ready], timeout: 5)
        kbFile.onReady = nil
        XCTAssertEqual(kbFile.count(of: "gấp"), 0)
        XCTAssertEqual(kbFile.count(of: "duyệt"), 3)
        XCTAssertEqual(kbFile.manualCompletions("phu"), ["Phúc"])

        // App xoá từ lần nữa; bàn phím đang có thay đổi chờ ghi — reload bỏ bảng RAM, đọc bản app.
        kbFile.record(word: "duyệt", after: nil)
        app.removeWord("Phúc"); app.saveSync()
        let again = expectation(description: "reload2")
        kbFile.onReady = { again.fulfill() }
        kbFile.reloadAfterExternalEdit()
        wait(for: [again], timeout: 5)
        XCTAssertTrue(kbFile.manual.isEmpty)
        XCTAssertEqual(kbFile.count(of: "duyệt"), 3)
    }

    func testManualWordSurvivesDecayAndPersistsInPlist() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("userdict-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = UserLangModel(fileURL: url, synchronous: true)
        a.addWord("Kubernetes")
        a.saveSync()
        // lastDecay = 20 tuần trước → mở lại: decay count về 0 nhưng từ thêm tay còn.
        var plist = try! PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), options: [], format: nil) as! [String: Any]
        XCTAssertEqual(plist["manual"] as? [String], ["Kubernetes"])
        plist["lastDecay"] = Date().addingTimeInterval(-20 * 7 * 86400)
        try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: url)
        let b = UserLangModel(fileURL: url, synchronous: true)
        XCTAssertGreaterThanOrEqual(b.count(of: "kubernetes"), 1)
        XCTAssertTrue(b.topWords(limit: 5).contains("Kubernetes"))
    }
}
