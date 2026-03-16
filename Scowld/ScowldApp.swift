import SwiftUI

@main
struct ScowldApp: App {
    @State private var memoryStore = MemoryStore()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView(memoryStore: memoryStore)
                    .preferredColorScheme(.dark)

                if showSplash {
                    SplashScreen()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.5), value: showSplash)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash Screen

struct SplashScreen: View {
    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image("ScowldLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(logoScale)
                    .scaleEffect(pulseScale)
                    .opacity(logoOpacity)

                Text("Scowld")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.8, blue: 1.0), Color(red: 0.2, green: 0.5, blue: 1.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(textOpacity)

                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(1.2)
                    .opacity(textOpacity)
                    .padding(.top, 8)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                textOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.6)) {
                pulseScale = 1.05
            }
        }
    }
}
