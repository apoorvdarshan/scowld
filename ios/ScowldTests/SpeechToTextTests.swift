import AVFoundation
import XCTest
@testable import Scowld

/// WAV encoding of recorded audio (no microphone involved).
@MainActor
final class WAVEncodingTests: XCTestCase {
    private func buffer(sampleRate: Double, channels: [[Float]]) throws -> (AVAudioPCMBuffer, AVAudioFormat) {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels.count),
            interleaved: false
        ))
        let frames = AVAudioFrameCount(channels[0].count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)
        for (channel, samples) in channels.enumerated() {
            for (index, sample) in samples.enumerated() {
                data[channel][index] = sample
            }
        }
        return (buffer, format)
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset + 4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        data.subdata(in: offset..<offset + 2).withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) }
    }

    private func samples(_ data: Data) -> [Int16] {
        stride(from: 44, to: data.count, by: 2).map { offset in
            data.subdata(in: offset..<offset + 2).withUnsafeBytes { Int16(littleEndian: $0.loadUnaligned(as: Int16.self)) }
        }
    }

    func testRecordingIsResampledTo16kHzMono16BitPCM() throws {
        let (pcm, format) = try buffer(sampleRate: 48_000, channels: [Array(repeating: 0.5, count: 4_800)])
        let wav = CloudSTTManager.createWAV(from: [pcm], format: format)

        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav.subdata(in: 12..<16), encoding: .ascii), "fmt ")
        XCTAssertEqual(uint32(wav, at: 16), 16)
        XCTAssertEqual(uint16(wav, at: 20), 1, "PCM")
        XCTAssertEqual(uint16(wav, at: 22), 1, "mono")
        XCTAssertEqual(uint32(wav, at: 24), 16_000)
        XCTAssertEqual(uint32(wav, at: 28), 32_000, "byte rate")
        XCTAssertEqual(uint16(wav, at: 32), 2, "block align")
        XCTAssertEqual(uint16(wav, at: 34), 16, "bits per sample")
        XCTAssertEqual(String(data: wav.subdata(in: 36..<40), encoding: .ascii), "data")

        let dataSize = uint32(wav, at: 40)
        XCTAssertEqual(dataSize, 3_200, "0.1 s at 16 kHz is 1,600 samples")
        XCTAssertEqual(uint32(wav, at: 4), 36 + dataSize)
        XCTAssertEqual(wav.count, 44 + Int(dataSize))
        XCTAssertEqual(Set(samples(wav)), [16_383])
    }

    func testStereoIsMixedDownAndSamplesAreClamped() throws {
        let (pcm, format) = try buffer(sampleRate: 16_000, channels: [[1, 2, -2, 0.25], [0, 2, -2, 0.25]])
        let wav = CloudSTTManager.createWAV(from: [pcm], format: format)
        XCTAssertEqual(samples(wav), [16_383, 32_767, -32_767, 8_191])
    }

    func testMultipleBuffersAreConcatenatedAndNoAudioMeansNoFile() throws {
        let (first, format) = try buffer(sampleRate: 16_000, channels: [[0.1, 0.1]])
        let (second, _) = try buffer(sampleRate: 16_000, channels: [[0.2, 0.2, 0.2]])
        XCTAssertEqual(samples(CloudSTTManager.createWAV(from: [first, second], format: format)).count, 5)
        XCTAssertTrue(CloudSTTManager.createWAV(from: [], format: format).isEmpty)
    }
}

/// Cloud speech-to-text requests and response parsing, answered in-process.
@MainActor
final class CloudTranscriptionTests: XCTestCase {
    private let audio = Data("RIFF-test-audio".utf8)

    private func prepare(_ backend: STTBackend, key: String? = "stt-key") {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        let keychain = KeychainSnapshot(keys: [backend.keychainKey])
        if let key {
            XCTAssertTrue(KeychainManager.save(key: backend.keychainKey, value: key))
        } else {
            KeychainManager.delete(key: backend.keychainKey)
        }
        addTeardownBlock { @MainActor in
            StubURLProtocol.uninstall()
            keychain.restore()
            defaults.restore()
        }
    }

