import UIKit

// MARK: - Claude Provider

/// Anthropic Claude API provider.
struct ClaudeProvider: LLMProvider {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "claude-haiku-4-5-20251001") {
        self.apiKey = apiKey
        self.model = model
    }

    func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        var apiMessages: [[String: Any]] = []

        for message in messages {
            apiMessages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.content,
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": apiMessages,
        ]

        let data = try await performRequest(body: body)
        return try parseResponse(data: data)
    }

    func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw LLMError.invalidResponse
        }
        let base64Image = imageData.base64EncodedString()

        var apiMessages: [[String: Any]] = []

        for (index, message) in messages.enumerated() {
            if index == messages.count - 1 && message.role == .user {
                // Last user message — attach image
                apiMessages.append([
                    "role": "user",
                    "content": [
                        ["type": "text", "text": message.content],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image,
                            ],
                        ],
                    ],
                ])
            } else {
                apiMessages.append([
                    "role": message.role == .user ? "user" : "assistant",
                    "content": message.content,
                ])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": apiMessages,
        ]

        let data = try await performRequest(body: body)
        return try parseResponse(data: data)
    }

    // MARK: - Private

    private func performRequest(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 429 { throw LLMError.rateLimited }
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String
        else {
            throw LLMError.invalidResponse
        }
        return text
    }
}
