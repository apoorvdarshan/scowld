import Foundation

// The live session runs on background threads (the microphone tap and the socket's
// receive loop), so these types opt out of the app target's default main-actor
// isolation.

/// The WebSocket a live session talks through; tests substitute a fake.
nonisolated protocol LiveSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

nonisolated enum LiveSocketError: LocalizedError, Equatable {
    case refused(statusCode: Int)
    case closed(String)
    case unexpectedMessage

    var errorDescription: String? {
        switch self {
        case .refused(let statusCode):
            statusCode == 401 || statusCode == 403
                ? "The provider rejected the API key (HTTP \(statusCode)). Check it in Settings."
                : "The provider refused the connection (HTTP \(statusCode))."
        case .closed(let reason):
            reason
        case .unexpectedMessage:
            "The provider sent a message Scowld can't read."
        }
    }
}

nonisolated final class URLSessionLiveSocket: LiveSocket, @unchecked Sendable {
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
            @unknown default: throw LiveSocketError.unexpectedMessage
            }
        } catch {
            // A refused handshake (bad key, no access to the model) is reported as such.
            if let http = task.response as? HTTPURLResponse, http.statusCode >= 400 {
                throw LiveSocketError.refused(statusCode: http.statusCode)
            }
            // Gemini closes the socket with a reason, such as an invalid key or model.
            if task.closeCode != .invalid, task.closeCode != .normalClosure,
               let reason = task.closeReason.flatMap({ String(data: $0, encoding: .utf8) }),
               !reason.isEmpty {
                throw LiveSocketError.closed(reason)
            }
            throw error
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
