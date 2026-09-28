package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** Kiểu âm phím (setting [Keys.KEY_SOUND_STYLE]); [id] = giá trị lưu/sao lưu (giống iOS). */
enum class KeySoundStyle(val id: String, val viTitle: String) {
    SUBTLE("subtle", "Nhẹ nhàng"), // l10n-key
    WOOD("wood", "Gõ gỗ"), // l10n-key
    MECHANICAL("mechanical", "Bàn phím cơ"), // l10n-key
    TYPEWRITER("typewriter", "Máy chữ"), // l10n-key
    BUBBLE("bubble", "Bong bóng"), // l10n-key
    CUSTOM("custom", "Âm của bạn"); // l10n-key

    companion object {
        val DEFAULT = SUBTLE
        val PRESETS = listOf(SUBTLE, WOOD, MECHANICAL, TYPEWRITER, BUBBLE)
        val IDS: Set<String> = entries.map { it.id }.toSet()
        fun of(id: String?): KeySoundStyle? = entries.firstOrNull { it.id == id }

        /** Giá trị lưu → kiểu thật sự phát. Lạ ⇒ mặc định; custom mà file vắng/hỏng ⇒ mặc định. */
        fun resolve(raw: String?, customAvailable: Boolean): KeySoundStyle {
            val s = of(raw) ?: return DEFAULT
            return if (s == CUSTOM && !customAvailable) DEFAULT else s
        }
    }
}

/**
 * Âm thanh phím riêng (setting [Keys.KEY_SOUND], mặc định TẮT): 3 tiếng (chữ / xoá / phím
 * chức năng) theo [KeySoundStyle], tổng hợp tất định lúc chạy — không có file âm thanh bên
 * thứ ba. Thuật toán + công thức Y HỆT iOS/Shared/KeySoundSynth.swift (test chốt checksum
 * chung). Công thức từng kiểu + lý do "không chói" ghi ở đầu file Swift.
 */
object KeySoundSynth {
    const val SAMPLE_RATE = 44_100
    /** Đổi khi đổi thuật toán/công thức ⇒ tên file WAV cache đổi theo. */
    const val VERSION = 2

    enum class Kind { LETTER, DELETE, MODIFIER }

    data class Tone(val amp: Double, val delay: Double, val f0: Double, val fEnd: Double, val glide: Double, val tau: Double)
    data class Noise(val amp: Double, val delay: Double, val hp: Double, val lp: Double, val tau: Double)
    data class Recipe(val tones: List<Tone>, val noises: List<Noise>, val attack: Double, val duration: Double,
                      val outLP: Double, val peak: Double)

    private fun t(amp: Double, f0: Double, fEnd: Double, glide: Double = 0.008, tau: Double, delay: Double = 0.0) =
        Tone(amp, delay, f0, fEnd, glide, tau)
    private fun n(amp: Double, hp: Double = 120.0, lp: Double, tau: Double, delay: Double = 0.0) =
        Noise(amp, delay, hp, lp, tau)

    fun baseRecipe(s: KeySoundStyle): Recipe = when (s) {
        KeySoundStyle.SUBTLE, KeySoundStyle.CUSTOM -> Recipe(
            listOf(t(1.0, 500.0, 360.0, tau = 0.007), t(0.24, 1050.0, 900.0, tau = 0.0025)),
            listOf(n(0.30, lp = 1900.0, tau = 0.002)), 0.0016, 0.032, 2600.0, 0.80)
        KeySoundStyle.WOOD -> Recipe(
            listOf(t(1.0, 640.0, 590.0, tau = 0.009), t(0.28, 640 * 2.72, 590 * 2.72, tau = 0.0026)),
            listOf(n(0.30, lp = 2400.0, tau = 0.0014)), 0.0009, 0.042, 3800.0, 0.80)
        KeySoundStyle.MECHANICAL -> Recipe(
            listOf(t(1.0, 230.0, 180.0, glide = 0.010, tau = 0.012), t(0.55, 520.0, 450.0, tau = 0.0045),
                t(0.45, 300.0, 280.0, tau = 0.005, delay = 0.007)),
            listOf(n(0.55, hp = 90.0, lp = 1300.0, tau = 0.0035), n(0.28, hp = 90.0, lp = 1300.0, tau = 0.002, delay = 0.007)),
            0.0014, 0.046, 2400.0, 0.80)
        KeySoundStyle.TYPEWRITER -> Recipe(
            listOf(t(0.35, 1050.0, 850.0, glide = 0.004, tau = 0.003), t(0.55, 260.0, 240.0, tau = 0.008)),
            listOf(n(0.95, hp = 500.0, lp = 2600.0, tau = 0.0028), n(0.30, hp = 500.0, lp = 2600.0, tau = 0.0018, delay = 0.011)),
            0.0008, 0.044, 3200.0, 0.85)
        KeySoundStyle.BUBBLE -> Recipe(
            listOf(t(1.0, 260.0, 720.0, glide = 0.009, tau = 0.009), t(0.08, 520.0, 1440.0, glide = 0.009, tau = 0.006)),
            emptyList(), 0.003, 0.036, 3000.0, 0.80)
    }

