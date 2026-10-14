import WebKit
import XCTest
@testable import Scowld

/// A message as the bundled companion page posts it to the `nativeAI` handler.
private final class PageMessage: WKScriptMessage {
    private let payload: Any

    init(body: Any) {
        payload = body
        super.init()
    }

    static func json(_ object: [String: Any]) -> PageMessage {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return PageMessage(body: String(decoding: data, as: UTF8.self))
    }

    override var body: Any { payload }
}

/// The native half of the bridge between the bundled 3D companion page and the
/// app: chat requests, speech requests and page events. Provider HTTP is
/// answered by `StubURLProtocol`; no page, key or network is needed.
@MainActor
final class CompanionBridgeTests: XCTestCase {
    private func makeCoordinator(apiKey: String? = "sk-bridge") -> (AmicaFullView.Coordinator, MemoryStore) {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        let keychain = KeychainSnapshot(keys: [AIProvider.openai.keychainKey, TTSBackend.elevenLabs.keychainKey])
        if let apiKey {
            XCTAssertTrue(KeychainManager.save(key: AIProvider.openai.keychainKey, value: apiKey))
        } else {
            KeychainManager.delete(key: AIProvider.openai.keychainKey)
        }
        KeychainManager.delete(key: TTSBackend.elevenLabs.keychainKey)
        UserDefaults.standard.set(AIProvider.openai.rawValue, forKey: "selectedProvider")
        UserDefaults.standard.set("Iris", forKey: "character_name")
        addTeardownBlock { @MainActor in
            StubURLProtocol.uninstall()
            keychain.restore()
            defaults.restore()
        }
        let store = MemoryStore(inMemory: true)
        return (AmicaFullView.Coordinator(memoryStore: store), store)
    }

    private func post(_ message: PageMessage, to coordinator: AmicaFullView.Coordinator) {
        coordinator.userContentController(WKUserContentController(), didReceive: message)
    }

    private func chat(_ text: String) -> PageMessage {
        .json(["type": "chat", "callbackId": "cb-1", "messages": [["role": "user", "content": text]]])
    }

    func testChatRequestIsAnsweredByTheSelectedProviderAndSaved() async throws {
        let (coordinator, store) = makeCoordinator()
        StubURLProtocol.install { _ in .json(["choices": [["message": ["content": "[happy] Bridge reply"]]]]) }
        let reply = expectation(forNotification: .aiResponseReady, object: nil) { notification in
            (notification.object as? String) == "[happy] Bridge reply"
        }

        post(chat("Hello bridge"), to: coordinator)
        await fulfillment(of: [reply], timeout: 5)

        XCTAssertEqual(store.fetchMessages().map(\.content), ["Hello bridge", "[happy] Bridge reply"])
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-bridge")
        let messages = try XCTUnwrap(sent.json["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.first?["content"] as? String)?.hasPrefix("You are Iris") == true,
                      "The system prompt carries the character name")
        XCTAssertEqual(messages.last?["content"] as? String, "Hello bridge")
    }

    func testChatWithoutAKeyNeverReachesTheNetwork() async throws {
        let (coordinator, store) = makeCoordinator(apiKey: nil)
        StubURLProtocol.install { _ in .json([:]) }
        let reply = expectation(forNotification: .aiResponseReady, object: nil)
        reply.isInverted = true

        post(chat("Hi"), to: coordinator)
        await fulfillment(of: [reply], timeout: 1)

        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertTrue(store.fetchMessages().isEmpty)
    }

    func testRequestsAreIgnoredWhileTheChatTabIsInactive() async throws {
        let (coordinator, store) = makeCoordinator()
        StubURLProtocol.install { _ in .json(["choices": [["message": ["content": "late"]]]]) }
        coordinator.setRuntimeActive(false)
        let reply = expectation(forNotification: .aiResponseReady, object: nil)
        reply.isInverted = true

        post(chat("Are you there?"), to: coordinator)
        await fulfillment(of: [reply], timeout: 1)

        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertTrue(store.fetchMessages().isEmpty)
    }

    func testSpeechWithoutAnElevenLabsKeyFailsWithoutARequest() async throws {
        let (coordinator, _) = makeCoordinator()
        StubURLProtocol.install { _ in .json([:]) }
        let failed = expectation(forNotification: .ttsFailed, object: nil)

        post(.json(["type": "tts_elevenlabs", "callbackId": "tts-1", "voiceId": "abc", "body": #"{"text":"Hi"}"#]), to: coordinator)
        await fulfillment(of: [failed], timeout: 5)

        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testPageEventsAreForwardedAndMalformedMessagesIgnored() async throws {
        let (coordinator, store) = makeCoordinator()
        let done = expectation(forNotification: .ttsDone, object: nil)
        let ready = expectation(forNotification: .appReady, object: nil)

        post(PageMessage(body: "not json"), to: coordinator)
        post(PageMessage(body: ["type": "chat"]), to: coordinator)
        post(.json(["type": "tts_done"]), to: coordinator)
        post(.json(["type": "app_ready"]), to: coordinator)
        await fulfillment(of: [done, ready], timeout: 2)

        XCTAssertTrue(store.fetchMessages().isEmpty)
    }
}
