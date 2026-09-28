package com.viettelex.android.ime

import com.viettelex.keyboard.KeySoundSynth
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
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
}
