// SyncCore — hợp nhất đồng bộ iCloud KVS theo LWW TỪNG MỤC (last-writer-wins).
//
// Mỗi mục (một setting / một gõ tắt / một mẫu câu) là một entry {v, t}: v = giá trị
// dạng chuỗi (nil = đã xoá — "tombstone"), t = thời điểm sửa (ms). Hai bản gộp bằng
// cách lấy entry có t lớn hơn cho từng key ⇒ giao hoán, kết hợp, luỹ đẳng: hai máy
// sửa HAI mục khác nhau cùng lúc thì giữ cả hai; cùng một mục thì bản sửa sau thắng.
//
// Máy không tự biết "mục nào vừa sửa" (App Group ghi từ app + bàn phím) nên giữ một
// SỔ CÁI (ledger) = bản đã gộp lần trước: lần đồng bộ sau so giá trị hiện tại với sổ,
// mục khác ⇒ đóng dấu t = now, mục biến mất ⇒ tombstone t = now ([stamp]).
//
// Lần đồng bộ ĐẦU TIÊN (sổ trống, vd máy mới): mục nào iCloud đã có (kể cả đã xoá)
// thì iCloud thắng — máy mới không đè cài đặt mặc định của nó lên máy cũ; mục chỉ máy
// mới có thì được thêm (t = now).
//
// File này THUẦN (chỉ Foundation) và dùng chung: bản macOS biên dịch nó theo đường dẫn
// (project.yml gốc repo) ⇒ Mac ↔ iPhone cùng định dạng KVS. Phần đổi mẫu câu/setting
// của iOS nằm ở SyncMerge.swift.
import Foundation

struct SyncEntry: Equatable {
    var v: String?     // nil = tombstone
    var t: Int64
}

typealias SyncDomain = [String: SyncEntry]

/// Ba nhóm được đồng bộ. Mẫu câu: key = câu, v = "<thứ tự 6 số>\u{1}<label>".
enum SyncSection: String, CaseIterable {
    case settings, shortcuts, templates
    /// Key trên NSUbiquitousKeyValueStore.
    var cloudKey: String { "vt.sync.\(rawValue)" }
}

enum SyncMerge {
    /// Tombstone cũ hơn ngần này thì bỏ (máy offline lâu hơn có thể "hồi sinh" mục đã xoá — chấp nhận).
    static let tombstoneTTL: Int64 = 180 * 86_400_000

    static func stamp(current: [String: String], ledger: SyncDomain?, remote: SyncDomain = [:],
                      now: Int64) -> SyncDomain {
        guard let ledger else {
            return current.filter { remote[$0.key] == nil }.mapValues { SyncEntry(v: $0, t: now) }
        }
        var out = ledger
        for (k, v) in current where ledger[k]?.v != v { out[k] = SyncEntry(v: v, t: now) }
        for (k, e) in ledger where e.v != nil && current[k] == nil { out[k] = SyncEntry(v: nil, t: now) }
        return out
    }

    static func merge(_ a: SyncDomain, _ b: SyncDomain) -> SyncDomain {
        a.merging(b) { x, y in wins(y, over: x) ? y : x }
    }

    /// Thứ tự toàn phần để hai máy luôn chọn cùng kết quả: t lớn hơn; hoà thì
    /// tombstone thua giá trị; hai giá trị hoà thì chuỗi lớn hơn.
    static func wins(_ y: SyncEntry, over x: SyncEntry) -> Bool {
        if y.t != x.t { return y.t > x.t }
        switch (x.v, y.v) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (xv?, yv?): return yv > xv
        }
    }

    static func live(_ d: SyncDomain) -> [String: String] { d.compactMapValues { $0.v } }

    static func pruned(_ d: SyncDomain, now: Int64) -> SyncDomain {
        d.filter { $0.value.v != nil || now - $0.value.t < tombstoneTTL }
    }

    // MARK: mã hoá (KVS + sổ cái) — JSON {"key": {"v": "...", "t": 123}}

    static func encode(_ d: SyncDomain) -> Data {
        var o: [String: Any] = [:]
        for (k, e) in d {
            var x: [String: Any] = ["t": NSNumber(value: e.t)]
            if let v = e.v { x["v"] = v }
            o[k] = x
        }
        return (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func decode(_ data: Data?) -> SyncDomain? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var out: SyncDomain = [:]
        for (k, raw) in o {
            guard let x = raw as? [String: Any], let t = (x["t"] as? NSNumber)?.int64Value else { continue }
            out[k] = SyncEntry(v: x["v"] as? String, t: t)
        }
        return out
    }
}

/// Kho key-value trên mây (NSUbiquitousKeyValueStore thật, hoặc bản giả trong test).
protocol SyncCloud: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

/// Dữ liệu cục bộ của một máy: đọc giá trị hiện tại, ghi giá trị đã gộp, và sổ cái.
protocol SyncLocal: AnyObject {
    func current(_ s: SyncSection) -> [String: String]
    func apply(_ s: SyncSection, _ values: [String: String])
    func ledger(_ s: SyncSection) -> SyncDomain?
    func setLedger(_ s: SyncSection, _ d: SyncDomain)
    /// true = dữ liệu mặc định chưa từng sửa (vd mẫu câu bundle) — lần đầu đồng bộ mà
    /// iCloud đã có dữ liệu thì không góp vào (tránh hồi sinh mẫu mặc định đã xoá ở máy kia).
    func isUntouched(_ s: SyncSection) -> Bool
}

enum SyncEngine {
    struct Result: Equatable { var pulled: [SyncSection] = []; var pushed: [SyncSection] = [] }

    /// Một lượt đồng bộ đầy đủ: đóng dấu thay đổi cục bộ → gộp với mây → ghi lại cả hai
    /// phía nếu khác. Gọi lặp lại vô hại (luỹ đẳng).
    @discardableResult
    /// `sections`: máy không có một nhóm (macOS không có mẫu câu) thì bỏ hẳn nhóm đó —
    /// không đọc, không ghi, không đóng dấu xoá lên iCloud.
    static func run(local: SyncLocal, cloud: SyncCloud, now: Int64,
                    sections: [SyncSection] = SyncSection.allCases) -> Result {
        var r = Result()
        for s in sections {
            let cur = local.current(s)
            let remote = SyncMerge.decode(cloud.data(forKey: s.cloudKey)) ?? [:]
            let ledger = local.ledger(s)
            let contrib = ledger == nil && !remote.isEmpty && local.isUntouched(s) ? [:] : cur
            let stamped = SyncMerge.stamp(current: contrib, ledger: ledger, remote: remote, now: now)
            let merged = SyncMerge.pruned(SyncMerge.merge(stamped, remote), now: now)
            let live = SyncMerge.live(merged)
            if live != cur { local.apply(s, live); r.pulled.append(s) }
            if merged != remote { cloud.set(SyncMerge.encode(merged), forKey: s.cloudKey); r.pushed.append(s) }
            local.setLedger(s, merged)
        }
        return r
    }
}
