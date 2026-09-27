// Tab Tính Năng (27/09/2026): trang chính là 8 nhóm (icon + tên + tóm tắt trạng thái),
// mỗi nhóm mở một trang con — thay cho danh sách dài mọi công tắc. Ô tìm kiếm trên đầu
// lọc theo tên/từ khoá rồi mở đúng trang. KHÔNG đổi key/mặc định/cổng Plus: các trang con
// đọc/ghi cùng key App Group như trước. Android dùng cùng cấu trúc (ui/FeaturePages.kt).
import SwiftUI
import UIKit

private let featureDefaults = UserDefaults(suiteName: "group.com.viettelex")

/// Các nhóm của tab Tính Năng — cùng thứ tự/tên với Android (FeaturePage.kt).
enum FeaturePage: String, CaseIterable, Identifiable {
    case chinhTa, goiY, goVuot, goTat, phim, giaoDien, riengTu, saoLuu
    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinhTa: return "Chính tả & sửa lỗi"
        case .goiY: return "Gợi ý & từ điển"
        case .goVuot: return "Gõ vuốt"
        case .goTat: return "Gõ tắt & mẫu câu"
        case .phim: return "Phím & cử chỉ"
        case .giaoDien: return "Giao diện"
        case .riengTu: return "Riêng tư & clipboard"
        case .saoLuu: return "Sao lưu & đồng bộ"
        }
    }
    var icon: String {
        switch self {
        case .chinhTa: return "checkmark.seal"
        case .goiY: return "lightbulb"
        case .goVuot: return "hand.draw"
        case .goTat: return "text.quote"
        case .phim: return "keyboard"
        case .giaoDien: return "paintpalette"
        case .riengTu: return "lock"
        case .saoLuu: return "icloud"
        }
    }
    var color: Color {
        switch self {
        case .chinhTa: return .green
        case .goiY: return .orange
        case .goVuot: return .purple
        case .goTat: return .teal
        case .phim: return .gray
        case .giaoDien: return .pink
        case .riengTu: return .indigo
        case .saoLuu: return .blue
        }
    }
    /// Cả nhóm đang thử nghiệm → nhãn nhỏ ngay trên dòng.
    var experimental: Bool { self == .goVuot }
    /// Mục tương ứng trong Hướng dẫn sử dụng (docs/hdsd/index.html).
    var guideAnchor: String {
        switch self {
        case .chinhTa: return "sua-dau"
        case .goiY: return "goi-y"
        case .goVuot: return "go-vuot"
        case .goTat: return "go-tat"
        case .phim: return "cu-chi"
        case .giaoDien: return "giao-dien"
        case .riengTu: return "clipboard"
        case .saoLuu: return "sao-luu"
        }
    }
    var guideURL: URL { URL(string: "https://viettelex.com/hdsd/?os=ios#\(guideAnchor)")! }

    @ViewBuilder var destination: some View {
        switch self {
        case .chinhTa: ChinhTaPage()
        case .goiY: GoiYPage()
        case .goVuot: GoVuotPage()
        case .goTat: GoTatPage()
        case .phim: PhimPage()
        case .giaoDien: ThemeSettingsView()
        case .riengTu: FeaturePageList(page: .riengTu) { RiengTuSection() }
        case .saoLuu: FeaturePageList(page: .saoLuu) { SaoLuuSection() }
        }
    }

    /// Các nhóm hiển thị theo 3 khối như app Cài đặt.
    static let groups: [[FeaturePage]] = [[.chinhTa, .goiY, .goVuot, .goTat], [.phim, .giaoDien], [.riengTu, .saoLuu]]
}

/// Chỉ mục cho ô tìm kiếm: tên cài đặt + từ khoá → trang chứa nó.
struct FeatureSearchEntry: Identifiable {
    let title: String
    let keywords: String
    let page: FeaturePage
    var id: String { page.rawValue + title }

