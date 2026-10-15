import XCTest
@testable import Scowld

/// A live conversation end to end, with a scripted provider and fake audio:
/// connecting, playback and lip sync, interruptions, typing, saved turns,
/// the camera and timeouts.
@MainActor
final class LiveConversationTests: XCTestCase {
    private struct Harness {
        let conversation: LiveConversation
        let store: MemoryStore
        let sockets: FakeSocketFactory
        let audio: () -> FakeLiveAudio?
        let clock: () -> Date
        let advance: (TimeInterval) -> Void
    }

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private func makeConversation(_ provider: AIProvider, key: String? = "live-key") -> Harness {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { defaults.restore() }
        UserDefaults.standard.set(provider.rawValue, forKey: HostedServiceConfig.providerDefaultsKey)
        UserDefaults.standard.set("Iris", forKey: "character_name")

        let store = MemoryStore(inMemory: true)
        let sockets = FakeSocketFactory()
        let audio = Box<FakeLiveAudio?>(nil)
        let now = Box(Date(timeIntervalSince1970: 1_000_000))
        let conversation = LiveConversation(
            memoryStore: store,
            makeSocket: sockets.make,
            makeAudio: {
                let fake = FakeLiveAudio()
                audio.value = fake
                return fake
            },
            loadKey: { _ in key },
            now: { now.value }
        )
        addTeardownBlock { @MainActor in conversation.end() }
        return Harness(
            conversation: conversation,
            store: store,
            sockets: sockets,
            audio: { audio.value },
            clock: { now.value },
            advance: { now.value = now.value.addingTimeInterval($0) }
        )
    }

    private func audioDelta(_ data: Data, item: String) -> [String: Any] {
        ["type": "response.output_audio.delta", "item_id": item, "delta": data.base64EncodedString()]
    }

    // MARK: Starting

    func testWithoutAKeyNothingConnects() {
        let h = makeConversation(.gemini, key: "  ")
        h.conversation.start(microphone: true)
        XCTAssertEqual(h.conversation.phase, .idle)
        XCTAssertTrue(h.sockets.sockets.isEmpty)
        XCTAssertNil(h.audio())
        XCTAssertEqual(h.conversation.errorMessage, "Add your Gemini API key in Settings to talk to Iris.")
    }

    func testAMicrophoneProblemIsReported() {
        let h = makeConversation(.openai)
        let audio = FakeLiveAudio()
        audio.failsToStart = true
        let conversation = LiveConversation(memoryStore: h.store, makeSocket: h.sockets.make, makeAudio: { audio }, loadKey: { _ in "k" })
        conversation.start(microphone: true)
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertTrue(audio.isStopped)
        XCTAssertTrue(h.sockets.sockets.isEmpty)
        XCTAssertEqual(conversation.errorMessage, "The microphone isn't available. Check microphone access in Settings.")
    }

