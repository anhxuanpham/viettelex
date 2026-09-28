import XCTest
import UIKit

/// Chia RAM bàn phím theo thành phần (iOS/docs/RAM-AUDIT.md). Bộ CHẬM (VT_SLOW_TESTS=1).
/// Mỗi bước nạp MỘT thành phần rồi đo phần tăng: phys_footprint (thứ jetsam tính) và heap
/// đang dùng (malloc, chính xác tới byte). Thứ tự cố định vì singleton chỉ nạp một lần.
/// Số in ra dòng "RAMPART <tên> foot=+x.xMB heap=+x.xMB".
///
/// Giới hạn: chạy trong process test (không phải process extension) — số tuyệt đối khác,
/// phần TĂNG của từng thành phần thì như nhau. Process thật: iOS/Scripts/ram-audit.
final class RamBreakdownTests: XCTestCase {

    static func heapBytes() -> Int {
        var s = malloc_statistics_t()
        malloc_zone_statistics(nil, &s)
        return Int(s.size_in_use)
    }

    static func spin(_ sec: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(sec)) }

    struct Step { let name: String; let foot: Double; let heap: Double }
    var steps: [Step] = []
    var lastFoot = 0.0, lastHeap = 0

    func begin() {
        Self.spin(0.3)
        lastFoot = KeyboardBenchTests.footprintMB(); lastHeap = Self.heapBytes()
    }

    func step(_ name: String, settle: TimeInterval = 0.2, _ body: () -> Void) {
        body()
        Self.spin(settle)
        let f = KeyboardBenchTests.footprintMB(), h = Self.heapBytes()
        let s = Step(name: name, foot: f - lastFoot, heap: Double(h - lastHeap) / 1_048_576)
        steps.append(s)
        print(String(format: "RAMPART %@ foot=%+.2fMB heap=%+.2fMB total=%.1fMB", name, s.foot, s.heap, f))
        lastFoot = f; lastHeap = h
    }

    @MainActor func testComponentBreakdown() throws {
        try SlowTests.require()
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = KeyboardBenchTests.makeDefaults("D")
        defer { UserDefaultsProvider.shared = saved }
        begin()

        // --- dữ liệu (mmap: phải ~0 dirty; phần dựng ra heap mới tốn) ---
        step("vnlexicon.bin (VNLexicon2Data)") { _ = VNLexicon2Data.blob.count; _ = VNLexicon2Data.offsets.count }
        step("vnlm.bin (SyllableLM.shared)") { _ = SyllableLM.shared }
        step("SwipeLexicon.forms") { _ = SwipeLexicon.forms.count }
        var dec: SwipeDecoder? = SwipeDecoder()
        step("SwipeDecoder templates") {
            dec!.setLayout(.qwerty(keyWidth: 40, rowHeight: 54))
            dec!.prepare()
        }
        print("RAMPART   (templateBytes=\(dec!.templateBytes))")
        step("enlexicon.bin (SwipeEnglish.lexicon)") { _ = SwipeEnglish.lexicon }
        step("TelexKeyPrior (smartTouch trie)") { _ = TelexKeyPrior.warmUp() }
        step("emoji.bin + categories (≈ font Apple Color Emoji của CoreText khi kiểm glyph)") { _ = EmojiData.categories.count; _ = EmojiData.kaomoji.count }
        var futo: FutoSwipe? = FutoSwipe(source: FutoSwipe.bundledWeights)
        step("FUTO model load") { _ = futo!.load() }
        step("FUTO release") { futo!.release(); futo = nil }
        step("SwipeDecoder release") { dec = nil }

        // --- model cá nhân tại trần (3000 uni / 6000 bi / 3000 tri) ---
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ram-userlm-\(UUID()).plist")
        var lm: UserLangModel? = UserLangModel(fileURL: url, synchronous: true)
        step("UserLangModel full (caps)") {
            let syl = Array(SwipeLexicon.forms.folded.prefix(1600))
            var prev: String?, prev2: String?
            for i in 0..<24_000 {
                let w = syl[(i * 7919) % syl.count]
                _ = lm!.record(word: w, after: prev, prev2: prev2)
                prev2 = prev; prev = w
            }
        }
        print("RAMPART   (uni=\(lm!.uniCount) bi=\(lm!.biPairCount) tri=\(lm!.triPairCount))")
        step("UserLangModel release", settle: 2.0) { lm = nil }
        try? FileManager.default.removeItem(at: url)

        // --- âm thanh / rung ---
        step("KeySound prepare (AVAudioEngine)", settle: 1.0) {
            KeySound.shared.setStyle("mechanical")
            KeySound.shared.prepare()
            _ = KeySound.shared.startNow()
        }
        step("KeySound shutdown", settle: 0.5) { KeySound.shared.shutdown() }

        // --- ảnh nền cỡ màn iPhone 17 (402×290pt @3x) ---
        var img: CGImage?
        step("Wallpaper decode (@2x, cắt đúng view)") {
            let jpg = Self.makeJPEG(width: 1080, height: 1440)
            let scale = Wallpaper.decodeScale(screenScale: 3)
            let view = CGSize(width: 402, height: 290)
            let px = Wallpaper.displayMaxPixel(viewSize: view, scale: scale, imageAspect: 1080.0 / 1440)
            let full = Wallpaper.downsample(data: jpg, maxPixel: px)!
            img = Wallpaper.aspectFillCrop(full, to: CGSize(width: view.width * scale, height: view.height * scale)) ?? full
        }
        if let img { print("RAMPART   (wallpaper \(img.width)x\(img.height) = \(img.bytesPerRow * img.height / 1024) KB)") }
        step("Wallpaper release") { img = nil }

        // --- UI: controller thật (cấu hình D) ---
        var rig: KeyboardBenchTests.Rig? = KeyboardBenchTests.Rig()
        step("Keyboard view shown (letters)", settle: 1.0) {}
        step("200 keys", settle: 1.0) {
            let keys = Array(KeyboardBenchTests.corpus)
            for i in 0..<200 { _ = rig!.key(keys[i % keys.count], index: i, drain: 0.005) }
        }
        step("numbers + symbols planes (planeCache)") { rig!.vc.debugKeyboard.debugCycleThroughNumbers() }
        step("emoji plane", settle: 1.0) {
            rig!.vc.debugKeyboard.debugShowEmojiPlane()
            rig!.vc.view.layoutIfNeeded()
        }
        step("emoji scroll all sections", settle: 0.5) {
            if let cv = Self.find(UICollectionView.self, in: rig!.vc.view) {
                var x: CGFloat = 0
                while x < cv.contentSize.width {
                    cv.contentOffset.x = x; cv.layoutIfNeeded()
                    CATransaction.flush(); Self.spin(0.01)
                    x += cv.bounds.width
                }
            }
        }
        step("back to letters", settle: 0.5) { rig!.vc.debugKeyboard.debugSetPlane(numbers: false) }
        step("didReceiveMemoryWarning", settle: 0.5) {
            rig!.vc.didReceiveMemoryWarning()
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
        step("close + release controller", settle: 1.0) { rig!.close(); rig = nil }

        // --- rò rỉ: mở/đóng controller mới 20 lần (iOS tạo controller mới mỗi lần hiện) ---
        // 3 vòng làm ấm (sau cảnh báo bộ nhớ UIKit vừa xả cache CA/ảnh — nạp lại một lần) rồi đo.
        var cycle: [Double] = [], heapAt: [Int] = []
        for i in -3..<20 {
            autoreleasepool {
                let r = KeyboardBenchTests.Rig()
                let keys = Array(KeyboardBenchTests.corpus)
                for j in 0..<20 { _ = r.key(keys[j], index: j, drain: 0.002) }
                r.close()
            }
            Self.spin(0.3)
            if i >= 0, i % 5 == 4 { cycle.append(KeyboardBenchTests.footprintMB()); heapAt.append(Self.heapBytes()) }
        }
        let heapGrowMB = Double((heapAt.last ?? 0) - (heapAt.first ?? 0)) / 1_048_576
        print("RAMPART leak-cycles footprint every 5: \(cycle.map { String(format: "%.1f", $0) }) heap +\(String(format: "%.2f", heapGrowMB))MB")
        // Rò rỉ #1 RAM-AUDIT.md (UIKit giữ UIInputView cũ ⇒ cây view cũ): đã sửa bằng xé cây ở
        // viewDidDisappear. Heap (malloc, ổn định) là thước chính: giờ chỉ còn vỏ UIKit ~80
        // KB/vòng. Footprint dao động theo cache CA/ảnh của UIKit (vừa xả ở cảnh báo bộ nhớ) nên
        // chỉ chặn lỏng — trước khi sửa +17 MB / 20 vòng.
        XCTAssertLessThan(heapGrowMB, 3, "heap tăng đều qua 15 vòng mở/đóng")
        XCTAssertLessThan((cycle.last ?? 0) - (cycle.first ?? 0), 8, "RAM tăng đều qua 15 vòng mở/đóng")
    }

    /// Emoji màu: CoreText giải PNG (sbix) của Apple Color Emoji ra bitmap và GIỮ trong cache
    /// glyph của process. Đo heap tăng khi vẽ N emoji khác nhau ở các cỡ chữ, và có nhả khi
    /// bỏ font / cảnh báo bộ nhớ không. Số in "RAMEMOJI …".
    @MainActor func testEmojiGlyphCache() throws {
        try SlowTests.require()
        let all = EmojiData.categories.flatMap { $0.ids.map { EmojiData.emoji(Int($0)) } }
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func draw(_ list: ArraySlice<String>, size: CGFloat) {
            autoreleasepool {
                let font = UIFont.systemFont(ofSize: size)
                for e in list {
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(string: e, attributes: [.font: font]))
                    ctx.textPosition = CGPoint(x: 10, y: 10)
                    CTLineDraw(line, ctx)
                }
            }
        }
        Self.spin(0.3)
        var h0 = Self.heapBytes(), f0 = KeyboardBenchTests.footprintMB()
        for (size, range) in [(CGFloat(32), 0..<300), (CGFloat(32), 0..<300), (CGFloat(24), 300..<600),
                              (CGFloat(32), 600..<1200)] {
            draw(all[range], size: size)
            Self.spin(0.2)
            let h = Self.heapBytes(), f = KeyboardBenchTests.footprintMB()
            print(String(format: "RAMEMOJI %dpt emoji[%d..<%d]: heap %+.2fMB (%.1f KB/emoji) foot %+.1fMB",
                         Int(size), range.lowerBound, range.upperBound, Double(h - h0) / 1_048_576,
                         Double(h - h0) / 1024 / Double(range.count), f - f0))
            h0 = h; f0 = f
        }
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        Self.spin(1)
        var h = Self.heapBytes()
        print(String(format: "RAMEMOJI after memory warning: heap %+.2fMB", Double(h - h0) / 1_048_576))
        h0 = h

        // CTFont riêng (không qua cache UIFont) rồi nhả: cache glyph có đi theo font không?
        autoreleasepool {
            let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 31, nil)
            for e in all[1200..<1500] {
                let line = CTLineCreateWithAttributedString(NSAttributedString(
                    string: e, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                ctx.textPosition = CGPoint(x: 10, y: 10)
                CTLineDraw(line, ctx)
            }
            h = Self.heapBytes()
            print(String(format: "RAMEMOJI own CTFont 31pt, 300 emoji: heap %+.2fMB", Double(h - h0) / 1_048_576))
        }
        Self.spin(0.5)
        let h2 = Self.heapBytes()
        print(String(format: "RAMEMOJI after releasing own CTFont: heap %+.2fMB (vs before draw)", Double(h2 - h0) / 1_048_576))
        // Cỡ nhỏ hơn ⇒ bitmap nhỏ hơn? (strike sbix gần nhất) — 100 emoji MỚI mỗi cỡ
        _ = 0
        for (i, size) in [CGFloat(20), 26, 40, 32].enumerated() {
            let hb = Self.heapBytes()
            draw(all[(1500 + i * 100)..<(1600 + i * 100)], size: size)
            print(String(format: "RAMEMOJI %dpt: %.1f KB/emoji", Int(size), Double(Self.heapBytes() - hb) / 1024 / 100))
        }
    }

    static func find<T: UIView>(_ t: T.Type, in v: UIView) -> T? {
        if let x = v as? T { return x }
        for s in v.subviews { if let x = find(t, in: s) { return x } }
        return nil
    }

    static func makeJPEG(width: Int, height: Int) -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                        format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let img = r.image { ctx in
            for i in 0..<20 {
                UIColor(hue: CGFloat(i) / 20, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: i * height / 20, width: width, height: height / 20))
            }
        }
        return img.jpegData(compressionQuality: 0.7)!
    }
}
