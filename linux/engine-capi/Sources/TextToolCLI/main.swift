// viettelex-text-tool — CÔNG CỤ VĂN BẢN cho vùng chọn trên Linux (Fcitx5 addon / IBus
// engine gọi như process con, y hệt `VietTelex --add-tones` của bản macOS): Thêm dấu, HOA,
// thường, Hoa Đầu Từ, Hoa đầu câu, Xoá dấu.
//
// Logic KHÔNG port: các file .swift cạnh file này là SYMLINK tới iOS/Keyboard (TextTools,
// AddTones + lexicon/LM) — cùng mã với iOS/macOS, cùng fixture chung. Chạy ở process riêng
// nên bảng lexicon/bigram (~1 MB heap) không bao giờ sống trong process bộ gõ.
//
//   viettelex-text-tool <tool>            stdin (UTF-8) → stdout
//       tool = addTones | upper | lower | title | sentence | stripDiacritics
//       exit 0 = đã đổi (stdout = kết quả) · 1 = không đổi / không xử lý · 2 = lỗi dùng/dữ liệu
//   viettelex-text-tool --check-fixtures <text-tools.txt> <add-tones.txt>
//       chạy fixture chung iOS/KeyboardTests/Fixtures (ctest), exit ≠ 0 nếu lệch
//
// Dữ liệu (vnlexicon.bin, vnlm.bin, enlexicon.bin): $VIETTELEX_DATA_DIR, hoặc
// <prefix>/share/viettelex suy từ vị trí file chạy, hoặc /usr/share/viettelex.
import Foundation   // Linux: = FoundationEssentials (xem LinuxShims.swift)
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Trần độ dài vùng chọn (UTF-16) — như TextActionTransform.maxLength của macOS.
let maxLength = 20_000

enum Tool: String, CaseIterable {
    case addTones, upper, lower, title, sentence, stripDiacritics
    var textTool: TextTool? { TextTool(rawValue: rawValue) }
}

/// = TextActionTransform.apply (App/Sources/TextActions.swift): nil = không đổi gì.
func apply(_ tool: Tool, _ text: String) -> String? {
    guard !text.isEmpty, text.utf16.count <= maxLength else { return nil }
    let out: String
    if let t = tool.textTool {
        out = TextTools.apply(t, text)
    } else {
        guard VTDataFile.url("vnlexicon.bin") != nil else { return nil }
        out = AddTones.restore(text.precomposedStringWithCanonicalMapping).text
    }
    guard !out.isEmpty, !out.unicodeScalars.elementsEqual(text.unicodeScalars) else { return nil }
    return out
}

func fail(_ msg: String, _ code: Int32 = 2) -> Never {
    writeAll(2, msg + "\n")
    exit(code)
}

/// Ghi hết `s` (UTF-8) ra fd (1 = stdout, 2 = stderr).
func writeAll(_ fd: Int32, _ s: String) {
    var bytes = Array(s.utf8)[...]
    while !bytes.isEmpty {
        let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n < 0 && errno == EINTR { continue }
        guard n > 0 else { return }
        bytes = bytes.dropFirst(n)
    }
}

/// Đọc hết stdin.
func readStdin() -> [UInt8] {
    var data: [UInt8] = []
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = buf.withUnsafeMutableBytes { read(0, $0.baseAddress, $0.count) }
        if n < 0 && errno == EINTR { continue }
        guard n > 0 else { break }
        data.append(contentsOf: buf[0..<n])
    }
    return data
}

func readFixture(_ path: String) -> [Substring] {
    guard let d = FileManager.default.contents(atPath: path) else { fail("không đọc được \(path)") }
    return String(decoding: d, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        .filter { !$0.hasPrefix("#") }
}

/// Fixture chung (định dạng: xem đầu mỗi file). Trả số ca lệch.
func checkFixtures(textTools: String, addTones: String) -> Int {
    var bad = 0, n = 0
    func decode(_ s: Substring) -> String {
        s.replacingOccurrences(of: "␣", with: " ").replacingOccurrences(of: "⏎", with: "\n")
    }
    for line in readFixture(textTools) {
        let c = line.split(separator: "|", omittingEmptySubsequences: false)
        guard c.count == 3 else { print("dòng fixture lạ: \(line)"); bad += 1; continue }
        let op = c[0].split(separator: "@")
        guard let tool = TextTool(rawValue: String(op[0])) else { print("op lạ: \(c[0])"); bad += 1; continue }
        var input = decode(c[1])
        if op.count > 1 { input = input.decomposedStringWithCanonicalMapping }
        let expected = decode(c[2])
        let got = TextTools.apply(tool, input)
        if !Array(got.unicodeScalars).elementsEqual(Array(expected.unicodeScalars)) {
            print("text-tools \(c[0]) «\(input)» → «\(got)», cần «\(expected)»"); bad += 1
        }
        n += 1
    }
    if n < 140 { print("text-tools: chỉ \(n) ca"); bad += 1 }
    var m = 0
    for line in readFixture(addTones) {
        let p = line.components(separatedBy: "\t")
        guard p.count == 2 else { print("dòng fixture lạ: \(line)"); bad += 1; continue }
        let got = AddTones.restore(p[0]).text
        if got != p[1] { print("add-tones «\(p[0])» → «\(got)», cần «\(p[1])»"); bad += 1 }
        m += 1
    }
    if m < 40 { print("add-tones: chỉ \(m) ca"); bad += 1 }
    if SyllableLM.shared == nil { print("vnlm.bin thiếu/hỏng/lệch vnlexicon"); bad += 1 }
    print("text-tools: \(n) ca, add-tones: \(m) ca, lệch: \(bad)")
    return bad
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--check-fixtures" {
    guard args.count == 3 else { fail("dùng: viettelex-text-tool --check-fixtures <text-tools.txt> <add-tones.txt>") }
    guard VTDataFile.url("vnlexicon.bin") != nil else { fail("thiếu vnlexicon.bin (VIETTELEX_DATA_DIR)") }
    exit(checkFixtures(textTools: args[1], addTones: args[2]) == 0 ? 0 : 1)
}
guard args.count == 1, let tool = Tool(rawValue: args[0]) else {
    fail("dùng: viettelex-text-tool <\(Tool.allCases.map(\.rawValue).joined(separator: "|"))> < vào > ra")
}
let input = String(decoding: readStdin(), as: UTF8.self)
guard let out = apply(tool, input) else { exit(1) }
writeAll(1, out)
exit(0)
