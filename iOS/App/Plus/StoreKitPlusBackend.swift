// StoreKit 2 thật — chỉ nằm trong APP (bàn phím không link StoreKit).
// Xác thực: chỉ nhận VerificationResult.verified (JWS do StoreKit kiểm chữ ký).
import Foundation
import StoreKit

final class StoreKitPlusBackend: PlusStoreBackend {
    private var products: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    deinit { updatesTask?.cancel() }

    func loadProducts(ids: [String]) async throws -> [PlusProduct] {
        let list = try await Product.products(for: ids)
        for p in list { products[p.id] = p }
        return list.map { PlusProduct(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice) }
    }

    func currentEntitlements() async -> [PlusEntitlement] {
        var out: [PlusEntitlement] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            out.append(PlusEntitlement(productID: t.productID, revoked: t.revocationDate != nil))
        }
        return out
    }

    func purchase(productID: String) async throws -> PlusPurchaseOutcome {
        let product: Product
        if let p = products[productID] {
            product = p
        } else if let p = try await Product.products(for: [productID]).first {
            products[productID] = p
            product = p
        } else {
            throw StoreKitError.notAvailableInStorefront
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let t) = verification else {
                throw StoreKitError.unknown   // chữ ký không hợp lệ → không mở khoá
            }
            await t.finish()   // tip consumable: finish = đã "tiêu thụ"
            return .success(productID: t.productID)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func sync() async throws { try await AppStore.sync() }

    func observeUpdates(_ handler: @escaping @Sendable () async -> Void) {
        updatesTask?.cancel()
        updatesTask = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await handler()
            }
        }
    }
}
