package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import com.viettelex.keyboard.HapticStrength
import com.viettelex.keyboard.KeySoundCustom
import com.viettelex.keyboard.KeySoundStyle
import com.viettelex.keyboard.KeySoundSynth
import java.io.File

/**
 * Âm + rung ở TOUCH-DOWN (spec §8). Âm: AudioManager.playSoundEffect — chỉ kêu khi
 * "Âm thanh khi chạm" của hệ thống bật. Rung: toggle hapticFeedback (mặc định TẮT) +
 * độ mạnh hapticStrength 10…100 % (giống iOS). Rung bằng Vibrator (quyền VIBRATE, qua
 * [KeyVibrator] — hiệu ứng rẻ pin nhất: primitive TICK có scale / one-shot ngắn) chứ không
 * performHapticFeedback: KEYBOARD_TAP bị hệ thống bỏ qua khi "Phản hồi khi chạm"/"Rung bàn
 * phím" tắt (FLAG_IGNORE_GLOBAL_SETTING vô hiệu từ API 33) và không chỉnh được độ mạnh.
 * Tắt rung ⇒ không lấy Vibrator, không dựng gì. Máy không có motor ⇒ performHapticFeedback.
 *
 * Âm thanh phím riêng (setting keySound, mặc định TẮT ⇒ playSoundEffect như trên): BẬT ⇒
 * tiếng theo kiểu keySoundStyle ([KeySoundSynth] 5 kiểu tổng hợp, hoặc âm tự chọn trong
 * noBackupFilesDir) qua SoundPool nạp sẵn, theo âm lượng thanh trượt, KHÔNG kèm tiếng hệ
 * thống; im khi máy ở Rung/Im lặng (như Gboard/AOSP LatinIME). SoundPool rảnh không tốn
 * CPU (không có luồng render liên tục như AVAudioEngine iOS) và được nhả khi ẩn bàn phím.
 */
class Feedback(private val ctx: Context) {
    private val audio = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val vibrator = KeyVibrator(ctx)
    @Volatile var hapticsEnabled = false
        set(v) { field = v; if (!v) vibrator.clear() }

    /** % đã kẹp. */
    @Volatile var hapticStrength = HapticStrength.DEFAULT
        set(v) { field = HapticStrength.clamp(v) }

    /** Rung một nhịp theo độ mạnh; false ⇒ không có Vibrator, gọi view.performHapticFeedback. */
    private fun vibrate(tick: Boolean): Boolean =
        vibrator.vibrate(if (tick) hapticStrength / 2 else hapticStrength)

    // --- Âm phím riêng (chỉ đụng trên main, trừ nạp WAV trên worker) ---
    private var soundEnabled = false
    private var volumePercent = 50
    private var gain = KeySoundSynth.gain(50)
    private var pool: SoundPool? = null
    /** Khoá bộ mẫu đang nạp (kiểu + mtime file tự chọn) — đổi ⇒ nạp lại. */
    private var poolKey: String? = null
    /** id SoundPool theo [KeySoundSynth.Kind.ordinal]; 0 = chưa nạp xong. */
    private val ids = IntArray(KeySoundSynth.Kind.entries.size)
    /** Hệ số âm lượng từng loại (âm tự chọn: một file, xoá/chức năng nhỏ hơn chút). */
    private val kindGain = FloatArray(ids.size) { 1f }
    @Volatile private var loaded = BooleanArray(ids.size)
    private var ringerNormal = true
    private var ringerCheckedAt = 0L
    /** Test hook: đường âm lần bấm gần nhất. */
    var lastRoute: KeySoundSynth.Route? = null
        private set

