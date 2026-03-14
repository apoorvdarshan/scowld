import UIKit

// MARK: - LLM Provider Protocol

/// All AI providers conform to this protocol for text and vision generation.
protocol LLMProvider: Sendable {
    /// Generate a text response from the conversation history
    func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String

    /// Generate a response with an image attachment (for "what do you see" requests)
    func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String
}

// MARK: - Provider Errors

enum LLMError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(String)
    case rateLimited
    case invalidModel(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            "No API key configured. Add your key in Settings."
        case .invalidResponse:
            "Received an invalid response from the AI provider."
        case .networkError(let message):
            "Network error: \(message)"
        case .rateLimited:
            "Rate limited. Please wait a moment and try again."
        case .invalidModel(let model):
            "Invalid model: \(model)"
        case .serverError(let code, let message):
            "Server error (\(code)): \(message)"
        }
    }
}
