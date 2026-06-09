import AVFoundation
import StoreKit
import SwiftUI

struct StartupOnboardingView: View {
    @Environment(\.requestReview) private var requestReview
    @State private var selectedPage = 0
    @State private var selectedLegalDocument: OnboardingLegalDocument = .privacy
    @State private var hasAcceptedLegal = false
    @State private var hasRequestedReview = false

    let onComplete: () -> Void

    private let pageCount = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $selectedPage) {
                    welcomePage
                        .tag(0)

                    companionPage
                        .tag(1)

                    videoPage
                        .tag(2)

                    ratingPage
                        .tag(3)

                    legalPage
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
            }
        }
    }

    private var welcomePage: some View {
        OnboardingPageShell {
            VStack(spacing: 24) {
                Image("ScowldLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 106, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .amicaBlue.opacity(0.38), radius: 26, y: 16)

                VStack(spacing: 10) {
                    Text("Welcome to Scowld")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.72)

                    Text("A voice companion with an animated character, memory, and expressive replies.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
        }
    }

    private var companionPage: some View {
        OnboardingPageShell {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Talk naturally.")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Scowld turns voice into a flowing conversation with speech, captions, optional vision, and saved past chats.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                VStack(spacing: 12) {
                    OnboardingFeatureRow(icon: "waveform", title: "Voice turns", subtitle: "Speak or type, then hear her answer.")
                    OnboardingFeatureRow(icon: "eye.fill", title: "Optional vision", subtitle: "Use camera context when you want it.")
                    OnboardingFeatureRow(icon: "text.bubble.fill", title: "Past chats", subtitle: "Keep conversations as reference.")
                }
            }
        }
    }

    private var videoPage: some View {
        OnboardingPageShell(topPadding: 26) {
            let isPad = UIDevice.current.userInterfaceIdiom == .pad

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose her vibe.")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Preview the animated companions before you start Scowld.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                OnboardingVideoCarousel(isVisible: selectedPage == 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: isPad ? 640 : 520)
            }
        }
    }

    private var ratingPage: some View {
        OnboardingPageShell {
            VStack(spacing: 24) {
                Image(systemName: hasRequestedReview ? "checkmark.seal.fill" : "star.fill")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(Color.amicaBlue)
                    .frame(width: 104, height: 104)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }

                VStack(spacing: 10) {
                    Text("Rate Scowld")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Ratings help people find the app. No fake reviews, just your honest rating when the iOS prompt appears.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    hasRequestedReview = true
                    requestReview()
                } label: {
                    Label(hasRequestedReview ? "Thanks" : "Rate Scowld", systemImage: hasRequestedReview ? "checkmark.circle.fill" : "star.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.black)
                        .background(Color.amicaBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(hasRequestedReview)
                .opacity(hasRequestedReview ? 0.8 : 1)
            }
        }
    }

    private var legalPage: some View {
        OnboardingPageShell(topPadding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before you continue")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Review Scowld's Privacy Policy and Terms of Service, then accept them to continue.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                Picker("Legal document", selection: $selectedLegalDocument) {
                    ForEach(OnboardingLegalDocument.allCases) { document in
                        Text(document.title).tag(document)
                    }
                }
                .pickerStyle(.segmented)

                OnboardingLegalTextView(document: selectedLegalDocument)
                    .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 560 : 390)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }

                Button {
                    hasAcceptedLegal.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: hasAcceptedLegal ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(hasAcceptedLegal ? Color.amicaBlue : .secondary)

                        Text("I have read and agree to the Privacy Policy and Terms of Service.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(hasAcceptedLegal ? Color.amicaBlue.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Capsule()
                        .fill(page == selectedPage ? Color.amicaBlue : Color.white.opacity(0.18))
                        .frame(width: page == selectedPage ? 28 : 8, height: 8)
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedPage)
                }
            }

            HStack(spacing: 12) {
                if selectedPage > 0 {
                    Button {
                        withAnimation(.smooth(duration: 0.26)) {
                            selectedPage -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 54, height: 54)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }

                Button {
                    if selectedPage == pageCount - 1 {
                        onComplete()
                    } else {
                        withAnimation(.smooth(duration: 0.26)) {
                            selectedPage += 1
                        }
                    }
                } label: {
                    HStack {
                        Text(footerButtonTitle)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .foregroundStyle(.black)
                    .background(Color.amicaBlue, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.42)
            }
        }
    }

    private var canContinue: Bool {
        selectedPage != pageCount - 1 || hasAcceptedLegal
    }

    private var footerButtonTitle: String {
        if selectedPage == pageCount - 1 {
            return hasAcceptedLegal ? "Start Scowld" : "Accept to Continue"
        }

        return "Continue"
    }
}

