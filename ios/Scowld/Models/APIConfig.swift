import Foundation

// MARK: - Live voice providers

/// The speech-to-speech providers Scowld talks to. Each one hears the microphone
/// directly and answers in its own voice over a single live connection, so there
/// is no separate speech-to-text or text-to-speech step.
nonisolated enum AIProvider: String, CaseIterable, Codable, Sendable {
    case gemini
    case openai
    case xai

    var displayName: String {
        switch self {
        case .gemini: "Google Gemini Live"
        case .openai: "OpenAI Realtime"
        case .xai: "xAI Grok Voice"
        }
    }

    /// The provider's name alone, for messages such as "Add your Gemini API key".
    var shortName: String {
        switch self {
        case .gemini: "Gemini"
        case .openai: "OpenAI"
        case .xai: "xAI"
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini:
            ["gemini-3.8-live", "gemini-3.8-live-extended-thinking", "gemini-3.1-flash-live-preview"]
        case .openai:
            ["gpt-realtime-2.1-mini", "gpt-realtime-2.1"]
        case .xai:
            ["grok-voice-latest", "grok-voice-3.0"]
        }
    }

    var defaultModel: String {
        availableModels[0]
    }

    /// The provider's built-in voices. Scowld cannot add voices of its own.
    var voices: [LiveVoice] {
        switch self {
        case .gemini:
            [
                LiveVoice(id: "Leda", style: "Youthful"),
                LiveVoice(id: "Aoede", style: "Breezy"),
                LiveVoice(id: "Zephyr", style: "Bright"),
                LiveVoice(id: "Achernar", style: "Soft"),
                LiveVoice(id: "Vindemiatrix", style: "Gentle"),
                LiveVoice(id: "Sulafat", style: "Warm"),
                LiveVoice(id: "Laomedeia", style: "Upbeat"),
                LiveVoice(id: "Kore", style: "Firm"),
                LiveVoice(id: "Callirrhoe", style: "Easy-going"),
                LiveVoice(id: "Despina", style: "Smooth"),
                LiveVoice(id: "Autonoe", style: "Bright"),
                LiveVoice(id: "Erinome", style: "Clear"),
                LiveVoice(id: "Pulcherrima", style: "Forward"),
                LiveVoice(id: "Gacrux", style: "Mature"),
                LiveVoice(id: "Puck", style: "Upbeat"),
                LiveVoice(id: "Fenrir", style: "Excitable"),
                LiveVoice(id: "Charon", style: "Informative"),
                LiveVoice(id: "Orus", style: "Firm"),
                LiveVoice(id: "Umbriel", style: "Easy-going"),
                LiveVoice(id: "Schedar", style: "Even"),
                LiveVoice(id: "Achird", style: "Friendly"),
                LiveVoice(id: "Sadachbia", style: "Lively"),
                LiveVoice(id: "Enceladus", style: "Breathy"),
                LiveVoice(id: "Algieba", style: "Smooth"),
                LiveVoice(id: "Algenib", style: "Gravelly"),
                LiveVoice(id: "Zubenelgenubi", style: "Casual"),
                LiveVoice(id: "Sadaltager", style: "Knowledgeable"),
                LiveVoice(id: "Iapetus", style: "Clear"),
                LiveVoice(id: "Rasalgethi", style: "Informative"),
                LiveVoice(id: "Alnilam", style: "Firm"),
            ]
        case .openai:
            [
                LiveVoice(id: "marin", style: "Natural, warm"),
                LiveVoice(id: "cedar", style: "Natural, lower"),
                LiveVoice(id: "shimmer", style: "Bright"),
                LiveVoice(id: "coral", style: "Friendly"),
                LiveVoice(id: "sage", style: "Calm"),
                LiveVoice(id: "ballad", style: "Expressive"),
                LiveVoice(id: "alloy", style: "Balanced"),
                LiveVoice(id: "verse", style: "Lively"),
                LiveVoice(id: "ash", style: "Steady"),
                LiveVoice(id: "echo", style: "Smooth"),
            ]
        case .xai:
            [
                LiveVoice(id: "ara", style: "Warm, friendly"),
                LiveVoice(id: "eve", style: "Energetic"),
                LiveVoice(id: "sal", style: "Smooth"),
                LiveVoice(id: "rex", style: "Confident"),
                LiveVoice(id: "leo", style: "Strong"),
            ]
        }
    }

    var defaultVoice: String {
        voices[0].id
    }

    /// How camera frames reach the provider while the eye is on.
    var cameraSupport: LiveCameraSupport {
        switch self {
        case .gemini: .continuous
        case .openai: .perTurn
        case .xai: .unsupported
        }
    }

    /// Keychain key for this provider's API key. These match the keys earlier
    /// versions used, so a saved Gemini, OpenAI or xAI key keeps working.
    var keychainKey: String {
        "com.scowld.apikey.\(rawValue)"
    }

    var modelDefaultsKey: String {
        "com.scowld.live.model.\(rawValue)"
    }

    var voiceDefaultsKey: String {
        "com.scowld.live.voice.\(rawValue)"
    }

    /// Where to create an API key.
    var keyURL: URL {
        switch self {
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .xai: URL(string: "https://console.x.ai")!
        }
    }

    var keyHost: String {
        keyURL.host() ?? keyURL.absoluteString
    }

    /// Model IDs this app offered before that the provider has retired, mapped to
    /// their replacement. A saved selection of one moves to the replacement (see
    /// `HostedServiceConfig.selectedModel(for:)`).
    var retiredModels: [String: String] {
        [:]
    }
}

nonisolated struct LiveVoice: Identifiable, Hashable, Sendable {
    let id: String
    let style: String

    /// Gemini voices are capitalized already; OpenAI and xAI IDs are lowercase.
    var name: String {
        id.prefix(1).uppercased() + id.dropFirst()
    }
}

nonisolated enum LiveCameraSupport: Sendable {
    /// A frame every couple of seconds while the camera is on (Gemini video input).
    case continuous
    /// The latest frame with each thing the user says.
    case perTurn
    /// The provider takes no images.
    case unsupported
}
