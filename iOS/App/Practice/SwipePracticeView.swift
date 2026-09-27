// SwipePracticeView.swift — màn "Luyện vuốt" (Cài đặt → Gõ vuốt): vuốt từ mục tiêu trên bàn
// phím mẫu CÙNG hình học (PracticeKeyboardGeometry) và CÙNG decoder với bàn phím; chấm
// đúng/sai + độ chính xác phiên. Chỉ lưu nét khi người dùng bật; xuất JSON qua share sheet.
import SwiftUI
import UIKit

/// Kho nét vuốt: JSON Lines trong Application Support của app (không App Group — bàn phím
/// không cần), loại khỏi sao lưu iCloud, không gửi mạng.
enum SwipeTraceStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("swipe-traces.jsonl")
    }

    static func count() -> Int {
        guard let d = try? Data(contentsOf: url) else { return 0 }
        return d.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    static func append(_ t: SwipeTrace) {
        let line = Data((SwipePractice.line(t) + "\n").utf8)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
            var u = url
            var v = URLResourceValues()
            v.isExcludedFromBackup = true
            try? u.setResourceValues(v)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line)
    }

    static func load() -> [SwipeTrace] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return SwipePractice.parseLines(s)
    }

    static func delete() { try? FileManager.default.removeItem(at: url) }

    /// File tạm để chia sẻ.
    static func exportFile() -> URL? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("viettelex-swipe-traces.json")
        do { try SwipePractice.export(load()).write(to: out, options: .atomic) } catch { return nil }
        return out
    }
}

@MainActor
final class SwipePracticeModel: ObservableObject {
    struct Result: Equatable { let ok: Bool; let got: String }

    @Published private(set) var index = 0
    @Published private(set) var tries = 0
    @Published private(set) var hits = 0
    @Published private(set) var result: Result?
    @Published private(set) var stored = 0
    private let seed = Int64(Date().timeIntervalSince1970 * 1000)
    /// SwipeDecoder KHÔNG thread-safe: mọi truy cập qua hàng đợi serial này.
    private let decoder = SwipeDecoder()
    private let queue = DispatchQueue(label: "com.viettelex.practice", qos: .userInitiated)

    var target: SwipePractice.Target { SwipePractice.target(seed: seed, index) }

    func load() {
        queue.async {
            _ = SwipePractice.vietnamese; _ = SwipePractice.english
            let n = SwipeTraceStore.count()
            DispatchQueue.main.async { self.stored = n }
        }
    }

    func skip() { result = nil; index += 1 }

    func submit(_ path: SwipePath, layout: SwipeLayout, save: Bool) {
        let t = target, d = decoder
        let canSave = save && stored < SwipePractice.maxTraces
        queue.async {
            if d.layout != layout { d.setLayout(layout) }
            let top = SwipePractice.decode(d, path, lang: t.lang).map(\.folded)
            if canSave {
                SwipeTraceStore.append(SwipeTrace(target: t.word, folded: t.folded, lang: t.lang, layout: layout,
                                                  path: path, decoded: top,
                                                  time: Int64(Date().timeIntervalSince1970 * 1000)))
            }
            DispatchQueue.main.async {
                let ok = top.first == t.folded
                self.tries += 1
                if ok { self.hits += 1; self.index += 1 }
                self.result = Result(ok: ok, got: top.first ?? "—")
                if canSave { self.stored += 1 }
            }
        }
    }

    func deleteAll() {
        queue.async {
            SwipeTraceStore.delete()
            DispatchQueue.main.async { self.stored = 0 }
        }
    }
}

struct SwipePracticeView: View {
    @StateObject private var m = SwipePracticeModel()
    @AppStorage("swipePracticeSave") private var save = false
    @AppStorage("rowHeightAdjust", store: UserDefaults(suiteName: "group.com.viettelex"))
    private var rowHeightAdjust = 0
    @State private var share: ShareItem?
    @State private var confirmDelete = false

