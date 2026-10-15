import AVFoundation
import Speech

/// Microphone access (live conversations) and on-device speech recognition (only
/// for the hands-free wake word).
enum VoicePermissions {
    static var microphoneGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static var microphoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    static var speechRecognitionGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Asks for whatever hasn't been decided yet and reports both permissions.
    static func request() async -> (microphone: Bool, speechRecognition: Bool) {
        let microphone = await AVAudioApplication.requestRecordPermission()
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return (microphone, speech)
    }
}
