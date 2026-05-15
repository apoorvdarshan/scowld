import SwiftUI

struct PaywallView: View {
    @Environment(BillingStore.self) private var billingStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubscriptionProductID = "scowld.sub.monthly"

    var reason: String?
    var showsCloseButton = true
    var title = "Scowld Plus"
    var isStartupGate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    subscriptionSection
                    if !isStartupGate {
                        creditBalance
                        extraCreditsSection
                    }
                    usagePolicySection
                }
                .padding(20)
                .padding(.bottom, isStartupGate ? 120 : 96)
            }
            .navigationTitle(isStartupGate ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
            .task {
                await billingStore.start()
            }
        }
        .interactiveDismissDisabled(!showsCloseButton)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("ScowldLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .amicaBlue.opacity(0.35), radius: 18, y: 10)

            VStack(spacing: 6) {
                Text(isStartupGate ? "Unlock Scowld" : "Scowld Plus")
                    .font(.largeTitle.bold())
                Text(reason ?? "Pick a plan to unlock voice conversations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if billingStore.isLoadingProducts {
                ProgressView("Loading App Store products...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = billingStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, isStartupGate ? 12 : 0)
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Choose your plan", systemImage: "creditcard.fill")
                    .font(.headline)
                Text(ScowldMonetization.voiceCreditDefinition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(ScowldMonetization.subscriptionPlans) { plan in
                subscriptionPlanCard(
                    plan,
                    badge: subscriptionBadge(for: plan),
                    isActive: billingStore.activeSubscriptionProductID == plan.productID,
                    isSelected: selectedSubscriptionProductID == plan.productID
                )
            }

            Button {
                purchaseSelectedSubscription()
            } label: {
                HStack {
                    Text(selectedSubscriptionButtonTitle)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Color.amicaBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(billingStore.isPurchasing || selectedSubscriptionPlan == nil)
            .opacity(billingStore.isPurchasing || selectedSubscriptionPlan == nil ? 0.55 : 1)

            Text("Payments are handled by Apple. You can cancel or manage subscriptions from your Apple ID settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func subscriptionPlanCard(
        _ plan: ScowldSubscriptionPlan,
        badge: String?,
        isActive: Bool,
        isSelected: Bool
    ) -> some View {
        Button {
            selectedSubscriptionProductID = plan.productID
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plan.title)
                                .font(.title3.bold())

                            if let badge {
                                Text(badge)
                                    .font(.caption2.bold())
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.amicaBlue.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.amicaBlue)
                            }

                            if isActive {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.amicaBlue)
                            } else if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.amicaBlue)
                            }
                        }

                        Text("\(plan.includedCredits) credits included")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isActive ? "Active" : billingStore.displayPrice(for: plan))
                            .font(.title3.bold())
                            .foregroundStyle(isActive ? .amicaBlue : .primary)
                        Text(planPriceCadence(for: plan))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Label(plan.refillDescription, systemImage: "arrow.clockwise.circle.fill")
                    Spacer()
                    Label(isActive ? "Current plan" : selectionLabel(isSelected: isSelected), systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(planCardBackground(isSelected: isSelected))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Color.amicaBlue.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isActive)
        .padding(.horizontal, 1)
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

    private func subscriptionBadge(for plan: ScowldSubscriptionPlan) -> String? {
        switch plan.id {
        case "monthly": "Popular"
        case "yearly": "Best value"
        default: nil
        }
    }

    private func planPriceCadence(for plan: ScowldSubscriptionPlan) -> String {
        switch plan.id {
        case "weekly": "per week"
        case "monthly": "per month"
        case "yearly": "per year"
        default: ""
        }
    }

    private func planCardBackground(isSelected: Bool) -> some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.amicaBlue.opacity(0.14))
        }

        return AnyShapeStyle(Material.ultraThinMaterial)
    }

    private var selectedSubscriptionPlan: ScowldSubscriptionPlan? {
        ScowldMonetization.subscriptionPlans.first { $0.productID == selectedSubscriptionProductID }
    }

    private var selectedSubscriptionButtonTitle: String {
        guard let plan = selectedSubscriptionPlan else {
            return "Choose a plan"
        }

        return "Continue with \(plan.title)"
    }

    private func selectionLabel(isSelected: Bool) -> String {
        isSelected ? "Selected" : "Tap to select"
    }

    private func purchaseSelectedSubscription() {
        guard let selectedSubscriptionPlan else { return }
        Task {
            await billingStore.purchase(productID: selectedSubscriptionPlan.productID)
        }
    }

    private var usagePolicySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Limits", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            Text(usagePolicyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sectionCard()
    }

    private var usagePolicyText: String {
        if isStartupGate {
            return "Each voice turn uses one credit. Subscription credits refill weekly, with one active reply, audio length, and reply length limits still applied."
        }

        return "Each voice turn uses one credit. Extra credits bypass weekly refill limits, but one active reply, audio length, and reply length limits still apply."
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
        .disabled(isActive || billingStore.isPurchasing)
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
