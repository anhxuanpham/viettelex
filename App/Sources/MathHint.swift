// MathHint.swift — gợi ý cạnh con trỏ cho macOS: "Hiện kết quả phép tính" ("12*3=" ⇒ "= 36")
// và "Chip số" (chỉ dạng tiền: "1tr2␣" ⇒ "1.200.000 ₫"). Logic chung iOS/Android:
// iOS/Keyboard/MathResults.swift + NumberChips.swift (fixture math-results.txt / number-chips.txt).
// KHÔNG tự chèn — chỉ đề xuất; Tab (phép tính: cả Enter) mới áp dụng, phím khác thì tắt.
//
// Hai kiểu hiển thị:
//  • Ô ứng viên HỆ THỐNG (IMKCandidates) — đường IMK (app in-place/marked) khi client
//    báo được rect con trỏ (firstRect) hợp lệ: cửa sổ ứng viên chuẩn của macOS, đặt
//    ngay dưới con trỏ bàn phím.
//  • Ô nổi riêng (NSPanel không lấy focus) — đường tap (terminal, Chromium, Office) và
//    app IMK có firstRect hỏng. Vị trí: firstRect của client IMK (nếu cùng app) → AX
//    bounds con trỏ → AX bounds ký tự trước con trỏ → ước lượng theo số dòng AX → góc
//    TRÁI-dưới của ô đang gõ. Không bao giờ đặt theo chuột; không tìm được ⇒ không hiện.
//
// Chi phí: chỉ chạy NGAY SAU phím "=" / dấu cách sau một cụm có chữ số (một lần đọc
// ~64 ký tự trước con trỏ qua IMK hoặc AX) — phím khác chỉ đọc một cờ dưới khoá.
//  • IMK: TelexInputController.handle gọi `afterEquals` / `afterNumberSpace`, `keyAction`.
//  • Tap: TerminalTap gọi cùng các hàm với client nil trên TAP-thread — trạng thái nằm
//    dưới `lock`. "=" thấy ở cả hai đường chỉ tính một lần (`lastCheck`).
import AppKit
import InputMethodKit

enum MathHintLogic {
    /// Phím vừa gõ là "=" trơn (không ⌘/⌃/⌥) ⇒ thử tính.
    static func isTrigger(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        characters == "=" && modifiers.intersection([.command, .control, .option]).isEmpty
    }

    /// Văn bản trước con trỏ (đã có "=" ở cuối) → chữ kết quả để chèn, nil nếu không phải
    /// phép tính (cùng quy tắc với chip iOS/Android — fixture math-results.txt).
    static func result(beforeCaret: String) -> String? {
        MathResults.chip(before: beforeCaret)?.insert
    }

    /// Chữ hiện trong ô: "= 36".
    static func label(_ result: String) -> String { "= " + result }
}

/// Một gợi ý đang chờ: `replace` = đuôi văn bản trước con trỏ sẽ bị thay (rỗng = chỉ
/// chèn thêm — kết quả phép tính), `insert` = chữ chèn vào.
struct CaretSuggestion: Equatable {
    enum Kind: Equatable { case math, number }
    let kind: Kind
    let display: String
    let replace: String
    let insert: String
}

/// Logic THUẦN của gợi ý cạnh con trỏ (test được, không AppKit sống).
enum CaretHintLogic {
    // MARK: Phím khi gợi ý đang hiện

    enum KeyAction: Equatable {
        case accept          // áp dụng gợi ý, nuốt phím
        case dismissConsume  // Esc: tắt gợi ý, nuốt phím
        case dismissPass     // phím khác: tắt gợi ý, phím đi tiếp như thường
    }

    static let kTab = 48, kReturn = 36, kKeypadEnter = 76, kEscape = 53

    /// `plain` = không ⌘/⌃/⌥/⇧. Tab chấp nhận cả hai loại; Enter chỉ cho phép tính
    /// (sau "50k␣" Enter là gửi tin nhắn / xuống dòng — không được cướp). Phím số KHÔNG
    /// chọn: gõ "5+5=" rồi tự gõ "10" không được thành "1010".
    static func action(kind: CaretSuggestion.Kind, keyCode: Int, plain: Bool) -> KeyAction {
        if keyCode == kEscape, plain { return .dismissConsume }
        guard plain else { return .dismissPass }
        if keyCode == kTab { return .accept }
        if kind == .math, keyCode == kReturn || keyCode == kKeypadEnter { return .accept }
        return .dismissPass
    }

