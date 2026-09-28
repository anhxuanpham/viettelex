package com.viettelex.android.ime

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View
import com.viettelex.keyboard.HapticStrength

/**
 * Âm + rung ở TOUCH-DOWN (spec §8). Âm: AudioManager.playSoundEffect — chỉ kêu khi
 * "Âm thanh khi chạm" của hệ thống bật. Rung: toggle hapticFeedback (mặc định TẮT) +
 * độ mạnh hapticStrength 10…100 % (giống iOS). Rung bằng Vibrator (quyền VIBRATE) chứ
 * không performHapticFeedback: KEYBOARD_TAP bị hệ thống bỏ qua khi "Phản hồi khi chạm"/
 * "Rung bàn phím" tắt (FLAG_IGNORE_GLOBAL_SETTING vô hiệu từ API 33) và không chỉnh
 * được độ mạnh. Một VibrationEffect dựng sẵn cho mỗi độ mạnh (không cấp phát mỗi phím);
 * tắt rung ⇒ không lấy Vibrator, không dựng gì. Máy không có motor ⇒ performHapticFeedback.
 */
class Feedback(ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val appCtx = ctx.applicationContext
    @Volatile var hapticsEnabled = false
        set(v) { field = v; if (!v) { tapEffect = null; tickEffect = null } }

    /** % đã kẹp; đổi ⇒ dựng lại hiệu ứng lười ở lần rung sau. */
    @Volatile var hapticStrength = HapticStrength.DEFAULT
        set(v) {
            val c = HapticStrength.clamp(v)
            if (c != field) { field = c; tapEffect = null; tickEffect = null }
        }

    private var vibratorLoaded = false
    private var vibrator: Vibrator? = null
    private var tapEffect: VibrationEffect? = null
    private var tickEffect: VibrationEffect? = null

    private fun vib(): Vibrator? {
        if (!vibratorLoaded) {
            vibratorLoaded = true
            vibrator = runCatching {
                if (Build.VERSION.SDK_INT >= 31)
                    (appCtx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
                else @Suppress("DEPRECATION") (appCtx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
            }.getOrNull()?.takeIf { it.hasVibrator() }
        }
        return vibrator
    }

    private fun effect(v: Vibrator, percent: Int): VibrationEffect =
        if (v.hasAmplitudeControl())
            VibrationEffect.createOneShot(HapticStrength.amplitudeDurationMs(percent), HapticStrength.amplitude(percent))
        else VibrationEffect.createOneShot(HapticStrength.durationOnlyMs(percent), VibrationEffect.DEFAULT_AMPLITUDE)

    /** Rung một nhịp theo độ mạnh; false ⇒ không có Vibrator, gọi view.performHapticFeedback. */
    private fun vibrate(tick: Boolean): Boolean {
        val v = vib() ?: return false
        val e = if (tick) tickEffect ?: effect(v, hapticStrength / 2).also { tickEffect = it }
                else tapEffect ?: effect(v, hapticStrength).also { tapEffect = it }
        return runCatching { v.vibrate(e) }.isSuccess
    }

    fun click(kind: Int, view: View) {
        audio.playSoundEffect(when (kind) {
            DELETE -> AudioManager.FX_KEYPRESS_DELETE
            SPACE -> AudioManager.FX_KEYPRESS_SPACEBAR
            RETURN -> AudioManager.FX_KEYPRESS_RETURN
            else -> AudioManager.FX_KEYPRESS_STANDARD
        })
        if (hapticsEnabled && !vibrate(tick = false)) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        }
    }

    /** Nấc nhẹ (vuốt ⌫ thêm/bớt một từ): chỉ rung, không âm. */
    fun tick(view: View) {
        if (hapticsEnabled && !vibrate(tick = true)) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    /** Giữ lâu đã kích hoạt (Enter xuống dòng): rung LONG_PRESS; tắt rung app ⇒ theo cài đặt hệ thống. */
    fun longPress(view: View) {
        if (hapticsEnabled) view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        else view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    companion object {
        const val LETTER = 0
        const val DELETE = 1
        const val MODIFIER = 2
        const val SPACE = 3
        const val RETURN = 4
    }
}
