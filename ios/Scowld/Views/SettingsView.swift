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
    @State private var fetchedModels: [String] = []
    @State private var voicePreviewer = VoicePreviewer()
    @State private var liveMode: LiveMode = .premium
    @State private var premiumVoice = AIProvider.gemini.defaultVoice
    @State private var premiumSheet: PremiumSheet?
    @Environment(PremiumModel.self) private var premium
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
                        menuRow("Language", value: selectedLanguageName, identifier: "settings.language") {
                            Picker("Language", selection: $selectedLanguageID) {
                                Text("iPhone Language")
                                    .tag(HostedServiceConfig.deviceLanguageID)
                                ForEach(ScowldLanguageLibrary.options) { language in
                                    Text(LocalizedStringKey(language.name)).tag(language.code)
                                }
                            }
                        }
                        .onChange(of: selectedLanguageID) {
                            guard !isLoadingSettings else { return }
                            saveLanguageSettings()
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
                        menuRow("Avatar", value: selectedAvatarName, identifier: "settings.avatar") {
                            Picker("Avatar", selection: $selectedAvatar) {
                                ForEach(CharacterPack.defaultPacks) { pack in
                                    Text(pack.displayName).tag(pack.fileName)
                                }
                            }
                        }
                        .onChange(of: selectedAvatar) {
                            guard !isLoadingSettings else { return }
                            saveAvatarSettings()
                        }

                        settingRow {
                            Text("Name")
                                .layoutPriority(1)
                            HStack(spacing: 8) {
                                TextField("Bella", text: $characterName)
                                    .multilineTextAlignment(.trailing)
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
        .onDisappear { voicePreviewer.stop() }
        .sheet(item: $premiumSheet) { sheet in
            switch sheet {
            case .paywall:
                PremiumPaywallView()
            case .minutes:
                MinutePacksView()
                    .presentationDetents([.medium, .large])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .amicaSettingsChanged)) { _ in
            // The paywall can switch to the user's own key.
            liveMode = HostedServiceConfig.liveMode()
        }
    }

    private var aiProviderSection: some View {
        settingsSection(
            "Live Voice",
            icon: "waveform.and.mic",
            footer: liveMode == .premium
                ? "Scowld Premium relays your conversation to Google Gemini Live with Scowld's own key, so you don't need one. Nothing is stored on the way."
                : "Scowld streams your voice to the provider you choose and plays her voice back. Your API key stays in the iOS Keychain and is sent only to that provider."
        ) {
            settingRow {
                Picker("Connection", selection: $liveMode) {
                    Text("Scowld Premium").tag(LiveMode.premium)
                    Text("Own API Key").tag(LiveMode.ownKey)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.ai.mode")
            }
            .onChange(of: liveMode) {
                guard !isLoadingSettings else { return }
                voicePreviewer.stop()
                UserDefaults.standard.set(liveMode.rawValue, forKey: HostedServiceConfig.liveModeDefaultsKey)
                NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
            }

            if liveMode == .premium {
                premiumRows
            } else {
                ownKeyRows
            }
        }
    }

    // MARK: Premium

    @ViewBuilder
    private var premiumRows: some View {
        settingRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(premiumPlanTitle)
                    .font(.body.weight(.medium))
                Text(premiumMinutesText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.premium.status")
            Spacer(minLength: 0)
        }

        settingRow {
            Text("Voice")
                .layoutPriority(1)
            Spacer(minLength: 8)
            choiceMenu("Voice", value: premiumVoiceTitle, identifier: "settings.premium.voice") {
                Picker("Voice", selection: $premiumVoice) {
                    ForEach(AIProvider.gemini.voices) { voice in
                        Text(Self.voiceTitle(voice)).tag(voice.id)
                    }
                }
            }
            premiumPreviewButton
        }
        .onChange(of: premiumVoice) {
            voicePreviewer.stop()
            guard !isLoadingSettings else { return }
            UserDefaults.standard.set(premiumVoice, forKey: AIProvider.gemini.voiceDefaultsKey)
            NotificationCenter.default.post(name: .amicaSettingsChanged, object: nil)
        }

        if case .failed(let message) = voicePreviewer.state {
            settingsInfoRow(title: message, systemImage: "exclamationmark.triangle.fill", color: .red)
        }

        if premium.isSubscribed {
            settingsActionRow(
                title: NSLocalizedString("Manage Subscription", comment: "Settings row"),
                subtitle: NSLocalizedString("Change or cancel your plan", comment: "Settings row subtitle"),
                systemImage: "creditcard.fill"
            ) {
                Task { await premium.manageSubscription() }
            }
        } else {
            settingsActionRow(
                title: NSLocalizedString("See Premium Plans", comment: "Settings row"),
                subtitle: NSLocalizedString("Weekly or yearly, with a free trial", comment: "Settings row subtitle"),
                systemImage: "sparkles",
                tint: .amicaBlue
            ) {
                premiumSheet = .paywall
            }
            .accessibilityIdentifier("settings.premium.plans")
        }

        settingsActionRow(
            title: NSLocalizedString("Buy More Minutes", comment: "Settings row"),
            subtitle: NSLocalizedString("Extra minutes never expire", comment: "Settings row subtitle"),
            systemImage: "plus.circle.fill"
        ) {
            premiumSheet = .minutes
        }
        .accessibilityIdentifier("settings.premium.minutes")

        settingsActionRow(
            title: NSLocalizedString("Restore Purchases", comment: "Settings row"),
            systemImage: "arrow.clockwise",
            isDisabled: premium.isBusy
        ) {
            Task { await premium.restore() }
        }
        .accessibilityIdentifier("settings.premium.restore")
    }

    private var premiumPlanTitle: String {
        switch premium.balance?.plan ?? premium.activePlan?.rawValue {
        case "yearly": NSLocalizedString("Yearly plan", comment: "Premium plan name")
        case "weekly": NSLocalizedString("Weekly plan", comment: "Premium plan name")
        case "trial": NSLocalizedString("Free trial", comment: "Premium plan name")
        default: NSLocalizedString("No plan yet", comment: "Premium plan name")
        }
    }

    private var premiumMinutesText: String {
        guard let balance = premium.balance else {
            return NSLocalizedString("Talk without your own API key.", comment: "Premium status")
        }
        var text = String.localizedStringWithFormat(NSLocalizedString("Minutes left: %d", comment: "Premium minutes left"), balance.minutesLeft)
        if let renews = balance.planRenewsAt, balance.plan != nil {
            text += " · " + String.localizedStringWithFormat(
                NSLocalizedString("more on %@", comment: "When plan minutes renew"),
                renews.formatted(date: .abbreviated, time: .omitted)
            )
        }
        return text
    }

    private var premiumVoiceTitle: String {
        AIProvider.gemini.voices.first { $0.id == premiumVoice }.map(Self.voiceTitle) ?? premiumVoice
    }

    /// Plays the voice through Premium, which uses a few seconds of the user's minutes.
    private var premiumPreviewButton: some View {
        let isBusy = voicePreviewer.voice == premiumVoice &&
            (voicePreviewer.state == .loading || voicePreviewer.state == .playing)
        let canPlay = premium.canTalk
        return Button {
            if isBusy {
                voicePreviewer.stop()
            } else {
                Task { await previewPremiumVoice() }
            }
        } label: {
            ZStack {
                if voicePreviewer.state == .loading && voicePreviewer.voice == premiumVoice {
                    ProgressView()
                } else {
                    Image(systemName: isBusy ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(canPlay ? Color.amicaBlue : Color.secondary)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(!canPlay)
        .accessibilityLabel(isBusy ? "Stop voice preview" : "Play voice preview")
        .accessibilityHint("Plays a short line in this voice using a few seconds of your Premium minutes.")
        .accessibilityIdentifier("settings.premium.voicePreview")
    }

    private func previewPremiumVoice() async {
        guard !ScowldTestEnvironment.isRunningTests, let userID = await premium.premiumUserID() else { return }
        voicePreviewer.play(
            provider: .gemini,
            model: AIProvider.gemini.defaultModel,
            voice: premiumVoice,
            apiKey: userID,
            name: CharacterPack.resolveCharacterName(),
            wire: ScowldPremiumWire()
        )
    }

    // MARK: Own key

    @ViewBuilder
    private var ownKeyRows: some View {
        menuRow("Provider", value: selectedAIProvider.displayName, identifier: "settings.ai.provider") {
            Picker("Provider", selection: $selectedAIProviderID) {
                ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
        }
        .onChange(of: selectedAIProviderID) {
            guard !isLoadingSettings else { return }
            loadAIProviderSettings()
        }

        modelSelectionRows(
            models: LiveModelCatalog.merged(builtIn: selectedAIProvider.availableModels, fetched: fetchedModels),
            selection: $selectedAIModel,
            isCustom: $aiModelIsCustom,
            identifier: "settings.ai"
        )

        settingRow {
            Text("Voice")
                .layoutPriority(1)
            Spacer(minLength: 8)
            choiceMenu("Voice", value: selectedVoiceTitle, identifier: "settings.ai.voice") {
                Picker("Voice", selection: $selectedVoice) {
                    ForEach(selectedAIProvider.voices) { voice in
                        Text(Self.voiceTitle(voice)).tag(voice.id)
                    }
                }
            }
            voicePreviewButton
        }
        .onChange(of: selectedVoice) {
            voicePreviewer.stop()
        }

        if case .failed(let message) = voicePreviewer.state {
            settingsInfoRow(title: message, systemImage: "exclamationmark.triangle.fill", color: .red)
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

    /// Plays the selected voice with the key in the field, so it can be heard before saving.
    private var voicePreviewButton: some View {
        let isBusy = voicePreviewer.voice == selectedVoice &&
            (voicePreviewer.state == .loading || voicePreviewer.state == .playing)
        let hasKey = hasSavedAIAPIKey || !aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if isBusy {
                voicePreviewer.stop()
            } else {
                previewSelectedVoice()
            }
        } label: {
            ZStack {
                if voicePreviewer.state == .loading && voicePreviewer.voice == selectedVoice {
                    ProgressView()
                } else {
                    Image(systemName: isBusy ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(hasKey ? Color.amicaBlue : Color.secondary)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(!hasKey)
        .accessibilityLabel(isBusy ? "Stop voice preview" : "Play voice preview")
        .accessibilityHint("Uses your API key to play a short line in this voice.")
        .accessibilityIdentifier("settings.ai.voicePreview")
    }

    private func previewSelectedVoice() {
        // Tests never reach a provider.
        guard !ScowldTestEnvironment.isRunningTests else { return }
        let model = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        voicePreviewer.play(
            provider: selectedAIProvider,
            model: model.isEmpty ? selectedAIProvider.defaultModel : model,
            voice: selectedVoice,
            apiKey: aiAPIKeyInUse,
            name: CharacterPack.resolveCharacterName()
        )
    }

    /// Adds the live models this key can use to the model list. Failures keep the
    /// built-in list.
    private func refreshModels() {
        let provider = selectedAIProvider
        let key = aiAPIKeyInUse
        fetchedModels = []
        guard !key.isEmpty, !ScowldTestEnvironment.isRunningTests else { return }
        Task {
            let models = (try? await LiveModelCatalog.fetch(for: provider, apiKey: key)) ?? []
            guard provider == selectedAIProvider else { return }
            fetchedModels = models
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
        menuRow(
            "Model",
            value: isCustom.wrappedValue ? NSLocalizedString("Custom model", comment: "Model picker option") : selection.wrappedValue,
            identifier: "\(identifier).model"
        ) {
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

    /// A titled row whose value opens a menu of choices.
    private func menuRow<Choices: View>(
        _ title: LocalizedStringKey,
        value: String,
        identifier: String,
        @ViewBuilder choices: () -> Choices
    ) -> some View {
        settingRow {
            Text(title)
                .layoutPriority(1)
            Spacer(minLength: 8)
            choiceMenu(title, value: value, identifier: identifier, choices: choices)
        }
    }

    /// The current value with a menu of choices. Unlike a menu-style picker, the
    /// value stays on one line: a long model name truncates in the middle instead
    /// of wrapping. VoiceOver reads the title and the value.
    private func choiceMenu<Choices: View>(
        _ title: LocalizedStringKey,
        value: String,
        identifier: String,
        @ViewBuilder choices: () -> Choices
    ) -> some View {
        Menu {
            choices()
        } label: {
            HStack(spacing: 5) {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.amicaBlue)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
        .accessibilityIdentifier(identifier)
    }

    private var selectedLanguageName: String {
        guard let language = ScowldLanguageLibrary.options.first(where: { $0.code == selectedLanguageID }) else {
            return NSLocalizedString("iPhone Language", comment: "Device language picker option")
        }
        return NSLocalizedString(language.name, comment: "Language name")
    }

    private var selectedAvatarName: String {
        CharacterPack.defaultPacks.first { $0.fileName == selectedAvatar }?.displayName ?? selectedAvatar
    }

    private static func voiceTitle(_ voice: LiveVoice) -> String {
        "\(voice.name) - \(voice.style)"
    }

    private var selectedVoiceTitle: String {
        selectedAIProvider.voices.first { $0.id == selectedVoice }.map(Self.voiceTitle) ?? selectedVoice
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

    /// The key typed in the field, or else the saved one. A saved key is never
    /// shown in the field; typing replaces it on Save.
    private var aiAPIKeyInUse: String {
        let typed = aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.isEmpty else { return typed }
        return KeychainManager.load(key: selectedAIProvider.keychainKey) ?? ""
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
        liveMode = HostedServiceConfig.liveMode()
        premiumVoice = HostedServiceConfig.selectedVoice(for: .gemini)
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
        aiAPIKey = ""
        hasSavedAIAPIKey = KeychainManager.exists(key: provider.keychainKey)
        voicePreviewer.stop()
        refreshModels()
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
        if hasSavedAIAPIKey {
            aiAPIKey = ""
        }
        aiSettingsMessage = "Saved"
        refreshModels()
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
