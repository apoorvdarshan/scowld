import SwiftUI

// MARK: - Home View

/// Main app screen. Shows the animated owl character, chat bubbles, and mic button.
/// Layout: Character (60%) → Chat (30%) → Controls (10%)
struct HomeView: View {
    // MARK: - Managers
    @State private var speechManager = SpeechManager()
    @State private var cameraManager = CameraManager()
    @State private var faceDetector = FaceDetector()
    @State private var arkitManager = ARKitManager()
    @State private var characterManager = CharacterManager()
    @State private var memoryStore = MemoryStore()
    @State private var memoryExtractor = MemoryExtractor()

    // MARK: - UI State
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showSettings = false
    @State private var showChat = false
    @State private var sessionId: UUID?
    @State private var sessionStartTime: Date?
    @State private var errorMessage: String?

    // Vision analysis timer
    @State private var visionTimer: Timer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: - Header
                    header

                    // MARK: - Character Area (60%)
                    characterArea(height: geo.size.height * 0.55)

                    // MARK: - Chat Area (expandable)
                    if showChat {
                        ChatView(
                            messages: messages,
                            inputText: $inputText,
                            onSend: sendTextMessage,
                            isGenerating: isGenerating
                        )
                        .frame(height: geo.size.height * 0.35)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // MARK: - Controls
                    controls
                        .padding(.bottom, 8)
                }

                // Error toast
                if let error = errorMessage {
                    VStack {
                        Spacer()
                        errorToast(error)
                            .padding(.bottom, 120)
                    }
                    .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(memoryStore: memoryStore)
        }
        .onAppear {
            startSession()
        }
        .onDisappear {
            endSession()
        }
        // Bridge speech amplitude → character lip sync
        .onChange(of: speechManager.currentAmplitude) {
            characterManager.updateFromSpeechAmplitude(speechManager.currentAmplitude)
        }
        .onChange(of: speechManager.isSpeaking) {
            if !speechManager.isSpeaking {
                characterManager.mouthOpenness = 0
            }
        }
        // Bridge ARKit tracking → character animation
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Scowld")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            // Camera indicator
            if cameraManager.isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Camera")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
                bodyBounce: characterManager.bodyBounce
            )
            .frame(height: height * 0.85)
            .onTapGesture {
                // Tap character to start/stop listening
                toggleListening()
            }

            // Emotion indicator
            HStack(spacing: 4) {
                Text(characterManager.emotion.emoji)
                    .font(.caption)
                Text(characterManager.emotion.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 20) {
            // Toggle chat
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showChat.toggle()
                }
            } label: {
                Image(systemName: showChat ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.title2)
                    .foregroundStyle(.gray)
                    .frame(width: 44, height: 44)
            }

            // Mic button (push to talk)
            Button {
                toggleListening()
            } label: {
                ZStack {
                    Circle()
                        .fill(speechManager.isListening ? Color.red : Color.orange)
                        .frame(width: 64, height: 64)
                        .shadow(color: (speechManager.isListening ? Color.red : Color.orange).opacity(0.4), radius: 8)

                    Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }

            // Camera toggle
            Button {
                toggleCamera()
            } label: {
                Image(systemName: cameraManager.isActive ? "eye.fill" : "eye.slash")
                    .font(.title2)
                    .foregroundStyle(cameraManager.isActive ? .green : .gray)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Error Toast

    @ViewBuilder
    private func errorToast(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.9))
            )
            .foregroundStyle(.white)
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

        // Request permissions
        Task {
            _ = await speechManager.requestPermissions()
            _ = await cameraManager.requestPermission()
        }
    }

    private func endSession() {
        characterManager.stopIdleAnimations()
        stopVisionAnalysis()

        // Extract memories from conversation
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
            // Process the recognized speech
            if !speechManager.recognizedText.isEmpty {
                let text = speechManager.recognizedText
                speechManager.recognizedText = ""
                processUserInput(text)
            }
        } else {
            // Stop any ongoing TTS
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
        // Add user message
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        // Save to CoreData
        if let sessionId {
            memoryStore.saveMessage(role: .user, content: text, emotion: nil, sessionId: sessionId)
        }

        // Show chat if hidden
        if !showChat {
            withAnimation(.spring(response: 0.3)) {
                showChat = true
            }
        }

        // Check if user wants vision analysis
        let wantsVision = text.lowercased().contains("look at") ||
                          text.lowercased().contains("what do you see") ||
                          text.lowercased().contains("can you see")

        // Generate AI response
        Task {
            await generateResponse(wantsVision: wantsVision)
        }
    }

    private func generateResponse(wantsVision: Bool) async {
        guard let provider = buildCurrentProvider() else {
            errorMessage = "No AI provider configured. Add your API key in Settings."
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build context
        let contextBuilder = ContextBuilder(memoryStore: memoryStore)
        let visionDesc = cameraManager.isActive ? faceDetector.sceneDescription : nil
        let systemPrompt = contextBuilder.buildSystemPrompt(visionDescription: visionDesc)

        do {
            let response: String
            if wantsVision, let snapshot = cameraManager.captureSnapshot() {
                response = try await provider.generateWithVision(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    image: snapshot
                )
            } else {
                response = try await provider.generate(
                    messages: messages,
                    systemPrompt: systemPrompt
                )
            }

            // Parse emotion and clean text
            let cleanText = characterManager.processAIResponse(response)

            // Add assistant message
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: cleanText,
                emotion: characterManager.emotion
            )
            messages.append(assistantMessage)

            // Save to CoreData
            if let sessionId {
                memoryStore.saveMessage(role: .assistant, content: cleanText, emotion: characterManager.emotion, sessionId: sessionId)
            }

            // Speak the response
            speechManager.speak(cleanText)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Vision Analysis

    private func startVisionAnalysis() {
        visionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                guard let frame = cameraManager.latestFrame else { return }
                await faceDetector.analyzeFrame(frame)

                // Update character from face detection
                if faceDetector.isFacePresent {
                    let gazeX: CGFloat = faceDetector.gazeDirection.contains("right") ? 0.3 :
                                         faceDetector.gazeDirection.contains("left") ? -0.3 : 0
                    let gazeY: CGFloat = faceDetector.gazeDirection.contains("up") ? 0.3 :
                                         faceDetector.gazeDirection.contains("down") ? -0.3 : 0
                    characterManager.pupilOffsetX = gazeX
                    characterManager.pupilOffsetY = gazeY
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
        let model = defaults.string(forKey: "selectedModel") ?? "gemini-2.0-flash"

        guard let provider = AIProvider(rawValue: providerStr) else { return nil }

        if provider.requiresAPIKey {
            guard let apiKey = KeychainManager.load(key: provider.keychainKey), !apiKey.isEmpty else {
                return nil
            }

            switch provider {
            case .gemini: return GeminiProvider(apiKey: apiKey, model: model)
            case .openai: return OpenAIProvider(apiKey: apiKey, model: model)
            case .claude: return ClaudeProvider(apiKey: apiKey, model: model)
            case .ollama: return nil // Ollama doesn't need a key
            }
        } else {
            // Ollama
            let url = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
            return OllamaProvider(baseURL: url, model: model)
        }
    }
}

