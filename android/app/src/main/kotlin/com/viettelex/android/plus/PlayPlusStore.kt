package com.viettelex.android.plus

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.coroutines.resume

/** Google Play Billing Library 8 — chỉ sản phẩm in-app (không thuê bao). */
class PlayPlusStore(
    context: Context,
    private val activity: () -> Activity?,
) : PlusStore {
    override var listener: ((PurchaseUpdate) -> Unit)? = null
    private val details = mutableMapOf<String, ProductDetails>()

    private val client: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener { result, purchases ->
            val u = when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> PurchaseUpdate.Purchases(purchases.orEmpty().map(::map))
                BillingClient.BillingResponseCode.USER_CANCELED -> PurchaseUpdate.Cancelled
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> PurchaseUpdate.AlreadyOwned
                else -> PurchaseUpdate.Error(result.responseCode)
            }
            listener?.invoke(u)
        }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    /** onResume và màn Plus có thể cùng gọi — chỉ một startConnection một lúc. */
    private val connecting = Mutex()

    override suspend fun connect(): Boolean = connecting.withLock {
        if (client.isReady) return@withLock true
        suspendCancellableCoroutine { cont ->
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(r: BillingResult) {
                    if (cont.isActive) cont.resume(r.responseCode == BillingClient.BillingResponseCode.OK)
                }
                override fun onBillingServiceDisconnected() {
                    if (cont.isActive) cont.resume(false)
                }
            })
        }
    }

    override suspend fun queryProducts(ids: List<String>): List<StoreProduct> {
        val params = QueryProductDetailsParams.newBuilder().setProductList(ids.map {
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(it).setProductType(BillingClient.ProductType.INAPP).build()
        }).build()
        val list = suspendCancellableCoroutine { cont ->
            client.queryProductDetailsAsync(params) { r, res ->
                cont.resume(if (r.responseCode == BillingClient.BillingResponseCode.OK) res.productDetailsList else emptyList())
            }
        }
        list.forEach { details[it.productId] = it }
        return list.map {
            StoreProduct(it.productId, it.name, it.oneTimePurchaseOfferDetails?.formattedPrice.orEmpty())
        }
    }

    override suspend fun queryPurchases(): List<StorePurchase>? = suspendCancellableCoroutine { cont ->
        val p = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        client.queryPurchasesAsync(p) { r, list ->
            cont.resume(if (r.responseCode == BillingClient.BillingResponseCode.OK) list.map(::map) else null)
        }
    }

    override suspend fun acknowledge(token: String): Boolean = suspendCancellableCoroutine { cont ->
        client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(token).build()) { r ->
            cont.resume(r.responseCode == BillingClient.BillingResponseCode.OK)
        }
    }

    override suspend fun consume(token: String): Boolean = suspendCancellableCoroutine { cont ->
        client.consumeAsync(ConsumeParams.newBuilder().setPurchaseToken(token).build()) { r, _ ->
            cont.resume(r.responseCode == BillingClient.BillingResponseCode.OK)
        }
    }

    override fun launchPurchase(productId: String): Boolean {
        val act = activity() ?: return false
        val pd = details[productId] ?: return false
        val params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(
            BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(pd).build()
        )).build()
        return client.launchBillingFlow(act, params).responseCode == BillingClient.BillingResponseCode.OK
    }

    private fun map(p: Purchase) = StorePurchase(
        productIds = p.products,
        token = p.purchaseToken,
        state = when (p.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> StorePurchase.State.PURCHASED
            Purchase.PurchaseState.PENDING -> StorePurchase.State.PENDING
            else -> StorePurchase.State.OTHER
        },
        acknowledged = p.isAcknowledged,
    )
}
