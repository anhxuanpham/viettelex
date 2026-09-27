import Foundation

/// Một mẫu câu: text đầy đủ + label tuỳ chọn (emoji/chữ ngắn) để bubble trên
/// bàn phím render gọn.
struct TemplateItem: Equatable, Identifiable {
    var label: String
    var text: String
    var id: String { label + "\u{1}" + text }
}

/// Logic THUẦN thêm/sửa mẫu câu (tab Mẫu Câu) — tách khỏi SwiftUI để test được và để
/// mọi lần KHÔNG thêm/sửa được đều có lý do hiển thị cho người dùng (trước đây nút ⊕
/// `return` im lặng khi trùng → người dùng tưởng app hỏng).
enum TemplateEdit {
    enum Rejection: Equatable {
        case emptyText
        /// Trùng câu với dòng `index` (0-based) đã có.
        case duplicate(index: Int)
    }

    enum Outcome: Equatable {
        case ok([TemplateItem])
        case rejected(Rejection)
    }

    /// Chuẩn hoá: bỏ khoảng trắng/xuống dòng hai đầu (label cũng vậy — label gõ
    /// kèm Enter không được lọt "\n" vào bubble).
    static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// So trùng theo câu (label khác không tính). String == của Swift đã so theo
    /// tương đương chính tắc (NFC ≡ NFD) — "đặt" dựng sẵn ≡ "đặt" tổ hợp.
    static func duplicateIndex(of text: String, in items: [TemplateItem], excluding: Int? = nil) -> Int? {
        items.indices.first { $0 != excluding && items[$0].text == text }
    }

    static func add(_ items: [TemplateItem], label: String, text: String) -> Outcome {
        let t = clean(text), l = clean(label)
        guard !t.isEmpty else { return .rejected(.emptyText) }
        if let i = duplicateIndex(of: t, in: items) { return .rejected(.duplicate(index: i)) }
        return .ok(items + [TemplateItem(label: l, text: t)])
    }

    static func update(_ items: [TemplateItem], at index: Int, label: String, text: String) -> Outcome {
        let t = clean(text), l = clean(label)
        guard items.indices.contains(index) else { return .ok(items) }
        guard !t.isEmpty else { return .rejected(.emptyText) }
        if let i = duplicateIndex(of: t, in: items, excluding: index) { return .rejected(.duplicate(index: i)) }
        var out = items
        out[index] = TemplateItem(label: l, text: t)
        return .ok(out)
    }

    /// Câu báo người dùng (tiếng Việt) cho từng lý do từ chối.
    static func message(_ r: Rejection, items: [TemplateItem]) -> String {
        switch r {
        case .emptyText:
            return "Chưa có nội dung mẫu câu — nhập câu vào ô bên phải label."
        case .duplicate(let i):
            let lbl = items.indices.contains(i) && !items[i].label.isEmpty ? " (\(items[i].label))" : ""
            return "Không thêm: mẫu câu này đã có ở dòng \(i + 1)\(lbl)."
        }
    }
}

// Định dạng file mẫu câu (ios-mau-cau.yml bundle + Import/Export) — dùng chung app + test.
extension TemplateEdit {
    /// Flat YAML: `- "label | text"` hoặc `- text`; bỏ comment/dòng trống.
    static func parseYAML(_ text: String) -> [TemplateItem] {
        text.split(separator: "\n").compactMap { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#"), s.hasPrefix("- ") else { return nil }
            s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
                s = String(s.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
            }
            guard !s.isEmpty else { return nil }
            if let r = s.range(of: " | ") {
                let label = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let body = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : TemplateItem(label: label, text: body)
            }
            return TemplateItem(label: "", text: s)
        }
    }

    static func exportYAML(_ items: [TemplateItem]) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }
        return "# VietTelex — mẫu câu (\(items.count))\n"
            + items.map {
                $0.label.isEmpty ? "- \"\(esc($0.text))\""
                                 : "- \"\(esc($0.label)) | \(esc($0.text))\""
            }.joined(separator: "\n") + "\n"
    }
}
