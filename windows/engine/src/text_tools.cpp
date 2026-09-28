// Port of iOS/Keyboard/TextTools.swift (transforms) + the Unicode services Swift gets
// from Foundation (NFC/NFD, case mapping, General Category) — see text_tools.hpp.
#include "viettelex/text_tools.hpp"

#include <algorithm>

#include "unicode_tables.hpp"

namespace vtx { namespace text {

namespace {

// ---- lookups ------------------------------------------------------------------------

enum CharClass : uint32_t { kOther = 0, kCased = 1, kLetterOther = 2, kMark = 3, kDigit = 4, kIgnorable = 5 };

uint32_t charClass(char32_t c) {
    const uint32_t* a = uni::kClassRanges;
    size_t lo = 0, hi = sizeof(uni::kClassRanges) / sizeof(uni::kClassRanges[0]);
    // last range whose start <= c
    while (hi - lo > 1) {
        size_t mid = (lo + hi) / 2;
        if ((a[mid] >> 3) <= static_cast<uint32_t>(c)) lo = mid;
        else hi = mid;
    }
    return a[lo] & 7u;
}

template <size_t N>
int findCp(const uint32_t (&cps)[N], char32_t c) {
    const uint32_t* p = std::lower_bound(cps, cps + N, static_cast<uint32_t>(c));
    return (p != cps + N && *p == static_cast<uint32_t>(c)) ? static_cast<int>(p - cps) : -1;
}

template <size_t N, size_t M, size_t P>
bool mapped(const uint32_t (&cps)[N], const uint32_t (&off)[M], const uint32_t (&pool)[P], char32_t c,
            std::u32string& out) {
    int i = findCp(cps, c);
    if (i < 0) return false;
    uint32_t o = off[i] >> 3, n = off[i] & 7u;
    for (uint32_t k = 0; k < n; ++k) out.push_back(static_cast<char32_t>(pool[o + k]));
    return true;
}

uint8_t ccc(char32_t c) {
    if (c < 0x300) return 0;
    int i = findCp(uni::kCccCp, c);
    return i < 0 ? 0 : uni::kCccVal[i];
}

// Hangul (UAX #15 §3.12)
constexpr char32_t kSBase = 0xAC00, kLBase = 0x1100, kVBase = 0x1161, kTBase = 0x11A7;
constexpr int kLCount = 19, kVCount = 21, kTCount = 28, kNCount = kVCount * kTCount, kSCount = kLCount * kNCount;

char32_t composePair(char32_t a, char32_t b) {
    if (a >= kLBase && a < kLBase + kLCount && b >= kVBase && b < kVBase + kVCount)
        return kSBase + ((a - kLBase) * kVCount + (b - kVBase)) * kTCount;
    if (a >= kSBase && a < kSBase + kSCount && (a - kSBase) % kTCount == 0 && b > kTBase && b < kTBase + kTCount)
        return a + (b - kTBase);
    if (a >= 0x200000 || b >= 0x200000) return 0;
    const uint64_t key = static_cast<uint64_t>(a) << 21 | b;
    const uint64_t* e = uni::kCompKey + sizeof(uni::kCompKey) / sizeof(uni::kCompKey[0]);
    const uint64_t* p = std::lower_bound(uni::kCompKey, e, key);
    return (p != e && *p == key) ? static_cast<char32_t>(uni::kCompVal[p - uni::kCompKey]) : 0;
}

bool isCased(char32_t c) { return charClass(c) == kCased; }

bool isCaseIgnorable(char32_t c) {
    switch (c) {
        case U'\'': case U'.': case U':': case 0x00B7: case 0x2018: case 0x2019: case 0x2024:
        case 0xFE13: case 0xFE52: case 0xFE55: case 0xFF07: case 0xFF0E: case 0xFF1A: return true;
        default: break;
    }
    const uint32_t k = charClass(c);
    return k == kMark || k == kIgnorable;
}

// Final_Sigma (SpecialCasing): Σ preceded by a cased letter and not followed by one,
// skipping case-ignorable characters either way.
bool finalSigma(const std::u32string& s, size_t i) {
    size_t j = i;
    bool before = false;
    while (j > 0) {
        char32_t c = s[--j];
        if (isCaseIgnorable(c)) continue;
        before = isCased(c);
        break;
    }
    if (!before) return false;
    for (size_t k = i + 1; k < s.size(); ++k) {
        if (isCaseIgnorable(s[k])) continue;
        return !isCased(s[k]);
    }
    return true;
}

bool isApostrophe(char32_t c) { return c == U'\'' || c == 0x2019; }
bool isSentenceEnd(char32_t c) { return c == U'.' || c == U'!' || c == U'?' || c == 0x2026; }
bool isNewline(char32_t c) { return c == U'\n' || c == U'\r' || c == 0x2028 || c == 0x2029; }

}  // namespace

// ---- Unicode ------------------------------------------------------------------------

bool isLetter(char32_t c) {
    const uint32_t k = charClass(c);
    return k == kCased || k == kLetterOther;
}
bool isMark(char32_t c) { return charClass(c) == kMark; }
bool isDigit(char32_t c) { return charClass(c) == kDigit; }

bool isSpace(char32_t c) {
    return (c >= 0x09 && c <= 0x0D) || c == 0x20 || c == 0x85 || c == 0xA0 || c == 0x1680 ||
           (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F ||
           c == 0x3000;
}

std::u32string nfd(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size() + s.size() / 2);
    for (char32_t c : s) {
        if (c >= kSBase && c < kSBase + kSCount) {
            const int si = static_cast<int>(c - kSBase);
            out.push_back(kLBase + si / kNCount);
            out.push_back(kVBase + (si % kNCount) / kTCount);
            if (si % kTCount) out.push_back(kTBase + si % kTCount);
        } else if (c < 0xC0 || !mapped(uni::kDecompCp, uni::kDecompOff, uni::kDecompPool, c, out)) {
            out.push_back(c);
        }
    }
    // canonical ordering: stable sort each run of non-starters by combining class
    for (size_t i = 0; i < out.size();) {
        if (ccc(out[i]) == 0) { ++i; continue; }
        size_t j = i;
        while (j < out.size() && ccc(out[j]) != 0) ++j;
        std::stable_sort(out.begin() + static_cast<std::ptrdiff_t>(i), out.begin() + static_cast<std::ptrdiff_t>(j),
                         [](char32_t a, char32_t b) { return ccc(a) < ccc(b); });
        i = j;
    }
    return out;
}

std::u32string nfc(const std::u32string& s) {
    std::u32string d = nfd(s);
    if (d.empty()) return d;
    // UAX #15 composition (the reference algorithm of the Unicode sample code)
    size_t starterPos = 0, compPos = 1;
    char32_t starter = d[0];
    int lastClass = ccc(starter);
    if (lastClass != 0) lastClass = 256;  // no starter yet: block everything
    for (size_t i = 1; i < d.size(); ++i) {
        const char32_t c = d[i];
        const int cls = ccc(c);
        const char32_t comp = lastClass == 256 ? 0 : composePair(starter, c);
        if (comp && (lastClass < cls || lastClass == 0)) {
            d[starterPos] = comp;
            starter = comp;
            continue;
        }
        if (cls == 0) {
            starterPos = compPos;
            starter = c;
        }
        lastClass = cls;
        d[compPos++] = c;
    }
    d.resize(compPos);
    return d;
}

std::u32string upper(char32_t c) {
    std::u32string out;
    if (!mapped(uni::kUpperCp, uni::kUpperOff, uni::kUpperPool, c, out)) out.push_back(c);
    return out;
}

std::u32string lower(char32_t c) {
    std::u32string out;
    if (!mapped(uni::kLowerCp, uni::kLowerOff, uni::kLowerPool, c, out)) out.push_back(c);
    return out;
}

std::u32string upper(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size());
    for (char32_t c : s)
        if (!mapped(uni::kUpperCp, uni::kUpperOff, uni::kUpperPool, c, out)) out.push_back(c);
    return out;
}

std::u32string lower(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        const char32_t c = s[i];
        if (c == 0x03A3 && finalSigma(s, i)) out.push_back(0x03C2);
        else if (!mapped(uni::kLowerCp, uni::kLowerOff, uni::kLowerPool, c, out)) out.push_back(c);
    }
    return out;
}

