import Foundation
import os

nonisolated private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "LiveSession")

/// One live speech-to-speech connection to a provider.
///
/// Messages go out in the order they are sent. Until the provider is ready, they
/// wait in a queue; microphone audio in that queue is capped, so a slow connection
/// keeps only the most recent few seconds of speech. Events arrive on a background
/// thread through `onEvent`.
nonisolated final class LiveSession: @unchecked Sendable {
    typealias SocketFactory = @Sendable (URLRequest) -> any LiveSocket

    /// Audio waiting for a connection beyond this is dropped, oldest first.
    static let maximumQueuedAudioBytes = 24_000 * 2 * 6 // six seconds at 24 kHz

    let config: LiveSessionConfig
    let wire: any LiveWire

    private let makeSocket: SocketFactory
    private let onEvent: @Sendable (LiveEvent) -> Void

    private let lock = NSLock()
    private var socket: (any LiveSocket)?
    private var outbox: AsyncStream<String>.Continuation?
    private var connection = 0
    private var isReady = false
    private var isClosed = false
    private var queued: [(message: String, audioBytes: Int)] = []
    private var queuedAudioBytes = 0
    private var resumptionHandle: String?

    init(
        config: LiveSessionConfig,
        wire: any LiveWire,
        makeSocket: @escaping SocketFactory = { URLSessionLiveSocket(request: $0) },
        onEvent: @escaping @Sendable (LiveEvent) -> Void
    ) {
        self.config = config
        self.wire = wire
        self.makeSocket = makeSocket
        self.onEvent = onEvent
    }

    func connect() {
        open()
    }

    func send(audio pcm16: Data) {
        guard !pcm16.isEmpty else { return }
        enqueue(wire.audioMessage(pcm16), audioBytes: pcm16.count)
    }

    func send(text: String, image: Data? = nil) {
        for message in wire.textMessages(text, image: image) {
            enqueue(message, audioBytes: 0)
        }
    }

    func send(image jpeg: Data) {
        for message in wire.imageMessages(jpeg) {
            enqueue(message, audioBytes: 0)
        }
    }

    /// Tells the provider how much of reply `itemID` the user heard before speaking over it.
    func truncate(itemID: String, audioEndMs: Int) {
        guard let message = wire.truncateMessage(itemID: itemID, audioEndMs: audioEndMs) else { return }
        enqueue(message, audioBytes: 0)
    }

    /// Stops a reply in progress, so typed text can ask for a new one.
    func cancelReply() {
        for message in wire.cancelReplyMessages() {
            enqueue(message, audioBytes: 0)
        }
    }

    func close() {
        let (socket, outbox): ((any LiveSocket)?, AsyncStream<String>.Continuation?) = lock.withLock {
            isClosed = true
            connection += 1
            queued.removeAll()
            queuedAudioBytes = 0
            defer { self.socket = nil; self.outbox = nil }
            return (self.socket, self.outbox)
        }
        outbox?.finish()
        socket?.close()
    }

    // MARK: - Connection

    private func open() {
        let request = wire.request(for: config)
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let opened: (id: Int, socket: any LiveSocket, handle: String?)? = lock.withLock {
            guard !isClosed else { return nil }
            connection += 1
            isReady = false
            let socket = makeSocket(request)
            self.socket = socket
            self.outbox = continuation
            return (connection, socket, resumptionHandle)
        }
        guard let opened else {
            continuation.finish()
            return
        }

        // Sender: one consumer keeps messages in order.
        Task { [weak self] in
            for await message in stream {
                do {
                    try await opened.socket.send(message)
                } catch {
                    self?.connectionFailed(opened.id, error)
                    return
                }
            }
        }

        for message in wire.setupMessages(for: config, resumptionHandle: opened.handle) {
            continuation.yield(message)
        }
        if !wire.waitsForSetupAcknowledgement {
            markReady(opened.id)
        }

        // Receiver.
        Task { [weak self] in
            while true {
                let text: String
                do {
                    text = try await opened.socket.receive()
                } catch {
                    self?.connectionFailed(opened.id, error)
                    return
                }
                guard let self else { return }
                for event in self.wire.parse(text) {
                    self.handle(event, connection: opened.id)
                }
            }
        }
    }

    private func handle(_ event: LiveEvent, connection id: Int) {
        guard lock.withLock({ id == connection && !isClosed }) else { return }
        switch event {
        case .ready:
            markReady(id)
        case .resumptionHandle(let handle):
            lock.withLock { resumptionHandle = handle }
        case .goAway:
            reconnect(from: id)
        default:
            onEvent(event)
        }
    }

    private func markReady(_ id: Int) {
        let flushed: (AsyncStream<String>.Continuation, [String])? = lock.withLock {
            guard id == connection, !isClosed, let outbox else { return nil }
            isReady = true
            let messages = queued.map(\.message)
            queued.removeAll()
            queuedAudioBytes = 0
            return (outbox, messages)
        }
        guard let (outbox, messages) = flushed else { return }
        for message in messages {
            outbox.yield(message)
        }
        onEvent(.ready)
    }

    private func enqueue(_ message: String, audioBytes: Int) {
        let outbox: AsyncStream<String>.Continuation? = lock.withLock {
            guard !isClosed else { return nil }
            if isReady, let outbox { return outbox }
            queued.append((message, audioBytes))
            queuedAudioBytes += audioBytes
            // Keep only the latest few seconds of speech while waiting.
            while queuedAudioBytes > Self.maximumQueuedAudioBytes,
                  let index = queued.firstIndex(where: { $0.audioBytes > 0 }) {
                queuedAudioBytes -= queued[index].audioBytes
                queued.remove(at: index)
            }
            return nil
        }
        outbox?.yield(message)
    }

    /// Gemini asks clients to move to a new connection before it closes one; the
    /// resumption handle carries the conversation over.
    private func reconnect(from id: Int) {
        let old: ((any LiveSocket)?, AsyncStream<String>.Continuation?)? = lock.withLock {
            guard id == connection, !isClosed else { return nil }
            // Retire the old connection first, so its closing can't end the session.
            connection += 1
            isReady = false
            defer { socket = nil; outbox = nil }
            return (socket, outbox)
        }
        guard let (socket, outbox) = old else { return }
        logger.info("[Live] Moving to a new connection")
        outbox?.finish()
        socket?.close()
        open()
    }

    private func connectionFailed(_ id: Int, _ error: Error) {
        let shouldReport = lock.withLock {
            guard id == connection, !isClosed else { return false }
            isClosed = true
            return true
        }
        guard shouldReport else { return }
        logger.error("[Live] Connection ended: \(error.localizedDescription, privacy: .public)")
        let socket = lock.withLock { () -> (any LiveSocket)? in
            defer { self.socket = nil; self.outbox = nil }
            return self.socket
        }
        socket?.close()
        onEvent(.closed(error.localizedDescription))
    }
}
