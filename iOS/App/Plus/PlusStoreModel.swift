// Logic mua VietTelex Plus / ủng hộ — KHÔNG import StoreKit để unit test chạy
// với backend giả. Bản thật: StoreKitPlusBackend.swift.
import Foundation

/// Một entitlement đã được StoreKit xác thực (JWS verified).
struct PlusEntitlement: Equatable {
    let productID: String
    /// Apple hoàn tiền / thu hồi (revocationDate != nil).
    let revoked: Bool
}

struct PlusProduct: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    var isTip: Bool { PlusConfig.tipProductIDs.contains(id) }
}

enum PlusPurchaseOutcome: Equatable {
    case success(productID: String)
    case pending        // Ask to Buy / chờ duyệt
    case cancelled
}

protocol PlusStoreBackend: AnyObject {
    func loadProducts(ids: [String]) async throws -> [PlusProduct]
    /// Entitlement hiện tại, chỉ gồm giao dịch đã verify.
    func currentEntitlements() async -> [PlusEntitlement]
    func purchase(productID: String) async throws -> PlusPurchaseOutcome
    /// Khôi phục: đồng bộ giao dịch với App Store (AppStore.sync).
    func sync() async throws
    /// Gọi `handler` khi có giao dịch mới/thay đổi ngoài luồng mua (Transaction.updates).
    func observeUpdates(_ handler: @escaping @Sendable () async -> Void)
}

enum PlusEntitlementLogic {
    /// Có Plus khi có entitlement non-consumable Plus chưa bị thu hồi.
    static func isEntitled(_ entitlements: [PlusEntitlement],
                           plusID: String = PlusConfig.plusProductID) -> Bool {
        entitlements.contains { $0.productID == plusID && !$0.revoked }
    }
}

@MainActor
final class PlusStoreModel: ObservableObject {
    @Published private(set) var plusProduct: PlusProduct?
    @Published private(set) var tipProducts: [PlusProduct] = []
    @Published private(set) var purchased: Bool
    @Published private(set) var busyProductID: String?
    @Published private(set) var isRestoring = false
    @Published var message: String?

    private let backend: PlusStoreBackend
    private let writeFlag: (Bool) -> Void

    init(backend: PlusStoreBackend,
         initialPurchased: Bool = PlusGate.purchased,
         writeFlag: @escaping (Bool) -> Void = { PlusGate.setPurchased($0) }) {
        self.backend = backend
        self.purchased = initialPurchased
        self.writeFlag = writeFlag
        backend.observeUpdates { [weak self] in await self?.refreshEntitlements() }
    }

    /// Đã có Plus (tính cả công tắc giả lập Debug) — dùng cho UI.
    var isPlus: Bool {
        PlusGate.resolve(purchased: purchased, debugOverride: PlusGate.debugOverride,
                         allowDebugOverride: PlusGate.allowsDebugOverride)
    }

    func loadProducts() async {
        do {
            let all = try await backend.loadProducts(ids: PlusConfig.allProductIDs)
            plusProduct = all.first { $0.id == PlusConfig.plusProductID }
            tipProducts = PlusConfig.tipProductIDs.compactMap { id in all.first { $0.id == id } }
        } catch {
            message = L("Không tải được sản phẩm từ App Store. Kiểm tra kết nối mạng rồi thử lại.")
        }
    }

    /// Đọc entitlement đã verify → cập nhật cờ App Group cho bàn phím.
    func refreshEntitlements() async {
        let ents = await backend.currentEntitlements()
        apply(PlusEntitlementLogic.isEntitled(ents))
    }

    func buy(_ productID: String) async {
        guard busyProductID == nil else { return }
        busyProductID = productID
        defer { busyProductID = nil }
        do {
            switch try await backend.purchase(productID: productID) {
            case .success(let id):
                if id == PlusConfig.plusProductID {
                    await refreshEntitlements()
                    message = purchased ? L("Đã mở khoá VietTelex Plus. Cảm ơn bạn!") : nil
                } else {
                    message = L("Cảm ơn bạn đã ủng hộ VietTelex! ❤️")
                }
            case .pending:
                message = L("Giao dịch đang chờ duyệt. Plus sẽ tự mở khi được chấp thuận.")
            case .cancelled:
                break
            }
        } catch {
            message = L("Giao dịch không thành công. Bạn chưa bị trừ tiền.")
        }
    }

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do { try await backend.sync() } catch {
            message = L("Không kết nối được App Store để khôi phục.")
            return
        }
        await refreshEntitlements()
        message = purchased ? L("Đã khôi phục VietTelex Plus.") : L("Không tìm thấy giao dịch Plus nào với Apple ID này.")
    }

    private func apply(_ entitled: Bool) {
        purchased = entitled
        writeFlag(entitled)
    }
}
