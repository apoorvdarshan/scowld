import Foundation

// MARK: - Character Manager

/// Central character state manager. Combines inputs from ARKit, emotion engine,
/// lip sync, and user interaction to produce the final character animation state.
@Observable
final class CharacterManager {
    // MARK: - Character Identity
    var selectedCharacter: CharacterPack = {
        let savedId = UserDefaults.standard.string(forKey: "selectedCharacter") ?? "avatar_a"
        return CharacterPack.defaultPacks.first { $0.id == savedId } ?? CharacterPack.defaultPacks[0]
    }()

    // MARK: - Animation State
    var emotion: Emotion = .neutral
    var mouthOpenness: CGFloat = 0   // 0-1, for lip sync
    var pupilOffsetX: CGFloat = 0    // -1 to 1
    var pupilOffsetY: CGFloat = 0    // -1 to 1
    var headRotation: CGFloat = 0    // degrees, left/right
    var headTilt: CGFloat = 0        // degrees, up/down
    var isBlinking = false
    var bodyBounce: CGFloat = 0      // For excited/happy bouncing

    // MARK: - Sub-engines
    let emotionEngine = EmotionEngine()
    let lipSyncEngine = LipSyncEngine()

    // MARK: - Idle Animation
    private var idleTimer: Timer?
    private var blinkTimer: Timer?

    func startIdleAnimations() {
        // Random blinking every 2-5 seconds
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isBlinking = true
                try? await Task.sleep(for: .milliseconds(150))
                self.isBlinking = false
            }
        }

        // Subtle idle movement
        idleTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Gentle random eye movement when not tracking
                self.pupilOffsetX = CGFloat.random(in: -0.2...0.2)
                self.pupilOffsetY = CGFloat.random(in: -0.1...0.1)
            }
        }
    }

    func stopIdleAnimations() {
        idleTimer?.invalidate()
        blinkTimer?.invalidate()
        idleTimer = nil
        blinkTimer = nil
    }

    // MARK: - ARKit Face Tracking Updates

    /// Update character from ARKit face tracking data
    func updateFromFaceTracking(yaw: Float, pitch: Float, eyeX: Float, eyeY: Float) {
        // Mirror user's head rotation onto character
        headRotation = CGFloat(yaw) * 30 // Scale to degrees
        headTilt = CGFloat(pitch) * 20

        // Eyes follow user's gaze (inverted — owl looks where user looks)
        pupilOffsetX = CGFloat(eyeX)
        pupilOffsetY = CGFloat(eyeY)
    }

    // MARK: - Speech Updates

    /// Update lip sync from speech amplitude
    func updateFromSpeechAmplitude(_ amplitude: Float) {
        lipSyncEngine.updateFromAmplitude(amplitude)
        mouthOpenness = lipSyncEngine.mouthOpenness
    }

    // MARK: - Emotion Updates

    /// Process AI response, extract emotion, update character
    func processAIResponse(_ response: String) -> String {
        let (emotion, cleanText) = emotionEngine.parseResponse(response)
        emotionEngine.setEmotion(emotion)
        self.emotion = emotion

        // Add body bounce for excited/happy
        if emotion == .excited || emotion == .happy {
            bodyBounce = 1
            Task {
                try? await Task.sleep(for: .seconds(2))
                self.bodyBounce = 0
            }
        }

        return cleanText
    }
}
