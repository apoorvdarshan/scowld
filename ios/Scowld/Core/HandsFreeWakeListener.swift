@preconcurrency import AVFoundation
import Speech
import os

private let handsFreeLogger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "HandsFree")

@Observable
@MainActor
final class HandsFreeWakeListener: NSObject {
    var isRunning = false
    var heardText = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var wakeName = ""
    private var normalizedWakeName = ""
    private var onWake: (() -> Void)?
    private var isStoppingForWake = false
    private var lastWakeAt = Date.distantPast

    private static let recognitionRestartInterval: TimeInterval = 55
    private static let wakeDebounceInterval: TimeInterval = 2.5

    func start(wakeName: String, onWake: @escaping () -> Void) {
        let trimmedName = wakeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            stop()
            return
        }

        let normalizedName = Self.normalized(trimmedName)
        self.onWake = onWake

        if isRunning, normalizedName == normalizedWakeName {
            return
        }

        stop()
        self.wakeName = trimmedName
        self.normalizedWakeName = normalizedName
        startRecognition()
    }

    func stop() {
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
        isRunning = false
        heardText = ""
        isStoppingForWake = false
    }

    private func startRecognition() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            handsFreeLogger.info("[HandsFree] Speech recognizer unavailable")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            recognitionRequest = request

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        self.heardText = transcript
                        self.handleTranscript(transcript)
                    }

                    if error != nil || result?.isFinal == true {
                        self.restartIfNeeded()
                    }
                }
            }

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true
            handsFreeLogger.info("[HandsFree] Listening for hey \(self.wakeName, privacy: .public)")

            restartTimer?.invalidate()
            restartTimer = Timer.scheduledTimer(withTimeInterval: Self.recognitionRestartInterval, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restartIfNeeded()
                }
            }
        } catch {
            handsFreeLogger.error("[HandsFree] Failed to start wake listener: \(error.localizedDescription)")
            stop()
        }
    }

    private func restartIfNeeded() {
        guard isRunning, !isStoppingForWake else { return }
        stop()
        guard !wakeName.isEmpty else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !self.wakeName.isEmpty else { return }
            self.startRecognition()
        }
    }

    private func handleTranscript(_ transcript: String) {
        guard Date().timeIntervalSince(lastWakeAt) > Self.wakeDebounceInterval else { return }
        guard matchesWakePhrase(transcript) else { return }

        lastWakeAt = Date()
        isStoppingForWake = true
        handsFreeLogger.info("[HandsFree] Wake phrase detected")
        let wakeAction = onWake
        stop()
        wakeAction?()
    }

    private func matchesWakePhrase(_ text: String) -> Bool {
        let normalizedText = " \(Self.normalized(text)) "
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        return Self.nameCandidates(for: wakeName).contains { candidate in
            normalizedText.contains(" hey \(candidate) ")
        }
    }

    private static func nameCandidates(for name: String) -> [String] {
        let base = normalized(name)
        var candidates = Set<String>()
        candidates.insert("bella")
        if !base.isEmpty {
            candidates.insert(base)
            if let first = base.split(separator: " ").first {
                candidates.insert(String(first))
            }
        }

        switch base {
        case "aria":
            candidates.insert("area")
        case "ciel":
            candidates.insert("seal")
            candidates.insert("seel")
            candidates.insert("see l")
        default:
            break
        }

        return Array(candidates)
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let scalarText = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalarText)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