    /** Xoá trầm hơn chút; phím chức năng trầm + dài hơn (như iOS). */
    fun recipe(s: KeySoundStyle, k: Kind): Recipe {
        val r = baseRecipe(s)
        val (pitch, decay, extra) = when (k) {
            Kind.LETTER -> return r
            Kind.DELETE -> Triple(0.86, 1.0, 0.0)
            Kind.MODIFIER -> Triple(0.74, 1.2, 0.006)
        }
        return r.copy(
            tones = r.tones.map { it.copy(f0 = it.f0 * pitch, fEnd = it.fEnd * pitch, tau = it.tau * decay) },
            noises = r.noises.map { it.copy(lp = it.lp * pitch, tau = it.tau * decay) },
            duration = r.duration + extra)
    }

    fun seed(s: KeySoundStyle, k: Kind): Int =
        (0x9E3779B9.toInt() * (s.ordinal + 1)) xor (0x85EBCA6B.toInt() * (k.ordinal + 1))

    fun samples(s: KeySoundStyle, k: Kind): FloatArray = render(recipe(s, k), seed(s, k))

    /** Tương thích: kiểu mặc định. */
    fun samples(k: Kind): FloatArray = samples(KeySoundStyle.DEFAULT, k)

    /** 3 mẫu (chữ / xoá / chức năng) cho kiểu đã lưu. custom vắng/hỏng ⇒ mặc định. */
    fun bank(raw: String?, custom: FloatArray?): Pair<KeySoundStyle, List<FloatArray>> {
        val st = KeySoundStyle.resolve(raw, custom != null)
        return if (st == KeySoundStyle.CUSTOM && custom != null) st to Kind.entries.map { KeySoundCustom.variant(custom, it) }
        else st to Kind.entries.map { samples(st, it) }
    }

    private fun ramp(t: Double, a: Double): Double = if (a <= 0 || t >= a) 1.0 else 0.5 - 0.5 * cos(PI * t / a)

    fun render(r: Recipe, seed: Int): FloatArray {
        val sr = SAMPLE_RATE.toDouble()
        val count = (r.duration * sr).roundToInt()
        val out = DoubleArray(count)
        for (tn in r.tones) {
            var phase = 0.0
            val start = (tn.delay * sr).roundToInt()
            for (i in start until count) {
                val tt = (i - start) / sr
                val f = tn.fEnd + (tn.f0 - tn.fEnd) * exp(-tt / tn.glide)
                phase += 2 * PI * f / sr
                out[i] += tn.amp * sin(phase) * exp(-tt / tn.tau) * ramp(tt, r.attack)
            }
        }
        r.noises.forEachIndexed { li, nz ->
            var state = seed xor (0x2545F491 * (li + 1))
            if (state == 0) state = 0x12345678
            val hpA = exp(-2 * PI * nz.hp / sr)
            val lpA = exp(-2 * PI * nz.lp / sr)
            var hpIn = 0.0; var hpOut = 0.0; var lp1 = 0.0; var lp2 = 0.0
            val start = (nz.delay * sr).roundToInt()
            for (i in start until count) {
                val tt = (i - start) / sr
                state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)
                val white = (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
                val hp = hpA * (hpOut + white - hpIn)
                hpIn = white; hpOut = hp
                lp1 = (1 - lpA) * hp + lpA * lp1
                lp2 = (1 - lpA) * lp1 + lpA * lp2
                out[i] += nz.amp * 2.5 * lp2 * exp(-tt / nz.tau) * ramp(tt, r.attack)
            }
        }
        val oA = exp(-2 * PI * r.outLP / sr)
        val dcA = exp(-2 * PI * 40 / sr)
        var y = 0.0; var dcIn = 0.0; var dcOut = 0.0
        val rel = minOf(count, (0.003 * sr).toInt())
        var peak = 0.0
        for (i in 0 until count) {
            y = (1 - oA) * out[i] + oA * y
            dcOut = dcA * (dcOut + y - dcIn); dcIn = y
            var v = dcOut
            val fromEnd = count - 1 - i
            if (fromEnd < rel) v *= 0.5 - 0.5 * cos(PI * fromEnd / rel)
            out[i] = v
            peak = maxOf(peak, abs(v))
        }
        val norm = if (peak > 0) r.peak / peak else 0.0
        return FloatArray(count) { (out[it] * norm).toFloat() }
    }

