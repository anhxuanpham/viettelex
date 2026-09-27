package com.viettelex.android.ime

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.view.ViewGroup
import android.view.WindowInsets
import kotlin.math.roundToInt

/**
 * Gốc input view: [KeyboardView] (vùng phím) · [StripView] (strip gợi ý, phủ 4 dp lên
 * mép phím) · [BalloonView] (overlay). Nền theme toàn khung (trong suốt được — độ trong suốt phím), cộng inset nav/gesture bar
 * ở đáy (cùng màu bàn phím, spec §6.1). Multi-touch tách theo view con.
 */
@SuppressLint("ViewConstructor")
class ImeRootView(
    context: Context,
    private val theme: ImeTheme,
    val keyboard: KeyboardView,
    val strip: StripView,
    val balloon: BalloonView,
    /** Vệt gõ vuốt — phủ đúng vùng phím, dưới balloon. */
    val trail: SwipeTrailView,
) : ViewGroup(context) {

    private var navInset = 0

    /** Ảnh nền (null = không dùng) — vẽ trong onDraw: bitmap center-crop + lớp phủ phẳng. */
    private val wallpaperFile: java.io.File? =
        if (theme.palette.wallpaper) java.io.File(context.filesDir, com.viettelex.keyboard.Keys.WALLPAPER_FILE) else null
    private var wallpaper: android.graphics.Bitmap? = null
    private val wallMatrix = android.graphics.Matrix()
    // Độ trong suốt phím: alpha paint của bitmap + lớp phủ (không layer offscreen).
    private val wallPaint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG).apply {
        alpha = (theme.palette.surfaceAlpha * 255).toInt()
    }
    private val dimColor = theme.withAlpha(theme.palette.wallpaperOverlay, theme.settings.dim / 100f * theme.palette.surfaceAlpha)

    init {
        val bottom = theme.palette.bgBottom
        when {
            wallpaperFile != null -> { setBackgroundColor(theme.bg); setWillNotDraw(false) }
            // Kính giả lập: gradient dọc (GradientDrawable — vẽ phẳng, không blur).
            bottom != null -> background = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(theme.bg, bottom))
            else -> setBackgroundColor(theme.bg)
        }
        isMotionEventSplittingEnabled = true
        addView(keyboard)
        addView(strip)
        addView(trail)
        addView(balloon)
    }

    private fun stripPx() = strip.stripPx().roundToInt()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val f = wallpaperFile ?: return
        val b = WallpaperBitmap.load(f, theme.settings.version, w, h)
        wallpaper = b
        if (b != null) {
            // center-crop
            val s = maxOf(w.toFloat() / b.width, h.toFloat() / b.height)
            wallMatrix.setScale(s, s)
            wallMatrix.postTranslate((w - b.width * s) / 2f, (h - b.height * s) / 2f)
        }
        invalidate()
    }

    override fun onDraw(canvas: android.graphics.Canvas) {
        super.onDraw(canvas)
        val b = wallpaper ?: return
        canvas.drawBitmap(b, wallMatrix, wallPaint)
        canvas.drawColor(dimColor)
    }
    /** Bảng phủ đúng vùng phím (lịch sử clipboard); null = không có. Thêm lười khi mở lần đầu. */
    var overlay: android.view.View? = null
        set(v) {
            if (field === v) return
            field?.let { removeView(it) }
            field = v
            if (v != null) addView(v, indexOfChild(balloon))
        }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val keyH = keyboard.keyAreaPx.roundToInt()
        val s = stripPx()
        val h = ImeInsets.totalHeight(s, keyH, navInset)
        keyboard.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        strip.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(strip.viewHeightPx(), MeasureSpec.EXACTLY))
        trail.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        overlay?.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(keyH, MeasureSpec.EXACTLY))
        balloon.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(s + keyH, MeasureSpec.EXACTLY))
        setMeasuredDimension(w, h)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val w = r - l
        val s = stripPx()
        val keyH = keyboard.measuredHeight
        keyboard.layout(0, s, w, s + keyH)
        strip.layout(0, 0, w, strip.measuredHeight)
        trail.layout(0, s, w, s + keyH)
        overlay?.layout(0, s, w, s + keyH)
        balloon.layout(0, 0, w, s + keyH)
    }

    private var insetsKnown = false

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        applyInsets(insets)
        return insets
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        refreshInsets()
    }

    /**
     * Đọc insets CHƯA bị nuốt của cửa sổ IME (khung IMS có thể consume trước khi tới
     * view này) — gọi mỗi lần bàn phím hiện.
     */
    fun refreshInsets() {
        val ri = rootView?.rootWindowInsets
        if (ri != null) applyInsets(ri) else update(0, 0)
    }

    @Suppress("DEPRECATION")
    private fun applyInsets(insets: WindowInsets) {
        val nav: Int
        val tap: Int
        if (Build.VERSION.SDK_INT >= 30) {
            nav = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
            tap = insets.getInsets(WindowInsets.Type.tappableElement()).bottom
        } else {
            nav = insets.systemWindowInsetBottom
            tap = if (Build.VERSION.SDK_INT >= 29) insets.tappableElementInsets.bottom else 0
        }
        insetsKnown = true
        update(nav, tap)
    }

    private fun update(nav: Int, tap: Int) {
        val pad = ImeInsets.bottomPad(Build.VERSION.SDK_INT, nav, tap, systemNavBarHeight(), insetsKnown)
        if (pad != navInset) { navInset = pad; requestLayout() }
    }

    @android.annotation.SuppressLint("DiscouragedApi", "InternalInsetResource")
    private fun systemNavBarHeight(): Int {
        val r = resources
        for (name in arrayOf("navigation_bar_frame_height", "navigation_bar_height")) {
            val id = r.getIdentifier(name, "dimen", "android")
            if (id != 0) { val v = r.getDimensionPixelSize(id); if (v > 0) return v }
        }
        return 0
    }
}
