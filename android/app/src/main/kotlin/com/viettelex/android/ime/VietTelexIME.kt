package com.viettelex.android.ime

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.inputmethodservice.InputMethodService
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.text.InputType
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.core.view.WindowInsetsControllerCompat
import com.viettelex.android.BuildConfig
import com.viettelex.android.shared.DebugLog
import com.viettelex.android.shared.VTPrefs
import com.viettelex.keyboard.ThemeSettings
import com.viettelex.keyboard.Cancellable
import com.viettelex.keyboard.EmojiData
import com.viettelex.keyboard.EmojiRecents
import com.viettelex.keyboard.FieldTraits
import com.viettelex.keyboard.Key
import com.viettelex.keyboard.KeyboardData
import com.viettelex.keyboard.KeyboardSession
import com.viettelex.keyboard.KeyboardSettings
import com.viettelex.keyboard.Keys
import com.viettelex.keyboard.MainThread
import com.viettelex.keyboard.SuggestionPlan
import com.viettelex.keyboard.SwipeDecoder
import com.viettelex.keyboard.SwipeEnglish
import com.viettelex.keyboard.SwipeLayout
import com.viettelex.keyboard.SwipePath
import com.viettelex.keyboard.SwipeSuggest
import com.viettelex.keyboard.SyllableBigram
import com.viettelex.keyboard.WriteMode
import com.viettelex.keyboard.TemplateItem
import com.viettelex.keyboard.PlusFeature
import com.viettelex.keyboard.PlusGate
import com.viettelex.keyboard.TextTool
import com.viettelex.keyboard.TextToolRunner
import com.viettelex.keyboard.TextTools
import com.viettelex.keyboard.Templates
import com.viettelex.keyboard.TouchLog
import com.viettelex.keyboard.UserLangModel
import java.io.File
import java.util.BitSet
import java.net.HttpURLConnection
import java.net.URL

/**
 * Bàn phím VietTelex (port iOS KeyboardViewController — phần nối dây; logic nằm ở
 * [KeyboardSession] của module :keyboard). Không Compose, không thư viện ngoài.
 *
 * Luồng: phím (touch-down) → session.handle trong MỘT batch edit → auto-shift ngay
 * lượt main kế → gợi ý sau 30 ms (phím mới huỷ lượt cũ) → phần nặng (VNSuggest +
 * AdjacentKeyFixer) trên HandlerThread "vt-suggest" → kết quả áp nếu còn hiện hành.
 * Không Handler nào được đặt khi không gõ.
 */
class VietTelexIME : InputMethodService(), KeyboardView.Listener, StripView.Listener {

    private val handler = Handler(Looper.getMainLooper())
    private val mainThread = object : MainThread {
        override fun post(r: Runnable) { handler.post(r) }
        override fun postDelayed(delayMs: Long, r: Runnable): Cancellable {
            handler.postDelayed(r, delayMs); return Cancellable { handler.removeCallbacks(r) }
        }
    }
    private lateinit var prefs: SharedPreferences
    private lateinit var model: UserLangModel
    private lateinit var clipboard: AndroidClipboard
    private lateinit var session: KeyboardSession
    private val tracker = SelectionTracker()
    private var portCache: AndroidEditorPort? = null
    private val proxy by lazy { IcProxy({ port() }, tracker) }
    private val swipe by lazy { SwipeDeleteController(proxy) }
    /** Đoạn vừa vuốt ⌫ xoá — ô "Khôi phục" một lượt; phím khác bất kỳ gỡ. */
    private var swipeUndo: String? = null
    /** Công cụ văn bản vừa áp ⇒ ô "↩︎ Hoàn tác" / ⌫ ngay sau (một lượt). */
    private var toolUndo: TextTools.Undo? = null

    /** Wrapper cache theo InputConnection hiện hành (không cấp phát mỗi phím). */
    private fun port(): EditorPort? {
        val ic = currentInputConnection ?: return null
        portCache?.let { if (it.ic === ic) return it }
        return AndroidEditorPort(ic).also { portCache = it }
    }
    private val feedback by lazy { Feedback(this) }

    private var worker: Handler? = null
    private var workerThread: HandlerThread? = null

