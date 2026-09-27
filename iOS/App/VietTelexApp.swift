// Container app: onboarding + Telex settings (shared with the keyboard via the
// App Group) + a link that opens the Learn site in the browser. Deliberately
// minimal — no WebView, no third-party dependencies (docs/ios-app.md).
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct VietTelexApp: App {
    init() {
        #if DEBUG
        let g = UserDefaults(suiteName: "group.com.viettelex")
        NSLog("DBG kbFullAccess=%d kbLastSeen=%f",
              g?.bool(forKey: "kbFullAccess") ?? false ? 1 : 0,
              g?.double(forKey: "kbLastSeen") ?? -1)
        #endif
    }
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Màu nhấn thích ứng sáng/tối — xanh đậm ở nền sáng (user: .blue vẫn nhạt),
/// xanh sáng hơn ở nền tối để chữ trắng vẫn nổi rõ.
let accentBlue = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(red: 0.30, green: 0.52, blue: 1.00, alpha: 1)
        : UIColor(red: 0.02, green: 0.32, blue: 0.84, alpha: 1)
})

/// Bàn phím VietTelex đã được bật trong Cài đặt chưa — quét danh sách bàn phím
/// đang hoạt động tìm bundle id của extension.
func isKeyboardEnabled() -> Bool {
    UITextInputMode.activeInputModes.contains {
        ($0.value(forKey: "identifier") as? String)?
            .hasPrefix("com.viettelex.ios.keyboard") == true
    }
}

