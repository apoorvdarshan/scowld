import SwiftUI

@main
struct ScowldApp: App {
    @State private var memoryStore = MemoryStore()

    var body: some Scene {
        WindowGroup {
            ScowldRootView(memoryStore: memoryStore)
                .preferredColorScheme(.dark)
        }
    }
}

private enum ScowldTab: Hashable {
    case chat
    case memories
    case settings
    case about
}

struct ScowldRootView: View {
    var memoryStore: MemoryStore
    @State private var selectedTab: ScowldTab = .chat

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(memoryStore: memoryStore)
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(ScowldTab.chat)

            NavigationStack {
                MemoryView(memoryStore: memoryStore)
            }
            .tabItem {
                Label("Memories", systemImage: "brain.head.profile.fill")
            }
            .tag(ScowldTab.memories)

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

                    Link(destination: URL(string: "https://scowld.vercel.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://scowld.vercel.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
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
