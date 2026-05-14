import Foundation

enum BundledElevenLabsVoicePreviews {
    static func url(forVoiceID voiceID: String) -> URL? {
        Bundle.main.url(forResource: voiceID, withExtension: "mp3")
            ?? Bundle.main.url(
                forResource: voiceID,
                withExtension: "mp3",
                subdirectory: "VoicePreviews"
            )
    }

    static func hasPreview(forVoiceID voiceID: String) -> Bool {
        url(forVoiceID: voiceID) != nil
    }
}
