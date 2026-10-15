import SwiftUI
import WebKit
import UIKit
import AVFoundation
import AudioToolbox
import os

private let logger = Logger(subsystem: "com.apoorvdarshan.Scowld", category: "Amica")

private enum InteractionFeedback {
    static func tap() {
        AudioServicesPlaySystemSound(SystemSoundID(1104))
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }

    static func liveStart() {
        AudioServicesPlaySystemSound(SystemSoundID(1113))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
    }

    static func liveEnd() {
        AudioServicesPlaySystemSound(SystemSoundID(1114))
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    static func camera(isOn: Bool) {
        AudioServicesPlaySystemSound(SystemSoundID(isOn ? 1104 : 1103))
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: isOn ? 0.55 : 0.75)
    }
}

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
    var isActive = true
    /// Shows the Settings tab, where the provider key is added.
    var openSettings: () -> Void = {}
    @State private var amicaCoordinator: AmicaFullView.Coordinator?
    @State private var live: LiveConversation
    @State private var camera = LiveCamera()
    @State private var handsFreeWakeListener = HandsFreeWakeListener()
    @State private var microphoneGranted = false
    @State private var speechRecognitionGranted = false
    @State private var showHomeTips = false
    @State private var hasProviderKey = true
    @AppStorage("camera_enabled") private var cameraOn = false
    @AppStorage("show_ai_caption") private var showAICaption = false
    @AppStorage("hands_free_mode_enabled") private var handsFreeModeEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(memoryStore: MemoryStore, isActive: Bool = true, openSettings: @escaping () -> Void = {}) {
        self.memoryStore = memoryStore
        self.isActive = isActive
        self.openSettings = openSettings
        _live = State(initialValue: LiveConversation(memoryStore: memoryStore))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if ScowldTestEnvironment.loadsCompanion {
                    AmicaFullView(memoryStore: memoryStore, onCoordinatorReady: { coord in
                        amicaCoordinator = coord
                        coord.setRuntimeActive(isActive)
                    })
                    .ignoresSafeArea()
                } else {
                    // UI tests leave the 3D companion out (see ScowldTestEnvironment).
                    Color.black.ignoresSafeArea()
                }

                // Captions of what she is saying
                VStack(spacing: 6) {
                    if showAICaption && !live.assistantCaption.isEmpty {
                        Text(live.assistantCaption)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.5))
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .allowsHitTesting(false)
            }
            .navigationTitle("Scowld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHomeTips = true
                        InteractionFeedback.tap()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Show home tips")
                    .accessibilityIdentifier("chat.tips")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    statusPill
                    composerBar
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.18), value: liveStatus?.text)
            }
        }
        .sheet(isPresented: $showHomeTips) {
            HomeTipsSheet(wakeName: CharacterPack.resolveCharacterName())
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            HostedServiceConfig.applyBYOKDefaults()
            refreshProviderKey()
            ScowldAudioSession.configureAmicaWebAudioPlayback()
            connectLiveConversation()

            // Tests and screenshot previews never prompt for, or use, the microphone
            // and speech recognition.
            if !ScowldTestEnvironment.isRunningTests, ScowldTestEnvironment.previewTab == nil {
                Task {
                    let granted = await VoicePermissions.request()
                    microphoneGranted = granted.microphone
                    speechRecognitionGranted = granted.speechRecognition
                    updateHandsFreeWakeListener()
                }
            }

            amicaCoordinator?.setRuntimeActive(isActive)
            updateHandsFreeWakeListener()
        }
        .onDisappear {
            stopActiveConversation()
        }
        .onChange(of: isActive) {
            if isActive {
                refreshProviderKey()
                amicaCoordinator?.setRuntimeActive(true)
                updateHandsFreeWakeListener()
            } else {
                stopActiveConversation()
            }
        }
        .onChange(of: live.isActive) {
            updateHandsFreeWakeListener()
            updateCamera()
        }
        .onReceive(NotificationCenter.default.publisher(for: .amicaSettingsChanged)) { _ in
            refreshProviderKey()
            updateHandsFreeWakeListener()
        }
        .onChange(of: handsFreeModeEnabled) {
            updateHandsFreeWakeListener()
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                if isActive {
                    amicaCoordinator?.setRuntimeActive(true)
                    updateHandsFreeWakeListener()
                }
            case .inactive:
                break
            case .background:
                stopActiveConversation()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Composer

    /// Starts and ends a live voice conversation.
    private var liveButton: some View {
        Button {
            toggleLiveConversation()
        } label: {
            ZStack {
                if live.phase == .live && !reduceMotion {
                    // A slow pulse while the conversation is open: red while she
                    // listens, blue while she talks.
                    Circle()
                        .fill((live.isAssistantSpeaking ? Color.amicaBlue : Color.red).opacity(0.3))
                        .phaseAnimator([false, true]) { halo, expanded in
                            halo
                                .scaleEffect(expanded ? 1.22 : 0.9)
                                .opacity(expanded ? 0.25 : 0.9)
                        } animation: { _ in
                            .easeInOut(duration: 1.1)
                        }
                        .allowsHitTesting(false)
                }
                if live.phase == .connecting {
                    ProgressView()
                        .tint(.amicaBlue)
                } else {
                    Image(systemName: live.isActive ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(live.isActive ? Color.red.opacity(0.9) : Color.amicaBlue)
                }
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(live.isActive ? "End live conversation" : "Start live conversation")
        .accessibilityIdentifier("chat.live")
        .accessibilityHint("Talk with her out loud. Speak anytime to interrupt her.")
    }

    private var composerBar: some View {
        HStack(spacing: 7) {
            Button {
                toggleCamera()
            } label: {
                Image(systemName: cameraOn ? "eye.fill" : "eye.slash")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 44, height: 48)
                    .foregroundStyle(cameraOn ? .amicaBlue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cameraOn ? "Turn off camera vision" : "Turn on camera vision")
            .accessibilityIdentifier("chat.camera")

            Spacer(minLength: 12)

            liveButton

            Spacer(minLength: 12)

            handsFreeButton
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .scowldComposerGlass()
    }

    private var handsFreeButton: some View {
        Button {
            toggleHandsFreeMode()
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 44, height: 48)
                .foregroundStyle(handsFreeIconColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(handsFreeModeEnabled ? "Turn off hands-free mode" : "Turn on hands-free mode")
        .accessibilityIdentifier("chat.handsFree")
        .accessibilityHint("Listens for hey Bella or the custom character name.")
    }

    private var handsFreeIconColor: Color {
        guard handsFreeModeEnabled else { return .secondary }
        return handsFreeWakeListener.isRunning ? .amicaBlue : .white.opacity(0.74)
    }

    // MARK: - Live status

    private struct LiveStatus: Equatable {
        let icon: String
        let text: String
        let isError: Bool
        let isBusy: Bool
        var opensSettings = false
    }

    private var liveStatus: LiveStatus? {
        let name = CharacterPack.resolveCharacterName()
        let missingKey = String.localizedStringWithFormat(
            NSLocalizedString("Add your %@ API key in Settings to talk to %@.", comment: "Missing provider key"),
            HostedServiceConfig.selectedProvider().shortName,
            name
        )
        if let error = live.errorMessage {
            return LiveStatus(icon: "exclamationmark.triangle.fill", text: error, isError: true, isBusy: false, opensSettings: error == missingKey)
        }
        switch live.phase {
        case .idle:
            // Until a key is saved, say so up front and link to Settings.
            guard !hasProviderKey else { return nil }
            return LiveStatus(icon: "key.fill", text: missingKey, isError: false, isBusy: false, opensSettings: true)
        case .connecting:
            return LiveStatus(
                icon: "antenna.radiowaves.left.and.right",
                text: String.localizedStringWithFormat(NSLocalizedString("Connecting to %@...", comment: "Live status"), live.provider.shortName),
                isError: false,
                isBusy: true
            )
        case .live where live.isAssistantSpeaking:
            let format = NSLocalizedString("%@ is talking. Speak to interrupt.", comment: "Live status")
            return LiveStatus(icon: "waveform", text: String.localizedStringWithFormat(format, name), isError: false, isBusy: false)
        case .live:
            return LiveStatus(icon: "mic.fill", text: NSLocalizedString("Listening...", comment: "Live status"), isError: false, isBusy: false)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let status = liveStatus {
            if status.opensSettings {
                Button {
                    InteractionFeedback.tap()
                    openSettings()
                } label: {
                    statusPillContent(status)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Settings.")
                .accessibilityIdentifier("chat.status")
            } else {
                statusPillContent(status)
                    .accessibilityIdentifier("chat.status")
            }
        }
    }

    private func statusPillContent(_ status: LiveStatus) -> some View {
        HStack(spacing: 8) {
            if status.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: status.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: status.icon == "waveform" || status.icon == "mic.fill")
                    .accessibilityHidden(true)
            }
            Text(status.text)
                .font(.footnote.weight(.semibold))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if status.opensSettings {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(status.isError ? Color.red.opacity(0.95) : Color.white.opacity(0.92))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    // MARK: - Actions

    private var canListenForHandsFreeWake: Bool {
        isActive &&
            scenePhase == .active &&
            handsFreeModeEnabled &&
            microphoneGranted &&
            speechRecognitionGranted &&
            !live.isActive
    }

    private func refreshProviderKey() {
        let provider = HostedServiceConfig.selectedProvider()
        hasProviderKey = KeychainManager.exists(key: provider.keychainKey)
    }

    private func connectLiveConversation() {
        live.onLipSync = { chunk in
            amicaCoordinator?.enqueueLipSync(chunk)
        }
        live.onLipSyncStop = {
            amicaCoordinator?.stopLipSync()
        }
        live.captureCameraFrame = { [camera] in
            camera.latestJPEG()
        }
        live.isCameraOn = {
            UserDefaults.standard.bool(forKey: "camera_enabled")
        }
        live.onEnded = {
            updateHandsFreeWakeListener()
        }
    }

    private func toggleLiveConversation() {
        if live.isActive {
            live.end()
            InteractionFeedback.liveEnd()
            return
        }
        guard !ScowldTestEnvironment.isRunningTests else { return }
        guard !VoicePermissions.microphoneDenied else {
            live.end(error: NSLocalizedString("Allow microphone access in iPhone Settings to talk with her.", comment: "Microphone denied"))
            return
        }
        // The live conversation needs the microphone the wake listener holds.
        handsFreeWakeListener.stop(waitUntilStopped: true)
        InteractionFeedback.liveStart()
        if VoicePermissions.microphoneGranted {
            live.start()
        } else {
            Task {
                let granted = await VoicePermissions.request()
                microphoneGranted = granted.microphone
                speechRecognitionGranted = granted.speechRecognition
                if granted.microphone {
                    live.start()
                } else {
                    live.end(error: NSLocalizedString("Allow microphone access in iPhone Settings to talk with her.", comment: "Microphone denied"))
                }
            }
        }
    }

    private func toggleCamera() {
        if !cameraOn, LiveCamera.isDenied {
            live.end(error: NSLocalizedString("Allow camera access in iPhone Settings so she can see.", comment: "Camera denied"))
            return
        }
        cameraOn.toggle()
        InteractionFeedback.camera(isOn: cameraOn)
        if cameraOn, !LiveCamera.isAuthorized, !ScowldTestEnvironment.isRunningTests {
            Task {
                if await LiveCamera.requestAccess() {
                    updateCamera()
                } else {
                    cameraOn = false
                }
            }
        }
        updateCamera()
    }

    /// The camera runs only while the eye is on during a conversation.
    private func updateCamera() {
        guard !ScowldTestEnvironment.isRunningTests else { return }
        if cameraOn && live.isActive && isActive {
            camera.start()
        } else {
            camera.stop()
        }
    }

    private func toggleHandsFreeMode() {
        handsFreeModeEnabled.toggle()
        InteractionFeedback.tap()
        updateHandsFreeWakeListener()
    }

    private func updateHandsFreeWakeListener() {
        guard canListenForHandsFreeWake else {
            handsFreeWakeListener.stop()
            return
        }

        handsFreeWakeListener.start(wakeName: CharacterPack.resolveCharacterName()) {
            handleHandsFreeWake()
        }
    }

    private func handleHandsFreeWake() {
        handsFreeWakeListener.stop()
        guard handsFreeModeEnabled, !live.isActive, microphoneGranted else {
            updateHandsFreeWakeListener()
            return
        }

        InteractionFeedback.liveStart()
        live.start()
    }

    private func stopActiveConversation() {
        handsFreeWakeListener.stop()
        live.end()
        camera.stop()
        amicaCoordinator?.cancelRuntimeWork()
    }
}

private struct HomeTipsSheet: View {
    let wakeName: String
    @Environment(\.dismiss) private var dismiss

    private var trimmedWakeName: String {
        let trimmed = wakeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bella" : trimmed
    }

    private var wakeText: String {
        if trimmedWakeName.caseInsensitiveCompare("Bella") == .orderedSame {
            return "Say \"Bella\" or \"hey Bella\". If you set a custom name, say that name or \"hey\" plus it."
        }

        return "Say \"\(trimmedWakeName)\" or \"hey \(trimmedWakeName)\" while hands-free is on. \"Bella\" still works too."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    tipRow(icon: "dot.radiowaves.left.and.right", title: "Hands-free wake", text: wakeText)
                    tipRow(icon: "mic.circle.fill", title: "Live voice", text: "Starts a live conversation. Talk naturally and speak anytime to interrupt her. Tap stop to end it.")
                    tipRow(icon: "eye.fill", title: "Eye", text: "Lets her see your front camera during a conversation, with Gemini or OpenAI. It's off until you turn it on.")
                }

                Section {
                    Text("Hands-free only listens when the app is open, idle, and the hands-free icon is enabled. A live conversation ends by itself after 90 seconds of silence.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Home Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func tipRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.amicaBlue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
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
        _ = withUnsafeMutablePointer(to: &assignedAddr) {
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
        header += "Access-Control-Allow-Headers: Content-Type, Accept\r\n"
        header += "Access-Control-Max-Age: 86400\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        let headerData = Data(header.utf8)
        headerData.withUnsafeBytes { ptr in
            _ = write(client, ptr.baseAddress!, headerData.count)
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

        let interactionBlockerScript = WKUserScript(
            source: """
            (function() {
                if (window.__scowldInteractionBlockerInstalled) return;
                window.__scowldInteractionBlockerInstalled = true;

                function installStyle() {
                    try {
                        if (document.getElementById('scowld-interaction-blocker-style')) return;
                        var style = document.createElement('style');
                        style.id = 'scowld-interaction-blocker-style';
                        style.textContent = '*{-webkit-touch-callout:none!important;-webkit-user-select:none!important;user-select:none!important;-webkit-user-drag:none!important}::selection{background:transparent!important;color:inherit!important}';
                        (document.head || document.documentElement).appendChild(style);
                    } catch(e) {}
                }

                function preventNativeMenu(event) {
                    event.preventDefault();
                    event.stopPropagation();
                    return false;
                }

                ['contextmenu', 'selectstart', 'dragstart', 'copy', 'cut'].forEach(function(type) {
                    document.addEventListener(type, preventNativeMenu, true);
                });
                installStyle();
                document.addEventListener('DOMContentLoaded', installStyle);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(interactionBlockerScript)

        // Inject native config before page loads. Conversations run natively (live
        // voice), so the page only renders the companion: it never chats or speaks.
        let settingsScript = WKUserScript(
            source: Coordinator.pageConfigScript(clearCachedSettings: true),
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

        // Live replies play natively (with echo cancellation), so the avatar's own
        // lip-sync analyser hears nothing. This bridge feeds it the reply's levels:
        // native code sends each chunk's levels and when it starts, and the analyser
        // reports the level due now. The avatar turns that into mouth movement.
        let lipSyncScript = WKUserScript(
            source: """
            (function() {
                if (window.__scowldLip) return;
                var timeline = [];
                function levelNow() {
                    var now = performance.now();
                    while (timeline.length && timeline[0].start + timeline[0].step * timeline[0].levels.length < now) {
                        timeline.shift();
                    }
                    var segment = timeline[0];
                    if (!segment || now < segment.start) return 0;
                    return segment.levels[Math.floor((now - segment.start) / segment.step)] || 0;
                }
                window.__scowldLip = {
                    enqueue: function(delayMs, stepMs, levels) {
                        timeline.push({ start: performance.now() + delayMs, step: stepMs, levels: levels });
                    },
                    clear: function() { timeline.length = 0; }
                };
                var proto = window.AnalyserNode && window.AnalyserNode.prototype;
                if (!proto || !proto.getFloatTimeDomainData) return;
                var original = proto.getFloatTimeDomainData;
                proto.getFloatTimeDomainData = function(array) {
                    original.call(this, array);
                    var level = levelNow();
                    if (level > 0 && array && array.length) {
                        array[0] = Math.max(Math.abs(array[0]), level);
                    }
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(lipSyncScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.underPageBackgroundColor = .black
        webView.allowsLinkPreview = false
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

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

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        let memoryStore: MemoryStore

        private var settingsObserver: NSObjectProtocol?
        private var isRuntimeActive = true
        private var appliedPageConfig = Coordinator.pageConfigScript(clearCachedSettings: false)

        init(memoryStore: MemoryStore) {
            self.memoryStore = memoryStore
            super.init()
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .amicaSettingsChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pushUpdatedConfig()
                }
            }
        }

        deinit {
            if let observer = settingsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func setRuntimeActive(_ active: Bool) {
            isRuntimeActive = active
            if !active {
                stopLipSync()
            }
        }

        func cancelRuntimeWork() {
            isRuntimeActive = false
            stopLipSync()
        }

        // MARK: Page config

        /// What the page needs to render the companion: her name and avatar. The
        /// page never chats or speaks (live conversations run natively), so its own
        /// speech stays muted.
        static func pageConfigScript(clearCachedSettings: Bool) -> String {
            let defaults = UserDefaults.standard
            let name = javaScriptString(CharacterPack.resolveCharacterName())
            let avatar = javaScriptString(defaults.string(forKey: "selected_avatar") ?? "AvatarSample_A")
            var script = ""
            if clearCachedSettings {
                script += """
                try {
                    var keys = Object.keys(localStorage);
                    for (var i = 0; i < keys.length; i++) {
                        if (keys[i].startsWith('chatvrm_')) {
                            localStorage.removeItem(keys[i]);
                        }
                    }
                } catch(e) {}

                """
            }
            script += """
            try {
                localStorage.setItem('chatvrm_tts_muted', 'true');
                localStorage.setItem('chatvrm_rvc_enabled', 'false');
                localStorage.setItem('chatvrm_amica_life_enabled', 'false');
            } catch(e) {}
            window.__nativeConfig = {
                chatbot_backend: 'native_ios',
                tts_muted: 'true',
                rvc_enabled: 'false',
                amica_life_enabled: 'false',
                name: \(name),
                system_prompt: 'You are ' + \(name) + '.',
                vrm_url: '/vrm/' + \(avatar) + '.vrm'
            };
            window.__scowldVisionEnabled = true;
            """
            if clearCachedSettings {
                script += """

                // Force full screen coverage
                var meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
                document.head?.appendChild(meta);
                """
            }
            return script
        }

        /// A JavaScript string literal, so a custom name can't break out of it.
        static func javaScriptString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let array = String(data: data, encoding: .utf8) else { return "''" }
            return String(array.dropFirst().dropLast())
        }

        /// Reloads the page when her name or avatar changed; other settings don't affect it.
        private func pushUpdatedConfig() {
            let script = Self.pageConfigScript(clearCachedSettings: false)
            guard script != appliedPageConfig, let webView else { return }
            appliedPageConfig = script
            webView.configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
            webView.reload()
            logger.info("[Amica] Updated config script and reloaded WebView")
        }

        // MARK: Live conversation hooks

        func enqueueLipSync(_ chunk: LipSyncChunk) {
            guard isRuntimeActive, let webView, !chunk.levels.isEmpty else { return }
            let levels = chunk.levels.map { String(format: "%.3f", Double($0)) }.joined(separator: ",")
            let delay = Int((chunk.delay * 1000).rounded())
            let step = Int((chunk.step * 1000).rounded())
            webView.evaluateJavaScript("window.__scowldLip && window.__scowldLip.enqueue(\(delay), \(step), [\(levels)]);")
        }

        func stopLipSync() {
            webView?.evaluateJavaScript("window.__scowldLip && window.__scowldLip.clear();")
        }

        // MARK: Navigation

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
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.info("[Amica] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.info("[Amica] Provisional navigation failed: \(error.localizedDescription)")
        }

        /// Amica's `/share` page publishes avatars to Amica's online store. Scowld
        /// does not ship its code, because it bundled a JavaScript encryption
        /// library (see store/README.md, "Export compliance"), so the page is never
        /// opened. Its menu link ends here: when the page's code fails to load, the
        /// page's router falls back to a full navigation to `/share/`.
        static func isRemovedCompanionPage(_ url: URL?) -> Bool {
            guard let path = url?.path(percentEncoded: false) else { return false }
            return path == "/share" || path.hasPrefix("/share/")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if Self.isRemovedCompanionPage(navigationAction.request.url) {
                logger.info("[Amica] Blocked the removed share page")
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            // The companion page never needs the camera or microphone: Scowld
            // captures both natively during a live conversation.
            logger.info("[Amica] Refused the page's media capture request")
            decisionHandler(.deny)
        }

        func webView(_ webView: WKWebView,
                     contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                     completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
            completionHandler(nil)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            switch type {
            case "app_ready":
                logger.info("[Amica] App ready — preview hidden")
                NotificationCenter.default.post(name: .appReady, object: nil)
            case "console":
                let level = json["level"] as? String ?? "log"
                let msg = json["message"] as? String ?? ""
                logger.info("[Amica-JS] [\(level)] \(msg)")
                DebugLog.shared.add("[\(level)] \(msg)")
            default:
                break
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func scowldComposerGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Notification for Settings Changes

extension Notification.Name {
    static let amicaSettingsChanged = Notification.Name("amicaSettingsChanged")
    static let appReady = Notification.Name("appReady")
}
