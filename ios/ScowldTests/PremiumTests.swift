import XCTest
@testable import Scowld

/// Scowld Premium in the app: the balance from Scowld's server, the store, and
/// which connection a user starts with. Nothing reaches the store or the server.
@MainActor
final class PremiumTests: XCTestCase {
    private final class FakeStore: PremiumStore, @unchecked Sendable {
        var userID: String? = "$RCAnonymousID:0123456789abcdef0123456789abcdef"
        var available: [PremiumProduct] = [
            PremiumProduct(productID: PremiumPlan.yearly.productID, localizedPrice: "$99.99", localizedMonthlyPrice: "$8.33", freeTrialDays: 3),
            PremiumProduct(productID: PremiumPlan.weekly.productID, localizedPrice: "$6.99", localizedMonthlyPrice: nil, freeTrialDays: nil),
            PremiumProduct(productID: MinutePack.all[0].productID, localizedPrice: "$6.99", localizedMonthlyPrice: nil, freeTrialDays: nil),
        ]
        var subscriptions: Set<String> = []
        var outcome: Result<TipPurchaseOutcome, Error> = .success(.completed)
        var subscribesOnPurchase: String?
        var restored = false
        var purchased: [String] = []

        func appUserID() async -> String? { userID }
        func products(_ productIDs: [String]) async -> [PremiumProduct] {
            available.filter { productIDs.contains($0.productID) }
        }
        func purchase(_ productID: String) async throws -> TipPurchaseOutcome {
            purchased.append(productID)
            let result = try outcome.get()
            if result == .completed, let subscribesOnPurchase { subscriptions.insert(subscribesOnPurchase) }
            return result
        }
        func restore() async throws { restored = true }
        func activeSubscriptions() async -> Set<String> { subscriptions }
        func showManageSubscriptions() async {}
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? { "The store is down." }
    }

    private func balance(plan: String?, planLeft: Int, packLeft: Int = 0) -> PremiumBalance {
        PremiumBalance(plan: plan, planMinutes: 50, planSecondsLeft: planLeft, planRenewsAt: nil, packSecondsLeft: packLeft)
    }

    func testLoadingReadsPricesSubscriptionsAndMinutesLeft() async {
        let store = FakeStore()
        store.subscriptions = [PremiumPlan.weekly.productID]
        var askedFor: [String] = []
        let model = PremiumModel(store: store) { userID in
            askedFor.append(userID)
            return self.balance(plan: "weekly", planLeft: 600, packLeft: 120)
        }
        await model.load()
        XCTAssertEqual(model.products[PremiumPlan.yearly.productID]?.freeTrialDays, 3)
        XCTAssertTrue(model.isSubscribed)
        XCTAssertEqual(model.activePlan, .weekly)
        XCTAssertEqual(model.balance?.minutesLeft, 12)
        XCTAssertTrue(model.canTalk)
        XCTAssertEqual(askedFor, [store.userID!])
    }

    func testCanTalkFollowsTheServerOrElseTheSubscription() async {
        let store = FakeStore()
        var serverBalance: PremiumBalance?
        let model = PremiumModel(store: store) { _ in
            guard let serverBalance else { throw URLError(.notConnectedToInternet) }
            return serverBalance
        }
        await model.load()
        XCTAssertNil(model.balance)
        XCTAssertFalse(model.canTalk, "No plan and no balance")

        store.subscriptions = [PremiumPlan.yearly.productID]
        await model.refresh()
        XCTAssertTrue(model.canTalk, "A subscriber can try while the balance is unknown; the server decides")

        serverBalance = balance(plan: "yearly", planLeft: 0)
        await model.refresh()
        XCTAssertFalse(model.canTalk, "Out of minutes")
    }

    func testBuyingAPlanRefreshesWhatTheUserHas() async {
        let store = FakeStore()
        store.subscribesOnPurchase = PremiumPlan.yearly.productID
        let model = PremiumModel(store: store) { _ in self.balance(plan: "trial", planLeft: 600) }
        await model.load()
        XCTAssertFalse(model.isSubscribed)

        let bought = await model.purchase(PremiumPlan.yearly.productID)
        XCTAssertTrue(bought)
        XCTAssertEqual(model.status, .idle)
        XCTAssertTrue(model.isSubscribed)
        XCTAssertEqual(model.balance?.plan, "trial")
    }

    func testCancelledPendingAndFailedPurchases() async {
        let store = FakeStore()
        let model = PremiumModel(store: store) { _ in self.balance(plan: nil, planLeft: 0) }
        await model.load()

        store.outcome = .success(.cancelled)
        var bought = await model.purchase(PremiumPlan.weekly.productID)
        XCTAssertFalse(bought)
        XCTAssertEqual(model.status, .idle)

        store.outcome = .success(.pending)
        bought = await model.purchase(PremiumPlan.weekly.productID)
        XCTAssertFalse(bought)
        XCTAssertEqual(model.status, .pending)

        store.outcome = .failure(Failure())
        bought = await model.purchase(PremiumPlan.weekly.productID)
        XCTAssertFalse(bought)
        XCTAssertEqual(model.status, .failed("The store is down."))

        // A product the store didn't return can't be bought.
        bought = await model.purchase(MinutePack.all[2].productID)
        XCTAssertFalse(bought)
        XCTAssertEqual(store.purchased.count, 3)
    }