private enum OnboardingLegalDocument: String, CaseIterable, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy:
            return "Privacy"
        case .terms:
            return "Terms"
        }
    }

    var date: String {
        switch self {
        case .privacy:
            return "Last updated: May 21, 2026"
        case .terms:
            return "Last updated: May 21, 2026"
        }
    }

    var sections: [LegalTextSection] {
        switch self {
        case .privacy:
            return [
                LegalTextSection(
                    title: "Overview",
                    body: "Scowld is a free, open-source iOS AI companion app. It uses bring-your-own-key provider settings for AI chat, optional cloud speech-to-text, and ElevenLabs or OpenAI text-to-speech. API keys you enter are stored in the iOS Keychain on your device. Scowld also includes an optional hands-free wake mode for starting voice input by saying the selected companion name."
                ),
                LegalTextSection(
                    title: "Account and analytics",
                    body: "The iOS app does not require a Scowld account. The app does not include advertising SDKs or third-party app analytics SDKs. We do not ask for your name, email, location, or account password in the iOS app. We do not sell personal data."
                ),
                LegalTextSection(
                    title: "AI and voice processing",
                    body: "To provide app features, Scowld may process typed messages, selected conversation context, speech audio sent for transcription, recognized speech text, assistant response text sent for speech generation, optional camera image context when you enable camera/vision and send a message, and hands-free wake detection audio processed on device while hands-free mode is enabled. Provider requests are sent directly from the app to the provider you configure. Hands-free wake detection is not sent to external providers before recording starts."
                ),
                LegalTextSection(
                    title: "Camera, vision, and face data",
                    body: "Scowld requests camera access only for optional vision context. Frames are captured on device and sent to the selected AI provider only when visual context is used in a message. Images are not saved to your photo library by Scowld. Scowld does not use Apple's TrueDepth API or ARKit face tracking. Scowld does not collect, use, store, disclose, share, or retain face geometry, depth maps, facial blend shapes, facial expressions, biometric identifiers, or any other face data."
                ),
                LegalTextSection(
                    title: "Microphone access",
                    body: "Scowld requests microphone access for voice input and optional hands-free wake mode. When you record or send voice input, speech audio is transcribed using native iOS speech recognition or the cloud STT provider you configure, and recognized text may be sent to the selected AI provider as part of the conversation. When hands-free mode is enabled, Scowld may keep the microphone active while the app is open and idle to listen on device for Bella or your saved custom companion name. Hands-free mode can be turned off in the composer, and microphone permission can be revoked in iOS settings."
                ),
                LegalTextSection(
                    title: "Third-party providers",
                    body: "Scowld can integrate with third-party providers you configure, including Google Gemini, OpenAI, Anthropic Claude, Ollama, Groq, OpenRouter, xAI, Together AI, Hugging Face, Venice AI, Moonshot AI, Deepgram, AssemblyAI, Google Cloud Speech-to-Text, and ElevenLabs. The marketing website is deployed on Vercel."
                ),
                LegalTextSection(
                    title: "Provider API keys",
                    body: "Scowld lets you enter your own provider API keys. Keys are stored in the iOS Keychain on your device and are not included in the App Store binary. Delete the app or remove keys from Settings to stop using saved keys."
                ),
                LegalTextSection(
                    title: "Local device storage",
                    body: "Scowld stores app data locally on your device, including past chat messages, the selected active chat, character settings, voice and language preferences, caption preferences, hands-free wake preferences, provider choices, and model choices. Provider API keys are stored in Keychain. Deleting the app removes local app data from the device, subject to normal iOS behavior and backups."
                ),
                LegalTextSection(
                    title: "Voice samples, children, and contact",
                    body: "Voice sample playback in Settings uses bundled local preview audio files and does not call ElevenLabs. Scowld is not directed at children under 13. For privacy questions, contact Apoorv Darshan at ad13dtu@gmail.com."
                ),
            ]
        case .terms:
            return [
                LegalTextSection(
                    title: "Acceptance",
                    body: "By downloading, installing, or using Scowld, you agree to these Terms of Service. If you do not agree, do not use the app."
                ),
                LegalTextSection(
                    title: "Service",
                    body: "Scowld is an iOS AI companion app with bring-your-own-key conversational AI, an animated VRM companion, voice input using native iOS speech recognition or configured cloud STT providers, optional hands-free wake mode, ElevenLabs or OpenAI text-to-speech, optional camera/vision context, and local saved chats."
                ),
                LegalTextSection(
                    title: "Bring your own keys",
                    body: "Scowld does not include subscriptions, paywalls, voice credits, or extra credit packs. You are responsible for the provider accounts, API keys, provider billing, usage limits, and acceptable use policies for the AI, speech-to-text, and text-to-speech services you configure."
                ),
                LegalTextSection(
                    title: "Your responsibilities",
                    body: "You agree not to use Scowld for illegal, harmful, abusive, harassing, threatening, exploitative, or otherwise objectionable purposes. You are responsible for content you submit and for how you use generated responses."
                ),
                LegalTextSection(
                    title: "Camera and microphone",
                    body: "When you enable camera or microphone permissions, you consent to their use for the purposes described in the Privacy Policy. If hands-free mode is enabled, the microphone may remain active while the app is open and idle so Scowld can listen on device for Bella or your saved custom companion name. Scowld does not use Apple's TrueDepth API or collect face data. Camera vision is optional and microphone input is used only for voice input and hands-free wake detection."
                ),
                LegalTextSection(
                    title: "Service limits and availability",
                    body: "Cloud AI, cloud speech-to-text, and cloud text-to-speech require an active internet connection and valid provider API keys. Hands-free wake detection requires microphone and speech recognition permission, may miss wake phrases, and may occasionally trigger unexpectedly. Third-party providers may change, fail, rate limit, bill your account, or become unavailable."
                ),
                LegalTextSection(
                    title: "AI output disclaimer",
                    body: "AI-generated responses may be inaccurate, incomplete, biased, offensive, or inappropriate. Scowld is an entertainment and companion experience, not a professional advisor. Do not rely on AI responses for medical, legal, financial, safety-critical, or emergency advice."
                ),
                LegalTextSection(
                    title: "Third-party services",
                    body: "The app integrates with services not owned or controlled by the developer, including AI, speech-to-text, text-to-speech, Apple platform services, and Vercel hosting. The developer is not responsible for third-party service content, policies, pricing, billing, availability, or data practices."
                ),
                LegalTextSection(
                    title: "Ownership and termination",
                    body: "The Scowld name, logo, branding, app design, and website are owned by Apoorv Darshan unless otherwise stated. The Scowld app source code is open source under the MIT License at github.com/apoorvdarshan/scowld. You may stop using Scowld at any time by deleting the app. Access may be restricted for abuse, unlawful use, or violation of these terms."
                ),
                LegalTextSection(
                    title: "Contact",
                    body: "For questions about these terms, contact Apoorv Darshan at ad13dtu@gmail.com."
                ),
            ]
        }
    }
}

