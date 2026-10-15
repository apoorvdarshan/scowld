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

/// The native half of the bridge to the bundled 3D companion page. The page only
/// renders the companion now: conversations run natively, so its old chat and
/// speech requests are ignored. No page, key or network is needed.
@MainActor
final class CompanionBridgeTests: XCTestCase {
    private func makeCoordinator() -> (AmicaFullView.Coordinator, MemoryStore) {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { @MainActor in
            StubURLProtocol.uninstall()
            defaults.restore()
        }
        let store = MemoryStore(inMemory: true)
        return (AmicaFullView.Coordinator(memoryStore: store), store)
    }

    private func post(_ message: PageMessage, to coordinator: AmicaFullView.Coordinator) {
        coordinator.userContentController(WKUserContentController(), didReceive: message)
    }

    func testPageEventsAreForwardedAndOldRequestsAndMalformedMessagesIgnored() async throws {
        let (coordinator, store) = makeCoordinator()
        StubURLProtocol.install { _ in .json([:]) }
        let ready = expectation(forNotification: .appReady, object: nil)

        post(PageMessage(body: "not json"), to: coordinator)
        post(PageMessage(body: ["type": "chat"]), to: coordinator)
        post(.json(["type": "chat", "callbackId": "cb", "messages": [["role": "user", "content": "Hi"]]]), to: coordinator)
        post(.json(["type": "tts_elevenlabs", "callbackId": "tts", "voiceId": "abc", "body": #"{"text":"Hi"}"#]), to: coordinator)
        post(.json(["type": "console", "level": "log", "message": "hello"]), to: coordinator)
        post(.json(["type": "app_ready"]), to: coordinator)
        await fulfillment(of: [ready], timeout: 2)

        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "The page can no longer make the app call a provider")
        XCTAssertTrue(store.fetchMessages().isEmpty)
    }

    func testPageConfigCarriesTheNameAndAvatarAndKeepsThePageQuiet() {
        _ = makeCoordinator()
        UserDefaults.standard.set("Iris", forKey: "character_name")
        UserDefaults.standard.set("AvatarSample_B", forKey: "selected_avatar")

        let script = AmicaFullView.Coordinator.pageConfigScript(clearCachedSettings: true)
        XCTAssertTrue(script.contains(#"name: "Iris""#))
        XCTAssertTrue(script.contains(#"vrm_url: '/vrm/' + "AvatarSample_B" + '.vrm'"#))
        XCTAssertTrue(script.contains("tts_muted: 'true'"))
        XCTAssertTrue(script.contains("localStorage.removeItem"))
        XCTAssertFalse(script.contains("elevenlabs"), "No speech provider settings reach the page")
        XCTAssertFalse(script.contains("apikey"))

        let update = AmicaFullView.Coordinator.pageConfigScript(clearCachedSettings: false)
        XCTAssertFalse(update.contains("localStorage.removeItem"))
    }

    func testANameCannotBreakOutOfItsJavaScriptString() {
        XCTAssertEqual(AmicaFullView.Coordinator.javaScriptString("Bella"), #""Bella""#)
        let hostile = #"Bella'; alert("x"); //"#
        let literal = AmicaFullView.Coordinator.javaScriptString(hostile)
        // A JSON string literal is a valid JavaScript string literal.
        let decoded = try? JSONSerialization.jsonObject(with: Data("[\(literal)]".utf8)) as? [String]
        XCTAssertEqual(decoded, [hostile])
    }

    func testNoCameraFrameWhileTheCameraIsOff() async {
        let (coordinator, _) = makeCoordinator()
        UserDefaults.standard.set(false, forKey: "camera_enabled")
        let frame = await coordinator.captureCameraFrame()
        XCTAssertNil(frame)
    }
}
