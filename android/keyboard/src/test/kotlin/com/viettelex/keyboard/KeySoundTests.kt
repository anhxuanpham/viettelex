package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/** Âm thanh phím riêng (28/09/2026) — giống iOS KeySoundTests. */
class KeySoundTests {
    @Test fun settingDefaultsAndClamp() {
        val d = KeyboardSettings()
        assertFalse(d.keySound)
        assertEquals(50, d.keySoundVolume)
        assertEquals("subtle", d.keySoundStyle)
        val s = KeyboardSettings.load { when (it) { Keys.KEY_SOUND -> true; Keys.KEY_SOUND_VOLUME -> 250; Keys.KEY_SOUND_STYLE -> "wood"; else -> null } }
        assertTrue(s.keySound)
        assertEquals(100, s.keySoundVolume)
        assertEquals("wood", s.keySoundStyle)
        assertEquals(0, KeyboardSettings.load { if (it == Keys.KEY_SOUND_VOLUME) -3 else null }.keySoundVolume)
        assertEquals("subtle", KeyboardSettings.load { if (it == Keys.KEY_SOUND_STYLE) "loud" else null }.keySoundStyle)
    }

    /** TẮT ⇒ tiếng hệ thống; BẬT ⇒ tiếng riêng (không kèm hệ thống); Rung/Im lặng hoặc 0 % ⇒ im. */
    @Test fun routeOffSystemOnCustom() {
        assertEquals(KeySoundSynth.Route.SYSTEM, KeySoundSynth.route(false, 50, true))
        assertEquals(KeySoundSynth.Route.SYSTEM, KeySoundSynth.route(false, 50, false))
        assertEquals(KeySoundSynth.Route.CUSTOM, KeySoundSynth.route(true, 50, true))
        assertEquals(KeySoundSynth.Route.SILENT, KeySoundSynth.route(true, 50, false))
        assertEquals(KeySoundSynth.Route.SILENT, KeySoundSynth.route(true, 0, true))
    }

    @Test fun gainCurve() {
        assertEquals(0f, KeySoundSynth.gain(0))
        assertEquals(0.25f, KeySoundSynth.gain(50), 1e-6f)
        assertEquals(1f, KeySoundSynth.gain(100))
        assertEquals(1f, KeySoundSynth.gain(300))
    }

    @Test fun samplesDeterministicNonEmptyDistinct() {
        for (st in KeySoundStyle.PRESETS) {
            val all = KeySoundSynth.Kind.entries.map { k ->
                val a = KeySoundSynth.samples(st, k)
                assertArrayEquals(a, KeySoundSynth.samples(st, k), 0f)
                assertTrue(a.size in 1001..2699)
                assertEquals(KeySoundSynth.baseRecipe(st).peak.toFloat(), a.maxOf { abs(it) }, 1e-4f)
                assertEquals(0f, a.first(), 1e-6f); assertEquals(0f, a.last(), 1e-6f)
                val e = a.sumOf { (it * it).toDouble() }
                val tail = a.copyOfRange(a.size / 2, a.size).sumOf { (it * it).toDouble() }
                assertTrue("$st/$k", tail / e < 0.08)
                a
            }
            assertFalse(all[0].contentEquals(all[1])); assertFalse(all[1].contentEquals(all[2]))
        }
        assertArrayEquals(KeySoundSynth.samples(KeySoundSynth.Kind.LETTER),
            KeySoundSynth.samples(KeySoundStyle.SUBTLE, KeySoundSynth.Kind.LETTER), 0f)
    }

    /** "Không chói" đo được: trọng tâm phổ thấp (bản cũ ~7 kHz), độ to dễ chịu. */
    @Test fun presetsAreSoft() {
        for (st in KeySoundStyle.PRESETS) for (k in KeySoundSynth.Kind.entries) {
            val a = KeySoundSynth.samples(st, k)
            val c = KeySoundSynth.spectralCentroid(a)
            assertTrue("$st/$k centroid $c", c < 2500)
            if (st == KeySoundStyle.SUBTLE) assertTrue("mặc định trầm-êm: $c", c < 1000)
            val r = KeySoundSynth.rms(a)
            assertTrue("$st/$k rms $r", r > 0.05 && r < 0.30)
        }
    }

