import XCTest
import StoreKitTest
import StoreKit

/// VietTelex Plus: PlusGate (cờ App Group), logic entitlement với backend giả,
/// và file cấu hình StoreKit (StoreKitTest).
final class PlusGateTests: XCTestCase {
    private var suiteName = ""
    private var savedDefaults: UserDefaults!
    private var savedPaywall = false
    private var savedAllowDebug = false

    override func setUp() {
        suiteName = "PlusGateTests.\(UUID().uuidString)"
        savedDefaults = PlusGate.defaults
        savedPaywall = PlusGate.paywallEnabled
        savedAllowDebug = PlusGate.allowsDebugOverride
        PlusGate.defaults = UserDefaults(suiteName: suiteName)!
        PlusGate.paywallEnabled = true
        PlusGate.allowsDebugOverride = false
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        PlusGate.defaults = savedDefaults
        PlusGate.paywallEnabled = savedPaywall
        PlusGate.allowsDebugOverride = savedAllowDebug
    }

    func testLockedByDefaultWhenPaywallOn() {
        for f in PlusFeature.allCases { XCTAssertFalse(PlusGate.isUnlocked(f), "\(f)") }
        XCTAssertEqual(PlusGate.pinnedClipLimit, PlusConfig.freePinnedClipLimit)
    }

    func testPurchasedFlagUnlocksEverything() {
        PlusGate.setPurchased(true)
        XCTAssertTrue(PlusGate.defaults.bool(forKey: PlusConfig.unlockedKey))
        for f in PlusFeature.allCases { XCTAssertTrue(PlusGate.isUnlocked(f), "\(f)") }
        XCTAssertNil(PlusGate.pinnedClipLimit)
        PlusGate.setPurchased(false)
        XCTAssertFalse(PlusGate.isUnlocked(.textTools))
    }

    /// Bàn phím đọc qua UserDefaults khác (process khác) — cùng suite phải thấy cờ.
    func testFlagVisibleThroughSeparateDefaultsInstance() {
        PlusGate.setPurchased(true)
        XCTAssertTrue(UserDefaults(suiteName: suiteName)!.bool(forKey: "plusUnlocked"))
    }

    func testPaywallOffOpensAllButThanksBadge() {
        PlusGate.paywallEnabled = false
        XCTAssertTrue(PlusGate.isUnlocked(.premiumThemes))
        XCTAssertTrue(PlusGate.isUnlocked(.iCloudSync))
        XCTAssertFalse(PlusGate.isUnlocked(.thanksBadge), "huy hiệu chỉ cho người đã mua")
        XCTAssertNil(PlusGate.pinnedClipLimit)
    }

    func testDebugOverrideOnlyWhenAllowed() {
        PlusGate.debugOverride = true
        XCTAssertFalse(PlusGate.isUnlocked(.sentenceDiacritics), "Release bỏ qua giả lập")
        PlusGate.allowsDebugOverride = true
        XCTAssertTrue(PlusGate.isUnlocked(.sentenceDiacritics))
        XCTAssertFalse(PlusGate.purchased, "giả lập không ghi cờ mua thật")
    }

    func testResolveTruthTable() {
        XCTAssertFalse(PlusGate.resolve(purchased: false, debugOverride: false, allowDebugOverride: true))
        XCTAssertFalse(PlusGate.resolve(purchased: false, debugOverride: true, allowDebugOverride: false))
        XCTAssertTrue(PlusGate.resolve(purchased: false, debugOverride: true, allowDebugOverride: true))
        XCTAssertTrue(PlusGate.resolve(purchased: true, debugOverride: false, allowDebugOverride: false))
    }

    func testConfigIDs() {
        XCTAssertEqual(PlusConfig.plusProductID, "com.viettelex.ios.plus")
        XCTAssertEqual(PlusConfig.tipProductIDs.count, 3)
        XCTAssertEqual(Set(PlusConfig.allProductIDs).count, 4)
        XCTAssertTrue(PlusConfig.paywallEnabled, "đã tạo 4 sản phẩm trên App Store Connect (27/09) → bán thật")
    }
}

