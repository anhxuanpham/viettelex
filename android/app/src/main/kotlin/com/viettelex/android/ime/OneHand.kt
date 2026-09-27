package com.viettelex.android.ime

/**
 * Chế độ một tay (điện thoại, không tablet): bàn phím thu hẹp còn [RATIO] bề ngang và
 * dồn sang trái / phải; dải trống bên kia ("rail") có nút đổi bên + thoát. THUẦN (không
 * Android API) — pinned by OneHandTest.
 *
 * Cách áp: [KeyLayout.build] dựng plane ở bề ngang hẹp rồi dời x ⇒ router, gõ vuốt (tâm
 * phím thật), vuốt ⌫ (bước = bề rộng phím), trackpad (tương đối) đều đúng mà không cần
 * biết tới một tay. Emoji / mẫu câu giữ nguyên bề ngang (pane tự dàn).
 */
enum class OneHandSide {
    OFF, LEFT, RIGHT;

    /** Giá trị lưu prefs (Keys.ONE_HAND_MODE) — cùng chuỗi với iOS App Group. */
    val pref: String get() = name.lowercase()

    companion object {
        fun fromPref(s: String?): OneHandSide = when (s) {
            "left" -> LEFT
            "right" -> RIGHT
            else -> OFF
        }
    }
}

object OneHand {
    /** Bề ngang bàn phím khi thu hẹp (Gboard ≈ 0.8, iOS ≈ 0.85). */
    const val RATIO = 0.82f

    /** Plane nào thu hẹp — emoji / mẫu câu là pane tự dàn theo bề ngang cả view. */
    fun appliesTo(plane: Plane): Boolean = plane != Plane.EMOJI && plane != Plane.TEMPLATES

    /** (x0, width) vùng phím trong view rộng [widthPx]. OFF ⇒ cả view. */
    fun span(widthPx: Float, side: OneHandSide): Pair<Float, Float> {
        if (side == OneHandSide.OFF) return 0f to widthPx
        val w = widthPx * RATIO
        return (if (side == OneHandSide.LEFT) 0f else widthPx - w) to w
    }

    /** Dải trống [left, right) chứa nút rail; null khi OFF. */
    fun rail(widthPx: Float, side: OneHandSide): Pair<Float, Float>? {
        if (side == OneHandSide.OFF) return null
        val (x0, w) = span(widthPx, side)
        return if (side == OneHandSide.LEFT) (x0 + w) to widthPx else 0f to x0
    }

    /** Nút rail: 0 = đổi bên, 1 = thoát; -1 = không trúng. Hai nút chia đôi chiều cao. */
    fun railButton(widthPx: Float, heightPx: Float, side: OneHandSide, x: Float, y: Float): Int {
        val r = rail(widthPx, side) ?: return -1
        if (x < r.first || x >= r.second || y < 0f || y >= heightPx) return -1
        return if (y < heightPx / 2) 0 else 1
    }

    /** Nút "đổi bên". */
    fun switched(side: OneHandSide): OneHandSide = when (side) {
        OneHandSide.LEFT -> OneHandSide.RIGHT
        OneHandSide.RIGHT -> OneHandSide.LEFT
        OneHandSide.OFF -> OneHandSide.OFF
    }

    /** Giữ lâu / nút "Một tay": tắt ⇒ bật về phía [preferred] (mặc định phải); bật ⇒ tắt. */
    fun toggled(side: OneHandSide, preferred: OneHandSide = OneHandSide.RIGHT): OneHandSide =
        if (side != OneHandSide.OFF) OneHandSide.OFF
        else if (preferred == OneHandSide.OFF) OneHandSide.RIGHT else preferred

    /** Dời mọi phím [dx] px (sau khi dựng ở bề ngang hẹp). */
    fun shift(keys: List<LaidKey>, dx: Float) {
        if (dx == 0f) return
        for (k in keys) { k.left += dx; k.right += dx }
    }
}