// ---- UTF ------------------------------------------------------------------------------

std::u32string fromUtf16(const char16_t* s, size_t n) {
    std::u32string o;
    o.reserve(n);
    for (size_t i = 0; i < n; ++i) {
        char32_t c = s[i];
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] <= 0xDFFF) {
            c = 0x10000 + ((c - 0xD800) << 10) + (s[i + 1] - 0xDC00);
            ++i;
        } else if (c >= 0xD800 && c <= 0xDFFF) {
            c = 0xFFFD;
        }
        o.push_back(c);
    }
    return o;
}

std::u16string toUtf16(const std::u32string& s) {
    std::u16string o;
    o.reserve(s.size());
    for (char32_t c : s) {
        if (c >= 0x10000 && c <= 0x10FFFF) {
            c -= 0x10000;
            o.push_back(static_cast<char16_t>(0xD800 + (c >> 10)));
            o.push_back(static_cast<char16_t>(0xDC00 + (c & 0x3FF)));
        } else if (c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) {
            o.push_back(0xFFFD);
        } else {
            o.push_back(static_cast<char16_t>(c));
        }
    }
    return o;
}

std::u32string fromUtf8(const char* s, size_t n) {
    std::u32string o;
    o.reserve(n);
    for (size_t i = 0; i < n;) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        char32_t cp;
        size_t len;
        if (c < 0x80) { cp = c; len = 1; }
        else if ((c >> 5) == 6) { cp = c & 0x1F; len = 2; }
        else if ((c >> 4) == 14) { cp = c & 0x0F; len = 3; }
        else if ((c >> 3) == 30) { cp = c & 0x07; len = 4; }
        else { o.push_back(0xFFFD); ++i; continue; }
        if (i + len > n) { o.push_back(0xFFFD); break; }
        bool ok = true;
        for (size_t k = 1; k < len; ++k) {
            const unsigned char t = static_cast<unsigned char>(s[i + k]);
            if ((t >> 6) != 2) { ok = false; break; }
            cp = (cp << 6) | (t & 0x3F);
        }
        if (!ok) { o.push_back(0xFFFD); ++i; continue; }
        o.push_back(cp);
        i += len;
    }
    return o;
}

