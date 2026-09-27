package com.viettelex.keyboard

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/*
 * SwipeDecoder.kt — LÕI GIẢI MÃ GÕ VUỐT (swipe/glide typing) tiếng Việt, phần THUẦN
 * (không View, không MotionEvent). Song sinh của iOS/Keyboard/SwipeDecoder.swift —
 * sửa thuật toán/hằng số ở đây thì sửa y hệt bên kia (test parity dùng chung fixture
 * iOS/KeyboardTests/Fixtures/swipe-paths.txt so top-1 hai bản).
 *
 * Người dùng vuốt theo chữ KHÔNG DẤU ("viet") → [SwipeDecoder.decode] trả dạng không dấu
 * top-K; [SwipeDecoder.expand] bung thành âm tiết có dấu (việt, viết…) theo tần suất
 * lexicon (+ điểm ngữ cảnh caller cấp).
 *
 * Thuật toán kiểu SHARK2 (Kristensson & Zhai 2004) như FlorisBoard
 * StatisticalGlideTypingClassifier: template = đường nối tâm phím (gộp chữ lặp) theo
 * LAYOUT THẬT; resample N điểm cách đều; shape channel (dời trọng tâm, chia cạnh lớn
 * bbox, sàn 1 phím) + location channel (đơn vị phím, α nặng 2 đầu, đường hầm 0.25 phím);
 * Gaussian log-prob + λ·tần suất; lọc phím đầu/cuối ≤ 1.6 phím (thiếu thì 3.2); kênh độ
 * dài; TẦNG 2 trên top-16: σ location thích nghi (nét cẩu thả ⇒ σ_L tới ×1.5), căn phím
 * đơn điệu vào đường 48 điểm, góc gắt của đường phải gần phím ứng viên. Lệch tay cá nhân
 * [SwipeDecoder.offsetX]/[SwipeDecoder.offsetY] học online bằng [SwipeDecoder.learnOffset].
 * Mọi phép tính Float32 cùng thứ tự với bản Swift → cùng điểm trên cùng input.
 *
 * Bộ nhớ: lười — không đọc lexicon/dựng template tới lần decode đầu (hoặc [prepare]).
 * Template ≈ 1666 × 24 × 2 Float ≈ 320 KB. Không cấp phát trong vòng chấm điểm.
 * KHÔNG thread-safe: gọi từ một luồng.
 */

/** Tâm phím a…z theo toạ độ thật (cùng hệ với đường vuốt). Đổi layout → setLayout lại. */
class SwipeLayout(
    /** Bước phím ngang (tâm-tới-tâm) — đơn vị chuẩn hoá mọi khoảng cách. */
    val keyWidth: Float,
    centers: Map<Char, Pair<Float, Float>>,
) {
    /** 52 số: (x, y) của 'a'…'z'; +∞ = không có phím. */
    val centers: FloatArray = FloatArray(52) { Float.POSITIVE_INFINITY }

    init {
        require(keyWidth > 0f) { "keyWidth phải > 0" }
        for ((ch, p) in centers) {
            if (ch !in 'a'..'z') continue
            this.centers[(ch - 'a') * 2] = p.first
            this.centers[(ch - 'a') * 2 + 1] = p.second
        }
    }

    fun center(ch: Char): Pair<Float, Float>? {
        if (ch !in 'a'..'z') return null
        val x = centers[(ch - 'a') * 2]
        return if (x.isFinite()) x to centers[(ch - 'a') * 2 + 1] else null
    }

    override fun equals(other: Any?): Boolean =
        other is SwipeLayout && other.keyWidth == keyWidth && other.centers.contentEquals(centers)

    override fun hashCode(): Int = 31 * keyWidth.hashCode() + centers.contentHashCode()

    companion object {
        /** QWERTY chuẩn (hàng 2 lệch 0.5 phím, hàng 3 lệch 1.5 phím). */
        fun qwerty(keyWidth: Float, rowHeight: Float, originX: Float = 0f, originY: Float = 0f): SwipeLayout {
            val m = HashMap<Char, Pair<Float, Float>>()
            val rows = listOf("qwertyuiop" to 0.5f, "asdfghjkl" to 1.0f, "zxcvbnm" to 2.0f)
            for ((r, rowPair) in rows.withIndex()) {
                val (row, x0) = rowPair
                for ((i, ch) in row.withIndex()) {
                    m[ch] = (originX + (x0 + i.toFloat()) * keyWidth) to
                        (originY + (r.toFloat() + 0.5f) * rowHeight)
                }
            }
            return SwipeLayout(keyWidth, m)
        }
    }
}

/**
 * Bộ đệm điểm vuốt cấp sẵn (cùng hành vi bản Swift). Chỉ nhận điểm cách điểm trước
 * ≥ [minDistance] (khuyên 1/6–1/4 phím); điểm nhấc tay thêm bằng `force = true`.
 * Đầy thì điểm mới ghi đè điểm cuối.
 */
