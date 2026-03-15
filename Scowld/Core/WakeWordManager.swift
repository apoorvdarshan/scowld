import AVFoundation
import Speech
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "WakeWord")

// MARK: - Wake Word Manager

enum WakeWordState {
    case idle
    case wakeListening
    case commandListening
}

@Observable
@MainActor
final class WakeWordManager: NSObject {
    // MARK: - Public State
    var state: WakeWordState = .idle
    var commandText: String = ""
    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startWakeWordListening()
            } else {
                stop()
            }
        }
    }

    // MARK: - Callbacks
    var onWakeWordDetected: (() -> Void)?
    var onCommandReady: ((String) -> Void)?

    // MARK: - Configuration
    var wakeWord: String = UserDefaults.standard.string(forKey: "character_name") ?? "Scowlly"

    // MARK: - Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var lastTranscriptTime: Date = .now
    private var isRestarting = false

    private static let silenceTimeout: TimeInterval = 1.5
    private static let maxRecognitionDuration: TimeInterval = 55.0

    override init() {
        super.init()
    }

    // MARK: - Public API

    func startWakeWordListening() {
        guard isEnabled else { return }
        guard state == .idle || state == .commandListening else { return }
        commandText = ""
        state = .wakeListening
        startRecognition(mode: .wakeWord)
        logger.info("[WakeWord] Entered WAKE_LISTENING")
    }

    func startCommandListening() {
        stopRecognitionInternal()
        commandText = ""
        state = .commandListening
        lastTranscriptTime = .now
        startRecognition(mode: .command)
        startSilenceTimer()
        logger.info("[WakeWord] Entered COMMAND_LISTENING")
    }

    func stop() {
        stopRecognitionInternal()
        silenceTimer?.invalidate()
        silenceTimer = nil
        restartTimer?.invalidate()
        restartTimer = nil
        state = .idle
        commandText = ""
        logger.info("[WakeWord] Stopped")
    }

    // MARK: - Recognition

    private enum RecognitionMode {
        case wakeWord
        case command
    }

    private func startRecognition(mode: RecognitionMode) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            logger.error("[WakeWord] Speech recognizer not available")
            return
        }

        // Stop any existing recognition
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
                        switch mode {
                        case .wakeWord:
                            self.handleWakeWordTranscript(transcript)
                        case .command:
                            self.handleCommandTranscript(transcript)
                        }
                    }
                    if let error {
                        // Error code 216 = recognition ended normally, 209 = retry needed
                        let nsError = error as NSError
                        if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209 || nsError.code == 203) {
                            logger.info("[WakeWord] Recognition ended (code \(nsError.code)), restarting...")
                            self.scheduleRestart(mode: mode)
                        } else {
                            logger.error("[WakeWord] Recognition error: \(error.localizedDescription)")
                            self.scheduleRestart(mode: mode)
                        }
                    } else if result?.isFinal == true {
                        if mode == .wakeWord {
                            self.scheduleRestart(mode: mode)
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

            // Auto-restart before Apple's 60s limit (wake word mode only)
            if mode == .wakeWord {
                restartTimer?.invalidate()
                restartTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecognitionDuration, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.state == .wakeListening else { return }
                        logger.info("[WakeWord] Auto-restart at 55s limit")
                        self.scheduleRestart(mode: .wakeWord)
                    }
                }
            }
        } catch {
            logger.error("[WakeWord] Failed to start recognition: \(error.localizedDescription)")
            // Retry after a delay
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if self.isEnabled && self.state != .idle {
                    self.startRecognition(mode: mode)
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

    private func scheduleRestart(mode: RecognitionMode) {
        guard isEnabled, !isRestarting else { return }
        isRestarting = true
        stopRecognitionInternal()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            self.isRestarting = false
            guard self.isEnabled else { return }
            switch mode {
            case .wakeWord where self.state == .wakeListening:
                self.startRecognition(mode: .wakeWord)
            case .command where self.state == .commandListening:
                self.startRecognition(mode: .command)
            default:
                break
            }
        }
    }

    // MARK: - Transcript Handling

    private func handleWakeWordTranscript(_ transcript: String) {
        if transcript.localizedCaseInsensitiveContains(wakeWord) {
            logger.info("[WakeWord] Wake word detected in: \(transcript)")
            onWakeWordDetected?()
            startCommandListening()
        }
    }

    private func handleCommandTranscript(_ transcript: String) {
        // Check for wake word interrupt (user says wake word again to cancel/restart)
        // Only check if there's already substantial text and wake word appears at the end
        let cleanTranscript = stripWakeWord(from: transcript)
        commandText = cleanTranscript
        lastTranscriptTime = .now
        resetSilenceTimer()
    }

    private func stripWakeWord(from transcript: String) -> String {
        // Remove the wake word if it appears at the very beginning (leftover from detection)
        var text = transcript
        if let range = text.range(of: wakeWord, options: [.caseInsensitive, .anchored]) {
            text.removeSubrange(range)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Silence Timer

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .commandListening else { return }
                let elapsed = Date.now.timeIntervalSince(self.lastTranscriptTime)
                if elapsed >= Self.silenceTimeout && !self.commandText.isEmpty {
                    self.finishCommand()
                }
            }
        }
    }

    private func resetSilenceTimer() {
        lastTranscriptTime = .now
    }

    private func finishCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopRecognitionInternal()

        guard !text.isEmpty else {
            startWakeWordListening()
            return
        }

        logger.info("[WakeWord] Command ready: \(text)")
        state = .idle
        onCommandReady?(text)
        // Resume wake word listening after sending
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if self.isEnabled {
                self.startWakeWordListening()
            }
        }
    }
}
