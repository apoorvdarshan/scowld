import XCTest

/// The bundled companion page (amica.bundle) is prebuilt third-party code. Its
/// upstream build initialized Sentry with the upstream project's DSN, which sent
/// error reports, performance traces and session replays from the app's web view
/// to a service Scowld does not use or disclose. These checks keep any Sentry
/// ingest endpoint out of the shipped bundle, including after a bundle update.
final class CompanionBundlePrivacyTests: XCTestCase {
    private func bundledScripts() throws -> [URL] {
        let bundle = try XCTUnwrap(
            Bundle.main.url(forResource: "amica", withExtension: "bundle"),
            "amica.bundle is missing from the app"
        )
        let files = try XCTUnwrap(FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil))
        return files.compactMap { $0 as? URL }.filter { ["js", "html"].contains($0.pathExtension) }
    }

    func testTheBundleContainsNoSentryIngestEndpoint() throws {
        let scripts = try bundledScripts()
        // Guards against passing vacuously if the bundle moves or is not copied.
        XCTAssertGreaterThan(scripts.count, 100)

        let ingest = try NSRegularExpression(pattern: #"ingest(\.[a-z]+)?\.sentry\.io|sentry\.io/api/"#)
        for script in scripts {
            let text = try String(contentsOf: script, encoding: .utf8)
            let match = ingest.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertNil(match, "\(script.lastPathComponent) contains a Sentry ingest endpoint")
        }
    }

    func testSentryIsDisabledWhereThePageInitializesIt() throws {
        let app = try XCTUnwrap(try bundledScripts().first { $0.lastPathComponent.hasPrefix("_app-") })
        let text = try String(contentsOf: app, encoding: .utf8)
        XCTAssertTrue(text.contains(#"dsn:"",integrations:[],tracesSampleRate:0,replaysSessionSampleRate:0,replaysOnErrorSampleRate:0,debug:!1,enabled:!1}"#))
    }
}
