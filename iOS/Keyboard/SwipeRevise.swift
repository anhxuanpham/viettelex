// SwipeRevise.swift — SỬA LẠI TỪ VUỐT TRƯỚC khi đã biết từ kế (ngữ cảnh HAI PHÍA). Song
// sinh android/keyboard/src/main/kotlin/com/viettelex/keyboard/SwipeRevise.kt — sửa hằng
// số/hành vi ở đây thì sửa y hệt bên kia.
//
// Vuốt w1 chỉ biết ngữ cảnh trái (w0). Khi cú vuốt kế ra w2, chấm lại các ứng viên c của w1
// bằng điểm cũ (hình học + tần suất + ngữ cảnh trái, `scored`) + trigram phải s(w2 | w0, c)
// (vnlm.bin) ·rightWeight kẹp [rightFloor, rightCap]; ứng viên khác thắng từ đang hiện
// ≥ margin ⇒ thay. Chỉ từ Việt, chỉ từ vuốt liền trước, một lần. Caller lo fail-safe màn
// hình (đuôi phải khớp đúng từ cũ). Từ kế cũng có thể GÕ BẰNG PHÍM (Typed/reviseTyped): chấm
// lại lúc từ gõ được chốt (dấu cách/dấu câu), ngữ cảnh phải = từ đã chốt (chắc chắn), trọng
// số/lề riêng. Chi phí: ≤ maxCandidates lần tra LM, chỉ sau một cú vuốt hoặc ở ranh giới từ
// NGAY SAU từ vuốt — không ở đường phím chữ.
import Foundation

enum SwipeRevise {
    /// Chỉnh trên tập dev (SwipeReviseTests.kt sweep) — docs/DATA-SOURCES.md "Sửa lại từ vuốt trước".
    static let rightWeight: Float = 0.1
    static let rightCap: Float = 1.0
    static let rightFloor: Float = -1.0
    static let margin: Float = 0.1
    /// Từ kế GÕ BẰNG PHÍM (chắc chắn, không phải từ vuốt đoán) ⇒ tin ngữ cảnh phải hơn, lề cao
    /// hơn để giữ sửa sai thấp. Chỉnh riêng trên dev (SwipeReviseTests.kt sweepTyped).
    static let typedRightWeight: Float = 0.15
    static let typedMargin: Float = 0.3
    static let poolForms = 3
    static let poolWords = 4
    static let maxCandidates = 8