    private var root: ImeRootView? = null
    private var keyboard: KeyboardView? = null
    private var strip: StripView? = null
    private var theme: ImeTheme? = null

    private var field = FieldMapping.map(0, 0)
    private var pendingGen = 0
    private var collapsed = false

    private val autoShiftRun = Runnable { if (pendingGen == session.generation) applyAutoShift() }
    private val suggestRun = Runnable { if (pendingGen == session.generation) refreshBar() }

    // --- gõ vuốt ---
    /**
     * Lõi giải mã (KHÔNG thread-safe): mọi truy cập nằm trong synchronized(swipeLock) —
     * prepare() chạy trên worker, setLayout/decode trên main. null khi tính năng tắt (0 RAM).
     */
    private var swipeDecoder: SwipeDecoder? = null
    private val swipeLock = Any()
    private var swipeSetting = false
    private var swipeFieldOk = false
    private var accessibility: AccessibilityManager? = null
    private val touchExplorationListener = AccessibilityManager.TouchExplorationStateChangeListener { updateSwipeTyping() }

    private val prefListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        // App vừa "Xóa từ đã học": bỏ model trong RAM NGAY (không bao giờ ghi đè lại).
        if (key == Keys.USERLM_RESET_AT) model.reloadAfterExternalErase()
        // Bật/tắt gõ vuốt trong app khi bàn phím đang mở (ô Thử gõ).
        else if (key == Keys.SWIPE_TYPING) { swipeSetting = VTPrefs.settings(prefs).swipeTyping; updateSwipeTyping() }
        else if (key == Keys.SWIPE_ENGLISH) session.swipeEnglish = VTPrefs.settings(prefs).swipeEnglish
        else if (key == Keys.HARDWARE_TELEX) hwSetting = VTPrefs.settings(prefs).hardwareTelex
        // Bật/tắt kiểu gõ trong app khi bàn phím đang mở (ô Thử gõ) → áp ngay, không đợi mở lại.
        else if (key in Keys.ENGINE_KEYS) session.bridge.applySettings(VTPrefs.settings(prefs))
    }

    override fun onCreate() {
        val t0 = SystemClock.elapsedRealtime()
        super.onCreate()
        prefs = VTPrefs.of(this)
        com.viettelex.android.plus.PlusPrefs.install(this)   // PlusGate đọc cờ Plus từ prefs chung
        KeyboardData.install(AssetBlobs.provider(assets))
        // Emoji mới hơn mức API chắc có → hỏi font hệ thống (ẩn emoji máy không vẽ được).
        EmojiData.trusted = EmojiData.trustedVersion(Build.VERSION.SDK_INT)
        val glyphPaint = android.graphics.Paint()
        EmojiData.glyphCheck = { e -> synchronized(glyphPaint) { glyphPaint.hasGlyph(e) } }
        DebugLog.configure(this, prefs.getBoolean(Keys.DEBUG_TOUCH_LOG, false))
        model = UserLangModel(File(filesDir, Keys.USERLM_FILE), mainThread)
        clipboard = AndroidClipboard(this)
        session = KeyboardSession(model, clipboard)
        model.onReady = { refreshBar() }
        prefs.registerOnSharedPreferenceChangeListener(prefListener)
        accessibility = (getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.also {
            it.addTouchExplorationStateChangeListener(touchExplorationListener)
        }
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onCreate ${SystemClock.elapsedRealtime() - t0} ms")
    }

    override fun onDestroy() {
        prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
        accessibility?.removeTouchExplorationStateChangeListener(touchExplorationListener)
        clipboard.release()
        workerThread?.quitSafely()
        session.finishInput()
        super.onDestroy()
    }

    /** iOS không có extract mode — luôn hiện bàn phím thường, kể cả ngang. */
    override fun onEvaluateFullscreenMode() = false

    override fun onCreateInputView(): View {
        val t0 = SystemClock.elapsedRealtime()
        val th = freshTheme()
        theme = th
        val balloon = BalloonView(this, th)
        val trail = SwipeTrailView(this, th)
        val kb = KeyboardView(this, th, balloon, feedback, trail)
        val st = StripView(this, th, feedback)
        kb.listener = this
        st.listener = this
        val r = ImeRootView(this, th, kb, st, balloon, trail)
        keyboard = kb; strip = st; root = r
        kb.setSwitcherHint(switcherHintVisible)
        styleWindow(th, r)
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onCreateInputView ${SystemClock.elapsedRealtime() - t0} ms")
        return r
    }

    /** Theme từ cài đặt hiện tại (rẻ: vài lần đọc màu resource, không giải ảnh). */
    private fun freshTheme(): ImeTheme {
        val all = prefs.all
        return ImeTheme(this, ThemeSettings.load { all[it] }, File(filesDir, Keys.WALLPAPER_FILE).exists())
    }

    @Suppress("DEPRECATION")
    private fun styleWindow(th: ImeTheme, v: View) {
        val w = window?.window ?: return
        if (Build.VERSION.SDK_INT < 35) w.navigationBarColor = th.bg
        if (Build.VERSION.SDK_INT >= 29) w.isNavigationBarContrastEnforced = false
        WindowInsetsControllerCompat(w, v).isAppearanceLightNavigationBars = !th.dark
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        val t0 = SystemClock.elapsedRealtime()
        super.onStartInputView(info, restarting)
        // Đổi theme/ảnh nền trong app → dựng lại input view (màu/Paint tạo sẵn trong view).
        if (theme != null && freshTheme().signature != theme?.signature) setInputView(onCreateInputView())
        val kb = keyboard ?: return
        val st = strip ?: return
        val th = theme ?: return
        val settings = VTPrefs.settings(prefs)
        DebugLog.configure(this, settings.debugTouchLog)
        // Đã gõ phím cứng trên ô này (onStartInput đã dựng ô, tracker/engine đang sống):
        // KHÔNG dựng lại từ EditorInfo cũ (initialSel đã lỗi thời) — chỉ lo phần giao diện.
        if (!hwTyped) configureField(info, settings)
        kb.holdNewline = field.holdNewline   // giữ lâu Enter = xuống dòng (ô nhiều dòng)
        feedback.hapticsEnabled = settings.hapticFeedback
        kb.searchSettings = settings
        swipeSetting = settings.swipeTyping
        // Chỉ ô chữ ghi COMMIT thường: không secure/passthrough (URI, email, mật khẩu hiện,
        // filter), không TYPE_NULL, không ô URL, không app phải ghi bằng key event.
        swipeFieldOk = !field.isSecure && !field.passthrough && !field.rawKeys && !proxy.uriField &&
            proxy.writeMode == WriteMode.COMMIT

        collapsed = prefs.getBoolean(Keys.SUGGESTION_BAR_COLLAPSED, false)
        session.barCollapsed = collapsed
        val barOn = session.suggestionsActive
        st.configure(barOn, collapsed, settings.templatesEnabled)
        val templates = if (settings.templatesEnabled) VTPrefs.templates(this, prefs) else emptyList()
        kb.configure(field.returnLabel, field.kind, needsGlobe(), settings.showSpaceLogo,
            settings.templatesEnabled, templates,
            th.dp(KeyLayout.keyAreaDp(th.tablet, th.landscape, settings.rowHeightAdjust, settings.numberRow)),
            field.numberSigned, field.numberDecimal, settings.numberRow)
        kb.textToolsEnabled = PlusGate.isUnlocked(PlusFeature.TEXT_TOOLS) && !field.isSecure
        st.setPlane(kb.plane)
        updateSwipeTyping()
        root?.refreshInsets()
        root?.requestLayout()

        session.invalidatePasteCache()
        applyAutoShift()
        refreshBar()                  // ô trống → gợi mở đầu ngay khi hiện
        if (BuildConfig.DEBUG) Log.d(TAG, "perf onStartInputView ${SystemClock.elapsedRealtime() - t0} ms")
    }

    /** Ô nhập → FieldMapping, IcProxy, tracker, session. Gọi ở onStartInputView (và onStartInput khi có phím cứng). */
    private fun configureField(info: EditorInfo, settings: KeyboardSettings) {
        field = FieldMapping.map(info.inputType, info.imeOptions, info.packageName,
            hasActionLabel = info.actionLabel != null, customActionId = info.actionId)
        proxy.secure = field.isSecure
        proxy.rawKeys = field.rawKeys
        proxy.multiLine = field.multiLine
        proxy.writeMode = com.viettelex.keyboard.WriteMode.forPackage(info.packageName)
        proxy.actionId = field.actionId
        proxy.uriField = (info.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
            (info.inputType and InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_URI
        startTracking(info)
        handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun)
        clearSwipeUndo()

        session.startInput(settings, FieldTraits(
            isSecure = field.isSecure, passthrough = field.passthrough,
            capSentences = field.capSentences, suggestionsAllowed = field.suggestionsAllowed,
            capWords = field.capWords, capCharacters = field.capCharacters,
            initialCaps = info.initialCapsMode != 0, noLearning = field.noLearning,
            packageName = info.packageName, urlField = proxy.uriField))
        hwSetting = settings.hardwareTelex
        fieldReady = true
    }

    /**
     * initialSel không tin tuyệt đối: đối chiếu độ dài getInitialTextBeforeCursor (API 30+);
     * lệch ⇒ con trỏ không biết. Khớp ⇒ nạp luôn shadow (khỏi IPC lượt đầu).
     */
    private fun startTracking(info: EditorInfo) {
        val before = if (Build.VERSION.SDK_INT >= 30 && !field.isSecure)
            info.getInitialTextBeforeCursor(IcProxy.CONTEXT_CAP, 0) else null
        val s = info.initialSelStart; val e = info.initialSelEnd
        val ok = InitialSelection.trusted(s, e, before?.length, IcProxy.CONTEXT_CAP)
        if (ok) tracker.reset(s, e) else tracker.reset(-1, -1)
        if (!ok && s >= 0 && TouchLog.enabled) TouchLog.write("initialSel $s..$e lệch initialTextBefore len=${before?.length}")
        proxy.startInput(if (ok) before else null,
            ok && before != null && InitialSelection.reachesFieldStart(s, e, before.length))
    }

    override fun onWindowShown() {
        super.onWindowShown()
        root?.refreshInsets()           // Android 15+: chừa dải cho nút ⌄/🌐 của hệ thống
        keyboard?.showLanguageBadge()   // "ViệtTelex" thoáng trên space như stock
        keyboard?.setNeedsGlobe(needsGlobe())
        if (BuildConfig.DEBUG) logMemory()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        super.onFinishInputView(finishingInput)
        swipeFieldOk = false
        handler.removeCallbacks(autoShiftRun); handler.removeCallbacks(suggestRun)
        keyboard?.onHidden()
        clearSwipeUndo()
        strip?.onHidden()
        root?.balloon?.hide()
        session.finishInput()
    }

    override fun onComputeInsets(outInsets: InputMethodService.Insets) {
        super.onComputeInsets(outInsets)
        // Toàn khung input view nhận touch — chạm vào khe không rơi sang app (§5).
        outInsets.touchableInsets = InputMethodService.Insets.TOUCHABLE_INSETS_CONTENT
    }

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int,
                                   candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        // Mình không dùng composing text: span còn (app/IME trước để sót) ⇒ chốt ở phím kế.
        if (candidatesStart != -1) proxy.finishComposingOnNextEdit()
        if (newSelStart < 0) proxy.invalidateShadow()   // "không biết": không reset engine, chỉ đọc lại chữ
        if (!tracker.onUpdate(newSelStart, newSelEnd)) return
        // Đổi từ NGOÀI (chạm chỗ khác, select-all, app tự sửa): quên từ + ngữ cảnh.
        proxy.invalidateShadow()
        session.externalSelectionChange()
        clearSwipeUndo()
        applyAutoShift()
        refreshBar()
    }

    // MARK: bàn phím cứng

    /** Công tắc "Telex cho bàn phím cứng" (Keys.HARDWARE_TELEX). */
    private var hwSetting = true
    /** configureField đã chạy cho ô hiện tại. */
    private var fieldReady = false
    /** Đã tiêu thụ ít nhất một phím cứng trên ô hiện tại. */
    private var hwTyped = false
    /** keyCode đã nuốt ở ACTION_DOWN ⇒ nuốt luôn ACTION_UP (app không nhận up mồ côi). */
    private val hwConsumed = BitSet()

    /**
     * Có phím cứng thì bàn phím ảo thường KHÔNG hiện (onEvaluateInputViewShown mặc định) ⇒
     * onStartInputView không chạy: dựng ô ngay ở đây để tracker theo dõi từ đầu. Không có
     * phím cứng ⇒ để onStartInputView lo như cũ (không tốn gì thêm cho người chỉ gõ chạm).
     */
    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        fieldReady = false
        hwTyped = false
        hwConsumed.clear()
        val settings = VTPrefs.settings(prefs)
        hwSetting = settings.hardwareTelex
        if (hwSetting && hardKeyboardPresent()) configureField(attribute, settings)
    }

    override fun onFinishInput() {
        if (hwTyped) session.finishInput()     // bàn phím ảo không hiện ⇒ onFinishInputView không lưu model
        fieldReady = false
        hwTyped = false
        hwConsumed.clear()
        super.onFinishInput()
    }

    private fun hardKeyboardPresent(): Boolean {
        val c = resources.configuration
        return c.keyboard != android.content.res.Configuration.KEYBOARD_NOKEYS &&
            c.hardKeyboardHidden != android.content.res.Configuration.HARDKEYBOARDHIDDEN_YES
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        onHardwareKeyDown(keyCode, event) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode >= 0 && hwConsumed.get(keyCode)) { hwConsumed.clear(keyCode); return true }
        return super.onKeyUp(keyCode, event)
    }

    /**
     * Phím cứng → cùng đường với phím chạm ([onKey]: batch IcProxy, confirmTail, tracker,
     * WriteMode). Chữ hoa/thường CHỈ theo Shift/CapsLock thật của KeyEvent — không đọc shift
     * của bàn phím ảo, không auto-shift (Funput #462: shift một lần phải nhả ngay).
     */
    private fun onHardwareKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (!hwSetting || currentInputConnection == null) return false
        if (!fieldReady) configureField(currentInputEditorInfo ?: return false, VTPrefs.settings(prefs))
        if (!hwSetting || field.isSecure || field.passthrough || field.rawKeys) return false
        val meta = event.metaState
        val k = HardwareKeys.classify(keyCode, meta, event.getUnicodeChar(meta))
        when (k) {
            HwKey.Pass -> {
                // Ctrl+C, mũi tên, Tab, Esc…: app tự xử lý; từ đang soạn coi như xong.
                if (session.bridge.isComposing) session.externalSelectionChange()
                return false
            }
            HwKey.Enter -> {
                // Chốt từ (auto-restore) rồi để Enter thật tới app: Shift+Enter, "Enter để gửi",
                // IME action của TextView đều giữ nguyên hành vi bàn phím cứng.
                clearSwipeUndo()
                if (proxy.begin()) try { session.commitComposing(proxy) } finally { proxy.end() }
                resetIfEditFailed()
                return false
            }
            else -> {}
        }
        val key = HardwareKeys.sessionKey(k, session.bridge.isComposing) ?: return false
        hwTyped = true
        hwConsumed.set(keyCode)
        onKey(key)
        // Bàn phím ảo đang hiện song song: shift một-lần của nó nhả NGAY khi gõ chữ cứng.
        if (key is Key.Letter) keyboard?.setAutoShift(false)
        return true
    }

    // MARK: phím

    override fun onKey(key: Key) {
        if (key == Key.Backspace && toolUndo != null) { undoTextTool(); return }   // ⌫ ngay sau = hoàn tác
        clearSwipeUndo()
        if (!proxy.begin()) return
        val out = try { session.handle(key, proxy) } finally { proxy.end() }
        if (key is Key.MoveCursor) {
            if (key.vertical) proxy.moveCursorVertical(key.delta) else proxy.moveCursor(key.delta)
        }
        resetIfEditFailed()
        if (key is Key.Letter) strip?.hidePasteCard()
        pendingGen = out.generation
        if (out.needsAutoShift) { handler.removeCallbacks(autoShiftRun); handler.post(autoShiftRun) }
        handler.removeCallbacks(suggestRun)
        handler.postDelayed(suggestRun, SUGGEST_DELAY_MS)
    }

    override fun onDeleteWord() {
        clearSwipeUndo()
        if (!proxy.begin()) return
        try { session.deleteWordBackward(proxy) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    // MARK: gõ vuốt

    /** Bật khi: setting + ô hợp lệ + KHÔNG TalkBack/touch exploration. Tắt ⇒ bỏ decoder (template GC được). */
    private fun updateSwipeTyping() {
        val on = swipeSetting && swipeFieldOk && accessibility?.isTouchExplorationEnabled != true
        if (!on) {
            keyboard?.swipeTyping = false
            if (::session.isInitialized) session.setSwipeTyping(false)
            synchronized(swipeLock) { swipeDecoder = null }
            return
        }
        if (swipeDecoder == null) synchronized(swipeLock) { swipeDecoder = SwipeDecoder() }
        session.setSwipeTyping(true)
        keyboard?.swipeTyping = true      // → onSwipeLayout khi plane chữ đã dựng
    }

    override fun onSwipeLayout(layout: SwipeLayout) {
        val dec = swipeDecoder ?: return
        synchronized(swipeLock) { dec.setLayout(layout) }
        // Dựng template nền (~320 KB) — một luồng nhờ swipeLock; decode chờ nếu chưa xong.
        worker().post {
            synchronized(swipeLock) { if (swipeDecoder === dec) dec.prepare() }
            if (session.swipeEnglish) SwipeEnglish.lexicon     // nạp từ điển Anh ở nền (lazy, thread-safe)
            SyllableBigram.shared   // bảng bigram tĩnh dùng chung (thanh gợi ý cũng dùng)
        }
    }

    override fun onSwipeTypingStart(): Boolean {
        if (!session.swipeTypingActive) return false
        clearSwipeUndo()
        if (!proxy.begin()) return false
        val ok = try { session.undoLastLetter(proxy) } finally { proxy.end() }
        resetIfEditFailed()
        if (ok) { handler.removeCallbacks(suggestRun); handler.removeCallbacks(autoShiftRun) }
        return ok
    }

    override fun onSwipeTypingEnd(path: SwipePath, case: SwipeSuggest.Case) {
        val dec = swipeDecoder ?: return
        val ctx = session.swipeContext()
        val t0 = if (TouchLog.enabled) System.nanoTime() else 0L
        // ctx.english != null ⇒ thêm ứng viên tiếng Anh (công tắc "Vuốt từ tiếng Anh"); điểm
        // cá nhân của từ tiếng Anh = ctx.englishWord (không có bigram tĩnh — chỉ cho âm tiết Việt).
        val cands = synchronized(swipeLock) {
            dec.decode(path, SwipeSuggest.TOP_K, ctx.folded, ctx.english, if (ctx.english != null) ctx.englishWord else null)
        }
        val choice = SwipeSuggest.choose(cands, ctx.word, case)
        if (TouchLog.enabled) TouchLog.write(String.format(java.util.Locale.ROOT, "swipe decode %.1fms pts=%d cands=%d",
            (System.nanoTime() - t0) / 1e6, path.count, cands.size))
        if (choice == null || !proxy.begin()) { applyAutoShift(); refreshBar(); return }
        val out = try { session.commitSwipe(choice, proxy) } finally { proxy.end() }
        resetIfEditFailed()
        strip?.hidePasteCard()
        pendingGen = out.generation
        applyAutoShift()
        refreshBar()
    }

    override fun onSwipeTypingCancel() {
        applyAutoShift()
        refreshBar()
    }

    // MARK: vuốt ⌫ xoá theo từ

    override fun onSwipeDeleteStart(): Boolean {
        clearSwipeUndo()
        if (!swipe.start()) return false
        // Từ đang soạn là "từ thứ nhất" trên màn hình (ranh giới tính từ chữ thật): quên nó trong engine.
        handler.removeCallbacks(suggestRun)
        session.externalSelectionChange()
        return true
    }

    override fun onSwipeDeleteUpdate(words: Int): Int {
        val n = swipe.update(words)
        if (!swipe.selecting) strip?.showSwipePreview(swipe.preview)
        return n
    }

    override fun onSwipeDeleteEnd(commit: Boolean) {
        strip?.showSwipePreview(null)
        val deleted = if (proxy.begin()) try { swipe.finish(commit) } finally { proxy.end() } else { swipe.finish(false); null }
        resetIfEditFailed()
        swipeUndo = deleted
        strip?.showRestore(deleted != null)
        applyAutoShift()
        refreshBar()
    }

    override fun onRestoreDeleted() {
        if (toolUndo != null) { undoTextTool(); return }
        val text = swipeUndo ?: return
        clearSwipeUndo()
        if (!proxy.begin()) return
        try { session.externalSelectionChange(); proxy.insertText(text) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    private fun clearSwipeUndo() {
        if (swipeUndo == null && toolUndo == null) return
        swipeUndo = null
        toolUndo = null
        strip?.showRestore(false)
    }

    // MARK: công cụ văn bản (Plus) — logic thuần ở keyboard/TextTools.kt

    /**
     * Áp [tool] lên vùng chọn (getSelectedText) hoặc đoạn trước con trỏ (tới xuống dòng).
     * Lối vào hiện tại: chip đầu lưới mẫu câu; bảng sửa văn bản gộp sau gọi thẳng hàm này.
     */
    override fun onTextTool(tool: TextTool) {
        if (!PlusGate.isUnlocked(PlusFeature.TEXT_TOOLS)) return
        clearSwipeUndo()
        handler.removeCallbacks(suggestRun)
        if (!proxy.begin()) return
        val out = try {
            session.commitComposing(proxy)          // từ đang soạn chốt trước (thuộc đoạn cần đổi)
            TextToolRunner.apply(tool, proxy, IcProxy.CONTEXT_CAP)
        } finally { proxy.end() }
        resetIfEditFailed()
        when (out) {
            is TextToolRunner.Outcome.Applied -> {
                toolUndo = out.undo
                strip?.showRestore(true, getString(com.viettelex.android.R.string.ime_undo))
            }
            TextToolRunner.Outcome.FailSafe -> TouchLog.write("failsafe: text tool ${tool.id} tail mismatch → skip")
            else -> {}
        }
        applyAutoShift()
        refreshBar()
    }

    private fun undoTextTool() {
        val u = toolUndo ?: return
        clearSwipeUndo()
        if (!proxy.begin()) return
        val ok = try { TextToolRunner.undo(u, proxy) } finally { proxy.end() }
        if (!ok) TouchLog.write("failsafe: text tool undo tail moved → skip")
        resetIfEditFailed()
        session.externalSelectionChange()
        applyAutoShift()
        refreshBar()
    }

    /** commitText/deleteSurroundingText trả false: màn hình không còn chắc khớp engine ⇒ quên từ. */
    private fun resetIfEditFailed() {
        if (proxy.takeFailure()) session.externalSelectionChange()
    }

    override fun onGlobe(longPress: Boolean) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (longPress) { imm.showInputMethodPicker(); return }
        if (Build.VERSION.SDK_INT >= 28) switchToNextInputMethod(false)
        else {
            val token = window?.window?.attributes?.token ?: return
            @Suppress("DEPRECATION") imm.switchToNextInputMethod(token, false)
        }
    }

    /** Không có phím 🌐 trên bàn phím (user chốt 26/09): đổi bàn phím bằng nút của thanh điều hướng hệ thống. */
    private fun needsGlobe(): Boolean = false

    /**
     * API 36: hệ thống báo khi thanh điều hướng KHÔNG vẽ nút đổi bàn phím → hiện gợi ý 🌐 nhỏ
     * trên phím 😊 (giữ lâu = chọn bàn phím). Có nút hệ thống thì ẩn gợi ý. Dưới API 36 thanh
     * điều hướng luôn có nút khi máy có ≥2 bàn phím → không hiện gợi ý.
     */
    override fun onCustomImeSwitcherButtonRequestedVisible(visible: Boolean) {
        switcherHintVisible = visible
        keyboard?.setSwitcherHint(visible)
    }
    private var switcherHintVisible = false

    override fun onDismissKeyboard() = requestHideSelf(0)

    override fun onPlaneChanged(plane: Plane) {
        strip?.setPlane(plane)
    }

    override fun emojiRecents(): List<String> = EmojiRecents.decode(prefs.getString(Keys.EMOJI_RECENTS, null))

    override fun noteEmojiUsed(e: String) {
        val next = EmojiRecents.noteUsed(emojiRecents(), e)
        prefs.edit().putString(Keys.EMOJI_RECENTS, EmojiRecents.encode(next)).apply()
    }

    // MARK: mẫu câu

    override fun onTemplate(item: TemplateItem) {
        val text = item.text
        if (!Templates.isDynamic(text)) { insertTemplate(text); return }
        // Mẫu động: fetch lúc chạm (timeout 4 s), lỗi ⇒ chèn chính URL.
        val w = worker()
        w.post {
            val bytes = try {
                val c = URL(text).openConnection() as HttpURLConnection
                c.connectTimeout = Templates.FETCH_TIMEOUT_MS
                c.readTimeout = Templates.FETCH_TIMEOUT_MS
                try {
                    c.inputStream.use { ins ->
                        val buf = ByteArray(Templates.FETCH_MAX_BYTES)
                        var n = 0
                        while (n < buf.size) { val r = ins.read(buf, n, buf.size - n); if (r < 0) break; n += r }
                        buf.copyOf(n)
                    }
                } finally { c.disconnect() }
            } catch (_: Exception) { null }
            handler.post { insertTemplate(Templates.bodyFromResponse(bytes) ?: text) }
        }
    }

    private fun insertTemplate(text: String) {
        if (!proxy.begin()) return
        try { session.insertTemplate(text, proxy) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    override fun onOpenTemplates() {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("viettelex://maucau"))
                .setPackage(packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        } catch (e: Exception) {
            Log.w(TAG, "open templates: $e")
        }
    }

    // MARK: strip

    override fun onSuggestion(item: String) {
        clearSwipeUndo()
        if (!proxy.begin()) return
        try { session.acceptSuggestion(item, proxy) } finally { proxy.end() }
        resetIfEditFailed()
        applyAutoShift()
        refreshBar()
    }

    override fun onToggleTemplates() { keyboard?.toggleTemplates() }

    override fun onBarToggled(collapsed: Boolean) {
        this.collapsed = collapsed
        prefs.edit().putBoolean(Keys.SUGGESTION_BAR_COLLAPSED, collapsed).apply()
        session.barCollapsed = collapsed
        if (!collapsed) refreshBar()
    }

    override fun onStripHeightChanged() { root?.requestLayout() }

    // MARK: auto-shift + gợi ý

    private fun applyAutoShift() {
        val on = session.updateAutoShift(proxy) ?: return
        keyboard?.setAutoShift(on)
    }

    private fun refreshBar() {
        val st = strip ?: return
        if (!session.suggestionsActive || session.barCollapsed) return
        when (val plan = session.requestSuggestions(proxy)) {
            is SuggestionPlan.Ready -> st.show(plan.set)
            is SuggestionPlan.Background -> {
                val job = plan.job
                worker().post {
                    val r = job.compute()
                    handler.post { session.completeSuggestions(job, r)?.let { strip?.show(it) } }
                }
            }
        }
    }

    private fun worker(): Handler = worker ?: run {
        val t = HandlerThread("vt-suggest", Process.THREAD_PRIORITY_DEFAULT).also { it.start() }
        workerThread = t
        Handler(t.looper).also { worker = it }
    }

    private fun logMemory() {
        val rt = Runtime.getRuntime()
        val heap = (rt.totalMemory() - rt.freeMemory()) / 1_048_576.0
        val pss = android.os.Debug.getPss() / 1024.0
        Log.d(TAG, String.format("mem: heap %.1f MB, pss %.1f MB", heap, pss))
    }

    companion object {
        private const val TAG = "VTKB"
        const val SUGGEST_DELAY_MS = 30L
    }
}
