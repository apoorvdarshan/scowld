import XCTest
@testable import Scowld

/// One live connection: setup, message order, waiting for the provider,
/// reconnecting and failures. The socket is scripted; nothing connects.
@MainActor
final class LiveSessionTests: XCTestCase {
    private final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [LiveEvent] = []
        var events: [LiveEvent] { lock.withLock { stored } }
        func append(_ event: LiveEvent) { lock.withLock { stored.append(event) } }
    }

    private func makeSession(_ provider: AIProvider) -> (LiveSession, FakeSocketFactory, EventLog) {
        let factory = FakeSocketFactory()
        let log = EventLog()
        let config = LiveSessionConfig(provider: provider, model: provider.defaultModel, voice: provider.defaultVoice, apiKey: "k", instructions: "Hi")
        let session = LiveSession(config: config, wire: provider.wire, makeSocket: factory.make) { log.append($0) }
        addTeardownBlock { session.close() }
        return (session, factory, log)
    }

    func testOpenAISendsSetupThenAudioInOrder() async throws {
        let (session, factory, log) = makeSession(.openai)
        session.connect()
        session.send(audio: pcm(4, value: 1))
        session.send(audio: pcm(4, value: 2))

        let socket = try XCTUnwrap(factory.last)
        await waitUntil { socket.sent.count == 4 }
        let types = socket.sentJSON.map { $0["type"] as? String }
        XCTAssertEqual(types, ["session.update", "session.update", "input_audio_buffer.append", "input_audio_buffer.append"])
        XCTAssertEqual(socket.sentJSON[2]["audio"] as? String, pcm(4, value: 1).base64EncodedString())
        XCTAssertEqual(log.events.first, .ready, "OpenAI needs no setup acknowledgement")
    }

    func testGeminiWaitsForSetupCompleteBeforeSendingInput() async throws {
        let (session, factory, log) = makeSession(.gemini)
        session.connect()
        session.send(audio: pcm(8, value: 3))
        session.send(text: "Hello")

        let socket = try XCTUnwrap(factory.last)
        await waitUntil { socket.sent.count == 1 }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(socket.sent.count, 1, "Only the setup goes out before setupComplete")
        XCTAssertNotNil(socket.sentJSON[0]["setup"])
        XCTAssertTrue(log.events.isEmpty)

        socket.deliver(["setupComplete": [String: Any]()])
        await waitUntil { socket.sent.count == 3 }
        XCTAssertNotNil((socket.sentJSON[1]["realtimeInput"] as? [String: Any])?["audio"])
        XCTAssertEqual((socket.sentJSON[2]["realtimeInput"] as? [String: Any])?["text"] as? String, "Hello")
        await waitUntil { log.events == [.ready] }
    }

    func testOnlyTheLatestSecondsOfSpeechWaitForTheConnection() async throws {
        let (session, factory, _) = makeSession(.gemini)
        session.connect()
        let chunk = 24_000 // half a second at 24 kHz
        let chunks = LiveSession.maximumQueuedAudioBytes / chunk + 4
        for index in 0..<chunks {
            session.send(audio: pcm(chunk, value: UInt8(index % 250)))
        }
        session.send(text: "kept")

        let socket = try XCTUnwrap(factory.last)
        socket.deliver(["setupComplete": [String: Any]()])
        await waitUntil { (socket.sentJSON.last?["realtimeInput"] as? [String: Any])?["text"] as? String == "kept" }

        let audio = socket.sentJSON.compactMap { ($0["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any] }
        XCTAssertEqual(audio.count, LiveSession.maximumQueuedAudioBytes / chunk, "The oldest audio was dropped")
        let firstKept = Data(base64Encoded: try XCTUnwrap(audio.first?["data"] as? String))
        XCTAssertEqual(firstKept?.first, UInt8((chunks - audio.count) % 250))
    }

    func testEventsAreForwardedAndTheResumptionHandleIsKept() async throws {
        let (session, factory, log) = makeSession(.gemini)
        session.connect()
        let socket = try XCTUnwrap(factory.last)
        socket.deliver(["setupComplete": [String: Any]()])
        socket.deliver(["sessionResumptionUpdate": ["newHandle": "resume-7", "resumable": true]])
        socket.deliver(["serverContent": ["outputTranscription": ["text": "Hi!"], "turnComplete": true]])
        await waitUntil { log.events.count == 3 }
        XCTAssertEqual(log.events, [.ready, .assistantText("Hi!"), .turnComplete])

        // goAway moves to a new connection that resumes with the latest handle.
        socket.deliver(["goAway": ["timeLeft": "10s"]])
        await waitUntil { factory.sockets.count == 2 }
        let next = try XCTUnwrap(factory.last)
        await waitUntil { next.sent.count == 1 }
        let setup = try XCTUnwrap(next.sentJSON[0]["setup"] as? [String: Any])
        XCTAssertEqual((setup["sessionResumption"] as? [String: Any])?["handle"] as? String, "resume-7")
        XCTAssertTrue(socket.isClosed)

        session.send(text: "still here")
        next.deliver(["setupComplete": [String: Any]()])
        await waitUntil { next.sent.count == 2 }
        XCTAssertFalse(log.events.contains { if case .closed = $0 { return true } else { return false } },
                       "Moving connections doesn't end the session")
    }

    func testADroppedConnectionIsReportedOnce() async throws {
        let (session, factory, log) = makeSession(.openai)
        session.connect()
        let socket = try XCTUnwrap(factory.last)
        socket.fail(LiveSocketError.refused(statusCode: 401))
        await waitUntil { log.events.contains { if case .closed = $0 { return true } else { return false } } }

        let closed = log.events.compactMap { event -> String?? in
            if case .closed(let message) = event { return message } else { return nil }
        }
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first ?? nil, "The provider rejected the API key (HTTP 401). Check it in Settings.")
        session.send(text: "too late")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(socket.sentJSON.contains { $0["type"] as? String == "conversation.item.create" })
    }

    func testClosingStopsEverything() async throws {
        let (session, factory, log) = makeSession(.openai)
        session.connect()
        let socket = try XCTUnwrap(factory.last)
        await waitUntil { socket.sent.count == 2 }
        session.close()
        XCTAssertTrue(socket.isClosed)
        session.send(audio: pcm(4))
        socket.deliver(#"{"type":"response.done"}"#)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(socket.sent.count, 2)
        XCTAssertEqual(log.events, [.ready], "No events after close")
    }

    func testTruncateUsesTheWire() async throws {
        let (session, factory, _) = makeSession(.openai)
        session.connect()
        session.truncate(itemID: "item_2", audioEndMs: 1500)
        let socket = try XCTUnwrap(factory.last)
        await waitUntil { socket.sent.count == 3 }
        XCTAssertEqual(socket.sentJSON[2]["type"] as? String, "conversation.item.truncate")
        XCTAssertEqual(socket.sentJSON[2]["audio_end_ms"] as? Int, 1500)
    }
}