    // MARK: Chip số (chỉ dạng tiền)

    /// Dấu cách vừa gõ sau một cụm có chữ số ("1tr2", "50k") — hoặc cụm đơn vị ngay sau
    /// cụm số ("2 tỷ", "15 triệu") ⇒ đáng đọc màn hình. Không thì không đọc gì cả.
    static func numberWorthChecking(boundary: String?, run: String, prevRun: String) -> Bool {
        guard boundary == " ", !run.isEmpty else { return false }
        if run.contains(where: \.isNumber) { return true }
        return run.count <= 6 && prevRun.contains(where: \.isNumber)
    }

    /// Văn bản trước con trỏ (kết thúc bằng đúng một dấu cách) → gợi ý dạng tiền, nil nếu
    /// không có. Dùng NumberChips.chip chung iOS/Android nhưng CHỈ giữ dạng tiền
    /// ("1.200.000 ₫", "1.250.000đ") — bỏ "đọc số thành chữ" trên macOS.
    static func moneyChip(before: String) -> CaretSuggestion? {
        guard before.hasSuffix(" "), let c = NumberChips.chip(before: before),
              isMoneyFormat(c.display) else { return nil }
        return CaretSuggestion(kind: .number, display: c.display, replace: c.replace, insert: c.insert)
    }

    static func isMoneyFormat(_ display: String) -> Bool {
        let d = display.hasPrefix("-") ? display.dropFirst() : Substring(display)
        return d.first?.isNumber == true
    }

    /// Văn bản dựng lại từ dòng phím (terminal không đọc được AX): cụm trước + cụm vừa
    /// gõ + dấu cách. Chỉ khi cụm đã NEO (thấy khoảng trắng/xuống dòng trước nó).
    static func keyStreamBefore(anchored: Bool, prevRun: String, run: String) -> String? {
        guard anchored, !run.isEmpty else { return nil }
        return (prevRun.isEmpty ? "" : prevRun + " ") + run + " "
    }

    // MARK: Vị trí

    enum CaretSource: Equatable, CaseIterable {
        case imkFirstRect     // client IMK: firstRect(forCharacterRange: selectedRange)
        case axCaret          // AXBoundsForRange (caret, 0)
        case axPrevChar       // AXBoundsForRange (caret-1, 1) → mép phải ký tự trước
        case axLineEstimate   // AXInsertionPointLineNumber + cột → ước lượng
        case fieldStart       // khung ô đang gõ → góc TRÁI-dưới (gần đầu chữ)
    }

    static let order: [CaretSource] = CaretSource.allCases

    /// Rect con trỏ đầu tiên dùng được theo `order`. `provider` được gọi LẦN LƯỢT và dừng
    /// ở nguồn đầu tiên hợp lệ (mỗi nguồn là vài lần gọi AX/IMK — không gọi thừa).
    /// Nguồn "con trỏ" phải nằm trong ô đang gõ (nếu biết `field`) và không to cỡ cả ô
    /// (Chromium/Electron hay trả khung ô cho range rỗng). nil ⇒ không hiện (không chuột).
    static func anchor(field: NSRect?, screens: [NSRect],
                       provider: (CaretSource) -> NSRect?) -> (rect: NSRect, source: CaretSource)? {
        for src in order {
            guard let r = provider(src) else { continue }
            if src == .fieldStart {
                guard TextToolsPanelLogic.isUsableCaretRect(r, screens: screens) || r.height >= 400
                else { continue }
                return (fieldStartAnchor(r), src)
            }
            if plausibleCaret(r, field: field, screens: screens) { return (r, src) }
        }
        return nil
    }

    static func plausibleCaret(_ r: NSRect, field: NSRect?, screens: [NSRect]) -> Bool {
        guard TextToolsPanelLogic.isUsableCaretRect(r, screens: screens), r.width <= 60 else { return false }
        guard let f = field, f.width > 0, f.height > 0 else { return true }
        let probe = NSPoint(x: r.minX, y: r.midY)
        return f.insetBy(dx: -4, dy: -4).contains(probe)
    }