    func testGeminiConnectsStreamsTheMicrophoneAndGoesLive() async throws {
        let h = makeConversation(.gemini)
        h.conversation.start(microphone: true)
        XCTAssertEqual(h.conversation.phase, .connecting)
        XCTAssertTrue(h.conversation.isMicrophoneOn)
        let audio = try XCTUnwrap(h.audio())
        XCTAssertEqual(audio.startedWith?.input, 16_000)
        XCTAssertEqual(audio.startedWith?.output, 24_000)
        XCTAssertEqual(audio.startedWith?.microphone, true)

        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { socket.sent.count == 1 }
        let setup = try XCTUnwrap(socket.sentJSON[0]["setup"] as? [String: Any])
        let instructions = ((setup["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String
        XCTAssertTrue(instructions?.hasPrefix("You are Iris") == true)

        audio.speak(pcm(6, value: 4))
        socket.deliver(["setupComplete": [String: Any]()])
        await waitUntil { h.conversation.phase == .live }
        await waitUntil { socket.sent.count == 2 }
        let chunk = (socket.sentJSON[1]["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any]
        XCTAssertEqual(chunk?["data"] as? String, pcm(6, value: 4).base64EncodedString(), "Speech before the connection was ready is kept")
    }

    // MARK: Replies

    func testReplyPlaysWithLipSyncCaptionsAndIsSavedAfterTheUsersWords() async throws {
        let h = makeConversation(.gemini)
        var lipChunks: [LipSyncChunk] = []
        h.conversation.onLipSync = { lipChunks.append($0) }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        socket.deliver(["setupComplete": [String: Any]()])

        let reply = pcm(480)
        socket.deliver(["serverContent": ["inputTranscription": ["text": "How was "]]])
        socket.deliver(["serverContent": ["inputTranscription": ["text": "your day?"]]])
        socket.deliver(["serverContent": [
            "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": reply.base64EncodedString()]]]],
            "outputTranscription": ["text": "Wonderful, thanks!"],
        ]])
        await waitUntil { h.conversation.isAssistantSpeaking }
        XCTAssertEqual(h.audio()?.played, [reply])
        XCTAssertEqual(lipChunks.count, 1)
        XCTAssertEqual(h.conversation.assistantCaption, "Wonderful, thanks!")

        socket.deliver(["serverContent": ["turnComplete": true]])
        await waitUntil { h.store.fetchMessages().count == 2 }
        XCTAssertEqual(h.store.fetchMessages().map(\.role), [.user, .assistant])
        XCTAssertEqual(h.store.fetchMessages().map(\.content), ["How was your day?", "Wonderful, thanks!"])
        XCTAssertEqual(h.conversation.assistantCaption, "Wonderful, thanks!", "The caption stays while she is still talking")

        h.audio()?.finishPlayback()
        XCTAssertFalse(h.conversation.isAssistantSpeaking)
        XCTAssertEqual(h.conversation.assistantCaption, "")
    }

    func testSpeakingOverOpenAIStopsHerAndReportsWhatWasHeard() async throws {
        let h = makeConversation(.openai)
        var lipStops = 0
        h.conversation.onLipSyncStop = { lipStops += 1 }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { h.conversation.phase == .live }

        socket.deliver(audioDelta(pcm(48_000), item: "item_7"))
        await waitUntil { h.conversation.isAssistantSpeaking }
        let audio = try XCTUnwrap(h.audio())
        audio.playbackPosition = 0.4

        socket.deliver(#"{"type":"input_audio_buffer.speech_started"}"#)
        await waitUntil { !h.conversation.isAssistantSpeaking }
        XCTAssertEqual(audio.stopPlaybackCount, 1)
        XCTAssertEqual(lipStops, 1)
        await waitUntil { socket.sentJSON.contains { $0["type"] as? String == "conversation.item.truncate" } }
        let truncate = try XCTUnwrap(socket.sentJSON.first { $0["type"] as? String == "conversation.item.truncate" })
        XCTAssertEqual(truncate["item_id"] as? String, "item_7")
        XCTAssertEqual(truncate["audio_end_ms"] as? Int, 400)
    }

    func testGeminiInterruptionStopsPlaybackWithoutATruncate() async throws {
        let h = makeConversation(.gemini)
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        socket.deliver(["setupComplete": [String: Any]()])
        socket.deliver(["serverContent": ["modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": pcm(100).base64EncodedString()]]]]]])
        await waitUntil { h.conversation.isAssistantSpeaking }
        socket.deliver(["serverContent": ["interrupted": true]])
        await waitUntil { !h.conversation.isAssistantSpeaking }
        XCTAssertEqual(h.audio()?.stopPlaybackCount, 1)
        XCTAssertEqual(socket.sent.count, 1, "Only the setup was sent")
    }

    // MARK: Typing

    func testTypingWithoutAConversationStartsATypedOne() async throws {
        let h = makeConversation(.openai)
        h.conversation.send("Hello from the keyboard")
        XCTAssertEqual(h.conversation.phase, .connecting)
        XCTAssertFalse(h.conversation.isMicrophoneOn)
        XCTAssertEqual(h.audio()?.startedWith?.microphone, false)
        XCTAssertNil(h.audio()?.onMicrophoneAudio)

        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { socket.sentJSON.contains { $0["type"] as? String == "response.create" } }
        let item = try XCTUnwrap(socket.sentJSON.first { $0["type"] as? String == "conversation.item.create" })
        let content = (item["item"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "Hello from the keyboard")
        XCTAssertEqual(h.store.fetchMessages().map(\.content), ["Hello from the keyboard"])
    }

    func testTypingOverHerCancelsTheReply() async throws {
        let h = makeConversation(.openai)
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { h.conversation.phase == .live }
        socket.deliver(audioDelta(pcm(2_400), item: "item_1"))
        await waitUntil { h.conversation.isAssistantSpeaking }

        h.conversation.send("Wait, stop")
        XCTAssertFalse(h.conversation.isAssistantSpeaking)
        await waitUntil { socket.sentJSON.contains { $0["type"] as? String == "response.create" } }
        let types = socket.sentJSON.compactMap { $0["type"] as? String }.filter { $0 != "session.update" }
        XCTAssertEqual(types, ["conversation.item.truncate", "response.cancel", "conversation.item.create", "response.create"])
    }

    func testStartingTheMicrophoneTurnsATypedConversationIntoAVoiceOne() async throws {
        let h = makeConversation(.gemini)
        h.conversation.send("Hi")
        let typed = try XCTUnwrap(h.sockets.last)
        h.conversation.start(microphone: true)
        XCTAssertTrue(typed.isClosed)
        XCTAssertEqual(h.sockets.sockets.count, 2)
        XCTAssertTrue(h.conversation.isMicrophoneOn)
    }

    // MARK: Camera

    func testOpenAIGetsTheLatestFrameWithWhatTheUserSays() async throws {
        let h = makeConversation(.openai)
        h.conversation.isCameraOn = { true }
        h.conversation.captureCameraFrame = { Data([0xFF, 0xD8]) }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { h.conversation.phase == .live }

        socket.deliver(#"{"type":"input_audio_buffer.speech_started"}"#)
        await waitUntil { socket.sentJSON.contains { $0["type"] as? String == "conversation.item.create" } }
        let item = try XCTUnwrap(socket.sentJSON.first { $0["type"] as? String == "conversation.item.create" })
        let content = (item["item"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "input_image")
        XCTAssertFalse(socket.sentJSON.contains { $0["type"] as? String == "response.create" }, "The frame alone asks for no reply")
    }

    func testGeminiWatchesFramesWhileTheCameraIsOn() async throws {
        let h = makeConversation(.gemini)
        h.conversation.isCameraOn = { true }
        h.conversation.captureCameraFrame = { Data([0xFF, 0xD8, 0x01]) }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        socket.deliver(["setupComplete": [String: Any]()])
        await waitUntil {
            socket.sentJSON.contains { ($0["realtimeInput"] as? [String: Any])?["video"] != nil }
        }
    }

    func testNoFramesWhileTheCameraIsOffOrWithXAI() async throws {
        let h = makeConversation(.xai)
        var captures = 0
        h.conversation.isCameraOn = { true }
        h.conversation.captureCameraFrame = { captures += 1; return Data([1]) }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { h.conversation.phase == .live }
        socket.deliver(#"{"type":"input_audio_buffer.speech_started"}"#)
        h.conversation.send("What do you see?")
        await waitUntil { socket.sentJSON.contains { $0["type"] as? String == "response.create" } }
        XCTAssertEqual(captures, 0, "xAI takes no images")
    }

    // MARK: Ending

    func testAProviderFailureEndsTheConversationAndKeepsWhatWasSaid() async throws {
        let h = makeConversation(.openai)
        var ended = 0
        h.conversation.onEnded = { ended += 1 }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        await waitUntil { h.conversation.phase == .live }
        socket.deliver(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"Are you there?"}"#)
        socket.deliver(#"{"type":"response.output_audio_transcript.delta","delta":"Yes, I"}"#)
        await waitUntil { h.conversation.assistantCaption == "Yes, I" }

        socket.fail(URLError(.networkConnectionLost))
        await waitUntil { h.conversation.phase == .idle }
        XCTAssertEqual(ended, 1)
        XCTAssertNotNil(h.conversation.errorMessage)
        XCTAssertTrue(h.audio()?.isStopped == true)
        XCTAssertEqual(h.store.fetchMessages().map(\.content), ["Are you there?", "Yes, I"])
    }

    func testIdleAndConnectionTimeouts() async throws {
        let h = makeConversation(.gemini)
        h.conversation.start(microphone: true)
        h.advance(LiveConversation.connectTimeout + 1)
        h.conversation.checkTimeouts()
        XCTAssertEqual(h.conversation.phase, .idle)
        XCTAssertEqual(h.conversation.errorMessage, "Couldn't connect to Gemini. Check your connection and try again.")

        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        socket.deliver(["setupComplete": [String: Any]()])
        await waitUntil { h.conversation.phase == .live }
        h.advance(LiveConversation.microphoneIdleTimeout - 5)
        h.conversation.checkTimeouts()
        XCTAssertEqual(h.conversation.phase, .live)
        h.advance(10)
        h.conversation.checkTimeouts()
        XCTAssertEqual(h.conversation.phase, .idle, "A silent conversation ends by itself")
        XCTAssertTrue(socket.isClosed)
    }

    func testAnAudioInterruptionEndsTheConversation() async throws {
        let h = makeConversation(.gemini)
        var ended = 0
        h.conversation.onEnded = { ended += 1 }
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        h.audio()?.interrupt()
        XCTAssertEqual(h.conversation.phase, .idle)
        XCTAssertEqual(ended, 1)
        XCTAssertTrue(socket.isClosed)
        XCTAssertNil(h.conversation.errorMessage, "An interruption isn't an error")
    }

    func testEventsFromAnEndedConversationAreIgnored() async throws {
        let h = makeConversation(.gemini)
        h.conversation.start(microphone: true)
        let socket = try XCTUnwrap(h.sockets.last)
        h.conversation.end()
        socket.deliver(["setupComplete": [String: Any]()])
        socket.deliver(["serverContent": ["outputTranscription": ["text": "late"], "turnComplete": true]])
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(h.conversation.phase, .idle)
        XCTAssertTrue(h.store.fetchMessages().isEmpty)
    }
}
