import AVFoundation
import Speech

// MARK: - Speech Manager

/// Handles both Speech-to-Text (STT) and Text-to-Speech (TTS).
/// Uses Apple's on-device Speech framework (free) and AVSpeechSynthesizer.
@Observable
final class SpeechManager: NSObject {
    // MARK: - Published State
    var isListening = false
    var recognizedText = ""
    var isSpeaking = false
    var currentAmplitude: Float = 0 // 0-1, used for lip sync
    var error: String?

    // MARK: - TTS Settings
    var speechRate: Float = 0.5
    var speechPitch: Float = 1.1

    // MARK: - Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var amplitudeTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micAuthorized: Bool
        if #available(iOS 17.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechAuthorized && micAuthorized
    }

    // MARK: - Speech-to-Text

    func startListening() {
        guard !isListening else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition is not available"
            return
        }

        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = true

            // Start recognition task
            recognizedText = ""
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.recognizedText = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stopListeningInternal()
                    }
                }
            }

            // Install audio tap
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            error = nil
        } catch {
            self.error = "Failed to start listening: \(error.localizedDescription)"
        }
    }

    func stopListening() {
        guard isListening else { return }
        stopListeningInternal()
    }

    private func stopListeningInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false

        // Reset audio session to playback so WKWebView can play audio
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String) {
        // Stop any ongoing speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.preUtteranceDelay = 0.1

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
        }

        isSpeaking = true
        startAmplitudeMonitoring()
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentAmplitude = 0
        stopAmplitudeMonitoring()
    }

    // MARK: - Amplitude Monitoring for Lip Sync

    private func startAmplitudeMonitoring() {
        // Simulate amplitude changes during speech for lip sync
        // Real amplitude from AVSpeechSynthesizer is not directly accessible,
        // so we generate a natural-looking pattern
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isSpeaking else { return }
                // Generate semi-random amplitude for natural lip movement
                let base: Float = 0.3
                let variation = Float.random(in: 0...0.7)
                self.currentAmplitude = base + variation
            }
        }
    }

    private func stopAmplitudeMonitoring() {
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
        currentAmplitude = 0
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: @preconcurrency AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentAmplitude = 0
            self.stopAmplitudeMonitoring()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentAmplitude = 0
            self.stopAmplitudeMonitoring()
        }
    }
}
