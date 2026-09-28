// text_tool_ipc.h — Công cụ văn bản between VietTelex.exe and the TIP (portable part).
//
// The TIP reads and replaces the SELECTION through TSF (it runs inside the app); the
// transform itself (HOA/thường/…/Thêm dấu, ~2 MB of language data) runs in VietTelex.exe
// only — never in every process the TIP is loaded into (macOS runs Thêm dấu in a child
// process for the same reason).
//
//   app  --PostMessage(kTipTextToolMsg, tool, request)-->  TIP window of the target thread
//   TIP  --WM_COPYDATA(kCopySelection: request, tool, text)-->  app        (has selection)
//   TIP  --AppCommand::TextToolReply(request, Fallback|Refused)-->  app    (no TSF selection
//                                                  / password field — app falls back to
//                                                  Ctrl+C / Ctrl+V, or beeps)
//   app  --WM_COPYDATA(kCopyResult: request, tool, new text)-->  TIP
//   TIP  replaces exactly the range it read (if it is still the selection) and replies
//        AppCommand::TextToolReply(request, Replaced|Failed).
//
// The TIP window is a message-only window titled textToolWindowTitle(thread id), one per
// TSF thread manager, created at Activate; the app finds it by that title
// (FindWindowEx(HWND_MESSAGE, …, nullptr, title)). Its CLASS name is private to each module
// load (TIP side), so a class left registered by an unloaded TIP can never be reused.
// Messages the app sends go DOWN in integrity (allowed by UIPI); the TIP's WM_COPYDATA /
// kAppCommandMsg go UP and are allowed by ChangeWindowMessageFilterEx on the app window.
#pragma once
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace vtx {

// "VietTelexTip:<decimal thread id>"
inline std::wstring textToolWindowTitle(unsigned long threadId) {
    return L"VietTelexTip:" + std::to_wstring(threadId);
}
constexpr unsigned kTipTextToolMsg = 0x8000u + 0x58u;  // WM_APP + 0x58: wParam tool, lParam request
constexpr uint32_t kCopySelection = 0x56545331u;       // "VTS1" TIP -> app
constexpr uint32_t kCopyResult = 0x56545332u;          // "VTS2" app -> TIP
constexpr size_t kTextToolMaxLength = 20000;           // UTF-16 units (TextActionTransform.maxLength)

enum class TextToolStatus : unsigned {
    Fallback = 1,  // no TSF selection here: app tries Ctrl+C / Ctrl+V
    Refused = 2,   // password / PIN field: do nothing (beep)
    Replaced = 3,  // done
    Failed = 4,    // selection changed or the app refused the edit: do nothing (beep)
};

// AppCommand::TextToolReply lParam: request (28 bits) << 4 | status.
constexpr uint32_t kTextToolRequestMask = 0x0FFFFFFFu;
inline uint32_t textToolReplyParam(uint32_t request, TextToolStatus s) {
    return (request & kTextToolRequestMask) << 4 | (static_cast<uint32_t>(s) & 0xFu);
}
inline uint32_t textToolReplyRequest(uint32_t lp) { return (lp >> 4) & kTextToolRequestMask; }
inline TextToolStatus textToolReplyStatus(uint32_t lp) { return static_cast<TextToolStatus>(lp & 0xFu); }

// Password-like input scopes (InputScope.h): never read, never replace.
inline bool isSecretInputScope(int scope) {
    return scope == 31 /* IS_PASSWORD */ || scope == 63 /* IS_NUMERIC_PASSWORD */ || scope == 64 /* IS_NUMERIC_PIN */ ||
           scope == 65 /* IS_ALPHANUMERIC_PIN */ || scope == 66 /* IS_ALPHANUMERIC_PIN_SET */;
}

// WM_COPYDATA payload: request u32 | tool u32 | UTF-16 text (no terminator), little-endian.
inline std::vector<uint8_t> packTextToolData(uint32_t request, uint32_t tool, const std::u16string& text) {
    std::vector<uint8_t> b(8 + text.size() * 2);
    for (int i = 0; i < 4; ++i) {
        b[static_cast<size_t>(i)] = static_cast<uint8_t>(request >> (8 * i));
        b[static_cast<size_t>(4 + i)] = static_cast<uint8_t>(tool >> (8 * i));
    }
    for (size_t i = 0; i < text.size(); ++i) {
        b[8 + 2 * i] = static_cast<uint8_t>(text[i] & 0xFF);
        b[9 + 2 * i] = static_cast<uint8_t>(text[i] >> 8);
    }
    return b;
}

// False on a malformed payload (odd size, too short, over the length cap).
inline bool unpackTextToolData(const void* data, size_t size, uint32_t& request, uint32_t& tool,
                               std::u16string& text) {
    if (!data || size < 8 || (size - 8) % 2 != 0 || (size - 8) / 2 > kTextToolMaxLength) return false;
    const auto* p = static_cast<const uint8_t*>(data);
    request = 0;
    tool = 0;
    for (int i = 0; i < 4; ++i) {
        request |= static_cast<uint32_t>(p[i]) << (8 * i);
        tool |= static_cast<uint32_t>(p[4 + i]) << (8 * i);
    }
    text.resize((size - 8) / 2);
    for (size_t i = 0; i < text.size(); ++i)
        text[i] = static_cast<char16_t>(p[8 + 2 * i] | (p[9 + 2 * i] << 8));
    return true;
}

}  // namespace vtx
