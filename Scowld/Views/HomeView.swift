import SwiftUI

// MARK: - Home View

/// Main app screen with animated owl character, glass chat overlay, and floating controls.
struct HomeView: View {
    // MARK: - Managers
    var memoryStore: MemoryStore
    @State private var speechManager = SpeechManager()
    @State private var cameraManager = CameraManager()
    @State private var faceDetector = FaceDetector()
    @State private var arkitManager = ARKitManager()
    @State private var characterManager = CharacterManager()
    @State private var memoryExtractor = MemoryExtractor()

    // MARK: - UI State
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showChat = false
    @State private var sessionId: UUID?
    @State private var sessionStartTime: Date?
    @State private var errorMessage: String?
    @State private var visionTimer: Timer?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.03, blue: 0.08),
                            Color(red: 0.08, green: 0.05, blue: 0.12),
                            Color(red: 0.04, green: 0.02, blue: 0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    // Ambient glow behind character
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.08), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(y: -geo.size.height * 0.1)

                    VStack(spacing: 0) {
                        // MARK: - Character
                        characterArea(height: showChat ? geo.size.height * 0.4 : geo.size.height * 0.65)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showChat)

                        Spacer(minLength: 0)

                        // MARK: - Chat Overlay
                        if showChat {
                            glassChatArea(height: geo.size.height * 0.38)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    // Error toast
                    if let error = errorMessage {
                        VStack {
                            Spacer()
                            glassErrorToast(error)
                                .padding(.bottom, 100)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .navigationTitle("Scowld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showChat.toggle()
                            }
                        } label: {
                            Label(
                                showChat ? "Hide Keyboard" : "Show Keyboard",
                                systemImage: showChat ? "keyboard.chevron.compact.down" : "keyboard"
                            )
                        }

                        Button {
                            toggleListening()
                        } label: {
                            Label(
                                speechManager.isListening ? "Stop Listening" : "Start Listening",
                                systemImage: speechManager.isListening ? "waveform" : "mic.fill"
                            )
                        }

                        Button {
                            toggleCamera()
                        } label: {
                            Label(
                                cameraManager.isActive ? "Disable Camera" : "Enable Camera",
                                systemImage: cameraManager.isActive ? "eye.fill" : "eye.slash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .onAppear { startSession() }
        .onDisappear { endSession() }
        .onChange(of: speechManager.currentAmplitude) {
            characterManager.updateFromSpeechAmplitude(speechManager.currentAmplitude)
        }
        .onChange(of: speechManager.isSpeaking) {
            if !speechManager.isSpeaking {
                characterManager.mouthOpenness = 0
            }
        }
        .onChange(of: arkitManager.headYaw) {
            if arkitManager.isTracking {
                characterManager.updateFromFaceTracking(
                    yaw: arkitManager.headYaw,
                    pitch: arkitManager.headPitch,
                    eyeX: arkitManager.leftEyeX,
                    eyeY: arkitManager.leftEyeY
                )
            }
        }
    }

    // MARK: - Character Area

    @ViewBuilder
    private func characterArea(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            VRMCharacterView(
                emotion: characterManager.emotion,
                mouthOpenness: characterManager.mouthOpenness,
                pupilOffsetX: characterManager.pupilOffsetX,
                pupilOffsetY: characterManager.pupilOffsetY,
                headRotation: characterManager.headRotation,
                isBlinking: characterManager.isBlinking,
                bodyBounce: characterManager.bodyBounce,
                modelFileName: characterManager.selectedCharacter.fileName,
                pendingGesture: Binding(
                    get: { characterManager.pendingGesture },
                    set: { characterManager.pendingGesture = $0 }
                )
            )
            .frame(height: height * 0.9)
            .onTapGesture { toggleListening() }

            // Emotion pill
            HStack(spacing: 6) {
                Text(characterManager.emotion.emoji)
                    .font(.subheadline)
                Text(characterManager.emotion.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(height: height)
    }

    // MARK: - Glass Chat Area

    @ViewBuilder
    private func glassChatArea(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ChatView(
                messages: messages,
                inputText: $inputText,
                onSend: sendTextMessage,
                isGenerating: isGenerating
            )
        }
        .frame(height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
    }

    // MARK: - Glass Error Toast

    @ViewBuilder
    private func glassErrorToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { errorMessage = nil }
            }
        }
    }

    // MARK: - Actions

    private func startSession() {
        sessionId = memoryStore.createSession()
        sessionStartTime = Date()
        characterManager.startIdleAnimations()
        Task {
            _ = await speechManager.requestPermissions()
            _ = await cameraManager.requestPermission()
        }
    }

    private func endSession() {
        characterManager.stopIdleAnimations()
        stopVisionAnalysis()
        if let sessionId, messages.count >= 4 {
            let contextBuilder = ContextBuilder(memoryStore: memoryStore)
            let summary = contextBuilder.buildSessionSummary(messages: messages)
            let duration = Date().timeIntervalSince(sessionStartTime ?? Date())
            memoryStore.updateSession(id: sessionId, summary: summary, duration: duration)
            Task {
                let provider = buildCurrentProvider()
                await memoryExtractor.extractAndSave(messages: messages, using: provider, store: memoryStore)
            }
        }
    }

    private func toggleListening() {
        if speechManager.isListening {
            speechManager.stopListening()
            if !speechManager.recognizedText.isEmpty {
                let text = speechManager.recognizedText
                speechManager.recognizedText = ""
                processUserInput(text)
            }
        } else {
            speechManager.stopSpeaking()
            speechManager.startListening()
        }
    }

    private func toggleCamera() {
        if cameraManager.isActive {
            cameraManager.stopCapture()
            stopVisionAnalysis()
        } else {
            cameraManager.startCapture()
            startVisionAnalysis()
        }
    }

    private func sendTextMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        processUserInput(text)
    }

    private func processUserInput(_ text: String) {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        if let sessionId {
            memoryStore.saveMessage(role: .user, content: text, emotion: nil, sessionId: sessionId)
        }

        if !showChat {
            withAnimation(.spring(response: 0.3)) { showChat = true }
        }

        let wantsVision = text.lowercased().contains("look at") ||
                          text.lowercased().contains("what do you see") ||
                          text.lowercased().contains("can you see")

        Task { await generateResponse(wantsVision: wantsVision) }
    }

    private func generateResponse(wantsVision: Bool) async {
        guard let provider = buildCurrentProvider() else {
            errorMessage = "No API key configured. Add your key in Settings tab."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        let contextBuilder = ContextBuilder(memoryStore: memoryStore)
        let visionDesc = cameraManager.isActive ? faceDetector.sceneDescription : nil
        let systemPrompt = contextBuilder.buildSystemPrompt(visionDescription: visionDesc)

        do {
            let response: String
            if wantsVision, let snapshot = cameraManager.captureSnapshot() {
                response = try await provider.generateWithVision(messages: messages, systemPrompt: systemPrompt, image: snapshot)
            } else {
                response = try await provider.generate(messages: messages, systemPrompt: systemPrompt)
            }

            let cleanText = characterManager.processAIResponse(response)

            let assistantMessage = ChatMessage(role: .assistant, content: cleanText, emotion: characterManager.emotion)
            messages.append(assistantMessage)

            if let sessionId {
                memoryStore.saveMessage(role: .assistant, content: cleanText, emotion: characterManager.emotion, sessionId: sessionId)
            }

            speechManager.speak(cleanText)
        } catch {
            let errText = error.localizedDescription
            errorMessage = errText
            // Also show error in chat so user can read it
            let errMessage = ChatMessage(role: .assistant, content: "Error: \(errText)")
            messages.append(errMessage)
        }
    }

    // MARK: - Vision Analysis

    private func startVisionAnalysis() {
        visionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                guard let frame = cameraManager.latestFrame else { return }
                await faceDetector.analyzeFrame(frame)
                if faceDetector.isFacePresent {
                    characterManager.pupilOffsetX = faceDetector.gazeDirection.contains("right") ? 0.3 :
                                                    faceDetector.gazeDirection.contains("left") ? -0.3 : 0
                    characterManager.pupilOffsetY = faceDetector.gazeDirection.contains("up") ? 0.3 :
                                                    faceDetector.gazeDirection.contains("down") ? -0.3 : 0
                }
            }
        }
    }

    private func stopVisionAnalysis() {
        visionTimer?.invalidate()
        visionTimer = nil
    }

    // MARK: - Provider Builder

    private func buildCurrentProvider() -> (any LLMProvider)? {
        let defaults = UserDefaults.standard
        let providerStr = defaults.string(forKey: "selectedProvider") ?? "gemini"
        guard let provider = AIProvider(rawValue: providerStr) else { return nil }

        // Use saved model if still valid, otherwise fall back to provider default
        let savedModel = defaults.string(forKey: "selectedModel") ?? provider.defaultModel
        let model = provider.availableModels.contains(savedModel) ? savedModel : provider.defaultModel

        if provider.requiresAPIKey {
            guard let apiKey = KeychainManager.load(key: provider.keychainKey), !apiKey.isEmpty else { return nil }
            switch provider {
            case .gemini: return GeminiProvider(apiKey: apiKey, model: model)
            case .openai: return OpenAIProvider(apiKey: apiKey, model: model)
            case .claude: return ClaudeProvider(apiKey: apiKey, model: model)
            case .ollama: return nil
            }
        } else {
            let url = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
            return OllamaProvider(baseURL: url, model: model)
        }
    }
}
