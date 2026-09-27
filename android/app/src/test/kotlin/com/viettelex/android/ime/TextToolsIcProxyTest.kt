package com.viettelex.android.ime

import com.viettelex.keyboard.TextTool
import com.viettelex.keyboard.TextToolRunner
import com.viettelex.keyboard.WriteMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.text.Normalizer

/** Công cụ văn bản qua IcProxy thật (FakeEditor): vùng chọn, trước con trỏ, hoàn tác, fail-safe, WriteMode. */
class TextToolsIcProxyTest {
    private val tracker = SelectionTracker()

    private fun proxy(ed: FakeEditor, mode: WriteMode = WriteMode.COMMIT): IcProxy {
        tracker.reset(ed.selStart, ed.selEnd)
        return IcProxy({ ed }, tracker).also { it.startInput(null, false); it.writeMode = mode }
    }

    private fun <T> IcProxy.batch(ed: FakeEditor, f: IcProxy.() -> T): T {
        begin(); try { return f() } finally { end(); tracker.onUpdate(ed.selStart, ed.selEnd) }
    }

    @Test fun beforeCursorParagraphAndUndo() {
        val ed = FakeEditor("Dòng đầu\nxin chào việt nam")
        val p = proxy(ed)
        val out = p.batch(ed) { TextToolRunner.apply(TextTool.TITLE, this, IcProxy.CONTEXT_CAP) }
        assertEquals("Dòng đầu\nXin Chào Việt Nam", ed.text)
        val u = (out as TextToolRunner.Outcome.Applied).undo
        assertTrue(p.batch(ed) { TextToolRunner.undo(u, this) })
        assertEquals("Dòng đầu\nxin chào việt nam", ed.text)
    }

    @Test fun selectionReplacedInPlace() {
        val ed = FakeEditor("Tôi nói tiếng việt hay", selStart = 8, selEnd = 18)
        val p = proxy(ed)
        val out = p.batch(ed) { TextToolRunner.apply(TextTool.UPPER, this, IcProxy.CONTEXT_CAP) }
        assertEquals("Tôi nói TIẾNG VIỆT hay", ed.text)
        assertEquals(18, ed.selStart)
        val u = (out as TextToolRunner.Outcome.Applied).undo
        assertTrue(p.batch(ed) { TextToolRunner.undo(u, this) })
        assertEquals("Tôi nói tiếng việt hay", ed.text)
    }

    @Test fun nfdFieldByCodePoints() {
        val nfd = Normalizer.normalize("Đường phố", Normalizer.Form.NFD)
        val ed = FakeEditor(nfd)
        val p = proxy(ed)
        p.batch(ed) { TextToolRunner.apply(TextTool.STRIP_DIACRITICS, this, IcProxy.CONTEXT_CAP) }
        assertEquals("Duong pho", ed.text)
    }

    @Test fun unreadableFieldTouchesNothing() {
        val ed = FakeEditor("xin chào")
        ed.readable = false
        val p = proxy(ed)
        val out = p.batch(ed) { TextToolRunner.apply(TextTool.UPPER, this, IcProxy.CONTEXT_CAP) }
        assertEquals(TextToolRunner.Outcome.NoSource, out)
        assertEquals("xin chào", ed.text)
    }

    @Test fun truncatedContextSkipsPartialWord() {
        val long = "a".repeat(300) + " cuối đoạn"
        val ed = FakeEditor(long)
        val p = proxy(ed)
        p.batch(ed) { TextToolRunner.apply(TextTool.UPPER, this, IcProxy.CONTEXT_CAP) }
        assertEquals("a".repeat(300) + " CUỐI ĐOẠN", ed.text)
    }

    @Test fun keyOnlyModeUsesKeyEvents() {
        val ed = FakeEditor("xin chào")
        val p = proxy(ed, WriteMode.KEY_ONLY)
        p.batch(ed) { TextToolRunner.apply(TextTool.UPPER, this, IcProxy.CONTEXT_CAP) }
        assertEquals("XIN CHÀO", ed.text)
        assertTrue(ed.keys.isNotEmpty())
    }
}
