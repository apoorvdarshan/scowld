import Foundation

// MARK: - Session settings and events

nonisolated struct LiveSessionConfig: Sendable, Equatable {
    let provider: AIProvider
    let model: String
    let voice: String
    let apiKey: String
    let instructions: String
}

/// What a provider says during a live session, in one shared vocabulary.
nonisolated enum LiveEvent: Equatable, Sendable {
    /// The session is configured and accepts audio and text.
    case ready
    /// Part of the companion's reply: 16-bit little-endian mono PCM at the wire's output rate.
    /// OpenAI names the reply item, so playback can be cut at the right point on interruption.
    case audio(Data, itemID: String?)
    /// Part of the transcript of what the companion is saying.
    case assistantText(String)
    /// The transcript of what the user said: a part to append, or the whole utterance so far.
    case userText(String, replacing: Bool)
    /// The user started speaking (OpenAI and xAI report this; it also ends any reply in progress).
    case userSpeechStarted
    /// The provider stopped its reply because the user spoke (Gemini).
    case interrupted
    /// The companion finished its turn.
    case turnComplete
    /// Gemini: a handle that resumes this session on a new connection.
    case resumptionHandle(String)
    /// Gemini: this connection will close soon; reconnect with the latest handle.
    case goAway
    /// The provider reported a problem; the session continues unless it also closes.
    case error(String)
    /// The connection ended. The message explains an unexpected end.
    case closed(String?)
}

// MARK: - Wire protocol

/// How one provider frames a live session on the wire.
nonisolated protocol LiveWire: Sendable {
    /// Sample rate of the microphone audio the provider expects (16-bit mono PCM).
    var inputSampleRate: Double { get }
    /// Sample rate of the reply audio the provider sends (16-bit mono PCM).
    var outputSampleRate: Double { get }
    /// Whether the session is ready only after the provider acknowledges the setup.
    var waitsForSetupAcknowledgement: Bool { get }

    func request(for config: LiveSessionConfig) -> URLRequest
    func setupMessages(for config: LiveSessionConfig, resumptionHandle: String?) -> [String]
    func audioMessage(_ pcm16: Data) -> String
    /// Typed text, optionally with the latest camera frame, followed by a request for a reply.
    func textMessages(_ text: String, image: Data?) -> [String]
    /// A camera frame on its own (no reply requested). Empty if the provider takes no images.
    func imageMessages(_ jpeg: Data) -> [String]
    /// Tells the provider how much of a reply the user actually heard, or nil if unsupported.
    func truncateMessage(itemID: String, audioEndMs: Int) -> String?
    /// Stops a reply in progress (before typed text asks for a new one).
    func cancelReplyMessages() -> [String]
    func parse(_ message: String) -> [LiveEvent]
}

nonisolated extension AIProvider {
    var wire: any LiveWire {
        switch self {
        case .gemini: GeminiLiveWire()
        case .openai: OpenAIRealtimeWire()
        case .xai: XAIVoiceWire()
        }
    }
}

// MARK: - Gemini Live

