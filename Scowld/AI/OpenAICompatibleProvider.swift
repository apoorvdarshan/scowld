import UIKit

// MARK: - OpenAI-Compatible Provider

/// Reusable provider for any API that follows the OpenAI /chat/completions format.
/// Works with OpenRouter, xAI, Together AI, Hugging Face, Venice AI, Moonshot, etc.
struct OpenAICompatibleProvider: LLMProvider {
    let baseURL: String
    let apiKey: String
    let model: String
    let extraHeaders: [String: String]

    init(baseURL: String, apiKey: String, model: String, extraHeaders: [String: String] = [:]) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.extraHeaders = extraHeaders
    }

    func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in messages {
            apiMessages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.content,
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.8,
            "max_tokens": 1024,
        ]

        let data = try await performRequest(body: body)
        return try parseResponse(data: data)
    }

    func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw LLMError.invalidResponse
        }
        let base64Image = imageData.base64EncodedString()

        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for (index, message) in messages.enumerated() {
            if index == messages.count - 1 && message.role == .user {
                apiMessages.append([
                    "role": "user",
                    "content": [
                        ["type": "text", "text": message.content],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]],
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
            "messages": apiMessages,
            "temperature": 0.8,
            "max_tokens": 1024,
        ]

        let data = try await performRequest(body: body)
        return try parseResponse(data: data)
    }

    // MARK: - Private

    private func performRequest(body: [String: Any]) async throws -> Data {
        let url = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

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
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.invalidResponse
        }
        return content
    }
}
