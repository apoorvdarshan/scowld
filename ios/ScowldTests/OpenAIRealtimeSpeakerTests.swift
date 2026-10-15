import Foundation
import XCTest
@testable import Scowld

/// OpenAI Realtime text-to-speech over a scripted fake socket; no network is used.
final class OpenAIRealtimeSpeakerTests: XCTestCase {
    /// Answers each `response.create` with the next scripted reply.
    private final class FakeSocket: RealtimeSocket, @unchecked Sendable {
        let request: URLRequest
        var sent: [[String: Any]] = []
        var replies: [[[String: Any]]]
        var failReceive: Error?
        private(set) var closed = false
        private var inbox: [String] = []
        private var waiting: CheckedContinuation<String, Error>?

        init(request: URLRequest, replies: [[[String: Any]]]) {
            self.request = request
            self.replies = replies
        }

        func send(_ text: String) async throws {
            let message = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            sent.append(message)
            guard message["type"] as? String == "response.create", !replies.isEmpty else { return }
            for event in replies.removeFirst() {
                inbox.append(String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self))
            }
        }

        func receive() async throws -> String {
            if let failReceive { throw failReceive }
            if closed { throw URLError(.cancelled) }
            if !inbox.isEmpty { return inbox.removeFirst() }
            // Nothing scripted: hang until closed, like a stalled connection.
            return try await withCheckedThrowingContinuation { waiting = $0 }
        }

