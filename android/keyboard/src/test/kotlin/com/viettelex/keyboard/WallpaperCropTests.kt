package com.viettelex.keyboard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Khung cắt ảnh nền (trình chỉnh kéo/zoom): chuẩn hoá ↔ px, ràng buộc phủ kín, suy khung
 * ngang, mặc định ảnh cũ, IME giải đúng vùng cắt, RAM giải ≤ trước. Cùng số với iOS
 * KeyboardTests/WallpaperCropTests.swift.
 */
class WallpaperCropTests {
    private val acc = 1e-9

    @Test fun coverTouchesTheRightEdges() {
        // Ảnh 4000×3000 (1.33), khung 1.2 hẹp hơn ⇒ chạm trên-dưới.
        val c = WallpaperCrop.cover(4000, 3000, 1.2)
        assertEquals(1.0, c.h, acc)
        assertEquals(3000 * 1.2 / 4000, c.w, acc)
        assertEquals(0.5, c.centerX, acc)
        assertEquals(1.2, c.aspect(4000, 3000), acc)
        // Khung 1.608 rộng hơn ảnh ⇒ chạm trái-phải.
        assertEquals(1.0, WallpaperCrop.cover(4000, 3000, 1.608).w, acc)
        // Ảnh dọc
        val p = WallpaperCrop.cover(1536, 2048, 1.5)
        assertEquals(1.0, p.w, acc)
        assertEquals(1536 / 1.5 / 2048, p.h, acc)
    }

    @Test fun coverConstraintAndClamp() {
        val z = WallpaperCrop.make(2000, 1000, 1.5, 0.3, 0.5, 0.5)
        assertEquals(WallpaperCrop.cover(2000, 1000, 1.5), z)
        val far = WallpaperCrop.make(2000, 1000, 1.5, 2.0, -3.0, 9.0)
        assertEquals(0.0, far.x, acc)
        assertEquals(1.0, far.y + far.h, acc)
        val big = WallpaperCrop.make(2000, 1000, 1.5, 99.0, 0.5, 0.5)
        assertEquals(WallpaperCrop.MAX_ZOOM, big.zoom(2000, 1000), 1e-9)
        val nan = WallpaperCrop.make(2000, 1000, 1.5, Double.NaN, Double.NaN, 0.5)
        assertEquals(WallpaperCrop.cover(2000, 1000, 1.5), nan)
        for (c in listOf(z, far, big)) {
            assertTrue(c.x >= -acc && c.y >= -acc && c.x + c.w <= 1 + acc && c.y + c.h <= 1 + acc)
            assertEquals(1.5, c.aspect(2000, 1000), 1e-9)
        }
    }

    @Test fun normalizedPixelRoundTrip() {
        val c = WallpaperCrop.make(2048, 1536, 1.4, 1.7, 0.3, 0.6)
        val r = c.pixelRect(2048, 1536)
        assertEquals(Math.round(c.x * 2048).toInt(), r[0])
        assertEquals(1.4, (r[2] - r[0]).toDouble() / (r[3] - r[1]), 0.01)
        val back = WallpaperCrop.fromPixelRect(r, 2048, 1536)
        assertEquals(c.x, back.x, 1.0 / 2048)
        assertEquals(c.w, back.w, 1.0 / 2048)
        // Cùng khung trên bản gốc cỡ khác (ảnh cũ 1080) = cùng vùng.
        val small = c.pixelRect(1024, 768)
        assertEquals(r[0].toDouble(), small[0] * 2.0, 2.0)
        assertArrayEquals(intArrayOf(9, 9, 10, 10), WallpaperCrop(0.9999, 0.9999, 0.00001, 0.00001).pixelRect(10, 10))
    }

    @Test fun landscapeDerivation() {
        val p = WallpaperCrop.make(3000, 2000, 1.4, 1.3, 0.4, 0.45)
        val l = p.landscape(3000, 2000, 4.0)
        assertEquals(p.centerX, l.centerX, acc)
        assertEquals(p.centerY, l.centerY, acc)
        assertEquals(p.w, l.w, acc)
        assertEquals(4.0, l.aspect(3000, 2000), 1e-9)
        assertTrue(l.y >= p.y && l.y + l.h <= p.y + p.h + acc)
        val narrow = p.landscape(3000, 2000, 1.0)
        assertEquals(p.h, narrow.h, acc)
        assertTrue(narrow.w < p.w)
    }

    @Test fun refitKeepsCenterAndZoom() {
        val c = WallpaperCrop.make(3000, 2000, 1.4, 2.0, 0.35, 0.55)
        val r = c.refit(3000, 2000, 1.2)
        assertEquals(c.centerX, r.centerX, 1e-9)
        assertEquals(c.centerY, r.centerY, 1e-9)
        assertEquals(2.0, r.zoom(3000, 2000), 1e-9)
        assertEquals(1.2, r.aspect(3000, 2000), 1e-9)
    }

    @Test fun serializationRoundTripAndRejectsGarbage() {
        val c = WallpaperCrop(0.125, 0.25, 0.5, 0.375)
        assertEquals("0.12500,0.25000,0.50000,0.37500", c.serialize())   // cùng chuỗi iOS
        assertEquals(c, WallpaperCrop.parse(c.serialize()))
        for (bad in listOf(null, "", "1,2,3", "a,b,c,d", "0,0,0,0.5", "0.6,0,0.6,0.5", "NaN,0,0.5,0.5", "-0.5,0,0.5,0.5"))
            assertNull(bad, WallpaperCrop.parse(bad))
    }

