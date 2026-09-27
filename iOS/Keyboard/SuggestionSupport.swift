// SuggestionSupport — logic THUẦN (không UIKit, không proxy) rút ra khỏi
// KeyboardViewController để unit-test được: đệm thanh gợi ý cho đủ 3, và quyết
// định double-space → ". ". Controller chỉ còn nối dây (đọc proxy/model).
import Foundation

enum SuggestionFill {
    /// Đệm `base` cho đủ `need` phần tử, lấy thêm từ `candidates` theo thứ tự,
    /// LOẠI TRÙNG (so lowercased) và loại `excluding` (từ đang gõ). Trả tối đa
    /// `need` phần tử. Giữ nguyên thứ tự: base trước, rồi candidate mới.
    static func pad(_ base: [String], with candidates: [String],
                    need: Int, excluding: String = "") -> [String] {
        if base.count >= need { return Array(base.prefix(need)) }
        var out = base
        var seen = Set(base.map { $0.lowercased() })
        if !excluding.isEmpty { seen.insert(excluding.lowercased()) }
        for c in candidates {
            if out.count >= need { break }
            if seen.insert(c.lowercased()).inserted { out.append(c) }
        }
        return out
    }
}

/// Xếp hạng thanh gợi ý — logic THUẦN (song sinh android SuggestRank trong
/// SuggestionSupport.kt; sửa ở đây thì sửa y hệt bên kia). Hợp đồng: docs/IOS-SUGGESTIONS.md
/// (tầng 1, 2, 7).
///
/// Inline (đang gõ dở): `ln(freq+1) + 2.5·ln(count+1) + 4·[trong nextWords] + 1.5·[chỉ thiếu dấu]
/// + bigram`, bigram = min(cap, weight·PMI(âm tiết trước → ứng viên)) — nhân `bigramDamp` khi
/// UserLangModel đã có ý kiến về chính lượt này (một ứng viên nằm trong nextWords): khi đó
/// cap·damp = 3.6 < 4 ⇒ ứng viên trong nextWords luôn hơn ứng viên chỉ có bigram (còn lại ngang
/// nhau) — cá nhân thắng. Không ứng viên nào trong nextWords (người dùng mới, prev lạ) ⇒ bigram đủ mạnh.
///
/// Từ kế tiếp (sau dấu cách): nextWords cá nhân/seed trước; thiếu thì lấp bằng top âm tiết theo
/// bigram tĩnh sau từ trước (PMI + nextFreqWeight·freq/255 — PMI thuần nghiêng về cặp hiếm).
enum SuggestRank {
    struct Params {
        var bigramWeight = SuggestRank.bigramWeight
        var bigramCap = SuggestRank.bigramCap
        var bigramDamp = SuggestRank.bigramDamp
        var nextFreqWeight = SuggestRank.nextFreqWeight
    }

    // chọn trên heldout (27/09/2026, lưới trong android SuggestBigramTests.tuneGrid); cap·damp = 3.6 < 4
    static let bigramWeight = 2.5
    static let bigramCap = 8.0
    static let bigramDamp = 0.45
    static let nextFreqWeight = 12.0

    /// Xếp pool VNSuggest (chưa lọc nhạy cảm). `pmi[i]` = PMI bigram của `pool[i]` (nil = không
    /// có âm tiết trước / bảng). Hoà điểm giữ thứ tự pool (tần suất tĩnh) — Kotlin y hệt.
    static func rankInline(_ pool: [VNSuggest.Match], pmi: [Float]?, typedLen: Int,
                           count: (String) -> Int, ctx: Set<String>, _ p: Params = Params()) -> [String] {
        let damp = pool.contains { ctx.contains($0.word) } ? p.bigramDamp : 1
        var scored: [(Int, Double)] = []
        scored.reserveCapacity(pool.count)
        for (i, m) in pool.enumerated() {
            var b = 0.0
            if let pmi, i < pmi.count, pmi[i] > 0 { b = min(p.bigramCap, p.bigramWeight * Double(pmi[i])) * damp }
            let s = log(Double(m.freq) + 1) + 2.5 * log(Double(count(m.word)) + 1)
                + (ctx.contains(m.word) ? 4 : 0) + (m.word.count == typedLen ? 1.5 : 0) + b
            scored.append((i, s))
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map { pool[$0.0].word }
    }

    /// PMI bigram của từng ứng viên sau âm tiết `prev` (nil nếu không có dữ liệu). Chạy nền.
    static func inlinePmi(_ pool: [VNSuggest.Match], prev: String?,
                          bigram: SyllableBigram? = SyllableBigram.shared) -> [Float]? {
        guard let prev, let bigram, !pool.isEmpty, let id = VNSuggest.lexiconId(of: prev) else { return nil }
        let row = bigram.row(id)
        guard row.size > 0 else { return nil }
        return pool.map { $0.id >= 0 ? row.score($0.id) : 0 }
    }

    /// Top `limit` âm tiết hay theo sau `prev` theo bigram tĩnh (chữ thường, dạng lexicon).
    static func bigramNext(_ prev: String, limit: Int, bigram: SyllableBigram? = SyllableBigram.shared,
                           _ p: Params = Params()) -> [String] {
        guard let bigram, limit > 0, let pid = VNSuggest.lexiconId(of: prev) else { return [] }
        let row = bigram.row(pid)
        guard row.size > 0 else { return [] }
        var ids = [Int](repeating: 0, count: limit), sc = [Double](repeating: 0, count: limit), n = 0
        row.forEach { id, pmi in
            let s = Double(pmi) + p.nextFreqWeight * Double(VNSuggest.freq(id: id)) / 255
            if n == limit && s <= sc[n - 1] { return }
            var j: Int
            if n < limit { j = n; n += 1 } else { j = n - 1 }
            while j > 0 && sc[j - 1] < s { sc[j] = sc[j - 1]; ids[j] = ids[j - 1]; j -= 1 }
            sc[j] = s; ids[j] = id
        }
        return (0..<n).map { VNSuggest.display(ids[$0]) }
    }
}

enum TypingHeuristics {
    /// Double-space có nên biến space vừa gõ thành ". " không (hành vi Apple).
    /// Điều kiện: phím trước là space, cuối ô đang là đúng " ", và ký tự ngay
    /// trước space đó là chữ/số (không phải khoảng trắng hay dấu câu) — tránh
    /// biến "␣␣" đầu ô / sau dấu câu thành ". .".
    static func doubleSpaceMakesPeriod(context: String, lastWasSpace: Bool) -> Bool {
        guard lastWasSpace, context.hasSuffix(" "),
              let prev = context.dropLast().last else { return false }
        return !prev.isWhitespace
            && prev != "." && prev != "!" && prev != "?" && prev != ","
    }
}