    /// Nguồn cuối: khung ô ⇒ neo ở mép TRÁI (lề 8pt), đáy ô — ô gợi ý hiện ngay dưới
    /// đầu ô gõ thay vì tít mép phải.
    static func fieldStartAnchor(_ field: NSRect) -> NSRect {
        let h = min(field.height, 22)
        return NSRect(x: field.minX + 8, y: field.minY, width: 0, height: h)
    }

    /// Ước lượng rect con trỏ từ số dòng AX (0-based) và cột (số ký tự sau "\n" cuối).
    /// Ô một dòng (thấp) ⇒ giữa ô theo chiều dọc. x kẹp trong ô.
    static func lineEstimate(field: NSRect, line: Int, column: Int,
                             lineHeight: CGFloat = 18, charWidth: CGFloat = 7.5, inset: CGFloat = 8) -> NSRect {
        let x = min(field.minX + inset + CGFloat(max(0, column)) * charWidth, field.maxX - inset)
        let y: CGFloat
        if field.height < 44 {
            y = field.midY - lineHeight / 2
        } else {
            y = max(field.minY, field.maxY - 4 - CGFloat(max(0, line) + 1) * lineHeight)
        }
        return NSRect(x: x, y: y, width: 0, height: lineHeight)
    }

    /// Cột con trỏ theo văn bản trước nó.
    static func column(before: String) -> Int {
        guard let i = before.lastIndex(where: { $0 == "\n" || $0 == "\r" }) else { return before.count }
        return before.distance(from: before.index(after: i), to: before.endIndex)
    }

    // MARK: Kiểu hiển thị

    enum Surface: Equatable { case candidates, panel }

    /// Ô ứng viên hệ thống chỉ khi: đường IMK (client + controller), có IMKServer, và
    /// firstRect của client là nguồn thắng (hệ thống đặt cửa sổ theo chính client đó).
    static func surface(imkPath: Bool, hasCandidateWindow: Bool, source: CaretSource) -> Surface {
        imkPath && hasCandidateWindow && source == .imkFirstRect ? .candidates : .panel
    }
}

final class CaretHint {
    static let shared = CaretHint()
    private let lock = NSLock()
    private var pending: CaretSuggestion?                   // guarded by lock
    private var pendingSurface: CaretHintLogic.Surface?     // guarded by lock
    private var lastCheck: UInt64 = 0                       // guarded by lock
    private var shownFrameCG: CGRect?                       // guarded by lock (toạ độ CG, gốc trên-trái)
    private var window: NSPanel?                            // main only
    private var hideWork: DispatchWorkItem?                 // main only
    /// Đọc nhiều lần mỗi phím (TAP-thread + main) — chỉ đọc cờ, không đụng UserDefaults.
    private(set) var mathEnabled: Bool
    private(set) var numberEnabled: Bool

    private init() {
        mathEnabled = AppState.shared.mathResults
        numberEnabled = AppState.shared.numberChips
    }
    func reloadSetting() {
        mathEnabled = AppState.shared.mathResults
        numberEnabled = AppState.shared.numberChips
    }

    var isShowing: Bool { lock.withLock { pending != nil } }
    var current: CaretSuggestion? { lock.withLock { pending } }

    /// Ô ứng viên hệ thống dùng chung (một IMKServer ⇒ một cửa sổ). nil trong test host.
    private static let candidateWindow: IMKCandidates? = {
        guard let server = telexServer,
              let c = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
        else { return nil }
        // Phím tới controller TRƯỚC (mặc định cửa sổ ứng viên ăn trước ⇒ Enter/số/mũi tên
        // bị nó xử lý): mình tự quyết Tab/Enter/Esc; phím khác ẩn cửa sổ rồi mới đi tiếp.
        c.setAttributes([IMKCandidatesSendServerKeyEventFirst as String: NSNumber(value: true)])
        return c
    }()

    // MARK: Kích hoạt