    func testOpenAIWhisperUploadsMultipartAudioWithTheSelectedModel() async throws {
        prepare(.openaiWhisper)
        UserDefaults.standard.set("whisper-1", forKey: STTBackend.openaiWhisper.modelDefaultsKey)
        StubURLProtocol.install { _ in .json(["text": "hello world"]) }

        let text = try await CloudSTTManager.transcribe(audioData: audio, backend: .openaiWhisper)
        XCTAssertEqual(text, "hello world")

        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer stt-key")
        XCTAssertTrue(sent.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: sent.body, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
        XCTAssertTrue(body.contains("RIFF-test-audio"))
    }

    func testGroqUsesItsOwnEndpoint() async throws {
        prepare(.groqWhisper)
        StubURLProtocol.install { _ in .json(["text": "fast"]) }
        let text = try await CloudSTTManager.transcribe(audioData: audio, backend: .groqWhisper)
        XCTAssertEqual(text, "fast")
        XCTAssertEqual(StubURLProtocol.requests.last?.request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
    }

    func testDeepgramSendsTheSelectedLanguage() async throws {
        prepare(.deepgram)
        UserDefaults.standard.set("de", forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        StubURLProtocol.install { _ in
            .json(["results": ["channels": [["alternatives": [["transcript": "hallo welt"]]]]]])
        }

        let text = try await CloudSTTManager.transcribe(audioData: audio, backend: .deepgram)
        XCTAssertEqual(text, "hallo welt")

        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        let url = try XCTUnwrap(sent.request.url)
        XCTAssertEqual(url.host, "api.deepgram.com")
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["model"], "nova-3")
        XCTAssertEqual(query["language"], "de")
        XCTAssertNil(query["detect_language"])
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Token stt-key")
        XCTAssertEqual(sent.body, audio)
    }

    func testGoogleCloudReturnsEmptyTextWhenNoSpeechWasDetected() async throws {
        prepare(.googleCloud)
        StubURLProtocol.install { _ in .json([:]) }
        let text = try await CloudSTTManager.transcribe(audioData: audio, backend: .googleCloud)
        XCTAssertEqual(text, "")

        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.request.url?.absoluteString, "https://speech.googleapis.com/v1/speech:recognize?key=stt-key")
        let config = try XCTUnwrap(sent.json["config"] as? [String: Any])
        XCTAssertEqual(config["encoding"] as? String, "LINEAR16")
        XCTAssertEqual(config["sampleRateHertz"] as? Int, 16_000)
        XCTAssertEqual(config["model"] as? String, STTBackend.googleCloud.defaultModel)
        XCTAssertEqual((sent.json["audio"] as? [String: String])?["content"], audio.base64EncodedString())
    }

    func testAssemblyAIUploadsCreatesAndPollsATranscript() async throws {
        prepare(.assemblyAI)
        StubURLProtocol.install { request in
            switch request.url?.path {
            case "/v2/upload": .json(["upload_url": "https://cdn.assemblyai.com/upload/abc"])
            case "/v2/transcript": .json(["id": "t-1"])
            case "/v2/transcript/t-1": .json(["status": "completed", "text": "assembled text"])
            default: .text("unexpected", status: 404)
            }
        }
        let text = try await CloudSTTManager.transcribe(audioData: audio, backend: .assemblyAI)
        XCTAssertEqual(text, "assembled text")

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map { $0.request.url?.path ?? "" }, ["/v2/upload", "/v2/transcript", "/v2/transcript/t-1"])
        XCTAssertEqual(requests[1].json["audio_url"] as? String, "https://cdn.assemblyai.com/upload/abc")
        XCTAssertEqual(requests[1].json["speech_models"] as? [String], [STTBackend.assemblyAI.defaultModel])
        XCTAssertTrue(requests.allSatisfy { $0.request.value(forHTTPHeaderField: "Authorization") == "stt-key" })
    }

    func testProviderErrorMessagesAreSurfaced() async throws {
        prepare(.openaiWhisper)
        StubURLProtocol.install { _ in .json(["error": ["message": "Incorrect API key provided"]], status: 401) }
        do {
            _ = try await CloudSTTManager.transcribe(audioData: audio, backend: .openaiWhisper)
            XCTFail("expected an API error")
        } catch let error as CloudSTTError {
            XCTAssertEqual(error.errorDescription, "STT API error: Incorrect API key provided")
        }
    }

    func testMissingKeyFailsBeforeAnyRequest() async throws {
        prepare(.deepgram, key: nil)
        StubURLProtocol.install { _ in .json([:]) }
        do {
            _ = try await CloudSTTManager.transcribe(audioData: audio, backend: .deepgram)
            XCTFail("expected a missing key error")
        } catch CloudSTTError.noAPIKey {}
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