    static var all: [FeatureSearchEntry] {
        var e: [FeatureSearchEntry] = [
            .init(title: "Tự khôi phục từ tiếng Anh", keywords: "english google restore", page: .chinhTa),
            .init(title: "Kiểm tra chính tả khi gõ", keywords: "spell check", page: .chinhTa),
            .init(title: "Sửa dấu từ đã gõ", keywords: "sửa dấu con trỏ backspace", page: .chinhTa),
            .init(title: "Chọn phím thông minh", keywords: "chạm trượt smart touch thử nghiệm", page: .chinhTa),
            .init(title: "Tự sửa từ gõ sai", keywords: "autocorrect sửa lỗi thử nghiệm", page: .chinhTa),
            .init(title: "Thanh gợi ý", keywords: "suggestion học từ", page: .goiY),
            .init(title: "Gợi ý emoji", keywords: "emoji biểu tượng", page: .goiY),
            .init(title: "Chip số", keywords: "số tiền tính phép tính number", page: .goiY),
            .init(title: "Nút Dán", keywords: "paste dán clipboard", page: .goiY),
            .init(title: "Lọc từ nhạy cảm", keywords: "tục chửi filter", page: .goiY),
            .init(title: "Từ điển cá nhân", keywords: "dictionary tên riêng thuật ngữ", page: .goiY),
            .init(title: "Xóa từ đã học", keywords: "xoá học reset", page: .goiY),
            .init(title: "Gõ vuốt", keywords: "swipe vuốt thử nghiệm", page: .goVuot),
            .init(title: "Vuốt từ tiếng Anh", keywords: "swipe english", page: .goVuot),
            .init(title: "Mô hình neural gõ vuốt", keywords: "futo neural swipe", page: .goVuot),
            .init(title: "Luyện vuốt", keywords: "practice swipe", page: .goVuot),
            .init(title: "Gõ tắt", keywords: "shortcut viết tắt", page: .goTat),
            .init(title: "Bảng gõ tắt", keywords: "shortcut yaml import export", page: .goTat),
            .init(title: "Mẫu câu", keywords: "template câu soạn sẵn", page: .goTat),
            .init(title: "Hàng phím số", keywords: "number row số", page: .phim),
            .init(title: "Giữ phím ra ký tự đặc biệt", keywords: "ký hiệu symbol @ # giữ lâu", page: .phim),
            .init(title: "Vuốt phím cách đổi Tiếng Việt / Tiếng Anh", keywords: "space ngôn ngữ english language", page: .phim),
            .init(title: "Phóng to chữ khi bấm", keywords: "key preview popup", page: .phim),
            .init(title: "Rung phím", keywords: "haptic rung vibrate", page: .phim),
            .init(title: "Theme & ảnh nền", keywords: "theme màu chủ đề wallpaper hình nền", page: .giaoDien),
            .init(title: "Độ trong suốt phím", keywords: "trong suốt transparent", page: .giaoDien),
            .init(title: "Độ trong suốt ký tự", keywords: "trong suốt transparent chữ", page: .giaoDien),
            .init(title: "Khôi phục giao diện gốc", keywords: "reset mặc định", page: .giaoDien),
            .init(title: "Chiều cao hàng phím", keywords: "height cao thấp", page: .giaoDien),
            .init(title: "Hiện logo Vᴛ", keywords: "logo phím cách", page: .giaoDien),
            .init(title: "Lịch sử clipboard", keywords: "copy dán clipboard", page: .riengTu),
            .init(title: "Chế độ ẩn danh", keywords: "incognito riêng tư", page: .riengTu),
            .init(title: "Xuất / nhập file sao lưu", keywords: "backup export import restore", page: .saoLuu),
        ]
        if UIDevice.current.userInterfaceIdiom == .phone {
            e.append(.init(title: "Giữ phím hàng trên để ra số", keywords: "số giữ lâu number", page: .phim))
            e.append(.init(title: "Chế độ một tay", keywords: "one hand một tay", page: .phim))
        }
        if PlusGate.isUnlocked(.sentenceDiacritics) {
            e.append(.init(title: "Chip “Thêm dấu”", keywords: "thêm dấu câu không dấu plus", page: .goiY))
        }
        if ICloudSync.isUnlocked() {
            e.append(.init(title: "Đồng bộ iCloud", keywords: "sync icloud đồng bộ", page: .saoLuu))
        }
        return e
    }

    /// So khớp không phân biệt hoa/thường và dấu (gõ "trong suot" vẫn ra).
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func search(_ query: String) -> [FeatureSearchEntry] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let pageHits = FeaturePage.allCases.map {
            FeatureSearchEntry(title: $0.title, keywords: "", page: $0)
        }
        return (pageHits + all).filter { e in
            let hay = fold(e.title + " " + e.keywords)
            return words.allSatisfy { hay.contains($0) }
        }
    }
}

/// Nhãn nhỏ "Thử nghiệm" cạnh tên cài đặt.
struct ExperimentalBadge: View {
    var body: some View {
        Text("Thử nghiệm")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.purple.opacity(0.15)))
            .foregroundStyle(.purple)
    }
}

