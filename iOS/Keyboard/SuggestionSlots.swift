// Thứ tự ưu tiên các loại chip tranh slot trên thanh gợi ý — THUẦN, song sinh
// android/keyboard/.../SuggestionSlots.kt, cùng bảng ca kiểm (SuggestionSlotsTests).
// Tài liệu: iOS/docs/IOS-SUGGESTIONS.md mục "Thứ tự ưu tiên slot".
//
// Từ cao xuống thấp (tầng trên thắng / đè tầng dưới):
//  1. Hoàn tác một lượt — "↩︎ Khôi phục" (vuốt ⌫), "↩︎ Hoàn tác" công cụ văn bản
//     (restoreLabel/restorePayload), "↩︎ Hoàn tác" thêm dấu (undoTonesToken). iOS: slot
//     đầu, gợi ý dời phải; Android: một pill giữa bar.
//  2. Clipboard vừa copy — tối đa 2 chip tách STK/SĐT/OTP + ô "Dán" nguyên văn, thắng
//     thẻ Dán; cả hai thay cả bar.
//  3. "Thêm dấu" (addTonesToken) — slot đầu, nhường clipboard.
//  4. Chip số — luôn slot GIỮA; nội dung slot giữa dời sang slot 3 (trừ khi slot 3 là
//     vùng emoji). Kết quả phép tính "…=" (MathResults) — slot ĐẦU như bàn phím gốc,
//     mọi chip khác dời phải một ô.
//  5. Chữ — nguyên văn / ứng viên (chip gõ tắt nằm ở ứng viên chính) / emoji, hoặc từ kế
//     tiếp (bigram, email/TLD, biến thể gõ vuốt).
import Foundation

struct BarChip: Equatable {
    let label: String
    let payload: String
}

enum BarLayout: Equatable {
    /// Một pill giữa bar (Android dùng cho hoàn tác; iOS không dùng).
    case pill(BarChip)
    /// Chip chia đều bar (clipboard).
    case chips([BarChip])
    /// Thẻ Dán thay cả bar.
    case pasteCard
    /// 3 slot trái→phải + emoji (vùng slot 3; slots[2] khi đó = nil).
    case slots([BarChip?], emojis: [String])
}

enum SuggestionSlots {
    /// `undoAsPill`: Android true, iOS false. `bestInMiddle`: từ kế tiếp tốt nhất ở giữa
    /// (Android/Gboard) hay trái (iOS).
    static func arrange(_ set: KeyboardView.SuggestionSet, undoAsPill: Bool = false,
                        bestInMiddle: Bool = false, pasteLabel: String = "Dán") -> BarLayout {
        var action: BarChip?
        if let l = set.actionLabel, let p = set.actionPayload { action = BarChip(label: l, payload: p) }
        // 1. hoàn tác một lượt
        var undo: BarChip?
        if let r = set.restoreLabel {
            undo = BarChip(label: r, payload: set.restorePayload ?? KeyboardView.restoreToken)
        } else if let a = action, a.payload == KeyboardView.undoTonesToken {
            undo = a
        }
        if let u = undo, undoAsPill { return .pill(u) }
        // 2. clipboard
        if undo == nil, !set.clipChips.isEmpty {
            var chips = set.clipChips.prefix(2).map { BarChip(label: $0.display, payload: $0.insert) }
            if set.paste, chips.count < 3 { chips.append(BarChip(label: pasteLabel, payload: KeyboardView.pasteToken)) }
            return .chips(chips)
        }
        if undo == nil, set.paste { return .pasteCard }
        // 5. chữ
        var slots: [BarChip?] = [nil, nil, nil]
        let emojis = set.nextWords.isEmpty ? Array(set.emojis.prefix(3)) : []
        if !set.nextWords.isEmpty {
            let order = bestInMiddle ? [1, 0, 2] : [0, 1, 2]
            for (i, w) in set.nextWords.prefix(3).enumerated() { slots[order[i]] = BarChip(label: w, payload: w) }
        } else {
            if let l = set.literal { slots[0] = BarChip(label: "\u{201C}\(l)\u{201D}", payload: l) }
            if let w = set.word { slots[1] = BarChip(label: w, payload: w) }
            if emojis.isEmpty, let w2 = set.word2 { slots[2] = BarChip(label: w2, payload: w2) }
        }
        // 1 (slot) / 3. hoàn tác, "Thêm dấu", "↩︎ từ cũ" (vuốt vừa sửa từ trước) hoặc "↩︎ chữ
        // gốc" (vừa tự sửa) chiếm slot đầu, chữ dời phải theo thứ tự đọc.
        let lead = undo ?? action.flatMap {
            [KeyboardView.addTonesToken, KeyboardView.undoReviseToken,
             KeyboardView.undoAutoCorrectToken].contains($0.payload) ? $0 : nil
        }
        if let lead {
            let words = set.nextWords.isEmpty ? slots.compactMap { $0 }
                : set.nextWords.prefix(3).map { BarChip(label: $0, payload: $0) }
            slots = [lead, words.first, words.count > 1 ? words[1] : nil]
        }
        // 4. chip số: slot giữa; nội dung cũ dời sang slot 3.
        if let n = set.number {
            slots[2] = slots[1]
            slots[1] = BarChip(label: n, payload: KeyboardView.numberToken)
        }
        // 4. kết quả phép tính: slot đầu; còn lại dời phải.
        if let m = set.math {
            slots = [BarChip(label: m, payload: KeyboardView.mathToken), slots[0], slots[1]]
        }
        if !emojis.isEmpty { slots[2] = nil }
        return .slots(slots, emojis: emojis)
    }
}
