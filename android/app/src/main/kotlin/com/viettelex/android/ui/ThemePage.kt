package com.viettelex.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.KeyboardTheme
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ThemeGate
import com.viettelex.keyboard.ThemePalette
import com.viettelex.keyboard.ThemeSettings
import com.viettelex.keyboard.WallpaperMath
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Ảnh nền: app thu nhỏ (inSampleSize + scale ≤1080px, xoay theo EXIF), mờ (hộp 3 lượt),
 * nén JPEG ≤400KB → filesDir/wallpaper.jpg (IME cùng process đọc). Bản chưa mờ giữ
 * riêng để đổi độ mờ không cần chọn lại ảnh.
 */
object WallpaperStore {
    fun file(ctx: Context) = File(ctx.filesDir, Keys.WALLPAPER_FILE)
    private fun src(ctx: Context) = File(ctx.filesDir, Keys.WALLPAPER_SRC_FILE)

    /** Ảnh từ picker → bitmap ≤ MAX_EDGE (không giải bản gốc full-size). */
    fun decodeSmall(ctx: Context, uri: Uri): Bitmap? {
        val cr = ctx.contentResolver
        val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, b) }
        if (b.outWidth <= 0) return null
        val (tw, th) = WallpaperMath.targetSize(b.outWidth, b.outHeight)
        val o = BitmapFactory.Options().apply { inSampleSize = WallpaperMath.sampleSize(b.outWidth, b.outHeight, tw, th) }
        var bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, o) } ?: return null
        val (sw, sh) = WallpaperMath.targetSize(bmp.width, bmp.height)
        if (sw != bmp.width) bmp = Bitmap.createScaledBitmap(bmp, sw, sh, true)
        val rot = runCatching {
            when (cr.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        }.getOrDefault(0)
        if (rot != 0) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(rot.toFloat()) }, true)
        return bmp
    }

    fun encode(bmp: Bitmap): ByteArray {
        var q = 80
        while (true) {
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, q, out)
            if (out.size() <= WallpaperMath.MAX_BYTES || q <= 40) return out.toByteArray()
            q -= 10
        }
    }

    fun blurred(bmp: Bitmap, radius: Int): Bitmap {
        if (radius <= 0) return bmp
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        WallpaperMath.blur(px, bmp.width, bmp.height, radius)
        return Bitmap.createBitmap(px, bmp.width, bmp.height, Bitmap.Config.ARGB_8888)
    }

    fun import(ctx: Context, uri: Uri, blur: Int): Boolean {
        val small = decodeSmall(ctx, uri) ?: return false
        src(ctx).writeBytes(encode(small))
        file(ctx).writeBytes(encode(blurred(small, blur)))
        return true
    }

    fun reblur(ctx: Context, blur: Int): Boolean {
        val s = src(ctx).takeIf { it.exists() } ?: return false
        val bmp = BitmapFactory.decodeFile(s.path) ?: return false
        file(ctx).writeBytes(encode(blurred(bmp, blur)))
        return true
    }

    fun remove(ctx: Context) { file(ctx).delete(); src(ctx).delete() }

    fun preview(ctx: Context): ImageBitmap? {
        val f = file(ctx).takeIf { it.exists() } ?: return null
        val o = BitmapFactory.Options().apply { inSampleSize = 2 }
        return BitmapFactory.decodeFile(f.path, o)?.asImageBitmap()
    }
}

private fun loadThemeSettings(ctx: Context): ThemeSettings {
    val all = Prefs.of(ctx).all
    return ThemeSettings.load { all[it] }
}

private fun saveThemeSettings(ctx: Context, s: ThemeSettings) {
    Prefs.of(ctx).edit().apply {
        putString(Keys.KEYBOARD_THEME, s.theme.id)
        putBoolean(Keys.WALLPAPER_ENABLED, s.wallpaper)
        putInt(Keys.WALLPAPER_DIM, s.dim)
        putInt(Keys.WALLPAPER_BLUR, s.blur)
        putLong(Keys.WALLPAPER_VERSION, s.version)
    }.apply()
}

