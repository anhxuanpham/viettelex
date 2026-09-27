// TextActionHotkey.swift
// Phím tắt toàn hệ thống cho "Thêm dấu cho vùng chọn" (mặc định TẮT). Carbon
// RegisterEventHotKey: WindowServer tự so khớp tổ hợp — process mình không thấy phím
// nào khác, không đi qua event tap, không tốn gì theo phím gõ. Tắt = gỡ đăng ký.

import AppKit
import Carbon.HIToolbox

enum TextActionHotkey {
    /// Giá trị lưu (AppState.addTonesHotkey) → nhãn hiển thị. Phím T theo vị trí QWERTY.
    static let choices: [(id: String, label: String)] = [
        ("off", ""), ("ctrl-opt-t", "⌃⌥T"), ("ctrl-shift-t", "⌃⇧T"), ("opt-cmd-t", "⌥⌘T"),
    ]

    /// Modifier Carbon của lựa chọn; nil = tắt / giá trị lạ.
    static func carbonModifiers(for choice: String) -> UInt32? {
        switch choice {
        case "ctrl-opt-t": return UInt32(controlKey | optionKey)
        case "ctrl-shift-t": return UInt32(controlKey | shiftKey)
        case "opt-cmd-t": return UInt32(optionKey | cmdKey)
        default: return nil
        }
    }

    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?
    static let signature: OSType = 0x5654_5448   // "VTTH"

    /// MAIN thread. Gọi lúc khởi động và khi đổi lựa chọn trong Cài đặt.
    static func apply(_ choice: String) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        guard let mods = carbonModifiers(for: choice) else { return }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // Chỉ nhận hotkey CỦA MÌNH: bảng Công cụ… (TextToolsPanel) đăng ký phím riêng
            // lúc đang mở trên cùng event target — không lọc thì phím 1–6 cũng chạy Thêm dấu.
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                let st = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hk)
                guard st == noErr, hk.signature == TextActionHotkey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { TextActionRunner.run(.addTones, client: nil) }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_T), mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { DebugLog.log("add-tones hotkey \(choice): register failed \(status)") }
    }
}