    private struct ShareItem: Identifiable { let url: URL; var id: URL { url } }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text(m.target.word).font(.largeTitle.bold())
                        Text(m.target.folded.map(String.init).joined(separator: " → "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Group {
                            if let r = m.result {
                                Text(r.ok ? "✓ Đúng" : "✗ Bàn phím đọc thành “\(r.got)” — thử lại")
                                    .foregroundStyle(r.ok ? .green : .red)
                            } else { Text(" ") }
                        }.font(.subheadline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    HStack {
                        Text(m.tries == 0 ? "Phiên này: chưa vuốt"
                             : "Phiên này: \(m.hits)/\(m.tries) đúng (\(m.hits * 100 / m.tries)%)")
                        Spacer()
                        Button("Bỏ qua") { m.skip() }
                    }
                } footer: {
                    Text(m.target.lang == .en ? "Từ tiếng Anh — vuốt đúng từng chữ."
                         : "Vuốt qua các chữ không dấu rồi nhấc tay.")
                }
                Section {
                    Toggle(isOn: $save) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lưu nét vuốt trên máy")
                            Text(m.stored > 0 ? "Đã lưu \(m.stored) nét." : "Tắt: chỉ luyện, không lưu gì.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if m.stored > 0 {
                        Button("Xuất JSON…") {
                            DispatchQueue.global(qos: .userInitiated).async {
                                let u = SwipeTraceStore.exportFile()
                                DispatchQueue.main.async { share = u.map(ShareItem.init) }
                            }
                        }
                        Button(confirmDelete ? "Chạm lần nữa để xoá \(m.stored) nét" : "Xoá nét đã lưu",
                               role: .destructive) {
                            if confirmDelete { m.deleteAll() }
                            confirmDelete.toggle()
                        }
                    }
                } header: { Text("Dữ liệu") } footer: {
                    Text("Nét vuốt chỉ nằm trên máy này (không sao lưu iCloud, không tự gửi đi). Xuất JSON để gửi cho nhà phát triển nếu bạn muốn giúp gõ vuốt chính xác hơn.")
                }
            }
            PracticeKeyboard(rowHeight: 54 + CGFloat(max(-10, min(10, rowHeightAdjust)))) { path, layout in
                m.submit(path, layout: layout, save: save)
            }
        }
        .navigationTitle("Luyện vuốt")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { m.load() }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
    }
}

/// Bàn phím mẫu: phím chữ theo PracticeKeyboardGeometry; nét vuốt vào SwipePath y như
/// KeyboardView (dời TouchGeometry.yOffset, lọc 1/5 bước phím).
private struct PracticeKeyboard: View {
    let rowHeight: CGFloat
    let onSwipe: (SwipePath, SwipeLayout) -> Void
    @State private var trail: [CGPoint] = []
    @State private var path: SwipePath?
    @State private var t0: Date?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let keys = PracticeKeyboardGeometry.keys(width: w, rowHeight: rowHeight)
            let layout = PracticeKeyboardGeometry.layout(width: w, rowHeight: rowHeight)
            ZStack(alignment: .topLeading) {
                ForEach(keys, id: \.0) { k in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(scheme == .dark ? Color(white: 0.42) : .white)
                        .overlay(Text(String(k.0)).font(.system(size: 22)))
                        .frame(width: k.1.width, height: k.1.height)
                        .position(x: k.1.midX, y: k.1.midY)
                }
                Path { p in
                    guard let f = trail.first else { return }
                    p.move(to: f)
                    for q in trail.dropFirst() { p.addLine(to: q) }
                }
                .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            .frame(width: w, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in add(v.location, v.time, layout) }
                .onEnded { v in
                    add(v.location, v.time, layout, force: true)
                    if let p = path, p.length >= layout.keyWidth { onSwipe(p, layout) }
                    path = nil; t0 = nil
                })
        }
        .frame(height: PracticeKeyboardGeometry.height(rowHeight: rowHeight) + 8)
        .background(scheme == .dark ? Color(white: 0.17) : Color(red: 0.82, green: 0.83, blue: 0.85))
    }

    private func add(_ pt: CGPoint, _ time: Date, _ layout: SwipeLayout, force: Bool = false) {
        if path == nil {
            path = SwipePath(minDistance: layout.keyWidth / 5)
            t0 = time
            trail = []
        }
        let q = TouchGeometry.keySelectionPoint(pt)
        path?.add(x: Float(q.x), y: Float(q.y), t: time.timeIntervalSince(t0 ?? time), force: force)
        trail.append(pt)
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
