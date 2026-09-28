package com.viettelex.android.plus

/**
 * Lớp trừu tượng cửa hàng — bản thật [PlayPlusStore] (Google Play Billing),
 * test dùng bản giả. Không chứa kiểu Billing để logic [PlusController] test
 * được trên JVM.
 */
data class StoreProduct(val id: String, val title: String, val price: String)

data class StorePurchase(
    val productIds: List<String>,
    val token: String,
    val state: State,
    val acknowledged: Boolean,
) {
    enum class State { PURCHASED, PENDING, OTHER }
}

sealed interface PurchaseUpdate {
    /** Giao dịch mới/đổi trạng thái (từ onPurchasesUpdated). */
    data class Purchases(val list: List<StorePurchase>) : PurchaseUpdate
    data object Cancelled : PurchaseUpdate
    /** Đã sở hữu (ITEM_ALREADY_OWNED) — nên query lại để khôi phục. */
    data object AlreadyOwned : PurchaseUpdate
    data class Error(val code: Int) : PurchaseUpdate
}

interface PlusStore {
    suspend fun connect(): Boolean
    suspend fun queryProducts(ids: List<String>): List<StoreProduct>
    /** Toàn bộ giao dịch in-app đang sở hữu; null = lỗi (giữ nguyên cờ cũ). */
    suspend fun queryPurchases(): List<StorePurchase>?
    suspend fun acknowledge(token: String): Boolean
    suspend fun consume(token: String): Boolean
    /** Mở màn thanh toán; kết quả về qua [listener]. false = không mở được. */
    fun launchPurchase(productId: String): Boolean
    var listener: ((PurchaseUpdate) -> Unit)?
    /** Activity chủ bị huỷ: ngắt kết nối (Billing tự nối lại hẹn giờ trên main looper — giữ activity). */
    fun release() {}
}
