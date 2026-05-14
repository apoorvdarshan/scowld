import SwiftUI

struct PaywallView: View {
    @Environment(BillingStore.self) private var billingStore
    @Environment(\.dismiss) private var dismiss

    var reason: String?
    var showsCloseButton = true
    var title = "Scowld Plus"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    creditBalance
                    subscriptionSection
                    extraCreditsSection
                    usagePolicySection
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task { await billingStore.restorePurchases() }
                    }
                    .disabled(billingStore.isPurchasing)
                }
            }
            .task {
                await billingStore.start()
            }
        }
        .interactiveDismissDisabled(!showsCloseButton)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice credits")
                .font(.largeTitle.bold())
            Text(reason ?? ScowldMonetization.voiceCreditDefinition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var creditBalance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Available now", systemImage: "bolt.circle.fill")
                .font(.headline)

            HStack(spacing: 12) {
                balanceTile("Subscription", value: billingStore.subscriptionCreditsRemaining)
                balanceTile("Extra", value: billingStore.extraCreditsRemaining)
                balanceTile("Total", value: billingStore.totalCreditsRemaining)
            }

            if let plan = billingStore.activeSubscriptionPlan {
                Text("Active: \(plan.title), refills \(plan.refillDescription).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Subscribe for weekly refills, or buy extra credits for one-time use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = billingStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sectionCard()
    }

    private func balanceTile(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Subscriptions", systemImage: "creditcard.fill")
                .font(.headline)

            ForEach(ScowldMonetization.subscriptionPlans) { plan in
                purchaseRow(
                    title: plan.title,
                    subtitle: "\(plan.includedCredits) credits included, \(plan.refillDescription)",
                    price: billingStore.displayPrice(for: plan),
                    productID: plan.productID,
                    isActive: billingStore.activeSubscriptionProductID == plan.productID
                )
            }
        }
        .sectionCard()
    }

    private var extraCreditsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Extra Credits", systemImage: "plus.circle.fill")
                .font(.headline)

            ForEach(ScowldMonetization.extraCreditPacks) { pack in
                purchaseRow(
                    title: "\(pack.credits) credits",
                    subtitle: "One-time pack. Uses after subscription credits.",
                    price: billingStore.displayPrice(for: pack),
                    productID: pack.productID,
                    isActive: false
                )
            }
        }
        .sectionCard()
    }

    private var usagePolicySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Limits", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            Text("Each voice turn uses one credit. Extra credits bypass weekly refill limits, but one active reply, audio length, and reply length limits still apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sectionCard()
    }

    private func purchaseRow(
        title: String,
        subtitle: String,
        price: String,
        productID: String,
        isActive: Bool
    ) -> some View {
        Button {
            Task {
                await billingStore.purchase(productID: productID)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isActive {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.amicaBlue)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Text(isActive ? "Active" : price)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? .amicaBlue : .primary)
            }
            .padding(14)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isActive || billingStore.isPurchasing || billingStore.product(for: productID) == nil)
        .opacity(billingStore.product(for: productID) == nil && !isActive ? 0.55 : 1)
    }
}

private extension View {
    func sectionCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}
