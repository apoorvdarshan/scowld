import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "LiveConversation")

/// A live voice conversation with the companion: the microphone streams to the
/// selected provider, her voice plays back with lip sync, and each turn is saved
/// to the active chat. One conversation runs at a time.
@MainActor
@Observable
final class LiveConversation {
    enum Phase: Equatable {
        case idle
        case connecting
        case live
    }

    private(set) var phase: Phase = .idle
    private(set) var isAssistantSpeaking = false
    /// What the companion is saying in the current turn, for captions.
    private(set) var assistantCaption = ""
    /// The latest problem, shown briefly.
    private(set) var errorMessage: String?
    private(set) var provider: AIProvider = .gemini

    var isActive: Bool { phase != .idle }

    // Set by the home screen.
    @ObservationIgnored var onLipSync: ((LipSyncChunk) -> Void)?
    @ObservationIgnored var onLipSyncStop: (() -> Void)?
    @ObservationIgnored var captureCameraFrame: (() async -> Data?)?
    @ObservationIgnored var isCameraOn: () -> Bool = { false }
    @ObservationIgnored var onEnded: (() -> Void)?

    /// A conversation ends after this long with no speech either way.
    static let idleTimeout: TimeInterval = 90
    static let connectTimeout: TimeInterval = 20
    static let cameraFrameInterval: TimeInterval = 2
    static let errorDisplayDuration: TimeInterval = 8

    @ObservationIgnored private let memoryStore: MemoryStore
    @ObservationIgnored private let makeSocket: LiveSession.SocketFactory
    @ObservationIgnored private let makeAudio: () -> any LiveAudioIO
    @ObservationIgnored private let loadKey: (AIProvider) -> String?
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var session: LiveSession?
    @ObservationIgnored private var audio: (any LiveAudioIO)?
    @ObservationIgnored private var sessionNumber = 0
    @ObservationIgnored private var pendingUserText = ""
    @ObservationIgnored private var replyText = ""
    @ObservationIgnored private var replyItem: (id: String, start: TimeInterval)?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var lastActivity = Date.distantPast
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var cameraLoop: Task<Void, Never>?
    @ObservationIgnored private var errorClearTask: Task<Void, Never>?

    init(
        memoryStore: MemoryStore,
        makeSocket: @escaping LiveSession.SocketFactory = { URLSessionLiveSocket(request: $0) },
        makeAudio: @escaping () -> any LiveAudioIO = { LiveAudioEngine() },
        loadKey: @escaping (AIProvider) -> String? = { KeychainManager.load(key: $0.keychainKey) },
        now: @escaping () -> Date = Date.init
    ) {
        self.memoryStore = memoryStore
        self.makeSocket = makeSocket
        self.makeAudio = makeAudio
        self.loadKey = loadKey
        self.now = now
    }

    // MARK: - Control

    /// Starts a voice conversation with the selected provider.
    func start() {
        guard !isActive else { return }

        HostedServiceConfig.applyBYOKDefaults()
        let provider = HostedServiceConfig.selectedProvider()
        self.provider = provider
        guard let key = loadKey(provider)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            showError(String.localizedStringWithFormat(
                NSLocalizedString("Add your %@ API key in Settings to talk to %@.", comment: "Missing provider key"),
                provider.shortName,
                CharacterPack.resolveCharacterName()
            ))
            return
        }

        let wire = provider.wire
        let config = LiveSessionConfig(
            provider: provider,
            model: HostedServiceConfig.selectedModel(for: provider),
            voice: HostedServiceConfig.selectedVoice(for: provider),
            apiKey: key,
            instructions: ContextBuilder(memoryStore: memoryStore)
                .buildSystemPrompt(cameraAvailable: provider.cameraSupport != .unsupported)
        )

