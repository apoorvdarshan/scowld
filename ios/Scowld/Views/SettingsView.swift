import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasChanges = false
    @State private var showAPIKey = false
    @State private var showOpenAITTSKey = false
    @State private var showElevenLabsKey = false
    @State private var showSTTAPIKey = false

    // MARK: - LLM Settings
    @State private var selectedProvider: AIProvider = .gemini
    @State private var selectedModel: String = AIProvider.gemini.defaultModel
    @State private var apiKeyInput: String = ""
    @State private var ollamaURL: String = OllamaConfig.defaultURL
    @State private var hasAPIKey: Bool = false

    // MARK: - TTS Settings
    @State private var ttsBackend: String = "native_ios"
    @State private var elevenLabsAPIKey: String = ""
    @State private var elevenLabsVoiceId: String = "mHX7OoPk2G45VMAuinIt"
    @State private var elevenLabsModel: String = Self.defaultElevenLabsModel
    @State private var openAITTSModel: String = Self.defaultOpenAITTSModel
    @State private var openAITTSVoice: String = Self.defaultOpenAITTSVoice
    @State private var speechRate: Float = 0.95
    @State private var speechPitch: Float = 1.2

    // MARK: - STT Settings
    @State private var sttBackend: String = "native_ios"
    @State private var selectedSTTModel: String = STTBackend.nativeIOS.defaultModel

    // MARK: - Character Settings
    @State private var characterName: String = "Stella"
    @State private var selectedAvatar: String = "AvatarSample_A"
    @State private var systemPrompt: String = ""

    private static let defaultSystemPrompt = "You are a warm, cheerful, and expressive AI companion. You're friendly, playful, and genuinely care about the person you're talking to. You speak naturally and conversationally — like a close friend. Keep responses concise (1-3 sentences). Be expressive and show personality."
    private static let defaultElevenLabsModel = "eleven_flash_v2_5"
    private static let defaultOpenAITTSModel = "gpt-4o-mini-tts"
    private static let defaultOpenAITTSVoice = "nova"
    private static let elevenLabsModels = [
        "eleven_flash_v2_5",
        "eleven_turbo_v2_5",
        "eleven_multilingual_v2",
        "eleven_v3",
    ]
    private static let openAITTSModels = [
        "gpt-4o-mini-tts",
        "tts-1",
        "tts-1-hd",
    ]
    private static let openAIGPT4oVoices = [
        "alloy",
        "ash",
        "ballad",
        "cedar",
        "coral",
        "echo",
        "fable",
        "marin",
        "nova",
        "onyx",
        "sage",
        "shimmer",
        "verse",
    ]
    private static let openAILegacyVoices = [
        "alloy",
        "ash",
        "coral",
        "echo",
        "fable",
        "nova",
        "onyx",
        "sage",
        "shimmer",
    ]

    private var supportedOpenAITTSVoices: [String] {
        openAITTSModel == Self.defaultOpenAITTSModel ? Self.openAIGPT4oVoices : Self.openAILegacyVoices
    }

    // Vision is handled automatically by the selected LLM provider

    var showsDismissControls = true

    var body: some View {
        NavigationStack {
            List {
                // MARK: - AI Provider
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) {
                        selectedModel = selectedProvider.defaultModel
                        showAPIKey = false
                        loadAPIKey()
                        hasChanges = true
                    }

                    Picker("Model", selection: $selectedModel) {
                        ForEach(selectedProvider.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: selectedModel) { hasChanges = true }

                    if selectedProvider.requiresAPIKey {
                        HStack {
                            if showAPIKey {
                                TextField("API Key", text: $apiKeyInput)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("API Key", text: $apiKeyInput)
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                            }
                            Button { showAPIKey.toggle() } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: apiKeyInput) { hasChanges = true }

                        Text("Stored securely in iOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if selectedProvider == .ollama {
                        TextField("Server URL", text: $ollamaURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: ollamaURL) { hasChanges = true }
                    }
                } header: {
                    Label("AI Provider", systemImage: "cpu")
                } footer: {
                    Text("Powers the AI responses in conversations.")
                }

                // MARK: - TTS (Text-to-Speech)
                Section {
                    Picker("Backend", selection: $ttsBackend) {
                        Text("ElevenLabs").tag("elevenlabs")
                        Text("OpenAI TTS").tag("openai_tts")
                        Text("Native iOS").tag("native_ios")
                        Text("None").tag("none")
                    }
                    .onChange(of: ttsBackend) {
                        showElevenLabsKey = false
                        showOpenAITTSKey = false
                        hasChanges = true
                    }

                    if ttsBackend == "elevenlabs" {
                        Picker("Model", selection: $elevenLabsModel) {
                            ForEach(Self.elevenLabsModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: elevenLabsModel) { hasChanges = true }

                        HStack {
                            if showElevenLabsKey {
                                TextField("API Key", text: $elevenLabsAPIKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("API Key", text: $elevenLabsAPIKey)
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                            }
                            Button { showElevenLabsKey.toggle() } label: {
                                Image(systemName: showElevenLabsKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: elevenLabsAPIKey) { hasChanges = true }

                        TextField("Voice ID", text: $elevenLabsVoiceId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: elevenLabsVoiceId) { hasChanges = true }

                        Text("Default voice: Sarah.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if ttsBackend == "openai_tts" {
                        Picker("Model", selection: $openAITTSModel) {
                            ForEach(Self.openAITTSModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: openAITTSModel) {
                            if !supportedOpenAITTSVoices.contains(openAITTSVoice) {
                                openAITTSVoice = supportedOpenAITTSVoices.first ?? Self.defaultOpenAITTSVoice
                            }
                            hasChanges = true
                        }

                        Picker("Voice", selection: $openAITTSVoice) {
                            ForEach(supportedOpenAITTSVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .onChange(of: openAITTSVoice) { hasChanges = true }

                        if selectedProvider == .openai {
                            Text("Uses the OpenAI API key above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                if showOpenAITTSKey {
                                    TextField("OpenAI API Key", text: Binding(
                                        get: { KeychainManager.load(key: AIProvider.openai.keychainKey) ?? "" },
                                        set: {
                                            if $0.isEmpty {
                                                KeychainManager.delete(key: AIProvider.openai.keychainKey)
                                            } else {
                                                KeychainManager.save(key: AIProvider.openai.keychainKey, value: $0)
                                            }
                                            hasChanges = true
                                        }
                                    ))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                } else {
                                    SecureField("OpenAI API Key", text: Binding(
                                        get: { KeychainManager.load(key: AIProvider.openai.keychainKey) ?? "" },
                                        set: {
                                            if $0.isEmpty {
                                                KeychainManager.delete(key: AIProvider.openai.keychainKey)
                                            } else {
                                                KeychainManager.save(key: AIProvider.openai.keychainKey, value: $0)
                                            }
                                            hasChanges = true
                                        }
                                    ))
                                    .textContentType(.password)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                }

                                Button { showOpenAITTSKey.toggle() } label: {
                                    Image(systemName: showOpenAITTSKey ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("Stored securely in iOS Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if ttsBackend == "native_ios" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speech Rate: \(String(format: "%.1f", speechRate))")
                                .font(.subheadline)
                            Slider(value: $speechRate, in: 0.5...1.5)
                                .tint(.amicaBlue)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pitch: \(String(format: "%.1f", speechPitch))")
                                .font(.subheadline)
                            Slider(value: $speechPitch, in: 0.5...2.0)
                                .tint(.amicaBlue)
                        }
                    }
                } header: {
                    Label("Text-to-Speech", systemImage: "speaker.wave.3")
                } footer: {
                    switch ttsBackend {
                    case "elevenlabs": Text("High-quality voices. Free: 10K chars/mo. Starter: $5/mo for 30K chars.")
                    case "openai_tts": Text("Uses your OpenAI API key. Natural sounding voices.")
                    case "native_ios": Text("Built-in iOS speech. Free, no API needed. No lip sync.")
                    default: Text("No voice output.")
                    }
                }

                // MARK: - STT (Speech-to-Text)
                Section {
                    Menu {
                        ForEach(STTBackend.allCases, id: \.self) { backend in
                            Button {
                                setSTTBackend(backend)
                            } label: {
                                if backend == selectedSTTBackend {
                                    Label(backend.displayName, systemImage: "checkmark")
                                } else {
                                    Text(backend.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Backend")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(selectedSTTBackend.displayName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if let backend = STTBackend(rawValue: sttBackend), !backend.availableModels.isEmpty {
                        Picker("Model", selection: $selectedSTTModel) {
                            ForEach(backend.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: selectedSTTModel) { hasChanges = true }
                    }

                    if let backend = STTBackend(rawValue: sttBackend), backend.requiresAPIKey {
                        HStack {
                            if showSTTAPIKey {
                                TextField("API Key", text: Binding(
                                    get: { KeychainManager.load(key: backend.keychainKey) ?? "" },
                                    set: {
                                        if $0.isEmpty {
                                            KeychainManager.delete(key: backend.keychainKey)
                                        } else {
                                            KeychainManager.save(key: backend.keychainKey, value: $0)
                                        }
                                        hasChanges = true
                                    }
                                ))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            } else {
                                SecureField("API Key", text: Binding(
                                    get: { KeychainManager.load(key: backend.keychainKey) ?? "" },
                                    set: {
                                        if $0.isEmpty {
                                            KeychainManager.delete(key: backend.keychainKey)
                                        } else {
                                            KeychainManager.save(key: backend.keychainKey, value: $0)
                                        }
                                        hasChanges = true
                                    }
                                ))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            }

                            Button { showSTTAPIKey.toggle() } label: {
                                Image(systemName: showSTTAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: sttBackend) {
                            showSTTAPIKey = false
                        }

                        Text("Stored securely in iOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Speech-to-Text", systemImage: "mic")
                } footer: {
                    Text((STTBackend(rawValue: sttBackend) ?? .nativeIOS).footerText)
                }

                // MARK: - Character
                Section {
                    Picker("Avatar", selection: $selectedAvatar) {
                        ForEach(CharacterPack.defaultPacks) { pack in
                            Text(pack.name).tag(pack.fileName)
                        }
                    }
                    .onChange(of: selectedAvatar) { hasChanges = true }

                    TextField("Custom Name (optional)", text: $characterName)
                        .autocorrectionDisabled()
                        .onChange(of: characterName) { hasChanges = true }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $systemPrompt)
                            .frame(minHeight: 100)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .onChange(of: systemPrompt) { hasChanges = true }
                    }
                } header: {
                    Label("Character", systemImage: "person.fill")
                } footer: {
                    Text("Each avatar uses its own name by default. Set a custom name to override it.")
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissControls {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveSettings()
                        if showsDismissControls {
                            dismiss()
                        }
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundStyle(hasChanges ? .amicaBlue : .secondary)
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .onAppear { loadSettings() }
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let providerStr = defaults.string(forKey: "selectedProvider"),
           let provider = AIProvider(rawValue: providerStr) {
            selectedProvider = provider
        }
        selectedModel = defaults.string(forKey: "selectedModel") ?? selectedProvider.defaultModel
        if !selectedProvider.availableModels.contains(selectedModel) {
            selectedModel = selectedProvider.defaultModel
        }
        ollamaURL = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
        speechRate = defaults.float(forKey: "speechRate")
        if speechRate == 0 { speechRate = 0.95 }
        speechPitch = defaults.float(forKey: "speechPitch")
        if speechPitch == 0 { speechPitch = 1.2 }
        // Amica backend settings
        ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "native_ios"
        sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "native_ios"
        let stt = STTBackend(rawValue: sttBackend) ?? .nativeIOS
        selectedSTTModel = STTBackend.selectedModel(for: stt)
        characterName = defaults.string(forKey: "character_name") ?? ""
        selectedAvatar = defaults.string(forKey: "selected_avatar") ?? "AvatarSample_A"
        systemPrompt = defaults.string(forKey: "system_prompt") ?? Self.defaultSystemPrompt
        elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "mHX7OoPk2G45VMAuinIt"
        elevenLabsModel = defaults.string(forKey: "amica_elevenlabs_model") ?? Self.defaultElevenLabsModel
        if !Self.elevenLabsModels.contains(elevenLabsModel) {
            elevenLabsModel = Self.defaultElevenLabsModel
        }
        openAITTSModel = defaults.string(forKey: "amica_openai_tts_model") ?? Self.defaultOpenAITTSModel
        if !Self.openAITTSModels.contains(openAITTSModel) {
            openAITTSModel = Self.defaultOpenAITTSModel
        }
        openAITTSVoice = defaults.string(forKey: "amica_openai_tts_voice") ?? Self.defaultOpenAITTSVoice
        if !supportedOpenAITTSVoices.contains(openAITTSVoice) {
            openAITTSVoice = Self.defaultOpenAITTSVoice
        }

        // Load existing keys into fields
        if let existingKey = KeychainManager.load(key: selectedProvider.keychainKey) {
            apiKeyInput = existingKey
        }
        if let existingELKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") {
            elevenLabsAPIKey = existingELKey
        }

        loadAPIKey()

        // Reset hasChanges AFTER fields are populated (onChange fires during load)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hasChanges = false
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
        defaults.set(selectedModel, forKey: "selectedModel")
        defaults.set(speechRate, forKey: "speechRate")
        defaults.set(speechPitch, forKey: "speechPitch")
        // Amica backend settings
        defaults.set(ttsBackend, forKey: "amica_tts_backend")
        defaults.set(sttBackend, forKey: "amica_stt_backend")
        defaults.set(elevenLabsVoiceId, forKey: "amica_elevenlabs_voiceid")
        defaults.set(elevenLabsModel, forKey: "amica_elevenlabs_model")
        defaults.set(openAITTSModel, forKey: "amica_openai_tts_model")
        defaults.set(openAITTSVoice, forKey: "amica_openai_tts_voice")
        if let backend = STTBackend(rawValue: sttBackend), !backend.availableModels.isEmpty {
            defaults.set(selectedSTTModel, forKey: backend.modelDefaultsKey)
        }
        defaults.set(characterName, forKey: "character_name")
        defaults.set(selectedAvatar, forKey: "selected_avatar")
        defaults.set(systemPrompt, forKey: "system_prompt")

        // Save or clear API keys in Keychain
        if apiKeyInput.isEmpty {
            KeychainManager.delete(key: selectedProvider.keychainKey)
        } else {
            KeychainManager.save(key: selectedProvider.keychainKey, value: apiKeyInput)
        }
        if elevenLabsAPIKey.isEmpty {
            KeychainManager.delete(key: "com.scowld.elevenlabs.apikey")
        } else {
            KeychainManager.save(key: "com.scowld.elevenlabs.apikey", value: elevenLabsAPIKey)
        }
        if selectedProvider == .ollama {
            KeychainManager.save(key: OllamaConfig.keychainURLKey, value: ollamaURL)
        }

        hasChanges = false

        // Push settings to Amica WebView via notification
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func loadAPIKey() {
        let existingKey = KeychainManager.load(key: selectedProvider.keychainKey) ?? ""
        apiKeyInput = selectedProvider.requiresAPIKey ? existingKey : ""
        hasAPIKey = !existingKey.isEmpty
    }

    private var selectedSTTBackend: STTBackend {
        STTBackend(rawValue: sttBackend) ?? .nativeIOS
    }

    private func setSTTBackend(_ backend: STTBackend) {
        sttBackend = backend.rawValue
        selectedSTTModel = STTBackend.selectedModel(for: backend)
        hasChanges = true
    }
}
