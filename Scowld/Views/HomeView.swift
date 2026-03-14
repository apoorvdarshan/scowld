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

        // Convert amica://host/path → find file in bundle
        var path = url.path
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.isEmpty { path = "index.html" }

        // Try multiple base locations (Xcode may place resources differently)
        let bundleRoot = Bundle.main.bundleURL
        let basePaths = [
            bundleRoot.appendingPathComponent("amica.bundle"),
            bundleRoot,
            bundleRoot.appendingPathComponent("amica"),
        ]

        var resolvedURL: URL? = nil
        for base in basePaths {
            let candidate = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                resolvedURL = candidate
                break
            }
            // Try with /index.html for directory paths
            if path.hasSuffix("/") {
                let indexCandidate = candidate.appendingPathComponent("index.html")
                if FileManager.default.fileExists(atPath: indexCandidate.path) {
                    resolvedURL = indexCandidate
                    break
                }
            }
            // Try with .html extension
            let htmlCandidate = base.appendingPathComponent(path + ".html")
            if FileManager.default.fileExists(atPath: htmlCandidate.path) {
                resolvedURL = htmlCandidate
                break
            }
        }

        guard let resolvedURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
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

        // Inject settings into localStorage BEFORE page loads
        let defaults = UserDefaults.standard
        let ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "native_ios"
        let sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "none"
        let visionBackend = defaults.string(forKey: "amica_vision_backend") ?? "none"
        let elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "cgSgspJ2msm6clMCkdW9"
        let elevenLabsKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
        let whisperApiKey = defaults.string(forKey: "amica_openai_whisper_apikey") ?? ""
        // Fall back to the main OpenAI key if no separate whisper key
        let effectiveWhisperKey = whisperApiKey.isEmpty ? (KeychainManager.load(key: AIProvider.openai.keychainKey) ?? "") : whisperApiKey

        let settingsScript = WKUserScript(
            source: """
            window.__nativeConfig = {
                chatbot_backend: 'native_ios',
                tts_backend: '\(ttsBackend)',
                stt_backend: '\(sttBackend)',
                vision_backend: '\(visionBackend)',
                elevenlabs_apikey: '\(elevenLabsKey)',
                elevenlabs_voiceid: '\(elevenLabsVoiceId)',
                elevenlabs_model: 'eleven_flash_v2_5',
                openai_whisper_apikey: '\(effectiveWhisperKey)'
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(settingsScript)

        // Forward JS console to Swift
        let consoleScript = WKUserScript(
            source: """
            (function() {
                var origLog = console.log, origError = console.error, origWarn = console.warn;
                function send(level, args) {
                    try { window.webkit.messageHandlers.nativeAI.postMessage(JSON.stringify({
                        type: 'console', level: level, message: Array.from(args).map(String).join(' ')
                    })); } catch(e) {}
                }
                console.log = function() { send('log', arguments); origLog.apply(console, arguments); };
                console.error = function() { send('error', arguments); origError.apply(console, arguments); };
                console.warn = function() { send('warn', arguments); origWarn.apply(console, arguments); };
                window.onerror = function(msg, url, line) {
                    send('error', ['JS Error: ' + msg + ' at ' + url + ':' + line]);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(consoleScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = true
        webView.navigationDelegate = context.coordinator

        // Verify amica files exist in bundle, then load via custom scheme
        let bundleRoot = Bundle.main.bundlePath
        let possiblePaths = [
            "\(bundleRoot)/amica.bundle/index.html",
            "\(bundleRoot)/index.html",
            "\(bundleRoot)/amica/index.html",
        ]
        var foundPath: String? = nil
        for p in possiblePaths {
            if FileManager.default.fileExists(atPath: p) {
                foundPath = p
                break
            }
        }

        if let found = foundPath {
            print("[Amica] Found index.html at: \(found)")
            webView.load(URLRequest(url: URL(string: "amica://host/index.html")!))
        } else {
            print("[Amica] ERROR: index.html not found in bundle")
            // Debug: list bundle contents
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: bundleRoot)) ?? []
            print("[Amica] Bundle root contents: \(contents.sorted())")
            // Check for amica folder
            for dir in ["amica", "Resources", "Resources/amica"] {
                let dirPath = "\(bundleRoot)/\(dir)"
                if let items = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
                    print("[Amica] \(dir)/: \(items.prefix(15))")
                }
            }
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        let memoryStore: MemoryStore
        let speechManager = SpeechManager()

        private var settingsObserver: Any?

        init(memoryStore: MemoryStore) {
            self.memoryStore = memoryStore
            super.init()
            // Listen for settings changes from Settings tab
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .amicaSettingsChanged, object: nil, queue: .main
            ) { [weak self] _ in
                self?.pushSettingsToAmica()
            }
        }

        deinit {
            if let observer = settingsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[Amica] Page loaded")
            // Double-check: push settings again after page load (user script may not have localStorage access on custom schemes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pushSettingsToAmica()
            }
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

        // Auto-grant microphone/camera permissions so it doesn't keep asking
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType) async -> WKPermissionDecision {
            return .grant
        }

        // MARK: Push Settings to Amica

        func pushSettingsToAmica() {
            guard let webView else { return }
            let defaults = UserDefaults.standard

            let ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "native_ios"
            let sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "none"
            let visionBackend = defaults.string(forKey: "amica_vision_backend") ?? "none"
            let elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "cgSgspJ2msm6clMCkdW9"
            let elevenLabsKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
            let whisperKey = defaults.string(forKey: "amica_openai_whisper_apikey") ?? ""
            let effectiveWhisperKey = whisperKey.isEmpty ? (KeychainManager.load(key: AIProvider.openai.keychainKey) ?? "") : whisperKey

            let js = """
            window.__nativeConfig = window.__nativeConfig || {};
            window.__nativeConfig.chatbot_backend = 'native_ios';
            window.__nativeConfig.tts_backend = '\(ttsBackend)';
            window.__nativeConfig.stt_backend = '\(sttBackend)';
            window.__nativeConfig.vision_backend = '\(visionBackend)';
            window.__nativeConfig.elevenlabs_apikey = '\(elevenLabsKey)';
            window.__nativeConfig.elevenlabs_voiceid = '\(elevenLabsVoiceId)';
            window.__nativeConfig.elevenlabs_model = 'eleven_flash_v2_5';
            window.__nativeConfig.openai_whisper_apikey = '\(effectiveWhisperKey)';
            console.log('Native config updated: tts=\(ttsBackend), stt=\(sttBackend)');
            """
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[Amica] Settings push error: \(error.localizedDescription)")
                } else {
                    print("[Amica] Settings pushed to Amica")
                }
            }
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
            case "speak":
                if let text = json["text"] as? String {
                    speechManager.speak(text)
                }
            case "console":
                let level = json["level"] as? String ?? "log"
                let msg = json["message"] as? String ?? ""
                print("[Amica-JS] [\(level)] \(msg)")
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

            switch provider {
            case .gemini:
                guard let apiKey = KeychainManager.load(key: provider.keychainKey), !apiKey.isEmpty else { return nil }
                return GeminiProvider(apiKey: apiKey, model: model)
            case .openai:
                guard let apiKey = KeychainManager.load(key: provider.keychainKey), !apiKey.isEmpty else { return nil }
                return OpenAIProvider(apiKey: apiKey, model: model)
            case .claude:
                guard let apiKey = KeychainManager.load(key: provider.keychainKey), !apiKey.isEmpty else { return nil }
                return ClaudeProvider(apiKey: apiKey, model: model)
            case .ollama:
                let url = KeychainManager.load(key: OllamaConfig.keychainURLKey) ?? OllamaConfig.defaultURL
                return OllamaProvider(baseURL: url, model: model)
            }
        }
    }
}
