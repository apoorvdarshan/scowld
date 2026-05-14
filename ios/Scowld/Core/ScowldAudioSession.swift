import AVFoundation
import os

private let audioSessionLogger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "AudioSession")

enum ScowldAudioSession {
    static func configureAmicaWebAudioPlayback() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try session.setActive(true)
            audioSessionLogger.info("[Audio] Routed Amica WebAudio through playback")
        } catch {
            audioSessionLogger.error("[Audio] Failed to route Amica WebAudio: \(error.localizedDescription)")
        }
    }
}
