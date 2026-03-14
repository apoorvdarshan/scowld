import Foundation

// MARK: - AI Provider Configuration

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case gemini
    case openai
    case claude
    case ollama

    var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openai: "OpenAI"
        case .claude: "Anthropic Claude"
        case .ollama: "Ollama (Local)"
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini: ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-2.5-flash"]
        case .openai: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-nano"]
        case .claude: ["claude-haiku-4-5-20251001", "claude-sonnet-4-6"]
        case .ollama: ["llama3.2", "mistral", "gemma2", "phi3"]
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: "gemini-2.0-flash"
        case .openai: "gpt-4o-mini"
        case .claude: "claude-haiku-4-5-20251001"
        case .ollama: "llama3.2"
        }
    }

    var requiresAPIKey: Bool {
        self != .ollama
    }

    /// Keychain key for storing this provider's API key
    var keychainKey: String {
        "com.scowld.apikey.\(rawValue)"
    }

    /// Whether this provider supports vision (image input)
    var supportsVision: Bool {
        switch self {
        case .gemini, .openai, .claude: true
        case .ollama: false
        }
    }
}

// MARK: - Ollama Configuration

enum OllamaConfig {
    static let defaultURL = "http://localhost:11434"
    static let keychainURLKey = "com.scowld.ollama.url"
}
