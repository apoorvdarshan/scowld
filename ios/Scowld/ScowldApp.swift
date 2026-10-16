import SwiftUI
import StoreKit

@main
struct ScowldApp: App {
    @State private var memoryStore: MemoryStore

    init() {
        // Debug simulator test switches only; a no-op in Release and on devices.
        ScowldTestEnvironment.prepare()
        RevenueCatSetup.configure()
        let memoryStore = MemoryStore(inMemory: ScowldTestEnvironment.isHostingUnitTests)
        ScowldTestEnvironment.seedIfRequested(memoryStore)
        _memoryStore = State(initialValue: memoryStore)
    }

    var body: some Scene {
        WindowGroup {
            if ScowldTestEnvironment.isHostingUnitTests {
                // Unit tests exercise the code directly; the host app stays idle.
                Color.black.ignoresSafeArea()
            } else {
                ScowldRootView(memoryStore: memoryStore)
                    .preferredColorScheme(.dark)
            }
        }
    }
}

private enum ScowldTab: Hashable {
    case chat
    case pastChats
    case settings
    case about

    /// The tab named by `--preview-tab` (Debug simulator screenshots only).
    init?(previewName: String?) {
        switch previewName {
        case "chat": self = .chat
        case "chats": self = .pastChats
        case "settings": self = .settings
        case "about": self = .about
        default: return nil
        }
    }
}

struct ScowldRootView: View {
    var memoryStore: MemoryStore
    @AppStorage("startup_onboarding_completed") private var hasCompletedStartupOnboarding = false
    @State private var selectedTab: ScowldTab = ScowldTab(previewName: ScowldTestEnvironment.previewTab) ?? .chat
    @State private var appUpdateState: AppUpdateState = .idle

    var body: some View {
        Group {
            if !hasCompletedStartupOnboarding {
                StartupOnboardingView {
                    hasCompletedStartupOnboarding = true
                }
            } else {
                appTabs
            }
        }
        .task {
            await checkForAppUpdateIfNeeded()
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(memoryStore: memoryStore, isActive: selectedTab == .chat, openSettings: { selectedTab = .settings })
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(ScowldTab.chat)

            NavigationStack {
                MemoryView(memoryStore: memoryStore)
            }
            .tabItem {
                Label("Chats", systemImage: "text.bubble.fill")
            }
            .tag(ScowldTab.pastChats)

            SettingsView(showsDismissControls: false)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(ScowldTab.settings)

            AboutView(updateState: $appUpdateState)
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
            .tag(ScowldTab.about)
                .aboutUpdateBadge(isVisible: appUpdateState.isUpdateAvailable)
        }
    }

