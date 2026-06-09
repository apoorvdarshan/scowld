@preconcurrency import AVFoundation
import Speech
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Voice")

// MARK: - Voice Manager

enum VoiceState {
    case idle
    case listening
    case waitingForTTS
    case transcribing // Cloud STT is processing
}

private struct VoiceAudioLevel: Sendable {
    let peak: Float
    let rms: Float

    var decibels: Float {
        20 * log10(max(rms, 0.000_001))
    }
}

private enum VoiceAudioStartError: LocalizedError {
    case invalidInputFormat

    var errorDescription: String? {
        "Microphone input format is unavailable"
    }
}

@Observable
@MainActor
final class VoiceManager: NSObject {
    // MARK: - Public State
    var state: VoiceState = .idle
    var transcriptText: String = ""
    var speechStatusText: String = ""
    var readyCommand: String? = nil
    var isEnabled: Bool = false
    var hasCapturedSpeech: Bool {
        hasDetectedSpeech ||
            !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var restartTimer: Timer?
    private var isRestarting = false
    private var speechStartWorkItem: DispatchWorkItem?
    private var speechEndWorkItem: DispatchWorkItem?
    private var lastNormalizedText: String = ""
    private var commandText: String = ""
    private var isTTSPlaying = false
    private var isSpeechStatusLatched = false
    private var ambientNoiseDecibels: Float = -55
    private var speechActivityReadyAt = Date.distantPast
    private var automaticallyFinishAfterSilence = false
    private var automaticFinishWorkItem: DispatchWorkItem?

    // Cloud STT audio buffer storage
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var preSpeechAudioBuffers: [AVAudioPCMBuffer] = []
    private var audioFormat: AVAudioFormat?
    private var hasInstalledInputTap = false
    private var hasDetectedSpeech = false
    private var speechBufferCount = 0

    private static let speechStartConfirmDuration: TimeInterval = 0.2
    private static let speechStatusReleaseDuration: TimeInterval = 0.75
    private static let speechActivityCalibrationDuration: TimeInterval = 0.35
    private static let initialAmbientNoiseDecibels: Float = -55
    private static let speechMinimumDecibels: Float = -38
    private static let speechNoiseMarginDecibels: Float = 12
    private static let speechPeakThreshold: Float = 0.065
    private static let ambientNoiseSmoothing: Float = 0.18
    private static let maxRecognitionDuration: TimeInterval = 55.0
    private static let cloudPreSpeechBufferLimit = 10
    private static let cloudMinimumSpeechBufferCount = 4
    private static let automaticSilenceFinishDuration: TimeInterval = 1.4
    private static let automaticNoSpeechTimeout: TimeInterval = 8

    /// Current STT backend from settings
    private var currentBackend: STTBackend {
        let raw = UserDefaults.standard.string(forKey: "amica_stt_backend") ?? STTBackend.nativeIOS.rawValue
        return STTBackend(rawValue: raw) ?? .nativeIOS
    }

    override init() {
        super.init()
    }

    // MARK: - Public API

    func startCommandCapture(autoFinishOnSilence: Bool = false) {
        guard state == .idle else { return }
        automaticallyFinishAfterSilence = autoFinishOnSilence
        isEnabled = true
        startListening()
    }

    func finishCommandCapture() {
        guard state == .listening else { return }
        isEnabled = false
        cancelAutomaticFinish()
        if currentBackend.isCloudBased {
            finishCloudRecording()
        } else {
            finishCommand()
        }
    }

    func cancelCommandCapture() {
        isEnabled = false
        automaticallyFinishAfterSilence = false
        cancelAutomaticFinish()
        stop()
    }

    private func startListening() {
        guard isEnabled else { return }
        guard state == .idle else {
            logger.info("[Voice] Ignoring listen start while state is locked")
            return
        }
        commandText = ""
        lastNormalizedText = ""
        transcriptText = ""
        isTTSPlaying = false
        audioBuffers = []
        preSpeechAudioBuffers = []
        hasDetectedSpeech = false
        speechBufferCount = 0
        cancelAutomaticFinish()
        ambientNoiseDecibels = Self.initialAmbientNoiseDecibels
        speechActivityReadyAt = Date().addingTimeInterval(Self.speechActivityCalibrationDuration)
        resetSpeechStatus()

        state = .listening

        if currentBackend.isCloudBased {
            startCloudRecording()
        } else {
            startRecognition()
        }
        logger.info("[Voice] Started listening (\(self.currentBackend.rawValue))")
    }

    func pauseForTTS() {
        stopRecognitionInternal()
        state = .waitingForTTS
        isTTSPlaying = true
        transcriptText = ""
        resetSpeechStatus()
        cancelAutomaticFinish()
        ScowldAudioSession.configureAmicaWebAudioPlayback()
        logger.info("[Voice] Paused for TTS")
    }

    func onTTSDone() {
        guard state == .waitingForTTS else { return }
        isTTSPlaying = false
        state = .idle
        transcriptText = ""
        resetSpeechStatus()
        logger.info("[Voice] TTS done")
    }

    func stop() {
        stopRecognitionInternal()
        restartTimer?.invalidate()
        restartTimer = nil
        state = .idle
        commandText = ""
        transcriptText = ""
        resetSpeechStatus()
        isTTSPlaying = false
        audioBuffers = []
        preSpeechAudioBuffers = []
        automaticallyFinishAfterSilence = false
        cancelAutomaticFinish()
        logger.info("[Voice] Stopped")
    }

    // MARK: - Native iOS Recognition

    private func startRecognition() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            logger.error("[Voice] Speech recognizer not available")
            return
        }

