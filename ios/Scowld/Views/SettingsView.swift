import SwiftUI
import AVFoundation

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVoicePickerID = HostedServiceConfig.defaultElevenLabsVoiceID
    @State private var customVoiceID = ""
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewError: String?
    @State private var selectedLanguageID = HostedServiceConfig.autoLanguageID
    @State private var showAICaption = false
    @State private var isLoadingSettings = false

    // MARK: - Character Settings
    @State private var hasCharacterChanges = false
    @State private var characterName: String = "Stella"
    @State private var selectedAvatar: String = "AvatarSample_A"
    @State private var systemPrompt: String = ""
    @State private var savedCharacterName: String = "Stella"
    @State private var savedSelectedAvatar: String = "AvatarSample_A"
    @State private var savedSystemPrompt: String = ""

    var showsDismissControls = true

    private static let defaultSystemPrompt = "You are a warm, cheerful, and expressive AI companion. You're friendly, playful, and genuinely care about the person you're talking to. You speak naturally and conversationally — like a close friend. Keep responses concise (1-3 sentences). Be expressive and show personality."

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Language", selection: $selectedLanguageID) {
                        Text("Auto").tag(HostedServiceConfig.autoLanguageID)
                        Text("iPhone Language (\(HostedServiceConfig.currentDeviceLanguageName()))")
                            .tag(HostedServiceConfig.deviceLanguageID)
                        ForEach(ScowldLanguageLibrary.options) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    .onChange(of: selectedLanguageID) {
                        guard !isLoadingSettings else { return }
                        saveLanguageSettings()
                    }

                    if let selectedLanguageDescription {
                        Text(selectedLanguageDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Show AI captions", isOn: $showAICaption)
                        .onChange(of: showAICaption) {
                            guard !isLoadingSettings else { return }
                            saveDisplaySettings()
                        }
                } header: {
                    Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                } footer: {
                    Text("Language applies to both Deepgram speech recognition and ElevenLabs speech. Captions control the assistant's spoken response overlay.")
                }

                Section {
                    Picker("Voice", selection: $selectedVoicePickerID) {
                        ForEach(ScowldVoiceLibrary.presetVoices) { voice in
                            Text(voice.name).tag(voice.voiceID)
                        }
                        Text("Custom Voice ID").tag(ScowldVoiceLibrary.customID)
                    }
                    .onChange(of: selectedVoicePickerID) {
                        guard !isLoadingSettings else { return }
                        saveSelectedVoice()
                        resetPreviewState()
                    }

                    if selectedVoicePickerID == ScowldVoiceLibrary.customID {
                        TextField("ElevenLabs Voice ID", text: $customVoiceID)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: customVoiceID) {
                                guard !isLoadingSettings else { return }
                                saveSelectedVoice()
                                resetPreviewState()
                            }

                        Link(destination: URL(string: "https://elevenlabs.io/app/voice-library")!) {
                            Label("Where to get a custom voice ID", systemImage: "info.circle")
                        }
                        .font(.caption)
                    } else if let voice = ScowldVoiceLibrary.option(for: selectedVoicePickerID) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voice.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(voice.voiceID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }

                    Button {
                        playBundledVoicePreview()
                    } label: {
                        Label(previewButtonTitle, systemImage: previewButtonIcon)
                    }
                    .disabled(!selectedVoiceHasBundledPreview)

                    if let previewError {
                        Text(previewError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Preset samples are bundled in the app and play locally from this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Voice", systemImage: "speaker.wave.3")
                } footer: {
                    Text("The selected voice ID is used for production ElevenLabs speech through the hosted backend.")
                }

                Section {
                    Picker("Avatar", selection: $selectedAvatar) {
                        ForEach(CharacterPack.defaultPacks) { pack in
                            Text(pack.name).tag(pack.fileName)
                        }
                    }
                    .onChange(of: selectedAvatar) { markCharacterChanged() }

                    TextField("Custom Name (optional)", text: $characterName)
                        .autocorrectionDisabled()
                        .onChange(of: characterName) { markCharacterChanged() }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $systemPrompt)
                            .frame(minHeight: 100)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .onChange(of: systemPrompt) { markCharacterChanged() }
                    }

                    Button {
                        saveCharacterSettings()
                    } label: {
                        Label("Save Character", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(hasCharacterChanges ? .amicaBlue : .secondary)
                    }
                    .disabled(!hasCharacterChanges)
                } header: {
                    Label("Character", systemImage: "person.fill")
                } footer: {
                    Text("Use Save Character after changing the avatar, custom name, or system prompt.")
                }

                Section {
                    labeledValue("AI", value: "Gemini 3 Flash")
                    labeledValue("Speech-to-Text", value: "Deepgram Nova-3")
                    labeledValue("Text-to-Speech", value: "ElevenLabs")
                } header: {
                    Label("Managed Services", systemImage: "cloud")
                } footer: {
                    Text("Provider keys are handled by Scowld's hosted backend, so they can be rotated without an App Store update.")
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
            }
        }
        .onAppear { loadSettings() }
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedPreviewVoiceID: String {
        ScowldVoiceLibrary.voiceID(for: selectedVoicePickerID, customVoiceID: customVoiceID)
    }

    private var previewButtonTitle: String {
        selectedVoiceHasBundledPreview ? "Play sample" : "Sample unavailable"
    }

    private var previewButtonIcon: String {
        selectedVoiceHasBundledPreview ? "play.circle.fill" : "exclamationmark.circle"
    }

    private var selectedVoiceHasBundledPreview: Bool {
        BundledElevenLabsVoicePreviews.hasPreview(forVoiceID: selectedPreviewVoiceID)
    }

    private var selectedLanguageDescription: String? {
        switch selectedLanguageID {
        case HostedServiceConfig.autoLanguageID:
            return "Auto detects speech language and lets text-to-speech infer the language from the response."
        case HostedServiceConfig.deviceLanguageID:
            if let code = HostedServiceConfig.currentDeviceLanguageCode(),
               let language = ScowldLanguageLibrary.option(for: code) {
                return "Uses this iPhone's current language when supported: \(language.name)."
            }
            return "This iPhone language is not in the supported shortcut list, so providers will use auto."
        default:
            return ScowldLanguageLibrary.option(for: selectedLanguageID).map {
                "Forces STT and TTS toward \($0.name)."
            }
        }
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        isLoadingSettings = true
        HostedServiceConfig.applyManagedDefaults()

        let defaults = UserDefaults.standard
        let voiceID = HostedServiceConfig.selectedElevenLabsVoiceID()
        selectedVoicePickerID = ScowldVoiceLibrary.pickerID(for: voiceID)
        customVoiceID = selectedVoicePickerID == ScowldVoiceLibrary.customID ? voiceID : ""
        selectedLanguageID = HostedServiceConfig.selectedServiceLanguageID()
        characterName = defaults.string(forKey: "character_name") ?? ""
        selectedAvatar = defaults.string(forKey: "selected_avatar") ?? "AvatarSample_A"
        systemPrompt = defaults.string(forKey: "system_prompt") ?? Self.defaultSystemPrompt
        savedCharacterName = characterName
        savedSelectedAvatar = selectedAvatar
        savedSystemPrompt = systemPrompt
        showAICaption = defaults.bool(forKey: "show_ai_caption")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoadingSettings = false
            hasCharacterChanges = false
        }
    }

    private func saveSelectedVoice() {
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyManagedDefaults()
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
            selectedAvatar != savedSelectedAvatar ||
            systemPrompt != savedSystemPrompt
    }

    private func saveCharacterSettings() {
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyManagedDefaults()
        defaults.set(characterName, forKey: "character_name")
        defaults.set(selectedAvatar, forKey: "selected_avatar")
        defaults.set(systemPrompt, forKey: "system_prompt")

        savedCharacterName = characterName
        savedSelectedAvatar = selectedAvatar
        savedSystemPrompt = systemPrompt
        hasCharacterChanges = false
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func playBundledVoicePreview() {
        previewError = nil
        previewPlayer?.stop()

        guard let url = BundledElevenLabsVoicePreviews.url(forVoiceID: selectedPreviewVoiceID) else {
            previewError = "No bundled sample is available for this custom voice ID."
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
            previewError = "Could not play sample: \(error.localizedDescription)"
        }
    }
}
