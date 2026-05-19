import AVFoundation
import StoreKit
import SwiftUI
import WebKit

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
                    Text("Preview the animated companions before you unlock Scowld Plus.")
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
                    Text("Review Scowld's Privacy Policy and Terms of Service, then accept them to continue to plans.")
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

                OnboardingLegalWebView(url: selectedLegalDocument.url)
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
            return hasAcceptedLegal ? "Continue to Plans" : "Accept to Continue"
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

    var url: URL {
        switch self {
        case .privacy:
            return URL(string: "https://scowld.xyz/privacy")!
        case .terms:
            return URL(string: "https://scowld.xyz/terms")!
        }
    }
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
        OnboardingClip(title: "Aria", resourceName: "aria"),
        OnboardingClip(title: "Bella", resourceName: "bella"),
        OnboardingClip(title: "Ciel", resourceName: "ciel"),
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

private struct OnboardingLegalWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(url, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var currentURL: URL?

        func load(_ url: URL, in webView: WKWebView) {
            guard currentURL != url else { return }
            currentURL = url
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.targetFrame?.isMainFrame == true else {
                return .allow
            }

            guard let url = navigationAction.request.url,
                  let host = url.host?.lowercased(),
                  host == "scowld.xyz" || host == "www.scowld.xyz" else {
                return .cancel
            }

            return url.path == "/privacy" || url.path == "/terms" ? .allow : .cancel
        }
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
