// Gõ tắt — quản lý bảng (tắt → đầy đủ) trong app chứa. Lưu App Group key "shortcuts"
// ([String: String], giống macOS AppState.shortcuts); bàn phím đọc lúc hiện. Nhập/xuất
// YAML phẳng CÙNG định dạng macOS (ShortcutFile) — một file dùng chung Mac/iPhone/Android.
import SwiftUI
import UniformTypeIdentifiers

enum ShortcutStore {
    static let store = UserDefaults(suiteName: "group.com.viettelex")
    static func load() -> [String: String] {
        (store?.dictionary(forKey: ShortcutFile.storeKey) as? [String: String]) ?? [:]
    }
    static func save(_ t: [String: String]) { store?.set(t, forKey: ShortcutFile.storeKey) }
}

/// Dòng trong Tính Năng: bật/tắt + mở trang quản lý.
struct ShortcutsSection: View {
    @AppStorage(ShortcutFile.enabledKey, store: UserDefaults(suiteName: "group.com.viettelex"))
    private var enabled = true
    @State private var count = ShortcutStore.load().count

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gõ tắt")
                    Text("Gõ chữ tắt rồi dấu cách/dấu câu để bung: ko → không, Ko → Không, KO → KHÔNG. ⌫ ngay sau đó trả lại chữ đã gõ.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                ShortcutsView()
            } label: {
                LabeledContent("Bảng gõ tắt", value: count == 0 ? "Trống" : "\(count) mục")
            }
        } header: { Text("Gõ tắt") }
        .onAppear { count = ShortcutStore.load().count }
    }
}

struct ShortcutsView: View {
    @State private var table = ShortcutStore.load()
    @State private var query = ""
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var editingKey: String?
    @State private var editKey = ""
    @State private var editValue = ""
    @State private var notice: String?
    @State private var showImporter = false
    @State private var showExporter = false

    private var rows: [(key: String, value: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return table.keys.sorted().compactMap { k in
            let v = table[k]!
            guard q.isEmpty || k.lowercased().contains(q) || v.lowercased().contains(q) else { return nil }
            return (k, v)
        }
    }

    private func persist() { ShortcutStore.save(table) }

    private func add() {
        let k = newKey.trimmingCharacters(in: .whitespaces)
        let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShortcutTable.isValidKey(k) else { notice = "Chữ tắt không được chứa khoảng trắng."; return }
        guard !v.isEmpty else { return }
        if table[k] != nil { notice = "“\(k)” đã có — chạm dòng đó để sửa."; return }
        table[k] = v
        newKey = ""; newValue = ""; notice = nil
        persist()
    }

    private func commitEdit() {
        guard let old = editingKey else { return }
        let k = editKey.trimmingCharacters(in: .whitespaces)
        let v = editValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShortcutTable.isValidKey(k), !v.isEmpty else { notice = "Chữ tắt không được chứa khoảng trắng."; return }
        if k != old, table[k] != nil { notice = "“\(k)” đã có."; return }
        table.removeValue(forKey: old)
        table[k] = v
        editingKey = nil; notice = nil
        persist()
    }

    var body: some View {
        List {
            Section {
                TextField("Tìm chữ tắt hoặc nội dung…", text: $query)
                    .textInputAutocapitalization(.never)
                ForEach(rows, id: \.key) { row in
                    if editingKey == row.key {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Chữ tắt", text: $editKey)
                                .textInputAutocapitalization(.never)
                            TextField("Nội dung", text: $editValue, axis: .vertical)
                                .lineLimit(1...6)
                            HStack {
                                Button("Lưu") { commitEdit() }
                                    .buttonStyle(.borderless)
                                Spacer()
                                Button("Huỷ") { editingKey = nil }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            editKey = row.key; editValue = row.value; editingKey = row.key
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.key).font(.body.monospaced()).foregroundStyle(.primary)
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                Text(row.value).foregroundStyle(.primary).lineLimit(3)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    let current = rows
                    for i in offsets { table.removeValue(forKey: current[i].key) }
                    persist()
                }
                if table.isEmpty {
                    Text("Chưa có gõ tắt nào. Thêm bên dưới, hoặc bấm “Thêm bộ gợi ý”.")
                        .foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    Text("Không tìm thấy.").foregroundStyle(.secondary)
                }
            } header: { Text("Bảng gõ tắt (\(table.count))") } footer: {
                Text("Chạm một dòng để sửa, vuốt trái để xoá.")
            }

            Section {
                TextField("Chữ tắt (vd: ko, cty, ->)", text: $newKey)
                    .textInputAutocapitalization(.never)
                TextField("Nội dung đầy đủ (được nhiều dòng)", text: $newValue, axis: .vertical)
                    .lineLimit(1...6)
                Button { add() } label: { Label("Thêm", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Thêm mới") } footer: {
                Text("Bung khi gõ dấu cách, Enter hoặc dấu câu ngay sau chữ tắt. Viết chữ tắt thường để tự theo hoa/thường khi gõ. Chữ tắt có ký hiệu hoặc số (->, k2) bung khi gõ dấu cách. Không bung khi dính liền sau số hoặc / # @ (5h, /h3), trong ô mật khẩu, email, URL.")
            }

            Section {
                Button {
                    let missing = ShortcutFile.suggested.filter { table[$0.key] == nil }
                    table.merge(missing) { cur, _ in cur }
                    persist()
                    notice = missing.isEmpty ? "Bộ gợi ý đã có đủ." : "Đã thêm \(missing.count) gõ tắt gợi ý."
                } label: { Label("Thêm bộ gợi ý", systemImage: "sparkles") }
                Button { showImporter = true } label: {
                    Label("Nhập từ file…", systemImage: "square.and.arrow.down")
                }
                .fileImporter(isPresented: $showImporter,
                              allowedContentTypes: [.yaml, .json, .plainText, .text, .data]) { result in
                    guard case .success(let url) = result else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                        notice = "Không đọc được file."
                        return
                    }
                    let imported = ShortcutFile.parse(text)
                    guard !imported.isEmpty else { notice = "File không có gõ tắt nào."; return }
                    let r = ShortcutFile.merge(table, imported)
                    table = r.table
                    persist()
                    notice = "Đã nhập \(imported.count) mục: \(r.added) mới, \(r.replaced) ghi đè."
                }
                Button { showExporter = true } label: {
                    Label("Xuất ra YAML…", systemImage: "square.and.arrow.up")
                }
                .disabled(table.isEmpty)
                .fileExporter(isPresented: $showExporter,
                              document: TemplatesDocument(text: ShortcutFile.exportYAML(table)),
                              contentType: .yaml,
                              defaultFilename: "viettelex-go-tat") { result in
                    if case .success = result { notice = "Đã xuất \(table.count) gõ tắt." }
                }
            } footer: {
                Text("Bộ gợi ý: \(ShortcutFile.suggested.keys.sorted().joined(separator: ", ")). File YAML “chữ tắt: nội dung” dùng chung với VietTelex trên Mac và Android; nhập sẽ gộp (mục trùng lấy theo file).")
            }
        }
        .navigationTitle("Gõ tắt")
        .scrollDismissesKeyboard(.immediately)
    }
}