/** Dòng trong section Giao diện mở trang theme. */
@Composable
fun ThemeRow(onOpen: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val current = remember { loadThemeSettings(ctx).theme.title }
    VTRow(onClick = onOpen) {
        Text("Theme & ảnh nền", style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
        Text("$current ›", style = VTType.body, color = c.secondary)
    }
}

/** Palette để xem trước trong app: SYSTEM mô phỏng màu sáng/tối mặc định. */
private fun previewPalette(t: KeyboardTheme, dark: Boolean): ThemePalette = t.palette(dark) ?: if (dark)
    ThemePalette(bg = 0xFF1F1F1F.toInt(), keyFill = 0xFF3C3C3F.toInt(), specialFill = 0xFF2B2F36.toInt(),
        ink = 0xFFE3E3E3.toInt(), trail = 0xFFA8C7FA.toInt(), balloon = 0xFF4A4A4E.toInt(), popup = 0xFF3C3C3F.toInt(),
        action = 0xFFA8C7FA.toInt(), actionInk = 0xFF062E6F.toInt(), chip = 0xFF004A77.toInt(), isDark = true)
else ThemePalette(bg = 0xFFEEF0F4.toInt(), keyFill = 0xFFFFFFFF.toInt(), specialFill = 0xFFD6DBE3.toInt(),
    ink = 0xFF1F1F1F.toInt(), trail = 0xFF0B57D0.toInt(), balloon = 0xFFFFFFFF.toInt(), popup = 0xFFFFFFFF.toInt(),
    action = 0xFF0B57D0.toInt(), actionInk = 0xFFFFFFFF.toInt(), chip = 0xFFD3E3FD.toInt(), isDark = false)

@Composable
fun ThemePage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    BackHandler(onBack = onBack)
    val dark = (ctx.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
        android.content.res.Configuration.UI_MODE_NIGHT_YES
    var s by remember { mutableStateOf(loadThemeSettings(ctx)) }
    var wall by remember { mutableStateOf(WallpaperStore.preview(ctx)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    fun update(n: ThemeSettings) { s = n; saveThemeSettings(ctx, n) }

    fun afterWrite(ok: Boolean, enable: Boolean) {
        busy = false
        if (!ok) { error = "Không đọc được ảnh này."; return }
        error = null
        wall = WallpaperStore.preview(ctx)
        update(s.copy(wallpaper = if (enable) true else s.wallpaper, version = System.currentTimeMillis()))
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        busy = true
        val blur = s.blur
        scope.launch {
            val ok = withContext(Dispatchers.Default) { runCatching { WallpaperStore.import(ctx, uri, blur) }.getOrDefault(false) }
            afterWrite(ok, enable = true)
        }
    }

    VTRow(onClick = onBack) { Text("‹ Tính Năng", style = VTType.body, color = c.accent) }

    val active = s.wallpaperActive(wall != null)
    val pal = (s.effectiveTheme.palette(dark) ?: previewPalette(KeyboardTheme.SYSTEM, dark)).let { if (active) it.overWallpaper() else it }
    VTSection(footer = "Áp dụng lần mở bàn phím kế tiếp.") {
        KeyboardPreview(pal, if (active) wall else null, s.dim, large = true,
            modifier = Modifier.fillMaxWidth().height(180.dp))
    }

    if (!ThemeGate.allowsWallpaper) {
        VTSection(footer = "Theme có nhãn Plus và ảnh nền thuộc VietTelex Plus (Giới Thiệu → VietTelex Plus). Hệ thống, Tối OLED và Tương phản cao luôn miễn phí.") {}
    }

    VTSection(header = "Theme") {
        KeyboardTheme.entries.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { t ->
                    val locked = !ThemeGate.allows(t)
                    val selected = s.theme == t
                    Column(Modifier.weight(1f).clickable(enabled = !locked) { update(s.copy(theme = t)) },
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        KeyboardPreview(previewPalette(t, dark), null, 0, large = false,
                            modifier = Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(8.dp))
                                .border(if (selected) 3.dp else 1.dp, if (selected) c.accent else c.separator, RoundedCornerShape(8.dp)))
                        Text(t.title + if (t.isPlus) " · Plus" else "", style = VTType.footnote,
                            color = if (locked) c.secondary else c.label, maxLines = 1)
                    }
                }
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }

    VTSection(header = "Ảnh nền · Plus",
        footer = "Ảnh được thu nhỏ và nén ngay trên máy, không gửi đi đâu. Lớp phủ giúp chữ trên phím dễ đọc.") {
        VTRow(onClick = if (busy || !ThemeGate.allowsWallpaper) null else {
            { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
        }) {
            Text(if (wall != null) "Đổi ảnh nền" else "Chọn ảnh nền", style = VTType.body,
                color = if (ThemeGate.allowsWallpaper) c.accent else c.secondary)
        }
        if (wall != null) {
            RowDivider()
            SettingToggle("Dùng ảnh nền", null, s.wallpaper) { update(s.copy(wallpaper = it)) }
            RowDivider()
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text("Độ tối lớp phủ: ${s.dim}%", style = VTType.body, color = c.label)
                Slider(value = s.dim.toFloat(), onValueChange = { update(s.copy(dim = (it / 5).toInt() * 5)) }, valueRange = 0f..80f)
                Text("Độ mờ ảnh: ${s.blur}", style = VTType.body, color = c.label)
                Slider(value = s.blur.toFloat(), onValueChange = { s = s.copy(blur = it.toInt()) }, valueRange = 0f..20f,
                    onValueChangeFinished = {
                        busy = true
                        val blur = s.blur
                        scope.launch {
                            val ok = withContext(Dispatchers.Default) { runCatching { WallpaperStore.reblur(ctx, blur) }.getOrDefault(false) }
                            afterWrite(ok, enable = false)
                        }
                    })
            }
            RowDivider()
            VTRow(onClick = {
                WallpaperStore.remove(ctx); wall = null
                update(s.copy(wallpaper = false, version = System.currentTimeMillis()))
            }) { Text("Xoá ảnh nền", style = VTType.body, color = c.red) }
        }
        if (busy) VTRow { Text("Đang xử lý ảnh…", style = VTType.footnote, color = c.secondary) }
        error?.let { VTRow { Text(it, style = VTType.footnote, color = c.red) } }
    }
}

/** Bàn phím thu nhỏ vẽ bằng đúng token theme. */
@Composable
private fun KeyboardPreview(p: ThemePalette, wallpaper: ImageBitmap?, dim: Int, large: Boolean, modifier: Modifier) {
    Box(modifier) {
        val bottom = p.bgBottom
        Canvas(Modifier.fillMaxSize()) {
            if (bottom != null) drawRect(Brush.verticalGradient(listOf(Color(p.bg), Color(bottom))))
            else drawRect(Color(p.bg))
        }
        if (wallpaper != null) {
            Image(wallpaper, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Canvas(Modifier.fillMaxSize()) { drawRect(Color(p.wallpaperOverlay).copy(alpha = dim / 100f)) }
        }
        Canvas(Modifier.fillMaxSize()) {
            val pad = if (large) 6.dp.toPx() else 3.dp.toPx()
            val gap = if (large) 5.dp.toPx() else 2.dp.toPx()
            val r = if (large) 6.dp.toPx() else 2.dp.toPx()
            val kw = (size.width - pad * 2 - gap * 9) / 10
            val kh = (size.height - pad * 2 - gap * 3) / 4
            fun key(x: Float, y: Float, w: Float, fill: Int) {
                drawRoundRect(Color(fill), Offset(x, y), Size(w, kh), CornerRadius(r))
                p.keyBorder?.let { drawRoundRect(Color(it), Offset(x, y), Size(w, kh), CornerRadius(r), style = Stroke(1.dp.toPx())) }
                if (large) drawCircle(Color(p.ink).copy(alpha = 0.8f), minOf(w, kh) * 0.09f, Offset(x + w / 2, y + kh / 2))
            }
            val counts = intArrayOf(10, 9, 7)
            for (row in 0..2) {
                val n = counts[row]
                val x0 = pad + (10 - n) * (kw + gap) / 2
                for (i in 0 until n) key(x0 + i * (kw + gap), pad + row * (kh + gap), kw, p.keyFill)
            }
            val y = pad + 3 * (kh + gap)
            key(pad, y, kw * 2 + gap, p.specialFill)
            key(pad + 2 * (kw + gap), y, kw * 6 + gap * 5, p.keyFill)
            key(pad + 8 * (kw + gap), y, kw * 2 + gap, p.action)
        }
    }
}