class SwipePath(val minDistance: Float, val capacity: Int = 256) {
    init { require(capacity >= 2) }
    val xs = FloatArray(capacity)
    val ys = FloatArray(capacity)
    val ts = DoubleArray(capacity)
    var count = 0; private set
    var length = 0f; private set

    fun reset() { count = 0; length = 0f }

    fun add(x: Float, y: Float, t: Double, force: Boolean = false): Boolean {
        if (count > 0) {
            val dx = x - xs[count - 1]; val dy = y - ys[count - 1]
            val d = sqrt(dx * dx + dy * dy)
            if (!force && d < minDistance) return false
            if (force && d == 0f) { ts[count - 1] = t; return true }
            if (count == capacity) {
                val px = xs[count - 2]; val py = ys[count - 2]
                val ox = xs[count - 1] - px; val oy = ys[count - 1] - py
                val nx = x - px; val ny = y - py
                length += sqrt(nx * nx + ny * ny) - sqrt(ox * ox + oy * oy)
                xs[count - 1] = x; ys[count - 1] = y; ts[count - 1] = t
                return true
            }
            length += d
        }
        xs[count] = x; ys[count] = y; ts[count] = t
        count++
        return true
    }

    /** Thời lượng vuốt (giây). */
    val duration: Double get() = if (count > 1) ts[count - 1] - ts[0] else 0.0
}

/** [folded] = dạng không dấu (VI) hoặc từ tiếng Anh nguyên văn (EN, giai đoạn 3). */
data class SwipeCandidate(val folded: String, val score: Float, val lang: SwipeLang = SwipeLang.VI)
data class SwipeWord(val word: String, val score: Float)

/** 1666 dạng không dấu rút từ vnlexicon.bin — mỗi dạng là một dải id liên tiếp. */
object SwipeLexicon {
    class Forms(
        val folded: Array<String>,
        val idStart: IntArray,   // dải id dạng f: idStart[f] until idStart[f+1]
        val freq: IntArray,      // 0-255, entry mạnh nhất
        val keys: ByteArray,     // phím đã gộp chữ lặp (0…25)
        val keyStart: IntArray,
    ) { val count: Int get() = folded.size }

    val forms: Forms by lazy { build() }

    private fun build(): Forms {
        val b = VNLexicon2Data.blob
        val n = VNLexicon2Data.count
        val folded = ArrayList<String>(1700)
        val idStart = IntArray(n + 1)
        val freq = IntArray(n)
        val keys = ByteArray(b.offsets[n])
        val keyStart = IntArray(n + 1)
        var fc = 0; var kc = 0
        var prevLo = -1; var prevHi = -1
        for (id in 0 until n) {
            val lo = b.offsets[id]; val hi = b.offsets[id + 1]
            if (prevLo >= 0 && hi - lo == prevHi - prevLo &&
                (0 until hi - lo).all { b.foldedByte(lo + it) == b.foldedByte(prevLo + it) }) continue
            prevLo = lo; prevHi = hi
            val sb = StringBuilder(hi - lo)
            var last = -1
            for (i in lo until hi) {
                val c = b.foldedByte(i)
                sb.append(c.toChar())
                val k = c - 97
                if (k != last) { keys[kc++] = k.toByte(); last = k }
            }
            folded.add(sb.toString())
            idStart[fc] = id
            freq[fc] = b.freq(id)
            fc++
            keyStart[fc] = kc
        }
        idStart[fc] = n
        return Forms(folded.toTypedArray(), idStart.copyOf(fc + 1), freq.copyOf(fc),
            keys.copyOf(kc), keyStart.copyOf(fc + 1))
    }

    /** Chỉ số dạng [folded] (binary search ASCII), -1 nếu không có. */
    fun indexOf(folded: String): Int {
        val a = forms.folded
        var lo = 0; var hi = a.size
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (a[mid] < folded) lo = mid + 1 else hi = mid
        }
        return if (lo < a.size && a[lo] == folded) lo else -1
    }
}

class SwipeDecoder(val params: Params = Params()) {
    /** Hằng số mô hình — GIỮ Y HỆT bản Swift. */
    data class Params(
        val points: Int = 24,
        val sigmaShape: Float = 0.2f,
        val sigmaLoc: Float = 0.2f,
        val lambdaFreq: Float = 2.5f,
        val tunnel: Float = 0.25f,
        val endWeight: Float = 8f,
        val endSpan: Float = 0.15f,
        val filterRadius: Float = 1.6f,
        val contextPool: Int = 16,
        /** Kênh độ dài: −w·ln²((dài đường+1)/(dài template+1)), đơn vị phím ([lengthPenalty]). */
        val lengthWeight: Float = 2f,
        /** Chấm lại (tầng 2) top-[rescorePool] hình học; 0 = tắt cả tầng 2 + σ thích nghi. */
        val rescorePool: Int = 16,
        /** Điểm resample của tầng 2 (căn phím + góc). */
        val rescorePoints: Int = 48,
        /** Căn phím template vào đường (đơn điệu): −w·trung bình d² (phím, trừ tunnel). */
        val alignWeight: Float = 1f,
        /** Mỗi GÓC gắt trên đường phải gần một phím của ứng viên: −w·Σ d². */
        val cornerWeight: Float = 3f,
        val cornerDegrees: Float = 55f,
        val rescoreTunnel: Float = 0.25f,
        /**
         * σ location thích nghi: nét cẩu thả (location tốt nhất > ngưỡng, phím) ⇒ σ_L nhân
         * tới [adaptMax] — tin tần suất/ngữ cảnh hơn (kiểu SHARK2 nới σ theo tốc độ).
         */
        val adaptThreshold: Float = 0.13f,
        val adaptMax: Float = 1.5f,
        /** Học lệch tay cá nhân ([learnOffset]): tốc độ EMA, trần mỗi lần (phím). */
        val offsetRate: Float = 0.05f,
        val offsetCap: Float = 0.5f,
    )

