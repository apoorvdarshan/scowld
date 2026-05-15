import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class BillingStore {
    private enum Keys {
        static let activeSubscriptionProductID = "billing_active_subscription_product_id"
        static let subscriptionCreditsRemaining = "billing_subscription_credits_remaining"
        static let subscriptionRefillStart = "billing_subscription_refill_start"
        static let extraCreditsRemaining = "billing_extra_credits_remaining"
        static let processedTransactionIDs = "billing_processed_transaction_ids"
    }

    private let refillInterval: TimeInterval = 7 * 24 * 60 * 60

    private(set) var products: [StoreProduct] = []
    private(set) var activeSubscriptionProductID: String?
    private(set) var subscriptionCreditsRemaining = 0
    private(set) var extraCreditsRemaining = 0
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var hasLoadedEntitlements = false
    private(set) var lastPurchaseState: BillingPurchaseState?
    var errorMessage: String?

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var processedTransactionIDs = Set<String>()
    @ObservationIgnored private var subscriptionRefillStart: Date?
    @ObservationIgnored private var revenueCatConfig: RevenueCatBillingConfig?

    init() {
        loadLocalLedger()
        applyWeeklyRefillIfNeeded()
    }

    var totalCreditsRemaining: Int {
        subscriptionCreditsRemaining + extraCreditsRemaining
    }

    var canSpendVoiceCredit: Bool {
        totalCreditsRemaining > 0
    }

    var activeSubscriptionPlan: ScowldSubscriptionPlan? {
        guard let activeSubscriptionProductID else { return nil }
        return Self.subscriptionPlan(forProductID: activeSubscriptionProductID)
    }

    var hasActiveSubscription: Bool {
        activeSubscriptionPlan != nil
    }

    var hasPaidAccess: Bool {
        hasActiveSubscription || totalCreditsRemaining > 0
    }

    func start() async {
        guard !hasStarted else {
            applyWeeklyRefillIfNeeded()
            return
        }

        hasStarted = true
        await reloadProductsAndEntitlements()
    }

    func reloadProductsAndEntitlements() async {
        hasLoadedEntitlements = false
        await loadProducts()
        await refreshEntitlements()
        hasLoadedEntitlements = true
    }

    func product(for productID: String) -> StoreProduct? {
        products.first { $0.productIdentifier == productID }
    }

    func displayPrice(for plan: ScowldSubscriptionPlan) -> String {
        product(for: plan.productID)?.localizedPriceString ?? plan.displayPrice
    }

    func displayPrice(for pack: ScowldCreditPack) -> String {
        product(for: pack.productID)?.localizedPriceString ?? pack.displayPrice
    }

    @discardableResult
    func spendVoiceCredit() -> Bool {
        applyWeeklyRefillIfNeeded()

        if subscriptionCreditsRemaining > 0 {
            subscriptionCreditsRemaining -= 1
            saveLocalLedger()
            return true
        }

        if extraCreditsRemaining > 0 {
            extraCreditsRemaining -= 1
            saveLocalLedger()
            return true
        }

        return false
    }

    func purchase(productID: String) async {
        do {
            try await configureRevenueCatIfNeeded()
            if product(for: productID) == nil {
                await loadProducts()
            }
        } catch {
            errorMessage = error.localizedDescription
            lastPurchaseState = .failed
            return
        }

        guard let product = product(for: productID) else {
            errorMessage = "This purchase is not available yet. Check App Store Connect and RevenueCat product setup."
            lastPurchaseState = .failed
            return
        }

        isPurchasing = true
        errorMessage = nil
        lastPurchaseState = nil
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(product: product)
            if result.userCancelled {
                lastPurchaseState = .cancelled
                return
            }

            if let pack = Self.creditPack(forProductID: productID) {
                let transactionID = result.transaction?.transactionIdentifier ?? UUID().uuidString
                addExtraCreditsIfNeeded(pack.credits, transactionID: transactionID)
            }

            apply(customerInfo: result.customerInfo)
            lastPurchaseState = .success
        } catch {
            #if DEBUG
            if let pack = Self.creditPack(forProductID: productID),
               Self.isStoreKitReceiptMissingPurchasedProductError(error) {
                addExtraCreditsIfNeeded(pack.credits, transactionID: "debug-\(productID)-\(UUID().uuidString)")
                errorMessage = nil
                lastPurchaseState = .success
                return
            }
            #endif

            errorMessage = error.localizedDescription
            lastPurchaseState = .failed
        }
    }

    func restorePurchases() async {
        errorMessage = nil

        do {
            try await configureRevenueCatIfNeeded()
            let customerInfo = try await Purchases.shared.restorePurchases()
            apply(customerInfo: customerInfo)
            lastPurchaseState = .restored
        } catch {
            errorMessage = error.localizedDescription
            lastPurchaseState = .failed
        }
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            try await configureRevenueCatIfNeeded()
            products = await Purchases.shared.products(ScowldMonetization.allProductIDs)
                .sorted { lhs, rhs in
                    productSortIndex(lhs.productIdentifier) < productSortIndex(rhs.productIdentifier)
                }
        } catch {
            errorMessage = error.localizedDescription
            products = []
        }
    }

    private func refreshEntitlements() async {
        do {
            try await configureRevenueCatIfNeeded()
            let customerInfo = try await Purchases.shared.customerInfo()
            apply(customerInfo: customerInfo)
        } catch {
            errorMessage = error.localizedDescription
            setActiveSubscription(productID: nil)
        }

        applyWeeklyRefillIfNeeded()
        saveLocalLedger()
    }

    private func configureRevenueCatIfNeeded() async throws {
        if revenueCatConfig != nil, Purchases.isConfigured {
            return
        }

        let config = try await loadRevenueCatConfig()
        revenueCatConfig = config

        guard !Purchases.isConfigured else { return }

        guard let apiKey = config.iosApiKey else {
            throw BillingError.revenueCatNotConfigured
        }

        Purchases.configure(withAPIKey: apiKey)
    }

    private func loadRevenueCatConfig() async throws -> RevenueCatBillingConfig {
        var request = URLRequest(url: HostedServiceConfig.billingConfigURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BillingError.invalidBillingConfigResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BillingError.billingConfigRequestFailed(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(HostedBillingConfigResponse.self, from: data)
        guard var revenueCat = decoded.revenueCat else {
            throw BillingError.revenueCatNotConfigured
        }

        revenueCat.iosApiKey = (revenueCat.iosApiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        revenueCat.entitlementID = revenueCat.entitlementID.trimmingCharacters(in: .whitespacesAndNewlines)
        revenueCat.offeringID = revenueCat.offeringID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !(revenueCat.iosApiKey ?? "").isEmpty else {
            throw BillingError.revenueCatNotConfigured
        }

        if revenueCat.entitlementID.isEmpty {
            revenueCat.entitlementID = RevenueCatBillingConfig.defaultEntitlementID
        }

        if revenueCat.offeringID.isEmpty {
            revenueCat.offeringID = RevenueCatBillingConfig.defaultOfferingID
        }

        return revenueCat
    }

    private func apply(customerInfo: CustomerInfo) {
        let entitlementID = revenueCatConfig?.entitlementID ?? RevenueCatBillingConfig.defaultEntitlementID
        if let entitlementProductID = customerInfo.entitlements.active[entitlementID]?.productIdentifier,
           Self.subscriptionPlan(forProductID: entitlementProductID) != nil {
            setActiveSubscription(productID: entitlementProductID)
        } else {
            let activeProductID = customerInfo.activeSubscriptions
                .filter { Self.subscriptionPlan(forProductID: $0) != nil }
                .max { lhs, rhs in
                    subscriptionRank(lhs) < subscriptionRank(rhs)
                }
            setActiveSubscription(productID: activeProductID)
        }

        applyWeeklyRefillIfNeeded()
        saveLocalLedger()
    }

    private func addExtraCreditsIfNeeded(_ credits: Int, transactionID: String) {
        guard !processedTransactionIDs.contains(transactionID) else { return }

        processedTransactionIDs.insert(transactionID)
        extraCreditsRemaining += credits
        saveLocalLedger()
    }

    private func setActiveSubscription(productID: String?) {
        guard activeSubscriptionProductID != productID else { return }

        activeSubscriptionProductID = productID
        subscriptionRefillStart = productID == nil ? nil : Date()
        subscriptionCreditsRemaining = productID.flatMap(Self.subscriptionPlan(forProductID:))?.weeklyRefillCredits ?? 0
        saveLocalLedger()
    }

    private func applyWeeklyRefillIfNeeded() {
        guard let plan = activeSubscriptionPlan else {
            subscriptionCreditsRemaining = 0
            subscriptionRefillStart = nil
            saveLocalLedger()
            return
        }

        let now = Date()
        guard let refillStart = subscriptionRefillStart else {
            subscriptionRefillStart = now
            subscriptionCreditsRemaining = plan.weeklyRefillCredits
            saveLocalLedger()
            return
        }

        let elapsed = now.timeIntervalSince(refillStart)
        guard elapsed >= refillInterval else { return }

        let periods = max(1, Int(elapsed / refillInterval))
        subscriptionRefillStart = refillStart.addingTimeInterval(TimeInterval(periods) * refillInterval)
        subscriptionCreditsRemaining = plan.weeklyRefillCredits
        saveLocalLedger()
    }

    private func loadLocalLedger() {
        let defaults = UserDefaults.standard
        activeSubscriptionProductID = defaults.string(forKey: Keys.activeSubscriptionProductID)
        subscriptionCreditsRemaining = max(0, defaults.integer(forKey: Keys.subscriptionCreditsRemaining))
        extraCreditsRemaining = max(0, defaults.integer(forKey: Keys.extraCreditsRemaining))
        subscriptionRefillStart = defaults.object(forKey: Keys.subscriptionRefillStart) as? Date
        processedTransactionIDs = Set(defaults.stringArray(forKey: Keys.processedTransactionIDs) ?? [])
    }

    private func saveLocalLedger() {
        let defaults = UserDefaults.standard
        defaults.set(activeSubscriptionProductID, forKey: Keys.activeSubscriptionProductID)
        defaults.set(subscriptionCreditsRemaining, forKey: Keys.subscriptionCreditsRemaining)
        defaults.set(extraCreditsRemaining, forKey: Keys.extraCreditsRemaining)
        defaults.set(subscriptionRefillStart, forKey: Keys.subscriptionRefillStart)
        defaults.set(Array(processedTransactionIDs), forKey: Keys.processedTransactionIDs)
    }

    private func productSortIndex(_ productID: String) -> Int {
        if let index = ScowldMonetization.subscriptionPlans.firstIndex(where: { $0.productID == productID }) {
            return index
        }
        if let index = ScowldMonetization.extraCreditPacks.firstIndex(where: { $0.productID == productID }) {
            return ScowldMonetization.subscriptionPlans.count + index
        }
        return Int.max
    }

    private func subscriptionRank(_ productID: String) -> Int {
        switch Self.subscriptionPlan(forProductID: productID)?.id {
        case "yearly": 3
        case "monthly": 2
        case "weekly": 1
        default: 0
        }
    }

    private static func subscriptionPlan(forProductID productID: String) -> ScowldSubscriptionPlan? {
        ScowldMonetization.subscriptionPlans.first { $0.productID == productID }
    }

    private static func creditPack(forProductID productID: String) -> ScowldCreditPack? {
        ScowldMonetization.extraCreditPacks.first { $0.productID == productID }
    }

    #if DEBUG
    private static func isStoreKitReceiptMissingPurchasedProductError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let message = [
            error.localizedDescription,
            nsError.localizedDescription,
            underlyingError?.localizedDescription,
        ]
            .compactMap(\.self)
            .joined(separator: " ")
            .lowercased()

        return message.contains("purchased product was missing in the receipt")
    }
    #endif
}

private struct HostedBillingConfigResponse: Decodable {
    let revenueCat: RevenueCatBillingConfig?
}

private struct RevenueCatBillingConfig: Decodable {
    static let defaultEntitlementID = "Scowld Plus"
    static let defaultOfferingID = "default"

    var iosApiKey: String?
    var entitlementID: String
    var offeringID: String
    let appStoreAppID: String?
    let isConfigured: Bool?
}

enum BillingPurchaseState: Equatable {
    case success
    case cancelled
    case pending
    case restored
    case failed
    case unknown
}

enum BillingError: LocalizedError {
    case invalidBillingConfigResponse
    case billingConfigRequestFailed(Int)
    case revenueCatNotConfigured

    var errorDescription: String? {
        switch self {
        case .invalidBillingConfigResponse:
            "Billing config returned an invalid response."
        case .billingConfigRequestFailed(let statusCode):
            "Billing config request failed with HTTP \(statusCode)."
        case .revenueCatNotConfigured:
            "RevenueCat is not configured on the billing backend."
        }
    }
}
