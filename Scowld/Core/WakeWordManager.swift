import AVFoundation
import Speech
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Voice")

// MARK: - Voice Manager

enum VoiceState {
    case idle
    case listening
    case waitingForTTS
}

@Observable
@MainActor
final class VoiceManager: NSObject {
    // MARK: - Public State
    var state: VoiceState = .idle
    var transcriptText: String = ""
    var readyCommand: String? = nil
    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startListening()
            } else {
                stop()
            }
        }
    }

    // MARK: - Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var restartTimer: Timer?
    private var isRestarting = false
    private var silenceWorkItem: DispatchWorkItem?
    private var lastNormalizedText: String = ""
    private var commandText: String = ""
    private var isTTSPlaying = false

    private static let silenceTimeout: TimeInterval = 0.8
    private static let maxRecognitionDuration: TimeInterval = 55.0

    override init() {
        super.init()
    }

    // MARK: - Public API

    func startListening() {
        guard isEnabled else { return }
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        commandText = ""
        lastNormalizedText = ""
        transcriptText = ""
        isTTSPlaying = false

        state = .listening
        startRecognition()
        logger.info("[Voice] Started listening")
    }

    func pauseForTTS() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        stopRecognitionInternal()
        state = .waitingForTTS
        isTTSPlaying = true
        transcriptText = ""
        // Switch to playback so TTS plays through speaker
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        logger.info("[Voice] Paused for TTS")
    }

    func onTTSDone() {
        guard isEnabled, state == .waitingForTTS else { return }
        isTTSPlaying = false

        logger.info("[Voice] TTS done, resuming listening after delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isEnabled, self.state == .waitingForTTS else { return }
            self.startListening()
        }
    }

    func stop() {
        stopRecognitionInternal()
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        restartTimer?.invalidate()
        restartTimer = nil
        state = .idle
        commandText = ""
        transcriptText = ""
        isTTSPlaying = false
        logger.info("[Voice] Stopped")
    }


    // MARK: - Recognition

    private func startRecognition() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            logger.error("[Voice] Speech recognizer not available")
            return
        }

        stopRecognitionInternal()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = true

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        self.handleTranscript(transcript)
                    }
                    if let error {
                        let nsError = error as NSError
                        logger.info("[Voice] Recognition ended (code \(nsError.code)), restarting...")
                        self.scheduleRestart()
                    } else if result?.isFinal == true {
                        if !self.commandText.isEmpty {
                            logger.info("[Voice] Recognition finalized, sending")
                            self.finishCommand()
                        } else {
                            self.scheduleRestart()
                        }
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            // Auto-restart before Apple's 60s limit
            restartTimer?.invalidate()
            restartTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecognitionDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state == .listening else { return }
                    logger.info("[Voice] Auto-restart at 55s limit")
                    self.scheduleRestart()
                }
            }
        } catch {
            logger.error("[Voice] Failed to start recognition: \(error.localizedDescription)")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if self.isEnabled && self.state == .listening {
                    self.startRecognition()
                }
            }
        }
    }

    private func stopRecognitionInternal() {
        restartTimer?.invalidate()
        restartTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func scheduleRestart() {
        guard isEnabled, !isRestarting else { return }
        isRestarting = true
        stopRecognitionInternal()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            self.isRestarting = false
            guard self.isEnabled, self.state == .listening else { return }
            self.startRecognition()
        }
    }

    // MARK: - Transcript Handling

    private func handleTranscript(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriptText = clean
        commandText = clean

        let normalized = clean.lowercased().filter { $0.isLetter || $0.isWhitespace }
        if normalized != lastNormalizedText {
            lastNormalizedText = normalized
            scheduleSilenceCheck()
        }
    }

    private func scheduleSilenceCheck() {
        silenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.state == .listening, !self.commandText.isEmpty else { return }
                self.finishCommand()
            }
        }
        silenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silenceTimeout, execute: workItem)
    }

    private func finishCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        stopRecognitionInternal()

        guard !text.isEmpty else {
            if isEnabled { startListening() }
            return
        }

        logger.info("[Voice] Command ready: \(text)")
        transcriptText = ""
        readyCommand = text
        pauseForTTS()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let voiceInterrupt = Notification.Name("voiceInterrupt")
}
