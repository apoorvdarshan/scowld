import XCTest
@testable import Scowld

/// The tip jar against a fake store; no StoreKit or RevenueCat calls are made.
@MainActor
final class TipJarTests: XCTestCase {
    private actor FakeStore: TipStore {
        var available: [TipProduct]
        var outcome: Result<TipPurchaseOutcome, Error>
        private(set) var purchased: [String] = []
        private(set) var productRequests = 0

        init(available: [TipProduct], outcome: Result<TipPurchaseOutcome, Error> = .success(.completed)) {
            self.available = available
            self.outcome = outcome
        }

        func products(_ productIDs: [String]) async -> [TipProduct] {
            productRequests += 1
            return available.filter { productIDs.contains($0.productID) }
        }

        func purchase(_ productID: String) async throws -> TipPurchaseOutcome {
            purchased.append(productID)
            return try outcome.get()
        }
    }

    private struct StoreDown: LocalizedError {
        var errorDescription: String? { "The App Store is unavailable." }
    }

    private let small = TipTier.all[0]
    private func priced(_ tier: TipTier, _ price: String) -> TipProduct {
        TipProduct(productID: tier.productID, localizedPrice: price)
    }

    func testTheFiveTiersMatchTheAppStoreProducts() {
        XCTAssertEqual(TipTier.all.map(\.productID), [
            "com.apoorvdarshan.Scowld.tip.small",
            "com.apoorvdarshan.Scowld.tip.medium",
            "com.apoorvdarshan.Scowld.tip.large",
            "com.apoorvdarshan.Scowld.tip.huge",
            "com.apoorvdarshan.Scowld.tip.giant",
        ])
        XCTAssertEqual(Set(TipTier.all.map(\.name)).count, 5)
        XCTAssertTrue(RevenueCatSetup.publicAPIKey.hasPrefix("appl_"), "only the public SDK key may ship")
    }

    func testLoadingShowsLocalizedPricesOnce() async {
        let store = FakeStore(available: [priced(small, "₹89.00"), priced(TipTier.all[4], "₹1,899.00")])
        let model = TipJarModel(store: store)
        await model.load()
        await model.load()
        XCTAssertEqual(model.products[small.productID]?.localizedPrice, "₹89.00")
        XCTAssertEqual(model.products.count, 2)
        let requests = await store.productRequests
        XCTAssertEqual(requests, 1, "products are fetched once")
    }

    func testACompletedTipThanksTheUser() async {
        let store = FakeStore(available: [priced(small, "$0.99")])
        let model = TipJarModel(store: store)
        await model.load()
        await model.purchase(small)
        XCTAssertEqual(model.status, .thanks)
        let purchased = await store.purchased
        XCTAssertEqual(purchased, [small.productID])
    }

    func testCancelledPendingAndFailedTips() async {
        let cancelled = TipJarModel(store: FakeStore(available: [priced(small, "$0.99")], outcome: .success(.cancelled)))
        await cancelled.load()
        await cancelled.purchase(small)
        XCTAssertEqual(cancelled.status, .idle, "cancelling is not an error")

        let pending = TipJarModel(store: FakeStore(available: [priced(small, "$0.99")], outcome: .success(.pending)))
        await pending.load()
        await pending.purchase(small)
        XCTAssertEqual(pending.status, .pending, "Ask to Buy waits for approval")

        let failed = TipJarModel(store: FakeStore(available: [priced(small, "$0.99")], outcome: .failure(StoreDown())))
        await failed.load()
        await failed.purchase(small)
        XCTAssertEqual(failed.status, .failed("The App Store is unavailable."))
    }

    func testAnUnavailableTipCannotBeBought() async {
        let store = FakeStore(available: [])
        let model = TipJarModel(store: store)
        await model.load()
        await model.purchase(small)
        XCTAssertEqual(model.status, .idle)
        let purchased = await store.purchased
        XCTAssertTrue(purchased.isEmpty)
    }

    func testTestsNeverReachTheStore() async {
        let model = TipJarModel(store: nil)
        await model.load()
        XCTAssertTrue(model.products.isEmpty)
        XCTAssertFalse(model.isLoading)
    }
}