    /// Ứng viên tiếng Việt (chữ thường) của một cú vuốt + điểm tổng cùng thước decoder:
    /// điểm dạng − điểm bung tốt nhất của dạng (= phần hình học) + điểm bung của âm tiết.
    /// Rỗng khi top-1 là tiếng Anh.
    static func scored(_ cands: [SwipeCandidate], context: ((String) -> Float)?,
                       lambdaFreq: Float) -> [SwipeWord] {
        guard let first = cands.first, first.lang == .vi else { return [] }
        var out: [(SwipeWord, Int)] = []
        for c in cands.prefix(poolForms) where c.lang == .vi {
            let ex = SwipeDecoder.expand(c.folded, limit: poolWords, lambdaFreq: lambdaFreq, context: context)
            guard let top = ex.first else { continue }
            let geom = c.score - top.score
            for w in ex { out.append((SwipeWord(word: w.word, score: geom + w.score), out.count)) }
        }
        out.sort { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        return out.prefix(maxCandidates).map { $0.0 }
    }

    /// Từ trước vừa được sửa ⇒ ngữ cảnh trái của cú vuốt này đổi: chấm lại ứng viên Việt =
    /// hình học (điểm cũ − bung tốt nhất theo ngữ cảnh cũ) + bung tốt nhất theo ngữ cảnh mới,
    /// xếp lại (ổn định). Ứng viên tiếng Anh giữ điểm.
    static func rerank(_ cands: [SwipeCandidate], old: ((String) -> Float)?, oldLambda: Float,
                       new: ((String) -> Float)?, newLambda: Float) -> [SwipeCandidate] {
        let re = cands.map { c -> SwipeCandidate in
            guard c.lang == .vi,
                  let o = SwipeDecoder.expand(c.folded, limit: 1, lambdaFreq: oldLambda, context: old).first,
                  let n = SwipeDecoder.expand(c.folded, limit: 1, lambdaFreq: newLambda, context: new).first
            else { return c }
            return SwipeCandidate(folded: c.folded, score: c.score - o.score + n.score)
        }
        return re.enumerated().sorted {
            $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
        }.map(\.element)
    }

    /// Điểm phải: trigram s(next | prev, c) có trọng số, kẹp. 0 nếu thiếu dữ liệu.
    static func rightScore(_ lm: SyllableLM, prev: Int, cand: Int, next: Int,
                           weight: Float = rightWeight) -> Float {
        guard let ctx = lm.context(prev2: prev, prev1: cand) else { return 0 }
        return max(rightFloor, min(rightCap, weight * ctx.score(next)))
    }

    /// Từ thay cho `current` (chữ thường, có dấu) khi biết từ kế `next`; nil = giữ nguyên.
    /// `prev` = từ trước `current` (ngữ cảnh trái của trigram phải).
    static func revise(_ scored: [SwipeWord], current: String, prev: String?, next: String,
                       lm: SyllableLM? = SyllableLM.shared, margin: Float = margin,
                       weight: Float = rightWeight) -> String? {
        guard let lm, scored.count >= 2, let nextId = SyllableBigram.id(of: next) else { return nil }
        let prevId = prev.flatMap { SyllableBigram.id(of: $0) } ?? -1
        var cur: Float?
        var best: String?
        var bestScore = -Float.infinity
        for w in scored {
            guard let id = SyllableBigram.id(of: w.word) else { continue }
            let s = w.score + rightScore(lm, prev: prevId, cand: id, next: nextId, weight: weight)
            if w.word == current { cur = s }
            if s > bestScore { bestScore = s; best = w.word }
        }
        guard let cur, let best, best != current, bestScore - cur >= margin else { return nil }
        return best
    }

    /// Từ vuốt Việt còn nguyên vừa được phím chữ (dấu cách treo) / dấu cách chốt, chờ từ gõ kế
    /// tiếp. `prev` = từ trước nó (ngữ cảnh trái của trigram phải).
    struct Typed: Equatable {
        let word: String
        let scored: [SwipeWord]
        let sc: SwipeCase
        let prev: String?
    }

    /// Kết quả reviseTyped: đuôi `tail` (đang trên màn hình) → `replacement`.
    struct TypedEdit: Equatable {
        let old: String
        let new: String
        let typed: String
        let boundary: String
        var tail: String { old + " " + typed + boundary }
        var replacement: String { new + " " + typed + boundary }
    }

    /// Từ gõ `typed` (dạng cuối đã chốt) vừa được ranh giới `boundary` chốt ngay sau từ vuốt
    /// `p`: chấm lại từ vuốt. Chỉ khi chữ trước con trỏ `before` kết thúc ĐÚNG bằng
    /// "từ vuốt + ␠ + từ gõ + ranh giới" và trước đó không dính chữ/số — lệch/không đọc được ⇒ nil.
    static func reviseTyped(_ p: Typed, typed: String, boundary: String, before: String?,
                            lm: SyllableLM? = SyllableLM.shared, margin: Float = typedMargin,
                            weight: Float = typedRightWeight) -> TypedEdit? {
        guard !typed.isEmpty, let b0 = boundary.first, !b0.isLetter, !b0.isNumber, let before else { return nil }
        let e0 = TypedEdit(old: p.word, new: p.word, typed: typed, boundary: boundary)
        guard before.hasSuffix(e0.tail) else { return nil }
        if let c = before.dropLast(e0.tail.count).last, c.isLetter || c.isNumber { return nil }
        guard let new = revise(p.scored, current: p.word.lowercased(), prev: p.prev, next: typed.lowercased(),
                               lm: lm, margin: margin, weight: weight) else { return nil }
        let cased = p.sc.apply(new)
        return cased == p.word ? nil : TypedEdit(old: p.word, new: cased, typed: typed, boundary: boundary)
    }

    /// Áp `e` lên màn hình: đọc lại đuôi, lệch ⇒ không đụng (false).
    static func apply(_ e: TypedEdit, undo: Bool = false, proxy: TextProxyLike) -> Bool {
        let (from, to) = undo ? (e.replacement, e.tail) : (e.tail, e.replacement)
        guard proxy.contextBeforeInput?.hasSuffix(from) == true else { return false }
        for _ in 0..<from.count { proxy.deleteBackward() }
        proxy.insertText(to)
        return true
    }
}