    var layout: SwipeLayout? = null; private set

    private var tpl = FloatArray(0)
    private var tplCX = FloatArray(0)
    private var tplCY = FloatArray(0)
    private var tplScale = FloatArray(0)
    private var tplValid = BooleanArray(0)
    private val alpha: FloatArray
    private val alphaSum: Float
    private val ux: FloatArray
    private val uy: FloatArray
    private val sx: FloatArray
    private val sy: FloatArray
    private var topScore = FloatArray(0)
    private var topIdx = IntArray(0)
    private var topDl = FloatArray(0)
    private var tplLen = FloatArray(0)
    // tầng 2 + học lệch
    private val mx: FloatArray
    private val my: FloatArray
    private val dp: FloatArray
    private val back: IntArray
    private val corners: IntArray
    private var cornerCount = 0
    private val rkx = FloatArray(32)
    private val rky = FloatArray(32)
    private var bx = FloatArray(0)
    private var by = FloatArray(0)
    private val cosCorner: Float

    /**
     * Lệch tay hệ thống của người dùng (đơn vị bề rộng phím; + = phải/xuống), trừ khỏi
     * đường vuốt trước khi chấm. Học bằng [learnOffset]; caller lưu/khôi phục.
     */
    var offsetX = 0f
    var offsetY = 0f
    private var filled = 0
    private val frame = FloatArray(3)
    // template tiếng Anh dựng ngay lúc chấm (không giữ)
    private val ekx = FloatArray(32)
    private val eky = FloatArray(32)
    private val erx: FloatArray
    private val ery: FloatArray
    private val eframe = FloatArray(3)
    private val okFirst = BooleanArray(26)
    private val okLast = BooleanArray(26)

    init {
        val n = params.points
        require(n >= 2)
        alpha = FloatArray(n)
        var s = 0f
        for (i in 0 until n) {
            val edge = min(i, n - 1 - i).toFloat() / (n.toFloat() * params.endSpan)
            alpha[i] = 1f + params.endWeight * max(0f, 1f - edge)
            s += alpha[i]
        }
        alphaSum = s
        ux = FloatArray(n); uy = FloatArray(n); sx = FloatArray(n); sy = FloatArray(n)
        erx = FloatArray(n); ery = FloatArray(n)
        val m2 = max(2, params.rescorePoints)
        mx = FloatArray(m2); my = FloatArray(m2); dp = FloatArray(32 * m2); back = IntArray(32 * m2)
        corners = IntArray(m2)
        cosCorner = kotlin.math.cos(params.cornerDegrees.toDouble() * Math.PI / 180.0).toFloat()
    }

    /** Đặt layout; khác layout cũ thì bỏ template (dựng lại lười). */
    fun setLayout(l: SwipeLayout) {
        if (l == layout) return
        layout = l
        tpl = FloatArray(0); tplCX = tpl; tplCY = tpl; tplScale = tpl; tplLen = tpl
        tplValid = BooleanArray(0)
    }

    /** Dựng template ngay (background khi bàn phím hiện). */
    fun prepare() {
        val l = layout ?: return
        if (tpl.isEmpty()) buildTemplates(l)
    }

    val templateBytes: Int
        get() = tpl.size * 4 + (tplCX.size + tplCY.size + tplScale.size + tplLen.size) * 4 + tplValid.size

