import XCTest
@testable import Scowld

/// The system prompt Scowld sends with every chat request.
@MainActor
final class SystemPromptTests: XCTestCase {
    private func cleanDefaults() {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { defaults.restore() }
    }

    func testDefaultPersonalityUsesTheCharacterNameAndEmotionRules() {
        cleanDefaults()
        let prompt = SystemPromptTemplate.build(userName: nil, conversationContext: [], visionDescription: nil, characterName: "Nova")

        XCTAssertTrue(prompt.hasPrefix("You are Nova, a friendly and expressive AI assistant"))
        XCTAssertTrue(prompt.contains("[neutral], [happy], [sad], [angry], [surprised], [thinking], [concerned], [excited]"))
        XCTAssertTrue(prompt.contains("- Your name is Nova. Never say your name is Amica or anything else."))
        XCTAssertTrue(prompt.contains("Current date/time: "))
        XCTAssertFalse(prompt.contains("Previous messages from the active saved chat"))
        XCTAssertFalse(prompt.contains("through the camera:"))
        XCTAssertFalse(prompt.contains("personal AI assistant.\n"))
    }

    func testCustomPromptReplacesTheDefaultPersonality() {
        cleanDefaults()
        UserDefaults.standard.set("Speak like a pirate.", forKey: "system_prompt")
        let prompt = SystemPromptTemplate.build(userName: nil, conversationContext: [], visionDescription: nil, characterName: "Nova")
        XCTAssertTrue(prompt.hasPrefix("You are Nova. Speak like a pirate."))
        XCTAssertFalse(prompt.contains("friendly and expressive AI assistant"))
    }

    func testContextUserNameAndVisionAreIncludedWhenPresent() {
        cleanDefaults()
        let prompt = SystemPromptTemplate.build(
            userName: "Sam",
            conversationContext: ["User: I like hiking", "Nova: Noted!"],
            visionDescription: "A person holding a mug",
            characterName: "Nova"
        )
        XCTAssertTrue(prompt.contains("You are Sam's personal AI assistant."))
        XCTAssertTrue(prompt.contains("Previous messages from the active saved chat"))
        XCTAssertTrue(prompt.contains("- User: I like hiking\n- Nova: Noted!\n"))
        XCTAssertTrue(prompt.contains("What you can currently see through the camera: A person holding a mug"))
    }

