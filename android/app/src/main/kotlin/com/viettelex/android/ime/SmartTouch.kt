package com.viettelex.android.ime

import com.viettelex.keyboard.KPoint
import com.viettelex.keyboard.KRect
import com.viettelex.keyboard.TouchTarget

/**
 * Chọn phím theo ngữ cảnh (thử nghiệm) cho plane chữ — logic ở keyboard/TouchTarget.kt
 * (song sinh iOS). Router gần-nhất ra [hit]; chạm trong lõi phím ⇒ giữ ngay (0 alloc),
 * vùng biên ⇒ TouchTarget.choose với prior của từ đang gõ. Vài µs, không IPC.
 */
internal object SmartTouch {
    /** [x], [py]: điểm chọn phím (đã dời yOffset như KeyLayout.hit). */
    fun refine(keys: List<LaidKey>, hit: LaidKey, x: Float, py: Float, prior: ((Char) -> Float?)?): LaidKey {
        if (prior == null || hit.kind != KeyKind.LETTER || hit.label.length != 1) return hit
        val p = KPoint(x, py)
        if (TouchTarget.inCore(p, KRect(hit.left, hit.top, hit.right, hit.bottom))) return hit
        val letters = ArrayList<LaidKey>(32)
        for (k in keys) if (k.kind == KeyKind.LETTER && k.label.length == 1) letters.add(k)
        val idx = letters.indexOf(hit)
        if (idx < 0) return hit
        val rects = letters.map { KRect(it.left, it.top, it.right, it.bottom) }
        val chars = CharArray(letters.size) { letters[it].label[0] }
        return letters[TouchTarget.choose(p, rects, chars, idx, prior)]
    }
}
