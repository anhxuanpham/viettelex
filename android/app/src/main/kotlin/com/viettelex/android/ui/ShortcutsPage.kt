package com.viettelex.android.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.ShortcutFile
import com.viettelex.keyboard.ShortcutTable

/**
 * Gõ tắt — bảng lưu pref [Keys.SHORTCUTS] dạng CHÍNH file YAML macOS ([ShortcutFile]); IME
 * đọc qua KeyboardSettings.load (đổi lúc bàn phím đang mở ⇒ áp ngay, [Keys.ENGINE_KEYS]).
 */
object ShortcutsStore {
    fun load(ctx: Context): Map<String, String> = ShortcutFile.parse(Prefs.of(ctx).getString(Keys.SHORTCUTS, null))
    fun save(ctx: Context, t: Map<String, String>) {
        Prefs.of(ctx).edit().putString(Keys.SHORTCUTS, ShortcutFile.exportYAML(t)).apply()
    }
}

/** Section trong Tính Năng: bật/tắt + mở trang quản lý. */
@Composable
fun ShortcutsSection(onOpen: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    var enabled by rememberBoolPref(Keys.SHORTCUTS_ENABLED, Prefs.D.shortcutsEnabled)
    val count = remember { ShortcutsStore.load(ctx).size }
    VTSection(header = "Gõ tắt") {
        SettingToggle("Gõ tắt", "Gõ chữ tắt rồi dấu cách/dấu câu để bung: ko → không, Ko → Không, KO → KHÔNG. ⌫ ngay sau đó trả lại chữ đã gõ.", enabled) { enabled = it }
        RowDivider()
        VTRow(onClick = onOpen) {
            Text("Bảng gõ tắt", style = VTType.body, color = c.label, modifier = Modifier.weight(1f))
            Text(if (count == 0) "Trống  ›" else "$count mục  ›", style = VTType.body, color = c.secondary)
        }
    }
}