    /**
     * Áp setting lúc bàn phím hiện. BẬT ⇒ dựng SoundPool + nạp 3 mẫu ([worker] ghi WAV cache
     * lần đầu / đọc file tự chọn); TẮT ⇒ nhả hết (0 chi phí). Đổi kiểu/file ⇒ nạp lại.
     */
    fun configureSound(enabled: Boolean, volume: Int, style: String, worker: (Runnable) -> Unit) {
        soundEnabled = enabled
        volumePercent = volume.coerceIn(0, 100)
        gain = KeySoundSynth.gain(volumePercent)
        if (!enabled || volumePercent == 0) { releaseSound(); return }
        refreshRinger(force = true)
        val customFile = customFile(ctx)
        val key = KeySoundCustom.bankKey(style, customFile)
        if (pool != null && key == poolKey) return
        releaseSound()
        val p = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
        pool = p; poolKey = key
        val fresh = BooleanArray(ids.size); loaded = fresh
        p.setOnLoadCompleteListener { sp, sampleId, status ->
            if (sp !== pool || status != 0) return@setOnLoadCompleteListener
            for (i in ids.indices) if (ids[i] == sampleId) fresh[i] = true
        }
        val dir = ctx.cacheDir
        worker(Runnable {
            val files = soundFiles(dir, style, customFile)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (pool !== p) return@post
                val custom = files.distinct().size == 1 && files[0] == customFile
                var sharedId = 0
                files.forEachIndexed { i, f ->
                    if (f == null) return@forEachIndexed
                    ids[i] = if (custom && sharedId != 0) sharedId else p.load(f.path, 1).also { sharedId = it }
                    kindGain[i] = if (custom) CUSTOM_KIND_GAIN[i] else 1f
                }
            }
        })
    }

    /** Nhả SoundPool (ẩn bàn phím, thiếu RAM, tắt setting). */
    fun releaseSound() {
        pool?.release()
        pool = null
        poolKey = null
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
                val g = gain * kindGain[i]
                if (loaded[i]) pool?.play(ids[i], g, g, 1, 0, 1f)
            }
            KeySoundSynth.Route.SILENT -> {}
        }
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
        private val CUSTOM_KIND_GAIN = floatArrayOf(1f, 0.9f, 0.82f)   // = KeySoundCustom.variant

        /** Loại phím → tiếng: chữ / xoá / còn lại (cách, Enter, shift… như stock). */
        fun soundKind(kind: Int): KeySoundSynth.Kind = when (kind) {
            LETTER -> KeySoundSynth.Kind.LETTER
            DELETE -> KeySoundSynth.Kind.DELETE
            else -> KeySoundSynth.Kind.MODIFIER
        }

        /** File âm tự chọn đã xử lý (noBackupFilesDir — không vào Auto Backup). */
        fun customFile(ctx: Context): File = File(ctx.noBackupFilesDir, KeySoundCustom.FILE_NAME)

        /**
         * File cho 3 loại phím theo kiểu đã lưu: custom hợp lệ ⇒ cùng một file tự chọn; còn lại
         * (hoặc custom vắng/hỏng) ⇒ WAV tổng hợp của kiểu thật sự phát. Chạy trên worker.
         */
        fun soundFiles(dir: File, style: String, custom: File?): List<File?> {
            val ok = style == KeySoundStyle.CUSTOM.id && KeySoundCustom.load(custom) != null
            val st = KeySoundStyle.resolve(style, ok)
            return if (st == KeySoundStyle.CUSTOM) KeySoundSynth.Kind.entries.map { custom }
            else KeySoundSynth.Kind.entries.map { wavFile(dir, st, it) }
        }

        /** WAV tất định ghi 1 lần vào cache (tên kèm VERSION + kiểu). null nếu ghi lỗi. */
        fun wavFile(dir: File, k: KeySoundSynth.Kind): File? = wavFile(dir, KeySoundStyle.DEFAULT, k)

        fun wavFile(dir: File, style: KeySoundStyle, k: KeySoundSynth.Kind): File? = runCatching {
            val f = File(dir, "keysound-v${KeySoundSynth.VERSION}-${style.id}-${k.name.lowercase()}.wav")
            if (!f.exists() || f.length() == 0L) {
                val tmp = File(dir, f.name + ".tmp")
                tmp.writeBytes(KeySoundSynth.wav(style, k))
                tmp.renameTo(f)
            }
            f
        }.getOrNull()
    }
}
