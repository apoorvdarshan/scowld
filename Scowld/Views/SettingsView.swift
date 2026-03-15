import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSaved = false
    @State private var hasChanges = false

    // MARK: - LLM Settings
    @State private var selectedProvider: AIProvider = .gemini
    @State private var selectedModel: String = AIProvider.gemini.defaultModel
    @State private var apiKeyInput: String = ""
    @State private var ollamaURL: String = OllamaConfig.defaultURL
    @State private var hasAPIKey: Bool = false
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false

    // MARK: - TTS Settings
    @State private var ttsBackend: String = "native_ios"
    @State private var elevenLabsAPIKey: String = ""
    @State private var hasElevenLabsKey: Bool = false
    @State private var elevenLabsVoiceId: String = "cgSgspJ2msm6clMCkdW9"
    @State private var speechRate: Float = 0.95
    @State private var speechPitch: Float = 1.2

    // MARK: - STT Settings
    @State private var sttBackend: String = "none"

    // MARK: - Vision Settings
    @State private var visionBackend: String = "none"

    // MARK: - Character
    @State private var selectedCharacterId: String = "avatar_a"

    let characters = CharacterPack.defaultPacks
    var memoryStore: MemoryStore

    var body: some View {
        NavigationStack {
            List {
                // MARK: - AI Provider (LLM)
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) {
                        selectedModel = selectedProvider.defaultModel
                        loadAPIKey()
                        hasChanges = true
                    }

                    Picker("Model", selection: $selectedModel) {
                        ForEach(selectedProvider.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } header: {
                    Label("AI Provider (LLM)", systemImage: "cpu")
                } footer: {
                    Text("Powers the AI responses in conversations.")
                }

                // MARK: - LLM API Key
                if selectedProvider.requiresAPIKey {
                    Section {
                        SecureField("API Key", text: $apiKeyInput)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .onChange(of: apiKeyInput) { hasChanges = true }

                        Text("Stored securely in iOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Label("API Key", systemImage: "key")
                    }
                }

                // MARK: - Ollama Settings
                if selectedProvider == .ollama {
                    Section {
                        TextField("Server URL", text: $ollamaURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Label("Ollama", systemImage: "server.rack")
                    }
                }

                // MARK: - Test Connection
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(isTesting || (!hasAPIKey && selectedProvider.requiresAPIKey && apiKeyInput.isEmpty))

                    if !testResult.isEmpty {
                        HStack {
                            Image(systemName: testResult.starts(with: "Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(testResult.starts(with: "Success") ? .green : .red)
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(testResult.starts(with: "Success") ? .green : .red)
                        }
                    }
                } header: {
                    Label("Connection", systemImage: "wifi")
                }

                // MARK: - TTS (Text-to-Speech)
                Section {
                    Picker("Backend", selection: $ttsBackend) {
                        Text("ElevenLabs").tag("elevenlabs")
                        Text("OpenAI TTS").tag("openai_tts")
                        Text("Native iOS").tag("native_ios")
                        Text("None").tag("none")
                    }

                    if ttsBackend == "native_ios" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speech Rate: \(String(format: "%.1f", speechRate))")
                                .font(.subheadline)
                            Slider(value: $speechRate, in: 0.5...1.5)
                                .tint(.orange)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pitch: \(String(format: "%.1f", speechPitch))")
                                .font(.subheadline)
                            Slider(value: $speechPitch, in: 0.5...2.0)
                                .tint(.orange)
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

                // MARK: - ElevenLabs Settings
                if ttsBackend == "elevenlabs" {
                    Section {
                        SecureField("API Key", text: $elevenLabsAPIKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .onChange(of: elevenLabsAPIKey) { hasChanges = true }

                        TextField("Voice ID", text: $elevenLabsVoiceId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: elevenLabsVoiceId) { hasChanges = true }

                        Text("Get your API key at elevenlabs.io. Default voice: Sarah.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Label("ElevenLabs", systemImage: "waveform.circle")
                    }
                }

                // MARK: - STT (Speech-to-Text)
                Section {
                    Picker("Backend", selection: $sttBackend) {
                        Text("OpenAI Whisper API").tag("openai_whisper")
                        Text("Amica (Browser Whisper)").tag("whisper_browser")
                        Text("None (use text input)").tag("none")
                    }
                } header: {
                    Label("Speech-to-Text", systemImage: "mic")
                } footer: {
                    switch sttBackend {
                    case "openai_whisper": Text("High accuracy, cloud-based. Uses your OpenAI API key.")
                    case "whisper_browser": Text("Runs Whisper locally in the browser. Free, on-device.")
                    default: Text("Voice input disabled. Use text input only.")
                    }
                }

                // MARK: - OpenAI Whisper API Key
                if sttBackend == "openai_whisper" {
                    Section {
                        Text("Uses the same OpenAI API key from your AI Provider settings above, or set a separate one below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("OpenAI Whisper API Key (optional)", text: Binding(
                            get: { UserDefaults.standard.string(forKey: "amica_openai_whisper_apikey") ?? "" },
                            set: { UserDefaults.standard.set($0, forKey: "amica_openai_whisper_apikey") }
                        ))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    } header: {
                        Label("Whisper Settings", systemImage: "mic.badge.xmark")
                    }
                }

                // MARK: - Vision
                Section {
                    Picker("Backend", selection: $visionBackend) {
                        Text("Gemini").tag("chatgpt")
                        Text("Ollama").tag("ollama")
                        Text("None").tag("none")
                    }
                } header: {
                    Label("Vision", systemImage: "eye")
                } footer: {
                    Text("Enables the character to see via camera. Uses your LLM provider's vision API.")
                }

                // MARK: - Character
                Section {
                    ForEach(characters) { character in
                        Button {
                            selectedCharacterId = character.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character.name)
                                        .foregroundStyle(.primary)
                                        .fontWeight(.medium)
                                    Text(character.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedCharacterId == character.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Character", systemImage: "person.fill")
                }

                // MARK: - Memory Management
                Section {
                    HStack {
                        Text("Stored Memories")
                        Spacer()
                        Text("\(memoryStore.totalMemoryCount)")
                            .foregroundStyle(.orange)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }

                    NavigationLink {
                        MemoryView(memoryStore: memoryStore)
                    } label: {
                        Label("Browse Memories", systemImage: "brain.head.profile.fill")
                    }

                    Button(role: .destructive) {
                        memoryStore.clearAllMemories()
                    } label: {
                        Label("Clear All Memories", systemImage: "trash")
                    }
                } header: {
                    Label("Memory", systemImage: "brain")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Scowld")
                            .fontWeight(.medium)
                        Spacer()
                        Text("v1.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("Open Source AI Assistant — MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Character: Amica by Arbius AI (MIT)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveSettings()
                        withAnimation { showSaved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showSaved = false }
                            dismiss()
                        }
                    } label: {
                        if showSaved {
                            Label("Saved!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundStyle(hasChanges ? .orange : .secondary)
                        }
                    }
                    .disabled(!hasChanges && !showSaved)
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
        ollamaURL = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
        speechRate = defaults.float(forKey: "speechRate")
        if speechRate == 0 { speechRate = 0.95 }
        speechPitch = defaults.float(forKey: "speechPitch")
        if speechPitch == 0 { speechPitch = 1.2 }
        selectedCharacterId = defaults.string(forKey: "selectedCharacter") ?? "avatar_a"

        // Amica backend settings
        ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "native_ios"
        sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "none"
        visionBackend = defaults.string(forKey: "amica_vision_backend") ?? "none"
        elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "EXAVITQu4vr4xnSDxMaL"

        // Load existing keys into fields (show dots if set)
        if let existingKey = KeychainManager.load(key: selectedProvider.keychainKey) {
            apiKeyInput = existingKey
        }
        if let existingELKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") {
            elevenLabsAPIKey = existingELKey
        }

        hasChanges = false
        loadAPIKey()
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
        defaults.set(selectedModel, forKey: "selectedModel")
        defaults.set(speechRate, forKey: "speechRate")
        defaults.set(speechPitch, forKey: "speechPitch")
        defaults.set(selectedCharacterId, forKey: "selectedCharacter")

        // Amica backend settings
        defaults.set(ttsBackend, forKey: "amica_tts_backend")
        defaults.set(sttBackend, forKey: "amica_stt_backend")
        defaults.set(visionBackend, forKey: "amica_vision_backend")
        defaults.set(elevenLabsVoiceId, forKey: "amica_elevenlabs_voiceid")

        // Save ALL API keys to Keychain
        if !apiKeyInput.isEmpty {
            KeychainManager.save(key: selectedProvider.keychainKey, value: apiKeyInput)
        }
        if !elevenLabsAPIKey.isEmpty {
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
        hasAPIKey = KeychainManager.exists(key: selectedProvider.keychainKey)
    }

    private func saveAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        let success = KeychainManager.save(key: selectedProvider.keychainKey, value: apiKeyInput)
        if success {
            hasAPIKey = true
            apiKeyInput = ""
        }
    }

    private func saveElevenLabsKey() {
        guard !elevenLabsAPIKey.isEmpty else { return }
        let success = KeychainManager.save(key: "com.scowld.elevenlabs.apikey", value: elevenLabsAPIKey)
        if success {
            hasElevenLabsKey = true
            elevenLabsAPIKey = ""
        }
    }

    // MARK: - Test Connection

    private func testConnection() async {
        isTesting = true
        testResult = ""
        defer { isTesting = false }

        do {
            let provider = buildProvider()
            let response = try await provider.generate(
                messages: [ChatMessage(role: .user, content: "Say 'Connection successful!' in exactly those words.")],
                systemPrompt: "Respond with exactly: Connection successful!"
            )
            testResult = "Success: \(response.prefix(50))"
        } catch {
            testResult = "Error: \(error.localizedDescription)"
        }
    }

    private func buildProvider() -> any LLMProvider {
        let apiKey = apiKeyInput.isEmpty
            ? (KeychainManager.load(key: selectedProvider.keychainKey) ?? "")
            : apiKeyInput

        switch selectedProvider {
        case .gemini: return GeminiProvider(apiKey: apiKey, model: selectedModel)
        case .openai: return OpenAIProvider(apiKey: apiKey, model: selectedModel)
        case .claude: return ClaudeProvider(apiKey: apiKey, model: selectedModel)
        case .ollama: return OllamaProvider(baseURL: ollamaURL, model: selectedModel)
        }
    }
}

