import XCTest
@testable import Scowld

/// Provider keys live only in the Keychain.
@MainActor
final class KeychainManagerTests: XCTestCase {
    func testSaveLoadOverwriteAndDelete() {
        let key = "com.scowld.tests.\(UUID().uuidString)"
        addTeardownBlock { @MainActor in KeychainManager.delete(key: key) }

        XCTAssertNil(KeychainManager.load(key: key))
        XCTAssertFalse(KeychainManager.exists(key: key))

        XCTAssertTrue(KeychainManager.save(key: key, value: "first-secret"))
        XCTAssertEqual(KeychainManager.load(key: key), "first-secret")
        XCTAssertTrue(KeychainManager.exists(key: key))

        XCTAssertTrue(KeychainManager.save(key: key, value: "second-secret"))
        XCTAssertEqual(KeychainManager.load(key: key), "second-secret", "Saving replaces the previous value")

        XCTAssertTrue(KeychainManager.delete(key: key))
        XCTAssertNil(KeychainManager.load(key: key))
        XCTAssertTrue(KeychainManager.delete(key: key), "Deleting a missing key is not an error")
    }
}

/// The About tab's App Store update check.
@MainActor
final class AppUpdateCheckerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppUpdateChecker.isVersion("2.0.2", newerThan: "2.0.1"))
        XCTAssertTrue(AppUpdateChecker.isVersion("2.1", newerThan: "2.0.9"))
        XCTAssertTrue(AppUpdateChecker.isVersion("10.0", newerThan: "9.9.9"))
        XCTAssertTrue(AppUpdateChecker.isVersion("2.0.1", newerThan: "2.0"))
        XCTAssertFalse(AppUpdateChecker.isVersion("2.0.1", newerThan: "2.0.1"))
        XCTAssertFalse(AppUpdateChecker.isVersion("2.0", newerThan: "2.0.0"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.9", newerThan: "2.0"))
    }

    private func lookup(_ response: StubURLProtocol.Response, currentVersion: String) async throws -> AppUpdateState {
        StubURLProtocol.install { _ in response }
        addTeardownBlock { StubURLProtocol.uninstall() }
        let state = await AppUpdateChecker.check(currentVersion: currentVersion)
        let request = try XCTUnwrap(StubURLProtocol.requests.last?.request.url)
        XCTAssertEqual(request.absoluteString, "https://itunes.apple.com/lookup?bundleId=\(Bundle.main.bundleIdentifier ?? "")")
        return state
    }

    func testNewerStoreVersionOffersTheUpdate() async throws {
        let store = "https://apps.apple.com/app/id6760672848"
        let state = try await lookup(.json(["results": [["version": "9.9.9", "trackViewUrl": store]]]), currentVersion: "2.0.1")
        XCTAssertEqual(state, .updateAvailable(version: "9.9.9", appStoreURL: URL(string: store)!))
        XCTAssertTrue(state.isUpdateAvailable)
    }

    func testSameStoreVersionIsUpToDate() async throws {
        let state = try await lookup(.json(["results": [["version": "2.0.1", "trackViewUrl": "https://apps.apple.com/app/id1"]]]), currentVersion: "2.0.1")
        XCTAssertEqual(state, .upToDate)
        XCTAssertFalse(state.isUpdateAvailable)
    }

    func testAppMissingFromTheStoreAndBadResponses() async throws {
        let missing = try await lookup(.json(["resultCount": 0, "results": []]), currentVersion: "2.0.1")
        XCTAssertEqual(missing, .notOnAppStore)
        let broken = try await lookup(.text("<html>Service Unavailable</html>", status: 503), currentVersion: "2.0.1")
        XCTAssertEqual(broken, .failed)
    }
}

/// The ElevenLabs text-to-speech request built from the user's settings.
@MainActor
final class ElevenLabsRequestTests: XCTestCase {
    private func prepare(apiKey: String?) {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        let keychain = KeychainSnapshot(keys: [TTSBackend.elevenLabs.keychainKey])
        if let apiKey {
            _ = KeychainManager.save(key: TTSBackend.elevenLabs.keychainKey, value: apiKey)
        } else {
            KeychainManager.delete(key: TTSBackend.elevenLabs.keychainKey)
        }
        addTeardownBlock { @MainActor in
            keychain.restore()
            defaults.restore()
        }
    }

