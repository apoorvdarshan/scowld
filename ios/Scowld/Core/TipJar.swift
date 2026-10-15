import Foundation
import Observation
import RevenueCat

// MARK: - RevenueCat

/// Tips are tracked through Scowld's own RevenueCat project.
enum RevenueCatSetup {
    /// The Scowld App Store app's public SDK key. Public SDK keys are meant to ship in
    /// apps: they can read offerings and record purchases, not change the catalog.
    static let publicAPIKey = "appl_yFwHjxnttQhHaATjcIuehZBmcLy"

    /// Configures RevenueCat once at launch; tests never reach the store.
    static func configure() {
        guard !ScowldTestEnvironment.isRunningTests, !Purchases.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: publicAPIKey)
    }
}

// MARK: - Tiers

/// Optional one-time tips (consumable in-app purchases) that fund development.
/// They unlock nothing: Scowld stays free and open source.
nonisolated struct TipTier: Identifiable, Equatable, Sendable {
    let productID: String
    let name: String
    let systemImage: String
    var id: String { productID }

    static let all: [TipTier] = [
        TipTier(productID: "com.apoorvdarshan.Scowld.tip.small", name: "Small Tip", systemImage: "cup.and.saucer.fill"),
        TipTier(productID: "com.apoorvdarshan.Scowld.tip.medium", name: "Medium Tip", systemImage: "heart.fill"),
        TipTier(productID: "com.apoorvdarshan.Scowld.tip.large", name: "Large Tip", systemImage: "star.fill"),
        TipTier(productID: "com.apoorvdarshan.Scowld.tip.huge", name: "Huge Tip", systemImage: "sparkles"),
        TipTier(productID: "com.apoorvdarshan.Scowld.tip.giant", name: "Giant Tip", systemImage: "crown.fill"),
    ]
}

/// A tip as the store sells it, with the price localized for the user's storefront.
nonisolated struct TipProduct: Equatable, Sendable {
    let productID: String
    let localizedPrice: String
}

nonisolated enum TipPurchaseOutcome: Equatable, Sendable {
    case completed
    case cancelled
    /// Waiting for approval (Ask to Buy or a payment that needs action).
    case pending
}

// MARK: - Store

/// The store the tip jar talks to: RevenueCat in the app, a fake in tests.
nonisolated protocol TipStore: Sendable {
    func products(_ productIDs: [String]) async -> [TipProduct]
    func purchase(_ productID: String) async throws -> TipPurchaseOutcome
}

actor RevenueCatTipStore: TipStore {
    private var storeProducts: [String: StoreProduct] = [:]

    func products(_ productIDs: [String]) async -> [TipProduct] {
        guard Purchases.isConfigured else { return [] }
        let fetched = await Purchases.shared.products(productIDs)
        for product in fetched {
            storeProducts[product.productIdentifier] = product
        }
        return fetched.map { TipProduct(productID: $0.productIdentifier, localizedPrice: $0.localizedPriceString) }
    }

    func purchase(_ productID: String) async throws -> TipPurchaseOutcome {
        guard let product = storeProducts[productID] else { throw TipJarError.unavailable }
        do {
            let result = try await Purchases.shared.purchase(product: product)
            return result.userCancelled ? .cancelled : .completed
        } catch let error as RevenueCat.ErrorCode where error == .paymentPendingError {
            return .pending
        } catch let error as RevenueCat.ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        }
    }
}

nonisolated enum TipJarError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "This tip isn't available right now. Check your connection and try again."
    }
}

// MARK: - Model

@MainActor
@Observable
final class TipJarModel {
    enum Status: Equatable {
        case idle
        case purchasing(String)
        case thanks
        case pending
        case failed(String)
    }

    private(set) var products: [String: TipProduct] = [:]
    private(set) var isLoading = false
    var status: Status = .idle

    /// `nil` while tests run, so the tip jar never reaches the store.
    private let store: TipStore?

    convenience init() {
        self.init(store: ScowldTestEnvironment.isRunningTests ? nil : RevenueCatTipStore())
    }

    init(store: TipStore?) {
        self.store = store
    }

    var isPurchasing: Bool {
        if case .purchasing = status { return true }
        return false
    }

    func load() async {
        guard let store, products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let fetched = await store.products(TipTier.all.map(\.productID))
        products = Dictionary(fetched.map { ($0.productID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func purchase(_ tier: TipTier) async {
        guard let store, products[tier.productID] != nil, !isPurchasing else { return }
        status = .purchasing(tier.productID)
        do {
            switch try await store.purchase(tier.productID) {
            case .completed: status = .thanks
            case .cancelled: status = .idle
            case .pending: status = .pending
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
