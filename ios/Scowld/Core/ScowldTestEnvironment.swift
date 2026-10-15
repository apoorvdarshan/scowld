import CoreData
import Foundation

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
    /// recognition or the camera, never starts a live conversation, and never shows
    /// a permission prompt.
    static var isRunningTests: Bool {
        isUITesting || isHostingUnitTests
    }

    /// The bundled 3D companion (WebGL in a web view, with its own network
    /// requests) is left out of UI tests: CI simulators render it in software,
    /// too slowly to drive the app. Its native bridge is covered by unit tests.
    static var loadsCompanion: Bool {
        !isUITesting
    }

    /// Debug simulator only: the tab to open at launch, for screenshots
    /// (`--preview-tab chat|chats|settings|about`).
    static var previewTab: String? {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--preview-tab"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
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

        let keychainKeys = AIProvider.allCases.map(\.keychainKey) + LegacySettingsCleanup.legacyKeychainKeys
        for key in Set(keychainKeys) {
            KeychainManager.delete(key: key)
        }
    }
    #else
    private static let preparation: Void = ()
    #endif
}
