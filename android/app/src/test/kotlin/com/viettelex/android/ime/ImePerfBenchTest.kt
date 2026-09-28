package com.viettelex.android.ime

import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.KPoint
import com.viettelex.keyboard.KRect
import com.viettelex.keyboard.ShortcutFile
import com.viettelex.keyboard.ShortcutTable
import com.viettelex.keyboard.TelexKeyPrior
import com.viettelex.keyboard.TouchTarget
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test

/**
 * Benchmark hiệu năng đường gõ (bộ CHẬM: VT_SLOW_TESTS=1). In bảng B/C/D; baseline A đo
 * bằng cùng [ImePerf] trên bản 36d2b6b. Ngưỡng RỘNG — chỉ bắt hồi quy lớn.
 */
class ImePerfBenchTest {
    companion object {
        @BeforeClass @JvmStatic fun setup() { ImePerf.installAssets() }

        /** C: mọi tính năng phụ (thêm sau baseline) TẮT. */
        fun lean() = KeyboardSettings(smartTouch = false, swipeTyping = false, shortcutsEnabled = false,
            addTonesChip = false, numberChips = false, mathResults = false)

        /** D: bật hết. */
        fun full() = KeyboardSettings(smartTouch = true, swipeTyping = true, swipeEnglish = true,
            shortcutsEnabled = true, clipboardHistory = true, addTonesChip = true, numberChips = true, mathResults = true,
            shortcuts = ShortcutTable(ShortcutFile.parse("ko: không\nvs: với\ndc: được\nbn: bao nhiêu\n")))

        /** Hàng phím chữ giả (QWERTY 10×3, phím 100×150) cho TouchTarget — chạm sát mép (ngoài lõi). */
        private val rows = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        private val rects = ArrayList<KRect>(); private val chars = StringBuilder()
        init {
            rows.forEachIndexed { r, s -> s.forEachIndexed { i, c ->
                val l = i * 100f + r * 50f; rects.add(KRect(l, r * 150f, l + 100f, r * 150f + 150f)); chars.append(c) } }
        }
        private val charArr = chars.toString().toCharArray()

        /** Như VietTelexIME.smartTouchPrior + SmartTouch.refine khi chạm sát mép phím. */
        val smartTouch: (com.viettelex.keyboard.KeyboardSession, Char) -> Unit = { s, ch ->
            val prior = TelexKeyPrior.sharedIfReady?.forTyping(s.bridge.rawWord, s.bridge.vniMode)
            val idx = chars.indexOf(ch.lowercaseChar())
            if (prior != null && idx >= 0) {
                val r = rects[idx]
                TouchTarget.choose(KPoint(r.left + 3f, (r.top + r.bottom) / 2), rects, charArr, idx, prior)
            }
        }
    }

    @Test fun benchTable() {
        assumeTrue("Test chậm — VT_SLOW_TESTS=1", System.getenv("VT_SLOW_TESTS") == "1")
        TelexKeyPrior.warmUp()
        ImePerf.run("khởi động JIT (bỏ)", full(), prepare = { it.setSwipeTyping(true) }, beforeLetter = smartTouch)
        val b = ImePerf.best { ImePerf.run("B main mặc định", KeyboardSettings(), beforeLetter = smartTouch) }
        val c = ImePerf.best { ImePerf.run("C main tắt tính năng phụ", lean()) }
        val c0 = ImePerf.best { ImePerf.run("C0 C + tắt thanh gợi ý", lean().also { it.showSuggestions = false }) }
        val d = ImePerf.best { ImePerf.run("D main bật hết", full(), clip = ImePerf.CountingClip(hasClip = true),
            prepare = { it.setSwipeTyping(true) }, beforeLetter = smartTouch) }
        val bOld = ImePerf.best { ImePerf.run("B' như trước (chip Thêm dấu bật)", KeyboardSettings(addTonesChip = true), beforeLetter = smartTouch) }
        val pOff = ImePerf.best { ImePerf.run("không dấu, chip TẮT", KeyboardSettings(), text = ImePerf.PLAIN) }
        val pOn = ImePerf.best { ImePerf.run("không dấu, chip BẬT", KeyboardSettings(addTonesChip = true), text = ImePerf.PLAIN) }
        for (r in listOf(b, bOld, c, c0, d, pOff, pOn)) println("PERF $r")
        val h1 = ImePerf.usedHeapMb()
        TelexKeyPrior.release()
        val h2 = ImePerf.usedHeapMb()
        println("HEAP %.1f MB; nhả trie chọn phím thông minh: -%.1f MB".format(h1, h1 - h2))
        // Ngưỡng RỘNG (máy CI/Mac có thể rất bận): chỉ bắt hồi quy cỡ bậc.
        assertTrue("phím p50 ${b.keyP50} µs", b.keyP50 < 200)
        assertTrue("gợi ý main p95 ${b.sugP95} µs", b.sugP95 < 5_000)
        assertTrue("C không được tệ hơn B nhiều", c.keyP50 < b.keyP50 * 3 + 20)
        assertTrue("IPC đọc/phím ${b.ipcPerKey}", b.ipcPerKey < 0.1)
        assertTrue("byte/phím ${b.bytesPerKey}", b.bytesPerKey < 200_000)
    }
}
