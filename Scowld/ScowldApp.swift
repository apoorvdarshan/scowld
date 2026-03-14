import SwiftUI

@main
struct ScowldApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}
