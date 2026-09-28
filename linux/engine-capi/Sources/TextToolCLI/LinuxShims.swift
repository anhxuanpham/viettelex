// LinuxShims.swift — phần riêng của viettelex-text-tool mà các file dùng chung (symlink
// iOS/Keyboard) cần: nơi đặt dữ liệu (thay Bundle, xem `#if VIETTELEX_CLI` trong
// VNLexicon2/SyllableLM/SwipeEnglish) và `L()` (nhãn TextTool — CLI không hiển thị nhãn).
import Foundation

enum VTDataFile {
    /// Thư mục dữ liệu theo thứ tự ưu tiên; file đầu tiên tồn tại thắng.
    static let dirs: [String] = {
        var d: [String] = []
        if let env = ProcessInfo.processInfo.environment["VIETTELEX_DATA_DIR"], !env.isEmpty { d.append(env) }
        // /usr/lib/<triplet>/viettelex/viettelex-text-tool → /usr/share/viettelex
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            var u = exe.deletingLastPathComponent()
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
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isReadableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }
}

/// = L10n.t với ngôn ngữ mặc định (TextTool.label — không dùng trong CLI).
func L(_ vi: String) -> String { vi }
