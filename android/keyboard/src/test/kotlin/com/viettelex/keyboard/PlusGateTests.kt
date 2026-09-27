package com.viettelex.keyboard

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class PlusGateTests {
    private val store = mutableMapOf<String, Any?>()

    @Before fun setUp() {
        store.clear()
        PlusGate.install({ store[it] }, debugBuild = false)
        PlusGate.paywallEnabled = true
    }

    @After fun tearDown() {
        PlusGate.install({ null }, debugBuild = false)
        PlusGate.paywallEnabled = PlusConfig.PAYWALL_ENABLED
    }

    @Test fun lockedWhenNotPurchased() {
        PlusFeature.entries.forEach { assertFalse(it.name, PlusGate.isUnlocked(it)) }
        assertEquals(PlusConfig.FREE_PINNED_CLIP_LIMIT, PlusGate.pinnedClipLimit)
    }

    @Test fun purchasedFlagUnlocksAll() {
        store[Keys.PLUS_UNLOCKED] = true
        PlusFeature.entries.forEach { assertTrue(it.name, PlusGate.isUnlocked(it)) }
        assertNull(PlusGate.pinnedClipLimit)
    }

    @Test fun wrongTypeIsIgnored() {
        store[Keys.PLUS_UNLOCKED] = "true"
        assertFalse(PlusGate.isPlus)
    }

    @Test fun paywallOffOpensAllButBadge() {
        PlusGate.paywallEnabled = false
        assertTrue(PlusGate.isUnlocked(PlusFeature.TEXT_TOOLS))
        assertTrue(PlusGate.isUnlocked(PlusFeature.PREMIUM_THEMES))
        assertFalse(PlusGate.isUnlocked(PlusFeature.THANKS_BADGE))
    }

    @Test fun debugOverrideOnlyInDebugBuild() {
        store[Keys.PLUS_DEBUG_OVERRIDE] = true
        assertFalse(PlusGate.isUnlocked(PlusFeature.SENTENCE_DIACRITICS))
        PlusGate.install({ store[it] }, debugBuild = true)
        assertTrue(PlusGate.isUnlocked(PlusFeature.SENTENCE_DIACRITICS))
        assertFalse(PlusGate.purchased)
    }

    @Test fun notInstalledMeansLocked() {
        PlusGate.install({ null }, debugBuild = true)
        assertFalse(PlusGate.isPlus)
    }

    @Test fun configDefaults() {
        assertTrue("bản 1.2 bán Plus (27/09)", PlusConfig.PAYWALL_ENABLED)
        assertEquals("plus", PlusConfig.PLUS_PRODUCT_ID)
        assertEquals(4, PlusConfig.ALL_PRODUCT_IDS.toSet().size)
    }
}
