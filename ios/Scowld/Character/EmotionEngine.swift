import Foundation

// MARK: - Emotion Engine

/// Parses emotion tags from AI responses and manages emotion state transitions.
/// AI responses include tags like: [happy] Great idea! or [thinking] Hmm, let me consider...
@Observable
final class EmotionEngine {
    var currentEmotion: Emotion = .neutral
    var isTransitioning = false

    /// Parse an AI response to extract the emotion tag and clean text.
    /// Returns (emotion, cleanedText).
    func parseResponse(_ response: String) -> (emotion: Emotion, text: String) {
        // Match pattern: [emotion] rest of text
        let pattern = #"^\[(\w+)\]\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let tagRange = Range(match.range(at: 1), in: response)
        else {
            return (.neutral, response)
        }

        let tag = String(response[tagRange]).lowercased()
        let emotion = Emotion(rawValue: tag) ?? .neutral

        // Remove the tag from the response text
        let textStart = response.index(response.startIndex, offsetBy: match.range.length)
        let cleanText = String(response[textStart...]).trimmingCharacters(in: .whitespaces)

        return (emotion, cleanText)
    }

    /// Transition to a new emotion with animation
    func setEmotion(_ emotion: Emotion) {
        guard emotion != currentEmotion else { return }
        isTransitioning = true
        currentEmotion = emotion

        // Reset transition flag after animation completes
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            isTransitioning = false
        }
    }
}