    func testSelectedServiceLanguageForcesTheReplyLanguage() {
        cleanDefaults()
        UserDefaults.standard.set("ja", forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        let prompt = SystemPromptTemplate.build(userName: nil, conversationContext: [], visionDescription: nil)
        XCTAssertTrue(prompt.contains("Response language: Reply in Japanese unless the user explicitly asks for another language."))
    }

    func testDeviceLanguageModeFollowsTheSimulatorLanguage() {
        cleanDefaults()
        UserDefaults.standard.set(HostedServiceConfig.deviceLanguageID, forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        let prompt = SystemPromptTemplate.build(userName: nil, conversationContext: [], visionDescription: nil)
        if let code = HostedServiceConfig.currentDeviceLanguageCode(),
           let language = ScowldLanguageLibrary.option(for: code) {
            XCTAssertTrue(prompt.contains("Response language: Reply in \(language.name) unless"))
        } else {
            XCTAssertTrue(prompt.contains("Response language: Reply in the same language as the user's latest message."))
        }
    }

    func testContextBuilderInjectsTheActiveChat() {
        cleanDefaults()
        UserDefaults.standard.set("Iris", forKey: "character_name")
        let store = MemoryStore(inMemory: true)
        store.saveExchange(userMessage: "My cat is Miso", assistantResponse: "What a cute name!")

        let prompt = ContextBuilder(memoryStore: store).buildSystemPrompt(visionDescription: "A sunny window")
        XCTAssertTrue(prompt.hasPrefix("You are Iris"))
        XCTAssertTrue(prompt.contains("- User: My cat is Miso\n- Iris: What a cute name!\n"))
        XCTAssertTrue(prompt.contains("through the camera: A sunny window"))
    }
}

/// Provider, model, voice and language preferences.
@MainActor
final class ServiceSettingsTests: XCTestCase {
    private func cleanDefaults() {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { defaults.restore() }
    }

    func testBYOKDefaultsOnFirstLaunch() {
        cleanDefaults()
        HostedServiceConfig.applyBYOKDefaults()
        let defaults = UserDefaults.standard

        XCTAssertEqual(defaults.string(forKey: "selectedProvider"), AIProvider.gemini.rawValue)
        XCTAssertEqual(defaults.string(forKey: "selectedModel"), HostedServiceConfig.defaultGeminiModel)
        XCTAssertEqual(defaults.string(forKey: AIProvider.gemini.modelDefaultsKey), HostedServiceConfig.defaultGeminiModel)
        XCTAssertEqual(defaults.string(forKey: "amica_tts_backend"), TTSBackend.elevenLabs.rawValue)
        XCTAssertEqual(defaults.string(forKey: "amica_elevenlabs_model"), HostedServiceConfig.defaultElevenLabsModel)
        XCTAssertEqual(defaults.string(forKey: TTSBackend.openAI.modelDefaultsKey), TTSBackend.openAI.defaultModel)
        XCTAssertEqual(defaults.string(forKey: HostedServiceConfig.openAITTSVoiceDefaultsKey), "marin")
        XCTAssertEqual(defaults.string(forKey: "amica_stt_backend"), STTBackend.nativeIOS.rawValue)
        XCTAssertEqual(defaults.string(forKey: "amica_elevenlabs_voiceid"), HostedServiceConfig.defaultElevenLabsVoiceID)
        for backend in STTBackend.allCases where !backend.availableModels.isEmpty {
            XCTAssertEqual(defaults.string(forKey: backend.modelDefaultsKey), backend.defaultModel, backend.rawValue)
        }
    }

    func testBYOKDefaultsKeepTheUsersChoices() {
        cleanDefaults()
        let defaults = UserDefaults.standard
        defaults.set(AIProvider.claude.rawValue, forKey: "selectedProvider")
        defaults.set("claude-opus-5-5", forKey: AIProvider.claude.modelDefaultsKey)
        defaults.set(TTSBackend.openAI.rawValue, forKey: "amica_tts_backend")
        defaults.set(STTBackend.deepgram.rawValue, forKey: "amica_stt_backend")
        defaults.set("myVoice123", forKey: "amica_elevenlabs_voiceid")
        defaults.set("nova", forKey: HostedServiceConfig.openAITTSVoiceDefaultsKey)

        HostedServiceConfig.applyBYOKDefaults()

        XCTAssertEqual(defaults.string(forKey: "selectedProvider"), AIProvider.claude.rawValue)
        XCTAssertEqual(defaults.string(forKey: "selectedModel"), "claude-opus-5-5")
        XCTAssertEqual(defaults.string(forKey: "amica_tts_backend"), TTSBackend.openAI.rawValue)
        XCTAssertEqual(defaults.string(forKey: "amica_stt_backend"), STTBackend.deepgram.rawValue)
        XCTAssertEqual(HostedServiceConfig.selectedElevenLabsVoiceID(), "myVoice123")
        XCTAssertEqual(HostedServiceConfig.selectedOpenAITTSVoice(), "nova")
    }

    func testSelectedModelsTrimWhitespaceAndFallBackToDefaults() {
        cleanDefaults()
        let defaults = UserDefaults.standard
        defaults.set("  gpt-5.5  ", forKey: AIProvider.openai.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .openai), "gpt-5.5")
        defaults.set("   ", forKey: AIProvider.openai.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .openai), AIProvider.openai.defaultModel)

        // Custom TTS model names are allowed; STT falls back when the saved model is not offered.
        defaults.set("my-custom-tts", forKey: TTSBackend.elevenLabs.modelDefaultsKey)
        XCTAssertEqual(TTSBackend.selectedModel(for: .elevenLabs), "my-custom-tts")
        defaults.set("not-a-model", forKey: STTBackend.groqWhisper.modelDefaultsKey)
        XCTAssertEqual(STTBackend.selectedModel(for: .groqWhisper), STTBackend.groqWhisper.defaultModel)
        defaults.set("whisper-large-v3", forKey: STTBackend.groqWhisper.modelDefaultsKey)
        XCTAssertEqual(STTBackend.selectedModel(for: .groqWhisper), "whisper-large-v3")
    }

