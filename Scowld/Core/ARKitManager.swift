import ARKit

// MARK: - ARKit Manager

/// Manages ARKit face tracking using TrueDepth camera.
/// Drives character animations: eye movement, head rotation, expressions.
@Observable
final class ARKitManager: NSObject {
    // MARK: - Published State (drives character animations)
    var isTracking = false
    var headYaw: Float = 0      // -1 to 1, left/right head rotation
    var headPitch: Float = 0    // -1 to 1, up/down
    var headRoll: Float = 0     // -1 to 1, tilt

    // Eye tracking
    var leftEyeX: Float = 0    // -1 to 1
    var leftEyeY: Float = 0
    var rightEyeX: Float = 0
    var rightEyeY: Float = 0

    // Expression blend shapes
    var mouthOpen: Float = 0    // 0 to 1
    var mouthSmile: Float = 0
    var mouthFrown: Float = 0
    var browUp: Float = 0
    var browDown: Float = 0
    var eyeSquint: Float = 0
    var eyeWide: Float = 0
    var blinkLeft: Float = 0
    var blinkRight: Float = 0

    // MARK: - Private
    private var arSession: ARSession?

    // MARK: - Setup

    var isFaceTrackingSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    func startTracking() {
        guard isFaceTrackingSupported else { return }

        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1

        let session = ARSession()
        session.delegate = self
        session.run(configuration)
        arSession = session
        isTracking = true
    }

    func stopTracking() {
        arSession?.pause()
        arSession = nil
        isTracking = false
    }
}

// MARK: - ARSessionDelegate

extension ARKitManager: @preconcurrency ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        let blendShapes = faceAnchor.blendShapes
        let transform = faceAnchor.transform

        // Extract head rotation from transform matrix
        let yaw = atan2(transform.columns.0.z, transform.columns.2.z)
        let pitch = asin(-transform.columns.1.z)
        let roll = atan2(transform.columns.1.x, transform.columns.1.y)

        // Extract blend shape values
        let mouth = (blendShapes[.jawOpen]?.floatValue ?? 0)
        let smile = ((blendShapes[.mouthSmileLeft]?.floatValue ?? 0) + (blendShapes[.mouthSmileRight]?.floatValue ?? 0)) / 2
        let frown = ((blendShapes[.mouthFrownLeft]?.floatValue ?? 0) + (blendShapes[.mouthFrownRight]?.floatValue ?? 0)) / 2
        let browUpVal = ((blendShapes[.browOuterUpLeft]?.floatValue ?? 0) + (blendShapes[.browOuterUpRight]?.floatValue ?? 0)) / 2
        let browDownVal = ((blendShapes[.browDownLeft]?.floatValue ?? 0) + (blendShapes[.browDownRight]?.floatValue ?? 0)) / 2
        let squint = ((blendShapes[.eyeSquintLeft]?.floatValue ?? 0) + (blendShapes[.eyeSquintRight]?.floatValue ?? 0)) / 2
        let wide = ((blendShapes[.eyeWideLeft]?.floatValue ?? 0) + (blendShapes[.eyeWideRight]?.floatValue ?? 0)) / 2
        let blinkL = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let blinkR = blendShapes[.eyeBlinkRight]?.floatValue ?? 0

        // Eye look direction
        let eyeLX = blendShapes[.eyeLookOutLeft]?.floatValue ?? 0
        let eyeLInX = blendShapes[.eyeLookInLeft]?.floatValue ?? 0
        let eyeLY = (blendShapes[.eyeLookUpLeft]?.floatValue ?? 0) - (blendShapes[.eyeLookDownLeft]?.floatValue ?? 0)
        let eyeRX = blendShapes[.eyeLookOutRight]?.floatValue ?? 0
        let eyeRInX = blendShapes[.eyeLookInRight]?.floatValue ?? 0
        let eyeRY = (blendShapes[.eyeLookUpRight]?.floatValue ?? 0) - (blendShapes[.eyeLookDownRight]?.floatValue ?? 0)

        Task { @MainActor in
            self.headYaw = yaw
            self.headPitch = pitch
            self.headRoll = roll
            self.mouthOpen = mouth
            self.mouthSmile = smile
            self.mouthFrown = frown
            self.browUp = browUpVal
            self.browDown = browDownVal
            self.eyeSquint = squint
            self.eyeWide = wide
            self.blinkLeft = blinkL
            self.blinkRight = blinkR
            self.leftEyeX = eyeLInX - eyeLX
            self.leftEyeY = eyeLY
            self.rightEyeX = eyeRX - eyeRInX
            self.rightEyeY = eyeRY
        }
    }
}
