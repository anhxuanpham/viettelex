// Chọn theme bàn phím + ảnh nền, có xem trước. Token màu nằm ở
// Keyboard/KeyboardTheme.swift (file dùng chung app + extension).
import SwiftUI
import PhotosUI

private let groupDefaults = UserDefaults(suiteName: "group.com.viettelex")

/// Bản ảnh CHƯA mờ (≤1080px) giữ trong container riêng của app — đổi độ mờ thì
/// dựng lại ảnh cho bàn phím từ đây, không cần chọn lại ảnh.
private var wallpaperSourceURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("wallpaper-src.jpg")
}

struct ThemeSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var settings = ThemeSettings.load(groupDefaults)
    @State private var pickerItem: PhotosPickerItem?
    @State private var wallpaperImage: UIImage? = Self.loadPreviewImage()
    @State private var busy = false
    @State private var error: String?

    private static func loadPreviewImage() -> UIImage? {
        guard let url = Wallpaper.url, let cg = Wallpaper.downsample(url: url, maxPixel: 800) else { return nil }
        return UIImage(cgImage: cg)
    }

    private var hasWallpaperFile: Bool { wallpaperImage != nil }

    var body: some View {
        List {
            Section {
                ThemePreview(palette: settings.palette(systemDark: scheme == .dark,
                                                       wallpaperActive: settings.wallpaperActive(fileExists: hasWallpaperFile)),
                             wallpaper: settings.wallpaperActive(fileExists: hasWallpaperFile) ? wallpaperImage : nil,
                             dim: settings.dim, large: true)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Áp dụng lần mở bàn phím kế tiếp.")
            }

            if !ThemeGate.allowsWallpaper {
                Section {
                    PlusEntryRow()
                } footer: {
                    Text("Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus. Hệ thống, Tối OLED và Tương phản cao luôn miễn phí.")
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(KeyboardTheme.allCases, id: \.self) { t in
                        themeTile(t)
                    }
                }
                .padding(.vertical, 6)
            } header: { Text("Theme") }

            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(hasWallpaperFile ? "Đổi ảnh nền" : "Chọn ảnh nền từ Thư viện",
                          systemImage: "photo")
                }
                .disabled(busy || !ThemeGate.allowsWallpaper)
                if hasWallpaperFile {
                    Toggle("Dùng ảnh nền", isOn: binding(\.wallpaper)).tint(.green)
                    VStack(alignment: .leading) {
                        Text("Độ tối lớp phủ: \(settings.dim)%")
                        Slider(value: Binding(get: { Double(settings.dim) },
                                              set: { settings.dim = Int($0); save() }),
                               in: 0...80, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Độ mờ ảnh: \(settings.blur)")
                        Slider(value: Binding(get: { Double(settings.blur) },
                                              set: { settings.blur = Int($0) }),
                               in: 0...20, step: 1) { editing in
                            if !editing { rerenderBlur() }
                        }
                    }
                    Button("Xoá ảnh nền", role: .destructive) { removeWallpaper() }
                }
                if busy { ProgressView() }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            } header: {
                HStack { Text("Ảnh nền"); plusBadge }
            } footer: {
                Text("Ảnh được thu nhỏ và nén ngay trên máy, không gửi đi đâu. Lớp phủ giúp chữ trên phím dễ đọc.")
            }
        }
        .navigationTitle("Giao diện bàn phím")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            importWallpaper(item)
        }
    }

    @ViewBuilder private var plusBadge: some View {
        Text("Plus").font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.85)))
            .foregroundStyle(.white)
    }

    private func themeTile(_ t: KeyboardTheme) -> some View {
        let selected = settings.theme == t
        let locked = !ThemeGate.allows(t)
        return Button {
            guard !locked else { return }
            settings.theme = t
            save()
        } label: {
            VStack(spacing: 6) {
                ThemePreview(palette: t.palette(systemDark: scheme == .dark),
                             wallpaper: nil, dim: 0, large: false)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: selected ? 3 : 1))
                HStack(spacing: 3) {
                    Text(t.title).font(.caption).lineLimit(1)
                    if t.isPlus { plusBadge }
                }
                .foregroundStyle(.primary)
            }
            .opacity(locked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title + (selected ? ", đang chọn" : ""))
    }

    private func binding(_ kp: WritableKeyPath<ThemeSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: kp] }, set: { settings[keyPath: kp] = $0; save() })
    }

    private func save() { settings.save(groupDefaults) }

    private func importWallpaper(_ item: PhotosPickerItem) {
        busy = true; error = nil
        Task {
            // Ảnh gốc chỉ nằm trong RAM của APP (không bao giờ tới extension).
            let data = try? await item.loadTransferable(type: Data.self)
            let blur = settings.blur
            let result: (src: Data, out: Data)? = await Task.detached(priority: .userInitiated) {
                guard let data, let small = Wallpaper.downsample(data: data, maxPixel: Wallpaper.maxEdge),
                      let src = Wallpaper.encodeJPEG(small),
                      let out = Wallpaper.encodeJPEG(Wallpaper.blurred(small, radius: blur)) else { return nil }
                return (src, out)
            }.value
            await MainActor.run {
                busy = false
                pickerItem = nil
                guard let result else { error = "Không đọc được ảnh này."; return }
                write(src: result.src, out: result.out)
                settings.wallpaper = true
                save()
            }
        }
    }

    private func rerenderBlur() {
        guard let srcURL = wallpaperSourceURL, let data = try? Data(contentsOf: srcURL) else { save(); return }
        busy = true
        let blur = settings.blur
        Task.detached(priority: .userInitiated) {
            let out = Wallpaper.downsample(data: data, maxPixel: Wallpaper.maxEdge)
                .flatMap { Wallpaper.encodeJPEG(Wallpaper.blurred($0, radius: blur)) }
            await MainActor.run {
                busy = false
                if let out { write(src: nil, out: out) }
                save()
            }
        }
    }

    private func write(src: Data?, out: Data) {
        do {
            if let src, let u = wallpaperSourceURL {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try src.write(to: u, options: .atomic)
            }
            guard let u = Wallpaper.url else { error = "Không truy cập được App Group."; return }
            try out.write(to: u, options: .atomic)
            settings.version = Date().timeIntervalSince1970   // bàn phím bỏ cache cũ
            wallpaperImage = Self.loadPreviewImage()
        } catch {
            self.error = "Không lưu được ảnh: \(error.localizedDescription)"
        }
    }

    private func removeWallpaper() {
        if let u = Wallpaper.url { try? FileManager.default.removeItem(at: u) }
        if let u = wallpaperSourceURL { try? FileManager.default.removeItem(at: u) }
        wallpaperImage = nil
        settings.wallpaper = false
        settings.version = Date().timeIntervalSince1970
        save()
    }
}

