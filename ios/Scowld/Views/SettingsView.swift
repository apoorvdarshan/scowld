import SwiftUI
import UIKit

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedLanguageID = HostedServiceConfig.deviceLanguageID
    @State private var showAICaption = false
    @State private var isLoadingSettings = false
    @State private var selectedAIProviderID = AIProvider.gemini.rawValue
    @State private var selectedAIModel = AIProvider.gemini.defaultModel
    @State private var aiModelIsCustom = false
    @State private var selectedVoice = AIProvider.gemini.defaultVoice
    @State private var aiAPIKey = ""
    @State private var hasSavedAIAPIKey = false
    @State private var aiSettingsMessage: String?
    // MARK: - Secret visibility
    @State private var revealAIKey = false

    // MARK: - Character Settings
    @State private var hasCharacterChanges = false
    @State private var characterName: String = ""
    @State private var selectedAvatar: String = "AvatarSample_A"
    @State private var systemPrompt: String = ""
    @State private var savedCharacterName: String = ""
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
                        footer: "Language sets the language she answers in. Captions show what she says while she talks."
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
                                .accessibilityIdentifier("settings.captions")
                                .onChange(of: showAICaption) {
                                    guard !isLoadingSettings else { return }
                                    saveDisplaySettings()
                                }
                        }
                    }

                    aiProviderSection

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
                                TextField("Bella", text: $characterName)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("settings.character.name")
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
                                ZStack(alignment: .topLeading) {
                                    if systemPrompt.isEmpty {
                                        Text(Self.defaultSystemPrompt)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 8)
                                            .allowsHitTesting(false)
                                    }
                                    TextEditor(text: $systemPrompt)
                                        .frame(minHeight: 112)
                                        .font(.body)
                                        .scrollContentBackground(.hidden)
                                        .onChange(of: systemPrompt) { markCharacterChanged() }
                                }
                                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                clearCharacterDefaults()
                            } label: {
                                Label("Clear", systemImage: "arrow.counterclockwise")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(canClearCharacter ? Color.red : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canClearCharacter)
                            .accessibilityLabel("Clear custom name and system prompt")

                            Spacer()

                            Button {
                                saveCharacterSettings()
                            } label: {
                                Label("Save Character", systemImage: "checkmark.circle.fill")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(hasCharacterChanges ? Color.amicaBlue : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasCharacterChanges)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
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
            "Live Voice",
            icon: "waveform.and.mic",
            footer: "Scowld streams your voice to the provider you choose and plays her voice back. Your API key stays in the iOS Keychain and is sent only to that provider."
        ) {
            settingRow {
                Picker("Provider", selection: $selectedAIProviderID) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.ai.provider")
                .onChange(of: selectedAIProviderID) {
                    guard !isLoadingSettings else { return }
                    loadAIProviderSettings()
                }
            }

            modelSelectionRows(
                models: selectedAIProvider.availableModels,
                selection: $selectedAIModel,
                isCustom: $aiModelIsCustom,
                identifier: "settings.ai"
            )

            settingRow {
                Picker("Voice", selection: $selectedVoice) {
                    ForEach(selectedAIProvider.voices) { voice in
                        Text("\(voice.name) - \(voice.style)").tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.ai.voice")
            }

            settingRow {
                apiKeyField(placeholder: aiAPIKeyPlaceholder, text: $aiAPIKey, isRevealed: $revealAIKey, identifier: "settings.ai.apiKey")
            }

            settingsActionRow(
                title: String.localizedStringWithFormat(
                    NSLocalizedString("Get your %@ API key", comment: "Link to the provider's API key page"),
                    selectedAIProvider.shortName
                ),
                subtitle: selectedAIProvider.keyHost,
                systemImage: "key.fill"
            ) {
                openURL(selectedAIProvider.keyURL)
            }

            if selectedAIProvider.cameraSupport == .unsupported {
                settingsInfoRow(
                    title: NSLocalizedString("Grok Voice can't see the camera. Choose Gemini or OpenAI for vision.", comment: "xAI camera note"),
                    systemImage: "eye.slash"
                )
            }

            glassSaveRow(status: aiSettingsMessage ?? aiSaveSubtitle, identifier: "settings.ai") {
                saveAISettings()
            }
        }
    }

    /// API-key entry with an eye toggle to reveal/hide the secret.
    @ViewBuilder
    private func apiKeyField(
        placeholder: String,
        text: Binding<String>,
        isRevealed: Binding<Bool>,
        identifier: String
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
        .accessibilityIdentifier(identifier)

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
        identifier: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("\(identifier).status")
            } else {
                Spacer(minLength: 0)
            }
            liquidGlassSaveButton(isDisabled: isDisabled, action: action)
                .accessibilityIdentifier("\(identifier).save")
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
        isCustom: Binding<Bool>,
        identifier: String
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
            .accessibilityIdentifier("\(identifier).model")
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
                "This iPhone language isn't in the list, so she answers in the language you speak.",
                comment: "Unsupported device language description"
            )
        default:
            return ScowldLanguageLibrary.option(for: selectedLanguageID).map {
                String.localizedStringWithFormat(
                    NSLocalizedString("She answers in %@.", comment: "Selected service language description"),
                    NSLocalizedString($0.name, comment: "Language name")
                )
            }
        }
    }

    private var selectedAIProvider: AIProvider {
        AIProvider(rawValue: selectedAIProviderID) ?? .gemini
    }

    private var aiAPIKeyPlaceholder: String {
        hasSavedAIAPIKey ? "Saved API key - type to replace" : "\(selectedAIProvider.shortName) API key"
    }

    private var aiSaveSubtitle: String {
        hasSavedAIAPIKey ? "Key saved in Keychain" : "Add a key before chatting"
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        isLoadingSettings = true
        HostedServiceConfig.applyBYOKDefaults()

        let defaults = UserDefaults.standard
        selectedAIProviderID = HostedServiceConfig.selectedProvider().rawValue
        loadAIProviderSettings(resetMessage: false)
        selectedLanguageID = HostedServiceConfig.selectedServiceLanguageID()
        let storedCharacterName = defaults.string(forKey: "character_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        characterName = storedCharacterName
        selectedAvatar = defaults.string(forKey: "selected_avatar") ?? "AvatarSample_A"
        let storedSystemPrompt = defaults.string(forKey: "system_prompt") ?? ""
        systemPrompt = storedSystemPrompt == Self.defaultSystemPrompt ? "" : storedSystemPrompt
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
        selectedVoice = HostedServiceConfig.selectedVoice(for: provider)
        aiAPIKey = KeychainManager.load(key: provider.keychainKey) ?? ""
        hasSavedAIAPIKey = !aiAPIKey.isEmpty
        if resetMessage {
            aiSettingsMessage = nil
        }
    }

    private func saveAISettings() {
        dismissKeyboard()
        let defaults = UserDefaults.standard
        let provider = selectedAIProvider
        let model = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(provider.rawValue, forKey: HostedServiceConfig.providerDefaultsKey)
        defaults.set(model.isEmpty ? provider.defaultModel : model, forKey: provider.modelDefaultsKey)
        defaults.set(selectedVoice, forKey: provider.voiceDefaultsKey)
        saveKeyIfNeeded(aiAPIKey, key: provider.keychainKey)

        hasSavedAIAPIKey = KeychainManager.exists(key: provider.keychainKey)
        aiSettingsMessage = "Saved"
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func saveKeyIfNeeded(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = KeychainManager.save(key: key, value: trimmed)
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

    private var canClearCharacter: Bool {
        !characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Reset the custom name and system prompt back to their placeholder defaults.
    /// Persisted on the next Save (empty name resolves to Bella; empty prompt to the default).
    private func clearCharacterDefaults() {
        dismissKeyboard()
        characterName = ""
        systemPrompt = ""
        markCharacterChanged()
    }

    private func saveAvatarSettings() {
        UserDefaults.standard.set(selectedAvatar, forKey: "selected_avatar")
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
    }

    private func saveCharacterSettings() {
        dismissKeyboard()
        let defaults = UserDefaults.standard
        HostedServiceConfig.applyBYOKDefaults()

        let trimmedCharacterName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        characterName = trimmedCharacterName
        defaults.set(trimmedCharacterName, forKey: "character_name")

        // An empty field means "use the default." Store the default text so the
        // effective prompt is unchanged, while the field keeps showing it as a placeholder.
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedSystemPrompt.isEmpty ? Self.defaultSystemPrompt : systemPrompt, forKey: "system_prompt")

        savedCharacterName = trimmedCharacterName
        savedSystemPrompt = systemPrompt
        hasCharacterChanges = false
        NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
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
