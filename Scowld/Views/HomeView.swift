import SwiftUI
import WebKit

// MARK: - Home View

/// Main app screen — embeds Amica's full web-based VRM character system.
/// Native Swift handles LLM responses via JS bridge.
struct HomeView: View {
    var memoryStore: MemoryStore

    var body: some View {
        AmicaFullView(memoryStore: memoryStore)
            .ignoresSafeArea()
    }
}

// MARK: - Amica URL Scheme Handler

/// Serves bundled Amica files under a custom URL scheme so absolute paths work.
/// e.g. amica://host/_next/static/... → Bundle/amica/_next/static/...
class AmicaSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // Convert amica://host/path → Bundle/amica/path
        var path = url.path
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.isEmpty { path = "index.html" }

        // Try to find the file in the bundle
        let amicaBase = Bundle.main.bundleURL.appendingPathComponent("amica")
        let fileURL = amicaBase.appendingPathComponent(path)

        // If path ends with /, try index.html
        var resolvedURL = fileURL
        if path.hasSuffix("/") {
            resolvedURL = fileURL.appendingPathComponent("index.html")
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            // Try with .html extension
            let htmlURL = amicaBase.appendingPathComponent(path + ".html")
            if FileManager.default.fileExists(atPath: htmlURL.path) {
                resolvedURL = htmlURL
            } else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
        }

        do {
            let data = try Data(contentsOf: resolvedURL)
            let mimeType = Self.mimeType(for: resolvedURL.pathExtension)
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        case "vrm", "glb": return "model/gltf-binary"
        case "vrma": return "model/gltf-binary"
        case "webmanifest": return "application/manifest+json"
        default: return "application/octet-stream"
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
        let schemeHandler = AmicaSchemeHandler()

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "amica")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "nativeAI")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // Load via custom scheme so absolute paths resolve correctly
        if let url = URL(string: "amica://host/index.html") {
            webView.load(URLRequest(url: url))
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        let memoryStore: MemoryStore

        init(memoryStore: MemoryStore) {
            self.memoryStore = memoryStore
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[Amica] Page loaded")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[Amica] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[Amica] Provisional navigation failed: \(error.localizedDescription)")
        }

        // Allow navigation within the amica scheme
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            return .allow
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
                print("[Amica] Bridge: \(type)")
            }
        }

        // MARK: Native AI

        private func handleChatRequest(callbackId: String, messages: [[String: String]]) async {
            guard let provider = buildCurrentProvider() else {
                await MainActor.run {
                    deliverError(callbackId: callbackId, error: "No API key configured")
                }
                return
            }

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
