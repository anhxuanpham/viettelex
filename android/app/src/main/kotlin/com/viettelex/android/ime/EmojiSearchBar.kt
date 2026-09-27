package com.viettelex.android.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.text.TextUtils
import android.text.TextPaint
import kotlin.math.abs

/**
 * Hàng trên của plane EMOJI_SEARCH (port iOS EmojiSearchBar), vẽ thẳng trên Canvas của
 * [KeyboardView]: ô tìm TỰ VẼ (query + con trỏ, nút ✕) + dải kết quả cuộn ngang. Phím chữ
 * bên dưới là phím VietTelex thật; KeyboardView chặn phím và đẩy vào EmojiSearchSession.
 */
class EmojiSearchBar(private val host: KeyboardView, private val theme: ImeTheme) {
    private val d = theme.density
    private var width = 0f
    private var height = 0f
    private var query = ""
    var results: List<String> = emptyList(); private set

    private val fieldPaint = theme.fill(theme.keyFill)
    private val queryPaint = TextPaint(theme.text(16f, align = Paint.Align.LEFT))
    private val hintPaint = TextPaint(theme.text(16f, color = theme.withAlpha(theme.ink, 0.4f), align = Paint.Align.LEFT))
    private val smallHint = theme.text(13f, color = theme.withAlpha(theme.ink, 0.4f), align = Paint.Align.LEFT)
    private val caretPaint = theme.fill(theme.action)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val emojiPaint = theme.text(26f)
    private val queryOff = theme.centerOffset(queryPaint)
    private val smallOff = theme.centerOffset(smallHint)
    private val emojiOff = theme.centerOffset(emojiPaint)

    private var fieldW = 0f
    private var scrollX = 0f
    private val cell get() = 40 * d

    private var ptr = -1
    private var downX = 0f
    private var lastX = 0f
    private var dragging = false

    fun layout(w: Float, h: Float) { width = w; height = h; relayout() }

    fun update(q: String, list: List<String>) {
        query = q; results = list; scrollX = 0f
        relayout()
    }

    private fun relayout() {
        val text = if (query.isEmpty()) HINT else query
        val tw = queryPaint.measureText(text)
        fieldW = (tw + 64 * d).coerceIn(120 * d, maxOf(width * 0.45f, 120 * d))
    }

    private val resultsLeft get() = 6 * d + fieldW + 6 * d
    private fun maxScroll() = maxOf(0f, results.size * cell - (width - resultsLeft))

    fun draw(c: Canvas) {
        val top = 5 * d; val bottom = height - 3 * d; val cy = (top + bottom) / 2
        c.drawRoundRect(6 * d, top, 6 * d + fieldW, bottom, 9 * d, 9 * d, fieldPaint)
        iconPaint.color = theme.withAlpha(theme.ink, 0.5f)
        ImeIcons.draw(c, ImeIcons.SEARCH, 6 * d + 16 * d, cy, 16 * d, iconPaint)
        val tx = 6 * d + 30 * d
        val avail = fieldW - 30 * d - 30 * d
        if (query.isEmpty()) {
            c.drawText(HINT, tx, cy + queryOff, hintPaint)
            c.drawRect(tx, cy - 10 * d, tx + 2 * d, cy + 10 * d, caretPaint)
        } else {
            val shown = TextUtils.ellipsize(query, queryPaint, avail, TextUtils.TruncateAt.START).toString()
            c.drawText(shown, tx, cy + queryOff, queryPaint)
            val cx = tx + queryPaint.measureText(shown) + 1 * d
            c.drawRect(cx, cy - 10 * d, cx + 2 * d, cy + 10 * d, caretPaint)
            iconPaint.color = theme.withAlpha(theme.ink, 0.35f)
            ImeIcons.draw(c, ImeIcons.DELETE_X, 6 * d + fieldW - 15 * d, cy, 16 * d, iconPaint)
        }
        val left = resultsLeft
        c.save()
        c.clipRect(left, 0f, width, height)
        if (results.isEmpty()) {
            c.drawText(if (query.isEmpty()) EMPTY_HINT else NO_RESULT, left + 4 * d, cy + smallOff, smallHint)
        } else {
            val first = maxOf(0, (scrollX / cell).toInt())
            var i = first
            while (i < results.size) {
                val x = left + i * cell - scrollX
                if (x > width) break
                c.drawText(results[i], x + cell / 2, cy + emojiOff, emojiPaint)
                i++
            }
        }
        c.restore()
    }

    fun contains(y: Float) = y < height

    fun down(pid: Int, x: Float) {
        if (ptr >= 0) return
        ptr = pid; downX = x; lastX = x; dragging = false
    }

    fun move(pid: Int, x: Float) {
        if (pid != ptr) return
        if (!dragging && abs(x - downX) > 8 * d && downX >= resultsLeft) dragging = true
        if (dragging) {
            scrollX = (scrollX + lastX - x).coerceIn(0f, maxScroll())
            lastX = x
            host.invalidate()
        }
    }

    fun up(pid: Int, x: Float, cancelled: Boolean) {
        if (pid != ptr) return
        ptr = -1
        if (cancelled || dragging) { dragging = false; return }
        if (x < resultsLeft) {
            if (query.isNotEmpty() && x > 6 * d + fieldW - 32 * d) host.searchClear()
            return
        }
        val i = ((x - resultsLeft + scrollX) / cell).toInt()
        results.getOrNull(i)?.let { host.paneEmoji(it) }
    }

    fun reset() { ptr = -1; dragging = false }

    companion object {
        const val HINT = "Tìm emoji"
        const val EMPTY_HINT = "Gõ để tìm: tim, chó, cười…"
        const val NO_RESULT = "Không thấy emoji"
    }
}
