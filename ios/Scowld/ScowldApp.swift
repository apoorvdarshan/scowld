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
    case billing
    case about
}

struct ScowldRootView: View {
    var memoryStore: MemoryStore
    @State private var selectedTab: ScowldTab = .chat
    @Environment(BillingStore.self) private var billingStore

    var body: some View {
        Group {
            if !billingStore.hasLoadedEntitlements {
                loadingBillingView
            } else if !billingStore.hasPaidAccess {
                PaywallView(
                    reason: "Choose a plan to start using Scowld.",
                    showsCloseButton: false,
                    title: "Scowld Plus",
                    isStartupGate: true
                )
            } else {
                appTabs
            }
        }
        .onChange(of: billingStore.hasPaidAccess) { _, hasPaidAccess in
            if hasPaidAccess {
                selectedTab = .chat
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBillingTab)) { _ in
            if billingStore.hasPaidAccess {
                selectedTab = .billing
            }
        }
    }

    private var appTabs: some View {
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

            BillingView()
            .tabItem {
                Label("Billing", systemImage: "creditcard.fill")
            }
            .tag(ScowldTab.billing)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(ScowldTab.about)
        }
    }

    private var loadingBillingView: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                ProgressView("Loading billing...")
            }
    }
}

struct AboutView: View {
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
                    Link(destination: URL(string: "https://www.linkedin.com/company/scowld")!) {
                        Label("LinkedIn", systemImage: "person.2.fill")
                    }

                    Link(destination: URL(string: "https://www.instagram.com/scowld_/")!) {
                        Label("Instagram", systemImage: "camera.fill")
                    }
                } header: {
                    Label("Social", systemImage: "link")
                }

                Section {
                    Text("Open Source AI Assistant - MIT License")
                        .foregroundStyle(.secondary)
                    Text("Character model: Arbius AI (MIT)")
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Credits", systemImage: "doc.plaintext")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
