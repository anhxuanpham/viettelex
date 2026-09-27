// TextToolsPanel.swift
// Bảng nổi "Công cụ…" cạnh con trỏ: 6 công cụ văn bản (TextActions.swift) thay cho 6 mục
// phẳng trong menu VietTelex (maintainer 27/09/2026). Menu con NSMenu KHÔNG dùng được:
// TextInputMenuAgent (macOS 27) vẽ menu con nhưng không chuyển action của mục con về IME.
//
// Giữ nguyên focus + vùng chọn của app đang gõ:
//  • NSPanel .nonactivatingPanel, canBecomeKey = false → không bao giờ thành key window,
//    app không activate, app đang gõ vẫn giữ first responder + vùng chọn.
//  • Vì panel không nhận phím, bàn phím đi qua Carbon hotkey KHÔNG modifier (1–6, ↑↓←→,
//    Tab/⇧Tab, Return/Enter, Esc) đăng ký CHỈ khi panel đang mở — WindowServer nuốt phím
//    đó trước app, gỡ đăng ký ngay khi đóng.
//  • Click ra ngoài / đổi app / gõ phím khác = đóng, không làm gì.
// Chi phí khi không dùng = 0: panel tạo lười lúc bấm "Công cụ…", thả hết (monitor, hotkey,
// cửa sổ) khi đóng.

import AppKit
import Carbon.HIToolbox
import InputMethodKit

// MARK: - Logic thuần (test ở AppTests/TextToolsPanelTests)

enum TextToolsPanelLogic {
    /// Thứ tự 6 nút = thứ tự cũ trong menu; phím số i+1 chạy tools[i].
    static let tools: [TextAction] = [.addTones, .upper, .lower, .title, .sentence, .stripDiacritics]

    enum Command: Equatable {
        case run(Int)        // chạy tools[index] ngay (phím số)
        case move(Int)       // dời chọn ±1 (vòng)
        case activate        // chạy mục đang chọn
        case cancel
    }

    /// Phím panel bắt khi đang mở: (keyCode, shift) → lệnh. Nguồn duy nhất cho cả
    /// đăng ký hotkey lẫn xử lý.
    static let bindings: [(keyCode: Int, shift: Bool, command: Command)] = {
        var b: [(Int, Bool, Command)] = []
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6]
        let keypad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
                      kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6]
        for i in 0..<tools.count {
            b.append((digits[i], false, .run(i)))
            b.append((keypad[i], false, .run(i)))
        }
        b.append((kVK_DownArrow, false, .move(1)))
        b.append((kVK_RightArrow, false, .move(1)))
        b.append((kVK_Tab, false, .move(1)))
        b.append((kVK_UpArrow, false, .move(-1)))
        b.append((kVK_LeftArrow, false, .move(-1)))
        b.append((kVK_Tab, true, .move(-1)))
        b.append((kVK_Return, false, .activate))
        b.append((kVK_ANSI_KeypadEnter, false, .activate))
        b.append((kVK_Space, false, .activate))
        b.append((kVK_Escape, false, .cancel))
        return b
    }()

    static func command(keyCode: Int, shift: Bool) -> Command? {
        bindings.first { $0.keyCode == keyCode && $0.shift == shift }?.command
    }

    /// Dời chọn có vòng (cuối ↓ → đầu).
    static func moved(_ index: Int, by delta: Int, count: Int = tools.count) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    /// Rect con trỏ có dùng được không (nhiều app trả rect rỗng ở gốc toạ độ, hoặc
    /// khổng lồ / NaN). Toạ độ màn hình Cocoa (gốc dưới-trái).
    static func isUsableCaretRect(_ r: NSRect, screens: [NSRect]) -> Bool {
        guard r.origin.x.isFinite, r.origin.y.isFinite, r.width.isFinite, r.height.isFinite,
              r.width >= 0, r.height >= 0, r.height < 400, r.width < 4000 else { return false }
        if r.origin == .zero && r.size == .zero { return false }
        let probe = NSPoint(x: r.minX, y: r.midY)
        return screens.contains { $0.insetBy(dx: -1, dy: -1).contains(probe) }
    }

    /// Góc dưới-trái của panel: ngay DƯỚI con trỏ, canh trái theo con trỏ; không đủ chỗ
    /// dưới thì lật lên TRÊN dòng; luôn kẹp trong `visible` (visibleFrame của màn hình)
    /// với lề `margin`.
    static func origin(caret: NSRect, panelSize: NSSize, visible: NSRect,
                       gap: CGFloat = 4, margin: CGFloat = 6) -> NSPoint {
        var x = caret.minX
        var y = caret.minY - gap - panelSize.height                 // dưới
        if y < visible.minY + margin {
            let above = caret.maxY + gap                             // lật lên trên
            if above + panelSize.height <= visible.maxY - margin { y = above }
        }
        x = min(max(x, visible.minX + margin), visible.maxX - margin - panelSize.width)
        y = min(max(y, visible.minY + margin), visible.maxY - margin - panelSize.height)
        // Panel to hơn màn hình (không xảy ra với 6 dòng) → dính mép trái/dưới.
        if panelSize.width + 2 * margin > visible.width { x = visible.minX }
        if panelSize.height + 2 * margin > visible.height { y = visible.minY }
        return NSPoint(x: x, y: y)
    }
}

