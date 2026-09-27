package com.viettelex.keyboard

/**
 * Thứ tự ưu tiên các loại chip tranh slot trên thanh gợi ý — THUẦN, song sinh
 * iOS/Keyboard/SuggestionSlots.swift, cùng bảng ca kiểm (SuggestionSlotsTests). Tài liệu:
 * iOS/docs/IOS-SUGGESTIONS.md mục "Thứ tự ưu tiên slot".
 *
 * Từ cao xuống thấp (tầng trên thắng / đè tầng dưới):
 *  1. **Hoàn tác một lượt** — "↩︎ Khôi phục" (vuốt ⌫; Android là pill riêng của StripView,
 *     đè mọi thứ), "↩︎ Hoàn tác" công cụ văn bản (cùng pill), "↩︎ Hoàn tác" thêm dấu
 *     ([SuggestionSet.UNDO_TONES_TOKEN]). Android: một pill giữa bar ([BarLayout.Pill]);
 *     iOS: slot đầu, gợi ý dời phải.
 *  2. **Clipboard vừa copy** — tối đa 2 chip tách STK/SĐT/OTP + ô "Dán" nguyên văn
 *     ([BarLayout.Chips]) thắng thẻ Dán ([BarLayout.PasteCard]); cả hai thay cả bar.
 *  3. **"Thêm dấu"** ([SuggestionSet.ADD_TONES_TOKEN]) — slot đầu, nhường clipboard.
 *  4. **Chip số** — luôn slot GIỮA; nội dung slot giữa dời sang slot 3 (trừ khi slot 3 là
 *     vùng emoji).
 *  5. **Chữ** — nguyên văn / ứng viên (chip gõ tắt nằm ở ứng viên chính) / emoji, hoặc từ
 *     kế tiếp (bigram, email/TLD, biến thể gõ vuốt).
 */
data class BarChip(val label: String, val payload: String)

sealed class BarLayout {
    /** Một pill giữa bar (Android: hoàn tác thêm dấu — cùng kiểu ô Khôi phục). */
    data class Pill(val chip: BarChip) : BarLayout()
    /** Chip chia đều bar (clipboard). */
    data class Chips(val chips: List<BarChip>) : BarLayout()
    /** Thẻ Dán thay cả bar. */
    object PasteCard : BarLayout()
    /** 3 slot trái→phải + emoji (chiếm vùng slot 3, slots[2] khi đó = null). */
    data class Slots(val slots: List<BarChip?>, val emojis: List<String>) : BarLayout()
}

object SuggestionSlots {
    /**
     * @param undo ô hoàn tác do view giữ (iOS: restoreLabel); Android truyền null vì ô
     *   Khôi phục / Hoàn tác công cụ là pill riêng vẽ đè (vẫn là tầng 1).
     * @param undoAsPill Android true (pill), iOS false (slot đầu).
     * @param bestInMiddle từ kế tiếp tốt nhất ở GIỮA (Android/Gboard) hay trái (iOS).
     * @param pasteLabel nhãn ô "Dán" thêm sau chip clipboard.
     */
    fun arrange(set: SuggestionSet, undo: BarChip? = null, undoAsPill: Boolean,
                bestInMiddle: Boolean, pasteLabel: String = "Dán"): BarLayout {
        val action = if (set.action != null && set.actionLabel != null) BarChip(set.actionLabel, set.action) else null
        // 1. hoàn tác một lượt
        val u = undo ?: action?.takeIf { it.payload == SuggestionSet.UNDO_TONES_TOKEN }
        if (u != null && undoAsPill) return BarLayout.Pill(u)
        // 2. clipboard
        if (u == null && set.clipChips.isNotEmpty()) {
            val chips = set.clipChips.take(2).map { BarChip(it.label, SuggestionSet.CLIP_CHIP_PREFIX + it.value) }.toMutableList()
            if (set.paste && chips.size < 3) chips += BarChip(pasteLabel, SuggestionSet.PASTE_TOKEN)
            return BarLayout.Chips(chips)
        }
        if (u == null && set.paste) return BarLayout.PasteCard
        // 5. chữ
        val slots = arrayOfNulls<BarChip>(3)
        val emojis = if (set.nextWords.isEmpty()) set.emojis.take(3) else emptyList()
        if (set.nextWords.isNotEmpty()) {
            val order = if (bestInMiddle) intArrayOf(1, 0, 2) else intArrayOf(0, 1, 2)
            for (i in 0 until minOf(3, set.nextWords.size)) slots[order[i]] = BarChip(set.nextWords[i], set.nextWords[i])
        } else {
            set.literal?.let { slots[0] = BarChip(it, it) }
            set.word?.let { slots[1] = BarChip(it, it) }
            if (emojis.isEmpty()) set.word2?.let { slots[2] = BarChip(it, it) }
        }
        // 1 (slot) / 3. hoàn tác (iOS) hoặc "Thêm dấu" chiếm slot đầu, chữ dời phải theo thứ tự đọc.
        val lead = u ?: action?.takeIf { it.payload == SuggestionSet.ADD_TONES_TOKEN }
        if (lead != null) {
            val words = if (set.nextWords.isNotEmpty())
                set.nextWords.take(3).map { BarChip(it, it) } else slots.filterNotNull()
            slots[0] = lead; slots[1] = words.getOrNull(0); slots[2] = words.getOrNull(1)
        }
        // 4. chip số: slot giữa; nội dung cũ dời sang slot 3.
        set.number?.let { n ->
            slots[2] = slots[1]
            slots[1] = BarChip(n, SuggestionSet.NUMBER_TOKEN)
        }
        if (emojis.isNotEmpty()) slots[2] = null
        return BarLayout.Slots(slots.toList(), emojis)
    }
}

/**
 * Chạm slot gợi ý: chốt payload lúc CHẠM XUỐNG. Gợi ý nền (VNSuggest) có thể về giữa
 * down và up và thay nội dung ô — đọc payload lúc nhấc tay từng chèn từ MỚI thay vì từ
 * người dùng nhắm (bug 27/09). Song sinh iOS KeyboardView (slot touchDown).
 */
class SlotTapLatch {
    private var payload: String? = null
    fun down(p: String?) { payload = p }
    /** Payload chốt lúc down (null = không có / đã huỷ); dùng một lần. */
    fun up(): String? = payload.also { payload = null }
    fun cancel() { payload = null }
}