    func testRetiredModelsMoveToTheirReplacementAndCustomModelsStay() {
        cleanDefaults()
        let defaults = UserDefaults.standard
        defaults.set("claude-opus-4-1-20250805", forKey: AIProvider.claude.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .claude), "claude-opus-5-5")
        XCTAssertEqual(defaults.string(forKey: AIProvider.claude.modelDefaultsKey), "claude-opus-5-5", "the move is saved")

        defaults.set("llama-3.1-8b-instant", forKey: AIProvider.groq.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .groq), "openai/gpt-oss-20b")

        defaults.set("my-local-finetune", forKey: AIProvider.ollama.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .ollama), "my-local-finetune")

        defaults.set("tts-1-hd", forKey: TTSBackend.openAI.modelDefaultsKey)
        XCTAssertEqual(TTSBackend.selectedModel(for: .openAI), "gpt-realtime-2.1-mini")
        defaults.set("eleven_turbo_v2_5", forKey: TTSBackend.elevenLabs.modelDefaultsKey)
        XCTAssertEqual(TTSBackend.selectedModel(for: .elevenLabs), "eleven_flash_v2_5")

        // STT offers no custom models, so anything retired falls back to the default.
        defaults.set("whisper-1", forKey: STTBackend.openaiWhisper.modelDefaultsKey)
        XCTAssertEqual(STTBackend.selectedModel(for: .openaiWhisper), "gpt-transcribe")
    }

    func testGPT4oMiniTTSStaysUntilTheSpeechEndpointShutsDownThenMovesToRealtime() {
        cleanDefaults()
        let originalClock = TTSBackend.now
        defer { TTSBackend.now = originalClock }
        let defaults = UserDefaults.standard

        TTSBackend.now = { TTSBackend.openAISpeechEndpointShutdown.addingTimeInterval(-60) }
        XCTAssertTrue(TTSBackend.openAI.availableModels.contains("gpt-4o-mini-tts"))
        defaults.set("gpt-4o-mini-tts", forKey: TTSBackend.openAI.modelDefaultsKey)
        XCTAssertEqual(TTSBackend.selectedModel(for: .openAI), "gpt-4o-mini-tts")

        TTSBackend.now = { TTSBackend.openAISpeechEndpointShutdown }
        XCTAssertFalse(TTSBackend.openAI.availableModels.contains("gpt-4o-mini-tts"))
        XCTAssertEqual(TTSBackend.selectedModel(for: .openAI), "gpt-realtime-2.1-mini")
        XCTAssertEqual(defaults.string(forKey: TTSBackend.openAI.modelDefaultsKey), "gpt-realtime-2.1-mini")
    }

    func testEveryReplacementAndDefaultIsAnOfferedModel() {
        for provider in AIProvider.allCases {
            XCTAssertTrue(provider.availableModels.contains(provider.defaultModel), provider.rawValue)
            for (old, new) in provider.retiredModels {
                XCTAssertTrue(provider.availableModels.contains(new), "\(provider.rawValue): \(old) -> \(new)")
                XCTAssertFalse(provider.availableModels.contains(old), "\(provider.rawValue) still offers \(old)")
            }
        }
        for backend in TTSBackend.allCases {
            XCTAssertTrue(backend.availableModels.contains(backend.defaultModel), backend.rawValue)
            for (old, new) in backend.retiredModels {
                XCTAssertTrue(backend.availableModels.contains(new), "\(backend.rawValue): \(old) -> \(new)")
                XCTAssertFalse(backend.availableModels.contains(old), "\(backend.rawValue) still offers \(old)")
            }
        }
        XCTAssertTrue(TTSBackend.openAI.voiceOptions.contains(HostedServiceConfig.defaultOpenAITTSVoice))
        for backend in STTBackend.allCases where !backend.availableModels.isEmpty {
            XCTAssertTrue(backend.availableModels.contains(backend.defaultModel), backend.rawValue)
        }
    }

    func testBlankVoiceSelectionsUseTheDefaults() {
        cleanDefaults()
        UserDefaults.standard.set("  ", forKey: "amica_elevenlabs_voiceid")
        UserDefaults.standard.set("", forKey: HostedServiceConfig.openAITTSVoiceDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedElevenLabsVoiceID(), HostedServiceConfig.defaultElevenLabsVoiceID)
        XCTAssertEqual(HostedServiceConfig.selectedOpenAITTSVoice(), HostedServiceConfig.defaultOpenAITTSVoice)
    }

    func testServiceLanguageSelection() {
        cleanDefaults()
        let defaults = UserDefaults.standard
        XCTAssertEqual(HostedServiceConfig.selectedServiceLanguageID(), HostedServiceConfig.deviceLanguageID)

        defaults.set("fr", forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedServiceLanguageID(), "fr")
        XCTAssertEqual(HostedServiceConfig.selectedServiceLanguageCode(), "fr")

        defaults.set("xx", forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedServiceLanguageID(), HostedServiceConfig.deviceLanguageID)

        defaults.set(HostedServiceConfig.autoLanguageID, forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedServiceLanguageID(), HostedServiceConfig.deviceLanguageID)

        XCTAssertNil(HostedServiceConfig.serviceLanguageCode(for: HostedServiceConfig.autoLanguageID))
        XCTAssertEqual(HostedServiceConfig.serviceLanguageCode(for: "zh-TW"), "zh-TW")
        XCTAssertNil(HostedServiceConfig.serviceLanguageCode(for: "xx"))
        if let deviceCode = HostedServiceConfig.currentDeviceLanguageCode() {
            XCTAssertNotNil(ScowldLanguageLibrary.option(for: deviceCode))
        }
    }

    func testLanguageLibraryHasUniqueCodes() {
        let codes = ScowldLanguageLibrary.options.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertEqual(ScowldLanguageLibrary.option(for: "tl")?.name, "Filipino")
        XCTAssertNil(ScowldLanguageLibrary.option(for: "klingon"))
    }

    func testCharacterNameResolution() {
        cleanDefaults()
        XCTAssertEqual(CharacterPack.resolveCharacterName(), "Bella")
        UserDefaults.standard.set("  Nova \n", forKey: "character_name")
        XCTAssertEqual(CharacterPack.resolveCharacterName(), "Nova")
        UserDefaults.standard.set("   ", forKey: "character_name")
        UserDefaults.standard.set("AvatarSample_C", forKey: "selected_avatar")
        XCTAssertEqual(CharacterPack.resolveCharacterName(), "Bella")
        XCTAssertEqual(CharacterPack.nameForAvatar("UnknownAvatar"), "Bella")
    }
}

