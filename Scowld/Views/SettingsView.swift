import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasChanges = false
    @State private var showClearConfirmation = false
    @State private var showAPIKey = false
    @State private var showElevenLabsKey = false

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
    @State private var speechRate: Float = 0.95
    @State private var speechPitch: Float = 1.2

    // MARK: - STT Settings
    @State private var sttBackend: String = "native_ios"

    // MARK: - Character Settings
    @State private var characterName: String = "Stella"
    @State private var systemPrompt: String = ""

    private static let defaultSystemPrompt = "You are a warm, cheerful, and expressive AI companion. You're friendly, playful, and genuinely care about the person you're talking to. You speak naturally and conversationally — like a close friend. Keep responses concise (1-3 sentences). Be expressive and show personality."

    // Vision is handled automatically by the selected LLM provider

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
                    .onChange(of: selectedModel) { hasChanges = true }
                } header: {
                    Label("AI Provider (LLM)", systemImage: "cpu")
                } footer: {
                    Text("Powers the AI responses in conversations.")
                }

                // MARK: - LLM API Key
                if selectedProvider.requiresAPIKey {
                    Section {
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

                // MARK: - TTS (Text-to-Speech)
                Section {
                    Picker("Backend", selection: $ttsBackend) {
                        Text("ElevenLabs").tag("elevenlabs")
                        Text("OpenAI TTS").tag("openai_tts")
                        Text("Native iOS").tag("native_ios")
                        Text("None").tag("none")
                    }
                    .onChange(of: ttsBackend) { hasChanges = true }

                    if ttsBackend == "native_ios" {
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

                // MARK: - OpenAI TTS Note
                if ttsBackend == "openai_tts" {
                    Section {
                        Text("Uses the OpenAI API key from your AI Provider settings (if OpenAI is selected), or enter one below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if selectedProvider != .openai {
                            HStack {
                                SecureField("OpenAI API Key for TTS", text: Binding(
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
                            }
                        }
                    } header: {
                        Label("OpenAI TTS", systemImage: "speaker.wave.2.circle")
                    }
                }

                // MARK: - ElevenLabs Settings
                if ttsBackend == "elevenlabs" {
                    Section {
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
                        ForEach(STTBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend.rawValue)
                        }
                    }
                    .onChange(of: sttBackend) { hasChanges = true }
                } header: {
                    Label("Speech-to-Text", systemImage: "mic")
                } footer: {
                    Text((STTBackend(rawValue: sttBackend) ?? .nativeIOS).footerText)
                }

                // MARK: - Cloud STT API Key
                if let backend = STTBackend(rawValue: sttBackend), backend.requiresAPIKey {
                    Section {
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

                        Text("Stored securely in iOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Label("\(backend.displayName) API Key", systemImage: "key")
                    }
                }



                // MARK: - Terminal (SSH)
                Section {
                    NavigationLink {
                        TerminalSettingsView()
                    } label: {
                        HStack {
                            Label("Configure SSH", systemImage: "terminal")
                            Spacer()
                            if SSHManager.shared.isConnected {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption2)
                            }
                        }
                    }
                } header: {
                    Label("Terminal (SSH)", systemImage: "terminal.fill")
                } footer: {
                    Text("Let your AI companion run commands on your Mac via SSH.")
                }

                // MARK: - Character
                Section {
                    TextField("Name", text: $characterName)
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
                    Text("Defines your AI companion's personality and behavior.")
                }

                // MARK: - Memory Management
                Section {
                    HStack {
                        Text("Stored Memories")
                        Spacer()
                        Text("\(memoryStore.totalMemoryCount)")
                            .foregroundStyle(.amicaBlue)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(.amicaBlue.opacity(0.15), in: Capsule())
                    }

                    NavigationLink {
                        MemoryView(memoryStore: memoryStore)
                    } label: {
                        Label("Browse Memories", systemImage: "brain.head.profile.fill")
                    }

                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All Memories", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .alert("Clear All Memories?", isPresented: $showClearConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear All", role: .destructive) {
                            memoryStore.clearAllMemories()
                        }
                    } message: {
                        Text("This will permanently delete all stored memories. This cannot be undone.")
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
                    Link(destination: URL(string: "https://scowld.vercel.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://scowld.vercel.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                    Text("Open Source AI Assistant — MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Character model: Arbius AI (MIT)")
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
                        dismiss()
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
        ollamaURL = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
        speechRate = defaults.float(forKey: "speechRate")
        if speechRate == 0 { speechRate = 0.95 }
        speechPitch = defaults.float(forKey: "speechPitch")
        if speechPitch == 0 { speechPitch = 1.2 }
        // Amica backend settings
        ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "native_ios"
        sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "native_ios"
        characterName = defaults.string(forKey: "character_name") ?? "Stella"
        systemPrompt = defaults.string(forKey: "system_prompt") ?? Self.defaultSystemPrompt
        elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "mHX7OoPk2G45VMAuinIt"

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
        defaults.set(characterName, forKey: "character_name")
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
        hasAPIKey = KeychainManager.exists(key: selectedProvider.keychainKey)
    }
}

