import XCTest
@testable import Scowld

/// How each provider's live session is framed on the wire. Pure message building
/// and parsing; nothing connects.
final class LiveWireTests: XCTestCase {
    private func config(_ provider: AIProvider, model: String? = nil, voice: String? = nil) -> LiveSessionConfig {
        LiveSessionConfig(
            provider: provider,
            model: model ?? provider.defaultModel,
            voice: voice ?? provider.defaultVoice,
            apiKey: "test-key",
            instructions: "Be Bella."
        )
    }

    private func json(_ message: String) throws -> [String: Any] {
        try XCTUnwrap(LiveJSON.object(message))
    }

    /// The message re-encoded with sorted keys, so equal messages compare equal.
    /// JSONSerialization writes a dictionary's keys in the dictionary's own order,
    /// and two dictionaries built separately with the same keys can order them
    /// differently, so the same message can come out as different strings.
    private func canonical(_ message: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(message.utf8))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Gemini

    func testPremiumGoesThroughScowldAndReadsItsNotices() throws {
        let wire = ScowldPremiumWire()
        let premium = LiveSessionConfig(provider: .gemini, model: "gemini-3.8-live", voice: "Leda", apiKey: "$RCAnonymousID:abc", instructions: "Hi")
        let request = wire.request(for: premium)
        XCTAssertEqual(request.url?.absoluteString, "wss://scowld.xyz/api/live")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Scowld-User"), "$RCAnonymousID:abc")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
        XCTAssertEqual(
            try wire.setupMessages(for: premium, resumptionHandle: nil).map(canonical),
            try GeminiLiveWire().setupMessages(for: premium, resumptionHandle: nil).map(canonical)
        )
        XCTAssertEqual(wire.inputSampleRate, 16_000)
        XCTAssertNil(wire.truncateMessage(itemID: "i", audioEndMs: 10))

        XCTAssertEqual(wire.parse(#"{"scowld":{"event":"out_of_minutes"}}"#), [.premiumOutOfMinutes])
        XCTAssertEqual(wire.parse(#"{"scowld":{"event":"unavailable"}}"#), [.premiumUnavailable])
        XCTAssertEqual(wire.parse(#"{"scowld":{"event":"something_new"}}"#), [])
        XCTAssertEqual(wire.parse(#"{"setupComplete":{}}"#), [.ready], "Gemini's own messages pass through")
    }

    func testGeminiRequestAndSetup() throws {
        let wire = GeminiLiveWire()
        let request = wire.request(for: config(.gemini))
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host(), "generativelanguage.googleapis.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
        XCTAssertNil(request.url?.query, "The key never goes in the URL")
        XCTAssertEqual(wire.inputSampleRate, 16_000)
        XCTAssertEqual(wire.outputSampleRate, 24_000)
        XCTAssertTrue(wire.waitsForSetupAcknowledgement)

        let messages = wire.setupMessages(for: config(.gemini, voice: "Aoede"), resumptionHandle: nil)
        XCTAssertEqual(messages.count, 1)
        let setup = try XCTUnwrap(try json(messages[0])["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.8-live")
        let generation = try XCTUnwrap(setup["generationConfig"] as? [String: Any])
        XCTAssertEqual(generation["responseModalities"] as? [String], ["AUDIO"])
        let voice = ((generation["speechConfig"] as? [String: Any])?["voiceConfig"] as? [String: Any])?["prebuiltVoiceConfig"] as? [String: Any]
        XCTAssertEqual(voice?["voiceName"] as? String, "Aoede")
        let instruction = (setup["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]]
        XCTAssertEqual(instruction?.first?["text"] as? String, "Be Bella.")
        XCTAssertNotNil(setup["inputAudioTranscription"])
        XCTAssertNotNil(setup["outputAudioTranscription"])
        XCTAssertNotNil((setup["contextWindowCompression"] as? [String: Any])?["slidingWindow"])
        XCTAssertEqual((setup["sessionResumption"] as? [String: Any])?.isEmpty, true)

        let resumed = try json(wire.setupMessages(for: config(.gemini, model: "models/custom-live"), resumptionHandle: "handle-1")[0])
        let resumedSetup = try XCTUnwrap(resumed["setup"] as? [String: Any])
        XCTAssertEqual(resumedSetup["model"] as? String, "models/custom-live")
        XCTAssertEqual((resumedSetup["sessionResumption"] as? [String: Any])?["handle"] as? String, "handle-1")
    }

    func testGeminiAudioTextAndImage() throws {
        let wire = GeminiLiveWire()
        let audio = try XCTUnwrap(try json(wire.audioMessage(Data([1, 2, 3, 4])))["realtimeInput"] as? [String: Any])
        let chunk = try XCTUnwrap(audio["audio"] as? [String: Any])
        XCTAssertEqual(chunk["mimeType"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual(chunk["data"] as? String, Data([1, 2, 3, 4]).base64EncodedString())

        let messages = wire.textMessages("Look at this", image: Data([9]))
        XCTAssertEqual(messages.count, 2, "The frame goes first, then the text")
        let frame = try XCTUnwrap((try json(messages[0])["realtimeInput"] as? [String: Any])?["video"] as? [String: Any])
        XCTAssertEqual(frame["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual((try json(messages[1])["realtimeInput"] as? [String: Any])?["text"] as? String, "Look at this")
        XCTAssertEqual(wire.textMessages("Hi", image: nil).count, 1)
        XCTAssertNil(wire.truncateMessage(itemID: "x", audioEndMs: 10))
    }

    func testGeminiParsesServerMessages() {
        let wire = GeminiLiveWire()
        XCTAssertEqual(wire.parse(#"{"setupComplete":{}}"#), [.ready])

        let audio = Data([5, 6, 7, 8])
        let content = LiveJSON.string(["serverContent": [
            "modelTurn": ["parts": [
                ["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": audio.base64EncodedString()]],
                ["inlineData": ["mimeType": "image/png", "data": "AAAA"]],
                ["text": "ignored"],
            ]],
            "inputTranscription": ["text": "Hi "],
            "outputTranscription": ["text": "Hello!"],
            "interrupted": true,
            "turnComplete": true,
        ]])
        XCTAssertEqual(wire.parse(content), [
            .audio(audio, itemID: nil),
            .userText("Hi ", replacing: false),
            .assistantText("Hello!"),
            .interrupted,
            .turnComplete,
        ])

        XCTAssertEqual(wire.parse(#"{"sessionResumptionUpdate":{"newHandle":"h2","resumable":true}}"#), [.resumptionHandle("h2")])
        XCTAssertEqual(wire.parse(#"{"sessionResumptionUpdate":{"newHandle":"h3","resumable":false}}"#), [])
        XCTAssertEqual(wire.parse(#"{"goAway":{"timeLeft":"5s"}}"#), [.goAway])
        XCTAssertEqual(wire.parse(#"{"error":{"message":"Bad model"}}"#), [.error("Bad model")])
        XCTAssertEqual(wire.parse("not json"), [])
        XCTAssertEqual(wire.parse(#"{"serverContent":{}}"#), [])
    }

    // MARK: OpenAI

    func testOpenAIRequestAndSetup() throws {
        let wire = OpenAIRealtimeWire()
        let request = wire.request(for: config(.openai, model: "gpt-realtime-2.1"))
        XCTAssertEqual(request.url?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertFalse(wire.waitsForSetupAcknowledgement)
        XCTAssertEqual(wire.inputSampleRate, 24_000)

        let messages = wire.setupMessages(for: config(.openai, voice: "coral"), resumptionHandle: nil)
        XCTAssertEqual(messages.count, 2, "Transcription is configured separately")
        let main = try XCTUnwrap(try json(messages[0])["session"] as? [String: Any])
        XCTAssertEqual(main["type"] as? String, "realtime")
        XCTAssertEqual(main["instructions"] as? String, "Be Bella.")
        XCTAssertEqual(main["output_modalities"] as? [String], ["audio"])
        let audio = try XCTUnwrap(main["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        XCTAssertEqual((input["format"] as? [String: Any])?["rate"] as? Int, 24_000)
        let turns = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turns["type"] as? String, "semantic_vad")
        XCTAssertEqual(turns["interrupt_response"] as? Bool, true)
        XCTAssertEqual((audio["output"] as? [String: Any])?["voice"] as? String, "coral")

        let transcription = try XCTUnwrap(try json(messages[1])["session"] as? [String: Any])
        let model = (((transcription["audio"] as? [String: Any])?["input"] as? [String: Any])?["transcription"] as? [String: Any])?["model"] as? String
        XCTAssertEqual(model, OpenAIRealtimeWire.transcriptionModel)
    }

    func testOpenAIInputMessages() throws {
        let wire = OpenAIRealtimeWire()
        let append = try json(wire.audioMessage(Data([1, 2])))
        XCTAssertEqual(append["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(append["audio"] as? String, Data([1, 2]).base64EncodedString())

        let text = wire.textMessages("What is this?", image: Data([7]))
        XCTAssertEqual(text.count, 2)
        let item = try XCTUnwrap(try json(text[0])["item"] as? [String: Any])
        let content = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["input_text", "input_image"])
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64,\(Data([7]).base64EncodedString())")
        XCTAssertEqual(try json(text[1])["type"] as? String, "response.create")

        let frame = try json(try XCTUnwrap(wire.imageMessages(Data([7])).first))
        XCTAssertEqual(frame["type"] as? String, "conversation.item.create")
        let frameContent = (frame["item"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(frameContent?.first?["type"] as? String, "input_image")

        let truncate = try json(try XCTUnwrap(wire.truncateMessage(itemID: "item_9", audioEndMs: -5)))
        XCTAssertEqual(truncate["type"] as? String, "conversation.item.truncate")
        XCTAssertEqual(truncate["item_id"] as? String, "item_9")
        XCTAssertEqual(truncate["audio_end_ms"] as? Int, 0)
    }

    func testRealtimeEventsParse() {
        let wire = OpenAIRealtimeWire()
        let audio = Data([1, 2, 3, 4])
        XCTAssertEqual(
            wire.parse(LiveJSON.string(["type": "response.output_audio.delta", "item_id": "item_1", "delta": audio.base64EncodedString()])),
            [.audio(audio, itemID: "item_1")]
        )
        XCTAssertEqual(wire.parse(#"{"type":"response.output_audio_transcript.delta","delta":"Hi"}"#), [.assistantText("Hi")])
        XCTAssertEqual(
            wire.parse(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"Hello there"}"#),
            [.userText("Hello there", replacing: true)]
        )
        XCTAssertEqual(wire.parse(#"{"type":"input_audio_buffer.speech_started"}"#), [.userSpeechStarted])
        XCTAssertEqual(wire.parse(#"{"type":"response.done","response":{"status":"completed"}}"#), [.turnComplete])
        XCTAssertEqual(wire.parse(#"{"type":"error","error":{"message":"Invalid voice"}}"#), [.error("Invalid voice")])
        XCTAssertEqual(wire.parse(#"{"type":"session.updated"}"#), [])
        XCTAssertEqual(wire.parse("[]"), [])
    }

    // MARK: xAI

    func testXAIRequestSetupAndEvents() throws {
        let wire = XAIVoiceWire()
        let request = wire.request(for: config(.xai))
        XCTAssertEqual(request.url?.absoluteString, "wss://api.x.ai/v1/realtime?model=grok-voice-latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let setup = try XCTUnwrap(try json(try XCTUnwrap(wire.setupMessages(for: config(.xai, voice: "eve"), resumptionHandle: nil).first))["session"] as? [String: Any])
        XCTAssertEqual(setup["voice"] as? String, "eve")
        XCTAssertEqual((setup["turn_detection"] as? [String: Any])?["type"] as? String, "server_vad")
        XCTAssertEqual(setup["instructions"] as? String, "Be Bella.")

        XCTAssertTrue(wire.imageMessages(Data([1])).isEmpty, "xAI takes no images")
        let text = wire.textMessages("Hi", image: Data([1]))
        let content = (try json(text[0])["item"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1, "The camera frame is left out")
        XCTAssertNil(wire.truncateMessage(itemID: "x", audioEndMs: 1))

        // xAI's transcript of what the user said is cumulative.
        XCTAssertEqual(
            wire.parse(#"{"type":"conversation.item.input_audio_transcription.updated","transcript":"Hey Bel"}"#),
            [.userText("Hey Bel", replacing: true)]
        )
        let audio = Data([9, 9])
        XCTAssertEqual(wire.parse(LiveJSON.string(["type": "response.audio.delta", "delta": audio.base64EncodedString()])), [.audio(audio, itemID: nil)])
        XCTAssertEqual(wire.parse(#"{"type":"response.text.delta","delta":"Yo"}"#), [.assistantText("Yo")])
    }

    func testEveryProviderHasAWire() {
        XCTAssertTrue(AIProvider.gemini.wire is GeminiLiveWire)
        XCTAssertTrue(AIProvider.openai.wire is OpenAIRealtimeWire)
        XCTAssertTrue(AIProvider.xai.wire is XAIVoiceWire)
    }
}
