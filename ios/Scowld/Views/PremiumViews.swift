import SwiftUI

/// Which Premium screen to show.
enum PremiumSheet: String, Identifiable {
    case paywall
    case minutes

    var id: String { rawValue }
}

// MARK: - Paywall

/// Scowld Premium plans: yearly (with the free trial, chosen by default) and weekly.
struct PremiumPaywallView: View {
    @Environment(PremiumModel.self) private var premium
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selected: PremiumPlan = .yearly
    /// Switches to the user's own API key and shows Settings.
    var onUseOwnKey: (() -> Void)?

    private let termsURL = URL(string: "https://scowld.xyz/terms")!
    private let privacyURL = URL(string: "https://scowld.xyz/privacy")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits
                    plans
                    purchaseButton
                    finePrint
                    links
                    if let onUseOwnKey {
                        Button {
                            dismiss()
                            onUseOwnKey()
                        } label: {
                            Text("Use my own API key instead")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("premium.ownKey")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("premium.close")
                }
            }
        }
        .task { await premium.load() }
        .onChange(of: premium.isSubscribed) {
            if premium.isSubscribed { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("ScowldLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text("Scowld Premium")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("premium.title")
            Text(String.localizedStringWithFormat(
                NSLocalizedString("Talk with %@ out loud. No API key, no setup.", comment: "Paywall subtitle"),
                CharacterPack.resolveCharacterName()
            ))
            .font(.headline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(spacing: 10) {
            benefit("waveform", "Natural live voice", "She hears you, answers in her own voice and lets you interrupt.")
            benefit("sparkles", "No API key needed", "Tap the mic and talk. Scowld takes care of the rest.")
            benefit("eye.fill", "She can see", "Turn on the camera and show her things.")
            benefit("plus.circle.fill", "Top up anytime", "Extra minutes never expire.")
        }
    }

    private func benefit(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.amicaBlue)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(PremiumPlan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: PremiumPlan) -> some View {
        let product = premium.products[plan.productID]
        let isSelected = selected == plan
        return Button {
            selected = plan
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.amicaBlue : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan == .yearly ? LocalizedStringKey("Yearly") : LocalizedStringKey("Weekly"))
                            .font(.headline)
                        if plan == .yearly {
                            Text(trialDays(product).map { String.localizedStringWithFormat(NSLocalizedString("%d-day free trial", comment: "Trial badge"), $0) }
                                ?? NSLocalizedString("Best value", comment: "Plan badge"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.amicaBlue.opacity(0.22), in: Capsule())
                                .foregroundStyle(Color.amicaBlue)
                        }
                    }
                    Text(planDetail(plan, product: product))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(product.map { planPrice(plan, price: $0.localizedPrice) } ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            .padding(16)
            .background(.white.opacity(isSelected ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.amicaBlue : .white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("premium.plan.\(plan.rawValue)")
    }

    private func trialDays(_ product: PremiumProduct?) -> Int? {
        product?.freeTrialDays
    }

    private func planDetail(_ plan: PremiumPlan, product: PremiumProduct?) -> String {
        switch plan {
        case .yearly:
            let minutes = String.localizedStringWithFormat(NSLocalizedString("%d minutes a month", comment: "Plan minutes"), plan.minutes)
            guard let monthly = product?.localizedMonthlyPrice else { return minutes }
            return String.localizedStringWithFormat(NSLocalizedString("%@/month · %@", comment: "Yearly plan detail: monthly price, minutes"), monthly, minutes)
        case .weekly:
            return String.localizedStringWithFormat(NSLocalizedString("%d minutes a week", comment: "Plan minutes"), plan.minutes)
        }
    }

    private func planPrice(_ plan: PremiumPlan, price: String) -> String {
        switch plan {
        case .yearly: String.localizedStringWithFormat(NSLocalizedString("%@/year", comment: "Price per year"), price)
        case .weekly: String.localizedStringWithFormat(NSLocalizedString("%@/week", comment: "Price per week"), price)
        }
    }

    private var purchaseButton: some View {
        let product = premium.products[selected.productID]
        let isPurchasing = premium.status == .purchasing(selected.productID)
        let title = selected == .yearly && trialDays(product) != nil
            ? NSLocalizedString("Start Free Trial", comment: "Paywall button")
            : NSLocalizedString("Subscribe", comment: "Paywall button")
        return Button {
            Task { await premium.purchase(selected.productID) }
        } label: {
            ZStack {
                if isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(.black)
            .background(Color.amicaBlue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(product == nil || premium.isBusy)
        .opacity(product == nil ? 0.5 : 1)
        .accessibilityIdentifier("premium.subscribe")
    }

    @ViewBuilder
    private var finePrint: some View {
        let product = premium.products[selected.productID]
        VStack(spacing: 6) {
            if let product {
                Text(renewalTerms(product))
            } else {
                Text("Prices aren't available right now. Check your connection and try again.")
            }
            if case .failed(let message) = premium.status {
                Text(message).foregroundStyle(.red)
            } else if premium.status == .pending {
                Text("Your purchase is waiting for approval.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private func renewalTerms(_ product: PremiumProduct) -> String {
        switch selected {
        case .yearly:
            if let days = product.freeTrialDays {
                return String.localizedStringWithFormat(
                    NSLocalizedString("Free for %d days with %d minutes, then %@ a year. Renews automatically until canceled. Cancel anytime in Settings at least 24 hours before the trial ends.", comment: "Yearly trial terms"),
                    days, PremiumPlan.trialMinutes, product.localizedPrice
                )
            }
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ a year. Renews automatically until canceled. Cancel anytime in Settings at least 24 hours before it renews.", comment: "Yearly terms"),
                product.localizedPrice
            )
        case .weekly:
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ a week. Renews automatically until canceled. Cancel anytime in Settings at least 24 hours before it renews.", comment: "Weekly terms"),
                product.localizedPrice
            )
        }
    }

    private var links: some View {
        HStack(spacing: 18) {
            Button("Restore Purchases") {
                Task { await premium.restore() }
            }
            .accessibilityIdentifier("premium.restore")
            Button("Terms") { openURL(termsURL) }
            Button("Privacy") { openURL(privacyURL) }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .disabled(premium.isBusy)
    }
}

// MARK: - Minute packs

/// Extra minutes, bought once. They never expire and are used after the plan's minutes.
struct MinutePacksView: View {
    @Environment(PremiumModel.self) private var premium
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(MinutePack.all) { pack in
                        packRow(pack)
                    }
                } header: {
                    if let balance = premium.balance {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Minutes left: %d", comment: "Premium minutes left"), balance.minutesLeft))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Extra minutes never expire. They're used after your plan's minutes run out.")
                        if case .failed(let message) = premium.status {
                            Text(message).foregroundStyle(.red)
                        } else if premium.status == .pending {
                            Text("Your purchase is waiting for approval.")
                        }
                    }
                }
            }
            .navigationTitle("More Minutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await premium.load() }
    }

    private func packRow(_ pack: MinutePack) -> some View {
        let product = premium.products[pack.productID]
        return HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(Color.amicaBlue)
            Text(String.localizedStringWithFormat(NSLocalizedString("%d minutes", comment: "Minute pack"), pack.minutes))
                .font(.body.weight(.medium))
            Spacer()
            Button {
                Task { await premium.purchase(pack.productID) }
            } label: {
                if premium.status == .purchasing(pack.productID) {
                    ProgressView()
                } else {
                    Text(product?.localizedPrice ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.amicaBlue.opacity(0.2), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(product == nil || premium.isBusy)
            .accessibilityIdentifier("premium.pack.\(pack.minutes)")
        }
    }
}
