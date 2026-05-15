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

    // MARK: - Character Settings
    @State private var hasCharacterChanges = false
    @State private var characterName: String = "Stella"
    @State private var selectedAvatar: String = "AvatarSample_A"
    @State private var systemPrompt: String = ""
    @State private var savedCharacterName: String = "Stella"
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
                        footer: "Language applies to both Deepgram speech recognition and ElevenLabs speech. Captions control the assistant's spoken response overlay."
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

                    settingsSection(
                        "Voice",
                        icon: "speaker.wave.3",
                        footer: "The selected voice ID is used for production ElevenLabs speech through the hosted backend."
                    ) {
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
                    }

                    settingsSection(
                        "Character",
                        icon: "person.fill",
                        footer: "Avatar saves immediately. Use Save Character after changing the custom name or system prompt."
                    ) {
                        settingRow {
                            Picker("Avatar", selection: $selectedAvatar) {
                                ForEach(CharacterPack.defaultPacks) { pack in
                                    Text(pack.name).tag(pack.fileName)
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
                                TextField("Custom Name (optional)", text: $characterName)
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

                    settingsSection(
                        "Managed Services",
                        icon: "cloud",
                        footer: "Provider keys are handled by Scowld's hosted backend, so they can be rotated without an App Store update."
                    ) {
                        labeledValue("AI", value: "Gemini 3 Flash")
                        labeledValue("Speech-to-Text", value: "Deepgram Nova-3")
                        labeledValue("Text-to-Speech", value: "ElevenLabs")
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
            systemPrompt != savedSystemPrompt
    }

    private func saveAvatarSettings() {
        UserDefaults.standard.set(selectedAvatar, forKey: "selected_avatar")
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveCharacterSettings() {
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyManagedDefaults()
        defaults.set(characterName, forKey: "character_name")
        defaults.set(systemPrompt, forKey: "system_prompt")

        savedCharacterName = characterName
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