// MARK: - Panel

final class TextToolsPanel {
    /// Panel đang mở (nil = không có gì sống).
    private(set) static var current: TextToolsPanel?

    /// MAIN thread. `client` = client IMK lúc bấm "Công cụ…" (nil được: runner tự dùng AX/⌘C).
    static func show(client: IMKTextInput?) {
        if current != nil { close(); return }        // bấm lại = đóng
        let p = TextToolsPanel(client: client)
        current = p
        p.present()
    }

    static func close() {
        guard let p = current else { return }
        current = nil
        p.teardown()
    }

    private let client: IMKTextInput?
    private var window: ToolsWindow?
    private var rows: [ToolRowView] = []
    private var selected = 0
    private var monitors: [Any] = []
    private var hotKeys: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var workspaceObserver: NSObjectProtocol?
    private static let signature: OSType = 0x5654_5450   // "VTTP" (≠ "VTTH" của TextActionHotkey)

    private init(client: IMKTextInput?) { self.client = client }

    // MARK: Layout

    private static let rowHeight: CGFloat = 24
    private static let width: CGFloat = 230
    private static let pad: CGFloat = 5

    private func present() {
        let n = TextToolsPanelLogic.tools.count
        let size = NSSize(width: Self.width, height: CGFloat(n) * Self.rowHeight + 2 * Self.pad)
        let w = ToolsWindow(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        w.isFloatingPanel = true
        w.becomesKeyOnlyIfNeeded = true
        w.hidesOnDeactivate = false
        w.level = .popUpMenu
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.animationBehavior = .utilityWindow

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .popover
        fx.state = .active
        fx.blendingMode = .behindWindow
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 10
        fx.layer?.masksToBounds = true
        fx.setAccessibilityRole(.list)
        fx.setAccessibilityLabel(VTLocalized("Tools…"))

        for (i, action) in TextToolsPanelLogic.tools.enumerated() {
            let y = size.height - Self.pad - CGFloat(i + 1) * Self.rowHeight
            let row = ToolRowView(frame: NSRect(x: Self.pad, y: y, width: size.width - 2 * Self.pad,
                                                height: Self.rowHeight),
                                  title: VTLocalized(action.titleKey), shortcut: "\(i + 1)")
            row.onHover = { [weak self] in self?.select(i) }
            row.onClick = { [weak self] in self?.run(i) }
            fx.addSubview(row)
            rows.append(row)
        }
        w.contentView = fx
        window = w
        select(0)

        w.setFrameOrigin(Self.anchorOrigin(client: client, panelSize: size))
        w.orderFrontRegardless()                   // KHÔNG makeKey / activate
        installInputHooks()
    }

    private static func anchorOrigin(client: IMKTextInput?, panelSize: NSSize) -> NSPoint {
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
            if caret == nil {
                var line = NSRect.zero
                _ = client.attributes(forCharacterIndex: max(0, sel.location == NSNotFound ? 0 : sel.location),
                                      lineHeightRectangle: &line)
                if TextToolsPanelLogic.isUsableCaretRect(line, screens: frames) { caret = line }
            }
        }
        let m = NSEvent.mouseLocation
        let anchor = caret ?? NSRect(x: m.x, y: m.y, width: 0, height: 0)
        let probe = NSPoint(x: anchor.minX, y: anchor.midY)
        let screen = screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(probe) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return TextToolsPanelLogic.origin(caret: anchor, panelSize: panelSize, visible: visible)
    }

    // MARK: Selection / run