    func testMissingKeyIsReportedWithSettingsGuidance() {
        prepare(apiKey: nil)
        XCTAssertThrowsError(try ElevenLabsBYOKRequestBuilder.makeRequest(voiceID: "abc", body: nil)) { error in
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "ElevenLabs API key is missing. Add it in Settings > Text-to-Speech."
            )
        }
    }

    func testRequestUsesTheVoiceModelLanguageAndDefaultVoiceSettings() throws {
        prepare(apiKey: "  eleven-key \n")
        UserDefaults.standard.set("eleven_multilingual_v2", forKey: TTSBackend.elevenLabs.modelDefaultsKey)
        UserDefaults.standard.set("fr", forKey: HostedServiceConfig.serviceLanguageDefaultsKey)

        let request = try ElevenLabsBYOKRequestBuilder.makeRequest(
            voiceID: " HxuFAkkGVeQs1sDIMF5g ",
            body: Data(#"{"text":"Bonjour"}"#.utf8)
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/text-to-speech/HxuFAkkGVeQs1sDIMF5g?output_format=mp3_44100_128")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "eleven-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/mpeg")

        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["text"] as? String, "Bonjour")
        XCTAssertEqual(body["model_id"] as? String, "eleven_multilingual_v2")
        XCTAssertEqual(body["language_code"] as? String, "fr")
        let settings = try XCTUnwrap(body["voice_settings"] as? [String: Any])
        XCTAssertEqual(settings["stability"] as? Double, 0.55)
        XCTAssertEqual(settings["use_speaker_boost"] as? Bool, true)
    }

    func testElevenV4GetsOnlyTheVoiceSettingsItSupports() throws {
        prepare(apiKey: "eleven-key")
        UserDefaults.standard.set("eleven_v4", forKey: TTSBackend.elevenLabs.modelDefaultsKey)
        let request = try ElevenLabsBYOKRequestBuilder.makeRequest(voiceID: "v", body: Data(#"{"text":"Hi"}"#.utf8))
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model_id"] as? String, "eleven_v4")
        let settings = try XCTUnwrap(body["voice_settings"] as? [String: Any])
        XCTAssertEqual(Set(settings.keys), ["stability", "similarity_boost"])
    }

    func testBlankVoiceUsesTheSavedVoiceAndCustomVoiceSettingsAreKept() throws {
        prepare(apiKey: "eleven-key")
        UserDefaults.standard.set("savedVoice99", forKey: "amica_elevenlabs_voiceid")
        let request = try ElevenLabsBYOKRequestBuilder.makeRequest(
            voiceID: "  ",
            body: Data(#"{"text":"Hi","voice_settings":{"stability":0.1}}"#.utf8)
        )
        XCTAssertEqual(request.url?.path, "/v1/text-to-speech/savedVoice99")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((body["voice_settings"] as? [String: Any])?["stability"] as? Double, 0.1)
    }

    func testErrorBodyIsValidJSONEvenWithQuotesAndNewlines() throws {
        struct Failure: LocalizedError {
            var errorDescription: String? { "Bad \"voice\"\nid \\ here" }
        }
        let data = ElevenLabsBYOKRequestBuilder.errorResponseBody(Failure())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["error"], "Bad \"voice\" id \\ here")
    }
}

/// The loopback HTTP server that serves the bundled companion and proxies
/// text-to-speech. Only 127.0.0.1 is contacted.
@MainActor
final class AmicaLocalServerTests: XCTestCase {
    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> (HTTPURLResponse, Data) {
        let server = AmicaLocalServer.shared
        server.start()
        XCTAssertGreaterThan(server.port, 0)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)\(path)")))
        request.httpMethod = method
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (try XCTUnwrap(response as? HTTPURLResponse), data)
    }

    func testMimeTypes() {
        XCTAssertEqual(AmicaLocalServer.mimeType(for: "HTML"), "text/html; charset=utf-8")
        XCTAssertEqual(AmicaLocalServer.mimeType(for: "js"), "application/javascript")
        XCTAssertEqual(AmicaLocalServer.mimeType(for: "vrm"), "model/gltf-binary")
        XCTAssertEqual(AmicaLocalServer.mimeType(for: "wasm"), "application/wasm")
        XCTAssertEqual(AmicaLocalServer.mimeType(for: "mp3"), "audio/mpeg")
        XCTAssertEqual(AmicaLocalServer.mimeType(for: "xyz"), "application/octet-stream")
    }

    func testServesTheBundledCompanionPage() async throws {
        let (response, data) = try await send("GET", "/")
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8")
        XCTAssertEqual(response.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("<html"))

        let (avatar, avatarData) = try await send("GET", "/vrm/AvatarSample_A.vrm?cache=1")
        XCTAssertEqual(avatar.statusCode, 200)
        XCTAssertEqual(avatar.value(forHTTPHeaderField: "Content-Type"), "model/gltf-binary")
        XCTAssertGreaterThan(avatarData.count, 1_000_000)
    }

    func testMissingFilesAndPreflightRequests() async throws {
        let (missing, _) = try await send("GET", "/does-not-exist.js")
        XCTAssertEqual(missing.statusCode, 404)

        let (preflight, _) = try await send("OPTIONS", "/index.html")
        XCTAssertEqual(preflight.statusCode, 204)
        XCTAssertEqual(preflight.value(forHTTPHeaderField: "Access-Control-Allow-Methods"), "GET, POST, OPTIONS")
    }

    func testSpeechProxyRefusesWithoutAKeyAndRejectsUnknownPaths() async throws {
        let keychain = KeychainSnapshot(keys: [TTSBackend.elevenLabs.keychainKey, AIProvider.openai.keychainKey])
        KeychainManager.delete(key: TTSBackend.elevenLabs.keychainKey)
        KeychainManager.delete(key: AIProvider.openai.keychainKey)
        addTeardownBlock { @MainActor in keychain.restore() }

        let (unknown, _) = try await send("GET", "/api/elevenlabs/voices")
        XCTAssertEqual(unknown.statusCode, 404)

        let (elevenLabs, elevenLabsBody) = try await send("POST", "/api/elevenlabs/text-to-speech/abc", body: Data(#"{"text":"Hi"}"#.utf8))
        XCTAssertEqual(elevenLabs.statusCode, 401)
        XCTAssertTrue(String(decoding: elevenLabsBody, as: UTF8.self).contains("ElevenLabs API key is missing"))

        let (openAI, openAIBody) = try await send("POST", "/api/openai-tts/v1/audio/speech", body: Data(#"{"input":"Hi"}"#.utf8))
        XCTAssertEqual(openAI.statusCode, 401)
        XCTAssertEqual(String(decoding: openAIBody, as: UTF8.self), #"{"error":"No OpenAI API key"}"#)
    }
}
