package com.viettelex.keyboard

/**
 * Tên SharedPreferences, key và file dùng chung IME (agent C) + app settings (agent D).
 * Key giữ nguyên tên iOS (App Group `group.com.viettelex`), spec §9.
 */
object Keys {
    const val PREFS = "viettelex"

    // Kiểu Gõ
    const val SIMPLE_TELEX = "simpleTelex"
    const val FREE_MARKING = "freeMarking"
    const val QUICK_TELEX = "quickTelex"
    const val MODERN_TONE = "modernTone"
    const val CONTEXTUAL_ENGLISH = "contextualEnglish"
    const val RE_EDIT_WORDS = "reEditWords"
    const val AUTO_FIX_ADJACENT = "autoFixAdjacent"
    const val TEENCODE = "teencode"
    /** Tự động viết hoa đầu câu (Bool, mặc định BẬT) — tắt ⇒ không auto-shift, không đọc context. */
    const val AUTO_CAPITALIZE = "autoCapitalize"
    /** Kiểu gõ VNI (Bool, mặc định false = Telex) — tên như iOS App Group / macOS. */
    const val VNI_MODE = "vniMode"
    // Tính Năng
    const val AUTO_RESTORE = "autoRestore"
    const val LIVE_SPELL_CHECK = "liveSpellCheck"
    /** Gõ vuốt (thử nghiệm, mặc định tắt). */
    const val SWIPE_TYPING = "swipeTyping"
    const val SWIPE_ENGLISH = "swipeEnglish"
    /** Giải mã vuốt bằng mô hình FUTO Swipe (thử nghiệm, mặc định TẮT — FutoSwipe). */
    const val SWIPE_FUTO = "swipeFuto"
    /** Luyện vuốt (app): đồng ý LƯU nét vuốt trên máy để xuất (mặc định TẮT, không gửi mạng). */
    const val SWIPE_PRACTICE_SAVE = "swipePracticeSave"
    /** Chọn phím theo ngữ cảnh lúc chạm (thử nghiệm, mặc định BẬT) — TouchTarget. */
    const val SMART_TOUCH = "smartTouch"
    /** Tự sửa từ gõ sai ở dấu cách (thử nghiệm, mặc định TẮT) — AutoCorrect. */
    const val AUTO_CORRECT = "autoCorrect"
    /** Từ từng hoàn tác tự sửa (chuỗi nhiều dòng) — trạng thái bàn phím, KHÔNG sao lưu. */
    const val AUTO_CORRECT_REJECTED = "autoCorrectRejected"
    /** Vuốt phím cách đổi Tiếng Việt ↔ Tiếng Anh — mặc định TẮT (tắt ⇒ luôn Tiếng Việt). */
    const val SPACE_SWIPE_LANGUAGE = "spaceSwipeLanguage"
    /** Tự thêm dấu cách sau . , ? ! ; : ([AutoSpace]) — mặc định TẮT. Giống iOS. */
    const val AUTO_SPACE_AFTER_PUNCT = "autoSpaceAfterPunct"
    /** Ngôn ngữ đang gõ ("vi" | "en") — trạng thái bàn phím, KHÔNG sao lưu. */
    const val KEYBOARD_LANGUAGE = "keyboardLanguage"
    /** Gõ Telex bằng bàn phím cứng (tablet, DeX, Chromebook, BT/USB) — mặc định BẬT. */
    const val HARDWARE_TELEX = "hardwareTelex"

    /** Gõ tắt: bật/tắt (mặc định BẬT) + bảng (String YAML phẳng như macOS, xem [ShortcutFile]). */
    const val SHORTCUTS_ENABLED = "shortcutsEnabled"
    const val SHORTCUTS = "shortcuts"

