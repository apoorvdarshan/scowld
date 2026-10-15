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
                "gpt-6-luna",
                "gpt-6.1-sol",
                "gpt-6-astra",
                "gpt-5.6-luna",
                "gpt-5.6-terra",
                "gpt-5.6-sol",
                "gpt-5.5",
                "gpt-5.4-mini",
            ]
        case .claude:
            [
                "claude-sonnet-5-5",
                "claude-opus-5-5",
                "claude-haiku-5-5",
                "claude-fable-5-1",
            ]
        case .ollama:
            ["gemma4:e4b", "gemma4:e2b", "qwen3.5:4b", "ministral-3:8b", "gpt-oss:20b", "llama3.2"]
        case .groq:
            [
                "openai/gpt-oss-20b",
                "openai/gpt-oss-120b",
                "qwen/qwen3.8-27b",
            ]
        case .openRouter:
            [
                "openrouter/auto",
                "anthropic/claude-sonnet-5.5",
                "anthropic/claude-haiku-5.5",
                "openai/gpt-6-luna",
                "google/gemini-3.8-flash",
                "google/gemini-3.5-flash-lite",
                "x-ai/grok-4.3",
                "deepseek/deepseek-v4.1-flash",
                "qwen/qwen3.8-flash",
                "moonshotai/kimi-k3",
            ]
        case .xai:
            [
                "grok-4.3",
                "grok-4.20-non-reasoning",
                "grok-4.20-reasoning",
                "grok-4.5",
                "grok-4.6",
                "grok-4.7",
            ]
        case .togetherAI:
            [
                "Qwen/Qwen3.8-Flash",
                "meta-models/Muse-Glimmer-30B",
                "zai-org/GLM-5.3-Flash",
                "deepseek-ai/DeepSeek-V4.1-Flash",
                "openai/gpt-oss-120b",
                "Qwen/Qwen3.7-Plus",
                "moonshotai/Kimi-K3",
                "zai-org/GLM-5.3",
                "deepseek-ai/DeepSeek-V4-Pro-0813",
            ]
        case .huggingFace:
            [
                "openai/gpt-oss-20b",
                "openai/gpt-oss-120b",
                "Qwen/Qwen3.8-27B",
                "zai-org/GLM-5.3-Flash",
                "google/gemma-4-26B-A4B-it",
                "meta-models/Muse-Glimmer-30B",
                "deepseek-ai/DeepSeek-V4.1-Flash",
                "meta-llama/Llama-3.3-70B-Instruct",
            ]
        case .veniceAI:
            [
                "qwen-3-8-flash",
                "deepseek-v4-1-flash",
                "z-ai-glm-5-3-flash",
                "claude-haiku-5-5",
                "openai-gpt-6-luna",
                "claude-sonnet-5-5",
                "grok-4-7",
                "openai-gpt-61-sol",
                "venice-uncensored-1-2",
            ]
        case .moonshot:
            [
                "kimi-k2.6",
                "kimi-k3",
            ]
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: HostedServiceConfig.defaultGeminiModel
        case .openai: "gpt-6-luna"
        case .claude: "claude-sonnet-5-5"
        case .ollama: "gemma4:e4b"
        case .groq: "openai/gpt-oss-20b"
        case .openRouter: "openrouter/auto"
        case .xai: "grok-4.3"
        case .togetherAI: "Qwen/Qwen3.8-Flash"
        case .huggingFace: "openai/gpt-oss-20b"
        case .veniceAI: "qwen-3-8-flash"
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

    var modelDefaultsKey: String {
        "com.scowld.ai.model.\(rawValue)"
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

    /// Request fields for faster spoken replies on OpenAI-compatible providers.
    func extraRequestFields(for model: String) -> [String: any Sendable] {
        switch (self, model) {
        // Kimi K2.6 thinks by default; Kimi K3 always does, at max effort unless told.
        case (.moonshot, "kimi-k2.6"): ["thinking": ["type": "disabled"]]
        case (.moonshot, "kimi-k3"): ["reasoning_effort": "low"]
        default: [:]
        }
    }

    /// Model IDs this app offered before that the provider has retired, deprecated or
    /// replaced in the same line, mapped to the current model. A saved selection of one
    /// moves to the replacement (see `HostedServiceConfig.selectedModel(for:)`). Older
    /// IDs that still work and have no same-line successor are left as custom models.
    var retiredModels: [String: String] {
        switch self {
        case .gemini:
            [
                "gemini-3-flash-preview": "gemini-3.6-flash",       // legacy preview
                "gemini-3.5-flash": "gemini-3.6-flash",             // redirected by Google
                "gemini-3.7-flash": "gemini-3.8-flash",             // redirected by Google
                "gemini-3.1-flash-lite-preview": "gemini-3.1-flash-lite", // shut down 2026-05-25
                "gemini-3-pro-preview": "gemini-4-argon",           // shut down 2026-03-09
                "gemini-2.0-flash": "gemini-3.5-flash-lite",        // shut down 2026-06-01
                "gemini-2.0-flash-lite": "gemini-3.5-flash-lite",   // shut down 2026-06-01
            ]
        case .openai:
            [
                "gpt-4.1-nano": "gpt-6-luna",   // shuts down 2026-10-23
                "gpt-4.1-mini": "gpt-6-luna",   // shuts down 2027-01-14
                "gpt-4.1": "gpt-6-luna",
                "gpt-4o": "gpt-6-luna",
                "gpt-4o-mini": "gpt-6-luna",
                "gpt-5.4-nano": "gpt-6-luna",   // shuts down 2027-04-01
                "gpt-5.4": "gpt-6.1-sol",
            ]
        case .claude:
            [
                "claude-opus-4-1-20250805": "claude-opus-5-5",   // retired 2026-08-05
                "claude-sonnet-4-20250514": "claude-sonnet-5-5", // retired 2026-06-15
                "claude-opus-4-7": "claude-opus-5-5",
                "claude-sonnet-4-6": "claude-sonnet-5-5",
                "claude-haiku-4-5-20251001": "claude-haiku-5-5",
                "claude-haiku-4-5": "claude-haiku-5-5",
            ]
        case .ollama:
            [:] // local models keep working once pulled
        case .groq:
            [
                "llama-3.1-8b-instant": "openai/gpt-oss-20b",                       // shut down 2026-08-16
                "llama-3.3-70b-versatile": "openai/gpt-oss-120b",                   // shut down 2026-08-16
                "qwen/qwen3-32b": "openai/gpt-oss-120b",                            // shut down 2026-07-17
                "meta-llama/llama-4-scout-17b-16e-instruct": "openai/gpt-oss-120b", // shut down 2026-07-17
                "meta-llama/llama-4-maverick-17b-128e-instruct": "openai/gpt-oss-120b", // shut down 2026-03-09
                "moonshotai/kimi-k2-instruct-0905": "openai/gpt-oss-120b",          // shut down 2026-04-15
                "groq/compound": "openai/gpt-oss-120b",                             // shut down 2026-09-21
                "groq/compound-mini": "openai/gpt-oss-20b",                         // shut down 2026-09-21
            ]
        case .openRouter:
            [
                "anthropic/claude-sonnet-4.6": "anthropic/claude-sonnet-5.5",
                "google/gemini-3.1-flash-lite": "google/gemini-3.5-flash-lite",
            ]
        case .xai:
            [
                "grok-4-1-fast-reasoning": "grok-4.3",     // retired 2026-05-15
                "grok-4-1-fast-non-reasoning": "grok-4.3", // retired 2026-05-15
                "grok-4.20-multi-agent": "grok-4.20-reasoning", // not on Chat Completions
                "grok-4.20": "grok-4.20-reasoning",        // same model, explicit name
            ]
        case .togetherAI:
            [
                "meta-llama/Llama-3.3-70B-Instruct-Turbo": "meta-models/Muse-Glimmer-30B", // removed 2026-10-22
                "moonshotai/Kimi-K2.6": "moonshotai/Kimi-K3",   // removed 2026-08-19
                "moonshotai/Kimi-K2.5": "moonshotai/Kimi-K3",   // removed 2026-05-21
                "openai/gpt-oss-20b": "Qwen/Qwen3.8-Flash",     // removed 2026-09-15
                "deepseek-ai/DeepSeek-V4-Pro": "deepseek-ai/DeepSeek-V4-Pro-0813", // removed 2026-08-27
                "zai-org/GLM-5.1": "zai-org/GLM-5.3",           // removed 2026-07-10
                "Qwen/Qwen3.6-Plus": "Qwen/Qwen3.7-Plus",
            ]
        case .huggingFace:
            [
                // Pinned providers dropped two of these; no suffix lets the router pick.
                "openai/gpt-oss-20b:fireworks-ai": "openai/gpt-oss-20b",
                "openai/gpt-oss-120b:fireworks-ai": "openai/gpt-oss-120b",
                "Qwen/Qwen3-Coder-30B-A3B-Instruct:novita": "Qwen/Qwen3.8-27B",
                "deepseek-ai/DeepSeek-R1:novita": "deepseek-ai/DeepSeek-V4.1-Flash",
                "meta-llama/Llama-3.3-70B-Instruct:novita": "meta-llama/Llama-3.3-70B-Instruct",
            ]
        case .veniceAI:
            [
                "qwen-3-6-plus": "qwen-3-8-flash", // now served as "Qwen 3.6 Plus Uncensored"
                "openai-gpt-55": "openai-gpt-61-sol",
                "openai-gpt-54-mini": "openai-gpt-6-luna",
                "claude-sonnet-4-6": "claude-sonnet-5-5",
                "deepseek-v4-flash": "deepseek-v4-1-flash",
            ]
        case .moonshot:
            [
                "kimi-k2.5": "kimi-k2.6",              // discontinued 2026-08-31
                "moonshot-v1-8k": "kimi-k2.6",         // discontinued 2026-08-31
                "moonshot-v1-32k": "kimi-k2.6",
                "moonshot-v1-128k": "kimi-k2.6",
                "kimi-k2-thinking": "kimi-k2.6",       // discontinued 2026-05-25
                "kimi-k2-thinking-turbo": "kimi-k2.6",
                "kimi-k2-turbo-preview": "kimi-k2.6",
                "kimi-k2-0905-preview": "kimi-k2.6",
            ]
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

// MARK: - Text-to-Speech Configuration

enum TTSBackend: String, CaseIterable, Codable, Sendable {
    case elevenLabs = "elevenlabs"
    case openAI = "openai_tts"

    var displayName: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI"
        }
    }

    var keychainKey: String {
        switch self {
        case .elevenLabs: "com.scowld.tts.\(rawValue)"
        // OpenAI TTS reuses the OpenAI chat provider key (one key for chat + speech).
        case .openAI: AIProvider.openai.keychainKey
        }
    }

    var modelDefaultsKey: String {
        "com.scowld.tts.model.\(rawValue)"
    }

    var availableModels: [String] {
        switch self {
        case .elevenLabs:
            [
                "eleven_flash_v2_5",
                "eleven_multilingual_v2",
                "eleven_v4",
                "eleven_v3",
                "eleven_flash_v2",
            ]
        case .openAI:
            // Realtime models (see OpenAIRealtimeSpeaker). gpt-4o-mini-tts stays on the
            // speech endpoint until that shuts down.
            ["gpt-realtime-2.1-mini", "gpt-realtime-2.1"]
                + (Self.now() < Self.openAISpeechEndpointShutdown ? ["gpt-4o-mini-tts"] : [])
        }
    }

    var defaultModel: String {
        switch self {
        case .elevenLabs: HostedServiceConfig.defaultElevenLabsModel
        case .openAI: "gpt-realtime-2.1-mini"
        }
    }

    /// OpenAI shuts down every `/v1/audio/speech` model (tts-1, tts-1-hd, gpt-4o-mini-tts)
    /// on 2027-01-06; the Realtime API replaces it.
    static let openAISpeechEndpointShutdown = Date(timeIntervalSince1970: 1_799_193_600)
    /// The clock the catalogue reads; tests move it.
    nonisolated(unsafe) static var now: () -> Date = Date.init

    static func usesOpenAIRealtime(_ model: String) -> Bool {
        model.hasPrefix("gpt-realtime")
    }

    /// Voices the Realtime models offer; fable, nova and onyx exist only on the speech endpoint.
    nonisolated static let openAIRealtimeVoices = ["marin", "cedar", "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse"]

    static func openAIVoices(for model: String) -> [String] {
        usesOpenAIRealtime(model) ? openAIRealtimeVoices : TTSBackend.openAI.voiceOptions
    }

    /// The closest Realtime voice for a voice saved for the speech endpoint.
    nonisolated static func openAIRealtimeVoice(for voice: String) -> String {
        if openAIRealtimeVoices.contains(voice) { return voice }
        return ["onyx", "fable"].contains(voice) ? "cedar" : "marin"
    }

    /// Fixed built-in voices exposed by the provider (OpenAI). ElevenLabs uses the
    /// named/custom voice library instead, so it returns an empty list here.
    var voiceOptions: [String] {
        switch self {
        case .elevenLabs: []
        case .openAI:
            ["marin", "cedar", "alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse"]
        }
    }

    /// Retired or deprecated TTS models this app offered, mapped to their replacement.
    var retiredModels: [String: String] {
        switch self {
        case .elevenLabs:
            // ElevenLabs: Flash is equivalent to Turbo with lower latency.
            ["eleven_turbo_v2_5": "eleven_flash_v2_5", "eleven_turbo_v2": "eleven_flash_v2"]
        case .openAI:
            // The speech endpoint's models shut down 2027-01-06; tts-1 also lacks the newer voices.
            ["tts-1": "gpt-realtime-2.1-mini", "tts-1-hd": "gpt-realtime-2.1-mini"]
                .merging(Self.now() < Self.openAISpeechEndpointShutdown ? [:] : ["gpt-4o-mini-tts": "gpt-realtime-2.1-mini"]) { $1 }
        }
    }

    static func selectedModel(for backend: TTSBackend) -> String {
        let saved = UserDefaults.standard.string(forKey: backend.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let replacement = backend.retiredModels[saved] {
            // A model the provider has retired or deprecated moves to its successor.
            UserDefaults.standard.set(replacement, forKey: backend.modelDefaultsKey)
            return replacement
        }
        if !saved.isEmpty {
            return saved
        }
        return backend.defaultModel
    }
}
