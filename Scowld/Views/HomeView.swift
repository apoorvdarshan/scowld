import SwiftUI
import WebKit
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Amica")

// MARK: - Home View

// Debug log shared between views
@Observable
class DebugLog {
    static let shared = DebugLog()
    var messages: [String] = []
    func add(_ msg: String) {
        DispatchQueue.main.async {
            self.messages.append(msg)
            if self.messages.count > 20 { self.messages.removeFirst() }
        }
    }
}

struct HomeView: View {
    var memoryStore: MemoryStore
    @State private var showDebug = false

    var body: some View {
        ZStack {
            AmicaFullView(memoryStore: memoryStore)
                .ignoresSafeArea()

            // Debug overlay - tap top-left corner to toggle
            VStack {
                HStack {
                    Button { showDebug.toggle() } label: {
                        Text("DBG")
                            .font(.caption2)
                            .padding(4)
                            .background(.black.opacity(0.5))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.leading, 8)

                if showDebug {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(DebugLog.shared.messages, id: \.self) { msg in
                                Text(msg)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 200)
                    .background(.black.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.horizontal, 8)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Local HTTP Server for Amica

/// Serves Amica's static files via a local HTTP server so fetch() works with normal CORS.
class AmicaLocalServer {
    static let shared = AmicaLocalServer()
    private var listener: (any NSObjectProtocol)?
    private var serverSocket: Int32 = -1
    var port: UInt16 = 0
    private var isRunning = false
    private let amicaBasePath: String

    init() {
        // Find amica.bundle in app bundle
        let bundle = Bundle.main.bundlePath
        let paths = [
            "\(bundle)/amica.bundle",
            bundle,
            "\(bundle)/amica"
        ]
        amicaBasePath = paths.first { FileManager.default.fileExists(atPath: "\($0)/index.html") } ?? bundle
        logger.info("[Server] Amica base: \(self.amicaBasePath)")
    }

    func start() {
        guard !isRunning else { return }

        // Create socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { logger.info("[Server] Socket failed"); return }

        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0 // Let OS pick a port

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else { logger.info("[Server] Bind failed"); return }

        // Get assigned port
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assignedAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(serverSocket, $0, &addrLen)
            }
        }
        port = UInt16(bigEndian: assignedAddr.sin_port)

        guard listen(serverSocket, 10) >= 0 else { logger.info("[Server] Listen failed"); return }

        isRunning = true
        logger.info("[Server] Running on http://127.0.0.1:\(self.port)")

        // Accept connections in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while self?.isRunning == true {
                guard let self else { return }
                let client = accept(self.serverSocket, nil, nil)
                if client >= 0 {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.handleClient(client)
                    }
                }
            }
        }
    }

    private func handleClient(_ client: Int32) {
        defer { close(client) }

        // Read request
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = read(client, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        var path = String(parts[1])
        if path == "/" { path = "/index.html" }

        // URL decode
        path = path.removingPercentEncoding ?? path

        // Remove query string
        if let qIndex = path.firstIndex(of: "?") {
            path = String(path[..<qIndex])
        }

        // Remove leading slash
        let relativePath = String(path.dropFirst())

        let filePath = "\(amicaBasePath)/\(relativePath)"

        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            // Try with .html
            let htmlPath = "\(amicaBasePath)/\(relativePath).html"
            if FileManager.default.fileExists(atPath: htmlPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: htmlPath)) {
                sendResponse(client: client, data: data, mimeType: "text/html", statusCode: 200)
                return
            }
            sendResponse(client: client, data: Data("Not Found".utf8), mimeType: "text/plain", statusCode: 404)
            return
        }

        let ext = (filePath as NSString).pathExtension
        let mimeType = Self.mimeType(for: ext)
        sendResponse(client: client, data: data, mimeType: mimeType, statusCode: 200)
    }

    private func sendResponse(client: Int32, data: Data, mimeType: String, statusCode: Int) {
        let statusText = statusCode == 200 ? "OK" : "Not Found"
        var header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        header += "Content-Type: \(mimeType)\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        let headerData = Data(header.utf8)
        headerData.withUnsafeBytes { ptr in
            _ = write(client, ptr.baseAddress!, headerData.count)
        }
        data.withUnsafeBytes { ptr in
            _ = write(client, ptr.baseAddress!, data.count)
        }
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
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
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Amica Full View

struct AmicaFullView: UIViewRepresentable {
    var memoryStore: MemoryStore

    func makeCoordinator() -> Coordinator {
        Coordinator(memoryStore: memoryStore)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Start local server
        AmicaLocalServer.shared.start()
        let port = AmicaLocalServer.shared.port

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "nativeAI")

        // Inject native config before page loads
        let defaults = UserDefaults.standard
        let ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "elevenlabs"
        let sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "none"
        let visionBackend = defaults.string(forKey: "amica_vision_backend") ?? "none"
        let elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "EXAVITQu4vr4xnSDxMaL"
        var elevenLabsKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
        // Temp hardcode for testing - remove after confirming it works
        if elevenLabsKey.isEmpty {
            elevenLabsKey = "sk_543bd57e4491227db8bf599e6af48dc10a777818dac5c004"
        }

        let settingsScript = WKUserScript(
            source: """
            // Clear ALL old cached config from localStorage
            try {
                var keys = Object.keys(localStorage);
                for (var i = 0; i < keys.length; i++) {
                    if (keys[i].startsWith('chatvrm_')) {
                        localStorage.removeItem(keys[i]);
                    }
                }
            } catch(e) {}
            window.__nativeConfig = {
                chatbot_backend: 'native_ios',
                tts_backend: '\(ttsBackend)',
                stt_backend: '\(sttBackend)',
                vision_backend: '\(visionBackend)',
                elevenlabs_apikey: '\(elevenLabsKey)',
                elevenlabs_voiceid: '\(elevenLabsVoiceId)',
                elevenlabs_model: 'eleven_flash_v2_5'
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(settingsScript)

        // Console forwarding
        let consoleScript = WKUserScript(
            source: """
            (function() {
                var origLog = console.log, origError = console.error;
                function send(level, args) {
                    try { window.webkit.messageHandlers.nativeAI.postMessage(JSON.stringify({
                        type: 'console', level: level, message: Array.from(args).map(String).join(' ')
                    })); } catch(e) {}
                }
                console.log = function() { send('log', arguments); origLog.apply(console, arguments); };
                console.error = function() { send('error', arguments); origError.apply(console, arguments); };
                window.onerror = function(msg, url, line) { send('error', ['JS: ' + msg + ' at ' + url + ':' + line]); };
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

        // Load from local HTTP server (not custom scheme — so fetch() works with CORS)
        if port > 0 {
            let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
            logger.info("[Amica] Loading from \(url)")
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
        let speechManager = SpeechManager()

        init(memoryStore: MemoryStore) {
            self.memoryStore = memoryStore
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("[Amica] Page loaded")
            DebugLog.shared.add("Page loaded")
            // Log the injected config
            webView.evaluateJavaScript("JSON.stringify(window.__nativeConfig || 'NOT SET')") { result, _ in
                DebugLog.shared.add("__nativeConfig: \(result ?? "nil")")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.info("[Amica] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.info("[Amica] Provisional navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            return .allow
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType) async -> WKPermissionDecision {
            return .grant
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
                logger.info("[Amica-JS] [\(level)] \(msg)")
                DebugLog.shared.add("[\(level)] \(msg)")
            default:
                break
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

// MARK: - Notification for Settings Changes

extension Notification.Name {
    static let amicaSettingsChanged = Notification.Name("amicaSettingsChanged")
}