    private fun buildTemplates(l: SwipeLayout) {
        val forms = SwipeLexicon.forms
        val n = params.points; val fc = forms.count
        tpl = FloatArray(fc * n * 2)
        tplCX = FloatArray(fc); tplCY = FloatArray(fc); tplScale = FloatArray(fc); tplLen = FloatArray(fc)
        tplValid = BooleanArray(fc)
        val kx = FloatArray(32); val ky = FloatArray(32)
        val rx = FloatArray(n); val ry = FloatArray(n)
        for (f in 0 until fc) {
            val lo = forms.keyStart[f]; val hi = forms.keyStart[f + 1]
            var ok = hi - lo <= kx.size
            var m = 0
            if (ok) {
                for (j in lo until hi) {
                    val k = forms.keys[j].toInt()
                    if (k !in 0 until 26) { ok = false; break }
                    val x = l.centers[k * 2]; val y = l.centers[k * 2 + 1]
                    if (!x.isFinite()) { ok = false; break }
                    kx[m] = x; ky[m] = y; m++
                }
            }
            if (!ok || m == 0) continue
            resample(kx, ky, m, n, rx, ry)
            val base = f * n * 2
            for (i in 0 until n) { tpl[base + i * 2] = rx[i]; tpl[base + i * 2 + 1] = ry[i] }
            shapeFrame(rx, ry, n, l.keyWidth, frame)
            tplCX[f] = frame[0]; tplCY[f] = frame[1]; tplScale[f] = frame[2]
            tplLen[f] = keyPathLength(kx, ky, m, l.keyWidth)
            tplValid[f] = true
        }
    }

    /** Giải mã → top-K dạng không dấu (điểm giảm dần); [context] cộng điểm ngữ cảnh. */
    fun decode(path: SwipePath, topK: Int = 5, context: ((String) -> Float)? = null): List<SwipeCandidate> =
        decodeCore(path.xs, path.ys, path.count, topK, context, null, null)

    fun decode(
        xs: FloatArray, ys: FloatArray, count: Int, topK: Int = 5,
        context: ((String) -> Float)? = null,
    ): List<SwipeCandidate> = decodeCore(xs, ys, count, topK, context, null, null)

    /**
     * Giai đoạn 3 — [english] != null: thêm từ tiếng Anh vào cùng không gian ứng viên
     * (+bias), [englishContext] = điểm ngữ cảnh riêng của từ tiếng Anh; sau khi xếp áp
     * [arbitrate]. null ⇒ y hệt [decode] thường. (Overload riêng để lambda đuôi
     * `decode(p, k) { … }` vẫn là [context].)
     */
    fun decode(
        path: SwipePath, topK: Int, context: ((String) -> Float)?,
        english: SwipeEnglishPrior?, englishContext: ((String) -> Float)? = null,
    ): List<SwipeCandidate> = decodeCore(path.xs, path.ys, path.count, topK, context, english, englishContext)

    fun decode(
        xs: FloatArray, ys: FloatArray, count: Int, topK: Int, context: ((String) -> Float)?,
        english: SwipeEnglishPrior?, englishContext: ((String) -> Float)? = null,
    ): List<SwipeCandidate> = decodeCore(xs, ys, count, topK, context, english, englishContext)

    private fun decodeCore(
        xs0: FloatArray, ys0: FloatArray, count: Int, topK: Int,
        context: ((String) -> Float)?,
        english: SwipeEnglishPrior?,
        englishContext: ((String) -> Float)?,
    ): List<SwipeCandidate> {
        val l = layout
        if (count <= 0 || topK <= 0 || l == null) return emptyList()
        if (tpl.isEmpty()) buildTemplates(l)
        val forms = SwipeLexicon.forms
        val en = if (english == null) null else SwipeEnglish.lexicon
        val fc = forms.count
        val n = params.points; val w = l.keyWidth
        val (xs, ys) = shifted(xs0, ys0, count, w)
        resample(xs, ys, count, n, ux, uy)
        val pathLen = keyPathLength(xs, ys, count, w)
        shapeFrame(ux, uy, n, w, frame)
        val ucx = frame[0]; val ucy = frame[1]; val us = frame[2]
        for (i in 0 until n) { sx[i] = (ux[i] - ucx) * us; sy[i] = (uy[i] - ucy) * us }

        var m = if (context == null && english == null) topK else max(topK, params.contextPool)
        if (params.rescorePool > 0) m = max(m, params.rescorePool)
        if (topScore.size < m) { topScore = FloatArray(m); topIdx = IntArray(m); topDl = FloatArray(m) }
        val tunnelW = params.tunnel * w
        val invS = 1f / (2f * params.sigmaShape * params.sigmaShape)
        val invL = 1f / (2f * params.sigmaLoc * params.sigmaLoc)
        val lam = params.lambdaFreq
        val lw = params.lengthWeight
        val t = tpl; val a = alpha

        for (pass in 0 until 2) {
            val r = params.filterRadius * w * (if (pass == 0) 1f else 2f)
            val r2 = r * r
            filled = 0
            for (f in 0 until forms.count) {
                if (!tplValid[f]) continue
                val base = f * n * 2
                var dx = ux[0] - t[base]; var dy = uy[0] - t[base + 1]
                if (dx * dx + dy * dy > r2) continue
                dx = ux[n - 1] - t[base + (n - 1) * 2]
                dy = uy[n - 1] - t[base + (n - 1) * 2 + 1]
                if (dx * dx + dy * dy > r2) continue
                val cx = tplCX[f]; val cy = tplCY[f]; val sc = tplScale[f]
                var ds = 0f; var dl = 0f
                for (i in 0 until n) {
                    val tx = t[base + i * 2]; val ty = t[base + i * 2 + 1]
                    val ex = sx[i] - (tx - cx) * sc; val ey = sy[i] - (ty - cy) * sc
                    ds += sqrt(ex * ex + ey * ey)
                    val lx = ux[i] - tx; val ly = uy[i] - ty
                    val d = sqrt(lx * lx + ly * ly) - tunnelW
                    if (d > 0f) dl += a[i] * d
                }
                ds = ds / n.toFloat()
                dl = dl / alphaSum / w
                var score = -(ds * ds) * invS - (dl * dl) * invL + lam * forms.freq[f].toFloat() / 255f
                if (lw > 0f) score -= lw * lengthPenalty(pathLen, tplLen[f])
                insertTop(score, f, dl, m)
            }
            if (en != null && english != null) scoreEnglish(en, english.bias, l, r2, m, fc, pathLen)
            if (filled >= topK) break
        }
        if (params.rescorePool > 0 && filled > 0) rescore(xs, ys, count, l, invL, en, fc)

        val out = ArrayList<SwipeCandidate>(filled)
        for (k in 0 until filled) {
            val f = topIdx[k]
            var s = topScore[k]
            if (f >= fc && en != null) {
                val word = en.words[f - fc]
                if (englishContext != null) s += englishContext(word)
                out.add(SwipeCandidate(word, s, SwipeLang.EN))
                continue
            }
            if (context != null) s += context(forms.folded[f])
            out.add(SwipeCandidate(forms.folded[f], s))
        }
        // sortedByDescending ổn định: bằng điểm giữ thứ tự hình học
        val sorted = if (context != null || englishContext != null) out.sortedByDescending { it.score } else out
        if (english != null) return arbitrate(sorted, topK, english.margin)
        return sorted.take(topK)
    }

