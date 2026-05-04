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

            SettingsView(memoryStore: memoryStore, showsDismissControls: false)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(ScowldTab.settings)
        }
    }
}
