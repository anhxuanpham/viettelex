package com.viettelex.android.ime

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.provider.OpenableColumns
import com.viettelex.keyboard.KeySoundCustom
import com.viettelex.keyboard.KeySoundSynth
import java.io.File
import java.nio.ByteOrder

/**
 * Âm phím tự chọn (Phím & cử chỉ → Phản hồi khi chạm): SAF ACTION_OPEN_DOCUMENT (mime audio) →
 * MediaExtractor + MediaCodec giải mã (mp3/m4a/ogg/wav/flac…, tối đa 10 s đầu) → trộn mono →
 * [KeySoundCustom.process] (44.1 kHz, bỏ lặng, cắt ≤ 300 ms, chuẩn hoá) → WAV 16-bit mono
 * (~26 KB) ở noBackupFilesDir (IME cùng process đọc; KHÔNG vào Auto Backup / file sao lưu —
 * chỉ key keySoundStyle đi theo). IME nạp khi kiểu = custom; vắng/hỏng ⇒ "Nhẹ nhàng".
 */
object KeySoundImport {
    enum class Failure { UNREADABLE, TOO_LARGE, SILENT }
    class ImportException(val failure: Failure) : Exception(failure.name)
    data class Outcome(val duration: Double, val truncated: Boolean)

    const val MAX_BYTES = 30L * 1024 * 1024
    const val MAX_DECODE_SECONDS = 10.0

    fun importUri(ctx: Context, uri: Uri, dest: File = Feedback.customFile(ctx)): Outcome {
        val size = runCatching {
            ctx.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null
            }
        }.getOrNull()
        if (size != null && size > MAX_BYTES) throw ImportException(Failure.TOO_LARGE)
        val (mono, rate) = runCatching { decode(ctx, uri) }.getOrNull() ?: throw ImportException(Failure.UNREADABLE)
        if (mono.isEmpty()) throw ImportException(Failure.UNREADABLE)
        val r = try { KeySoundCustom.process(mono, rate) } catch (_: KeySoundCustom.Failure) { throw ImportException(Failure.SILENT) }
        write(dest, KeySoundSynth.wav(r.samples))
        return Outcome(r.samples.size / KeySoundSynth.SAMPLE_RATE.toDouble(), r.truncated)
    }

    /** Ghi nguyên tử (tmp → rename). */
    fun write(dest: File, bytes: ByteArray) {
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, dest.name + ".tmp")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(dest)) { dest.delete(); tmp.renameTo(dest) }
    }

    fun remove(ctx: Context) { Feedback.customFile(ctx).delete() }

    fun storedDuration(ctx: Context): Double? =
        KeySoundCustom.load(Feedback.customFile(ctx))?.let { it.size / KeySoundSynth.SAMPLE_RATE.toDouble() }

    /** Giải mã track audio đầu tiên → mono Float ở tần số gốc (≤ 10 s). null ⇒ không đọc được. */
    fun decode(ctx: Context, uri: Uri): Pair<FloatArray, Double>? {
        val ex = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            ex.setDataSource(ctx, uri, null)
            val track = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            ex.selectTrack(track)
            val inFmt = ex.getTrackFormat(track)
            var rate = inFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = inFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var float = false
            val c = MediaCodec.createDecoderByType(inFmt.getString(MediaFormat.KEY_MIME)!!)
            codec = c
            c.configure(inFmt, null, null, 0)
            c.start()
            val out = ArrayList<Float>(rate)
            val maxFrames = (rate * MAX_DECODE_SECONDS).toInt()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var idle = 0
            while (!outputDone && out.size < maxFrames && idle < 200) {
                if (!inputDone) {
                    val ii = c.dequeueInputBuffer(10_000)
                    if (ii >= 0) {
                        val buf = c.getInputBuffer(ii)!!
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0) { c.queueInputBuffer(ii, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true }
                        else { c.queueInputBuffer(ii, 0, n, ex.sampleTime, 0); ex.advance() }
                    }
                }
                val oi = c.dequeueOutputBuffer(info, 10_000)
                when {
                    oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = c.outputFormat
                        rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        float = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    oi >= 0 -> {
                        idle = 0
                        val buf = c.getOutputBuffer(oi)!!.order(ByteOrder.nativeOrder())
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        val ch = channels.coerceAtLeast(1)
                        if (float) {
                            val fb = buf.asFloatBuffer()
                            while (fb.remaining() >= ch) { var acc = 0f; repeat(ch) { acc += fb.get() }; out.add(acc / ch) }
                        } else {
                            val sb = buf.asShortBuffer()
                            while (sb.remaining() >= ch) { var acc = 0f; repeat(ch) { acc += sb.get() / 32768f }; out.add(acc / ch) }
                        }
                        c.releaseOutputBuffer(oi, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                    else -> idle++
                }
            }
            val n = minOf(out.size, maxFrames)
            return FloatArray(n) { out[it] } to rate.toDouble()
        } finally {
            runCatching { codec?.stop() }; runCatching { codec?.release() }
            ex.release()
        }
    }
}

/**
 * Nghe/rung thử trong app — cùng mẫu + cùng đường cong âm lượng + cùng [KeyVibrator] như bàn
 * phím. Âm: AudioTrack tĩnh (USAGE_ASSISTANCE_SONIFICATION như SoundPool của IME) và IM khi
 * máy để Rung/Im lặng — cố ý giống bàn phím (nghe thử phải đúng cảm giác lúc gõ); chú thích
 * dưới thanh trượt nhắc điều này. Rung thử luôn chạy (Rung/Im lặng không chặn rung).
 */
class KeyFeedbackPreview(ctx: Context) {
    private val appCtx = ctx.applicationContext
    private val audio = appCtx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val vibrator = KeyVibrator(appCtx)
    private var track: AudioTrack? = null
    private var trackKey: String? = null

    fun playSound(style: String, volume: Int) {
        if (runCatching { audio.ringerMode != AudioManager.RINGER_MODE_NORMAL }.getOrDefault(false)) return
        val custom = Feedback.customFile(appCtx)
        val key = KeySoundCustom.bankKey(style, custom)
        if (key != trackKey || track == null) {
            release()
            val samples = KeySoundSynth.bank(style, KeySoundCustom.load(custom)).second[0]
            val pcm = ShortArray(samples.size) { (samples[it].coerceIn(-1f, 1f) * 32767f).toInt().toShort() }
            track = runCatching {
                AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(KeySoundSynth.SAMPLE_RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(pcm.size * 2)
                    .build().also { it.write(pcm, 0, pcm.size) }
            }.getOrNull()
            trackKey = key
        }
        val t = track ?: return
        runCatching {
            if (t.playState == AudioTrack.PLAYSTATE_PLAYING) t.stop()
            t.reloadStaticData()
            t.setVolume(KeySoundSynth.gain(volume))
            t.play()
        }
    }

    fun playHaptic(strength: Int) { vibrator.vibrate(strength) }

    fun release() {
        runCatching { track?.release() }
        track = null; trackKey = null
    }
}
