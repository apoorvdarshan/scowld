import Foundation

/// Asks a provider which live models an API key can use, so Settings can offer
/// more than the built-in list. A failure just leaves the built-in list.
nonisolated enum LiveModelCatalog {
    static func request(for provider: AIProvider, apiKey: String) -> URLRequest {
        switch provider {
        case .gemini:
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000"), URLQueryItem(name: "key", value: apiKey)]
            return URLRequest(url: components.url!)
        case .openai:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return request
        case .xai:
            var request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

    /// The live model IDs in a provider's model list.
    static func liveModels(in data: Data, for provider: AIProvider) -> [String] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let ids: [String]
        switch provider {
        case .gemini:
            // Live models are the ones that take the bidirectional (Live API) method.
            let models = json["models"] as? [[String: Any]] ?? []
            ids = models.compactMap { model in
                guard let name = model["name"] as? String,
                      (model["supportedGenerationMethods"] as? [String])?.contains("bidiGenerateContent") == true else { return nil }
                return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            }
        case .openai:
            let models = json["data"] as? [[String: Any]] ?? []
            ids = models.compactMap { $0["id"] as? String }
                .filter { $0.contains("realtime") && !$0.contains("transcri") && !$0.contains("translat") }
        case .xai:
            let models = (json["data"] ?? json["models"]) as? [[String: Any]] ?? []
            ids = models.compactMap { $0["id"] as? String }.filter { $0.hasPrefix("grok-voice") }
        }
        return Array(Set(ids)).sorted()
    }

    static func fetch(for provider: AIProvider, apiKey: String, session: URLSession = .shared) async throws -> [String] {
        let (data, response) = try await session.data(for: request(for: provider, apiKey: apiKey))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveSocketError.refused(statusCode: http.statusCode)
        }
        return liveModels(in: data, for: provider)
    }

    /// The built-in models first, then any others the key can use.
    static func merged(builtIn: [String], fetched: [String]) -> [String] {
        builtIn + fetched.filter { !builtIn.contains($0) }
    }
}
