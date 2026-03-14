import SwiftUI
import WebKit

// MARK: - Home View

/// Main app screen — embeds Amica's full web-based VRM character system.
/// Native Swift handles LLM responses via JS bridge.
struct HomeView: View {
    // MARK: - Managers
    var memoryStore: MemoryStore
    @State private var cameraManager = CameraManager()
    @State private var faceDetector = FaceDetector()

    // MARK: - UI State
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AmicaFullView(memoryStore: memoryStore)
                .ignoresSafeArea()

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
}

// MARK: - Amica Full View (WKWebView)

struct AmicaFullView: UIViewRepresentable {
    var memoryStore: MemoryStore

    func makeCoordinator() -> Coordinator {
        Coordinator(memoryStore: memoryStore)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "nativeAI")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // Load Amica
        if let indexURL = Bundle.main.url(forResource: "amica/index", withExtension: "html"),
           let amicaDir = Bundle.main.url(forResource: "amica", withExtension: nil) {
            webView.loadFileURL(indexURL, allowingReadAccessTo: amicaDir)
        } else {
            print("[Amica] ERROR: amica/index.html not found in bundle")
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator (handles native AI bridge)

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        let memoryStore: MemoryStore

        init(memoryStore: MemoryStore) {
            self.memoryStore = memoryStore
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[Amica] Page loaded")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[Amica] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[Amica] Provisional navigation failed: \(error.localizedDescription)")
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            switch type {
            case "chat":
                guard let callbackId = json["callbackId"] as? String,
                      let messages = json["messages"] as? [[String: String]] else { return }
                Task { await handleChatRequest(callbackId: callbackId, messages: messages) }
            default:
                print("[Amica] Bridge message: \(type)")
            }
        }

        // MARK: - Native AI Chat

        private func handleChatRequest(callbackId: String, messages: [[String: String]]) async {
            guard let provider = buildCurrentProvider() else {
                deliverError(callbackId: callbackId, error: "No API key configured")
                return
            }

            // Convert message dicts to ChatMessage
            let chatMessages = messages.compactMap { dict -> ChatMessage? in
                guard let roleStr = dict["role"], let content = dict["content"] else { return nil }
                let role: MessageRole = roleStr == "user" ? .user : roleStr == "assistant" ? .assistant : .system
                return ChatMessage(role: role, content: content)
            }

            do {
                let response = try await provider.generate(messages: chatMessages, systemPrompt: "")
                await MainActor.run {
                    deliverResponse(callbackId: callbackId, response: response)
                }
            } catch {
                await MainActor.run {
                    deliverError(callbackId: callbackId, error: error.localizedDescription)
                }
            }
        }

        private func deliverResponse(callbackId: String, response: String) {
            let escaped = response
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            webView?.evaluateJavaScript("window.nativeAIResponse && window.nativeAIResponse('\(callbackId)', '\(escaped)')")
        }

        private func deliverError(callbackId: String, error: String) {
            let escaped = error.replacingOccurrences(of: "'", with: "\\'")
            webView?.evaluateJavaScript("window.nativeAIError && window.nativeAIError('\(callbackId)', '\(escaped)')")
        }

        // MARK: - Provider Builder

        private func buildCurrentProvider() -> (any LLMProvider)? {
            let defaults = UserDefaults.standard
            let providerStr = defaults.string(forKey: "selectedProvider") ?? "gemini"
            guard let provider = AIProvider(rawValue: providerStr) else { return nil }

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
}
