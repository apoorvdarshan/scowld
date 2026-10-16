import Foundation
import Observation
import RevenueCat
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Premium")

// MARK: - Catalog

/// Scowld Premium plans: talk without an API key. Scowld's server
/// (web/src/premium.js) holds the same minutes and decides what each plan allows.
nonisolated enum PremiumPlan: String, CaseIterable, Identifiable, Sendable {
    case yearly
    case weekly

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .yearly: "com.apoorvdarshan.Scowld.premium.yearly"
        case .weekly: "com.apoorvdarshan.Scowld.premium.weekly"
        }
    }

    /// Minutes included each month (yearly) or each week (weekly).
    var minutes: Int {
        switch self {
        case .yearly: 50
        case .weekly: 20
        }
    }

    /// Minutes during the yearly plan's free trial.
    static let trialMinutes = 10
}

/// Extra minutes bought once. They never expire and are used after a plan's minutes.
nonisolated struct MinutePack: Identifiable, Equatable, Sendable {
    let productID: String
    let minutes: Int
    var id: String { productID }

    static let all: [MinutePack] = [
        MinutePack(productID: "com.apoorvdarshan.Scowld.minutes.20", minutes: 20),
        MinutePack(productID: "com.apoorvdarshan.Scowld.minutes.60", minutes: 60),
        MinutePack(productID: "com.apoorvdarshan.Scowld.minutes.150", minutes: 150),
    ]
}

/// The RevenueCat app user ID that identifies the app to Scowld's server, or nil
/// before RevenueCat is configured (and in tests).
nonisolated enum PremiumIdentity {
    static func currentUserID() -> String? {
        guard !ScowldTestEnvironment.isRunningTests, Purchases.isConfigured else { return nil }
        return Purchases.shared.appUserID
    }
}

/// How live conversations connect: through Scowld Premium, or straight to a
/// provider with the user's own API key.
nonisolated enum LiveMode: String, CaseIterable, Sendable {
    case premium
    case ownKey
}

// MARK: - Balance

/// The minutes left, as Scowld's server counts them.
nonisolated struct PremiumBalance: Decodable, Equatable, Sendable {
    /// "weekly", "yearly", "trial", or nil without an active plan.
    let plan: String?
    let planMinutes: Int
    let planSecondsLeft: Int
    let planRenewsAt: Date?
    let packSecondsLeft: Int

    var secondsLeft: Int { planSecondsLeft + packSecondsLeft }
    var minutesLeft: Int { secondsLeft / 60 }
    var canTalk: Bool { secondsLeft > 0 }
}

nonisolated enum PremiumAPI {
    static let balanceURL = URL(string: "https://scowld.xyz/api/premium/balance")!

    /// The app identifies itself with its RevenueCat app user ID. No key is involved.
    static func balanceRequest(userID: String) -> URLRequest {
        var request = URLRequest(url: balanceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(userID, forHTTPHeaderField: "X-Scowld-User")
        return request
    }

    static func decodeBalance(_ data: Data) throws -> PremiumBalance {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date"))
        }
        return try decoder.decode(PremiumBalance.self, from: data)
    }

    static func fetchBalance(userID: String, session: URLSession = .shared) async throws -> PremiumBalance {
        let (data, response) = try await session.data(for: balanceRequest(userID: userID))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decodeBalance(data)
    }
}

// MARK: - Store

/// A Premium product as the store sells it, priced for the user's storefront.
nonisolated struct PremiumProduct: Equatable, Sendable {
    let productID: String
    let localizedPrice: String
    /// The yearly price spread over 12 months, for comparison.
    let localizedMonthlyPrice: String?
    /// Days of free trial for a new subscriber, if the product offers one.
    let freeTrialDays: Int?
}

/// The store Premium talks to: RevenueCat in the app, a fake in tests.
nonisolated protocol PremiumStore: Sendable {
    func appUserID() async -> String?
    func products(_ productIDs: [String]) async -> [PremiumProduct]
    func purchase(_ productID: String) async throws -> TipPurchaseOutcome
    func restore() async throws
    func activeSubscriptions() async -> Set<String>
    func showManageSubscriptions() async
}

