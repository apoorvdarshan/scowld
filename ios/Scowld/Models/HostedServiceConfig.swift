import Foundation

// MARK: - Local Provider Configuration

enum HostedServiceConfig {
    static let serviceLanguageDefaultsKey = "scowld_service_language"
    static let autoLanguageID = "__auto_language__"
    static let deviceLanguageID = "__device_language__"
    static let providerDefaultsKey = "selectedProvider"

    static func applyBYOKDefaults() {
        LegacySettingsCleanup.runOnce()
        let defaults = UserDefaults.standard
        let provider = selectedProvider()
        defaults.set(provider.rawValue, forKey: providerDefaultsKey)
        defaults.set(selectedModel(for: provider), forKey: provider.modelDefaultsKey)
        defaults.set(selectedVoice(for: provider), forKey: provider.voiceDefaultsKey)
    }

    /// The saved live provider. A provider this version no longer offers (Claude,
    /// Groq, Ollama and the other text-only providers) falls back to Gemini.
    static func selectedProvider() -> AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: providerDefaultsKey) ?? "") ?? .gemini
    }

    static func selectedModel(for provider: AIProvider) -> String {
        let saved = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let replacement = provider.retiredModels[saved] {
            // A model the provider has retired or deprecated moves to its successor.
            UserDefaults.standard.set(replacement, forKey: provider.modelDefaultsKey)
            return replacement
        }
        return saved.isEmpty ? provider.defaultModel : saved
    }

    /// The saved voice, if the provider offers it; otherwise its default voice.
    static func selectedVoice(for provider: AIProvider) -> String {
        let saved = UserDefaults.standard.string(forKey: provider.voiceDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return provider.voices.contains { $0.id == saved } ? saved : provider.defaultVoice
    }

    static func selectedServiceLanguageID() -> String {
        let saved = UserDefaults.standard.string(forKey: serviceLanguageDefaultsKey) ?? deviceLanguageID
        if saved == autoLanguageID || saved == deviceLanguageID {
            return deviceLanguageID
        }
        return ScowldLanguageLibrary.option(for: saved) == nil ? deviceLanguageID : saved
    }

    static func selectedServiceLanguageCode() -> String? {
        serviceLanguageCode(for: selectedServiceLanguageID())
    }

    static func serviceLanguageCode(for selectionID: String) -> String? {
        switch selectionID {
        case autoLanguageID:
            return nil
        case deviceLanguageID:
            return currentDeviceLanguageCode()
        default:
            return ScowldLanguageLibrary.option(for: selectionID)?.code
        }
    }

    static func currentDeviceLanguageCode() -> String? {
        guard let preferred = Locale.preferredLanguages.first else { return nil }
        let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") {
            return "zh-TW"
        }
        if normalized.hasPrefix("fil") {
            return "tl"
        }

        let code = preferred
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { String($0).lowercased() } ?? ""
        return ScowldLanguageLibrary.option(for: code) == nil ? nil : code
    }

    static func currentDeviceLanguageName() -> String {
        guard let preferred = Locale.preferredLanguages.first else {
            return NSLocalizedString("Unknown", comment: "Unknown language fallback")
        }
        return Locale.current.localizedString(forIdentifier: preferred) ?? preferred
    }
}

struct ScowldLanguageOption: Identifiable, Hashable {
    var id: String { code }
    let name: String
    let code: String
}

enum ScowldLanguageLibrary {
    static let options: [ScowldLanguageOption] = [
        ScowldLanguageOption(name: "Arabic", code: "ar"),
        ScowldLanguageOption(name: "Chinese Simplified", code: "zh"),
        ScowldLanguageOption(name: "Chinese Traditional", code: "zh-TW"),
        ScowldLanguageOption(name: "Dutch", code: "nl"),
        ScowldLanguageOption(name: "English", code: "en"),
        ScowldLanguageOption(name: "Filipino", code: "tl"),
        ScowldLanguageOption(name: "French", code: "fr"),
        ScowldLanguageOption(name: "German", code: "de"),
        ScowldLanguageOption(name: "Hindi", code: "hi"),
        ScowldLanguageOption(name: "Indonesian", code: "id"),
        ScowldLanguageOption(name: "Italian", code: "it"),
        ScowldLanguageOption(name: "Japanese", code: "ja"),
        ScowldLanguageOption(name: "Korean", code: "ko"),
        ScowldLanguageOption(name: "Polish", code: "pl"),
        ScowldLanguageOption(name: "Portuguese", code: "pt"),
        ScowldLanguageOption(name: "Russian", code: "ru"),
        ScowldLanguageOption(name: "Spanish", code: "es"),
        ScowldLanguageOption(name: "Swedish", code: "sv"),
        ScowldLanguageOption(name: "Thai", code: "th"),
        ScowldLanguageOption(name: "Turkish", code: "tr"),
        ScowldLanguageOption(name: "Ukrainian", code: "uk"),
        ScowldLanguageOption(name: "Vietnamese", code: "vi"),
    ]

    static func option(for code: String) -> ScowldLanguageOption? {
        options.first { $0.code == code }
    }
}

/// Removes what earlier versions stored for the speech-to-text, text-to-speech and
/// text-only chat providers this version dropped, including their API keys.
enum LegacySettingsCleanup {
    static let doneDefaultsKey = "legacy_voice_pipeline_cleaned"

    static let legacyKeychainKeys = [
        "com.scowld.apikey.claude",
        "com.scowld.apikey.ollama",
        "com.scowld.apikey.groq",
        "com.scowld.apikey.openRouter",
        "com.scowld.apikey.togetherAI",
        "com.scowld.apikey.huggingFace",
        "com.scowld.apikey.veniceAI",
        "com.scowld.apikey.moonshot",
        "com.scowld.ollama.url",
        "com.scowld.tts.elevenlabs",
        "com.scowld.stt.openai_whisper",
        "com.scowld.stt.groq_whisper",
        "com.scowld.stt.deepgram",
        "com.scowld.stt.assemblyai",
        "com.scowld.stt.google_cloud_stt",
    ]

    static let legacyDefaultsKeys = [
        "selectedModel",
        "amica_tts_backend",
        "amica_stt_backend",
        "amica_elevenlabs_voiceid",
        "amica_elevenlabs_model",
        "amica_openai_tts_voice",
    ]

    /// Legacy defaults keys with a per-provider suffix (models of old chat, STT and TTS providers).
    static let legacyDefaultsPrefixes = [
        "com.scowld.ai.model.",
        "com.scowld.tts.model.",
        "com.scowld.stt.model.",
    ]

    static func runOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneDefaultsKey) else { return }
        for key in legacyKeychainKeys {
            KeychainManager.delete(key: key)
        }
        for key in legacyDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
        where legacyDefaultsPrefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: doneDefaultsKey)
    }
}