/// Toggle có nhãn "Thử nghiệm" (cùng kiểu settingToggle).
func experimentalToggle(_ title: String, _ caption: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { Text(title); ExperimentalBadge() }
            Text(caption).font(.footnote).foregroundStyle(.secondary)
        }
    }
    .tint(.green)
}

/// Ô icon màu kiểu app Cài đặt.
struct FeatureIcon: View {
    let page: FeaturePage
    var body: some View {
        Image(systemName: page.icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(page.color))
    }
}

/// Dòng "Tìm hiểu thêm" cuối mỗi trang con.
struct GuideLinkSection: View {
    let page: FeaturePage
    var body: some View {
        Section {
            Link(destination: page.guideURL) {
                Label("Tìm hiểu thêm trong Hướng dẫn", systemImage: "book")
            }
        } footer: {
            Text("Cài đặt áp dụng ngay lần mở bàn phím kế tiếp.")
        }
    }
}

/// Khung trang con: List + tiêu đề inline + link Hướng dẫn + chừa lối cho bar nổi.
struct FeaturePageList<Content: View>: View {
    let page: FeaturePage
    @ViewBuilder var content: Content
    var body: some View {
        List {
            content
            GuideLinkSection(page: page)
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarScrollMargin()
    }
}

// ============================================================== Trang chính

/// Tab Tính Năng — ô tìm kiếm + các nhóm kèm tóm tắt trạng thái hiện tại.
struct TinhNangSections: View {
    @State private var query = ""
    @State private var shortcutCount = ShortcutStore.load().count
    @State private var theme = ThemeSettings.load(featureDefaults)

    // Chỉ để dựng dòng tóm tắt — trang con ghi, @AppStorage tự cập nhật.
    @AppStorage("autoRestore", store: featureDefaults) private var autoRestore = true
    @AppStorage("liveSpellCheck", store: featureDefaults) private var liveSpellCheck = true
    @AppStorage("reEditWord", store: featureDefaults) private var reEditWord = true
    @AppStorage("autoCorrect", store: featureDefaults) private var autoCorrect = false
    @AppStorage("showSuggestions", store: featureDefaults) private var showSuggestions = true
    @AppStorage("emojiSuggest", store: featureDefaults) private var emojiSuggest = true
    @AppStorage("numberChips", store: featureDefaults) private var numberChips = true
    @AppStorage("swipeTyping", store: featureDefaults) private var swipeTyping = false
    @AppStorage("swipeEnglish", store: featureDefaults) private var swipeEnglish = true
    @AppStorage("swipeFuto", store: featureDefaults) private var swipeFuto = false
    @AppStorage(ShortcutFile.enabledKey, store: featureDefaults) private var shortcutsEnabled = true
    @AppStorage("templatesEnabled", store: featureDefaults) private var templatesEnabled = true
    @AppStorage("numberRow", store: featureDefaults) private var numberRow = false
    @AppStorage("spaceSwipeLanguage", store: featureDefaults) private var spaceSwipeLanguage = false
    @AppStorage("hapticFeedback", store: featureDefaults) private var hapticFeedback = false
    @AppStorage("oneHandMode", store: featureDefaults) private var oneHandMode = "off"
    @AppStorage("clipboardHistory", store: featureDefaults) private var clipboardHistory = false
    @AppStorage("incognitoMode", store: featureDefaults) private var incognitoMode = false
    @AppStorage(ICloudSync.enabledKey, store: featureDefaults) private var iCloudSync = false

    private static func join(_ parts: [(Bool, String)], none: String) -> String {
        let on = parts.filter(\.0).map(\.1)
        return on.isEmpty ? none : on.joined(separator: " · ")
    }