/// Gemini Live API over a raw WebSocket (BidiGenerateContent).
nonisolated struct GeminiLiveWire: LiveWire {
    let inputSampleRate = 16_000.0
    let outputSampleRate = 24_000.0
    let waitsForSetupAcknowledgement = true

    static let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    func request(for config: LiveSessionConfig) -> URLRequest {
        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        return URLRequest(url: components.url!)
    }

    func setupMessages(for config: LiveSessionConfig, resumptionHandle: String?) -> [String] {
        let model = config.model.hasPrefix("models/") ? config.model : "models/\(config.model)"
        var resumption: [String: Any] = [:]
        if let resumptionHandle { resumption["handle"] = resumptionHandle }
        let setup: [String: Any] = [
            "model": model,
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": config.voice]]],
            ],
            "systemInstruction": ["parts": [["text": config.instructions]]],
            "inputAudioTranscription": [String: Any](),
            "outputAudioTranscription": [String: Any](),
            // Without compression an audio session ends after 15 minutes, and one with
            // camera frames after 2.
            "contextWindowCompression": ["slidingWindow": [String: Any]()],
            "sessionResumption": resumption,
        ]
        return [LiveJSON.string(["setup": setup])]
    }

    func audioMessage(_ pcm16: Data) -> String {
        LiveJSON.string(["realtimeInput": ["audio": [
            "data": pcm16.base64EncodedString(),
            "mimeType": "audio/pcm;rate=16000",
        ]]])
    }

    func textMessages(_ text: String, image: Data?) -> [String] {
        (image.map(imageMessages) ?? []) + [LiveJSON.string(["realtimeInput": ["text": text]])]
    }

    func imageMessages(_ jpeg: Data) -> [String] {
        [LiveJSON.string(["realtimeInput": ["video": [
            "data": jpeg.base64EncodedString(),
            "mimeType": "image/jpeg",
        ]]])]
    }

    func truncateMessage(itemID: String, audioEndMs: Int) -> String? {
        nil
    }

    /// New input interrupts a Gemini reply on its own.
    func cancelReplyMessages() -> [String] {
        []
    }

    func parse(_ message: String) -> [LiveEvent] {
        guard let json = LiveJSON.object(message) else { return [] }
        var events: [LiveEvent] = []
        if json["setupComplete"] != nil {
            events.append(.ready)
        }
        if let content = json["serverContent"] as? [String: Any] {
            let parts = (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            for part in parts {
                guard let inline = part["inlineData"] as? [String: Any],
                      (inline["mimeType"] as? String)?.hasPrefix("audio/") == true,
                      let base64 = inline["data"] as? String,
                      let audio = Data(base64Encoded: base64) else { continue }
                events.append(.audio(audio, itemID: nil))
            }
            if let text = (content["inputTranscription"] as? [String: Any])?["text"] as? String, !text.isEmpty {
                events.append(.userText(text, replacing: false))
            }
            if let text = (content["outputTranscription"] as? [String: Any])?["text"] as? String, !text.isEmpty {
                events.append(.assistantText(text))
            }
            if content["interrupted"] as? Bool == true {
                events.append(.interrupted)
            }
            if content["turnComplete"] as? Bool == true {
                events.append(.turnComplete)
            }
        }
        if let update = json["sessionResumptionUpdate"] as? [String: Any],
           update["resumable"] as? Bool != false,
           let handle = update["newHandle"] as? String, !handle.isEmpty {
            events.append(.resumptionHandle(handle))
        }
        if json["goAway"] != nil {
            events.append(.goAway)
        }
        if let error = json["error"] as? [String: Any] {
            events.append(.error(error["message"] as? String ?? "Gemini reported an error."))
        }
        return events
    }
}

// MARK: - OpenAI Realtime

