package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer

/**
 * keyprior.bin (trie chọn phím thông minh dựng sẵn) ≡ dựng trong RAM từ lexicon.
 *
 * Sinh lại asset (đổi vnlexicon/enlexicon/seed hoặc thuật toán TelexSpell/build):
 *   `VT_REGEN_KEYPRIOR=1 ./gradlew --offline :keyboard:test --tests '*KeyPriorBlobTests*'`
 */
class KeyPriorBlobTests {
    @Before fun setUp() = TestAssets.install()

    private val ref by lazy { TelexKeyPrior.fromLexicon() }

    private fun assetFile(): File =
        listOf(File("../app/src/main/assets"), File("app/src/main/assets"), File("android/app/src/main/assets"))
            .first { File(it, Keys.ASSET_LEXICON).exists() }.let { File(it, Keys.ASSET_KEY_PRIOR) }

    private fun fresh(): ByteArray =
        KeyPriorBlob.encode(ref.trie, KeyPriorBlob.inputCrc(), TelexKeyPrior.LAMBDA, TelexKeyPrior.ENGLISH)

    @Test fun assetMatchesInMemoryBuild() {
        val bytes = fresh()
        val f = assetFile()
        if (System.getenv("VT_REGEN_KEYPRIOR") == "1") {
            val tmp = File(f.parentFile, f.name + ".tmp"); tmp.writeBytes(bytes)   // inode mới: bản đang mmap không bị cắt
            check(tmp.renameTo(f)); println("KEYPRIOR wrote ${f.path} ${bytes.size} B") }
        val h = KeyPriorBlob.header(ByteBuffer.wrap(f.readBytes()).order(java.nio.ByteOrder.LITTLE_ENDIAN))
        assertNotNull("thiếu/hỏng ${f.path}", h)
        assertEquals("asset lệch dữ liệu nguồn — chạy VT_REGEN_KEYPRIOR=1 (xem docstring)", KeyPriorBlob.inputCrc(), h!!.inputCrc)
        assertArrayEquals("asset lệch bản dựng trong RAM — VT_REGEN_KEYPRIOR=1", bytes, f.readBytes())
    }

    /** Duyệt đủ mọi nút của hai trie cùng lúc: cùng con, cùng trọng số (bit). */
    @Test fun mappedTrieIsIdenticalToArrayTrie() {
        val m = KeyTrie.mapped(ByteBuffer.wrap(fresh()))!!
        val a = ref.trie
        assertEquals(a.nodeCount, m.nodeCount)
        val stack = ArrayDeque<Pair<Int, Int>>().apply { add(0 to 0) }
        var seen = 0
        while (stack.isNotEmpty()) {
            val (na, nm) = stack.removeLast()
            seen++
            assertEquals(a.weight(na).toRawBits(), m.weight(nm).toRawBits())
            for (k in 0 until 26) {
                val ca = a.child(na, k); val cm = m.child(nm, k)
                assertEquals(ca < 0, cm < 0)
                if (ca >= 0) stack.add(ca to cm)
            }
        }
        assertEquals(a.nodeCount, seen)
    }

    @Test fun sharedUsesAssetAndGivesSamePriors() {
        val asset = TelexKeyPrior.fromAsset()
        assertNotNull("IME dùng asset (không dựng 31 MB rác)", asset)
        for (raw in listOf("", "t", "th", "ng", "ngh", "tie", "dd", "hel", "k", "uwow", "truwowngf", "qqq", "a".repeat(13))) {
            val p = ref.forRaw(raw); val q = asset!!.forRaw(raw)
            assertEquals(raw, p == null, q == null)
            if (p != null) for (c in 'a'..'z') assertEquals("$raw→$c", p(c), q!!(c))
        }
        TelexKeyPrior.release()
        val w = TelexKeyPrior.warmUp()
        assertTrue("warmUp mở asset mmap", w.trie::class.simpleName == "Mapped")
    }

    @Test fun rejectsBadBlob() {
        assertNull(KeyTrie.mapped(ByteBuffer.wrap(ByteArray(64))))
        val b = fresh(); b[4] = 9
        assertNull("sai phiên bản", KeyTrie.mapped(ByteBuffer.wrap(b)))
        assertNull("cụt", KeyTrie.mapped(ByteBuffer.wrap(fresh().copyOf(1000))))
    }
}
