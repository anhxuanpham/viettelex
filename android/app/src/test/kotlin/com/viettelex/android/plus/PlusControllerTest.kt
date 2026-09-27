package com.viettelex.android.plus

import com.viettelex.keyboard.PlusConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FakePlusStore : PlusStore {
    override var listener: ((PurchaseUpdate) -> Unit)? = null
    var connectOk = true
    var products = listOf<StoreProduct>()
    var owned: List<StorePurchase>? = emptyList()
    var launchOk = true
    val acked = mutableListOf<String>()
    val consumed = mutableListOf<String>()
    val launched = mutableListOf<String>()

    override suspend fun connect() = connectOk
    override suspend fun queryProducts(ids: List<String>) = products.filter { it.id in ids }
    override suspend fun queryPurchases() = owned
    override suspend fun acknowledge(token: String): Boolean { acked += token; return true }
    override suspend fun consume(token: String): Boolean { consumed += token; return true }
    override fun launchPurchase(productId: String): Boolean { launched += productId; return launchOk }
}

class PlusControllerTest {
    private val flags = mutableListOf<Boolean>()
    private fun make(s: FakePlusStore, initial: Boolean = false) =
        PlusController(s, { flags += it }, initial, CoroutineScope(Dispatchers.Unconfined))

    private fun plus(token: String = "p1", ack: Boolean = false, state: StorePurchase.State = StorePurchase.State.PURCHASED) =
        StorePurchase(listOf(PlusConfig.PLUS_PRODUCT_ID), token, state, ack)
    private fun tip(token: String = "t1") =
        StorePurchase(listOf(PlusConfig.TIP_PRODUCT_IDS[0]), token, StorePurchase.State.PURCHASED, false)

    @Test fun refreshGrantsAndAcknowledges() = runBlocking {
        val s = FakePlusStore().apply { owned = listOf(plus()) }
        val c = make(s)
        c.refresh()
        assertTrue(c.state.value.purchased)
        assertEquals(listOf(true), flags)
        assertEquals(listOf("p1"), s.acked)
    }

    @Test fun alreadyAcknowledgedNotReAcked() = runBlocking {
        val s = FakePlusStore().apply { owned = listOf(plus(ack = true)) }
        make(s).refresh()
        assertTrue(s.acked.isEmpty())
    }

    @Test fun refundRevokesOnFullQuery() = runBlocking {
        val s = FakePlusStore().apply { owned = emptyList() }
        val c = make(s, initial = true)
        c.refresh()
        assertFalse(c.state.value.purchased)
        assertEquals(listOf(false), flags)
    }

    @Test fun queryErrorKeepsFlag() = runBlocking {
        val s = FakePlusStore().apply { owned = null }
        val c = make(s, initial = true)
        c.refresh()
        assertTrue(c.state.value.purchased)
        assertTrue(flags.isEmpty())
    }

    @Test fun offlineKeepsFlag() = runBlocking {
        val s = FakePlusStore().apply { connectOk = false }
        val c = make(s, initial = true)
        c.refresh()
        assertTrue(c.state.value.purchased)
        assertTrue(flags.isEmpty())
        assertNotNull(c.state.value.message)
    }

    @Test fun pendingDoesNotUnlock() = runBlocking {
        val s = FakePlusStore()
        val c = make(s)
        c.handleUpdate(PurchaseUpdate.Purchases(listOf(plus(state = StorePurchase.State.PENDING))))
        assertFalse(c.state.value.purchased)
        assertTrue(s.acked.isEmpty())
        assertTrue(c.state.value.message!!.contains("chờ"))
    }

    @Test fun purchaseFlowViaListener() {
        val s = FakePlusStore()
        val c = make(s)
        c.buy(PlusConfig.PLUS_PRODUCT_ID)
        assertEquals(PlusConfig.PLUS_PRODUCT_ID, c.state.value.busyProductId)
        s.listener!!(PurchaseUpdate.Purchases(listOf(plus("new"))))
        assertTrue(c.state.value.purchased)
        assertNull(c.state.value.busyProductId)
        assertEquals(listOf("new"), s.acked)
        assertEquals(listOf(true), flags)
    }

    @Test fun tipIsConsumedAndDoesNotUnlock() = runBlocking {
        val s = FakePlusStore()
        val c = make(s)
        c.handleUpdate(PurchaseUpdate.Purchases(listOf(tip())))
        assertEquals(listOf("t1"), s.consumed)
        assertFalse(c.state.value.purchased)
        assertTrue(flags.isEmpty())
        assertTrue(c.state.value.message!!.contains("ủng hộ"))
    }

    @Test fun leftoverTipConsumedOnRefresh() = runBlocking {
        val s = FakePlusStore().apply { owned = listOf(tip("old"), plus(ack = true)) }
        val c = make(s)
        c.refresh()
        assertEquals(listOf("old"), s.consumed)
        assertTrue(c.state.value.purchased)
    }

    @Test fun cancelClearsBusy() = runBlocking {
        val s = FakePlusStore()
        val c = make(s)
        c.buy(PlusConfig.TIP_PRODUCT_IDS[1])
        c.handleUpdate(PurchaseUpdate.Cancelled)
        assertNull(c.state.value.busyProductId)
        assertNull(c.state.value.message)
    }

    @Test fun launchFailureShowsMessage() {
        val s = FakePlusStore().apply { launchOk = false }
        val c = make(s)
        c.buy(PlusConfig.PLUS_PRODUCT_ID)
        assertNull(c.state.value.busyProductId)
        assertNotNull(c.state.value.message)
    }

    @Test fun alreadyOwnedTriggersRestore() = runBlocking {
        val s = FakePlusStore().apply { owned = listOf(plus(ack = true)) }
        val c = make(s)
        c.handleUpdate(PurchaseUpdate.AlreadyOwned)
        assertTrue(c.state.value.purchased)
        assertFalse(c.state.value.restoring)
    }

    @Test fun restoreNothingFound() = runBlocking {
        val s = FakePlusStore()
        val c = make(s)
        c.restore()
        assertFalse(c.state.value.purchased)
        assertTrue(c.state.value.message!!.contains("Không tìm thấy"))
    }

    @Test fun productsSplitAndOrdered() = runBlocking {
        val s = FakePlusStore().apply {
            products = listOf(
                StoreProduct(PlusConfig.TIP_PRODUCT_IDS[2], "L", "99.000 ₫"),
                StoreProduct(PlusConfig.PLUS_PRODUCT_ID, "Plus", "69.000 ₫"),
                StoreProduct(PlusConfig.TIP_PRODUCT_IDS[0], "S", "25.000 ₫"),
            )
        }
        val c = make(s)
        c.refresh()
        assertEquals("69.000 ₫", c.state.value.plus?.price)
        assertEquals(listOf(PlusConfig.TIP_PRODUCT_IDS[0], PlusConfig.TIP_PRODUCT_IDS[2]), c.state.value.tips.map { it.id })
    }
}
