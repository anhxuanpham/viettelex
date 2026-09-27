package com.viettelex.android.ui

import com.viettelex.keyboard.L10n
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ô tìm cài đặt khớp CẢ tiếng Việt lẫn English, bất kể đang chọn ngôn ngữ nào. */
class FeatureSearchL10nTest {
    @After fun reset() { L10n.lang = L10n.DEFAULT }

    private fun pages(q: String) = FeatureSearchEntry.search(q).map { it.page }.toSet()

    @Test fun matchesBothLanguages() {
        for (lang in listOf("vi", "en")) {
            L10n.lang = lang
            assertTrue(lang, FeaturePage.GiaoDien in pages("trong suot"))
            assertTrue(lang, FeaturePage.GiaoDien in pages("label transparency"))
            assertTrue(lang, FeaturePage.GoVuot in pages("swipe practice"))
            assertTrue(lang, FeaturePage.Phim in pages("một tay"))
            assertTrue(lang, FeaturePage.Phim in pages("one-handed"))
            assertTrue(lang, FeaturePage.SaoLuu in pages("backup"))
        }
    }

    @Test fun titlesAndGuideFollowLanguage() {
        assertEquals("Tính Năng", AppTab.TinhNang.title)
        assertTrue(FeaturePage.GoVuot.guideUrl.endsWith("/hdsd/?os=android#go-vuot"))
        L10n.lang = "en"
        assertEquals("Features", AppTab.TinhNang.title)
        assertEquals("Swipe typing", FeaturePage.GoVuot.title)
        assertEquals("https://viettelex.com/en/guide/?os=android#swipe", FeaturePage.GoVuot.guideUrl)
        assertEquals("https://viettelex.com/en/guide/?os=android#backup", FeaturePage.SaoLuu.guideUrl)
    }
}
