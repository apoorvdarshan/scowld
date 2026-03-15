import SwiftUI
import WebKit
import UIKit
import AVFoundation
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
    @State private var messageText = ""
    @State private var amicaCoordinator: AmicaFullView.Coordinator?
    @State private var cameraEnabled = false
    @State private var showSettings = false
    @State private var showMemories = false
    @State private var voiceManager = VoiceManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AmicaFullView(memoryStore: memoryStore, onCoordinatorReady: { coord in
                    amicaCoordinator = coord
                })
                .ignoresSafeArea()

                // Live caption of what user is saying
                if voiceManager.state == .listening && !voiceManager.transcriptText.isEmpty {
                    Text(voiceManager.transcriptText)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6))
                        .cornerRadius(16)
                        .padding(.bottom, 70)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Scowld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            cameraEnabled.toggle()
                            amicaCoordinator?.webView?.evaluateJavaScript(
                                "window.__toggleWebcam && window.__toggleWebcam(\(cameraEnabled));"
                            )
                        } label: {
                            Label(
                                cameraEnabled ? "Disable Camera" : "Enable Camera",
                                systemImage: cameraEnabled ? "eye.fill" : "eye.slash"
                            )
                        }

                        Divider()

                        Button { showMemories = true } label: {
                            Label("Memories", systemImage: "brain.head.profile.fill")
                        }
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        toggleHandsFree()
                    } label: {
                        Image(systemName: handsFreeIconName)
                            .foregroundStyle(handsFreeIconColor)
                    }

                    TextField("Message...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { stopAndSend() }

                    Button {
                        stopAndSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.amicaBlue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(memoryStore: memoryStore)
        }
        .onChange(of: showSettings) {
            if !showSettings {
                let handsFree = UserDefaults.standard.bool(forKey: "hands_free_mode")
                voiceManager.isEnabled = handsFree
            }
        }
        .sheet(isPresented: $showMemories) {
            NavigationStack {
                MemoryView(memoryStore: memoryStore)
            }
        }
        .onAppear {
            // Start in playback mode so TTS works through speaker
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)

            Task {
                _ = await SpeechManager().requestPermissions()
            }

            setupVoice()
        }
        .onChange(of: voiceManager.readyCommand) {
            if let text = voiceManager.readyCommand {
                voiceManager.readyCommand = nil
                messageText = text
                sendMessage()
                logger.info("[WakeWord] Command sent: \(text)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttsDone)) { _ in
            voiceManager.onTTSDone()
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                if voiceManager.isEnabled {
                    voiceManager.startListening()
                }
            case .inactive, .background:
                if voiceManager.isEnabled {
                    voiceManager.stop()
                }
            @unknown default:
                break
            }
        }
    }

    private var handsFreeIconName: String {
        voiceManager.isEnabled ? "waveform" : "waveform.slash"
    }

    private var handsFreeIconColor: Color {
        voiceManager.isEnabled ? .amicaBlue : .secondary
    }

    private func toggleHandsFree() {
        voiceManager.isEnabled.toggle()
        UserDefaults.standard.set(voiceManager.isEnabled, forKey: "hands_free_mode")
        if voiceManager.isEnabled {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    private func stopAndSend() {
        sendMessage()
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        // Pause listening so TTS plays through speaker
        if voiceManager.isEnabled {
            voiceManager.pauseForTTS()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        logger.info("[HomeView] Sending message: \(text)")

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        amicaCoordinator?.webView?.evaluateJavaScript(
            "window.__sendMessageFromNative && window.__sendMessageFromNative('\(escaped)');"
        ) { result, error in
            if let error {
                logger.info("[HomeView] JS error: \(error.localizedDescription)")
            } else {
                logger.info("[HomeView] Message sent OK")
            }
        }
    }


    // MARK: - Wake Word

    private func setupVoice() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hands_free_mode") == nil {
            defaults.set(true, forKey: "hands_free_mode")
        }
        voiceManager.isEnabled = defaults.bool(forKey: "hands_free_mode")
    }

    private func stopTTS() {
        amicaCoordinator?.webView?.evaluateJavaScript("""
            (function() {
                // Stop all AudioContext sources
                if (window._allAudioContexts) {
                    window._allAudioContexts.forEach(function(ctx) {
                        try { ctx.close(); } catch(e) {}
                    });
                    window._allAudioContexts = [];
                }
                // Pause all HTML5 audio elements
                document.querySelectorAll('audio').forEach(function(a) {
                    a.pause();
                    a.currentTime = 0;
                });
                // Stop any speech synthesis
                if (window.speechSynthesis) {
                    window.speechSynthesis.cancel();
                }
            })();
        """)
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

        // Read full request (headers + body)
        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        var contentLength = 0
        var headerEnd = 0

        // First read — usually gets headers + body for small requests
        let firstRead = read(client, &buffer, buffer.count)
        guard firstRead > 0 else { return }
        allData.append(contentsOf: buffer[0..<firstRead])

        // Find header/body boundary
        guard let sepRange = allData.range(of: separator) else { return }
        headerEnd = sepRange.upperBound

        // Parse Content-Length
        if let hdrStr = String(data: allData[0..<sepRange.lowerBound], encoding: .utf8) {
            for line in hdrStr.components(separatedBy: "\r\n") {
                if line.lowercased().hasPrefix("content-length:") {
                    contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        }

        // If we know Content-Length, read until we have it all
        if contentLength > 0 {
            let totalNeeded = headerEnd + contentLength
            while allData.count < totalNeeded {
                let n = read(client, &buffer, min(buffer.count, totalNeeded - allData.count))
                if n <= 0 { break }
                allData.append(contentsOf: buffer[0..<n])
            }
        } else {
            // No Content-Length — try reading more with a short poll
            var pollFd = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            while Darwin.poll(&pollFd, 1, 50) > 0 { // 50ms timeout
                let n = read(client, &buffer, buffer.count)
                if n <= 0 { break }
                allData.append(contentsOf: buffer[0..<n])
            }
        }

        // Body = everything after headers
        let requestBody: Data? = headerEnd < allData.count ? Data(allData[headerEnd...]) : nil

        let headerStr = String(data: allData[0..<sepRange.lowerBound], encoding: .utf8) ?? ""
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        let method = String(parts[0])
        var path = String(parts[1])
        if path == "/" { path = "/index.html" }

        // URL decode
        path = path.removingPercentEncoding ?? path

        // MARK: - ElevenLabs TTS Proxy
        // Intercept /api/elevenlabs/* and proxy to api.elevenlabs.io (bypasses CORS)
        if path.hasPrefix("/api/elevenlabs/") {
            let elPath = String(path.dropFirst("/api/elevenlabs".count))
            handleElevenLabsProxy(client: client, method: method, elPath: elPath, body: requestBody)
            return
        }

        // MARK: - OpenAI TTS Proxy
        if path.hasPrefix("/api/openai-tts/") {
            let oaiPath = String(path.dropFirst("/api/openai-tts".count))
            handleOpenAITTSProxy(client: client, method: method, oaiPath: oaiPath, body: requestBody)
            return
        }

        // MARK: - CORS Preflight
        if method == "OPTIONS" {
            sendCORSPreflight(client: client)
            return
        }

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

    private func sendCORSPreflight(client: Int32) {
        var header = "HTTP/1.1 204 No Content\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        header += "Access-Control-Allow-Headers: Content-Type, xi-api-key, Authorization, Accept\r\n"
        header += "Access-Control-Max-Age: 86400\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        let headerData = Data(header.utf8)
        headerData.withUnsafeBytes { ptr in
            _ = write(client, ptr.baseAddress!, headerData.count)
        }
    }

    private func handleElevenLabsProxy(client: Int32, method: String, elPath: String, body: Data?) {
        let apiKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
        guard !apiKey.isEmpty else {
            sendResponse(client: client, data: Data("{\"error\":\"No ElevenLabs API key\"}".utf8), mimeType: "application/json", statusCode: 401)
            return
        }

        // Build query string from original path
        let fullPath = elPath.hasPrefix("/") ? elPath : "/\(elPath)"
        let urlStr = "https://api.elevenlabs.io/v1\(fullPath)"
        guard let url = URL(string: urlStr) else {
            sendResponse(client: client, data: Data("Bad URL".utf8), mimeType: "text/plain", statusCode: 400)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        if method == "POST" {
            urlRequest.httpBody = body
        }

        logger.info("[Proxy] ElevenLabs \(method) \(fullPath) bodyLen=\(body?.count ?? 0) keyLen=\(apiKey.count) keyPrefix=\(String(apiKey.prefix(4)))")
        if let body, let bodyStr = String(data: body, encoding: .utf8) {
            logger.info("[Proxy] ElevenLabs body: \(bodyStr.prefix(200))")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var responseCode = 500
        var responseMime = "application/octet-stream"

        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let httpResp = response as? HTTPURLResponse {
                responseCode = httpResp.statusCode
                responseMime = httpResp.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg"
            }
            if let data { responseData = data }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        logger.info("[Proxy] ElevenLabs \(method) \(fullPath) -> \(responseCode) (\(responseData.count) bytes)")
        if responseCode != 200, let errStr = String(data: responseData, encoding: .utf8) {
            logger.error("[Proxy] ElevenLabs error: \(errStr.prefix(300))")
        }
        sendResponse(client: client, data: responseData, mimeType: responseMime, statusCode: responseCode)
    }

    private func handleOpenAITTSProxy(client: Int32, method: String, oaiPath: String, body: Data?) {
        let apiKey = KeychainManager.load(key: AIProvider.openai.keychainKey) ?? ""
        guard !apiKey.isEmpty else {
            sendResponse(client: client, data: Data("{\"error\":\"No OpenAI API key\"}".utf8), mimeType: "application/json", statusCode: 401)
            return
        }

        let fullPath = oaiPath.hasPrefix("/") ? oaiPath : "/\(oaiPath)"
        let urlStr = "https://api.openai.com/v1\(fullPath)"
        guard let url = URL(string: urlStr) else {
            sendResponse(client: client, data: Data("Bad URL".utf8), mimeType: "text/plain", statusCode: 400)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if method == "POST" {
            urlRequest.httpBody = body
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var responseCode = 500
        var responseMime = "application/octet-stream"

        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let httpResp = response as? HTTPURLResponse {
                responseCode = httpResp.statusCode
                responseMime = httpResp.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg"
            }
            if let data { responseData = data }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        logger.info("[Proxy] OpenAI TTS \(method) \(fullPath) -> \(responseCode) (\(responseData.count) bytes)")
        sendResponse(client: client, data: responseData, mimeType: responseMime, statusCode: responseCode)
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
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(memoryStore: memoryStore)
        DispatchQueue.main.async { onCoordinatorReady?(coord) }
        return coord
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
        let sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "native_ios"
        let selectedProviderStr = defaults.string(forKey: "selectedProvider") ?? "gemini"
        let visionEnabled = AIProvider(rawValue: selectedProviderStr)?.supportsVision ?? false
        let visionBackend = visionEnabled ? "native_ios" : "none"
        let elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "cgSgspJ2msm6clMCkdW9"
        let elevenLabsKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
        let openaiKey = KeychainManager.load(key: AIProvider.openai.keychainKey) ?? ""
        let characterName = defaults.string(forKey: "character_name") ?? "Scowlly"

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
                elevenlabs_model: 'eleven_flash_v2_5',
                openai_tts_apikey: '\(openaiKey)',
                name: '\(characterName)',
                system_prompt: 'You are \(characterName), a warm, cheerful, and expressive AI companion.'
            };
            // Force full screen coverage
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
            document.head?.appendChild(meta);
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

        // Resume AudioContext for TTS audio playback
        let audioResumeScript = WKUserScript(
            source: """
            (function() {
                // Resume all AudioContexts periodically and on interaction
                function resumeAll() {
                    try {
                        var ctxs = [window._audioContext, window.audioContext];
                        // Find AudioContexts in Amica's React state
                        document.querySelectorAll('*').forEach(function() {});
                        if (typeof AudioContext !== 'undefined') {
                            var origAC = AudioContext;
                            window._allAudioContexts = window._allAudioContexts || [];
                            window.AudioContext = function(opts) {
                                var ctx = new origAC(opts);
                                window._allAudioContexts.push(ctx);
                                return ctx;
                            };
                            window.AudioContext.prototype = origAC.prototype;
                        }
                        (window._allAudioContexts || []).forEach(function(ctx) {
                            if (ctx && ctx.state === 'suspended') {
                                ctx.resume().then(function() {
                                    console.log('[Audio] Resumed AudioContext, state: ' + ctx.state);
                                });
                            }
                        });
                    } catch(e) {}
                }
                // Track all created AudioContexts
                var _OrigAC = window.AudioContext || window.webkitAudioContext;
                window._allAudioContexts = [];
                window.AudioContext = function(opts) {
                    var ctx = new _OrigAC(opts);
                    window._allAudioContexts.push(ctx);
                    console.log('[Audio] New AudioContext created, state: ' + ctx.state);
                    return ctx;
                };
                if (_OrigAC) {
                    Object.keys(_OrigAC).forEach(function(k) { window.AudioContext[k] = _OrigAC[k]; });
                    window.AudioContext.prototype = _OrigAC.prototype;
                }
                window.webkitAudioContext = window.AudioContext;

                document.addEventListener('touchstart', resumeAll, {once: false});
                document.addEventListener('click', resumeAll, {once: false});
                setInterval(function() {
                    (window._allAudioContexts || []).forEach(function(ctx) {
                        if (ctx && ctx.state === 'suspended') {
                            ctx.resume();
                        }
                    });
                }, 1000);

                // Track active audio sources to detect when TTS finishes
                window.__activeAudioCount = 0;
                var _ttsDoneTimer = null;
                function notifyTTSDone() {
                    window.__activeAudioCount--;
                    if (window.__activeAudioCount <= 0) {
                        window.__activeAudioCount = 0;
                        // Debounce: wait 3s to make sure no new audio chunks start
                        if (_ttsDoneTimer) clearTimeout(_ttsDoneTimer);
                        _ttsDoneTimer = setTimeout(function() {
                            if (window.__activeAudioCount <= 0) {
                                try {
                                    window.webkit.messageHandlers.nativeAI.postMessage(JSON.stringify({type: 'tts_done'}));
                                } catch(e) {}
                            }
                        }, 3000);
                    }
                }
                // Hook Audio elements
                var _origAudioPlay = HTMLAudioElement.prototype.play;
                HTMLAudioElement.prototype.play = function() {
                    var self = this;
                    window.__activeAudioCount++;
                    self.addEventListener('ended', notifyTTSDone, {once: true});
                    self.addEventListener('error', notifyTTSDone, {once: true});
                    return _origAudioPlay.apply(self, arguments);
                };
                // Hook AudioContext.decodeAudioData + createBufferSource
                if (_OrigAC) {
                    var _origCreateBS = _OrigAC.prototype.createBufferSource;
                    _OrigAC.prototype.createBufferSource = function() {
                        var src = _origCreateBS.apply(this, arguments);
                        var _origStart = src.start.bind(src);
                        src.start = function() {
                            window.__activeAudioCount++;
                            src.addEventListener('ended', notifyTTSDone, {once: true});
                            return _origStart.apply(null, arguments);
                        };
                        return src;
                    };
                }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(audioResumeScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.underPageBackgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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
        let memoryExtractor = MemoryExtractor()

        private var settingsObserver: NSObjectProtocol?

        init(memoryStore: MemoryStore) {
            self.memoryStore = memoryStore
            super.init()
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .amicaSettingsChanged, object: nil, queue: .main
            ) { [weak self] _ in
                self?.pushUpdatedConfig()
            }
        }

        deinit {
            if let observer = settingsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func pushUpdatedConfig() {
            let defaults = UserDefaults.standard
            let ttsBackend = defaults.string(forKey: "amica_tts_backend") ?? "elevenlabs"
            let sttBackend = defaults.string(forKey: "amica_stt_backend") ?? "native_ios"
            let elevenLabsKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
            let elevenLabsVoiceId = defaults.string(forKey: "amica_elevenlabs_voiceid") ?? "cgSgspJ2msm6clMCkdW9"
            let openaiKey = KeychainManager.load(key: AIProvider.openai.keychainKey) ?? ""
            let selectedProviderStr = defaults.string(forKey: "selectedProvider") ?? "gemini"
            let visionEnabled = AIProvider(rawValue: selectedProviderStr)?.supportsVision ?? false
            let visionBackend = visionEnabled ? "native_ios" : "none"
            let characterName = defaults.string(forKey: "character_name") ?? "Scowlly"

            let js = """
                window.__nativeConfig = {
                    chatbot_backend: 'native_ios',
                    tts_backend: '\(ttsBackend)',
                    stt_backend: '\(sttBackend)',
                    vision_backend: '\(visionBackend)',
                    elevenlabs_apikey: '\(elevenLabsKey)',
                    elevenlabs_voiceid: '\(elevenLabsVoiceId)',
                    elevenlabs_model: 'eleven_flash_v2_5',
                    openai_tts_apikey: '\(openaiKey)',
                    name: '\(characterName)'
                };
            """
            webView?.evaluateJavaScript(js)
            logger.info("[Amica] Pushed updated config to WebView")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("[Amica] Page loaded")
            // Force full-screen coverage via CSS
            webView.evaluateJavaScript("""
                var s = document.createElement('style');
                s.textContent = 'html, body { margin: 0; padding: 0; width: 100%; height: 100%; } body { padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); box-sizing: border-box; } canvas { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; }';
                document.head.appendChild(s);
                var vm = document.querySelector('meta[name=viewport]');
                if (vm) vm.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover, user-scalable=no';
            """)
            // Zoom out camera after a delay (viewer needs time to initialize)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                webView.evaluateJavaScript("""
                    if (window.__viewer?.camera) {
                        window.__viewer.camera.position.z += 0.5;
                    }
                    // Try Amica's resetCamera with offset
                    try {
                        var cam = document.querySelector('canvas')?.__three_camera;
                        if (!cam) {
                            // Find camera in Three.js scene
                            var scenes = Object.values(window).filter(v => v && v.isScene);
                        }
                    } catch(e) {}
                """)
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
                let imageData = json["imageData"] as? String
                Task { await handleChatRequest(callbackId: callbackId, messages: messages, imageData: imageData) }
            case "tts_elevenlabs":
                guard let callbackId = json["callbackId"] as? String,
                      let voiceId = json["voiceId"] as? String,
                      let bodyStr = json["body"] as? String else { return }
                Task { await handleElevenLabsTTS(callbackId: callbackId, voiceId: voiceId, body: bodyStr) }
            case "speak":
                if let text = json["text"] as? String {
                    speechManager.speak(text)
                }
            case "tts_done":
                logger.info("[Amica] TTS playback finished")
                NotificationCenter.default.post(name: .ttsDone, object: nil)
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

        private func handleChatRequest(callbackId: String, messages: [[String: String]], imageData: String? = nil) async {
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

            // Check if current provider supports vision
            let defaults = UserDefaults.standard
            let providerStr = defaults.string(forKey: "selectedProvider") ?? "gemini"
            let currentProvider = AIProvider(rawValue: providerStr)
            let supportsVision = currentProvider?.supportsVision ?? false

            // Build system prompt with memory log and character name
            let contextBuilder = ContextBuilder(memoryStore: memoryStore)
            let systemPrompt = contextBuilder.buildSystemPrompt()

            do {
                let response: String
                if supportsVision,
                   let imageBase64 = imageData,
                   !imageBase64.isEmpty,
                   let imgData = Data(base64Encoded: imageBase64),
                   let image = UIImage(data: imgData) {
                    // Vision request — send image with the message
                    logger.info("[Amica] Vision request with image: \(imgData.count) bytes")
                    response = try await provider.generateWithVision(
                        messages: chatMessages, systemPrompt: systemPrompt, image: image
                    )
                } else {
                    response = try await provider.generate(messages: chatMessages, systemPrompt: systemPrompt)
                }
                await MainActor.run {
                    deliverResponse(callbackId: callbackId, response: response)
                }

                // Update memory log in background
                let lastUserMsg = chatMessages.last(where: { $0.role == .user })?.content ?? ""
                let currentLog = memoryStore.getActiveMemoryLog()
                Task.detached { [memoryExtractor, memoryStore] in
                    await memoryExtractor.updateMemoryLog(
                        userMessage: lastUserMsg,
                        aiResponse: response,
                        currentLog: currentLog,
                        using: provider,
                        store: memoryStore
                    )
                }
            } catch {
                await MainActor.run {
                    deliverError(callbackId: callbackId, error: error.localizedDescription)
                }
            }
        }

        // MARK: - Native ElevenLabs TTS

        private func handleElevenLabsTTS(callbackId: String, voiceId: String, body: String) async {
            let apiKey = KeychainManager.load(key: "com.scowld.elevenlabs.apikey") ?? ""
            guard !apiKey.isEmpty else {
                await MainActor.run {
                    let escaped = "No ElevenLabs API key".replacingOccurrences(of: "'", with: "\\'")
                    webView?.evaluateJavaScript("window['__ttsError_\(callbackId)'] && window['__ttsError_\(callbackId)']('\(escaped)')")
                }
                return
            }

            let urlStr = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)?output_format=mp3_44100_128"
            guard let url = URL(string: urlStr) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.httpBody = body.data(using: .utf8)

            logger.info("[TTS] ElevenLabs request: voice=\(voiceId) bodyLen=\(body.count)")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return }

                if httpResponse.statusCode == 200 {
                    let base64 = data.base64EncodedString()
                    logger.info("[TTS] ElevenLabs success: \(data.count) bytes")
                    await MainActor.run {
                        webView?.evaluateJavaScript("window['__ttsCallback_\(callbackId)'] && window['__ttsCallback_\(callbackId)']('\(base64)')")
                    }
                } else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    logger.error("[TTS] ElevenLabs error \(httpResponse.statusCode): \(errorBody)")
                    logger.error("[TTS] Sent body: \(body.prefix(300))")
                    await MainActor.run {
                        let detail = errorBody.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\n", with: " ").prefix(200)
                        webView?.evaluateJavaScript("window['__ttsError_\(callbackId)'] && window['__ttsError_\(callbackId)']('ElevenLabs \(httpResponse.statusCode): \(detail)')")
                    }
                }
            } catch {
                logger.error("[TTS] ElevenLabs network error: \(error.localizedDescription)")
                await MainActor.run {
                    let escaped = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
                    webView?.evaluateJavaScript("window['__ttsError_\(callbackId)'] && window['__ttsError_\(callbackId)']('\(escaped)')")
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

            // OpenAI-compatible providers (OpenRouter, xAI, Together AI, etc.)
            if let baseURL = provider.baseURL {
                guard let apiKey = KeychainManager.load(key: provider.keychainKey), !apiKey.isEmpty else { return nil }
                return OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey, model: model)
            }

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
            default:
                return nil
            }
        }
    }
}

// MARK: - Notification for Settings Changes

extension Notification.Name {
    static let amicaSettingsChanged = Notification.Name("amicaSettingsChanged")
    static let ttsDone = Notification.Name("ttsDone")
}
