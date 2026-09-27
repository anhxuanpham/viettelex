// SwipeTyping.swift — glue gõ vuốt giữa KeyboardView (đường vuốt) và EngineBridge
// (chèn/seed từ). Không UIKit: test được với MockProxy (SwipeTypingTests).
//
// Luồng: KeyboardView phân loại chạm→vuốt (GestureClassifier) → `begin` HUỶ chữ
// đầu đã chèn lúc chạm xuống (checkpoint engine, không ⌫) → nhấc tay → `finish`:
// decode top-5 dạng không dấu (ngữ cảnh = từ kế tiếp hay gặp sau từ trước, theo
// UserLangModel, + LM âm tiết tĩnh: trigram SyllableLM theo 2 âm tiết trước, thiếu thì
// bigram SyllableBigram) → expand dạng thắng thành âm tiết có dấu → chèn top-1 (dấu cách
// treo + seed engine, xem EngineBridge.insertSwipeWord) → thanh gợi ý hiện biến thể.
//
// SwipeDecoder KHÔNG thread-safe: MỌI truy cập đi qua một hàng đợi serial (`queue`);
// prepare() chạy nền ở đó, decode gọi `queue.sync` từ main (lần vuốt đầu ngay sau khi
// hiện bàn phím có thể chờ prepare xong — vài chục ms, một lần).
import Foundation

final class SwipeTyping {
    struct Outcome: Equatable {
        /// Từ trước đó vừa được chốt (để caller học), nếu có.
        let committed: EngineBridge.SettledCommit?
        /// Từ đã chèn (đã áp chữ hoa).
        let word: String
        /// Phương án khác cho thanh gợi ý (đã áp chữ hoa), ≤ 3.
        let alternatives: [String]
        /// Từ chèn là tiếng Anh (nguyên văn) — giai đoạn 3.
        var english = false
        /// Các phương án tiếng Anh trong `alternatives` (chọn ⇒ chèn nguyên văn).
        var englishAlternatives: Set<String> = []
    }

    /// Kết quả thuần của pick/resolve.
    struct Choice: Equatable {
        let word: String
        let alternatives: [String]
        var english = false
        var englishAlternatives: Set<String> = []
    }

    private let decoder = SwipeDecoder()
    private let queue = DispatchQueue(label: "com.viettelex.swipe", qos: .userInitiated)
    /// Layout lần cuối đã gửi xuống hàng đợi (chỉ đọc/ghi trên main).
    private(set) var layout: SwipeLayout?
    /// FUTO Swipe (thử nghiệm, FutoSwipe.swift) — CHỈ đụng trên `queue`; nil = tắt (mặc định):
    /// không tạo, không tải, decode SHARK2 y như cũ.
    private var futo: FutoSwipe?
    /// Công tắc FUTO đã bật (main).
    private(set) var futoActive = false

    /// Điểm ngữ cảnh (log-domain, GIỐNG bản Android SwipeSuggest.Context):
    ///  - cá nhân: +1.5 nếu là từ kế tiếp hay gặp sau từ trước (UserLangModel.nextWords);
    ///    +0.4·ln(1+count) cho từ hay gõ, trần 1.5;
    ///  - tĩnh: PMI bigram âm tiết (vnbigram.bin) sau âm tiết trước ·0.3, trần 1.2 (< 1.5 ⇒
    ///    dữ liệu cá nhân vẫn thắng); đã có nextWords thì nhân 0.5.
    static let nextBonus: Float = 1.5
    static let personalWeight: Float = 0.4
    static let personalCap: Float = 1.5
    static let staticWeight: Float = 0.3
    static let staticCap: Float = 1.2
    static let staticDamp: Float = 0.5
    private static let lambdaFreq = SwipeDecoder.Params().lambdaFreq
    /// Mô hình trigram (vnlm.bin, SyllableLM) — thay bigram PMI khi có: điểm = s·lmWeight
    /// kẹp [lmFloor, lmCap] (có bằng chứng ÂM: "hiếm sau ngữ cảnh này"), và khi đó λ tần
    /// suất lúc chọn dạng/bung dấu hạ còn lmLambdaFreq (LM gánh phần tiên nghiệm). Chỉnh
    /// trên tập dev (Scripts/gen-syllable-lm.py, docs/DATA-SOURCES.md): heldout top-1
    /// 0.861 → 0.894, top-3 0.951 → 0.962 (decoder tầng 2).
    static let lmWeight: Float = 0.15
    static let lmCap: Float = 1.0
    static let lmFloor: Float = -1.0
    static let lmLambdaFreq: Float = 1.0