/// Bàn phím thu nhỏ vẽ bằng đúng token của theme.
struct ThemePreview: View {
    let palette: KeyboardPalette
    let wallpaper: UIImage?
    let dim: Int
    let large: Bool

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                if let wallpaper {
                    Image(uiImage: wallpaper).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                    Color(palette.wallpaperOverlay.alpha(Double(dim) / 100).ui)
                }
                keys(in: geo.size)
            }
        }
    }

    @ViewBuilder private var background: some View {
        if let bg = palette.background {
            Color(bg.ui)
        } else {
            // Nền trong suốt (Hệ thống/Kính): giả lập backdrop hệ thống.
            LinearGradient(colors: palette.isDark
                           ? [Color(white: 0.16), Color(white: 0.10)]
                           : [Color(red: 0.82, green: 0.84, blue: 0.87), Color(red: 0.76, green: 0.78, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func keys(in size: CGSize) -> some View {
        let gap: CGFloat = large ? 5 : 2
        let pad: CGFloat = large ? 6 : 3
        let keyW = (size.width - pad * 2 - gap * 9) / 10
        let keyH = (size.height - pad * 2 - gap * 3) / 4
        let radius: CGFloat = large ? 6 : 2.5
        return VStack(spacing: gap) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(Array(row), id: \.self) { ch in
                        key(large ? String(ch) : "", w: keyW, h: keyH, r: radius)
                    }
                }
            }
            HStack(spacing: gap) {
                key(large ? "123" : "", w: keyW * 2, h: keyH, r: radius, fill: palette.specialFill)
                key(large ? "dấu cách" : "", w: keyW * 5 + gap * 4, h: keyH, r: radius)
                key(large ? "return" : "", w: keyW * 2 + gap, h: keyH, r: radius, fill: palette.accent,
                    ink: palette.accentInk)
            }
        }
        .padding(pad)
    }

    private func key(_ label: String, w: CGFloat, h: CGFloat, r: CGFloat,
                     fill: RGBA? = nil, ink: RGBA? = nil) -> some View {
        RoundedRectangle(cornerRadius: r)
            .fill(Color((fill ?? palette.keyFill).ui))
            .overlay(RoundedRectangle(cornerRadius: r)
                .stroke(Color(palette.keyBorder?.ui ?? .clear), lineWidth: palette.keyBorder == nil ? 0 : 1))
            .overlay(Text(label).font(.system(size: label.count > 1 ? 11 : 15))
                .foregroundColor(Color((ink ?? palette.ink).ui)))
            .frame(width: max(w, 1), height: max(h, 1))
    }
}
