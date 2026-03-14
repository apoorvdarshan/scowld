import UIKit

// MARK: - OpenAI Provider

/// OpenAI API provider (GPT-4o, GPT-4o-mini).
struct OpenAIProvider: LLMProvider {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
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
                // Last user message — attach image
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
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
