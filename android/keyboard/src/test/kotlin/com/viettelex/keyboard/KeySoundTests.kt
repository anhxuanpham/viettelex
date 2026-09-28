package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/** Âm thanh phím riêng (28/09/2026) — giống iOS KeySoundTests. */
class KeySoundTests {
    @Test fun settingDefaultsAndClamp() {
        val d = KeyboardSettings()
        assertFalse(d.keySound)
        assertEquals(50, d.keySoundVolume)
        val s = KeyboardSettings.load { when (it) { Keys.KEY_SOUND -> true; Keys.KEY_SOUND_VOLUME -> 250; else -> null } }
        assertTrue(s.keySound)
        assertEquals(100, s.keySoundVolume)
        assertEquals(0, KeyboardSettings.load { if (it == Keys.KEY_SOUND_VOLUME) -3 else null }.keySoundVolume)
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
        val all = KeySoundSynth.Kind.entries.map { k ->
            val a = KeySoundSynth.samples(k)
            assertArrayEquals(a, KeySoundSynth.samples(k), 0f)
            assertTrue(a.size in 1001..1999)
            assertEquals(0.9f, a.maxOf { abs(it) }, 1e-4f)
            assertEquals(0f, a.first(), 1e-6f); assertEquals(0f, a.last(), 1e-6f)
            val e = a.sumOf { (it * it).toDouble() }
            val tail = a.copyOfRange(a.size / 2, a.size).sumOf { (it * it).toDouble() }
            assertTrue(tail / e < 0.05)
            a
        }
        assertFalse(all[0].contentEquals(all[1])); assertFalse(all[1].contentEquals(all[2]))
    }

    @Test fun wavHeader() {
        val w = KeySoundSynth.wav(KeySoundSynth.Kind.LETTER)
        assertEquals("RIFF", String(w, 0, 4)); assertEquals("WAVE", String(w, 8, 4)); assertEquals("data", String(w, 36, 4))
        assertEquals(44 + KeySoundSynth.samples(KeySoundSynth.Kind.LETTER).size * 2, w.size)
        assertArrayEquals(w, KeySoundSynth.wav(KeySoundSynth.Kind.LETTER))
    }

    @Test fun backupRoundTripAndClamp() {
        val snap = BackupPrefs.snapshot({ when (it) { Keys.KEY_SOUND -> true; Keys.KEY_SOUND_VOLUME -> 35; else -> null } }, emptyList(), null)
        assertEquals(true, snap.settings!![Keys.KEY_SOUND]); assertEquals(35, snap.settings!![Keys.KEY_SOUND_VOLUME])
        val back = BackupCodec.decode(BackupCodec.encode(snap))
        assertEquals(true, back.settings!![Keys.KEY_SOUND]); assertEquals(35, back.settings!![Keys.KEY_SOUND_VOLUME])
        val raw = """{"format":"viettelex-backup","version":1,"minReaderVersion":1,"platform":"ios","settings":{"keySoundVolume":250}}"""
        assertEquals(100, BackupCodec.decode(raw).settings!![Keys.KEY_SOUND_VOLUME])
        // mặc định khi pref vắng
        val def = BackupPrefs.settings { null }
        assertEquals(false, def[Keys.KEY_SOUND]); assertEquals(50, def[Keys.KEY_SOUND_VOLUME])
    }
}