    /** 0…100 % → biên độ SoundPool; bình phương cho cảm giác to/nhỏ đều tay. */
    fun gain(percent: Int): Float {
        val x = percent.coerceIn(0, 100) / 100f
        return x * x
    }

    // --- đo đạc (test) ---

    /** Trọng tâm phổ (Hz), trọng số biên độ DFT. Cao ⇒ chói. */
    fun spectralCentroid(x: FloatArray, sr: Double = SAMPLE_RATE.toDouble()): Double {
        val n = x.size
        if (n < 2) return 0.0
        var num = 0.0; var den = 0.0
        for (k in 1..n / 2) {
            var re = 0.0; var im = 0.0
            val w = 2 * PI * k / n
            for (i in 0 until n) { re += x[i] * cos(w * i); im -= x[i] * sin(w * i) }
            val mag = sqrt(re * re + im * im)
            num += mag * k * sr / n; den += mag
        }
        return if (den > 0) num / den else 0.0
    }

    fun rms(x: FloatArray): Double = if (x.isEmpty()) 0.0 else sqrt(x.sumOf { it.toDouble() * it } / x.size)

    // --- WAV PCM 16-bit mono (SoundPool chỉ nạp từ file/fd) ---

    fun wav(k: Kind): ByteArray = wav(samples(k))
    fun wav(style: KeySoundStyle, k: Kind): ByteArray = wav(samples(style, k))