/// Các tab của app — floating menu kiểu iOS ở đáy (user 2026-07-24).
/// Tab Mẫu Câu chỉ hiện khi bật tính năng trong Tính Năng → Gợi ý.
enum AppTab: CaseIterable {
    case kieuGo, tinhNang, mauCau, gioiThieu
    var title: String {
        switch self {
        case .kieuGo: return "Kiểu Gõ"
        case .tinhNang: return "Tính Năng"
        case .mauCau: return "Mẫu Câu"
        case .gioiThieu: return "Giới Thiệu"
        }
    }
    var icon: String {
        switch self {
        case .kieuGo: return "keyboard"
        case .tinhNang: return "slider.horizontal.3"
        case .mauCau: return "text.quote"
        case .gioiThieu: return "info.circle"
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardEnabled = isKeyboardEnabled()
    @State private var pasteReady = Self.readPasteReady()
    /// Đọc thẳng App Group (bàn phím ghi từ process khác — @AppStorage không chắc
    /// nhận thay đổi chéo process), làm mới mỗi lần app active.
    static func readPasteReady() -> Bool {
        let d = UserDefaults(suiteName: "group.com.viettelex")
        return d?.bool(forKey: "kbFullAccess") == true && d?.bool(forKey: "pasteNoPrompt") == true
    }
    @State private var tryItText = ""
    @State private var tab: AppTab = .kieuGo
    @State private var barCollapsed = false
    /// Bàn phím đang hiện → ẩn FloatingTabBar: overlay đáy bị iOS đẩy lên theo bàn
    /// phím và đè đúng dải khung "kính" phía trên bàn phím (host vẽ) → thanh gợi ý
    /// trông như bị cắt (user 25/09/2026).
    @State private var keyboardShown = false
    @AppStorage("templatesEnabled", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var templatesEnabled = true

    private var visibleTabs: [AppTab] {
        templatesEnabled ? AppTab.allCases
                         : AppTab.allCases.filter { $0 != .mauCau }
    }

    /// "1.0.0 · build 24/07/2026" — ngày build = mtime của binary.
    static var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let exe = (Bundle.main.executableURL ?? Bundle.main.bundleURL).path
        let date = (try? FileManager.default.attributesOfItem(atPath: exe)[.modificationDate]) as? Date ?? Date()
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        return "\(v) · build \(f.string(from: date))"
    }

    // Bar tự chế nổi THẬT trên content (user 2026-07-24): system tab bar
    // reserve nguyên dải đáy — hai bên pill lộ nền list thành 2 khối chắn.
    // Overlay + contentMargins để content cuộn xuyên dưới capsule glass.
    var body: some View {
        NavigationStack {
            List {
                switch tab {
                case .kieuGo: kieuGoTab
                case .tinhNang: TinhNangSections(); RiengTuSection()
                case .mauCau: MauCauSections()
                case .gioiThieu: gioiThieuTab
                }
            }
            .navigationTitle(tab == .kieuGo ? "VietTelex" : tab.title)
            .bottomBarScrollMargin()
            .collapseBarOnScroll($barCollapsed)
            // Ô "Thử gõ": cuộn là đóng bàn phím. KHÔNG gắn TapGesture lên List —
            // nó nuốt tap của mọi Button trong row (+, Import, Export, Xóa từ đã học…).
            .scrollDismissesKeyboard(.immediately)
        }
        .overlay(alignment: .bottom) {
            if !keyboardShown {
                FloatingTabBar(selected: $tab, tabs: visibleTabs, collapsed: barCollapsed)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .onChange(of: scenePhase) { phase in
            // Quay lại từ Cài đặt → cập nhật trạng thái bật bàn phím ngay.
            if phase == .active {
                keyboardEnabled = isKeyboardEnabled()
                pasteReady = Self.readPasteReady()
                // Plus: đọc entitlement đã verify → cờ App Group cho bàn phím.
                Task { await PlusShared.model.refreshEntitlements() }
                ICloudSync.shared.start()          // tắt ⇒ không làm gì
            } else if phase == .background {
                ICloudSync.shared.syncNow()        // đẩy thay đổi vừa sửa lên iCloud
            }
        }
        .onChange(of: templatesEnabled) { on in
            if !on && tab == .mauCau { tab = .tinhNang }
        }
        // Bubble ⚙️ trên bàn phím → viettelex://maucau → nhảy thẳng tab Mẫu Câu.
        .onOpenURL { url in
            guard url.scheme == "viettelex" else { return }
            if url.host == "maucau" {
                templatesEnabled = true   // user chủ động mở từ keyboard
                tab = .mauCau
            }
        }
    }

    @ViewBuilder private var kieuGoTab: some View {
        Section {
            OnboardingCard(enabled: keyboardEnabled, pasteReady: pasteReady)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            // KHÔNG .autocorrectionDisabled(): bàn phím coi ô autocorrection == .no là
            // ô mã/username → passthrough (literal, tắt Telex) — ô thử gõ mất tác dụng
            // (log Debug mode 25/09/2026: composing=0 mọi phím).
            TextField("Thử gõ tại đây…", text: $tryItText, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
        } header: { Text("Thử gõ") } footer: {
            Text("Bấm 🌐 dưới bàn phím để chuyển sang Tiếng Việt (VietTelex), rồi gõ thử: vieejt → việt.")
        }
        KieuGoSection()
    }

    @ViewBuilder private var gioiThieuTab: some View {
        SaoLuuSection()
        DebugSection()
        // Logo + tên app trên đầu tab (user 2026-07-24), như About của macOS.
        Section {
            VStack(spacing: 10) {
                if let icon = vtAppIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                } else {
                    Text("⌨️").font(.system(size: 64))
                }
                Text("VietTelex").font(.title2.bold())
                Text("Bàn phím Telex tiếng Việt")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
        Section { PlusEntryRow() }
        Section {
            Link(destination: URL(string: "https://ptrinh.github.io/viettelex/")!) {
                Label("Website", systemImage: "globe")
            }
            Link(destination: URL(string: "https://ptrinh.github.io/viettelex/learn/")!) {
                Label("Học gõ Telex", systemImage: "graduationcap")
            }
            Link(destination: URL(string: "https://github.com/ptrinh/viettelex")!) {
                Label("Mã nguồn trên GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: { Text("Tài nguyên") }
        Section {
            LabeledContent("Phiên bản", value: Self.versionLine)
            HStack {
                Text(verbatim: "© Phil Trinh \(String(Calendar.current.component(.year, from: Date())))")
                Spacer()
                Link("vt@trinh.uk", destination: URL(string: "mailto:vt@trinh.uk")!)
                    .foregroundStyle(accentBlue)
            }
            .font(.footnote).foregroundStyle(.secondary)
            Text("Không thu thập dữ liệu · Không theo dõi · Mã nguồn mở")
                .font(.footnote).foregroundStyle(.secondary)
            // Ghi công theo giấy phép dữ liệu bigram gõ vuốt (vnbigram.bin) — docs/DATA-SOURCES.md
            Link(destination: URL(string: "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md")!) {
                Text("Dữ liệu gõ vuốt: thống kê từ Wikipedia, Wikisource… tiếng Việt (CC BY-SA 4.0) và Tatoeba (CC BY 2.0 FR)")
                    .multilineTextAlignment(.leading)
            }
            .font(.footnote).foregroundStyle(.secondary)
            Text("Toàn quyền Truy cập là tuỳ chọn — chỉ cần cho Rung phím và Mẫu câu động (https://); VietTelex không dùng quyền này cho bất kỳ việc gì khác.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Giới thiệu") }
    }
}

/// Thanh tab nổi Liquid Glass tự chế: capsule ôm đúng nội dung, content cuộn
/// xuyên bên dưới. iOS 26 dùng glassEffect thật (khúc xạ + interactive);
/// iOS cũ fallback material + viền specular. Pill chọn morph bằng
/// matchedGeometryEffect + spring.
struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var tabs: [AppTab] = AppTab.allCases
    /// Cuộn xuống → thu về icon-only (mô phỏng minimize của system bar);
    /// cuộn lên → bung lại đủ label.
    var collapsed = false
    @Namespace private var pillNS

    private var buttons: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selected = t
                    }
                } label: {
                    // Icon TRÊN text (user 2026-07-24): 4 tab nằm ngang mà
                    // icon+label cùng hàng thì bar dài quá bề ngang màn hình.
                    VStack(spacing: 2) {
                        Image(systemName: t.icon).font(.subheadline.weight(.medium))
                        if !collapsed {
                            Text(t.title).font(.caption2.weight(.semibold))
                                .lineLimit(1).fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, collapsed ? 11 : 12)
                    .padding(.vertical, collapsed ? 9 : 6)
                    .foregroundStyle(selected == t ? Color.white : Color.primary)
                    .background {
                        if selected == t {
                            Capsule()
                                .fill(accentBlue)
                                .matchedGeometryEffect(id: "pill", in: pillNS)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                buttons.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                buttons
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.06)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            }
        }
        .padding(.bottom, 8)
    }
}

extension View {
    /// Chừa lối cuộn cho bar nổi: hàng cuối cuộn lên được trên capsule
    /// (iOS 17+; iOS 16 chấp nhận hàng cuối lấp dưới bar một chút).
    @ViewBuilder func bottomBarScrollMargin() -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.bottom, 72, for: .scrollContent)
        } else {
            self
        }
    }

    /// Theo dõi hướng cuộn để thu/bung bar nổi (iOS 18+; máy cũ giữ bar full).
    /// Ngưỡng 3pt lọc rung tay; chỉ thu khi đã cuộn quá 40pt khỏi đỉnh.
    @ViewBuilder func collapseBarOnScroll(_ collapsed: Binding<Bool>) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
                guard abs(new - old) > 3 else { return }
                let want = new > old && new > 40
                if want != collapsed.wrappedValue {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        collapsed.wrappedValue = want
                    }
                }
            }
        } else {
            self
        }
    }

    /// Nền card theo Liquid Glass (iOS 26); iOS cũ giữ material xám nhẹ.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular,
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Nút hành động chính: glass prominent (iOS 26) / borderedProminent (cũ),
    /// cùng tint accentBlue.
    @ViewBuilder func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(accentBlue)
        } else {
            self.buttonStyle(.borderedProminent).tint(accentBlue)
        }
    }
}

