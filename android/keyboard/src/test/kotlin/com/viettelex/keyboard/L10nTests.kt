package com.viettelex.keyboard

import java.util.Locale
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Giao diện hai ngôn ngữ ([L10n], [L10nTable]): mặc định Tiếng Việt bất kể ngôn ngữ máy, chọn
 * ngôn ngữ được lưu, bảng dịch đủ và khớp placeholder. Độ phủ theo mã nguồn (mọi `tr("…")` có
 * bản dịch, không sót chữ Việt ngoài `tr`) ở app: L10nCoverageTest.
 */
class L10nTests {
    @AfterTest fun reset() { L10n.lang = L10n.DEFAULT; L10n.onRead = null }

    @Test fun defaultIsVietnameseRegardlessOfDeviceLocale() {
        val saved = Locale.getDefault()
        try {
            for (loc in listOf(Locale.US, Locale.UK, Locale.JAPAN, Locale.forLanguageTag("vi-VN"))) {
                Locale.setDefault(loc)
                assertEquals("vi", L10n.load { null }, "máy $loc, chưa chọn ⇒ vi")
                assertEquals("Tính Năng", tr("Tính Năng"))
            }
        } finally { Locale.setDefault(saved) }
    }

    @Test fun unknownValuesFallBackToVietnamese() {
        for (raw in listOf<Any?>(null, "", "fr", "EN", 1, true)) assertEquals("vi", L10n.normalize(raw), "$raw")
        L10n.lang = "xx"
        assertEquals("vi", L10n.lang)
    }

    @Test fun switchingPersistsAndReloads() {
        val store = HashMap<String, Any?>()
        assertEquals("en", L10n.select("en") { k, v -> store[k] = v })
        assertEquals("en", store[Keys.UI_LANGUAGE])
        assertEquals("Features", tr("Tính Năng"))
        L10n.lang = L10n.DEFAULT                                    // "khởi động lại"
        assertEquals("en", L10n.load { store[it] })
        assertEquals("Features", tr("Tính Năng"))
        L10n.select("vi") { k, v -> store[k] = v }
        assertEquals("vi", L10n.load { store[it] })
        assertEquals("Tính Năng", tr("Tính Năng"))
    }

    @Test fun formatsArgumentsInBothLanguages() {
        assertEquals("Gõ tắt: 3 mục", tr("Gõ tắt: %d mục", 3))
        L10n.lang = "en"
        assertEquals("Shortcuts: 3", tr("Gõ tắt: %d mục", 3))
        assertEquals("Overlay darkness: 40%", tr("Độ tối lớp phủ: %s%%", 40))
        assertEquals("chưa có bản dịch", tr("chưa có bản dịch"))   // thiếu ⇒ giữ tiếng Việt
    }

    @Test fun onReadHookFiresForComposeObservation() {
        var reads = 0
        L10n.onRead = { reads++ }
        tr("Tính Năng"); L10n.isEnglish
        assertEquals(2, reads)
    }

    @Test fun guideUrlFollowsLanguage() {
        assertEquals("https://viettelex.com/hdsd/?os=android#go-vuot", L10n.guideUrl("android", "go-vuot"))
        L10n.lang = "en"
        assertEquals("https://viettelex.com/en/guide/?os=android", L10n.guideUrl("android"))
    }

    private val placeholder = Regex("%(?:%|[-+ #0]*\\d*(?:\\.\\d+)?[sd])")

    @Test fun tableHasNoEmptyValuesAndMatchingPlaceholders() {
        assertTrue(L10nTable.EN.size > 300, "bảng dịch quá ít: ${L10nTable.EN.size}")
        for ((vi, en) in L10nTable.EN) {
            assertTrue(vi.isNotBlank() && en.isNotBlank(), "rỗng: “$vi” → “$en”")
            assertEquals(placeholder.findAll(vi).map { it.value }.sorted().toList(),
                placeholder.findAll(en).map { it.value }.sorted().toList(), "placeholder lệch: “$vi” → “$en”")
        }
        // Tên thương hiệu giữ nguyên.
        for ((vi, en) in L10nTable.EN) {
            for (brand in listOf("VietTelex", "FUTO Swipe", "Telex", "VNI"))
                if (brand in vi) assertTrue(brand in en, "mất “$brand”: “$vi” → “$en”")
        }
    }

    /** Nhãn enum hiển thị (theme, Plus, công cụ văn bản, chip) đều có bản dịch. */
    @Test fun enumLabelsTranslated() {
        val vi = KeyboardTheme.entries.map { it.viTitle } + PlusFeature.entries.flatMap { listOf(it.viTitle, it.viDetail) } +
            TextTool.entries.map { it.viLabel } + listOf("Thêm dấu", "Hoàn tác")
        for (k in vi) assertTrue(L10nTable.EN[k]?.isNotBlank() == true, "thiếu bản dịch: “$k”")
        L10n.lang = "en"
        assertEquals("OLED Dark", KeyboardTheme.OLED.title)
        assertEquals("Text tools", PlusFeature.TEXT_TOOLS.title)
        assertEquals("Add tones", KeyboardSession.ADD_TONES_LABEL)
        assertEquals("↩︎ Undo", KeyboardSession.UNDO_TONES_LABEL)
        assertNotEquals(TextTool.TITLE.viLabel, TextTool.TITLE.label)
    }

    @Test fun backupMessagesTranslated() {
        L10n.lang = "en"
        assertEquals("Not a VietTelex backup file.", BackupException(BackupException.Reason.NOT_BACKUP).userMessage)
        assertEquals("Imported 2 settings.", BackupMerge.summary(BackupPayload(settings = mapOf("a" to true, "b" to 1)), 0, 0))
        val (_, notice) = Templates.merge(emptyList(), listOf(TemplateItem("", "a")))
        assertEquals("Added 1/1 snippets.", notice)
        assertFalse(Templates.addNotice(Templates.AddResult.EmptyText)!!.contains("mẫu"))
    }
}
