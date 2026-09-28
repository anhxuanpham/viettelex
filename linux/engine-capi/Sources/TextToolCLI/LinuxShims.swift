// LinuxShims.swift — phần riêng của viettelex-text-tool mà các file dùng chung (symlink
// iOS/Keyboard) cần: nơi đặt dữ liệu (thay Bundle, xem `#if VIETTELEX_CLI` trong
// VNLexicon2/SyllableLM/SwipeEnglish) và `L()` (nhãn TextTool — CLI không hiển thị nhãn).
//
// Trên Linux `import Foundation` = FoundationEssentials (-module-alias, xem Package.swift):
// không Bundle/NSString/folding; Foundation đầy đủ kéo CoreFoundation + ICU (~45 MB) vào
// file chạy tĩnh. Phần thiếu mà mã dùng chung cần nằm cuối file này.
import Foundation
#if os(Linux)
@_spi(_Unicode) import Swift   // String._nfd (chuẩn hoá NFD của stdlib)
import Glibc
#endif

enum VTDataFile {
    /// Thư mục dữ liệu theo thứ tự ưu tiên; file đầu tiên tồn tại thắng.
    static let dirs: [String] = {
        var d: [String] = []
        if let env = ProcessInfo.processInfo.environment["VIETTELEX_DATA_DIR"], !env.isEmpty { d.append(env) }
        // /usr/lib/<triplet>/viettelex/viettelex-text-tool → /usr/share/viettelex
        if let exe = executablePath() {
            var u = URL(fileURLWithPath: exe).deletingLastPathComponent()
            for _ in 0..<3 {
                u = u.deletingLastPathComponent()
                d.append(u.appendingPathComponent("share/viettelex").path)
            }
        }
        d.append("/usr/share/viettelex")
        d.append("/usr/local/share/viettelex")
        return d
    }()

    static func url(_ name: String) -> URL? {
        for dir in dirs {
            let p = dir.hasSuffix("/") ? dir + name : dir + "/" + name
            if FileManager.default.isReadableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    /// Đường dẫn thật (đã giải symlink) của file chạy.
    private static func executablePath() -> String? {
        #if os(Linux)
        guard let p = realpath("/proc/self/exe", nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
        #else
        return Bundle.main.executableURL?.resolvingSymlinksInPath().path
        #endif
    }
}

/// = L10n.t với ngôn ngữ mặc định (TextTool.label — không dùng trong CLI).
func L(_ vi: String) -> String { vi }

#if os(Linux)
/// Foundation đầy đủ re-export Glibc; FoundationEssentials thì không (AddTones dùng `log`).
func log(_ x: Double) -> Double { Glibc.log(x) }

// Ba API NSString mà các file dùng chung cần, FoundationEssentials không có. Chuẩn hoá
// Unicode lấy từ stdlib Swift (cùng dữ liệu Unicode mà String dùng để so sánh);
// replacingOccurrences so khớp theo unicode scalar như NSString (.literal).
// Fixture chung (ctest text_tool_fixtures) canh hành vi.
extension StringProtocol {
    var precomposedStringWithCanonicalMapping: String {
        String(decoding: String(self)._nfcCodeUnits, as: UTF8.self)
    }

    var decomposedStringWithCanonicalMapping: String {
        var v = String.UnicodeScalarView()
        for u in String(self)._nfd { v.append(u) }
        return String(v)
    }

    func replacingOccurrences(of target: String, with replacement: String) -> String {
        String(String(self).unicodeScalars.replacing(target.unicodeScalars, with: replacement.unicodeScalars))
    }
}
#endif
