import SwiftUI
import WebKit

// MARK: - Amica Character View

/// Embeds Amica's web-based VRM renderer in a WKWebView.
/// Bridges native Swift AI (LLM, TTS, STT) into Amica's character system.
struct VRMCharacterView: View {
    let emotion: Emotion
    let mouthOpenness: CGFloat
    let pupilOffsetX: CGFloat
    let pupilOffsetY: CGFloat
    let headRotation: CGFloat
    let isBlinking: Bool
    let bodyBounce: CGFloat
    let modelFileName: String
    @Binding var pendingGesture: String?

    var body: some View {
        AmicaWebView(
            emotion: emotion,
            mouthOpenness: mouthOpenness,
            pendingGesture: $pendingGesture
        )
    }
}

// MARK: - Amica WebView

struct AmicaWebView: UIViewRepresentable {
    let emotion: Emotion
    let mouthOpenness: CGFloat
    @Binding var pendingGesture: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "nativeAI")
        contentController.add(context.coordinator, name: "vrmEvent")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // Load Amica's index.html
        if let amicaDir = Bundle.main.url(forResource: "amica", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "amica/index", withExtension: "html") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: amicaDir)
        } else {
            print("[Amica] ERROR: amica/index.html not found in bundle")
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.isReady else { return }

        // Send gesture if pending
        if let gesture = pendingGesture {
            let animMap = [
                "wave": "greeting", "greeting": "greeting",
                "dance": "dance", "happy": "dance",
                "peace": "peaceSign", "pose": "modelPose",
                "spin": "spin", "squat": "squat"
            ]
            if let animName = animMap[gesture] {
                let js = "window.__amicaPlayAnimation && window.__amicaPlayAnimation('\(animName)')"
                webView.evaluateJavaScript(js)
            }
            Task { @MainActor in pendingGesture = nil }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false

        /// Called when Amica's native AI bridge sends a chat request
        var onChatRequest: ((_ callbackId: String, _ messages: [[String: String]]) -> Void)?

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[Amica] Page loaded")
            isReady = true
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
                // LLM request from Amica → forward to native AI
                guard let callbackId = json["callbackId"] as? String,
                      let messages = json["messages"] as? [[String: String]] else { return }
                print("[Amica] Chat request: \(callbackId)")
                onChatRequest?(callbackId, messages)
            default:
                print("[Amica] Message: \(type)")
            }
        }

        /// Send LLM response back to Amica
        func deliverResponse(callbackId: String, response: String) {
            let escaped = response
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            webView?.evaluateJavaScript("window.nativeAIResponse('\(callbackId)', '\(escaped)')")
        }

        func deliverError(callbackId: String, error: String) {
            let escaped = error.replacingOccurrences(of: "'", with: "\\'")
            webView?.evaluateJavaScript("window.nativeAIError('\(callbackId)', '\(escaped)')")
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var gesture: String? = nil
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
            modelFileName: "AvatarSample_A",
            pendingGesture: $gesture
        )
    }
}
