import SwiftUI
import WebKit

// MARK: - VRM Character View

/// Renders a VRM 3D character using WKWebView + three-vrm.
/// Controlled via JavaScript bridge for emotions, lip sync, eye tracking, and head rotation.
struct VRMCharacterView: View {
    let emotion: Emotion
    let mouthOpenness: CGFloat
    let pupilOffsetX: CGFloat
    let pupilOffsetY: CGFloat
    let headRotation: CGFloat
    let isBlinking: Bool
    let bodyBounce: CGFloat
    let modelFileName: String

    var body: some View {
        VRMWebView(
            emotion: emotion,
            mouthOpenness: mouthOpenness,
            pupilOffsetX: pupilOffsetX,
            pupilOffsetY: pupilOffsetY,
            headRotation: headRotation,
            isBlinking: isBlinking,
            bodyBounce: bodyBounce,
            modelFileName: modelFileName
        )
    }
}

// MARK: - WKWebView Wrapper

struct VRMWebView: UIViewRepresentable {
    let emotion: Emotion
    let mouthOpenness: CGFloat
    let pupilOffsetX: CGFloat
    let pupilOffsetY: CGFloat
    let headRotation: CGFloat
    let isBlinking: Bool
    let bodyBounce: CGFloat
    let modelFileName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Allow file access for loading VRM models
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let contentController = config.userContentController

        // Forward console.log to Swift for debugging
        let consoleScript = WKUserScript(
            source: """
            (function() {
                var origLog = console.log;
                var origError = console.error;
                var origWarn = console.warn;
                function send(level, args) {
                    try {
                        window.webkit.messageHandlers.vrmEvent.postMessage(
                            JSON.stringify({ type: 'console', level: level, message: Array.from(args).map(String).join(' ') })
                        );
                    } catch(e) {}
                }
                console.log = function() { send('log', arguments); origLog.apply(console, arguments); };
                console.error = function() { send('error', arguments); origError.apply(console, arguments); };
                console.warn = function() { send('warn', arguments); origWarn.apply(console, arguments); };
                window.onerror = function(msg, url, line, col, err) {
                    send('error', ['JS Error: ' + msg + ' at ' + url + ':' + line]);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(consoleScript)
        contentController.add(context.coordinator, name: "vrmEvent")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // Load HTML with access to the entire bundle for VRM files
        if let htmlURL = Bundle.main.url(forResource: "vrm_viewer", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        } else {
            print("[VRM] ERROR: vrm_viewer.html not found in bundle")
        }

        context.coordinator.webView = webView
        context.coordinator.pendingModel = modelFileName
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Load model if changed
        if coordinator.currentModel != modelFileName {
            coordinator.loadModel(modelFileName)
        }

        // Only send updates after the viewer is ready and model is loaded
        guard coordinator.isReady, coordinator.isModelLoaded else { return }

        webView.evaluateJavaScript("setEmotion('\(emotion.rawValue)')")
        webView.evaluateJavaScript("setMouthOpenness(\(mouthOpenness))")
        webView.evaluateJavaScript("setBlink(\(isBlinking ? "true" : "false"))")
        webView.evaluateJavaScript("setEyeGaze(\(pupilOffsetX), \(pupilOffsetY))")
        webView.evaluateJavaScript("setHeadRotation(\(headRotation), 0)")
        webView.evaluateJavaScript("setBodyBounce(\(bodyBounce))")
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false
        var isModelLoaded = false
        var currentModel: String?
        var pendingModel: String?

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[VRM] HTML page loaded successfully")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[VRM] Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[VRM] Provisional navigation failed: \(error.localizedDescription)")
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            Task { @MainActor in
                switch type {
                case "ready":
                    print("[VRM] Viewer ready")
                    self.isReady = true
                    if let pending = self.pendingModel {
                        self.loadModel(pending)
                        self.pendingModel = nil
                    }
                case "loaded":
                    let model = json["model"] as? String ?? "unknown"
                    print("[VRM] Model loaded: \(model)")
                    self.isModelLoaded = true
                case "error":
                    let msg = json["message"] as? String ?? "Unknown error"
                    print("[VRM] Error: \(msg)")
                case "console":
                    let level = json["level"] as? String ?? "log"
                    let msg = json["message"] as? String ?? ""
                    print("[VRM-JS] [\(level)] \(msg)")
                default:
                    break
                }
            }
        }

        func loadModel(_ fileName: String) {
            guard isReady, let webView else {
                pendingModel = fileName
                return
            }
            currentModel = fileName
            isModelLoaded = false

            if let modelURL = Bundle.main.url(forResource: fileName, withExtension: "vrm") {
                let urlString = modelURL.absoluteString
                print("[VRM] Loading model: \(urlString)")
                webView.evaluateJavaScript("loadModel('\(urlString)')") { _, error in
                    if let error {
                        print("[VRM] JS eval error: \(error.localizedDescription)")
                    }
                }
            } else {
                print("[VRM] ERROR: \(fileName).vrm not found in bundle")
                // List what IS in the bundle for debugging
                if let resourcePath = Bundle.main.resourcePath {
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: resourcePath)) ?? []
                    let vrmFiles = files.filter { $0.hasSuffix(".vrm") }
                    print("[VRM] VRM files in bundle: \(vrmFiles)")
                    let htmlFiles = files.filter { $0.hasSuffix(".html") }
                    print("[VRM] HTML files in bundle: \(htmlFiles)")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        VRMCharacterView(
            emotion: .happy,
            mouthOpenness: 0.3,
            pupilOffsetX: 0,
            pupilOffsetY: 0,
            headRotation: 0,
            isBlinking: false,
            bodyBounce: 0,
            modelFileName: "AvatarSample_A"
        )
        .frame(width: 300, height: 400)
    }
}