/// Tab Mẫu Câu — quản lý câu soạn sẵn cho nút ☰ trên bàn phím
/// (App Group key "userTemplates", mỗi entry ["label": …, "text": …]).
struct MauCauSections: View {
    private static let store = UserDefaults(suiteName: "group.com.viettelex")
    /// Mặc định từ ios-mau-cau.yml bundle theo build — cùng file với keyboard.
    static let bundledDefaults: [TemplateItem] = {
        guard let url = Bundle.main.url(forResource: "ios-mau-cau", withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [TemplateItem(label: "👋", text: "Chào buổi sáng")] }
        return parseYAML(text)
    }()

    static func load() -> [TemplateItem] {
        guard let raw = store?.array(forKey: "userTemplates") as? [[String: String]] else {
            return bundledDefaults
        }
        return raw.compactMap { e in
            guard let t = e["text"], !t.isEmpty else { return nil }
            return TemplateItem(label: e["label"] ?? "", text: t)
        }
    }

    @State private var templates = MauCauSections.load()
    @State private var newLabel = ""
    @State private var newText = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var notice: String?
    @State private var editingIndex: Int?
    @State private var editLabel = ""
    @State private var editText = ""

    /// Báo lý do ở ngay dưới hàng đang thao tác (thêm mới / sửa).
    @State private var addNotice: String?

    /// Lưu dòng đang sửa; rỗng/trùng câu dòng khác → báo lý do, giữ nguyên ô sửa.
    private func commitEdit() {
        guard let i = editingIndex, templates.indices.contains(i) else { editingIndex = nil; return }
        switch TemplateEdit.update(templates, at: i, label: editLabel, text: editText) {
        case .ok(let items):
            templates = items
            editingIndex = nil
            addNotice = nil
            persist()
        case .rejected(let r):
            addNotice = TemplateEdit.message(r, items: templates)
        }
    }

    /// Nút ⊕: thêm, hoặc báo lý do không thêm (trước đây trùng câu → return IM LẶNG).
    private func commitAdd() {
        endEditing()
        switch TemplateEdit.add(templates, label: newLabel, text: newText) {
        case .ok(let items):
            templates = items
            addNotice = "Đã thêm mẫu câu (dòng \(items.count))."
            newLabel = ""; newText = ""
            persist()
        case .rejected(let r):
            addNotice = TemplateEdit.message(r, items: templates)
        }
    }

    /// Chốt chữ đang soạn (marked text của bàn phím) vào binding trước khi đọc ô.
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func persist() {
        Self.store?.set(templates.map { ["label": $0.label, "text": $0.text] },
                        forKey: "userTemplates")
    }

