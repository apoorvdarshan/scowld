import XCTest
@testable import Scowld

/// The instructions Scowld sends when a live voice session starts.
@MainActor
final class SystemPromptTests: XCTestCase {
    private func cleanDefaults() {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        addTeardownBlock { defaults.restore() }
    }

    func testDefaultPersonalityIsSpokenAndHasNoEmotionTags() {
        cleanDefaults()
        let prompt = SystemPromptTemplate.build(conversationContext: [], characterName: "Nova", cameraAvailable: false)

        XCTAssertTrue(prompt.hasPrefix("You are Nova, a friendly and expressive AI companion"))
        XCTAssertTrue(prompt.contains("real-time voice conversation"))
        XCTAssertTrue(prompt.contains("- Your name is Nova. Never say your name is Amica or anything else."))
        XCTAssertTrue(prompt.contains("everything you say is spoken aloud"))
        XCTAssertTrue(prompt.contains("Current date/time: "))
        // Bracketed emotion tags would be read out loud.
        XCTAssertFalse(prompt.contains("[happy]"))
        XCTAssertFalse(prompt.contains("emotion tag"))
        XCTAssertFalse(prompt.contains("Previous messages from the active saved chat"))
        XCTAssertFalse(prompt.contains("front camera"))
    }

    func testCustomPromptReplacesTheDefaultPersonality() {
        cleanDefaults()
        UserDefaults.standard.set("Speak like a pirate.", forKey: "system_prompt")
        let prompt = SystemPromptTemplate.build(conversationContext: [], characterName: "Nova", cameraAvailable: false)
        XCTAssertTrue(prompt.hasPrefix("You are Nova. Speak like a pirate."))
        XCTAssertFalse(prompt.contains("friendly and expressive AI companion"))
    }

    func testSavedChatAndCameraNoteAreIncludedWhenPresent() {
        cleanDefaults()
        let prompt = SystemPromptTemplate.build(
            conversationContext: ["User: I like hiking", "Nova: Noted!"],
            characterName: "Nova",
            cameraAvailable: true
        )
        XCTAssertTrue(prompt.contains("Previous messages from the active saved chat"))
        XCTAssertTrue(prompt.contains("- User: I like hiking\n- Nova: Noted!\n"))
        XCTAssertTrue(prompt.contains("You may receive images from the user's front camera."))
    }