    /** Checksum chung với iOS (KeySoundTests.swift testCrossPlatformChecksums). */
    @Test fun crossPlatformChecksums() {
        val golden = mapOf(KeySoundStyle.SUBTLE to 169.1699, KeySoundStyle.WOOD to 192.4240,
            KeySoundStyle.MECHANICAL to 239.0849, KeySoundStyle.TYPEWRITER to 139.7659, KeySoundStyle.BUBBLE to 233.6785)
        for ((st, want) in golden) {
            val s = KeySoundSynth.samples(st, KeySoundSynth.Kind.LETTER).sumOf { abs(it).toDouble() }
            assertEquals("$st", want, s, 0.01)
        }
    }

    @Test fun styleResolveAndBankFallback() {
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve(null, true))
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve("xyz", true))
        assertEquals(KeySoundStyle.WOOD, KeySoundStyle.resolve("wood", false))
        assertEquals(KeySoundStyle.SUBTLE, KeySoundStyle.resolve("custom", false))
        assertEquals(KeySoundStyle.CUSTOM, KeySoundStyle.resolve("custom", true))
        val miss = KeySoundSynth.bank("custom", null)
        assertEquals(KeySoundStyle.SUBTLE, miss.first)
        assertArrayEquals(KeySoundSynth.samples(KeySoundStyle.SUBTLE, KeySoundSynth.Kind.LETTER), miss.second[0], 0f)
        val c = floatArrayOf(0f, 0.5f, -0.5f, 0f)
        val hit = KeySoundSynth.bank("custom", c)
        assertEquals(KeySoundStyle.CUSTOM, hit.first)
        assertArrayEquals(c, hit.second[0], 0f)
        val dir = Files.createTempDirectory("ks").toFile()
        try {
            val f = java.io.File(dir, KeySoundCustom.FILE_NAME)
            assertNull(KeySoundCustom.load(f))
            f.writeText("not a wav")
            assertNull(KeySoundCustom.load(f))
            assertEquals("custom", KeySoundCustom.bankKey("custom", java.io.File(dir, "none")))
            assertEquals("wood", KeySoundCustom.bankKey("wood", f))
        } finally { dir.deleteRecursively() }
    }

    @Test fun wavHeaderAndRoundTrip() {
        val w = KeySoundSynth.wav(KeySoundSynth.Kind.LETTER)
        assertEquals("RIFF", String(w, 0, 4)); assertEquals("WAVE", String(w, 8, 4)); assertEquals("data", String(w, 36, 4))
        assertEquals(44 + KeySoundSynth.samples(KeySoundSynth.Kind.LETTER).size * 2, w.size)
        assertArrayEquals(w, KeySoundSynth.wav(KeySoundSynth.Kind.LETTER))
        val s = KeySoundSynth.samples(KeySoundStyle.WOOD, KeySoundSynth.Kind.DELETE)
        val (back, rate) = KeySoundSynth.parseWav(KeySoundSynth.wav(s))!!
        assertEquals(44_100.0, rate, 0.0)
        assertEquals(s.size, back.size)
        for (i in s.indices) assertEquals(s[i], back[i], 1f / 16_000)
        assertNull(KeySoundSynth.parseWav(byteArrayOf(1, 2, 3)))
    }

    /** WAV thử: stereo 16-bit ở [rate], lặng [lead] s rồi sine [tone] s biên độ [amp]. */
    private fun testWav(rate: Int, lead: Double, tone: Double, amp: Double, freq: Double = 440.0): ByteArray {
        val n = ((lead + tone) * rate).toInt()
        val data = n * 4
        val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(2).putInt(rate).putInt(rate * 4).putShort(4).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        for (i in 0 until n) {
            val t = i.toDouble() / rate - lead
            val v = if (t < 0) 0.0 else amp * sin(2 * PI * freq * t)
            val sv = (v.coerceIn(-1.0, 1.0) * 32767).toInt().toShort()
            b.putShort(sv); b.putShort(sv)
        }
        return b.array()
    }

    /** Đường nhập từ file thử (giải mã WAV → process): bỏ lặng, cắt ≤ 300 ms, đỉnh/RMS an toàn. */
    @Test fun customImportTrimsCapsNormalizes() {
        val (mono, rate) = KeySoundSynth.parseWav(testWav(48_000, 0.25, 0.8, 1.0))!!
        val r = KeySoundCustom.process(mono, rate)
        assertTrue(r.truncated)
        val dur = r.samples.size / 44_100.0
        assertTrue("dur $dur", dur <= 0.3 + 1e-3 && dur > 0.29)
        assertTrue(r.samples.maxOf { abs(it) } <= KeySoundCustom.TARGET_PEAK + 1e-3)
        assertTrue(KeySoundSynth.rms(r.samples) <= KeySoundCustom.MAX_RMS + 1e-3)
        assertTrue(r.samples.copyOfRange(0, 220).maxOf { abs(it) } > 0.05f)   // lặng đầu đã bỏ
        assertEquals(0f, r.samples.last(), 1e-3f)
        // Ghi + đọc lại như IME.
        val dir = Files.createTempDirectory("ks").toFile()
        try {
            val f = java.io.File(dir, KeySoundCustom.FILE_NAME)
            f.writeBytes(KeySoundSynth.wav(r.samples))
            val loaded = KeySoundCustom.load(f)
            assertNotNull(loaded)
            assertEquals(r.samples.size, loaded!!.size)
            assertEquals(KeySoundStyle.CUSTOM, KeySoundSynth.bank("custom", loaded).first)
            assertTrue(KeySoundCustom.bankKey("custom", f).startsWith("custom@"))
        } finally { dir.deleteRecursively() }
    }

    @Test fun customImportShortQuietIsBoostedAndSilentRejected() {
        val (mono, rate) = KeySoundSynth.parseWav(testWav(22_050, 0.02, 0.03, 0.05, 300.0))!!
        val r = KeySoundCustom.process(mono, rate)
        assertFalse(r.truncated)
        assertTrue(r.samples.size < 0.06 * 44_100)
        val peak = r.samples.maxOf { abs(it) }
        assertTrue("peak $peak", peak > 0.25f && peak <= KeySoundCustom.TARGET_PEAK + 1e-3f)
        assertEquals(KeySoundCustom.MAX_RMS, KeySoundSynth.rms(r.samples), 0.01)
        val silent = KeySoundSynth.parseWav(testWav(44_100, 0.5, 0.0, 0.0))!!
        assertTrue(runCatching { KeySoundCustom.process(silent.first, silent.second) }.exceptionOrNull() is KeySoundCustom.Failure)
        assertTrue(runCatching { KeySoundCustom.process(FloatArray(0), 44_100.0) }.exceptionOrNull() is KeySoundCustom.Failure)
        assertEquals(44_100, KeySoundCustom.resample(FloatArray(48_000) { 0.5f }, 48_000.0, 44_100.0).size)
    }

    @Test fun previewThrottle() {
        val t = PreviewThrottle(120)
        assertTrue(t.shouldFire(50, 0, false))
        assertFalse(t.shouldFire(55, 50, false))    // quá sớm
        assertTrue(t.shouldFire(55, 130, false))
        assertFalse(t.shouldFire(55, 300, false))   // cùng giá trị khi kéo
        assertFalse(t.shouldFire(55, 200, true))    // vừa phát đúng giá trị này
        assertTrue(t.shouldFire(60, 210, true))     // thả ở giá trị mới ⇒ luôn phát
        assertTrue(t.shouldFire(60, 500, true))     // thả sau lâu ⇒ phát lại
    }

    @Test fun backupRoundTripAndClamp() {
        val snap = BackupPrefs.snapshot({ when (it) { Keys.KEY_SOUND -> true; Keys.KEY_SOUND_VOLUME -> 35; Keys.KEY_SOUND_STYLE -> "bubble"; else -> null } }, emptyList(), null)
        assertEquals(true, snap.settings!![Keys.KEY_SOUND]); assertEquals(35, snap.settings!![Keys.KEY_SOUND_VOLUME])
        assertEquals("bubble", snap.settings!![Keys.KEY_SOUND_STYLE])
        val back = BackupCodec.decode(BackupCodec.encode(snap))
        assertEquals(true, back.settings!![Keys.KEY_SOUND]); assertEquals(35, back.settings!![Keys.KEY_SOUND_VOLUME])
        assertEquals("bubble", back.settings!![Keys.KEY_SOUND_STYLE])
        val raw = """{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"ios","settings":{"keySoundVolume":250,"keySoundStyle":"loud"}}"""
        val dec = BackupCodec.decode(raw).settings!!
        assertEquals(100, dec[Keys.KEY_SOUND_VOLUME])
        assertNull(dec[Keys.KEY_SOUND_STYLE])
        // mặc định khi pref vắng
        val def = BackupPrefs.settings { null }
        assertEquals(false, def[Keys.KEY_SOUND]); assertEquals(50, def[Keys.KEY_SOUND_VOLUME])
        assertEquals("subtle", def[Keys.KEY_SOUND_STYLE])
    }
}
