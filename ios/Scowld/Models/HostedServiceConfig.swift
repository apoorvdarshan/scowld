import Foundation

// MARK: - Hosted Provider Configuration

enum HostedServiceConfig {
    static let baseURLString = "https://scowld.xyz"

    static let defaultGeminiModel = "gemini-3.1-pro-preview"
    static let geminiFallbackModels = [
        "gemini-3.1-pro-preview",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
    ]

    static let defaultElevenLabsVoiceID = "mHX7OoPk2G45VMAuinIt"
    static let defaultElevenLabsModel = "eleven_flash_v2_5"
    static let defaultDeepgramModel = "nova-3"

    static var chatURL: URL {
        URL(string: "\(baseURLString)/api/chat")!
    }

    static var elevenLabsTTSURL: URL {
        URL(string: "\(baseURLString)/api/tts/elevenlabs")!
    }

    static func deepgramSTTURL(model: String) -> URL {
        var components = URLComponents(string: "\(baseURLString)/api/stt/deepgram")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model.isEmpty ? defaultDeepgramModel : model)
        ]
        return components.url!
    }

    static func applyManagedDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(AIProvider.gemini.rawValue, forKey: "selectedProvider")
        defaults.set(defaultGeminiModel, forKey: "selectedModel")
        defaults.set("elevenlabs", forKey: "amica_tts_backend")
        defaults.set(defaultElevenLabsModel, forKey: "amica_elevenlabs_model")
        defaults.set(STTBackend.deepgram.rawValue, forKey: "amica_stt_backend")
        defaults.set(defaultDeepgramModel, forKey: STTBackend.deepgram.modelDefaultsKey)

        let voiceID = defaults.string(forKey: "amica_elevenlabs_voiceid")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if voiceID.isEmpty {
            defaults.set(defaultElevenLabsVoiceID, forKey: "amica_elevenlabs_voiceid")
        }
    }

    static func selectedElevenLabsVoiceID() -> String {
        let value = UserDefaults.standard.string(forKey: "amica_elevenlabs_voiceid")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultElevenLabsVoiceID : value
    }
}

struct ScowldVoiceOption: Identifiable, Hashable {
    var id: String { voiceID }
    let name: String
    let voiceID: String
    let description: String
    let previewText: String
}

enum ScowldVoiceLibrary {
    static let customID = "__custom_voice_id__"
    static let defaultPreviewText = "Hi, I'm Scowld. Tell me if this voice fits the avatar."

    static let presetVoices: [ScowldVoiceOption] = [
        ScowldVoiceOption(
            name: "Sarah",
            voiceID: HostedServiceConfig.defaultElevenLabsVoiceID,
            description: "Default bright companion voice",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Aria",
            voiceID: "9BWtsMINqrJLrRacOk9x",
            description: "Clear, lively, and youthful",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Bella",
            voiceID: "EXAVITQu4vr4xnSDxMaL",
            description: "Soft and expressive",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Domi",
            voiceID: "AZnzlk1XvdvUeBnXmlld",
            description: "Energetic and playful",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Dorothy",
            voiceID: "ThT5KcBeYPX3keUQqHPh",
            description: "Cute and gentle",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Elli",
            voiceID: "MF3mGyEYCl7XYWbV9V6O",
            description: "Young, bright, and animated",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Grace",
            voiceID: "oWAxZDx7w5VEj9dCyTzz",
            description: "Warm and friendly",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Jessica",
            voiceID: "cgSgspJ2msm6clMCkdW9",
            description: "Upbeat and modern",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Lily",
            voiceID: "pFZP5JQG7iQjIQuC4Bku",
            description: "Sweet and polished",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Matilda",
            voiceID: "XrExE9yKIg1WjnnlVkGX",
            description: "Soft-spoken and calm",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Nicole",
            voiceID: "piTKgcLEGmPE4e6mEKli",
            description: "Gentle and natural",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Rachel",
            voiceID: "21m00Tcm4TlvDq8ikWAM",
            description: "Classic, clear narration",
            previewText: defaultPreviewText
        ),
    ]

    static func pickerID(for voiceID: String) -> String {
        presetVoices.contains(where: { $0.voiceID == voiceID }) ? voiceID : customID
    }

    static func voiceID(for pickerID: String, customVoiceID: String) -> String {
        if pickerID == customID {
            let trimmed = customVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? HostedServiceConfig.defaultElevenLabsVoiceID : trimmed
        }
        return pickerID
    }

    static func option(for voiceID: String) -> ScowldVoiceOption? {
        presetVoices.first { $0.voiceID == voiceID }
    }
}
