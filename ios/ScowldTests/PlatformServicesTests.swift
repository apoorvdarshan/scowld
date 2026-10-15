import AVFoundation
import XCTest
@testable import Scowld

/// The playback audio session used by the companion page and voice previews.
@MainActor
final class AudioSessionTests: XCTestCase {
    func testPlaybackSessionIsAccepted() throws {
        // `.allowBluetoothA2DP` is only valid with `.playAndRecord`; with
        // `.playback` iOS rejected the category (OSStatus -50) and every voice
        // preview failed before it reached the provider.
        XCTAssertNoThrow(try ScowldAudioSession.activatePlayback())
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback)
        XCTAssertFalse(session.categoryOptions.contains(.allowBluetoothA2DP))
    }
}

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

/// The loopback HTTP server that serves the bundled companion page. Only
/// 127.0.0.1 is contacted.
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

    /// The old text-to-speech proxies are gone: those paths are just missing files.
    func testNoSpeechProxyRemains() async throws {
        for path in ["/api/elevenlabs/text-to-speech/abc", "/api/openai-tts/v1/audio/speech"] {
            let (response, _) = try await send("POST", path, body: Data(#"{"text":"Hi"}"#.utf8))
            XCTAssertEqual(response.statusCode, 404, path)
        }
    }
}
