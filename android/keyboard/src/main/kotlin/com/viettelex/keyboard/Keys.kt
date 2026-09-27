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
    /** Kiểu gõ VNI (Bool, mặc định false = Telex) — tên như iOS App Group / macOS. */
    const val VNI_MODE = "vniMode"
    // Tính Năng
    const val AUTO_RESTORE = "autoRestore"
    const val LIVE_SPELL_CHECK = "liveSpellCheck"
    /** Gõ vuốt (thử nghiệm, mặc định tắt). */
    const val SWIPE_TYPING = "swipeTyping"
    const val SWIPE_ENGLISH = "swipeEnglish"
    /** Gõ Telex bằng bàn phím cứng (tablet, DeX, Chromebook, BT/USB) — mặc định BẬT. */
    const val HARDWARE_TELEX = "hardwareTelex"

    /** Gõ tắt: bật/tắt (mặc định BẬT) + bảng (String YAML phẳng như macOS, xem [ShortcutFile]). */
    const val SHORTCUTS_ENABLED = "shortcutsEnabled"
    const val SHORTCUTS = "shortcuts"

    /** Key ảnh hưởng engine/EngineBridge — đổi lúc bàn phím đang mở thì áp ngay. */
    val ENGINE_KEYS = setOf(SIMPLE_TELEX, FREE_MARKING, QUICK_TELEX, MODERN_TONE, CONTEXTUAL_ENGLISH,
        AUTO_FIX_ADJACENT, TEENCODE, AUTO_RESTORE, LIVE_SPELL_CHECK, SHORTCUTS_ENABLED, SHORTCUTS, VNI_MODE)
    const val SHOW_SUGGESTIONS = "showSuggestions"
    const val FILTER_SENSITIVE = "filterSensitive"
    const val TEMPLATES_ENABLED = "templatesEnabled"
    const val SHOW_SPACE_LOGO = "showSpaceLogo"
    const val HAPTIC_FEEDBACK = "hapticFeedback"
    /** Int −10…10 (dp mỗi hàng). */
    const val ROW_HEIGHT_ADJUST = "rowHeightAdjust"
    /** Bool — hàng phím số trên plane chữ (tên như iOS App Group). */
    const val NUMBER_ROW = "numberRow"
    /** String "off" | "left" | "right" — chế độ một tay (điện thoại; tên như iOS App Group). */
    const val ONE_HAND_MODE = "oneHandMode"
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
    const val ASSET_BIGRAM = "vnbigram.bin"
    const val ASSET_LM = "vnlm.bin"
    const val ASSET_EMOJI_SUGGEST = "emojisuggest.bin"
    const val ASSET_SEED = "seed.tsv"
    /** Emoji + khoá tìm tiếng Việt + kaomoji (Scripts/gen-emoji-data.py, chung iOS). */
    const val ASSET_EMOJI_DATA = "emoji.bin"
    const val ASSET_TEMPLATES_YAML = "ios-mau-cau.yml"
    const val ASSET_SPACE_LOGO = "spacelogo.png"
}