    func testSelectedServiceLanguageForcesTheReplyLanguage() {
        cleanDefaults()
        UserDefaults.standard.set("ja", forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        let prompt = SystemPromptTemplate.build(conversationContext: [], cameraAvailable: false)
        XCTAssertTrue(prompt.contains("Response language: Reply in Japanese unless the user explicitly asks for another language."))
    }

    func testDeviceLanguageModeFollowsTheSimulatorLanguage() {
        cleanDefaults()
        UserDefaults.standard.set(HostedServiceConfig.deviceLanguageID, forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        let prompt = SystemPromptTemplate.build(conversationContext: [], cameraAvailable: false)
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

        let prompt = ContextBuilder(memoryStore: store).buildSystemPrompt(cameraAvailable: true)
        XCTAssertTrue(prompt.hasPrefix("You are Iris"))
        XCTAssertTrue(prompt.contains("- User: My cat is Miso\n- Iris: What a cute name!\n"))
        XCTAssertTrue(prompt.contains("front camera"))
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

    func testDefaultsOnFirstLaunch() {
        cleanDefaults()
        HostedServiceConfig.applyBYOKDefaults()
        let defaults = UserDefaults.standard

        XCTAssertEqual(defaults.string(forKey: HostedServiceConfig.providerDefaultsKey), AIProvider.gemini.rawValue)
        XCTAssertEqual(defaults.string(forKey: AIProvider.gemini.modelDefaultsKey), "gemini-3.8-live")
        XCTAssertEqual(defaults.string(forKey: AIProvider.gemini.voiceDefaultsKey), "Leda")
    }

    func testDefaultsKeepTheUsersChoices() {
        cleanDefaults()
        let defaults = UserDefaults.standard
        defaults.set(AIProvider.openai.rawValue, forKey: HostedServiceConfig.providerDefaultsKey)
        defaults.set("gpt-realtime-2.1", forKey: AIProvider.openai.modelDefaultsKey)
        defaults.set("coral", forKey: AIProvider.openai.voiceDefaultsKey)

        HostedServiceConfig.applyBYOKDefaults()

        XCTAssertEqual(HostedServiceConfig.selectedProvider(), .openai)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .openai), "gpt-realtime-2.1")
        XCTAssertEqual(HostedServiceConfig.selectedVoice(for: .openai), "coral")
    }

    func testARemovedVoiceFallsBackToTheDefault() {
        cleanDefaults()
        // Male voices were removed; a saved one falls back to the provider's default.
        UserDefaults.standard.set("cedar", forKey: AIProvider.openai.voiceDefaultsKey)
        UserDefaults.standard.set("Puck", forKey: AIProvider.gemini.voiceDefaultsKey)
        UserDefaults.standard.set("rex", forKey: AIProvider.xai.voiceDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedVoice(for: .openai), "marin")
        XCTAssertEqual(HostedServiceConfig.selectedVoice(for: .gemini), "Leda")
        XCTAssertEqual(HostedServiceConfig.selectedVoice(for: .xai), "ara")
    }

    func testARemovedProviderFallsBackToGemini() {
        cleanDefaults()
        for removed in ["claude", "ollama", "groq", "openRouter", "moonshot", ""] {
            UserDefaults.standard.set(removed, forKey: HostedServiceConfig.providerDefaultsKey)
            XCTAssertEqual(HostedServiceConfig.selectedProvider(), .gemini, removed)
        }
    }

    func testBlankModelsUseTheDefaultAndCustomModelsStay() {
        cleanDefaults()
        UserDefaults.standard.set("  ", forKey: AIProvider.xai.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .xai), "grok-voice-latest")
        UserDefaults.standard.set(" gemini-live-custom ", forKey: AIProvider.gemini.modelDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedModel(for: .gemini), "gemini-live-custom")
    }

