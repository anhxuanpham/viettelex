package com.viettelex.android

import com.viettelex.keyboard.Keys
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Auto Backup: chỉ prefs lên mây; từ đã học chỉ theo chuyển máy trực tiếp; log gỡ lỗi
 * không bao giờ. Đổi tên file prefs/userlm mà quên sửa XML ⇒ test này đỏ.
 */
class BackupRulesTest {
    private fun res(name: String): File =
        listOf("src/main", "app/src/main").map { File(it, name) }.first { it.exists() }

    private fun includes(section: org.w3c.dom.Element): Set<String> {
        val out = HashSet<String>()
        val nodes = section.getElementsByTagName("include")
        for (i in 0 until nodes.length) {
            val e = nodes.item(i) as org.w3c.dom.Element
            out.add(e.getAttribute("domain") + ":" + e.getAttribute("path"))
        }
        return out
    }

    private fun parse(name: String) =
        DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(res("res/xml/$name")).documentElement

    private val prefs = "sharedpref:${Keys.PREFS}.xml"
    private val learned = "file:${Keys.USERLM_FILE}"

    @Test fun legacyFullBackupOnlyPrefs() {
        assertEquals(setOf(prefs), includes(parse("backup_rules.xml")))
    }

    @Test fun dataExtractionRules() {
        val root = parse("data_extraction_rules.xml")
        val cloud = root.getElementsByTagName("cloud-backup").item(0) as org.w3c.dom.Element
        val transfer = root.getElementsByTagName("device-transfer").item(0) as org.w3c.dom.Element
        assertEquals(setOf(prefs), includes(cloud))
        assertEquals(setOf(prefs, learned), includes(transfer))
        val all = includes(cloud) + includes(transfer)
        assertFalse(all.any { Keys.TOUCHLOG_FILE in it })
    }

    @Test fun manifestWiresRules() {
        val m = res("AndroidManifest.xml").readText()
        assertTrue(m.contains("android:fullBackupContent=\"@xml/backup_rules\""))
        assertTrue(m.contains("android:dataExtractionRules=\"@xml/data_extraction_rules\""))
    }
}