    private func summary(_ p: FeaturePage) -> String {
        switch p {
        case .chinhTa:
            return Self.join([(autoRestore, "Khôi phục tiếng Anh"), (liveSpellCheck, "Kiểm tra chính tả"),
                              (reEditWord, "Sửa dấu"), (autoCorrect, "Tự sửa")], none: "Đang tắt")
        case .goiY:
            guard showSuggestions else { return "Tắt thanh gợi ý" }
            return Self.join([(true, "Thanh gợi ý"), (emojiSuggest, "Emoji"), (numberChips, "Chip số")], none: "")
        case .goVuot:
            guard swipeTyping else { return "Đang tắt" }
            return Self.join([(true, "Bật"), (swipeEnglish, "Tiếng Anh"), (swipeFuto, "Neural")], none: "")
        case .goTat:
            let st = shortcutsEnabled ? (shortcutCount == 0 ? "Gõ tắt bật" : "Gõ tắt: \(shortcutCount) mục") : "Gõ tắt tắt"
            return st + " · Mẫu câu " + (templatesEnabled ? "bật" : "tắt")
        case .phim:
            return Self.join([(numberRow, "Hàng số"), (spaceSwipeLanguage, "Vuốt phím cách"),
                              (hapticFeedback, "Rung"), (oneHandMode != "off", "Một tay")], none: "Mặc định")
        case .giaoDien:
            let wp = theme.wallpaperActive(fileExists: Wallpaper.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            return theme.effectiveTheme.title + (wp ? " · Ảnh nền" : "")
                + (theme.keyboardTransparency > 0 || theme.labelTransparency > 0 ? " · Trong suốt" : "")
        case .riengTu:
            return "Lịch sử clipboard " + (clipboardHistory ? "bật" : "tắt") + (incognitoMode ? " · Ẩn danh" : "")
        case .saoLuu:
            return iCloudSync && ICloudSync.isUnlocked() ? "Đồng bộ iCloud bật" : "Xuất / nhập file"
        }
    }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                // KHÔNG .autocorrectionDisabled(): bàn phím VietTelex coi ô đó là ô mã → tắt Telex.
                TextField("Tìm cài đặt…", text: $query)
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Xoá tìm kiếm")
                }
            }
            .onAppear {
                // Quay về từ trang con → làm mới các giá trị không phải @AppStorage.
                shortcutCount = ShortcutStore.load().count
                theme = ThemeSettings.load(featureDefaults)
            }
        }

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ForEach(Array(FeaturePage.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { p in
                        NavigationLink { p.destination } label: { row(p, subtitle: summary(p)) }
                    }
                }
            }
        } else {
            let hits = FeatureSearchEntry.search(query)
            Section {
                if hits.isEmpty {
                    Text("Không tìm thấy cài đặt nào.").foregroundStyle(.secondary)
                }
                ForEach(hits) { e in
                    NavigationLink { e.page.destination } label: {
                        row(e.page, title: e.title, subtitle: e.title == e.page.title ? summary(e.page) : e.page.title)
                    }
                }
            } header: { Text("Kết quả") }
        }
    }

    private func row(_ p: FeaturePage, title: String? = nil, subtitle: String) -> some View {
        HStack(spacing: 12) {
            FeatureIcon(page: p)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title ?? p.title)
                    if p.experimental && title == nil { ExperimentalBadge() }
                }
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// ============================================================== Trang con

struct ChinhTaPage: View {
    @AppStorage("autoRestore", store: featureDefaults) private var autoRestore = true
    @AppStorage("liveSpellCheck", store: featureDefaults) private var liveSpellCheck = true
    @AppStorage("reEditWord", store: featureDefaults) private var reEditWord = true
    /// Thử nghiệm — mặc định BẬT, xem KeyboardSettings.smartTouch.
    @AppStorage("smartTouch", store: featureDefaults) private var smartTouch = true
    /// Thử nghiệm — mặc định TẮT, xem KeyboardSettings.autoCorrect.
    @AppStorage("autoCorrect", store: featureDefaults) private var autoCorrect = false

    var body: some View {
        FeaturePageList(page: .chinhTa) {
            Section {
                settingToggle("Tự khôi phục từ tiếng Anh", "Từ không phải tiếng Việt trả về như đã gõ (google, github…).", isOn: $autoRestore)
                settingToggle("Kiểm tra chính tả khi gõ", "Ngừng bỏ dấu khi từ không thể là tiếng Việt.", isOn: $liveSpellCheck)
                settingToggle("Sửa dấu từ đã gõ", "⌫ ngay sau dấu cách để sửa tiếp từ vừa gõ (tháy ␣ ⌫ a → thấy), hoặc đặt con trỏ sau từ rồi gõ phím dấu: viêt + j → việt.", isOn: $reEditWord)
            } header: { Text("Chính tả") }
            Section {
                experimentalToggle("Chọn phím thông minh", "Chạm sát mép giữa hai phím thì chọn phím hợp với chữ đang gõ. Chạm giữa phím luôn ra đúng phím đó.", isOn: $smartTouch)
                experimentalToggle("Tự sửa từ gõ sai", "Khi gõ dấu cách, sửa từ lỡ chạm phím kề (tpoi → tôi) nếu chắc chắn. ⌫ ngay sau đó để trả lại chữ gốc.", isOn: $autoCorrect)
            } header: { Text("Chạm trượt") } footer: {
                Text("Gợi ý sửa lỗi chạm trượt (hiện trên thanh gợi ý) nằm ở tab Kiểu Gõ.")
            }
        }
    }
}

