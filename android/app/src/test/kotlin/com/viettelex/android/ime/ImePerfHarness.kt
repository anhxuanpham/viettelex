package com.viettelex.android.ime

import com.viettelex.keyboard.ClipboardSource
import com.viettelex.keyboard.FieldTraits
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyboardData
import com.viettelex.keyboard.KeyboardSession
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.SuggestionPlan
import com.viettelex.keyboard.UserLangModel
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileChannel
import java.util.Locale

/**
 * Đo đường xử lý phím trên JVM y như VietTelexIME.onKey: batch IcProxy → session.handle →
 * onUpdateSelection (SelectionTracker) → auto-shift → lượt gợi ý (phần main + phần nền).
 * Chỉ dùng API có từ bản 36d2b6b (để chép nguyên file sang bản baseline mà đo so sánh).
 *
 * Đơn vị: µs mỗi phím (p50/p95/p99), byte cấp phát mỗi phím (ThreadMXBean), IPC mỗi phím
 * (lời gọi EditorPort đọc chữ), IPC clipboard (binder ClipboardManager), CPU ms / 100 phím.
 */
object ImePerf {
    /**
     * Chuỗi phím Telex kiểu chat: có dấu, tiếng Anh, số, dấu câu, ⌫ ('<'), và một đoạn KHÔNG
     * dấu ở cuối (đoạn "Thêm dấu" sẽ mời).
     */
    const val TEXT = "xin chaof moij nguwowif, hoom nay minhf ddi hocj luc 7 gio sangs. " +
        "tooi thichs ddocj sachs vaf nghe nhacj. check mail roi gui file cho anh nhe, gia 150000 dong. " +
        "tahnk< < < thank you very much. ddaay laf mootj caau thuwr nghieemj khas daif ddeer ddo toocs ddooj. " +
        "hom nay troi dep qua minh di choi thoi "

    /** Câu chat gõ KHÔNG dấu (trường hợp tệ nhất cho chip "Thêm dấu": mỗi dấu cách có kế hoạch mới). */
    const val PLAIN = "hom nay troi dep qua minh di choi cong vien voi ban be roi an trua o nha hang gan truong " +
        "chieu ve nha nghi ngoi xem phim va doc sach truoc khi di ngu som "

    fun installAssets() {
        val dir = listOf(File("src/main/assets"), File("app/src/main/assets"), File("android/app/src/main/assets"))
            .first { File(it, Keys.ASSET_LEXICON).exists() }
        KeyboardData.install { name ->
            RandomAccessFile(File(dir, name), "r").use { f -> f.channel.map(FileChannel.MapMode.READ_ONLY, 0, f.length()) }
        }
    }

    fun keys(text: String = TEXT): List<Key> = text.map { c ->
        when {
            c == '<' -> Key.Backspace
            c == ' ' -> Key.Space
            c == '\n' -> Key.Newline
            c.isLetter() -> Key.Letter(c)
            else -> Key.Text(c.toString())
        }
    }

    /** Ô giả đếm mọi lời gọi IPC (đọc chữ / ghi) tới app. */
    class CountingPort(val ed: FakeEditor) : EditorPort by ed {
        var reads = 0; var writes = 0
        override fun textBefore(n: Int): CharSequence? { reads++; return ed.textBefore(n) }
        override fun textAfter(n: Int): CharSequence? { reads++; return ed.textAfter(n) }
        override fun selectedText(): CharSequence? { reads++; return ed.selectedText() }
        override fun commitText(text: CharSequence): Boolean { writes++; return ed.commitText(text) }
        override fun deleteCodePointsBefore(count: Int): Boolean { writes++; return ed.deleteCodePointsBefore(count) }
        override fun deleteBefore(utf16: Int): Boolean { writes++; return ed.deleteBefore(utf16) }
    }

    /** Clipboard giả: mỗi lời gọi = một binder IPC tới ClipboardService trên máy thật. */
    class CountingClip(var hasClip: Boolean = false) : ClipboardSource {
        var ipc = 0
        override var changeCount = 0
        override fun hasText(): Boolean { ipc++; return hasClip }
        override fun readText(): String? { ipc++; return if (hasClip) "0912345678" else null }
    }

    class Result(
        val name: String, val keys: Int,
        val keyP50: Double, val keyP95: Double, val keyP99: Double,
        val sugP50: Double, val sugP95: Double, val sugP99: Double,
        val bgP50: Double, val bgP95: Double, val bgP99: Double,
        val bytesPerKey: Double, val cpuMsPer100: Double,
        val ipcPerKey: Double, val clipIpcPer100: Double,
    ) {
        override fun toString(): String = String.format(Locale.ROOT,
            "%-26s phím µs p50/p95/p99 %6.1f %6.1f %6.1f | gợi ý-main %6.1f %6.1f %6.1f | nền %6.1f %6.1f %6.1f | " +
                "%7.0f B/phím | CPU %6.2f ms/100 phím | IPC đọc %.3f/phím | clip IPC %.2f/100",
            name, keyP50, keyP95, keyP99, sugP50, sugP95, sugP99, bgP50, bgP95, bgP99,
            bytesPerKey, cpuMsPer100, ipcPerKey, clipIpcPer100)
    }