        stopRecognitionInternal()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = true

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        self.handleTranscript(transcript)
                    }
                    if let error {
                        let nsError = error as NSError
                        logger.info("[Voice] Recognition ended (code \(nsError.code))")
                    } else if result?.isFinal == true {
                        logger.info("[Voice] Recognition finalized")
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw VoiceAudioStartError.invalidInputFormat
            }
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                let level = Self.audioLevel(for: buffer)
                Task { @MainActor [weak self] in
                    self?.handleSpeechActivity(level)
                }
            }
            hasInstalledInputTap = true

            audioEngine.prepare()
            try audioEngine.start()

            // Auto-restart before Apple's 60s limit
            restartTimer?.invalidate()
            restartTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecognitionDuration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .listening else { return }
                    logger.info("[Voice] Auto-restart at 55s limit")
                    self.scheduleRestart()
                }
            }
        } catch {
            stopRecognitionInternal()
            logger.error("[Voice] Failed to start recognition: \(error.localizedDescription)")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.isEnabled && self.state == .listening {
                    self.startRecognition()
                }
            }
        }
    }

    // MARK: - Cloud STT Recording

    private func startCloudRecording() {
        stopRecognitionInternal()
        audioBuffers = []
        preSpeechAudioBuffers = []
        hasDetectedSpeech = false

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw VoiceAudioStartError.invalidInputFormat
            }
            audioFormat = recordingFormat

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                Task { @MainActor [weak self] in
                    self?.handleCloudAudioBuffer(buffer)
                }
            }
            hasInstalledInputTap = true

            audioEngine.prepare()
            try audioEngine.start()

            transcriptText = ""
            logger.info("[Voice] Cloud recording started")

            // Auto-restart to prevent infinite recording
            restartTimer?.invalidate()
            let noSpeechTimeout = automaticallyFinishAfterSilence ? Self.automaticNoSpeechTimeout : 30
            restartTimer = Timer.scheduledTimer(withTimeInterval: noSpeechTimeout, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .listening else { return }
                    if self.hasDetectedSpeech {
                        self.isEnabled = false
                        self.finishCloudRecording()
                    } else {
                        self.isEnabled = false
                        self.restartListening(afterShowing: "No speech detected")
                    }
                }
            }
        } catch {
            stopRecognitionInternal()
            logger.error("[Voice] Failed to start cloud recording: \(error.localizedDescription)")
        }
    }

    private func handleCloudAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let level = Self.audioLevel(for: buffer)
        handleSpeechActivity(level)
        guard let copy = copyAudioBuffer(buffer) else { return }
        let speechLike = isSpeechLike(level)

        if speechLike {
            cancelAutomaticFinish()
            if !hasDetectedSpeech {
                audioBuffers.append(contentsOf: preSpeechAudioBuffers)
                preSpeechAudioBuffers = []
            }
            hasDetectedSpeech = true
            speechBufferCount += 1
            audioBuffers.append(copy)
        } else if hasDetectedSpeech {
            // Still capture silence buffers (for natural speech gaps)
            audioBuffers.append(copy)
            scheduleAutomaticFinishIfNeeded()
        } else {
            preSpeechAudioBuffers.append(copy)
            if preSpeechAudioBuffers.count > Self.cloudPreSpeechBufferLimit {
                preSpeechAudioBuffers.removeFirst(preSpeechAudioBuffers.count - Self.cloudPreSpeechBufferLimit)
            }
        }
    }

    private func finishCloudRecording() {
        isEnabled = false
        stopRecognitionInternal()
        cancelAutomaticFinish()

        // Need a few confirmed speech buffers to avoid sending background noise.
        guard !audioBuffers.isEmpty, let format = audioFormat, speechBufferCount >= Self.cloudMinimumSpeechBufferCount else {
            logger.info("[Voice] Not enough speech detected (\(self.speechBufferCount) buffers), restarting")
            resetSpeechStatus()
            restartListening(afterShowing: "No speech detected")
            return
        }

        let buffers = audioBuffers
        audioBuffers = []

        state = .transcribing
        resetSpeechStatus()
        speechStatusText = "Transcribing..."
        logger.info("[Voice] Sending \(buffers.count) buffers to cloud STT")

        let backend = currentBackend

        Task { @MainActor in
            do {
                let wavData = CloudSTTManager.createWAV(from: buffers, format: format)
                logger.info("[Voice] Cloud STT upload: backend=\(backend.rawValue) model=\(STTBackend.selectedModel(for: backend)) wavBytes=\(wavData.count)")
                let transcript = try await CloudSTTManager.transcribe(audioData: wavData, backend: backend)

                let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else {
                    logger.info("[Voice] Cloud STT returned empty transcript")
                    restartListening(afterShowing: "Didn't catch that")
                    return
                }

                logger.info("[Voice] Cloud STT result: \(clean)")
                speechStatusText = ""
                readyCommand = clean
                pauseForTTS()
            } catch {
                logger.error("[Voice] Cloud STT error: \(error.localizedDescription)")
                transcriptText = ""
                restartListening(afterShowing: sttFailureMessage(for: error))
            }
        }
    }

    // MARK: - Common

    private func stopRecognitionInternal() {
        restartTimer?.invalidate()
        restartTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if hasInstalledInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }

        audioEngine.reset()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func scheduleRestart() {
        guard isEnabled, !isRestarting else { return }
        isRestarting = true
        cancelAutomaticFinish()
        stopRecognitionInternal()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            self.isRestarting = false
            guard self.isEnabled, self.state == .listening else { return }
            if self.currentBackend.isCloudBased {
                self.startCloudRecording()
            } else {
                self.startRecognition()
            }
        }
    }

    // MARK: - Transcript Handling (Native iOS)

    private func handleTranscript(_ transcript: String) {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriptText = clean
        commandText = clean

        let normalized = clean.lowercased().filter { $0.isLetter || $0.isWhitespace }
        if normalized != lastNormalizedText {
            lastNormalizedText = normalized
        }
    }

    private func finishCommand() {
        isEnabled = false
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecognitionInternal()

        guard !text.isEmpty else {
            state = .idle
            if isEnabled { startListening() }
            return
        }

        logger.info("[Voice] Command ready: \(text)")
        transcriptText = ""
        speechStatusText = ""
        readyCommand = text
        pauseForTTS()
    }

    private func scheduleAutomaticFinishIfNeeded() {
        guard automaticallyFinishAfterSilence,
              state == .listening,
              automaticFinishWorkItem == nil,
              hasCapturedSpeech
        else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.automaticallyFinishAfterSilence,
                      self.state == .listening
                else { return }
                self.automaticFinishWorkItem = nil
                self.finishCommandCapture()
            }
        }

        automaticFinishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.automaticSilenceFinishDuration, execute: workItem)
    }

    private func cancelAutomaticFinish() {
        automaticFinishWorkItem?.cancel()
        automaticFinishWorkItem = nil
    }

    // MARK: - Local Speech Activity

    nonisolated private static func audioLevel(for buffer: AVAudioPCMBuffer) -> VoiceAudioLevel {
        guard let channelData = buffer.floatChannelData else {
            return VoiceAudioLevel(peak: 0, rms: 0)
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return VoiceAudioLevel(peak: 0, rms: 0)
        }

        let channelCount = max(1, Int(buffer.format.channelCount))
        var peak: Float = 0
        var sumSquares: Float = 0
        var sampleCount: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameCount {
                let sample = samples[index]
                let absolute = abs(sample)
                peak = max(peak, absolute)
                sumSquares += sample * sample
                sampleCount += 1
            }
        }

        let rms = sqrt(sumSquares / max(sampleCount, 1))
        return VoiceAudioLevel(peak: peak, rms: rms)
    }

    private func isSpeechLike(_ level: VoiceAudioLevel) -> Bool {
        let threshold = max(Self.speechMinimumDecibels, ambientNoiseDecibels + Self.speechNoiseMarginDecibels)
        return level.decibels >= threshold && level.peak >= Self.speechPeakThreshold
    }

    private func copyAudioBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        copy.frameLength = buffer.frameLength
        if let srcData = buffer.floatChannelData, let dstData = copy.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                memcpy(dstData[ch], srcData[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }

        return copy
    }

    private func handleSpeechActivity(_ level: VoiceAudioLevel) {
        guard state == .listening, !isTTSPlaying else { return }

        if Date() < speechActivityReadyAt {
            updateAmbientNoiseFloor(with: level)
            return
        }

        if isSpeechLike(level) {
            cancelAutomaticFinish()
            speechEndWorkItem?.cancel()
            speechEndWorkItem = nil

            guard !isSpeechStatusLatched else {
                speechStatusText = "Listening..."
                return
            }

            guard speechStartWorkItem == nil else { return }

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .listening, !self.isTTSPlaying else { return }
                    self.isSpeechStatusLatched = true
                    self.speechStatusText = "Listening..."
                    self.speechStartWorkItem = nil
                }
            }
            speechStartWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.speechStartConfirmDuration, execute: workItem)
        } else {
            updateAmbientNoiseFloor(with: level)
            speechStartWorkItem?.cancel()
            speechStartWorkItem = nil
            scheduleSpeechStatusRelease()
            scheduleAutomaticFinishIfNeeded()
        }
    }

    private func scheduleSpeechStatusRelease() {
        guard isSpeechStatusLatched, speechEndWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                self.isSpeechStatusLatched = false
                self.speechStatusText = ""
                self.speechEndWorkItem = nil
            }
        }
        speechEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.speechStatusReleaseDuration, execute: workItem)
    }

    private func resetSpeechStatus() {
        speechStartWorkItem?.cancel()
        speechStartWorkItem = nil
        speechEndWorkItem?.cancel()
        speechEndWorkItem = nil
        isSpeechStatusLatched = false
        speechStatusText = ""
    }

    private func updateAmbientNoiseFloor(with level: VoiceAudioLevel) {
        guard !isSpeechStatusLatched else { return }
        let measured = min(max(level.decibels, -80), -20)
        ambientNoiseDecibels += (measured - ambientNoiseDecibels) * Self.ambientNoiseSmoothing
    }

    private func restartListening(afterShowing message: String) {
        stopRecognitionInternal()
        cancelAutomaticFinish()
        resetSpeechStatus()
        speechStatusText = message
        state = .idle

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self else { return }
            guard self.state == .idle else { return }
            self.speechStatusText = ""
            if self.isEnabled {
                self.startListening()
            }
        }
    }

    private func sttFailureMessage(for error: Error) -> String {
        guard let sttError = error as? CloudSTTError else {
            return "STT failed: \(shortErrorMessage(error.localizedDescription))"
        }

        switch sttError {
        case .noAPIKey:
            return "STT API key missing"
        case .timeout:
            return "STT timed out"
        case .apiError(let message):
            return "STT API: \(shortErrorMessage(message))"
        case .parseError:
            return "STT response parse failed"
        case .unsupportedBackend:
            return "STT backend unsupported"
        }
    }

    private func shortErrorMessage(_ message: String) -> String {
        let singleLine = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.isEmpty {
            return "unknown error"
        }

        if singleLine.count > 90 {
            return String(singleLine.prefix(90)) + "..."
        }

        return singleLine
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let voiceInterrupt = Notification.Name("voiceInterrupt")
}
