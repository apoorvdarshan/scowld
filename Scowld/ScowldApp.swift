import SwiftUI

@main
struct ScowldApp: App {
    @State private var memoryStore = MemoryStore()

    var body: some Scene {
        WindowGroup {
            HomeView(memoryStore: memoryStore)
                .preferredColorScheme(.dark)
        }
    }
}