    /** Chấm từ tiếng Anh lọt lọc phím đầu/cuối (theo cặp phím, thứ tự cố định — parity Swift). */
    private fun scoreEnglish(en: SwipeEnglish.Lexicon, bias: Float, l: SwipeLayout, r2: Float, m: Int, fc: Int,
                             pathLen: Float) {
        val n = params.points; val w = l.keyWidth
        val tunnelW = params.tunnel * w
        val invS = 1f / (2f * params.sigmaShape * params.sigmaShape)
        val invL = 1f / (2f * params.sigmaLoc * params.sigmaLoc)
        val lam = params.lambdaFreq
        val a = alpha
        for (k in 0 until 26) {
            val x = l.centers[k * 2]; val y = l.centers[k * 2 + 1]
            if (!x.isFinite()) { okFirst[k] = false; okLast[k] = false; continue }
            var dx = ux[0] - x; var dy = uy[0] - y
            okFirst[k] = dx * dx + dy * dy <= r2
            dx = ux[n - 1] - x; dy = uy[n - 1] - y
            okLast[k] = dx * dx + dy * dy <= r2
        }
        for (fa in 0 until 26) {
            if (!okFirst[fa]) continue
            for (lb in 0 until 26) {
                if (!okLast[lb]) continue
                val bk = fa * 26 + lb
                for (o in en.bucketStart[bk] until en.bucketStart[bk + 1]) {
                    val i = en.order[o]
                    val lo = en.keyStart[i]; val hi = en.keyStart[i + 1]
                    if (hi - lo > ekx.size) continue
                    var mk = 0; var ok = true
                    for (j in lo until hi) {
                        val k = en.keys[j].toInt()
                        val x = l.centers[k * 2]
                        if (!x.isFinite()) { ok = false; break }
                        ekx[mk] = x; eky[mk] = l.centers[k * 2 + 1]; mk++
                    }
                    if (!ok) continue
                    resample(ekx, eky, mk, n, erx, ery)
                    shapeFrame(erx, ery, n, w, eframe)
                    val cx = eframe[0]; val cy = eframe[1]; val sc = eframe[2]
                    var ds = 0f; var dl = 0f
                    for (p in 0 until n) {
                        val tx = erx[p]; val ty = ery[p]
                        val ex = sx[p] - (tx - cx) * sc; val ey = sy[p] - (ty - cy) * sc
                        ds += sqrt(ex * ex + ey * ey)
                        val lx = ux[p] - tx; val ly = uy[p] - ty
                        val d = sqrt(lx * lx + ly * ly) - tunnelW
                        if (d > 0f) dl += a[p] * d
                    }
                    ds = ds / n.toFloat()
                    dl = dl / alphaSum / w
                    var score = -(ds * ds) * invS - (dl * dl) * invL +
                        lam * en.freq[i].toFloat() / 255f + bias
                    if (params.lengthWeight > 0f)
                        score -= params.lengthWeight * lengthPenalty(pathLen, keyPathLength(ekx, eky, mk, w))
                    insertTop(score, fc + i, dl, m)
                }
            }
        }
    }

