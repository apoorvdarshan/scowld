import Foundation
import XCTest
@testable import Scowld

/// Restores the host app's preferences after a test changes them.
struct DefaultsSnapshot {
    private let domainName: String
    private let saved: [String: Any]?

    init() {
        domainName = Bundle.main.bundleIdentifier ?? "com.apoorvdarshan.Scowld"
        saved = UserDefaults.standard.persistentDomain(forName: domainName)
    }

    /// Starts the test from empty preferences.
    func clear() {
        UserDefaults.standard.removePersistentDomain(forName: domainName)
    }

    func restore() {
        if let saved {
            UserDefaults.standard.setPersistentDomain(saved, forName: domainName)
        } else {
            UserDefaults.standard.removePersistentDomain(forName: domainName)
        }
    }
}

/// Restores Keychain items a test overwrites, so a developer's simulator keys survive.
@MainActor
struct KeychainSnapshot {
    private let saved: [String: String?]

    init(keys: [String]) {
        var saved: [String: String?] = [:]
        for key in keys {
            saved[key] = KeychainManager.load(key: key)
        }
        self.saved = saved
    }

    func restore() {
        for (key, value) in saved {
            if let value {
                _ = KeychainManager.save(key: key, value: value)
            } else {
                KeychainManager.delete(key: key)
            }
        }
    }
}

/// Answers every URLSession request in-process. Any request without a stubbed
/// answer fails, so these tests can never reach the network.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data()

        static func json(_ object: Any, status: Int = 200) -> Response {
            Response(status: status, body: try! JSONSerialization.data(withJSONObject: object))
        }

        static func text(_ text: String, status: Int) -> Response {
            Response(status: status, headers: ["Content-Type": "text/plain"], body: Data(text.utf8))
        }
    }

    struct Recorded {
        let request: URLRequest
        let body: Data

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responder: ((URLRequest) -> Response)?
    nonisolated(unsafe) private static var recorded: [Recorded] = []
    nonisolated(unsafe) private static var isRegistered = false

    /// Answers requests with `responder` (replacing any previous one).
    static func install(_ responder: @escaping (URLRequest) -> Response) {
        let needsRegistration = lock.withLock { () -> Bool in
            self.responder = responder
            recorded = []
            defer { isRegistered = true }
            return !isRegistered
        }
        if needsRegistration {
            URLProtocol.registerClass(StubURLProtocol.self)
        }
    }

    static func uninstall() {
        let wasRegistered = lock.withLock { () -> Bool in
            responder = nil
            recorded = []
            defer { isRegistered = false }
            return isRegistered
        }
        if wasRegistered {
            URLProtocol.unregisterClass(StubURLProtocol.self)
        }
    }

    static var requests: [Recorded] {
        lock.withLock { recorded }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(of: request)
        let responder = Self.lock.withLock { () -> ((URLRequest) -> Response)? in
            Self.recorded.append(Recorded(request: request, body: body))
            return Self.responder
        }
        guard let responder, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let stub = responder(request)
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
