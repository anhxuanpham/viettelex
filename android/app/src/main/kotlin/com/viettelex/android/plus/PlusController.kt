package com.viettelex.android.plus

import com.viettelex.keyboard.PlusConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import com.viettelex.keyboard.tr

data class PlusUiState(
    val plus: StoreProduct? = null,
    val tips: List<StoreProduct> = emptyList(),
    val purchased: Boolean = false,
    val busyProductId: String? = null,
    val restoring: Boolean = false,
    val message: String? = null,
)

/**
 * Logic mua Plus / ủng hộ trên nền [PlusStore]:
 * - Plus (mua một lần): PURCHASED ⇒ acknowledge (nếu chưa) + ghi cờ cho IME.
 * - Tip: PURCHASED ⇒ consume (mua lại được), không mở gì.
 * - PENDING không mở khoá. Lỗi kết nối/truy vấn ⇒ giữ nguyên cờ cũ.
 * - Khôi phục = queryPurchases: danh sách đầy đủ ⇒ cờ = có Plus hay không
 *   (Play hoàn tiền ⇒ giao dịch biến mất ⇒ thu hồi).
 */
class PlusController(
    private val store: PlusStore,
    private val writeFlag: (Boolean) -> Unit,
    initialPurchased: Boolean,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(PlusUiState(purchased = initialPurchased))
    val state: StateFlow<PlusUiState> = _state

    init {
        store.listener = { u -> scope.launch { handleUpdate(u) } }
    }

    /** Kết nối + tải giá + đồng bộ giao dịch. Gọi khi mở app / onResume. */
    suspend fun refresh(loadProducts: Boolean = true) {
        if (!store.connect()) {
            if (loadProducts) msg(tr("Không kết nối được Google Play."))
            return
        }
        if (loadProducts) {
            val all = store.queryProducts(PlusConfig.ALL_PRODUCT_IDS)
            _state.update { s ->
                s.copy(plus = all.firstOrNull { it.id == PlusConfig.PLUS_PRODUCT_ID },
                    tips = PlusConfig.TIP_PRODUCT_IDS.mapNotNull { id -> all.firstOrNull { it.id == id } })
            }
        }
        val owned = store.queryPurchases() ?: return
        setPurchased(process(owned, thankTips = false))
    }

    /** Nút "Khôi phục giao dịch". */
    suspend fun restore() {
        _state.update { it.copy(restoring = true) }
        try {
            if (!store.connect()) { msg(tr("Không kết nối được Google Play.")); return }
            val owned = store.queryPurchases()
            if (owned == null) { msg(tr("Không truy vấn được giao dịch. Thử lại sau.")); return }
            val ok = process(owned, thankTips = false)
            setPurchased(ok)
            msg(if (ok) tr("Đã khôi phục VietTelex Plus.") else tr("Không tìm thấy giao dịch Plus nào với tài khoản Google này."))
        } finally {
            _state.update { it.copy(restoring = false) }
        }
    }

    fun buy(productId: String) {
        if (_state.value.busyProductId != null) return
        if (!store.launchPurchase(productId)) {
            msg(tr("Chưa mở được thanh toán. Kiểm tra kết nối rồi thử lại."))
            return
        }
        _state.update { it.copy(busyProductId = productId) }
    }

    suspend fun handleUpdate(u: PurchaseUpdate) {
        _state.update { it.copy(busyProductId = null) }
        when (u) {
            is PurchaseUpdate.Purchases -> {
                // Danh sách này chỉ gồm giao dịch mới ⇒ chỉ mở, không thu hồi.
                if (process(u.list, thankTips = true)) {
                    setPurchased(true)
                    msg(tr("Đã mở khoá VietTelex Plus. Cảm ơn bạn!"))
                } else if (u.list.any { it.state == StorePurchase.State.PENDING && PlusConfig.PLUS_PRODUCT_ID in it.productIds }) {
                    msg(tr("Giao dịch đang chờ thanh toán. Plus sẽ tự mở khi hoàn tất."))
                }
            }
            PurchaseUpdate.AlreadyOwned -> restore()
            PurchaseUpdate.Cancelled -> Unit
            is PurchaseUpdate.Error -> msg(tr("Giao dịch không thành công (mã %s). Bạn chưa bị trừ tiền.", u.code))
        }
    }

    fun dismissMessage() = _state.update { it.copy(message = null) }

    /** Acknowledge Plus / consume tip. Trả về: có Plus đã thanh toán không. */
    private suspend fun process(list: List<StorePurchase>, thankTips: Boolean): Boolean {
        var plus = false
        for (p in list) {
            if (p.state != StorePurchase.State.PURCHASED) continue
            if (PlusConfig.PLUS_PRODUCT_ID in p.productIds) {
                plus = true
                // Không acknowledge trong 3 ngày ⇒ Play tự hoàn tiền.
                if (!p.acknowledged) store.acknowledge(p.token)
            }
            if (p.productIds.any { it in PlusConfig.TIP_PRODUCT_IDS }) {
                if (store.consume(p.token) && thankTips) msg(tr("Cảm ơn bạn đã ủng hộ VietTelex! ❤️"))
            }
        }
        return plus
    }

    private fun setPurchased(on: Boolean) {
        _state.update { it.copy(purchased = on) }
        writeFlag(on)
    }

    private fun msg(m: String) = _state.update { it.copy(message = m) }
}
