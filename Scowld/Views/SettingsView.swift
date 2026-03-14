import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: AIProvider = .gemini
    @State private var selectedModel: String = AIProvider.gemini.defaultModel
    @State private var apiKeyInput: String = ""
    @State private var ollamaURL: String = OllamaConfig.defaultURL
    @State private var hasAPIKey: Bool = false
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false
    @State private var speechRate: Float = 0.5
    @State private var speechPitch: Float = 1.1

    // Character selection
    @State private var selectedCharacterId: String = "default"
    let characters = CharacterPack.defaultPacks

    // Memory
    var memoryStore: MemoryStore

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - AI Provider
                Section("AI Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: selectedProvider) {
                        selectedModel = selectedProvider.defaultModel
                        loadAPIKey()
                    }

                    Picker("Model", selection: $selectedModel) {
                        ForEach(selectedProvider.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                // MARK: - API Key
                if selectedProvider.requiresAPIKey {
                    Section("API Key") {
                        if hasAPIKey {
                            HStack {
                                Text(String(repeating: "\u{2022}", count: 20))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") {
                                    hasAPIKey = false
                                    apiKeyInput = ""
                                }
                                .font(.caption)
                            }
                        } else {
                            SecureField("Enter API Key", text: $apiKeyInput)
                                .textContentType(.password)
                                .autocorrectionDisabled()

                            if !apiKeyInput.isEmpty {
                                Button("Save Key") {
                                    saveAPIKey()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }

                        Text("Stored securely in iOS Keychain only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Ollama Settings
                if selectedProvider == .ollama {
                    Section("Ollama Configuration") {
                        TextField("Server URL", text: $ollamaURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Text("Default: \(OllamaConfig.defaultURL)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Test Connection
                Section("Connection") {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(isTesting || (!hasAPIKey && selectedProvider.requiresAPIKey && apiKeyInput.isEmpty))

                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.starts(with: "Success") ? .green : .red)
                    }
                }

                // MARK: - Voice Settings
                Section("Voice") {
                    VStack(alignment: .leading) {
                        Text("Speech Rate: \(String(format: "%.1f", speechRate))")
                        Slider(value: $speechRate, in: 0.1...1.0)
                            .tint(.orange)
                    }

                    VStack(alignment: .leading) {
                        Text("Pitch: \(String(format: "%.1f", speechPitch))")
                        Slider(value: $speechPitch, in: 0.5...2.0)
                            .tint(.orange)
                    }
                }

                // MARK: - Character
                Section("Character") {
                    ForEach(characters) { character in
                        Button {
                            selectedCharacterId = character.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(character.name)
                                        .foregroundStyle(.primary)
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
                }

                // MARK: - Memory Management
                Section("Memory") {
                    HStack {
                        Text("Stored Memories")
                        Spacer()
                        Text("\(memoryStore.totalMemoryCount)")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink("Browse Memories") {
                        MemoryView(memoryStore: memoryStore)
                    }

                    Button("Clear All Memories", role: .destructive) {
                        memoryStore.clearAllMemories()
                    }
                }

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("Scowld")
                        Spacer()
                        Text("v1.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("Open Source AI Owl Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
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
        if speechRate == 0 { speechRate = 0.5 }
        speechPitch = defaults.float(forKey: "speechPitch")
        if speechPitch == 0 { speechPitch = 1.1 }
        selectedCharacterId = defaults.string(forKey: "selectedCharacter") ?? "default"
        loadAPIKey()
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
        defaults.set(selectedModel, forKey: "selectedModel")
        defaults.set(speechRate, forKey: "speechRate")
        defaults.set(speechPitch, forKey: "speechPitch")
        defaults.set(selectedCharacterId, forKey: "selectedCharacter")

        if selectedProvider == .ollama {
            KeychainManager.save(key: OllamaConfig.keychainURLKey, value: ollamaURL)
        }
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

    // MARK: - Test Connection

    private func testConnection() async {
        isTesting = true
        testResult = ""

        defer { isTesting = false }

        do {
            let provider = buildProvider()
            let response = try await provider.generate(
                messages: [ChatMessage(role: .user, content: "Say 'Connection successful!' in exactly those words.")],
                systemPrompt: "You are a test assistant. Respond with exactly: Connection successful!"
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
        case .gemini:
            return GeminiProvider(apiKey: apiKey, model: selectedModel)
        case .openai:
            return OpenAIProvider(apiKey: apiKey, model: selectedModel)
        case .claude:
            return ClaudeProvider(apiKey: apiKey, model: selectedModel)
        case .ollama:
            return OllamaProvider(baseURL: ollamaURL, model: selectedModel)
        }
    }
}
