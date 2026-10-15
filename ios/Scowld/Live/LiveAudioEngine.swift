@preconcurrency import AVFoundation
import os

nonisolated private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "LiveAudio")

/// Mouth movement for one played chunk of the companion's voice: one level per
/// `step` seconds, starting `delay` seconds from now.
struct LipSyncChunk: Equatable {
    let delay: TimeInterval
    let step: TimeInterval
    let levels: [Float]
}

/// Microphone in, companion voice out. `LiveConversation` drives it; tests use a fake.
protocol LiveAudioIO: AnyObject {
    /// Receives microphone audio (16-bit mono PCM at the input rate) on an audio thread.
    var onMicrophoneAudio: (@Sendable (Data) -> Void)? { get set }
    /// Called on the main actor when everything scheduled has finished playing.
    var onPlaybackFinished: (() -> Void)? { get set }
    /// Called on the main actor when the system stops the audio (a phone call,
    /// another app taking over, or a route change it can't recover from).
    var onInterrupted: (() -> Void)? { get set }
    var isPlaying: Bool { get }

    /// Starts the microphone and playback. With `microphone` false (voice previews in
    /// Settings) only playback runs.
    func start(inputSampleRate: Double, outputSampleRate: Double, microphone: Bool) throws
    /// Schedules reply audio after anything already queued and returns its mouth movement.
    func play(_ pcm16: Data) -> LipSyncChunk?
    /// Where playback is, in seconds since this reply's audio began.
    var playbackPosition: TimeInterval { get }
    /// Where the next scheduled chunk will start, in the same timeline as `playbackPosition`.
    var scheduledEnd: TimeInterval { get }
    func stopPlayback()
    func stop()
}

enum LiveAudioError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "The microphone isn't available."
        }
    }
}

