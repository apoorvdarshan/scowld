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
            .onReceive(NotificationCenter.default.publisher(for: .appReady)) { _ in
                showSplash = false
            }
            .onAppear {
                // Fallback: dismiss after 6s if notification never fires
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash Screen

struct SplashScreen: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0
    @State private var glowRadius: CGFloat = 0
    @State private var subtitleOpacity: Double = 0

    private let cyan = Color(red: 0.0, green: 0.85, blue: 1.0)
    private let deepBlue = Color(red: 0.1, green: 0.3, blue: 0.9)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle radial glow behind logo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cyan.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 160
                    )
                )
                .frame(width: 350, height: 350)
                .blur(radius: 30)
                .opacity(ringOpacity)

            VStack(spacing: 0) {
                ZStack {
                    // Spinning ring
                    Circle()
                        .trim(from: 0.0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                colors: [cyan, deepBlue, cyan.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(ringRotation))
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Second ring, opposite direction
                    Circle()
                        .trim(from: 0.0, to: 0.4)
                        .stroke(
                            AngularGradient(
                                colors: [deepBlue, cyan.opacity(0.0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: 170, height: 170)
                        .rotationEffect(.degrees(-ringRotation * 0.6))
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity * 0.6)

                    // Logo with glow
                    Image("ScowldLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .shadow(color: cyan.opacity(0.3), radius: glowRadius)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }

                Spacer().frame(height: 32)

                Text("Scowld")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [cyan, deepBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(textOpacity)

                Spacer().frame(height: 8)

                Text("Your AI Companion")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .opacity(subtitleOpacity)

                Spacer().frame(height: 40)

                // Dot loader
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        DotView(delay: Double(i) * 0.2, color: cyan)
                    }
                }
                .opacity(subtitleOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
                ringScale = 1.0
                ringOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                textOpacity = 1.0
                glowRadius = 12
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                subtitleOpacity = 1.0
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

struct DotView: View {
    let delay: Double
    let color: Color
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
    }
}
