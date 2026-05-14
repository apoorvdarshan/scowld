import AVFoundation
import os

private let audioSessionLogger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "AudioSession")

enum ScowldAudioSession {
    static func configureAmicaWebAudioPlayback() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
            audioSessionLogger.info("[Audio] Routed Amica WebAudio through speaker")
        } catch {
            audioSessionLogger.error("[Audio] Failed to route Amica WebAudio: \(error.localizedDescription)")
        }
    }
}
