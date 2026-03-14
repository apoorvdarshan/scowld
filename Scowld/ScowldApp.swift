import SwiftUI

@main
struct ScowldApp: App {
    @State private var memoryStore = MemoryStore()

    var body: some Scene {
        WindowGroup {
            MainTabView(memoryStore: memoryStore)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    var memoryStore: MemoryStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "bird.fill", value: 0) {
                HomeView(memoryStore: memoryStore)
            }

            Tab("Memories", systemImage: "brain.head.profile.fill", value: 1) {
                NavigationStack {
                    MemoryView(memoryStore: memoryStore)
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                SettingsView(memoryStore: memoryStore)
            }
        }
        .tint(.orange)
    }
}
