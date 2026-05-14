import StoreKit
import SwiftUI

@main
struct ScowldApp: App {
    @State private var memoryStore = MemoryStore()
    @State private var billingStore = BillingStore()

    var body: some Scene {
        WindowGroup {
            ScowldRootView(memoryStore: memoryStore)
                .environment(billingStore)
                .preferredColorScheme(.dark)
                .task {
                    await billingStore.start()
                }
        }
    }
}

private enum ScowldTab: Hashable {
    case chat
    case pastChats
    case settings
    case billing
    case about
}

struct ScowldRootView: View {
    var memoryStore: MemoryStore
    @State private var selectedTab: ScowldTab = .chat
    @Environment(BillingStore.self) private var billingStore

    var body: some View {
        Group {
            if !billingStore.hasLoadedEntitlements {
                loadingBillingView
            } else if !billingStore.hasPaidAccess {
                PaywallView(
                    reason: "Choose a plan to start using Scowld.",
                    showsCloseButton: false,
                    title: "Scowld Plus",
                    isStartupGate: true
                )
            } else {
                appTabs
            }
        }
        .onChange(of: billingStore.hasPaidAccess) { _, hasPaidAccess in
            if hasPaidAccess {
                selectedTab = .chat
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBillingTab)) { _ in
            if billingStore.hasPaidAccess {
                selectedTab = .billing
            }
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(memoryStore: memoryStore, isActive: selectedTab == .chat)
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

            BillingView()
            .tabItem {
                Label("Billing", systemImage: "creditcard.fill")
            }
            .tag(ScowldTab.billing)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(ScowldTab.about)
        }
    }

    private var loadingBillingView: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                ProgressView("Loading billing...")
            }
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var updateState: AppUpdateState = .idle

    private let websiteURL = URL(string: "https://scowld.xyz")!
    private let koFiURL = URL(string: "https://ko-fi.com/apoorvdarshan")!
    private let productHuntURL = URL(string: "https://www.producthunt.com/products/scowld")!
    private let reportIssueURL = URL(string: "mailto:ad13dtu@gmail.com?subject=BUG%20Report%20-%20Scowld&body=What%20happened%3A%0A%0ASteps%20to%20reproduce%3A%0A%0ADevice%20and%20iOS%20version%3A")!
    private let requestFeatureURL = URL(string: "mailto:ad13dtu@gmail.com?subject=Feature%20Request%20-%20Scowld&body=Feature%20idea%3A%0A%0AWhy%20it%20would%20help%3A")!
    private let contactURL = URL(string: "mailto:ad13dtu@gmail.com?subject=Scowld%20Contact")!
    private let developerXURL = URL(string: "https://x.com/apoorvdarshan")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Scowld")
                            .fontWeight(.medium)
                        Spacer()
                        Text(versionDisplay)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://scowld.xyz/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://scowld.xyz/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                Section {
                    Button {
                        handleUpdateTap()
                    } label: {
                        HStack {
                            Label(updateButtonTitle, systemImage: updateButtonIcon)
                            Spacer()
                            if updateState == .checking {
                                ProgressView()
                            } else if let updateStatusText {
                                Text(updateStatusText)
                                    .foregroundStyle(updateStatusColor)
                            }
                        }
                    }

                    Button {
                        requestReview()
                    } label: {
                        Label("Rate Scowld", systemImage: "star.fill")
                    }

                    ShareLink(item: websiteURL) {
                        Label("Share Scowld", systemImage: "square.and.arrow.up")
                    }

                    Link(destination: koFiURL) {
                        Label("Support on Ko-fi", systemImage: "cup.and.saucer.fill")
                    }

                    Link(destination: productHuntURL) {
                        Label("Vote on Product Hunt", systemImage: "arrow.up.circle.fill")
                    }
                } header: {
                    Label("App", systemImage: "app.badge")
                }

                Section {
                    Link(destination: reportIssueURL) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble.fill")
                    }

                    Link(destination: requestFeatureURL) {
                        Label("Request a Feature", systemImage: "sparkles")
                    }

                    Link(destination: contactURL) {
                        Label("Contact", systemImage: "envelope.fill")
                    }
                } header: {
                    Label("Contact", systemImage: "envelope")
                }

                Section {
                    Link(destination: URL(string: "https://www.linkedin.com/company/scowld")!) {
                        Label("LinkedIn", systemImage: "person.2.fill")
                    }

                    Link(destination: URL(string: "https://www.instagram.com/scowld_/")!) {
                        Label("Instagram", systemImage: "camera.fill")
                    }

                    Link(destination: developerXURL) {
                        HStack {
                            Label("Meet the Developer on X", systemImage: "person.crop.circle.fill")
                            Spacer()
                            Text("@apoorvdarshan")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Social", systemImage: "link")
                }

                Section {
                    Text("Character model: Arbius AI (MIT)")
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Credits", systemImage: "doc.plaintext")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var versionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

        if build.isEmpty {
            return "v\(version)"
        }

        return "v\(version) (\(build))"
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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
}

private enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, appStoreURL: URL)
    case notOnAppStore
    case failed
}

private struct AppUpdateChecker {
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

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
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
