package com.viettelex.keyboard

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Độ mạnh rung 10…100 % → biên độ / độ dài nhịp (giống iOS HapticTests). */
class HapticStrengthTests {
    @Test fun clampRange() {
        assertEquals(10, HapticStrength.clamp(0)); assertEquals(10, HapticStrength.clamp(-5))
        assertEquals(100, HapticStrength.clamp(250)); assertEquals(45, HapticStrength.clamp(45))
    }

    @Test fun amplitudeMapping() {
        assertEquals(26, HapticStrength.amplitude(10))
        assertEquals(115, HapticStrength.amplitude(45))
        assertEquals(255, HapticStrength.amplitude(100))
        assertEquals(255, HapticStrength.amplitude(999))
        assertEquals(26, HapticStrength.amplitude(1))
        assertEquals(9L, HapticStrength.amplitudeDurationMs(10))
        assertEquals(18L, HapticStrength.amplitudeDurationMs(100))
    }

    @Test fun mappingsMonotonic() {
        assertEquals(5L, HapticStrength.durationOnlyMs(10))
        assertEquals(30L, HapticStrength.durationOnlyMs(100))
        assertEquals(5L, HapticStrength.durationOnlyMs(0))
        val durs = (10..100 step 5).map { HapticStrength.durationOnlyMs(it) }
        assertTrue(durs.zipWithNext().all { (a, b) -> a <= b })
        val amps = (10..100 step 5).map { HapticStrength.amplitude(it) }
        assertTrue(amps.zipWithNext().all { (a, b) -> a < b })
    }

    @Test fun settingsLoadDefaultAndClamp() {
        assertEquals(45, KeyboardSettings.load { null }.hapticStrength)
        assertEquals(70, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 70 else null }.hapticStrength)
        assertEquals(100, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 300 else null }.hapticStrength)
        assertEquals(10, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) 3 else null }.hapticStrength)
        assertEquals(45, KeyboardSettings.load { if (it == Keys.HAPTIC_STRENGTH) "x" else null }.hapticStrength)
    }

    @Test fun backupSpecAndSnapshot() {
        val kind = BackupSettings.byKey[Keys.HAPTIC_STRENGTH]!!.kind as SettingKind.IntRange
        assertEquals(45, kind.default); assertEquals(10..100, kind.range)
        val prefs = mapOf<String, Any?>(Keys.HAPTIC_STRENGTH to 250)
        assertEquals(100, BackupPrefs.snapshot({ prefs[it] }, emptyList(), null).settings!![Keys.HAPTIC_STRENGTH])
        assertEquals(45, BackupPrefs.snapshot({ null }, emptyList(), null).settings!![Keys.HAPTIC_STRENGTH])
    }
}