        sessionNumber += 1
        let number = sessionNumber
        let session = LiveSession(config: config, wire: wire, makeSocket: makeSocket) { [weak self] event in
            // The main queue keeps events in order (reply audio must play in sequence).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(event, session: number)
                }
            }
        }
        let audio = makeAudio()
        audio.onMicrophoneAudio = { @Sendable [weak session] pcm in
            session?.send(audio: pcm)
        }
        audio.onPlaybackFinished = { [weak self] in self?.playbackFinished(session: number) }
        audio.onInterrupted = { [weak self] in
            guard self?.sessionNumber == number else { return }
            self?.end()
        }
        do {
            try audio.start(inputSampleRate: wire.inputSampleRate, outputSampleRate: wire.outputSampleRate, microphone: true)
        } catch {
            logger.error("[Live] Audio failed to start: \(error.localizedDescription, privacy: .public)")
            audio.stop()
            showError(NSLocalizedString("The microphone isn't available. Check microphone access in Settings.", comment: "Microphone unavailable"))
            return
        }

        self.session = session
        self.audio = audio
        phase = .connecting
        isAssistantSpeaking = false
        assistantCaption = ""
        pendingUserText = ""
        replyText = ""
        replyItem = nil
        clearError()
        startedAt = now()
        lastActivity = startedAt
        session.connect()
        startWatchdog(session: number)
    }

    /// Ends the conversation, keeping what was said in the active chat.
    func end(error: String? = nil) {
        guard isActive || session != nil else {
            if let error { showError(error) }
            return
        }
        sessionNumber += 1
        watchdog?.cancel()
        watchdog = nil
        cameraLoop?.cancel()
        cameraLoop = nil
        session?.close()
        session = nil
        audio?.stop()
        audio = nil
        onLipSyncStop?()
        saveTurn()

        phase = .idle
        isAssistantSpeaking = false
        assistantCaption = ""
        if let error {
            showError(error)
        }
        onEnded?()
    }

    /// Ends the conversation when nothing has been said either way for a while, or
    /// when connecting takes too long. The watchdog calls this every few seconds.
    func checkTimeouts() {
        guard isActive else { return }
        let current = now()
        if phase == .connecting, current.timeIntervalSince(startedAt) > Self.connectTimeout {
            end(error: String.localizedStringWithFormat(
                NSLocalizedString("Couldn't connect to %@. Check your connection and try again.", comment: "Live connection timeout"),
                provider.shortName
            ))
            return
        }
        if !isAssistantSpeaking, current.timeIntervalSince(lastActivity) > Self.idleTimeout {
            logger.info("[Live] Ending an idle conversation")
            end()
        }
    }

    // MARK: - Provider events

    private func handle(_ event: LiveEvent, session number: Int) {
        guard number == sessionNumber, isActive else { return }
        switch event {
        case .ready:
            phase = .live
            startCameraLoop(session: number)
        case .audio(let pcm, let itemID):
            noteActivity()
            guard let audio else { return }
            if let itemID, replyItem?.id != itemID {
                replyItem = (itemID, audio.scheduledEnd)
            }
            if let chunk = audio.play(pcm) {
                isAssistantSpeaking = true
                onLipSync?(chunk)
            }
        case .assistantText(let text):
            noteActivity()
            replyText += text
            assistantCaption = replyText
        case .userText(let text, let replacing):
            noteActivity()
            pendingUserText = replacing ? text : pendingUserText + text
        case .userSpeechStarted:
            noteActivity()
            interruptReply(tellProvider: true)
            sendCameraFrameForTurn()
        case .interrupted:
            interruptReply(tellProvider: false)
        case .turnComplete:
            saveTurn()
        case .error(let message):
            logger.error("[Live] Provider error: \(message, privacy: .public)")
            showError(message)
        case .closed(let message):
            end(error: message ?? NSLocalizedString("The live connection ended.", comment: "Live connection closed"))
        case .resumptionHandle, .goAway:
            break
        }
    }

    private func playbackFinished(session number: Int) {
        guard number == sessionNumber else { return }
        isAssistantSpeaking = false
        noteActivity()
        if replyText.isEmpty {
            assistantCaption = ""
        }
    }

    /// Stops her reply because the user spoke over it. OpenAI is told how
    /// much was heard, so the conversation history matches what the user heard.
    private func interruptReply(tellProvider: Bool) {
        guard let audio, audio.isPlaying || isAssistantSpeaking else { return }
        if tellProvider, let replyItem {
            let heardMs = Int(((audio.playbackPosition - replyItem.start) * 1000).rounded())
            session?.truncate(itemID: replyItem.id, audioEndMs: heardMs)
        }
        audio.stopPlayback()
        onLipSyncStop?()
        isAssistantSpeaking = false
    }

    // MARK: - Saved chat

    /// Saves what the user said, then her reply, to the active chat.
    private func saveTurn() {
        savePendingUserText()
        let reply = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reply.isEmpty {
            memoryStore.saveMessage(role: .assistant, content: reply)
        }
        replyText = ""
        replyItem = nil
        if !isAssistantSpeaking {
            assistantCaption = ""
        }
    }

    private func savePendingUserText() {
        let text = pendingUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingUserText = ""
        if !text.isEmpty {
            memoryStore.saveMessage(role: .user, content: text)
        }
    }

    // MARK: - Camera

    /// Gemini watches a frame every couple of seconds while the camera is on.
    private func startCameraLoop(session number: Int) {
        guard provider.cameraSupport == .continuous, cameraLoop == nil else { return }
        cameraLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, number == self.sessionNumber, self.isActive else { return }
                if self.isCameraOn(), let frame = await self.captureCameraFrame?() {
                    guard number == self.sessionNumber else { return }
                    self.session?.send(image: frame)
                }
                try? await Task.sleep(for: .seconds(Self.cameraFrameInterval))
            }
        }
    }

    /// OpenAI sees the latest frame with each thing the user says.
    private func sendCameraFrameForTurn() {
        guard provider.cameraSupport == .perTurn, isCameraOn(),
              let session, let captureCameraFrame else { return }
        Task {
            guard let frame = await captureCameraFrame() else { return }
            session.send(image: frame)
        }
    }

    // MARK: - Helpers

    private func noteActivity() {
        lastActivity = now()
    }

    private func startWatchdog(session number: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, number == self.sessionNumber else { return }
                self.checkTimeouts()
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.errorDisplayDuration))
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }

    private func clearError() {
        errorClearTask?.cancel()
        errorClearTask = nil
        errorMessage = nil
    }
}
