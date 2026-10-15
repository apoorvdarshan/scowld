import UIKit

// MARK: - Claude Provider

/// Anthropic Claude API provider.
struct ClaudeProvider: LLMProvider {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = AIProvider.claude.defaultModel) {
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

        let data = try await performRequest(body: requestBody(messages: apiMessages, systemPrompt: systemPrompt))
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

        let data = try await performRequest(body: requestBody(messages: apiMessages, systemPrompt: systemPrompt))
        return try parseResponse(data: data)
    }

    // MARK: - Request shape

    /// Models that accept `output_config.effort` (Claude Haiku 4.5 and Sonnet 4.5 reject it).
    private static let effortModelPrefixes = [
        "claude-fable-", "claude-mythos-", "claude-opus-5", "claude-sonnet-5", "claude-haiku-5",
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5", "claude-sonnet-4-6",
    ]

    /// Models that take server-side refusal fallbacks (`fallbacks: "default"`).
    private static let serverFallbackModels: Set = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]
    static let serverFallbackBeta = "server-side-fallback-2026-07-01"

    private var usesServerFallback: Bool { Self.serverFallbackModels.contains(model) }

    private func requestBody(messages: [[String: Any]], systemPrompt: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            // Current models think adaptively (Opus 5.5 always does) and those tokens
            // count toward max_tokens, so leave room beyond the short spoken reply.
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": messages,
        ]
        if Self.effortModelPrefixes.contains(where: model.hasPrefix) {
            // Spoken chat: low effort keeps replies fast (Opus 5.5 defaults to medium).
            body["output_config"] = ["effort": "low"]
        }
        if usesServerFallback {
            // A declined request is retried on a model chosen for that refusal category.
            body["fallbacks"] = "default"
        }
        return body
    }

    // MARK: - Private

    private func performRequest(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if usesServerFallback {
            request.setValue(Self.serverFallbackBeta, forHTTPHeaderField: "anthropic-beta")
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

    /// Joins the reply's text blocks. Thinking blocks (which come first on current
    /// models, with empty text by default) are skipped.
    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else {
            throw LLMError.invalidResponse
        }
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            if json["stop_reason"] as? String == "refusal" {
                throw LLMError.serverError(200, "Claude declined to answer that message.")
            }
            throw LLMError.invalidResponse
        }
        return text
    }
}
