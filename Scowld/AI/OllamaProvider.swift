import UIKit

// MARK: - Ollama Provider

/// Local Ollama API provider. Zero cost, runs entirely on user's machine.
/// Requires Ollama running at the configured URL (default: localhost:11434).
struct OllamaProvider: LLMProvider {
    let baseURL: String
    let model: String

    init(baseURL: String = OllamaConfig.defaultURL, model: String = "llama3.2") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.model = model
    }

    func generate(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        var apiMessages: [[String: String]] = [
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
            "stream": false,
        ]

        let data = try await performRequest(body: body)
        return try parseResponse(data: data)
    }

    func generateWithVision(messages: [ChatMessage], systemPrompt: String, image: UIImage) async throws -> String {
        // Ollama vision support is limited — fall back to text-only with a note
        var modifiedMessages = messages
        if let last = modifiedMessages.last, last.role == .user {
            modifiedMessages[modifiedMessages.count - 1] = ChatMessage(
                id: last.id,
                role: last.role,
                content: last.content + "\n(Note: Image was provided but Ollama doesn't support vision in this configuration)",
                emotion: last.emotion,
                timestamp: last.timestamp
            )
        }
        return try await generate(messages: modifiedMessages, systemPrompt: systemPrompt)
    }

    // MARK: - Private

    private func performRequest(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMError.networkError("Invalid Ollama URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // Ollama can be slow on first load
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.serverError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.invalidResponse
        }
        return content
    }
}
