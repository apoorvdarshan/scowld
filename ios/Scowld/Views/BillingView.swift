import StoreKit
import SwiftUI
import UIKit

struct BillingView: View {
    @Environment(BillingStore.self) private var billingStore
    @Environment(\.openURL) private var openURL
    @State private var managementError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    subscriptionStatus
                    creditBalance
                    extraCreditsSection
                    usagePolicy
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .navigationTitle("Billing")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await billingStore.start()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("ScowldLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Manage Billing")
                    .font(.title2.bold())
                Text("Subscription status, credits, and extra credit packs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subscriptionStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Current Subscription", systemImage: "checkmark.seal.fill")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(activeSubscriptionTitle)
                        .font(.title3.bold())
                    Text(activeSubscriptionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(billingStore.hasActiveSubscription ? "Active" : "Inactive")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Button {
                Task { await openSubscriptionManagement() }
            } label: {
                HStack {
                    Label("Manage Subscription", systemImage: "arrow.up.forward.app.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
                .padding(14)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if let message = managementError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .billingSectionCard()
    }

    private var creditBalance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Credits", systemImage: "bolt.circle.fill")
                .font(.headline)

            HStack(spacing: 12) {
                balanceTile("Subscription", value: billingStore.subscriptionCreditsRemaining)
                balanceTile("Extra", value: billingStore.extraCreditsRemaining)
                balanceTile("Total", value: billingStore.totalCreditsRemaining)
            }

            Text("Each voice conversation turn uses one credit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .billingSectionCard()
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
            Label("Buy Extra Credits", systemImage: "plus.circle.fill")
                .font(.headline)

            ForEach(ScowldMonetization.extraCreditPacks) { pack in
                extraCreditRow(pack)
            }

            if let message = billingStore.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .billingSectionCard()
    }

    private func extraCreditRow(_ pack: ScowldCreditPack) -> some View {
        Button {
            Task { await billingStore.purchase(productID: pack.productID) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pack.credits) credits")
                        .font(.headline)
                    Text("One-time pack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(billingStore.displayPrice(for: pack))
                    .font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(billingStore.isPurchasing)
    }

    private var usagePolicy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Usage", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            Text("Extra credits are used after subscription credits. One active reply, audio length, and reply length limits still apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .billingSectionCard()
    }

    private var activeSubscriptionTitle: String {
        billingStore.activeSubscriptionPlan?.title ?? "No active subscription"
    }

    private var activeSubscriptionSubtitle: String {
        guard let plan = billingStore.activeSubscriptionPlan else {
            return "Open Apple subscription management to subscribe, cancel, or change plans."
        }

        return "\(plan.includedCredits) credits included, \(plan.refillDescription)"
    }

    private var statusColor: Color {
        billingStore.hasActiveSubscription ? .amicaBlue : .secondary
    }

    private func openSubscriptionManagement() async {
        managementError = nil

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await billingStore.reloadProductsAndEntitlements()
        } catch {
            managementError = error.localizedDescription
        }
    }
}

private extension View {
    func billingSectionCard() -> some View {
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
