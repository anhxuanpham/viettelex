// text_action_logic.h — Công cụ văn bản in VietTelex.exe, the portable decisions
// (unit-tested on any OS). The Win32 flow is app/src/text_actions.cpp; the transforms are
// windows/engine (text_tools.hpp, add_tones.hpp); the TIP side is ime/core/text_tool_ipc.h.
// macOS equivalents: App/Sources/TextActions.swift, TextActionHotkey.swift.
#pragma once
#include <cstddef>
#include <string>

#include <viettelex/add_tones.hpp>
#include <viettelex/text_tools.hpp>

namespace vtx {

// ---- tray menu --------------------------------------------------------------------
// Order of the six tools in the "Công cụ văn bản" submenu (= macOS TextAction order).
constexpr text::Tool kTextToolMenuOrder[text::kToolCount] = {
    text::Tool::AddTones, text::Tool::Upper,    text::Tool::Lower,
    text::Tool::Title,    text::Tool::Sentence, text::Tool::StripDiacritics,
};

// ---- Thêm dấu hotkey (settings addTonesHotkey) -------------------------------------
// RegisterHotKey modifiers (MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_WIN 8). The key is T
// by virtual-key code (layout independent, like macOS's QWERTY-position T).
struct HotkeyChoice {
    const char* id;
    unsigned mods;
    unsigned vk;
    const wchar_t* label;  // nullptr = "off" (localised by the caller)
};
constexpr HotkeyChoice kAddTonesHotkeys[] = {
    {"off", 0, 0, nullptr},
    {"ctrl-alt-t", 0x2 | 0x1, 'T', L"Ctrl+Alt+T"},
    {"ctrl-shift-t", 0x2 | 0x4, 'T', L"Ctrl+Shift+T"},
    {"win-alt-t", 0x8 | 0x1, 'T', L"Win+Alt+T"},
};
constexpr size_t kAddTonesHotkeyCount = sizeof(kAddTonesHotkeys) / sizeof(kAddTonesHotkeys[0]);
// Index into kAddTonesHotkeys; unknown values -> 0 ("off").
size_t addTonesHotkeyIndex(const std::string& id);
// False for "off" / unknown values (nothing to register).
bool addTonesHotkeyKeys(const std::string& id, unsigned& mods, unsigned& vk);

// ---- transform (TextActionTransform.apply) ----------------------------------------------
// `out` = the tool applied to `in`. False when there is nothing to do: empty input, longer
// than kTextToolMaxLength UTF-16 units (a whole document selected by mistake), Thêm dấu
// without language data, or a result identical to the input (scalar by scalar).
bool transformText(text::Tool tool, const std::u16string& in, const addtones::LanguageData* data,
                   std::u16string& out);

// ---- Ctrl+C / Ctrl+V fallback ----------------------------------------------------------
// Consoles and terminals (Ctrl+C = interrupt) and remote/VM viewers (keys go elsewhere)
// never get synthetic Ctrl+C / Ctrl+V. `exe` = normalized exe name (app_policy.h).
bool clipboardFallbackAllowed(const std::string& exe, bool console, const std::string& windowClass);

// Tray path: clicking the notification area makes the TASKBAR the foreground window, so
// the tool must go to the last foreground window that was not a shell surface (taskbar,
// overflow flyout, Start / search). Window class names.
bool isShellSurfaceClass(const std::string& windowClass);

// How a clipboard format is saved for the restore (macOS PasteboardBridge.Snapshot keeps
// every item/type). Global = HGLOBAL bytes (almost everything, incl. registered formats);
// EnhMetafile = CopyEnhMetaFile; Skip = GDI handles / owner-display / private formats
// (CF_BITMAP is re-synthesised by Windows from the saved CF_DIB).
enum class ClipFormatKind { Skip, Global, EnhMetafile };
ClipFormatKind clipboardFormatKind(unsigned format);

}  // namespace vtx