    func testRestoringPurchases() async {
        let store = FakeStore()
        let model = PremiumModel(store: store) { _ in self.balance(plan: nil, planLeft: 0) }
        await model.restore()
        XCTAssertTrue(store.restored)
        XCTAssertEqual(model.status, .idle)
    }

    func testWithoutAStoreNothingHappens() async {
        let model = PremiumModel(store: nil) { _ in
            XCTFail("Tests never reach the server")
            return self.balance(plan: nil, planLeft: 0)
        }
        await model.load()
        let bought = await model.purchase(PremiumPlan.yearly.productID)
        XCTAssertFalse(bought)
        XCTAssertNil(model.balance)
        let userID = await model.premiumUserID()
        XCTAssertNil(userID)
    }

    // MARK: Server

    func testTheBalanceRequestIdentifiesTheAppAndDecodes() throws {
        let request = PremiumAPI.balanceRequest(userID: "$RCAnonymousID:abc")
        XCTAssertEqual(request.url?.absoluteString, "https://scowld.xyz/api/premium/balance")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Scowld-User"), "$RCAnonymousID:abc")
        XCTAssertNil(request.url?.query)

        let json = #"{"plan":"yearly","planMinutes":50,"planSecondsLeft":1830,"planRenewsAt":"2026-11-16T10:30:00.000Z","packSecondsLeft":1200}"#
        let decoded = try PremiumAPI.decodeBalance(Data(json.utf8))
        XCTAssertEqual(decoded.plan, "yearly")
        XCTAssertEqual(decoded.minutesLeft, 50)
        XCTAssertEqual(decoded.planRenewsAt, ISO8601DateFormatter().date(from: "2026-11-16T10:30:00Z"))

        let empty = try PremiumAPI.decodeBalance(Data(#"{"plan":null,"planMinutes":0,"planSecondsLeft":0,"planRenewsAt":null,"packSecondsLeft":0}"#.utf8))
        XCTAssertNil(empty.plan)
        XCTAssertFalse(empty.canTalk)
    }

    func testFetchingTheBalanceUsesTheServer() async throws {
        StubURLProtocol.install { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Scowld-User"), "$RCAnonymousID:abc")
            return .json(["plan": "weekly", "planMinutes": 20, "planSecondsLeft": 300, "planRenewsAt": "2026-10-20T00:00:00Z", "packSecondsLeft": 0])
        }
        addTeardownBlock { StubURLProtocol.uninstall() }
        let balance = try await PremiumAPI.fetchBalance(userID: "$RCAnonymousID:abc")
        XCTAssertEqual(balance.minutesLeft, 5)

        StubURLProtocol.install { _ in .json(["error": "unavailable"], status: 503) }
        do {
            _ = try await PremiumAPI.fetchBalance(userID: "$RCAnonymousID:abc")
            XCTFail("A server error is reported")
        } catch {}
    }

    // MARK: Connection

    func testNewUsersStartWithPremiumAndKeyHoldersKeepTheirKey() {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { defaults.restore() }

        XCTAssertEqual(HostedServiceConfig.liveMode(hasSavedKey: { _ in false }), .premium)
        XCTAssertEqual(HostedServiceConfig.liveMode(hasSavedKey: { $0 == .xai }), .ownKey)

        UserDefaults.standard.set(LiveMode.premium.rawValue, forKey: HostedServiceConfig.liveModeDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.liveMode(hasSavedKey: { _ in true }), .premium, "A chosen mode is kept")
        UserDefaults.standard.set("nonsense", forKey: HostedServiceConfig.liveModeDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.liveMode(hasSavedKey: { _ in false }), .premium)
    }

    func testCatalogMatchesScowldsServer() {
        // web/src/premium.js holds the same products and minutes.
        XCTAssertEqual(PremiumPlan.weekly.productID, "com.apoorvdarshan.Scowld.premium.weekly")
        XCTAssertEqual(PremiumPlan.yearly.productID, "com.apoorvdarshan.Scowld.premium.yearly")
        XCTAssertEqual(PremiumPlan.weekly.minutes, 20)
        XCTAssertEqual(PremiumPlan.yearly.minutes, 50)
        XCTAssertEqual(PremiumPlan.trialMinutes, 10)
        XCTAssertEqual(MinutePack.all.map(\.minutes), [20, 60, 150])
        XCTAssertEqual(MinutePack.all.map(\.productID), [
            "com.apoorvdarshan.Scowld.minutes.20",
            "com.apoorvdarshan.Scowld.minutes.60",
            "com.apoorvdarshan.Scowld.minutes.150",
        ])
    }
}
