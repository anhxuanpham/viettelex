// BackupStore — nối BackupFormat/SyncMerge vào dữ liệu thật của iOS: UserDefaults
// App Group "group.com.viettelex" (settings, userTemplates, shortcuts) + file
// userlm.plist trong container (từ đã học). Tests truyền UserDefaults/URL riêng.
import Foundation

final class BackupStore: SyncLocal {
    let defaults: UserDefaults
    let containerURL: URL?
    let defaultTemplates: () -> [BackupTemplate]

    /// Key cục bộ iOS khác tên chuẩn trong file.
    static let localKey: [String: String] = ["reEditWords": "reEditWord"]
    /// Setting iOS không có (bỏ qua khi nhập/đồng bộ, không xuất).
    static let unsupported: Set<String> = ["hardwareTelex"]
    static let templatesKey = "userTemplates"
    /// Gõ tắt: dict [khoá: nội dung] ở App Group — đúng chỗ bàn phím đọc (Keyboard/Shortcuts.swift).
    static let shortcutsKey = ShortcutFile.storeKey
    static let learnedFile = "userlm.plist"
    static func ledgerKey(_ s: SyncSection) -> String { "syncLedger.\(s.rawValue)" }

    init(defaults: UserDefaults, containerURL: URL?, defaultTemplates: @escaping () -> [BackupTemplate] = { [] }) {
        self.defaults = defaults
        self.containerURL = containerURL
        self.defaultTemplates = defaultTemplates
    }

    static var specs: [BackupSettings.Spec] { BackupSettings.all.filter { !unsupported.contains($0.key) } }

    // MARK: settings

    func settings() -> [String: SettingValue] {
        var out: [String: SettingValue] = [:]
        for spec in Self.specs {
            let raw = defaults.object(forKey: Self.localKey[spec.key] ?? spec.key)
            switch spec.kind {
            case .bool(let def): out[spec.key] = .bool((raw as? Bool) ?? def)
            case .int(let def, let r):
                let v = (raw as? Int) ?? def
                out[spec.key] = .int(min(max(v, r.lowerBound), r.upperBound))
            }
        }
        return out
    }

    func setSettings(_ s: [String: SettingValue]) {
        for (k, v) in s where BackupSettings.byKey[k] != nil && !Self.unsupported.contains(k) {
            let lk = Self.localKey[k] ?? k
            switch v { case .bool(let b): defaults.set(b, forKey: lk); case .int(let i): defaults.set(i, forKey: lk) }
        }
    }

    // MARK: gõ tắt / mẫu câu

    func shortcuts() -> [String: String] {
        (defaults.dictionary(forKey: Self.shortcutsKey) as? [String: String]) ?? [:]
    }
    func setShortcuts(_ d: [String: String]) { defaults.set(d, forKey: Self.shortcutsKey) }

    func templates() -> [BackupTemplate] {
        guard let raw = defaults.array(forKey: Self.templatesKey) as? [[String: String]] else {
            return defaultTemplates()
        }
        return raw.compactMap { e in
            guard let t = e["text"], !t.isEmpty else { return nil }
            return BackupTemplate(label: e["label"] ?? "", text: t)
        }
    }
    func setTemplates(_ items: [BackupTemplate]) {
        defaults.set(items.map { ["label": $0.label, "text": $0.text] }, forKey: Self.templatesKey)
    }

    // MARK: từ đã học (plist cùng layout UserLangModel)

    private var learnedURL: URL? { containerURL?.appendingPathComponent(Self.learnedFile) }

    func learnedWords() -> LearnedWords? {
        guard let url = learnedURL, let data = try? Data(contentsOf: url),
              let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let uni = d["uni"] as? [String: Int] else { return nil }
        return LearnedWords(uni: uni,
                            bi: d["bi"] as? [String: [String: Int]] ?? [:],
                            tri: d["tri"] as? [String: [String: Int]] ?? [:])
    }

    /// Gộp vào file hiện có (count lớn hơn). Bàn phím nạp lại file lần hiện kế tiếp.
    func mergeLearnedWords(_ lw: LearnedWords) {
        guard let url = learnedURL, !lw.isEmpty else { return }
        var lastDecay = Date()
        if let data = try? Data(contentsOf: url),
           let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
           let ld = d["lastDecay"] as? Date { lastDecay = ld }
        let merged = (learnedWords() ?? LearnedWords()).merged(with: lw)
        let plist: [String: Any] = ["version": 3, "uni": merged.uni, "bi": merged.bi,
                                    "tri": merged.tri, "lastDecay": lastDecay]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: file sao lưu

    func snapshot(includeLearned: Bool, now: Date = Date()) -> BackupPayload {
        BackupPayload(createdAt: now, platform: "ios", settings: settings(), shortcuts: shortcuts(),
                      templates: templates(), learnedWords: includeLearned ? (learnedWords() ?? LearnedWords()) : nil)
    }

    /// Nhập theo chính sách BackupMerge; trả câu tóm tắt cho người dùng.
    @discardableResult
    func apply(_ p: BackupPayload) -> String {
        if let s = p.settings { setSettings(s) }
        var changed = 0
        if let sc = p.shortcuts {
            let cur = shortcuts()
            changed = sc.filter { cur[$0.key] != $0.value }.count
            setShortcuts(BackupMerge.shortcuts(current: cur, imported: sc))
        }
        var added = 0
        if let t = p.templates {
            let cur = templates()
            let merged = BackupMerge.templates(current: cur, imported: t)
            added = merged.count - cur.count
            setTemplates(merged)
        }
        if let lw = p.learnedWords { mergeLearnedWords(lw) }
        return BackupMerge.summary(p, templatesAdded: added, shortcutsChanged: changed)
    }

    // MARK: SyncLocal (iCloud) — không đồng bộ từ đã học

    func current(_ s: SyncSection) -> [String: String] {
        switch s {
        case .settings: return SyncMerge.settingsToDomain(settings())
        case .shortcuts: return shortcuts()
        case .templates: return SyncMerge.templatesToDomain(templates())
        }
    }

    func apply(_ s: SyncSection, _ values: [String: String]) {
        switch s {
        case .settings: setSettings(SyncMerge.settingsFromDomain(values))
        case .shortcuts: setShortcuts(values)
        case .templates: setTemplates(SyncMerge.templatesFromDomain(values))
        }
    }

    func isUntouched(_ s: SyncSection) -> Bool {
        s == .templates && defaults.object(forKey: Self.templatesKey) == nil
    }

    func ledger(_ s: SyncSection) -> SyncDomain? { SyncMerge.decode(defaults.data(forKey: Self.ledgerKey(s))) }
    func setLedger(_ s: SyncSection, _ d: SyncDomain) { defaults.set(SyncMerge.encode(d), forKey: Self.ledgerKey(s)) }
    // Tắt đồng bộ KHÔNG xoá sổ: bật lại thì thay đổi làm trong lúc tắt được đóng dấu
    // "now" và thắng bản cũ trên iCloud (không mất sửa đổi cục bộ).
}
