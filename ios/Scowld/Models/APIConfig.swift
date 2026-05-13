import Foundation

// MARK: - AI Provider Configuration

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case gemini
    case openai
    case claude
    case ollama
    case groq
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
        case .groq: "Groq"
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
        case .gemini:
            HostedServiceConfig.geminiFallbackModels
        case .openai:
            [
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
                "gpt-4o",
                "gpt-4o-mini",
            ]
        case .claude:
            [
                "claude-opus-4-7",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001",
                "claude-opus-4-1-20250805",
                "claude-sonnet-4-20250514",
            ]
        case .ollama:
            ["llama3.3", "llama3.2", "qwen3", "gemma3", "phi4", "mistral", "deepseek-r1"]
        case .groq:
            [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "openai/gpt-oss-20b",
                "openai/gpt-oss-120b",
                "meta-llama/llama-4-scout-17b-16e-instruct",
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "qwen/qwen3-32b",
                "moonshotai/kimi-k2-instruct-0905",
                "groq/compound-mini",
                "groq/compound",
            ]
        case .openRouter:
            [
                "openrouter/auto",
                "google/gemini-3.1-pro-preview",
                "google/gemini-3.1-flash-lite",
                "openai/gpt-5.5",
                "openai/gpt-5.4-mini",
                "anthropic/claude-sonnet-4.6",
                "x-ai/grok-4.3",
                "deepseek/deepseek-v4-flash",
                "qwen/qwen3.6-flash",
                "moonshotai/kimi-k2.6",
            ]
        case .xai:
            [
                "grok-4.3",
                "grok-4.20",
                "grok-4.20-multi-agent",
                "grok-4-1-fast-reasoning",
                "grok-4-1-fast-non-reasoning",
            ]
        case .togetherAI:
            [
                "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                "Qwen/Qwen3.6-Plus",
                "moonshotai/Kimi-K2.6",
                "moonshotai/Kimi-K2.5",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
                "deepseek-ai/DeepSeek-V4-Pro",
                "zai-org/GLM-5.1",
            ]
        case .huggingFace:
            [
                "openai/gpt-oss-20b:fireworks-ai",
                "openai/gpt-oss-120b:fireworks-ai",
                "Qwen/Qwen3-Coder-30B-A3B-Instruct:novita",
                "deepseek-ai/DeepSeek-R1:novita",
                "meta-llama/Llama-3.3-70B-Instruct:novita",
            ]
        case .veniceAI:
            [
                "qwen-3-6-plus",
                "venice-uncensored-1-2",
                "gemini-3-1-pro-preview",
                "grok-4-3",
                "claude-sonnet-4-6",
                "openai-gpt-55",
                "openai-gpt-54-mini",
                "kimi-k2-6",
                "deepseek-v4-flash",
                "llama-3.3-70b",
            ]
        case .moonshot:
            [
                "kimi-k2.6",
                "kimi-k2.5",
                "kimi-k2-thinking",
                "kimi-k2-thinking-turbo",
                "kimi-k2-turbo-preview",
                "kimi-k2-0905-preview",
                "moonshot-v1-8k",
                "moonshot-v1-32k",
                "moonshot-v1-128k",
            ]
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: HostedServiceConfig.defaultGeminiModel
        case .openai: "gpt-5.4-mini"
        case .claude: "claude-sonnet-4-6"
        case .ollama: "llama3.2"
        case .groq: "llama-3.1-8b-instant"
        case .openRouter: "openrouter/auto"
        case .xai: "grok-4.3"
        case .togetherAI: "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .huggingFace: "openai/gpt-oss-20b:fireworks-ai"
        case .veniceAI: "qwen-3-6-plus"
        case .moonshot: "kimi-k2.6"
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
        case .gemini, .openai, .claude, .openRouter, .xai, .togetherAI, .moonshot: true
        case .huggingFace: true // some models
        case .ollama, .groq, .veniceAI: false
        }
    }

    /// Base URL for OpenAI-compatible providers
    var baseURL: String? {
        switch self {
        case .groq: "https://api.groq.com/openai/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .xai: "https://api.x.ai/v1"
        case .togetherAI: "https://api.together.xyz/v1"
        case .huggingFace: "https://router.huggingface.co/v1"
        case .veniceAI: "https://api.venice.ai/api/v1"
        case .moonshot: "https://api.moonshot.ai/v1"
        default: nil
        }
    }

    /// Some providers reject custom sampling values for their newest models.
    var includesSamplingTemperature: Bool {
        switch self {
        case .moonshot: false
        default: true
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
