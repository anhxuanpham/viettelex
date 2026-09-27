// SyncMerge — phần iOS của đồng bộ iCloud: đổi mẫu câu / setting ⇄ domain LWW.
// Lõi hợp nhất (SyncEntry, SyncMerge.stamp/merge, SyncEngine) ở SyncCore.swift.
import Foundation

extension SyncMerge {
    // MARK: mẫu câu ⇄ domain (giữ thứ tự)

    static func templatesToDomain(_ items: [BackupTemplate]) -> [String: String] {
        var out: [String: String] = [:]
        for (i, it) in items.enumerated() where out[it.text] == nil {
            out[it.text] = String(format: "%06d", i) + "\u{1}" + it.label
        }
        return out
    }

    static func templatesFromDomain(_ d: [String: String]) -> [BackupTemplate] {
        d.map { text, v -> (String, BackupTemplate) in
            let parts = v.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            let order = parts.first.map(String.init) ?? ""
            let label = parts.count > 1 ? String(parts[1]) : ""
            return (order, BackupTemplate(label: label, text: text))
        }
        .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.text < $1.1.text }
        .map { $0.1 }
    }

    static func settingsToDomain(_ s: [String: SettingValue]) -> [String: String] { s.mapValues { $0.syncString } }
    static func settingsFromDomain(_ d: [String: String]) -> [String: SettingValue] {
        var out: [String: SettingValue] = [:]
        for (k, v) in d { if let sv = SettingValue.fromSyncString(v, key: k) { out[k] = sv } }
        return out
    }
}
