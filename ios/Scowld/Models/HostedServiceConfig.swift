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
            name: "celine - cuddly, thin and soft.",
            voiceID: HostedServiceConfig.defaultElevenLabsVoiceID,
            description: "Default ElevenLabs companion voice",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Elara - Crisp Pro Narrator",
            voiceID: "AZnzlk1XvdvUeBnXmlld",
            description: "Crisp pro narrator",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Evelyn",
            voiceID: "ThT5KcBeYPX3keUQqHPh",
            description: "ElevenLabs voice",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Janet",
            voiceID: "21m00Tcm4TlvDq8ikWAM",
            description: "ElevenLabs voice",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Jessica - Playful, Bright, Warm",
            voiceID: "cgSgspJ2msm6clMCkdW9",
            description: "Playful, bright, warm",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Lily - Velvety Actress",
            voiceID: "pFZP5JQG7iQjIQuC4Bku",
            description: "Velvety actress",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Maisie - Friendly Casual Neighbor",
            voiceID: "piTKgcLEGmPE4e6mEKli",
            description: "Friendly casual neighbor",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Matilda - Knowledgable, Professional",
            voiceID: "XrExE9yKIg1WjnnlVkGX",
            description: "Knowledgeable, professional",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Peter",
            voiceID: "MF3mGyEYCl7XYWbV9V6O",
            description: "ElevenLabs voice",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Riley",
            voiceID: "oWAxZDx7w5VEj9dCyTzz",
            description: "ElevenLabs voice",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Sarah - Mature, Reassuring, Confident",
            voiceID: "EXAVITQu4vr4xnSDxMaL",
            description: "Mature, reassuring, confident",
            previewText: defaultPreviewText
        ),
        ScowldVoiceOption(
            name: "Zoe",
            voiceID: "9BWtsMINqrJLrRacOk9x",
            description: "ElevenLabs voice",
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