    var body: some View {
        Section {
            ForEach(Array(templates.enumerated()), id: \.element.id) { i, t in
                if editingIndex == i {
                    // Sửa tại chỗ (không dùng sheet/alert — trong List chúng không hiện).
                    VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("👋", text: $editLabel)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                        Divider()
                        TextField("Mẫu câu", text: $editText, axis: .vertical)
                            .lineLimit(1...4)
                        Button { endEditing(); commitEdit() } label: {
                            Image(systemName: "checkmark.circle.fill").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        Button { editingIndex = nil; addNotice = nil } label: {
                            Image(systemName: "xmark.circle").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    if let addNotice, !addNotice.hasPrefix("Đã") {
                        Text(addNotice).font(.footnote).foregroundStyle(.orange)
                    }
                    }
                } else {
                    Button {
                        editLabel = t.label; editText = t.text; editingIndex = i; addNotice = nil
                    } label: {
                        HStack {
                            Text(t.label.isEmpty ? "💬" : t.label).frame(minWidth: 30)
                            Text(t.text).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in
                templates.remove(atOffsets: offsets)
                persist()
            }
            if templates.isEmpty {
                Text("Chưa có mẫu câu nào.").foregroundStyle(.secondary)
            }
        } header: { Text("Mẫu câu (\(templates.count))") } footer: {
            Text("Bấm ☰ trên bàn phím để chèn nhanh. Chạm một dòng để sửa, vuốt trái để xoá. Label (emoji/chữ ngắn) giúp bubble trên bàn phím gọn hơn.")
        }

        Section {
            HStack {
                TextField("👋", text: $newLabel)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                Divider()
                TextField("Thêm mẫu câu…", text: $newText, axis: .vertical)
                    .lineLimit(1...3)
                // KHÔNG .disabled theo newText: chữ đang soạn (marked text) chưa vào
                // binding → nút xám dù ô có chữ; bấm luôn được, lý do báo ở footer.
                Button { commitAdd() } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Thêm mẫu câu")
            }
        } header: { Text("Thêm mới") } footer: {
            if let addNotice {
                Text(addNotice).foregroundStyle(addNotice.hasPrefix("Đã") ? Color.secondary : Color.orange)
            } else {
                Text("Ô nhỏ bên trái là label (không bắt buộc).")
            }
        }

        Section {
            FullAccessNotice(reason: "Mẫu câu động")
        } header: { Text("Mẫu câu động (https://)") } footer: {
            Text("Mẫu có nội dung bắt đầu bằng https:// sẽ fetch dữ liệu NGAY LÚC BẤM và chèn kết quả (tối đa 1000 bytes) — ví dụ 🌐 IP chèn địa chỉ IP hiện tại. Chưa cấp Toàn quyền thì bàn phím không có mạng, bấm sẽ chèn chính URL.")
        }

        Section {
            Button {
                showImporter = true
            } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.yaml, .plainText, .text, .data]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    notice = "Không đọc được file."
                    return
                }
                let imported = Self.parseYAML(text)
                let before = templates.count
                for item in imported
                where !templates.contains(where: { $0.text == item.text }) {
                    templates.append(item)
                }
                persist()
                let added = templates.count - before
                notice = "Đã thêm \(added)/\(imported.count) mẫu"
                    + (imported.count > added ? " (trùng bị bỏ qua)." : ".")
            }
            Button {
                showExporter = true
            } label: { Label("Export ra YAML…", systemImage: "square.and.arrow.up") }
            .fileExporter(isPresented: $showExporter,
                          document: TemplatesDocument(text: Self.exportYAML(templates)),
                          contentType: .yaml,
                          defaultFilename: "viettelex-mau-cau") { result in
                if case .success = result { notice = "Đã export \(templates.count) mẫu." }
            }
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("YAML phẳng, mỗi dòng “- \"👋 | Chào buổi sáng\"” (label | câu) hoặc “- \"câu\"”. Import gộp thêm, không thay thế.")
        }
    }

    static func parseYAML(_ text: String) -> [TemplateItem] { TemplateEdit.parseYAML(text) }
    static func exportYAML(_ items: [TemplateItem]) -> String { TemplateEdit.exportYAML(items) }
}

/// FileDocument tối giản cho export YAML.
struct TemplatesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.yaml, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Icon app từ asset catalog (AppIcon) — đọc tên file icon từ Info.plist.
/// Dùng chung cho OnboardingCard và header tab Giới Thiệu.
let vtAppIcon: UIImage? = {
    guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
          let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
          let files = primary["CFBundleIconFiles"] as? [String],
          let name = files.last else { return nil }
    return UIImage(named: name)
}()

struct OnboardingCard: View {
    let enabled: Bool
    /// Ẩn hướng dẫn Dán khi đã xong cả hai bước: bàn phím báo có Toàn quyền
    /// (kbFullAccess) VÀ lần dán gần nhất iOS không hỏi (pasteNoPrompt).
    var pasteReady = false

    @ViewBuilder private var hero: some View {
        if let icon = vtAppIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Text("⌨️").font(.system(size: 52))
        }
    }

    /// Một dòng checklist: xong = tick xanh, chưa = số thứ tự.
    private func step(_ n: Int, _ title: String, done: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle.fill")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
    }

