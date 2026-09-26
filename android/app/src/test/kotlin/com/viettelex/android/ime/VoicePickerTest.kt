package com.viettelex.android.ime

import com.viettelex.android.ime.VoicePicker.Candidate
import com.viettelex.android.ime.VoicePicker.Pick
import com.viettelex.android.ime.VoicePicker.Sub
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VoicePickerTest {
    private val self = "com.viettelex.android"
    private val gboard = Candidate("com.google.android.inputmethod.latin/.LatinIME",
        "com.google.android.inputmethod.latin", listOf(Sub("keyboard", "en-US"), Sub("keyboard", "vi")))
    private val googleVoice = Candidate(
        "com.google.android.googlequicksearchbox/com.google.android.voicesearch.ime.VoiceInputMethodService",
        "com.google.android.googlequicksearchbox", listOf(Sub("voice", "en-US"), Sub("voice", "vi-VN")))
    private val otherVoice = Candidate("com.example.voice/.Ime", "com.example.voice", listOf(Sub("voice")))
    private val mine = Candidate("$self/.ime.VietTelexIME", self, listOf(Sub("keyboard", "vi-VN"), Sub("voice")))

    @Test fun noVoiceImeMeansHidden() {
        assertNull(VoicePicker.pick(listOf(gboard, mine), self))   // chính mình không tính
        assertNull(VoicePicker.pick(emptyList(), self))
    }

    @Test fun prefersGoogleVoiceTypingAndVietnameseSubtype() {
        assertEquals(Pick(googleVoice.id, 1), VoicePicker.pick(listOf(gboard, otherVoice, googleVoice, mine), self))
    }

    @Test fun fallsBackToAnyVoiceIme() {
        assertEquals(Pick(otherVoice.id, 0), VoicePicker.pick(listOf(gboard, otherVoice), self))
        val mixed = Candidate("x/.Ime", "x", listOf(Sub("keyboard"), Sub("voice", "en")))
        assertEquals(Pick("x/.Ime", 1), VoicePicker.pick(listOf(mixed), self))
    }
}