std::string toUtf8(const std::u32string& s) {
    std::string o;
    o.reserve(s.size());
    for (char32_t c : s) {
        if (c < 0x80) o.push_back(static_cast<char>(c));
        else if (c < 0x800) {
            o.push_back(static_cast<char>(0xC0 | (c >> 6)));
            o.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        } else if (c < 0x10000) {
            o.push_back(static_cast<char>(0xE0 | (c >> 12)));
            o.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
            o.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        } else {
            o.push_back(static_cast<char>(0xF0 | (c >> 18)));
            o.push_back(static_cast<char>(0x80 | ((c >> 12) & 0x3F)));
            o.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
            o.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        }
    }
    return o;
}

// ---- tools (TextTools.swift) ----------------------------------------------------------

std::u32string titleCase(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size());
    bool inWord = false;
    for (size_t i = 0; i < s.size(); ++i) {
        const char32_t c = s[i];
        if (isLetter(c) || isDigit(c)) {
            out += inWord ? lower(c) : upper(c);
            inWord = true;
        } else if (isMark(c)) {
            out.push_back(c);
        } else if (isApostrophe(c) && inWord && i + 1 < s.size() && isLetter(s[i + 1])) {
            out.push_back(c);
        } else {
            out.push_back(c);
            inWord = false;
        }
    }
    return out;
}

std::u32string sentenceCase(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size());
    bool capNext = true, pendingEnd = false;
    for (char32_t c : s) {
        if (isLetter(c)) {
            out += capNext ? upper(c) : lower(c);
            capNext = false;
            pendingEnd = false;
        } else if (isDigit(c)) {
            out.push_back(c);
            capNext = false;
            pendingEnd = false;
        } else if (isNewline(c)) {
            out.push_back(c);
            capNext = true;
            pendingEnd = false;
        } else if (isSpace(c)) {
            out.push_back(c);
            if (pendingEnd) capNext = true;
        } else {
            if (isSentenceEnd(c)) pendingEnd = true;
            out.push_back(c);
        }
    }
    return out;
}

std::u32string stripDiacritics(const std::u32string& s) {
    std::u32string out;
    for (char32_t c : nfd(s)) {
        if (c >= 0x0300 && c <= 0x036F) continue;
        if (c == 0x0111) out.push_back(U'd');
        else if (c == 0x0110) out.push_back(U'D');
        else out.push_back(c);
    }
    return out;
}

std::u32string apply(Tool tool, const std::u32string& text) {
    const std::u32string s = nfc(text);
    switch (tool) {
        case Tool::Upper: return nfc(upper(s));
        case Tool::Lower: return nfc(lower(s));
        case Tool::Title: return nfc(titleCase(s));
        case Tool::Sentence: return nfc(sentenceCase(s));
        case Tool::StripDiacritics: return nfc(stripDiacritics(s));
        case Tool::AddTones: break;
    }
    return s;
}

}}  // namespace vtx::text
