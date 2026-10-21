import WebKit
import XCTest
@testable import Scowld

/// A navigation as the web view hands it to the coordinator.
private final class Navigation: WKNavigationAction {
    private let target: URLRequest

    init(_ url: String) {
        target = URLRequest(url: URL(string: url)!)
        super.init()
    }

    override var request: URLRequest { target }
}

/// Scowld declares that it uses no non-exempt encryption
/// (ITSAppUsesNonExemptEncryption = NO): only HTTPS, the Keychain and Apple's
/// system crypto. The prebuilt companion page (amica.bundle) used to carry a
/// JavaScript encryption library (Node's `crypto` polyfill: AES, DES,
/// Diffie-Hellman, ECDH, RSA, PBKDF2) for its `/share` page, which only hashed
/// files before publishing them to Amica's online store. That code was removed
/// and the page is blocked. These checks keep it that way, including after a
/// bundle update. See store/README.md, "Export compliance".
@MainActor
final class CompanionExportComplianceTests: XCTestCase {
    private static let origin = "http://127.0.0.1:8080"

    private func bundledScripts() throws -> [URL] {
        let bundle = try XCTUnwrap(
            Bundle.main.url(forResource: "amica", withExtension: "bundle"),
            "amica.bundle is missing from the app"
        )
        let files = try XCTUnwrap(FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil))
        return files.compactMap { $0 as? URL }.filter { ["js", "html", "json"].contains($0.pathExtension) }
    }

    func testTheAppDeclaresNoNonExemptEncryption() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
    }

    func testTheBundleShipsNoEncryptionLibrary() throws {
        let scripts = try bundledScripts()
        // Guards against passing vacuously if the bundle moves or is not copied.
        XCTAssertGreaterThan(scripts.count, 100)

        let cipherCode = try NSRegularExpression(pattern: [
            #"createCipher"#, #"createDecipher"#, #"getCiphers"#, #"aes-(128|192|256)-"#, #"des-ede"#,
            #"DiffieHellman"#, #"createECDH"#, #"secp256k1"#, #"publicEncrypt"#, #"privateDecrypt"#,
            #"pbkdf2"#, #"EVP_BytesToKey"#, #"MillerRabin"#,
            #"subtle\.(encrypt|decrypt|wrapKey|unwrapKey|deriveKey|deriveBits)"#,
        ].joined(separator: "|"))
        for script in scripts {
            let text = try String(contentsOf: script, encoding: .utf8)
            let match = cipherCode.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertNil(match, "\(script.lastPathComponent) contains encryption code")
        }
    }

    // The coordinator decides without a web view. Creating a WKWebView here would
    // launch WebKit's GPU, networking and web content processes inside the test
    // host; on CI they took up to 30 seconds to start and stalled the main thread
    // under the tests that ran next.

    func testTheRemovedSharePageIsNeverOpened() {
        let coordinator = AmicaFullView.Coordinator(memoryStore: MemoryStore(inMemory: true))
        for path in ["/share", "/share/", "/share/?from=menu", "/share/avatar", "/%73hare/"] {
            XCTAssertEqual(coordinator.policy(for: Navigation(Self.origin + path)), .cancel, path)
        }
        // WebKit asks the coordinator for every navigation; it answers with that policy.
        let decidePolicy = NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")
        XCTAssertTrue(coordinator.responds(to: decidePolicy))
    }

    func testEveryOtherCompanionPageStillOpens() {
        let coordinator = AmicaFullView.Coordinator(memoryStore: MemoryStore(inMemory: true))
        for path in ["/", "/index.html", "/import/", "/import/abc123/", "/shared/", "/sharepoint",
                     "/_next/static/chunks/pages/share-cb4d38ba21de5e45.js"] {
            XCTAssertEqual(coordinator.policy(for: Navigation(Self.origin + path)), .allow, path)
        }
        XCTAssertFalse(AmicaFullView.Coordinator.isRemovedCompanionPage(nil))
        XCTAssertFalse(AmicaFullView.Coordinator.isRemovedCompanionPage(URL(string: "about:blank")))
    }
}