    /** Ảnh cũ: không khóa khung ⇒ null ⇒ cắt giữa; khôi phục giao diện giữ khung; round-trip. */
    @Test fun migrationDefaultAndPersistence() {
        val legacy = ThemeSettings.load(mapOf<String, Any>(Keys.WALLPAPER_ENABLED to true)::get)
        assertNull(legacy.crop)
        assertTrue(Keys.WALLPAPER_CROP !in legacy.toMap())
        val s = legacy.copy(crop = WallpaperCrop(0.1, 0.2, 0.5, 0.3))
        val m = s.toMap()
        assertEquals(s, ThemeSettings.load { m[it] })
        assertEquals(s.crop, s.resetToDefaults().crop)
        assertTrue(s.resetToDefaults().isDefault)
        // Không khung ⇒ IME giải như cũ (cắt giữa cả ảnh)
        assertArrayEquals(WallpaperMath.visibleCrop(810, 1080, 1080, 780),
            WallpaperMath.decodePlan(810, 1080, 1080, 780).copyOf(4))
    }

    /** Pipeline nướng + kế hoạch giải của IME = đúng vùng khung (dọc) / dải giữa (ngang). */
    @Test fun keyboardDecodeUsesCrop() {
        val iw = 1536; val ih = 2048
        val view = 1080 to 780                         // vùng bàn phím dọc (px)
        val a = view.first.toDouble() / view.second
        val crop = WallpaperCrop.make(iw, ih, a, 1.6, 0.5, 0.0)    // phóng to, kéo lên đỉnh
        val r = crop.pixelRect(iw, ih)
        val (bw, bh) = WallpaperMath.bakedSize(iw, ih, crop)
        assertTrue(maxOf(bw, bh) <= WallpaperMath.MAX_EDGE)
        assertEquals(a, bw.toDouble() / bh, 0.01)
        // Dọc: IME giải (gần) cả file đã nướng = đúng vùng khung trong ảnh gốc
        val plan = WallpaperMath.decodePlan(bw, bh, view.first, view.second)
        assertTrue(plan[0] <= 1 && plan[1] <= 1 && plan[2] >= bw - 1 && plan[3] >= bh - 1)
        // Ngang: IME cắt giữa file đã nướng = khung ngang suy từ khung dọc
        val land = 2340 to 640
        val lp = WallpaperMath.decodePlan(bw, bh, land.first, land.second)
        val l = crop.landscape(iw, ih, land.first.toDouble() / land.second)
        val k = bw.toDouble() / (r[2] - r[0])           // px nướng / px gốc
        val lr = l.pixelRect(iw, ih)
        assertEquals((lr[1] - r[1]) * k, lp[1].toDouble(), 2.0)
        assertEquals((lr[3] - r[1]) * k, lp[3].toDouble(), 2.0)
        assertEquals(0, lp[0]); assertEquals(bw, lp[2])
    }

    /**
     * RAM: số điểm ảnh IME giải (vùng / sample²). Khung mặc định (zoom 1) = đúng như cũ (file cả
     * ảnh ≤1080, cắt giữa) cho cả dọc lẫn ngang; zoom bất kỳ ≤ trần cũ (1080×1080).
     */
    @Test fun decodeRamNotAboveBefore() {
        fun px(p: IntArray) = ((p[2] - p[0]) / p[4]).toLong() * ((p[3] - p[1]) / p[4])
        for ((iw, ih) in listOf(1536 to 2048, 2048 to 1536, 2048 to 946, 4000 to 3000, 800 to 600)) {
            for ((vw, vh) in listOf(1080 to 780, 1440 to 1000, 720 to 560)) {
                val (ow, oh) = WallpaperMath.targetSize(iw, ih)              // cũ: cả ảnh ≤1080
                val crop = WallpaperCrop.cover(iw, ih, vw.toDouble() / vh)   // mới: vùng khung
                val (bw, bh) = WallpaperMath.bakedSize(iw, ih, crop)
                for ((qw, qh) in listOf(vw to vh, 2340 to 640)) {             // dọc + ngang
                    val old = px(WallpaperMath.decodePlan(ow, oh, qw, qh))
                    val new = px(WallpaperMath.decodePlan(bw, bh, qw, qh))
                    // ±1 px làm tròn mỗi cạnh
                    assertTrue("$iw×$ih on $qw×$qh: $new > $old", new <= old + 2L * (ow + oh))
                }
                for (z in listOf(1.5, 3.0, WallpaperCrop.MAX_ZOOM)) {
                    val zc = WallpaperCrop.make(iw, ih, vw.toDouble() / vh, z, 0.3, 0.7)
                    val (zw, zh) = WallpaperMath.bakedSize(iw, ih, zc)
                    assertTrue(maxOf(zw, zh) <= WallpaperMath.MAX_EDGE)
                    assertTrue(px(WallpaperMath.decodePlan(zw, zh, vw, vh)) <= 1080L * 1080)
                }
            }
        }
    }

    @Test fun portraitSizeParsingAndEstimate() {
        assertEquals(1080 to 870, WallpaperMath.parseSize("1080x870"))
        for (bad in listOf(null, "", "0x5", "axb", "10x", "99999x5")) assertNull(WallpaperMath.parseSize(bad))
        // 224 dp + strip 34 dp @2.625 + nav 63 px
        assertEquals(1080 to Math.round(258 * 2.625f + 63), WallpaperMath.estimatePortraitPx(1080, 2.625f, 224f, 34f, 63))
    }
}
