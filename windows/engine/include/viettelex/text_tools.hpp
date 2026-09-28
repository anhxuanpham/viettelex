// text_tools.hpp — CÔNG CỤ VĂN BẢN (Windows port of iOS/Keyboard/TextTools.swift +
// the Unicode pieces Swift/Kotlin get from the platform): HOA / thường / Hoa Đầu Từ /
// Hoa đầu câu / Xoá dấu, plus NFC/NFD and full Unicode case mapping from generated
// tables (tools/gen_unicode.py). Must give the SAME results as TextTools.swift/.kt on the
// shared fixture iOS/KeyboardTests/Fixtures/text-tools.txt (tests/text_tests.cpp).
//
// Everything works on code points (char32_t) — like the Swift version iterating Unicode
// scalars — never on UTF-16 units. Results are always NFC. Heap use is fine here: these
// run once per user action (tray menu / hotkey), never per keystroke. Not linked into the
// TIP: only VietTelex.exe uses them (library viettelex_text).
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

namespace vtx { namespace text {

// ---- Unicode ------------------------------------------------------------------------
bool isLetter(char32_t c);   // General Category L* (Lu Ll Lt Lm Lo)
bool isMark(char32_t c);     // M* (Mn Mc Me)
bool isDigit(char32_t c);    // Nd
bool isSpace(char32_t c);    // White_Space (the explicit list of TextTools.isSpace)

std::u32string nfd(const std::u32string& s);
std::u32string nfc(const std::u32string& s);
/// Full case mapping of the whole string (SpecialCasing, root locale; lower() applies
/// Final_Sigma). = Swift String.uppercased()/lowercased().
std::u32string upper(const std::u32string& s);
std::u32string lower(const std::u32string& s);
/// One code point, no context (= Swift String(scalar).uppercased()).
std::u32string upper(char32_t c);
std::u32string lower(char32_t c);

// ---- UTF conversions (lenient: a lone surrogate becomes U+FFFD) -----------------------
std::u32string fromUtf16(const char16_t* s, size_t n);
inline std::u32string fromUtf16(const std::u16string& s) { return fromUtf16(s.data(), s.size()); }
std::u16string toUtf16(const std::u32string& s);
std::u32string fromUtf8(const char* s, size_t n);
inline std::u32string fromUtf8(const std::string& s) { return fromUtf8(s.data(), s.size()); }
std::string toUtf8(const std::u32string& s);

// ---- tools --------------------------------------------------------------------------
enum class Tool : int {
    AddTones = 0,        // Thêm dấu (add_tones.hpp — needs the language data)
    Upper = 1,           // HOA
    Lower = 2,           // thường
    Title = 3,           // Hoa Đầu Từ
    Sentence = 4,        // Hoa đầu câu
    StripDiacritics = 5, // Xoá dấu
};
constexpr int kToolCount = 6;
inline bool isValidTool(int v) { return v >= 0 && v < kToolCount; }

std::u32string titleCase(const std::u32string& s);
std::u32string sentenceCase(const std::u32string& s);
std::u32string stripDiacritics(const std::u32string& s);
/// Upper / Lower / Title / Sentence / StripDiacritics on NFC(input); result NFC.
/// Tool::AddTones returns NFC(input) (Thêm dấu needs the data: add_tones.hpp).
std::u32string apply(Tool tool, const std::u32string& text);

}}  // namespace vtx::text
