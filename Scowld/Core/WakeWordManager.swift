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

    // MARK: - Observable Events (used by SwiftUI instead of closures)
    var wakeWordTriggered: Bool = false
    var readyCommand: String? = nil
    var debugTranscript: String = ""  // Shows what the recognizer is hearing

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
    private var commandListeningStartTime: Date = .now
    private var isRestarting = false
    private var silenceWorkItem: DispatchWorkItem?
    private var lastNormalizedText: String = ""

    private static let silenceTimeout: TimeInterval = 1.5
    private static let maxRecognitionDuration: TimeInterval = 55.0

    override init() {
        super.init()
    }

    // MARK: - Public API

    func startWakeWordListening() {
        guard isEnabled else {
            logger.info("[WakeWord] startWakeWordListening skipped — not enabled")
            return
        }
        guard state == .idle || state == .commandListening else {
            logger.info("[WakeWord] startWakeWordListening skipped — state is \(String(describing: self.state))")
            return
        }
        commandText = ""
        state = .wakeListening
        startRecognition(mode: .wakeWord)
        logger.info("[WakeWord] Entered WAKE_LISTENING")
    }

    func startCommandListening() {
        stopRecognitionInternal()
        commandText = ""
        lastNormalizedText = ""
        debugTranscript = "Listening..."
        state = .commandListening
        lastTranscriptTime = .now
        logger.info("[WakeWord] Entered COMMAND_LISTENING")
        // Small delay so the audio engine fully resets before restarting
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard self.state == .commandListening else { return }
            self.startRecognition(mode: .command)
            // If nothing said after 8s, go back to wake listening
            try? await Task.sleep(for: .seconds(8))
            if self.state == .commandListening && self.commandText.isEmpty {
                logger.info("[WakeWord] No speech detected, returning to wake listening")
                self.stopRecognitionInternal()
                self.startWakeWordListening()
            }
        }
    }

    /// Stop all listening and switch to playback mode so TTS can be heard.
    func pauseForTTS() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        stopRecognitionInternal()
        state = .idle
        // Deactivate and switch to playback so WebView audio plays through speaker
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        logger.info("[WakeWord] Paused for TTS playback")
    }

    /// Call this after TTS/response is done to resume wake word detection
    func resumeWakeListening() {
        guard isEnabled, state == .idle else { return }
        startWakeWordListening()
    }

    func stop() {
        stopRecognitionInternal()
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
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
                        } else if mode == .command && !self.commandText.isEmpty {
                            logger.info("[WakeWord] Recognition finalized, sending command")
                            self.finishCommand()
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
        debugTranscript = transcript
        logger.info("[WakeWord] Heard: \(transcript)")
        if matchesWakeWord(transcript) {
            logger.info("[WakeWord] MATCH for '\(self.wakeWord)' in: \(transcript)")
            wakeWordTriggered = true
            startCommandListening()
        }
    }

    /// Fuzzy match: checks if the transcript contains the wake word or sounds similar.
    /// Speech recognizer often mishears uncommon names (e.g. "Amica" → "America", "a Micah").
    private func matchesWakeWord(_ transcript: String) -> Bool {
        let lower = transcript.lowercased()
        let wake = wakeWord.lowercased()

        // Exact substring match
        if lower.contains(wake) { return true }

        // Check each word in transcript for close match
        let words = lower.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            // Starts-with match (e.g. "amica" matches "america")
            if word.hasPrefix(wake) || wake.hasPrefix(word) { return true }
            // Edit distance — allow 2 edits for words of similar length
            if abs(word.count - wake.count) <= 2 && editDistance(word, wake) <= 2 { return true }
        }

        // Multi-word run match (e.g. "a micah" → "amica")
        let joined = words.joined()
        if joined.contains(wake) { return true }

        return false
    }

    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                if a[i-1] == b[j-1] {
                    dp[j] = prev
                } else {
                    dp[j] = 1 + min(prev, dp[j], dp[j-1])
                }
                prev = temp
            }
        }
        return dp[b.count]
    }

    private func handleCommandTranscript(_ transcript: String) {
        let cleanTranscript = stripWakeWord(from: transcript)
        debugTranscript = cleanTranscript.isEmpty ? "..." : cleanTranscript
        logger.info("[WakeWord] Command transcript: '\(cleanTranscript)'")
        commandText = cleanTranscript
        // Only reschedule auto-send if the actual words changed (ignore case/punctuation)
        let normalized = cleanTranscript.lowercased().filter { $0.isLetter || $0.isWhitespace }
        let previousNormalized = lastNormalizedText
        if normalized != previousNormalized {
            lastNormalizedText = normalized
            scheduleSilenceCheck()
        }
    }

    private func scheduleSilenceCheck() {
        // Cancel previous pending send
        silenceWorkItem?.cancel()
        // Schedule new one — fires 1.5s after last text change
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.state == .commandListening, !self.commandText.isEmpty else { return }
                self.finishCommand()
            }
        }
        silenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silenceTimeout, execute: workItem)
    }

    private func stripWakeWord(from transcript: String) -> String {
        // Remove the wake word (or fuzzy variants) from the beginning
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let wake = wakeWord.lowercased()
        let words = text.components(separatedBy: .whitespaces)
        // Check if first word is the wake word or close to it
        if let firstWord = words.first?.lowercased() {
            if firstWord.contains(wake) || wake.contains(firstWord)
                || editDistance(firstWord, wake) <= 2 {
                text = words.dropFirst().joined(separator: " ")
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
        stopRecognitionInternal()

        guard !text.isEmpty else {
            startWakeWordListening()
            return
        }

        logger.info("[WakeWord] Command ready: \(text)")
        debugTranscript = ""
        readyCommand = text
        // Switch to playback mode so TTS plays through speaker
        pauseForTTS()
    }
}