struct GoiYPage: View {
    @AppStorage("showSuggestions", store: featureDefaults) private var showSuggestions = true
    @AppStorage("filterSensitive", store: featureDefaults) private var filterSensitive = true
    @AppStorage("emojiSuggest", store: featureDefaults) private var emojiSuggest = true
    @AppStorage("numberChips", store: featureDefaults) private var numberChips = true
    @AppStorage("pasteButton", store: featureDefaults) private var pasteButton = true
    @AppStorage("addTonesChip", store: featureDefaults) private var addTonesChip = false

    var body: some View {
        FeaturePageList(page: .goiY) {
            Section {
                // Thanh gợi ý bật = tự học từ hay dùng (learnWords đi theo — quyết định 2026-07-24).
                settingToggle("Thanh gợi ý", "Gợi ý từ + emoji, tự học từ bạn hay dùng (chỉ trên máy).", isOn: $showSuggestions)
                if showSuggestions {
                    settingToggle("Gợi ý emoji", "Emoji hợp với từ đang gõ (yêu → ❤️).", isOn: $emojiSuggest)
                    settingToggle("Chip số", "Đọc số thành chữ, định dạng tiền, tính nhanh (2+3 → 5).", isOn: $numberChips)
                    settingToggle("Nút Dán", "Vừa copy xong thì hiện nút Dán (cần Toàn quyền).", isOn: $pasteButton)
                    if PlusGate.isUnlocked(.sentenceDiacritics) {
                        settingToggle("Chip “Thêm dấu”", "Câu vừa gõ không dấu → một chạm thêm dấu cả câu. Tắt mặc định cho nhẹ máy.", isOn: $addTonesChip)
                    }
                }
                settingToggle("Lọc từ nhạy cảm", "Không chủ động gợi ý từ tục — gõ tay vẫn bình thường.", isOn: $filterSensitive)
            } header: { Text("Thanh gợi ý") }
            Section {
                NavigationLink {
                    UserDictView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Từ điển cá nhân")
                        Text("Xem, tìm, xoá từ đã học; thêm tên riêng.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("Xóa từ đã học", role: .destructive) {
                    // Xoá file + đổi mốc userlmResetAt ⇒ bàn phím bỏ bảng trong RAM lần hiện kế tiếp.
                    UserDictStore.eraseAll()
                }
            } header: { Text("Từ đã học") }
        }
    }
}

struct GoVuotPage: View {
    @AppStorage("swipeTyping", store: featureDefaults) private var swipeTyping = false
    /// Công tắc con — mặc định BẬT, xem KeyboardSettings.swipeEnglish.
    @AppStorage("swipeEnglish", store: featureDefaults) private var swipeEnglish = true
    /// Decoder FUTO Swipe — mặc định TẮT, xem KeyboardSettings.swipeFuto.
    @AppStorage("swipeFuto", store: featureDefaults) private var swipeFuto = false

