import Foundation
import Observation
import StoreKit

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

    private(set) var products: [Product] = []
    private(set) var activeSubscriptionProductID: String?
    private(set) var subscriptionCreditsRemaining = 0
    private(set) var extraCreditsRemaining = 0
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var lastPurchaseState: BillingPurchaseState?
    var errorMessage: String?

    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var processedTransactionIDs = Set<String>()
    @ObservationIgnored private var subscriptionRefillStart: Date?

    init() {
        loadLocalLedger()
        applyWeeklyRefillIfNeeded()
    }

    deinit {
        transactionUpdatesTask?.cancel()
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

    func start() async {
        guard !hasStarted else {
            applyWeeklyRefillIfNeeded()
            return
        }

        hasStarted = true
        listenForTransactionUpdates()
        await reloadProductsAndEntitlements()
    }

    func reloadProductsAndEntitlements() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func product(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    func displayPrice(for plan: ScowldSubscriptionPlan) -> String {
        product(for: plan.productID)?.displayPrice ?? plan.displayPrice
    }

    func displayPrice(for pack: ScowldCreditPack) -> String {
        product(for: pack.productID)?.displayPrice ?? pack.displayPrice
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
        guard let product = product(for: productID) else {
            errorMessage = "This purchase is not available yet. Check App Store Connect product setup."
            return
        }

        isPurchasing = true
        errorMessage = nil
        lastPurchaseState = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await process(transaction: transaction)
                await transaction.finish()
                await refreshEntitlements()
                lastPurchaseState = .success
            case .userCancelled:
                lastPurchaseState = .cancelled
            case .pending:
                lastPurchaseState = .pending
            @unknown default:
                lastPurchaseState = .unknown
            }
        } catch {
            errorMessage = error.localizedDescription
            lastPurchaseState = .failed
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
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
            products = try await Product.products(for: ScowldMonetization.allProductIDs)
                .sorted { lhs, rhs in
                    productSortIndex(lhs.id) < productSortIndex(rhs.id)
                }
        } catch {
            errorMessage = error.localizedDescription
            products = []
        }
    }

    private func refreshEntitlements() async {
        var activeSubscriptions: [Transaction] = []

        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement),
                  transaction.revocationDate == nil,
                  Self.subscriptionPlan(forProductID: transaction.productID) != nil
            else {
                continue
            }

            if let expiration = transaction.expirationDate, expiration < Date() {
                continue
            }

            activeSubscriptions.append(transaction)
        }

        let selectedSubscription = activeSubscriptions.max { lhs, rhs in
            subscriptionRank(lhs.productID) < subscriptionRank(rhs.productID)
        }

        setActiveSubscription(productID: selectedSubscription?.productID)
        applyWeeklyRefillIfNeeded()
        saveLocalLedger()
    }

    private func listenForTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionUpdate: update)
            }
        }
    }

    private func handle(transactionUpdate update: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(update)
            await process(transaction: transaction)
            await transaction.finish()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func process(transaction: Transaction) async {
        if let pack = Self.creditPack(forProductID: transaction.productID) {
            addExtraCreditsIfNeeded(pack.credits, transactionID: transaction.id)
            return
        }

        if Self.subscriptionPlan(forProductID: transaction.productID) != nil {
            setActiveSubscription(productID: transaction.productID)
        }
    }

    private func addExtraCreditsIfNeeded(_ credits: Int, transactionID: UInt64) {
        let transactionKey = String(transactionID)
        guard !processedTransactionIDs.contains(transactionKey) else { return }

        processedTransactionIDs.insert(transactionKey)
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

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw BillingError.unverifiedTransaction
        }
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
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .unverifiedTransaction:
            "The App Store could not verify this purchase."
        }
    }
}