    /// Điểm ngữ cảnh cá nhân của một âm tiết có dấu.
    static func contextScore(_ w: String, next: Set<String>, count: (String) -> Int) -> Float {
        let c = count(w)
        let personal = c > 0 ? min(personalCap, personalWeight * log(1 + Float(c))) : 0
        return (next.contains(w) ? nextBonus : 0) + personal
    }

    /// Ngữ cảnh một cú vuốt: cá nhân + LM tĩnh theo âm tiết trước — trigram (`prev2`, `prev`)
    /// của SyllableLM nếu có, không thì bigram PMI của SyllableBigram theo `prev`.
    struct Context {
        let next: Set<String>
        let count: (String) -> Int
        private let row: SyllableBigram.Row?
        private let lmContext: SyllableLM.Context?
        private let weight: Float
        /// λ tần suất khi chọn dạng + bung dấu (hạ khi có trigram).
        let lambdaFreq: Float

        init(next: Set<String>, count: @escaping (String) -> Int = { _ in 0 },
             prev: String? = nil, bigram: SyllableBigram? = nil,
             prev2: String? = nil, lm: SyllableLM? = nil) {
            self.next = next
            self.count = count
            let id1 = prev.flatMap { SyllableBigram.id(of: $0) }
            if let lm, let id1 {
                lmContext = lm.context(prev2: prev2.flatMap { SyllableBigram.id(of: $0) } ?? -1, prev1: id1)
            } else { lmContext = nil }
            if lmContext == nil, let bigram, let id1 {
                let r = bigram.row(id1)
                row = r.size > 0 ? r : nil
            } else { row = nil }
            let damp: Float = next.isEmpty ? 1 : SwipeTyping.staticDamp
            weight = (lmContext != nil ? SwipeTyping.lmWeight : SwipeTyping.staticWeight) * damp
            lambdaFreq = lmContext != nil ? SwipeTyping.lmLambdaFreq : SwipeTyping.lambdaFreq
        }

        /// Điểm LM tĩnh của âm tiết có dấu `w` (0 nếu không có dữ liệu).
        func staticScore(_ w: String) -> Float {
            if let lmContext {
                guard let id = SyllableBigram.id(of: w) else { return 0 }
                let damp: Float = next.isEmpty ? 1 : SwipeTyping.staticDamp
                return max(SwipeTyping.lmFloor * damp, min(SwipeTyping.lmCap * damp, weight * lmContext.score(id)))
            }
            guard let row, let id = SyllableBigram.id(of: w) else { return 0 }
            return min(SwipeTyping.staticCap, weight * row.score(id))
        }

        func word(_ w: String) -> Float {
            SwipeTyping.contextScore(w, next: next, count: count) + staticScore(w)
        }

        /// Có trigram thì ứng viên Việt chấm tần suất bằng lmLambdaFreq thay vì λ decoder — hạ
        /// y như vậy cho từ tiếng Anh để cán cân Việt/Anh (bias, margin) giữ nguyên.
        func englishFreqShift(_ w: String) -> Float {
            guard lmContext != nil, let i = SwipeEnglish.index(of: w) else { return 0 }
            return -(SwipeTyping.lambdaFreq - SwipeTyping.lmLambdaFreq) * Float(SwipeEnglish.lexicon.freq[i]) / 255
        }

        /// Cho decoder: max(λ'·tần suất + ngữ cảnh) trên các âm tiết của dạng không dấu −
        /// phần tần suất decoder đã cộng ⇒ decode và expand chấm cùng một thước. Không có
        /// trigram: λ' = λ và kẹp ≥ 0 (như cũ); có trigram: λ' = lmLambdaFreq, không kẹp.
        func folded(_ f: String) -> Float {
            guard let i = SwipeLexicon.index(of: f),
                  let best = SwipeDecoder.expand(f, limit: 1, lambdaFreq: lambdaFreq, context: word).first
            else { return 0 }
            let d = best.score - SwipeTyping.lambdaFreq * Float(SwipeLexicon.forms.freq[i]) / 255
            return lmContext != nil ? d : max(0, d)
        }
    }

    /// Đặt layout (khác lần trước mới gửi); `prepare` = dựng template ngay ở nền.
    func setLayout(_ l: SwipeLayout, prepare: Bool) {
        guard l != layout else { return }
        layout = l
        let d = decoder
        queue.async { [weak self] in
            d.setLayout(l)
            if let f = self?.futo { f.setLayout(l); if prepare { f.load() } }
            if prepare {
                d.prepare()
                _ = SyllableBigram.shared   // bảng bigram tĩnh dùng chung (thanh gợi ý cũng map sẵn)
                _ = SyllableLM.shared       // map mô hình trigram (vnlm.bin)
            }
        }
    }

