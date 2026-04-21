import Foundation

// MARK: - AI Provider Configuration

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case gemini
    case openai
    case claude
    case ollama
    case openRouter
    case xai
    case togetherAI
    case huggingFace
    case veniceAI
    case moonshot

    var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openai: "OpenAI"
        case .claude: "Anthropic Claude"
        case .ollama: "Ollama (Local)"
        case .openRouter: "OpenRouter"
        case .xai: "xAI (Grok)"
        case .togetherAI: "Together AI"
        case .huggingFace: "Hugging Face"
        case .veniceAI: "Venice AI"
        case .moonshot: "Moonshot AI"
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash-001"]
        case .openai: ["gpt-4.1-nano", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4o"]
        case .claude: ["claude-haiku-4-5-20251001", "claude-sonnet-4-6-20250514"]
        case .ollama: ["llama3.2", "mistral", "gemma2", "phi3"]
        case .openRouter: ["openai/gpt-4o", "anthropic/claude-sonnet-4-6", "google/gemini-2.5-flash", "meta-llama/llama-3.3-70b-instruct"]
        case .xai: ["grok-3-mini", "grok-3"]
        case .togetherAI: ["meta-llama/Llama-3.3-70B-Instruct-Turbo", "mistralai/Mixtral-8x7B-Instruct-v0.1", "Qwen/Qwen2.5-72B-Instruct-Turbo"]
        case .huggingFace: ["meta-llama/Llama-3.3-70B-Instruct", "mistralai/Mixtral-8x7B-Instruct-v0.1", "Qwen/Qwen2.5-72B-Instruct"]
        case .veniceAI: ["llama-3.3-70b", "deepseek-r1-671b"]
        case .moonshot: ["kimi-k2.5", "moonshot-v1-8k"]
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: "gemini-2.5-flash"
        case .openai: "gpt-4.1-nano"
        case .claude: "claude-haiku-4-5-20251001"
        case .ollama: "llama3.2"
        case .openRouter: "openai/gpt-4o"
        case .xai: "grok-3-mini"
        case .togetherAI: "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .huggingFace: "meta-llama/Llama-3.3-70B-Instruct"
        case .veniceAI: "llama-3.3-70b"
        case .moonshot: "kimi-k2.5"
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
        case .gemini, .openai, .claude, .openRouter, .xai, .togetherAI: true
        case .huggingFace: true // some models
        case .ollama, .veniceAI, .moonshot: false
        }
    }

    /// Base URL for OpenAI-compatible providers
    var baseURL: String? {
        switch self {
        case .openRouter: "https://openrouter.ai/api/v1"
        case .xai: "https://api.x.ai/v1"
        case .togetherAI: "https://api.together.xyz/v1"
        case .huggingFace: "https://api-inference.huggingface.co/v1"
        case .veniceAI: "https://api.venice.ai/api/v1"
        case .moonshot: "https://api.moonshot.cn/v1"
        default: nil
        }
    }

    /// Whether this provider uses the OpenAI-compatible API format
    var isOpenAICompatible: Bool {
        baseURL != nil
    }
}

// MARK: - Ollama Configuration

enum OllamaConfig {
    static let defaultURL = "http://localhost:11434"
    static let keychainURLKey = "com.scowld.ollama.url"
}
