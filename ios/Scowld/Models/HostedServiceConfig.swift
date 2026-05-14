import Foundation

// MARK: - Hosted Provider Configuration

enum HostedServiceConfig {
    static let baseURLString = "https://www.scowld.xyz"
    static let serviceLanguageDefaultsKey = "scowld_service_language"
    static let autoLanguageID = "__auto_language__"
    static let deviceLanguageID = "__device_language__"

    static let fastGeminiModel = "gemini-3-flash-preview"
    static let defaultGeminiModel = fastGeminiModel
    static let geminiFallbackModels = [
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite",
        "gemini-3.1-pro-preview",
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
        var queryItems = [
            URLQueryItem(name: "model", value: model.isEmpty ? defaultDeepgramModel : model)
        ]
        if let languageCode = selectedServiceLanguageCode() {
            queryItems.append(URLQueryItem(name: "language", value: languageCode))
        } else {
            queryItems.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        components.queryItems = queryItems
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

    static func selectedServiceLanguageID() -> String {
        let saved = UserDefaults.standard.string(forKey: serviceLanguageDefaultsKey) ?? autoLanguageID
        if saved == autoLanguageID || saved == deviceLanguageID {
            return saved
        }
        return ScowldLanguageLibrary.option(for: saved) == nil ? autoLanguageID : saved
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

struct ScowldVoiceOption: Identifiable, Hashable {
    var id: String { voiceID }
    let name: String
    let voiceID: String
    let description: String
    let previewText: String
}

enum ScowldVoiceLibrary {
    static let customID = "__custom_voice_id__"
    static let defaultPreviewText = "Hi, this is the selected voice. Tell me if this voice fits the avatar."

    static let presetVoices: [ScowldVoiceOption] = [
        ScowldVoiceOption(
            name: "Celine - cuddly, thin and soft",
            voiceID: HostedServiceConfig.defaultElevenLabsVoiceID,
            description: "Realistic, soft companion voice",
            previewText: "Hi, I'm Celine. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Claire - Cute & Cheerful JP",
            voiceID: "HxuFAkkGVeQs1sDIMF5g",
            description: "Cute, cheerful Japanese voice",
            previewText: "Hi, I'm Claire. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Haru - Calm & Friendly Japanese Female",
            voiceID: "a0MsDWokG5Xsuji8g8er",
            description: "Calm, friendly Japanese female voice",
            previewText: "Hi, I'm Haru. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Hina - cute and friendly",
            voiceID: "lhTvHflPVOqgSWyuWQry",
            description: "Cute, friendly voice",
            previewText: "Hi, I'm Hina. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Jessica - Playful, Bright, Warm",
            voiceID: "cgSgspJ2msm6clMCkdW9",
            description: "Realistic, playful, bright voice",
            previewText: "Hi, I'm Jessica. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Kana - Japanese Young Female",
            voiceID: "dhGvgIx0X6G3xzSWqOye",
            description: "Young Japanese female voice",
            previewText: "Hi, I'm Kana. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Lily - Velvety Actress",
            voiceID: "pFZP5JQG7iQjIQuC4Bku",
            description: "Realistic, velvety actress voice",
            previewText: "Hi, I'm Lily. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Renren - Soft and Calm Japanese Female",
            voiceID: "RWZ1lnBIIgPBTpyCnKn2",
            description: "Soft, calm Japanese female voice",
            previewText: "Hi, I'm Renren. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Sara - Calm, Soothing & Multilingual Japanese Female",
            voiceID: "l7ME2dcqpdvq6E8sCS24",
            description: "Calm, soothing Japanese female voice",
            previewText: "Hi, I'm Sara. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Sarah - Mature, Reassuring, Confident",
            voiceID: "EXAVITQu4vr4xnSDxMaL",
            description: "Realistic, mature, reassuring voice",
            previewText: "Hi, I'm Sarah. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Yoko Honda - Soft female voice",
            voiceID: "0ptCJp0xgdabdcpVtCB5",
            description: "Soft Japanese female voice",
            previewText: "Hi, I'm Yoko. Tell me if this voice fits the avatar."
        ),
        ScowldVoiceOption(
            name: "Yukiko - Native Japanese female calm voice",
            voiceID: "Z5Rahxh8jMhJKEgBfCSS",
            description: "Native Japanese calm female voice",
            previewText: "Hi, I'm Yukiko. Tell me if this voice fits the avatar."
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