private struct LegalTextSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

private struct OnboardingPageShell<Content: View>: View {
    var topPadding: CGFloat = 48
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack {
                Spacer(minLength: topPadding)

                content
                    .padding(22)
                    .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 640 : .infinity)

                Spacer(minLength: 18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: UIScreen.main.bounds.height - 124)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.amicaBlue)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct OnboardingVideoCarousel: View {
    let isVisible: Bool
    @State private var selectedClip = 0
    private let videoAspectRatio: CGFloat = 1180.0 / 2556.0

    private let clips = [
        OnboardingClip(title: "Character 1", resourceName: "aria"),
        OnboardingClip(title: "Character 2", resourceName: "bella"),
        OnboardingClip(title: "Character 3", resourceName: "ciel"),
    ]

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(320, proxy.size.height - 46)
            let availableWidth = max(180, proxy.size.width - 36)
            let videoHeight = min(availableHeight, availableWidth / videoAspectRatio)
            let videoWidth = videoHeight * videoAspectRatio

            VStack(spacing: 14) {
                TabView(selection: $selectedClip) {
                    ForEach(Array(clips.enumerated()), id: \.element.resourceName) { index, clip in
                        VStack(spacing: 10) {
                            LoopingOnboardingVideoView(resourceName: clip.resourceName, isActive: isVisible && selectedClip == index)
                                .frame(width: videoWidth, height: videoHeight)
                                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.38), radius: 20, y: 14)

                            Text(clip.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(clips.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedClip ? Color.amicaBlue : Color.white.opacity(0.18))
                            .frame(width: index == selectedClip ? 22 : 7, height: 7)
                    }
                }
            }
        }
    }
}

