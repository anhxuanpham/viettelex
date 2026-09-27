package com.viettelex.keyboard


/** Phím gửi vào [KeyboardSession.handle] (≈ KeyboardView.Key iOS). */
sealed class Key {
    /** Phím chữ, đã theo shift. */
    data class Letter(val ch: Char) : Key()
    /** Số / ký hiệu / dấu câu (boundary + ngắt câu). */
    data class Text(val text: String) : Key()
    object Space : Key()
    /** Space thứ 2 trong < 0.35 s (IME đo nhịp). */
    object DoubleSpacePeriod : Key()
    object Newline : Key()
    /**
     * Giữ lâu Enter: chèn "\n" THẬT (commitText) — không performEditorAction, không
     * KEYCODE_ENTER (Zalo/Messenger bắt phím Enter thành "Gửi"). Chốt/học từ như [Newline].
     */
    object LineBreak : Key()
    object Backspace : Key()
    /** Trackpad: session reset; IME tự dời con trỏ [delta] ký tự, hoặc [delta] dòng
     *  khi [vertical] (âm = trái/lên). */
    data class MoveCursor(val delta: Int, val vertical: Boolean = false) : Key()
    /** 🗑 plane mẫu câu: xoá sạch ô (qua [TextProxy.clearAll]). */
    object ClearField : Key()
}

/** Đặc tính ô nhập (từ EditorInfo). */
data class FieldTraits(
    val isSecure: Boolean = false,
    /** Gõ literal, bỏ Telex (spec §12: URI/EMAIL/VISIBLE_PASSWORD/FILTER). */
    val passthrough: Boolean = false,
    /** TYPE_TEXT_FLAG_CAP_SENTENCES — auto-shift đầu câu. */
    val capSentences: Boolean = false,
    /** Ô cho phép thanh gợi ý (không secure, không passthrough, …). */
    val suggestionsAllowed: Boolean = true,
    /** TYPE_TEXT_FLAG_CAP_WORDS — auto-shift đầu mỗi từ (ô tên người, tiêu đề…). */
    val capWords: Boolean = false,
    /** TYPE_TEXT_FLAG_CAP_CHARACTERS — luôn viết hoa (mã, biển số…). */
    val capCharacters: Boolean = false,
    /**
     * EditorInfo.initialCapsMode ≠ 0 — editor tự tính lúc mở ô. Chỉ dùng khi KHÔNG đọc
     * được chữ trước con trỏ (getTextBeforeCursor = null) và chưa gõ phím nào.
     */
    val initialCaps: Boolean = false,
    /**
     * IME_FLAG_NO_PERSONALIZED_LEARNING (Chrome ẩn danh, app nhạy cảm): KHÔNG ghi từ vào
     * UserLangModel. Gợi ý vẫn hiện (chỉ đọc).
     */
    val noLearning: Boolean = false,
    /** EditorInfo.packageName — tra bảng [WriteMode]. */
    val packageName: String? = null,
    /** Ô URL (TYPE_TEXT_VARIATION_URI — omnibox tự hoàn tất): không gõ tắt. */
    val urlField: Boolean = false,
) {
    /** Cách ghi chữ vào ô theo app (bảng [WriteMode.forPackage]). */
    val writeMode: WriteMode get() = WriteMode.forPackage(packageName)
}

/**
 * Cách lớp ghi (IcProxy) đẩy chữ vào ô — vài editor văn phòng xử lý sai
 * commitText/deleteSurroundingText.
 *
 * IcProxy.writeMode áp bảng này (VietTelexIME.onStartInputView):
 *  - [COMMIT]: commitText + deleteSurroundingTextInCodePoints.
 *  - [DEL_VIA_KEY_EVENT]: commitText nhưng xoá bằng KEYCODE_DEL (ONLYOFFICE bỏ qua deleteSurroundingText).
 *  - [KEY_ONLY]: mọi thứ qua key event (WPS bản Xiaomi/Huawei, HSL).
 */
enum class WriteMode {
    COMMIT, DEL_VIA_KEY_EVENT, KEY_ONLY;

    companion object {
        private val KEY_ONLY_PKGS = listOf("com.huawei.hsl", "cn.wps.huawei")

        fun forPackage(pkg: String?): WriteMode {
            if (pkg.isNullOrEmpty()) return COMMIT
            fun under(base: String) = pkg == base || pkg.startsWith("$base.")
            return when {
                pkg.startsWith("com.xiaomi.wps") || KEY_ONLY_PKGS.any(::under) -> KEY_ONLY
                pkg.startsWith("com.onlyoffice.") -> DEL_VIA_KEY_EVENT
                else -> COMMIT
            }
        }
    }
}

/** Kiểu viết hoa tự động của ô (TYPE_TEXT_FLAG_CAP_*). */
enum class CapMode { NONE, SENTENCES, WORDS, CHARACTERS }

/** Kết quả một phím: IME dùng [generation] để coalesce auto-shift + gợi ý 30 ms. */
data class KeyOutcome(val needsAutoShift: Boolean, val generation: Int)

/** Nội dung thanh gợi ý (≈ KeyboardView.SuggestionSet). */
data class SuggestionSet(
    val literal: String? = null,
    val word: String? = null,
    /** Ứng viên inline thứ hai (khi không có emoji). */
    val word2: String? = null,
    val emojis: List<String> = emptyList(),
    /** Gợi ý khi CHƯA gõ (đầu câu / sau space / email / TLD). */
    val nextWords: List<String> = emptyList(),
    /** Thẻ Dán thay cả bar. */
    val paste: Boolean = false,
    val pasteIsImage: Boolean = false,
    /** Chip số (NumberChips) — luôn ở slot GIỮA; chạm gửi [NUMBER_TOKEN]. */
    val number: String? = null,
    /** Chip tách số (OTP/SĐT/STK) từ nội dung vừa copy — thay thẻ Dán. */
    val clipChips: List<ClipChip> = emptyList(),
    /** Chip hành động ở slot trái khi chưa gõ ("Thêm dấu" / "↩︎ Hoàn tác") — payload [action]. */
    val actionLabel: String? = null,
    val action: String? = null,
) {
    val isEmpty: Boolean get() = literal == null && word == null && word2 == null && emojis.isEmpty() &&
        nextWords.isEmpty() && number == null
    /** So để bỏ vẽ lại khi không đổi. */
    fun signature(): String = listOf(literal, word, word2, emojis.joinToString("\u0002"),
        nextWords.joinToString("\u0002"), paste.toString(), number,
        clipChips.joinToString("\u0002") { it.label + "\u0003" + it.value }, action, actionLabel).joinToString("\u0001")

    companion object {
        /** Payload chạm thẻ Dán → truyền vào acceptSuggestion. */
        const val PASTE_TOKEN = "paste"
        const val PASTE_IMAGE_TOKEN = "pasteImage"
        /** Payload chạm chip số (session giữ NumberChip: đuôi cần thay + chữ chèn). */
        const val NUMBER_TOKEN = "\uE000number"
        /** Payload chip tách số clipboard: tiền tố + giá trị cần dán (không space, không học). */
        const val CLIP_CHIP_PREFIX = "\uE000clip:"
        /** Chip "Thêm dấu" / "Hoàn tác" (ký tự Private Use — không thể là từ thật). */
        const val ADD_TONES_TOKEN = "\uE000addTones"
        const val UNDO_TONES_TOKEN = "\uE000undoTones"
        /** Chip "↩︎ từ cũ": hoàn tác lần vuốt vừa sửa lại từ vuốt trước (SwipeRevise). */
        const val UNDO_REVISE_TOKEN = "\uE000undoRevise"
    }
}