// MARK: - Logic entitlement với backend giả

final class FakePlusBackend: PlusStoreBackend {
    var products: [PlusProduct] = []
    var entitlements: [PlusEntitlement] = []
    var purchaseResult: Result<PlusPurchaseOutcome, Error> = .success(.cancelled)
    /// Mua thành công Plus → thêm entitlement (như StoreKit).
    var grantOnPurchase = true
    var syncError: Error?
    var syncCalls = 0
    var updateHandler: (@Sendable () async -> Void)?

    func loadProducts(ids: [String]) async throws -> [PlusProduct] { products.filter { ids.contains($0.id) } }
    func currentEntitlements() async -> [PlusEntitlement] { entitlements }
    func purchase(productID: String) async throws -> PlusPurchaseOutcome {
        let r = try purchaseResult.get()
        if case .success(let id) = r, id == PlusConfig.plusProductID, grantOnPurchase {
            entitlements.append(PlusEntitlement(productID: id, revoked: false))
        }
        return r
    }
    func sync() async throws { syncCalls += 1; if let e = syncError { throw e } }
    func observeUpdates(_ handler: @escaping @Sendable () async -> Void) { updateHandler = handler }
}

@MainActor
final class PlusStoreModelTests: XCTestCase {
    private var flag: [Bool] = []
    private func make(_ b: FakePlusBackend, initial: Bool = false) -> PlusStoreModel {
        PlusStoreModel(backend: b, initialPurchased: initial, writeFlag: { [weak self] in self?.flag.append($0) })
    }

    func testEntitlementLogic() {
        let plus = PlusConfig.plusProductID
        XCTAssertFalse(PlusEntitlementLogic.isEntitled([]))
        XCTAssertTrue(PlusEntitlementLogic.isEntitled([.init(productID: plus, revoked: false)]))
        XCTAssertFalse(PlusEntitlementLogic.isEntitled([.init(productID: plus, revoked: true)]), "hoàn tiền → mất quyền")
        XCTAssertFalse(PlusEntitlementLogic.isEntitled([.init(productID: PlusConfig.tipProductIDs[0], revoked: false)]),
                       "tip không mở Plus")
    }

    func testRefreshWritesFlag() async {
        let b = FakePlusBackend()
        b.entitlements = [.init(productID: PlusConfig.plusProductID, revoked: false)]
        let m = make(b)
        await m.refreshEntitlements()
        XCTAssertTrue(m.purchased)
        XCTAssertEqual(flag, [true])
        b.entitlements = []
        await m.refreshEntitlements()
        XCTAssertFalse(m.purchased)
        XCTAssertEqual(flag, [true, false])
    }

    func testBuyPlusSuccess() async {
        let b = FakePlusBackend()
        b.purchaseResult = .success(.success(productID: PlusConfig.plusProductID))
        let m = make(b)
        await m.buy(PlusConfig.plusProductID)
        XCTAssertTrue(m.purchased)
        XCTAssertEqual(flag.last, true)
        XCTAssertNil(m.busyProductID)
        XCTAssertNotNil(m.message)
    }

    func testBuyTipDoesNotUnlock() async {
        let b = FakePlusBackend()
        let tip = PlusConfig.tipProductIDs[1]
        b.purchaseResult = .success(.success(productID: tip))
        let m = make(b)
        await m.buy(tip)
        XCTAssertFalse(m.purchased)
        XCTAssertTrue(flag.isEmpty)
        XCTAssertTrue(m.message?.contains("ủng hộ") == true)
    }

    func testPendingAndCancelledDoNotUnlock() async {
        let b = FakePlusBackend()
        let m = make(b)
        b.purchaseResult = .success(.pending)
        await m.buy(PlusConfig.plusProductID)
        XCTAssertFalse(m.purchased)
        b.purchaseResult = .success(.cancelled)
        await m.buy(PlusConfig.plusProductID)
        XCTAssertFalse(m.purchased)
        XCTAssertTrue(flag.isEmpty)
    }

