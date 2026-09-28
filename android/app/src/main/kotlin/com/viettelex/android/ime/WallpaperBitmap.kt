package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Build
import com.viettelex.keyboard.WallpaperMath
import java.io.File

/**
 * Bitmap ảnh nền cho IME (RAM-AUDIT #4). File đã được app cắt sẵn theo khung người dùng chỉnh
 * ([com.viettelex.keyboard.WallpaperCrop]; ảnh cũ = cả ảnh). Chỉ giải VÙNG THẤY ĐƯỢC (center-crop theo tỉ lệ
 * view, BitmapRegionDecoder) ở inSampleSize như trước (vừa phủ view, không bao giờ lớn hơn
 * cần) ⇒ cùng điểm ảnh trên màn, bớt phần bị cắt. Cửa sổ vẽ bằng GPU ⇒ chuyển sang
 * [Bitmap.Config.HARDWARE]: điểm ảnh chỉ nằm ở GPU (texture vốn đã có), bỏ bản CPU ở native
 * heap; chất lượng giữ ARGB_8888 (không vằn như RGB_565). Cache MỘT bitmap theo version +
 * cỡ — input view dựng lại (xoay, đổi theme) không giải lại.
 */
object WallpaperBitmap {
    private var key = ""
    private var bitmap: Bitmap? = null

    @Synchronized
    fun load(file: File, version: Long, viewW: Int, viewH: Int, hardware: Boolean = false): Bitmap? {
        if (!file.exists() || viewW <= 0 || viewH <= 0) return null
        val k = "$version|$viewW|$viewH|$hardware|${file.lastModified()}"
        if (k == key) bitmap?.let { return it }
        bitmap = null; key = ""          // nhả bitmap cũ trước khi giải cái mới
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0) return null
        val plan = WallpaperMath.decodePlan(bounds.outWidth, bounds.outHeight, viewW, viewH)
        val sample = plan[4]
        val cpu = decodeCrop(file, bounds.outWidth, bounds.outHeight, plan)
            ?: runCatching { BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) }.getOrNull()
            ?: return null
        val b = if (hardware) toHardware(cpu) else cpu
        bitmap = b; key = k
        return b
    }

    private fun decodeCrop(file: File, w: Int, h: Int, c: IntArray): Bitmap? = runCatching {
        val sample = c[4]
        if (c[0] == 0 && c[1] == 0 && c[2] == w && c[3] == h) return@runCatching null   // thấy cả ảnh
        @Suppress("DEPRECATION")
        val d = if (Build.VERSION.SDK_INT >= 31) BitmapRegionDecoder.newInstance(file.path)
            else BitmapRegionDecoder.newInstance(file.path, false)
        try {
            d?.decodeRegion(Rect(c[0], c[1], c[2], c[3]), BitmapFactory.Options().apply {
                inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888
            })
        } finally { d?.recycle() }
    }.getOrNull()

    /** Bản GPU (API 26+); lỗi (driver không hỗ trợ) ⇒ giữ bản CPU. */
    private fun toHardware(b: Bitmap): Bitmap {
        val hw = runCatching { b.copy(Bitmap.Config.HARDWARE, false) }.getOrNull() ?: return b
        b.recycle()
        return hw
    }

    @Synchronized
    fun drop() { bitmap = null; key = "" }
}
