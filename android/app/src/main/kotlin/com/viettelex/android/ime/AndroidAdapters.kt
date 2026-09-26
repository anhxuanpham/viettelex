package com.viettelex.android.ime

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.res.AssetManager
import android.os.SystemClock
import android.view.KeyEvent
import android.view.inputmethod.InputConnection
import com.viettelex.keyboard.ClipboardSource
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/** [EditorPort] thật trên một InputConnection (logic nằm ở [IcProxy], thuần). */
class AndroidEditorPort(val ic: InputConnection) : EditorPort {
    override fun beginBatch() { ic.beginBatchEdit() }
    override fun endBatch() { ic.endBatchEdit() }
    override fun commitText(text: CharSequence) = ic.commitText(text, 1)
    override fun deleteBefore(utf16: Int) = ic.deleteSurroundingText(utf16, 0)
    override fun deleteCodePointsBefore(count: Int) = ic.deleteSurroundingTextInCodePoints(count, 0)
    override fun deleteSurrounding(before: Int, after: Int) = ic.deleteSurroundingText(before, after)
    override fun textBefore(n: Int): CharSequence? = ic.getTextBeforeCursor(n, 0)
    override fun textAfter(n: Int): CharSequence? = ic.getTextAfterCursor(n, 0)
    override fun selectedText(): CharSequence? = ic.getSelectedText(0)
    override fun setSelection(start: Int, end: Int) = ic.setSelection(start, end)
    override fun finishComposing() = ic.finishComposingText()
    override fun performEditorAction(actionId: Int) = ic.performEditorAction(actionId)

    @Suppress("DEPRECATION")   // ACTION_MULTIPLE + chuỗi: cách duy nhất gửi ký tự Unicode qua key event
    override fun sendText(text: CharSequence) {
        ic.sendKeyEvent(KeyEvent(android.os.SystemClock.uptimeMillis(), text.toString(),
            android.view.KeyCharacterMap.VIRTUAL_KEYBOARD, 0))
    }

    override fun sendKey(key: EditorPort.PortKey) {
        val code = when (key) {
            EditorPort.PortKey.DEL -> KeyEvent.KEYCODE_DEL
            EditorPort.PortKey.ENTER -> KeyEvent.KEYCODE_ENTER
            EditorPort.PortKey.LEFT -> KeyEvent.KEYCODE_DPAD_LEFT
            EditorPort.PortKey.RIGHT -> KeyEvent.KEYCODE_DPAD_RIGHT
            EditorPort.PortKey.UP -> KeyEvent.KEYCODE_DPAD_UP
            EditorPort.PortKey.DOWN -> KeyEvent.KEYCODE_DPAD_DOWN
        }
        val t = SystemClock.uptimeMillis()
        val flags = KeyEvent.FLAG_SOFT_KEYBOARD or KeyEvent.FLAG_KEEP_TOUCH_MODE
        ic.sendKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0, 0, -1, 0, flags))
        ic.sendKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0, 0, -1, 0, flags))
    }
}

/**
 * Nguồn clipboard cho nút Dán (§7.1): đếm đổi bằng addPrimaryClipChangedListener; chỉ
 * đọc ClipDescription (không bật toast "đã dán") cho tới khi user chạm.
 */
class AndroidClipboard(private val ctx: Context) : ClipboardSource {
    private val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    @Volatile private var count = 0
    /**
     * Gọi (main thread) mỗi lần clip đổi — IME ghi lịch sử clipboard. Listener chỉ sống
     * khi process IME sống (VietTelex là bàn phím đang chọn); copy lúc process chết thì
     * bù ở lần hiện kế ([ClipDescription.getTimestamp] ≤ 180 s).
     */
    var onChanged: (() -> Unit)? = null
    private val listener = ClipboardManager.OnPrimaryClipChangedListener { count++; onChanged?.invoke() }

    init { cm.addPrimaryClipChangedListener(listener) }

    fun release() = cm.removePrimaryClipChangedListener(listener)

    override val changeCount: Int get() = count

    override fun hasText(): Boolean = try {
        val d = cm.primaryClipDescription
        d != null && (d.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) || d.hasMimeType("text/*")) && isRecent(d)
    } catch (_: Exception) { false }

    /**
     * Clip copy TRƯỚC khi process IME sống thì listener không thấy — dùng timestamp hệ
     * thống (API 26) để không mời dán clip cũ > 180 s. Chịu cả hai time base.
     */
    private fun isRecent(d: ClipDescription): Boolean {
        val ts = d.timestamp
        if (ts <= 0) return true
        val now = if (ts > 1_000_000_000_000L) System.currentTimeMillis() else SystemClock.elapsedRealtime()
        return now - ts < 180_000
    }

    /** Android 13+: app nguồn đánh dấu EXTRA_IS_SENSITIVE (mật khẩu, OTP từ trình quản lý mật khẩu). */
    override fun isSensitive(): Boolean = try {
        cm.primaryClipDescription?.extras?.getBoolean(EXTRA_IS_SENSITIVE, false) == true
    } catch (_: Exception) { false }

    override fun readText(): String? = try {
        cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString()
    } catch (_: Exception) { null }

    private companion object {
        /** = ClipDescription.EXTRA_IS_SENSITIVE (API 33); hằng chuỗi để chạy cả máy cũ. */
        const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }
}

/** Blob assets: mmap (asset không nén) — fallback đọc cả file. */
object AssetBlobs {
    fun provider(am: AssetManager): (String) -> ByteBuffer = { name ->
        try {
            am.openFd(name).use { fd ->
                FileInputStream(fd.fileDescriptor).channel.use { ch ->
                    ch.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.length)
                }
            }
        } catch (_: Exception) {
            ByteBuffer.wrap(am.open(name).use { it.readBytes() })
        }
    }
}