/// OpenAI's Realtime API (GA event names) over a WebSocket.
nonisolated struct OpenAIRealtimeWire: LiveWire {
    let inputSampleRate = 24_000.0
    let outputSampleRate = 24_000.0
    let waitsForSetupAcknowledgement = false

    /// Transcribes what the user says so it can be saved to the chat.
    static let transcriptionModel = "whisper-1"

    func request(for config: LiveSessionConfig) -> URLRequest {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: config.model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func setupMessages(for config: LiveSessionConfig, resumptionHandle: String?) -> [String] {
        let session: [String: Any] = [
            "type": "realtime",
            "model": config.model,
            "instructions": config.instructions,
            "output_modalities": ["audio"],
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": 24_000],
                    "turn_detection": ["type": "semantic_vad", "create_response": true, "interrupt_response": true],
                ],
                "output": [
                    "format": ["type": "audio/pcm", "rate": 24_000],
                    "voice": config.voice,
                ],
            ],
        ]
        // Transcription goes in its own update, so a transcription problem can't
        // reject the voice and turn-taking settings with it.
        let transcription: [String: Any] = [
            "type": "realtime",
            "audio": ["input": ["transcription": ["model": Self.transcriptionModel]]],
        ]
        return [
            LiveJSON.string(["type": "session.update", "session": session]),
            LiveJSON.string(["type": "session.update", "session": transcription]),
        ]
    }

    func audioMessage(_ pcm16: Data) -> String {
        LiveJSON.string(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
    }

    func textMessages(_ text: String, image: Data?) -> [String] {
        var content: [[String: Any]] = [["type": "input_text", "text": text]]
        if let image {
            content.append(["type": "input_image", "image_url": "data:image/jpeg;base64,\(image.base64EncodedString())"])
        }
        return [
            LiveJSON.string(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": content]]),
            LiveJSON.string(["type": "response.create"]),
        ]
    }

    func imageMessages(_ jpeg: Data) -> [String] {
        let content: [[String: Any]] = [["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]
        return [LiveJSON.string(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": content]])]
    }

    func truncateMessage(itemID: String, audioEndMs: Int) -> String? {
        LiveJSON.string([
            "type": "conversation.item.truncate",
            "item_id": itemID,
            "content_index": 0,
            "audio_end_ms": max(0, audioEndMs),
        ])
    }

    func cancelReplyMessages() -> [String] {
        [LiveJSON.string(["type": "response.cancel"])]
    }

    func parse(_ message: String) -> [LiveEvent] {
        Self.parseRealtimeEvent(message)
    }

    /// Server events shared by OpenAI and xAI, which follows the same Realtime shape.
    /// Alternative names that either provider uses are accepted too.
    static func parseRealtimeEvent(_ message: String) -> [LiveEvent] {
        guard let json = LiveJSON.object(message), let type = json["type"] as? String else { return [] }
        switch type {
        case "response.output_audio.delta", "response.audio.delta":
            guard let base64 = json["delta"] as? String, let audio = Data(base64Encoded: base64) else { return [] }
            return [.audio(audio, itemID: json["item_id"] as? String)]
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta",
             "response.output_text.delta", "response.text.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return [] }
            return [.assistantText(delta)]
        case "conversation.item.input_audio_transcription.completed",
             "conversation.item.input_audio_transcription.updated":
            // Both carry the whole utterance (xAI's "updated" is cumulative).
            guard let transcript = json["transcript"] as? String, !transcript.isEmpty else { return [] }
            return [.userText(transcript, replacing: true)]
        case "input_audio_buffer.speech_started":
            return [.userSpeechStarted]
        case "response.done":
            return [.turnComplete]
        case "error":
            let error = json["error"] as? [String: Any]
            // Cancelling a reply that had already finished is harmless.
            if error?["code"] as? String == "response_cancel_not_active" { return [] }
            return [.error(error?["message"] as? String ?? "The provider reported an error.")]
        default:
            return []
        }
    }
}

// MARK: - xAI Grok Voice

/// xAI's Grok Voice Agent API, which follows the Realtime event shape.
nonisolated struct XAIVoiceWire: LiveWire {
    let inputSampleRate = 24_000.0
    let outputSampleRate = 24_000.0
    let waitsForSetupAcknowledgement = false

    func request(for config: LiveSessionConfig) -> URLRequest {
        var components = URLComponents(string: "wss://api.x.ai/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: config.model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func setupMessages(for config: LiveSessionConfig, resumptionHandle: String?) -> [String] {
        let session: [String: Any] = [
            "voice": config.voice,
            "instructions": config.instructions,
            "turn_detection": ["type": "server_vad"],
            "audio": [
                "input": ["format": ["type": "audio/pcm", "rate": 24_000]],
                "output": ["format": ["type": "audio/pcm", "rate": 24_000]],
            ],
        ]
        return [LiveJSON.string(["type": "session.update", "session": session])]
    }

    func audioMessage(_ pcm16: Data) -> String {
        LiveJSON.string(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
    }

    /// xAI's voice API documents no image input, so typed text goes alone.
    func textMessages(_ text: String, image: Data?) -> [String] {
        let content: [[String: Any]] = [["type": "input_text", "text": text]]
        return [
            LiveJSON.string(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": content]]),
            LiveJSON.string(["type": "response.create"]),
        ]
    }

    func imageMessages(_ jpeg: Data) -> [String] {
        []
    }

    func truncateMessage(itemID: String, audioEndMs: Int) -> String? {
        nil
    }

    func cancelReplyMessages() -> [String] {
        [LiveJSON.string(["type": "response.cancel"])]
    }

    func parse(_ message: String) -> [LiveEvent] {
        OpenAIRealtimeWire.parseRealtimeEvent(message)
    }
}

// MARK: - JSON helpers

nonisolated enum LiveJSON {
    static func string(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
