package com.viettelex.android.ime

import com.viettelex.android.ime.TrackpadGesture.Axis
import com.viettelex.android.ime.TrackpadGesture.Step
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** EditorPort đếm MỌI lệnh (mỗi lệnh = 1 IPC InputConnection thật). */
private class CountingPort(val ed: FakeEditor) : EditorPort by ed {
    var ipc = 0
    override fun beginBatch() { ipc++; ed.beginBatch() }
    override fun endBatch() { ipc++; ed.endBatch() }
    override fun textBefore(n: Int): CharSequence? { ipc++; return ed.textBefore(n) }
    override fun textAfter(n: Int): CharSequence? { ipc++; return ed.textAfter(n) }
    override fun setSelection(start: Int, end: Int): Boolean { ipc++; return ed.setSelection(start, end) }
    override fun sendKey(key: EditorPort.PortKey) { ipc++; ed.sendKey(key) }
    override fun finishComposing(): Boolean { ipc++; return ed.finishComposing() }
}

class TrackpadIpcTest {
    @Test fun batcherSumsSameAxis() {
        val b = TrackpadBatcher()
        assertNull(b.add(Step(Axis.H, 1)))
        assertNull(b.add(Step(Axis.H, 2)))
        assertNull(b.add(Step(Axis.H, -1)))
        assertEquals(Step(Axis.H, 2), b.drain())
        assertNull(b.drain())
    }

    @Test fun batcherFlushesOnAxisChangeInOrder() {
        val b = TrackpadBatcher()
        b.add(Step(Axis.H, 3))
        assertEquals(Step(Axis.H, 3), b.add(Step(Axis.V, -1)))   // ngang phát trước
        assertEquals(Step(Axis.V, -1), b.drain())
    }

    @Test fun batcherCancelledStepsEmitNothing() {
        val b = TrackpadBatcher()
        b.add(Step(Axis.H, 2)); b.add(Step(Axis.H, -2))
        assertNull(b.drain())
        b.add(Step(Axis.H, 5)); b.clear()
        assertNull(b.drain())
    }

    private class Result(val ipc: Int, val refreshes: Int, val cursor: Int)

    /**
     * Vệt mẫu: giữ space rồi kéo phải 90 dp chậm, kéo lại trái 45 dp; mẫu chạm 8 ms
     * (120 Hz), frame 16 ms. [old] = đường cũ: mỗi bước một phím MoveCursor (batch + đọc
     * lại chữ sau con trỏ + auto-shift/gợi ý). Mới: gom theo frame, batch chỉ bước đầu,
     * cache chữ sau con trỏ, auto-shift/gợi ý một lần lúc nhả.
     */
    private fun run(old: Boolean): Result {
        val text = "Xin chào các bạn, hôm nay trời đẹp quá ".repeat(4)
        val ed = FakeEditor(text, selStart = 10)
        val port = CountingPort(ed)
        val tracker = SelectionTracker()
        tracker.reset(ed.selStart, ed.selEnd)
        val p = IcProxy({ port }, tracker)
        p.startInput(null, false)
        p.begin(); p.insertText("x"); p.end(); tracker.onUpdate(ed.selStart, ed.selEnd)
        p.begin(); p.deleteCodePoints(1); p.end(); tracker.onUpdate(ed.selStart, ed.selEnd)
        assertTrue(tracker.reliable)
        port.ipc = 0

        val xs = (1..60).map { it * 1.5f } + (1..30).map { 90f - it * 1.5f }
        val g = TrackpadGesture(); g.begin(0f, 0f, 0)
        val batch = TrackpadBatcher()
        var refreshes = 0
        var first = true
        fun send(s: Step) {
            if (old || first) { p.begin(); p.end(); first = false }
            p.moveCursor(s.count)
            tracker.onUpdate(ed.selStart, ed.selEnd)
            if (old) refreshes++
        }
        var t = 0L
        for (x in xs) {
            t += 8
            val s = g.move(x, 0f, t)
            if (old) { s?.let { send(it) }; continue }
            s?.let { batch.add(it)?.let { prev -> send(prev) } }
            if (t % 16 == 0L) batch.drain()?.let { send(it) }
        }
        if (!old) { batch.drain()?.let { send(it) }; refreshes++ }
        return Result(port.ipc, refreshes, ed.selStart)
    }

    @Test fun framedTrackpadCutsIpc() {
        val before = run(old = true)
        val after = run(old = false)
        assertEquals(before.cursor, after.cursor)        // cùng vị trí cuối
        println("trackpad IPC: cũ ${before.ipc} lệnh + ${before.refreshes} lượt auto-shift/gợi ý; " +
            "mới ${after.ipc} lệnh + ${after.refreshes} lượt")
        assertTrue(after.ipc * 2 < before.ipc)
        assertEquals(1, after.refreshes)
    }

    @Test fun afterCacheDroppedOnExternalEdit() {
        val ed = FakeEditor("abcdef", selStart = 0)
        val port = CountingPort(ed)
        val tracker = SelectionTracker(); tracker.reset(0, 0)
        val p = IcProxy({ port }, tracker)
        p.startInput("", true)
        p.begin(); p.insertText("x"); p.end(); tracker.onUpdate(ed.selStart, ed.selEnd)
        p.begin(); p.deleteCodePoints(1); p.end(); tracker.onUpdate(ed.selStart, ed.selEnd)
        p.moveCursor(1); tracker.onUpdate(ed.selStart, ed.selEnd)
        assertEquals(1, ed.selStart)
        // App tự sửa chữ sau con trỏ ⇒ onUpdateSelection lệch ⇒ IME invalidateShadow.
        ed.sb.insert(1, "😀"); p.invalidateShadow()
        p.moveCursor(1)
        assertEquals(3, ed.selStart)                     // qua trọn 😀 (đọc lại, không dùng cache cũ)
    }
}
