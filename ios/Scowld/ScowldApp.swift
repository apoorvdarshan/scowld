import SwiftUI

@main
struct ScowldApp: App {
    @State private var memoryStore = MemoryStore()
    @State private var billingStore = BillingStore()

    var body: some Scene {
        WindowGroup {
            ScowldRootView(memoryStore: memoryStore)
                .environment(billingStore)
                .preferredColorScheme(.dark)
                .task {
                    await billingStore.start()
                }
        }
    }
}

private enum ScowldTab: Hashable {
    case chat
    case pastChats
    case settings
    case about
}

struct ScowldRootView: View {
    var memoryStore: MemoryStore
    @State private var selectedTab: ScowldTab = .chat

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(memoryStore: memoryStore, isActive: selectedTab == .chat)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(ScowldTab.chat)

            NavigationStack {
                MemoryView(memoryStore: memoryStore)
            }
            .tabItem {
                Label("Chats", systemImage: "text.bubble.fill")
            }
            .tag(ScowldTab.pastChats)

            SettingsView(showsDismissControls: false)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(ScowldTab.settings)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(ScowldTab.about)
        }
    }
}

struct AboutView: View {
    @Environment(BillingStore.self) private var billingStore
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Scowld")
                            .fontWeight(.medium)
                        Spacer()
                        Text("v1.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://scowld.xyz/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://scowld.xyz/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Manage Billing", systemImage: "creditcard")
                    }

                    HStack {
                        Text("Credits Available")
                        Spacer()
                        Text("\(billingStore.totalCreditsRemaining)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Label("Billing", systemImage: "bolt.circle")
                }

                Section {
                    Text("Open Source AI Assistant - MIT License")
                        .foregroundStyle(.secondary)
                    Text("Character model: Arbius AI (MIT)")
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Credits", systemImage: "doc.plaintext")
                }

                Section {
                    Text(ScowldMonetization.voiceCreditDefinition)
                        .foregroundStyle(.secondary)

                    ForEach(ScowldMonetization.subscriptionPlans) { plan in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(plan.title)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(plan.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(plan.includedCredits) credits included - \(plan.refillDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Subscriptions", systemImage: "creditcard")
                } footer: {
                    Text("Subscription credits refill weekly. Extra credits can be used after the weekly refill is consumed.")
                }

                Section {
                    ForEach(ScowldMonetization.extraCreditPacks) { pack in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(pack.credits) credits")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(pack.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("Extra Credits", systemImage: "plus.circle")
                } footer: {
                    Text("Extra credits bypass the weekly subscription refill, but not safety limits like one active reply at a time.")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: "Manage subscription and extra voice credits.")
            }
        }
    }
}
