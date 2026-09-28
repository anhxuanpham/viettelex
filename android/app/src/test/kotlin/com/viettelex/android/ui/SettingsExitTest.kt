package com.viettelex.android.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** RAM-AUDIT #5: rời app cài đặt ⇒ finish (Compose/HWUI không nằm lại trong process IME). */
class SettingsExitTest {
    @Test fun finishesWhenUserLeaves() {
        assertTrue(SettingsExit.shouldFinish(changingConfig = false, launchedChild = false, interactive = true, finishing = false))
    }

    @Test fun keepsActivityWhenItMustComeBack() {
        assertFalse("xoay / đổi theme", SettingsExit.shouldFinish(true, false, true, false))
        assertFalse("chọn ảnh/file, Billing, Cài đặt bàn phím — chờ kết quả", SettingsExit.shouldFinish(false, true, true, false))
        assertFalse("tắt màn hình", SettingsExit.shouldFinish(false, false, false, false))
        assertFalse("đã finish", SettingsExit.shouldFinish(false, false, true, true))
    }
}