    /// Bật/tắt decoder FUTO Swipe (main). Bật ⇒ tạo + tải model ở nền (đã bật mà model bị nhả
    /// lúc ẩn bàn phím ⇒ tải lại); tắt ⇒ bỏ hẳn (RAM trả lại).
    func setFuto(enabled: Bool) {
        let was = futoActive
        futoActive = enabled
        let l = layout
        queue.async { [weak self] in
            guard let self else { return }
            if !enabled { self.futo = nil; return }
            if !was || self.futo == nil { self.futo = FutoSwipe(source: FutoSwipe.bundledWeights) }
            if let f = self.futo, let l { f.setLayout(l); f.load() }
        }
    }

    /// Nhả model FUTO (ẩn bàn phím / cảnh báo bộ nhớ) — công tắc giữ nguyên, lần hiện sau tải lại.
    func releaseFuto() {
        guard futoActive else { return }
        queue.async { [weak self] in self?.futo?.release() }
    }

    /// Nạp từ điển tiếng Anh ở nền (lần vuốt đầu khỏi chờ ~vài chục ms). An toàn gọi lại.
    func preloadEnglish() {
        queue.async { _ = SwipeEnglish.lexicon }
    }

    /// Cú vuốt bắt đầu: huỷ chữ đầu (đã chèn lúc chạm xuống). Không huỷ được (màn hình
    /// lệch) ⇒ ⌫ như iPad vuốt xuống.
    func begin(bridge: EngineBridge, proxy: TextProxyLike) {
        if !bridge.undoLastLetter(proxy: proxy) {
            TouchLog.write("swipe: undo chữ đầu thất bại → ⌫")
            bridge.backspace(proxy: proxy)
        }
    }

    /// Giải mã (đồng bộ trên hàng đợi decoder) → dạng thắng + phương án.
    /// `contextWords` = từ hay theo sau từ trước (UserLangModel.nextWords), có dấu;
    /// `count` = số lần user đã gõ một âm tiết (UserLangModel.count);
    /// `prev` = âm tiết liền trước, `prev2` = âm tiết trước nữa (LM tĩnh).
    /// `english` (giai đoạn 3) = tham số tiếng Anh theo ngữ cảnh (SwipeLangContext.prior);
    /// nil = chỉ tiếng Việt (công tắc "Vuốt từ tiếng Anh" tắt).
    func resolve(_ path: SwipePath, contextWords: [String], count: @escaping (String) -> Int = { _ in 0 },
                 prev: String? = nil, bigram: SyllableBigram? = SyllableBigram.shared,
                 prev2: String? = nil, lm: SyllableLM? = SyllableLM.shared,
                 english: SwipeEnglishPrior? = nil, englishOnly: Bool = false,
                 case sc: SwipeCase) -> Choice? {
        guard layout != nil, path.count >= 2 else { return nil }
        let ctx = Context(next: Set(contextWords.map { $0.lowercased() }), count: count,
                          prev: prev, bigram: bigram, prev2: prev2, lm: lm)
        let d = decoder
        // từ tiếng Anh: chỉ điểm cá nhân/từ kế tiếp (bigram tĩnh là của âm tiết Việt)
        let next = ctx.next
        let enCtx: ((String) -> Float)? = english == nil ? nil : { w in
            Self.contextScore(w, next: next, count: count) + ctx.englishFreqShift(w)
        }
        let cands = queue.sync { () -> [SwipeCandidate] in
            if let f = futo {
                if let r = f.decode(path, topK: 5, context: ctx.folded, english: english, englishContext: enCtx,
                                    shark: d) { return r }
                // model chưa sẵn/bị nhả ⇒ SHARK2 lần này, tải nền cho lần sau
                queue.async { f.load() }
            }
            return d.decode(path, topK: 5, context: ctx.folded, english: english, englishContext: enCtx)
        }
        return Self.pick(englishOnly ? Self.englishOnly(cands) : cands, context: ctx, case: sc)
    }

    /// Chế độ Tiếng Anh (vuốt phím cách): chỉ giữ ứng viên tiếng Anh — decode chạy với
    /// `SwipeLangContext.onlyEnglishPrior` để top-K không bị âm tiết Việt chiếm chỗ.
    static func englishOnly(_ cands: [SwipeCandidate]) -> [SwipeCandidate] {
        cands.filter { $0.lang == .en }
    }

