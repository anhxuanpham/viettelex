// MathHint.swift — "Hiện kết quả phép tính" cho macOS (như chip kết quả trên iOS/Android,
// logic chung iOS/Keyboard/MathResults.swift). Gõ "12*3=" ⇒ ô nhỏ nổi cạnh con trỏ
// "= 36   ⇥ Tab"; bấm Tab chèn "36" sau dấu "=", phím khác (hoặc 8s) thì ô tự tắt.
// KHÔNG tự chèn — chỉ đề xuất, như bàn phím iOS gốc.
//
// Chi phí: chỉ chạy NGAY SAU phím "=" (một lần đọc ~64 ký tự trước con trỏ qua IMK
// attributedSubstring hoặc AX) — phím khác chỉ đọc một cờ dưới khoá. Hai đường gõ:
//  • IMK (in-place/marked): TelexInputController.handle gọi `afterEquals(client:)`,
//    `consumeTab()` / `dismiss()`.
//  • Tap (terminal/Chromium): TerminalTap gọi `afterEquals(client: nil)` (đọc AX) và
//    `consumeTab()` trên TAP-thread — trạng thái nằm dưới `lock`. Đường nào thấy Tab
//    trước thì chèn (tap chặn Tab thì IMK không thấy nữa); "=" thấy ở cả hai đường chỉ
//    tính một lần (`lastCheck`).
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

final class MathHint {
    static let shared = MathHint()
    private let lock = NSLock()
    private var pending: String?                            // guarded by lock
    private var lastCheck: UInt64 = 0                       // guarded by lock
    private var window: NSPanel?                            // main only
    private var hideWork: DispatchWorkItem?                 // main only
    /// Đọc nhiều lần mỗi phím (TAP-thread + main) — chỉ đọc cờ, không đụng UserDefaults.
    private(set) var enabled: Bool

    private init() { enabled = AppState.shared.mathResults }
    func reloadSetting() { enabled = AppState.shared.mathResults }

    var isShowing: Bool { lock.withLock { pending != nil } }

    /// MAIN. Gọi sau khi phím "=" đã vào app. `client` nil ⇒ đọc qua AX (đường tap).
    func afterEquals(client: IMKTextInput?) {
        guard enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let dup = lock.withLock { () -> Bool in
            defer { lastCheck = now }
            return now &- lastCheck < 150_000_000
        }
        if dup { return }
        // Đợi app nhận "=" (tap: phím đi native; IMK: insertText vừa gọi) rồi mới đọc.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, let before = Self.textBeforeCaret(client: client),
                  let r = MathHintLogic.result(beforeCaret: before) else { return }
            self.lock.withLock { self.pending = r }
            self.present(result: r, client: client)
            DebugLog.log("math hint: result len=\(r.count) (\(client == nil ? "ax" : "imk"))")
        }
    }

    /// Bất kỳ thread. Tab trơn khi ô đang hiện ⇒ trả chữ cần chèn (và tắt ô); nil ⇒ không
    /// phải việc của mình, xử lý phím như thường.
    func consumeTab() -> String? {
        let r: String? = lock.withLock {
            defer { pending = nil }
            return pending
        }
        if r != nil { DispatchQueue.main.async { self.hideWindow() } }
        return r
    }

    /// Bất kỳ thread. Phím khác khi ô đang hiện ⇒ tắt ô (không chặn phím).
    func dismiss() {
        let had = lock.withLock { () -> Bool in
            defer { pending = nil }
            return pending != nil
        }
        if had { DispatchQueue.main.async { self.hideWindow() } }
    }

    // MARK: - Đọc văn bản trước con trỏ

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

    // MARK: - Ô nổi

    private func present(result: String, client: IMKTextInput?) {
        hideWindow()
        let label = NSTextField(labelWithString: MathHintLogic.label(result))
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
        w.setFrameOrigin(Self.origin(client: client, size: size))
        w.orderFrontRegardless()
        window = w

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func hideWindow() {
        hideWork?.cancel(); hideWork = nil
        window?.orderOut(nil)
        window = nil
    }

    private static func origin(client: IMKTextInput?, size: NSSize) -> NSPoint {
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        var caret: NSRect?
        if let client {
            let sel = client.selectedRange()
            if sel.location != NSNotFound {
                var actual = NSRange(location: NSNotFound, length: 0)
                let r = client.firstRect(forCharacterRange: NSRange(location: sel.location, length: 0),
                                         actualRange: &actual)
                if TextToolsPanelLogic.isUsableCaretRect(r, screens: frames) { caret = r }
            }
        } else if let r = AXTextEdit.caretScreenRect(),
                  TextToolsPanelLogic.isUsableCaretRect(r, screens: frames) {
            caret = r
        }
        let m = NSEvent.mouseLocation
        let anchor = caret ?? NSRect(x: m.x, y: m.y, width: 0, height: 0)
        let probe = NSPoint(x: anchor.minX, y: anchor.midY)
        let screen = screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(probe) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return TextToolsPanelLogic.origin(caret: anchor, panelSize: size, visible: visible)
    }
}

/// Ô không bao giờ thành key/main: app đang gõ giữ focus.
private final class HintWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