/// The provider, voice and speech catalogs shown in Settings.
@MainActor
final class ProviderCatalogTests: XCTestCase {
    func testEveryAIProviderOffersItsDefaultModelAndHasItsOwnKey() {
        for provider in AIProvider.allCases {
            XCTAssertTrue(provider.availableModels.contains(provider.defaultModel), provider.rawValue)
            XCTAssertEqual(Set(provider.availableModels).count, provider.availableModels.count, provider.rawValue)
            XCTAssertEqual(provider.requiresAPIKey, provider != .ollama, provider.rawValue)
            XCTAssertEqual(provider.isOpenAICompatible, provider.baseURL != nil, provider.rawValue)
            if let baseURL = provider.baseURL {
                XCTAssertTrue(baseURL.hasPrefix("https://"), baseURL)
            }
        }
        let keys = AIProvider.allCases.map(\.keychainKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(
            Set(AIProvider.allCases.filter(\.isOpenAICompatible)),
            [.groq, .openRouter, .xai, .togetherAI, .huggingFace, .veniceAI, .moonshot]
        )
        XCTAssertEqual(AIProvider.allCases.filter { !$0.includesSamplingTemperature }, [.moonshot])
        XCTAssertFalse(AIProvider.ollama.supportsVision)
        XCTAssertTrue(AIProvider.gemini.supportsVision)
    }

    func testSpeechBackendsAreConsistent() {
        for backend in STTBackend.allCases {
            if backend.availableModels.isEmpty {
                XCTAssertEqual(backend.defaultModel, "", backend.rawValue)
            } else {
                XCTAssertTrue(backend.availableModels.contains(backend.defaultModel), backend.rawValue)
            }
            XCTAssertEqual(backend.isCloudBased, backend.requiresAPIKey, backend.rawValue)
            XCTAssertFalse(backend.footerText.isEmpty)
        }
        XCTAssertFalse(STTBackend.nativeIOS.requiresAPIKey)
        XCTAssertFalse(STTBackend.none.requiresAPIKey)
        let keys = STTBackend.allCases.map(\.keychainKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testTextToSpeechBackends() {
        for backend in TTSBackend.allCases {
            XCTAssertTrue(backend.availableModels.contains(backend.defaultModel), backend.rawValue)
        }
        XCTAssertEqual(TTSBackend.openAI.keychainKey, AIProvider.openai.keychainKey, "OpenAI speech reuses the chat key")
        XCTAssertNotEqual(TTSBackend.elevenLabs.keychainKey, AIProvider.openai.keychainKey)
        XCTAssertTrue(TTSBackend.elevenLabs.voiceOptions.isEmpty)
        XCTAssertTrue(TTSBackend.openAI.voiceOptions.contains(HostedServiceConfig.defaultOpenAITTSVoice))
    }

    func testEveryPresetVoiceShipsALocalPreview() {
        let ids = ScowldVoiceLibrary.presetVoices.map(\.voiceID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains(HostedServiceConfig.defaultElevenLabsVoiceID))
        for voice in ScowldVoiceLibrary.presetVoices {
            XCTAssertTrue(BundledElevenLabsVoicePreviews.hasPreview(forVoiceID: voice.voiceID), voice.name)
        }
        XCTAssertFalse(BundledElevenLabsVoicePreviews.hasPreview(forVoiceID: "not-a-voice"))
    }

    func testVoicePickerMapping() {
        let preset = ScowldVoiceLibrary.presetVoices[1].voiceID
        XCTAssertEqual(ScowldVoiceLibrary.pickerID(for: preset), preset)
        XCTAssertEqual(ScowldVoiceLibrary.pickerID(for: "customVoice42"), ScowldVoiceLibrary.customID)
        XCTAssertEqual(ScowldVoiceLibrary.voiceID(for: preset, customVoiceID: "ignored"), preset)
        XCTAssertEqual(ScowldVoiceLibrary.voiceID(for: ScowldVoiceLibrary.customID, customVoiceID: "  abc123 "), "abc123")
        XCTAssertEqual(
            ScowldVoiceLibrary.voiceID(for: ScowldVoiceLibrary.customID, customVoiceID: "  "),
            HostedServiceConfig.defaultElevenLabsVoiceID
        )
        XCTAssertEqual(ScowldVoiceLibrary.option(for: preset)?.voiceID, preset)
        XCTAssertNil(ScowldVoiceLibrary.option(for: "customVoice42"))
    }
}
