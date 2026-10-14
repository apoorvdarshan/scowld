import CoreData
import Foundation
import UIKit
import WebKit

/// Launch switches used only by the XCTest suites.
///
/// Everything here is compiled out of Release builds and is inert on devices:
/// outside a Debug simulator build every switch reads `false`, so App Store
/// builds behave exactly as before.
enum ScowldTestEnvironment {
    /// Set by the UI tests on every launch.
    static let uiTestingArgument = "--ui-testing"
    /// Wipes Scowld's simulator state (preferences, saved chats, provider keys).
    static let resetArgument = "--ui-testing-reset"
    /// Marks startup onboarding as completed.
    static let onboardedArgument = "--ui-testing-onboarded"
    /// Adds a saved chat with a short transcript.
    static let seedChatArgument = "--ui-testing-seed-chat"
    /// Answers chat messages with `StubLLMProvider` instead of a real provider.
    static let stubAIArgument = "--ui-testing-stub-ai"
    /// Posted once the bundled companion page can accept messages (UI tests only).
    static let companionReadyNotification = Notification.Name("ScowldTestsCompanionReady")

    static let seededChatName = "Weekend Plans"
    static let seededUserMessage = "Plan a picnic for Saturday"
    static let seededAssistantMessage = "Pack sandwiches, lemonade, and a blanket."

    /// The app was launched by the UI tests.
    static var isUITesting: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return CommandLine.arguments.contains(uiTestingArgument)
        #else
        return false
        #endif
    }

    /// The app is only hosting the unit-test bundle, so it stays idle.
    static var isHostingUnitTests: Bool {
        #if DEBUG && targetEnvironment(simulator)
        guard !isUITesting else { return false }
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
        #else
        return false
        #endif
    }

    /// While tests run, Scowld never reaches the network, the microphone, speech
    /// recognition or the camera, and never shows a permission prompt.
    static var isRunningTests: Bool {
        isUITesting || isHostingUnitTests
    }

    /// Chat replies come from `StubLLMProvider` (UI tests that send a message).
    static var usesStubAI: Bool {
        isUITesting && CommandLine.arguments.contains(stubAIArgument)
    }

    /// A local, instant chat provider for UI tests: no key, no network.
    struct StubLLMProvider: LLMProvider {
        func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String {
            let lastUserMessage = messages.last(where: { $0.role == .user })?.content ?? ""
            return "[happy] Test reply to: \(lastUserMessage)"
        }

        func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String {
            try await generate(messages: messages, systemPrompt: systemPrompt)
        }
    }

    /// UI tests: posts `companionReadyNotification` once the page's native message
    /// bridge exists, so a test never sends before the companion can receive it.
    static func reportCompanionReadiness(of webView: WKWebView) {
        guard isUITesting else { return }
        webView.evaluateJavaScript("typeof window.__sendMessageFromNative === 'function'") { [weak webView] result, _ in
            if (result as? Bool) == true {
                NotificationCenter.default.post(name: companionReadyNotification, object: nil)
            } else if let webView {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    reportCompanionReadiness(of: webView)
                }
            }
        }
    }

    /// Applies the launch switches once, before any stored state is read.
    static func prepare() {
        _ = preparation
    }

    /// Adds the seeded chat when the UI tests ask for it.
    static func seedIfRequested(_ memoryStore: MemoryStore) {
        #if DEBUG && targetEnvironment(simulator)
        guard isUITesting, CommandLine.arguments.contains(seedChatArgument) else { return }
        let slot = memoryStore.createSlot(name: seededChatName)
        memoryStore.setActiveSlot(id: slot.id)
        memoryStore.saveExchange(userMessage: seededUserMessage, assistantResponse: seededAssistantMessage)
        #endif
    }

    /// Loads the bundled companion page with every request that leaves the
    /// device blocked (fonts, CDNs, telemetry). Never falls back to an
    /// unblocked load: if the rule list cannot be compiled, nothing loads.
    static func loadBlockingExternalRequests(_ webView: WKWebView, request: URLRequest) {
        let rules = #"""
        [
          {"trigger": {"url-filter": "^(https?|wss?)://"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "^(https?|wss?)://(127\\.0\\.0\\.1|localhost)[:/]"}, "action": {"type": "ignore-previous-rules"}}
        ]
        """#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ScowldTestsOffline",
            encodedContentRuleList: rules
        ) { [weak webView] ruleList, _ in
            guard let webView, let ruleList else { return }
            webView.configuration.userContentController.add(ruleList)
            webView.load(request)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let preparation: Void = {
        guard isUITesting else { return }
        let arguments = CommandLine.arguments
        if arguments.contains(resetArgument) {
            resetSimulatorState()
        }
        if arguments.contains(onboardedArgument) {
            UserDefaults.standard.set(true, forKey: "startup_onboarding_completed")
        }
    }()

    /// Simulator-only: removes this app's preferences, saved chats and provider
    /// keys so every UI test starts from a fresh install.
    private static func resetSimulatorState() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: storeDirectory.appendingPathComponent("Scowld.sqlite\(suffix)"))
        }

        let keychainKeys = AIProvider.allCases.map(\.keychainKey)
            + STTBackend.allCases.map(\.keychainKey)
            + TTSBackend.allCases.map(\.keychainKey)
            + [OllamaConfig.keychainURLKey]
        for key in Set(keychainKeys) {
            KeychainManager.delete(key: key)
        }
    }
    #else
    private static let preparation: Void = ()
    #endif
}