        func close() {
            closed = true
            waiting?.resume(throwing: URLError(.cancelled))
            waiting = nil
        }
    }

    private var sockets: [FakeSocket] = []
    private var script: [[[[String: Any]]]] = [] // replies for each socket opened
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func speaker() -> OpenAIRealtimeSpeaker {
        OpenAIRealtimeSpeaker(
            makeSocket: { [unowned self] request in
                let socket = FakeSocket(request: request, replies: script.isEmpty ? [] : script.removeFirst())
                sockets.append(socket)
                return socket
            },
            now: { [unowned self] in clock }
        )
    }

    /// A completed spoken response carrying `pcm` and its transcript.
    private func reply(id: String = "resp_1", pcm: Data = Data([1, 0, 2, 0]), transcript: String, status: String = "completed") -> [[String: Any]] {
        [
            ["type": "response.created", "response": ["id": id, "status": "in_progress"]],
            ["type": "response.output_audio.delta", "response_id": id, "delta": pcm.base64EncodedString()],
            ["type": "response.output_audio_transcript.done", "response_id": id, "transcript": transcript],
            ["type": "response.done", "response": ["id": id, "status": status]],
        ]
    }

    func testSpeaksTheTextVerbatimAndReturnsWAV() async throws {
        script = [[reply(transcript: "Hello there!")]]
        let speech = try await speaker().speak(text: "Hello there!", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "sk-test")

        let socket = try XCTUnwrap(sockets.first)
        XCTAssertEqual(socket.request.url?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini")
        XCTAssertEqual(socket.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let session = try XCTUnwrap(socket.sent.first?["session"] as? [String: Any])
        XCTAssertEqual(socket.sent.first?["type"] as? String, "session.update")
        XCTAssertEqual(session["output_modalities"] as? [String], ["audio"])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        XCTAssertTrue((audio["input"] as? [String: Any])?["turn_detection"] is NSNull, "no microphone, no turn detection")
        let output = try XCTUnwrap(audio["output"] as? [String: Any])
        XCTAssertEqual(output["voice"] as? String, "marin")
        XCTAssertEqual((output["format"] as? [String: Any])?["rate"] as? Int, 24_000)

        let response = try XCTUnwrap(socket.sent.last?["response"] as? [String: Any])
        XCTAssertEqual(response["conversation"] as? String, "none", "out-of-band: no history kept")
        XCTAssertEqual((response["input"] as? [Any])?.count, 0)
        XCTAssertTrue((response["instructions"] as? String)?.hasSuffix("Say exactly the following:\nHello there!") == true)

        XCTAssertEqual(speech.transcript, "Hello there!")
        XCTAssertEqual(String(decoding: speech.wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: speech.wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(speech.wav.count, 44 + 4)
        XCTAssertEqual(speech.wav.suffix(4), Data([1, 0, 2, 0]))
        let sampleRate = speech.wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: sampleRate), 24_000)
    }

    func testOneSessionServesManyUtterancesAndIsRenewedForANewVoiceOrAfter55Minutes() async throws {
        script = [
            [reply(transcript: "One"), reply(id: "resp_2", transcript: "Two")],
            [reply(id: "resp_3", transcript: "Three")],
            [reply(id: "resp_4", transcript: "Four")],
        ]
        let speaker = speaker()
        _ = try await speaker.speak(text: "One", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k")
        _ = try await speaker.speak(text: "Two", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k")
        XCTAssertEqual(sockets.count, 1, "the warm session is reused")

        _ = try await speaker.speak(text: "Three", model: "gpt-realtime-2.1-mini", voice: "cedar", apiKey: "k")
        XCTAssertEqual(sockets.count, 2, "a voice can't change after a session's first audio")
        XCTAssertTrue(sockets[0].closed)

        clock += 56 * 60
        _ = try await speaker.speak(text: "Four", model: "gpt-realtime-2.1-mini", voice: "cedar", apiKey: "k")
        XCTAssertEqual(sockets.count, 3, "sessions end at 60 minutes, so they are renewed before that")
    }

    func testADriftedTakeIsRetriedOnceAndTheCloserOneWins() async throws {
        script = [[
            reply(transcript: "Sure! Here's a fun fact about otters."),
            reply(id: "resp_2", pcm: Data([9, 9]), transcript: "Otters hold hands while they sleep."),
        ]]
        let speech = try await speaker().speak(text: "Otters hold hands while they sleep.", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k")
        XCTAssertEqual(speech.transcript, "Otters hold hands while they sleep.")
        XCTAssertEqual(speech.wav.suffix(2), Data([9, 9]))
        XCTAssertEqual(sockets[0].sent.filter { $0["type"] as? String == "response.create" }.count, 2)
    }

    func testServerErrorsAndFailedResponsesSurfaceWithoutRetrying() async throws {
        script = [[[["type": "error", "error": ["message": "Invalid value: 'nova'"]]]]]
        do {
            _ = try await speaker().speak(text: "Hi", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k")
            XCTFail("an error event must throw")
        } catch {
            XCTAssertEqual(error as? RealtimeSpeechError, .server("Invalid value: 'nova'"))
        }
        XCTAssertEqual(sockets.count, 1)

        script = [[reply(transcript: "Hi", status: "failed")]]
        do {
            _ = try await speaker().speak(text: "Hi", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k")
            XCTFail("a failed response must throw")
        } catch {
            XCTAssertEqual(error as? RealtimeSpeechError, .response(status: "failed"))
        }
    }

    func testADroppedConnectionReconnectsOnce() async throws {
        script = [[], [reply(transcript: "Back again")]]
        let speaker = speaker()
        let pending = Task { try await speaker.speak(text: "Back again", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k") }
        while sockets.isEmpty { await Task.yield() }
        sockets[0].failReceive = URLError(.networkConnectionLost)
        sockets[0].close() // wake the pending receive
        let speech = try await pending.value
        XCTAssertEqual(speech.transcript, "Back again")
        XCTAssertEqual(sockets.count, 2)
    }

    func testAStalledResponseTimesOutAndFreesTheSpeaker() throws {
        script = [[]] // the response never arrives
        let result = speaker().speakSynchronously(text: "Hi", model: "gpt-realtime-2.1-mini", voice: "marin", apiKey: "k", timeout: 0.5)
        guard case .failure(let error) = result else { return XCTFail("expected a timeout") }
        XCTAssertEqual(error as? RealtimeSpeechError, .timedOut)
        XCTAssertTrue(sockets[0].closed)
    }

    func testVoicesAndModelsForRealtime() {
        XCTAssertEqual(TTSBackend.openAIRealtimeVoice(for: "coral"), "coral")
        XCTAssertEqual(TTSBackend.openAIRealtimeVoice(for: "nova"), "marin")
        XCTAssertEqual(TTSBackend.openAIRealtimeVoice(for: "onyx"), "cedar")
        XCTAssertFalse(TTSBackend.openAIVoices(for: "gpt-realtime-2.1-mini").contains("fable"))
        XCTAssertTrue(TTSBackend.openAIVoices(for: "gpt-4o-mini-tts").contains("fable"))
        XCTAssertTrue(TTSBackend.usesOpenAIRealtime(TTSBackend.openAI.defaultModel))
    }

    func testWordSimilarityIgnoresCaseAndPunctuation() {
        XCTAssertEqual(OpenAIRealtimeSpeaker.wordSimilarity("Hi, there!", "hi there"), 1)
        XCTAssertEqual(OpenAIRealtimeSpeaker.wordSimilarity("one two three four", "one two three"), 0.75)
        XCTAssertLessThan(OpenAIRealtimeSpeaker.wordSimilarity("I love otters", "Sure! Here is a poem about otters"), 0.5)
    }

    func testTheProxyReadsTheWebEnginesSpeechRequest() throws {
        let body = Data(#"{"model":"gpt-realtime-2.1","input":"  Hi there ","voice":"cedar"}"#.utf8)
        let request = try XCTUnwrap(AmicaLocalServer.openAISpeechRequest(from: body))
        XCTAssertEqual(request.model, "gpt-realtime-2.1")
        XCTAssertEqual(request.input, "Hi there")
        XCTAssertEqual(request.voice, "cedar")
        XCTAssertNil(AmicaLocalServer.openAISpeechRequest(from: Data(#"{"input":"   "}"#.utf8)))
    }
}