    private func select(_ i: Int) {
        selected = i
        for (j, r) in rows.enumerated() { r.highlighted = (j == i) }
    }

    private func run(_ i: Int) {
        guard TextToolsPanelLogic.tools.indices.contains(i) else { return }
        let action = TextToolsPanelLogic.tools[i]
        let c = client
        Self.close()
        // Async: để panel tắt hẳn (và phím hotkey nhả) trước khi runner đọc AX/⌘C.
        DispatchQueue.main.async { TextActionRunner.run(action, client: c) }
    }

    private func perform(_ cmd: TextToolsPanelLogic.Command) {
        switch cmd {
        case .run(let i): run(i)
        case .move(let d): select(TextToolsPanelLogic.moved(selected, by: d))
        case .activate: run(selected)
        case .cancel: Self.close()
        }
    }

    // MARK: Input hooks (sống đúng lúc panel mở)

    private func installInputHooks() {
        // Click ra ngoài (sự kiện gửi app KHÁC — click trong panel không tới đây).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                     handler: { _ in TextToolsPanel.close() }) {
            monitors.append(m)
        }
        // Gõ phím khác (không phải phím panel bắt) = user bỏ panel, gõ tiếp. Cần quyền
        // Accessibility; không có thì chỉ mất tiện ích này.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { e in
            let shift = e.modifierFlags.contains(.shift)
            if TextToolsPanelLogic.command(keyCode: Int(e.keyCode), shift: shift) == nil
                || !e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                TextToolsPanel.close()
            }
        }) { monitors.append(m) }
        // Đổi sang app KHÁC = đóng (client IMK đã chụp không còn đúng chỗ).
        let hostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != hostPid { TextToolsPanel.close() }
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard st == noErr, hk.signature == TextToolsPanel.signature else { return OSStatus(eventNotHandledErr) }
            let idx = Int(hk.id)
            DispatchQueue.main.async {
                guard let p = TextToolsPanel.current,
                      TextToolsPanelLogic.bindings.indices.contains(idx) else { return }
                p.perform(TextToolsPanelLogic.bindings[idx].command)
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        var failed = 0
        for (idx, b) in TextToolsPanelLogic.bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(idx))
            let st = RegisterEventHotKey(UInt32(b.keyCode), b.shift ? UInt32(shiftKey) : 0, id,
                                         GetApplicationEventTarget(), 0, &ref)
            if st == noErr, let ref { hotKeys.append(ref) } else { failed += 1 }
        }
        if failed > 0 { DebugLog.log("tools panel: \(failed) hotkey(s) failed to register") }
    }

    private func teardown() {
        for ref in hotKeys { UnregisterEventHotKey(ref) }
        hotKeys = []
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        if let o = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObserver = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        rows = []
    }
}

/// Panel không bao giờ thành key/main: app đang gõ giữ focus + vùng chọn.
private final class ToolsWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Một dòng kiểu mục menu: tên công cụ + phím số mờ bên phải; nền accent khi chọn.
private final class ToolRowView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var highlighted = false { didSet { if highlighted != oldValue { updateColors() } } }
    private let titleField: NSTextField
    private let keyField: NSTextField
    private let bg = NSView()

    init(frame: NSRect, title: String, shortcut: String) {
        titleField = NSTextField(labelWithString: title)
        keyField = NSTextField(labelWithString: shortcut)
        super.init(frame: frame)
        bg.frame = bounds
        bg.autoresizingMask = [.width, .height]
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 5
        addSubview(bg)
        titleField.font = .menuFont(ofSize: 0)
        titleField.lineBreakMode = .byTruncatingTail
        keyField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        keyField.alignment = .right
        let h = titleField.intrinsicContentSize.height
        titleField.frame = NSRect(x: 10, y: (frame.height - h) / 2, width: frame.width - 44, height: h)
        let kh = keyField.intrinsicContentSize.height
        keyField.frame = NSRect(x: frame.width - 30, y: (frame.height - kh) / 2, width: 20, height: kh)
        addSubview(titleField)
        addSubview(keyField)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        // cgColor phải resolve theo appearance của panel (sáng/tối), không theo process.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bg.layer?.backgroundColor = highlighted ? NSColor.selectedContentBackgroundColor.cgColor
                                                    : NSColor.clear.cgColor
        }
        titleField.textColor = highlighted ? .alternateSelectedControlTextColor : .labelColor
        keyField.textColor = highlighted ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75)
                                         : .tertiaryLabelColor
    }
}
