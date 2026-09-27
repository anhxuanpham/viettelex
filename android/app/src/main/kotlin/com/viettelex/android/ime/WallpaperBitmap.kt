package com.viettelex.android.ime

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.viettelex.keyboard.WallpaperMath
import java.io.File

/**
 * Bitmap ảnh nền cho IME: giải bằng inSampleSize ở cỡ vừa phủ view (không bao giờ
 * giải bản lớn hơn cần), cache MỘT bitmap theo version + cỡ — input view dựng lại
 * (xoay, đổi theme) không giải lại.
 */
object WallpaperBitmap {
    private var key = ""
    private var bitmap: Bitmap? = null

    @Synchronized
    fun load(file: File, version: Long, viewW: Int, viewH: Int): Bitmap? {
        if (!file.exists() || viewW <= 0 || viewH <= 0) return null
        val k = "$version|$viewW|$viewH|${file.lastModified()}"
        if (k == key) bitmap?.let { return it }
        bitmap = null; key = ""          // nhả bitmap cũ trước khi giải cái mới
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0) return null
        val (needW, needH) = WallpaperMath.fillSize(bounds.outWidth, bounds.outHeight, viewW, viewH)
        val opts = BitmapFactory.Options().apply {
            inSampleSize = WallpaperMath.sampleSize(bounds.outWidth, bounds.outHeight, needW, needH)
        }
        val b = runCatching { BitmapFactory.decodeFile(file.path, opts) }.getOrNull() ?: return null
        bitmap = b; key = k
        return b
    }

    @Synchronized
    fun drop() { bitmap = null; key = "" }
}
