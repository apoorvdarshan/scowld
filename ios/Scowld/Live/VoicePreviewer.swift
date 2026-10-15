import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "VoicePreview")

/// Plays a short line in a provider voice, using the user's own key, so they can
/// hear a voice before choosing it. Each preview is one brief live session.
@MainActor
@Observable
final class VoicePreviewer {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The voice being previewed (or that just failed).
    private(set) var voice: String?

    static let timeout: TimeInterval = 20
    static let instructions = "You are a text-to-speech voice. Read the text you are given aloud exactly as written, word for word, warmly and naturally. Do not answer it or add anything."

    static func line(name: String) -> String {
        "Say exactly this: Hi, I'm \(name)! This is my voice. Do you like how I sound?"
    }

    @ObservationIgnored private let makeSocket: LiveSession.SocketFactory
    @ObservationIgnored private let makeAudio: () -> any LiveAudioIO
    @ObservationIgnored private var session: LiveSession?
    @ObservationIgnored private var audio: (any LiveAudioIO)?
    @ObservationIgnored private var number = 0
    @ObservationIgnored private var replyFinished = false
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init(
        makeSocket: @escaping LiveSession.SocketFactory = { URLSessionLiveSocket(request: $0) },
        makeAudio: @escaping () -> any LiveAudioIO = { LiveAudioEngine() }
    ) {
        self.makeSocket = makeSocket
        self.makeAudio = makeAudio
    }

    func play(provider: AIProvider, model: String, voice: String, apiKey: String, name: String, timeout: TimeInterval = VoicePreviewer.timeout) {
        stop()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        number += 1
        let current = number
        let wire = provider.wire
        let config = LiveSessionConfig(provider: provider, model: model, voice: voice, apiKey: key, instructions: Self.instructions)
        let session = LiveSession(config: config, wire: wire, makeSocket: makeSocket) { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(event, preview: current)
                }
            }
        }
        let audio = makeAudio()
        audio.onPlaybackFinished = { [weak self] in self?.playbackFinished(preview: current) }
        audio.onInterrupted = { [weak self] in
            guard self?.number == current else { return }
            self?.stop()
        }
        do {
            try audio.start(inputSampleRate: wire.inputSampleRate, outputSampleRate: wire.outputSampleRate, microphone: false)
        } catch {
            audio.stop()
            state = .failed(error.localizedDescription)
            self.voice = voice
            return
        }

        self.session = session
        self.audio = audio
        self.voice = voice
        replyFinished = false
        state = .loading
        session.connect()
        session.send(text: Self.line(name: name))

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled, self.number == current, self.state == .loading else { return }
            self.fail(String.localizedStringWithFormat(
                NSLocalizedString("Couldn't connect to %@. Check your connection and try again.", comment: "Live connection timeout"),
                provider.shortName
            ))
        }
    }

    func stop() {
        number += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        session?.close()
        session = nil
        audio?.stop()
        audio = nil
        if state != .idle, !isFailure {
            state = .idle
        }
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func handle(_ event: LiveEvent, preview current: Int) {
        guard current == number, let audio else { return }
        switch event {
        case .audio(let pcm, _):
            if audio.play(pcm) != nil {
                state = .playing
            }
        case .turnComplete:
            replyFinished = true
            if !audio.isPlaying {
                finish()
            } else {
                // The reply is complete; nothing else is needed from the provider.
                session?.close()
                session = nil
            }
        case .error(let message):
            logger.error("[Preview] Provider error: \(message, privacy: .public)")
            if state != .playing { fail(message) }
        case .closed(let message):
            if state == .playing {
                replyFinished = true
            } else {
                fail(message ?? NSLocalizedString("The live connection ended.", comment: "Live connection closed"))
            }
        default:
            break
        }
    }

    private func playbackFinished(preview current: Int) {
        guard current == number, replyFinished else { return }
        finish()
    }

    private func finish() {
        stop()
        state = .idle
    }

    private func fail(_ message: String) {
        let voice = self.voice
        stop()
        self.voice = voice
        state = .failed(message)
    }
}
