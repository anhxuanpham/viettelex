// SelfTest.swift — `viettelex-text-tool --self-test <iOS/KeyboardTests/Fixtures>` (ctest
// caret_suggest): các ca của macOS AppTests/CaretSuggestionsTests.swift + MathHintTests.swift
// (fixture chung math-results.txt / number-chips.txt) chạy trên bản Linux của logic
// (CaretSuggest.swift) và giao thức --serve (Serve.swift). Trả số ca lệch.
import Foundation
import TelexCore

func caretSelfTest(fixtures: String) -> Int {
    var bad = 0, n = 0
    func check(_ ok: Bool, _ what: @autoclosure () -> String) {
        n += 1
        if !ok { bad += 1; print("LỆCH: \(what())") }
    }
    func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): «\(a)» ≠ «\(b)»") }
    func S(_ k: CaretSuggestion.Kind, _ d: String, _ r: String, _ i: String) -> CaretSuggestion {
        CaretSuggestion(kind: k, display: d, replace: r, insert: i)
    }
    func lines(_ name: String) -> [[String]] {
        readFixture(fixtures + "/" + name).map {
            $0.split(separator: "|", omittingEmptySubsequences: false).map { String($0).replacingOccurrences(of: "␣", with: " ") }
        }
    }

    // MARK: Phép tính (MathHintTests)
    var m = 0
    for c in lines("math-results.txt") where c.first == "chip" && c.count == 3 {
        eq(CaretHintLogic.mathResult(beforeCaret: c[1]) ?? "-", c[2], "math chip «\(c[1])»"); m += 1
    }
    check(m > 10, "math-results: chỉ \(m) ca chip")
    eq(CaretHintLogic.mathResult(beforeCaret: "12*3="), "36", "12*3=")
    eq(CaretHintLogic.mathResult(beforeCaret: "giá 200+10%="), "220", "200+10%=")
    eq(CaretHintLogic.mathResult(beforeCaret: "125 x (4 + 5.5) ="), "1187.5", "125 x (4 + 5.5) =")
    eq(CaretHintLogic.mathResult(beforeCaret: "a=b"), nil, "a=b")
    eq(CaretHintLogic.mathResult(beforeCaret: "x = 5"), nil, "x = 5")
    eq(CaretHintLogic.mathResult(beforeCaret: "12*3"), nil, "chưa có =")
    eq(CaretHintLogic.math(before: "12*3="), S(.math, "= 36", "", "36"), "math suggestion")

    // MARK: Chip số — chỉ dạng tiền (fixture chung, bỏ đọc chữ)
    var k = 0
    for c in lines("number-chips.txt") where c.first == "chip" && (c.count == 3 || c.count == 5) {
        var ctx = c[1], sp = ""
        if !ctx.hasSuffix(" ") { ctx += " "; sp = " " }
        let want: CaretSuggestion? = c.count == 5 && CaretHintLogic.isMoneyFormat(c[2])
            ? S(.number, c[2], c[3] + sp, c[4] + sp) : nil
        eq(CaretHintLogic.moneyChip(before: ctx), want, "money «\(ctx)»"); k += 1
    }
    check(k > 20, "number-chips: chỉ \(k) ca chip")
    eq(CaretHintLogic.moneyChip(before: "giá 1tr2 ")?.display, "1.200.000 ₫", "1tr2")
    eq(CaretHintLogic.moneyChip(before: "giá 1tr2"), nil, "chưa có dấu cách")
    eq(CaretHintLogic.moneyChip(before: "1250000 "), nil, "đọc chữ: bỏ")
    check(CaretHintLogic.numberWorthChecking(boundary: " ", run: "1tr2", prevRun: ""), "worth 1tr2")
    check(CaretHintLogic.numberWorthChecking(boundary: " ", run: "tỷ", prevRun: "2"), "worth 2 tỷ")
    check(!CaretHintLogic.numberWorthChecking(boundary: ",", run: "50k", prevRun: ""), "worth , ")
    check(!CaretHintLogic.numberWorthChecking(boundary: " ", run: "hello", prevRun: "word"), "worth chữ")

    // MARK: Sửa lỗi gõ sai (CaretSuggestionsTests)
    typealias T = TypoFixLogic
    check(T.worthChecking(boundary: " ", raw: "tpoi", word: "tpoi"), "gate space")
    check(T.worthChecking(boundary: ",", raw: "tpoi", word: "tpoi"), "gate ,")
    check(!T.worthChecking(boundary: ".", raw: "tpoi", word: "tpoi"), "gate .")
    check(!T.worthChecking(boundary: "'", raw: "tpoi", word: "tpoi"), "gate '")
    check(!T.worthChecking(boundary: "\n", raw: "tpoi", word: "tpoi"), "gate Enter")
    check(!T.worthChecking(boundary: " ", raw: "tooi", word: "tôi"), "gate âm tiết hợp lệ")
    check(!T.worthChecking(boundary: " ", raw: "kp", word: "kp"), "gate ngắn")
    check(!T.worthChecking(boundary: " ", raw: "tp1i", word: "tp1i"), "gate số")
    check(!T.worthChecking(boundary: " ", raw: "tpoi", word: "(tpoi"), "gate ký hiệu")

    let flags = T.EngineFlags()
    func fix(_ raw: String) -> String? { T.lexiconCorrection(raw: raw, flags: flags) }
    eq(fix("tpoi"), "tôi", "fix tpoi")
    eq(fix("Tpoi"), "Tôi", "fix Tpoi")
    eq(fix("khoong"), nil, "fix khoong")
    eq(fix("khpong"), "không", "fix khpong")
    eq(fix("nhuwng"), nil, "fix nhuwng")
    eq(fix("github"), nil, "fix github")
    eq(fix("hello"), nil, "fix hello")
    eq(fix("toi"), nil, "fix toi")
    eq(fix("tooi"), nil, "fix tooi")
    check(T.isKnown("the"), "known the")
    check(!T.isKnown("tpoi"), "known tpoi")
    eq(T.EngineFlags(bits: "1010000110"), T.EngineFlags(), "flags mặc định")
    check(T.EngineFlags(bits: "0000010000").vniMode, "flags vni")

    typealias C = T.Cand
    let p = T.Params(minLen: 3, minFreq: 150, margin: 80, edits: [.sub, .swap], rivals: [.del, .ins])
    eq(T.pick([C(word: "tôi", freq: 255, edit: .sub)], p: p)?.word, "tôi", "pick một")
    eq(T.pick([C(word: "tôi", freq: 140, edit: .sub)], p: p), nil, "pick hiếm")
    eq(T.pick([C(word: "tôi", freq: 255, edit: .sub), C(word: "tới", freq: 200, edit: .sub)], p: p), nil, "pick sát nút")
    eq(T.pick([C(word: "tội", freq: 175, edit: .sub), C(word: "tôi", freq: 255, edit: .del)], p: p), nil, "pick đối thủ")
    eq(T.pick([C(word: "tôi", freq: 255, edit: .sub), C(word: "tối", freq: 150, edit: .ins)], p: p)?.word, "tôi", "pick margin")

    eq(T.suggestion(before: "anh tpoi,", word: "tpoi", boundary: ",", raw: "tpoi", fix: "tôi"),
       S(.typo, "tôi", "tpoi,", "tôi,"), "typo giữ ranh giới")
    eq(T.suggestion(before: "anh xtpoi ", word: "tpoi", boundary: " ", raw: "tpoi", fix: "tôi"), nil, "typo dính")
    eq(T.suggestion(before: "anh tpoi", word: "tpoi", boundary: " ", raw: "tpoi", fix: "tôi"), nil, "typo lệch")
    check(T.suggestion(before: "Xong. Tpoi ", word: "Tpoi", boundary: " ", raw: "Tpoi", fix: "Tôi") != nil, "typo hoa đầu câu")
    check(T.suggestion(before: "Tpoi ", word: "Tpoi", boundary: " ", raw: "Tpoi", fix: "Tôi") != nil, "typo đầu văn bản")
    eq(T.suggestion(before: "gặp Tpoi ", word: "Tpoi", boundary: " ", raw: "Tpoi", fix: "Tôi"), nil, "typo tên riêng")
    eq(T.suggestion(before: "\u{FFFC}Tpoi ", word: "Tpoi", boundary: " ", raw: "Tpoi", fix: "Tôi"), nil, "typo chưa neo")

    // MARK: Thêm dấu cho cụm không dấu
    func feed(_ t: inout ToneRunLogic.Tracker, _ text: String) -> [ToneRunLogic.Trigger?] {
        var out: [ToneRunLogic.Trigger?] = []
        var chunk = ""
        for ch in text {
            if ch.isLetter || ch.isNumber { chunk.append(ch); continue }
            out.append(t.feed(chunk: chunk, boundary: String(ch)))
            chunk = ch.isWhitespace ? "" : chunk + String(ch)
        }
        return out
    }
    var tr = ToneRunLogic.Tracker()
    eq(feed(&tr, "toi di hoc "), [nil, nil, .pause], "tracker 1")
    eq(feed(&tr, "hom nay "), [.pause, .pause], "tracker 2")
    tr.reset(); eq(feed(&tr, "toi di hoc."), [nil, nil, .sentenceEnd], "tracker .")
    eq(feed(&tr, " roi "), [nil, nil], "tracker câu mới")
    tr.reset(); eq(feed(&tr, "toi, di hoc "), [nil, nil, nil, .pause], "tracker ,")
    tr.reset(); eq(feed(&tr, "tôi di hoc "), [nil, nil, nil], "tracker có dấu")
    tr.reset(); eq(feed(&tr, "the cat is "), [nil, nil, nil], "tracker Anh")
    tr.reset(); eq(feed(&tr, "toi di\nhoc "), [nil, nil, nil], "tracker xuống dòng")
    tr.reset(); eq(feed(&tr, "a b "), [nil, nil], "tracker ngắn")
    for (c, want) in [("toi", true), ("hoc", true), ("toi,", true), ("Toi", true), ("TOI", true), ("tOi", false),
                      ("the", false), ("tôi", false), ("abcdefgh", false), ("", false), ("hoc.", true)] {
        eq(ToneRunLogic.isUnaccentedSyllable(Substring(c)), want, "unaccented «\(c)»")
    }

    eq(ToneRunLogic.run(before: "toi di hoc "), "toi di hoc ", "run 1")
    eq(ToneRunLogic.run(before: "Chiều nào toi di hoc hom nay "), "toi di hoc hom nay ", "run 2")
    eq(ToneRunLogic.run(before: "Xong. toi di hoc."), "toi di hoc.", "run 3")
    eq(ToneRunLogic.run(before: "xin chao ban. toi di hoc "), "toi di hoc ", "run câu trước")
    eq(ToneRunLogic.run(before: "dong 1\ntoi di hoc "), "toi di hoc ", "run dòng")
    eq(ToneRunLogic.run(before: "toi di "), nil, "run ngắn")
    eq(ToneRunLogic.run(before: "tôi đi học "), nil, "run có dấu")
    eq(ToneRunLogic.run(before: "open the file "), nil, "run Anh")

    let run = "toi di hoc "
    let restored = apply(.addTones, run)
    eq(restored, "tôi đi học ", "addTones")
    eq(ToneRunLogic.suggestion(run: run, restored: restored ?? ""), S(.tones, "tôi đi học", run, "tôi đi học "), "tones sugg")
    eq(ToneRunLogic.suggestion(run: run, restored: run), nil, "tones không đổi")
    eq(ToneRunLogic.suggestion(run: run, restored: "tôi"), nil, "tones lệch độ dài")

    // MARK: Ngày giờ
    let en: (String) -> Bool = T.isEnglish
    typealias D = DateHintLogic
    eq(D.detect(boundary: " ", prevRun: "hôm", run: "nay", isEnglish: en), .today, "date hôm nay")
    eq(D.detect(boundary: " ", prevRun: "Hôm", run: "qua", isEnglish: en), .yesterday, "date Hôm qua")
    eq(D.detect(boundary: " ", prevRun: "ngày", run: "mai", isEnglish: en), .tomorrow, "date ngày mai")
    eq(D.detect(boundary: " ", prevRun: "bây", run: "giờ", isEnglish: en), .now, "date bây giờ")
    eq(D.detect(boundary: " ", prevRun: "you", run: "tomorrow", isEnglish: en), .tomorrow, "date you tomorrow")
    eq(D.detect(boundary: " ", prevRun: "right", run: "now", isEnglish: en), .now, "date right now")
    eq(D.detect(boundary: " ", prevRun: "", run: "now", isEnglish: en), nil, "date now trơn")
    eq(D.detect(boundary: " ", prevRun: "gặp", run: "today", isEnglish: en), nil, "date gặp today")
    eq(D.detect(boundary: ",", prevRun: "hôm", run: "nay", isEnglish: en), nil, "date ,")
    eq(D.detect(boundary: " ", prevRun: "hom", run: "nay", isEnglish: en), nil, "date không dấu")
    eq(D.detect(boundary: " ", prevRun: "hôm", run: "sau", isEnglish: en), nil, "date hôm sau")

    let now = D.LocalTime(year: 2026, month: 9, day: 28, hour: 21, minute: 35)
    eq(D.format(.today, now: now), "28/09/2026", "format today")
    eq(D.format(.tomorrow, now: now), "29/09/2026", "format tomorrow")
    eq(D.format(.yesterday, now: now), "27/09/2026", "format yesterday")
    eq(D.format(.now, now: now), "21:35", "format now")
    eq(D.format(.tomorrow, now: .init(year: 2026, month: 12, day: 31, hour: 0, minute: 5)), "01/01/2027", "qua năm")
    eq(D.format(.yesterday, now: .init(year: 2028, month: 3, day: 1, hour: 9, minute: 0)), "29/02/2028", "năm nhuận")
    eq(D.format(.now, now: .init(year: 2026, month: 1, day: 1, hour: 7, minute: 4)), "07:04", "giờ 2 chữ số")

    eq(D.suggestion(before: "Hẹn hôm nay ", prevRun: "hôm", run: "nay", phrase: .today, now: now),
       S(.date, "28/09/2026", "hôm nay ", "28/09/2026 "), "date sugg")
    eq(D.suggestion(before: "bây giờ ", prevRun: "bây", run: "giờ", phrase: .now, now: now)?.insert, "21:35 ", "date giờ")
    eq(D.suggestion(before: "see you tomorrow ", prevRun: "you", run: "tomorrow", phrase: .tomorrow, now: now)?.replace,
       "tomorrow ", "date Anh")
    eq(D.suggestion(before: "xhôm nay ", prevRun: "hôm", run: "nay", phrase: .today, now: now), nil, "date dính")
    eq(D.suggestion(before: "hôm nay", prevRun: "hôm", run: "nay", phrase: .today, now: now), nil, "date lệch")

    // MARK: Giao thức --serve
    eq(HintProtocol.unescape(Substring(HintProtocol.escape("a\tb\nc\\d\re"))), "a\tb\nc\\d\re", "escape")
    eq(HintProtocol.handle("ping"), "ok", "ping")
    eq(HintProtocol.handle("math\t12*3="), "math\t= 36\t\t36", "serve math")
    eq(HintProtocol.handle("math\tabc"), "-", "serve math không")
    eq(HintProtocol.handle("number\tgiá 1tr2 "), "number\t1.200.000 ₫\t1tr2 \t1.200.000 ₫ ", "serve number")
    eq(HintProtocol.handle("date\tHẹn hôm nay \thôm\tnay\t \t2026\t9\t28\t21\t35"),
       "date\t28/09/2026\thôm nay \t28/09/2026 ", "serve date")
    eq(HintProtocol.handle("date\tnay \t\tnay\t \t2026\t9\t28\t21\t35"), "-", "serve date không")
    eq(HintProtocol.handle("typo\tanh tpoi \ttpoi\t \ttpoi\t1010000110"), "typo\ttôi\ttpoi \ttôi ", "serve typo")
    eq(HintProtocol.handle("typo\tgithub \tgithub\t \tgithub\t1010000110"), "-", "serve typo Anh")
    eq(HintProtocol.handle("tones\txin chao ban. toi di hoc "), "tones\ttôi đi học\ttoi di hoc \ttôi đi học ", "serve tones")
    eq(HintProtocol.handle("tones\ttoi di "), "-", "serve tones ngắn")
    eq(HintProtocol.handle("tones\tdong 1\\ntoi di hoc "), "tones\ttôi đi học\ttoi di hoc \ttôi đi học ", "serve tones \\n")
    eq(HintProtocol.handle("lạ\tx"), "-", "serve lệnh lạ")
    eq(HintProtocol.handle(""), "-", "serve rỗng")

    print("caret-suggest: \(n) ca, lệch: \(bad)")
    return bad
}
