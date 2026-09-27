// Tab Giới Thiệu → "Sao lưu & đồng bộ": xuất/nhập file một tệp (JSON, đọc được trên
// Android) + công tắc đồng bộ iCloud (mặc định tắt).
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SaoLuuSection: View {
    @ObservedObject private var sync = ICloudSync.shared
    @AppStorage(ICloudSync.enabledKey, store: UserDefaults(suiteName: BackupStore.appGroupID))
    private var syncEnabled = false
    @AppStorage("backupIncludeLearned", store: UserDefaults(suiteName: BackupStore.appGroupID))
    private var includeLearned = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc = BackupDocument(data: Data())
    @State private var notice: String?

    private static var fileName: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "viettelex-sao-luu-\(f.string(from: Date()))"
    }

    var body: some View {
        Section {
            if ICloudSync.isUnlocked() {
                Toggle(isOn: Binding(get: { syncEnabled },
                                     set: { syncEnabled = $0; sync.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Đồng bộ iCloud")
                        Text(syncCaption).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            settingToggle("Kèm từ đã học khi xuất file",
                          "Từ bàn phím đã học (tần suất gõ) — riêng tư, chỉ bật khi file do chính bạn giữ.",
                          isOn: $includeLearned)
            Button {
                let p = BackupStore.appGroup.snapshot(includeLearned: includeLearned)
                exportDoc = BackupDocument(data: BackupCodec.encode(p))
                showExporter = true
            } label: { Label("Xuất file sao lưu…", systemImage: "square.and.arrow.up") }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                          defaultFilename: Self.fileName) { result in
                if case .success = result { notice = "Đã xuất file sao lưu." }
            }
            Button {
                showImporter = true
            } label: { Label("Nhập file sao lưu…", systemImage: "square.and.arrow.down") }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { notice = "Không đọc được file."; return }
                do {
                    notice = BackupStore.appGroup.apply(try BackupCodec.decode(data))
                    sync.syncNow()
                } catch let e as BackupError {
                    notice = e.message
                } catch { notice = "Không đọc được file." }
            }
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("Sao lưu & đồng bộ") } footer: {
            Text("File sao lưu gồm cài đặt, gõ tắt, mẫu câu (và từ đã học nếu chọn) — mở được trên VietTelex iPhone, iPad và Android. Nhập file: cài đặt theo file, gõ tắt và mẫu câu được gộp thêm.")
        }
    }

    private var syncCaption: String {
        guard syncEnabled else {
            return "Cài đặt, gõ tắt, mẫu câu giống nhau trên mọi máy cùng tài khoản iCloud. Không đồng bộ từ đã học."
        }
        if !sync.iCloudAvailable { return "Máy chưa đăng nhập iCloud — sẽ đồng bộ khi đăng nhập." }
        guard let d = sync.lastSync else { return "Đang chờ đồng bộ…" }
        let f = DateFormatter(); f.dateFormat = "HH:mm dd/MM"
        return "Đồng bộ lần cuối \(f.string(from: d))."
    }
}