    /// MAIN. Gọi sau khi phím "=" đã vào app. `client` nil ⇒ đường tap (đọc AX).
    func afterEquals(client: IMKTextInput?, controller: TelexInputController?) {
        guard mathEnabled, !dedupe() else { return }
        // Đợi app nhận "=" (tap: phím đi native; IMK: insertText vừa gọi) rồi mới đọc.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, let before = Self.textBeforeCaret(client: client),
                  let r = MathHintLogic.result(beforeCaret: before) else { return }
            let s = CaretSuggestion(kind: .math, display: MathHintLogic.label(r), replace: "", insert: r)
            self.present(s, before: before, client: client, controller: controller)
        }
    }

    /// Bất kỳ thread. Dấu cách vừa gõ sau cụm có chữ số. `keyStream` = văn bản dựng từ
    /// dòng phím (tap, khi AX không đọc được — terminal). `canReplace` = đường gọi thay
    /// được chữ đã chốt (IMK: app đã chứng minh in-place).
    func afterNumberSpace(client: IMKTextInput?, controller: TelexInputController?,
                          keyStream: String?, canReplace: Bool) {
        guard numberEnabled, canReplace else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            let before = Self.textBeforeCaret(client: client) ?? (client == nil ? keyStream : nil)
            guard let before, let s = CaretHintLogic.moneyChip(before: before) else { return }
            self.present(s, before: before, client: client, controller: controller)
        }
    }

    private func dedupe() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        return lock.withLock { () -> Bool in
            defer { lastCheck = now }
            return now &- lastCheck < 150_000_000
        }
    }

    // MARK: Phím

    /// Bất kỳ thread. Việc cần làm với phím này khi gợi ý đang hiện (nil = không hiện gì).
    /// `panelOnly` (tap) ⇒ chỉ nhận gợi ý dạng ô nổi — ô ứng viên IMK do controller lo.
    func keyAction(keyCode: Int, plain: Bool, panelOnly: Bool = false) -> CaretHintLogic.KeyAction? {
        lock.withLock {
            guard let p = pending, !panelOnly || pendingSurface == .panel else { return nil }
            return CaretHintLogic.action(kind: p.kind, keyCode: keyCode, plain: plain)
        }
    }

    /// Bất kỳ thread. Lấy gợi ý để áp dụng (và tắt ô).
    func take() -> CaretSuggestion? {
        let r: CaretSuggestion? = lock.withLock {
            defer { pending = nil; pendingSurface = nil; shownFrameCG = nil }
            return pending
        }
        if r != nil { hideUI() }
        return r
    }

    /// Bất kỳ thread. Tắt gợi ý (không chặn phím). Trên main: ẩn NGAY — cửa sổ ứng viên
    /// phải biến mất trước khi phím đi tiếp, không thì nó xử lý phím đó.
    func dismiss() {
        let had = lock.withLock { () -> Bool in
            defer { pending = nil; pendingSurface = nil; shownFrameCG = nil }
            return pending != nil
        }
        if had { hideUI() }
    }

    /// TAP-thread (chuột xuống). Click ngoài ô ứng viên đang hiện ⇒ tắt. `point` toạ độ
    /// CGEvent (gốc trên-trái màn hình chính).
    func dismissForClick(at point: CGPoint) {
        let inside = lock.withLock { () -> Bool? in
            guard pending != nil else { return nil }
            return shownFrameCG?.contains(point) ?? false
        }
        if inside == false { dismiss() }
    }

    /// Chỉ cho test: đặt trạng thái như vừa hiện (không tạo cửa sổ).
    func setPendingForTesting(_ s: CaretSuggestion?, surface: CaretHintLogic.Surface = .panel) {
        lock.withLock { pending = s; pendingSurface = s == nil ? nil : surface }
    }

    /// Chuỗi hiện trong ô ứng viên (IMKInputController.candidates(_:)).
    var candidateStrings: [String] { lock.withLock { pending.map { [$0.display] } ?? [] } }

    private func hideUI() {
        if Thread.isMainThread { hideWindows() } else { DispatchQueue.main.async { self.hideWindows() } }
    }

    // MARK: Đọc văn bản trước con trỏ

    private static let window64 = MathResults.maxLength + 2

    private static func textBeforeCaret(client: IMKTextInput?) -> String? {
        if let client {
            let sel = client.selectedRange()
            guard sel.location != NSNotFound, sel.length == 0, sel.location > 0 else { return nil }
            let start = max(0, sel.location - window64)
            return client.attributedSubstring(from: NSRange(location: start, length: sel.location - start))?.string
        }
        guard let caret = AXTextEdit.readCaret(), caret > 0 else { return nil }
        let start = max(0, caret - window64)
        return AXTextEdit.readString(at: start, length: caret - start)
    }

    // MARK: Hiển thị

    private func present(_ s: CaretSuggestion, before: String, client: IMKTextInput?,
                         controller: TelexInputController?) {
        hideWindows()
        let screens = NSScreen.screens.map(\.frame)
        // Client IMK cho vị trí: đường IMK dùng chính client; đường tap mượn client của
        // controller đang active NẾU cùng app đang trước (firstRect thường đúng hơn AX).
        let posClient = client ?? TelexInputController.activeClientForFrontApp()
        let ax = AXTextEdit.focusedGeometryReader()
        let field = ax?.fieldFrame()
        let prevIsNewline = before.last == "\n" || before.last == "\r"
        let found = CaretHintLogic.anchor(field: field, screens: screens) { src in
            switch src {
            case .imkFirstRect: return posClient.flatMap(Self.imkCaretRect)
            case .axCaret: return ax?.caretBounds()
            case .axPrevChar:
                guard !prevIsNewline, let r = ax?.previousCharBounds() else { return nil }
                return NSRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
            case .axLineEstimate:
                guard let f = field, let line = ax?.insertionLine() else { return nil }
                return CaretHintLogic.lineEstimate(field: f, line: line, column: CaretHintLogic.column(before: before))
            case .fieldStart: return field
            }
        }
        guard let found else {
            DebugLog.log("caret hint \(s.kind): no caret position → not shown")
            return
        }
        let surface = CaretHintLogic.surface(imkPath: client != nil && controller != nil,
                                             hasCandidateWindow: Self.candidateWindow != nil,
                                             source: found.source)
        lock.withLock { pending = s; pendingSurface = surface }
        if surface == .candidates, let c = Self.candidateWindow {
            showCandidates(c, s, caret: found.rect)
            let f = c.candidateFrame()
            let primaryH = NSScreen.screens.first?.frame.height ?? 0
            let cg = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
            lock.withLock { shownFrameCG = cg }
        } else {
            showPanel(s, caret: found.rect)   // ignoresMouseEvents: mọi click đều "ngoài"
        }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        DebugLog.log("caret hint \(s.kind): len=\(s.insert.count) via \(found.source) → \(surface)")
    }

    private static func imkCaretRect(_ client: IMKTextInput) -> NSRect? {
        let sel = client.selectedRange()
        guard sel.location != NSNotFound else { return nil }
        var actual = NSRange(location: NSNotFound, length: 0)
        return client.firstRect(forCharacterRange: NSRange(location: sel.location, length: 0), actualRange: &actual)
    }

    private static func visibleFrame(for caret: NSRect) -> NSRect {
        let probe = NSPoint(x: caret.minX, y: caret.midY)
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(probe) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func showCandidates(_ c: IMKCandidates, _ s: CaretSuggestion, caret: NSRect) {
        c.setCandidateData([s.display])
        c.show(kIMKLocateCandidatesBelowHint)
        // Hệ thống tự đặt theo client; đặt lại theo rect đã kiểm (cùng nguồn firstRect)
        // để không bao giờ lệch khỏi con trỏ, và lật lên trên khi sát đáy màn hình.
        let size = c.candidateFrame().size
        if size.width > 0, size.height > 0 {
            let o = TextToolsPanelLogic.origin(caret: caret, panelSize: size, visible: Self.visibleFrame(for: caret))
            c.setCandidateFrameTopLeft(NSPoint(x: o.x, y: o.y + size.height))
        }
    }

    private func showPanel(_ s: CaretSuggestion, caret: NSRect) {
        let label = NSTextField(labelWithString: s.display)
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        let hint = NSTextField(labelWithString: "⇥ Tab")
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, hint])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        let size = stack.fittingSize

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .popover
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 8
        fx.layer?.masksToBounds = true
        stack.frame = fx.bounds
        fx.addSubview(stack)

        let w = HintWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .popUpMenu
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.contentView = fx
        w.setFrameOrigin(TextToolsPanelLogic.origin(caret: caret, panelSize: size,
                                                    visible: Self.visibleFrame(for: caret)))
        w.orderFrontRegardless()
        window = w
    }

    private func hideWindows() {
        hideWork?.cancel(); hideWork = nil
        window?.orderOut(nil)
        window = nil
        if let c = Self.candidateWindow, c.isVisible() { c.hide() }
    }
}

/// Ô không bao giờ thành key/main: app đang gõ giữ focus.
private final class HintWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