    func testPurchaseErrorKeepsState() async {
        struct E: Error {}
        let b = FakePlusBackend()
        b.purchaseResult = .failure(E())
        let m = make(b, initial: true)
        await m.buy(PlusConfig.plusProductID)
        XCTAssertTrue(m.purchased, "lỗi mạng không thu hồi Plus")
        XCTAssertTrue(flag.isEmpty)
        XCTAssertNotNil(m.message)
    }

    func testRestore() async {
        let b = FakePlusBackend()
        b.entitlements = [.init(productID: PlusConfig.plusProductID, revoked: false)]
        let m = make(b)
        await m.restore()
        XCTAssertEqual(b.syncCalls, 1)
        XCTAssertTrue(m.purchased)
        XCTAssertFalse(m.isRestoring)
    }

    func testRestoreFailureDoesNotRevoke() async {
        struct E: Error {}
        let b = FakePlusBackend()
        b.syncError = E()
        let m = make(b, initial: true)
        await m.restore()
        XCTAssertTrue(m.purchased)
        XCTAssertTrue(flag.isEmpty)
    }

    func testTransactionUpdateRefreshes() async {
        let b = FakePlusBackend()
        let m = make(b)
        b.entitlements = [.init(productID: PlusConfig.plusProductID, revoked: false)]
        await b.updateHandler?()
        XCTAssertTrue(m.purchased)
    }

    func testLoadProductsSplitsPlusAndTips() async {
        let b = FakePlusBackend()
        b.products = [
            .init(id: PlusConfig.tipProductIDs[2], displayName: "L", displayPrice: "99.000đ"),
            .init(id: PlusConfig.plusProductID, displayName: "Plus", displayPrice: "69.000đ"),
            .init(id: PlusConfig.tipProductIDs[0], displayName: "S", displayPrice: "25.000đ"),
        ]
        let m = make(b)
        await m.loadProducts()
        XCTAssertEqual(m.plusProduct?.displayPrice, "69.000đ")
        XCTAssertEqual(m.tipProducts.map(\.id), [PlusConfig.tipProductIDs[0], PlusConfig.tipProductIDs[2]], "giữ thứ tự config")
    }
}

// MARK: - File .storekit khớp PlusConfig

final class PlusStoreKitConfigTests: XCTestCase {
    private var configURL: URL? {
        Bundle(for: Self.self).url(forResource: "VietTelex", withExtension: "storekit")
    }

    /// Không cần StoreKit runtime: đọc JSON, kiểm ID + loại + giá.
    func testStoreKitFileMatchesConfig() throws {
        let url = try XCTUnwrap(configURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        var types: [String: String] = [:]
        var prices: [String: String] = [:]
        for p in products {
            types[p["productID"] as! String] = p["type"] as? String
            prices[p["productID"] as! String] = p["displayPrice"] as? String
        }
        XCTAssertEqual(types[PlusConfig.plusProductID], "NonConsumable")
        XCTAssertEqual(prices[PlusConfig.plusProductID], "69000")
        for id in PlusConfig.tipProductIDs { XCTAssertEqual(types[id], "Consumable", id) }
        XCTAssertEqual(PlusConfig.tipProductIDs.map { prices[$0] }, ["25000", "49000", "99000"])
    }

    /// StoreKitTest thật: nạp sản phẩm từ file cấu hình. Bundle test không có
    /// app host → một số môi trường không nạp được; khi đó bỏ qua (không fail).
    func testStoreKitTestSessionLoadsProducts() async throws {
        try SlowTests.require()
        let url = try XCTUnwrap(configURL)
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        let products = try await Product.products(for: PlusConfig.allProductIDs)
        try XCTSkipIf(products.isEmpty, "StoreKitTest không khả dụng trong bundle test không host")
        XCTAssertEqual(Set(products.map(\.id)), Set(PlusConfig.allProductIDs))
        XCTAssertEqual(products.first { $0.id == PlusConfig.plusProductID }?.type, .nonConsumable)
    }
}
