import SwiftUI
import AVFoundation

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasChanges = false
    @State private var selectedVoicePickerID = HostedServiceConfig.defaultElevenLabsVoiceID
    @State private var customVoiceID = ""
    @State private var previewPlayer: AVAudioPlayer?
    @State private var isPreviewLoading = false
    @State private var previewError: String?

    // MARK: - Character Settings
    @State private var characterName: String = "Stella"
    @State private var selectedAvatar: String = "AvatarSample_A"
    @State private var systemPrompt: String = ""

    var showsDismissControls = true

    private static let defaultSystemPrompt = "You are a warm, cheerful, and expressive AI companion. You're friendly, playful, and genuinely care about the person you're talking to. You speak naturally and conversationally — like a close friend. Keep responses concise (1-3 sentences). Be expressive and show personality."

    var body: some View {
        NavigationStack {
            List {
                Section {
                    labeledValue("AI", value: "Gemini 3.1 Pro")
                    labeledValue("Speech-to-Text", value: "Deepgram Nova-3")
                    labeledValue("Text-to-Speech", value: "ElevenLabs")
                } header: {
                    Label("Managed Services", systemImage: "cloud")
                } footer: {
                    Text("Provider keys are handled by Scowld's hosted backend, so they can be rotated without an App Store update.")
                }

                Section {
                    Picker("Voice", selection: $selectedVoicePickerID) {
                        ForEach(ScowldVoiceLibrary.presetVoices) { voice in
                            Text(voice.name).tag(voice.voiceID)
                        }
                        Text("Custom Voice ID").tag(ScowldVoiceLibrary.customID)
                    }
                    .onChange(of: selectedVoicePickerID) { hasChanges = true }
                    .onChange(of: selectedVoicePickerID) { resetPreviewState() }

                    if selectedVoicePickerID == ScowldVoiceLibrary.customID {
                        TextField("ElevenLabs Voice ID", text: $customVoiceID)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: customVoiceID) { hasChanges = true }
                            .onChange(of: customVoiceID) { resetPreviewState() }
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
                        playElevenLabsVoicePreview()
                    } label: {
                        if isPreviewLoading {
                            Label("Downloading sample", systemImage: "arrow.down.circle")
                        } else {
                            Label(previewButtonTitle, systemImage: previewButtonIcon)
                        }
                    }
                    .disabled(isPreviewLoading)

                    if let previewError {
                        Text(previewError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Samples download once from ElevenLabs through Scowld's backend, then play locally from this device.")
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

    private var selectedPreviewText: String {
        ScowldVoiceLibrary.option(for: selectedVoicePickerID)?.previewText
            ?? ScowldVoiceLibrary.defaultPreviewText
    }

    private var previewButtonTitle: String {
        ElevenLabsVoicePreviewCache.isCached(voiceID: selectedPreviewVoiceID) ? "Play sample" : "Download sample"
    }

    private var previewButtonIcon: String {
        ElevenLabsVoicePreviewCache.isCached(voiceID: selectedPreviewVoiceID) ? "play.circle.fill" : "arrow.down.circle.fill"
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        HostedServiceConfig.applyManagedDefaults()

        let defaults = UserDefaults.standard
        let voiceID = HostedServiceConfig.selectedElevenLabsVoiceID()
        selectedVoicePickerID = ScowldVoiceLibrary.pickerID(for: voiceID)
        customVoiceID = selectedVoicePickerID == ScowldVoiceLibrary.customID ? voiceID : ""
        characterName = defaults.string(forKey: "character_name") ?? ""
        selectedAvatar = defaults.string(forKey: "selected_avatar") ?? "AvatarSample_A"
        systemPrompt = defaults.string(forKey: "system_prompt") ?? Self.defaultSystemPrompt

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hasChanges = false
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyManagedDefaults()
        defaults.set(
            ScowldVoiceLibrary.voiceID(for: selectedVoicePickerID, customVoiceID: customVoiceID),
            forKey: "amica_elevenlabs_voiceid"
        )
        defaults.set(characterName, forKey: "character_name")
        defaults.set(selectedAvatar, forKey: "selected_avatar")
        defaults.set(systemPrompt, forKey: "system_prompt")

        hasChanges = false
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func playElevenLabsVoicePreview() {
        previewError = nil
        previewPlayer?.stop()
        isPreviewLoading = true

        let voiceID = selectedPreviewVoiceID
        let text = selectedPreviewText

        Task {
            do {
                let url = try await ElevenLabsVoicePreviewCache.localAudioURL(voiceID: voiceID, text: text)
                await MainActor.run {
                    isPreviewLoading = false
                    playPreviewAudio(from: url)
                }
            } catch {
                await MainActor.run {
                    isPreviewLoading = false
                    previewError = error.localizedDescription
                }
            }
        }
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
