package com.viettelex.keyboard

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/** Tắt "Chọn phím thông minh" / onTrimMemory: trie dùng chung được nhả (0 RAM), bật lại dựng lại. */
class TelexKeyPriorReleaseTests {
    @Test fun releaseDropsSharedTableAndWarmUpRebuilds() {
        TestAssets.install()
        val t = TelexKeyPrior.warmUp()
        assertSame(t, TelexKeyPrior.sharedIfReady)
        TelexKeyPrior.release()
        assertNull("tắt ⇒ router cũ, không giữ bảng", TelexKeyPrior.sharedIfReady)
        assertNotNull(TelexKeyPrior.warmUp().forRaw("vie"))
    }
}
