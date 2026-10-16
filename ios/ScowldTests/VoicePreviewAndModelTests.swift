import XCTest
@testable import Scowld

/// Which live models a key can use, from each provider's model list.
final class LiveModelCatalogTests: XCTestCase {
    private func data(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func testRequestsUseTheKeyTheWayEachProviderExpects() throws {
        let gemini = LiveModelCatalog.request(for: .gemini, apiKey: "g-key")
        let query = URLComponents(url: try XCTUnwrap(gemini.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(gemini.url?.host(), "generativelanguage.googleapis.com")
        XCTAssertEqual(gemini.value(forHTTPHeaderField: "x-goog-api-key"), "g-key")
        XCTAssertFalse(query.contains { $0.name == "key" }, "The key never goes in the URL")

        let openAI = LiveModelCatalog.request(for: .openai, apiKey: "o-key")
        XCTAssertEqual(openAI.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(openAI.value(forHTTPHeaderField: "Authorization"), "Bearer o-key")

        let xai = LiveModelCatalog.request(for: .xai, apiKey: "x-key")
        XCTAssertEqual(xai.url?.absoluteString, "https://api.x.ai/v1/models")
        XCTAssertEqual(xai.value(forHTTPHeaderField: "Authorization"), "Bearer x-key")
    }

    func testOnlyLiveModelsAreKept() {
        let gemini = data(["models": [
            ["name": "models/gemini-3.8-live", "supportedGenerationMethods": ["bidiGenerateContent", "countTokens"]],
            ["name": "models/gemini-3.5-flash-lite", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-live-new", "supportedGenerationMethods": ["bidiGenerateContent"]],
        ]])
        XCTAssertEqual(LiveModelCatalog.liveModels(in: gemini, for: .gemini), ["gemini-3.8-live", "gemini-live-new"])

        let openAI = data(["data": [
            ["id": "gpt-realtime-2.1"], ["id": "gpt-6-luna"], ["id": "gpt-realtime-transcribe"], ["id": "gpt-realtime-2.1-mini"],
        ]])
        XCTAssertEqual(LiveModelCatalog.liveModels(in: openAI, for: .openai), ["gpt-realtime-2.1", "gpt-realtime-2.1-mini"])

        let xai = data(["data": [["id": "grok-voice-3.0"], ["id": "grok-6"]]])
        XCTAssertEqual(LiveModelCatalog.liveModels(in: xai, for: .xai), ["grok-voice-3.0"])

        XCTAssertEqual(LiveModelCatalog.liveModels(in: Data("nope".utf8), for: .gemini), [])
    }

    func testBuiltInModelsComeFirst() {
        XCTAssertEqual(
            LiveModelCatalog.merged(builtIn: ["a", "b"], fetched: ["c", "a"]),
            ["a", "b", "c"]
        )
    }
}

/// Hearing a voice before choosing it, with a scripted provider and fake audio.
@MainActor
final class VoicePreviewerTests: XCTestCase {
    private func makePreviewer() -> (VoicePreviewer, FakeSocketFactory, () -> FakeLiveAudio?) {
        let sockets = FakeSocketFactory()
        var audio: FakeLiveAudio?
        let previewer = VoicePreviewer(makeSocket: sockets.make, makeAudio: {
            let fake = FakeLiveAudio()
            audio = fake
            return fake
        })
        addTeardownBlock { @MainActor in previewer.stop() }
        return (previewer, sockets, { audio })
    }

    func testAPreviewReadsALineInTheVoiceAndCloses() async throws {
        let (previewer, sockets, audio) = makePreviewer()
        previewer.play(provider: .gemini, model: "gemini-3.8-live", voice: "Aoede", apiKey: " key ", name: "Iris")
        XCTAssertEqual(previewer.state, .loading)
        XCTAssertEqual(previewer.voice, "Aoede")
        XCTAssertEqual(audio()?.startedWith?.microphone, false, "A preview never opens the microphone")

        let socket = try XCTUnwrap(sockets.last)
        await waitUntil { socket.sent.count == 1 }
        let setup = try XCTUnwrap(socket.sentJSON[0]["setup"] as? [String: Any])
        let voice = (((setup["generationConfig"] as? [String: Any])?["speechConfig"] as? [String: Any])?["voiceConfig"] as? [String: Any])?["prebuiltVoiceConfig"] as? [String: Any]
        XCTAssertEqual(voice?["voiceName"] as? String, "Aoede")
        XCTAssertEqual(socket.request.value(forHTTPHeaderField: "x-goog-api-key"), "key")

        socket.deliver(["setupComplete": [String: Any]()])
        await waitUntil { socket.sent.count == 2 }
        let text = (socket.sentJSON[1]["realtimeInput"] as? [String: Any])?["text"] as? String
        XCTAssertTrue(text?.contains("Hi, I'm Iris!") == true)

        socket.deliver(["serverContent": ["modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": pcm(480).base64EncodedString()]]]]]])
        await waitUntil { previewer.state == .playing }
        socket.deliver(["serverContent": ["turnComplete": true]])
        await waitUntil { socket.isClosed }
        XCTAssertEqual(previewer.state, .playing, "It keeps playing what arrived")

        audio()?.finishPlayback()
        XCTAssertEqual(previewer.state, .idle)
        XCTAssertTrue(audio()?.isStopped == true)
    }

    func testARejectedKeyIsReported() async throws {
        let (previewer, sockets, _) = makePreviewer()
        previewer.play(provider: .openai, model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "bad", name: "Bella")
        let socket = try XCTUnwrap(sockets.last)
        socket.fail(LiveSocketError.refused(statusCode: 401))
        await waitUntil { if case .failed = previewer.state { return true } else { return false } }
        XCTAssertEqual(previewer.state, .failed("The provider rejected the API key (HTTP 401). Check it in Settings."))
    }

    func testWithoutAKeyNothingHappensAndTimeoutsFail() async throws {
        let (previewer, sockets, _) = makePreviewer()
        previewer.play(provider: .xai, model: "grok-voice-latest", voice: "ara", apiKey: "   ", name: "Bella")
        XCTAssertEqual(previewer.state, .idle)
        XCTAssertTrue(sockets.sockets.isEmpty)

        previewer.play(provider: .xai, model: "grok-voice-latest", voice: "ara", apiKey: "k", name: "Bella", timeout: 0.1)
        await waitUntil { if case .failed = previewer.state { return true } else { return false } }
        XCTAssertEqual(previewer.state, .failed("Couldn't connect to xAI. Check your connection and try again."))
        XCTAssertTrue(try XCTUnwrap(sockets.last).isClosed)
    }

    func testStoppingEndsThePreview() async throws {
        let (previewer, sockets, audio) = makePreviewer()
        previewer.play(provider: .openai, model: "gpt-realtime-2.1-mini", voice: "coral", apiKey: "k", name: "Bella")
        previewer.stop()
        XCTAssertEqual(previewer.state, .idle)
        XCTAssertTrue(try XCTUnwrap(sockets.last).isClosed)
        XCTAssertTrue(audio()?.isStopped == true)
    }
}