    private fun insertTop(s: Float, idx: Int, dl: Float, m: Int) {
        if (filled == m && s <= topScore[m - 1]) return
        var pos = if (filled < m) filled else m - 1
        while (pos > 0 && topScore[pos - 1] < s) {
            topScore[pos] = topScore[pos - 1]; topIdx[pos] = topIdx[pos - 1]; topDl[pos] = topDl[pos - 1]; pos--
        }
        topScore[pos] = s; topIdx[pos] = idx; topDl[pos] = dl
        if (filled < m) filled++
    }

    /** Đường trừ lệch tay ([offsetX]/[offsetY]); không lệch ⇒ chính mảng gốc. */
    private fun shifted(xs: FloatArray, ys: FloatArray, count: Int, w: Float): Pair<FloatArray, FloatArray> {
        if (offsetX == 0f && offsetY == 0f) return xs to ys
        if (bx.size < count) { bx = FloatArray(max(count, 64)); by = FloatArray(max(count, 64)) }
        val ox = offsetX * w; val oy = offsetY * w
        for (i in 0 until count) { bx[i] = xs[i] - ox; by[i] = ys[i] - oy }
        return bx to by
    }

    /** Phím của ứng viên [idx] (< fc: dạng VN; ≥ fc: từ tiếng Anh) → rkx/rky; số phím, ≤ 0 = không dựng được. */
    private fun candidateKeys(idx: Int, l: SwipeLayout, en: SwipeEnglish.Lexicon?, fc: Int): Int {
        val keys: ByteArray; val lo: Int; val hi: Int
        if (idx < fc) {
            val forms = SwipeLexicon.forms
            keys = forms.keys; lo = forms.keyStart[idx]; hi = forms.keyStart[idx + 1]
        } else {
            if (en == null) return -1
            keys = en.keys; lo = en.keyStart[idx - fc]; hi = en.keyStart[idx - fc + 1]
        }
        if (hi - lo > rkx.size) return -1
        var k = 0
        for (j in lo until hi) {
            val c = keys[j].toInt()
            if (c !in 0 until 26) return -1
            val x = l.centers[c * 2]
            if (!x.isFinite()) return -1
            rkx[k] = x; rky[k] = l.centers[c * 2 + 1]; k++
        }
        return k
    }

    /**
     * Tầng 2 trên top-[filled]: σ location thích nghi (theo location tốt nhất), rồi trừ
     * chi phí căn phím + góc; xếp lại ổn định (bằng điểm giữ thứ tự cũ).
     */
    private fun rescore(xs: FloatArray, ys: FloatArray, count: Int, l: SwipeLayout, invL: Float,
                        en: SwipeEnglish.Lexicon?, fc: Int) {
        val w = l.keyWidth
        if (params.adaptThreshold > 0f && params.adaptMax > 1f) {
            var best = Float.MAX_VALUE
            for (k in 0 until filled) if (topDl[k] < best) best = topDl[k]
            var kk = best / params.adaptThreshold
            if (kk > params.adaptMax) kk = params.adaptMax
            if (kk > 1f) {
                val gain = invL * (1f - 1f / (kk * kk))
                for (k in 0 until filled) topScore[k] += topDl[k] * topDl[k] * gain
            }
        }
        resample(xs, ys, count, mx.size, mx, my)
        detectCorners(w)
        val t = params.rescoreTunnel * w
        for (k in 0 until filled) {
            val km = candidateKeys(topIdx[k], l, en, fc)
            if (km <= 0) continue
            var cost = 0f
            if (params.alignWeight > 0f) cost += params.alignWeight * alignCost(km, t, w)
            if (params.cornerWeight > 0f && cornerCount > 0) {
                var c = 0f
                for (q in 0 until cornerCount) c += nearestKeyCost(mx[corners[q]], my[corners[q]], km, t, w)
                cost += params.cornerWeight * c
            }
            topScore[k] -= cost
        }
        // insertion sort ổn định, giảm dần
        for (i in 1 until filled) {
            val s = topScore[i]; val id = topIdx[i]; val d = topDl[i]
            var j = i
            while (j > 0 && topScore[j - 1] < s) {
                topScore[j] = topScore[j - 1]; topIdx[j] = topIdx[j - 1]; topDl[j] = topDl[j - 1]; j--
            }
            topScore[j] = s; topIdx[j] = id; topDl[j] = d
        }
    }

    /** Góc gắt trên đường resample tầng 2 (cos góc rẽ < cos[Params.cornerDegrees]). */
    private fun detectCorners(w: Float) {
        cornerCount = 0
        if (params.cornerWeight <= 0f) return
        val m2 = mx.size; val g = 2; val minLen = 0.15f * w
        for (i in g until m2 - g) {
            val c = turnCos(i, g, minLen)
            if (c >= cosCorner) continue
            if (cornerCount > 0 && i - corners[cornerCount - 1] <= g) {
                if (c < turnCos(corners[cornerCount - 1], g, minLen)) corners[cornerCount - 1] = i
            } else {
                corners[cornerCount++] = i
            }
        }
    }