@Composable
fun ShortcutsPage(onBack: () -> Unit) {
    val c = LocalVT.current
    val ctx = LocalContext.current
    BackHandler(onBack = onBack)
    var table by remember { mutableStateOf(ShortcutsStore.load(ctx)) }
    var query by rememberSaveable { mutableStateOf("") }
    var newKey by rememberSaveable { mutableStateOf("") }
    var newValue by rememberSaveable { mutableStateOf("") }
    var editing by remember { mutableStateOf<String?>(null) }
    var editKey by remember { mutableStateOf("") }
    var editValue by remember { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    fun persist(t: Map<String, String>) { table = t; ShortcutsStore.save(ctx, t) }

    VTRow(onClick = onBack) { Text("‹ Tính Năng", style = VTType.body, color = c.accent) }

    val q = query.trim().lowercase()
    val rows = table.keys.sorted().filter { q.isEmpty() || it.lowercase().contains(q) || table.getValue(it).lowercase().contains(q) }
    VTSection(header = "Bảng gõ tắt (${table.size})", footer = "Chạm một dòng để sửa hoặc xoá.") {
        VTRow { VTTextField(query, { query = it }, "Tìm chữ tắt hoặc nội dung…", capitalization = KeyboardCapitalization.None) }
        rows.forEach { k ->
            key(k) {
                RowDivider()
                if (editing == k) {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        VTTextField(editKey, { editKey = it }, "Chữ tắt", capitalization = KeyboardCapitalization.None)
                        VTTextField(editValue, { editValue = it }, "Nội dung", maxLines = 6)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Lưu", style = VTType.body, color = c.accent, modifier = Modifier.clickable {
                                val nk = editKey.trim(); val nv = editValue.trim()
                                when {
                                    !ShortcutTable.isValidKey(nk) -> notice = "Chữ tắt không được chứa khoảng trắng."
                                    nv.isEmpty() -> {}
                                    nk != k && table.containsKey(nk) -> notice = "“$nk” đã có."
                                    else -> { persist(table - k + (nk to nv)); editing = null; notice = null }
                                }
                            })
                            Text("Xoá", style = VTType.body, color = c.red, modifier = Modifier.padding(start = 24.dp).clickable {
                                persist(table - k); editing = null
                            })
                            Box(Modifier.weight(1f))
                            Text("Huỷ", style = VTType.body, color = c.secondary, modifier = Modifier.clickable { editing = null })
                        }
                    }
                } else {
                    VTRow(onClick = { editKey = k; editValue = table.getValue(k); editing = k }) {
                        Text(k, style = VTType.body.copy(fontFamily = FontFamily.Monospace), color = c.label)
                        Text("→", style = VTType.footnote, color = c.secondary, modifier = Modifier.padding(horizontal = 8.dp))
                        Text(table.getValue(k), style = VTType.body, color = c.label, maxLines = 3, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        if (table.isEmpty()) {
            RowDivider()
            VTRow { Text("Chưa có gõ tắt nào. Thêm bên dưới, hoặc bấm “Thêm bộ gợi ý”.", style = VTType.body, color = c.secondary) }
        } else if (rows.isEmpty()) {
            RowDivider()
            VTRow { Text("Không tìm thấy.", style = VTType.body, color = c.secondary) }
        }
    }

    VTSection(header = "Thêm mới",
        footer = "Bung khi gõ dấu cách, Enter hoặc dấu câu ngay sau chữ tắt. Viết chữ tắt thường để tự theo hoa/thường khi gõ. Chữ tắt có ký hiệu hoặc số (->, k2) bung khi gõ dấu cách. Không bung khi dính liền sau số hoặc / # @ (5h, /h3), trong ô mật khẩu, email, địa chỉ web.") {
        VTRow { VTTextField(newKey, { newKey = it }, "Chữ tắt (vd: ko, cty, ->)", capitalization = KeyboardCapitalization.None) }
        RowDivider()
        VTRow { VTTextField(newValue, { newValue = it }, "Nội dung đầy đủ (được nhiều dòng)", maxLines = 6) }
        RowDivider()
        val canAdd = newKey.isNotBlank() && newValue.isNotBlank()
        VTRow(onClick = if (canAdd) ({
            val k = newKey.trim(); val v = newValue.trim()
            when {
                !ShortcutTable.isValidKey(k) -> notice = "Chữ tắt không được chứa khoảng trắng."
                table.containsKey(k) -> notice = "“$k” đã có — chạm dòng đó để sửa."
                else -> { persist(table + (k to v)); newKey = ""; newValue = ""; notice = null }
            }
        }) else null) {
            GlyphIcon(Glyph.Plus, if (canAdd) c.accent else c.tertiary, 20.dp)
            Text("Thêm", style = VTType.body, color = if (canAdd) c.accent else c.tertiary, modifier = Modifier.padding(start = 16.dp))
        }
        notice?.let {
            RowDivider()
            VTRow { Text(it, style = VTType.footnote, color = c.secondary) }
        }
    }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching { ctx.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() } }.getOrNull()
        if (text == null) { notice = "Không đọc được file."; return@rememberLauncherForActivityResult }
        val imported = ShortcutFile.parse(text)
        if (imported.isEmpty()) { notice = "File không có gõ tắt nào."; return@rememberLauncherForActivityResult }
        val (merged, added, replaced) = ShortcutFile.merge(table, imported)
        persist(merged)
        notice = "Đã nhập ${imported.size} mục: $added mới, $replaced ghi đè."
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/x-yaml")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            ctx.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(ShortcutFile.exportYAML(table).toByteArray()) }
        }.isSuccess
        notice = if (ok) "Đã xuất ${table.size} gõ tắt." else "Không ghi được file."
    }
    VTSection(footer = "Bộ gợi ý: ${ShortcutFile.SUGGESTED.keys.sorted().joinToString(", ")}. File YAML “chữ tắt: nội dung” dùng chung với VietTelex trên Mac và iPhone; nhập sẽ gộp (mục trùng lấy theo file).") {
        VTRow(onClick = {
            val missing = ShortcutFile.SUGGESTED.filterKeys { it !in table }
            persist(table + missing)
            notice = if (missing.isEmpty()) "Bộ gợi ý đã có đủ." else "Đã thêm ${missing.size} gõ tắt gợi ý."
        }) {
            Text("✦", color = c.accent, modifier = Modifier.size(20.dp))
            Text("Thêm bộ gợi ý", style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 16.dp))
        }
        RowDivider(52.dp)
        VTRow(onClick = { importer.launch(arrayOf("*/*")) }) {
            GlyphIcon(Glyph.Import, c.accent, 20.dp)
            Text("Nhập từ file…", style = VTType.body, color = c.accent, modifier = Modifier.padding(start = 16.dp))
        }
        RowDivider(52.dp)
        VTRow(onClick = if (table.isEmpty()) null else ({ exporter.launch("viettelex-go-tat.yml") })) {
            GlyphIcon(Glyph.Export, if (table.isEmpty()) c.tertiary else c.accent, 20.dp)
            Text("Xuất ra YAML…", style = VTType.body, color = if (table.isEmpty()) c.tertiary else c.accent,
                modifier = Modifier.padding(start = 16.dp))
        }
    }
}
