package com.viettelex.android.ui

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.viettelex.android.ime.AssetBlobs
import com.viettelex.android.ime.KeyKind
import com.viettelex.android.ime.KeyLayout
import com.viettelex.android.ime.LayoutConfig
import com.viettelex.android.ime.Plane
import com.viettelex.keyboard.KeyboardData
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.SwipeDecoder
import com.viettelex.keyboard.SwipeLang
import com.viettelex.keyboard.SwipeLayout
import com.viettelex.keyboard.SwipePath
import com.viettelex.keyboard.SwipePractice
import com.viettelex.keyboard.SwipeTrace
import com.viettelex.keyboard.TouchGeometry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Kho nét vuốt luyện tập: JSON Lines trong noBackupFilesDir (không sao lưu đám mây, không
 * gửi mạng). Xuất = tài liệu JSON (SwipePractice.export) ở cache/export → share sheet.
 */
private object TraceStore {
    private fun file(ctx: Context) = File(ctx.noBackupFilesDir, "swipe-traces.jsonl")

    fun count(ctx: Context): Int = file(ctx).takeIf { it.exists() }?.useLines { l -> l.count { it.isNotBlank() } } ?: 0

    fun append(ctx: Context, t: SwipeTrace) = file(ctx).appendText(SwipePractice.line(t) + "\n")

    fun delete(ctx: Context) { file(ctx).delete() }