    /// Tuỳ chọn thêm (user 25/09/2026): nút Dán trên thanh gợi ý cần Toàn quyền, và
    /// iOS hỏi "Allow Paste" MỖI lần trừ khi chọn Cho phép — không có API nào để bàn
    /// phím bên thứ ba dán mà không hỏi (UIPasteControl không vẽ trong extension).
    /// Trang Cài đặt của app chứa CẢ công tắc Toàn quyền (mục Bàn phím) lẫn
    /// "Dán từ ứng dụng khác" → một nút mở thẳng trang đó.
    @ViewBuilder private var pasteSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Để dán nhanh từ thanh gợi ý", systemImage: "doc.on.clipboard")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Bàn phím → VietTelex → bật Cho phép Toàn quyền")
                Text("2. Dán từ ứng dụng khác → chọn Cho phép")
                Text("Nếu chưa thấy mục 2: bấm nút Dán trên bàn phím một lần để iOS hỏi, rồi quay lại đây.")
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Mở Cài đặt VietTelex").font(.subheadline.weight(.semibold))
            }
            // .borderless: nút trong dòng List có nhiều control — kiểu mặc định để cả
            // dòng nuốt chạm, nút "không làm gì" (user 25/09/2026, như "Xem log" cũ).
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    var body: some View {
        VStack(spacing: 14) {
            if enabled {
                // Đã bật — thu gọn, chỉ xác nhận + nhắc thử gõ.
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2).foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bàn phím đã bật").font(.headline)
                        Text("Thử gõ ngay bên dưới.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if !pasteReady { pasteSetup }
            } else {
                hero
                Text("Bật bàn phím VietTelex").font(.title3.bold())
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Bật bàn phím trong Cài đặt", done: enabled)
                    step(2, "Thử gõ ngay bên dưới", done: false)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cài đặt → Cài đặt chung → Bàn phím → Bàn phím")
                        Text("Thêm bàn phím mới… → Tiếng Việt (VietTelex)")
                        Text("Khi gõ, bấm 🌐 để chuyển sang VietTelex")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.leading, 30)
                }
                .font(.subheadline)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Mở Cài đặt").font(.headline).frame(maxWidth: .infinity)
                }
                .prominentGlassButton()
                if !pasteReady { pasteSetup }
            }
        }
        .padding(enabled ? 14 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.vertical, 6)
    }
}

/// Cảnh báo + nút mở Settings cho các tính năng cần Toàn quyền Truy cập
/// (Rung phím, Mẫu câu động https://) — dùng chung.
struct FullAccessNotice: View {
    var reason: String
    // Cờ do keyboard extension ghi vào App Group mỗi lần hiện (kbFullAccess) —
    // app chứa không tự hỏi được iOS về Full Access của extension.
    @State private var state = FullAccessNotice.check()

    /// granted: hasFullAccess extension báo về lần chạy gần nhất.
    /// kbSeen: bàn phím đã chạy bản có heartbeat ít nhất một lần chưa —
    /// chưa chạy thì cờ granted không có ý nghĩa.
    static func check() -> (granted: Bool, kbSeen: Bool) {
        guard let g = UserDefaults(suiteName: "group.com.viettelex") else {
            return (false, false)
        }
        return (g.bool(forKey: "kbFullAccess"),
                g.double(forKey: "kbLastSeen") > 0)
    }

