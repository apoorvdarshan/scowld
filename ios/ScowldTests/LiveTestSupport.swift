import Foundation
import XCTest
@testable import Scowld

/// A WebSocket the tests script: it records what Scowld sends and delivers
/// provider messages on demand. Nothing reaches the network.
final class FakeLiveSocket: LiveSocket, @unchecked Sendable {
    let request: URLRequest
    private let lock = NSLock()
    private var sentMessages: [String] = []
    private var inbox: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var closed = false
    private var failure: Error?

    init(request: URLRequest) {
        self.request = request
    }

    var sent: [String] { lock.withLock { sentMessages } }
    var sentJSON: [[String: Any]] { sent.compactMap(LiveJSON.object) }
    var isClosed: Bool { lock.withLock { closed } }

    func send(_ text: String) async throws {
        lock.withLock { sentMessages.append(text) }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let failure {
                lock.unlock()
                continuation.resume(throwing: failure)
            } else if !inbox.isEmpty {
                let message = inbox.removeFirst()
                lock.unlock()
                continuation.resume(returning: message)
            } else if closed {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    /// Delivers a provider message.
    func deliver(_ object: [String: Any]) {
        deliver(LiveJSON.string(object))
    }

    func deliver(_ message: String) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: message)
        } else {
            inbox.append(message)
            lock.unlock()
        }
    }

    /// The connection drops.
    func fail(_ error: Error) {
        lock.lock()
        failure = error
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(throwing: error)
    }

    func close() {
        lock.lock()
        closed = true
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(throwing: CancellationError())
    }
}

/// Keeps every socket a session opens, in order.
final class FakeSocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [FakeLiveSocket] = []

    var sockets: [FakeLiveSocket] { lock.withLock { opened } }
    var last: FakeLiveSocket? { sockets.last }

    var make: LiveSession.SocketFactory {
        { [self] request in
            let socket = FakeLiveSocket(request: request)
            lock.withLock { opened.append(socket) }
            return socket
        }
    }
}

/// Audio without hardware: records what would play and lets tests set the clock.
@MainActor
final class FakeLiveAudio: LiveAudioIO {
    var onMicrophoneAudio: (@Sendable (Data) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var isPlaying = false
    var playbackPosition: TimeInterval = 0
    var scheduledEnd: TimeInterval = 0

    private(set) var startedWith: (input: Double, output: Double, microphone: Bool)?
    private(set) var played: [Data] = []
    private(set) var stopPlaybackCount = 0
    private(set) var isStopped = false
    var failsToStart = false

    func start(inputSampleRate: Double, outputSampleRate: Double, microphone: Bool) throws {
        if failsToStart { throw LiveAudioError.microphoneUnavailable }
        startedWith = (inputSampleRate, outputSampleRate, microphone)
    }

    func play(_ pcm16: Data) -> LipSyncChunk? {
        played.append(pcm16)
        isPlaying = true
        scheduledEnd += Double(pcm16.count / 2) / 24_000
        return LipSyncChunk(delay: 0, step: 0.02, levels: [0.5])
    }

    func stopPlayback() {
        stopPlaybackCount += 1
        isPlaying = false
    }

    func stop() {
        isStopped = true
        isPlaying = false
    }

    /// The microphone hears something.
    func speak(_ pcm16: Data) {
        onMicrophoneAudio?(pcm16)
    }

    /// A phone call or another app takes the audio.
    func interrupt() {
        onInterrupted?()
    }

    /// Everything scheduled has played.
    func finishPlayback() {
        isPlaying = false
        onPlaybackFinished?()
    }
}

/// Waits (letting the main queue run) until `condition` holds.
@MainActor
func waitUntil(timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("Timed out waiting", file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

func pcm(_ byteCount: Int, value: UInt8 = 1) -> Data {
    Data(repeating: value, count: byteCount)
}
