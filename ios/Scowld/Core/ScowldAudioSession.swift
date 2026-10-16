import AVFoundation
import os

private let audioSessionLogger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "AudioSession")

enum ScowldAudioSession {
    /// Plain playback for the companion page and voice previews. Bluetooth
    /// headphones are used automatically: `.allowBluetoothA2DP` is only valid with
    /// `.playAndRecord`, and passing it here makes iOS reject the whole category
    /// (OSStatus -50).
    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    static func configureAmicaWebAudioPlayback() {
        do {
            try activatePlayback()
            audioSessionLogger.info("[Audio] Routed Amica WebAudio through playback")
        } catch {
            audioSessionLogger.error("[Audio] Failed to route Amica WebAudio: \(error.localizedDescription)")
        }
    }
}
