package com.viettelex.android

import com.viettelex.keyboard.L10nTable
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Độ phủ bảng dịch theo mã nguồn: (1) mọi `tr("…")` trong app + :keyboard và mọi chữ Việt ở
 * dòng đánh dấu `// l10n-key` (tên enum hiển thị qua `tr(viTitle)`) đều có bản dịch English;
 * (2) giao diện app (ui/, plus/) và chữ hiện trên bàn phím (ime/) không còn chuỗi tiếng Việt
 * nằm ngoài `tr(` — trừ dòng `// l10n-skip` (song ngữ sẵn) và log gỡ lỗi.
 */
class L10nCoverageTest {
    private fun dir(vararg c: String): File =
        c.map { File(it) }.first { it.isDirectory }

    private val appSrc = dir("src/main/kotlin", "app/src/main/kotlin")
    private val kbSrc = dir("../keyboard/src/main/kotlin", "keyboard/src/main/kotlin")

    private val vn = Regex("[àáảãạăắằẳẵặâấầẩẫậđèéẻẽẹêếềểễệìíỉĩịòóỏõọôốồổỗộơớờởỡợùúủũụưứừửữựỳýỷỹỵĐÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬÊẾỀỂỄỆÔỐỒỔỖỘƠỚỜỞỠỢƯỨỪỬỮỰÍÌỈĨỊÚÙỦŨỤÝỲỶỸỴÉÈẺẼẸÓÒỎÕỌ]")
    private val literal = Regex("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")

    /** Phần code của dòng (bỏ chú thích `//` nằm ngoài chuỗi). */
    private fun code(line: String): String {
        var inStr = false; var i = 0
        while (i < line.length) {
            val c = line[i]
            if (inStr) { if (c == '\\') i++ else if (c == '"') inStr = false }
            else if (c == '"') inStr = true
            else if (c == '/' && i + 1 < line.length && line[i + 1] == '/') return line.substring(0, i)
            i++
        }
        return line
    }

    private fun unescape(s: String): String {
        val sb = StringBuilder(); var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '\\' && i + 1 < s.length) {
                when (val e = s[i + 1]) {
                    'n' -> sb.append('\n'); 't' -> sb.append('\t'); 'u' -> { sb.append(s.substring(i + 2, i + 6).toInt(16).toChar()); i += 4 }
                    else -> sb.append(e)
                }
                i += 2
            } else { sb.append(c); i++ }
        }
        return sb.toString()
    }

    private fun lines(root: File) = root.walkTopDown().filter { it.extension == "kt" && it.name != "L10nTable.kt" }
        .flatMap { f -> f.readLines().mapIndexed { n, l -> Triple(f, n + 1, l) } }
        .filter { (_, _, l) -> !l.trimStart().let { it.startsWith("*") || it.startsWith("/*") || it.startsWith("//") } }

    @Test fun everyKeyHasEnglish() {
        val missing = ArrayList<String>()
        var count = 0
        for ((f, n, l) in lines(appSrc) + lines(kbSrc)) {
            val c = code(l)
            for (m in Regex("(?<![\\w.])tr\\(\\s*" + literal.pattern).findAll(c)) {
                count++
                val k = unescape(m.groupValues[1])
                if (L10nTable.EN[k].isNullOrBlank()) missing.add("${f.name}:$n “$k”")
            }
            if ("l10n-key" in l) {
                val first = literal.find(c)?.groupValues?.get(1)?.let(::unescape)
                if (first != null && vn.containsMatchIn(first) && L10nTable.EN[first].isNullOrBlank())
                    missing.add("${f.name}:$n “$first”")
            }
        }
        assertTrue("quét được quá ít tr(): $count", count > 300)
        assertTrue("thiếu bản dịch (thêm vào keyboard/…/L10nTable.kt):\n" + missing.joinToString("\n"), missing.isEmpty())
    }

    @Test fun noVietnameseOutsideTr() {
        val stray = ArrayList<String>()
        val scanned = listOf("ui", "plus", "ime").map { File(appSrc, "com/viettelex/android/$it") }
        for (d in scanned) for ((f, n, l) in lines(d)) {
            if ("l10n-key" in l || "l10n-skip" in l || "TouchLog.write" in l || "Log." in l) continue
            val c = code(l)
            for (m in literal.findAll(c)) {
                if (!vn.containsMatchIn(m.groupValues[1])) continue
                if (c.substring(0, m.range.first).trimEnd().endsWith("tr(")) continue
                stray.add("${f.name}:$n ${m.value}")
            }
        }
        assertTrue("chuỗi tiếng Việt chưa bọc tr(…):\n" + stray.joinToString("\n"), stray.isEmpty())
    }
}
