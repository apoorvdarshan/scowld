import UIKit

// MARK: - Hosted Gemini Provider

/// Gemini provider routed through Scowld's hosted backend so API keys stay out of the app binary.
struct HostedGeminiProvider: LLMProvider {
    let model: String

    init(model: String = HostedServiceConfig.defaultGeminiModel) {
        self.model = model
    }

    func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        try await performRequest(messages: messages, systemPrompt: systemPrompt, imageBase64: nil)
    }

    func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw LLMError.invalidResponse
        }
        return try await performRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            imageBase64: imageData.base64EncodedString()
        )
    }

    private func performRequest(messages: [ChatMessage], systemPrompt: String, imageBase64: String?) async throws -> String {
        var request = URLRequest(url: HostedServiceConfig.chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(HostedChatRequest(
            model: model,
            messages: messages.map { HostedChatMessage(role: $0.role.rawValue, content: $0.content) },
            systemPrompt: systemPrompt,
            imageBase64: imageBase64
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if http.statusCode == 429 {
            throw LLMError.rateLimited
        }

        guard http.statusCode == 200 else {
            let error = (try? JSONDecoder().decode(HostedErrorResponse.self, from: data))?.message
                ?? String(data: data, encoding: .utf8)
                ?? "Hosted Gemini request failed."
            throw LLMError.serverError(http.statusCode, error)
        }

        let decoded = try JSONDecoder().decode(HostedChatResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LLMError.invalidResponse
        }
        return text
    }
}

private struct HostedChatRequest: Encodable {
    let model: String
    let messages: [HostedChatMessage]
    let systemPrompt: String
    let imageBase64: String?
}

private struct HostedChatMessage: Encodable {
    let role: String
    let content: String
}

private struct HostedChatResponse: Decodable {
    let text: String
    let model: String?
}

private struct HostedErrorResponse: Decodable {
    let error: String?
    let detail: String?

    var message: String? {
        detail ?? error
    }
}
