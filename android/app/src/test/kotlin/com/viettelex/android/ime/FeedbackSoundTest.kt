package com.viettelex.android.ime

import com.viettelex.keyboard.KeySoundCustom
import com.viettelex.keyboard.KeySoundStyle
import com.viettelex.keyboard.KeySoundSynth
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

/** Âm thanh phím riêng: loại phím → tiếng như stock; WAV cache tất định, ghi một lần. */
class FeedbackSoundTest {
    @Test fun kindMapping() {
        assertEquals(KeySoundSynth.Kind.LETTER, Feedback.soundKind(Feedback.LETTER))
        assertEquals(KeySoundSynth.Kind.DELETE, Feedback.soundKind(Feedback.DELETE))
        for (k in listOf(Feedback.MODIFIER, Feedback.SPACE, Feedback.RETURN))
            assertEquals(KeySoundSynth.Kind.MODIFIER, Feedback.soundKind(k))
    }

    @Test fun wavCacheWrittenOnce() {
        val dir = Files.createTempDirectory("keysound").toFile()
        try {
            val f = Feedback.wavFile(dir, KeySoundSynth.Kind.DELETE)!!
            assertArrayEquals(KeySoundSynth.wav(KeySoundSynth.Kind.DELETE), f.readBytes())
            val stamp = f.lastModified()
            assertEquals(f, Feedback.wavFile(dir, KeySoundSynth.Kind.DELETE))
            assertEquals(stamp, f.lastModified())
        } finally { dir.deleteRecursively() }
    }

    /** Kiểu custom: file hợp lệ ⇒ cả 3 loại dùng file đó; vắng/hỏng ⇒ WAV "Nhẹ nhàng". Kiểu khác ⇒ WAV kiểu đó. */
    @Test fun soundFilesStyleAndCustomFallback() {
        val dir = Files.createTempDirectory("keysound").toFile()
        try {
            val custom = java.io.File(dir, KeySoundCustom.FILE_NAME)
            val miss = Feedback.soundFiles(dir, "custom", custom)
            assertEquals(Feedback.wavFile(dir, KeySoundStyle.SUBTLE, KeySoundSynth.Kind.LETTER), miss[0])
            custom.writeText("hỏng")
            assertEquals(Feedback.wavFile(dir, KeySoundStyle.SUBTLE, KeySoundSynth.Kind.DELETE), Feedback.soundFiles(dir, "custom", custom)[1])
            custom.writeBytes(KeySoundSynth.wav(floatArrayOf(0f, 0.5f, -0.5f, 0f)))
            assertEquals(listOf(custom, custom, custom), Feedback.soundFiles(dir, "custom", custom))
            val wood = Feedback.soundFiles(dir, "wood", custom)
            assertArrayEquals(KeySoundSynth.wav(KeySoundStyle.WOOD, KeySoundSynth.Kind.MODIFIER), wood[2]!!.readBytes())
            assertTrue(wood[0]!!.name.contains("-wood-"))
        } finally { dir.deleteRecursively() }
    }
}