    var body: some View {
        Group {
            if state.granted {
                Label {
                    Text("Đã cấp Toàn quyền Truy cập.")
                        .font(.footnote).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                notice
                if !state.kbSeen {
                    Text("Nếu đã bật rồi: mở bàn phím VietTelex một lần (gõ ở app bất kỳ) để app nhận trạng thái quyền.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        // Refresh khi view hiện lại (đổi tab) và khi quay lại từ
        // Settings/bàn phím — cờ chỉ đổi ngoài app.
        .onAppear { state = Self.check() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            state = Self.check()
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("\(reason) cần Toàn quyền Truy cập. Bật trong Cài đặt → Bàn phím → Cho phép Toàn quyền Truy cập. VietTelex không thu thập dữ liệu.")
                    .font(.footnote).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Mở Cài đặt để cấp Toàn quyền")
                    .font(.subheadline.weight(.medium))
            }
            // .borderless bắt buộc: Button nằm chung row trong List mà không
            // set style thì List nuốt tap (row nhiều phần tử tương tác).
            .buttonStyle(.borderless)
            .tint(accentBlue)
        }
    }
}

/// Toggle kèm chú giải nhỏ bên dưới tiêu đề — dùng chung cho 2 tab settings.
func settingToggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(caption).font(.footnote).foregroundStyle(.secondary)
        }
    }
    .tint(.green)   // giữ màu toggle hệ thống — .tint(accentBlue) ở TabView lan xuống
}

/// Tab Kiểu Gõ — các tuỳ chọn Telex core (EngineBridge đọc cùng key qua App Group).
struct KieuGoSection: View {
    @AppStorage("freeMarking", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var freeMarking = true
    @AppStorage("simpleTelex", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var simpleTelex = true
    @AppStorage("quickTelex", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var quickTelex = false
    @AppStorage("modernTone", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var modernTone = false
    @AppStorage("autoFixAdjacent", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var autoFixAdjacent = true
    @AppStorage("contextualEnglish", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var contextualEnglish = true
    @AppStorage("teencode", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var teencode = false
    @AppStorage("vniMode", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var vniMode = false
    @AppStorage("numberRow", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var numberRow = false

    var body: some View {
        Section {
            // Telex / VNI loại trừ nhau → segmented (như radio macOS). Chọn VNI TỰ BẬT hàng
            // phím số (số là phím dấu — không có hàng số thì mỗi dấu phải chuyển plane 123);
            // tắt lại được ở Tính năng → Giao diện.
            Picker("Kiểu gõ", selection: Binding(
                get: { vniMode ? "vni" : "telex" },
                set: { v in
                    let vni = v == "vni"
                    if vni, !vniMode { numberRow = true }
                    vniMode = vni
                })) {
                Text("Telex").tag("telex")
                Text("VNI").tag("vni")
            }
            .pickerStyle(.segmented)
            if vniMode {
                Text("Gõ dấu bằng số khi đang gõ một từ: 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng, 6 mũ (â ê ô), 7 móc (ơ ư), 8 trăng (ă), 9 đ, 0 xoá dấu — tie6ng1 vie6t5 → tiếng việt. Ngoài từ, phím số vẫn gõ ra số. Chọn VNI tự bật Hàng phím số (tắt được ở Tính năng → Giao diện).")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                settingToggle("Telex đơn giản", "Phím w đứng lẻ giữ nguyên là w, không thành ư.", isOn: $simpleTelex)
                settingToggle("Bỏ dấu tự do", "Phím dấu đặt đâu cũng được, không cần đúng thứ tự.", isOn: $freeMarking)
                settingToggle("Gõ nhanh (Quick Telex)", "Phụ âm đôi đầu từ thành phụ âm ghép: cc → ch, nn → ng, tt → th…", isOn: $quickTelex)
            }
            settingToggle("Bỏ dấu kiểu mới", "hoà, thuý thay vì hòa, thúy.", isOn: $modernTone)
            settingToggle("Quyết định theo ngữ cảnh", "Sau một từ tiếng Anh, từ nhập nhằng kế tiếp mà chuỗi phím tạo thành một từ tiếng Anh sẽ được giữ tiếng Anh thay vì tiếng Việt — “he is” → “he is”, không phải “he í”. Sau từ tiếng Việt hoặc không rõ thì để tiếng Việt — “sao í”.", isOn: $contextualEnglish)
            settingToggle("Gợi ý sửa lỗi chạm trượt", "Khi từ đang gõ không phải tiếng Việt, gợi ý từ đúng nếu bạn lỡ chạm phím bên cạnh: nbjeeuf → nhiều, ohims → phím, cahcs → cách. Chạm gợi ý để thay.", isOn: $autoFixAdjacent)
            if !vniMode {
                settingToggle("Chính tả teencode", "Chấp nhận cách viết khi chat: w/z/k thay cho qu/d/c (wá, zui zẻ, kó) và bíe, thík, gòy, ừk. Tắt = chỉ chính tả chuẩn, từ tiếng Anh như was, war, zoo giữ nguyên.", isOn: $teencode)
            }
        } header: { Text("Kiểu gõ") } footer: {
            Text("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")
        }
    }
}

/// Tab Tính Năng — Chính tả, Gợi ý, Giao diện.
struct TinhNangSections: View {
    @AppStorage("liveSpellCheck", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var liveSpellCheck = true
    @AppStorage("autoRestore", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var autoRestore = true
    @AppStorage("showSpaceLogo", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var showSpaceLogo = true
    @AppStorage("showSuggestions", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var showSuggestions = true
    @AppStorage("filterSensitive", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var filterSensitive = true
    // Công tắc phụ của thanh gợi ý (KeyboardSettings) — tắt = bàn phím không làm việc đó.
    @AppStorage("emojiSuggest", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var emojiSuggest = true
    @AppStorage("numberChips", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var numberChips = true
    @AppStorage("pasteButton", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var pasteButton = true
    @AppStorage("addTonesChip", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var addTonesChip = false
    @AppStorage("templatesEnabled", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var templatesEnabled = true
    @AppStorage("rowHeightAdjust", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var rowHeightAdjust = 0
    @AppStorage("numberRow", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var numberRow = false
    /// "off" | "left" | "right" — bàn phím đọc lúc hiện (OneHand.resolve).
    @AppStorage("oneHandMode", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var oneHandMode = "off"
    @AppStorage("hapticFeedback", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var hapticFeedback = false
    /// Ô phóng to chữ khi bấm phím — mặc định BẬT (KeyboardView.keyPreviewKey).
    @AppStorage("keyPreviewEnabled", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var keyPreview = true
    @AppStorage("reEditWord", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var reEditWord = true
    @AppStorage("swipeTyping", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var swipeTyping = false
    /// Công tắc con (giai đoạn 3) — mặc định BẬT, xem KeyboardSettings.swipeEnglish.
    @AppStorage("swipeEnglish", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var swipeEnglish = true
    /// Decoder FUTO Swipe (thử nghiệm) — mặc định TẮT, xem KeyboardSettings.swipeFuto.
    @AppStorage("swipeFuto", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var swipeFuto = false
    /// Chọn phím theo ngữ cảnh (thử nghiệm) — mặc định BẬT, xem KeyboardSettings.smartTouch.
    @AppStorage("smartTouch", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var smartTouch = true

    var body: some View {
        Section {
            settingToggle("Tự khôi phục từ tiếng Anh", "Từ không phải tiếng Việt tự trả về như đã gõ (google, github…).", isOn: $autoRestore)
            settingToggle("Kiểm tra chính tả khi gõ", "Ngừng bỏ dấu ngay khi từ không thể là tiếng Việt.", isOn: $liveSpellCheck)
            settingToggle("Sửa dấu từ đã gõ", "Xoá dấu cách ngay sau một từ để gõ tiếp dấu cho từ đó (tháy ␣ ⌫ a → thấy); hoặc đặt con trỏ ngay sau từ rồi gõ phím dấu s f r x j: viêt + j → việt (VNI: số 1–5, 0).", isOn: $reEditWord)
        } header: { Text("Chính tả") }

        ShortcutsSection()

        Section {
            // Thanh gợi ý bật = tự học từ hay dùng (learnWords đi theo, không
            // còn toggle riêng — quyết định 2026-07-24)
            settingToggle("Thanh gợi ý", "Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy).", isOn: $showSuggestions)
            settingToggle("Lọc từ nhạy cảm khỏi gợi ý", "Không chủ động gợi ý từ tục — gõ tay và học vẫn bình thường.", isOn: $filterSensitive)
            if showSuggestions {
                settingToggle("Gợi ý emoji", "Emoji hợp với từ đang gõ (yêu → ❤️).", isOn: $emojiSuggest)
                settingToggle("Chip số", "Sau khi gõ số: đọc thành chữ, định dạng tiền, tính phép tính (2+3 → 5).", isOn: $numberChips)
                settingToggle("Nút Dán", "Vừa copy xong thì thanh gợi ý hiện nút Dán (cần Toàn quyền).", isOn: $pasteButton)
                if PlusGate.isUnlocked(.sentenceDiacritics) {
                    settingToggle("Chip “Thêm dấu”", "Sau dấu cách, nếu câu vừa gõ không dấu thì hiện chip “Thêm dấu” — một chạm thêm dấu cả câu. Tắt mặc định: bàn phím phải đọc lại câu ở mỗi dấu cách.", isOn: $addTonesChip)
                }
            }
            settingToggle("Mẫu câu", "Nút ☰ trên bàn phím chèn nhanh câu soạn sẵn — quản lý ở tab Mẫu Câu.", isOn: $templatesEnabled)
            NavigationLink {
                UserDictView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Từ điển cá nhân")
                    Text("Xem, tìm, xoá từ đã học; thêm tên riêng, thuật ngữ.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Xóa từ đã học", role: .destructive) {
                // Xoá file + đổi mốc userlmResetAt ⇒ bàn phím bỏ bảng trong RAM lần hiện kế tiếp.
                UserDictStore.eraseAll()
            }
        } header: { Text("Gợi ý") }

        Section {
            NavigationLink {
                ThemeSettingsView()
            } label: {
                Label("Theme & ảnh nền", systemImage: "paintpalette")
            }
            settingToggle("Hiện logo Vᴛ", "Logo mờ ở góc phải phím space.", isOn: $showSpaceLogo)
            settingToggle("Phóng to chữ khi bấm", "Ô chữ lớn nổi lên trên phím vừa chạm (như iPhone). Tắt cho gọn và nhẹ máy hơn.", isOn: $keyPreview)
            settingToggle("Rung phím", "Rung nhẹ mỗi lần chạm phím.", isOn: $hapticFeedback)
            if hapticFeedback {
                FullAccessNotice(reason: "Rung phím")
            }
            Stepper(value: $rowHeightAdjust, in: -10...10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chiều cao hàng phím")
                    Text(rowHeightAdjust == 0
                         ? "Chuẩn"
                         : String(format: "%+d pt mỗi hàng (%+d pt cả bàn phím)",
                                  // hàng số cao ¾ hàng chữ ⇒ tổng ×4,75 khi bật
                                  rowHeightAdjust,
                                  Int((Double(rowHeightAdjust) * (numberRow ? 4.75 : 4)).rounded())))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            settingToggle("Hàng phím số", "Thêm hàng 1 2 3 … 0 phía trên hàng chữ — gõ số không cần chuyển sang bàn phím 123. Bàn phím cao thêm khoảng ¾ hàng.", isOn: $numberRow)
            if UIDevice.current.userInterfaceIdiom == .phone {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chế độ một tay")
                    Picker("Chế độ một tay", selection: $oneHandMode) {
                        Text("Tắt").tag("off")
                        Text("Trái").tag("left")
                        Text("Phải").tag("right")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Thu hẹp bàn phím về một bên. Trên bàn phím: giữ lâu nút ☰ (mẫu câu) trên thanh gợi ý để bật/tắt nhanh; nút ở dải trống để đổi bên hoặc thoát.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Giao diện") } footer: {
            Text("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")
        }

        Section {
            settingToggle("Chọn phím thông minh", "Chạm lệch sát mép giữa hai phím thì bàn phím chọn phím hợp với chữ đang gõ (như bàn phím iPhone) — bớt gõ trượt sang phím bên cạnh. Chạm giữa phím luôn ra đúng phím đó; chữ đã gõ không bao giờ bị tự sửa.", isOn: $smartTouch)
            settingToggle("Gõ vuốt", "Vuốt qua các chữ không dấu rồi nhấc tay: v→i→e→t ra “việt”. Gõ tiếp phím dấu (s f r x j) để đổi dấu, ⌫ ngay sau đó xoá cả từ, thanh gợi ý có các cách viết khác. Chỉ trên iPhone; tắt khi dùng VoiceOver và ở ô email/mật khẩu/URL.", isOn: $swipeTyping)
            if swipeTyping {
                settingToggle("Vuốt từ tiếng Anh", "Vuốt ra cả từ tiếng Anh xen trong câu: check, mail, file, meeting… Khi một nét vuốt vừa là từ Việt vừa là từ Anh (the/thế, can/cần), bàn phím ưu tiên tiếng Việt — trừ khi đang gõ tiếng Anh — và luôn để phương án kia trên thanh gợi ý.", isOn: $swipeEnglish)
                settingToggle("Mô hình nơ-ron gõ vuốt", "Thêm mạng nơ-ron nhận dạng nét vuốt (chạy hoàn toàn trên máy) để chấm cùng bộ giải mã hiện có. Tốn thêm khoảng 3 MB bộ nhớ khi bàn phím mở.", isOn: $swipeFuto)
                NavigationLink {
                    SwipePracticeView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Luyện vuốt")
                        Text("Vuốt thử từng từ trên bàn phím mẫu, xem bàn phím đọc đúng bao nhiêu.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                // Ghi công BẮT BUỘC theo FUTO Model Weights License 1.0 ("visible notice …
                // within the product's settings") — Phil 27/09/2026: chỉ hiện ở đây (dưới công
                // tắc, khi đã bật Gõ vuốt), chữ nhỏ mờ. KHÔNG xoá. Xem docs/DATA-SOURCES.md.
                Link(destination: URL(string: "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md#futo-swipe")!) {
                    Text("powered by FUTO Swipe")
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        } header: { Text("Thử nghiệm") } footer: {
            Text("Tính năng đang thử — áp dụng lần mở bàn phím kế tiếp.")
        }
    }
}

/// Debug mode (25/09/2026): lấy log "gõ nhanh rớt chữ" không cần cáp/Console.
/// Bàn phím ghi touchlog.txt vào App Group (cần Full Access). Log hiện NGAY trong
/// section qua một Toggle — Button mở sheet / present UIKit đều "không hiện ra gì"
/// trên máy user (25/09/2026); Toggle trong cùng Form thì chạy chắc chắn.
struct DebugSection: View {
    @AppStorage("debugTouchLog", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var debugTouchLog = false
    @State private var showLog = false
    @State private var logText = ""
    @State private var clearLog = false

    static var logURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.viettelex")?
            .appendingPathComponent("touchlog.txt")
    }
    private func reload() {
        logText = Self.logURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    var body: some View {
        Section {
            settingToggle("Debug mode — ghi log chạm phím",
                          "Ghi thời điểm chạm, độ trễ và số phím vào log trong app — KHÔNG ghi nội dung bạn gõ. Cần \"Cho phép Toàn quyền\" cho bàn phím. Tắt + Xoá log khi xong.",
                          isOn: $debugTouchLog)
            if debugTouchLog {
                settingToggle("Hiện log (tự copy vào clipboard)",
                              "Bật để xem log bên dưới và copy toàn bộ — tắt rồi bật lại để tải log mới.",
                              isOn: $showLog)
                settingToggle("Xoá log", "Bật để xoá log cũ trước khi thử lại.", isOn: $clearLog)
                if showLog {
                    Text(logText.isEmpty
                         ? "Chưa có log. Bật \"Cho phép Toàn quyền\" cho bàn phím VietTelex (Cài đặt → Chung → Bàn phím → Bàn phím → VietTelex), rồi gõ thử."
                         : "\(logText.split(separator: "\n").count) dòng — đã copy vào clipboard.\n\n" + logText.split(separator: "\n").suffix(80).joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } header: { Text("Gỡ lỗi") }
        .onChange(of: showLog) { on in
            guard on else { return }
            reload()
            if !logText.isEmpty { UIPasteboard.general.string = logText }
        }
        .onChange(of: clearLog) { on in
            guard on else { return }
            if let u = Self.logURL { try? FileManager.default.removeItem(at: u) }
            logText = ""
            clearLog = false
        }
    }
}
