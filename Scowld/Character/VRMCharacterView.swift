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
        .background(.clear)
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

        let handler = context.coordinator
        config.userContentController.add(handler, name: "vrmEvent")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        // Allow loading local files
        if let htmlURL = Bundle.main.url(forResource: "vrm_viewer", withExtension: "html") {
            let resourceDir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
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

    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var isReady = false
        var isModelLoaded = false
        var currentModel: String?
        var pendingModel: String?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            Task { @MainActor in
                switch type {
                case "ready":
                    self.isReady = true
                    if let pending = self.pendingModel {
                        self.loadModel(pending)
                        self.pendingModel = nil
                    }
                case "loaded":
                    self.isModelLoaded = true
                case "error":
                    let msg = json["message"] as? String ?? "Unknown error"
                    print("[VRM] Error: \(msg)")
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
                webView.evaluateJavaScript("loadModel('\(urlString)')")
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