    /** cos góc rẽ tại điểm i (cạnh ±g điểm); cạnh < minLen ⇒ 1 (không tính là góc). */
    private fun turnCos(i: Int, g: Int, minLen: Float): Float {
        val ax = mx[i] - mx[i - g]; val ay = my[i] - my[i - g]
        val bx = mx[i + g] - mx[i]; val by = my[i + g] - my[i]
        val la = sqrt(ax * ax + ay * ay); val lb = sqrt(bx * bx + by * by)
        if (la < minLen || lb < minLen) return 1f
        return (ax * bx + ay * by) / (la * lb)
    }

    /** (khoảng cách tới phím gần nhất của ứng viên − tunnel)², đơn vị phím. */
    private fun nearestKeyCost(x: Float, y: Float, km: Int, t: Float, w: Float): Float {
        var best = Float.MAX_VALUE
        for (j in 0 until km) {
            val dx = x - rkx[j]; val dy = y - rky[j]
            var d = (sqrt(dx * dx + dy * dy) - t) / w
            if (d < 0f) d = 0f
            if (d < best) best = d
        }
        return best * best
    }

    /** Căn đơn điệu km phím (rkx/rky) vào mx/my: trung bình (d − tunnel)² nhỏ nhất (phím). */
    private fun alignCost(km: Int, t: Float, w: Float): Float {
        val m2 = mx.size
        for (j in 0 until km) {
            var run = Float.MAX_VALUE
            for (i in 0 until m2) {
                val dx = mx[i] - rkx[j]; val dy = my[i] - rky[j]
                var d = (sqrt(dx * dx + dy * dy) - t) / w
                if (d < 0f) d = 0f
                var prev = 0f
                if (j > 0) { val v = dp[(j - 1) * m2 + i]; if (v < run) run = v; prev = run }
                dp[j * m2 + i] = d * d + prev
            }
        }
        var best = Float.MAX_VALUE
        for (i in 0 until m2) { val v = dp[(km - 1) * m2 + i]; if (v < best) best = v }
        return best / km.toFloat()
    }

    /**
     * Học lệch tay từ một lượt vuốt người dùng ĐÃ CHẤP NHẬN là dạng [folded] (không dấu,
     * có trong lexicon): căn phím vào đường (đã trừ lệch hiện tại), lệch trung bình (kẹp
     * ±[Params.offsetCap] phím) → EMA [Params.offsetRate] vào [offsetX]/[offsetY].
     * false = không học (chưa có layout / dạng lạ / đường < 2 điểm).
     */
    fun learnOffset(xs0: FloatArray, ys0: FloatArray, count: Int, folded: String): Boolean {
        val l = layout ?: return false
        if (count < 2 || params.offsetRate <= 0f) return false
        val f = SwipeLexicon.indexOf(folded)
        if (f < 0) return false
        val km = candidateKeys(f, l, null, SwipeLexicon.forms.count)
        if (km <= 0) return false
        val w = l.keyWidth
        val (xs, ys) = shifted(xs0, ys0, count, w)
        val m2 = mx.size
        resample(xs, ys, count, m2, mx, my)
        for (j in 0 until km) {
            var run = Float.MAX_VALUE; var runI = 0
            for (i in 0 until m2) {
                val dx = mx[i] - rkx[j]; val dy = my[i] - rky[j]
                val d = sqrt(dx * dx + dy * dy) / w
                var prev = 0f
                if (j > 0) {
                    val v = dp[(j - 1) * m2 + i]
                    if (v < run) { run = v; runI = i }
                    prev = run; back[j * m2 + i] = runI
                }
                dp[j * m2 + i] = d * d + prev
            }
        }
        var bi = 0
        for (i in 1 until m2) if (dp[(km - 1) * m2 + i] < dp[(km - 1) * m2 + bi]) bi = i
        var sx = 0f; var sy = 0f
        var pos = bi
        for (j in km - 1 downTo 0) {
            sx += mx[pos] - rkx[j]; sy += my[pos] - rky[j]
            if (j > 0) pos = back[j * m2 + pos]
        }
        val cap = params.offsetCap
        val dx = (sx / km.toFloat() / w).coerceIn(-cap, cap)
        val dy = (sy / km.toFloat() / w).coerceIn(-cap, cap)
        offsetX += params.offsetRate * dx
        offsetY += params.offsetRate * dy
        return true
    }

    fun learnOffset(path: SwipePath, folded: String): Boolean = learnOffset(path.xs, path.ys, path.count, folded)

