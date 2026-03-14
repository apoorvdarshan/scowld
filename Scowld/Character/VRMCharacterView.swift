import SwiftUI

// MARK: - Owl Character View

/// Animated 2D owl character rendered with SwiftUI.
/// This view is VRM-ready — replace with VRMKit/RealityKit rendering when .vrm files are available.
/// The character reacts to: emotion state, lip sync amplitude, eye tracking, and head rotation.
struct VRMCharacterView: View {
    let emotion: Emotion
    let mouthOpenness: CGFloat
    let pupilOffsetX: CGFloat
    let pupilOffsetY: CGFloat
    let headRotation: CGFloat
    let isBlinking: Bool
    let bodyBounce: CGFloat

    // MARK: - Colors
    private let owlBody = Color(red: 0.55, green: 0.35, blue: 0.17)
    private let owlBodyLight = Color(red: 0.72, green: 0.53, blue: 0.30)
    private let owlBelly = Color(red: 0.85, green: 0.75, blue: 0.60)
    private let owlFaceDisc = Color(red: 0.92, green: 0.84, blue: 0.72)
    private let owlBeak = Color(red: 0.90, green: 0.68, blue: 0.15)
    private let owlEarTuft = Color(red: 0.40, green: 0.25, blue: 0.12)
    private let owlIris = Color(red: 0.80, green: 0.50, blue: 0.05)
    private let owlPupil = Color(red: 0.08, green: 0.06, blue: 0.04)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Body
                owlBody(size: size)

