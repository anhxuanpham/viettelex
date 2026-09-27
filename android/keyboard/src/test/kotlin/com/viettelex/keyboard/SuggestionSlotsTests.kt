package com.viettelex.keyboard

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Thứ tự ưu tiên slot thanh gợi ý (SuggestionSlots) — CÙNG bảng ca với iOS
 * SuggestionSlotsTests.swift (so payload; nhãn nguyên văn khác kiểu nền tảng).
 * Tầng: hoàn tác > clipboard > "Thêm dấu" > chip số (giữa) > chữ.
 */
class SuggestionSlotsTests {
    private val N = SuggestionSet.NUMBER_TOKEN
    private val ADD = SuggestionSet.ADD_TONES_TOKEN
    private val UNDO = SuggestionSet.UNDO_TONES_TOKEN
    private val PASTE = SuggestionSet.PASTE_TOKEN
    private fun clip(v: String) = SuggestionSet.CLIP_CHIP_PREFIX + v
    private val otp = ClipChip(ClipChip.Kind.entries.first(), "482913", "Dán OTP 482913")
    private val stk = ClipChip(ClipChip.Kind.entries.first(), "0123456789", "Dán STK 0123456789")

    /** Payload 3 slot (iOS: từ kế tiếp trái→phải) hoặc mô tả bố cục khác. */
    private fun payloads(set: SuggestionSet, undo: BarChip? = null, pill: Boolean = false, middle: Boolean = false): String =
        when (val l = SuggestionSlots.arrange(set, undo, undoAsPill = pill, bestInMiddle = middle)) {
            is BarLayout.Pill -> "pill:" + l.chip.payload
            BarLayout.PasteCard -> "paste"
            is BarLayout.Chips -> "chips:" + l.chips.joinToString("|") { it.payload }
            is BarLayout.Slots -> l.slots.joinToString("|") { it?.payload ?: "-" } +
                (if (l.emojis.isEmpty()) "" else " e:" + l.emojis.joinToString(""))
        }

    @Test fun wordsOnly() {
        assertEquals("anh|ánh|- e:😀", payloads(SuggestionSet(literal = "anh", word = "ánh", word2 = "ảnh", emojis = listOf("😀"))))
        assertEquals("anh|ánh|ảnh", payloads(SuggestionSet(literal = "anh", word = "ánh", word2 = "ảnh")))
        assertEquals("a|b|c", payloads(SuggestionSet(nextWords = listOf("a", "b", "c"))))
        assertEquals("b|a|c", payloads(SuggestionSet(nextWords = listOf("a", "b", "c")), middle = true))
    }

    @Test fun numberChipAlwaysMiddle() {
        assertEquals("12|$N|mười", payloads(SuggestionSet(literal = "12", word = "mười", number = "mười hai")))
        // slot 3 là vùng emoji ⇒ nội dung giữa rơi (không chồng emoji)
        assertEquals("12|$N|- e:😀", payloads(SuggestionSet(literal = "12", word = "mười", emojis = listOf("😀"), number = "x")))
        assertEquals("a|$N|b", payloads(SuggestionSet(nextWords = listOf("a", "b", "c"), number = "x")))
    }

    @Test fun undoBeatsEverything() {
        val u = BarChip("↩︎ Khôi phục", "restore")
        val busy = SuggestionSet(nextWords = listOf("a", "b"), paste = true, clipChips = listOf(otp), number = "x",
            actionLabel = "Thêm dấu", action = ADD)
        assertEquals("restore|$N|a", payloads(busy, undo = u))
        assertEquals("pill:restore", payloads(busy, undo = u, pill = true))
        val tones = SuggestionSet(nextWords = listOf("a", "b"), number = "x", actionLabel = "↩︎ Hoàn tác", action = UNDO)
        assertEquals("$UNDO|$N|a", payloads(tones))
        assertEquals("pill:$UNDO", payloads(tones, pill = true))
        // hoàn tác khi đang gõ: nguyên văn + ứng viên dời phải
        assertEquals("restore|anh|ánh", payloads(SuggestionSet(literal = "anh", word = "ánh"), undo = u))
    }

    @Test fun clipboardBeatsAddTonesAndNumber() {
        val s = SuggestionSet(nextWords = listOf("a"), paste = true, clipChips = listOf(otp, stk, otp), number = "x",
            actionLabel = "Thêm dấu", action = ADD)
        assertEquals("chips:${clip("482913")}|${clip("0123456789")}|$PASTE", payloads(s))
        assertEquals("paste", payloads(s.copy(clipChips = emptyList())))
        // không vừa copy ⇒ không ô Dán kèm
        assertEquals("chips:${clip("482913")}", payloads(s.copy(paste = false, clipChips = listOf(otp))))
    }

    @Test fun addTonesLeadsThenNumberMiddle() {
        val s = SuggestionSet(nextWords = listOf("a", "b", "c"), actionLabel = "Thêm dấu", action = ADD)
        assertEquals("$ADD|a|b", payloads(s))
        assertEquals("$ADD|a|b", payloads(s, middle = true))
        assertEquals("$ADD|$N|a", payloads(s.copy(number = "x")))
    }

    /** Bug 27/09: gợi ý nền về giữa chạm xuống và nhấc tay đổi ô — phải chèn từ lúc chạm xuống. */
    @Test fun tapCommitsPayloadShownAtTouchDown() {
        val latch = SlotTapLatch()
        val slots = arrayOf<String?>("casn", "cánh", "cắn")
        latch.down(slots[2])
        slots[2] = "cân"                                // kết quả nền mới vẽ lại bar
        assertEquals("cắn", latch.up())
        assertEquals(null, latch.up())                   // dùng một lần
        latch.down("x"); latch.cancel()
        assertEquals(null, latch.up())
    }

    /** "↩︎ từ cũ" sau khi vuốt sửa lại từ trước: slot đầu, biến thể vuốt dời phải — không thành pill. */
    @Test fun reviseUndoLeadsSwipeAlternatives() {
        val r = SuggestionSet.UNDO_REVISE_TOKEN
        val s = SuggestionSet(nextWords = listOf("a", "b", "c"), actionLabel = "↩︎ có", action = r)
        assertEquals("$r|a|b", payloads(s))
        assertEquals("$r|a|b", payloads(s, pill = true))
    }
}