    /** ThreadMXBean qua reflection (unit test app biên dịch với android.jar — không có java.lang.management). */
    private val mx: Any = Class.forName("java.lang.management.ManagementFactory").getMethod("getThreadMXBean").invoke(null)
    private val allocM = Class.forName("com.sun.management.ThreadMXBean").getMethod("getThreadAllocatedBytes", Long::class.javaPrimitiveType)
    private val cpuM = Class.forName("java.lang.management.ThreadMXBean").getMethod("getCurrentThreadCpuTime")
    fun allocated(): Long = allocM.invoke(mx, Thread.currentThread().id) as Long
    fun cpuNs(): Long = cpuM.invoke(mx) as Long

    private fun pct(a: LongArray, n: Int, p: Double): Double {
        val s = a.copyOf(n); s.sort()
        return s[((n - 1) * p).toInt()] / 1000.0
    }

    /**
     * [settings]/[traits]: cấu hình. [prepare]: sau startInput (bật gõ vuốt…). [beforeLetter]:
     * việc lúc chạm phím chữ ngoài session (SmartTouch prior). [suggest]: có chạy lượt gợi ý
     * sau mỗi phím (giả định gõ chậm hơn debounce 30 ms — trường hợp tệ nhất).
     */
    fun run(
        name: String, settings: KeyboardSettings, traits: FieldTraits = FieldTraits(capSentences = true),
        reps: Int = 12, warm: Int = 6, clip: CountingClip = CountingClip(),
        prepare: (KeyboardSession) -> Unit = {},
        beforeLetter: ((KeyboardSession, Char) -> Unit)? = null,
        suggest: Boolean = true,
        text: String = TEXT,
    ): Result {
        val ks = keys(text)
        val model = UserLangModel()
        val session = KeyboardSession(model, clip)
        val total = ks.size * reps
        val keyNs = LongArray(total); val sugNs = LongArray(total); val bgNs = LongArray(total)
        var n = 0; var sn = 0; var bn = 0
        var ipc = 0L
        val clipStart = IntArray(1)
        var bytes = 0L; var cpu = 0L
        for (round in 0 until warm + reps) {
            val measure = round >= warm
            val ed = FakeEditor()
            val port = CountingPort(ed)
            val tracker = SelectionTracker()
            tracker.reset(0, 0)
            val proxy = IcProxy({ port }, tracker)
            proxy.startInput("", true)
            session.startInput(settings, traits)
            prepare(session)
            session.updateAutoShift(proxy)
            if (measure && round == warm) clipStart[0] = clip.ipc
            val b0 = if (measure) allocated() else 0L
            val c0 = if (measure) cpuNs() else 0L
            val r0 = port.reads
            for (k in ks) {
                val t0 = System.nanoTime()
                if (k is Key.Letter) beforeLetter?.invoke(session, k.ch)
                proxy.begin()
                val out = try { session.handle(k, proxy) } finally { proxy.end() }
                proxy.takeFailure()
                if (tracker.onUpdate(ed.selStart, ed.selEnd)) { proxy.invalidateShadow(); session.externalSelectionChange() }
                if (out.needsAutoShift) session.updateAutoShift(proxy)
                val t1 = System.nanoTime()
                if (measure) keyNs[n++] = t1 - t0
                if (suggest) {
                    val t2 = System.nanoTime()
                    when (val plan = session.requestSuggestions(proxy)) {
                        is SuggestionPlan.Ready -> { plan.set?.signature(); if (measure) sugNs[sn++] = System.nanoTime() - t2 }
                        is SuggestionPlan.Background -> {
                            val t3 = System.nanoTime()
                            val r = plan.job.compute()
                            val t4 = System.nanoTime()
                            session.completeSuggestions(plan.job, r)?.signature()
                            val t5 = System.nanoTime()
                            if (measure) { sugNs[sn++] = (t3 - t2) + (t5 - t4); bgNs[bn++] = t4 - t3 }
                        }
                    }
                }
            }
            if (measure) {
                bytes += allocated() - b0
                cpu += cpuNs() - c0
                ipc += port.reads - r0
            }
            session.finishInput()
        }
        val z = LongArray(1)
        return Result(name, total,
            pct(keyNs, n, 0.50), pct(keyNs, n, 0.95), pct(keyNs, n, 0.99),
            if (sn > 0) pct(sugNs, sn, 0.50) else 0.0, if (sn > 0) pct(sugNs, sn, 0.95) else 0.0, if (sn > 0) pct(sugNs, sn, 0.99) else 0.0,
            if (bn > 0) pct(bgNs, bn, 0.50) else 0.0, if (bn > 0) pct(bgNs, bn, 0.95) else 0.0, if (bn > 0) pct(bgNs, bn, 0.99) else pct(z, 1, 0.5),
            bytes.toDouble() / total, cpu / 1e6 / (total / 100.0),
            ipc.toDouble() / total, (clip.ipc - clipStart[0]) * 100.0 / total)
    }

    /** Chạy [f] 3 lượt, lấy lượt có p50 phím nhỏ nhất (chống nhiễu khi máy bận). */
    fun best(f: () -> Result): Result = (0 until 3).map { f() }.minBy { it.keyP50 + it.sugP50 }

    /** Heap đã dùng sau GC (MB) — xấp xỉ RAM Java của dữ liệu đã nạp. */
    fun usedHeapMb(): Double {
        repeat(3) { System.gc(); Thread.sleep(50) }
        val rt = Runtime.getRuntime()
        return (rt.totalMemory() - rt.freeMemory()) / 1_048_576.0
    }
}
