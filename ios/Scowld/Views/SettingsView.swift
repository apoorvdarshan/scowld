import SwiftUI
import AVFoundation
import UIKit

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedVoicePickerID = HostedServiceConfig.defaultElevenLabsVoiceID
    @State private var customVoiceID = ""
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewError: String?
    @State private var selectedLanguageID = HostedServiceConfig.deviceLanguageID
    @State private var showAICaption = false
    @State private var isLoadingSettings = false
    @State private var selectedAIProviderID = AIProvider.gemini.rawValue
    @State private var selectedAIModel = AIProvider.gemini.defaultModel
    @State private var aiModelIsCustom = false
    @State private var aiAPIKey = ""
    @State private var hasSavedAIAPIKey = false
    @State private var ollamaURL = OllamaConfig.defaultURL
    @State private var aiSettingsMessage: String?
    @State private var selectedSTTBackendID = STTBackend.nativeIOS.rawValue
    @State private var selectedSTTModel = STTBackend.nativeIOS.defaultModel
    @State private var sttModelIsCustom = false
    @State private var sttAPIKey = ""
    @State private var hasSavedSTTAPIKey = false
    @State private var sttSettingsMessage: String?
    @State private var selectedTTSBackendID = TTSBackend.elevenLabs.rawValue
    @State private var selectedTTSModel = TTSBackend.elevenLabs.defaultModel
    @State private var ttsModelIsCustom = false
    @State private var ttsAPIKey = ""
    @State private var hasSavedTTSAPIKey = false
    @State private var ttsSettingsMessage: String?

    // MARK: - Secret visibility
    @State private var revealAIKey = false
    @State private var revealSTTKey = false
    @State private var revealTTSKey = false

    // MARK: - Character Settings
    @State private var hasCharacterChanges = false
    @State private var characterName: String = "Bella"
    @State private var selectedAvatar: String = "AvatarSample_A"
    @State private var systemPrompt: String = ""
    @State private var savedCharacterName: String = "Bella"
    @State private var savedSystemPrompt: String = ""

    var showsDismissControls = true

    private static let defaultSystemPrompt = "You are a warm, cheerful, and expressive AI companion. You're friendly, playful, and genuinely care about the person you're talking to. You speak naturally and conversationally — like a close friend. Keep responses concise (1-3 sentences). Be expressive and show personality."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection(
                        "Conversation",
                        icon: "bubble.left.and.bubble.right",
                        footer: "Language helps supported speech providers choose transcription and voice output language. Captions control the assistant's spoken response overlay."
                    ) {
                        settingRow {
                            Picker("Language", selection: $selectedLanguageID) {
                                Text(
                                    String.localizedStringWithFormat(
                                        NSLocalizedString("iPhone Language (%@)", comment: "Device language picker option"),
                                        HostedServiceConfig.currentDeviceLanguageName()
                                    )
                                )
                                    .tag(HostedServiceConfig.deviceLanguageID)
                                ForEach(ScowldLanguageLibrary.options) { language in
                                    Text(LocalizedStringKey(language.name)).tag(language.code)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedLanguageID) {
                                guard !isLoadingSettings else { return }
                                saveLanguageSettings()
                            }
                        }

                        if let selectedLanguageDescription {
                            settingsInfoRow(
                                title: selectedLanguageDescription,
                                systemImage: "globe"
                            )
                        }

                        settingRow {
                            Toggle("Show AI captions", isOn: $showAICaption)
                                .tint(.amicaBlue)
                                .onChange(of: showAICaption) {
                                    guard !isLoadingSettings else { return }
                                    saveDisplaySettings()
                                }
                        }
                    }

                    aiProviderSection
                    sttProviderSection

                    settingsSection(
                        "Text-to-Speech",
                        icon: "speaker.wave.3",
                        footer: "ElevenLabs speech uses your API key from Keychain. Celine, Claire, and custom voice IDs are supported."
                    ) {
                        settingRow {
                            Picker("Provider", selection: $selectedTTSBackendID) {
                                ForEach(TTSBackend.allCases, id: \.rawValue) { backend in
                                    Text(backend.displayName).tag(backend.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedTTSBackendID) {
                                guard !isLoadingSettings else { return }
                                loadTTSBackendSettings()
                            }
                        }

                        modelSelectionRows(
                            models: selectedTTSBackend.availableModels,
                            selection: $selectedTTSModel,
                            isCustom: $ttsModelIsCustom
                        )

                        settingRow {
                            apiKeyField(placeholder: ttsAPIKeyPlaceholder, text: $ttsAPIKey, isRevealed: $revealTTSKey)
                        }

                        settingRow {
                            Picker("Voice", selection: $selectedVoicePickerID) {
                                ForEach(ScowldVoiceLibrary.presetVoices) { voice in
                                    Text(LocalizedStringKey(voice.name)).tag(voice.voiceID)
                                }
                                Text("Custom Voice ID").tag(ScowldVoiceLibrary.customID)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedVoicePickerID) {
                                guard !isLoadingSettings else { return }
                                saveSelectedVoice()
                                resetPreviewState()
                            }
                        }

                        if selectedVoicePickerID == ScowldVoiceLibrary.customID {
                            settingRow {
                                TextField("ElevenLabs Voice ID", text: $customVoiceID)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: customVoiceID) {
                                        guard !isLoadingSettings else { return }
                                        saveSelectedVoice()
                                        resetPreviewState()
                                    }
                            }

                            settingsActionRow(
                                title: "Where to get a custom voice ID",
                                subtitle: "elevenlabs.io/app/voice-library",
                                systemImage: "info.circle"
                            ) {
                                openURL(URL(string: "https://elevenlabs.io/app/voice-library")!)
                            }
                        } else if let voice = ScowldVoiceLibrary.option(for: selectedVoicePickerID) {
                            settingRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedStringKey(voice.description))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(voice.voiceID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        settingsActionRow(
                            title: previewButtonTitle,
                            subtitle: selectedVoiceHasBundledPreview ? "Plays a bundled local sample" : nil,
                            systemImage: previewButtonIcon,
                            isDisabled: !selectedVoiceHasBundledPreview
                        ) {
                            playBundledVoicePreview()
                        }

                        if let previewError {
                            settingsInfoRow(title: previewError, systemImage: "exclamationmark.triangle.fill", color: .red)
                        }

                        settingsInfoRow(
                            title: "Preset samples are bundled in the app and play locally from this device.",
                            systemImage: "speaker.wave.2.fill"
                        )

                        glassSaveRow(status: ttsSettingsMessage ?? ttsSaveSubtitle) {
                            saveTTSSettings()
                        }
                    }

                    settingsSection(
                        "Character",
                        icon: "person.fill",
                        footer: "Avatar saves immediately. Use Save Character after changing the custom name or system prompt."
                    ) {
                        settingRow {
                            Picker("Avatar", selection: $selectedAvatar) {
                                ForEach(CharacterPack.defaultPacks) { pack in
                                    Text(pack.displayName).tag(pack.fileName)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: selectedAvatar) {
                                guard !isLoadingSettings else { return }
                                saveAvatarSettings()
                            }
                        }

                        settingRow {
                            HStack(spacing: 8) {
                                TextField("Add custom name", text: $characterName)
                                    .autocorrectionDisabled()
                                    .onChange(of: characterName) { markCharacterChanged() }

                                if !characterName.isEmpty {
                                    Button {
                                        characterName = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Clear custom name")
                                }
                            }
                        }

                        settingRow {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("System Prompt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $systemPrompt)
                                    .frame(minHeight: 112)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .onChange(of: systemPrompt) { markCharacterChanged() }
                            }
                        }

                        settingsActionRow(
                            title: "Save Character",
                            subtitle: hasCharacterChanges ? "Unsaved changes" : "No changes",
                            systemImage: "checkmark.circle.fill",
                            tint: hasCharacterChanges ? .amicaBlue : .secondary,
                            isDisabled: !hasCharacterChanges
                        ) {
                            saveCharacterSettings()
                        }
                    }

                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .background(KeyboardDismissInstaller())
            .toolbar {
                if showsDismissControls {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { loadSettings() }
    }

    private var aiProviderSection: some View {
        settingsSection(
            "BYOK AI",
            icon: "brain.head.profile",
            footer: "Scowld sends chat and optional vision requests directly to your selected provider using the key saved in Keychain."
        ) {
            settingRow {
                Picker("Provider", selection: $selectedAIProviderID) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedAIProviderID) {
                    guard !isLoadingSettings else { return }
                    loadAIProviderSettings()
                }
            }

            if selectedAIProvider == .ollama {
                settingRow {
                    TextField("Ollama URL", text: $ollamaURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            modelSelectionRows(
                models: selectedAIProvider.availableModels,
                selection: $selectedAIModel,
                isCustom: $aiModelIsCustom
            )

            if selectedAIProvider.requiresAPIKey {
                settingRow {
                    apiKeyField(placeholder: aiAPIKeyPlaceholder, text: $aiAPIKey, isRevealed: $revealAIKey)
                }
            }

            glassSaveRow(status: aiSettingsMessage ?? aiSaveSubtitle) {
                saveAISettings()
            }
        }
    }

    private var sttProviderSection: some View {
        settingsSection(
            "Speech-to-Text",
            icon: "waveform.badge.mic",
            footer: "Native iOS uses no API key. Cloud STT providers use your API key from Keychain."
        ) {
            settingRow {
                Picker("Provider", selection: $selectedSTTBackendID) {
                    ForEach(STTBackend.allCases, id: \.rawValue) { backend in
                        Text(backend.displayName).tag(backend.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedSTTBackendID) {
                    guard !isLoadingSettings else { return }
                    loadSTTBackendSettings()
                }
            }

            if !selectedSTTBackend.availableModels.isEmpty {
                modelSelectionRows(
                    models: selectedSTTBackend.availableModels,
                    selection: $selectedSTTModel,
                    isCustom: $sttModelIsCustom
                )
            }

            if selectedSTTBackend.requiresAPIKey {
                settingRow {
                    apiKeyField(placeholder: sttAPIKeyPlaceholder, text: $sttAPIKey, isRevealed: $revealSTTKey)
                }
            }

            settingsInfoRow(title: selectedSTTBackend.footerText, systemImage: "info.circle")

            glassSaveRow(status: sttSettingsMessage ?? sttSaveSubtitle) {
                saveSTTSettings()
            }
        }
    }

    /// API-key entry with an eye toggle to reveal/hide the secret.
    @ViewBuilder
    private func apiKeyField(
        placeholder: String,
        text: Binding<String>,
        isRevealed: Binding<Bool>
    ) -> some View {
        Group {
            if isRevealed.wrappedValue {
                TextField(placeholder, text: text)
            } else {
                SecureField(placeholder, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)

        Button {
            isRevealed.wrappedValue.toggle()
        } label: {
            Image(systemName: isRevealed.wrappedValue ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isRevealed.wrappedValue ? .amicaBlue : .secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed.wrappedValue ? "Hide key" : "Show key")
    }

    /// Footer row: optional status text on the left, Liquid Glass Save button on the right.
    private func glassSaveRow(
        status: String?,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            liquidGlassSaveButton(isDisabled: isDisabled, action: action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func liquidGlassSaveButton(
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label("Save", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(.amicaBlue)
            .disabled(isDisabled)
        } else {
            Button(action: action) {
                Label("Save", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [.amicaBlue, .amicaBlue.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .shadow(color: .amicaBlue.opacity(0.4), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
        }
    }

    private static let customModelTag = "__scowld_custom_model__"

    /// Single model row: a menu picker of preset models plus a "Custom model" option.
    /// The editable text field only appears when "Custom model" is selected, so the
    /// model name is never shown twice.
    @ViewBuilder
    private func modelSelectionRows(
        models: [String],
        selection: Binding<String>,
        isCustom: Binding<Bool>
    ) -> some View {
        settingRow {
            Picker("Model", selection: Binding(
                get: { isCustom.wrappedValue ? Self.customModelTag : selection.wrappedValue },
                set: { newValue in
                    if newValue == Self.customModelTag {
                        isCustom.wrappedValue = true
                    } else {
                        isCustom.wrappedValue = false
                        selection.wrappedValue = newValue
                    }
                }
            )) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
                Text("Custom model").tag(Self.customModelTag)
            }
            .pickerStyle(.menu)
        }

        if isCustom.wrappedValue {
            settingRow {
                TextField("Custom model name", text: selection)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        settingRow {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                content()
            }
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func settingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            settingsRowDivider
        }
    }

    private func settingsActionRow(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = .primary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(tint)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                settingsRowDivider
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
    }

    private func settingsInfoRow(
        title: String,
        systemImage: String,
        color: Color = .secondary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: Circle())

            Text(title)
                .font(.caption)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            settingsRowDivider
        }
    }

    private var settingsRowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 62)
    }

    private var selectedPreviewVoiceID: String {
        ScowldVoiceLibrary.voiceID(for: selectedVoicePickerID, customVoiceID: customVoiceID)
    }

    private var previewButtonTitle: String {
        selectedVoiceHasBundledPreview
            ? NSLocalizedString("Play sample", comment: "Play voice preview button")
            : NSLocalizedString("Sample unavailable", comment: "Disabled voice preview button")
    }

    private var previewButtonIcon: String {
        selectedVoiceHasBundledPreview ? "play.circle.fill" : "exclamationmark.circle"
    }

    private var selectedVoiceHasBundledPreview: Bool {
        BundledElevenLabsVoicePreviews.hasPreview(forVoiceID: selectedPreviewVoiceID)
    }

    private var selectedLanguageDescription: String? {
        switch selectedLanguageID {
        case HostedServiceConfig.deviceLanguageID:
            if let code = HostedServiceConfig.currentDeviceLanguageCode(),
               let language = ScowldLanguageLibrary.option(for: code) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("Uses this iPhone's current language when supported: %@.", comment: "Device language mode description"),
                    NSLocalizedString(language.name, comment: "Language name")
                )
            }
            return NSLocalizedString(
                "This iPhone language is not in the supported shortcut list, so providers will use auto.",
                comment: "Unsupported device language description"
            )
        default:
            return ScowldLanguageLibrary.option(for: selectedLanguageID).map {
                String.localizedStringWithFormat(
                    NSLocalizedString("Forces STT and TTS toward %@.", comment: "Selected service language description"),
                    NSLocalizedString($0.name, comment: "Language name")
                )
            }
        }
    }

    private var selectedAIProvider: AIProvider {
        AIProvider(rawValue: selectedAIProviderID) ?? .gemini
    }

    private var selectedSTTBackend: STTBackend {
        STTBackend(rawValue: selectedSTTBackendID) ?? .nativeIOS
    }

    private var selectedTTSBackend: TTSBackend {
        TTSBackend(rawValue: selectedTTSBackendID) ?? .elevenLabs
    }

    private var aiAPIKeyPlaceholder: String {
        hasSavedAIAPIKey ? "Saved API key - type to replace" : "\(selectedAIProvider.displayName) API key"
    }

    private var sttAPIKeyPlaceholder: String {
        hasSavedSTTAPIKey ? "Saved API key - type to replace" : "\(selectedSTTBackend.displayName) API key"
    }

    private var ttsAPIKeyPlaceholder: String {
        hasSavedTTSAPIKey ? "Saved API key - type to replace" : "ElevenLabs API key"
    }

    private var aiSaveSubtitle: String {
        selectedAIProvider.requiresAPIKey
            ? (hasSavedAIAPIKey ? "Key saved in Keychain" : "Add a key before chatting")
            : "No API key required"
    }

    private var sttSaveSubtitle: String {
        selectedSTTBackend.requiresAPIKey
            ? (hasSavedSTTAPIKey ? "Key saved in Keychain" : "Add a key for cloud STT")
            : "No API key required"
    }

    private var ttsSaveSubtitle: String {
        hasSavedTTSAPIKey ? "Key saved in Keychain" : "Add a key for spoken replies"
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        isLoadingSettings = true
        HostedServiceConfig.applyBYOKDefaults()

        let defaults = UserDefaults.standard
        selectedAIProviderID = defaults.string(forKey: "selectedProvider") ?? AIProvider.gemini.rawValue
        loadAIProviderSettings(resetMessage: false)
        selectedSTTBackendID = defaults.string(forKey: "amica_stt_backend") ?? STTBackend.nativeIOS.rawValue
        loadSTTBackendSettings(resetMessage: false)
        selectedTTSBackendID = defaults.string(forKey: "amica_tts_backend") ?? TTSBackend.elevenLabs.rawValue
        loadTTSBackendSettings(resetMessage: false)
        let voiceID = HostedServiceConfig.selectedElevenLabsVoiceID()
        selectedVoicePickerID = ScowldVoiceLibrary.pickerID(for: voiceID)
        customVoiceID = selectedVoicePickerID == ScowldVoiceLibrary.customID ? voiceID : ""
        selectedLanguageID = HostedServiceConfig.selectedServiceLanguageID()
        let storedCharacterName = defaults.string(forKey: "character_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        characterName = storedCharacterName.isEmpty ? "Bella" : storedCharacterName
        selectedAvatar = defaults.string(forKey: "selected_avatar") ?? "AvatarSample_A"
        systemPrompt = defaults.string(forKey: "system_prompt") ?? Self.defaultSystemPrompt
        savedCharacterName = characterName
        savedSystemPrompt = systemPrompt
        showAICaption = defaults.bool(forKey: "show_ai_caption")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoadingSettings = false
            hasCharacterChanges = false
        }
    }

    private func loadAIProviderSettings(resetMessage: Bool = true) {
        let provider = selectedAIProvider
        selectedAIModel = HostedServiceConfig.selectedModel(for: provider)
        aiModelIsCustom = !provider.availableModels.contains(selectedAIModel)
        aiAPIKey = ""
        hasSavedAIAPIKey = provider.requiresAPIKey && KeychainManager.exists(key: provider.keychainKey)
        ollamaURL = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
        if resetMessage {
            aiSettingsMessage = nil
        }
    }

    private func loadSTTBackendSettings(resetMessage: Bool = true) {
        let backend = selectedSTTBackend
        selectedSTTModel = STTBackend.selectedModel(for: backend)
        sttModelIsCustom = !backend.availableModels.isEmpty && !backend.availableModels.contains(selectedSTTModel)
        sttAPIKey = ""
        hasSavedSTTAPIKey = backend.requiresAPIKey && KeychainManager.exists(key: backend.keychainKey)
        if resetMessage {
            sttSettingsMessage = nil
        }
    }

    private func loadTTSBackendSettings(resetMessage: Bool = true) {
        let backend = selectedTTSBackend
        selectedTTSModel = TTSBackend.selectedModel(for: backend)
        ttsModelIsCustom = !backend.availableModels.isEmpty && !backend.availableModels.contains(selectedTTSModel)
        ttsAPIKey = ""
        hasSavedTTSAPIKey = KeychainManager.exists(key: backend.keychainKey)
        if resetMessage {
            ttsSettingsMessage = nil
        }
    }

    private func saveAISettings() {
        let defaults = UserDefaults.standard
        let provider = selectedAIProvider
        let model = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(provider.rawValue, forKey: "selectedProvider")
        defaults.set(model.isEmpty ? provider.defaultModel : model, forKey: provider.modelDefaultsKey)
        defaults.set(model.isEmpty ? provider.defaultModel : model, forKey: "selectedModel")

        if provider == .ollama {
            let url = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = KeychainManager.save(key: OllamaConfig.keychainURLKey, value: url.isEmpty ? OllamaConfig.defaultURL : url)
        } else {
            saveKeyIfNeeded(aiAPIKey, key: provider.keychainKey)
        }

        aiAPIKey = ""
        hasSavedAIAPIKey = provider.requiresAPIKey && KeychainManager.exists(key: provider.keychainKey)
        aiSettingsMessage = "Saved"
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveSTTSettings() {
        let defaults = UserDefaults.standard
        let backend = selectedSTTBackend
        let model = selectedSTTModel.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(backend.rawValue, forKey: "amica_stt_backend")
        if !backend.availableModels.isEmpty {
            defaults.set(model.isEmpty ? backend.defaultModel : model, forKey: backend.modelDefaultsKey)
        }

        if backend.requiresAPIKey {
            saveKeyIfNeeded(sttAPIKey, key: backend.keychainKey)
        }

        sttAPIKey = ""
        hasSavedSTTAPIKey = backend.requiresAPIKey && KeychainManager.exists(key: backend.keychainKey)
        sttSettingsMessage = "Saved"
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveTTSSettings() {
        let defaults = UserDefaults.standard
        let backend = selectedTTSBackend
        let model = selectedTTSModel.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(backend.rawValue, forKey: "amica_tts_backend")
        defaults.set(model.isEmpty ? backend.defaultModel : model, forKey: backend.modelDefaultsKey)
        defaults.set(model.isEmpty ? backend.defaultModel : model, forKey: "amica_elevenlabs_model")
        saveSelectedVoice()
        saveKeyIfNeeded(ttsAPIKey, key: backend.keychainKey)

        ttsAPIKey = ""
        hasSavedTTSAPIKey = KeychainManager.exists(key: backend.keychainKey)
        ttsSettingsMessage = "Saved"
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveKeyIfNeeded(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = KeychainManager.save(key: key, value: trimmed)
    }

    private func saveSelectedVoice() {
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyBYOKDefaults()
        defaults.set(
            ScowldVoiceLibrary.voiceID(for: selectedVoicePickerID, customVoiceID: customVoiceID),
            forKey: "amica_elevenlabs_voiceid"
        )
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveLanguageSettings() {
        UserDefaults.standard.set(selectedLanguageID, forKey: HostedServiceConfig.serviceLanguageDefaultsKey)
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveDisplaySettings() {
        UserDefaults.standard.set(showAICaption, forKey: "show_ai_caption")
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func markCharacterChanged() {
        guard !isLoadingSettings else { return }
        hasCharacterChanges =
            characterName != savedCharacterName ||
            systemPrompt != savedSystemPrompt
    }

    private func saveAvatarSettings() {
        UserDefaults.standard.set(selectedAvatar, forKey: "selected_avatar")
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveCharacterSettings() {
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyBYOKDefaults()
        let trimmedCharacterName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedName = trimmedCharacterName.isEmpty ? "Bella" : trimmedCharacterName
        characterName = savedName
        defaults.set(trimmedCharacterName, forKey: "character_name")
        defaults.set(systemPrompt, forKey: "system_prompt")

        savedCharacterName = savedName
        savedSystemPrompt = systemPrompt
        hasCharacterChanges = false
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func playBundledVoicePreview() {
        previewError = nil
        previewPlayer?.stop()

        guard let url = BundledElevenLabsVoicePreviews.url(forVoiceID: selectedPreviewVoiceID) else {
            previewError = NSLocalizedString(
                "No bundled sample is available for this custom voice ID.",
                comment: "Missing voice preview error"
            )
            return
        }

        playPreviewAudio(from: url)
    }

    private func resetPreviewState() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewError = nil
    }

    private func playPreviewAudio(from url: URL) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            previewPlayer = player
        } catch {
            previewError = String.localizedStringWithFormat(
                NSLocalizedString("Could not play sample: %@", comment: "Voice preview playback error"),
                error.localizedDescription
            )
        }
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        InstallerView { window in
            context.coordinator.install(on: window)
        }
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.onWindowChange = { window in
            context.coordinator.install(on: window)
        }
        context.coordinator.install(on: view.window)
    }

    static func dismantleUIView(_ view: InstallerView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class InstallerView: UIView {
        var onWindowChange: (UIWindow?) -> Void

        init(onWindowChange: @escaping (UIWindow?) -> Void) {
            self.onWindowChange = onWindowChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func install(on window: UIWindow?) {
            guard self.window !== window else { return }
            uninstall()
            guard let window else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            self.window = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        @objc private func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !isTextInput(touch.view)
        }

        private func isTextInput(_ view: UIView?) -> Bool {
            guard let view else { return false }
            if view is UITextField || view is UITextView {
                return true
            }
            return isTextInput(view.superview)
        }
    }
}
