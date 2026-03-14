import Vision
import UIKit

// MARK: - Face Detector

/// Uses Apple Vision framework for on-device face and scene detection.
/// All processing is local — no images are sent to any API.
@Observable
final class FaceDetector {
    // MARK: - Published State
    var isFacePresent = false
    var faceExpression = "neutral"
    var gazeDirection = "forward"
    var sceneDescription = ""
    var lastAnalysisTime = Date.distantPast

    // MARK: - Private
    private let analysisInterval: TimeInterval = 5.0 // Analyze every 5 seconds

    // MARK: - Scene Analysis

    /// Analyze a camera frame to detect face and describe the scene.
    /// Returns a text description — image is NEVER sent to any API.
    func analyzeFrame(_ image: UIImage) async {
        // Throttle analysis to every 5 seconds
        guard Date().timeIntervalSince(lastAnalysisTime) >= analysisInterval else { return }
        lastAnalysisTime = Date()

        guard let cgImage = image.cgImage else { return }

        // Run face detection and classification in parallel
        async let faceResult = detectFace(in: cgImage)
        async let classifyResult = classifyScene(in: cgImage)

        let (faceInfo, sceneLabels) = await (faceResult, classifyResult)

        // Update face state
        isFacePresent = faceInfo.isPresent
        if isFacePresent {
            faceExpression = faceInfo.expression
            gazeDirection = faceInfo.gaze
        }

        // Build scene description text
        buildSceneDescription(faceInfo: faceInfo, sceneLabels: sceneLabels)
    }

    // MARK: - Face Detection

    private struct FaceInfo: Sendable {
        let isPresent: Bool
        let expression: String
        let gaze: String
        let yaw: CGFloat
        let pitch: CGFloat
    }

    nonisolated private func detectFace(in cgImage: CGImage) async -> FaceInfo {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let results = request.results, let face = results.first else {
                return FaceInfo(isPresent: false, expression: "neutral", gaze: "away", yaw: 0, pitch: 0)
            }

            let yaw = face.yaw?.doubleValue ?? 0
            let pitch = face.pitch?.doubleValue ?? 0

            // Determine gaze direction from head pose
            let gaze: String
            if abs(yaw) < 0.15 && abs(pitch) < 0.15 {
                gaze = "looking at camera"
            } else if yaw > 0.15 {
                gaze = "looking right"
            } else if yaw < -0.15 {
                gaze = "looking left"
            } else if pitch > 0.15 {
                gaze = "looking up"
            } else {
                gaze = "looking down"
            }

            // Simple expression detection from face landmarks
            let expression = detectExpression(from: face)

            return FaceInfo(isPresent: true, expression: expression, gaze: gaze, yaw: yaw, pitch: pitch)
        } catch {
            return FaceInfo(isPresent: false, expression: "neutral", gaze: "unknown", yaw: 0, pitch: 0)
        }
    }

    nonisolated private func detectExpression(from face: VNFaceObservation) -> String {
        // Use face landmarks to infer expression
        guard let landmarks = face.landmarks else { return "neutral" }

        // Check mouth shape for smile detection
        if let outerLips = landmarks.outerLips {
            let points = outerLips.normalizedPoints
            if points.count >= 6 {
                // Rough smile detection: corners of mouth higher than center bottom
                let leftCornerY = points[0].y
                let rightCornerY = points[points.count / 2].y
                let bottomY = points[points.count * 3 / 4].y

                if leftCornerY > bottomY + 0.02 && rightCornerY > bottomY + 0.02 {
                    return "smiling"
                }
            }
        }

        return "neutral"
    }

    // MARK: - Scene Classification

    nonisolated private func classifyScene(in cgImage: CGImage) async -> [String] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let results = request.results else { return [] }

            // Get top classifications with confidence > 0.3
            return results
                .filter { $0.confidence > 0.3 }
                .prefix(5)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        } catch {
            return []
        }
    }

    // MARK: - Description Builder

    private func buildSceneDescription(faceInfo: FaceInfo, sceneLabels: [String]) {
        var parts: [String] = []

        if faceInfo.isPresent {
            parts.append("User is present, \(faceInfo.gaze)")
            if faceInfo.expression != "neutral" {
                parts.append("appears to be \(faceInfo.expression)")
            }
        } else {
            parts.append("User is not visible")
        }

        if !sceneLabels.isEmpty {
            parts.append("Scene: \(sceneLabels.joined(separator: ", "))")
        }

        sceneDescription = parts.joined(separator: ". ") + "."
    }
}