private struct OnboardingClip {
    let title: String
    let resourceName: String
}

private struct OnboardingLegalTextView: View {
    let document: OnboardingLegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(document.title == "Privacy" ? "Privacy Policy" : "Terms of Service")
                        .font(.title3.weight(.bold))
                    Text(document.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(section.body)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .foregroundStyle(.secondary)
                            .textSelection(.disabled)
                    }
                }
            }
            .padding(18)
        }
        .scrollIndicators(.visible)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct LoopingOnboardingVideoView: UIViewRepresentable {
    let resourceName: String
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LoopingOnboardingVideoUIView {
        let view = LoopingOnboardingVideoUIView()
        view.playerLayer.videoGravity = .resizeAspect
        context.coordinator.configure(resourceName: resourceName, in: view)
        context.coordinator.setActive(isActive)
        return view
    }

    func updateUIView(_ uiView: LoopingOnboardingVideoUIView, context: Context) {
        context.coordinator.configure(resourceName: resourceName, in: uiView)
        context.coordinator.setActive(isActive)
    }

    final class Coordinator {
        private var currentResourceName: String?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(resourceName: String, in view: LoopingOnboardingVideoUIView) {
            guard currentResourceName != resourceName else { return }
            currentResourceName = resourceName

            guard let url = videoURL(for: resourceName) else {
                view.playerLayer.player = nil
                player = nil
                looper = nil
                return
            }

            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = false
            queuePlayer.volume = 1
            queuePlayer.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
            view.playerLayer.player = queuePlayer
        }

        func setActive(_ isActive: Bool) {
            if isActive {
                prepareAudioPlayback()
                player?.play()
            } else {
                player?.pause()
            }
        }

        private func prepareAudioPlayback() {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }

        private func videoURL(for resourceName: String) -> URL? {
            Bundle.main.url(forResource: resourceName, withExtension: "mp4")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mp4", subdirectory: "OnboardingVideos")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mp4", subdirectory: "Resources/OnboardingVideos")
        }
    }
}

private final class LoopingOnboardingVideoUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
