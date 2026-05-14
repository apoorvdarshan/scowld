import Foundation

enum ElevenLabsVoicePreviewCache {
    static func isCached(voiceID: String) -> Bool {
        guard let url = try? fileURL(for: voiceID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func localAudioURL(voiceID: String, text: String) async throws -> URL {
        let fileURL = try fileURL(for: voiceID)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "voiceId": voiceID,
            "text": text,
            "model": HostedServiceConfig.defaultElevenLabsModel,
        ]
        var request = URLRequest(url: HostedServiceConfig.elevenLabsTTSURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ElevenLabsVoicePreviewError.downloadFailed(errorMessage(from: data))
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func fileURL(for voiceID: String) throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ElevenLabsVoicePreviewError.cacheUnavailable
        }
        return baseURL
            .appendingPathComponent("ElevenLabsVoicePreviews", isDirectory: true)
            .appendingPathComponent("\(sanitizedFileName(for: voiceID)).mp3")
    }

    private static func sanitizedFileName(for voiceID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return String(voiceID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "No response body" }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String {
                if let detail = json["detail"] as? String, !detail.isEmpty {
                    return "\(error): \(detail)"
                }
                return error
            }
            if let detail = json["detail"] as? String {
                return detail
            }
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}

enum ElevenLabsVoicePreviewError: LocalizedError {
    case cacheUnavailable
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .cacheUnavailable:
            "Local voice preview cache is unavailable."
        case .downloadFailed(let message):
            "Preview download failed: \(message)"
        }
    }
}
