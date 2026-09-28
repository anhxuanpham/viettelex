package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import com.viettelex.keyboard.KeySoundSynth
import java.io.File

/**
 * Âm + rung ở TOUCH-DOWN (spec §8).
 * Âm, setting "Âm thanh phím" TẮT (mặc định): AudioManager.playSoundEffect — chỉ kêu khi
 * "Âm thanh khi chạm" của hệ thống bật (y như trước, không dựng gì thêm).
 * Âm, setting BẬT: tiếng click riêng ([KeySoundSynth], SoundPool nạp sẵn) theo âm lượng
 * thanh trượt, KHÔNG kèm tiếng hệ thống; im khi máy ở Rung/Im lặng (như Gboard/AOSP).
 * Rung: toggle hapticFeedback (mặc định TẮT), Android không cần quyền đặc biệt.
 */
class Feedback(private val ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    @Volatile var hapticsEnabled = false

    // --- Âm phím riêng (chỉ đụng trên main, trừ nạp WAV trên worker) ---
    private var soundEnabled = false
    private var volumePercent = 50
    private var gain = KeySoundSynth.gain(50)
    private var pool: SoundPool? = null
    /** id SoundPool theo [KeySoundSynth.Kind.ordinal]; 0 = chưa nạp xong. */
    private val ids = IntArray(KeySoundSynth.Kind.entries.size)
    @Volatile private var loaded = BooleanArray(ids.size)
    private var ringerNormal = true
    private var ringerCheckedAt = 0L
    /** Test hook: đường âm lần bấm gần nhất. */
    var lastRoute: KeySoundSynth.Route? = null
        private set

    /**
     * Áp setting lúc bàn phím hiện. BẬT ⇒ dựng SoundPool + nạp 3 mẫu ([worker] ghi WAV cache
     * lần đầu); TẮT ⇒ nhả hết (0 chi phí).
     */
    fun configureSound(enabled: Boolean, volume: Int, worker: (Runnable) -> Unit) {
        soundEnabled = enabled
        volumePercent = volume.coerceIn(0, 100)
        gain = KeySoundSynth.gain(volumePercent)
        refreshRinger(force = true)
        if (!enabled || volumePercent == 0) { releaseSound(); return }
        if (pool != null) return
        val p = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = p
        val fresh = BooleanArray(ids.size); loaded = fresh
        p.setOnLoadCompleteListener { sp, sampleId, status ->
            if (sp !== pool || status != 0) return@setOnLoadCompleteListener
            val i = ids.indexOf(sampleId)
            if (i >= 0) fresh[i] = true
        }
        val dir = ctx.cacheDir
        worker(Runnable {
            val files = KeySoundSynth.Kind.entries.map { k -> wavFile(dir, k) }
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (pool !== p) return@post
                files.forEachIndexed { i, f -> if (f != null) ids[i] = p.load(f.path, 1) }
            }
        })
    }

    /** Nhả SoundPool (ẩn bàn phím, thiếu RAM, tắt setting). */
    fun releaseSound() {
        pool?.release()
        pool = null
        ids.fill(0)
        loaded = BooleanArray(ids.size)
    }

    fun click(kind: Int, view: View) {
        val route = KeySoundSynth.route(soundEnabled, volumePercent, ringerNormal())
        lastRoute = route
        when (route) {
            KeySoundSynth.Route.SYSTEM -> audio.playSoundEffect(when (kind) {
                DELETE -> AudioManager.FX_KEYPRESS_DELETE
                SPACE -> AudioManager.FX_KEYPRESS_SPACEBAR
                RETURN -> AudioManager.FX_KEYPRESS_RETURN
                else -> AudioManager.FX_KEYPRESS_STANDARD
            })
            KeySoundSynth.Route.CUSTOM -> {
                val i = soundKind(kind).ordinal
                if (loaded[i]) pool?.play(ids[i], gain, gain, 1, 0, 1f)
            }
            KeySoundSynth.Route.SILENT -> {}
        }
        if (hapticsEnabled) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP,
                HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        }
    }

    /** Nấc nhẹ (vuốt ⌫ thêm/bớt một từ): chỉ rung, không âm. */
    fun tick(view: View) {
        if (hapticsEnabled) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    /** Giữ lâu đã kích hoạt (Enter xuống dòng): rung LONG_PRESS; tắt rung app ⇒ theo cài đặt hệ thống. */
    fun longPress(view: View) {
        if (hapticsEnabled) view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        else view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    /** Ringer mode đọc qua binder — chỉ khi âm riêng bật, cache 2 s (gạt Rung/Im giữa lúc gõ vẫn kịp). */
    private fun ringerNormal(): Boolean {
        if (soundEnabled) refreshRinger(force = false)
        return ringerNormal
    }

    private fun refreshRinger(force: Boolean) {
        val now = SystemClock.uptimeMillis()
        if (!force && now - ringerCheckedAt < 2000) return
        ringerCheckedAt = now
        ringerNormal = runCatching { audio.ringerMode == AudioManager.RINGER_MODE_NORMAL }.getOrDefault(true)
    }

    companion object {
        const val LETTER = 0
        const val DELETE = 1
        const val MODIFIER = 2
        const val SPACE = 3
        const val RETURN = 4

        /** Loại phím → tiếng: chữ / xoá / còn lại (cách, Enter, shift… như stock). */
        fun soundKind(kind: Int): KeySoundSynth.Kind = when (kind) {
            LETTER -> KeySoundSynth.Kind.LETTER
            DELETE -> KeySoundSynth.Kind.DELETE
            else -> KeySoundSynth.Kind.MODIFIER
        }

        /** WAV tất định ghi 1 lần vào cache (tên kèm VERSION). null nếu ghi lỗi. */
        fun wavFile(dir: File, k: KeySoundSynth.Kind): File? = runCatching {
            val f = File(dir, "keysound-v${KeySoundSynth.VERSION}-${k.name.lowercase()}.wav")
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, f.name + ".tmp")
                tmp.writeBytes(KeySoundSynth.wav(k))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()
    }
}