/// AVAudioEngine with voice processing: the echo canceller removes the companion's
/// own voice from the microphone, so she doesn't hear and interrupt herself when
/// the reply plays through the loudspeaker.
final class LiveAudioEngine: LiveAudioIO {
    var onMicrophoneAudio: (@Sendable (Data) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onInterrupted: (() -> Void)?

    private let engine = AVAudioEngine()
    private var observers: [NSObjectProtocol] = []
    private let player = AVAudioPlayerNode()
    private var playbackFormat: AVAudioFormat?
    private var outputSampleRate = 24_000.0
    private var isRunning = false
    private var usesMicrophone = false
    private var hasMicrophoneTap = false
    private var generation = 0
    private var pendingBuffers = 0
    private var queueEndFrame: AVAudioFramePosition = 0

    /// Mouth levels are measured over windows this long (seconds).
    static let lipSyncStep: TimeInterval = 0.02

    var isPlaying: Bool {
        pendingBuffers > 0
    }

    func start(inputSampleRate: Double, outputSampleRate: Double, microphone: Bool) throws {
        self.outputSampleRate = outputSampleRate
        if microphone {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } else {
            try ScowldAudioSession.activatePlayback()
        }

        if microphone {
            // Voice processing must be on before the engine is configured and started.
            usesMicrophone = true
            try engine.inputNode.setVoiceProcessingEnabled(true)
        }

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputSampleRate, channels: 1, interleaved: false) else {
            throw LiveAudioError.microphoneUnavailable
        }
        playbackFormat = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        if microphone {
            try installMicrophoneTap(sampleRate: inputSampleRate)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        observeInterruptions()
        logger.info("[LiveAudio] Started (microphone: \(microphone))")
    }

    func play(_ pcm16: Data) -> LipSyncChunk? {
        // The player throws (an Objective-C exception) if the engine has stopped.
        guard isRunning, engine.isRunning, let format = playbackFormat else { return nil }
        let frameCount = pcm16.count / 2
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        pcm16.withUnsafeBytes { raw in
            for index in 0..<frameCount {
                let value = raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
                samples[index] = Float(Int16(littleEndian: value)) / 32_768
            }
        }

        let levels = Self.lipSyncLevels(samples, count: frameCount, sampleRate: outputSampleRate)
        let now = currentFrame()
        let start = max(now, queueEndFrame)
        queueEndFrame = start + AVAudioFramePosition(frameCount)
        pendingBuffers += 1

        let scheduledGeneration = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.bufferFinished(generation: scheduledGeneration)
                }
            }
        }
        if !player.isPlaying {
            player.play()
        }

        return LipSyncChunk(
            delay: Double(start - now) / outputSampleRate,
            step: Self.lipSyncStep,
            levels: levels
        )
    }

    var playbackPosition: TimeInterval {
        Double(currentFrame()) / outputSampleRate
    }

    var scheduledEnd: TimeInterval {
        Double(max(currentFrame(), queueEndFrame)) / outputSampleRate
    }

    func stopPlayback() {
        generation += 1
        pendingBuffers = 0
        queueEndFrame = 0
        player.stop()
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if engine.isRunning {
            stopPlayback()
        } else {
            generation += 1
            pendingBuffers = 0
            queueEndFrame = 0
        }
        // The input node is only touched if this engine used the microphone:
        // creating it would start microphone use.
        if hasMicrophoneTap {
            engine.inputNode.removeTap(onBus: 0)
            hasMicrophoneTap = false
        }
        if engine.isRunning {
            engine.stop()
        }
        if usesMicrophone {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            usesMicrophone = false
        }
        isRunning = false
        onMicrophoneAudio = nil
        onPlaybackFinished = nil
        onInterrupted = nil
        // Leave the voice-chat route (lower volume, Bluetooth HFP) for normal playback.
        ScowldAudioSession.configureAmicaWebAudioPlayback()
        logger.info("[LiveAudio] Stopped")
    }

    // MARK: - Internals

    private func observeInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType.flatMap(AVAudioSession.InterruptionType.init) == .began else { return }
            MainActor.assumeIsolated {
                self?.onInterrupted?()
            }
        })
        // A route change (headphones, Bluetooth) stops the engine; restart it.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartAfterConfigurationChange()
            }
        })
    }

    private func restartAfterConfigurationChange() {
        guard isRunning, !engine.isRunning else { return }
        generation += 1
        pendingBuffers = 0
        queueEndFrame = 0
        do {
            engine.prepare()
            try engine.start()
            logger.info("[LiveAudio] Restarted after an audio route change")
        } catch {
            logger.error("[LiveAudio] Couldn't restart: \(error.localizedDescription, privacy: .public)")
            onInterrupted?()
        }
    }

    private func bufferFinished(generation finishedGeneration: Int) {
        guard finishedGeneration == generation, pendingBuffers > 0 else { return }
        pendingBuffers -= 1
        if pendingBuffers == 0 {
            onPlaybackFinished?()
        }
    }

    /// The player's position in frames since it last started; 0 before it renders.
    private func currentFrame() -> AVAudioFramePosition {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return 0 }
        return max(0, playerTime.sampleTime)
    }

    private func installMicrophoneTap(sampleRate: Double) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw LiveAudioError.microphoneUnavailable
        }
        // Voice processing can deliver more than one channel; the provider wants mono.
        converter.downmix = true
        let sink = onMicrophoneAudio
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat, block: Self.microphoneTap(converter: converter, targetFormat: targetFormat, sink: sink))
        hasMicrophoneTap = true
    }

    /// Built outside the main actor: the tap runs on an audio thread.
    nonisolated private static func microphoneTap(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        sink: (@Sendable (Data) -> Void)?
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let sink, let data = convert(buffer, with: converter, to: targetFormat) else { return }
            sink(data)
        }
    }

    nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> Data? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let channel = output.int16ChannelData?[0] else { return nil }
        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    /// The loudest sample in each lip-sync window, as the avatar's own analyser measures it.
    nonisolated static func lipSyncLevels(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Double) -> [Float] {
        let window = max(1, Int(sampleRate * lipSyncStep))
        return stride(from: 0, to: count, by: window).map { start in
            var peak: Float = 0
            for index in start..<min(start + window, count) {
                peak = max(peak, abs(samples[index]))
            }
            return peak
        }
    }
}