sealed class SuggestionPlan {
    /** Vẽ ngay; [set] null = không vẽ gì (bar tắt / thu gọn). */
    data class Ready(val set: SuggestionSet?) : SuggestionPlan()
    /** Chạy [SuggestJob.compute] ở thread nền, rồi [KeyboardSession.completeSuggestions] trên main. */
    class Background(val job: SuggestJob) : SuggestionPlan()
}

/** Phần nặng của gợi ý khi đang gõ dở (VNSuggest + AdjacentKeyFixer) — thread-safe. */
class SuggestJob internal constructor(
    internal val req: Int, internal val gen: Int, internal val bridge: EngineBridge,
    val composed: String, val raw: String, internal val predicted: String, private val wantFix: Boolean,
    /** Âm tiết liền trước (bigram tĩnh). */
    private val prev: String? = null,
    internal val number: String? = null,
) {
    class Result(val pool: List<VNSuggest.Match>, val fix: String?, val pmi: FloatArray? = null)
    fun compute(): Result {
        val pool = VNSuggest.matches(composed, poolLimit = 24, excluding = composed.lowercase())
        val fix = if (pool.isEmpty() && wantFix) AdjacentKeyFixer.lexiconCorrection(raw, bridge) else null
        return Result(pool, fix, SuggestRank.inlinePmi(pool, prev))
    }
}

/**
 * "Bộ não" controller — port 1:1 phần logic của KeyboardViewController.swift (không UI):
 * engine bridge, học từ, gợi ý 6 tầng, backspace-undo auto-restore, nút Dán, xoá theo
 * từ, mẫu câu. Mọi hàm gọi trên MAIN thread, trừ [SuggestJob.compute].
 */