    fun share(ctx: Context) {
        val f = file(ctx)
        val traces = if (f.exists()) SwipePractice.parseLines(f.readText()) else emptyList()
        val dir = File(ctx.cacheDir, "export").apply { mkdirs() }
        val out = File(dir, "viettelex-swipe-traces.json")
        out.writeText(SwipePractice.export(traces, "android"))
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.export", out)
        val send = Intent(Intent.ACTION_SEND).setType("application/json")
            .putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(Intent.createChooser(send, "Xuất nét vuốt").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/**
 * Luyện vuốt: vuốt từ mục tiêu trên bản sao bàn phím CÙNG hình học (KeyLayout.build như IME)
 * và CÙNG decoder; chấm đúng/sai, độ chính xác phiên. Chỉ lưu nét khi người dùng bật.
 */
@Composable
fun SwipePracticeDialog(onDismiss: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var save by rememberBoolPref(Keys.SWIPE_PRACTICE_SAVE, false)
    val rowAdjust by rememberIntPref(Keys.ROW_HEIGHT_ADJUST, Prefs.D.rowHeightAdjust)
    val seed = remember { System.currentTimeMillis() }
    var index by remember { mutableIntStateOf(0) }
    val target = remember(index) { SwipePractice.target(seed, index) }
    var tries by remember { mutableIntStateOf(0) }
    var hits by remember { mutableIntStateOf(0) }
    var result by remember { mutableStateOf<Pair<Boolean, String>?>(null) }
    var stored by remember { mutableIntStateOf(-1) }
    var confirmDelete by remember { mutableStateOf(false) }
    val decoder = remember { SwipeDecoder() }

    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            if (!KeyboardData.installed) KeyboardData.install(AssetBlobs.provider(ctx.applicationContext.assets))
            stored = TraceStore.count(ctx)
        }
    }

    fun onSwipe(path: SwipePath, layout: SwipeLayout, keys: Map<Char, Pair<Float, Float>>) {
        val t = target
        val pts = (0 until path.count).map { Triple(path.xs[it], path.ys[it], ((path.ts[it] - path.ts[0]) * 1000).toFloat()) }
        scope.launch {
            val top = withContext(Dispatchers.Default) {
                synchronized(decoder) {
                    if (decoder.layout != layout) decoder.setLayout(layout)
                    SwipePractice.decode(decoder, path, t.lang).map { it.folded }
                }
            }
            val ok = top.firstOrNull() == t.folded
            tries++; if (ok) hits++
            result = ok to (top.firstOrNull() ?: "—")
            if (save && stored in 0 until SwipePractice.MAX_TRACES) {
                val trace = SwipeTrace(t.word, t.folded, t.lang, layout.keyWidth, keys, pts, top, System.currentTimeMillis())
                withContext(Dispatchers.IO) { TraceStore.append(ctx, trace) }
                stored++
            }
            if (ok) index++
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(c.groupedBg).safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Luyện vuốt", style = VTType.headline, color = c.label, modifier = Modifier.weight(1f))
                Text("Xong", style = VTType.body, color = c.accent, modifier = Modifier.clickable(onClick = onDismiss))
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                VTSection(footer = if (target.lang == SwipeLang.EN) "Từ tiếng Anh — vuốt đúng từng chữ." else "Vuốt qua các chữ không dấu rồi nhấc tay.") {
                    Column(Modifier.fillMaxWidth().padding(vertical = 18.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(target.word, style = VTType.largeTitle, color = c.label)
                        Text(target.folded.toList().joinToString(" → "), style = VTType.subheadline, color = c.secondary)
                        val r = result
                        Text(when {
                            r == null -> " "
                            r.first -> "✓ Đúng"
                            else -> "✗ Bàn phím đọc thành “${r.second}” — thử lại"
                        }, style = VTType.subheadline, color = if (r?.first == false) c.red else c.green)
                    }
                    RowDivider()
                    VTRow {
                        Text(if (tries == 0) "Phiên này: chưa vuốt" else "Phiên này: $hits/$tries đúng (${hits * 100 / tries}%)",
                            style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
                        Text("Bỏ qua", style = VTType.body, color = c.accent, modifier = Modifier.clickable { result = null; index++ })
                    }
                }
                VTSection(header = "Dữ liệu", footer = "Nét vuốt chỉ nằm trên máy này (không sao lưu, không tự gửi đi). Xuất JSON để gửi cho nhà phát triển nếu bạn muốn giúp gõ vuốt chính xác hơn.") {
                    SettingToggle("Lưu nét vuốt trên máy", if (stored > 0) "Đã lưu $stored nét." else "Tắt: chỉ luyện, không lưu gì.", save) { save = it }
                    if (stored > 0) {
                        RowDivider()
                        VTRow(onClick = { scope.launch(Dispatchers.IO) { TraceStore.share(ctx) } }) {
                            Text("Xuất JSON…", style = VTType.body, color = c.accent)
                        }
                        RowDivider()
                        VTRow(onClick = {
                            if (!confirmDelete) { confirmDelete = true; return@VTRow }
                            confirmDelete = false
                            scope.launch(Dispatchers.IO) { TraceStore.delete(ctx); stored = 0 }
                        }) {
                            Text(if (confirmDelete) "Chạm lần nữa để xoá $stored nét" else "Xoá nét đã lưu", style = VTType.body, color = c.red)
                        }
                    }
                }
            }
            PracticeKeyboard(rowAdjust, ::onSwipe)
        }
    }
}

/** Bản sao plane chữ của IME (KeyLayout.build) + nhận nét vuốt y như KeyboardView (dời yOffset, lọc 1/5 phím). */
@OptIn(ExperimentalComposeUiApi::class)   // PointerInputChange.historical: điểm lịch sử như KeyboardView
@Composable
private fun PracticeKeyboard(rowAdjust: Int, onSwipe: (SwipePath, SwipeLayout, Map<Char, Pair<Float, Float>>) -> Unit) {
    val c = LocalVT.current
    val conf = LocalConfiguration.current
    val density = LocalDensity.current.density
    val tablet = conf.smallestScreenWidthDp >= 600
    val landscape = conf.orientation == Configuration.ORIENTATION_LANDSCAPE
    val areaDp = KeyLayout.keyAreaDp(tablet, landscape, rowAdjust)
    BoxWithConstraints(Modifier.fillMaxWidth().height(areaDp.dp).background(if (c.dark) Color(0xFF2B2B2B) else Color(0xFFD1D3D9))) {
        val widthPx = constraints.maxWidth.toFloat()
        val keys = remember(widthPx, areaDp, density) {
            KeyLayout.build(LayoutConfig(Plane.LETTERS, widthPx, areaDp * density, density, tablet = tablet))
        }
        val centers = remember(keys) { KeyLayout.letterCenters(keys) }
        val layout = remember(centers) {
            val kw = (centers['w']?.first ?: 0f) - (centers['q']?.first ?: 0f)
            if (kw > 0f) SwipeLayout(kw, centers) else null
        }
        val trail = remember { mutableStateListOf<Offset>() }
        val yOff = TouchGeometry.yOffset * density
        val keyColor = if (c.dark) Color(0xFF6B6B6B) else Color.White
        val specialColor = if (c.dark) Color(0xFF474747) else Color(0xFFABB0BA)
        val labelArgb = c.label.toArgb()
        val paint = remember(labelArgb, density) {
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = labelArgb; textSize = 22f * density; textAlign = android.graphics.Paint.Align.CENTER
            }
        }
        val accent = c.accent
        Canvas(Modifier.fillMaxSize().pointerInput(layout) {
            val l = layout ?: return@pointerInput
            awaitEachGesture {
                val down = awaitFirstDown()
                val path = SwipePath(minDistance = l.keyWidth / 5f)
                trail.clear()
                val t0 = down.uptimeMillis
                fun add(o: Offset, t: Long, force: Boolean = false) {
                    path.add(o.x, o.y - yOff, (t - t0) / 1000.0, force)
                    trail.add(o)
                }
                add(down.position, down.uptimeMillis)
                var last = down.position; var lastT = down.uptimeMillis
                while (true) {
                    val ev = awaitPointerEvent()
                    val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
                    for (h in ch.historical) add(h.position, h.uptimeMillis)
                    add(ch.position, ch.uptimeMillis)
                    last = ch.position; lastT = ch.uptimeMillis
                    ch.consume()
                    if (!ch.pressed) break
                }
                add(last, lastT, force = true)
                // Một chạm (≤ 1 phím) không phải nét vuốt
                if (path.length >= l.keyWidth) onSwipe(path, l, centers)
            }
        }) {
            val r = KeyLayout.KEY_RADIUS * density
            for (k in keys) {
                val letter = k.kind == KeyKind.LETTER
                drawRoundRect(if (letter || k.kind == KeyKind.SPACE) keyColor else specialColor,
                    Offset(k.left, k.top), Size(k.width, k.height), CornerRadius(r, r))
                if (letter) drawContext.canvas.nativeCanvas.drawText(k.label, k.centerX, k.centerY + paint.textSize / 3f, paint)
            }
            if (trail.size > 1) {
                val p = Path().apply { moveTo(trail[0].x, trail[0].y); for (o in trail.drop(1)) lineTo(o.x, o.y) }
                drawPath(p, accent.copy(alpha = 0.55f), style = Stroke(width = 6f * density, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}
