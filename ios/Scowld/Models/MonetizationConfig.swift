import Foundation

enum ScowldMonetization {
    static let voiceCreditDefinition = "1 credit = 1 full voice turn"
    static let reservedCostPerCreditUSD = 0.08

    static let subscriptionPlans: [ScowldSubscriptionPlan] = [
        ScowldSubscriptionPlan(
            id: "weekly",
            productID: "scowld.sub.weekly",
            title: "Weekly",
            displayPrice: "$9.99",
            includedCredits: 40,
            refillDescription: "40 credits/week"
        ),
        ScowldSubscriptionPlan(
            id: "monthly",
            productID: "scowld.sub.monthly",
            title: "Monthly",
            displayPrice: "$34.99",
            includedCredits: 180,
            refillDescription: "45 credits/week"
        ),
        ScowldSubscriptionPlan(
            id: "yearly",
            productID: "scowld.sub.yearly",
            title: "Yearly",
            displayPrice: "$299.99",
            includedCredits: 2_340,
            refillDescription: "45 credits/week"
        ),
    ]

    static let extraCreditPacks: [ScowldCreditPack] = [
        ScowldCreditPack(id: "credits_10", productID: "scowld.credits.10", credits: 10, displayPrice: "$3.99"),
        ScowldCreditPack(id: "credits_50", productID: "scowld.credits.50", credits: 50, displayPrice: "$14.99"),
        ScowldCreditPack(id: "credits_100", productID: "scowld.credits.100", credits: 100, displayPrice: "$27.99"),
        ScowldCreditPack(id: "credits_200", productID: "scowld.credits.200", credits: 200, displayPrice: "$49.99"),
        ScowldCreditPack(id: "credits_500", productID: "scowld.credits.500", credits: 500, displayPrice: "$119.99"),
    ]

    static let usagePolicy = ScowldUsagePolicy(
        maxInputAudioSeconds: 20,
        maxTTSCharactersPerReply: 700,
        maxActiveRequests: 1,
        maxRepliesPerTenMinutes: 15,
        extraCreditsBypassSubscriptionRefill: true
    )

    static var allProductIDs: [String] {
        subscriptionPlans.map(\.productID) + extraCreditPacks.map(\.productID)
    }
}

struct ScowldSubscriptionPlan: Identifiable, Hashable {
    let id: String
    let productID: String
    let title: String
    let displayPrice: String
    let includedCredits: Int
    let refillDescription: String
}

struct ScowldCreditPack: Identifiable, Hashable {
    let id: String
    let productID: String
    let credits: Int
    let displayPrice: String
}

struct ScowldUsagePolicy: Hashable {
    let maxInputAudioSeconds: Int
    let maxTTSCharactersPerReply: Int
    let maxActiveRequests: Int
    let maxRepliesPerTenMinutes: Int
    let extraCreditsBypassSubscriptionRefill: Bool
}