class KeyboardSession(
    val langModel: UserLangModel,
    private val clipboard: ClipboardSource? = null,
    /** Đồng hồ ms (nút Dán: 180 s / cache 2 s). */
    private val clock: () -> Long = System::currentTimeMillis,
) {
    var bridge = EngineBridge(); private set
    private var lastWord: String? = null
    private var lastWord2: String? = null
    private var learnEnabled = true
    /** Ẩn danh (thủ công HOẶC IME_FLAG_NO_PERSONALIZED_LEARNING): không học, không lưu clipboard. */
    var incognito = false; private set
    /** Lịch sử clipboard — null khi tắt (IME set theo setting, lo đọc/ghi file). */
    var clipHistory: ClipboardHistory? = null
    private var filterSensitive = true
    private var traits = FieldTraits()
    private var lastResetAt: Long? = null
    /** Chưa gõ phím nào từ startInput — [FieldTraits.initialCaps] còn hiệu lực. */
    private var initialCapsPending = true

    /** Tăng mỗi phím — IME so với KeyOutcome.generation để bỏ lượt cũ. */
    var generation = 0; private set
    private var suggestReq = 0
    private var lastInsertWasSpace = false
    /** Auto-shift đang bật (gợi ý viết hoa chữ đầu). */
    var autoShiftOn = false; private set
    /** Bar tắt ở setting hoặc ô cấm. */
    var suggestionsActive = true; private set
    /** Bar thu gọn — pipeline gợi ý ngừng. IME set theo chevron. */
    var barCollapsed = false
    private var lastKeyWasEmailTrigger = false
    /** Số dấu cách kể từ chữ số/phép tính cuối (≤1 → đáng đọc context tìm chip số). */
    private var numberSpaces = 99
    /** Chip số đang hiện — payload [SuggestionSet.NUMBER_TOKEN]. */
    private var numberChip: NumberChip? = null
    private var restoreUndoRaw: String? = null
    private var restoreUndoComposed: String? = null
    private var undoOfferActive = false
    private var ctxCacheKey: String? = null
    /** Từ chốt gần nhất + biên nhận học — ⌫ mở lại từ đó thì rút lại lượt học (không học trùng). */
    private class LastCommit(val word: String, val prev1: String?, val prev2: String?, val learned: UserLangModel.Learned?)
    private var lastCommit: LastCommit? = null
    private var ctxCache: Set<String> = emptySet()
    /** Thêm dấu vừa áp (chip "Hoàn tác" / ⌫ ngay sau) — sống tới phím kế. */
    private var tonesUndo: AddTones.Plan? = null
    /** Đoạn vừa hoàn tác — không mời lại đúng đoạn đó. */
    private var tonesDismissed: String? = null
    private var tonesCacheBefore: String? = null
    private var tonesCachePlan: AddTones.Plan? = null
    /** Công tắc chip "Thêm dấu" tự hiện ([KeyboardSettings.addTonesChip]) — tắt ⇒ 0 việc mỗi dấu cách. */
    private var addTonesChip = false
    /** Công tắc chip số ([KeyboardSettings.numberChips]) — tắt ⇒ không đọc context sau chữ số. */
    private var numberChipsOn = true

    /** Gõ vuốt bật cho ô hiện tại (IME quyết: setting + loại ô + TalkBack). */
    var swipeTypingActive = false
        private set
    /** Từ vừa vuốt, còn là composition đang mở (null khi phím/thao tác khác xen vào). */
    private var swipeWord: String? = null
    private var swipeAlts: List<String> = emptyList()
    /** Từ vuốt đang mở là tiếng Anh chèn NGUYÊN VĂN (engine trống — không seed Telex). */
    private var swipeLiteral = false
    /** Phương án tiếng Anh trong [swipeAlts] (chèn nguyên văn khi chọn). */
    private var swipeEnglishAlts: Set<String> = emptySet()
    /** Vuốt ra từ tiếng Anh (công tắc con, [KeyboardSettings.swipeEnglish]). */
    var swipeEnglish = true
    /**
     * Từ vuốt Việt vừa chèn + ứng viên đã chấm — cú vuốt NGAY SAU được sửa lại nó theo ngữ
     * cảnh hai phía (SwipeRevise). Chỉ sống qua đúng một phím chữ bị huỷ thành đầu cú vuốt kế.
     */
    private class Revisable(val word: String, val scored: List<SwipeWord>, val case: SwipeSuggest.Case)
    private var revisable: Revisable? = null
    private var revisableAfterLetter: Revisable? = null
    /** Vừa sửa lại từ trước: (từ cũ, từ mới) — chip "↩︎ từ cũ", sống khi từ vuốt kế còn mở. */
    private var reviseUndo: Pair<String, String>? = null
    /** Vài từ tiếng Anh vừa vuốt ra (chữ thường) — ngữ cảnh ngôn ngữ cho cú vuốt kế. */
    private val recentEnglish = ArrayDeque<String>()

    init {
        langModel.isKnownWord = { VNSuggest.contains(it) }
        langModel.seedIfEmpty(SeedData::load)
    }

    // MARK: vòng đời

    /** onStartInputView: settings mới, bridge mới, reset trạng thái (viewWillAppear). */
    fun startInput(settings: KeyboardSettings, field: FieldTraits) {
        if (lastResetAt != null && lastResetAt != settings.userlmResetAt) langModel.reloadAfterExternalErase()
        lastResetAt = settings.userlmResetAt
        TouchLog.session("android")
        bridge = EngineBridge(settings)
        bridge.passthrough = field.passthrough
        bridge.shortcutsAllowed = !field.urlField
        traits = field
        lastKeyWasEmailTrigger = false
        clearUndo()
        incognito = settings.incognito || field.noLearning
        learnEnabled = settings.learnWords && !incognito
        initialCapsPending = true
        filterSensitive = settings.filterSensitive
        swipeEnglish = settings.swipeEnglish
        recentEnglish.clear()
        suggestionsActive = settings.showSuggestions && field.suggestionsAllowed && !field.isSecure && !field.passthrough
        lastWord = null; lastWord2 = null
        lastInsertWasSpace = false
        lastCommit = null
        clearSwipe()
        setSwipeTyping(false)
        tonesUndo = null; tonesDismissed = null; tonesCacheBefore = null; tonesCachePlan = null
        addTonesChip = settings.addTonesChip
        numberChipsOn = settings.numberChips
    }

    /** IME bật/tắt gõ vuốt cho ô hiện tại (sau [startInput]). Tắt ⇒ bridge thôi ghi checkpoint. */
    fun setSwipeTyping(on: Boolean) {
        swipeTypingActive = on
        bridge.trackLetterUndo = on
        if (!on) clearSwipe()
    }

    private fun clearSwipe() {
        swipeWord = null; swipeAlts = emptyList(); swipeLiteral = false; swipeEnglishAlts = emptySet()
        revisable = null; reviseUndo = null
    }

    /** Từ vuốt còn mở: từ engine đang soạn, hoặc từ tiếng Anh nguyên văn. */
    private fun openSwipeWord(): String? = swipeWord?.takeIf { swipeLiteral || it == bridge.composedWord }

    /** Chốt từ tiếng Anh nguyên văn đang mở (học + ngữ cảnh), trước khi phím kế chèn gì. */
    private fun settleLiteral(word: String) {
        commitAndLearn(word)
        bridge.noteExternalWord(true)
        recentEnglish.addLast(word.lowercase())
        while (recentEnglish.size > 4) recentEnglish.removeFirst()
    }

    /** onFinishInputView (viewWillDisappear). */
    fun finishInput() { langModel.saveNow() }

    /** Con trỏ/selection đổi từ NGOÀI (textWillChange): quên từ + ngữ cảnh. */
    fun externalSelectionChange() {
        TouchLog.host("selectionChanged", false, bridge.isComposing)
        bridge.reset(); lastWord = null; lastWord2 = null
        clearUndo()
        lastCommit = null
        clearSwipe()
        tonesUndo = null
    }

    /**
     * Bàn phím cứng: phím sắp đi THẲNG tới app (Enter thật — Shift+Enter, "Enter để gửi"):
     * chốt từ đang soạn (auto-restore + học) mà KHÔNG chèn gì; như [Key.Newline], ⌫ sau đó
     * không mở lại từ cũ.
     */
    fun commitComposing(proxy: TextProxy) {
        val literal = if (swipeLiteral) openSwipeWord() else null
        clearSwipe()
        if (literal != null) settleLiteral(literal)
        else if (bridge.isComposing) commitAndLearn(bridge.boundary("", proxy))
        bridge.forgetLastCommit()
        lastWord = null; lastWord2 = null; clearUndo()
        lastInsertWasSpace = false
        generation++
    }

    private fun clearUndo() { restoreUndoRaw = null; restoreUndoComposed = null; undoOfferActive = false }

    /**
     * Auto-shift theo cờ CAP_* của ô: trả true/false; null = không đụng shift (ô không cờ
     * CAP, hoặc KHÔNG đọc được chữ trước con trỏ — null ≠ ô trống, trước đây coi null là ""
     * nên bật shift sai giữa câu). Chỉ nâng OFF→ON là việc của IME (không hạ CAPS).
     */
    fun updateAutoShift(proxy: TextProxy): Boolean? {
        val mode = capMode(traits)
        if (mode == CapMode.NONE) return null
        val before = proxy.contextBeforeInput()
        val auto = when {
            before != null -> autoShiftFor(before, mode)
            mode == CapMode.CHARACTERS -> true
            initialCapsPending -> traits.initialCaps
            else -> return null
        }
        autoShiftOn = auto
        return auto
    }

    // MARK: phím

    fun handle(key: Key, proxy: TextProxy): KeyOutcome {
        val t0 = if (TouchLog.enabled) System.nanoTime() else 0L
        // ⌫ NGAY SAU khi thêm dấu = hoàn tác (một lần); phím khác bỏ lời mời hoàn tác.
        if (key == Key.Backspace && tonesUndo != null && !bridge.isComposing && openSwipeWord() == null) {
            undoAddTones(proxy)
            generation++
            return KeyOutcome(true, generation)
        }
        tonesUndo = null
        val swiped = openSwipeWord()
        val literal = if (swipeLiteral) swiped else null
        revisableAfterLetter = revisable?.takeIf { key is Key.Letter && it.word == swiped }
        clearSwipe()
        // Từ tiếng Anh vuốt ra đang mở: phím chữ/ranh giới chốt nó (học), phím chữ thêm dấu
        // cách treo trước (không dính "mailx"; huỷ được nếu phím đó là đầu cú vuốt mới).
        if (literal != null && (key is Key.Letter || key is Key.Text || key == Key.Space ||
                key == Key.DoubleSpacePeriod || key == Key.Newline || key == Key.LineBreak)) {
            settleLiteral(literal)
            if (key is Key.Letter) bridge.boundary(" ", proxy, expand = false)
        }
        // Từ vuốt không bao giờ là chữ tắt.
        val expand = swiped == null
        when (key) {
            is Key.Letter -> { bridge.letter(key.ch, proxy); clearUndo() }
            is Key.Text -> {
                // VNI: số trong lúc soạn từ (hàng số / plane 123 / phím cứng) mang dấu — phím
                // của từ. Sau từ tiếng Anh vuốt nguyên văn thì số chỉ là số.
                val d = key.text.singleOrNull()
                if (literal == null && d != null && bridge.vniDigit(d, proxy)) {
                    clearUndo()
                } else {
                    commitAndLearn(bridge.boundary(key.text, proxy, expand = expand))
                    lastWord = null; lastWord2 = null
                    clearUndo()
                }
            }
            Key.Space -> {
                val composedBefore = bridge.composedWord
                val committed = bridge.boundary(" ", proxy, expand = expand)
                // (Gõ tắt vừa bung thì không: ⌫ kế tiếp tự trả lại chữ tắt trong bridge.)
                if (composedBefore.isNotEmpty() && committed != composedBefore && !bridge.expandedAtLastBoundary) {
                    restoreUndoRaw = committed; restoreUndoComposed = composedBefore
                } else { restoreUndoRaw = null; restoreUndoComposed = null }
                undoOfferActive = false
                if (literal == null) commitAndLearn(committed)
            }
            Key.DoubleSpacePeriod -> {
                val ctx = proxy.contextBeforeInput() ?: ""
                if (TypingHeuristics.doubleSpaceMakesPeriod(ctx, lastInsertWasSpace)) {
                    // Xoá space bằng deleteSurroundingText (qua deleteCodePoints), KHÔNG
                    // deleteBackward: KEYCODE_DEL đi đường key event bất đồng bộ (ViewRootImpl
                    // post Message) nên có thể tới SAU commitText(". ") → "chữ ." thay vì "chữ. ".
                    proxy.deleteCodePoints(1)
                    proxy.insertText(". ")
                    lastWord = null; lastWord2 = null
                } else {
                    commitAndLearn(bridge.boundary(" ", proxy, expand = expand))
                }
                // Space đôi có thể đã thành ". ": ⌫ sau đó không được mở lại từ.
                bridge.forgetLastCommit()
                clearUndo()
            }
            is Key.MoveCursor -> {
                bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
            }
            Key.Newline, Key.LineBreak -> {
                commitAndLearn(bridge.boundary("\n", proxy, lineBreak = key == Key.LineBreak, expand = expand))
                // Enter có thể là "gửi"/performEditorAction: ⌫ sau đó không mở lại từ cũ.
                bridge.forgetLastCommit()
                lastWord = null; lastWord2 = null; clearUndo()
            }
            Key.ClearField -> {
                proxy.clearAll()
                bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
            }
            Key.Backspace -> if (swiped != null && proxy.confirmTail(swiped)) {
                // ⌫ ĐẦU TIÊN ngay sau vuốt: xoá cả từ vuốt (từ chưa chốt ⇒ ngữ cảnh giữ nguyên).
                proxy.deleteCodePoints(Cp.count(swiped))
                bridge.reset()
                clearUndo()
            } else {
                if (!bridge.isComposing && lastInsertWasSpace && restoreUndoRaw != null) undoOfferActive = true
                else clearUndo()
                if (bridge.backspace(proxy)) onReopened()
                else if (!bridge.isComposing) { lastWord = null; lastWord2 = null }
            }
        }
        // Chip số: chỉ đọc context khi token này / token ngay trước có chữ số/phép tính.
        numberSpaces = when (key) {
            is Key.Text -> if (key.text.firstOrNull()?.let { it.isDigit() || it in "=+-*/×÷:%().," } == true) 0 else 99
            Key.Space, Key.DoubleSpacePeriod -> numberSpaces + 1
            Key.Backspace -> 0
            is Key.Letter -> numberSpaces
            else -> 99
        }
        lastInsertWasSpace = key == Key.Space || key == Key.DoubleSpacePeriod
        lastKeyWasEmailTrigger = key is Key.Text && (key.text == "@" || key.text == ".")
        initialCapsPending = false
        val needsAutoShift = when (key) {
            Key.Space, Key.Newline, Key.LineBreak, Key.DoubleSpacePeriod, Key.Backspace, is Key.MoveCursor, Key.ClearField -> true
            // CAP_CHARACTERS: shift ON bị bàn phím hạ sau mỗi chữ → bật lại.
            else -> traits.capCharacters
        }
        if (TouchLog.enabled) {
            val (kind, ch) = when (key) {
                is Key.Letter -> "letter" to key.ch.toString()
                is Key.Text -> "text" to key.text
                Key.Space -> "space" to null
                Key.DoubleSpacePeriod -> "doubleSpace" to null
                Key.Backspace -> "backspace" to null
                Key.Newline -> "newline" to null
                Key.LineBreak -> "linebreak" to null
                is Key.MoveCursor -> "cursor" to null
                Key.ClearField -> "clear" to null
            }
            TouchLog.key(kind, bridge.isComposing, (System.nanoTime() - t0) / 1e6, ch)
        }
        generation++
        return KeyOutcome(needsAutoShift, generation)
    }

    // MARK: gõ vuốt

    /**
     * Ngón vừa chuyển từ chạm sang VUỐT: huỷ phím chữ đã chèn lúc chạm xuống (checkpoint
     * engine, không ⌫). false ⇒ không huỷ được (ô đổi / thao tác khác xen) — IME coi là chạm.
     */
    fun undoLastLetter(proxy: TextProxy): Boolean {
        val ok = bridge.undoLastLetter(proxy)
        revisable = if (ok) revisableAfterLetter else null
        revisableAfterLetter = null
        generation++
        return ok
    }

    /** Từ chọn cho một cú vuốt; [revisedPrev] = từ vuốt trước cần thay (đã theo chữ hoa của nó). */
    class SwipeResolved(val choice: SwipeChoice, val scored: List<SwipeWord>, val case: SwipeSuggest.Case,
                        val revisedPrev: String? = null)

    /**
     * Ứng viên decoder → từ chèn. Cú vuốt ngay sau một từ vuốt Việt còn nguyên (chưa sửa, chưa
     * chọn phương án): chấm lại từ đó theo ngữ cảnh hai phía; đổi thì chọn lại từ này theo ngữ
     * cảnh trái mới. Chỉ vài lần bung dấu + tra LM — sau nhấc tay, không ở đường phím.
     */
    fun resolveSwipe(cands: List<SwipeCandidate>, ctx: SwipeSuggest.Context,
                     case: SwipeSuggest.Case = SwipeSuggest.Case.LOWER): SwipeResolved? {
        val choice = SwipeSuggest.choose(cands, ctx.word, case, ctx.lambdaFreq) ?: return null
        val scored = if (choice.english) emptyList() else SwipeRevise.scored(cands, ctx.word, ctx.lambdaFreq)
        val rec = revisable
        if (rec == null || choice.english || swipeLiteral || !bridge.isComposing || bridge.composedWord != rec.word)
            return SwipeResolved(choice, scored, case)
        val new = SwipeRevise.revise(rec.scored, rec.word.lowercase(), lastWord, choice.word.lowercase())
            ?: return SwipeResolved(choice, scored, case)
        val nctx = SwipeSuggest.context(langModel, new, lastWord, ctx.english)
        val re = SwipeRevise.rerank(cands, ctx.word, ctx.lambdaFreq, nctx.word, nctx.lambdaFreq)
        val c = SwipeSuggest.choose(re, nctx.word, case, nctx.lambdaFreq) ?: choice
        return SwipeResolved(c, if (c.english) emptyList() else SwipeRevise.scored(re, nctx.word, nctx.lambdaFreq),
            case, SwipeSuggest.applyCase(new, rec.case))
    }

    fun commitSwipe(r: SwipeResolved, proxy: TextProxy): KeyOutcome =
        commitSwipe(r.choice, proxy, r.revisedPrev, r.scored, r.case)

    /** Điểm ngữ cảnh cho decoder: từ trước = từ đang soạn (sẽ được chốt) hoặc từ chốt gần nhất. */
    fun swipeContext(): SwipeSuggest.Context {
        val lit = if (swipeLiteral) swipeWord else null
        val composing = bridge.isComposing || lit != null
        val pending = when {
            lit != null -> lit
            bridge.isComposing -> bridge.predictedCommit.takeIf { UserLangModel.learnable(it) }
            else -> null
        }
        val p1 = if (composing) pending else lastWord
        val p2 = if (composing) (if (pending != null) lastWord else null) else lastWord2
        // Ngôn ngữ theo 2 từ trước: từ Anh vừa vuốt (nhãn) chắc nhất, rồi bảng từ của engine.
        val english = if (!swipeEnglish) null else SwipeLangContext.prior(
            SwipeLangContext.classify(p1, lit != null || isRecentEnglish(p1)),
            SwipeLangContext.classify(p2, isRecentEnglish(p2)))
        return SwipeSuggest.context(langModel, p1, p2, english)
    }

    private fun isRecentEnglish(w: String?) = w != null && w.lowercase() in recentEnglish

    /**
     * Nhấc tay khỏi đường vuốt: chốt từ đang soạn (nếu có, kèm dấu cách), dấu cách treo
     * nếu liền trước là chữ, chèn [choice] rồi seed engine bằng nó ⇒ composition đang mở
     * (phím dấu Telex sửa được, ⌫ đầu xoá cả từ, thanh gợi ý hiện biến thể).
     */
    fun commitSwipe(choice: SwipeChoice, proxy: TextProxy, revisedPrev: String? = null,
                    scored: List<SwipeWord> = emptyList(), case: SwipeSuggest.Case = SwipeSuggest.Case.LOWER): KeyOutcome {
        tonesUndo = null
        val lit = if (swipeLiteral) swipeWord else null
        val prevWord = revisable?.word
        clearUndo(); clearSwipe()
        var revised: Pair<String, String>? = null
        if (lit != null) {
            // từ tiếng Anh vuốt trước còn mở: chốt nó + dấu cách
            settleLiteral(lit)
            bridge.boundary(" ", proxy, expand = false)
        } else if (bridge.isComposing) {
            // Sửa lại từ vuốt trước (ngữ cảnh hai phía): chỉ khi đuôi màn hình đúng là nó.
            if (revisedPrev != null && prevWord != null && prevWord == bridge.composedWord &&
                proxy.confirmTail(prevWord)) {
                proxy.deleteCodePoints(Cp.count(prevWord))
                proxy.insertText(revisedPrev)
                revised = prevWord to revisedPrev
                if (!bridge.adoptWord(revisedPrev)) commitAndLearn(revisedPrev)
            }
            // dấu cách tự chèn trước từ vuốt: không phải ranh giới người dùng gõ → không gõ tắt
            if (bridge.isComposing) commitAndLearn(bridge.boundary(" ", proxy, expand = false))
            else bridge.boundary(" ", proxy, expand = false)
        } else if (SwipeSuggest.needsLeadingSpace(proxy.contextBeforeInput())) {
            bridge.boundary(" ", proxy, expand = false)
        }
        proxy.insertText(choice.word)
        if (choice.english) {
            // tiếng Anh: chèn nguyên văn, engine trống (không seed Telex, không bung dấu)
            bridge.adoptLiteral()
            swipeWord = choice.word
            swipeLiteral = true
            swipeAlts = choice.alternatives
            swipeEnglishAlts = choice.englishAlternatives
        } else if (bridge.adoptWord(choice.word)) {
            swipeWord = choice.word
            swipeAlts = choice.alternatives
            swipeEnglishAlts = choice.englishAlternatives
            if (scored.isNotEmpty()) revisable = Revisable(choice.word, scored, case)
            reviseUndo = revised
        }
        if (revised != null) TouchLog.write("swipe: sửa từ trước (${Cp.count(revised.first)}→${Cp.count(revised.second)} chars)")
        lastInsertWasSpace = false
        lastKeyWasEmailTrigger = false
        initialCapsPending = false
        TouchLog.write("swipe: ${Cp.count(choice.word)} chars, ${choice.alternatives.size} alts")
        generation++
        return KeyOutcome(true, generation)
    }

    /** Đang hiện biến thể của từ vừa vuốt (test / IME). */
    val swipeAlternatives: List<String>? get() = openSwipeWord()?.let { swipeAlts }

    /** Từ vuốt đang mở là tiếng Anh nguyên văn (test / IME). */
    val swipeWordIsEnglish: Boolean get() = swipeLiteral && swipeWord != null

    /** Giữ ⌫ > 3 s: xoá theo TỪ (khoảng trắng đuôi rồi tới đầu từ). */
    fun deleteWordBackward(proxy: TextProxy) {
        tonesUndo = null
        bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
        val before = proxy.contextBeforeInput() ?: ""
        if (before.isEmpty()) return
        var end = before.length
        var count = 0
        fun lastCp() = before.codePointBefore(end)
        while (end > 0 && (lastCp() == ' '.code || lastCp() == '\n'.code)) { end--; count++ }
        while (end > 0 && !(lastCp() == ' '.code || lastCp() == '\n'.code)) {
            end -= Character.charCount(lastCp()); count++
        }
        proxy.deleteCodePoints(maxOf(count, 1))
    }

    /**
     * Mẫu câu (sau khi IME đã fetch mẫu động): xoá từ đang soạn, chèn nguyên văn,
     * reset engine, KHÔNG học. IME gọi updateAutoShift + refresh bar sau đó.
     */
    fun insertTemplate(text: String, proxy: TextProxy) {
        tonesUndo = null
        val n = Cp.count(bridge.composedWord)
        if (n > 0 && proxy.confirmTail(bridge.composedWord)) proxy.deleteCodePoints(n)
        proxy.insertText(text)
        bridge.reset(); lastWord = null; lastWord2 = null; clearUndo()
    }

    /**
     * ⌫ vừa mở lại từ chốt trước: từ đó quay về trạng thái "đang gõ" — rút lượt học của nó
     * (chốt lại sẽ học đúng một lần, kể cả khi đã sửa dấu) và trả ngữ cảnh về trước nó.
     */
    private fun onReopened() {
        clearUndo()
        val lc = lastCommit
        lastCommit = null
        if (lc != null && lc.word == bridge.composedWord) {
            lc.learned?.let { langModel.retract(it) }
            lastWord = lc.prev1; lastWord2 = lc.prev2
        } else { lastWord = null; lastWord2 = null }
    }

    private fun commitAndLearn(word: String, accepted: Boolean = false) {
        lastCommit = null
        if (word.isEmpty()) return
        // Nội dung gõ tắt nhiều từ ("mọi người"): học lần lượt từng từ (bigram trong cụm).
        val parts = ShortcutFile.words(word)
        if (parts.size != 1 || parts[0] != word) {
            for (p in parts) commitAndLearn(p, accepted)
            if (parts.isEmpty()) { lastWord = null; lastWord2 = null }
            return
        }
        val learned = if (learnEnabled) langModel.record(word, lastWord, lastWord2, if (accepted) 2 else 1) else null
        lastCommit = LastCommit(word, lastWord, lastWord2, learned)
        if (UserLangModel.learnable(word)) { lastWord2 = lastWord; lastWord = word }
        else { lastWord = null; lastWord2 = null }
    }

    // MARK: gợi ý

    private fun caseForContext(w: String) = if (autoShiftOn) Cp.capitalizeFirst(w) else w

    private fun padWords(base: List<String>, need: Int, typed: String = ""): List<String> {
        if (base.size >= need) return base.take(need)
        val cands = SensitiveWords.filter(langModel.topWords(need + 12), filterSensitive)
            .map { caseForContext(DisplayCase.apply(it)) }
        return SuggestionFill.pad(base, cands, need, typed)
    }

    /** Gọi sau debounce 30 ms (hoặc khi hiện bàn phím / selection đổi / bật bar). */
    fun requestSuggestions(proxy: TextProxy): SuggestionPlan {
        suggestReq++
        numberChip = null
        if (!suggestionsActive || barCollapsed) return SuggestionPlan.Ready(null)
        swipeAlternatives?.let { alts ->
            val u = reviseUndo
            return SuggestionPlan.Ready(SuggestionSet(nextWords = alts, actionLabel = u?.let { "↩\uFE0E ${it.first}" },
                action = u?.let { SuggestionSet.UNDO_REVISE_TOKEN }))
        }
        val composed = bridge.composedWord
        var literal: String? = null
        if (composed.isEmpty() && undoOfferActive) literal = restoreUndoComposed
        if (composed.isEmpty() && lastKeyWasEmailTrigger) {
            val before = proxy.contextBeforeInput()
            val last = before?.split(' ')?.lastOrNull { it.isNotEmpty() }
            if (last != null) {
                if (last.endsWith("@") && Cp.count(last) > 1)
                    return SuggestionPlan.Ready(SuggestionSet(nextWords = EMAIL_SUFFIXES))
                if (last.endsWith(".") && Cp.count(last) > 1 &&
                    last.dropLast(1).codePoints().allMatch { Character.isLetterOrDigit(it) })
                    return SuggestionPlan.Ready(SuggestionSet(nextWords = DOMAIN_TLDS))
            }
        }
        if (composed.isNotEmpty()) {
            val b = bridge
            return SuggestionPlan.Background(SuggestJob(suggestReq, generation, b, composed,
                b.rawWord, b.predictedCommit, b.autoFixAdjacent, lastWord, refreshNumberChip(proxy)))
        }
        val prev = lastWord
        val next: List<String> = if (prev != null) {
            // cá nhân/seed trước; thiếu thì lấp bằng bigram tĩnh (người dùng mới) rồi mới topWords
            val personal = SensitiveWords.filter(langModel.nextWords(prev, lastWord2, 6), filterSensitive).take(3)
            val n = if (personal.size >= 3) personal else SuggestionFill.pad(personal,
                SensitiveWords.filter(SuggestRank.bigramNext(prev, 6), filterSensitive), 3)
            padWords(n.map { caseForContext(DisplayCase.apply(it, prev)) }, 3)
        } else {
            val top = SensitiveWords.filter(langModel.topWords(6), filterSensitive)
                .take(3).map { caseForContext(DisplayCase.apply(it)) }
            padWords(top, 3)
        }
        val number = refreshNumberChip(proxy)
        val paste = pasteOffer(proxy)
        // Chip tách STK/SĐT/OTP = Clipboard nâng cao (Plus; paywall tắt ⇒ mở cho mọi người).
        val chips = if (paste && !incognito && PlusGate.isUnlocked(PlusFeature.ADVANCED_CLIPBOARD)) clipChips() else emptyList()
        // "Hoàn tác" thêm dấu (vừa bấm) thắng thẻ Dán; "Thêm dấu" nhường thẻ Dán (StripView/SuggestionSlots).
        if (tonesUndo != null) return SuggestionPlan.Ready(SuggestionSet(literal = literal, nextWords = next,
            number = number, actionLabel = UNDO_TONES_LABEL, action = SuggestionSet.UNDO_TONES_TOKEN))
        val offer = literal == null && addTonesPlan(proxy) != null
        return SuggestionPlan.Ready(SuggestionSet(literal = literal, nextWords = next, paste = paste,
            number = number, clipChips = chips,
            actionLabel = if (offer) ADD_TONES_LABEL else null, action = if (offer) SuggestionSet.ADD_TONES_TOKEN else null))
    }

    /** Chip số cho token trước con trỏ (đọc chữ / định dạng tiền / máy tính nhanh). */
    private fun refreshNumberChip(proxy: TextProxy): String? {
        numberChip = null
        if (!numberChipsOn || numberSpaces > 1) return null
        val before = proxy.contextBeforeInput() ?: return null
        numberChip = NumberChips.chip(before)
        return numberChip?.display
    }

    /** Áp kết quả nền; null nếu đã lỗi thời (phím mới / lượt mới / từ khác / bar tắt). */
    fun completeSuggestions(job: SuggestJob, result: SuggestJob.Result): SuggestionSet? {
        if (job.req != suggestReq || job.gen != generation || bridge !== job.bridge ||
            job.bridge.composedWord != job.composed || !suggestionsActive || barCollapsed) return null
        return composingSuggestions(job.composed, job.raw, job.predicted, result.pool, result.fix, result.pmi)
            .copy(number = job.number)
    }

    /** Đồng bộ (test / debug): tính luôn trên thread gọi. */
    fun suggestionsNow(proxy: TextProxy): SuggestionSet? = when (val p = requestSuggestions(proxy)) {
        is SuggestionPlan.Ready -> p.set
        is SuggestionPlan.Background -> completeSuggestions(p.job, p.job.compute())
    }

    private fun composingSuggestions(composed: String, raw: String, predicted: String,
                                     pool: List<VNSuggest.Match>, fix: String?,
                                     pmi: FloatArray? = null): SuggestionSet {
        val literal = if (predicted == composed) raw else composed
        var word: String? = null
        var word2: String? = null
        // Từ thêm tay (Từ điển cá nhân) khớp tiền tố: đứng đầu pool (freq cao) — lexicon
        // không có tên riêng/thuật ngữ nên VNSuggest không bao giờ đưa ra.
        val manualHits = langModel.manualCompletions(composed)
        val pool = if (manualHits.isEmpty()) pool else {
            val low = manualHits.mapTo(HashSet()) { it.lowercase() }
            manualHits.map { VNSuggest.Match(it, MANUAL_FREQ) } + pool.filter { it.word.lowercase() !in low }
        }
        if (pool.isNotEmpty()) {
            val ctxKey = (lastWord ?: "") + "\u0001" + (lastWord2 ?: "")
            if (ctxKey != ctxCacheKey) {
                ctxCache = lastWord?.let { langModel.nextWords(it, lastWord2, 24).toSet() } ?: emptySet()
                ctxCacheKey = ctxKey
            }
            val ctx = ctxCache
            val ranked = SensitiveWords.filter(
                SuggestRank.rankInline(pool, pmi, Cp.count(composed), langModel::count, ctx), filterSensitive)
            word = ranked.firstOrNull()?.let { DisplayCase.apply(it, lastWord) }
            word2 = ranked.getOrNull(1)?.let { DisplayCase.apply(it, lastWord) }
        } else if (fix != null) {
            word = fix
        }
        var emojis: List<String> = emptyList()
        val cLow = composed.lowercase()
        lastWord?.let { emojis = EmojiSuggest.emojis(it.lowercase() + " " + cLow) }
        if (emojis.isEmpty()) emojis = EmojiSuggest.emojis(composed)
        if (emojis.isEmpty()) emojis = EmojiSuggest.emojis(raw.lowercase())
        if (emojis.isEmpty()) {
            val words = padWords(listOfNotNull(word, word2), 2, composed)
            word = words.firstOrNull()
            word2 = if (words.size > 1) words.last() else null
        }
        // Đang gõ đúng một chữ tắt: slot chính hiện nội dung sẽ bung (chạm = bung ngay).
        // Nội dung nhiều dòng không lên bar (gõ ranh giới vẫn bung).
        val preview = bridge.shortcutPreview
        if (preview != null && !preview.contains('\n') && word != preview) { word2 = word ?: word2; word = preview }
        return SuggestionSet(literal = literal, word = word, word2 = word2, emojis = emojis)
    }

    // MARK: nút Dán

    private var pasteSeenChange = -1
    private var pasteSeenAt = Long.MIN_VALUE / 2
    private var pasteUsedChange = -1
    private var pasteCheckedAt = Long.MIN_VALUE / 2
    private var pasteCached = false

    /** Bàn phím vừa hiện hẳn / clipboard đổi: bỏ cache 2 s. */
    fun invalidatePasteCache() { pasteCheckedAt = Long.MIN_VALUE / 2 }

    /** Kết quả nút Dán gần nhất (IME so trước/sau invalidate để quyết refresh). */
    val pasteCachedValue: Boolean get() = pasteCached

    internal fun pasteOffer(proxy: TextProxy): Boolean {
        val cb = clipboard ?: return false
        val last = proxy.contextBeforeInput()?.let { Cp.lastCodePoint(it) }
        if (last != null && !Character.isWhitespace(last)) return false
        val now = clock()
        if (now - pasteCheckedAt < 2000) return pasteCached
        pasteCheckedAt = now
        val cc = cb.changeCount
        if (cc != pasteSeenChange) { pasteSeenChange = cc; pasteSeenAt = now }
        val has = cb.hasText()
        pasteCached = cc != pasteUsedChange && has && now - pasteSeenAt < 180_000
        if (TouchLog.enabled) TouchLog.write("paste: cc=$cc used=$pasteUsedChange hasText=${if (has) 1 else 0} " +
            "age=${(now - pasteSeenAt) / 1000}s → ${if (pasteCached) 1 else 0}")
        return pasteCached
    }

    // MARK: chip số + lịch sử clipboard

    private var chipsForChange = -1
    private var chipsCached: List<ClipChip> = emptyList()

    /** Chip của clip hiện tại (đọc nội dung 1 lần mỗi changeCount); clip nhạy cảm → không chip. */
    internal fun clipChips(): List<ClipChip> {
        val cb = clipboard ?: return emptyList()
        val cc = cb.changeCount
        if (cc != chipsForChange) {
            chipsForChange = cc
            chipsCached = if (cb.isSensitive()) emptyList()
                else cb.readText()?.let { ClipDetect.detect(it) } ?: emptyList()
        }
        return chipsCached
    }

    /**
     * Clip vừa đổi (listener) hoặc bàn phím vừa hiện: ghi vào lịch sử nếu được phép —
     * lịch sử bật, không ẩn danh, ô đang hiện không phải mật khẩu ([fieldSecure]), clip
     * không đánh dấu nhạy cảm. [onlyIfNew]: bỏ qua nếu nội dung đã có (lúc hiện bàn phím,
     * không làm mới hạn của mục cũ). Trả true nếu lịch sử đổi (IME ghi file).
     */
    fun recordClip(fieldSecure: Boolean, onlyIfNew: Boolean = false): Boolean {
        val h = clipHistory ?: return false
        val cb = clipboard ?: return false
        if (incognito || fieldSecure || cb.isSensitive()) return false
        val text = cb.readText() ?: return false
        if (onlyIfNew && h.contains(text)) return false
        return h.add(text, clock())
    }

    /** Chạm một mục trong bảng lịch sử: chèn nguyên văn, không học, không space. */
    fun insertClip(text: String, proxy: TextProxy) {
        clearSwipe(); clearUndo()
        if (text.isNotEmpty()) proxy.insertText(text)
        bridge.reset(); lastWord = null; lastWord2 = null
        lastCommit = null
    }

    // MARK: chạm gợi ý

    /**
     * Chạm slot (QuickType): emoji thay từ; từ thay từ + space (học weight 2); fragment
     * (`gmail.com`, `com`) chèn không space; [SuggestionSet.PASTE_TOKEN] dán clipboard.
     * Sau đó IME gọi updateAutoShift + refresh bar, phát click.
     */
    fun acceptSuggestion(item: String, proxy: TextProxy) {
        if (item == SuggestionSet.PASTE_IMAGE_TOKEN) {
            pasteUsedChange = clipboard?.changeCount ?: -1; pasteCached = false
            return
        }
        if (item == SuggestionSet.ADD_TONES_TOKEN) { applyAddTones(proxy); return }
        if (item == SuggestionSet.UNDO_TONES_TOKEN) { undoAddTones(proxy); return }
        if (item == SuggestionSet.UNDO_REVISE_TOKEN) { undoRevise(proxy); return }
        tonesUndo = null
        if (item.startsWith(SuggestionSet.CLIP_CHIP_PREFIX)) {
            proxy.insertText(item.substring(SuggestionSet.CLIP_CHIP_PREFIX.length))
            pasteUsedChange = clipboard?.changeCount ?: -1
            pasteCached = false
            bridge.reset(); lastWord = null; lastWord2 = null
            return
        }
        if (item == SuggestionSet.PASTE_TOKEN) {
            val cb = clipboard
            val s = cb?.readText()
            if (!s.isNullOrEmpty()) proxy.insertText(s)
            pasteUsedChange = cb?.changeCount ?: -1
            pasteCached = false
            bridge.reset(); lastWord = null; lastWord2 = null
            return
        }
        if (item == SuggestionSet.NUMBER_TOKEN) { acceptNumberChip(proxy); return }
        val sw = openSwipeWord()
        if (sw != null && item in swipeAlts) {
            // Chạm biến thể của từ vừa vuốt: thay từ, vẫn là composition mở (chưa học — học khi chốt).
            if (!proxy.confirmTail(sw)) { clearSwipe(); bridge.reset(); return }
            proxy.deleteCodePoints(Cp.count(sw))
            proxy.insertText(item)
            val itemEnglish = item in swipeEnglishAlts
            // phương án chéo đổi chỗ với từ cũ (từ cũ tiếng Anh ⇒ vẫn là phương án tiếng Anh)
            val eng = swipeEnglishAlts - item + (if (swipeLiteral) setOf(sw) else emptySet())
            val alts = swipeAlts.map { if (it == item) sw else it }
            revisable = null                       // user đã chọn: cú vuốt kế không sửa lại từ này
            if (itemEnglish) {
                bridge.adoptLiteral()
                swipeWord = item; swipeLiteral = true; swipeAlts = alts; swipeEnglishAlts = eng
            } else if (bridge.adoptWord(item)) {
                swipeWord = item; swipeLiteral = false; swipeAlts = alts; swipeEnglishAlts = eng
            } else clearSwipe()
            return
        }
        clearSwipe()
        val uRaw = restoreUndoRaw; val uComposed = restoreUndoComposed
        if (undoOfferActive && uRaw != null && uComposed != null && item == uComposed && bridge.composedWord.isEmpty()) {
            if (!proxy.confirmTail(uRaw)) {
                // Chữ vừa chốt không còn trước con trỏ: không xoá mù, bỏ lời mời hoàn tác.
                clearUndo(); bridge.reset()
                return
            }
            proxy.deleteCodePoints(Cp.count(uRaw))
            proxy.insertText("$uComposed ")
            clearUndo()
            bridge.reset()
            commitAndLearn(uComposed, accepted = true)
            return
        }
        clearUndo()
        val isFragment = item.contains('.') || item.contains('@')
        val isWord = !isFragment && item.isNotEmpty() && Character.isLetter(item.codePointAt(0))
        val n = Cp.count(bridge.composedWord)
        // Fail-safe: từ đang soạn không còn trước con trỏ ⇒ chèn, không xoá mù.
        if (n > 0 && proxy.confirmTail(bridge.composedWord)) proxy.deleteCodePoints(n)
        proxy.insertText(if (isWord) "$item " else item)
        bridge.reset()
        if (isWord) commitAndLearn(item, accepted = true) else { lastWord = null; lastWord2 = null }
    }

    /**
     * Chip "↩︎ từ cũ": trả từ vuốt trước về như lúc vuốt (đuôi phải đúng "từ mới + từ đang
     * mở", lệch ⇒ bỏ) và học lại từ cũ thay từ mới.
     */
    private fun undoRevise(proxy: TextProxy) {
        val (old, new) = reviseUndo ?: return
        reviseUndo = null
        revisable = null
        val sw = openSwipeWord() ?: return
        val tail = "$new $sw"
        if (!proxy.confirmTail(tail)) return
        proxy.deleteCodePoints(Cp.count(tail))
        proxy.insertText("$old $sw")
        bridge.forgetLastCommit()
        val lc = lastCommit
        if (lc != null && lc.word == new) {
            lc.learned?.let { langModel.retract(it) }
            lastWord = lc.prev1; lastWord2 = lc.prev2
        }
        commitAndLearn(old, accepted = true)
    }

    /** Chạm chip số: thay đúng đuôi đã tính (kiểm lại đuôi trước khi xoá — lệch thì bỏ). */
    private fun acceptNumberChip(proxy: TextProxy) {
        val c = numberChip ?: return
        numberChip = null
        if (c.replace.isNotEmpty()) {
            if (!proxy.confirmTail(c.replace)) { TouchLog.write("failsafe: number chip tail mismatch → skip"); return }
            proxy.deleteCodePoints(Cp.count(c.replace))
        }
        proxy.insertText(c.insert)
        bridge.reset()
        lastWord = null; lastWord2 = null
        clearUndo(); clearSwipe()
        numberSpaces = 0          // kết quả mới cũng là số → chip kế trong chuỗi (tiền → chữ)
    }

    // MARK: thêm dấu cho câu không dấu (chỉ khi người dùng bấm chip — AddTones.kt)

    private fun tonesPersonal() = AddTones.Personal(langModel::count, langModel::bigramCount)

    /** Kế hoạch thêm dấu cho chữ trước con trỏ (cache theo văn bản); null = không mời. */
    private fun addTonesPlan(proxy: TextProxy): AddTones.Plan? {
        if (!addTonesChip) return null
        if (!PlusGate.isUnlocked(PlusFeature.SENTENCE_DIACRITICS)) return null
        if (bridge.isComposing || !proxy.canReEdit || proxy.hasSelection) return null
        val before = proxy.contextBeforeInput()
        if (before.isNullOrEmpty()) return null
        if (before != tonesCacheBefore) {
            tonesCacheBefore = before
            tonesCachePlan = AddTones.plan(before, tonesPersonal())?.takeIf { it.original != tonesDismissed }
        }
        return tonesCachePlan
    }

    /** Chạm "Thêm dấu": thay đuôi không dấu bằng bản có dấu (fail-safe confirmTail, không xoá mù). */
    fun applyAddTones(proxy: TextProxy) {
        tonesCacheBefore = null
        val plan = addTonesPlan(proxy) ?: return
        tonesCacheBefore = null
        if (!proxy.confirmTail(plan.original)) return
        proxy.deleteCodePoints(Cp.count(plan.original))
        proxy.insertText(plan.replacement)
        bridge.reset(); lastWord = null; lastWord2 = null; clearUndo(); lastCommit = null
        tonesUndo = plan
    }

    /** "Hoàn tác" / ⌫ ngay sau: trả lại bản gốc nếu chữ trước con trỏ vẫn là bản vừa thay. */
    fun undoAddTones(proxy: TextProxy) {
        val u = tonesUndo ?: return
        tonesUndo = null
        tonesCacheBefore = null
        if (!proxy.canReEdit || !proxy.confirmTail(u.replacement)) return
        proxy.deleteCodePoints(Cp.count(u.replacement))
        proxy.insertText(u.original)
        tonesDismissed = u.original
        bridge.reset(); lastWord = null; lastWord2 = null; clearUndo(); lastCommit = null
    }

    companion object {
        const val ADD_TONES_LABEL = "Thêm dấu"
        const val UNDO_TONES_LABEL = "↩\uFE0E Hoàn tác"
        /** freq giả cho từ thêm tay trong pool hoàn thiện = trần freq lexicon (255). */
        const val MANUAL_FREQ = 255
        val EMAIL_SUFFIXES = listOf("gmail.com", "yahoo.com", "outlook.com")
        val DOMAIN_TLDS = listOf("com", "vn", "net")

        /** Auto-shift thuần: ô trống, hoặc " " sau .!?, hoặc sau \n. */
        fun autoShiftFor(before: String): Boolean {
            val t = before.trim(' ', '\t')
            return before.isEmpty() ||
                (before.endsWith(" ") && (t.endsWith(".") || t.endsWith("!") || t.endsWith("?"))) ||
                before.endsWith("\n")
        }

        /** Mode mạnh nhất của ô (≈ bitmask TextUtils.getCapsMode: có bit nào là shift). */
        fun capMode(t: FieldTraits): CapMode = when {
            t.capCharacters -> CapMode.CHARACTERS
            t.capWords -> CapMode.WORDS
            t.capSentences -> CapMode.SENTENCES
            else -> CapMode.NONE
        }

        /**
         * Auto-shift thuần theo mode (logic tương đương TextUtils.getCapsMode, không cần
         * android.jar): CHARACTERS luôn hoa; WORDS đầu ô hoặc sau khoảng trắng (bỏ qua
         * ngoặc/nháy mở như getCapsMode: `("` rồi mới tới chữ); SENTENCES như [autoShiftFor].
         */
        fun autoShiftFor(before: String, mode: CapMode): Boolean = when (mode) {
            CapMode.NONE -> false
            CapMode.CHARACTERS -> true
            CapMode.SENTENCES -> autoShiftFor(before)
            CapMode.WORDS -> {
                val t = before.trimEnd('"', '\'', '(', '[', '{', '“', '‘', '«')
                t.isEmpty() || t.last().isWhitespace()
            }
        }
    }
}
