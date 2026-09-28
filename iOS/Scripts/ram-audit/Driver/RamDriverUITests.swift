import XCTest

/// Driver đo RAM process VietTelexKeyboard THẬT (iOS/docs/RAM-AUDIT.md).
/// Đi qua các trạng thái, mỗi mốc ghi `<nn>-<tên>.mark` vào RAM_SYNC rồi chờ `<nn>-<tên>.ack`
/// — ram-audit.sh (chạy trên máy host) lấy footprint / vmmap / heap của process extension
/// giữa hai file đó. Env (qua TEST_RUNNER_…): RAM_SYNC (bắt buộc), RAM_CYCLES (mặc định 30).
final class RamDriverUITests: XCTestCase {
    var sync: String { ProcessInfo.processInfo.environment["RAM_SYNC"] ?? "/tmp/ramdrv" }
    var cycles: Int { Int(ProcessInfo.processInfo.environment["RAM_CYCLES"] ?? "") ?? 30 }
    var seq = 0

    func mark(_ name: String, timeout: TimeInterval = 300) {
        seq += 1
        let base = sync + "/" + String(format: "%02d-", seq) + name
        try? "x".write(toFile: base + ".mark", atomically: true, encoding: .utf8)
        let end = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: base + ".ack"), Date() < end { usleep(200_000) }
    }

    func tap(_ app: XCUIApplication, _ p: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)).tap()
    }
    func coord(_ app: XCUIApplication, _ p: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
    }

    func isVT(_ app: XCUIApplication) -> Bool { app.buttons["Số"].exists || app.buttons["Chữ"].exists }

    /// Chuyển sang bàn phím VietTelex (giữ 🌐 → chọn trong danh sách).
    func switchToVT(_ app: XCUIApplication) {
        for _ in 0..<8 {
            if isVT(app) { return }
            let nk = app.buttons["Next keyboard"]
            if nk.exists {
                nk.press(forDuration: 1.2)
                sleep(1)
                let item = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS[c] 'VietTelex'")).firstMatch
                if item.exists { item.tap() }
            } else {
                tap(app, CGPoint(x: 42, y: app.frame.height - 41))
            }
            sleep(3)
        }
    }

    func letterFrames(_ app: XCUIApplication) -> [Character: CGPoint] {
        var frames: [Character: CGPoint] = [:]
        for ch in "abcdefghijklmnopqrstuvwxyz" {
            for lab in [String(ch), String(ch).uppercased()] {
                let b = app.buttons[lab]
                if b.exists { frames[ch] = CGPoint(x: b.frame.midX, y: b.frame.midY); break }
            }
        }
        return frames
    }

    static let corpus = "xin chaof moij nguowif hoom nay tooi ddi lamf vieecj owr coong ty mowis "
        + "vaf gawpj nhieeuf ddoongf nghieepj raats vui veer chungs tooi cungf nhau baanf veef "
        + "keees hoachj sanr phaamr cho nawm sau "

    func typeKeys(_ app: XCUIApplication, count: Int) {
        let frames = letterFrames(app)
        let spaceB = app.buttons["Dấu cách"]
        let space = spaceB.exists ? CGPoint(x: spaceB.frame.midX, y: spaceB.frame.midY) : .zero
        let del = app.buttons["Xoá"].exists ? app.buttons["Xoá"].frame : .zero
        var n = 0
        let keys = Array(Self.corpus)
        while n < count {
            let ch = keys[n % keys.count]
            if n > 0, n % 25 == 0, del != .zero { tap(app, CGPoint(x: del.midX, y: del.midY)) }
            else if ch == " " { tap(app, space) }
            else if let p = frames[ch] { tap(app, p) }
            n += 1
        }
    }

    static let swipeWords = ["chao", "moi", "nguoi", "hom", "nay", "toi", "di", "lam", "viec", "cong",
                             "ty", "moi", "va", "gap", "nhieu", "dong", "nghiep", "rat", "vui", "ve"]

    func swipeWords(_ app: XCUIApplication, count: Int) {
        let frames = letterFrames(app)
        let spaceB = app.buttons["Dấu cách"]
        let space = CGPoint(x: spaceB.frame.midX, y: spaceB.frame.midY)
        for i in 0..<count {
            let w = Array(Self.swipeWords[i % Self.swipeWords.count])
            guard let a = frames[w.first!], let b = frames[w.last!], a != b else { continue }
            // Đường vuốt thẳng chữ đầu → chữ cuối (XCUI chỉ kéo 2 điểm) — đủ để chạy decoder,
            // template, FUTO; không đo độ chính xác.
            coord(app, a).press(forDuration: 0.05, thenDragTo: coord(app, b),
                                withVelocity: 700, thenHoldForDuration: 0.05)
            usleep(300_000)
            tap(app, space)
        }
    }

    func testRamAudit() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        app.textViews["field"].tap()
        sleep(3)
        switchToVT(app)
        XCTAssertTrue(isVT(app), "không mở được bàn phím VietTelex")
        sleep(3)
        mark("shown")

        typeKeys(app, count: 200)
        sleep(3)
        mark("typed200")

        let emoji = app.buttons["Emoji"]
        if emoji.exists {
            emoji.tap()
            sleep(2)
            // lướt qua nhiều nhóm emoji (dựng glyph màu cho từng trang)
            let y = app.frame.height - 150
            for _ in 0..<6 {
                coord(app, CGPoint(x: app.frame.width - 30, y: y))
                    .press(forDuration: 0.05, thenDragTo: coord(app, CGPoint(x: 30, y: y)))
                usleep(600_000)
            }
            sleep(2)
            mark("emoji")
            if app.buttons["ABC"].exists { app.buttons["ABC"].tap() }
            sleep(2)
            mark("emoji-left")
        }

        let clip = app.buttons["Lịch sử clipboard"]
        if clip.exists {
            clip.tap()
            sleep(2)
            mark("clipboard")
            if app.buttons["Đóng clipboard"].exists { app.buttons["Đóng clipboard"].tap() }
            sleep(1)
        }

        swipeWords(app, count: 50)
        sleep(3)
        mark("swipe50")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(4)
        mark("landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(4)
        mark("portrait")

        // ram-audit.sh gửi cảnh báo bộ nhớ giữa mark và ack, rồi đo lại.
        mark("memwarn")
        sleep(2)
        mark("after-memwarn")

        // Rò rỉ: ẩn/hiện bàn phím nhiều vòng — footprint lúc HIỆN phải phẳng.
        let toggle = app.buttons["toggle"]
        for i in 1...cycles {
            toggle.tap(); usleep(1_500_000)          // ẩn
            toggle.tap(); usleep(1_500_000)          // hiện
            if i == 1 || i % 5 == 0 {
                typeKeys(app, count: 20)
                sleep(1)
                mark("cycle\(i)")
            }
        }
        mark("end")
    }
}