    var body: some View {
        FeaturePageList(page: .goVuot) {
            Section {
                experimentalToggle("Gõ vuốt", "Vuốt qua các chữ không dấu rồi nhấc tay: v→i→e→t ra “việt”. Gõ phím dấu ngay sau để đổi dấu, ⌫ xoá cả từ. Chỉ trên iPhone.", isOn: $swipeTyping)
                if swipeTyping {
                    settingToggle("Vuốt từ tiếng Anh", "check, mail, meeting… Nét vừa Việt vừa Anh (the/thế) ưu tiên tiếng Việt, phương án kia ở thanh gợi ý.", isOn: $swipeEnglish)
                    settingToggle("Mô hình neural gõ vuốt", "Mạng neural chạy hoàn toàn trên máy, chấm cùng bộ giải mã. Tốn thêm ~3 MB bộ nhớ.", isOn: $swipeFuto)
                    // Ghi công BẮT BUỘC theo FUTO Model Weights License 1.0 ("visible notice …
                    // within the product's settings") — Phil 27/09/2026: chỉ hiện ở đây (dưới công
                    // tắc, khi đã bật Gõ vuốt), chữ nhỏ mờ. KHÔNG xoá. Xem docs/DATA-SOURCES.md.
                    Link(destination: URL(string: "https://github.com/ptrinh/viettelex/blob/main/docs/DATA-SOURCES.md#futo-swipe")!) {
                        Text("powered by FUTO Swipe")
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
            } footer: {
                Text("Tự tắt khi dùng VoiceOver và ở ô email/mật khẩu/URL.")
            }
            if swipeTyping {
                Section {
                    NavigationLink {
                        SwipePracticeView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Luyện vuốt")
                            Text("Vuốt thử từng từ, xem bàn phím đọc đúng bao nhiêu.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct GoTatPage: View {
    @AppStorage("templatesEnabled", store: featureDefaults) private var templatesEnabled = true

    var body: some View {
        FeaturePageList(page: .goTat) {
            ShortcutsSection()
            Section {
                settingToggle("Mẫu câu", "Nút ☰ trên bàn phím chèn câu soạn sẵn — quản lý ở tab Mẫu Câu.", isOn: $templatesEnabled)
            } header: { Text("Mẫu câu") }
        }
    }
}

struct PhimPage: View {
    @AppStorage("numberRow", store: featureDefaults) private var numberRow = false
    /// Giữ phím chữ ra ký tự phụ (KeyAlternates) — số mặc định BẬT, ký hiệu TẮT.
    @AppStorage("longPressNumbers", store: featureDefaults) private var longPressNumbers = true
    @AppStorage("longPressSymbols", store: featureDefaults) private var longPressSymbols = false
    /// Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh — mặc định TẮT (KeyboardSettings.spaceSwipeLanguage).
    @AppStorage("spaceSwipeLanguage", store: featureDefaults) private var spaceSwipeLanguage = false
    /// "off" | "left" | "right" — bàn phím đọc lúc hiện (OneHand.resolve).
    @AppStorage("oneHandMode", store: featureDefaults) private var oneHandMode = "off"
    /// Ô phóng to chữ khi bấm phím — mặc định BẬT (KeyboardView.keyPreviewKey).
    @AppStorage("keyPreviewEnabled", store: featureDefaults) private var keyPreview = true
    @AppStorage("hapticFeedback", store: featureDefaults) private var hapticFeedback = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        FeaturePageList(page: .phim) {
            Section {
                settingToggle("Hàng phím số", "Thêm hàng 1 … 0 trên hàng chữ (bàn phím cao thêm ~¾ hàng).", isOn: $numberRow)
                // iPad có ký tự phụ vuốt xuống riêng ⇒ chỉ iPhone.
                if isPhone {
                    if !numberRow {
                        settingToggle("Giữ phím hàng trên để ra số", "Giữ q … p để gõ 1 … 0 (số nhỏ ở góc phím).", isOn: $longPressNumbers)
                    }
                    settingToggle("Giữ phím hàng 2, 3 để ra ký tự đặc biệt", "Giữ a … l, z … m để gõ @ # $ _ & - + ( ) … Giữ , để ra dấu chấm.", isOn: $longPressSymbols)
                }
            } header: { Text("Phím") }
            Section {
                settingToggle("Vuốt phím cách đổi Tiếng Việt / Tiếng Anh", "Vuốt nhanh phím cách sang trái/phải. Tiếng Anh gõ nguyên văn, logo thành E. Giữ rồi kéo vẫn là di con trỏ.", isOn: $spaceSwipeLanguage)
                if isPhone {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chế độ một tay")
                        Picker("Chế độ một tay", selection: $oneHandMode) {
                            Text("Tắt").tag("off")
                            Text("Trái").tag("left")
                            Text("Phải").tag("right")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("Thu hẹp bàn phím về một bên. Giữ lâu nút ☰ trên thanh gợi ý để bật/tắt nhanh.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Cử chỉ") }
            Section {
                settingToggle("Phóng to chữ khi bấm", "Ô chữ lớn nổi trên phím vừa chạm. Tắt cho gọn, nhẹ máy.", isOn: $keyPreview)
                settingToggle("Rung phím", "Rung nhẹ mỗi lần chạm phím.", isOn: $hapticFeedback)
                if hapticFeedback {
                    FullAccessNotice(reason: "Rung phím")
                }
            } header: { Text("Phản hồi khi chạm") }
        }
    }
}