                // Head + face (offset up)
                owlHead(size: size)
                    .offset(y: -size * 0.18)
                    .rotation3DEffect(
                        .degrees(Double(headRotation)),
                        axis: (0, 1, 0),
                        perspective: 0.3
                    )
            }
            .frame(width: size, height: size)
            .offset(y: bodyBounce > 0 ? -8 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: bodyBounce)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .animation(.easeInOut(duration: 0.3), value: emotion)
        .animation(.easeInOut(duration: 0.15), value: isBlinking)
        .animation(.spring(response: 0.2), value: mouthOpenness)
    }

    // MARK: - Body

    @ViewBuilder
    private func owlBody(size: CGFloat) -> some View {
        ZStack {
            // Main body
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [owlBodyLight, owlBody],
                        center: .center,
                        startRadius: size * 0.05,
                        endRadius: size * 0.3
                    )
                )
                .frame(width: size * 0.55, height: size * 0.6)
                .offset(y: size * 0.1)

            // Belly patch
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [owlBelly, owlBelly.opacity(0.3)],
                        center: .top,
                        startRadius: 0,
                        endRadius: size * 0.2
                    )
                )
                .frame(width: size * 0.32, height: size * 0.35)
                .offset(y: size * 0.18)

            // Belly feather lines
            ForEach(0..<4) { i in
                let yOffset = size * (0.12 + CGFloat(i) * 0.06)
                let width = size * (0.25 - CGFloat(i) * 0.03)
                Capsule()
                    .fill(owlBody.opacity(0.2))
                    .frame(width: width, height: 1.5)
                    .offset(y: yOffset)
            }

            // Wings (left)
            WingShape()
                .fill(owlBody.opacity(0.8))
                .frame(width: size * 0.18, height: size * 0.35)
                .offset(x: -size * 0.3, y: size * 0.08)

            // Wings (right)
            WingShape()
                .fill(owlBody.opacity(0.8))
                .frame(width: size * 0.18, height: size * 0.35)
                .scaleEffect(x: -1)
                .offset(x: size * 0.3, y: size * 0.08)

            // Feet
            HStack(spacing: size * 0.08) {
                owlFoot(size: size)
                owlFoot(size: size)
            }
            .offset(y: size * 0.42)
        }
    }

    @ViewBuilder
    private func owlFoot(size: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { _ in
                Capsule()
                    .fill(owlBeak.opacity(0.7))
                    .frame(width: size * 0.025, height: size * 0.05)
            }
        }
    }

    // MARK: - Head

    @ViewBuilder
    private func owlHead(size: CGFloat) -> some View {
        ZStack {
            // Face disc (characteristic owl feature)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [owlFaceDisc, owlBodyLight],
                        center: .center,
                        startRadius: size * 0.02,
                        endRadius: size * 0.22
                    )
                )
                .frame(width: size * 0.5, height: size * 0.5)

            // Face disc rim
            Circle()
                .strokeBorder(owlBody.opacity(0.4), lineWidth: 2)
                .frame(width: size * 0.5, height: size * 0.5)

            // Ear tufts
            earTuft(size: size, flipped: false)
                .offset(x: -size * 0.17, y: -size * 0.22)
                .rotationEffect(.degrees(-15))

            earTuft(size: size, flipped: true)
                .offset(x: size * 0.17, y: -size * 0.22)
                .rotationEffect(.degrees(15))

            // Eyes
            HStack(spacing: size * 0.1) {
                owlEye(size: size, isLeft: true)
                owlEye(size: size, isLeft: false)
            }
            .offset(y: -size * 0.02)

            // Beak
            owlBeak(size: size)
                .offset(y: size * 0.1)

            // Eyebrows (expression-dependent)
            if emotion == .angry {
                // Angry brows
                HStack(spacing: size * 0.1) {
                    Capsule()
                        .fill(owlEarTuft)
                        .frame(width: size * 0.1, height: size * 0.015)
                        .rotationEffect(.degrees(15))
                    Capsule()
                        .fill(owlEarTuft)
                        .frame(width: size * 0.1, height: size * 0.015)
                        .rotationEffect(.degrees(-15))
                }
                .offset(y: -size * 0.1)
            }
        }
    }

    // MARK: - Eye

    @ViewBuilder
    private func owlEye(size: CGFloat, isLeft: Bool) -> some View {
        let eyeScale = eyeScaleForEmotion
        let pupilSize = pupilSizeForEmotion

        ZStack {
            // Eye white (sclera)
            Ellipse()
                .fill(.white)
                .frame(
                    width: size * 0.14 * eyeScale.width,
                    height: size * 0.14 * eyeScale.height * (isBlinking ? 0.1 : 1.0)
                )
                .shadow(color: .black.opacity(0.1), radius: 2)

            if !isBlinking {
                // Iris
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [owlIris, owlIris.opacity(0.7)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.04
                        )
                    )
                    .frame(width: size * 0.09 * pupilSize, height: size * 0.09 * pupilSize)
                    .offset(
                        x: pupilOffsetX * size * 0.02,
                        y: pupilOffsetY * size * 0.02
                    )

                // Pupil
                Circle()
                    .fill(owlPupil)
                    .frame(width: size * 0.045 * pupilSize, height: size * 0.045 * pupilSize)
                    .offset(
                        x: pupilOffsetX * size * 0.02,
                        y: pupilOffsetY * size * 0.02
                    )

                // Eye highlight
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: size * 0.02, height: size * 0.02)
                    .offset(
                        x: size * 0.015 + pupilOffsetX * size * 0.01,
                        y: -size * 0.015 + pupilOffsetY * size * 0.01
                    )
            }
        }
    }

    private var eyeScaleForEmotion: CGSize {
        switch emotion {
        case .surprised, .excited: CGSize(width: 1.2, height: 1.2)
        case .happy: CGSize(width: 1.0, height: 0.8)
        case .sad: CGSize(width: 0.9, height: 0.85)
        case .angry: CGSize(width: 1.0, height: 0.7)
        case .thinking: CGSize(width: 0.95, height: 0.95)
        case .concerned: CGSize(width: 1.0, height: 0.9)
        default: CGSize(width: 1.0, height: 1.0)
        }
    }

    private var pupilSizeForEmotion: CGFloat {
        switch emotion {
        case .surprised, .excited: 1.2
        case .happy: 1.1
        case .angry: 0.8
        default: 1.0
        }
    }

    // MARK: - Beak

    @ViewBuilder
    private func owlBeak(size: CGFloat) -> some View {
        let beakOpen = mouthOpenness * size * 0.025

        ZStack {
            // Upper beak
            TriangleShape()
                .fill(owlBeak)
                .frame(width: size * 0.06, height: size * 0.035)
                .offset(y: -beakOpen / 2)

            // Lower beak
            TriangleShape()
                .fill(owlBeak.opacity(0.8))
                .frame(width: size * 0.05, height: size * 0.025)
                .rotationEffect(.degrees(180))
                .offset(y: size * 0.02 + beakOpen / 2)
        }
    }

    // MARK: - Ear Tufts

    @ViewBuilder
    private func earTuft(size: CGFloat, flipped: Bool) -> some View {
        ZStack {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == 0 ? owlEarTuft : owlBody)
                    .frame(width: size * 0.025, height: size * 0.08 - CGFloat(i) * size * 0.01)
                    .rotationEffect(.degrees(Double(i - 1) * 12 * (flipped ? -1 : 1)))
            }
        }
    }
}

// MARK: - Custom Shapes

struct WingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX + rect.width * 0.2, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.maxY * 0.8)
        )
        return path
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        VRMCharacterView(
            emotion: .happy,
            mouthOpenness: 0.3,
            pupilOffsetX: 0,
            pupilOffsetY: 0,
            headRotation: 0,
            isBlinking: false,
            bodyBounce: 0
        )
        .frame(width: 300, height: 400)
    }
}