    companion object {
        /**
         * Phân xử ngôn ngữ trên danh sách đã xếp (port Swift `arbitrate`): top-1 tiếng Anh
         * mà có ứng viên Việt kém < [margin] ⇒ ứng viên Việt đó lên đầu; top-K thiếu ngôn
         * ngữ kia mà pool có ⇒ NỐI THÊM ứng viên tốt nhất của ngôn ngữ kia (kết quả có thể
         * dài topK+1 — không chiếm chỗ ứng viên cùng ngôn ngữ).
         */
        fun arbitrate(sorted: List<SwipeCandidate>, topK: Int, margin: Float): List<SwipeCandidate> {
            val out = sorted.toMutableList()
            val first = out.firstOrNull()
            if (first != null && first.lang == SwipeLang.EN && margin > 0f) {
                val j = out.indexOfFirst { it.lang == SwipeLang.VI && it.score > first.score - margin }
                if (j >= 0) out.add(0, out.removeAt(j))
            }
            val top = out.take(topK).toMutableList()
            val lead = top.firstOrNull()?.lang
            if (topK >= 2 && lead != null && top.none { it.lang != lead }) {
                val other = out.firstOrNull { it.lang != lead }
                if (other != null) top.add(other)
            }
            return top
        }

        /** Bung dạng không dấu → âm tiết có dấu, điểm = λ·tần suất/255 (+context), giảm dần. */
        fun expand(
            folded: String, limit: Int = 8, lambdaFreq: Float = Params().lambdaFreq,
            context: ((String) -> Float)? = null,
        ): List<SwipeWord> {
            if (limit <= 0) return emptyList()
            val f = SwipeLexicon.indexOf(folded)
            if (f < 0) return emptyList()
            val forms = SwipeLexicon.forms
            val b = VNLexicon2Data.blob
            val out = ArrayList<SwipeWord>()
            for (id in forms.idStart[f] until forms.idStart[f + 1]) {
                val w = VNSuggest.display(id)
                var s = lambdaFreq * b.freq(id).toFloat() / 255f
                if (context != null) s += context(w)
                out.add(SwipeWord(w, s))
            }
            // ổn định: bằng điểm giữ thứ tự lexicon (id tăng)
            return out.sortedByDescending { it.score }.take(limit)
        }

        /** Độ dài polyline (count điểm) theo đơn vị phím. */
        fun keyPathLength(xs: FloatArray, ys: FloatArray, count: Int, keyWidth: Float): Float {
            var s = 0f
            for (j in 0 until count - 1) {
                val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
                s += sqrt(dx * dx + dy * dy)
            }
            return s / keyWidth
        }

        /**
         * ≈ ln²((a+1)/(b+1)) bằng 2(a−b)/(a+b+2) (xấp xỉ Padé của ln, bão hoà ở ±2 khi
         * lệch lớn) — thuần + − × ÷ nên Swift/Kotlin ra cùng bit.
         */
        fun lengthPenalty(a: Float, b: Float): Float {
            val r = 2f * (a - b) / (a + b + 2f)
            return r * r
        }

        /** Resample polyline (count điểm) thành n điểm cách đều theo độ dài. */
        fun resample(xs: FloatArray, ys: FloatArray, count: Int, n: Int, ox: FloatArray, oy: FloatArray) {
            var total = 0f
            if (count > 1) {
                for (j in 0 until count - 1) {
                    val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
                    total += sqrt(dx * dx + dy * dy)
                }
            }
            if (count == 1 || total <= 1e-4f) {
                for (k in 0 until n) { ox[k] = xs[0]; oy[k] = ys[0] }
                return
            }
            val step = total / (n - 1).toFloat()
            ox[0] = xs[0]; oy[0] = ys[0]
            var j = 0; var acc = 0f
            var segLen = segmentLength(xs, ys, 0)
            for (k in 1 until n - 1) {
                val target = k.toFloat() * step
                while (j < count - 2 && acc + segLen < target) {
                    acc += segLen; j++
                    segLen = segmentLength(xs, ys, j)
                }
                var tt = if (segLen > 0f) (target - acc) / segLen else 0f
                if (tt < 0f) tt = 0f else if (tt > 1f) tt = 1f
                ox[k] = xs[j] + (xs[j + 1] - xs[j]) * tt
                oy[k] = ys[j] + (ys[j + 1] - ys[j]) * tt
            }
            ox[n - 1] = xs[count - 1]; oy[n - 1] = ys[count - 1]
        }

        private fun segmentLength(xs: FloatArray, ys: FloatArray, j: Int): Float {
            val dx = xs[j + 1] - xs[j]; val dy = ys[j + 1] - ys[j]
            return sqrt(dx * dx + dy * dy)
        }

        /** out = (trọng tâm x, y, 1 / max(cạnh bbox, 1 phím)). */
        fun shapeFrame(xs: FloatArray, ys: FloatArray, n: Int, keyWidth: Float, out: FloatArray) {
            var minX = xs[0]; var maxX = xs[0]; var minY = ys[0]; var maxY = ys[0]
            var sx = 0f; var sy = 0f
            for (i in 0 until n) {
                val x = xs[i]; val y = ys[i]
                if (x < minX) minX = x; if (x > maxX) maxX = x
                if (y < minY) minY = y; if (y > maxY) maxY = y
                sx += x; sy += y
            }
            val side = max(max(maxX - minX, maxY - minY), keyWidth)
            out[0] = sx / n.toFloat(); out[1] = sy / n.toFloat(); out[2] = 1f / side
        }
    }
}
