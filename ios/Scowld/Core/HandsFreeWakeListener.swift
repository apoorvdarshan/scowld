@preconcurrency import AVFoundation
@preconcurrency import Speech
import os

nonisolated private let handsFreeLogger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "HandsFree")

/// The microphone side of wake listening. Activating the audio session and
/// starting the engine can take a few hundred milliseconds, so it runs on its own
/// serial queue: on the main thread it froze the Chat tab each time listening
/// started (switching to the tab, and every automatic restart).
nonisolated private final class WakeMicrophone: @unchecked Sendable {
    private enum Failure: Error {
        case invalidInputFormat
    }

    private let queue = DispatchQueue(label: "com.apoorvdarshan.Scowld.wake-microphone", qos: .userInitiated)
    // Touched only on `queue`.
    private let engine = AVAudioEngine()
    private var hasInputTap = false

    /// Starts feeding microphone buffers to `append` (on an audio thread), then
    /// reports on the main queue whether it started.
    func start(append: @escaping @Sendable (AVAudioPCMBuffer) -> Void, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            let started: Bool
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.invalidInputFormat }
                stopEngine()
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    append(buffer)
                }
                hasInputTap = true
                engine.prepare()
                try engine.start()
                started = true
            } catch {
                handsFreeLogger.error("[HandsFree] Failed to start the microphone: \(String(describing: error), privacy: .public)")
                stopEngine()
                started = false
            }
            DispatchQueue.main.async {
                completion(started)
            }
        }
    }

    /// Stops the microphone. With `waitUntilStopped`, returns only once it has
    /// stopped, so a live conversation can take the microphone over right away.
    func stop(waitUntilStopped: Bool) {
        if waitUntilStopped {
            queue.sync { stopEngine() }
        } else {
            queue.async { [self] in stopEngine() }
        }
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine.reset()
    }
}

@Observable
@MainActor
final class HandsFreeWakeListener: NSObject {
    var isRunning = false
    var heardText = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let microphone = WakeMicrophone()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var wakeName = ""
    private var normalizedWakeName = ""
    private var onWake: (() -> Void)?
    private var isStoppingForWake = false
    /// The microphone is starting in the background.
    private var isStarting = false
    /// Bumped by `stop()`, so a start that finishes afterwards is ignored.
    private var generation = 0
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

        if isRunning || isStarting, normalizedName == normalizedWakeName {
            return
        }

        stop()
        self.wakeName = trimmedName
        self.normalizedWakeName = normalizedName
        startRecognition()
    }

    /// Stops listening. With `waitUntilStopped`, the microphone is free when this
    /// returns (before a live conversation starts); otherwise it stops in the
    /// background so the screen never waits.
    func stop(waitUntilStopped: Bool = false) {
        generation += 1
        restartTimer?.invalidate()
        restartTimer = nil

        microphone.stop(waitUntilStopped: waitUntilStopped)

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRunning = false
        isStarting = false
        heardText = ""
        isStoppingForWake = false
    }

    private func startRecognition() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            handsFreeLogger.info("[HandsFree] Speech recognizer unavailable")
            return
        }

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

        isStarting = true
        let current = generation
        microphone.start(append: { buffer in
            request.append(buffer)
        }, completion: { [weak self] started in
            MainActor.assumeIsolated {
                self?.microphoneStarted(started, generation: current)
            }
        })
    }

    private func microphoneStarted(_ started: Bool, generation startedGeneration: Int) {
        guard startedGeneration == generation else { return }
        isStarting = false
        guard started else {
            stop()
            return
        }
        isRunning = true
        handsFreeLogger.info("[HandsFree] Listening for hey \(self.wakeName, privacy: .public)")

        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: Self.recognitionRestartInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartIfNeeded()
            }
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
        // The live conversation needs the microphone next.
        stop(waitUntilStopped: true)
        wakeAction?()
    }

    private func matchesWakePhrase(_ text: String) -> Bool {
        let normalizedText = " \(Self.normalized(text)) "
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        return Self.nameCandidates(for: wakeName).contains { candidate in
            normalizedText.contains(" \(candidate) ") ||
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
