package com.viettelex.keyboard

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Âm thanh phím riêng (setting [Keys.KEY_SOUND], mặc định TẮT): 3 tiếng click tổng hợp
 * tất định lúc chạy — chữ / xoá / phím chức năng (cách, Enter, shift… như stock). Không có
 * file âm thanh bên thứ ba. Thuật toán y hệt iOS/Keyboard/KeySound.swift (KeySoundSynth).
 */
object KeySoundSynth {
    const val SAMPLE_RATE = 44_100
    /** Đổi khi đổi thuật toán ⇒ tên file WAV cache đổi theo. */
    const val VERSION = 1

    enum class Kind { LETTER, DELETE, MODIFIER }

    class Voice(val freq: Double, val toneTau: Double, val noiseTau: Double, val noiseMix: Double,
                val duration: Double, val seed: Int)

    fun voice(k: Kind): Voice = when (k) {
        Kind.LETTER -> Voice(1850.0, 0.0045, 0.0022, 0.55, 0.028, 0x12345678)
        Kind.DELETE -> Voice(1300.0, 0.0055, 0.0028, 0.50, 0.032, 0x23456789)
        Kind.MODIFIER -> Voice(900.0, 0.0075, 0.0035, 0.45, 0.040, 0x3456789A)
    }

    /** Mẫu mono −1…1, đỉnh chuẩn hoá 0.9. */
    fun samples(k: Kind): FloatArray {
        val v = voice(k)
        val sr = SAMPLE_RATE.toDouble()
        val n = (v.duration * sr).roundToInt()
        val out = DoubleArray(n)
        var state = v.seed
        // Nhiễu trắng → high-pass một cực (bỏ ù) → low-pass một cực (bỏ xì) ≈ dải 1–6 kHz.
        val hpA = exp(-2 * PI * 1000 / sr)
        val lpA = exp(-2 * PI * 6000 / sr)
        var hpPrevIn = 0.0; var hpPrevOut = 0.0; var lp = 0.0
        val attack = (0.0004 * sr).toInt()
        val release = (0.002 * sr).toInt()
        var peak = 0.0
        for (i in 0 until n) {
            val t = i / sr
            state = state xor (state shl 13); state = state xor (state ushr 17); state = state xor (state shl 5)  // xorshift32
            val white = (state.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
            val hp = hpA * (hpPrevOut + white - hpPrevIn)
            hpPrevIn = white; hpPrevOut = hp
            lp = (1 - lpA) * hp + lpA * lp
            val tone = sin(2 * PI * v.freq * t) * exp(-t / v.toneTau) +
                0.35 * sin(2 * PI * v.freq * 2.03 * t) * exp(-t / (v.toneTau * 0.6))
            var s = tone + v.noiseMix * 3 * lp * exp(-t / v.noiseTau)
            if (i < attack) s *= i.toDouble() / attack
            if (i >= n - release) s *= (n - 1 - i).toDouble() / release
            out[i] = s
            peak = maxOf(peak, abs(s))
        }
        val norm = if (peak > 0) 0.9 / peak else 0.0
        return FloatArray(n) { (out[it] * norm).toFloat() }
    }

    /** WAV PCM 16-bit mono (SoundPool chỉ nạp từ file/fd). */
    fun wav(k: Kind): ByteArray {
        val s = samples(k)
        val data = s.size * 2
        val b = java.nio.ByteBuffer.allocate(44 + data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(SAMPLE_RATE).putInt(SAMPLE_RATE * 2).putShort(2).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        for (x in s) b.putShort((x.coerceIn(-1f, 1f) * 32767f).roundToInt().toShort())
        return b.array()
    }

    /** 0…100 % → biên độ SoundPool; bình phương cho cảm giác to/nhỏ đều tay. */
    fun gain(percent: Int): Float {
        val x = percent.coerceIn(0, 100) / 100f
        return x * x
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