    /** Key ảnh hưởng engine/EngineBridge — đổi lúc bàn phím đang mở thì áp ngay. */
    val ENGINE_KEYS = setOf(SIMPLE_TELEX, FREE_MARKING, QUICK_TELEX, MODERN_TONE, CONTEXTUAL_ENGLISH,
        AUTO_FIX_ADJACENT, TEENCODE, AUTO_RESTORE, LIVE_SPELL_CHECK, SHORTCUTS_ENABLED, SHORTCUTS, VNI_MODE)
    const val SHOW_SUGGESTIONS = "showSuggestions"
    /**
     * Chip "Thêm dấu" hiện TỰ ĐỘNG trên thanh gợi ý (Bool, mặc định TẮT — ưu tiên gõ trơn):
     * tắt ⇒ không đọc chữ trước con trỏ / không chạy AddTones ở mỗi dấu cách.
     */
    const val ADD_TONES_CHIP = "addTonesChip"
    /** Chip số (đọc số thành chữ / tiền / máy tính nhanh) — mặc định BẬT; tắt ⇒ không đọc context sau chữ số. */
    const val NUMBER_CHIPS = "numberChips"
    const val FILTER_SENSITIVE = "filterSensitive"
    const val TEMPLATES_ENABLED = "templatesEnabled"
    const val SHOW_SPACE_LOGO = "showSpaceLogo"
    /** Bool — ô phóng to chữ khi bấm phím (balloon); tên như iOS App Group. Mặc định BẬT. */
    const val KEY_PREVIEW = "keyPreviewEnabled"
    const val HAPTIC_FEEDBACK = "hapticFeedback"
    /** Độ mạnh rung 10…100 % (mặc định 45, [HapticStrength]) — giống iOS. */
    const val HAPTIC_STRENGTH = "hapticStrength"
    /** Bool — âm thanh phím riêng ([KeySoundSynth]), mặc định TẮT (= tiếng hệ thống như cũ). */
    const val KEY_SOUND = "keySound"
    /** Int 0…100 (%) — âm lượng âm phím riêng, mặc định 50. */
    const val KEY_SOUND_VOLUME = "keySoundVolume"
    /** Int −10…10 (dp mỗi hàng). */
    const val ROW_HEIGHT_ADJUST = "rowHeightAdjust"
    /** Bool — hàng phím số trên plane chữ (tên như iOS App Group). */
    const val NUMBER_ROW = "numberRow"
    /** Bool — giữ q…p ra 1…0 (chỉ khi hàng số tắt), mặc định BẬT — [KeyAlternates]. */
    const val LONG_PRESS_NUMBERS = "longPressNumbers"
    /** Bool — giữ a–l, z–m ra ký hiệu, mặc định TẮT — [KeyAlternates]. */
    const val LONG_PRESS_SYMBOLS = "longPressSymbols"
    /** String "off" | "left" | "right" — chế độ một tay (điện thoại; tên như iOS App Group). */
    const val ONE_HAND_MODE = "oneHandMode"
    /** String "vi" | "en" — ngôn ngữ giao diện app + chữ trên bàn phím ([L10n]). Mặc định "vi"
     *  LUÔN (không theo ngôn ngữ máy); tên như iOS App Group. */
    const val UI_LANGUAGE = "uiLanguage"
    /** String "left" | "right" — bên dùng gần nhất (giữ lâu icon con trỏ bật lại bên này). */
    const val ONE_HAND_LAST = "oneHandLastSide"
    /** String JSON `[{"label":…,"text":…}]`; vắng ⇒ mặc định từ assets/ios-mau-cau.yml. */
    const val USER_TEMPLATES = "userTemplates"
    const val DEBUG_TOUCH_LOG = "debugTouchLog"
    // Theme & ảnh nền ([ThemeSettings]) — tên như iOS App Group.
    const val KEYBOARD_THEME = "keyboardTheme"
    const val WALLPAPER_ENABLED = "wallpaperEnabled"
    const val WALLPAPER_DIM = "wallpaperDim"
    const val WALLPAPER_BLUR = "wallpaperBlur"
    const val WALLPAPER_VERSION = "wallpaperVersion"
    /** Độ trong suốt phím (nền + phím) / ký tự trên phím, 0…100. */
    const val KEYBOARD_TRANSPARENCY = "keyboardTransparency"
    const val KEY_LABEL_TRANSPARENCY = "keyLabelTransparency"
    /** Lịch sử clipboard (mặc định TẮT — riêng tư). */
    const val CLIPBOARD_HISTORY = "clipboardHistory"
    /** Chế độ ẩn danh thủ công: không học từ, không lưu clipboard. */
    const val INCOGNITO = "incognitoMode"
    // nội bộ IME
    const val SUGGESTION_BAR_COLLAPSED = "suggestionBarCollapsed"
    /** String, emoji nối bằng '\n' (xem [EmojiRecents]). */
    const val EMOJI_RECENTS = "emojiRecents"
    /** Long ms — app ghi khi user bấm "Xóa từ đã học" (đã xoá [USERLM_FILE]). */
    const val USERLM_RESET_AT = "userlmResetAt"

    // VietTelex Plus (xem [PlusGate]) — app ghi, IME chỉ đọc.
    /** Boolean: đã mua Plus (Play Billing xác nhận + acknowledge). */
    const val PLUS_UNLOCKED = "plusUnlocked"
    /** Boolean: giả lập đã mua — chỉ bản debug nghe. */
    const val PLUS_DEBUG_OVERRIDE = "plusDebugOverride"

    // file trong filesDir
    const val USERLM_FILE = "userlm.bin"
    const val TOUCHLOG_FILE = "touchlog.txt"
    /** Ảnh nền đã thu nhỏ/mờ/nén cho IME; bản chưa mờ để đổi độ mờ không cần chọn lại. */
    const val WALLPAPER_FILE = "wallpaper.jpg"
    const val WALLPAPER_SRC_FILE = "wallpaper-src.jpg"
    const val CLIPBOARD_FILE = "clipboard-history.txt"

    // assets
    const val ASSET_LEXICON = "vnlexicon.bin"
    const val ASSET_EN_LEXICON = "enlexicon.bin"
    const val ASSET_LM = "vnlm.bin"
    /** Encoder FUTO Swipe fp16 (FUTO Model Weights License 1.0 — chỉ đọc khi bật SWIPE_FUTO). */
    const val ASSET_FUTO = "futoswipe.bin"
    const val ASSET_EMOJI_SUGGEST = "emojisuggest.bin"
    const val ASSET_SEED = "seed.tsv"
    /** Emoji + khoá tìm tiếng Việt + kaomoji (Scripts/gen-emoji-data.py, chung iOS). */
    const val ASSET_EMOJI_DATA = "emoji.bin"
    const val ASSET_TEMPLATES_YAML = "ios-mau-cau.yml"
    const val ASSET_SPACE_LOGO = "spacelogo.png"
}
