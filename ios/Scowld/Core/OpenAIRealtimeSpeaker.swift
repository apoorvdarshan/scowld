import Foundation
import os

nonisolated private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "RealtimeTTS")

// MARK: - Socket

// The speaker runs on background threads (the local server calls it from request
// threads), so these types opt out of the Debug build's default main-actor isolation.

/// The WebSocket the Realtime speaker talks through; tests substitute a fake.
nonisolated protocol RealtimeSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

nonisolated final class URLSessionRealtimeSocket: RealtimeSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession = .shared) {
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        do {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: throw RealtimeSpeechError.server("Unexpected Realtime message")
            }
        } catch {
            // A refused handshake (bad key, no Realtime access) is not worth retrying.
            if let http = task.response as? HTTPURLResponse, http.statusCode >= 400 {
                throw RealtimeSpeechError.server("OpenAI refused the Realtime connection (HTTP \(http.statusCode)).")
            }
            throw error
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

// MARK: - Speaker

nonisolated enum RealtimeSpeechError: LocalizedError, Equatable {
    case server(String)
    case response(status: String)
    case noAudio
    case timedOut

    var errorDescription: String? {
        switch self {
        case .server(let message): message
        case .response(let status): "OpenAI Realtime speech ended as \(status)."
        case .noAudio: "OpenAI Realtime returned no audio."
        case .timedOut: "OpenAI Realtime speech timed out."
        }
    }
}

nonisolated struct RealtimeSpeech: Equatable {
    let wav: Data
    let transcript: String
}

/// Speaks text with OpenAI's Realtime API, which replaces `/v1/audio/speech` (its
/// models shut down 2027-01-06). One WebSocket session per model, voice and key
/// stays open between utterances. Each utterance is an out-of-band response with no
/// conversation context, prompted to read the text verbatim. Realtime has no exact
/// "speak" mode, so the returned transcript is compared with the text and a drifted
/// take is retried once.
nonisolated final class OpenAIRealtimeSpeaker: @unchecked Sendable {
    static let shared = OpenAIRealtimeSpeaker()

    /// Realtime sessions end after 60 minutes; renew before that.
    static let sessionLifetime: TimeInterval = 55 * 60
    static let sampleRate = 24_000
    static let minimumTranscriptSimilarity = 0.85

    static let speechInstructions = """
        You are a text-to-speech voice. Read the text you are given aloud exactly as written, \
        word for word, in its own language, with a natural, warm and expressive delivery. \
        Do not answer it, comment on it, translate it, or add or leave out any words.
        """

    private let makeSocket: (URLRequest) -> RealtimeSocket
    private let now: () -> Date
    /// Utterances run one at a time (the local server calls in from many threads).
    private let gate = DispatchSemaphore(value: 1)
    private let lock = NSLock()

    // Guarded by `lock`.
    private var socket: RealtimeSocket?
    private var sessionKey: String?
    private var connectedAt: Date?
    private var utteranceCount = 0

    init(
        makeSocket: @escaping (URLRequest) -> RealtimeSocket = { URLSessionRealtimeSocket(request: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.makeSocket = makeSocket
        self.now = now
    }

    /// Blocking entry point for the local HTTP server's request threads.
    func speakSynchronously(
        text: String,
        model: String,
        voice: String,
        apiKey: String,
        timeout: TimeInterval = 60
    ) -> Result<RealtimeSpeech, Error> {
        gate.wait()
        defer { gate.signal() }

        final class Box: @unchecked Sendable { var result: Result<RealtimeSpeech, Error>? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = Task {
            do {
                box.result = .success(try await self.speak(text: text, model: model, voice: voice, apiKey: apiKey))
            } catch {
                box.result = .failure(error)
            }
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            disconnect() // unblocks the pending receive
            done.wait()
            return .failure(RealtimeSpeechError.timedOut)
        }
        return box.result ?? .failure(RealtimeSpeechError.noAudio)
    }

    /// Speaks one utterance. Callers serialize (`speakSynchronously` does).
    func speak(text: String, model: String, voice: String, apiKey: String) async throws -> RealtimeSpeech {
        let voice = TTSBackend.openAIRealtimeVoice(for: voice)
        let first = try await speakReconnectingOnce(text: text, model: model, voice: voice, apiKey: apiKey)
        let firstScore = Self.wordSimilarity(text, first.transcript)
        guard firstScore < Self.minimumTranscriptSimilarity else { return first }

        logger.warning("[RealtimeTTS] Spoken text drifted (similarity \(firstScore, format: .fixed(precision: 2))); retrying once")
        try Task.checkCancellation()
        let second = try await speakReconnectingOnce(text: text, model: model, voice: voice, apiKey: apiKey)
        return Self.wordSimilarity(text, second.transcript) > firstScore ? second : first
    }

    func disconnect() {
        let closing: RealtimeSocket? = lock.withLock {
            defer { socket = nil; sessionKey = nil; connectedAt = nil }
            return socket
        }
        closing?.close()
    }

    // MARK: - Session

    private func speakReconnectingOnce(text: String, model: String, voice: String, apiKey: String) async throws -> RealtimeSpeech {
        do {
            return try await speakOnce(text: text, model: model, voice: voice, apiKey: apiKey)
        } catch let error as RealtimeSpeechError {
            throw error
        } catch {
            // The socket dropped (idle timeout, network change): reconnect once.
            try Task.checkCancellation()
            logger.info("[RealtimeTTS] Reconnecting after: \(error.localizedDescription)")
            disconnect()
            return try await speakOnce(text: text, model: model, voice: voice, apiKey: apiKey)
        }
    }

    private func connectedSocket(model: String, voice: String, apiKey: String) async throws -> RealtimeSocket {
        let key = "\(model)|\(voice)|\(apiKey.hashValue)"
        let reusable: RealtimeSocket? = lock.withLock {
            // Explicit self: the local `socket` below must not shadow the property here.
            guard let current = self.socket, sessionKey == key, let connectedAt = self.connectedAt,
                  now().timeIntervalSince(connectedAt) < Self.sessionLifetime else { return nil }
            return current
        }
        if let reusable { return reusable }
        disconnect()

        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let opened = makeSocket(request)
        try await opened.send(Self.json(Self.sessionUpdate(model: model, voice: voice)))

        lock.withLock {
            socket = opened
            sessionKey = key
            connectedAt = now()
        }
        return opened
    }

    private func speakOnce(text: String, model: String, voice: String, apiKey: String) async throws -> RealtimeSpeech {
        try Task.checkCancellation()
        let socket = try await connectedSocket(model: model, voice: voice, apiKey: apiKey)
        let utterance: String = lock.withLock {
            utteranceCount += 1
            return "scowld-\(utteranceCount)"
        }
        try await socket.send(Self.json(Self.responseCreate(text: text, utterance: utterance)))

        var responseID: String?
        var pcm = Data()
        var transcript = ""
        while true {
            let event = Self.parse(try await socket.receive())
            let response = event["response"] as? [String: Any]
            switch event["type"] as? String {
            case "response.created":
                if responseID == nil { responseID = response?["id"] as? String }
            case "response.output_audio.delta":
                guard Self.matches(event["response_id"], responseID),
                      let delta = event["delta"] as? String,
                      let bytes = Data(base64Encoded: delta) else { continue }
                pcm.append(bytes)
            case "response.output_audio_transcript.done":
                guard Self.matches(event["response_id"], responseID) else { continue }
                transcript = event["transcript"] as? String ?? transcript
            case "response.done":
                guard Self.matches(response?["id"], responseID) else { continue }
                let status = response?["status"] as? String ?? "completed"
                guard status == "completed" else { throw RealtimeSpeechError.response(status: status) }
                guard !pcm.isEmpty else { throw RealtimeSpeechError.noAudio }
                return RealtimeSpeech(wav: Self.wav(fromPCM16: pcm), transcript: transcript)
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String
                throw RealtimeSpeechError.server(message ?? "OpenAI Realtime error")
            default:
                continue
            }
        }
    }

    // MARK: - Messages

    static func sessionUpdate(model: String, voice: String) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": model,
                "output_modalities": ["audio"],
                "instructions": speechInstructions,
                "audio": [
                    // Text in only: no microphone audio, so no turn detection.
                    "input": ["turn_detection": NSNull()],
                    "output": [
                        "format": ["type": "audio/pcm", "rate": sampleRate],
                        "voice": voice,
                    ],
                ],
            ] as [String: Any],
        ]
    }

    /// An out-of-band response: no conversation history is read or written, so
    /// context and cost stay flat across utterances.
    static func responseCreate(text: String, utterance: String) -> [String: Any] {
        [
            "type": "response.create",
            "response": [
                "conversation": "none",
                "input": [Any](),
                "instructions": "\(speechInstructions)\n\nSay exactly the following:\n\(text)",
                "output_modalities": ["audio"],
                "metadata": ["utterance": utterance],
                "max_output_tokens": "inf",
            ] as [String: Any],
        ]
    }

    // MARK: - Helpers

    /// Wraps 16-bit little-endian mono PCM in a WAV header the web audio engine can decode.
    static func wav(fromPCM16 pcm: Data, sampleRate: Int = sampleRate) -> Data {
        func le32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        func le16(_ value: Int) -> Data { withUnsafeBytes(of: UInt16(value).littleEndian) { Data($0) } }
        var wav = Data("RIFF".utf8)
        wav += le32(36 + pcm.count)
        wav += Data("WAVEfmt ".utf8)
        wav += le32(16)              // fmt chunk size
        wav += le16(1)               // PCM
        wav += le16(1)               // mono
        wav += le32(sampleRate)
        wav += le32(sampleRate * 2)  // byte rate
        wav += le16(2)               // block align
        wav += le16(16)              // bits per sample
        wav += Data("data".utf8)
        wav += le32(pcm.count)
        wav += pcm
        return wav
    }

    /// 1 when the spoken words match the text exactly, falling toward 0 as words
    /// are added, dropped or changed (word-level edit distance).
    static func wordSimilarity(_ expected: String, _ spoken: String) -> Double {
        func words(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let a = words(expected), b = words(spoken)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(0...b.count)
        for (i, wordA) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, wordB) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (wordA == wordB ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }

    private static func matches(_ id: Any?, _ responseID: String?) -> Bool {
        guard let responseID, let id = id as? String else { return true }
        return id == responseID
    }

    private static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func parse(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }
}