    @MainActor
    private func checkForAppUpdateIfNeeded() async {
        // Tests never reach the App Store lookup.
        guard !ScowldTestEnvironment.isRunningTests else { return }
        guard appUpdateState == .idle else { return }
        appUpdateState = .checking
        appUpdateState = await AppUpdateChecker.check(currentVersion: AppUpdateChecker.currentVersion)
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Binding var updateState: AppUpdateState
    @State private var tipJar = TipJarModel()

    private let websiteURL = URL(string: "https://scowld.xyz")!
    private let privacyURL = URL(string: "https://scowld.xyz/privacy")!
    private let termsURL = URL(string: "https://scowld.xyz/terms")!
    private let productHuntURL = URL(string: "https://www.producthunt.com/products/scowld")!
    private let githubRepoURL = URL(string: "https://github.com/apoorvdarshan/scowld")!
    // Open the repository's issue forms directly (.github/ISSUE_TEMPLATE).
    private let githubBugReportURL = URL(string: "https://github.com/apoorvdarshan/scowld/issues/new?template=bug_report.yml")!
    private let githubFeatureRequestURL = URL(string: "https://github.com/apoorvdarshan/scowld/issues/new?template=feature_request.yml")!
    private let contactURL = URL(string: "mailto:ad13dtu@gmail.com?subject=Scowld%20Contact")!
    private let developerXURL = URL(string: "https://x.com/apoorvdarshan")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard

                    aboutSection("App", icon: "app.badge") {
                        aboutActionRow(
                            title: updateButtonTitle,
                            subtitle: updateStatusText,
                            systemImage: updateButtonIcon,
                            trailing: updateState == .checking ? .progress : .chevron,
                            subtitleColor: updateStatusColor
                        ) {
                            handleUpdateTap()
                        }

                        aboutActionRow(title: "Rate Scowld", systemImage: "star.fill") {
                            requestReview()
                        }

                        ShareLink(item: websiteURL) {
                            aboutRowContent(
                                title: "Share Scowld",
                                subtitle: "Send the app link",
                                systemImage: "square.and.arrow.up",
                                trailing: .chevron
                            )
                        }
                        .buttonStyle(.plain)

                        linkRow(
                            title: "Vote on Product Hunt",
                            subtitle: "producthunt.com/products/scowld",
                            systemImage: "arrow.up.circle.fill",
                            url: productHuntURL
                        )
                    }

                    aboutSection("Open Source", icon: "chevron.left.forwardslash.chevron.right") {
                        linkRow(
                            title: "Open Source on GitHub",
                            subtitle: "github.com/apoorvdarshan/scowld · MIT",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            url: githubRepoURL
                        )

                        linkRow(
                            title: "Star on GitHub",
                            subtitle: "Support the project with a star",
                            systemImage: "star.circle.fill",
                            url: githubRepoURL
                        )

                        linkRow(
                            title: "Report an Issue",
                            subtitle: "Bug report form on GitHub",
                            systemImage: "exclamationmark.bubble.fill",
                            url: githubBugReportURL
                        )

                        linkRow(
                            title: "Request a Feature",
                            subtitle: "Feature request form on GitHub",
                            systemImage: "sparkles",
                            url: githubFeatureRequestURL
                        )
                    }

                    aboutSection("Support Scowld", icon: "heart.circle.fill") {
                        aboutInfoRow(
                            title: "Leave a tip",
                            subtitle: "One-time tips fund development. They don't unlock anything: Scowld stays free and open source.",
                            systemImage: "hands.sparkles.fill"
                        )
                        ForEach(TipTier.all) { tier in
                            tipRow(tier)
                        }
                    }
                    .task { await tipJar.load() }

                    aboutSection("Contact", icon: "envelope") {
                        linkRow(
                            title: "Contact",
                            subtitle: "ad13dtu@gmail.com",
                            systemImage: "envelope.fill",
                            url: contactURL
                        )
                    }

                    aboutSection("Social", icon: "link") {
                        linkRow(
                            title: "Instagram",
                            subtitle: "@apoorvcodes",
                            systemImage: "camera.fill",
                            url: URL(string: "https://www.instagram.com/apoorvcodes/")!
                        )

                        linkRow(
                            title: "Meet the Developer on X",
                            subtitle: "@apoorvdarshan",
                            systemImage: "person.crop.circle.fill",
                            url: developerXURL
                        )
                    }

                    aboutSection("Credits", icon: "doc.plaintext") {
                        aboutInfoRow(
                            title: "Character model",
                            subtitle: "Arbius AI (MIT)",
                            systemImage: "cube.fill"
                        )
                    }

                    aboutSection("Legal", icon: "checkmark.shield.fill") {
                        linkRow(
                            title: "Privacy Policy",
                            subtitle: "scowld.xyz/privacy",
                            systemImage: "hand.raised.fill",
                            url: privacyURL
                        )

                        linkRow(
                            title: "Terms of Service",
                            subtitle: "scowld.xyz/terms",
                            systemImage: "doc.text.fill",
                            url: termsURL
                        )
                    }
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .alert(tipAlert?.title ?? "", isPresented: tipAlertShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tipAlert?.message ?? "")
            }
        }
    }

    // MARK: - Tips

    private func tipRow(_ tier: TipTier) -> some View {
        let product = tipJar.products[tier.productID]
        let trailing: AboutRowTrailing
        if tipJar.status == .purchasing(tier.productID) || (product == nil && tipJar.isLoading) {
            trailing = .progress
        } else if let product {
            trailing = .text(product.localizedPrice)
        } else {
            // Offline, or the store hasn't propagated the products yet.
            trailing = .text("Unavailable")
        }
        return Button {
            Task { await tipJar.purchase(tier) }
        } label: {
            aboutRowContent(title: tier.name, systemImage: tier.systemImage, trailing: trailing)
        }
        .buttonStyle(.plain)
        .disabled(product == nil || tipJar.isPurchasing)
    }

    private var tipAlert: (title: String, message: String)? {
        switch tipJar.status {
        case .thanks: ("Thank you!", "Your tip keeps Scowld free and open source.")
        case .pending: ("Tip pending", "Your tip is waiting for approval. It goes through once it's approved.")
        case .failed(let message): ("Tip didn't go through", message)
        case .idle, .purchasing: nil
        }
    }

    private var tipAlertShown: Binding<Bool> {
        Binding(
            get: { tipAlert != nil },
            set: { if !$0 { tipJar.status = .idle } }
        )
    }

    private var versionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "v\(version)"
    }

    private var currentVersion: String {
        AppUpdateChecker.currentVersion
    }

    private var updateButtonTitle: String {
        if case .updateAvailable = updateState {
            return "Open App Store Update"
        }

        return "Check for Updates"
    }

    private var updateButtonIcon: String {
        if case .updateAvailable = updateState {
            return "arrow.down.app.fill"
        }

        return "arrow.triangle.2.circlepath"
    }

    private var updateStatusText: String? {
        switch updateState {
        case .idle, .checking:
            return nil
        case .upToDate:
            return "Up to date"
        case .updateAvailable(let version, _):
            return "v\(version)"
        case .notOnAppStore:
            return "Not live yet"
        case .failed:
            return "Failed"
        }
    }

    private var updateStatusColor: Color {
        switch updateState {
        case .updateAvailable:
            return .amicaBlue
        case .failed:
            return .red
        default:
            return .secondary
        }
    }

    private func handleUpdateTap() {
        if case .updateAvailable(_, let appStoreURL) = updateState {
            openURL(appStoreURL)
            return
        }

        Task {
            await checkForUpdates()
        }
    }

    @MainActor
    private func checkForUpdates() async {
        updateState = .checking
        updateState = await AppUpdateChecker.check(currentVersion: currentVersion)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image("ScowldLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Scowld")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text(versionDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("about.version")
                Text("AI voice companion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func aboutSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                content()
            }
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func linkRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        url: URL
    ) -> some View {
        aboutActionRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            openURL(url)
        }
    }

    private func aboutActionRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        trailing: AboutRowTrailing = .chevron,
        subtitleColor: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            aboutRowContent(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                trailing: trailing,
                subtitleColor: subtitleColor
            )
        }
        .buttonStyle(.plain)
    }

    private func aboutInfoRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        aboutRowContent(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            trailing: .none
        )
    }

    private func aboutRowContent(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        trailing: AboutRowTrailing = .chevron,
        subtitleColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 10)

            switch trailing {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            case .progress:
                ProgressView()
            case .text(let value):
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.leading, 62)
        }
        .contentShape(Rectangle())
    }
}

private enum AboutRowTrailing {
    case chevron
    case progress
    case text(String)
    case none
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, appStoreURL: URL)
    case notOnAppStore
    case failed

    var isUpdateAvailable: Bool {
        if case .updateAvailable = self {
            return true
        }

        return false
    }
}

struct AppUpdateChecker {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func check(currentVersion: String) async -> AppUpdateState {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)") else {
            return .failed
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)

            guard let result = response.results.first,
                  let storeVersion = result.version else {
                return .notOnAppStore
            }

            if isVersion(storeVersion, newerThan: currentVersion),
               let appStoreURL = result.trackViewURL {
                return .updateAvailable(version: storeVersion, appStoreURL: appStoreURL)
            }

            return .upToDate
        } catch {
            return .failed
        }
    }

    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }

        return false
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let version: String?
    let trackViewURL: URL?

    private enum CodingKeys: String, CodingKey {
        case version
        case trackViewURL = "trackViewUrl"
    }
}

private extension View {
    @ViewBuilder
    func aboutUpdateBadge(isVisible: Bool) -> some View {
        if isVisible {
            badge("")
        } else {
            self
        }
    }
}