    fun wav(s: FloatArray, sampleRate: Int = SAMPLE_RATE): ByteArray {
        val data = s.size * 2
        val b = java.nio.ByteBuffer.allocate(44 + data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(sampleRate).putInt(sampleRate * 2).putShort(2).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        for (x in s) b.putShort((x.coerceIn(-1f, 1f) * 32767f).toInt().toShort())
        return b.array()
    }

    /** Đọc WAV PCM 16-bit (mono/stereo → mono). null nếu không phải định dạng đó. */
    fun parseWav(d: ByteArray): Pair<FloatArray, Double>? {
        if (d.size < 44 || String(d, 0, 4) != "RIFF" || String(d, 8, 4) != "WAVE") return null
        fun u16(o: Int) = (d[o].toInt() and 0xFF) or ((d[o + 1].toInt() and 0xFF) shl 8)
        fun u32(o: Int) = u16(o) or (u16(o + 2) shl 16)
        var o = 12
        var channels = 0; var rate = 0; var bits = 0; var tag = 0
        while (o + 8 <= d.size) {
            val id = String(d, o, 4)
            val size = u32(o + 4)
            val body = o + 8
            if (id == "fmt " && body + 16 <= d.size) {
                tag = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if (id == "data") {
                if (tag != 1 || bits != 16 || channels < 1 || rate <= 0) return null
                val end = minOf(d.size.toLong(), body.toLong() + (size.toLong() and 0xFFFFFFFFL)).toInt()
                val frames = (end - body) / (2 * channels)
                val out = FloatArray(frames) { f ->
                    var acc = 0.0
                    for (c in 0 until channels) acc += u16(body + (f * channels + c) * 2).toShort().toDouble()
                    (acc / channels / 32768).toFloat()
                }
                return out to rate.toDouble()
            }
            if (size < 0) return null
            o = body + size + (size and 1)
        }
        return null
    }

    enum class Route { SYSTEM, CUSTOM, SILENT }

    /**
     * Đường âm cho một lần bấm. TẮT ⇒ [Route.SYSTEM] (AudioManager.playSoundEffect như cũ —
     * theo "Âm thanh khi chạm" của máy). BẬT ⇒ tiếng riêng, KHÔNG kèm tiếng hệ thống; im khi
     * máy ở chế độ Rung/Im lặng (như Gboard/AOSP LatinIME) hoặc âm lượng 0.
     */
    fun route(enabled: Boolean, volumePercent: Int, ringerNormal: Boolean): Route = when {
        !enabled -> Route.SYSTEM
        !ringerNormal || volumePercent <= 0 -> Route.SILENT
        else -> Route.CUSTOM
    }
}

/**
 * Âm tự chọn: xử lý thuần sau khi giải mã (Android: MediaCodec; iOS: AVAudioFile) — giống
 * hệt Swift KeySoundCustom. 44.1 kHz mono, bỏ lặng đầu/cuối, cắt ≤ 300 ms, mở/đóng mềm,
 * chuẩn hoá đỉnh 0.8 + trần RMS 0.22.
 */
object KeySoundCustom {
    const val MAX_DURATION = 0.300
    const val TARGET_PEAK = 0.80f
    const val MAX_RMS = 0.22
    /** Trong noBackupFilesDir của app (IME cùng process đọc được) — không vào sao lưu. */
    const val FILE_NAME = "keysound-custom.wav"

    class Failure(val silent: Boolean) : Exception(if (silent) "silent" else "empty")
    data class Result(val samples: FloatArray, val truncated: Boolean)

    fun process(mono: FloatArray, sampleRate: Double): Result {
        if (mono.isEmpty() || sampleRate <= 0) throw Failure(silent = false)
        val sr = KeySoundSynth.SAMPLE_RATE.toDouble()
        val x = resample(mono, sampleRate, sr)
        val peak = x.maxOf { abs(it) }
        if (peak < 0.001f) throw Failure(silent = true)
        val thr = maxOf(peak * 0.05f, 0.001f)
        val first = x.indexOfFirst { abs(it) >= thr }.coerceAtLeast(0)
        val last = x.indexOfLast { abs(it) >= thr }.let { if (it < 0) x.size - 1 else it }
        val start = maxOf(0, first - (0.002 * sr).toInt())
        val endAll = minOf(x.size, last + 1 + (0.010 * sr).toInt())
        val cap = (MAX_DURATION * sr).toInt()
        val truncated = endAll - start > cap
        val end = minOf(endAll, start + cap)
        val y = x.copyOfRange(start, end)
        val fin = minOf(y.size, (0.001 * sr).toInt())
        for (i in 0 until fin) y[i] *= (0.5 - 0.5 * cos(PI * i / fin)).toFloat()
        val fout = minOf(y.size, ((if (truncated) 0.015 else 0.005) * sr).toInt())
        for (j in 0 until fout) { val i = y.size - 1 - j; y[i] *= (0.5 - 0.5 * cos(PI * j / fout)).toFloat() }
        val p2 = y.maxOf { abs(it) }
        if (p2 <= 0f) throw Failure(silent = true)
        var g = TARGET_PEAK / p2
        val r = KeySoundSynth.rms(y) * g
        if (r > MAX_RMS) g *= (MAX_RMS / r).toFloat()
        return Result(FloatArray(y.size) { y[it] * g }, truncated)
    }

    fun resample(x: FloatArray, from: Double, to: Double): FloatArray {
        if (abs(from - to) < 0.5 || x.size < 2) return x
        val n = maxOf(1, (x.size * to / from).roundToInt())
        val step = from / to
        return FloatArray(n) { i ->
            val p = i * step
            val j = p.toInt()
            if (j >= x.size - 1) x[x.size - 1]
            else { val f = (p - j).toFloat(); x[j] * (1 - f) + x[j + 1] * f }
        }
    }

    /** Mẫu cho từng loại phím: chữ nguyên bản, xoá/chức năng nhỏ hơn chút. */
    fun variant(s: FloatArray, k: KeySoundSynth.Kind): FloatArray = when (k) {
        KeySoundSynth.Kind.LETTER -> s
        KeySoundSynth.Kind.DELETE -> FloatArray(s.size) { s[it] * 0.9f }
        KeySoundSynth.Kind.MODIFIER -> FloatArray(s.size) { s[it] * 0.82f }
    }

    /** Đọc file âm tự chọn đã xử lý. null ⇒ vắng/hỏng ⇒ dùng mặc định. */
    fun load(f: java.io.File?): FloatArray? {
        if (f == null || !f.isFile) return null
        val (s, rate) = runCatching { KeySoundSynth.parseWav(f.readBytes()) }.getOrNull() ?: return null
        if (s.isEmpty() || s.size > (MAX_DURATION * KeySoundSynth.SAMPLE_RATE).toInt() + 16) return null
        return resample(s, rate, KeySoundSynth.SAMPLE_RATE.toDouble())
    }

    /** Khoá bộ mẫu: kiểu + (nếu tự chọn) ngày sửa + cỡ file ⇒ app thay file là nạp lại. */
    fun bankKey(style: String, file: java.io.File?): String =
        if (style != KeySoundStyle.CUSTOM.id || file == null || !file.isFile) style
        else "$style@${file.lastModified()}#${file.length()}"
}

/**
 * Giới hạn tần suất nghe/rung thử khi kéo thanh trượt: ≤ 1 lần / [intervalMs] khi kéo, luôn
 * phát lúc thả (trừ khi vừa phát đúng giá trị đó rất gần). Thuần — test được. Giống iOS.
 */
class PreviewThrottle(private val intervalMs: Long = 120) {
    private var lastFire = Long.MIN_VALUE / 2
    private var lastValue: Int? = null

    fun shouldFire(value: Int, nowMs: Long, final: Boolean): Boolean {
        val elapsed = nowMs - lastFire
        val fire = if (final) value != lastValue || elapsed >= intervalMs
                   else elapsed >= intervalMs && value != lastValue
        if (fire) { lastFire = nowMs; lastValue = value }
        return fire
    }
}