    /// Phần thuần: từ top-K dạng không dấu → từ chèn + phương án. Phương án = các biến
    /// thể dấu khác của dạng thắng xen với top-1 có dấu của dạng không dấu hạng 2/3
    /// (vd. vuốt "cho": chó · co · chờ).
    static func pick(_ folded: [String], contextWords: Set<String>,
                     count: @escaping (String) -> Int = { _ in 0 }, case sc: SwipeCase) -> Choice? {
        pick(folded.map { SwipeCandidate(folded: $0, score: 0) },
             context: Context(next: contextWords, count: count), case: sc)
    }

    static func pick(_ folded: [String], context: Context, case sc: SwipeCase) -> Choice? {
        pick(folded.map { SwipeCandidate(folded: $0, score: 0) }, context: context, case: sc)
    }

    /// Bản có nhãn ngôn ngữ (giai đoạn 3): ứng viên tiếng Anh hiển thị nguyên văn; top-1
    /// tiếng Anh ⇒ chèn nguyên văn. Luôn giữ 1 phương án ngôn ngữ kia nếu decoder có
    /// (the ↔ thế) — thay phương án cuối. GIỐNG Android SwipeSuggest.choose. Ngữ cảnh
    /// (cá nhân + bigram tĩnh) chỉ dùng để bung dấu ứng viên tiếng Việt.
    static func pick(_ cands: [SwipeCandidate], context: Context, case sc: SwipeCase) -> Choice? {
        let ctx: (String) -> Float = context.word
        let lam = context.lambdaFreq
        func words(_ c: SwipeCandidate, _ limit: Int) -> [String] {
            c.lang == .en ? [c.folded]
                : SwipeDecoder.expand(c.folded, limit: limit, lambdaFreq: lam, context: ctx).map(\.word)
        }
        guard let top = cands.first else { return nil }
        let expanded = words(top, 6)
        guard let best = expanded.first else { return nil }
        var english: Set<String> = top.lang == .en ? [best] : []
        let variants = expanded.dropFirst()
        var others: [String] = []
        for c in cands.dropFirst().prefix(2) {
            guard let w = words(c, 1).first else { continue }
            others.append(w)
            if c.lang == .en { english.insert(w) }
        }
        var alts: [String] = []
        var vi = variants.makeIterator(), oi = others.makeIterator()
        while alts.count < 3 {
            var added = false
            for next in [vi.next(), oi.next()] {
                guard let w = next else { continue }
                added = true
                if w != best, !alts.contains(w), alts.count < 3 { alts.append(w) }
            }
            if !added { break }
        }
        let isOther: (String) -> Bool = { english.contains($0) != (top.lang == .en) }
        if !alts.contains(where: isOther),
           let c = cands.dropFirst().first(where: { $0.lang != top.lang && !words($0, 1).isEmpty }),
           let w = words(c, 1).first, w != best {
            if c.lang == .en { english.insert(w) } else { english.remove(w) }
            alts.removeAll { $0 == w }
            if alts.count >= 3 { alts.removeLast() }
            alts.append(w)
        }
        return Choice(word: sc.apply(best), alternatives: alts.map(sc.apply), english: top.lang == .en,
                      englishAlternatives: Set(alts.filter { english.contains($0) }.map(sc.apply)))
    }

    /// Nhấc tay: giải mã rồi chèn. nil = không nhận ra gì (không đụng màn hình).
    func finish(_ path: SwipePath, case sc: SwipeCase, contextWords: [String],
                count: @escaping (String) -> Int = { _ in 0 }, prev: String? = nil,
                prev2: String? = nil, english: SwipeEnglishPrior? = nil, englishOnly: Bool = false,
                bridge: EngineBridge, proxy: TextProxyLike) -> Outcome? {
        guard let r = resolve(path, contextWords: contextWords, count: count, prev: prev,
                              prev2: prev2, english: english, englishOnly: englishOnly, case: sc) else {
            TouchLog.write("swipe: không có ứng viên (pts=\(path.count))")
            return nil
        }
        let committed = bridge.insertSwipeWord(r.word, literal: r.english, proxy: proxy)
        if TouchLog.enabled {
            TouchLog.write(String(format: "swipe: pts=%d len=%.0f ms=%.0f alts=%d",
                                  path.count, path.length, path.duration * 1000, r.alternatives.count))
        }
        return Outcome(committed: committed, word: r.word, alternatives: r.alternatives,
                       english: r.english, englishAlternatives: r.englishAlternatives)
    }

    /// Bỏ dấu tiếng Việt (đ → d), chữ thường — khoá so với dạng không dấu của lexicon.
    static func fold(_ w: String) -> String { SwipeLexicon.fold(w) }
}
