import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedProvider: AIProvider = .gemini
    @State private var selectedModel: String = AIProvider.gemini.defaultModel
    @State private var apiKeyInput: String = ""
    @State private var ollamaURL: String = OllamaConfig.defaultURL
    @State private var hasAPIKey: Bool = false
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false
    @State private var speechRate: Float = 0.5
    @State private var speechPitch: Float = 1.1
    @State private var selectedCharacterId: String = "default"

    let characters = CharacterPack.defaultPacks
    var memoryStore: MemoryStore

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
                        loadAPIKey()
                    }

                    Picker("Model", selection: $selectedModel) {
                        ForEach(selectedProvider.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } header: {
                    Label("AI Provider", systemImage: "cpu")
                }

                // MARK: - API Key
                if selectedProvider.requiresAPIKey {
                    Section {
                        if hasAPIKey {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(String(repeating: "\u{2022}", count: 20))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") {
                                    hasAPIKey = false
                                    apiKeyInput = ""
                                }
                                .font(.caption)
                                .tint(.orange)
                            }
                        } else {
                            SecureField("Enter API Key", text: $apiKeyInput)
                                .textContentType(.password)
                                .autocorrectionDisabled()

                            if !apiKeyInput.isEmpty {
                                Button {
                                    saveAPIKey()
                                } label: {
                                    HStack {
                                        Image(systemName: "key.fill")
                                        Text("Save to Keychain")
                                    }
                                }
                                .tint(.orange)
                            }
                        }

                        Text("Stored securely in iOS Keychain only. Never sent anywhere.")
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

                        Text("Default: \(OllamaConfig.defaultURL)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                // MARK: - Voice Settings
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech Rate: \(String(format: "%.1f", speechRate))")
                            .font(.subheadline)
                        Slider(value: $speechRate, in: 0.1...1.0)
                            .tint(.orange)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pitch: \(String(format: "%.1f", speechPitch))")
                            .font(.subheadline)
                        Slider(value: $speechPitch, in: 0.5...2.0)
                            .tint(.orange)
                    }
                } header: {
                    Label("Voice", systemImage: "waveform")
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
                    Label("Character", systemImage: "bird.fill")
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
                    Text("Open Source AI Owl Assistant — MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                    .tint(.orange)
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