    func testAVoiceTheProviderDoesNotOfferUsesItsDefault() {
        cleanDefaults()
        // An ElevenLabs voice ID or another provider's voice is not a Gemini voice.
        UserDefaults.standard.set("mHX7OoPk2G45VMAuinIt", forKey: AIProvider.gemini.voiceDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedVoice(for: .gemini), "Leda")
        UserDefaults.standard.set("marin", forKey: AIProvider.xai.voiceDefaultsKey)
        XCTAssertEqual(HostedServiceConfig.selectedVoice(for: .xai), "ara")
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

/// Earlier versions' speech-to-text, text-to-speech and text-chat settings are
/// removed once, keys included.
@MainActor
final class LegacySettingsCleanupTests: XCTestCase {
    func testOldProviderKeysAndSettingsAreRemovedOnceAndLiveKeysStay() {
        let defaults = DefaultsSnapshot()
        defaults.clear()
        let keys = LegacySettingsCleanup.legacyKeychainKeys + [AIProvider.gemini.keychainKey]
        let keychain = KeychainSnapshot(keys: keys)
        addTeardownBlock { @MainActor in
            keychain.restore()
            defaults.restore()
        }

        XCTAssertTrue(KeychainManager.save(key: "com.scowld.apikey.claude", value: "claude-key"))
        XCTAssertTrue(KeychainManager.save(key: "com.scowld.tts.elevenlabs", value: "eleven-key"))
        XCTAssertTrue(KeychainManager.save(key: AIProvider.gemini.keychainKey, value: "gemini-key"))
        let standard = UserDefaults.standard
        standard.set("elevenlabs", forKey: "amica_tts_backend")
        standard.set("gemini-3.5-flash-lite", forKey: "com.scowld.ai.model.gemini")
        standard.set("nova-3", forKey: "com.scowld.stt.model.deepgram")
        standard.set("Nova", forKey: "character_name")

        LegacySettingsCleanup.runOnce()

        XCTAssertNil(KeychainManager.load(key: "com.scowld.apikey.claude"))
        XCTAssertNil(KeychainManager.load(key: "com.scowld.tts.elevenlabs"))
        XCTAssertEqual(KeychainManager.load(key: AIProvider.gemini.keychainKey), "gemini-key")
        XCTAssertNil(standard.string(forKey: "amica_tts_backend"))
        XCTAssertNil(standard.string(forKey: "com.scowld.ai.model.gemini"))
        XCTAssertNil(standard.string(forKey: "com.scowld.stt.model.deepgram"))
        XCTAssertEqual(standard.string(forKey: "character_name"), "Nova")

        // Only once: a key saved afterwards is left alone.
        XCTAssertTrue(KeychainManager.save(key: "com.scowld.apikey.claude", value: "later"))
        LegacySettingsCleanup.runOnce()
        XCTAssertEqual(KeychainManager.load(key: "com.scowld.apikey.claude"), "later")
    }
}

/// The providers, models and voices shown in Settings.
@MainActor
final class ProviderCatalogTests: XCTestCase {
    func testEveryProviderOffersItsDefaultsAndHasItsOwnKey() {
        for provider in AIProvider.allCases {
            XCTAssertTrue(provider.availableModels.contains(provider.defaultModel), provider.rawValue)
            XCTAssertTrue(provider.voices.contains { $0.id == provider.defaultVoice }, provider.rawValue)
            XCTAssertEqual(Set(provider.voices.map(\.id)).count, provider.voices.count, "\(provider) lists a voice twice")
            XCTAssertEqual(Set(provider.availableModels).count, provider.availableModels.count)
        }
        XCTAssertEqual(Set(AIProvider.allCases.map(\.keychainKey)).count, AIProvider.allCases.count)
        XCTAssertEqual(Set(AIProvider.allCases.map(\.modelDefaultsKey)).count, AIProvider.allCases.count)
        XCTAssertEqual(Set(AIProvider.allCases.map(\.voiceDefaultsKey)).count, AIProvider.allCases.count)
    }

    func testKeychainKeysMatchEarlierVersions() {
        // Saved Gemini, OpenAI and xAI keys keep working after the update.
        XCTAssertEqual(AIProvider.gemini.keychainKey, "com.scowld.apikey.gemini")
        XCTAssertEqual(AIProvider.openai.keychainKey, "com.scowld.apikey.openai")
        XCTAssertEqual(AIProvider.xai.keychainKey, "com.scowld.apikey.xai")
    }

    func testCameraSupportAndVoiceNames() {
        XCTAssertEqual(AIProvider.gemini.cameraSupport, .continuous)
        XCTAssertEqual(AIProvider.openai.cameraSupport, .perTurn)
        XCTAssertEqual(AIProvider.xai.cameraSupport, .unsupported)
        XCTAssertEqual(LiveVoice(id: "marin", style: "").name, "Marin")
        XCTAssertEqual(LiveVoice(id: "Leda", style: "").name, "Leda")
    }

    func testOnlyFemaleVoicesAreOffered() {
        XCTAssertEqual(AIProvider.gemini.voices.map(\.id), [
            "Leda", "Aoede", "Zephyr", "Achernar", "Vindemiatrix", "Sulafat", "Laomedeia",
            "Kore", "Callirrhoe", "Despina", "Autonoe", "Erinome", "Pulcherrima", "Gacrux",
        ])
        XCTAssertEqual(AIProvider.openai.voices.map(\.id), ["marin", "shimmer", "coral", "sage"])
        XCTAssertEqual(AIProvider.xai.voices.map(\.id), ["ara", "eve"])
    }
}
