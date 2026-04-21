import Foundation

// MARK: - Lip Sync Engine

/// Drives mouth animations from audio amplitude during TTS playback.
/// Maps amplitude values to smooth mouth openness for character animation.
@Observable
final class LipSyncEngine {
    /// Current mouth openness (0 = closed, 1 = fully open)
    var mouthOpenness: CGFloat = 0

    /// Smoothing factor — higher = more responsive, lower = smoother
    private let smoothingFactor: CGFloat = 0.3

    /// Update mouth openness from raw audio amplitude.
    /// Called ~20 times/second during speech playback.
    func updateFromAmplitude(_ amplitude: Float) {
        let target = CGFloat(amplitude)
        // Exponential smoothing for natural-looking movement
        mouthOpenness = mouthOpenness + (target - mouthOpenness) * smoothingFactor
        // Clamp to valid range
        mouthOpenness = max(0, min(1, mouthOpenness))
    }

    /// Reset mouth to closed position
    func reset() {
        mouthOpenness = 0
    }
}
