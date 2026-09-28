package com.viettelex.keyboard

import java.util.Locale

/**
 * Khung cắt ảnh nền (trình chỉnh kéo/zoom), CHUẨN HOÁ 0…1 theo ảnh gốc đã lưu (đã xoay
 * EXIF): x, y = góc trên-trái. Tỉ lệ (theo px) = tỉ lệ vùng bàn phím DỌC (gồm strip gợi ý
 * + đệm thanh điều hướng) lúc chỉnh. Không phụ thuộc độ phân giải ⇒ bản gốc lưu lại cỡ khác
 * vẫn đúng vùng.
 *
 * App "nướng" sẵn đúng vùng này vào wallpaper.jpg (≤1080 px, đã mờ) ⇒ IME chỉ giải vùng cắt
 * (vẫn BitmapRegionDecoder + inSampleSize + HARDWARE như RAM-AUDIT #4) — không bao giờ giải
 * bản gốc 2048 px.
 *
 * Bàn phím NGANG: cùng khung, cắt theo tỉ lệ ngang QUANH TÂM khung ([landscape]) — ngang rộng
 * hơn dọc ⇒ giữ bề ngang, lấy dải giữa; luôn nằm trong khung dọc ⇒ đúng bằng phép cắt giữa
 * IME làm trên file đã nướng ([WallpaperMath.visibleCrop]). Đổi chiều cao bàn phím sau khi
 * chỉnh cũng cắt giữa như vậy. Không có khung (ảnh chọn trước bản này) ⇒ cắt giữa như cũ.
 * Cùng công thức với iOS Keyboard/Wallpaper.swift (test hai bên cùng số).
 */
data class WallpaperCrop(val x: Double, val y: Double, val w: Double, val h: Double) {
    val centerX: Double get() = x + w / 2
    val centerY: Double get() = y + h / 2

    /** Tỉ lệ px (rộng/cao) của khung trên ảnh iw×ih. */
    fun aspect(iw: Int, ih: Int): Double = (w * iw) / maxOf(h * ih, 1e-9)

    /** Zoom so với khung phủ cùng tỉ lệ (≥1). */
    fun zoom(iw: Int, ih: Int): Double {
        val c = cover(iw, ih, aspect(iw, ih))
        return if (w > 0) maxOf(1.0, c.w / w) else 1.0
    }

    /** Cùng tâm + zoom, tỉ lệ mới (bàn phím đổi chiều cao rồi mở lại trình chỉnh). */
    fun refit(iw: Int, ih: Int, frameAspect: Double): WallpaperCrop =
        make(iw, ih, frameAspect, zoom(iw, ih), centerX, centerY)

    /** Khung cho bàn phím NGANG (tỉ lệ [a]): quanh tâm khung dọc, nằm TRONG khung dọc. */
    fun landscape(iw: Int, ih: Int, a: Double): WallpaperCrop {
        val pw = w * iw; val ph = h * ih
        if (pw <= 0 || ph <= 0 || a <= 0 || iw <= 0 || ih <= 0) return this
        var lw = pw; var lh = pw / a
        if (lh > ph) { lh = ph; lw = ph * a }
        val nw = lw / iw; val nh = lh / ih
        return WallpaperCrop(centerX - nw / 2, centerY - nh / 2, nw, nh)
    }

    /** [left, top, right, bottom] px nguyên trong ảnh iw×ih (kẹp biên, ≥1 px). */
    fun pixelRect(iw: Int, ih: Int): IntArray {
        val l = Math.round(x * iw).toInt().coerceIn(0, maxOf(iw - 1, 0))
        val t = Math.round(y * ih).toInt().coerceIn(0, maxOf(ih - 1, 0))
        val r = Math.round((x + w) * iw).toInt().coerceAtLeast(l + 1).coerceAtMost(iw)
        val b = Math.round((y + h) * ih).toInt().coerceAtLeast(t + 1).coerceAtMost(ih)
        return intArrayOf(l, t, r, b)
    }

    /** "x,y,w,h" (dấu chấm, 5 số lẻ) — cùng định dạng iOS. */
    fun serialize(): String = listOf(x, y, w, h).joinToString(",") { String.format(Locale.ROOT, "%.5f", it) }

    companion object {
        const val MAX_ZOOM = 5.0

        /** Khung phủ kín (zoom 1) giữa ảnh — cũng là mặc định cho ảnh cũ chưa có khung. */
        fun cover(iw: Int, ih: Int, frameAspect: Double) = make(iw, ih, frameAspect, 1.0, 0.5, 0.5)

        /**
         * Khung tỉ lệ [frameAspect] (rộng/cao px), zoom 1…[MAX_ZOOM] (1 = vừa phủ — không bao giờ
         * lộ viền), tâm (chuẩn hoá) kẹp để khung luôn nằm trong ảnh.
         */
        fun make(iw: Int, ih: Int, frameAspect: Double, zoom: Double, cx: Double, cy: Double): WallpaperCrop {
            val bw = maxOf(iw, 1).toDouble(); val bh = maxOf(ih, 1).toDouble()
            val a = if (frameAspect > 0 && frameAspect.isFinite()) frameAspect else 1.0
            var cw = bw; var ch = bw / a           // phủ: chạm hai mép trái-phải…
            if (ch > bh) { ch = bh; cw = bh * a }   // …hoặc trên-dưới
            val z = (if (zoom.isFinite()) zoom else 1.0).coerceIn(1.0, MAX_ZOOM)
            val w = cw / z / bw; val h = ch / z / bh
            val x = (if (cx.isFinite()) cx else 0.5).coerceIn(w / 2, 1 - w / 2)
            val y = (if (cy.isFinite()) cy else 0.5).coerceIn(h / 2, 1 - h / 2)
            return WallpaperCrop(x - w / 2, y - h / 2, w, h)
        }

        fun fromPixelRect(r: IntArray, iw: Int, ih: Int): WallpaperCrop {
            val bw = maxOf(iw, 1).toDouble(); val bh = maxOf(ih, 1).toDouble()
            return WallpaperCrop(r[0] / bw, r[1] / bh, (r[2] - r[0]) / bw, (r[3] - r[1]) / bh)
        }

        /** Sai định dạng / ngoài biên ⇒ null (= cắt giữa như cũ). */
        fun parse(s: String?): WallpaperCrop? {
            if (s == null) return null
            val v = s.split(",").mapNotNull { it.trim().toDoubleOrNull() }
            if (v.size != 4 || v.any { !it.isFinite() }) return null
            val eps = 1e-3
            if (v[2] <= 0 || v[3] <= 0 || v[0] < -eps || v[1] < -eps || v[0] + v[2] > 1 + eps || v[1] + v[3] > 1 + eps) return null
            val x = maxOf(0.0, v[0]); val y = maxOf(0.0, v[1])
            return WallpaperCrop(x, y, minOf(v[2], 1 - x), minOf(v[3], 1 - y))
        }
    }
}
