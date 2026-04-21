import UIKit

// MARK: - Gemini Provider

/// Google Gemini API provider. Uses the free tier (gemini-2.0-flash) by default.
/// API docs: https://ai.google.dev/api
struct GeminiProvider: LLMProvider {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "gemini-2.0-flash") {
        self.apiKey = apiKey
        self.model = model
    }

    func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var contents: [[String: Any]] = []

        // Add conversation messages
        for message in messages {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": message.content]],
            ])
        }

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "temperature": 0.8,
                "maxOutputTokens": 1024,
            ],
        ]

        let data = try await performRequest(url: url, body: body)
        return try parseResponse(data: data)
    }

    func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw LLMError.invalidResponse
        }
        let base64Image = imageData.base64EncodedString()

        // Build the last user message with image
        var contents: [[String: Any]] = []

        for (index, message) in messages.enumerated() {
            let role = message.role == .user ? "user" : "model"
            if index == messages.count - 1 && message.role == .user {
                // Last user message — attach image
                contents.append([
                    "role": role,
                    "parts": [
                        ["text": message.content],
                        ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]],
                    ],
                ])
            } else {
                contents.append([
                    "role": role,
                    "parts": [["text": message.content]],
                ])
            }
        }

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "temperature": 0.8,
                "maxOutputTokens": 1024,
            ],
        ]

        let data = try await performRequest(url: url, body: body)
        return try parseResponse(data: data)
    }

    // MARK: - Private

    private func performRequest(url: URL, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw LLMError.invalidResponse
        }
        return text
    }
}