actor RevenueCatPremiumStore: PremiumStore {
    private var storeProducts: [String: StoreProduct] = [:]

    func appUserID() async -> String? {
        guard Purchases.isConfigured else { return nil }
        return Purchases.shared.appUserID
    }

    func products(_ productIDs: [String]) async -> [PremiumProduct] {
        guard Purchases.isConfigured else { return [] }
        let fetched = await Purchases.shared.products(productIDs)
        for product in fetched {
            storeProducts[product.productIdentifier] = product
        }
        return fetched.map { product in
            var monthly: String?
            if product.subscriptionPeriod?.unit == .year, let formatter = product.priceFormatter {
                monthly = formatter.string(from: (product.price / 12) as NSDecimalNumber)
            }
            var trialDays: Int?
            if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
                let period = intro.subscriptionPeriod
                switch period.unit {
                case .day: trialDays = period.value
                case .week: trialDays = period.value * 7
                default: trialDays = nil
                }
            }
            return PremiumProduct(
                productID: product.productIdentifier,
                localizedPrice: product.localizedPriceString,
                localizedMonthlyPrice: monthly,
                freeTrialDays: trialDays
            )
        }
    }

    func purchase(_ productID: String) async throws -> TipPurchaseOutcome {
        guard let product = storeProducts[productID] else { throw PremiumError.unavailable }
        do {
            let result = try await Purchases.shared.purchase(product: product)
            return result.userCancelled ? .cancelled : .completed
        } catch let error as RevenueCat.ErrorCode where error == .paymentPendingError {
            return .pending
        } catch let error as RevenueCat.ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        }
    }

    func restore() async throws {
        _ = try await Purchases.shared.restorePurchases()
    }

    func activeSubscriptions() async -> Set<String> {
        guard Purchases.isConfigured, let info = try? await Purchases.shared.customerInfo() else { return [] }
        return info.activeSubscriptions
    }

    func showManageSubscriptions() async {
        try? await Purchases.shared.showManageSubscriptions()
    }
}

nonisolated enum PremiumError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        NSLocalizedString("This purchase isn't available right now. Check your connection and try again.", comment: "Premium product unavailable")
    }
}

// MARK: - Model

/// Plans, prices and minutes left for the paywall, Settings and the Chat screen.
@MainActor
@Observable
final class PremiumModel {
    enum Status: Equatable {
        case idle
        case purchasing(String)
        case restoring
        case pending
        case failed(String)
    }

    private(set) var products: [String: PremiumProduct] = [:]
    private(set) var activeSubscriptions: Set<String> = []
    private(set) var balance: PremiumBalance?
    private(set) var userID: String?
    var status: Status = .idle

    /// `nil` while tests run, so nothing reaches the store or the server.
    @ObservationIgnored private let store: PremiumStore?
    @ObservationIgnored private let fetchBalance: (String) async throws -> PremiumBalance

    convenience init() {
        self.init(
            store: ScowldTestEnvironment.isRunningTests ? nil : RevenueCatPremiumStore(),
            fetchBalance: { try await PremiumAPI.fetchBalance(userID: $0) }
        )
    }

    init(store: PremiumStore?, fetchBalance: @escaping (String) async throws -> PremiumBalance) {
        self.store = store
        self.fetchBalance = fetchBalance
    }

    var isSubscribed: Bool {
        !activeSubscriptions.isDisjoint(with: PremiumPlan.allCases.map(\.productID))
    }

    var activePlan: PremiumPlan? {
        PremiumPlan.allCases.first { activeSubscriptions.contains($0.productID) }
    }

    var isBusy: Bool {
        switch status {
        case .purchasing, .restoring: true
        default: false
        }
    }

    /// Whether a Premium conversation can start: unknown counts as yes, so the
    /// server (which knows best) answers when the balance couldn't be loaded.
    var canTalk: Bool {
        balance?.canTalk ?? isSubscribed
    }

    func load() async {
        guard let store else { return }
        if products.isEmpty {
            let ids = PremiumPlan.allCases.map(\.productID) + MinutePack.all.map(\.productID)
            let fetched = await store.products(ids)
            products = Dictionary(fetched.map { ($0.productID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        await refresh()
    }

    /// Reloads the active subscriptions and the minutes left.
    func refresh() async {
        guard let store else { return }
        activeSubscriptions = await store.activeSubscriptions()
        await refreshBalance()
    }

    func refreshBalance() async {
        guard let store else { return }
        if userID == nil {
            userID = await store.appUserID()
        }
        guard let userID else { return }
        do {
            balance = try await fetchBalance(userID)
        } catch {
            logger.error("[Premium] Couldn't load the balance: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Buys a plan or a minute pack. Returns true once the purchase went through.
    @discardableResult
    func purchase(_ productID: String) async -> Bool {
        guard let store, products[productID] != nil, !isBusy else { return false }
        status = .purchasing(productID)
        do {
            switch try await store.purchase(productID) {
            case .completed:
                status = .idle
                await refresh()
                return true
            case .cancelled:
                status = .idle
            case .pending:
                status = .pending
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
        return false
    }

    func restore() async {
        guard let store, !isBusy else { return }
        status = .restoring
        do {
            try await store.restore()
            status = .idle
            await refresh()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func manageSubscription() async {
        await store?.showManageSubscriptions()
    }

    /// The RevenueCat app user ID that identifies this app to Scowld's server.
    func premiumUserID() async -> String? {
        if userID == nil {
            userID = await store?.appUserID()
        }
        return userID
    }
}
